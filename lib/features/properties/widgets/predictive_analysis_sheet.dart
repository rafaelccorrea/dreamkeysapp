import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/ai_service.dart';

/// Mensagem amigável para a falha da análise preditiva — mesmos textos do
/// `usePredictiveSales.ts` do web (400 = limite diário, 429 = muitas
/// requisições, 404/403 = indisponível).
String predictiveAnalysisErrorMessage(int statusCode, String? message) {
  switch (statusCode) {
    case 400:
      return 'O limite diário de análises de IA foi atingido. Tente novamente '
          'amanhã ou entre em contato com o suporte para mais informações.';
    case 429:
      return 'Muitas requisições foram feitas. Aguarde alguns minutos antes '
          'de tentar novamente.';
    case 404:
      return 'API de análise preditiva não encontrada. Esta funcionalidade '
          'pode não estar disponível.';
    case 403:
      return 'Acesso negado à API de análise preditiva. Esta funcionalidade '
          'pode não estar disponível.';
  }
  final m = (message ?? '').trim();
  return m.isEmpty ? 'Erro na análise preditiva' : m;
}

/// Rótulo da probabilidade como o web: ≥70 Alta, ≥40 Média, senão Baixa.
String predictiveProbabilityLabel(double p) {
  if (p >= 70) return 'Alta';
  if (p >= 40) return 'Média';
  return 'Baixa';
}

/// "Análise preditiva" do menu do card (web `PropertiesPage.tsx` ~3438 +
/// `PredictiveAnalysisModal.tsx`): `POST /ai-assistant/predictive/sales
/// { propertyId, analysisType: 'single' }`.
Future<void> showPredictiveAnalysisSheet(
  BuildContext context, {
  required String propertyId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => _PredictiveAnalysisSheet(propertyId: propertyId),
  );
}

class _PredictiveAnalysisSheet extends StatefulWidget {
  const _PredictiveAnalysisSheet({required this.propertyId});

  final String propertyId;

  @override
  State<_PredictiveAnalysisSheet> createState() =>
      _PredictiveAnalysisSheetState();
}

class _PredictiveAnalysisSheetState extends State<_PredictiveAnalysisSheet> {
  bool _loading = true;
  String? _error;
  PredictiveSalesResponse? _analysis;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await AiService.instance.predictiveSalesAnalysis(
      PredictiveSalesRequest(
        propertyId: widget.propertyId,
        analysisType: 'single',
      ),
    );
    if (!mounted) return;
    PredictiveSalesResponse? found;
    final data = res.data;
    if (data is PredictiveSalesResponse) {
      found = data;
    } else if (data is List) {
      found = data.whereType<PredictiveSalesResponse>().firstOrNull;
    }
    setState(() {
      _loading = false;
      if (!res.success) {
        _error = predictiveAnalysisErrorMessage(res.statusCode, res.message);
      } else if (found == null || found.propertyId.isEmpty) {
        // Resposta vazia: o web trata como limite de IA atingido.
        _error = 'Não foi possível gerar a análise no momento. O limite '
            'diário de IA pode ter sido atingido. Tente novamente amanhã.';
      } else {
        _analysis = found;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final accent = AppColors.primary.primary;

    return Container(
      constraints: BoxConstraints(maxHeight: mq.size.height * 0.9),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: secondary.withValues(alpha: 0.32),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
              child: Row(
                children: [
                  Icon(LucideIcons.sparkles, color: accent, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Análise preditiva de vendas',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: _buildBody(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final textColor = ThemeHelpers.textColor(context);
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 14),
            Text(
              'Gerando análise preditiva...',
              style: TextStyle(color: secondary, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      final err = AppColors.status.error;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: err.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: err.withValues(alpha: 0.35)),
            ),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: err, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _run,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Tentar novamente'),
          ),
        ],
      );
    }
    final a = _analysis!;
    final money = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: r'R$',
      decimalDigits: 0,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (a.propertyTitle.isNotEmpty)
          Text(
            a.propertyTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: textColor,
            ),
          ),
        const SizedBox(height: 12),
        _StatTile(
          label: 'Venda estimada',
          value: '${a.estimatedDaysToSale} dias',
          icon: LucideIcons.timer,
          tone: AppColors.primary.primary,
          highlight: true,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final (label, p) in [
              ('30 dias', a.probability30Days),
              ('60 dias', a.probability60Days),
              ('90 dias', a.probability90Days),
            ]) ...[
              if (label != '30 dias') const SizedBox(width: 8),
              Expanded(
                child: _StatTile(
                  label: 'Probabilidade $label',
                  value: '${p.round()}%',
                  badge: predictiveProbabilityLabel(p),
                  icon: p >= 70
                      ? LucideIcons.trendingUp
                      : p >= 40
                          ? LucideIcons.moveRight
                          : LucideIcons.trendingDown,
                  tone: p >= 70
                      ? AppColors.status.success
                      : p >= 40
                          ? AppColors.status.warning
                          : AppColors.status.error,
                ),
              ),
            ],
          ],
        ),
        if (a.suggestedPrice != null && a.suggestedPrice! > 0) ...[
          const SizedBox(height: 16),
          _SectionTitle(icon: LucideIcons.circleDollarSign, label: 'Preço sugerido pela IA'),
          const SizedBox(height: 6),
          Text(
            money.format(a.suggestedPrice),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: AppColors.status.success,
            ),
          ),
        ],
        if ((a.priceImpact ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.status.warning.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.status.warning.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Impacto do preço',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(a.priceImpact!.trim(), style: TextStyle(color: textColor)),
              ],
            ),
          ),
        ],
        if (a.influencingFactors.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionTitle(icon: LucideIcons.trendingUp, label: 'Fatores que influenciam'),
          const SizedBox(height: 6),
          for (final f in a.influencingFactors) _Bullet(text: f),
        ],
        if (a.recommendations.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionTitle(icon: LucideIcons.lightbulb, label: 'Recomendações de ação'),
          const SizedBox(height: 6),
          for (final r in a.recommendations) _Bullet(text: r),
        ],
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
    this.badge,
    this.highlight = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color tone;
  final String? badge;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: highlight ? (isDark ? 0.20 : 0.10) : 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 2,
            style: TextStyle(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w800,
              fontSize: 9.5,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(icon, size: 16, color: tone),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  value,
                  style: TextStyle(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w900,
                    fontSize: highlight ? 20 : 16,
                  ),
                ),
              ),
            ],
          ),
          if (badge != null) ...[
            const SizedBox(height: 4),
            Text(
              badge!,
              style: TextStyle(
                color: tone,
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 17, color: AppColors.primary.primary),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: ThemeHelpers.textColor(context),
            fontWeight: FontWeight.w900,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 8),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.primary.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
