import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/utils/input_formatters.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../workspace/models/admin_user_model.dart';
import '../../workspace/services/admin_users_service.dart';
import '../models/rental_form_model.dart';
import '../models/rental_form_sections.dart';
import '../services/rental_forms_service.dart';
import '../widgets/rental_form_inputs.dart';
import '../widgets/rental_share_link_sheet.dart';

/// Estado do autosave — paridade com o editor web (`AutoSaveState`).
enum _SaveState { idle, saving, saved, error }

/// Editor da ficha de locação — porta `FichaLocacaoEditorPage.tsx` +
/// `RentalLocacaoFormBody.tsx` como formulário por etapas (mesmo padrão visual
/// dos steps da ficha de venda: cor da marca, header flush com sublinhado,
/// campos filled em 2 colunas). Salvamento automático com debounce; blocos de
/// link público e finalização/assinatura no último passo.
class RentalFormEditorPage extends StatefulWidget {
  const RentalFormEditorPage({super.key, required this.formId});

  final String formId;

  @override
  State<RentalFormEditorPage> createState() => _RentalFormEditorPageState();
}

class _RentalFormEditorPageState extends State<RentalFormEditorPage> {
  // ── Estado da ficha ───────────────────────────────────────────────────────
  bool _loading = true;
  String? _loadError;
  RentalForm? _form;
  RentalFormStatus _status = RentalFormStatus.pending;

  final _title = TextEditingController();
  final Map<RentalSectionKey, Map<String, String>> _data = {
    for (final t in RentalSectionKey.values) t: <String, String>{},
  };
  final _obs = TextEditingController();
  List<RentalFormUser> _involved = [];

  // Link público / assinatura.
  String? _publicToken;
  DateTime? _publicExpiresAt;
  RentalPublicLinkType _linkType = RentalPublicLinkType.completa;
  String? _signatureUrl;
  List<RentalSignatureEvent> _signatureHistory = const [];

  // ── Autosave ─────────────────────────────────────────────────────────────
  _SaveState _saveState = _SaveState.saved;
  DateTime? _lastSavedAt;
  String _lastSnapshot = '';
  Timer? _debounce;
  bool _saving = false;
  bool _finishing = false;
  bool _linkBusy = false;

  /// Se algo mudou desde que a lista foi aberta (retorno do `pop`).
  bool _dirtySinceOpen = false;

  // ── Stepper / campos ─────────────────────────────────────────────────────
  final PageController _pageCtrl = PageController();
  int _step = 0;

  /// Controllers de texto por `'{tab}.{campo}'` — criados sob demanda e
  /// descartados ao recarregar a ficha (bump em [_reloadTick]).
  final Map<String, TextEditingController> _ctrls = {};
  int _reloadTick = 0;

  bool get _canEdit =>
      ModuleAccessService.instance
          .hasPermission(RentalFormPermissions.update) ||
      ModuleAccessService.instance.hasPermission(RentalFormPermissions.create);

  bool get _editable => _canEdit && _status == RentalFormStatus.pending;

  Color get _brand => Theme.of(context).brightness == Brightness.dark
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;

  @override
  void initState() {
    super.initState();
    _title.addListener(_onTitleChanged);
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // Voltar do sistema pode sair sem passar pelo botão — descarrega o
    // autosave pendente (fire-and-forget; a lista recarrega ao retornar).
    if (_editable && !_saving && _snapshot() != _lastSnapshot) {
      unawaited(RentalFormsService.instance.update(
        widget.formId,
        title: _title.text,
        payload: _buildPayload(),
        involvedUserIds: _involved.map((u) => u.id).toList(),
      ));
    }
    _pageCtrl.dispose();
    _title.removeListener(_onTitleChanged);
    _title.dispose();
    _obs.dispose();
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _onTitleChanged() {
    if (!_editable || _loading) return;
    _scheduleAutosave();
  }

  // ── Carregamento ─────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final res = await RentalFormsService.instance.getById(widget.formId);
    if (!mounted) return;
    if (!res.success || res.data == null) {
      setState(() {
        _loading = false;
        _loadError =
            res.message ?? 'Ficha não encontrada ou sem permissão.';
      });
      return;
    }
    setState(() {
      _applyForm(res.data!);
      _loading = false;
    });
  }

  /// Aplica a ficha carregada (ou reaberta) ao estado — re-hidrata campos.
  void _applyForm(RentalForm f) {
    _form = f;
    _status = f.status;
    _title.text = f.title ?? '';
    for (final tab in RentalSectionKey.values) {
      _data[tab] = Map<String, String>.from(f.section(tab.payloadKey));
    }
    _obs.text = f.observacoesInternas;
    _involved = List.of(f.involvedUsers);
    _publicToken = f.publicToken;
    _publicExpiresAt = f.publicTokenExpiresAt;
    _signatureUrl = RentalFormsService.isInvalidSignatureUrl(f.signatureUrl)
        ? null
        : f.signatureUrl;
    _signatureHistory = f.signatureHistory;
    _lastSavedAt = f.updatedAt;
    _saveState = _SaveState.saved;
    _lastSnapshot = _snapshot();
    // Recria controllers com os novos valores.
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _ctrls.clear();
    _reloadTick++;
  }

  // ── Payload / snapshot ───────────────────────────────────────────────────

  Map<String, dynamic> _buildPayload() {
    // Preserva chaves desconhecidas do payload original (anexos, legado…).
    final base = Map<String, dynamic>.from(_form?.payload ?? const {});
    for (final tab in RentalSectionKey.values) {
      final clean = <String, String>{};
      _data[tab]!.forEach((k, v) {
        if (v.trim().isNotEmpty) clean[k] = v;
      });
      base[tab.payloadKey] = clean;
    }
    base['observacoesInternas'] = _obs.text;
    return base;
  }

  String _snapshot() {
    dynamic sortDeep(dynamic v) {
      if (v is Map) {
        final keys = v.keys.map((k) => k.toString()).toList()..sort();
        return {for (final k in keys) k: sortDeep(v[k])};
      }
      if (v is List) return v.map(sortDeep).toList();
      return v;
    }

    final ids = _involved.map((u) => u.id).toList()..sort();
    return jsonEncode(sortDeep({
      'title': _title.text.trim(),
      'payload': _buildPayload(),
      'involvedUserIds': ids,
    }));
  }

  // ── Autosave / salvar ────────────────────────────────────────────────────

  void _scheduleAutosave() {
    if (!_editable) return;
    _dirtySinceOpen = true;
    _debounce?.cancel();
    if (_saveState != _SaveState.idle) {
      setState(() => _saveState = _SaveState.idle);
    }
    _debounce = Timer(const Duration(milliseconds: 1400), () {
      _save();
    });
  }

  Future<bool> _save({bool toast = false}) async {
    if (!_editable || _saving) return false;
    final snapshot = _snapshot();
    if (snapshot == _lastSnapshot) {
      if (_saveState != _SaveState.saved && mounted) {
        setState(() => _saveState = _SaveState.saved);
      }
      return true;
    }
    setState(() {
      _saving = true;
      _saveState = _SaveState.saving;
    });
    final res = await RentalFormsService.instance.update(
      widget.formId,
      title: _title.text,
      payload: _buildPayload(),
      involvedUserIds: _involved.map((u) => u.id).toList(),
    );
    if (!mounted) return false;
    setState(() {
      _saving = false;
      if (res.success && res.data != null) {
        final f = res.data!;
        // NÃO re-hidrata os campos (usuário pode estar digitando) — só o meta.
        _form = RentalForm({...?_form?.raw, ...f.raw});
        _status = f.status;
        _involved = f.involvedUsers.isNotEmpty || _involved.isEmpty
            ? List.of(f.involvedUsers)
            : _involved;
        _signatureHistory = f.signatureHistory;
        _lastSavedAt = f.updatedAt ?? DateTime.now();
        _lastSnapshot = snapshot;
        _saveState = _SaveState.saved;
        _dirtySinceOpen = true;
      } else {
        _saveState = _SaveState.error;
      }
    });
    if (toast) {
      _toast(
        res.success
            ? 'Alterações salvas.'
            : (res.message ?? 'Erro ao salvar.'),
        error: !res.success,
      );
    }
    return res.success;
  }

  // ── Finalização / assinatura ─────────────────────────────────────────────

  /// Valida os obrigatórios (perfil `editor` do web): cada aba só é exigida
  /// se foi iniciada. Retorna `(step, mensagem)` do primeiro problema.
  (int, String)? _validateForFinish() {
    for (final tab in RentalSectionKey.values) {
      final data = _data[tab]!;
      if (!rentalSectionHasContent(data)) continue;
      final required = rentalRequiredKeysForTab(tab, data);
      final missing = <String>[];
      for (final key in required) {
        if ((data[key] ?? '').trim().isEmpty) {
          missing.add(_labelForKey(tab, key));
        }
      }
      if (missing.isNotEmpty) {
        final step = RentalSectionKey.values.indexOf(tab) + 1;
        final list = missing.take(4).join(', ');
        final extra = missing.length > 4 ? '…' : '';
        return (step, '${tab.label}: preencha $list$extra');
      }
    }
    return null;
  }

  String _labelForKey(RentalSectionKey tab, String key) {
    final isPJ = tab == RentalSectionKey.inquilino &&
        (_data[tab]!['inquilinoTipoCadastro'] ?? '') == 'Pessoa Jurídica';
    for (final s in rentalSectionsForTab(tab, isPJ: isPJ)) {
      for (final f in s.fields) {
        if (f.key == key) return f.label;
      }
    }
    return key;
  }

  Future<void> _finish() async {
    if (_finishing || !_editable) return;
    final invalid = _validateForFinish();
    if (invalid != null) {
      _toast(invalid.$2, error: true);
      _goToStep(invalid.$1);
      return;
    }
    setState(() => _finishing = true);
    final saved = await _save();
    if (!saved) {
      if (mounted) setState(() => _finishing = false);
      return;
    }
    final res =
        await RentalFormsService.instance.generateSignatureLink(widget.formId);
    if (!mounted) return;
    setState(() => _finishing = false);
    if (!res.success || res.data == null) {
      _toast(
        res.message ?? 'Não foi possível finalizar a ficha.',
        error: true,
      );
      return;
    }
    final link = res.data!;
    if (RentalFormsService.isInvalidSignatureUrl(link.signatureUrl)) {
      _toast(
        'O backend retornou um link inválido. Gere novamente na Autentique.',
        error: true,
      );
      return;
    }
    setState(() {
      _status = RentalFormStatus.awaitingSignature;
      _signatureUrl = link.signatureUrl;
      _dirtySinceOpen = true;
    });
    _toast('Link de assinatura gerado.');
    _shareSignature();
    // Recarrega em segundo plano para trazer histórico atualizado.
    unawaited(_reloadSilently());
  }

  Future<void> _reloadSilently() async {
    final res = await RentalFormsService.instance.getById(widget.formId);
    if (!mounted || !res.success || res.data == null) return;
    setState(() => _applyForm(res.data!));
  }

  Future<void> _reopenForEditing() async {
    if (_finishing || !_canEdit) return;
    setState(() => _finishing = true);
    final res = await RentalFormsService.instance
        .update(widget.formId, status: RentalFormStatus.pending);
    if (!mounted) return;
    setState(() {
      _finishing = false;
      if (res.success && res.data != null) {
        _applyForm(res.data!);
        _dirtySinceOpen = true;
      }
    });
    _toast(
      res.success
          ? 'Ficha reaberta para edição.'
          : (res.message ?? 'Não foi possível reabrir a ficha.'),
      error: !res.success,
    );
  }

  void _shareSignature() {
    final url = _signatureUrl;
    if (url == null) return;
    RentalShareLinkSheet.show(
      context,
      title: 'Link de assinatura',
      subtitle: 'Envie para o cliente assinar a ficha.',
      url: url,
      whatsappMessage:
          'Olá! Segue o link para assinatura da ficha de locação:\n$url',
      icon: LucideIcons.signature,
    );
  }

  // ── Link público ─────────────────────────────────────────────────────────

  String get _publicUrl => RentalFormsService.publicUrl(
        _publicToken ?? '',
        type: _linkType,
      );

  Future<void> _generatePublicLink() async {
    if (_linkBusy || !_editable) return;
    setState(() => _linkBusy = true);
    final res = await RentalFormsService.instance
        .generatePublicLink(widget.formId, expirationDays: 30);
    if (!mounted) return;
    setState(() {
      _linkBusy = false;
      if (res.success && res.data != null) {
        _publicToken = res.data!.token;
        _publicExpiresAt = res.data!.expiresAt;
        _dirtySinceOpen = true;
      }
    });
    if (!res.success || res.data == null) {
      _toast(res.message ?? 'Não foi possível gerar o link.', error: true);
      return;
    }
    _toast('Link público gerado.');
    _sharePublicLink();
  }

  Future<void> _revokePublicLink() async {
    if (_linkBusy || !_editable) return;
    setState(() => _linkBusy = true);
    final res =
        await RentalFormsService.instance.revokePublicLink(widget.formId);
    if (!mounted) return;
    setState(() {
      _linkBusy = false;
      if (res.success) {
        _publicToken = null;
        _publicExpiresAt = null;
        _dirtySinceOpen = true;
      }
    });
    _toast(
      res.success ? 'Link revogado.' : (res.message ?? 'Erro ao revogar.'),
      error: !res.success,
    );
  }

  void _sharePublicLink() {
    if (_publicToken == null) return;
    final url = _publicUrl;
    final validade = _publicExpiresAt != null
        ? '\nVálido até ${DateFormat('dd/MM/yyyy', 'pt_BR').format(_publicExpiresAt!.toLocal())}.'
        : '';
    RentalShareLinkSheet.show(
      context,
      title: 'Link público da ficha',
      subtitle: _linkType == RentalPublicLinkType.completa
          ? 'O cliente preenche a ficha completa.'
          : 'O cliente preenche apenas: ${_linkType.label.toLowerCase()}.',
      url: url,
      whatsappMessage:
          'Olá! Segue o link para preencher a ficha de locação:\n$url$validade',
    );
  }

  // ── Envolvidos ───────────────────────────────────────────────────────────

  Future<void> _pickInvolvedUser() async {
    final u = await showModalBottomSheet<AdminUser>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UserPickerSheet(accent: _brand),
    );
    if (u == null || !mounted) return;
    if (_involved.any((x) => x.id == u.id)) return;
    setState(() {
      _involved = [
        ..._involved,
        RentalFormUser(id: u.id, name: u.name, email: u.email),
      ];
    });
    _scheduleAutosave();
  }

  void _removeInvolved(String id) {
    setState(() => _involved = _involved.where((u) => u.id != id).toList());
    _scheduleAutosave();
  }

  // ── Helpers de campo ─────────────────────────────────────────────────────

  TextEditingController _ctrl(RentalSectionKey tab, RentalField f) {
    final key = '$_reloadTick.${tab.payloadKey}.${f.key}';
    return _ctrls.putIfAbsent(key, () {
      var raw = _data[tab]![f.key] ?? '';
      if (f.type == RentalFieldType.money) {
        raw = raw.replaceFirst(RegExp(r'^R\$\s*'), '');
      }
      return TextEditingController(text: raw);
    });
  }

  void _setField(RentalSectionKey tab, String key, String value,
      {bool rebuild = false}) {
    _data[tab]![key] = value;
    if (rebuild) {
      setState(() {});
    }
    _scheduleAutosave();
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            error ? AppColors.status.error : AppColors.status.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Navegação dos passos ─────────────────────────────────────────────────

  void _goToStep(int i) {
    _pageCtrl.animateToPage(
      i,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _next(int total) {
    // Flush do autosave ao trocar de passo (não bloqueia a navegação).
    _debounce?.cancel();
    if (_editable) unawaited(_save());
    if (_step < total - 1) _goToStep(_step + 1);
  }

  void _back() {
    if (_step > 0) _goToStep(_step - 1);
  }

  Future<void> _exit() async {
    _debounce?.cancel();
    if (_editable) await _save();
    if (!mounted) return;
    Navigator.of(context).pop(_dirtySinceOpen);
  }

  // ── Tema local dos campos (idêntico ao editor da ficha de venda) ─────────

  ThemeData _formTheme(BuildContext context) {
    final base = Theme.of(context);
    final isDark = base.brightness == Brightness.dark;
    final fill = isDark
        ? Colors.white.withValues(alpha: 0.045)
        : Colors.black.withValues(alpha: 0.025);
    final muted = ThemeHelpers.textSecondaryColor(context);
    OutlineInputBorder b(Color c, double w) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              w == 0 ? BorderSide.none : BorderSide(color: c, width: w),
        );
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(primary: _brand),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: _brand,
        selectionColor: _brand.withValues(alpha: 0.18),
        selectionHandleColor: _brand,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fill,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        labelStyle: TextStyle(
            color: muted, fontWeight: FontWeight.w600, fontSize: 13.5),
        floatingLabelStyle: TextStyle(
            color: _brand, fontWeight: FontWeight.w700, fontSize: 13.5),
        hintStyle: TextStyle(
            color: muted.withValues(alpha: 0.7), fontWeight: FontWeight.w500),
        prefixStyle: TextStyle(
            color: ThemeHelpers.textColor(context),
            fontWeight: FontWeight.w700),
        border: b(Colors.transparent, 0),
        enabledBorder: b(Colors.transparent, 0),
        disabledBorder: b(Colors.transparent, 0),
        focusedBorder: b(_brand, 1.6),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return AppScaffold(
        title: 'Ficha de locação',
        currentBottomNavIndex: -1,
        showBottomNavigation: false,
        body: const _EditorSkeleton(),
      );
    }
    if (_loadError != null) {
      return AppScaffold(
        title: 'Ficha de locação',
        currentBottomNavIndex: -1,
        showBottomNavigation: false,
        body: _LoadError(message: _loadError!, onRetry: _load),
      );
    }

    final steps = _buildSteps();
    final step = steps[_step];

    return AppScaffold(
      title: 'Ficha de locação',
      currentBottomNavIndex: -1,
      showBottomNavigation: false,
      body: Column(
        children: [
          _StepHeader(
            index: _step,
            total: steps.length,
            title: step.title,
            subtitle: step.subtitle,
            icon: step.icon,
            color: _brand,
            status: _status,
            saveState: _editable ? _saveState : null,
            lastSavedAt: _lastSavedAt,
          ),
          if (!_editable) _ReadOnlyBanner(status: _status, canEdit: _canEdit),
          Expanded(
            child: Theme(
              data: _formTheme(context),
              child: PageView(
                controller: _pageCtrl,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _step = i),
                children: [
                  for (final s in steps)
                    ListView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                      children: s.content(),
                    ),
                ],
              ),
            ),
          ),
          _navBar(steps.length),
        ],
      ),
    );
  }

  List<
      ({
        String title,
        String subtitle,
        IconData icon,
        List<Widget> Function() content
      })> _buildSteps() {
    return [
      (
        title: 'Identificação',
        subtitle: 'Título e pessoas envolvidas',
        icon: LucideIcons.fileText,
        content: _sectionIdentificacao,
      ),
      (
        title: 'Inquilino',
        subtitle: RentalSectionKey.inquilino.hint,
        icon: LucideIcons.user,
        content: () => _tabContent(RentalSectionKey.inquilino),
      ),
      (
        title: 'Fiador',
        subtitle: RentalSectionKey.fiador.hint,
        icon: LucideIcons.shieldCheck,
        content: () => _tabContent(RentalSectionKey.fiador),
      ),
      (
        title: 'Proprietário',
        subtitle: RentalSectionKey.proprietario.hint,
        icon: LucideIcons.house,
        content: () => _tabContent(RentalSectionKey.proprietario),
      ),
      (
        title: 'Compartilhar & finalizar',
        subtitle: 'Link público e assinatura',
        icon: LucideIcons.send,
        content: _sectionCompartilhar,
      ),
    ];
  }

  Widget _navBar(int total) {
    final last = _step == total - 1;
    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border(
          top: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
      child: Row(
        children: [
          if (_step > 0) ...[
            OutlinedButton.icon(
              onPressed: _saving ? null : _back,
              style: OutlinedButton.styleFrom(
                foregroundColor: ThemeHelpers.textSecondaryColor(context),
                side: BorderSide(color: ThemeHelpers.borderColor(context)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(LucideIcons.arrowLeft, size: 16),
              label: const Text('Voltar',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: FilledButton.icon(
              onPressed: last ? _exit : () => _next(total),
              style: FilledButton.styleFrom(
                backgroundColor: _brand,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: Icon(last ? LucideIcons.check : LucideIcons.arrowRight,
                  size: 18),
              label: Text(
                last
                    ? (_editable ? 'Salvar e voltar' : 'Voltar à lista')
                    : 'Próximo',
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Passo 1: Identificação ───────────────────────────────────────────────

  List<Widget> _sectionIdentificacao() {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return [
      const RentalSectionBand(
        title: 'Identificação',
        hint: 'Título exibido na lista interna (opcional).',
        icon: LucideIcons.fileText,
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: _title,
          enabled: _editable,
          textCapitalization: TextCapitalization.sentences,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
          decoration: const InputDecoration(
            labelText: 'Título da ficha',
            hintText: 'Ex.: Apartamento 302 — Maria Silva',
          ),
        ),
      ),
      RentalSectionBand(
        title: 'Pessoas envolvidas',
        hint: 'Usuários internos que acompanham a ficha — não aparecem para '
            'quem acessa pelo link público.',
        icon: LucideIcons.users,
      ),
      if (_involved.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'Nenhum envolvido selecionado.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: muted, fontWeight: FontWeight.w600),
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final u in _involved)
                _InvolvedChip(
                  user: u,
                  accent: _brand,
                  onRemove: _editable ? () => _removeInvolved(u.id) : null,
                ),
            ],
          ),
        ),
      if (_editable)
        GestureDetector(
          onTap: _pickInvolvedUser,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 11),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _brand.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.userPlus, size: 15, color: _brand),
                const SizedBox(width: 6),
                Text(
                  'Adicionar envolvido',
                  style: TextStyle(
                    color: _brand,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 16),
      _MetaCard(form: _form, status: _status),
    ];
  }

  // ── Passos 2–4: abas do formulário ───────────────────────────────────────

  List<Widget> _tabContent(RentalSectionKey tab) {
    final data = _data[tab]!;
    final isPJ = tab == RentalSectionKey.inquilino &&
        (data['inquilinoTipoCadastro'] ?? '') == 'Pessoa Jurídica';
    final sections = rentalSectionsForTab(tab, isPJ: isPJ);
    final required = rentalRequiredKeysForTab(tab, data).toSet();

    final widgets = <Widget>[];
    for (final s in sections) {
      widgets.add(RentalSectionBand(
        title: s.title,
        hint: s.hint,
        icon: _iconForSection(s.id),
      ));
      widgets.addAll(_fieldsGrid(tab, s.fields, required));
    }
    widgets.add(const SizedBox(height: 6));
    return widgets;
  }

  IconData _iconForSection(String id) {
    switch (id) {
      case 'documentos':
      case 'inquilino-pj':
        return LucideIcons.idCard;
      case 'contato':
        return LucideIcons.phone;
      case 'endereco':
        return LucideIcons.mapPin;
      case 'trabalho':
        return LucideIcons.briefcase;
      case 'inquilino-complementar':
        return LucideIcons.clipboardList;
      case 'conjuge':
        return LucideIcons.users;
      case 'contrato':
        return LucideIcons.fileSignature;
      case 'referencias-locatario':
      case 'referencias':
        return LucideIcons.contact;
      case 'propriedades-fiador':
        return LucideIcons.house;
      case 'credito-proprietario':
        return LucideIcons.wallet;
      case 'documentacao-anexos':
        return LucideIcons.paperclip;
      default:
        return LucideIcons.fileText;
    }
  }

  bool _isFullWidth(RentalField f) =>
      f.full ||
      f.type == RentalFieldType.multiline ||
      f.type == RentalFieldType.multiSelect ||
      f.type == RentalFieldType.checkbox ||
      f.type == RentalFieldType.moradores;

  /// Pareia campos compactos em 2 colunas; campos `full` ocupam a linha.
  List<Widget> _fieldsGrid(
    RentalSectionKey tab,
    List<RentalField> fields,
    Set<String> required,
  ) {
    final out = <Widget>[];
    var i = 0;
    while (i < fields.length) {
      final f = fields[i];
      if (_isFullWidth(f)) {
        out.add(_buildField(tab, f, required.contains(f.key)));
        i++;
        continue;
      }
      final hasPair = i + 1 < fields.length && !_isFullWidth(fields[i + 1]);
      if (hasPair) {
        final g = fields[i + 1];
        out.add(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildField(tab, f, required.contains(f.key))),
            const SizedBox(width: 12),
            Expanded(child: _buildField(tab, g, required.contains(g.key))),
          ],
        ));
        i += 2;
      } else {
        out.add(_buildField(tab, f, required.contains(f.key)));
        i++;
      }
    }
    return out;
  }

  Widget _buildField(RentalSectionKey tab, RentalField f, bool required) {
    final data = _data[tab]!;
    switch (f.type) {
      case RentalFieldType.select:
        return RentalSelectField(
          label: f.label,
          value: data[f.key] ?? '',
          options: f.options ?? const [],
          enabled: _editable,
          required: required,
          onChanged: (v) => _setField(tab, f.key, v, rebuild: true),
        );
      case RentalFieldType.multiSelect:
        return RentalMultiSelectField(
          label: f.label,
          value: data[f.key] ?? '',
          options: f.options ?? const [],
          accent: _brand,
          enabled: _editable,
          onChanged: (v) => _setField(tab, f.key, v, rebuild: true),
        );
      case RentalFieldType.checkbox:
        return RentalCheckboxField(
          label: f.label,
          value: data[f.key] ?? '',
          accent: _brand,
          enabled: _editable,
          required: required,
          onChanged: (v) => _setField(tab, f.key, v, rebuild: true),
        );
      case RentalFieldType.moradores:
        return MoradoresEditor(
          key: ValueKey('moradores.${tab.payloadKey}.$_reloadTick'),
          value: data[f.key] ?? '',
          accent: _brand,
          enabled: _editable,
          onChanged: (v) => _setField(tab, f.key, v),
        );
      default:
        return _buildTextField(tab, f, required);
    }
  }

  Widget _buildTextField(RentalSectionKey tab, RentalField f, bool required) {
    final isMoney = f.type == RentalFieldType.money;
    TextInputType? keyboard;
    List<TextInputFormatter>? formatters;
    TextCapitalization cap = TextCapitalization.none;
    switch (f.type) {
      case RentalFieldType.cpf:
        keyboard = TextInputType.number;
        formatters = [CpfInputFormatter()];
        break;
      case RentalFieldType.cnpj:
        keyboard = TextInputType.number;
        formatters = [CnpjInputFormatter()];
        break;
      case RentalFieldType.phone:
        keyboard = TextInputType.phone;
        formatters = [PhoneInputFormatter()];
        break;
      case RentalFieldType.cep:
        keyboard = TextInputType.number;
        formatters = [CepInputFormatter()];
        break;
      case RentalFieldType.email:
        keyboard = TextInputType.emailAddress;
        break;
      case RentalFieldType.date:
        keyboard = TextInputType.number;
        formatters = [DateInputFormatter()];
        break;
      case RentalFieldType.money:
        keyboard = TextInputType.number;
        formatters = [CurrencyInputFormatter()];
        break;
      case RentalFieldType.number:
        keyboard = TextInputType.number;
        formatters = [NumericInputFormatter()];
        break;
      case RentalFieldType.rg:
        keyboard = TextInputType.text;
        break;
      default:
        cap = TextCapitalization.sentences;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _ctrl(tab, f),
        enabled: _editable,
        maxLines: f.type == RentalFieldType.multiline ? 3 : 1,
        keyboardType: keyboard,
        inputFormatters: formatters,
        textCapitalization: cap,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: required ? '${f.label} *' : f.label,
          hintText: f.hint,
          prefixText: isMoney ? 'R\$ ' : null,
        ),
        onChanged: (v) {
          // Moeda: valor salvo com prefixo 'R$ ' (paridade maskCurrencyReais).
          final stored =
              isMoney ? (v.trim().isEmpty ? '' : 'R\$ $v') : v;
          _setField(tab, f.key, stored);
        },
      ),
    );
  }

  // ── Passo 5: Compartilhar & finalizar ────────────────────────────────────

  List<Widget> _sectionCompartilhar() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final warn =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;

    final dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');

    return [
      // ── Observações internas ─────────────────────────────────────────
      const RentalSectionBand(
        title: 'Observações internas',
        hint: 'Visível apenas para a equipe — não aparece no link público.',
        icon: LucideIcons.stickyNote,
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: TextField(
          controller: _obs,
          enabled: _editable,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          style: theme.textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
          decoration: const InputDecoration(
            labelText: 'Observações',
            hintText: 'Anotações internas sobre a ficha…',
          ),
          onChanged: (_) => _scheduleAutosave(),
        ),
      ),

      // ── Link público ─────────────────────────────────────────────────
      const RentalSectionBand(
        title: 'Link público para o cliente',
        hint: 'Quem tiver o link pode preencher os blocos até a validade. '
            'Revogue se o link vazar.',
        icon: LucideIcons.link,
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in RentalPublicLinkType.values)
              _LinkTypeChip(
                label: t.label,
                selected: _linkType == t,
                accent: _brand,
                onTap: _editable
                    ? () => setState(() => _linkType = t)
                    : null,
              ),
          ],
        ),
      ),
      if (_publicToken != null) ...[
        _LinkBox(url: _publicUrl),
        if (_publicExpiresAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 2),
            child: Text(
              'Válido até ${dateFmt.format(_publicExpiresAt!.toLocal())}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _sharePublicLink,
                style: FilledButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13)),
                  elevation: 0,
                ),
                icon: const Icon(LucideIcons.share2, size: 16),
                label: const Text('Compartilhar',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _editable && !_linkBusy ? _generatePublicLink : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _brand,
                  side: BorderSide(color: _brand.withValues(alpha: 0.45)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13)),
                ),
                icon: const Icon(LucideIcons.refreshCw, size: 15),
                label: const Text('Renovar',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: _editable && !_linkBusy ? _revokePublicLink : null,
            style: TextButton.styleFrom(foregroundColor: muted),
            icon: const Icon(LucideIcons.ban, size: 14),
            label: const Text('Revogar link',
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 12.5)),
          ),
        ),
      ] else
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: FilledButton.icon(
            onPressed: _editable && !_linkBusy ? _generatePublicLink : null,
            style: FilledButton.styleFrom(
              backgroundColor: _brand,
              padding: const EdgeInsets.symmetric(vertical: 14),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            icon: _linkBusy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(LucideIcons.link, size: 17),
            label: Text(
              _linkBusy ? 'Gerando…' : 'Gerar link público (30 dias)',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),

      // ── Finalização ──────────────────────────────────────────────────
      const RentalSectionBand(
        title: 'Finalização da ficha',
        hint: 'Finalizar bloqueia edições e gera o link de assinatura '
            '(Autentique). Reabra para voltar a editar.',
        icon: LucideIcons.signature,
      ),
      if (_status == RentalFormStatus.pending && _canEdit)
        FilledButton.icon(
          onPressed: _finishing ? null : _finish,
          style: FilledButton.styleFrom(
            backgroundColor: _brand,
            padding: const EdgeInsets.symmetric(vertical: 14),
            minimumSize: const Size.fromHeight(48),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: _finishing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(LucideIcons.signature, size: 17),
          label: Text(
            _finishing
                ? 'Gerando link de assinatura…'
                : 'Finalizar e gerar assinatura',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      if (_status == RentalFormStatus.awaitingSignature &&
          _signatureUrl != null) ...[
        _LinkBox(url: _signatureUrl!),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _shareSignature,
          style: FilledButton.styleFrom(
            backgroundColor: green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
            minimumSize: const Size.fromHeight(46),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
            elevation: 0,
          ),
          icon: const Icon(LucideIcons.share2, size: 16),
          label: const Text('Compartilhar link de assinatura',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
      if ((_status == RentalFormStatus.finalized ||
              _status == RentalFormStatus.awaitingSignature) &&
          _canEdit) ...[
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _finishing ? null : _reopenForEditing,
          style: OutlinedButton.styleFrom(
            foregroundColor: warn,
            side: BorderSide(color: warn.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(vertical: 13),
            minimumSize: const Size.fromHeight(46),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          ),
          icon: const Icon(LucideIcons.penLine, size: 16),
          label: Text(
            _finishing ? 'Reabrindo…' : 'Reabrir para edição',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
      if (_status == RentalFormStatus.canceled)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Esta ficha está cancelada.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: muted, fontWeight: FontWeight.w700),
          ),
        ),

      // ── Histórico de assinaturas ─────────────────────────────────────
      if (_signatureHistory.isNotEmpty) ...[
        const RentalSectionBand(
          title: 'Histórico de assinaturas',
          icon: LucideIcons.history,
        ),
        for (final e in _signatureHistory.take(8))
          _SignatureHistoryTile(event: e),
      ],
      const SizedBox(height: 8),
    ];
  }
}

// ─── Widgets locais ─────────────────────────────────────────────────────────

/// Header do passo — flush com sublinhado na cor da marca + progresso +
/// linha de status/autosave (mesma gramática do `_StepHeader` da ficha de
/// venda).
class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.index,
    required this.total,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.status,
    required this.saveState,
    required this.lastSavedAt,
  });

  final int index;
  final int total;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final RentalFormStatus status;

  /// `null` quando a ficha não está editável (esconde a pill de autosave).
  final _SaveState? saveState;
  final DateTime? lastSavedAt;

  Color _statusTone(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    switch (status) {
      case RentalFormStatus.finalized:
        return dark
            ? AppColors.status.successDarkMode
            : AppColors.status.success;
      case RentalFormStatus.awaitingSignature:
        return dark
            ? AppColors.status.warningDarkMode
            : AppColors.status.warning;
      case RentalFormStatus.canceled:
        return dark ? AppColors.status.errorDarkMode : AppColors.status.error;
      case RentalFormStatus.pending:
        return dark ? AppColors.status.infoDarkMode : AppColors.status.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final frac = (index + 1) / total;
    final tone = _statusTone(context);

    String saveLabel = '';
    IconData saveIcon = LucideIcons.check;
    Color saveColor = muted;
    if (saveState != null) {
      final isDarkGreen = isDark
          ? AppColors.status.successDarkMode
          : AppColors.status.success;
      switch (saveState!) {
        case _SaveState.saved:
          final at = lastSavedAt != null
              ? ' às ${DateFormat('HH:mm', 'pt_BR').format(lastSavedAt!.toLocal())}'
              : '';
          saveLabel = 'Salvo$at';
          saveIcon = LucideIcons.checkCheck;
          saveColor = isDarkGreen;
          break;
        case _SaveState.saving:
          saveLabel = 'Salvando…';
          saveIcon = LucideIcons.refreshCw;
          saveColor = muted;
          break;
        case _SaveState.idle:
          saveLabel = 'Alterações pendentes';
          saveIcon = LucideIcons.clock3;
          saveColor = muted;
          break;
        case _SaveState.error:
          saveLabel = 'Falha ao salvar';
          saveIcon = LucideIcons.circleAlert;
          saveColor = isDark
              ? AppColors.status.errorDarkMode
              : AppColors.status.error;
          break;
      }
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border(
          bottom: BorderSide(color: color.withValues(alpha: 0.7), width: 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isDark ? 0.22 : 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -0.3,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Passo ${index + 1} de $total · $subtitle',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 4,
              backgroundColor:
                  ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(shape: BoxShape.circle, color: tone),
              ),
              const SizedBox(width: 6),
              Text(
                status.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
              if (saveState != null) ...[
                const Spacer(),
                Icon(saveIcon, size: 12, color: saveColor),
                const SizedBox(width: 5),
                Text(
                  saveLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: saveColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Banner discreto quando a ficha não está editável.
class _ReadOnlyBanner extends StatelessWidget {
  const _ReadOnlyBanner({required this.status, required this.canEdit});
  final RentalFormStatus status;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final warn =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final String msg;
    if (!canEdit) {
      msg = 'Você tem apenas permissão de leitura nesta ficha.';
    } else if (status == RentalFormStatus.awaitingSignature) {
      msg = 'Aguardando assinatura — reabra no último passo para editar.';
    } else if (status == RentalFormStatus.finalized) {
      msg = 'Ficha finalizada — reabra no último passo para editar.';
    } else {
      msg = 'Ficha cancelada — somente leitura.';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      color: warn.withValues(alpha: isDark ? 0.14 : 0.09),
      child: Row(
        children: [
          Icon(LucideIcons.info, size: 14, color: warn),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: warn,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.1,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Card de metadados da ficha (criador, datas) no passo de identificação.
class _MetaCard extends StatelessWidget {
  const _MetaCard({required this.form, required this.status});
  final RentalForm? form;
  final RentalFormStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
    final f = form;
    if (f == null) return const SizedBox.shrink();

    Widget row(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Icon(icon, size: 14, color: muted),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
              Text(
                value,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: ThemeHelpers.textColor(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border.all(
          color: ThemeHelpers.borderLightColor(context)
              .withValues(alpha: isDark ? 0.9 : 0.8),
        ),
      ),
      child: Column(
        children: [
          row(LucideIcons.user, 'RESPONSÁVEL', f.responsibleName),
          if (f.createdAt != null)
            row(LucideIcons.calendar, 'CRIADA',
                dateFmt.format(f.createdAt!.toLocal())),
          if (f.submittedAt != null)
            row(LucideIcons.checkCircle2, 'FINALIZADA',
                dateFmt.format(f.submittedAt!.toLocal())),
          row(LucideIcons.flag, 'STATUS', status.label),
        ],
      ),
    );
  }
}

class _InvolvedChip extends StatelessWidget {
  const _InvolvedChip({
    required this.user,
    required this.accent,
    this.onRemove,
  });
  final RentalFormUser user;
  final Color accent;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 5, 10, 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.16),
            ),
            child: Text(
              user.initials,
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w900,
                fontSize: 9,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            user.name.split(' ').first,
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onRemove,
              child: Icon(LucideIcons.x, size: 14, color: accent),
            ),
          ],
        ],
      ),
    );
  }
}

class _LinkTypeChip extends StatelessWidget {
  const _LinkTypeChip({
    required this.label,
    required this.selected,
    required this.accent,
    this.onTap,
  });
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.5)
                : ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12,
            color: selected ? accent : muted,
          ),
        ),
      ),
    );
  }
}

/// Caixa de link (monoespaçado suave) — paridade com o `LinkBox` do web,
/// com toque para copiar.
class _LinkBox extends StatelessWidget {
  const _LinkBox({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    return InkWell(
      onTap: () async {
        final messenger = ScaffoldMessenger.of(context);
        await Clipboard.setData(ClipboardData(text: url));
        messenger.showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Link copiado!'),
          ),
        );
      },
      borderRadius: BorderRadius.circular(13),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          color: isDark
              ? Colors.white.withValues(alpha: 0.045)
              : Colors.black.withValues(alpha: 0.03),
          border: Border.all(color: ThemeHelpers.borderLightColor(context)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                url,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textColor(context),
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(LucideIcons.copy, size: 15, color: muted),
          ],
        ),
      ),
    );
  }
}

class _SignatureHistoryTile extends StatelessWidget {
  const _SignatureHistoryTile({required this.event});
  final RentalSignatureEvent event;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final Color tone;
    switch (event.eventType) {
      case 'signed':
        tone = isDark
            ? AppColors.status.successDarkMode
            : AppColors.status.success;
        break;
      case 'canceled':
        tone = isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
        break;
      default:
        tone = isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
    }
    final date = event.createdAt != null
        ? DateFormat('dd/MM/yyyy HH:mm', 'pt_BR')
            .format(event.createdAt!.toLocal())
        : '—';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        color: tone.withValues(alpha: isDark ? 0.10 : 0.07),
        border: Border.all(color: tone.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: tone),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 76,
            child: Text(
              event.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: tone,
              ),
            ),
          ),
          Expanded(
            child: Text(
              date,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: muted,
              ),
            ),
          ),
          if (event.actorUserName != null)
            Flexible(
              child: Text(
                event.actorUserName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Skeleton do editor — header do passo + campos (fiel ao layout real).
class _EditorSkeleton extends StatelessWidget {
  const _EditorSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget box(double w, double h, {double r = 10}) => _ShimmerBox(
          width: w,
          height: h,
          radius: r,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color:
                    ThemeHelpers.borderColor(context).withValues(alpha: 0.6),
                width: 2,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  box(42, 42, r: 13),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      box(150, 15),
                      const SizedBox(height: 7),
                      box(190, 11),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              box(double.infinity, 4, r: 3),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              box(170, 12),
              const SizedBox(height: 16),
              box(double.infinity, 48, r: 14),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: box(double.infinity, 48, r: 14)),
                  const SizedBox(width: 12),
                  Expanded(child: box(double.infinity, 48, r: 14)),
                ],
              ),
              const SizedBox(height: 12),
              box(double.infinity, 48, r: 14),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: box(double.infinity, 48, r: 14)),
                  const SizedBox(width: 12),
                  Expanded(child: box(double.infinity, 48, r: 14)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  const _ShimmerBox({
    required this.width,
    required this.height,
    required this.radius,
  });
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black)
            .withValues(alpha: isDark ? 0.07 : 0.06),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final accent = Theme.of(context).brightness == Brightness.dark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.cloudOff, size: 52, color: muted),
            const SizedBox(height: 12),
            Text(
              'Não foi possível abrir a ficha',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: muted),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(color: accent.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text(
                'Tentar novamente',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sheet de seleção de usuário da empresa (mesma gramática do picker da
/// ficha de venda) — usado para "Pessoas envolvidas".
class _UserPickerSheet extends StatefulWidget {
  const _UserPickerSheet({required this.accent});
  final Color accent;

  @override
  State<_UserPickerSheet> createState() => _UserPickerSheetState();
}

class _UserPickerSheetState extends State<_UserPickerSheet> {
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  List<AdminUser> _users = [];
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await AdminUsersService.instance.listUsers(
      limit: 100,
      search: _q.isEmpty ? null : _q,
      compact: true,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _users = res.data!.users;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          18, 10, 18, 14 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: ThemeHelpers.borderColor(context),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _searchCtrl,
            onSubmitted: (v) {
              _q = v.trim();
              _load();
            },
            decoration: InputDecoration(
              hintText: 'Buscar usuário…',
              prefixIcon: const Icon(LucideIcons.search, size: 18),
              isDense: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _users.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text('Nenhum usuário encontrado.',
                            style: TextStyle(color: secondary)),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: _users.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 4),
                        itemBuilder: (_, i) {
                          final u = _users[i];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor:
                                  widget.accent.withValues(alpha: 0.15),
                              child: Text(
                                u.name.isNotEmpty
                                    ? u.name[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                    color: widget.accent,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13),
                              ),
                            ),
                            title: Text(u.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            subtitle: Text(u.email,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            onTap: () => Navigator.of(context).pop(u),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
