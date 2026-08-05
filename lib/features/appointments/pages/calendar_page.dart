import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/navigation/adaptive_page_route.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/minimal_body_chrome.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../controllers/appointment_controller.dart';
import '../models/appointment_model.dart';
import '../widgets/appointment_card.dart';
import '../widgets/appointment_filters_sheet.dart';
import '../widgets/appointment_helpers.dart';
import '../widgets/view_mode_selector.dart';
import 'appointment_details_page.dart';
import 'create_appointment_page.dart';

/// Tela premium de Agenda — concentra calendário, indicadores, busca/filtros,
/// múltiplas visualizações (Mês / Semana / Agenda) e timeline detalhado do dia.
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage>
    with TickerProviderStateMixin {
  // Controle do calendário
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  CalendarFormat _tableFormat = CalendarFormat.month;
  CalendarViewMode _viewMode = CalendarViewMode.month;

  // Busca / filtros locais
  final TextEditingController _searchController = TextEditingController();
  bool _searchOpen = false;
  late final FocusNode _searchFocusNode;
  CalendarFiltersState _filters = const CalendarFiltersState();

  // Cache para markers do calendário (evita rebuild pesado)
  Map<String, List<Appointment>> _eventsByDay = const {};
  List<Appointment> _lastSeenSource = const [];

  @override
  void initState() {
    super.initState();
    _searchFocusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ctrl = context.read<AppointmentController>();
      // Novo modelo: escopo persistido + janela derivada da navegação.
      await ctrl.restoreScope();
      ctrl.ensureWindowCovers(_focusedDay);
      await ctrl.loadAppointments(reset: true);
      await ctrl.loadPendingInvites();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  /// Aplica filtros locais (status / tipo / período / minhas) sobre a lista
  /// retornada pelo controller.
  List<Appointment> _applyLocalFilters(List<Appointment> input) {
    var result = input;
    if (_filters.status != null) {
      result = result.where((a) => a.status == _filters.status).toList();
    }
    if (_filters.type != null) {
      result = result.where((a) => a.type == _filters.type).toList();
    }
    if (_filters.startDate != null && _filters.endDate != null) {
      final s = DateTime(
        _filters.startDate!.year,
        _filters.startDate!.month,
        _filters.startDate!.day,
      );
      final e = DateTime(
        _filters.endDate!.year,
        _filters.endDate!.month,
        _filters.endDate!.day,
        23,
        59,
        59,
      );
      result = result
          .where((a) => !a.startDate.isBefore(s) && !a.startDate.isAfter(e))
          .toList();
    }
    return result;
  }

  Map<String, List<Appointment>> _bucketize(List<Appointment> source) {
    if (identical(source, _lastSeenSource) && _eventsByDay.isNotEmpty) {
      return _eventsByDay;
    }
    final map = <String, List<Appointment>>{};
    for (final a in source) {
      final key = AppointmentVisuals.dayKey(a.startDate);
      map.putIfAbsent(key, () => []).add(a);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.startDate.compareTo(b.startDate));
    }
    _eventsByDay = map;
    _lastSeenSource = source;
    return map;
  }

  List<Appointment> _eventsFor(DateTime day) {
    return _eventsByDay[AppointmentVisuals.dayKey(day)] ?? const [];
  }

  void _openCreate({DateTime? date}) {
    final base = date ?? _selectedDay;
    final now = DateTime.now();

    // Guard do novo modelo: dia no PASSADO não abre o formulário — explica
    // e oferece o dia de hoje (paridade com o aviso âmbar do web).
    final baseDay = DateTime(base.year, base.month, base.day);
    final today = DateTime(now.year, now.month, now.day);
    if (baseDay.isBefore(today)) {
      _showPastDayNotice(baseDay);
      return;
    }

    final start = DateTime(
      base.year,
      base.month,
      base.day,
      base.year == now.year && base.month == now.month && base.day == now.day
          ? math.min(now.hour + 1, 23)
          : 9,
      0,
    );
    Navigator.push(
      context,
      adaptivePageRoute<void>(
        builder: (_) => CreateAppointmentPage(
          initialStartDate: start,
          initialEndDate: start.add(const Duration(hours: 1)),
        ),
      ),
    ).then((_) {
      if (!mounted) return;
      context.read<AppointmentController>().loadAppointments(reset: true);
    });
  }

  void _openDetails(Appointment a) {
    Navigator.push(
      context,
      adaptivePageRoute<void>(
        builder: (_) => AppointmentDetailsPage(appointmentId: a.id),
      ),
    ).then((_) {
      if (!mounted) return;
      context.read<AppointmentController>().loadAppointments(reset: true);
    });
  }

  void _openFilters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AppointmentFiltersSheet(
        initial: _filters,
        onApply: (f) {
          setState(() => _filters = f);
          context.read<AppointmentController>().setFilters(
            status: f.status?.value,
            type: f.type?.value,
            startDate: f.startDate,
            endDate: f.endDate,
            onlyMyData: f.onlyMyData,
          );
          context.read<AppointmentController>().loadAppointments(reset: true);
        },
      ),
    );
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (_searchOpen) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _searchFocusNode.requestFocus(),
        );
      } else {
        _searchController.clear();
        context.read<AppointmentController>().setSearchTerm('');
      }
    });
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Agenda',
      currentBottomNavIndex: 2,
      actions: [
        ChromeToolbarIconButton(
          icon: _searchOpen ? Icons.close_rounded : Icons.search_rounded,
          tooltip: _searchOpen ? 'Fechar busca' : 'Buscar',
          onPressed: _toggleSearch,
        ),
        // Máximo de 2 ícones na navbar: busca + filtros. O escopo de
        // pessoas vive como chip na ContextBar, não como terceiro ícone.
        Stack(
          clipBehavior: Clip.none,
          children: [
            ChromeToolbarIconButton(
              icon: Icons.tune_rounded,
              tooltip: 'Filtros',
              onPressed: _openFilters,
            ),
            if (_filters.hasActiveFilters)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.primary.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.scaffoldBackgroundColor,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
      body: Consumer<AppointmentController>(
        builder: (context, ctrl, _) {
          if (ctrl.loading && ctrl.appointments.isEmpty) {
            return _buildSkeleton(theme);
          }
          if (ctrl.error != null && ctrl.appointments.isEmpty) {
            return _buildErrorState(theme, ctrl);
          }

          final filtered = _applyLocalFilters(ctrl.filteredAppointments);
          _bucketize(filtered);

          return RefreshIndicator(
            color: AppColors.primary.primary,
            onRefresh: () async {
              await ctrl.loadAppointments(reset: true);
              await ctrl.loadPendingInvites();
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOutCubic,
                    child: _searchOpen
                        ? _buildSearchBar(ctrl, theme)
                        : const SizedBox.shrink(),
                  ),
                ),
                // Novo modelo (paridade com o web): sem hero nem cards de
                // stats — "uma barra de contexto e a grade".
                SliverToBoxAdapter(
                  child: _buildContextBar(ctrl, theme, filtered),
                ),
                SliverToBoxAdapter(child: _buildViewModeSection(theme)),
                if (_viewMode == CalendarViewMode.month ||
                    _viewMode == CalendarViewMode.week)
                  SliverToBoxAdapter(child: _buildCalendar(theme))
                else
                  SliverToBoxAdapter(child: _buildAgendaList(filtered, theme)),
                if (_viewMode != CalendarViewMode.agenda)
                  SliverToBoxAdapter(child: _buildSelectedDayHeader(theme)),
                if (_viewMode != CalendarViewMode.agenda)
                  SliverToBoxAdapter(child: _buildSelectedDayList(theme)),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SEARCH BAR
  // ---------------------------------------------------------------------------
  Widget _buildSearchBar(AppointmentController ctrl, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ThemeHelpers.borderColor(context)),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          decoration: InputDecoration(
            hintText: 'Buscar por título, descrição ou local…',
            hintStyle: TextStyle(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w500,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: AppColors.primary.primary,
            ),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded),
                    onPressed: () {
                      _searchController.clear();
                      ctrl.setSearchTerm('');
                      setState(() {});
                    },
                  )
                : null,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
          ),
          onChanged: (v) {
            ctrl.setSearchTerm(v);
            setState(() {});
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CONTEXT BAR — novo modelo ("uma barra de contexto e a grade")
  // ---------------------------------------------------------------------------

  /// Tons da barra de contexto — EXATOS do web (`CONTEXT_TONES`):
  /// quente → fria → neutra; a cor só acende quando o valor > 0.
  static const Color _toneToday = Color(0xFFE6B84C);
  static const Color _toneWeek = Color(0xFF0D9488);
  static const Color _toneRange = Color(0xFF64748B);
  static const Color _toneInvites = Color(0xFF4A90E2);
  static const Color _toneSchedule = Color(0xFF3FA66B);

  static String _capitalizeFirst(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// Barra de contexto flush: hoje por extenso + pílulas de contagem +
  /// próximo compromisso + atalhos (Convites com badge / Meus horários).
  /// Substitui o hero premium + 5 stats + pill morta do modelo antigo.
  Widget _buildContextBar(
    AppointmentController ctrl,
    ThemeData theme,
    List<Appointment> filtered,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekEnd = today.add(const Duration(days: 7));
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final hairline =
        ThemeHelpers.borderColor(context).withValues(alpha: 0.35);

    final todayCount =
        filtered.where((a) => _isSameDay(a.startDate, today)).length;
    final weekCount = filtered
        .where(
          (a) => !a.startDate.isBefore(today) && a.startDate.isBefore(weekEnd),
        )
        .length;
    final rangeCount = filtered.length;

    final next = filtered
        .where((a) => !a.endDate.isBefore(now))
        .fold<Appointment?>(
          null,
          (acc, a) =>
              acc == null || a.startDate.isBefore(acc.startDate) ? a : acc,
        );

    final pending = ctrl.pendingInvites.length;
    final isTodaySelected = _isSameDay(_selectedDay, today);
    final todayLine = _capitalizeFirst(
      DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(now),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Linha 1 — hoje por extenso + atalho "Hoje" quando fora dele.
          Row(
            children: [
              Expanded(
                child: Text(
                  todayLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                    fontSize: 16.5,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
              ),
              if (!isTodaySelected)
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => setState(() {
                    _selectedDay = today;
                    _focusedDay = today;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: _toneToday.withValues(alpha: 0.55),
                      ),
                    ),
                    child: Text(
                      'Hoje',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: _toneToday,
                        letterSpacing: 0.3,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Linha 2 — pílulas de contagem (acendem quando > 0).
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _contextCount(theme, _toneToday, todayCount, 'hoje'),
              _contextCount(theme, _toneWeek, weekCount, 'em 7 dias'),
              _contextCount(theme, _toneRange, rangeCount, 'no período'),
            ],
          ),

          // Linha 3 — próximo compromisso (link pro detalhe).
          if (next != null) ...[
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _openDetails(next),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_arrow_rounded, size: 15, color: secondary),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      'Próximo: ${next.title} · '
                      '${DateFormat('HH:mm').format(next.startDate)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: secondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(Icons.chevron_right_rounded,
                      size: 15, color: secondary),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),

          // Linha 4 — atalhos do modelo novo: Escopo (de quem é a agenda) +
          // Convites (badge) + Meus horários. O escopo saiu da navbar e
          // vive aqui; preenchido quando difere de "minha agenda".
          Row(
            children: [
              Expanded(
                child: _contextAction(
                  theme,
                  icon: Icons.group_rounded,
                  label: _scopeChipLabel(ctrl),
                  tone: _toneInvites,
                  filled: ctrl.hasCustomScope,
                  chevron: true,
                  onTap: _openScopeSheet,
                ),
              ),
              if (pending > 0) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _contextAction(
                    theme,
                    icon: Icons.mark_email_unread_rounded,
                    label:
                        '$pending convite${pending > 1 ? 's' : ''} pendente${pending > 1 ? 's' : ''}',
                    tone: _toneInvites,
                    filled: true,
                    onTap: _openInvites,
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Expanded(
                child: _contextAction(
                  theme,
                  icon: Icons.schedule_rounded,
                  label: 'Meus horários',
                  tone: _toneSchedule,
                  filled: false,
                  onTap: _openScheduleSettings,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: hairline),
        ],
      ),
    );
  }

  Widget _contextCount(ThemeData theme, Color tone, int value, String label) {
    final on = value > 0;
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? tone : muted.withValues(alpha: 0.35),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$value $label',
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 11.5,
            color: on ? ThemeHelpers.textColor(context) : muted,
            fontFeatures: const [FontFeature.tabularFigures()],
            height: 1,
          ),
        ),
      ],
    );
  }

  /// Rótulo do chip de escopo: "Minha agenda" / "Toda a empresa" /
  /// "N agenda(s)" quando há seleção de pessoas.
  String _scopeChipLabel(AppointmentController ctrl) {
    if (ctrl.scopeAllCompany) return 'Toda a empresa';
    final n = ctrl.scopeUserIds.length;
    if (n == 0) return 'Minha agenda';
    return '$n agenda${n > 1 ? 's' : ''}';
  }

  Widget _contextAction(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required Color tone,
    required bool filled,
    required VoidCallback onTap,
    bool chevron = false,
  }) {
    return Material(
      color: filled ? tone : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: filled
                ? null
                : Border.all(color: tone.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: filled ? Colors.white : tone),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: filled ? Colors.white : tone,
                    height: 1,
                  ),
                ),
              ),
              if (chevron) ...[
                const SizedBox(width: 2),
                Icon(
                  Icons.expand_more_rounded,
                  size: 14,
                  color: filled ? Colors.white : tone,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Aviso âmbar de dia no passado — compara a data escolhida com a mais
  /// cedo possível e oferece agendar hoje (paridade com o modal do web).
  void _showPastDayNotice(DateTime chosenDay) {
    final theme = Theme.of(context);
    const amber = Color(0xFFE6B84C);
    final now = DateTime.now();
    final fmt = DateFormat("EEE, d 'de' MMM", 'pt_BR');

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final muted = ThemeHelpers.textSecondaryColor(sheetContext);
        return Container(
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(sheetContext),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(26)),
          ),
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 20),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: muted.withValues(alpha: 0.32),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: amber.withValues(alpha: 0.14),
                        border:
                            Border.all(color: amber.withValues(alpha: 0.4)),
                      ),
                      child: const Icon(Icons.history_toggle_off_rounded,
                          size: 20, color: amber),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Esse dia já passou',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                          color: ThemeHelpers.textColor(sheetContext),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Agendamentos só podem ser criados de hoje em diante.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: muted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _pastNoticeCell(
                        theme,
                        sheetContext,
                        label: 'ESCOLHIDA',
                        value: _capitalizeFirst(fmt.format(chosenDay)),
                        tone: amber,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _pastNoticeCell(
                        theme,
                        sheetContext,
                        label: 'MAIS CEDO POSSÍVEL',
                        value: _capitalizeFirst(fmt.format(now)),
                        tone: const Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        style: TextButton.styleFrom(foregroundColor: muted),
                        child: const Text('Fechar'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          _openCreate(date: now);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                        ),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Agendar hoje',
                              maxLines: 1, softWrap: false),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _pastNoticeCell(
    ThemeData theme,
    BuildContext cellContext, {
    required String label,
    required String value,
    required Color tone,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(shape: BoxShape.circle, color: tone),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800,
                  fontSize: 9.5,
                  color: ThemeHelpers.textSecondaryColor(cellContext),
                  height: 1,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            letterSpacing: -0.2,
            color: ThemeHelpers.textColor(cellContext),
          ),
        ),
      ],
    );
  }

  void _openInvites() {
    Navigator.of(context).pushNamed('/calendar/convites').then((_) {
      if (!mounted) return;
      final ctrl = context.read<AppointmentController>();
      ctrl.loadAppointments(reset: true);
      ctrl.loadPendingInvites();
    });
  }

  void _openScheduleSettings() {
    Navigator.of(context).pushNamed('/calendar/horarios');
  }

  // ---------------------------------------------------------------------------
  // ESCOPO DE PESSOAS (minha agenda / seleção / toda a empresa)
  // ---------------------------------------------------------------------------

  /// Membros da empresa (cache da sessão) — `GET /users/company-members/simple`.
  List<({String id, String name})>? _members;
  bool _loadingMembers = false;

  Future<void> _ensureMembersLoaded(StateSetter refresh) async {
    if (_members != null || _loadingMembers) return;
    _loadingMembers = true;
    refresh(() {});
    try {
      final res = await ApiService.instance
          .get<dynamic>('/users/company-members/simple');
      final raw = res.data;
      final list = raw is List
          ? raw
          : (raw is Map && raw['data'] is List ? raw['data'] as List : const []);
      _members = list
          .whereType<Map>()
          .map((e) => (
                id: e['id']?.toString() ?? '',
                name: e['name']?.toString() ?? '',
              ))
          .where((m) => m.id.isNotEmpty && m.name.isNotEmpty)
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } catch (_) {
      _members = [];
    }
    _loadingMembers = false;
    if (mounted) refresh(() {});
  }

  /// Paleta de cores ESTÁVEIS para o avatar-inicial dos membros — a cor
  /// deriva de um hash do nome, então a mesma pessoa fica sempre igual.
  static const List<Color> _memberAvatarPalette = [
    Color(0xFF0EA5E9),
    Color(0xFF14B8A6),
    Color(0xFF6366F1),
    Color(0xFFF97316),
    Color(0xFF22C55E),
    Color(0xFFEC4899),
    Color(0xFFA855F7),
    Color(0xFF0891B2),
  ];

  static Color _memberAvatarColor(String name) {
    var hash = 0;
    for (final unit in name.toLowerCase().codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return _memberAvatarPalette[hash % _memberAvatarPalette.length];
  }

  /// Azul do escopo — mesmo tom dos convites na ContextBar.
  static const Color _scopeAccent = _toneInvites;

  /// Sheet de escopo com a anatomia da casa (ref.: property_share_sheet):
  /// grabber, eyebrow + título editorial, divisor gradient, tiles ricos
  /// com roundel/radio custom, busca por nome e rodapé Cancelar/Aplicar.
  void _openScopeSheet() {
    final ctrl = context.read<AppointmentController>();
    final role = ModuleAccessService.instance.userRole?.toLowerCase() ?? '';
    // Gate por PAPEL, não permissão — paridade com o web.
    final canViewAllCompany =
        role == 'master' || role == 'admin' || role == 'manager';

    var selectedIds = List<String>.of(ctrl.scopeUserIds);
    var allCompany = ctrl.scopeAllCompany;
    final memberSearchCtrl = TextEditingController();
    var memberQuery = '';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, refresh) {
            _ensureMembersLoaded((fn) {
              if (sheetContext.mounted) refresh(fn);
            });
            final mq = MediaQuery.of(sheetContext);
            final theme = Theme.of(sheetContext);
            final isDark = theme.brightness == Brightness.dark;
            final muted = ThemeHelpers.textSecondaryColor(sheetContext);
            final hairline = ThemeHelpers.borderColor(sheetContext)
                .withValues(alpha: 0.35);
            final isMine = !allCompany && selectedIds.isEmpty;

            final members = _members ?? const <({String id, String name})>[];
            final visibleMembers = memberQuery.isEmpty
                ? members
                : members
                    .where((m) => m.name.toLowerCase().contains(memberQuery))
                    .toList();

            return Padding(
              // Busca aberta com teclado: o sheet sobe junto.
              padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
              child: Container(
                constraints:
                    BoxConstraints(maxHeight: mq.size.height * 0.85),
                decoration: BoxDecoration(
                  color: ThemeHelpers.cardBackgroundColor(sheetContext),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(28)),
                  border: Border(
                    top: BorderSide(
                      color: ThemeHelpers.borderColor(sheetContext)
                          .withValues(alpha: 0.55),
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black
                          .withValues(alpha: isDark ? 0.45 : 0.10),
                      blurRadius: 22,
                      offset: const Offset(0, -8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(28)),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Grabber
                        Center(
                          child: Container(
                            width: 42,
                            height: 4,
                            margin: const EdgeInsets.only(top: 10, bottom: 6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              color: muted.withValues(alpha: 0.32),
                            ),
                          ),
                        ),
                        // ── Header editorial: eyebrow + título + fechar ──
                        Padding(
                          padding: const EdgeInsets.fromLTRB(22, 12, 14, 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'ESCOPO',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                        color: _scopeAccent,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.6,
                                        fontSize: 10,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'De quem é a agenda?',
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.4,
                                        color: ThemeHelpers.textColor(
                                            sheetContext),
                                        height: 1.15,
                                        fontSize: 19,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () =>
                                    Navigator.of(sheetContext).pop(),
                              ),
                            ],
                          ),
                        ),
                        // Divisor gradient sutil
                        Container(
                          height: 1,
                          margin:
                              const EdgeInsets.symmetric(horizontal: 22),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                ThemeHelpers.borderColor(sheetContext),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.5, 1.0],
                            ),
                          ),
                        ),
                        Flexible(
                          child: ListView(
                            shrinkWrap: true,
                            padding:
                                const EdgeInsets.fromLTRB(16, 10, 16, 10),
                            children: [
                              _scopeModeTile(
                                theme,
                                sheetContext,
                                icon: Icons.person_rounded,
                                label: 'Minha agenda',
                                subtitle: 'Somente os seus compromissos',
                                selected: isMine,
                                onTap: () => refresh(() {
                                  allCompany = false;
                                  selectedIds = [];
                                }),
                              ),
                              if (canViewAllCompany)
                                _scopeModeTile(
                                  theme,
                                  sheetContext,
                                  icon: Icons.apartment_rounded,
                                  label: 'Toda a empresa',
                                  subtitle:
                                      'Compromissos de todos os usuários',
                                  selected: allCompany,
                                  onTap: () => refresh(() {
                                    allCompany = true;
                                    selectedIds = [];
                                  }),
                                ),
                              const SizedBox(height: 14),
                              // ── Seção: pessoas específicas ──────────────
                              Row(
                                children: [
                                  Text(
                                    'PESSOAS ESPECÍFICAS',
                                    style:
                                        theme.textTheme.labelSmall?.copyWith(
                                      letterSpacing: 1.4,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 9.5,
                                      color: muted,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Container(
                                        height: 1, color: hairline),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              // Busca por nome — filled compacto.
                              TextField(
                                controller: memberSearchCtrl,
                                onChanged: (v) => refresh(() =>
                                    memberQuery = v.trim().toLowerCase()),
                                textAlignVertical: TextAlignVertical.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: ThemeHelpers.textColor(sheetContext),
                                ),
                                decoration: InputDecoration(
                                  isDense: true,
                                  filled: true,
                                  fillColor: isDark
                                      ? AppColors.background
                                          .backgroundTertiaryDarkMode
                                      : AppColors
                                          .background.backgroundTertiary,
                                  hintText: 'Buscar pessoa…',
                                  hintStyle: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: muted.withValues(alpha: 0.9),
                                  ),
                                  prefixIcon: Icon(
                                    Icons.search_rounded,
                                    size: 18,
                                    color: muted,
                                  ),
                                  prefixIconConstraints:
                                      const BoxConstraints(
                                    minWidth: 38,
                                    minHeight: 36,
                                  ),
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 9,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(11),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              if (_loadingMembers)
                                const Padding(
                                  padding:
                                      EdgeInsets.symmetric(vertical: 20),
                                  child: Center(
                                    child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2.4),
                                    ),
                                  ),
                                )
                              else if (members.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      6, 8, 6, 10),
                                  child: Text(
                                    'Nenhum membro encontrado.',
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: muted),
                                  ),
                                )
                              else if (visibleMembers.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      6, 8, 6, 10),
                                  child: Text(
                                    'Ninguém com esse nome.',
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: muted),
                                  ),
                                )
                              else
                                for (final m in visibleMembers)
                                  _scopeMemberTile(
                                    theme,
                                    sheetContext,
                                    name: m.name,
                                    selected: selectedIds.contains(m.id),
                                    onTap: () => refresh(() {
                                      allCompany = false;
                                      if (selectedIds.contains(m.id)) {
                                        selectedIds = selectedIds
                                            .where((x) => x != m.id)
                                            .toList();
                                      } else {
                                        selectedIds = [...selectedIds, m.id];
                                      }
                                    }),
                                  ),
                            ],
                          ),
                        ),
                        Container(height: 1, color: hairline),
                        // ── Rodapé: Cancelar neutro | Aplicar verde ──────
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  onPressed: () =>
                                      Navigator.of(sheetContext).pop(),
                                  style: TextButton.styleFrom(
                                      foregroundColor: muted),
                                  child: const FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text('Cancelar',
                                        maxLines: 1, softWrap: false),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () async {
                                    Navigator.of(sheetContext).pop();
                                    await ctrl.setScope(
                                      userIds: selectedIds,
                                      allCompany: allCompany,
                                    );
                                    await ctrl.loadAppointments(reset: true);
                                  },
                                  style: FilledButton.styleFrom(
                                    backgroundColor:
                                        const Color(0xFF059669),
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text('Aplicar',
                                        maxLines: 1, softWrap: false),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(memberSearchCtrl.dispose);
  }

  /// Tile rico de modo de escopo — roundel 40 tinted + label + subtítulo +
  /// radio custom (nada de ListTile default).
  Widget _scopeModeTile(
    ThemeData theme,
    BuildContext tileContext, {
    required IconData icon,
    required String label,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(tileContext);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: _scopeAccent.withValues(alpha: 0.16),
        highlightColor: _scopeAccent.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 9, 6, 9),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color:
                      _scopeAccent.withValues(alpha: isDark ? 0.18 : 0.12),
                  border: Border.all(
                    color:
                        _scopeAccent.withValues(alpha: isDark ? 0.34 : 0.22),
                  ),
                ),
                child: Icon(icon, size: 19, color: _scopeAccent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.15,
                        color: ThemeHelpers.textColor(tileContext),
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: muted,
                        fontSize: 11.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _scopeRadio(tileContext, selected),
            ],
          ),
        ),
      ),
    );
  }

  /// Linha de membro — avatar-inicial 34px em cor estável + nome +
  /// checkbox custom.
  Widget _scopeMemberTile(
    ThemeData theme,
    BuildContext tileContext, {
    required String name,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final avatarColor = _memberAvatarColor(name);
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: _scopeAccent.withValues(alpha: 0.14),
        highlightColor: _scopeAccent.withValues(alpha: 0.07),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 7, 6, 7),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: avatarColor.withValues(alpha: 0.16),
                  border: Border.all(
                    color: avatarColor.withValues(alpha: 0.38),
                  ),
                ),
                child: Text(
                  initial,
                  style: TextStyle(
                    color: avatarColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight:
                        selected ? FontWeight.w800 : FontWeight.w600,
                    letterSpacing: -0.1,
                    color: ThemeHelpers.textColor(tileContext),
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _scopeCheckbox(tileContext, selected),
            ],
          ),
        ),
      ),
    );
  }

  /// Radio custom 20px — círculo outline; ativo = preenchido azul + check.
  Widget _scopeRadio(BuildContext radioContext, bool selected) {
    final muted = ThemeHelpers.textSecondaryColor(radioContext);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? _scopeAccent : Colors.transparent,
        border: selected
            ? null
            : Border.all(color: muted.withValues(alpha: 0.55), width: 1.6),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
          : null,
    );
  }

  /// Checkbox custom 20px (quadrado radius 6) — pra seleção múltipla.
  Widget _scopeCheckbox(BuildContext boxContext, bool selected) {
    final muted = ThemeHelpers.textSecondaryColor(boxContext);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: selected ? _scopeAccent : Colors.transparent,
        border: selected
            ? null
            : Border.all(color: muted.withValues(alpha: 0.55), width: 1.6),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
          : null,
    );
  }

  // ---------------------------------------------------------------------------
  // VIEW MODE SECTION
  // ---------------------------------------------------------------------------
  Widget _buildViewModeSection(ThemeData theme) {
    // O chip "Hoje" vive na ContextBar — aqui é só o seletor de modo.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: ViewModeSelector(
        value: _viewMode,
        onChanged: (m) {
          setState(() {
            _viewMode = m;
            if (m == CalendarViewMode.month) {
              _tableFormat = CalendarFormat.month;
            } else if (m == CalendarViewMode.week) {
              _tableFormat = CalendarFormat.week;
            }
          });
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CALENDAR (MES / SEMANA)
  // ---------------------------------------------------------------------------
  /// Calendário FLUSH — gramática do Apple Calendar: grid direto na
  /// página (sem card, sem borda, sem sombra, sem gradiente), hoje é o
  /// número no accent, selecionado é um disco sólido, eventos são dots
  /// minúsculos na cor real do agendamento. Uma hairline fecha o bloco.
  Widget _buildCalendar(ThemeData theme) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final hairline =
        ThemeHelpers.borderColor(context).withValues(alpha: 0.35);

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      child: Column(
        children: [
          TableCalendar<Appointment>(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2032, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => _isSameDay(_selectedDay, day),
            calendarFormat: _tableFormat,
            startingDayOfWeek: StartingDayOfWeek.monday,
            locale: 'pt_BR',
            rowHeight: 52,
            daysOfWeekHeight: 30,
            availableCalendarFormats: const {
              CalendarFormat.month: 'Mês',
              CalendarFormat.week: 'Semana',
            },
            eventLoader: _eventsFor,
            headerStyle: HeaderStyle(
              // Título à esquerda, navegação discreta — nada de pills.
              titleCentered: false,
              formatButtonVisible: false,
              titleTextFormatter: (date, locale) {
                final f = DateFormat('MMMM yyyy', 'pt_BR').format(date);
                return AppointmentVisuals.capitalize(f);
              },
              titleTextStyle:
                  theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    fontSize: 17,
                  ) ??
                  const TextStyle(),
              leftChevronIcon: Icon(
                Icons.chevron_left_rounded,
                size: 26,
                color: secondary,
              ),
              rightChevronIcon: Icon(
                Icons.chevron_right_rounded,
                size: 26,
                color: secondary,
              ),
              leftChevronPadding: const EdgeInsets.all(6),
              rightChevronPadding: const EdgeInsets.all(6),
              headerPadding: const EdgeInsets.fromLTRB(8, 0, 0, 4),
            ),
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: TextStyle(
                color: secondary.withValues(alpha: 0.8),
                fontWeight: FontWeight.w700,
                fontSize: 11,
                letterSpacing: 0.4,
              ),
              weekendStyle: TextStyle(
                color: secondary.withValues(alpha: 0.5),
                fontWeight: FontWeight.w700,
                fontSize: 11,
                letterSpacing: 0.4,
              ),
              dowTextFormatter: (date, locale) {
                final raw = DateFormat.E(locale).format(date);
                return raw.length >= 3
                    ? raw.substring(0, 3).toUpperCase()
                    : raw.toUpperCase();
              },
            ),
            calendarStyle: const CalendarStyle(
              outsideDaysVisible: false,
              cellMargin: EdgeInsets.all(4),
            ),
            calendarBuilders: CalendarBuilders<Appointment>(
              defaultBuilder: (context, day, focused) =>
                  _dayCell(day, false, false, false),
              todayBuilder: (context, day, focused) =>
                  _dayCell(day, false, true, false),
              selectedBuilder: (context, day, focused) => _dayCell(
                day,
                true,
                _isSameDay(day, DateTime.now()),
                false,
              ),
              outsideBuilder: (context, day, focused) =>
                  _dayCell(day, false, false, true),
              markerBuilder: (context, day, events) {
                if (events.isEmpty) return null;
                // Dots minúsculos na cor real de cada agendamento — sem
                // glow. Ficam abaixo do disco, então não precisam trocar
                // de cor quando o dia está selecionado.
                return Positioned(
                  bottom: 4,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: events.take(3).map((e) {
                      final c = AppointmentVisuals.colorFromHex(e.color);
                      return Container(
                        margin:
                            const EdgeInsets.symmetric(horizontal: 1.5),
                        width: 4.5,
                        height: 4.5,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
            onDaySelected: (selected, focused) {
              setState(() {
                _selectedDay = selected;
                _focusedDay = focused;
              });
            },
            onPageChanged: (focused) {
              _focusedDay = focused;
              // Janela de fetch derivada: navegou pra fora dela → ela
              // cresce (nunca encolhe) e recarrega o range novo.
              final ctrl = context.read<AppointmentController>();
              if (ctrl.ensureWindowCovers(focused)) {
                ctrl.loadAppointments(reset: true);
              }
            },
            onFormatChanged: (format) {
              setState(() {
                _tableFormat = format;
                _viewMode = format == CalendarFormat.week
                    ? CalendarViewMode.week
                    : CalendarViewMode.month;
              });
            },
          ),
          const SizedBox(height: 6),
          Container(height: 1, color: hairline),
        ],
      ),
    );
  }

  /// Célula de dia — gramática Apple Calendar:
  /// - **Hoje**: número no accent da marca (o único vermelho do grid).
  /// - **Selecionado**: disco sólido — accent quando é hoje; tinta do tema
  ///   (preto no claro / branco no escuro) nos demais dias.
  /// - Sem ring, sem gradiente, sem sombra, sem fundo tinted.
  Widget _dayCell(DateTime day, bool selected, bool isToday, bool outside) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = AppColors.primary.primary;
    final isWeekend =
        day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;

    Color? disc;
    Color text;
    if (selected) {
      disc = isToday
          ? primary
          : (isDark ? Colors.white : const Color(0xFF111827));
      text = isToday
          ? Colors.white
          : (isDark ? const Color(0xFF111827) : Colors.white);
    } else if (outside) {
      text =
          ThemeHelpers.textSecondaryColor(context).withValues(alpha: 0.35);
    } else if (isToday) {
      text = primary;
    } else if (isWeekend) {
      text = ThemeHelpers.textSecondaryColor(context);
    } else {
      text = ThemeHelpers.textColor(context);
    }

    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: disc, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text(
          '${day.day}',
          style: TextStyle(
            color: text,
            fontWeight:
                selected || isToday ? FontWeight.w800 : FontWeight.w500,
            fontSize: 15.5,
            letterSpacing: -0.2,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SELECTED DAY HEADER
  // ---------------------------------------------------------------------------
  /// Rótulo caps do dia — mesma gramática do header da vista Agenda:
  /// "HOJE · TER, 5 DE AGO".
  String _dayCapsLabel(DateTime day) {
    final now = DateTime.now();
    final isToday = _isSameDay(day, now);
    final isTomorrow = _isSameDay(day, now.add(const Duration(days: 1)));
    final dateLabel = DateFormat("EEE, d 'de' MMM", 'pt_BR')
        .format(day)
        .toUpperCase()
        .replaceAll('.', '');
    final prefix = isToday
        ? 'HOJE · '
        : isTomorrow
            ? 'AMANHÃ · '
            : '';
    return '$prefix$dateLabel';
  }

  /// Header flush do dia selecionado — small caps sobre hairline (mesma
  /// gramática do `_agendaDayHeader`), contagem tabular e ação "Novo" no
  /// lugar da pill + botão tonal encaixotados.
  Widget _buildSelectedDayHeader(ThemeData theme) {
    final events = _eventsFor(_selectedDay);
    final isToday = _isSameDay(_selectedDay, DateTime.now());
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final accent = isToday ? AppColors.primary.primary : secondary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _dayCapsLabel(_selectedDay),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    fontSize: 11,
                  ),
                ),
              ),
              if (events.isNotEmpty) ...[
                Text(
                  '${events.length}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 14),
              ],
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _openCreate(date: _selectedDay),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add_rounded,
                        size: 15,
                        color: AppColors.primary.primary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'Novo',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.primary.primary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                          fontSize: 11,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 1,
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.35),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SELECTED DAY LIST (Timeline)
  // ---------------------------------------------------------------------------
  Widget _buildSelectedDayList(ThemeData theme) {
    final events = _eventsFor(_selectedDay);
    if (events.isEmpty) {
      return _buildDayEmptyState(theme);
    }
    final hairline = ThemeHelpers.borderColor(context).withValues(alpha: 0.35);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (int i = 0; i < events.length; i++) ...[
            _TimelineRow(
              appointment: events[i],
              onTap: () => _openDetails(events[i]),
            ),
            if (i != events.length - 1)
              Padding(
                // Recuo até a coluna do título (44 + 12 + 3 + 12).
                padding: const EdgeInsets.only(left: 71),
                child: Container(height: 1, color: hairline),
              ),
          ],
        ],
      ),
    );
  }

  /// Empty state do dia — neutro (slate) e flush: roundel + título +
  /// subtítulo + ação em texto. Sem card com borda, sem tom de marca.
  Widget _buildDayEmptyState(ThemeData theme) {
    const slate = Color(0xFF64748B);
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: slate.withValues(alpha: 0.10),
              border: Border.all(color: slate.withValues(alpha: 0.22)),
            ),
            child: const Icon(
              Icons.event_available_rounded,
              size: 24,
              color: slate,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Dia livre',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Nenhum agendamento em '
            '${DateFormat('dd/MM/yyyy').format(_selectedDay)}.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: muted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _openCreate(date: _selectedDay),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add_rounded,
                    size: 15,
                    color: AppColors.primary.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Criar agendamento',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.primary.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // AGENDA (LISTA POR DIA)
  // ---------------------------------------------------------------------------
  Widget _buildAgendaList(List<Appointment> filtered, ThemeData theme) {
    if (filtered.isEmpty) {
      // Empty state neutro (slate) e flush — sem card, sem tom de alerta.
      const slate = Color(0xFF64748B);
      final muted = ThemeHelpers.textSecondaryColor(context);
      final hasFilters = _filters.hasActiveFilters;
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 44, 20, 0),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: slate.withValues(alpha: 0.10),
                border: Border.all(color: slate.withValues(alpha: 0.22)),
              ),
              child: const Icon(
                Icons.event_busy_rounded,
                size: 24,
                color: slate,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Nenhum agendamento encontrado',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: ThemeHelpers.textColor(context),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              hasFilters
                  ? 'Tente ajustar ou remover os filtros aplicados.'
                  : 'Crie um novo agendamento para começar.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: muted,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: hasFilters
                  ? () {
                      setState(() => _filters = const CalendarFiltersState());
                      final ctrl = context.read<AppointmentController>();
                      ctrl.clearFilters();
                      ctrl.loadAppointments(reset: true);
                    }
                  : () => _openCreate(),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasFilters
                          ? Icons.refresh_rounded
                          : Icons.add_rounded,
                      size: 15,
                      color: hasFilters ? slate : AppColors.primary.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      hasFilters ? 'Limpar filtros' : 'Novo agendamento',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color:
                            hasFilters ? slate : AppColors.primary.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Agrupar por dia
    final groups = <DateTime, List<Appointment>>{};
    for (final a in filtered) {
      final k = DateTime(a.startDate.year, a.startDate.month, a.startDate.day);
      groups.putIfAbsent(k, () => []).add(a);
    }
    final sortedKeys = groups.keys.toList()..sort();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        children: [
          for (final day in sortedKeys) ...[
            _agendaDayHeader(theme, day, groups[day]!.length),
            const SizedBox(height: 8),
            for (int i = 0; i < groups[day]!.length; i++) ...[
              AppointmentCard(
                appointment: groups[day]![i],
                dense: true,
                onTap: () => _openDetails(groups[day]![i]),
              ),
              if (i != groups[day]!.length - 1) const SizedBox(height: 8),
            ],
            const SizedBox(height: 18),
          ],
        ],
      ),
    );
  }

  /// Header de dia da lista — flush, à la Apple Calendar: "HOJE · TER, 5 DE
  /// AGO" em small caps sobre hairline. Só HOJE fala no accent da marca.
  Widget _agendaDayHeader(ThemeData theme, DateTime day, int count) {
    final isToday = _isSameDay(day, DateTime.now());
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final isTomorrow = _isSameDay(day, tomorrow);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    final accent = isToday ? AppColors.primary.primary : secondary;
    final dateLabel = DateFormat("EEE, d 'de' MMM", 'pt_BR')
        .format(day)
        .toUpperCase()
        .replaceAll('.', '');
    final prefix = isToday
        ? 'HOJE · '
        : isTomorrow
            ? 'AMANHÃ · '
            : '';

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$prefix$dateLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    fontSize: 11,
                  ),
                ),
              ),
              Text(
                '$count',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: secondary,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 1,
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.35),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ERROR / SKELETON
  // ---------------------------------------------------------------------------
  Widget _buildErrorState(ThemeData theme, AppointmentController ctrl) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.status.error.withValues(alpha: 0.10),
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                size: 40,
                color: AppColors.status.error,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Não conseguimos carregar a agenda',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              ctrl.error ?? '',
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            CustomButton(
              text: 'Tentar novamente',
              icon: Icons.refresh_rounded,
              onPressed: () => ctrl.loadAppointments(reset: true),
            ),
          ],
        ),
      ),
    );
  }

  /// Skeleton fiel ao layout flush: linha do dia + contagens + chips de
  /// atalho, seletor de modo, grade do calendário, header hairline do dia
  /// e linhas da timeline (sem os cards encaixotados do modelo antigo).
  Widget _buildSkeleton(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SkeletonBox(height: 18, width: 210, borderRadius: 6),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: SkeletonBox(height: 11, width: 250, borderRadius: 6),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: SkeletonBox(height: 33, borderRadius: 11)),
              const SizedBox(width: 8),
              Expanded(child: SkeletonBox(height: 33, borderRadius: 11)),
            ],
          ),
          const SizedBox(height: 18),
          SkeletonBox(height: 44, borderRadius: 14),
          const SizedBox(height: 16),
          SkeletonBox(height: 300, borderRadius: 18),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: SkeletonBox(height: 11, width: 150, borderRadius: 6),
          ),
          const SizedBox(height: 14),
          for (int i = 0; i < 3; i++) ...[
            SkeletonBox(height: 52, borderRadius: 12),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  // ===========================================================================
  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}


/// Linha FLUSH da timeline do dia selecionado — hora início/fim em coluna
/// tabular à esquerda, barra vertical 3px na cor do agendamento, título +
/// "tipo · local" e chevron. Sem card, sem borda: o ritmo vem das
/// hairlines entre as linhas. Cancelado/não compareceu fala apagado.
class _TimelineRow extends StatelessWidget {
  final Appointment appointment;
  final VoidCallback onTap;

  const _TimelineRow({required this.appointment, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final accent = AppointmentVisuals.colorFromHex(appointment.color);
    final isDead = appointment.status == AppointmentStatus.cancelled ||
        appointment.status == AppointmentStatus.noShow;

    final subtitle = [
      appointment.type.label,
      if ((appointment.location ?? '').trim().isNotEmpty)
        appointment.location!.trim(),
    ].join(' · ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: accent.withValues(alpha: 0.10),
        highlightColor: accent.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 44,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppointmentVisuals.formattedTime(appointment.startDate),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: -0.2,
                        color:
                            isDead ? muted : ThemeHelpers.textColor(context),
                        fontFeatures: const [FontFeature.tabularFigures()],
                        height: 1.2,
                      ),
                    ),
                    Text(
                      AppointmentVisuals.formattedTime(appointment.endDate),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        color: muted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 3,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDead ? 0.35 : 1),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      appointment.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        fontSize: 14.5,
                        color:
                            isDead ? muted : ThemeHelpers.textColor(context),
                        decoration:
                            isDead ? TextDecoration.lineThrough : null,
                        decorationColor: muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        fontSize: 11.5,
                        color: muted,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: muted.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
