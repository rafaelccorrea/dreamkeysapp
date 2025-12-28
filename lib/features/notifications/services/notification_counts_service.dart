import '../models/notification_model.dart';

/// Mapeamento de rotas para tipos de notificação
const Map<String, List<String>> routeToNotificationTypes = {
  '/inspections': ['inspection', 'inspection_approval'],
  '/rentals': ['rental'],
  '/keys': ['key'],
  '/financial': ['payment', 'inspection_approval'],
  '/clients': ['client', 'document'],
  '/properties': ['property', 'property_match', 'document'],
  '/matches': ['property_match'],
  '/tasks': ['task'],
  '/calendar': ['appointment', 'appointment_invite'], // Agenda usa /calendar
  '/notes': ['note'],
  '/messages': ['message'],
  '/subscriptions': ['subscription'],
};

/// Serviço para calcular badges de notificações por rota
class NotificationCountsService {
  NotificationCountsService._();

  static final NotificationCountsService _instance =
      NotificationCountsService._();

  factory NotificationCountsService() => _instance;

  static NotificationCountsService get instance => _instance;

  /// Calcula contadores de notificações por rota
  Map<String, int> calculateCountsByRoute(
    List<NotificationModel> notifications,
  ) {
    final counts = <String, int>{};

    // Inicializar contadores para todas as rotas
    for (final route in routeToNotificationTypes.keys) {
      counts[route] = 0;
    }

    // Contar notificações não lidas por rota
    for (final notification in notifications) {
      if (notification.read) continue;

      // Verificar cada rota
      for (final entry in routeToNotificationTypes.entries) {
        final route = entry.key;
        final types = entry.value;

        // Verificar se o tipo ou entityType corresponde
        if (types.contains(notification.type) ||
            (notification.entityType != null &&
                types.contains(notification.entityType!))) {
          counts[route] = (counts[route] ?? 0) + 1;
        }
      }
    }

    return counts;
  }

  /// Obtém contador para uma rota específica
  int getCountForRoute(
    String route,
    List<NotificationModel> notifications,
  ) {
    final counts = calculateCountsByRoute(notifications);
    return counts[route] ?? 0;
  }

  /// Obtém contador total de não lidas
  int getTotalCount(List<NotificationModel> notifications) {
    return notifications.where((n) => !n.read).length;
  }

  /// Verifica se uma notificação corresponde a uma rota
  bool notificationMatchesRoute(
    NotificationModel notification,
    String route,
  ) {
    if (notification.read) return false;

    final types = routeToNotificationTypes[route];
    if (types == null) return false;

    return types.contains(notification.type) ||
        (notification.entityType != null &&
            types.contains(notification.entityType!));
  }
}

