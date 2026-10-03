import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../core/finance_format.dart';
import '../models/drill_models.dart';
import '../models/meu_financeiro_models.dart';

/// Paleta das famílias de valor (mesma leitura do web).
class FinanceTones {
  FinanceTones._();
  static const Color emerald = Color(0xFF10B981);
  static const Color amber = Color(0xFFF59E0B);
  static const Color rose = Color(0xFFF43F5E);
  static const Color sky = Color(0xFF0EA5E9);
  static const Color violet = Color(0xFF8B5CF6);
  static const Color slate = Color(0xFF64748B);

  static Color proximoStatus(String status, {bool emAtraso = false}) {
    if (emAtraso) return rose;
    switch (status) {
      case 'WAITING_FOR_SIGNATURE':
      case 'ADVANCE':
      case 'APROVADO':
        return amber;
      case 'PAID':
        return emerald;
      case 'REVERSAL':
        return rose;
      default:
        return sky;
    }
  }

  static Color advanceStatus(String s) {
    switch (s) {
      case 'SOLICITADO':
        return sky;
      case 'APROVADO':
      case 'QUITADO':
        return emerald;
      case 'PAGO':
        return amber;
      case 'REPROVADO':
        return rose;
      default:
        return slate;
    }
  }

  static Color requestStatus(String s) {
    switch (s) {
      case 'APROVADO':
      case 'CONCLUIDO':
        return emerald;
      case 'REPROVADO':
        return rose;
      case 'EM_PROCESSAMENTO':
        return violet;
      case 'CANCELADO':
        return slate;
      default:
        return amber;
    }
  }
}

Color financeAccent(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? AppColors.primary.primaryDarkMode
    : AppColors.primary.primary;

/// Cartão base das seções.
class FinanceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? borderColor;

  const FinanceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: borderColor ?? ThemeHelpers.borderLightColor(context),
        ),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: card,
      ),
    );
  }
}

/// Título de seção com ação opcional à direita.
class FinanceSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget? trailing;

  const FinanceSectionHeader({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final accent = financeAccent(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 17, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.3,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Pílula de status.
class FinancePill extends StatelessWidget {
  final String label;
  final Color color;

  const FinancePill({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// Chip de filtro.
class FinanceFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const FinanceFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = financeAccent(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected
            ? accent.withValues(alpha: 0.12)
            : ThemeHelpers.cardBackgroundColor(context),
        shape: StadiumBorder(
          side: BorderSide(
            color: selected
                ? accent.withValues(alpha: 0.5)
                : ThemeHelpers.borderLightColor(context),
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected
                    ? accent
                    : ThemeHelpers.textSecondaryColor(context),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Cartão destaque "A receber" (gradiente da marca).
class FinanceHeroCard extends StatelessWidget {
  final String label;
  final double value;
  final bool hidden;
  final String? liquido;
  final String? tag;
  final bool selected;
  final VoidCallback onTap;

  const FinanceHeroCard({
    super.key,
    required this.label,
    required this.value,
    required this.hidden,
    required this.onTap,
    this.liquido,
    this.tag,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = financeAccent(context);
    final deep = Color.lerp(accent, Colors.black, 0.45)!;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [accent, deep],
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.28),
                blurRadius: 24,
                offset: const Offset(0, 12),
                spreadRadius: -8,
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -8,
                top: -6,
                child: Icon(
                  LucideIcons.wallet,
                  size: 86,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11.5,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w800,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                      if (selected) ...[
                        const SizedBox(width: 8),
                        Icon(
                          LucideIcons.listFilter,
                          size: 13,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formatBrl(value, hidden: hidden),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.8,
                        color: Colors.white,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  if (liquido != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      liquido!,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                  if (tag != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            LucideIcons.signature,
                            size: 13,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              tag!,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// KPI compacto (grade 2×2).
class FinanceKpiTile extends StatelessWidget {
  final String label;
  final String value;
  final String hint;
  final IconData icon;
  final Color tone;
  final bool selected;
  final VoidCallback onTap;

  const FinanceKpiTile({
    super.key,
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    required this.tone,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return FinanceCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      borderColor: selected ? tone.withValues(alpha: 0.6) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 15, color: tone),
              ),
              const Spacer(),
              if (selected) Icon(LucideIcons.listFilter, size: 14, color: tone),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
                color: ThemeHelpers.textColor(context),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            hint,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.25,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Barra de composição: recebido / retido / a receber.
class FinanceCompositionBar extends StatelessWidget {
  final EarningsTotals totals;
  final bool hidden;

  const FinanceCompositionBar({
    super.key,
    required this.totals,
    required this.hidden,
  });

  @override
  Widget build(BuildContext context) {
    final aReceber = math.max(0.0, totals.aReceber);
    final devido = totals.recebido + totals.retido + aReceber;
    final parts = [
      (FinanceTones.emerald, 'Recebido', totals.recebido),
      (FinanceTones.amber, 'Retido', totals.retido),
      (FinanceTones.sky, 'A receber', aReceber),
    ];
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Devido',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: secondary,
              ),
            ),
            const Spacer(),
            Text(
              formatBrl(devido, hidden: hidden),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: ThemeHelpers.textColor(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 10,
            child: devido <= 0
                ? ColoredBox(color: ThemeHelpers.borderLightColor(context))
                : Row(
                    children: [
                      for (final p in parts)
                        if (p.$3 > 0)
                          Expanded(
                            flex: math.max(1, (p.$3 / devido * 1000).round()),
                            child: ColoredBox(color: p.$1),
                          ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            for (final p in parts)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: p.$1,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${p.$2} ${formatBrl(p.$3, hidden: hidden)}',
                    style: TextStyle(fontSize: 11.5, color: secondary),
                  ),
                ],
              ),
          ],
        ),
        if ((totals.travado ?? 0) > 0) ...[
          const SizedBox(height: 8),
          Text(
            '+ ${formatBrl(totals.travado!, hidden: hidden)} travado · sem assinatura',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: FinanceTones.amber,
            ),
          ),
        ],
        if ((totals.bonificacao ?? 0) > 0) ...[
          const SizedBox(height: 4),
          Text(
            'incl. ${formatBrl(totals.bonificacao!, hidden: hidden)} de bonificação',
            style: TextStyle(fontSize: 11.5, color: secondary),
          ),
        ],
      ],
    );
  }
}

/// "Linha do tempo das comissões": barras empilhadas (recebido + retido) e
/// o previsto como marcador, nos últimos meses.
class FinanceMonthlyChart extends StatelessWidget {
  final List<MonthlyEarning> mensal;
  final bool hidden;

  /// Mês selecionado (`YYYY-MM`) — os outros ficam esmaecidos.
  final String? selectedMonth;

  /// Toque no mês filtra a lista "por visão" (outro toque desfaz).
  final ValueChanged<String>? onMonthTap;

  const FinanceMonthlyChart({
    super.key,
    required this.mensal,
    required this.hidden,
    this.selectedMonth,
    this.onMonthTap,
  });

  @override
  Widget build(BuildContext context) {
    // 6 meses para trás e 5 à frente do mês atual (o back manda 12 + 6).
    final meses = janelaDoGrafico(mensal, DateTime.now());
    final secondary = ThemeHelpers.textSecondaryColor(context);
    if (meses.isEmpty ||
        meses.every((m) => m.recebido + m.retido + m.previsto == 0)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text(
            'Sem movimentações na janela do gráfico.',
            style: TextStyle(fontSize: 13, color: secondary),
          ),
        ),
      );
    }
    final maxV = meses
        .map((m) => math.max(m.recebido + m.retido, m.previsto))
        .fold<double>(0, math.max);
    const barH = 120.0;
    return Column(
      children: [
        SizedBox(
          height: barH + 22,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final m in meses)
                Expanded(
                  child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onMonthTap == null ? null : () => onMonthTap!(m.month),
                  child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: selectedMonth == null || selectedMonth == m.month ? 1 : 0.35,
                  child: Tooltip(
                    message: hidden
                        ? _monthLabel(m.month)
                        : '${_monthLabel(m.month)}\nRecebido ${formatBrl(m.recebido)}\n'
                              'Retido ${formatBrl(m.retido)}\nPrevisto ${formatBrl(m.previsto)}',
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SizedBox(
                          height: barH,
                          child: Stack(
                            alignment: Alignment.bottomCenter,
                            children: [
                              Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  _bar(
                                    m.retido,
                                    maxV,
                                    barH,
                                    FinanceTones.amber,
                                  ),
                                  _bar(
                                    m.recebido,
                                    maxV,
                                    barH,
                                    FinanceTones.emerald,
                                  ),
                                ],
                              ),
                              if (m.previsto > 0 && maxV > 0)
                                Positioned(
                                  bottom: (m.previsto / maxV * barH).clamp(
                                    2,
                                    barH - 2,
                                  ),
                                  left: 6,
                                  right: 6,
                                  child: Container(
                                    height: 2.5,
                                    decoration: BoxDecoration(
                                      color: FinanceTones.sky,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _monthShort(m.month),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: selectedMonth == m.month
                                ? FontWeight.w900
                                : FontWeight.w600,
                            color: selectedMonth == m.month
                                ? financeAccent(context)
                                : secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          children: [
            _legend(FinanceTones.emerald, 'Recebido', secondary),
            _legend(FinanceTones.amber, 'Retido', secondary),
            _legend(FinanceTones.sky, 'Previsto', secondary),
          ],
        ),
      ],
    );
  }

  Widget _bar(double v, double maxV, double h, Color c) {
    if (v <= 0 || maxV <= 0) return const SizedBox.shrink();
    return Container(
      width: 14,
      height: math.max(2, v / maxV * h),
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(5),
      ),
    );
  }

  Widget _legend(Color c, String t, Color text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 4,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 6),
      Text(t, style: TextStyle(fontSize: 11.5, color: text)),
    ],
  );

  static String _monthShort(String ym) {
    final d = DateTime.tryParse('$ym-01');
    if (d == null) return ym;
    final s = DateFormat('MMM', 'pt_BR').format(d).replaceAll('.', '');
    return s.isEmpty ? ym : '${s[0].toUpperCase()}${s.substring(1)}';
  }

  static String _monthLabel(String ym) {
    final d = DateTime.tryParse('$ym-01');
    if (d == null) return ym;
    return DateFormat("MMMM 'de' yyyy", 'pt_BR').format(d);
  }
}

/// Linha genérica de lista (título, subtítulo, valor e pílula).
class FinanceRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? meta;
  final String value;
  final FinancePill? pill;
  final VoidCallback? onTap;

  /// Ação extra à direita (ex.: "De onde vem este repasse").
  final Widget? action;

  const FinanceRow({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    this.meta,
    this.pill,
    this.onTap,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: secondary),
                    ),
                  ],
                  if (meta != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      meta!,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: secondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (pill != null) ...[const SizedBox(height: 5), pill!],
              ],
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}

/// Estado vazio dentro de uma seção.
class FinanceEmpty extends StatelessWidget {
  final String text;
  final IconData icon;

  const FinanceEmpty({
    super.key,
    required this.text,
    this.icon = LucideIcons.inbox,
  });

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: secondary.withValues(alpha: 0.7)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: secondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Aviso inline (erro de uma seção).
class FinanceInlineNotice extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;
  final VoidCallback? onRetry;

  const FinanceInlineNotice({
    super.key,
    required this.text,
    this.color = FinanceTones.rose,
    this.icon = LucideIcons.circleAlert,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
          if (onRetry != null)
            IconButton(
              tooltip: 'Tentar de novo',
              visualDensity: VisualDensity.compact,
              onPressed: onRetry,
              icon: Icon(LucideIcons.refreshCw, size: 16, color: color),
            ),
        ],
      ),
    );
  }
}
