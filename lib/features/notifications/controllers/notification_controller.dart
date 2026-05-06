import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/notification_model.dart';
import '../services/notification_service.dart';
import '../services/notification_websocket_service.dart';
import '../services/notification_counts_service.dart';
import '../../../shared/services/secure_storage_service.dart';

/// Controller para gerenciar estado das notificações
class NotificationController extends ChangeNotifier {
  NotificationController._();

  static final NotificationController instance = NotificationController._();

  final NotificationService _notificationService = NotificationService.instance;
  final NotificationWebSocketService _wsService =
      NotificationWebSocketService.instance;
  final NotificationCountsService _countsService =
      NotificationCountsService.instance;

  // Estado
  List<NotificationModel> _notifications = [];
  int _unreadCount = 0;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  bool _hasMore = true;
  int _currentPage = 1;
  static const int _pageLimit = 20;

  // Filtros
  bool? _filterRead;
  String? _filterType;
  String? _filterCompanyId;

  // WebSocket
  bool _wsConnected = false;

  // Getters
  List<NotificationModel> get notifications => List.unmodifiable(_notifications);
  int get unreadCount => _unreadCount;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  String? get error => _error;
  bool get hasMore => _hasMore;
  bool get wsConnected => _wsConnected;

  /// Obtém contador de notificações para uma rota específica
  int getCountForRoute(String route) {
    return _countsService.getCountForRoute(route, _notifications);
  }

  /// Obtém contadores por rota
  Map<String, int> get countsByRoute {
    return _countsService.calculateCountsByRoute(_notifications);
  }

  /// Inicializa o controller
  Future<void> initialize() async {
    // Configurar callbacks do WebSocket
    _setupWebSocketCallbacks();

    // Carregar contador inicial
    await refreshUnreadCount();

    // Conectar WebSocket se tiver userId
    final userId = await _getUserId();
    if (userId != null) {
      await _wsService.connect(userId);
      
      // Inscrever na empresa selecionada
      await _subscribeToSelectedCompany();
    }
  }

  /// Inscreve-se na empresa selecionada
  Future<void> _subscribeToSelectedCompany() async {
    try {
      final companyId = await SecureStorageService.instance.getCompanyId();
      if (companyId != null && companyId.isNotEmpty) {
        _wsService.subscribeCompany(companyId);
      }
    } catch (e) {
      debugPrint('⚠️ [NOTIFICATION_CTRL] Erro ao inscrever empresa: $e');
    }
  }

  /// Configura callbacks do WebSocket
  void _setupWebSocketCallbacks() {
    _wsService.setOnNotificationReceived((notification) {
      // Adicionar no início da lista
      _notifications.insert(0, notification);
      if (!notification.read) {
        _unreadCount++;
      }
      notifyListeners();
    });

    _wsService.setOnBadgeUpdate((count) {
      _unreadCount = count;
      notifyListeners();
    });

    _wsService.setOnNotificationRead((notificationId) {
      // Atualizar notificação local
      final index = _notifications.indexWhere((n) => n.id == notificationId);
      if (index != -1) {
        final notification = _notifications[index];
        if (!notification.read) {
          _unreadCount = (_unreadCount - 1).clamp(0, double.infinity).toInt();
        }
        _notifications[index] = notification.copyWith(read: true);
        notifyListeners();
      }
    });

    _wsService.setOnConnectionStatusChanged((connected) {
      _wsConnected = connected;
      notifyListeners();
    });

    _wsService.setOnCompanySubscribed((companyId) {
      debugPrint('✅ [NOTIFICATION_CTRL] Empresa inscrita: $companyId');
    });

    _wsService.setOnCompanyUnsubscribed((companyId) {
      debugPrint('✅ [NOTIFICATION_CTRL] Empresa desinscrita: $companyId');
    });
  }

  /// Obtém userId do storage (do token JWT)
  Future<String?> _getUserId() async {
    try {
      final token = await SecureStorageService.instance.getAccessToken();
      if (token != null) {
        // Decodificar JWT para obter userId
        final parts = token.split('.');
        if (parts.length == 3) {
          final payload = parts[1];
          final decoded = _decodeBase64(payload);
          final json = jsonDecode(decoded) as Map<String, dynamic>;
          return json['sub']?.toString() ?? json['userId']?.toString();
        }
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ [NOTIFICATION_CTRL] Erro ao obter userId: $e');
      return null;
    }
  }

  /// Decodifica base64
  String _decodeBase64(String str) {
    try {
      String output = str.replaceAll('-', '+').replaceAll('_', '/');
      switch (output.length % 4) {
        case 0:
          break;
        case 2:
          output += '==';
          break;
        case 3:
          output += '=';
          break;
      }
      return String.fromCharCodes(base64Decode(output));
    } catch (e) {
      return '';
    }
  }

  /// Carrega notificações
  Future<void> loadNotifications({bool reset = false}) async {
    if (reset) {
      _currentPage = 1;
      _hasMore = true;
      _notifications.clear();
    }

    if (_loading || (_loadingMore && !reset)) {
      return;
    }

    if (reset) {
      _loading = true;
    } else {
      _loadingMore = true;
    }

    _error = null;
    notifyListeners();

    try {
      final response = await _notificationService.listNotifications(
        read: _filterRead,
        type: _filterType,
        companyId: _filterCompanyId,
        page: _currentPage,
        limit: _pageLimit,
      );

      if (response.success && response.data != null) {
        final listResponse = response.data!;

        if (reset) {
          _notifications = listResponse.notifications;
        } else {
          _notifications.addAll(listResponse.notifications);
        }

        _unreadCount = listResponse.unreadCount;
        _currentPage = listResponse.page;
        _hasMore = listResponse.page < listResponse.totalPages;
        _error = null;
      } else {
        _error = response.message ?? 'Erro ao carregar notificações';
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [NOTIFICATION_CTRL] Erro ao carregar: $e');
      debugPrint('📚 [NOTIFICATION_CTRL] StackTrace: $stackTrace');
      _error = 'Erro ao carregar notificações: ${e.toString()}';
    } finally {
      _loading = false;
      _loadingMore = false;
      notifyListeners();
    }
  }

  /// Carrega mais notificações (paginção)
  Future<void> loadMore() async {
    if (!_hasMore || _loadingMore || _loading) {
      return;
    }

    _currentPage++;
    await loadNotifications();
  }

  /// Carrega apenas não lidas
  Future<void> loadUnreadNotifications({bool reset = false}) async {
    if (reset) {
      _currentPage = 1;
      _hasMore = true;
      _notifications.clear();
    }

    if (_loading || (_loadingMore && !reset)) {
      return;
    }

    if (reset) {
      _loading = true;
    } else {
      _loadingMore = true;
    }

    _error = null;
    notifyListeners();

    try {
      final response = await _notificationService.listUnreadNotifications(
        companyId: _filterCompanyId,
        page: _currentPage,
        limit: _pageLimit,
      );

      if (response.success && response.data != null) {
        final listResponse = response.data!;

        if (reset) {
          _notifications = listResponse.notifications;
        } else {
          _notifications.addAll(listResponse.notifications);
        }

        _unreadCount = listResponse.unreadCount;
        _currentPage = listResponse.page;
        _hasMore = listResponse.page < listResponse.totalPages;
        _error = null;
      } else {
        _error = response.message ?? 'Erro ao carregar notificações não lidas';
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [NOTIFICATION_CTRL] Erro ao carregar não lidas: $e');
      debugPrint('📚 [NOTIFICATION_CTRL] StackTrace: $stackTrace');
      _error = 'Erro ao carregar notificações não lidas: ${e.toString()}';
    } finally {
      _loading = false;
      _loadingMore = false;
      notifyListeners();
    }
  }

  /// Atualiza contador de não lidas
  Future<void> refreshUnreadCount() async {
    try {
      final response = await _notificationService.getUnreadCount(
        companyId: _filterCompanyId,
      );

      if (response.success && response.data != null) {
        _unreadCount = response.data!.count;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('❌ [NOTIFICATION_CTRL] Erro ao atualizar contador: $e');
    }
  }

  /// Marca notificação como lida
  Future<bool> markAsRead(String id) async {
    try {
      final response = await _notificationService.markAsRead(id);

      if (response.success && response.data != null) {
        // Atualizar na lista local
        final index = _notifications.indexWhere((n) => n.id == id);
        if (index != -1) {
          final notification = _notifications[index];
          if (!notification.read) {
            _unreadCount = (_unreadCount - 1).clamp(0, double.infinity).toInt();
          }
          _notifications[index] = response.data!;
        }

        // Atualizar contador
        await refreshUnreadCount();
        notifyListeners();
        return true;
      } else {
        _error = response.message ?? 'Erro ao marcar como lida';
        notifyListeners();
        return false;
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [NOTIFICATION_CTRL] Erro ao marcar como lida: $e');
      debugPrint('📚 [NOTIFICATION_CTRL] StackTrace: $stackTrace');
      _error = 'Erro ao marcar como lida: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  /// Marca todas como lidas.
  ///
  /// IMPORTANTE: o backend trata `companyId` ausente como "marcar APENAS
  /// notificações pessoais (`companyId IS NULL`)". Por isso, se o usuário
  /// não escolheu filtro explícito, usamos a empresa atualmente selecionada
  /// (via [SecureStorageService]). Sem isso, ao chamar a rota o backend
  /// não persiste nada para usuários cujas notificações vêm todas da
  /// empresa, e ao recarregar elas voltam como não lidas.
  Future<bool> markAllAsRead() async {
    try {
      String? effectiveCompanyId = _filterCompanyId;
      if (effectiveCompanyId == null || effectiveCompanyId.isEmpty) {
        effectiveCompanyId =
            await SecureStorageService.instance.getCompanyId();
      }

      final response = await _notificationService.markAllAsRead(
        companyId: effectiveCompanyId,
      );

      if (response.success && response.data != null) {
        // Update otimista local
        _notifications = _notifications
            .map((n) => n.copyWith(read: true))
            .toList();

        _unreadCount = response.data!.unreadCount;
        notifyListeners();

        // Garante consistência com o backend mesmo se o WS estiver mudo:
        // recarrega a primeira página + contador canônico. Sem isso, ao
        // entrar de novo na tela / abrir o overlay, vínhamos com uma cópia
        // ainda não lida do servidor caso a chamada tivesse afetado 0
        // registros (cenário do bug original).
        unawaited(loadNotifications(reset: true));
        unawaited(refreshUnreadCount());

        return true;
      } else {
        _error = response.message ?? 'Erro ao marcar todas como lidas';
        notifyListeners();
        return false;
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [NOTIFICATION_CTRL] Erro ao marcar todas: $e');
      debugPrint('📚 [NOTIFICATION_CTRL] StackTrace: $stackTrace');
      _error = 'Erro ao marcar todas como lidas: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  /// Marca múltiplas como lidas
  Future<bool> markMultipleAsRead(List<String> ids) async {
    try {
      final response =
          await _notificationService.markMultipleAsRead(ids);

      if (response.success && response.data != null) {
        // Atualizar na lista local
        for (final id in ids) {
          final index = _notifications.indexWhere((n) => n.id == id);
          if (index != -1) {
            final notification = _notifications[index];
            if (!notification.read) {
              _unreadCount = (_unreadCount - 1).clamp(0, double.infinity).toInt();
            }
            _notifications[index] = notification.copyWith(read: true);
          }
        }

        _unreadCount = response.data!.unreadCount;
        notifyListeners();
        return true;
      } else {
        _error = response.message ?? 'Erro ao marcar múltiplas como lidas';
        notifyListeners();
        return false;
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [NOTIFICATION_CTRL] Erro ao marcar múltiplas: $e');
      debugPrint('📚 [NOTIFICATION_CTRL] StackTrace: $stackTrace');
      _error = 'Erro ao marcar múltiplas como lidas: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  /// Exclui notificação
  Future<bool> deleteNotification(String id) async {
    try {
      final response = await _notificationService.deleteNotification(id);

      if (response.success) {
        // Remover da lista local
        final index = _notifications.indexWhere((n) => n.id == id);
        if (index != -1) {
          final notification = _notifications[index];
          if (!notification.read) {
            _unreadCount = (_unreadCount - 1).clamp(0, double.infinity).toInt();
          }
          _notifications.removeAt(index);
        }

        // Atualizar contador
        await refreshUnreadCount();
        notifyListeners();
        return true;
      } else {
        _error = response.message ?? 'Erro ao excluir notificação';
        notifyListeners();
        return false;
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [NOTIFICATION_CTRL] Erro ao excluir: $e');
      debugPrint('📚 [NOTIFICATION_CTRL] StackTrace: $stackTrace');
      _error = 'Erro ao excluir notificação: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  /// Aplica filtros
  void setFilters({
    bool? read,
    String? type,
    String? companyId,
  }) {
    _filterRead = read;
    _filterType = type;
    _filterCompanyId = companyId;
    loadNotifications(reset: true);
  }

  /// Limpa filtros
  void clearFilters() {
    _filterRead = null;
    _filterType = null;
    _filterCompanyId = null;
    loadNotifications(reset: true);
  }

  /// Atualiza (refresh)
  Future<void> refresh() async {
    await loadNotifications(reset: true);
    await refreshUnreadCount();
  }

  /// Inscreve-se em empresa no WebSocket
  void subscribeCompany(String companyId) {
    _wsService.subscribeCompany(companyId);
  }

  /// Desinscreve-se de empresa no WebSocket
  void unsubscribeCompany(String companyId) {
    _wsService.unsubscribeCompany(companyId);
  }

  /// Reconecta WebSocket
  Future<void> reconnectWebSocket() async {
    await _wsService.reconnect();
  }

  /// Limpa estado
  void clear() {
    _notifications.clear();
    _unreadCount = 0;
    _error = null;
    _currentPage = 1;
    _hasMore = true;
    notifyListeners();
  }

  /// Adiciona notificações de teste (apenas para desenvolvimento)
  void addTestNotifications(List<NotificationModel> notifications) {
    _notifications.insertAll(0, notifications);
    _unreadCount += notifications.where((n) => !n.read).length;
    notifyListeners();
  }

  /// Remove notificações de teste (que começam com 'test-')
  void removeTestNotifications() {
    final testNotifications = _notifications.where((n) => n.id.startsWith('test-')).toList();
    final removedUnread = testNotifications.where((n) => !n.read).length;
    _notifications.removeWhere((n) => n.id.startsWith('test-'));
    _unreadCount = (_unreadCount - removedUnread).clamp(0, double.infinity).toInt();
    notifyListeners();
  }

  /// Dispose
  @override
  void dispose() {
    _wsService.disconnect();
    super.dispose();
  }
}

