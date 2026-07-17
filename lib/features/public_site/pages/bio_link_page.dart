import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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

/// Tela **Link in Bio** — a própria bio page é a heroína: um mock compacto
/// de telefone (moldura tingida pela cor da bio) mostra avatar, nome,
/// @handle e os botões de link reais em miniatura; ao lado, o painel de
/// identidade: status rico, URL como chip com ações e mini-stats. O acento
/// da tela inteira é o VIOLETA (identidade de bio/criador) — o vermelho da
/// marca só existe no confirmar dos diálogos destrutivos e no erro de slug
/// em uso. Abaixo, edição em abas com sublinhado, conteúdo flush e ações no
/// próprio item. Paridade com `BioLinkConfigPage.tsx` (as etapas viáveis em
/// mobile — templates/customização Premium ficam no painel web; devolvemos
/// `customization` intacta para não apagar nada).
class BioLinkPage extends StatefulWidget {
  const BioLinkPage({super.key});

  @override
  State<BioLinkPage> createState() => _BioLinkPageState();
}

class _BioLinkPageState extends State<BioLinkPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 88;
  static const double _kSectionGap = 12;

  static const List<int> _kAnalyticsPeriods = [7, 30, 90];

  _BioTab _activeTab = _BioTab.links;

  BioPageConfig? _page;
  bool _loading = true;
  String? _error;

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
  // confirmar dos diálogos destrutivos e ao erro de slug já em uso. Assim,
  // violeta (identidade) + verde (publicada) + âmbar (rascunho) convivem
  // sem nunca encostar verde em vermelho.

  Color _accent(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.status.purpleDarkMode
        : AppColors.status.purple;
  }

  /// Tinta do hero — a cor custom da própria bio quando existir (primeiro
  /// link ativo com cor definida); caso contrário, o violeta da tela.
  Color _heroTint(BuildContext context) {
    for (final link in _linksDraft) {
      if (!link.isActive) continue;
      final custom = siteParseHexColor(link.color);
      if (custom != null) return custom;
    }
    return _accent(context);
  }

  // ─── Dados ────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await BioPageService.instance.getPage();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _applyPage(res.data!, resetDrafts: true);
      } else {
        _error = res.message ?? 'Erro ao carregar a página Link in Bio';
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
    });
    if (!res.success) {
      _showSnack(res.message ?? 'Erro ao carregar as métricas');
    }
  }

  // ─── Ações ────────────────────────────────────────────────────────────────

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
    );
  }

  Future<void> _copyUrl() async {
    final url = _page?.bestPublicUrl;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    _showSnack('URL copiada');
  }

  Future<void> _openPage() async {
    final url = _page?.bestPublicUrl;
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) _showSnack('Não foi possível abrir a página');
  }

  Future<void> _togglePublish() async {
    final page = _page;
    if (page == null || _publishing) return;

    if (page.isPublished) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Despublicar página?'),
          content: const Text(
            'Sua página sai do ar imediatamente e o link da bio deixa de '
            'funcionar. Você pode publicá-la novamente quando quiser.',
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
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).brightness == Brightness.dark
                    ? AppColors.status.errorDarkMode
                    : AppColors.status.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Despublicar'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    } else if ((page.slug ?? '').trim().isEmpty) {
      _showSnack('Defina a URL pública na aba Perfil antes de publicar');
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
        res.data!.isPublished ? 'Página no ar' : 'Página despublicada',
      );
    } else {
      _showSnack(res.message ?? 'Erro ao alterar a publicação');
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
        _applyPage(res.data!, resetDrafts: true);
      }
    });
    _showSnack(
      res.success ? 'Perfil salvo' : (res.message ?? 'Erro ao salvar o perfil'),
    );
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
      _showSnack('O endereço precisa de pelo menos 3 caracteres');
      return;
    }
    if (_slugAvailable == false) {
      _showSnack('Este endereço já está em uso — escolha outro');
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
    _showSnack(
      res.success
          ? 'URL atualizada'
          : (res.message ?? 'Endereço inválido ou reservado'),
    );
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remover link?'),
        content: Text(
          link.label.trim().isEmpty
              ? 'O link sai da página quando você salvar.'
              : '"${link.label.trim()}" sai da página quando você salvar. '
                    'Para ocultar sem excluir, desative o interruptor do link.',
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
              backgroundColor: Theme.of(ctx).brightness == Brightness.dark
                  ? AppColors.status.errorDarkMode
                  : AppColors.status.error,
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
    _showSnack(
      res.success ? 'Links salvos' : (res.message ?? 'Erro ao salvar os links'),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

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
    return AppScaffold(
      title: 'Link in Bio',
      showBottomNavigation: false,
      body: RefreshIndicator(
        color: _accent(context),
        onRefresh: () async {
          await _load();
          if (_analyticsLoaded) await _loadAnalytics();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: _loading
              ? [_buildPageSkeleton(context)]
              : _error != null
              ? [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _kPagePadH,
                      48,
                      _kPagePadH,
                      _kPagePadBottom,
                    ),
                    child: SiteErrorState(message: _error!, onRetry: _load),
                  ),
                ]
              : [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _kPagePadH,
                      _kPagePadTop,
                      _kPagePadH,
                      0,
                    ),
                    child: _buildPhoneHero(context),
                  ),
                  const SizedBox(height: _kSectionGap + 2),
                  _buildTabsRail(context),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _kPagePadH,
                      _kSectionGap,
                      _kPagePadH,
                      _kPagePadBottom,
                    ),
                    child: _buildActivePanel(context),
                  ),
                ],
        ),
      ),
    );
  }

  // ─── Hero: a bio page é a protagonista (mock de telefone) ────────────────

  Widget _buildPhoneHero(BuildContext context) {
    final activeLinks = _linksDraft
        .where((l) => l.isActive)
        .toList(growable: false);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPhoneMock(context, activeLinks),
        const SizedBox(width: 18),
        // Painel de identidade — flush, sem card em volta: status rico,
        // URL como chip e o par de mini-stats, em cascata.
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              _buildHeroStatus(context)
                  .animate()
                  .fadeIn(delay: 60.ms, duration: 280.ms)
                  .moveY(begin: 6, end: 0, curve: Curves.easeOut),
              const SizedBox(height: 16),
              _buildHeroUrl(context)
                  .animate()
                  .fadeIn(delay: 130.ms, duration: 280.ms)
                  .moveY(begin: 6, end: 0, curve: Curves.easeOut),
              const SizedBox(height: 16),
              _buildHeroMiniStats(context)
                  .animate()
                  .fadeIn(delay: 200.ms, duration: 280.ms)
                  .moveY(begin: 6, end: 0, curve: Curves.easeOut),
            ],
          ),
        ),
      ],
    );
  }

  /// Status da página — tira flush entre hairlines: roundel semântico com
  /// ícone (globo no ar / lápis em rascunho), título forte com dot de halo e
  /// linha viva do endereço. Sem caixa, sem pill solta.
  Widget _buildHeroStatus(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final hairline =
        ThemeHelpers.borderLightColor(context).withValues(alpha: 0.55);
    final emerald = isDark
        ? AppColors.status.greenDarkMode
        : AppColors.status.green;
    final amber = isDark
        ? AppColors.status.warningDarkMode
        : AppColors.status.warning;
    final published = _page!.isPublished;
    final tone = published ? emerald : amber;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: hairline),
          bottom: BorderSide(color: hairline),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tone.withValues(alpha: isDark ? 0.16 : 0.12),
              border: Border.all(color: tone.withValues(alpha: 0.35)),
            ),
            child: Icon(
              published ? LucideIcons.globe : LucideIcons.pencilLine,
              size: 14,
              color: tone,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        published ? 'Página publicada' : 'Rascunho',
                        softWrap: false,
                        overflow: TextOverflow.fade,
                        style: TextStyle(
                          color: tone,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          letterSpacing: -0.15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: tone,
                        boxShadow: [
                          BoxShadow(
                            color:
                                tone.withValues(alpha: isDark ? 0.55 : 0.45),
                            blurRadius: 5,
                            spreadRadius: 1.2,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  published
                      ? 'Recebendo visitas em $kBioPublicBase'
                      : 'Só você vê — publique quando estiver pronta',
                  maxLines: 2,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: published ? secondary : amber,
                    fontWeight: published ? FontWeight.w600 : FontWeight.w700,
                    fontSize: 10.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Microlinha de apoio sob um campo — ícone 12px + texto de uma linha.
  Widget _fieldMeta(
    BuildContext context, {
    required IconData icon,
    required String text,
    bool highlight = false,
  }) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final tone =
        highlight ? _accent(context) : secondary.withValues(alpha: 0.85);
    return Row(
      children: [
        Icon(icon, size: 11.5, color: tone),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
              color: tone,
              letterSpacing: -0.05,
            ),
          ),
        ),
      ],
    );
  }

  /// Contador vivo da bio — esquenta para âmbar perto do limite.
  Widget _bioCounter(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final amber = isDark
        ? AppColors.status.warningDarkMode
        : AppColors.status.warning;
    final len = _bioController.text.length;
    final tone = len >= 260 ? amber : secondary.withValues(alpha: 0.8);
    return Text(
      '$len/280',
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        color: tone,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  /// URL como chip elegante — /slug em destaque, domínio esmaecido e as
  /// ações Copiar/Abrir como icon-chips neutros 32px lado a lado.
  Widget _buildHeroUrl(BuildContext context) {
    final theme = Theme.of(context);
    final violet = _accent(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final page = _page!;
    final slug = (page.slug ?? '').trim();
    final hasUrl = page.bestPublicUrl != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          kBioPublicBase,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: secondary.withValues(alpha: 0.85),
            fontWeight: FontWeight.w700,
            fontSize: 9.5,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Expanded(
              // FittedBox em vez de reticências — a URL nunca trunca.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  slug.isEmpty ? 'URL não definida' : '/$slug',
                  maxLines: 1,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                    color: slug.isEmpty ? secondary : violet,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _heroIconChip(
              context,
              icon: LucideIcons.copy,
              tooltip: 'Copiar URL',
              onTap: hasUrl ? _copyUrl : null,
            ),
            const SizedBox(width: 6),
            _heroIconChip(
              context,
              icon: LucideIcons.externalLink,
              tooltip: 'Abrir página',
              onTap: hasUrl ? _openPage : null,
            ),
          ],
        ),
        if (slug.isEmpty) ...[
          const SizedBox(height: 3),
          Text(
            'Defina o endereço na aba Perfil',
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondary,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  /// Icon-chip neutro 32px — ação rápida ao lado da URL.
  Widget _heroIconChip(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    VoidCallback? onTap,
  }) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final disabled = onTap == null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: ThemeHelpers.borderColor(
                  context,
                ).withValues(alpha: disabled ? 0.5 : 1),
              ),
            ),
            child: Icon(
              icon,
              size: 15,
              color: disabled ? secondary.withValues(alpha: 0.4) : secondary,
            ),
          ),
        ),
      ),
    );
  }

  /// Par de mini-stats — número tabular w800 + label overline.
  Widget _buildHeroMiniStats(BuildContext context) {
    final violet = _accent(context);
    final numberFmt = NumberFormat.decimalPattern('pt_BR');
    final visible = _linksDraft.where((l) => l.isActive).length;
    final views = _analytics?.pageViews;

    return Row(
      children: [
        Expanded(
          child: _heroMiniStat(
            context,
            value: numberFmt.format(visible),
            label: visible == 1 ? 'Link visível' : 'Links visíveis',
            valueColor: violet,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          // Views entram quando as métricas já foram carregadas; antes
          // disso, o total de links mantém o par sempre completo.
          child: views != null
              ? _heroMiniStat(
                  context,
                  value: numberFmt.format(views),
                  label: 'Views · ${_analyticsDays}d',
                  valueColor: ThemeHelpers.textColor(context),
                )
              : _heroMiniStat(
                  context,
                  value: numberFmt.format(_linksDraft.length),
                  label: 'No total',
                  valueColor: ThemeHelpers.textColor(context),
                ),
        ),
      ],
    );
  }

  Widget _heroMiniStat(
    BuildContext context, {
    required String value,
    required String label,
    required Color valueColor,
  }) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          softWrap: false,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            color: valueColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: secondary,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
            fontSize: 8.5,
          ),
        ),
      ],
    );
  }

  /// Mock de "telefone" com a bio page em miniatura — avatar, nome, @handle,
  /// bio e os primeiros botões de link reais (cores customizadas incluídas).
  Widget _buildPhoneMock(BuildContext context, List<BioPageLink> activeLinks) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tint = _heroTint(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final page = _page!;

    final title = (page.title ?? '').trim();
    final handle = (page.instagramHandle ?? '').trim().replaceFirst(
      RegExp(r'^@+'),
      '',
    );
    final bio = (page.bio ?? '').trim();
    final shown = activeLinks.take(3).toList(growable: false);
    final extra = activeLinks.length - shown.length;

    final screenBase = isDark
        ? AppColors.background.backgroundSecondaryDarkMode
        : Colors.white;

    return Container(
          width: 168,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            // Moldura tingida pela cor da própria bio (nunca o vermelho da
            // marca), com um brilho suave da mesma tinta atrás do aparelho.
            color: Color.alphaBlend(
              tint.withValues(alpha: isDark ? 0.30 : 0.24),
              isDark ? const Color(0xFF191627) : const Color(0xFF201C2E),
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: tint.withValues(alpha: isDark ? 0.28 : 0.20),
                blurRadius: 26,
                spreadRadius: -4,
                offset: const Offset(0, 10),
              ),
              ...ThemeHelpers.cardShadow(context),
            ],
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(21),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.alphaBlend(
                    tint.withValues(alpha: isDark ? 0.16 : 0.09),
                    screenBase,
                  ),
                  screenBase,
                ],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // "Câmera" do aparelho
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: secondary.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Center(child: _mockAvatar(context, tint, title)),
                const SizedBox(height: 8),
                Text(
                  title.isEmpty ? 'Sua página' : title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
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
                  const SizedBox(height: 6),
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
                const SizedBox(height: 12),
                if (shown.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
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
                    _mockLinkButton(context, shown[i], tint, isDark),
                  ],
                if (extra > 0) ...[
                  const SizedBox(height: 8),
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
        )
        .animate()
        .fadeIn(duration: 300.ms)
        .moveY(begin: 8, end: 0, curve: Curves.easeOut);
  }

  Widget _mockAvatar(BuildContext context, Color accent, String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final avatarUrl = (_page!.avatarUrl ?? '').trim();
    final initial = title.isNotEmpty ? title[0].toUpperCase() : null;
    return Container(
      width: 46,
      height: 46,
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
              errorBuilder: (_, _, _) =>
                  _mockAvatarFallback(accent, initial),
            )
          : _mockAvatarFallback(accent, initial),
    );
  }

  Widget _mockAvatarFallback(Color accent, String? initial) {
    return Center(
      child: initial != null
          ? Text(
              initial,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: accent,
              ),
            )
          : Icon(LucideIcons.userRound, size: 18, color: accent),
    );
  }

  Widget _mockLinkButton(
    BuildContext context,
    BioPageLink link,
    Color accent,
    bool isDark,
  ) {
    final Color? c1 = siteParseHexColor(link.color);
    final Color c2 = siteParseHexColor(link.color2) ?? c1 ?? accent;
    final fg = c1 != null
        ? (ThemeData.estimateBrightnessForColor(c1) == Brightness.dark
              ? Colors.white
              : const Color(0xFF1F2937))
        : accent;
    final label = link.label.trim().isEmpty ? 'Sem texto' : link.label.trim();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: c1 != null ? LinearGradient(colors: [c1, c2]) : null,
        color: c1 != null
            ? null
            : accent.withValues(alpha: isDark ? 0.2 : 0.12),
        border: c1 != null
            ? null
            : Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_linkIcon(link.url), size: 10, color: fg),
          const SizedBox(width: 5),
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

  Widget _buildTabsRail(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: _kPagePadH - 8),
      child: Row(
        children: [
          for (final tab in _BioTab.values)
            Expanded(
              child: SiteFlushTab(
                icon: _tabIcon(tab),
                label: _tabLabel(tab),
                count: tab == _BioTab.links ? _linksDraft.length : null,
                tone: _accent(context),
                selected: _activeTab == tab,
                onTap: () {
                  setState(() => _activeTab = tab);
                  if (tab == _BioTab.analytics && !_analyticsLoaded) {
                    _loadAnalytics();
                  }
                },
              ),
            ),
        ],
      ),
    );
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

  ({String eyebrow, String title, String hint}) _panelMeta(_BioTab tab) {
    switch (tab) {
      case _BioTab.profile:
        return (
          eyebrow: 'Perfil',
          title: 'Como sua página se apresenta',
          hint: 'Nome, bio, Instagram e o endereço público da página.',
        );
      case _BioTab.links:
        return (
          eyebrow: 'Links',
          title: 'Monte a lista de botões',
          hint: 'A ordem da lista é a ordem na página. Oculte sem excluir.',
        );
      case _BioTab.analytics:
        return (
          eyebrow: 'Métricas',
          title: 'Desempenho da página',
          hint: 'Visualizações, cliques e conversão no período escolhido.',
        );
    }
  }

  /// Cabeçalho de seção — barra tonal violeta 18×2.5 + eyebrow + título
  /// w900. Mesma anatomia em TODAS as seções da tela.
  Widget _sectionHeader(
    BuildContext context, {
    required String eyebrow,
    required String title,
    String? hint,
  }) {
    final theme = Theme.of(context);
    final violet = _accent(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 18,
          height: 2.5,
          decoration: BoxDecoration(
            color: violet,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          eyebrow.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: violet,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.3,
            fontSize: 9.5,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          title,
          // Sem maxLines de propósito — título nunca trunca, quebra linha.
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: ThemeHelpers.textColor(context),
            letterSpacing: -0.3,
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(
            hint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              height: 1.32,
            ),
          ),
        ],
      ],
    );
  }

  Widget _panelShell(BuildContext context, _BioTab tab, List<Widget> body) {
    final meta = _panelMeta(tab);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Entrada em cascata: cabeçalho primeiro, corpo logo atrás.
        _sectionHeader(
              context,
              eyebrow: meta.eyebrow,
              title: meta.title,
              hint: meta.hint,
            )
            .animate()
            .fadeIn(duration: 240.ms)
            .moveY(begin: 8, end: 0, curve: Curves.easeOut),
        const SizedBox(height: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body)
            .animate()
            .fadeIn(delay: 70.ms, duration: 260.ms)
            .moveY(begin: 10, end: 0, curve: Curves.easeOut),
      ],
    );
  }

  Widget _readOnlyNotice(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final amber = isDark
        ? AppColors.status.warningDarkMode
        : AppColors.status.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: amber.withValues(alpha: isDark ? 0.12 : 0.08),
        border: Border.all(color: amber.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.lock, size: 14, color: amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Somente leitura — para editar, solicite ao administrador a '
              'permissão de gerenciar o Link in Bio.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
                height: 1.3,
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Perfil & URL ──

  Widget _buildProfilePanel(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final page = _page!;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final emerald = isDark
        ? AppColors.status.greenDarkMode
        : AppColors.status.green;
    final amber = isDark
        ? AppColors.status.warningDarkMode
        : AppColors.status.warning;
    final danger = isDark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;
    final statusTone = page.isPublished ? emerald : amber;
    final dateFmt = DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR');

    final currentSlug = (page.slug ?? '').trim();
    final draftSlug = _slugController.text.trim();
    final slugChanged = draftSlug != currentSlug;

    void markDirty(String _) {
      if (!_profileDirty) setState(() => _profileDirty = true);
    }

    return _panelShell(context, _BioTab.profile, [
      if (!_canManage)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _readOnlyNotice(context),
        ),
      // Card de publicação — ação principal no próprio card.
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: statusTone.withValues(alpha: isDark ? 0.12 : 0.07),
          border: Border.all(color: statusTone.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  page.isPublished
                      ? LucideIcons.circleCheckBig
                      : LucideIcons.circleDashed,
                  size: 18,
                  color: statusTone,
                ),
                const SizedBox(width: 8),
                Text(
                  page.isPublished ? 'PÁGINA PUBLICADA' : 'PÁGINA EM RASCUNHO',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: statusTone,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              page.isPublished
                  ? (page.publishedAt != null
                        ? 'Publicada em ${dateFmt.format(page.publishedAt!.toLocal())}.'
                        : 'Sua página está visível para qualquer visitante.')
                  : 'Quando os links estiverem prontos, publique para o '
                        'endereço da bio começar a funcionar.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondary,
                height: 1.4,
              ),
            ),
            if (_canManage) ...[
              const SizedBox(height: 14),
              // Publicada: despublicar é ação DISCRETA e neutra — o vermelho
              // fica só no botão confirmar do diálogo. Rascunho: publicar é
              // o "vá" — verde cheio.
              SizedBox(
                width: double.infinity,
                child: page.isPublished
                    ? OutlinedButton.icon(
                        onPressed: _publishing ? null : _togglePublish,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: secondary,
                          side: BorderSide(
                            color: ThemeHelpers.borderColor(context),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
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
                            : const Icon(LucideIcons.cloudOff, size: 17),
                        label: Text(
                          _publishing ? 'Aguarde…' : 'Despublicar página',
                          softWrap: false,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      )
                    : FilledButton.icon(
                        onPressed: _publishing ? null : _togglePublish,
                        style: FilledButton.styleFrom(
                          backgroundColor: emerald,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
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
                        label: Text(
                          _publishing ? 'Aguarde…' : 'Publicar página',
                          softWrap: false,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 20),
      _sectionHeader(context, eyebrow: 'Endereço', title: 'URL pública'),
      const SizedBox(height: 12),
      SiteFilledField(
        controller: _slugController,
        label: 'Endereço da página',
        hint: 'minha-imobiliaria',
        prefixText: '$kBioPublicBase/',
        keyboardType: TextInputType.url,
        enabled: _canManage,
        onChanged: _onSlugChanged,
        accent: _accent(context),
      ),
      if (slugChanged && draftSlug.isNotEmpty) ...[
        const SizedBox(height: 7),
        Row(
          children: [
            if (_slugChecking) ...[
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: secondary,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                'Verificando disponibilidade…',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: secondary,
                  fontSize: 11.5,
                ),
              ),
            ] else if (draftSlug.length < 3) ...[
              Icon(LucideIcons.circleAlert, size: 13, color: amber),
              const SizedBox(width: 6),
              Text(
                'Mínimo de 3 caracteres',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: amber,
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                ),
              ),
            ] else if (_slugAvailable == true) ...[
              Icon(LucideIcons.circleCheckBig, size: 13, color: emerald),
              const SizedBox(width: 6),
              Text(
                'Disponível — toque em Salvar URL',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: emerald,
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                ),
              ),
            ] else if (_slugAvailable == false) ...[
              Icon(LucideIcons.circleX, size: 13, color: danger),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Este endereço já está em uso por outra empresa',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: danger,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed:
              _canManage &&
                  !_slugSaving &&
                  slugChanged &&
                  draftSlug.length >= 3 &&
                  _slugAvailable != false
              ? _saveSlug
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: emerald,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
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
              : const Icon(LucideIcons.save, size: 16),
          label: Text(
            _slugSaving
                ? 'Salvando…'
                : (slugChanged || currentSlug.isEmpty
                      ? 'Salvar URL'
                      : 'URL salva'),
            softWrap: false,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.info, size: 13, color: secondary),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              'Sem DNS e sem configuração — a Intellisys hospeda em '
              '$kBioPublicBase e você só escolhe a parte final do endereço.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondary,
                height: 1.35,
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      _sectionHeader(
        context,
        eyebrow: 'Apresentação',
        title: 'Nome, bio e Instagram',
      ),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SiteFilledField(
                  controller: _titleController,
                  label: 'Nome ou título',
                  hint: 'Sua imobiliária',
                  icon: LucideIcons.store,
                  enabled: _canManage,
                  onChanged: (v) {
                    markDirty(v);
                    setState(() {});
                  },
                  accent: _accent(context),
                ),
                const SizedBox(height: 5),
                _fieldMeta(
                  context,
                  icon: LucideIcons.type,
                  text: 'Título no topo da sua página',
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                  accent: _accent(context),
                ),
                const SizedBox(height: 5),
                _fieldMeta(
                  context,
                  icon: LucideIcons.link2,
                  text: _instagramController.text.trim().isEmpty
                      ? 'Vira o botão do seu perfil'
                      : 'instagram.com/'
                          '${_instagramController.text.trim().replaceAll('@', '')}',
                  highlight: _instagramController.text.trim().isNotEmpty,
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      SiteFilledField(
        controller: _bioController,
        label: 'Bio',
        hint: 'Conte em poucas palavras o que o visitante encontra aqui…',
        maxLines: 3,
        maxLength: 280,
        enabled: _canManage,
        onChanged: (v) {
          markDirty(v);
          setState(() {});
        },
        accent: _accent(context),
      ),
      const SizedBox(height: 5),
      Row(
        children: [
          Expanded(
            child: _fieldMeta(
              context,
              icon: LucideIcons.alignLeft,
              text: 'Aparece logo abaixo do seu nome',
            ),
          ),
          _bioCounter(context),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.image, size: 13, color: secondary),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              'Foto de perfil, template e customização Premium são ajustados '
              'no painel web — aqui você cuida do texto, da URL e dos links.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondary,
                height: 1.35,
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ),
      SiteSaveBar(
        visible: _canManage && _profileDirty,
        saving: _profileSaving,
        label: 'Salvar perfil',
        onSave: _saveProfile,
        onDiscard: () {
          setState(() {
            _profileDirty = false;
            _applyPage(_page!, resetDrafts: true);
          });
        },
      ),
    ]);
  }

  // ── Links ──

  Widget _buildLinksPanel(BuildContext context) {
    final theme = Theme.of(context);
    final tone = _accent(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    // Cliques por link (quando as métricas já foram carregadas) — entram
    // como microlinha na própria linha do link.
    final clicksByLink = <String, int>{
      for (final item in _analytics?.links ?? const <BioPageLinkAnalytics>[])
        item.linkId: item.clicks,
    };

    return _panelShell(context, _BioTab.links, [
      if (!_canManage)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _readOnlyNotice(context),
        ),
      if (_linksDraft.isEmpty)
        SiteEmptyState(
          icon: LucideIcons.link,
          title: 'Nenhum link ainda',
          body:
              'Adicione WhatsApp, site, catálogo de imóveis ou formulário — '
              'os botões aparecem na página na ordem da lista.',
          tone: tone,
          action: _canManage
              ? FilledButton.icon(
                  onPressed: _addLink,
                  style: FilledButton.styleFrom(
                    backgroundColor: tone,
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
                  label: const Text(
                    'Adicionar o primeiro link',
                    softWrap: false,
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                )
              : null,
        )
      else ...[
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: _linksDraft.length,
          // Linha arrastada ganha chão de card para descolar da lista flush.
          proxyDecorator: (child, index, animation) => Material(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: BorderRadius.circular(14),
            elevation: 3,
            shadowColor: Colors.black.withValues(alpha: 0.3),
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
        if (_canManage) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _addLink,
            style: OutlinedButton.styleFrom(
              foregroundColor: tone,
              side: BorderSide(color: tone.withValues(alpha: 0.45)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            icon: const Icon(LucideIcons.plus, size: 16),
            label: const Text(
              'Adicionar link',
              softWrap: false,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.gripVertical, size: 13, color: secondary),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Arraste pela alça à direita para reordenar e toque no '
                  'link para editar. O ícone do botão é detectado pela URL. '
                  'As alterações só vão ao ar depois de salvar.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondary,
                    height: 1.35,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
      SiteSaveBar(
        visible: _canManage && _linksDirty,
        saving: _linksSaving,
        label: 'Salvar links',
        onSave: _saveLinks,
        onDiscard: () {
          setState(() {
            _linksDraft = List.of(_page!.links);
            _linksDirty = false;
          });
        },
      ),
    ]);
  }

  IconData _linkIcon(String url) {
    final u = url.toLowerCase();
    if (u.contains('wa.me') || u.contains('whatsapp')) {
      return LucideIcons.messageCircle;
    }
    // Lucide removeu os ícones de marca — usamos equivalentes semânticos.
    if (u.contains('instagram.com')) return LucideIcons.camera;
    if (u.contains('youtube.com') || u.contains('youtu.be')) {
      return LucideIcons.circlePlay;
    }
    if (u.contains('facebook.com') || u.contains('fb.com')) {
      return LucideIcons.thumbsUp;
    }
    if (u.contains('linkedin.com')) return LucideIcons.briefcaseBusiness;
    if (u.contains('tiktok.com')) return LucideIcons.music2;
    if (u.contains('t.me') || u.contains('telegram')) return LucideIcons.send;
    if (u.startsWith('mailto:')) return LucideIcons.mail;
    if (u.startsWith('tel:')) return LucideIcons.phone;
    return LucideIcons.globe;
  }

  /// Linha de link flush — plate 40px pintado com a cor custom do link
  /// (gradiente quando houver `color2`; fallback violeta tonal), título
  /// w700, URL esmaecida, cliques quando houver métrica, switch violeta e
  /// alça de arraste discreta à direita. Hairline indentado na régua do
  /// texto separa as linhas.
  Widget _buildLinkTile(
    BuildContext context,
    BioPageLink link,
    int index,
    int? clicks, {
    required bool isLast,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final violet = _accent(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final active = link.isActive;
    final displayUrl = link.url.replaceFirst(RegExp(r'^https?://'), '').trim();
    final numberFmt = NumberFormat.decimalPattern('pt_BR');

    final Color? c1 = active ? siteParseHexColor(link.color) : null;
    final Color? c2 = active ? siteParseHexColor(link.color2) : null;
    final plateFg = c1 != null
        ? (ThemeData.estimateBrightnessForColor(c1) == Brightness.dark
              ? Colors.white
              : const Color(0xFF1F2937))
        : (active ? violet : secondary.withValues(alpha: 0.75));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            splashColor: violet.withValues(alpha: 0.08),
            highlightColor: violet.withValues(alpha: 0.04),
            onTap: _canManage ? () => _editLink(index) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      gradient: c1 != null
                          ? LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [c1, c2 ?? c1],
                            )
                          : null,
                      color: c1 != null
                          ? null
                          : (active
                                ? violet.withValues(
                                    alpha: isDark ? 0.18 : 0.10,
                                  )
                                : secondary.withValues(
                                    alpha: isDark ? 0.14 : 0.09,
                                  )),
                    ),
                    child: Icon(_linkIcon(link.url), size: 18, color: plateFg),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                link.label.trim().isEmpty
                                    ? 'Sem texto'
                                    : link.label.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: active
                                      ? ThemeHelpers.textColor(context)
                                      : secondary,
                                  letterSpacing: -0.1,
                                ),
                              ),
                            ),
                            if (!active) ...[
                              const SizedBox(width: 7),
                              SiteMiniPill(
                                label: 'Oculto',
                                tone: secondary,
                                icon: LucideIcons.eyeOff,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          displayUrl.isEmpty ? '—' : displayUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: secondary,
                            fontSize: 11.5,
                          ),
                        ),
                        if (clicks != null) ...[
                          const SizedBox(height: 3),
                          Text.rich(
                            TextSpan(
                              text: numberFmt.format(clicks),
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: active ? violet : secondary,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                              children: [
                                TextSpan(
                                  text: clicks == 1 ? ' clique' : ' cliques',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: secondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Switch.adaptive(
                    value: active,
                    activeThumbColor: violet,
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
                  // Remover é neutro — o vermelho fica só no botão confirmar
                  // do diálogo de remoção.
                  Tooltip(
                    message: 'Remover link',
                    child: InkResponse(
                      radius: 18,
                      onTap: _canManage ? () => _removeLink(index) : null,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          LucideIcons.trash2,
                          size: 16,
                          color: secondary.withValues(
                            alpha: _canManage ? 0.75 : 0.35,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Alça de arraste discreta à direita.
                  ReorderableDragStartListener(
                    index: index,
                    enabled: _canManage,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 6, 0, 6),
                      child: Icon(
                        LucideIcons.gripVertical,
                        size: 16,
                        color: secondary.withValues(
                          alpha: _canManage ? 0.55 : 0.3,
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
            margin: const EdgeInsets.only(left: 52),
            height: 1,
            color: ThemeHelpers.borderLightColor(
              context,
            ).withValues(alpha: 0.55),
          ),
      ],
    );
  }

  // ── Analytics ──

  Widget _buildAnalyticsPanel(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = _accent(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final page = _page!;

    return _panelShell(context, _BioTab.analytics, [
      // Chips de período — grid alinhado, ação de atualizar na própria linha.
      Row(
        children: [
          for (final days in _kAnalyticsPeriods) ...[
            Expanded(child: _periodChip(context, days, tone)),
            const SizedBox(width: 8),
          ],
          SiteRowAction(
            icon: LucideIcons.refreshCw,
            tooltip: 'Atualizar',
            tone: tone,
            onTap: _analyticsLoading ? null : () => _loadAnalytics(),
          ),
        ],
      ),
      const SizedBox(height: 14),
      if (_analyticsLoading)
        _buildAnalyticsSkeleton(context)
      else if (_analytics == null)
        SiteEmptyState(
          icon: LucideIcons.chartLine,
          title: page.isPublished ? 'Sem métricas ainda' : 'Página fora do ar',
          body: page.isPublished
              ? 'Assim que alguém visitar sua página, as métricas '
                    'aparecem aqui.'
              : 'Publique a página para começar a coletar visualizações e '
                    'cliques.',
          tone: tone,
          action: OutlinedButton.icon(
            onPressed: () => _loadAnalytics(),
            style: OutlinedButton.styleFrom(
              foregroundColor: tone,
              side: BorderSide(color: tone.withValues(alpha: 0.45)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 11,
              ),
            ),
            icon: const Icon(LucideIcons.refreshCw, size: 15),
            label: const Text(
              'Atualizar',
              softWrap: false,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        )
      else
        ..._buildAnalyticsBody(context, theme, isDark, tone, secondary),
    ]);
  }

  Widget _periodChip(BuildContext context, int days, Color tone) {
    final selected = _analyticsDays == days;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: selected
          ? tone.withValues(alpha: isDark ? 0.2 : 0.12)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: _analyticsLoading || selected
            ? null
            : () => _loadAnalytics(days: days),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected
                  ? tone.withValues(alpha: 0.45)
                  : ThemeHelpers.borderColor(context),
            ),
          ),
          child: Center(
            child: Text(
              '$days dias',
              style: TextStyle(
                color: selected ? tone : secondary,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                fontSize: 12.5,
                letterSpacing: -0.1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildAnalyticsBody(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    Color tone,
    Color secondary,
  ) {
    final data = _analytics!;
    final numberFmt = NumberFormat.decimalPattern('pt_BR');
    final ctrFmt = NumberFormat('#,##0.0', 'pt_BR');
    final emerald = isDark
        ? AppColors.status.greenDarkMode
        : AppColors.status.green;
    final blue = isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
    // Âmbar categórico para o Instagram — vermelho de status é só erro.
    final amber = isDark
        ? AppColors.status.warningDarkMode
        : AppColors.status.warning;
    final maxClicks = data.links.isEmpty
        ? 0
        : data.links.map((l) => l.clicks).reduce((a, b) => a > b ? a : b);

    return [
      // Grade 2×2 de estatísticas — cor por significado: views no violeta
      // da tela, cliques em azul, Instagram em âmbar, conversão em verde.
      Row(
        children: [
          Expanded(
            child: _statTile(
              context,
              LucideIcons.eye,
              'Visualizações',
              numberFmt.format(data.pageViews),
              tone,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _statTile(
              context,
              LucideIcons.mousePointerClick,
              'Cliques',
              numberFmt.format(data.linkClicks),
              blue,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: _statTile(
              context,
              LucideIcons.camera,
              'Instagram',
              numberFmt.format(data.instagramClicks),
              amber,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _statTile(
              context,
              LucideIcons.trendingUp,
              'Taxa de cliques',
              '${ctrFmt.format(data.clickThroughRate)}%',
              emerald,
              meter: (data.clickThroughRate / 100).clamp(0.0, 1.0),
            ),
          ),
        ],
      ),
      if (data.viewsByDay.any((d) => d.views > 0 || d.clicks > 0)) ...[
        const SizedBox(height: 20),
        _sectionHeader(
          context,
          eyebrow: 'Tendência',
          title: 'Visualizações por dia',
        ),
        const SizedBox(height: 12),
        _buildViewsChart(context, data, tone, secondary),
      ],
      const SizedBox(height: 20),
      _sectionHeader(context, eyebrow: 'Ranking', title: 'Cliques por link'),
      const SizedBox(height: 12),
      if (data.links.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(LucideIcons.mousePointerClick, size: 14, color: secondary),
              const SizedBox(width: 8),
              Text(
                'Nenhum clique no período',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        )
      else
        SiteCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            children: [
              for (var i = 0; i < data.links.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 16,
                    color: ThemeHelpers.borderLightColor(
                      context,
                    ).withValues(alpha: 0.5),
                  ),
                _clicksRow(context, data.links[i], maxClicks, tone, numberFmt),
              ],
            ],
          ),
        ),
    ];
  }

  Widget _statTile(
    BuildContext context,
    IconData icon,
    String label,
    String value,
    Color tone, {
    double? meter,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.05),
        ),
        boxShadow: ThemeHelpers.cardShadow(context, strength: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: tone.withValues(alpha: isDark ? 0.18 : 0.1),
                ),
                child: Icon(icon, size: 14, color: tone),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    fontSize: 9.5,
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
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: tone,
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
                value: meter.clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: tone.withValues(alpha: 0.14),
                valueColor: AlwaysStoppedAnimation<Color>(tone),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildViewsChart(
    BuildContext context,
    BioPageAnalytics data,
    Color tone,
    Color secondary,
  ) {
    final days = data.viewsByDay;
    final maxViews = days
        .map((d) => d.views)
        .fold<int>(0, (m, v) => v > m ? v : m);
    if (maxViews == 0) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    String edgeLabel(String iso) {
      final parsed = DateTime.tryParse(iso);
      if (parsed == null) return iso;
      return DateFormat('dd/MM', 'pt_BR').format(parsed);
    }

    String viewsWord(int n) => n == 1 ? 'visualização' : 'visualizações';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 64,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < days.length; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                Expanded(
                  child: Tooltip(
                    message:
                        '${edgeLabel(days[i].date)} — ${days[i].views} '
                        '${viewsWord(days[i].views)}',
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: days[i].views <= 0
                          ? 3
                          : (6 + 58 * (days[i].views / maxViews))
                                .clamp(3, 64)
                                .toDouble(),
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3),
                        ),
                        color: days[i].views <= 0
                            ? tone.withValues(alpha: isDark ? 0.14 : 0.1)
                            : tone.withValues(
                                alpha: 0.35 + 0.65 * (days[i].views / maxViews),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              days.isNotEmpty ? edgeLabel(days.first.date) : '',
              style: TextStyle(fontSize: 10, color: secondary),
            ),
            Text(
              'pico: $maxViews ${viewsWord(maxViews)}',
              style: TextStyle(
                fontSize: 10,
                color: tone,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              days.isNotEmpty ? edgeLabel(days.last.date) : '',
              style: TextStyle(fontSize: 10, color: secondary),
            ),
          ],
        ),
      ],
    );
  }

  Widget _clicksRow(
    BuildContext context,
    BioPageLinkAnalytics item,
    int maxClicks,
    Color tone,
    NumberFormat fmt,
  ) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final ratio = maxClicks <= 0 ? 0.0 : item.clicks / maxClicks;
    return Column(
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
                color: tone,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: ratio.clamp(0.02, 1.0),
            minHeight: 5,
            backgroundColor: secondary.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation<Color>(
              tone.withValues(alpha: 0.35 + 0.65 * ratio),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnalyticsSkeleton(BuildContext context) {
    return Column(
      children: [
        Row(
          children: const [
            Expanded(child: SkeletonBox(height: 84, borderRadius: 14)),
            SizedBox(width: 10),
            Expanded(child: SkeletonBox(height: 84, borderRadius: 14)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: const [
            Expanded(child: SkeletonBox(height: 84, borderRadius: 14)),
            SizedBox(width: 10),
            Expanded(child: SkeletonBox(height: 84, borderRadius: 14)),
          ],
        ),
        const SizedBox(height: 18),
        const SkeletonBox(
          width: double.infinity,
          height: 150,
          borderRadius: 16,
        ),
      ],
    );
  }

  // ─── Skeleton (fiel ao hero recomposto e às linhas flush) ────────────────

  Widget _buildPageSkeleton(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final violet = isDark
        ? AppColors.status.purpleDarkMode
        : AppColors.status.purple;
    // Mesma moldura tingida do mock real (enquanto carrega, a tinta é o
    // violeta da tela — ainda não conhecemos as cores custom dos links).
    final frameColor = Color.alphaBlend(
      violet.withValues(alpha: isDark ? 0.30 : 0.24),
      isDark ? const Color(0xFF191627) : const Color(0xFF201C2E),
    );
    final hairline = ThemeHelpers.borderLightColor(
      context,
    ).withValues(alpha: 0.55);

    Widget miniStat() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        SkeletonText(width: 34, height: 17),
        SizedBox(height: 5),
        SkeletonText(width: 64, height: 8),
      ],
    );

    Widget linkRow() => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          const SkeletonBox(width: 40, height: 40, borderRadius: 13),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonText(width: 120, height: 13),
                SizedBox(height: 6),
                SkeletonText(width: 170, height: 10),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const SkeletonBox(width: 40, height: 22, borderRadius: 999),
        ],
      ),
    );

    Widget indentedHairline() => Container(
      margin: const EdgeInsets.only(left: 52),
      height: 1,
      color: hairline,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _kPagePadH,
        _kPagePadTop + 4,
        _kPagePadH,
        _kPagePadBottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Moldura do telefone
              Container(
                width: 168,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: frameColor,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const SkeletonBox(height: 264, borderRadius: 21),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    // Pill de status + microlinha
                    const SkeletonBox(
                      width: 126,
                      height: 26,
                      borderRadius: 999,
                    ),
                    const SizedBox(height: 8),
                    const SkeletonText(width: 148, height: 10),
                    const SizedBox(height: 18),
                    // Domínio esmaecido + /slug + icon-chips 32px
                    const SkeletonText(width: 96, height: 9),
                    const SizedBox(height: 6),
                    Row(
                      children: const [
                        Expanded(child: SkeletonText(height: 17)),
                        SizedBox(width: 8),
                        SkeletonBox(width: 32, height: 32, borderRadius: 10),
                        SizedBox(width: 6),
                        SkeletonBox(width: 32, height: 32, borderRadius: 10),
                      ],
                    ),
                    const SizedBox(height: 18),
                    // Par de mini-stats
                    Row(
                      children: [
                        Expanded(child: miniStat()),
                        const SizedBox(width: 12),
                        Expanded(child: miniStat()),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          // Abas
          Row(
            children: const [
              Expanded(child: SkeletonText(height: 14)),
              SizedBox(width: 14),
              Expanded(child: SkeletonText(height: 14)),
              SizedBox(width: 14),
              Expanded(child: SkeletonText(height: 14)),
            ],
          ),
          const SizedBox(height: 22),
          // Cabeçalho de seção (barra 18×2.5 + eyebrow + título)
          const SkeletonBox(width: 18, height: 2.5, borderRadius: 999),
          const SizedBox(height: 8),
          const SkeletonText(width: 56, height: 9),
          const SizedBox(height: 6),
          const SkeletonText(width: 180, height: 15),
          const SizedBox(height: 16),
          // Linhas de link flush com hairlines indentados
          linkRow(),
          indentedHairline(),
          linkRow(),
          indentedHairline(),
          linkRow(),
        ],
      ),
    );
  }
}
