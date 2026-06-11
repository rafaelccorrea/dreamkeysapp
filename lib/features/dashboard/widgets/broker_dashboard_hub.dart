import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/shell_visual_tokens.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../features/appointments/services/appointment_service.dart';
import '../../../features/appointments/models/appointment_model.dart';
import '../../../shared/utils/broker_contact_actions.dart';
import '../../../shared/services/purchase_proposals_service.dart';
import 'broker_global_search_sheet.dart';

/// Hub do corretor no Início: busca global, propostas e visitas do dia.
class BrokerDashboardHub extends StatefulWidget {
  const BrokerDashboardHub({super.key});

  @override
  State<BrokerDashboardHub> createState() => _BrokerDashboardHubState();
}

class _BrokerDashboardHubState extends State<BrokerDashboardHub> {
  bool _loading = true;
  List<Appointment> _todayVisits = [];
  int _pendingSignatures = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final propRes = await PurchaseProposalsService.instance.list(
      filters: const ProposalFilters(page: 1, limit: 30),
    );
    if (propRes.success && propRes.data != null) {
      _pendingSignatures = propRes.data!.items
          .where((p) => p.status == ProposalStatus.processing)
          .length;
    }

    final dayEnd = today.add(const Duration(days: 1));
    final apptRes = await AppointmentService.instance.listAppointments(
      startDate: today.toIso8601String(),
      endDate: dayEnd.toIso8601String(),
      limit: 8,
      onlyMyData: true,
    );
    if (apptRes.success && apptRes.data != null) {
      _todayVisits = apptRes.data!.appointments
          .where((a) => a.type == AppointmentType.visit)
          .toList();
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  void _openGlobalSearch() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const BrokerGlobalSearchSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = Theme.of(context).brightness == Brightness.dark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: ShellVisualTokens.dashboardGlassFill(context),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _openGlobalSearch,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, color: accent, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Buscar imóvel, cliente ou lead…',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_pendingSignatures > 0) ...[
          const SizedBox(height: 12),
          _HubTile(
            title: '$_pendingSignatures proposta(s) em andamento',
            subtitle: 'Toque para ver fichas e assinaturas',
            icon: Icons.description_outlined,
            accent: const Color(0xFFD97706),
            onTap: () => Navigator.of(context).pushNamed(AppRoutes.proposals),
          ),
        ],
        if (_loading && _todayVisits.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (_todayVisits.isNotEmpty) ...[
          const SizedBox(height: 12),
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
          ..._todayVisits.take(4).map(
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
                        Navigator.of(context).pushNamed(
                          AppRoutes.calendarDetails(a.id),
                        );
                      }
                    },
                  ),
                ),
              ),
        ],
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
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
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
