// Fila de anexos da conversa do WhatsApp (29/09/2026) — porte de
// `utils/whatsappFilaDeAnexos.ts` do imobx-front, com as mesmas regras e
// frases. O app só mandava texto e template; agora manda imagem, documento e
// áudio, vários de uma vez, cada um virando uma mensagem, como no web.
//
// Regra do canal (espelho de imobx/src/whatsapp/utils/whatsapp-anexo-oficial.util.ts):
//  - API oficial (Meta): imagem JPG/PNG/GIF/WEBP até 5MB, documento
//    PDF/DOC/DOCX/XLS/XLSX/PPT/PPTX/TXT até 50MB, áudio MP3/M4A/OGG/AAC/AMR
//    até 16MB. Fora disso a Meta recusa: recusar na fila é melhor do que
//    gerar mensagem "Falhou".
//  - QR Code (Baileys): qualquer tipo até 50MB.
//
// Puro de propósito (sem widget); só lê o começo do arquivo para descobrir o
// tipo real de uma imagem.

import 'dart:io';
import 'dart:typed_data';

import 'whatsapp_midia.dart';

const int kMaximoDeAnexos = 30;

/// Legenda de mídia na Cloud API vai até 1024 caracteres; acima disso o texto
/// sai antes, como mensagem própria (ver [montarTrabalhosDeEnvio]).
const int kLegendaMaxima = 1024;

const int _mb = 1024 * 1024;
const int kLimiteDaImagemBytes = 5 * _mb;
const int kLimiteDoDocumentoBytes = 50 * _mb;
const int kLimiteDoAudioBytes = 16 * _mb;

const String kRotuloDasImagens = 'JPG, PNG, GIF ou WEBP';
const String kRotuloDosDocumentos =
    'PDF, DOC, DOCX, XLS, XLSX, PPT, PPTX ou TXT';
const String kRotuloDosAudios = 'MP3, M4A, OGG, AAC ou AMR';

const List<String> _imagensDaApiOficial = [
  'image/jpeg',
  'image/jpg',
  'image/png',
  'image/gif',
  'image/webp',
];

const List<String> _documentosDaApiOficial = [
  'application/pdf',
  'text/plain',
  // text/csv NÃO: a Cloud API recusa CSV como documento (igual ao web).
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-excel',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.ms-powerpoint',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation',
];

const List<String> _audiosDaApiOficial = [
  'audio/aac',
  'audio/amr',
  'audio/mpeg',
  'audio/mp4',
  'audio/ogg',
];

/// Extensões do seletor "Documento ou áudio" do canal oficial — o mesmo
/// `accept` do botão de clipe do web (ACCEPT_DOS_DOCUMENTOS_OFICIAIS).
const List<String> kExtensoesDoAnexoOficial = [
  'pdf',
  'doc',
  'docx',
  'xls',
  'xlsx',
  'ppt',
  'pptx',
  'txt',
  'mp3',
  'm4a',
  'ogg',
  'aac',
  'amr',
];

/// Nomes alternativos que sistemas dão ao mesmo formato.
const Map<String, String> _sinonimos = {
  'image/jpg': 'image/jpeg',
  'audio/mp3': 'audio/mpeg',
  'audio/x-m4a': 'audio/mp4',
  'audio/m4a': 'audio/mp4',
  'audio/x-aac': 'audio/aac',
  'audio/opus': 'audio/ogg',
};

/// O seletor do aparelho não informa MIME: sai da extensão. Além do catálogo
/// do web, entram os tipos que só o QR Code aceita (vídeo, HEIC, ZIP…), para
/// o back receber o tipo certo.
const Map<String, String> _extensaoParaMime = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'bmp': 'image/bmp',
  'pdf': 'application/pdf',
  'txt': 'text/plain',
  'csv': 'text/csv',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx':
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'mp3': 'audio/mpeg',
  'm4a': 'audio/mp4',
  'aac': 'audio/aac',
  'amr': 'audio/amr',
  'ogg': 'audio/ogg',
  'oga': 'audio/ogg',
  'opus': 'audio/ogg',
  'wav': 'audio/wav',
  'mp4': 'video/mp4',
  'm4v': 'video/x-m4v',
  'mov': 'video/quicktime',
  '3gp': 'video/3gpp',
  'webm': 'video/webm',
  'zip': 'application/zip',
  'rar': 'application/vnd.rar',
};

/// Imagens que o Flutter desenha na miniatura da bandeja (HEIC não).
const Set<String> _imagensExibiveis = {
  'image/jpeg',
  'image/png',
  'image/gif',
  'image/webp',
  'image/bmp',
};

/// MIME pelo nome do arquivo (e, se houver, pelo MIME informado), já com os
/// sinônimos normalizados para o nome do catálogo.
String mimeDoArquivo(String nome, [String? informado]) {
  final base = (informado ?? '').toLowerCase().split(';').first.trim();
  final generico = base.isEmpty ||
      base == 'application/octet-stream' ||
      base == 'binary/octet-stream';
  if (!generico) return _sinonimos[base] ?? base;
  return _extensaoParaMime[extensaoDoArquivo(nome)] ?? '';
}

String _ascii(Uint8List b, int ini, int fim) =>
    String.fromCharCodes(b.sublist(ini, fim));

/// Tipo real de uma IMAGEM pelos primeiros bytes. O image_picker do Android
/// recomprime em JPEG mas mantém o nome original ("scaled_IMG.heic"), então
/// pelo nome a foto seria recusada ou iria com o tipo errado.
String? _mimeDaImagemPelosBytes(Uint8List b) {
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (b.length >= 4 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47) {
    return 'image/png';
  }
  if (b.length >= 4 &&
      b[0] == 0x47 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x38) {
    return 'image/gif';
  }
  if (b.length >= 12 &&
      _ascii(b, 0, 4) == 'RIFF' &&
      _ascii(b, 8, 12) == 'WEBP') {
    return 'image/webp';
  }
  if (b.length >= 12 && _ascii(b, 4, 8) == 'ftyp') {
    const marcasHeic = {
      'heic',
      'heix',
      'hevc',
      'hevx',
      'heim',
      'heis',
      'mif1',
      'msf1',
    };
    if (marcasHeic.contains(_ascii(b, 8, 12))) return 'image/heic';
  }
  return null;
}

const Map<String, String> _extensaoDaImagem = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/gif': 'gif',
  'image/webp': 'webp',
  'image/heic': 'heic',
};

// ─── Anexo ──────────────────────────────────────────────────────────────────

/// Um arquivo esperando o envio na bandeja.
class WhatsAppAnexo {
  final String id;

  /// Caminho local (cópia do seletor, em cache do app).
  final String caminho;

  /// Nome mostrado na bandeja (o do arquivo escolhido).
  final String nome;
  final int tamanho;

  /// MIME resolvido (pelos bytes em imagem; pela extensão no resto).
  final String mime;

  const WhatsAppAnexo({
    required this.id,
    required this.caminho,
    required this.nome,
    required this.tamanho,
    required this.mime,
  });

  bool get ehImagem => mime.startsWith('image/');
  bool get ehAudio => mime.startsWith('audio/');
  bool get ehVideo => mime.startsWith('video/');

  /// Miniatura de verdade só para imagem que o Flutter desenha.
  bool get temPrevia => _imagensExibiveis.contains(mime);

  /// Nome enviado ao back: a extensão acompanha o tipo REAL da imagem
  /// (JPEG dentro de ".heic" vai como ".jpg"); demais arquivos vão como estão.
  String get nomeParaEnvio {
    final nomeLimpo = nome.trim().isEmpty ? 'arquivo' : nome.trim();
    final extReal = _extensaoDaImagem[mime];
    if (extReal == null) return nomeLimpo;
    final ext = extensaoDoArquivo(nomeLimpo);
    final coerente = ext == extReal || (extReal == 'jpg' && ext == 'jpeg');
    if (coerente) return nomeLimpo;
    final ponto = nomeLimpo.lastIndexOf('.');
    final base = ponto > 0 ? nomeLimpo.substring(0, ponto) : nomeLimpo;
    return '$base.$extReal';
  }

  static int _sequencia = 0;

  /// Lê tamanho e tipo de um arquivo local. `null` se o arquivo sumiu.
  static Future<WhatsAppAnexo?> doArquivo(
    String caminho, {
    String? nome,
    int? tamanho,
  }) async {
    final arquivo = File(caminho);
    try {
      if (!await arquivo.exists()) return null;
      final bytes = tamanho ?? await arquivo.length();
      final nomeFinal = (nome ?? '').trim().isNotEmpty
          ? nome!.trim()
          : caminho.split(RegExp(r'[\\/]')).last;
      String? pelosBytes;
      RandomAccessFile? leitor;
      try {
        leitor = await arquivo.open();
        pelosBytes = _mimeDaImagemPelosBytes(await leitor.read(16));
      } catch (_) {
        pelosBytes = null;
      } finally {
        await leitor?.close();
      }
      _sequencia += 1;
      return WhatsAppAnexo(
        id: 'anexo-${DateTime.now().microsecondsSinceEpoch}-$_sequencia',
        caminho: caminho,
        nome: nomeFinal,
        tamanho: bytes,
        mime: pelosBytes ?? mimeDoArquivo(nomeFinal),
      );
    } catch (_) {
      return null;
    }
  }
}

// ─── Regra do canal ─────────────────────────────────────────────────────────

class WhatsAppRegraDeAnexo {
  /// MIMEs aceitos; `null` = qualquer tipo (QR Code).
  final List<String>? tiposAceitos;
  final String rotuloDosTipos;

  /// Teto para o que não é imagem nem áudio (e para tudo no QR Code).
  final int tamanhoMaximoBytes;
  final String rotuloDoTamanho;
  final int? limiteDaImagemBytes;
  final String? rotuloDoLimiteDaImagem;
  final int? limiteDoAudioBytes;
  final String? rotuloDoLimiteDoAudio;

  const WhatsAppRegraDeAnexo({
    required this.tiposAceitos,
    required this.rotuloDosTipos,
    required this.tamanhoMaximoBytes,
    required this.rotuloDoTamanho,
    this.limiteDaImagemBytes,
    this.rotuloDoLimiteDaImagem,
    this.limiteDoAudioBytes,
    this.rotuloDoLimiteDoAudio,
  });
}

/// API oficial = imagens (5MB) + documentos (50MB) + áudios (16MB);
/// QR Code = qualquer tipo até 50MB.
WhatsAppRegraDeAnexo regraDoCanal(bool naoOficial) {
  if (naoOficial) {
    return const WhatsAppRegraDeAnexo(
      tiposAceitos: null,
      rotuloDosTipos: '',
      tamanhoMaximoBytes: 50 * _mb,
      rotuloDoTamanho: '50MB',
    );
  }
  return const WhatsAppRegraDeAnexo(
    tiposAceitos: [
      ..._imagensDaApiOficial,
      ..._documentosDaApiOficial,
      ..._audiosDaApiOficial,
    ],
    rotuloDosTipos: '$kRotuloDasImagens (imagem), $kRotuloDosDocumentos '
        '(documento) ou $kRotuloDosAudios (áudio)',
    tamanhoMaximoBytes: kLimiteDoDocumentoBytes,
    rotuloDoTamanho: '50MB',
    limiteDaImagemBytes: kLimiteDaImagemBytes,
    rotuloDoLimiteDaImagem: '5MB',
    limiteDoAudioBytes: kLimiteDoAudioBytes,
    rotuloDoLimiteDoAudio: '16MB',
  );
}

enum WhatsAppMotivoDaRecusa { tipo, tamanho, tamanhoImagem, tamanhoAudio, limite }

class WhatsAppAnexoRecusado {
  final String nome;
  final WhatsAppMotivoDaRecusa motivo;
  const WhatsAppAnexoRecusado(this.nome, this.motivo);
}

/// Acrescenta ao FIM da fila, na ordem recebida; nunca troca o que já está
/// lá. Recusa (sem bloquear os outros) o que foge da regra ou passa do máximo.
({List<WhatsAppAnexo> fila, List<WhatsAppAnexoRecusado> recusados})
    acrescentarAnexos(
  List<WhatsAppAnexo> fila,
  List<WhatsAppAnexo> novos,
  WhatsAppRegraDeAnexo regra,
) {
  final nova = [...fila];
  final recusados = <WhatsAppAnexoRecusado>[];
  for (final a in novos) {
    final aceitos = regra.tiposAceitos;
    if (aceitos != null && !aceitos.contains(a.mime)) {
      recusados.add(WhatsAppAnexoRecusado(a.nome, WhatsAppMotivoDaRecusa.tipo));
      continue;
    }
    final limiteImagem = regra.limiteDaImagemBytes;
    final limiteAudio = regra.limiteDoAudioBytes;
    if (limiteImagem != null && a.ehImagem) {
      if (a.tamanho > limiteImagem) {
        recusados.add(
            WhatsAppAnexoRecusado(a.nome, WhatsAppMotivoDaRecusa.tamanhoImagem));
        continue;
      }
    } else if (limiteAudio != null && a.ehAudio) {
      if (a.tamanho > limiteAudio) {
        recusados.add(
            WhatsAppAnexoRecusado(a.nome, WhatsAppMotivoDaRecusa.tamanhoAudio));
        continue;
      }
    } else if (a.tamanho > regra.tamanhoMaximoBytes) {
      recusados.add(WhatsAppAnexoRecusado(a.nome, WhatsAppMotivoDaRecusa.tamanho));
      continue;
    }
    if (nova.length >= kMaximoDeAnexos) {
      recusados.add(WhatsAppAnexoRecusado(a.nome, WhatsAppMotivoDaRecusa.limite));
      continue;
    }
    nova.add(a);
  }
  return (fila: nova, recusados: recusados);
}

String _quantos(int n) =>
    n == 1 ? '1 arquivo ignorado' : '$n arquivos ignorados';

/// Um aviso só para o lote: "2 arquivos ignorados: imagem acima de 5MB".
/// Motivos diferentes viram partes separadas por ponto e vírgula.
String? resumoDosRecusados(
  List<WhatsAppAnexoRecusado> recusados,
  WhatsAppRegraDeAnexo regra,
) {
  if (recusados.isEmpty) return null;
  int conta(WhatsAppMotivoDaRecusa m) =>
      recusados.where((r) => r.motivo == m).length;
  final porTipo = regra.limiteDaImagemBytes != null;
  final partes = <String>[];
  final tipo = conta(WhatsAppMotivoDaRecusa.tipo);
  if (tipo > 0) {
    partes.add(_quantos(tipo) +
        (regra.rotuloDosTipos.isNotEmpty
            ? ': só ${regra.rotuloDosTipos} neste canal'
            : ': tipo não aceito'));
  }
  final imagem = conta(WhatsAppMotivoDaRecusa.tamanhoImagem);
  if (imagem > 0) {
    partes.add(
        '${_quantos(imagem)}: imagem acima de ${regra.rotuloDoLimiteDaImagem ?? ''}');
  }
  final audio = conta(WhatsAppMotivoDaRecusa.tamanhoAudio);
  if (audio > 0) {
    partes.add(
        '${_quantos(audio)}: áudio acima de ${regra.rotuloDoLimiteDoAudio ?? ''}');
  }
  final tamanho = conta(WhatsAppMotivoDaRecusa.tamanho);
  if (tamanho > 0) {
    partes.add(
        '${_quantos(tamanho)}: ${porTipo ? 'documento ' : ''}acima de ${regra.rotuloDoTamanho}');
  }
  final limite = conta(WhatsAppMotivoDaRecusa.limite);
  if (limite > 0) {
    partes.add('${_quantos(limite)}: máximo de $kMaximoDeAnexos por envio');
  }
  return partes.join('; ');
}

// ─── Envio em lote ──────────────────────────────────────────────────────────

class WhatsAppTrabalhoDeEnvio {
  /// `null` = mensagem só de texto.
  final WhatsAppAnexo? anexo;

  /// Texto (legenda quando há anexo).
  final String texto;

  const WhatsAppTrabalhoDeEnvio({this.anexo, this.texto = ''});
}

/// Divide o envio em mensagens, na ordem da bandeja: cada anexo é uma; o
/// texto vai como LEGENDA do primeiro — a menos que passe de
/// [kLegendaMaxima] ou que o primeiro seja ÁUDIO (a Meta não aceita legenda
/// em áudio e o back devolve 400): aí o texto sai ANTES, como mensagem
/// própria. A tela nunca perde texto.
List<WhatsAppTrabalhoDeEnvio> montarTrabalhosDeEnvio(
  List<WhatsAppAnexo> anexos,
  String texto,
) {
  final limpo = texto.trim();
  if (anexos.isEmpty) return [WhatsAppTrabalhoDeEnvio(texto: limpo)];
  final primeiroEhAudio = limpo.isNotEmpty && anexos.first.ehAudio;
  if (limpo.length > kLegendaMaxima || primeiroEhAudio) {
    return [
      WhatsAppTrabalhoDeEnvio(texto: limpo),
      for (final a in anexos) WhatsAppTrabalhoDeEnvio(anexo: a),
    ];
  }
  return [
    for (var i = 0; i < anexos.length; i++)
      WhatsAppTrabalhoDeEnvio(anexo: anexos[i], texto: i == 0 ? limpo : ''),
  ];
}
