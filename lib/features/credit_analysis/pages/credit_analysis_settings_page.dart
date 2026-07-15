import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/credit_analysis_model.dart';
import '../services/credit_analysis_service.dart';

final NumberFormat _money = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 2,
);

/// **Regras de Análise de Crédito** — leitura das configurações de
/// aprovação/rejeição automática (`GET /credit-analysis/settings`). A edição
/// fica no painel web; aqui o gestor consulta a régua vigente em campo.
/// Permissão de entrada: `credit_analysis:review` (paridade com a rota web).
class CreditAnalysisSettingsPage extends StatefulWidget {
  const CreditAnalysisSettingsPage({super.key});

  @override
  State<CreditAnalysisSettingsPage> createState() =>
      _CreditAnalysisSettingsPageState();
}

class _CreditAnalysisSettingsPageState
    extends State<CreditAnalysisSettingsPage> {
  static const double _kPagePadH = 16;

  CreditAnalysisSettings? _settings;
  bool _loading = true;
  String? _error;

  bool get _canReview =>
      ModuleAccessService.instance.hasCompanyModule('credit_and_collection') &&
      ModuleAccessService.instance.hasPermission('credit_analysis:review');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Color _accentColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await CreditAnalysisService.instance.getSettings();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _settings = res.data!;
      } else {
        _error = res.message ?? 'Erro ao carregar configurações';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_canReview) {
      return const AppScaffold(
        title: 'Regras de Crédito',
        showBottomNavigation: false,
        body: _DeniedView(),
      );
    }
    return AppScaffold(
      title: 'Regras de Crédito',
      showBottomNavigation: false,
      body: RefreshIndicator(
        color: _accentColor(context),
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(_kPagePadH, 10, _kPagePadH, 88),
          child: _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _settings == null) return _buildSkeleton();
    if (_error != null && _settings == null) return _buildError(context);
    final s = _settings;
    if (s == null) return _buildError(context);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final emerald =
        isDark ? AppColors.status.successDarkMode : AppColors.status.success;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final blue = isDark ? AppColors.status.infoDarkMode : AppColors.status.info;

    final children = <Widget>[
      _buildHero(context),
      const SizedBox(height: 20),
      _buildSection(
        context,
        tone: emerald,
        icon: LucideIcons.shieldCheck,
        eyebrow: 'APROVAÇÃO AUTOMÁTICA',
        title: 'Quando aprovar sozinho',
        enabled: s.autoApproveEnabled,
        rows: [
          _rule(context, 'Score mínimo', '${s.autoApproveMinScore} pts'),
          _rule(context, 'Máx. de restrições', '${s.autoApproveMaxRestrictions}'),
          _rule(context, 'Dívida máxima', _money.format(s.autoApproveMaxDebt)),
          _boolRule(context, 'Permite ações judiciais',
              s.autoApproveAllowLawsuits),
          _boolRule(
              context, 'Permite protestos', s.autoApproveAllowProtests),
        ],
      ),
      const SizedBox(height: 16),
      _buildSection(
        context,
        tone: danger,
        icon: LucideIcons.shieldX,
        eyebrow: 'REJEIÇÃO AUTOMÁTICA',
        title: 'Quando reprovar sozinho',
        enabled: s.autoRejectEnabled,
        rows: [
          _rule(context, 'Score máximo', '${s.autoRejectMaxScore} pts'),
          _rule(context, 'Mín. de restrições', '${s.autoRejectMinRestrictions}'),
          _rule(context, 'Dívida mínima', _money.format(s.autoRejectMinDebt)),
          _boolRule(
              context, 'Rejeita se houver ações', s.autoRejectIfLawsuits),
          _boolRule(
              context, 'Rejeita se houver protestos', s.autoRejectIfProtests),
        ],
      ),
      const SizedBox(height: 16),
      _buildSection(
        context,
        tone: amber,
        icon: LucideIcons.shieldQuestionMark,
        eyebrow: 'REVISÃO MANUAL',
        title: 'Zona cinzenta',
        rows: [
          _rule(
            context,
            'Faixa de score',
            '${s.manualReviewScoreMin} – ${s.manualReviewScoreMax} pts',
          ),
          _boolRule(context, 'Revisar se houver restrições',
              s.manualReviewIfRestrictions),
          _rule(context, 'Revisar se dívida acima de',
              _money.format(s.manualReviewIfDebtAbove)),
        ],
      ),
      const SizedBox(height: 16),
      _buildSection(
        context,
        tone: blue,
        icon: LucideIcons.house,
        eyebrow: 'REGRAS DE LOCAÇÃO',
        title: 'Impacto na criação de aluguel',
        rows: [
          _boolRule(context, 'Exige análise para criar aluguel',
              s.requireCreditAnalysisToCreateRental),
          _boolRule(context, 'Só permite aluguel com parecer positivo',
              s.onlyAllowRentalIfAnalysisPositive),
          if (s.minScoreToAllowRental != null)
            _rule(context, 'Score mínimo para alugar',
                '${s.minScoreToAllowRental} pts'),
          _boolRule(context, 'Exige comprovação de renda',
              s.requireIncomeVerification),
          if (s.minIncomeRatio > 0)
            _rule(
              context,
              'Renda mínima',
              '${s.minIncomeRatio.toStringAsFixed(s.minIncomeRatio % 1 == 0 ? 0 : 1).replaceAll('.', ',')}× o aluguel',
            ),
        ],
      ),
    ];

    var i = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final w in children)
          w is SizedBox
              ? w
              : w.animate(key: ValueKey('sec-${i++}')).fadeIn(
                    delay: Duration(milliseconds: 40 * i),
                    duration: 240.ms,
                  ),
      ],
    );
  }

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accentColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration:
                    BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Text(
                'ANÁLISE DE CRÉDITO · REGRAS',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.6,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Critérios automáticos vigentes',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
              height: 1.05,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Somente leitura no app — a régua é ajustada no painel web.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondary,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required Color tone,
    required IconData icon,
    required String eyebrow,
    required String title,
    required List<Widget> rows,
    bool? enabled,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(18),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: tone.withValues(alpha: isDark ? 0.2 : 0.12),
                ),
                child: Icon(icon, color: tone, size: 19),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: tone,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
              if (enabled != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: (enabled ? tone : ThemeHelpers.textSecondaryColor(context))
                        .withValues(alpha: isDark ? 0.16 : 0.1),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: (enabled
                              ? tone
                              : ThemeHelpers.textSecondaryColor(context))
                          .withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    enabled ? 'Ativa' : 'Inativa',
                    style: TextStyle(
                      color: enabled
                          ? tone
                          : ThemeHelpers.textSecondaryColor(context),
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ...rows,
        ],
      ),
    );
  }

  Widget _rule(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.7),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  /// Regra booleana — verde quando "Sim", cinza quando "Não" (cor por
  /// significado, sem alarmismo: aqui é configuração, não risco).
  Widget _boolRule(BuildContext context, String label, bool value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final good =
        isDark ? AppColors.status.successDarkMode : AppColors.status.success;
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.7),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: neutral,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Icon(
            value ? LucideIcons.circleCheck : LucideIcons.circle,
            size: 13,
            color: value ? good : neutral.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 5),
          Text(
            value ? 'Sim' : 'Não',
            style: theme.textTheme.bodySmall?.copyWith(
              color: value ? good : neutral,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        const SkeletonText(width: 180, height: 12),
        const SizedBox(height: 10),
        const SkeletonText(width: 240, height: 22),
        const SizedBox(height: 8),
        const SkeletonText(width: double.infinity, height: 13),
        const SizedBox(height: 20),
        for (var i = 0; i < 3; i++) ...[
          SkeletonBox(
            width: double.infinity,
            height: 190,
            borderRadius: 18,
            margin: const EdgeInsets.only(bottom: 16),
          ),
        ],
      ],
    );
  }

  Widget _buildError(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 4),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: danger.withValues(alpha: 0.12),
              border: Border.all(color: danger.withValues(alpha: 0.32)),
            ),
            child: Icon(LucideIcons.cloudOff, color: danger, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            _error ?? 'Erro ao carregar configurações',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}

class _DeniedView extends StatelessWidget {
  const _DeniedView();
  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.lock, size: 38, color: secondary),
            const SizedBox(height: 12),
            Text(
              'Você não tem acesso às regras de análise de crédito.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Solicite ao administrador a permissão de revisão de análises.',
              textAlign: TextAlign.center,
              style: TextStyle(color: secondary, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
