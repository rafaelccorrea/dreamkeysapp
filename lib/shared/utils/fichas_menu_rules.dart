/// Visibilidade dos itens de Fichas no menu lateral — paridade com o
/// `Drawer.tsx` do web (03/10/2026, M-1/M-2/M-3 da auditoria de Fichas).
///
/// Função pura (recebe o checador de permissão e o módulo) para dar teste.
///
/// Regra do web para um item com `permission: X` (`canShowDrawerItem`):
/// alguma VISÃO do módulo + alguma AÇÃO do módulo; e a rota de destino exige
/// `X` exata (`PermissionRoute`). O menu do app usa a interseção das duas —
/// assim o item só aparece para quem consegue abrir a tela (antes bastava
/// `view_team`/`view_all` e a tela respondia "sem acesso").
///
/// Os dashboards (`*:view_dashboard`) estão em `DRAWER_EXACT_PERMISSION_
/// REQUIRED` no web: só a permissão exata libera (`noRoleBypass`).
///
/// O bypass de papel (master/admin) já vem embutido em [has]
/// (`ModuleAccessService.hasPermission`), como no `hasPermission` do web.
class FichasMenuRules {
  FichasMenuRules._();

  static const String module = 'sale_forms';

  static const List<String> saleFormActions = [
    'sale_form:create',
    'sale_form:update',
    'sale_form:delete',
    'sale_form:export',
    'sale_form:manage_mandatory_signers',
  ];

  static const List<String> proposalActions = [
    'proposal:create',
    'proposal:update',
    'proposal:delete',
    'proposal:export',
  ];

  /// "Fichas de venda" e "Assinaturas pendentes" (`sale_form:view`).
  static bool canSeeSaleForms({
    required bool hasModule,
    required bool Function(String permission) has,
  }) =>
      hasModule &&
      has('sale_form:view') &&
      saleFormActions.any(has);

  /// "Fichas de proposta" (`proposal:view`).
  static bool canSeeProposals({
    required bool hasModule,
    required bool Function(String permission) has,
  }) =>
      hasModule && has('proposal:view') && proposalActions.any(has);

  /// "Dash Fichas Venda" (`sale_form:view_dashboard`, exata).
  static bool canSeeSaleFormsDashboard({
    required bool hasModule,
    required bool Function(String permission) has,
  }) =>
      hasModule && has('sale_form:view_dashboard');

  /// "Dash Fichas Proposta" (`proposal:view_dashboard`, exata).
  static bool canSeeProposalsDashboard({
    required bool hasModule,
    required bool Function(String permission) has,
  }) =>
      hasModule && has('proposal:view_dashboard');
}
