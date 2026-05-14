import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../core/navigation/adaptive_page_route.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../controllers/appointment_controller.dart';
import '../models/appointment_model.dart';
import '../widgets/appointment_helpers.dart';
import 'edit_appointment_page.dart';

/// Tela premium de detalhes do agendamento — hero com gradiente, contagem
/// regressiva inteligente, ações rápidas de status e seções refinadas.
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
        backgroundColor:
            ok ? AppointmentVisuals.colorForStatus(s) : AppColors.status.error,
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
            Text(
              ok
                  ? 'Status atualizado: ${s.label}'
                  : (ctrl.error ?? 'Erro ao atualizar status'),
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
                  color: AppColors.status.error.withOpacity(0.10),
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
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.status.error,
                      ),
                      child: const Text('Excluir'),
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

          return Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                children: [
                  _buildHero(theme, a, accent),
                  const SizedBox(height: 18),
                  _buildStatusFlow(theme, a),
                  const SizedBox(height: 18),
                  _buildWhenCard(theme, a, accent),
                  if (a.location != null && a.location!.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _buildLocationCard(theme, a),
                  ],
                  if (a.description != null && a.description!.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _buildSectionCard(
                      theme,
                      icon: Icons.description_rounded,
                      title: 'Descrição',
                      child: Text(
                        a.description!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.55,
                        ),
                      ),
                    ),
                  ],
                  if (a.notes != null && a.notes!.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _buildSectionCard(
                      theme,
                      icon: Icons.sticky_note_2_rounded,
                      title: 'Observações privadas',
                      child: Text(
                        a.notes!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.55,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _buildMetadataRow(theme, a),
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
  // HERO HEADER
  // ---------------------------------------------------------------------------
  Widget _buildHero(ThemeData theme, Appointment a, Color accent) {
    final isDark = theme.brightness == Brightness.dark;
    final relative =
        AppointmentVisuals.relativeTimeLabel(a.startDate, a.endDate);
    final isHappening = DateTime.now().isAfter(a.startDate) &&
        DateTime.now().isBefore(a.endDate);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [accent.withOpacity(0.22), accent.withOpacity(0.06)]
              : [accent.withOpacity(0.16), accent.withOpacity(0.04)],
        ),
        border: Border.all(color: accent.withOpacity(0.30)),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(isDark ? 0.18 : 0.10),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.20),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withOpacity(0.30)),
                ),
                child: Icon(
                  AppointmentVisuals.iconFor(a.type),
                  color: accent,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          a.type.label.toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4,
                            fontSize: 10.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          a.visibility.label,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      a.title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _statusBadge(theme, a.status),
              const Spacer(),
              if (isHappening)
                _liveBadge(accent)
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: accent.withOpacity(0.32)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timelapse_rounded, size: 14, color: accent),
                      const SizedBox(width: 5),
                      Text(
                        relative,
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(ThemeData theme, AppointmentStatus s) {
    final color = AppointmentVisuals.colorForStatus(s);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.40)),
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

  Widget _liveBadge(Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withOpacity(0.55)),
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
  // STATUS FLOW (Quick actions)
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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ThemeHelpers.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_rounded,
                  color: AppColors.primary.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                'AÇÕES RÁPIDAS',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: suggested.map((s) {
              final color = AppointmentVisuals.colorForStatus(s);
              return InkWell(
                onTap: _updatingStatus ? null : () => _changeStatus(s),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withOpacity(0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        AppointmentVisuals.iconForStatus(s),
                        size: 16,
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
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // WHEN CARD
  // ---------------------------------------------------------------------------
  Widget _buildWhenCard(ThemeData theme, Appointment a, Color accent) {
    final dateFormat = DateFormat("EEEE, d 'de' MMMM 'de' y", 'pt_BR');
    final start = a.startDate;
    final end = a.endDate;
    final sameDay = start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ThemeHelpers.borderColor(context)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.event_rounded, color: accent, size: 18),
                ),
                const SizedBox(width: 12),
                Text(
                  'Data e horário',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Bloco de horário visual
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _timePillar(theme, accent, 'Início', start),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          height: 1.5,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                accent.withOpacity(0.0),
                                accent.withOpacity(0.55),
                                accent.withOpacity(0.0),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            AppointmentVisuals.durationLabel(start, end),
                            style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w800,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _timePillar(theme, accent, 'Término', end),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.05),
              border: Border(
                top: BorderSide(color: ThemeHelpers.borderColor(context)),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today_rounded,
                    size: 14, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    sameDay
                        ? AppointmentVisuals.capitalize(
                            dateFormat.format(start))
                        : '${AppointmentVisuals.formattedShortDate(start)}  →  ${AppointmentVisuals.formattedShortDate(end)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _timePillar(
    ThemeData theme,
    Color accent,
    String label,
    DateTime date,
  ) {
    return Column(
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 76,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: accent.withOpacity(0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withOpacity(0.25)),
          ),
          child: Column(
            children: [
              Text(
                AppointmentVisuals.formattedTime(date),
                style: theme.textTheme.titleLarge?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                DateFormat('dd/MM').format(date),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // LOCATION CARD
  // ---------------------------------------------------------------------------
  Widget _buildLocationCard(ThemeData theme, Appointment a) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ThemeHelpers.borderColor(context)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.status.info.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.location_on_rounded,
              color: AppColors.status.info,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LOCAL',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    fontSize: 10.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  a.location!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // GENERIC SECTION CARD
  // ---------------------------------------------------------------------------
  Widget _buildSectionCard(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ThemeHelpers.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    Icon(icon, color: AppColors.primary.primary, size: 18),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // METADATA ROW (criado em / atualizado em)
  // ---------------------------------------------------------------------------
  Widget _buildMetadataRow(ThemeData theme, Appointment a) {
    final f = DateFormat("d MMM y 'às' HH:mm", 'pt_BR');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context).withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withOpacity(0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _meta(
              theme,
              icon: Icons.add_circle_outline_rounded,
              label: 'Criado em',
              value: AppointmentVisuals.capitalize(f.format(a.createdAt)),
            ),
          ),
          Container(
            width: 1,
            height: 36,
            color: ThemeHelpers.borderColor(context),
          ),
          Expanded(
            child: _meta(
              theme,
              icon: Icons.update_rounded,
              label: 'Atualizado',
              value: AppointmentVisuals.capitalize(f.format(a.updatedAt)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _meta(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 13,
                  color: ThemeHelpers.textSecondaryColor(context)),
              const SizedBox(width: 4),
              Text(
                label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontWeight: FontWeight.w800,
                  fontSize: 10,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BOTTOM BAR (Edit + Delete)
  // ---------------------------------------------------------------------------
  Widget _buildBottomBar(ThemeData theme, Appointment a) {
    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor.withOpacity(0.96),
        border: Border(
          top: BorderSide(color: ThemeHelpers.borderColor(context)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
              label: Text(
                'Excluir',
                style: TextStyle(color: AppColors.status.error),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.status.error,
                side: BorderSide(
                  color: AppColors.status.error.withOpacity(0.55),
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
              label: const Text('Editar agendamento'),
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
                color: AppColors.status.error.withOpacity(0.10),
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                size: 40,
                color: AppColors.status.error,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Não foi possível carregar',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              ctrl.error ?? 'Agendamento não encontrado',
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            CustomButton(
              text: 'Voltar',
              icon: Icons.arrow_back_rounded,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeleton(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
      children: [
        SkeletonBox(height: 150, borderRadius: 22),
        const SizedBox(height: 18),
        SkeletonBox(height: 90, borderRadius: 18),
        const SizedBox(height: 14),
        SkeletonBox(height: 180, borderRadius: 18),
        const SizedBox(height: 14),
        SkeletonBox(height: 70, borderRadius: 18),
        const SizedBox(height: 14),
        SkeletonBox(height: 100, borderRadius: 18),
      ],
    );
  }
}
