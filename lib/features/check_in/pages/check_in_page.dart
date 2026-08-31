import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/app_permissions.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/services/check_in_service.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/live_activity_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';

/// Tela principal de check-in — versão "editorial", sem caixas centrais.
/// O conteúdo respira nas margens, usa toda a horizontal e troca o
/// vermelho/preto pesado por uma paleta calma de **emerald/teal** quando
/// presente e **slate/violet** quando não está.
class CheckInPage extends StatefulWidget {
  /// `true` quando a tela é aberta pelo deep link "Sair" da Ilha Dinâmica
  /// (`dreamkeys://check-in/checkout`): após carregar o estado, mostra a
  /// confirmação de check-out em vez de esperar o toque no CTA.
  final bool startCheckout;

  const CheckInPage({super.key, this.startCheckout = false});

  @override
  State<CheckInPage> createState() => _CheckInPageState();
}

class _CheckInPageState extends State<CheckInPage> {
  bool _bootLoading = true;
  bool _actionLoading = false;
  String _actionStep = 'location';
  String? _error;

  /// Confirmação de saída do deep link já exibida (dispara UMA vez).
  bool _checkoutPromptShown = false;

  CheckIn? _active;
  CheckInSettings? _settings;

  /// Estado vindo de `GET /check-in/status`: janela de horário, bloqueio
  /// semanal e liberação do gestor. É o que decide se o botão abre ou trava —
  /// sem ele a tela só descobre o problema depois do 400.
  CheckInStatus? _status;

  Timer? _ticker;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      setState(() {});
      // A janela vira pelo relógio do SERVIDOR, não do aparelho: a cada minuto
      // reconsulta o status para o botão destravar/travar sozinho.
      _tick++;
      if (_tick % 4 == 0) unawaited(_refreshStatus());
      if (_active != null && _active!.isActive) {
        LiveActivityService.instance.syncCheckIn(
          _active,
          companyName: _settings?.company?.name,
        );
      }
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
      CheckInService.instance.getStatus(),
      CheckInService.instance.getSettings(),
    ]);
    if (!mounted) return;
    final statusRes = results[0] as ApiResponse<CheckInStatus>;
    final settingsRes = results[1] as ApiResponse<CheckInSettings>;

    // O status já devolve o check-in ativo. Se ele falhar, cai no /active para
    // a tela não ficar sem o essencial (só perde a leitura das janelas).
    CheckIn? active;
    bool loaded;
    if (statusRes.success && statusRes.data != null) {
      active = statusRes.data!.activeCheckIn;
      loaded = true;
    } else {
      final activeRes = await CheckInService.instance.getActiveCheckIn();
      if (!mounted) return;
      loaded = activeRes.success;
      active = activeRes.data;
    }

    setState(() {
      _bootLoading = false;
      _status = statusRes.success ? statusRes.data : null;
      _active = active;
      _error = loaded
          ? null
          : (statusRes.message ?? 'Erro ao carregar o estado do check-in');
      if (settingsRes.success) {
        _settings = settingsRes.data;
      }
    });

    // Espelha o estado do check-in na Ilha Dinâmica (iOS 16.1+). No-op nas
    // demais plataformas.
    LiveActivityService.instance.syncCheckIn(
      _active,
      companyName: _settings?.company?.name,
    );

    _maybePromptDeepLinkCheckout();
  }

  /// Fluxo do deep link "Sair" da Ilha: com o estado carregado, pede a
  /// confirmação de check-out (nunca encerra direto sem o usuário ver).
  Future<void> _maybePromptDeepLinkCheckout() async {
    if (!widget.startCheckout || _checkoutPromptShown || !mounted) return;
    _checkoutPromptShown = true;

    if (_active == null) {
      _snack('Nenhum check-in ativo para encerrar.');
      return;
    }

    final expiresText = DateFormat(
      'HH:mm',
    ).format(_active!.expiresAt.toLocal());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Encerrar check-in?',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Text(
          'Sua presença está registrada até $expiresText. '
          'Deseja fazer o check-out agora?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Agora não'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Fazer check-out'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _doCheckOut();
    }
  }

  Future<void> _refresh() async => _bootstrap();

  /// Recarrega só o status, sem piscar a tela. Usado no tique de 1 minuto e
  /// depois de cada ação — é assim que a liberação consumida e a virada de
  /// janela aparecem sem o usuário precisar puxar para atualizar.
  Future<void> _refreshStatus() async {
    final res = await CheckInService.instance.getStatus();
    if (!mounted || !res.success || res.data == null) return;
    setState(() {
      _status = res.data;
      _active = res.data!.activeCheckIn;
    });
  }

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
        _snack(res.message ?? 'Não foi possível fazer check-in.', error: true);
        return;
      }
      setState(() => _active = res.data);
      // A liberação do gestor é consumida no check-in e a janela pode ter
      // virado: relê o status para a tela contar a verdade nova.
      unawaited(_refreshStatus());
      await LiveActivityService.instance.syncCheckIn(
        res.data,
        companyName: _settings?.company?.name,
      );
      final hint = LiveActivityService.instance.unavailableHint;
      if (hint != null) {
        _snack(hint, error: false);
      }
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
    unawaited(_refreshStatus());
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
        if (_canManage)
          IconButton(
            tooltip: 'Gestão do check-in',
            icon: const Icon(LucideIcons.shieldCheck),
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.checkInManage),
          ),
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
                    _StatusBlock(active: _active != null, status: _status),
                    if (_notice != null) ...[
                      const SizedBox(height: 18),
                      _NoticeBlock(notice: _notice!),
                    ],
                    const SizedBox(height: 20),
                    _PrimaryCta(
                      isActive: _active != null,
                      loading: _actionLoading,
                      locked: _checkInLocked,
                      step: _actionStep,
                      onCheckIn: _doCheckIn,
                      onCheckOut: _doCheckOut,
                    ),
                    if (_status?.windowsRestricted == true) ...[
                      const SizedBox(height: 26),
                      _SectionLabel(
                        icon: LucideIcons.clock,
                        label: 'HORÁRIO DE CHECK-IN',
                        accent: _accent(context),
                      ),
                      const SizedBox(height: 10),
                      _WindowsStrip(status: _status!),
                    ],
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
                      onTap: () => Navigator.of(
                        context,
                      ).pushNamed(AppRoutes.checkInList),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  /// Pode agir sobre o check-in de outras pessoas — abre a tela de gestão.
  bool get _canManage {
    final access = ModuleAccessService.instance;
    final role = access.userRole?.toLowerCase().trim() ?? '';
    if (role == 'master' || role == 'admin' || role == 'manager') return true;
    return access.hasPermission(AppPermissions.checkInManageSettings);
  }

  /// O botão de check-in está travado — bloqueio semanal, fora da janela ou
  /// check-in desligado na empresa. Quem já está presente nunca fica travado
  /// (o botão vira check-out).
  bool get _checkInLocked => _active == null && _status?.lockedReason != null;

  /// UM aviso de topo, na ordem em que importa para quem está olhando.
  _CheckInNotice? get _notice {
    final s = _status;
    if (s == null) return null;
    final raio = _settings?.radiusMeters;
    final sufixoRaio = raio != null && raio > 0 ? ' (raio de $raio m)' : '';

    if (!s.enabled) {
      return const _CheckInNotice(
        tone: _NoticeTone.neutral,
        icon: LucideIcons.power,
        title: 'Check-in desativado',
        body:
            'A empresa não usa check-in por localização. '
            'Sua presença aqui não influencia a distribuição de leads.',
      );
    }
    if (s.reasonCannot == CheckInBlockedReason.blocked) {
      final dia = s.block?.weekdayLabel;
      return _CheckInNotice(
        tone: _NoticeTone.danger,
        icon: LucideIcons.lock,
        title: 'Bloqueado nesta semana',
        body: dia == null
            ? 'Você ficou sem check-in no dia obrigatório e está bloqueado '
                  'até domingo. Só o gestor pode liberar.'
            : 'Você não fez check-in na $dia e está bloqueado até domingo. '
                  'Só o gestor pode liberar.',
      );
    }
    if (s.reasonCannot == CheckInBlockedReason.outsideWindow) {
      final proximo = s.nextWindowText?.trim();
      return _CheckInNotice(
        tone: _NoticeTone.warning,
        icon: LucideIcons.clock,
        title: 'Fora do horário de check-in',
        body:
            'Agora são ${s.localTime} no horário da empresa.'
            '${proximo != null && proximo.isNotEmpty ? ' $proximo' : ''}',
      );
    }
    if (s.hasUsableException && _active == null) {
      final ate = s.exception!.validUntil!;
      return _CheckInNotice(
        tone: _NoticeTone.info,
        icon: LucideIcons.unlock,
        title: 'Liberação do gestor',
        body:
            'Vale até ${DateFormat('HH:mm').format(ate.toLocal())}. '
            'Você ainda precisa estar na imobiliária$sufixoRaio.',
      );
    }
    return null;
  }

  Color _accent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF6366F1) // indigo-500
      : const Color(0xFF4F46E5); // indigo-600

  Color _emerald(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
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
  final CheckInStatus? status;
  const _StatusBlock({required this.active, this.status});

  /// Rótulo do olho-mágico — muda com o motivo, não só com "presente/ausente".
  String get _eyebrow {
    if (active) return 'VOCÊ ESTÁ NA IMOBILIÁRIA';
    switch (status?.reasonCannot) {
      case CheckInBlockedReason.blocked:
        return 'BLOQUEADO NESTA SEMANA';
      case CheckInBlockedReason.outsideWindow:
        return 'FORA DO HORÁRIO';
      case CheckInBlockedReason.disabled:
        return 'CHECK-IN DESATIVADO';
      default:
        return 'FORA DA IMOBILIÁRIA';
    }
  }

  String get _title {
    if (active) return 'Presença registrada';
    switch (status?.reasonCannot) {
      case CheckInBlockedReason.blocked:
        return 'Check-in bloqueado';
      case CheckInBlockedReason.outsideWindow:
        return 'Ainda não é a hora';
      case CheckInBlockedReason.disabled:
        return 'Check-in desativado';
      default:
        return 'Pronto para começar?';
    }
  }

  String get _subtitle {
    if (active) {
      return 'Você está marcado como presente até o horário de expiração abaixo.';
    }
    switch (status?.reasonCannot) {
      case CheckInBlockedReason.blocked:
        return 'Enquanto o bloqueio valer você não consegue registrar presença — '
            'a liberação é feita pelo gestor.';
      case CheckInBlockedReason.outsideWindow:
        return 'O check-in só é aceito dentro das janelas de horário definidas '
            'pela empresa.';
      case CheckInBlockedReason.disabled:
        return 'A empresa não exige registro de presença por localização.';
      default:
        final atual = status?.currentWindow;
        if (atual != null) {
          return 'Você está dentro da janela das ${atual.label}. '
              'Aproxime-se da imobiliária e registre sua presença.';
        }
        return 'Aproxime-se da imobiliária e toque em fazer check-in para '
            'registrar sua presença.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final emerald = isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
    final slate = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final rose = isDark ? const Color(0xFFFB7185) : const Color(0xFFE11D48);
    final amber = isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
    // Cor por significado: presente é verde, bloqueio é vermelho, espera é
    // âmbar. Nada de vermelho decorativo — ele só aparece quando trava mesmo.
    final Color eyebrowColor;
    if (active) {
      eyebrowColor = emerald;
    } else {
      switch (status?.reasonCannot) {
        case CheckInBlockedReason.blocked:
          eyebrowColor = rose;
        case CheckInBlockedReason.outsideWindow:
          eyebrowColor = amber;
        default:
          eyebrowColor = slate;
      }
    }

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
                _eyebrow,
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
          _title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: ThemeHelpers.textColor(context),
            height: 1.1,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _subtitle,
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

  /// Regra do servidor impede o check-in agora (bloqueio, janela, desligado).
  final bool locked;
  final String step;
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;

  const _PrimaryCta({
    required this.isActive,
    required this.loading,
    required this.locked,
    required this.step,
    required this.onCheckIn,
    required this.onCheckOut,
  });

  String _label() {
    if (!loading) {
      if (isActive) return 'Fazer check-out';
      return locked ? 'Check-in indisponível' : 'Fazer check-in';
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
    final emeraldFrom = isDark
        ? const Color(0xFF34D399)
        : const Color(0xFF10B981);
    final emeraldTo = isDark
        ? const Color(0xFF059669)
        : const Color(0xFF047857);
    final indigoTo = isDark ? const Color(0xFF6366F1) : const Color(0xFF4F46E5);
    // Travado: some o gradiente vivo e o brilho. O botão continua legível,
    // mas para de convidar — quem explica o porquê é o aviso logo acima.
    final blocked = locked && !isActive;
    final Color from;
    final Color to;
    if (blocked) {
      from = isDark ? const Color(0xFF2A2A32) : const Color(0xFFE2E8F0);
      to = isDark ? const Color(0xFF1E1E25) : const Color(0xFFCBD5E1);
    } else if (isActive) {
      // Neutro escuro para encerrar: verde ali passaria mensagem ambígua.
      from = const Color(0xFF1F2937);
      to = const Color(0xFF0F172A);
    } else {
      from = emeraldFrom;
      to = emeraldTo;
    }
    final glow = isActive ? indigoTo : emeraldTo;
    final fg = blocked
        ? (isDark ? const Color(0xFF8A8A96) : const Color(0xFF64748B))
        : Colors.white;

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: loading || blocked
              ? null
              : (isActive ? onCheckOut : onCheckIn),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [from, to],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: blocked
                  ? null
                  : [
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
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation<Color>(fg),
                    ),
                  ),
                  const SizedBox(width: 10),
                ] else ...[
                  Icon(
                    blocked
                        ? LucideIcons.lock
                        : (isActive ? LucideIcons.logOut : LucideIcons.mapPin),
                    size: 19,
                    color: fg,
                  ),
                  const SizedBox(width: 10),
                ],
                Flexible(
                  child: Text(
                    _label(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.25,
                      fontSize: 15.5,
                    ),
                  ),
                ),
                if (!loading && !blocked) ...[
                  const SizedBox(width: 8),
                  Icon(
                    LucideIcons.arrowRight,
                    size: 16,
                    color: fg.withValues(alpha: 0.85),
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

// ─── Aviso de topo (bloqueio / janela / liberação) ───────────────────────────

enum _NoticeTone { danger, warning, info, neutral }

/// O que impede — ou libera — o check-in agora. Um por vez.
class _CheckInNotice {
  final _NoticeTone tone;
  final IconData icon;
  final String title;
  final String body;

  const _CheckInNotice({
    required this.tone,
    required this.icon,
    required this.title,
    required this.body,
  });
}

class _NoticeBlock extends StatelessWidget {
  final _CheckInNotice notice;
  const _NoticeBlock({required this.notice});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color accent;
    switch (notice.tone) {
      case _NoticeTone.danger:
        accent = isDark ? const Color(0xFFFB7185) : const Color(0xFFE11D48);
      case _NoticeTone.warning:
        accent = isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
      case _NoticeTone.info:
        accent = isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);
      case _NoticeTone.neutral:
        accent = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 14, 13),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.13 : 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.32 : 0.22),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.22 : 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: Icon(notice.icon, size: 15, color: accent),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  notice.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.1,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  notice.body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Janelas de horário do dia ───────────────────────────────────────────────

/// As janelas de hoje, com a vigente destacada e as já vencidas apagadas.
/// Quando o dia não tem janela nenhuma, diz isso em vez de mostrar vazio.
class _WindowsStrip extends StatelessWidget {
  final CheckInStatus status;
  const _WindowsStrip({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final emerald = isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
    final indigo = isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1);
    final slate = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final janelas = status.todayWindows;
    final proximo = status.nextWindowText?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (janelas.isEmpty)
          Text(
            '${status.weekdayLabel} não tem janela de check-in.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          )
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: janelas.map((w) {
              final atual = status.currentWindow;
              final isCurrent =
                  atual != null && atual.start == w.start && atual.end == w.end;
              // `localTime` é HH:mm no fuso da empresa — comparação de texto
              // basta e evita reconstruir a data do servidor no aparelho.
              final isPast =
                  !isCurrent && status.localTime.compareTo(w.end) > 0;
              return _InfoChip(
                icon: isCurrent
                    ? LucideIcons.radio
                    : (isPast ? LucideIcons.check : LucideIcons.clock),
                label: isCurrent
                    ? 'Agora'
                    : (isPast ? 'Encerrada' : 'Mais tarde'),
                value: w.label,
                color: isCurrent ? emerald : (isPast ? slate : indigo),
                emphasize: isCurrent,
              );
            }).toList(),
          ),
        if (proximo != null && proximo.isNotEmpty && !status.insideWindow) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.arrowRight, size: 13, color: muted),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  proximo,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
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
          child: Container(height: 1, color: muted.withValues(alpha: 0.22)),
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
    final emerald = isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
    final amber = isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
    final slate = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final remaining = checkIn.expiresAt.difference(DateTime.now());
    final entryText = DateFormat('HH:mm').format(checkIn.checkedInAt.toLocal());
    final entryDate = DateFormat('dd/MM').format(checkIn.checkedInAt.toLocal());
    final expiresText = DateFormat('HH:mm').format(checkIn.expiresAt.toLocal());

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
    final indigo = isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1);
    final teal = isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0D9488);
    final slate = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
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
          icon: settings.enabled ? LucideIcons.checkCircle2 : LucideIcons.power,
          label: 'Status',
          value: settings.enabled ? 'Habilitado' : 'Desabilitado',
          color: settings.enabled
              ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
              : (isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706)),
          emphasize: true,
        ),
        if (settings.hasWindows)
          _InfoChip(
            icon: LucideIcons.calendarClock,
            label: 'Horário',
            value: 'Só dentro das janelas',
            color: indigo,
          ),
        // Por que o check-in importa: é isto que muda na entrada de leads.
        if (settings.enabled && settings.leadPriorityEnabled)
          _InfoChip(
            icon: LucideIcons.userCheck,
            label: 'Leads',
            value: settings.leadPriorityMode == 'exclusive'
                ? 'Só para quem está presente'
                : 'Presentes primeiro',
            color: settings.leadPriorityMode == 'exclusive'
                ? (isDark ? const Color(0xFFFB7185) : const Color(0xFFE11D48))
                : teal,
            emphasize: true,
          ),
        if (settings.enabled && settings.autoDistributeOnWindowEnd)
          _InfoChip(
            icon: LucideIcons.share2,
            label: 'Fila',
            value: settings.maxAutoPerUserPerRun != null
                ? 'Distribui ao fim da janela · até '
                      '${settings.maxAutoPerUserPerRun} por rodada'
                : 'Distribui ao fim da janela',
            color: teal,
          ),
        if (settings.enabled && settings.weekendUsesSaturdayCheckIn)
          _InfoChip(
            icon: LucideIcons.calendarDays,
            label: 'Fim de semana',
            value: 'Sábado vale até domingo',
            color: slate,
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
    final emerald = isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
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
