import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/sale_forms_service.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/skeleton_box.dart';
import 'sale_form_row_actions.dart' show showSaleFormPdfSheet;
import 'sale_form_tones.dart';

/// Bottom sheet de assinaturas da FICHA DE VENDA — paridade com
/// `SaleFormSignatureModalPrivate.tsx` (web).
///
/// O documento nasce no Autentique com envio por LINK (o Autentique não
/// dispara nada). Quem distribui o link somos nós: por e-mail (automático na
/// criação, reenviável aqui), pelo WhatsApp da empresa ou manualmente.
///
/// Mesma lógica de abas do web:
///  - nada enviado → só o formulário de envio;
///  - enviado e ninguém assinou → abas **Status** e **Novo envio** (novo envio
///    cancela os links pendentes);
///  - alguém já assinou → só o **Status**.
///
/// Linhas do usuário logado ("você") ganham o botão **Assinar**, que abre o
/// link do Autentique fora do app — o mesmo fluxo de quem assina pelo web.
///
/// [canInvalidate]: `null` (padrão) = regra do web calculada aqui com os dados
/// da própria ficha (`canInvalidateSignatures`, status, assinaturas ativas e
/// `sale_form:update`); `false` esconde o "Cancelar todas" de qualquer jeito.
Future<void> showSaleFormSignaturesSheet(
  BuildContext context, {
  required String saleFormId,
  String? formNumber,
  bool? canInvalidate,
  VoidCallback? onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    builder: (ctx) => _SaleFormSignaturesSheet(
      saleFormId: saleFormId,
      formNumber: formNumber,
      canInvalidate: canInvalidate,
      onChanged: onChanged,
    ),
  );
}

class _SaleFormSignaturesSheet extends StatefulWidget {
  const _SaleFormSignaturesSheet({
    required this.saleFormId,
    required this.formNumber,
    required this.canInvalidate,
    this.onChanged,
  });

  final String saleFormId;
  final String? formNumber;
  final bool? canInvalidate;
  final VoidCallback? onChanged;

  @override
  State<_SaleFormSignaturesSheet> createState() =>
      _SaleFormSignaturesSheetState();
}

class _SaleFormSignaturesSheetState extends State<_SaleFormSignaturesSheet>
    with SingleTickerProviderStateMixin {
  static const int _tabStatus = 0;
  static const int _tabEnvio = 1;

  late final TabController _tab;
  bool _loading = true;
  bool _primeiraCarga = true;
  String? _error;
  int _errorStatus = 0;
  bool _sending = false;
  bool _syncing = false;
  bool _invalidating = false;
  bool _resendingEmail = false;
  bool _resendingWa = false;
  String? _emailingSigId;
  String? _linkBusyId;
  String? _pdfBusy;

  SaleForm? _form;
  List<SaleFormSignature> _signatures = const [];
  List<SaleFormSignerPreview> _autoSigners = const [];
  SaleFormWhatsappEnvio? _whatsapp;
  SaleFormEmailEnvio? _ultimoEmail;

  late final TextEditingController _docName;
  late final TextEditingController _docMessage;
  bool _docNameTouched = false;
  final List<_SignerForm> _forms = [];
  bool _extrasExpanded = false;
  bool _prefilled = false;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _accent =>
      _isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
  // Tons de texto/ícone (legíveis também no modo claro) — `sale_form_tones`.
  Color get _green => SaleFormTom.sucesso(context).texto;
  Color get _warn => SaleFormTom.aviso(context).texto;
  Color get _red => SaleFormTom.erro(context).texto;
  Color get _blue => SaleFormTom.info(context).texto;

  /// Fundo de botão verde com texto branco (o mesmo nos dois temas).
  Color get _greenFill => SaleFormTom.verdeDeConfirmar();

  String get _numero {
    final a = widget.formNumber?.trim() ?? '';
    if (a.isNotEmpty) return a;
    return _form?.formNumber.trim() ?? '';
  }

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this, initialIndex: _tabEnvio);
    _docName = TextEditingController();
    _docMessage = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    _docName.dispose();
    _docMessage.dispose();
    for (final f in _forms) {
      f.dispose();
    }
    super.dispose();
  }

  // ─── Carga ────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final svc = SaleFormsService.instance;
    final sigsFut = svc.listSignatures(widget.saleFormId);
    final autoFut = svc.getAutomaticaSignersPreview(widget.saleFormId);
    final waFut = svc.getWhatsappEnvio(widget.saleFormId);
    final emailFut = svc.getUltimoEnvioEmail(widget.saleFormId);
    final formFut = svc.getById(widget.saleFormId);
    final sigsRes = await sigsFut;
    final autoRes = await autoFut;
    final waRes = await waFut;
    final emailRes = await emailFut;
    final formRes = await formFut;
    if (!mounted) return;
    setState(() {
      if (sigsRes.success && sigsRes.data != null) {
        _signatures = sigsRes.data!;
        _error = null;
        _errorStatus = 0;
      } else {
        _error = sigsRes.message;
        _errorStatus = sigsRes.statusCode;
      }
      _autoSigners = autoRes.success && autoRes.data != null
          ? autoRes.data!
          : const [];
      _whatsapp = waRes.success ? waRes.data : null;
      _ultimoEmail = emailRes.success ? emailRes.data : _ultimoEmail;
      if (formRes.success && formRes.data != null) _form = formRes.data;

      if (_signatures.isEmpty) {
        if (_docName.text.trim().isEmpty) {
          _docName.text =
              _numero.isEmpty ? 'Ficha de Venda' : 'Ficha de Venda $_numero';
        }
        if (_docMessage.text.trim().isEmpty) {
          _docMessage.text = 'Por favor, assine a ficha de venda conforme os '
              'dados informados.';
        }
      }
      if (_primeiraCarga || !_showTabs) {
        _tab.index = _alreadySent ? _tabStatus : _tabEnvio;
      }
      _primeiraCarga = false;
      _loading = false;
    });
    if (!_prefilled) await _prefillExtras();
  }

  /// Sugestão de extras (`assinatura-envio-signers-preview`), uma vez por
  /// abertura — igual ao web.
  Future<void> _prefillExtras() async {
    _prefilled = true;
    final res =
        await SaleFormsService.instance.getEnvioSignersPreview(widget.saleFormId);
    if (!mounted) return;
    final temAuto = _autoSigners.isNotEmpty;
    setState(() {
      for (final f in _forms) {
        f.dispose();
      }
      _forms.clear();
      final List<SaleFormSignerPreview> rows =
          res.success ? (res.data ?? const []) : const [];
      if (rows.isNotEmpty) {
        for (final r in rows) {
          _forms.add(_SignerForm(name: r.name.trim(), email: r.email.trim()));
        }
        _extrasExpanded = true;
      } else if (temAuto) {
        _extrasExpanded = false;
      } else {
        _forms.add(_SignerForm());
        _extrasExpanded = true;
      }
    });
    if (!res.success) {
      _prefilled = false;
      _snack('Não foi possível sugerir signatários extras. Puxe Atualizar '
          'para tentar de novo.');
    }
  }

  // ─── Regras (espelho do web) ─────────────────────────────────────────────

  bool get _alreadySent => _signatures.isNotEmpty;
  bool get _nenhumaAssinada => _signatures.every((s) => !s.isSigned);
  bool get _mostrarFormularioEnvio => !_alreadySent || _nenhumaAssinada;
  bool get _showTabs => _alreadySent && _mostrarFormularioEnvio;
  bool get _temAuto => _autoSigners.isNotEmpty;

  static bool _inativa(SaleFormSignature s) {
    final st = s.status.toLowerCase();
    return st == 'cancelled' || st == 'canceled' || st == 'expired';
  }

  List<SaleFormSignature> get _ativas =>
      _signatures.where((s) => !_inativa(s)).toList();

  bool _pendente(SaleFormSignature s) =>
      !s.isSigned && !s.isRejected && !_inativa(s);

  String get _meuEmail =>
      (ModuleAccessService.instance.userPermissions?.userEmail ?? '')
          .trim()
          .toLowerCase();

  bool _ehVoce(String? email) {
    final me = _meuEmail;
    return me.isNotEmpty && (email ?? '').trim().toLowerCase() == me;
  }

  Set<String> get _autoEmails => {
        for (final a in _autoSigners)
          if (a.email.trim().isNotEmpty) a.email.trim().toLowerCase(),
      };

  List<String> get _duplicadosAuto {
    final auto = _autoEmails;
    final seen = <String>{};
    final out = <String>[];
    for (final f in _forms) {
      final raw = f.email.text.trim();
      final key = raw.toLowerCase();
      if (key.isEmpty || !auto.contains(key) || !seen.add(key)) continue;
      out.add(raw);
    }
    return out;
  }

  bool get _extrasPreenchidos => _forms.any(
        (f) => f.name.text.trim().isNotEmpty || f.email.text.trim().isNotEmpty,
      );

  bool get _canCancelarTodas {
    if (widget.canInvalidate == false) return false;
    final f = _form;
    if (f == null) return false;
    if (!ModuleAccessService.instance.hasPermission('sale_form:update')) {
      return false;
    }
    final ativas = f.assinaturasTotal > 0 || _ativas.isNotEmpty;
    return f.deletedAt == null &&
        f.status != SaleFormStatus.canceled &&
        f.canInvalidateSignatures &&
        ativas;
  }

  // ─── Ações ───────────────────────────────────────────────────────────────

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirmar({
    required String titulo,
    required String texto,
    required String confirmar,
    bool destrutivo = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ThemeHelpers.cardBackgroundColor(ctx),
        title: Text(titulo),
        content: Text(
          texto,
          style: TextStyle(
            color: ThemeHelpers.textSecondaryColor(ctx),
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: ThemeHelpers.textSecondaryColor(ctx),
            ),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: destrutivo ? _red : _greenFill,
              foregroundColor: Colors.white,
            ),
            child: Text(confirmar),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    final res =
        await SaleFormsService.instance.syncAssinaturas(widget.saleFormId);
    if (!mounted) return;
    setState(() => _syncing = false);
    if (res.success) {
      _snack('Status atualizado com o Autentique.');
      widget.onChanged?.call();
      _load();
    } else {
      _snack(res.message ?? 'Erro ao sincronizar.');
    }
  }

  Future<void> _enviar() async {
    if (_signatures.isNotEmpty && _nenhumaAssinada) {
      final ok = await _confirmar(
        titulo: 'Gerar um novo envio?',
        texto: 'Esta ficha já tem assinaturas pendentes. Um novo envio cancela '
            'os links anteriores no Autentique.',
        confirmar: 'Continuar',
      );
      if (!ok || !mounted) return;
    }
    final nome = _docName.text.trim();
    setState(() => _docNameTouched = true);
    if (nome.isEmpty) {
      _snack('Nome do documento é obrigatório.');
      return;
    }
    final auto = _autoEmails;
    for (final f in _forms) {
      final e = f.email.text.trim().toLowerCase();
      if (e.isNotEmpty && auto.contains(e)) {
        _snack('Há e-mail repetido na lista extra que já entra na inclusão '
            'automática. Remova ou altere.');
        return;
      }
    }
    final payload = <SaleFormSignerInput>[];
    final vistos = <String>{};
    var duplicadas = 0;
    for (final f in _forms) {
      final n = f.name.text.trim();
      final e = f.email.text.trim();
      if (n.isEmpty && e.isEmpty) continue;
      if (saleFormSignerExcluido(email: e, name: n)) {
        _snack('Contas administrativas genéricas ou nome institucional da '
            'imobiliária não podem ser enviados.');
        return;
      }
      if (e.isNotEmpty && n.isEmpty) {
        _snack('Complete o nome do signatário extra ou apague a linha para '
            'enviar só com a inclusão automática.');
        return;
      }
      final key = e.isNotEmpty ? e.toLowerCase() : 'name:${n.toLowerCase()}';
      if (!vistos.add(key)) {
        duplicadas++;
        continue;
      }
      payload.add(SaleFormSignerInput(name: n, email: e.isEmpty ? null : e));
    }
    if (payload.isEmpty && _autoSigners.isEmpty) {
      _snack('Não há signatários para enviar. Verifique a inclusão automática '
          'ou adicione signatários extras.');
      return;
    }
    if (duplicadas > 0) {
      _snack('$duplicadas linha(s) duplicada(s) foram ignoradas no envio.');
    }
    setState(() => _sending = true);
    final msg = _docMessage.text.trim();
    final res = await SaleFormsService.instance.enviarParaAssinatura(
      widget.saleFormId,
      signers: payload,
      documentName: nome,
      documentMessage: msg.isEmpty ? null : msg,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (res.success) {
      _snack('Documento criado. Quem tem e-mail já recebeu o link; copie ou '
          'envie por WhatsApp para os demais.');
      widget.onChanged?.call();
      await _load();
      if (mounted) _tab.animateTo(_tabStatus);
    } else {
      _snack(res.message ?? 'Erro ao gerar documento para assinatura.');
      if (res.statusCode == 0) _load();
    }
  }

  Future<void> _invalidar() async {
    final ok = await _confirmar(
      titulo: 'Cancelar todas as assinaturas?',
      texto: 'Cancela TODAS as assinaturas desta ficha (inclusive as já '
          'assinadas) para permitir um novo envio. Não pode ser desfeito.',
      confirmar: 'Cancelar todas',
      destrutivo: true,
    );
    if (!ok || !mounted) return;
    setState(() => _invalidating = true);
    final res =
        await SaleFormsService.instance.invalidarAssinaturas(widget.saleFormId);
    if (!mounted) return;
    setState(() => _invalidating = false);
    if (res.success) {
      _snack('Assinaturas canceladas. Você pode gerar um novo envio.');
      widget.onChanged?.call();
      await _load();
      if (mounted) _tab.animateTo(_tabEnvio);
    } else {
      _snack(res.message ?? 'Não foi possível cancelar as assinaturas.');
    }
  }

  /// PDF original / assinado pela folha de arquivo do app (Compartilhar /
  /// Salvar no aparelho) — `Uri.file` não abre no Android nem no iOS.
  Future<void> _abrirPdf(String modo) async {
    setState(() => _pdfBusy = modo);
    await showSaleFormPdfSheet(
      context,
      saleFormId: widget.saleFormId,
      numero: _numero.isNotEmpty ? _numero : widget.saleFormId,
      modo: modo,
    );
    if (mounted) setState(() => _pdfBusy = null);
  }

  /// Link da assinatura: usa `signatureUrl` quando já existe (sem POST).
  Future<String?> _resolveLink(SaleFormSignature sig) async {
    final pronto = sig.signatureUrl?.trim() ?? '';
    if (pronto.isNotEmpty) return pronto;
    setState(() => _linkBusyId = sig.id);
    final res = await SaleFormsService.instance
        .obterLinkAssinatura(widget.saleFormId, sig.id);
    if (!mounted) return null;
    setState(() => _linkBusyId = null);
    if (res.success && res.data != null) return res.data;
    _snack(res.message ?? 'Erro ao obter link.');
    return null;
  }

  Future<void> _copiarLink(SaleFormSignature sig) async {
    final link = await _resolveLink(sig);
    if (link == null || !mounted) return;
    await Clipboard.setData(ClipboardData(text: link));
    _snack('Link copiado. Envie só ao signatário correspondente.');
  }

  /// "Assinar": abre o link do próprio usuário no Autentique, fora do app.
  Future<void> _assinar(SaleFormSignature sig) async {
    final link = saleFormLinkAbrivel(await _resolveLink(sig));
    if (link == null || !mounted) {
      if (mounted) _snack('Link de assinatura indisponível.');
      return;
    }
    final ok = await launchUrl(
      Uri.parse(link),
      mode: LaunchMode.externalApplication,
    );
    if (!ok) {
      _snack('Não foi possível abrir o link de assinatura.');
      return;
    }
    _snack('Depois de assinar, toque em Sincronizar para atualizar o status.');
  }

  /// WhatsApp manual (wa.me) — o usuário escolhe o contato.
  Future<void> _whatsappManual(SaleFormSignature sig) async {
    final link = await _resolveLink(sig);
    if (link == null || !mounted) return;
    final texto = 'Olá! Segue o link para assinar a ficha de venda '
        '$_numero:\n\n$link';
    await launchUrl(
      Uri.parse('https://wa.me/?text=${Uri.encodeComponent(texto)}'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _reenviarWhatsappUm(SaleFormSignature sig) async {
    final res = await SaleFormsService.instance
        .reenviarUmWhatsapp(widget.saleFormId, sig.id);
    if (!mounted) return;
    _snack(res.success
        ? _resumoWa(res.data)
        : res.message ?? 'Erro ao reenviar pelo WhatsApp.');
  }

  String _resumoWa(Map<String, dynamic>? r) {
    int n(String k) {
      final v = r?[k];
      return v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
    }

    final parts = <String>[
      if (n('sent') > 0) '${n('sent')} enviado(s)',
      if (n('skippedNoPhone') > 0) '${n('skippedNoPhone')} sem telefone',
      if (n('failed') > 0) '${n('failed')} falha(s)',
    ];
    return parts.isEmpty ? 'Nenhuma mensagem enviada.' : parts.join(' · ');
  }

  Future<void> _reenviarWhatsappTodos() async {
    if (_resendingWa) return;
    setState(() => _resendingWa = true);
    final res = await SaleFormsService.instance
        .reenviarTodosWhatsapp(widget.saleFormId);
    if (!mounted) return;
    setState(() => _resendingWa = false);
    _snack(res.success
        ? _resumoWa(res.data)
        : res.message ?? 'Erro ao reenviar pelo WhatsApp.');
    if (res.success) {
      widget.onChanged?.call();
      _load();
    }
  }

  Future<void> _reenviarEmailTodos() async {
    if (_resendingEmail) return;
    setState(() => _resendingEmail = true);
    final res =
        await SaleFormsService.instance.reenviarTodosEmail(widget.saleFormId);
    if (!mounted) return;
    setState(() => _resendingEmail = false);
    if (res.success && res.data != null) {
      _snack(res.data!.sent > 0
          ? res.data!.resumo
          : (res.data!.motivo ?? res.data!.resumo));
      _load();
    } else {
      _snack(res.message ?? 'Erro ao enviar por e-mail.');
    }
  }

  Future<void> _reenviarEmailUm(SaleFormSignature sig) async {
    if (_emailingSigId != null) return;
    setState(() => _emailingSigId = sig.id);
    final res = await SaleFormsService.instance
        .reenviarUmEmail(widget.saleFormId, sig.id);
    if (!mounted) return;
    setState(() => _emailingSigId = null);
    if (res.success && res.data != null) {
      _snack(res.data!.sent > 0
          ? 'Link enviado para ${sig.signerEmail}.'
          : (res.data!.motivo ?? 'O e-mail não foi enviado.'));
      final u = await SaleFormsService.instance
          .getUltimoEnvioEmail(widget.saleFormId);
      if (mounted && u.success) setState(() => _ultimoEmail = u.data);
    } else {
      _snack(res.message ?? 'Erro ao enviar por e-mail.');
    }
  }

  // ─── Extras ──────────────────────────────────────────────────────────────

  void _addSigner() => setState(() {
        _extrasExpanded = true;
        _forms.add(_SignerForm());
      });

  void _removeSigner(int i) => setState(() {
        _forms.removeAt(i).dispose();
        if (_forms.isEmpty) {
          if (_temAuto) {
            _extrasExpanded = false;
          } else {
            _forms.add(_SignerForm());
          }
        }
      });

  void _abrirExtras() => setState(() {
        _extrasExpanded = true;
        if (_forms.isEmpty) _forms.add(_SignerForm());
      });

  void _ocultarExtras() => setState(() {
        for (final f in _forms) {
          f.dispose();
        }
        _forms.clear();
        _extrasExpanded = false;
      });

  Future<void> _buscarNaEmpresa(int i) async {
    final m = await showModalBottomSheet<SaleFormCompanyMember>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _MemberPickerSheet(),
    );
    if (m == null || !mounted || i >= _forms.length) return;
    setState(() {
      _forms[i].name.text = m.name.trim();
      _forms[i].email.text = m.email.trim();
    });
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final altura = math.max(
      0.0,
      math.min(
        mq.size.height * 0.88,
        mq.size.height - mq.viewInsets.bottom - mq.padding.top - 12,
      ),
    );
    // Pouca altura (teclado aberto em paisagem): cabeçalho sem alça nem
    // sobretítulo, para as abas e o corpo continuarem com espaço.
    final compacto = altura < 360;
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        height: altura,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            _SheetHeader(
              formNumber: _numero,
              compacto: compacto,
              onClose: () => Navigator.of(context).pop(),
            ),
            if (!_loading && _showTabs)
              TabBar(
                controller: _tab,
                indicatorColor: _accent,
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: _accent,
                unselectedLabelColor:
                    ThemeHelpers.textSecondaryColor(context),
                labelStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                dividerColor: ThemeHelpers.borderLightColor(context),
                tabs: [
                  Tab(text: 'Status (${_ativas.length})'),
                  const Tab(text: 'Novo envio'),
                ],
              ),
            Expanded(child: _buildCorpo()),
          ],
        ),
      ),
    );
  }

  Widget _buildCorpo() {
    if (_loading && _primeiraCarga) return const _SheetSkeleton();
    if (_error != null && _signatures.isEmpty) {
      return ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 28),
        children: [
          AppErrorState.fromApi(
            message: _error,
            statusCode: _errorStatus,
            onRetry: _load,
            dense: true,
          ),
        ],
      );
    }
    if (_showTabs) {
      return TabBarView(
        controller: _tab,
        children: [_buildStatusTab(), _abaEnvio()],
      );
    }
    return _alreadySent ? _buildStatusTab() : _abaEnvio();
  }

  /// Aba de envio com os campos `filled` do formulário ([_formTheme]).
  Widget _abaEnvio() =>
      Theme(data: _formTheme(context), child: _buildSendTab());

  // ─── Status ──────────────────────────────────────────────────────────────

  Widget _buildStatusTab() {
    final t = Theme.of(context).textTheme;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final ativas = _ativas;
    final assinados = ativas.where((s) => s.isSigned).length;
    final pendentes = ativas.where(_pendente).length;
    final algumaAssinada = _signatures.any((s) => s.isSigned);
    final canResendWa = _whatsapp?.canResend ?? false;
    final hasEmailPending = _signatures.any((s) =>
        (s.signatureUrl?.trim().isNotEmpty ?? false) &&
        (s.signerEmail?.trim().isNotEmpty ?? false) &&
        ['pending', 'viewed'].contains(s.status.toLowerCase()));
    final waUi = _waUi();
    final u = _ultimoEmail;

    return RefreshIndicator(
      onRefresh: _load,
      color: _accent,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _Leitura(valor: '${ativas.length}', rotulo: 'no envio'),
              _Leitura(
                valor: '$assinados',
                rotulo: assinados == 1 ? 'assinou' : 'assinaram',
                cor: _green,
              ),
              _Leitura(
                valor: '$pendentes',
                rotulo: pendentes == 1 ? 'falta assinar' : 'faltam assinar',
                cor: _warn,
              ),
            ],
          ),
          if (ativas.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (assinados / ativas.length).clamp(0.0, 1.0).toDouble(),
                minHeight: 5,
                backgroundColor: ThemeHelpers.borderLightColor(context),
                valueColor: AlwaysStoppedAnimation(
                  SaleFormTom.sucesso(context).sinal,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _AcaoTexto(
                icon: LucideIcons.refreshCw,
                label: _syncing ? 'Sincronizando…' : 'Sincronizar',
                busy: _syncing,
                onTap: _syncing || _loading ? null : _sync,
              ),
              _AcaoTexto(
                icon: LucideIcons.fileText,
                label: _pdfBusy == 'sistema' ? 'Baixando…' : 'PDF original',
                busy: _pdfBusy == 'sistema',
                onTap: _pdfBusy != null ? null : () => _abrirPdf('sistema'),
              ),
              if (algumaAssinada)
                _AcaoTexto(
                  icon: LucideIcons.fileCheck,
                  label: _pdfBusy == 'assinaturas'
                      ? 'Baixando…'
                      : 'PDF assinado',
                  color: _green,
                  busy: _pdfBusy == 'assinaturas',
                  onTap: _pdfBusy != null
                      ? null
                      : () => _abrirPdf('assinaturas'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionLabel('REENVIAR LINKS', accent: _accent),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _resendingEmail || _syncing || !hasEmailPending
                      ? null
                      : _reenviarEmailTodos,
                  icon: _resendingEmail
                      ? const _Spin()
                      : const Icon(LucideIcons.mailPlus, size: 17),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _resendingEmail ? 'Enviando…' : 'Por e-mail',
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                  style: _estiloReenvio(_blue),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: waUi.$1 ? null : _reenviarWhatsappTodos,
                  icon: _resendingWa
                      ? const _Spin()
                      : const Icon(LucideIcons.messageCircle, size: 17),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _resendingWa ? 'Enviando…' : 'Pelo WhatsApp',
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                  style: _estiloReenvio(_green),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            hasEmailPending
                ? 'E-mail: cada signatário pendente recebe o próprio link. '
                    'WhatsApp: ${waUi.$2}'
                : 'Nenhum signatário pendente com e-mail e link. '
                    'WhatsApp: ${waUi.$2}',
            style: t.labelSmall?.copyWith(color: muted, height: 1.35),
          ),
          if (u != null && u.at != null) ...[
            const SizedBox(height: 4),
            Text(
              'Último envio por e-mail em '
              '${DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(u.at!.toLocal())}'
              '${u.sent > 0 ? ' · ${u.sent} de ${u.total} enviado(s)' : (u.motivo != null ? ' · ${u.motivo}' : '')}',
              style: t.labelSmall?.copyWith(color: muted, height: 1.35),
            ),
          ],
          if (_whatsapp != null) ...[
            const SizedBox(height: 12),
            _buildWaStatus(),
          ],
          const SizedBox(height: 18),
          _SectionLabel('SIGNATÁRIOS', accent: _accent),
          const SizedBox(height: 4),
          if (_signatures.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Nenhuma assinatura ainda.',
                style: t.bodySmall?.copyWith(color: muted),
              ),
            )
          else
            for (final s in _signatures)
              _SignatureRow(
                signature: s,
                ehVoce: _ehVoce(s.signerEmail),
                busy: _linkBusyId == s.id,
                emailing: _emailingSigId == s.id,
                green: _green,
                warn: _warn,
                red: _red,
                blue: _blue,
                // "VOCÊ" na cor de assinar (a mesma das assinaturas pendentes).
                accent: _green,
                onAssinar: () => _assinar(s),
                onCopyLink: () => _copiarLink(s),
                onWhatsappManual: () => _whatsappManual(s),
                onResendEmail: (s.signerEmail?.trim().isNotEmpty ?? false) &&
                        (s.signatureUrl?.trim().isNotEmpty ?? false) &&
                        _emailingSigId == null
                    ? () => _reenviarEmailUm(s)
                    : null,
                onResendWhatsapp:
                    canResendWa ? () => _reenviarWhatsappUm(s) : null,
              ),
          if (_canCancelarTodas) ...[
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _invalidating || _syncing || _sending
                    ? null
                    : _invalidar,
                icon: _invalidating
                    ? const _Spin()
                    : Icon(LucideIcons.ban, size: 17, color: _red),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Cancelar todas para reenvio',
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(color: _red),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _red,
                  side: BorderSide(color: _red.withValues(alpha: 0.45)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// (desabilitado, explicação) do reenvio pelo WhatsApp — regras do web.
  (bool, String) _waUi() {
    if (_resendingWa) return (true, 'aguarde o envio pela integração.');
    if (_syncing) return (true, 'aguarde a sincronização com o Autentique.');
    final wa = _whatsapp;
    if (wa == null) return (true, 'integração indisponível. Puxe para atualizar.');
    if (!wa.autoSendEnabled) {
      return (true, 'envio não configurado para a empresa.');
    }
    if (!wa.canResend) return (true, 'nenhuma sessão conectada para envio.');
    final temPendenteComLink = _signatures.any(
      (s) => (s.signatureUrl?.trim().isNotEmpty ?? false) && _pendente(s),
    );
    if (!temPendenteComLink) {
      return (true, 'não há assinaturas pendentes com link.');
    }
    return (false, 'reenvia os links pendentes pela sessão da empresa.');
  }

  Widget _buildWaStatus() {
    final wa = _whatsapp!;
    final perms = ModuleAccessService.instance;
    final podeObrig =
        perms.hasPermission('sale_form:manage_mandatory_signers');
    final podeWa = perms.hasPermission('whatsapp:manage_config');
    const pedir = 'Solicite a configuração a um responsável (administrador '
        'ou gestor) da empresa.';
    late final bool ok;
    late final String titulo;
    late final String texto;
    if (!wa.autoSendEnabled) {
      ok = false;
      titulo = 'Envio de assinaturas por WhatsApp não configurado';
      texto = podeObrig
          ? 'Ative o envio automático dos links em Signatários obrigatórios '
              '(sistema web).'
          : pedir;
    } else if (!wa.canResend) {
      ok = false;
      titulo = wa.preferredSessionKind != null
          ? 'O número escolhido para envio não está conectado'
          : 'Nenhuma sessão WhatsApp conectada para envio';
      texto = podeWa
          ? 'Conecte a sessão WhatsApp da empresa nas configurações do '
              'WhatsApp (sistema web).'
          : pedir;
    } else {
      ok = true;
      final kind = wa.sessionKind ?? wa.preferredSessionKind;
      final canal = kind == 'monitor'
          ? 'Monitoramento'
          : kind == 'unofficial'
              ? 'WhatsApp Não Oficial'
              : 'WhatsApp da empresa';
      final numero = _formatWaPhone(wa.phoneNumber);
      titulo = 'Envio por WhatsApp configurado';
      texto = numero != null
          ? 'Os links saem do número $numero ($canal).'
          : 'Os links saem pela sessão $canal.';
    }
    final cor = ok ? _green : _warn;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? LucideIcons.circleCheck : LucideIcons.info,
            size: 16,
            color: cor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  texto,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        height: 1.35,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String? _formatWaPhone(String? digits) {
    final d = (digits ?? '').replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) return null;
    final m = RegExp(r'^55(\d{2})(\d{4,5})(\d{4})$').firstMatch(d);
    return m != null ? '+55 (${m[1]}) ${m[2]}-${m[3]}' : '+$d';
  }

  /// Reenviar não é confirmação nem destrutivo: contorno neutro, a cor fica
  /// só no ícone (e-mail azul, WhatsApp verde) e some quando desabilitado.
  ButtonStyle _estiloReenvio(Color icone) => OutlinedButton.styleFrom(
        foregroundColor: ThemeHelpers.textColor(context),
        iconColor: icone,
        side: BorderSide(color: ThemeHelpers.borderColor(context)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      );

  /// Campos `filled` leves do formulário de envio — mesma gramática do
  /// cadastro da ficha: sem borda em repouso, foco na cor da marca.
  ThemeData _formTheme(BuildContext context) {
    final base = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final fill = _isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    final erro = _red;
    OutlineInputBorder b(Color c, double w) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              w == 0 ? BorderSide.none : BorderSide(color: c, width: w),
        );
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(primary: _accent),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: _accent,
        selectionColor: _accent.withValues(alpha: 0.18),
        selectionHandleColor: _accent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fill,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        labelStyle: TextStyle(
          color: muted,
          fontWeight: FontWeight.w600,
          fontSize: 13.5,
        ),
        floatingLabelStyle: TextStyle(
          color: _accent,
          fontWeight: FontWeight.w700,
          fontSize: 13.5,
        ),
        hintStyle: TextStyle(
          color: muted.withValues(alpha: 0.7),
          fontWeight: FontWeight.w500,
        ),
        errorStyle: TextStyle(
          color: erro,
          fontWeight: FontWeight.w600,
          fontSize: 11.5,
        ),
        errorMaxLines: 3,
        border: b(Colors.transparent, 0),
        enabledBorder: b(Colors.transparent, 0),
        focusedBorder: b(_accent, 1.6),
        errorBorder: b(erro.withValues(alpha: 0.75), 1.2),
        focusedErrorBorder: b(erro, 1.6),
      ),
    );
  }

  // ─── Envio ───────────────────────────────────────────────────────────────

  Widget _buildSendTab() {
    final t = Theme.of(context).textTheme;
    final muted = ThemeHelpers.textSecondaryColor(context);
    if (!ModuleAccessService.instance.hasPermission('sale_form:update')) {
      return const _LockedNotice(
        message:
            'Você não tem permissão para enviar esta ficha para assinatura.',
      );
    }
    if (!_mostrarFormularioEnvio) {
      return const _LockedNotice(
        message: 'Esta ficha já tem assinatura concluída. Para um novo envio, '
            'cancele todas as assinaturas (reenvio) no Status.',
      );
    }
    final dups = _duplicadosAuto;
    final nomeVazio = _docNameTouched && _docName.text.trim().isEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(LucideIcons.info, size: 14, color: muted),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Gera os links no Autentique. Quem tem e-mail recebe o link '
                'por e-mail na hora; o WhatsApp da empresa segue como reforço.',
                style: t.bodySmall?.copyWith(color: muted, height: 1.35),
              ),
            ),
          ],
        ),
        if (_alreadySent && _nenhumaAssinada) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: _warn.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _warn.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    LucideIcons.triangleAlert,
                    size: 15,
                    color: _warn,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Esta ficha já tem assinaturas pendentes. Um novo envio '
                    'cancela os links anteriores no Autentique.',
                    style: t.bodySmall?.copyWith(height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        _SectionLabel('DOCUMENTO', accent: _accent),
        const SizedBox(height: 10),
        TextField(
          controller: _docName,
          onChanged: (_) {
            if (_docNameTouched) setState(() {});
          },
          decoration: InputDecoration(
            labelText: 'Nome no Autentique *',
            errorText: nomeVazio ? 'Obrigatório' : null,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _docMessage,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Mensagem (opcional)',
            hintText: 'Texto exibido ao abrir o link de assinatura',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 22),
        _SectionLabel('INCLUSÃO AUTOMÁTICA', accent: _accent),
        const SizedBox(height: 4),
        Text(
          'Obrigatórios da empresa e gestor/corretores do PDF. Entram no envio '
          'sem precisar adicionar na lista abaixo.',
          style: t.bodySmall?.copyWith(color: muted, height: 1.35),
        ),
        const SizedBox(height: 6),
        if (_autoSigners.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Nenhum signatário automático. Adicione extras ou revise as '
              'comissões da ficha.',
              style: t.bodySmall?.copyWith(color: muted),
            ),
          )
        else
          for (final s in _autoSigners)
            _AutoSignerRow(signer: s, ehVoce: _ehVoce(s.email)),
        const SizedBox(height: 22),
        _SectionLabel(
          _temAuto ? 'SIGNATÁRIOS EXTRAS · OPCIONAL' : 'SIGNATÁRIOS EXTRAS',
          accent: _accent,
        ),
        const SizedBox(height: 6),
        if (_temAuto && !_extrasExpanded && !_extrasPreenchidos) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.circleCheck, size: 17, color: _green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_autoSigners.length} '
                  '${_autoSigners.length == 1 ? 'pessoa já entra' : 'pessoas já entram'} '
                  'automaticamente (empresa + comissões da ficha). Em venda '
                  'solo, ou quando ninguém extra falta assinar, gere os links '
                  'sem preencher nada abaixo.',
                  style: t.bodySmall?.copyWith(height: 1.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _abrirExtras,
              icon: const Icon(LucideIcons.userPlus, size: 17),
              label: const Text('Adicionar signatário extra'),
              style: TextButton.styleFrom(foregroundColor: _accent),
            ),
          ),
        ] else ...[
          Text(
            _temAuto
                ? 'Só preencha se faltar criador, vinculado ou outra parte que '
                    'não está na lista automática.'
                : 'Informe quem ainda precisa assinar além dos obrigatórios da '
                    'empresa (se houver).',
            style: t.bodySmall?.copyWith(color: muted, height: 1.35),
          ),
          if (dups.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'E-mail(s) ${dups.join(', ')} já estão na inclusão automática.',
              style: t.bodySmall?.copyWith(
                color: _red,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (_temAuto)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _ocultarExtras,
                icon: const Icon(LucideIcons.chevronUp, size: 16),
                label: const Text('Ocultar extras (só inclusão automática)'),
                style: TextButton.styleFrom(
                  foregroundColor: muted,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          const SizedBox(height: 4),
          for (var i = 0; i < _forms.length; i++)
            _SignerFormRow(
              index: i,
              form: _forms[i],
              obrigatorio: !_temAuto,
              duplicado: _autoEmails
                  .contains(_forms[i].email.text.trim().toLowerCase()),
              accent: _accent,
              onChanged: () => setState(() {}),
              onBuscar: () => _buscarNaEmpresa(i),
              onRemove: !_temAuto &&
                      _forms.length <= 1 &&
                      _forms[i].name.text.trim().isEmpty &&
                      _forms[i].email.text.trim().isEmpty
                  ? null
                  : () => _removeSigner(i),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addSigner,
              icon: const Icon(LucideIcons.plus, size: 17),
              label: const Text('Outro signatário extra'),
              style: TextButton.styleFrom(foregroundColor: _accent),
            ),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _sending || dups.isNotEmpty ? null : _enviar,
            icon: _sending
                ? const _Spin(color: Colors.white)
                : const Icon(LucideIcons.link, size: 18),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _sending
                    ? 'Gerando…'
                    : _temAuto && !_extrasPreenchidos
                        ? 'Gerar links (automáticos)'
                        : 'Gerar links',
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _greenFill,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _greenFill.withValues(alpha: 0.35),
              disabledForegroundColor: Colors.white.withValues(alpha: 0.85),
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        if (_sending) ...[
          const SizedBox(height: 8),
          Text(
            'Gerando o documento no Autentique… pode levar até 2 minutos.',
            textAlign: TextAlign.center,
            style: t.labelSmall?.copyWith(color: muted),
          ),
        ],
      ],
    );
  }
}

// ─── Peças ────────────────────────────────────────────────────────────────────

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.formNumber,
    required this.onClose,
    this.compacto = false,
  });
  final String formNumber;
  final VoidCallback onClose;

  /// Altura curta: some a alça e o sobretítulo.
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, compacto ? 4 : 10, 8, compacto ? 0 : 4),
      child: Column(
        children: [
          if (!compacto)
            Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: muted.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!compacto)
                      Text(
                        'ASSINATURAS',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: muted,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.6,
                            ),
                      ),
                    Text(
                      formNumber.isEmpty
                          ? 'Ficha de venda'
                          : 'Ficha de venda nº $formNumber',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Fechar',
                onPressed: onClose,
                icon: const Icon(LucideIcons.x, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SheetSkeleton extends StatelessWidget {
  const _SheetSkeleton();

  @override
  Widget build(BuildContext context) {
    // Mesma silhueta do Status: leituras + barra, ações, reenvio em par e
    // linhas de signatário (ícone, nome, e-mail, pílula).
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: const [
            SkeletonBox(width: 70, height: 18, borderRadius: 6),
            SkeletonBox(width: 90, height: 18, borderRadius: 6),
            SkeletonBox(width: 100, height: 18, borderRadius: 6),
          ],
        ),
        const SizedBox(height: 10),
        const SkeletonBox(height: 5, borderRadius: 3),
        const SizedBox(height: 14),
        Row(
          children: const [
            SkeletonBox(width: 110, height: 34, borderRadius: 10),
            SizedBox(width: 8),
            SkeletonBox(width: 110, height: 34, borderRadius: 10),
          ],
        ),
        const SizedBox(height: 20),
        const SkeletonBox(width: 130, height: 12, borderRadius: 6),
        const SizedBox(height: 10),
        Row(
          children: const [
            Expanded(child: SkeletonBox(height: 46, borderRadius: 12)),
            SizedBox(width: 10),
            Expanded(child: SkeletonBox(height: 46, borderRadius: 12)),
          ],
        ),
        const SizedBox(height: 22),
        const SkeletonBox(width: 110, height: 12, borderRadius: 6),
        const SizedBox(height: 6),
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonBox(width: 16, height: 16, borderRadius: 4),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 150, height: 14, borderRadius: 6),
                      SizedBox(height: 6),
                      SkeletonBox(width: 180, height: 11, borderRadius: 6),
                      SizedBox(height: 8),
                      SkeletonBox(width: 86, height: 18, borderRadius: 999),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.accent});
  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 15,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.3,
                  color: ThemeHelpers.textColor(context),
                  fontSize: 11,
                ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            color: ThemeHelpers.borderLightColor(context),
          ),
        ),
      ],
    );
  }
}

class _Leitura extends StatelessWidget {
  const _Leitura({required this.valor, required this.rotulo, this.cor});
  final String valor;
  final String rotulo;
  final Color? cor;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: valor,
            style: t.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: cor ?? ThemeHelpers.textColor(context),
            ),
          ),
          TextSpan(
            text: ' $rotulo',
            style: t.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _AcaoTexto extends StatelessWidget {
  const _AcaoTexto({
    required this.icon,
    required this.label,
    required this.onTap,
    this.busy = false,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool busy;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: busy ? const _Spin() : Icon(icon, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: color ?? ThemeHelpers.textColor(context),
        visualDensity: VisualDensity.compact,
        side: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class _Spin extends StatelessWidget {
  const _Spin({this.color});
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2, color: color),
    );
  }
}

class _VoceBadge extends StatelessWidget {
  const _VoceBadge({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        'VOCÊ',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
              fontSize: 9.5,
            ),
      ),
    );
  }
}

class _AutoSignerRow extends StatelessWidget {
  const _AutoSignerRow({required this.signer, required this.ehVoce});
  final SaleFormSignerPreview signer;
  final bool ehVoce;

  @override
  Widget build(BuildContext context) {
    final isMandatory = signer.source == 'mandatory';
    // Tons legíveis também no modo claro (texto do selo).
    final tone = isMandatory
        ? SaleFormTom.sucesso(context).texto
        : SaleFormTom.info(context).texto;
    // "VOCÊ" na cor de assinar, como nas linhas do Status.
    final accent = SaleFormTom.sucesso(context).texto;
    final badge = isMandatory ? 'EMPRESA' : 'PDF';
    final name = signer.name.trim().isEmpty ? signer.email : signer.name;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              badge,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: tone,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    fontSize: 9.5,
                  ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name.trim().isEmpty ? 'Signatário' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    if (ehVoce) ...[
                      const SizedBox(width: 6),
                      _VoceBadge(color: accent),
                    ],
                  ],
                ),
                if (signer.email.trim().isNotEmpty)
                  Text(
                    signer.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SignatureRow extends StatelessWidget {
  const _SignatureRow({
    required this.signature,
    required this.ehVoce,
    required this.busy,
    required this.emailing,
    required this.green,
    required this.warn,
    required this.red,
    required this.blue,
    required this.accent,
    required this.onAssinar,
    required this.onCopyLink,
    required this.onWhatsappManual,
    this.onResendEmail,
    this.onResendWhatsapp,
  });

  final SaleFormSignature signature;
  final bool ehVoce;
  final bool busy;
  final bool emailing;
  final Color green;
  final Color warn;
  final Color red;
  final Color blue;
  final Color accent;
  final VoidCallback onAssinar;
  final VoidCallback onCopyLink;
  final VoidCallback onWhatsappManual;
  final VoidCallback? onResendEmail;
  final VoidCallback? onResendWhatsapp;

  Color _tone(BuildContext context) {
    if (signature.isSigned) return green;
    if (signature.isRejected) return red;
    final s = signature.status.toLowerCase();
    if (s == 'viewed') return blue;
    if (s == 'cancelled' || s == 'canceled' || s == 'expired') {
      return ThemeHelpers.textSecondaryColor(context);
    }
    return warn;
  }

  PopupMenuItem<String> _itemMenu(
    BuildContext context,
    String value,
    IconData icon,
    String label,
    Color cor,
  ) {
    return PopupMenuItem<String>(
      value: value,
      height: 44,
      child: Row(
        children: [
          Icon(icon, size: 18, color: cor),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                height: 1.2,
                color: ThemeHelpers.textColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final tone = _tone(context);
    final st = signature.status.toLowerCase();
    final encerrada = signature.isSigned ||
        signature.isRejected ||
        st == 'cancelled' ||
        st == 'canceled' ||
        st == 'expired';
    final nome = signature.signerName?.trim().isNotEmpty == true
        ? signature.signerName!.trim()
        : (signature.signerEmail ?? 'Signatário sem nome');
    final assinadoEm = signature.isSigned && signature.signedAt != null
        ? DateFormat('dd/MM/yyyy HH:mm', 'pt_BR')
            .format(signature.signedAt!.toLocal())
        : null;
    final fill = SaleFormTom.verdeDeConfirmar();
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  signature.signerEmail != null
                      ? LucideIcons.mail
                      : LucideIcons.userCheck,
                  size: 16,
                  color: tone,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            nome,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (ehVoce) ...[
                          const SizedBox(width: 6),
                          _VoceBadge(color: accent),
                        ],
                      ],
                    ),
                    if (signature.signerEmail != null)
                      Text(
                        signature.signerEmail!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall?.copyWith(color: muted),
                      ),
                    const SizedBox(height: 6),
                    // Status em pílula embaixo do nome: a linha de cima fica
                    // livre para o nome em 320dp.
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _StatusPill(label: signature.statusLabel, tone: tone),
                        if (assinadoEm != null)
                          Text(
                            'em $assinadoEm',
                            style: t.labelSmall?.copyWith(
                              color: green,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!encerrada)
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  tooltip: 'Ações do signatário',
                  color: ThemeHelpers.cardBackgroundColor(context),
                  elevation: 12,
                  shadowColor: Colors.black.withValues(alpha: 0.25),
                  constraints:
                      const BoxConstraints(minWidth: 220, maxWidth: 320),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: ThemeHelpers.borderColor(context)
                          .withValues(alpha: 0.7),
                    ),
                  ),
                  icon: busy || emailing
                      ? const _Spin()
                      : Icon(LucideIcons.ellipsisVertical,
                          size: 18, color: muted),
                  itemBuilder: (ctx) => [
                    _itemMenu(
                      ctx,
                      'copy',
                      LucideIcons.copy,
                      'Copiar link',
                      muted,
                    ),
                    if (onResendEmail != null)
                      _itemMenu(
                        ctx,
                        'email',
                        LucideIcons.mailPlus,
                        'Enviar link por e-mail',
                        blue,
                      ),
                    _itemMenu(
                      ctx,
                      'wa',
                      LucideIcons.messageCircle,
                      'Compartilhar no WhatsApp',
                      green,
                    ),
                    if (onResendWhatsapp != null)
                      _itemMenu(
                        ctx,
                        'resend',
                        LucideIcons.send,
                        'Reenviar pelo WhatsApp da empresa',
                        green,
                      ),
                  ],
                  onSelected: (v) {
                    switch (v) {
                      case 'copy':
                        onCopyLink();
                        break;
                      case 'email':
                        onResendEmail?.call();
                        break;
                      case 'wa':
                        onWhatsappManual();
                        break;
                      case 'resend':
                        onResendWhatsapp?.call();
                        break;
                    }
                  },
                ),
            ],
          ),
          if (ehVoce && !encerrada) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: FilledButton.icon(
                onPressed: busy ? null : onAssinar,
                icon: const Icon(LucideIcons.penLine, size: 17),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Assinar agora',
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: fill,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: fill.withValues(alpha: 0.35),
                  disabledForegroundColor:
                      Colors.white.withValues(alpha: 0.85),
                  minimumSize: const Size(0, 46),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Status do signatário em pílula (tom = significado: assinado verde,
/// visualizado azul, pendente âmbar, recusado vermelho, encerrado neutro).
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.tone});
  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: tone,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
              fontSize: 10,
            ),
      ),
    );
  }
}

class _LockedNotice extends StatelessWidget {
  const _LockedNotice({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.lock, size: 28, color: muted.withValues(alpha: 0.7)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: muted,
                    height: 1.4,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignerForm {
  _SignerForm({String name = '', String email = ''})
      : name = TextEditingController(text: name),
        email = TextEditingController(text: email);

  final TextEditingController name;
  final TextEditingController email;

  void dispose() {
    name.dispose();
    email.dispose();
  }
}

class _SignerFormRow extends StatelessWidget {
  const _SignerFormRow({
    required this.index,
    required this.form,
    required this.obrigatorio,
    required this.duplicado,
    required this.accent,
    required this.onChanged,
    required this.onBuscar,
    this.onRemove,
  });

  final int index;
  final _SignerForm form;
  final bool obrigatorio;
  final bool duplicado;
  final Color accent;
  final VoidCallback onChanged;
  final VoidCallback onBuscar;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 8, bottom: 14),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Extra ${index + 1}${obrigatorio ? ' *' : ''}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              TextButton.icon(
                onPressed: onBuscar,
                icon: const Icon(LucideIcons.search, size: 15),
                label: const Text('Buscar na empresa'),
                style: TextButton.styleFrom(
                  foregroundColor: accent,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              IconButton(
                tooltip: 'Remover linha',
                onPressed: onRemove,
                icon: const Icon(LucideIcons.trash2, size: 17),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, c) {
              final nome = TextField(
                controller: form.name,
                onChanged: (_) => onChanged(),
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Nome no documento${obrigatorio ? ' *' : ''}',
                  hintText: obrigatorio
                      ? 'Como aparece na assinatura'
                      : 'Só se esta pessoa for assinar',
                ),
              );
              final email = TextField(
                controller: form.email,
                onChanged: (_) => onChanged(),
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'E-mail (opcional)',
                  hintText: 'Recebe o link por e-mail',
                  errorText:
                      duplicado ? 'Já está na inclusão automática' : null,
                ),
              );
              // Duas colunas só quando cabem os rótulos inteiros (tablet /
              // paisagem); no celular, um embaixo do outro.
              if (c.maxWidth >= 520) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: nome),
                    const SizedBox(width: 10),
                    Expanded(child: email),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [nome, const SizedBox(height: 10), email],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Seletor de membros da empresa (web: "Buscar na empresa").
class _MemberPickerSheet extends StatefulWidget {
  const _MemberPickerSheet();

  @override
  State<_MemberPickerSheet> createState() => _MemberPickerSheetState();
}

class _MemberPickerSheetState extends State<_MemberPickerSheet> {
  final TextEditingController _q = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  String? _erro;
  int _erroStatus = 0;
  List<SaleFormCompanyMember> _items = const [];
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _buscar('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _buscar(String termo) async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _erro = null;
    });
    final res =
        await SaleFormsService.instance.buscarMembrosEmpresa(search: termo);
    if (!mounted || seq != _seq) return;
    setState(() {
      _loading = false;
      if (res.success) {
        _items = res.data ?? const [];
      } else {
        _items = const [];
        _erro = res.message ?? 'Erro ao buscar membros da empresa.';
        _erroStatus = res.statusCode;
      }
    });
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () => _buscar(v));
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final hair = ThemeHelpers.borderLightColor(context);
    OutlineInputBorder borda(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c, width: w),
        );

    final Widget corpo;
    if (_loading) {
      // Esqueleto fiel às linhas (iniciais + nome + e-mail).
      corpo = ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        children: [
          for (var i = 0; i < 5; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                children: const [
                  SkeletonBox(width: 34, height: 34, borderRadius: 17),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 150, height: 13, borderRadius: 6),
                        SizedBox(height: 6),
                        SkeletonBox(width: 190, height: 11, borderRadius: 6),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    } else if (_erro != null) {
      corpo = SingleChildScrollView(
        child: AppErrorState.fromApi(
          message: _erro,
          statusCode: _erroStatus,
          onRetry: () => _buscar(_q.text),
          dense: true,
        ),
      );
    } else if (_items.isEmpty) {
      corpo = SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        child: Column(
          children: [
            Icon(LucideIcons.searchX, size: 26, color: muted),
            const SizedBox(height: 10),
            Text(
              _q.text.trim().isEmpty
                  ? 'Nenhum membro da empresa para mostrar.'
                  : 'Ninguém encontrado para "${_q.text.trim()}". Confira o '
                      'nome ou busque pelo e-mail.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: muted, height: 1.4),
            ),
          ],
        ),
      );
    } else {
      corpo = ListView.separated(
        shrinkWrap: true,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 20),
        itemCount: _items.length,
        separatorBuilder: (ctx, i) => Divider(
          height: 1,
          indent: 62,
          endIndent: 16,
          color: ThemeHelpers.borderLightColor(context),
        ),
        itemBuilder: (ctx, i) {
          final m = _items[i];
          return _MembroLinha(
            membro: m,
            onTap: () => Navigator.of(context).pop(m),
          );
        },
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.88),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Buscar na empresa',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fechar',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(LucideIcons.x, size: 20, color: muted),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _q,
                  autofocus: true,
                  onChanged: _onChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Nome ou e-mail…',
                    prefixIcon:
                        Icon(LucideIcons.search, size: 18, color: accent),
                    filled: true,
                    fillColor: isDark
                        ? AppColors.background.backgroundTertiaryDarkMode
                        : AppColors.background.backgroundTertiary,
                    contentPadding: const EdgeInsets.symmetric(vertical: 13),
                    border: borda(hair),
                    enabledBorder: borda(hair),
                    focusedBorder: borda(accent.withValues(alpha: 0.65), 1.4),
                  ),
                ),
              ),
              Flexible(child: corpo),
            ],
          ),
        ),
      ),
    );
  }
}

/// Linha de membro: iniciais + nome + e-mail (toque preenche o signatário).
class _MembroLinha extends StatelessWidget {
  const _MembroLinha({required this.membro, required this.onTap});
  final SaleFormCompanyMember membro;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final partes = membro.name.trim().split(RegExp(r'\s+'));
    final ini = partes.isEmpty || partes.first.isEmpty
        ? '?'
        : (partes.length == 1
                ? partes.first[0]
                : '${partes.first[0]}${partes.last[0]}')
            .toUpperCase();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: muted.withValues(alpha: 0.14),
                border: Border.all(color: muted.withValues(alpha: 0.3)),
              ),
              child: Text(
                ini,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    membro.name.trim().isEmpty ? membro.email : membro.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                  if (membro.email.trim().isNotEmpty)
                    Text(
                      membro.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, size: 18, color: muted),
          ],
        ),
      ),
    );
  }
}
