import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/module_access_service.dart';
import '../../../../shared/services/notes_service.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/vivid_chrome.dart';
import '../widgets/create_note_sheet.dart';

String _priorityLabelPt(String raw) {
  switch (raw.toLowerCase().trim()) {
    case 'low':
      return 'Baixa';
    case 'high':
      return 'Alta';
    case 'urgent':
      return 'Urgente';
    case 'medium':
    default:
      return 'Média';
  }
}

Color _accentForNote(NoteListItem n, Color fallback) {
  final hex = n.color?.trim();
  if (hex != null && hex.isNotEmpty) {
    var s = hex.replaceFirst('#', '');
    if (s.length == 6) s = 'FF$s';
    if (s.length == 8) {
      final v = int.tryParse(s, radix: 16);
      if (v != null) return Color(v);
    }
  }
  switch (n.priority.toLowerCase()) {
    case 'urgent':
      return const Color(0xFFDC2626);
    case 'high':
      return const Color(0xFFF97316);
    case 'low':
      return const Color(0xFF64748B);
    case 'medium':
    default:
      return fallback;
  }
}

/// Anotações — paridade funcional com o CRM web (`GET/POST /notes`, filtros ativo/arquivado).
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final status = _archived ? 'archived' : 'active';
    final search =
        _search.text.trim().isEmpty ? null : _search.text.trim();
    final listFut = NotesService.instance.listNotes(
      search: search,
      status: status,
    );
    final statsFut = NotesService.instance.getStats();
    final r = await listFut;
    final s = await statsFut;
    if (!mounted) return;
    if (r.success && r.data != null) {
      setState(() {
        _data = r.data;
        _stats = s.success ? s.data : _stats;
        _error = null;
        _loading = false;
      });
    } else {
      setState(() {
        _error = r.message;
        _loading = false;
      });
    }
  }

  void _openCreate() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CreateNoteSheet(
        onCreated: () {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Anotação criada.')),
          );
          _load();
        },
      ),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ModuleAccessService.instance,
      builder: (context, _) {
        return _buildNotes(context);
      },
    );
  }

  Widget _buildNotes(BuildContext context) {
    final accent = Theme.of(context).brightness == Brightness.dark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;

    final canModule = ModuleAccessService.instance.hasCompanyModule('notes');
    final canView =
        ModuleAccessService.instance.hasPermission('note:view') && canModule;
    final canCreate =
        ModuleAccessService.instance.hasPermission('note:create') && canModule;

    if (!canView) {
      return AppScaffold(
        title: 'Anotações',
        currentBottomNavIndex: -1,
        showBottomNavigation: false,
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            VividChrome.heroBanner(
              context,
              accent: accent,
              eyebrow: 'Produtividade',
              title: 'Anotações',
              subtitle:
                  'Este módulo exige permissão note:view e o módulo notes na empresa.',
              icon: Icons.lock_outline_rounded,
            ),
            const SizedBox(height: 16),
            VividChrome.mutedMessage(
              context,
              'Sem permissão ou módulo de anotações na empresa.',
              accent: accent,
            ),
          ],
        ),
      );
    }

    return AppScaffold(
      title: 'Anotações',
      currentBottomNavIndex: -1,
      showBottomNavigation: false,
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: VividChrome.heroBanner(
                  context,
                  accent: accent,
                  eyebrow: 'Produtividade',
                  title: 'Anotações',
                  subtitle:
                      'Ideias e lembretes da equipa — criar, pesquisar e alternar ativas ou arquivadas, como no painel web.',
                  icon: Icons.edit_note_rounded,
                ),
              ),
              if (_stats != null) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _StatsStrip(stats: _stats!, accent: accent),
                ),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _search,
                      decoration: InputDecoration(
                        hintText: 'Pesquisar título, conteúdo ou cliente…',
                        prefixIcon: const Icon(Icons.search_rounded),
                        filled: true,
                        fillColor: ThemeHelpers.cardBackgroundColor(context),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: ThemeHelpers.borderColor(context)
                                .withValues(alpha: 0.35),
                          ),
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.refresh_rounded),
                          onPressed: _load,
                        ),
                      ),
                      onSubmitted: (_) => _load(),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment<bool>(
                                value: false,
                                label: Text('Ativas'),
                                icon: Icon(Icons.note_alt_outlined, size: 18),
                              ),
                              ButtonSegment<bool>(
                                value: true,
                                label: Text('Arquivadas'),
                                icon: Icon(Icons.inventory_2_outlined, size: 18),
                              ),
                            ],
                            selected: {_archived},
                            onSelectionChanged: (s) {
                              setState(() => _archived = s.first);
                              _load();
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: accent,
                  onRefresh: _load,
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                              children: [
                                VividChrome.mutedMessage(
                                  context,
                                  _error!,
                                  accent: accent,
                                ),
                              ],
                            )
                          : _data == null || _data!.items.isEmpty
                              ? ListView(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    24,
                                    16,
                                    96,
                                  ),
                                  children: [
                                    _EmptyNotesIllustration(accent: accent),
                                    const SizedBox(height: 20),
                                    Text(
                                      _archived
                                          ? 'Nenhuma anotação arquivada.'
                                          : 'Nenhuma anotação ainda. Toque em «Nova» para criar a primeira.',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.copyWith(
                                            color: ThemeHelpers
                                                .textSecondaryColor(context),
                                            fontWeight: FontWeight.w600,
                                            height: 1.4,
                                          ),
                                    ),
                                  ],
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    4,
                                    16,
                                    96,
                                  ),
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  itemCount: _data!.items.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (_, i) {
                                    final n = _data!.items[i];
                                    final stripe =
                                        _accentForNote(n, accent);
                                    return _NoteEditorialCard(
                                      note: n,
                                      stripeColor: stripe,
                                      accent: accent,
                                    );
                                  },
                                ),
                ),
              ),
            ],
          ),
          if (canCreate)
            Positioned(
              right: 18,
              bottom: 22,
              child: SafeArea(
                child: Material(
                  elevation: 10,
                  shadowColor: accent.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(18),
                  color: const Color(0xFF4F46E5),
                  child: InkWell(
                    onTap: _openCreate,
                    borderRadius: BorderRadius.circular(18),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.add_rounded, color: Colors.white, size: 22),
                          SizedBox(width: 8),
                          Text(
                            'Nova',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.stats, required this.accent});

  final NotesStats stats;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final border = ThemeHelpers.borderColor(context);
    final items = [
      ('Total', '${stats.total}'),
      ('Básicas', '${stats.basic}'),
      ('Avançadas', '${stats.advanced}'),
      ('Fixadas', '${stats.pinned}'),
      ('Lembretes', '${stats.withReminders}'),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border.withValues(alpha: 0.28)),
        color: ThemeHelpers.cardBackgroundColor(context).withValues(alpha: 0.92),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0)
                Container(
                  width: 1,
                  height: 28,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: border.withValues(alpha: 0.25),
                ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      items[i].$2,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: accent,
                          ),
                    ),
                    Text(
                      items[i].$1,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NoteEditorialCard extends StatelessWidget {
  const _NoteEditorialCard({
    required this.note,
    required this.stripeColor,
    required this.accent,
  });

  final NoteListItem note;
  final Color stripeColor;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = ThemeHelpers.borderColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border.all(color: border.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: stripeColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (note.isPinned) ...[
                          Icon(Icons.push_pin_rounded, size: 17, color: accent),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            note.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.35,
                              height: 1.2,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: stripeColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: stripeColor.withValues(alpha: 0.28),
                            ),
                          ),
                          child: Text(
                            _priorityLabelPt(note.priority),
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: stripeColor.withValues(alpha: 0.95),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (note.content != null && note.content!.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        note.content!.trim(),
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: muted,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (note.reminderDate != null &&
                        note.reminderDate!.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 16,
                            color: muted,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              note.reminderDate!,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: muted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyNotesIllustration extends StatelessWidget {
  const _EmptyNotesIllustration({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [
              accent.withValues(alpha: 0.18),
              accent.withValues(alpha: 0.06),
            ],
          ),
          border: Border.all(color: accent.withValues(alpha: 0.25)),
        ),
        child: Icon(
          Icons.sticky_note_2_rounded,
          size: 52,
          color: accent.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}
