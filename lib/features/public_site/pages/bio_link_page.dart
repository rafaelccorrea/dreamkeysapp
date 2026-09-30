import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/bio_page_model.dart';
import '../public_site_access.dart';
import '../services/bio_page_service.dart';
import '../widgets/bio_link_edit_sheet.dart';
import '../widgets/public_site_shared.dart';

enum _BioTab { profile, links, analytics }

/// Tela **Link in Bio** — o topo responde de cara às quatro perguntas de
/// quem abre: a página está no ar? em qual endereço? quantos links aparecem?
/// o que o visitante vê? À esquerda, a prévia do celular (com o rascunho ao
/// vivo, nas cores que o cliente escolheu para os botões); ao lado, o estado
/// (No ar / Rascunho, com "Publicar" à mão), a contagem de links e, embaixo,
/// o endereço com Copiar / Abrir / Compartilhar. Abaixo, edição em abas com
/// sublinhado, listas flush e ações no próprio item.
///
/// Revisão 30/09/2026: o acento da tela INTEIRA é o violeta (token
/// `status.purple`, identidade de "bio/criador") — a paleta por aba
/// (azul/rosa/violeta) virou arco-íris e saiu. Verde = no ar / confirmar,
/// âmbar = rascunho / não salvo, vermelho só no confirmar destrutivo. Cores
/// escolhidas pelo cliente (botões da bio) são DADO: aparecem como ele
/// configurou, com texto legível por [siteOnColor]. Coluna de até
/// [_kMaxContent] no tablet; barra de salvar presa embaixo quando há altura.
///
/// Paridade com `BioLinkConfigPage.tsx` (as etapas viáveis em mobile —
/// templates/customização Premium ficam no painel web; devolvemos
/// `customization` intacta para não apagar nada).
class BioLinkPage extends StatefulWidget {
  const BioLinkPage({super.key});

  @override
  State<BioLinkPage> createState() => _BioLinkPageState();
}

class _BioLinkPageState extends State<BioLinkPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;

  /// Folga no fim da rolagem: a bolha do chat fica 80dp acima da borda e
  /// tem 56 de altura — com 88, ela cobria o "Salvar" no fim do painel.
  static const double _kPagePadBottom = 148;
  static const double _kSectionGap = 12;

  /// Largura máxima da coluna (tablet / paisagem larga).
  static const double _kMaxContent = 720;

  /// Altura útil (tela menos teclado) a partir da qual a barra de salvar
  /// fica presa embaixo. Abaixo disso (paisagem, teclado aberto) ela volta
  /// para o fim do painel e não come a área de edição.
  static const double _kDockMinHeight = 560;

  static const List<int> _kAnalyticsPeriods = [7, 30, 90];

  _BioTab _activeTab = _BioTab.links;

  BioPageConfig? _page;
  bool _loading = true;
  String? _error;
  // Guardado junto da mensagem: sem o código HTTP não dá para distinguir
  // "sem permissão" de "servidor fora do ar".
  int _errorStatus = 0;

  // Publicação
  bool _publishing = false;

  // Perfil (rascunho local + dirty)
  final _titleController = TextEditingController();
  final _instagramController = TextEditingController();
  final _bioController = TextEditingController();
  bool _profileDirty = false;
  bool _profileSaving = false;

  // Slug (URL pública)
  final _slugController = TextEditingController();
  Timer? _slugDebounce;
  bool? _slugAvailable;
  bool _slugChecking = false;
  bool _slugSaving = false;

  // Links (rascunho local + dirty)
  List<BioPageLink> _linksDraft = const [];
  bool _linksDirty = false;
  bool _linksSaving = false;

  // Analytics
  BioPageAnalytics? _analytics;
  bool _analyticsLoading = false;
  bool _analyticsLoaded = false;
  int _analyticsDays = 30;
  // Falha ao carregar as métricas — antes ela aparecia como "Sem métricas
  // ainda" (erro pintado de vazio). Agora vira estado de erro com a causa e
  // "Tentar de novo".
  String? _analyticsError;
  int _analyticsErrorStatus = 0;

  bool get _canView =>
      ModuleAccessService.instance.hasPermission(PublicSiteAccess.permView);

  bool get _canManage =>
      ModuleAccessService.instance.hasPermission(PublicSiteAccess.permManage);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _slugDebounce?.cancel();
    _titleController.dispose();
    _instagramController.dispose();
    _bioController.dispose();
    _slugController.dispose();
    super.dispose();
  }

  // ─── Cores ────────────────────────────────────────────────────────────────
  //
  // O acento desta tela INTEIRA é o violeta — identidade de "bio/criador".
  // O vermelho da marca não entra aqui: ele ficou reservado ao botão
  // confirmar dos diálogos destrutivos e ao erro de endereço já em uso.
  // Assim, violeta (identidade) + verde (no ar / confirmar) + âmbar
  // (rascunho / não salvo) convivem sem nunca encostar verde em vermelho.
  // Texto e ícone pequenos passam por [siteInk] (contraste AA no claro);
  // fundo cheio com rótulo branco, por [siteSolid].

  /// Cor identitária da tela (violeta de "bio/criador") — a mesma em todas
  /// as abas, no hero, nos campos e na folha de edição.
  Color _identity(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.status.purpleDarkMode
        : AppColors.status.purple;
  }

  Color _green(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? AppColors.status.greenDarkMode
      : AppColors.status.green;

  Color _amber(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? AppColors.status.warningDarkMode
      : AppColors.status.warning;

  Color _red(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? AppColors.status.errorDarkMode
      : AppColors.status.error;

  /// Tinta do hero — a cor custom da própria bio quando existir (primeiro
  /// link ativo com cor definida); caso contrário, o violeta da tela.
  Color _heroTint(BuildContext context) {
    for (final link in _linksDraft) {
      if (!link.isActive) continue;
      final custom = siteParseHexColor(link.color);
      if (custom != null) return custom;
    }
    return _identity(context);
  }

  // ─── Dados ────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _errorStatus = 0;
    });
    final res = await BioPageService.instance.getPage();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _applyPage(res.data!, resetDrafts: true);
      } else {
        _error = res.message ?? 'Erro ao carregar a página Link in Bio';
        _errorStatus = res.statusCode;
      }
    });
  }

  void _applyPage(BioPageConfig page, {bool resetDrafts = false}) {
    _page = page;
    if (resetDrafts || !_profileDirty) {
      _titleController.text = page.title ?? '';
      _instagramController.text = page.instagramHandle ?? '';
      _bioController.text = page.bio ?? '';
      _profileDirty = false;
    }
    if (resetDrafts || !_linksDirty) {
      _linksDraft = List.of(page.links);
      _linksDirty = false;
    }
    if (resetDrafts ||
        _slugController.text.trim().isEmpty ||
        _slugController.text.trim() == (page.slug ?? '')) {
      _slugController.text = page.slug ?? '';
      _slugAvailable = null;
    }
  }

  Future<void> _loadAnalytics({int? days}) async {
    final target = days ?? _analyticsDays;
    setState(() {
      _analyticsDays = target;
      _analyticsLoading = true;
    });
    final res = await BioPageService.instance.getAnalytics(days: target);
    if (!mounted) return;
    setState(() {
      _analyticsLoading = false;
      _analyticsLoaded = true;
      _analytics = res.success ? res.data : null;
      // A falha fica na própria aba (causa + "Tentar de novo"), no lugar
      // do aviso rápido que sumia e deixava "Sem métricas ainda" na tela.
      _analyticsError = res.success
          ? null
          : (res.message ?? 'Não foi possível carregar as métricas.');
      _analyticsErrorStatus = res.success ? 0 : res.statusCode;
    });
  }

  // ─── Ações ────────────────────────────────────────────────────────────────

  /// Aviso rápido no cartão do tema — o ícone diz se deu certo ou falhou, e
  /// o aviso novo troca o anterior (copiar três vezes não enfileira três).
  void _showSnack(String message, {SiteSnackTone tone = SiteSnackTone.info}) {
    if (!mounted) return;
    siteShowSnack(context, message, tone: tone);
  }

  /// Causa da falha em português do dia a dia (nunca a exceção crua).
  String _failure(String? message, int statusCode, String fallback) =>
      siteFailureMessage(message, statusCode, fallback: fallback);

  Future<void> _copyUrl() async {
    final url = _page?.bestPublicUrl;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    _showSnack(
      'Link copiado — é só colar na bio do Instagram.',
      tone: SiteSnackTone.success,
    );
  }

  Future<void> _openPage() async {
    final url = _page?.bestPublicUrl;
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      _showSnack('Não foi possível abrir a página.', tone: SiteSnackTone.error);
    }
  }

  /// Folha de compartilhar do sistema (WhatsApp, Instagram, e-mail…) com o
  /// endereço da página. [anchor] é o contexto do botão: no iPad a folha
  /// abre ancorada nele. Se o sistema recusar, o link vai para a área de
  /// transferência.
  Future<void> _shareUrl(BuildContext anchor) async {
    final url = _page?.bestPublicUrl;
    if (url == null) return;
    Rect? origin;
    final box = anchor.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      origin = box.localToGlobal(Offset.zero) & box.size;
    }
    try {
      await SharePlus.instance.share(
        ShareParams(text: url, sharePositionOrigin: origin),
      );
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      _showSnack('Não deu para abrir o compartilhamento — o link foi copiado.');
    }
  }

  Future<void> _togglePublish() async {
    final page = _page;
    if (page == null || _publishing) return;

    if (page.isPublished) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          // Rola em paisagem / fonte grande em vez de estourar.
          scrollable: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Tirar a página do ar?'),
          content: const Text(
            'Quem abrir o link da bio deixa de ver a página na hora. Seus '
            'links e textos continuam guardados — dá para publicar de novo '
            'quando quiser.',
          ),
          actions: [
            // Cancelar é neutro — o tema pinta TextButton com o vermelho da
            // marca, o que confundiria com a ação destrutiva ao lado.
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: ThemeHelpers.textSecondaryColor(ctx),
              ),
              child: const Text('Cancelar'),
            ),
            // Destrutivo: vermelho escurecido até o branco passar de 4,5:1
            // (o vermelho do escuro, cru, dava 3,4:1).
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: siteSolid(_red(ctx)),
                foregroundColor: Colors.white,
              ),
              child: const Text('Tirar do ar'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    } else if ((page.slug ?? '').trim().isEmpty) {
      _showSnack(
        'Escolha o endereço da página (aba Perfil) antes de publicar.',
      );
      setState(() => _activeTab = _BioTab.profile);
      return;
    }

    setState(() => _publishing = true);
    final res = page.isPublished
        ? await BioPageService.instance.unpublish()
        : await BioPageService.instance.publish();
    if (!mounted) return;
    setState(() {
      _publishing = false;
      if (res.success && res.data != null) _applyPage(res.data!);
    });
    if (res.success) {
      _showSnack(
        res.data!.isPublished
            ? 'Página no ar — quem abrir o link já vê.'
            : 'Página fora do ar.',
        tone: SiteSnackTone.success,
      );
    } else {
      _showSnack(
        _failure(
          res.message,
          res.statusCode,
          'Não foi possível mudar a publicação — tente de novo.',
        ),
        tone: SiteSnackTone.error,
      );
    }
  }

  Future<void> _saveProfile() async {
    if (_profileSaving) return;
    setState(() => _profileSaving = true);
    final res = await BioPageService.instance.update({
      'title': _titleController.text.trim(),
      'bio': _bioController.text.trim(),
      'instagramHandle': _instagramController.text.trim().replaceFirst(
        RegExp(r'^@+'),
        '',
      ),
    });
    if (!mounted) return;
    setState(() {
      _profileSaving = false;
      if (res.success && res.data != null) {
        _profileDirty = false;
        // Sem `resetDrafts`: os campos do perfil voltam do servidor (o dirty
        // acabou de zerar), mas links e endereço ainda não salvos ficam
        // como estavam — antes, salvar o perfil apagava esses rascunhos.
        _applyPage(res.data!);
      }
    });
    if (res.success) {
      _showSnack('Perfil salvo', tone: SiteSnackTone.success);
    } else {
      _showSnack(
        _failure(
          res.message,
          res.statusCode,
          'Não foi possível salvar o perfil — tente de novo.',
        ),
        tone: SiteSnackTone.error,
      );
    }
  }

  /// Descarta SÓ o rascunho do perfil. Antes o "Descartar" chamava
  /// `_applyPage(resetDrafts: true)` e levava junto os links e o endereço
  /// ainda não salvos.
  void _discardProfile() {
    final page = _page;
    if (page == null) return;
    setState(() {
      _titleController.text = page.title ?? '';
      _instagramController.text = page.instagramHandle ?? '';
      _bioController.text = page.bio ?? '';
      _profileDirty = false;
    });
  }

  // ── Slug ──

  void _onSlugChanged(String raw) {
    final sanitized = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9-]'), '');
    if (sanitized != raw) {
      _slugController.value = TextEditingValue(
        text: sanitized,
        selection: TextSelection.collapsed(offset: sanitized.length),
      );
    }
    _slugDebounce?.cancel();
    final current = (_page?.slug ?? '').trim();
    if (sanitized.length < 3 || sanitized == current) {
      setState(() {
        _slugAvailable = null;
        _slugChecking = false;
      });
      return;
    }
    setState(() {
      _slugAvailable = null;
      _slugChecking = true;
    });
    _slugDebounce = Timer(const Duration(milliseconds: 450), () async {
      final res = await BioPageService.instance.checkSlug(sanitized);
      if (!mounted || _slugController.text.trim() != sanitized) return;
      setState(() {
        _slugChecking = false;
        _slugAvailable = res.success ? res.data : null;
      });
    });
  }

  Future<void> _saveSlug() async {
    final slug = _slugController.text.trim();
    if (slug.length < 3) {
      _showSnack(
        'O endereço precisa de pelo menos 3 caracteres.',
        tone: SiteSnackTone.error,
      );
      return;
    }
    if (_slugAvailable == false) {
      _showSnack(
        'Este endereço já está em uso — escolha outro.',
        tone: SiteSnackTone.error,
      );
      return;
    }
    if (_slugSaving) return;
    setState(() => _slugSaving = true);
    final res = await BioPageService.instance.updateSlug(slug);
    if (!mounted) return;
    setState(() {
      _slugSaving = false;
      if (res.success && res.data != null) {
        _applyPage(res.data!);
        _slugController.text = res.data!.slug ?? slug;
        _slugAvailable = null;
      } else if (res.statusCode == 409) {
        _slugAvailable = false;
      }
    });
    if (res.success) {
      _showSnack('Endereço atualizado', tone: SiteSnackTone.success);
    } else {
      // O 409 do serviço fala em "slug" — aqui é "endereço".
      _showSnack(
        res.statusCode == 409
            ? 'Este endereço já está em uso por outra empresa — escolha '
                  'outro.'
            : _failure(
                res.message,
                res.statusCode,
                'Endereço inválido ou reservado — tente outro.',
              ),
        tone: SiteSnackTone.error,
      );
    }
  }

  // ── Links ──

  void _reindexLinks() {
    _linksDraft = [
      for (var i = 0; i < _linksDraft.length; i++)
        _linksDraft[i].copyWith(order: i),
    ];
  }

  Future<void> _addLink() async {
    final link = await BioLinkEditSheet.show(context);
    if (link == null || !mounted) return;
    setState(() {
      _linksDraft = [..._linksDraft, link];
      _reindexLinks();
      _linksDirty = true;
    });
  }

  Future<void> _editLink(int index) async {
    final edited = await BioLinkEditSheet.show(
      context,
      initial: _linksDraft[index],
    );
    if (edited == null || !mounted) return;
    setState(() {
      _linksDraft = List.of(_linksDraft)..[index] = edited;
      _linksDirty = true;
    });
  }

  Future<void> _removeLink(int index) async {
    final link = _linksDraft[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remover link?'),
        content: Text(
          link.label.trim().isEmpty
              ? 'O link sai da página quando você salvar os links.'
              : '“${link.label.trim()}” sai da página quando você salvar os '
                    'links. Para esconder sem apagar, desligue o interruptor '
                    'do link.',
        ),
        actions: [
          // Cancelar é neutro — nunca no vermelho padrão do tema.
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: ThemeHelpers.textSecondaryColor(ctx),
            ),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: siteSolid(_red(ctx)),
              foregroundColor: Colors.white,
            ),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _linksDraft = List.of(_linksDraft)..removeAt(index);
      _reindexLinks();
      _linksDirty = true;
    });
  }

  Future<void> _saveLinks() async {
    if (_linksSaving) return;
    setState(() => _linksSaving = true);
    _reindexLinks();
    // 29/09/2026 (integ-01): cada link vai inteiro — `kind`, `icon`,
    // `subtitle`, cores e campos que o app não conhece (`extras`) — e o
    // botão de captação vai com `url: ''`, igual ao save do web. Antes o
    // `sanitizeLinks` do back recebia o link sem `kind`, descartava o botão
    // de captação e zerava ícone e subtítulo feitos no web.
    final res = await BioPageService.instance.update({
      'links': [for (final l in _linksDraft) l.toJson()],
    });
    if (!mounted) return;
    setState(() {
      _linksSaving = false;
      if (res.success && res.data != null) {
        _linksDirty = false;
        _applyPage(res.data!, resetDrafts: false);
        _linksDraft = List.of(res.data!.links);
      }
    });
    if (res.success) {
      _showSnack('Links salvos', tone: SiteSnackTone.success);
    } else {
      _showSnack(
        _failure(
          res.message,
          res.statusCode,
          'Não foi possível salvar os links — tente de novo.',
        ),
        tone: SiteSnackTone.error,
      );
    }
  }

  /// Volta a lista para o que está salvo (só os links).
  void _discardLinks() {
    final page = _page;
    if (page == null) return;
    setState(() {
      _linksDraft = List.of(page.links);
      _linksDirty = false;
    });
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  /// Recuo lateral da coluna: 16 no celular (mais o entalhe em paisagem) e,
  /// no tablet, o que sobra para a coluna ficar em [_kMaxContent] centrada.
  /// Vem da largura da tela — sem LayoutBuilder entre o RefreshIndicator e
  /// a lista (ali ele quebra o puxar-para-atualizar).
  EdgeInsets _columnInsets(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final safe = MediaQuery.paddingOf(context);
    final spare = (width - _kMaxContent) / 2;
    return EdgeInsets.only(
      left: math.max(_kPagePadH + safe.left, spare),
      right: math.max(_kPagePadH + safe.right, spare),
    );
  }

  /// Há altura para a barra de salvar ficar presa embaixo?
  bool _dockFits(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return height - MediaQuery.viewInsetsOf(context).bottom >= _kDockMinHeight;
  }

  /// Endereço digitado e ainda não salvo (acende o ponto da aba Perfil).
  bool get _slugDraftDirty {
    final draft = _slugController.text.trim();
    return draft.isNotEmpty && draft != (_page?.slug ?? '').trim();
  }

  /// O que a barra de salvar da aba ativa salva (o endereço tem botão
  /// próprio, logo abaixo do campo).
  bool get _activeTabDirty {
    switch (_activeTab) {
      case _BioTab.profile:
        return _profileDirty;
      case _BioTab.links:
        return _linksDirty;
      case _BioTab.analytics:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_canView) {
      return const AppScaffold(
        title: 'Link in Bio',
        showBottomNavigation: false,
        body: SiteDeniedView(
          message: 'Você não tem acesso à página Link in Bio.',
          permissionLabel: PublicSiteAccess.permView,
        ),
      );
    }

    final insets = _columnInsets(context);
    final ready = !_loading && _error == null && _page != null;
    final showDock =
        ready && _canManage && _activeTabDirty && _dockFits(context);

    final List<Widget> children;
    if (_loading) {
      children = [_buildPageSkeleton(context, insets)];
    } else if (!ready) {
      children = [
        Padding(
          padding: insets.copyWith(top: 48, bottom: _kPagePadBottom),
          child: SiteErrorState(
            message:
                _error ?? 'Não foi possível carregar a página Link in Bio.',
            statusCode: _errorStatus,
            onRetry: _load,
          ),
        ),
      ];
    } else {
      children = [
        Padding(
          padding: insets.copyWith(top: _kPagePadTop),
          child: _buildHero(context),
        ),
        const SizedBox(height: _kSectionGap + 10),
        _buildTabsRail(context, insets),
        Padding(
          padding: insets.copyWith(
            top: _kSectionGap + 6,
            bottom: _kPagePadBottom,
          ),
          child: _buildActivePanel(context),
        ),
      ];
    }

    return AppScaffold(
      title: 'Link in Bio',
      showBottomNavigation: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: RefreshIndicator(
              color: _identity(context),
              onRefresh: () async {
                await _load();
                if (_analyticsLoaded) await _loadAnalytics();
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.zero,
                children: children,
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: showDock
                ? _buildSaveDock(context, insets)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  // ─── Hero: no ar? em qual endereço? quantos links? o que o visitante vê? ──

  Widget _buildHero(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final wide = width >= 560;
        // Prévia: ~42% da coluna no celular (121dp em 320, 138 em 360) e 176
        // no tablet — o bloco ao lado nunca fica abaixo de ~150dp. Antes o
        // celular tinha 168 fixos e sobravam ~24dp para o endereço em 320.
        final phoneWidth = wide
            ? 176.0
            : (width * 0.42).clamp(118.0, 168.0).toDouble();
        final phone = _buildPhoneMock(context, phoneWidth);
        final status = _buildHeroStatus(context);
        final counts = _buildHeroCounts(context);
        final address = _buildHeroAddress(context);
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              phone,
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    status,
                    const SizedBox(height: 18),
                    counts,
                    const SizedBox(height: 18),
                    address,
                  ],
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                phone,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [status, const SizedBox(height: 16), counts],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            address,
          ],
        );
      },
    );
  }

  /// Estado da página em palavra grande — No ar (verde) / Rascunho (âmbar)
  /// —, a frase do que isso quer dizer e, em rascunho, o "Publicar" à mão
  /// (travado com o motivo para quem não gerencia).
  Widget _buildHeroStatus(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final page = _page!;
    final published = page.isPublished;
    final tone = published ? _green(context) : _amber(context);
    final ink = siteInk(context, tone);
    final dateFmt = DateFormat('dd/MM/yyyy', 'pt_BR');
    final String sub;
    if (published) {
      sub = page.publishedAt != null
          ? 'Publicada em ${dateFmt.format(page.publishedAt!.toLocal())}'
          : 'Quem abrir o link vê a página.';
    } else {
      sub = 'Só você vê — ninguém abre a página até ela ser publicada.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tone.withValues(alpha: isDark ? 0.18 : 0.12),
                border: Border.all(color: tone.withValues(alpha: 0.4)),
              ),
              child: Icon(
                published ? LucideIcons.globe : LucideIcons.pencilLine,
                size: 15,
                color: ink,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                published ? 'No ar' : 'Rascunho',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: ink,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          sub,
          style: theme.textTheme.bodySmall?.copyWith(
            color: secondary,
            height: 1.35,
          ),
        ),
        if (!published) ...[
          const SizedBox(height: 10),
          if (_canManage)
            _heroPublishButton(context)
          else
            const SiteReadOnlyNotice(
              dense: true,
              text: 'Só quem gerencia o Link in Bio pode publicar.',
            ),
        ],
        if (_linksDirty || _profileDirty) ...[
          const SizedBox(height: 10),
          _noteLine(
            context,
            LucideIcons.pencilLine,
            'A prévia mostra alterações ainda não salvas.',
            color: siteInk(context, _amber(context)),
          ),
        ],
      ],
    );
  }

  /// "Publicar" no próprio estado — mesma ação (e mesmas checagens) do
  /// controle de publicação da aba Perfil.
  Widget _heroPublishButton(BuildContext context) {
    final green = siteSolid(_green(context));
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.icon(
        onPressed: _publishing ? null : _togglePublish,
        style: FilledButton.styleFrom(
          backgroundColor: green,
          foregroundColor: Colors.white,
          disabledBackgroundColor: green.withValues(alpha: 0.6),
          disabledForegroundColor: Colors.white,
          minimumSize: const Size(0, 40),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
        ),
        icon: _publishing
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(LucideIcons.rocket, size: 16),
        label: SiteButtonLabel(_publishing ? 'Publicando…' : 'Publicar'),
      ),
    );
  }

  /// Quantos links aparecem na página — o número que importa, grande, com o
  /// rótulo curto embaixo; captação e visitas (quando já carregadas) depois.
  Widget _buildHeroCounts(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final numberFmt = NumberFormat.decimalPattern('pt_BR');
    final total = _linksDraft.length;
    final active = _linksDraft.where((l) => l.isActive).length;
    final leadActive = _linksDraft.any((l) => l.isActive && l.isLeadForm);
    // Enquanto outro período carrega, o número antigo não vai com o rótulo
    // do período novo.
    final views = _analyticsLoading ? null : _analytics?.pageViews;

    final String caption;
    if (total == 0) {
      caption = 'links na página — comece pela aba Links';
    } else if (active == 1) {
      caption = 'link aparece na página';
    } else {
      caption = 'links aparecem na página';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: numberFmt.format(active),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                    height: 1.0,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (active != total)
                  TextSpan(
                    text: ' de ${numberFmt.format(total)}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          caption,
          style: theme.textTheme.bodySmall?.copyWith(
            color: secondary,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
        if (leadActive) ...[
          const SizedBox(height: 8),
          _noteLine(
            context,
            LucideIcons.userRoundPlus,
            'Com botão de captação ativo',
            color: siteInk(context, _identity(context)),
          ),
        ],
        if (views != null) ...[
          const SizedBox(height: 6),
          _noteLine(
            context,
            LucideIcons.eye,
            '${numberFmt.format(views)} ${views == 1 ? 'visita' : 'visitas'} '
            'nos últimos $_analyticsDays dias',
          ),
        ],
      ],
    );
  }

  /// Endereço como barra de navegador (domínio esmaecido, final forte) e
  /// Copiar / Abrir / Compartilhar logo embaixo. Sem endereço: o que fazer.
  Widget _buildHeroAddress(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final violetInk = siteInk(context, _identity(context));
    final page = _page!;
    final url = page.bestPublicUrl;
    final barDecoration = BoxDecoration(
      color: siteFieldFill(context),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: ThemeHelpers.borderLightColor(context)),
    );

    if (url == null) {
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 8, 11),
        decoration: barDecoration,
        child: Row(
          children: [
            Icon(LucideIcons.globe, size: 16, color: secondary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Endereço ainda não definido',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: ThemeHelpers.textColor(context),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _canManage
                        ? 'Escolha o final do link na aba Perfil — é ele que '
                              'vai na bio do Instagram.'
                        : 'Quem gerencia o Link in Bio escolhe o endereço.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            if (_canManage) ...[
              const SizedBox(width: 6),
              TextButton(
                onPressed: () => setState(() => _activeTab = _BioTab.profile),
                style: TextButton.styleFrom(
                  foregroundColor: violetInk,
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: const Text(
                  'Definir',
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ],
        ),
      );
    }

    // "https://bio.intellisysbr.com/minha-imobiliaria" → domínio esmaecido
    // + o final forte (o que a pessoa escolheu), sem o esquema.
    final display = url.replaceFirst(RegExp(r'^https?://'), '');
    final cut = display.lastIndexOf('/');
    final hasTail = cut > 0 && cut < display.length - 1;
    final head = hasTail ? display.substring(0, cut + 1) : '';
    final tail = hasTail ? display.substring(cut + 1) : display;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: 'Endereço da página: $display',
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
            decoration: barDecoration,
            child: Row(
              children: [
                Icon(
                  page.isPublished ? LucideIcons.globe : LucideIcons.globeLock,
                  size: 16,
                  color: secondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (head.isNotEmpty)
                        Text(
                          head,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: secondary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      // Final em até 2 linhas (quebra no hífen) — nunca
                      // encolhido até ficar ilegível.
                      Text(
                        tail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: violetInk,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _addressAction(
                context,
                icon: LucideIcons.copy,
                label: 'Copiar',
                onTap: _copyUrl,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _addressAction(
                context,
                icon: LucideIcons.externalLink,
                label: 'Abrir',
                onTap: _openPage,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Builder(
                builder: (anchor) => _addressAction(
                  anchor,
                  icon: LucideIcons.share2,
                  label: 'Compartilhar',
                  onTap: () => _shareUrl(anchor),
                ),
              ),
            ),
          ],
        ),
        if (!page.isPublished) ...[
          const SizedBox(height: 10),
          _noteLine(
            context,
            LucideIcons.circleAlert,
            'Fora do ar: quem abrir este link ainda não vê a página.',
            color: siteInk(context, _amber(context)),
          ),
        ],
      ],
    );
  }

  /// Ação do endereço: ícone em cima, rótulo embaixo — as três lado a lado
  /// cabem em 320dp com fonte a 130% (o rótulo encolhe, não estoura).
  Widget _addressAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final violetInk = siteInk(context, _identity(context));
    // O nó de acessibilidade leva o rótulo E a ação (excluir os filhos sem
    // repassar o toque deixava o botão mudo para o leitor de tela).
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(6, 9, 6, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: siteHairline(context)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: violetInk),
                const SizedBox(height: 5),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      color: ThemeHelpers.textColor(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
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

  /// Prévia do celular — o que o visitante vê: foto, nome, @, bio e os
  /// primeiros links ativos nas cores que o cliente escolheu. Mostra o
  /// RASCUNHO (campos e lista), então acompanha a edição. Moldura: o cinza
  /// dos campos com um véu da cor da bio — tudo por token, sem brilho
  /// colorido atrás. Miniatura: o texto cresce até 110%, senão a proporção
  /// do aparelho se perde (a informação real está ao lado e na lista).
  Widget _buildPhoneMock(BuildContext context, double width) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tint = _heroTint(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final title = _titleController.text.trim();
    final handle = _instagramController.text.trim().replaceFirst(
      RegExp(r'^@+'),
      '',
    );
    final bio = _bioController.text.trim();
    final active = _linksDraft.where((l) => l.isActive).toList(growable: false);
    final shown = active.take(3).toList(growable: false);
    final extra = active.length - shown.length;
    final compact = width < 150;
    final pad = compact ? 8.0 : 10.0;
    final frame = Color.alphaBlend(
      tint.withValues(alpha: isDark ? 0.22 : 0.16),
      siteFieldFill(context),
    );

    return Semantics(
      label: 'Prévia da página como o visitante vê',
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.1,
        child: Container(
          width: width,
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: frame,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: tint.withValues(alpha: isDark ? 0.4 : 0.3),
            ),
            boxShadow: ThemeHelpers.cardShadow(context),
          ),
          child: Container(
            padding: EdgeInsets.fromLTRB(pad, 9, pad, 12),
            decoration: BoxDecoration(
              color: ThemeHelpers.cardBackgroundColor(context),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 34,
                    height: 4,
                    decoration: BoxDecoration(
                      color: secondary.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: _mockAvatar(
                    context,
                    tint,
                    title,
                    compact ? 40.0 : 46.0,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  title.isEmpty ? 'Sua página' : title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                    height: 1.2,
                    color: title.isEmpty
                        ? secondary
                        : ThemeHelpers.textColor(context),
                  ),
                ),
                if (handle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '@$handle',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: secondary,
                    ),
                  ),
                ],
                if (bio.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    bio,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      color: secondary,
                    ),
                  ),
                ],
                const SizedBox(height: 11),
                if (shown.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: secondary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      'Seus links aparecem aqui',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                        color: secondary,
                      ),
                    ),
                  )
                else
                  for (var i = 0; i < shown.length; i++) ...[
                    if (i > 0) const SizedBox(height: 6),
                    _mockLinkButton(context, shown[i], tint),
                  ],
                if (extra > 0) ...[
                  const SizedBox(height: 7),
                  Text(
                    '+$extra ${extra == 1 ? 'link' : 'links'}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: secondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _mockAvatar(
    BuildContext context,
    Color accent,
    String title,
    double size,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final avatarUrl = (_page!.avatarUrl ?? '').trim();
    final initial = title.isNotEmpty
        ? title.characters.first.toUpperCase()
        : null;
    final ink = siteInk(context, accent);
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withValues(alpha: isDark ? 0.2 : 0.12),
        border: Border.all(color: accent.withValues(alpha: 0.45), width: 1.5),
      ),
      child: avatarUrl.isNotEmpty
          ? Image.network(
              avatarUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _mockAvatarFallback(ink, initial),
            )
          : _mockAvatarFallback(ink, initial),
    );
  }

  Widget _mockAvatarFallback(Color ink, String? initial) {
    return Center(
      child: initial != null
          ? Text(
              initial,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: ink,
              ),
            )
          : Icon(LucideIcons.userRound, size: 18, color: ink),
    );
  }

  /// Botão da bio em miniatura. Cor escolhida pelo cliente = DADO: pinta o
  /// botão como na página (degradê quando há segunda cor) e o texto vem de
  /// [siteOnColor] sobre o meio do degradê. Sem cor, o violeta da tela.
  Widget _mockLinkButton(BuildContext context, BioPageLink link, Color accent) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c1 = siteParseHexColor(link.color);
    final c2 = siteParseHexColor(link.color2);
    final List<Color>? paint = c1 == null ? null : [c1, c2 ?? c1];
    final fg = paint != null
        ? siteOnColor(Color.lerp(paint.first, paint.last, 0.5)!)
        : siteInk(context, accent);
    final label = link.label.trim().isEmpty ? 'Sem texto' : link.label.trim();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: paint == null ? null : LinearGradient(colors: paint),
        color: paint == null
            ? accent.withValues(alpha: isDark ? 0.2 : 0.12)
            : null,
        border: paint == null
            ? Border.all(color: accent.withValues(alpha: 0.3))
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(bioLinkIcon(link), size: 10, color: fg),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.1,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Abas flush ───────────────────────────────────────────────────────────

  Widget _buildTabsRail(BuildContext context, EdgeInsets insets) {
    final tone = _identity(context);
    return Padding(
      padding: EdgeInsets.only(
        left: math.max(0.0, insets.left - 8),
        right: math.max(0.0, insets.right - 8),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
          ),
        ),
        child: Row(
          children: [
            for (final tab in _BioTab.values)
              Expanded(
                child: SiteFlushTab(
                  icon: _tabIcon(tab),
                  label: _tabLabel(tab),
                  count: tab == _BioTab.links ? _linksDraft.length : null,
                  tone: tone,
                  selected: _activeTab == tab,
                  // Ponto âmbar estático: há rascunho nesta aba.
                  dirty: _tabDirty(tab),
                  onTap: () {
                    setState(() => _activeTab = tab);
                    if (tab == _BioTab.analytics &&
                        !_analyticsLoaded &&
                        !_analyticsLoading) {
                      _loadAnalytics();
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _tabDirty(_BioTab tab) {
    switch (tab) {
      case _BioTab.profile:
        return _profileDirty || _slugDraftDirty;
      case _BioTab.links:
        return _linksDirty;
      case _BioTab.analytics:
        return false;
    }
  }

  IconData _tabIcon(_BioTab tab) {
    switch (tab) {
      case _BioTab.profile:
        return LucideIcons.userRound;
      case _BioTab.links:
        return LucideIcons.link;
      case _BioTab.analytics:
        return LucideIcons.chartLine;
    }
  }

  String _tabLabel(_BioTab tab) {
    switch (tab) {
      case _BioTab.profile:
        return 'Perfil';
      case _BioTab.links:
        return 'Links';
      case _BioTab.analytics:
        return 'Métricas';
    }
  }

  // ─── Painéis ──────────────────────────────────────────────────────────────

  Widget _buildActivePanel(BuildContext context) {
    final Widget child;
    switch (_activeTab) {
      case _BioTab.profile:
        child = _buildProfilePanel(context);
        break;
      case _BioTab.links:
        child = _buildLinksPanel(context);
        break;
      case _BioTab.analytics:
        child = _buildAnalyticsPanel(context);
        break;
    }
    return KeyedSubtree(
      key: ValueKey('panel-${_activeTab.name}'),
      child: child,
    );
  }

  ({IconData icon, String title, String hint}) _panelMeta(_BioTab tab) {
    switch (tab) {
      case _BioTab.profile:
        return (
          icon: LucideIcons.idCard,
          title: 'Como a página se apresenta',
          hint: 'Publicação, endereço, nome, bio e Instagram.',
        );
      case _BioTab.links:
        return (
          icon: LucideIcons.link,
          title: 'Links da página',
          hint:
              'Cada link vira um botão, na ordem desta lista. Toque para '
              'editar; arraste pela alça para mudar a ordem.',
        );
      case _BioTab.analytics:
        return (
          icon: LucideIcons.chartLine,
          title: 'Desempenho da página',
          hint: 'Visitas e cliques em cada link no período escolhido.',
        );
    }
  }

  /// Cabeçalho do painel (barra de acento + título + dica, o mesmo do Meu
  /// Site) e o corpo, com entrada suave ao trocar de aba.
  Widget _panelShell(BuildContext context, _BioTab tab, List<Widget> body) {
    final meta = _panelMeta(tab);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SitePanelHeader(
          icon: meta.icon,
          title: meta.title,
          hint: meta.hint,
          tone: _identity(context),
        ),
        const SizedBox(height: 16),
        ...body,
      ],
    ).animate().fadeIn(duration: 220.ms);
  }

  /// Quem só pode ver: campos travados e o porquê, com quem libera.
  Widget _readOnlyNotice() => const SiteReadOnlyNotice(
    text:
        'Somente leitura — para editar, peça ao administrador a permissão '
        '“Gerenciar o Meu Site e o Link in Bio”.',
  );

  /// Linha de apoio: ícone 13 + texto que quebra em quantas linhas precisar.
  /// Com [color], ícone e texto vão na tinta do significado.
  Widget _noteLine(
    BuildContext context,
    IconData icon,
    String text, {
    Color? color,
  }) {
    final tint = color ?? ThemeHelpers.textSecondaryColor(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 13, color: tint),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: tint,
              fontSize: 11.5,
              fontWeight: color == null ? FontWeight.w500 : FontWeight.w700,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  // ─── Barra de salvar presa embaixo ───────────────────────────────────────

  /// Com altura sobrando, "Descartar" e "Salvar" ficam presos embaixo
  /// enquanto a aba tiver alteração — ligar um link no topo de uma lista
  /// longa não deixa mais o botão escondido no fim da rolagem. Com teclado
  /// aberto ou em paisagem, volta a ser o [SiteSaveBar] no fim do painel.
  Widget _buildSaveDock(BuildContext context, EdgeInsets insets) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    // Salvar = confirmar → verde escurecido até o branco passar de 4,5:1.
    final green = siteSolid(_green(context));
    final amber = siteInk(context, _amber(context));
    final links = _activeTab == _BioTab.links;
    final saving = links ? _linksSaving : _profileSaving;
    final VoidCallback onSave = links ? _saveLinks : _saveProfile;
    final VoidCallback onDiscard = links ? _discardLinks : _discardProfile;
    final label = links ? 'Salvar links' : 'Salvar perfil';
    final pending = links
        ? 'Links alterados — a página só muda depois de salvar.'
        : 'Perfil alterado — a página só muda depois de salvar.';
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border(top: BorderSide(color: siteHairline(context))),
      ),
      padding: EdgeInsets.fromLTRB(
        insets.left,
        10,
        insets.right,
        10 + safeBottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            // Folga à direita para a bolha do chat (canto, 80dp acima).
            padding: const EdgeInsets.only(right: 56),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: amber,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pending,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: secondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              // Descartar no tamanho do rótulo; Salvar leva o resto — em
              // 320dp a 130% ficam lado a lado (o par empilhado dobrava a
              // altura da barra).
              OutlinedButton.icon(
                onPressed: saving ? null : onDiscard,
                style: OutlinedButton.styleFrom(
                  foregroundColor: secondary,
                  side: BorderSide(color: ThemeHelpers.borderColor(context)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 13,
                  ),
                ),
                icon: const Icon(LucideIcons.undo2, size: 15),
                label: const Text(
                  'Descartar',
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: saving ? null : onSave,
                  style: FilledButton.styleFrom(
                    backgroundColor: green,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: green.withValues(alpha: 0.6),
                    disabledForegroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                  ),
                  icon: saving
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(LucideIcons.check, size: 17),
                  label: SiteButtonLabel(saving ? 'Salvando…' : label),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Perfil & endereço ──

  /// Publicação (aba Perfil) — controle com corpo: estado, o que falta
  /// (endereço e links) e a ação: Publicar verde / Tirar do ar neutro (o
  /// vermelho fica no confirmar do diálogo). Sem permissão: botão travado
  /// com cadeado e o motivo, em vez de sumir.
  Widget _buildPublishControl(
    BuildContext context, {
    required BioPageConfig page,
    required bool hasSlug,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final published = page.isPublished;
    final tone = published ? _green(context) : _amber(context);
    final dateFmt = DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR');
    final activeCount = _linksDraft.where((l) => l.isActive).length;
    final address = page.bestPublicUrl?.replaceFirst(RegExp(r'^https?://'), '');

    final String title;
    final String sub;
    if (published) {
      title = 'Sua página está no ar';
      sub = page.publishedAt != null
          ? 'Publicada em ${dateFmt.format(page.publishedAt!.toLocal())}. '
                'Quem abrir o link vê a página.'
          : 'Quem abrir o link vê a página.';
    } else if (hasSlug) {
      title = 'Pronta para publicar';
      sub = 'Enquanto for rascunho, só você vê a página.';
    } else {
      title = 'Falta o endereço para publicar';
      sub = 'Escolha o final do endereço logo abaixo e depois publique.';
    }

    final Widget action;
    if (!_canManage) {
      action = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: null,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: ThemeHelpers.borderLightColor(context)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            icon: const Icon(LucideIcons.lock, size: 15),
            label: SiteButtonLabel(
              published ? 'Tirar do ar' : 'Publicar página',
            ),
          ),
          const SizedBox(height: 8),
          const SiteReadOnlyNotice(
            dense: true,
            text:
                'Só quem gerencia o Link in Bio publica ou tira a página do ar.',
          ),
        ],
      );
    } else if (published) {
      action = OutlinedButton.icon(
        onPressed: _publishing ? null : _togglePublish,
        style: OutlinedButton.styleFrom(
          foregroundColor: secondary,
          side: BorderSide(color: ThemeHelpers.borderColor(context)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        icon: _publishing
            ? SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: secondary,
                ),
              )
            : const Icon(LucideIcons.eyeOff, size: 16),
        label: SiteButtonLabel(_publishing ? 'Aguarde…' : 'Tirar do ar'),
      );
    } else {
      final green = siteSolid(_green(context));
      action = FilledButton.icon(
        onPressed: _publishing ? null : _togglePublish,
        style: FilledButton.styleFrom(
          backgroundColor: green,
          foregroundColor: Colors.white,
          disabledBackgroundColor: green.withValues(alpha: 0.6),
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        ),
        icon: _publishing
            ? const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(LucideIcons.rocket, size: 17),
        label: SiteButtonLabel(_publishing ? 'Publicando…' : 'Publicar página'),
      );
    }

    return SiteCard(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tone.withValues(alpha: isDark ? 0.18 : 0.12),
                  border: Border.all(color: tone.withValues(alpha: 0.4)),
                ),
                child: Icon(
                  published ? LucideIcons.globe : LucideIcons.rocket,
                  size: 18,
                  color: siteInk(context, tone),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      sub,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // O que falta para ir ao ar — a mesma linha de checklist do Meu
          // Site (antes eram dois chips lado a lado que cortavam o texto em
          // 320dp). Sem link ativo, a seta leva à aba Links.
          SiteCheckRow(
            label: 'Endereço',
            value: hasSlug && address != null
                ? address
                : 'Falta escolher — é logo abaixo.',
            state: hasSlug ? SiteCheckState.done : SiteCheckState.missing,
          ),
          SiteCheckRow(
            label: 'Links na página',
            value: activeCount == 0
                ? 'Nenhum link aparece — adicione na aba Links.'
                : '$activeCount '
                      '${activeCount == 1 ? 'link aparece' : 'links aparecem'} '
                      'para o visitante.',
            state: activeCount > 0
                ? SiteCheckState.done
                : SiteCheckState.missing,
            divider: false,
            onTap: activeCount == 0
                ? () => setState(() => _activeTab = _BioTab.links)
                : null,
          ),
          const SizedBox(height: 10),
          action,
        ],
      ),
    );
  }

  /// Microlinha sob um campo — ícone 12 + texto em até 2 linhas.
  Widget _fieldMeta(
    BuildContext context, {
    required IconData icon,
    required String text,
    bool highlight = false,
  }) {
    final tone = highlight
        ? siteInk(context, _identity(context))
        : ThemeHelpers.textSecondaryColor(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 12, color: tone),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
              color: tone,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  /// Contador vivo da bio — esquenta para âmbar perto do limite.
  Widget _bioCounter(BuildContext context) {
    final len = _bioController.text.length;
    final tone = len >= 260
        ? siteInk(context, _amber(context))
        : ThemeHelpers.textSecondaryColor(context);
    return Text(
      '$len/280',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: tone,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  /// O endereço inteiro, ao vivo, sob o campo — o campo só pede o final
  /// (antes o prefixo "bio.intellisysbr.com/" comia 2/3 do campo em 320dp).
  Widget _slugPreviewLine(BuildContext context, String draftSlug) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final violetInk = siteInk(context, _identity(context));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(LucideIcons.globe, size: 13, color: secondary),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$kBioPublicBase/',
                  style: TextStyle(
                    color: secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(
                  text: draftSlug.isEmpty ? 'seu-endereco' : draftSlug,
                  style: TextStyle(
                    color: draftSlug.isEmpty
                        ? secondary.withValues(alpha: 0.7)
                        : violetInk,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, height: 1.35),
          ),
        ),
      ],
    );
  }

  /// Disponibilidade do endereço digitado (só quando ele mudou).
  Widget _slugStatusLine(BuildContext context, String draftSlug) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final Widget lead;
    final String text;
    final Color color;
    if (_slugChecking) {
      color = secondary;
      text = 'Conferindo se o endereço está livre…';
      lead = SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 1.6, color: secondary),
      );
    } else if (draftSlug.length < 3) {
      color = siteInk(context, _amber(context));
      text = 'Use pelo menos 3 caracteres.';
      lead = Icon(LucideIcons.circleAlert, size: 13, color: color);
    } else if (_slugAvailable == true) {
      color = siteInk(context, _green(context));
      text = 'Livre — toque em Salvar endereço.';
      lead = Icon(LucideIcons.circleCheckBig, size: 13, color: color);
    } else if (_slugAvailable == false) {
      color = siteInk(context, _red(context));
      text = 'Este endereço já está em uso por outra empresa — escolha outro.';
      lead = Icon(LucideIcons.circleX, size: 13, color: color);
    } else {
      return const SizedBox.shrink();
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: lead),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfilePanel(BuildContext context) {
    final page = _page!;
    final violet = _identity(context);
    final green = siteSolid(_green(context));

    final currentSlug = (page.slug ?? '').trim();
    final draftSlug = _slugController.text.trim();
    final slugChanged = draftSlug != currentSlug;
    final canSaveSlug =
        _canManage &&
        !_slugSaving &&
        slugChanged &&
        draftSlug.length >= 3 &&
        _slugAvailable != false;
    final slugLabel = _slugSaving
        ? 'Salvando…'
        : (slugChanged || currentSlug.isEmpty
              ? 'Salvar endereço'
              : 'Endereço salvo');
    final instagram = _instagramController.text.trim().replaceAll('@', '');

    void markDirty(String _) {
      if (!_profileDirty) setState(() => _profileDirty = true);
    }

    return _panelShell(context, _BioTab.profile, [
      if (!_canManage) ...[_readOnlyNotice(), const SizedBox(height: 12)],
      _buildPublishControl(
        context,
        page: page,
        hasSlug: currentSlug.isNotEmpty,
      ),
      const SizedBox(height: 26),
      const SiteSubsectionHeader(
        label: 'Endereço da página',
        icon: LucideIcons.globe,
        hint:
            'É o link que vai na bio do Instagram. Não precisa configurar '
            'nada: você só escolhe o final.',
      ),
      const SizedBox(height: 12),
      SiteFilledField(
        controller: _slugController,
        label: 'Final do endereço',
        hint: 'minha-imobiliaria',
        prefixText: '/',
        icon: LucideIcons.link2,
        keyboardType: TextInputType.url,
        enabled: _canManage,
        onChanged: _onSlugChanged,
        accent: violet,
      ),
      const SizedBox(height: 7),
      _slugPreviewLine(context, draftSlug),
      if (slugChanged && draftSlug.isNotEmpty) ...[
        const SizedBox(height: 6),
        _slugStatusLine(context, draftSlug),
      ],
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: canSaveSlug ? _saveSlug : null,
        style: FilledButton.styleFrom(
          backgroundColor: green,
          foregroundColor: Colors.white,
          // Salvando: segue verde com o spinner branco à vista. Sem
          // mudança: o desabilitado neutro diz "nada a salvar".
          disabledBackgroundColor: _slugSaving
              ? green.withValues(alpha: 0.6)
              : null,
          disabledForegroundColor: _slugSaving ? Colors.white : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        icon: _slugSaving
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(
                slugChanged || currentSlug.isEmpty
                    ? LucideIcons.save
                    : LucideIcons.check,
                size: 16,
              ),
        label: SiteButtonLabel(slugLabel),
      ),
      const SizedBox(height: 26),
      const SiteSubsectionHeader(
        label: 'Nome, bio e Instagram',
        icon: LucideIcons.userRound,
        hint: 'O que aparece no topo da página, acima dos links.',
      ),
      const SizedBox(height: 12),
      // Duas colunas só quando cada uma tem folga (≥170dp × escala do
      // texto) — em 320dp, ou a 130%, empilham.
      SiteRow2(
        minColumnWidth: 170,
        left: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SiteFilledField(
              controller: _titleController,
              label: 'Nome ou título',
              hint: 'Sua imobiliária',
              icon: LucideIcons.store,
              enabled: _canManage,
              textCapitalization: TextCapitalization.words,
              onChanged: (v) {
                markDirty(v);
                setState(() {});
              },
              accent: violet,
            ),
            const SizedBox(height: 5),
            _fieldMeta(
              context,
              icon: LucideIcons.type,
              text: 'Título no topo da página',
            ),
          ],
        ),
        right: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SiteFilledField(
              controller: _instagramController,
              label: 'Instagram',
              hint: 'sua_imobiliaria',
              icon: LucideIcons.atSign,
              enabled: _canManage,
              onChanged: (v) {
                markDirty(v);
                setState(() {});
              },
              accent: violet,
            ),
            const SizedBox(height: 5),
            _fieldMeta(
              context,
              icon: LucideIcons.link2,
              text: instagram.isEmpty
                  ? 'Vira o botão do seu perfil'
                  : 'instagram.com/$instagram',
              highlight: instagram.isNotEmpty,
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      SiteFilledField(
        controller: _bioController,
        label: 'Bio',
        hint: 'Conte em poucas palavras o que o visitante encontra aqui…',
        maxLines: 3,
        maxLength: 280,
        enabled: _canManage,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (v) {
          markDirty(v);
          setState(() {});
        },
        accent: violet,
      ),
      const SizedBox(height: 5),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _fieldMeta(
              context,
              icon: LucideIcons.alignLeft,
              text: 'Aparece logo abaixo do nome',
            ),
          ),
          const SizedBox(width: 8),
          _bioCounter(context),
        ],
      ),
      const SizedBox(height: 12),
      _noteLine(
        context,
        LucideIcons.image,
        'Foto de perfil, modelo e cores da página são ajustados no painel '
        'web — aqui você cuida do texto, do endereço e dos links.',
      ),
      SiteSaveBar(
        visible: _canManage && _profileDirty && !_dockFits(context),
        saving: _profileSaving,
        label: 'Salvar perfil',
        onSave: _saveProfile,
        onDiscard: _discardProfile,
        pendingText: 'Perfil alterado — a página só muda depois de salvar.',
      ),
    ]);
  }

  // ── Links ──

  Widget _buildLinksPanel(BuildContext context) {
    final violet = _identity(context);
    final violetInk = siteInk(context, violet);
    final hairline = ThemeHelpers.borderLightColor(context);
    // Cliques por link (quando as métricas já foram carregadas) — entram na
    // própria linha do link.
    final clicksByLink = <String, int>{
      for (final item in _analytics?.links ?? const <BioPageLinkAnalytics>[])
        item.linkId: item.clicks,
    };

    return _panelShell(context, _BioTab.links, [
      if (!_canManage) ...[_readOnlyNotice(), const SizedBox(height: 12)],
      if (_linksDraft.isEmpty)
        SiteEmptyState(
          icon: LucideIcons.link,
          title: 'Sua página ainda não tem links',
          body: _canManage
              ? 'Cada link vira um botão na página, na ordem desta lista. '
                    'Comece pelo WhatsApp (wa.me/55 + DDD + número) e depois '
                    'o Instagram, o site ou o catálogo de imóveis.'
              : 'Quem gerencia o Link in Bio adiciona os links — cada um '
                    'vira um botão na página.',
          tone: violet,
          // Criar é o CTA principal da tela vazia: o violeta da tela,
          // escurecido até o rótulo branco passar de 4,5:1.
          action: _canManage
              ? FilledButton.icon(
                  onPressed: _addLink,
                  style: FilledButton.styleFrom(
                    backgroundColor: siteSolid(violet),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                  ),
                  icon: const Icon(LucideIcons.plus, size: 16),
                  label: const SiteButtonLabel('Adicionar o primeiro link'),
                )
              : null,
        )
      else ...[
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: hairline),
              bottom: BorderSide(color: hairline),
            ),
          ),
          child: ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: _linksDraft.length,
            // Linha arrastada ganha chão de card (com filete) para descolar
            // da lista flush.
            proxyDecorator: (child, index, animation) => Material(
              color: ThemeHelpers.cardBackgroundColor(context),
              elevation: 3,
              shadowColor: ThemeHelpers.shadowColor(context),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: siteHairline(context)),
              ),
              child: child,
            ),
            onReorder: !_canManage
                ? (_, _) {}
                : (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final item = _linksDraft.removeAt(oldIndex);
                      _linksDraft.insert(newIndex, item);
                      _reindexLinks();
                      _linksDirty = true;
                    });
                  },
            itemBuilder: (context, index) {
              final link = _linksDraft[index];
              return KeyedSubtree(
                key: ValueKey('bio-link-${link.id}'),
                child: _buildLinkTile(
                  context,
                  link,
                  index,
                  clicksByLink[link.id],
                  isLast: index == _linksDraft.length - 1,
                ),
              );
            },
          ),
        ),
        if (_canManage) ...[
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _addLink,
            style: OutlinedButton.styleFrom(
              foregroundColor: violetInk,
              side: BorderSide(color: violet.withValues(alpha: 0.45)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            icon: const Icon(LucideIcons.plus, size: 16),
            label: const SiteButtonLabel('Adicionar link'),
          ),
        ],
        const SizedBox(height: 12),
        _noteLine(
          context,
          LucideIcons.info,
          'Oculto = continua na lista, mas some da página. Nada vai ao ar '
          'antes de salvar os links.',
        ),
      ],
      SiteSaveBar(
        visible: _canManage && _linksDirty && !_dockFits(context),
        saving: _linksSaving,
        label: 'Salvar links',
        onSave: _saveLinks,
        onDiscard: _discardLinks,
        pendingText: 'Links alterados — a página só muda depois de salvar.',
      ),
    ]);
  }

  /// Linha de link flush: alça de arrastar (à esquerda, longe do
  /// interruptor), plaquinha com o ícone nas cores do cliente, o texto do
  /// botão, o tipo — endereço do link ou selo CAPTAÇÃO —, oculto e cliques;
  /// à direita, o interruptor "aparece na página" e remover. Toque na linha
  /// = editar.
  Widget _buildLinkTile(
    BuildContext context,
    BioPageLink link,
    int index,
    int? clicks, {
    required bool isLast,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final violet = _identity(context);
    final violetInk = siteInk(context, violet);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final active = link.isActive;
    final label = link.label.trim().isEmpty ? 'Sem texto' : link.label.trim();
    final displayUrl = link.url.replaceFirst(RegExp(r'^https?://'), '').trim();
    final numberFmt = NumberFormat.decimalPattern('pt_BR');

    // Cores do cliente = dado (como na página); só no link ativo — o oculto
    // fica cinza para ler "fora da página" de relance.
    final c1 = active ? siteParseHexColor(link.color) : null;
    final c2 = active ? siteParseHexColor(link.color2) : null;
    final List<Color>? paint = c1 == null ? null : [c1, c2 ?? c1];
    final plateFg = paint != null
        ? siteOnColor(Color.lerp(paint.first, paint.last, 0.5)!)
        : (active ? violetInk : secondary);
    final plateTone = active ? violet : secondary;

    final String detail;
    var detailColor = secondary;
    if (link.isLeadForm) {
      detail = 'abre o formulário de nome e telefone';
    } else if (displayUrl.isEmpty) {
      detail = 'sem endereço — toque para completar';
      detailColor = siteInk(context, _amber(context));
    } else {
      detail = displayUrl;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            splashColor: violet.withValues(alpha: 0.08),
            highlightColor: violet.withValues(alpha: 0.04),
            onTap: _canManage ? () => _editLink(index) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  // O toque na alça não abre a edição (o GestureDetector
                  // segura o toque; o arraste segue com o listener).
                  ReorderableDragStartListener(
                    index: index,
                    enabled: _canManage,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                      child: Semantics(
                        label: 'Arrastar para mudar a ordem',
                        child: SizedBox(
                          width: 28,
                          height: 44,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Icon(
                              LucideIcons.gripVertical,
                              size: 18,
                              color: secondary.withValues(
                                alpha: _canManage ? 0.75 : 0.3,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: paint == null
                          ? null
                          : LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: paint,
                            ),
                      color: paint == null
                          ? plateTone.withValues(alpha: isDark ? 0.16 : 0.1)
                          : null,
                      border: paint == null
                          ? Border.all(color: plateTone.withValues(alpha: 0.25))
                          : null,
                    ),
                    child: Icon(bioLinkIcon(link), size: 18, color: plateFg),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: active
                                ? ThemeHelpers.textColor(context)
                                : secondary,
                            letterSpacing: -0.1,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Selos e detalhe em Wrap: com texto grande, o
                        // detalhe desce para a linha de baixo em vez de
                        // espremer os selos.
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (link.isLeadForm)
                              SiteMiniPill(
                                label: 'Captação',
                                tone: violet,
                                icon: LucideIcons.userRoundPlus,
                              ),
                            if (!active)
                              SiteMiniPill(
                                label: 'Oculto',
                                tone: secondary,
                                icon: LucideIcons.eyeOff,
                              ),
                            Text(
                              detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: detailColor,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (clicks != null)
                              Text(
                                '${numberFmt.format(clicks)} '
                                '${clicks == 1 ? 'clique' : 'cliques'}',
                                maxLines: 1,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: ThemeHelpers.textColor(context),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Ligado = aparece na página: verde, como "no ar" (antes
                  // era polegar violeta sobre a trilha vermelha do tema).
                  Semantics(
                    label: active ? 'Aparece na página' : 'Oculto da página',
                    child: Switch.adaptive(
                      value: active,
                      activeThumbColor: Colors.white,
                      activeTrackColor: _green(context),
                      onChanged: !_canManage
                          ? null
                          : (v) {
                              setState(() {
                                _linksDraft = List.of(_linksDraft)
                                  ..[index] = link.copyWith(isActive: v);
                                _linksDirty = true;
                              });
                            },
                    ),
                  ),
                  // Remover é neutro — o vermelho fica só no confirmar do
                  // diálogo de remoção.
                  Tooltip(
                    message: 'Remover link',
                    child: InkResponse(
                      radius: 20,
                      onTap: _canManage ? () => _removeLink(index) : null,
                      child: SizedBox(
                        width: 34,
                        height: 40,
                        child: Icon(
                          LucideIcons.trash2,
                          size: 16,
                          color: secondary.withValues(
                            alpha: _canManage ? 0.8 : 0.35,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (!isLast)
          Container(
            margin: const EdgeInsets.only(left: 77),
            height: 1,
            color: ThemeHelpers.borderLightColor(context),
          ),
      ],
    );
  }

  // ── Métricas ──

  Widget _buildAnalyticsPanel(BuildContext context) {
    final Widget body;
    if (_analyticsLoading || !_analyticsLoaded) {
      body = _buildAnalyticsSkeleton(context);
    } else if (_analyticsError != null) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SiteErrorState(
          message: _analyticsError!,
          statusCode: _analyticsErrorStatus,
          onRetry: () => _loadAnalytics(),
        ),
      );
    } else {
      body = _buildAnalyticsBody(context, _analytics ?? BioPageAnalytics.empty);
    }
    return _panelShell(context, _BioTab.analytics, [
      _buildPeriodSelector(context),
      const SizedBox(height: 14),
      body,
    ]);
  }

  /// Período em controle segmentado (7 / 30 / 90 dias) + atualizar.
  Widget _buildPeriodSelector(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: siteFieldFill(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ThemeHelpers.borderLightColor(context)),
            ),
            child: Row(
              children: [
                for (final days in _kAnalyticsPeriods)
                  Expanded(child: _periodSegment(context, days)),
              ],
            ),
          ),
        ),
        SiteRowAction(
          icon: LucideIcons.refreshCw,
          tooltip: 'Atualizar métricas',
          tone: _identity(context),
          onTap: _analyticsLoading ? null : () => _loadAnalytics(),
        ),
      ],
    );
  }

  Widget _periodSegment(BuildContext context, int days) {
    final selected = _analyticsDays == days;
    final violet = _identity(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(9),
      side: selected
          ? BorderSide(color: violet.withValues(alpha: 0.4))
          : BorderSide.none,
    );
    final VoidCallback? onTap = _analyticsLoading || selected
        ? null
        : () => _loadAnalytics(days: days);
    return Semantics(
      button: true,
      selected: selected,
      label: 'Últimos $days dias',
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: selected
            ? ThemeHelpers.cardBackgroundColor(context)
            : Colors.transparent,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$days dias',
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    color: selected
                        ? siteInk(context, violet)
                        : ThemeHelpers.textSecondaryColor(context),
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _tilesRow(List<Widget> tiles) => [
    for (var i = 0; i < tiles.length; i++) ...[
      if (i > 0) const SizedBox(width: 10),
      Expanded(child: tiles[i]),
    ],
  ];

  Widget _buildAnalyticsBody(BuildContext context, BioPageAnalytics data) {
    final numberFmt = NumberFormat.decimalPattern('pt_BR');
    final ctrFmt = NumberFormat('#,##0.0', 'pt_BR');
    final published = _page!.isPublished;
    final hasViews = data.viewsByDay.any((d) => d.views > 0);
    final totalClicks = data.links.fold<int>(0, (s, l) => s + l.clicks);
    final maxClicks = data.links.fold<int>(
      0,
      (m, l) => l.clicks > m ? l.clicks : m,
    );

    // Número em tinta de texto, cor só no ícone e no medidor — o arco-íris
    // de antes (violeta/azul/âmbar/verde) não dizia nada.
    final tiles = <Widget>[
      _statTile(
        context,
        icon: LucideIcons.eye,
        label: 'Visitas à página',
        value: numberFmt.format(data.pageViews),
      ),
      _statTile(
        context,
        icon: LucideIcons.mousePointerClick,
        label: 'Cliques nos links',
        value: numberFmt.format(data.linkClicks),
      ),
      _statTile(
        context,
        icon: LucideIcons.atSign,
        label: 'Cliques no Instagram',
        value: numberFmt.format(data.instagramClicks),
      ),
      _statTile(
        context,
        icon: LucideIcons.trendingUp,
        label: 'Taxa de cliques',
        value: '${ctrFmt.format(data.clickThroughRate)}%',
        meter: (data.clickThroughRate / 100).clamp(0.0, 1.0).toDouble(),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!published) ...[
          _noteLine(
            context,
            LucideIcons.circleAlert,
            'A página está fora do ar — as visitas só contam depois de '
            'publicar.',
            color: siteInk(context, _amber(context)),
          ),
          const SizedBox(height: 12),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            // 4 lado a lado no tablet; 2×2 no celular. Altura igual por
            // linha: rótulo de 2 linhas não desalinha o número do vizinho.
            if (constraints.maxWidth >= 560) {
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _tilesRow(tiles),
                ),
              );
            }
            return Column(
              children: [
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _tilesRow(tiles.sublist(0, 2)),
                  ),
                ),
                const SizedBox(height: 10),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _tilesRow(tiles.sublist(2)),
                  ),
                ),
              ],
            );
          },
        ),
        if (published && data.pageViews == 0) ...[
          const SizedBox(height: 12),
          _noteLine(
            context,
            LucideIcons.info,
            'Ninguém visitou a página neste período. Coloque o link na bio '
            'do Instagram e mande no WhatsApp para começar.',
          ),
        ],
        if (hasViews) ...[
          const SizedBox(height: 24),
          const SiteSubsectionHeader(
            label: 'Visitas por dia',
            icon: LucideIcons.chartNoAxesColumn,
          ),
          const SizedBox(height: 12),
          _buildViewsChart(context, data),
        ],
        const SizedBox(height: 24),
        const SiteSubsectionHeader(
          label: 'Cliques por link',
          icon: LucideIcons.mousePointerClick,
        ),
        const SizedBox(height: 4),
        if (data.links.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _noteLine(
              context,
              LucideIcons.mousePointerClick,
              'Nenhum clique nos links neste período.',
            ),
          )
        else
          for (var i = 0; i < data.links.length; i++) ...[
            if (i > 0)
              Container(
                height: 1,
                color: ThemeHelpers.borderLightColor(context),
              ),
            _clicksRow(
              context,
              data.links[i],
              maxClicks,
              totalClicks,
              numberFmt,
            ),
          ],
      ],
    );
  }

  Widget _statTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    double? meter,
  }) {
    final theme = Theme.of(context);
    final violet = _identity(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: siteHairline(context)),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon, size: 14, color: siteInk(context, violet)),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: ThemeHelpers.textColor(context),
                letterSpacing: -0.6,
                height: 1.0,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (meter != null) ...[
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: meter.clamp(0.0, 1.0).toDouble(),
                minHeight: 4,
                backgroundColor: violet.withValues(alpha: 0.14),
                valueColor: AlwaysStoppedAnimation<Color>(violet),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildViewsChart(BuildContext context, BioPageAnalytics data) {
    final days = data.viewsByDay;
    final maxViews = days.fold<int>(0, (m, d) => d.views > m ? d.views : m);
    if (days.isEmpty || maxViews == 0) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final violet = _identity(context);
    final numberFmt = NumberFormat.decimalPattern('pt_BR');
    // 90 barras em 288dp: sem vão entre elas; com poucos dias, 2dp.
    final gap = days.length > 60 ? 0.0 : (days.length > 31 ? 1.0 : 2.0);

    String edgeLabel(String iso) {
      final parsed = DateTime.tryParse(iso);
      if (parsed == null) return iso;
      return DateFormat('dd/MM', 'pt_BR').format(parsed);
    }

    String visitsWord(int n) => n == 1 ? 'visita' : 'visitas';

    final edgeStyle = TextStyle(
      fontSize: 10.5,
      color: secondary,
      fontWeight: FontWeight.w600,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 72,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < days.length; i++) ...[
                if (i > 0 && gap > 0) SizedBox(width: gap),
                Expanded(
                  child: Tooltip(
                    message:
                        '${edgeLabel(days[i].date)} — '
                        '${numberFmt.format(days[i].views)} '
                        '${visitsWord(days[i].views)}',
                    child: Container(
                      height: days[i].views <= 0
                          ? 3
                          : (6 + 64 * (days[i].views / maxViews))
                                .clamp(3.0, 72.0)
                                .toDouble(),
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3),
                        ),
                        color: days[i].views <= 0
                            ? violet.withValues(alpha: isDark ? 0.16 : 0.12)
                            : violet.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Container(height: 1, color: ThemeHelpers.borderLightColor(context)),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(edgeLabel(days.first.date), style: edgeStyle),
            Expanded(
              child: Text(
                'pico: ${numberFmt.format(maxViews)} ${visitsWord(maxViews)}',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  color: siteInk(context, violet),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(edgeLabel(days.last.date), style: edgeStyle),
          ],
        ),
      ],
    );
  }

  Widget _clicksRow(
    BuildContext context,
    BioPageLinkAnalytics item,
    int maxClicks,
    int totalClicks,
    NumberFormat fmt,
  ) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final violet = _identity(context);
    final ratio = maxClicks <= 0 ? 0.0 : item.clicks / maxClicks;
    final share = totalClicks <= 0
        ? null
        : (item.clicks * 100 / totalClicks).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.label.trim().isEmpty ? 'Sem texto' : item.label.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                fmt.format(item.clicks),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textColor(context),
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (share != null) ...[
                const SizedBox(width: 6),
                Text(
                  '$share%',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.02, 1.0).toDouble(),
              minHeight: 5,
              backgroundColor: secondary.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(violet),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsSkeleton(BuildContext context) {
    Widget tile() =>
        const Expanded(child: SkeletonBox(height: 92, borderRadius: 14));
    return LayoutBuilder(
      builder: (context, constraints) {
        final four = constraints.maxWidth >= 560;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (four)
              Row(
                children: [
                  tile(),
                  const SizedBox(width: 10),
                  tile(),
                  const SizedBox(width: 10),
                  tile(),
                  const SizedBox(width: 10),
                  tile(),
                ],
              )
            else ...[
              Row(children: [tile(), const SizedBox(width: 10), tile()]),
              const SizedBox(height: 10),
              Row(children: [tile(), const SizedBox(width: 10), tile()]),
            ],
            const SizedBox(height: 24),
            const SkeletonText(width: 120, height: 10),
            const SizedBox(height: 14),
            const SkeletonBox(height: 72, borderRadius: 8),
            const SizedBox(height: 24),
            const SkeletonText(width: 120, height: 10),
            const SizedBox(height: 14),
            for (var i = 0; i < 3; i++) ...[
              const SkeletonText(height: 12),
              const SizedBox(height: 8),
              const SkeletonBox(height: 5, borderRadius: 999),
              const SizedBox(height: 16),
            ],
          ],
        );
      },
    );
  }

  // ─── Esqueleto (espelha o hero, as abas e as linhas de link) ─────────────

  Widget _buildPageSkeleton(BuildContext context, EdgeInsets insets) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Mesma moldura da prévia real (enquanto carrega, o véu é o violeta da
    // tela — ainda não conhecemos as cores dos links).
    final frame = Color.alphaBlend(
      _identity(context).withValues(alpha: isDark ? 0.22 : 0.16),
      siteFieldFill(context),
    );
    final hairline = ThemeHelpers.borderLightColor(context);

    Widget phone(double width) => Container(
      width: width,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: frame,
        borderRadius: BorderRadius.circular(26),
      ),
      child: SkeletonBox(
        height: (width * 1.85).clamp(200.0, 300.0).toDouble(),
        borderRadius: 20,
      ),
    );

    Widget status() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            SkeletonBox(width: 30, height: 30, borderRadius: 999),
            SizedBox(width: 10),
            Expanded(child: SkeletonText(height: 16)),
          ],
        ),
        const SizedBox(height: 10),
        const SkeletonText(height: 10),
        const SizedBox(height: 6),
        const SkeletonText(width: 90, height: 10),
        const SizedBox(height: 18),
        const SkeletonText(width: 64, height: 24),
        const SizedBox(height: 6),
        const SkeletonText(height: 10),
      ],
    );

    Widget address() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SkeletonBox(height: 58, borderRadius: 14),
        const SizedBox(height: 10),
        Row(
          children: const [
            Expanded(child: SkeletonBox(height: 56, borderRadius: 12)),
            SizedBox(width: 8),
            Expanded(child: SkeletonBox(height: 56, borderRadius: 12)),
            SizedBox(width: 8),
            Expanded(child: SkeletonBox(height: 56, borderRadius: 12)),
          ],
        ),
      ],
    );

    Widget linkRow() => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: const [
          SizedBox(width: 28),
          SkeletonBox(width: 38, height: 38, borderRadius: 12),
          SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonText(width: 130, height: 13),
                SizedBox(height: 7),
                SkeletonText(width: 170, height: 10),
              ],
            ),
          ),
          SizedBox(width: 10),
          SkeletonBox(width: 46, height: 26, borderRadius: 999),
          SizedBox(width: 12),
          SkeletonBox(width: 16, height: 18, borderRadius: 4),
          SizedBox(width: 9),
        ],
      ),
    );

    Widget indentedHairline() => Container(
      margin: const EdgeInsets.only(left: 77),
      height: 1,
      color: hairline,
    );

    return Padding(
      padding: insets.copyWith(top: _kPagePadTop, bottom: _kPagePadBottom),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final wide = width >= 560;
          final phoneWidth = wide
              ? 176.0
              : (width * 0.42).clamp(118.0, 168.0).toDouble();
          final Widget hero = wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    phone(phoneWidth),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          status(),
                          const SizedBox(height: 18),
                          address(),
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        phone(phoneWidth),
                        const SizedBox(width: 14),
                        Expanded(child: status()),
                      ],
                    ),
                    const SizedBox(height: 16),
                    address(),
                  ],
                );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              hero,
              const SizedBox(height: 26),
              Row(
                children: const [
                  Expanded(child: SkeletonText(height: 14)),
                  SizedBox(width: 14),
                  Expanded(child: SkeletonText(height: 14)),
                  SizedBox(width: 14),
                  Expanded(child: SkeletonText(height: 14)),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: const [
                  SkeletonBox(width: 3.5, height: 34, borderRadius: 999),
                  SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonText(width: 150, height: 15),
                        SizedBox(height: 6),
                        SkeletonText(height: 10),
                      ],
                    ),
                  ),
                  SizedBox(width: 10),
                  SkeletonBox(width: 34, height: 34, borderRadius: 11),
                ],
              ),
              const SizedBox(height: 16),
              Container(height: 1, color: hairline),
              linkRow(),
              indentedHairline(),
              linkRow(),
              indentedHairline(),
              linkRow(),
            ],
          );
        },
      ),
    );
  }
}
