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

  // Endpoints de Teams
  static const String teams = '/teams';
  static String teamById(String id) => '/teams/$id';

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

  // Endpoints de Matches
  static const String matches = '/matches';
  static String matchById(String id) => '/matches/$id';
  static String matchAccept(String id) => '/matches/$id/accept';
  static String matchIgnore(String id) => '/matches/$id/ignore';
  static String matchView(String id) => '/matches/$id/view';
  static String matchStatus(String id) => '/matches/$id/status';

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

  // Endpoints de Kanban
  static String kanbanBoard(String teamId) => '/kanban/board/$teamId';
  static const String kanbanColumns = '/kanban/columns';
  static String kanbanColumnById(String id) => '/kanban/columns/$id';
  static String kanbanColumnsReorder(String teamId) => '/kanban/columns/reorder/$teamId';
  static const String kanbanTasks = '/kanban/tasks';
  static String kanbanTaskById(String id) => '/kanban/tasks/$id';
  static const String kanbanTasksMove = '/kanban/tasks/move';
  static String kanbanTaskHistory(String id) => '/kanban/tasks/$id/history';
  static String kanbanTaskComments(String taskId) => '/kanban/tasks/$taskId/comments';
  static String kanbanTaskComment(String taskId, String commentId) => '/kanban/tasks/$taskId/comments/$commentId';
  static String kanbanTags(String teamId) => '/kanban/tags/$teamId';
  
  // Endpoints de Projetos Kanban
  static const String kanbanProjects = '/kanban/projects';
  static String kanbanProjectById(String id) => '/kanban/projects/$id';
  static String kanbanProjectsByTeam(String teamId) => '/kanban/projects/team/$teamId';
  static const String kanbanProjectsPersonal = '/kanban/projects/team/personal';
  static const String kanbanProjectsFiltered = '/kanban/projects/filtered';
  static String kanbanProjectFinalize(String id) => '/kanban/projects/$id/finalize';
  static String kanbanProjectsTeamHistory(String teamId) => '/kanban/projects/team/$teamId/history';
  static String kanbanProjectHistory(String id) => '/kanban/projects/$id/history';

  // Endpoints de Documentos
  static const String documents = '/documents';
  static String documentById(String id) => '/documents/$id';
  static String documentUpdate(String id) => '/documents/$id';
  static const String documentsUpload = '/documents/upload';
  static String documentApprove(String id) => '/documents/$id/approve';
  static String documentsByClient(String clientId) => '/documents/client/$clientId';
  static String documentsByProperty(String propertyId) => '/documents/property/$propertyId';
  static String documentsExpiring(int days) => '/documents/expiring/$days';
  
  // Endpoints de Assinaturas
  static String documentSignatures(String documentId) => '/documents/$documentId/signatures';
  static String documentSignaturesBatch(String documentId) => '/documents/$documentId/signatures/batch';
  static String documentSignaturesStats(String documentId) => '/documents/$documentId/signatures/stats';
  static String documentSignatureById(String documentId, String signatureId) => '/documents/$documentId/signatures/$signatureId';
  static String documentSignatureSendEmail(String documentId, String signatureId) => '/documents/$documentId/signatures/$signatureId/send-email';
  static String documentSignatureResendEmail(String documentId, String signatureId) => '/documents/$documentId/signatures/$signatureId/resend-email';
  static String documentSignatureViewed(String documentId, String signatureId) => '/documents/$documentId/signatures/$signatureId/viewed';
  static String documentSignatureSigned(String documentId, String signatureId) => '/documents/$documentId/signatures/$signatureId/signed';
  static String documentSignatureRejected(String documentId, String signatureId) => '/documents/$documentId/signatures/$signatureId/rejected';
  static String signaturesByClient(String clientId) => '/signatures/client/$clientId';
  static const String signaturesPending = '/signatures/pending';
  static const String signatures = '/signatures';
  static const String publicSignature = '/public/signatures';
  static String publicSignatureById(String signatureId) => '/public/signatures/$signatureId';
  
  // Endpoints de Upload Tokens
  static const String uploadTokens = '/documents/upload-tokens';
  static String uploadTokenById(String tokenId) => '/documents/upload-tokens/$tokenId';
  static String uploadTokenSendEmail(String tokenId) => '/documents/upload-tokens/$tokenId/send-email';
  static String uploadTokenRevoke(String tokenId) => '/documents/upload-tokens/$tokenId/revoke';
  static const String publicUploadDocuments = '/public/upload-documents';
  static String publicUploadDocumentsInfo(String token) => '/public/upload-documents/$token/info';
  static String publicUploadDocumentsValidate(String token) => '/public/upload-documents/$token/validate';
  static String publicUploadDocumentsUpload(String token) => '/public/upload-documents/$token/upload';
  static String publicUploadDocumentsUploadMultiple(String token) => '/public/upload-documents/$token/upload-multiple';

  // Endpoints de Chat
  static const String chatRooms = '/chat/rooms';
  static String chatRoomById(String id) => '/chat/rooms/$id';
  static String chatRoomUploadImage(String id) => '/chat/rooms/$id/upload-image';
  static String chatRoomParticipants(String id) => '/chat/rooms/$id/participants';
  static String chatRoomParticipantsRemove(String id) => '/chat/rooms/$id/participants/remove';
  static String chatRoomPromoteAdmin(String id) => '/chat/rooms/$id/promote-admin';
  static String chatRoomRemoveAdmin(String id) => '/chat/rooms/$id/remove-admin';
  static String chatRoomArchive(String id) => '/chat/rooms/$id/archive';
  static String chatRoomUnarchive(String id) => '/chat/rooms/$id/unarchive';
  static String chatRoomLeave(String id) => '/chat/rooms/$id/leave';
  static String chatRoomRead(String id) => '/chat/rooms/$id/read';
  static String chatRoomMessages(String id, {int? limit, int? offset}) {
    final params = <String>[];
    if (limit != null) params.add('limit=$limit');
    if (offset != null) params.add('offset=$offset');
    return '/chat/rooms/$id/messages${params.isNotEmpty ? '?${params.join('&')}' : ''}';
  }
  static String chatRoomHistory(String id) => '/chat/rooms/$id/history';
  static const String chatMessages = '/chat/messages';
  static const String chatMessagesEdit = '/chat/messages/edit';
  static const String chatMessagesDelete = '/chat/messages/delete';
  static const String chatCompanyUsers = '/chat/company/users';

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
