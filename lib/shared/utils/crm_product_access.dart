/// Plano "só Financeiro" (back, commits `4d56e505`/`848dac00`, 02/10/2026).
///
/// Espelho de `hasCrmProduct` em `intellisys-CRM-Back/src/enums/module-type.enum.ts`:
/// a empresa tem o produto CRM quando a lista de módulos traz pelo menos um
/// módulo que NÃO é de plataforma, NÃO é add-on e NÃO está oculto. Quem não
/// tem CRM toma 403 do `CrmProductAccessInterceptor` em todas as rotas de CRM
/// (dashboard, kanban, imóveis, clientes, agenda, WhatsApp…) — e o app, que
/// ainda não tem o Financeiro, não teria nada útil a mostrar.
library;

/// Módulos de plataforma: valem em qualquer plano, inclusive no só-Financeiro.
const Set<String> kPlatformModules = {
  'user_management',
  'company_management',
  'team_management',
};

/// Add-ons pagos à parte (não concedem o produto CRM sozinhos).
const Set<String> kAddonModules = {
  'rental_management',
  'financial_management',
  'whatsapp_ai',
};

/// Módulos ocultos/indisponíveis (inclui o alias `mcmv_management`).
const Set<String> kHiddenModules = {
  'gamification',
  'mcmv',
  'mcmv_management',
};

String _normalizeModuleCode(String code) =>
    code.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');

/// A lista de módulos inclui o produto CRM? (idêntico ao back)
bool hasCrmProduct(Iterable<String>? modules) {
  if (modules == null) return false;
  for (final raw in modules) {
    final code = _normalizeModuleCode(raw);
    if (code.isEmpty) continue;
    if (kPlatformModules.contains(code)) continue;
    if (kAddonModules.contains(code)) continue;
    if (kHiddenModules.contains(code)) continue;
    return true;
  }
  return false;
}

/// A empresa comprovadamente NÃO tem CRM? Mesma regra do interceptor do back
/// (`empresaSemCrm`): lista de módulos NÃO vazia e sem módulo de CRM. Lista
/// vazia/nula (legado ou ainda não carregada) nunca bloqueia. Master passa.
bool companyLacksCrmProduct(Iterable<String>? modules, {String? role}) {
  if ((role ?? '').trim().toLowerCase() == 'master') return false;
  if (modules == null) return false;
  final list = modules.where((m) => m.trim().isNotEmpty).toList();
  if (list.isEmpty) return false;
  return !hasCrmProduct(list);
}
