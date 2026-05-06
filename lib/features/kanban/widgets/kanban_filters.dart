import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../controllers/kanban_controller.dart';
import '../models/kanban_models.dart';

/// Widget de filtros do Kanban — busca + prioridade.
///
/// Layout:
/// - Wide (≥ 540): linha horizontal com busca expandida + botão de prioridade premium.
/// - Narrow: empilhado.
class KanbanFilters extends StatefulWidget {
  /// Quando [true], omite o cartão externo (uso dentro do painel agrupado na [KanbanPage]).
  final bool embedded;

  const KanbanFilters({
    super.key,
    this.embedded = false,
  });

  @override
  State<KanbanFilters> createState() => _KanbanFiltersState();
}

class _KanbanFiltersState extends State<KanbanFilters> {
  static const double _kWideBreak = 540;

  final _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  KanbanPriority? _selectedPriority;
  String? _selectedAssigneeId;

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<KanbanController>();

    Widget search = _PremiumSearchField(
      controller: _searchController,
      focusNode: _searchFocus,
      onChanged: (_) {
        setState(() {});
        _applyFilters(controller);
      },
      onClear: () {
        _searchController.clear();
        _applyFilters(controller);
        setState(() {});
      },
    );

    Widget priority = _PriorityTrigger(
      value: _selectedPriority,
      onTap: () => _openPriorityPicker(controller),
    );

    Widget? clearAll = !_hasActiveFilters()
        ? null
        : _ClearAllButton(onPressed: () => _clearFilters(controller));

    Widget innerFields(double maxWidth) {
      final wide = maxWidth >= _kWideBreak;
      if (wide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: search),
            const SizedBox(width: 10),
            priority,
            if (clearAll != null) ...[
              const SizedBox(width: 8),
              clearAll,
            ],
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          search,
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: priority),
              if (clearAll != null) ...[
                const SizedBox(width: 8),
                clearAll,
              ],
            ],
          ),
        ],
      );
    }

    if (widget.embedded) {
      return LayoutBuilder(
        builder: (context, c) => innerFields(c.maxWidth),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderColor(context)),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, c) => innerFields(c.maxWidth),
      ),
    );
  }

  Future<void> _openPriorityPicker(KanbanController controller) async {
    final picked = await showModalBottomSheet<_PriorityPickResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PriorityPickerSheet(
        selected: _selectedPriority,
      ),
    );
    if (picked == null) return;
    setState(() => _selectedPriority = picked.value);
    _applyFilters(controller);
  }

  bool _hasActiveFilters() {
    return _searchController.text.isNotEmpty ||
        _selectedPriority != null ||
        _selectedAssigneeId != null;
  }

  void _applyFilters(KanbanController controller) {
    controller.applyFilters(
      searchQuery: _searchController.text.trim().isEmpty
          ? null
          : _searchController.text.trim(),
      priority: _selectedPriority,
      assigneeId: _selectedAssigneeId,
    );
  }

  void _clearFilters(KanbanController controller) {
    setState(() {
      _searchController.clear();
      _selectedPriority = null;
      _selectedAssigneeId = null;
    });
    controller.clearFilters();
  }
}

// ============================================================================
// SEARCH PREMIUM
// ============================================================================

class _PremiumSearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _PremiumSearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _kanbanAccent(context);
    const cool = Color(0xFF0891B2);
    final hasText = controller.text.isNotEmpty;
    final focused = focusNode.hasFocus;
    final highlighted = focused || hasText;

    // Refino minimalista premium:
    // - Card sólido em idle (sem aspecto "apagado")
    // - Tint accent muito sutil ao focar
    // - Sombra com cor accent quando ativo (eleva o componente)
    // - Stripe degradê fininho no rodapé do campo quando ativo (detalhe premium)
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: highlighted
            ? Color.alphaBlend(
                accent.withValues(alpha: isDark ? 0.10 : 0.05),
                ThemeHelpers.cardBackgroundColor(context),
              )
            : ThemeHelpers.cardBackgroundColor(context),
        border: Border.all(
          color: highlighted
              ? accent.withValues(alpha: isDark ? 0.6 : 0.42)
              : ThemeHelpers.borderColor(context),
          width: highlighted ? 1.4 : 1,
        ),
        boxShadow: highlighted
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: isDark ? 0.18 : 0.08),
                  blurRadius: 14,
                  spreadRadius: -3,
                  offset: const Offset(0, 5),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.025),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Stack(
        children: [
          // Stripe inferior degradê (detalhe premium minimalista) — só ao focar.
          // Indica visualmente o estado ativo sem precisar pintar o fundo todo.
          if (highlighted)
            Positioned(
              left: 12,
              right: 12,
              bottom: 0,
              child: Container(
                height: 1.5,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  gradient: LinearGradient(
                    colors: [
                      accent.withValues(alpha: 0.0),
                      accent.withValues(alpha: 0.55),
                      cool.withValues(alpha: 0.45),
                      accent.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 0.32, 0.68, 1.0],
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                // Caixinha do ícone — monocromática (não duo-tone como antes),
                // mas com leve gradient interno quando ativa para dar profundidade.
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: highlighted
                          ? LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                accent.withValues(alpha: isDark ? 0.28 : 0.16),
                                accent.withValues(alpha: isDark ? 0.14 : 0.08),
                              ],
                            )
                          : null,
                      color: highlighted
                          ? null
                          : ThemeHelpers.borderColor(context)
                              .withValues(alpha: isDark ? 0.22 : 0.18),
                      border: Border.all(
                        color: highlighted
                            ? accent.withValues(alpha: isDark ? 0.42 : 0.32)
                            : ThemeHelpers.borderColor(context)
                                .withValues(alpha: 0.5),
                        width: 0.9,
                      ),
                    ),
                    child: Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: highlighted
                          ? accent
                          : ThemeHelpers.textSecondaryColor(context),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    textInputAction: TextInputAction.search,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      color: ThemeHelpers.textColor(context),
                    ),
                    decoration: InputDecoration(
                      hintText: 'Buscar lead, título ou descrição…',
                      hintStyle: theme.textTheme.bodyMedium?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        fontWeight: FontWeight.w500,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 14,
                      ),
                    ),
                    onChanged: onChanged,
                  ),
                ),
                if (hasText)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: IconButton(
                      icon: Icon(
                        Icons.clear_rounded,
                        size: 18,
                        color: ThemeHelpers.textSecondaryColor(context),
                      ),
                      onPressed: onClear,
                      tooltip: 'Limpar busca',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
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

// ============================================================================
// PRIORITY TRIGGER + SHEET
// ============================================================================

class _PriorityTrigger extends StatelessWidget {
  final KanbanPriority? value;
  final VoidCallback onTap;

  const _PriorityTrigger({required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _kanbanAccent(context);
    final selected = value != null;
    final color = selected ? _priorityColor(value!) : accent;

    // Refino minimalista premium:
    // - Card sólido com leve tint quando selecionado
    // - Stripe lateral 3px colorido (acento de prioridade) — detalhe premium
    //   que reforça visualmente a prioridade selecionada sem encher o card
    // - Ícone num quadradinho com gradient interno suave quando ativo
    // - Sombra com a cor da prioridade ao selecionar
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: selected
                ? Color.alphaBlend(
                    color.withValues(alpha: isDark ? 0.12 : 0.06),
                    ThemeHelpers.cardBackgroundColor(context),
                  )
                : ThemeHelpers.cardBackgroundColor(context),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: isDark ? 0.55 : 0.4)
                  : ThemeHelpers.borderColor(context),
              width: selected ? 1.4 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: isDark ? 0.18 : 0.10),
                      blurRadius: 14,
                      spreadRadius: -3,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.18 : 0.025,
                      ),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: [
                // Stripe esquerda — só aparece quando há prioridade
                // selecionada. Conecta visualmente com o stripe do card de
                // tarefa (mesma cor da prioridade).
                if (selected)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 3,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            color.withValues(alpha: 0.95),
                            color.withValues(alpha: 0.55),
                          ],
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    selected ? 13 : 12,
                    10,
                    10,
                    10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          gradient: selected
                              ? LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    color.withValues(
                                      alpha: isDark ? 0.32 : 0.18,
                                    ),
                                    color.withValues(
                                      alpha: isDark ? 0.16 : 0.08,
                                    ),
                                  ],
                                )
                              : null,
                          color: selected
                              ? null
                              : ThemeHelpers.borderColor(context).withValues(
                                  alpha: isDark ? 0.22 : 0.18,
                                ),
                          border: Border.all(
                            color: selected
                                ? color.withValues(
                                    alpha: isDark ? 0.55 : 0.38,
                                  )
                                : ThemeHelpers.borderColor(context).withValues(
                                    alpha: 0.5,
                                  ),
                            width: 0.9,
                          ),
                        ),
                        child: Icon(
                          selected ? Icons.flag_rounded : Icons.tune_rounded,
                          color: selected
                              ? color
                              : ThemeHelpers.textSecondaryColor(context),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'PRIORIDADE',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.1,
                              color: selected
                                  ? color
                                  : ThemeHelpers.textSecondaryColor(context),
                              height: 1,
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            selected ? value!.label : 'Todas',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                              height: 1.1,
                              color: ThemeHelpers.textColor(context),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.expand_more_rounded,
                        color: selected
                            ? color.withValues(alpha: 0.85)
                            : ThemeHelpers.textSecondaryColor(context),
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PriorityPickResult {
  final KanbanPriority? value;
  const _PriorityPickResult(this.value);
}

class _PriorityPickerSheet extends StatelessWidget {
  final KanbanPriority? selected;

  const _PriorityPickerSheet({required this.selected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _kanbanAccent(context);
    final mq = MediaQuery.of(context);

    final all = <_PriorityChoice>[
      const _PriorityChoice(null, 'Todas as prioridades',
          'Não filtrar por prioridade', Color(0xFF6B7280)),
      ...KanbanPriority.values.map(
        (p) => _PriorityChoice(p, p.label, _priorityHelp(p), _priorityColor(p)),
      ),
    ];

    return SafeArea(
      top: false,
      child: Container(
        margin: EdgeInsets.only(top: mq.padding.top + 36),
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.18),
              blurRadius: 28,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: ThemeHelpers.textSecondaryColor(context)
                    .withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        colors: [
                          accent.withValues(alpha: isDark ? 0.4 : 0.22),
                          const Color(0xFF0891B2)
                              .withValues(alpha: isDark ? 0.4 : 0.22),
                        ],
                      ),
                      border:
                          Border.all(color: accent.withValues(alpha: 0.4)),
                    ),
                    child: Icon(
                      Icons.flag_rounded,
                      size: 20,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Filtrar por prioridade',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Foque o quadro nos cards mais críticos',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + mq.padding.bottom),
              child: Column(
                children: [
                  for (final item in all) ...[
                    _PriorityTile(
                      choice: item,
                      selected: item.value == selected,
                      onTap: () => Navigator.of(context)
                          .pop(_PriorityPickResult(item.value)),
                    ),
                    if (item != all.last) const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriorityChoice {
  final KanbanPriority? value;
  final String label;
  final String description;
  final Color color;

  const _PriorityChoice(this.value, this.label, this.description, this.color);
}

class _PriorityTile extends StatelessWidget {
  final _PriorityChoice choice;
  final bool selected;
  final VoidCallback onTap;

  const _PriorityTile({
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = choice.color;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: selected
                ? color.withValues(alpha: isDark ? 0.18 : 0.09)
                : ThemeHelpers.cardBackgroundColor(context)
                    .withValues(alpha: 0.5),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: isDark ? 0.6 : 0.4)
                  : ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: color.withValues(alpha: isDark ? 0.32 : 0.16),
                    border: Border.all(
                      color: color.withValues(alpha: isDark ? 0.55 : 0.35),
                    ),
                  ),
                  child: Icon(
                    choice.value == null ? Icons.all_inclusive_rounded : Icons.flag_rounded,
                    color: color,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        choice.label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        choice.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: ThemeHelpers.textSecondaryColor(context),
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle_rounded, color: color, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// CLEAR ALL
// ============================================================================

class _ClearAllButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _ClearAllButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger = theme.colorScheme.error;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: danger.withValues(alpha: isDark ? 0.14 : 0.08),
            border: Border.all(
              color: danger.withValues(alpha: isDark ? 0.45 : 0.32),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.clear_all_rounded, size: 18, color: danger),
                const SizedBox(width: 6),
                Text(
                  'Limpar',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: danger,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// HELPERS
// ============================================================================

Color _kanbanAccent(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
}

Color _priorityColor(KanbanPriority p) {
  return Color(int.parse(p.color.replaceFirst('#', '0xFF')));
}

String _priorityHelp(KanbanPriority p) {
  switch (p) {
    case KanbanPriority.low:
      return 'Baixa relevância — pode esperar';
    case KanbanPriority.medium:
      return 'Ritmo padrão do funil';
    case KanbanPriority.high:
      return 'Atenção elevada — acompanhe de perto';
    case KanbanPriority.urgent:
      return 'Crítico — agir agora';
  }
}
