/// Rotas internas da feature Condomínios & Empreendimentos.
///
/// Mantidas aqui (e não em `AppRoutes`) porque arquivos compartilhados não
/// são editados pela feature — a fiação central replica estes nomes no
/// `app_routes.dart` (ver manifest da feature).
class CondominiumRoutes {
  CondominiumRoutes._();

  static const String condominiums = '/condominiums';
  static const String condominiumCreate = '/condominiums/create';
  static String condominiumEdit(String id) => '/condominiums/$id/edit';

  static const String developments = '/developments';
  static const String developmentCreate = '/developments/create';
  static String developmentDetails(String id) => '/developments/$id';
  static String developmentEdit(String id) => '/developments/$id/edit';
}
