import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../shared/services/property_service.dart';
import '../../../../shared/services/cep_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';

/// Bottom sheet premium de filtros do portfólio de imóveis.
///
/// Identidade visual alinhada com os demais sheets da tela de Imóveis
/// (Quick Actions, Métricas Detalhadas, Busca Rápida, Otimizar Portfólio):
/// - Sheet atracado no rodapé, full-width, bordas só no topo
/// - Header editorial: drag handle + eyebrow accent + título grande w900
/// - Divisor gradient horizontal entre seções
/// - Cada seção tem seu próprio `_FilterSectionTitle` com eyebrow uppercase
/// - ChoiceChips customizados (sem o visual Material padrão)
/// - Inputs com bordas refinadas (sem OutlineInputBorder genérico)
/// - Footer com 2 ações (Limpar / Aplicar) com border-radius e padding
///   consistentes com o resto do app
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

    _minPriceController.text = filters.minPrice?.toString() ?? '';
    _maxPriceController.text = filters.maxPrice?.toString() ?? '';
    _minAreaController.text = filters.minArea?.toString() ?? '';
    _maxAreaController.text = filters.maxArea?.toString() ?? '';
    _zipCodeController.text = '';
    _cityController.text = filters.city ?? '';
    _neighborhoodController.text = filters.neighborhood ?? '';
    _stateController.text = '';
    _selectedType = filters.type;
    _selectedStatus = filters.status;
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
    final filters = PropertyFilters(
      type: _selectedType,
      status: _selectedStatus,
      minPrice: _minPriceController.text.trim().isEmpty
          ? null
          : double.tryParse(_minPriceController.text),
      maxPrice: _maxPriceController.text.trim().isEmpty
          ? null
          : double.tryParse(_maxPriceController.text),
      minArea: _minAreaController.text.trim().isEmpty
          ? null
          : double.tryParse(_minAreaController.text),
      maxArea: _maxAreaController.text.trim().isEmpty
          ? null
          : double.tryParse(_maxAreaController.text),
      city: _cityController.text.trim().isEmpty
          ? null
          : _cityController.text.trim(),
      neighborhood: _neighborhoodController.text.trim().isEmpty
          ? null
          : _neighborhoodController.text.trim(),
    );

    widget.onFiltersChanged(filters);
    Navigator.of(context).pop();
  }

  void _clearFilters() {
    setState(() {
      _minPriceController.clear();
      _maxPriceController.clear();
      _zipCodeController.clear();
      _minAreaController.clear();
      _maxAreaController.clear();
      _cityController.clear();
      _neighborhoodController.clear();
      _stateController.clear();
      _selectedType = null;
      _selectedStatus = null;
    });
    widget.onFiltersChanged(null);
  }

  /// Quantos critérios estão ativos? Usado pra mostrar contagem no header.
  int get _activeCount {
    var n = 0;
    if (_selectedType != null) n++;
    if (_selectedStatus != null) n++;
    if (_minPriceController.text.trim().isNotEmpty) n++;
    if (_maxPriceController.text.trim().isNotEmpty) n++;
    if (_minAreaController.text.trim().isNotEmpty) n++;
    if (_maxAreaController.text.trim().isNotEmpty) n++;
    if (_cityController.text.trim().isNotEmpty) n++;
    if (_neighborhoodController.text.trim().isNotEmpty) n++;
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mq = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        // Sheet atracado no rodapé — full-width, bordas só no topo (28).
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.92),
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(28),
          ),
          border: Border(
            top: BorderSide(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.55),
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
            top: Radius.circular(28),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Drag handle ─────────────────────────────────────────
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: ThemeHelpers.textSecondaryColor(context)
                          .withValues(alpha: 0.32),
                    ),
                  ),
                ),
                // ── Header editorial ───────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 12, 14, 16),
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
                                Text(
                                  'PORTFÓLIO · REFINAR',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: AppColors.primary.primary,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.6,
                                    fontSize: 10,
                                  ),
                                ),
                                if (_activeCount > 0) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius:
                                          BorderRadius.circular(999),
                                      color: AppColors.primary.primary
                                          .withValues(
                                        alpha: isDark ? 0.22 : 0.14,
                                      ),
                                      border: Border.all(
                                        color: AppColors.primary.primary
                                            .withValues(
                                          alpha: isDark ? 0.4 : 0.28,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      '$_activeCount ${_activeCount == 1 ? "ativo" : "ativos"}',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                        color: AppColors.primary.primary,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 9.5,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Filtros do portfólio',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.6,
                                color: ThemeHelpers.textColor(context),
                                height: 1.05,
                                fontSize: 24,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Combine critérios para encontrar os imóveis certos.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color:
                                    ThemeHelpers.textSecondaryColor(context),
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                                fontSize: 13.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        iconSize: 26,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                // ── Divisor gradient ──────────────────────────────────
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 22),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        ThemeHelpers.borderColor(context),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
                // ── Conteúdo scrollável ───────────────────────────────
                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Tipo ────────────────────────────────────────
                        const _FilterSectionTitle(
                          eyebrow: 'CATEGORIA',
                          title: 'Tipo de imóvel',
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _FilterChoiceChip(
                              label: 'Todos',
                              selected: _selectedType == null,
                              onTap: () =>
                                  setState(() => _selectedType = null),
                            ),
                            ...PropertyType.values.map((type) {
                              return _FilterChoiceChip(
                                label: type.label,
                                selected: _selectedType == type,
                                onTap: () => setState(
                                  () => _selectedType =
                                      _selectedType == type ? null : type,
                                ),
                              );
                            }),
                          ],
                        ),
                        const SizedBox(height: 32),
                        // ── Status ──────────────────────────────────────
                        const _FilterSectionTitle(
                          eyebrow: 'DISPONIBILIDADE',
                          title: 'Status do imóvel',
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _FilterChoiceChip(
                              label: 'Todos',
                              selected: _selectedStatus == null,
                              onTap: () =>
                                  setState(() => _selectedStatus = null),
                            ),
                            ...PropertyStatus.values.map((status) {
                              return _FilterChoiceChip(
                                label: status.label,
                                selected: _selectedStatus == status,
                                onTap: () => setState(
                                  () => _selectedStatus =
                                      _selectedStatus == status
                                          ? null
                                          : status,
                                ),
                              );
                            }),
                          ],
                        ),
                        const SizedBox(height: 32),
                        // ── Preço ───────────────────────────────────────
                        const _FilterSectionTitle(
                          eyebrow: 'FAIXA',
                          title: 'Preço',
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _FilterTextField(
                                controller: _minPriceController,
                                label: 'Mínimo',
                                hint: 'R\$ 0',
                                prefixIcon: Icons.south_rounded,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _FilterTextField(
                                controller: _maxPriceController,
                                label: 'Máximo',
                                hint: 'R\$ 0',
                                prefixIcon: Icons.north_rounded,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        // ── Área ────────────────────────────────────────
                        const _FilterSectionTitle(
                          eyebrow: 'DIMENSÃO',
                          title: 'Área (m²)',
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _FilterTextField(
                                controller: _minAreaController,
                                label: 'Mínima',
                                hint: '0 m²',
                                prefixIcon: Icons.square_foot_rounded,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _FilterTextField(
                                controller: _maxAreaController,
                                label: 'Máxima',
                                hint: '0 m²',
                                prefixIcon: Icons.square_foot_rounded,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        // ── Localização ─────────────────────────────────
                        const _FilterSectionTitle(
                          eyebrow: 'ENDEREÇO',
                          title: 'Localização',
                          subtitle:
                              'Digite o CEP para preencher o restante automaticamente.',
                        ),
                        const SizedBox(height: 14),
                        _FilterTextField(
                          controller: _zipCodeController,
                          label: 'CEP',
                          hint: '00000-000',
                          prefixIcon: Icons.pin_drop_outlined,
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
                          },
                          suffix: _isSearchingCep
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: _FilterTextField(
                                controller: _cityController,
                                label: 'Cidade',
                                hint: 'Nome da cidade',
                                prefixIcon: Icons.location_city_rounded,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _FilterTextField(
                                controller: _stateController,
                                label: 'UF',
                                hint: 'SP',
                                textCapitalization:
                                    TextCapitalization.characters,
                                inputFormatters: [
                                  LengthLimitingTextInputFormatter(2),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _FilterTextField(
                          controller: _neighborhoodController,
                          label: 'Bairro',
                          hint: 'Nome do bairro',
                          prefixIcon: Icons.signpost_outlined,
                        ),
                      ],
                    ),
                  ),
                ),
                // ── Footer com ações ──────────────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
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
                          icon: const Icon(
                            Icons.clear_all_rounded,
                            size: 18,
                          ),
                          label: const Text('Limpar'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(
                              color: ThemeHelpers.borderColor(context),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _applyFilters,
                          icon: const Icon(
                            Icons.filter_alt_rounded,
                            size: 18,
                          ),
                          label: Text(
                            _activeCount > 0
                                ? 'Aplicar ($_activeCount)'
                                : 'Aplicar filtros',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
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
}

/// Título de seção do drawer de filtros — eyebrow uppercase em accent +
/// título maior + subtítulo opcional. Mesmo padrão usado nas Métricas
/// detalhadas.
class _FilterSectionTitle extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String? subtitle;

  const _FilterSectionTitle({
    required this.eyebrow,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          eyebrow,
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppColors.primary.primary,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
            fontSize: 9.5,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
            color: ThemeHelpers.textColor(context),
            height: 1.15,
            fontSize: 17,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w500,
              height: 1.3,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}

/// Chip de seleção customizado — substitui o `ChoiceChip` Material.
/// Estado idle: borda neutra + texto secundário.
/// Estado selecionado: borda accent + fundo tinted accent + texto accent w800.
class _FilterChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = AppColors.primary.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: selected
                ? Color.alphaBlend(
                    accent.withValues(alpha: isDark ? 0.18 : 0.10),
                    ThemeHelpers.cardBackgroundColor(context),
                  )
                : ThemeHelpers.cardBackgroundColor(context),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: isDark ? 0.55 : 0.4)
                  : ThemeHelpers.borderColor(context),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(
                  Icons.check_rounded,
                  size: 14,
                  color: accent,
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selected
                      ? accent
                      : ThemeHelpers.textColor(context).withValues(
                          alpha: 0.85,
                        ),
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  letterSpacing: -0.05,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Campo de texto refinado — label uppercase pequena + input com borda
/// arredondada + ícone prefix opcional. Substitui o `OutlineInputBorder`
/// Material padrão por algo mais coerente com o resto do sheet.
class _FilterTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData? prefixIcon;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;

  const _FilterTextField({
    required this.controller,
    required this.label,
    required this.hint,
    this.prefixIcon,
    this.suffix,
    this.keyboardType,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.onChanged,
  });

  @override
  State<_FilterTextField> createState() => _FilterTextFieldState();
}

class _FilterTextFieldState extends State<_FilterTextField> {
  late final FocusNode _focus;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode();
    _focus.addListener(() {
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
            borderRadius: BorderRadius.circular(13),
            color: ThemeHelpers.cardBackgroundColor(context),
            border: Border.all(
              color: highlighted
                  ? accent.withValues(alpha: isDark ? 0.55 : 0.4)
                  : ThemeHelpers.borderColor(context),
              width: highlighted ? 1.4 : 1,
            ),
            boxShadow: highlighted
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: isDark ? 0.14 : 0.08),
                      blurRadius: 10,
                      spreadRadius: -3,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Row(
              children: [
                if (widget.prefixIcon != null) ...[
                  Icon(
                    widget.prefixIcon,
                    size: 17,
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
                    onChanged: (v) {
                      widget.onChanged?.call(v);
                      // Pra atualizar a borda highlighted enquanto digita
                      // (ex.: campo deixa de estar vazio).
                      if (mounted) setState(() {});
                    },
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: ThemeHelpers.textColor(context),
                      height: 1.2,
                    ),
                    decoration: InputDecoration(
                      hintText: widget.hint,
                      hintStyle: theme.textTheme.bodyMedium?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context)
                            .withValues(alpha: 0.6),
                        fontWeight: FontWeight.w500,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 14,
                      ),
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
        ),
      ],
    );
  }
}
