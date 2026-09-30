import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';

/// Ações de arquivo da biblioteca de documentos — abrir, baixar e copiar.
///
/// O web abre o `fileUrl` numa aba (Visualizar) e força o download com
/// `<a download>` (Baixar). No app: "Visualizar" abre no aplicativo externo;
/// "Baixar" traz os bytes para um arquivo temporário e abre a folha do
/// sistema para salvar ou compartilhar — assim o arquivo chega ao aparelho.
class DocumentFileActions {
  DocumentFileActions._();

  /// Aviso no snackbar do tema (cartão com borda): o significado vem do
  /// ícone colorido. Fundo verde/vermelho com o texto escuro do tema perdia
  /// contraste — no modo escuro, texto claro sobre verde claro.
  static void _snack(BuildContext context, String text, {bool ok = false}) {
    if (!context.mounted) return;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final Color tone;
    if (ok) {
      tone = dark ? AppColors.status.successDarkMode : AppColors.status.success;
    } else {
      tone = dark ? AppColors.status.errorDarkMode : AppColors.status.error;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
              size: 20,
              color: tone,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }

  /// Motivo legível de uma falha de rede/arquivo. O `toString()` da exceção
  /// (jargão para quem usa) vai só para o log.
  static String _failureText(Object e, String what) {
    if (e is TimeoutException) {
      return 'Demorou demais para $what e a operação foi interrompida. '
          'Confira a conexão e tente de novo.';
    }
    if (e is SocketException || e is http.ClientException) {
      return 'Sem conexão para $what. Confira a internet e tente de novo.';
    }
    return 'Não foi possível $what. Tente de novo em instantes.';
  }

  /// Motivo legível de uma resposta HTTP recusada no download.
  static String _httpFailureText(int status) {
    if (status == 401 || status == 403 || status == 404 || status == 410) {
      return 'O arquivo não está mais disponível no servidor (link expirado '
          'ou removido). Atualize a tela e tente de novo.';
    }
    if (status >= 500) {
      return 'O servidor de arquivos falhou ao entregar o download. Tente de '
          'novo em instantes.';
    }
    return 'O servidor recusou o download do arquivo (código $status).';
  }

  /// Abre o arquivo no aplicativo externo (navegador / leitor de PDF).
  static Future<void> open(BuildContext context, String? url) async {
    final u = url?.trim() ?? '';
    if (u.isEmpty) {
      _snack(context, 'Este documento está sem arquivo para visualizar.');
      return;
    }
    try {
      final ok = await launchUrl(
        Uri.parse(u),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && context.mounted) {
        _snack(
          context,
          'O aparelho não conseguiu abrir o arquivo. Tente "Baixar" e abrir '
          'pelo app de arquivos.',
        );
      }
    } catch (e) {
      debugPrint('[DocumentFileActions] open: $e');
      if (!context.mounted) return;
      _snack(
        context,
        'O aparelho não conseguiu abrir o arquivo. Tente "Baixar" e abrir '
        'pelo app de arquivos.',
      );
    }
  }

  /// Abre o link de assinatura (Autentique) no navegador do aparelho — fora
  /// do app, para o signatário assinar com a sessão/conta dele.
  static Future<void> openSignatureLink(
    BuildContext context,
    String? url,
  ) async {
    final u = url?.trim() ?? '';
    final uri = u.isEmpty ? null : Uri.tryParse(u);
    if (uri == null || !uri.hasScheme) {
      _snack(context, 'Link de assinatura indisponível.');
      return;
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        _snack(
          context,
          'Não foi possível abrir o link de assinatura no navegador. Use '
          '"Copiar link" e cole no navegador.',
        );
      }
    } catch (e) {
      debugPrint('[DocumentFileActions] openSignatureLink: $e');
      if (!context.mounted) return;
      _snack(
        context,
        'Não foi possível abrir o link de assinatura no navegador. Use '
        '"Copiar link" e cole no navegador.',
      );
    }
  }

  /// Baixa o arquivo e abre a folha de salvar/compartilhar.
  static Future<bool> download(
    BuildContext context,
    String? url,
    String fileName,
  ) async {
    final u = url?.trim() ?? '';
    if (u.isEmpty) {
      _snack(context, 'Este documento está sem arquivo para baixar.');
      return false;
    }
    try {
      final res = await http
          .get(Uri.parse(u))
          .timeout(const Duration(seconds: 120));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        if (!context.mounted) return false;
        _snack(context, _httpFailureText(res.statusCode));
        return false;
      }
      final path = await saveBytes(res.bodyBytes, fileName);
      if (!context.mounted) return false;
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path)], subject: fileName),
      );
      return true;
    } catch (e) {
      debugPrint('[DocumentFileActions] download: $e');
      if (!context.mounted) return false;
      _snack(context, _failureText(e, 'baixar o arquivo'));
      return false;
    }
  }

  /// Baixa vários arquivos e abre UMA folha de compartilhar com todos
  /// (equivalente ao "Baixar" em lote da biblioteca do web). Devolve quantos
  /// arquivos chegaram.
  static Future<int> downloadMany(
    BuildContext context,
    List<MapEntry<String, String>> urlAndName,
  ) async {
    final files = <XFile>[];
    for (final e in urlAndName) {
      final u = e.key.trim();
      if (u.isEmpty) continue;
      try {
        final res = await http
            .get(Uri.parse(u))
            .timeout(const Duration(seconds: 120));
        if (res.statusCode < 200 || res.statusCode >= 300) continue;
        final path = await saveBytes(res.bodyBytes, e.value);
        files.add(XFile(path));
      } catch (_) {}
    }
    if (!context.mounted) return files.length;
    if (files.isEmpty) {
      _snack(
        context,
        'Nenhum arquivo pôde ser baixado. Confira a conexão e tente de novo.',
      );
      return 0;
    }
    await SharePlus.instance.share(ShareParams(files: files));
    return files.length;
  }

  /// Grava bytes num arquivo temporário e devolve o caminho.
  static Future<String> saveBytes(List<int> bytes, String fileName) async {
    final dir = await getTemporaryDirectory();
    final safe = sanitizeFileName(fileName);
    final file = File('${dir.path}/$safe');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Compartilha um arquivo já gravado.
  static Future<void> shareFile(String path, {String? subject}) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], subject: subject),
    );
  }

  static String sanitizeFileName(String name) {
    final cleaned = name.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return cleaned.isEmpty ? 'arquivo' : cleaned;
  }

  static Future<void> copyLink(
    BuildContext context,
    String? url, {
    String message = 'Link copiado para a área de transferência',
  }) async {
    final u = url?.trim() ?? '';
    if (u.isEmpty) {
      _snack(context, 'Este item está sem link para copiar.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: u));
    if (!context.mounted) return;
    _snack(context, message, ok: true);
  }
}
