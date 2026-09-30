import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/whatsapp_midia.dart';
import '../models/whatsapp_models.dart';

// Mídia recebida/enviada dentro da conversa (29/09/2026).
//
// Antes o app só desenhava imagem; áudio, nota de voz, vídeo e documento
// viravam um chip "Abra no painel para visualizar." e obrigavam a usar o web.
// Paridade com o WhatsAppConversationViewer do web:
//  - imagem e figurinha na bolha, com tela cheia (pinça para ampliar);
//  - áudio, nota de voz e vídeo tocam no navegador do próprio app (Safari /
//    Chrome Custom Tabs), que tem o player nativo — o pubspec não tem pacote
//    de player (just_audio/video_player) e nenhuma dependência nova entra;
//  - documento abre no aplicativo do aparelho, como "Visualizar" na
//    biblioteca de documentos do app;
//  - em tudo, "Salvar ou compartilhar" baixa o arquivo e abre a folha do
//    sistema (é também a saída quando o aparelho não toca o formato, ex.:
//    nota de voz OGG em iPhone antigo);
//  - a URL assinada vence em 1 h: antes de abrir e quando a imagem falha, a
//    conversa renova a URL (o web faz o mesmo em `onError`).

/// Renova a URL assinada de uma mídia. Devolve a URL nova ou `null`.
typedef WhatsAppRenovarMidia = Future<String?> Function(WhatsAppMessage m);

/// Abrir, tocar e salvar mídia da conversa.
class WhatsAppAcoesDeMidia {
  WhatsAppAcoesDeMidia._();

  static void _aviso(BuildContext context, String texto) {
    if (!context.mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(texto),
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            isDark ? AppColors.status.errorDarkMode : AppColors.status.error,
      ),
    );
  }

  /// URL pronta para abrir: renova antes quando a assinatura venceu (ou vence
  /// nos próximos 2 minutos). Sem renovação possível, devolve a atual.
  static Future<String?> urlValida(
    WhatsAppMessage m,
    WhatsAppRenovarMidia? renovar,
  ) async {
    final atual = (m.mediaUrl ?? '').trim();
    if (atual.isNotEmpty && !urlAssinadaVencida(atual)) return atual;
    if (renovar != null) {
      final nova = await renovar(m);
      if (nova != null && nova.trim().isNotEmpty) return nova.trim();
    }
    return atual.isEmpty ? null : atual;
  }

  /// O Android lança exceção (ACTIVITY_NOT_FOUND) quando nada abre a URL;
  /// vira `false` para cair na próxima forma de abrir.
  static Future<bool> _lancar(Uri uri, LaunchMode modo) async {
    try {
      return await launchUrl(uri, mode: modo);
    } catch (_) {
      return false;
    }
  }

  /// Áudio, nota de voz e vídeo: tocam no navegador interno do app (player
  /// nativo do sistema). Sem navegador interno, vai para o app externo.
  static Future<void> tocar(
    BuildContext context,
    WhatsAppMessage m,
    WhatsAppRenovarMidia? renovar,
  ) async {
    final url = await urlValida(m, renovar);
    if (!context.mounted) return;
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null) {
      _aviso(context, 'Esta mídia não está disponível.');
      return;
    }
    var ok = await _lancar(uri, LaunchMode.inAppBrowserView);
    if (!ok) ok = await _lancar(uri, LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      _aviso(
        context,
        'Nenhum aplicativo deste aparelho abriu a mídia. Use "Salvar ou compartilhar".',
      );
    }
  }

  /// Documento: abre no aplicativo do aparelho (leitor de PDF, planilha…).
  static Future<void> abrirDocumento(
    BuildContext context,
    WhatsAppMessage m,
    WhatsAppRenovarMidia? renovar,
  ) async {
    final url = await urlValida(m, renovar);
    if (!context.mounted) return;
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null) {
      _aviso(context, 'Este documento não está disponível.');
      return;
    }
    var ok = await _lancar(uri, LaunchMode.externalApplication);
    if (!ok) ok = await _lancar(uri, LaunchMode.inAppBrowserView);
    if (!ok && context.mounted) {
      _aviso(
        context,
        'Nenhum aplicativo deste aparelho abriu o documento. Use "Salvar ou compartilhar".',
      );
    }
  }

  /// Nome do arquivo salvo: o da mensagem (documento) ou um nome pelo tipo.
  static String nomeParaSalvar(WhatsAppMessage m) {
    final original = (m.mediaFileName ?? '')
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (original.isNotEmpty) return original;
    final String prefixo;
    switch (m.messageType) {
      case WhatsAppMessageType.image:
        prefixo = 'imagem';
        break;
      case WhatsAppMessageType.sticker:
        prefixo = 'figurinha';
        break;
      case WhatsAppMessageType.audio:
        prefixo = 'audio';
        break;
      case WhatsAppMessageType.voice:
        prefixo = 'nota-de-voz';
        break;
      case WhatsAppMessageType.video:
        prefixo = 'video';
        break;
      default:
        prefixo = 'arquivo';
    }
    final id = m.id.length > 8 ? m.id.substring(0, 8) : m.id;
    final ext = extensaoPeloMime(m.mediaMimeType, m.messageType.name);
    return '$prefixo-${id.isEmpty ? 'whatsapp' : id}.$ext';
  }

  /// Baixa o arquivo e abre a folha do sistema (salvar em Arquivos, abrir em
  /// outro app, compartilhar). Se a assinatura venceu no caminho, renova uma
  /// vez e tenta de novo.
  static Future<void> baixarECompartilhar(
    BuildContext context,
    WhatsAppMessage m,
    WhatsAppRenovarMidia? renovar,
  ) async {
    final url = await urlValida(m, renovar);
    if (!context.mounted) return;
    if (url == null) {
      _aviso(context, 'Este arquivo não está disponível para baixar.');
      return;
    }
    try {
      var resposta =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 120));
      if ((resposta.statusCode == 403 || resposta.statusCode == 400) &&
          renovar != null) {
        final nova = await renovar(m);
        if (nova != null && nova != url) {
          resposta = await http
              .get(Uri.parse(nova))
              .timeout(const Duration(seconds: 120));
        }
      }
      if (!context.mounted) return;
      if (resposta.statusCode < 200 || resposta.statusCode >= 300) {
        _aviso(
          context,
          'Não foi possível baixar o arquivo (HTTP ${resposta.statusCode}).',
        );
        return;
      }
      final nome = nomeParaSalvar(m);
      final pasta = await getTemporaryDirectory();
      final destino = File(p.join(pasta.path, 'whatsapp', nome));
      await destino.parent.create(recursive: true);
      await destino.writeAsBytes(resposta.bodyBytes, flush: true);
      if (!context.mounted) return;
      // iPad exige a origem da folha; no celular ela é ignorada.
      Rect? origem;
      final caixa = context.findRenderObject();
      if (caixa is RenderBox && caixa.hasSize) {
        origem = caixa.localToGlobal(Offset.zero) & caixa.size;
      }
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(destino.path, mimeType: m.mediaMimeType)],
          subject: nome,
          sharePositionOrigin: origem,
        ),
      );
    } on TimeoutException {
      if (!context.mounted) return;
      _aviso(context, 'O download passou de 2 minutos sem terminar.');
    } catch (e) {
      if (!context.mounted) return;
      _aviso(context, 'Não foi possível baixar o arquivo: $e');
    }
  }
}

// ─── Peças visuais comuns ───────────────────────────────────────────────────

Color _fundoNeutro(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return (isDark ? Colors.white : Colors.black)
      .withValues(alpha: isDark ? 0.07 : 0.045);
}

Color _bordaNeutra(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return (isDark ? Colors.white : Colors.black)
      .withValues(alpha: isDark ? 0.10 : 0.06);
}

Color _verde(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? AppColors.status.greenDarkMode
        : AppColors.status.green;

Widget _botaoSalvar(
  BuildContext context, {
  required VoidCallback? onTap,
  bool ocupado = false,
  Color? cor,
}) {
  final c = cor ?? ThemeHelpers.textSecondaryColor(context);
  return Tooltip(
    message: 'Salvar ou compartilhar',
    child: InkResponse(
      onTap: ocupado ? null : onTap,
      radius: 20,
      child: SizedBox(
        width: 34,
        height: 34,
        child: Center(
          child: ocupado
              ? SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2, color: c),
                )
              : Icon(LucideIcons.download, size: 17, color: c),
        ),
      ),
    ),
  );
}

// ─── Imagem e figurinha ─────────────────────────────────────────────────────

/// Imagem da bolha: carrega a URL assinada, renova uma vez quando falha e
/// abre em tela cheia ao tocar.
class WhatsAppImagemDaBolha extends StatefulWidget {
  final WhatsAppMessage message;
  final WhatsAppRenovarMidia? onRenovarMidia;

  /// Título da tela cheia (nome do contato ou "Você").
  final String? titulo;
  final bool figurinha;

  const WhatsAppImagemDaBolha({
    super.key,
    required this.message,
    this.onRenovarMidia,
    this.titulo,
    this.figurinha = false,
  });

  @override
  State<WhatsAppImagemDaBolha> createState() => _WhatsAppImagemDaBolhaState();
}

class _WhatsAppImagemDaBolhaState extends State<WhatsAppImagemDaBolha> {
  bool _tentouRenovar = false;
  bool _renovando = false;
  bool _falhou = false;
  String? _urlDaRenovacao;

  @override
  void didUpdateWidget(covariant WhatsAppImagemDaBolha oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nova = widget.message.mediaUrl;
    if (nova != oldWidget.message.mediaUrl) {
      _falhou = false;
      // URL trocada por fora (releitura da thread): pode renovar de novo.
      // Trocada pela própria renovação: não, para não entrar em laço.
      if (nova != _urlDaRenovacao) _tentouRenovar = false;
    }
  }

  void _pedirRenovacao() {
    if (!mounted || _renovando) return;
    final renovar = widget.onRenovarMidia;
    if (_tentouRenovar || renovar == null) {
      if (!_falhou) setState(() => _falhou = true);
      return;
    }
    _tentouRenovar = true;
    setState(() => _renovando = true);
    renovar(widget.message).then((nova) {
      if (!mounted) return;
      setState(() {
        _renovando = false;
        if (nova == null || nova.isEmpty) {
          _falhou = true;
        } else {
          _urlDaRenovacao = nova;
          _falhou = false;
        }
      });
    });
  }

  void _abrirTelaCheia() {
    WhatsAppImagemTelaCheia.abrir(
      context,
      message: widget.message,
      titulo: widget.titulo,
      onRenovarMidia: widget.onRenovarMidia,
    );
  }

  Widget _carregando(BuildContext context) {
    final lado = widget.figurinha ? 120.0 : null;
    return Container(
      width: lado ?? 210,
      height: lado ?? 150,
      decoration: BoxDecoration(
        color: _fundoNeutro(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
        ),
      ),
    );
  }

  Widget _indisponivel(BuildContext context) {
    final theme = Theme.of(context);
    final secundaria = ThemeHelpers.textSecondaryColor(context);
    return InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: () => setState(() {
        _falhou = false;
        _tentouRenovar = false;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: _fundoNeutro(context),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: _bordaNeutra(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.imageOff, size: 20, color: secundaria),
            const SizedBox(width: 9),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.figurinha
                        ? 'Figurinha indisponível'
                        : 'Imagem indisponível',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textColor(context),
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'A mídia não pôde ser carregada. Toque para tentar de novo.',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: secundaria,
                      fontWeight: FontWeight.w500,
                      fontSize: 10.5,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = (widget.message.mediaUrl ?? '').trim();
    if (_falhou || url.isEmpty) return _indisponivel(context);
    if (_renovando) return _carregando(context);

    final imagem = Image.network(
      url,
      fit: widget.figurinha ? BoxFit.contain : BoxFit.cover,
      // Troca de URL (renovação) sem piscar o quadro vazio.
      gaplessPlayback: true,
      loadingBuilder: (context, child, progresso) {
        if (progresso == null) return child;
        return _carregando(context);
      },
      errorBuilder: (context, error, stack) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _pedirRenovacao());
        return _carregando(context);
      },
    );

    return Semantics(
      button: true,
      label: widget.figurinha ? 'Figurinha' : 'Imagem, toque para ampliar',
      child: GestureDetector(
        onTap: _abrirTelaCheia,
        child: widget.figurinha
            ? ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 140, maxHeight: 140),
                child: imagem,
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: 230, maxHeight: 260),
                  child: imagem,
                ),
              ),
      ),
    );
  }
}

/// Imagem em tela cheia, com pinça para ampliar e "Salvar ou compartilhar".
class WhatsAppImagemTelaCheia extends StatefulWidget {
  final WhatsAppMessage message;
  final String? titulo;
  final WhatsAppRenovarMidia? onRenovarMidia;

  const WhatsAppImagemTelaCheia({
    super.key,
    required this.message,
    this.titulo,
    this.onRenovarMidia,
  });

  static Future<void> abrir(
    BuildContext context, {
    required WhatsAppMessage message,
    String? titulo,
    WhatsAppRenovarMidia? onRenovarMidia,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => WhatsAppImagemTelaCheia(
          message: message,
          titulo: titulo,
          onRenovarMidia: onRenovarMidia,
        ),
      ),
    );
  }

  @override
  State<WhatsAppImagemTelaCheia> createState() =>
      _WhatsAppImagemTelaCheiaState();
}

class _WhatsAppImagemTelaCheiaState extends State<WhatsAppImagemTelaCheia> {
  late String _url = (widget.message.mediaUrl ?? '').trim();
  bool _tentouRenovar = false;
  bool _falhou = false;
  bool _salvando = false;

  Future<void> _renovar() async {
    if (_tentouRenovar) {
      if (mounted && !_falhou) setState(() => _falhou = true);
      return;
    }
    _tentouRenovar = true;
    final nova = await widget.onRenovarMidia?.call(widget.message);
    if (!mounted) return;
    setState(() {
      if (nova != null && nova.isNotEmpty && nova != _url) {
        _url = nova;
      } else {
        _falhou = true;
      }
    });
  }

  Future<void> _salvar() async {
    if (_salvando) return;
    setState(() => _salvando = true);
    await WhatsAppAcoesDeMidia.baixarECompartilhar(
      context,
      widget.message.copyWith(mediaUrl: _url),
      widget.onRenovarMidia,
    );
    if (mounted) setState(() => _salvando = false);
  }

  @override
  Widget build(BuildContext context) {
    final legenda = (widget.message.message ?? '').trim();
    final quando = widget.message.createdAt;
    final subtitulo = quando == null
        ? null
        : DateFormat("d 'de' MMM, HH:mm", 'pt_BR').format(quando.toLocal());
    final titulo = (widget.titulo ?? '').trim();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              titulo.isEmpty ? 'Imagem' : titulo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            if (subtitulo != null)
              Text(
                subtitulo,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.72),
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Salvar ou compartilhar',
            onPressed: _url.isEmpty || _salvando ? null : _salvar,
            icon: _salvando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(LucideIcons.download, size: 20),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _falhou || _url.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.imageOff,
                            size: 34,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Imagem indisponível',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'A mídia não pôde ser carregada.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    )
                  : InteractiveViewer(
                      minScale: 1,
                      maxScale: 5,
                      child: Image.network(
                        _url,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        loadingBuilder: (context, child, progresso) {
                          if (progresso == null) return child;
                          return const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          );
                        },
                        errorBuilder: (context, error, stack) {
                          WidgetsBinding.instance
                              .addPostFrameCallback((_) => _renovar());
                          return const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ),
          if (legenda.isNotEmpty)
            SafeArea(
              top: false,
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 160),
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                child: SingleChildScrollView(
                  child: Text(
                    legenda,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 14.5,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Áudio, nota de voz e vídeo ─────────────────────────────────────────────

/// Áudio/nota de voz (linha com botão de tocar) e vídeo (quadro com play).
/// Tocar abre o player nativo no navegador do app.
class WhatsAppMidiaTocavel extends StatefulWidget {
  final WhatsAppMessage message;
  final WhatsAppRenovarMidia? onRenovarMidia;

  const WhatsAppMidiaTocavel({
    super.key,
    required this.message,
    this.onRenovarMidia,
  });

  @override
  State<WhatsAppMidiaTocavel> createState() => _WhatsAppMidiaTocavelState();
}

class _WhatsAppMidiaTocavelState extends State<WhatsAppMidiaTocavel> {
  bool _abrindo = false;
  bool _salvando = false;

  bool get _ehVideo => widget.message.messageType == WhatsAppMessageType.video;
  bool get _ehVoz => widget.message.messageType == WhatsAppMessageType.voice;

  Future<void> _tocar() async {
    if (_abrindo) return;
    setState(() => _abrindo = true);
    await WhatsAppAcoesDeMidia.tocar(
        context, widget.message, widget.onRenovarMidia);
    if (mounted) setState(() => _abrindo = false);
  }

  Future<void> _salvar() async {
    if (_salvando) return;
    setState(() => _salvando = true);
    await WhatsAppAcoesDeMidia.baixarECompartilhar(
        context, widget.message, widget.onRenovarMidia);
    if (mounted) setState(() => _salvando = false);
  }

  @override
  Widget build(BuildContext context) {
    return _ehVideo ? _video(context) : _audio(context);
  }

  Widget _audio(BuildContext context) {
    final theme = Theme.of(context);
    final verde = _verde(context);
    final secundaria = ThemeHelpers.textSecondaryColor(context);
    final nome = (widget.message.mediaFileName ?? '').trim();
    final titulo = _ehVoz ? 'Nota de voz' : 'Áudio';
    final dica = _ehVoz || nome.isEmpty ? 'Toque para ouvir' : nome;

    return Semantics(
      button: true,
      label: '$titulo, toque para ouvir',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 250),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _tocar,
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 6, 2, 6),
              decoration: BoxDecoration(
                color: _fundoNeutro(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _bordaNeutra(context)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration:
                        BoxDecoration(color: verde, shape: BoxShape.circle),
                    child: Center(
                      child: _abrindo
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              LucideIcons.play,
                              size: 18,
                              color: Colors.white,
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _ehVoz ? LucideIcons.mic : LucideIcons.music,
                              size: 12,
                              color: secundaria,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                titulo,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: ThemeHelpers.textColor(context),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 1),
                        Text(
                          dica,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: secundaria,
                            fontWeight: FontWeight.w500,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _botaoSalvar(context, onTap: _salvar, ocupado: _salvando),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _video(BuildContext context) {
    final nome = (widget.message.mediaFileName ?? '').trim();
    return Semantics(
      button: true,
      label: 'Vídeo, toque para assistir',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 230,
          height: 132,
          child: Material(
            color: const Color(0xFF15151B),
            child: InkWell(
              onTap: _tocar,
              child: Stack(
                children: [
                  Center(
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: _abrindo
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF15151B),
                                ),
                              )
                            : const Padding(
                                padding: EdgeInsets.only(left: 3),
                                child: Icon(
                                  LucideIcons.play,
                                  size: 24,
                                  color: Color(0xFF15151B),
                                ),
                              ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: _botaoSalvar(
                      context,
                      onTap: _salvar,
                      ocupado: _salvando,
                      cor: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 8,
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.video,
                          size: 13,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            nome.isNotEmpty ? nome : 'Vídeo · toque para assistir',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.88),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Documento ──────────────────────────────────────────────────────────────

IconData iconeDaFamilia(WhatsAppFamiliaDoDocumento familia) {
  switch (familia) {
    case WhatsAppFamiliaDoDocumento.pdf:
      return LucideIcons.fileText;
    case WhatsAppFamiliaDoDocumento.planilha:
      return LucideIcons.fileSpreadsheet;
    case WhatsAppFamiliaDoDocumento.apresentacao:
      return LucideIcons.presentation;
    case WhatsAppFamiliaDoDocumento.texto:
      return LucideIcons.fileType;
    case WhatsAppFamiliaDoDocumento.outro:
      return LucideIcons.file;
  }
}

/// Documento na bolha: ícone da família, nome e "PDF · abrir". Tocar abre no
/// aplicativo do aparelho; o botão ao lado salva ou compartilha.
class WhatsAppDocumentoDaBolha extends StatefulWidget {
  final WhatsAppMessage message;
  final WhatsAppRenovarMidia? onRenovarMidia;

  const WhatsAppDocumentoDaBolha({
    super.key,
    required this.message,
    this.onRenovarMidia,
  });

  @override
  State<WhatsAppDocumentoDaBolha> createState() =>
      _WhatsAppDocumentoDaBolhaState();
}

class _WhatsAppDocumentoDaBolhaState extends State<WhatsAppDocumentoDaBolha> {
  bool _abrindo = false;
  bool _salvando = false;

  Future<void> _abrir() async {
    if (_abrindo) return;
    setState(() => _abrindo = true);
    await WhatsAppAcoesDeMidia.abrirDocumento(
        context, widget.message, widget.onRenovarMidia);
    if (mounted) setState(() => _abrindo = false);
  }

  Future<void> _salvar() async {
    if (_salvando) return;
    setState(() => _salvando = true);
    await WhatsAppAcoesDeMidia.baixarECompartilhar(
        context, widget.message, widget.onRenovarMidia);
    if (mounted) setState(() => _salvando = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final nome = (widget.message.mediaFileName ?? '').trim();
    final familia = familiaDoDocumento(nome, widget.message.mediaMimeType);
    final tom = familia == WhatsAppFamiliaDoDocumento.pdf
        ? (isDark ? AppColors.status.errorDarkMode : AppColors.status.error)
        : familia == WhatsAppFamiliaDoDocumento.planilha
            ? _verde(context)
            : familia == WhatsAppFamiliaDoDocumento.apresentacao
                ? (isDark
                    ? AppColors.status.warningDarkMode
                    : const Color(0xFFB7791F))
                : (isDark
                    ? AppColors.status.blueDarkMode
                    : AppColors.status.blue);

    return Semantics(
      button: true,
      label: 'Documento ${nome.isEmpty ? '' : nome}, toque para abrir',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _abrir,
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 8, 2, 8),
              decoration: BoxDecoration(
                color: _fundoNeutro(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _bordaNeutra(context)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: tom.withValues(alpha: isDark ? 0.18 : 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: _abrindo
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: tom,
                              ),
                            )
                          : Icon(iconeDaFamilia(familia), size: 20, color: tom),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          nome.isEmpty ? 'Documento' : nome,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ThemeHelpers.textColor(context),
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${rotuloDaFamilia(familia)} · abrir',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                            fontWeight: FontWeight.w500,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _botaoSalvar(context, onTap: _salvar, ocupado: _salvando),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
