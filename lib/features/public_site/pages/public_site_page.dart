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

/// Item do "o que falta para ir ao ar"; [tab] = aba onde ele se resolve
/// (null = não se resolve no app).
typedef _CheckItem = ({
  String label,
  String value,
  SiteCheckState state,
  _SiteTab? tab,
});

/// Tela **Meu Site** — responde de cara às três perguntas de quem abre: o
/// site está no ar? em qual endereço? o que falta?
///
/// No alto, o PREVIEW do site é o herói: uma moldura de navegador com o
/// endereço real emoldura um mini-site montado só com dados reais (logo,
/// tintas, frase, botão e seções ligadas). Logo abaixo, a situação (no ar /
/// fora do ar, domínio) com abrir e copiar, e o PRÓXIMO PASSO numa frase,
/// com o atalho até onde ele se resolve. As configurações seguem em abas com
/// sublinhado: Resumo (publicar, o que falta, identidade), Seções, Textos e
/// Domínio (roteiro de 3 passos numerados). Paridade com
/// `PublicSiteConfigPage.tsx` nas etapas viáveis no celular — modelo, marca
/// e prévia ao vivo seguem no web.
///
/// Revisão 30/09/2026: coluna de 720 no tablet, barra de salvar fixa no pé
/// (desce para o fim do painel com pouca altura útil), folga para o botão do
/// chat, cores só por token e nada espremido em 320dp com texto a 130%.
class PublicSitePage extends StatefulWidget {
  const PublicSitePage({super.key});

  @override
  State<PublicSitePage> createState() => _PublicSitePageState();
}

/// Uma das três tintas do site já resolvida: a escolhida no painel ou, sem
/// escolha, a de fábrica do modelo.
class _SitePaint {
  final String name;
  final String caption;
  final Color color;
  final String code;
  final bool isDefault;

  const _SitePaint({
    required this.name,
    required this.caption,
    required this.color,
    required this.code,
    required this.isDefault,
  });
}

/// O passo que destrava o site agora — a frase do alto da tela.
class _NextStep {
  final IconData icon;
  final Color tone;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _NextStep({
    required this.icon,
    required this.tone,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });
}

class _PublicSitePageState extends State<PublicSitePage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;

  /// Folga no fim da rolagem: o botão flutuante do chat (56dp, a 80dp do pé)
  /// não cobre o último campo nem a barra de salvar que entra no painel.
  static const double _kPagePadBottom = 140;
  static const double _kSectionGap = 12;

  /// Coluna de leitura no tablet e na paisagem larga — nada estica em 1000dp.
  static const double _kMaxContentWidth = 720;

  /// Abaixo desta altura útil (paisagem, teclado aberto) a barra de salvar
  /// sai do pé da tela e entra no fim do painel: fixa, ela espremeria os
  /// campos até sumirem.
  static const double _kDockMinHeight = 300;

  /// Tela baixa (celular deitado): o alto mostra só a barra de endereço, a
  /// situação e o próximo passo — o mini-site passaria da altura da tela.
  static const double _kCompactHeroHeight = 480;

  static const String _readOnlyText =
      'Somente leitura — quem libera a edição é o administrador da empresa, '
      'na permissão “Gerenciar o Meu Site e o Link in Bio”.';

  _SiteTab _activeTab = _SiteTab.overview;
  final GlobalKey _tabsKey = GlobalKey();

  PublicSiteConfig? _config;
  List<PublicSiteTemplateInfo> _templates = const [];
  PublicSiteDnsInstructions? _dns;
  bool _loading = true;
  String? _error;
  // Guardado junto da mensagem: sem o código HTTP não dá para distinguir
  // "sem permissão" de "servidor fora do ar".
  int _errorStatus = 0;

  // Publicação
  bool _publishing = false;

  // Seções (rascunho local + dirty)
  List<PublicSiteHomeBlock> _blocksDraft = const [];
  bool _blocksDirty = false;
  bool _blocksSaving = false;

  // Textos, contato e Google
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

  /// E-mail recusado no último "Salvar" — a MESMA checagem de sempre (só
  /// quando preenchido), agora escrita também sob o próprio campo.
  String? _emailError;

  // Domínio
  final _domainController = TextEditingController();
  bool _domainSaving = false;
  bool _dnsVerifying = false;

  /// Guia do provedor (passo a passo + onde criar) aberto ou fechado. `null`
  /// = automático: aberto enquanto o DNS ainda não foi encontrado.
  bool? _dnsGuideOpen;

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

  // ─── Cores (só tokens) ────────────────────────────────────────────────────

  bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  Color _accentColor(BuildContext context) => _isDark(context)
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;

  Color _green(BuildContext context) => _isDark(context)
      ? AppColors.status.greenDarkMode
      : AppColors.status.green;

  Color _amber(BuildContext context) => _isDark(context)
      ? AppColors.status.warningDarkMode
      : AppColors.status.warning;

  Color _blue(BuildContext context) =>
      _isDark(context) ? AppColors.status.infoDarkMode : AppColors.status.info;

  Color _red(BuildContext context) => _isDark(context)
      ? AppColors.status.errorDarkMode
      : AppColors.status.error;

  Color _tone(BuildContext context, _SiteTab tab) {
    switch (tab) {
      case _SiteTab.overview:
        return _accentColor(context);
      case _SiteTab.sections:
        return _isDark(context)
            ? AppColors.status.purpleDarkMode
            : AppColors.status.purple;
      case _SiteTab.content:
        return _blue(context);
      case _SiteTab.domain:
        return _amber(context);
    }
  }

  Color _domainStatusColor(BuildContext context, PublicSiteDomainStatus st) {
    switch (st) {
      case PublicSiteDomainStatus.active:
        return _green(context);
      case PublicSiteDomainStatus.pendingDns:
        return _amber(context);
      // 29/09/2026: "Emitindo HTTPS" e "Revisão manual" são processamento
      // do nosso lado (azul); "Falhou" e "Desativado" são erro (vermelho).
      case PublicSiteDomainStatus.pendingSsl:
      case PublicSiteDomainStatus.pendingReview:
        return _blue(context);
      case PublicSiteDomainStatus.failed:
      case PublicSiteDomainStatus.disabled:
        return _red(context);
    }
  }

  /// Situação do domínio em palavras — o rótulo cru ("Ativo", "Falhou")
  /// ficava ambíguo ao lado de "No ar".
  String _domainStateTitle(PublicSiteDomainStatus st) {
    switch (st) {
      case PublicSiteDomainStatus.active:
        return 'Domínio ativo';
      case PublicSiteDomainStatus.pendingDns:
        return 'Aguardando DNS';
      case PublicSiteDomainStatus.pendingSsl:
        return 'Emitindo HTTPS';
      case PublicSiteDomainStatus.pendingReview:
        return 'Em revisão manual';
      case PublicSiteDomainStatus.failed:
        return 'HTTPS não emitido';
      case PublicSiteDomainStatus.disabled:
        return 'Domínio desativado';
    }
  }

  IconData _domainStateIcon(PublicSiteDomainStatus st) {
    switch (st) {
      case PublicSiteDomainStatus.active:
        return LucideIcons.circleCheckBig;
      case PublicSiteDomainStatus.pendingDns:
        return LucideIcons.clock3;
      case PublicSiteDomainStatus.pendingSsl:
      case PublicSiteDomainStatus.pendingReview:
        return LucideIcons.hourglass;
      case PublicSiteDomainStatus.failed:
        return LucideIcons.circleAlert;
      case PublicSiteDomainStatus.disabled:
        return LucideIcons.circleX;
    }
  }

  /// O que a situação do domínio quer dizer e o que fazer, numa frase.
  String _domainExplanation(
    PublicSiteConfig cfg,
    PublicSiteDnsInstructions dns,
  ) {
    switch (cfg.domainStatus) {
      case PublicSiteDomainStatus.active:
        return 'Domínio ativo — o site responde em '
            '${(cfg.customDomain ?? '').trim()}.';
      case PublicSiteDomainStatus.pendingDns:
        // 29/09/2026 (integ-02): cita o que o back pede de verdade (hoje,
        // registro A em www E em @), nunca "CNAME" fixo.
        return 'Crie ${dns.recordsToCreateLabel} no seu provedor e toque em '
            '"Verificar DNS" — quando o DNS propagar, o domínio é ativado '
            'sozinho.';
      case PublicSiteDomainStatus.pendingSsl:
        return 'O DNS já aponta para o site. Falta o certificado de '
            'segurança (HTTPS), que sai sozinho em 1 a 5 minutos — depois, '
            'toque em "Verificar DNS".';
      case PublicSiteDomainStatus.pendingReview:
        return 'O DNS já aponta para o site e o domínio está em revisão '
            'manual pela equipe de suporte. Você não precisa fazer nada '
            'agora.';
      case PublicSiteDomainStatus.failed:
        return 'O DNS está certo, mas o certificado HTTPS não foi emitido no '
            'prazo. Toque em "Verificar DNS" para tentar de novo.';
      case PublicSiteDomainStatus.disabled:
        return 'Este domínio foi desativado e o site não responde nele. Fale '
            'com o suporte para reativar.';
    }
  }

  // ─── Dados ────────────────────────────────────────────────────────────────

  /// [silent] = puxar para atualizar com a tela montada: recarrega os mesmos
  /// três GETs sem trocar o site pelo esqueleto e sem descartar rascunho
  /// não salvo; se falhar, a tela fica como estava e o aviso diz a causa.
  Future<void> _load({bool silent = false}) async {
    final quiet = silent && _config != null;
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
        _errorStatus = 0;
      });
    }
    final results = await Future.wait([
      PublicSiteService.instance.getConfig(),
      PublicSiteService.instance.getTemplates(),
      PublicSiteService.instance.getDnsInstructions(),
    ]);
    if (!mounted) return;

    final cfgRes = results[0] as dynamic;
    final tplRes = results[1] as dynamic;
    final dns = results[2] as PublicSiteDnsInstructions;
    final ok = cfgRes.success == true && cfgRes.data != null;

    setState(() {
      _loading = false;
      _dns = dns;
      if (ok) {
        _applyConfig(cfgRes.data as PublicSiteConfig, resetDrafts: !quiet);
        _error = null;
        _errorStatus = 0;
      } else if (!quiet) {
        _error = cfgRes.message ?? 'Erro ao carregar configuração do site';
        _errorStatus = cfgRes.statusCode;
      }
      if (tplRes.success && tplRes.data != null) {
        _templates = tplRes.data as List<PublicSiteTemplateInfo>;
      }
    });
    if (quiet && !ok) {
      _showSnack(
        siteFailureMessage(
          cfgRes.message as String?,
          cfgRes.statusCode as int,
          fallback: 'Não foi possível atualizar agora — tente de novo.',
        ),
        tone: SiteSnackTone.error,
      );
    }
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
        _errorStatus = 0;
      }
    });
  }

  // ─── Ações ────────────────────────────────────────────────────────────────

  void _showSnack(String message, {SiteSnackTone tone = SiteSnackTone.info}) {
    if (!mounted) return;
    siteShowSnack(context, message, tone: tone);
  }

  /// Troca de aba. [reveal] = veio do "próximo passo" ou do "o que falta":
  /// rola até as abas, para a pessoa ver o painel que abriu (em tela baixa
  /// ele fica abaixo da dobra).
  void _openTab(_SiteTab tab, {bool reveal = false}) {
    if (_activeTab != tab) setState(() => _activeTab = tab);
    if (!reveal) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _tabsKey.currentContext;
      if (!mounted || target == null) return;
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _copyUrl() async {
    final url = _config?.bestPublicUrl;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    _showSnack('Endereço do site copiado', tone: SiteSnackTone.success);
  }

  Future<void> _openSite() async {
    final url = _config?.bestPublicUrl;
    if (url == null) return;
    await _openExternal(url, failure: 'Não foi possível abrir o site');
  }

  Future<void> _openExternal(String url, {required String failure}) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) _showSnack(failure, tone: SiteSnackTone.error);
  }

  Future<void> _copyText(String value, {String? feedback}) async {
    await Clipboard.setData(ClipboardData(text: value));
    _showSnack(feedback ?? 'Copiado', tone: SiteSnackTone.success);
  }

  Future<void> _togglePublish() async {
    final cfg = _config;
    if (cfg == null || _publishing) return;

    if (cfg.isPublished) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final red = Theme.of(ctx).brightness == Brightness.dark
              ? AppColors.status.errorDarkMode
              : AppColors.status.error;
          return AlertDialog(
            scrollable: true,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text('Tirar o site do ar?'),
            content: const Text(
              'O site sai do ar na hora e os visitantes deixam de acessá-lo. '
              'Você pode publicar de novo quando quiser.',
            ),
            actions: [
              // Cancelar NEUTRO — o tema pinta TextButton de vermelho.
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
                  backgroundColor: siteSolid(red),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Tirar do ar'),
              ),
            ],
          );
        },
      );
      if (confirmed != true || !mounted) return;
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
    if (res.success && res.data != null) {
      _showSnack(
        res.data!.isPublished ? 'Site no ar' : 'Site fora do ar',
        tone: SiteSnackTone.success,
      );
    } else {
      _showSnack(
        siteFailureMessage(
          res.message,
          res.statusCode,
          fallback: 'Não foi possível alterar a publicação — tente de novo.',
        ),
        tone: SiteSnackTone.error,
      );
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
    if (res.success) {
      _showSnack('Seções salvas', tone: SiteSnackTone.success);
    } else {
      _showSnack(
        siteFailureMessage(
          res.message,
          res.statusCode,
          fallback: 'Não foi possível salvar as seções — tente de novo.',
        ),
        tone: SiteSnackTone.error,
      );
    }
  }

  void _discardBlocks() {
    setState(() {
      _blocksDraft = List.of(_config!.editorHomeBlocks);
      _blocksDirty = false;
    });
  }

  /// Formato mínimo de e-mail (algo@dominio.tld) — o `@IsEmail` do back é a
  /// palavra final; isto só evita a ida e volta no erro óbvio.
  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  Future<void> _saveContent() async {
    final cfg = _config;
    if (cfg == null || _contentSaving) return;

    // 29/09/2026 (integ-03): o e-mail NÃO é obrigatório (igual ao web e ao
    // DTO, `@IsOptional`). Só é validado quando preenchido; vazio vai como
    // `null` (o toJson cuida) e o save passa. Antes o app mandava '' e o
    // `@IsEmail` do back devolvia 400 — empresa sem e-mail não salvava nada
    // desta aba.
    final email = _emailController.text.trim();
    if (email.isNotEmpty && !_emailPattern.hasMatch(email)) {
      const reason = 'E-mail inválido — corrija ou deixe o campo vazio';
      setState(() => _emailError = reason);
      _showSnack(reason, tone: SiteSnackTone.error);
      return;
    }
    setState(() {
      _contentSaving = true;
      _emailError = null;
    });

    // Parte do conteúdo carregado; o toJson manda só os campos desta aba e o
    // merge raso do back preserva o resto (redes sociais, endereço, selos,
    // cabeçalho, GA…) do jeito que o web salvou.
    final content = cfg.content.copyWith(
      tagline: _taglineController.text.trim(),
      aboutText: _aboutController.text.trim(),
      whatsapp: _whatsappController.text.trim(),
      phone: _phoneController.text.trim(),
      email: email,
      ctaText: _ctaController.text.trim(),
    );
    final seo = cfg.seo.copyWith(
      title: _seoTitleController.text.trim(),
      description: _seoDescriptionController.text.trim(),
    );

    final res = await PublicSiteService.instance.updateConfig({
      'content': content.toJson(),
      'seo': seo.toJson(),
    });
    if (!mounted) return;
    setState(() {
      _contentSaving = false;
      if (res.success && res.data != null) {
        // Só o rascunho DESTA aba volta ao que o servidor gravou; seções
        // alteradas e ainda não salvas continuam como estão (antes o
        // `resetDrafts: true` descartava as duas coisas juntas).
        _contentDirty = false;
        _applyConfig(res.data!);
      }
    });
    if (res.success) {
      _showSnack('Textos salvos', tone: SiteSnackTone.success);
    } else {
      _showSnack(
        siteFailureMessage(
          res.message,
          res.statusCode,
          fallback: 'Não foi possível salvar os textos — tente de novo.',
        ),
        tone: SiteSnackTone.error,
      );
    }
  }

  void _discardContent() {
    setState(() {
      // Idem: descartar os textos não mexe nas seções em rascunho.
      _contentDirty = false;
      _emailError = null;
      _applyConfig(_config!);
    });
  }

  Future<void> _saveDomain() async {
    final domain = _domainController.text.trim();
    if (domain.isEmpty) {
      _showSnack(
        'Informe o domínio do site (ex.: www.suaimobiliaria.com.br)',
        tone: SiteSnackTone.error,
      );
      return;
    }
    if (_domainSaving) return;
    FocusScope.of(context).unfocus();
    setState(() => _domainSaving = true);
    final res = await PublicSiteService.instance.updateCustomDomain(domain);
    if (!mounted) return;
    setState(() {
      _domainSaving = false;
      if (res.success && res.data != null) _applyConfig(res.data!);
    });
    // 29/09/2026 (integ-02): o sucesso dizia "configure o CNAME"; agora diz
    // os registros que o back pede de verdade (A em www e em @ hoje).
    final dns = _dns ?? PublicSiteDnsInstructions.fromJson(null);
    if (res.success) {
      _showSnack(
        'Domínio salvo — crie ${dns.recordsToCreateLabel} e toque em '
        '"Verificar DNS"',
        tone: SiteSnackTone.success,
      );
    } else {
      _showSnack(
        siteFailureMessage(
          res.message,
          res.statusCode,
          fallback: 'Não foi possível salvar o domínio — tente de novo.',
        ),
        tone: SiteSnackTone.error,
      );
    }
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
      final result = res.data!;
      _showSnack(
        result.message.isNotEmpty
            ? result.message
            : (result.verified
                  ? 'Domínio verificado e ativo'
                  : 'O DNS ainda não propagou — tente de novo em alguns '
                        'minutos'),
        tone: result.verified ? SiteSnackTone.success : SiteSnackTone.info,
      );
    } else {
      setState(() => _dnsVerifying = false);
      _showSnack(
        siteFailureMessage(
          res.message,
          res.statusCode,
          fallback: 'Não foi possível verificar o DNS agora — tente de novo.',
        ),
        tone: SiteSnackTone.error,
      );
    }
  }

  // ─── Auxiliares de leitura ────────────────────────────────────────────────

  String _displayUrl(String url) => url
      .replaceFirst(RegExp(r'^https?://'), '')
      .replaceFirst(RegExp(r'/+$'), '');

  String _templateName(PublicSiteConfig cfg) {
    for (final t in _templates) {
      if (t.id == cfg.templateId) return t.name;
    }
    return _fallbackTemplateLabel(cfg.templateId);
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

  /// As três tintas que o site usa de verdade — mesma regra do web (Ato 03):
  /// a cor escolhida no painel ou, sem escolha, a de fábrica do modelo.
  List<_SitePaint> _paints(PublicSiteConfig cfg) {
    final factoryPaints =
        kPublicSiteFactoryPaints[cfg.templateId] ??
        kPublicSiteFactoryPaints['classic']!;
    _SitePaint paint(
      String name,
      String caption,
      String? chosen,
      String factoryHex,
    ) {
      final chosenColor = siteParseHexColor(chosen);
      final hex = chosenColor != null ? chosen!.trim() : factoryHex;
      return _SitePaint(
        name: name,
        caption: caption,
        color:
            chosenColor ??
            siteParseHexColor(factoryHex) ??
            _accentColor(context),
        code: '#${hex.replaceFirst('#', '').toUpperCase()}',
        isDefault: chosenColor == null,
      );
    }

    return [
      paint(
        'Primária',
        'botões e destaques',
        cfg.branding.primaryColor,
        factoryPaints.primary,
      ),
      paint(
        'Secundária',
        'fundos e apoios',
        cfg.branding.secondaryColor,
        factoryPaints.secondary,
      ),
      paint(
        'Acento',
        'detalhes e links',
        cfg.branding.accentColor,
        factoryPaints.accent,
      ),
    ];
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
      // LayoutBuilder FORA do RefreshIndicator (entre ele e a lista, crasha).
      body: LayoutBuilder(
        builder: (context, box) {
          final sidePad = box.maxWidth > _kMaxContentWidth + _kPagePadH * 2
              ? (box.maxWidth - _kMaxContentWidth) / 2
              : _kPagePadH;
          final dockBar = box.maxHeight >= _kDockMinHeight;
          final compactHero =
              MediaQuery.sizeOf(context).height < _kCompactHeroHeight;
          final ready = !_loading && _error == null && _config != null;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: RefreshIndicator(
                  color: _accentColor(context),
                  onRefresh: () => _load(silent: true),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.zero,
                    children: _loading
                        ? [_buildPageSkeleton(context, sidePad)]
                        : _error != null
                        ? [
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                sidePad,
                                48,
                                sidePad,
                                _kPagePadBottom,
                              ),
                              child: SiteErrorState(
                                message: _error!,
                                statusCode: _errorStatus,
                                onRetry: _load,
                              ),
                            ),
                          ]
                        : [
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                sidePad,
                                _kPagePadTop,
                                sidePad,
                                0,
                              ),
                              child: _buildBrowserHero(
                                context,
                                compact: compactHero,
                              ),
                            ),
                            const SizedBox(height: _kSectionGap + 4),
                            _buildTabsRail(context, sidePad),
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                sidePad,
                                _kSectionGap + 4,
                                sidePad,
                                _kPagePadBottom,
                              ),
                              child: _buildActivePanel(
                                context,
                                inlineSave: !dockBar,
                              ),
                            ),
                          ],
                  ),
                ),
              ),
              if (ready && dockBar) _buildSaveBar(context, docked: true),
            ],
          );
        },
      ),
    );
  }

  // ─── Alto: o site é o protagonista (moldura de navegador) ────────────────

  Widget _buildBrowserHero(BuildContext context, {required bool compact}) {
    final cfg = _config!;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final published = cfg.isPublished;
    final url = cfg.bestPublicUrl;
    final hasUrl = url != null;
    final domain = (cfg.customDomain ?? '').trim();
    final hasDomain = domain.isNotEmpty;
    final address = hasDomain
        ? domain
        : (url != null ? _displayUrl(url) : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBrowserFrame(
          context,
          address: address,
          published: published,
          compact: compact,
        ),
        const SizedBox(height: 12),
        // Situação em selos (quebram de linha em vez de estourar) + abrir e
        // copiar o endereço, sempre à mão em qualquer aba.
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SiteMiniPill(
                    label: published ? 'No ar' : 'Fora do ar',
                    tone: published ? _green(context) : _amber(context),
                    icon: published
                        ? LucideIcons.circleCheckBig
                        : LucideIcons.circleDashed,
                  ),
                  SiteMiniPill(
                    label: hasDomain
                        ? _domainStateTitle(cfg.domainStatus)
                        : 'Sem domínio',
                    tone: hasDomain
                        ? _domainStatusColor(context, cfg.domainStatus)
                        : secondary,
                    icon: hasDomain
                        ? _domainStateIcon(cfg.domainStatus)
                        : LucideIcons.globe,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            SiteRowAction(
              icon: LucideIcons.externalLink,
              tooltip: 'Abrir o site',
              tone: _accentColor(context),
              onTap: hasUrl ? _openSite : null,
            ),
            SiteRowAction(
              icon: LucideIcons.copy,
              tooltip: 'Copiar o endereço',
              tone: secondary,
              onTap: hasUrl ? _copyUrl : null,
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildNextStep(context),
      ],
    );
  }

  /// Moldura de "navegador": três pontinhos NEUTROS (dizem "janela" sem
  /// arco-íris) + campo de endereço com o domínio real; embaixo, o mini-site.
  Widget _buildBrowserFrame(
    BuildContext context, {
    required String? address,
    required bool published,
    required bool compact,
  }) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final hairline = siteHairline(context);
    final secure = published && address != null;

    Widget browserDot() => Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(shape: BoxShape.circle, color: hairline),
    );

    final bar = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          browserDot(),
          const SizedBox(width: 5),
          browserDot(),
          const SizedBox(width: 5),
          browserDot(),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: siteFieldFill(context),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                children: [
                  Icon(
                    secure ? LucideIcons.lock : LucideIcons.globe,
                    size: 12,
                    color: secure
                        ? siteInk(context, _green(context))
                        : secondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      address ?? 'Endereço ainda não definido',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: address != null
                            ? FontWeight.w800
                            : FontWeight.w600,
                        letterSpacing: -0.1,
                        color: address != null
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
    );

    final frame = Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: hairline),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          bar,
          if (!compact) ...[
            Divider(
              height: 1,
              thickness: 1,
              color: ThemeHelpers.borderLightColor(context),
            ),
            _buildSitePreview(context),
          ],
        ],
      ),
    );
    return frame
        .animate()
        .fadeIn(duration: 300.ms)
        .moveY(begin: 8, end: 0, curve: Curves.easeOut);
  }

  /// Mini-site montado só com dados reais: logo, título, modelo, as três
  /// tintas, a frase e o botão do banner e as seções ligadas.
  Widget _buildSitePreview(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = _isDark(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final fill = siteFieldFill(context);
    final cfg = _config!;
    final paints = _paints(cfg);
    final brand = paints.first.color;
    final siteTitle = (cfg.seo.title ?? '').trim();
    final tagline = (cfg.content.tagline ?? '').trim();
    final cta = (cfg.content.ctaText ?? '').trim();
    final enabledBlocks = _blocksDraft
        .where((b) => b.enabled)
        .toList(growable: false);

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _buildLogoBox(context, size: 40, brand: brand),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      siteTitle.isNotEmpty ? siteTitle : 'Seu site imobiliário',
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
                      'Modelo ${_templateName(cfg)}'
                      '${cfg.premiumTemplateUnlocked ? ' · Premium' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: secondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              for (var i = 0; i < paints.length; i++)
                Container(
                  width: 14,
                  height: 14,
                  margin: EdgeInsets.only(left: i == 0 ? 0 : 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: paints[i].color,
                    border: Border.all(color: siteHairline(context)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // "Banner" do site — frase + botão na cor da marca, em tinta
          // chapada (o degradê de antes era enfeite inventado).
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: brand.withValues(alpha: isDark ? 0.18 : 0.08),
              border: Border.all(color: brand.withValues(alpha: 0.24)),
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
                      fontSize: 11.5,
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
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Container(
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
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.1,
                        color: siteOnColor(brand),
                      ),
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
                for (var i = 0; i < enabledBlocks.length && i < 4; i++) ...[
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
                          color: fill,
                        ),
                        child: Icon(
                          PublicSiteBlockCatalog.iconOf(enabledBlocks[i].type),
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
                    constraints: const BoxConstraints(minHeight: 30),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      color: fill,
                    ),
                    child: Text(
                      '+${enabledBlocks.length - 4}',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${enabledBlocks.length} '
              '${enabledBlocks.length == 1 ? 'seção' : 'seções'} na página '
              'inicial',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: secondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Logo numa caixa de tamanho FIXO: a imagem cabe inteira (contain, sem
  /// cortar a marca); sem logo, o prédio em cinza sobre o tom da marca.
  Widget _buildLogoBox(
    BuildContext context, {
    required double size,
    required Color brand,
  }) {
    final isDark = _isDark(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final logo = (_config!.branding.logoUrl ?? '').trim();
    final hasLogo = logo.isNotEmpty;
    final placeholder = Icon(
      LucideIcons.building2,
      size: size * 0.45,
      color: secondary,
    );
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(hasLogo ? size * 0.1 : 0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        color: hasLogo
            ? ThemeHelpers.cardBackgroundColor(context)
            : brand.withValues(alpha: isDark ? 0.2 : 0.1),
        border: Border.all(
          color: hasLogo ? siteHairline(context) : brand.withValues(alpha: 0.3),
        ),
      ),
      child: hasLogo
          ? Image.network(
              logo,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => placeholder,
            )
          : placeholder,
    );
  }

  /// O passo que destrava o site agora — mesma ordem do "conselheiro" do
  /// web: domínio → DNS → publicar → no ar.
  _NextStep _nextStep(BuildContext context) {
    final cfg = _config!;
    final dns = _dns ?? PublicSiteDnsInstructions.fromJson(null);
    final domain = (cfg.customDomain ?? '').trim();
    void goDomain() => _openTab(_SiteTab.domain, reveal: true);

    if (domain.isEmpty) {
      return _NextStep(
        icon: LucideIcons.globe,
        tone: _amber(context),
        title: 'Próximo passo: informe o domínio do site',
        body:
            'É o endereço em que os visitantes vão abrir o site (ex.: '
            'www.suaimobiliaria.com.br).',
        actionLabel: 'Configurar o domínio',
        onAction: goDomain,
      );
    }
    switch (cfg.domainStatus) {
      case PublicSiteDomainStatus.pendingDns:
        return _NextStep(
          icon: LucideIcons.network,
          tone: _amber(context),
          title: 'Próximo passo: crie ${dns.recordsToCreateLabel}',
          body:
              'No painel de DNS do seu domínio. Depois, toque em "Verificar '
              'DNS" — o domínio é ativado sozinho quando propagar.',
          actionLabel: 'Ver como fazer',
          onAction: goDomain,
        );
      case PublicSiteDomainStatus.pendingSsl:
        return _NextStep(
          icon: LucideIcons.hourglass,
          tone: _blue(context),
          title: 'Quase lá: emitindo o HTTPS do domínio',
          body:
              'O DNS já aponta para o site. O certificado sai em 1 a 5 '
              'minutos — depois, toque em "Verificar DNS".',
          actionLabel: 'Verificar o DNS',
          onAction: goDomain,
        );
      case PublicSiteDomainStatus.pendingReview:
        return _NextStep(
          icon: LucideIcons.hourglass,
          tone: _blue(context),
          title: 'Domínio em revisão manual',
          body:
              'O DNS já aponta para o site; a liberação é feita pela equipe '
              'de suporte. Você não precisa fazer nada agora.',
          actionLabel: 'Ver o domínio',
          onAction: goDomain,
        );
      case PublicSiteDomainStatus.failed:
        return _NextStep(
          icon: LucideIcons.circleAlert,
          tone: _red(context),
          title: 'O HTTPS do domínio não foi emitido',
          body:
              'O DNS está certo, mas o certificado não saiu no prazo. Toque em '
              '"Verificar DNS" para tentar de novo.',
          actionLabel: 'Resolver',
          onAction: goDomain,
        );
      case PublicSiteDomainStatus.disabled:
        return _NextStep(
          icon: LucideIcons.circleX,
          tone: _red(context),
          title: 'Domínio desativado',
          body:
              'O site não responde neste domínio. Fale com o suporte para '
              'reativar.',
          actionLabel: 'Ver o domínio',
          onAction: goDomain,
        );
      case PublicSiteDomainStatus.active:
        break;
    }
    if (!cfg.isPublished) {
      return _NextStep(
        icon: LucideIcons.rocket,
        tone: _green(context),
        title: 'Tudo pronto — falta publicar',
        body: _canManage
            ? 'O domínio já está ativo. Visitantes só veem o site depois de '
                  'publicado.'
            : 'O domínio já está ativo. Peça a quem gerencia o site para '
                  'publicar.',
        actionLabel: _canManage ? 'Publicar o site' : null,
        onAction: _canManage && !_publishing ? _togglePublish : null,
      );
    }
    return _NextStep(
      icon: LucideIcons.circleCheckBig,
      tone: _green(context),
      title: 'Site no ar em $domain',
      body: 'Alterações salvas nas abas abaixo entram direto no site.',
    );
  }

  Widget _buildNextStep(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = _isDark(context);
    final step = _nextStep(context);
    final ink = siteInk(context, step.tone);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: step.tone.withValues(alpha: isDark ? 0.12 : 0.07),
        border: Border.all(
          color: step.tone.withValues(alpha: isDark ? 0.32 : 0.28),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(step.icon, size: 18, color: ink),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                    letterSpacing: -0.2,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  step.body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    height: 1.4,
                  ),
                ),
                if (step.actionLabel != null) ...[
                  const SizedBox(height: 2),
                  TextButton.icon(
                    onPressed: step.onAction,
                    iconAlignment: IconAlignment.end,
                    style: TextButton.styleFrom(
                      foregroundColor: ink,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      minimumSize: const Size(44, 40),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(LucideIcons.arrowRight, size: 15),
                    label: SiteButtonLabel(step.actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Abas flush ───────────────────────────────────────────────────────────

  Widget _buildTabsRail(BuildContext context, double sidePad) {
    return Container(
      key: _tabsKey,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: sidePad - 8),
      child: Row(
        children: [
          for (final tab in _SiteTab.values)
            Expanded(
              child: SiteFlushTab(
                icon: _tabIcon(tab),
                label: _tabLabel(tab),
                tone: _tone(context, tab),
                selected: _activeTab == tab,
                // Ponto âmbar estático: rascunho não salvo nesta aba.
                dirty:
                    (tab == _SiteTab.sections && _blocksDirty) ||
                    (tab == _SiteTab.content && _contentDirty),
                onTap: () => _openTab(tab),
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

  /// Rótulos curtos: 4 abas em 320dp com fonte a 130% sem encolher até
  /// ficar ilegível ("Visão geral" virava ~8px).
  String _tabLabel(_SiteTab tab) {
    switch (tab) {
      case _SiteTab.overview:
        return 'Resumo';
      case _SiteTab.sections:
        return 'Seções';
      case _SiteTab.content:
        return 'Textos';
      case _SiteTab.domain:
        return 'Domínio';
    }
  }

  // ─── Painéis ──────────────────────────────────────────────────────────────

  Widget _buildActivePanel(BuildContext context, {required bool inlineSave}) {
    final Widget child;
    switch (_activeTab) {
      case _SiteTab.overview:
        child = _buildOverviewPanel(context);
        break;
      case _SiteTab.sections:
        child = _buildSectionsPanel(context, inlineSave: inlineSave);
        break;
      case _SiteTab.content:
        child = _buildContentPanel(context, inlineSave: inlineSave);
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
          title: 'Resumo do site',
          hint:
              'Se está no ar, o que falta para ir ao ar e como o site se '
              'apresenta.',
        );
      case _SiteTab.sections:
        return (
          icon: LucideIcons.layoutList,
          title: 'Seções da página inicial',
          hint:
              'O que aparece na página inicial e em que ordem — de cima para '
              'baixo, como no site.',
        );
      case _SiteTab.content:
        return (
          icon: LucideIcons.penLine,
          title: 'Textos e contato',
          hint:
              'O que o visitante lê, como fala com você e como o site aparece '
              'no Google.',
        );
      case _SiteTab.domain:
        return (
          icon: LucideIcons.globe,
          title: 'Endereço do site',
          hint:
              'Use o seu domínio em 3 passos: informe, crie os registros no '
              'provedor e verifique.',
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
        const SizedBox(height: 16),
        ...body,
      ],
    );
  }

  /// Barra de salvar da aba aberta (Seções ou Textos); nas outras, nada.
  Widget _buildSaveBar(BuildContext context, {required bool docked}) {
    const maxWidth = _kMaxContentWidth + _kPagePadH * 2;
    switch (_activeTab) {
      case _SiteTab.sections:
        return SiteSaveBar(
          docked: docked,
          maxContentWidth: maxWidth,
          visible: _canManage && _blocksDirty,
          saving: _blocksSaving,
          label: 'Salvar seções',
          pendingText: 'Seções alteradas — o site só muda depois de salvar.',
          onSave: _saveBlocks,
          onDiscard: _discardBlocks,
        );
      case _SiteTab.content:
        return SiteSaveBar(
          docked: docked,
          maxContentWidth: maxWidth,
          visible: _canManage && _contentDirty,
          saving: _contentSaving,
          label: 'Salvar textos',
          pendingText: 'Textos alterados — o site só muda depois de salvar.',
          onSave: _saveContent,
          onDiscard: _discardContent,
        );
      case _SiteTab.overview:
      case _SiteTab.domain:
        return const SizedBox.shrink();
    }
  }

  // ── Resumo ──

  Widget _buildOverviewPanel(BuildContext context) {
    return _panelShell(context, _SiteTab.overview, [
      _buildPublishCard(context),
      const SizedBox(height: 22),
      _buildReadiness(context),
      const SizedBox(height: 22),
      _buildIdentity(context),
    ]);
  }

  /// Publicação: a situação em manchete e a ação principal no próprio
  /// cartão (sem permissão, travada com o cadeado e o motivo).
  Widget _buildPublishCard(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = _isDark(context);
    final cfg = _config!;
    final published = cfg.isPublished;
    final tone = published ? _green(context) : _amber(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final dateFmt = DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR');

    final String body;
    if (published) {
      body = cfg.publishedAt != null
          ? 'Publicado em ${dateFmt.format(cfg.publishedAt!.toLocal())}. '
                'Alterações salvas entram direto no site.'
          : 'Visível para qualquer visitante. Alterações salvas entram '
                'direto no site.';
    } else {
      body =
          'Publique quando o DNS estiver ativo — visitantes só veem o site '
          'depois de publicado.';
    }

    Widget spinner(Color color) => SizedBox(
      width: 15,
      height: 15,
      child: CircularProgressIndicator(strokeWidth: 2, color: color),
    );

    final Widget action;
    if (!_canManage) {
      action = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: null,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: ThemeHelpers.borderColor(context)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            ),
            icon: const Icon(LucideIcons.lock, size: 16),
            label: SiteButtonLabel(
              published ? 'Tirar o site do ar' : 'Publicar site',
            ),
          ),
          const SizedBox(height: 8),
          const SiteReadOnlyNotice(
            dense: true,
            text:
                'Quem publica ou tira o site do ar é quem tem a permissão '
                '“Gerenciar o Meu Site e o Link in Bio”.',
          ),
        ],
      );
    } else if (published) {
      // Tirar do ar é destrutivo mas raro: vermelho VAZADO aqui; a
      // confirmação tem o vermelho cheio com texto branco.
      final red = _red(context);
      action = OutlinedButton.icon(
        onPressed: _publishing ? null : _togglePublish,
        style: OutlinedButton.styleFrom(
          foregroundColor: siteInk(context, red),
          side: BorderSide(color: red.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        ),
        icon: _publishing
            ? spinner(siteInk(context, red))
            : const Icon(LucideIcons.cloudOff, size: 17),
        label: SiteButtonLabel(_publishing ? 'Aguarde…' : 'Tirar o site do ar'),
      );
    } else {
      // Publicar = confirmar → verde, escurecido até o branco passar de
      // 4,5:1 nos dois temas.
      final solid = siteSolid(_green(context));
      action = FilledButton.icon(
        onPressed: _publishing ? null : _togglePublish,
        style: FilledButton.styleFrom(
          backgroundColor: solid,
          foregroundColor: Colors.white,
          disabledBackgroundColor: solid.withValues(alpha: 0.6),
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        ),
        icon: _publishing
            ? spinner(Colors.white)
            : const Icon(LucideIcons.rocket, size: 17),
        label: SiteButtonLabel(_publishing ? 'Publicando…' : 'Publicar site'),
      );
    }

    return SiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Selo em caixa FIXA; o texto ao lado é que quebra.
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  color: tone.withValues(alpha: isDark ? 0.18 : 0.1),
                  border: Border.all(color: tone.withValues(alpha: 0.3)),
                ),
                child: Icon(
                  published
                      ? LucideIcons.circleCheckBig
                      : LucideIcons.circleDashed,
                  size: 21,
                  color: siteInk(context, tone),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      published
                          ? 'Seu site está no ar'
                          : 'Seu site está fora do ar',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -0.3,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      body,
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
          const SizedBox(height: 14),
          action,
        ],
      ),
    );
  }

  /// "O que falta para ir ao ar" — os mesmos itens da prontidão do web
  /// (domínio, DNS, seções, identidade) mais os textos que o app edita. Cada
  /// item que se resolve numa aba leva até ela.
  Widget _buildReadiness(BuildContext context) {
    final cfg = _config!;
    final dns = _dns ?? PublicSiteDnsInstructions.fromJson(null);
    final domain = (cfg.customDomain ?? '').trim();
    final hasDomain = domain.isNotEmpty;
    final blocks = cfg.editorHomeBlocks;
    final blocksOn = blocks.where((b) => b.enabled).length;
    final hasTagline = (cfg.content.tagline ?? '').trim().isNotEmpty;
    final hasContact = [
      cfg.content.whatsapp,
      cfg.content.phone,
      cfg.content.email,
    ].any((v) => (v ?? '').trim().isNotEmpty);
    final hasLogo = (cfg.branding.logoUrl ?? '').trim().isNotEmpty;

    final SiteCheckState dnsState;
    final String dnsValue;
    if (!hasDomain) {
      dnsState = SiteCheckState.missing;
      dnsValue = 'Vem depois do domínio';
    } else {
      switch (cfg.domainStatus) {
        case PublicSiteDomainStatus.active:
          dnsState = SiteCheckState.done;
          dnsValue = 'Ativo — o site responde no domínio';
        case PublicSiteDomainStatus.pendingDns:
          dnsState = SiteCheckState.missing;
          dnsValue = 'Crie ${dns.recordsToCreateLabel} e verifique';
        case PublicSiteDomainStatus.pendingSsl:
          dnsState = SiteCheckState.waiting;
          dnsValue = 'DNS certo — emitindo o HTTPS';
        case PublicSiteDomainStatus.pendingReview:
          dnsState = SiteCheckState.waiting;
          dnsValue = 'DNS certo — em revisão manual';
        case PublicSiteDomainStatus.failed:
          dnsState = SiteCheckState.problem;
          dnsValue = 'O HTTPS não foi emitido — verifique de novo';
        case PublicSiteDomainStatus.disabled:
          dnsState = SiteCheckState.problem;
          dnsValue = 'Domínio desativado';
      }
    }

    final missingTexts = [
      if (!hasTagline) 'a frase de destaque',
      if (!hasContact) 'um contato (WhatsApp, telefone ou e-mail)',
    ];

    final rows = <_CheckItem>[
      (
        label: 'Domínio',
        value: hasDomain ? domain : 'Não configurado',
        state: hasDomain ? SiteCheckState.done : SiteCheckState.missing,
        tab: _SiteTab.domain,
      ),
      (
        label: 'DNS do domínio',
        value: dnsValue,
        state: dnsState,
        tab: _SiteTab.domain,
      ),
      (
        label: 'Seções da página inicial',
        value: blocksOn > 0
            ? '$blocksOn de ${blocks.length} ligadas'
            : 'Nenhuma seção ligada',
        state: blocksOn > 0 ? SiteCheckState.done : SiteCheckState.missing,
        tab: _SiteTab.sections,
      ),
      (
        label: 'Textos e contato',
        value: missingTexts.isEmpty
            ? 'Frase de destaque e contato preenchidos'
            : 'Falta ${missingTexts.join(' e ')}',
        state: missingTexts.isEmpty
            ? SiteCheckState.done
            : SiteCheckState.missing,
        tab: _SiteTab.content,
      ),
      (
        label: 'Logo',
        value: hasLogo ? 'Enviada' : 'Sem logo',
        state: hasLogo ? SiteCheckState.done : SiteCheckState.missing,
        tab: null,
      ),
    ];
    final done = rows.where((r) => r.state == SiteCheckState.done).length;
    final allDone = done == rows.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SiteSubsectionHeader(
          label: 'O que falta para ir ao ar',
          icon: LucideIcons.listChecks,
          hint: 'Os itens com seta levam direto até onde se resolvem.',
          trailing: Text(
            allDone ? 'Tudo pronto' : '$done de ${rows.length} prontos',
            maxLines: 2,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              color: allDone
                  ? siteInk(context, _green(context))
                  : ThemeHelpers.textSecondaryColor(context),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SiteCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++)
                SiteCheckRow(
                  label: rows[i].label,
                  value: rows[i].value,
                  state: rows[i].state,
                  divider: i < rows.length - 1,
                  onTap: rows[i].tab == null
                      ? null
                      : () => _openTab(rows[i].tab!, reveal: true),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Identidade visual (só leitura no app): logo e tintas em caixas de
  /// tamanho FIXO — o texto ao lado encolhe, a amostra nunca é espremida.
  Widget _buildIdentity(BuildContext context) {
    final theme = Theme.of(context);
    final cfg = _config!;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final paints = _paints(cfg);
    final hasLogo = (cfg.branding.logoUrl ?? '').trim().isNotEmpty;
    final divider = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Divider(height: 1, color: ThemeHelpers.borderLightColor(context)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SiteSubsectionHeader(
          label: 'Identidade visual',
          icon: LucideIcons.palette,
          hint:
              'Como o site se apresenta: a logo e as três cores da marca, do '
              'jeito que aparecem para o visitante.',
        ),
        const SizedBox(height: 10),
        SiteCard(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _buildLogoBox(context, size: 56, brand: paints.first.color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Logo',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: ThemeHelpers.textColor(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasLogo
                              ? 'Enviada — aparece no cabeçalho do site.'
                              : 'Nenhuma logo enviada ainda.',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
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
              divider,
              LayoutBuilder(
                builder: (context, constraints) {
                  final scale = siteTextScale(context);
                  final tiles = [
                    for (final p in paints)
                      SiteSwatchTile(
                        label: p.name,
                        caption: p.caption,
                        color: p.color,
                        code: p.code,
                        isDefault: p.isDefault,
                      ),
                  ];
                  // Três lado a lado só quando cada amostra tem espaço para
                  // o nome e o código inteiros; senão, uma embaixo da outra.
                  if (constraints.maxWidth >= 3 * 190 * scale + 20) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: tiles[0]),
                        const SizedBox(width: 10),
                        Expanded(child: tiles[1]),
                        const SizedBox(width: 10),
                        Expanded(child: tiles[2]),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      tiles[0],
                      const SizedBox(height: 10),
                      tiles[1],
                      const SizedBox(height: 10),
                      tiles[2],
                    ],
                  );
                },
              ),
              divider,
              Row(
                children: [
                  Icon(LucideIcons.paintbrush, size: 15, color: secondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Modelo ',
                            style: TextStyle(
                              color: secondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextSpan(
                            text: _templateName(cfg),
                            style: TextStyle(
                              color: ThemeHelpers.textColor(context),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  if (cfg.templateId == 'premium') ...[
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 110),
                      child: SiteMiniPill(
                        label: 'Premium',
                        tone: _amber(context),
                        icon: LucideIcons.star,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              _noteLine(
                context,
                LucideIcons.info,
                'Por enquanto, logo, cores e modelo mudam só pelo painel web — '
                'lá também fica a prévia ao vivo do site.',
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Seções ──

  Widget _buildSectionsPanel(BuildContext context, {required bool inlineSave}) {
    final theme = Theme.of(context);
    final tone = _tone(context, _SiteTab.sections);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    if (_blocksDraft.isEmpty) {
      return _panelShell(context, _SiteTab.sections, [
        SiteEmptyState(
          icon: LucideIcons.layoutList,
          title: 'Nenhuma seção por aqui',
          body:
              'As seções padrão do modelo aparecem aqui assim que o site for '
              'configurado. Puxe a tela para baixo para atualizar.',
          tone: tone,
        ),
      ]);
    }

    final total = _blocksDraft.length;
    final on = _blocksDraft.where((b) => b.enabled).length;

    return _panelShell(context, _SiteTab.sections, [
      if (!_canManage) ...[
        const SiteReadOnlyNotice(text: _readOnlyText),
        const SizedBox(height: 14),
      ],
      // O número que importa em destaque, com o rótulo curto ao lado.
      Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$on',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: ThemeHelpers.textColor(context),
                letterSpacing: -0.5,
                height: 1.1,
              ),
            ),
            TextSpan(
              text:
                  ' de $total ${total == 1 ? 'seção' : 'seções'} '
                  '${on == 1 ? 'aparece' : 'aparecem'} no site',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: secondary,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 4),
      Text(
        _canManage
            ? 'Ligue ou desligue cada seção e arraste pela alça para mudar a '
                  'ordem.'
            : 'A ordem abaixo é a ordem da página inicial.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: secondary,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 12),
      SiteCard(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: _blocksDraft.length,
          // A linha arrastada ganha o fundo do cartão e o filete — sem isso
          // ela "flutuava" transparente sobre as outras.
          proxyDecorator: (child, index, animation) => Material(
            color: Colors.transparent,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: ThemeHelpers.cardBackgroundColor(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: siteHairline(context)),
                boxShadow: ThemeHelpers.cardShadow(context, strength: 2),
              ),
              child: child,
            ),
          ),
          onReorder: !_canManage
              ? (_, _) {}
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
            final position = block.enabled
                ? _blocksDraft.take(index).where((b) => b.enabled).length + 1
                : 0;
            return KeyedSubtree(
              key: ValueKey('block-${block.id}'),
              child: _buildBlockRow(
                context,
                block,
                index,
                position: position,
                tone: tone,
                last: index == _blocksDraft.length - 1,
              ),
            );
          },
        ),
      ),
      if (inlineSave) _buildSaveBar(context, docked: false),
    ]);
  }

  /// Linha flush de uma seção: alça, ícone, nome, "3ª na página · o que
  /// mostra" e a chave verde (ligada = aparece no site).
  Widget _buildBlockRow(
    BuildContext context,
    PublicSiteHomeBlock block,
    int index, {
    required int position,
    required Color tone,
    required bool last,
  }) {
    final theme = Theme.of(context);
    final isDark = _isDark(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final enabled = block.enabled;
    final description = PublicSiteBlockCatalog.descriptionOf(block.type);
    final where = enabled ? '$positionª na página' : 'Fora da página';

    return Container(
      padding: const EdgeInsets.fromLTRB(0, 10, 10, 10),
      decoration: last
          ? null
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: ThemeHelpers.borderLightColor(context),
                ),
              ),
            ),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            enabled: _canManage,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Icon(
                LucideIcons.gripVertical,
                size: 18,
                color: secondary.withValues(alpha: _canManage ? 0.85 : 0.3),
                semanticLabel: _canManage
                    ? 'Arrastar para mudar a ordem'
                    : null,
              ),
            ),
          ),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              color: (enabled ? tone : secondary).withValues(
                alpha: isDark ? 0.16 : 0.1,
              ),
            ),
            child: Icon(
              PublicSiteBlockCatalog.iconOf(block.type),
              size: 17,
              color: enabled
                  ? siteInk(context, tone)
                  : secondary.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  PublicSiteBlockCatalog.labelOf(block.type),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: enabled
                        ? ThemeHelpers.textColor(context)
                        : secondary,
                    letterSpacing: -0.1,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description.isEmpty ? where : '$where · $description',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondary,
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: enabled,
            activeTrackColor: siteSolid(_green(context)),
            activeThumbColor: Colors.white,
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

  // ── Textos, contato e Google ──

  Widget _buildContentPanel(BuildContext context, {required bool inlineSave}) {
    void markDirty(String _) {
      if (!_contentDirty) setState(() => _contentDirty = true);
    }

    // Título e descrição alimentam a prévia do Google: redesenha a cada letra.
    void markDirtyLive(String _) => setState(() => _contentDirty = true);

    return _panelShell(context, _SiteTab.content, [
      if (!_canManage) ...[
        const SiteReadOnlyNotice(text: _readOnlyText),
        const SizedBox(height: 16),
      ],
      const SiteSubsectionHeader(
        label: 'Apresentação',
        icon: LucideIcons.sparkles,
        hint:
            'O que o visitante lê primeiro: a frase do banner, o botão de '
            'contato e o texto "Sobre nós".',
      ),
      const SizedBox(height: 12),
      SiteFilledField(
        controller: _taglineController,
        label: 'Frase de destaque',
        hint: 'Encontre o imóvel dos seus sonhos',
        icon: LucideIcons.sparkles,
        helperText: 'A frase grande do banner, no alto da página.',
        enabled: _canManage,
        onChanged: markDirty,
      ),
      const SizedBox(height: 12),
      SiteFilledField(
        controller: _ctaController,
        label: 'Texto do botão de contato',
        hint: 'Fale com um corretor',
        icon: LucideIcons.megaphone,
        helperText: 'O botão principal do banner e da chamada final.',
        enabled: _canManage,
        onChanged: markDirty,
      ),
      const SizedBox(height: 12),
      SiteFilledField(
        controller: _aboutController,
        label: 'Sobre a imobiliária',
        hint: 'Conte a história e os diferenciais da empresa…',
        maxLines: 4,
        helperText: 'Aparece na seção "Sobre nós".',
        enabled: _canManage,
        onChanged: markDirty,
      ),
      const SizedBox(height: 24),
      const SiteSubsectionHeader(
        label: 'Contato',
        icon: LucideIcons.phone,
        hint: 'Por onde o visitante fala com você. Deixe vazio o que não usa.',
      ),
      const SizedBox(height: 12),
      // Lado a lado só com ~120dp úteis para "(11) 99999-9999" em cada
      // campo (ícone + recuo comem ~60): a 360dp eles empilham em vez de o
      // número rolar escondido.
      SiteRow2(
        minColumnWidth: 176,
        left: SiteFilledField(
          controller: _whatsappController,
          label: 'WhatsApp',
          hint: '(11) 99999-9999',
          icon: LucideIcons.messageCircle,
          keyboardType: TextInputType.phone,
          enabled: _canManage,
          onChanged: markDirty,
        ),
        right: SiteFilledField(
          controller: _phoneController,
          label: 'Telefone',
          hint: '(11) 3333-3333',
          icon: LucideIcons.phone,
          keyboardType: TextInputType.phone,
          enabled: _canManage,
          onChanged: markDirty,
        ),
      ),
      const SizedBox(height: 12),
      SiteFilledField(
        controller: _emailController,
        label: 'E-mail de contato',
        hint: 'contato@suaimobiliaria.com.br',
        icon: LucideIcons.mail,
        keyboardType: TextInputType.emailAddress,
        errorText: _emailError,
        enabled: _canManage,
        onChanged: (v) {
          markDirty(v);
          if (_emailError != null) setState(() => _emailError = null);
        },
      ),
      const SizedBox(height: 24),
      const SiteSubsectionHeader(
        label: 'Google (busca)',
        icon: LucideIcons.search,
        hint:
            'Como o site aparece nos resultados do Google: um título curto e '
            'uma descrição de uma ou duas frases.',
      ),
      const SizedBox(height: 12),
      SiteFilledField(
        controller: _seoTitleController,
        label: 'Título na busca',
        hint: 'Sua Imobiliária — Imóveis em São Paulo',
        icon: LucideIcons.heading,
        enabled: _canManage,
        onChanged: markDirtyLive,
      ),
      const SizedBox(height: 12),
      SiteFilledField(
        controller: _seoDescriptionController,
        label: 'Descrição na busca',
        hint: 'Compra, venda e locação de imóveis com atendimento completo…',
        maxLines: 3,
        enabled: _canManage,
        onChanged: markDirtyLive,
      ),
      const SizedBox(height: 12),
      _buildGooglePreview(context),
      if (inlineSave) _buildSaveBar(context, docked: false),
    ]);
  }

  /// Prévia do resultado no Google, ao vivo com o que está digitado.
  Widget _buildGooglePreview(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = _isDark(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final cfg = _config!;
    final title = _seoTitleController.text.trim();
    final description = _seoDescriptionController.text.trim();
    final url = cfg.bestPublicUrl;
    final domain = (cfg.customDomain ?? '').trim();
    final host = url != null
        ? _displayUrl(url)
        : (domain.isNotEmpty ? domain : 'seudominio.com.br');
    final link = isDark
        ? AppColors.message.infoTextDarkMode
        : AppColors.message.infoText;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border.all(color: siteHairline(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.search, size: 13, color: secondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'COMO APARECE NO GOOGLE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: siteFieldFill(context),
                  border: Border.all(color: siteHairline(context)),
                ),
                child: Icon(LucideIcons.globe, size: 12, color: secondary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            title.isNotEmpty ? title : 'Preencha o título para ver como fica',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: title.isNotEmpty ? FontWeight.w600 : FontWeight.w500,
              height: 1.3,
              color: title.isNotEmpty ? siteInk(context, link) : secondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description.isNotEmpty
                ? description
                : 'A descrição aparece aqui, logo abaixo do título.',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  // ── Domínio ──

  Widget _buildDomainPanel(BuildContext context) {
    final cfg = _config!;
    final tone = _tone(context, _SiteTab.domain);
    final dns = _dns ?? PublicSiteDnsInstructions.fromJson(null);
    final savedDomain = (cfg.customDomain ?? '').trim();
    final hasDomain = savedDomain.isNotEmpty;
    final status = cfg.domainStatus;
    final isActive = status == PublicSiteDomainStatus.active;
    // DNS encontrado: o registro já aponta para cá (o que falta, se falta, é
    // do nosso lado — HTTPS ou revisão).
    final dnsFound =
        hasDomain &&
        (isActive ||
            status == PublicSiteDomainStatus.pendingSsl ||
            status == PublicSiteDomainStatus.pendingReview ||
            status == PublicSiteDomainStatus.failed);
    final editing = _domainController.text.trim() != savedDomain;
    // 29/09/2026 (integ-02): tipo, host e valor vêm do payload do back
    // (`recordType/recordHost/recordValue`). Hoje é registro A para o IP,
    // em `www` E em `@` (raiz), criados juntos — o card antigo mostrava
    // "CNAME → sites.intellisysbr.com" fixo e o domínio nunca ativava.
    final twoARecords = dns.needsRootRecord;

    final step1 = hasDomain && !editing
        ? SiteStepState.done
        : SiteStepState.now;
    final step2 = !hasDomain
        ? SiteStepState.todo
        : (dnsFound ? SiteStepState.done : SiteStepState.now);
    final SiteStepState step3;
    if (!hasDomain) {
      step3 = SiteStepState.todo;
    } else if (isActive) {
      step3 = SiteStepState.done;
    } else if (status == PublicSiteDomainStatus.failed ||
        status == PublicSiteDomainStatus.disabled) {
      step3 = SiteStepState.problem;
    } else {
      step3 = dnsFound ? SiteStepState.now : SiteStepState.todo;
    }

    return _panelShell(context, _SiteTab.domain, [
      if (!_canManage) ...[
        const SiteReadOnlyNotice(text: _readOnlyText),
        const SizedBox(height: 16),
      ],
      SiteStep(
        number: 1,
        title: 'Informe o domínio',
        subtitle: !hasDomain
            ? 'O endereço que você já tem, de preferência com www.'
            : (editing
                  ? 'Salvo: $savedDomain — toque em "Salvar domínio" para '
                        'trocar.'
                  : 'Salvo: $savedDomain'),
        state: step1,
        tone: tone,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SiteFilledField(
              controller: _domainController,
              label: 'Domínio do site',
              hint: 'www.suaimobiliaria.com.br',
              icon: LucideIcons.globe,
              keyboardType: TextInputType.url,
              enabled: _canManage,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            _buildSaveDomainButton(context),
          ],
        ),
      ),
      SiteStep(
        number: 2,
        title: 'Crie ${dns.recordsToCreateLabel} no provedor',
        subtitle:
            'No painel de DNS do domínio (Registro.br, GoDaddy, Hostinger, '
            'Cloudflare…) — nem sempre é onde o domínio foi comprado.',
        state: step2,
        tone: tone,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildDnsRecordCard(
              context,
              dns: dns,
              host: dns.recordHost,
              tone: tone,
              caption: twoARecords ? 'Registro 1 · subdomínio' : null,
            ),
            if (twoARecords) ...[
              const SizedBox(height: 12),
              _buildDnsRecordCard(
                context,
                dns: dns,
                host: '@',
                tone: tone,
                caption: 'Registro 2 · domínio raiz (crie junto)',
              ),
            ],
            const SizedBox(height: 10),
            _noteLine(
              context,
              LucideIcons.timer,
              'TTL (tempo de cache): ${dns.ttlRecommendation}',
            ),
            const SizedBox(height: 6),
            _noteLine(context, LucideIcons.info, dns.propagationNote),
            const SizedBox(height: 8),
            _buildDnsGuide(
              context,
              dns,
              tone,
              open: _dnsGuideOpen ?? !dnsFound,
            ),
          ],
        ),
      ),
      SiteStep(
        number: 3,
        title: 'Verifique o DNS',
        subtitle: 'Quando o DNS propagar, o domínio é ativado sozinho.',
        state: step3,
        tone: tone,
        last: true,
        child: _buildVerifyBlock(
          context,
          dns: dns,
          hasDomain: hasDomain,
          isActive: isActive,
        ),
      ),
    ]);
  }

  Widget _buildSaveDomainButton(BuildContext context) {
    if (!_canManage) {
      return OutlinedButton.icon(
        onPressed: null,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: ThemeHelpers.borderColor(context)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        ),
        icon: const Icon(LucideIcons.lock, size: 16),
        label: const SiteButtonLabel('Salvar domínio'),
      );
    }
    // Salvar = confirmar → verde (era o vermelho da marca).
    final solid = siteSolid(_green(context));
    return FilledButton.icon(
      onPressed: _domainSaving ? null : _saveDomain,
      style: FilledButton.styleFrom(
        backgroundColor: solid,
        foregroundColor: Colors.white,
        disabledBackgroundColor: solid.withValues(alpha: 0.6),
        disabledForegroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      ),
      icon: _domainSaving
          ? const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(LucideIcons.save, size: 16),
      label: SiteButtonLabel(_domainSaving ? 'Salvando…' : 'Salvar domínio'),
    );
  }

  /// Cartão de um registro DNS (tipo · nome/host · valor), com copiar no
  /// nome e no valor. Usado duas vezes no registro A: `www` e `@`.
  Widget _buildDnsRecordCard(
    BuildContext context, {
    required PublicSiteDnsInstructions dns,
    required String host,
    required Color tone,
    String? caption,
  }) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final line = Divider(
      height: 1,
      color: ThemeHelpers.borderLightColor(context),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (caption != null) ...[
          Text(
            caption,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: secondary,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 6),
        ],
        SiteCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          child: Column(
            children: [
              SiteInfoRow(
                icon: LucideIcons.tag,
                label: 'Tipo',
                value: dns.recordType,
                mono: true,
              ),
              line,
              SiteInfoRow(
                icon: LucideIcons.atSign,
                label: 'Nome / host',
                value: host,
                mono: true,
                actions: [
                  SiteRowAction(
                    icon: LucideIcons.copy,
                    tooltip: 'Copiar o nome (host)',
                    tone: tone,
                    onTap: () =>
                        _copyText(host, feedback: 'Nome (host) copiado'),
                  ),
                ],
              ),
              line,
              SiteInfoRow(
                icon: LucideIcons.arrowRight,
                label: dns.isARecord ? 'Aponta para (IP)' : 'Aponta para',
                value: dns.recordValue,
                mono: true,
                actions: [
                  SiteRowAction(
                    icon: LucideIcons.copy,
                    tooltip: 'Copiar o valor',
                    tone: tone,
                    onTap: () =>
                        _copyText(dns.recordValue, feedback: 'Valor copiado'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Passo a passo do back + onde criar por provedor, recolhível: aberto
  /// enquanto o DNS não foi encontrado, fechado depois (continua à mão).
  Widget _buildDnsGuide(
    BuildContext context,
    PublicSiteDnsInstructions dns,
    Color tone, {
    required bool open,
  }) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: open,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _dnsGuideOpen = !open),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Icon(LucideIcons.listOrdered, size: 15, color: secondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        open
                            ? 'Passo a passo no provedor'
                            : 'Ver o passo a passo no provedor',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      open ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                      size: 17,
                      color: secondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (open) ...[
          const SizedBox(height: 6),
          for (final step in dns.steps) _buildDnsStepLine(context, step),
          if (dns.providerHints.isNotEmpty) ...[
            const SizedBox(height: 4),
            const SiteSubsectionHeader(
              label: 'Onde criar, por provedor',
              icon: LucideIcons.server,
            ),
            const SizedBox(height: 12),
            for (final hint in dns.providerHints)
              _buildProviderHint(context, hint, tone),
          ],
        ],
      ],
    );
  }

  Widget _buildDnsStepLine(BuildContext context, PublicSiteDnsStep step) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: siteFieldFill(context),
              border: Border.all(color: siteHairline(context)),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${step.order}',
                style: TextStyle(
                  color: secondary,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
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

  Widget _buildProviderHint(
    BuildContext context,
    PublicSiteDnsProviderHint hint,
    Color tone,
  ) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final url = hint.url?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              LucideIcons.server,
              size: 14,
              color: siteInk(context, tone),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hint.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint.hint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (url.isNotEmpty)
            SiteRowAction(
              icon: LucideIcons.externalLink,
              tooltip: 'Abrir ${hint.name}',
              tone: tone,
              onTap: () => _openExternal(
                url,
                failure: 'Não foi possível abrir ${hint.name}',
              ),
            ),
        ],
      ),
    );
  }

  /// Passo 3: a situação da verificação em palavras e o "Verificar DNS"
  /// (mesma regra de sempre: só com domínio salvo e ainda não ativo).
  Widget _buildVerifyBlock(
    BuildContext context, {
    required PublicSiteDnsInstructions dns,
    required bool hasDomain,
    required bool isActive,
  }) {
    final theme = Theme.of(context);
    final isDark = _isDark(context);
    final cfg = _config!;
    final secondary = ThemeHelpers.textSecondaryColor(context);

    if (!hasDomain) {
      return Text(
        'Depois de salvar o domínio e criar os registros, é aqui que você '
        'confere se deu certo.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: secondary,
          height: 1.4,
        ),
      );
    }

    final statusTone = _domainStatusColor(context, cfg.domainStatus);
    final box = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: statusTone.withValues(alpha: isDark ? 0.12 : 0.07),
        border: Border.all(color: statusTone.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              _domainStateIcon(cfg.domainStatus),
              size: 17,
              color: siteInk(context, statusTone),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _domainStateTitle(cfg.domainStatus),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _domainExplanation(cfg, dns),
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

    if (isActive) return box;

    final Widget button;
    if (!_canManage) {
      button = OutlinedButton.icon(
        onPressed: null,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: ThemeHelpers.borderColor(context)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        ),
        icon: const Icon(LucideIcons.lock, size: 16),
        label: const SiteButtonLabel('Verificar DNS'),
      );
    } else {
      // Verificar = conferir (azul de informação), distinto do Salvar verde.
      final solid = siteSolid(_blue(context));
      button = FilledButton.icon(
        onPressed: _dnsVerifying ? null : _verifyDns,
        style: FilledButton.styleFrom(
          backgroundColor: solid,
          foregroundColor: Colors.white,
          disabledBackgroundColor: solid.withValues(alpha: 0.6),
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        ),
        icon: _dnsVerifying
            ? const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(LucideIcons.radar, size: 16),
        label: SiteButtonLabel(
          _dnsVerifying ? 'Verificando…' : 'Verificar DNS',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [box, const SizedBox(height: 10), button],
    );
  }

  // ─── Auxiliares de desenho ────────────────────────────────────────────────

  /// Linha de nota (ícone + frase) em cinza secundário.
  Widget _noteLine(BuildContext context, IconData icon, String text) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 14, color: secondary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: secondary,
              height: 1.4,
              fontSize: 11.5,
            ),
          ),
        ),
      ],
    );
  }

  // ─── Esqueleto (fiel ao layout: moldura, situação, próximo passo, abas,
  // cabeçalho do painel, publicação e "o que falta") ────────────────────────

  Widget _buildPageSkeleton(BuildContext context, double sidePad) {
    final hairline = siteHairline(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        sidePad,
        _kPagePadTop,
        sidePad,
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
              border: Border.all(color: hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    children: [
                      SkeletonBox(width: 8, height: 8, borderRadius: 999),
                      SizedBox(width: 5),
                      SkeletonBox(width: 8, height: 8, borderRadius: 999),
                      SizedBox(width: 5),
                      SkeletonBox(width: 8, height: 8, borderRadius: 999),
                      SizedBox(width: 10),
                      Expanded(
                        child: SkeletonBox(height: 26, borderRadius: 999),
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: ThemeHelpers.borderLightColor(context),
                ),
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          SkeletonBox(width: 40, height: 40, borderRadius: 12),
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
                      SizedBox(height: 12),
                      SkeletonBox(height: 54, borderRadius: 12),
                      SizedBox(height: 10),
                      Row(
                        children: [
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
          // Selos + abrir/copiar
          const Row(
            children: [
              SkeletonBox(width: 74, height: 24, borderRadius: 999),
              SizedBox(width: 6),
              Flexible(
                child: SkeletonBox(width: 118, height: 24, borderRadius: 999),
              ),
              Spacer(),
              SkeletonBox(width: 36, height: 36, borderRadius: 11),
              SizedBox(width: 6),
              SkeletonBox(width: 36, height: 36, borderRadius: 11),
            ],
          ),
          const SizedBox(height: 10),
          // Próximo passo
          const SkeletonBox(height: 84, borderRadius: 14),
          const SizedBox(height: 18),
          // Abas
          const Row(
            children: [
              Expanded(
                child: Center(child: SkeletonText(width: 52, height: 12)),
              ),
              Expanded(
                child: Center(child: SkeletonText(width: 52, height: 12)),
              ),
              Expanded(
                child: Center(child: SkeletonText(width: 52, height: 12)),
              ),
              Expanded(
                child: Center(child: SkeletonText(width: 52, height: 12)),
              ),
            ],
          ),
          const SizedBox(height: 26),
          // Cabeçalho do painel
          const Row(
            children: [
              SkeletonBox(width: 4, height: 34, borderRadius: 999),
              SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonText(width: 150, height: 14),
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
          // Publicação
          const SkeletonBox(height: 148, borderRadius: 16),
          const SizedBox(height: 22),
          // O que falta
          const SkeletonText(width: 180, height: 11),
          const SizedBox(height: 10),
          const SkeletonBox(height: 280, borderRadius: 16),
        ],
      ),
    );
  }
}
