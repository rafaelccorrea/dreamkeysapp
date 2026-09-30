import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/feature_visibility.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/utils/broker_contact_actions.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../../../shared/state/screen_state_cache.dart';
import '../../matches/models/match_model.dart';
import '../../matches/services/match_service.dart';
import '../models/client_model.dart';
import '../services/client_service.dart';
import '../widgets/async_excel_import_modal.dart';
import '../widgets/client_filters_drawer.dart';
import '../widgets/transfer_client_modal.dart';
import '../utils/client_phone_rules.dart';
import '../utils/client_spreadsheet.dart';

final _compactIntFormatter = NumberFormat.decimalPattern('pt_BR');

/// Largura máxima do conteúdo em tablet/tela larga: a lista não estica
/// linhas por 1000dp — o excedente vira margem dos dois lados.
const double _kMaxContentWidth = 760;

/// Verde do WhatsApp — cor de identidade da marca, sem equivalente em
/// `AppColors`. No claro vale o tom escuro oficial (contraste no branco);
/// no escuro, o verde vivo. Mesmo par usado no Kanban e na Roleta.
const Color _kWhatsappGreen = Color(0xFF25D366);
const Color _kWhatsappGreenDeep = Color(0xFF128C7E);

/// Permissões das ações de cliente — as mesmas do web
/// (`PermissionButton`/`PermissionMenuItem` em `ClientsPage.tsx`).
const String _kPermClientCreate = 'client:create';
const String _kPermClientUpdate = 'client:update';
const String _kPermClientTransfer = 'client:transfer';
const String _kPermClientDelete = 'client:delete';
const String _kPermClientExport = 'client:export';

/// Rótulos de origem usados na exportação (`CLIENT_SOURCE_LABELS` do web).
const Map<String, String> _kExportSourceLabels = {
  'whatsapp': 'WhatsApp',
  'social_media': 'Redes Sociais',
  'phone': 'Telefone',
  'olx': 'OLX',
  'zap_imoveis': 'Zap Imóveis',
  'viva_real': 'VivaReal',
  'dream_keys': 'Intellisys - Site',
  'other': 'Outros',
};

/// Ícone de cada tipo de cliente — o mesmo na linha da lista e no resumo
/// da carteira, para o olho ligar um ao outro.
IconData _clientTypeIcon(ClientType type) {
  switch (type) {
    case ClientType.buyer:
      return Icons.shopping_bag_outlined;
    case ClientType.seller:
      return Icons.sell_outlined;
    case ClientType.renter:
      return Icons.vpn_key_outlined;
    case ClientType.lessor:
      return Icons.home_work_outlined;
    case ClientType.investor:
      return Icons.trending_up_outlined;
    case ClientType.general:
      return Icons.person_outline;
  }
}

/// Página de listagem de clientes.
///
/// Gramática de lista pesada (inspirada em Imóveis): no topo, o tamanho da
/// carteira em destaque, a busca com o botão de filtros colado, o cadastro
/// e as planilhas à vista; abaixo, linhas flush com filete, cada uma com
/// quem é, situação, telefone, quem atende e os atalhos de WhatsApp/ligar.
class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key});

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  final ClientService _clientService = ClientService.instance;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  /// Foco da busca do topo — o item "Buscar" do menu leva direto a ela.
  final FocusNode _searchFocus = FocusNode();

  bool _isLoading = true;
  bool _isLoadingMore = false;
  List<Client> _clients = [];
  int _currentPage = 1;
  int _totalPages = 1;
  int _total = 0;
  String? _errorMessage;
  // Guardado junto da mensagem: sem o código HTTP não dá para distinguir
  // "sem permissão" de "servidor fora do ar".
  int _errorStatus = 0;
  Object? _errorRaw;
  ClientSearchFilters? _filters;
  String _searchQuery = '';
  ClientStatistics? _statistics;

  /// Debounce da busca (400 ms, igual ao web) e contador de requisição para
  /// descartar respostas que chegam fora de ordem.
  Timer? _searchDebounce;
  int _loadSeq = 0;
  bool _exporting = false;

  /// Chave usada para preservar estado (busca + filtros) ao sair e voltar.
  static const String _stateCacheKey = 'clients:list';

  @override
  void initState() {
    super.initState();
    _restoreCachedState();
    _scrollController.addListener(_onScroll);
    _loadClients(refresh: true);
    _loadStatistics();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _persistState();
    _searchController.dispose();
    _searchFocus.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  /// Restaura `_searchQuery` e `_filters` da cache global em memória.
  void _restoreCachedState() {
    final cached = ScreenStateCache.instance.read<Map<String, dynamic>>(
      _stateCacheKey,
    );
    if (cached == null) return;
    final s = cached['search'] as String?;
    final f = cached['filters'];
    if (s != null && s.isNotEmpty) {
      _searchQuery = s;
      _searchController.text = s;
    }
    if (f is ClientSearchFilters) {
      _filters = f;
    }
  }

  /// Persiste o estado atual para restauração rápida ao voltar para a tela.
  void _persistState() {
    ScreenStateCache.instance.save(_stateCacheKey, {
      'search': _searchQuery,
      'filters': _filters,
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _currentPage < _totalPages && !_isLoading) {
        _loadMoreClients();
      }
    }
  }

  // ───────────────────────── Networking ─────────────────────────

  Future<void> _loadClients({bool refresh = false}) async {
    final seq = ++_loadSeq;
    if (refresh) {
      setState(() {
        _currentPage = 1;
        _clients.clear();
      });
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _errorStatus = 0;
      _errorRaw = null;
    });

    try {
      final filters =
          (_filters ?? ClientSearchFilters()).copyWith(
            search: _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
            page: _currentPage,
            limit: 50,
          );

      final response = await _clientService.getClients(filters: filters);

      if (!mounted || seq != _loadSeq) return;

      if (response.success && response.data != null) {
        final pagination = response.data!.pagination;
        setState(() {
          if (refresh) {
            _clients = response.data!.data;
          } else {
            _clients.addAll(response.data!.data);
          }
          _totalPages = pagination?.totalPages ?? 1;
          _total = pagination?.total ?? _clients.length;
          _isLoading = false;
          _isLoadingMore = false;
        });
      } else {
        setState(() {
          _errorMessage = response.message ?? 'Erro ao carregar clientes';
          _errorStatus = response.statusCode;
          _errorRaw = response.error;
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _errorMessage = 'Erro ao conectar com o servidor';
        _errorStatus = 0;
        _errorRaw = e;
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _loadMoreClients() async {
    if (_isLoadingMore || _currentPage >= _totalPages) return;
    setState(() {
      _isLoadingMore = true;
      _currentPage++;
    });
    await _loadClients();
  }

  Future<void> _loadStatistics() async {
    try {
      final response = await _clientService.getStatistics(filters: _filters);
      if (!mounted) return;
      if (response.success && response.data != null) {
        setState(() => _statistics = response.data);
      }
    } catch (_) {
      // Estatísticas são opcionais — silenciamos erro.
    }
  }

  /// Busca só com 0 ou 3+ caracteres, como o web: com 1–2 letras o back
  /// responde 400 ("Informe ao menos 2 caracteres para busca textual").
  bool _isSearchable(String query) {
    final q = query.trim();
    return q.isEmpty || q.length >= 3;
  }

  Future<void> _handleSearch(String query) async {
    _searchDebounce?.cancel();
    if (!_isSearchable(query)) return;
    if (query.trim() == _searchQuery.trim() && _clients.isNotEmpty) return;
    setState(() {
      _searchQuery = query;
    });
    _persistState();
    await _loadClients(refresh: true);
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _handleSearch(query);
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _handleSearch('');
  }

  void _clearFilters() {
    setState(() => _filters = null);
    _persistState();
    _loadClients(refresh: true);
    _loadStatistics();
  }

  /// "Buscar" do menu: sobe para o topo e põe o cursor na busca.
  void _focusSearch() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
    _searchFocus.requestFocus();
  }

  // ───────────────────────── Permissões ─────────────────────────

  bool _can(String permission) =>
      ModuleAccessService.instance.hasPermission(permission);

  /// Regra da casa: a ação aparece travada (cadeado) em vez de sumir.
  bool _guard(String permission) {
    if (_can(permission)) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Você não tem permissão para esta ação. Fale com um administrador.',
        ),
        backgroundColor: AppColors.status.warning,
      ),
    );
    return false;
  }

  // ───────────────────────── Build ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Clientes',
      currentBottomNavIndex: 3,
      showBottomNavigation: true,
      actions: [_buildOverflowMenu(context)],
      body: _buildViewport(context),
    );
  }

  Color _accentColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
  }

  /// Um único scroll para todos os estados: o topo (com a busca) fica
  /// montado enquanto a lista troca entre esqueleto, erro, vazio e itens —
  /// assim o teclado não fecha no meio da digitação.
  Widget _buildViewport(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final sidePad =
        width > _kMaxContentWidth ? (width - _kMaxContentWidth) / 2 : 0.0;
    final firstLoad = _isLoading && _clients.isEmpty;
    final failed = !firstLoad && _errorMessage != null && _clients.isEmpty;
    final empty = !firstLoad && !failed && _clients.isEmpty;

    final slivers = <Widget>[
      SliverToBoxAdapter(child: _buildHeader(context, firstLoad: firstLoad)),
      if (firstLoad)
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _ClientRowSkeleton(isLast: index == 5),
            childCount: 6,
          ),
        )
      else if (failed)
        SliverToBoxAdapter(child: _buildErrorState(context))
      else if (empty)
        SliverToBoxAdapter(child: _buildEmptyState(context))
      else ...[
        SliverToBoxAdapter(child: _buildListHeader(context)),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildClientRow(
              context,
              _clients[index],
              isLast: index == _clients.length - 1 && !_isLoadingMore,
            ),
            childCount: _clients.length,
          ),
        ),
        if (_isLoadingMore)
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _ClientRowSkeleton(isLast: index == 1),
              childCount: 2,
            ),
          ),
        SliverToBoxAdapter(child: _buildListFooter(context)),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 28)),
    ];

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          _loadClients(refresh: true),
          _loadStatistics(),
        ]);
      },
      color: AppColors.primary.primary,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          for (final sliver in slivers)
            sidePad > 0
                ? SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: sidePad),
                    sliver: sliver,
                  )
                : sliver,
        ],
      ),
    );
  }

  // ───────────────────────── Overflow Menu ─────────────────────────

  Widget _buildOverflowMenu(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final pm = AppTheme.styledPopupMenu(brightness);
    final base = Theme.of(context);
    final accent = _accentColor(context);

    return Theme(
      data: base.copyWith(
        popupMenuTheme: pm,
        splashColor: AppColors.primary.primary.withValues(alpha: 0.10),
        highlightColor: AppColors.primary.primary.withValues(alpha: 0.05),
      ),
      child: PopupMenuButton<String>(
        clipBehavior: Clip.antiAlias,
        constraints: const BoxConstraints(minHeight: 40, minWidth: 44),
        color: pm.color,
        surfaceTintColor: pm.surfaceTintColor,
        elevation: pm.elevation ?? 20,
        shadowColor: pm.shadowColor,
        shape: pm.shape,
        offset: const Offset(0, 8),
        icon: Icon(
          Icons.more_vert,
          color: ThemeHelpers.textColor(context).withValues(alpha: 0.88),
        ),
        tooltip: 'Mais opções',
        onSelected: (value) {
          switch (value) {
            case 'new':
              _navigateToCreate();
              break;
            case 'search':
              _focusSearch();
              break;
            case 'filters':
              _openFilters(context);
              break;
            case 'import':
              _showImportModal();
              break;
            case 'export':
              _exportClients();
              break;
          }
        },
        itemBuilder: (menuCtx) {
          final pmt = Theme.of(menuCtx).popupMenuTheme;
          final labelStyle = pmt.textStyle ?? Theme.of(menuCtx).textTheme.bodyMedium;
          final iconColor = pmt.iconColor ?? ThemeHelpers.textSecondaryColor(menuCtx);
          final lockedStyle = labelStyle?.copyWith(
            color: ThemeHelpers.textSecondaryColor(menuCtx)
                .withValues(alpha: 0.6),
          );
          final canCreate = _can(_kPermClientCreate);
          final canExport = _can(_kPermClientExport);
          final filterCount = _activeFilterCount();

          PopupMenuItem<String> item({
            required String value,
            required IconData icon,
            required String label,
            bool enabled = true,
            bool locked = false,
            Widget? trailing,
          }) {
            return PopupMenuItem<String>(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              value: value,
              enabled: enabled,
              child: Row(
                children: [
                  Icon(
                    locked ? Icons.lock_outline_rounded : icon,
                    size: 20,
                    color: iconColor,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: locked ? lockedStyle : labelStyle,
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing,
                  ],
                ],
              ),
            );
          }

          return [
            item(
              value: 'new',
              icon: Icons.person_add_alt_1,
              label: 'Novo cliente',
              enabled: canCreate,
              locked: !canCreate,
            ),
            item(
              value: 'search',
              icon: Icons.search_rounded,
              label: 'Buscar',
            ),
            item(
              value: 'filters',
              icon: Icons.tune_rounded,
              label: 'Filtros',
              trailing: filterCount > 0
                  ? _CountBadge(count: filterCount, tone: accent)
                  : null,
            ),
            const PopupMenuDivider(height: 10, thickness: 1),
            item(
              value: 'import',
              icon: Icons.upload_file_rounded,
              label: 'Importar planilha',
              enabled: canCreate,
              locked: !canCreate,
            ),
            item(
              value: 'export',
              icon: Icons.file_download_outlined,
              label: _exporting ? 'Exportando…' : 'Exportar planilha',
              enabled: canExport && !_exporting,
              locked: !canExport,
            ),
          ];
        },
      ),
    );
  }

  // ───────────────────────── Topo da carteira ─────────────────────────

  Widget _buildHeader(BuildContext context, {required bool firstLoad}) {
    final hasFilters = _hasActiveFilters();
    final showSummary = firstLoad || _clients.isNotEmpty;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.7),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showSummary) ...[
              firstLoad
                  ? const _SummarySkeleton()
                  : _buildPortfolioSummary(context),
              const SizedBox(height: 16),
            ],
            // Busca (a ação mais usada) com o botão de filtros colado nela.
            Row(
              children: [
                Expanded(child: _buildSearchField(context)),
                const SizedBox(width: 10),
                _buildFilterButton(context),
              ],
            ),
            _buildSearchHint(context),
            const SizedBox(height: 12),
            _buildHeaderActions(context),
            if (hasFilters) ...[
              const SizedBox(height: 12),
              _buildFilterStrip(context),
            ],
          ],
        ),
      ),
    );
  }

  /// Quantos clientes há (o número que importa) + a composição por tipo.
  /// Sem busca, as estatísticas seguem os mesmos filtros da lista.
  Widget _buildPortfolioSummary(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = ThemeHelpers.textColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final hasSearch = _searchQuery.trim().isNotEmpty;
    final hasFilters = _hasActiveFilters();
    final stats = hasSearch ? null : _statistics;
    final total = _total;

    final String label;
    if (hasSearch) {
      label = total == 1 ? 'cliente encontrado' : 'clientes encontrados';
    } else if (hasFilters) {
      label = total == 1
          ? 'cliente com estes filtros'
          : 'clientes com estes filtros';
    } else {
      label = total == 1 ? 'cliente na carteira' : 'clientes na carteira';
    }

    String? detail;
    if (hasSearch) {
      final q = _searchQuery.trim();
      detail = 'para “${q.length > 40 ? '${q.substring(0, 40)}…' : q}”';
    } else if (stats != null && stats.totalClients > 0) {
      final inactive = stats.totalClients - stats.activeClients;
      detail = '${_compactIntFormatter.format(stats.activeClients)} '
          '${stats.activeClients == 1 ? 'ativo' : 'ativos'} · '
          '${_compactIntFormatter.format(inactive < 0 ? 0 : inactive)} '
          '${inactive == 1 ? 'inativo' : 'inativos'}';
    }

    final typeCounts = <MapEntry<ClientType, int>>[
      if (stats != null) ...[
        MapEntry(ClientType.buyer, stats.buyers),
        MapEntry(ClientType.seller, stats.sellers),
        MapEntry(ClientType.renter, stats.renters),
        MapEntry(ClientType.lessor, stats.lessors),
        MapEntry(ClientType.investor, stats.investors),
        MapEntry(ClientType.general, stats.generalClients),
      ],
    ].where((e) => e.value > 0).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _compactIntFormatter.format(total),
                  maxLines: 1,
                  softWrap: false,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.0,
                    height: 1.0,
                    color: textColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      color: textColor,
                    ),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (typeCounts.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              for (final e in typeCounts)
                _TypeCount(
                  icon: _clientTypeIcon(e.key),
                  count: e.value,
                  label: _typePlural(e.key, e.value),
                ),
            ],
          ),
        ],
      ],
    );
  }

  String _typePlural(ClientType type, int count) {
    final one = count == 1;
    switch (type) {
      case ClientType.buyer:
        return one ? 'comprador' : 'compradores';
      case ClientType.seller:
        return one ? 'vendedor' : 'vendedores';
      case ClientType.renter:
        return one ? 'locatário' : 'locatários';
      case ClientType.lessor:
        return one ? 'locador' : 'locadores';
      case ClientType.investor:
        return one ? 'investidor' : 'investidores';
      case ClientType.general:
        return one ? 'geral' : 'gerais';
    }
  }

  Widget _buildSearchField(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final accent = _accentColor(context);
    final idle = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: ThemeHelpers.borderColor(context)),
    );

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _searchController,
      builder: (context, value, _) {
        return TextField(
          controller: _searchController,
          focusNode: _searchFocus,
          textInputAction: TextInputAction.search,
          onChanged: _onSearchChanged,
          onSubmitted: _handleSearch,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: ThemeHelpers.textColor(context),
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            filled: true,
            isDense: true,
            hintText: 'Nome, telefone ou CPF',
            hintMaxLines: 1,
            hintStyle: theme.textTheme.bodyMedium?.copyWith(
              color: muted,
              fontWeight: FontWeight.w500,
            ),
            prefixIcon: Icon(Icons.search_rounded, color: muted, size: 22),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpar busca',
                    icon: Icon(Icons.close_rounded, color: muted, size: 20),
                    onPressed: _clearSearch,
                  ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
            border: idle,
            enabledBorder: idle,
            focusedBorder: idle.copyWith(
              borderSide: BorderSide(color: accent, width: 1.6),
            ),
          ),
        );
      },
    );
  }

  /// Com 1–2 letras a busca não dispara (regra do back) — em vez de parecer
  /// travada, a tela diz o porquê.
  Widget _buildSearchHint(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _searchController,
      builder: (context, value, _) {
        final len = value.text.trim().length;
        if (len == 0 || len >= 3) return const SizedBox.shrink();
        final muted = ThemeHelpers.textSecondaryColor(context);
        return Padding(
          padding: const EdgeInsets.only(top: 8, left: 4),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 15, color: muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Digite ao menos 3 caracteres para buscar.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Botão de filtros colado na busca — com a contagem de filtros ativos.
  Widget _buildFilterButton(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _accentColor(context);
    final count = _activeFilterCount();
    final active = count > 0;
    final radius = BorderRadius.circular(14);

    return Tooltip(
      message: active
          ? 'Filtros ($count ${count == 1 ? 'ativo' : 'ativos'})'
          : 'Filtros',
      child: Material(
        // Mesmo preenchimento do campo de busca (fill do tema).
        color: active
            ? accent.withValues(alpha: isDark ? 0.16 : 0.08)
            : (isDark
                ? AppColors.background.backgroundSecondaryDarkMode
                : AppColors.background.backgroundTertiary),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: active
                ? accent.withValues(alpha: 0.55)
                : ThemeHelpers.borderColor(context),
            width: active ? 1.4 : 1,
          ),
        ),
        child: InkWell(
          onTap: () => _openFilters(context),
          customBorder: RoundedRectangleBorder(borderRadius: radius),
          child: SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(
                  child: Icon(
                    Icons.tune_rounded,
                    size: 22,
                    color: active
                        ? accent
                        : ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
                if (active)
                  Positioned(
                    top: 5,
                    right: 5,
                    child: _CountBadge(count: count, tone: accent),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Cadastro (CTA da marca) + planilhas. Em tela estreita o CTA ocupa a
  /// linha e as planilhas dividem a de baixo; em tela larga, uma linha só.
  Widget _buildHeaderActions(BuildContext context) {
    final canCreate = _can(_kPermClientCreate);
    final canExport = _can(_kPermClientExport);

    final create = _buildCreateCta(context);
    final importButton = _buildSecondaryAction(
      context,
      icon: Icons.upload_file_rounded,
      label: 'Importar planilha',
      locked: !canCreate,
      onTap: _showImportModal,
    );
    final exportButton = _buildSecondaryAction(
      context,
      icon: Icons.file_download_outlined,
      label: _exporting ? 'Exportando…' : 'Exportar planilha',
      locked: !canExport,
      busy: _exporting,
      onTap: _exportClients,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 480) {
          return Row(
            children: [
              Expanded(flex: 5, child: create),
              const SizedBox(width: 8),
              Expanded(flex: 4, child: importButton),
              const SizedBox(width: 8),
              Expanded(flex: 4, child: exportButton),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            create,
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: importButton),
                const SizedBox(width: 8),
                Expanded(child: exportButton),
              ],
            ),
          ],
        );
      },
    );
  }

  /// CTA de criação — vermelho da marca; sem permissão, travado com cadeado
  /// (o toque explica o motivo em vez de sumir com o botão).
  Widget _buildCreateCta(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final canCreate = _can(_kPermClientCreate);
    final fg = canCreate
        ? Colors.white
        : ThemeHelpers.textSecondaryColor(context);
    final radius = BorderRadius.circular(14);

    return Material(
      color: canCreate
          ? _accentColor(context)
          : (isDark
              ? AppColors.background.backgroundTertiaryDarkMode
              : AppColors.background.backgroundTertiary),
      borderRadius: radius,
      child: InkWell(
        onTap: _navigateToCreate,
        borderRadius: radius,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      canCreate
                          ? Icons.person_add_alt_1
                          : Icons.lock_outline_rounded,
                      size: 19,
                      color: fg,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Novo cliente',
                      maxLines: 1,
                      softWrap: false,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                        letterSpacing: -0.1,
                        color: fg,
                      ),
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

  /// Ação secundária neutra (planilhas). Travada: cadeado + texto apagado.
  Widget _buildSecondaryAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool locked,
    required VoidCallback onTap,
    bool busy = false,
  }) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final fg = locked
        ? muted.withValues(alpha: 0.75)
        : ThemeHelpers.textColor(context);
    final radius = BorderRadius.circular(14);

    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: ThemeHelpers.borderColor(context)),
      ),
      child: InkWell(
        onTap: busy ? null : onTap,
        customBorder: RoundedRectangleBorder(borderRadius: radius),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 46),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (busy)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: muted,
                        ),
                      )
                    else
                      Icon(
                        locked ? Icons.lock_outline_rounded : icon,
                        size: 18,
                        color: locked ? muted : _accentColor(context),
                      ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: fg,
                      ),
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

  /// Faixa com o que está filtrado, em palavras — e o atalho para limpar.
  Widget _buildFilterStrip(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accentColor(context);
    final labels = _activeFilterLabels();
    final text = labels.isEmpty ? 'Filtros aplicados' : labels.join(' · ');

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          Icon(Icons.filter_alt_outlined, size: 17, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
            ),
          ),
          // Limpar não é destrutivo: neutro (o tema pintaria de vermelho).
          TextButton(
            onPressed: _clearFilters,
            style: TextButton.styleFrom(
              foregroundColor: ThemeHelpers.textColor(context),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── Lista ─────────────────────────

  /// Linha acima da lista: em que ordem os clientes estão e quantos já
  /// apareceram do total.
  Widget _buildListHeader(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: [
          Icon(Icons.swap_vert_rounded, size: 16, color: muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _sortLabel(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: muted,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${_compactIntFormatter.format(_clients.length)} de '
            '${_compactIntFormatter.format(_total)}',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: ThemeHelpers.textColor(context),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  void _openDetails(Client client) {
    Navigator.pushNamed(context, AppRoutes.clientDetails(client.id))
        .then((_) {
      if (!mounted) return;
      _loadClients(refresh: true);
    });
  }

  /// Linha flush do cliente: quem é, situação e tipo, telefone e cidade,
  /// quem atende e há quanto tempo mexeram — e os atalhos para falar com
  /// ele sem abrir a ficha.
  Widget _buildClientRow(
    BuildContext context,
    Client client, {
    required bool isLast,
  }) {
    final theme = Theme.of(context);
    final textColor = ThemeHelpers.textColor(context);

    final phone = client.phone.trim();
    final whatsapp = (client.whatsapp ?? '').trim();
    final email = client.email.trim();
    final secondary = (client.secondaryPhone ?? '').trim();
    final mainPhone = phone.isNotEmpty
        ? phone
        : (whatsapp.isNotEmpty ? whatsapp : secondary);
    final place = [client.city.trim(), client.state.trim()]
        .where((s) => s.isNotEmpty)
        .join('/');

    final contactParts = <String>[
      if (mainPhone.isNotEmpty)
        ClientPhoneRules.maskAuto(mainPhone)
      else if (email.isNotEmpty)
        email,
      if (place.isNotEmpty) place,
    ];
    final contactIcon = mainPhone.isNotEmpty
        ? Icons.phone_outlined
        : (email.isNotEmpty
            ? Icons.alternate_email_rounded
            : Icons.place_outlined);

    final responsible = client.responsibleUser?.name.trim() ?? '';
    final captor = client.capturedBy?.name.trim() ?? '';
    final showCaptor =
        captor.isNotEmpty && client.capturedById != client.responsibleUserId;
    final updated = _updatedLabel(client);
    final peopleParts = <String>[
      if (responsible.isNotEmpty) 'Atendido por $responsible',
      if (showCaptor) 'captado por $captor',
      if (updated != null) updated,
    ];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openDetails(client),
        onLongPress: () => _showClientActions(context, client),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ClientInitialsAvatar(initials: _initialsFor(client.name)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  client.name.trim().isEmpty
                                      ? 'Cliente sem nome'
                                      : client.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15.5,
                                    height: 1.2,
                                    letterSpacing: -0.2,
                                    color: textColor,
                                  ),
                                ),
                              ),
                            ),
                            // Matches oculto no app: pill fora da linha.
                            if (FeatureVisibility.matchesEnabled)
                              _MatchesPill(
                                clientId: client.id,
                                accent: _accentColor(context),
                                onTap: () => Navigator.pushNamed(
                                  context,
                                  AppRoutes.matchesByClient(client.id),
                                ),
                              ),
                            _buildCardOverflowMenu(context, client),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 10,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _StatusPill(
                              label: client.status.label,
                              tone: _statusTone(context, client.status),
                            ),
                            _MetaTag(
                              icon: _clientTypeIcon(client.type),
                              label: client.type.label,
                            ),
                            if (!client.isActive &&
                                client.status != ClientStatus.inactive)
                              const _MetaTag(
                                icon: Icons.block_rounded,
                                label: 'Desativado',
                              ),
                          ],
                        ),
                        if (contactParts.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _InfoLine(
                            icon: contactIcon,
                            text: contactParts.join(' · '),
                            strong: true,
                          ),
                        ],
                        if (peopleParts.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          _InfoLine(
                            icon: Icons.support_agent,
                            text: peopleParts.join(' · '),
                            maxLines: 2,
                          ),
                        ],
                        const SizedBox(height: 10),
                        _buildRowContactActions(
                          context,
                          phone: phone,
                          whatsapp: whatsapp,
                          email: email,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (!isLast)
              Padding(
                padding: const EdgeInsets.only(left: 72),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: ThemeHelpers.borderLightColor(context),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Atalhos de contato no próprio item — só aparecem os canais que o
  /// cadastro tem; sem nenhum, a linha diz o que falta.
  Widget _buildRowContactActions(
    BuildContext context, {
    required String phone,
    required String whatsapp,
    required String email,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);

    if (phone.isEmpty && whatsapp.isEmpty && email.isEmpty) {
      return Text(
        'Sem telefone ou e-mail cadastrado.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: muted,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    final onlyEmail = phone.isEmpty && whatsapp.isEmpty;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (whatsapp.isNotEmpty)
          _ContactChipButton(
            icon: Icons.chat_outlined,
            label: 'WhatsApp',
            tone: isDark ? _kWhatsappGreen : _kWhatsappGreenDeep,
            onTap: () => _launchUri(
              'https://wa.me/${BrokerContactActions.whatsappDigits(whatsapp)}',
            ),
          ),
        if (phone.isNotEmpty)
          _ContactChipButton(
            icon: Icons.call_rounded,
            label: 'Ligar',
            tone: isDark
                ? AppColors.status.infoDarkMode
                : AppColors.message.infoText,
            onTap: () => _launchUri('tel:${_onlyDigits(phone)}'),
          ),
        if (email.isNotEmpty)
          _ContactChipButton(
            icon: Icons.mail_outline_rounded,
            label: onlyEmail ? 'E-mail' : null,
            tooltip: 'Enviar e-mail',
            tone: muted,
            onTap: () => _launchUri('mailto:$email'),
          ),
      ],
    );
  }

  /// Fim da lista: quanto já apareceu e, se houver mais, o mesmo carregar
  /// mais do scroll (a paginação por setas somava páginas repetidas).
  Widget _buildListFooter(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);

    // Falha ao buscar a próxima página: a lista continua visível e o erro
    // aparece aqui, com a causa e o "Tentar de novo".
    if (_errorMessage != null && _clients.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: AppErrorState.fromApi(
          message: _errorMessage,
          statusCode: _errorStatus,
          error: _errorRaw,
          onRetry: () => _loadClients(),
          dense: true,
        ),
      );
    }

    if (_isLoadingMore) return const SizedBox.shrink();

    final hasMore = _currentPage < _totalPages;
    if (hasMore) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: Column(
          children: [
            Text(
              'Mostrando ${_compactIntFormatter.format(_clients.length)} de '
              '${_compactIntFormatter.format(_total)} clientes',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _loadMoreClients,
              icon: const Icon(Icons.expand_more_rounded, size: 18),
              label: const Text(
                'Carregar mais',
                maxLines: 1,
                softWrap: false,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: ThemeHelpers.textColor(context),
                side: BorderSide(color: ThemeHelpers.borderColor(context)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline_rounded, size: 16, color: muted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              _total == 1
                  ? 'Fim da lista · 1 cliente'
                  : 'Fim da lista · ${_compactIntFormatter.format(_total)} clientes',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardOverflowMenu(BuildContext context, Client client) {
    final pm = AppTheme.styledPopupMenuOf(context);
    return SizedBox(
      width: 36,
      height: 36,
      child: PopupMenuButton<String>(
        tooltip: 'Ações do cliente',
        padding: EdgeInsets.zero,
        iconSize: 20,
        icon: Icon(
          Icons.more_vert_rounded,
          color: ThemeHelpers.textSecondaryColor(context),
        ),
        color: pm.color,
        surfaceTintColor: pm.surfaceTintColor,
        elevation: pm.elevation,
        shadowColor: pm.shadowColor,
        shape: pm.shape,
        position: PopupMenuPosition.under,
        onSelected: (value) async {
          switch (value) {
            case 'view':
              await Navigator.pushNamed(
                context,
                AppRoutes.clientDetails(client.id),
              );
              _loadClients(refresh: true);
              break;
            case 'edit':
              if (!_guard(_kPermClientUpdate)) break;
              await Navigator.pushNamed(
                context,
                AppRoutes.clientEdit(client.id),
              );
              _loadClients(refresh: true);
              _loadStatistics();
              break;
            case 'matches':
              Navigator.pushNamed(
                context,
                AppRoutes.matchesByClient(client.id),
              );
              break;
            case 'transfer':
              if (!_guard(_kPermClientTransfer)) break;
              if (mounted) await _showTransferModal(context, client);
              break;
            case 'delete':
              if (!_guard(_kPermClientDelete)) break;
              if (mounted) await _showDeleteConfirmation(context, client);
              break;
          }
        },
        itemBuilder: (_) => [
          _plainMenuItem(
            value: 'view',
            icon: Icons.open_in_new_rounded,
            label: 'Abrir',
          ),
          _lockableMenuItem(
            value: 'edit',
            icon: Icons.edit_outlined,
            label: 'Editar',
            permission: _kPermClientUpdate,
          ),
          // Matches oculto no app: item fora do menu.
          if (FeatureVisibility.matchesEnabled)
            _plainMenuItem(
              value: 'matches',
              icon: Icons.handshake_outlined,
              label: 'Ver matches',
            ),
          _lockableMenuItem(
            value: 'transfer',
            icon: Icons.swap_horiz_rounded,
            label: 'Transferir',
            permission: _kPermClientTransfer,
          ),
          const PopupMenuDivider(),
          _lockableMenuItem(
            value: 'delete',
            icon: Icons.delete_outline,
            label: 'Excluir',
            permission: _kPermClientDelete,
            destructive: true,
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _plainMenuItem({
    required String value,
    required IconData icon,
    required String label,
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(children: [
        Icon(icon, size: 18),
        const SizedBox(width: 10),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }

  /// Item de menu que trava (cadeado + desabilitado) sem a permissão.
  PopupMenuItem<String> _lockableMenuItem({
    required String value,
    required IconData icon,
    required String label,
    required String permission,
    bool destructive = false,
  }) {
    final allowed = _can(permission);
    final color = !allowed
        ? ThemeHelpers.textSecondaryColor(context).withValues(alpha: 0.6)
        : (destructive ? AppColors.status.error : null);
    return PopupMenuItem<String>(
      value: value,
      enabled: allowed,
      child: Row(children: [
        Icon(
          allowed ? icon : Icons.lock_outline_rounded,
          size: 18,
          color: color,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color),
          ),
        ),
      ]),
    );
  }

  String _onlyDigits(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

  Future<void> _launchUri(String uri) async {
    final parsed = Uri.tryParse(uri);
    if (parsed == null) return;
    try {
      await launchUrl(parsed, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir esse link')),
      );
    }
  }

  String _initialsFor(String name) {
    if (name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  /// Cor de SIGNIFICADO do status (tokens de status). No selo ela pinta só
  /// o ponto, o fundo e a borda — o texto fica na cor do texto, legível nos
  /// dois temas mesmo no amarelo.
  Color _statusTone(BuildContext context, ClientStatus status) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    switch (status) {
      case ClientStatus.active:
        return dark ? AppColors.status.successDarkMode : AppColors.status.success;
      case ClientStatus.contacted:
        return dark ? AppColors.status.infoDarkMode : AppColors.status.info;
      case ClientStatus.interested:
        return dark ? AppColors.status.warningDarkMode : AppColors.status.warning;
      case ClientStatus.closed:
        return dark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
      case ClientStatus.inactive:
        return ThemeHelpers.textSecondaryColor(context);
    }
  }

  /// "atualizado hoje / ontem / há 3 dias / em 12/03/25" — a última mexida
  /// no cadastro (a listagem não traz a data do último contato).
  String? _updatedLabel(Client client) {
    final raw = client.updatedAt.trim().isNotEmpty
        ? client.updatedAt.trim()
        : client.createdAt.trim();
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    final date = parsed.toLocal();
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(date.year, date.month, date.day))
        .inDays;
    if (days <= 0) return 'atualizado hoje';
    if (days == 1) return 'atualizado ontem';
    if (days < 7) return 'atualizado há $days dias';
    return 'atualizado em ${DateFormat('dd/MM/yy', 'pt_BR').format(date)}';
  }

  /// Ordem real da lista. Sem ordenação escolhida (ou sem direção), o back
  /// usa data de cadastro e decrescente.
  String _sortLabel() {
    final f = _filters;
    final by = (f?.sortBy ?? '').trim();
    final asc = (f?.sortOrder ?? 'DESC').toUpperCase() == 'ASC';
    switch (by) {
      case 'name':
        return asc ? 'Ordem: nome, de A a Z' : 'Ordem: nome, de Z a A';
      case 'city':
        return asc ? 'Ordem: cidade, de A a Z' : 'Ordem: cidade, de Z a A';
      case 'status':
        return asc ? 'Ordem: status, crescente' : 'Ordem: status, decrescente';
      case 'type':
        return asc ? 'Ordem: tipo, crescente' : 'Ordem: tipo, decrescente';
      default:
        return asc
            ? 'Cadastros mais antigos primeiro'
            : 'Cadastros mais recentes primeiro';
    }
  }

  // ───────────────────────── Vazio / Erro ─────────────────────────

  Widget _buildErrorState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: AppErrorState.fromApi(
        message: _errorMessage,
        statusCode: _errorStatus,
        error: _errorRaw,
        onRetry: () async {
          await _loadClients(refresh: true);
          await _loadStatistics();
        },
        dense: true,
      ),
    );
  }

  /// Vazio que ensina: o que aparece aqui, por que não apareceu e como
  /// chegar lá (os botões de cadastro e planilha estão logo acima).
  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final hasSearch = _searchQuery.trim().isNotEmpty;
    final hasFilters = _hasActiveFilters();
    final obstructed = hasSearch || hasFilters;

    final String title;
    final String body;
    if (hasSearch) {
      final q = _searchQuery.trim();
      title = 'Nenhum cliente para “${q.length > 32 ? '${q.substring(0, 32)}…' : q}”';
      body = 'A busca procura no nome, no telefone, no e-mail e no CPF. '
          'Confira a grafia ou tente só o sobrenome ou os últimos dígitos '
          'do telefone.'
          '${hasFilters ? ' Os filtros ativos também restringem o resultado.' : ''}';
    } else if (hasFilters) {
      title = 'Nenhum cliente com esses filtros';
      body = 'Ninguém da carteira atende a todos os critérios escolhidos. '
          'Tire algum critério nos filtros ou limpe tudo para ver a carteira '
          'inteira.';
    } else {
      title = 'Sua carteira ainda está vazia';
      body = 'Aqui aparecem os seus clientes, com situação, telefone, quem '
          'atende e atalhos para ligar ou chamar no WhatsApp. Toque em '
          '“Novo cliente” para cadastrar um, ou em “Importar planilha” para '
          'trazer vários de uma vez.';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: isDark
                  ? AppColors.background.backgroundTertiaryDarkMode
                  : AppColors.background.backgroundTertiary,
              border: Border.all(color: ThemeHelpers.borderColor(context)),
            ),
            child: Icon(
              obstructed
                  ? Icons.manage_search_rounded
                  : Icons.people_outline_rounded,
              size: 26,
              color: muted,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
              height: 1.2,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: muted,
              height: 1.45,
            ),
          ),
          if (obstructed) ...[
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                  _filters = null;
                });
                _persistState();
                _loadClients(refresh: true);
                _loadStatistics();
              },
              icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
              label: Text(
                hasSearch && hasFilters
                    ? 'Limpar busca e filtros'
                    : (hasSearch ? 'Limpar busca' : 'Limpar filtros'),
                maxLines: 1,
                softWrap: false,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: ThemeHelpers.textColor(context),
                side: BorderSide(color: ThemeHelpers.borderColor(context)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ───────────────────────── Ações ─────────────────────────

  void _navigateToCreate() {
    if (!_guard(_kPermClientCreate)) return;
    Navigator.pushNamed(context, AppRoutes.clientCreate).then((created) {
      if (!mounted) return;
      if (created != null) {
        _loadClients(refresh: true);
        _loadStatistics();
      }
    });
  }

  void _openFilters(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black54,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (context) => ClientFiltersDrawer(
        initialFilters: _filters,
        onFiltersChanged: (filters) {
          setState(() => _filters = filters);
          _persistState();
          _loadClients(refresh: true);
          _loadStatistics();
        },
      ),
    );
  }

  Future<void> _showClientActions(BuildContext context, Client client) async {
    final theme = Theme.of(context);
    final navigator = Navigator.of(context);

    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final muted = ThemeHelpers.textSecondaryColor(ctx);
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.88,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: ThemeHelpers.cardBackgroundColor(ctx),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      margin: const EdgeInsets.only(top: 10, bottom: 10),
                      decoration: BoxDecoration(
                        color: ThemeHelpers.borderColor(ctx)
                            .withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 8, 10),
                    child: Row(
                      children: [
                        _ClientInitialsAvatar(
                          initials: _initialsFor(client.name),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                client.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  height: 1.2,
                                  color: ThemeHelpers.textColor(ctx),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${client.type.label} · ${client.status.label}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: muted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Fechar',
                          icon: Icon(Icons.close_rounded, color: muted),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: ThemeHelpers.borderLightColor(ctx),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _actionRow(
                            ctx,
                            Icons.open_in_new_rounded,
                            'Abrir cliente',
                            'Ver dados completos e a linha do tempo',
                            () => Navigator.pop(ctx, 'view'),
                          ),
                          _actionRow(
                            ctx,
                            Icons.edit_outlined,
                            'Editar dados',
                            'Atualizar o cadastro do cliente',
                            () => Navigator.pop(ctx, 'edit'),
                            locked: !_can(_kPermClientUpdate),
                          ),
                          // Matches oculto no app: linha fora do sheet de ações.
                          if (FeatureVisibility.matchesEnabled)
                            _actionRow(
                              ctx,
                              Icons.handshake_outlined,
                              'Ver matches',
                              'Imóveis compatíveis com o perfil',
                              () => Navigator.pop(ctx, 'matches'),
                            ),
                          _actionRow(
                            ctx,
                            Icons.swap_horiz_rounded,
                            'Transferir',
                            'Passar o cliente para outro responsável',
                            () => Navigator.pop(ctx, 'transfer'),
                            locked: !_can(_kPermClientTransfer),
                          ),
                          _actionRow(
                            ctx,
                            Icons.delete_outline,
                            'Excluir cliente',
                            'Remove o cadastro de vez',
                            () => Navigator.pop(ctx, 'delete'),
                            destructive: true,
                            locked: !_can(_kPermClientDelete),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (action == null || !mounted) return;
    switch (action) {
      case 'view':
        await navigator.pushNamed(AppRoutes.clientDetails(client.id));
        _loadClients(refresh: true);
        break;
      case 'edit':
        await navigator.pushNamed(AppRoutes.clientEdit(client.id));
        _loadClients(refresh: true);
        _loadStatistics();
        break;
      case 'matches':
        navigator.pushNamed(AppRoutes.matchesByClient(client.id));
        break;
      case 'transfer':
        if (!mounted) break;
        // ignore: use_build_context_synchronously
        await _showTransferModal(context, client);
        break;
      case 'delete':
        if (!mounted) break;
        // ignore: use_build_context_synchronously
        await _showDeleteConfirmation(context, client);
        break;
    }
  }

  Widget _actionRow(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap, {
    bool destructive = false,
    bool locked = false,
  }) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final fg = locked
        ? muted
        : (destructive ? AppColors.status.error : ThemeHelpers.textColor(context));
    final iconColor = locked
        ? muted
        : (destructive ? AppColors.status.error : _accentColor(context));
    if (locked) {
      icon = Icons.lock_outline_rounded;
      subtitle = 'Sem permissão para esta ação';
      destructive = false;
    }

    return InkWell(
      onTap: locked ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                color: iconColor.withValues(alpha: 0.10),
                border: Border.all(color: iconColor.withValues(alpha: 0.22)),
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: fg,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: destructive
                          ? AppColors.status.error.withValues(alpha: 0.78)
                          : muted,
                      fontWeight: FontWeight.w500,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: muted.withValues(alpha: 0.38)),
          ],
        ),
      ),
    );
  }

  Future<void> _showTransferModal(BuildContext context, Client client) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        clipBehavior: Clip.antiAlias,
        child: TransferClientModal(
          clientId: client.id,
          clientName: client.name,
          currentResponsibleUserId: client.responsibleUserId,
          currentResponsibleName: client.responsibleUser?.name,
        ),
      ),
    );

    if (result == true) {
      _loadClients(refresh: true);
      _loadStatistics();
    }
  }

  Future<void> _showDeleteConfirmation(
    BuildContext context,
    Client client,
  ) async {
    final theme = Theme.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.status.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.warning_amber_rounded,
                color: AppColors.status.error,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Excluir cliente?')),
          ],
        ),
        content: Text(
          'O cliente "${client.name}" será removido permanentemente. '
          'Essa ação não pode ser desfeita.',
          style: theme.textTheme.bodyMedium,
        ),
        actions: [
          // Cancelar é neutro: o tema pinta TextButton de vermelho.
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              foregroundColor: ThemeHelpers.textSecondaryColor(ctx),
            ),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.status.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final response = await _clientService.deleteClient(client.id);
    if (!mounted) return;

    if (response.success) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Cliente excluído com sucesso!'),
          backgroundColor: AppColors.status.success,
        ),
      );
      _loadClients(refresh: true);
      _loadStatistics();
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(response.message ?? 'Erro ao excluir cliente'),
          backgroundColor: AppColors.status.error,
        ),
      );
    }
  }

  Future<void> _showImportModal() async {
    if (!_guard(_kPermClientCreate)) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black54,
      // O modal pinta a própria superfície (com o mesmo raio de 24).
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (context) => AsyncExcelImportModal(
        onImportComplete: () {
          _loadClients(refresh: true);
          _loadStatistics();
        },
      ),
    );
  }

  /// Exportação igual à do web (`handleExportClients`): planilha enxuta com
  /// NOME, TELEFONE (principal → WhatsApp → secundário, só dígitos com 55) e
  /// MÍDIA DE ORIGEM, gerada a partir da lista filtrada/buscada da tela e
  /// aberta na folha de compartilhar para salvar ou enviar.
  Future<void> _exportClients() async {
    if (!_guard(_kPermClientExport) || _exporting) return;
    final messenger = ScaffoldMessenger.of(context);

    if (_clients.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text(
            'Não há clientes para exportar. Crie alguns clientes primeiro.',
          ),
          backgroundColor: AppColors.status.warning,
        ),
      );
      return;
    }

    setState(() => _exporting = true);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Iniciando exportação... Aguarde.'),
        duration: Duration(seconds: 3),
      ),
    );

    try {
      final response = await _clientService.fetchAllClients(
        filters: _filters,
        search: _searchQuery,
      );
      if (!mounted) return;

      if (!response.success || response.data == null) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(response.message ?? 'Erro ao exportar clientes'),
            backgroundColor: AppColors.status.error,
          ),
        );
        return;
      }

      final clients = response.data!;
      final rows = <List<Object?>>[
        ['NOME', 'TELEFONE', 'MÍDIA DE ORIGEM'],
        for (final c in clients)
          [
            c.name,
            _exportPhoneDigits(c),
            _exportSourceLabel(c),
          ],
      ];
      final bytes = ClientSpreadsheet.buildXlsx(
        sheetName: 'Clientes',
        rows: rows,
        columnWidths: const [40, 16, 28],
      );
      final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final fileName =
          'Clientes_Exportados_${date}_${clients.length}registros.xlsx';

      await ClientSpreadsheet.shareBytes(
        bytes: bytes,
        fileName: fileName,
        subject: 'Exportação de clientes',
      );
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('${clients.length} clientes exportados com sucesso!'),
          backgroundColor: AppColors.status.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Erro ao exportar clientes: ${e.toString()}'),
          backgroundColor: AppColors.status.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// `formatPhoneForExportDigitsBR` do web.
  String _exportPhoneDigits(Client c) {
    String pick(String? v) => (v ?? '').trim();
    final raw = pick(c.phone).isNotEmpty
        ? pick(c.phone)
        : (pick(c.whatsapp).isNotEmpty
            ? pick(c.whatsapp)
            : pick(c.secondaryPhone));
    var d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) return '';
    while (d.startsWith('0') && d.length > 1) {
      d = d.substring(1);
    }
    if (d.startsWith('55')) {
      return d.length > 13 ? d.substring(0, 13) : d;
    }
    if (d.length == 10 || d.length == 11) return '55$d';
    return d;
  }

  String _exportSourceLabel(Client c) {
    final src = c.leadSource;
    if (src == null) return '';
    return _kExportSourceLabels[src.value] ?? src.label;
  }

  // ───────────────────────── Helpers ─────────────────────────

  bool _hasActiveFilters() {
    final f = _filters;
    if (f == null) return false;
    return f.name != null ||
        f.email != null ||
        f.phone != null ||
        f.document != null ||
        f.city != null ||
        f.neighborhood != null ||
        f.state != null ||
        f.type != null ||
        f.status != null ||
        f.isActive != null ||
        f.onlyMyData != null ||
        f.createdFrom != null ||
        f.createdTo != null ||
        f.sortBy != null;
  }

  /// O que está filtrado, em palavras (a faixa do topo mostra isso).
  List<String> _activeFilterLabels() {
    final f = _filters;
    if (f == null) return const [];
    String? v(String? raw) {
      final s = raw?.trim() ?? '';
      return s.isEmpty ? null : s;
    }

    final labels = <String>[];
    final name = v(f.name);
    final email = v(f.email);
    final phone = v(f.phone);
    final document = v(f.document);
    final city = v(f.city);
    final neighborhood = v(f.neighborhood);
    final uf = v(f.state);
    if (name != null) labels.add('Nome: $name');
    if (email != null) labels.add('E-mail: $email');
    if (phone != null) labels.add('Telefone: $phone');
    if (document != null) labels.add('CPF: $document');
    if (city != null) labels.add('Cidade: $city');
    if (neighborhood != null) labels.add('Bairro: $neighborhood');
    if (uf != null) labels.add('UF: $uf');
    if (f.type != null) labels.add(f.type!.label);
    if (f.status != null) labels.add(f.status!.label);
    if (f.isActive != null) {
      labels.add(f.isActive! ? 'Só ativos' : 'Só desativados');
    }
    if (f.onlyMyData == true) labels.add('Só os meus clientes');
    final period = _periodLabel(f.createdFrom, f.createdTo);
    if (period != null) labels.add(period);
    if (v(f.sortBy) != null) labels.add(_sortLabel());
    return labels;
  }

  int _activeFilterCount() {
    if (!_hasActiveFilters()) return 0;
    final count = _activeFilterLabels().length;
    return count == 0 ? 1 : count;
  }

  String? _periodLabel(String? from, String? to) {
    String? fmt(String? raw) {
      final s = raw?.trim() ?? '';
      if (s.isEmpty) return null;
      final d = DateTime.tryParse(s);
      return d == null ? s : DateFormat('dd/MM/yy', 'pt_BR').format(d);
    }

    final a = fmt(from);
    final b = fmt(to);
    if (a != null && b != null) return 'Cadastro de $a a $b';
    if (a != null) return 'Cadastro desde $a';
    if (b != null) return 'Cadastro até $b';
    return null;
  }
}

// ───────────────────────── Peças da lista ─────────────────────────

/// Avatar de iniciais neutro — a cor da linha fica para o significado
/// (status e atalhos), não para enfeite.
class _ClientInitialsAvatar extends StatelessWidget {
  const _ClientInitialsAvatar({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 44,
      height: 44,
      padding: const EdgeInsets.all(6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark
            ? AppColors.background.backgroundTertiaryDarkMode
            : AppColors.background.backgroundTertiary,
        border: Border.all(color: ThemeHelpers.borderColor(context)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          initials,
          maxLines: 1,
          style: TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            height: 1.0,
            color: ThemeHelpers.textColor(context),
          ),
        ),
      ),
    );
  }
}

/// Selo de status: ponto e fundo na cor do significado, texto legível.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.tone});

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.18 : 0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: isDark ? 0.45 : 0.36)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 11,
                height: 1.2,
                color: ThemeHelpers.textColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Etiqueta neutra de ícone + texto (tipo do cliente, "Desativado").
class _MetaTag extends StatelessWidget {
  const _MetaTag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: muted),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              height: 1.2,
              color: muted,
            ),
          ),
        ),
      ],
    );
  }
}

/// Linha de informação da lista (ícone + texto com reticências).
class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.text,
    this.maxLines = 1,
    this.strong = false,
  });

  final IconData icon;
  final String text;
  final int maxLines;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 14, color: muted),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 12.5,
              height: 1.3,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
              color: strong
                  ? ThemeHelpers.textColor(context).withValues(alpha: 0.9)
                  : muted,
            ),
          ),
        ),
      ],
    );
  }
}

/// Atalho de contato da linha (WhatsApp, Ligar, E-mail) — alvo de toque de
/// 36px, cor do canal só no ícone, no texto e num tom leve de fundo.
class _ContactChipButton extends StatelessWidget {
  const _ContactChipButton({
    required this.icon,
    required this.tone,
    required this.onTap,
    this.label,
    this.tooltip,
  });

  final IconData icon;
  final Color tone;
  final VoidCallback onTap;
  final String? label;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(10);
    final button = Material(
      color: tone.withValues(alpha: isDark ? 0.16 : 0.09),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: tone.withValues(alpha: isDark ? 0.42 : 0.30)),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(borderRadius: radius),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36, minWidth: 40),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: label == null ? 10 : 12,
              vertical: 7,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: tone),
                if (label != null) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label!,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                        color: tone,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    final message = tooltip ?? label;
    if (message == null) return button;
    return Tooltip(message: message, child: button);
  }
}

/// Número pequeno (filtros ativos) no botão de filtros e no menu.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.tone});

  final int count;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tone,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count > 9 ? '9+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          height: 1.1,
        ),
      ),
    );
  }
}

/// Contagem por tipo no resumo da carteira ("312 compradores").
class _TypeCount extends StatelessWidget {
  const _TypeCount({
    required this.icon,
    required this.count,
    required this.label,
  });

  final IconData icon;
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: muted),
        const SizedBox(width: 5),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: _compactIntFormatter.format(count),
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                TextSpan(
                  text: ' $label',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 12.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// Esqueleto do resumo da carteira (número + rótulo + tipos).
class _SummarySkeleton extends StatelessWidget {
  const _SummarySkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SkeletonBox(width: 92, height: 34, borderRadius: 8),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(flex: 7, child: SkeletonText(height: 13)),
                      Spacer(flex: 3),
                    ],
                  ),
                  SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(flex: 5, child: SkeletonText(height: 11)),
                      Spacer(flex: 5),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(flex: 8, child: SkeletonText(height: 12)),
            Spacer(flex: 2),
          ],
        ),
      ],
    );
  }
}

/// Esqueleto FIEL à linha do cliente: avatar, nome, selo + tipo, duas
/// linhas de informação e os atalhos de contato.
class _ClientRowSkeleton extends StatelessWidget {
  const _ClientRowSkeleton({required this.isLast});

  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 44, height: 44, borderRadius: 22),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(flex: 6, child: SkeletonText(height: 15)),
                        Spacer(flex: 4),
                      ],
                    ),
                    SizedBox(height: 9),
                    Row(
                      children: [
                        SkeletonBox(width: 80, height: 20, borderRadius: 999),
                        SizedBox(width: 10),
                        SkeletonBox(width: 64, height: 12, borderRadius: 4),
                      ],
                    ),
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(flex: 8, child: SkeletonText(height: 11)),
                        Spacer(flex: 2),
                      ],
                    ),
                    SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(flex: 6, child: SkeletonText(height: 11)),
                        Spacer(flex: 4),
                      ],
                    ),
                    SizedBox(height: 12),
                    Row(
                      children: [
                        SkeletonBox(width: 100, height: 34, borderRadius: 10),
                        SizedBox(width: 8),
                        SkeletonBox(width: 72, height: 34, borderRadius: 10),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Padding(
            padding: const EdgeInsets.only(left: 72),
            child: Divider(
              height: 1,
              thickness: 1,
              color: ThemeHelpers.borderLightColor(context),
            ),
          ),
      ],
    );
  }
}

/// Pill compacta que mostra a contagem de matches pendentes do cliente.
///
/// Aparece apenas quando há matches > 0; do contrário, ocupa zero espaço.
class _MatchesPill extends StatefulWidget {
  const _MatchesPill({
    required this.clientId,
    required this.accent,
    this.onTap,
  });

  final String clientId;
  final Color accent;
  final VoidCallback? onTap;

  @override
  State<_MatchesPill> createState() => _MatchesPillState();
}

class _MatchesPillState extends State<_MatchesPill> {
  int _count = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await MatchService.instance.getMatches(
        status: MatchStatus.pending,
        clientId: widget.clientId,
        limit: 1,
      );
      if (!mounted) return;
      setState(() {
        _count = response.data?.total ?? 0;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _count == 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final color = widget.accent;
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 4),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: color.withValues(alpha: 0.12),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.handshake_outlined, size: 12, color: color),
              const SizedBox(width: 4),
              Text(
                _count > 99 ? '99+' : '$_count',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  height: 1.0,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Extensão para clonar filtros, útil em vários pontos da listagem.
extension ClientSearchFiltersExtension on ClientSearchFilters {
  ClientSearchFilters copyWith({
    String? name,
    String? email,
    String? phone,
    String? search,
    String? document,
    String? city,
    String? neighborhood,
    String? state,
    ClientType? type,
    ClientStatus? status,
    String? responsibleUserId,
    bool? isActive,
    bool? onlyMyData,
    String? createdFrom,
    String? createdTo,
    int? limit,
    int? page,
    String? sortBy,
    String? sortOrder,
  }) {
    return ClientSearchFilters(
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      search: search ?? this.search,
      document: document ?? this.document,
      city: city ?? this.city,
      neighborhood: neighborhood ?? this.neighborhood,
      state: state ?? this.state,
      type: type ?? this.type,
      status: status ?? this.status,
      responsibleUserId: responsibleUserId ?? this.responsibleUserId,
      isActive: isActive ?? this.isActive,
      onlyMyData: onlyMyData ?? this.onlyMyData,
      createdFrom: createdFrom ?? this.createdFrom,
      createdTo: createdTo ?? this.createdTo,
      limit: limit ?? this.limit,
      page: page ?? this.page,
      sortBy: sortBy ?? this.sortBy,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}
