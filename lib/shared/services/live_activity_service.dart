import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
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

  final LiveActivities _plugin = LiveActivities();

  bool _initialized = false;
  bool _available = false;
  bool _bootstrapped = false;
  StreamSubscription<UrlSchemeData>? _urlSub;

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
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    final current = ModalRoute.of(nav.context)?.settings.name;
    if (current == AppRoutes.checkIn) return;
    nav.pushNamed(AppRoutes.checkIn);
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
      _available = supported && await _plugin.areActivitiesEnabled();
    } catch (e) {
      _available = false;
      debugPrint('[LiveActivity] init indisponível: $e');
    }
  }

  Future<void> _syncFromApi() async {
    await _ensureInit();
    if (!_available) return;
    try {
      final res = await CheckInService.instance.getActiveCheckIn();
      if (res.success) {
        await syncCheckIn(res.data);
      }
    } catch (e) {
      debugPrint('[LiveActivity] syncFromApi: $e');
    }
  }

  /// Reflete o estado atual do check-in na Ilha Dinâmica.
  Future<void> syncCheckIn(CheckIn? active) async {
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
        final data = <String, dynamic>{
          'status': 'active',
          'statusPhase': statusPhase,
          'userName': name.isEmpty ? 'Corretor' : name,
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

  /// Encerra a Live Activity de check-in (check-out, expiração ou logout).
  Future<void> endCheckIn() async {
    await _ensureInit();
    if (!_available) return;

    try {
      await _plugin.endActivity(_activityId);
    } catch (e) {
      debugPrint('[LiveActivity] endActivity falhou, tentando endAll: $e');
      try {
        await _plugin.endAllActivities();
      } catch (_) {}
    }
  }
}
