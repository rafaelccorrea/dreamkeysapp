import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../models/kanban_models.dart';
import '../services/kanban_service.dart';

/// Modal de configuração da cadência WhatsApp automática de uma coluna.
/// Espelha o `ColumnCadenceModal` da web (canais oficial/não-oficial,
/// tentativas, intervalos e ações ao responder / não responder).
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
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
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: Center(
                  child: Container(
                    width: 44,
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
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
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
        const SizedBox(height: 14),
        _buildSection(
          context,
          icon: Icons.schedule_outlined,
          accent: accent,
          title: 'Quando enviar',
          description: 'Tempo na coluna antes do 1º disparo automático.',
          child: _numberField(
            controller: _sendAfterController,
            label: 'Enviar após (minutos na coluna)',
            accent: accent,
          ),
        ),
        const SizedBox(height: 14),
        _buildSection(
          context,
          icon: Icons.forum_outlined,
          accent: accent,
          title: 'Canal e mensagem',
          description: 'Oficial usa template aprovado; não-oficial, texto livre.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ChipChoice(
                    label: 'Oficial (template)',
                    selected: _channel == 'official',
                    accent: accent,
                    onTap: () {
                      setState(() => _channel = 'official');
                      _loadTemplates();
                    },
                  ),
                  _ChipChoice(
                    label: 'Não-oficial (texto)',
                    selected: _channel == 'unofficial',
                    accent: accent,
                    onTap: () => setState(() => _channel = 'unofficial'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (_channel == 'official') ...[
                _templateDropdown(context, accent),
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
        const SizedBox(height: 14),
        _buildSection(
          context,
          icon: Icons.repeat_rounded,
          accent: accent,
          title: 'Tentativas',
          description: 'Quantos disparos e o intervalo entre eles.',
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
        const SizedBox(height: 14),
        _buildSection(
          context,
          icon: Icons.call_split_rounded,
          accent: accent,
          title: 'Ações',
          description: 'O que fazer quando o lead responde ou não responde.',
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
                _columnDropdown(
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
                _columnDropdown(
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
        const SizedBox(height: 12),
        Text(
          _loadError!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
    ];
  }

  Widget _enabledTile(BuildContext context, Color accent) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: _enabled
            ? accent.withValues(alpha: 0.08)
            : ThemeHelpers.cardBackgroundColor(context),
        border: Border.all(
          color: _enabled
              ? accent.withValues(alpha: 0.45)
              : ThemeHelpers.borderColor(context).withValues(alpha: 0.42),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: accent.withValues(alpha: 0.14),
            ),
            child: Icon(Icons.schedule_send_outlined, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cadência automática',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _enabled
                      ? 'Ativa nesta coluna'
                      : 'Desligada — leads não recebem follow-up',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
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
    );
  }

  Widget _templateDropdown(BuildContext context, Color accent) {
    if (_loadingTemplates) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    }
    final names = _templates.map((t) => t.name).toSet().toList()..sort();
    // Garante que um template já salvo apareça mesmo se não veio na lista.
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
    return DropdownButtonFormField<String>(
      initialValue: _templateName,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Template aprovado',
        prefixIcon: Icon(Icons.description_outlined, color: accent),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: [
        for (final n in names)
          DropdownMenuItem(value: n, child: Text(n, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (v) => setState(() => _templateName = v),
    );
  }

  Widget _columnDropdown(
    BuildContext context,
    Color accent, {
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    final cols = widget.siblingColumns;
    final validValue =
        cols.any((c) => c.id == value) ? value : null;
    return DropdownButtonFormField<String>(
      initialValue: validValue,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Coluna de destino',
        prefixIcon: Icon(Icons.view_column_outlined, color: accent),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: [
        for (final c in cols)
          DropdownMenuItem(
            value: c.id,
            child: Text(c.title, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [accent, const Color(0xFF075E54)],
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.32),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.schedule_send_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cadência WhatsApp',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
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

  Widget _buildSection(
    BuildContext context, {
    required IconData icon,
    required Color accent,
    required String title,
    required String description,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.42),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                  spreadRadius: -3,
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: accent.withValues(alpha: isDark ? 0.16 : 0.10),
                    border: Border.all(color: accent.withValues(alpha: 0.22)),
                  ),
                  child: Icon(icon, color: accent, size: 19),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
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
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('Cancelar'),
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
                _saving ? 'Salvando...' : 'Salvar',
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

class _ChipChoice extends StatelessWidget {
  const _ChipChoice({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.accent,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected ? Colors.white : ThemeHelpers.textColor(context);
    final bg = selected ? accent : ThemeHelpers.cardBackgroundColor(context);
    final border =
        selected ? accent : ThemeHelpers.borderLightColor(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.30),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: fg,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.1,
          ),
        ),
      ),
    );
  }
}
