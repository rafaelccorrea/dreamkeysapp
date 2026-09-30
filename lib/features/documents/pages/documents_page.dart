import 'package:flutter/material.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/utils/error_cause.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../core/routes/app_routes.dart';
import '../services/document_service.dart';
import '../models/document_model.dart';
import '../utils/document_file_actions.dart';
import '../utils/document_permissions.dart';
import '../widgets/document_access_locked.dart';
import '../widgets/document_filters_drawer.dart';
import '../widgets/upload_tokens_modal.dart';
import 'send_document_for_signature_page.dart';

/// Ações do menu de cada documento (paridade com o menu do item da
/// biblioteca do web: ver, baixar, editar, enviar p/ assinatura, aprovar,
/// recusar e excluir — cada uma com a permissão correspondente).
enum _DocAction { view, download, edit, sendForSignature, approve, reject, delete }

/// Largura máxima da coluna da biblioteca em tela larga (tablet/landscape):
/// a lista não estica por 1000dp — centraliza numa coluna de leitura, com as
/// margens de 16 valendo dentro dela.
const double _kLibraryMaxWidth = 820;

/// Página de listagem de documentos
class DocumentsPage extends StatefulWidget {
  const DocumentsPage({super.key});

  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends State<DocumentsPage>
    with SingleTickerProviderStateMixin {
  final DocumentService _documentService = DocumentService.instance;
  late TabController _tabController;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  List<Document> _documents = [];
  int _currentPage = 1;
  int _totalPages = 1;
  /// Diagnóstico da falha (API ou exceção) — preserva o código HTTP.
  ErrorCause? _errorCause;
  DocumentFilters? _filters;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  // Documentos por tab
  List<Document> _allDocuments = [];
  List<Document> _myDocuments = [];
  List<Document> _pendingDocuments = [];
  List<Document> _approvedDocuments = [];
  
  // Estado de carregamento por tab
  bool _isLoadingMyDocuments = false;
  bool _isLoadingPendingDocuments = false;
  bool _isLoadingApprovedDocuments = false;

  /// Seleção múltipla (toque longo) para as ações em lote do web:
  /// aprovar, recusar, baixar e excluir.
  final Set<String> _selectedIds = <String>{};
  bool _bulkBusy = false;
  String? _busyDocumentId;

  bool get _selecting => _selectedIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    ModuleAccessService.instance.addListener(_onAccessChanged);
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadDocuments();
    _scrollController.addListener(_onScroll);
  }

  void _onAccessChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ModuleAccessService.instance.removeListener(_onAccessChanged);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    if (_selectedIds.isNotEmpty) setState(_selectedIds.clear);
    _loadDocumentsForCurrentTab(force: true);
  }

  // ─── Ações por item e em lote ─────────────────────────────────────────

  void _snack(String text, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: ok ? AppColors.status.success : AppColors.status.error,
      ),
    );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        // Rola em vez de estourar com texto a 130% / landscape.
        scrollable: true,
        title: Text(title),
        content: Text(message),
        actions: [
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
              backgroundColor: destructive
                  ? AppColors.status.error
                  : AppColors.status.success,
              foregroundColor: Colors.white,
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _refreshAfterAction() async {
    setState(() {
      _allDocuments.clear();
      _myDocuments.clear();
      _pendingDocuments.clear();
      _approvedDocuments.clear();
    });
    await _loadDocumentsForCurrentTab(force: true);
  }

  void _toggleSelected(Document d) {
    setState(() {
      if (!_selectedIds.remove(d.id)) _selectedIds.add(d.id);
    });
  }

  Future<void> _openSendForSignature(Document d) async {
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SendDocumentForSignaturePage(documentId: d.id),
      ),
    );
    if (sent == true && mounted) _refreshAfterAction();
  }

  Future<void> _handleDocAction(_DocAction action, Document d) async {
    switch (action) {
      case _DocAction.view:
        await Navigator.pushNamed(context, AppRoutes.documentDetails(d.id));
        if (mounted) _refreshAfterAction();
        break;
      case _DocAction.download:
        setState(() => _busyDocumentId = d.id);
        await DocumentFileActions.download(
          context,
          d.fileUrl,
          d.originalName.isNotEmpty ? d.originalName : d.fileName,
        );
        if (mounted) setState(() => _busyDocumentId = null);
        break;
      case _DocAction.edit:
        await Navigator.pushNamed(context, AppRoutes.documentEdit(d.id));
        if (mounted) _refreshAfterAction();
        break;
      case _DocAction.sendForSignature:
        await _openSendForSignature(d);
        break;
      case _DocAction.approve:
      case _DocAction.reject: {
        final approving = action == _DocAction.approve;
        final ok = await _confirm(
          title: approving ? 'Aprovar documento' : 'Recusar documento',
          message: approving
              ? 'Confirmar a aprovação de "${d.title ?? d.originalName}"?'
              : 'Confirmar a recusa de "${d.title ?? d.originalName}"?',
          confirmLabel: approving ? 'Aprovar' : 'Recusar',
          destructive: !approving,
        );
        if (!ok || !mounted) return;
        setState(() => _busyDocumentId = d.id);
        final res = await _documentService.approveDocument(
          d.id,
          status:
              approving ? DocumentStatus.approved : DocumentStatus.rejected,
        );
        if (!mounted) return;
        setState(() => _busyDocumentId = null);
        if (res.success) {
          _snack(
            approving ? 'Documento aprovado.' : 'Documento rejeitado.',
            ok: true,
          );
          _refreshAfterAction();
        } else {
          _snack(res.message ??
              (approving
                  ? 'Erro ao aprovar documento.'
                  : 'Erro ao rejeitar documento.'));
        }
        break;
      }
      case _DocAction.delete: {
        final ok = await _confirm(
          title: 'Excluir documento',
          message:
              'Excluir "${d.title ?? d.originalName}"? Esta ação não pode ser '
              'desfeita.',
          confirmLabel: 'Excluir',
          destructive: true,
        );
        if (!ok || !mounted) return;
        setState(() => _busyDocumentId = d.id);
        final res = await _documentService.deleteDocuments([d.id]);
        if (!mounted) return;
        setState(() => _busyDocumentId = null);
        if (res.success) {
          _snack('Documento excluído.', ok: true);
          _refreshAfterAction();
        } else {
          _snack(res.message ?? 'Erro ao excluir documento.');
        }
        break;
      }
    }
  }

  List<Document> get _selectedDocuments =>
      _documents.where((d) => _selectedIds.contains(d.id)).toList();

  Future<void> _bulkReview(bool approving) async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    final ok = await _confirm(
      title: approving ? 'Aprovar documentos' : 'Recusar documentos',
      message: approving
          ? 'Aprovar ${ids.length} documento(s)?'
          : 'Recusar ${ids.length} documento(s)?',
      confirmLabel: approving ? 'Aprovar' : 'Recusar',
      destructive: !approving,
    );
    if (!ok || !mounted) return;
    setState(() => _bulkBusy = true);
    final results = await Future.wait(
      ids.map(
        (id) => _documentService.approveDocument(
          id,
          status:
              approving ? DocumentStatus.approved : DocumentStatus.rejected,
        ),
      ),
    );
    if (!mounted) return;
    final okCount = results.where((r) => r.success).length;
    setState(() {
      _bulkBusy = false;
      _selectedIds.clear();
    });
    if (okCount == ids.length) {
      _snack(
        approving
            ? '$okCount documento(s) aprovado(s).'
            : '$okCount documento(s) rejeitado(s).',
        ok: true,
      );
    } else {
      _snack(
        approving
            ? 'Erro ao aprovar documentos ($okCount de ${ids.length}).'
            : 'Erro ao rejeitar documentos ($okCount de ${ids.length}).',
      );
    }
    _refreshAfterAction();
  }

  Future<void> _bulkDelete() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    final ok = await _confirm(
      title: 'Excluir documentos',
      message:
          'Excluir ${ids.length} documento(s)? Esta ação não pode ser desfeita.',
      confirmLabel: 'Excluir',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _bulkBusy = true);
    final res = await _documentService.deleteDocuments(ids);
    if (!mounted) return;
    setState(() {
      _bulkBusy = false;
      if (res.success) _selectedIds.clear();
    });
    if (res.success) {
      _snack('${ids.length} documento(s) excluído(s).', ok: true);
      _refreshAfterAction();
    } else {
      _snack(res.message ?? 'Erro ao excluir documentos.');
    }
  }

  Future<void> _bulkDownload() async {
    final docs = _selectedDocuments;
    if (docs.isEmpty) return;
    setState(() => _bulkBusy = true);
    final n = await DocumentFileActions.downloadMany(
      context,
      docs
          .map(
            (d) => MapEntry(
              d.fileUrl,
              d.originalName.isNotEmpty ? d.originalName : d.fileName,
            ),
          )
          .toList(),
    );
    if (!mounted) return;
    setState(() => _bulkBusy = false);
    if (n > 0) _snack('Download iniciado para $n arquivo(s).', ok: true);
  }

  Future<void> _loadDocumentsForCurrentTab({bool force = false}) async {
    switch (_tabController.index) {
      case 0: // Todos
        if (force || _allDocuments.isEmpty) {
          await _loadDocuments(refresh: true);
        } else {
          setState(() {
            _documents = _allDocuments;
          });
        }
        break;
      case 1: // Meus
        if (force || (_myDocuments.isEmpty && !_isLoadingMyDocuments)) {
          await _loadMyDocuments();
        } else {
          setState(() {
            _documents = _myDocuments;
          });
        }
        break;
      case 2: // Pendentes
        if (force || (_pendingDocuments.isEmpty && !_isLoadingPendingDocuments)) {
          await _loadPendingDocuments();
        } else {
          setState(() {
            _documents = _pendingDocuments;
          });
        }
        break;
      case 3: // Aprovados
        if (force || (_approvedDocuments.isEmpty && !_isLoadingApprovedDocuments)) {
          await _loadApprovedDocuments();
        } else {
          setState(() {
            _documents = _approvedDocuments;
          });
        }
        break;
    }
  }

  Future<void> _loadMyDocuments() async {
    setState(() => _isLoadingMyDocuments = true);

    try {
      final baseFilters = DocumentFilters(
        onlyMyDocuments: true,
        search: _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
      );
      
      // Mesclar com filtros aplicados
      final filters = _filters != null 
          ? baseFilters.copyWith(
              type: _filters!.type,
              status: _filters!.status,
              sortBy: _filters!.sortBy,
              sortOrder: _filters!.sortOrder,
            )
          : baseFilters;

      final response = await _documentService.getDocuments(
        filters: filters,
        page: 1,
        limit: 100,
      );

      if (mounted && response.success && response.data != null) {
        setState(() {
          _myDocuments = response.data!.data;
          _documents = _myDocuments;
          _isLoadingMyDocuments = false;
        });
      } else {
        setState(() => _isLoadingMyDocuments = false);
      }
    } catch (e) {
      debugPrint('❌ [DOCUMENTS_PAGE] Erro ao carregar meus documentos: $e');
      if (mounted) {
        setState(() => _isLoadingMyDocuments = false);
      }
    }
  }

  Future<void> _loadPendingDocuments() async {
    setState(() => _isLoadingPendingDocuments = true);

    try {
      final baseFilters = DocumentFilters(
        status: DocumentStatus.pendingReview,
        search: _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
      );
      
      // Mesclar com filtros aplicados (sem sobrescrever o status pendente)
      final filters = _filters != null 
          ? baseFilters.copyWith(
              type: _filters!.type,
              sortBy: _filters!.sortBy,
              sortOrder: _filters!.sortOrder,
            )
          : baseFilters;

      final response = await _documentService.getDocuments(
        filters: filters,
        page: 1,
        limit: 100,
      );

      if (mounted && response.success && response.data != null) {
        setState(() {
          _pendingDocuments = response.data!.data;
          _documents = _pendingDocuments;
          _isLoadingPendingDocuments = false;
        });
      } else {
        setState(() => _isLoadingPendingDocuments = false);
      }
    } catch (e) {
      debugPrint('❌ [DOCUMENTS_PAGE] Erro ao carregar documentos pendentes: $e');
      if (mounted) {
        setState(() => _isLoadingPendingDocuments = false);
      }
    }
  }

  Future<void> _loadApprovedDocuments() async {
    setState(() => _isLoadingApprovedDocuments = true);

    try {
      final baseFilters = DocumentFilters(
        status: DocumentStatus.approved,
        search: _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
      );
      
      // Mesclar com filtros aplicados (sem sobrescrever o status aprovado)
      final filters = _filters != null 
          ? baseFilters.copyWith(
              type: _filters!.type,
              sortBy: _filters!.sortBy,
              sortOrder: _filters!.sortOrder,
            )
          : baseFilters;

      final response = await _documentService.getDocuments(
        filters: filters,
        page: 1,
        limit: 100,
      );

      if (mounted && response.success && response.data != null) {
        setState(() {
          _approvedDocuments = response.data!.data;
          _documents = _approvedDocuments;
          _isLoadingApprovedDocuments = false;
        });
      } else {
        setState(() => _isLoadingApprovedDocuments = false);
      }
    } catch (e) {
      debugPrint('❌ [DOCUMENTS_PAGE] Erro ao carregar documentos aprovados: $e');
      if (mounted) {
        setState(() => _isLoadingApprovedDocuments = false);
      }
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _currentPage < _totalPages) {
        _loadMoreDocuments();
      }
    }
  }

  Future<void> _loadDocuments({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _currentPage = 1;
        _documents.clear();
      });
    }

    setState(() {
      _isLoading = true;
      _errorCause = null;
    });

    try {
      DocumentFilters? filters;
      if (_filters != null || _searchQuery.trim().isNotEmpty) {
        filters = (_filters ?? DocumentFilters()).copyWith(
          search: _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
        );
      }

      final response = await _documentService.getDocuments(
        filters: filters,
        page: _currentPage,
        limit: 20,
      );

      if (mounted) {
        if (response.success && response.data != null) {
          final documents = response.data!.data;
          setState(() {
            if (refresh) {
              _allDocuments = documents;
            } else {
              _allDocuments.addAll(documents);
            }
            _totalPages = response.data!.pagination?.totalPages ?? 1;
            _errorCause = null;
            _isLoading = false;
            _isLoadingMore = false;
          });
          // Atualizar lista exibida baseada na tab atual
          if (_tabController.index == 0) {
            _documents = _allDocuments;
          }
        } else {
          setState(() {
            _errorCause = ErrorCause.fromApi(
              message: response.message,
              statusCode: response.statusCode,
            );
            _isLoading = false;
            _isLoadingMore = false;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ [DOCUMENTS_PAGE] Erro: $e');
      if (mounted) {
        setState(() {
          _errorCause = ErrorCause.fromException(e);
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMoreDocuments() async {
    if (_isLoadingMore || _currentPage >= _totalPages) return;

    setState(() {
      _isLoadingMore = true;
      _currentPage++;
    });

    await _loadDocuments();
  }

  bool _hasActiveFilters() {
    if (_filters == null) return false;
    return _filters!.type != null ||
        _filters!.status != null ||
        _filters!.sortBy != null;
  }

  Future<void> _handleSearch(String query) async {
    setState(() {
      _searchQuery = query;
      _currentPage = 1;
      _allDocuments.clear();
      _myDocuments.clear();
      _pendingDocuments.clear();
      _approvedDocuments.clear();
    });
    
    // Recarregar documentos baseado na tab atual
    await _loadDocumentsForCurrentTab(force: true);
  }

  void _openUploadLinks() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const UploadTokensModal(),
    );
  }

  // ─── Apoio de apresentação ────────────────────────────────────────────

  Future<void> _openCreate() async {
    await Navigator.pushNamed(context, AppRoutes.documentCreate);
    if (mounted) _refreshAfterAction();
  }

  void _openFilters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DocumentFiltersDrawer(
        initialFilters: _filters,
        onFiltersChanged: (filters) {
          setState(() {
            _filters = filters;
            // Limpar listas para forçar recarregamento
            _allDocuments.clear();
            _myDocuments.clear();
            _pendingDocuments.clear();
            _approvedDocuments.clear();
          });
          _loadDocumentsForCurrentTab(force: true);
        },
      ),
    );
  }

  /// Quantos filtros do drawer estão valendo (os mesmos campos de
  /// [_hasActiveFilters]) — vira a contagem no botão de filtros.
  int _activeFilterCount() {
    final f = _filters;
    if (f == null) return 0;
    var n = 0;
    if (f.type != null) n++;
    if (f.status != null) n++;
    if (f.sortBy != null) n++;
    return n;
  }

  /// Ação sem permissão fica à vista, travada: o toque explica o motivo.
  void _explainLocked(String reason) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 18,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(reason)),
          ],
        ),
      ),
    );
  }

  /// Ícone de ação travada: o próprio ícone esmaecido com um cadeado no
  /// canto — a ação continua à vista, só não abre.
  Widget _lockedGlyph(BuildContext context, IconData icon) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return SizedBox(
      width: 26,
      height: 26,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Center(
            child: Icon(icon, color: muted.withValues(alpha: 0.55)),
          ),
          Positioned(
            right: -3,
            bottom: -2,
            child: Icon(Icons.lock_rounded, size: 12, color: muted),
          ),
        ],
      ),
    );
  }

  /// Recuo extra em tela larga para centralizar a coluna da biblioteca
  /// (no celular é zero: o conteúdo encosta nas margens de 16).
  double _wideInset(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width > _kLibraryMaxWidth ? (width - _kLibraryMaxWidth) / 2 : 0;
  }

  /// Lista própria de cada aba: cada página do TabBarView desenha a SUA
  /// lista — no deslize, a aba que entra não exibe a lista da outra.
  List<Document> _docsForTab(int tab) {
    switch (tab) {
      case 1:
        return _myDocuments;
      case 2:
        return _pendingDocuments;
      case 3:
        return _approvedDocuments;
      default:
        return _allDocuments;
    }
  }

  bool _loadingForTab(int tab) {
    switch (tab) {
      case 1:
        return _isLoadingMyDocuments;
      case 2:
        return _isLoadingPendingDocuments;
      case 3:
        return _isLoadingApprovedDocuments;
      default:
        return _isLoading;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Porta da biblioteca (web: ModuleRoute('document_management') +
    // document:read). Sem ela, cadeado com o motivo.
    if (!DocumentPermissions.canOpenLibrary) {
      return const AppScaffold(
        title: 'Documentos',
        showBottomNavigation: true,
        body: DocumentAccessLocked(),
      );
    }

    final canCreate = DocumentPermissions.canCreate;
    // Lido aqui, acima do Scaffold: dentro do corpo o Scaffold zera o
    // viewInsets do teclado.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return AppScaffold(
      title: 'Documentos',
      showBottomNavigation: true,
      // Duas ações só: com três, o cabeçalho estoura em 320dp. Os filtros
      // foram para o lado da busca, com a contagem no próprio botão.
      actions: [
        IconButton(
          icon: canCreate
              ? const Icon(Icons.add)
              : _lockedGlyph(context, Icons.add),
          onPressed: canCreate
              ? _openCreate
              : () => _explainLocked(
                    'Enviar documentos exige a permissão de criar '
                    'documentos. Peça a um administrador para liberar.',
                  ),
          tooltip: canCreate ? 'Novo documento' : 'Novo documento (bloqueado)',
        ),
        PopupMenuButton<String>(
          tooltip: 'Mais opções',
          icon: const Icon(Icons.more_vert),
          onSelected: (v) {
            if (v == 'signatures') {
              Navigator.pushNamed(context, AppRoutes.signatures);
            } else if (v == 'links') {
              _openUploadLinks();
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'signatures',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.draw_outlined),
                title: Text('Assinaturas'),
              ),
            ),
            if (canCreate)
              const PopupMenuItem(
                value: 'links',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.link),
                  title: Text('Links públicos'),
                ),
              )
            else
              const PopupMenuItem(
                value: 'links',
                enabled: false,
                child: ListTile(
                  enabled: false,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.lock_outline_rounded),
                  title: Text('Links públicos'),
                  subtitle: Text('Exige a permissão de criar documentos'),
                ),
              ),
          ],
        ),
      ],
      body: LayoutBuilder(
        builder: (context, box) {
          // Tela baixa (landscape com teclado aberto, tela dividida): as
          // abas saem de cena para a busca e a lista caberem. A estrutura
          // da coluna não muda (Visibility), então o campo de busca não é
          // recriado e o teclado não fecha.
          final showTabs = box.maxHeight >= (keyboardOpen ? 240 : 170);
          final showBulkBar =
              _selecting && !(keyboardOpen && box.maxHeight < 240);
          return Column(
            children: [
              Visibility(
                visible: showTabs,
                maintainState: true,
                maintainAnimation: true,
                child: _buildTabs(context, theme),
              ),
              _buildSearchBar(context, theme),
              Expanded(
                child: _isLoading && _documents.isEmpty
                    ? _buildSkeleton(context, theme)
                    : _errorCause != null && _documents.isEmpty
                        ? _buildErrorState(context, theme)
                        : TabBarView(
                            controller: _tabController,
                            children: [
                              for (var tab = 0; tab < 4; tab++)
                                _buildDocumentsList(context, theme, tab),
                            ],
                          ),
              ),
              if (showBulkBar) _buildBulkBar(context, theme),
            ],
          );
        },
      ),
    );
  }

  /// Abas com sublinhado (DNA do app) em linha única — ícone ao lado do
  /// rótulo, 46dp em vez de 72: sobra altura para a lista em landscape.
  Widget _buildTabs(BuildContext context, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;

    Widget tab(IconData icon, String label) {
      return Tab(
        height: 46,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            Text(label, maxLines: 1, softWrap: false),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderColor(context)),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: accent,
        unselectedLabelColor: ThemeHelpers.textSecondaryColor(context),
        indicatorColor: accent,
        dividerColor: Colors.transparent,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        padding: EdgeInsets.symmetric(horizontal: _wideInset(context)),
        labelStyle: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w500,
        ),
        tabs: [
          tab(Icons.folder_outlined, 'Todos'),
          tab(Icons.person_outline, 'Meus'),
          tab(Icons.pending_outlined, 'Pendentes'),
          tab(Icons.check_circle_outline, 'Aprovados'),
        ],
      ),
    );
  }

  /// Barra de ações em lote (web: aprovar/recusar com `canApprove`, baixar
  /// com `canDownload`, excluir com `canDelete`). Uma linha só (até 64dp,
  /// abaixo do botão flutuante do chat): a contagem em destaque e cada ação
  /// com ícone + rótulo, sem depender de tooltip. Sem nenhuma ação
  /// liberada, o motivo aparece no lugar.
  Widget _buildBulkBar(BuildContext context, ThemeData theme) {
    final n = _selectedIds.length;
    final isDark = theme.brightness == Brightness.dark;
    final canApprove = DocumentPermissions.canApprove;
    final canDownload = DocumentPermissions.canDownload;
    final canDelete = DocumentPermissions.canDelete;
    final textColor = ThemeHelpers.textColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final ok =
        isDark ? AppColors.status.successDarkMode : AppColors.status.success;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final inset = _wideInset(context);

    Widget action(
      IconData icon,
      String label,
      VoidCallback onTap,
      Color color,
    ) {
      return Tooltip(
        message: label,
        child: InkWell(
          onTap: _bulkBusy ? null : onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 21, color: color),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      color: textColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final actions = <Widget>[
      if (canApprove) ...[
        action(
          Icons.check_circle_outline_rounded,
          'Aprovar',
          () => _bulkReview(true),
          ok,
        ),
        action(
          Icons.cancel_outlined,
          'Recusar',
          () => _bulkReview(false),
          danger,
        ),
      ],
      if (canDownload)
        action(Icons.download_outlined, 'Baixar', _bulkDownload, textColor),
      if (canDelete)
        action(Icons.delete_outline_rounded, 'Excluir', _bulkDelete, danger),
    ];

    final Widget trailing;
    if (_bulkBusy) {
      trailing = Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'Processando…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ),
        ],
      );
    } else if (actions.isEmpty) {
      trailing = Row(
        children: [
          Icon(Icons.lock_outline_rounded, size: 15, color: muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Seu perfil não tem ações em lote liberadas.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11.5,
                color: muted,
              ),
            ),
          ),
        ],
      );
    } else {
      trailing = Row(
        children: [
          for (final a in actions) Expanded(child: a),
        ],
      );
    }

    return Container(
      padding: EdgeInsets.fromLTRB(
        4 + inset,
        6,
        8 + inset,
        6 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border(
          top: BorderSide(color: ThemeHelpers.borderColor(context)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Cancelar seleção',
            onPressed: _bulkBusy ? null : () => setState(_selectedIds.clear),
            icon: Icon(Icons.close_rounded, color: muted),
          ),
          // Contagem em destaque, rótulo curto embaixo.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 84),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$n',
                    maxLines: 1,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                      color: textColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    n == 1 ? 'selecionado' : 'selecionados',
                    maxLines: 1,
                    softWrap: false,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: trailing),
        ],
      ),
    );
  }

  /// Página de uma aba. Cada página desenha a lista DAQUELA aba; o
  /// controller de rolagem (paginação) fica só em "Todos" — é a única aba
  /// paginada, e um controller preso a quatro listas ao mesmo tempo quebra
  /// no deslize entre abas.
  Widget _buildDocumentsList(BuildContext context, ThemeData theme, int tab) {
    final docs = _docsForTab(tab);
    // Sem lista ainda (carregando, ou a aba que está entrando no deslize):
    // skeleton no lugar de um "nenhum documento" falso.
    if (docs.isEmpty && (_loadingForTab(tab) || tab != _tabController.index)) {
      return _buildSkeleton(context, theme);
    }
    final inset = _wideInset(context);

    return RefreshIndicator(
      color: AppColors.primary.primary,
      onRefresh: () async {
        if (_tabController.index == 0) {
          await _loadDocuments(refresh: true);
        } else {
          await _loadDocumentsForCurrentTab();
        }
      },
      child: CustomScrollView(
        controller: tab == 0 ? _scrollController : null,
        primary: false,
        // Rola mesmo com lista curta ou vazia: o puxar-para-atualizar
        // funciona sempre.
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (docs.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: tab == 0 && _errorCause != null
                  ? Center(
                      child: AppErrorState(
                        cause: _errorCause!,
                        onRetry: () => _loadDocuments(refresh: true),
                        dense: true,
                      ),
                    )
                  : _buildEmptyState(context, theme, tab),
            )
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: inset),
                child: _buildListHeader(context, theme, tab, docs),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: inset),
              sliver: SliverList.separated(
                itemCount: docs.length,
                separatorBuilder: (context, _) => _rowHairline(context),
                itemBuilder: (context, index) =>
                    _buildDocumentCard(context, theme, docs[index]),
              ),
            ),
            if (tab == 0 && _isLoadingMore)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: inset),
                  child: Column(
                    children: [
                      _rowHairline(context),
                      _buildSkeletonRow(),
                    ],
                  ),
                ),
              ),
            // Falha ao carregar a próxima página: a causa e o "Tentar de
            // novo" no fim da lista, em vez de silêncio.
            if (tab == 0 && _errorCause != null && !_isLoading)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: inset),
                  child: AppErrorState(
                    cause: _errorCause!,
                    onRetry: () => _loadDocuments(refresh: true),
                    dense: true,
                  ),
                ),
              ),
            // Folga no fim: a última linha sobe acima do botão flutuante do
            // chat (fica a 80dp do rodapé do corpo).
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ],
      ),
    );
  }

  /// Filete entre as linhas — recuado até a coluna do texto (depois da
  /// folha do arquivo), como nas listas do app.
  Widget _rowHairline(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.only(left: 68, right: 16),
      color: ThemeHelpers.borderColor(context),
    );
  }

  /// Busca no campo `filled` do tema + filtros com corpo ao lado, na mesma
  /// altura do campo.
  Widget _buildSearchBar(BuildContext context, ThemeData theme) {
    final inset = _wideInset(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16 + inset, 12, 16 + inset, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Buscar documentos',
                prefixIcon: Icon(Icons.search_rounded, size: 20, color: muted),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        tooltip: 'Limpar busca',
                        icon: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: muted,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          _handleSearch('');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              onChanged: (value) {
                _handleSearch(value);
              },
            ),
          ),
          const SizedBox(width: 8),
          _buildFilterButton(context, theme),
        ],
      ),
    );
  }

  /// Filtros com corpo: mesma altura e fundo do campo de busca; com filtro
  /// valendo, o botão veste a marca e mostra quantos.
  Widget _buildFilterButton(BuildContext context, ThemeData theme) {
    final active = _activeFilterCount();
    final on = active > 0;
    final isDark = theme.brightness == Brightness.dark;
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    return Tooltip(
      message: on
          ? 'Filtros ($active ${active == 1 ? 'ativo' : 'ativos'})'
          : 'Filtros',
      child: Material(
        color: on
            ? accent.withValues(alpha: isDark ? 0.18 : 0.08)
            : (theme.inputDecorationTheme.fillColor ?? Colors.transparent),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: on
                ? accent.withValues(alpha: 0.6)
                : ThemeHelpers.borderColor(context),
            width: 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _openFilters,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 21,
                  color: on ? accent : ThemeHelpers.textColor(context),
                ),
                if (on)
                  Positioned(
                    top: 5,
                    right: 5,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$active',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Carregando: skeleton fiel à lista — cabeçalho com a contagem e linhas
  /// com a folha do arquivo, título, selos e a linha de envio.
  Widget _buildSkeleton(BuildContext context, ThemeData theme) {
    final inset = _wideInset(context);
    return ListView(
      primary: false,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.symmetric(horizontal: inset),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Row(
            children: [
              SkeletonBox(width: 30, height: 24, borderRadius: 6),
              SizedBox(width: 10),
              SkeletonText(width: 120, height: 12),
            ],
          ),
        ),
        for (var i = 0; i < 6; i++) ...[
          if (i > 0) _rowHairline(context),
          _buildSkeletonRow(),
        ],
      ],
    );
  }

  Widget _buildSkeletonRow() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 40, height: 50, borderRadius: 6),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FractionallySizedBox(
                  widthFactor: 0.8,
                  child: SkeletonText(height: 14),
                ),
                SizedBox(height: 10),
                Row(
                  children: [
                    SkeletonBox(width: 84, height: 20, borderRadius: 6),
                    SizedBox(width: 6),
                    SkeletonBox(width: 62, height: 20, borderRadius: 6),
                  ],
                ),
                SizedBox(height: 10),
                FractionallySizedBox(
                  widthFactor: 0.55,
                  child: SkeletonText(height: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, ThemeData theme) {
    return AppErrorState(
      cause: _errorCause!,
      onRetry: () => _loadDocuments(refresh: true),
    );
  }

  /// Vazio que ENSINA: o que aparece nesta aba e como chegar lá — ou, com
  /// busca/filtro, por que não apareceu nada e como desfazer.
  Widget _buildEmptyState(BuildContext context, ThemeData theme, int tab) {
    final textColor = ThemeHelpers.textColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final query = _searchQuery.trim();
    // Limpar/ajustar é ação neutra (o tema pinta OutlinedButton de vermelho).
    final neutral = OutlinedButton.styleFrom(
      foregroundColor: textColor,
      side: BorderSide(color: ThemeHelpers.borderColor(context), width: 1.5),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      textStyle: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    );

    IconData icon;
    String title;
    String message;
    Widget? action;

    if (query.isNotEmpty) {
      icon = Icons.search_off_rounded;
      title = 'Nada encontrado para “$query”';
      message = 'A busca olha o título, o nome do arquivo, o cliente e o '
          'imóvel. Confira a grafia ou tente outro termo.';
      action = OutlinedButton.icon(
        style: neutral,
        onPressed: () {
          _searchController.clear();
          _handleSearch('');
        },
        icon: const Icon(Icons.close_rounded, size: 18),
        label: const Text('Limpar busca'),
      );
    } else if (_hasActiveFilters()) {
      icon = Icons.filter_alt_off_outlined;
      title = 'Nenhum documento com esses filtros';
      message = 'Os filtros escondem o restante da biblioteca. Ajuste ou '
          'limpe os filtros para ver mais.';
      action = OutlinedButton.icon(
        style: neutral,
        onPressed: _openFilters,
        icon: const Icon(Icons.tune_rounded, size: 18),
        label: const Text('Ajustar filtros'),
      );
    } else {
      switch (tab) {
        case 1:
          icon = Icons.person_outline_rounded;
          title = 'Nenhum documento da sua carteira';
          message = 'Aqui ficam os documentos dos clientes e imóveis pelos '
              'quais você é responsável.';
          break;
        case 2:
          icon = Icons.task_alt;
          title = 'Nada aguardando revisão';
          message = DocumentPermissions.canApprove
              ? 'Quando um documento precisar de revisão, ele aparece aqui '
                  'para você aprovar ou recusar direto na lista.'
              : 'Documentos enviados para revisão aparecem aqui até alguém '
                  'com permissão aprovar ou recusar.';
          break;
        case 3:
          icon = Icons.verified_outlined;
          title = 'Nenhum documento aprovado';
          message = 'Documentos aprovados na revisão aparecem aqui, prontos '
              'para consulta e download.';
          break;
        default:
          icon = Icons.folder_open_outlined;
          title = 'A biblioteca está vazia';
          message = 'Contratos, documentos pessoais, comprovantes e laudos '
              'dos seus clientes e imóveis ficam guardados aqui, com a '
              'revisão e as assinaturas de cada um.';
      }
      if (tab <= 1) {
        action = DocumentPermissions.canCreate
            ? ElevatedButton.icon(
                onPressed: _openCreate,
                icon: const Icon(Icons.add),
                label: const Text('Novo documento'),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline_rounded, size: 15, color: muted),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Enviar documentos exige permissão. Peça a um '
                      'administrador.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              );
      }
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: ThemeHelpers.cardBackgroundColor(context),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: ThemeHelpers.borderColor(context)),
                ),
                child: Icon(icon, size: 28, color: muted),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: muted,
                  height: 1.45,
                ),
              ),
              if (action != null) ...[
                const SizedBox(height: 20),
                action,
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Cabeçalho da lista: o número que importa em destaque, o que ele quer
  /// dizer nesta aba e os fatos que pedem atenção (revisão, assinatura,
  /// vencimento), contados sobre o que está carregado.
  Widget _buildListHeader(
    BuildContext context,
    ThemeData theme,
    int tab,
    List<Document> docs,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final n = docs.length;
    final more = tab == 0 && _currentPage < _totalPages;

    final String label;
    switch (tab) {
      case 1:
        label = n == 1
            ? 'documento da sua carteira'
            : 'documentos da sua carteira';
        break;
      case 2:
        label = 'aguardando revisão';
        break;
      case 3:
        label = n == 1 ? 'documento aprovado' : 'documentos aprovados';
        break;
      default:
        label = n == 1 ? 'documento' : 'documentos';
    }

    var pendingReview = 0;
    var awaitingSignature = 0;
    var expired = 0;
    var expiring = 0;
    for (final d in docs) {
      if (d.status == DocumentStatus.pendingReview) pendingReview++;
      final sig = d.signatures;
      if (sig != null && sig.hasSignatures && sig.pending > 0) {
        awaitingSignature++;
      }
      final days = _daysToExpiry(d);
      if (days != null) {
        if (days < 0) {
          expired++;
        } else if (days <= 30) {
          expiring++;
        }
      }
    }

    final warn =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final info = isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;

    final facts = <Widget>[
      if (tab != 2 && pendingReview > 0)
        _fact(
          theme,
          Icons.hourglass_top_rounded,
          warn,
          '$pendingReview aguardando revisão',
        ),
      if (awaitingSignature > 0)
        _fact(
          theme,
          Icons.draw_outlined,
          info,
          awaitingSignature == 1
              ? '1 com assinatura pendente'
              : '$awaitingSignature com assinaturas pendentes',
        ),
      if (expired > 0)
        _fact(
          theme,
          Icons.event_busy_outlined,
          danger,
          expired == 1 ? '1 vencido' : '$expired vencidos',
        ),
      if (expiring > 0)
        _fact(
          theme,
          Icons.schedule_rounded,
          warn,
          expiring == 1
              ? '1 vence em até 30 dias'
              : '$expiring vencem em até 30 dias',
        ),
    ];

    final canBulk = DocumentPermissions.canApprove ||
        DocumentPermissions.canDownload ||
        DocumentPermissions.canDelete;
    final String? hint = _selecting
        ? 'Toque nos documentos para marcar ou desmarcar.'
        : (canBulk && n > 1
            ? 'Toque e segure um documento para selecionar vários.'
            : null);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$n',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                  letterSpacing: -0.5,
                  color: textColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: more
                            ? '$label ${n == 1 ? 'carregado' : 'carregados'}'
                            : label,
                      ),
                      if (more)
                        TextSpan(
                          text: ' · role para ver mais',
                          style: TextStyle(
                            color: muted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
          if (facts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 14, runSpacing: 6, children: facts),
          ],
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(
              hint,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11.5,
                color: muted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Linha flush de um documento — a "ficha" da biblioteca: folha com o
  /// formato do arquivo, título, selos (status, tipo, vencimento), o
  /// progresso das assinaturas, vínculo/envio/tamanho e a revisão no
  /// próprio item quando está pendente.
  Widget _buildDocumentCard(
    BuildContext context,
    ThemeData theme,
    Document document,
  ) {
    final selected = _selectedIds.contains(document.id);
    final busy = _busyDocumentId == document.id;
    final isDark = theme.brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final statusColor = _getStatusColor(document.status);
    final warn =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final info = isDark ? AppColors.status.infoDarkMode : AppColors.status.info;

    // Título vazio cai no nome do arquivo (como no web); o nome original
    // aparece embaixo só quando for diferente do título.
    final rawTitle = document.title?.trim() ?? '';
    final title = rawTitle.isNotEmpty
        ? rawTitle
        : (document.originalName.isNotEmpty
            ? document.originalName
            : 'Documento sem nome');
    final showOriginal = rawTitle.isNotEmpty &&
        document.originalName.isNotEmpty &&
        rawTitle != document.originalName;
    final sig = document.signatures;
    final expiryDays = _daysToExpiry(document);
    final tags = (document.tags ?? const <String>[])
        .where((t) => t.trim().isNotEmpty)
        .toList();
    final pendingReview = document.status == DocumentStatus.pendingReview;

    String? link;
    var linkIcon = Icons.person_outline_rounded;
    if (document.client != null && document.client!.name.trim().isNotEmpty) {
      link = document.client!.name.trim();
    } else if (document.property != null &&
        document.property!.title.trim().isNotEmpty) {
      link = document.property!.title.trim();
      linkIcon = Icons.home_outlined;
    } else if ((document.clientId ?? '').isNotEmpty) {
      link = 'Vinculado a um cliente';
    } else if ((document.propertyId ?? '').isNotEmpty) {
      link = 'Vinculado a um imóvel';
      linkIcon = Icons.home_outlined;
    }
    final uploader = document.uploadedBy?.name.trim() ?? '';
    final sent = uploader.isEmpty
        ? 'Enviado ${_ago(document.createdAt)}'
        : 'Enviado por $uploader ${_ago(document.createdAt)}';

    return Material(
      color: selected
          ? AppColors.primary.primary.withValues(alpha: isDark ? 0.14 : 0.06)
          : Colors.transparent,
      child: InkWell(
        onTap: () {
          if (_selecting) {
            _toggleSelected(document);
          } else {
            _handleDocAction(_DocAction.view, document);
          }
        },
        onLongPress: () => _toggleSelected(document),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 4, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Folha do arquivo (vira o check na seleção).
              _DocSheet(
                label: _extensionLabel(document),
                icon: _getFileIcon(document.fileExtension),
                statusColor: statusColor,
                selected: selected,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                        letterSpacing: -0.2,
                        color: textColor,
                      ),
                    ),
                    if (showOriginal) ...[
                      const SizedBox(height: 2),
                      Text(
                        document.originalName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11.5,
                          color: muted,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _selo(
                          theme,
                          icon: _statusIcon(document.status),
                          label: document.status.label,
                          color: statusColor,
                        ),
                        _selo(
                          theme,
                          icon: _typeIcon(document.type),
                          label: document.type.label,
                        ),
                        if (expiryDays != null && expiryDays < 0)
                          _selo(
                            theme,
                            icon: Icons.event_busy_outlined,
                            label: 'Vencido',
                            color: danger,
                          )
                        else if (expiryDays != null && expiryDays <= 30)
                          _selo(
                            theme,
                            icon: Icons.schedule_rounded,
                            label: expiryDays == 0
                                ? 'Vence hoje'
                                : 'Vence em $expiryDays '
                                    '${expiryDays == 1 ? 'dia' : 'dias'}',
                            color: warn,
                          ),
                        if (document.isEncrypted)
                          _selo(
                            theme,
                            icon: Icons.lock_outline_rounded,
                            label: 'Criptografado',
                            color: info,
                          ),
                        for (final tag in tags.take(2))
                          _selo(theme, icon: Icons.sell_outlined, label: tag),
                        if (tags.length > 2)
                          _selo(theme, label: '+${tags.length - 2}'),
                      ],
                    ),
                    if (sig != null && sig.hasSignatures && sig.total > 0) ...[
                      const SizedBox(height: 10),
                      _buildSignatureProgress(theme, sig),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        if (link != null) _meta(theme, linkIcon, link),
                        _meta(theme, Icons.file_upload_outlined, sent),
                        if (document.fileSize > 0)
                          _meta(
                            theme,
                            Icons.insert_drive_file_outlined,
                            _formatFileSize(document.fileSize),
                          ),
                        if (expiryDays != null && expiryDays > 30)
                          _meta(
                            theme,
                            Icons.event_outlined,
                            'Vence em ${_formatDate(document.expiryDate!)}',
                          ),
                      ],
                    ),
                    if (pendingReview && !_selecting) ...[
                      const SizedBox(height: 12),
                      DocumentPermissions.canApprove
                          ? _buildReviewActions(theme, document, busy)
                          : _buildReviewLocked(theme),
                    ],
                  ],
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (!_selecting)
                _buildItemMenu(document)
              else
                const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }

  /// Selo do item: ícone e fundo na cor do significado; o texto fica na
  /// cor do texto (âmbar como letra some no branco). Sem cor = neutro.
  Widget _selo(
    ThemeData theme, {
    IconData? icon,
    required String label,
    Color? color,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    final tone = color ?? ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color == null
            ? ThemeHelpers.borderLightColor(context)
                .withValues(alpha: isDark ? 0.7 : 0.55)
            : color.withValues(alpha: isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: color == null
              ? ThemeHelpers.borderColor(context)
              : color.withValues(alpha: isDark ? 0.42 : 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: tone),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
                height: 1.25,
                color: ThemeHelpers.textColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Pedaço da linha de contexto (vínculo, envio, tamanho): ícone + texto
  /// que encurta com reticências em vez de empurrar a linha.
  Widget _meta(ThemeData theme, IconData icon, String text) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: muted),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: muted,
            ),
          ),
        ),
      ],
    );
  }

  /// Fato do cabeçalho (ex.: "3 aguardando revisão"): ícone na cor do
  /// significado, texto forte — sem virar pílula.
  Widget _fact(ThemeData theme, IconData icon, Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: ThemeHelpers.textColor(context),
            ),
          ),
        ),
      ],
    );
  }

  /// Assinaturas de relance: quantas já foram, quantas recusaram e a barra
  /// de progresso (mesma leitura de cor do web: pendente = âmbar, todas =
  /// verde, recusa = vermelho, o resto = azul).
  Widget _buildSignatureProgress(
    ThemeData theme,
    DocumentSignaturesInfo sig,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final Color tone;
    if (sig.pending > 0) {
      tone = isDark
          ? AppColors.status.warningDarkMode
          : AppColors.status.warning;
    } else if (sig.allSigned) {
      tone = isDark
          ? AppColors.status.successDarkMode
          : AppColors.status.success;
    } else if (sig.rejected > 0) {
      tone = danger;
    } else {
      tone = isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
    }
    final fraction = (sig.signed / sig.total).clamp(0.0, 1.0).toDouble();
    final percent = (fraction * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.draw_outlined, size: 14, color: tone),
            const SizedBox(width: 6),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${sig.signed} de ${sig.total} '
                          '${sig.total == 1 ? 'assinatura' : 'assinaturas'}',
                    ),
                    if (sig.rejected > 0)
                      TextSpan(
                        text: ' · ${sig.rejected} '
                            '${sig.rejected == 1 ? 'recusada' : 'recusadas'}',
                        style: TextStyle(color: danger),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$percent%',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: textColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 4,
          width: double.infinity,
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: ThemeHelpers.borderLightColor(context),
            borderRadius: BorderRadius.circular(99),
          ),
          child: FractionallySizedBox(
            widthFactor: fraction,
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tone,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Revisão no próprio item (web: aprovar/recusar com `canApprove`):
  /// aprovar é o verde de confirmação, recusar é vermelho vazado — o
  /// diálogo de sempre confirma antes de gravar. Duas metades iguais numa
  /// linha (rótulo encolhe em vez de quebrar), com teto de largura para
  /// não virarem faixas em tablet.
  Widget _buildReviewActions(ThemeData theme, Document d, bool busy) {
    final isDark = theme.brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final blocked = busy || _bulkBusy;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    final labelStyle = theme.textTheme.labelLarge?.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w700,
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: blocked
                  ? null
                  : () => _handleDocAction(_DocAction.approve, d),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.status.success,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: shape,
                textStyle: labelStyle,
              ),
              icon: const Icon(Icons.check_rounded, size: 17),
              label: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('Aprovar', maxLines: 1, softWrap: false),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: blocked
                  ? null
                  : () => _handleDocAction(_DocAction.reject, d),
              style: OutlinedButton.styleFrom(
                foregroundColor: danger,
                side: BorderSide(
                  color: danger.withValues(alpha: 0.55),
                  width: 1.2,
                ),
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: shape,
                textStyle: labelStyle,
              ),
              icon: const Icon(Icons.close_rounded, size: 17),
              label: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('Recusar', maxLines: 1, softWrap: false),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Pendente sem permissão de aprovar: a revisão fica à vista, travada e
  /// com o motivo — em vez de sumir.
  Widget _buildReviewLocked(ThemeData theme) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(Icons.lock_outline_rounded, size: 14, color: muted),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Aguardando revisão — só quem tem a permissão de aprovar '
            'documentos pode aprovar ou recusar.',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11.5,
              height: 1.35,
              color: muted,
            ),
          ),
        ),
      ],
    );
  }

  /// Menu do item — cada ação só aparece com a permissão do web.
  Widget _buildItemMenu(Document d) {
    final canDownload = DocumentPermissions.canDownload;
    final canUpdate = DocumentPermissions.canUpdate;
    final canCreate = DocumentPermissions.canCreate;
    final canApprove = DocumentPermissions.canApprove;
    final canDelete = DocumentPermissions.canDelete;
    final pending = d.status == DocumentStatus.pendingReview;
    final allSigned = d.signatures?.allSigned ?? false;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ok =
        isDark ? AppColors.status.successDarkMode : AppColors.status.success;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;

    PopupMenuItem<_DocAction> item(
      _DocAction value,
      IconData icon,
      String label, {
      Color? color,
    }) {
      return PopupMenuItem<_DocAction>(
        value: value,
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: color != null ? TextStyle(color: color) : null,
              ),
            ),
          ],
        ),
      );
    }

    return PopupMenuButton<_DocAction>(
      tooltip: 'Ações',
      icon: Icon(
        Icons.more_vert,
        color: ThemeHelpers.textSecondaryColor(context),
      ),
      onSelected: (a) => _handleDocAction(a, d),
      itemBuilder: (context) => [
        item(_DocAction.view, Icons.visibility_outlined, 'Ver detalhes'),
        if (canDownload && d.fileUrl.isNotEmpty)
          item(_DocAction.download, Icons.download_outlined, 'Baixar'),
        if (canUpdate) item(_DocAction.edit, Icons.edit_outlined, 'Editar'),
        if (canCreate && !allSigned)
          item(
            _DocAction.sendForSignature,
            Icons.send_outlined,
            'Enviar para assinatura',
          ),
        if (canApprove && pending) ...[
          item(
            _DocAction.approve,
            Icons.check_circle_outline_rounded,
            'Aprovar',
            color: ok,
          ),
          item(
            _DocAction.reject,
            Icons.cancel_outlined,
            'Recusar',
            color: danger,
          ),
        ],
        // Destrutivo separado do resto por um filete.
        if (canDelete) ...[
          const PopupMenuDivider(),
          item(
            _DocAction.delete,
            Icons.delete_outline_rounded,
            'Excluir',
            color: danger,
          ),
        ],
      ],
    );
  }

  IconData _getFileIcon(String extension) {
    switch (extension.toLowerCase()) {
      case '.pdf':
        return Icons.picture_as_pdf;
      case '.doc':
      case '.docx':
        return Icons.description;
      case '.xls':
      case '.xlsx':
        return Icons.table_chart;
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.gif':
      case '.webp':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  /// Cor do status (mesma leitura do web): ativo = azul, aprovado = verde,
  /// pendente = âmbar, recusado/excluído = vermelho, arquivado = neutro —
  /// com a variante do modo escuro.
  Color _getStatusColor(DocumentStatus status) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    switch (status) {
      case DocumentStatus.active:
        return dark ? AppColors.status.infoDarkMode : AppColors.status.info;
      case DocumentStatus.approved:
        return dark
            ? AppColors.status.successDarkMode
            : AppColors.status.success;
      case DocumentStatus.pendingReview:
        return dark
            ? AppColors.status.warningDarkMode
            : AppColors.status.warning;
      case DocumentStatus.rejected:
        return dark ? AppColors.status.errorDarkMode : AppColors.status.error;
      case DocumentStatus.archived:
        return ThemeHelpers.textSecondaryColor(context);
      case DocumentStatus.deleted:
        return dark ? AppColors.status.errorDarkMode : AppColors.status.error;
    }
  }

  IconData _statusIcon(DocumentStatus status) {
    switch (status) {
      case DocumentStatus.active:
        return Icons.circle_outlined;
      case DocumentStatus.approved:
        return Icons.verified_outlined;
      case DocumentStatus.pendingReview:
        return Icons.hourglass_top_rounded;
      case DocumentStatus.rejected:
        return Icons.cancel_outlined;
      case DocumentStatus.archived:
        return Icons.inventory_2_outlined;
      case DocumentStatus.deleted:
        return Icons.delete_outline_rounded;
    }
  }

  /// Ícone do tipo (mesmo mapa do web: contrato = assinatura, identidade =
  /// crachá, comprovante de endereço = casa…).
  IconData _typeIcon(DocumentType type) {
    switch (type) {
      case DocumentType.contract:
        return Icons.draw_outlined;
      case DocumentType.identity:
        return Icons.badge_outlined;
      case DocumentType.proofOfAddress:
        return Icons.home_outlined;
      case DocumentType.proofOfIncome:
        return Icons.payments_outlined;
      case DocumentType.deed:
        return Icons.task_outlined;
      case DocumentType.registration:
        return Icons.fact_check_outlined;
      case DocumentType.taxDocument:
        return Icons.receipt_long_outlined;
      case DocumentType.inspectionReport:
        return Icons.assignment_outlined;
      case DocumentType.appraisal:
        return Icons.price_check;
      case DocumentType.photo:
        return Icons.photo_outlined;
      case DocumentType.other:
        return Icons.description_outlined;
    }
  }

  /// Formato do arquivo para a folha ("PDF", "DOCX"…): da extensão, ou do
  /// nome original quando a extensão não veio.
  String _extensionLabel(Document d) {
    var ext = d.fileExtension.trim();
    if (ext.isEmpty) {
      final name = d.originalName.trim();
      final dot = name.lastIndexOf('.');
      if (dot > 0 && dot < name.length - 1) ext = name.substring(dot + 1);
    }
    ext = ext.replaceAll('.', '').toUpperCase();
    return ext.length > 4 ? ext.substring(0, 4) : ext;
  }

  /// Dias até o vencimento (negativo = vencido) — a mesma conta do web
  /// (`daysFromNow`, arredondada para baixo).
  int? _daysToExpiry(Document d) {
    final expiry = d.expiryDate;
    if (expiry == null) return null;
    final ms = expiry.difference(DateTime.now()).inMilliseconds;
    return (ms / Duration.millisecondsPerDay).floor();
  }

  /// "hoje", "ontem", "há 3 dias", "há 2 meses" — a leitura do `timeAgo`
  /// do web, por extenso.
  String _ago(DateTime date) {
    final days = DateTime.now().difference(date).inDays;
    if (days <= 0) return 'hoje';
    if (days == 1) return 'ontem';
    if (days < 30) return 'há $days dias';
    if (days < 365) {
      final months = days ~/ 30;
      return months == 1 ? 'há 1 mês' : 'há $months meses';
    }
    final years = days ~/ 365;
    return years == 1 ? 'há 1 ano' : 'há $years anos';
  }

  String _formatDate(DateTime date) {
    final d = date.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  /// Tamanho em pt-BR ("850 KB", "1,2 MB"), como o web.
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    final mb = (bytes / (1024 * 1024)).toStringAsFixed(1);
    return '${mb.replaceAll('.', ',')} MB';
  }
}

/// Folha do arquivo na lista — o formato (PDF, DOCX…) escrito na folha e a
/// orelha dobrada na cor do status, lida de relance antes do texto. Na
/// seleção, a folha vira o check.
class _DocSheet extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color statusColor;
  final bool selected;

  const _DocSheet({
    required this.label,
    required this.icon,
    required this.statusColor,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final centered = selected || label.isEmpty;
    // A folha é um pictograma de tamanho fixo: o texto dela escala pouco,
    // para nunca estourar a folha com a fonte do sistema grande.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: SizedBox(
        width: 40,
        height: 50,
        child: CustomPaint(
          painter: _SheetPainter(
            fill: selected ? primary : ThemeHelpers.cardBackgroundColor(context),
            stroke: selected
                ? primary
                : (isDark
                    ? muted.withValues(alpha: 0.32)
                    : ThemeHelpers.borderColor(context)),
            ear: selected ? Colors.white.withValues(alpha: 0.45) : statusColor,
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: centered ? 14 : 11,
                child: Icon(
                  selected ? Icons.check_rounded : icon,
                  size: selected ? 22 : 17,
                  color: selected ? Colors.white : muted,
                ),
              ),
              if (!selected && label.isNotEmpty)
                Positioned(
                  left: 3,
                  right: 3,
                  bottom: 5,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                        height: 1.0,
                        color: ThemeHelpers.textColor(context),
                      ),
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

/// Desenho da folha: cantos arredondados, o canto superior direito cortado
/// e a orelha dobrada preenchida com a cor do status.
class _SheetPainter extends CustomPainter {
  final Color fill;
  final Color stroke;
  final Color ear;

  const _SheetPainter({
    required this.fill,
    required this.stroke,
    required this.ear,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const fold = 11.0;
    const r = 5.0;
    const o = 0.5;
    final w = size.width - o;
    final h = size.height - o;

    final sheet = Path()
      ..moveTo(o + r, o)
      ..lineTo(w - fold, o)
      ..lineTo(w, o + fold)
      ..lineTo(w, h - r)
      ..quadraticBezierTo(w, h, w - r, h)
      ..lineTo(o + r, h)
      ..quadraticBezierTo(o, h, o, h - r)
      ..lineTo(o, o + r)
      ..quadraticBezierTo(o, o, o + r, o)
      ..close();
    canvas.drawPath(sheet, Paint()..color = fill);
    canvas.drawPath(
      sheet,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final flap = Path()
      ..moveTo(w - fold, o)
      ..lineTo(w - fold, o + fold - 3)
      ..quadraticBezierTo(w - fold, o + fold, w - fold + 3, o + fold)
      ..lineTo(w, o + fold)
      ..close();
    canvas.drawPath(flap, Paint()..color = ear);
  }

  @override
  bool shouldRepaint(covariant _SheetPainter oldDelegate) =>
      oldDelegate.fill != fill ||
      oldDelegate.stroke != stroke ||
      oldDelegate.ear != ear;
}

/// Extensão para copiar filtros
extension DocumentFiltersExtension on DocumentFilters {
  DocumentFilters copyWith({
    DocumentType? type,
    DocumentStatus? status,
    String? clientId,
    String? propertyId,
    List<String>? tags,
    bool? onlyMyDocuments,
    String? search,
    String? sortBy,
    String? sortOrder,
  }) {
    return DocumentFilters(
      type: type ?? this.type,
      status: status ?? this.status,
      clientId: clientId ?? this.clientId,
      propertyId: propertyId ?? this.propertyId,
      tags: tags ?? this.tags,
      onlyMyDocuments: onlyMyDocuments ?? this.onlyMyDocuments,
      search: search ?? this.search,
      sortBy: sortBy ?? this.sortBy,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}

