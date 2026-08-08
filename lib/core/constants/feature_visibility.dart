/// Áreas do app temporariamente OCULTAS da UI (decisão de produto).
///
/// Ocultar ≠ deletar: rotas, páginas e serviços continuam no código — apenas
/// os pontos de entrada (tiles, badges, itens de menu, deep links) somem.
/// Para reativar uma área, basta voltar o getter para `true`: todos os
/// gates de permissão/módulo originais foram preservados atrás do flag.
///
/// Getters (e não `const bool`) de propósito: o analyzer não constant-folda,
/// então nenhum `if (flag)` vira warning de dead_code espalhado pelo app.
class FeatureVisibility {
  FeatureVisibility._();

  /// Ofertas de imóveis (listagem, detalhe de oferta, atalhos e badges).
  static bool get offersEnabled => false;

  /// Matches (por imóvel e por cliente: telas, pills, badges e menus).
  static bool get matchesEnabled => false;
}
