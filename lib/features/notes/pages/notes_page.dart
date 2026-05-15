import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/module_access_service.dart';
import '../../../../shared/services/notes_service.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../pages/create_note_page.dart' show showCreateNoteSheet;
import '../widgets/note_detail_sheet.dart';
import '../widgets/note_paper_card.dart';

const double _kPadH = 16;
const double _kPadTop = 8;
const double _kFabBottom = 88;

Color _accent(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;
}

class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  final _search = TextEditingController();
  NotesListResult? _data;
  NotesStats? _stats;
  String? _error;
  bool _loading = true;
  bool _archived = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await NotesService.instance.listNotes(
      search: _search.text.trim().isEmpty ? null : _search.text.trim(),
      status: _archived ? 'archived' : 'active',
    );
    final s = await NotesService.instance.getStats();
    if (!mounted) return;
    setState(() {
      if (r.success && r.data != null) {
        _data = r.data;
        _error = null;
      } else {
        _error = r.message;
      }
      _stats = s.success ? s.data : _stats;
      _loading = false;
    });
  }

  void _openDetail(NoteListItem note) {
    final accent = _accent(context);
    final canUpdate =
        ModuleAccessService.instance.hasPermission('note:update');
    final canDelete =
        ModuleAccessService.instance.hasPermission('note:delete');
    showNoteDetailSheet(
      context,
      note: note,
      accent: accent,
      canUpdate: canUpdate,
      canDelete: canDelete,
      archived: _archived,
      onChanged: _load,
    );
  }

  Future<void> _openCreate() async {
    final created = await showCreateNoteSheet(
      context,
      accent: _accent(context),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Anotação criada.')),
      );
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ModuleAccessService.instance,
      builder: (context, _) {
        final canModule = ModuleAccessService.instance.hasCompanyModule('notes');
        final canView =
            ModuleAccessService.instance.hasPermission('note:view') && canModule;
        if (!canView) {
          return AppScaffold(
            title: 'Anotações',
            currentBottomNavIndex: -1,
            showBottomNavigation: false,
            body: Center(
              child: Text(
                'Sem permissão para anotações.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          );
        }
        return _buildBody(context);
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    final accent = _accent(context);
    final theme = Theme.of(context);
    final canCreate =
        ModuleAccessService.instance.hasPermission('note:create');

    return AppScaffold(
      title: 'Anotações',
      currentBottomNavIndex: -1,
      showBottomNavigation: false,
      body: Stack(
        children: [
          RefreshIndicator(
            color: accent,
            onRefresh: _load,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                SliverToBoxAdapter(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ..._ambientGlows(context, accent),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          _kPadH,
                          _kPadTop,
                          _kPadH,
                          0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _NotesHero(
                              accent: accent,
                              archived: _archived,
                              stats: _stats,
                            ),
                            const SizedBox(height: 14),
                            _NotesSearchBar(
                              controller: _search,
                              accent: accent,
                              onSubmitted: _load,
                              onRefresh: _load,
                            ),
                            const SizedBox(height: 10),
                            _NotesStatusToggle(
                              archived: _archived,
                              accent: accent,
                              onChanged: (v) {
                                setState(() => _archived = v);
                                _load();
                              },
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: _kPadH),
                      child: Text(
                        _error!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                      ),
                    ),
                  )
                else if (_data == null || _data!.items.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _NotesEmpty(accent: accent, archived: _archived),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      _kPadH,
                      0,
                      _kPadH,
                      _kFabBottom,
                    ),
                    sliver: SliverList.separated(
                      itemCount: _data!.items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => NotePaperCard(
                        note: _data!.items[i],
                        accent: accent,
                        onTap: () => _openDetail(_data!.items[i]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (canCreate)
            Positioned(
              right: _kPadH,
              bottom: 18,
              child: SafeArea(
                child: _CreateFab(accent: accent, onTap: _openCreate),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _ambientGlows(BuildContext context, Color accent) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return [
      Positioned(
        top: -60,
        right: -40,
        child: IgnorePointer(
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  accent.withValues(alpha: isDark ? 0.2 : 0.1),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }
}

/// Hero aberto — mesmo idioma do dashboard (`_buildGreeting`).
class _NotesHero extends StatelessWidget {
  const _NotesHero({
    required this.accent,
    required this.archived,
    this.stats,
  });

  final Color accent;
  final bool archived;
  final NotesStats? stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HeroIcon(accent: accent, archived: archived),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        archived ? 'ARQUIVO' : 'ANOTAÇÕES',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent.withValues(alpha: 0.55),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('HH:mm', 'pt_BR').format(now),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    archived ? 'Itens arquivados' : 'Bloco de notas',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                      height: 1.05,
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    archived
                        ? 'Consulta rápida do que foi arquivado no CRM.'
                        : 'Cliente, lembrete, tags e prioridade.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (stats != null) ...[
          const SizedBox(height: 14),
          _NotesKpiStrip(stats: stats!, accent: accent),
        ],
      ],
    );
  }
}

class _HeroIcon extends StatelessWidget {
  const _HeroIcon({required this.accent, required this.archived});

  final Color accent;
  final bool archived;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone = archived ? const Color(0xFFF59E0B) : accent;

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tone,
            Color.lerp(tone, const Color(0xFF7C3AED), 0.45) ?? tone,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: tone.withValues(alpha: isDark ? 0.32 : 0.22),
            blurRadius: 14,
            offset: const Offset(0, 6),
            spreadRadius: -2,
          ),
        ],
      ),
      child: Icon(
        archived ? Icons.inventory_2_outlined : Icons.sticky_note_2_rounded,
        color: Colors.white,
        size: 26,
      ),
    );
  }
}

/// Faixa KPI horizontal — igual `_HeroQuickKpiStrip` do dashboard.
class _NotesKpiStrip extends StatelessWidget {
  const _NotesKpiStrip({required this.stats, required this.accent});

  final NotesStats stats;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final div = ThemeHelpers.borderLightColor(context).withValues(alpha: 0.6);
    final items = [
      _KpiItem(accent: accent, label: 'Total', value: '${stats.total}'),
      _KpiItem(
        accent: const Color(0xFFF59E0B),
        label: 'Fixadas',
        value: '${stats.pinned}',
      ),
      _KpiItem(
        accent: const Color(0xFF10B981),
        label: 'Lembretes',
        value: '${stats.withReminders}',
      ),
    ];

    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) Container(width: 1, height: 38, color: div),
          Expanded(child: items[i]),
        ],
      ],
    );
  }
}

class _KpiItem extends StatelessWidget {
  const _KpiItem({
    required this.accent,
    required this.label,
    required this.value,
  });

  final Color accent;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: accent,
                letterSpacing: -0.6,
                height: 1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: ThemeHelpers.textSecondaryColor(context),
              letterSpacing: 1.4,
              fontSize: 9.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Container(
            height: 2,
            width: 18,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotesSearchBar extends StatelessWidget {
  const _NotesSearchBar({
    required this.controller,
    required this.accent,
    required this.onSubmitted,
    required this.onRefresh,
  });

  final TextEditingController controller;
  final Color accent;
  final VoidCallback onSubmitted;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final border = ThemeHelpers.borderColor(context);

    return TextField(
      controller: controller,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
      decoration: InputDecoration(
        hintText: 'Buscar título, conteúdo ou cliente…',
        isDense: true,
        prefixIcon: Icon(Icons.search_rounded, color: accent, size: 22),
        suffixIcon: IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: onRefresh,
          tooltip: 'Atualizar',
        ),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.35),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border.withValues(alpha: 0.4)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border.withValues(alpha: 0.35)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent.withValues(alpha: 0.65)),
        ),
      ),
      onSubmitted: (_) => onSubmitted(),
    );
  }
}

class _NotesStatusToggle extends StatelessWidget {
  const _NotesStatusToggle({
    required this.archived,
    required this.accent,
    required this.onChanged,
  });

  final bool archived;
  final Color accent;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _tab(context, 'Ativas', !archived, () => onChanged(false)),
        const SizedBox(width: 20),
        _tab(context, 'Arquivadas', archived, () => onChanged(true)),
      ],
    );
  }

  Widget _tab(
    BuildContext context,
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: selected
                    ? accent
                    : ThemeHelpers.textSecondaryColor(context),
              ),
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 2,
              width: selected ? 32 : 0,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateFab extends StatelessWidget {
  const _CreateFab({required this.accent, required this.onTap});

  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 10,
      shadowColor: accent.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(16),
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [accent, Color.lerp(accent, Colors.black, 0.15)!],
            ),
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, color: Colors.white, size: 22),
                SizedBox(width: 8),
                Text(
                  'Nova anotação',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
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

class _NotesEmpty extends StatelessWidget {
  const _NotesEmpty({required this.accent, required this.archived});

  final Color accent;
  final bool archived;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _kPadH),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sticky_note_2_outlined, size: 48, color: accent.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              archived ? 'Nada arquivado' : 'Nenhuma anotação',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
