import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/unit_model.dart';
import '../organization_access.dart';
import '../services/unit_service.dart';
import '../widgets/org_ui.dart';
import '../widgets/unit_editor_sheet.dart';

/// Filtro de status da lista (paridade `StatusFilter` do UnitsPage.tsx).
enum _UnitFilter { all, active, inactive }

/// Tela **Unidades** (filiais) — lista + CRUD, paridade com o `UnitsPage.tsx`
/// do painel. Gramática das telas-cânone: hero flush com eyebrow + KPIs,
/// busca flush, abas com sublinhado, ações no próprio item.
class OrganizationUnitsPage extends StatefulWidget {
  const OrganizationUnitsPage({super.key});

  @override
  State<OrganizationUnitsPage> createState() => _OrganizationUnitsPageState();
}

class _OrganizationUnitsPageState extends State<OrganizationUnitsPage> {
  static const double _kPagePadH = 16;
  static const double _kPagePadTop = 10;
  static const double _kPagePadBottom = 88;
  static const double _kSectionGap = 12;

  List<OrgUnit> _units = const [];
  bool _loading = true;
  String? _error;

  _UnitFilter _filter = _UnitFilter.all;
  final TextEditingController _searchController = TextEditingController();
  String _search = '';

  /// Unidade com toggle de ativação em curso (trava o botão).
  String? _togglingId;

  bool get _canView => OrganizationAccess.canViewUnits();
  bool get _canManage => OrganizationAccess.canManageUnits();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ─── Cores ───────────────────────────────────────────────────────────────

  Color get _accent => Theme.of(context).brightness == Brightness.dark
      ? AppColors.status.purpleDarkMode
      : AppColors.status.purple;

  Color get _green => Theme.of(context).brightness == Brightness.dark
      ? AppColors.status.greenDarkMode
      : AppColors.status.green;

  Color get _amber => Theme.of(context).brightness == Brightness.dark
      ? AppColors.status.warningDarkMode
      : AppColors.status.warning;

  Color get _blue => Theme.of(context).brightness == Brightness.dark
      ? AppColors.status.infoDarkMode
      : AppColors.status.info;

  Color get _danger => Theme.of(context).brightness == Brightness.dark
      ? AppColors.status.errorDarkMode
      : AppColors.status.error;

  Color _filterTone(_UnitFilter f) {
    switch (f) {
      case _UnitFilter.all:
        return _accent;
      case _UnitFilter.active:
        return _green;
      case _UnitFilter.inactive:
        return _amber;
    }
  }

  // ─── Dados ───────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await UnitService.instance.list();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _units = res.data!;
      } else {
        _error = res.message ?? 'Erro ao carregar unidades';
      }
    });
  }

  List<OrgUnit> get _visibleUnits {
    final q = _search.trim().toLowerCase();
    return _units.where((u) {
      if (_filter == _UnitFilter.active && !u.isActive) return false;
      if (_filter == _UnitFilter.inactive && u.isActive) return false;
      if (q.isEmpty) return true;
      return u.name.toLowerCase().contains(q) ||
          (u.description ?? '').toLowerCase().contains(q) ||
          u.managers.any((m) => m.name.toLowerCase().contains(q));
    }).toList();
  }

  int _filterCount(_UnitFilter f) {
    switch (f) {
      case _UnitFilter.all:
        return _units.length;
      case _UnitFilter.active:
        return _units.where((u) => u.isActive).length;
      case _UnitFilter.inactive:
        return _units.where((u) => !u.isActive).length;
    }
  }

  // ─── Ações ───────────────────────────────────────────────────────────────

  void _openEditor({OrgUnit? unit}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => UnitEditorSheet(unit: unit, onSaved: _load),
    );
  }

  Future<void> _toggleActive(OrgUnit unit) async {
    setState(() => _togglingId = unit.id);
    final res =
        await UnitService.instance.update(unit.id, isActive: !unit.isActive);
    if (!mounted) return;
    setState(() => _togglingId = null);
    if (res.success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text(unit.isActive ? 'Unidade desativada' : 'Unidade ativada'),
      ));
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message ?? 'Erro ao atualizar status')),
      );
    }
  }

  Future<void> _confirmDelete(OrgUnit unit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Excluir unidade'),
        content: Text(
          'Tem certeza que deseja excluir a unidade "${unit.name}"? '
          'As equipes vinculadas devem ser movidas antes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final res = await UnitService.instance.remove(unit.id);
    if (!mounted) return;
    if (res.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unidade excluída')),
      );
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message ?? 'Erro ao excluir unidade')),
      );
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canView) {
      return const AppScaffold(
        title: 'Unidades',
        showBottomNavigation: false,
        body: OrgDeniedView(
          message: 'Você não tem acesso às unidades.',
          hint: 'Solicite ao administrador o acesso de visualizar unidades.',
        ),
      );
    }
    return AppScaffold(
      title: 'Unidades',
      showBottomNavigation: false,
      body: RefreshIndicator(
        color: _accent,
        onRefresh: _load,
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
                        OrgSearchField(
                          controller: _searchController,
                          hint: 'Buscar por nome, descrição, gestor…',
                          accent: _accent,
                          onChanged: (v) => setState(() => _search = v),
                        ),
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

  // ─── Hero ────────────────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    final total = _units.length;
    final active = _units.where((u) => u.isActive).length;
    final teams = _units.fold<int>(0, (acc, u) => acc + u.teamCount);
    final managers = _units.fold<int>(0, (acc, u) => acc + u.managers.length);
    final dot = active > 0 ? _green : _amber;
    final subtitle = total == 0
        ? 'Estruture a operação em filiais: cada unidade agrupa equipes e '
            'gestores.'
        : '$active em operação · $teams equipe${teams == 1 ? '' : 's'} '
            'vinculada${teams == 1 ? '' : 's'}';

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
                'UNIDADES & FILIAIS',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _accent,
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
                  total == 1 ? 'unidade' : 'unidades',
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
          OrgHeroKpiStrip(blocks: [
            OrgHeroKpi(
              icon: LucideIcons.circleCheckBig,
              label: 'ATIVAS',
              value: _loading ? '—' : '$active',
              sub: 'em operação',
              tone: _green,
            ),
            OrgHeroKpi(
              icon: LucideIcons.users2,
              label: 'EQUIPES',
              value: _loading ? '—' : '$teams',
              sub: 'vinculadas',
              tone: _blue,
            ),
            OrgHeroKpi(
              icon: LucideIcons.userCog,
              label: 'GESTORES',
              value: _loading ? '—' : '$managers',
              sub: 'designados',
              tone: _accent,
            ),
          ]),
        ],
      ),
    );
  }

  // ─── Abas ────────────────────────────────────────────────────────────────

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
          for (final f in _UnitFilter.values)
            Expanded(
              child: OrgFlushTab(
                icon: switch (f) {
                  _UnitFilter.all => LucideIcons.building2,
                  _UnitFilter.active => LucideIcons.circleCheckBig,
                  _UnitFilter.inactive => LucideIcons.circlePause,
                },
                label: switch (f) {
                  _UnitFilter.all => 'Todas',
                  _UnitFilter.active => 'Ativas',
                  _UnitFilter.inactive => 'Inativas',
                },
                count: _filterCount(f),
                tone: _filterTone(f),
                selected: _filter == f,
                onTap: () => setState(() => _filter = f),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Painel ──────────────────────────────────────────────────────────────

  ({IconData icon, String eyebrow, String title, String hint}) _panelMeta() {
    switch (_filter) {
      case _UnitFilter.all:
        return (
          icon: LucideIcons.building2,
          eyebrow: 'TODAS',
          title: 'Unidades da empresa',
          hint: 'Filiais com suas equipes e gestores designados.',
        );
      case _UnitFilter.active:
        return (
          icon: LucideIcons.circleCheckBig,
          eyebrow: 'ATIVAS',
          title: 'Em operação',
          hint: 'Unidades ativas — recebem equipes e fichas normalmente.',
        );
      case _UnitFilter.inactive:
        return (
          icon: LucideIcons.circlePause,
          eyebrow: 'INATIVAS',
          title: 'Pausadas',
          hint: 'Unidades desativadas — reative quando voltar a operar.',
        );
    }
  }

  Widget _buildActivePanel(BuildContext context) {
    final meta = _panelMeta();
    Widget child;
    if (_loading && _units.isEmpty) {
      child = _buildSkeleton();
    } else if (_error != null && _units.isEmpty) {
      child = OrgErrorState(message: _error!, onRetry: _load);
    } else if (_visibleUnits.isEmpty) {
      child = _buildEmpty(context);
    } else {
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _visibleUnits.length; i++)
            _UnitCard(
              unit: _visibleUnits[i],
              canManage: _canManage,
              toggling: _togglingId == _visibleUnits[i].id,
              green: _green,
              amber: _amber,
              blue: _blue,
              danger: _danger,
              onEdit: () => _openEditor(unit: _visibleUnits[i]),
              onToggle: () => _toggleActive(_visibleUnits[i]),
              onDelete: () => _confirmDelete(_visibleUnits[i]),
            )
                .animate(key: ValueKey('unit-${_visibleUnits[i].id}'))
                .fadeIn(
                  delay: Duration(milliseconds: 30 * i.clamp(0, 12)),
                  duration: 220.ms,
                ),
        ],
      );
    }

    return Column(
      key: ValueKey('panel-${_filter.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OrgPanelHeader(
          icon: meta.icon,
          eyebrow: meta.eyebrow,
          title: meta.title,
          hint: meta.hint,
          tone: _filterTone(_filter),
          trailing: _canManage
              ? FilledButton.icon(
                  onPressed: () => _openEditor(),
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 13, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(LucideIcons.plus, size: 15),
                  label: const Text(
                    'Nova',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                )
              : null,
        ),
        const SizedBox(height: 14),
        child,
      ],
    ).animate(key: ValueKey('panel-${_filter.name}')).fadeIn(duration: 240.ms);
  }

  Widget _buildEmpty(BuildContext context) {
    final hasSearch = _search.trim().isNotEmpty;
    if (hasSearch) {
      return OrgEmptyState(
        icon: LucideIcons.searchX,
        title: 'Nada encontrado',
        body: 'Nenhuma unidade corresponde a "${_search.trim()}".',
        tone: _filterTone(_filter),
      );
    }
    switch (_filter) {
      case _UnitFilter.all:
        return OrgEmptyState(
          icon: LucideIcons.building2,
          title: 'Nenhuma unidade ainda',
          body: 'Crie a primeira unidade para organizar equipes e gestores '
              'por filial.',
          tone: _accent,
          action: _canManage
              ? FilledButton.icon(
                  onPressed: () => _openEditor(),
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(LucideIcons.plus, size: 16),
                  label: const Text('Nova unidade'),
                )
              : null,
        );
      case _UnitFilter.active:
        return OrgEmptyState(
          icon: LucideIcons.circleCheckBig,
          title: 'Nenhuma unidade ativa',
          body: 'Ative uma unidade pausada ou crie uma nova.',
          tone: _green,
        );
      case _UnitFilter.inactive:
        return OrgEmptyState(
          icon: LucideIcons.circlePause,
          title: 'Nenhuma unidade pausada',
          body: 'Todas as unidades estão em operação.',
          tone: _amber,
        );
    }
  }

  /// Skeleton fiel ao card real (tile colorido + título + pills + rodapé).
  Widget _buildSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(
        4,
        (_) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: BorderRadius.circular(16),
            boxShadow: ThemeHelpers.cardShadow(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 44, height: 44, borderRadius: 13),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SkeletonText(width: 140, height: 16),
                        SizedBox(height: 8),
                        SkeletonText(width: double.infinity, height: 12),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: const [
                  SkeletonText(width: 84, height: 20, borderRadius: 999),
                  SizedBox(width: 8),
                  SkeletonText(width: 70, height: 20, borderRadius: 999),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Card de unidade ─────────────────────────────────────────────────────────

class _UnitCard extends StatelessWidget {
  final OrgUnit unit;
  final bool canManage;
  final bool toggling;
  final Color green;
  final Color amber;
  final Color blue;
  final Color danger;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _UnitCard({
    required this.unit,
    required this.canManage,
    required this.toggling,
    required this.green,
    required this.amber,
    required this.blue,
    required this.danger,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final unitColor = Color(unit.colorValue);
    final statusTone = unit.isActive ? green : amber;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: canManage ? onEdit : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Opacity(
              opacity: unit.isActive ? 1 : 0.72,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(13),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              unitColor,
                              unitColor.withValues(alpha: 0.72),
                            ],
                          ),
                        ),
                        child: const Icon(LucideIcons.building2,
                            color: Colors.white, size: 21),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              unit.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: ThemeHelpers.textColor(context),
                                letterSpacing: -0.2,
                              ),
                            ),
                            if ((unit.description ?? '').trim().isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                unit.description!.trim(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: secondary,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 11),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      OrgMiniPill(
                        label: unit.isActive ? 'Em operação' : 'Pausada',
                        tone: statusTone,
                        icon: unit.isActive
                            ? LucideIcons.circleCheckBig
                            : LucideIcons.circlePause,
                      ),
                      OrgMiniPill(
                        label:
                            '${unit.teamCount} equipe${unit.teamCount == 1 ? '' : 's'}',
                        tone: blue,
                        icon: LucideIcons.users2,
                      ),
                    ],
                  ),
                  if (unit.managers.isNotEmpty) ...[
                    const SizedBox(height: 11),
                    Row(
                      children: [
                        SizedBox(
                          width: 26.0 +
                              (unit.managers.length.clamp(1, 4) - 1) * 18.0,
                          height: 26,
                          child: Stack(
                            children: [
                              for (var i = 0;
                                  i < unit.managers.length.clamp(0, 4);
                                  i++)
                                Positioned(
                                  left: i * 18.0,
                                  child: OrgAvatar(
                                    name: unit.managers[i].name,
                                    imageUrl: unit.managers[i].avatar,
                                    tone: unitColor,
                                    size: 26,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            unit.managers.length == 1
                                ? unit.managers.first.name
                                : '${unit.managers.length} gestores de unidade',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: secondary,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (canManage) ...[
                    const SizedBox(height: 10),
                    Container(
                      height: 1,
                      color: ThemeHelpers.borderLightColor(context)
                          .withValues(alpha: 0.6),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _actionButton(
                          context,
                          icon: LucideIcons.pencil,
                          label: 'Editar',
                          tone: secondary,
                          onTap: onEdit,
                        ),
                        _actionButton(
                          context,
                          icon: LucideIcons.power,
                          label: unit.isActive ? 'Pausar' : 'Ativar',
                          tone: unit.isActive ? amber : green,
                          onTap: toggling ? null : onToggle,
                          busy: toggling,
                        ),
                        const Spacer(),
                        _actionButton(
                          context,
                          icon: LucideIcons.trash2,
                          label: 'Excluir',
                          tone: danger,
                          onTap: onDelete,
                        ),
                      ],
                    ),
                  ] else
                    const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color tone,
    required VoidCallback? onTap,
    bool busy = false,
  }) {
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: tone,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      icon: busy
          ? SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 1.8, color: tone),
            )
          : Icon(icon, size: 14),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }
}
