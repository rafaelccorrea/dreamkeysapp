import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import 'whatsapp_tocador_de_audio.dart';

/// Nota de voz no compositor (30/09/2026, pedido do Edson).
///
/// Dois jeitos de gravar, como no WhatsApp: SEGURAR o microfone (soltar
/// para, deslizar para a esquerda cancela) ou TOCAR (grava até tocar em
/// parar). Nos dois, a nota vai para a PRÉVIA — dá para ouvir, descartar ou
/// enviar; nada sai sem o toque em enviar.
///
/// Formato: o WhatsApp só mostra "nota de voz" para Ogg/Opus. No Android 10+
/// o `record` grava Opus dentro de Ogg (MediaMuxer OGG); no Android antigo e
/// no iPhone grava AAC em .m4a, que o back aceita (audio/mp4) e chega ao
/// cliente como áudio comum. Conferido no `record_ios` 2.1.1 (30/09/2026): o
/// iPhone grava com AVAudioRecorder, que escolhe o contêiner pela extensão e
/// não escreve Ogg — Opus ali só sairia em CAF, que a Meta não aceita. O .m4a
/// do AVAudioRecorder é MP4 comum (moov no fim), NÃO fragmentado: o fMP4 que
/// a Meta recusa com 131053 é o do MediaRecorder do Chrome, não este.
enum WhatsAppEstadoDaGravacao { ocioso, gravando, previa }

/// Nota pronta para enviar.
class WhatsAppNotaDeVoz {
  final String caminho;
  final String nome;
  final Duration duracao;

  const WhatsAppNotaDeVoz({
    required this.caminho,
    required this.nome,
    required this.duracao,
  });
}

class WhatsAppGravadorDeVoz extends ChangeNotifier {
  /// Teto de uma nota (a Meta aceita áudio até 16 MB; 15 min de Opus a
  /// 32 kbps dá ~3,6 MB, de AAC a 64 kbps ~7,2 MB).
  static const Duration limite = Duration(minutes: 15);

  /// Menos que isso é toque acidental: descarta e ensina a segurar.
  static const Duration minimo = Duration(milliseconds: 800);

  /// Arrasto para a esquerda que cancela ao segurar.
  static const double arrastoQueCancela = 110;

  final AudioRecorder _recorder = AudioRecorder();
  final Stopwatch _cronometro = Stopwatch();
  Timer? _tique;

  WhatsAppEstadoDaGravacao _estado = WhatsAppEstadoDaGravacao.ocioso;
  bool _segurando = false;
  double _arrasto = 0;
  Duration _duracao = Duration.zero;
  String? _caminho;
  String _extensao = 'm4a';
  bool _iniciando = false;
  bool _descartado = false;

  WhatsAppEstadoDaGravacao get estado => _estado;
  bool get segurando => _segurando;
  double get arrasto => _arrasto;
  Duration get duracao => _duracao;
  bool get ocioso => _estado == WhatsAppEstadoDaGravacao.ocioso;

  /// Id da prévia no [WhatsAppTocadorDeAudio].
  String get idDaPrevia => 'previa:${_caminho ?? ''}';

  /// Arquivo da gravação (prévia).
  String? get caminho => _caminho;

  /// Começa a gravar. Devolve a frase de erro (sem permissão, microfone
  /// ocupado) ou `null` quando começou.
  Future<String?> iniciar({required bool segurando}) async {
    if (!ocioso || _iniciando) return null;
    _iniciando = true;
    _descartado = false;
    try {
      if (!await _recorder.hasPermission()) {
        return 'Libere o microfone para o Intellisys nas configurações do '
            'aparelho para gravar notas de voz.';
      }
      // Se a pessoa soltou antes da permissão responder, não grava.
      if (segurando && _descartado) return null;
      await WhatsAppTocadorDeAudio.instance.parar();
      final opus = Platform.isAndroid &&
          await _recorder.isEncoderSupported(AudioEncoder.opus);
      _extensao = opus ? 'ogg' : 'm4a';
      final pasta = await getTemporaryDirectory();
      final caminho =
          '${pasta.path}/nota-de-voz-${DateTime.now().millisecondsSinceEpoch}'
          '.$_extensao';
      await _recorder.start(
        RecordConfig(
          encoder: opus ? AudioEncoder.opus : AudioEncoder.aacLc,
          sampleRate: opus ? 48000 : 44100,
          bitRate: opus ? 32000 : 64000,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
        ),
        path: caminho,
      );
      _caminho = caminho;
      _segurando = segurando;
      _arrasto = 0;
      _duracao = Duration.zero;
      _estado = WhatsAppEstadoDaGravacao.gravando;
      _cronometro
        ..reset()
        ..start();
      _tique?.cancel();
      _tique = Timer.periodic(const Duration(milliseconds: 200), (_) {
        _duracao = _cronometro.elapsed;
        if (_duracao >= limite) {
          unawaited(parar());
        } else {
          notifyListeners();
        }
      });
      unawaited(HapticFeedback.mediumImpact());
      notifyListeners();
      return null;
    } catch (e) {
      debugPrint('[WHATSAPP] gravador: não começou: $e');
      await _limpar(apagarArquivo: true);
      return 'Não foi possível usar o microfone agora. Feche outros apps que '
          'estejam gravando e tente de novo.';
    } finally {
      _iniciando = false;
    }
  }

  /// Para e vai para a prévia. Gravação curta demais é descartada e devolve
  /// `false` (a tela ensina "segure para gravar").
  Future<bool> parar() async {
    if (_estado != WhatsAppEstadoDaGravacao.gravando) {
      // Soltou antes de a gravação começar de fato.
      _descartado = true;
      return true;
    }
    _tique?.cancel();
    _cronometro.stop();
    _duracao = _cronometro.elapsed;
    String? caminho;
    try {
      caminho = await _recorder.stop();
    } catch (e) {
      debugPrint('[WHATSAPP] gravador: stop falhou: $e');
    }
    _caminho = caminho ?? _caminho;
    if (_duracao < minimo || _caminho == null) {
      await _limpar(apagarArquivo: true);
      return false;
    }
    _segurando = false;
    _arrasto = 0;
    _estado = WhatsAppEstadoDaGravacao.previa;
    unawaited(HapticFeedback.lightImpact());
    notifyListeners();
    return true;
  }

  /// Arrasto do dedo ao segurar (negativo = para a esquerda). Passou do
  /// limite, cancela.
  void arrastar(double dx) {
    if (_estado != WhatsAppEstadoDaGravacao.gravando || !_segurando) return;
    _arrasto = dx.clamp(-arrastoQueCancela - 20, 0.0);
    if (dx <= -arrastoQueCancela) {
      unawaited(cancelar());
      return;
    }
    notifyListeners();
  }

  /// Cancela a gravação em andamento (nada é salvo).
  Future<void> cancelar() async {
    if (_estado != WhatsAppEstadoDaGravacao.gravando) {
      _descartado = true;
      return;
    }
    _tique?.cancel();
    _cronometro.stop();
    try {
      await _recorder.cancel();
    } catch (e) {
      debugPrint('[WHATSAPP] gravador: cancel falhou: $e');
    }
    unawaited(HapticFeedback.selectionClick());
    await _limpar(apagarArquivo: true);
  }

  /// Joga fora a prévia.
  Future<void> descartar() async {
    await WhatsAppTocadorDeAudio.instance.parar(seFor: idDaPrevia);
    await _limpar(apagarArquivo: true);
  }

  /// Entrega a nota para envio e volta ao compositor normal. O arquivo fica
  /// no disco: quem envia apaga (ou devolve com [restaurar] se falhar).
  WhatsAppNotaDeVoz? consumir() {
    final caminho = _caminho;
    if (_estado != WhatsAppEstadoDaGravacao.previa || caminho == null) {
      return null;
    }
    unawaited(WhatsAppTocadorDeAudio.instance.parar(seFor: idDaPrevia));
    final nota = WhatsAppNotaDeVoz(
      caminho: caminho,
      nome: 'Nota de voz.$_extensao',
      duracao: _duracao,
    );
    _caminho = null;
    _estado = WhatsAppEstadoDaGravacao.ocioso;
    _duracao = Duration.zero;
    notifyListeners();
    return nota;
  }

  /// Envio falhou: a nota volta para a prévia, para tentar de novo.
  void restaurar(WhatsAppNotaDeVoz nota) {
    if (!ocioso) return;
    _caminho = nota.caminho;
    _duracao = nota.duracao;
    final ponto = nota.nome.lastIndexOf('.');
    _extensao = ponto > 0 ? nota.nome.substring(ponto + 1) : _extensao;
    _estado = WhatsAppEstadoDaGravacao.previa;
    notifyListeners();
  }

  Future<void> _limpar({required bool apagarArquivo}) async {
    _tique?.cancel();
    _cronometro
      ..stop()
      ..reset();
    final caminho = _caminho;
    _caminho = null;
    _segurando = false;
    _arrasto = 0;
    _duracao = Duration.zero;
    _estado = WhatsAppEstadoDaGravacao.ocioso;
    notifyListeners();
    if (apagarArquivo && caminho != null) {
      try {
        final f = File(caminho);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _tique?.cancel();
    final caminho = _caminho;
    if (_estado == WhatsAppEstadoDaGravacao.gravando) {
      unawaited(_recorder.cancel().catchError((_) {}));
    } else if (caminho != null) {
      unawaited(File(caminho).delete().then((_) {}, onError: (_) {}));
    }
    unawaited(_recorder.dispose());
    super.dispose();
  }
}

// ─── Peças de tela ──────────────────────────────────────────────────────────

Color _verde(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? AppColors.status.greenDarkMode
        : AppColors.status.green;

Color _vermelho(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;

/// Lado esquerdo do compositor enquanto grava ou na prévia (ocupa o lugar do
/// campo de texto). O botão da direita é o [WhatsAppBotaoDeVoz].
class WhatsAppPainelDeVoz extends StatelessWidget {
  final WhatsAppGravadorDeVoz gravador;

  const WhatsAppPainelDeVoz({super.key, required this.gravador});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: gravador,
      builder: (context, _) {
        return gravador.estado == WhatsAppEstadoDaGravacao.previa
            ? _PreviaDaNota(gravador: gravador)
            : _Gravando(gravador: gravador);
      },
    );
  }
}

class _Gravando extends StatelessWidget {
  final WhatsAppGravadorDeVoz gravador;

  const _Gravando({required this.gravador});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vermelho = _vermelho(context);
    final texto = ThemeHelpers.textColor(context);
    final secundaria = ThemeHelpers.textSecondaryColor(context);
    final segurando = gravador.segurando;
    // 0 → 1 conforme o dedo se aproxima do cancelamento.
    final perto = (gravador.arrasto.abs() /
            WhatsAppGravadorDeVoz.arrastoQueCancela)
        .clamp(0.0, 1.0);

    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.only(left: 4, right: 10),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ThemeHelpers.borderLightColor(context)),
      ),
      child: Row(
        children: [
          // Lixeira: cancela (no modo segurar, o arrasto faz o mesmo).
          Semantics(
            button: true,
            label: 'Cancelar gravação',
            child: IconButton(
              onPressed: () => gravador.cancelar(),
              visualDensity: VisualDensity.compact,
              icon: Icon(LucideIcons.trash2, size: 19, color: secundaria),
            ),
          ),
          // Microfone vermelho parado (sem piscar) + cronômetro.
          Icon(LucideIcons.mic, size: 16, color: vermelho),
          const SizedBox(width: 6),
          Text(
            formatarTempoDeAudio(gravador.duracao),
            style: theme.textTheme.titleSmall?.copyWith(
              color: texto,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: segurando
                ? Transform.translate(
                    offset: Offset(gravador.arrasto * 0.5, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Icon(
                          LucideIcons.chevronLeft,
                          size: 16,
                          color: Color.lerp(secundaria, vermelho, perto),
                        ),
                        Flexible(
                          child: Text(
                            'Deslize para cancelar',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Color.lerp(secundaria, vermelho, perto),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : Text(
                    'Gravando — toque em parar para ouvir',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secundaria,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PreviaDaNota extends StatelessWidget {
  final WhatsAppGravadorDeVoz gravador;

  const _PreviaDaNota({required this.gravador});

  @override
  Widget build(BuildContext context) {
    final tocador = WhatsAppTocadorDeAudio.instance;
    final theme = Theme.of(context);
    final verde = _verde(context);
    final secundaria = ThemeHelpers.textSecondaryColor(context);

    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.only(left: 4, right: 12),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ThemeHelpers.borderLightColor(context)),
      ),
      child: AnimatedBuilder(
        animation: tocador,
        builder: (context, _) {
          final id = gravador.idDaPrevia;
          final daVez = tocador.ehAtual(id);
          final tocando = daVez && tocador.tocando;
          final progresso = tocador.progressoDe(id);
          final tempo = daVez && tocador.duracao != null
              ? '${formatarTempoDeAudio(tocador.posicao)} / '
                  '${formatarTempoDeAudio(tocador.duracao!)}'
              : formatarTempoDeAudio(gravador.duracao);
          return Row(
            children: [
              Semantics(
                button: true,
                label: 'Descartar nota de voz',
                child: IconButton(
                  onPressed: () => gravador.descartar(),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(LucideIcons.trash2, size: 19, color: secundaria),
                ),
              ),
              Semantics(
                button: true,
                label: tocando ? 'Pausar prévia' : 'Ouvir antes de enviar',
                child: InkResponse(
                  radius: 20,
                  onTap: () async {
                    final ok = await tocador.alternar(
                      id: id,
                      fonte: () async => gravador.caminho,
                      arquivoLocal: true,
                    );
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Não foi possível tocar a prévia neste aparelho.',
                          ),
                        ),
                      );
                    }
                  },
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: Center(
                      child: daVez && tocador.carregando
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: verde,
                              ),
                            )
                          : Icon(
                              tocando ? LucideIcons.pause : LucideIcons.play,
                              size: 20,
                              color: verde,
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progresso,
                    minHeight: 4,
                    color: verde,
                    backgroundColor: secundaria.withValues(alpha: 0.22),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                tempo,
                maxLines: 1,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: secundaria,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Botão redondo da direita quando não há texto nem anexo: microfone
/// (tocar ou segurar), "parar" durante a gravação por toque, "enviar" na
/// prévia. É o MESMO widget nos três estados — trocar de widget no meio do
/// "segurar" cancelaria o gesto.
class WhatsAppBotaoDeVoz extends StatelessWidget {
  final WhatsAppGravadorDeVoz gravador;
  final bool habilitado;
  final bool enviando;

  /// Toque ou pressão longa no microfone (a tela confere permissão/janela
  /// antes de chamar [WhatsAppGravadorDeVoz.iniciar]).
  final void Function({required bool segurando}) onComecar;

  /// Toque em enviar na prévia.
  final VoidCallback onEnviar;

  /// Gravação curta demais (toque acidental no modo segurar).
  final VoidCallback? onCurtoDemais;

  const WhatsAppBotaoDeVoz({
    super.key,
    required this.gravador,
    required this.habilitado,
    required this.enviando,
    required this.onComecar,
    required this.onEnviar,
    this.onCurtoDemais,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final verde = _verde(context);
    final vermelho = _vermelho(context);
    final tinta = ThemeHelpers.onPrimaryColor(context);

    return AnimatedBuilder(
      animation: gravador,
      builder: (context, _) {
        final estado = gravador.estado;
        final gravandoSegurando =
            estado == WhatsAppEstadoDaGravacao.gravando && gravador.segurando;
        final gravandoPorToque =
            estado == WhatsAppEstadoDaGravacao.gravando && !gravador.segurando;
        final naPrevia = estado == WhatsAppEstadoDaGravacao.previa;

        final IconData icone;
        final String rotulo;
        Color fundo = verde;
        if (naPrevia) {
          icone = LucideIcons.arrowUp;
          rotulo = 'Enviar nota de voz';
        } else if (gravandoPorToque) {
          icone = LucideIcons.square;
          rotulo = 'Parar gravação';
          fundo = vermelho;
        } else {
          icone = LucideIcons.mic;
          rotulo = 'Gravar nota de voz. Toque para gravar ou segure e solte';
        }
        final ativo = habilitado && !enviando;
        // Segurando: o botão cresce sob o dedo, como no WhatsApp.
        final tamanho = gravandoSegurando ? 54.0 : 42.0;

        return Semantics(
          button: true,
          enabled: ativo,
          label: rotulo,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: !ativo
                ? null
                : () async {
                    if (naPrevia) {
                      onEnviar();
                    } else if (gravandoPorToque) {
                      final ok = await gravador.parar();
                      if (!ok) onCurtoDemais?.call();
                    } else if (estado == WhatsAppEstadoDaGravacao.ocioso) {
                      onComecar(segurando: false);
                    }
                  },
            onLongPressStart: !ativo || estado != WhatsAppEstadoDaGravacao.ocioso
                ? null
                : (_) => onComecar(segurando: true),
            onLongPressMoveUpdate: (d) =>
                gravador.arrastar(d.offsetFromOrigin.dx),
            onLongPressEnd: (_) async {
              if (gravador.estado == WhatsAppEstadoDaGravacao.gravando &&
                  gravador.segurando) {
                final ok = await gravador.parar();
                if (!ok) onCurtoDemais?.call();
              } else if (gravador.estado ==
                  WhatsAppEstadoDaGravacao.ocioso) {
                // Soltou antes de a gravação começar (permissão pendente).
                await gravador.parar();
              }
            },
            child: SizedBox(
              width: 42,
              height: 42,
              child: OverflowBox(
                maxWidth: 54,
                maxHeight: 54,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  width: tamanho,
                  height: tamanho,
                  decoration: BoxDecoration(
                    color: ativo
                        ? fundo
                        : fundo.withValues(alpha: isDark ? 0.35 : 0.4),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: enviando
                        ? SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: tinta,
                            ),
                          )
                        : Icon(
                            icone,
                            size: gravandoSegurando ? 24 : 20,
                            color: tinta,
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
