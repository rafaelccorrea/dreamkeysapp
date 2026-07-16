import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/collection_models.dart';
import '../services/collection_service.dart';
import '../widgets/collection_rule_card.dart';

/// Aba da lista de réguas.
enum _RulesTab { all, active, inactive }

/// Tela **Regras da Régua de Cobrança** (`/collection/rules`) — paridade com
/// a `CollectionRulesPage.tsx` do imobx-front: lista as réguas configuradas
/// com ações no próprio item (ativar/pausar, excluir), criação de réguas
/// padrão quando a empresa ainda não tem nenhuma e atalho para nova régua.
class CollectionRulesPage extends StatefulWidget {
  const CollectionRulesPage({super.key});

  @override
  State<CollectionRulesPage> createState() => _CollectionRulesPageState();
}

class _CollectionRulesPageState extends State<CollectionRulesPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 88;
  static const double _kSectionGap = 12;

  static const _tabs = [_RulesTab.all, _RulesTab.active, _RulesTab.inactive];

  _RulesTab _activeTab = _RulesTab.all;

  List<CollectionRule> _rules = const [];
  bool _loading = true;
  String? _error;
  bool _creatingDefault = false;
  final Set<String> _togglingIds = {};

  bool get _canManage =>
      ModuleAccessService.instance.hasPermission(CollectionAccess.manage);

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  // ─── Cores ───────────────────────────────────────────────────────────────

  Color _accentColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
  }

  Color _tabColor(BuildContext context, _RulesTab tab) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (tab) {
      case _RulesTab.all:
        return _accentColor(context);
      case _RulesTab.active:
        return isDark
            ? AppColors.status.greenDarkMode
            : AppColors.status.green;
      case _RulesTab.inactive:
        return ThemeHelpers.textSecondaryColor(context);
    }
  }

  // ─── Dados ───────────────────────────────────────────────────────────────

  Future<void> _loadRules() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await CollectionService.instance.getRules();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        final list = [...res.data!];
        // Prioridade menor primeiro (ordem de disparo), depois nome.
        list.sort((a, b) {
          final p = a.priority.compareTo(b.priority);
          return p != 0 ? p : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        _rules = list;
      } else {
        _error = res.message ?? 'Erro ao carregar réguas';
      }
    });
  }

  List<CollectionRule> _listFor(_RulesTab tab) {
    switch (tab) {
      case _RulesTab.all:
        return _rules;
      case _RulesTab.active:
        return _rules.where((r) => r.isActive).toList();
      case _RulesTab.inactive:
        return _rules.where((r) => !r.isActive).toList();
    }
  }

  int get _activeCount => _rules.where((r) => r.isActive).length;

  // ─── Ações ───────────────────────────────────────────────────────────────

  void _openForm({String? ruleId}) {
    final route =
        ruleId == null ? '/collection/rules/new' : '/collection/rules/$ruleId';
    Navigator.of(context).pushNamed(route).then((changed) {
      if (mounted && changed == true) _loadRules();
    });
  }

  Future<void> _toggle(CollectionRule rule) async {
    if (_togglingIds.contains(rule.id)) return;
    setState(() => _togglingIds.add(rule.id));
    final res = await CollectionService.instance.toggleRule(rule.id);
    if (!mounted) return;
    setState(() => _togglingIds.remove(rule.id));
    if (res.success) {
      await _loadRules();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message ?? 'Erro ao alternar régua'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmDelete(CollectionRule rule) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: ThemeHelpers.cardBackgroundColor(ctx),
        title: Text(
          'Excluir régua',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
            color: ThemeHelpers.textColor(ctx),
          ),
        ),
        content: Text(
          'Deseja realmente excluir a régua "${rule.name}"? '
          'Essa ação não pode ser desfeita.',
          style: TextStyle(
            color: ThemeHelpers.textSecondaryColor(ctx),
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: ThemeHelpers.textSecondaryColor(ctx),
            ),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: danger,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(LucideIcons.trash2, size: 16),
            label: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final res = await CollectionService.instance.deleteRule(rule.id);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (res.success) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Régua excluída com sucesso!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadRules();
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(res.message ?? 'Erro ao excluir régua'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmCreateDefault() async {
    if (_rules.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Esta empresa já possui réguas. Não é possível criar as padrão novamente.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final accent = _accentColor(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: ThemeHelpers.cardBackgroundColor(ctx),
        title: Text(
          'Criar réguas padrão',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
            color: ThemeHelpers.textColor(ctx),
          ),
        ),
        content: Text(
          'Deseja criar as réguas padrão? Isso adicionará 4 réguas '
          'pré-configuradas de lembrete e cobrança.',
          style: TextStyle(
            color: ThemeHelpers.textSecondaryColor(ctx),
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: ThemeHelpers.textSecondaryColor(ctx),
            ),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(LucideIcons.sparkles, size: 16),
            label: const Text('Criar réguas'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _creatingDefault = true);
    final res = await CollectionService.instance.createDefaultRules();
    if (!mounted) return;
    setState(() => _creatingDefault = false);
    final messenger = ScaffoldMessenger.of(context);
    if (res.success) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Réguas padrão criadas com sucesso!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadRules();
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(res.message ?? 'Erro ao criar réguas padrão'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canManage) {
      return const AppScaffold(
        title: 'Regras da Régua',
        showBottomNavigation: false,
        body: _DeniedView(),
      );
    }
    return AppScaffold(
      title: 'Regras da Régua',
      showBottomNavigation: false,
      body: RefreshIndicator(
        color: _accentColor(context),
        onRefresh: _loadRules,
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
                        const SizedBox(height: 16),
                        _buildActions(context),
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

  // ─── Hero: rack da automação ─────────────────────────────────────────────
  //
  // Irmão da tela da régua (linha do tempo): aqui a identidade é o "rack" de
  // regras — um segmento por regra, aceso quando ativa, apagado quando
  // pausada — com a leitura "X de N ativas". Sem número gigante nem dot
  // pulsante.

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;

    final total = _rules.length;
    final active = _activeCount;
    final inactive = total - active;
    final running = total > 0 && active > 0;
    final tone = running ? emerald : amber;
    final subtitle = total == 0
        ? 'Nenhuma regra configurada — comece pelas réguas padrão.'
        : active == 0
            ? 'Todas as regras estão pausadas — nada será enviado.'
            : '$active ativa${active == 1 ? '' : 's'}'
                '${inactive > 0 ? ' · $inactive pausada${inactive == 1 ? '' : 's'}' : ' — régua rodando todos os dias.'}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  color: tone.withValues(alpha: isDark ? 0.18 : 0.1),
                  border: Border.all(color: tone.withValues(alpha: 0.3)),
                ),
                child: Icon(
                  running ? LucideIcons.zap : LucideIcons.zapOff,
                  color: tone,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Regras da régua',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -0.5,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      running
                          ? 'Automação ligada'
                          : total == 0
                              ? 'Automação sem regras'
                              : 'Automação pausada',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tone,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                'RACK DE REGRAS',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: secondary,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                  fontSize: 9.5,
                ),
              ),
              const Spacer(),
              Text(
                _loading && _rules.isEmpty
                    ? '—'
                    : total == 0
                        ? 'vazio'
                        : '$active de $total ativa${total == 1 ? '' : 's'}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: running ? emerald : secondary,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Um segmento por regra: aceso = ativa, apagado = pausada.
          SizedBox(
            height: 8,
            child: total == 0
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: Container(
                      color: ThemeHelpers.borderColor(context)
                          .withValues(alpha: 0.4),
                    ),
                  )
                : Row(
                    children: [
                      for (var i = 0; i < _rules.length; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOut,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(99),
                              color: _rules[i].isActive
                                  ? emerald
                                  : ThemeHelpers.borderColor(context)
                                      .withValues(alpha: 0.55),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 10),
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
    );
  }

  Widget _buildActions(BuildContext context) {
    final accent = _accentColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final defaultDisabled = _rules.isNotEmpty || _creatingDefault || _loading;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: defaultDisabled ? null : _confirmCreateDefault,
            icon: _creatingDefault
                ? SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: secondary,
                    ),
                  )
                : const Icon(LucideIcons.sparkles, size: 16),
            label: Text(
              _creatingDefault ? 'Criando…' : 'Réguas padrão',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: ThemeHelpers.textColor(context),
              side: BorderSide(color: secondary.withValues(alpha: 0.35)),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            onPressed: () => _openForm(),
            icon: const Icon(LucideIcons.plus, size: 16),
            label: const Text(
              'Nova régua',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
              ),
              elevation: 0,
            ),
          ),
        ),
      ],
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

  IconData _tabIcon(_RulesTab tab) {
    switch (tab) {
      case _RulesTab.all:
        return LucideIcons.listChecks;
      case _RulesTab.active:
        return LucideIcons.play;
      case _RulesTab.inactive:
        return LucideIcons.pause;
    }
  }

  String _tabLabel(_RulesTab tab) {
    switch (tab) {
      case _RulesTab.all:
        return 'Todas';
      case _RulesTab.active:
        return 'Ativas';
      case _RulesTab.inactive:
        return 'Pausadas';
    }
  }

  // ─── Painel ativo ────────────────────────────────────────────────────────

  Widget _buildActivePanel(BuildContext context) {
    final list = _listFor(_activeTab);
    Widget child;
    if (_loading && _rules.isEmpty) {
      child = _buildSkeleton();
    } else if (_error != null && _rules.isEmpty) {
      child = _buildError(context, _error!);
    } else if (list.isEmpty) {
      child = _buildEmpty(context, _activeTab);
    } else {
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < list.length; i++)
            CollectionRuleCard(
              rule: list[i],
              canManage: _canManage,
              onTap: () => _openForm(ruleId: list[i].id),
              onToggle: () => _toggle(list[i]),
              onDelete: () => _confirmDelete(list[i]),
            ).animate(key: ValueKey('r-${list[i].id}')).fadeIn(
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

  ({IconData icon, String eyebrow, String title, String hint}) _panelMeta(
      _RulesTab tab) {
    switch (tab) {
      case _RulesTab.all:
        return (
          icon: LucideIcons.listChecks,
          eyebrow: 'TODAS',
          title: 'Regras configuradas',
          hint: 'Em ordem de prioridade — toque para editar uma regra.',
        );
      case _RulesTab.active:
        return (
          icon: LucideIcons.play,
          eyebrow: 'ATIVAS',
          title: 'Rodando na régua',
          hint: 'Estas regras disparam cobranças no horário configurado.',
        );
      case _RulesTab.inactive:
        return (
          icon: LucideIcons.pause,
          eyebrow: 'PAUSADAS',
          title: 'Fora da régua',
          hint: 'Regras desativadas — reative para voltarem a disparar.',
        );
    }
  }

  Widget _buildPanelHeader(BuildContext context, _RulesTab tab) {
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

  // ─── Estados ─────────────────────────────────────────────────────────────

  Widget _buildSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(
        4,
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
                    SkeletonText(width: 72, height: 16, borderRadius: 999),
                    SizedBox(height: 9),
                    SkeletonText(width: double.infinity, height: 14),
                    SizedBox(height: 6),
                    SkeletonText(width: 190, height: 12),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const SkeletonBox(width: 32, height: 70, borderRadius: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, _RulesTab tab) {
    final theme = Theme.of(context);
    final tone = _tabColor(context, tab);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final (icon, title, body) = switch (tab) {
      _RulesTab.all => (
          LucideIcons.settings2,
          'Nenhuma regra ainda',
          'Toque em "Réguas padrão" para começar com 4 regras prontas, ou crie a sua.',
        ),
      _RulesTab.active => (
          LucideIcons.pause,
          'Nenhuma regra ativa',
          'Reative uma regra pausada ou crie uma nova para a régua voltar a rodar.',
        ),
      _RulesTab.inactive => (
          LucideIcons.circleCheckBig,
          'Nenhuma pausada',
          'Todas as suas regras estão ativas e rodando.',
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
            onPressed: _loadRules,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}

// ─── Aba flush ───────────────────────────────────────────────────────────────

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
              'Você não tem acesso às regras da régua de cobrança.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Solicite ao administrador a permissão de gerenciar cobranças.',
              textAlign: TextAlign.center,
              style: TextStyle(color: secondary, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
