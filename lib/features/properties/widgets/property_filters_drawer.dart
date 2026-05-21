import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/cep_service.dart';
import '../../../../shared/services/property_service.dart';

/// Drawer de filtros avançados — identidade visual alinhada com o painel
/// "Atalhos do corretor" do hero da `PropertiesPage`:
///
/// - Cabeçalho compacto com eyebrow accent + título + close.
/// - Seções soltas no background (sem cards encapsulando), separadas só
///   por respiro vertical e label de eyebrow.
/// - Chips coloridos por categoria (mesmo padrão das chips de portfólio).
/// - Toggles tipo "Switch pill" reaproveitados quando faz sentido.
/// - Inputs com borda sutil, label uppercase pequena, sem moldura grossa.
/// - Footer: Limpar (outline) + Aplicar (primary com badge de contagem).
class PropertyFiltersDrawer extends StatefulWidget {
  final PropertyFilters? initialFilters;
  final Function(PropertyFilters?) onFiltersChanged;

  const PropertyFiltersDrawer({
    super.key,
    this.initialFilters,
    required this.onFiltersChanged,
  });

  @override
  State<PropertyFiltersDrawer> createState() => _PropertyFiltersDrawerState();
}

class _PropertyFiltersDrawerState extends State<PropertyFiltersDrawer> {
  // Controllers
  final _minPriceController = TextEditingController();
  final _maxPriceController = TextEditingController();
  final _minAreaController = TextEditingController();
  final _maxAreaController = TextEditingController();
  final _zipCodeController = TextEditingController();
  final _cityController = TextEditingController();
  final _neighborhoodController = TextEditingController();
  final _stateController = TextEditingController();

  // Seleções
  PropertyType? _selectedType;
  PropertyStatus? _selectedStatus;
  int? _bedrooms;
  int? _bathrooms;
  int? _parkingSpaces;

  // Serviços
  final CepService _cepService = CepService.instance;
  bool _isSearchingCep = false;

  @override
  void initState() {
    super.initState();
    _loadInitialFilters();
  }

  void _loadInitialFilters() {
    final filters = widget.initialFilters;
    if (filters == null) return;

    _minPriceController.text = filters.minPrice?.toStringAsFixed(0) ?? '';
    _maxPriceController.text = filters.maxPrice?.toStringAsFixed(0) ?? '';
    _minAreaController.text = filters.minArea?.toStringAsFixed(0) ?? '';
    _maxAreaController.text = filters.maxArea?.toStringAsFixed(0) ?? '';
    _cityController.text = filters.city ?? '';
    _neighborhoodController.text = filters.neighborhood ?? '';
    _stateController.text = filters.state ?? '';
    _selectedType = filters.type;
    _selectedStatus = filters.status;
    _bedrooms = filters.bedrooms;
    _bathrooms = filters.bathrooms;
    _parkingSpaces = filters.parkingSpaces;
  }

  @override
  void dispose() {
    _minPriceController.dispose();
    _maxPriceController.dispose();
    _minAreaController.dispose();
    _maxAreaController.dispose();
    _zipCodeController.dispose();
    _cityController.dispose();
    _neighborhoodController.dispose();
    _stateController.dispose();
    super.dispose();
  }

  Future<void> _searchCep() async {
    final cep = _zipCodeController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (cep.length != 8) return;
    setState(() => _isSearchingCep = true);
    try {
      final address = await _cepService.searchCep(cep);
      if (address != null && mounted) {
        setState(() {
          _cityController.text = address.city ?? '';
          _neighborhoodController.text = address.neighborhood ?? '';
          _stateController.text = address.state ?? '';
        });
      }
    } catch (e) {
      debugPrint('Erro ao buscar CEP: $e');
    } finally {
      if (mounted) setState(() => _isSearchingCep = false);
    }
  }

  void _applyFilters() {
    final base = widget.initialFilters ?? PropertyFilters();
    final filters = base.copyWith(
      type: _selectedType,
      status: _selectedStatus,
      minPrice: _minPriceController.text.trim().isEmpty
          ? null
          : double.tryParse(_minPriceController.text.trim()),
      maxPrice: _maxPriceController.text.trim().isEmpty
          ? null
          : double.tryParse(_maxPriceController.text.trim()),
      minArea: _minAreaController.text.trim().isEmpty
          ? null
          : double.tryParse(_minAreaController.text.trim()),
      maxArea: _maxAreaController.text.trim().isEmpty
          ? null
          : double.tryParse(_maxAreaController.text.trim()),
      city: _cityController.text.trim().isEmpty
          ? null
          : _cityController.text.trim(),
      state: _stateController.text.trim().isEmpty
          ? null
          : _stateController.text.trim().toUpperCase(),
      neighborhood: _neighborhoodController.text.trim().isEmpty
          ? null
          : _neighborhoodController.text.trim(),
      bedrooms: _bedrooms,
      bathrooms: _bathrooms,
      parkingSpaces: _parkingSpaces,
    );
    widget.onFiltersChanged(filters);
    Navigator.of(context).pop();
  }

  void _clearFilters() {
    setState(() {
      _minPriceController.clear();
      _maxPriceController.clear();
      _minAreaController.clear();
      _maxAreaController.clear();
      _zipCodeController.clear();
      _cityController.clear();
      _neighborhoodController.clear();
      _stateController.clear();
      _selectedType = null;
      _selectedStatus = null;
      _bedrooms = null;
      _bathrooms = null;
      _parkingSpaces = null;
    });
    widget.onFiltersChanged(null);
  }

  int get _activeCount {
    var n = 0;
    if (_selectedType != null) n++;
    if (_selectedStatus != null) n++;
    if (_minPriceController.text.trim().isNotEmpty) n++;
    if (_maxPriceController.text.trim().isNotEmpty) n++;
    if (_minAreaController.text.trim().isNotEmpty) n++;
    if (_maxAreaController.text.trim().isNotEmpty) n++;
    if (_cityController.text.trim().isNotEmpty) n++;
    if (_stateController.text.trim().isNotEmpty) n++;
    if (_neighborhoodController.text.trim().isNotEmpty) n++;
    if (_bedrooms != null) n++;
    if (_bathrooms != null) n++;
    if (_parkingSpaces != null) n++;
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mq = MediaQuery.of(context);
    final accent = AppColors.primary.primary;
    final textColor = ThemeHelpers.textColor(context);
    final secondaryColor = ThemeHelpers.textSecondaryColor(context);

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.92),
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(24),
          ),
          border: Border(
            top: BorderSide(
              color:
                  ThemeHelpers.borderColor(context).withValues(alpha: 0.55),
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.10),
              blurRadius: 22,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(24),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10, bottom: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: secondaryColor.withValues(alpha: 0.32),
                    ),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 12, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Icon(LucideIcons.slidersHorizontal,
                                    size: 13, color: accent),
                                const SizedBox(width: 6),
                                Text(
                                  'FILTROS AVANÇADOS',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: accent,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.65,
                                    fontSize: 10.5,
                                  ),
                                ),
                                if (_activeCount > 0) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius:
                                          BorderRadius.circular(999),
                                      color: accent.withValues(
                                        alpha: isDark ? 0.20 : 0.12,
                                      ),
                                      border: Border.all(
                                        color: accent.withValues(alpha: 0.35),
                                      ),
                                    ),
                                    child: Text(
                                      '$_activeCount ativo${_activeCount > 1 ? "s" : ""}',
                                      style: TextStyle(
                                        color: accent,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 10.5,
                                        letterSpacing: 0.25,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Refinar busca',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                                color: textColor,
                                height: 1.0,
                                fontSize: 22,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Combine critérios pra encontrar o imóvel certo.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: secondaryColor,
                                fontWeight: FontWeight.w500,
                                height: 1.35,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        iconSize: 24,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                // Divisor sutil
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  color: ThemeHelpers.borderColor(context)
                      .withValues(alpha: 0.45),
                ),
                // Conteúdo
                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Tipo ───────────────────────────────────────
                        const _SectionLabel(label: 'TIPO DE IMÓVEL'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _FilterChip(
                              label: 'Todos',
                              icon: LucideIcons.layoutGrid,
                              active: _selectedType == null,
                              tone: accent,
                              onTap: () =>
                                  setState(() => _selectedType = null),
                            ),
                            for (final t in PropertyType.values)
                              _FilterChip(
                                label: t.label,
                                icon: _propertyTypeIcon(t),
                                tone: _propertyTypeTone(t),
                                active: _selectedType == t,
                                onTap: () => setState(() {
                                  _selectedType =
                                      _selectedType == t ? null : t;
                                }),
                              ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        // ── Status ─────────────────────────────────────
                        const _SectionLabel(label: 'STATUS DO IMÓVEL'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _FilterChip(
                              label: 'Todos',
                              icon: LucideIcons.layoutGrid,
                              active: _selectedStatus == null,
                              tone: accent,
                              onTap: () =>
                                  setState(() => _selectedStatus = null),
                            ),
                            for (final s in PropertyStatus.values)
                              _FilterChip(
                                label: s.label,
                                icon: _propertyStatusIcon(s),
                                tone: _propertyStatusTone(s),
                                active: _selectedStatus == s,
                                onTap: () => setState(() {
                                  _selectedStatus =
                                      _selectedStatus == s ? null : s;
                                }),
                              ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        // ── Preço ──────────────────────────────────────
                        const _SectionLabel(label: 'PREÇO'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _FilterInput(
                                controller: _minPriceController,
                                label: 'Mínimo',
                                hint: 'R\$ 0',
                                icon: LucideIcons.arrowDown,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _FilterInput(
                                controller: _maxPriceController,
                                label: 'Máximo',
                                hint: 'R\$ 0',
                                icon: LucideIcons.arrowUp,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        // ── Área ───────────────────────────────────────
                        const _SectionLabel(label: 'ÁREA (m²)'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _FilterInput(
                                controller: _minAreaController,
                                label: 'Mínima',
                                hint: '0',
                                icon: LucideIcons.move,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _FilterInput(
                                controller: _maxAreaController,
                                label: 'Máxima',
                                hint: '0',
                                icon: LucideIcons.maximize2,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        // ── Ambientes ──────────────────────────────────
                        const _SectionLabel(label: 'AMBIENTES'),
                        const SizedBox(height: 10),
                        _CountSelector(
                          label: 'Dormitórios',
                          icon: LucideIcons.bed,
                          options: const [1, 2, 3, 4],
                          selected: _bedrooms,
                          onChanged: (v) => setState(() => _bedrooms = v),
                        ),
                        const SizedBox(height: 12),
                        _CountSelector(
                          label: 'Banheiros',
                          icon: LucideIcons.bath,
                          options: const [1, 2, 3, 4],
                          selected: _bathrooms,
                          onChanged: (v) => setState(() => _bathrooms = v),
                        ),
                        const SizedBox(height: 12),
                        _CountSelector(
                          label: 'Vagas',
                          icon: LucideIcons.car,
                          options: const [0, 1, 2, 3, 4],
                          selected: _parkingSpaces,
                          onChanged: (v) =>
                              setState(() => _parkingSpaces = v),
                        ),
                        const SizedBox(height: 22),
                        // ── Localização ────────────────────────────────
                        const _SectionLabel(
                          label: 'LOCALIZAÇÃO',
                          subtitle:
                              'Digite o CEP para preencher o resto automaticamente.',
                        ),
                        const SizedBox(height: 8),
                        _FilterInput(
                          controller: _zipCodeController,
                          label: 'CEP',
                          hint: '00000-000',
                          icon: LucideIcons.mapPin,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(8),
                            TextInputFormatter.withFunction(
                              (oldValue, newValue) {
                                final t = newValue.text;
                                if (t.length <= 5) return newValue;
                                return TextEditingValue(
                                  text:
                                      '${t.substring(0, 5)}-${t.substring(5)}',
                                  selection: TextSelection.collapsed(
                                    offset: newValue.selection.end + 1,
                                  ),
                                );
                              },
                            ),
                          ],
                          onChanged: (value) {
                            final cep =
                                value.replaceAll(RegExp(r'[^0-9]'), '');
                            if (cep.length == 8) _searchCep();
                            setState(() {});
                          },
                          suffix: _isSearchingCep
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: _FilterInput(
                                controller: _cityController,
                                label: 'Cidade',
                                hint: 'Nome da cidade',
                                icon: LucideIcons.building,
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _FilterInput(
                                controller: _stateController,
                                label: 'UF',
                                hint: 'SP',
                                textCapitalization:
                                    TextCapitalization.characters,
                                inputFormatters: [
                                  LengthLimitingTextInputFormatter(2),
                                ],
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _FilterInput(
                          controller: _neighborhoodController,
                          label: 'Bairro',
                          hint: 'Nome do bairro',
                          icon: LucideIcons.map,
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                    ),
                  ),
                ),
                // Footer
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: ThemeHelpers.borderColor(context)
                            .withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _activeCount > 0 ? _clearFilters : null,
                          icon: const Icon(LucideIcons.eraser, size: 16),
                          label: const Text('Limpar'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(
                              color: ThemeHelpers.borderColor(context),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _applyFilters,
                          icon: const Icon(LucideIcons.filter, size: 16),
                          label: Text(
                            _activeCount > 0
                                ? 'Aplicar ($_activeCount)'
                                : 'Aplicar filtros',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
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
          ),
        ),
      ),
    );
  }

  IconData _propertyTypeIcon(PropertyType type) {
    switch (type) {
      case PropertyType.house:
        return LucideIcons.home;
      case PropertyType.apartment:
        return LucideIcons.building2;
      case PropertyType.commercial:
        return LucideIcons.store;
      case PropertyType.land:
        return LucideIcons.trees;
      case PropertyType.rural:
        return LucideIcons.trees;
    }
  }

  Color _propertyTypeTone(PropertyType type) {
    switch (type) {
      case PropertyType.house:
        return const Color(0xFF10B981);
      case PropertyType.apartment:
        return const Color(0xFF3B82F6);
      case PropertyType.commercial:
        return const Color(0xFFF59E0B);
      case PropertyType.land:
        return const Color(0xFF84CC16);
      case PropertyType.rural:
        return const Color(0xFFA16207);
    }
  }

  IconData _propertyStatusIcon(PropertyStatus status) {
    switch (status) {
      case PropertyStatus.draft:
        return LucideIcons.fileEdit;
      case PropertyStatus.pendingApproval:
        return LucideIcons.clock;
      case PropertyStatus.pendingOwnerAuthorization:
        return LucideIcons.userCheck;
      case PropertyStatus.available:
        return LucideIcons.checkCircle2;
      case PropertyStatus.rented:
        return LucideIcons.key;
      case PropertyStatus.sold:
        return LucideIcons.tag;
      case PropertyStatus.maintenance:
        return LucideIcons.wrench;
    }
  }

  Color _propertyStatusTone(PropertyStatus status) {
    switch (status) {
      case PropertyStatus.draft:
        return const Color(0xFF6366F1);
      case PropertyStatus.pendingApproval:
      case PropertyStatus.pendingOwnerAuthorization:
        return const Color(0xFFF59E0B);
      case PropertyStatus.available:
        return const Color(0xFF10B981);
      case PropertyStatus.rented:
        return const Color(0xFF06B6D4);
      case PropertyStatus.sold:
        return const Color(0xFF8B5CF6);
      case PropertyStatus.maintenance:
        return const Color(0xFFEF4444);
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Componentes do drawer
// ──────────────────────────────────────────────────────────────────────────

/// Label de seção: eyebrow uppercase pequena em accent + subtítulo opcional.
class _SectionLabel extends StatelessWidget {
  final String label;
  final String? subtitle;
  const _SectionLabel({required this.label, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppColors.primary.primary;
    final secondaryColor = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: accent,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            fontSize: 10.5,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondaryColor,
              fontWeight: FontWeight.w500,
              height: 1.3,
              fontSize: 11.5,
            ),
          ),
        ],
      ],
    );
  }
}

/// Chip de filtro — pill arredondada com ícone + label. Inativo: card
/// surface com borda fina. Ativo: fill tintado + borda da cor + texto
/// na cor. Mesmo padrão dos chips de portfólio do hero.
class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color tone;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.tone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = active ? tone : ThemeHelpers.textColor(context);
    final bg = active
        ? tone.withValues(alpha: isDark ? 0.18 : 0.12)
        : ThemeHelpers.cardBackgroundColor(context);
    final border = active
        ? tone.withValues(alpha: isDark ? 0.50 : 0.42)
        : ThemeHelpers.borderColor(context).withValues(alpha: 0.55);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        splashColor: tone.withValues(alpha: 0.14),
        highlightColor: tone.withValues(alpha: 0.07),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Seletor numérico em linha — ícone + label à esquerda, pills 1/2/3/4+
/// à direita. Sem moldura externa, tudo flat no fundo do drawer.
class _CountSelector extends StatelessWidget {
  final String label;
  final IconData icon;
  final List<int> options;
  final int? selected;
  final ValueChanged<int?> onChanged;

  const _CountSelector({
    required this.label,
    required this.icon,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppColors.primary.primary;
    final isDark = theme.brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);

    return Row(
      children: [
        Icon(icon, size: 16, color: ThemeHelpers.textSecondaryColor(context)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: textColor,
              fontSize: 13,
              letterSpacing: -0.1,
            ),
          ),
        ),
        for (var i = 0; i < options.length; i++) ...[
          _PillCount(
            label: i == options.length - 1
                ? '${options[i]}+'
                : '${options[i]}',
            active: selected == options[i],
            tone: accent,
            isDark: isDark,
            onTap: () => onChanged(selected == options[i] ? null : options[i]),
          ),
          if (i < options.length - 1) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

class _PillCount extends StatelessWidget {
  final String label;
  final bool active;
  final Color tone;
  final bool isDark;
  final VoidCallback onTap;

  const _PillCount({
    required this.label,
    required this.active,
    required this.tone,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = active ? tone : ThemeHelpers.textColor(context);
    final bg = active
        ? tone.withValues(alpha: isDark ? 0.20 : 0.14)
        : Colors.transparent;
    final border = active
        ? tone.withValues(alpha: isDark ? 0.50 : 0.42)
        : ThemeHelpers.borderColor(context).withValues(alpha: 0.55);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        splashColor: tone.withValues(alpha: 0.14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 32,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border, width: 1),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// Input flat — borda fina, label uppercase pequena acima do campo,
/// ícone prefix opcional. Sem moldura grossa, sem sombra.
class _FilterInput extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData? icon;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;

  const _FilterInput({
    required this.controller,
    required this.label,
    required this.hint,
    this.icon,
    this.suffix,
    this.keyboardType,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.onChanged,
  });

  @override
  State<_FilterInput> createState() => _FilterInputState();
}

class _FilterInputState extends State<_FilterInput> {
  late final FocusNode _focus;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode()
      ..addListener(() {
        if (mounted) setState(() => _focused = _focus.hasFocus);
      });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = AppColors.primary.primary;
    final highlighted = _focused || widget.controller.text.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            fontSize: 9.5,
          ),
        ),
        const SizedBox(height: 6),
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            color: Colors.transparent,
            border: Border.all(
              color: highlighted
                  ? accent.withValues(alpha: isDark ? 0.55 : 0.42)
                  : ThemeHelpers.borderColor(context)
                      .withValues(alpha: 0.55),
              width: highlighted ? 1.4 : 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  size: 15,
                  color: highlighted
                      ? accent
                      : ThemeHelpers.textSecondaryColor(context),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  keyboardType: widget.keyboardType,
                  inputFormatters: widget.inputFormatters,
                  textCapitalization: widget.textCapitalization,
                  onChanged: (v) => widget.onChanged?.call(v),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: ThemeHelpers.textColor(context),
                    height: 1.2,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    hintStyle: theme.textTheme.bodyMedium?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context)
                          .withValues(alpha: 0.6),
                      fontWeight: FontWeight.w500,
                      fontSize: 13.5,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
              if (widget.suffix != null) ...[
                const SizedBox(width: 8),
                widget.suffix!,
              ],
            ],
          ),
        ),
      ],
    );
  }
}
