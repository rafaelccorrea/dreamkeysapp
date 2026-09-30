import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../models/dashboard_overview_model.dart';
import 'company_overview_style.dart';

/// Qual "Ver detalhes" abrir — os mesmos oito do `HomeDetailsModal` do web.
enum OverviewDetailKind {
  leads,
  conversion,
  sales,
  appointments,
  tasks,
  documents,
  funnel,
  sources,
}

class _DetailMeta {
  const _DetailMeta({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.route,
    this.cta,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String? route;
  final String? cta;
}

_DetailMeta _metaOf(OverviewDetailKind k) {
  switch (k) {
    case OverviewDetailKind.leads:
      return const _DetailMeta(
        title: 'Leads do período',
        subtitle: 'Leads mais recentes e origem',
        icon: LucideIcons.users,
        route: AppRoutes.kanban,
        cta: 'Abrir CRM',
      );
    case OverviewDetailKind.conversion:
      return const _DetailMeta(
        title: 'Conversão',
        subtitle: 'Como o número é calculado',
        icon: LucideIcons.percent,
        route: AppRoutes.saleFormsDashboard,
        cta: 'Dashboard de fichas',
      );
    case OverviewDetailKind.sales:
      return const _DetailMeta(
        title: 'Vendas e meta',
        subtitle: 'Fichas finalizadas × meta do mês',
        icon: LucideIcons.dollarSign,
        route: AppRoutes.saleForms,
        cta: 'Ver fichas',
      );
    case OverviewDetailKind.appointments:
      return const _DetailMeta(
        title: 'Agendamentos',
        subtitle: 'Próximos compromissos',
        icon: LucideIcons.calendarCheck,
        route: AppRoutes.calendar,
        cta: 'Abrir agenda',
      );
    case OverviewDetailKind.tasks:
      return const _DetailMeta(
        title: 'Tarefas urgentes',
        subtitle: 'Atrasadas e vencendo hoje',
        icon: LucideIcons.triangleAlert,
        route: AppRoutes.kanban,
        cta: 'Abrir CRM',
      );
    case OverviewDetailKind.documents:
      return const _DetailMeta(
        title: 'Documentos pendentes',
        subtitle: 'Aguardando conferência',
        icon: LucideIcons.fileText,
      );
    case OverviewDetailKind.funnel:
      return const _DetailMeta(
        title: 'Funil do período',
        subtitle: 'Etapas, perdas e conversão etapa a etapa',
        icon: LucideIcons.funnel,
        route: AppRoutes.kanban,
        cta: 'Abrir CRM',
      );
    case OverviewDetailKind.sources:
      return const _DetailMeta(
        title: 'Origem dos leads',
        subtitle: 'Todos os canais do período',
        icon: LucideIcons.chartPie,
        route: AppRoutes.kanban,
        cta: 'Abrir CRM',
      );
  }
}

/// O atalho do rodapé só aparece quando a pessoa pode abrir o destino
/// (módulo contratado + permissão) — nunca leva a uma tela bloqueada.
bool _canOpen(String route) {
  final access = ModuleAccessService.instance;
  if (route == AppRoutes.kanban) {
    return access.hasCompanyModule('kanban_management');
  }
  if (route == AppRoutes.saleForms) {
    return access.hasCompanyModule('sale_forms');
  }
  if (route == AppRoutes.saleFormsDashboard) {
    return access.hasCompanyModule('sale_forms') &&
        access.hasPermission('sale_form:view_dashboard');
  }
  return access.canAccessRoutePath(route);
}

/// Abre o detalhe de um KPI da Home executiva.
///
/// 29/09/2026 (dash-01): paridade com o `HomeDetailsModal` do web. Só mostra
/// o que o overview já trouxe — sem requisição extra e sem recálculo: as
/// listas são as do mesmo payload e dos mesmos filtros da tela.
Future<void> showOverviewDetails(
  BuildContext context, {
  required OverviewDetailKind kind,
  required DashboardOverview data,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.black54,
    backgroundColor: ThemeHelpers.cardBackgroundColor(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (ctx) => _OverviewDetailsSheet(kind: kind, data: data),
  );
}

class _OverviewDetailsSheet extends StatelessWidget {
  const _OverviewDetailsSheet({required this.kind, required this.data});

  final OverviewDetailKind kind;
  final DashboardOverview data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.of(context);
    final meta = _metaOf(kind);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final metaRoute = meta.route;
    final String? ctaRoute =
        metaRoute != null && meta.cta != null && _canOpen(metaRoute)
            ? metaRoute
            : null;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: mq.size.height * 0.88),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: ThemeHelpers.borderLightColor(context),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 8, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(meta.icon, size: 20, color: ThemeHelpers.textColor(context)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meta.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: ThemeHelpers.textColor(context),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        meta.subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Fechar',
                  icon: Icon(Icons.close_rounded, color: secondary),
                ),
              ],
            ),
          ),
          Container(height: 1, color: OverviewTones.rule(context)),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: _body(context),
            ),
          ),
          if (ctaRoute != null)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () {
                      final nav = Navigator.of(context);
                      nav.pop();
                      nav.pushNamed(ctaRoute);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ThemeHelpers.textColor(context),
                      side: BorderSide(color: ThemeHelpers.borderColor(context)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            meta.cta!,
                            maxLines: 1,
                            softWrap: false,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.arrow_forward_rounded, size: 18),
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

  Widget _body(BuildContext context) {
    switch (kind) {
      case OverviewDetailKind.leads:
        return _leadsBody(context);
      case OverviewDetailKind.conversion:
        return _conversionBody(context);
      case OverviewDetailKind.sales:
        return _salesBody(context);
      case OverviewDetailKind.appointments:
        return _appointmentsBody(context);
      case OverviewDetailKind.tasks:
        return _tasksBody(context);
      case OverviewDetailKind.documents:
        return _documentsBody(context);
      case OverviewDetailKind.funnel:
        return _funnelBody(context);
      case OverviewDetailKind.sources:
        return _sourcesBody(context);
    }
  }

  // ─── corpos ────────────────────────────────────────────────────────────────

  Widget _leadsBody(BuildContext context) {
    final leads = data.leads.leads;
    final sources = data.leadSources.sources;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Stats(items: [
          ('Total', ovInt(data.statistics.totalLeads)),
          ('Hoje', ovInt(data.leads.newToday)),
          ('Score médio', ovInt(data.leads.avgScore.round())),
          ('Sem origem', ovInt(data.leadSources.withoutSource)),
        ]),
        if (sources.isNotEmpty) ...[
          const _BlockTitle('Origem'),
          _SourceBars(sources: sources.take(8).toList(growable: false)),
        ],
        const _BlockTitle('Mais recentes'),
        if (leads.isEmpty)
          const _Muted('Nenhum lead neste recorte.')
        else
          ...leads.take(10).map((l) {
            final sub = [l.location, _maskPhone(l.phone)]
                .whereType<String>()
                .where((s) => s.isNotEmpty)
                .join(' · ');
            return _ListRow(
              title: l.name,
              subtitle: sub.isEmpty ? '—' : sub,
              meta: [
                ovSource(l.source),
                ovLeadStatus(l.status),
                l.assignedToName ?? '—',
              ],
            );
          }),
      ],
    );
  }

  Widget _conversionBody(BuildContext context) {
    final s = data.statistics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Stats(items: [
          ('Leads', ovInt(s.totalLeads)),
          ('Agendamentos', ovInt(s.appointments)),
          ('Fichas finalizadas', ovInt(s.salesCount)),
          ('Conversão', ovPct(s.realConversionRate)),
        ]),
        const _Muted(
          'Conversão = fichas de venda finalizadas ÷ leads captados, ambos no '
          'mesmo período e filtros. A variação no indicador compara com o '
          'período anterior de mesma duração.',
        ),
      ],
    );
  }

  Widget _salesBody(BuildContext context) {
    final s = data.statistics;
    final g = data.monthlyGoal;
    final ticket = s.salesCount > 0 ? ovMoneyShort(s.totalSales / s.salesCount) : '—';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Stats(items: [
          ('VGV no período', ovMoney(s.totalSales)),
          ('Fichas', ovInt(s.salesCount)),
          ('Ticket médio', ticket),
          ('Receita', ovMoney(s.totalRevenue)),
        ]),
        if (g.hasTarget) ...[
          const _BlockTitle('Meta do mês'),
          OverviewBar(
            fraction: (g.progress / 100).clamp(0.0, 1.0).toDouble(),
            tone: g.onTrack
                ? OverviewTones.green(context)
                : OverviewTones.amber(context),
            height: 8,
          ),
          const SizedBox(height: 8),
          _Muted(
            '${ovMoney(g.current)} de ${ovMoney(g.target)} '
            '(${ovPct(g.progress, 0)}) · faltam ${ovMoney(g.remaining < 0 ? 0 : g.remaining)} '
            'em ${g.daysLeft} ${g.daysLeft == 1 ? 'dia' : 'dias'} '
            '(${ovMoneyShort(g.dailyTarget)}/dia)'
            '${data.projectedTotal > 0 ? ' · projeção ${ovMoneyShort(data.projectedTotal)}' : ''}',
          ),
        ] else
          const _Muted('Nenhuma meta mensal definida para este recorte.'),
      ],
    );
  }

  Widget _appointmentsBody(BuildContext context) {
    final a = data.appointments;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Stats(items: [
          ('Total', ovInt(a.total)),
          ('Marcados', ovInt(a.scheduled)),
          ('Realizados', ovInt(a.completed)),
          ('Cancelados', ovInt(a.cancelled)),
        ]),
        const _BlockTitle('Próximos'),
        if (a.upcoming.isEmpty)
          const _Muted('Nenhum agendamento próximo.')
        else
          ...a.upcoming.take(10).map((ap) {
            final when = ap.dateTime == null
                ? '—'
                : DateFormat('dd/MM HH:mm', 'pt_BR').format(ap.dateTime!);
            return _ListRow(
              title: ap.title,
              subtitle: ap.clientName ?? ap.propertyTitle ?? '—',
              meta: [when, _appointmentType(ap.type), ap.assignedToName ?? '—'],
            );
          }),
      ],
    );
  }

  Widget _tasksBody(BuildContext context) {
    final t = data.tasks;
    final today = DateUtils.dateOnly(DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Stats(items: [
          ('Atrasadas', ovInt(t.overdue)),
          ('Hoje', ovInt(t.dueToday)),
          ('Amanhã', ovInt(t.dueTomorrow)),
          ('Total', ovInt(t.total)),
        ]),
        const SizedBox(height: 4),
        if (t.tasks.isEmpty)
          const _Muted('Nenhuma tarefa pendente neste recorte.')
        else
          ...t.tasks.take(12).map((task) {
            final due = task.dueDate;
            final overdue =
                due != null && DateUtils.dateOnly(due).isBefore(today);
            return _ListRow(
              title: task.title,
              subtitle: task.relatedName ?? '—',
              meta: [
                due == null ? '—' : DateFormat('dd/MM', 'pt_BR').format(due),
                ovPriority(task.priority),
                task.assigneeName ?? '—',
              ],
              dangerFirstMeta: overdue,
            );
          }),
      ],
    );
  }

  Widget _documentsBody(BuildContext context) {
    final d = data.documents;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Stats(items: [
          ('Pessoais', ovInt(d.personal)),
          ('Do imóvel', ovInt(d.property)),
          ('Contratos', ovInt(d.contract)),
          ('Outros', ovInt(d.other)),
        ]),
        const SizedBox(height: 4),
        if (d.documents.isEmpty)
          const _Muted('Nenhum documento pendente neste recorte.')
        else
          ...d.documents.take(12).map((doc) {
            return _ListRow(
              title: doc.title,
              subtitle: doc.relatedName ?? '—',
              meta: [
                _documentType(doc.type),
                doc.uploadedAt == null
                    ? '—'
                    : DateFormat('dd/MM', 'pt_BR').format(doc.uploadedAt!),
                doc.uploadedByName ?? '—',
              ],
            );
          }),
      ],
    );
  }

  Widget _funnelBody(BuildContext context) {
    final s = data.statistics;
    final steps = <({String label, int value, int? prev})>[
      (label: 'Leads captados', value: s.totalLeads, prev: s.previousLeads),
      (
        label: 'Agendamentos',
        value: s.appointments,
        prev: s.previousAppointments,
      ),
      (
        label: 'Fichas finalizadas',
        value: s.salesCount,
        prev: s.previousSalesCount,
      ),
    ];
    final top = steps.first.value;
    double pctOf(int v, int base) => base > 0 ? v / base * 100 : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Stats(items: [
          ('Topo do funil', ovInt(top)),
          ('Conversão total', ovPct(s.realConversionRate)),
          ('Lead → agend.', ovPct(pctOf(steps[1].value, top))),
          ('Agend. → ficha', ovPct(pctOf(steps[2].value, steps[1].value))),
        ]),
        const _BlockTitle('Etapa a etapa'),
        for (var i = 0; i < steps.length; i++)
          Builder(builder: (context) {
            final st = steps[i];
            final prevStep = i > 0 ? steps[i - 1].value : null;
            final stepRate =
                prevStep == null ? null : pctOf(st.value, prevStep);
            final lost = prevStep == null
                ? null
                : (prevStep - st.value < 0 ? 0 : prevStep - st.value);
            final sub = StringBuffer('${ovPct(pctOf(st.value, top))} do topo');
            if (st.prev != null) {
              sub.write(' · período anterior: ${ovInt(st.prev)}');
            }
            return _ListRow(
              title: '${st.label} · ${ovInt(st.value)}',
              subtitle: sub.toString(),
              meta: [
                stepRate == null ? '—' : '${ovPct(stepRate)} da etapa anterior',
                lost == null ? '—' : '${ovInt(lost)} não avançaram',
              ],
              dangerLastMeta: (lost ?? 0) > 0,
            );
          }),
        const SizedBox(height: 8),
        const _Muted(
          'Todas as etapas usam o mesmo período e filtros da página: leads = '
          'cards criados no CRM, agendamentos = compromissos com início no '
          'período, fichas = fichas de venda finalizadas.',
        ),
      ],
    );
  }

  Widget _sourcesBody(BuildContext context) {
    final ls = data.leadSources;
    final sources = ls.sources;
    final first = sources.isEmpty ? null : sources.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Stats(items: [
          ('Leads com origem', ovInt(ls.total)),
          ('Sem origem', ovInt(ls.withoutSource)),
          ('Canais', ovInt(sources.length)),
          (
            'Principal',
            first == null
                ? '—'
                : '${first.label} (${ovPct(first.percentage, 0)})',
          ),
        ]),
        if (sources.isEmpty)
          const _Muted('Nenhum lead com origem informada neste recorte.')
        else ...[
          const _BlockTitle('Por canal'),
          _SourceBars(sources: sources),
        ],
      ],
    );
  }
}

// ─── helpers de texto ────────────────────────────────────────────────────────

String? _maskPhone(String? raw) {
  if (raw == null) return null;
  var d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.length == 13 && d.startsWith('55')) d = d.substring(2);
  if (d.length == 11) {
    return '(${d.substring(0, 2)}) ${d.substring(2, 7)}-${d.substring(7)}';
  }
  if (d.length == 10) {
    return '(${d.substring(0, 2)}) ${d.substring(2, 6)}-${d.substring(6)}';
  }
  return raw.trim().isEmpty ? null : raw.trim();
}

String _appointmentType(String type) {
  switch (type) {
    case 'visit':
      return 'Visita';
    case 'meeting':
      return 'Reunião';
    case 'call':
      return 'Ligação';
    default:
      return type.isEmpty ? '—' : type;
  }
}

String _documentType(String type) {
  switch (type.trim().toLowerCase()) {
    case 'personal_document':
      return 'Pessoal';
    case 'property_document':
      return 'Do imóvel';
    case 'contract':
      return 'Contrato';
    case 'other':
      return 'Outro';
    default:
      return type.isEmpty ? '—' : type;
  }
}

// ─── átomos ──────────────────────────────────────────────────────────────────

/// Quatro leituras em 2×2, separadas por fio (sem chapa de card).
class _Stats extends StatelessWidget {
  const _Stats({required this.items});

  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    Widget cell((String, String) it) {
      final theme = Theme.of(context);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              it.$2,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: ThemeHelpers.textColor(context),
                letterSpacing: -0.3,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              it.$1,
              maxLines: 2,
              style: theme.textTheme.labelSmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      );
    }

    final rule = OverviewTones.rule(context);
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      final left = items[i];
      final right = i + 1 < items.length ? items[i + 1] : null;
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: cell(left)),
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: rule,
              ),
              Expanded(
                child: right == null ? const SizedBox.shrink() : cell(right),
              ),
            ],
          ),
        ),
      );
      rows.add(Container(height: 1, color: rule));
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }
}

class _BlockTitle extends StatelessWidget {
  const _BlockTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: OverviewEyebrow(text),
    );
  }
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              height: 1.4,
            ),
      ),
    );
  }
}

/// Linha flush: título, linha de apoio e as colunas do web viram uma linha
/// de meta separada por " · " (no telefone não cabem quatro colunas).
class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.title,
    required this.subtitle,
    required this.meta,
    this.dangerFirstMeta = false,
    this.dangerLastMeta = false,
  });

  final String title;
  final String subtitle;
  final List<String> meta;
  final bool dangerFirstMeta;
  final bool dangerLastMeta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final danger = OverviewTones.red(context);
    final metaStyle = theme.textTheme.labelSmall?.copyWith(
      color: secondary,
      fontWeight: FontWeight.w600,
      height: 1.35,
    );
    final spans = <InlineSpan>[];
    for (var i = 0; i < meta.length; i++) {
      if (i > 0) spans.add(const TextSpan(text: ' · '));
      final isDanger = (i == 0 && dangerFirstMeta) ||
          (i == meta.length - 1 && dangerLastMeta);
      spans.add(
        TextSpan(
          text: meta[i],
          style: isDanger
              ? TextStyle(color: danger, fontWeight: FontWeight.w800)
              : null,
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: OverviewTones.rule(context))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: secondary),
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text.rich(
              TextSpan(children: spans),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: metaStyle,
            ),
          ],
        ],
      ),
    );
  }
}

/// Régua por canal: nome, contagem, percentual e barra (maior em aço, os
/// demais em pedra — o maior canal é a informação que importa).
class _SourceBars extends StatelessWidget {
  const _SourceBars({required this.sources});

  final List<OverviewLeadSource> sources;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sky = OverviewTones.sky(context);
    final slate = OverviewTones.slate(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < sources.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        sources[i].label,
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
                      '${ovInt(sources[i].count)} · ${ovPct(sources[i].percentage)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ThemeHelpers.textSecondaryColor(context),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                OverviewBar(
                  fraction: sources[i].percentage / 100,
                  tone: i == 0 ? sky : slate.withValues(alpha: 0.75),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
