import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/whatsapp_anexos.dart';
import '../models/whatsapp_midia.dart';
import 'whatsapp_midia_da_bolha.dart' show iconeDaFamilia;

// Bandeja de anexos do composer (29/09/2026) — a vista da fila de
// `whatsapp_anexos.dart`, no desenho do `WhatsAppBandejaDeAnexos` do web:
// miniaturas na ordem de envio, posição quando há mais de um, remover em cada
// um, "+" para acrescentar e o resumo do lote.
// Durante o lote, a linha "Enviando 2 de 5" com a barra de progresso.
//
// Revisão de design (30/09/2026), na gramática do WhatsApp do iPhone:
//  - cabeçalho "3 anexos · 8,4 MB" com o limite ao lado (âmbar quando cheio);
//  - documento/áudio/vídeo com ícone na cor da família (a mesma da bolha),
//    formato ("PDF", "MP3"), nome com reticências no meio e tamanho;
//  - dica da legenda que segue a regra do envio (áudio no 1º = texto antes);
//  - a bandeja encolhe pela altura livre ACIMA DO TECLADO (o Scaffold tira o
//    teclado do MediaQuery do corpo, então a leitura vem da janela): com o
//    teclado aberto em tela baixa, o campo de legenda e o Enviar ficam à vista;
//  - folha do clipe como a do iPhone: opções agrupadas com ícone em cor por
//    tipo, "Cancelar" neutro separado, teto de 0,88 da tela e rolagem.

/// De onde vem o anexo (folha do botão de clipe).
enum WhatsAppOrigemDoAnexo { camera, galeria, arquivo }

/// Quanto da bandeja cabe na altura livre acima do teclado.
enum _ModoDaBandeja { oculta, linha, compacta, completa }

/// Cor da família do anexo — a mesma da bolha do documento, por token.
Color _tomDoAnexo(WhatsAppAnexo anexo, bool isDark) {
  final s = AppColors.status;
  if (anexo.ehImagem) return isDark ? s.blueDarkMode : s.blue;
  if (anexo.ehVideo) return isDark ? s.roseDarkMode : s.rose;
  if (anexo.ehAudio) return isDark ? s.purpleDarkMode : s.purple;
  switch (familiaDoDocumento(anexo.nome, anexo.mime)) {
    case WhatsAppFamiliaDoDocumento.pdf:
      return isDark ? s.errorDarkMode : s.error;
    case WhatsAppFamiliaDoDocumento.planilha:
      return isDark ? s.greenDarkMode : s.green;
    case WhatsAppFamiliaDoDocumento.apresentacao:
      return isDark
          ? AppColors.message.warningTextDarkMode
          : AppColors.message.warningText;
    case WhatsAppFamiliaDoDocumento.texto:
    case WhatsAppFamiliaDoDocumento.outro:
      return isDark ? s.blueDarkMode : s.blue;
  }
}

/// Formato curto para a ficha do anexo: a extensão ("PDF", "MP3") ou, sem
/// ela, o tipo em palavras.
String _formatoDoAnexo(WhatsAppAnexo anexo) {
  final ext = extensaoDoArquivo(anexo.nome).toUpperCase();
  if (ext.isNotEmpty && ext.length <= 4) return ext;
  if (anexo.ehVideo) return 'Vídeo';
  if (anexo.ehAudio) return 'Áudio';
  if (anexo.ehImagem) return 'Foto';
  switch (familiaDoDocumento(anexo.nome, anexo.mime)) {
    case WhatsAppFamiliaDoDocumento.pdf:
      return 'PDF';
    case WhatsAppFamiliaDoDocumento.planilha:
      return 'Planilha';
    case WhatsAppFamiliaDoDocumento.apresentacao:
      return 'Slides';
    case WhatsAppFamiliaDoDocumento.texto:
      return 'Texto';
    case WhatsAppFamiliaDoDocumento.outro:
      return 'Arquivo';
  }
}

class WhatsAppBandejaDeAnexos extends StatelessWidget {
  final List<WhatsAppAnexo> anexos;
  final ValueChanged<String> onRemover;
  final VoidCallback? onAdicionar;

  /// Durante o envio do lote: nada se mexe.
  final bool desabilitado;

  const WhatsAppBandejaDeAnexos({
    super.key,
    required this.anexos,
    required this.onRemover,
    this.onAdicionar,
    this.desabilitado = false,
  });

  @override
  Widget build(BuildContext context) {
    if (anexos.isEmpty) return const SizedBox.shrink();
    return _MedidorDaJanela(
      builder: (context, alturaLivre) {
        // Altura livre = janela − teclado − barra de status. Abaixo de 230
        // (deitado com teclado) a própria página já está no limite: a
        // bandeja sai e volta quando o teclado fecha.
        final modo = alturaLivre < 230
            ? _ModoDaBandeja.oculta
            : alturaLivre < 320
                ? _ModoDaBandeja.linha
                : alturaLivre < 440
                    ? _ModoDaBandeja.compacta
                    : _ModoDaBandeja.completa;
        if (modo == _ModoDaBandeja.oculta) return const SizedBox.shrink();
        return _conteudo(context, modo);
      },
    );
  }

  Widget _conteudo(BuildContext context, _ModoDaBandeja modo) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final texto = ThemeHelpers.textColor(context);
    final secundaria = ThemeHelpers.textSecondaryColor(context);
    final ambar = isDark
        ? AppColors.message.warningTextDarkMode
        : AppColors.message.warningText;
    final cheio = anexos.length >= kMaximoDeAnexos;

    var bytes = 0;
    for (final a in anexos) {
      if (a.tamanho > 0) bytes += a.tamanho;
    }
    final quantos = anexos.length == 1 ? '1 anexo' : '${anexos.length} anexos';
    final peso = bytes > 0 ? ' · ${rotuloDoTamanho(bytes)}' : '';

    // Mesma regra de `montarTrabalhosDeEnvio`: áudio não leva legenda, então
    // o texto sai antes, como mensagem própria.
    final primeiroEhAudio = anexos.first.ehAudio;
    final dicaCurta = primeiroEhAudio
        ? 'texto sai antes'
        : anexos.length > 1
            ? 'legenda vai no 1º'
            : 'legenda vai junto';
    final dicaLonga = primeiroEhAudio
        ? 'O texto digitado sai antes, em mensagem própria: áudio não leva '
            'legenda.'
        : anexos.length > 1
            ? 'O texto digitado vai como legenda do 1º anexo.'
            : 'O texto digitado vai como legenda.';
    final limite = cheio
        ? 'Limite de $kMaximoDeAnexos atingido'
        : 'máx. $kMaximoDeAnexos por envio';

    final forte = theme.textTheme.labelMedium?.copyWith(
      color: texto,
      fontWeight: FontWeight.w800,
      fontSize: 12,
      height: 1.25,
    );
    final fraco = theme.textTheme.labelMedium?.copyWith(
      color: secundaria,
      fontWeight: FontWeight.w600,
      fontSize: 12,
      height: 1.25,
    );
    final doLimite = cheio
        ? fraco?.copyWith(color: ambar, fontWeight: FontWeight.w800)
        : fraco;

    // Teclado aberto em tela baixa: só o resumo, numa linha.
    if (modo == _ModoDaBandeja.linha) {
      return Semantics(
        label: '$quantos na bandeja. ${cheio ? limite : dicaLonga}',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 7, 14, 0),
          child: Row(
            children: [
              Icon(LucideIcons.paperclip, size: 13, color: secundaria),
              const SizedBox(width: 6),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: quantos, style: forte),
                      TextSpan(text: '$peso · ', style: fraco),
                      TextSpan(
                        text: cheio ? limite : dicaCurta,
                        style: doLimite,
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final compacta = modo == _ModoDaBandeja.compacta;
    final lado = compacta ? 52.0 : 64.0;

    final faixa = SizedBox(
      height: lado + 8,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: anexos.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          if (i == anexos.length) {
            return _BotaoAdicionar(
              lado: lado,
              cheio: cheio,
              onTap: desabilitado || cheio ? null : onAdicionar,
            );
          }
          return _ItemDaBandeja(
            anexo: anexos[i],
            lado: lado,
            posicao: anexos.length > 1 ? i + 1 : null,
            onRemover: desabilitado ? null : () => onRemover(anexos[i].id),
          );
        },
      ),
    );

    if (compacta) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            faixa,
            const SizedBox(height: 3),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: quantos, style: forte),
                  TextSpan(text: '$peso · ', style: fraco),
                  TextSpan(text: cheio ? limite : dicaCurta, style: doLimite),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // "3 anexos · 8,4 MB" à esquerda, o limite à direita; sem espaço,
          // o limite desce inteiro para a linha de baixo.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 2,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: quantos, style: forte),
                    TextSpan(text: peso, style: fraco),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                limite,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: doLimite,
              ),
            ],
          ),
          const SizedBox(height: 4),
          faixa,
          const SizedBox(height: 4),
          // Encostada no campo: diz para onde vai o texto que se digita.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(LucideIcons.captions, size: 13, color: secundaria),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  dicaLonga,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: fraco?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Altura livre acima do teclado, relida a cada mudança da janela (teclado
/// abrindo/fechando, giro). O Scaffold (resizeToAvoidBottomInset) zera o
/// teclado no MediaQuery do corpo, por isso a leitura vem da própria janela.
class _MedidorDaJanela extends StatefulWidget {
  final Widget Function(BuildContext context, double alturaLivre) builder;

  const _MedidorDaJanela({required this.builder});

  @override
  State<_MedidorDaJanela> createState() => _MedidorDaJanelaState();
}

class _MedidorDaJanelaState extends State<_MedidorDaJanela>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final janela = MediaQueryData.fromView(View.of(context));
    final livre = janela.size.height -
        janela.viewInsets.bottom -
        janela.padding.top;
    return widget.builder(context, livre);
  }
}

class _ItemDaBandeja extends StatelessWidget {
  final WhatsAppAnexo anexo;
  final double lado;
  final int? posicao;
  final VoidCallback? onRemover;

  const _ItemDaBandeja({
    required this.anexo,
    required this.lado,
    required this.posicao,
    required this.onRemover,
  });

  IconData get _icone {
    if (anexo.ehVideo) return LucideIcons.video;
    if (anexo.ehAudio) return LucideIcons.music;
    if (anexo.ehImagem) return LucideIcons.image;
    return iconeDaFamilia(familiaDoDocumento(anexo.nome, anexo.mime));
  }

  /// Ficha do que não tem miniatura: ícone na cor da família, formato, nome
  /// (no quadro de 64) e tamanho. Encolhe inteira com fonte grande em vez de
  /// estourar o quadro.
  Widget _ficha(BuildContext context, Color tom, String tamanho) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final texto = ThemeHelpers.textColor(context);
    final secundaria = ThemeHelpers.textSecondaryColor(context);
    return Container(
      color: tom.withValues(alpha: isDark ? 0.16 : 0.10),
      padding: const EdgeInsets.all(4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: lado - 8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icone, size: lado >= 60 ? 18 : 16, color: tom),
              const SizedBox(height: 2),
              Text(
                _formatoDoAnexo(anexo),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: texto,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.2,
                  height: 1.15,
                ),
              ),
              if (lado >= 60)
                Text(
                  nomeAbreviado(anexo.nome, 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: texto,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              if (tamanho.isNotEmpty)
                Text(
                  tamanho,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: secundaria,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tom = _tomDoAnexo(anexo, isDark);
    final tamanho = rotuloDoTamanho(anexo.tamanho);
    final raio = BorderRadius.circular(lado >= 60 ? 12 : 10);

    final Widget miolo = anexo.temPrevia
        ? Image.file(
            File(anexo.caminho),
            fit: BoxFit.cover,
            cacheWidth: 200,
            errorBuilder: (context, _, _) => _ficha(context, tom, tamanho),
          )
        : _ficha(context, tom, tamanho);

    return Semantics(
      label: '${anexo.nome}, ${_formatoDoAnexo(anexo)}'
          '${tamanho.isEmpty ? '' : ', $tamanho'}'
          '${posicao == null ? '' : ', $posicaoº da fila'}',
      child: SizedBox(
        width: lado,
        height: lado,
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.background.backgroundTertiaryDarkMode
                      : AppColors.background.backgroundTertiary,
                  borderRadius: raio,
                  border: Border.all(
                    color: ThemeHelpers.borderLightColor(context),
                  ),
                ),
                child: miolo,
              ),
            ),
            if (posicao != null)
              Positioned(
                left: 4,
                bottom: 4,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  height: 18,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  alignment: Alignment.center,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$posicao',
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            // Remover dentro do quadro (a lista horizontal corta o que sai
            // dele): X branco em círculo escuro de borda clara, legível
            // sobre foto e sobre a ficha; área de toque de 32 no canto.
            Positioned(
              top: 0,
              right: 0,
              child: Semantics(
                button: true,
                enabled: onRemover != null,
                label: 'Remover ${anexo.nome}',
                onTap: onRemover,
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: onRemover,
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 3, right: 3),
                        child: Opacity(
                          opacity: onRemover == null ? 0.4 : 1,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.66),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.9),
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(
                              LucideIcons.x,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BotaoAdicionar extends StatelessWidget {
  final double lado;
  final bool cheio;
  final VoidCallback? onTap;

  const _BotaoAdicionar({
    required this.lado,
    required this.cheio,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final secundaria = ThemeHelpers.textSecondaryColor(context);
    final cor = onTap != null ? secundaria : secundaria.withValues(alpha: 0.45);
    final raio = BorderRadius.circular(lado >= 60 ? 12 : 10);
    return Tooltip(
      message: cheio
          ? 'Máximo de $kMaximoDeAnexos por envio'
          : 'Adicionar mais arquivos',
      child: Semantics(
        button: true,
        enabled: onTap != null,
        label: cheio
            ? 'Limite de $kMaximoDeAnexos anexos atingido'
            : 'Adicionar mais arquivos',
        onTap: onTap,
        excludeSemantics: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: raio,
            child: Container(
              width: lado,
              height: lado,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                borderRadius: raio,
                border: Border.all(
                  color: ThemeHelpers.borderColor(context),
                  width: 1.2,
                ),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      cheio ? LucideIcons.lock : LucideIcons.plus,
                      size: 20,
                      color: cor,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cheio ? 'Limite' : 'Adicionar',
                      maxLines: 1,
                      style: TextStyle(
                        color: cor,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
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

/// Linha "Enviando 2 de 5" com a barra do lote (a bandeja já esvaziou).
class WhatsAppProgressoDoLote extends StatelessWidget {
  final int atual;
  final int total;

  const WhatsAppProgressoDoLote({
    super.key,
    required this.atual,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final verde =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final fracao = total <= 0 ? 0.0 : ((atual - 1).clamp(0, total) / total);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 9, 14, 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            total == 1 ? 'Enviando 1 arquivo' : 'Enviando $atual de $total',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: total == 1 ? null : fracao.toDouble(),
              minHeight: 3,
              color: verde,
              backgroundColor: verde.withValues(alpha: 0.18),
            ),
          ),
        ],
      ),
    );
  }
}

/// Uma opção da folha do clipe.
class _OpcaoDeOrigem {
  final WhatsAppOrigemDoAnexo valor;
  final IconData icone;
  final Color cor;
  final String titulo;
  final String detalhe;

  const _OpcaoDeOrigem({
    required this.valor,
    required this.icone,
    required this.cor,
    required this.titulo,
    required this.detalhe,
  });
}

/// Folha do clipe, como a do WhatsApp do iPhone: Câmera, Fotos e Documento
/// agrupados, ícone em cor por tipo, o que o canal aceita escrito em cada
/// opção e "Cancelar" neutro à parte.
class WhatsAppOrigemDoAnexoSheet extends StatelessWidget {
  final bool naoOficial;

  const WhatsAppOrigemDoAnexoSheet({super.key, required this.naoOficial});

  static Future<WhatsAppOrigemDoAnexo?> show(
    BuildContext context, {
    required bool naoOficial,
  }) {
    return showModalBottomSheet<WhatsAppOrigemDoAnexo>(
      context: context,
      useSafeArea: true,
      // Sem isto a folha fica presa a 9/16 da altura: num celular de 568 pt
      // (ou deitado) as três opções com a regra do canal passavam do limite.
      // A folha cresce até o conteúdo (teto de 0,88) e rola quando não cabe.
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => WhatsAppOrigemDoAnexoSheet(naoOficial: naoOficial),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mq = MediaQuery.of(context);
    final texto = ThemeHelpers.textColor(context);
    final secundaria = ThemeHelpers.textSecondaryColor(context);
    final filete = ThemeHelpers.borderLightColor(context);
    // Fundo agrupado do iOS: folha um tom abaixo, cartões na cor do card.
    final fundo = isDark
        ? AppColors.background.backgroundDarkMode
        : AppColors.background.backgroundSecondary;
    final cartao = ThemeHelpers.cardBackgroundColor(context);
    final s = AppColors.status;

    final opcoes = <_OpcaoDeOrigem>[
      _OpcaoDeOrigem(
        valor: WhatsAppOrigemDoAnexo.camera,
        icone: LucideIcons.camera,
        cor: isDark ? s.roseDarkMode : s.rose,
        titulo: 'Câmera',
        detalhe: 'Tirar uma foto agora',
      ),
      _OpcaoDeOrigem(
        valor: WhatsAppOrigemDoAnexo.galeria,
        icone: LucideIcons.images,
        cor: isDark ? s.blueDarkMode : s.blue,
        titulo: naoOficial ? 'Fotos e vídeos' : 'Fotos',
        detalhe: naoOficial
            ? 'Várias de uma vez · até 50 MB cada'
            : 'Várias de uma vez · $kRotuloDasImagens, até 5 MB cada',
      ),
      _OpcaoDeOrigem(
        valor: WhatsAppOrigemDoAnexo.arquivo,
        icone: LucideIcons.fileText,
        cor: isDark ? s.purpleDarkMode : s.purple,
        titulo: naoOficial ? 'Arquivo' : 'Documento ou áudio',
        detalhe: naoOficial
            ? 'Documento, vídeo, áudio ou outro · até 50 MB'
            : 'PDF, Word, Excel, PowerPoint ou TXT até 50 MB · áudio '
                '$kRotuloDosAudios até 16 MB',
      ),
    ];

    final linhas = <Widget>[];
    for (var i = 0; i < opcoes.length; i++) {
      if (i > 0) {
        linhas.add(Divider(height: 1, thickness: 1, indent: 64, color: filete));
      }
      linhas.add(_linha(context, opcoes[i]));
    }

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.88),
        child: Container(
          decoration: BoxDecoration(
            color: fundo,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: filete),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 6),
                    child: Container(
                      width: 36,
                      height: 5,
                      decoration: BoxDecoration(
                        color: ThemeHelpers.borderColor(context),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Anexar',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: texto,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        naoOficial
                            ? 'Conexão por QR Code: aceita qualquer tipo de '
                                'arquivo.'
                            : 'API oficial: o WhatsApp só aceita os formatos '
                                'abaixo.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secundaria,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: cartao,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: filete),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: linhas,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 1),
                                child: Icon(
                                  LucideIcons.info,
                                  size: 14,
                                  color: secundaria,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Até $kMaximoDeAnexos arquivos por envio. '
                                  'Cada um vira uma mensagem, e o texto '
                                  'digitado vai como legenda do primeiro.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: secundaria,
                                    height: 1.35,
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
                // Cancelar à parte, como no iPhone — neutro (o tema pinta
                // TextButton de vermelho).
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: cartao,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: filete),
                    ),
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: secundaria,
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Cancelar',
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _linha(BuildContext context, _OpcaoDeOrigem opcao) {
    final theme = Theme.of(context);
    final secundaria = ThemeHelpers.textSecondaryColor(context);
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => Navigator.of(context).pop(opcao.valor),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 60),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    // Quadrado cheio na cor do tipo, glifo em contraste
                    // (branco no claro, escuro no escuro: ≥ 3:1 nos dois).
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: opcao.cor,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                        opcao.icone,
                        size: 19,
                        color: ThemeHelpers.onPrimaryColor(context),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            opcao.titulo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: ThemeHelpers.textColor(context),
                              fontWeight: FontWeight.w700,
                              fontSize: 15.5,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            opcao.detalhe,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: secundaria,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      LucideIcons.chevronRight,
                      size: 16,
                      color: secundaria,
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
