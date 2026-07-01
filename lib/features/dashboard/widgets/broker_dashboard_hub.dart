import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../features/appointments/services/appointment_service.dart';
import '../../../features/appointments/models/appointment_model.dart';
import '../../../shared/utils/broker_contact_actions.dart';

/// Hub do corretor no Início: visitas do dia.
class BrokerDashboardHub extends StatefulWidget {
  const BrokerDashboardHub({super.key});

  @override
  State<BrokerDashboardHub> createState() => _BrokerDashboardHubState();
}

class _BrokerDashboardHubState extends State<BrokerDashboardHub> {
  List<Appointment> _todayVisits = [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dayEnd = today.add(const Duration(days: 1));
    final apptRes = await AppointmentService.instance.listAppointments(
      startDate: today.toIso8601String(),
      endDate: dayEnd.toIso8601String(),
      limit: 8,
      onlyMyData: true,
    );
    if (!mounted) return;
    if (apptRes.success && apptRes.data != null) {
      setState(() {
        _todayVisits = apptRes.data!.appointments
            .where((a) => a.type == AppointmentType.visit)
            .toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Só "Visitas de hoje" — sem busca nem propostas, e sem spinner que destoa
    // do skeleton (aparece quando as visitas chegam; nada enquanto carrega).
    if (_todayVisits.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'Visitas de hoje',
          icon: Icons.event_available_rounded,
          trailing: TextButton(
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.calendar),
            child: const Text('Agenda'),
          ),
        ),
        const SizedBox(height: 8),
        ..._todayVisits
            .take(4)
            .map(
              (a) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _HubTile(
                  title: a.title,
                  subtitle: a.location ?? a.startDate.toString(),
                  icon: Icons.place_outlined,
                  accent: const Color(0xFF0891B2),
                  onTap: () {
                    if (a.location != null && a.location!.trim().isNotEmpty) {
                      BrokerContactActions.openMaps(context, a.location!);
                    } else {
                      Navigator.of(
                        context,
                      ).pushNamed(AppRoutes.calendarDetails(a.id));
                    }
                  },
                ),
              ),
            ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget? trailing;

  const _SectionHeader({
    required this.title,
    required this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: ThemeHelpers.textSecondaryColor(context)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _HubTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  const _HubTile({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ThemeHelpers.cardBackgroundColor(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null && subtitle!.trim().isNotEmpty)
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
