import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/competition_models.dart';
import '../services/competition_service.dart';
import '../widgets/competition_card.dart';
import '../widgets/gamification_ui.dart';

final DateFormat _confirmDate = DateFormat('dd/MM/yyyy', 'pt_BR');

/// Ordenação da lista (paridade `sortBy` do `CompetitionsPage.tsx`).
enum _CompetitionSort {
  startDate('Data de início'),
  endDate('Data de término'),
  name('Nome');

  const _CompetitionSort(this.label);
  final String label;
}

/// Lista de **Competições** — filtro por status/tipo, busca, criação e ações
/// no próprio card (editar, prêmios, finalizar, status, excluir).
/// Paridade `CompetitionsPage.tsx`.
class CompetitionsPage extends StatefulWidget {
  const CompetitionsPage({super.key});

  @override
  State<CompetitionsPage> createState() => _CompetitionsPageState();
}

class _CompetitionsPageState extends State<CompetitionsPage> {
  static const double _padH = 16;

  final _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Competition> _competitions = const [];

  CompetitionStatus? _statusFilter; // null = todas
  CompetitionType? _typeFilter; // null = todos
  _CompetitionSort _sort = _CompetitionSort.startDate;

  bool get _canView =>
      ModuleAccessService.instance.hasPermission('competition:view');
  bool get _canCreate =>
      ModuleAccessService.instance.hasPermission('competition:create');
  bool get _canEdit =>
      ModuleAccessService.instance.hasPermission('competition:edit');
  bool get _canDelete =>
      ModuleAccessService.instance.hasPermission('competition:delete');
  bool get _canManagePrizes =>
      ModuleAccessService.instance.hasPermission('prize:create');

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await CompetitionService.instance
        .getCompetitions(status: _statusFilter);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _competitions = res.data!;
      } else {
        _error = res.message ?? 'Erro ao carregar competições';
      }
    });
  }

  void _selectStatus(CompetitionStatus? status) {
    if (status == _statusFilter) return;
    setState(() => _statusFilter = status);
    _load();
  }

  List<Competition> get _visible {
    final term = _searchController.text.trim().toLowerCase();
    final list = _competitions.where((c) {
      if (term.isNotEmpty && !c.name.toLowerCase().contains(term)) {
        return false;
      }
      if (_typeFilter != null && c.type != _typeFilter) return false;
      return true;
    }).toList();

    list.sort((a, b) {
      switch (_sort) {
        case _CompetitionSort.name:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case _CompetitionSort.startDate:
          return (b.startDate ?? DateTime(1970))
              .compareTo(a.startDate ?? DateTime(1970));
        case _CompetitionSort.endDate:
          return (b.endDate ?? DateTime(1970))
              .compareTo(a.endDate ?? DateTime(1970));
      }
    });
    return list;
  }

  int get _activeFilterCount =>
      (_typeFilter != null ? 1 : 0) +
      (_sort != _CompetitionSort.startDate ? 1 : 0);

  // ─── Ações ─────────────────────────────────────────────────────────────────

  void _openCreate() {
    Navigator.of(context)
        .pushNamed('/competitions/new')
        .then((_) => _load());
  }

  void _openEdit(Competition c) {
    Navigator.of(context)
        .pushNamed('/competitions/${c.id}/edit')
        .then((_) => _load());
  }

  void _openPrizes(Competition c) {
    Navigator.of(context)
        .pushNamed('/competitions/${c.id}/prizes')
        .then((_) => _load());
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? gamDanger(context) : null,
      ),
    );
  }

  Future<void> _changeStatus(Competition c, CompetitionStatus status) async {
    final res = await CompetitionService.instance.changeStatus(c.id, status);
    if (!mounted) return;
    if (res.success) {
      _snack('Status atualizado com sucesso');
      _load();
    } else {
      _snack(res.message ?? 'Erro ao atualizar status', error: true);
    }
  }

  Future<void> _confirmFinalize(Competition c) async {
    final confirmed = await _confirmSheet(
      icon: LucideIcons.trophy,
      tone: gamAmber(context),
      title: 'Finalizar competição?',
      body: 'Isso irá calcular o ranking do período e atribuir os prêmios '
          'aos vencedores definidos.',
      competition: c,
      confirmLabel: 'Finalizar competição',
    );
    if (confirmed != true) return;

    final res = await CompetitionService.instance.finalize(c.id);
    if (!mounted) return;
    if (res.success) {
      _snack('Competição finalizada com sucesso');
      _load();
    } else {
      _snack(res.message ?? 'Erro ao finalizar competição', error: true);
    }
  }

  Future<void> _confirmDelete(Competition c) async {
    final confirmed = await _confirmSheet(
      icon: LucideIcons.trash2,
      tone: gamDanger(context),
      title: 'Excluir competição?',
      body: 'A competição "${c.name}" será removida permanentemente. '
          'Esta ação não pode ser desfeita.',
      competition: c,
      confirmLabel: 'Excluir',
      danger: true,
    );
    if (confirmed != true) return;

    final res = await CompetitionService.instance.delete(c.id);
    if (!mounted) return;
    if (res.success) {
      _snack('Competição excluída com sucesso');
      _load();
    } else {
      _snack(res.message ?? 'Erro ao excluir competição', error: true);
    }
  }

  Future<bool?> _confirmSheet({
    required IconData icon,
    required Color tone,
    required String title,
    required String body,
    required Competition competition,
    required String confirmLabel,
    bool danger = false,
  }) {
    final theme = Theme.of(context);
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final secondary = ThemeHelpers.textSecondaryColor(sheetContext);
        return Container(
          padding: EdgeInsets.fromLTRB(
            20,
            14,
            20,
            20 + MediaQuery.of(sheetContext).padding.bottom,
          ),
          decoration: BoxDecoration(
            color: ThemeHelpers.backgroundColor(sheetContext),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ThemeHelpers.borderColor(sheetContext)
                        .withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tone.withValues(alpha: 0.13),
                    border: Border.all(color: tone.withValues(alpha: 0.35)),
                  ),
                  child: Icon(icon, color: tone, size: 26),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(sheetContext),
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: secondary,
                  height: 1.45,
                ),
              ),
              if (competition.startDate != null ||
                  competition.endDate != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: ThemeHelpers.cardBackgroundColor(sheetContext),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: ThemeHelpers.cardShadow(sheetContext),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.calendarRange,
                          size: 13, color: secondary),
                      const SizedBox(width: 8),
                      Text(
                        '${competition.startDate != null ? _confirmDate.format(competition.startDate!) : '—'}'
                        '  →  '
                        '${competition.endDate != null ? _confirmDate.format(competition.endDate!) : '—'}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: ThemeHelpers.textColor(sheetContext),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(sheetContext).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: tone,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      child: Text(
                        confirmLabel,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canView) {
      return const AppScaffold(
        title: 'Competições',
        showBottomNavigation: false,
        body: GamDeniedView(
          what: 'competições',
          permission: 'competition:view',
        ),
      );
    }

    final accent = gamAccentColor(context);

    return AppScaffold(
      title: 'Competições',
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
                  child: _buildContent(context),
                ),
              ),
            ),
          ),
          if (_canCreate)
            Positioned(
              right: 16,
              bottom: 24,
              child: FloatingActionButton.extended(
                heroTag: 'competitions-fab',
                onPressed: _openCreate,
                backgroundColor: accent,
                foregroundColor: Colors.white,
                icon: const Icon(LucideIcons.plus, size: 18),
                label: const Text(
                  'Nova competição',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_loading) return _buildSkeleton(context);

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(_padH, 60, _padH, 100),
        child: GamErrorState(message: _error!, onRetry: _load),
      );
    }

    final visible = _visible;

    return Padding(
      padding: const EdgeInsets.fromLTRB(_padH, 10, _padH, 108),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHero(context),
          const SizedBox(height: 16),
          _buildSearchRow(context),
          const SizedBox(height: 12),
          _buildStatusChips(context),
          const SizedBox(height: 16),
          if (visible.isEmpty)
            GamEmptyState(
              icon: LucideIcons.flag,
              title: _searchController.text.trim().isNotEmpty ||
                      _typeFilter != null ||
                      _statusFilter != null
                  ? 'Nenhuma competição encontrada'
                  : 'Nenhuma competição ainda',
              body: _searchController.text.trim().isNotEmpty ||
                      _typeFilter != null ||
                      _statusFilter != null
                  ? 'Tente ajustar a busca ou os filtros.'
                  : 'Crie competições para motivar sua equipe com eventos '
                      'temporários e prêmios!',
              tone: gamAccentColor(context),
              action: _canCreate &&
                      _searchController.text.trim().isEmpty &&
                      _typeFilter == null &&
                      _statusFilter == null
                  ? FilledButton.icon(
                      onPressed: _openCreate,
                      style: FilledButton.styleFrom(
                        backgroundColor: gamAccentColor(context),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(LucideIcons.plus, size: 16),
                      label: const Text('Criar primeira competição'),
                    )
                  : null,
            )
          else
            for (var i = 0; i < visible.length; i++)
              CompetitionCard(
                competition: visible[i],
                onTap: () =>
                    _canEdit ? _openEdit(visible[i]) : _openPrizesIfAllowed(visible[i]),
                onEdit: _canEdit ? () => _openEdit(visible[i]) : null,
                onPrizes:
                    _canManagePrizes ? () => _openPrizes(visible[i]) : null,
                onFinalize:
                    _canEdit ? () => _confirmFinalize(visible[i]) : null,
                onDelete: _canDelete ? () => _confirmDelete(visible[i]) : null,
                onChangeStatus: _canEdit
                    ? (s) => _changeStatus(visible[i], s)
                    : null,
              ).animate(key: ValueKey('comp-${visible[i].id}')).fadeIn(
                    delay: Duration(milliseconds: 30 * i.clamp(0, 10)),
                    duration: 220.ms,
                  ),
        ],
      ),
    );
  }

  void _openPrizesIfAllowed(Competition c) {
    if (_canManagePrizes) _openPrizes(c);
  }

  // ─── Hero ──────────────────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    final accent = gamAccentColor(context);
    final green = gamGreen(context);
    final blue = gamBlue(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    final total = _competitions.length;
    final active = _competitions
        .where((c) => c.status == CompetitionStatus.active)
        .length;
    final scheduled = _competitions
        .where((c) => c.status == CompetitionStatus.scheduled)
        .length;
    final prizesCount =
        _competitions.fold<int>(0, (sum, c) => sum + c.prizes.length);

    final dot = active > 0 ? green : blue;

    return Column(
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
              'COMPETIÇÕES',
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
              '$total',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: ThemeHelpers.textColor(context),
                height: 1.0,
                letterSpacing: -1.0,
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                total == 1 ? 'competição' : 'competições',
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
          active > 0
              ? '$active em andamento agora — acompanhe o placar e os prêmios.'
              : scheduled > 0
                  ? '$scheduled agendada${scheduled == 1 ? '' : 's'} para começar em breve.'
                  : 'Eventos temporários com prêmios para motivar a equipe.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: secondary,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            GamMiniPill(
              label: '$active em andamento',
              color: green,
              icon: LucideIcons.play,
            ),
            GamMiniPill(
              label: '$scheduled agendada${scheduled == 1 ? '' : 's'}',
              color: blue,
              icon: LucideIcons.calendarClock,
            ),
            GamMiniPill(
              label: '$prizesCount prêmio${prizesCount == 1 ? '' : 's'}',
              color: gamAmber(context),
              icon: LucideIcons.gift,
            ),
          ],
        ),
      ],
    );
  }

  // ─── Busca + filtros ───────────────────────────────────────────────────────

  Widget _buildSearchRow(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final accent = gamAccentColor(context);
    final activeCount = _activeFilterCount;

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: ThemeHelpers.textColor(context)),
            decoration: InputDecoration(
              hintText: 'Buscar por nome…',
              hintStyle:
                  theme.textTheme.bodyMedium?.copyWith(color: secondary),
              prefixIcon: Icon(LucideIcons.search, size: 17, color: secondary),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(LucideIcons.x, size: 15, color: secondary),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
              isDense: true,
              filled: true,
              fillColor: fill,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: BorderSide(color: accent.withValues(alpha: 0.5)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: _openFilters,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              color: activeCount > 0
                  ? accent.withValues(alpha: isDark ? 0.22 : 0.1)
                  : fill,
              border: activeCount > 0
                  ? Border.all(color: accent.withValues(alpha: 0.5))
                  : null,
            ),
            child: Stack(
              children: [
                Center(
                  child: Icon(
                    LucideIcons.listFilter,
                    size: 18,
                    color: activeCount > 0 ? accent : secondary,
                  ),
                ),
                if (activeCount > 0)
                  Positioned(
                    top: 7,
                    right: 7,
                    child: Container(
                      width: 15,
                      height: 15,
                      decoration:
                          BoxDecoration(color: accent, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: Text(
                        '$activeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChips(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget chip(String label, CompetitionStatus? status, Color tone) {
      final selected = _statusFilter == status;
      return GestureDetector(
        onTap: () => _selectStatus(status),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: selected
                ? tone.withValues(alpha: isDark ? 0.22 : 0.1)
                : Colors.transparent,
            border: Border.all(
              color: selected
                  ? tone.withValues(alpha: 0.5)
                  : ThemeHelpers.borderColor(context).withValues(alpha: 0.6),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? tone : secondary,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
              fontSize: 12.5,
              letterSpacing: -0.1,
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          chip('Todas', null, gamAccentColor(context)),
          for (final s in CompetitionStatus.values)
            chip(s.label, s, competitionStatusColor(context, s)),
        ],
      ),
    );
  }

  // ─── Modal de filtros (espelha o do CRM) ───────────────────────────────────

  void _openFilters() {
    var type = _typeFilter;
    var sort = _sort;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final isDark = theme.brightness == Brightness.dark;
        final accent = gamAccentColor(sheetContext);
        final cTipo = gamPurple(sheetContext);
        final cOrdem = gamBlue(sheetContext);
        final secondary = ThemeHelpers.textSecondaryColor(sheetContext);

        return StatefulBuilder(
          builder: (context, setSheetState) {
            Widget optionChip({
              required String label,
              required IconData icon,
              required bool selected,
              required Color tone,
              required VoidCallback onTap,
            }) {
              return GestureDetector(
                onTap: onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: selected
                        ? tone.withValues(alpha: isDark ? 0.22 : 0.1)
                        : Colors.transparent,
                    border: Border.all(
                      color: selected
                          ? tone.withValues(alpha: 0.55)
                          : ThemeHelpers.borderColor(context)
                              .withValues(alpha: 0.6),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon,
                          size: 13, color: selected ? tone : secondary),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          color: selected ? tone : secondary,
                          fontWeight:
                              selected ? FontWeight.w900 : FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            Widget section({
              required Color tone,
              required String label,
              required String hint,
              required Widget child,
              bool first = false,
            }) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!first) ...[
                    const SizedBox(height: 18),
                    Container(
                      height: 1,
                      color: ThemeHelpers.borderLightColor(context)
                          .withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 18),
                  ],
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration:
                            BoxDecoration(color: tone, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        label.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: tone,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hint,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: secondary, fontSize: 11.5),
                  ),
                  const SizedBox(height: 10),
                  child,
                ],
              );
            }

            return Container(
              decoration: BoxDecoration(
                color: ThemeHelpers.backgroundColor(context),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 4),
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: ThemeHelpers.borderColor(context)
                            .withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                    child: Row(
                      children: [
                        Icon(LucideIcons.listFilter, size: 17, color: accent),
                        const SizedBox(width: 8),
                        Text(
                          'Filtrar competições',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: ThemeHelpers.textColor(context),
                            letterSpacing: -0.2,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            setSheetState(() {
                              type = null;
                              sort = _CompetitionSort.startDate;
                            });
                          },
                          child: Text(
                            'Limpar',
                            style: TextStyle(
                              color: secondary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        section(
                          tone: cTipo,
                          label: 'Tipo',
                          hint: 'Individual, por equipes ou misto.',
                          first: true,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              optionChip(
                                label: 'Todos',
                                icon: LucideIcons.sparkles,
                                selected: type == null,
                                tone: cTipo,
                                onTap: () => setSheetState(() => type = null),
                              ),
                              for (final t in CompetitionType.values)
                                optionChip(
                                  label: t.label,
                                  icon: t == CompetitionType.team
                                      ? LucideIcons.users2
                                      : t == CompetitionType.mixed
                                          ? LucideIcons.blend
                                          : LucideIcons.user,
                                  selected: type == t,
                                  tone: cTipo,
                                  onTap: () => setSheetState(() => type = t),
                                ),
                            ],
                          ),
                        ),
                        section(
                          tone: cOrdem,
                          label: 'Ordenar por',
                          hint: 'Como a lista é organizada.',
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final s in _CompetitionSort.values)
                                optionChip(
                                  label: s.label,
                                  icon: s == _CompetitionSort.name
                                      ? LucideIcons.arrowDownUp
                                      : LucideIcons.calendarDays,
                                  selected: sort == s,
                                  tone: cOrdem,
                                  onTap: () => setSheetState(() => sort = s),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: FilledButton(
                            onPressed: () {
                              setState(() {
                                _typeFilter = type;
                                _sort = sort;
                              });
                              Navigator.of(context).pop();
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              'Aplicar filtros',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ─── Skeleton fiel ─────────────────────────────────────────────────────────

  Widget _buildSkeleton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_padH, 14, _padH, 108),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonText(width: 130, height: 12, borderRadius: 999),
          const SizedBox(height: 14),
          const SkeletonText(width: 150, height: 34, borderRadius: 10),
          const SizedBox(height: 10),
          const SkeletonText(width: double.infinity, height: 13),
          const SizedBox(height: 14),
          Row(
            children: const [
              SkeletonBox(width: 110, height: 26, borderRadius: 999),
              SizedBox(width: 8),
              SkeletonBox(width: 100, height: 26, borderRadius: 999),
              SizedBox(width: 8),
              SkeletonBox(width: 90, height: 26, borderRadius: 999),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: const [
              Expanded(child: SkeletonBox(height: 44, borderRadius: 13)),
              SizedBox(width: 10),
              SkeletonBox(width: 44, height: 44, borderRadius: 13),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: const [
              SkeletonBox(width: 66, height: 30, borderRadius: 999),
              SizedBox(width: 8),
              SkeletonBox(width: 90, height: 30, borderRadius: 999),
              SizedBox(width: 8),
              SkeletonBox(width: 86, height: 30, borderRadius: 999),
            ],
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < 3; i++) ...[
            const SkeletonBox(
                width: double.infinity, height: 190, borderRadius: 18),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
