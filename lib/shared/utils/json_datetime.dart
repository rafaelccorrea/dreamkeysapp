/// Parse de datas vindas da API (ISO, null, string "null", vazio).
DateTime? tryParseApiDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  final s = value.toString().trim();
  if (s.isEmpty || s == 'null') return null;
  return DateTime.tryParse(s);
}

/// Obrigatório: usa [fallback] ou agora se a API omitir o campo.
DateTime parseApiDateTime(
  dynamic value, {
  DateTime? fallback,
}) {
  return tryParseApiDateTime(value) ?? fallback ?? DateTime.now();
}
