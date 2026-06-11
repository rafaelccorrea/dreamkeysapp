import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/kanban/models/kanban_subtask_models.dart';
import '../../features/kanban/services/kanban_subtask_service.dart';
import '../../shared/state/broker_offline_cache.dart';

/// Lembretes locais ~15 min antes do vencimento de subtarefas do CRM.
///
/// Dispara ao sincronizar (ex.: abrir o Início) quando o prazo está a ≤15 min.
class SubtaskReminderService {
  SubtaskReminderService._();
  static final SubtaskReminderService instance = SubtaskReminderService._();

  static const _notifiedKey = 'subtask_reminders_notified_v1';
  static const _channelId = 'imobx_subtask_reminders';
  static const _reminderWindow = Duration(minutes: 15);

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
    );
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        'Lembretes de follow-up',
        description: 'Aviso antes do vencimento de tarefas do CRM',
        importance: Importance.high,
      ),
    );
    _ready = true;
  }

  Future<void> syncFromServer() async {
    await init();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekAhead = today.add(const Duration(days: 14));

    final res = await KanbanSubtaskService.instance.getMySubTasks(
      filters: SubTasksListFilters(
        onlyMine: true,
        isCompleted: false,
        dueDateFrom: today,
        dueDateTo: weekAhead,
        page: 1,
        limit: 40,
      ),
      useCache: false,
    );

    if (!res.success || res.data == null) return;

    final items = res.data!.data;
    await BrokerOfflineCache.instance.saveSubtasks(
      items
          .map(
            (s) => {
              'id': s.id,
              'title': s.title,
              'taskId': s.taskId,
              'dueDate': s.dueDate?.toIso8601String(),
              'taskTitle': s.taskTitle ?? s.parentTaskTitle,
            },
          )
          .toList(),
    );

    final prefs = await SharedPreferences.getInstance();
    final notifiedRaw = prefs.getString(_notifiedKey);
    final notified = notifiedRaw != null
        ? Set<String>.from(jsonDecode(notifiedRaw) as List)
        : <String>{};

    for (final sub in items) {
      final due = sub.dueDate;
      if (due == null || sub.isCompleted) continue;

      final diff = due.difference(now);
      if (diff.isNegative || diff > _reminderWindow) continue;

      final dedupeKey = '${sub.id}_${due.toIso8601String()}';
      if (notified.contains(dedupeKey)) continue;

      final cardLabel = sub.taskTitle ?? sub.parentTaskTitle ?? 'CRM';
      await _plugin.show(
        id: sub.id.hashCode & 0x7fffffff,
        title: 'Follow-up: ${sub.title}',
        body: 'Card: $cardLabel · vence em breve',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Lembretes de follow-up',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: jsonEncode({
          'entityType': 'task',
          'entityId': sub.taskId,
        }),
      );
      notified.add(dedupeKey);
    }

    await prefs.setString(_notifiedKey, jsonEncode(notified.toList()));
    debugPrint('⏰ [SUBTASK_REMINDER] sync OK (${items.length} subtarefas)');
  }
}
