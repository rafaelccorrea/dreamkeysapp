import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
///
/// Leitura da tela: abas de status com sublinhado; a busca rola junto com a
/// lista; a manchete diz quantas há no recorte e o que fazer com elas; as
/// assinaturas seguidas do mesmo documento ficam sob o cabeçalho dele (que
/// abre o documento), cada uma com a trilha enviado → visto → assinado.
class SignaturesPage extends StatefulWidget {
  const SignaturesPage({super.key});

  @override
  State<SignaturesPage> createState() => _SignaturesPageState();
}

class _SignaturesPageState extends State<SignaturesPage>
    with SingleTickerProviderStateMixin {
  static const int _limit = 20;
  static final NumberFormat _numero = NumberFormat.decimalPattern('pt_BR');

  final DocumentService _documentService = DocumentService.instance;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final TabController _tabs;
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
    _tabs = TabController(
      length: DocumentSignatureStatus.values.length + 1,
      vsync: this,
    );
    ModuleAccessService.instance.addListener(_onAccessChanged);
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    ModuleAccessService.instance.removeListener(_onAccessChanged);
    _debounce?.cancel();
    _tabs.dispose();
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

  /// "Ver todas" do vazio filtrado: limpa a busca e volta para a aba Todas.
  void _limparFiltros() {
    _debounce?.cancel();
    _searchController.clear();
    _tabs.index = 0;
    setState(() => _status = null);
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

  // ─── Textos do recorte ────────────────────────────────────────────────

  static String _tabLabel(DocumentSignatureStatus s) => switch (s) {
        DocumentSignatureStatus.pending => 'Aguardando',
        DocumentSignatureStatus.viewed => 'Visualizadas',
        DocumentSignatureStatus.signed => 'Assinadas',
        DocumentSignatureStatus.rejected => 'Rejeitadas',
        DocumentSignatureStatus.expired => 'Expiradas',
        DocumentSignatureStatus.cancelled => 'Canceladas',
      };

  /// O que vem depois do número na manchete ("12 aguardando assinatura").
  String _manchete(int n) {
    final um = n == 1;
    return switch (_status) {
      null => um ? 'assinatura enviada' : 'assinaturas enviadas',
      DocumentSignatureStatus.pending => 'aguardando assinatura',
      DocumentSignatureStatus.viewed => um
          ? 'abriu o link e ainda não assinou'
          : 'abriram o link e ainda não assinaram',
      DocumentSignatureStatus.signed => um ? 'assinada' : 'assinadas',
      DocumentSignatureStatus.rejected =>
        um ? 'rejeitada pelo signatário' : 'rejeitadas pelos signatários',
      DocumentSignatureStatus.expired =>
        um ? 'expirou sem assinatura' : 'expiraram sem assinatura',
      DocumentSignatureStatus.cancelled => um ? 'cancelada' : 'canceladas',
    };
  }

  /// O que fazer com o recorte, em uma frase.
  String _dica() => switch (_status) {
        null => 'Da mais recente para a mais antiga, agrupadas por '
            'documento. Toque no documento para abri-lo.',
        DocumentSignatureStatus.pending => 'Esperando o signatário. Cobre '
            'por e-mail ou copie o link para mandar por outro canal.',
        DocumentSignatureStatus.viewed => 'Já viram o documento e falta '
            'assinar. Dá para mandar um lembrete por e-mail na própria linha.',
        DocumentSignatureStatus.signed =>
          'Concluídas. Toque no documento para abri-lo.',
        DocumentSignatureStatus.rejected => 'Quando o signatário informa o '
            'motivo da recusa, ele aparece na linha.',
        DocumentSignatureStatus.expired => 'O prazo acabou antes da '
            'assinatura. O e-mail ainda pode ser enviado de novo pela linha.',
        DocumentSignatureStatus.cancelled =>
          'Canceladas não podem mais ser assinadas.',
      };

  String _docTitle(DocumentSignature s) {
    final d = s.document;
    if (d != null && d.title.trim().isNotEmpty) return d.title.trim();
    if (d != null && d.originalName.trim().isNotEmpty) {
      return d.originalName.trim();
    }
    return 'Documento';
  }

  /// "3 signatários · 1 assinou · 2 faltam" — só com o que está carregado.
  String _resumoGrupo(List<DocumentSignature> grupo) {
    final n = grupo.length;
    final base = '$n ${n == 1 ? 'signatário' : 'signatários'}';
    if (_status != null) return base;
    final assinaram =
        grupo.where((s) => s.status == DocumentSignatureStatus.signed).length;
    final rejeitaram =
        grupo.where((s) => s.status == DocumentSignatureStatus.rejected).length;
    final faltam = grupo.where((s) => s.status.isSignable).length;
    return [
      base,
      if (assinaram > 0)
        '$assinaram ${assinaram == 1 ? 'assinou' : 'assinaram'}',
      if (rejeitaram > 0)
        '$rejeitaram ${rejeitaram == 1 ? 'rejeitou' : 'rejeitaram'}',
      if (faltam > 0) '$faltam ${faltam == 1 ? 'falta' : 'faltam'}',
    ].join(' · ');
  }

  /// Agrupa assinaturas SEGUIDAS do mesmo documento — a ordem continua a do
  /// back (mais recentes primeiro). Só apresentação.
  List<_Linha> _linhas() {
    final out = <_Linha>[];
    var i = 0;
    while (i < _signatures.length) {
      final docId = _signatures[i].documentId;
      var j = i + 1;
      while (j < _signatures.length && _signatures[j].documentId == docId) {
        j++;
      }
      final grupo = _signatures.sublist(i, j);
      out.add(_Linha.cabecalho(grupo.first, grupo));
      for (var k = 0; k < grupo.length; k++) {
        out.add(_Linha.assinatura(grupo[k], primeiraDoGrupo: k == 0));
      }
      i = j;
    }
    return out;
  }

  /// Assinatura de mentira do exemplo no vazio ("assim aparece").
  static DocumentSignature _exemplo() {
    final agora = DateTime.now();
    return DocumentSignature(
      id: '',
      documentId: '',
      companyId: '',
      status: DocumentSignatureStatus.viewed,
      signerName: 'Nome do signatário',
      signerEmail: 'email@exemplo.com',
      createdAt: agora.subtract(const Duration(days: 1)),
      updatedAt: agora,
      viewedAt: agora.subtract(const Duration(hours: 2)),
      expiresAt: agora.add(const Duration(days: 6)),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!DocumentPermissions.canOpenLibrary) {
      return const AppScaffold(
        title: 'Assinaturas',
        showBottomNavigation: false,
        body: DocumentAccessLocked(),
      );
    }
    return AppScaffold(
      title: 'Assinaturas',
      showBottomNavigation: false,
      body: LayoutBuilder(
        builder: (context, c) {
          // Tela baixa (paisagem com o teclado aberto): as abas saem e a
          // busca fica com a altura toda. O Expanded segue sendo o mesmo
          // elemento, então o campo em edição não perde o foco.
          final compacta = c.maxHeight < 220;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 840),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!compacta) _buildTabs(context),
                  Expanded(child: _buildBody(context)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTabs(BuildContext context) {
    final accent = _status == null
        ? AppColors.primary.primary
        : signatureStatusColor(context, _status!);
    final recarregando = _loading && _signatures.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: ThemeHelpers.textColor(context),
          unselectedLabelColor: ThemeHelpers.textSecondaryColor(context),
          labelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          indicatorColor: accent,
          indicatorWeight: 2.5,
          dividerColor: Colors.transparent,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          onTap: (i) {
            _setStatus(i == 0 ? null : DocumentSignatureStatus.values[i - 1]);
            if (_scrollController.hasClients) _scrollController.jumpTo(0);
          },
          tabs: [
            const Tab(text: 'Todas'),
            for (final s in DocumentSignatureStatus.values)
              Tab(text: _tabLabel(s)),
          ],
        ),
        // Filete das abas; vira barra de progresso enquanto o recorte novo
        // chega (a lista anterior segue na tela até lá).
        SizedBox(
          height: 2,
          child: recarregando
              ? LinearProgressIndicator(
                  minHeight: 2,
                  color: accent,
                  backgroundColor: Colors.transparent,
                )
              : Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    height: 1,
                    color: ThemeHelpers.borderColor(context),
                  ),
                ),
        ),
      ],
    );
  }

  /// Uma rolagem só para todos os estados: a busca (primeiro sliver) nunca
  /// é desmontada, então digitar não derruba o teclado quando a lista troca
  /// de carregando para vazio e vice-versa.
  Widget _buildBody(BuildContext context) {
    final vazio = _signatures.isEmpty;
    final linhas = vazio ? const <_Linha>[] : _linhas();
    return RefreshIndicator(
      color: AppColors.primary.primary,
      onRefresh: () => _load(),
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(child: _buildSearch(context)),
          if (_loading && vazio)
            SliverToBoxAdapter(child: _buildSkeleton())
          else if (_errorCause != null && vazio)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                child: AppErrorState(
                  cause: _errorCause!,
                  onRetry: () => _load(),
                  dense: true,
                ),
              ),
            )
          else if (vazio)
            SliverToBoxAdapter(child: _buildEmpty(context))
          else ...[
            if (_errorCause != null)
              SliverToBoxAdapter(child: _buildAvisoFalha(context)),
            SliverToBoxAdapter(child: _buildHeadline(context)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _buildLinha(context, linhas[i], i == 0),
                  childCount: linhas.length,
                ),
              ),
            ),
            SliverToBoxAdapter(child: _buildFooter(context)),
          ],
        ],
      ),
    );
  }

  Widget _buildSearch(BuildContext context) {
    return Padding(
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
    );
  }

  /// Manchete do recorte: o número que importa + o que ele quer dizer + o
  /// próximo passo. Não é hero — é a resposta de quem abre a tela.
  Widget _buildHeadline(BuildContext context) {
    final theme = Theme.of(context);
    final texto = ThemeHelpers.textColor(context);
    final busca = _searchController.text.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _numero.format(_total),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  color: texto,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _manchete(_total),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: texto,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            busca.isEmpty ? _dica() : 'Busca por “$busca”. ${_dica()}',
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  /// A atualização falhou mas a lista anterior segue na tela: avisa a causa
  /// sem tirar o que já dá para ler.
  Widget _buildAvisoFalha(BuildContext context) {
    final c = _errorCause!;
    final texto = ThemeHelpers.textColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        decoration: BoxDecoration(
          color: c.tone.withValues(alpha: isDark ? 0.14 : 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(c.icon, size: 18, color: c.tone),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${c.title}. A lista abaixo pode estar desatualizada.',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: texto,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            if (c.retryable)
              TextButton(
                onPressed: () => _load(),
                style: TextButton.styleFrom(
                  foregroundColor: texto,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Tentar de novo'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinha(BuildContext context, _Linha l, bool primeira) {
    final grupo = l.grupo;
    if (grupo != null) {
      return _buildDocHeader(context, l.assinatura, grupo, primeira);
    }
    if (l.primeiraDoGrupo) return _tile(l.assinatura);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(
          height: 1,
          thickness: 1,
          color: ThemeHelpers.borderLightColor(context),
        ),
        _tile(l.assinatura),
      ],
    );
  }

  /// Cabeçalho do documento: filete forte entre documentos (o fraco fica
  /// entre signatários do mesmo documento), título e o placar do grupo.
  Widget _buildDocHeader(
    BuildContext context,
    DocumentSignature first,
    List<DocumentSignature> grupo,
    bool primeiro,
  ) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final hasDoc = first.documentId.isNotEmpty;
    return Container(
      margin: EdgeInsets.only(top: primeiro ? 0 : 10),
      decoration: primeiro
          ? null
          : BoxDecoration(
              border: Border(
                top: BorderSide(color: ThemeHelpers.borderColor(context)),
              ),
            ),
      child: InkWell(
        onTap: hasDoc
            ? () => Navigator.pushNamed(
                  context,
                  AppRoutes.documentDetails(first.documentId),
                )
            : null,
        child: Padding(
          padding: EdgeInsets.only(top: primeiro ? 4 : 14, bottom: 2),
          child: Row(
            children: [
              Icon(Icons.description_outlined, size: 18, color: muted),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _docTitle(first),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _resumoGrupo(grupo),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasDoc) ...[
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, size: 20, color: muted),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Fim da lista: carregando a próxima página (esqueleto de uma linha) ou
  /// "Carregar mais", como no web. A folga de baixo deixa a última linha
  /// sair de baixo do botão flutuante do chat.
  Widget _buildFooter(BuildContext context) {
    final restam = _page < _totalPages;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      child: _loadingMore
          ? _skeletonLinha()
          : !restam
              ? const SizedBox.shrink()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: ThemeHelpers.borderLightColor(context),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Mostrando ${_signatures.length} de '
                      '${_numero.format(_total)}',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: OutlinedButton.icon(
                        onPressed: _loading
                            ? null
                            : () => _load(append: true),
                        icon: const Icon(Icons.expand_more_rounded, size: 18),
                        label: const Text(
                          'Carregar mais',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ThemeHelpers.textColor(context),
                          side: BorderSide(
                            color: ThemeHelpers.borderColor(context),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  /// Esqueleto fiel: manchete + dois documentos com duas linhas cada.
  Widget _buildSkeleton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              SkeletonBox(width: 44, height: 26, borderRadius: 8),
              SizedBox(width: 10),
              SkeletonText(width: 150, height: 16),
            ],
          ),
          const SizedBox(height: 8),
          const SkeletonText(width: double.infinity, height: 12),
          const SizedBox(height: 22),
          for (var g = 0; g < 2; g++) ...[
            const SkeletonText(width: 190, height: 15),
            const SizedBox(height: 6),
            const SkeletonText(width: 120, height: 11),
            _skeletonLinha(),
            _skeletonLinha(),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _skeletonLinha() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SkeletonBox(width: 38, height: 38, borderRadius: 19),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonText(width: 140, height: 14),
                    SizedBox(height: 6),
                    SkeletonText(width: 180, height: 11),
                  ],
                ),
              ),
              SizedBox(width: 8),
              SkeletonBox(width: 76, height: 22, borderRadius: 999),
            ],
          ),
          SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: SkeletonText(height: 10)),
              SizedBox(width: 16),
              Expanded(child: SkeletonText(height: 10)),
              SizedBox(width: 16),
              Expanded(child: SkeletonText(height: 10)),
            ],
          ),
        ],
      ),
    );
  }

  /// Vazio que ensina: sem filtro, diz como uma assinatura chega aqui e
  /// mostra um exemplo apagado da linha; com filtro, oferece voltar a Todas.
  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    final texto = ThemeHelpers.textColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final busca = _searchController.text.trim();
    final filtrando = busca.isNotEmpty || _status != null;
    final onde = [
      if (_status != null) 'em “${_tabLabel(_status!)}”',
      if (busca.isNotEmpty) 'com “$busca”',
    ].join(' ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 96),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: texto.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              filtrando ? Icons.filter_alt_off_outlined : Icons.draw_outlined,
              size: 26,
              color: muted,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            filtrando
                ? 'Nada neste recorte'
                : 'Nenhuma assinatura enviada ainda',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: texto,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            filtrando
                ? 'Nenhuma assinatura $onde. Limpe a busca ou volte para '
                    '“Todas”.'
                : 'Para pedir uma assinatura, abra o documento em Documentos '
                    'e toque em “Enviar p/ assinatura”. Cada signatário '
                    'aparece aqui com o andamento: enviado, visto e assinado.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: muted,
              height: 1.4,
            ),
          ),
          if (filtrando) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _limparFiltros,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Ver todas'),
              style: OutlinedButton.styleFrom(
                foregroundColor: texto,
                side: BorderSide(color: ThemeHelpers.borderColor(context)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'ASSIM APARECE CADA SIGNATÁRIO',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 2),
            IgnorePointer(
              child: Opacity(
                opacity: 0.55,
                child: DocumentSignatureTile(signature: _exemplo()),
              ),
            ),
          ],
        ],
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
    // O nome do documento sai no cabeçalho do grupo, não em cada linha.
    return DocumentSignatureTile(
      signature: s,
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

/// Uma linha da lista: o cabeçalho de um documento ou uma assinatura dele.
class _Linha {
  final DocumentSignature assinatura;

  /// Não nulo = cabeçalho do grupo (assinaturas seguidas do documento).
  final List<DocumentSignature>? grupo;
  final bool primeiraDoGrupo;

  const _Linha.cabecalho(this.assinatura, this.grupo)
      : primeiraDoGrupo = false;

  const _Linha.assinatura(this.assinatura, {required this.primeiraDoGrupo})
      : grupo = null;
}
