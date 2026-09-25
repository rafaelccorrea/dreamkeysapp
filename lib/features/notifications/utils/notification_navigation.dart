import '../../../shared/utils/app_deep_link.dart';
import '../models/notification_model.dart';

/// Utilitário para determinar URL de navegação de notificações
class NotificationNavigation {
  NotificationNavigation._();

  static String? getNotificationNavigationUrl(NotificationModel notification) {
    return AppDeepLink.resolve(
      actionUrl: notification.actionUrl,
      entityType: notification.entityType,
      entityId: notification.entityId,
      metadata: notification.metadata,
    );
  }

  /// Destino completo do toque: rota interna OU link externo (25/09/2026).
  ///
  /// "Assine a ficha" traz o short link do Autentique — abre no navegador,
  /// não no `Navigator`. Mesmo resolvedor do push (`AppDeepLink`), para o
  /// toque no painel e o toque na notificação do sistema nunca divergirem.
  static AppDeepLinkTarget? getNotificationTarget(
    NotificationModel notification,
  ) {
    return AppDeepLink.resolveTarget(
      actionUrl: notification.actionUrl,
      entityType: notification.entityType,
      entityId: notification.entityId,
      metadata: notification.metadata,
    );
  }

  static String getNotificationTypeLabel(String type) {
    switch (type.toLowerCase()) {
      // Ficha de venda (25/09/2026): assinatura pedida/feita/recusada e
      // ficha finalizada.
      case 'sale_form_signature_requested':
      case 'sale_form_signature_signed':
      case 'sale_form_signature_rejected':
      case 'sale_form_finalized':
        return 'Ficha de venda';
      case 'rental_expiring':
      case 'rental_expired':
        return 'Aluguel';
      case 'payment_due':
      case 'payment_overdue':
        return 'Pagamento';
      case 'key_pending_return':
      case 'key_overdue':
        return 'Chave';
      case 'inspection_scheduled':
      case 'inspection_overdue':
      case 'inspection_approval_requested':
      case 'inspection_approved':
      case 'inspection_rejected':
        return 'Vistoria';
      case 'client_document_expiring':
      case 'property_document_expiring':
        return 'Documento';
      case 'task_assigned':
      case 'task_due':
      case 'task_overdue':
        return 'Lead / Tarefa';
      case 'note_pending':
        return 'Nota';
      case 'appointment_reminder':
      case 'appointment_invite':
      case 'appointment_invite_accepted':
      case 'appointment_invite_declined':
        return 'Compromisso';
      case 'subscription_expiring_soon':
      case 'subscription_expired':
        return 'Assinatura';
      case 'reward_redemption_requested':
      case 'reward_redemption_approved':
      case 'reward_redemption_rejected':
      case 'reward_delivered':
        return 'Recompensa';
      case 'system_alert':
      case 'new_message':
        return 'Sistema';
      case 'property_match_found':
      case 'property_match_high_score':
        return 'Match de Propriedade';
      default:
        return 'Notificação';
    }
  }
}
