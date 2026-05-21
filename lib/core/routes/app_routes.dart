import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';

import '../navigation/adaptive_page_route.dart';
import '../theme/app_theme.dart';
import '../../features/auth/login/pages/login_page.dart';
import '../../features/auth/forgot_password/pages/forgot_password_page.dart';
import '../../features/auth/forgot_password/pages/forgot_password_confirmation_page.dart';
import '../../features/auth/forgot_password/pages/reset_password_page.dart';
import '../../features/auth/two_factor/pages/two_factor_page.dart';
import '../../features/splash/pages/splash_page.dart';
import '../../features/dashboard/pages/dashboard_page.dart';
import '../../features/settings/pages/settings_page.dart';
import '../../features/properties/pages/properties_page.dart';
import '../../features/notifications/pages/notifications_page.dart';
import '../../features/properties/pages/property_details_page.dart';
import '../../features/properties/pages/create_property_page.dart';
import '../../features/properties/pages/property_drafts_list_page.dart';
import '../../features/properties/pages/property_offers_page.dart';
import '../../features/properties/pages/offer_details_page.dart';
import '../../features/properties/pages/property_approvals_page.dart';
import '../../features/appointments/pages/calendar_page.dart';
import '../../features/appointments/pages/create_appointment_page.dart';
import '../../features/appointments/pages/edit_appointment_page.dart';
import '../../features/appointments/pages/appointment_details_page.dart';
import '../../features/profile/pages/profile_page.dart';
import '../../features/profile/pages/edit_profile_page.dart';
import '../../features/clients/pages/clients_page.dart';
import '../../features/clients/pages/client_details_page.dart';
import '../../features/clients/pages/client_form_page.dart';
import '../../features/matches/pages/matches_page.dart';
import '../../features/kanban/pages/kanban_page.dart';
import '../../features/kanban/pages/kanban_subtasks_list_page.dart';
import '../../features/kanban/pages/kanban_task_details_page.dart';
import '../../features/documents/pages/documents_page.dart';
import '../../features/documents/pages/create_document_page.dart';
import '../../features/documents/pages/document_details_page.dart';
import '../../features/documents/pages/signatures_page.dart';
import '../../features/chat/pages/chat_page.dart';
import '../../features/chat/pages/edit_group_chat_page.dart';
import '../../features/inspections/pages/inspections_page.dart';
import '../../features/inspections/pages/inspection_details_page.dart';
import '../../features/inspections/pages/create_inspection_page.dart';
import '../../features/inspections/pages/edit_inspection_page.dart';
import '../../features/keys/pages/keys_page.dart';
import '../../features/keys/pages/create_key_page.dart';
import '../../features/notes/pages/create_note_page.dart';
import '../../features/notes/pages/notes_page.dart';
import '../../features/proposals/pages/create_proposal_page.dart';
import '../../features/proposals/pages/proposals_page.dart';
import '../../features/checklists/pages/checklists_page.dart';
import '../../features/workspace/pages/workspace_page.dart';
import '../../features/workspace/pages/users_page.dart';
import '../../features/workspace/pages/teams_page.dart';
import '../../features/check_in/pages/check_in_page.dart';
import '../../features/check_in/pages/check_in_list_page.dart';
import '../../shared/services/property_service.dart';

/// Rotas da aplicação com transições customizadas
class AppRoutes {
  AppRoutes._();

  static const String splash = '/';
  static const String login = '/login';
  static const String forgotPassword = '/forgot-password';
  static const String forgotPasswordConfirmation =
      '/forgot-password-confirmation';
  static const String resetPassword = '/reset-password';
  static const String twoFactor = '/two-factor';
  static const String home = '/home';
  static const String settings = '/settings';
  static const String profile = '/profile';
  static const String profileEdit = '/profile/edit';
  static const String properties = '/properties';
  static const String propertyCreate = '/properties/create';
  /// Rascunhos de cadastro armazenados só no dispositivo.
  static const String propertyDraftsLocal = '/properties/drafts-local';
  static const String propertyOffers = '/properties/offers';
  /// Fila de aprovação de imóveis (paridade com `/properties/pending-approvals`
  /// no `imobx-front`). Lista pendentes de disponibilidade, publicação,
  /// autorização do proprietário e recusados.
  static const String propertyApprovals = '/properties/pending-approvals';
  static const String notifications = '/notifications';
  static const String calendar = '/calendar';
  static const String calendarCreate = '/calendar/create';
  static String calendarEdit(String id) => '/calendar/edit/$id';
  static String calendarDetails(String id) => '/calendar/details/$id';

  static const String clients = '/clients';
  static const String clientCreate = '/clients/new';
  static String clientEdit(String id) => '/clients/$id/edit';
  static String clientDetails(String id) => '/clients/$id';

  // Matches
  static const String matches = '/matches';
  static String matchesByProperty(String propertyId) =>
      '/properties/$propertyId/matches';
  static String matchesByClient(String clientId) =>
      '/clients/$clientId/matches';

  // Kanban (Tarefas)
  static const String kanban = '/kanban';
  /// Lista global de tarefas do CRM (subtarefas dos cards). Paridade com
  /// `/kanban/tarefas` do `imobx-front` — usuário pode ver pendentes, hoje,
  /// atrasadas, concluídas e todas.
  static const String kanbanSubtasks = '/kanban/tarefas';
  /// Deep-link para a negociação (card do funil) — abre o `TaskDetailsModal`
  /// automaticamente após carregar a `KanbanTask` por id. Paridade com
  /// `/kanban/task/:taskId` do `imobx-front`.
  static String kanbanTaskDetails(String taskId) => '/kanban/task/$taskId';

  // Documentos
  static const String documents = '/documents';
  static const String documentCreate = '/documents/create';
  static String documentDetails(String id) => '/documents/$id';
  static String documentEdit(String id) => '/documents/$id/edit';
  static const String signatures = '/signatures';

  // Chat
  static const String chat = '/chat';
  static String chatRoom(String roomId) => '/chat/$roomId';
  static String chatEditGroup(String roomId) => '/chat/edit-group/$roomId';

  // Vistorias
  static const String inspections = '/inspections';
  static const String inspectionCreate = '/inspections/new';
  static String inspectionDetails(String id) => '/inspections/$id';
  static String inspectionEdit(String id) => '/inspections/$id/edit';

  // Chaves
  static const String keys = '/keys';
  static const String keyCreate = '/keys/create';
  static String keyEdit(String id) => '/keys/$id/edit';

  static const String notes = '/notes';
  static const String notesCreate = '/notes/create';
  static const String checklists = '/checklists';
  static const String workspace = '/workspace';

  // Colaboradores → sub-rotas
  static const String users = '/users';
  static const String teams = '/teams';

  // Check-in (presença na imobiliária por geolocalização)
  /// Tela principal — fazer check-in / check-out + estado atual.
  static const String checkIn = '/check-in';
  /// Histórico de check-ins (lista paginada com filtros).
  static const String checkInList = '/check-in/list';

  // Fichas de proposta de compra
  static const String proposals = '/proposals';
  static const String proposalCreate = '/proposals/create';
  static String proposalEdit(String id) => '/proposals/$id/edit';

  static String propertyOfferDetails(String offerId) =>
      '/properties/offers/$offerId';

  /// Gera rota de detalhes da propriedade
  static String propertyDetails(String id) => '/properties/$id';

  /// Gera rota de edição da propriedade
  static String propertyEdit(String id) => '/properties/$id/edit';

  /// Autenticação sempre em tema claro (independente do modo escuro do app).
  static Widget _authLightTheme(Widget child) =>
      Theme(data: AppTheme.lightTheme, child: child);

  static Route<dynamic> generateRoute(RouteSettings settings) {
    final routeName = settings.name;

    if (routeName == splash) {
      return _buildRoute(const SplashPage(), settings);
    } else if (routeName == login) {
      return _buildRoute(_authLightTheme(const LoginPage()), settings);
    } else if (routeName == forgotPassword) {
      return _buildRoute(_authLightTheme(const ForgotPasswordPage()), settings);
    } else if (routeName == forgotPasswordConfirmation) {
      final email = settings.arguments as String?;
      return _buildRoute(
        _authLightTheme(ForgotPasswordConfirmationPage(email: email)),
        settings,
      );
    } else if (routeName == resetPassword) {
      final token = settings.arguments as String?;
      return _buildRoute(
        _authLightTheme(ResetPasswordPage(token: token)),
        settings,
      );
    } else if (routeName == twoFactor) {
      final args = settings.arguments as Map<String, dynamic>?;
      return _buildRoute(
        _authLightTheme(
          TwoFactorPage(
            email: args?['email'] ?? '',
            password: args?['password'] ?? '',
            tempToken: args?['tempToken'] ?? '',
          ),
        ),
        settings,
      );
    } else if (routeName == home) {
      return _buildRoute(const DashboardPage(), settings);
    } else if (routeName == AppRoutes.settings) {
      return _buildRoute(const SettingsPage(), settings);
    } else if (routeName == AppRoutes.profile) {
      return _buildRoute(const ProfilePage(), settings);
    } else if (routeName == AppRoutes.profileEdit) {
      return _buildRoute(const EditProfilePage(), settings);
    } else if (routeName == AppRoutes.properties) {
      return _buildRoute(const PropertiesPage(), settings);
    } else if (routeName == AppRoutes.notifications) {
      return _buildRoute(const NotificationsPage(), settings);
    } else if (routeName == AppRoutes.calendar) {
      return _buildRoute(const CalendarPage(), settings);
    } else if (routeName == AppRoutes.calendarCreate) {
      return _buildRoute(const CreateAppointmentPage(), settings);
    } else if (routeName == AppRoutes.clients) {
      return _buildRoute(const ClientsPage(), settings);
    } else if (routeName == AppRoutes.clientCreate) {
      return _buildRoute(const ClientFormPage(), settings);
    } else if (routeName != null && routeName.startsWith('/calendar/')) {
      final segments = routeName.split('/');
      if (segments.length >= 3) {
        final action = segments[2];
        final id = segments.length > 3 ? segments[3] : null;

        if (action == 'edit' && id != null) {
          return _buildRoute(EditAppointmentPage(appointmentId: id), settings);
        } else if (action == 'details' && id != null) {
          return _buildRoute(
            AppointmentDetailsPage(appointmentId: id),
            settings,
          );
        }
      }
    } else if (routeName == AppRoutes.propertyDraftsLocal) {
      return _buildRoute(const PropertyDraftsListPage(), settings);
    } else if (routeName == AppRoutes.propertyCreate) {
      final args = settings.arguments as Map<String, dynamic>?;
      final localDraftId = args != null ? args['localDraftId'] as String? : null;
      return _buildRoute(
        CreatePropertyPage(localDraftId: localDraftId),
        settings,
      );
    } else if (routeName == AppRoutes.propertyOffers) {
      // IMPORTANTE: Esta rota deve vir ANTES da verificação genérica de /properties/
      debugPrint('🛣️ [ROUTES] Navegando para PropertyOffersPage');
      return _buildRoute(const PropertyOffersPage(), settings);
    } else if (routeName == AppRoutes.propertyApprovals) {
      // IMPORTANTE: deve vir ANTES da regex de /properties/:id senão o
      // segmento "pending-approvals" é tratado como UUID e cai em
      // PropertyDetailsPage.
      return _buildRoute(const PropertyApprovalsPage(), settings);
    } else if (routeName != null &&
        routeName.startsWith('/properties/offers/')) {
      // Detalhes de oferta: /properties/offers/:offerId
      final segments = routeName.split('/');
      if (segments.length == 4) {
        final offerId = segments[3];
        return _buildRoute(OfferDetailsPage(offerId: offerId), settings);
      }
    } else if (routeName != null && routeName.startsWith('/properties/')) {
      // Detalhes ou edição de propriedade (deve vir DEPOIS das rotas de ofertas)
      final segments = routeName.split('/');
      if (segments.length >= 3) {
        final id = segments[2];
        if (segments.length == 3) {
          // Detalhes: /properties/:id
          final args = settings.arguments;
          final initialProperty = args is Map<String, dynamic>
              ? args['property'] as Property?
              : null;
          return _buildRoute(
            PropertyDetailsPage(propertyId: id, initialProperty: initialProperty),
            settings,
          );
        } else if (segments.length == 4 && segments[3] == 'edit') {
          // Edição: /properties/:id/edit
          return _buildRoute(CreatePropertyPage(propertyId: id), settings);
        } else if (segments.length == 4 && segments[3] == 'matches') {
          // Matches filtrados por imóvel
          return _buildRoute(MatchesPage(propertyId: id), settings);
        }
      }
      // Se não correspondeu aos padrões acima, retornar página não encontrada
      return _buildRoute(
        const Scaffold(body: Center(child: Text('Página não encontrada'))),
        settings,
      );
    } else if (routeName != null && routeName.startsWith('/clients/')) {
      // Rotas de clientes
      final segments = routeName.split('/');
      if (segments.length >= 3) {
        final id = segments[2];
        if (segments.length == 3) {
          // Detalhes: /clients/:id
          return _buildRoute(ClientDetailsPage(clientId: id), settings);
        } else if (segments.length == 4 && segments[3] == 'edit') {
          // Edição: /clients/:id/edit
          return _buildRoute(ClientFormPage(clientId: id), settings);
        }
      }
    } else if (routeName == AppRoutes.matches) {
      return _buildRoute(const MatchesPage(), settings);
    } else if (routeName == AppRoutes.kanban) {
      return _buildRoute(const KanbanPage(), settings);
    } else if (routeName == AppRoutes.kanbanSubtasks) {
      return _buildRoute(const KanbanSubtasksListPage(), settings);
    } else if (routeName != null &&
        routeName.startsWith('/kanban/task/')) {
      // /kanban/task/:taskId — IMPORTANTE: deve vir antes da regex genérica
      // de /kanban/ se houver outras. Aqui só prefixo dedicado, sem ambiguidade.
      final segments = routeName.split('/');
      if (segments.length == 4) {
        final taskId = segments[3];
        if (taskId.isNotEmpty) {
          return _buildRoute(KanbanTaskDetailsPage(taskId: taskId), settings);
        }
      }
    } else if (routeName == AppRoutes.inspections) {
      return _buildRoute(const InspectionsPage(), settings);
    } else if (routeName == AppRoutes.inspectionCreate) {
      return _buildRoute(const CreateInspectionPage(), settings);
    } else if (routeName != null && routeName.startsWith('/inspections/')) {
      final segments = routeName.split('/');
      if (segments.length >= 3) {
        final id = segments[2];
        if (segments.length == 3) {
          // Detalhes: /inspections/:id
          return _buildRoute(InspectionDetailsPage(inspectionId: id), settings);
        } else if (segments.length == 4 && segments[3] == 'edit') {
          // Edição: /inspections/:id/edit
          return _buildRoute(EditInspectionPage(inspectionId: id), settings);
        }
      }
    } else if (routeName == AppRoutes.keys) {
      return _buildRoute(const KeysPage(), settings);
    } else if (routeName == AppRoutes.keyCreate) {
      return _buildRoute(const CreateKeyPage(), settings);
    } else if (routeName != null && routeName.startsWith('/keys/')) {
      final segments = routeName.split('/');
      if (segments.length >= 4 && segments[3] == 'edit') {
        final id = segments[2];
        return _buildRoute(CreateKeyPage(keyId: id), settings);
      }
    } else if (routeName == AppRoutes.documents) {
      return _buildRoute(const DocumentsPage(), settings);
    } else if (routeName == AppRoutes.signatures) {
      return _buildRoute(const SignaturesPage(), settings);
    } else if (routeName == AppRoutes.documentCreate) {
      return _buildRoute(const CreateDocumentPage(), settings);
    } else if (routeName == AppRoutes.chat) {
      return _buildRoute(const ChatPage(), settings);
    } else if (routeName != null && routeName.startsWith('/chat/edit-group/')) {
      final segments = routeName.split('/');
      if (segments.length == 4) {
        final roomId = segments[3];
        return _buildRoute(EditGroupChatPage(roomId: roomId), settings);
      }
    } else if (routeName != null && routeName.startsWith('/chat/')) {
      final segments = routeName.split('/');
      if (segments.length == 3) {
        final roomId = segments[2];
        return _buildRoute(ChatPage(roomId: roomId), settings);
      }
    } else if (routeName != null && routeName.startsWith('/documents/')) {
      final segments = routeName.split('/');
      if (segments.length >= 3) {
        final id = segments[2];
        if (segments.length == 3) {
          // Detalhes: /documents/:id
          return _buildRoute(DocumentDetailsPage(documentId: id), settings);
        } else if (segments.length == 4 && segments[3] == 'edit') {
          // Edição: /documents/:id/edit
          return _buildRoute(CreateDocumentPage(documentId: id), settings);
        }
      }
    } else if (routeName != null && routeName.startsWith('/clients/')) {
      // Matches de cliente: /clients/:clientId/matches
      final segments = routeName.split('/');
      if (segments.length == 4 && segments[3] == 'matches') {
        final clientId = segments[2];
        return _buildRoute(MatchesPage(clientId: clientId), settings);
      }
    } else if (routeName == AppRoutes.notes) {
      return _buildRoute(const NotesPage(), settings);
    } else if (routeName == AppRoutes.notesCreate) {
      return _buildRoute(const CreateNotePage(), settings);
    } else if (routeName == AppRoutes.proposals) {
      return _buildRoute(const ProposalsPage(), settings);
    } else if (routeName == AppRoutes.proposalCreate) {
      return _buildRoute(const CreateProposalPage(), settings);
    } else if (routeName != null &&
        routeName.startsWith('/proposals/')) {
      final segments = routeName.split('/');
      if (segments.length == 4 && segments[3] == 'edit') {
        final id = segments[2];
        if (id.isNotEmpty) {
          return _buildRoute(CreateProposalPage(proposalId: id), settings);
        }
      }
    } else if (routeName == AppRoutes.checklists) {
      return _buildRoute(const ChecklistsPage(), settings);
    } else if (routeName == AppRoutes.workspace) {
      return _buildRoute(const WorkspacePage(), settings);
    } else if (routeName == AppRoutes.users) {
      return _buildRoute(const UsersPage(), settings);
    } else if (routeName == AppRoutes.teams) {
      return _buildRoute(const TeamsPage(), settings);
    } else if (routeName == AppRoutes.checkIn) {
      return _buildRoute(const CheckInPage(), settings);
    } else if (routeName == AppRoutes.checkInList) {
      return _buildRoute(const CheckInListPage(), settings);
    }

    // Rota não encontrada
    return _buildRoute(
      const Scaffold(body: Center(child: Text('Página não encontrada'))),
      settings,
    );
  }

  /// Transição suave entre telas.
  ///
  /// O tipo genérico das rotas ([PageRouteBuilder]/[ModalRoute]) refere-se ao
  /// **valor opcional** retornado por `Navigator.pop(result)` — não ao widget da
  /// página. Usar `T extends Widget` quebrava `pop(true)` / `pop(false)` com
  /// `type 'bool' is not a subtype of type 'Widget?'` e leave o navigator num
  /// estado inconsistente (`!_debugLocked`).
  static Route<dynamic> _buildRoute(
    Widget page,
    RouteSettings settings,
  ) {
    // iPhone: transição e gesto de voltar nativos (paridade com apps de sistema).
    if (useCupertinoNativeTransitions) {
      return CupertinoPageRoute<dynamic>(
        settings: settings,
        builder: (_) => page,
      );
    }

    return PageRouteBuilder<dynamic>(
      settings: settings,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        // Animação de fade + slide
        const begin = Offset(0.0, 0.03);
        const end = Offset.zero;
        const curve = Curves.easeInOutCubic;

        var tween = Tween(
          begin: begin,
          end: end,
        ).chain(CurveTween(curve: curve));

        var fadeTween = Tween(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: curve));

        return FadeTransition(
          opacity: animation.drive(fadeTween),
          child: SlideTransition(
            position: animation.drive(tween),
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 400),
    );
  }
}
