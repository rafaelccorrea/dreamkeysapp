// Mídia da conversa do WhatsApp (29/09/2026) — regras puras, sem widget.
//
// A mídia vem do back como URL ASSINADA do S3, válida por 1 h
// (`generatePresignedUrl(key, 3600)` em whatsapp.service.ts), e cada resposta
// de GET /whatsapp/messages assina no máximo 25 mídias. Duas consequências
// que o app não tratava:
//  - a cada releitura da thread (poll de 20 s, socket) as URLs mudam de
//    assinatura e toda imagem recarregava, piscando o carregamento;
//  - depois de 1 h a mídia some ("Imagem indisponível") sem renovar.
// Aqui ficam as leituras da validade da assinatura e os rótulos de arquivo,
// com as mesmas frases do web (utils/whatsappFilaDeAnexos.ts).

// ─── Validade da URL assinada ───────────────────────────────────────────────

/// Fim da validade de uma URL pré-assinada do S3 (`X-Amz-Date` +
/// `X-Amz-Expires`). `null` quando a URL não é assinada (pública, da Meta ou
/// sem os parâmetros) — nesse caso não há como saber se venceu.
DateTime? validadeDaUrlAssinada(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasQuery) return null;
  String? data;
  int? segundos;
  uri.queryParameters.forEach((chave, valor) {
    final k = chave.toLowerCase();
    if (k == 'x-amz-date') data = valor;
    if (k == 'x-amz-expires') segundos = int.tryParse(valor);
  });
  final d = data;
  final s = segundos;
  if (d == null || s == null) return null;
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$').firstMatch(d);
  if (m == null) return null;
  final inicio = DateTime.utc(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
    int.parse(m.group(6)!),
  );
  return inicio.add(Duration(seconds: s));
}

/// A assinatura já venceu ou vence dentro de [margem]? URL sem assinatura
/// conhecida responde `false` (quem decide é a tentativa de carregar).
bool urlAssinadaVencida(
  String url, {
  Duration margem = const Duration(minutes: 2),
}) {
  final fim = validadeDaUrlAssinada(url);
  if (fim == null) return false;
  return DateTime.now().toUtc().add(margem).isAfter(fim);
}

/// As duas URLs apontam para o MESMO arquivo (mesmo host e caminho, só a
/// assinatura muda)?
bool mesmoArquivoDeMidia(String a, String b) {
  final ua = Uri.tryParse(a.trim());
  final ub = Uri.tryParse(b.trim());
  if (ua == null || ub == null) return false;
  return ua.scheme == ub.scheme && ua.host == ub.host && ua.path == ub.path;
}

/// Qual URL a bolha deve usar quando a thread é relida (29/09/2026): a
/// antiga, se ainda vale por mais alguns minutos e é o mesmo arquivo — assim
/// a imagem não recarrega a cada 20 s; a nova, se a antiga está vencendo ou
/// não era assinada (fora do teto de 25 assinaturas por resposta).
String? urlDeMidiaParaManter(String? antiga, String? nova) {
  if (antiga == null || antiga.isEmpty) return nova;
  if (nova == null || nova.isEmpty) return antiga;
  if (antiga == nova) return nova;
  if (!mesmoArquivoDeMidia(antiga, nova)) return nova;
  final validadeAntiga = validadeDaUrlAssinada(antiga);
  if (validadeAntiga == null) {
    // Antiga sem assinatura: se a nova é assinada, ela é a que abre.
    return validadeDaUrlAssinada(nova) != null ? nova : antiga;
  }
  if (urlAssinadaVencida(antiga, margem: const Duration(minutes: 5))) {
    return nova;
  }
  return antiga;
}

// ─── Arquivos: família, tamanho e nome ──────────────────────────────────────

/// Família do documento, para o ícone da bandeja e da bolha (mesmas famílias
/// do web: `familiaDoDocumento`).
enum WhatsAppFamiliaDoDocumento { pdf, texto, planilha, apresentacao, outro }

String _extensaoDe(String nome) {
  final limpo = nome.trim().toLowerCase();
  final ponto = limpo.lastIndexOf('.');
  if (ponto < 0 || ponto == limpo.length - 1) return '';
  return limpo.substring(ponto + 1);
}

/// Extensão do arquivo em minúsculas, sem o ponto ('' quando não há).
String extensaoDoArquivo(String nome) => _extensaoDe(nome);

WhatsAppFamiliaDoDocumento familiaDoDocumento(String nome, [String? mime]) {
  final tipo = (mime ?? '').toLowerCase().split(';').first.trim();
  final ext = _extensaoDe(nome);
  if (tipo == 'application/pdf' || ext == 'pdf') {
    return WhatsAppFamiliaDoDocumento.pdf;
  }
  if (tipo.contains('spreadsheet') ||
      tipo == 'application/vnd.ms-excel' ||
      tipo == 'text/csv' ||
      const {'xls', 'xlsx', 'csv', 'ods'}.contains(ext)) {
    return WhatsAppFamiliaDoDocumento.planilha;
  }
  if (tipo.contains('presentation') ||
      tipo == 'application/vnd.ms-powerpoint' ||
      const {'ppt', 'pptx', 'odp', 'key'}.contains(ext)) {
    return WhatsAppFamiliaDoDocumento.apresentacao;
  }
  if (tipo.contains('word') ||
      tipo == 'text/plain' ||
      const {'doc', 'docx', 'txt', 'rtf', 'odt'}.contains(ext)) {
    return WhatsAppFamiliaDoDocumento.texto;
  }
  return WhatsAppFamiliaDoDocumento.outro;
}

/// "PDF", "Planilha"… — o mesmo rótulo que o web põe embaixo do nome.
String rotuloDaFamilia(WhatsAppFamiliaDoDocumento familia) {
  switch (familia) {
    case WhatsAppFamiliaDoDocumento.pdf:
      return 'PDF';
    case WhatsAppFamiliaDoDocumento.planilha:
      return 'Planilha';
    case WhatsAppFamiliaDoDocumento.apresentacao:
      return 'Apresentação';
    case WhatsAppFamiliaDoDocumento.texto:
      return 'Documento de texto';
    case WhatsAppFamiliaDoDocumento.outro:
      return 'Documento';
  }
}

/// "1,2 MB", "340 KB", "812 B" (mesma escrita do web).
String rotuloDoTamanho(int bytes) {
  if (bytes < 0) return '';
  const mb = 1024 * 1024;
  if (bytes >= mb) {
    var s = (bytes / mb).toStringAsFixed(1);
    if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
    return '${s.replaceAll('.', ',')} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
  return '$bytes B';
}

/// Nome com reticências no MEIO, preservando a extensão:
/// "relatorio-fin…2026.pdf".
String nomeAbreviado(String nome, [int max = 22]) {
  if (nome.length <= max) return nome;
  final ponto = nome.lastIndexOf('.');
  final ext = ponto > 0 && nome.length - ponto <= 6 ? nome.substring(ponto) : '';
  final base = ext.isNotEmpty ? nome.substring(0, ponto) : nome;
  final sobra = (max - ext.length - 1) < 4 ? 4 : (max - ext.length - 1);
  final ini = (sobra * 0.6).ceil();
  final fim = sobra - ini;
  final inicio = base.substring(0, ini > base.length ? base.length : ini);
  final finalDoNome =
      fim > 0 && base.length > fim ? base.substring(base.length - fim) : '';
  return '$inicio…$finalDoNome$ext';
}

/// Extensão para o arquivo salvo quando a mensagem não traz nome (imagem,
/// áudio, vídeo recebidos): sai do MIME; na falta dele, do tipo.
String extensaoPeloMime(String? mime, String tipoDaMensagem) {
  final t = (mime ?? '').toLowerCase().split(';').first.trim();
  const mapa = {
    'image/jpeg': 'jpg',
    'image/jpg': 'jpg',
    'image/png': 'png',
    'image/gif': 'gif',
    'image/webp': 'webp',
    'image/heic': 'heic',
    'audio/ogg': 'ogg',
    'audio/opus': 'ogg',
    'audio/mpeg': 'mp3',
    'audio/mp3': 'mp3',
    'audio/mp4': 'm4a',
    'audio/x-m4a': 'm4a',
    'audio/aac': 'aac',
    'audio/amr': 'amr',
    'video/mp4': 'mp4',
    'video/3gpp': '3gp',
    'video/quicktime': 'mov',
    'application/pdf': 'pdf',
    'text/plain': 'txt',
  };
  final porMime = mapa[t];
  if (porMime != null) return porMime;
  switch (tipoDaMensagem) {
    case 'image':
      return 'jpg';
    case 'sticker':
      return 'webp';
    case 'audio':
    case 'voice':
      return 'ogg';
    case 'video':
      return 'mp4';
    default:
      return 'bin';
  }
}
