import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:live_activities/live_activities.dart';

import 'check_in_service.dart';

/// Gerencia a Live Activity / Ilha Dinâmica do **check-in** no iOS 16.1+.
///
/// Tudo aqui é **defensivo**: em Android, iOS antigo, sem App Group
/// configurado ou se o plugin falhar, os métodos viram no-op silencioso e
/// NUNCA lançam exceção para o chamador. Assim, ligar/desligar a feature não
/// afeta o fluxo de check-in normal do app.
///
/// O App Group precisa bater EXATAMENTE com o configurado na Widget Extension
/// (`group.com.dreamkeys.corretor`).
class LiveActivityService {
  LiveActivityService._();
  static final LiveActivityService instance = LiveActivityService._();

  /// Mesmo identificador usado em `ios/CheckInWidget/CheckInWidget.entitlements`
  /// e em `Runner.entitlements`.
  static const String _appGroupId = 'group.com.dreamkeys.corretor';

  /// Só existe uma Live Activity de check-in por vez, então usamos um id fixo
  /// (o plugin 2.4.x recebe o id do chamador e o reaproveita em update/end).
  static const String _activityId = 'checkin';

  final LiveActivities _plugin = LiveActivities();

  bool _initialized = false;
  bool _available = false;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    _initialized = true;

    if (!Platform.isIOS) {
      _available = false;
      return;
    }
    try {
      await _plugin.init(appGroupId: _appGroupId);
      final supported = await _plugin.areActivitiesSupported();
      _available = supported && await _plugin.areActivitiesEnabled();
    } catch (e) {
      _available = false;
      debugPrint('[LiveActivity] init indisponível: $e');
    }
  }

  /// Reflete o estado atual do check-in na Ilha Dinâmica.
  /// Cria/atualiza a atividade quando há check-in vigente; encerra caso não haja.
  Future<void> syncCheckIn(CheckIn? active) async {
    await _ensureInit();
    if (!_available) return;

    try {
      if (active != null && active.isActive) {
        // Apenas tipos compatíveis com UserDefaults (String / num).
        final data = <String, dynamic>{
          'status': 'active',
          'userName': active.user?.name ?? '',
          'checkedInAtEpoch': active.checkedInAt.millisecondsSinceEpoch,
          'expiresAtEpoch': active.expiresAt.millisecondsSinceEpoch,
        };
        await _plugin.createOrUpdateActivity(_activityId, data);
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
