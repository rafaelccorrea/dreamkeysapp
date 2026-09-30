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

/// Tinta do detalhe — a mesma do indicador que o abriu na Home (aço para o
/// que entra, pedra para número derivado, musgo para venda, âmbar para
/// agenda, vermelho para atraso).
Color _toneOf(BuildContext context, OverviewDetailKind k) {
  switch (k) {
    case OverviewDetailKind.leads:
    case OverviewDetailKind.documents:
    case OverviewDetailKind.funnel:
    case OverviewDetailKind.sources:
      return OverviewTones.sky(context);
    case OverviewDetailKind.conversion:
      return OverviewTones.slate(context);
    case OverviewDetailKind.sales:
      return OverviewTones.green(context);
    case OverviewDetailKind.appointments:
      return OverviewTones.amber(context);
    case OverviewDetailKind.tasks:
      return OverviewTones.red(context);
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
    final tone = _toneOf(context, kind);
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
                color: ThemeHelpers.borderColor(context),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          // Título à esquerda com a chapa na tinta do indicador que abriu o
          // detalhe; fechar à direita.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 8, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: OverviewTones.wash(context, tone),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(meta.icon, size: 20, color: tone),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meta.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: ThemeHelpers.textColor(context),
                          letterSpacing: -0.3,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        meta.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
              // Sem o atalho do rodapé, o fim da rolagem respeita a barra de
              // gestos (o SafeArea do sheet não cobre a borda de baixo).
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                20 + (ctaRoute == null ? mq.padding.bottom : 0),
              ),
              child: _body(context),
            ),
          ),
          if (ctaRoute != null)
            Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: OverviewTones.rule(context)),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                  // Atalho de navegação: neutro (não é confirmar nem criar),
                  // com corpo de controle e a seta de "ir". Altura MÍNIMA de
                  // 48 com padding próprio: cravado em 48 com o padding
                  // vertical 16 do tema, sobravam 16dp para o rótulo e o
                  // `FittedBox` o encolhia para ~60% com fonte em 130%.
                  child: OutlinedButton(
                    onPressed: () {
                      final nav = Navigator.of(context);
                      nav.pop();
                      nav.pushNamed(ctaRoute);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ThemeHelpers.textColor(context),
                      backgroundColor: OverviewTones.track(context),
                      side: BorderSide(
                        color: ThemeHelpers.borderLightColor(context),
                      ),
                      minimumSize: const Size.fromHeight(48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
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
    final sources = data.leadSources.sources;
    final shown = data.leads.leads.take(10).toList(growable: false);
    final total = data.statistics.totalLeads;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Stats(items: [
          _StatItem('Leads no período', ovInt(total)),
          _StatItem('Novos hoje', ovInt(data.leads.newToday)),
          _StatItem('Pontuação média', ovInt(data.leads.avgScore.round())),
          _StatItem('Sem origem', ovInt(data.leadSources.withoutSource)),
        ]),
        if (sources.isNotEmpty) ...[
          const _BlockTitle('De onde vieram'),
          _SourceBars(sources: sources.take(8).toList(growable: false)),
        ],
        _BlockTitle(
          'Mais recentes',
          note: shown.isNotEmpty && total > shown.length
              ? '${ovInt(shown.length)} de ${ovInt(total)}'
              : null,
        ),
        if (shown.isEmpty)
          const _Muted(
            'Nenhum lead entrou neste recorte. Amplie o período nos filtros '
            'para ver os anteriores.',
          )
        else
          for (final l in shown)
            _ListRow(
              title: l.name,
              subtitle: [l.location, _maskPhone(l.phone)]
                  .whereType<String>()
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .join(' · '),
              bits: [
                _bit(LucideIcons.radioTower, ovSource(l.source)),
                _bit(LucideIcons.circleDot, ovLeadStatus(l.status)),
                _bit(LucideIcons.userRound, l.assignedToName),
              ],
            ),
      ],
    );
  }

  Widget _conversionBody(BuildContext context) {
    final s = data.statistics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Stats(items: [
          _StatItem('Leads', ovInt(s.totalLeads)),
          _StatItem('Agendamentos', ovInt(s.appointments)),
          _StatItem('Fichas finalizadas', ovInt(s.salesCount)),
          _StatItem('Conversão', ovPct(s.realConversionRate)),
        ]),
        const _BlockTitle('A conta'),
        // A fórmula desenhada: o número que a pessoa vê no indicador sai
        // desta divisão, com os mesmos números da tela.
        _Formula(
          numerator: (
            ovInt(s.salesCount),
            s.salesCount == 1 ? 'ficha finalizada' : 'fichas finalizadas',
          ),
          denominator: (ovInt(s.totalLeads), 'leads captados'),
          result: (ovPct(s.realConversionRate), 'conversão'),
        ),
        const SizedBox(height: 12),
        const _Muted(
          'Conversão = fichas de venda finalizadas ÷ leads captados, os dois '
          'no mesmo período e filtros da tela. Com a comparação ligada nos '
          'filtros, a seta do indicador compara com o período escolhido lá.',
        ),
      ],
    );
  }

  Widget _salesBody(BuildContext context) {
    final s = data.statistics;
    final g = data.monthlyGoal;
    final ticket = s.salesCount > 0 ? ovMoneyShort(s.totalSales / s.salesCount) : '—';
    final progress = g.progress.clamp(0.0, 100.0).toDouble();
    final remaining = g.remaining < 0 ? 0.0 : g.remaining;
    final surplus = g.remaining < 0 ? -g.remaining : 0.0;
    // Mesma cor do anel da Home: musgo batida, âmbar fora do ritmo, marca no
    // caminho normal — a régua não pode contar outra história.
    final tone = progress >= 100
        ? OverviewTones.green(context)
        : (!g.onTrack
            ? OverviewTones.amber(context)
            : OverviewTones.brand(context));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Stats(items: [
          _StatItem('VGV no período', ovMoney(s.totalSales)),
          _StatItem('Fichas finalizadas', ovInt(s.salesCount)),
          _StatItem('Ticket médio', ticket),
          _StatItem('Receita', ovMoney(s.totalRevenue)),
        ]),
        if (g.hasTarget) ...[
          _BlockTitle('Meta do mês', note: '${ovPct(g.progress, 0)} atingido'),
          OverviewBar(fraction: progress / 100, tone: tone, height: 8),
          const SizedBox(height: 6),
          // A conta da meta em linhas (antes era uma frase corrida com seis
          // números entre parênteses).
          _KeyLine(label: 'Atingido', value: ovMoney(g.current)),
          _KeyLine(label: 'Meta', value: ovMoney(g.target)),
          if (remaining > 0) ...[
            _KeyLine(
              label: 'Faltam',
              value: ovMoney(remaining),
              icon: LucideIcons.hourglass,
              tone: OverviewTones.amber(context),
            ),
            _KeyLine(
              label: 'Prazo',
              value: '${ovInt(g.daysLeft)} ${g.daysLeft == 1 ? 'dia' : 'dias'}',
            ),
            if (g.dailyTarget > 0)
              _KeyLine(
                label: 'Ritmo necessário',
                value: '${ovMoneyShort(g.dailyTarget)}/dia',
              ),
          ] else
            _KeyLine(
              label: surplus > 0 ? 'Acima da meta' : 'Situação',
              value: surplus > 0 ? '+${ovMoney(surplus)}' : 'Meta batida',
              icon: LucideIcons.circleCheck,
              tone: OverviewTones.green(context),
            ),
          if (data.projectedTotal > 0)
            _KeyLine(
              label: 'Projeção do mês',
              value: ovMoneyShort(data.projectedTotal),
              icon: LucideIcons.trendingUp,
            ),
        ] else
          const _Muted(
            'Nenhuma meta mensal definida para este recorte. Quando houver '
            'meta cadastrada, o progresso do mês aparece aqui.',
          ),
      ],
    );
  }

  Widget _appointmentsBody(BuildContext context) {
    final a = data.appointments;
    final shown = a.upcoming.take(10).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Stats(items: [
          _StatItem('Total', ovInt(a.total)),
          _StatItem('Marcados', ovInt(a.scheduled)),
          _StatItem('Realizados', ovInt(a.completed)),
          _StatItem('Cancelados', ovInt(a.cancelled)),
        ]),
        const _BlockTitle('Próximos'),
        if (shown.isEmpty)
          const _Muted(
            'Nenhum compromisso marcado para os próximos dias. Visitas e '
            'reuniões criadas na agenda aparecem aqui.',
          )
        else
          for (final ap in shown)
            _ListRow(
              title: ap.title,
              subtitle: _firstFilled([ap.clientName, ap.propertyTitle]),
              bits: [
                _bit(
                  LucideIcons.clock3,
                  ap.dateTime == null
                      ? null
                      : DateFormat("dd/MM 'às' HH:mm", 'pt_BR')
                          .format(ap.dateTime!),
                ),
                _bit(LucideIcons.calendarDays, _appointmentType(ap.type)),
                _bit(LucideIcons.userRound, ap.assignedToName),
              ],
            ),
      ],
    );
  }

  Widget _tasksBody(BuildContext context) {
    final t = data.tasks;
    final today = DateUtils.dateOnly(DateTime.now());
    final shown = t.tasks.take(12).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Stats(items: [
          _StatItem('Atrasadas', ovInt(t.overdue)),
          _StatItem('Vencem hoje', ovInt(t.dueToday)),
          _StatItem('Vencem amanhã', ovInt(t.dueTomorrow)),
          _StatItem('Total', ovInt(t.total)),
        ]),
        _BlockTitle(
          'Pendentes',
          note: shown.isNotEmpty && t.total > shown.length
              ? '${ovInt(shown.length)} de ${ovInt(t.total)}'
              : null,
        ),
        if (shown.isEmpty)
          const _Muted(
            'Nenhuma tarefa pendente neste recorte — nada atrasado nem '
            'vencendo.',
          )
        else
          for (final task in shown)
            Builder(builder: (context) {
              final due = task.dueDate;
              final day = due == null ? null : DateUtils.dateOnly(due);
              final overdue = day != null && day.isBefore(today);
              final isToday = day != null && DateUtils.isSameDay(day, today);
              // O prazo dito por extenso: "venceu 12/09" em vermelho diz o
              // atraso sem depender só da cor.
              final String? when = day == null
                  ? null
                  : overdue
                      ? 'venceu ${DateFormat('dd/MM', 'pt_BR').format(day)}'
                      : isToday
                          ? 'vence hoje'
                          : 'vence ${DateFormat('dd/MM', 'pt_BR').format(day)}';
              return _ListRow(
                title: task.title,
                subtitle: task.relatedName,
                bits: [
                  _bit(LucideIcons.calendarClock, when, danger: overdue),
                  _bit(LucideIcons.flag, ovPriority(task.priority)),
                  _bit(LucideIcons.userRound, task.assigneeName),
                ],
              );
            }),
      ],
    );
  }

  Widget _documentsBody(BuildContext context) {
    final d = data.documents;
    final shown = d.documents.take(12).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Stats(items: [
          _StatItem('Pessoais', ovInt(d.personal)),
          _StatItem('Do imóvel', ovInt(d.property)),
          _StatItem('Contratos', ovInt(d.contract)),
          _StatItem('Outros', ovInt(d.other)),
        ]),
        const _BlockTitle('Aguardando conferência'),
        if (shown.isEmpty)
          const _Muted('Nenhum documento esperando conferência neste recorte.')
        else
          for (final doc in shown)
            _ListRow(
              title: doc.title,
              subtitle: doc.relatedName,
              bits: [
                _bit(LucideIcons.fileText, _documentType(doc.type)),
                _bit(
                  LucideIcons.calendarDays,
                  doc.uploadedAt == null
                      ? null
                      : 'enviado ${DateFormat('dd/MM', 'pt_BR').format(doc.uploadedAt!)}',
                ),
                _bit(LucideIcons.userRound, doc.uploadedByName),
              ],
            ),
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
          _StatItem('Topo do funil', ovInt(top)),
          _StatItem('Conversão total', ovPct(s.realConversionRate)),
          _StatItem('Lead → agendamento', ovPct(pctOf(steps[1].value, top))),
          _StatItem(
            'Agendamento → ficha',
            ovPct(pctOf(steps[2].value, steps[1].value)),
          ),
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
              bits: [
                if (stepRate != null)
                  _bit(
                    LucideIcons.percent,
                    '${ovPct(stepRate)} da etapa anterior',
                  ),
                if (lost != null)
                  _bit(
                    LucideIcons.trendingDown,
                    lost == 1
                        ? '1 não avançou'
                        : '${ovInt(lost)} não avançaram',
                    danger: lost > 0,
                  ),
              ],
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
          _StatItem('Leads com origem', ovInt(ls.total)),
          _StatItem('Sem origem', ovInt(ls.withoutSource)),
          _StatItem('Canais', ovInt(sources.length)),
          // O nome do canal quebra linha em vez de encolher; o percentual
          // vai para o rótulo.
          _StatItem(
            first == null
                ? 'Canal principal'
                : 'Canal principal · ${ovPct(first.percentage, 0)}',
            first?.label ?? '—',
            isText: true,
          ),
        ]),
        if (sources.isEmpty)
          const _Muted(
            'Nenhum lead com origem informada neste recorte. A origem vem do '
            'canal por onde o lead chegou (site, portais, WhatsApp).',
          )
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

/// Primeiro texto preenchido (nulo se nenhum).
String? _firstFilled(List<String?> values) {
  for (final v in values) {
    final t = v?.trim() ?? '';
    if (t.isNotEmpty) return t;
  }
  return null;
}

/// Código desconhecido vindo do back ("follow_up") vira texto legível
/// ("Follow up") em vez de aparecer cru.
String _pretty(String raw) {
  final t = raw.trim().replaceAll(RegExp(r'[_-]+'), ' ');
  if (t.isEmpty) return '';
  return t[0].toUpperCase() + t.substring(1);
}

String _appointmentType(String type) {
  switch (type.trim().toLowerCase()) {
    case 'visit':
      return 'Visita';
    case 'meeting':
      return 'Reunião';
    case 'call':
      return 'Ligação';
    case 'inspection':
      return 'Vistoria';
    case 'other':
      return 'Outro';
    default:
      return _pretty(type);
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
      return _pretty(type);
  }
}

// ─── átomos ──────────────────────────────────────────────────────────────────

/// Um par rótulo/valor da grade de leituras.
class _StatItem {
  const _StatItem(this.label, this.value, {this.isText = false});

  final String label;
  final String value;

  /// O valor é um nome (canal), não um número: quebra em até duas linhas em
  /// vez de encolher.
  final bool isText;
}

/// Quatro leituras em 2×2, separadas por fio (sem chapa de card). Número
/// nunca quebra linha: encolhe para caber (R$ 12.500.000 em 320dp com fonte
/// grande quebrava em "R$" / "12.500.000").
class _Stats extends StatelessWidget {
  const _Stats({required this.items});

  final List<_StatItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w900,
      color: ThemeHelpers.textColor(context),
      letterSpacing: -0.3,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget cell(_StatItem it) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (it.isText)
              Text(
                it.value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: valueStyle?.copyWith(height: 1.2),
              )
            else
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  it.value,
                  maxLines: 1,
                  softWrap: false,
                  style: valueStyle,
                ),
              ),
            const SizedBox(height: 2),
            Text(
              it.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                height: 1.25,
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

/// Cabeça de bloco, com a contagem do recorte à direita quando a lista
/// mostra só parte ("10 de 45").
class _BlockTitle extends StatelessWidget {
  const _BlockTitle(this.text, {this.note});

  final String text;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final n = note;
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: OverviewEyebrow(text)),
          if (n != null) ...[
            const SizedBox(width: 8),
            Text(
              n,
              maxLines: 1,
              softWrap: false,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
          ],
        ],
      ),
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

/// Linha rótulo → valor (a conta da meta). O estado vem no ícone tingido;
/// o valor fica no tom do texto — âmbar e verde miúdos não passam contraste
/// no claro.
class _KeyLine extends StatelessWidget {
  const _KeyLine({
    required this.label,
    required this.value,
    this.icon,
    this.tone,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final glyph = icon;
    final labelText = Text(
      label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: secondary,
        fontWeight: FontWeight.w600,
        height: 1.25,
      ),
    );
    // O valor tem prioridade sobre o rótulo: lado a lado, cada um ficava com
    // metade da linha e "R$ 12.500.000" saía "R$ 12.500.…" (um número
    // errado) em 320dp com fonte grande. Dinheiro encolhe, nunca corta.
    Widget valueLine({required bool end}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (glyph != null) ...[
              Icon(glyph, size: 14, color: tone ?? secondary),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: end ? Alignment.centerRight : Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  softWrap: false,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: OverviewTones.rule(context))),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          // Linha estreita demais para o par (fonte muito grande): o valor
          // desce para baixo do rótulo.
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          if (c.maxWidth < 176 * scale) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                labelText,
                const SizedBox(height: 1),
                valueLine(end: false),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: labelText),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: c.maxWidth * 0.62),
                child: valueLine(end: true),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A conta da conversão desenhada: "12 fichas ÷ 300 leads = 4,0%". Em tela
/// estreita (ou fonte grande) o resultado desce de linha em vez de estourar.
class _Formula extends StatelessWidget {
  const _Formula({
    required this.numerator,
    required this.denominator,
    required this.result,
  });

  /// (valor, rótulo).
  final (String, String) numerator;
  final (String, String) denominator;
  final (String, String) result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    Widget term((String, String) t) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.$1,
              maxLines: 1,
              softWrap: false,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: textColor,
                height: 1.1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              t.$2,
              maxLines: 1,
              softWrap: false,
              style: theme.textTheme.labelSmall?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        );
    Widget op(String s) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            s,
            style: theme.textTheme.titleMedium?.copyWith(
              color: secondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        term(numerator),
        op('÷'),
        term(denominator),
        op('='),
        // O resultado ganha a chapa neutra de campo: é o número da tela.
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: OverviewTones.track(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ThemeHelpers.borderLightColor(context)),
          ),
          child: term(result),
        ),
      ],
    );
  }
}

/// Pedaço da linha de meta de um item (ícone + texto; `danger` pinta de
/// vermelho — atraso, perda).
typedef _Bit = ({IconData icon, String text, bool danger});

_Bit _bit(IconData icon, String? text, {bool danger = false}) =>
    (icon: icon, text: text?.trim() ?? '', danger: danger);

/// Linha flush: título, linha de apoio e as colunas do web viram pedaços com
/// ícone (quando, quem, estado) que quebram linha em `Wrap` — no telefone não
/// cabem quatro colunas. Dado que não veio SOME da linha: nada de "—" solto.
class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.title,
    this.subtitle,
    this.bits = const [],
  });

  final String title;
  final String? subtitle;
  final List<_Bit> bits;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final danger = OverviewTones.red(context);
    final sub = subtitle?.trim() ?? '';
    final shown = bits
        .where((b) => b.text.isNotEmpty && b.text != '—')
        .toList(growable: false);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
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
              height: 1.25,
            ),
          ),
          if (sub.isNotEmpty && sub != '—') ...[
            const SizedBox(height: 2),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: secondary),
            ),
          ],
          if (shown.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final b in shown)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        b.icon,
                        size: 12,
                        color: b.danger ? danger : secondary,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          b.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: b.danger ? danger : secondary,
                            fontWeight:
                                b.danger ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
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
                      maxLines: 1,
                      softWrap: false,
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
