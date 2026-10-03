/// Mídia de origem da ficha de venda — espelha
/// `constants/midiasOrigemFichaVenda.ts` do web.
///
/// O valor gravado em `mediaSource` é o próprio rótulo. O web mostra a lista
/// oficial + o legado (sem duplicar equivalentes) e mantém o valor gravado
/// mesmo quando ele não está em nenhuma das duas listas.
library;

/// Lista oficial (`MIDIAS_ORIGEM_FICHA_VENDA`).
const List<String> kSaleFormMediaSourcesOficiais = [
  'REMARKETING',
  'PAP',
  'RELACIONAMENTO',
  'ANUNCIO PAGO',
  'INDICAÇÃO',
  'PLANTAO EXTERNO/INTERNO',
  'CHAVES NA MAO',
  'SITE',
  'GRUPO ZAP',
  'FEIRAS E EVENTOS',
  'LISTA FRIA',
  'ANUNCIO PAGO (CAMPANHA PESSOAL)',
  'ANUNCIO PAGO (CAMPANHA DE CONVERSA)',
  'INSTAGRAM PESSOAL',
  'CHATPRO - LEAD ORGANICO',
  'TELEFONE IMOBILIARIA',
  'DISPAROS MANYCHAT',
  'PLACA',
  'INSTAGRAM ORGANICO',
  'GOOGLE ADS',
];

/// Valores das fichas antigas (`MIDIAS_ORIGEM_FICHA_VENDA_LEGADO`).
const List<String> kSaleFormMediaSourcesLegado = [
  'Instagram',
  'Facebook',
  'Google',
  'Google Ads',
  'Facebook Ads',
  'LinkedIn',
  'YouTube',
  'TikTok',
  'WhatsApp',
  'Indicação',
  'Site',
  'Jornal',
  'Rádio',
  'TV',
  'indicacao',
  'internet',
  'placa',
  'fachada',
  'whatsapp',
  'instagram',
  'facebook',
  'google',
  'outro',
];

/// `chaveMidiaOrigemFicha`: ignora caixa e colapsa espaços.
String saleFormMediaSourceKey(String s) =>
    s.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();

/// `MIDIAS_ORIGEM_FICHA_VENDA_COMPLETA`: oficial + legado sem equivalentes.
final List<String> kSaleFormMediaSourcesCompleta = () {
  final out = <String>[...kSaleFormMediaSourcesOficiais];
  final chaves = out.map(saleFormMediaSourceKey).toSet();
  for (final leg in kSaleFormMediaSourcesLegado) {
    if (chaves.add(saleFormMediaSourceKey(leg))) out.add(leg);
  }
  return List<String>.unmodifiable(out);
}();

/// Valor gravado a manter na edição: o próprio texto (aparado), qualquer que
/// seja — inclusive legado e o `'DISPAROS'` que o app gravava antes. Vazio
/// vira `null` (campo sem resposta).
String? saleFormStoredMediaSource(String? stored) {
  final s = (stored ?? '').trim();
  return s.isEmpty ? null : s;
}

/// Opções do select: a lista completa e, se o valor atual não for
/// equivalente a nenhuma delas, ele próprio no fim (para não sumir ao editar).
List<String> saleFormMediaSourceOptions(String? current) {
  final c = saleFormStoredMediaSource(current);
  if (c == null || kSaleFormMediaSourcesCompleta.contains(c)) {
    return kSaleFormMediaSourcesCompleta;
  }
  return [...kSaleFormMediaSourcesCompleta, c];
}

/// Rótulo da tela (`displayMidiaOrigemFichaVenda`): maiúsculas, valor
/// gravado intacto.
String saleFormMediaSourceLabel(String stored) => stored.trim().toUpperCase();
