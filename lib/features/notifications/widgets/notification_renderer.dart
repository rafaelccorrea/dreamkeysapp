import 'package:flutter/material.dart';
import '../models/notification_model.dart';
import 'property_match_notification.dart';

/// Renderizador que detecta o tipo e renderiza o componente apropriado
class NotificationRenderer extends StatelessWidget {
  final NotificationModel notification;
  final VoidCallback? onRead;

  const NotificationRenderer({
    super.key,
    required this.notification,
    this.onRead,
  });

  @override
  Widget build(BuildContext context) {
    // Verificar se é notificação de match de propriedade
    if (_isPropertyMatchNotification(notification.type)) {
      return PropertyMatchNotification(
        notification: notification,
        onRead: onRead,
      );
    }

    // Para outros tipos, usar renderização padrão
    // Por enquanto, retornar Container vazio
    // Pode ser expandido no futuro para outros tipos específicos
    return const SizedBox.shrink();
  }

  bool _isPropertyMatchNotification(String type) {
    return type.toLowerCase() == 'property_match_found' ||
        type.toLowerCase() == 'property_match_high_score';
  }
}


