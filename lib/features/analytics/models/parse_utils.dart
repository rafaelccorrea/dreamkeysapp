/// Helpers de parse defensivo compartilhados pelos models de Analytics.
/// Toleram null, string numérica, número e formatos mistos vindos da API.
library;

double parseDouble(dynamic v, [double fallback = 0]) {
  if (v == null) return fallback;
  if (v is num) return v.toDouble();
  if (v is String) {
    return double.tryParse(v.replaceAll(',', '.')) ?? fallback;
  }
  return fallback;
}

double? parseDoubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(',', '.'));
  return null;
}

int parseInt(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? parseDouble(v).toInt();
  return fallback;
}

String parseString(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  final s = v.toString().trim();
  return s.isEmpty ? fallback : s;
}

String? parseStringOrNull(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

DateTime? parseDate(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

/// Lista de mapas tipados a partir de qualquer `List` dinâmica.
List<Map<String, dynamic>> parseMapList(dynamic v) {
  if (v is! List) return const [];
  return v
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList(growable: false);
}

/// Lista de strings tolerante (ignora entradas nulas/vazias).
List<String> parseStringList(dynamic v) {
  if (v is! List) return const [];
  return v
      .map((e) => e?.toString().trim() ?? '')
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
}

Map<String, dynamic>? parseMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}

/// Desembrulha respostas `{ success, data: {...} }` do backend; se não houver
/// wrapper, devolve o próprio mapa.
Map<String, dynamic> unwrapData(Map<String, dynamic> json) {
  final data = json['data'];
  if (data is Map) return Map<String, dynamic>.from(data);
  return json;
}
