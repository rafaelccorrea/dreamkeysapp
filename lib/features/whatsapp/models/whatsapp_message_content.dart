// O QUE a bolha da conversa (e a prévia da lista) mostra para uma mensagem,
// e POR QUE uma mensagem enviada "Falhou". Porte fiel (29/09/2026) de
// `utils/whatsappConteudoDaBolha.ts` e `utils/whatsappFalha.ts` do
// imobx-front: o app não lia `webhookData`, então reação e aviso do WhatsApp
// (gravados como `text` com `message` NULL) viravam bolha só com o horário,
// localização/contato viravam "Abra no painel" e a lista dizia "Mensagem" —
// o mesmo defeito do caso União de 17/09 que o web já tinha corrigido.
//
// Puro de propósito: nenhum widget aqui. A bolha e o card decidem o desenho;
// este arquivo decide o CONTEÚDO, com as mesmas frases do web.

import 'whatsapp_models.dart';

// ─── Helpers ────────────────────────────────────────────────────────────────

String _limpo(dynamic v) {
  if (v is! String) return '';
  return v.replaceAll(RegExp(r'\s+'), ' ').trim();
}

Map<String, dynamic>? _objeto(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}

int? _inteiro(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.isFinite ? v.truncate() : null;
  if (v is String) return int.tryParse(v.trim()) ?? double.tryParse(v.trim())?.truncate();
  return null;
}

double? _numero(dynamic v) {
  if (v is num) return v.isFinite ? v.toDouble() : null;
  if (v is String) return double.tryParse(v.trim());
  return null;
}

// ─── Rótulos (mesmas frases do web) ─────────────────────────────────────────

const Map<String, String> _midias = {
  'image': 'Imagem',
  'video': 'Vídeo',
  'audio': 'Áudio',
  'voice': 'Nota de voz',
  'document': 'Documento',
  'sticker': 'Figurinha',
};

const Map<String, String> _nativos = {
  'location': 'Localização',
  'contact': 'Contato',
};

/// Tipos que a Meta/Baileys mandam e que não têm desenho próprio.
const Map<String, String> _desconhecidos = {
  'reaction': 'Reação',
  'button': 'Botão',
  'interactive': 'Resposta interativa',
  'unsupported': 'Mensagem não suportada pelo WhatsApp',
  'unknown': 'Mensagem não suportada pelo WhatsApp',
  'revoked': 'Mensagem apagada',
  'deleted': 'Mensagem apagada',
  'poll': 'Enquete',
  'poll_update': 'Voto em enquete',
  'order': 'Pedido',
  'contacts': 'Contatos',
  'system': 'Aviso do WhatsApp',
  'ephemeral': 'Mensagem temporária',
  'template': 'Template',
  'request_welcome': 'Início de conversa',
};

const String kRotuloSemTexto = 'Mensagem sem texto';
const String kRotuloLegadoSemConteudo =
    'Conteúdo não exibível (reação, enquete ou similar)';
const String kRotuloNaoSuportado =
    'Conteúdo que o WhatsApp oficial não entrega (enquete, evento, visualização única ou similar)';
const String kPreviaNaoSuportado = 'Conteúdo não suportado';
const String kRotuloAvisoDoWhatsApp = 'Aviso do WhatsApp';
const String kRotuloFormularioRespondido = 'Formulário respondido';

String rotuloDoPedido(int? itens) {
  if (itens == null || itens <= 0) return 'Pedido do catálogo';
  return 'Pedido do catálogo · $itens ${itens == 1 ? 'item' : 'itens'}';
}

/// Rótulo legível de um tipo bruto. Documento usa o nome do arquivo.
String rotuloDoTipo(String messageType, [String? mediaFileName]) {
  final tipo = messageType.toLowerCase();
  if (tipo == 'text') return 'Mensagem';
  if (tipo == 'document' && _limpo(mediaFileName).isNotEmpty) {
    return _limpo(mediaFileName);
  }
  if (_midias.containsKey(tipo)) return _midias[tipo]!;
  if (_nativos.containsKey(tipo)) return _nativos[tipo]!;
  if (_desconhecidos.containsKey(tipo)) return _desconhecidos[tipo]!;
  return 'Mensagem sem conteúdo exibível (tipo ${tipo.isEmpty ? 'desconhecido' : tipo})';
}

// ─── Contato e localização compartilhados ───────────────────────────────────

class WhatsAppContatoCompartilhado {
  final String? name;
  final String? phone;
  final String? email;
  const WhatsAppContatoCompartilhado({this.name, this.phone, this.email});
}

List<WhatsAppContatoCompartilhado> contatosDaMensagem(WhatsAppMessage m) {
  final wd = m.webhookData;
  if (wd == null) return const [];
  final lista = wd['contacts'] is List
      ? (wd['contacts'] as List).map(_objeto).whereType<Map<String, dynamic>>().toList()
      : <Map<String, dynamic>>[];
  final unico = _objeto(wd['contact']);
  final brutos = lista.isNotEmpty ? lista : (unico != null ? [unico] : const <Map<String, dynamic>>[]);
  String? n(dynamic v) => _limpo(v).isEmpty ? null : _limpo(v);
  return brutos
      .map((c) => WhatsAppContatoCompartilhado(
            name: n(c['name']),
            phone: n(c['phone']),
            email: n(c['email']),
          ))
      .toList();
}

class WhatsAppLocalizacao {
  final double? latitude;
  final double? longitude;
  final String? name;
  final String? address;
  final String? url;
  const WhatsAppLocalizacao({
    this.latitude,
    this.longitude,
    this.name,
    this.address,
    this.url,
  });

  /// Link para abrir no app de mapas: o do WhatsApp quando veio; senão as
  /// coordenadas; senão o endereço.
  String? get linkDoMapa {
    if ((url ?? '').isNotEmpty) return url;
    if (latitude != null && longitude != null) {
      return 'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude';
    }
    final alvo = address ?? name;
    if ((alvo ?? '').isNotEmpty) {
      return 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(alvo!)}';
    }
    return null;
  }
}

WhatsAppLocalizacao localizacaoDaMensagem(WhatsAppMessage m) {
  final wd = m.webhookData ?? const <String, dynamic>{};
  String? n(dynamic v) => _limpo(v).isEmpty ? null : _limpo(v);
  return WhatsAppLocalizacao(
    latitude: _numero(wd['latitude']),
    longitude: _numero(wd['longitude']),
    name: n(wd['name']),
    address: n(wd['address']),
    url: n(wd['url']),
  );
}

// ─── Conteúdo da bolha ──────────────────────────────────────────────────────

enum WhatsAppTipoDeConteudo {
  /// Texto normal.
  texto,

  /// Mídia com arquivo (imagem, vídeo, áudio, voz, documento, figurinha).
  midia,

  /// Mídia SEM arquivo: "Imagem indisponível" + legenda, se houver.
  midiaAusente,

  /// location/contact: desenho próprio.
  nativo,

  /// Reação do cliente a uma mensagem.
  reacao,

  /// Enquete, evento, visualização única… (a API oficial não entrega).
  naoSuportado,

  /// Aviso do WhatsApp (cliente trocou de número etc.).
  sistema,

  /// Pedido do catálogo.
  pedido,

  /// Formulário (flow) respondido.
  formulario,

  /// `text` sem texto.
  semTexto,

  /// Tipo sem desenho: só o rótulo legível.
  desconhecido,
}

class WhatsAppConteudoDaBolha {
  final WhatsAppTipoDeConteudo tipo;
  final String? texto;
  final String? legenda;
  final String? rotulo;
  final String? detalhe;
  final String? emoji;
  final String? alvoId;
  final String? alvoWamid;

  const WhatsAppConteudoDaBolha(
    this.tipo, {
    this.texto,
    this.legenda,
    this.rotulo,
    this.detalhe,
    this.emoji,
    this.alvoId,
    this.alvoWamid,
  });
}

/// Conteúdo pelo `webhookData` (contrato novo do back): reação, não
/// suportado, aviso do sistema, pedido e formulário chegam como `text`.
WhatsAppConteudoDaBolha? _conteudoPeloWebhook(WhatsAppMessage m) {
  final wd = m.webhookData;
  if (wd == null) return null;
  final tipoOriginal = _limpo(wd['tipoOriginal']).toLowerCase();

  final reaction = _objeto(wd['reaction']);
  if (reaction != null || tipoOriginal == 'reaction') {
    final emoji = _limpo(reaction?['emoji']);
    if (emoji.isEmpty) return null;
    final alvoId = _limpo(reaction?['targetMessageId']);
    final wamid = _limpo(reaction?['messageId']).isNotEmpty
        ? _limpo(reaction?['messageId'])
        : _limpo(m.replyToMessageId);
    return WhatsAppConteudoDaBolha(
      WhatsAppTipoDeConteudo.reacao,
      emoji: emoji,
      alvoId: alvoId.isEmpty ? null : alvoId,
      alvoWamid: wamid.isEmpty ? null : wamid,
    );
  }

  final unsupported = _objeto(wd['unsupported']);
  if (unsupported != null ||
      tipoOriginal == 'unsupported' ||
      tipoOriginal == 'unknown') {
    final detalhe = [_limpo(unsupported?['title']), _limpo(unsupported?['details'])]
        .where((s) => s.isNotEmpty)
        .join(' · ');
    return WhatsAppConteudoDaBolha(
      WhatsAppTipoDeConteudo.naoSuportado,
      rotulo: kRotuloNaoSuportado,
      detalhe: detalhe.isEmpty ? null : detalhe,
    );
  }

  final system = _objeto(wd['system']);
  if (system != null || tipoOriginal == 'system') {
    final body = _limpo(system?['body']);
    return WhatsAppConteudoDaBolha(
      WhatsAppTipoDeConteudo.sistema,
      rotulo: body.isNotEmpty ? '$kRotuloAvisoDoWhatsApp: $body' : kRotuloAvisoDoWhatsApp,
    );
  }

  final order = _objeto(wd['order']);
  if (order != null || tipoOriginal == 'order') {
    final texto = _limpo(m.message);
    return WhatsAppConteudoDaBolha(
      WhatsAppTipoDeConteudo.pedido,
      rotulo: rotuloDoPedido(_inteiro(order?['itens'])),
      texto: texto.isEmpty ? null : texto,
    );
  }

  // Formulário (flow) respondido: o body da Meta é só "Sent", o back não
  // grava texto. Com texto, é texto normal.
  final interactive = _objeto(wd['interactive']);
  if (_limpo(interactive?['type']).toLowerCase() == 'nfm_reply' &&
      _limpo(m.message).isEmpty) {
    return const WhatsAppConteudoDaBolha(
      WhatsAppTipoDeConteudo.formulario,
      rotulo: kRotuloFormularioRespondido,
    );
  }
  return null;
}

/// O que a BOLHA deve mostrar. Nunca devolve "nada".
WhatsAppConteudoDaBolha conteudoDaBolha(WhatsAppMessage m) {
  final peloWebhook = _conteudoPeloWebhook(m);
  if (peloWebhook != null) return peloWebhook;

  final tipo = m.rawType.toLowerCase();
  final texto = _limpo(m.message);
  final legenda = texto.isEmpty ? null : texto;

  if (tipo == 'text') {
    final original = (m.message ?? '').trim();
    if (original.isNotEmpty) {
      return WhatsAppConteudoDaBolha(WhatsAppTipoDeConteudo.texto, texto: original);
    }
    final tipoOriginal = _limpo(m.webhookData?['tipoOriginal']).toLowerCase();
    return WhatsAppConteudoDaBolha(
      WhatsAppTipoDeConteudo.semTexto,
      rotulo: tipoOriginal == 'text' ? kRotuloSemTexto : kRotuloLegadoSemConteudo,
    );
  }
  if (_midias.containsKey(tipo)) {
    if ((m.mediaUrl ?? '').isNotEmpty) {
      return WhatsAppConteudoDaBolha(WhatsAppTipoDeConteudo.midia, legenda: legenda);
    }
    return WhatsAppConteudoDaBolha(
      WhatsAppTipoDeConteudo.midiaAusente,
      rotulo: '${_midias[tipo]} indisponível',
      legenda: legenda,
    );
  }
  if (_nativos.containsKey(tipo)) {
    return const WhatsAppConteudoDaBolha(WhatsAppTipoDeConteudo.nativo);
  }
  return WhatsAppConteudoDaBolha(
    WhatsAppTipoDeConteudo.desconhecido,
    rotulo: rotuloDoTipo(tipo, m.mediaFileName),
  );
}

/// Prévia de UMA linha para a lista — a mesma verdade da bolha.
String previaDaMensagem(WhatsAppMessage m) {
  final c = conteudoDaBolha(m);
  switch (c.tipo) {
    case WhatsAppTipoDeConteudo.texto:
      return _limpo(c.texto);
    case WhatsAppTipoDeConteudo.midia:
      return c.legenda ?? rotuloDoTipo(m.rawType, m.mediaFileName);
    case WhatsAppTipoDeConteudo.midiaAusente:
      return c.legenda ?? c.rotulo ?? '';
    case WhatsAppTipoDeConteudo.nativo:
      final tipo = m.rawType.toLowerCase();
      if (tipo == 'contact') {
        final contatos = contatosDaMensagem(m);
        final nome = contatos.isNotEmpty ? contatos.first.name : null;
        return nome != null ? 'Contato: $nome' : 'Contato';
      }
      if (tipo == 'location') {
        final nome = localizacaoDaMensagem(m).name;
        return nome != null ? 'Localização: $nome' : 'Localização';
      }
      return rotuloDoTipo(tipo);
    case WhatsAppTipoDeConteudo.reacao:
      return 'Reagiu com ${c.emoji}';
    case WhatsAppTipoDeConteudo.naoSuportado:
      return kPreviaNaoSuportado;
    case WhatsAppTipoDeConteudo.sistema:
    case WhatsAppTipoDeConteudo.formulario:
      return c.rotulo ?? '';
    case WhatsAppTipoDeConteudo.pedido:
      return c.texto != null ? '${c.rotulo}: ${c.texto}' : (c.rotulo ?? '');
    case WhatsAppTipoDeConteudo.semTexto:
    case WhatsAppTipoDeConteudo.desconhecido:
      return c.rotulo ?? '';
  }
}

// ─── Citação (resposta a uma mensagem) ──────────────────────────────────────

/// Só responde a mensagem que existe de verdade no WhatsApp: com wamid e sem
/// ter falhado (mesma regra de `podeResponder` do web).
bool podeResponder(WhatsAppMessage m) =>
    (m.whatsappMessageId ?? '').isNotEmpty &&
    m.status != WhatsAppMessageStatus.failed;

/// A mensagem citada, pelo wamid, entre as carregadas.
WhatsAppMessage? acharCitada(List<WhatsAppMessage> mensagens, String? wamid) {
  if (wamid == null || wamid.isEmpty) return null;
  for (final m in mensagens) {
    if (m.whatsappMessageId == wamid) return m;
  }
  return null;
}

/// Uma linha só, cortada em 90 caracteres com "…".
String umaLinha(String texto, [int limite = 90]) {
  final plano = texto.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (plano.length <= limite) return plano;
  return '${plano.substring(0, limite).trimRight()}…';
}

/// Resumo da citação: autor e texto de uma linha (legenda ou rótulo da mídia).
({String autor, String texto, bool ehImagem}) resumoDaCitacao(
  WhatsAppMessage m,
  String? contato,
) {
  final tipo = m.rawType.toLowerCase();
  final autor = m.isOutbound
      ? 'Você'
      : ((m.contactName ?? '').trim().isNotEmpty
          ? m.contactName!.trim()
          : ((contato ?? '').trim().isNotEmpty
              ? contato!.trim()
              : formatWhatsAppPhone(m.phoneNumber)));
  final legenda = umaLinha(m.message ?? '');
  String rotulo;
  switch (tipo) {
    case 'text':
      rotulo = '';
      break;
    case 'image':
    case 'sticker':
      rotulo = 'Foto';
      break;
    case 'document':
      rotulo = (m.mediaFileName ?? '').isNotEmpty
          ? 'Documento · ${m.mediaFileName}'
          : 'Documento';
      break;
    case 'audio':
    case 'voice':
      rotulo = 'Mensagem de voz';
      break;
    case 'video':
      rotulo = 'Vídeo';
      break;
    default:
      rotulo = 'Mensagem';
  }
  return (
    autor: autor,
    texto: legenda.isNotEmpty ? legenda : rotulo,
    ehImagem: tipo == 'image' || tipo == 'sticker',
  );
}

// ─── Falha de envio ─────────────────────────────────────────────────────────

class WhatsAppMotivoFalha {
  final int? codigo;
  final String titulo;
  final String? detalhe;
  final String? acao;
  const WhatsAppMotivoFalha({
    this.codigo,
    required this.titulo,
    this.detalhe,
    this.acao,
  });

  /// "Fora da janela de 24 h · Envie um template aprovado".
  String get frase => acao != null ? '$titulo · $acao' : titulo;

  /// Frase completa: título, explicação e ação.
  String get fraseCompleta {
    String comPonto(String t) => RegExp(r'[.!?]$').hasMatch(t) ? t : '$t.';
    return [
      comPonto(titulo),
      if (detalhe != null) comPonto(detalhe!),
      if (acao != null) comPonto(acao!),
    ].join(' ');
  }
}

/// Falhas que REENVIAR NÃO RESOLVE — espelho de `FALHAS_SEM_REENVIO` do back
/// e do web (mesmas frases).
const Map<int, String> kFalhasSemReenvio = {
  131047:
      'Fora da janela de 24 horas neste número: reenviar não adianta. Envie um template aprovado.',
  200: 'Sem permissão para enviar por este número na Meta: reenviar não adianta.',
  10: 'Sem permissão para enviar por este número na Meta: reenviar não adianta.',
  131026:
      'Este número não está recebendo mensagens do WhatsApp (sem WhatsApp, bloqueou ou app desatualizado).',
  131049:
      'A Meta segurou a mensagem para não saturar o cliente. Tente mais tarde, de preferência com o cliente respondendo antes.',
  130472: 'Número em experimento da Meta: não recebe esta mensagem.',
  131051: 'Tipo de mensagem não suportado pela Meta: reenviar não adianta.',
  131052: 'A Meta não conseguiu baixar a mídia: envie o arquivo de novo pelo chat.',
  131053:
      'A Meta não reconheceu o arquivo (formato inválido): grave ou anexe de novo em outro formato.',
};

const Map<int, WhatsAppMotivoFalha> _motivosConhecidos = {
  200: WhatsAppMotivoFalha(
    titulo: 'A conta do WhatsApp Business recusou o envio por falta de permissão',
    detalhe:
        'Erro 200 da Meta. Não é a janela de 24h: o token ou o número da integração não tem permissão para enviar por esta conta.',
    acao: 'Avise o administrador para revisar o token e o número na integração',
  ),
  131047: WhatsAppMotivoFalha(
    titulo: 'Fora da janela de 24 h',
    detalhe:
        'A Meta só aceita texto livre até 24 h depois da última mensagem do cliente.',
    acao: 'Envie um template aprovado',
  ),
  131026: WhatsAppMotivoFalha(
    titulo: 'Número não recebe mensagens',
    detalhe:
        'O contato não tem WhatsApp, bloqueou a empresa ou não aceitou os termos do WhatsApp.',
    acao: 'Confirme o número com o cliente',
  ),
  131049: WhatsAppMotivoFalha(
    titulo: 'Limite de mensagens de marketing para este contato',
    detalhe:
        'A Meta segura templates de marketing para quem não interage com a empresa.',
    acao: 'Aguarde o cliente responder ou use um template de utilidade',
  ),
  131048: WhatsAppMotivoFalha(
    titulo: 'Limite de envio da conta atingido',
    detalhe: 'A conta da empresa chegou ao teto de mensagens permitido pela Meta.',
    acao: 'Aguarde a liberação do limite',
  ),
  131056: WhatsAppMotivoFalha(
    titulo: 'Muitas mensagens para o mesmo número em pouco tempo',
    acao: 'Aguarde alguns minutos e tente de novo',
  ),
  130472: WhatsAppMotivoFalha(
    titulo: 'Número em teste da Meta',
    detalhe: 'A Meta está avaliando a qualidade deste número e limitou o envio.',
  ),
  131031: WhatsAppMotivoFalha(
    titulo: 'Conta bloqueada pela Meta',
    acao: 'Verifique a conta no Gerenciador de Negócios da Meta',
  ),
  132015: WhatsAppMotivoFalha(
    titulo: 'Template pausado',
    acao: 'Use outro template ou revise este no Gerenciador da Meta',
  ),
  132016: WhatsAppMotivoFalha(
    titulo: 'Template desativado',
    acao: 'Use outro template aprovado',
  ),
  132001: WhatsAppMotivoFalha(
    titulo: 'Template não existe ou não foi aprovado',
    acao: 'Confira o nome e a aprovação do template na Meta',
  ),
  131030: WhatsAppMotivoFalha(
    titulo: 'Número fora da lista permitida (modo teste)',
    detalhe: 'A conta ainda está em teste e só envia para números cadastrados.',
    acao: 'Cadastre o número na Meta ou publique a conta',
  ),
  100: WhatsAppMotivoFalha(
    titulo: 'Parâmetros inválidos',
    detalhe: 'A Meta recusou o conteúdo da mensagem.',
  ),
  131009: WhatsAppMotivoFalha(
    titulo: 'Parâmetros inválidos',
    detalhe: 'A Meta recusou o conteúdo da mensagem.',
  ),
  131053: WhatsAppMotivoFalha(
    titulo: 'Falha no envio da mídia',
    detalhe: 'A Meta não conseguiu baixar ou aceitar o arquivo enviado.',
    acao: 'Tente enviar o arquivo de novo',
  ),
};

class _FalhaWebhook {
  final dynamic code;
  final String? title;
  final String? message;
  final String? details;
  const _FalhaWebhook({this.code, this.title, this.message, this.details});
}

String? _limparOuNulo(dynamic v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

int? _codigoNumerico(dynamic v) {
  if (v is int) return v;
  if (v is num && v.isFinite) return v.toInt();
  if (v is String && RegExp(r'^\d+$').hasMatch(v.trim())) return int.parse(v.trim());
  return null;
}

/// `webhookData.failure` gravado pelo back ou, como reserva, o primeiro item
/// de `errors` no formato cru da Meta.
_FalhaWebhook? _falhaDoWebhook(Map<String, dynamic>? wd) {
  if (wd == null) return null;
  final failure = _objeto(wd['failure']);
  if (failure != null) {
    return _FalhaWebhook(
      code: failure['code'],
      title: _limparOuNulo(failure['title']),
      message: _limparOuNulo(failure['message']),
      details: _limparOuNulo(failure['details']),
    );
  }
  final errors = wd['errors'];
  if (errors is List && errors.isNotEmpty) {
    final e = _objeto(errors.first);
    if (e != null) {
      final errorData = _objeto(e['error_data']);
      return _FalhaWebhook(
        code: e['code'],
        title: _limparOuNulo(e['title']),
        message: _limparOuNulo(e['message']),
        details: _limparOuNulo(errorData?['details']),
      );
    }
  }
  return null;
}

/// Motivo para NÃO reenviar, ou null se reenviar pode dar certo. 131053 em
/// áudio tem reenvio (o back converte a nota e manda de novo).
String? motivoParaNaoReenviar(WhatsAppMessage m) {
  final falha = _falhaDoWebhook(m.webhookData);
  if (falha == null) return null;
  final codigo = _codigoNumerico(falha.code);
  if (codigo == null) return null;
  final tipo = m.rawType.toLowerCase();
  if (codigo == 131053 && (tipo == 'audio' || tipo == 'voice')) return null;
  return kFalhasSemReenvio[codigo];
}

/// A saída desta falha é mandar TEMPLATE (janela de 24 h fechada).
bool falhaPedeTemplate(WhatsAppMessage m) =>
    _codigoNumerico(_falhaDoWebhook(m.webhookData)?.code) == 131047;

/// Motivo da falha em pt-BR. Código conhecido: nosso texto; desconhecido:
/// título/mensagem crus da Meta. Sem falha gravada: null.
WhatsAppMotivoFalha? motivoDaFalha(WhatsAppMessage m) {
  final falha = _falhaDoWebhook(m.webhookData);
  if (falha == null) return null;
  final codigo = _codigoNumerico(falha.code);
  final textoMeta = [falha.title, falha.message, falha.details]
      .whereType<String>()
      .join(' ');

  final conhecido = codigo != null ? _motivosConhecidos[codigo] : null;
  if (conhecido != null) {
    if (codigo == 131047 &&
        textoMeta.isNotEmpty &&
        RegExp(
          r'outro\s+n[uú]mero|another\s+(phone\s+)?number|different\s+(phone\s+)?number|n[uú]mero\s+diferente',
          caseSensitive: false,
        ).hasMatch(textoMeta)) {
      return WhatsAppMotivoFalha(
        codigo: codigo,
        titulo: conhecido.titulo,
        detalhe:
            'O cliente escreveu para outro número da empresa; a janela de 24 h vale por número.',
        acao: conhecido.acao,
      );
    }
    return WhatsAppMotivoFalha(
      codigo: codigo,
      titulo: conhecido.titulo,
      detalhe: conhecido.detalhe,
      acao: conhecido.acao,
    );
  }

  final titulo = falha.title ??
      falha.message ??
      (codigo != null ? 'Erro $codigo da Meta' : null);
  if (titulo == null) return null;
  final detalhe = falha.title != null &&
          falha.message != null &&
          falha.message != falha.title
      ? [falha.message, falha.details].whereType<String>().join(' ')
      : falha.details;
  return WhatsAppMotivoFalha(
    codigo: codigo,
    titulo: titulo,
    detalhe: _limparOuNulo(detalhe),
  );
}
