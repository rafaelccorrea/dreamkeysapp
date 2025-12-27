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
