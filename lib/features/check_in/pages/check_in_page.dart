import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/services/check_in_service.dart';
import '../../../shared/services/live_activity_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';

/// Tela principal de check-in — versão "editorial", sem caixas centrais.
/// O conteúdo respira nas margens, usa toda a horizontal e troca o
/// vermelho/preto pesado por uma paleta calma de **emerald/teal** quando
/// presente e **slate/violet** quando não está.
class CheckInPage extends StatefulWidget {
  const CheckInPage({super.key});

  @override
  State<CheckInPage> createState() => _CheckInPageState();
}

class _CheckInPageState extends State<CheckInPage> {
  bool _bootLoading = true;
  bool _actionLoading = false;
  String _actionStep = 'location';
  String? _error;

  CheckIn? _active;
  CheckInSettings? _settings;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _bootLoading = true;
      _error = null;
    });
    final results = await Future.wait([
      CheckInService.instance.getActiveCheckIn(),
      CheckInService.instance.getSettings(),
    ]);
    if (!mounted) return;
    final activeRes = results[0] as ApiResponse<CheckIn?>;
    final settingsRes = results[1] as ApiResponse<CheckInSettings>;
    setState(() {
      _bootLoading = false;
      if (activeRes.success) {
        _active = activeRes.data;
      } else {
        _error = activeRes.message ?? 'Erro ao carregar check-in ativo';
      }
      if (settingsRes.success) {
        _settings = settingsRes.data;
      }
    });

    // Espelha o estado do check-in na Ilha Dinâmica (iOS 16.1+). No-op nas
    // demais plataformas.
    LiveActivityService.instance.syncCheckIn(_active);
  }

  Future<void> _refresh() async => _bootstrap();

  Future<void> _doCheckIn() async {
    if (_actionLoading) return;
    setState(() {
      _actionLoading = true;
      _actionStep = 'location';
    });
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _snack(
          'Ative a localização do dispositivo para fazer check-in.',
          error: true,
        );
        if (mounted) setState(() => _actionLoading = false);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        _snack(
          'Permissão de localização negada. Habilite nas configurações.',
          error: true,
        );
        if (mounted) setState(() => _actionLoading = false);
        return;
      }
      if (perm == LocationPermission.denied) {
        _snack('Sem permissão de localização.', error: true);
        if (mounted) setState(() => _actionLoading = false);
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      setState(() => _actionStep = 'registering');

      final res = await CheckInService.instance.doCheckIn(
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracy: pos.accuracy,
      );
      if (!mounted) return;
      setState(() => _actionLoading = false);
      if (!res.success) {
        _snack(res.message ?? 'Não foi possível fazer check-in.',
            error: true);
        return;
      }
      setState(() => _active = res.data);
      LiveActivityService.instance.syncCheckIn(res.data);
      final expires = res.data?.expiresAt;
      _snack(
        expires != null
            ? 'Check-in registrado · válido até ${DateFormat('HH:mm').format(expires.toLocal())}'
            : 'Check-in registrado',
      );
    } catch (e) {
      if (mounted) setState(() => _actionLoading = false);
      _snack('Erro ao obter localização: $e', error: true);
    }
  }

  Future<void> _doCheckOut() async {
    if (_actionLoading) return;
    setState(() {
      _actionLoading = true;
      _actionStep = 'checkout';
    });
    final res = await CheckInService.instance.doCheckOut();
    if (!mounted) return;
    setState(() => _actionLoading = false);
    if (!res.success) {
      _snack(res.message ?? 'Não foi possível fazer check-out.', error: true);
      return;
    }
    setState(() => _active = null);
    LiveActivityService.instance.endCheckIn();
    _snack('Check-out registrado');
  }

  void _snack(String message, {bool error = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = error
        ? (isDark ? AppColors.status.errorDarkMode : AppColors.status.error)
        : (isDark ? AppColors.status.greenDarkMode : AppColors.status.green);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        content: Row(
          children: [
            Icon(
              error ? LucideIcons.alertCircle : LucideIcons.checkCircle2,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Check-in',
      showBottomNavigation: false,
      actions: [
        IconButton(
          tooltip: 'Histórico',
          icon: const Icon(LucideIcons.history),
          onPressed: () =>
              Navigator.of(context).pushNamed(AppRoutes.checkInList),
        ),
      ],
      body: _bootLoading
          ? _buildSkeleton(context)
          : RefreshIndicator(
              onRefresh: _refresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 80),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) ...[
                      _ErrorLine(message: _error!),
                      const SizedBox(height: 14),
                    ],
                    _StatusBlock(active: _active != null),
                    const SizedBox(height: 20),
                    _PrimaryCta(
                      isActive: _active != null,
                      loading: _actionLoading,
                      step: _actionStep,
                      onCheckIn: _doCheckIn,
                      onCheckOut: _doCheckOut,
                    ),
                    if (_active != null) ...[
                      const SizedBox(height: 24),
                      _SectionLabel(
                        icon: LucideIcons.activity,
                        label: 'SESSÃO ATUAL',
                        accent: _emerald(context),
                      ),
                      const SizedBox(height: 10),
                      _ActiveStrip(checkIn: _active!),
                    ],
                    if (_settings != null) ...[
                      const SizedBox(height: 26),
                      _SectionLabel(
                        icon: LucideIcons.compass,
                        label: 'REGRAS DA EMPRESA',
                        accent: _accent(context),
                      ),
                      const SizedBox(height: 10),
                      _SettingsRow(settings: _settings!),
                    ],
                    const SizedBox(height: 26),
                    _HistoryLink(
                      onTap: () => Navigator.of(context).pushNamed(
                        AppRoutes.checkInList,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Color _accent(BuildContext context) => Theme.of(context).brightness ==
          Brightness.dark
      ? const Color(0xFF6366F1) // indigo-500
      : const Color(0xFF4F46E5); // indigo-600

  Color _emerald(BuildContext context) => Theme.of(context).brightness ==
          Brightness.dark
      ? const Color(0xFF34D399) // emerald-400
      : const Color(0xFF059669); // emerald-600

  Widget _buildSkeleton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkeletonBox(height: 24, width: 220, borderRadius: 8),
          const SizedBox(height: 10),
          SkeletonBox(height: 36, borderRadius: 8),
          const SizedBox(height: 8),
          SkeletonBox(height: 18, width: 280, borderRadius: 6),
          const SizedBox(height: 22),
          SkeletonBox(height: 56, borderRadius: 16),
          const SizedBox(height: 24),
          SkeletonBox(height: 14, width: 160, borderRadius: 6),
          const SizedBox(height: 10),
          SkeletonBox(height: 64, borderRadius: 14),
        ],
      ),
    );
  }
}

// ─── Status Block — eyebrow + title + subtitle (sem caixa) ────────────────────

class _StatusBlock extends StatelessWidget {
  final bool active;
  const _StatusBlock({required this.active});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final emerald = isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
    final slate = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final eyebrowColor = active ? emerald : slate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Dot pulsante quando ativo, neutro quando não.
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: eyebrowColor,
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: emerald.withValues(alpha: 0.55),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 9),
            Flexible(
              child: Text(
                active
                    ? 'VOCÊ ESTÁ NA IMOBILIÁRIA'
                    : 'FORA DA IMOBILIÁRIA',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: eyebrowColor,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.2,
                  fontSize: 11.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          active ? 'Presença registrada' : 'Pronto para começar?',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: ThemeHelpers.textColor(context),
            height: 1.1,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          active
              ? 'Você está marcado como presente até o horário de expiração abaixo.'
              : 'Aproxime-se da imobiliária e toque em fazer check-in para registrar sua presença.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

// ─── CTA Primário ────────────────────────────────────────────────────────────

class _PrimaryCta extends StatelessWidget {
  final bool isActive;
  final bool loading;
  final String step;
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;

  const _PrimaryCta({
    required this.isActive,
    required this.loading,
    required this.step,
    required this.onCheckIn,
    required this.onCheckOut,
  });

  String _label() {
    if (!loading) {
      return isActive ? 'Fazer check-out' : 'Fazer check-in';
    }
    switch (step) {
      case 'location':
        return 'Obtendo localização…';
      case 'registering':
        return 'Registrando…';
      case 'checkout':
        return 'Encerrando…';
      default:
        return 'Aguarde…';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final emeraldFrom =
        isDark ? const Color(0xFF34D399) : const Color(0xFF10B981);
    final emeraldTo =
        isDark ? const Color(0xFF059669) : const Color(0xFF047857);
    final indigoTo =
        isDark ? const Color(0xFF6366F1) : const Color(0xFF4F46E5);
    // Verde quando vai criar check-in; "neutro escuro" quando o ato é
    // encerrar (não quero verde lá pra não passar mensagem ambígua).
    final from = isActive ? const Color(0xFF1F2937) : emeraldFrom;
    final to = isActive ? const Color(0xFF0F172A) : emeraldTo;
    final glow = isActive ? indigoTo : emeraldTo;

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: loading ? null : (isActive ? onCheckOut : onCheckIn),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [from, to],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: glow.withValues(alpha: isDark ? 0.45 : 0.35),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                  spreadRadius: -6,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading) ...[
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  const SizedBox(width: 10),
                ] else ...[
                  Icon(
                    isActive ? LucideIcons.logOut : LucideIcons.mapPin,
                    size: 19,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 10),
                ],
                Flexible(
                  child: Text(
                    _label(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.25,
                      fontSize: 15.5,
                    ),
                  ),
                ),
                if (!loading) ...[
                  const SizedBox(width: 8),
                  Icon(
                    isActive
                        ? LucideIcons.arrowRight
                        : LucideIcons.arrowRight,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Section label (eyebrow horizontal) ──────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  const _SectionLabel({
    required this.icon,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Row(
      children: [
        Icon(icon, size: 13, color: accent),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: muted,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.0,
            fontSize: 10.5,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            color: muted.withValues(alpha: 0.22),
          ),
        ),
      ],
    );
  }
}

// ─── Active strip — chips inline horizontal ──────────────────────────────────

class _ActiveStrip extends StatelessWidget {
  final CheckIn checkIn;
  const _ActiveStrip({required this.checkIn});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final emerald =
        isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
    final amber =
        isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
    final slate =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final remaining = checkIn.expiresAt.difference(DateTime.now());
    final entryText = DateFormat('HH:mm').format(checkIn.checkedInAt.toLocal());
    final entryDate =
        DateFormat('dd/MM').format(checkIn.checkedInAt.toLocal());
    final expiresText =
        DateFormat('HH:mm').format(checkIn.expiresAt.toLocal());

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _InfoChip(
          icon: LucideIcons.logIn,
          label: 'Entrada',
          value: '$entryText · $entryDate',
          color: emerald,
          emphasize: true,
        ),
        _InfoChip(
          icon: LucideIcons.timer,
          label: 'Expira',
          value: '$expiresText · ${_formatRemaining(remaining)}',
          color: amber,
          emphasize: true,
        ),
        _InfoChip(
          icon: LucideIcons.mapPin,
          label: 'Local',
          value: _formatCoord(checkIn.latitude, checkIn.longitude),
          color: slate,
        ),
        if (checkIn.accuracy != null)
          _InfoChip(
            icon: LucideIcons.target,
            label: 'Precisão',
            value: '${checkIn.accuracy!.toStringAsFixed(0)} m',
            color: slate,
          ),
      ],
    );
  }

  static String _formatCoord(double lat, double lon) =>
      '${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}';

  static String _formatRemaining(Duration remaining) {
    if (remaining.isNegative) return 'expirado';
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes.toString().padLeft(2, '0')}min';
    }
    return '${remaining.inMinutes} min';
  }
}

// ─── Settings row — chips inline horizontal ──────────────────────────────────

class _SettingsRow extends StatelessWidget {
  final CheckInSettings settings;
  const _SettingsRow({required this.settings});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final indigo =
        isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1);
    final teal =
        isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0D9488);
    final slate =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final hasAddress = (settings.company?.address ?? '').trim().isNotEmpty;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _InfoChip(
          icon: LucideIcons.compass,
          label: 'Raio',
          value: '${settings.radiusMeters} m',
          color: indigo,
          emphasize: true,
        ),
        _InfoChip(
          icon: LucideIcons.hourglass,
          label: 'Duração',
          value: '${settings.durationHours.toStringAsFixed(0)} h',
          color: teal,
          emphasize: true,
        ),
        _InfoChip(
          icon: settings.enabled
              ? LucideIcons.checkCircle2
              : LucideIcons.power,
          label: 'Status',
          value: settings.enabled ? 'Habilitado' : 'Desabilitado',
          color: settings.enabled
              ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
              : (isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706)),
          emphasize: true,
        ),
        if (hasAddress)
          _InfoChip(
            icon: LucideIcons.building,
            label: 'Endereço',
            value: settings.company!.address!,
            color: slate,
          ),
      ],
    );
  }
}

// ─── InfoChip reusável (estado / KPI inline) ─────────────────────────────────

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool emphasize;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final bg = emphasize
        ? color.withValues(alpha: isDark ? 0.16 : 0.08)
        : Colors.transparent;
    final border = emphasize
        ? color.withValues(alpha: isDark ? 0.34 : 0.22)
        : (isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.06));
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 8, 13, 8),
      constraints: const BoxConstraints(maxWidth: 320),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                  fontSize: 9.5,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: ThemeHelpers.textColor(context),
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.1,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── History Link ────────────────────────────────────────────────────────────

class _HistoryLink extends StatelessWidget {
  final VoidCallback onTap;
  const _HistoryLink({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final emerald =
        isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
    final muted = ThemeHelpers.textSecondaryColor(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Row(
          children: [
            Icon(LucideIcons.history, size: 16, color: emerald),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Histórico de check-ins',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: ThemeHelpers.textColor(context),
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.1,
                    ),
                  ),
                  Text(
                    'Veja entradas, saídas e quem encerrou cada sessão.',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.arrowRight, size: 15, color: emerald),
          ],
        ),
      ),
    );
  }
}

// ─── Error inline ────────────────────────────────────────────────────────────

class _ErrorLine extends StatelessWidget {
  final String message;
  const _ErrorLine({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final danger = AppColors.status.error;
    return Row(
      children: [
        Icon(LucideIcons.alertCircle, size: 16, color: danger),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: danger,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}
