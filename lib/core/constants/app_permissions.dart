/// Constantes de permissões usadas na app, alinhadas 1:1 com o backend
/// (`src/enums/permission.enum.ts`) e o front web (`imobx-front`).
///
/// Use estas constantes em vez de strings literais para evitar typo entre
/// implementações. O `ModuleAccessService.hasPermission(...)` faz a leitura
/// exata desses valores no payload de `GET /permissions/my-permissions`.
class AppPermissions {
  AppPermissions._();

  // ─── Property: visão / CRUD ────────────────────────────────────────────
  static const String propertyView = 'property:view';
  static const String propertyCreate = 'property:create';
  static const String propertyUpdate = 'property:update';
  static const String propertyDelete = 'property:delete';
  static const String propertyExport = 'property:export';

  // ─── Property: fila de aprovação ───────────────────────────────────────
  /// Aprovar disponibilidade (item sai da fila e fica `available`).
  static const String propertyApproveAvailability =
      'property:approve_availability';
  /// Recusar disponibilidade (item permanece em `pending_approval` com
  /// motivo + timestamp de recusa, aguardando reenvio para nova análise).
  static const String propertyRejectAvailability =
      'property:reject_availability';
  /// Aprovar publicação no site (item passa a `isAvailableForSite: true`).
  static const String propertyApprovePublication =
      'property:approve_publication';
  /// Recusar publicação no site (item permanece `available` mas privado).
  static const String propertyRejectPublication =
      'property:reject_publication';
  /// Acesso à tela de configurações da fila (regras da empresa, aprovadores).
  static const String propertyManageApprovalSettings =
      'property:manage_approval_settings';

  // ─── Check-in por localização ──────────────────────────────────────────
  /// Permite fazer / desfazer o próprio check-in e check-out.
  static const String checkInDo = 'check_in:do';
  /// Permite ver o histórico (lista) de check-ins (próprios e da equipe).
  static const String checkInView = 'check_in:view';
  /// Permite editar configurações (raio, duração, localização da empresa)
  /// e desfazer check-in de outros usuários.
  static const String checkInManageSettings = 'check_in:manage_settings';

  // ─── Conjuntos úteis para gating de UI ─────────────────────────────────
  /// Permissões que liberam a entrada do menu/atalho da Fila de Aprovação.
  /// Espelha exatamente a `customPermission` do `Drawer.tsx` no web:
  /// view OR create OR approve_availability OR approve_publication OR
  /// manage_approval_settings (com bypass admin/master no `hasAnyPermission`).
  static const List<String> approvalQueueMenu = [
    propertyView,
    propertyCreate,
    propertyApproveAvailability,
    propertyApprovePublication,
    propertyManageApprovalSettings,
  ];

  /// Permissões mínimas para conseguir abrir a tela em si (paridade com
  /// `<PermissionRoute permissions={['property:view', 'property:create']}>`
  /// do `App.tsx` web — `requireAll={false}`).
  static const List<String> approvalQueueRoute = [
    propertyView,
    propertyCreate,
  ];

  // ─── Users (Colaboradores → Usuários) ──────────────────────────────────
  static const String userView = 'user:view';
  static const String userCreate = 'user:create';
  static const String userUpdate = 'user:update';
  static const String userDelete = 'user:delete';
  static const String userTransfer = 'user:transfer';

  /// Permissões que liberam a entrada do menu/atalho de Usuários no drawer.
  /// Espelha o `customPermission` do `Drawer.tsx` web:
  /// `user:view` AND (`create` OR `update` OR `delete`). A checagem prática
  /// fica como "qualquer ação de gestão"; o módulo `user_management` e o
  /// bypass admin/master/manager continuam aplicáveis.
  static const List<String> userManageMenu = [
    userCreate,
    userUpdate,
    userDelete,
  ];

  // ─── Fichas de Venda (sale_form:*) ─────────────────────────────────────
  static const String saleFormView = 'sale_form:view';
  static const String saleFormViewTeam = 'sale_form:view_team';
  static const String saleFormViewAll = 'sale_form:view_all';
  static const String saleFormCreate = 'sale_form:create';
  static const String saleFormUpdate = 'sale_form:update';
  static const String saleFormDelete = 'sale_form:delete';
  static const String saleFormExport = 'sale_form:export';
  static const String saleFormViewDashboard = 'sale_form:view_dashboard';

  /// Permissões que liberam a entrada de Fichas de Venda no drawer
  /// (qualquer visão). Espelha o gating do web.
  static const List<String> saleFormMenu = [
    saleFormView,
    saleFormViewTeam,
    saleFormViewAll,
  ];

  // ─── Comissões ─────────────────────────────────────────────────────────
  static const String commissionView = 'commission:view';
  static const String commissionCreate = 'commission:create';
  static const String commissionUpdate = 'commission:update';
  static const String commissionDelete = 'commission:delete';
  static const String commissionCalculate = 'commission:calculate';

  /// Módulo (availableModules da empresa) que libera a entrada de Comissões.
  static const String moduleCommissionManagement = 'commission_management';

  // ─── Teams (Colaboradores → Equipes) ───────────────────────────────────
  static const String teamView = 'team:view';
  static const String teamCreate = 'team:create';
  static const String teamUpdate = 'team:update';
  static const String teamDelete = 'team:delete';
  static const String teamManageMembers = 'team:manage_members';
}
