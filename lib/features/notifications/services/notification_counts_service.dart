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
  '/kanban': ['task', 'task_assigned', 'task_due', 'task_overdue'],
  '/calendar': ['appointment', 'appointment_invite'], // Agenda uses /calendar
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

  /// Calcula contadores de notificações por rota.
  ///
  /// [activeCompanyId] restringe a contagem à empresa em que o usuário está
  /// operando. É ESSENCIAL: a lista que alimenta este cálculo vem de
  /// `/notifications/all-companies` (traz todas as empresas de propósito),
  /// então sem o recorte o badge da navbar mostrava notificação de OUTRA
  /// imobiliária — o caso da Village, sem nenhum imóvel, exibindo "2" sobre
  /// o ícone de Imóveis por causa de pendências da "Imobiliária de Teste".
  ///
  /// Notificações pessoais (`companyId == null`) valem em qualquer contexto
  /// e seguem contando. Sem [activeCompanyId] o comportamento antigo é
  /// mantido (conta tudo) — evita zerar badges antes da sessão resolver a
  /// empresa.
  Map<String, int> calculateCountsByRoute(
    List<NotificationModel> notifications, {
    String? activeCompanyId,
  }) {
    final counts = <String, int>{};
    final escopo = (activeCompanyId ?? '').trim();
    final filtrarPorEmpresa = escopo.isNotEmpty;

    // Inicializar contadores para todas as rotas
    for (final route in routeToNotificationTypes.keys) {
      counts[route] = 0;
    }

    // Contar notificações não lidas por rota
    for (final notification in notifications) {
      if (notification.read) continue;

      // Fora da empresa ativa não conta (pessoal, sem empresa, sempre conta).
      if (filtrarPorEmpresa) {
        final dona = (notification.companyId ?? '').trim();
        if (dona.isNotEmpty && dona != escopo) continue;
      }

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
    List<NotificationModel> notifications, {
    String? activeCompanyId,
  }) {
    final counts = calculateCountsByRoute(
      notifications,
      activeCompanyId: activeCompanyId,
    );
    return counts[route] ?? 0;
  }

  /// Obtém contador total de não lidas
  int getTotalCount(
    List<NotificationModel> notifications, {
    String? activeCompanyId,
  }) {
    final escopo = (activeCompanyId ?? '').trim();
    return notifications.where((n) {
      if (n.read) return false;
      if (escopo.isEmpty) return true;
      final dona = (n.companyId ?? '').trim();
      return dona.isEmpty || dona == escopo;
    }).length;
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

