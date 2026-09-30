import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/visit_report_model.dart';

/// Cor semântica do status da assinatura (âmbar = aguardando, verde =
/// assinado, neutro = expirado) — clara/escura conforme o tema.
Color visitStatusColor(BuildContext context, VisitSignatureStatus status) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  switch (status) {
    case VisitSignatureStatus.pending:
      return isDark
          ? AppColors.status.warningDarkMode
          : AppColors.status.warning;
    case VisitSignatureStatus.signed:
      return isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    case VisitSignatureStatus.expired:
    case VisitSignatureStatus.unknown:
      return ThemeHelpers.textSecondaryColor(context);
  }
}

IconData visitStatusIcon(VisitSignatureStatus status) {
  switch (status) {
    case VisitSignatureStatus.pending:
      return LucideIcons.clock3;
    case VisitSignatureStatus.signed:
      return LucideIcons.circleCheck;
    case VisitSignatureStatus.expired:
      return LucideIcons.circleAlert;
    case VisitSignatureStatus.unknown:
      return LucideIcons.clipboardList;
  }
}

/// Folhinha de calendário — assinatura visual da feature Visitas (agenda).
/// Faixa superior sólida com o mês, dia grande no corpo e dia da semana
/// abaixo. Sem data → ícone de calendário no mesmo invólucro tonal.
class VisitDateLeaf extends StatelessWidget {
  final DateTime? date;
  final Color tone;
  final double width;

  const VisitDateLeaf({
    super.key,
    required this.date,
    required this.tone,
    this.width = 56,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final d = date;

    return Container(
      width: width,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: tone.withValues(alpha: isDark ? 0.12 : 0.06),
        border: Border.all(color: tone.withValues(alpha: isDark ? 0.4 : 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: d == null
          ? SizedBox(
              height: width * 1.12,
              child: Center(
                child: Icon(LucideIcons.calendarDays, color: tone, size: 20),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Faixa do mês — sólida na cor de acento (folhinha clássica).
                Container(
                  width: double.infinity,
                  color: tone,
                  padding: const EdgeInsets.symmetric(vertical: 3.5),
                  child: Text(
                    DateFormat('MMM', 'pt_BR')
                        .format(d)
                        .replaceAll('.', '')
                        .toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.6,
                      height: 1.0,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 7, 4, 7),
                  child: Column(
                    children: [
                      Text(
                        '${d.day}',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          height: 1.0,
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        DateFormat('E', 'pt_BR')
                            .format(d)
                            .replaceAll('.', '')
                            .toLowerCase(),
                        style: TextStyle(
                          color: secondary,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          height: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// Contraste mínimo de TEXTO (WCAG AA, texto normal).
const double _kContrasteMinimo = 4.5;

final Map<(int, bool), Color> _inkCache = <(int, bool), Color>{};

/// Tinta de TEXTO (e ícone pequeno) legível a partir de um tom de status
/// (30/09/2026). No modo claro o âmbar (#E6B84C) dá 1,9:1 no branco, o verde
/// 3:1 e o violeta 4,2:1 — o selo "Aguardando" em âmbar sobre âmbar claro
/// quase sumia. O tom é misturado com a cor de texto do tema só o bastante
/// para passar de 4,5:1 contra o cinza de campo (#EEF0F3) — logo também no
/// branco. Mesmo matiz, sem hex novo; no escuro os tons já passam e voltam
/// como vieram. É a mesma conta do `sdrTintaLegivel` (candidata a subir para
/// `core/theme` quando o coordenador liberar).
Color visitInk(BuildContext context, Color tone) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return _inkCache.putIfAbsent((tone.toARGB32(), isDark), () {
    final fundo = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    final texto = ThemeHelpers.textColor(context);
    for (var passo = 0; passo <= 50; passo++) {
      final c = Color.lerp(tone, texto, passo / 50)!;
      if (_contraste(c, fundo) >= _kContrasteMinimo) return c;
    }
    return texto;
  });
}

double _contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final claro = la > lb ? la : lb;
  final escuro = la > lb ? lb : la;
  return (claro + 0.05) / (escuro + 0.05);
}

/// Prazo do link em palavras ("vence hoje", "vence em 3 dias").
String _linkDeadline(DateTime expiresAt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final l = expiresAt.toLocal();
  final diff = DateTime(l.year, l.month, l.day).difference(today).inDays;
  if (diff <= 0) return 'link vence hoje';
  if (diff == 1) return 'link vence amanhã';
  return 'link vence em $diff dias';
}

/// Item da lista de visitas — **linha de agenda** (30/09/2026): nó do status
/// sobre um trilho vertical, o estado em palavra com o que ele significa
/// ("link vence em 2 dias", "assinado em 12/09 por Ana", "link ainda não
/// gerado"), quem, onde, a negociação e a AÇÃO PRINCIPAL no próprio item:
/// "Enviar no WhatsApp" quando há link ativo, "Gerar link de assinatura"
/// quando não há — travado com cadeado e motivo para quem não pode editar
/// (antes sumia). Editar e Excluir ficam como ações secundárias.
/// A data fica no cabeçalho do dia — a lista é agrupada por dia.
class VisitReportCard extends StatelessWidget {
  final VisitReport report;

  /// Mostra o corretor (visão gestão / `scope=all`).
  final bool showBroker;
  final bool canEdit;
  final bool canDelete;

  /// Pode gerar link de assinatura (`visit:update`). Sem ela o botão aparece
  /// travado, com o motivo, em vez de sumir.
  final bool canGenerateLink;
  final VoidCallback? onTap;
  final VoidCallback? onShareWhatsApp;
  final VoidCallback? onCopyLink;
  final VoidCallback? onGenerateLink;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// Uma ação de link está em andamento (mostra progresso no item).
  final bool linkBusy;

  const VisitReportCard({
    super.key,
    required this.report,
    this.showBroker = false,
    this.canEdit = false,
    this.canDelete = false,
    this.canGenerateLink = true,
    this.onTap,
    this.onShareWhatsApp,
    this.onCopyLink,
    this.onGenerateLink,
    this.onEdit,
    this.onDelete,
    this.linkBusy = false,
  });

  /// Linha que diz o que o estado significa para quem está olhando.
  (String, bool)? _stateDetail() {
    final dateFmt = DateFormat('dd/MM', 'pt_BR');
    switch (report.signatureStatus) {
      case VisitSignatureStatus.pending:
        final exp = report.signatureExpiresAt;
        if (report.hasActiveLink && exp != null) {
          final now = DateTime.now();
          final soon = exp.toLocal().difference(now).inDays <= 2;
          return (_linkDeadline(exp), soon);
        }
        if (exp != null) {
          return ('link venceu em ${dateFmt.format(exp.toLocal())}', true);
        }
        return ('link ainda não gerado', false);
      case VisitSignatureStatus.signed:
        final at = report.signedAt;
        final who = (report.signerName ?? '').trim();
        if (at == null && who.isEmpty) return null;
        final parts = <String>[
          if (at != null) 'em ${dateFmt.format(at.toLocal())}',
          if (who.isNotEmpty) 'por $who',
        ];
        return (parts.join(' '), false);
      case VisitSignatureStatus.expired:
        final expiredAt = report.signatureExpiresAt;
        return (
          expiredAt != null
              ? 'link venceu em ${dateFmt.format(expiredAt.toLocal())}'
              : 'link vencido',
          false,
        );
      case VisitSignatureStatus.unknown:
        return null;
    }
  }

  void _explainLocked(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          'Gerar link de assinatura exige a permissão de editar relatórios '
          'de visita. Peça ao administrador.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final tone = visitStatusColor(context, report.signatureStatus);
    final toneInk = visitInk(context, tone);
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final blue = isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;

    final propsCount = report.properties.length;
    final address = report.firstAddress;
    final deal = (report.kanbanTaskTitle ?? '').trim();
    final broker = (report.createdByName ?? '').trim();
    final detail = _stateDetail();

    final hasActiveLink = report.hasActiveLink;
    final needsLink = !report.isSigned && !hasActiveLink;

    // Ação principal no item (tonal, numa linha própria: a 320dp/130%
    // "Gerar link de assinatura" cabe inteiro) + secundárias abaixo.
    Widget? mainAction;
    if (!report.isSigned && hasActiveLink && onShareWhatsApp != null) {
      mainAction = _MainAction(
        icon: LucideIcons.messageCircle,
        label: 'Enviar no WhatsApp',
        tone: green,
        busy: linkBusy,
        onTap: onShareWhatsApp!,
      );
    } else if (needsLink && canGenerateLink && onGenerateLink != null) {
      mainAction = _MainAction(
        icon: LucideIcons.link,
        label: 'Gerar link de assinatura',
        tone: blue,
        busy: linkBusy,
        onTap: onGenerateLink!,
      );
    } else if (needsLink && !canGenerateLink) {
      mainAction = _MainAction(
        icon: LucideIcons.lock,
        label: 'Gerar link de assinatura',
        tone: neutral,
        locked: true,
        onTap: () => _explainLocked(context),
      );
    }
    final actions = <Widget>[
      if (!report.isSigned && hasActiveLink && onCopyLink != null)
        _CardAction(
          icon: LucideIcons.copy,
          label: 'Copiar link',
          color: neutral,
          busy: linkBusy,
          onTap: onCopyLink!,
        ),
      if (canEdit && onEdit != null)
        _CardAction(
          icon: LucideIcons.penLine,
          label: 'Editar',
          color: neutral,
          onTap: onEdit!,
        ),
    ];
    final showDelete = canDelete && onDelete != null;
    final hasSecondary = actions.isNotEmpty || showDelete;

    Widget infoLine(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(icon, size: 12, color: neutral),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: neutral,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Trilho de agenda: nó do status + linha vertical que conecta
                // os itens do mesmo dia.
                SizedBox(
                  width: 28,
                  child: Column(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: tone.withValues(alpha: isDark ? 0.16 : 0.12),
                          border: Border.all(
                            color: tone.withValues(alpha: 0.45),
                            width: 1.2,
                          ),
                        ),
                        child: Icon(
                          visitStatusIcon(report.signatureStatus),
                          color: toneInk,
                          size: 14,
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: Container(
                            width: 2,
                            margin: const EdgeInsets.only(top: 6),
                            decoration: BoxDecoration(
                              color: ThemeHelpers.borderLightColor(context),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Estado em palavra + o que ele significa. Wrap: com
                        // texto grande a explicação desce inteira.
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _StatusPill(
                              label: report.signatureStatus.shortLabel,
                              fill: tone,
                              ink: toneInk,
                            ),
                            if (detail != null)
                              Text(
                                detail.$1,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: detail.$2
                                      ? visitInk(context, amber)
                                      : neutral,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11.5,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        Text(
                          report.clientLabel,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: ThemeHelpers.textColor(context),
                            height: 1.2,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (address != null)
                          infoLine(
                            LucideIcons.mapPin,
                            propsCount > 1
                                ? '$address · +${propsCount - 1} imóve${propsCount - 1 == 1 ? 'l' : 'is'}'
                                : address,
                          )
                        else if (propsCount == 0)
                          infoLine(
                            LucideIcons.mapPin,
                            'Nenhum imóvel informado',
                          ),
                        if (deal.isNotEmpty)
                          infoLine(LucideIcons.handshake, deal),
                        if (showBroker && broker.isNotEmpty)
                          infoLine(LucideIcons.userRound, 'Corretor: $broker'),
                        if (mainAction != null) ...[
                          const SizedBox(height: 10),
                          mainAction,
                        ],
                        if (hasSecondary) ...[
                          SizedBox(height: mainAction != null ? 4 : 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: actions,
                                ),
                              ),
                              if (showDelete)
                                Tooltip(
                                  message: 'Excluir relatório',
                                  child: InkResponse(
                                    radius: 20,
                                    onTap: onDelete,
                                    child: SizedBox(
                                      width: 36,
                                      height: 36,
                                      child: Center(
                                        child: Icon(
                                          LucideIcons.trash2,
                                          size: 17,
                                          color: danger,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
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
}

/// Ação principal do item — botão tonal (fundo do tom, rótulo na tinta
/// legível), com progresso quando o link está sendo buscado. Rótulo em 1
/// linha que encolhe em vez de estourar.
class _MainAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color tone;
  final VoidCallback onTap;
  final bool busy;
  final bool locked;

  const _MainAction({
    required this.icon,
    required this.label,
    required this.tone,
    required this.onTap,
    this.busy = false,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = locked
        ? ThemeHelpers.textSecondaryColor(context)
        : visitInk(context, tone);
    final fill = locked
        ? (isDark
            ? AppColors.background.backgroundTertiaryDarkMode
            : AppColors.background.backgroundTertiary)
        : tone.withValues(alpha: isDark ? 0.18 : 0.12);
    return Semantics(
      button: true,
      enabled: !locked,
      label: locked ? '$label, bloqueado' : label,
      excludeSemantics: true,
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (busy)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: ink,
                      ),
                    )
                  else
                    Icon(icon, size: 15, color: ink),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ação secundária do item — ícone + rótulo neutros, alvo de 36dp.
class _CardAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool busy;

  const _CardAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 36),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Selo de status — fundo no tom, texto na tinta legível (≥ 4,5:1). Antes
/// o texto usava o próprio tom: "Aguardando" em âmbar sobre âmbar claro.
class _StatusPill extends StatelessWidget {
  final String label;
  final Color fill;
  final Color ink;

  const _StatusPill({
    required this.label,
    required this.fill,
    required this.ink,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: fill.withValues(alpha: isDark ? 0.16 : 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fill.withValues(alpha: isDark ? 0.4 : 0.45)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: ink,
          fontWeight: FontWeight.w800,
          fontSize: 11,
          letterSpacing: -0.1,
        ),
      ),
    );
  }
}
