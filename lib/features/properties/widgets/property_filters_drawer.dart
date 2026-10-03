import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/api_service.dart';
import '../../../../shared/services/cep_service.dart';
import '../../../../shared/services/property_service.dart';
import '../services/property_list_signals_service.dart';
import '../utils/property_status_visual.dart';
import '../utils/property_type_visual.dart';

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

  final _codeController = TextEditingController();

  // Proprietário e endereço (web `PropertyFiltersDrawer.tsx`).
  final _ownerNameController = TextEditingController();
  final _ownerPhoneController = TextEditingController();
  final _numberController = TextEditingController();
  final _unityController = TextEditingController();
  final _towerController = TextEditingController();
  final _blockController = TextEditingController();
  final _lotController = TextEditingController();

  // Faixas de venda e aluguel.
  final _minSaleController = TextEditingController();
  final _maxSaleController = TextEditingController();
  final _minRentController = TextEditingController();
  final _maxRentController = TextEditingController();

  /// Captação: período do cadastro (AAAA-MM-DD) e equipes.
  String? _createdFrom;
  String? _createdTo;
  String? _teamId;
  String? _captorsTeamId;
  String? _responsibleUserId;
  bool _responsibleWithoutCaptor = false;
  String? _sector;
  int? _suites;
  int? _rooms;

  List<PropertyFormTeamOption> _teams = const [];
  List<PropertyFilterMember> _members = const [];
  bool _optionsLoading = true;

  /// Setores sugeridos do web (`constants/propertySectorSuggestions.ts`).
  static const List<String> _kSectorSuggestions = [
    'Setor Norte',
    'Setor Sul',
    'Setor Leste',
    'Setor Oeste',
    'Setor Central',
    'Setor Industrial',
    'Setor Comercial',
    'Setor Residencial',
    'Zona Norte',
    'Zona Sul',
    'Zona Leste',
    'Zona Oeste',
  ];

  // Seleções
  PropertyType? _selectedType;
  PropertyStatus? _selectedStatus;
  int? _bedrooms;
  int? _bathrooms;
  int? _parkingSpaces;

  /// Finalidade (`venda` | `locacao` | `ambos`) — `null` = todas.
  String? _finalidade;

  /// Ordenação escolhida (chave de [_kSortOptions]); `null` = padrão do back.
  String? _sortKey;

  /// Opções de ordenação do web (`constants/propertySortOptions.ts`).
  static const List<({String key, String label, String sortBy, String order})>
      _kSortOptions = [
    (key: 'lastActivity:DESC', label: 'Atividade recente', sortBy: 'lastActivity', order: 'DESC'),
    (key: 'createdAt:DESC', label: 'Mais novos', sortBy: 'createdAt', order: 'DESC'),
    (key: 'createdAt:ASC', label: 'Mais antigos', sortBy: 'createdAt', order: 'ASC'),
    (key: 'updatedAt:DESC', label: 'Ficha atualizada', sortBy: 'updatedAt', order: 'DESC'),
    (key: 'salePrice:DESC', label: 'Maior preço de venda', sortBy: 'salePrice', order: 'DESC'),
    (key: 'salePrice:ASC', label: 'Menor preço de venda', sortBy: 'salePrice', order: 'ASC'),
    (key: 'rentPrice:DESC', label: 'Maior aluguel', sortBy: 'rentPrice', order: 'DESC'),
    (key: 'rentPrice:ASC', label: 'Menor aluguel', sortBy: 'rentPrice', order: 'ASC'),
    (key: 'totalArea:DESC', label: 'Maior área', sortBy: 'totalArea', order: 'DESC'),
    (key: 'title:ASC', label: 'Título A–Z', sortBy: 'title', order: 'ASC'),
    (key: 'code:ASC', label: 'Código crescente', sortBy: 'code', order: 'ASC'),
  ];

  // Serviços
  final CepService _cepService = CepService.instance;
  bool _isSearchingCep = false;

  @override
  void initState() {
    super.initState();
    _loadInitialFilters();
    _loadPickerOptions();
  }

  /// Equipes (`/properties/form-settings`) e membros
  /// (`/users/company-members/simple`) — as mesmas fontes do web.
  Future<void> _loadPickerOptions() async {
    final results = await Future.wait([
      PropertyService.instance.getPropertyFormSettings(),
      PropertyListSignalsService.instance.getCompanyMembers(),
    ]);
    if (!mounted) return;
    final settings =
        results[0] as ApiResponse<PropertyFormSettingsBundle>;
    final teams = [...?settings.data?.teams]
      ..removeWhere((t) => t.id.isEmpty)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    setState(() {
      _teams = settings.success ? teams : const [];
      _members = results[1] as List<PropertyFilterMember>;
      _optionsLoading = false;
    });
  }

  static String? _text(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  static double? _num(TextEditingController c) {
    final t = c.text.trim().replaceAll(',', '.');
    return t.isEmpty ? null : double.tryParse(t);
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _ymdLabel(String? ymd) {
    final d = ymd == null ? null : DateTime.tryParse(ymd);
    if (d == null) return 'Qualquer data';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  List<(String, String)> get _teamOptions => [
        for (final t in _teams) (t.id, t.name),
      ];

  List<(String, String)> get _memberOptions => [
        for (final m in _members)
          (m.id, m.email.isEmpty ? m.name : '${m.name} — ${m.email}'),
      ];

  /// Rótulo do item escolhido; id fora da lista ainda aparece (o web mostra
  /// "fora da lista permitida" em vez de sumir com o filtro).
  String _optionLabel(
    String? id,
    List<(String, String)> options,
    String anyLabel,
  ) {
    if (id == null || id.isEmpty) return anyLabel;
    for (final o in options) {
      if (o.$1 == id) return o.$2;
    }
    return _optionsLoading ? 'Carregando…' : 'Selecionado (fora da lista)';
  }

  Future<void> _chooseOption({
    required String title,
    required List<(String, String)> options,
    required String anyLabel,
    required ValueChanged<String?> onSelected,
    bool searchable = false,
  }) async {
    final picked = await showModalBottomSheet<(String?,)>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _OptionListSheet(
        title: title,
        options: options,
        anyLabel: anyLabel,
        searchable: searchable,
      ),
    );
    if (picked == null || !mounted) return;
    onSelected(picked.$1);
  }

  Future<void> _pickDate({required bool from}) async {
    final current = DateTime.tryParse((from ? _createdFrom : _createdTo) ?? '');
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: from ? 'Cadastrado a partir de' : 'Cadastrado até',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (from) {
        _createdFrom = _ymd(picked);
      } else {
        _createdTo = _ymd(picked);
      }
    });
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
    _finalidade = filters.finalidade;
    _codeController.text = filters.code ?? '';
    _zipCodeController.text = filters.zipCode ?? '';
    _ownerNameController.text = filters.ownerName ?? '';
    _ownerPhoneController.text = filters.ownerPhone ?? '';
    _numberController.text = filters.number ?? '';
    _unityController.text = filters.propertyUnity ?? '';
    _towerController.text = filters.tower ?? '';
    _blockController.text = filters.block ?? '';
    _lotController.text = filters.lot ?? '';
    _minSaleController.text = filters.minSalePrice?.toStringAsFixed(0) ?? '';
    _maxSaleController.text = filters.maxSalePrice?.toStringAsFixed(0) ?? '';
    _minRentController.text = filters.minRentPrice?.toStringAsFixed(0) ?? '';
    _maxRentController.text = filters.maxRentPrice?.toStringAsFixed(0) ?? '';
    _createdFrom = filters.createdFrom;
    _createdTo = filters.createdTo;
    _teamId = filters.teamId;
    _captorsTeamId = filters.captorsTeamId;
    _responsibleUserId = filters.responsibleUserId;
    _responsibleWithoutCaptor = filters.responsibleWithoutCaptor == true;
    _sector = filters.sector;
    _suites = filters.suites;
    _rooms = filters.rooms;
    final sortKey = '${filters.sortBy}:${filters.sortOrder}';
    _sortKey = _kSortOptions.any((o) => o.key == sortKey) ? sortKey : null;
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
    _codeController.dispose();
    for (final c in [
      _ownerNameController,
      _ownerPhoneController,
      _numberController,
      _unityController,
      _towerController,
      _blockController,
      _lotController,
      _minSaleController,
      _maxSaleController,
      _minRentController,
      _maxRentController,
    ]) {
      c.dispose();
    }
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
    final sort = _kSortOptions.where((o) => o.key == _sortKey).firstOrNull;
    final code = _codeController.text.trim();
    // `withAdvancedFilters` (não `copyWith`): desmarcar um filtro limpa de
    // verdade — antes "Todos os tipos" mantinha o tipo anterior.
    final filters = base.withAdvancedFilters(
      sortBy: sort?.sortBy,
      sortOrder: sort?.order,
      finalidade: _finalidade,
      code: code.isEmpty ? null : code,
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
      // CEP agora vai na query (`zipCode`, como o web) — antes só servia
      // para preencher cidade/bairro.
      zipCode: _text(_zipCodeController),
      sector: _sector,
      ownerName: _text(_ownerNameController),
      ownerPhone: _text(_ownerPhoneController),
      number: _text(_numberController),
      propertyUnity: _text(_unityController),
      tower: _text(_towerController),
      block: _text(_blockController),
      lot: _text(_lotController),
      createdFrom: _createdFrom,
      createdTo: _createdTo,
      teamId: _teamId,
      captorsTeamId: _captorsTeamId,
      responsibleUserId: _responsibleUserId,
      responsibleWithoutCaptor: _responsibleWithoutCaptor ? true : null,
      minSalePrice: _num(_minSaleController),
      maxSalePrice: _num(_maxSaleController),
      minRentPrice: _num(_minRentController),
      maxRentPrice: _num(_maxRentController),
      suites: _suites,
      rooms: _rooms,
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
      _finalidade = null;
      _sortKey = null;
      _codeController.clear();
      for (final c in [
        _ownerNameController,
        _ownerPhoneController,
        _numberController,
        _unityController,
        _towerController,
        _blockController,
        _lotController,
        _minSaleController,
        _maxSaleController,
        _minRentController,
        _maxRentController,
      ]) {
        c.clear();
      }
      _createdFrom = null;
      _createdTo = null;
      _teamId = null;
      _captorsTeamId = null;
      _responsibleUserId = null;
      _responsibleWithoutCaptor = false;
      _sector = null;
      _suites = null;
      _rooms = null;
    });
    // Como o web (`buildClearedDrawerFilters`): limpa só o que é do drawer e
    // mantém aba, "minhas", busca e "só excluídos".
    final base = widget.initialFilters;
    widget.onFiltersChanged(base?.withAdvancedFilters());
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
    if (_finalidade != null) n++;
    if (_sortKey != null) n++;
    if (_codeController.text.trim().isNotEmpty) n++;
    if (_zipCodeController.text.trim().isNotEmpty) n++;
    for (final c in [
      _ownerNameController,
      _ownerPhoneController,
      _numberController,
      _unityController,
      _towerController,
      _blockController,
      _lotController,
      _minSaleController,
      _maxSaleController,
      _minRentController,
      _maxRentController,
    ]) {
      if (c.text.trim().isNotEmpty) n++;
    }
    for (final v in [
      _createdFrom,
      _createdTo,
      _teamId,
      _captorsTeamId,
      _responsibleUserId,
      _sector,
    ]) {
      if ((v ?? '').isNotEmpty) n++;
    }
    if (_responsibleWithoutCaptor) n++;
    if (_suites != null) n++;
    if (_rooms != null) n++;
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
    // Tons das seções Tipo e Status por token (mesmos valores de antes).
    final typeTone =
        isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
    final statusTone =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;

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
                                // Flexible: em 320dp com texto a 130% o
                                // eyebrow + "12 ativos" passava do fechar.
                                Flexible(
                                  child: Text(
                                    'FILTROS AVANÇADOS',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        theme.textTheme.labelSmall?.copyWith(
                                      color: accent,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.65,
                                      fontSize: 10.5,
                                    ),
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
                                      maxLines: 1,
                                      softWrap: false,
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
                        // ── Ordenação ──────────────────────────────────
                        // Mesmas opções do web (`propertySortOptions.ts`).
                        _SectionLabel(label: 'ORDENAR POR', tone: accent),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _FilterChip(
                              label: 'Padrão',
                              icon: LucideIcons.arrowDownUp,
                              active: _sortKey == null,
                              tone: accent,
                              onTap: () => setState(() => _sortKey = null),
                            ),
                            for (final o in _kSortOptions)
                              _FilterChip(
                                label: o.label,
                                icon: o.order == 'ASC'
                                    ? LucideIcons.arrowUpNarrowWide
                                    : LucideIcons.arrowDownWideNarrow,
                                active: _sortKey == o.key,
                                tone: accent,
                                onTap: () => setState(() {
                                  _sortKey = _sortKey == o.key ? null : o.key;
                                }),
                              ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        // ── Finalidade e código ────────────────────────
                        _SectionLabel(label: 'FINALIDADE', tone: typeTone),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final f in const [
                              (null, 'Todas', LucideIcons.layoutGrid),
                              ('venda', 'Venda', LucideIcons.tag),
                              ('locacao', 'Locação', LucideIcons.key),
                              ('ambos', 'Venda e locação', LucideIcons.repeat),
                            ])
                              _FilterChip(
                                label: f.$2,
                                icon: f.$3,
                                active: _finalidade == f.$1,
                                tone: f.$1 == null ? accent : typeTone,
                                onTap: () => setState(() => _finalidade = f.$1),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _FilterInput(
                          controller: _codeController,
                          label: 'Código do imóvel',
                          hint: 'Ex.: AP-1024',
                          icon: LucideIcons.hash,
                          keyboardType: TextInputType.text,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 22),
                        // ── Proprietário e endereço (web) ──────────────
                        const _SectionLabel(
                          label: 'PROPRIETÁRIO E ENDEREÇO',
                          tone: Color(0xFF0EA5E9),
                        ),
                        const SizedBox(height: 8),
                        _FilterInput(
                          controller: _ownerNameController,
                          label: 'Nome do proprietário',
                          hint: 'Parte do nome',
                          icon: LucideIcons.user,
                          textCapitalization: TextCapitalization.words,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 8),
                        _FilterInput(
                          controller: _ownerPhoneController,
                          label: 'Telefone do proprietário',
                          hint: 'Só os dígitos já bastam',
                          icon: LucideIcons.phone,
                          keyboardType: TextInputType.phone,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _FilterInput(
                                controller: _numberController,
                                label: 'Número',
                                hint: 'Ex.: 120',
                                icon: LucideIcons.hash,
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _FilterInput(
                                controller: _unityController,
                                label: 'Apto / unidade',
                                hint: 'Ex.: 302',
                                icon: LucideIcons.doorOpen,
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _FilterInput(
                                controller: _towerController,
                                label: 'Torre / bloco',
                                hint: 'Ex.: B',
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _FilterInput(
                                controller: _blockController,
                                label: 'Quadra',
                                hint: 'Ex.: 12',
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _FilterInput(
                                controller: _lotController,
                                label: 'Lote',
                                hint: 'Ex.: 7',
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        // ── Captação (cadastro) ────────────────────────
                        const _SectionLabel(
                          label: 'CAPTAÇÃO (CADASTRO)',
                          tone: Color(0xFFF97316),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _PickerField(
                                label: 'Data inicial',
                                value: _ymdLabel(_createdFrom),
                                icon: LucideIcons.calendar,
                                active: _createdFrom != null,
                                onTap: () => _pickDate(from: true),
                                onClear: _createdFrom == null
                                    ? null
                                    : () => setState(() => _createdFrom = null),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _PickerField(
                                label: 'Data final',
                                value: _ymdLabel(_createdTo),
                                icon: LucideIcons.calendarCheck,
                                active: _createdTo != null,
                                onTap: () => _pickDate(from: false),
                                onClear: _createdTo == null
                                    ? null
                                    : () => setState(() => _createdTo = null),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _PickerField(
                          label: 'Equipe dos captadores',
                          value: _optionLabel(
                            _captorsTeamId,
                            _teamOptions,
                            'Qualquer equipe',
                          ),
                          icon: LucideIcons.users,
                          active: _captorsTeamId != null,
                          loading: _optionsLoading,
                          onTap: () => _chooseOption(
                            title: 'Equipe dos captadores',
                            options: _teamOptions,
                            anyLabel: 'Qualquer equipe',
                            onSelected: (v) =>
                                setState(() => _captorsTeamId = v),
                          ),
                          onClear: _captorsTeamId == null
                              ? null
                              : () => setState(() => _captorsTeamId = null),
                        ),
                        const SizedBox(height: 8),
                        _PickerField(
                          label: 'Equipe do imóvel',
                          value: _optionLabel(
                            _teamId,
                            _teamOptions,
                            'Todas as equipes',
                          ),
                          icon: LucideIcons.usersRound,
                          active: _teamId != null,
                          loading: _optionsLoading,
                          onTap: () => _chooseOption(
                            title: 'Equipe do imóvel',
                            options: _teamOptions,
                            anyLabel: 'Todas as equipes',
                            onSelected: (v) => setState(() => _teamId = v),
                          ),
                          onClear: _teamId == null
                              ? null
                              : () => setState(() => _teamId = null),
                        ),
                        const SizedBox(height: 22),
                        // ── Corretor responsável ───────────────────────
                        const _SectionLabel(
                          label: 'CORRETOR RESPONSÁVEL',
                          tone: Color(0xFF8B5CF6),
                        ),
                        const SizedBox(height: 8),
                        _PickerField(
                          label: 'Corretor',
                          value: _optionLabel(
                            _responsibleUserId,
                            _memberOptions,
                            'Qualquer responsável',
                          ),
                          icon: LucideIcons.userCheck,
                          active: _responsibleUserId != null,
                          loading: _optionsLoading,
                          onTap: () => _chooseOption(
                            title: 'Corretor responsável',
                            options: _memberOptions,
                            anyLabel: 'Qualquer responsável',
                            searchable: true,
                            onSelected: (v) =>
                                setState(() => _responsibleUserId = v),
                          ),
                          onClear: _responsibleUserId == null
                              ? null
                              : () =>
                                  setState(() => _responsibleUserId = null),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _FilterChip(
                            label: 'Sem captador externo',
                            icon: LucideIcons.userX,
                            active: _responsibleWithoutCaptor,
                            tone: const Color(0xFF8B5CF6),
                            onTap: () => setState(
                              () => _responsibleWithoutCaptor =
                                  !_responsibleWithoutCaptor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        // ── Tipo ───────────────────────────────────────
                        // 16 tipos em 3 grupos (Residencial / Comercial /
                        // Terreno e rural): acha-se o tipo pelo grupo, não
                        // varrendo uma parede de pastilhas. Tipo não tem cor
                        // própria — o ícone diferencia; o tom é o da seção.
                        _SectionLabel(
                          label: 'TIPO DE IMÓVEL',
                          tone: typeTone,
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _FilterChip(
                            label: 'Todos os tipos',
                            icon: LucideIcons.layoutGrid,
                            active: _selectedType == null,
                            tone: accent,
                            onTap: () => setState(() => _selectedType = null),
                          ),
                        ),
                        for (final g in PropertyTypeVisual.grouped())
                          _ChipGroup(
                            caption: g.$1.label,
                            children: [
                              for (final t in g.$2)
                                _FilterChip(
                                  label: t.label,
                                  icon: PropertyTypeVisual.lucide(t),
                                  tone: typeTone,
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
                        // 17 status em fases (cadastro, carteira, funil de
                        // locação, fechados), com a MESMA cor e ícone da pill
                        // do card (PropertyStatusVisual é a fonte única).
                        _SectionLabel(
                          label: 'STATUS DO IMÓVEL',
                          tone: statusTone,
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _FilterChip(
                            label: 'Todos os status',
                            icon: LucideIcons.layoutGrid,
                            active: _selectedStatus == null,
                            tone: accent,
                            onTap: () => setState(() => _selectedStatus = null),
                          ),
                        ),
                        for (final g in PropertyStatusVisual.grouped())
                          _ChipGroup(
                            caption: g.$1.label,
                            children: [
                              for (final s in g.$2)
                                _FilterChip(
                                  label: s.label,
                                  icon: PropertyStatusVisual.of(s).icon,
                                  tone: PropertyStatusVisual.of(
                                    s,
                                    dark: isDark,
                                  ).color,
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
                        const _SectionLabel(
                          label: 'PREÇO',
                          tone: Color(0xFF10B981),
                        ),
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
                        const SizedBox(height: 12),
                        _RangeRow(
                          caption: 'Preço de venda',
                          minController: _minSaleController,
                          maxController: _maxSaleController,
                          onChanged: () => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                        _RangeRow(
                          caption: 'Aluguel',
                          minController: _minRentController,
                          maxController: _maxRentController,
                          onChanged: () => setState(() {}),
                        ),
                        const SizedBox(height: 22),
                        // ── Área ───────────────────────────────────────
                        const _SectionLabel(
                          label: 'ÁREA (m²)',
                          tone: Color(0xFFE6B84C),
                        ),
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
                        const _SectionLabel(
                          label: 'AMBIENTES',
                          tone: Color(0xFF6366F1),
                        ),
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
                          label: 'Suítes',
                          icon: LucideIcons.bedDouble,
                          options: const [1, 2, 3, 4],
                          selected: _suites,
                          onChanged: (v) => setState(() => _suites = v),
                        ),
                        const SizedBox(height: 12),
                        // Imóvel comercial conta salas, não quartos.
                        _CountSelector(
                          label: 'Salas',
                          icon: LucideIcons.briefcase,
                          options: const [1, 2, 3, 4],
                          selected: _rooms,
                          onChanged: (v) => setState(() => _rooms = v),
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
                          tone: Color(0xFF14B8A6),
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
                        const SizedBox(height: 12),
                        _ChipGroup(
                          caption: 'Setor',
                          children: [
                            _FilterChip(
                              label: 'Qualquer setor',
                              icon: LucideIcons.layoutGrid,
                              active: _sector == null,
                              tone: accent,
                              onTap: () => setState(() => _sector = null),
                            ),
                            for (final s in {
                              ..._kSectorSuggestions,
                              ?_sector,
                            })
                              _FilterChip(
                                label: s,
                                icon: LucideIcons.compass,
                                active: _sector == s,
                                tone: const Color(0xFF14B8A6),
                                onTap: () => setState(() {
                                  _sector = _sector == s ? null : s;
                                }),
                              ),
                          ],
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
                            // Neutro — não vermelho (ação secundária).
                            foregroundColor:
                                ThemeHelpers.textSecondaryColor(context),
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
}

// ──────────────────────────────────────────────────────────────────────────
// Componentes do drawer
// ──────────────────────────────────────────────────────────────────────────

/// Label de seção: eyebrow uppercase pequena em accent + subtítulo opcional.
class _SectionLabel extends StatelessWidget {
  final String label;
  final String? subtitle;
  final Color? tone;
  const _SectionLabel({required this.label, this.subtitle, this.tone});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Cada seção tem sua cor coerente (passada por `tone`) — contraste e
    // leitura rápida, sem ser "tudo vermelho".
    final accent = tone ?? AppColors.primary.primary;
    final secondaryColor = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.5),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.only(left: 13),
            child: Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondaryColor,
                fontWeight: FontWeight.w500,
                height: 1.3,
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Grupo de chips com legenda curta ("Residencial", "Funil de locação"):
/// quebra as listas longas de tipo (16) e status (17) em blocos que a pessoa
/// reconhece, em vez de uma parede de pastilhas.
class _ChipGroup extends StatelessWidget {
  final String caption;
  final List<Widget> children;

  const _ChipGroup({required this.caption, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: children),
        ],
      ),
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
              // "Aguardando autorização do proprietário" não cabe numa linha
              // em 320dp com texto a 130%: quebra em 2 dentro da pill em vez
              // de estourar a Wrap.
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    letterSpacing: -0.1,
                    height: 1.2,
                  ),
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
        // 5 pílulas fixas (~176dp) deixam ~80dp ao rótulo em 320dp: reduz em
        // vez de partir "Dormitórios" no meio da palavra com texto a 130%.
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: textColor,
                fontSize: 13,
                letterSpacing: -0.1,
              ),
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

/// Campo de seleção (data, equipe, corretor) no mesmo desenho do
/// [_FilterInput]: label pequena acima, valor, "x" para limpar.
class _PickerField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool active;
  final bool loading;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _PickerField({
    required this.label,
    required this.value,
    required this.icon,
    required this.active,
    required this.onTap,
    this.loading = false,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = AppColors.primary.primary;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: secondary,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            fontSize: 9.5,
          ),
        ),
        const SizedBox(height: 6),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: loading ? null : onTap,
            borderRadius: BorderRadius.circular(11),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              constraints: const BoxConstraints(minHeight: 44),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: active
                      ? accent.withValues(alpha: isDark ? 0.55 : 0.42)
                      : ThemeHelpers.borderColor(context)
                          .withValues(alpha: 0.55),
                  width: active ? 1.4 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 15, color: active ? accent : secondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active
                            ? ThemeHelpers.textColor(context)
                            : secondary,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  if (loading)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (onClear != null)
                    InkWell(
                      onTap: onClear,
                      borderRadius: BorderRadius.circular(999),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.close_rounded,
                            size: 16, color: secondary),
                      ),
                    )
                  else
                    Icon(Icons.expand_more_rounded, size: 18, color: secondary),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Lista de opções em sheet (com busca opcional). Devolve `(id,)` — `(null,)`
/// é "qualquer"; fechar sem escolher devolve `null`.
class _OptionListSheet extends StatefulWidget {
  final String title;
  final List<(String, String)> options;
  final String anyLabel;
  final bool searchable;

  const _OptionListSheet({
    required this.title,
    required this.options,
    required this.anyLabel,
    required this.searchable,
  });

  @override
  State<_OptionListSheet> createState() => _OptionListSheetState();
}

class _OptionListSheetState extends State<_OptionListSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _query.trim().toLowerCase();
    final items = q.isEmpty
        ? widget.options
        : widget.options
            .where((o) => o.$2.toLowerCase().contains(q))
            .toList();
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            if (widget.searchable)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  autofocus: false,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(LucideIcons.search, size: 18),
                    hintText: 'Buscar',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: const Icon(LucideIcons.layoutGrid, size: 18),
                    title: Text(widget.anyLabel),
                    onTap: () => Navigator.of(context).pop((null,)),
                  ),
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Nenhuma opção encontrada.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                      ),
                    ),
                  for (final o in items)
                    ListTile(
                      title: Text(o.$2),
                      onTap: () => Navigator.of(context).pop((o.$1,)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Faixa mínimo/máximo de um valor (venda, aluguel) com legenda curta.
class _RangeRow extends StatelessWidget {
  final String caption;
  final TextEditingController minController;
  final TextEditingController maxController;
  final VoidCallback onChanged;

  const _RangeRow({
    required this.caption,
    required this.minController,
    required this.maxController,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const keyboard = TextInputType.numberWithOptions(decimal: true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          caption,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
              ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _FilterInput(
                controller: minController,
                label: 'Mínimo',
                hint: r'R$ 0',
                icon: LucideIcons.arrowDown,
                keyboardType: keyboard,
                onChanged: (_) => onChanged(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _FilterInput(
                controller: maxController,
                label: 'Máximo',
                hint: r'R$ 0',
                icon: LucideIcons.arrowUp,
                keyboardType: keyboard,
                onChanged: (_) => onChanged(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
