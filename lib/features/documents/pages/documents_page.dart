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
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              foregroundColor: ThemeHelpers.textColor(ctx),
            ),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: destructive
                  ? AppColors.status.error
                  : AppColors.status.success,
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

    return AppScaffold(
      title: 'Documentos',
      showBottomNavigation: true,
      actions: [
        IconButton(
          icon: Stack(
            children: [
              const Icon(Icons.filter_list),
              if (_filters != null && _hasActiveFilters())
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          onPressed: () {
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
          },
          tooltip: 'Filtros',
        ),
        if (canCreate)
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              await Navigator.pushNamed(context, AppRoutes.documentCreate);
              if (mounted) _refreshAfterAction();
            },
            tooltip: 'Novo Documento',
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
              ),
          ],
        ),
      ],
      body: Column(
        children: [
          Container(
            color: ThemeHelpers.cardBackgroundColor(context),
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.primary.primary,
              unselectedLabelColor: ThemeHelpers.textSecondaryColor(context),
              indicatorColor: AppColors.primary.primary,
              dividerColor: Colors.transparent,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: const [
                Tab(icon: Icon(Icons.folder_outlined, size: 20), text: 'Todos'),
                Tab(icon: Icon(Icons.person_outline, size: 20), text: 'Meus'),
                Tab(icon: Icon(Icons.pending_outlined, size: 20), text: 'Pendentes'),
                Tab(icon: Icon(Icons.check_circle_outline, size: 20), text: 'Aprovados'),
              ],
            ),
          ),
          // Barra de busca
          _buildSearchBar(context, theme),
          
          // Conteúdo principal
          Expanded(
            child: _isLoading && _documents.isEmpty
                ? _buildSkeleton(context, theme)
                : _errorCause != null && _documents.isEmpty
                    ? _buildErrorState(context, theme)
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildDocumentsList(context, theme),
                          _buildDocumentsList(context, theme),
                          _buildDocumentsList(context, theme),
                          _buildDocumentsList(context, theme),
                        ],
                      ),
          ),
          if (_selecting) _buildBulkBar(context, theme),
        ],
      ),
    );
  }

  /// Barra de ações em lote (web: aprovar/recusar com `canApprove`, baixar
  /// com `canDownload`, excluir com `canDelete`).
  Widget _buildBulkBar(BuildContext context, ThemeData theme) {
    final n = _selectedIds.length;
    final canApprove = DocumentPermissions.canApprove;
    final canDownload = DocumentPermissions.canDownload;
    final canDelete = DocumentPermissions.canDelete;

    Widget action(
      IconData icon,
      String tooltip,
      VoidCallback? onTap, {
      Color? color,
    }) {
      return IconButton(
        tooltip: tooltip,
        onPressed: _bulkBusy ? null : onTap,
        icon: Icon(icon, color: color),
      );
    }

    return Container(
      padding: EdgeInsets.fromLTRB(
        8,
        6,
        8,
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
            icon: const Icon(Icons.close_rounded),
          ),
          Expanded(
            child: Text(
              _bulkBusy
                  ? 'Processando...'
                  : '$n selecionado${n > 1 ? 's' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: ThemeHelpers.textColor(context),
              ),
            ),
          ),
          if (canApprove) ...[
            action(
              Icons.check_circle_outline_rounded,
              'Aprovar',
              () => _bulkReview(true),
              color: AppColors.status.success,
            ),
            action(
              Icons.cancel_outlined,
              'Recusar',
              () => _bulkReview(false),
              color: AppColors.status.error,
            ),
          ],
          if (canDownload)
            action(Icons.download_outlined, 'Baixar', _bulkDownload),
          if (canDelete)
            action(
              Icons.delete_outline_rounded,
              'Excluir',
              _bulkDelete,
              color: AppColors.status.error,
            ),
        ],
      ),
    );
  }

  Widget _buildDocumentsList(BuildContext context, ThemeData theme) {
    return RefreshIndicator(
      onRefresh: () async {
        if (_tabController.index == 0) {
          await _loadDocuments(refresh: true);
        } else {
          await _loadDocumentsForCurrentTab();
        }
      },
      child: _documents.isEmpty
          ? _buildEmptyState(context, theme)
          : CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index >= _documents.length) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }
                        return _buildDocumentCard(
                          context,
                          theme,
                          _documents[index],
                        );
                      },
                      childCount: _documents.length + (_isLoadingMore ? 1 : 0),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSearchBar(BuildContext context, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border(
          bottom: BorderSide(
            color: ThemeHelpers.borderColor(context),
            width: 1,
          ),
        ),
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Buscar documentos...',
          prefixIcon: Icon(
            Icons.search,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                  onPressed: () {
                    _searchController.clear();
                    _handleSearch('');
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: ThemeHelpers.borderColor(context),
            ),
          ),
          filled: true,
          fillColor: ThemeHelpers.cardBackgroundColor(context),
        ),
        onChanged: (value) {
          _handleSearch(value);
        },
      ),
    );
  }

  Widget _buildSkeleton(BuildContext context, ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: List.generate(
          5,
          (index) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SkeletonBox(
              width: double.infinity,
              height: 100,
              borderRadius: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, ThemeData theme) {
    return AppErrorState(
      cause: _errorCause!,
      onRetry: () => _loadDocuments(refresh: true),
    );
  }

  Widget _buildEmptyState(BuildContext context, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.description_outlined,
              size: 64,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhum documento encontrado',
              style: theme.textTheme.titleLarge?.copyWith(
                color: ThemeHelpers.textColor(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Tente buscar com outros termos'
                  : 'Comece adicionando seu primeiro documento',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
            if (DocumentPermissions.canCreate) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () async {
                  await Navigator.pushNamed(context, AppRoutes.documentCreate);
                  if (mounted) _refreshAfterAction();
                },
                icon: const Icon(Icons.add),
                label: const Text('Novo Documento'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentCard(
    BuildContext context,
    ThemeData theme,
    Document document,
  ) {
    final selected = _selectedIds.contains(document.id);
    final busy = _busyDocumentId == document.id;
    final muted = ThemeHelpers.textSecondaryColor(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected
              ? AppColors.primary.primary
              : ThemeHelpers.borderLightColor(context),
          width: selected ? 1.5 : 1,
        ),
      ),
      color: selected
          ? AppColors.primary.primary.withValues(alpha: 0.06)
          : ThemeHelpers.cardBackgroundColor(context),
      child: InkWell(
        onTap: () {
          if (_selecting) {
            _toggleSelected(document);
          } else {
            _handleDocAction(_DocAction.view, document);
          }
        },
        onLongPress: () => _toggleSelected(document),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 4, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Ícone do tipo de arquivo (vira o check na seleção)
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary.primary
                      : AppColors.primary.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  selected
                      ? Icons.check_rounded
                      : _getFileIcon(document.fileExtension),
                  color: selected ? Colors.white : AppColors.primary.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              // Informações
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.title ?? document.originalName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: ThemeHelpers.textColor(context),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _pill(
                          theme,
                          document.type.label,
                          AppColors.primary.primary,
                        ),
                        _pill(
                          theme,
                          document.status.label,
                          _getStatusColor(document.status),
                        ),
                        if (document.signatures != null &&
                            document.signatures!.hasSignatures)
                          _pill(
                            theme,
                            '${document.signatures!.signed}/${document.signatures!.total} assinaturas',
                            document.signatures!.allSigned
                                ? AppColors.status.success
                                : AppColors.status.warning,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.file_present, size: 14, color: muted),
                        const SizedBox(width: 4),
                        Text(
                          _formatFileSize(document.fileSize),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                            fontSize: 12,
                          ),
                        ),
                        if (document.client != null) ...[
                          const SizedBox(width: 12),
                          Icon(Icons.person, size: 14, color: muted),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              document.client!.name,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: muted,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ] else if (document.property != null) ...[
                          const SizedBox(width: 12),
                          Icon(Icons.home_outlined, size: 14, color: muted),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              document.property!.title,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: muted,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (!_selecting)
                _buildItemMenu(document),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(ThemeData theme, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
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
            'Enviar p/ assinatura',
          ),
        if (canApprove && pending) ...[
          item(
            _DocAction.approve,
            Icons.check_circle_outline_rounded,
            'Aprovar',
            color: AppColors.status.success,
          ),
          item(
            _DocAction.reject,
            Icons.cancel_outlined,
            'Recusar',
            color: AppColors.status.error,
          ),
        ],
        if (canDelete)
          item(
            _DocAction.delete,
            Icons.delete_outline_rounded,
            'Excluir',
            color: AppColors.status.error,
          ),
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

  Color _getStatusColor(DocumentStatus status) {
    switch (status) {
      case DocumentStatus.active:
        return AppColors.status.success;
      case DocumentStatus.approved:
        return AppColors.status.success;
      case DocumentStatus.pendingReview:
        return AppColors.status.warning;
      case DocumentStatus.rejected:
        return AppColors.status.error;
      case DocumentStatus.archived:
        return AppColors.text.textSecondary;
      case DocumentStatus.deleted:
        return AppColors.status.error;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
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

