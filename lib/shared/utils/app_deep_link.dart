import '../../core/routes/app_routes.dart';

/// Resolve URLs/payloads de notificação e push para rotas do app mobile.
class AppDeepLink {
  AppDeepLink._();

  /// Converte [actionUrl] web ou payload FCM em rota interna.
  static String? resolve({
    String? actionUrl,
    String? entityType,
    String? entityId,
    Map<String, dynamic>? metadata,
  }) {
    if (actionUrl != null && actionUrl.trim().isNotEmpty) {
      final mobile = _fromActionUrl(actionUrl.trim());
      if (mobile != null) return mobile;
    }
    if (entityType != null &&
        entityType.trim().isNotEmpty &&
        entityId != null &&
        entityId.trim().isNotEmpty) {
      return _fromEntity(entityType.trim(), entityId.trim(), metadata);
    }
    return null;
  }

  static String? fromPushData(Map<String, dynamic> data) {
    return resolve(
      actionUrl: data['actionUrl']?.toString() ?? data['url']?.toString(),
      entityType: data['entityType']?.toString(),
      entityId: data['entityId']?.toString() ?? data['id']?.toString(),
      metadata: data['metadata'] is Map
          ? Map<String, dynamic>.from(data['metadata'] as Map)
          : null,
    );
  }

  static String? _fromActionUrl(String url) {
    if (url.startsWith('/')) return _normalizeMobilePath(url);
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final path = uri.path;
    if (path.isEmpty) return null;
    return _normalizeMobilePath(path);
  }

  static String? _normalizeMobilePath(String path) {
    if (path.startsWith('/kanban/task/')) return path;
    if (path.startsWith('/tasks/')) {
      final id = path.split('/').where((s) => s.isNotEmpty).last;
      return AppRoutes.kanbanTaskDetails(id);
    }
    if (path.startsWith('/appointments/') && !path.contains('/invites/')) {
      final segments = path.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.length == 2) {
        return AppRoutes.calendarDetails(segments[1]);
      }
    }
    if (path.startsWith('/proposals/')) {
      final segments = path.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.length >= 2 && segments.last != 'edit') {
        return AppRoutes.proposalEdit(segments[1]);
      }
      return AppRoutes.proposals;
    }
    if (path.startsWith('/properties/')) return path;
    if (path.startsWith('/clients/')) return path;
    if (path.startsWith('/kanban')) return path;
    if (path == '/notifications') return AppRoutes.notifications;
    return path;
  }

  static String? _fromEntity(
    String entityType,
    String entityId,
    Map<String, dynamic>? metadata,
  ) {
    switch (entityType.toLowerCase()) {
      case 'task':
      case 'kanban_task':
      case 'lead':
        return AppRoutes.kanbanTaskDetails(entityId);
      case 'appointment':
        return AppRoutes.calendarDetails(entityId);
      case 'property':
        return AppRoutes.propertyDetails(entityId);
      case 'client':
        return AppRoutes.clientDetails(entityId);
      case 'proposal':
      case 'purchase_proposal':
        return AppRoutes.proposalEdit(entityId);
      case 'property_match':
        final propertyId = metadata?['propertyId']?.toString();
        if (propertyId != null && propertyId.isNotEmpty) {
          return AppRoutes.matchesByProperty(propertyId);
        }
        return AppRoutes.matches;
      case 'inspection':
        return AppRoutes.inspectionDetails(entityId);
      case 'document':
        return AppRoutes.documentDetails(entityId);
      case 'lead_claim':
      case 'whatsapp_lead_claim':
        return AppRoutes.kanbanTaskDetails(entityId);
      case 'note':
        return AppRoutes.notes;
      case 'message':
      case 'chat':
        return AppRoutes.chat;
      default:
        return null;
    }
  }
}
