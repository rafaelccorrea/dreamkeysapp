import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../controllers/notification_controller.dart';
import '../models/notification_model.dart';
import '../utils/notification_navigation.dart';
import 'notification_item.dart';
import '../../../core/notifications/app_toast.dart';
import '../../../core/session/session_bootstrap.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/utils/app_deep_link.dart';
import '../../../shared/widgets/app_error_state.dart';

/// Lista de notificações com scroll infinito
class NotificationList extends StatefulWidget {
  final bool embedded;
  final double? maxHeight;

  const NotificationList({
    super.key,
    this.embedded = false,
    this.maxHeight,
  });

  @override
  State<NotificationList> createState() => _NotificationListState();
}

class _NotificationListState extends State<NotificationList> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    
    // Carregar notificações ao inicializar
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = Provider.of<NotificationController>(context, listen: false);
      controller.loadNotifications(reset: true);
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      final controller = Provider.of<NotificationController>(context, listen: false);
      if (!controller.loadingMore && controller.hasMore) {
        controller.loadMore();
      }
    }
  }

  /// Toque num item do painel.
  ///
  /// ORDEM IMPORTA (era aqui o "clico na notificação e dá erro"):
  ///  1. resolve o destino ANTES de qualquer await — se não houver tela no
  ///     app, permanecemos no painel em vez de empurrar rota desconhecida
  ///     (que cai no "Página não encontrada" do `generateRoute`);
  ///  2. marcar como lida é EFEITO COLATERAL: dispara sem bloquear. Antes,
  ///     duas chamadas HTTP em série (markAsRead + refreshUnreadCount)
  ///     seguravam o toque, e uma falha delas deixava o usuário sem
  ///     navegação nenhuma;
  ///  3. captura o `NavigatorState` ANTES de fechar o sheet — depois do
  ///     `pop()` este `context` está desmontado e usá-lo estoura;
  ///  4. fecha o painel e só então navega, no Navigator RAIZ. Navegar com o
  ///     bottom sheet ainda aberto empilhava a tela por cima da rota modal
  ///     (scrim vivo, back voltando pro sheet).
  ///
  /// LINK EXTERNO (25/09/2026): "Assine a ficha" traz o short link do
  /// Autentique. Não há tela no app para isso — o destino é o navegador
  /// (`LaunchMode.externalApplication`). O painel fica aberto: quando o
  /// usuário volta do navegador, está onde estava. Marcar como lida segue
  /// igual para os dois casos.
  Future<void> _handleNotificationTap(
    BuildContext context,
    NotificationController controller,
    NotificationModel notification,
  ) async {
    final target = NotificationNavigation.getNotificationTarget(notification);

    if (!notification.read) {
      unawaited(controller.markAsRead(notification.id));
    }

    if (target == null) {
      // Notificação sem tela correspondente no app (financeiro,
      // permissões…). Fica no painel com aviso discreto.
      AppToast.show(
        context,
        message: 'Esta notificação não abre nenhuma tela do app.',
      );
      return;
    }

    if (target is AppDeepLinkExternal) {
      await _openExternal(context, target.uri);
      return;
    }

    final destination = (target as AppDeepLinkRoute).route;

    final sheetNavigator = Navigator.of(context);
    final rootNavigator = Navigator.of(context, rootNavigator: true);

    // `embedded` = lista dentro do bottom sheet do sino. Na tela cheia
    // (`NotificationsPage`) não há sheet para fechar.
    if (widget.embedded) {
      sheetNavigator.pop();
    }

    // Toque vindo de push abre o painel logo no boot: a sessão (token +
    // empresa) pode não estar resolvida e a tela de destino pediria rota
    // protegida sem `X-Company-ID`. Idempotente — instantâneo quando pronta.
    await SessionBootstrap.instance.ensureReady(
      timeout: const Duration(seconds: 12),
    );

    if (!rootNavigator.mounted) return;
    rootNavigator.pushNamed(destination);
  }

  /// Abre [uri] no navegador do aparelho. Falha vira toast com a CAUSA
  /// (sem navegador, esquema bloqueado, exceção da plataforma) — "não
  /// abriu" sem motivo não ajuda ninguém a resolver.
  Future<void> _openExternal(BuildContext context, Uri uri) async {
    String? causa;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return;
      causa = 'Nenhum aplicativo do aparelho aceitou abrir ${uri.host}.';
    } catch (e) {
      causa = e.toString();
    }
    if (!context.mounted) return;
    AppToast.error(
      context,
      'Não foi possível abrir o link no navegador.',
      subtitle: causa,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Consumer<NotificationController>(
      builder: (context, controller, child) {
        if (controller.loading && controller.notifications.isEmpty) {
          return SizedBox(
            height: widget.maxHeight ?? 300,
            child: Center(
              child: CircularProgressIndicator(
                color: isDark
                    ? AppColors.primary.primaryDarkMode
                    : AppColors.primary.primary,
              ),
            ),
          );
        }

        if (controller.error != null && controller.notifications.isEmpty) {
          return SizedBox(
            height: widget.maxHeight ?? 300,
            child: SingleChildScrollView(
              child: AppErrorState.fromApi(
                message: controller.error,
                statusCode: controller.errorStatus,
                onRetry: () => controller.loadNotifications(reset: true),
                dense: true,
              ),
            ),
          );
        }

        if (controller.notifications.isEmpty) {
          return SizedBox(
            height: widget.maxHeight ?? 300,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 48,
                    color: isDark
                        ? AppColors.text.textLightDarkMode
                        : AppColors.text.textLight,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhuma notificação',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: isDark
                          ? AppColors.text.textSecondaryDarkMode
                          : AppColors.text.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Container(
          constraints: widget.maxHeight != null
              ? BoxConstraints(maxHeight: widget.maxHeight!)
              : null,
          child: RefreshIndicator(
            onRefresh: () => controller.refresh(),
            child: ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.zero,
              itemCount: controller.notifications.length +
                  (controller.loadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= controller.notifications.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                  final notification = controller.notifications[index];
                return NotificationItem(
                  notification: notification,
                  onTap: () {
                    unawaited(
                      _handleNotificationTap(context, controller, notification),
                    );
                  },
                  onDelete: () async {
                    await controller.deleteNotification(notification.id);
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }
}

