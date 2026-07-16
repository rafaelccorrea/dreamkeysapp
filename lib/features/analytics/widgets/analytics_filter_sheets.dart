// Bottom-sheets de filtro do domínio Analytics — espelham o modal de filtros
// do CRM (kanban_filters_drawer.dart): seções flush com filete tracejado +
// eyebrow com dot, chips em tint (nunca preenchimento sólido), footer com
// Limpar/Aplicar.

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/multichannel_models.dart';
import '../models/property_analytics_models.dart';
import 'analytics_ui.dart';

// ─── Infra compartilhada ──────────────────────────────────────────────────────

Color _fieldFill(BuildContext c) => Theme.of(c).brightness == Brightness.dark
    ? AppColors.background.backgroundTertiaryDarkMode
    : AppColors.background.backgroundTertiary;

/// Shell do sheet: handle + header (chip de ícone + título + contagem) +
/// conteúdo scrollável + footer Limpar/Aplicar.
class _SheetShell extends StatelessWidget {
  const _SheetShell({
    required this.title,
    required this.activeCount,
    required this.children,
    required this.onApply,
    required this.onClear,
    this.initialSize = 0.72,
  });

  final String title;
  final int activeCount;
  final List<Widget> children;
  final VoidCallback onApply;
  final VoidCallback onClear;
  final double initialSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = AnalyticsTones.accent(context);
    final mq = MediaQuery.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: initialSize,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: ThemeHelpers.backgroundColor(context),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.4),
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
              Container(
                padding: const EdgeInsets.fromLTRB(20, 4, 10, 14),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: ThemeHelpers.borderLightColor(context),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color:
                            accent.withValues(alpha: isDark ? 0.2 : 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child:
                          Icon(Icons.tune_rounded, color: accent, size: 21),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
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
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                  children: children,
                ),
              ),
              Container(
                padding:
                    EdgeInsets.fromLTRB(16, 12, 16, 12 + mq.padding.bottom),
                decoration: BoxDecoration(
                  color: ThemeHelpers.cardBackgroundColor(context),
                  border: Border(
                    top: BorderSide(
                      color: ThemeHelpers.borderColor(context)
                          .withValues(alpha: 0.45),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    if (activeCount > 0) ...[
                      Expanded(
                        flex: 3,
                        child: OutlinedButton.icon(
                          onPressed: onClear,
                          icon: const Icon(Icons.filter_alt_off_outlined,
                              size: 18),
                          label: const Text(
                            'Limpar',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor:
                                ThemeHelpers.textSecondaryColor(context),
                            side: BorderSide(
                                color: ThemeHelpers.borderColor(context)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 14),
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
                        onPressed: onApply,
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: Text(
                          activeCount == 0
                              ? 'Aplicar'
                              : 'Aplicar ($activeCount)',
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
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Seção flush: filete tracejado (exceto a primeira) + eyebrow com dot + hint.
class _Section extends StatelessWidget {
  const _Section({
    required this.accent,
    required this.label,
    required this.child,
    this.hint,
    this.first = false,
  });

  final Color accent;
  final String label;
  final String? hint;
  final Widget child;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: first ? 16 : 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!first) ...[
            _DashedLine(color: ThemeHelpers.borderLightColor(context)),
            const SizedBox(height: 18),
          ],
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
              hint!,
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
}

/// Chip de seleção em tint (ativo = fundo translúcido + borda + texto na cor).
class AnalyticsChip extends StatelessWidget {
  const AnalyticsChip({
    super.key,
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
    final fg = selected
        ? accent
        : ThemeHelpers.textColor(context).withValues(alpha: 0.82);
    final bg = selected
        ? accent.withValues(alpha: isDark ? 0.18 : 0.10)
        : _fieldFill(context);
    final border = selected ? accent : ThemeHelpers.borderLightColor(context);
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

/// Campo em pill com chip de ícone (padrão FilterControl da web).
class _FieldControl extends StatelessWidget {
  const _FieldControl({
    required this.icon,
    required this.accent,
    required this.child,
  });

  final IconData icon;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
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
              color: accent.withValues(alpha: isDark ? 0.2 : 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(child: child),
        ],
      ),
    );
  }
}

TextStyle _fieldTextStyle(BuildContext context) => TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: ThemeHelpers.textColor(context),
    );

InputDecoration _bareDecoration(BuildContext context, String hint) =>
    InputDecoration(
      isDense: true,
      border: InputBorder.none,
      contentPadding: EdgeInsets.zero,
      hintText: hint,
      hintStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color:
            ThemeHelpers.textSecondaryColor(context).withValues(alpha: 0.9),
      ),
    );

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

// ─── Multicanal ───────────────────────────────────────────────────────────────

/// Filtros da Análise Multicanal: período (diário/semanal/mensal) + cidades.
class MultichannelFiltersSheet extends StatefulWidget {
  const MultichannelFiltersSheet({
    super.key,
    required this.period,
    required this.selectedCityKeys,
    required this.availableCities,
    required this.onApply,
  });

  final String period;
  final Set<String> selectedCityKeys;
  final List<CityOption> availableCities;
  final void Function(String period, Set<String> cityKeys) onApply;

  @override
  State<MultichannelFiltersSheet> createState() =>
      _MultichannelFiltersSheetState();
}

class _MultichannelFiltersSheetState extends State<MultichannelFiltersSheet> {
  late String _period;
  late Set<String> _cities;

  static const _periods = [
    ('daily', 'Diário'),
    ('weekly', 'Semanal'),
    ('monthly', 'Mensal'),
  ];

  @override
  void initState() {
    super.initState();
    _period = widget.period;
    _cities = Set<String>.from(widget.selectedCityKeys);
  }

  int get _activeCount =>
      (_period != 'monthly' ? 1 : 0) + (_cities.isNotEmpty ? 1 : 0);

  @override
  Widget build(BuildContext context) {
    final cPeriodo = AnalyticsTones.blue(context);
    final cCidades = AnalyticsTones.green(context);
    return _SheetShell(
      title: 'Filtrar análise',
      activeCount: _activeCount,
      onApply: () {
        widget.onApply(_period, _cities);
        Navigator.of(context).pop();
      },
      onClear: () {
        widget.onApply('monthly', <String>{});
        Navigator.of(context).pop();
      },
      children: [
        _Section(
          accent: cPeriodo,
          label: 'Período',
          hint: 'Janela de tempo dos dados de origem e engajamento.',
          first: true,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (value, label) in _periods)
                AnalyticsChip(
                  label: label,
                  selected: _period == value,
                  accent: cPeriodo,
                  onTap: () => setState(() => _period = value),
                ),
            ],
          ),
        ),
        _Section(
          accent: cCidades,
          label: 'Cidades',
          hint:
              'Sem seleção = todas as cidades onde a empresa possui imóveis.',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AnalyticsChip(
                label: 'Todas',
                selected: _cities.isEmpty,
                accent: cCidades,
                onTap: () => setState(() => _cities.clear()),
              ),
              for (final c in widget.availableCities)
                AnalyticsChip(
                  label: c.label,
                  selected: _cities.contains(c.key),
                  accent: cCidades,
                  onTap: () => setState(() {
                    if (!_cities.remove(c.key)) _cities.add(c.key);
                  }),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Analytics avançado ───────────────────────────────────────────────────────

/// Filtro de período do Analytics Avançado (semana/mês/trimestre/ano).
class AdvancedFiltersSheet extends StatefulWidget {
  const AdvancedFiltersSheet({
    super.key,
    required this.period,
    required this.onApply,
  });

  final String period;
  final void Function(String period) onApply;

  @override
  State<AdvancedFiltersSheet> createState() => _AdvancedFiltersSheetState();
}

class _AdvancedFiltersSheetState extends State<AdvancedFiltersSheet> {
  late String _period;

  static const _periods = [
    ('week', 'Última semana'),
    ('month', 'Último mês'),
    ('quarter', 'Último trimestre'),
    ('year', 'Último ano'),
  ];

  @override
  void initState() {
    super.initState();
    _period = widget.period;
  }

  @override
  Widget build(BuildContext context) {
    final cPeriodo = AnalyticsTones.blue(context);
    return _SheetShell(
      title: 'Filtrar análise',
      activeCount: _period != 'month' ? 1 : 0,
      initialSize: 0.5,
      onApply: () {
        widget.onApply(_period);
        Navigator.of(context).pop();
      },
      onClear: () {
        widget.onApply('month');
        Navigator.of(context).pop();
      },
      children: [
        _Section(
          accent: cPeriodo,
          label: 'Período',
          hint: 'Janela usada em performance, corretores, funil e captações.',
          first: true,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (value, label) in _periods)
                AnalyticsChip(
                  label: label,
                  selected: _period == value,
                  accent: cPeriodo,
                  onTap: () => setState(() => _period = value),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Analytics de imóveis ─────────────────────────────────────────────────────

/// Filtros do Analytics de Imóveis: status, finalidade, tipo, cidade e bairro.
class PropertyAnalyticsFiltersSheet extends StatefulWidget {
  const PropertyAnalyticsFiltersSheet({
    super.key,
    required this.filters,
    required this.onApply,
  });

  final PropertyAnalyticsFilters filters;
  final void Function(PropertyAnalyticsFilters filters) onApply;

  @override
  State<PropertyAnalyticsFiltersSheet> createState() =>
      _PropertyAnalyticsFiltersSheetState();
}

class _PropertyAnalyticsFiltersSheetState
    extends State<PropertyAnalyticsFiltersSheet> {
  late final TextEditingController _cityController;
  late final TextEditingController _neighborhoodController;
  String? _status;
  String? _finality;
  String? _type;

  static const _statuses = [
    ('available', 'Disponível'),
    ('sold', 'Vendido'),
    ('rented', 'Alugado'),
    ('maintenance', 'Manutenção'),
    ('draft', 'Rascunho'),
  ];

  static const _finalities = [
    ('sale', 'Venda'),
    ('rent', 'Aluguel'),
    ('both', 'Ambos'),
  ];

  static const _types = [
    ('house', 'Casa'),
    ('apartment', 'Apartamento'),
    ('townhouse', 'Sobrado'),
    ('commercial', 'Comercial'),
    ('land', 'Terreno'),
    ('farm', 'Chácara/Fazenda'),
    ('penthouse', 'Cobertura'),
    ('studio', 'Studio'),
    ('kitnet', 'Kitnet'),
  ];

  @override
  void initState() {
    super.initState();
    _status = widget.filters.status;
    _finality = widget.filters.finality;
    _type = widget.filters.propertyType;
    _cityController = TextEditingController(text: widget.filters.city ?? '');
    _neighborhoodController =
        TextEditingController(text: widget.filters.neighborhood ?? '');
  }

  @override
  void dispose() {
    _cityController.dispose();
    _neighborhoodController.dispose();
    super.dispose();
  }

  PropertyAnalyticsFilters _build() {
    final city = _cityController.text.trim();
    final neighborhood = _neighborhoodController.text.trim();
    return PropertyAnalyticsFilters(
      status: _status,
      finality: _finality,
      propertyType: _type,
      city: city.isEmpty ? null : city,
      neighborhood: neighborhood.isEmpty ? null : neighborhood,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cStatus = AnalyticsTones.green(context);
    final cFinalidade = AnalyticsTones.amber(context);
    final cTipo = AnalyticsTones.purple(context);
    final cLocal = AnalyticsTones.blue(context);
    return _SheetShell(
      title: 'Filtrar imóveis',
      activeCount: _build().activeCount,
      initialSize: 0.86,
      onApply: () {
        widget.onApply(_build());
        Navigator.of(context).pop();
      },
      onClear: () {
        widget.onApply(const PropertyAnalyticsFilters());
        Navigator.of(context).pop();
      },
      children: [
        _Section(
          accent: cStatus,
          label: 'Status',
          hint: 'Situação atual do imóvel no CRM.',
          first: true,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AnalyticsChip(
                label: 'Todos',
                selected: _status == null,
                accent: cStatus,
                onTap: () => setState(() => _status = null),
              ),
              for (final (value, label) in _statuses)
                AnalyticsChip(
                  label: label,
                  selected: _status == value,
                  accent: cStatus,
                  onTap: () => setState(
                      () => _status = _status == value ? null : value),
                ),
            ],
          ),
        ),
        _Section(
          accent: cFinalidade,
          label: 'Finalidade',
          hint: 'Venda, aluguel ou ambos.',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AnalyticsChip(
                label: 'Todas',
                selected: _finality == null,
                accent: cFinalidade,
                onTap: () => setState(() => _finality = null),
              ),
              for (final (value, label) in _finalities)
                AnalyticsChip(
                  label: label,
                  selected: _finality == value,
                  accent: cFinalidade,
                  onTap: () => setState(
                      () => _finality = _finality == value ? null : value),
                ),
            ],
          ),
        ),
        _Section(
          accent: cTipo,
          label: 'Tipo de imóvel',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AnalyticsChip(
                label: 'Todos',
                selected: _type == null,
                accent: cTipo,
                onTap: () => setState(() => _type = null),
              ),
              for (final (value, label) in _types)
                AnalyticsChip(
                  label: label,
                  selected: _type == value,
                  accent: cTipo,
                  onTap: () =>
                      setState(() => _type = _type == value ? null : value),
                ),
            ],
          ),
        ),
        _Section(
          accent: cLocal,
          label: 'Localização',
          hint: 'Cidade e bairro exatos como cadastrados.',
          child: Column(
            children: [
              _FieldControl(
                icon: Icons.location_city_rounded,
                accent: cLocal,
                child: TextField(
                  controller: _cityController,
                  style: _fieldTextStyle(context),
                  decoration: _bareDecoration(context, 'Cidade'),
                ),
              ),
              const SizedBox(height: 10),
              _FieldControl(
                icon: Icons.map_outlined,
                accent: cLocal,
                child: TextField(
                  controller: _neighborhoodController,
                  style: _fieldTextStyle(context),
                  decoration: _bareDecoration(context, 'Bairro'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
