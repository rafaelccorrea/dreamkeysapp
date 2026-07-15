/// Módulo e permissões do domínio "Meu Site + Link in Bio".
///
/// Strings EXATAS do web (`misc.routes.tsx` + `permission.enum.ts` do imobx):
///   - módulo `public_site_hosting` gate a rota /settings/public-site e
///     /settings/bio-link;
///   - `public_site:view` abre as telas;
///   - `public_site:manage` libera edição/publicação (o backend exige nos
///     PATCH/POST — aqui usamos para travar a UI em vez de esconder).
class PublicSiteAccess {
  PublicSiteAccess._();

  /// Módulo da empresa (`availableModules`) que libera o domínio.
  static const String module = 'public_site_hosting';

  /// Abre as telas Meu Site e Link in Bio.
  static const String permView = 'public_site:view';

  /// Editar configuração, publicar/despublicar, salvar domínio e links.
  static const String permManage = 'public_site:manage';
}
