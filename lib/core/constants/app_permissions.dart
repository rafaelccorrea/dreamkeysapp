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
}
