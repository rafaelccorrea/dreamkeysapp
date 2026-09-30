import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/utils/input_formatters.dart';
import '../../../shared/utils/masks.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../../clients/services/client_service.dart';
import '../models/document_model.dart';
import '../models/document_signature_model.dart';
import '../services/document_service.dart';
import '../utils/document_permissions.dart';
import '../widgets/document_access_locked.dart';
import '../widgets/document_signature_tile.dart';
import '../widgets/entity_selector.dart';

/// "Enviar para assinatura" — paridade com `SendDocumentForSignaturePage.tsx`.
///
/// Regras do web replicadas:
/// - até 3 signatários; pelo menos 1;
/// - tipo externo, cliente do sistema ou usuário ativo da empresa (cliente e
///   usuário preenchem nome, e-mail, telefone e CPF e travam os campos);
/// - nome e e-mail obrigatórios, e-mail válido, sem e-mail repetido na lista;
/// - bloqueia quem já tem assinatura válida (não expirada/cancelada) neste
///   documento;
/// - prazo opcional e futuro, aplicado a todos;
/// - "Enviar e-mail automaticamente" ligado por padrão;
/// - confirmação antes do envio (depois não dá para adicionar signatários);
/// - envio em lote (`POST /documents/:id/signatures/batch`).
///
/// Devolve `true` no `Navigator.pop` quando criou ao menos uma assinatura.
class SendDocumentForSignaturePage extends StatefulWidget {
  final String documentId;

  const SendDocumentForSignaturePage({super.key, required this.documentId});

  @override
  State<SendDocumentForSignaturePage> createState() =>
      _SendDocumentForSignaturePageState();
}

class _SignerDraft {
  final String key;
  SignerKind kind = SignerKind.external;
  String? clientId;
  String? clientName;
  String? userId;
  final TextEditingController name = TextEditingController();
  final TextEditingController email = TextEditingController();
  final TextEditingController phone = TextEditingController();
  final TextEditingController cpf = TextEditingController();

  _SignerDraft(this.key);

  bool get locked => kind != SignerKind.external;

  void clearFields() {
    name.clear();
    email.clear();
    phone.clear();
    cpf.clear();
  }

  void dispose() {
    name.dispose();
    email.dispose();
    phone.dispose();
    cpf.dispose();
  }
}

class _SendDocumentForSignaturePageState
    extends State<SendDocumentForSignaturePage> {
  static const int _maxSigners = 3;
  static final RegExp _emailRegex =
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  final DocumentService _service = DocumentService.instance;

  Document? _document;
  bool _loading = true;
  String? _error;
  int _errorStatus = 0;

  List<SignerUserOption> _users = [];
  List<DocumentSignature> _existing = [];

  final List<_SignerDraft> _signers = [];
  DateTime? _expiresAt;
  bool _sendEmail = true;
  bool _sending = false;
  String? _fillingKey;

  @override
  void initState() {
    super.initState();
    _signers.add(_SignerDraft('1'));
    ModuleAccessService.instance.addListener(_onAccessChanged);
    _load();
  }

  @override
  void dispose() {
    ModuleAccessService.instance.removeListener(_onAccessChanged);
    for (final s in _signers) {
      s.dispose();
    }
    super.dispose();
  }

  void _onAccessChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final docFuture = _service.getDocumentById(widget.documentId);
    final usersFuture = _service.getSignerUsers();
    final sigsFuture = _service.getDocumentSignatures(widget.documentId);
    final doc = await docFuture;
    final users = await usersFuture;
    final sigs = await sigsFuture;
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (doc.success && doc.data != null) {
        _document = doc.data;
      } else {
        _error = doc.message ?? 'Documento não encontrado';
        _errorStatus = doc.statusCode;
      }
      _users = users.data ?? const [];
      _existing = sigs.data ?? const [];
    });
  }

  void _snack(String text, {bool ok = false, bool warn = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: ok
            ? AppColors.status.success
            : (warn ? AppColors.status.warning : AppColors.status.error),
      ),
    );
  }

  // ─── Signatários ──────────────────────────────────────────────────────

  void _addSigner() {
    if (_signers.length >= _maxSigners) {
      _snack('Máximo de 3 signatários por documento', warn: true);
      return;
    }
    setState(() {
      _signers.add(_SignerDraft(DateTime.now().microsecondsSinceEpoch.toString()));
    });
  }

  void _removeSigner(_SignerDraft s) {
    if (_signers.length <= 1) {
      _snack('É necessário pelo menos um signatário');
      return;
    }
    setState(() => _signers.remove(s));
    s.dispose();
  }

  void _changeKind(_SignerDraft s, SignerKind kind) {
    if (s.kind == kind) return;
    setState(() {
      s.kind = kind;
      s.clientId = null;
      s.clientName = null;
      s.userId = null;
      s.clearFields();
    });
  }

  Future<void> _selectClient(_SignerDraft s, String id, String name) async {
    setState(() {
      s.clientId = id;
      s.clientName = name;
      s.name.text = name;
      _fillingKey = s.key;
    });
    final res = await ClientService.instance.getClientById(id);
    if (!mounted) return;
    setState(() {
      _fillingKey = null;
      if (res.success && res.data != null && s.clientId == id) {
        final c = res.data!;
        s.name.text = c.name;
        s.email.text = c.email;
        s.phone.text = c.phone.isEmpty ? '' : Masks.phone(c.phone);
        s.cpf.text = c.cpf.isEmpty ? '' : Masks.cpf(c.cpf);
      }
    });
    if (!res.success) {
      _snack(res.message ?? 'Erro ao carregar dados do cliente');
    }
  }

  void _selectUser(_SignerDraft s, String? userId) {
    final u = _users.where((e) => e.id == userId).toList();
    setState(() {
      s.userId = userId;
      if (u.isNotEmpty) {
        s.name.text = u.first.name;
        s.email.text = u.first.email;
        final phone = u.first.phone ?? '';
        s.phone.text = phone.isEmpty ? '' : Masks.phone(phone);
        s.cpf.clear();
      } else {
        s.clearFields();
      }
    });
  }

  // ─── Validação (espelho do validateSigner do web) ────────────────────

  bool _isEmail(String v) => _emailRegex.hasMatch(v.trim());

  bool get _isFormValid => _signers.every((s) {
        if (s.kind == SignerKind.client) return (s.clientId ?? '').isNotEmpty;
        if (s.kind == SignerKind.user) return (s.userId ?? '').isNotEmpty;
        return s.name.text.trim().isNotEmpty &&
            s.email.text.trim().isNotEmpty &&
            _isEmail(s.email.text);
      });

  bool _isLiveSignature(DocumentSignature sig) =>
      sig.status != DocumentSignatureStatus.expired &&
      sig.status != DocumentSignatureStatus.cancelled;

  String? _validateSigner(_SignerDraft s) {
    if (s.kind == SignerKind.client && (s.clientId ?? '').isEmpty) {
      return 'Cliente é obrigatório';
    }
    if (s.kind == SignerKind.user && (s.userId ?? '').isEmpty) {
      return 'Usuário é obrigatório';
    }
    if (s.name.text.trim().isEmpty) return 'Nome do signatário é obrigatório';
    if (s.email.text.trim().isEmpty) {
      return 'Email do signatário é obrigatório';
    }
    if (!_isEmail(s.email.text)) return 'Email inválido';

    final email = s.email.text.trim().toLowerCase();
    final dup = _signers.any(
      (o) => o.key != s.key && o.email.text.trim().toLowerCase() == email,
    );
    if (dup) return 'Este email já está na lista de signatários';

    DocumentSignature? existing;
    for (final sig in _existing) {
      if (!_isLiveSignature(sig)) continue;
      final match = s.kind == SignerKind.client
          ? sig.clientId == s.clientId
          : s.kind == SignerKind.user
              ? sig.userId == s.userId
              : (sig.signerEmail.toLowerCase() == email &&
                  (sig.clientId ?? '').isEmpty &&
                  (sig.userId ?? '').isEmpty);
      if (match) {
        existing = sig;
        break;
      }
    }
    if (existing != null) {
      return 'Já existe uma assinatura válida para ${existing.signerName}';
    }
    return null;
  }

  bool _validateAll() {
    for (final s in _signers) {
      final err = _validateSigner(s);
      if (err != null) {
        _snack(err);
        return false;
      }
    }
    if (_expiresAt != null && !_expiresAt!.isAfter(DateTime.now())) {
      _snack('Data de expiração deve ser futura');
      return false;
    }
    return true;
  }

  // ─── Envio ────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_document == null || _sending) return;
    if (!_validateAll()) return;

    final n = _signers.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: AppColors.status.warning,
          size: 36,
        ),
        title: const Text('Atenção!'),
        content: Text(
          'Após enviar este documento para assinatura, não será possível '
          'adicionar mais signatários.\n\nVocê está prestes a enviar para '
          '$n signatário${n > 1 ? 's' : ''}.\n\nDeseja continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              foregroundColor: ThemeHelpers.textSecondaryColor(ctx),
            ),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.status.success,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirmar e enviar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _sending = true);
    final signers = _signers.map((s) {
      final phone = s.phone.text.replaceAll(RegExp(r'\D'), '');
      final cpf = s.cpf.text.replaceAll(RegExp(r'\D'), '');
      return SignatureSignerInput(
        clientId: s.kind == SignerKind.client ? s.clientId : null,
        userId: s.kind == SignerKind.user ? s.userId : null,
        signerName: s.name.text.trim(),
        signerEmail: s.email.text.trim(),
        signerPhone: phone.isEmpty ? null : phone,
        signerCpf: cpf.isEmpty ? null : cpf,
      );
    }).toList();

    final res = await _service.createSignaturesBatch(
      documentId: widget.documentId,
      signers: signers,
      expiresAt: _expiresAt,
      sendEmail: _sendEmail,
    );
    if (!mounted) return;
    setState(() => _sending = false);

    if (!res.success || res.data == null) {
      _snack(res.message ?? 'Erro ao enviar documento para assinatura');
      return;
    }
    final result = res.data!;
    if (result.success > 0) {
      final extra = result.errors.isEmpty
          ? ''
          : ' Avisos: ${result.errors.join(' | ')}';
      _snack(
        '${result.success} assinatura(s) criada(s) com sucesso!$extra',
        ok: result.errors.isEmpty,
        warn: result.errors.isNotEmpty,
      );
      Navigator.of(context).pop(true);
    } else {
      _snack(
        result.errors.isNotEmpty
            ? result.errors.join(' | ')
            : 'Nenhuma assinatura foi criada. Verifique os dados.',
      );
    }
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final initial = _expiresAt ?? now.add(const Duration(days: 7));
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
      helpText: 'Data de expiração',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'Horário de expiração',
    );
    if (!mounted) return;
    final t = time ?? const TimeOfDay(hour: 23, minute: 59);
    setState(() {
      _expiresAt = DateTime(date.year, date.month, date.day, t.hour, t.minute);
    });
  }

  // ─── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final allowed =
        DocumentPermissions.moduleEnabled && DocumentPermissions.canCreate;
    return AppScaffold(
      title: 'Enviar para assinatura',
      showBottomNavigation: false,
      body: !allowed
          ? DocumentAccessLocked(
              message: DocumentPermissions.moduleEnabled
                  ? 'Enviar documentos para assinatura exige a permissão '
                      'de criar documentos.'
                  : 'O módulo de documentos não está ativo nesta empresa.',
            )
          : _loading
              ? _buildSkeleton()
              : _error != null
                  ? AppErrorState.fromApi(
                      message: _error,
                      statusCode: _errorStatus,
                      onRetry: _load,
                    )
                  : _buildForm(context),
    );
  }

  /// Esqueleto fiel ao formulário: documento, aviso, um signatário e o
  /// botão de adicionar.
  Widget _buildSkeleton() {
    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      children: const [
        Row(
          children: [
            SkeletonBox(width: 44, height: 44, borderRadius: 12),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonText(width: 220, height: 16),
                  SizedBox(height: 8),
                  SkeletonText(width: 130, height: 12),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        SkeletonBox(width: double.infinity, height: 52, borderRadius: 12),
        SizedBox(height: 24),
        SkeletonText(width: 120, height: 11),
        SizedBox(height: 14),
        SkeletonBox(width: double.infinity, height: 300, borderRadius: 14),
        SizedBox(height: 12),
        SkeletonBox(width: double.infinity, height: 56, borderRadius: 12),
      ],
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final doc = _document!;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final n = _signers.length;

    return LayoutBuilder(
      builder: (context, c) {
        // Tela baixa (paisagem, ou teclado aberto em aparelho pequeno): a
        // barra de envio deixa de ser fixa e vai para o fim da rolagem, para
        // o campo em edição não ficar espremido. O Expanded da lista segue
        // sendo o mesmo elemento, então o campo não perde o foco.
        final inline = c.maxHeight < 320;
        // Tablet: o formulário fica numa coluna de até 760, centralizada.
        final hPad = c.maxWidth > 792 ? (c.maxWidth - 760) / 2 : 16.0;
        return Column(
          children: [
            Expanded(
              child: ListView(
                padding:
                    EdgeInsets.fromLTRB(hPad, 16, hPad, 24 + bottomInset),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  _docHeader(context, doc),
                  const SizedBox(height: 14),
                  _notice(
                    context,
                    'Adicione todos os signatários agora: depois do envio não '
                    'dá para incluir mais ninguém neste documento.',
                  ),
                  if (_existing.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    _existingBlock(context),
                  ],
                  const SizedBox(height: 22),
                  _band(
                    context,
                    'SIGNATÁRIOS',
                    Icons.groups_outlined,
                    trailing: '$n de $_maxSigners',
                  ),
                  for (var i = 0; i < _signers.length; i++)
                    _signerSection(context, _signers[i], i),
                  _addSignerButton(context),
                  const SizedBox(height: 26),
                  _band(context, 'PRAZO E AVISO', Icons.event_outlined),
                  _label(context, 'Prazo para assinar (opcional)'),
                  InkWell(
                    onTap: _sending ? null : _pickExpiry,
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.event_outlined, size: 20),
                        suffixIcon: _expiresAt == null
                            ? const Icon(Icons.arrow_drop_down)
                            : IconButton(
                                tooltip: 'Remover prazo',
                                icon: const Icon(Icons.close_rounded, size: 18),
                                onPressed: _sending
                                    ? null
                                    : () => setState(() => _expiresAt = null),
                              ),
                      ),
                      child: Text(
                        _expiresAt == null
                            ? 'Sem prazo'
                            : DateFormat("dd/MM/yyyy 'às' HH:mm")
                                .format(_expiresAt!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: _expiresAt == null
                              ? muted
                              : ThemeHelpers.textColor(context),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _expiryHelp(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: muted,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _emailSwitch(context),
                  if (inline) ...[
                    const SizedBox(height: 24),
                    _actionBar(context),
                  ],
                ],
              ),
            ),
            // ── Barra de ações ─────────────────────────────────────────
            if (!inline)
              Container(
                padding: EdgeInsets.fromLTRB(
                  16,
                  10,
                  16,
                  10 + MediaQuery.of(context).padding.bottom,
                ),
                decoration: BoxDecoration(
                  color: ThemeHelpers.cardBackgroundColor(context),
                  border: Border(
                    top: BorderSide(color: ThemeHelpers.borderColor(context)),
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: _actionBar(context),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Qual documento sai para assinatura: título, tipo/arquivo e o vínculo
  /// (cliente ou imóvel) — o que evita voltar para conferir.
  Widget _docHeader(BuildContext context, Document doc) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final titulo = (doc.title ?? '').trim().isNotEmpty
        ? doc.title!.trim()
        : (doc.originalName.trim().isNotEmpty
            ? doc.originalName.trim()
            : 'Documento');
    final ext = doc.fileExtension.replaceAll('.', '').trim().toUpperCase();
    final tipo = [doc.type.label, if (ext.isNotEmpty) ext].join(' · ');
    final cliente = doc.client?.name.trim() ?? '';
    final imovel = doc.property?.title.trim() ?? '';
    final vinculo = cliente.isNotEmpty
        ? 'Cliente: $cliente'
        : (imovel.isNotEmpty ? 'Imóvel: $imovel' : null);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: isDark ? 0.18 : 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.description_outlined, color: accent, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: ThemeHelpers.textColor(context),
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                tipo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (vinculo != null)
                Text(
                  vinculo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Quem já recebeu este documento — explica, antes do erro no envio, por
  /// que alguém não entra de novo (mesma regra de `_isLiveSignature`).
  Widget _existingBlock(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final texto = ThemeHelpers.textColor(context);
    final vivas = _existing.where(_isLiveSignature).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _band(
          context,
          'JÁ ENVIADO NESTE DOCUMENTO',
          Icons.history_rounded,
          trailing: '${_existing.length}',
        ),
        Text(
          vivas > 0
              ? 'Quem já tem assinatura em andamento, assinada ou rejeitada '
                  'aqui não entra de novo. Expiradas e canceladas podem ser '
                  'reenviadas.'
              : 'Todas expiraram ou foram canceladas: dá para incluir essas '
                  'pessoas de novo.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: muted,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < _existing.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: i == 0
                ? null
                : BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: ThemeHelpers.borderLightColor(context),
                      ),
                    ),
                  ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: signatureStatusColor(context, _existing[i].status),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _existing[i].signerName.trim().isEmpty
                            ? 'Signatário sem nome'
                            : _existing[i].signerName.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          // Expiradas/canceladas não barram ninguém: apagadas.
                          color: _isLiveSignature(_existing[i]) ? texto : muted,
                        ),
                      ),
                      if (_existing[i].signerEmail.trim().isNotEmpty)
                        Text(
                          _existing[i].signerEmail.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: muted),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 110),
                  child: Text(
                    _existing[i].status.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: texto,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Cabeçalho de seção: ícone, rótulo em caixa alta, contagem à direita e
  /// o filete de ponta a ponta embaixo.
  Widget _band(
    BuildContext context,
    String title,
    IconData icon, {
    String? trailing,
  }) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: muted),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.3,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 10),
                Text(
                  trailing,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: muted,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 7),
          Container(
            height: 1,
            color: ThemeHelpers.borderLightColor(context),
          ),
        ],
      ),
    );
  }

  /// Bloco de um signatário: número (vira ✓ quando está pronto), nome ao
  /// vivo, tipo em três segmentos, campos e o que falta no rodapé.
  Widget _signerSection(BuildContext context, _SignerDraft s, int index) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final texto = ThemeHelpers.textColor(context);
    final filling = _fillingKey == s.key;
    final nome = s.name.text.trim();
    final pronto = _signerHint(s) == null;
    final green =
        isDark ? AppColors.status.successDarkMode : AppColors.status.success;
    // Cliente e usuário preenchem os campos e travam: o cadeado diz isso.
    final travado = s.locked
        ? Icon(Icons.lock_outline_rounded, size: 16, color: muted)
        : null;
    final estiloTravado = s.locked ? TextStyle(color: muted) : null;

    return Container(
      // Chave por signatário: ao remover um do meio, o estado dos campos
      // (tipo, seletor) não escorrega para o vizinho.
      key: ValueKey('signer-${s.key}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ThemeHelpers.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: pronto ? green : texto.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: pronto
                    ? const Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: Colors.white,
                      )
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: texto,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome.isEmpty ? 'Signatário ${index + 1}' : nome,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: texto,
                      ),
                    ),
                    Text(
                      nome.isEmpty
                          ? s.kind.label
                          : 'Signatário ${index + 1} · ${s.kind.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (_signers.length > 1)
                TextButton.icon(
                  onPressed: _sending ? null : () => _removeSigner(s),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Remover'),
                  style: TextButton.styleFrom(
                    foregroundColor: isDark
                        ? AppColors.status.errorDarkMode
                        : AppColors.status.error,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _kindSelector(context, s),
          const SizedBox(height: 6),
          Text(
            _kindHelp(s.kind),
            style: theme.textTheme.bodySmall?.copyWith(
              color: muted,
              height: 1.35,
            ),
          ),
          if (s.kind == SignerKind.client) ...[
            const SizedBox(height: 14),
            _label(context, 'Cliente *'),
            EntitySelector(
              key: ValueKey('client-${s.key}'),
              type: 'client',
              selectedId: s.clientId,
              selectedName: s.clientName,
              floatingLabel: false,
              placeholder: 'Selecione um cliente',
              onSelected: (id, name) => _selectClient(s, id, name),
            ),
            if (filling) ...[
              const SizedBox(height: 6),
              const LinearProgressIndicator(minHeight: 2),
            ],
          ],
          if (s.kind == SignerKind.user) ...[
            const SizedBox(height: 14),
            _label(context, 'Usuário ativo na empresa *'),
            DropdownButtonFormField<String>(
              key: ValueKey('user-${s.key}'),
              initialValue: s.userId,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Selecione um usuário ativo',
              ),
              items: _users
                  .map(
                    (u) => DropdownMenuItem(
                      value: u.id,
                      child: Text(
                        u.email.isEmpty ? u.name : '${u.name} (${u.email})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _sending ? null : (v) => _selectUser(s, v),
            ),
            if (_users.isEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Nenhum usuário ativo encontrado nesta empresa.',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
          ],
          const SizedBox(height: 14),
          _pair(
            minWidth: 520,
            left: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _label(context, 'Nome do signatário *'),
                TextField(
                  controller: s.name,
                  readOnly: s.locked,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                  style: estiloTravado,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Nome completo',
                    suffixIcon: travado,
                  ),
                ),
              ],
            ),
            right: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _label(context, 'E-mail do signatário *'),
                TextField(
                  controller: s.email,
                  readOnly: s.locked,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                  style: estiloTravado,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'email@exemplo.com',
                    suffixIcon: travado,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _pair(
            minWidth: 360,
            left: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _label(context, 'Telefone'),
                TextField(
                  controller: s.phone,
                  readOnly: s.locked,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [PhoneInputFormatter()],
                  style: estiloTravado,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '(00) 00000-0000',
                    suffixIcon: travado,
                  ),
                ),
              ],
            ),
            right: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _label(context, 'CPF'),
                TextField(
                  controller: s.cpf,
                  readOnly: s.locked,
                  keyboardType: TextInputType.number,
                  inputFormatters: [CpfInputFormatter()],
                  style: estiloTravado,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '000.000.000-00',
                    suffixIcon: travado,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _signerStatus(context, s),
        ],
      ),
    );
  }

  /// Tipo do signatário em três segmentos (tudo à vista, um toque): mesmo
  /// fundo e borda dos campos; o escolhido sobe em cartão.
  Widget _kindSelector(BuildContext context, _SignerDraft s) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final texto = ThemeHelpers.textColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final trilho = theme.inputDecorationTheme.fillColor ??
        ThemeHelpers.backgroundColor(context);

    Widget opcao(SignerKind k, IconData icon, String rotulo) {
      final sel = s.kind == k;
      return Expanded(
        child: Semantics(
          selected: sel,
          child: Material(
            color: sel
                ? (isDark
                    ? texto.withValues(alpha: 0.12)
                    : ThemeHelpers.cardBackgroundColor(context))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            child: InkWell(
              onTap: _sending ? null : () => _changeKind(s, k),
              borderRadius: BorderRadius.circular(9),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: sel
                        ? ThemeHelpers.borderColor(context)
                        : Colors.transparent,
                  ),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 16, color: sel ? texto : muted),
                      const SizedBox(width: 6),
                      Text(
                        rotulo,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              sel ? FontWeight.w800 : FontWeight.w600,
                          color: sel ? texto : muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: trilho,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ThemeHelpers.borderColor(context),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          opcao(SignerKind.external, Icons.person_outline_rounded, 'Externo'),
          const SizedBox(width: 3),
          opcao(SignerKind.client, Icons.badge_outlined, 'Cliente'),
          const SizedBox(width: 3),
          opcao(SignerKind.user, Icons.groups_outlined, 'Usuário'),
        ],
      ),
    );
  }

  static String _kindHelp(SignerKind k) => switch (k) {
        SignerKind.external =>
          'Alguém de fora do sistema: preencha nome e e-mail.',
        SignerKind.client => 'Um cliente do cadastro: nome, e-mail, telefone '
            'e CPF vêm da ficha dele.',
        SignerKind.user => 'Alguém da equipe com vínculo ativo nesta '
            'empresa: os dados vêm do perfil.',
      };

  /// O que falta neste signatário, na voz de pendência ("Falta o e-mail."),
  /// ou `null` quando está pronto. Os bloqueios de verdade (e-mail repetido,
  /// já tem assinatura aqui) vêm da própria validação do envio.
  String? _signerHint(_SignerDraft s) {
    if (_fillingKey == s.key) return 'Buscando os dados do cliente…';
    final erro = _validateSigner(s);
    if (erro == null) return null;
    final faltam = <String>[
      if (s.kind == SignerKind.client && (s.clientId ?? '').isEmpty)
        'escolher o cliente',
      if (s.kind == SignerKind.user && (s.userId ?? '').isEmpty)
        'escolher o usuário',
      if (!s.locked && s.name.text.trim().isEmpty) 'o nome',
      if (!s.locked && s.email.text.trim().isEmpty) 'o e-mail',
    ];
    if (faltam.isNotEmpty) return 'Falta ${faltam.join(' e ')}.';
    if (s.locked && s.email.text.trim().isEmpty) {
      return s.kind == SignerKind.client
          ? 'O cadastro deste cliente está sem e-mail. Complete a ficha do '
              'cliente ou envie como Externo.'
          : 'Este usuário está sem e-mail no perfil.';
    }
    return erro;
  }

  Widget _signerStatus(BuildContext context, _SignerDraft s) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final pendencia = _signerHint(s);
    final pronto = pendencia == null;
    final cor = pronto
        ? (isDark ? AppColors.status.successDarkMode : AppColors.status.success)
        : (isDark
            ? AppColors.status.warningDarkMode
            : AppColors.status.warning);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          pronto ? Icons.check_circle_rounded : Icons.error_outline_rounded,
          size: 16,
          color: cor,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            pendencia ?? 'Pronto para envio',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.35,
              color: pronto
                  ? ThemeHelpers.textSecondaryColor(context)
                  : ThemeHelpers.textColor(context),
            ),
          ),
        ),
      ],
    );
  }

  /// Dois campos lado a lado quando cabem; empilhados em tela estreita.
  Widget _pair({
    required Widget left,
    required Widget right,
    required double minWidth,
  }) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < minWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, const SizedBox(height: 12), right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 12),
            Expanded(child: right),
          ],
        );
      },
    );
  }

  /// "Adicionar signatário" à vista, com quantos ainda cabem; no limite,
  /// fica travado com o cadeado e o motivo (no lugar de sumir).
  Widget _addSignerButton(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final restam = _maxSigners - _signers.length;
    if (restam <= 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ThemeHelpers.borderColor(context)),
        ),
        child: Row(
          children: [
            Icon(Icons.lock_outline_rounded, size: 18, color: muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Limite de $_maxSigners signatários por documento atingido.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    return Material(
      color: accent.withValues(alpha: isDark ? 0.14 : 0.07),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _sending ? null : _addSigner,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              Icon(Icons.person_add_alt_1_outlined, size: 20, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Adicionar signatário',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                    Text(
                      restam == 1
                          ? 'Ainda cabe 1 · máximo de $_maxSigners por '
                              'documento'
                          : 'Ainda cabem $restam · máximo de $_maxSigners '
                              'por documento',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.add_rounded, size: 20, color: accent),
            ],
          ),
        ),
      ),
    );
  }

  String _expiryHelp() {
    final e = _expiresAt;
    if (e == null) return 'Vale para todos os signatários.';
    final agora = DateTime.now();
    if (!e.isAfter(agora)) {
      return 'Esse horário já passou: escolha um prazo no futuro.';
    }
    final dias = (DateTime(e.year, e.month, e.day)
                .difference(DateTime(agora.year, agora.month, agora.day))
                .inHours /
            24)
        .round();
    final quando = dias <= 0
        ? 'vence hoje'
        : (dias == 1 ? 'vence amanhã' : 'vence em $dias dias');
    return 'Vale para todos os signatários · $quando.';
  }

  /// Linha do e-mail automático: título + o que acontece em cada posição.
  /// A linha inteira alterna (alvo de toque maior que o Switch).
  Widget _emailSwitch(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final green =
        isDark ? AppColors.status.successDarkMode : AppColors.status.success;
    return InkWell(
      onTap: _sending ? null : () => setState(() => _sendEmail = !_sendEmail),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enviar o link por e-mail agora',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _sendEmail
                        ? 'Cada signatário recebe o link de assinatura no '
                            'e-mail assim que você enviar.'
                        : 'Ninguém recebe e-mail agora. Depois dá para enviar '
                            'pela tela de Assinaturas ou copiar o link.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Switch(
              value: _sendEmail,
              onChanged:
                  _sending ? null : (v) => setState(() => _sendEmail = v),
              activeThumbColor: Colors.white,
              activeTrackColor: green,
            ),
          ],
        ),
      ),
    );
  }

  /// Resumo do que vai sair + Cancelar/Enviar. Quando o "Enviar" está
  /// travado, o resumo diz qual signatário conferir.
  Widget _actionBar(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final green =
        isDark ? AppColors.status.successDarkMode : AppColors.status.success;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final n = _signers.length;
    final pessoas = '$n ${n == 1 ? 'signatário' : 'signatários'}';
    final pendentes = <int>[
      for (var i = 0; i < _signers.length; i++)
        if (_signerHint(_signers[i]) != null) i + 1,
    ];
    final pronto = pendentes.isEmpty;
    final String resumo;
    if (_sending) {
      resumo = 'Enviando para $pessoas…';
    } else if (!pronto) {
      final quais = pendentes.length == 1
          ? 'o signatário ${pendentes.first}'
          : 'os signatários '
              '${pendentes.sublist(0, pendentes.length - 1).join(', ')} '
              'e ${pendentes.last}';
      resumo = 'Confira $quais antes de enviar';
    } else {
      resumo = [
        pessoas,
        _sendEmail ? 'link por e-mail' : 'sem e-mail agora',
        if (_expiresAt != null)
          'prazo ${DateFormat('dd/MM').format(_expiresAt!)}',
      ].join(' · ');
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _sending
                  ? Icons.schedule_rounded
                  : (pronto
                      ? Icons.check_circle_rounded
                      : Icons.error_outline_rounded),
              size: 16,
              color: pronto ? green : amber,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                resumo,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: pronto
                      ? ThemeHelpers.textSecondaryColor(context)
                      : ThemeHelpers.textColor(context),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: OutlinedButton(
                onPressed: _sending ? null : () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ThemeHelpers.textColor(context),
                  side: BorderSide(color: ThemeHelpers.borderColor(context)),
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Cancelar', maxLines: 1, softWrap: false),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: FilledButton.icon(
                onPressed: _sending || !_isFormValid ? null : _submit,
                icon: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _sending ? 'Enviando…' : 'Enviar',
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.status.success,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _label(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: ThemeHelpers.textColor(context),
            ),
      ),
    );
  }

  /// Aviso em faixa tonal (sem filete lateral): disco âmbar com o ícone
  /// escuro — legível nos dois temas — e o texto na cor do texto.
  Widget _notice(BuildContext context, String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.14 : 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(
              Icons.priority_high_rounded,
              size: 14,
              color: AppColors.text.text,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textColor(context),
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
