import '../../../shared/services/module_access_service.dart';

/// Módulo, permissões e rotas dos Relatórios de Visita.
///
/// Strings EXATAS do backend (`ModuleType.VISIT_REPORT` + `Permission.VISIT_*`
/// no imobx/NestJS) e das rotas do web (`kanban.routes.tsx`). Mantidas locais
/// à feature — a fiação central migra o que precisar para
/// `app_permissions.dart` / `app_routes.dart`.
class VisitReportAccess {
  VisitReportAccess._();

  // Módulo da empresa.
  static const String module = 'visit_report';

  // Permissões (1:1 com `Permission.VISIT_*` do backend).
  static const String view = 'visit:view';
  static const String create = 'visit:create';
  static const String update = 'visit:update';
  static const String delete = 'visit:delete';

  /// Gestão: habilita `scope=all` (todas as visitas da empresa).
  static const String manage = 'visit:manage';

  /// Ações do módulo que o menu do web conta (29/09/2026). O
  /// `canShowDrawerItem` do web (`drawerPermissionRules.ts`, categoria
  /// `visit`) só mostra a tela para quem, além de VER, pode FAZER alguma
  /// coisa nela — quem só enxerga, sem nenhuma ação, não ganha o item.
  static const List<String> menuActionPermissions = [
    create,
    update,
    delete,
    manage,
  ];

  /// Item "Lista de Visitas" do menu (29/09/2026). O web mostra o grupo
  /// Visitas com o módulo `visit_report` ligado; a lista exige `visit:view`
  /// (é o que a rota /visits do web cobra) e ao menos uma ação do módulo.
  /// Antes o app escondia o grupo achando que o web também escondia, e o
  /// corretor ficava sem como registrar visita pelo app.
  static bool get canSeeListInMenu {
    final access = ModuleAccessService.instance;
    return access.hasCompanyModule(module) &&
        access.hasPermission(view) &&
        access.hasAnyPermission(menuActionPermissions);
  }

  /// Item "Gestão de Visitas" do menu (29/09/2026): módulo + `visit:manage`.
  /// É a permissão que a rota /visit-reports do web exige e a que libera o
  /// `scope=all` no back — sem ela o item levaria a uma tela bloqueada.
  static bool get canSeeManagementInMenu {
    final access = ModuleAccessService.instance;
    return access.hasCompanyModule(module) && access.hasPermission(manage);
  }
}

/// Rotas nomeadas da feature (padrão do `AppRoutes` — a fiação central copia
/// estas constantes para `app_routes.dart`).
class VisitReportRoutes {
  VisitReportRoutes._();

  static const String list = '/visits';
  static const String createReport = '/visits/create';
  static String details(String id) => '/visits/$id';
  static String edit(String id) => '/visits/$id/edit';

  /// Gestão de Visitas (29/09/2026): a mesma lista aberta na visão da
  /// empresa, como a rota /visit-reports do web. Fica FORA do prefixo
  /// /visits/ de propósito, para não ser lida como id de relatório.
  static const String management = '/visit-reports';
}
