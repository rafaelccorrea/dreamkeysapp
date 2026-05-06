import 'package:flutter/material.dart';

/// Categorias visuais de notificação (espelha o intellisys-web).
///
/// Cada categoria define a cor temática e a label curta exibida no chip.
enum NotificationCategory {
  lead,
  rental,
  payment,
  key,
  inspection,
  document,
  task,
  taskMention,
  note,
  appointment,
  subscription,
  reward,
  propertyMatch,
  propertyApproval,
  property,
  message,
  system,
  generic;

  /// Label exibida no chip (ao lado da data).
  String get label {
    switch (this) {
      case NotificationCategory.lead:
        return 'Lead';
      case NotificationCategory.rental:
        return 'Aluguel';
      case NotificationCategory.payment:
        return 'Pagamento';
      case NotificationCategory.key:
        return 'Chave';
      case NotificationCategory.inspection:
        return 'Vistoria';
      case NotificationCategory.document:
        return 'Documento';
      case NotificationCategory.task:
        return 'Tarefa';
      case NotificationCategory.taskMention:
        return 'Menção';
      case NotificationCategory.note:
        return 'Nota';
      case NotificationCategory.appointment:
        return 'Compromisso';
      case NotificationCategory.subscription:
        return 'Assinatura';
      case NotificationCategory.reward:
        return 'Recompensa';
      case NotificationCategory.propertyMatch:
        return 'Match';
      case NotificationCategory.propertyApproval:
        return 'Aprovação';
      case NotificationCategory.property:
        return 'Imóvel';
      case NotificationCategory.message:
        return 'Mensagem';
      case NotificationCategory.system:
        return 'Sistema';
      case NotificationCategory.generic:
        return 'Notificação';
    }
  }
}

/// Estilo visual derivado do `type` de uma notificação.
///
/// Uso típico:
/// ```dart
/// final style = NotificationTypeStyle.fromType(notification.type);
/// // style.color, style.icon, style.category.label
/// ```
class NotificationTypeStyle {
  final NotificationCategory category;
  final Color color;
  final IconData icon;

  const NotificationTypeStyle({
    required this.category,
    required this.color,
    required this.icon,
  });

  /// Resolve estilo a partir do `type` cru retornado pelo backend.
  factory NotificationTypeStyle.fromType(String? rawType) {
    final type = (rawType ?? '').toLowerCase();

    // ── Leads ────────────────────────────────────────────────────────────
    if (type == 'whatsapp_lead_received') {
      return const NotificationTypeStyle(
        category: NotificationCategory.lead,
        color: Color(0xFF22C55E), // verde WhatsApp
        icon: Icons.chat_rounded,
      );
    }
    if (type == 'meta_lead_received') {
      return const NotificationTypeStyle(
        category: NotificationCategory.lead,
        color: Color(0xFF1877F2), // azul Meta
        icon: Icons.campaign_rounded,
      );
    }

    // ── Aluguéis ─────────────────────────────────────────────────────────
    if (type == 'rental_expiring') {
      return const NotificationTypeStyle(
        category: NotificationCategory.rental,
        color: Color(0xFFF59E0B),
        icon: Icons.home_rounded,
      );
    }
    if (type == 'rental_expired') {
      return const NotificationTypeStyle(
        category: NotificationCategory.rental,
        color: Color(0xFFEF4444),
        icon: Icons.home_rounded,
      );
    }

    // ── Pagamentos ───────────────────────────────────────────────────────
    if (type == 'payment_due') {
      return const NotificationTypeStyle(
        category: NotificationCategory.payment,
        color: Color(0xFFF59E0B),
        icon: Icons.payments_rounded,
      );
    }
    if (type == 'payment_overdue') {
      return const NotificationTypeStyle(
        category: NotificationCategory.payment,
        color: Color(0xFFEF4444),
        icon: Icons.payments_rounded,
      );
    }

    // ── Chaves ───────────────────────────────────────────────────────────
    if (type == 'key_pending_return') {
      return const NotificationTypeStyle(
        category: NotificationCategory.key,
        color: Color(0xFFF59E0B),
        icon: Icons.vpn_key_rounded,
      );
    }
    if (type == 'key_overdue') {
      return const NotificationTypeStyle(
        category: NotificationCategory.key,
        color: Color(0xFFEF4444),
        icon: Icons.vpn_key_rounded,
      );
    }

    // ── Vistorias ────────────────────────────────────────────────────────
    if (type == 'inspection_scheduled') {
      return const NotificationTypeStyle(
        category: NotificationCategory.inspection,
        color: Color(0xFF3B82F6),
        icon: Icons.search_rounded,
      );
    }
    if (type == 'inspection_overdue' ||
        type == 'inspection_approval_requested' ||
        type == 'inspection_rejected') {
      return const NotificationTypeStyle(
        category: NotificationCategory.inspection,
        color: Color(0xFFEF4444),
        icon: Icons.search_rounded,
      );
    }
    if (type == 'inspection_approved') {
      return const NotificationTypeStyle(
        category: NotificationCategory.inspection,
        color: Color(0xFF10B981),
        icon: Icons.check_circle_rounded,
      );
    }

    // ── Documentos ───────────────────────────────────────────────────────
    if (type == 'client_document_expiring' ||
        type == 'property_document_expiring') {
      return const NotificationTypeStyle(
        category: NotificationCategory.document,
        color: Color(0xFFF59E0B),
        icon: Icons.description_rounded,
      );
    }

    // ── Tarefas ──────────────────────────────────────────────────────────
    if (type == 'task_assigned') {
      return const NotificationTypeStyle(
        category: NotificationCategory.task,
        color: Color(0xFF10B981),
        icon: Icons.assignment_rounded,
      );
    }
    if (type == 'task_due') {
      return const NotificationTypeStyle(
        category: NotificationCategory.task,
        color: Color(0xFFF59E0B),
        icon: Icons.assignment_rounded,
      );
    }
    if (type == 'task_overdue') {
      return const NotificationTypeStyle(
        category: NotificationCategory.task,
        color: Color(0xFFEF4444),
        icon: Icons.assignment_late_rounded,
      );
    }
    if (type == 'task_comment_mention') {
      return const NotificationTypeStyle(
        category: NotificationCategory.taskMention,
        color: Color(0xFFC62828),
        icon: Icons.alternate_email_rounded,
      );
    }
    if (type == 'task_comment_reply') {
      return const NotificationTypeStyle(
        category: NotificationCategory.taskMention,
        color: Color(0xFFAD1457),
        icon: Icons.reply_rounded,
      );
    }

    // ── Notas ────────────────────────────────────────────────────────────
    if (type == 'note_pending') {
      return const NotificationTypeStyle(
        category: NotificationCategory.note,
        color: Color(0xFF3B82F6),
        icon: Icons.sticky_note_2_rounded,
      );
    }

    // ── Compromissos ─────────────────────────────────────────────────────
    if (type == 'appointment_reminder') {
      return const NotificationTypeStyle(
        category: NotificationCategory.appointment,
        color: Color(0xFFF59E0B),
        icon: Icons.event_rounded,
      );
    }
    if (type == 'appointment_invite') {
      return const NotificationTypeStyle(
        category: NotificationCategory.appointment,
        color: Color(0xFF3B82F6),
        icon: Icons.event_available_rounded,
      );
    }
    if (type == 'appointment_invite_accepted') {
      return const NotificationTypeStyle(
        category: NotificationCategory.appointment,
        color: Color(0xFF10B981),
        icon: Icons.event_available_rounded,
      );
    }
    if (type == 'appointment_invite_declined') {
      return const NotificationTypeStyle(
        category: NotificationCategory.appointment,
        color: Color(0xFFEF4444),
        icon: Icons.event_busy_rounded,
      );
    }

    // ── Assinaturas ──────────────────────────────────────────────────────
    if (type == 'subscription_expiring_soon') {
      return const NotificationTypeStyle(
        category: NotificationCategory.subscription,
        color: Color(0xFFF59E0B),
        icon: Icons.subscriptions_rounded,
      );
    }
    if (type == 'subscription_expired') {
      return const NotificationTypeStyle(
        category: NotificationCategory.subscription,
        color: Color(0xFFEF4444),
        icon: Icons.subscriptions_rounded,
      );
    }

    // ── Recompensas ──────────────────────────────────────────────────────
    if (type.startsWith('reward_')) {
      Color color;
      IconData icon;
      switch (type) {
        case 'reward_redemption_approved':
        case 'reward_delivered':
          color = const Color(0xFF10B981);
          icon = Icons.workspace_premium_rounded;
          break;
        case 'reward_redemption_rejected':
          color = const Color(0xFFEF4444);
          icon = Icons.workspace_premium_rounded;
          break;
        default:
          color = const Color(0xFF8B5CF6);
          icon = Icons.workspace_premium_rounded;
      }
      return NotificationTypeStyle(
        category: NotificationCategory.reward,
        color: color,
        icon: icon,
      );
    }

    // ── Match de propriedades ────────────────────────────────────────────
    if (type == 'property_match_found' || type == 'property_match_high_score') {
      return const NotificationTypeStyle(
        category: NotificationCategory.propertyMatch,
        color: Color(0xFF8B5CF6),
        icon: Icons.home_work_rounded,
      );
    }

    // ── Aprovações de imóvel ─────────────────────────────────────────────
    if (type == 'property_responsible_availability_approved' ||
        type == 'property_responsible_publication_approved') {
      return const NotificationTypeStyle(
        category: NotificationCategory.propertyApproval,
        color: Color(0xFF10B981),
        icon: Icons.check_circle_rounded,
      );
    }
    if (type == 'property_responsible_availability_rejected' ||
        type == 'property_responsible_publication_rejected') {
      return const NotificationTypeStyle(
        category: NotificationCategory.propertyApproval,
        color: Color(0xFFEF4444),
        icon: Icons.warning_rounded,
      );
    }
    if (type == 'property_responsible_availability_reopened' ||
        type == 'property_responsible_publication_reopened') {
      return const NotificationTypeStyle(
        category: NotificationCategory.propertyApproval,
        color: Color(0xFF3B82F6),
        icon: Icons.refresh_rounded,
      );
    }
    if (type == 'property_approval_thread_message') {
      return const NotificationTypeStyle(
        category: NotificationCategory.propertyApproval,
        color: Color(0xFF3B82F6),
        icon: Icons.forum_rounded,
      );
    }

    // ── Atualização de imóvel ────────────────────────────────────────────
    if (type == 'property_update_reminder') {
      return const NotificationTypeStyle(
        category: NotificationCategory.property,
        color: Color(0xFFF59E0B),
        icon: Icons.update_rounded,
      );
    }

    // ── Mensagens / Sistema ──────────────────────────────────────────────
    if (type == 'new_message') {
      return const NotificationTypeStyle(
        category: NotificationCategory.message,
        color: Color(0xFF3B82F6),
        icon: Icons.message_rounded,
      );
    }
    if (type == 'system_alert') {
      return const NotificationTypeStyle(
        category: NotificationCategory.system,
        color: Color(0xFF8B5CF6),
        icon: Icons.info_rounded,
      );
    }

    // ── Default ──────────────────────────────────────────────────────────
    return const NotificationTypeStyle(
      category: NotificationCategory.generic,
      color: Color(0xFF3B82F6),
      icon: Icons.notifications_rounded,
    );
  }
}
