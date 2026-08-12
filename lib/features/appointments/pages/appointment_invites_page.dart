import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/utils/json_datetime.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../controllers/appointment_controller.dart';
import '../models/appointment_model.dart';
import '../services/appointment_service.dart';
import '../widgets/appointment_helpers.dart';

// ─── Tons do convite (EXATOS do web — INVITE_TONES do InvitesListStyles) ─────
const Color _tAccent = Color(0xFF4A90E2); // azul convite
const Color _tOk = Color(0xFF3FA66B); // verde aceitar/confirmar
const Color _tMute = Color(0xFF64748B); // slate neutro
const Color _tWarn = Color(0xFFE6B84C); // âmbar aviso
const Color _tDanger = Color(0xFFDC2626); // vermelho recusar

// Rótulos curtos pt-BR SEM os pontos de abreviação do intl ("ter." / "ago.") —
// mesma tabela do `InvitesList.tsx`, para o mobile escrever a data idêntica ao
// web: "ter, 5 de ago". DateTime.weekday é 1=seg…7=dom, por isso o `% 7`.
const List<String> _weekdays = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'];
const List<String> _months = [
  'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
  'jul', 'ago', 'set', 'out', 'nov', 'dez',
];

String _two(int n) => n.toString().padLeft(2, '0');
String _clock(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// Tela de CONVITES da agenda — paridade com o `InvitesList.tsx` do web.
///
/// Duas abas (segmented): **Pendentes** (`/appointment-invites/pending`) e
/// **Todos** (`/appointment-invites/my-invites`). Aceitar/recusar responde
/// direto pelo `AppointmentInviteService` (a mensagem de erro da API chega ao
/// SnackBar — o controller engoliria).
///
/// IMPORTANTE PARA O CHAMADOR: ao voltar desta tela o usuário pode ter aceitado
/// convites (compromissos novos entraram na agenda dele). Recarregue SEMPRE no
/// `.then()` da navegação:
///
/// ```dart
/// Navigator.pushNamed(context, AppRoutes.calendarInvites).then((_) {
///   ctrl.loadAppointments(reset: true);
///   ctrl.loadPendingInvites();
/// });
/// ```
///
/// A tela já ressincroniza `AppointmentController.loadPendingInvites()` após
/// cada resposta, então badges ligados ao controller se atualizam sozinhos.
class AppointmentInvitesPage extends StatefulWidget {
  const AppointmentInvitesPage({super.key});

  @override
  State<AppointmentInvitesPage> createState() => _AppointmentInvitesPageState();
}

class _AppointmentInvitesPageState extends State<AppointmentInvitesPage> {
  /// 0 = Pendentes · 1 = Todos.
  int _tab = 0;

  /// `null` = aba ainda não carregada (cada aba carrega sob demanda).
  List<AppointmentInvite>? _pending;
  List<AppointmentInvite>? _all;

  bool _loading = false;
  String? _error;
  // Código HTTP guardado junto da mensagem: é ele que diferencia permissão,
  // sessão expirada e servidor fora do ar.
  int _errorStatus = 0;
  Object? _errorRaw;

  /// Convite sendo respondido agora (trava os botões de todos os itens para
  /// evitar resposta dupla em paralelo, igual ao `isLoading` do web).
  String? _respondingId;

  /// Pelo menos 1 resposta dada nesta visita. Serve de gatilho para recarregar
  /// a outra aba ao trocar (os dados mudaram no servidor) — e documenta que o
  /// CHAMADOR deve recarregar a agenda no `.then()` (ver doc da classe).
  bool _responded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _load();
      // Base do radar de conflito: convite × compromissos que JÁ estão na
      // minha agenda. Se o usuário chegou aqui sem passar pela agenda, o
      // controller ainda está vazio — carrega uma vez (fire-and-forget).
      final ctrl = AppointmentController.instance;
      if (ctrl.appointments.isEmpty) {
        ctrl.loadAppointments(reset: true);
      }
    });
  }

  // ─── Dados ─────────────────────────────────────────────────────────────────

  List<AppointmentInvite>? get _activeList => _tab == 0 ? _pending : _all;

  DateTime _startOf(AppointmentInvite invite) =>
      tryParseApiDateTime(invite.appointment?['startDate']) ?? invite.createdAt;

  Future<void> _load({bool refresh = false}) async {
    final tab = _tab;
    if (!refresh) {
      setState(() {
        _loading = true;
        _error = null;
        _errorStatus = 0;
        _errorRaw = null;
      });
    }

    final res = tab == 0
        ? await AppointmentInviteService.instance.getPendingInvites()
        : await AppointmentInviteService.instance.getMyInvites();

    if (!mounted || tab != _tab) return; // resposta atrasada de outra aba

    if (res.success && res.data != null) {
      final data = [...res.data!];
      if (tab == 0) {
        // Pendentes: o mais próximo primeiro (bate com o "mais próximo" do resumo).
        data.sort((a, b) => _startOf(a).compareTo(_startOf(b)));
      } else {
        // Todos: pendentes primeiro (mais próximo no topo); respondidos depois,
        // do mais recente para o mais antigo.
        data.sort((a, b) {
          final ap = a.status == InviteStatus.pending;
          final bp = b.status == InviteStatus.pending;
          if (ap != bp) return ap ? -1 : 1;
          if (ap) return _startOf(a).compareTo(_startOf(b));
          final ar = a.respondedAt ?? a.updatedAt;
          final br = b.respondedAt ?? b.updatedAt;
          return br.compareTo(ar);
        });
      }
      setState(() {
        _loading = false;
        _error = null;
        _errorStatus = 0;
        _errorRaw = null;
        if (tab == 0) {
          _pending = data;
        } else {
          _all = data;
        }
      });
    } else {
      final message = res.message ?? 'Erro ao carregar convites';
      setState(() {
        _loading = false;
        // Com lista já na tela (pull-to-refresh) o erro vira SnackBar; sem
        // lista vira estado de erro em tela cheia.
        if (_activeList == null) {
          _error = message;
          _errorStatus = res.statusCode;
          _errorRaw = res.error;
        }
      });
      if (refresh && _activeList != null) _snack(message, tone: _SnackTone.error);
    }
  }

  void _setTab(int tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    final target = tab == 0 ? _pending : _all;
    // Sob demanda na primeira visita à aba; após qualquer resposta os dados do
    // servidor mudaram, então a troca também recarrega.
    if (target == null || _responded) _load();
  }

  Future<void> _respond(_InviteRow row, InviteStatus status) async {
    if (_respondingId != null) return;
    setState(() => _respondingId = row.invite.id);

    final res = await AppointmentInviteService.instance.respondToInvite(
      inviteId: row.invite.id,
      status: status,
    );

    if (!mounted) return;

    if (res.success) {
      HapticFeedback.mediumImpact();
      _responded = true;
      setState(() {
        _respondingId = null;
        _pending?.removeWhere((i) => i.id == row.invite.id);
        final all = _all;
        if (all != null) {
          final idx = all.indexWhere((i) => i.id == row.invite.id);
          if (idx != -1) {
            all[idx] = _resolvedCopy(all[idx], res.data, status);
          }
        }
      });
      // Ressincroniza o controller (badge de pendentes da agenda etc.).
      AppointmentController.instance.loadPendingInvites();
      final accepted = status == InviteStatus.accepted;
      _snack(
        accepted
            ? 'Convite aceito — agendamento na sua agenda'
            : 'Convite recusado',
        tone: accepted ? _SnackTone.ok : _SnackTone.neutral,
      );
    } else {
      setState(() => _respondingId = null);
      _snack(
        res.message ?? 'Erro ao responder convite',
        tone: _SnackTone.error,
      );
    }
  }

  /// Cópia do convite com o status novo, PRESERVANDO as relações locais
  /// (`appointment`/`inviter`) — a resposta da API pode vir sem elas e a linha
  /// perderia título e horário.
  AppointmentInvite _resolvedCopy(
    AppointmentInvite src,
    AppointmentInvite? fresh,
    InviteStatus fallback,
  ) {
    return AppointmentInvite(
      id: src.id,
      appointmentId: src.appointmentId,
      inviterUserId: src.inviterUserId,
      invitedUserId: src.invitedUserId,
      companyId: src.companyId,
      status: fresh?.status ?? fallback,
      message: src.message,
      respondedAt: fresh?.respondedAt ?? DateTime.now(),
      createdAt: src.createdAt,
      updatedAt: fresh?.updatedAt ?? DateTime.now(),
      appointment: src.appointment,
      inviter: src.inviter,
      invitedUser: src.invitedUser,
    );
  }

  void _snack(String message, {required _SnackTone tone}) {
    if (!mounted) return;
    final background = switch (tone) {
      _SnackTone.ok => _tOk,
      _SnackTone.neutral => const Color(0xFF334155),
      _SnackTone.error => AppColors.status.error,
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: background,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(message),
      ),
    );
  }

  // ─── Derivação das linhas ──────────────────────────────────────────────────

  int _daysApart(DateTime target, DateTime from) {
    final a = DateTime(target.year, target.month, target.day);
    final b = DateTime(from.year, from.month, from.day);
    return a.difference(b).inDays;
  }

  List<_InviteRow> _buildRows(List<AppointmentInvite> invites) {
    final now = DateTime.now();
    // Agenda já ocupada (status != cancelled). Compromisso do PRÓPRIO convite
    // não conta como choque consigo mesmo.
    final busy = AppointmentController.instance.appointments
        .where((a) => a.status != AppointmentStatus.cancelled)
        .toList();

    return invites.map((invite) {
      Appointment? appt;
      final raw = invite.appointment;
      if (raw != null) {
        try {
          appt = Appointment.fromJson(raw);
        } catch (_) {
          appt = null;
        }
      }

      final start = appt?.startDate;
      final end = appt?.endDate;
      final isPending = invite.status == InviteStatus.pending;

      var isOver = false;
      var isNow = false;
      var dayGap = 0;
      String? countdown;
      Color countdownTone = _tMute;
      final clashes = <Appointment>[];

      if (start != null && end != null) {
        isOver = now.isAfter(end);
        isNow = !isOver && !now.isBefore(start);
        dayGap = _daysApart(start, now);

        // Countdown com tom por urgência.
        if (isOver) {
          countdown = 'Já terminou';
          countdownTone = _tMute;
        } else if (isNow) {
          countdown = 'Acontecendo agora';
          countdownTone = _tOk;
        } else if (dayGap == 0) {
          countdown = 'Ainda hoje';
          countdownTone = _tWarn;
        } else if (dayGap == 1) {
          countdown = 'Amanhã';
          countdownTone = _tAccent;
        } else {
          countdown = 'Em $dayGap dias';
          countdownTone = _tMute;
        }

        // Conflito só interessa em convite vivo — em convite respondido o
        // aviso viraria ruído sobre decisão já tomada (regra do web).
        if (isPending && !isOver) {
          for (final b in busy) {
            if (b.id == invite.appointmentId) continue;
            final overlaps =
                start.isBefore(b.endDate) && b.startDate.isBefore(end);
            if (overlaps) clashes.add(b);
          }
          clashes.sort((a, b) => a.startDate.compareTo(b.startDate));
        }
      }

      return _InviteRow(
        invite: invite,
        appointment: appt,
        start: start,
        end: end,
        isPending: isPending,
        isOver: isOver,
        dayGap: dayGap,
        countdown: countdown,
        countdownTone: countdownTone,
        clashes: clashes,
      );
    }).toList();
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Convites',
      showBottomNavigation: false,
      showDrawer: false,
      // ListenableBuilder FORA do RefreshIndicator: quando os appointments do
      // controller chegam, o radar de conflito acende sem mexer na invariante
      // RefreshIndicator → ListView direto (nada no meio).
      body: ListenableBuilder(
        listenable: AppointmentController.instance,
        builder: (context, _) {
          return RefreshIndicator(
            color: _tAccent,
            onRefresh: () => _load(refresh: true),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: _buildChildren(context),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildChildren(BuildContext context) {
    final children = <Widget>[
      _Segmented(tab: _tab, onChanged: _setTab),
      const SizedBox(height: 16),
    ];

    final list = _activeList;

    if (_loading && list == null) {
      children.addAll(_skeletons());
      return children;
    }

    if (_error != null && list == null) {
      children.add(_errorState(context));
      return children;
    }

    final invites = list ?? const <AppointmentInvite>[];
    if (invites.isEmpty) {
      children.add(_emptyState(context, pendingTab: _tab == 0));
      return children;
    }

    final rows = _buildRows(invites);
    if (_tab == 0) {
      children.add(_Summary(rows: rows));
    }

    final hairline = ThemeHelpers.borderColor(context).withValues(alpha: 0.6);
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) children.add(Container(height: 1, color: hairline));
      children.add(_inviteTile(context, rows[i]));
    }
    return children;
  }

  // ─── Item da lista (flush — hairline entre itens, sem card) ───────────────

  Widget _inviteTile(BuildContext context, _InviteRow row) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final invite = row.invite;
    final appt = row.appointment;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    final dimmed = invite.status == InviteStatus.declined ||
        invite.status == InviteStatus.cancelled;

    final title = (appt != null && appt.title.trim().isNotEmpty)
        ? appt.title
        : 'Compromisso sem título';
    final type = appt?.type ?? AppointmentType.other;
    final inviterName = invite.inviter?['name']?.toString();
    final message = invite.message?.trim();

    final blockedByEnd = row.isPending && row.isOver;
    final respondingHere = _respondingId == invite.id;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Roundel do tipo do compromisso.
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _tAccent.withValues(alpha: isDark ? 0.20 : 0.12),
                ),
                child: Icon(
                  AppointmentVisuals.iconFor(type),
                  size: 18,
                  color: _tAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                height: 1.25,
                                color: dimmed ? secondary : textColor,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: _StatusPill(status: invite.status),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    if (row.start != null && row.end != null)
                      Row(
                        children: [
                          const Icon(Icons.event_rounded,
                              size: 13, color: _tMute),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _whenLabel(row.start!, row.end!),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: secondary,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    if (inviterName != null && inviterName.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Convidado por $inviterName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: secondary),
                        ),
                      ),
                    if (message != null && message.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '“$message”',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: secondary,
                          ),
                        ),
                      ),
                    if (row.countdown != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          row.countdown!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: row.countdownTone,
                          ),
                        ),
                      ),
                    if (row.clashes.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 1.5),
                              child: Icon(Icons.warning_amber_rounded,
                                  size: 13, color: _tWarn),
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                _clashLabel(row.clashes),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _tWarn,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (!row.isPending && invite.respondedAt != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _respondedLabel(invite.respondedAt!),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _tMute,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (row.isPending) ...[
            const SizedBox(height: 12),
            if (respondingHere)
              const SizedBox(
                height: 44,
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _tAccent,
                    ),
                  ),
                ),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _respondingId != null
                          ? null
                          : () => _respond(row, InviteStatus.declined),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _tDanger,
                        side: BorderSide(
                          color: _tDanger.withValues(alpha: 0.55),
                          width: 1.2,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Recusar',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    // Aceitar/confirmar é SEMPRE verde (regra do app).
                    child: FilledButton(
                      onPressed: (blockedByEnd || _respondingId != null)
                          ? null
                          : () => _respond(row, InviteStatus.accepted),
                      style: FilledButton.styleFrom(
                        backgroundColor: _tOk,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            _tMute.withValues(alpha: isDark ? 0.22 : 0.14),
                        disabledForegroundColor:
                            _tMute.withValues(alpha: 0.9),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Aceitar',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (blockedByEnd)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Prazo encerrado — não dá mais para aceitar',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _tMute,
                    ),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }

  /// "ter, 5 de ago · 14:00–15:30" (mesmo dia) ou
  /// "05/08 14:00 → 06/08 15:30" (vira o dia) — formato do web.
  String _whenLabel(DateTime start, DateTime end) {
    final sameDay = start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;
    if (sameDay) {
      final weekday = _weekdays[start.weekday % 7];
      final month = _months[start.month - 1];
      return '$weekday, ${start.day} de $month · '
          '${_clock(start)}–${_clock(end)}';
    }
    return '${_two(start.day)}/${_two(start.month)} ${_clock(start)} → '
        '${_two(end.day)}/${_two(end.month)} ${_clock(end)}';
  }

  String _clashLabel(List<Appointment> clashes) {
    final first = clashes.first;
    final base = 'Conflita com ${first.title} '
        '(${_clock(first.startDate)}–${_clock(first.endDate)})';
    if (clashes.length == 1) return base;
    final rest = clashes.length - 1;
    return '$base · +$rest';
  }

  String _respondedLabel(DateTime d) =>
      'Respondido em ${_two(d.day)}/${_two(d.month)}/${d.year} às ${_clock(d)}';

  // ─── Estados auxiliares ────────────────────────────────────────────────────

  List<Widget> _skeletons() {
    return List.generate(4, (i) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonBox(width: 34, height: 34, borderRadius: 17),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonBox(height: 14, borderRadius: 7),
                  SizedBox(height: 8),
                  SkeletonBox(width: 170, height: 11, borderRadius: 6),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _errorState(BuildContext context) {
    return AppErrorState.fromApi(
      message: _error,
      statusCode: _errorStatus,
      error: _errorRaw,
      onRetry: _loading ? null : () => _load(),
      dense: true,
    );
  }

  Widget _emptyState(BuildContext context, {required bool pendingTab}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _tMute.withValues(alpha: isDark ? 0.16 : 0.10),
            ),
            child: Icon(
              pendingTab
                  ? Icons.mark_email_read_outlined
                  : Icons.all_inbox_rounded,
              size: 30,
              color: _tMute,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            pendingTab ? 'Caixa de convites limpa' : 'Nenhum convite por aqui',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: textColor,
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(
              pendingTab
                  ? 'Quando alguém te convidar para um compromisso, '
                      'ele aparece aqui.'
                  : 'Convites aceitos, recusados e cancelados ficam '
                      'registrados nesta lista.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, height: 1.45, color: secondary),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Linha derivada (tudo que o item precisa, calculado uma vez) ─────────────

class _InviteRow {
  final AppointmentInvite invite;
  final Appointment? appointment;
  final DateTime? start;
  final DateTime? end;
  final bool isPending;
  final bool isOver;
  final int dayGap;
  final String? countdown;
  final Color countdownTone;
  final List<Appointment> clashes;

  const _InviteRow({
    required this.invite,
    required this.appointment,
    required this.start,
    required this.end,
    required this.isPending,
    required this.isOver,
    required this.dayGap,
    required this.countdown,
    required this.countdownTone,
    required this.clashes,
  });
}

enum _SnackTone { ok, neutral, error }

// ─── Segmented "Pendentes / Todos" (estilo pill do app) ──────────────────────

class _Segmented extends StatelessWidget {
  final int tab;
  final ValueChanged<int> onChanged;

  const _Segmented({required this.tab, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final track = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);
    final border = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: track,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SegmentButton(
              icon: Icons.hourglass_top_rounded,
              label: 'Pendentes',
              selected: tab == 0,
              onTap: () => onChanged(0),
            ),
          ),
          Expanded(
            child: _SegmentButton(
              icon: Icons.all_inbox_rounded,
              label: 'Todos',
              selected: tab == 1,
              onTap: () => onChanged(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : ThemeHelpers.textColor(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: selected
                ? LinearGradient(
                    colors: [_tAccent, _tAccent.withValues(alpha: 0.82)],
                  )
                : null,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: _tAccent.withValues(alpha: 0.32),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                      spreadRadius: -3,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Resumo flush (só na aba Pendentes, quando há convites) ──────────────────

class _Summary extends StatelessWidget {
  final List<_InviteRow> rows;

  const _Summary({required this.rows});

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final textColor = ThemeHelpers.textColor(context);

    final live = rows.where((r) => r.isPending && !r.isOver).toList();
    final today = live.where((r) => r.dayGap == 0).length;
    final week = live.where((r) => r.dayGap > 0 && r.dayGap <= 7).length;
    final clashing = live.where((r) => r.clashes.isNotEmpty).length;

    _InviteRow? next;
    for (final r in live) {
      if (r.start == null) continue;
      if (next == null || r.start!.isBefore(next.start!)) next = r;
    }

    final hairline = ThemeHelpers.borderColor(context).withValues(alpha: 0.6);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            _metric(context, '${live.length} pendentes', _tAccent,
                active: live.isNotEmpty),
            _metric(context, '$today hoje', _tWarn, active: today > 0),
            _metric(context, '$week nos próximos 7 dias', _tAccent,
                active: week > 0),
            _metric(context, '$clashing com conflito', _tWarn,
                active: clashing > 0),
          ],
        ),
        if (next != null && next.countdown != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'O mais próximo é '),
                  TextSpan(
                    text: (next.appointment?.title.trim().isNotEmpty == true)
                        ? next.appointment!.title
                        : 'compromisso sem título',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                  TextSpan(text: ', ${next.countdown!.toLowerCase()}.'),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: secondary),
            ),
          ),
        const SizedBox(height: 12),
        Container(height: 1, color: hairline),
      ],
    );
  }

  /// Mini-métrica: dot colorido 7px + texto 12 w700. O dot carrega o tom;
  /// métrica zerada esmaece (dot slate + texto secundário).
  Widget _metric(
    BuildContext context,
    String label,
    Color tone, {
    required bool active,
  }) {
    final color = active ? tone : _tMute.withValues(alpha: 0.55);
    final textColor = active
        ? ThemeHelpers.textColor(context)
        : ThemeHelpers.textSecondaryColor(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
      ],
    );
  }
}

// ─── Pill de status (FORMA além de cor) ──────────────────────────────────────
//
// pending   → outline azul (borda 1.4, texto accent)
// accepted  → pill SÓLIDA verde, texto branco
// declined  → outline slate, texto slate
// cancelled → outline slate esmaecido (opacidade 0.7)

class _StatusPill extends StatelessWidget {
  final InviteStatus status;

  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    late final Color fg;
    Color? bg;
    Border? border;
    var opacity = 1.0;

    switch (status) {
      case InviteStatus.pending:
        fg = _tAccent;
        border = Border.all(color: _tAccent, width: 1.4);
        break;
      case InviteStatus.accepted:
        fg = Colors.white;
        bg = _tOk;
        break;
      case InviteStatus.declined:
        fg = _tMute;
        border = Border.all(color: _tMute, width: 1.4);
        break;
      case InviteStatus.cancelled:
        fg = _tMute;
        border = Border.all(color: _tMute, width: 1.4);
        opacity = 0.7;
        break;
    }

    return Opacity(
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          border: border,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          status.label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: fg,
          ),
        ),
      ),
    );
  }
}
