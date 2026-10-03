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
import '../../features/appointments/pages/appointment_invites_page.dart';
import '../../features/appointments/pages/calendar_page.dart';
import '../../features/appointments/pages/create_appointment_page.dart';
import '../../features/appointments/pages/edit_appointment_page.dart';
import '../../features/appointments/pages/appointment_details_page.dart';
import '../../features/appointments/pages/schedule_settings_page.dart';
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
import '../../features/proposals/abrir_nova_proposta.dart';
import '../../features/sale_forms/pages/sale_forms_page.dart';
import '../../features/sale_forms/pages/sale_forms_dashboard_page.dart';
import '../../features/proposals/pages/proposals_dashboard_page.dart';
import '../../features/sale_forms/pages/sale_form_detail_page.dart';
import '../../features/sale_forms/pages/sale_form_pending_signatures_page.dart';
import '../../features/sale_forms/pages/create_sale_form_page.dart';
import '../../features/sale_forms/sale_form_new_from_proposal.dart';
import '../../shared/widgets/permission_route.dart';
import '../../shared/widgets/route_action_launcher.dart';
import '../../features/commissions/pages/commissions_page.dart';
import '../../features/workspace/pages/workspace_page.dart';
import '../../features/workspace/pages/users_page.dart';
import '../../features/workspace/pages/create_user_page.dart';
import '../../features/workspace/pages/teams_page.dart';
import '../../features/workspace/pages/team_form_page.dart';
import '../../features/check_in/pages/check_in_page.dart';
import '../../features/check_in/pages/check_in_list_page.dart';
import '../../features/check_in/pages/check_in_manage_page.dart';
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
import '../../features/sdr/roleta/pages/sdr_roulette_page.dart';
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
import '../../shared/services/subscription_access_gate.dart';
import '../../features/subscriptions/models/subscription_models.dart';
import '../../features/subscriptions/pages/access_blocked_page.dart';
import '../../features/subscriptions/pages/subscription_details_page.dart';
import '../../features/subscriptions/pages/subscription_management_page.dart';
import '../../features/subscriptions/pages/subscription_page.dart';
import '../../features/subscriptions/pages/subscription_plans_page.dart';
import '../../features/finance/finance_routes.dart';

/// Rotas da aplicação com transições customizadas
class AppRoutes {
  /// Marca a PRÓXIMA rota gerada como troca de aba (sem animação). Consumida
  /// em `_buildRoute`, que roda de forma síncrona dentro do `pushNamed…`.
  static bool _proximaEhTrocaDeAba = false;

  /// Troca de aba: substitui a pilha pela rota da aba, sem animação — a barra
  /// inferior fica parada e só o conteúdo muda. Use para a barra inferior e
  /// para o "voltar" da raiz que leva à Home.
  static void trocarDeAba(
    NavigatorState navigator,
    String rota, {
    bool manterPilha = false,
  }) {
    // A rota é gerada de forma síncrona dentro do push: a marca vale só para
    // ela e é desligada logo em seguida (mesmo se o push falhar).
    _proximaEhTrocaDeAba = true;
    try {
      if (manterPilha) {
        navigator.pushNamed(rota);
      } else {
        navigator.pushNamedAndRemoveUntil(
          rota,
          (route) => route.settings.name == rota,
        );
      }
    } finally {
      _proximaEhTrocaDeAba = false;
    }
  }

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

  /// Caixa de convites da agenda (aceitar/recusar). Precisa de case EXATO no
  /// `generateRoute` ANTES do prefixo genérico `/calendar/` — senão "convites"
  /// seria lido como action de edit/details e cairia em rota não encontrada.
  static const String calendarInvites = '/calendar/convites';
  static String calendarEdit(String id) => '/calendar/edit/$id';
  static String calendarDetails(String id) => '/calendar/details/$id';

  /// "Meus horários" — regra de horários da agenda (paridade com o
  /// ScheduleSettingsPanel do imobx-front).
  static const String calendarSchedule = '/calendar/horarios';

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
  /// Deep-link para a negociação (card do funil) — abre a `TaskDetailsPage`
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
  /// Aceita `arguments: {'checkout': true}` para abrir já com a confirmação
  /// de saída (deep link "Sair" da Ilha Dinâmica).
  static const String checkIn = '/check-in';
  /// Deep link da Ilha Dinâmica (`dreamkeys://check-in/checkout`): abre a
  /// tela de check-in com o fluxo de checkout armado.
  static const String checkInCheckout = '/check-in/checkout';
  /// Histórico de check-ins (lista paginada com filtros).
  static const String checkInList = '/check-in/list';
  /// Gestão do check-in (gestor): registrar por alguém, liberar fora do
  /// horário, soltar bloqueio semanal e ler a auditoria.
  static const String checkInManage = '/check-in/manage';

  // Comissões
  static const String commissions = '/commissions';

  // Fichas de proposta de compra
  static const String proposals = '/proposals';
  static const String proposalCreate = '/proposals/create';
  static const String proposalsDashboard = '/proposals/dashboard';
  static String proposalEdit(String id) => '/proposals/$id/edit';

  /// `/fichas-proposta/nova` do web: dispara `abrirNovaProposta` (fluxo de
  /// criação com escolha de tipo) — ver [RouteActionLauncher].
  static const String proposalNew = '/proposals/new';

  static const String saleForms = '/sale-forms';

  /// Edição de ficha de venda — `/fichas-venda/:id/editar` do web.
  static String saleFormEdit(String id) => '/sale-forms/$id/edit';

  /// Nova ficha a partir de proposta — `/fichas-venda/nova?propostaId=X` do
  /// web (notificação "proposta finalizada").
  static const String saleFormNew = '/sale-forms/new';
  static String saleFormNewFromProposal(String proposalId) =>
      '$saleFormNew?proposalId=${Uri.encodeQueryComponent(proposalId)}';

  /// Painel de fichas de venda (paridade com `/fichas-venda/dashboard` do web).
  static const String saleFormsDashboard = '/sale-forms/dashboard';

  /// Detalhe (read-only) de uma ficha de venda — paridade com
  /// `/fichas-venda/detalhes/:id` do web. Rota NOMEADA porque notificação e
  /// push chegam pelo `Navigator` raiz com `pushNamed` (25/09/2026); a lista
  /// continua abrindo o detalhe por `MaterialPageRoute`, sem mudança.
  static String saleFormDetails(String id) => '/sale-forms/$id';

  /// Assinaturas pendentes das fichas de venda — paridade com
  /// `/fichas-venda/assinaturas-pendentes` do web (`sale_form:view`).
  static const String saleFormsPendingSignatures =
      '/sale-forms/pending-signatures';

  // Relatórios de Visita (módulo `visit_report`)
  static const String visits = '/visits';
  static const String visitCreate = '/visits/create';
  static String visitDetails(String id) => '/visits/$id';
  static String visitEdit(String id) => '/visits/$id/edit';

  /// Gestão de Visitas (29/09/2026): a mesma lista de visitas aberta na
  /// visão da empresa (`scope=all`, `visit:manage`), como a rota
  /// /visit-reports do web. Fora do prefixo /visits/ para não virar id.
  static const String visitReports = '/visit-reports';

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

  // Assinaturas (sub-01 / NEW-01, 03/10/2026). As telas já existiam sem
  // rota; os caminhos são os que elas mesmas usam (`/subscription/plans`,
  // `/subscription/manage/:id`).
  static const String mySubscription = '/subscription';
  static const String subscriptionPlans = '/subscription/plans';
  static const String subscriptionManage = '/subscription/manage';
  static String subscriptionManageDetails(String id) =>
      '/subscription/manage/$id';

  /// Acesso bloqueado (assinatura / plano sem CRM) — ver
  /// `SubscriptionAccessGate`.
  static const String subscriptionRequired =
      SubscriptionAccessGate.subscriptionRequiredRoute;
  static const String systemUnavailable =
      SubscriptionAccessGate.systemUnavailableRoute;
  static const String crmUnavailable =
      SubscriptionAccessGate.crmNotIncludedRoute;

  // Financeiro (microserviço próprio; toda tela passa pelo portão do PIN).
  // Mesmos paths do web para os deep links casarem 1:1.
  static const String financeiro = FinanceRoutes.index;
  static const String financeiroMeuDashboard = FinanceRoutes.meuDashboard;

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
  // Roleta de SDRs (web: "Disponibilidade dos SDRs" na barra do WhatsApp).
  static const String sdrRoulette = '/sdr/roleta';

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
    // SANITIZA a rota: tira query string e fragmento antes de casar/extrair
    // ids. Sem isto, um nome de rota com query (`/kanban/task/{id}?teamId=…`,
    // formato de actionUrl do web) faz o `split('/')` devolver o id SUJO —
    // e a chamada de API vira `/kanban/tasks/{id}?teamId=…/fields`, o erro
    // "Cannot GET …" que o usuário via ao abrir a negociação pela
    // notificação. Nenhuma rota daqui lê query params, então cortar é
    // seguro para TODAS as rotas com id no path.
    final rawName = settings.name;
    final routeName = rawName == null
        ? null
        : rawName.split('?').first.split('#').first;

    // Conta bloqueada (assinatura vencida/suspensa ou plano sem CRM): fora
    // das rotas liberadas, abre a tela de bloqueio em vez de uma tela que só
    // daria 403 (NEW-01/NEW-02). Vale para drawer, deep link e push.
    final blockedTarget =
        SubscriptionAccessGate.instance.routeOverride(routeName);
    if (blockedTarget != null) {
      // Plano só Financeiro: a "Home" (e qualquer rota de CRM) abre o Meu
      // Financeiro em vez de uma tela de bloqueio.
      if (FinanceRoutes.owns(blockedTarget)) {
        return _buildRoute(
          FinanceRoutes.pageFor(blockedTarget),
          RouteSettings(name: blockedTarget, arguments: settings.arguments),
        );
      }
      return _buildRoute(
        AccessBlockedPage(decision: SubscriptionAccessGate.instance.decision),
        RouteSettings(name: blockedTarget, arguments: settings.arguments),
      );
    }

    if (routeName == subscriptionRequired) {
      return _buildRoute(
        const AccessBlockedPage(
          decision: AccessGateDecision.subscriptionRequired,
        ),
        settings,
      );
    } else if (routeName == systemUnavailable) {
      return _buildRoute(
        const AccessBlockedPage(decision: AccessGateDecision.systemUnavailable),
        settings,
      );
    } else if (routeName == crmUnavailable) {
      return _buildRoute(
        const AccessBlockedPage(decision: AccessGateDecision.crmNotIncluded),
        settings,
      );
    } else if (routeName == mySubscription) {
      return _buildRoute(const SubscriptionPage(), settings);
    } else if (routeName == subscriptionPlans) {
      return _buildRoute(const SubscriptionPlansPage(), settings);
    } else if (routeName == subscriptionManage) {
      return _buildRoute(const SubscriptionManagementPage(), settings);
    } else if (routeName != null &&
        routeName.startsWith('$subscriptionManage/')) {
      final id = routeName.substring(subscriptionManage.length + 1);
      if (id.isNotEmpty && !id.contains('/')) {
        final item = settings.arguments;
        return _buildRoute(
          SubscriptionDetailsPage(
            subscriptionId: id,
            initialItem: item is AdminSubscriptionItem ? item : null,
          ),
          settings,
        );
      }
    }

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
    } else if (routeName == AppRoutes.calendarSchedule) {
      // IMPORTANTE: deve vir ANTES do startsWith('/calendar/') genérico,
      // senão "horarios" é tratado como action de edit/details.
      return _buildRoute(const ScheduleSettingsPage(), settings);
    } else if (routeName == AppRoutes.calendarInvites) {
      // IMPORTANTE: também ANTES do startsWith('/calendar/') genérico.
      // O chamador deve recarregar a agenda no `.then()` da navegação —
      // convites aceitos criam compromissos novos (ver doc da página).
      return _buildRoute(const AppointmentInvitesPage(), settings);
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
      // `?tab=` (link do web, ex.: `?tab=updates`) abre o detalhe na aba.
      final routeUri = Uri.parse(routeName);
      final segments = routeUri.path.split('/');
      if (segments.length >= 3) {
        final id = segments[2];
        if (segments.length == 3) {
          // Detalhes: /properties/:id
          final args = settings.arguments;
          final initialProperty = args is Map<String, dynamic>
              ? args['property'] as Property?
              : null;
          return _buildRoute(
            PropertyDetailsPage(
              propertyId: id,
              initialProperty: initialProperty,
              initialTab: routeUri.queryParameters['tab'],
            ),
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
      return _buildRoute(
        _guarded(const InspectionsPage(),
            module: 'vistoria', permission: 'inspection:view'),
        settings,
      );
    } else if (routeName == AppRoutes.inspectionCreate) {
      return _buildRoute(
        _guarded(const CreateInspectionPage(),
            module: 'vistoria', permission: 'inspection:create'),
        settings,
      );
    } else if (routeName != null && routeName.startsWith('/inspections/')) {
      final segments = routeName.split('/');
      if (segments.length >= 3) {
        final id = segments[2];
        if (segments.length == 3) {
          // Detalhes: /inspections/:id
          return _buildRoute(
            _guarded(InspectionDetailsPage(inspectionId: id),
                module: 'vistoria', permission: 'inspection:view'),
            settings,
          );
        } else if (segments.length == 4 && segments[3] == 'edit') {
          // Edição: /inspections/:id/edit
          return _buildRoute(
            _guarded(EditInspectionPage(inspectionId: id),
                module: 'vistoria', permission: 'inspection:update'),
            settings,
          );
        }
      }
    } else if (routeName == AppRoutes.keys) {
      return _buildRoute(
        _guarded(const KeysPage(),
            module: 'key_control', permission: 'key:view'),
        settings,
      );
    } else if (routeName == AppRoutes.keyCreate) {
      return _buildRoute(
        _guarded(const CreateKeyPage(),
            module: 'key_control', permission: 'key:create'),
        settings,
      );
    } else if (routeName != null && routeName.startsWith('/keys/')) {
      final segments = routeName.split('/');
      if (segments.length >= 4 && segments[3] == 'edit') {
        final id = segments[2];
        return _buildRoute(
          _guarded(CreateKeyPage(keyId: id),
              module: 'key_control', permission: 'key:update'),
          settings,
        );
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
      // M-4: `ModuleRoute sale_forms` + `PermissionRoute view_dashboard
      // noRoleBypass` do web. O `PermissionRoute` do app já é o noRoleBypass:
      // só master pula o módulo e o bypass de papel é o do back.
      return _buildRoute(
        _guarded(
          const SaleFormsDashboardPage(),
          module: 'sale_forms',
          permission: 'sale_form:view_dashboard',
        ),
        settings,
      );
    } else if (routeName == AppRoutes.saleFormsPendingSignatures) {
      return _buildRoute(
        const PermissionRoute(
          permission: 'sale_form:view',
          child: SaleFormPendingSignaturesPage(),
        ),
        settings,
      );
    } else if (routeName == AppRoutes.saleFormNew) {
      // V-L1: `/fichas-venda/nova?propostaId=X` (aviso "proposta finalizada").
      // A permissão (`sale_form:create`) é conferida dentro do fluxo, que
      // espera as permissões carregarem na abertura a frio.
      final proposalId = rawName == null
          ? ''
          : (Uri.tryParse(rawName)?.queryParameters['proposalId'] ?? '')
              .trim();
      if (proposalId.isEmpty) {
        return _buildRoute(const SaleFormsPage(), settings);
      }
      return _buildRoute(
        RouteActionLauncher(
          action: (ctx) => abrirNovaFichaDaProposta(ctx, proposalId),
          fallbackRoute: AppRoutes.saleForms,
        ),
        settings,
      );
    } else if (routeName != null && routeName.startsWith('/sale-forms/')) {
      // Detalhe: /sale-forms/:id (notificações de ficha de venda, 25/09/2026).
      // `dashboard` já casou na igualdade acima; qualquer outro segmento
      // único é id de ficha.
      final segments = routeName.split('/');
      // /sale-forms/:id/edit — `/fichas-venda/:id/editar` (sale_form:update).
      if (segments.length == 4 &&
          segments[2].isNotEmpty &&
          segments[3] == 'edit') {
        return _buildRoute(
          _guarded(
            CreateSaleFormPage(saleFormId: segments[2]),
            module: 'sale_forms',
            permission: 'sale_form:update',
          ),
          settings,
        );
      }
      if (segments.length == 3 && segments[2].isNotEmpty) {
        // V-L11: o web guarda o detalhe com `sale_form:view`.
        return _buildRoute(
          _guarded(
            SaleFormDetailPage(saleFormId: segments[2]),
            module: 'sale_forms',
            permission: 'sale_form:view',
          ),
          settings,
        );
      }
    } else if (routeName == AppRoutes.proposals) {
      return _buildRoute(const ProposalsPage(), settings);
    } else if (routeName == AppRoutes.proposalCreate) {
      return _buildRoute(const CreateProposalPage(), settings);
    } else if (routeName == AppRoutes.proposalNew) {
      // V-L12: `/fichas-proposta/nova` — mesmo fluxo do botão da lista
      // (permissão + rascunho), não a tela crua.
      return _buildRoute(
        _guarded(
          const RouteActionLauncher(
            action: abrirNovaProposta,
            fallbackRoute: AppRoutes.proposals,
          ),
          module: 'sale_forms',
          permission: 'proposal:create',
        ),
        settings,
      );
    } else if (routeName == AppRoutes.proposalsDashboard) {
      // M-4: idem dashboard de venda (`proposal:view_dashboard`).
      return _buildRoute(
        _guarded(
          const ProposalsDashboardPage(),
          module: 'sale_forms',
          permission: 'proposal:view_dashboard',
        ),
        settings,
      );
    } else if (routeName != null &&
        routeName.startsWith('/proposals/')) {
      final segments = routeName.split('/');
      if (segments.length == 4 && segments[3] == 'edit') {
        final id = segments[2];
        if (id.isNotEmpty) {
          // P-C1: `/fichas-proposta/:id/editar` exige `proposal:update`.
          return _buildRoute(
            _guarded(
              CreateProposalPage(proposalId: id),
              module: 'sale_forms',
              permission: 'proposal:update',
            ),
            settings,
          );
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
      final args = settings.arguments as Map<String, dynamic>?;
      return _buildRoute(
        CheckInPage(startCheckout: args?['checkout'] == true),
        settings,
      );
    } else if (routeName == AppRoutes.checkInCheckout) {
      // Alvo direto do deep link — mesmo destino da rota acima com o
      // checkout armado.
      return _buildRoute(const CheckInPage(startCheckout: true), settings);
    } else if (routeName == AppRoutes.checkInList) {
      return _buildRoute(const CheckInListPage(), settings);
    } else if (routeName == AppRoutes.checkInManage) {
      return _buildRoute(const CheckInManagePage(), settings);
    } else if (routeName == AppRoutes.visits) {
      return _buildRoute(const VisitsPage(), settings);
    } else if (routeName == AppRoutes.visitReports) {
      // Gestão de Visitas (29/09/2026): mesma tela, aberta em scope=all.
      return _buildRoute(const VisitsPage(openManagement: true), settings);
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
      return _buildRoute(
        _guarded(const AssetsPage(),
            module: 'asset_management', permission: 'asset:view'),
        settings,
      );
    } else if (routeName == AppRoutes.assetCreate) {
      return _buildRoute(
        _guarded(const CreateAssetPage(),
            module: 'asset_management', permission: 'asset:create'),
        settings,
      );
    } else if (routeName != null && routeName.startsWith('/assets/')) {
      final segments = routeName.split('/');
      if (segments.length >= 3) {
        final id = segments[2];
        if (segments.length == 3 && id.isNotEmpty) {
          return _buildRoute(
            _guarded(AssetDetailsPage(assetId: id),
                module: 'asset_management', permission: 'asset:view'),
            settings,
          );
        } else if (segments.length == 4 && segments[3] == 'edit') {
          return _buildRoute(
            _guarded(CreateAssetPage(assetId: id),
                module: 'asset_management', permission: 'asset:update'),
            settings,
          );
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
      return _buildRoute(
        _guarded(const CollectionPage(),
            module: 'credit_and_collection', permission: 'collection:view'),
        settings,
      );
    } else if (routeName == AppRoutes.collectionRules) {
      return _buildRoute(
        _guarded(const CollectionRulesPage(),
            module: 'credit_and_collection', permission: 'collection:manage'),
        settings,
      );
    } else if (routeName == AppRoutes.collectionRuleCreate) {
      return _buildRoute(
        _guarded(const CollectionRuleFormPage(),
            module: 'credit_and_collection', permission: 'collection:manage'),
        settings,
      );
    } else if (routeName != null &&
        routeName.startsWith('/collection/rules/')) {
      // /collection/rules/:id — edição de régua
      final segments = routeName.split('/');
      if (segments.length == 4 && segments[3].isNotEmpty) {
        return _buildRoute(
          _guarded(CollectionRuleFormPage(ruleId: segments[3]),
              module: 'credit_and_collection',
              permission: 'collection:manage'),
          settings,
        );
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
    } else if (routeName == AppRoutes.sdrRoulette) {
      return _buildRoute(
        const PermissionRoute(
          permission: 'whatsapp:manage_config',
          child: SdrRoulettePage(),
        ),
        settings,
      );
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
    } else if (FinanceRoutes.owns(routeName)) {
      // /financeiro e /financeiro/* — portão de módulo + PIN embutido.
      // Com a query (`?venda=`, `?saleId=`): o Financeiro lê.
      return _buildRoute(FinanceRoutes.pageFor(rawName ?? routeName!), settings);
    }

    // Rota não encontrada
    return _buildRoute(
      const Scaffold(body: Center(child: Text('Página não encontrada'))),
      settings,
    );
  }

  /// Guarda de módulo + permissão da rota, igual ao `ModuleRoute` +
  /// `PermissionRoute` do web (transv-25, 03/10/2026): sem acesso, a tela de
  /// "sem permissão"/"fora do plano" em vez de uma tela que só daria 403.
  static Widget _guarded(
    Widget child, {
    String? module,
    String? permission,
  }) {
    return PermissionRoute(
      module: module,
      permission: permission,
      child: child,
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
    // Troca de ABA (barra inferior / voltar da raiz para a Home): sem
    // animação, como a barra de abas nativa. Antes a tela nova deslizava por
    // cima da atual — com a barra inferior junto, como se cada tela tivesse a
    // sua — e sempre do mesmo lado, mesmo indo para uma aba à esquerda
    // (relato do Edson, 01/10/2026). Empilhar telas (abrir detalhe) continua
    // com a transição normal abaixo.
    if (_proximaEhTrocaDeAba) {
      _proximaEhTrocaDeAba = false;
      return PageRouteBuilder<dynamic>(
        settings: settings,
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      );
    }

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
