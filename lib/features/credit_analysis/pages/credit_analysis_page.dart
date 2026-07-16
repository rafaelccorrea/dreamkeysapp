import 'dart:async';
import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/notifications/app_toast.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/utils/input_formatters.dart';
import '../../../shared/utils/masks.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/credit_analysis_model.dart';
import '../services/credit_analysis_service.dart';
import '../widgets/credit_analysis_card.dart';

final NumberFormat _money = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: 'R\$',
  decimalDigits: 2,
);

/// Tela **Análise de Crédito** — porta do `CreditAnalysisPage.tsx` do painel
/// web. O hero traz o gauge do score médio como protagonista + medidor da
/// taxa de aprovação; busca flush, abas flush com sublinhado, lista de
/// pareceres e ações no próprio item (detalhe + refazer). Módulo
/// `credit_and_collection`, permissões `credit_analysis:view|create|review`.
class CreditAnalysisPage extends StatefulWidget {
  const CreditAnalysisPage({super.key});

  @override
  State<CreditAnalysisPage> createState() => _CreditAnalysisPageState();
}

class _CreditAnalysisPageState extends State<CreditAnalysisPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 88;
  static const double _kSectionGap = 12;

  /// Rota central (fiação em `app_routes.dart`).
  static const String _settingsRoute = '/credit-analysis/settings';

  static const _tabs = [
    CreditAnalysisTab.all,
    CreditAnalysisTab.approved,
    CreditAnalysisTab.review,
    CreditAnalysisTab.rejected,
  ];

  CreditAnalysisTab _activeTab = CreditAnalysisTab.all;

  List<CreditAnalysis> _analyses = const [];
  bool _loading = true;
  String? _error;

  CreditAnalysisStatistics _stats = CreditAnalysisStatistics.zero;
  bool _statsLoading = true;

  String? _redoingId;

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _appliedSearch = '';
  bool _searchFocused = false;

  bool get _canView =>
      ModuleAccessService.instance.hasCompanyModule('credit_and_collection') &&
      ModuleAccessService.instance.hasPermission('credit_analysis:view');
  bool get _canCreate =>
      ModuleAccessService.instance.hasPermission('credit_analysis:create');
  bool get _canReview =>
      ModuleAccessService.instance.hasPermission('credit_analysis:review');

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ─── Cores ───────────────────────────────────────────────────────────────

  Color _accentColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
  }

  Color _tabColor(BuildContext context, CreditAnalysisTab tab) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (tab) {
      case CreditAnalysisTab.all:
        return _accentColor(context);
      case CreditAnalysisTab.approved:
        return isDark
            ? AppColors.status.successDarkMode
            : AppColors.status.success;
      case CreditAnalysisTab.review:
        return isDark
            ? AppColors.status.warningDarkMode
            : AppColors.status.warning;
      case CreditAnalysisTab.rejected:
        return isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    }
  }

  // ─── Dados ───────────────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    await Future.wait([_loadStats(), _loadAnalyses()]);
  }

  Future<void> _loadStats() async {
    setState(() => _statsLoading = true);
    final res = await CreditAnalysisService.instance.getStatistics();
    if (!mounted) return;
    setState(() {
      _statsLoading = false;
      if (res.success && res.data != null) _stats = res.data!;
    });
  }

  Future<void> _loadAnalyses() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await CreditAnalysisService.instance.getAnalyses();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _analyses = res.data!;
        _error = null;
      } else {
        _error = res.message ?? 'Erro ao carregar análises de crédito';
      }
    });
  }

  /// Filtro da aba + busca (CPF/nome) aplicado no cliente — a lista é enxuta
  /// e o web também não pagina.
  List<CreditAnalysis> get _visible {
    Iterable<CreditAnalysis> list = _analyses;
    switch (_activeTab) {
      case CreditAnalysisTab.all:
        break;
      case CreditAnalysisTab.approved:
        list = list.where((a) =>
            a.status == CreditAnalysisStatus.approved ||
            (a.status == CreditAnalysisStatus.completed &&
                a.recommendation == CreditRecommendation.approve));
        break;
      case CreditAnalysisTab.review:
        list = list.where((a) =>
            a.status == CreditAnalysisStatus.manualReview ||
            (a.status == CreditAnalysisStatus.completed &&
                a.recommendation == CreditRecommendation.manualReview));
        break;
      case CreditAnalysisTab.rejected:
        list = list.where((a) =>
            a.status == CreditAnalysisStatus.rejected ||
            (a.status == CreditAnalysisStatus.completed &&
                a.recommendation == CreditRecommendation.reject));
        break;
    }
    final q = _appliedSearch.trim().toLowerCase();
    if (q.isNotEmpty) {
      final digits = q.replaceAll(RegExp(r'[^0-9]'), '');
      list = list.where((a) {
        final byName = (a.analyzedName ?? '').toLowerCase().contains(q);
        final byCpf = digits.isNotEmpty && a.analyzedCpf.contains(digits);
        return byName || byCpf;
      });
    }
    return list.toList();
  }

  int _tabCount(CreditAnalysisTab tab) {
    switch (tab) {
      case CreditAnalysisTab.all:
        return _stats.total;
      case CreditAnalysisTab.approved:
        return _stats.approved;
      case CreditAnalysisTab.review:
        return _stats.manualReview;
      case CreditAnalysisTab.rejected:
        return _stats.rejected;
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final v = value.trim();
      if (v == _appliedSearch) return;
      setState(() => _appliedSearch = v);
    });
  }

  // ─── Ações ───────────────────────────────────────────────────────────────

  Future<void> _redoAnalysis(CreditAnalysis analysis) async {
    if (_redoingId != null) return;
    setState(() => _redoingId = analysis.id);
    final res = await CreditAnalysisService.instance.createAnalysis(
      analyzedCpf: analysis.analyzedCpf,
      analyzedName: analysis.analyzedName,
    );
    if (!mounted) return;
    setState(() => _redoingId = null);
    if (res.success && res.data != null) {
      if (res.data!.status.isError) {
        AppToast.error(
          context,
          res.data!.errorMessage ??
              'Não foi possível consultar o crédito. Tente novamente.',
        );
      } else {
        AppToast.success(context, 'Nova análise de crédito concluída!');
      }
      _loadAll();
    } else {
      AppToast.error(context, res.message ?? 'Erro ao refazer análise');
    }
  }

  Future<void> _openDetail(CreditAnalysis analysis) async {
    // Busca o parecer fresco (paridade com o web, que refaz o GET por id).
    CreditAnalysis current = analysis;
    final res = await CreditAnalysisService.instance.getById(analysis.id);
    if (res.success && res.data != null) current = res.data!;
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => _AnalysisDetailSheet(analysis: current),
    );
  }

  Future<void> _openNewAnalysisSheet() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => const _NewAnalysisSheet(),
    );
    if (created == true && mounted) _loadAll();
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canView) {
      return const AppScaffold(
        title: 'Análise de Crédito',
        showBottomNavigation: false,
        body: _DeniedView(),
      );
    }
    return AppScaffold(
      title: 'Análise de Crédito',
      showBottomNavigation: false,
      actions: [
        if (_canReview)
          IconButton(
            tooltip: 'Regras de análise de crédito',
            icon: const Icon(LucideIcons.settings2, size: 20),
            onPressed: () =>
                Navigator.of(context).pushNamed(_settingsRoute),
          ),
      ],
      body: RefreshIndicator(
        color: _accentColor(context),
        onRefresh: _loadAll,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        _kPagePadH, _kPagePadTop, _kPagePadH, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHero(context),
                        const SizedBox(height: _kSectionGap),
                        _buildSearchField(context),
                        if (_canCreate) ...[
                          const SizedBox(height: _kSectionGap),
                          _buildNewAnalysisCta(context),
                        ],
                        const SizedBox(height: _kSectionGap),
                      ],
                    ),
                  ),
                  _buildTabsRail(context),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        _kPagePadH, _kSectionGap, _kPagePadH, _kPagePadBottom),
                    child: _buildActivePanel(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Hero: o score como protagonista ─────────────────────────────────────
  //
  // Meio-gauge do score médio (0–1000) à esquerda, com o tom da faixa de
  // risco; título e leitura contextual à direita; embaixo, medidor da taxa
  // de aprovação com legenda de pareceres. Sem eyebrow com dot nem fileira
  // de KPIs sublinhados.

  /// Tom semântico da faixa de score: ≥700 saudável, ≥400 atenção, <400 risco.
  Color _scoreTone(BuildContext context, double score) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (score >= 700) {
      return isDark ? AppColors.status.successDarkMode : AppColors.status.success;
    }
    if (score >= 400) {
      return isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    }
    return isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
  }

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    final total = _stats.total;
    final hasReview = _stats.manualReview > 0;
    final subtitle = total == 0
        ? 'Consulte o crédito de inquilinos antes de fechar a locação.'
        : hasReview
            ? '${total == 1 ? '1 análise' : '$total análises'} na carteira · '
                '${_stats.manualReview} aguardando revisão manual.'
            : '${total == 1 ? '1 análise' : '$total análises'} na carteira · '
                'nenhum parecer pendente de revisão.';

    final hasScore = !_statsLoading && _stats.averageScore > 0;
    final score = _stats.averageScore.clamp(0, 1000).toDouble();

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ScoreGauge(
                score: hasScore ? score : null,
                tone: hasScore
                    ? _scoreTone(context, score)
                    : ThemeHelpers.textSecondaryColor(context),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Análise de crédito',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -0.5,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildApprovalMeter(context),
        ],
      ),
    );
  }

  /// Medidor da taxa de aprovação + legenda dos pareceres.
  Widget _buildApprovalMeter(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final emerald =
        isDark ? AppColors.status.successDarkMode : AppColors.status.success;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;

    final frac =
        _statsLoading ? 0.0 : _stats.approvalRate.clamp(0.0, 1.0).toDouble();
    final rate = (_stats.approvalRate * 100).clamp(0, 100).toDouble();
    final rateLabel =
        (rate % 1 == 0 ? rate.toStringAsFixed(0) : rate.toStringAsFixed(1))
            .replaceAll('.', ',');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'TAXA DE APROVAÇÃO',
              style: theme.textTheme.labelSmall?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
                fontSize: 9.5,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: SizedBox(
                  height: 6,
                  child: LayoutBuilder(
                    builder: (context, c) => Stack(
                      children: [
                        Container(
                          color: ThemeHelpers.borderColor(context)
                              .withValues(alpha: 0.4),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOutCubic,
                          width: c.maxWidth * frac,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(99),
                            gradient: LinearGradient(
                              colors: [
                                emerald.withValues(alpha: 0.7),
                                emerald,
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _statsLoading ? '—' : '$rateLabel%',
              style: theme.textTheme.labelSmall?.copyWith(
                color: emerald,
                fontWeight: FontWeight.w900,
                fontSize: 12,
                letterSpacing: -0.2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            _verdictReading(
              context,
              emerald,
              _statsLoading
                  ? '— aprovadas'
                  : '${_stats.approved} aprovada${_stats.approved == 1 ? '' : 's'}',
            ),
            _verdictReading(
              context,
              amber,
              _statsLoading
                  ? '— em revisão'
                  : '${_stats.manualReview} em revisão',
            ),
            _verdictReading(
              context,
              danger,
              _statsLoading
                  ? '— recusadas'
                  : '${_stats.rejected} recusada${_stats.rejected == 1 ? '' : 's'}',
            ),
          ],
        ),
      ],
    );
  }

  Widget _verdictReading(BuildContext context, Color tone, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: tone),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: ThemeHelpers.textSecondaryColor(context),
            height: 1.0,
          ),
        ),
      ],
    );
  }

  // ─── Busca flush ─────────────────────────────────────────────────────────

  Widget _buildSearchField(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _accentColor(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final cardColor = ThemeHelpers.cardBackgroundColor(context);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final hasText = _searchController.text.isNotEmpty;
    final showAccent = _searchFocused || hasText;

    return Focus(
      onFocusChange: (f) => setState(() => _searchFocused = f),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        height: 50,
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: showAccent
                ? accent.withValues(alpha: isDark ? 0.5 : 0.42)
                : borderColor,
            width: showAccent ? 1.4 : 1,
          ),
          boxShadow: showAccent
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: isDark ? 0.18 : 0.12),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                    spreadRadius: -4,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            Icon(LucideIcons.search,
                size: 18, color: showAccent ? accent : secondary),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                cursorColor: accent,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
                decoration: InputDecoration(
                  hintText: 'Buscar por CPF ou nome…',
                  hintStyle: TextStyle(
                    color: secondary.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w500,
                    fontSize: 13.5,
                  ),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
                onChanged: (v) {
                  _onSearchChanged(v);
                  setState(() {});
                },
              ),
            ),
            if (hasText)
              InkResponse(
                radius: 18,
                onTap: () {
                  _searchController.clear();
                  _onSearchChanged('');
                  setState(() {});
                },
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(LucideIcons.x, size: 15, color: secondary),
                ),
              ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  /// CTA primário — vermelho da marca (mesma régua do "Novo imóvel").
  Widget _buildNewAnalysisCta(BuildContext context) {
    final accent = _accentColor(context);
    return SizedBox(
      height: 48,
      child: FilledButton.icon(
        onPressed: _openNewAnalysisSheet,
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14.5,
            letterSpacing: -0.1,
          ),
        ),
        icon: const Icon(LucideIcons.scanSearch, size: 18),
        label: const Text('Nova análise de crédito'),
      ),
    );
  }

  // ─── Abas flush ──────────────────────────────────────────────────────────

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
          for (final tab in _tabs)
            Expanded(
              child: _FlushTab(
                icon: _tabIcon(tab),
                label: _tabLabel(tab),
                count: _tabCount(tab),
                tone: _tabColor(context, tab),
                selected: _activeTab == tab,
                onTap: () => setState(() => _activeTab = tab),
              ),
            ),
        ],
      ),
    );
  }

  IconData _tabIcon(CreditAnalysisTab tab) {
    switch (tab) {
      case CreditAnalysisTab.all:
        return LucideIcons.listChecks;
      case CreditAnalysisTab.approved:
        return LucideIcons.shieldCheck;
      case CreditAnalysisTab.review:
        return LucideIcons.shieldQuestionMark;
      case CreditAnalysisTab.rejected:
        return LucideIcons.shieldX;
    }
  }

  String _tabLabel(CreditAnalysisTab tab) {
    switch (tab) {
      case CreditAnalysisTab.all:
        return 'Todas';
      case CreditAnalysisTab.approved:
        return 'Aprovadas';
      case CreditAnalysisTab.review:
        return 'Revisão';
      case CreditAnalysisTab.rejected:
        return 'Reprovadas';
    }
  }

  // ─── Painel ativo ────────────────────────────────────────────────────────

  ({IconData icon, String eyebrow, String title, String hint}) _panelMeta(
      CreditAnalysisTab tab) {
    switch (tab) {
      case CreditAnalysisTab.all:
        return (
          icon: LucideIcons.listChecks,
          eyebrow: 'TODAS',
          title: 'Histórico de análises',
          hint: 'Todos os pareceres já consultados, do mais recente ao mais antigo.',
        );
      case CreditAnalysisTab.approved:
        return (
          icon: LucideIcons.shieldCheck,
          eyebrow: 'APROVADAS',
          title: 'Crédito aprovado',
          hint: 'Inquilinos com parecer positivo — prontos para avançar.',
        );
      case CreditAnalysisTab.review:
        return (
          icon: LucideIcons.shieldQuestionMark,
          eyebrow: 'REVISÃO MANUAL',
          title: 'Aguardando revisão',
          hint: 'Pareceres na zona cinzenta — decida caso a caso no painel.',
        );
      case CreditAnalysisTab.rejected:
        return (
          icon: LucideIcons.shieldX,
          eyebrow: 'REPROVADAS',
          title: 'Crédito reprovado',
          hint: 'Consultas com parecer negativo — restrições ou score baixo.',
        );
    }
  }

  Widget _buildActivePanel(BuildContext context) {
    Widget child;
    final items = _visible;
    if (_loading && _analyses.isEmpty) {
      child = _buildSkeleton();
    } else if (_error != null && _analyses.isEmpty) {
      child = _buildError(context, _error!);
    } else if (items.isEmpty) {
      child = _buildEmpty(context, _activeTab);
    } else {
      child = _buildList(context, items);
    }

    return Column(
      key: ValueKey('panel-${_activeTab.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPanelHeader(context, _activeTab),
        const SizedBox(height: 14),
        child,
      ],
    ).animate(key: ValueKey('panel-${_activeTab.name}')).fadeIn(
          duration: 240.ms,
        );
  }

  Widget _buildPanelHeader(BuildContext context, CreditAnalysisTab tab) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = _tabColor(context, tab);
    final meta = _panelMeta(tab);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: tone.withValues(alpha: isDark ? 0.2 : 0.12),
          ),
          child: Icon(meta.icon, color: tone, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: tone,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: tone.withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    meta.eyebrow,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: tone,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                meta.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                meta.hint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  height: 1.32,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildList(BuildContext context, List<CreditAnalysis> items) {
    var animIndex = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final a in items)
          CreditAnalysisCard(
            analysis: a,
            redoing: _redoingId == a.id,
            onTap: () => _openDetail(a),
            onRedo: _canCreate ? () => _confirmRedo(a) : null,
          ).animate(key: ValueKey('ca-${a.id}')).fadeIn(
                delay: Duration(milliseconds: 30 * (animIndex++).clamp(0, 12)),
                duration: 220.ms,
              ),
      ],
    );
  }

  Future<void> _confirmRedo(CreditAnalysis a) async {
    if (!a.canRedo) {
      AppToast.info(
        context,
        'É possível refazer a análise após 15 dias da última.',
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Refazer análise?'),
        content: Text(
          'Uma nova consulta de crédito será feita para o CPF '
          '${Masks.cpf(a.analyzedCpf)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Refazer'),
          ),
        ],
      ),
    );
    if (ok == true) _redoAnalysis(a);
  }

  // ─── Estados ─────────────────────────────────────────────────────────────

  Widget _buildSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(
        5,
        (_) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 44, height: 44, borderRadius: 13),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonText(width: 120, height: 16, borderRadius: 999),
                    SizedBox(height: 9),
                    SkeletonText(width: double.infinity, height: 14),
                    SizedBox(height: 6),
                    SkeletonText(width: 140, height: 12),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const SkeletonText(width: 48, height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, CreditAnalysisTab tab) {
    final theme = Theme.of(context);
    final tone = _tabColor(context, tab);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final hasSearch = _appliedSearch.trim().isNotEmpty;
    final (icon, title, body) = hasSearch
        ? (
            LucideIcons.searchX,
            'Nada encontrado',
            'Nenhuma análise corresponde a "${_appliedSearch.trim()}".',
          )
        : switch (tab) {
            CreditAnalysisTab.all => (
                LucideIcons.scanSearch,
                'Nenhuma análise ainda',
                _canCreate
                    ? 'Toque em "Nova análise de crédito" para consultar o primeiro CPF.'
                    : 'As análises de crédito da empresa aparecerão aqui.',
              ),
            CreditAnalysisTab.approved => (
                LucideIcons.shieldCheck,
                'Nenhuma aprovada',
                'Pareceres positivos aparecem aqui.',
              ),
            CreditAnalysisTab.review => (
                LucideIcons.partyPopper,
                'Nada para revisar',
                'Nenhum parecer aguardando revisão manual.',
              ),
            CreditAnalysisTab.rejected => (
                LucideIcons.shieldX,
                'Nenhuma reprovada',
                'Consultas com parecer negativo aparecem aqui.',
              ),
          };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 4),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [
                tone.withValues(alpha: 0.18),
                tone.withValues(alpha: 0.06),
              ]),
              border: Border.all(color: tone.withValues(alpha: 0.32)),
            ),
            child: Icon(icon, color: tone, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textColor(context),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, String message) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 4),
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
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _loadAll,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}

// ─── Aba flush (ícone + rótulo + contagem + sublinhado) ──────────────────────

// ─── Gauge do score (hero) ───────────────────────────────────────────────────

/// Meio-gauge do score médio (0–1000). `score == null` desenha só o trilho
/// com “—” no centro (carregando ou sem consultas).
class _ScoreGauge extends StatelessWidget {
  final double? score;
  final Color tone;

  const _ScoreGauge({required this.score, required this.tone});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final track = ThemeHelpers.borderColor(context).withValues(alpha: 0.45);
    final frac = score == null ? 0.0 : (score! / 1000).clamp(0.0, 1.0);

    return SizedBox(
      width: 116,
      height: 74,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: frac),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) => CustomPaint(
          painter: _ScoreGaugePainter(
            fraction: value,
            tone: tone,
            track: track,
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  score == null ? '—' : score!.round().toString(),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: tone,
                    letterSpacing: -0.8,
                    height: 1.0,
                    fontSize: 25,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'SCORE MÉDIO',
                  style: TextStyle(
                    fontSize: 7.5,
                    fontWeight: FontWeight.w900,
                    color: secondary,
                    letterSpacing: 1.3,
                    height: 1.0,
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

class _ScoreGaugePainter extends CustomPainter {
  final double fraction;
  final Color tone;
  final Color track;

  const _ScoreGaugePainter({
    required this.fraction,
    required this.tone,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 9.0;
    final center = Offset(size.width / 2, size.height - 2);
    final radius = size.width / 2 - stroke / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(rect, pi, pi, false, trackPaint);

    if (fraction > 0) {
      final valuePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: pi,
          endAngle: 2 * pi,
          colors: [tone.withValues(alpha: 0.55), tone],
        ).createShader(rect);
      canvas.drawArc(rect, pi, pi * fraction, false, valuePaint);
    }
  }

  @override
  bool shouldRepaint(_ScoreGaugePainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.tone != tone ||
      oldDelegate.track != track;
}

class _FlushTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color tone;
  final bool selected;
  final VoidCallback onTap;

  const _FlushTab({
    required this.icon,
    required this.label,
    required this.count,
    required this.tone,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected ? tone : ThemeHelpers.textSecondaryColor(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: tone.withValues(alpha: 0.12),
        highlightColor: tone.withValues(alpha: 0.06),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: fg),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      maxLines: 1,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: fg,
                        fontWeight:
                            selected ? FontWeight.w900 : FontWeight.w600,
                        letterSpacing: 0.1,
                      ),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: tone.withValues(alpha: selected ? 0.18 : 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          count > 99 ? '99+' : '$count',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: selected
                                ? tone
                                : ThemeHelpers.textSecondaryColor(context),
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              height: 2.5,
              decoration: BoxDecoration(
                color: selected ? tone : Colors.transparent,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(3)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Bottom sheet: detalhe do parecer ────────────────────────────────────────

class _AnalysisDetailSheet extends StatelessWidget {
  const _AnalysisDetailSheet({required this.analysis});
  final CreditAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = creditStatusColor(context, analysis.status);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final fmt = DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR');
    final scoreTone = analysis.hasGoodScore
        ? (isDark
            ? AppColors.status.successDarkMode
            : AppColors.status.success)
        : (isDark ? AppColors.status.errorDarkMode : AppColors.status.error);

    final name = (analysis.analyzedName ?? '').trim();

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: tone.withValues(alpha: isDark ? 0.22 : 0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.16),
            blurRadius: 28,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: secondary.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        color: tone.withValues(alpha: isDark ? 0.18 : 0.1),
                        border: Border.all(color: tone.withValues(alpha: 0.3)),
                      ),
                      child: Icon(LucideIcons.scanSearch, color: tone, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name.isNotEmpty
                                ? name
                                : Masks.cpf(analysis.analyzedCpf),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: ThemeHelpers.textColor(context),
                              letterSpacing: -0.3,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _miniPill(analysis.status.label, tone, isDark),
                              if (analysis.riskLevel != CreditRiskLevel.unknown)
                                _miniPill(
                                  'Risco ${analysis.riskLevel.label.toLowerCase()}',
                                  creditRiskColor(context, analysis.riskLevel),
                                  isDark,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // Mensagem de erro amigável (ex.: CPF não encontrado na Serasa).
                if (analysis.status.isError &&
                    (analysis.errorMessage ?? '').isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: (isDark
                              ? AppColors.status.warningDarkMode
                              : AppColors.status.warning)
                          .withValues(alpha: isDark ? 0.14 : 0.1),
                      border: Border.all(
                        color: (isDark
                                ? AppColors.status.warningDarkMode
                                : AppColors.status.warning)
                            .withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          LucideIcons.triangleAlert,
                          size: 16,
                          color: isDark
                              ? AppColors.status.warningDarkMode
                              : AppColors.status.warning,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            analysis.errorMessage!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: ThemeHelpers.textColor(context),
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                // Destaque: score + recomendação lado a lado.
                if (!analysis.status.isError) ...[
                  const SizedBox(height: 18),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _highlightBox(
                            context,
                            label: 'SCORE DE CRÉDITO',
                            tone: analysis.creditScore > 0
                                ? scoreTone
                                : secondary,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  analysis.creditScore > 0
                                      ? '${analysis.creditScore}'
                                      : '—',
                                  style:
                                      theme.textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: ThemeHelpers.textColor(context),
                                    letterSpacing: -0.6,
                                    height: 1.0,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Text(
                                    '/1000',
                                    style:
                                        theme.textTheme.labelSmall?.copyWith(
                                      color: secondary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _highlightBox(
                            context,
                            label: 'PARECER',
                            tone: creditRecommendationColor(
                                context, analysis.recommendation),
                            child: Text(
                              analysis.recommendation.label,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: ThemeHelpers.textColor(context),
                                letterSpacing: -0.2,
                                height: 1.1,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                _row(context, 'CPF consultado', Masks.cpf(analysis.analyzedCpf),
                    icon: LucideIcons.idCard),
                if (name.isNotEmpty)
                  _row(context, 'Nome', name, icon: LucideIcons.user),
                const _SheetDivider(),
                _boolRow(
                  context,
                  'Restrições',
                  analysis.hasRestrictions,
                  analysis.restrictionsCount,
                ),
                _row(context, 'Dívidas', _money.format(analysis.totalDebt)),
                _boolRow(
                  context,
                  'Protestos',
                  analysis.hasProtests,
                  analysis.protestsCount,
                ),
                _boolRow(
                  context,
                  'Ações judiciais',
                  analysis.hasLawsuits,
                  analysis.lawsuitsCount,
                ),
                if (analysis.rental != null) ...[
                  const _SheetDivider(),
                  _row(context, 'Aluguel vinculado', analysis.rental!.label,
                      icon: LucideIcons.house),
                ],
                const _SheetDivider(),
                if (analysis.createdAt != null)
                  _row(context, 'Consultada em',
                      fmt.format(analysis.createdAt!.toLocal())),
                if (analysis.reviewedAt != null)
                  _row(context, 'Revisada em',
                      fmt.format(analysis.reviewedAt!.toLocal())),
                if ((analysis.notes ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    'OBSERVAÇÕES',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    analysis.notes!.trim(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: ThemeHelpers.textColor(context),
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _highlightBox(
    BuildContext context, {
    required String label,
    required Color tone,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: tone.withValues(alpha: isDark ? 0.12 : 0.07),
        border: Border.all(color: tone.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: tone,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              fontSize: 9.5,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _miniPill(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: isDark ? 0.4 : 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontWeight: FontWeight.w800, fontSize: 11),
      ),
    );
  }

  /// Linha booleana com cor por significado: "Não" = verde (bom sinal),
  /// "Sim (n)" = vermelho (ponto de atenção).
  Widget _boolRow(
      BuildContext context, String label, bool value, int count) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final good =
        isDark ? AppColors.status.successDarkMode : AppColors.status.success;
    final bad =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Icon(
            value ? LucideIcons.circleX : LucideIcons.circleCheck,
            size: 14,
            color: value ? bad : good,
          ),
          const SizedBox(width: 5),
          Text(
            value ? 'Sim${count > 0 ? ' ($count)' : ''}' : 'Não',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: value ? bad : good,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value,
      {IconData? icon}) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: secondary),
            const SizedBox(width: 7),
          ],
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetDivider extends StatelessWidget {
  const _SheetDivider();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        height: 1,
        color: ThemeHelpers.borderLightColor(context),
      ),
    );
  }
}

// ─── Bottom sheet: nova análise ──────────────────────────────────────────────

class _NewAnalysisSheet extends StatefulWidget {
  const _NewAnalysisSheet();

  @override
  State<_NewAnalysisSheet> createState() => _NewAnalysisSheetState();
}

class _NewAnalysisSheetState extends State<_NewAnalysisSheet> {
  final _cpfController = TextEditingController();
  final _nameController = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _cpfController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Color get _accent => Theme.of(context).brightness == Brightness.dark
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;

  Future<void> _submit() async {
    final digits = _cpfController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 11) {
      AppToast.warning(context, 'Informe um CPF válido (11 dígitos).');
      return;
    }
    setState(() => _creating = true);
    final res = await CreditAnalysisService.instance.createAnalysis(
      analyzedCpf: digits,
      analyzedName: _nameController.text,
    );
    if (!mounted) return;
    setState(() => _creating = false);
    if (res.success && res.data != null) {
      if (res.data!.status.isError) {
        AppToast.error(
          context,
          res.data!.errorMessage ??
              'Não foi possível consultar o crédito. Tente novamente.',
        );
      } else {
        AppToast.success(context, 'Análise de crédito concluída!');
      }
      Navigator.of(context).pop(true);
    } else {
      AppToast.error(context, res.message ?? 'Erro ao criar análise');
    }
  }

  InputDecoration _decoration(String label, String hint) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final fill = isDark
        ? Colors.white.withValues(alpha: 0.045)
        : Colors.black.withValues(alpha: 0.025);
    OutlineInputBorder b(Color c, double w) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: w == 0 ? BorderSide.none : BorderSide(color: c, width: w),
        );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: fill,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      labelStyle:
          TextStyle(color: muted, fontWeight: FontWeight.w600, fontSize: 13.5),
      floatingLabelStyle: TextStyle(
          color: _accent, fontWeight: FontWeight.w700, fontSize: 13.5),
      hintStyle: TextStyle(
          color: muted.withValues(alpha: 0.7), fontWeight: FontWeight.w500),
      border: b(Colors.transparent, 0),
      enabledBorder: b(Colors.transparent, 0),
      focusedBorder: b(_accent, 1.6),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: _accent.withValues(alpha: isDark ? 0.22 : 0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.16),
            blurRadius: 28,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: secondary.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'NOVA ANÁLISE',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _accent,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Consultar crédito de inquilino',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'A consulta é feita na hora e o parecer entra no histórico.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _cpfController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    CpfInputFormatter(),
                  ],
                  cursorColor: _accent,
                  style: TextStyle(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                  decoration: _decoration('CPF *', '000.000.000-00'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  cursorColor: _accent,
                  style: TextStyle(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                  decoration: _decoration('Nome (opcional)', 'Nome completo'),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _creating ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                    icon: _creating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(LucideIcons.scanSearch, size: 18),
                    label: Text(_creating ? 'Analisando…' : 'Analisar crédito'),
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

// ─── Sem permissão ───────────────────────────────────────────────────────────

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
              'Você não tem acesso à análise de crédito.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Solicite ao administrador a permissão de visualizar análises de crédito.',
              textAlign: TextAlign.center,
              style: TextStyle(color: secondary, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
