import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import 'dashboard_filters_drawer.dart';

/// Tinta e formatação da Home executiva (admin/master).
///
/// 29/09/2026 (dash-01): cor por SIGNIFICADO, igual ao `DH` do web
/// (`DashboardHomeStyles.ts`), nunca por identificação:
///   aço (sky)      = o que ENTRA (leads, canais);
///   pedra (slate)  = estrutura, número derivado (conversão, ranking);
///   âmbar          = compromisso no tempo, atenção (agenda, vence hoje);
///   musgo (green)  = confirmado (fichas finalizadas, meta batida);
///   oxblood (red)  = perda, atraso.
/// Os tons do modo claro são os escuros do web — texto âmbar #E6B84C sobre
/// branco não passa contraste; #B45309 passa.
abstract final class OverviewTones {
  static bool _dark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

  static Color sky(BuildContext c) =>
      _dark(c) ? const Color(0xFF7DB8D8) : const Color(0xFF2E6F8E);
  static Color slate(BuildContext c) =>
      _dark(c) ? const Color(0xFFA8A29E) : const Color(0xFF57534E);
  static Color amber(BuildContext c) =>
      _dark(c) ? const Color(0xFFF0A868) : const Color(0xFFB45309);
  static Color green(BuildContext c) =>
      _dark(c) ? const Color(0xFF9BCB5A) : const Color(0xFF4D7C0F);
  static Color red(BuildContext c) =>
      _dark(c) ? const Color(0xFFFB7185) : const Color(0xFF9F1239);

  /// Vermelho da marca — a curva do VGV e o anel da meta no caminho normal.
  static Color brand(BuildContext c) =>
      _dark(c) ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;

  /// Trilho das réguas (fundo neutro, sem gota de cor).
  static Color track(BuildContext c) => _dark(c)
      ? Colors.white.withValues(alpha: 0.07)
      : const Color(0xFFECEDF1);

  /// Fio que separa as faixas.
  static Color rule(BuildContext c) =>
      ThemeHelpers.borderLightColor(c).withValues(alpha: _dark(c) ? 0.9 : 1);
}

final NumberFormat _intFmt = NumberFormat.decimalPattern('pt_BR');

String ovInt(num? v) => _intFmt.format((v ?? 0).round());

final Map<int, NumberFormat> _casasFmt = <int, NumberFormat>{};

String _casas(double n, int d) => (_casasFmt[d] ??=
        NumberFormat.decimalPatternDigits(locale: 'pt_BR', decimalDigits: d))
    .format(n);

/// "12,5%" — vírgula decimal, como o resto do sistema.
String ovPct(double? v, [int digits = 1]) => '${_casas(v ?? 0, digits)}%';

/// "R$ 1,25M", "R$ 12k", "R$ 950" — o `fmtMoneyShort` do web.
String ovMoneyShort(double? v) {
  final n = v ?? 0;
  final sign = n < 0 ? '-' : '';
  final a = n.abs();
  if (a >= 1000000) {
    return '${sign}R\$ ${_casas(a / 1000000, a >= 10000000 ? 1 : 2)}M';
  }
  if (a >= 1000) return '${sign}R\$ ${_casas(a / 1000, a >= 10000 ? 0 : 1)}k';
  return '${sign}R\$ ${_casas(a, 0)}';
}

/// "R$ 1.250.000" — valor cheio, sem centavos (o `fmtMoney` do web).
String ovMoney(double? v) => 'R\$ ${_casas(v ?? 0, 0)}';

/// Tom da variação com ZONA MORTA (abaixo de 0,05% em módulo é "estável"),
/// mesma regra do `deltaTone` do web: sem ela, 0,02% vira seta verde.
enum OvDeltaTone { up, down, flat }

OvDeltaTone ovDeltaTone(double? v) {
  if (v == null || v.abs() < 0.05) return OvDeltaTone.flat;
  return v > 0 ? OvDeltaTone.up : OvDeltaTone.down;
}

/// Sinal explícito no positivo; travessão quando não há com o que comparar.
String ovDelta(double? v) {
  if (v == null) return '—';
  final s = _casas(v, 1);
  return v > 0 ? '+$s%' : '$s%';
}

const List<String> _kMonths = [
  'Jan',
  'Fev',
  'Mar',
  'Abr',
  'Mai',
  'Jun',
  'Jul',
  'Ago',
  'Set',
  'Out',
  'Nov',
  'Dez',
];

/// Rótulo curto para chaves `YYYY-MM` ("Mai/26"); rótulo já curto passa.
String ovShortMonth(String label) {
  final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(label.trim());
  if (m == null) return label;
  final month = int.tryParse(m.group(2)!) ?? 0;
  if (month < 1 || month > 12) return label;
  return '${_kMonths[month - 1]}/${m.group(1)!.substring(2)}';
}

/// "agora", "há 5min", "há 3h", "ontem", "há 4d" ou "12/09".
String ovTimeAgo(DateTime? d) {
  if (d == null) return '';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'agora';
  if (diff.inMinutes < 60) return 'há ${diff.inMinutes}min';
  if (diff.inHours < 24) return 'há ${diff.inHours}h';
  if (diff.inDays == 1) return 'ontem';
  if (diff.inDays < 7) return 'há ${diff.inDays}d';
  return DateFormat('dd/MM', 'pt_BR').format(d);
}

const Map<String, String> _kRangeLabels = {
  'today': 'Hoje',
  '7d': 'Últimos 7 dias',
  '30d': 'Últimos 30 dias',
  '90d': 'Últimos 90 dias',
  '1y': 'Último ano',
  'custom': 'Personalizado',
};

DateTime? _ymd(String? s) =>
    s == null || s.isEmpty ? null : DateTime.tryParse(s);

/// Rótulo do recorte ("01/09 – 29/09/2026" ou "Últimos 30 dias").
String ovPeriodLabel(DashboardFilters f) {
  final s = _ymd(f.startDate);
  final e = _ymd(f.endDate);
  if (f.dateRange == 'custom' && s != null && e != null) {
    return '${DateFormat('dd/MM').format(s)} – ${DateFormat('dd/MM/yyyy').format(e)}';
  }
  return _kRangeLabels[f.dateRange ?? 'custom'] ?? (f.dateRange ?? '');
}

/// Palavra do recorte para o botão do topo ("Este mês", "Hoje"...).
String ovPeriodWord(DashboardFilters f) {
  if (f.dateRange == 'custom') {
    return f.isCurrentMonthPeriod ? 'Este mês' : 'Período escolhido';
  }
  return _kRangeLabels[f.dateRange ?? ''] ?? 'Período';
}

/// Quantos dias o recorte cobre (inclusivo) — o `diasDoRecorte` do web.
int ovDaysInRange(DashboardFilters f) {
  final s = _ymd(f.startDate);
  final e = _ymd(f.endDate);
  if (f.dateRange == 'custom' && s != null && e != null) {
    final n = e.difference(s).inDays + 1;
    return n < 1 ? 1 : n;
  }
  switch (f.dateRange) {
    case 'today':
      return 1;
    case '7d':
      return 7;
    case '30d':
      return 30;
    case '90d':
      return 90;
    case '1y':
      return 365;
    default:
      return DateTime.now().day;
  }
}

/// Rótulo da comparação ("vs. período anterior").
String ovCompareLabel(String? compareWith) {
  switch (compareWith) {
    case 'previous_period':
      return 'vs. período anterior';
    case 'previous_year':
      return 'vs. mesmo período do ano passado';
    default:
      return 'sem comparação';
  }
}

String _titleCase(String s) => s
    .replaceAll(RegExp(r'[_-]+'), ' ')
    .split(' ')
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
    .join(' ');

/// Situação do lead: o back manda o `result` do card (open/won/lost) ou o
/// status do cliente — os dois viram português.
String ovLeadStatus(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '—';
  const labels = {
    'open': 'Em andamento',
    'won': 'Ganho',
    'lost': 'Perdido',
    'cancelled': 'Cancelado',
    'active': 'Ativo',
    'contacted': 'Contatado',
    'interested': 'Interessado',
    'closed': 'Fechado',
    'inactive': 'Inativo',
  };
  return labels[raw.trim().toLowerCase()] ?? _titleCase(raw.trim());
}

/// Origem livre normalizada — o `normalizeFreeSource` do web.
String ovSource(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '—';
  final t = raw.trim();
  final lower = t.toLowerCase();
  if (lower == 'chatpro' || lower.contains('whatsapp')) return 'WhatsApp';
  if (lower.contains('meta') ||
      lower.contains('facebook') ||
      lower.contains('instagram')) {
    return 'Meta';
  }
  if (lower.contains('google')) return 'Google Ads';
  if (lower.contains('webhook')) return 'Webhook';
  if (lower.contains('site') || lower.contains('landing')) return 'Site';
  if (lower.contains('grupozap') || lower.contains('grupo zap')) {
    return 'Grupo ZAP';
  }
  if (lower.contains('olx')) return 'OLX';
  if (lower.contains('chaves')) return 'Chaves na Mão';
  if (lower.contains('indicac')) return 'Indicação';
  if (lower.contains('telefone')) return 'Telefone';
  if (lower.contains('placa')) return 'Placa';
  if (lower.contains('plant')) return 'Plantão';
  if (lower.contains('presencial')) return 'Presencial';
  const known = {
    'phone': 'Telefone',
    'social_media': 'Redes Sociais',
    'zap_imoveis': 'Zap Imóveis',
    'viva_real': 'Viva Real',
    'dream_keys': 'Intellisys',
    'other': 'Outro',
  };
  return known[lower] ?? _titleCase(t);
}

/// Prioridade da tarefa em português.
String ovPriority(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'low':
      return 'Baixa';
    case 'medium':
      return 'Média';
    case 'high':
      return 'Alta';
    case 'urgent':
      return 'Urgente';
    default:
      return raw.isEmpty ? '—' : _titleCase(raw);
  }
}

/// Iniciais (duas) para o avatar sem foto.
String ovInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  final letters = parts.take(2).map((p) => p[0].toUpperCase()).join();
  return letters.isEmpty ? '?' : letters;
}

// ─── Peças visuais comuns ────────────────────────────────────────────────────

/// Cabeçalho de faixa: traço tonal curto + título + dica, com ação à direita.
/// O título nunca trunca com reticências — quebra linha.
class OverviewBandHeader extends StatelessWidget {
  const OverviewBandHeader({
    super.key,
    required this.title,
    required this.tone,
    this.hint,
    this.trailing,
  });

  final String title;
  final Color tone;
  final String? hint;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            width: 16,
            height: 3,
            decoration: BoxDecoration(
              color: tone,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                softWrap: true,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  letterSpacing: -0.3,
                  height: 1.2,
                ),
              ),
              if (hint != null && hint!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  hint!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    height: 1.3,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

/// Rótulo pequeno em caixa alta (cabeça de zona dentro de uma faixa).
class OverviewEyebrow extends StatelessWidget {
  const OverviewEyebrow(this.text, {super.key, this.tone});

  final String text;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: tone ?? ThemeHelpers.textSecondaryColor(context),
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            fontSize: 10.5,
            height: 1.3,
          ),
    );
  }
}

/// Link de texto de uma zona ("Ver detalhes", "Abrir").
class OverviewLink extends StatelessWidget {
  const OverviewLink({
    super.key,
    required this.label,
    required this.onTap,
    this.withChevron = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool withChevron;

  @override
  Widget build(BuildContext context) {
    final color = ThemeHelpers.textColor(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                    decoration: TextDecoration.underline,
                    decorationColor: color.withValues(alpha: 0.35),
                  ),
            ),
            if (withChevron)
              Icon(Icons.chevron_right_rounded, size: 16, color: color),
          ],
        ),
      ),
    );
  }
}

/// Selo de variação (seta + percentual) na tinta do sentido.
class OverviewDeltaChip extends StatelessWidget {
  const OverviewDeltaChip({super.key, required this.value, this.compact = false});

  final double? value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tone = ovDeltaTone(value);
    final color = switch (tone) {
      OvDeltaTone.up => OverviewTones.green(context),
      OvDeltaTone.down => OverviewTones.red(context),
      OvDeltaTone.flat => OverviewTones.slate(context),
    };
    final icon = switch (tone) {
      OvDeltaTone.up => Icons.north_east_rounded,
      OvDeltaTone.down => Icons.south_east_rounded,
      OvDeltaTone.flat => Icons.remove_rounded,
    };
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 11 : 12, color: color),
          const SizedBox(width: 3),
          Text(
            ovDelta(value),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: compact ? 10.5 : 11.5,
              height: 1.1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Régua proporcional (trilho neutro + preenchimento na tinta).
class OverviewBar extends StatelessWidget {
  const OverviewBar({
    super.key,
    required this.fraction,
    required this.tone,
    this.height = 6,
  });

  /// 0–1. Quem tem valor nunca some: piso visual de 2,5%.
  final double fraction;
  final Color tone;
  final double height;

  @override
  Widget build(BuildContext context) {
    final f = fraction <= 0 ? 0.0 : fraction.clamp(0.025, 1.0).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(color: OverviewTones.track(context)),
            ),
            FractionallySizedBox(
              widthFactor: f,
              heightFactor: 1,
              alignment: Alignment.centerLeft,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tone,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vazio de uma zona: ícone + frase curta, sem casca.
class OverviewEmptyLine extends StatelessWidget {
  const OverviewEmptyLine({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 18, color: secondary.withValues(alpha: 0.8)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: secondary,
                    height: 1.35,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Avatar com foto (quando houver) ou iniciais em chapa neutra.
class OverviewAvatar extends StatelessWidget {
  const OverviewAvatar({
    super.key,
    required this.name,
    this.url,
    this.size = 34,
  });

  final String name;
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark ? const Color(0xFF1C1C23) : const Color(0xFFEEF0F3),
        border: Border.all(color: ThemeHelpers.borderLightColor(context)),
      ),
      child: Text(
        ovInitials(name),
        style: TextStyle(
          color: ThemeHelpers.textColor(context),
          fontWeight: FontWeight.w800,
          fontSize: size * 0.36,
          height: 1,
        ),
      ),
    );
    final u = url;
    if (u == null || u.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        u,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}
