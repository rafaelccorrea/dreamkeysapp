import '../models/property_change_request.dart';

/// Rótulo curto do imóvel no filtro das solicitações de edição: "Título
/// (CÓD)", só o título, só o código ou "Imóvel" quando nada veio.
String changeRequestPropertyLabel(ChangeRequestPropertyRef p) {
  final title = p.title.trim();
  final code = (p.code ?? '').trim();
  if (title.isNotEmpty && code.isNotEmpty) return '$title ($code)';
  if (title.isNotEmpty) return title;
  if (code.isNotEmpty) return 'Cód. $code';
  return 'Imóvel';
}

/// Opções do filtro por imóvel: sem repetição (por `id`) e em ordem
/// alfabética do rótulo.
List<ChangeRequestPropertyRef> changeRequestPropertyOptions(
  Iterable<ChangeRequestPropertyRef> refs,
) {
  final byId = <String, ChangeRequestPropertyRef>{};
  for (final r in refs) {
    if (r.id.trim().isEmpty) continue;
    byId[r.id] = r;
  }
  final list = byId.values.toList()
    ..sort(
      (a, b) => changeRequestPropertyLabel(a)
          .toLowerCase()
          .compareTo(changeRequestPropertyLabel(b).toLowerCase()),
    );
  return list;
}
