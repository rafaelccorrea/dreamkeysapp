import 'package:http_parser/http_parser.dart' show MediaType;

/// Tipo MIME do anexo da ficha física (venda e proposta), pela extensão.
///
/// O back filtra o upload pelo `mimetype` do arquivo e só aceita
/// `application/pdf`, `image/jpeg`, `image/jpg`, `image/png` e `image/webp`
/// (`sale-forms.controller.ts` / `purchase-proposals.controller.ts`). Sem
/// `contentType`, o `http.MultipartFile` manda `application/octet-stream`
/// e o back recusa com "Tipo inválido. Use PDF, JPEG, PNG ou WEBP.".
///
/// Retorna `null` para extensões fora da lista (o cliente já barra antes).
MediaType? fichaAnexoContentType(String fileName) {
  final name = fileName.split('/').last.split('\\').last;
  final dot = name.lastIndexOf('.');
  final ext = dot >= 0 ? name.substring(dot + 1).trim().toLowerCase() : '';
  switch (ext) {
    case 'pdf':
      return MediaType('application', 'pdf');
    case 'jpg':
    case 'jpeg':
      return MediaType('image', 'jpeg');
    case 'png':
      return MediaType('image', 'png');
    case 'webp':
      return MediaType('image', 'webp');
    default:
      return null;
  }
}
