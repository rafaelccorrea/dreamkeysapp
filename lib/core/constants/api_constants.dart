/// Constantes da API
class ApiConstants {
  ApiConstants._();

  // Base URL - TODO: Configurar através de variáveis de ambiente
  static const String baseUrl = 'https://api.dreamkeys.com.br';
  static const String baseApiUrl = baseUrl;

  // Endpoints de Autenticação
  static const String login = '/auth/login';
  static const String logout = '/auth/logout';
  static const String refreshToken = '/auth/refresh';
  static const String forgotPassword = '/auth/forgot-password';
  static const String resetPassword = '/auth/reset-password';
  static const String verify2FA = '/auth/verify-2fa';
  static const String check2FA = '/auth/check-2fa';
  static const String profile = '/auth/profile';
  static const String changePassword = '/auth/change-password';
  static const String avatar = '/auth/avatar';

  // Endpoints de Dashboard
  static const String dashboardUser = '/dashboard/user';

  // Endpoints de Companies
  static const String companies = '/companies';
  static const String companyById = '/companies'; // /companies/:id

  // Endpoints de Permissions
  static const String myPermissions = '/permissions/my-permissions';

  // Endpoints de Subscriptions
  static const String checkSubscriptionAccess = '/subscriptions/check-access';

  // Endpoints de Configurações
  static const String settings = '/settings';

  // Endpoints de Notificações
  static const String notifications = '/notifications';
  static const String notificationsUnreadList = '/notifications/unread/list';
  static const String notificationsUnreadCount = '/notifications/unread-count';
  static const String notificationsUnreadCountByCompany = '/notifications/unread-count-by-company';
  static String notificationById(String id) => '/notifications/$id';
  static String markNotificationRead(String id) => '/notifications/$id/read';
  static String markNotificationUnread(String id) => '/notifications/$id/unread';
  static const String markNotificationsReadBulk = '/notifications/read/bulk';
  static const String markNotificationsReadAll = '/notifications/read/all';

  // WebSocket
  static Uri getWebSocketUri({String? token}) {
    // Parse da URL base
    final baseUri = Uri.parse(baseUrl);
    
    // Determinar o scheme correto (wss para https, ws para http)
    final scheme = baseUri.scheme == 'https' ? 'wss' : 'ws';
    
    // Construir URI do WebSocket
    final uri = Uri(
      scheme: scheme,
      host: baseUri.host,
      port: baseUri.port == 443 || baseUri.port == 80 ? null : baseUri.port,
      path: '/notifications',
      queryParameters: token != null && token.isNotEmpty 
          ? {'token': token} 
          : null,
    );
    
    return uri;
  }
  
  // Método de compatibilidade que retorna String
  static String getWebSocketUrl({String? token}) {
    return getWebSocketUri(token: token).toString();
  }

  // Headers
  static const String contentTypeHeader = 'Content-Type';
  static const String authorizationHeader = 'Authorization';
  static const String acceptHeader = 'Accept';
  static const String contentTypeJson = 'application/json';
  static const String bearerPrefix = 'Bearer';

  // Timeouts
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration sendTimeout = Duration(seconds: 30);
}
