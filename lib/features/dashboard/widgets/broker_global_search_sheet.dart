import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../features/clients/models/client_model.dart';
import '../../../features/clients/services/client_service.dart';
import '../../../features/kanban/models/kanban_subtask_models.dart';
import '../../../features/kanban/services/kanban_subtask_service.dart';
import '../../../shared/services/property_service.dart';
import '../../../shared/state/broker_offline_cache.dart';

/// Busca global única: imóveis, clientes e leads (subtarefas/cards).
class BrokerGlobalSearchSheet extends StatefulWidget {
  const BrokerGlobalSearchSheet({super.key});

  @override
  State<BrokerGlobalSearchSheet> createState() =>
      _BrokerGlobalSearchSheetState();
}

class _BrokerGlobalSearchSheetState extends State<BrokerGlobalSearchSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  String _query = '';

  List<Property> _properties = [];
  List<Client> _clients = [];
  List<KanbanSubTask> _leads = [];

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 420), () {
      _search(value.trim());
    });
  }

  Future<void> _search(String q) async {
    setState(() {
      _query = q;
      _loading = q.isNotEmpty;
    });
    if (q.isEmpty) {
      setState(() {
        _properties = [];
        _clients = [];
        _leads = [];
        _loading = false;
      });
      return;
    }

    final props = await PropertyService.instance.getProperties(
      page: 1,
      limit: 6,
      filters: PropertyFilters(search: q),
    );
    final clients = await ClientService.instance.getClients(
      filters: ClientSearchFilters(search: q, page: 1, limit: 6),
    );
    final subs = await KanbanSubtaskService.instance.getMySubTasks(
      filters: SubTasksListFilters(
        onlyMine: true,
        cardSearch: q,
        page: 1,
        limit: 6,
      ),
    );

    if (!mounted) return;

    setState(() {
      _loading = false;
      _properties =
          props.success && props.data != null ? props.data!.data : [];
      _clients = clients.success && clients.data != null
          ? clients.data!.data
          : [];
      _leads = subs.success && subs.data != null ? subs.data!.data : [];
    });

    if (clients.success && clients.data != null) {
      unawaited(
        BrokerOfflineCache.instance.saveClients(
          clients.data!.data
              .map(
                (c) => {
                  'id': c.id,
                  'name': c.name,
                  'phone': c.phone,
                },
              )
              .toList(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasResults =
        _properties.isNotEmpty || _clients.isNotEmpty || _leads.isNotEmpty;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Material(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Text(
                'Busca global',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Imóvel, cliente, lead…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _controller.clear();
                            _search('');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                onSubmitted: _search,
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Center(child: CircularProgressIndicator(strokeWidth: 2))
              else if (_query.isNotEmpty && !hasResults)
                Text(
                  'Nenhum resultado para “$_query”.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                )
              else ...[
                if (_properties.isNotEmpty) ...[
                  _SectionLabel('Imóveis'),
                  ..._properties.map(
                    (p) => ListTile(
                      leading: const Icon(Icons.home_outlined),
                      title: Text(p.title),
                      subtitle: Text(p.code ?? p.city ?? ''),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.of(context)
                            .pushNamed(AppRoutes.propertyDetails(p.id));
                      },
                    ),
                  ),
                ],
                if (_clients.isNotEmpty) ...[
                  _SectionLabel('Clientes'),
                  ..._clients.map(
                    (c) => ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(c.name),
                      subtitle: Text(c.phone ?? c.email ?? ''),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.of(context)
                            .pushNamed(AppRoutes.clientDetails(c.id));
                      },
                    ),
                  ),
                ],
                if (_leads.isNotEmpty) ...[
                  _SectionLabel('Leads / tarefas'),
                  ..._leads.map(
                    (s) => ListTile(
                      leading: const Icon(Icons.view_kanban_outlined),
                      title: Text(s.taskTitle ?? s.title),
                      subtitle: Text(s.title),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.of(context).pushNamed(
                          AppRoutes.kanbanTaskDetails(s.taskId),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
      ),
    );
  }
}
