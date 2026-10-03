import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/property_service.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/shimmer_image.dart';
import '../services/nearby_places_service.dart';
import '../services/property_map_service.dart';
import '../widgets/property_filters_drawer.dart';

/// Mapa da carteira — paridade com `PropertiesMapExplorer.tsx` (web),
/// rota `/properties/map`, gate `property:view` (o mesmo da listagem).
///
/// Abre com os filtros que estavam na listagem (o web lê os mesmos filtros
/// salvos da lista). Aqui dá para trocar a aba, buscar, ligar "só os meus" e
/// tirar filtros pelos chips; o back devolve até 120 imóveis por vez (os mais
/// vistos no site) e, ao mover o mapa, "Pesquisar nesta área" refaz a busca
/// só no retângulo visível.
///
/// Mesmo comportamento do web: pinos com preço coloridos pelo agrupamento
/// (cidade, valor, operação, tipo, status), legenda que esconde grupos,
/// agrupamento por proximidade (raio 70 px, desligado no zoom 18), médias da
/// área visível, lista agrupada com ordenação e o card do imóvel com Abrir,
/// vista de rua, WhatsApp e link.
class PropertiesMapPage extends StatefulWidget {
  const PropertiesMapPage({super.key, this.initialFilters});

  /// Filtros da listagem no momento em que o mapa foi aberto.
  final PropertyFilters? initialFilters;

  @override
  State<PropertiesMapPage> createState() => _PropertiesMapPageState();
}

/// Agrupamento escolhido — lembrado durante a sessão (o web guarda no
/// `localStorage`).
PropertyMapGroupBy _sessionGroupBy = PropertyMapGroupBy.city;

const String _webBase = 'https://intellisysbr.com/sistema';
const LatLng _brazilCenter = LatLng(-14.235, -51.925);

class _PropertiesMapPageState extends State<PropertiesMapPage> {
  final MapController _map = MapController();
  final GlobalKey _mapKey = GlobalKey();
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  Timer? _cameraDebounce;

  late PropertyFilters _baseFilters;
  PortfolioScope? _scope;
  String _search = '';
  bool _onlyMine = false;

  PropertyMapGroupBy _groupBy = _sessionGroupBy;
  PropertyMapSort _sort = PropertyMapSort.relevance;
  final Set<String> _hiddenGroups = {};
  final Set<String> _collapsedGroups = {};
  bool _showList = false;

  List<PropertyMapMarker> _markers = const [];
  bool _truncated = false;
  bool _loading = true;
  String? _error;
  int _errorStatus = 0;
  Object? _errorDetail;
  int _ticket = 0;
  int? _activeOnSite;

  bool _mapReady = false;
  bool _pendingFit = false;
  bool _areaSearchAvailable = false;
  double _zoom = 4;
  PropertyMapBounds? _viewport;
  String? _selectedId;

  /// "Tela cheia" do web: aqui some o cabeçalho e o mapa ocupa a tela toda.
  bool _fullscreen = false;

  // Lugares próximos (Overpass/OSM) — ligado por padrão, como no web.
  bool _nearbyOn = true;
  bool _nearbyLoading = false;
  bool _nearbyFailed = false;
  List<NearbyPlace> _nearby = const [];
  (double, double)? _nearbyCenter;
  String? _nearbyBaseId;
  int _nearbyTicket = 0;

  @override
  void initState() {
    super.initState();
    final base = widget.initialFilters ?? PropertyFilters();
    _scope = base.portfolioScope;
    _search = (base.search ?? '').trim();
    _searchCtrl.text = _search;
    _onlyMine = base.onlyMyData == true;
    _baseFilters = composePropertyMapFilters(base: base);
    _load(refit: true);
    _loadActiveOnSite();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _cameraDebounce?.cancel();
    _searchCtrl.dispose();
    _map.dispose();
    super.dispose();
  }

  PropertyFilters get _effectiveFilters => composePropertyMapFilters(
    base: _baseFilters,
    scope: _scope,
    search: _search,
    onlyMine: _onlyMine,
  );

  Future<void> _loadActiveOnSite() async {
    final res = await PropertyService.instance.getPropertyStats();
    if (!mounted) return;
    if (res.success && res.data != null) {
      setState(() => _activeOnSite = res.data!.available);
    }
  }

  Future<void> _load({bool refit = false, PropertyMapBounds? bounds}) async {
    final ticket = ++_ticket;
    setState(() {
      _loading = true;
      _error = null;
      _areaSearchAvailable = false;
    });
    final res = await PropertyMapService.instance.getMarkers(
      filters: _effectiveFilters,
      bounds: bounds,
    );
    if (!mounted || ticket != _ticket) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _markers = res.data!.markers;
        _truncated = res.data!.truncated;
        if (_selectedId != null && !_markers.any((m) => m.id == _selectedId)) {
          _selectedId = null;
        }
      } else {
        _error = res.message ?? 'Erro ao carregar o mapa';
        _errorStatus = res.statusCode;
        _errorDetail = res.error;
      }
    });
    if (refit && res.success) _fitToMarkers();
  }

  Future<void> _reload() => _load(refit: true);

  void _fitToMarkers() {
    if (!_mapReady) {
      _pendingFit = true;
      return;
    }
    final focus = pickDensestMapRegion(_visibleMarkers);
    if (focus.isEmpty) return;
    final points = [for (final m in focus) LatLng(m.lat, m.lng)];
    try {
      if (points.length == 1) {
        _map.move(points.first, 15);
      } else {
        _map.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(points),
            padding: const EdgeInsets.fromLTRB(48, 96, 48, 72),
            maxZoom: 16,
          ),
        );
      }
    } catch (_) {
      // Mapa ainda sem tamanho (troca de aba) — enquadra na próxima vez.
      _pendingFit = true;
    }
    _syncCamera();
  }

  void _syncCamera() {
    if (!_mapReady) return;
    final cam = _map.camera;
    final b = cam.visibleBounds;
    setState(() {
      _zoom = cam.zoom;
      _viewport = PropertyMapBounds(
        north: b.north,
        south: b.south,
        east: b.east,
        west: b.west,
      );
    });
    _maybeLoadNearby();
  }

  // ── Lugares próximos ─────────────────────────────────────────────────

  /// Zoom mínimo para buscar POIs: o raio é de 1,8 km; num zoom de país a
  /// busca no centro da tela não diz nada (e gasta o Overpass público).
  static const double _nearbyMinZoom = 11;

  void _maybeLoadNearby({bool force = false}) {
    if (!_nearbyOn || !_mapReady) return;
    final sel = _selected;
    if (sel == null && _zoom < _nearbyMinZoom) return;
    final cam = _map.camera.center;
    final center = sel != null
        ? (sel.lat, sel.lng)
        : (cam.latitude, cam.longitude);
    final baseChanged = sel?.id != _nearbyBaseId;
    if (!force &&
        !shouldRefetchNearby(
          previous: _nearbyCenter,
          next: center,
          anchoredOnSelection: baseChanged,
        )) {
      return;
    }
    _nearbyCenter = center;
    _nearbyBaseId = sel?.id;
    final ticket = ++_nearbyTicket;
    setState(() {
      _nearbyLoading = true;
      _nearbyFailed = false;
    });
    NearbyPlacesService.instance
        .fetch(lat: center.$1, lng: center.$2)
        .then((places) {
          if (!mounted || ticket != _nearbyTicket) return;
          setState(() {
            _nearby = places;
            _nearbyLoading = false;
          });
        })
        .catchError((Object _) {
          if (!mounted || ticket != _nearbyTicket) return;
          setState(() {
            _nearby = const [];
            _nearbyFailed = true;
            _nearbyLoading = false;
          });
        });
  }

  void _toggleNearby() {
    setState(() {
      _nearbyOn = !_nearbyOn;
      _nearbyTicket++;
      _nearby = const [];
      _nearbyLoading = false;
      _nearbyFailed = false;
      _nearbyCenter = null;
      _nearbyBaseId = null;
    });
    if (_nearbyOn) _maybeLoadNearby(force: true);
  }

  void _selectMarker(String? id) {
    setState(() => _selectedId = id);
    _maybeLoadNearby();
  }

  void _showPlace(NearbyPlace p) {
    final cat = nearbyCategoryOf(p.category);
    _toast(
      '${cat.label}: ${p.name}${p.address == null ? '' : ' • ${p.address}'}',
    );
  }

  // ── Filtros avançados (mesmo drawer da lista) ────────────────────────

  void _openFiltersDrawer() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black54,
      backgroundColor: Colors.transparent,
      builder: (_) => PropertyFiltersDrawer(
        initialFilters: _baseFilters,
        onFiltersChanged: (filters) {
          setState(() {
            _baseFilters = composePropertyMapFilters(
              base: filters ?? PropertyFilters(),
            );
          });
          _load(refit: true);
        },
      ),
    );
  }

  void _setFullscreen(bool value) {
    setState(() {
      _fullscreen = value;
      if (value) _showList = false;
    });
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    if (hasGesture && !_areaSearchAvailable && !_loading) {
      setState(() => _areaSearchAvailable = true);
    }
    _cameraDebounce?.cancel();
    _cameraDebounce = Timer(const Duration(milliseconds: 140), () {
      if (mounted) _syncCamera();
    });
  }

  void _searchThisArea() {
    final v = _viewport;
    if (v == null) return;
    _load(bounds: v);
  }

  // ── Filtros ──────────────────────────────────────────────────────────

  void _setScope(PortfolioScope? scope) {
    if (scope == _scope) return;
    setState(() => _scope = scope);
    _load(refit: true);
  }

  void _toggleMine() {
    setState(() => _onlyMine = !_onlyMine);
    _load(refit: true);
  }

  void _removeChip(String key) {
    setState(() => _baseFilters = propertyFiltersWithout(_baseFilters, key));
    _load(refit: true);
  }

  void _onSearchChanged(String value) {
    setState(() {});
    _searchDebounce?.cancel();
    // Mesmo atraso do web (3 s) — Enter aplica na hora.
    _searchDebounce = Timer(const Duration(seconds: 3), () => _commitSearch());
  }

  void _commitSearch() {
    _searchDebounce?.cancel();
    final term = _searchCtrl.text.trim();
    if (term == _search) return;
    setState(() => _search = term);
    _load(refit: true);
  }

  void _clearSearch() {
    _searchCtrl.clear();
    _commitSearch();
  }

  void _setGroupBy(PropertyMapGroupBy g) {
    setState(() {
      _groupBy = g;
      _sessionGroupBy = g;
      _hiddenGroups.clear();
      _collapsedGroups.clear();
    });
  }

  // ── Derivados ────────────────────────────────────────────────────────

  PropertyMapGrouping get _grouping =>
      buildPropertyMapGroups(sortPropertyMapMarkers(_markers, _sort), _groupBy);

  List<PropertyMapMarker> get _visibleMarkers {
    if (_hiddenGroups.isEmpty) return _markers;
    final g = _grouping;
    final ids = <String>{
      for (final group in g.groups)
        if (!_hiddenGroups.contains(group.key))
          for (final m in group.markers) m.id,
    };
    return _markers.where((m) => ids.contains(m.id)).toList();
  }

  PropertyMapMarker? get _selected {
    final id = _selectedId;
    if (id == null) return null;
    for (final m in _markers) {
      if (m.id == id) return m;
    }
    return null;
  }

  // ── Ações ────────────────────────────────────────────────────────────

  void _openProperty(String id) {
    Navigator.of(context).pushNamed(AppRoutes.propertyDetails(id));
  }

  void _focusMarker(PropertyMapMarker m) {
    setState(() {
      _selectedId = m.id;
      _showList = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_mapReady) return;
      final z = _map.camera.zoom < 16 ? 16.0 : _map.camera.zoom;
      _map.move(LatLng(m.lat, m.lng), z);
      _syncCamera();
    });
  }

  void _zoomIntoCluster(PropertyMapCluster c) {
    final points = [for (final m in c.markers) LatLng(m.lat, m.lng)];
    final bounds = LatLngBounds.fromPoints(points);
    final degenerate =
        (bounds.north - bounds.south).abs() < 1e-6 &&
        (bounds.east - bounds.west).abs() < 1e-6;
    if (degenerate) {
      _map.move(points.first, (_map.camera.zoom + 3).clamp(3, 19).toDouble());
    } else {
      _map.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(64),
          maxZoom: 19,
        ),
      );
    }
    _syncCamera();
  }

  Future<void> _launch(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) _toast('Não foi possível abrir o link.');
    } catch (_) {
      if (mounted) _toast('Não foi possível abrir o link.');
    }
  }

  void _openStreetView(PropertyMapMarker m) => _launch(
    Uri.parse('https://www.mapillary.com/app/?lat=${m.lat}&lng=${m.lng}&z=17'),
  );

  String _priceText(PropertyMapMarker m) {
    if (m.hasSale) return 'Venda ${_money(m.salePrice!)}';
    if (m.hasRent) return 'Aluguel ${_money(m.rentPrice!)}/mês';
    return '';
  }

  void _shareWhatsApp(PropertyMapMarker m) {
    final price = _priceText(m);
    final text =
        '${m.title}${price.isEmpty ? '' : ' — $price'}\n'
        '$_webBase/properties/${m.id}';
    _launch(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'));
  }

  Future<void> _copyLink(PropertyMapMarker m) async {
    await Clipboard.setData(
      ClipboardData(text: '$_webBase/properties/${m.id}'),
    );
    if (mounted) _toast('Link copiado');
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
      );
  }

  void _pickGroupBy() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: ThemeHelpers.cardBackgroundColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AGRUPAR POR',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.primary.primary,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Cor dos pinos, legenda e seções da lista',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(ctx),
                ),
              ),
              const SizedBox(height: 10),
              for (final g in PropertyMapGroupBy.values)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: Icon(
                    _groupIcon(g),
                    color: AppColors.primary.primary,
                  ),
                  title: Text(
                    g.label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  trailing: g == _groupBy
                      ? Icon(
                          LucideIcons.check,
                          color: AppColors.primary.primary,
                        )
                      : null,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _setGroupBy(g);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  static IconData _groupIcon(PropertyMapGroupBy g) => switch (g) {
    PropertyMapGroupBy.city => LucideIcons.building2,
    PropertyMapGroupBy.price => LucideIcons.badgeDollarSign,
    PropertyMapGroupBy.operation => LucideIcons.arrowLeftRight,
    PropertyMapGroupBy.type => LucideIcons.house,
    PropertyMapGroupBy.status => LucideIcons.circleDot,
  };

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final grouping = _grouping;
    if (_fullscreen) {
      // Tela cheia: sem cabeçalho nem filtros — só o mapa e seus controles.
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _setFullscreen(false);
        },
        child: Scaffold(
          body: SafeArea(bottom: false, child: _mapView(context, grouping)),
        ),
      );
    }
    return AppScaffold(
      title: 'Mapa de imóveis',
      showBottomNavigation: false,
      actions: [
        IconButton(
          tooltip: _showList ? 'Ver mapa' : 'Ver lista',
          onPressed: () => setState(() => _showList = !_showList),
          icon: Icon(_showList ? LucideIcons.map : LucideIcons.list, size: 20),
        ),
        IconButton(
          tooltip: 'Atualizar',
          onPressed: _loading ? null : _reload,
          icon: const Icon(LucideIcons.refreshCw, size: 20),
        ),
      ],
      body: Column(
        children: [
          _header(context),
          Expanded(
            child: _error != null && _markers.isEmpty
                ? AppErrorState.fromApi(
                    message: _error,
                    statusCode: _errorStatus,
                    error: _errorDetail,
                    onRetry: _reload,
                  )
                : IndexedStack(
                    index: _showList ? 1 : 0,
                    children: [
                      _mapView(context, grouping),
                      _listView(context, grouping),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = AppColors.primary.primary;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final chips = buildPropertyMapFilterChips(_baseFilters);
    final ignored = propertyMapIgnoredFilterKeys(_baseFilters);
    final tabs = [
      ...kPropertyMapTabs,
      if (_scope != null && !kPropertyMapTabs.any((t) => t.$1 == _scope))
        (_scope, _scopeLabel(_scope!)),
    ];
    final success = isDark
        ? AppColors.status.successDarkMode
        : AppColors.status.success;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MAPA DA CARTEIRA',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.6,
                        fontSize: 10.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _loading
                          ? 'Carregando imóveis…'
                          : '${_markers.length} '
                                '${_markers.length == 1 ? 'imóvel' : 'imóveis'} no mapa',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                  ],
                ),
              ),
              Tooltip(
                message:
                    'Imóveis ativos e publicados no site '
                    '(não considera os filtros do mapa)',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: success.withValues(alpha: isDark ? 0.2 : 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: success.withValues(alpha: isDark ? 0.4 : 0.28),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _activeOnSite == null
                            ? '—'
                            : NumberFormat.decimalPattern(
                                'pt_BR',
                              ).format(_activeOnSite),
                        style: TextStyle(
                          color: success,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'no site',
                        style: TextStyle(
                          color: success,
                          fontWeight: FontWeight.w600,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearchChanged,
                  onSubmitted: (_) => _commitSearch(),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Endereço, condomínio, código…',
                    prefixIcon: Icon(
                      LucideIcons.search,
                      size: 18,
                      color: muted,
                    ),
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Limpar busca',
                            icon: Icon(LucideIcons.x, size: 16, color: muted),
                            onPressed: _clearSearch,
                          ),
                    filled: true,
                    fillColor: ThemeHelpers.cardBackgroundColor(context),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: ThemeHelpers.borderColor(context),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: ThemeHelpers.borderColor(context),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: accent, width: 1.4),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _SquareToggle(
                icon: LucideIcons.slidersHorizontal,
                active: chips.isNotEmpty || ignored.isNotEmpty,
                badge: chips.length + ignored.length,
                tooltip: 'Filtros',
                onTap: _openFiltersDrawer,
              ),
              const SizedBox(width: 8),
              _SquareToggle(
                icon: _onlyMine ? LucideIcons.userCheck : LucideIcons.user,
                active: _onlyMine,
                tooltip: 'Só os meus',
                onTap: _toggleMine,
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, i) {
                final (scope, label) = tabs[i];
                final selected = scope == _scope;
                return ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) => _setScope(scope),
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    color: selected ? accent : ThemeHelpers.textColor(context),
                  ),
                  selectedColor: accent.withValues(alpha: isDark ? 0.22 : 0.12),
                  side: BorderSide(
                    color: selected
                        ? accent.withValues(alpha: 0.5)
                        : ThemeHelpers.borderColor(context),
                  ),
                );
              },
            ),
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: chips.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, i) {
                  final chip = chips[i];
                  return InputChip(
                    label: Text(chip.label),
                    onDeleted: () => _removeChip(chip.key),
                    deleteIcon: const Icon(LucideIcons.x, size: 13),
                    deleteButtonTooltipMessage: 'Remover filtro',
                    visualDensity: VisualDensity.compact,
                    labelStyle: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                    backgroundColor: accent.withValues(
                      alpha: isDark ? 0.2 : 0.1,
                    ),
                    side: BorderSide.none,
                    deleteIconColor: accent,
                  );
                },
              ),
            ),
          ],
          if (ignored.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(LucideIcons.info, size: 13, color: muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    ignored.length == 1
                        ? '1 filtro da lista não vale no mapa (o servidor do '
                              'mapa não o aplica).'
                        : '${ignored.length} filtros da lista não valem no '
                              'mapa (o servidor do mapa não os aplica).',
                    style: TextStyle(fontSize: 11.5, color: muted),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    var f = _baseFilters;
                    for (final k in ignored) {
                      f = propertyFiltersWithout(f, k);
                    }
                    setState(() => _baseFilters = f);
                  },
                  child: const Text('Remover'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _scopeLabel(PortfolioScope s) => switch (s) {
    PortfolioScope.available => 'Disponíveis',
    PortfolioScope.pending => 'Pendentes',
    PortfolioScope.rejected => 'Recusados',
    PortfolioScope.sold => 'Vendidos',
    PortfolioScope.rented => 'Locados',
    PortfolioScope.negotiation => 'Em negociação',
    PortfolioScope.others => 'Outros',
    PortfolioScope.inactive => 'Inativos',
  };

  // ── Mapa ─────────────────────────────────────────────────────────────

  Widget _mapView(BuildContext context, PropertyMapGrouping grouping) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final visible = _visibleMarkers;
    final clusters = clusterPropertyMapMarkers(visible, _zoom);
    final selected = _selected;
    final stats = computePropertyMapAreaStats(visible, _viewport);
    final brand = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;

    final markers = <Marker>[];
    for (final c in clusters) {
      if (c.isSingle) {
        final m = c.markers.first;
        final label = mapPillPriceLabel(m);
        final width = (label.length * 7.4 + 28 + 17).clamp(58, 180).toDouble();
        final isSel = m.id == _selectedId;
        markers.add(
          Marker(
            key: ValueKey('m-${m.id}'),
            point: LatLng(m.lat, m.lng),
            width: width,
            height: 37,
            alignment: Alignment.topCenter,
            child: GestureDetector(
              onTap: () => _selectMarker(m.id),
              child: _PricePin(
                label: label,
                color: isSel
                    ? brand
                    : (grouping.colorByMarkerId[m.id] ?? kMapNeutralColor),
                highlighted: isSel,
              ),
            ),
          ),
        );
      } else {
        final n = c.markers.length;
        final size = n < 10 ? 44.0 : (n < 100 ? 56.0 : 70.0);
        markers.add(
          Marker(
            key: ValueKey('c-${c.markers.first.id}-$n'),
            point: LatLng(c.lat, c.lng),
            width: size,
            height: size,
            child: GestureDetector(
              onTap: () => _zoomIntoCluster(c),
              child: _ClusterBubble(count: n, size: size, color: brand),
            ),
          ),
        );
      }
    }
    // Selecionado por último = desenhado por cima.
    markers.sort((a, b) {
      final ka = a.key == ValueKey('m-$_selectedId') ? 1 : 0;
      final kb = b.key == ValueKey('m-$_selectedId') ? 1 : 0;
      return ka.compareTo(kb);
    });

    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          // GlobalKey: entrar/sair da tela cheia move o mapa de lugar na
          // árvore sem recriá-lo (mantém posição e zoom).
          key: _mapKey,
          mapController: _map,
          options: MapOptions(
            initialCenter: _brazilCenter,
            initialZoom: 4,
            minZoom: 3,
            maxZoom: 19,
            backgroundColor: isDark
                ? const Color(0xFF11151F)
                : const Color(0xFFE9ECF3),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onMapReady: () {
              _mapReady = true;
              // Fora do build: o callback roda no initState do mapa.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                if (_pendingFit && _markers.isNotEmpty) {
                  _pendingFit = false;
                  _fitToMarkers();
                } else {
                  _syncCamera();
                }
              });
            },
            onPositionChanged: _onPositionChanged,
            onTap: (_, _) {
              if (_selectedId != null) _selectMarker(null);
            },
          ),
          children: [
            TileLayer(
              // Mesmos tiles do web/detalhe: CARTO Positron / Dark Matter.
              urlTemplate: isDark
                  ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                  : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
              maxZoom: 20,
              userAgentPackageName: 'com.dreamkeys.corretor',
            ),
            if (_nearbyOn && _nearby.isNotEmpty)
              MarkerLayer(
                markers: [
                  for (final p in _nearby)
                    Marker(
                      key: ValueKey('poi-${p.id}'),
                      point: LatLng(p.lat, p.lng),
                      width: 30,
                      height: 30,
                      child: GestureDetector(
                        onTap: () => _showPlace(p),
                        child: _PoiDot(category: p.category),
                      ),
                    ),
                ],
              ),
            MarkerLayer(markers: markers),
          ],
        ),
        if (_loading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 2.5),
          ),
        // Legenda / agrupamento
        Positioned(
          top: 10,
          left: 0,
          right: 0,
          child: _legend(context, grouping),
        ),
        Positioned(
          top: 54,
          left: 12,
          right: 12,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _truncated && !_loading
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: _GlassPill(
                          icon: LucideIcons.info,
                          text: 'Até 120 por vez · aproxime e pesquise na área',
                          margin: EdgeInsets.zero,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: 8),
              _MapRoundButton(
                icon: LucideIcons.mapPinned,
                tooltip: 'Lugares próximos',
                active: _nearbyOn,
                onTap: _toggleNearby,
              ),
              const SizedBox(width: 6),
              _MapRoundButton(
                icon: _fullscreen
                    ? LucideIcons.minimize2
                    : LucideIcons.maximize2,
                tooltip: _fullscreen ? 'Sair da tela cheia' : 'Tela cheia',
                active: _fullscreen,
                onTap: () => _setFullscreen(!_fullscreen),
              ),
            ],
          ),
        ),
        if (_nearbyOn)
          Positioned(
            top: 100,
            right: 12,
            child: _NearbyPanel(
              loading: _nearbyLoading,
              failed: _nearbyFailed,
              tooFar: _selected == null && _zoom < _nearbyMinZoom,
              places: _nearby,
              anchoredOnSelection: _selected != null,
            ),
          ),
        if (!_loading && _markers.isEmpty && _error == null)
          Center(
            child: _GlassPill(
              icon: LucideIcons.mapPinOff,
              text: 'Nenhum imóvel com localização nestes filtros',
            ),
          ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_areaSearchAvailable && !_loading)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: FilledButton.icon(
                    onPressed: _searchThisArea,
                    icon: const Icon(LucideIcons.refreshCw, size: 16),
                    label: const Text('Pesquisar nesta área'),
                    style: FilledButton.styleFrom(
                      backgroundColor: brand,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      elevation: 6,
                    ),
                  ),
                ),
              if (selected != null)
                _SelectedCard(
                  marker: selected,
                  onClose: () => _selectMarker(null),
                  onOpen: () => _openProperty(selected.id),
                  onStreet: () => _openStreetView(selected),
                  onWhatsApp: () => _shareWhatsApp(selected),
                  onCopy: () => _copyLink(selected),
                )
              else if (stats.count > 0 && !_loading)
                _AreaStatsStrip(stats: stats, money: _money),
            ],
          ),
        ),
        Positioned(
          right: 6,
          bottom: 2,
          child: IgnorePointer(
            child: Text(
              '© OpenStreetMap · CARTO',
              style: TextStyle(
                fontSize: 8.5,
                color: (isDark ? Colors.white : Colors.black).withValues(
                  alpha: 0.45,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _legend(BuildContext context, PropertyMapGrouping grouping) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _GlassButton(
            icon: _groupIcon(_groupBy),
            label: _groupBy.label,
            trailing: LucideIcons.chevronDown,
            onTap: _pickGroupBy,
          ),
          for (final g in grouping.groups) ...[
            const SizedBox(width: 6),
            _LegendChip(
              color: g.color,
              label: g.label,
              count: g.markers.length,
              hidden: _hiddenGroups.contains(g.key),
              onTap: () => setState(() {
                if (!_hiddenGroups.remove(g.key)) _hiddenGroups.add(g.key);
              }),
            ),
          ],
        ],
      ),
    );
  }

  // ── Lista ────────────────────────────────────────────────────────────

  Widget _listView(BuildContext context, PropertyMapGrouping grouping) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final accent = AppColors.primary.primary;
    final visibleGroups = grouping.groups
        .where((g) => !_hiddenGroups.contains(g.key))
        .toList();
    final stats = computePropertyMapAreaStats(_visibleMarkers, _viewport);

    if (_loading && _markers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _truncated
                              ? '${_markers.length} no mapa · aproxime para ver mais'
                              : '${_markers.length} '
                                    '${_markers.length == 1 ? 'imóvel' : 'imóveis'}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: muted,
                          ),
                        ),
                      ),
                      PopupMenuButton<PropertyMapSort>(
                        initialValue: _sort,
                        onSelected: (s) => setState(() => _sort = s),
                        itemBuilder: (_) => [
                          for (final s in PropertyMapSort.values)
                            PopupMenuItem(value: s, child: Text(s.label)),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: ThemeHelpers.borderColor(context),
                            ),
                            color: ThemeHelpers.cardBackgroundColor(context),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.arrowUpDown,
                                size: 14,
                                color: accent,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _sort.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: accent.withValues(alpha: 0.18)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(LucideIcons.info, size: 15, color: accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Exibimos até 120 imóveis por vez para manter o '
                            'mapa rápido. Prioridade: os mais visitados no '
                            'site; sem histórico, entram os mais novos.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: muted,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (stats.count > 0) ...[
                    const SizedBox(height: 10),
                    _AreaStatsStrip(stats: stats, money: _money, flat: true),
                  ],
                ],
              ),
            ),
          ),
          if (_markers.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.map, size: 40, color: muted),
                    const SizedBox(height: 12),
                    Text(
                      'Nenhum imóvel nesta área',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ajuste os filtros ou mova o mapa para explorar outra '
                      'região.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
            ),
          for (final g in visibleGroups) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                child: _GroupHeader(
                  group: g,
                  collapsed: _collapsedGroups.contains(g.key),
                  onTap: () => setState(() {
                    if (!_collapsedGroups.remove(g.key)) {
                      _collapsedGroups.add(g.key);
                    }
                  }),
                ),
              ),
            ),
            if (!_collapsedGroups.contains(g.key))
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.separated(
                  itemCount: g.markers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final m = g.markers[i];
                    return _MarkerCard(
                      marker: m,
                      accent: grouping.colorByMarkerId[m.id] ?? g.color,
                      money: _money,
                      onOpen: () => _openProperty(m.id),
                      onShowOnMap: () => _focusMarker(m),
                    );
                  },
                ),
              ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

String _money(double v) => NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 0,
).format(v);

(String, Color) _statusStyle(String status, bool isDark) {
  switch (status) {
    case 'available':
      return ('Disponível', const Color(0xFF059669));
    case 'sold':
      return (
        'Vendido',
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
      );
    case 'rented':
      return ('Alugado', const Color(0xFFB45309));
    default:
      final label = PropertyStatus.labelOf(status);
      return (label.isEmpty ? 'Sem status' : label, const Color(0xFF2563EB));
  }
}

// ─── Widgets ──────────────────────────────────────────────────────────────

class _SquareToggle extends StatelessWidget {
  const _SquareToggle({
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primary.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: Badge(
        isLabelVisible: badge > 0,
        label: Text('$badge'),
        backgroundColor: accent,
        child: Material(
          color: active
              ? accent.withValues(alpha: isDark ? 0.24 : 0.12)
              : ThemeHelpers.cardBackgroundColor(context),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: active
                      ? accent.withValues(alpha: 0.5)
                      : ThemeHelpers.borderColor(context),
                ),
              ),
              child: Icon(
                icon,
                size: 18,
                color: active
                    ? accent
                    : ThemeHelpers.textSecondaryColor(context),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PricePin extends StatelessWidget {
  const _PricePin({
    required this.label,
    required this.color,
    required this.highlighted,
  });

  final String label;
  final Color color;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(15),
            border: highlighted
                ? Border.all(color: Colors.white, width: 2)
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: highlighted ? 10 : 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.home_rounded, size: 13, color: Colors.white),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        CustomPaint(size: const Size(12, 7), painter: _PointerPainter(color)),
      ],
    );
  }
}

class _PointerPainter extends CustomPainter {
  _PointerPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PointerPainter old) => old.color != color;
}

class _ClusterBubble extends StatelessWidget {
  const _ClusterBubble({
    required this.count,
    required this.size,
    required this.color,
  });

  final int count;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ring = (size * 0.13).clamp(5, 12).toDouble();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.22),
      ),
      padding: EdgeInsets.all(ring),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 10),
          ],
        ),
        child: Text(
          NumberFormat.decimalPattern('pt_BR').format(count),
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: size >= 70 ? 15 : (size >= 56 ? 14 : 13),
          ),
        ),
      ),
    );
  }
}

class _GlassPill extends StatelessWidget {
  const _GlassPill({
    required this.icon,
    required this.text,
    this.margin = const EdgeInsets.symmetric(horizontal: 16),
  });
  final IconData icon;
  final String text;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: (isDark ? const Color(0xF0131320) : const Color(0xF2FFFFFF)),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11.5,
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

class _MapRoundButton extends StatelessWidget {
  const _MapRoundButton({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColors.primary.primary;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active
            ? accent
            : (isDark ? const Color(0xEB13131F) : const Color(0xF2FFFFFF)),
        shape: const CircleBorder(),
        elevation: 3,
        shadowColor: Colors.black38,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(
              icon,
              size: 17,
              color: active ? Colors.white : ThemeHelpers.textColor(context),
            ),
          ),
        ),
      ),
    );
  }
}

IconData _poiIcon(NearbyCategoryKey key) => switch (key) {
  NearbyCategoryKey.market => Icons.storefront_rounded,
  NearbyCategoryKey.health => Icons.local_hospital_rounded,
  NearbyCategoryKey.pharmacy => Icons.local_pharmacy_rounded,
  NearbyCategoryKey.school => Icons.school_rounded,
};

class _PoiDot extends StatelessWidget {
  const _PoiDot({required this.category});
  final NearbyCategoryKey category;

  @override
  Widget build(BuildContext context) {
    final color = nearbyCategoryOf(category).color;
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Icon(_poiIcon(category), size: 15, color: Colors.white),
    );
  }
}

/// Painel do "Lugares próximos": estado da busca e contagem por categoria
/// (mesmos textos do web).
class _NearbyPanel extends StatelessWidget {
  const _NearbyPanel({
    required this.loading,
    required this.failed,
    required this.tooFar,
    required this.places,
    required this.anchoredOnSelection,
  });

  final bool loading;
  final bool failed;
  final bool tooFar;
  final List<NearbyPlace> places;
  final bool anchoredOnSelection;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final km = (kNearbyRadiusMeters / 1000).round();
    final String head;
    if (tooFar) {
      head = 'Aproxime o mapa para ver locais próximos';
    } else if (loading) {
      head = 'Buscando locais...';
    } else if (failed) {
      head = 'Locais próximos indisponíveis';
    } else {
      head = '${places.length} locais em até $km km';
    }
    return Container(
      width: 196,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xEB13131F) : const Color(0xF5FFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            head,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          if (!tooFar) ...[
            const SizedBox(height: 6),
            // Falhou: não listar categorias zeradas — "0 escolas" afirmaria
            // que não há escolas, quando a consulta é que não voltou.
            if (failed)
              Text(
                'A base do OpenStreetMap não respondeu. Mova o mapa para '
                'tentar de novo.',
                style: TextStyle(fontSize: 11, color: muted, height: 1.35),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final c in kNearbyCategories)
                    SizedBox(
                      width: 82,
                      child: Row(
                        children: [
                          Icon(_poiIcon(c.key), size: 13, color: c.color),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '${c.label} (${places.where((p) => p.category == c.key).length})',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: ThemeHelpers.textColor(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 6),
            Text(
              'Base: ${anchoredOnSelection ? 'imóvel selecionado' : 'centro atual do mapa'}'
              ' · OpenStreetMap.',
              style: TextStyle(fontSize: 10.5, color: muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final IconData? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primary.primary;
    return Material(
      color: accent,
      borderRadius: BorderRadius.circular(999),
      elevation: 3,
      shadowColor: Colors.black38,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 4),
                Icon(trailing, size: 14, color: Colors.white),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({
    required this.color,
    required this.label,
    required this.count,
    required this.hidden,
    required this.onTap,
  });

  final Color color;
  final String label;
  final int count;
  final bool hidden;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xEB13131F) : const Color(0xF2FFFFFF);
    return Tooltip(
      message: hidden ? 'Mostrar no mapa' : 'Ocultar do mapa',
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        elevation: 2,
        shadowColor: Colors.black26,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Opacity(
            opacity: hidden ? 0.45 : 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: hidden ? Colors.transparent : color,
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: ThemeHelpers.textColor(context),
                        decoration: hidden ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 11.5,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AreaStatsStrip extends StatelessWidget {
  const _AreaStatsStrip({
    required this.stats,
    required this.money,
    this.flat = false,
  });

  final PropertyMapAreaStats stats;
  final String Function(double) money;
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = <(String, String)>[
      ('NA ÁREA', NumberFormat.decimalPattern('pt_BR').format(stats.count)),
      if (stats.avgSale != null) ('MÉDIA VENDA', money(stats.avgSale!)),
      if (stats.avgRent != null) ('MÉDIA ALUGUEL', money(stats.avgRent!)),
      if (stats.avgPricePerSqm != null)
        ('R\$/M²', money(stats.avgPricePerSqm!)),
    ];
    final bg = flat
        ? ThemeHelpers.cardBackgroundColor(context)
        : (isDark ? const Color(0xEB13131F) : const Color(0xF5FFFFFF));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.6),
        ),
        boxShadow: flat
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (label, value) in items)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: AppColors.primary.primary.withValues(
                    alpha: isDark ? 0.14 : 0.07,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: ThemeHelpers.textSecondaryColor(context),
                      ),
                    ),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                      ),
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

class _SelectedCard extends StatelessWidget {
  const _SelectedCard({
    required this.marker,
    required this.onClose,
    required this.onOpen,
    required this.onStreet,
    required this.onWhatsApp,
    required this.onCopy,
  });

  final PropertyMapMarker marker;
  final VoidCallback onClose;
  final VoidCallback onOpen;
  final VoidCallback onStreet;
  final VoidCallback onWhatsApp;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final (statusLabel, statusColor) = _statusStyle(marker.status, isDark);
    final typeLine = [
      PropertyType.labelOf(marker.type),
      if ((marker.code ?? '').isNotEmpty) marker.code!,
    ].where((s) => s.isNotEmpty).join(' · ');

    return Material(
      color: ThemeHelpers.cardBackgroundColor(context),
      elevation: 10,
      shadowColor: Colors.black45,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 92,
                      height: 92,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          (marker.thumbnail ?? '').isEmpty
                              ? Container(
                                  color: statusColor.withValues(alpha: 0.12),
                                  child: Icon(
                                    LucideIcons.house,
                                    color: statusColor,
                                  ),
                                )
                              : ShimmerImage(imageUrl: marker.thumbnail!),
                          Positioned(
                            left: 6,
                            top: 6,
                            child: _StatusBadge(
                              label: statusLabel,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                typeLine.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppColors.primary.primary,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: onClose,
                              customBorder: const CircleBorder(),
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Icon(
                                  LucideIcons.x,
                                  size: 17,
                                  color: muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          marker.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                            color: ThemeHelpers.textColor(context),
                          ),
                        ),
                        const SizedBox(height: 6),
                        _Prices(marker: marker),
                        const SizedBox(height: 6),
                        _Specs(marker: marker),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onOpen,
                      icon: const Icon(LucideIcons.externalLink, size: 16),
                      label: const Text('Abrir imóvel'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _ActionIcon(
                    icon: LucideIcons.footprints,
                    tooltip: 'Vista de rua (Mapillary)',
                    color: const Color(0xFF2563EB),
                    onTap: onStreet,
                  ),
                  const SizedBox(width: 6),
                  _ActionIcon(
                    icon: LucideIcons.messageCircle,
                    tooltip: 'Enviar no WhatsApp',
                    color: const Color(0xFF25D366),
                    onTap: onWhatsApp,
                  ),
                  const SizedBox(width: 6),
                  _ActionIcon(
                    icon: LucideIcons.link,
                    tooltip: 'Copiar link',
                    color: muted,
                    onTap: onCopy,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 42,
            height: 40,
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _Prices extends StatelessWidget {
  const _Prices({required this.marker});
  final PropertyMapMarker marker;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sale = isDark
        ? AppColors.status.successDarkMode
        : AppColors.status.success;
    final rent = AppColors.primary.primary;
    Widget pill(String caption, String value, Color c, {String? suffix}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: c.withValues(alpha: isDark ? 0.2 : 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              caption,
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
                color: c,
              ),
            ),
            Text.rich(
              TextSpan(
                text: value,
                children: [
                  if (suffix != null)
                    TextSpan(
                      text: suffix,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
                color: c,
              ),
            ),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (marker.hasSale) pill('VENDA', _money(marker.salePrice!), sale),
        if (marker.hasRent)
          pill('ALUGUEL', _money(marker.rentPrice!), rent, suffix: '/mês'),
        if (!marker.hasSale && !marker.hasRent) pill('VALOR', 'Consulte', sale),
      ],
    );
  }
}

class _Specs extends StatelessWidget {
  const _Specs({required this.marker});
  final PropertyMapMarker marker;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final items = <(IconData, String)>[
      if ((marker.bedrooms ?? 0) > 0)
        (LucideIcons.bedDouble, '${marker.bedrooms}'),
      if ((marker.bathrooms ?? 0) > 0)
        (LucideIcons.bath, '${marker.bathrooms}'),
      if ((marker.parkingSpaces ?? 0) > 0)
        (LucideIcons.car, '${marker.parkingSpaces}'),
      if ((marker.area ?? 0) > 0)
        (
          LucideIcons.ruler,
          '${NumberFormat.decimalPattern('pt_BR').format(marker.area)}m²',
        ),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final (icon, text) in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: muted),
                const SizedBox(width: 4),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: muted,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.group,
    required this.collapsed,
    required this.onTap,
  });

  final PropertyMapGroup group;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primary.primary;
    return Material(
      color: ThemeHelpers.cardBackgroundColor(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.7),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: group.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  group.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${group.markers.length}',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              AnimatedRotation(
                turns: collapsed ? -0.25 : 0,
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  LucideIcons.chevronDown,
                  size: 18,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarkerCard extends StatelessWidget {
  const _MarkerCard({
    required this.marker,
    required this.accent,
    required this.money,
    required this.onOpen,
    required this.onShowOnMap,
  });

  final PropertyMapMarker marker;
  final Color accent;
  final String Function(double) money;
  final VoidCallback onOpen;
  final VoidCallback onShowOnMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final (statusLabel, statusColor) = _statusStyle(marker.status, isDark);
    final typeLine = [
      PropertyType.labelOf(marker.type),
      if ((marker.code ?? '').isNotEmpty) marker.code!,
    ].where((s) => s.isNotEmpty).join(' · ');

    return Material(
      color: ThemeHelpers.cardBackgroundColor(context),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 150,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    (marker.thumbnail ?? '').isEmpty
                        ? Container(
                            color: accent.withValues(alpha: 0.1),
                            child: Icon(
                              LucideIcons.house,
                              color: accent,
                              size: 30,
                            ),
                          )
                        : ShimmerImage(imageUrl: marker.thumbnail!),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment(0, -0.2),
                          colors: [Color(0x40000000), Color(0x00000000)],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      top: 10,
                      child: _StatusBadge(
                        label: statusLabel,
                        color: statusColor,
                      ),
                    ),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Material(
                        color: Colors.white.withValues(alpha: 0.92),
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: 'Ver no mapa',
                          visualDensity: VisualDensity.compact,
                          onPressed: onShowOnMap,
                          icon: Icon(
                            LucideIcons.mapPin,
                            size: 17,
                            color: AppColors.primary.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      typeLine.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: accent,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      marker.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _Prices(marker: marker),
                    const SizedBox(height: 8),
                    _Specs(marker: marker),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
