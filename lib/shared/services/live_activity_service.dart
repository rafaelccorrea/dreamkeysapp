import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:live_activities/live_activities.dart';
import 'package:live_activities/models/url_scheme_data.dart';

import '../../core/navigation/app_navigator.dart';
import '../../core/routes/app_routes.dart';
import 'check_in_service.dart';

/// Gerencia a Live Activity / Ilha Dinâmica do **check-in** no iOS 16.1+.
///
/// Tudo aqui é **defensivo**: em Android, iOS antigo, sem App Group
/// configurado ou se o plugin falhar, os métodos viram no-op silencioso e
/// NUNCA lançam exceção para o chamador.
class LiveActivityService with WidgetsBindingObserver {
  LiveActivityService._();
  static final LiveActivityService instance = LiveActivityService._();

  static const String _appGroupId = 'group.com.dreamkeys.corretor';
  static const String _activityId = 'checkin';
  static const String _urlScheme = 'dreamkeys';

  static const MethodChannel _islandCache = MethodChannel(
    'com.dreamkeys.corretor/live_activity',
  );

  final LiveActivities _plugin = LiveActivities();

  bool _initialized = false;
  bool _available = false;
  bool _bootstrapped = false;
  StreamSubscription<UrlSchemeData>? _urlSub;

  /// iOS 16.1+, Live Activities ligadas nas configurações e App Group ok.
  bool get isAvailable => _available;

  /// Registra listener de deep link e resume (chamar uma vez no [main]).
  Future<void> bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;

    if (!Platform.isIOS) return;

    WidgetsBinding.instance.addObserver(this);
    await _ensureInit();
    if (!_available) return;

    _urlSub ??= _plugin.urlSchemeStream().listen(_onUrlScheme);
    await _syncFromApi();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncFromApi());
    }
  }

  void _onUrlScheme(UrlSchemeData data) {
    if (data.scheme != _urlScheme) return;

    final path = (data.path ?? '').toLowerCase();
    final url = (data.url ?? '').toLowerCase();
    final host = (data.host ?? '').toLowerCase();
    final isCheckout = path.contains('checkout') ||
        url.contains('checkout') ||
        host == 'checkout';

    if (isCheckout) {
      unawaited(_performCheckoutFromIsland());
      return;
    }

    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    final current = ModalRoute.of(nav.context)?.settings.name;
    if (current == AppRoutes.checkIn) return;
    nav.pushNamed(AppRoutes.checkIn);
  }

  /// Encerra check-in ao tocar em "Sair" na Ilha expandida.
  Future<void> _performCheckoutFromIsland() async {
    try {
      final res = await CheckInService.instance.doCheckOut();
      await endCheckIn();
      if (kDebugMode) {
        debugPrint(
          '[LiveActivity] checkout via ilha: success=${res.success}',
        );
      }
      final nav = appNavigatorKey.currentState;
      if (nav != null) {
        nav.pushNamed(AppRoutes.checkIn);
      }
    } catch (e) {
      debugPrint('[LiveActivity] checkout via ilha falhou: $e');
    }
  }

  Future<void> _ensureInit() async {
    if (_initialized) return;
    _initialized = true;

    if (!Platform.isIOS) {
      _available = false;
      return;
    }
    try {
      await _plugin.init(
        appGroupId: _appGroupId,
        urlScheme: _urlScheme,
      );
      final supported = await _plugin.areActivitiesSupported();
      final enabled = await _plugin.areActivitiesEnabled();
      _available = supported && enabled;
      if (kDebugMode) {
        debugPrint(
          '[LiveActivity] supported=$supported enabled=$enabled '
          'available=$_available',
        );
      }
    } catch (e) {
      _available = false;
      debugPrint('[LiveActivity] init indisponível: $e');
    }
  }

  /// Mensagem curta quando a ilha não pode ser usada (só iOS).
  String? get unavailableHint {
    if (!Platform.isIOS || _available) return null;
    return 'Ative Live Activities em Ajustes → Intellisys para ver o check-in na Ilha Dinâmica.';
  }

  Future<void> _syncFromApi() async {
    await _ensureInit();
    if (!_available) return;
    try {
      final results = await Future.wait([
        CheckInService.instance.getActiveCheckIn(),
        CheckInService.instance.getSettings(),
      ]);
      final activeRes = results[0] as ApiResponse<CheckIn?>;
      final settingsRes = results[1] as ApiResponse<CheckInSettings>;
      final companyName = settingsRes.data?.company?.name;
      if (activeRes.success) {
        await syncCheckIn(
          activeRes.data,
          companyName: companyName,
        );
      }
    } catch (e) {
      debugPrint('[LiveActivity] syncFromApi: $e');
    }
  }

  /// Reflete o estado atual do check-in na Ilha Dinâmica.
  Future<void> syncCheckIn(
    CheckIn? active, {
    String? companyName,
  }) async {
    await _ensureInit();
    if (!_available) return;

    try {
      if (active != null && active.isActive) {
        final now = DateTime.now();
        final remaining = active.expiresAt.difference(now);
        final String statusPhase;
        if (remaining.inSeconds <= 0) {
          statusPhase = 'expired';
        } else if (remaining.inMinutes < 5) {
          statusPhase = 'critical';
        } else if (remaining.inMinutes < 15) {
          statusPhase = 'expiring';
        } else {
          statusPhase = 'active';
        }

        final name = (active.user?.name ?? '').trim();
        final company = (companyName ?? '').trim();
        final data = <String, dynamic>{
          'status': 'active',
          'statusPhase': statusPhase,
          'userName': name.isEmpty ? 'Corretor' : name,
          if (company.isNotEmpty) 'companyName': company,
          'checkedInAtEpoch':
              '${active.checkedInAt.millisecondsSinceEpoch}',
          'expiresAtEpoch': '${active.expiresAt.millisecondsSinceEpoch}',
        };

        final staleIn = remaining.inMinutes >= 1 ? remaining : null;

        await _plugin.createOrUpdateActivity(
          _activityId,
          data,
          staleIn: staleIn,
        );
        await _cacheIslandPayload(data);
        if (kDebugMode) {
          debugPrint(
            '[LiveActivity] sync até ${active.expiresAt.toIso8601String()} '
            '(fase $statusPhase)',
          );
        }
      } else {
        await endCheckIn();
      }
    } catch (e) {
      debugPrint('[LiveActivity] syncCheckIn falhou: $e');
    }
  }

  /// Grava cópia em chaves fixas no App Group (a widget lê `island_*`).
  Future<void> _cacheIslandPayload(Map<String, dynamic> data) async {
    if (!Platform.isIOS) return;
    try {
      final cache = <String, String>{
        for (final e in data.entries)
          if (e.value != null) e.key: e.value.toString(),
      };
      await _islandCache.invokeMethod<bool>('cacheIslandPayload', cache);
    } catch (e) {
      debugPrint('[LiveActivity] cacheIslandPayload: $e');
    }
  }

  /// Encerra a Live Activity de check-in (check-out, expiração ou logout).
  Future<void> endCheckIn() async {
    await _ensureInit();
    if (!_available) return;

    try {
      if (Platform.isIOS) {
        try {
          await _islandCache.invokeMethod<void>('clearIslandPayload');
        } catch (_) {}
      }
      await _plugin.endActivity(_activityId);
    } catch (e) {
      debugPrint('[LiveActivity] endActivity falhou, tentando endAll: $e');
      try {
        await _plugin.endAllActivities();
      } catch (_) {}
    }
  }
}
