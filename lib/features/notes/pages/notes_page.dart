import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/module_access_service.dart';
import '../../../../shared/services/notes_service.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/vivid_chrome.dart';

/// Lista de anotações (`GET /notes`) — leitura; criação permanece no web se necessário.
class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  final _search = TextEditingController();
  NotesListResult? _data;
  String? _error;
  bool _loading = true;

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
    );
    if (!mounted) return;
    if (r.success && r.data != null) {
      setState(() {
        _data = r.data;
        _loading = false;
      });
    } else {
      setState(() {
        _error = r.message;
        _loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).brightness == Brightness.dark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;

    final can = ModuleAccessService.instance.hasPermission('note:view') &&
        ModuleAccessService.instance.hasCompanyModule('notes');

    return AppScaffold(
      title: 'Anotações',
      currentBottomNavIndex: -1,
      showBottomNavigation: false,
      body: !can
          ? ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                VividChrome.heroBanner(
                  context,
                  accent: accent,
                  eyebrow: 'Produtividade',
                  title: 'Anotações',
                  subtitle: 'Este módulo exige permissão note:view e o módulo notes na empresa.',
                  icon: Icons.lock_outline_rounded,
                ),
                const SizedBox(height: 16),
                VividChrome.mutedMessage(
                  context,
                  'Sem permissão ou módulo de anotações na empresa.',
                  accent: accent,
                ),
              ],
            )
          : Column(
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
                        'Lista vinda do servidor — pesquisa e leitura; criação avançada no painel web, se aplicável.',
                    icon: Icons.edit_note_rounded,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: 'Pesquisar…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: ThemeHelpers.cardBackgroundColor(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.refresh_rounded),
                        onPressed: _load,
                      ),
                    ),
                    onSubmitted: (_) => _load(),
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
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                                child: VividChrome.mutedMessage(
                                  context,
                                  _error!,
                                  accent: accent,
                                ),
                              ),
                            ],
                          )
                        : _data == null || _data!.items.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                                child: VividChrome.mutedMessage(
                                  context,
                                  'Nenhuma anotação encontrada para os filtros atuais.',
                                  accent: accent,
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(
                              16,
                              4,
                              16,
                              32,
                            ),
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: _data!.items.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              final n = _data!.items[i];
                              return Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  color: ThemeHelpers.cardBackgroundColor(
                                    context,
                                  ),
                                  border: Border.all(
                                    color: accent.withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        if (n.isPinned)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              right: 6,
                                            ),
                                            child: Icon(
                                              Icons.push_pin_rounded,
                                              size: 16,
                                              color: accent,
                                            ),
                                          ),
                                        Expanded(
                                          child: Text(
                                            n.title,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (n.content != null &&
                                        n.content!.trim().isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        n.content!.trim(),
                                        maxLines: 4,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: ThemeHelpers
                                              .textSecondaryColor(context),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 6),
                                    Text(
                                      'Prioridade: ${n.priority}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}
