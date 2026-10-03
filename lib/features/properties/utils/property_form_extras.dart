import '../../../shared/services/property_service.dart';

// ─── Permuta ──────────────────────────────────────────────────────────────
// Espelho de `utils/propertyExchange.ts` do web: no cadastro e na edição é
// obrigatório responder Sim/Não; com Sim, o valor máximo (> 0). O back
// (`normalizeExchangeFields`) recusa "aceita" sem valor.

/// Resposta da permuta no formulário: `null` = ainda não respondeu (imóvel
/// antigo), `true` = aceita, `false` = não aceita.
String? exchangeValidationError({
  required bool? acceptsExchange,
  required double? exchangeMaxValue,
}) {
  if (acceptsExchange == null) return 'Informe se o imóvel aceita permuta.';
  if (acceptsExchange && !((exchangeMaxValue ?? 0) > 0)) {
    return 'Informe o valor máximo aceito na permuta.';
  }
  return null;
}

/// Chaves do payload (`acceptsExchange` + `exchangeMaxValue`), conferidas no
/// `CreatePropertyDto`/`UpdatePropertyDto` atuais. Sem resposta, nada vai.
Map<String, dynamic> exchangeApiFields({
  required bool? acceptsExchange,
  required double? exchangeMaxValue,
}) {
  if (acceptsExchange == null) return const {};
  if (!acceptsExchange) {
    return const {'acceptsExchange': false, 'exchangeMaxValue': null};
  }
  final v = exchangeMaxValue ?? 0;
  return {'acceptsExchange': true, 'exchangeMaxValue': v > 0 ? v : null};
}

// ─── Cômodos extras (catálogo) ──────────────────────────────────────────────
// Espelho de `utils/propertyCatalog.ts` do web.

String _norm(String s) => s.trim().toLowerCase();

/// Cômodos a exibir: os do catálogo + os já gravados no imóvel que saíram do
/// catálogo (não somem da edição nem são apagados sem querer).
List<String> extraRoomNames(
  List<PropertyCatalogItem> catalogRooms,
  List<PropertyExtraRoom> current,
) {
  final names = <String>[];
  final seen = <String>{};
  for (final r in catalogRooms) {
    if (seen.add(_norm(r.name))) names.add(r.name);
  }
  for (final r in current) {
    if (seen.add(_norm(r.name))) names.add(r.name);
  }
  return names;
}

/// Quantidade gravada de [name] (0 quando não há).
int extraRoomQuantity(List<PropertyExtraRoom> current, String name) {
  for (final r in current) {
    if (_norm(r.name) == _norm(name)) return r.quantity;
  }
  return 0;
}

/// Nova lista com [name] na quantidade [qty] (teto 99, o `@Max` do DTO);
/// 0 tira o cômodo da lista.
List<PropertyExtraRoom> setExtraRoomQuantity(
  List<PropertyExtraRoom> current,
  String name,
  int qty,
) {
  final q = qty.clamp(0, 99);
  final idx = current.indexWhere((r) => _norm(r.name) == _norm(name));
  final next = List<PropertyExtraRoom>.from(current);
  if (q <= 0) {
    if (idx >= 0) next.removeAt(idx);
    return next;
  }
  final room = PropertyExtraRoom(name: name, quantity: q);
  if (idx >= 0) {
    next[idx] = room;
  } else {
    next.add(room);
  }
  return next;
}

/// Mesmo conteúdo (nome + quantidade, sem olhar a ordem).
bool sameExtraRooms(List<PropertyExtraRoom> a, List<PropertyExtraRoom> b) {
  if (a.length != b.length) return false;
  for (final r in a) {
    if (extraRoomQuantity(b, r.name) != r.quantity) return false;
  }
  return true;
}

/// Características fixas + infraestrutura da empresa, sem repetir nome.
List<String> mergeFeatureOptions(
  List<String> base,
  List<PropertyCatalogItem> infrastructure,
) {
  final seen = base.map(_norm).toSet();
  return [
    ...base,
    for (final i in infrastructure)
      if (seen.add(_norm(i.name))) i.name,
  ];
}
