import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/models/sdr_metrics_models.dart';
import '../../../../shared/services/kanban_analytics_service.dart';
import '../../kanban/models/kanban_models.dart';
import '../../kanban/services/team_service.dart';

/// Painel SDR — dados de `GET /kanban/analytics/sdr/metrics` (mesmo contrato do web).
class SdrDashboardTab extends StatefulWidget {
  const SdrDashboardTab({super.key});

  @override
  State<SdrDashboardTab> createState() => _SdrDashboardTabState();
}

class _SdrDashboardTabState extends State<SdrDashboardTab> {
  static const double _padH = 20;
  static const double _padBottom = 88;

  int _periodDays = 30;
  SdrMetricsPayload? _data;
  String? _error;
  bool _loading = true;

  final Set<String> _selectedTeamIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final now = DateTime.now();
    final start = now.subtract(Duration(days: _periodDays));
    final fmt = DateFormat('yyyy-MM-dd');
    final r = await KanbanAnalyticsService.instance.getSdrMetrics(
      teamIds: _selectedTeamIds.isEmpty ? null : _selectedTeamIds.toList(),
      startDate: fmt.format(start),
      endDate: fmt.format(now),
    );
    if (!mounted) return;
    if (r.success && r.data != null) {
      setState(() {
        _data = r.data;
        _loading = false;
      });
    } else {
      setState(() {
        _error = r.message ?? 'Não foi possível carregar o Dash SDR';
        _loading = false;
      });
    }
  }

  Future<void> _pickTeams() async {
    final res = await TeamService.instance.getTeams();
    if (!mounted) return;
    if (!res.success || res.data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message ?? 'Erro ao listar equipes')),
      );
      return;
    }
    final teams = res.data!;
    final chosen = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        var local = Set<String>.from(_selectedTeamIds);
        return StatefulBuilder(
          builder: (context, setModal) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.55,
              maxChildSize: 0.9,
              minChildSize: 0.35,
              builder: (_, scroll) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Filtrar por equipe',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => setModal(() => local.clear()),
                            child: const Text('Limpar'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, local),
                            child: const Text('Aplicar'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: scroll,
                        itemCount: teams.length,
                        itemBuilder: (_, i) {
                          final KanbanTeam t = teams[i];
                          final sel = local.contains(t.id);
                          return CheckboxListTile(
                            value: sel,
                            title: Text(t.name),
                            onChanged: (v) {
                              setModal(() {
                                if (v == true) {
                                  local.add(t.id);
                                } else {
                                  local.remove(t.id);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
    if (chosen != null) {
      setState(() {
        _selectedTeamIds
          ..clear()
          ..addAll(chosen);
      });
      await _load();
    }
  }

  Color _accent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.primary.primaryDarkMode
          : AppColors.primary.primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accent(context);

    return RefreshIndicator(
      color: accent,
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(_padH, 12, _padH, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _periodRow(context, accent),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _pickTeams,
                    icon: const Icon(Icons.groups_rounded, size: 20),
                    label: Text(
                      _selectedTeamIds.isEmpty
                          ? 'Todas as equipes'
                          : '${_selectedTeamIds.length} equipe(s)',
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (_error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppColors.status.errorDarkMode
                        : AppColors.status.error,
                    fontSize: 15,
                  ),
                ),
              ),
            )
          else if (_data != null)
            ..._buildBodySlivers(context, theme, accent, _data!),
          const SliverToBoxAdapter(child: SizedBox(height: _padBottom)),
        ],
      ),
    );
  }

  Widget _periodRow(BuildContext context, Color accent) {
    Widget chip(String label, int days) {
      final on = _periodDays == days;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Material(
            color: on
                ? accent.withValues(alpha: 0.18)
                : ThemeHelpers.cardBackgroundColor(context),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                setState(() => _periodDays = days);
                _load();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: on
                        ? accent.withValues(alpha: 0.55)
                        : ThemeHelpers.borderColor(context)
                            .withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('7 dias', 7),
        chip('30 dias', 30),
        chip('90 dias', 90),
      ],
    );
  }

  List<Widget> _buildBodySlivers(
    BuildContext context,
    ThemeData theme,
    Color accent,
    SdrMetricsPayload d,
  ) {
    final s = d.summary;
    final nf = NumberFormat.decimalPattern('pt_BR');
    final pct = NumberFormat.percentPattern('pt_BR');

    final kpiStrip = Padding(
      padding: const EdgeInsets.fromLTRB(_padH, 14, _padH, 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              accent.withValues(alpha: 0.14),
              AppColors.secondary.secondary.withValues(alpha: 0.08),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: accent.withValues(alpha: 0.22),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Funil SDR',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                pct.format(
                  s.conversionRate > 1
                      ? s.conversionRate / 100
                      : s.conversionRate,
                ),
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: accent,
                ),
              ),
              Text(
                'taxa de conversão (transferidos / leads)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _kpiCell(context, 'Leads', nf.format(s.totalLeads), accent),
                  _kpiCell(
                    context,
                    'Transferidos',
                    nf.format(s.transferred),
                    Colors.teal,
                  ),
                  _kpiCell(
                    context,
                    'Perdidos',
                    nf.format(s.lost),
                    Colors.orange,
                  ),
                  _kpiCell(
                    context,
                    'Em qualif.',
                    nf.format(s.inQualification),
                    Colors.indigo,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    final agents = Padding(
      padding: const EdgeInsets.fromLTRB(_padH, 16, _padH, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Por corretor',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 118,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: d.byAgent.length.clamp(0, 40),
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final a = d.byAgent[i];
                return _agentCard(context, a, accent, nf, pct);
              },
            ),
          ),
        ],
      ),
    );

    final sources = d.bySource.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.fromLTRB(_padH, 20, _padH, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Por origem',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: d.bySource.take(24).map((src) {
                    return Chip(
                      avatar: CircleAvatar(
                        backgroundColor: accent.withValues(alpha: 0.2),
                        child: Text(
                          src.source.isNotEmpty
                              ? src.source[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      label: Text(
                        '${src.source} · ${nf.format(src.totalLeads)} · ${pct.format(src.conversionRate > 1 ? src.conversionRate / 100 : src.conversionRate)}',
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          );

    final channels = d.byChannel.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.fromLTRB(_padH, 20, _padH, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Por canal',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                ...d.byChannel.take(12).map((c) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      tileColor: ThemeHelpers.cardBackgroundColor(context),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: ThemeHelpers.borderColor(context)
                              .withValues(alpha: 0.35),
                        ),
                      ),
                      title: Text(
                        c.label.isNotEmpty ? c.label : c.channel,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        'Leads ${nf.format(c.totalLeads)} · Conv. ${pct.format(c.conversionRate > 1 ? c.conversionRate / 100 : c.conversionRate)}',
                      ),
                    ),
                  );
                }),
              ],
            ),
          );

    final wa = d.whatsapp == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.fromLTRB(_padH, 20, _padH, 0),
            child: _whatsappCard(context, d.whatsapp!, accent),
          );

    final transfers = Padding(
      padding: const EdgeInsets.fromLTRB(_padH, 22, _padH, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Transferências recentes',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          ...d.transferList.take(30).map((t) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                tileColor: ThemeHelpers.cardBackgroundColor(context),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color:
                        ThemeHelpers.borderColor(context).withValues(alpha: 0.35),
                  ),
                ),
                title: Text(
                  t.leadTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${t.fromTeam} → ${t.toTeam}\n${t.sdrAgentName} · ${_shortDate(t.transferredAt)}',
                  style: theme.textTheme.bodySmall,
                ),
                isThreeLine: true,
              ),
            );
          }),
        ],
      ),
    );

    return [
      SliverToBoxAdapter(child: kpiStrip),
      SliverToBoxAdapter(child: agents),
      SliverToBoxAdapter(child: sources),
      SliverToBoxAdapter(child: channels),
      SliverToBoxAdapter(child: wa),
      SliverToBoxAdapter(child: transfers),
    ];
  }

  String _shortDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('dd/MM HH:mm').format(dt);
    } catch (_) {
      return iso;
    }
  }

  Widget _kpiCell(
    BuildContext context,
    String label,
    String value,
    Color tone,
  ) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: tone,
            ),
          ),
        ],
      ),
    );
  }

  Widget _agentCard(
    BuildContext context,
    SdrAgentRow a,
    Color accent,
    NumberFormat nf,
    NumberFormat pct,
  ) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accent.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            a.agentName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const Spacer(),
          Text(
            'Leads ${nf.format(a.totalLeads)}',
            style: TextStyle(
              color: ThemeHelpers.textSecondaryColor(context),
              fontSize: 12,
            ),
          ),
          Text(
            'Conv. ${pct.format(a.conversionRate > 1 ? a.conversionRate / 100 : a.conversionRate)}',
            style: TextStyle(color: accent, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _whatsappCard(
    BuildContext context,
    SdrWhatsappSnapshot w,
    Color accent,
  ) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF25D366).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF25D366).withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.chat_rounded, color: Color(0xFF25D366)),
                const SizedBox(width: 8),
                Text(
                  'WhatsApp (período)',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Aguardando resposta: ${w.awaitingReplyCount}',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (w.firstResponseSampleSize > 0) ...[
              const SizedBox(height: 6),
              Text(
                '1ª resposta — média: ${w.avgFirstResponseMinutes?.toStringAsFixed(1) ?? '—'} min · mediana: ${w.medianFirstResponseMinutes?.toStringAsFixed(1) ?? '—'} min · amostra ${w.firstResponseSampleSize}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
