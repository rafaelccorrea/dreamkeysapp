import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/secure_storage_service.dart';
import '../core/finance_api_client.dart';
import '../core/finance_config.dart';
import '../core/finance_deep_link.dart';
import '../core/finance_me.dart';
import '../core/finance_visibility.dart';

/// Espera da reconexão do socket: `min(2 s × 2^tentativas, 60 s)`
/// (`financeNotificationsSocket.ts:32-34`). Pura (testada).
Duration financeSocketBackoff(int attempts) => Duration(
  milliseconds: math.min(2000 * math.pow(2, attempts).toInt(), 60000),
);

/// Origem do socket: a base da API sem o caminho (`/api/v1`).
String financeSocketOrigin(String baseUrl) {
  final u = Uri.parse(baseUrl);
  return u.hasPort && u.port != 80 && u.port != 443
      ? '${u.scheme}://${u.host}:${u.port}'
      : '${u.scheme}://${u.host}';
}

/// Sino do Financeiro — REST + Socket.IO + polling de segurança (60 s com o
/// app em primeiro plano), como o web (`useNotifications.ts:859-929`).
/// O sino NÃO pede PIN (rotas sem PIN no back). Só roda com o módulo
/// `financial_management` na empresa.
class FinanceNotificationsController extends ChangeNotifier
    with WidgetsBindingObserver {
  FinanceNotificationsController._();

  static final FinanceNotificationsController instance =
      FinanceNotificationsController._();

  final FinanceApiClient _client = FinanceApiClient.instance;

  List<FinanceNotification> _items = const [];
  final Set<String> _markedRead = {};
  bool _started = false;
  bool _loading = false;
  bool _foreground = true;
  String? _companyId;
  FinanceMe? _me;

  io.Socket? _socket;
  bool _connecting = false;
  int _attempts = 0;
  Timer? _reconnect;
  Timer? _poll;
  Timer? _pushDebounce;

  /// Incrementa a cada aviso do socket — telas (Meu Financeiro) escutam
  /// para atualizar.
  final ValueNotifier<int> pushTick = ValueNotifier(0);

  List<FinanceNotification> get items => _items;
  int get unread => _items.where((n) => !n.read).length;
  bool get loading => _loading;

  /// Mostrar o sino? (`NotificationCenter.tsx:1006-1010`).
  bool get visible =>
      (_me?.podeVerSino ?? false) ||
      (_me?.receiveNotifications ?? false) ||
      _items.isNotEmpty;

  FinanceMe? get me => _me;

  bool get _hasModule =>
      companyHasFinanceModule(
        ModuleAccessService.instance.selectedCompany?.availableModules,
      ) ==
      true;

  /// Liga (idempotente). Chamado pelo botão do sino.
  void start() {
    if (_started) {
      unawaited(refresh());
      return;
    }
    if (!_hasModule) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadMe());
    unawaited(refresh());
    unawaited(_connect());
    _poll = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_foreground) unawaited(refresh());
    });
  }

  /// Desliga tudo (logout).
  void stop() {
    if (_started) WidgetsBinding.instance.removeObserver(this);
    _started = false;
    _poll?.cancel();
    _reconnect?.cancel();
    _pushDebounce?.cancel();
    _disposeSocket();
    _items = const [];
    _markedRead.clear();
    _me = null;
    _companyId = null;
    _attempts = 0;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && _started) {
      unawaited(refresh());
      if (_socket == null && !_connecting) unawaited(_connect());
    }
  }

  Future<void> _loadMe() async {
    final r = await FinanceMeService.instance.load();
    if (r.success) {
      _me = r.data;
      notifyListeners();
    }
  }

  /// GET /notifications (lista única, não lidas primeiro, até 50).
  Future<void> refresh() async {
    if (!_started) return;
    final company = await SecureStorageService.instance.getCompanyId();
    if (company != _companyId) {
      // Troca de empresa: zera o "já marquei" e reconecta a sala.
      _companyId = company;
      _markedRead.clear();
      _items = const [];
      if (!_hasModule) {
        _disposeSocket();
        notifyListeners();
        return;
      }
      unawaited(_loadMe());
    }
    _loading = true;
    final res = await _client.get<dynamic>('/notifications');
    _loading = false;
    if (res.success && res.data is List) {
      final list = (res.data as List)
          .whereType<Map>()
          .map((m) => FinanceNotification.fromJson(
                m.map((k, v) => MapEntry(k.toString(), v)),
              ))
          .where((n) => n.id.isNotEmpty)
          .map((n) => _markedRead.contains(n.id) ? n.copyRead() : n)
          .toList();
      _items = list;
    }
    notifyListeners();
  }

  Future<void> markRead(String id) async {
    final i = _items.indexWhere((n) => n.id == id);
    if (i < 0 || _items[i].read) return;
    _markedRead.add(id);
    _items = [..._items]..[i] = _items[i].copyRead();
    notifyListeners();
    await _client.patch<dynamic>(
      '/notifications/${Uri.encodeComponent(id)}/read',
      body: const <String, dynamic>{},
    );
  }

  Future<void> markAllRead() async {
    _markedRead.addAll(_items.map((n) => n.id));
    _items = _items.map((n) => n.read ? n : n.copyRead()).toList();
    notifyListeners();
    await _client.post<dynamic>(
      '/notifications/mark-all-read',
      body: const <String, dynamic>{},
    );
  }

  // ─── Socket ─────────────────────────────────────────────────────────────

  Future<void> _connect() async {
    if (!_started || _connecting || _socket != null) return;
    _connecting = true;
    try {
      final t = await _client.post<Map<String, dynamic>>(
        '/notifications/socket-ticket',
        body: const <String, dynamic>{},
      );
      final ticket = t.data?['ticket']?.toString();
      if (!t.success || ticket == null || ticket.isEmpty) {
        _scheduleReconnect();
        return;
      }
      final path = t.data?['path']?.toString() ?? '/finance-socket';
      final s = io.io(
        financeSocketOrigin(FinanceConfig.baseUrl),
        io.OptionBuilder()
            .setPath(path)
            .setTransports(['websocket'])
            .setAuth({'ticket': ticket})
            .disableReconnection()
            .disableAutoConnect()
            .enableForceNew()
            .build(),
      );
      _socket = s;
      s.onConnect((_) => _attempts = 0);
      s.on('finance:notification', (_) => _onPush());
      s.on('finance:unauthorized', (_) => _dropAndRetry());
      s.onDisconnect((_) => _dropAndRetry());
      s.onConnectError((_) => _dropAndRetry());
      s.connect();
    } catch (e) {
      debugPrint('⚠️ [FINANCE_SOCKET] $e');
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void _onPush() {
    _pushDebounce?.cancel();
    _pushDebounce = Timer(const Duration(milliseconds: 800), () {
      unawaited(refresh());
      pushTick.value++;
    });
  }

  void _dropAndRetry() {
    _disposeSocket();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_started) return;
    _reconnect?.cancel();
    final wait = financeSocketBackoff(_attempts);
    _attempts++;
    _reconnect = Timer(wait, () {
      if (_foreground) unawaited(_connect());
    });
  }

  void _disposeSocket() {
    final s = _socket;
    _socket = null;
    if (s == null) return;
    try {
      s.clearListeners();
      s.dispose();
    } catch (_) {}
  }
}
