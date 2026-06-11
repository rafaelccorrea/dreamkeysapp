import '../../core/routes/app_routes.dart';
import '../state/recent_navigation_cache.dart';

/// Salva "continuar de onde parou" ao abrir telas-chave do corretor.
class RecentNavHelper {
  RecentNavHelper._();

  static Future<void> trackProperty(String id, String title) =>
      RecentNavigationCache.instance.save(
        route: AppRoutes.propertyDetails(id),
        label: title,
        extra: 'Imóvel',
      );

  static Future<void> trackClient(String id, String name) =>
      RecentNavigationCache.instance.save(
        route: AppRoutes.clientDetails(id),
        label: name,
        extra: 'Cliente',
      );

  static Future<void> trackKanbanTask(String id, String title) =>
      RecentNavigationCache.instance.save(
        route: AppRoutes.kanbanTaskDetails(id),
        label: title,
        extra: 'Negociação',
      );
}
