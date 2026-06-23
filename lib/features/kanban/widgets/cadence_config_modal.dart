import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../models/kanban_models.dart';
import '../services/kanban_service.dart';

/// Modal de configuração da cadência WhatsApp automática de uma coluna.
/// Espelha o `ColumnCadenceModal` da web — canais oficial/não-oficial,
/// tentativas, intervalos e ações ao responder / não responder.
///
/// Design flush (paridade com o drawer de filtros): seções abertas separadas
/// por filete tracejado + eyebrow com dot; campos em pill; selects próprios
/// (picker em bottom-sheet, nada de dropdown nativo); cor de tela coerente —
/// verde do WhatsApp como accent, neutro no "Cancelar".
class CadenceConfigModal extends StatefulWidget {
  final KanbanColumn column;
  final List<KanbanColumn> siblingColumns;
  final VoidCallback? onSaved;

  const CadenceConfigModal({
    super.key,
    required this.column,
    required this.siblingColumns,
    this.onSaved,
  });

  @override
  State<CadenceConfigModal> createState() => _CadenceConfigModalState();
}

class _CadenceConfigModalState extends State<CadenceConfigModal> {
  final _service = KanbanService.instance;

  final _messageController = TextEditingController();
  final _sendAfterController = TextEditingController(text: '120');
  final _maxAttemptsController = TextEditingController(text: '1');
  final _resendController = TextEditingController(text: '1440');
  final _waitReplyController = TextEditingController(text: '1440');
  final _templateLangController = TextEditingController(text: 'pt_BR');

  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  bool _enabled = false;
  String _channel = 'official';
  String? _templateName;
  List<WhatsappTemplate> _templates = const [];
  bool _loadingTemplates = false;

  String _onNoReplyAction = 'move_column';
  String? _noReplyTargetColumnId;
  String _onReplyAction = 'stop';
  String? _replyTargetColumnId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _sendAfterController.dispose();
    _maxAttemptsController.dispose();
    _resendController.dispose();
    _waitReplyController.dispose();
    _templateLangController.dispose();
    super.dispose();
  }

  Color _fieldFill(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
          ? AppColors.background.backgroundTertiaryDarkMode
          : AppColors.background.backgroundTertiary;

  Future<void> _load() async {
    final res = await _service.getColumnCadence(widget.column.id);
    if (!mounted) return;
    if (res.success && res.data != null) {
      _applyConfig(res.data!);
      setState(() => _loading = false);
    } else {
      // Sem config ainda — usa defaults.
      setState(() {
        _loading = false;
        _loadError = res.statusCode == 404 ? null : res.message;
      });
    }
    if (_channel == 'official') _loadTemplates();
  }

  void _applyConfig(KanbanColumnCadenceConfig c) {
    _enabled = c.enabled;
    _channel = c.channel;
    _templateName = (c.templateName ?? '').isEmpty ? null : c.templateName;
    _templateLangController.text = c.templateLanguage ?? 'pt_BR';
    _messageController.text = c.messageText ?? '';
    _sendAfterController.text = '${c.sendAfterMinutes}';
    _maxAttemptsController.text = '${c.maxAttempts}';
    _resendController.text = '${c.resendIntervalMinutes}';
    _waitReplyController.text = '${c.waitReplyMinutes}';
    _onNoReplyAction = c.onNoReplyAction;
    _noReplyTargetColumnId = c.noReplyTargetColumnId;
    _onReplyAction = c.onReplyAction;
    _replyTargetColumnId = c.replyTargetColumnId;
  }

  Future<void> _loadTemplates() async {
    if (_templates.isNotEmpty || _loadingTemplates) return;
    setState(() => _loadingTemplates = true);
    final res = await _service.listWhatsappTemplates();
    if (!mounted) return;
    setState(() {
      _loadingTemplates = false;
      if (res.success && res.data != null) _templates = res.data!;
    });
  }

  int _intOf(TextEditingController c, int fallback) =>
      int.tryParse(c.text.trim()) ?? fallback;

  KanbanColumnCadenceConfig _buildConfig() {
    return KanbanColumnCadenceConfig(
      enabled: _enabled,
      sendAfterMinutes: _intOf(_sendAfterController, 120),
      channel: _channel,
      messageText: _messageController.text.trim(),
      templateName: _templateName ?? '',
      templateLanguage: _templateLangController.text.trim().isEmpty
          ? 'pt_BR'
          : _templateLangController.text.trim(),
      maxAttempts: _intOf(_maxAttemptsController, 1),
      resendIntervalMinutes: _intOf(_resendController, 1440),
      waitReplyMinutes: _intOf(_waitReplyController, 1440),
      onNoReplyAction: _onNoReplyAction,
      noReplyTargetColumnId:
          _onNoReplyAction == 'move_column' ? _noReplyTargetColumnId : null,
      onReplyAction: _onReplyAction,
      replyTargetColumnId:
          _onReplyAction == 'move_column' ? _replyTargetColumnId : null,
    );
  }

  String? _validate(KanbanColumnCadenceConfig c) {
    if (!c.enabled) return null;
    if (c.channel == 'official' && (c.templateName ?? '').isEmpty) {
      return 'Selecione um template aprovado para o canal oficial.';
    }
    if (c.channel == 'unofficial' && (c.messageText ?? '').isEmpty) {
      return 'Escreva a mensagem para o canal não-oficial.';
    }
    if (c.onNoReplyAction == 'move_column' && c.noReplyTargetColumnId == null) {
      return 'Escolha a coluna de destino para "sem resposta".';
    }
    if (c.onReplyAction == 'move_column' && c.replyTargetColumnId == null) {
      return 'Escolha a coluna de destino para "ao responder".';
    }
    return null;
  }

  Future<void> _save() async {
    final config = _buildConfig();
    final err = _validate(config);
    if (err != null) {
      _snack(err);
      return;
    }
    setState(() => _saving = true);
    final res = await _service.updateColumnCadence(widget.column.id, config);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.success) {
      widget.onSaved?.call();
      Navigator.of(context).pop();
      _snack('Cadência salva.');
    } else {
      _snack(res.message ?? 'Não foi possível salvar a cadência.');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Cor de tela coerente: verde do WhatsApp (não vermelho da marca).
    final accent = isDark ? const Color(0xFF25D366) : const Color(0xFF128C7E);
    final mq = MediaQuery.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: ThemeHelpers.backgroundColor(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.40),
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: ThemeHelpers.borderColor(context)
                          .withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
              _buildHeader(context, accent),
              Expanded(
                child: _loading
                    ? Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: accent,
                          ),
                        ),
                      )
                    : ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                        children: _buildBody(context, accent),
                      ),
              ),
              _buildFooter(context, accent, mq),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildBody(BuildContext context, Color accent) {
    return [
      _enabledTile(context, accent),
      if (_enabled) ...[
        _section(
          context,
          accent: accent,
          label: 'Quando enviar',
          hint: 'Tempo na coluna antes do 1º disparo automático.',
          child: _numberField(
            controller: _sendAfterController,
            label: 'Enviar após (minutos na coluna)',
            accent: accent,
          ),
        ),
        _section(
          context,
          accent: accent,
          label: 'Canal e mensagem',
          hint: 'Oficial usa template aprovado; não-oficial, texto livre.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ChipChoice(
                    label: 'Oficial (template)',
                    icon: Icons.verified_outlined,
                    selected: _channel == 'official',
                    accent: accent,
                    onTap: () {
                      setState(() => _channel = 'official');
                      _loadTemplates();
                    },
                  ),
                  _ChipChoice(
                    label: 'Não-oficial (texto)',
                    icon: Icons.edit_outlined,
                    selected: _channel == 'unofficial',
                    accent: accent,
                    onTap: () => setState(() => _channel = 'unofficial'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (_channel == 'official') ...[
                _templateSelect(context, accent),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _templateLangController,
                  label: 'Idioma do template (ex.: pt_BR)',
                  prefixIcon: const Icon(Icons.language_outlined),
                ),
              ] else
                CustomTextField(
                  controller: _messageController,
                  label: 'Mensagem',
                  hint: 'Olá! Vi que você tem interesse...',
                  maxLines: 4,
                ),
            ],
          ),
        ),
        _section(
          context,
          accent: accent,
          label: 'Tentativas',
          hint: 'Quantos disparos e o intervalo entre eles.',
          child: Column(
            children: [
              _numberField(
                controller: _maxAttemptsController,
                label: 'Máximo de tentativas',
                accent: accent,
                onChanged: (_) => setState(() {}),
              ),
              if (_intOf(_maxAttemptsController, 1) > 1) ...[
                const SizedBox(height: 12),
                _numberField(
                  controller: _resendController,
                  label: 'Intervalo entre reenvios (minutos)',
                  accent: accent,
                ),
              ],
              const SizedBox(height: 12),
              _numberField(
                controller: _waitReplyController,
                label: 'Aguardar resposta (minutos)',
                accent: accent,
              ),
            ],
          ),
        ),
        _section(
          context,
          accent: accent,
          label: 'Ações',
          hint: 'O que fazer quando o lead responde ou não responde.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fieldLabel(context, 'Se não responder'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ChipChoice(
                    label: 'Mover de coluna',
                    selected: _onNoReplyAction == 'move_column',
                    accent: accent,
                    onTap: () =>
                        setState(() => _onNoReplyAction = 'move_column'),
                  ),
                  _ChipChoice(
                    label: 'Não fazer nada',
                    selected: _onNoReplyAction == 'none',
                    accent: accent,
                    onTap: () => setState(() => _onNoReplyAction = 'none'),
                  ),
                ],
              ),
              if (_onNoReplyAction == 'move_column') ...[
                const SizedBox(height: 12),
                _columnSelect(
                  context,
                  accent,
                  value: _noReplyTargetColumnId,
                  onChanged: (v) =>
                      setState(() => _noReplyTargetColumnId = v),
                ),
              ],
              const SizedBox(height: 18),
              _fieldLabel(context, 'Ao responder'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ChipChoice(
                    label: 'Parar cadência',
                    selected: _onReplyAction == 'stop',
                    accent: accent,
                    onTap: () => setState(() => _onReplyAction = 'stop'),
                  ),
                  _ChipChoice(
                    label: 'Mover de coluna',
                    selected: _onReplyAction == 'move_column',
                    accent: accent,
                    onTap: () =>
                        setState(() => _onReplyAction = 'move_column'),
                  ),
                ],
              ),
              if (_onReplyAction == 'move_column') ...[
                const SizedBox(height: 12),
                _columnSelect(
                  context,
                  accent,
                  value: _replyTargetColumnId,
                  onChanged: (v) => setState(() => _replyTargetColumnId = v),
                ),
              ],
            ],
          ),
        ),
      ],
      if (_loadError != null) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: AppColors.status.warning.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.status.warning.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 18, color: AppColors.status.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _loadError!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ),
      ],
    ];
  }

  /// Toggle-mestre da cadência. Superfície leve (é o controle de liga/desliga),
  /// não um card de conteúdo — fica claro o estado ativo.
  Widget _enabledTile(BuildContext context, Color accent) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: _enabled
              ? accent.withValues(alpha: isDark ? 0.12 : 0.07)
              : _fieldFill(context),
          border: Border.all(
            color: _enabled
                ? accent.withValues(alpha: 0.40)
                : ThemeHelpers.borderLightColor(context),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                color: accent.withValues(alpha: isDark ? 0.20 : 0.14),
              ),
              child:
                  Icon(Icons.schedule_send_outlined, color: accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cadência automática',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _enabled
                        ? 'Ativa nesta coluna'
                        : 'Desligada — leads não recebem follow-up',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: _enabled
                          ? accent
                          : ThemeHelpers.textSecondaryColor(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: _enabled,
              activeThumbColor: accent,
              onChanged: (v) {
                setState(() => _enabled = v);
                if (v && _channel == 'official') _loadTemplates();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Seção flush: filete tracejado + eyebrow com dot + hint + conteúdo.
  Widget _section(
    BuildContext context, {
    required Color accent,
    required String label,
    String? hint,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DashedLine(color: ThemeHelpers.borderLightColor(context)),
          const SizedBox(height: 18),
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.45),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
              ),
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(
              hint,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                height: 1.3,
                color: ThemeHelpers.textSecondaryColor(context)
                    .withValues(alpha: 0.85),
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  /// Pill no padrão FilterControl (chip de ícone + conteúdo).
  Widget _filterControl(
    BuildContext context, {
    required IconData icon,
    required Color accent,
    required Widget child,
    VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final control = Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
      decoration: BoxDecoration(
        color: _fieldFill(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ThemeHelpers.borderLightColor(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.20 : 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(child: child),
        ],
      ),
    );
    if (onTap == null) return control;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: control,
    );
  }

  /// Select próprio (substitui o dropdown nativo): pill com valor/placeholder
  /// + chevron, abre um picker estilizado em bottom-sheet.
  Widget _select({
    required BuildContext context,
    required IconData icon,
    required Color accent,
    required String placeholder,
    String? valueLabel,
    required VoidCallback onTap,
  }) {
    final hasValue = valueLabel != null && valueLabel.isNotEmpty;
    return _filterControl(
      context,
      icon: icon,
      accent: accent,
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Text(
              hasValue ? valueLabel : placeholder,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: hasValue
                    ? ThemeHelpers.textColor(context)
                    : ThemeHelpers.textSecondaryColor(context)
                        .withValues(alpha: 0.9),
              ),
            ),
          ),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 20,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
        ],
      ),
    );
  }

  Future<void> _openPicker({
    required String title,
    required List<_Option> options,
    required String? selected,
    required Color accent,
    required ValueChanged<String> onSelected,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final mq = MediaQuery.of(ctx);
        return Container(
          constraints: BoxConstraints(maxHeight: mq.size.height * 0.7),
          decoration: BoxDecoration(
            color: ThemeHelpers.backgroundColor(ctx),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(
              color: ThemeHelpers.borderColor(ctx).withValues(alpha: 0.40),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: ThemeHelpers.borderColor(ctx)
                          .withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: ThemeHelpers.textColor(ctx),
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + mq.padding.bottom),
                  itemCount: options.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (_, i) {
                    final o = options[i];
                    final isSel = o.value == selected;
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        onSelected(o.value);
                        Navigator.of(ctx).pop();
                      },
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                        decoration: BoxDecoration(
                          color: isSel
                              ? accent.withValues(alpha: 0.10)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSel
                                ? accent.withValues(alpha: 0.45)
                                : ThemeHelpers.borderLightColor(ctx),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                o.label,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight:
                                      isSel ? FontWeight.w700 : FontWeight.w600,
                                  color: isSel
                                      ? accent
                                      : ThemeHelpers.textColor(ctx),
                                ),
                              ),
                            ),
                            if (isSel)
                              Icon(Icons.check_rounded,
                                  size: 18, color: accent),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _templateSelect(BuildContext context, Color accent) {
    if (_loadingTemplates) {
      return _filterControl(
        context,
        icon: Icons.description_outlined,
        accent: accent,
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: accent),
            ),
            const SizedBox(width: 10),
            Text(
              'Carregando templates…',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
          ],
        ),
      );
    }
    final names = _templates.map((t) => t.name).toSet().toList()..sort();
    if (_templateName != null && !names.contains(_templateName)) {
      names.insert(0, _templateName!);
    }
    if (names.isEmpty) {
      return Text(
        'Nenhum template aprovado encontrado. Use o canal não-oficial ou '
        'cadastre um template na integração oficial.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w600,
            ),
      );
    }
    return _select(
      context: context,
      icon: Icons.description_outlined,
      accent: accent,
      placeholder: 'Selecionar template aprovado',
      valueLabel: _templateName,
      onTap: () => _openPicker(
        title: 'Template aprovado',
        accent: accent,
        selected: _templateName,
        options: [for (final n in names) _Option(n, n)],
        onSelected: (v) => setState(() => _templateName = v),
      ),
    );
  }

  Widget _columnSelect(
    BuildContext context,
    Color accent, {
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    final cols = widget.siblingColumns;
    final validValue = cols.any((c) => c.id == value) ? value : null;
    final selectedTitle = validValue == null
        ? null
        : cols.firstWhere((c) => c.id == validValue).title;
    return _select(
      context: context,
      icon: Icons.view_column_outlined,
      accent: accent,
      placeholder: 'Escolher coluna de destino',
      valueLabel: selectedTitle,
      onTap: () => _openPicker(
        title: 'Coluna de destino',
        accent: accent,
        selected: validValue,
        options: [for (final c in cols) _Option(c.id, c.title)],
        onSelected: (v) => onChanged(v),
      ),
    );
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    required Color accent,
    ValueChanged<String>? onChanged,
  }) {
    return CustomTextField(
      controller: controller,
      label: label,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      prefixIcon: Icon(Icons.timer_outlined, color: accent),
      onChanged: onChanged,
    );
  }

  Widget _fieldLabel(BuildContext context, String label) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: ThemeHelpers.textColor(context),
          ),
    );
  }

  Widget _buildHeader(BuildContext context, Color accent) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 4, 10, 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: accent.withValues(alpha: isDark ? 0.20 : 0.12),
            ),
            child: Icon(Icons.schedule_send_rounded, color: accent, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cadência WhatsApp',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.column.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Fechar',
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context, Color accent, MediaQueryData mq) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + mq.padding.bottom),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border(
          top: BorderSide(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                // Neutro: nada de vermelho num botão secundário.
                foregroundColor: ThemeHelpers.textSecondaryColor(context),
                side: BorderSide(color: ThemeHelpers.borderColor(context)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Cancelar',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(
                _saving ? 'Salvando...' : 'Salvar cadência',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Option {
  const _Option(this.value, this.label);
  final String value;
  final String label;
}

/// Chip de seleção — ativo usa *tint* (sem preenchimento sólido candy).
class _ChipChoice extends StatelessWidget {
  const _ChipChoice({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.accent,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fieldFill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    final fg = selected
        ? accent
        : ThemeHelpers.textColor(context).withValues(alpha: 0.82);
    final bg =
        selected ? accent.withValues(alpha: isDark ? 0.18 : 0.10) : fieldFill;
    final border =
        selected ? accent : ThemeHelpers.borderLightColor(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border, width: selected ? 1.2 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontSize: 12.5,
                color: fg,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Filete tracejado fino — separa seções como na web.
class _DashedLine extends StatelessWidget {
  const _DashedLine({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      width: double.infinity,
      child: CustomPaint(painter: _DashedPainter(color)),
    );
  }
}

class _DashedPainter extends CustomPainter {
  _DashedPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const dash = 5.0;
    const gap = 4.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dash, 0), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedPainter oldDelegate) =>
      oldDelegate.color != color;
}
