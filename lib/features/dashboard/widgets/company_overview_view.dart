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

  /// Tela larga (tablet, celular deitado): a coluna para em 880dp e
  /// centraliza — faixa esticada em 1000dp vira leitura cansada.
  static const double _kMaxContentW = 880;

  /// Largura ÚTIL a partir da qual as faixas abrem em duas colunas (VGV |
  /// curva, quatro indicadores numa linha, origem | agenda).
  static const double _kTwoColW = 600;

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
    // Largura útil sem LayoutBuilder: o RefreshIndicator precisa do ListView
    // como filho DIRETO (LayoutBuilder no meio quebra o gesto de puxar).
    final viewW = MediaQuery.sizeOf(context).width;
    final side = viewW > _kMaxContentW ? (viewW - _kMaxContentW) / 2 : 0.0;
    final wide = math.min(viewW, _kMaxContentW) - 2 * _kPadH >= _kTwoColW;

    return RefreshIndicator(
      color: OverviewTones.brand(context),
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(side, 0, side, 88),
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
                pad(_buildOpening(context, data, wide)),
                rule,
                pad(_buildKpis(context, data, wide), top: 6, bottom: 6),
                rule,
                pad(_buildFunnel(context, data)),
                rule,
                pad(_buildRanking(context, data)),
                rule,
                pad(_buildPanorama(context, data, wide)),
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

  /// "qua, 30 set 2026".
  String _todayStamp() {
    final now = DateTime.now();
    String clean(String s) => s.replaceAll('.', '');
    final wd = clean(DateFormat('EEE', 'pt_BR').format(now));
    final mon = clean(DateFormat('MMM', 'pt_BR').format(now));
    return '$wd, ${now.day} $mon ${now.year}';
  }

  /// Primeiro texto preenchido da lista (nulo se nenhum) — no lugar de
  /// mostrar "—" onde o dado não veio.
  static String? _firstFilled(List<String?> values) {
    for (final v in values) {
      final t = v?.trim() ?? '';
      if (t.isNotEmpty) return t;
    }
    return null;
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
        // Quem lê e de onde: o avatar + saudação do Dashboard geral (a
        // referência de painel do app), sem ponto de cor nem pílulas.
        Row(
          children: [
            OverviewAvatar(
              name: _userName ?? '',
              url: AvatarUrlResolver.resolve(_userAvatar),
              size: 46,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  const SizedBox(height: 2),
                  Text(
                    '$visao · ${_todayStamp()}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // O botão do período tem altura MÍNIMA (cresce com texto em 130%);
        // o de atualizar é o quadrado de 48 ao lado, centrado nele.
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
              message: 'Atualizar agora',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _loading ? null : _refresh,
                  borderRadius: BorderRadius.circular(12),
                  // Mesmo corpo do botão do período (fill de campo + fio):
                  // os dois controles do topo leem como um par.
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: OverviewTones.track(context),
                      border: Border.all(
                        color: ThemeHelpers.borderLightColor(context),
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
                        : Icon(
                            LucideIcons.refreshCw,
                            size: 17,
                            color: textColor,
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // "Mostrando …" — as palavras do recorte, todas abrem os filtros.
        // Frase e carimbo em `Wrap`: lado a lado quando cabem; em tela
        // estreita (ou fonte grande) o carimbo desce de linha — ao lado, ele
        // espremia a frase numa coluna de quatro linhas em 320dp.
        InkWell(
          onTap: _openFilters,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text.rich(
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
                            decorationColor: textColor.withValues(alpha: 0.3),
                          ),
                        ),
                      ],
                    ],
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
                ),
                if (stamp != null || _stale)
                  _Stamp(
                    stale: _stale,
                    time: stamp,
                  ),
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
                padding: const EdgeInsets.fromLTRB(11, 7, 8, 7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: OverviewTones.track(context),
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

  Widget _buildOpening(
    BuildContext context,
    DashboardOverview data,
    bool wide,
  ) {
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

    final secondaryStyle = theme.textTheme.labelSmall?.copyWith(
      color: secondary,
      fontWeight: FontWeight.w600,
    );
    final curve = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OverviewEyebrow('Últimos 6 meses'),
        // A leitura do mês vira manchete da curva, numa linha própria: ao
        // lado do rótulo ela dividia 50/50 e o VALOR saía com reticências
        // em 320dp. Em `Wrap`, o selo desce quando não cabe.
        if (readIndex != null) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '${curveLabels[readIndex]}  '),
                    TextSpan(
                      text: ovMoneyShort(curveValues[readIndex]),
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: secondary,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (readDelta != null) ...[
                OverviewDeltaChip(value: readDelta, compact: true),
                Text('vs. mês anterior', style: secondaryStyle),
              ],
            ],
          ),
        ],
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
            text: 'A curva aparece quando houver pelo menos dois meses de '
                'histórico de vendas.',
          ),
        if (curveValues.length > 1) ...[
          const SizedBox(height: 8),
          // Legenda em peças soltas: a meta (quando há) e o "como ler".
          Wrap(
            spacing: 14,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (g.hasTarget)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DashMark(color: OverviewTones.amber(context)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Meta do mês ${ovMoneyShort(g.target)}',
                        style: secondaryStyle,
                      ),
                    ),
                  ],
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.touch_app_outlined, size: 13, color: secondary),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'Toque ou arraste para ler um mês',
                      style: secondaryStyle,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ],
    );

    final rule = OverviewTones.rule(context);
    // Tela larga: VGV e curva lado a lado (a curva ganha o fio à esquerda
    // como divisor — `IntrinsicHeight` não convive com o LayoutBuilder dela).
    final top = wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: vgv),
              const SizedBox(width: 20),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.only(left: 20),
                  decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: rule)),
                  ),
                  child: curve,
                ),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              vgv,
              const SizedBox(height: 18),
              Container(height: 1, color: rule),
              const SizedBox(height: 16),
              curve,
            ],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        top,
        if (g.hasTarget) ...[
          const SizedBox(height: 18),
          Container(height: 1, color: rule),
          const SizedBox(height: 16),
          _buildGoal(context, g, wide),
        ],
      ],
    );
  }

  Widget _vRule(BuildContext context) => Container(
        width: 1,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        color: OverviewTones.rule(context),
      );

  Widget _buildGoal(BuildContext context, OverviewMonthlyGoal g, bool wide) {
    final rawProgress = g.progress;
    final progress = rawProgress.clamp(0.0, 100.0).toDouble();
    final remaining = g.remaining < 0 ? 0.0 : g.remaining;
    // Cor do anel = estado da meta: musgo batida, âmbar fora do ritmo, marca
    // no caminho normal (mesma regra do `HomeAbertura` do web).
    final ringColor = progress >= 100
        ? OverviewTones.green(context)
        : (!g.onTrack ? OverviewTones.amber(context) : OverviewTones.brand(context));
    final status = progress >= 100
        ? 'Meta batida'
        : (g.onTrack ? 'No ritmo da meta' : 'Abaixo do ritmo');

    // Passou da meta: a linha diz QUANTO passou (o anel já diz "batida").
    final surplus = g.remaining < 0 ? -g.remaining : 0.0;

    // `stretch`: cada linha ocupa a largura toda (o filete de baixo também)
    // mesmo quando o valor desce para baixo do rótulo em tela estreita.
    final lines = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GoalLine(label: 'Atingido', value: ovMoneyShort(g.current)),
        _GoalLine(label: 'Meta', value: ovMoneyShort(g.target)),
        _GoalLine(
          label: remaining > 0
              ? 'Faltam'
              : (surplus > 0 ? 'Acima da meta' : 'Situação'),
          value: remaining > 0
              ? ovMoneyShort(remaining)
              : (surplus > 0 ? '+${ovMoneyShort(surplus)}' : 'Batida'),
          icon: remaining > 0 ? LucideIcons.hourglass : LucideIcons.circleCheck,
          tone: remaining > 0
              ? OverviewTones.amber(context)
              : OverviewTones.green(context),
        ),
        // O ritmo que falta por dia responde "o que fazer agora" melhor que
        // o saldo solto.
        if (remaining > 0 && g.daysLeft > 0 && g.dailyTarget > 0)
          _GoalLine(
            label: 'Ritmo necessário',
            value: '${ovMoneyShort(g.dailyTarget)}/dia',
          ),
        _GoalLine(
          label: 'Prazo',
          value: '${ovInt(g.daysLeft)} ${g.daysLeft == 1 ? 'dia' : 'dias'}',
          last: true,
        ),
      ],
    );

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
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _GoalRing(
                  progress: progress,
                  label: ovPct(rawProgress, 0),
                  color: ringColor,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: _GoalRing.size,
                  child: Text(
                    status,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: ThemeHelpers.textColor(context),
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 18),
            // Na tela larga as linhas não se espicham: rótulo e valor
            // separados por 600dp não se leem como par.
            Expanded(
              child: wide
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 380),
                        child: lines,
                      ),
                    )
                  : lines,
            ),
          ],
        ),
      ],
    );
  }

  // ─── 3. Indicadores ────────────────────────────────────────────────────────

  Widget _buildKpis(BuildContext context, DashboardOverview data, bool wide) {
    final s = data.statistics;
    final ap = data.appointments;
    final comparing = _filters.isComparing;

    final leads = _Kpi(
      kind: OverviewDetailKind.leads,
      label: 'Leads',
      value: ovInt(s.totalLeads),
      delta: s.leadsGrowth,
      note: [
        (ovInt(data.leads.newToday), true),
        (data.leads.newToday == 1 ? ' novo hoje' : ' novos hoje', false),
      ],
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
        (s.salesCount == 1 ? ' ficha ÷ ' : ' fichas ÷ ', false),
        (ovInt(s.totalLeads), true),
        (s.totalLeads == 1 ? ' lead' : ' leads', false),
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
        (ap.completed == 1 ? ' realizado · ' : ' realizados · ', false),
        (ovInt(ap.scheduled), true),
        (ap.scheduled == 1 ? ' marcado' : ' marcados', false),
      ],
      icon: LucideIcons.calendarCheck,
      tone: OverviewTones.amber(context),
    );
    final sales = _Kpi(
      kind: OverviewDetailKind.sales,
      label: 'Fichas finalizadas',
      value: ovInt(s.salesCount),
      delta: s.salesGrowth,
      // A legenda carrega o valor (evita o toque para descobrir quanto).
      note: s.salesCount > 0
          ? [(ovMoneyShort(s.totalSales), true), (' em VGV no período', false)]
          : const [('nenhuma ficha finalizada no período', false)],
      icon: LucideIcons.fileCheck,
      tone: OverviewTones.green(context),
    );

    // Rótulo na linha do ícone só quando a palavra mais longa cabe ali
    // (medida no tamanho real, fonte do sistema inclusa); senão ele ganha
    // linha própria — em 320dp "Agendamentos" partia em "Agendam/entos". A
    // largura da célula sai da coluna da tela: a grade vive em
    // `IntrinsicHeight`, que não convive com LayoutBuilder. Vale para as
    // quatro células juntas, para os números ficarem no mesmo prumo.
    final cols = wide ? 4 : 2;
    final gridW =
        math.min(MediaQuery.sizeOf(context).width, _kMaxContentW) - 2 * _kPadH;
    final cellW = (gridW - (cols - 1) * 25) / cols - 4;
    final widest = ovWidestWord(
      [leads.label, conversion.label, appointments.label, sales.label],
      _KpiTile.labelStyle(context),
      MediaQuery.textScalerOf(context),
    );
    final stacked = cellW - 26 - 8 - 16 < widest + 1;

    Widget tile(_Kpi k) => _KpiTile(
          kpi: k,
          comparing: comparing,
          stacked: stacked,
          onTap: () => _openDetails(k.kind),
        );

    // Grade de leituras separada por fios (sem chapa de card nem faixa
    // lateral): o fio vertical divide as colunas e o horizontal as linhas.
    // `IntrinsicHeight` iguala a altura do par sem fixar pixel.
    final rule = OverviewTones.rule(context);
    Widget vRule() => Container(
          width: 1,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: rule,
        );
    Widget row(List<Widget> tiles) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) vRule(),
                Expanded(child: tiles[i]),
              ],
            ],
          ),
        );

    if (wide) {
      return row([
        tile(leads),
        tile(conversion),
        tile(appointments),
        tile(sales),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row([tile(leads), tile(conversion)]),
        Container(height: 1, color: rule),
        row([tile(appointments), tile(sales)]),
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
          icon: LucideIcons.funnel,
          badge: _ValueTag(
            text: '${ovPct(s.realConversionRate)} de conversão',
          ),
        ),
        const SizedBox(height: 14),
        if (hasFunnel) ...[
          InkWell(
            onTap: () => _openDetails(OverviewDetailKind.funnel),
            borderRadius: BorderRadius.circular(10),
            // A coluna do nome da etapa acompanha a largura E a fonte: cabe
            // a palavra mais longa medida no tamanho real (30% da faixa
            // partia "Agendam/entos" em 320dp), com teto de 42% da faixa
            // para a régua nunca sumir.
            child: LayoutBuilder(
              builder: (context, c) {
                final widest = ovWidestWord(
                  stages.map((st) => st.label),
                  _FunnelStep.labelStyle(context),
                  MediaQuery.textScalerOf(context),
                );
                final labelW = math.min(
                  math.max(widest + 4, math.min(c.maxWidth * 0.3, 150.0)),
                  c.maxWidth * 0.42,
                );
                return Column(
                  children: [
                    for (var i = 0; i < stages.length; i++)
                      _FunnelStep(
                        stage: stages[i],
                        previousWidth: i > 0 ? stages[i - 1].width : null,
                        labelWidth: labelW,
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    // Legenda do véu de perda desenhado nos degraus.
                    Container(
                      width: 14,
                      height: 9,
                      decoration: BoxDecoration(
                        color: _FunnelStep.lossVeil(context),
                        borderRadius: BorderRadius.circular(2),
                        border: Border(
                          right: BorderSide(
                            color: _FunnelStep.lossEdge(context),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Frase curta: em 320dp com fonte grande a longa ("quem
                    // não avançou de uma etapa para a outra") saía cortada
                    // ao lado de "Etapa a etapa".
                    Flexible(
                      child: Text(
                        'quem ficou pelo caminho',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: ThemeHelpers.textSecondaryColor(context),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              OverviewLink(
                label: 'Etapa a etapa',
                withChevron: true,
                onTap: () => _openDetails(OverviewDetailKind.funnel),
              ),
            ],
          ),
        ] else
          const OverviewEmptyLine(
            icon: LucideIcons.funnel,
            text: 'Sem movimento no período. Amplie o período ou remova '
                'filtros para ver o caminho dos leads até a venda.',
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
          secondary: '${ovInt(m.completedTasks)} '
              '${m.completedTasks == 1 ? 'concluída' : 'concluídas'}',
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
              ? 'por VGV no período · toque no nome para ver só os números dele'
              : 'por tarefas concluídas · toque no nome para ver só os '
                  'números dele',
          tone: OverviewTones.slate(context),
          icon: LucideIcons.trophy,
        ),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          const OverviewEmptyLine(
            icon: LucideIcons.trophy,
            text: 'Nenhuma venda finalizada neste recorte. O ranking aparece '
                'assim que um corretor finalizar uma ficha — amplie o período '
                'para ver meses anteriores.',
          )
        else
          for (var i = 0; i < rows.length; i++)
            _RankTile(
              row: rows[i],
              selected: _filters.teamMember == rows[i].userId,
              // Sem filete na última linha: o fio da faixa vem logo abaixo
              // e os dois juntos liam como linha dupla.
              last: i == rows.length - 1,
              onTap: () => _toggleMember(rows[i].userId),
            ),
      ],
    );
  }

  // ─── 6. Panorama ───────────────────────────────────────────────────────────

  Widget _buildPanorama(
    BuildContext context,
    DashboardOverview data,
    bool wide,
  ) {
    final rule = OverviewTones.rule(context);
    final header = OverviewBandHeader(
      title: 'Panorama',
      hint: 'de onde vêm os leads, o que está marcado e o que está pendente',
      tone: OverviewTones.slate(context),
      icon: LucideIcons.layoutDashboard,
    );
    // Tela larga: origem e agenda lado a lado (fio à esquerda da agenda);
    // pendências embaixo, na largura toda.
    final sourcesAndAgenda = wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildSources(context, data)),
              const SizedBox(width: 20),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.only(left: 20),
                  decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: rule)),
                  ),
                  child: _buildAgenda(context, data),
                ),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSources(context, data),
              const SizedBox(height: 16),
              Container(height: 1, color: rule),
              const SizedBox(height: 14),
              _buildAgenda(context, data),
            ],
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 16),
        sourcesAndAgenda,
        const SizedBox(height: 16),
        Container(height: 1, color: rule),
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
            text: 'Nenhum lead com origem informada no período. A origem vem '
                'do canal por onde o lead chegou (site, portais, WhatsApp).',
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
              Flexible(
                child: Text(
                  'leads com origem',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w700,
                  ),
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
                          maxLines: 1,
                          softWrap: false,
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
          '${ovInt(a.visits)} ${a.visits == 1 ? 'visita' : 'visitas'} · '
          '${ovInt(a.meetings)} ${a.meetings == 1 ? 'reunião' : 'reuniões'}',
        ),
        if (upcoming.isEmpty)
          const OverviewEmptyLine(
            icon: LucideIcons.calendarClock,
            text: 'Nenhum compromisso marcado para os próximos dias. Visitas '
                'e reuniões criadas na agenda aparecem aqui.',
          )
        else
          for (var i = 0; i < upcoming.length; i++)
            Builder(builder: (context) {
              final ap = upcoming[i];
              // Sem filete na última linha: logo abaixo vem o fio que separa
              // a agenda das pendências (os dois liam como linha dupla).
              final last = i == upcoming.length - 1;
              final dt = ap.dateTime;
              final day = dt == null ? null : DateUtils.dateOnly(dt);
              final isToday = day != null && DateUtils.isSameDay(day, today);
              final isTomorrow = day != null &&
                  DateUtils.isSameDay(
                    day,
                    today.add(const Duration(days: 1)),
                  );
              final dayLabel = isToday
                  ? 'hoje'
                  : isTomorrow
                      ? 'amanhã'
                      : (dt == null ? '' : DateFormat('dd/MM').format(dt));
              // Quem e com quem, sem "—" onde o dado não veio.
              final details = [
                _firstFilled([ap.clientName, ap.propertyTitle]),
                _firstFilled([ap.assignedToName]),
              ].whereType<String>().join(' · ');
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  border: last
                      ? null
                      : Border(
                          bottom: BorderSide(color: OverviewTones.rule(context)),
                        ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Coluna da hora com largura MÍNIMA (cresce com a fonte);
                    // "hoje" ganha o marcador âmbar e o texto fica no tom do
                    // tema — âmbar como texto miúdo não passa contraste.
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 54),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            dt == null ? '--:--' : DateFormat('HH:mm').format(dt),
                            maxLines: 1,
                            softWrap: false,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: ThemeHelpers.textColor(context),
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          if (dayLabel.isNotEmpty)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isToday) ...[
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: OverviewTones.amber(context),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Text(
                                  dayLabel,
                                  maxLines: 1,
                                  softWrap: false,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: isToday
                                        ? ThemeHelpers.textColor(context)
                                        : ThemeHelpers.textSecondaryColor(
                                            context,
                                          ),
                                    fontWeight: isToday
                                        ? FontWeight.w900
                                        : FontWeight.w700,
                                  ),
                                ),
                              ],
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
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: ThemeHelpers.textColor(context),
                              height: 1.25,
                            ),
                          ),
                          if (details.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              details,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color:
                                    ThemeHelpers.textSecondaryColor(context),
                              ),
                            ),
                          ],
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
          total == 0
              ? 'tudo em dia'
              : total == 1
                  ? '1 item pede atenção'
                  : '${ovInt(total)} itens pedem atenção',
        ),
        if (total == 0)
          const OverviewEmptyLine(
            icon: LucideIcons.listTodo,
            text: 'Nada atrasado, nada vencendo hoje e nenhum documento '
                'esperando conferência.',
          )
        else
          for (final (i, it) in items.indexed)
            InkWell(
              onTap: () => _openDetails(it.kind),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                // A última linha fica sem filete: o fio da faixa vem logo
                // abaixo e os dois liam como linha dupla.
                decoration: BoxDecoration(
                  border: i == items.length - 1
                      ? null
                      : Border(
                          bottom: BorderSide(color: OverviewTones.rule(context)),
                        ),
                ),
                child: Row(
                  children: [
                    // Com pendência, o ícone ganha a chapa da tinta e salta
                    // aos olhos; zerado, fica apagado.
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: it.value > 0
                            ? OverviewTones.wash(context, it.tone)
                            : null,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                        it.icon,
                        size: 16,
                        color: it.value > 0
                            ? it.tone
                            : secondary.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Duas linhas: "Documentos pendentes" saía "Documentos
                    // pende…" em 320dp com fonte grande.
                    Expanded(
                      child: Text(
                        it.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: ThemeHelpers.textColor(context),
                          height: 1.25,
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
        // Mesmo cabeçalho das outras faixas; o selo conta os eventos e a
        // seta diz que a faixa abre.
        InkWell(
          onTap: () => setState(() => _activitiesOpen = !_activitiesOpen),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: OverviewBandHeader(
              title: 'Atividades recentes',
              hint: _activitiesOpen
                  ? 'os eventos mais recentes do período'
                  : 'eventos do sistema no período · toque para ver',
              tone: OverviewTones.slate(context),
              icon: LucideIcons.activity,
              badge: _ValueTag(text: ovInt(data.activities.total)),
              trailing: AnimatedRotation(
                turns: _activitiesOpen ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                child: Icon(Icons.expand_more_rounded, color: secondary),
              ),
            ),
          ),
        ),
        if (_activitiesOpen) ...[
          if (list.isEmpty)
            const OverviewEmptyLine(
              icon: LucideIcons.activity,
              text: 'Nenhum evento no período. Cadastros, vendas e mudanças '
                  'no CRM aparecem aqui conforme acontecem.',
            )
          else
            for (final act in list.take(12))
              Builder(builder: (context) {
                final tone = toneOf(act.type);
                final sub = [
                  _firstFilled([act.description]),
                  _firstFilled([act.userName]),
                ].whereType<String>().join(' · ');
                return Container(
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
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: OverviewTones.wash(context, tone),
                        ),
                        child: Icon(iconOf(act.type), size: 14, color: tone),
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
                                height: 1.25,
                              ),
                            ),
                            if (sub.isNotEmpty)
                              Text(
                                sub,
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
                        maxLines: 1,
                        softWrap: false,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: secondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          const SizedBox(height: 6),
        ],
      ],
    );
  }

  // ─── Esqueleto ─────────────────────────────────────────────────────────────

  /// Esqueleto fiel à tela: topo com avatar, botão do período, VGV com as
  /// três leituras, curva, grade dos quatro indicadores e o funil — na mesma
  /// coluna centrada da tela larga.
  Widget _buildSkeleton(BuildContext context) {
    Widget line(double w, double h) =>
        SkeletonText(width: w, height: h, borderRadius: 5);
    final rule = Container(height: 1, color: OverviewTones.rule(context));
    Widget kpi() => Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const SkeletonBox(width: 26, height: 26, borderRadius: 8),
                  const SizedBox(width: 8),
                  line(64, 11),
                ],
              ),
              const SizedBox(height: 10),
              line(60, 24),
              const SizedBox(height: 8),
              line(104, 10),
            ],
          ),
        );
    Widget kpiRow() => Row(
          children: [
            Expanded(child: kpi()),
            const SizedBox(width: 25),
            Expanded(child: kpi()),
          ],
        );
    final viewW = MediaQuery.sizeOf(context).width;
    final side = viewW > _kMaxContentW ? (viewW - _kMaxContentW) / 2 : 0.0;
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(_kPadH + side, 10, _kPadH + side, 88),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SkeletonBox(width: 46, height: 46, borderRadius: 23),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    line(170, 22),
                    const SizedBox(height: 7),
                    line(200, 11),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Row(
            children: [
              Expanded(child: SkeletonBox(height: 48, borderRadius: 12)),
              SizedBox(width: 8),
              SkeletonBox(width: 48, height: 48, borderRadius: 12),
            ],
          ),
          const SizedBox(height: 14),
          line(240, 12),
          const SizedBox(height: 16),
          rule,
          const SizedBox(height: 18),
          line(110, 11),
          const SizedBox(height: 10),
          line(160, 36),
          const SizedBox(height: 10),
          line(220, 12),
          const SizedBox(height: 14),
          const SkeletonBox(width: double.infinity, height: 40, borderRadius: 8),
          const SizedBox(height: 18),
          rule,
          const SizedBox(height: 16),
          line(100, 11),
          const SizedBox(height: 12),
          const SkeletonBox(width: double.infinity, height: 150, borderRadius: 12),
          const SizedBox(height: 18),
          rule,
          kpiRow(),
          rule,
          kpiRow(),
          rule,
          const SizedBox(height: 18),
          Row(
            children: [
              const SkeletonBox(width: 34, height: 34, borderRadius: 10),
              const SizedBox(width: 11),
              line(150, 16),
            ],
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < 3; i++) ...[
            const SkeletonBox(width: double.infinity, height: 26, borderRadius: 6),
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
                // Selo de 15dp: o número acompanha o selo, não a fonte do
                // sistema (em 130% ele vazava da pastilha).
                child: Text(
                  '$count',
                  textScaler: TextScaler.noScaling,
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
    // Atalhos ("Hoje", "Últimos 30 dias") não têm data própria para mostrar:
    // a segunda linha repetia a primeira. Ela só aparece com as datas.
    final showPeriod = period.trim().isNotEmpty && period.trim() != word.trim();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        // Altura MÍNIMA de 48, não fixa: com texto em 130% as duas linhas
        // (palavra + datas) não cabiam em 46 cravados.
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.fromLTRB(9, 6, 8, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: OverviewTones.track(context),
            border: Border.all(color: ThemeHelpers.borderLightColor(context)),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
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
                  mainAxisSize: MainAxisSize.min,
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
                    if (showPeriod)
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

/// Carimbo da hora do dado ("Atualizado 14:32" / "Último dado 14:32"). O
/// estado vai no ÍCONE (nuvem com alerta em âmbar quando a última
/// atualização falhou); o texto fica no tom do tema, legível nos dois.
class _Stamp extends StatelessWidget {
  const _Stamp({required this.stale, required this.time});

  final bool stale;
  final String? time;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Tooltip(
      message: stale
          ? 'A última atualização falhou; a tela mostra o dado anterior'
          : 'Hora do dado que está em tela',
      child: Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              stale ? LucideIcons.cloudAlert : LucideIcons.clock3,
              size: 13,
              color: stale ? OverviewTones.amber(context) : secondary,
            ),
            const SizedBox(width: 4),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: stale ? 'Último dado' : 'Atualizado'),
                  if (time != null)
                    TextSpan(
                      text: ' $time',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                ],
              ),
              maxLines: 1,
              softWrap: false,
              style: theme.textTheme.labelSmall?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ],
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: OverviewTones.track(context),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
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
    // Rótulo em até duas linhas: em 320dp com fonte grande, "Ticket médio"
    // numa linha só virava "Ticket mé…".
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            fontWeight: FontWeight.w700,
            height: 1.2,
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

/// Linha da ficha da meta (rótulo à esquerda, valor à direita). O estado
/// (falta / batida) vem no ícone tingido antes do valor; o valor fica no tom
/// do tema — âmbar e verde como texto miúdo não passam contraste no claro.
class _GoalLine extends StatelessWidget {
  const _GoalLine({
    required this.label,
    required this.value,
    this.icon,
    this.tone,
    this.last = false,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? tone;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glyph = icon;
    final labelText = Text(
      label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: ThemeHelpers.textSecondaryColor(context),
        fontWeight: FontWeight.w600,
        height: 1.25,
      ),
    );
    // Valor com o ícone de estado. Dinheiro NUNCA sai com reticências
    // ("R$ 1,…" é um número errado): encolhe um pouco se precisar.
    Widget valueLine({required bool end}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (glyph != null) ...[
              Icon(
                glyph,
                size: 14,
                color: tone ?? ThemeHelpers.textSecondaryColor(context),
              ),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: end ? Alignment.centerRight : Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  softWrap: false,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: OverviewTones.rule(context))),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          // Faixa estreita (anel ao lado em 320dp, ou fonte grande): o valor
          // desce para baixo do rótulo. Lado a lado cada um ficava com
          // metade e o dinheiro saía cortado ("R$ 13k/d…").
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          if (c.maxWidth < 176 * scale) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                labelText,
                const SizedBox(height: 1),
                valueLine(end: false),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: labelText),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: c.maxWidth * 0.62),
                child: valueLine(end: true),
              ),
            ],
          );
        },
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

  static const double size = 108;

  /// 0–100 (já limitado).
  final double progress;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
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
          // O miolo tem ~80dp: "1.250%" ou fonte em 130% encolhem em vez de
          // vazar por cima do arco.
          SizedBox(
            width: size - 30,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: ThemeHelpers.textColor(context),
                      height: 1.0,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'atingido',
                    maxLines: 1,
                    softWrap: false,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Traço tracejado curto da legenda da meta (o mesmo desenho da linha da
/// meta na curva).
class _DashMark extends StatelessWidget {
  const _DashMark({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 2, color: color),
        const SizedBox(width: 3),
        Container(width: 6, height: 2, color: color),
      ],
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

  /// Altura do desenho (sem a faixa dos meses, que cresce com a fonte).
  static const double _plotHeight = 146;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Os rótulos acompanham a fonte do sistema até 130% (antes ficavam
    // cravados em 10px, ignorando a acessibilidade).
    final scaler = MediaQuery.textScalerOf(
      context,
    ).clamp(minScaleFactor: 1, maxScaleFactor: 1.3);
    final labelStyle = (theme.textTheme.labelSmall ?? const TextStyle()).copyWith(
      color: ThemeHelpers.textSecondaryColor(context),
      fontSize: 10,
    );
    // Margem da escada de valores medida pelo MAIOR rótulo: "R$ 12,5M" não
    // cabia nos 48dp fixos e saía "R$ 1…".
    final yMax = _CurvePainter.axisMax(values, target);
    var padL = 34.0;
    for (var k = 0; k <= 2; k++) {
      final tp = TextPainter(
        text: TextSpan(
          text: ovMoneyShort(yMax * k / 2),
          style: labelStyle.copyWith(fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      padL = math.max(padL, tp.width + 8);
      tp.dispose();
    }
    padL = math.min(padL, 88.0);
    final padB = 12 + scaler.scale(10) * 1.3;

    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        // Mês com o ano ("Mai/26") só quando cabe no vão de cada ponto (o
        // mês tocado vai em negrito, que é mais largo); em 320dp com fonte
        // grande ele saía "Mai/…" — aí fica só o mês. O ano segue na
        // leitura do mês, acima da curva.
        final slot = values.length > 1
            ? (width - padL - _CurvePainter.padR) / (values.length - 1)
            : width;
        final widestMonth = ovWidestWord(
          labels,
          labelStyle.copyWith(fontWeight: FontWeight.w900),
          scaler,
        );
        final monthLabels = widestMonth <= math.max(28.0, slot) - 2
            ? labels
            : [for (final l in labels) l.split('/').first];
        int? indexAt(double dx) {
          if (values.length < 2) return null;
          final inner = width - padL - _CurvePainter.padR;
          if (inner <= 0) return null;
          final rel = ((dx - padL) / inner).clamp(0.0, 1.0);
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
            size: Size(width, _plotHeight + padB),
            painter: _CurvePainter(
              values: values,
              labels: monthLabels,
              target: target,
              selected: selected,
              line: OverviewTones.brand(context),
              targetColor: OverviewTones.amber(context),
              grid: ThemeHelpers.borderLightColor(context),
              surface: ThemeHelpers.backgroundColor(context),
              labelStyle: labelStyle,
              strongLabelColor: ThemeHelpers.textColor(context),
              padL: padL,
              padB: padB,
              scaler: scaler,
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
    required this.padL,
    required this.padB,
    required this.scaler,
  });

  static const double padR = 14;
  static const double padT = 8;

  /// Topo do eixo: o maior valor (ou a meta, se maior) com 12% de folga.
  static double axisMax(List<double> values, double? target) {
    if (values.isEmpty) return 1;
    var maxV = values.reduce(math.max);
    if (target != null && target > maxV) maxV = target;
    return maxV <= 0 ? 1.0 : maxV * 1.12;
  }

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

  /// Margem esquerda (escada de valores) medida pelo maior rótulo.
  final double padL;

  /// Faixa dos meses, proporcional à fonte.
  final double padB;
  final TextScaler scaler;

  /// Escreve um rótulo. `middle` centraliza na vertical sobre `y` (a escada
  /// de valores acompanha a linha da grade em qualquer tamanho de fonte).
  void _text(
    Canvas canvas,
    String text,
    double x,
    double y, {
    required double maxWidth,
    bool alignRight = false,
    bool center = false,
    bool middle = false,
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
      textScaler: scaler,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(0.0, maxWidth));
    var dx = x;
    if (alignRight) dx = x + maxWidth - tp.width;
    if (center) dx = x - tp.width / 2;
    final dy = middle ? y - tp.height / 2 : y;
    tp.paint(canvas, Offset(dx, dy));
    tp.dispose();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final innerW = size.width - padL - padR;
    final innerH = size.height - padT - padB;
    if (innerW <= 0 || innerH <= 0) return;

    final t = target;
    final yMax = axisMax(values, t);

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
      _text(
        canvas,
        ovMoneyShort(v),
        0,
        yy,
        maxWidth: padL - 6,
        alignRight: true,
        middle: true,
      );
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
        size.height - padB + 7,
        maxWidth: math.max(28.0, slot),
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

/// Indicador da grade: chapa tonal com o ícone na tinta do significado,
/// número grande e a legenda com os números em negrito. Sem chapa de card e
/// sem faixa lateral — quem separa as células são os fios da grade. A seta
/// no canto diz que o toque abre o detalhe.
class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.kpi,
    required this.comparing,
    required this.onTap,
    this.stacked = false,
  });

  final _Kpi kpi;
  final bool comparing;
  final VoidCallback onTap;

  /// Célula estreita (320dp, fonte grande): o rótulo sai da linha do ícone
  /// e ganha a largura toda da célula.
  final bool stacked;

  /// Estilo do rótulo — também usado para medir se ele cabe na linha.
  static TextStyle? labelStyle(BuildContext context) =>
      Theme.of(context).textTheme.labelMedium?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            fontWeight: FontWeight.w800,
            height: 1.15,
          );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final chip = Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: OverviewTones.wash(context, kpi.tone),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(kpi.icon, size: 14, color: kpi.tone),
    );
    final chevron = Icon(
      Icons.chevron_right_rounded,
      size: 16,
      color: secondary.withValues(alpha: 0.7),
    );
    final label = Text(
      kpi.label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: labelStyle(context),
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (stacked) ...[
              Row(children: [chip, const Spacer(), chevron]),
              const SizedBox(height: 7),
              label,
            ] else
              Row(
                children: [
                  chip,
                  const SizedBox(width: 8),
                  Expanded(child: label),
                  chevron,
                ],
              ),
            const SizedBox(height: 8),
            // Número e selo em `Wrap`: o selo desce quando não cabe ao lado,
            // em vez de o número (a leitura que importa) encolher pela metade
            // numa célula de 130dp.
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    kpi.value,
                    maxLines: 1,
                    softWrap: false,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: textColor,
                      letterSpacing: -0.8,
                      height: 1.0,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                // Sem comparação ligada o selo diria "— 0,0%" nos quatro.
                if (comparing) OverviewDeltaChip(value: kpi.delta, compact: true),
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
              maxLines: 3,
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
  const _FunnelStep({
    required this.stage,
    required this.previousWidth,
    required this.labelWidth,
  });

  final _FunnelStage stage;
  final double? previousWidth;

  /// Coluna do nome da etapa (proporcional à largura da faixa).
  final double labelWidth;

  /// Véu da perda (e da legenda dele, abaixo do funil). Um degrau mais
  /// visível que antes: a 6% no claro a perda quase sumia no branco.
  static Color lossVeil(BuildContext context) => OverviewTones.red(context)
      .withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? 0.14 : 0.09,
      );

  /// Borda que marca onde a etapa anterior terminava.
  static Color lossEdge(BuildContext context) =>
      OverviewTones.red(context).withValues(alpha: 0.5);

  /// Estilo do nome da etapa — também usado para medir a coluna.
  static TextStyle? labelStyle(BuildContext context) =>
      Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: ThemeHelpers.textColor(context),
            height: 1.2,
          );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final w = (stage.width / 100).clamp(0.0, 1.0).toDouble();
    final pw = ((previousWidth ?? 0) / 100).clamp(0.0, 1.0).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              stage.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: labelStyle(context),
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
                          color: lossVeil(context),
                          borderRadius: BorderRadius.circular(4),
                          border: Border(
                            right: BorderSide(
                              color: lossEdge(context),
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
          // Largura MÍNIMA (não fixa): "12.345" com fonte grande cresce e a
          // régua cede, em vez de o número ser cortado.
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 56),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ovInt(stage.value),
                  maxLines: 1,
                  softWrap: false,
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
                  softWrap: false,
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
    this.last = false,
  });

  final _RankRow row;
  final bool selected;
  final VoidCallback onTap;

  /// Última linha da lista: sem filete (o fio da faixa vem logo abaixo).
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final brand = OverviewTones.brand(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    // Pódio em UMA tinta com peso decrescente (posição é ordem, não
    // significado): 1º medalha âmbar, 2º e 3º medalha pedra, o resto só o
    // número. O número da medalha fica no tom do texto (contraste).
    final medal = row.rank == 1
        ? OverviewTones.amber(context)
        : row.rank <= 3
            ? OverviewTones.slate(context)
            : null;
    return Tooltip(
      message: selected
          ? 'Voltar a ver toda a equipe'
          : 'Ver a tela só com os números deste corretor',
      child: InkWell(
        onTap: onTap,
        // Linha filtrada: véu da marca na linha inteira + "x" para soltar
        // (sem faixa lateral).
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 10, 2, 10),
          decoration: BoxDecoration(
            color: selected
                ? brand.withValues(alpha: isDark ? 0.12 : 0.06)
                : null,
            border: last
                ? null
                : Border(
                    bottom: BorderSide(color: OverviewTones.rule(context)),
                  ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: medal != null
                      ? Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: OverviewTones.wash(context, medal),
                            border: Border.all(
                              color: medal.withValues(alpha: 0.6),
                            ),
                          ),
                          child: Text(
                            '${row.rank}',
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900,
                              color: textColor,
                              height: 1,
                            ),
                          ),
                        )
                      : Text(
                          '${row.rank}º',
                          maxLines: 1,
                          softWrap: false,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: secondary,
                          ),
                        ),
                ),
              ),
              OverviewAvatar(name: row.name, url: row.avatar, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nome em até duas linhas: em 320dp com fonte grande a
                    // coluna tem ~90dp e uma linha só virava "Ana Beatri…" —
                    // no ranking, saber QUEM é a leitura principal.
                    Text(
                      row.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight:
                            selected ? FontWeight.w900 : FontWeight.w800,
                        color: textColor,
                        height: 1.2,
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
                width: 22,
                child: selected
                    ? Icon(Icons.close_rounded, size: 16, color: brand)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
