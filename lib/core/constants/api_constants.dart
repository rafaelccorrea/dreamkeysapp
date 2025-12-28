/// Constantes da API
class ApiConstants {
  ApiConstants._();

  // Base URL - TODO: Configurar através de variáveis de ambiente
  static const String baseUrl = 'https://api.dreamkeys.com.br';
  static const String baseApiUrl = baseUrl;

  // Endpoints de Autenticação
  static const String login =
      '/auth/broker/login'; // Login específico para corretores
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

  // Endpoints de Appointments
  static const String appointments = '/appointments';
  static String appointmentById(String id) => '/appointments/$id';
  static String appointmentUpdate(String id) => '/appointments/$id';
  static String appointmentDelete(String id) => '/appointments/$id';
  static String appointmentParticipant(String appointmentId, String userId) =>
      '/appointments/$appointmentId/participants/$userId';
  static const String appointmentInvites = '/appointments/invites';
  static const String appointmentInvitesMyInvites =
      '/appointments/invites/my-invites';
  static const String appointmentInvitesPending =
      '/appointments/invites/pending';
  static String appointmentInviteById(String id) => '/appointments/invites/$id';
  static String appointmentInviteRespond(String id) =>
      '/appointments/invites/$id/respond';

  // Endpoints de Clientes
  static const String clients = '/clients';
  static String clientById(String id) => '/clients/$id';
  static String clientUpdate(String id) => '/clients/$id';
  static String clientDelete(String id) => '/clients/$id';
  static String clientDeletePermanent(String id) => '/clients/$id/permanent';
  static const String clientsStatistics = '/clients/statistics';
  static String clientTransfer(String clientId) =>
      '/clients/$clientId/transfer';
  static const String clientsUsersForTransfer = '/clients/users-for-transfer';
  static String clientPropertyAssociate(String clientId, String propertyId) =>
      '/clients/$clientId/properties/$propertyId';
  static String clientPropertyDisassociate(
    String clientId,
    String propertyId,
  ) => '/clients/$clientId/properties/$propertyId';
  static String clientProperties(String clientId) =>
      '/clients/$clientId/properties';
  static String clientByProperty(String propertyId) =>
      '/clients/properties/$propertyId';
  static String clientInteractions(String clientId) =>
      '/clients/$clientId/interactions';
  static String clientInteraction(String clientId, String interactionId) =>
      '/clients/$clientId/interactions/$interactionId';
  static const String clientsBulkImport = '/clients/bulk-import';
  static const String clientsImportJobs = '/clients/import-jobs';
  static String clientsImportJob(String jobId) => '/clients/import-jobs/$jobId';
  static String clientsImportJobErrors(String jobId) =>
      '/clients/import-jobs/$jobId/errors';
  static const String clientsExport = '/clients/export';
  static const String clientsExportBulk = '/clients/export-bulk';

  // Endpoints de Notificações
  static const String notifications = '/notifications';
  static String notificationsUnreadList([int? page, int? limit]) {
    final params = <String>[];
    if (page != null) params.add('page=$page');
    if (limit != null) params.add('limit=$limit');
    return '/notifications/unread${params.isNotEmpty ? '?${params.join('&')}' : ''}';
  }

  static const String notificationsUnreadCount = '/notifications/unread/count';
  static const String notificationsUnreadCountByCompany =
      '/notifications/unread/count/by-company';
  static String notificationById(String id) => '/notifications/$id';
  static String markNotificationRead(String id) => '/notifications/$id/read';
  static String markNotificationUnread(String id) =>
      '/notifications/$id/unread';
  static const String markNotificationsReadBulk = '/notifications/read/bulk';
  static const String markNotificationsReadAll = '/notifications/read/all';

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
