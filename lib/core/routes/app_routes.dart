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
import '../../features/sale_forms/pages/sale_forms_page.dart';
import '../../features/sale_forms/pages/sale_forms_dashboard_page.dart';
import '../../features/commissions/pages/commissions_page.dart';
import '../../features/workspace/pages/workspace_page.dart';
import '../../features/workspace/pages/users_page.dart';
import '../../features/workspace/pages/create_user_page.dart';
import '../../features/workspace/pages/teams_page.dart';
import '../../features/workspace/pages/team_form_page.dart';
import '../../features/check_in/pages/check_in_page.dart';
import '../../features/check_in/pages/check_in_list_page.dart';
import '../../features/visit_reports/pages/visits_page.dart';
import '../../features/visit_reports/pages/visit_report_form_page.dart';
import '../../features/visit_reports/pages/visit_report_detail_page.dart';
import '../../features/condominiums/pages/condominiums_page.dart';
import '../../features/condominiums/pages/condominium_form_page.dart';
import '../../features/condominiums/pages/developments_page.dart';
import '../../features/condominiums/pages/development_detail_page.dart';
import '../../features/condominiums/pages/development_form_page.dart';
import '../../features/mcmv/models/mcmv_models.dart';
import '../../features/mcmv/pages/mcmv_blacklist_page.dart';
import '../../features/mcmv/pages/mcmv_lead_details_page.dart';
import '../../features/mcmv/pages/mcmv_leads_page.dart';
import '../../features/mcmv/pages/mcmv_templates_page.dart';
import '../../features/goals/pages/goals_page.dart';
import '../../features/goals/pages/goal_form_page.dart';
import '../../features/goals/pages/goal_analytics_page.dart';
import '../../features/checklists/pages/checklists_page.dart';
import '../../features/checklists/pages/create_checklist_page.dart';
import '../../features/checklists/pages/checklist_details_page.dart';
import '../../features/assets/pages/assets_page.dart';
import '../../features/assets/pages/create_asset_page.dart';
import '../../features/assets/pages/asset_details_page.dart';
import '../../features/rentals/pages/rentals_page.dart';
import '../../features/rentals/pages/rental_form_page.dart';
import '../../features/rentals/pages/rental_details_page.dart';
import '../../features/rentals/pages/rental_dashboard_page.dart';
import '../../features/rental_forms/pages/rental_form_editor_page.dart';
import '../../features/rental_forms/pages/rental_forms_page.dart';
import '../../features/insurance/pages/insurance_quote_page.dart';
import '../../features/credit_analysis/pages/credit_analysis_page.dart';
import '../../features/credit_analysis/pages/credit_analysis_settings_page.dart';
import '../../features/collection/pages/collection_page.dart';
import '../../features/collection/pages/collection_rules_page.dart';
import '../../features/collection/pages/collection_rule_form_page.dart';
import '../../features/gamification/pages/gamification_page.dart';
import '../../features/gamification/pages/gamification_settings_page.dart';
import '../../features/gamification/pages/competitions_page.dart';
import '../../features/gamification/pages/competition_form_page.dart';
import '../../features/gamification/pages/add_prizes_page.dart';
import '../../features/gamification/pages/prizes_page.dart';
import '../../features/rewards/pages/approve_redemptions_page.dart';
import '../../features/rewards/pages/manage_rewards_page.dart';
import '../../features/rewards/pages/my_redemptions_page.dart';
import '../../features/rewards/pages/reward_form_page.dart';
import '../../features/rewards/pages/rewards_page.dart';
import '../../features/tickets/pages/tickets_page.dart';
import '../../features/tickets/pages/ticket_create_page.dart';
import '../../features/tickets/pages/ticket_detail_page.dart';
import '../../features/help/pages/help_page.dart';
import '../../features/automations/pages/automations_page.dart';
import '../../features/automations/pages/create_automation_page.dart';
import '../../features/automations/pages/automation_details_page.dart';
import '../../features/automations/pages/automation_history_page.dart';
import '../../features/whatsapp/models/whatsapp_models.dart';
import '../../features/whatsapp/pages/whatsapp_conversation_page.dart';
import '../../features/whatsapp/pages/whatsapp_inbox_page.dart';
import '../../features/sdr/pages/sdr_dashboard_page.dart';
import '../../features/sdr/pages/sdr_settings_page.dart';
import '../../features/integrations/pages/integrations_page.dart';
import '../../features/integrations/pages/integration_details_page.dart';
import '../../features/zezin/pages/zezin_ask_page.dart';
import '../../features/zezin/pages/zezin_config_page.dart';
import '../../features/public_site/pages/public_site_page.dart';
import '../../features/public_site/pages/bio_link_page.dart';
import '../../features/analytics/pages/multichannel_analytics_page.dart';
import '../../features/analytics/pages/advanced_analytics_page.dart';
import '../../features/analytics/pages/property_analytics_page.dart';
import '../../features/analytics/pages/compare_users_page.dart';
import '../../features/analytics/pages/compare_teams_page.dart';
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
  static const String workspace = '/workspace';

  // Colaboradores → sub-rotas
  static const String users = '/users';
  static const String userCreate = '/users/create';
  static const String teams = '/teams';
  static const String teamCreate = '/teams/create';
  static String teamEdit(String id) => '/teams/$id/edit';

  // Check-in (presença na imobiliária por geolocalização)
  /// Tela principal — fazer check-in / check-out + estado atual.
  static const String checkIn = '/check-in';
  /// Histórico de check-ins (lista paginada com filtros).
  static const String checkInList = '/check-in/list';

  // Comissões
  static const String commissions = '/commissions';

  // Fichas de proposta de compra
  static const String proposals = '/proposals';
  static const String proposalCreate = '/proposals/create';
  static String proposalEdit(String id) => '/proposals/$id/edit';

  static const String saleForms = '/sale-forms';

  /// Painel de fichas de venda (paridade com `/fichas-venda/dashboard` do web).
  static const String saleFormsDashboard = '/sale-forms/dashboard';

  // Relatórios de Visita (módulo `visit_report`)
  static const String visits = '/visits';
  static const String visitCreate = '/visits/create';
  static String visitDetails(String id) => '/visits/$id';
  static String visitEdit(String id) => '/visits/$id/edit';

  // Condomínios & Empreendimentos
  static const String condominiums = '/condominiums';
  static const String condominiumCreate = '/condominiums/create';
  static String condominiumEdit(String id) => '/condominiums/$id/edit';
  static const String developments = '/developments';
  static const String developmentCreate = '/developments/create';
  static String developmentDetails(String id) => '/developments/$id';
  static String developmentEdit(String id) => '/developments/$id/edit';

  // MCMV (Minha Casa Minha Vida)
  static const String mcmvLeads = '/mcmv/leads';
  static const String mcmvBlacklist = '/mcmv/blacklist';
  static const String mcmvTemplates = '/mcmv/templates';
  static String mcmvLeadDetails(String id) => '/mcmv/leads/$id';

  // Metas (acesso admin/master — espelha o AdminRoute do web)
  static const String goals = '/goals';
  static const String goalCreate = '/goals/create';
  static String goalEdit(String id) => '/goals/$id/edit';
  static String goalAnalytics(String id) => '/goals/$id/analytics';

  // Checklists standalone
  static const String checklists = '/checklists';
  static const String checklistCreate = '/checklists/create';
  static String checklistDetails(String id) => '/checklists/$id';
  static String checklistEdit(String id) => '/checklists/$id/edit';

  // Patrimônio (assets)
  static const String assets = '/assets';
  static const String assetCreate = '/assets/create';
  static String assetDetails(String id) => '/assets/$id';
  static String assetEdit(String id) => '/assets/$id/edit';

  // Locações (módulo rental_management)
  static const String rentals = '/rentals';
  static const String rentalCreate = '/rentals/create';
  static const String rentalsDashboard = '/rentals/dashboard';
  static String rentalDetails(String id) => '/rentals/$id';
  static String rentalEdit(String id) => '/rentals/$id/edit';

  // Fichas de locação (módulo rental_management)
  static const String rentalForms = '/rental-forms';
  static String rentalFormEditor(String id) => '/rental-forms/$id';

  // Seguros — cotação de seguro fiança (módulo rental_management)
  static const String insuranceQuote = '/insurance/quote';

  // Análise de crédito (módulo credit_and_collection)
  static const String creditAnalysis = '/credit-analysis';
  static const String creditAnalysisSettings = '/credit-analysis/settings';

  // Régua de Cobrança (módulo credit_and_collection)
  static const String collection = '/collection';
  static const String collectionRules = '/collection/rules';
  static const String collectionRuleCreate = '/collection/rules/new';
  static String collectionRuleEdit(String id) => '/collection/rules/$id';

  // Gamificação & Competições (módulo gamification — OCULTO do drawer)
  static const String gamification = '/gamification';
  static const String gamificationSettings = '/gamification/settings';
  static const String competitions = '/competitions';
  static const String competitionCreate = '/competitions/new';
  static String competitionEdit(String id) => '/competitions/$id/edit';
  static String competitionPrizes(String id) => '/competitions/$id/prizes';
  static const String prizes = '/prizes';

  // Prêmios & Resgates (módulo gamification — OCULTO do drawer)
  static const String rewards = '/rewards';
  static const String rewardsMine = '/rewards/mine';
  static const String rewardsApprove = '/rewards/approve';
  static const String rewardsManage = '/rewards/manage';
  static const String rewardCreate = '/rewards/create';
  static String rewardEdit(String id) => '/rewards/$id/edit';

  // Suporte (Tickets) + Central de Ajuda
  static const String tickets = '/tickets';
  static const String ticketCreate = '/tickets/new';
  static const String ticketDetail = '/tickets/detail';
  static const String help = '/help';

  // Automações (role admin/master + módulo `automations`)
  static const String automations = '/automations';
  static const String automationCreate = '/automations/create';
  static String automationDetails(String id) => '/automations/$id';
  static String automationHistory(String id) => '/automations/$id/history';

  // WhatsApp inbox (módulo api_integrations)
  static const String whatsapp = '/whatsapp';
  static String whatsappConversation(String phoneNumber) =>
      '/whatsapp/${Uri.encodeComponent(phoneNumber)}';

  // SDR IA (módulo whatsapp_ai)
  static const String sdr = '/sdr';
  static const String sdrSettings = '/sdr/settings';

  // Central de Integrações
  static const String integrations = '/integrations';
  static String integrationDetails(String key) => '/integrations/$key';

  // Zezin (assistente IA — módulo ai_assistant; oculto do drawer como no web)
  static const String zezin = '/zezin';
  static const String zezinConfig = '/zezin/config';

  // Meu Site + Link in Bio (módulo public_site_hosting)
  static const String mySite = '/my-site';
  static const String bioLink = '/bio-link';

  // Analytics (só Multicanal aparece no menu — demais são rotas diretas,
  // paridade com o web que mantém as comparações ocultas)
  static const String analyticsMultichannel = '/analytics/multichannel';
  static const String analyticsAdvanced = '/analytics/advanced';
  static const String analyticsProperties = '/analytics/properties';
  static const String analyticsCompareUsers = '/analytics/compare-users';
  static const String analyticsCompareTeams = '/analytics/compare-teams';

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
      final args = settings.arguments as Map<String, dynamic>?;
      return _buildRoute(
        CreateAppointmentPage(
          initialTitle: args?['title'] as String?,
          initialLocation: args?['location'] as String?,
          propertyId: args?['propertyId'] as String?,
          clientId: args?['clientId'] as String?,
        ),
        settings,
      );
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
    } else if (routeName == AppRoutes.commissions) {
      return _buildRoute(const CommissionsPage(), settings);
    } else if (routeName == AppRoutes.saleForms) {
      return _buildRoute(const SaleFormsPage(), settings);
    } else if (routeName == AppRoutes.saleFormsDashboard) {
      return _buildRoute(const SaleFormsDashboardPage(), settings);
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
    } else if (routeName == AppRoutes.workspace) {
      return _buildRoute(const WorkspacePage(), settings);
    } else if (routeName == AppRoutes.users) {
      return _buildRoute(const UsersPage(), settings);
    } else if (routeName == AppRoutes.userCreate) {
      return _buildRoute(const CreateUserPage(), settings);
    } else if (routeName == AppRoutes.teams) {
      return _buildRoute(const TeamsPage(), settings);
    } else if (routeName == AppRoutes.teamCreate) {
      return _buildRoute(const TeamFormPage(), settings);
    } else if (routeName != null && routeName.startsWith('/teams/')) {
      // Edição: /teams/:id/edit
      final segments = routeName.split('/');
      if (segments.length == 4 && segments[3] == 'edit') {
        final id = segments[2];
        if (id.isNotEmpty) {
          return _buildRoute(TeamFormPage(teamId: id), settings);
        }
      }
    } else if (routeName == AppRoutes.checkIn) {
      return _buildRoute(const CheckInPage(), settings);
    } else if (routeName == AppRoutes.checkInList) {
      return _buildRoute(const CheckInListPage(), settings);
    } else if (routeName == AppRoutes.visits) {
      return _buildRoute(const VisitsPage(), settings);
    } else if (routeName == AppRoutes.visitCreate) {
      // Deve vir ANTES do prefixo genérico de /visits/, senão "create" vira id.
      return _buildRoute(const VisitReportFormPage(), settings);
    } else if (routeName != null && routeName.startsWith('/visits/')) {
      final segments = routeName.split('/');
      if (segments.length >= 3) {
        final id = segments[2];
        if (segments.length == 3 && id.isNotEmpty) {
          return _buildRoute(VisitReportDetailPage(reportId: id), settings);
        } else if (segments.length == 4 && segments[3] == 'edit') {
          return _buildRoute(VisitReportFormPage(reportId: id), settings);
        }
      }
    } else if (routeName == AppRoutes.condominiums) {
      return _buildRoute(const CondominiumsPage(), settings);
    } else if (routeName == AppRoutes.condominiumCreate) {
      return _buildRoute(const CondominiumFormPage(), settings);
    } else if (routeName != null && routeName.startsWith('/condominiums/')) {
      // Edição: /condominiums/:id/edit
      final segments = routeName.split('/');
      if (segments.length == 4 && segments[3] == 'edit') {
        final id = segments[2];
        if (id.isNotEmpty) {
          return _buildRoute(CondominiumFormPage(condominiumId: id), settings);
        }
      }
    } else if (routeName == AppRoutes.developments) {
      return _buildRoute(const DevelopmentsPage(), settings);
    } else if (routeName == AppRoutes.developmentCreate) {
      return _buildRoute(const DevelopmentFormPage(), settings);
    } else if (routeName != null && routeName.startsWith('/developments/')) {
      // Detalhe (/developments/:id) e edição (/developments/:id/edit)
      final segments = routeName.split('/');
      if (segments.length >= 3) {
        final id = segments[2];
        if (id.isNotEmpty) {
          if (segments.length == 3) {
            return _buildRoute(
                DevelopmentDetailPage(developmentId: id), settings);
          } else if (segments.length == 4 && segments[3] == 'edit') {
            return _buildRoute(
                DevelopmentFormPage(developmentId: id), settings);
          }
        }
      }
    } else if (routeName == AppRoutes.mcmvLeads) {
      return _buildRoute(const McmvLeadsPage(), settings);
    } else if (routeName == AppRoutes.mcmvBlacklist) {
      return _buildRoute(const McmvBlacklistPage(), settings);
    } else if (routeName == AppRoutes.mcmvTemplates) {
      return _buildRoute(const McmvTemplatesPage(), settings);
    } else if (routeName != null && routeName.startsWith('/mcmv/leads/')) {
      // Detalhe: /mcmv/leads/:id — o backend não expõe GET por id; a página
      // aceita o McmvLead da listagem via settings.arguments.
      final segments = routeName.split('/');
      if (segments.length == 4 && segments[3].isNotEmpty) {
        final lead = settings.arguments is McmvLead
            ? settings.arguments as McmvLead
            : null;
        return _buildRoute(
          McmvLeadDetailsPage(leadId: segments[3], initialLead: lead),
          settings,
        );
      }
    } else if (routeName == AppRoutes.goals) {
      return _buildRoute(const GoalsPage(), settings);
    } else if (routeName == AppRoutes.goalCreate) {
      return _buildRoute(const GoalFormPage(), settings);
    } else if (routeName != null && routeName.startsWith('/goals/')) {
      // /goals/:id/edit e /goals/:id/analytics
      final segments = routeName.split('/');
      if (segments.length == 4 && segments[2].isNotEmpty) {
        final id = segments[2];
        if (segments[3] == 'edit') {
          return _buildRoute(GoalFormPage(goalId: id), settings);
        } else if (segments[3] == 'analytics') {
          return _buildRoute(GoalAnalyticsPage(goalId: id), settings);
        }
      }
    } else if (routeName == AppRoutes.checklists) {
      return _buildRoute(const ChecklistsPage(), settings);
    } else if (routeName == AppRoutes.checklistCreate) {
      return _buildRoute(const CreateChecklistPage(), settings);
    } else if (routeName != null && routeName.startsWith('/checklists/')) {
      final segments = routeName.split('/');
      if (segments.length >= 3) {
        final id = segments[2];
        if (segments.length == 3 && id.isNotEmpty) {
          return _buildRoute(ChecklistDetailsPage(checklistId: id), settings);
        } else if (segments.length == 4 && segments[3] == 'edit') {
          return _buildRoute(CreateChecklistPage(checklistId: id), settings);
        }
      }
    } else if (routeName == AppRoutes.assets) {
      return _buildRoute(const AssetsPage(), settings);
    } else if (routeName == AppRoutes.assetCreate) {
      return _buildRoute(const CreateAssetPage(), settings);
    } else if (routeName != null && routeName.startsWith('/assets/')) {
      final segments = routeName.split('/');
      if (segments.length >= 3) {
        final id = segments[2];
        if (segments.length == 3 && id.isNotEmpty) {
          return _buildRoute(AssetDetailsPage(assetId: id), settings);
        } else if (segments.length == 4 && segments[3] == 'edit') {
          return _buildRoute(CreateAssetPage(assetId: id), settings);
        }
      }
    } else if (routeName == AppRoutes.rentals) {
      return _buildRoute(const RentalsPage(), settings);
    } else if (routeName == AppRoutes.rentalCreate) {
      return _buildRoute(const RentalFormPage(), settings);
    } else if (routeName == AppRoutes.rentalsDashboard) {
      return _buildRoute(const RentalDashboardPage(), settings);
    } else if (routeName != null && routeName.startsWith('/rentals/')) {
      // Detalhe (/rentals/:id) e edição (/rentals/:id/edit)
      final segments = routeName.split('/');
      if (segments.length >= 3 && segments[2].isNotEmpty) {
        final id = segments[2];
        if (segments.length == 3) {
          // A lista passa arguments: {'tab': 'payments'} para abrir direto
          // na aba de parcelas (ação "Pagamentos" do item).
          final args = settings.arguments;
          final tab =
              args is Map<String, dynamic> ? args['tab'] as String? : null;
          return _buildRoute(
            RentalDetailsPage(rentalId: id, initialTab: tab),
            settings,
          );
        } else if (segments.length == 4 && segments[3] == 'edit') {
          return _buildRoute(RentalFormPage(rentalId: id), settings);
        }
      }
    } else if (routeName == AppRoutes.rentalForms) {
      return _buildRoute(const RentalFormsPage(), settings);
    } else if (routeName != null && routeName.startsWith('/rental-forms/')) {
      // Editor: /rental-forms/:id
      final segments = routeName.split('/');
      if (segments.length == 3 && segments[2].isNotEmpty) {
        return _buildRoute(
            RentalFormEditorPage(formId: segments[2]), settings);
      }
    } else if (routeName == AppRoutes.insuranceQuote) {
      // `rentalId` opcional via arguments — habilita a contratação da
      // apólice (sem ele a tela cota mas não contrata, paridade com o web).
      final args = settings.arguments as Map<String, dynamic>?;
      return _buildRoute(
        InsuranceQuotePage(rentalId: args?['rentalId'] as String?),
        settings,
      );
    } else if (routeName == AppRoutes.creditAnalysisSettings) {
      return _buildRoute(const CreditAnalysisSettingsPage(), settings);
    } else if (routeName == AppRoutes.creditAnalysis) {
      return _buildRoute(const CreditAnalysisPage(), settings);
    } else if (routeName == AppRoutes.collection) {
      return _buildRoute(const CollectionPage(), settings);
    } else if (routeName == AppRoutes.collectionRules) {
      return _buildRoute(const CollectionRulesPage(), settings);
    } else if (routeName == AppRoutes.collectionRuleCreate) {
      return _buildRoute(const CollectionRuleFormPage(), settings);
    } else if (routeName != null &&
        routeName.startsWith('/collection/rules/')) {
      // /collection/rules/:id — edição de régua
      final segments = routeName.split('/');
      if (segments.length == 4 && segments[3].isNotEmpty) {
        return _buildRoute(
            CollectionRuleFormPage(ruleId: segments[3]), settings);
      }
    } else if (routeName == AppRoutes.gamification) {
      return _buildRoute(const GamificationPage(), settings);
    } else if (routeName == AppRoutes.gamificationSettings) {
      return _buildRoute(const GamificationSettingsPage(), settings);
    } else if (routeName == AppRoutes.competitions) {
      return _buildRoute(const CompetitionsPage(), settings);
    } else if (routeName == AppRoutes.competitionCreate) {
      return _buildRoute(const CompetitionFormPage(), settings);
    } else if (routeName != null && routeName.startsWith('/competitions/')) {
      // /competitions/:id/edit e /competitions/:id/prizes
      final segments = routeName.split('/');
      if (segments.length == 4 && segments[2].isNotEmpty) {
        final id = segments[2];
        if (segments[3] == 'edit') {
          return _buildRoute(CompetitionFormPage(competitionId: id), settings);
        } else if (segments[3] == 'prizes') {
          return _buildRoute(AddPrizesPage(competitionId: id), settings);
        }
      }
    } else if (routeName == AppRoutes.prizes) {
      return _buildRoute(const PrizesPage(), settings);
    } else if (routeName == AppRoutes.rewards) {
      return _buildRoute(const RewardsPage(), settings);
    } else if (routeName == AppRoutes.rewardsMine) {
      return _buildRoute(const MyRedemptionsPage(), settings);
    } else if (routeName == AppRoutes.rewardsApprove) {
      return _buildRoute(const ApproveRedemptionsPage(), settings);
    } else if (routeName == AppRoutes.rewardsManage) {
      return _buildRoute(const ManageRewardsPage(), settings);
    } else if (routeName == AppRoutes.rewardCreate) {
      // Deve vir ANTES do prefixo genérico de /rewards/, senão "create" vira id.
      return _buildRoute(const RewardFormPage(), settings);
    } else if (routeName != null && routeName.startsWith('/rewards/')) {
      // Edição: /rewards/:id/edit
      final segments = routeName.split('/');
      if (segments.length == 4 && segments[3] == 'edit') {
        final id = segments[2];
        if (id.isNotEmpty) {
          return _buildRoute(RewardFormPage(rewardId: id), settings);
        }
      }
    } else if (routeName == AppRoutes.tickets) {
      return _buildRoute(const TicketsPage(), settings);
    } else if (routeName == AppRoutes.ticketCreate) {
      return _buildRoute(const TicketCreatePage(), settings);
    } else if (routeName == AppRoutes.ticketDetail) {
      // Recebe o id do ticket via settings.arguments (String ou Map).
      final args = settings.arguments;
      final ticketId = args is String
          ? args
          : args is Map<String, dynamic>
              ? (args['ticketId']?.toString() ?? args['id']?.toString() ?? '')
              : '';
      return _buildRoute(TicketDetailPage(ticketId: ticketId), settings);
    } else if (routeName == AppRoutes.help) {
      return _buildRoute(const HelpPage(), settings);
    } else if (routeName == AppRoutes.automations) {
      return _buildRoute(const AutomationsPage(), settings);
    } else if (routeName == AppRoutes.automationCreate) {
      // IMPORTANTE: deve vir ANTES da verificação genérica de /automations/
      return _buildRoute(const CreateAutomationPage(), settings);
    } else if (routeName != null && routeName.startsWith('/automations/')) {
      final segments = routeName.split('/');
      if (segments.length == 4 && segments[3] == 'history') {
        // /automations/:id/history — o detalhe passa o nome via arguments
        // pra evitar flash sem título (a página busca sozinha se faltar).
        final args = settings.arguments as Map<String, dynamic>?;
        return _buildRoute(
          AutomationHistoryPage(
            automationId: segments[2],
            automationName: args?['automationName'] as String?,
          ),
          settings,
        );
      } else if (segments.length == 3) {
        // /automations/:id
        return _buildRoute(
          AutomationDetailsPage(automationId: segments[2]),
          settings,
        );
      }
    } else if (routeName == AppRoutes.whatsapp) {
      return _buildRoute(const WhatsAppInboxPage(), settings);
    } else if (routeName != null && routeName.startsWith('/whatsapp/')) {
      final segments = routeName.split('/');
      if (segments.length == 3 && segments[2].isNotEmpty) {
        final phone = Uri.decodeComponent(segments[2]);
        final args = settings.arguments;
        return _buildRoute(
          WhatsAppConversationPage(
            phoneNumber: phone,
            conversation: args is WhatsAppConversation ? args : null,
          ),
          settings,
        );
      }
    } else if (routeName == AppRoutes.sdr) {
      return _buildRoute(const SdrDashboardPage(), settings);
    } else if (routeName == AppRoutes.sdrSettings) {
      return _buildRoute(const SdrSettingsPage(), settings);
    } else if (routeName == AppRoutes.integrations) {
      return _buildRoute(const IntegrationsPage(), settings);
    } else if (routeName != null && routeName.startsWith('/integrations/')) {
      // Detalhe da integração: /integrations/:key
      final segments = routeName.split('/');
      if (segments.length == 3 && segments[2].isNotEmpty) {
        return _buildRoute(
          IntegrationDetailsPage(integrationKey: segments[2]),
          settings,
        );
      }
    } else if (routeName == AppRoutes.zezin) {
      return _buildRoute(const ZezinAskPage(), settings);
    } else if (routeName == AppRoutes.zezinConfig) {
      return _buildRoute(const ZezinConfigPage(), settings);
    } else if (routeName == AppRoutes.mySite) {
      return _buildRoute(const PublicSitePage(), settings);
    } else if (routeName == AppRoutes.bioLink) {
      return _buildRoute(const BioLinkPage(), settings);
    } else if (routeName == AppRoutes.analyticsMultichannel) {
      return _buildRoute(const MultichannelAnalyticsPage(), settings);
    } else if (routeName == AppRoutes.analyticsAdvanced) {
      return _buildRoute(const AdvancedAnalyticsPage(), settings);
    } else if (routeName == AppRoutes.analyticsProperties) {
      return _buildRoute(const PropertyAnalyticsPage(), settings);
    } else if (routeName == AppRoutes.analyticsCompareUsers) {
      return _buildRoute(const CompareUsersPage(), settings);
    } else if (routeName == AppRoutes.analyticsCompareTeams) {
      return _buildRoute(const CompareTeamsPage(), settings);
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
