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
import '../models/public_site_config_model.dart';
import '../public_site_access.dart';
import '../services/public_site_service.dart';
import '../widgets/public_site_shared.dart';

enum _SiteTab { overview, sections, content, domain }

/// Tela **Meu Site** — aqui o PREVIEW do site é o herói: uma moldura de
/// navegador (três pontinhos + campo de URL com o domínio real) emoldura um
/// mini-mock da identidade configurada — logo, cores da marca, tagline, CTA
/// e as seções ativas da home. Abaixo, as configurações seguem sóbrias em
/// abas com sublinhado, conteúdo flush nas margens e ações no próprio item.
/// Paridade com `PublicSiteConfigPage.tsx` (as etapas viáveis em mobile —
/// template/preview completos ficam no painel web).
class PublicSitePage extends StatefulWidget {
  const PublicSitePage({super.key});

  @override
  State<PublicSitePage> createState() => _PublicSitePageState();
}

class _PublicSitePageState extends State<PublicSitePage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 88;
  static const double _kSectionGap = 12;

  _SiteTab _activeTab = _SiteTab.overview;

  PublicSiteConfig? _config;
  List<PublicSiteTemplateInfo> _templates = const [];
  PublicSiteDnsInstructions? _dns;
  bool _loading = true;
  String? _error;

  // Publicação
  bool _publishing = false;

  // Seções (rascunho local + dirty)
  List<PublicSiteHomeBlock> _blocksDraft = const [];
  bool _blocksDirty = false;
  bool _blocksSaving = false;

  // Conteúdo & SEO
  final _taglineController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _ctaController = TextEditingController();
  final _aboutController = TextEditingController();
  final _seoTitleController = TextEditingController();
  final _seoDescriptionController = TextEditingController();
  bool _contentDirty = false;
  bool _contentSaving = false;

  // Domínio
  final _domainController = TextEditingController();
  bool _domainSaving = false;
  bool _dnsVerifying = false;

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
    _taglineController.dispose();
    _whatsappController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _ctaController.dispose();
    _aboutController.dispose();
    _seoTitleController.dispose();
    _seoDescriptionController.dispose();
    _domainController.dispose();
    super.dispose();
  }

  // ─── Cores ────────────────────────────────────────────────────────────────

  Color _accentColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
  }

  Color _tone(BuildContext context, _SiteTab tab) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (tab) {
      case _SiteTab.overview:
        return _accentColor(context);
      case _SiteTab.sections:
        return isDark
            ? AppColors.status.purpleDarkMode
            : AppColors.status.purple;
      case _SiteTab.content:
        return isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
      case _SiteTab.domain:
        return isDark
            ? AppColors.status.warningDarkMode
            : AppColors.status.warning;
    }
  }

  Color _domainStatusColor(BuildContext context, PublicSiteDomainStatus st) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (st) {
      case PublicSiteDomainStatus.active:
        return isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
      case PublicSiteDomainStatus.pendingDns:
        return isDark
            ? AppColors.status.warningDarkMode
            : AppColors.status.warning;
      case PublicSiteDomainStatus.pendingReview:
        return isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
      case PublicSiteDomainStatus.disabled:
        return isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    }
  }

  // ─── Dados ────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final results = await Future.wait([
      PublicSiteService.instance.getConfig(),
      PublicSiteService.instance.getTemplates(),
      PublicSiteService.instance.getDnsInstructions(),
    ]);
    if (!mounted) return;

    final cfgRes = results[0] as dynamic;
    final tplRes = results[1] as dynamic;
    final dns = results[2] as PublicSiteDnsInstructions;

    setState(() {
      _loading = false;
      _dns = dns;
      if (cfgRes.success && cfgRes.data != null) {
        _applyConfig(cfgRes.data as PublicSiteConfig, resetDrafts: true);
      } else {
        _error = cfgRes.message ?? 'Erro ao carregar configuração do site';
      }
      if (tplRes.success && tplRes.data != null) {
        _templates = tplRes.data as List<PublicSiteTemplateInfo>;
      }
    });
  }

  void _applyConfig(PublicSiteConfig cfg, {bool resetDrafts = false}) {
    _config = cfg;
    if (resetDrafts || !_blocksDirty) {
      _blocksDraft = List.of(cfg.editorHomeBlocks);
      _blocksDirty = false;
    }
    if (resetDrafts || !_contentDirty) {
      _taglineController.text = cfg.content.tagline ?? '';
      _whatsappController.text = cfg.content.whatsapp ?? '';
      _phoneController.text = cfg.content.phone ?? '';
      _emailController.text = cfg.content.email ?? '';
      _ctaController.text = cfg.content.ctaText ?? '';
      _aboutController.text = cfg.content.aboutText ?? '';
      _seoTitleController.text = cfg.seo.title ?? '';
      _seoDescriptionController.text = cfg.seo.description ?? '';
      _contentDirty = false;
    }
    _domainController.text = cfg.customDomain ?? '';
  }

  Future<void> _refresh() async {
    final res = await PublicSiteService.instance.getConfig();
    if (!mounted) return;
    setState(() {
      if (res.success && res.data != null) {
        _applyConfig(res.data!);
        _error = null;
      }
    });
  }

  // ─── Ações ────────────────────────────────────────────────────────────────

  void _showSnack(String message, {Color? tone}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: tone,
        content: Text(message),
      ),
    );
  }

  Future<void> _copyUrl() async {
    final url = _config?.bestPublicUrl;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    _showSnack('URL copiada');
  }

  Future<void> _openSite() async {
    final url = _config?.bestPublicUrl;
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) _showSnack('Não foi possível abrir o site');
  }

  Future<void> _copyText(String value, {String? feedback}) async {
    await Clipboard.setData(ClipboardData(text: value));
    _showSnack(feedback ?? 'Copiado');
  }

  Future<void> _togglePublish() async {
    final cfg = _config;
    if (cfg == null || _publishing) return;

    if (cfg.isPublished) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Despublicar site?'),
          content: const Text(
            'Seu site sai do ar imediatamente e os visitantes deixam de '
            'acessá-lo. Você pode publicar de novo quando quiser.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).brightness == Brightness.dark
                    ? AppColors.status.errorDarkMode
                    : AppColors.status.error,
              ),
              child: const Text('Despublicar'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _publishing = true);
    final res = cfg.isPublished
        ? await PublicSiteService.instance.unpublish()
        : await PublicSiteService.instance.publish();
    if (!mounted) return;
    setState(() {
      _publishing = false;
      if (res.success && res.data != null) _applyConfig(res.data!);
    });
    if (res.success) {
      _showSnack(res.data!.isPublished ? 'Site no ar' : 'Site despublicado');
    } else {
      _showSnack(res.message ?? 'Erro ao alterar publicação');
    }
  }

  Future<void> _saveBlocks() async {
    if (_blocksSaving) return;
    setState(() => _blocksSaving = true);
    final payload = {
      'homeBlocks': [for (final b in _blocksDraft) b.toJson()],
    };
    final res = await PublicSiteService.instance.updateConfig(payload);
    if (!mounted) return;
    setState(() {
      _blocksSaving = false;
      if (res.success && res.data != null) {
        _blocksDirty = false;
        _applyConfig(res.data!, resetDrafts: false);
        _blocksDraft = List.of(res.data!.editorHomeBlocks);
      }
    });
    _showSnack(
      res.success ? 'Seções salvas' : (res.message ?? 'Erro ao salvar seções'),
    );
  }

  Future<void> _saveContent() async {
    final cfg = _config;
    if (cfg == null || _contentSaving) return;
    setState(() => _contentSaving = true);

    final content = PublicSiteContent(
      tagline: _taglineController.text.trim(),
      aboutText: _aboutController.text.trim(),
      whatsapp: _whatsappController.text.trim(),
      phone: _phoneController.text.trim(),
      email: _emailController.text.trim(),
      socialLinks: cfg.content.socialLinks,
      ctaText: _ctaController.text.trim(),
    );
    final seo = PublicSiteSeo(
      title: _seoTitleController.text.trim(),
      description: _seoDescriptionController.text.trim(),
      gaMeasurementId: cfg.seo.gaMeasurementId,
    );

    final res = await PublicSiteService.instance.updateConfig({
      'content': content.toJson(),
      'seo': seo.toJson(),
    });
    if (!mounted) return;
    setState(() {
      _contentSaving = false;
      if (res.success && res.data != null) {
        _contentDirty = false;
        _applyConfig(res.data!, resetDrafts: true);
      }
    });
    _showSnack(
      res.success ? 'Conteúdo salvo' : (res.message ?? 'Erro ao salvar'),
    );
  }

  Future<void> _saveDomain() async {
    final domain = _domainController.text.trim();
    if (domain.isEmpty) {
      _showSnack('Informe o domínio do site (ex.: www.suaimobiliaria.com.br)');
      return;
    }
    if (_domainSaving) return;
    setState(() => _domainSaving = true);
    final res = await PublicSiteService.instance.updateCustomDomain(domain);
    if (!mounted) return;
    setState(() {
      _domainSaving = false;
      if (res.success && res.data != null) _applyConfig(res.data!);
    });
    _showSnack(
      res.success
          ? 'Domínio salvo — configure o CNAME e verifique a propagação'
          : (res.message ?? 'Erro ao salvar domínio'),
    );
  }

  Future<void> _verifyDns() async {
    if (_dnsVerifying) return;
    setState(() => _dnsVerifying = true);
    final res = await PublicSiteService.instance.verifyCustomDomainDns();
    if (!mounted) return;
    if (res.success && res.data != null) {
      await _refresh();
      if (!mounted) return;
      setState(() => _dnsVerifying = false);
      _showSnack(
        res.data!.message.isNotEmpty
            ? res.data!.message
            : (res.data!.verified
                  ? 'Domínio verificado e ativo'
                  : 'CNAME ainda não propagou — tente de novo em alguns minutos'),
      );
    } else {
      setState(() => _dnsVerifying = false);
      _showSnack(res.message ?? 'Erro ao verificar DNS');
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canView) {
      return const AppScaffold(
        title: 'Meu Site',
        showBottomNavigation: false,
        body: SiteDeniedView(
          message: 'Você não tem acesso à configuração do site.',
          permissionLabel: PublicSiteAccess.permView,
        ),
      );
    }
    return AppScaffold(
      title: 'Meu Site',
      showBottomNavigation: false,
      body: RefreshIndicator(
        color: _accentColor(context),
        onRefresh: () async {
          await _load();
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
                    child: _buildBrowserHero(context),
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

  // ─── Hero: o site é o protagonista (moldura de navegador) ────────────────

  Widget _buildBrowserHero(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accentColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final emerald = isDark
        ? AppColors.status.greenDarkMode
        : AppColors.status.green;
    final amber = isDark
        ? AppColors.status.warningDarkMode
        : AppColors.status.warning;

    final cfg = _config!;
    final published = cfg.isPublished;
    final statusTone = published ? emerald : amber;
    final url = cfg.bestPublicUrl;
    final hasUrl = url != null;
    final hasDomain = (cfg.customDomain ?? '').trim().isNotEmpty;
    final domainTone = _domainStatusColor(context, cfg.domainStatus);

    final domainLabel = hasDomain
        ? cfg.customDomain!.trim()
        : (hasUrl
              ? url
                    .replaceFirst(RegExp(r'^https?://'), '')
                    .replaceFirst(RegExp(r'/+$'), '')
              : 'domínio ainda não definido');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBrowserFrame(
          context,
          domainLabel: domainLabel,
          hasAddress: hasUrl || hasDomain,
          published: published,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            SiteMiniPill(
              label: published ? 'No ar' : 'Rascunho',
              tone: statusTone,
              icon: published
                  ? LucideIcons.circleCheckBig
                  : LucideIcons.circleDashed,
            ),
            if (hasDomain) ...[
              const SizedBox(width: 7),
              Flexible(
                child: SiteMiniPill(
                  label: cfg.domainStatus.label,
                  tone: domainTone,
                  icon: cfg.domainStatus == PublicSiteDomainStatus.active
                      ? LucideIcons.check
                      : LucideIcons.clock3,
                ),
              ),
            ],
            const Spacer(),
            SiteRowAction(
              icon: LucideIcons.externalLink,
              tooltip: 'Ver site',
              tone: accent,
              onTap: hasUrl ? _openSite : null,
            ),
            SiteRowAction(
              icon: LucideIcons.copy,
              tooltip: 'Copiar URL',
              tone: secondary,
              onTap: hasUrl ? _copyUrl : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          published
              ? 'É assim que os visitantes encontram seu site agora.'
              : 'Só você vê este preview — publique na aba Visão geral para '
                    'colocar o site no ar.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: secondary,
            height: 1.35,
            fontSize: 11.5,
          ),
        ),
      ],
    );
  }

  /// Moldura de "navegador": barra com três pontinhos + campo de URL com o
  /// domínio real, emoldurando um mini-preview da identidade do site montado
  /// só com dados reais (logo, cores da marca, tagline, CTA e seções ativas).
  Widget _buildBrowserFrame(
    BuildContext context, {
    required String domainLabel,
    required bool hasAddress,
    required bool published,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final emerald = isDark
        ? AppColors.status.greenDarkMode
        : AppColors.status.green;
    final amber = isDark
        ? AppColors.status.warningDarkMode
        : AppColors.status.warning;
    final rose = isDark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;

    final cfg = _config!;
    final brand =
        siteParseHexColor(cfg.branding.primaryColor) ?? _accentColor(context);
    final swatches = [
      cfg.branding.primaryColor,
      cfg.branding.secondaryColor,
      cfg.branding.accentColor,
    ].map(siteParseHexColor).whereType<Color>().toList(growable: false);

    final templateName =
        _templates
            .where((t) => t.id == cfg.templateId)
            .map((t) => t.name)
            .firstOrNull ??
        _fallbackTemplateLabel(cfg.templateId);
    final siteTitle = (cfg.seo.title ?? '').trim();
    final tagline = (cfg.content.tagline ?? '').trim();
    final cta = (cfg.content.ctaText ?? '').trim();
    final enabledBlocks = _blocksDraft
        .where((b) => b.enabled)
        .toList(growable: false);
    final onBrand =
        ThemeData.estimateBrightnessForColor(brand) == Brightness.dark
        ? Colors.white
        : const Color(0xFF1F2937);

    Widget browserDot(Color tone) => Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tone.withValues(alpha: 0.8),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Barra do navegador — três pontinhos + campo de URL real.
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: ThemeHelpers.borderLightColor(context),
                ),
              ),
            ),
            child: Row(
              children: [
                browserDot(rose),
                const SizedBox(width: 5),
                browserDot(amber),
                const SizedBox(width: 5),
                browserDot(emerald),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.black.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          published
                              ? LucideIcons.lock
                              : LucideIcons.circleDashed,
                          size: 10,
                          color: published ? emerald : secondary,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            domainLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.1,
                              color: hasAddress
                                  ? ThemeHelpers.textColor(context)
                                  : secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Mini-preview da identidade — somente dados reais configurados.
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _previewLogo(context, brand),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            siteTitle.isNotEmpty
                                ? siteTitle
                                : 'Seu site imobiliário',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.2,
                              color: siteTitle.isNotEmpty
                                  ? ThemeHelpers.textColor(context)
                                  : secondary,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            'Template $templateName'
                            '${cfg.premiumTemplateUnlocked ? ' · Premium' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (swatches.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      for (var i = 0; i < swatches.length; i++)
                        Container(
                          width: 14,
                          height: 14,
                          margin: EdgeInsets.only(left: i == 0 ? 0 : 4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: swatches[i],
                            border: Border.all(
                              color: ThemeHelpers.cardBackgroundColor(context),
                              width: 1.5,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                // "Banner" do site — tagline + CTA nas cores da marca.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        brand.withValues(alpha: isDark ? 0.22 : 0.14),
                        brand.withValues(alpha: isDark ? 0.08 : 0.05),
                      ],
                    ),
                    border: Border.all(color: brand.withValues(alpha: 0.22)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          tagline.isNotEmpty
                              ? tagline
                              : 'Sua frase de destaque aparece aqui',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.1,
                            height: 1.25,
                            color: tagline.isNotEmpty
                                ? ThemeHelpers.textColor(context)
                                : secondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: brand,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          cta.isNotEmpty ? cta : 'Fale conosco',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.2,
                            color: onBrand,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (enabledBlocks.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (
                        var i = 0;
                        i < enabledBlocks.length && i < 4;
                        i++
                      ) ...[
                        if (i > 0) const SizedBox(width: 6),
                        Expanded(
                          child: Tooltip(
                            message: PublicSiteBlockCatalog.labelOf(
                              enabledBlocks[i].type,
                            ),
                            child: Container(
                              height: 30,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(9),
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : Colors.black.withValues(alpha: 0.04),
                              ),
                              child: Icon(
                                PublicSiteBlockCatalog.iconOf(
                                  enabledBlocks[i].type,
                                ),
                                size: 13,
                                color: secondary,
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (enabledBlocks.length > 4) ...[
                        const SizedBox(width: 6),
                        Container(
                          height: 30,
                          padding: const EdgeInsets.symmetric(horizontal: 9),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(9),
                            color: brand.withValues(
                              alpha: isDark ? 0.16 : 0.09,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '+${enabledBlocks.length - 4}',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w900,
                                color: brand,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${enabledBlocks.length} '
                    '${enabledBlocks.length == 1 ? 'seção ativa' : 'seções ativas'} na home',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: secondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).moveY(begin: 8, end: 0, curve: Curves.easeOut);
  }

  Widget _previewLogo(BuildContext context, Color brand) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final logo = (_config!.branding.logoUrl ?? '').trim();
    return Container(
      width: 38,
      height: 38,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: brand.withValues(alpha: isDark ? 0.2 : 0.12),
        border: Border.all(color: brand.withValues(alpha: 0.3)),
      ),
      child: logo.isNotEmpty
          ? Image.network(
              logo,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Icon(LucideIcons.building2, size: 18, color: brand),
            )
          : Icon(LucideIcons.building2, size: 18, color: brand),
    );
  }

  String _fallbackTemplateLabel(String id) {
    switch (id) {
      case 'classic':
        return 'Clássico';
      case 'modern':
        return 'Moderno';
      case 'corporate':
        return 'Corporativo';
      case 'luxury':
        return 'Luxo';
      case 'compact':
        return 'Compacto';
      case 'premium':
        return 'Premium';
      default:
        return id;
    }
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
          for (final tab in _SiteTab.values)
            Expanded(
              child: SiteFlushTab(
                icon: _tabIcon(tab),
                label: _tabLabel(tab),
                tone: _tone(context, tab),
                selected: _activeTab == tab,
                onTap: () => setState(() => _activeTab = tab),
              ),
            ),
        ],
      ),
    );
  }

  IconData _tabIcon(_SiteTab tab) {
    switch (tab) {
      case _SiteTab.overview:
        return LucideIcons.panelsTopLeft;
      case _SiteTab.sections:
        return LucideIcons.layoutList;
      case _SiteTab.content:
        return LucideIcons.penLine;
      case _SiteTab.domain:
        return LucideIcons.globe;
    }
  }

  String _tabLabel(_SiteTab tab) {
    switch (tab) {
      case _SiteTab.overview:
        return 'Visão geral';
      case _SiteTab.sections:
        return 'Seções';
      case _SiteTab.content:
        return 'Conteúdo';
      case _SiteTab.domain:
        return 'Domínio';
    }
  }

  // ─── Painéis ──────────────────────────────────────────────────────────────

  Widget _buildActivePanel(BuildContext context) {
    final Widget child;
    switch (_activeTab) {
      case _SiteTab.overview:
        child = _buildOverviewPanel(context);
        break;
      case _SiteTab.sections:
        child = _buildSectionsPanel(context);
        break;
      case _SiteTab.content:
        child = _buildContentPanel(context);
        break;
      case _SiteTab.domain:
        child = _buildDomainPanel(context);
        break;
    }
    return KeyedSubtree(
      key: ValueKey('panel-${_activeTab.name}'),
      child: child.animate().fadeIn(duration: 240.ms),
    );
  }

  ({IconData icon, String title, String hint}) _panelMeta(_SiteTab tab) {
    switch (tab) {
      case _SiteTab.overview:
        return (
          icon: LucideIcons.panelsTopLeft,
          title: 'Status do seu site',
          hint: 'Publicação, endereço e um resumo do que está configurado.',
        );
      case _SiteTab.sections:
        return (
          icon: LucideIcons.layoutList,
          title: 'Monte a página inicial',
          hint:
              'Ative, desative e reordene os blocos que aparecem no seu site.',
        );
      case _SiteTab.content:
        return (
          icon: LucideIcons.penLine,
          title: 'Textos e contato',
          hint: 'O que os visitantes leem — e como o Google encontra o site.',
        );
      case _SiteTab.domain:
        return (
          icon: LucideIcons.globe,
          title: 'Endereço do site',
          hint: 'Aponte o seu domínio com um CNAME e ative automaticamente.',
        );
    }
  }

  Widget _panelShell(BuildContext context, _SiteTab tab, List<Widget> body) {
    final meta = _panelMeta(tab);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SitePanelHeader(
          icon: meta.icon,
          title: meta.title,
          hint: meta.hint,
          tone: _tone(context, tab),
        ),
        const SizedBox(height: 14),
        ...body,
      ],
    );
  }

  // ── Visão geral ──

  Widget _buildOverviewPanel(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cfg = _config!;
    final emerald = isDark
        ? AppColors.status.greenDarkMode
        : AppColors.status.green;
    final amber = isDark
        ? AppColors.status.warningDarkMode
        : AppColors.status.warning;
    final danger = isDark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final statusTone = cfg.isPublished ? emerald : amber;
    final domainTone = _domainStatusColor(context, cfg.domainStatus);
    final dateFmt = DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR');
    final url = cfg.bestPublicUrl;

    return _panelShell(context, _SiteTab.overview, [
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
                  cfg.isPublished
                      ? LucideIcons.circleCheckBig
                      : LucideIcons.circleDashed,
                  size: 18,
                  color: statusTone,
                ),
                const SizedBox(width: 8),
                Text(
                  cfg.isPublished ? 'SITE PUBLICADO' : 'SITE EM RASCUNHO',
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
              cfg.isPublished
                  ? (cfg.publishedAt != null
                        ? 'Publicado em ${dateFmt.format(cfg.publishedAt!.toLocal())}.'
                        : 'Seu site está visível para qualquer visitante.')
                  : 'Quando estiver satisfeito com as seções, conteúdo e '
                        'domínio, publique para colocar o site no ar.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondary,
                height: 1.4,
              ),
            ),
            if (_canManage) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _publishing ? null : _togglePublish,
                  style: FilledButton.styleFrom(
                    backgroundColor: cfg.isPublished ? danger : emerald,
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
                      : Icon(
                          cfg.isPublished
                              ? LucideIcons.cloudOff
                              : LucideIcons.rocket,
                          size: 17,
                        ),
                  label: Text(
                    _publishing
                        ? 'Aguarde…'
                        : (cfg.isPublished
                              ? 'Despublicar site'
                              : 'Publicar site'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 14),
      SiteCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          children: [
            SiteInfoRow(
              icon: LucideIcons.link,
              label: 'URL pública',
              value: url ?? 'Defina um domínio para gerar a URL',
              valueTone: url == null ? secondary : null,
              actions: [
                SiteRowAction(
                  icon: LucideIcons.copy,
                  tooltip: 'Copiar URL',
                  tone: _accentColor(context),
                  onTap: url == null ? null : _copyUrl,
                ),
                SiteRowAction(
                  icon: LucideIcons.externalLink,
                  tooltip: 'Abrir site',
                  tone: _accentColor(context),
                  onTap: url == null ? null : _openSite,
                ),
              ],
            ),
            Divider(height: 1, color: ThemeHelpers.borderLightColor(context)),
            SiteInfoRow(
              icon: LucideIcons.globe,
              label: 'Domínio próprio',
              value: (cfg.customDomain ?? '').trim().isNotEmpty
                  ? cfg.customDomain!.trim()
                  : 'Não configurado',
              valueTone: (cfg.customDomain ?? '').trim().isNotEmpty
                  ? null
                  : secondary,
              actions: [
                if ((cfg.customDomain ?? '').trim().isNotEmpty)
                  SiteMiniPill(
                    label: cfg.domainStatus.label,
                    tone: domainTone,
                    icon: cfg.domainStatus == PublicSiteDomainStatus.active
                        ? LucideIcons.check
                        : LucideIcons.clock3,
                  ),
              ],
            ),
            Divider(height: 1, color: ThemeHelpers.borderLightColor(context)),
            SiteInfoRow(
              icon: LucideIcons.paintbrush,
              label: 'Template',
              value:
                  _templates
                      .where((t) => t.id == cfg.templateId)
                      .map((t) => t.name)
                      .firstOrNull ??
                  _fallbackTemplateLabel(cfg.templateId),
              actions: [
                if (cfg.templateId == 'premium')
                  SiteMiniPill(
                    label: 'Premium',
                    tone: isDark
                        ? AppColors.status.warningDarkMode
                        : AppColors.status.warning,
                    icon: LucideIcons.star,
                  ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      // Nota de escopo mobile — template e preview completos ficam no painel.
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.info, size: 14, color: secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'A troca de template e o preview ao vivo ficam no painel web — '
              'aqui você acompanha o status e ajusta seções, conteúdo e domínio.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    ]);
  }

  // ── Seções ──

  Widget _buildSectionsPanel(BuildContext context) {
    final tone = _tone(context, _SiteTab.sections);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final theme = Theme.of(context);

    if (_blocksDraft.isEmpty) {
      return _panelShell(context, _SiteTab.sections, [
        SiteEmptyState(
          icon: LucideIcons.layoutList,
          title: 'Sem seções configuradas',
          body:
              'As seções padrão do template aparecem aqui assim que o site '
              'for configurado no painel.',
          tone: tone,
        ),
      ]);
    }

    return _panelShell(context, _SiteTab.sections, [
      if (!_canManage)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _readOnlyNotice(context),
        ),
      ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: _blocksDraft.length,
        proxyDecorator: (child, index, animation) =>
            Material(color: Colors.transparent, child: child),
        onReorder: !_canManage
            ? (_, __) {}
            : (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = _blocksDraft.removeAt(oldIndex);
                  _blocksDraft.insert(newIndex, item);
                  _blocksDirty = true;
                });
              },
        itemBuilder: (context, index) {
          final block = _blocksDraft[index];
          return Padding(
            key: ValueKey('block-${block.id}'),
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildBlockTile(context, block, index, tone),
          );
        },
      ),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(LucideIcons.gripVertical, size: 13, color: secondary),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                'Arraste pela alça para reordenar. A ordem daqui é a ordem '
                'da página inicial do site.',
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
      SiteSaveBar(
        visible: _canManage && _blocksDirty,
        saving: _blocksSaving,
        label: 'Salvar seções',
        onSave: _saveBlocks,
        onDiscard: () {
          setState(() {
            _blocksDraft = List.of(_config!.editorHomeBlocks);
            _blocksDirty = false;
          });
        },
      ),
    ]);
  }

  Widget _buildBlockTile(
    BuildContext context,
    PublicSiteHomeBlock block,
    int index,
    Color tone,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final enabled = block.enabled;
    final fg = enabled ? tone : secondary.withValues(alpha: 0.7);

    return Container(
      padding: const EdgeInsets.fromLTRB(6, 10, 12, 10),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: enabled
              ? tone.withValues(alpha: isDark ? 0.28 : 0.2)
              : (isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.05)),
        ),
        boxShadow: ThemeHelpers.cardShadow(context, strength: 0.7),
      ),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            enabled: _canManage,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Icon(
                LucideIcons.gripVertical,
                size: 16,
                color: secondary.withValues(alpha: _canManage ? 0.7 : 0.3),
              ),
            ),
          ),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              color: fg.withValues(alpha: isDark ? 0.16 : 0.1),
            ),
            child: Icon(
              PublicSiteBlockCatalog.iconOf(block.type),
              size: 17,
              color: fg,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  PublicSiteBlockCatalog.labelOf(block.type),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: enabled
                        ? ThemeHelpers.textColor(context)
                        : secondary,
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  PublicSiteBlockCatalog.descriptionOf(block.type),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondary,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: enabled,
            activeColor: tone,
            onChanged: !_canManage
                ? null
                : (v) {
                    setState(() {
                      _blocksDraft[index] = block.copyWith(enabled: v);
                      _blocksDirty = true;
                    });
                  },
          ),
        ],
      ),
    );
  }

  // ── Conteúdo & SEO ──

  Widget _buildContentPanel(BuildContext context) {
    void markDirty(String _) {
      if (!_contentDirty) setState(() => _contentDirty = true);
    }

    return _panelShell(context, _SiteTab.content, [
      if (!_canManage)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _readOnlyNotice(context),
        ),
      const SiteSubsectionHeader(
        label: 'Apresentação',
        icon: LucideIcons.sparkles,
      ),
      const SizedBox(height: 12),
      SiteFilledField(
        controller: _taglineController,
        label: 'Frase de destaque (tagline)',
        hint: 'Encontre o imóvel dos seus sonhos',
        icon: LucideIcons.sparkles,
        enabled: _canManage,
        onChanged: markDirty,
      ),
      const SizedBox(height: 12),
      SiteFilledField(
        controller: _aboutController,
        label: 'Sobre a imobiliária',
        hint: 'Conte a história e os diferenciais da empresa…',
        maxLines: 4,
        enabled: _canManage,
        onChanged: markDirty,
      ),
      const SizedBox(height: 12),
      SiteFilledField(
        controller: _ctaController,
        label: 'Texto do botão de contato (CTA)',
        hint: 'Fale com um corretor',
        icon: LucideIcons.megaphone,
        enabled: _canManage,
        onChanged: markDirty,
      ),
      const SizedBox(height: 18),
      const SiteSubsectionHeader(label: 'Contato', icon: LucideIcons.phone),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SiteFilledField(
              controller: _whatsappController,
              label: 'WhatsApp',
              hint: '(11) 99999-9999',
              icon: LucideIcons.messageCircle,
              keyboardType: TextInputType.phone,
              enabled: _canManage,
              onChanged: markDirty,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SiteFilledField(
              controller: _phoneController,
              label: 'Telefone',
              hint: '(11) 3333-3333',
              icon: LucideIcons.phone,
              keyboardType: TextInputType.phone,
              enabled: _canManage,
              onChanged: markDirty,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      SiteFilledField(
        controller: _emailController,
        label: 'E-mail de contato',
        hint: 'contato@suaimobiliaria.com.br',
        icon: LucideIcons.mail,
        keyboardType: TextInputType.emailAddress,
        enabled: _canManage,
        onChanged: markDirty,
      ),
      const SizedBox(height: 18),
      const SiteSubsectionHeader(
        label: 'SEO · Google',
        icon: LucideIcons.search,
      ),
      const SizedBox(height: 12),
      SiteFilledField(
        controller: _seoTitleController,
        label: 'Título da página (SEO)',
        hint: 'Sua Imobiliária — Imóveis em São Paulo',
        icon: LucideIcons.heading,
        enabled: _canManage,
        onChanged: markDirty,
      ),
      const SizedBox(height: 12),
      SiteFilledField(
        controller: _seoDescriptionController,
        label: 'Descrição (aparece na busca)',
        hint: 'Compra, venda e locação de imóveis com atendimento completo…',
        maxLines: 3,
        enabled: _canManage,
        onChanged: markDirty,
      ),
      SiteSaveBar(
        visible: _canManage && _contentDirty,
        saving: _contentSaving,
        label: 'Salvar conteúdo',
        onSave: _saveContent,
        onDiscard: () {
          setState(() {
            _contentDirty = false;
            _applyConfig(_config!, resetDrafts: true);
          });
        },
      ),
    ]);
  }

  // ── Domínio ──

  Widget _buildDomainPanel(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cfg = _config!;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final tone = _tone(context, _SiteTab.domain);
    final emerald = isDark
        ? AppColors.status.greenDarkMode
        : AppColors.status.green;
    final hasDomain = (cfg.customDomain ?? '').trim().isNotEmpty;
    final domainTone = _domainStatusColor(context, cfg.domainStatus);
    final dns = _dns ?? PublicSiteDnsInstructions.fromJson(null);
    final isActive = cfg.domainStatus == PublicSiteDomainStatus.active;

    return _panelShell(context, _SiteTab.domain, [
      if (!_canManage)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _readOnlyNotice(context),
        ),
      SiteFilledField(
        controller: _domainController,
        label: 'Domínio do site',
        hint: 'www.suaimobiliaria.com.br',
        icon: LucideIcons.globe,
        keyboardType: TextInputType.url,
        enabled: _canManage,
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _canManage && !_domainSaving ? _saveDomain : null,
              style: FilledButton.styleFrom(
                backgroundColor: _accentColor(context),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: _domainSaving
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
                _domainSaving ? 'Salvando…' : 'Salvar domínio',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _canManage && hasDomain && !_dnsVerifying && !isActive
                  ? _verifyDns
                  : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: emerald,
                side: BorderSide(color: emerald.withValues(alpha: 0.45)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: _dnsVerifying
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: emerald,
                      ),
                    )
                  : const Icon(LucideIcons.radar, size: 16),
              label: Text(
                _dnsVerifying ? 'Verificando…' : 'Verificar DNS',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
      if (hasDomain) ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: domainTone.withValues(alpha: isDark ? 0.12 : 0.07),
            border: Border.all(color: domainTone.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Icon(
                isActive ? LucideIcons.circleCheckBig : LucideIcons.clock3,
                size: 18,
                color: domainTone,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cfg.domainStatus.label.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: domainTone,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isActive
                          ? 'Domínio ativo — o site responde em '
                                '${cfg.customDomain!.trim()}.'
                          : 'Aguardando o CNAME propagar. Salve o registro no '
                                'seu provedor e toque em "Verificar DNS".',
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
        ),
      ],
      const SizedBox(height: 18),
      const SiteSubsectionHeader(
        label: 'Registro CNAME',
        icon: LucideIcons.network,
      ),
      const SizedBox(height: 12),
      SiteCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          children: [
            SiteInfoRow(icon: LucideIcons.tag, label: 'Tipo', value: 'CNAME'),
            Divider(height: 1, color: ThemeHelpers.borderLightColor(context)),
            SiteInfoRow(
              icon: LucideIcons.atSign,
              label: 'Host / Nome',
              value: 'www',
              actions: [
                SiteRowAction(
                  icon: LucideIcons.copy,
                  tooltip: 'Copiar host',
                  tone: tone,
                  onTap: () => _copyText('www', feedback: 'Host copiado'),
                ),
              ],
            ),
            Divider(height: 1, color: ThemeHelpers.borderLightColor(context)),
            SiteInfoRow(
              icon: LucideIcons.arrowRight,
              label: 'Aponta para',
              value: dns.cnameTarget,
              actions: [
                SiteRowAction(
                  icon: LucideIcons.copy,
                  tooltip: 'Copiar destino',
                  tone: tone,
                  onTap: () =>
                      _copyText(dns.cnameTarget, feedback: 'Destino copiado'),
                ),
              ],
            ),
            Divider(height: 1, color: ThemeHelpers.borderLightColor(context)),
            SiteInfoRow(
              icon: LucideIcons.timer,
              label: 'TTL recomendado',
              value: dns.ttlRecommendation,
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.info, size: 14, color: secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              dns.propagationNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondary,
                height: 1.4,
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      const SiteSubsectionHeader(
        label: 'Passo a passo',
        icon: LucideIcons.listOrdered,
      ),
      const SizedBox(height: 12),
      for (final step in dns.steps) _buildDnsStep(context, step, tone),
    ]);
  }

  Widget _buildDnsStep(
    BuildContext context,
    PublicSiteDnsStep step,
    Color tone,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tone.withValues(alpha: isDark ? 0.18 : 0.12),
              border: Border.all(color: tone.withValues(alpha: 0.35)),
            ),
            child: Center(
              child: Text(
                '${step.order}',
                style: TextStyle(
                  color: tone,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  step.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Auxiliares ───────────────────────────────────────────────────────────

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
              'Somente leitura — a edição exige a permissão '
              '"${PublicSiteAccess.permManage}".',
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

  // ─── Skeleton (fiel ao layout novo: moldura de navegador + abas) ─────────

  Widget _buildPageSkeleton(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _kPagePadH,
        _kPagePadTop + 4,
        _kPagePadH,
        _kPagePadBottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Moldura de navegador
          Container(
            decoration: BoxDecoration(
              color: ThemeHelpers.cardBackgroundColor(context),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    children: const [
                      SkeletonBox(width: 8, height: 8, borderRadius: 999),
                      SizedBox(width: 5),
                      SkeletonBox(width: 8, height: 8, borderRadius: 999),
                      SizedBox(width: 5),
                      SkeletonBox(width: 8, height: 8, borderRadius: 999),
                      SizedBox(width: 10),
                      Expanded(
                        child: SkeletonBox(height: 25, borderRadius: 999),
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: ThemeHelpers.borderLightColor(context),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: const [
                          SkeletonBox(width: 38, height: 38, borderRadius: 12),
                          SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SkeletonText(width: 150, height: 12),
                                SizedBox(height: 6),
                                SkeletonText(width: 100, height: 10),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const SkeletonBox(height: 52, borderRadius: 12),
                      const SizedBox(height: 10),
                      Row(
                        children: const [
                          Expanded(
                            child: SkeletonBox(height: 30, borderRadius: 9),
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: SkeletonBox(height: 30, borderRadius: 9),
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: SkeletonBox(height: 30, borderRadius: 9),
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: SkeletonBox(height: 30, borderRadius: 9),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: const [
              SkeletonBox(width: 84, height: 24, borderRadius: 999),
              SizedBox(width: 7),
              SkeletonBox(width: 110, height: 24, borderRadius: 999),
              Spacer(),
              SkeletonBox(width: 34, height: 34, borderRadius: 11),
              SizedBox(width: 6),
              SkeletonBox(width: 34, height: 34, borderRadius: 11),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: const [
              Expanded(child: SkeletonText(height: 14)),
              SizedBox(width: 14),
              Expanded(child: SkeletonText(height: 14)),
              SizedBox(width: 14),
              Expanded(child: SkeletonText(height: 14)),
              SizedBox(width: 14),
              Expanded(child: SkeletonText(height: 14)),
            ],
          ),
          const SizedBox(height: 22),
          const SkeletonBox(height: 44, borderRadius: 12),
          const SizedBox(height: 14),
          const SkeletonBox(height: 130, borderRadius: 16),
          const SizedBox(height: 12),
          const SkeletonBox(height: 180, borderRadius: 16),
        ],
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
