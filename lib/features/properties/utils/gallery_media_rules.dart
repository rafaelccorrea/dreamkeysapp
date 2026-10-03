import '../../../shared/services/property_service.dart';

/// Regras da galeria do imóvel — os mesmos limites do web
/// (`galleryApi.ts`: `GALLERY_MAX_VIDEO_FILE_BYTES`,
/// `GALLERY_MAX_VIDEO_DURATION_SECONDS`) e do back
/// (`shared/utils/allowed-image-upload.ts`).

/// Vídeo do imóvel: até 150 MB.
const int kGalleryMaxVideoBytes = 150 * 1024 * 1024;

/// Vídeo do imóvel: até 1:40 (100 s). O web aceita meio segundo de folga.
const int kGalleryMaxVideoDurationSeconds = 100;

/// Extensões aceitas pelo back para o vídeo (MP4, MOV, WebM).
const List<String> kGalleryVideoExtensions = ['mp4', 'mov', 'webm'];

String _ext(String fileName) {
  final name = fileName.trim().toLowerCase();
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1);
}

/// MIME do vídeo pela extensão (`video/mp4`, `video/quicktime`,
/// `video/webm`); `null` quando não é um formato aceito.
String? galleryVideoMimeType(String fileName) {
  switch (_ext(fileName)) {
    case 'mp4':
    case 'm4v':
      return 'video/mp4';
    case 'mov':
    case 'qt':
      return 'video/quicktime';
    case 'webm':
      return 'video/webm';
  }
  return null;
}

/// "1:40" a partir de segundos (o `formatVideoDuration` do web).
String formatGalleryVideoDuration(num seconds) {
  final total = seconds.isFinite && seconds > 0 ? seconds.round() : 0;
  final m = total ~/ 60;
  final s = total % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Mensagem do web quando o `<video>` não carrega para medir a duração.
const String kGalleryVideoUnreadableMessage =
    'Não foi possível processar este vídeo. Tente outro arquivo.';

/// Valida o vídeo antes do envio, com as mensagens do web. `null` = ok.
/// Com [requireDuration], duração nula (não deu para medir) BLOQUEIA o envio,
/// como o web — o back não mede, então sem ela o limite de 1:40 não seria
/// checado. Sem a flag, só formato e tamanho (checagem rápida, antes de
/// abrir o arquivo).
String? validateGalleryVideo({
  required String fileName,
  required int sizeBytes,
  double? durationSeconds,
  bool requireDuration = false,
}) {
  if (galleryVideoMimeType(fileName) == null) {
    return '$fileName: envie um arquivo de vídeo (MP4, MOV ou WebM)';
  }
  if (sizeBytes > kGalleryMaxVideoBytes) {
    return 'Vídeo muito grande (máximo '
        '${kGalleryMaxVideoBytes ~/ (1024 * 1024)}MB)';
  }
  if (requireDuration &&
      (durationSeconds == null ||
          !durationSeconds.isFinite ||
          durationSeconds <= 0)) {
    return kGalleryVideoUnreadableMessage;
  }
  if (durationSeconds != null &&
      durationSeconds > kGalleryMaxVideoDurationSeconds + 0.5) {
    return 'Vídeo muito longo (${formatGalleryVideoDuration(durationSeconds)}).'
        ' Máximo de 1:40 (100s).';
  }
  return null;
}

/// Move o item de [from] para a posição final [to] (as setas do web trocam
/// com o vizinho: `to = from ± 1`; o arrasto usa o destino já ajustado do
/// `onReorderItem`). Índices fora da faixa devolvem a lista como está.
List<T> moveGalleryItem<T>(List<T> items, int from, int to) {
  if (from < 0 || from >= items.length || to < 0 || to >= items.length) {
    return List<T>.of(items);
  }
  if (from == to) return List<T>.of(items);
  final out = List<T>.of(items);
  final moved = out.removeAt(from);
  out.insert(to, moved);
  return out;
}

/// Corpo do `PUT /gallery/reorder`: `{ imageIds }` só com as FOTOS, na nova
/// ordem (o vídeo fica à parte, como no web). Ignora ids vazios e repetidos.
Map<String, dynamic> galleryReorderPayload(List<PropertyImage> media) {
  final seen = <String>{};
  final ids = <String>[];
  for (final m in media) {
    if (m.isVideo) continue;
    final id = m.id.trim();
    if (id.isEmpty || !seen.add(id)) continue;
    ids.add(id);
  }
  return {'imageIds': ids};
}

/// Fotos na ordem de exibição (sem o vídeo) — base da tela de gestão.
List<PropertyImage> galleryPhotosOf(List<PropertyImage> media) => media
    .where((m) => !m.isVideo && m.url.trim().isNotEmpty)
    .toList(growable: false);

/// O vídeo do imóvel (o back mantém só um).
PropertyImage? galleryVideoOf(List<PropertyImage> media) {
  for (final m in media) {
    if (m.isVideo && m.url.trim().isNotEmpty) return m;
  }
  return null;
}
