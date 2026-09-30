import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/notifications/app_toast.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/profile_service.dart';
import '../../../shared/utils/avatar_url_resolver.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/minimal_body_chrome.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../../notifications/widgets/notification_center.dart';
import '../models/dashboard_overview_model.dart';
import '../services/dashboard_overview_service.dart';
import 'company_overview_details_sheet.dart';
import 'company_overview_style.dart';
import 'dashboard_filters_drawer.dart';

/// Home executiva de admin/master — a visão da EMPRESA.
///
/// 29/09/2026 (dash-01): paridade com o `DashboardPage` do web
/// (`RoleBasedDashboard` entrega esta tela a admin e master). Antes o app
/// chamava sempre `GET /dashboard/user`, e o dono via os números pessoais
/// dele como se fossem os da empresa.
///
/// Fonte única: `GET /dashboard/overview` com o recorte do topo (período,
/// empresa, corretor, comparação) — nenhum bloco consulta outro endpoint,
/// então todos os números da tela vêm do mesmo recorte. Faixas flush,
/// separadas por fio, na ordem do web:
///   1. topo: quem lê, o recorte em tela e a hora do dado;
///   2. abertura: VGV | curva de 6 meses | meta do mês;
///   3. quatro indicadores (leads, conversão, agendamentos, fichas);
///   4. funil do período;
///   5. top corretores (toque filtra a tela inteira por ele);
///   6. panorama: origem dos leads, agenda e pendências;
///   7. atividades recentes (recolhível, fechada).
/// Cada "Ver detalhes" abre o detalhe do KPI com o mesmo payload.
class CompanyOverviewDashboard extends StatefulWidget {
  const CompanyOverviewDashboard({super.key, this.isOwner = false});

  /// Dono da conta: o topo diz "visão completa" (admin: "visão executiva").
  final bool isOwner;

  @override
  State<CompanyOverviewDashboard> createState() =>
      _CompanyOverviewDashboardState();
}

class _CompanyOverviewDashboardState extends State<CompanyOverviewDashboard>
    with WidgetsBindingObserver {
  static const double _kPadH = 16;

  /// O web recarrega em segundo plano a cada 2 min e ao voltar para a aba
  /// quando o dado tem mais de 1 min.
  static const Duration _kAutoRefresh = Duration(minutes: 2);
  static const Duration _kStaleOnResume = Duration(seconds: 60);

  DashboardFilters _filters = DashboardFilters.executiveDefaults();
  DashboardOverview? _data;
  bool _loading = true;

  /// A última atualização falhou e a tela mostra o dado anterior.
  bool _stale = false;
  String? _error;
  int _errorStatus = 0;
  DateTime? _loadedAt;
  int _requestSeq = 0;
  Timer? _autoRefresh;

  List<DashboardScopeOption> _companies = const [];
  String? _userName;
  String? _userEmail;
  String? _userAvatar;

  bool _activitiesOpen = false;

  /// Ponto tocado na curva de 6 meses (nulo = leitura do último mês).
  int? _curveIndex;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    unawaited(_loadCompanies());
    unawaited(_loadProfile());
    _autoRefresh = Timer.periodic(_kAutoRefresh, (_) {
      if (mounted) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final at = _loadedAt;
    if (at != null && DateTime.now().difference(at) > _kStaleOnResume) {
      _load(silent: true);
    }
  }

  // ─── Dados ─────────────────────────────────────────────────────────────────

  /// Busca o overview do recorte atual.
  ///
  /// 29/09/2026 (dash-01): mesmo ciclo do `useDashboard` do web — dado do
  /// mesmo recorte com menos de 90 s vem do cache (voltar para a Home pelo
  /// menu não refaz a consulta); `force` ("Atualizar", puxar para baixo,
  /// "Tentar novamente") descarta o cache antes, como o `refresh` do web.
  /// `silent` é o recarregamento em segundo plano: não esmaece a tela e, se
  /// falhar, mantém o último dado com o carimbo "Último dado".
  Future<void> _load({bool silent = false, bool force = false}) async {
    final seq = ++_requestSeq;
    final service = DashboardOverviewService.instance;
    if (!silent) {
      setState(() {
        _loading = true;
        if (_data == null) _error = null;
      });
    }
    if (force) {
      await service.invalidate(_filters);
    } else {
      final hit = await service.cachedEntry(_filters);
      if (!mounted || seq != _requestSeq) return;
      if (hit != null) {
        setState(() {
          _loading = false;
          _data = hit.data;
          _stale = false;
          _error = null;
          _errorStatus = 0;
          _loadedAt = hit.at;
          _curveIndex = null;
        });
        return;
      }
    }
    if (!mounted || seq != _requestSeq) return;
    final res = await service.getOverview(_filters);
    // Resposta de um recorte antigo (a pessoa trocou o filtro no meio) não
    // sobrescreve a do recorte atual.
    if (!mounted || seq != _requestSeq) return;
    final ok = res.success && res.data != null;
    setState(() {
      _loading = false;
      if (ok) {
        _data = res.data;
        _stale = false;
        _error = null;
        _errorStatus = 0;
        _loadedAt = DateTime.now();
        _curveIndex = null;
      } else if (_data != null) {
        _stale = true;
        _error = res.message;
        _errorStatus = res.statusCode;
      } else {
        _error = res.message ?? 'Erro ao carregar o painel da empresa';
        _errorStatus = res.statusCode;
      }
    });
    if (!ok && !silent && _data != null && mounted) {
      AppToast.warning(
        context,
        'O painel não foi atualizado',
        subtitle: res.message ?? 'Mostrando o último dado carregado.',
      );
    }
  }

  Future<void> _refresh() => _load(force: true);

  /// Empresas do seletor "Empresa" — mesma lista (sem repetição, em ordem
  /// alfabética) que o serviço monta a partir do `GET /companies`.
  Future<void> _loadCompanies() async {
    final list = await DashboardOverviewService.instance.getCompanyOptions();
    if (!mounted) return;
    setState(() => _companies = list);
  }

  Future<void> _loadProfile() async {
    final res = await ProfileService.instance.getProfile();
    if (!mounted || !res.success || res.data == null) return;
    final p = res.data!;
    setState(() {
      _userName = p.name;
      _userEmail = p.email;
      _userAvatar = p.avatar;
    });
  }

  // ─── Recorte ───────────────────────────────────────────────────────────────

  List<DashboardScopeOption> get _members =>
      (_data?.availableUsers ?? const <OverviewUserOption>[])
          .map((u) => DashboardScopeOption(id: u.id, name: u.name))
          .toList(growable: false);

  /// "Este mês" é o período padrão: não conta como filtro ativo nem vira
  /// ficha na fita (o `isDefaultPeriod` do web).
  bool get _isDefaultPeriod => _filters.isCurrentMonthPeriod;

  int get _activeCount {
    var n = 0;
    if (!_isDefaultPeriod) n++;
    if (_filters.teamMember != null) n++;
    if (_filters.isComparing) n++;
    n += _filters.companyIds.length;
    return n;
  }

  void _applyFilters(DashboardFilters next) {
    setState(() => _filters = next);
    _load();
  }

  void _openFilters() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (ctx) => DashboardFiltersDrawer(
        initialFilters: _filters,
        executive: true,
        companies: _companies,
        members: _members,
        onFiltersChanged: _applyFilters,
      ),
    );
  }

  /// Toque no ranking: filtra a tela inteira pelo corretor (toque de novo
  /// no mesmo remove o filtro) — o `onSelectMember` do web.
  void _toggleMember(String userId) {
    _applyFilters(
      _filters.teamMember == userId
          ? _filters.copyWith(clearTeamMember: true)
          : _filters.copyWith(teamMember: userId),
    );
  }

  void _openDetails(OverviewDetailKind kind) {
    final d = _data;
    if (d == null) return;
    showOverviewDetails(context, kind: kind, data: d);
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Intellisys',
      currentBottomNavIndex: 0,
      userName: _userName,
      userEmail: _userEmail,
      userAvatar: _userAvatar,
      actions: [
        const NotificationCenter(compactToolbar: true),
        _BadgedAction(
          count: _activeCount,
          child: ChromeToolbarIconButton(
            icon: Icons.tune_rounded,
            tooltip: 'Filtros',
            onPressed: _openFilters,
          ),
        ),
      ],
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final data = _data;
    if (data == null) {
      if (_loading) return _buildSkeleton(context);
      return AppErrorState.fromApi(
        message: _error,
        statusCode: _errorStatus,
        onRetry: _refresh,
      );
    }
    Widget pad(Widget child, {double top = 18, double bottom = 18}) => Padding(
          padding: EdgeInsets.fromLTRB(_kPadH, top, _kPadH, bottom),
          child: child,
        );
    final rule = Container(height: 1, color: OverviewTones.rule(context));

    return RefreshIndicator(
      color: OverviewTones.brand(context),
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          pad(_buildMasthead(context, data), top: 10, bottom: 14),
          // Recarregando com dado em tela: a página esmaece (o `$busy` do
          // web) em vez de trocar tudo por esqueleto.
          AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: _loading ? 0.5 : 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                rule,
                pad(_buildOpening(context, data)),
                rule,
                pad(_buildKpis(context, data), top: 14, bottom: 14),
                rule,
                pad(_buildFunnel(context, data)),
                rule,
                pad(_buildRanking(context, data)),
                rule,
                pad(_buildPanorama(context, data)),
                rule,
                pad(_buildActivities(context, data), top: 6, bottom: 6),
                rule,
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── 1. Topo ───────────────────────────────────────────────────────────────

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Bom dia';
    if (h < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  String _todayStamp() {
    final now = DateTime.now();
    String clean(String s) => s.replaceAll('.', '');
    final wd = clean(DateFormat('EEE', 'pt_BR').format(now));
    final mon = clean(DateFormat('MMM', 'pt_BR').format(now));
    return '$wd · ${now.day} $mon ${now.year}';
  }

  String? _memberName(DashboardOverview data) {
    final id = _filters.teamMember;
    if (id == null) return null;
    for (final u in data.availableUsers) {
      if (u.id == id) return u.name;
    }
    return 'Corretor selecionado';
  }

  String _companyLabel() {
    if (_filters.companyIds.isEmpty) return 'Empresa atual';
    final id = _filters.companyIds.first;
    for (final c in _companies) {
      if (c.id == id) return c.name;
    }
    return 'Empresa selecionada';
  }

  Widget _buildMasthead(BuildContext context, DashboardOverview data) {
    final theme = Theme.of(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final brand = OverviewTones.brand(context);
    final firstName = (_userName ?? '').trim().split(RegExp(r'\s+')).first;
    final visao = widget.isOwner
        ? 'Visão completa do negócio'
        : 'Visão executiva do negócio';

    final stampTime = data.generatedAt ?? _loadedAt;
    final stamp = stampTime == null
        ? null
        : DateFormat('HH:mm', 'pt_BR').format(stampTime);

    final scopeWords = <String>[
      if (_companies.length > 1) _companyLabel(),
      _memberName(data) ?? 'toda a equipe',
      _filters.isComparing
          ? ovCompareLabel(_filters.compareWith).replaceFirst('vs. ', '')
          : 'sem comparação',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: brand),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                '${_todayStamp()} · $visao',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: secondary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${_greeting()}, ',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextSpan(
                text: firstName.isEmpty ? 'por aqui' : firstName,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                ),
              ),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _PeriodButton(
                word: ovPeriodWord(_filters),
                period: ovPeriodLabel(_filters),
                onTap: _openFilters,
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Atualizar',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _loading ? null : _refresh,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: ThemeHelpers.borderColor(context),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: _loading
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: secondary,
                            ),
                          )
                        : Icon(LucideIcons.refreshCw, size: 17, color: textColor),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // "Mostrando …" — as palavras do recorte, todas abrem os filtros.
        InkWell(
          onTap: _openFilters,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Mostrando ',
                          style: TextStyle(
                            color: secondary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        for (var i = 0; i < scopeWords.length; i++) ...[
                          if (i > 0)
                            TextSpan(
                              text: ' · ',
                              style: TextStyle(color: secondary),
                            ),
                          TextSpan(
                            text: scopeWords[i],
                            style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.w800,
                              decoration: TextDecoration.underline,
                              decorationColor:
                                  textColor.withValues(alpha: 0.3),
                            ),
                          ),
                        ],
                      ],
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
                  ),
                ),
                if (stamp != null || _stale) ...[
                  const SizedBox(width: 10),
                  _Stamp(
                    stale: _stale,
                    time: stamp,
                  ),
                ],
              ],
            ),
          ),
        ),
        ..._buildActiveChips(context, data),
      ],
    );
  }

  /// Fita dos filtros ativos (o `Fita` do web): cada ficha remove o seu.
  List<Widget> _buildActiveChips(BuildContext context, DashboardOverview data) {
    final chips = <({String label, String value, VoidCallback onRemove})>[];
    if (!_isDefaultPeriod) {
      chips.add((
        label: 'Período',
        value: ovPeriodLabel(_filters),
        onRemove: () {
          final d = DashboardFilters.executiveDefaults();
          _applyFilters(
            _filters.copyWith(
              dateRange: d.dateRange,
              startDate: d.startDate,
              endDate: d.endDate,
            ),
          );
        },
      ));
    }
    final member = _memberName(data);
    if (member != null) {
      chips.add((
        label: 'Corretor',
        value: member,
        onRemove: () => _applyFilters(_filters.copyWith(clearTeamMember: true)),
      ));
    }
    if (_filters.isComparing) {
      chips.add((
        label: 'Comparando com',
        value: ovCompareLabel(_filters.compareWith).replaceFirst('vs. ', ''),
        onRemove: () => _applyFilters(_filters.copyWith(compareWith: 'none')),
      ));
    }
    for (final id in _filters.companyIds) {
      var name = 'Empresa selecionada';
      for (final c in _companies) {
        if (c.id == id) name = c.name;
      }
      chips.add((
        label: 'Empresa',
        value: name,
        onRemove: () => _applyFilters(
          _filters.copyWith(
            companyIds: _filters.companyIds.where((x) => x != id).toList(),
          ),
        ),
      ));
    }
    if (chips.isEmpty) return const [];

    final theme = Theme.of(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return [
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final c in chips)
            InkWell(
              onTap: c.onRemove,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 300),
                padding: const EdgeInsets.fromLTRB(11, 6, 8, 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: ThemeHelpers.borderColor(context)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${c.label} ',
                              style: TextStyle(color: secondary),
                            ),
                            TextSpan(
                              text: c.value,
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.close_rounded, size: 14, color: secondary),
                  ],
                ),
              ),
            ),
          if (chips.length > 1)
            TextButton(
              onPressed: () =>
                  _applyFilters(DashboardFilters.executiveDefaults()),
              style: TextButton.styleFrom(
                foregroundColor: secondary,
                visualDensity: VisualDensity.compact,
              ),
              child: const Text(
                'Limpar tudo',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
    ];
  }

  // ─── 2. Abertura: VGV | curva | meta ───────────────────────────────────────

  Widget _buildOpening(BuildContext context, DashboardOverview data) {
    final theme = Theme.of(context);
    final s = data.statistics;
    final g = data.monthlyGoal;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final brand = OverviewTones.brand(context);
    final compareOn = _filters.isComparing;
    final dias = ovDaysInRange(_filters);
    final cmpValues = data.salesChart.comparisonValues;
    final cmpTotal = cmpValues.isEmpty
        ? null
        : cmpValues.fold<double>(0, (a, b) => a + b);

    // Série da curva: os 6 últimos pontos, como no web.
    final labels = data.salesChart.labels;
    final values = data.salesChart.values;
    final take = math.min(labels.length, values.length);
    final start = take > 6 ? take - 6 : 0;
    final curveLabels = <String>[
      for (var i = start; i < take; i++) ovShortMonth(labels[i]),
    ];
    final curveValues = <double>[
      for (var i = start; i < take; i++) values[i],
    ];

    // Leitura da curva: o ponto tocado ou o último, com a variação contra o
    // ponto anterior.
    final readIndex = curveValues.isEmpty
        ? null
        : (_curveIndex != null && _curveIndex! < curveValues.length
            ? _curveIndex!
            : curveValues.length - 1);
    double? readDelta;
    if (readIndex != null && readIndex > 0) {
      final prev = curveValues[readIndex - 1];
      if (prev > 0) readDelta = (curveValues[readIndex] - prev) / prev * 100;
    }

    final vgv = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: OverviewEyebrow('VGV do período', tone: brand)),
            OverviewLink(
              label: 'Ver detalhes',
              onTap: () => _openDetails(OverviewDetailKind.sales),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  ovMoneyShort(s.totalSales),
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: textColor,
                    letterSpacing: -1.2,
                    height: 1.0,
                  ),
                ),
              ),
            ),
            if (compareOn) ...[
              const SizedBox(width: 10),
              OverviewDeltaChip(value: s.salesGrowth),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: ovInt(s.salesCount),
                style: TextStyle(color: textColor, fontWeight: FontWeight.w900),
              ),
              TextSpan(
                text: s.salesCount == 1
                    ? ' ficha finalizada · '
                    : ' fichas finalizadas · ',
              ),
              TextSpan(text: ovPeriodLabel(_filters)),
              if (compareOn && cmpTotal != null) ...[
                const TextSpan(text: ' · '),
                TextSpan(
                  text: ovMoneyShort(cmpTotal),
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                TextSpan(text: ' ${ovCompareLabel(_filters.compareWith)}'),
              ],
            ],
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: secondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Reading(
                  label: 'Ticket médio',
                  value: s.salesCount > 0
                      ? ovMoneyShort(s.totalSales / s.salesCount)
                      : '—',
                ),
              ),
              _vRule(context),
              Expanded(
                child: _Reading(
                  label: 'Por dia',
                  value: dias > 0 ? ovMoneyShort(s.totalSales / dias) : '—',
                ),
              ),
              _vRule(context),
              Expanded(
                child: _Reading(
                  label: 'Conversão',
                  value: ovPct(s.realConversionRate),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final curve = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: OverviewEyebrow('Últimos 6 meses')),
            if (readIndex != null)
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '${curveLabels[readIndex]} '),
                            TextSpan(
                              text: ovMoneyShort(curveValues[readIndex]),
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: secondary,
                        ),
                      ),
                    ),
                    if (readDelta != null) ...[
                      const SizedBox(width: 6),
                      OverviewDeltaChip(value: readDelta, compact: true),
                    ],
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (curveValues.length > 1)
          _SalesCurve(
            labels: curveLabels,
            values: curveValues,
            target: g.hasTarget ? g.target : null,
            selected: _curveIndex,
            onSelect: (i) => setState(() {
              _curveIndex = (i == null || i == _curveIndex) ? null : i;
            }),
          )
        else
          const OverviewEmptyLine(
            icon: LucideIcons.chartNoAxesColumn,
            text: 'Sem histórico suficiente para o gráfico.',
          ),
        if (g.hasTarget && curveValues.length > 1) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                width: 14,
                height: 2,
                color: OverviewTones.amber(context),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Tracejado: meta do mês (${ovMoneyShort(g.target)}). Toque no gráfico para ler um mês.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: secondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        vgv,
        const SizedBox(height: 18),
        Container(height: 1, color: OverviewTones.rule(context)),
        const SizedBox(height: 16),
        curve,
        if (g.hasTarget) ...[
          const SizedBox(height: 18),
          Container(height: 1, color: OverviewTones.rule(context)),
          const SizedBox(height: 16),
          _buildGoal(context, g),
        ],
      ],
    );
  }

  Widget _vRule(BuildContext context) => Container(
        width: 1,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        color: OverviewTones.rule(context),
      );

  Widget _buildGoal(BuildContext context, OverviewMonthlyGoal g) {
    final rawProgress = g.progress;
    final progress = rawProgress.clamp(0.0, 100.0).toDouble();
    final remaining = g.remaining < 0 ? 0.0 : g.remaining;
    // Cor do anel = estado da meta: musgo batida, âmbar fora do ritmo, marca
    // no caminho normal (mesma regra do `HomeAbertura` do web).
    final ringColor = progress >= 100
        ? OverviewTones.green(context)
        : (!g.onTrack ? OverviewTones.amber(context) : OverviewTones.brand(context));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: OverviewEyebrow('Meta do mês')),
            OverviewLink(
              label: 'Detalhes',
              onTap: () => _openDetails(OverviewDetailKind.sales),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _GoalRing(
              progress: progress,
              label: ovPct(rawProgress, 0),
              color: ringColor,
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                children: [
                  _GoalLine(label: 'Atingido', value: ovMoneyShort(g.current)),
                  _GoalLine(label: 'Meta', value: ovMoneyShort(g.target)),
                  _GoalLine(
                    label: remaining > 0 ? 'Faltam' : 'Situação',
                    value: remaining > 0 ? ovMoneyShort(remaining) : 'Batida',
                    tone: remaining > 0
                        ? OverviewTones.amber(context)
                        : OverviewTones.green(context),
                  ),
                  _GoalLine(
                    label: 'Prazo',
                    value: '${ovInt(g.daysLeft)} ${g.daysLeft == 1 ? 'dia' : 'dias'}',
                    last: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─── 3. Indicadores ────────────────────────────────────────────────────────

  Widget _buildKpis(BuildContext context, DashboardOverview data) {
    final s = data.statistics;
    final ap = data.appointments;
    final comparing = _filters.isComparing;

    Widget tile(_Kpi k) => _KpiTile(kpi: k, comparing: comparing, onTap: () => _openDetails(k.kind));

    final leads = _Kpi(
      kind: OverviewDetailKind.leads,
      label: 'Leads',
      value: ovInt(s.totalLeads),
      delta: s.leadsGrowth,
      note: [(ovInt(data.leads.newToday), true), (' novos hoje', false)],
      icon: LucideIcons.users,
      tone: OverviewTones.sky(context),
    );
    final conversion = _Kpi(
      kind: OverviewDetailKind.conversion,
      label: 'Conversão',
      value: ovPct(s.realConversionRate),
      delta: s.conversionGrowth,
      note: [
        (ovInt(s.salesCount), true),
        (' fichas ÷ ', false),
        (ovInt(s.totalLeads), true),
        (' leads', false),
      ],
      icon: LucideIcons.percent,
      tone: OverviewTones.slate(context),
    );
    final appointments = _Kpi(
      kind: OverviewDetailKind.appointments,
      label: 'Agendamentos',
      value: ovInt(s.appointments),
      delta: s.appointmentsGrowth,
      note: [
        (ovInt(ap.completed), true),
        (' realizados · ', false),
        (ovInt(ap.scheduled), true),
        (' marcados', false),
      ],
      icon: LucideIcons.calendarCheck,
      tone: OverviewTones.amber(context),
    );
    final sales = _Kpi(
      kind: OverviewDetailKind.sales,
      label: 'Fichas finalizadas',
      value: ovInt(s.salesCount),
      delta: s.salesGrowth,
      note: const [('vendas concluídas no período', false)],
      icon: LucideIcons.fileCheck,
      tone: OverviewTones.green(context),
    );

    Widget pair(Widget a, Widget b) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: a),
              const SizedBox(width: 12),
              Expanded(child: b),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        pair(tile(leads), tile(conversion)),
        const SizedBox(height: 14),
        pair(tile(appointments), tile(sales)),
      ],
    );
  }

  // ─── 4. Funil ──────────────────────────────────────────────────────────────

  Widget _buildFunnel(BuildContext context, DashboardOverview data) {
    final s = data.statistics;
    final leads = s.totalLeads;
    double pct(int n) => leads > 0 ? n / leads * 100 : 0.0;
    // Largura desenhada ≠ percentual exibido: quem tem valor nunca some da
    // escada (piso de 2,5%), mas o número ao lado é o real.
    double width(double p, int v) => math.max(p, v > 0 ? 2.5 : 0.0);
    final stages = <_FunnelStage>[
      _FunnelStage(
        label: 'Leads',
        value: leads,
        pctOfTop: leads > 0 ? 100.0 : 0.0,
        width: width(leads > 0 ? 100.0 : 0.0, leads),
        tone: OverviewTones.sky(context),
      ),
      _FunnelStage(
        label: 'Agendamentos',
        value: s.appointments,
        pctOfTop: pct(s.appointments),
        width: width(pct(s.appointments), s.appointments),
        tone: OverviewTones.amber(context),
      ),
      _FunnelStage(
        label: 'Fichas finalizadas',
        value: s.salesCount,
        pctOfTop: pct(s.salesCount),
        width: width(pct(s.salesCount), s.salesCount),
        tone: OverviewTones.green(context),
      ),
    ];
    final hasFunnel = stages.any((st) => st.value > 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OverviewBandHeader(
          title: 'Funil do período',
          hint: 'leads → agendamentos → fichas finalizadas',
          tone: OverviewTones.sky(context),
          trailing: _ValueTag(text: '${ovPct(s.realConversionRate)} conversão'),
        ),
        const SizedBox(height: 14),
        if (hasFunnel)
          InkWell(
            onTap: () => _openDetails(OverviewDetailKind.funnel),
            borderRadius: BorderRadius.circular(10),
            child: Column(
              children: [
                for (var i = 0; i < stages.length; i++)
                  _FunnelStep(
                    stage: stages[i],
                    previousWidth: i > 0 ? stages[i - 1].width : null,
                  ),
              ],
            ),
          )
        else
          const OverviewEmptyLine(
            icon: LucideIcons.funnel,
            text: 'Sem movimento no período. Amplie o período ou remova filtros.',
          ),
      ],
    );
  }

  // ─── 5. Top corretores ─────────────────────────────────────────────────────

  Widget _buildRanking(BuildContext context, DashboardOverview data) {
    final rows = <_RankRow>[];
    var salesMode = true;
    if (data.performers.isNotEmpty) {
      final sorted = [...data.performers]..sort((a, b) => a.rank.compareTo(b.rank));
      final top = sorted.take(6).toList(growable: false);
      final best = top.isEmpty ? 0.0 : top.first.revenue;
      for (final p in top) {
        rows.add(_RankRow(
          userId: p.userId,
          name: p.name,
          avatar: AvatarUrlResolver.resolve(p.avatar),
          rank: p.rank,
          primary: ovMoneyShort(p.revenue),
          secondary: '${ovInt(p.sales)} ${p.sales == 1 ? 'venda' : 'vendas'}',
          relative: best > 0 ? p.revenue / best : 0,
        ));
      }
    } else {
      salesMode = false;
      final sorted = [...data.teamMembers]
        ..sort((a, b) => b.performance.compareTo(a.performance));
      final top = sorted.take(6).toList(growable: false);
      final best = top.isEmpty ? 0.0 : top.first.performance;
      for (var i = 0; i < top.length; i++) {
        final m = top[i];
        rows.add(_RankRow(
          userId: m.userId,
          name: m.name,
          rank: i + 1,
          primary: ovPct(m.performance, 0),
          secondary: '${ovInt(m.completedTasks)} concluídas',
          relative: best > 0 ? m.performance / best : 0,
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OverviewBandHeader(
          title: 'Top corretores',
          hint: salesMode
              ? 'por VGV no período · toque para filtrar'
              : 'por tarefas concluídas · toque para filtrar',
          tone: OverviewTones.slate(context),
        ),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          const OverviewEmptyLine(
            icon: LucideIcons.trophy,
            text: 'Nenhum corretor com vendas neste recorte.',
          )
        else
          for (final r in rows)
            _RankTile(
              row: r,
              selected: _filters.teamMember == r.userId,
              onTap: () => _toggleMember(r.userId),
            ),
      ],
    );
  }

  // ─── 6. Panorama ───────────────────────────────────────────────────────────

  Widget _buildPanorama(BuildContext context, DashboardOverview data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OverviewBandHeader(
          title: 'Panorama',
          tone: OverviewTones.slate(context),
        ),
        const SizedBox(height: 14),
        _buildSources(context, data),
        const SizedBox(height: 16),
        Container(height: 1, color: OverviewTones.rule(context)),
        const SizedBox(height: 14),
        _buildAgenda(context, data),
        const SizedBox(height: 16),
        Container(height: 1, color: OverviewTones.rule(context)),
        const SizedBox(height: 14),
        _buildPending(context, data),
      ],
    );
  }

  Widget _zoneHint(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
        ),
      );

  Widget _buildSources(BuildContext context, DashboardOverview data) {
    final theme = Theme.of(context);
    final ls = data.leadSources;
    // Mesmo recorte do web: as 6 primeiras fatias sem as zeradas, ordenadas
    // do maior para o menor; o percentual é sobre as fatias exibidas.
    final shown = ls.sources.take(6).where((s) => s.count > 0).toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    final sum = shown.fold<int>(0, (a, b) => a + b.count);
    final sky = OverviewTones.sky(context);
    final slate = OverviewTones.slate(context);
    const alphas = [1.0, 1.0, 0.78, 0.62, 0.5, 0.4];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: OverviewEyebrow('Origem dos leads')),
            OverviewLink(
              label: 'Ver detalhes',
              onTap: () => _openDetails(OverviewDetailKind.sources),
            ),
          ],
        ),
        _zoneHint(
          context,
          ls.withoutSource > 0
              ? '${ovInt(ls.withoutSource)} sem origem informada'
              : 'distribuição por canal',
        ),
        if (shown.isEmpty)
          const OverviewEmptyLine(
            icon: LucideIcons.chartPie,
            text: 'Nenhum lead com origem no período.',
          )
        else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                ovInt(ls.total),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'leads',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < shown.length; i++)
            InkWell(
              onTap: () => _openDetails(OverviewDetailKind.sources),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            shown[i].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: ThemeHelpers.textColor(context),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${ovInt(shown[i].count)} · ${ovPct(sum > 0 ? shown[i].count / sum * 100 : 0.0)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    OverviewBar(
                      fraction: sum > 0 ? shown[i].count / sum : 0,
                      tone: i == 0
                          ? sky
                          : slate.withValues(alpha: alphas[math.min(i, alphas.length - 1)]),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildAgenda(BuildContext context, DashboardOverview data) {
    final theme = Theme.of(context);
    final a = data.appointments;
    final upcoming = a.upcoming.take(5).toList(growable: false);
    final today = DateUtils.dateOnly(DateTime.now());
    final canOpenCalendar =
        ModuleAccessService.instance.canAccessRoutePath(AppRoutes.calendar);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: OverviewEyebrow('Agenda')),
            if (canOpenCalendar)
              OverviewLink(
                label: 'Abrir',
                withChevron: true,
                onTap: () => Navigator.of(context).pushNamed(AppRoutes.calendar),
              ),
          ],
        ),
        _zoneHint(
          context,
          '${ovInt(a.visits)} visitas · ${ovInt(a.meetings)} reuniões',
        ),
        if (upcoming.isEmpty)
          const OverviewEmptyLine(
            icon: LucideIcons.calendarClock,
            text: 'Nenhum compromisso próximo.',
          )
        else
          for (final ap in upcoming)
            Builder(builder: (context) {
              final dt = ap.dateTime;
              final isToday =
                  dt != null && DateUtils.isSameDay(DateUtils.dateOnly(dt), today);
              final stampTone = isToday
                  ? OverviewTones.amber(context)
                  : ThemeHelpers.textColor(context);
              final who = ap.clientName ?? ap.propertyTitle ?? '—';
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: OverviewTones.rule(context)),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 52,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dt == null ? '—' : DateFormat('HH:mm').format(dt),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: stampTone,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          Text(
                            isToday
                                ? 'hoje'
                                : (dt == null
                                    ? ''
                                    : DateFormat('dd/MM').format(dt)),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: isToday
                                  ? stampTone
                                  : ThemeHelpers.textSecondaryColor(context),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ap.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: ThemeHelpers.textColor(context),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$who · ${ap.assignedToName ?? '—'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: ThemeHelpers.textSecondaryColor(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
      ],
    );
  }

  Widget _buildPending(BuildContext context, DashboardOverview data) {
    final theme = Theme.of(context);
    final t = data.tasks;
    final items = <({String label, int value, IconData icon, Color tone, OverviewDetailKind kind})>[
      (
        label: 'Tarefas atrasadas',
        value: t.overdue,
        icon: LucideIcons.triangleAlert,
        tone: OverviewTones.red(context),
        kind: OverviewDetailKind.tasks,
      ),
      (
        label: 'Vencem hoje',
        value: t.dueToday,
        icon: LucideIcons.clock3,
        tone: OverviewTones.amber(context),
        kind: OverviewDetailKind.tasks,
      ),
      (
        label: 'Documentos pendentes',
        value: data.statistics.pendingDocuments,
        icon: LucideIcons.fileText,
        tone: OverviewTones.sky(context),
        kind: OverviewDetailKind.documents,
      ),
    ];
    final total = items.fold<int>(0, (a, b) => a + b.value);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OverviewEyebrow('Pendências'),
        _zoneHint(
          context,
          total > 0 ? '${ovInt(total)} itens pedem atenção' : 'tudo em dia',
        ),
        if (total == 0)
          const OverviewEmptyLine(
            icon: LucideIcons.listTodo,
            text: 'Nenhuma pendência no momento.',
          )
        else
          for (final it in items)
            InkWell(
              onTap: () => _openDetails(it.kind),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: OverviewTones.rule(context)),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(it.icon, size: 17, color: it.tone),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        it.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                    ),
                    Text(
                      ovInt(it.value),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: it.value == 0
                            ? secondary.withValues(alpha: 0.6)
                            : ThemeHelpers.textColor(context),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded, size: 18, color: secondary),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  // ─── 7. Atividades ─────────────────────────────────────────────────────────

  Widget _buildActivities(BuildContext context, DashboardOverview data) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final list = data.activities.activities;

    Color toneOf(String type) {
      switch (type) {
        case 'sale':
          return OverviewTones.green(context);
        case 'lost':
          return OverviewTones.red(context);
        case 'lead':
        case 'client':
          return OverviewTones.sky(context);
        case 'property':
        case 'rental':
          return OverviewTones.amber(context);
        default:
          return OverviewTones.slate(context);
      }
    }

    IconData iconOf(String type) {
      switch (type) {
        case 'property':
          return LucideIcons.building2;
        case 'sale':
          return LucideIcons.dollarSign;
        case 'lost':
          return LucideIcons.trendingDown;
        case 'lead':
          return LucideIcons.userPlus;
        case 'rental':
          return LucideIcons.house;
        case 'client':
          return LucideIcons.users;
        case 'user':
          return LucideIcons.userRound;
        default:
          return LucideIcons.calendarDays;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _activitiesOpen = !_activitiesOpen),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Icon(
                  LucideIcons.activity,
                  size: 17,
                  color: ThemeHelpers.textColor(context),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Atividades recentes',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                      Text(
                        'eventos do sistema no período',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                _ValueTag(text: ovInt(data.activities.total)),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: _activitiesOpen ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(Icons.expand_more_rounded, color: secondary),
                ),
              ],
            ),
          ),
        ),
        if (_activitiesOpen) ...[
          if (list.isEmpty)
            const OverviewEmptyLine(
              icon: LucideIcons.activity,
              text: 'Nenhuma atividade no período.',
            )
          else
            for (final act in list.take(12))
              Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: OverviewTones.rule(context)),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: toneOf(act.type).withValues(alpha: 0.14),
                      ),
                      child: Icon(
                        iconOf(act.type),
                        size: 13,
                        color: toneOf(act.type),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            act.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: ThemeHelpers.textColor(context),
                            ),
                          ),
                          if (act.description.isNotEmpty ||
                              act.userName != null)
                            Text(
                              [
                                if (act.description.isNotEmpty) act.description,
                                if (act.userName != null) act.userName!,
                              ].join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: secondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      ovTimeAgo(act.createdAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: secondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }

  // ─── Esqueleto ─────────────────────────────────────────────────────────────

  Widget _buildSkeleton(BuildContext context) {
    Widget line(double w, double h) =>
        SkeletonText(width: w, height: h, borderRadius: 5);
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(_kPadH, 14, _kPadH, 88),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          line(220, 11),
          const SizedBox(height: 12),
          line(180, 26),
          const SizedBox(height: 16),
          const SkeletonBox(width: double.infinity, height: 46, borderRadius: 12),
          const SizedBox(height: 14),
          line(260, 12),
          const SizedBox(height: 26),
          line(120, 11),
          const SizedBox(height: 10),
          line(170, 36),
          const SizedBox(height: 10),
          line(230, 12),
          const SizedBox(height: 22),
          const SkeletonBox(width: double.infinity, height: 150, borderRadius: 12),
          const SizedBox(height: 24),
          for (var r = 0; r < 2; r++) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      line(90, 11),
                      const SizedBox(height: 8),
                      line(70, 24),
                      const SizedBox(height: 6),
                      line(120, 10),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      line(90, 11),
                      const SizedBox(height: 8),
                      line(70, 24),
                      const SizedBox(height: 6),
                      line(120, 10),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
          ],
          line(160, 16),
          const SizedBox(height: 14),
          for (var i = 0; i < 3; i++) ...[
            const SkeletonBox(width: double.infinity, height: 22, borderRadius: 6),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Peças locais
// ═════════════════════════════════════════════════════════════════════════════

/// Badge de filtros ativos sobre o botão de Filtros da toolbar.
class _BadgedAction extends StatelessWidget {
  const _BadgedAction({required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (count > 0)
          Positioned(
            top: 5,
            right: 4,
            child: IgnorePointer(
              child: Container(
                constraints: const BoxConstraints(minWidth: 15),
                height: 15,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: OverviewTones.brand(context),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: ThemeHelpers.backgroundColor(context),
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Botão do recorte de tempo: palavra do período + datas; abre os filtros.
class _PeriodButton extends StatelessWidget {
  const _PeriodButton({
    required this.word,
    required this.period,
    required this.onTap,
  });

  final String word;
  final String period;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = OverviewTones.brand(context);
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ThemeHelpers.borderColor(context)),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  color: brand.withValues(alpha: isDark ? 0.18 : 0.10),
                ),
                child: Icon(LucideIcons.calendarRange, size: 16, color: brand),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      word,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                        height: 1.1,
                      ),
                    ),
                    Text(
                      period,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.expand_more_rounded,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Carimbo da hora do dado ("Atualizado 14:32" / "Último dado").
class _Stamp extends StatelessWidget {
  const _Stamp({required this.stale, required this.time});

  final bool stale;
  final String? time;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = stale
        ? OverviewTones.amber(context)
        : ThemeHelpers.textSecondaryColor(context);
    return Tooltip(
      message: stale
          ? 'A última atualização falhou; a tela mostra o dado anterior'
          : 'Hora do dado que está em tela',
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: stale ? 'Último dado' : 'Atualizado'),
            if (time != null)
              TextSpan(
                text: ' $time',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
          ],
        ),
        style: theme.textTheme.labelSmall?.copyWith(
          color: tone,
          fontWeight: FontWeight.w700,
          height: 1.6,
        ),
      ),
    );
  }
}

/// Selo de valor neutro (não é variação: não pinta de verde).
class _ValueTag extends StatelessWidget {
  const _ValueTag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : const Color(0xFFEEF0F3),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: ThemeHelpers.textColor(context),
          fontWeight: FontWeight.w800,
          fontSize: 11,
          height: 1.2,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Leitura miúda da abertura (Ticket médio / Por dia / Conversão).
class _Reading extends StatelessWidget {
  const _Reading({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textColor(context),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// Linha da ficha da meta (rótulo à esquerda, valor à direita).
class _GoalLine extends StatelessWidget {
  const _GoalLine({
    required this.label,
    required this.value,
    this.tone,
    this.last = false,
  });

  final String label;
  final String value;
  final Color? tone;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: OverviewTones.rule(context))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: tone ?? ThemeHelpers.textColor(context),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Anel da meta: trilho neutro + arco na cor do estado da meta.
class _GoalRing extends StatelessWidget {
  const _GoalRing({
    required this.progress,
    required this.label,
    required this.color,
  });

  /// 0–100 (já limitado).
  final double progress;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const size = 108.0;
    final theme = Theme.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(size, size),
            painter: _RingPainter(
              fraction: progress / 100,
              color: color,
              track: OverviewTones.track(context),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'atingido',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.fraction,
    required this.color,
    required this.track,
  });

  final double fraction;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 11.0;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final base = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    final f = fraction.clamp(0.0, 1.0).toDouble();
    if (f <= 0) return;
    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * f, false, arc);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.fraction != fraction || old.color != color || old.track != track;
}

/// Curva de 6 meses do VGV: área na tinta da marca, meta tracejada em âmbar
/// e leitura por toque (toque ou arraste lê o mês; toque de novo solta).
class _SalesCurve extends StatelessWidget {
  const _SalesCurve({
    required this.labels,
    required this.values,
    required this.target,
    required this.selected,
    required this.onSelect,
  });

  final List<String> labels;
  final List<double> values;
  final double? target;
  final int? selected;
  final ValueChanged<int?> onSelect;

  static const double _height = 170;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final labelStyle = (theme.textTheme.labelSmall ?? const TextStyle()).copyWith(
      color: ThemeHelpers.textSecondaryColor(context),
      fontSize: 10,
    );
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        int? indexAt(double dx) {
          if (values.length < 2) return null;
          final inner = width - _CurvePainter.padL - _CurvePainter.padR;
          if (inner <= 0) return null;
          final rel = ((dx - _CurvePainter.padL) / inner).clamp(0.0, 1.0);
          return (rel * (values.length - 1)).round();
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) {
            final i = indexAt(d.localPosition.dx);
            if (i != null) onSelect(i);
          },
          onHorizontalDragUpdate: (d) {
            final i = indexAt(d.localPosition.dx);
            if (i != null && i != selected) onSelect(i);
          },
          child: CustomPaint(
            size: Size(width, _height),
            painter: _CurvePainter(
              values: values,
              labels: labels,
              target: target,
              selected: selected,
              line: OverviewTones.brand(context),
              targetColor: OverviewTones.amber(context),
              grid: ThemeHelpers.borderLightColor(context),
              surface: isDark
                  ? ThemeHelpers.backgroundColor(context)
                  : Colors.white,
              labelStyle: labelStyle,
              strongLabelColor: ThemeHelpers.textColor(context),
            ),
          ),
        );
      },
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.values,
    required this.labels,
    required this.target,
    required this.selected,
    required this.line,
    required this.targetColor,
    required this.grid,
    required this.surface,
    required this.labelStyle,
    required this.strongLabelColor,
  });

  static const double padL = 48;
  static const double padR = 8;
  static const double padT = 8;
  static const double padB = 22;

  final List<double> values;
  final List<String> labels;
  final double? target;
  final int? selected;
  final Color line;
  final Color targetColor;
  final Color grid;
  final Color surface;
  final TextStyle labelStyle;
  final Color strongLabelColor;

  void _text(
    Canvas canvas,
    String text,
    double x,
    double y, {
    required double maxWidth,
    bool alignRight = false,
    bool center = false,
    bool strong = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: strong
            ? labelStyle.copyWith(
                color: strongLabelColor,
                fontWeight: FontWeight.w900,
              )
            : labelStyle.copyWith(fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    var dx = x;
    if (alignRight) dx = x + maxWidth - tp.width;
    if (center) dx = x - tp.width / 2;
    tp.paint(canvas, Offset(dx, y));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final innerW = size.width - padL - padR;
    final innerH = size.height - padT - padB;
    if (innerW <= 0 || innerH <= 0) return;

    var maxV = values.reduce(math.max);
    final t = target;
    if (t != null && t > maxV) maxV = t;
    final yMax = maxV <= 0 ? 1.0 : maxV * 1.12;

    double x(int i) => padL + innerW * i / (values.length - 1);
    double y(double v) => padT + innerH - (v / yMax) * innerH;

    // Grade recessiva: três linhas com o valor na margem.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var k = 0; k <= 2; k++) {
      final v = yMax * k / 2;
      final yy = y(v);
      canvas.drawLine(Offset(padL, yy), Offset(size.width - padR, yy), gridPaint);
      _text(canvas, ovMoneyShort(v), 0, yy - 7, maxWidth: padL - 6, alignRight: true);
    }

    // Área + linha da série.
    final path = Path()..moveTo(x(0), y(values[0]));
    for (var i = 1; i < values.length; i++) {
      path.lineTo(x(i), y(values[i]));
    }
    final area = Path.from(path)
      ..lineTo(x(values.length - 1), y(0))
      ..lineTo(x(0), y(0))
      ..close();
    final shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [line.withValues(alpha: 0.22), line.withValues(alpha: 0.0)],
    ).createShader(Rect.fromLTWH(0, padT, size.width, innerH));
    canvas.drawPath(area, Paint()..shader = shader);
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // Meta do mês tracejada.
    if (t != null && t > 0) {
      final ty = y(t);
      final dash = Paint()
        ..color = targetColor
        ..strokeWidth = 1.5;
      var dx = padL;
      final end = size.width - padR;
      while (dx < end) {
        canvas.drawLine(Offset(dx, ty), Offset(math.min(dx + 5, end), ty), dash);
        dx += 9;
      }
    }

    // Mira do mês tocado.
    final sel = selected;
    if (sel != null && sel >= 0 && sel < values.length) {
      final sx = x(sel);
      canvas.drawLine(
        Offset(sx, padT),
        Offset(sx, padT + innerH),
        Paint()
          ..color = strongLabelColor.withValues(alpha: 0.25)
          ..strokeWidth = 1,
      );
    }

    // Pontos com anel na cor da superfície.
    for (var i = 0; i < values.length; i++) {
      final c = Offset(x(i), y(values[i]));
      final isSel = i == sel;
      canvas.drawCircle(c, isSel ? 6.5 : 4.5, Paint()..color = surface);
      canvas.drawCircle(c, isSel ? 4.5 : 3, Paint()..color = line);
    }

    // Rótulos dos meses.
    final slot = innerW / (values.length - 1);
    for (var i = 0; i < labels.length && i < values.length; i++) {
      _text(
        canvas,
        labels[i],
        x(i),
        size.height - padB + 6,
        maxWidth: math.max(28, slot),
        center: true,
        strong: i == sel,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CurvePainter old) => true;
}

// ─── Indicadores ─────────────────────────────────────────────────────────────

class _Kpi {
  const _Kpi({
    required this.kind,
    required this.label,
    required this.value,
    required this.delta,
    required this.note,
    required this.icon,
    required this.tone,
  });

  final OverviewDetailKind kind;
  final String label;
  final String value;
  final double? delta;

  /// Legenda com trechos em negrito (os números).
  final List<(String, bool)> note;
  final IconData icon;
  final Color tone;
}

/// Indicador da fita: traço vertical de 3px na tinta do próprio indicador
/// (divisor e identidade ao mesmo tempo), sem chapa de card.
class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.kpi,
    required this.comparing,
    required this.onTap,
  });

  final _Kpi kpi;
  final bool comparing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 4, 4, 4),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: kpi.tone, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(kpi.icon, size: 14, color: kpi.tone),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    kpi.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      kpi.value,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: textColor,
                        letterSpacing: -0.8,
                        height: 1.0,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                // Sem comparação ligada o selo diria "— 0,0%" nos quatro.
                if (comparing) ...[
                  const SizedBox(width: 6),
                  OverviewDeltaChip(value: kpi.delta, compact: true),
                ],
              ],
            ),
            const SizedBox(height: 5),
            Text.rich(
              TextSpan(
                children: [
                  for (final seg in kpi.note)
                    TextSpan(
                      text: seg.$1,
                      style: seg.$2
                          ? TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.w900,
                            )
                          : null,
                    ),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Funil ───────────────────────────────────────────────────────────────────

class _FunnelStage {
  const _FunnelStage({
    required this.label,
    required this.value,
    required this.pctOfTop,
    required this.width,
    required this.tone,
  });

  final String label;
  final int value;
  final double pctOfTop;

  /// Largura desenhada do degrau (% do trilho, com piso de 2,5%).
  final double width;
  final Color tone;
}

/// Degrau da escada: corpo em véu, ponta sólida de 3px na tinta da etapa e o
/// recuo em relação à etapa anterior (a PERDA) marcado no próprio trilho.
class _FunnelStep extends StatelessWidget {
  const _FunnelStep({required this.stage, required this.previousWidth});

  final _FunnelStage stage;
  final double? previousWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final w = (stage.width / 100).clamp(0.0, 1.0).toDouble();
    final pw = ((previousWidth ?? 0) / 100).clamp(0.0, 1.0).toDouble();
    final loss = OverviewTones.red(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              stage.label,
              maxLines: 2,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: ThemeHelpers.textColor(context),
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 26,
              child: Stack(
                children: [
                  // O vão entre o degrau anterior e este É a perda.
                  if (previousWidth != null && pw > w)
                    FractionallySizedBox(
                      widthFactor: pw,
                      heightFactor: 1,
                      alignment: Alignment.centerLeft,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: loss.withValues(alpha: isDark ? 0.10 : 0.06),
                          borderRadius: BorderRadius.circular(4),
                          border: Border(
                            right: BorderSide(
                              color: loss.withValues(alpha: 0.45),
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (w > 0)
                    FractionallySizedBox(
                      widthFactor: w,
                      heightFactor: 1,
                      alignment: Alignment.centerLeft,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: stage.tone.withValues(alpha: isDark ? 0.28 : 0.18),
                          borderRadius: BorderRadius.circular(4),
                          border: Border(
                            right: BorderSide(color: stage.tone, width: 3),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 58,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  ovInt(stage.value),
                  maxLines: 1,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                    fontFeatures: const [FontFeature.tabularFigures()],
                    height: 1.1,
                  ),
                ),
                Text(
                  ovPct(stage.pctOfTop, stage.pctOfTop < 10 ? 1 : 0),
                  maxLines: 1,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w700,
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

// ─── Ranking ─────────────────────────────────────────────────────────────────

class _RankRow {
  const _RankRow({
    required this.userId,
    required this.name,
    this.avatar,
    required this.rank,
    required this.primary,
    required this.secondary,
    required this.relative,
  });

  final String userId;
  final String name;
  final String? avatar;
  final int rank;
  final String primary;
  final String secondary;

  /// Proporção em relação ao 1º (0–1).
  final double relative;
}

class _RankTile extends StatelessWidget {
  const _RankTile({
    required this.row,
    required this.selected,
    required this.onTap,
  });

  final _RankRow row;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final brand = OverviewTones.brand(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    // Pódio em UMA tinta com peso decrescente (posição é ordem, não
    // significado): 1º âmbar, 2º pedra, o resto neutro.
    final medal = row.rank == 1
        ? OverviewTones.amber(context)
        : row.rank == 2
            ? OverviewTones.slate(context)
            : secondary;
    return Tooltip(
      message: selected
          ? 'Remover filtro por este corretor'
          : 'Filtrar por este corretor',
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 9, 4, 9),
          decoration: BoxDecoration(
            color: selected
                ? brand.withValues(alpha: isDark ? 0.10 : 0.05)
                : null,
            border: Border(
              left: BorderSide(
                color: selected ? brand : Colors.transparent,
                width: 3,
              ),
              bottom: BorderSide(color: OverviewTones.rule(context)),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  '${row.rank}º',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: medal,
                  ),
                ),
              ),
              OverviewAvatar(name: row.name, url: row.avatar, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                    const SizedBox(height: 5),
                    // A régua cede espaço, a legenda ("12 vendas") não
                    // estoura: em tela de 320dp ou com fonte grande ela
                    // leva no máximo 3/4 da linha e encolhe com reticências
                    // (29/09/2026).
                    LayoutBuilder(
                      builder: (context, c) => Row(
                        children: [
                          Expanded(
                            child: OverviewBar(
                              fraction: row.relative,
                              tone: OverviewTones.slate(context),
                              height: 5,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: math.max(
                                0.0,
                                math.min(c.maxWidth * 0.75, c.maxWidth - 8),
                              ),
                            ),
                            child: Text(
                              row.secondary,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: secondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Teto para o valor: o nome e a régua nunca ficam sem lugar.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 104),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    row.primary,
                    maxLines: 1,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: ThemeHelpers.textColor(context),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              // Slot fixo: o "x" só aparece na linha filtrada, mas o espaço
              // existe sempre para a coluna de números não sair do prumo.
              SizedBox(
                width: 24,
                child: selected
                    ? Icon(Icons.close_rounded, size: 15, color: secondary)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
