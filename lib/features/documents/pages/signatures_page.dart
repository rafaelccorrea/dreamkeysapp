import 'dart:async';

import 'package:flutter/material.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/utils/error_cause.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../services/document_service.dart';
import '../models/document_signature_model.dart';
import '../utils/document_file_actions.dart';
import '../utils/document_permissions.dart';
import '../widgets/document_access_locked.dart';
import '../widgets/document_signature_tile.dart';

/// Todas as assinaturas da empresa — paridade com `AllSignaturesPage.tsx`:
/// busca, filtro por status (os 6 do web), paginação de 20, e por
/// assinatura: abrir o documento, copiar o link, enviar e reenviar e-mail
/// (para aguardando, visualizado e expirado).
class SignaturesPage extends StatefulWidget {
  const SignaturesPage({super.key});

  @override
  State<SignaturesPage> createState() => _SignaturesPageState();
}

class _SignaturesPageState extends State<SignaturesPage> {
  static const int _limit = 20;

  final DocumentService _documentService = DocumentService.instance;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;

  List<DocumentSignature> _signatures = [];
  DocumentSignatureStatus? _status;
  int _page = 1;
  int _totalPages = 1;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  ErrorCause? _errorCause;
  int _requestSeq = 0;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    ModuleAccessService.instance.addListener(_onAccessChanged);
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    ModuleAccessService.instance.removeListener(_onAccessChanged);
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onAccessChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 240 &&
        !_loading &&
        !_loadingMore &&
        _page < _totalPages) {
      _load(append: true);
    }
  }

  Future<void> _load({bool append = false}) async {
    final seq = ++_requestSeq;
    final nextPage = append ? _page + 1 : 1;
    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        _loading = true;
        _errorCause = null;
      }
    });
    try {
      final res = await _documentService.getSignatures(
        status: _status,
        search: _searchController.text,
        page: nextPage,
        limit: _limit,
      );
      if (!mounted || seq != _requestSeq) return;
      if (res.success && res.data != null) {
        final data = res.data!;
        setState(() {
          _signatures = append ? [..._signatures, ...data.data] : data.data;
          _page = nextPage;
          _total = data.pagination?.totalItems ?? _signatures.length;
          _totalPages = data.pagination?.totalPages ?? 1;
          _loading = false;
          _loadingMore = false;
        });
      } else {
        setState(() {
          if (!append) {
            _errorCause = ErrorCause.fromApi(
              message: res.message,
              statusCode: res.statusCode,
            );
          }
          _loading = false;
          _loadingMore = false;
        });
      }
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        if (!append) _errorCause = ErrorCause.fromException(e);
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _load();
    });
    setState(() {});
  }

  void _setStatus(DocumentSignatureStatus? s) {
    if (_status == s) return;
    setState(() => _status = s);
    _load();
  }

  void _snack(String text, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: ok ? AppColors.status.success : AppColors.status.error,
      ),
    );
  }

  Future<void> _email(DocumentSignature s, {required bool resend}) async {
    if (s.documentId.isEmpty) return;
    setState(() => _busyId = s.id);
    final res = resend
        ? await _documentService.resendSignatureEmail(s.documentId, s.id)
        : await _documentService.sendSignatureEmail(s.documentId, s.id);
    if (!mounted) return;
    setState(() => _busyId = null);
    if (res.success) {
      _snack(
        resend ? 'Email reenviado com sucesso!' : 'Email enviado com sucesso!',
        ok: true,
      );
      _load();
    } else {
      _snack(resend ? 'Erro ao reenviar email' : 'Erro ao enviar email');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!DocumentPermissions.canOpenLibrary) {
      return const AppScaffold(
        title: 'Assinaturas',
        showBottomNavigation: false,
        body: DocumentAccessLocked(),
      );
    }
    final theme = Theme.of(context);
    return AppScaffold(
      title: 'Assinaturas',
      showBottomNavigation: false,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Buscar por signatário, e-mail ou documento',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpar busca',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _debounce?.cancel();
                          setState(() {});
                          _load();
                        },
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _statusChip(context, null, 'Todas'),
                for (final s in DocumentSignatureStatus.values)
                  _statusChip(context, s, s.label),
              ],
            ),
          ),
          if (!_loading && _errorCause == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '$_total assinatura${_total == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
              ),
            ),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _statusChip(
    BuildContext context,
    DocumentSignatureStatus? status,
    String label,
  ) {
    final selected = _status == status;
    final color = status == null
        ? AppColors.primary.primary
        : signatureStatusColor(context, status);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => _setStatus(status),
        showCheckmark: false,
        selectedColor: color.withValues(alpha: 0.16),
        labelStyle: TextStyle(
          color: selected ? color : ThemeHelpers.textColor(context),
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
        side: BorderSide(
          color: selected ? color : ThemeHelpers.borderColor(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _signatures.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        children: List.generate(
          6,
          (_) => const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: SkeletonBox(
              width: double.infinity,
              height: 72,
              borderRadius: 12,
            ),
          ),
        ),
      );
    }
    if (_errorCause != null && _signatures.isEmpty) {
      return AppErrorState(cause: _errorCause!, onRetry: () => _load());
    }
    return RefreshIndicator(
      color: AppColors.primary.primary,
      onRefresh: () => _load(),
      child: _signatures.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(32),
              children: [
                Icon(
                  Icons.draw_outlined,
                  size: 52,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
                const SizedBox(height: 12),
                Text(
                  'Nenhuma assinatura encontrada',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: ThemeHelpers.textColor(context),
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  _searchController.text.isNotEmpty || _status != null
                      ? 'Ajuste a busca ou o filtro de status.'
                      : 'As assinaturas aparecem aqui quando um documento é '
                          'enviado para assinatura.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                      ),
                ),
              ],
            )
          : ListView.separated(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: _signatures.length + (_loadingMore ? 1 : 0),
              separatorBuilder: (_, _) => Divider(
                height: 1,
                color: ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
              ),
              itemBuilder: (context, i) {
                if (i >= _signatures.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: SkeletonBox(
                      width: double.infinity,
                      height: 60,
                      borderRadius: 12,
                    ),
                  );
                }
                return _tile(_signatures[i]);
              },
            ),
    );
  }

  Widget _tile(DocumentSignature s) {
    final hasDoc = s.documentId.isNotEmpty;
    // Web: "Enviar Email" e "Reenviar" para aguardando, visualizado e
    // expirado; "Copiar link" sempre que houver URL. No app, "Abrir para
    // assinar" leva ao Autentique (fora do app) enquanto dá para assinar.
    final canEmail = hasDoc &&
        (s.status == DocumentSignatureStatus.pending ||
            s.status == DocumentSignatureStatus.viewed ||
            s.status == DocumentSignatureStatus.expired);
    final url = s.signatureUrl;
    final docTitle = (s.document?.title.isNotEmpty ?? false)
        ? s.document!.title
        : (s.document?.originalName.isNotEmpty ?? false)
            ? s.document!.originalName
            : 'Documento';
    return DocumentSignatureTile(
      signature: s,
      documentTitle: docTitle,
      busy: _busyId == s.id,
      onTap: hasDoc
          ? () => Navigator.pushNamed(
                context,
                AppRoutes.documentDetails(s.documentId),
              )
          : null,
      onOpenLink: (url != null && url.isNotEmpty && s.status.isSignable)
          ? () => DocumentFileActions.openSignatureLink(context, url)
          : null,
      onCopyLink: (url != null && url.isNotEmpty)
          ? () => DocumentFileActions.copyLink(
                context,
                url,
                message: 'Link copiado para a área de transferência!',
              )
          : null,
      onSendEmail: canEmail ? () => _email(s, resend: false) : null,
      onResendEmail: canEmail ? () => _email(s, resend: true) : null,
    );
  }
}
