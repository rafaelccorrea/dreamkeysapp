import 'dart:async';
import 'dart:io' show File;
import 'dart:math' show max;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/secure_storage_service.dart';
import '../../../shared/utils/jwt_utils.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../notifications/services/notification_websocket_service.dart';
import '../models/whatsapp_anexos.dart';
import '../models/whatsapp_message_content.dart' show acharCitada;
import '../models/whatsapp_midia.dart';
import '../models/whatsapp_models.dart';
import '../services/whatsapp_service.dart';
import '../widgets/whatsapp_bandeja_de_anexos.dart';
import '../widgets/whatsapp_gravador_de_voz.dart';
import '../widgets/whatsapp_tocador_de_audio.dart';
import '../widgets/whatsapp_conversation_card.dart'
    show WhatsAppAvatar, whatsAppSourceIcon;
import '../widgets/whatsapp_message_bubble.dart';
import '../widgets/whatsapp_send_template_sheet.dart';

/// Tela **Conversa do WhatsApp** (`/whatsapp/:phoneNumber`) — thread de
/// mensagens de um contato, com envio de texto e anexos (canal oficial ou
/// QR Code) e de template quando a janela de 24h da API oficial está fechada.
///
/// Paridade com o `WhatsAppConversationViewer.tsx` do painel:
/// - mensagens do backend em ordem desc (paginação por offset);
/// - marca as recebidas como lidas ao abrir;
/// - texto livre e anexos só com QR Code ativo OU janela de 24h aberta;
/// - anexos em fila (até 30), cada um uma mensagem, texto como legenda do
///   primeiro (29/09/2026);
/// - mídia recebida: imagem em tela cheia, áudio/vídeo tocam, documento abre
///   (29/09/2026);
/// - "Assumir conversa" para quem não é o responsável (29/09/2026);
/// - "Finalizar conversa" tira a thread das abas ativas.
class WhatsAppConversationPage extends StatefulWidget {
  final String phoneNumber;
  final WhatsAppConversation? conversation;

  const WhatsAppConversationPage({
    super.key,
    required this.phoneNumber,
    this.conversation,
  });

  @override
  State<WhatsAppConversationPage> createState() =>
      _WhatsAppConversationPageState();
}

class _WhatsAppConversationPageState extends State<WhatsAppConversationPage> {
  static const int _pageSize = 50;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _composerController = TextEditingController();
  final FocusNode _composerFocus = FocusNode();

  /// Mensagens em ordem cronológica (mais antiga → mais recente).
  List<WhatsAppMessage> _messages = const [];
  int _total = 0;
  bool _loading = true;
  bool _loadingOlder = false;
  String? _error;
  // Guardado junto da mensagem: sem o código HTTP não dá para distinguir
  // "sem permissão" de "servidor fora do ar".
  int _errorStatus = 0;
  bool _sending = false;
  WhatsAppIntegrationStatus? _integrationStatus;
  Timer? _pollTimer;

  /// Usuário logado — decide se "Assumir conversa" aparece (29/09/2026).
  String? _currentUserId;
  bool _assumindo = false;

  /// Fila de anexos do composer, na ordem de envio (29/09/2026).
  List<WhatsAppAnexo> _anexos = const [];
  bool _preparandoAnexos = false;

  /// Progresso do lote em envio ("Enviando 2 de 5"); null fora do envio.
  ({int atual, int total})? _progressoDoLote;

  /// O back recusou um envio por janela de 24h fechada (ex.: o cliente
  /// escreveu para outro número da empresa): guarda a última recebida daquele
  /// momento. A caixa trava e o caminho vira template até chegar uma nova
  /// mensagem do cliente — paridade com `setIs24HoursWindowOpen(false)`.
  String? _janelaFechadaNaInbound;

  /// Nota de voz do compositor (gravar → prévia → enviar).
  final WhatsAppGravadorDeVoz _gravador = WhatsAppGravadorDeVoz();

  /// Renovações de URL de mídia em andamento, uma por mensagem.
  final Map<String, Future<String?>> _renovacoes = {};

  final ImagePicker _imagePicker = ImagePicker();

  bool get _hasOlder => _messages.length < _total;

  bool get _canSend =>
      ModuleAccessService.instance.hasPermission('whatsapp:send');

  bool get _canViewMessages =>
      ModuleAccessService.instance.hasPermission('whatsapp:view_messages');

  /// Responsável atual da conversa — paridade com
  /// `getConversationAssignedSdrId` do web: a mensagem mais recente que tem
  /// responsável.
  String get _responsavelAtualId {
    for (var i = _messages.length - 1; i >= 0; i--) {
      final id = (_messages[i].assignedToId ?? '').trim();
      if (id.isNotEmpty) return id;
    }
    return '';
  }

  /// "Assumir conversa": com whatsapp:view_messages, conversa com mensagens e
  /// responsável diferente de quem está logado (a fila não tem responsável).
  bool get _podeAssumir =>
      _canViewMessages &&
      _messages.isNotEmpty &&
      _responsavelAtualId != _currentUserId;

  /// Canal não oficial (QR Code) ativo para o atendimento?
  bool get _usesUnofficial => _integrationStatus?.usesUnofficialChat ?? false;

  /// Última mensagem recebida do contato (para a janela de 24h).
  WhatsAppMessage? get _lastInbound {
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].isInbound) return _messages[i];
    }
    return null;
  }

  /// Janela de 24h da API oficial — paridade com o painel: aberta se a última
  /// mensagem do contato tem menos de 24h.
  bool get _is24hWindowOpen {
    final last = _lastInbound?.createdAt;
    if (last == null) return false;
    return DateTime.now().difference(last.toLocal()).inHours < 24;
  }

  /// O último envio voltou com erro de janela e o cliente ainda não escreveu
  /// de novo.
  bool get _janelaFechadaNoEnvio {
    final marca = _janelaFechadaNaInbound;
    return marca != null && marca == _lastInbound?.id;
  }

  /// Texto livre (e anexo) permitido? QR Code sempre; oficial exige janela
  /// aberta — e não recusada pelo back no último envio.
  bool get _canSendFreeText =>
      _usesUnofficial || (_is24hWindowOpen && !_janelaFechadaNoEnvio);

  String get _displayName {
    final c = widget.conversation;
    if (c != null && c.displayName.trim().isNotEmpty) return c.displayName;
    final fromMessages = _messages
        .where((m) => (m.contactName ?? '').trim().isNotEmpty)
        .map((m) => m.contactName!.trim());
    if (fromMessages.isNotEmpty) return fromMessages.last;
    return formatWhatsAppPhone(widget.phoneNumber);
  }

  String? get _clientId =>
      widget.conversation?.clientId ??
      _messages.where((m) => m.clientId != null).map((m) => m.clientId).lastOrNull;

  @override
  void initState() {
    super.initState();
    _gravador.addListener(_aoMudarGravador);
    _bootstrap();
    unawaited(_resolverUsuarioAtual());
    // Poll leve enquanto a thread está aberta (o painel usa socket/poll).
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && !_loading && !_sending) _syncLatest();
    });
    // Tempo real (29/09/2026): mensagem nova ou mudança de status desta
    // conversa chega pelo socket, como no web; o poll de 20 s vira só a rede
    // de segurança.
    _aoVivo = NotificationWebSocketService.instance.eventosAoVivo.listen((e) {
      if (e.tipo == 'new_whatsapp_message' && !_ehDestaConversa(e.dados)) {
        return;
      }
      if (e.tipo != 'new_whatsapp_message' &&
          e.tipo != 'whatsapp_message_status') {
        return;
      }
      _debounceAoVivo?.cancel();
      _debounceAoVivo = Timer(const Duration(milliseconds: 400), () {
        if (mounted && !_loading && !_sending) _syncLatest();
      });
    });
  }

  StreamSubscription<AvisoAoVivo>? _aoVivo;
  Timer? _debounceAoVivo;

  /// Mesmo número, comparando os 8 últimos dígitos (com ou sem o 9 e o DDI).
  bool _ehDestaConversa(Map<String, dynamic> dados) {
    String digitos(String v) => v.replaceAll(RegExp(r'\D'), '');
    String cauda(String v) => v.length > 8 ? v.substring(v.length - 8) : v;
    final dele = digitos((dados['phoneNumber'] ?? '').toString());
    final meu = digitos(widget.phoneNumber);
    if (dele.isEmpty || meu.isEmpty) return false;
    return cauda(dele) == cauda(meu);
  }

  @override
  void dispose() {
    _aoVivo?.cancel();
    _debounceAoVivo?.cancel();
    _pollTimer?.cancel();
    _scrollController.dispose();
    _composerController.dispose();
    _composerFocus.dispose();
    _gravador.removeListener(_aoMudarGravador);
    _gravador.dispose();
    // Áudio tocando não segue tocando depois de sair da conversa.
    unawaited(WhatsAppTocadorDeAudio.instance.parar());
    super.dispose();
  }

  void _aoMudarGravador() {
    if (mounted) setState(() {});
  }

  // ─── Nota de voz ─────────────────────────────────────────────────────────

  /// Microfone: mesma regra de anexar (permissão, 1ª mensagem do cliente,
  /// janela de 24h) — a nota sai pelo mesmo envio de mídia.
  Future<void> _comecarGravacao({required bool segurando}) async {
    final motivo = _motivoDeNaoAnexar();
    if (motivo != null) {
      _showSnack(
        motivo.replaceFirst('para anexar', 'para gravar'),
        isError: true,
      );
      return;
    }
    final erro = await _gravador.iniciar(segurando: segurando);
    if (erro != null && mounted) _showSnack(erro, isError: true);
  }

  /// Envia a nota da prévia (uma mensagem de áudio, sem legenda). Falhou:
  /// a nota volta para a prévia; sem resposta do servidor, não volta (pode
  /// ter saído — mesma regra do lote de anexos).
  Future<void> _enviarNotaDeVoz() async {
    if (_sending) return;
    if (!_canSend) {
      _showSnack(
        'Você não tem permissão para enviar mensagens WhatsApp.',
        isError: true,
      );
      return;
    }
    if (!_canSendFreeText) {
      _showSnack(_motivoDeNaoEnviar(), isError: true);
      return;
    }
    final nota = _gravador.consumir();
    if (nota == null) return;
    final anexo = await WhatsAppAnexo.doArquivo(nota.caminho, nome: nota.nome);
    if (!mounted) return;
    if (anexo == null) {
      _showSnack('A gravação se perdeu. Grave de novo.', isError: true);
      return;
    }
    final viaQrCode = _usesUnofficial;
    setState(() => _sending = true);
    final res = await WhatsAppService.instance.sendMedia(
      to: widget.phoneNumber,
      anexo: anexo,
      caption: '',
      clientId: _clientId,
      viaUnofficial: viaQrCode,
    );
    if (!mounted) return;
    setState(() => _sending = false);

    if (res.success) {
      unawaited(_apagarArquivoDaNota(nota.caminho));
      await _syncLatest();
      _scrollToBottom();
      return;
    }
    final erro = res.error;
    if (erro is Map && erro['naoConfirmado'] == true) {
      _showSnack(
        'A resposta do servidor não chegou. A nota de voz pode ter saído: '
        'confira a conversa antes de gravar de novo.',
        isError: true,
      );
      await _syncLatest();
      return;
    }
    final motivo = (res.message ?? '').trim();
    if (!viaQrCode && _ehErroDeJanela24h(motivo)) {
      setState(() => _janelaFechadaNaInbound = _lastInbound?.id ?? '');
    }
    _gravador.restaurar(nota);
    _showSnack(
      motivo.isNotEmpty
          ? motivo
          : 'Não foi possível enviar a nota de voz. Toque em enviar para '
              'tentar de novo.',
      isError: true,
    );
  }

  Future<void> _apagarArquivoDaNota(String caminho) async {
    try {
      final f = File(caminho);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<void> _bootstrap() async {
    unawaited(_loadIntegrationStatus());
    await _loadMessages();
  }

  /// Id do usuário logado: o do ModuleAccessService (lido do JWT no login)
  /// ou, se ainda não carregou, o do próprio token — mesmo caminho da caixa.
  Future<void> _resolverUsuarioAtual() async {
    var id = ModuleAccessService.instance.userId;
    if (id == null || id.isEmpty) {
      try {
        final token = await SecureStorageService.instance.getAccessToken();
        if (token != null) {
          final payload = JwtUtils.decodeToken(token);
          id = payload?['sub']?.toString() ?? payload?['userId']?.toString();
        }
      } catch (e) {
        debugPrint('❌ [WHATSAPP] _resolverUsuarioAtual: $e');
      }
    }
    if (!mounted) return;
    setState(() => _currentUserId = id);
  }

  Future<void> _loadIntegrationStatus() async {
    final status = await WhatsAppService.instance.getIntegrationStatus();
    if (!mounted) return;
    setState(() => _integrationStatus = status);
  }

  Future<void> _loadMessages() async {
    setState(() {
      _loading = true;
      _error = null;
      _errorStatus = 0;
    });
    final res = await WhatsAppService.instance.getMessages(
      phoneNumber: widget.phoneNumber,
      limit: _pageSize,
      offset: 0,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        // Backend devolve desc (mais recente primeiro) → inverte p/ cronológica.
        _messages = _manterUrlsValidas(res.data!.messages.reversed.toList());
        _total = res.data!.total;
      } else {
        _error = res.message ?? 'Erro ao carregar mensagens';
        _errorStatus = res.statusCode;
      }
    });
    if (res.success) _markInboundAsRead();
  }

  /// A cada releitura o back assina as URLs de novo e a imagem recarregava
  /// (piscando) a cada 20 s. Mantém a URL já carregada enquanto ela vale
  /// (29/09/2026); troca quando vence ou quando a antiga não era assinada.
  List<WhatsAppMessage> _manterUrlsValidas(List<WhatsAppMessage> novas) {
    if (_messages.isEmpty) return novas;
    final antigas = {for (final m in _messages) m.id: m};
    return [for (final n in novas) _comUrlMantida(antigas[n.id], n)];
  }

  static WhatsAppMessage _comUrlMantida(
    WhatsAppMessage? antiga,
    WhatsAppMessage nova,
  ) {
    final url = urlDeMidiaParaManter(antiga?.mediaUrl, nova.mediaUrl);
    if (url == null || url == nova.mediaUrl) return nova;
    return nova.copyWith(mediaUrl: url);
  }

  /// Renova a URL assinada de uma mídia (vale 1 h no S3). O web chama
  /// GET /whatsapp/messages/:id, rota que o back ainda não tem (404); sem
  /// ela, relê a janela da thread onde a mensagem está — a lista devolve as
  /// URLs assinadas de novo. Uma renovação por mensagem por vez.
  Future<String?> _renovarMidia(WhatsAppMessage m) {
    final emCurso = _renovacoes[m.id];
    if (emCurso != null) return emCurso;
    final futuro =
        _executarRenovacao(m).whenComplete(() => _renovacoes.remove(m.id));
    _renovacoes[m.id] = futuro;
    return futuro;
  }

  Future<String?> _executarRenovacao(WhatsAppMessage m) async {
    // O web só pede a mensagem de novo com whatsapp:view_messages.
    if (!_canViewMessages) return null;
    final atual = (m.mediaUrl ?? '').trim();
    String? nova;

    final direta = await WhatsAppService.instance.getMessage(m.id);
    final urlDireta = (direta?.mediaUrl ?? '').trim();
    if (urlDireta.isNotEmpty && urlDireta != atual) nova = urlDireta;

    if (nova == null) {
      final i = _messages.indexWhere((x) => x.id == m.id);
      if (i >= 0) {
        // Posição a partir da mais recente (a ordem do back); a janela de 25
        // cobre mensagens que chegaram depois e deslocaram o offset.
        final aPartirDaMaisRecente = _messages.length - 1 - i;
        final res = await WhatsAppService.instance.getMessages(
          phoneNumber: widget.phoneNumber,
          limit: 25,
          offset: max(0, aPartirDaMaisRecente - 12),
        );
        if (res.success && res.data != null) {
          for (final x in res.data!.messages) {
            final u = (x.mediaUrl ?? '').trim();
            if (x.id == m.id && u.isNotEmpty && u != atual) {
              nova = u;
              break;
            }
          }
        }
      }
    }

    if (nova == null || !mounted) return nova;
    final url = nova;
    setState(() {
      _messages = [
        for (final x in _messages)
          x.id == m.id ? x.copyWith(mediaUrl: url) : x,
      ];
    });
    return url;
  }

  /// Ressincroniza a primeira página sem "piscar" a tela (poll / pós-envio).
  Future<void> _syncLatest() async {
    final res = await WhatsAppService.instance.getMessages(
      phoneNumber: widget.phoneNumber,
      limit: _pageSize,
      offset: 0,
    );
    if (!mounted || !res.success || res.data == null) return;
    final latest = _manterUrlsValidas(res.data!.messages.reversed.toList());
    // Preserva as páginas antigas já carregadas: mantém as mensagens que não
    // estão na primeira página e anexa a página nova.
    final latestIds = latest.map((m) => m.id).toSet();
    final older = _messages.where((m) => !latestIds.contains(m.id)).toList();
    final hadNew = latest.length + older.length != _messages.length;
    setState(() {
      _messages = [...older, ...latest];
      _total = res.data!.total;
    });
    if (hadNew) _markInboundAsRead();
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasOlder) return;
    setState(() => _loadingOlder = true);
    final res = await WhatsAppService.instance.getMessages(
      phoneNumber: widget.phoneNumber,
      limit: _pageSize,
      offset: _messages.length,
    );
    if (!mounted) return;
    setState(() {
      _loadingOlder = false;
      if (res.success && res.data != null) {
        final older = res.data!.messages.reversed.toList();
        final existing = _messages.map((m) => m.id).toSet();
        _messages = [
          ...older.where((m) => !existing.contains(m.id)),
          ..._messages,
        ];
        _total = res.data!.total;
      }
    });
  }

  /// Marca como lidas as recebidas ainda não lidas (page atual) — espelha o
  /// comportamento do painel ao abrir a conversa.
  void _markInboundAsRead() {
    final unread = _messages.where((m) => m.isUnread).take(40).toList();
    if (unread.isEmpty) return;
    unawaited(Future.wait(
      unread.map((m) => WhatsAppService.instance.markAsRead(m.id)),
    ));
  }

  // ─── Ações ───────────────────────────────────────────────────────────────

  /// Mesma leitura do web (`ehErroDeJanela24h`): a frase do back fala da
  /// janela de 24 horas.
  static bool _ehErroDeJanela24h(String mensagem) {
    final m = mensagem.toLowerCase();
    return m.contains('janela de 24 horas') ||
        m.contains('24 horas') ||
        m.contains('24h');
  }

  /// Por que não dá para anexar agora (mesmas frases do web).
  String? _motivoDeNaoAnexar() {
    if (_sending) return 'Aguarde o envio terminar para anexar mais.';
    if (!_canSend) {
      return 'Você não tem permissão para enviar mensagens WhatsApp.';
    }
    if (!_usesUnofficial && _lastInbound == null) {
      return 'Aguarde o cliente enviar a primeira mensagem para anexar.';
    }
    if (!_canSendFreeText) {
      return _janelaFechadaNoEnvio
          ? 'Não é possível anexar: a janela de 24 horas não está aberta no número que envia. Envie um template.'
          : 'Não é possível anexar: a janela de 24 horas expirou.';
    }
    return null;
  }

  /// Por que não dá para enviar agora (a janela venceu com a caixa aberta).
  String _motivoDeNaoEnviar() {
    if (!_usesUnofficial && _lastInbound == null) {
      return 'Aguarde o cliente enviar a primeira mensagem.';
    }
    if (_janelaFechadaNoEnvio) {
      return 'Janela de 24 horas fechada no número que envia: envie um template.';
    }
    return 'Não é possível enviar: janela de 24 horas expirada.';
  }

  /// Envia o que está no composer: texto e/ou a fila de anexos, uma mensagem
  /// por anexo, na ordem da bandeja (29/09/2026). Paridade com
  /// `handleSendMessage` do web:
  ///  - o texto vai como legenda do 1º anexo (ou antes, como mensagem
  ///    própria, se passar de 1024 caracteres ou se o 1º for áudio);
  ///  - erro de janela de 24h PARA o lote: o que não saiu volta para a
  ///    bandeja, o texto volta para a caixa e a conversa passa a pedir
  ///    template;
  ///  - falha comum não para o lote: o que falhou volta para a bandeja e o
  ///    aviso traz a frase do back;
  ///  - sem resposta do servidor (timeout, queda), o anexo NÃO volta: ele pode
  ///    ter saído, e reenviar duplicaria na cliente.
  Future<void> _enviar() async {
    if (_sending || _preparandoAnexos) return;
    final texto = _composerController.text.trim();
    final lote = List<WhatsAppAnexo>.of(_anexos);
    if (texto.isEmpty && lote.isEmpty) return;
    if (!_canSend) {
      _showSnack(
        'Você não tem permissão para enviar mensagens WhatsApp.',
        isError: true,
      );
      return;
    }
    if (!_canSendFreeText) {
      _showSnack(_motivoDeNaoEnviar(), isError: true);
      return;
    }

    final trabalhos = montarTrabalhosDeEnvio(lote, texto);
    final temAnexo = lote.isNotEmpty;
    final viaQrCode = _usesUnofficial;
    final clientId = _clientId;
    setState(() {
      _sending = true;
      _anexos = const [];
      _composerController.clear();
      if (temAnexo) _progressoDoLote = (atual: 1, total: trabalhos.length);
    });

    var enviouAlguma = false;
    var houveNaoConfirmado = false;
    var janelaFechou = false;
    final falhas = <String>[];
    final devolver = <WhatsAppAnexo>[];
    String? textoDevolvido;

    for (var i = 0; i < trabalhos.length; i++) {
      final trabalho = trabalhos[i];
      final anexo = trabalho.anexo;
      if (temAnexo && mounted) {
        setState(
            () => _progressoDoLote = (atual: i + 1, total: trabalhos.length));
      }
      final res = anexo == null
          ? await WhatsAppService.instance.sendText(
              to: widget.phoneNumber,
              message: trabalho.texto,
              clientId: clientId,
              viaUnofficial: viaQrCode,
            )
          : await WhatsAppService.instance.sendMedia(
              to: widget.phoneNumber,
              anexo: anexo,
              caption: trabalho.texto,
              clientId: clientId,
              viaUnofficial: viaQrCode,
            );
      if (res.success) {
        enviouAlguma = true;
        // Lote: a bolha de cada envio aparece enquanto os outros sobem.
        if (trabalhos.length > 1 && mounted) unawaited(_syncLatest());
        continue;
      }
      final motivo = (res.message ?? '').trim();
      if (!viaQrCode && _ehErroDeJanela24h(motivo)) {
        for (final resto in trabalhos.skip(i)) {
          final a = resto.anexo;
          if (a != null) devolver.add(a);
        }
        if (trabalho.texto.isNotEmpty) textoDevolvido = trabalho.texto;
        janelaFechou = true;
        falhas
          ..clear()
          ..add(motivo);
        break;
      }
      final erro = res.error;
      if (anexo != null && erro is Map && erro['naoConfirmado'] == true) {
        houveNaoConfirmado = true;
        continue;
      }
      falhas.add(motivo.isNotEmpty
          ? motivo
          : (anexo == null
              ? 'Não foi possível enviar a mensagem.'
              : 'Não foi possível enviar "${anexo.nome}".'));
      if (anexo != null) devolver.add(anexo);
      if (trabalho.texto.isNotEmpty) textoDevolvido ??= trabalho.texto;
    }

    if (!mounted) return;
    setState(() {
      _sending = false;
      _progressoDoLote = null;
      if (devolver.isNotEmpty) _anexos = [...devolver, ..._anexos];
      final t = textoDevolvido;
      if (t != null && _composerController.text.trim().isEmpty) {
        _composerController.text = t;
      }
      if (janelaFechou) _janelaFechadaNaInbound = _lastInbound?.id ?? '';
    });

    if (falhas.length == 1) {
      _showSnack(falhas.first, isError: true);
    } else if (falhas.length > 1) {
      _showSnack(
        '${falhas.length} de ${trabalhos.length} não foram enviadas. O que '
        'falhou voltou para a caixa: toque em enviar para tentar de novo.',
        isError: true,
      );
    }
    if (houveNaoConfirmado) {
      _showSnack(
        'A resposta do servidor não chegou para uma ou mais mensagens. Elas '
        'podem ter saído: confira a conversa antes de reenviar.',
        isError: true,
      );
    }
    if (enviouAlguma || houveNaoConfirmado) {
      await _syncLatest();
      _scrollToBottom();
    }
  }

  // ─── Anexos ──────────────────────────────────────────────────────────────

  /// Botão de clipe: câmera, galeria ou arquivo, com a regra do canal.
  Future<void> _abrirMenuDeAnexo() async {
    final motivo = _motivoDeNaoAnexar();
    if (motivo != null) {
      _showSnack(motivo, isError: true);
      return;
    }
    if (_anexos.length >= kMaximoDeAnexos) {
      _showSnack('Máximo de $kMaximoDeAnexos arquivos por envio.',
          isError: true);
      return;
    }
    FocusScope.of(context).unfocus();
    final origem = await WhatsAppOrigemDoAnexoSheet.show(
      context,
      naoOficial: _usesUnofficial,
    );
    if (origem == null || !mounted) return;
    switch (origem) {
      case WhatsAppOrigemDoAnexo.camera:
        await _anexarDaCamera();
        break;
      case WhatsAppOrigemDoAnexo.galeria:
        await _anexarDaGaleria();
        break;
      case WhatsAppOrigemDoAnexo.arquivo:
        await _anexarArquivos();
        break;
    }
  }

  /// Foto da câmera. `imageQuality`/tamanho máximo: o iPhone entrega HEIC
  /// (a Meta recusa) e fotos de 12MP passam dos 5MB da API oficial — a
  /// recompressão sai em JPEG, como o WhatsApp faz ao enviar.
  Future<void> _anexarDaCamera() async {
    try {
      final foto = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 2560,
        maxHeight: 2560,
        requestFullMetadata: false,
      );
      if (foto == null) return;
      await _acrescentar([_ArquivoEscolhido(foto.path, foto.name)]);
    } on PlatformException catch (e) {
      _avisarFalhaDoSeletor(e, camera: true);
    } catch (e) {
      debugPrint('❌ [WHATSAPP] câmera: $e');
      _showSnack(
        'Não foi possível abrir a câmera. Feche e abra o app e tente de novo.',
        isError: true,
      );
    }
  }

  /// Galeria: só fotos na API oficial; fotos e vídeos no QR Code.
  Future<void> _anexarDaGaleria() async {
    final restante = kMaximoDeAnexos - _anexos.length;
    if (restante <= 0) return;
    try {
      final List<XFile> itens = _usesUnofficial
          ? await _imagePicker.pickMultipleMedia(
              imageQuality: 85,
              maxWidth: 2560,
              maxHeight: 2560,
              limit: restante,
              requestFullMetadata: false,
            )
          : await _imagePicker.pickMultiImage(
              imageQuality: 85,
              maxWidth: 2560,
              maxHeight: 2560,
              limit: restante,
              requestFullMetadata: false,
            );
      if (itens.isEmpty) return;
      await _acrescentar([
        for (final x in itens) _ArquivoEscolhido(x.path, x.name),
      ]);
    } on PlatformException catch (e) {
      _avisarFalhaDoSeletor(e);
    } catch (e) {
      debugPrint('❌ [WHATSAPP] galeria: $e');
      _showSnack(
        'Não foi possível abrir a galeria. Feche e abra o app e tente de '
        'novo.',
        isError: true,
      );
    }
  }

  /// Arquivo: na API oficial, documentos e áudios da lista da Meta (o mesmo
  /// `accept` do clipe do web); no QR Code, qualquer tipo.
  Future<void> _anexarArquivos() async {
    try {
      final resultado = _usesUnofficial
          ? await FilePicker.pickFiles(type: FileType.any)
          : await FilePicker.pickFiles(
              type: FileType.custom,
              allowedExtensions: kExtensoesDoAnexoOficial,
            );
      if (resultado == null || resultado.files.isEmpty) return;
      final escolhidos = <_ArquivoEscolhido>[];
      for (final f in resultado.files) {
        final caminho = f.path;
        if (caminho == null || caminho.isEmpty) continue;
        escolhidos.add(_ArquivoEscolhido(caminho, f.name, f.size));
      }
      await _acrescentar(escolhidos);
    } on PlatformException catch (e) {
      _avisarFalhaDoSeletor(e);
    } catch (e) {
      debugPrint('❌ [WHATSAPP] arquivos: $e');
      _showSnack(
        'Não foi possível abrir os arquivos. Feche e abra o app e tente de '
        'novo.',
        isError: true,
      );
    }
  }

  void _avisarFalhaDoSeletor(PlatformException e, {bool camera = false}) {
    final codigo = e.code.toLowerCase();
    if (codigo.contains('denied') || codigo.contains('permission')) {
      _showSnack(
        camera
            ? 'Sem acesso à câmera. Libere a permissão do Intellisys nas configurações do aparelho.'
            : 'Sem acesso às fotos e arquivos. Libere a permissão do Intellisys nas configurações do aparelho.',
        isError: true,
      );
      return;
    }
    // Detalhe técnico só no log; na tela, a causa em português.
    debugPrint('❌ [WHATSAPP] seletor: ${e.code} ${e.message ?? ''}');
    final String causa;
    if (codigo.contains('already_active') || codigo.contains('multiple')) {
      causa = 'outro seletor ainda está aberto. Aguarde e tente de novo.';
    } else if (codigo.contains('camera') || codigo.contains('no_available')) {
      causa = 'o aparelho não liberou a câmera agora. Tente de novo.';
    } else {
      causa = 'o aparelho recusou o pedido. Tente de novo.';
    }
    _showSnack(
      camera
          ? 'Não foi possível abrir a câmera: $causa'
          : 'Não foi possível abrir o seletor: $causa',
      isError: true,
    );
  }

  /// Lê os arquivos escolhidos e acrescenta ao FIM da fila; o que foge da
  /// regra do canal vira UM aviso resumido (mesmas frases do web).
  Future<void> _acrescentar(List<_ArquivoEscolhido> escolhidos) async {
    if (escolhidos.isEmpty || !mounted) return;
    setState(() => _preparandoAnexos = true);
    final novos = <WhatsAppAnexo>[];
    for (final e in escolhidos) {
      final anexo = await WhatsAppAnexo.doArquivo(
        e.caminho,
        nome: e.nome,
        tamanho: e.tamanho,
      );
      if (anexo != null) novos.add(anexo);
    }
    if (!mounted) return;
    final regra = regraDoCanal(_usesUnofficial);
    final resultado = acrescentarAnexos(_anexos, novos, regra);
    setState(() {
      _preparandoAnexos = false;
      _anexos = resultado.fila;
    });
    final aviso = resumoDosRecusados(resultado.recusados, regra);
    final ilegiveis = escolhidos.length - novos.length;
    if (aviso != null) {
      _showSnack(aviso, isError: true);
    } else if (ilegiveis > 0) {
      _showSnack(
        ilegiveis == 1
            ? 'Não foi possível ler 1 arquivo escolhido.'
            : 'Não foi possível ler $ilegiveis arquivos escolhidos.',
        isError: true,
      );
    }
  }

  void _removerAnexo(String id) {
    setState(() => _anexos = _anexos.where((a) => a.id != id).toList());
  }

  // ─── Assumir conversa ────────────────────────────────────────────────────

  /// Pega para si a conversa da fila — paridade com "Assumir conversa" do
  /// web: usa a última mensagem da thread e relê em seguida.
  Future<void> _assumirConversa() async {
    if (_assumindo || _messages.isEmpty) return;
    setState(() => _assumindo = true);
    final res =
        await WhatsAppService.instance.claimConversation(_messages.last.id);
    if (!mounted) return;
    setState(() => _assumindo = false);
    if (res.success) {
      _showSnack('Conversa assumida. Agora ela é sua.');
      await _syncLatest();
    } else {
      _showSnack(res.message ?? 'Erro ao assumir conversa.', isError: true);
    }
  }

  Future<void> _openTemplateSheet() async {
    final sent = await WhatsAppSendTemplateSheet.show(
      context,
      phoneNumber: widget.phoneNumber,
      clientId: _clientId,
      // Variáveis já preenchidas, como no web: o nome da conversa (ou o do
      // cadastro, se o apelido não servir) e o imóvel do card mais recente
      // da conversa, que o sheet busca em paralelo.
      nomeDoContato: _displayName,
      nomeDoCadastro: widget.conversation?.clientName ??
          _messages.map((m) => m.clientName).whereType<String>().lastOrNull,
      kanbanTaskId:
          _messages.map((m) => m.kanbanTaskId).whereType<String>().lastOrNull ??
              widget.conversation?.kanbanTaskId,
    );
    if (!mounted) return;
    if (sent) {
      _showSnack('Template enviado.');
      await _syncLatest();
      _scrollToBottom();
    }
  }

  Future<void> _finalizeConversation() async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: ThemeHelpers.cardBackgroundColor(ctx),
        title: Text(
          'Finalizar conversa?',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: ThemeHelpers.textColor(ctx),
          ),
        ),
        content: Text(
          'A conversa sai das abas de atendimento. Se o contato mandar uma '
          'nova mensagem, ela reabre automaticamente.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: ThemeHelpers.textSecondaryColor(ctx),
            height: 1.4,
          ),
        ),
        actions: [
          // Cancelar NEUTRO (o tema pinta TextButton de vermelho).
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: ThemeHelpers.textSecondaryColor(ctx),
            ),
            child: const Text('Cancelar'),
          ),
          // Concluir o atendimento não é destrutivo (reabre sozinha): verde
          // de confirmação, não o vermelho da marca.
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).brightness == Brightness.dark
                  ? AppColors.status.greenDarkMode
                  : AppColors.status.green,
              foregroundColor: ThemeHelpers.onPrimaryColor(ctx),
            ),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final res = await WhatsAppService.instance
        .finalizeConversation(widget.phoneNumber);
    if (!mounted) return;
    if (res.success) {
      _showSnack('Conversa finalizada.');
      Navigator.of(context).maybePop(true);
    } else {
      _showSnack(res.message ?? 'Erro ao finalizar conversa', isError: true);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    // Seletores e envios terminam depois de awaits: a tela pode ter fechado.
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        // Tinta pelo tema: no escuro o verde/vermelho são claros e o branco
        // não lia.
        content: Text(
          message,
          style: TextStyle(color: ThemeHelpers.onPrimaryColor(context)),
        ),
        backgroundColor: isError
            ? (isDark ? AppColors.status.errorDarkMode : AppColors.status.error)
            : (isDark
                ? AppColors.status.greenDarkMode
                : AppColors.status.green),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _scrollToBottom() {
    // Lista reversa: o "fundo" (mensagem mais recente) é o offset 0.
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Altura livre medida AQUI, acima do Scaffold (no corpo o Scaffold tira
    // o teclado do MediaQuery). Em paisagem ou com teclado aberto o
    // cabeçalho encolhe — ou some e o nome do contato sobe para o título —
    // e a caixa cresce menos: a conversa continua aparecendo.
    final mq = MediaQuery.of(context);
    final livre = mq.size.height - mq.viewInsets.bottom - mq.viewPadding.top;
    final baixa = livre < 420;
    final minima = livre < 300;
    return AppScaffold(
      title: minima ? _displayName : 'WhatsApp',
      showBottomNavigation: false,
      body: Column(
        children: [
          // Mesmo lugar na árvore nos dois casos: a caixa de texto não perde
          // o foco quando o cabeçalho some.
          minima
              ? const SizedBox.shrink()
              : _buildContactHeader(context, compacto: baixa),
          Expanded(child: _buildThread(context)),
          _buildComposerArea(context, baixa: baixa, minima: minima),
        ],
      ),
    );
  }

  // ─── Cabeçalho do contato (compacto, estilo iOS) ─────────────────────────

  /// Quem é, por onde fala e com quem está: nome, telefone · canal e o
  /// responsável ("Com você", "Com Ana Souza", "Sem responsável"), com
  /// "Assumir" à vista quando a conversa não é sua. [compacto] (paisagem ou
  /// teclado em tela baixa): avatar menor e sem a linha do responsável.
  Widget _buildContactHeader(BuildContext context, {bool compacto = false}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);

    final last = _messages.isNotEmpty ? _messages.last : null;
    final avatarUrl = widget.conversation?.lastMessage?.contactAvatarUrl ??
        last?.contactAvatarUrl;

    // Origem do canal — resolve pela última mensagem; cai no status global.
    var source = last?.integrationSource ?? WhatsAppIntegrationSource.unknown;
    if (source == WhatsAppIntegrationSource.unknown &&
        _integrationStatus != null &&
        _integrationStatus!.hasAnyChannel) {
      source = _integrationStatus!.chatSource;
    }

    // Responsável: o mesmo que decide "Assumir conversa" (a mensagem mais
    // recente com responsável); o nome vem dessa mesma mensagem.
    final responsavelId = _responsavelAtualId;
    var responsavelNome = '';
    if (responsavelId.isNotEmpty) {
      for (var i = _messages.length - 1; i >= 0; i--) {
        final m = _messages[i];
        if ((m.assignedToId ?? '').trim() != responsavelId) continue;
        final nome = (m.assignedToName ?? '').trim();
        if (nome.isNotEmpty) {
          responsavelNome = nome;
          break;
        }
      }
    }
    if (responsavelNome.isEmpty) {
      responsavelNome = (last?.assignedToName ??
              widget.conversation?.lastMessage?.assignedToName ??
              '')
          .trim();
    }
    final comVoce = responsavelId.isNotEmpty &&
        _currentUserId != null &&
        responsavelId == _currentUserId;
    final semResponsavel = responsavelId.isEmpty && responsavelNome.isEmpty;
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    // Tinta de texto legível no claro: o token puro (verde 3,0:1, âmbar
    // 3,2:1 no branco) puxado para a cor do texto, sem hex novo.
    final greenInk = isDark
        ? green
        : Color.lerp(
            AppColors.message.successText,
            AppColors.text.text,
            0.35,
          )!;
    final amberInk = isDark
        ? AppColors.message.warningTextDarkMode
        : Color.lerp(
            AppColors.message.warningText,
            AppColors.text.text,
            0.35,
          )!;
    final String responsavelTexto;
    final IconData responsavelIcone;
    final Color responsavelCor;
    if (comVoce) {
      responsavelTexto = 'Com você';
      responsavelIcone = LucideIcons.userCheck;
      responsavelCor = greenInk;
    } else if (semResponsavel) {
      responsavelTexto = 'Sem responsável';
      responsavelIcone = LucideIcons.inbox;
      responsavelCor = amberInk;
    } else {
      responsavelTexto = responsavelNome.isNotEmpty
          ? 'Com $responsavelNome'
          : 'Com outro atendente';
      responsavelIcone = LucideIcons.userRound;
      responsavelCor = secondary;
    }
    // Sem mensagens ainda não há de quem seja a conversa.
    final mostrarResponsavel = !compacto && _messages.isNotEmpty;

    // Linha de status: telefone · canal.
    final statusParts = <String>[formatWhatsAppPhone(widget.phoneNumber)];
    if (source != WhatsAppIntegrationSource.unknown) {
      statusParts.add(source.label);
    }

    return Container(
      padding: EdgeInsets.fromLTRB(16, compacto ? 5 : 9, 8, compacto ? 5 : 9),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: Row(
        children: [
          WhatsAppAvatar(
            name: _displayName,
            imageUrl: avatarUrl,
            size: compacto ? 32 : 42,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _displayName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                    letterSpacing: -0.3,
                    fontSize: 16,
                    height: 1.15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (source != WhatsAppIntegrationSource.unknown) ...[
                      Icon(
                        whatsAppSourceIcon(source),
                        size: 11,
                        color: secondary.withValues(alpha: 0.85),
                      ),
                      const SizedBox(width: 3.5),
                    ],
                    Flexible(
                      child: Text(
                        statusParts.join(' · '),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: secondary,
                          fontWeight: FontWeight.w500,
                          fontSize: 11.5,
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (mostrarResponsavel) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(responsavelIcone, size: 12, color: responsavelCor),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          responsavelTexto,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: comVoce || semResponsavel
                                ? responsavelCor
                                : secondary,
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_podeAssumir) ...[
                        const SizedBox(width: 8),
                        _buildBotaoAssumir(context, green, greenInk),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(LucideIcons.ellipsisVertical,
                size: 19, color: secondary),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            color: ThemeHelpers.cardBackgroundColor(context),
            onSelected: (value) {
              switch (value) {
                case 'claim':
                  _assumirConversa();
                  break;
                case 'template':
                  _openTemplateSheet();
                  break;
                case 'finalize':
                  _finalizeConversation();
                  break;
                case 'refresh':
                  _loadMessages();
                  break;
              }
            },
            itemBuilder: (ctx) => [
              // Fila manual: a conversa fica em Aguardando até alguém pegar
              // (29/09/2026). Some para quem já é o responsável.
              if (_podeAssumir)
                PopupMenuItem(
                  value: 'claim',
                  enabled: !_assumindo,
                  child: _menuRow(
                      ctx, LucideIcons.userPlus, 'Assumir conversa'),
                ),
              if (_canSend)
                PopupMenuItem(
                  value: 'template',
                  child: _menuRow(ctx, LucideIcons.badgeCheck,
                      'Enviar template'),
                ),
              PopupMenuItem(
                value: 'refresh',
                child: _menuRow(ctx, LucideIcons.refreshCw, 'Atualizar'),
              ),
              PopupMenuItem(
                value: 'finalize',
                child: _menuRow(
                    ctx, LucideIcons.circleCheckBig, 'Finalizar conversa'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// "Assumir" à vista no cabeçalho (mesma ação do menu ⋮): pílula verde
  /// tonal, rótulo que encolhe em vez de estourar.
  Widget _buildBotaoAssumir(BuildContext context, Color green, Color ink) {
    return TextButton(
      onPressed: _assumindo ? null : _assumirConversa,
      style: TextButton.styleFrom(
        foregroundColor: ink,
        backgroundColor: green.withValues(alpha: 0.14),
        disabledForegroundColor: ink.withValues(alpha: 0.5),
        minimumSize: const Size(0, 28),
        padding: const EdgeInsets.symmetric(horizontal: 11),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        shape: const StadiumBorder(),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          _assumindo ? 'Assumindo…' : 'Assumir',
          maxLines: 1,
          softWrap: false,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _menuRow(BuildContext context, IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 16, color: ThemeHelpers.textSecondaryColor(context)),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
        ),
      ],
    );
  }

  // ─── Thread ──────────────────────────────────────────────────────────────

  /// Chave de "remetente" para agrupamento de bolhas sequenciais — contato,
  /// IA ou usuário do sistema.
  static String _authorKey(WhatsAppMessage m) {
    if (!m.isOutbound) return 'in';
    if (m.isAiResponse) return 'out-ai';
    return 'out-${m.userId ?? m.userName ?? ''}';
  }

  Widget _buildThread(BuildContext context) {
    if (_loading && _messages.isEmpty) return _buildSkeleton(context);
    if (_error != null && _messages.isEmpty) return _buildError(context);
    if (_messages.isEmpty) return _buildEmpty(context);

    // Monta em ordem cronológica com separadores de dia e agrupamento de
    // mensagens sequenciais do mesmo remetente; inverte no final — com
    // `reverse: true` a mensagem mais recente fica colada no composer.
    final children = <Widget>[];
    final nomeDoContato = _displayName;
    DateTime? currentDay;
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      final created = m.createdAt?.toLocal();
      var dayChanged = false;
      if (created != null) {
        final day = DateTime(created.year, created.month, created.day);
        if (currentDay == null || day != currentDay) {
          currentDay = day;
          dayChanged = true;
          children.add(WhatsAppDaySeparator(date: day));
        }
      }

      final prev = i > 0 ? _messages[i - 1] : null;
      final isFirst =
          dayChanged || prev == null || _authorKey(prev) != _authorKey(m);

      // Última do grupo: a próxima não existe, muda de remetente ou de dia.
      var isLast = true;
      if (i < _messages.length - 1) {
        final next = _messages[i + 1];
        if (_authorKey(next) == _authorKey(m)) {
          final nc = next.createdAt?.toLocal();
          final sameDay = nc != null &&
              created != null &&
              nc.year == created.year &&
              nc.month == created.month &&
              nc.day == created.day;
          isLast = !(sameDay || (nc == null && created == null));
        }
      }

      children.add(WhatsAppMessageBubble(
        // Chave pela mensagem: quando chega uma nova, as bolhas mudam de
        // posição e a mídia de cada uma (imagem carregada, renovação em
        // curso) precisa seguir a SUA mensagem.
        key: ValueKey('msg-${m.id.isEmpty ? 'pos-$i' : m.id}'),
        message: m,
        isFirstInGroup: isFirst,
        isLastInGroup: isLast,
        onRenovarMidia: _renovarMidia,
        contactLabel: nomeDoContato,
        citada: acharCitada(_messages, m.replyToMessageId),
      ));
    }

    if (_hasOlder || _loadingOlder) {
      children.insert(
        0,
        Padding(
          padding: const EdgeInsets.only(bottom: 10, top: 2),
          child: Center(
            child: _loadingOlder
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                  )
                : OutlinedButton.icon(
                    onPressed: _loadOlder,
                    icon: const Icon(LucideIcons.history, size: 14),
                    label: const Text('Carregar mensagens anteriores'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          ThemeHelpers.textSecondaryColor(context),
                      side: BorderSide(
                          color: ThemeHelpers.borderColor(context)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
          ),
        ),
      );
    }

    return ListView(
      controller: _scrollController,
      reverse: true,
      // Como no iPhone: arrastar a conversa recolhe o teclado.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      children: children.reversed.toList(),
    );
  }

  Widget _buildSkeleton(BuildContext context) {
    // Fiel à thread nova: bolhas agrupadas (margem menor dentro do grupo).
    Widget bubble({
      required bool own,
      required double width,
      bool grouped = false,
      double height = 46,
    }) {
      return Align(
        alignment: own ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.only(bottom: grouped ? 2 : 10),
          child: SkeletonBox(width: width, height: height, borderRadius: 18),
        ),
      );
    }

    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      children: [
        // Cápsula do dia, como na thread.
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Center(
            child: SkeletonBox(width: 64, height: 20, borderRadius: 999),
          ),
        ),
        bubble(own: false, width: 210, height: 56),
        bubble(own: true, width: 180, grouped: true),
        bubble(own: true, width: 140),
        bubble(own: false, width: 228, grouped: true, height: 64),
        bubble(own: false, width: 150),
        bubble(own: true, width: 220, height: 56),
        bubble(own: false, width: 190),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final String dica;
    if (!_canSend) {
      dica = 'As mensagens com este contato aparecem aqui. Enviar mensagens '
          'depende da permissão de envio do WhatsApp.';
    } else if (_canSendFreeText) {
      dica = 'Escreva no campo abaixo para começar. As respostas do contato '
          'aparecem aqui.';
    } else {
      dica = 'Pelo número oficial, a conversa começa com um template '
          'aprovado. Depois que o contato responder, o campo de mensagem '
          'libera.';
    }
    // Rola em tela baixa (paisagem com teclado) em vez de estourar.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: green.withValues(alpha: isDark ? 0.16 : 0.12),
                      ),
                      child: Icon(
                        LucideIcons.messagesSquare,
                        color: green,
                        size: 26,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Nenhuma mensagem ainda',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dica,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return AppErrorState.fromApi(
      message: _error ?? 'Erro ao carregar mensagens',
      statusCode: _errorStatus,
      onRetry: _loadMessages,
      dense: false,
    );
  }

  // ─── Composer ────────────────────────────────────────────────────────────

  Widget _buildComposerArea(
    BuildContext context, {
    bool baixa = false,
    bool minima = false,
  }) {
    // Sem permissão: a caixa não some calada — diz por que não dá.
    if (!_canSend) return _buildSemPermissaoDeEnvio(context);
    // Aguardando primeiro load para decidir a UI do composer.
    if (_loading && _messages.isEmpty && _integrationStatus == null) {
      return const SizedBox.shrink();
    }
    if (!_canSendFreeText) {
      return _buildWindowClosedBanner(context, compacto: baixa);
    }
    // Teto de linhas pela altura livre: 6 em pé, menos com teclado em tela
    // baixa (o texto rola por dentro do campo).
    return _buildComposer(context, maxLinhas: minima ? 2 : (baixa ? 4 : 6));
  }

  /// Faixa no lugar da caixa para quem não tem whatsapp:send.
  Widget _buildSemPermissaoDeEnvio(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.backgroundColor(context),
        border: Border(
          top: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
          child: Row(
            children: [
              Icon(LucideIcons.lock, size: 15, color: secondary),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Você pode ler esta conversa, mas não tem permissão para '
                  'enviar mensagens. Quem libera é o administrador.',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondary,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Faixa âmbar quando a janela de 24h da API oficial está fechada, com a
  /// causa certa (contato ainda não escreveu / janela venceu / o número que
  /// envia está fora da janela) e "Enviar template" verde à vista.
  /// [compacto]: em paisagem some a explicação longa.
  Widget _buildWindowClosedBanner(
    BuildContext context, {
    bool compacto = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    // Âmbar como TEXTO: no claro o token some no branco — puxado para a
    // tinta do texto (sem hex novo).
    final amberInk = isDark
        ? AppColors.message.warningTextDarkMode
        : Color.lerp(
            AppColors.message.warningText,
            AppColors.text.text,
            0.35,
          )!;
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;

    final ultima = _lastInbound?.createdAt?.toLocal();
    final String titulo;
    final String explicacao;
    if (_lastInbound == null) {
      titulo = 'O contato ainda não escreveu';
      explicacao = 'Pelo número oficial, a conversa só começa com um '
          'template aprovado. Quando o contato responder, o campo de '
          'mensagem volta.';
    } else if (_janelaFechadaNoEnvio) {
      titulo = 'Janela de 24 horas fechada no número que envia';
      explicacao = 'O contato escreveu para outro número da empresa. Para '
          'falar por este, envie um template aprovado.';
    } else {
      titulo = 'Janela de 24 horas encerrada';
      explicacao = ultima == null
          ? 'Pelo número oficial, depois de 24 horas sem resposta do '
              'contato só dá para retomar com um template aprovado.'
          : 'A última mensagem do contato foi em ${_dataCurta(ultima)}. '
              'Pelo número oficial, depois de 24 horas só dá para retomar '
              'com um template aprovado.';
    }

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.backgroundColor(context),
        border: Border(
          top: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: compacto ? 8 : 12,
      ),
      child: SafeArea(
        top: false,
        child: Container(
          padding: EdgeInsets.all(compacto ? 10 : 13),
          decoration: BoxDecoration(
            color: amber.withValues(alpha: isDark ? 0.13 : 0.09),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: amber.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(LucideIcons.clock3, size: 15, color: amberInk),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      titulo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: ThemeHelpers.textColor(context),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                ],
              ),
              if (!compacto) ...[
                const SizedBox(height: 4),
                Text(
                  explicacao,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    height: 1.35,
                  ),
                ),
              ],
              SizedBox(height: compacto ? 8 : 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _openTemplateSheet,
                  icon: const Icon(LucideIcons.badgeCheck, size: 16),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Enviar template',
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: green,
                    foregroundColor: ThemeHelpers.onPrimaryColor(context),
                    padding: EdgeInsets.symmetric(vertical: compacto ? 9 : 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "28/09 às 14:32" (com o ano quando não é o corrente).
  static String _dataCurta(DateTime d) {
    String dois(int n) => n.toString().padLeft(2, '0');
    final ano = d.year == DateTime.now().year ? '' : '/${d.year}';
    return '${dois(d.day)}/${dois(d.month)}$ano às '
        '${dois(d.hour)}:${dois(d.minute)}';
  }

  /// Composer estilo iOS: campo arredondado em superfície clara + botão de
  /// enviar circular VERDE (identidade WhatsApp), seta pra cima. Acima dele,
  /// a bandeja de anexos e, durante o lote, "Enviando 2 de 5" (29/09/2026).
  /// O clipe fica dentro do campo, como no WhatsApp, para não estreitar a
  /// caixa em telas pequenas.
  Widget _buildComposer(BuildContext context, {int maxLinhas = 6}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final fieldFill = ThemeHelpers.cardBackgroundColor(context);
    final hairline = ThemeHelpers.borderLightColor(context);
    final hasText = _composerController.text.trim().isNotEmpty;
    final temConteudo = hasText || _anexos.isNotEmpty;
    final progresso = _progressoDoLote;

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.backgroundColor(context),
        border: Border(top: BorderSide(color: hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (progresso != null)
              WhatsAppProgressoDoLote(
                atual: progresso.atual,
                total: progresso.total,
              ),
            WhatsAppBandejaDeAnexos(
              anexos: _anexos,
              onRemover: _removerAnexo,
              onAdicionar: _abrirMenuDeAnexo,
              desabilitado: _sending,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: _buildComposerRow(
                context,
                isDark: isDark,
                green: green,
                secondary: secondary,
                fieldFill: fieldFill,
                hairline: hairline,
                temConteudo: temConteudo,
                maxLinhas: maxLinhas,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Botão de clipe dentro do campo (abre câmera, galeria ou arquivo).
  Widget _buildBotaoAnexar(BuildContext context, Color secondary) {
    final ocupado = _preparandoAnexos;
    return Semantics(
      button: true,
      label: _usesUnofficial ? 'Anexar arquivo' : 'Anexar foto, documento ou áudio',
      child: InkResponse(
        radius: 20,
        onTap: ocupado || _sending ? null : _abrirMenuDeAnexo,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(
            child: ocupado
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: secondary,
                    ),
                  )
                : Icon(
                    LucideIcons.paperclip,
                    size: 19,
                    color: _sending ? secondary.withValues(alpha: 0.4) : secondary,
                  ),
          ),
        ),
      ),
    );
  }

  /// Linha do composer (29/09/2026): atalho de template (canal oficial),
  /// campo com o clipe no fim e o botão de enviar. O mesmo botão manda o
  /// texto E a fila de anexos (`_enviar`), então acende com qualquer um dos
  /// dois — antes só com texto, e o anexo sozinho não tinha como sair.
  Widget _buildComposerRow(
    BuildContext context, {
    required bool isDark,
    required Color green,
    required Color secondary,
    required Color fieldFill,
    required Color hairline,
    required bool temConteudo,
    int maxLinhas = 6,
  }) {
    // Enquanto o seletor ainda lê os arquivos, `_enviar` ignora o toque: o
    // botão fica apagado para não parecer que enviou.
    final podeEnviar = temConteudo && !_sending && !_preparandoAnexos;
    final quantosAnexos = _anexos.length;
    // Tinta sobre o verde: branca no claro, escura no escuro (o verde do
    // modo escuro é claro demais para branco).
    final sobreVerde = ThemeHelpers.onPrimaryColor(context);

    // Nota de voz: sem texto e sem anexo, o botão verde vira microfone
    // (tocar ou segurar); gravando ou na prévia, o campo dá lugar ao painel
    // de voz e o botão segue sendo o mesmo widget (o gesto não se perde).
    final vozAtiva = !_gravador.ocioso;
    final mostrarVoz = vozAtiva || !temConteudo;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Atalho de template (sempre disponível no canal oficial).
        if (!_usesUnofficial && !vozAtiva)
          Padding(
            padding: const EdgeInsets.only(right: 7, bottom: 3),
            child: Tooltip(
              message: 'Enviar template',
              child: Semantics(
                button: true,
                label: 'Enviar template',
                child: InkResponse(
                  radius: 21,
                  onTap: _openTemplateSheet,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: fieldFill,
                      shape: BoxShape.circle,
                      border: Border.all(color: hairline),
                    ),
                    child: Icon(
                      LucideIcons.badgeCheck,
                      size: 18,
                      color: secondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        Expanded(
          child: vozAtiva
              ? WhatsAppPainelDeVoz(gravador: _gravador)
              : Container(
            constraints: const BoxConstraints(minHeight: 44),
            // Direita curta: o clipe (36) já traz o próprio respiro.
            padding: const EdgeInsets.only(left: 14, right: 4),
            decoration: BoxDecoration(
              color: fieldFill,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.black.withValues(alpha: 0.08),
                width: 0.8,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _composerController,
                    focusNode: _composerFocus,
                    minLines: 1,
                    maxLines: maxLinhas,
                    textCapitalization: TextCapitalization.sentences,
                    cursorColor: green,
                    style: TextStyle(
                      color: ThemeHelpers.textColor(context),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                      letterSpacing: -0.1,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Mensagem',
                      hintStyle: TextStyle(
                        color: secondary.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w400,
                        fontSize: 15,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 11.5),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                // Clipe dentro do campo, no rodapé: com o texto crescendo
                // ele fica na última linha, como no WhatsApp.
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _buildBotaoAnexar(context, secondary),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 7),
        if (mostrarVoz)
          Padding(
            padding: const EdgeInsets.only(bottom: 1),
            child: WhatsAppBotaoDeVoz(
              gravador: _gravador,
              habilitado: !_preparandoAnexos,
              enviando: _sending,
              onComecar: _comecarGravacao,
              onEnviar: _enviarNotaDeVoz,
              onCurtoDemais: () => _showSnack(
                'Segure o microfone para gravar, ou toque uma vez para gravar '
                'e de novo para parar.',
              ),
            ),
          )
        else
        Padding(
          padding: const EdgeInsets.only(bottom: 1),
          child: Semantics(
            button: true,
            enabled: podeEnviar,
            // Mesmo rótulo da dica do botão no web.
            label: quantosAnexos > 1
                ? 'Enviar $quantosAnexos anexos'
                : 'Enviar mensagem',
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: 42,
              height: 42,
              // Chapado, sem brilho verde difuso (sombra colorida vira mancha
              // no claro).
              decoration: BoxDecoration(
                color: podeEnviar
                    ? green
                    : green.withValues(alpha: isDark ? 0.35 : 0.4),
                shape: BoxShape.circle,
              ),
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: podeEnviar ? _enviar : null,
                  child: Center(
                    child: _sending
                        ? SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: sobreVerde,
                            ),
                          )
                        : Icon(
                            LucideIcons.arrowUp,
                            size: 21,
                            color: sobreVerde,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

extension<T> on Iterable<T> {
  T? get lastOrNull => isEmpty ? null : last;
}

/// Arquivo vindo de um seletor (câmera, galeria ou arquivos), antes de virar
/// anexo: o seletor já informa nome e, às vezes, tamanho.
class _ArquivoEscolhido {
  final String caminho;
  final String? nome;
  final int? tamanho;

  const _ArquivoEscolhido(this.caminho, [this.nome, this.tamanho]);
}
