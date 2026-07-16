import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/automation_models.dart';
import '../services/automation_service.dart';
import '../widgets/automation_card.dart';

/// Aba ativa da tela de automações (filtro local sobre a lista carregada).
enum _AutomationTab { active, attention, all }

/// Tela **Automações** (`/automations`) — paridade com AutomationsPage.tsx do
/// imobx-front: lista das automações da empresa com toggle ativar/desativar no
/// próprio item. Gate: role admin/master (AdminRoute) + módulo `automations`
/// (ModuleRoute). Mesmo DNA das telas canônicas: hero flush com eyebrow +
/// contagem + KPIs, abas flush com sublinhado, conteúdo nas margens.
class AutomationsPage extends StatefulWidget {
  const AutomationsPage({super.key});

  @override
  State<AutomationsPage> createState() => _AutomationsPageState();
}

class _AutomationsPageState extends State<AutomationsPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 110;
  static const double _kSectionGap = 12;

  List<Automation> _automations = const [];
  bool _loading = true;
  String? _error;
  _AutomationTab _activeTab = _AutomationTab.active;

  /// Ids com PATCH de toggle em andamento (trava o switch do item).
  final Set<String> _togglingIds = {};

  // ─── Gate (paridade automations.routes.tsx: AdminRoute + ModuleRoute) ──────

  bool get _isPrivileged {
    final role = ModuleAccessService.instance.userRole?.toLowerCase().trim();
    return role == 'admin' || role == 'master';
  }

  bool get _hasModule =>
      ModuleAccessService.instance.hasCompanyModule('automations');

  @override
  void initState() {
    super.initState();
    if (_isPrivileged && _hasModule) {
      _load();
    } else {
      _loading = false;
    }
  }

  Color _accent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.primary.primaryDarkMode
          : AppColors.primary.primary;

  // ─── Dados ──────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await AutomationService.instance.getAutomations();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _automations = res.data!;
      } else {
        _error = res.message ?? 'Erro ao carregar automações';
      }
    });
  }

  Future<void> _toggle(Automation automation, bool value) async {
    setState(() => _togglingIds.add(automation.id));
    final res = await AutomationService.instance.toggle(automation.id, value);
    if (!mounted) return;
    setState(() {
      _togglingIds.remove(automation.id);
      if (res.success && res.data != null) {
        _automations = _automations
            .map((a) => a.id == automation.id ? res.data! : a)
            .toList();
      }
    });
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    if (res.success) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'Automação ativada com sucesso!'
                : 'Automação desativada com sucesso!',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(res.message ?? 'Erro ao alternar automação'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openCreate() async {
    await Navigator.of(context).pushNamed('/automations/create');
    // Recarrega sempre ao voltar — o botão voltar do AppScaffold faz pop sem
    // resultado, então não dá pra confiar só no retorno.
    if (mounted) _load();
  }

  Future<void> _openDetails(Automation automation) async {
    await Navigator.of(context).pushNamed('/automations/${automation.id}');
    if (mounted) _load();
  }

  // ─── Derivados ──────────────────────────────────────────────────────────

  List<Automation> get _activeList =>
      _automations.where((a) => a.isActive).toList();
  List<Automation> get _attentionList =>
      _automations.where((a) => a.hasFailures).toList();

  List<Automation> _listFor(_AutomationTab tab) {
    switch (tab) {
      case _AutomationTab.active:
        return _activeList;
      case _AutomationTab.attention:
        return _attentionList;
      case _AutomationTab.all:
        return _automations;
    }
  }

  int get _totalExecutions =>
      _automations.fold(0, (sum, a) => sum + a.executionCount);
  int get _totalSuccess =>
      _automations.fold(0, (sum, a) => sum + a.successfulExecutions);
  int get _totalFailures =>
      _automations.fold(0, (sum, a) => sum + a.failedExecutions);

  Color _tabColor(BuildContext context, _AutomationTab tab) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (tab) {
      case _AutomationTab.active:
        return isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
      case _AutomationTab.attention:
        return isDark
            ? AppColors.status.warningDarkMode
            : AppColors.status.warning;
      case _AutomationTab.all:
        return _accent(context);
    }
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_isPrivileged) {
      return const AppScaffold(
        title: 'Automações',
        showBottomNavigation: false,
        body: _RestrictedView(
          icon: LucideIcons.lock,
          title: 'Acesso restrito',
          message: 'A gestão de automações é restrita a administradores '
              'da empresa.',
        ),
      );
    }
    if (!_hasModule) {
      return const AppScaffold(
        title: 'Automações',
        showBottomNavigation: false,
        body: _RestrictedView(
          icon: LucideIcons.zapOff,
          title: 'Módulo não disponível',
          message: 'Seu plano não inclui acesso ao módulo de Automações. '
              'Faça upgrade para o Plano Pro.',
        ),
      );
    }

    final accent = _accent(context);
    return AppScaffold(
      title: 'Automações',
      showBottomNavigation: false,
      body: Stack(
        children: [
          RefreshIndicator(
            color: accent,
            onRefresh: _load,
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(minHeight: constraints.maxHeight),
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
                          ],
                        ),
                      ),
                      _buildTabsRail(context),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(_kPagePadH,
                            _kSectionGap, _kPagePadH, _kPagePadBottom),
                        child: _buildActivePanel(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Nova automação — ação primária da tela (paridade com o botão do web).
          Positioned(
            right: 16,
            bottom: 24,
            child: FloatingActionButton.extended(
              heroTag: 'automations-fab',
              onPressed: _openCreate,
              backgroundColor: accent,
              foregroundColor: Colors.white,
              elevation: 3,
              icon: const Icon(LucideIcons.plus, size: 19),
              label: const Text(
                'Nova automação',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Hero editorial ─────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accent(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    final blue = isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;

    final total = _automations.length;
    final activeCount = _activeList.length;
    final hasIssues = _attentionList.isNotEmpty;
    final dot = hasIssues ? amber : emerald;
    final subtitle = _loading
        ? 'Carregando as automações da empresa…'
        : total == 0
            ? 'Crie rotinas que avisam sua equipe e seus clientes sozinhas.'
            : hasIssues
                ? '$activeCount ativa${activeCount == 1 ? '' : 's'} · '
                    '${_attentionList.length} precisa${_attentionList.length == 1 ? '' : 'm'} de atenção'
                : activeCount == 0
                    ? 'Nenhuma automação ativa no momento.'
                    : '$activeCount ativa${activeCount == 1 ? '' : 's'} — tudo rodando sem falhas.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dot,
                  boxShadow: [
                    BoxShadow(
                      color: dot.withValues(alpha: 0.55),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 9),
              Text(
                'AUTOMAÇÕES',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.2,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _loading ? '—' : '$total',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: textColor,
                  height: 1.0,
                  letterSpacing: -1.0,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  total == 1 ? 'automação' : 'automações',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: secondary,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          _buildKpiStrip(context, emerald, blue, amber),
        ],
      ),
    );
  }

  Widget _buildKpiStrip(
      BuildContext context, Color emerald, Color blue, Color amber) {
    final divider = ThemeHelpers.borderColor(context).withValues(alpha: 0.45);
    final blocks = <Widget>[
      _heroKpiBlock(
        context,
        LucideIcons.zap,
        'ATIVAS',
        _loading ? '—' : '${_activeList.length}',
        'de ${_automations.length} no total',
        emerald,
      ),
      _heroKpiBlock(
        context,
        LucideIcons.activity,
        'EXECUÇÕES',
        _loading ? '—' : '$_totalExecutions',
        '$_totalSuccess com sucesso',
        blue,
      ),
      _heroKpiBlock(
        context,
        LucideIcons.triangleAlert,
        'FALHAS',
        _loading ? '—' : '$_totalFailures',
        _totalFailures == 0 ? 'nenhuma falha' : 'para investigar',
        amber,
      ),
    ];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < blocks.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: divider,
              ),
            Expanded(child: blocks[i]),
          ],
        ],
      ),
    );
  }

  Widget _heroKpiBlock(BuildContext context, IconData icon, String label,
      String value, String sub, Color tone) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: tone),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: tone,
                    letterSpacing: 1.2,
                    height: 1.0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: tone,
                letterSpacing: -0.6,
                height: 1.0,
                fontSize: 22,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            sub,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: secondary,
              height: 1.0,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 7),
          Container(
            height: 2,
            width: 18,
            decoration: BoxDecoration(
              color: tone,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Abas flush (sublinhado) ────────────────────────────────────────────

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
          for (final tab in _AutomationTab.values)
            Expanded(
              child: _FlushTab(
                icon: _tabIcon(tab),
                label: _tabLabel(tab),
                count: _listFor(tab).length,
                tone: _tabColor(context, tab),
                selected: _activeTab == tab,
                onTap: () => setState(() => _activeTab = tab),
              ),
            ),
        ],
      ),
    );
  }

  IconData _tabIcon(_AutomationTab tab) {
    switch (tab) {
      case _AutomationTab.active:
        return LucideIcons.zap;
      case _AutomationTab.attention:
        return LucideIcons.triangleAlert;
      case _AutomationTab.all:
        return LucideIcons.layers;
    }
  }

  String _tabLabel(_AutomationTab tab) {
    switch (tab) {
      case _AutomationTab.active:
        return 'Ativas';
      case _AutomationTab.attention:
        return 'Atenção';
      case _AutomationTab.all:
        return 'Todas';
    }
  }

  ({IconData icon, String eyebrow, String title, String hint}) _panelMeta(
      _AutomationTab tab) {
    switch (tab) {
      case _AutomationTab.active:
        return (
          icon: LucideIcons.zap,
          eyebrow: 'ATIVAS',
          title: 'Rodando agora',
          hint: 'Automações ligadas, notificando sua equipe e seus clientes.',
        );
      case _AutomationTab.attention:
        return (
          icon: LucideIcons.triangleAlert,
          eyebrow: 'ATENÇÃO',
          title: 'Com falhas registradas',
          hint: 'Automações com erros de execução — abra o histórico para '
              'investigar.',
        );
      case _AutomationTab.all:
        return (
          icon: LucideIcons.layers,
          eyebrow: 'TODAS',
          title: 'Todas as automações',
          hint: 'Tudo que está configurado na empresa, ativo ou não.',
        );
    }
  }

  // ─── Painel ativo ───────────────────────────────────────────────────────

  Widget _buildActivePanel(BuildContext context) {
    final list = _listFor(_activeTab);
    Widget child;
    if (_loading) {
      child = _buildSkeleton();
    } else if (_error != null) {
      child = _buildError(context, _error!);
    } else if (list.isEmpty) {
      child = _buildEmpty(context, _activeTab);
    } else {
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < list.length; i++)
            AutomationCard(
              automation: list[i],
              toggling: _togglingIds.contains(list[i].id),
              onToggle: (v) => _toggle(list[i], v),
              onTap: () => _openDetails(list[i]),
            ).animate(key: ValueKey('a-${list[i].id}')).fadeIn(
                  delay: Duration(milliseconds: 30 * i.clamp(0, 12)),
                  duration: 220.ms,
                ),
        ],
      );
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

  Widget _buildPanelHeader(BuildContext context, _AutomationTab tab) {
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

  // ─── Estados ────────────────────────────────────────────────────────────

  /// Skeleton fiel ao [AutomationCard]: glyph + pill + título + descrição +
  /// bits + switch.
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
                    SkeletonText(width: 88, height: 16, borderRadius: 999),
                    SizedBox(height: 9),
                    SkeletonText(width: double.infinity, height: 15),
                    SizedBox(height: 6),
                    SkeletonText(width: double.infinity, height: 12),
                    SizedBox(height: 6),
                    SkeletonText(width: 170, height: 11),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SkeletonBox(width: 40, height: 22, borderRadius: 999),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, _AutomationTab tab) {
    final theme = Theme.of(context);
    final tone = _tabColor(context, tab);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final noneAtAll = _automations.isEmpty;
    final (icon, title, body) = noneAtAll
        ? (
            LucideIcons.bot,
            'Nenhuma automação configurada',
            'Comece criando sua primeira automação a partir de um template. '
                'Elas mantêm processos organizados e clientes informados.',
          )
        : switch (tab) {
            _AutomationTab.active => (
                LucideIcons.zapOff,
                'Nenhuma automação ativa',
                'Ative uma automação pelo interruptor do item para ela voltar '
                    'a disparar.',
              ),
            _AutomationTab.attention => (
                LucideIcons.partyPopper,
                'Nada precisa de atenção',
                'Nenhuma automação registrou falhas de execução.',
              ),
            _AutomationTab.all => (
                LucideIcons.bot,
                'Nenhuma automação',
                'As automações configuradas na empresa aparecem aqui.',
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
          if (noneAtAll) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _openCreate,
              style: OutlinedButton.styleFrom(
                foregroundColor: _accent(context),
                side: BorderSide(
                  color: _accent(context).withValues(alpha: 0.45),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('Criar primeira automação'),
            ),
          ],
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
            onPressed: _load,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}

// ─── Aba flush (ícone + rótulo + contagem + sublinhado) ──────────────────────

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

// ─── Bloqueios (sem role / sem módulo) ──────────────────────────────────────

class _RestrictedView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _RestrictedView({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 38, color: secondary),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: secondary, fontSize: 12.5, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
