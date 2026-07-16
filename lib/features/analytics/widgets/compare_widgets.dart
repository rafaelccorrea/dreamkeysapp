// Blocos compartilhados das telas Comparar Corretores / Comparar Equipes —
// tabela lado a lado com melhor valor destacado, cards "melhores em" e
// campos do formulário de critérios.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import 'analytics_ui.dart';

/// Converte texto da máscara monetária pt-BR ("1.234,56") em double.
double? parseCurrencyText(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  final normalized = t.replaceAll('.', '').replaceAll(',', '.');
  return double.tryParse(normalized);
}

/// Linha da tabela de comparação: rótulo + um valor por entidade.
class ComparisonRow {
  final String label;
  final List<String> values;

  /// Índice da melhor entidade nesta métrica (-1 = sem destaque).
  final int bestIndex;

  const ComparisonRow({
    required this.label,
    required this.values,
    this.bestIndex = -1,
  });

  /// Constrói a linha a partir de valores numéricos, destacando o maior
  /// (ou o menor quando [lowerIsBetter], ex.: tempo de resposta).
  factory ComparisonRow.fromValues({
    required String label,
    required List<double> values,
    required String Function(double) format,
    bool lowerIsBetter = false,
  }) {
    var bestIndex = -1;
    if (values.length > 1) {
      var best = values[0];
      bestIndex = 0;
      for (var i = 1; i < values.length; i++) {
        final better =
            lowerIsBetter ? values[i] < best : values[i] > best;
        if (better) {
          best = values[i];
          bestIndex = i;
        }
      }
      // Sem destaque quando todos empatam ou tudo é zero.
      if (values.every((v) => v == values[0]) ||
          (!lowerIsBetter && best <= 0)) {
        bestIndex = -1;
      }
    }
    return ComparisonRow(
      label: label,
      values: values.map(format).toList(growable: false),
      bestIndex: bestIndex,
    );
  }
}

/// Tabela lado a lado (scroll horizontal) — melhor valor de cada linha em
/// verde com medalha, zebra sutil, cabeçalho fixo por coluna de entidade.
class ComparisonTable extends StatelessWidget {
  const ComparisonTable({
    super.key,
    required this.entityNames,
    required this.rows,
  });

  final List<String> entityNames;
  final List<ComparisonRow> rows;

  static const double _labelWidth = 132;
  static const double _cellWidth = 108;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final green = AnalyticsTones.green(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final zebra = Theme.of(context).brightness == Brightness.dark
        ? AppColors.background.backgroundTertiaryDarkMode
            .withValues(alpha: 0.5)
        : AppColors.background.backgroundTertiary.withValues(alpha: 0.6);

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabeçalho
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: ThemeHelpers.borderLightColor(context),
                  ),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: _labelWidth,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 14),
                      child: Text(
                        'MÉTRICA',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                          fontSize: 9.5,
                          color: secondary,
                        ),
                      ),
                    ),
                  ),
                  for (final name in entityNames)
                    SizedBox(
                      width: _cellWidth,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            fontSize: 11.5,
                            height: 1.15,
                            color: ThemeHelpers.textColor(context),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            for (var r = 0; r < rows.length; r++)
              Container(
                color: r.isOdd ? zebra : Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: _labelWidth,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 14, right: 6),
                        child: Text(
                          rows[r].label,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                            height: 1.2,
                            color: secondary,
                          ),
                        ),
                      ),
                    ),
                    for (var c = 0; c < rows[r].values.length; c++)
                      SizedBox(
                        width: _cellWidth,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (rows[r].bestIndex == c) ...[
                              Icon(LucideIcons.medal, size: 11, color: green),
                              const SizedBox(width: 3),
                            ],
                            Flexible(
                              child: Text(
                                rows[r].values[c],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: rows[r].bestIndex == c
                                      ? FontWeight.w900
                                      : FontWeight.w700,
                                  fontSize: 12,
                                  color: rows[r].bestIndex == c
                                      ? green
                                      : ThemeHelpers.textColor(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Card "melhor em X" — vencedor da categoria com valor.
class BestInCard extends StatelessWidget {
  const BestInCard({
    super.key,
    required this.icon,
    required this.category,
    required this.name,
    required this.valueLabel,
    required this.tone,
  });

  final IconData icon;
  final String category;
  final String name;
  final String valueLabel;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              color: tone.withValues(alpha: isDark ? 0.2 : 0.12),
            ),
            child: Icon(icon, size: 16, color: tone),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.9,
                    color: tone,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  valueLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: secondary,
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

/// Campo de data em pill (com limpar), padrão dos modais de filtro.
class CompareDateField extends StatelessWidget {
  const CompareDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
    required this.accent,
  });

  final String label;
  final String? value;
  final VoidCallback onTap;
  final VoidCallback onClear;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldFill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    final filled = value != null && value!.isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
        decoration: BoxDecoration(
          color: fieldFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ThemeHelpers.borderLightColor(context)),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: isDark ? 0.2 : 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child:
                  Icon(Icons.calendar_today_outlined, size: 16, color: accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                filled ? value! : label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: filled
                      ? ThemeHelpers.textColor(context)
                      : ThemeHelpers.textSecondaryColor(context)
                          .withValues(alpha: 0.9),
                ),
              ),
            ),
            if (filled)
              GestureDetector(
                onTap: onClear,
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Campo de texto em pill (UF, preços) — filled, chip de ícone, padrão web.
class CompareTextField extends StatelessWidget {
  const CompareTextField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    required this.accent,
    this.prefixText,
    this.keyboardType,
    this.inputFormatters,
    this.maxLength,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final Color accent;
  final String? prefixText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fieldFill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
      decoration: BoxDecoration(
        color: fieldFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ThemeHelpers.borderLightColor(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.2 : 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              maxLength: maxLength,
              textCapitalization: textCapitalization,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ThemeHelpers.textColor(context),
              ),
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                prefixText: prefixText,
                prefixStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
                hintText: hint,
                hintStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: ThemeHelpers.textSecondaryColor(context)
                      .withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
