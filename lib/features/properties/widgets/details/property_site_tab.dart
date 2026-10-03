import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/property_service.dart';
import '../../../../shared/utils/error_cause.dart';
import '../../services/property_detail_extras_service.dart';
import '../../utils/property_publish_rules.dart';
import 'property_details_kit.dart';

/// Corpo da aba "Site" da ficha — paridade com o `PropertySiteSection` do web
/// (a "Vitrine do site"): as três decisões de vitrine, salvas NA HORA do
/// toque (sem botão de confirmar), com a leitura do alcance antes.
///
/// Regras do web (W:1039-1075, 1515-1545, 2309-2322):
/// - a aba só existe com `public_site:manage` E com a esteira de aprovação da
///   empresa DESLIGADA — use [shouldShow] (falha ao ler a configuração =
///   aba escondida). Com a esteira ligada, quem decide o que vai ao ar é o
///   fluxo de aprovação.
/// - cada toque manda `PATCH /properties/:id` só com a chave que mudou
///   (`isAvailableForSite`, `isFeatured`, `isSitePremiumLine`); tirar do site
///   manda as três `false` juntas (nada de destaque que o visitante não abre);
///   destaque e linha premium ficam travados enquanto o imóvel não está no
///   site;
/// - otimista: a chave responde na hora e volta atrás se o servidor recusar
///   ("Não foi possível salvar a vitrine do site."); um toque por vez.
///
/// A página passa o [Property] do detalhe e recebe [onSaved] depois de cada
/// gravação aceita (`updated` = imóvel que o servidor devolveu; `null` =
/// recarregue a ficha). [onOpenShowcase] abre a vitrine completa (sem tela no
/// app hoje: sem ele, o atalho aparece travado com o motivo).
/// [lockedReason] trava as três chaves (ex.: imóvel excluído).
class PropertySiteTab extends StatefulWidget {
  const PropertySiteTab({
    super.key,
    required this.property,
    this.onSaved,
    this.onOpenShowcase,
    this.lockedReason,
  });

  final Property property;
  final ValueChanged<Property?>? onSaved;
  final VoidCallback? onOpenShowcase;
  final String? lockedReason;

  /// `public_site:manage` pela regra do web (master/admin passam direto; o
  /// resto precisa da permissão explícita — gestor NÃO passa por papel).
  static bool canManagePublicSite({
    required String? role,
    required List<String> explicitPermissions,
  }) =>
      PropertyDetailExtrasService.webHasPermission(
        role: role,
        explicitPermissions: explicitPermissions,
        permission: 'public_site:manage',
      );

  /// A aba "Site" aparece? `true` só com [canManagePublicSite] e a esteira de
  /// aprovação desligada (`GET /properties/approval-settings/active`); se a
  /// leitura falhar, `false` — a mesma prudência do web. Chame depois que a
  /// ficha carregar; até responder, deixe a aba escondida (o web não a mostra
  /// antes da resposta, para não "piscar").
  static Future<bool> shouldShow({required bool canManagePublicSite}) async {
    if (!canManagePublicSite) return false;
    return PropertyDetailExtrasService.instance.isApprovalWorkflowOff();
  }

  @override
  State<PropertySiteTab> createState() => _PropertySiteTabState();
}

class _PropertySiteTabState extends State<PropertySiteTab> {
  late bool _site;
  late bool _featured;
  late bool _premium;
  bool _saving = false;
  bool _savedOnce = false;
  ErrorCause? _error;

  @override
  void initState() {
    super.initState();
    _syncFromProperty();
  }

  @override
  void didUpdateWidget(covariant PropertySiteTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_saving && !identical(oldWidget.property, widget.property)) {
      _syncFromProperty();
    }
  }

  void _syncFromProperty() {
    final p = widget.property;
    _site = p.isAvailableForSite == true;
    _featured = p.isFeatured;
    _premium = p.isSitePremiumLine == true;
  }

  bool get _locked => (widget.lockedReason ?? '').trim().isNotEmpty;

  /// Por que não dá para PUBLICAR agora (ativo, Disponível e 5 fotos — regra
  /// do web com `publishableImageCount`). Tirar do site nunca trava.
  String? get _publishBlock =>
      _site ? null : sitePublishBlockReason(widget.property);

  void _toggleSite() {
    final next = !_site;
    if (next && _publishBlock != null) return;
    _save(
      site: next,
      // Saiu do site: sai também das vitrines (regra do web).
      featured: _site ? false : null,
      premium: _site ? false : null,
    );
  }

  Future<void> _save({bool? site, bool? featured, bool? premium}) async {
    if (_saving || _locked) return;
    final before = (site: _site, featured: _featured, premium: _premium);
    setState(() {
      if (site != null) _site = site;
      if (featured != null) _featured = featured;
      if (premium != null) _premium = premium;
      _saving = true;
      _error = null;
    });
    final res = await PropertyDetailExtrasService.instance.updateSiteShowcase(
      widget.property.id,
      isAvailableForSite: site,
      isFeatured: featured,
      isSitePremiumLine: premium,
    );
    if (!mounted) return;
    if (pdkApplied(res)) {
      setState(() {
        _saving = false;
        _savedOnce = true;
      });
      widget.onSaved?.call(res.data);
      return;
    }
    final cause = pdkFailureCause(res);
    setState(() {
      _site = before.site;
      _featured = before.featured;
      _premium = before.premium;
      _saving = false;
      _error = cause;
    });
    pdkShowSnack(
      context,
      'Não foi possível salvar a vitrine do site.',
      tone: PdkSnackTone.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final listing = PdkTone.green(context);
    final featured = PdkTone.amber(context);
    final premium = _gold(context);
    final showcase = _site;
    final onFeatured = _featured && showcase;
    final onPremium = _premium && showcase;
    final lockReason = widget.lockedReason?.trim() ?? '';
    final error = _error;
    const requiresPublication =
        'Publique no site primeiro — só imóveis no ar entram na vitrine.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Reach(
          listingOn: _site,
          featuredOn: onFeatured,
          premiumOn: onPremium,
          listingTone: listing,
          featuredTone: featured,
          premiumTone: premium,
        ),
        const SizedBox(height: 14),
        _SaveStatus(saving: _saving, saved: _savedOnce),
        if (lockReason.isNotEmpty) ...[
          const SizedBox(height: 12),
          PdkLockNote(title: 'A vitrine está travada', reason: lockReason),
        ],
        if (error != null) ...[
          const SizedBox(height: 12),
          PdkErrorNote(
            title: 'Não foi possível salvar a vitrine do site.',
            cause: error,
          ),
        ],
        const SizedBox(height: 6),
        _Decision(
          tone: listing,
          on: _site,
          icon: _site ? LucideIcons.globe : LucideIcons.eyeOff,
          name: 'Publicar no site',
          description: _site
              ? 'O imóvel aparece na listagem do site público e pode ser '
                  'encontrado na busca.'
              : (_publishBlock != null
                  ? 'Ainda não dá para publicar: $_publishBlock.'
                  : 'O imóvel fica só no CRM — ninguém o encontra pelo site.'),
          tag: _site ? 'no ar' : 'fora do site',
          tagLocked: !_site && _publishBlock != null,
          enabled: !_saving && lockReason.isEmpty && _publishBlock == null,
          onToggle: _toggleSite,
        ),
        Container(height: 1, color: ThemeHelpers.borderLightColor(context)),
        _Decision(
          tone: featured,
          on: onFeatured,
          icon: showcase ? LucideIcons.star : LucideIcons.lock,
          name: 'Imóvel em destaque',
          description: showcase
              ? 'Entra no carrossel e nos cards de destaque da página inicial.'
              : requiresPublication,
          tag: !showcase
              ? 'requer publicação'
              : (onFeatured ? 'na vitrine de destaques' : 'fora dos destaques'),
          tagLocked: !showcase,
          enabled: showcase && !_saving && lockReason.isEmpty,
          onToggle: () => _save(featured: !_featured),
        ),
        Container(height: 1, color: ThemeHelpers.borderLightColor(context)),
        _Decision(
          tone: premium,
          on: onPremium,
          icon: showcase ? LucideIcons.crown : LucideIcons.lock,
          name: 'Linha premium',
          description: showcase
              ? 'Entra na seção “Linha premium” — a fileira curada do template '
                  'Premium.'
              : requiresPublication,
          tag: !showcase
              ? 'requer publicação'
              : (onPremium ? 'na linha premium' : 'fora da linha premium'),
          tagLocked: !showcase,
          enabled: showcase && !_saving && lockReason.isEmpty,
          onToggle: () => _save(premium: !_premium),
        ),
        const SizedBox(height: 6),
        _ShowcaseFooter(onOpen: widget.onOpenShowcase),
      ],
    );
  }
}

/// Ouro da linha premium (token amarelo; texto passa por `pdkInk`).
Color _gold(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? AppColors.status.yellowDarkMode
        : AppColors.status.yellow;

/// "Alcance no site": medidor 0N/03 na cor da camada mais alta, a frase do
/// estado e a escada das três prateleiras (listagem → destaque → premium).
class _Reach extends StatelessWidget {
  const _Reach({
    required this.listingOn,
    required this.featuredOn,
    required this.premiumOn,
    required this.listingTone,
    required this.featuredTone,
    required this.premiumTone,
  });

  final bool listingOn;
  final bool featuredOn;
  final bool premiumOn;
  final Color listingTone;
  final Color featuredTone;
  final Color premiumTone;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final active = [listingOn, featuredOn, premiumOn].where((b) => b).length;
    final Color? topTone = premiumOn
        ? premiumTone
        : (featuredOn ? featuredTone : (listingOn ? listingTone : null));
    final meterColor =
        topTone == null ? secondary : pdkInk(context, topTone);
    final String title;
    if (active == 0) {
      title = 'Este imóvel não aparece em lugar nenhum';
    } else if (active == 3) {
      title = 'Presente em todas as vitrines';
    } else {
      title = 'Presente em $active de 3 vitrines';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.only(right: 14),
              margin: const EdgeInsets.only(right: 14),
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: ThemeHelpers.borderColor(context)),
                ),
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: active.toString().padLeft(2, '0'),
                      style: TextStyle(
                        color: meterColor,
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        height: 0.95,
                        letterSpacing: -1.6,
                      ),
                    ),
                    TextSpan(
                      text: '/03',
                      style: TextStyle(
                        color: secondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ALCANCE NO SITE',
                    style: TextStyle(
                      color: meterColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    style: TextStyle(
                      color: ThemeHelpers.textColor(context),
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Cada camada acima soma à anterior — a listagem é a base, o destaque '
          'puxa a home e a linha premium é a fileira mais curada do template '
          'Premium.',
          style: TextStyle(color: secondary, fontSize: 12.5, height: 1.45),
        ),
        const SizedBox(height: 16),
        ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: ThemeHelpers.borderColor(context)),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: _Rung(
                    name: 'Listagem do site',
                    state: listingOn ? 'aparece na busca' : 'não aparece',
                    tone: listingTone,
                    on: listingOn,
                    slots: 6,
                    mine: 2,
                    height: 34,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Rung(
                    name: 'Destaques da home',
                    state: featuredOn ? 'no carrossel' : 'fora da vitrine',
                    tone: featuredTone,
                    on: featuredOn,
                    slots: 4,
                    mine: 1,
                    height: 48,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Rung(
                    name: 'Linha premium',
                    state: premiumOn ? 'fileira curada' : 'fora da seleção',
                    tone: premiumTone,
                    on: premiumOn,
                    slots: 3,
                    mine: 1,
                    height: 64,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Uma prateleira da escada: nome, estado e os "cards do site vistos de
/// longe" — o do imóvel aceso quando a camada está ligada.
class _Rung extends StatelessWidget {
  const _Rung({
    required this.name,
    required this.state,
    required this.tone,
    required this.on,
    required this.slots,
    required this.mine,
    required this.height,
  });

  final String name;
  final String state;
  final Color tone;
  final bool on;
  final int slots;
  final int mine;
  final double height;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final border = ThemeHelpers.borderColor(context);
    final soft = isDark
        ? AppColors.background.backgroundSecondaryDarkMode
        : AppColors.background.backgroundSecondary;
    return Opacity(
      opacity: on ? 1 : 0.55,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name.toUpperCase(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: on ? pdkInk(context, tone) : secondary,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: on ? tone : border,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  state,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: secondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < slots; i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: i == mine
                            ? (on ? pdkSolid(tone) : border)
                            : (on ? tone.withValues(alpha: 0.22) : soft),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                          bottom: Radius.circular(2),
                        ),
                        border: i == mine
                            ? null
                            : Border.all(
                                color: on
                                    ? tone.withValues(alpha: 0.3)
                                    : border,
                              ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Salvando…" / "Tudo salvo" / como funciona — a aba não tem botão salvar.
class _SaveStatus extends StatelessWidget {
  const _SaveStatus({required this.saving, required this.saved});

  final bool saving;
  final bool saved;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final green = PdkTone.green(context);
    final Widget icon;
    final String text;
    if (saving) {
      icon = SizedBox(
        width: 13,
        height: 13,
        child: CircularProgressIndicator(strokeWidth: 2, color: secondary),
      );
      text = 'Salvando…';
    } else if (saved) {
      icon = Icon(
        LucideIcons.circleCheck,
        size: 14,
        color: pdkInk(context, green),
      );
      text = 'Tudo salvo';
    } else {
      icon = Icon(LucideIcons.info, size: 14, color: secondary);
      text = 'Cada chave salva na hora do toque.';
    }
    return Semantics(
      liveRegion: true,
      child: Row(
        children: [
          icon,
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: saved && !saving ? pdkInk(context, green) : secondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Faixa de decisão: selo no tom (aceso quando ligada), nome, efeito real,
/// etiqueta de estado e a chave. A faixa inteira responde ao toque.
class _Decision extends StatelessWidget {
  const _Decision({
    required this.tone,
    required this.on,
    required this.icon,
    required this.name,
    required this.description,
    required this.tag,
    required this.enabled,
    required this.onToggle,
    this.tagLocked = false,
  });

  final Color tone;
  final bool on;
  final IconData icon;
  final String name;
  final String description;
  final String tag;
  final bool tagLocked;
  final bool enabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final ink = pdkInk(context, tone);
    final lit = on && !tagLocked;
    return Semantics(
      toggled: on,
      enabled: enabled,
      label: name,
      child: InkWell(
        onTap: enabled ? onToggle : null,
        child: Opacity(
          opacity: tagLocked ? 0.7 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: lit
                        ? tone.withValues(alpha: isDark ? 0.2 : 0.12)
                        : ThemeHelpers.borderLightColor(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: lit
                          ? tone.withValues(alpha: 0.4)
                          : ThemeHelpers.borderColor(context),
                    ),
                  ),
                  child: Icon(icon, size: 18, color: lit ? ink : secondary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          color: ThemeHelpers.textColor(context),
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        description,
                        style: TextStyle(
                          color: secondary,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: lit
                              ? tone.withValues(alpha: isDark ? 0.18 : 0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: lit
                                ? tone.withValues(alpha: 0.34)
                                : ThemeHelpers.borderColor(context),
                          ),
                        ),
                        child: Text(
                          tag.toUpperCase(),
                          style: TextStyle(
                            color: lit ? ink : secondary,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Switch.adaptive(
                  value: on,
                  onChanged: enabled ? (_) => onToggle() : null,
                  activeTrackColor: pdkSolid(tone),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Atalho para a vitrine completa ("Montar as vitrines de uma vez"). Sem
/// tela no app: travado com o motivo.
class _ShowcaseFooter extends StatelessWidget {
  const _ShowcaseFooter({this.onOpen});

  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final brand = isDark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Montar as vitrines de uma vez',
          style: TextStyle(
            color: ThemeHelpers.textColor(context),
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Escolha vários imóveis para destaque e linha premium na mesma '
          'tela, com busca e prévia.',
          style: TextStyle(color: secondary, fontSize: 12, height: 1.4),
        ),
        if (onOpen == null) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  LucideIcons.lock,
                  size: 13,
                  color: pdkInk(context, PdkTone.violet(context)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Disponível na versão web, em Configurações › Vitrine do '
                  'site.',
                  style: TextStyle(color: secondary, fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ),
        ],
      ],
    );
    return Container(
      padding: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: brand.withValues(alpha: isDark ? 0.18 : 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: brand.withValues(alpha: 0.3)),
            ),
            child: Icon(
              LucideIcons.slidersHorizontal,
              size: 16,
              color: pdkInk(context, brand),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: onOpen == null
                ? text
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      text,
                      const SizedBox(height: 10),
                      PdkNeutralButton(
                        label: 'Abrir vitrine',
                        trailingIcon: LucideIcons.arrowRight,
                        onPressed: onOpen,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
