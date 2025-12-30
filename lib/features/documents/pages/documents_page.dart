import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../core/routes/app_routes.dart';
import '../services/document_service.dart';
import '../models/document_model.dart';
import '../widgets/document_filters_drawer.dart';
import '../widgets/upload_tokens_modal.dart';

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
  String? _errorMessage;
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadDocuments();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    _loadDocumentsForCurrentTab(force: true);
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
      _errorMessage = null;
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
            _isLoading = false;
            _isLoadingMore = false;
          });
          // Atualizar lista exibida baseada na tab atual
          if (_tabController.index == 0) {
            _documents = _allDocuments;
          }
        } else {
          setState(() {
            _errorMessage = response.message ?? 'Erro ao carregar documentos';
            _isLoading = false;
            _isLoadingMore = false;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ [DOCUMENTS_PAGE] Erro: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Erro ao conectar com o servidor';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Documentos',
      showBottomNavigation: true,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          color: ThemeHelpers.cardBackgroundColor(context),
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.primary.primary,
            unselectedLabelColor: ThemeHelpers.textSecondaryColor(context),
            indicatorColor: AppColors.primary.primary,
            dividerColor: Colors.transparent,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(icon: Icon(Icons.folder_outlined, size: 20), text: 'Todos'),
              Tab(icon: Icon(Icons.person_outline, size: 20), text: 'Meus'),
              Tab(icon: Icon(Icons.pending_outlined, size: 20), text: 'Pendentes'),
              Tab(icon: Icon(Icons.check_circle_outline, size: 20), text: 'Aprovados'),
            ],
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.link),
          onPressed: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              backgroundColor: Colors.transparent,
              builder: (context) => const UploadTokensModal(),
            );
          },
          tooltip: 'Links Públicos',
        ),
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
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: () {
            Navigator.pushNamed(context, AppRoutes.documentCreate);
          },
          tooltip: 'Novo Documento',
        ),
      ],
      body: Column(
        children: [
          // Barra de busca
          _buildSearchBar(context, theme),
          
          // Conteúdo principal
          Expanded(
            child: _isLoading && _documents.isEmpty
                ? _buildSkeleton(context, theme)
                : _errorMessage != null && _documents.isEmpty
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: AppColors.status.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Erro ao carregar documentos',
              style: theme.textTheme.titleLarge?.copyWith(
                color: ThemeHelpers.textColor(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Erro desconhecido',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _loadDocuments(refresh: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar Novamente'),
            ),
          ],
        ),
      ),
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
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pushNamed(context, AppRoutes.documentCreate);
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
        ),
      ),
    );
  }

  Widget _buildDocumentCard(
    BuildContext context,
    ThemeData theme,
    Document document,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: ThemeHelpers.borderLightColor(context),
          width: 1,
        ),
      ),
      color: ThemeHelpers.cardBackgroundColor(context),
      child: InkWell(
        onTap: () {
          Navigator.pushNamed(
            context,
            AppRoutes.documentDetails(document.id),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Ícone do tipo de arquivo
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getFileIcon(document.fileExtension),
                  color: AppColors.primary.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              // Informações
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Título ou nome
                    Text(
                      document.title ?? document.originalName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: ThemeHelpers.textColor(context),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Tipo e Status
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            document.type.label,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.primary.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _getStatusColor(document.status)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            document.status.label,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: _getStatusColor(document.status),
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Informações adicionais
                    Row(
                      children: [
                        Icon(
                          Icons.file_present,
                          size: 14,
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatFileSize(document.fileSize),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                            fontSize: 12,
                          ),
                        ),
                        if (document.client != null) ...[
                          const SizedBox(width: 12),
                          Icon(
                            Icons.person,
                            size: 14,
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              document.client!.name,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: ThemeHelpers.textSecondaryColor(context),
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
              // Botões de ação
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.download_outlined),
                    onPressed: () => _downloadDocument(context, document),
                    tooltip: 'Baixar',
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right,
                    color: ThemeHelpers.textSecondaryColor(context),
                    size: 24,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _downloadDocument(BuildContext context, Document document) async {
    try {
      final url = Uri.parse(document.fileUrl);
      
      // Verifica se a URL pode ser lançada
      final canLaunch = await canLaunchUrl(url);
      
      if (!canLaunch) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Não foi possível abrir o documento: ${document.originalName}'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
        return;
      }

      // Tenta abrir no navegador/externo
      final launched = await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );

      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível abrir o documento: ${document.originalName}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ [DOCUMENTS_PAGE] Erro ao baixar documento: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao abrir documento: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    }
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

