import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        debugPrint,
        defaultTargetPlatform,
        kDebugMode,
        kIsWeb,
        kReleaseMode;
import 'package:flutter/services.dart' show rootBundle;

import 'dev_network_config.dart';

/// Constantes da API
class ApiConstants {
  ApiConstants._();

  static String _baseUrl = 'http://127.0.0.1:3000';
  static bool _didInit = false;

  /// Chame no `main()` antes de `runApp` (já configurado em [main.dart]).
  ///
  /// Prioridade:
  /// 1. `--dart-define=API_BASE_URL=https://...` (URL completa, máxima prioridade)
  /// 2. **Build de release** (`kReleaseMode`) — força [DevNetworkConfig.productionApiBaseUrl],
  ///    ignorando `api_target.txt`. Garante que `.aab` publicado nunca aponte para `lan`.
  /// 3. `assets/config/api_target.txt` — primeira linha útil: `production` →
  ///    [DevNetworkConfig.productionApiBaseUrl]; `lan` → resolve IP local (abaixo)
  /// 4. Modo **lan**: emulador Android `10.0.2.2`, físico + `dev_lan_host.txt`, etc.
  ///
  /// Para API no PC, mude `api_target.txt` para `lan` (apenas em debug/profile).
  static Future<void> ensureInitialized() async {
    if (_didInit) return;

    const fromEnvFull = String.fromEnvironment('API_BASE_URL');
    if (fromEnvFull.isNotEmpty) {
      _baseUrl = _normalizeBaseUrl(fromEnvFull);
      _didInit = true;
      debugPrint('📡 [API] API_BASE_URL (dart-define) → $_baseUrl');
      return;
    }

    // Trava de segurança: builds de release SEMPRE usam produção, ignorando
    // `api_target.txt`. Evita que um `.aab` publicado por engano aponte para
    // `127.0.0.1`/LAN só porque o asset ficou em `lan` na máquina do dev.
    if (kReleaseMode) {
      _baseUrl = _normalizeBaseUrl(DevNetworkConfig.productionApiBaseUrl);
      _didInit = true;
      debugPrint('📡 [API] release build → produção fixa → $_baseUrl');
      return;
    }

    final target = await _apiTargetFromAsset();
    if (target == 'production') {
      _baseUrl = _normalizeBaseUrl(DevNetworkConfig.productionApiBaseUrl);
      _didInit = true;
      debugPrint('📡 [API] api_target.txt → production → $_baseUrl');
      return;
    }

    const port = String.fromEnvironment('API_PORT', defaultValue: '3000');
    const devLanHost = String.fromEnvironment('DEV_LAN_HOST');

    if (kIsWeb) {
      _baseUrl = 'http://127.0.0.1:$port';
      _didInit = true;
      return;
    }

    final deviceInfo = DeviceInfoPlugin();

    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = await deviceInfo.androidInfo;
      if (android.isPhysicalDevice) {
        final host = await _resolveAndroidPhysicalHost(
          devLanHost: devLanHost,
          port: port,
        );
        _baseUrl = 'http://$host:$port';
        debugPrint('📡 [API] Android físico → $_baseUrl');
      } else {
        _baseUrl = 'http://10.0.2.2:$port';
        debugPrint('📡 [API] Android emulador → $_baseUrl');
      }
      _didInit = true;
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = await deviceInfo.iosInfo;
      if (ios.isPhysicalDevice) {
        final host = await _resolveIosPhysicalHost(devLanHost: devLanHost);
        _baseUrl = 'http://$host:$port';
        debugPrint('📡 [API] iOS físico → $_baseUrl');
      } else {
        _baseUrl = 'http://127.0.0.1:$port';
        debugPrint('📡 [API] iOS Simulator → $_baseUrl');
      }
      _didInit = true;
      return;
    }

    _baseUrl = 'http://127.0.0.1:$port';
    _didInit = true;
    debugPrint('📡 [API] Desktop/outro → $_baseUrl');
  }

  static Future<String> _resolveAndroidPhysicalHost({
    required String devLanHost,
    required String port,
  }) async {
    if (devLanHost.isNotEmpty) return devLanHost;
    if (DevNetworkConfig.pcLanIPv4.isNotEmpty) {
      return DevNetworkConfig.pcLanIPv4;
    }
    final fromAsset = await _devLanHostFromAsset();
    if (fromAsset != null) {
      debugPrint('📡 [API] host de assets/config/dev_lan_host.txt → $fromAsset');
      return fromAsset;
    }
    if (kDebugMode) {
      debugPrint(
        '📡 [API] Android físico (debug): 127.0.0.1 — USB: o Gradle tenta '
        '`adb reverse tcp:$port tcp:$port`; se falhar, rode manualmente. '
        'Wi‑Fi: edite assets/config/dev_lan_host.txt ou DEV_LAN_HOST / pcLanIPv4.',
      );
      return '127.0.0.1';
    }
    throw StateError(
      'Android físico em release: defina --dart-define=API_BASE_URL=... ou '
      'DEV_LAN_HOST / DevNetworkConfig.pcLanIPv4 / dev_lan_host.txt.',
    );
  }

  static Future<String> _resolveIosPhysicalHost({
    required String devLanHost,
  }) async {
    if (devLanHost.isNotEmpty) return devLanHost;
    if (DevNetworkConfig.pcLanIPv4.isNotEmpty) {
      return DevNetworkConfig.pcLanIPv4;
    }
    final fromAsset = await _devLanHostFromAsset();
    if (fromAsset != null) return fromAsset;
    throw StateError(
      'iOS físico: defina assets/config/dev_lan_host.txt, '
      'DevNetworkConfig.pcLanIPv4 ou --dart-define=DEV_LAN_HOST= '
      '(IPv4 do Mac na mesma Wi‑Fi).',
    );
  }

  static final _ipv4 = RegExp(
    r'^(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)$',
  );

  static Future<String?> _devLanHostFromAsset() async {
    try {
      final raw = await rootBundle.loadString('assets/config/dev_lan_host.txt');
      for (final line in raw.split(RegExp(r'\r?\n'))) {
        final t = line.trim();
        if (t.isEmpty || t.startsWith('#')) continue;
        if (_ipv4.hasMatch(t)) return t;
      }
    } catch (_) {}
    return null;
  }

  static String _normalizeBaseUrl(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  /// `production` — API pública; `lan` — mesmo PC/rede. Sem linha válida ou sem asset → `production`.
  static Future<String> _apiTargetFromAsset() async {
    try {
      final raw = await rootBundle.loadString('assets/config/api_target.txt');
      for (final line in raw.split(RegExp(r'\r?\n'))) {
        final t = line.trim();
        if (t.isEmpty || t.startsWith('#')) continue;
        final lower = t.toLowerCase();
        if (lower == 'production' || lower == 'lan') return lower;
      }
    } catch (_) {}
    return 'production';
  }

  static String get baseUrl {
    assert(
      _didInit,
      'Chame ApiConstants.ensureInitialized() no main() antes de usar a API.',
    );
    return _baseUrl;
  }

  /// Alias de [baseUrl] (sem path) — uso em uploads e URIs absolutas.
  static String get baseApiUrl => baseUrl;

  // Endpoints de Autenticação
  /// App móvel tenta primeiro esta rota (corretores); [standardLogin] faz fallback (ex.: MASTER).
  static const String login = '/auth/broker/login';
  /// Mesma rota que o imobx-front (`POST /auth/login`) — administradores / master.
  static const String standardLogin = '/auth/login';
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
  static String teamMembers(String teamId) => '/teams/$teamId/members';

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

  // Endpoints de Notificações (paridade com imobx/Nest: hífens, não /unread/count)
  static const String notifications = '/notifications';
  /// Todas as empresas do utilizador — necessário no mobile quando não há X-Company-ID
  /// ou para ver o mesmo universo que o web para utilizadores com várias empresas.
  static const String notificationsAllCompanies = '/notifications/all-companies';
  static const String notificationsUnreadList = '/notifications/unread/list';
  static const String notificationsUnreadCount = '/notifications/unread-count';
  static const String notificationsUnreadCountByCompany =
      '/notifications/unread-count-by-company';
  static String notificationById(String id) => '/notifications/$id';
  static String markNotificationRead(String id) => '/notifications/$id/read';
  static String markNotificationUnread(String id) =>
      '/notifications/$id/unread';
  static const String markNotificationsReadBulk = '/notifications/read/bulk';
  static const String markNotificationsReadAll = '/notifications/read/all';
  /// Registo do token FCM do app (POST / DELETE com body `{ token }`).
  static const String notificationsMobileDevices = '/notifications/mobile-devices';

  // Kanban — analytics por tarefa (ex.: módulo `kanban_management` + `kanban:view_analytics`)
  static String kanbanAnalyticsTaskMetrics(String taskId) =>
      '/kanban/analytics/tasks/$taskId/metrics';

  /// Jornada do lead (`GET` — permissão `kanban:view`).
  static String kanbanTaskJourney(String taskId) =>
      '/kanban/tasks/$taskId/journey';

  /// Anexos diretos no card (`GET`/`POST`/`DELETE` — ver guards no Nest).
  static String kanbanTaskAttachments(String taskId) =>
      '/kanban/tasks/$taskId/attachments';

  // Endpoints de Kanban
  static const String kanbanMyBoards = '/kanban/my-boards';
  static String kanbanBoard(String teamId) => '/kanban/board/$teamId';
  static const String kanbanColumns = '/kanban/columns';
  static String kanbanColumnById(String id) => '/kanban/columns/$id';
  /// Colunas resumidas (`projectId` em query) — alinhado a `kanbanValidationsApi.getSimpleColumns`.
  static String kanbanColumnsSimple(String teamId) =>
      '/kanban/columns/$teamId/simple';

  /// `GET /kanban/columns/:columnId/tasks?teamId&projectId&page&limit&search`
  /// Usado pelo "Carregar mais" cards dentro de uma coluna do board.
  static String kanbanColumnTasks(String columnId) =>
      '/kanban/columns/$columnId/tasks';
  static String kanbanColumnsReorder(String teamId) =>
      '/kanban/columns/reorder/$teamId';
  static const String kanbanTasks = '/kanban/tasks';
  static String kanbanTaskById(String id) => '/kanban/tasks/$id';
  static String kanbanTaskMarkResult(String taskId) =>
      '/kanban/tasks/$taskId/mark-result';
  static String kanbanTaskTransfer(String taskId) =>
      '/kanban/tasks/$taskId/transfer';
  static const String kanbanTasksMove = '/kanban/tasks/move';
  static String kanbanTaskHistory(String id) => '/kanban/tasks/$id/history';
  static String kanbanTaskComments(String taskId) =>
      '/kanban/tasks/$taskId/comments';
  static String kanbanTaskComment(String taskId, String commentId) =>
      '/kanban/tasks/$taskId/comments/$commentId';
  static String kanbanTags(String teamId) => '/kanban/tags/$teamId';

  // Endpoints de Projetos Kanban
  static const String kanbanProjects = '/kanban/projects';
  static String kanbanProjectById(String id) => '/kanban/projects/$id';
  /// Equipes do seletor de funis (`ProjectSelect` / `GET /kanban/teams`).
  static const String kanbanTeams = '/kanban/teams';
  /// Projetos de várias equipes: `GET ...?teamIds=uuid1,uuid2`
  static const String kanbanProjectsByTeams = '/kanban/projects/teams';
  static const String kanbanProjectsWithoutTeam = '/kanban/projects/without-team';
  static String kanbanProjectsByTeam(String teamId) =>
      '/kanban/projects/team/$teamId';
  static const String kanbanProjectsPersonal = '/kanban/projects/team/personal';
  static const String kanbanProjectsFiltered = '/kanban/projects/filtered';
  /// Todos os funis da empresa — mesmo contrato do modal web de transferência.
  static const String kanbanProjectsCompany = '/kanban/projects/company';
  static String kanbanProjectFinalize(String id) =>
      '/kanban/projects/$id/finalize';
  static String kanbanProjectsTeamHistory(String teamId) =>
      '/kanban/projects/team/$teamId/history';
  static String kanbanProjectHistory(String id) =>
      '/kanban/projects/$id/history';
  static String kanbanProjectMembers(String projectId) =>
      '/kanban/projects/$projectId/members';
  static String kanbanProjectClients(String projectId) =>
      '/kanban/projects/$projectId/clients';
  static String kanbanProjectProperties(String projectId) =>
      '/kanban/projects/$projectId/properties';
  static String kanbanTaskInvolvedUsers(String taskId) =>
      '/kanban/tasks/$taskId/involved-users';

  // Endpoints de Documentos
  static const String documents = '/documents';
  static String documentById(String id) => '/documents/$id';
  static String documentUpdate(String id) => '/documents/$id';
  static const String documentsUpload = '/documents/upload';
  static String documentApprove(String id) => '/documents/$id/approve';
  static String documentsByClient(String clientId) =>
      '/documents/client/$clientId';
  static String documentsByProperty(String propertyId) =>
      '/documents/property/$propertyId';
  static String documentsExpiring(int days) => '/documents/expiring/$days';

  // Endpoints de Assinaturas
  static String documentSignatures(String documentId) =>
      '/documents/$documentId/signatures';
  static String documentSignaturesBatch(String documentId) =>
      '/documents/$documentId/signatures/batch';
  static String documentSignaturesStats(String documentId) =>
      '/documents/$documentId/signatures/stats';
  static String documentSignatureById(String documentId, String signatureId) =>
      '/documents/$documentId/signatures/$signatureId';
  static String documentSignatureSendEmail(
    String documentId,
    String signatureId,
  ) => '/documents/$documentId/signatures/$signatureId/send-email';
  static String documentSignatureResendEmail(
    String documentId,
    String signatureId,
  ) => '/documents/$documentId/signatures/$signatureId/resend-email';
  static String documentSignatureViewed(
    String documentId,
    String signatureId,
  ) => '/documents/$documentId/signatures/$signatureId/viewed';
  static String documentSignatureSigned(
    String documentId,
    String signatureId,
  ) => '/documents/$documentId/signatures/$signatureId/signed';
  static String documentSignatureRejected(
    String documentId,
    String signatureId,
  ) => '/documents/$documentId/signatures/$signatureId/rejected';
  static String signaturesByClient(String clientId) =>
      '/signatures/client/$clientId';
  static const String signaturesPending = '/signatures/pending';
  static const String signatures = '/signatures';
  static const String publicSignature = '/public/signatures';
  static String publicSignatureById(String signatureId) =>
      '/public/signatures/$signatureId';

  // Endpoints de Upload Tokens
  static const String uploadTokens = '/documents/upload-tokens';
  static String uploadTokenById(String tokenId) =>
      '/documents/upload-tokens/$tokenId';
  static String uploadTokenSendEmail(String tokenId) =>
      '/documents/upload-tokens/$tokenId/send-email';
  static String uploadTokenRevoke(String tokenId) =>
      '/documents/upload-tokens/$tokenId/revoke';
  static const String publicUploadDocuments = '/public/upload-documents';
  static String publicUploadDocumentsInfo(String token) =>
      '/public/upload-documents/$token/info';
  static String publicUploadDocumentsValidate(String token) =>
      '/public/upload-documents/$token/validate';
  static String publicUploadDocumentsUpload(String token) =>
      '/public/upload-documents/$token/upload';
  static String publicUploadDocumentsUploadMultiple(String token) =>
      '/public/upload-documents/$token/upload-multiple';

  // Endpoints de Chat
  static const String chatRooms = '/chat/rooms';
  static String chatRoomById(String id) => '/chat/rooms/$id';
  static String chatRoomUploadImage(String id) =>
      '/chat/rooms/$id/upload-image';
  static String chatRoomParticipants(String id) =>
      '/chat/rooms/$id/participants';
  static String chatRoomParticipantsRemove(String id) =>
      '/chat/rooms/$id/participants/remove';
  static String chatRoomPromoteAdmin(String id) =>
      '/chat/rooms/$id/promote-admin';
  static String chatRoomRemoveAdmin(String id) =>
      '/chat/rooms/$id/remove-admin';
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

  // Endpoints de Vistorias
  static const String inspections = '/inspection';
  static String inspectionById(String id) => '/inspection/$id';
  static String inspectionUpdate(String id) => '/inspection/$id';
  static String inspectionDelete(String id) => '/inspection/$id';
  static String inspectionByProperty(String propertyId) =>
      '/inspection/property/$propertyId';
  static String inspectionByInspector(String inspectorId) =>
      '/inspection/vistoriador/$inspectorId';
  static String inspectionUploadPhoto(String id) =>
      '/inspection/$id/upload-foto';
  static String inspectionDeletePhoto(String id, String photoUrl) =>
      '/inspection/$id/foto/${Uri.encodeComponent(photoUrl)}';
  static String inspectionRequestApproval(String id) =>
      '/inspection/$id/request-approval';
  static String inspectionHistory(String id) => '/inspection/$id/history';
  static String inspectionHistoryEntry(String id, String historyId) =>
      '/inspection/$id/history/$historyId';

  // Endpoints de Aprovações Financeiras de Vistorias
  static const String inspectionApprovals = '/inspection-approval';
  static String inspectionApprovalById(String id) => '/inspection-approval/$id';
  static String inspectionApprovalApprove(String id) =>
      '/inspection-approval/$id/approve';

  // Endpoints de Chaves
  static const String keys = '/keys';
  static String keyById(String id) => '/keys/$id';
  static String keyUpdate(String id) => '/keys/$id';
  static String keyDelete(String id) => '/keys/$id';
  static const String keyStatistics = '/keys/statistics';
  static String keyStatus(String propertyId) =>
      '/keys/status?propertyId=$propertyId';
  static String keysByProperty(String propertyId) =>
      '/keys?propertyId=$propertyId';

  // Endpoints de Controle de Chaves (Checkout/Return)
  static const String keyCheckout = '/keys/checkout';
  static String keyReturn(String keyControlId) => '/keys/return/$keyControlId';
  static const String keyControlsAll = '/keys/controls/all';
  static const String keyControlsOverdue = '/keys/controls/overdue';
  static const String keyControlsUser = '/keys/controls/user';
  static String keyControlById(String id) => '/keys/controls/$id';

  // Endpoints de Histórico de Chaves
  static String keyHistoryByKey(String keyId) => '/key-history/key/$keyId';
  static String keyHistoryByUser(String userId) => '/key-history/user/$userId';
  static const String keyHistoryMyHistory = '/key-history/my-history';
  static const String keyHistoryStatistics = '/key-history/statistics';

  // Endpoints de Despesas de Propriedades
  static String propertyExpenses(String propertyId) =>
      '/properties/$propertyId/expenses';
  static String propertyExpensesSummary(String propertyId) =>
      '/properties/$propertyId/expenses/summary';
  static String propertyExpenseById(String propertyId, String expenseId) =>
      '/properties/$propertyId/expenses/$expenseId';
  static String propertyExpenseMarkAsPaid(
    String propertyId,
    String expenseId,
  ) => '/properties/$propertyId/expenses/$expenseId/mark-as-paid';

  // Endpoints de Checklists
  static const String saleChecklists = '/sale-checklists';
  static String saleChecklistById(String id) => '/sale-checklists/$id';
  static String saleChecklistsByProperty(String propertyId) =>
      '/sale-checklists?propertyId=$propertyId';

  // Endpoints de Anotações (módulo `notes` + permissões `note:*`)
  static const String notes = '/notes';
  static const String notesStats = '/notes/stats';
  static const String notesReminders = '/notes/reminders';
  static String noteById(String id) => '/notes/$id';
  static String noteTogglePin(String id) => '/notes/$id/toggle-pin';
  static String noteArchive(String id) => '/notes/$id/archive';
  static String noteRestore(String id) => '/notes/$id/restore';

  // Endpoints de utilizadores (admin — módulo `user_management`)
  static const String adminUsers = '/admin/users';

  // Endpoints de Subscriptions (admin/master — ver `RolesGuard` no Nest)
  static const String subscriptionsMyActive =
      '/subscriptions/my-active-subscription';
  static const String subscriptionsMyList = '/subscriptions/my-subscriptions';

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
