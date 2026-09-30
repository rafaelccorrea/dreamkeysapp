import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/property_service.dart';

/// Visual unificado do status do imóvel — usado em paridade entre a
/// lista (`PropertiesPage`), a tela de detalhes (`PropertyDetailsPage`), o
/// drawer de filtros e o cadastro.
///
/// COR É SIGNIFICADO, NÃO ETIQUETA: os 17 status do back caem em poucas
/// famílias, todas por token (`AppColors`), para a pessoa ler o estado do
/// imóvel sem decorar um arco-íris. Dentro da família, quem diferencia é o
/// ícone e o rótulo.
///
/// - Rascunho → neutro (ainda não é nada; falta terminar).
/// - Aguardando autorização / aprovação / publicação → âmbar (espera alguém).
/// - Disponível → verde (pode oferecer).
/// - 9 etapas do funil de locação → azul (em andamento).
/// - Vendido → roxo; Alugado → ciano (fechados, e distintos entre si).
/// - Manutenção → vermelho (parado).
///
/// No claro o tom usa os tokens de TEXTO sobre tinta (`AppColors.message.*`),
/// que têm contraste no branco; no escuro, os `*DarkMode` de `AppColors.status`.
class PropertyStatusVisual {
  const PropertyStatusVisual({
    required this.label,
    required this.shortLabel,
    required this.color,
    required this.icon,
  });

  final String label;
  final String shortLabel;
  final Color color;
  final IconData icon;

  /// Resolve a partir do enum `PropertyStatus`. [dark] escolhe a variante do
  /// tema escuro do mesmo token.
  factory PropertyStatusVisual.of(PropertyStatus status, {bool dark = false}) {
    switch (status) {
      case PropertyStatus.draft:
        return _v(status, _neutral(dark), LucideIcons.fileEdit);
      case PropertyStatus.pendingOwnerAuthorization:
        return _v(status, _waiting(dark), LucideIcons.userCheck);
      case PropertyStatus.pendingApproval:
        return _v(status, _waiting(dark), LucideIcons.clock);
      case PropertyStatus.pendingPublication:
        return _v(status, _waiting(dark), LucideIcons.globe);
      case PropertyStatus.available:
        return _v(status, _available(dark), LucideIcons.checkCircle2);
      case PropertyStatus.inService:
        return _v(status, _funnel(dark), LucideIcons.headphones);
      case PropertyStatus.visitScheduled:
        return _v(status, _funnel(dark), LucideIcons.calendarCheck);
      case PropertyStatus.inVisit:
        return _v(status, _funnel(dark), LucideIcons.doorOpen);
      case PropertyStatus.inNegotiation:
        return _v(status, _funnel(dark), LucideIcons.handshake);
      case PropertyStatus.proposalReceived:
        return _v(status, _funnel(dark), LucideIcons.inbox);
      case PropertyStatus.registrationAnalysis:
        return _v(status, _funnel(dark), LucideIcons.clipboardCheck);
      case PropertyStatus.documentation:
        return _v(status, _funnel(dark), LucideIcons.fileText);
      case PropertyStatus.contractDrafting:
        return _v(status, _funnel(dark), LucideIcons.clipboardList);
      case PropertyStatus.signature:
        return _v(status, _funnel(dark), LucideIcons.penLine);
      case PropertyStatus.rented:
        return _v(status, _rented(dark), LucideIcons.key);
      case PropertyStatus.sold:
        return _v(
          status,
          dark ? AppColors.status.purpleDarkMode : AppColors.status.purple,
          LucideIcons.tag,
        );
      case PropertyStatus.maintenance:
        return _v(
          status,
          dark ? AppColors.status.errorDarkMode : AppColors.status.error,
          LucideIcons.wrench,
        );
    }
  }

  /// Resolve a partir do valor cru da API. Status que o app não conhece sai
  /// neutro, com o próprio valor como rótulo (regra do
  /// `translatePropertyStatus` do web) — nunca disfarçado de "Rascunho". O
  /// valor é só legibilizado ("em_reforma" → "Em reforma"), sem inventar nome.
  factory PropertyStatusVisual.ofRaw(
    PropertyStatus status,
    String? raw, {
    bool dark = false,
  }) {
    final r = raw?.trim() ?? '';
    if (r.isEmpty || PropertyStatus.fromString(r) != null) {
      return PropertyStatusVisual.of(
        PropertyStatus.fromString(r) ?? status,
        dark: dark,
      );
    }
    final legivel = _legivel(r);
    return PropertyStatusVisual(
      label: legivel,
      shortLabel: legivel,
      color: _neutral(dark),
      icon: LucideIcons.helpCircle,
    );
  }

  /// Fase do status — agrupa os 17 para leitura (filtros e trilhas).
  static PropertyStatusPhase phaseOf(PropertyStatus status) {
    switch (status) {
      case PropertyStatus.draft:
      case PropertyStatus.pendingOwnerAuthorization:
      case PropertyStatus.pendingApproval:
      case PropertyStatus.pendingPublication:
        return PropertyStatusPhase.cadastro;
      case PropertyStatus.available:
      case PropertyStatus.maintenance:
        return PropertyStatusPhase.carteira;
      case PropertyStatus.inService:
      case PropertyStatus.visitScheduled:
      case PropertyStatus.inVisit:
      case PropertyStatus.inNegotiation:
      case PropertyStatus.proposalReceived:
      case PropertyStatus.registrationAnalysis:
      case PropertyStatus.documentation:
      case PropertyStatus.contractDrafting:
      case PropertyStatus.signature:
        return PropertyStatusPhase.funil;
      case PropertyStatus.rented:
      case PropertyStatus.sold:
        return PropertyStatusPhase.encerrado;
    }
  }

  /// Os status agrupados por fase, cada grupo na ordem do enum (a mesma de
  /// `PropertyStatusOptions` do web).
  static List<(PropertyStatusPhase, List<PropertyStatus>)> grouped() {
    return [
      for (final f in PropertyStatusPhase.values)
        (
          f,
          [
            for (final s in PropertyStatus.values)
              if (phaseOf(s) == f) s,
          ],
        ),
    ].where((g) => g.$2.isNotEmpty).toList();
  }

  /// Etapas do funil de locação, na ordem do web.
  static List<PropertyStatus> get rentalFunnelSteps => [
        for (final s in PropertyStatus.values)
          if (s.isRentalFunnel) s,
      ];

  static Color _neutral(bool dark) =>
      dark ? AppColors.text.textLightDarkMode : AppColors.text.textLight;

  static Color _waiting(bool dark) =>
      dark ? AppColors.status.warningDarkMode : AppColors.message.warningText;

  static Color _available(bool dark) =>
      dark ? AppColors.status.successDarkMode : AppColors.message.successText;

  static Color _funnel(bool dark) =>
      dark ? AppColors.status.infoDarkMode : AppColors.message.infoText;

  /// Ciano de "Alugado" (token `AppColors.status.teal`) — o tom que o app já
  /// usava. Não colide com o âmbar dos "Aguardando" nem com o azul do funil
  /// de locação. Rosa foi recusado.
  static Color _rented(bool dark) =>
      dark ? AppColors.status.tealDarkMode : AppColors.status.teal;

  static String _legivel(String raw) {
    final s = raw.replaceAll(RegExp(r'[_\-]+'), ' ').trim().toLowerCase();
    if (s.isEmpty) return raw;
    return s[0].toUpperCase() + s.substring(1);
  }

  static PropertyStatusVisual _v(
    PropertyStatus status,
    Color color,
    IconData icon,
  ) {
    return PropertyStatusVisual(
      label: status.label,
      shortLabel: status.shortLabel,
      color: color,
      icon: icon,
    );
  }
}

/// Fases de leitura do status (agrupamento visual; não é regra de negócio).
enum PropertyStatusPhase {
  cadastro('Cadastro e aprovação'),
  carteira('Em carteira'),
  funil('Funil de locação'),
  encerrado('Fechados');

  const PropertyStatusPhase(this.label);

  final String label;
}

/// Trilha do funil de locação — 9 traços com a etapa atual acesa e a frase
/// "etapa N de 9". Responde de cara "onde este imóvel está no funil" sem a
/// pessoa decorar a ordem das etapas. Fora do funil, não ocupa espaço.
class PropertyRentalFunnelTrail extends StatelessWidget {
  const PropertyRentalFunnelTrail({super.key, required this.status});

  final PropertyStatus status;

  @override
  Widget build(BuildContext context) {
    if (!status.isRentalFunnel) return const SizedBox.shrink();
    final steps = PropertyStatusVisual.rentalFunnelSteps;
    final idx = steps.indexOf(status);
    if (idx < 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = PropertyStatusVisual.of(status, dark: isDark).color;
    final track = ThemeHelpers.borderColor(context);

    return Semantics(
      label: 'Funil de locação, etapa ${idx + 1} de ${steps.length}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              for (var i = 0; i < steps.length; i++)
                Expanded(
                  child: Container(
                    height: 4,
                    margin: EdgeInsets.only(
                      right: i == steps.length - 1 ? 0 : 3,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      color: i < idx
                          ? tone.withValues(alpha: isDark ? 0.45 : 0.38)
                          : i == idx
                              ? tone
                              : track.withValues(alpha: isDark ? 0.9 : 0.7),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Funil de locação · etapa ${idx + 1} de ${steps.length}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pill de status do imóvel — variante padrão (cor accent + fill leve).
///
/// Use nos cards da lista e na identidade da tela de detalhes pra dar
/// visibilidade imediata ao corretor (mais útil que descobrir o status
/// só clicando no imóvel).
class PropertyStatusPill extends StatelessWidget {
  const PropertyStatusPill({
    super.key,
    required this.status,
    this.rawStatus,
    this.short = false,
    this.solid = false,
    this.dense = false,
    this.onTap,
    this.actionSuffix,
  });

  /// Status do imóvel.
  final PropertyStatus status;

  /// Valor cru da API (`Property.statusRaw`). Quando informado e desconhecido,
  /// a pill mostra o próprio valor em tom neutro.
  final String? rawStatus;

  /// Quando `true`, usa o label curto (ex.: "Aguard. proprietário").
  /// Útil em cards estreitos.
  final bool short;

  /// Quando `true`, renderiza com fundo sólido (cor) + texto branco.
  /// Use em cima de imagens/herós onde o pill precisa contrastar.
  final bool solid;

  /// Quando `true`, reduz padding e fonte (para uso em cards pequenos).
  final bool dense;

  /// Quando informado, torna o pill interativo (ex.: desfazer venda).
  final VoidCallback? onTap;

  /// Texto extra após o label (ex.: " · Desvender").
  final String? actionSuffix;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final v = PropertyStatusVisual.ofRaw(status, rawStatus, dark: isDark);

    if (solid) {
      return _wrapInteractive(_renderSolid(v));
    }

    return _wrapInteractive(
      Container(
        padding: dense
            ? const EdgeInsets.symmetric(horizontal: 7, vertical: 3)
            : const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: v.color.withValues(alpha: isDark ? 0.18 : 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: v.color.withValues(alpha: isDark ? 0.50 : 0.42),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(v.icon, size: dense ? 11 : 12, color: v.color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                _labelText(v),
                style: TextStyle(
                  color: v.color,
                  fontWeight: FontWeight.w900,
                  fontSize: dense ? 9.5 : 10.5,
                  letterSpacing: 0.2,
                  height: 1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _labelText(PropertyStatusVisual v) {
    final base = short ? v.shortLabel : v.label;
    if (actionSuffix == null || actionSuffix!.isEmpty) return base;
    return '$base$actionSuffix';
  }

  Widget _wrapInteractive(Widget child) {
    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: child,
      ),
    );
  }

  Widget _renderSolid(PropertyStatusVisual v) {
    return Container(
      padding: dense
          ? const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5)
          : const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: v.color,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: v.color.withValues(alpha: 0.45),
            blurRadius: 8,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(v.icon, size: dense ? 11 : 12, color: Colors.white),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              _labelText(v),
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: dense ? 9.5 : 10.5,
                letterSpacing: 0.3,
                height: 1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pill de **situação** — ativo no cadastro / inativo / publicação no site.
/// Complementa o `PropertyStatusPill` (que é "estado de negócio").
class PropertySituationPill extends StatelessWidget {
  const PropertySituationPill({
    super.key,
    required this.isActive,
    required this.isAvailableForSite,
    this.dense = false,
  });

  final bool isActive;
  final bool isAvailableForSite;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color color;
    final IconData icon;
    final String label;

    // Mesmos tokens do PropertyStatusPill: neutro = parado, verde = em uso.
    final ativo = isDark
        ? AppColors.status.successDarkMode
        : AppColors.message.successText;
    if (!isActive) {
      color = isDark ? AppColors.text.textLightDarkMode : AppColors.text.textLight;
      icon = LucideIcons.minusCircle;
      label = 'Inativo';
    } else if (isAvailableForSite) {
      color = ativo;
      icon = LucideIcons.globe;
      label = 'Ativo · no site';
    } else {
      color = ativo;
      icon = LucideIcons.checkCircle2;
      label = 'Ativo';
    }

    return Container(
      padding: dense
          ? const EdgeInsets.symmetric(horizontal: 7, vertical: 3)
          : const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.50 : 0.42),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: dense ? 11 : 12, color: color),
          const SizedBox(width: 5),
          // Flexible + ellipsis: no card da lista a pill divide ~130dp com o
          // status; em 320dp com texto a 130% "Ativo · no site" estourava.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: dense ? 9.5 : 10.5,
                letterSpacing: 0.2,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
