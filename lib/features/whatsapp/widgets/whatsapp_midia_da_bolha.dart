import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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
//
// Revisão de design (30/09/2026), no molde do WhatsApp do iPhone:
//  - foto/vídeo com a proporção real presa entre tetos de largura E altura
//    (retrato alto não toma a tela; panorama não vira tira) e hora/ticks
//    opcionais sobre a mídia, em pílula escurecida (`sobreposicao`);
//  - áudio como o player do WhatsApp: tocar, onda (nota de voz) ou trilha
//    (arquivo de áudio) e o que é embaixo — o back não manda duração;
//  - documento como cartão: folha com o formato escrito, nome em 2 linhas,
//    família e o estado ("Abrindo…", "Baixando…");
//  - erro diz a causa em português e tem "Tentar de novo"; cores só por
//    token (saíram os dois `Color(0x…)` soltos).

/// Renova a URL assinada de uma mídia. Devolve a URL nova ou `null`.
typedef WhatsAppRenovarMidia = Future<String?> Function(WhatsAppMessage m);

/// Abrir, tocar e salvar mídia da conversa.
class WhatsAppAcoesDeMidia {
  WhatsAppAcoesDeMidia._();

  /// Aviso no cartão do tema com ícone vermelho (30/09/2026): o fundo
  /// vermelho saturado com o texto do tema perdia contraste no modo escuro.
  static void _aviso(BuildContext context, String texto) {
    if (!context.mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final vermelho =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ThemeHelpers.cardBackgroundColor(context),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: ThemeHelpers.borderColor(context)),
        ),
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(LucideIcons.circleAlert, size: 18, color: vermelho),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                texto,
                style: TextStyle(
                  color: ThemeHelpers.textColor(context),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Causa do download que falhou, em português (30/09/2026) — o código
  /// HTTP cru não dizia nada a quem usa; ele vai para o log.
  static String _causaDoHttp(int status) {
    if (status == 400 || status == 403) {
      return 'O link do arquivo venceu. Toque de novo para baixar.';
    }
    if (status == 404 || status == 410) {
      return 'O arquivo não está mais no servidor.';
    }
    if (status >= 500) {
      return 'O servidor não respondeu. Tente de novo em instantes.';
    }
    return 'Não foi possível baixar o arquivo. Tente de novo.';
  }

  /// URL pronta para abrir: renova antes quando a assinatura venceu (ou vence
  /// nos próximos 2 minutos) e quando a URL do S3 veio sem assinatura (fora
  /// do teto de 25 por resposta — 29/09/2026). Sem renovação possível,
  /// devolve a atual.
  static Future<String?> urlValida(
    WhatsAppMessage m,
    WhatsAppRenovarMidia? renovar,
  ) async {
    final atual = (m.mediaUrl ?? '').trim();
    if (atual.isNotEmpty &&
        !urlAssinadaVencida(atual) &&
        !urlDoS3SemAssinatura(atual)) {
      return atual;
    }
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
        debugPrint('[WhatsApp mídia] download HTTP ${resposta.statusCode}');
        _aviso(context, _causaDoHttp(resposta.statusCode));
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
      _aviso(
        context,
        'O download passou de 2 minutos sem terminar. Confira a internet e tente de novo.',
      );
    } catch (e) {
      // A exceção crua vai para o log; a pessoa lê a causa em português.
      debugPrint('[WhatsApp mídia] falha ao baixar/compartilhar: $e');
      if (!context.mounted) return;
      _aviso(
        context,
        e is SocketException || e is http.ClientException
            ? 'Sem conexão com a internet. Confira e tente de novo.'
            : 'Não foi possível baixar o arquivo. Tente de novo.',
      );
    }
  }
}

// ─── Peças visuais comuns ───────────────────────────────────────────────────

/// Raio da mídia dentro da bolha (acompanha o canto de 18 da bolha, menos o
/// respiro interno).
const double _raioMidia = 12;

/// Teto de largura da mídia: o de uma bolha de celular. A bolha ainda limita
/// por dentro (em 320dp sobram ~212), então nada passa da bolha.
const double _larguraMaximaDaMidia = 260;

/// Teto de altura da mídia por fração da tela (30/09/2026): retrato muito
/// alto não toma a tela e, deitado (landscape), a foto cabe entre o topo e a
/// caixa de texto.
double _alturaMaximaDaMidia(BuildContext context) {
  final altura = MediaQuery.sizeOf(context).height;
  return (altura * 0.42).clamp(140.0, 320.0).toDouble();
}

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
        width: 36,
        height: 36,
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

/// Hora e ticks SOBRE a foto/vídeo, em pílula escurecida (como no WhatsApp
/// do iPhone): legível em qualquer imagem, nos dois temas.
Widget _pilulaSobreMidia(Widget filho) {
  return DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      child: IconTheme.merge(
        data: const IconThemeData(color: Colors.white),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: Colors.white),
          child: filho,
        ),
      ),
    ),
  );
}

/// Pílula no canto inferior direito da mídia: encolhe (nunca estoura) quando
/// a hora com texto grande não cabe na largura da foto.
Widget _cantoInferiorDireito(Widget filho) {
  return Positioned(
    left: 6,
    right: 6,
    bottom: 6,
    child: Align(
      alignment: Alignment.bottomRight,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: _pilulaSobreMidia(filho),
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

  /// Hora e ticks desenhados SOBRE a imagem, no canto inferior direito, em
  /// pílula escurecida (WhatsApp do iPhone, quando não há legenda).
  /// Opcional: sem ele, a bolha segue com a hora embaixo. O conteúdo vem
  /// em branco (a pílula é escura nos dois temas); texto e ícone sem cor
  /// própria herdam o branco.
  final Widget? sobreposicao;

  const WhatsAppImagemDaBolha({
    super.key,
    required this.message,
    this.onRenovarMidia,
    this.titulo,
    this.figurinha = false,
    this.sobreposicao,
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

  /// Limites da foto (30/09/2026): a proporção real vale entre um piso e um
  /// teto de largura e de altura — retrato muito alto para no teto (corta
  /// em cover, como o WhatsApp) e panorama não vira tira (piso de 110).
  /// Sem LayoutBuilder: a bolha pode medir a largura intrínseca da mídia.
  BoxConstraints _limites(BuildContext context) {
    if (widget.figurinha) {
      return const BoxConstraints(maxWidth: 140, maxHeight: 140);
    }
    return BoxConstraints(
      minWidth: 140,
      maxWidth: _larguraMaximaDaMidia,
      minHeight: 110,
      maxHeight: _alturaMaximaDaMidia(context),
    );
  }

  Widget _carregando(BuildContext context) {
    final figurinha = widget.figurinha;
    return Container(
      width: figurinha ? 120 : 240,
      height: figurinha ? 120 : 170,
      decoration: BoxDecoration(
        color: _fundoNeutro(context),
        borderRadius: BorderRadius.circular(_raioMidia),
      ),
      child: Center(
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.32),
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Falhou mesmo depois de renovar (ou veio sem arquivo): diz o que houve e,
  /// quando há o que tentar, "Tentar de novo" à vista.
  Widget _indisponivel(BuildContext context, {required bool semArquivo}) {
    final theme = Theme.of(context);
    final secundaria = ThemeHelpers.textSecondaryColor(context);
    final texto = ThemeHelpers.textColor(context);
    final tipo = widget.figurinha ? 'Figurinha' : 'Imagem';
    final podeTentar = !semArquivo;

    final corpo = Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      decoration: BoxDecoration(
        color: _fundoNeutro(context),
        borderRadius: BorderRadius.circular(_raioMidia),
        border: Border.all(color: _bordaNeutra(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _fundoNeutro(context),
              shape: BoxShape.circle,
            ),
            child: Icon(LucideIcons.imageOff, size: 17, color: secundaria),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  podeTentar ? '$tipo não carregou' : '$tipo indisponível',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: texto,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  podeTentar
                      ? 'Confira a sua internet.'
                      : 'O arquivo não chegou ao servidor.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: secundaria,
                    fontWeight: FontWeight.w500,
                    fontSize: 11,
                  ),
                ),
                if (podeTentar) ...[
                  const SizedBox(height: 7),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.rotateCw, size: 13, color: texto),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          'Tentar de novo',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: texto,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _larguraMaximaDaMidia),
      child: !podeTentar
          ? corpo
          : Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(_raioMidia),
                onTap: () => setState(() {
                  _falhou = false;
                  _tentouRenovar = false;
                }),
                child: corpo,
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = (widget.message.mediaUrl ?? '').trim();
    if (_falhou || url.isEmpty) {
      return _indisponivel(context, semArquivo: url.isEmpty);
    }
    final limites = _limites(context);
    if (_renovando) {
      return ConstrainedBox(constraints: limites, child: _carregando(context));
    }

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

    Widget quadro = ConstrainedBox(constraints: limites, child: imagem);
    if (!widget.figurinha) {
      quadro = ClipRRect(
        borderRadius: BorderRadius.circular(_raioMidia),
        child: quadro,
      );
    }
    final sobre = widget.sobreposicao;
    if (sobre != null) {
      quadro = Stack(
        children: [quadro, _cantoInferiorDireito(sobre)],
      );
    }

    return Semantics(
      button: true,
      label: widget.figurinha ? 'Figurinha' : 'Imagem, toque para ampliar',
      child: GestureDetector(
        onTap: _abrirTelaCheia,
        child: quadro,
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

  /// Falha na tela cheia: a causa e "Tentar de novo" (o mesmo recomeço da
  /// bolha). Rola quando a tela é baixa (landscape com legenda).
  Widget _erro() {
    final podeTentar = _url.isNotEmpty;
    return SingleChildScrollView(
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
          Text(
            podeTentar ? 'A imagem não carregou' : 'Imagem indisponível',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            podeTentar
                ? 'Confira a sua internet e tente de novo.'
                : 'O arquivo não chegou ao servidor.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 12.5,
            ),
          ),
          if (podeTentar) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => setState(() {
                _falhou = false;
                _tentouRenovar = false;
              }),
              icon: const Icon(LucideIcons.rotateCw, size: 16),
              label: const Text(
                'Tentar de novo',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                shape: const StadiumBorder(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final legenda = (widget.message.message ?? '').trim();
    final quando = widget.message.createdAt;
    final subtitulo = quando == null
        ? null
        : DateFormat("d 'de' MMM, HH:mm", 'pt_BR').format(quando.toLocal());
    final titulo = (widget.titulo ?? '').trim();
    // Legenda longa não toma a foto deitado (landscape): teto pela altura.
    final tetoDaLegenda =
        math.min(160.0, MediaQuery.sizeOf(context).height * 0.28);

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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
                  ? _erro()
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
                constraints: BoxConstraints(maxHeight: tetoDaLegenda),
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

/// Áudio/nota de voz (player no molde do WhatsApp: tocar, onda ou trilha e o
/// que é) e vídeo (quadro 16:9 com play). Tocar abre o player nativo no
/// navegador do app.
class WhatsAppMidiaTocavel extends StatefulWidget {
  final WhatsAppMessage message;
  final WhatsAppRenovarMidia? onRenovarMidia;

  /// Só no vídeo: hora e ticks sobre o quadro, no canto inferior direito, em
  /// pílula escurecida (ver [WhatsAppImagemDaBolha.sobreposicao]).
  final Widget? sobreposicao;

  const WhatsAppMidiaTocavel({
    super.key,
    required this.message,
    this.onRenovarMidia,
    this.sobreposicao,
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

  /// Botão redondo de tocar, verde do WhatsApp; a tinta do ícone segue o
  /// tema (branco no claro, escura no escuro — o verde do escuro é claro).
  Widget _botaoTocar(BuildContext context, Color verde) {
    final tinta = ThemeHelpers.onPrimaryColor(context);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: verde, shape: BoxShape.circle),
      child: Center(
        child: _abrindo
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: tinta),
              )
            : Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Icon(LucideIcons.play, size: 18, color: tinta),
              ),
      ),
    );
  }

  Widget _audio(BuildContext context) {
    final theme = Theme.of(context);
    final verde = _verde(context);
    final secundaria = ThemeHelpers.textSecondaryColor(context);
    final nome = (widget.message.mediaFileName ?? '').trim();
    final titulo = _ehVoz ? 'Nota de voz' : 'Áudio';
    // O back não manda a duração: embaixo da onda vai o que é — "Nota de
    // voz" ou o nome do arquivo (reticências no meio, extensão visível).
    final rotulo = _salvando
        ? 'Baixando…'
        : _abrindo
            ? 'Abrindo o player…'
            : (_ehVoz || nome.isEmpty ? titulo : nomeAbreviado(nome, 30));

    return Semantics(
      button: true,
      label: '$titulo, toque para ouvir',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(_raioMidia),
            onTap: _tocar,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 3, 0, 1),
              child: Row(
                children: [
                  _botaoTocar(context, verde),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 24,
                          width: double.infinity,
                          child: CustomPaint(
                            painter: _TrilhaDoAudio(
                              semente: widget.message.id.hashCode,
                              onda: _ehVoz,
                              corDaTrilha: secundaria.withValues(alpha: 0.42),
                              corDoCursor: verde,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(
                              _ehVoz
                                  ? LucideIcons.mic
                                  : LucideIcons.headphones,
                              size: 12,
                              color: _ehVoz ? verde : secundaria,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                rotulo,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: secundaria,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
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
    // Quadro escuro nos dois temas (como o vídeo sem miniatura do WhatsApp).
    final fundo = AppColors.background.cardBackgroundDarkMode;
    final sobre = widget.sobreposicao;

    return Semantics(
      button: true,
      label: 'Vídeo, toque para assistir',
      // 16:9 pela largura da bolha (em 320dp ~212×119), com teto de
      // largura e de altura — antes 230×132 fixos.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: _larguraMaximaDaMidia,
          maxHeight: _alturaMaximaDaMidia(context),
        ),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_raioMidia),
            child: Material(
              color: fundo,
              child: InkWell(
                onTap: _tocar,
                child: Stack(
                  fit: StackFit.expand,
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
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: fundo,
                                  ),
                                )
                              : Padding(
                                  padding: const EdgeInsets.only(left: 3),
                                  child: Icon(
                                    LucideIcons.play,
                                    size: 24,
                                    color: fundo,
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
                      right: 6,
                      bottom: 6,
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
                              _abrindo
                                  ? 'Abrindo o player…'
                                  : nome.isNotEmpty
                                      ? nomeAbreviado(nome, 26)
                                      : 'Toque para assistir',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.88),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (sobre != null) ...[
                            const SizedBox(width: 6),
                            // Teto de 96: a hora encolhe em vez de empurrar
                            // o nome para fora (texto a 130%).
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 96),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: _pilulaSobreMidia(sobre),
                              ),
                            ),
                          ],
                        ],
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
}

/// Onda da nota de voz (barras) ou trilha do arquivo de áudio, com o cursor
/// no início — o desenho do player do WhatsApp. É decorativa: o back não
/// manda amplitude nem duração. A forma sai da mensagem (semente), então
/// cada nota tem a sua e não muda a cada releitura. Pinta na largura que
/// tiver: nunca estoura.
class _TrilhaDoAudio extends CustomPainter {
  final int semente;
  final bool onda;
  final Color corDaTrilha;
  final Color corDoCursor;

  const _TrilhaDoAudio({
    required this.semente,
    required this.onda,
    required this.corDaTrilha,
    required this.corDoCursor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    const raio = 5.5;
    final meio = size.height / 2;
    const inicio = raio * 2 + 3;
    final pincel = Paint()
      ..color = corDaTrilha
      ..strokeCap = StrokeCap.round;
    if (onda) {
      const passo = 4.0;
      pincel.strokeWidth = 2.4;
      var s = semente & 0x7fffffff;
      var x = inicio;
      while (x <= size.width - 2) {
        s = (s * 1664525 + 1013904223) & 0x7fffffff;
        final sorteio = (s % 1000) / 1000;
        // Mais alta no meio da fala, baixa nas pontas.
        final envelope = 0.45 + 0.55 * math.sin(math.pi * (x / size.width));
        final altura =
            math.max(3.0, size.height * (0.25 + 0.75 * sorteio) * envelope);
        canvas.drawLine(
          Offset(x, meio - altura / 2),
          Offset(x, meio + altura / 2),
          pincel,
        );
        x += passo;
      }
    } else if (size.width > inicio + 2) {
      pincel.strokeWidth = 3;
      canvas.drawLine(
        Offset(inicio, meio),
        Offset(size.width - 2, meio),
        pincel,
      );
    }
    canvas.drawCircle(
      Offset(raio + 1, meio),
      raio,
      Paint()..color = corDoCursor,
    );
  }

  @override
  bool shouldRepaint(covariant _TrilhaDoAudio old) =>
      old.semente != semente ||
      old.onda != onda ||
      old.corDaTrilha != corDaTrilha ||
      old.corDoCursor != corDoCursor;
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

/// Tom da família do documento, só por token: PDF vermelho, planilha verde,
/// apresentação âmbar (o de texto, legível no claro), texto/outros azul.
Color _tomDaFamilia(BuildContext context, WhatsAppFamiliaDoDocumento familia) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  switch (familia) {
    case WhatsAppFamiliaDoDocumento.pdf:
      return isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    case WhatsAppFamiliaDoDocumento.planilha:
      return _verde(context);
    case WhatsAppFamiliaDoDocumento.apresentacao:
      return isDark
          ? AppColors.message.warningTextDarkMode
          : AppColors.message.warningText;
    case WhatsAppFamiliaDoDocumento.texto:
    case WhatsAppFamiliaDoDocumento.outro:
      return isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
  }
}

/// Documento na bolha, como cartão do WhatsApp: folha com o formato escrito
/// ("PDF", "XLSX"), nome em até 2 linhas e "PDF · toque para abrir". Tocar
/// abre no aplicativo do aparelho; o botão ao lado salva ou compartilha.
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

  /// Folha do documento: ícone da família e o formato escrito embaixo. O
  /// formato encolhe (FittedBox num espaço limitado) com texto grande.
  Widget _folha(
    BuildContext context,
    WhatsAppFamiliaDoDocumento familia,
    Color tom,
    String formato,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 40,
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
      decoration: BoxDecoration(
        color: tom.withValues(alpha: isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: _abrindo
          ? Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: tom),
              ),
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(iconeDaFamilia(familia), size: 18, color: tom),
                if (formato.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        formato,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nome = (widget.message.mediaFileName ?? '').trim();
    final familia = familiaDoDocumento(nome, widget.message.mediaMimeType);
    final tom = _tomDaFamilia(context, familia);
    final ext = extensaoDoArquivo(nome).toUpperCase();
    // Extensão longa demais não é formato ("backup2026"): fica só o ícone.
    final formato = ext.length <= 5 ? ext : '';
    final estado = _salvando
        ? 'Baixando…'
        : _abrindo
            ? 'Abrindo…'
            : '${rotuloDaFamilia(familia)} · toque para abrir';

    return Semantics(
      button: true,
      label: nome.isEmpty
          ? 'Documento, toque para abrir'
          : 'Documento $nome, toque para abrir',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(_raioMidia),
            onTap: _abrir,
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 8, 2, 8),
              decoration: BoxDecoration(
                color: _fundoNeutro(context),
                borderRadius: BorderRadius.circular(_raioMidia),
                border: Border.all(color: _bordaNeutra(context)),
              ),
              child: Row(
                children: [
                  _folha(context, familia, tom, formato),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          nome.isEmpty ? 'Documento sem nome' : nome,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ThemeHelpers.textColor(context),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          estado,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
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
