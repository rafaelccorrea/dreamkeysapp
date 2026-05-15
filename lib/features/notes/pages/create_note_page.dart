import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/notes_service.dart';

const _noteColors = [
  '#3B82F6',
  '#10B981',
  '#F59E0B',
  '#EF4444',
  '#8B5CF6',
  '#06B6D4',
  '#84CC16',
  '#F97316',
  '#EC4899',
  '#6366F1',
];

const _priorities = <String, ({String label, Color tone})>{
  'low': (label: 'Baixa', tone: Color(0xFF64748B)),
  'medium': (label: 'Média', tone: Color(0xFF3B82F6)),
  'high': (label: 'Alta', tone: Color(0xFFF97316)),
  'urgent': (label: 'Urgente', tone: Color(0xFFDC2626)),
};

/// Abre formulário de criação como popup elevado (paridade com detalhe da nota).
Future<bool?> showCreateNoteSheet(
  BuildContext context, {
  required Color accent,
}) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Fechar',
    barrierColor: Colors.black.withValues(alpha: 0.58),
    transitionDuration: const Duration(milliseconds: 340),
    pageBuilder: (context, animation, secondaryAnimation) {
      return _CreateNoteOverlay(accent: accent);
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.06),
            end: Offset.zero,
          ).animate(curved),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}

/// Mantido para rotas legadas — prefira [showCreateNoteSheet].
class CreateNotePage extends StatelessWidget {
  const CreateNotePage({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).brightness == Brightness.dark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      showCreateNoteSheet(context, accent: accent).then((created) {
        if (created == true && context.mounted) {
          Navigator.of(context).pop(true);
        } else if (context.mounted) {
          Navigator.of(context).maybePop();
        }
      });
    });
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: SizedBox.shrink(),
    );
  }
}

class _CreateNoteOverlay extends StatefulWidget {
  const _CreateNoteOverlay({required this.accent});

  final Color accent;

  @override
  State<_CreateNoteOverlay> createState() => _CreateNoteOverlayState();
}

class _CreateNoteOverlayState extends State<_CreateNoteOverlay> {
  final _title = TextEditingController();
  final _content = TextEditingController();
  final _clientName = TextEditingController();
  final _clientPhone = TextEditingController();
  final _clientEmail = TextEditingController();
  final _tagInput = TextEditingController();

  String _priority = 'medium';
  String _color = _noteColors.first;
  bool _pinned = false;
  bool _hasReminder = false;
  bool _clientExpanded = false;
  DateTime? _reminderAt;
  final List<String> _tags = [];
  bool _submitting = false;

  Color get _noteColor => _parseHex(_color);

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _clientName.dispose();
    _clientPhone.dispose();
    _clientEmail.dispose();
    _tagInput.dispose();
    super.dispose();
  }

  void _addTag() {
    final t = _tagInput.text.trim();
    if (t.isEmpty) return;
    if (_tags.length >= 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Máximo de 8 tags.')),
      );
      return;
    }
    if (_tags.contains(t)) return;
    setState(() {
      _tags.add(t);
      _tagInput.clear();
    });
  }

  Future<void> _pickReminder() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _reminderAt ?? now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
      locale: const Locale('pt', 'BR'),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_reminderAt ?? now),
    );
    if (time == null || !mounted) return;
    setState(() {
      _reminderAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _hasReminder = true;
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final t = _title.text.trim();
    if (t.isEmpty) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um título.')),
      );
      return;
    }
    if (_hasReminder && _reminderAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Defina data e hora do lembrete.')),
      );
      return;
    }

    setState(() => _submitting = true);
    final res = await NotesService.instance.createNote(
      CreateNoteRequest(
        title: t,
        content: _content.text.trim().isEmpty ? null : _content.text.trim(),
        priority: _priority,
        isPinned: _pinned,
        hasReminder: _hasReminder,
        reminderDate: _hasReminder ? _reminderAt : null,
        color: _color,
        tags: List.unmodifiable(_tags),
        clientName:
            _clientName.text.trim().isEmpty ? null : _clientName.text.trim(),
        clientPhone:
            _clientPhone.text.trim().isEmpty ? null : _clientPhone.text.trim(),
        clientEmail:
            _clientEmail.text.trim().isEmpty ? null : _clientEmail.text.trim(),
      ),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (res.success) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message ?? 'Não foi possível criar.')),
      );
    }
  }

  InputDecoration _fieldDec(
    BuildContext context, {
    required String label,
    String? hint,
    int? maxLines,
    Color? accent,
  }) {
    final a = accent ?? widget.accent;
    final border = ThemeHelpers.borderColor(context);
    return InputDecoration(
      labelText: label,
      hintText: hint,
      alignLabelWithHint: maxLines != null && maxLines > 1,
      filled: true,
      fillColor: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.35),
      contentPadding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: maxLines != null && maxLines > 1 ? 14 : 12,
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: border.withValues(alpha: 0.35)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: a.withValues(alpha: 0.7), width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final border = ThemeHelpers.borderColor(context);
    final sheetBg = isDark
        ? ThemeHelpers.cardBackgroundColor(context)
        : const Color(0xFFFFFDF8);

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 520,
                maxHeight: mq.size.height * 0.92,
              ),
              child: Material(
                elevation: 28,
                shadowColor: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(22),
                clipBehavior: Clip.antiAlias,
                color: sheetBg,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: 5,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              _noteColor,
                              _noteColor.withValues(alpha: 0.35),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _CreateHeader(
                          accent: widget.accent,
                          noteColor: _noteColor,
                          pinned: _pinned,
                          submitting: _submitting,
                          onClose: () => Navigator.of(context).pop(),
                          onTogglePin: _submitting
                              ? null
                              : () => setState(() => _pinned = !_pinned),
                        ),
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                            physics: const BouncingScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextField(
                                  controller: _title,
                                  enabled: !_submitting,
                                  autofocus: true,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.3,
                                    height: 1.15,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Título da anotação',
                                    hintStyle: theme.textTheme.titleLarge
                                        ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: muted.withValues(alpha: 0.55),
                                      letterSpacing: -0.3,
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _content,
                                  enabled: !_submitting,
                                  minLines: 4,
                                  maxLines: 10,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  decoration: _fieldDec(
                                    context,
                                    label: 'Conteúdo',
                                    hint:
                                        'Detalhes, próximos passos, observações…',
                                    maxLines: 4,
                                    accent: _noteColor,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                _CreateSection(
                                  icon: Icons.flag_rounded,
                                  iconColor: _priorities[_priority]!.tone,
                                  title: 'Prioridade',
                                  child: _PriorityPicker(
                                    value: _priority,
                                    enabled: !_submitting,
                                    onChanged: (v) =>
                                        setState(() => _priority = v),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                _CreateSection(
                                  icon: Icons.palette_outlined,
                                  iconColor: _noteColor,
                                  title: 'Cor da nota',
                                  child: _ColorPicker(
                                    colors: _noteColors,
                                    selected: _color,
                                    accent: widget.accent,
                                    enabled: !_submitting,
                                    onSelected: (hex) =>
                                        setState(() => _color = hex),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                _CreateSection(
                                  icon: Icons.person_outline_rounded,
                                  iconColor: widget.accent,
                                  title: 'Cliente',
                                  trailing: IconButton(
                                    visualDensity: VisualDensity.compact,
                                    onPressed: _submitting
                                        ? null
                                        : () => setState(
                                              () => _clientExpanded =
                                                  !_clientExpanded,
                                            ),
                                    icon: Icon(
                                      _clientExpanded
                                          ? Icons.expand_less_rounded
                                          : Icons.expand_more_rounded,
                                      color: muted,
                                    ),
                                  ),
                                  child: AnimatedCrossFade(
                                    firstCurve: Curves.easeOutCubic,
                                    secondCurve: Curves.easeOutCubic,
                                    sizeCurve: Curves.easeOutCubic,
                                    crossFadeState: _clientExpanded
                                        ? CrossFadeState.showSecond
                                        : CrossFadeState.showFirst,
                                    duration: const Duration(milliseconds: 220),
                                    firstChild: Text(
                                      'Opcional — nome, telefone e e-mail',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                        color: muted,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    secondChild: Column(
                                      children: [
                                        TextField(
                                          controller: _clientName,
                                          enabled: !_submitting,
                                          textCapitalization:
                                              TextCapitalization.words,
                                          decoration: _fieldDec(
                                            context,
                                            label: 'Nome',
                                            accent: widget.accent,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        TextField(
                                          controller: _clientPhone,
                                          enabled: !_submitting,
                                          keyboardType: TextInputType.phone,
                                          decoration: _fieldDec(
                                            context,
                                            label: 'Telefone',
                                            accent: widget.accent,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        TextField(
                                          controller: _clientEmail,
                                          enabled: !_submitting,
                                          keyboardType:
                                              TextInputType.emailAddress,
                                          decoration: _fieldDec(
                                            context,
                                            label: 'E-mail',
                                            accent: widget.accent,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                _CreateSection(
                                  icon: Icons.notifications_active_outlined,
                                  iconColor: const Color(0xFF10B981),
                                  title: 'Lembrete',
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _ToggleRow(
                                        label: 'Agendar lembrete',
                                        value: _hasReminder,
                                        accent: const Color(0xFF10B981),
                                        enabled: !_submitting,
                                        onChanged: (v) => setState(() {
                                          _hasReminder = v;
                                          if (!v) _reminderAt = null;
                                        }),
                                      ),
                                      if (_hasReminder) ...[
                                        const SizedBox(height: 8),
                                        Material(
                                          color: const Color(0xFF10B981)
                                              .withValues(alpha: 0.08),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          child: InkWell(
                                            onTap: _submitting
                                                ? null
                                                : _pickReminder,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 14,
                                                vertical: 12,
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons
                                                        .calendar_today_outlined,
                                                    size: 18,
                                                    color: _reminderAt == null
                                                        ? muted
                                                        : const Color(
                                                            0xFF10B981,
                                                          ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Text(
                                                      _reminderAt == null
                                                          ? 'Escolher data e hora'
                                                          : DateFormat(
                                                              "dd/MM/yyyy 'às' HH:mm",
                                                              'pt_BR',
                                                            ).format(
                                                              _reminderAt!,
                                                            ),
                                                      style: theme
                                                          .textTheme.bodyMedium
                                                          ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: _reminderAt ==
                                                                null
                                                            ? muted
                                                            : ThemeHelpers
                                                                .textColor(
                                                                context,
                                                              ),
                                                      ),
                                                    ),
                                                  ),
                                                  Icon(
                                                    Icons.chevron_right_rounded,
                                                    color: muted,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 18),
                                _CreateSection(
                                  icon: Icons.local_offer_outlined,
                                  iconColor: widget.accent,
                                  title: 'Tags',
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller: _tagInput,
                                              enabled: !_submitting,
                                              onSubmitted: (_) => _addTag(),
                                              decoration: _fieldDec(
                                                context,
                                                label: 'Nova tag',
                                                hint: 'Enter para adicionar',
                                                accent: widget.accent,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          IconButton.filled(
                                            onPressed:
                                                _submitting ? null : _addTag,
                                            style: IconButton.styleFrom(
                                              backgroundColor: widget.accent,
                                              minimumSize: const Size(48, 48),
                                            ),
                                            icon: const Icon(
                                              Icons.add_rounded,
                                              size: 22,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (_tags.isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: _tags.map((t) {
                                            return InputChip(
                                              label: Text(t),
                                              labelStyle: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12.5,
                                              ),
                                              side: BorderSide(
                                                color: border.withValues(
                                                  alpha: 0.45,
                                                ),
                                              ),
                                              onDeleted: _submitting
                                                  ? null
                                                  : () => setState(
                                                        () => _tags.remove(t),
                                                      ),
                                            );
                                          }).toList(),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                            ),
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color: border.withValues(alpha: 0.35),
                              ),
                            ),
                          ),
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _submitting
                                      ? null
                                      : () => Navigator.of(context).pop(),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 48),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    side: BorderSide(
                                      color: border.withValues(alpha: 0.55),
                                    ),
                                  ),
                                  child: const Text(
                                    'Cancelar',
                                    style: TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 2,
                                child: FilledButton(
                                  onPressed: _submitting ? null : _submit,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _noteColor,
                                    minimumSize: const Size(0, 48),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: _submitting
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          'Salvar anotação',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 15,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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

  Color _parseHex(String hex) {
    var s = hex.replaceFirst('#', '');
    if (s.length == 6) s = 'FF$s';
    final v = int.tryParse(s, radix: 16);
    return v != null ? Color(v) : const Color(0xFF3B82F6);
  }
}

class _CreateHeader extends StatelessWidget {
  const _CreateHeader({
    required this.accent,
    required this.noteColor,
    required this.pinned,
    required this.submitting,
    required this.onClose,
    this.onTogglePin,
  });

  final Color accent;
  final Color noteColor;
  final bool pinned;
  final bool submitting;
  final VoidCallback onClose;
  final VoidCallback? onTogglePin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final now = DateTime.now();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  noteColor,
                  Color.lerp(noteColor, accent, 0.35) ?? noteColor,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: noteColor.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.edit_note_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'NOVA ANOTAÇÃO',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: noteColor,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: noteColor.withValues(alpha: 0.55),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('HH:mm', 'pt_BR').format(now),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: muted,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Registro avançado',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  'Cliente, lembrete, tags e prioridade.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          if (onTogglePin != null)
            IconButton(
              onPressed: submitting ? null : onTogglePin,
              tooltip: pinned ? 'Desafixar' : 'Fixar no topo',
              icon: Icon(
                pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                color: pinned ? const Color(0xFFF59E0B) : muted,
              ),
            ),
          IconButton(
            onPressed: onClose,
            icon: Icon(Icons.close_rounded, color: muted),
          ),
        ],
      ),
    );
  }
}

class _CreateSection extends StatelessWidget {
  const _CreateSection({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _PriorityPicker extends StatelessWidget {
  const _PriorityPicker({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _priorities.entries.map((e) {
        final on = value == e.key;
        final tone = e.value.tone;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: e.key != 'urgent' ? 6 : 0,
            ),
            child: Material(
              color: on
                  ? tone.withValues(alpha: 0.14)
                  : Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: enabled ? () => onChanged(e.key) : null,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: on
                          ? tone.withValues(alpha: 0.65)
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: tone,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        e.value.label,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: on
                                  ? tone
                                  : ThemeHelpers.textSecondaryColor(context),
                              fontSize: 10.5,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({
    required this.colors,
    required this.selected,
    required this.accent,
    required this.enabled,
    required this.onSelected,
  });

  final List<String> colors;
  final String selected;
  final Color accent;
  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: colors.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final hex = colors[i];
          final c = _parseHexStatic(hex);
          final sel = selected == hex;
          return GestureDetector(
            onTap: enabled ? () => onSelected(hex) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: sel ? 40 : 34,
              height: sel ? 40 : 34,
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(sel ? 12 : 10),
                border: Border.all(
                  color: sel ? accent : Colors.white.withValues(alpha: 0.2),
                  width: sel ? 2.5 : 1,
                ),
                boxShadow: sel
                    ? [
                        BoxShadow(
                          color: c.withValues(alpha: 0.5),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: sel
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                  : null,
            ),
          );
        },
      ),
    );
  }

  static Color _parseHexStatic(String hex) {
    var s = hex.replaceFirst('#', '');
    if (s.length == 6) s = 'FF$s';
    final v = int.tryParse(s, radix: 16);
    return v != null ? Color(v) : const Color(0xFF3B82F6);
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.accent,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final Color accent;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        Switch.adaptive(
          value: value,
          onChanged: enabled ? onChanged : null,
          activeTrackColor: accent.withValues(alpha: 0.45),
          activeThumbColor: accent,
        ),
      ],
    );
  }
}
