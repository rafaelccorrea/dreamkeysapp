import 'package:flutter/material.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/appointment_model.dart';
import 'appointment_helpers.dart';

/// Card premium reutilizável que representa um agendamento na lista do dia
/// e na visão "Agenda Lista". Sintetiza tipo, horário, status e localização
/// num bloco compacto e elegante.
class AppointmentCard extends StatelessWidget {
  final Appointment appointment;
  final VoidCallback onTap;
  final bool dense;

  const AppointmentCard({
    super.key,
    required this.appointment,
    required this.onTap,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = AppointmentVisuals.colorFromHex(appointment.color);
    final statusColor = AppointmentVisuals.colorForStatus(appointment.status);
    final typeIcon = AppointmentVisuals.iconFor(appointment.type);
    final relative =
        AppointmentVisuals.relativeTimeLabel(appointment.startDate, appointment.endDate);
    final duration =
        AppointmentVisuals.durationLabel(appointment.startDate, appointment.endDate);

    final isHappening = DateTime.now().isAfter(appointment.startDate) &&
        DateTime.now().isBefore(appointment.endDate);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border.all(
          color: isHappening
              ? accent.withOpacity(0.55)
              : ThemeHelpers.borderColor(context).withOpacity(0.55),
          width: isHappening ? 1.6 : 1,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: accent.withOpacity(0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                  spreadRadius: -4,
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: EdgeInsets.all(dense ? 14 : 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Coluna do horário com gradiente vertical
                Container(
                  width: 64,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        accent.withOpacity(0.16),
                        accent.withOpacity(0.04),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: accent.withOpacity(0.22),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        AppointmentVisuals.formattedTime(appointment.startDate),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        width: 14,
                        height: 1.6,
                        color: accent.withOpacity(0.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppointmentVisuals.formattedTime(appointment.endDate),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: accent.withOpacity(0.85),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                // Conteúdo principal
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: accent.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(typeIcon, size: 14, color: accent),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            appointment.type.label,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: ThemeHelpers.textSecondaryColor(context),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              fontSize: 11,
                            ),
                          ),
                          const Spacer(),
                          if (isHappening)
                            _LiveBadge(color: accent)
                          else
                            _RelativeBadge(
                              label: relative,
                              color: statusColor,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        appointment.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _meta(
                            context,
                            Icons.timer_outlined,
                            duration,
                          ),
                          if (appointment.location != null &&
                              appointment.location!.isNotEmpty)
                            _meta(
                              context,
                              Icons.place_outlined,
                              appointment.location!,
                              maxWidth: 180,
                            ),
                          _statusPill(context, appointment.status),
                        ],
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
  }

  Widget _meta(
    BuildContext context,
    IconData icon,
    String text, {
    double? maxWidth,
  }) {
    final c = ThemeHelpers.textSecondaryColor(context);
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: c),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: c,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
          ),
        ),
      ],
    );
    if (maxWidth != null) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      );
    }
    return child;
  }

  Widget _statusPill(BuildContext context, AppointmentStatus status) {
    final color = AppointmentVisuals.colorForStatus(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            status.label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _RelativeBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _RelativeBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _LiveBadge extends StatefulWidget {
  final Color color;
  const _LiveBadge({required this.color});

  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: widget.color.withOpacity(0.16),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.color.withOpacity(0.4 + 0.4 * t),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withOpacity(0.6 - 0.4 * t),
                      blurRadius: 4 + 4 * t,
                      spreadRadius: 1 + 2 * t,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Text(
                'AO VIVO',
                style: TextStyle(
                  color: widget.color,
                  fontWeight: FontWeight.w800,
                  fontSize: 10,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Pill leve para indicar agendamentos pendentes/convites no header da agenda.
class AppointmentBannerPill extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;
  const AppointmentBannerPill({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withOpacity(0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  letterSpacing: 0.2,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, size: 14, color: color),
              ]
            ],
          ),
        ),
      ),
    );
  }
}
