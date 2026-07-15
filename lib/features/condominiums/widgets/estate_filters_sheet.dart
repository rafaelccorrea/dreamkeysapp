import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/condominium_models.dart';
import 'estate_shared.dart';

const List<String> kEstateUfs = [
  'AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MT', 'MS',
  'MG', 'PA', 'PB', 'PR', 'PE', 'PI', 'RJ', 'RN', 'RS', 'RO', 'RR', 'SC',
  'SP', 'SE', 'TO',
];

/// Bottom-sheet de filtros de Condomínios/Empreendimentos — espelha o padrão
/// do modal de filtros do CRM (`kanban_filters_drawer.dart`): seções flush
/// separadas por filete tracejado + eyebrow com dot, campos em pill, footer
/// com Limpar/Aplicar.
class EstateFiltersSheet extends StatefulWidget {
  final EstateListFilters initialFilters;
  final Color accent;
  final ValueChanged<EstateListFilters> onApply;

  const EstateFiltersSheet({
    super.key,
    required this.initialFilters,
    required this.accent,
    required this.onApply,
  });

  @override
  State<EstateFiltersSheet> createState() => _EstateFiltersSheetState();
}

class _EstateFiltersSheetState extends State<EstateFiltersSheet> {
  final _cityController = TextEditingController();
  final _neighborhoodController = TextEditingController();
  String? _state;
  late EstateSortBy _sortBy;
  late bool _ascending;

  @override
  void initState() {
    super.initState();
    final f = widget.initialFilters;
    _cityController.text = f.city ?? '';
    _neighborhoodController.text = f.neighborhood ?? '';
    _state = (f.state ?? '').trim().isEmpty ? null : f.state!.trim();
    _sortBy = f.sortBy;
    _ascending = f.ascending;
  }

  @override
  void dispose() {
    _cityController.dispose();
    _neighborhoodController.dispose();
    super.dispose();
  }

  Color _fieldFill(BuildContext c) => Theme.of(c).brightness == Brightness.dark
      ? AppColors.background.backgroundTertiaryDarkMode
      : AppColors.background.backgroundTertiary;

  EstateListFilters _buildFilters() {
    String? opt(String v) => v.trim().isEmpty ? null : v.trim();
    return EstateListFilters(
      search: widget.initialFilters.search,
      isActive: widget.initialFilters.isActive,
      limit: widget.initialFilters.limit,
      page: 1,
      city: opt(_cityController.text),
      state: _state,
      neighborhood: opt(_neighborhoodController.text),
      sortBy: _sortBy,
      ascending: _ascending,
    );
  }

  int get _activeCount => _buildFilters().activeCount;

  void _apply() {
    widget.onApply(_buildFilters());
    Navigator.of(context).pop();
  }

  void _clear() {
    widget.onApply(EstateListFilters(
      search: widget.initialFilters.search,
      isActive: widget.initialFilters.isActive,
      limit: widget.initialFilters.limit,
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final cLocal = EstateTones.blue(context);
    final cSort = EstateTones.amber(context);
    final mq = MediaQuery.of(context);
    final activeCount = _activeCount;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.95,
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
              _buildHeader(context, accent, activeCount),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                  children: [
                    _section(
                      context,
                      accent: cLocal,
                      label: 'Localização',
                      hint: 'Restrinja por cidade, bairro ou UF.',
                      first: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _textControl(
                            context,
                            icon: LucideIcons.mapPin,
                            accent: cLocal,
                            controller: _cityController,
                            hint: 'Cidade',
                          ),
                          const SizedBox(height: 10),
                          _textControl(
                            context,
                            icon: LucideIcons.map,
                            accent: cLocal,
                            controller: _neighborhoodController,
                            hint: 'Bairro',
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _ChipChoice(
                                label: 'Todas as UFs',
                                selected: _state == null,
                                accent: cLocal,
                                onTap: () => setState(() => _state = null),
                              ),
                              for (final uf in kEstateUfs)
                                _ChipChoice(
                                  label: uf,
                                  selected: _state == uf,
                                  accent: cLocal,
                                  onTap: () => setState(() => _state = uf),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    _section(
                      context,
                      accent: cSort,
                      label: 'Ordenação',
                      hint: 'Como a lista deve ser ordenada.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final s in EstateSortBy.values)
                                _ChipChoice(
                                  label: s.label,
                                  selected: _sortBy == s,
                                  accent: cSort,
                                  onTap: () => setState(() => _sortBy = s),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _ChipChoice(
                                label: 'Crescente',
                                icon: LucideIcons.arrowUpNarrowWide,
                                selected: _ascending,
                                accent: cSort,
                                onTap: () => setState(() => _ascending = true),
                              ),
                              _ChipChoice(
                                label: 'Decrescente',
                                icon: LucideIcons.arrowDownWideNarrow,
                                selected: !_ascending,
                                accent: cSort,
                                onTap: () => setState(() => _ascending = false),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _buildFooter(context, accent, activeCount, mq),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, Color accent, int activeCount) {
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
              color: accent.withValues(alpha: isDark ? 0.20 : 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(LucideIcons.slidersHorizontal, color: accent, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filtrar lista',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  activeCount == 0
                      ? 'Nenhum filtro aplicado'
                      : '$activeCount filtro${activeCount == 1 ? '' : 's'} ativo${activeCount == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: activeCount == 0
                        ? ThemeHelpers.textSecondaryColor(context)
                        : accent,
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

  Widget _section(
    BuildContext context, {
    required Color accent,
    required String label,
    String? hint,
    required Widget child,
    bool first = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(top: first ? 16 : 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!first) ...[
            Container(
              height: 1,
              color:
                  ThemeHelpers.borderLightColor(context).withValues(alpha: 0.7),
            ),
            const SizedBox(height: 18),
          ],
          EstateSectionHeader(tone: accent, label: label, hint: hint),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _textControl(
    BuildContext context, {
    required IconData icon,
    required Color accent,
    required TextEditingController controller,
    required String hint,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
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
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: (_) => setState(() {}),
              textAlignVertical: TextAlignVertical.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ThemeHelpers.textColor(context),
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: hint,
                hintStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: ThemeHelpers.textSecondaryColor(context)
                      .withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: () => setState(controller.clear),
              child: Icon(
                Icons.close_rounded,
                size: 18,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFooter(
    BuildContext context,
    Color accent,
    int activeCount,
    MediaQueryData mq,
  ) {
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
          if (activeCount > 0) ...[
            Expanded(
              flex: 3,
              child: OutlinedButton.icon(
                onPressed: _clear,
                icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                label: const Text(
                  'Limpar',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ThemeHelpers.textSecondaryColor(context),
                  side: BorderSide(color: ThemeHelpers.borderColor(context)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            flex: activeCount > 0 ? 4 : 1,
            child: FilledButton.icon(
              onPressed: _apply,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text(
                activeCount == 0 ? 'Aplicar' : 'Aplicar ($activeCount)',
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

/// Chip de escolha (mesma gramática do modal do CRM).
class _ChipChoice extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _ChipChoice({
    required this.label,
    this.icon,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = selected ? accent : ThemeHelpers.textSecondaryColor(context);
    return Material(
      color: selected
          ? accent.withValues(alpha: isDark ? 0.18 : 0.10)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.55)
                  : ThemeHelpers.borderColor(context),
              width: selected ? 1.3 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: fg),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
