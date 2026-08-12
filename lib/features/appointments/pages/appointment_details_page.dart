import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../core/navigation/adaptive_page_route.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/utils/error_cause.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../controllers/appointment_controller.dart';
import '../models/appointment_model.dart';
import '../models/appointment_tags.dart';
import '../widgets/appointment_helpers.dart';
import 'edit_appointment_page.dart';

// ─── Paleta por seção (coerência ≠ uniformidade) ─────────────────────────────
const Color _kWhenAccent = Color(0xFF3FA66B); // verde agenda (Meus horários)
const Color _kPlaceAccent = Color(0xFF0EA5E9); // sky — local
const Color _kBriefingAccent = Color(0xFF6366F1); // indigo — texto editorial
const Color _kNotesAccent = Color(0xFFD97706); // âmbar — nota privada
const Color _kGuestsAccent = Color(0xFF4A90E2); // azul — convidados
const Color _kTagsAccent = Color(0xFF64748B); // slate — etiquetas
const Color _kLinksAccent = Color(0xFF0891B2); // cyan — vínculos (dados)
const Color _kEditGreen = Color(0xFF059669); // confirmar/editar (canon)

/// Cor semântica canônica do status (spec do redesign da agenda):
/// agendado azul, confirmado verde, em andamento âmbar, concluído verde
/// selado, cancelado vermelho, não compareceu slate.
Color _statusTone(AppointmentStatus s) {
  switch (s) {
    case AppointmentStatus.scheduled:
      return const Color(0xFF3B82F6);
    case AppointmentStatus.confirmed:
      return const Color(0xFF10B981);
    case AppointmentStatus.inProgress:
      return const Color(0xFFF59E0B);
    case AppointmentStatus.completed:
      return const Color(0xFF059669);
    case AppointmentStatus.cancelled:
      return const Color(0xFFEF4444);
    case AppointmentStatus.noShow:
      return const Color(0xFF64748B);
  }
}

/// Rótulo humano da visibilidade (paridade com o create/edit).
String _visibilityLabel(AppointmentVisibility v) {
  switch (v) {
    case AppointmentVisibility.private:
      return 'Particular';
    case AppointmentVisibility.public:
      return 'Pública';
    case AppointmentVisibility.team:
      return 'Equipe';
  }
}

/// Ícone Lucide da visibilidade: pública=globe, particular=lock, equipe=users.
IconData _visibilityIcon(AppointmentVisibility v) {
  switch (v) {
    case AppointmentVisibility.public:
      return LucideIcons.globe;
    case AppointmentVisibility.private:
      return LucideIcons.lock;
    case AppointmentVisibility.team:
      return LucideIcons.users;
  }
}

/// Cor estável derivada do nome — cada pessoa tem a sua (mesma mecânica do
/// dossiê do kanban). Sem nome → slate.
Color _personColor(String? name) {
  if (name == null || name.trim().isEmpty) return const Color(0xFF64748B);
  const palette = [
    Color(0xFF0EA5E9),
    Color(0xFF14B8A6),
    Color(0xFF6366F1),
    Color(0xFFF97316),
    Color(0xFF22C55E),
    Color(0xFFEC4899),
    Color(0xFFA855F7),
    Color(0xFF0891B2),
  ];
  var h = 0;
  for (final c in name.trim().toLowerCase().codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return palette[h % palette.length];
}

/// Linha da lista de pessoas: convite (com status) ou participante direto.
class _GuestEntry {
  final String name;
  final String? subtitle;

  /// null = participante sem convite (sem fluxo aceitar/recusar).
  final InviteStatus? invite;

  const _GuestEntry({required this.name, this.subtitle, this.invite});
}

/// Tela de detalhes do agendamento — dossiê flush: header de seção com
/// barrinha + overline + título, hairlines, cor por significado. Paridade de
/// exibição com o web: convidados, etiquetas, visibilidade e vínculos.
class AppointmentDetailsPage extends StatefulWidget {
  final String appointmentId;

  const AppointmentDetailsPage({super.key, required this.appointmentId});

  @override
  State<AppointmentDetailsPage> createState() =>
      _AppointmentDetailsPageState();
}

class _AppointmentDetailsPageState extends State<AppointmentDetailsPage> {
  bool _updatingStatus = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context
          .read<AppointmentController>()
          .loadAppointmentById(widget.appointmentId);
    });
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------
  Future<void> _changeStatus(AppointmentStatus s) async {
    setState(() => _updatingStatus = true);
    HapticFeedback.lightImpact();
    final ctrl = context.read<AppointmentController>();
    final ok = await ctrl.updateAppointment(
      widget.appointmentId,
      UpdateAppointmentData(status: s),
    );
    if (!mounted) return;
    setState(() => _updatingStatus = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: ok ? _statusTone(s) : AppColors.status.error,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            Icon(
              ok
                  ? AppointmentVisuals.iconForStatus(s)
                  : Icons.error_outline_rounded,
              color: Colors.white,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                ok
                    ? 'Status atualizado: ${s.label}'
                    : (ctrl.error ?? 'Erro ao atualizar status'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Appointment a) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.status.error.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.status.error,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Excluir agendamento?',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                '“${a.title}” será removido permanentemente.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        // Cancelar nunca em vermelho: neutro forçado.
                        foregroundColor:
                            ThemeHelpers.textSecondaryColor(context),
                      ),
                      onPressed: () => Navigator.pop(context, false),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Cancelar'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.status.error,
                        foregroundColor: Colors.white,
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Excluir'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    final ctrl = context.read<AppointmentController>();
    final ok = await ctrl.deleteAppointment(widget.appointmentId);
    if (!context.mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.status.success,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: const Text('Agendamento excluído'),
        ),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.status.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Text(ctrl.error ?? 'Erro ao excluir'),
        ),
      );
    }
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Detalhes',
      showDrawer: false,
      showBottomNavigation: false,
      body: Consumer<AppointmentController>(
        builder: (context, ctrl, _) {
          if (ctrl.loading && ctrl.selectedAppointment == null) {
            return _buildSkeleton(theme);
          }
          final a = ctrl.selectedAppointment;
          if (a == null) return _buildErrorState(theme, ctrl);

          final accent = AppointmentVisuals.colorFromHex(a.color);
          final guests = _guestEntries(a);
          final hasLocation =
              a.location != null && a.location!.trim().isNotEmpty;
          final hasDescription =
              a.description != null && a.description!.trim().isNotEmpty;
          final hasNotes = a.notes != null && a.notes!.trim().isNotEmpty;
          final hasLinks = a.property != null || a.client != null;

          // Seções presentes (as vazias somem — nada de blocos "sem dados").
          final sections = <Widget>[
            _buildStatusFlow(theme, a),
            _buildWhenSection(theme, a),
            if (hasLocation)
              _editorialBlock(
                accent: _kPlaceAccent,
                overline: 'LOCAL',
                overlineIcon: Icons.location_on_rounded,
                child: Text(
                  a.location!.trim(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.45,
                  ),
                ),
              ),
            if (hasDescription)
              _editorialBlock(
                accent: _kBriefingAccent,
                overline: 'DESCRIÇÃO',
                child: Text(
                  a.description!.trim(),
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
                ),
              ),
            if (hasNotes)
              _editorialBlock(
                accent: _kNotesAccent,
                overline: 'OBSERVAÇÕES PRIVADAS',
                overlineIcon: Icons.lock_outline_rounded,
                child: Text(
                  a.notes!.trim(),
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
                ),
              ),
            if (guests.isNotEmpty) _buildGuestsSection(theme, guests),
            if (a.tags.isNotEmpty) _buildTagsSection(theme, a),
            if (hasLinks) _buildLinksSection(theme, a),
            _buildRegistry(theme, a),
          ];

          return Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
                children: [
                  _buildHero(theme, a, accent),
                  const SizedBox(height: 22),
                  for (int i = 0; i < sections.length; i++) ...[
                    if (i > 0) ...[
                      const SizedBox(height: 20),
                      _hairline(),
                      const SizedBox(height: 20),
                    ],
                    sections[i],
                  ],
                ],
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: _buildBottomBar(theme, a),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // GRAMÁTICA FLUSH
  // ---------------------------------------------------------------------------
  Widget _hairline() {
    return Container(
      height: 1,
      color: ThemeHelpers.borderColor(context).withValues(alpha: 0.6),
    );
  }

  Widget _sectionHeader({
    required Color accent,
    required String overline,
    required String title,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Container(
          width: 3.5,
          height: 24,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                overline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: accent,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing,
        ],
      ],
    );
  }

  /// Bloco editorial: régua accent à esquerda + overline + conteúdo
  /// (linguagem do briefing do kanban — variedade dentro da gramática).
  Widget _editorialBlock({
    required Color accent,
    required String overline,
    IconData? overlineIcon,
    required Widget child,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 3,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (overlineIcon != null) ...[
                      Icon(overlineIcon, size: 12, color: accent),
                      const SizedBox(width: 5),
                    ],
                    Expanded(
                      child: Text(
                        overline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.6,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HERO FLUSH — barra de acento + eyebrow + título + pills (nunca banner)
  // ---------------------------------------------------------------------------
  Widget _buildHero(ThemeData theme, Appointment a, Color accent) {
    final now = DateTime.now();
    final isHappening =
        now.isAfter(a.startDate) && now.isBefore(a.endDate);
    final relative =
        AppointmentVisuals.relativeTimeLabel(a.startDate, a.endDate);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 3.5,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          AppointmentVisuals.iconFor(a.type),
                          size: 14,
                          color: accent,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            a.type.label.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _visibilityLabel(a.visibility).toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color:
                                  ThemeHelpers.textSecondaryColor(context),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.0,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      a.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        height: 1.12,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _statusPill(a.status),
            if (isHappening) _liveBadge(accent) else _relativePill(relative),
          ],
        ),
      ],
    );
  }

  Widget _statusPill(AppointmentStatus s) {
    final color = _statusTone(s);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppointmentVisuals.iconForStatus(s), size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            s.label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _relativePill(String relative) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: ThemeHelpers.borderColor(context),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timelapse_rounded, size: 13, color: secondary),
          const SizedBox(width: 5),
          Text(
            relative,
            style: TextStyle(
              color: secondary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveBadge(Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: accent, blurRadius: 8, spreadRadius: 1),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'AO VIVO AGORA',
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w900,
              fontSize: 11,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // STATUS FLOW — ações sugeridas em chips semânticos (mesma lógica)
  // ---------------------------------------------------------------------------
  Widget _buildStatusFlow(ThemeData theme, Appointment a) {
    // Ações sugeridas baseadas no status atual
    final suggested = <AppointmentStatus>[];
    switch (a.status) {
      case AppointmentStatus.scheduled:
        suggested.addAll([
          AppointmentStatus.confirmed,
          AppointmentStatus.cancelled,
        ]);
        break;
      case AppointmentStatus.confirmed:
        suggested.addAll([
          AppointmentStatus.inProgress,
          AppointmentStatus.cancelled,
        ]);
        break;
      case AppointmentStatus.inProgress:
        suggested.addAll([
          AppointmentStatus.completed,
          AppointmentStatus.noShow,
        ]);
        break;
      case AppointmentStatus.completed:
      case AppointmentStatus.cancelled:
      case AppointmentStatus.noShow:
        suggested.add(AppointmentStatus.scheduled);
        break;
    }

    if (suggested.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          accent: _statusTone(a.status),
          overline: 'STATUS',
          title: 'Fluxo do compromisso',
          trailing: _updatingStatus
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.8),
                )
              : null,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: suggested.map((s) {
            final color = _statusTone(s);
            return InkWell(
              onTap: _updatingStatus ? null : () => _changeStatus(s),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      AppointmentVisuals.iconForStatus(s),
                      size: 15,
                      color: color,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Marcar como ${s.label.toLowerCase()}',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // QUANDO — tipografia de horas flush (sem caixas)
  // ---------------------------------------------------------------------------
  bool _isAllDay(DateTime s, DateTime e) {
    return s.hour == 0 &&
        s.minute == 0 &&
        e.day == s.day &&
        e.hour == 23 &&
        e.minute >= 58;
  }

  Widget _buildWhenSection(ThemeData theme, Appointment a) {
    final start = a.startDate;
    final end = a.endDate;
    final sameDay = start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;
    final allDay = _isAllDay(start, end);
    final title = sameDay
        ? AppointmentVisuals.capitalize(
            DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(start))
        : '${AppointmentVisuals.formattedShortDate(start)} → ${AppointmentVisuals.formattedShortDate(end)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          accent: _kWhenAccent,
          overline: 'QUANDO',
          title: title,
        ),
        const SizedBox(height: 14),
        if (allDay)
          Row(
            children: [
              const Icon(Icons.wb_sunny_rounded,
                  size: 20, color: _kWhenAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Dia inteiro',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
              ),
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _timeColumn(theme, 'INÍCIO', start, showDay: !sameDay),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        height: 1.5,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _kWhenAccent.withValues(alpha: 0.0),
                              _kWhenAccent.withValues(alpha: 0.55),
                              _kWhenAccent.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: _kWhenAccent.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Text(
                          AppointmentVisuals.durationLabel(start, end),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _kWhenAccent,
                            fontWeight: FontWeight.w800,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _timeColumn(theme, 'TÉRMINO', end, showDay: !sameDay),
            ],
          ),
      ],
    );
  }

  /// Hora em tipografia forte com sublinhado accent (voz do "Meus horários").
  Widget _timeColumn(
    ThemeData theme,
    String label,
    DateTime date, {
    required bool showDay,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          AppointmentVisuals.formattedTime(date),
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: ThemeHelpers.textColor(context),
          ),
        ),
        const SizedBox(height: 3),
        Container(
          height: 2,
          width: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            color: _kWhenAccent.withValues(alpha: 0.5),
          ),
        ),
        if (showDay) ...[
          const SizedBox(height: 4),
          Text(
            DateFormat('dd/MM').format(date),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // CONVIDADOS — paridade web: invites (status do convite) e participantes
  // ---------------------------------------------------------------------------
  /// Monta a lista defensivamente: convites primeiro (com status), depois
  /// participantes que não têm convite (sem duplicar pessoa).
  List<_GuestEntry> _guestEntries(Appointment a) {
    final entries = <_GuestEntry>[];
    final seen = <String>{};

    final invites = a.invites;
    if (invites != null) {
      for (final inv in invites) {
        final id = inv.invitedUserId.isNotEmpty ? inv.invitedUserId : inv.id;
        if (id.isNotEmpty && !seen.add(id)) continue;
        final name = inv.invitedUser?['name']?.toString().trim() ?? '';
        final email = inv.invitedUser?['email']?.toString().trim() ?? '';
        entries.add(_GuestEntry(
          name: name.isEmpty ? 'Convidado' : name,
          subtitle: email.isEmpty ? null : email,
          invite: inv.status,
        ));
      }
    }

    final participants = a.participants;
    if (participants != null) {
      for (final p in participants) {
        if (p.id.isNotEmpty && seen.contains(p.id)) continue;
        if (p.id.isNotEmpty) seen.add(p.id);
        final email = p.email.trim();
        final role = p.role.trim();
        entries.add(_GuestEntry(
          name: p.name.trim().isEmpty ? 'Participante' : p.name.trim(),
          subtitle: email.isNotEmpty ? email : (role.isNotEmpty ? role : null),
          invite: null,
        ));
      }
    }
    return entries;
  }

  Widget _buildGuestsSection(ThemeData theme, List<_GuestEntry> guests) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          accent: _kGuestsAccent,
          overline: 'CONVIDADOS',
          title: 'Quem participa',
          trailing: Text(
            '${guests.length}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
        ),
        const SizedBox(height: 6),
        for (int i = 0; i < guests.length; i++) ...[
          if (i > 0)
            Container(
              height: 1,
              color:
                  ThemeHelpers.borderColor(context).withValues(alpha: 0.35),
            ),
          _guestRow(theme, guests[i]),
        ],
      ],
    );
  }

  Widget _guestRow(ThemeData theme, _GuestEntry g) {
    final tone = _personColor(g.name);
    final initial =
        g.name.trim().isEmpty ? '?' : g.name.trim()[0].toUpperCase();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tone.withValues(alpha: 0.16),
              border: Border.all(color: tone.withValues(alpha: 0.35)),
            ),
            child: Text(
              initial,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: tone,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  g.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                if (g.subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    g.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _invitePill(g.invite),
        ],
      ),
    );
  }

  /// Pill de status do convite — FORMA além de cor: pendente outline azul,
  /// aceito sólida verde, recusado outline slate, cancelado slate apagado.
  /// Participante direto (sem convite) leva pill neutra.
  Widget _invitePill(InviteStatus? status) {
    const slate = Color(0xFF64748B);
    if (status == null) {
      return _pill(
        icon: Icons.person_rounded,
        label: 'Participante',
        ink: slate,
        border: slate.withValues(alpha: 0.35),
      );
    }
    switch (status) {
      case InviteStatus.pending:
        return _pill(
          icon: Icons.schedule_rounded,
          label: 'Pendente',
          ink: _kGuestsAccent,
          border: _kGuestsAccent.withValues(alpha: 0.55),
        );
      case InviteStatus.accepted:
        return _pill(
          icon: Icons.check_rounded,
          label: 'Aceito',
          ink: Colors.white,
          fill: const Color(0xFF10B981),
        );
      case InviteStatus.declined:
        return _pill(
          icon: Icons.close_rounded,
          label: 'Recusado',
          ink: slate,
          border: slate.withValues(alpha: 0.55),
        );
      case InviteStatus.cancelled:
        return _pill(
          icon: Icons.do_not_disturb_on_outlined,
          label: 'Cancelado',
          ink: slate.withValues(alpha: 0.7),
          fill: slate.withValues(alpha: 0.08),
        );
    }
  }

  Widget _pill({
    required IconData icon,
    required String label,
    required Color ink,
    Color? fill,
    Color? border,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: fill ?? Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: border != null ? Border.all(color: border) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: ink),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ETIQUETAS — chips do catálogo (valor desconhecido aparece cru em slate)
  // ---------------------------------------------------------------------------
  Widget _buildTagsSection(ThemeData theme, Appointment a) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          accent: _kTagsAccent,
          overline: 'ETIQUETAS',
          title: 'Preparação da visita',
          trailing: Text(
            '${a.tags.length}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: a.tags.map((value) {
            final tag = appointmentTagByValue(value);
            final tone = tag?.tone ?? _kTagsAccent;
            final label = tag?.label ?? value;
            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: tone.withValues(alpha: 0.45)),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: tone,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // VÍNCULOS — imóvel/cliente populados (só exibição, sem navegação nova)
  // ---------------------------------------------------------------------------
  String? _mapName(Map<String, dynamic>? m, List<String> keys) {
    if (m == null) return null;
    for (final k in keys) {
      final v = m[k]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  Widget _buildLinksSection(ThemeData theme, Appointment a) {
    final rows = <Widget>[];
    final propertyName =
        _mapName(a.property, const ['title', 'name', 'code']);
    final clientName = _mapName(a.client, const ['name', 'fullName']);
    if (a.property != null) {
      rows.add(_linkRow(
        icon: LucideIcons.building2,
        overline: 'IMÓVEL',
        name: propertyName ?? 'Imóvel vinculado',
      ));
    }
    if (a.client != null) {
      if (rows.isNotEmpty) {
        rows.add(Container(
          height: 1,
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.35),
        ));
      }
      rows.add(_linkRow(
        icon: LucideIcons.user,
        overline: 'CLIENTE',
        name: clientName ?? 'Cliente vinculado',
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          accent: _kLinksAccent,
          overline: 'VÍNCULOS',
          title: 'Imóvel e cliente',
        ),
        const SizedBox(height: 6),
        ...rows,
      ],
    );
  }

  Widget _linkRow({
    required IconData icon,
    required String overline,
    required String name,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              color: _kLinksAccent.withValues(alpha: 0.12),
              border: Border.all(
                color: _kLinksAccent.withValues(alpha: 0.28),
              ),
            ),
            child: Icon(icon, size: 17, color: _kLinksAccent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  overline,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: ThemeHelpers.textSecondaryColor(context)
                .withValues(alpha: 0.6),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // REGISTRO — visibilidade + criado/atualizado em grade com hairlines
  // (eyebrow + linha, na voz do dossiê do kanban)
  // ---------------------------------------------------------------------------
  Widget _buildRegistry(ThemeData theme, Appointment a) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final hairline =
        ThemeHelpers.borderColor(context).withValues(alpha: 0.35);
    final f = DateFormat("d MMM y '·' HH:mm", 'pt_BR');

    final entries = <(IconData, String, String)>[
      (
        _visibilityIcon(a.visibility),
        'VISIBILIDADE',
        _visibilityLabel(a.visibility),
      ),
      (
        LucideIcons.calendarPlus,
        'CRIADO EM',
        AppointmentVisuals.capitalize(f.format(a.createdAt)),
      ),
      (
        LucideIcons.history,
        'ATUALIZADO',
        AppointmentVisuals.capitalize(f.format(a.updatedAt)),
      ),
    ];

    // Pares por linha; sobra ímpar vira linha cheia.
    final rows = <List<(IconData, String, String)>>[];
    for (var i = 0; i < entries.length; i += 2) {
      rows.add(entries.sublist(
          i, i + 2 > entries.length ? entries.length : i + 2));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'REGISTRO',
              style: TextStyle(
                letterSpacing: 2.6,
                fontWeight: FontWeight.w900,
                color: secondary,
                fontSize: 10,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Container(height: 1, color: hairline)),
          ],
        ),
        const SizedBox(height: 4),
        for (final row in rows) ...[
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _registryCell(row[0], padRight: row.length == 2),
                ),
                if (row.length == 2) ...[
                  Container(width: 1, color: hairline),
                  Expanded(
                    child: _registryCell(row[1], padLeft: true),
                  ),
                ],
              ],
            ),
          ),
          if (row != rows.last) Container(height: 1, color: hairline),
        ],
      ],
    );
  }

  Widget _registryCell(
    (IconData, String, String) entry, {
    bool padRight = false,
    bool padLeft = false,
  }) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: EdgeInsets.only(
        top: 10,
        bottom: 10,
        right: padRight ? 12 : 0,
        left: padLeft ? 12 : 0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(entry.$1, size: 12, color: secondary),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  entry.$2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    color: secondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            entry.$3,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: ThemeHelpers.textColor(context),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BOTTOM BAR — Excluir outline vermelho / Editar verde
  // ---------------------------------------------------------------------------
  Widget _buildBottomBar(ThemeData theme, Appointment a) {
    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor.withValues(alpha: 0.96),
        border: Border(
          top: BorderSide(color: ThemeHelpers.borderColor(context)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: AppColors.status.error,
              ),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Excluir',
                  style: TextStyle(color: AppColors.status.error),
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.status.error,
                side: BorderSide(
                  color: AppColors.status.error.withValues(alpha: 0.55),
                ),
              ),
              onPressed: () => _confirmDelete(context, a),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('Editar agendamento'),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kEditGreen,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  adaptivePageRoute<void>(
                    builder: (_) =>
                        EditAppointmentPage(appointmentId: a.id),
                  ),
                ).then((_) {
                  if (!mounted) return;
                  context
                      .read<AppointmentController>()
                      .loadAppointmentById(widget.appointmentId);
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ERROR / SKELETON
  // ---------------------------------------------------------------------------
  Widget _buildErrorState(ThemeData theme, AppointmentController ctrl) {
    // Sem falha registrada e ainda assim sem agendamento: o registro sumiu
    // (excluído por outra pessoa), não é queda de rede.
    final cause = ctrl.errorCause ?? ErrorCause.fromApi(statusCode: 404);
    return AppErrorState(
      cause: cause,
      onRetry: () => ctrl.loadAppointmentById(widget.appointmentId),
      secondaryLabel: 'Voltar',
      onSecondary: () => Navigator.pop(context),
    );
  }

  /// Skeleton fiel ao layout flush: barra+título, pills, seções com header.
  Widget _buildSkeleton(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
      children: [
        SkeletonBox(width: 220, height: 12, borderRadius: 4),
        const SizedBox(height: 10),
        SkeletonBox(height: 26, borderRadius: 6),
        const SizedBox(height: 14),
        Row(
          children: [
            SkeletonBox(width: 110, height: 28, borderRadius: 999),
            const SizedBox(width: 8),
            SkeletonBox(width: 90, height: 28, borderRadius: 999),
          ],
        ),
        const SizedBox(height: 30),
        for (int i = 0; i < 3; i++) ...[
          SkeletonBox(width: 170, height: 14, borderRadius: 4),
          const SizedBox(height: 12),
          SkeletonBox(height: 72, borderRadius: 12),
          const SizedBox(height: 26),
        ],
      ],
    );
  }
}
