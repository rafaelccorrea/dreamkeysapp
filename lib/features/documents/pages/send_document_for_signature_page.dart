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
              foregroundColor: ThemeHelpers.textColor(ctx),
            ),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.status.success,
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
          ? const DocumentAccessLocked(
              message: 'Enviar documentos para assinatura exige a permissão '
                  'de criar documentos (document:create).',
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

  Widget _buildSkeleton() {
    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      children: const [
        SkeletonBox(width: 220, height: 22, borderRadius: 8),
        SizedBox(height: 16),
        SkeletonBox(width: double.infinity, height: 56, borderRadius: 12),
        SizedBox(height: 20),
        SkeletonBox(width: double.infinity, height: 260, borderRadius: 12),
      ],
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final doc = _document!;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final n = _signers.length;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + bottomInset),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              Row(
                children: [
                  Icon(Icons.description_outlined,
                      color: AppColors.primary.primary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      doc.title ?? doc.originalName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Adicione todos os signatários para este documento',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
              const SizedBox(height: 14),
              _notice(
                context,
                'Adicione todos os signatários agora. Após o envio, não será '
                'possível adicionar mais signatários.',
              ),
              for (var i = 0; i < _signers.length; i++)
                _signerSection(context, _signers[i], i),
              const SizedBox(height: 16),
              if (_signers.length < _maxSigners)
                OutlinedButton.icon(
                  onPressed: _sending ? null : _addSigner,
                  icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                  label: const Text('Adicionar signatário'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary.primary,
                    side: BorderSide(
                      color: AppColors.primary.primary.withValues(alpha: 0.5),
                    ),
                    minimumSize: const Size(double.infinity, 46),
                  ),
                )
              else
                _notice(context, 'Limite de 3 signatários por documento atingido'),
              const SizedBox(height: 24),
              _label(context, 'Data de expiração (opcional)'),
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
                            onPressed: () => setState(() => _expiresAt = null),
                          ),
                  ),
                  child: Text(
                    _expiresAt == null
                        ? 'Sem prazo'
                        : DateFormat('dd/MM/yyyy HH:mm').format(_expiresAt!),
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
              const SizedBox(height: 4),
              Text(
                'Aplicar a todos os signatários',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: _sendEmail,
                onChanged: _sending
                    ? null
                    : (v) => setState(() => _sendEmail = v ?? true),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: AppColors.primary.primary,
                title: Text(
                  'Enviar email automaticamente com link de assinatura para '
                  'todos os signatários',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
              ),
            ],
          ),
        ),
        // ── Barra de ações ─────────────────────────────────────────────
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
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: OutlinedButton(
                  onPressed: _sending ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ThemeHelpers.textColor(context),
                    side: BorderSide(color: ThemeHelpers.borderColor(context)),
                    minimumSize: const Size(0, 48),
                  ),
                  child: const Text('Cancelar'),
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
                  label: Text(
                    _sending
                        ? 'Enviando...'
                        : 'Enviar ($n signatário${n > 1 ? 's' : ''})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.status.success,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 48),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _signerSection(BuildContext context, _SignerDraft s, int index) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final filling = _fillingKey == s.key;

    return Padding(
      // Chave por signatário: ao remover um do meio, o estado dos campos
      // (tipo, seletor) não escorrega para o vizinho.
      key: ValueKey('signer-${s.key}'),
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Signatário ${index + 1}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
              ),
              if (_signers.length > 1)
                TextButton.icon(
                  onPressed: _sending ? null : () => _removeSigner(s),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Remover'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.status.error,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
          Divider(
            height: 12,
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.6),
          ),
          const SizedBox(height: 6),
          _label(context, 'Tipo de signatário *'),
          DropdownButtonFormField<SignerKind>(
            initialValue: s.kind,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true),
            items: SignerKind.values
                .map(
                  (k) => DropdownMenuItem(
                    value: k,
                    child: Text(
                      k.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: _sending
                ? null
                : (k) {
                    if (k != null) _changeKind(s, k);
                  },
          ),
          if (s.kind == SignerKind.client) ...[
            const SizedBox(height: 12),
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
            const SizedBox(height: 12),
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
            const SizedBox(height: 4),
            Text(
              'Lista apenas usuários com vínculo ativo nesta empresa.',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
          const SizedBox(height: 12),
          _label(context, 'Nome do signatário *'),
          TextField(
            controller: s.name,
            readOnly: s.locked,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Nome completo',
            ),
          ),
          const SizedBox(height: 12),
          _label(context, 'Email do signatário *'),
          TextField(
            controller: s.email,
            readOnly: s.locked,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'email@exemplo.com',
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final phone = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _label(context, 'Telefone'),
                  TextField(
                    controller: s.phone,
                    readOnly: s.locked,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [PhoneInputFormatter()],
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '(00) 00000-0000',
                    ),
                  ),
                ],
              );
              final cpf = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _label(context, 'CPF'),
                  TextField(
                    controller: s.cpf,
                    readOnly: s.locked,
                    keyboardType: TextInputType.number,
                    inputFormatters: [CpfInputFormatter()],
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '000.000.000-00',
                    ),
                  ),
                ],
              );
              if (c.maxWidth < 300) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [phone, const SizedBox(height: 12), cpf],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: phone),
                  const SizedBox(width: 10),
                  Expanded(child: cpf),
                ],
              );
            },
          ),
        ],
      ),
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

  Widget _notice(BuildContext context, String text) {
    final color = AppColors.status.warning;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textColor(context),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
