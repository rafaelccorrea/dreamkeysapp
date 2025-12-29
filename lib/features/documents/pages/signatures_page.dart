import 'package:flutter/material.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../services/document_service.dart';
import '../models/document_signature_model.dart';

/// Página de listagem de assinaturas
class SignaturesPage extends StatefulWidget {
  const SignaturesPage({super.key});

  @override
  State<SignaturesPage> createState() => _SignaturesPageState();
}

class _SignaturesPageState extends State<SignaturesPage>
    with SingleTickerProviderStateMixin {
  final DocumentService _documentService = DocumentService.instance;
  late TabController _tabController;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  List<DocumentSignature> _signatures = [];
  int _currentPage = 1;
  int _totalPages = 1;
  String? _errorMessage;
  final ScrollController _scrollController = ScrollController();
  
  // Assinaturas por tab
  List<DocumentSignature> _allSignatures = [];
  List<DocumentSignature> _pendingSignatures = [];
  List<DocumentSignature> _signedSignatures = [];
  List<DocumentSignature> _rejectedSignatures = [];
  
  // Estado de carregamento por tab
  bool _isLoadingPending = false;
  bool _isLoadingSigned = false;
  bool _isLoadingRejected = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadSignatures();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    _loadSignaturesForCurrentTab();
  }

  Future<void> _loadSignaturesForCurrentTab() async {
    switch (_tabController.index) {
      case 0: // Todas
        _signatures = _allSignatures;
        break;
      case 1: // Pendentes
        if (_pendingSignatures.isEmpty && !_isLoadingPending) {
          await _loadPendingSignatures();
        } else {
          _signatures = _pendingSignatures;
        }
        break;
      case 2: // Assinadas
        if (_signedSignatures.isEmpty && !_isLoadingSigned) {
          await _loadSignedSignatures();
        } else {
          _signatures = _signedSignatures;
        }
        break;
      case 3: // Rejeitadas
        if (_rejectedSignatures.isEmpty && !_isLoadingRejected) {
          await _loadRejectedSignatures();
        } else {
          _signatures = _rejectedSignatures;
        }
        break;
    }
  }

  Future<void> _loadPendingSignatures() async {
    setState(() => _isLoadingPending = true);

    try {
      final response = await _documentService.getPendingSignatures(
        page: 1,
        limit: 100,
      );

      if (mounted && response.success && response.data != null) {
        setState(() {
          _pendingSignatures = response.data!.data;
          _signatures = _pendingSignatures;
          _isLoadingPending = false;
        });
      } else {
        setState(() => _isLoadingPending = false);
      }
    } catch (e) {
      debugPrint('❌ [SIGNATURES_PAGE] Erro ao carregar assinaturas pendentes: $e');
      if (mounted) {
        setState(() => _isLoadingPending = false);
      }
    }
  }

  Future<void> _loadSignedSignatures() async {
    setState(() => _isLoadingSigned = true);

    try {
      final response = await _documentService.getSignatures(
        status: DocumentSignatureStatus.signed,
        page: 1,
        limit: 100,
      );

      if (mounted && response.success && response.data != null) {
        setState(() {
          _signedSignatures = response.data!.data;
          _signatures = _signedSignatures;
          _isLoadingSigned = false;
        });
      } else {
        setState(() => _isLoadingSigned = false);
      }
    } catch (e) {
      debugPrint('❌ [SIGNATURES_PAGE] Erro ao carregar assinaturas assinadas: $e');
      if (mounted) {
        setState(() => _isLoadingSigned = false);
      }
    }
  }

  Future<void> _loadRejectedSignatures() async {
    setState(() => _isLoadingRejected = true);

    try {
      final response = await _documentService.getSignatures(
        status: DocumentSignatureStatus.rejected,
        page: 1,
        limit: 100,
      );

      if (mounted && response.success && response.data != null) {
        setState(() {
          _rejectedSignatures = response.data!.data;
          _signatures = _rejectedSignatures;
          _isLoadingRejected = false;
        });
      } else {
        setState(() => _isLoadingRejected = false);
      }
    } catch (e) {
      debugPrint('❌ [SIGNATURES_PAGE] Erro ao carregar assinaturas rejeitadas: $e');
      if (mounted) {
        setState(() => _isLoadingRejected = false);
      }
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _currentPage < _totalPages) {
        _loadMoreSignatures();
      }
    }
  }

  Future<void> _loadSignatures({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _currentPage = 1;
        _allSignatures.clear();
      });
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _documentService.getSignatures(
        page: _currentPage,
        limit: 20,
      );

      if (mounted) {
        if (response.success && response.data != null) {
          final signatures = response.data!.data;
          setState(() {
            if (refresh) {
              _allSignatures = signatures;
            } else {
              _allSignatures.addAll(signatures);
            }
            _totalPages = response.data!.pagination?.totalPages ?? 1;
            _isLoading = false;
            _isLoadingMore = false;
          });
          if (_tabController.index == 0) {
            _signatures = _allSignatures;
          }
        } else {
          setState(() {
            _errorMessage = response.message ?? 'Erro ao carregar assinaturas';
            _isLoading = false;
            _isLoadingMore = false;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ [SIGNATURES_PAGE] Erro: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Erro ao conectar com o servidor';
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMoreSignatures() async {
    if (_isLoadingMore || _currentPage >= _totalPages) return;

    setState(() {
      _isLoadingMore = true;
      _currentPage++;
    });

    await _loadSignatures();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Assinaturas',
      showBottomNavigation: true,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Material(
          color: ThemeHelpers.cardBackgroundColor(context),
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.primary.primary,
            unselectedLabelColor: ThemeHelpers.textSecondaryColor(context),
            indicatorColor: AppColors.primary.primary,
            dividerColor: Colors.transparent,
            overlayColor: WidgetStateProperty.all(Colors.transparent),
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(icon: Icon(Icons.description_outlined, size: 20), text: 'Todas'),
              Tab(icon: Icon(Icons.pending_outlined, size: 20), text: 'Pendentes'),
              Tab(icon: Icon(Icons.check_circle_outline, size: 20), text: 'Assinadas'),
              Tab(icon: Icon(Icons.cancel_outlined, size: 20), text: 'Rejeitadas'),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          // Conteúdo principal
          Expanded(
            child: _isLoading && _signatures.isEmpty
                ? _buildSkeleton(context, theme)
                : _errorMessage != null && _signatures.isEmpty
                    ? _buildErrorState(context, theme)
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildSignaturesList(context, theme),
                          _buildSignaturesList(context, theme),
                          _buildSignaturesList(context, theme),
                          _buildSignaturesList(context, theme),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignaturesList(BuildContext context, ThemeData theme) {
    return RefreshIndicator(
      onRefresh: () async {
        if (_tabController.index == 0) {
          await _loadSignatures(refresh: true);
        } else {
          await _loadSignaturesForCurrentTab();
        }
      },
      child: _signatures.isEmpty
          ? _buildEmptyState(context, theme)
          : CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index >= _signatures.length) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }
                        return _buildSignatureCard(
                          context,
                          theme,
                          _signatures[index],
                        );
                      },
                      childCount: _signatures.length + (_isLoadingMore ? 1 : 0),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSignatureCard(
    BuildContext context,
    ThemeData theme,
    DocumentSignature signature,
  ) {
    Color statusColor;
    IconData statusIcon;
    
    switch (signature.status) {
      case DocumentSignatureStatus.pending:
        statusColor = Colors.orange;
        statusIcon = Icons.pending_outlined;
        break;
      case DocumentSignatureStatus.viewed:
        statusColor = Colors.blue;
        statusIcon = Icons.visibility_outlined;
        break;
      case DocumentSignatureStatus.signed:
        statusColor = AppColors.status.success;
        statusIcon = Icons.check_circle_outlined;
        break;
      case DocumentSignatureStatus.rejected:
        statusColor = AppColors.status.error;
        statusIcon = Icons.cancel_outlined;
        break;
      case DocumentSignatureStatus.expired:
        statusColor = Colors.grey;
        statusIcon = Icons.access_time_outlined;
        break;
      case DocumentSignatureStatus.cancelled:
        statusColor = Colors.grey;
        statusIcon = Icons.block_outlined;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: ThemeHelpers.borderLightColor(context),
        ),
      ),
      child: InkWell(
        onTap: () {
          // TODO: Navegar para detalhes da assinatura
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      statusIcon,
                      color: statusColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          signature.document?.title ?? signature.document?.originalName ?? 'Documento',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          signature.signerName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      signature.status.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (signature.signerEmail.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.email_outlined,
                      size: 16,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        signature.signerEmail,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
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
              'Erro ao carregar assinaturas',
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
              onPressed: () => _loadSignatures(refresh: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
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
              'Nenhuma assinatura encontrada',
              style: theme.textTheme.titleLarge?.copyWith(
                color: ThemeHelpers.textColor(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'As assinaturas aparecerão aqui quando forem criadas',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

