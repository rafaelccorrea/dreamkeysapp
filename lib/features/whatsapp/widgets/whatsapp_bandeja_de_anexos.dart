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
// um, "+" para acrescentar e o resumo "3 de 30 · A legenda vai com a 1ª".
// Durante o lote, a linha "Enviando 2 de 5" com a barra de progresso.

/// De onde vem o anexo (folha do botão de clipe).
enum WhatsAppOrigemDoAnexo { camera, galeria, arquivo }

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
    final theme = Theme.of(context);
    final secundaria = ThemeHelpers.textSecondaryColor(context);
    final cheio = anexos.length >= kMaximoDeAnexos;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: anexos.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                if (i == anexos.length) {
                  return _BotaoAdicionar(
                    onTap: desabilitado || cheio ? null : onAdicionar,
                    dica: cheio
                        ? 'Máximo de $kMaximoDeAnexos por envio'
                        : 'Adicionar mais',
                  );
                }
                return _ItemDaBandeja(
                  anexo: anexos[i],
                  posicao: anexos.length > 1 ? i + 1 : null,
                  onRemover: desabilitado ? null : () => onRemover(anexos[i].id),
                );
              },
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Text(
                '${anexos.length} de $kMaximoDeAnexos',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: ThemeHelpers.textColor(context),
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  anexos.length > 1
                      ? 'A legenda vai com a 1ª'
                      : 'A legenda vai junto',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: secundaria,
                    fontWeight: FontWeight.w500,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ItemDaBandeja extends StatelessWidget {
  final WhatsAppAnexo anexo;
  final int? posicao;
  final VoidCallback? onRemover;

  const _ItemDaBandeja({
    required this.anexo,
    required this.posicao,
    required this.onRemover,
  });

  IconData get _icone {
    if (anexo.ehVideo) return LucideIcons.video;
    if (anexo.ehAudio) return LucideIcons.music;
    if (anexo.ehImagem) return LucideIcons.image;
    return iconeDaFamilia(familiaDoDocumento(anexo.nome, anexo.mime));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secundaria = ThemeHelpers.textSecondaryColor(context);
    final tamanho = rotuloDoTamanho(anexo.tamanho);

    final Widget conteudo = anexo.temPrevia
        ? Image.file(
            File(anexo.caminho),
            fit: BoxFit.cover,
            cacheWidth: 200,
            errorBuilder: (_, _, _) =>
                Center(child: Icon(_icone, size: 20, color: secundaria)),
          )
        : Padding(
            padding: const EdgeInsets.fromLTRB(5, 7, 5, 5),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_icone, size: 18, color: secundaria),
                const SizedBox(height: 3),
                Text(
                  nomeAbreviado(anexo.nome, 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: ThemeHelpers.textColor(context),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                if (tamanho.isNotEmpty)
                  Text(
                    tamanho,
                    maxLines: 1,
                    style: TextStyle(
                      color: secundaria,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                    ),
                  ),
              ],
            ),
          );

    return Semantics(
      label: '${anexo.nome}${tamanho.isEmpty ? '' : ', $tamanho'}'
          '${posicao == 1 ? ', leva a legenda' : ''}',
      child: SizedBox(
        width: 64,
        height: 64,
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black)
                      .withValues(alpha: isDark ? 0.07 : 0.045),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: (isDark ? Colors.white : Colors.black)
                        .withValues(alpha: isDark ? 0.12 : 0.08),
                  ),
                ),
                child: conteudo,
              ),
            ),
            if (posicao != null)
              Positioned(
                left: 4,
                bottom: 4,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 17),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  height: 17,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$posicao',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            // Remover dentro do quadro (a lista horizontal corta o que sai
            // dele): círculo escuro com borda clara, legível sobre a foto.
            Positioned(
              top: 3,
              right: 3,
              child: Semantics(
                button: true,
                label: 'Remover ${anexo.nome}',
                child: InkResponse(
                  onTap: onRemover,
                  radius: 16,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF2A2A36)
                          : const Color(0xFF3A3A44),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: ThemeHelpers.backgroundColor(context),
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
          ],
        ),
      ),
    );
  }
}

class _BotaoAdicionar extends StatelessWidget {
  final VoidCallback? onTap;
  final String dica;

  const _BotaoAdicionar({required this.onTap, required this.dica});

  @override
  Widget build(BuildContext context) {
    final secundaria = ThemeHelpers.textSecondaryColor(context);
    final ativo = onTap != null;
    return Tooltip(
      message: dica,
      child: Semantics(
        button: true,
        label: 'Adicionar mais arquivos',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: ThemeHelpers.borderColor(context),
                width: 1.2,
              ),
            ),
            child: Icon(
              LucideIcons.plus,
              size: 20,
              color: ativo ? secundaria : secundaria.withValues(alpha: 0.4),
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

/// Folha do clipe: câmera, galeria e arquivo — com os tipos que o canal
/// aceita (os mesmos rótulos das dicas do web).
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
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => WhatsAppOrigemDoAnexoSheet(naoOficial: naoOficial),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final verde =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final azul = isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    final violeta =
        isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.backgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.40),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ThemeHelpers.borderColor(context)
                        .withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
              child: Text(
                'Anexar',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  letterSpacing: -0.2,
                ),
              ),
            ),
            _opcao(
              context,
              icone: LucideIcons.camera,
              cor: verde,
              titulo: 'Câmera',
              detalhe: naoOficial
                  ? 'Tirar uma foto agora'
                  : 'Tirar uma foto agora ($kRotuloDasImagens, até 5MB)',
              valor: WhatsAppOrigemDoAnexo.camera,
            ),
            _opcao(
              context,
              icone: LucideIcons.images,
              cor: azul,
              titulo: naoOficial ? 'Fotos e vídeos' : 'Fotos',
              detalhe: naoOficial
                  ? 'Várias de uma vez, até 50MB cada'
                  : 'Várias de uma vez ($kRotuloDasImagens, até 5MB cada)',
              valor: WhatsAppOrigemDoAnexo.galeria,
            ),
            _opcao(
              context,
              icone: LucideIcons.paperclip,
              cor: violeta,
              titulo: naoOficial ? 'Arquivo' : 'Documento ou áudio',
              detalhe: naoOficial
                  ? 'Vídeo, áudio ou documento, até 50MB'
                  : 'Documento ($kRotuloDosDocumentos, até 50MB) ou áudio '
                      '($kRotuloDosAudios, até 16MB)',
              valor: WhatsAppOrigemDoAnexo.arquivo,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
              child: Text(
                'Até $kMaximoDeAnexos arquivos por envio; cada um vira uma '
                'mensagem, e o texto digitado vai como legenda do primeiro.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _opcao(
    BuildContext context, {
    required IconData icone,
    required Color cor,
    required String titulo,
    required String detalhe,
    required WhatsAppOrigemDoAnexo valor,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: () => Navigator.of(context).pop(valor),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: cor.withValues(alpha: isDark ? 0.18 : 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icone, size: 20, color: cor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    titulo,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: ThemeHelpers.textColor(context),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detalhe,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ],
        ),
      ),
    );
  }
}
