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
}

/// Rotas nomeadas da feature (padrão do `AppRoutes` — a fiação central copia
/// estas constantes para `app_routes.dart`).
class VisitReportRoutes {
  VisitReportRoutes._();

  static const String list = '/visits';
  static const String createReport = '/visits/create';
  static String details(String id) => '/visits/$id';
  static String edit(String id) => '/visits/$id/edit';
}
