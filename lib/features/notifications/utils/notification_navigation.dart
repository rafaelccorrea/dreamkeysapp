import '../models/notification_model.dart';

/// Utilitário para determinar URL de navegação de notificações
class NotificationNavigation {
  NotificationNavigation._();

  /// Obtém URL de navegação para uma notificação
  /// Prioridade 1: actionUrl se existir
  /// Prioridade 2: entityType e entityId para gerar URL
  static String? getNotificationNavigationUrl(NotificationModel notification) {
    // Prioridade 1: Usar actionUrl se existir
    if (notification.actionUrl != null &&
        notification.actionUrl!.isNotEmpty) {
      return notification.actionUrl;
    }

    // Prioridade 2: Gerar URL baseado em entityType e entityId
    if (notification.entityType != null &&
        notification.entityId != null) {
      return _generateUrlFromEntity(
        notification.entityType!,
        notification.entityId!,
        notification.metadata,
      );
    }

    return null;
  }

  /// Gera URL baseado no tipo de entidade
  static String? _generateUrlFromEntity(
    String entityType,
    String entityId,
    Map<String, dynamic>? metadata,
  ) {
    switch (entityType.toLowerCase()) {
      case 'inspection':
        return '/inspections/$entityId';

      case 'inspection_approval':
        return '/financial/inspection-approvals';

      case 'rental':
        return '/rentals/$entityId';

      case 'key':
        return '/keys/$entityId';

      case 'payment':
        return '/financial/payments/$entityId';

      case 'document':
        // Documentos podem ser de cliente ou propriedade
        if (metadata != null) {
          final clientId = metadata['clientId']?.toString();
          final propertyId = metadata['propertyId']?.toString();

          if (clientId != null && clientId.isNotEmpty) {
            return '/clients/$clientId/documents';
          } else if (propertyId != null && propertyId.isNotEmpty) {
            return '/properties/$propertyId/documents';
          }
        }
        return '/documents';

      case 'task':
        return '/tasks/$entityId';

      case 'appointment':
        return '/appointments/$entityId';

      case 'appointment_invite':
        return '/appointments/invites/$entityId';

      case 'note':
        return '/notes/$entityId';

      case 'message':
        return '/messages/$entityId';

      case 'subscription':
        return '/subscriptions';

      case 'property_match':
        // Property match pode ter propertyId no metadata
        if (metadata != null) {
          final propertyId = metadata['propertyId']?.toString();
          if (propertyId != null && propertyId.isNotEmpty) {
            return '/properties/$propertyId/matches';
          }
        }
        return '/matches';

      case 'property':
        return '/properties/$entityId';

      default:
        // Tipo desconhecido, retornar null
        return null;
    }
  }

  /// Obtém label do tipo de notificação
  static String getNotificationTypeLabel(String type) {
    switch (type.toLowerCase()) {
      // Aluguéis
      case 'rental_expiring':
      case 'rental_expired':
        return 'Aluguel';

      // Pagamentos
      case 'payment_due':
      case 'payment_overdue':
        return 'Pagamento';

      // Chaves
      case 'key_pending_return':
      case 'key_overdue':
        return 'Chave';

      // Vistorias
      case 'inspection_scheduled':
      case 'inspection_overdue':
      case 'inspection_approval_requested':
      case 'inspection_approved':
      case 'inspection_rejected':
        return 'Vistoria';

      // Documentos
      case 'client_document_expiring':
      case 'property_document_expiring':
        return 'Documento';

      // Tarefas
      case 'task_assigned':
      case 'task_due':
      case 'task_overdue':
        return 'Tarefa';

      // Notas
      case 'note_pending':
        return 'Nota';

      // Compromissos
      case 'appointment_reminder':
      case 'appointment_invite':
      case 'appointment_invite_accepted':
      case 'appointment_invite_declined':
        return 'Compromisso';

      // Assinaturas
      case 'subscription_expiring_soon':
      case 'subscription_expired':
        return 'Assinatura';

      // Recompensas
      case 'reward_redemption_requested':
      case 'reward_redemption_approved':
      case 'reward_redemption_rejected':
      case 'reward_delivered':
        return 'Recompensa';

      // Sistema
      case 'system_alert':
      case 'new_message':
        return 'Sistema';

      // Matches
      case 'property_match_found':
      case 'property_match_high_score':
        return 'Match de Propriedade';

      // Propriedades
      default:
        return 'Notificação';
    }
  }
}





