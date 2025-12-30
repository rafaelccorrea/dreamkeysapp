import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../controllers/chat_unread_controller.dart';

/// Botão flutuante para acesso rápido ao chat quando há mensagens não lidas
class ChatFloatingButton extends StatelessWidget {
  const ChatFloatingButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatUnreadController>(
      builder: (context, controller, child) {
        final unreadCount = controller.totalUnreadCount;

        // Só mostrar se houver mensagens não lidas
        if (unreadCount == 0) {
          return const SizedBox.shrink();
        }

        final currentRoute = ModalRoute.of(context)?.settings.name;
        
        // Não mostrar se já estiver na página de chat
        if (currentRoute == AppRoutes.chat || 
            (currentRoute != null && currentRoute.startsWith('/chat'))) {
          return const SizedBox.shrink();
        }

        return Positioned(
          bottom: 80, // Acima da bottom navigation
          right: 16,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(28),
            color: AppColors.primary.primary,
            child: InkWell(
              onTap: () {
                Navigator.of(context).pushNamedAndRemoveUntil(
                  AppRoutes.chat,
                  (route) => false,
                );
              },
              borderRadius: BorderRadius.circular(28),
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Center(
                      child: Icon(
                        Icons.chat_bubble,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white,
                            width: 2,
                          ),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        child: Text(
                          unreadCount > 99 ? '99+' : '$unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            height: 1,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

