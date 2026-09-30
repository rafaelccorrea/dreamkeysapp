import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Tocador ÚNICO dos áudios do WhatsApp no app (bolhas e prévia da nota de
/// voz), como no WhatsApp: dar play num áudio pausa o anterior.
///
/// Cada tela ouve este objeto e se desenha pela [atualId]: só o áudio da vez
/// mostra posição, duração e velocidade. A posição avisa no máximo a cada
/// 200 ms para não redesenhar a conversa inteira a cada quadro.
class WhatsAppTocadorDeAudio extends ChangeNotifier {
  WhatsAppTocadorDeAudio._();

  static final WhatsAppTocadorDeAudio instance = WhatsAppTocadorDeAudio._();

  /// Velocidades do botão "1x · 1,5x · 2x" (mesma ordem do WhatsApp).
  static const List<double> velocidades = [1.0, 1.5, 2.0];

  AudioPlayer? _player;
  final List<StreamSubscription<dynamic>> _escutas = [];

  String? _atualId;
  bool _carregando = false;
  bool _tocando = false;
  Duration _posicao = Duration.zero;
  Duration? _duracao;
  double _velocidade = 1.0;
  DateTime _ultimoAvisoDePosicao = DateTime.fromMillisecondsSinceEpoch(0);

  String? get atualId => _atualId;
  bool get carregando => _carregando;
  bool get tocando => _tocando;
  Duration get posicao => _posicao;
  Duration? get duracao => _duracao;
  double get velocidade => _velocidade;

  bool ehAtual(String id) => _atualId == id;

  /// 0..1 do áudio [id]; 0 quando não é o da vez ou sem duração.
  double progressoDe(String id) {
    final d = _duracao;
    if (_atualId != id || d == null || d.inMilliseconds <= 0) return 0;
    return (_posicao.inMilliseconds / d.inMilliseconds).clamp(0.0, 1.0);
  }

  AudioPlayer _garantirPlayer() {
    final existente = _player;
    if (existente != null) return existente;
    final p = AudioPlayer();
    _escutas.add(p.playerStateStream.listen((estado) {
      final concluiu = estado.processingState == ProcessingState.completed;
      if (concluiu) {
        // Fim do áudio: volta ao começo, pausado (como o WhatsApp).
        _tocando = false;
        _posicao = Duration.zero;
        unawaited(p.pause());
        unawaited(p.seek(Duration.zero));
      } else {
        _tocando = estado.playing;
      }
      _carregando = estado.processingState == ProcessingState.loading ||
          estado.processingState == ProcessingState.buffering;
      notifyListeners();
    }));
    _escutas.add(p.durationStream.listen((d) {
      _duracao = d;
      notifyListeners();
    }));
    _escutas.add(p.positionStream.listen((pos) {
      _posicao = pos;
      final agora = DateTime.now();
      if (agora.difference(_ultimoAvisoDePosicao).inMilliseconds >= 200) {
        _ultimoAvisoDePosicao = agora;
        notifyListeners();
      }
    }));
    _player = p;
    return p;
  }

  /// Toca/pausa o áudio [id]. Se for outro áudio, troca a fonte. [fonte]
  /// devolve a URL (renovada quando venceu) ou o caminho local; `null` = sem
  /// mídia. Devolve `false` quando este aparelho não conseguiu carregar o
  /// arquivo (ex.: Ogg/Opus no iPhone) — quem chamou decide o plano B.
  Future<bool> alternar({
    required String id,
    required Future<String?> Function() fonte,
    bool arquivoLocal = false,
  }) async {
    final p = _garantirPlayer();
    if (_atualId == id && _duracao != null) {
      if (_tocando) {
        await p.pause();
      } else {
        unawaited(p.play());
      }
      return true;
    }

    _atualId = id;
    _carregando = true;
    _tocando = false;
    _posicao = Duration.zero;
    _duracao = null;
    notifyListeners();
    try {
      await p.stop();
      final caminho = await fonte();
      if (caminho == null || caminho.trim().isEmpty) {
        throw StateError('sem mídia');
      }
      if (_atualId != id) return true; // outro play chegou antes
      if (arquivoLocal) {
        await p.setFilePath(caminho);
      } else {
        await p.setUrl(caminho);
      }
      await p.setSpeed(_velocidade);
      unawaited(p.play());
      return true;
    } catch (e) {
      debugPrint('[WHATSAPP] tocador: não carregou $id: $e');
      if (_atualId == id) {
        _atualId = null;
        _carregando = false;
        _tocando = false;
        _duracao = null;
        notifyListeners();
      }
      return false;
    }
  }

  Future<void> buscar(String id, double fracao) async {
    final p = _player;
    final d = _duracao;
    if (p == null || _atualId != id || d == null) return;
    final alvo = Duration(
      milliseconds: (d.inMilliseconds * fracao.clamp(0.0, 1.0)).round(),
    );
    _posicao = alvo;
    notifyListeners();
    await p.seek(alvo);
  }

  /// 1x → 1,5x → 2x → 1x. Vale para o próximo áudio também.
  Future<void> proximaVelocidade() async {
    final i = velocidades.indexOf(_velocidade);
    _velocidade = velocidades[(i + 1) % velocidades.length];
    notifyListeners();
    await _player?.setSpeed(_velocidade);
  }

  /// Para e solta o áudio da vez (sair da conversa, descartar a prévia).
  Future<void> parar({String? seFor}) async {
    if (seFor != null && _atualId != seFor) return;
    _atualId = null;
    _tocando = false;
    _carregando = false;
    _posicao = Duration.zero;
    _duracao = null;
    notifyListeners();
    await _player?.stop();
  }
}

/// "0:07", "1:05", "12:40" — o tempo como o WhatsApp mostra.
String formatarTempoDeAudio(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final min = total ~/ 60;
  final seg = (total % 60).toString().padLeft(2, '0');
  return '$min:$seg';
}

/// "1x", "1,5x", "2x".
String rotuloDaVelocidade(double v) =>
    v == v.roundToDouble() ? '${v.toInt()}x' : '${v.toString().replaceAll('.', ',')}x';
