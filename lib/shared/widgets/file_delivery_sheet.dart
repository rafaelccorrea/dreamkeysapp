import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_helpers.dart';
import '../services/api_service.dart';
import '../utils/error_cause.dart';
import 'app_error_state.dart';

/// Arquivo pronto para entregar: bytes + nome (+ tipo, quando se sabe).
class DeliverableFile {
  const DeliverableFile({
    required this.bytes,
    required this.fileName,
    this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final String? mimeType;

  /// Extensão em minúsculas, sem o ponto ('' quando o nome não tem).
  String get extension {
    final name = fileName.trim();
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  /// Tipo para o sistema: o informado ou o deduzido da extensão.
  String get resolvedMimeType {
    final informed = mimeType?.trim() ?? '';
    if (informed.isNotEmpty) return informed.split(';').first.trim();
    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'zip':
        return 'application/zip';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.'
            'spreadsheetml.sheet';
      case 'csv':
        return 'text/csv';
      default:
        return 'application/octet-stream';
    }
  }
}

/// Desenho da folha que aparece enquanto o arquivo é gerado.
enum FileDeliveryPaper {
  /// Apresentação do imóvel: foto, título, preço, características, contato.
  presentation,

  /// Documento de texto (ficha, proposta, relatório) com linha de assinatura.
  document,

  /// Planilha (Excel, CSV).
  spreadsheet,
}

/// Folha de entrega de arquivo gerado no servidor — a saída única do app
/// para PDF, planilha e ZIP no celular.
///
/// Abrir o arquivo com `launchUrl(Uri.file(...))` não funciona no Android nem
/// no iOS (o url_launcher só abre `file:` no desktop): o arquivo ficava
/// "salvo em /caminho" que ninguém acha. Aqui ele sai por Compartilhar
/// (WhatsApp, e-mail, Drive, "Abrir com…") e por Salvar no aparelho (seletor
/// do sistema: Downloads, Arquivos).
///
/// A folha abre já carregando: a miniatura mostra o arquivo sendo "impresso",
/// o relógio diz há quanto tempo e, passado [slowAfterSeconds], o texto
/// avisa que está demorando. Falha vira o estado de erro padrão, com a causa
/// e "Tentar de novo". [details] aparece embaixo (gerando e pronto) — por
/// exemplo, o que vai e o que não vai no arquivo.
Future<void> showFileDeliverySheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required Future<ApiResponse<DeliverableFile>> Function() load,
  FileDeliveryPaper paper = FileDeliveryPaper.document,
  String? expectedType,
  String generatingTitle = 'Gerando o arquivo…',
  String generatingHint = 'Costuma levar poucos segundos.',
  String slowHint = 'Está levando mais que o normal. Aguarde mais um pouco.',
  int slowAfterSeconds = 45,
  String readyTitle = 'Arquivo pronto',
  String? Function(DeliverableFile file)? readyNote,
  String? failureHint,
  Widget? details,
  String? shareSubject,
  String saveDialogTitle = 'Salvar arquivo',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    // Tablet: folha com largura de leitura, centralizada.
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => _FileDeliverySheet(
      title: title,
      subtitle: subtitle,
      load: load,
      paper: paper,
      expectedType: expectedType,
      generatingTitle: generatingTitle,
      generatingHint: generatingHint,
      slowHint: slowHint,
      slowAfterSeconds: slowAfterSeconds,
      readyTitle: readyTitle,
      readyNote: readyNote,
      failureHint: failureHint,
      details: details,
      shareSubject: shareSubject,
      saveDialogTitle: saveDialogTitle,
    ),
  );
}

enum _Phase { generating, ready, failed }

class _FileDeliverySheet extends StatefulWidget {
  const _FileDeliverySheet({
    required this.title,
    required this.subtitle,
    required this.load,
    required this.paper,
    required this.expectedType,
    required this.generatingTitle,
    required this.generatingHint,
    required this.slowHint,
    required this.slowAfterSeconds,
    required this.readyTitle,
    required this.readyNote,
    required this.failureHint,
    required this.details,
    required this.shareSubject,
    required this.saveDialogTitle,
  });

  final String title;
  final String? subtitle;
  final Future<ApiResponse<DeliverableFile>> Function() load;
  final FileDeliveryPaper paper;
  final String? expectedType;
  final String generatingTitle;
  final String generatingHint;
  final String slowHint;
  final int slowAfterSeconds;
  final String readyTitle;
  final String? Function(DeliverableFile file)? readyNote;

  /// Dica extra embaixo do erro (ex.: "sincronize as assinaturas").
  final String? failureHint;
  final Widget? details;
  final String? shareSubject;
  final String saveDialogTitle;

  @override
  State<_FileDeliverySheet> createState() => _FileDeliverySheetState();
}

class _FileDeliverySheetState extends State<_FileDeliverySheet> {
  _Phase _phase = _Phase.generating;
  final Stopwatch _clock = Stopwatch();
  Timer? _ticker;
  int _seconds = 0;

  /// Nova tentativa descarta a resposta atrasada da anterior.
  int _attempt = 0;

  DeliverableFile? _file;
  String? _path;
  ErrorCause? _failure;
  bool _sharing = false;
  bool _saving = false;

  /// Resultado do salvar/compartilhar, escrito na própria folha: o snackbar
  /// da página ficaria escondido atrás dela.
  ({bool ok, String text})? _note;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _generate() async {
    final attempt = ++_attempt;
    _ticker?.cancel();
    _clock
      ..reset()
      ..start();
    setState(() {
      _phase = _Phase.generating;
      _seconds = 0;
      _file = null;
      _path = null;
      _failure = null;
      _note = null;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds = _clock.elapsed.inSeconds);
    });

    ApiResponse<DeliverableFile> res;
    try {
      res = await widget.load();
    } catch (e) {
      res = ApiResponse.error(message: e.toString(), statusCode: 0);
    }
    if (!mounted || attempt != _attempt) return;
    _ticker?.cancel();
    _clock.stop();

    final file = res.data;
    if (!res.success || file == null || file.bytes.isEmpty) {
      setState(() {
        _phase = _Phase.failed;
        _failure = _causeOf(res);
      });
      return;
    }

    try {
      final path = await _writeTemp(file);
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _file = file;
        _path = path;
        _phase = _Phase.ready;
      });
    } catch (e) {
      debugPrint('[FILE_DELIVERY] gravar: $e');
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _phase = _Phase.failed;
        _failure = ErrorCause.fromException(e);
      });
    }
  }

  /// Causa legível: tempo esgotado e falta de conexão pela família; o texto
  /// técnico (exceção crua) vai para o detalhe recolhido.
  static ErrorCause _causeOf(ApiResponse<DeliverableFile> res) {
    final raw = (res.message ?? '').trim();
    if (res.statusCode == 408 || raw.contains('TimeoutException')) {
      return ErrorCause.fromException(
        TimeoutException(
          raw.isEmpty ? 'O arquivo demorou demais para ficar pronto.' : raw,
        ),
      );
    }
    if (res.statusCode == 0) {
      return ErrorCause.fromApi(
        message: '',
        statusCode: 0,
        error: raw.isEmpty ? res.error : raw,
      );
    }
    return ErrorCause.fromApi(
      message: raw,
      statusCode: res.success ? 500 : res.statusCode,
      error: res.error,
    );
  }

  static String sanitizeFileName(String name) {
    final cleaned = name.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return cleaned.isEmpty ? 'arquivo' : cleaned;
  }

  static Future<String> _writeTemp(DeliverableFile file) async {
    final dir = await getTemporaryDirectory();
    final out = File('${dir.path}/${sanitizeFileName(file.fileName)}');
    await out.writeAsBytes(file.bytes, flush: true);
    return out.path;
  }

  Future<void> _share(BuildContext buttonContext) async {
    final file = _file;
    final path = _path;
    if (file == null || path == null || _sharing) return;
    // iPad: a folha do sistema precisa de uma âncora na tela.
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    setState(() {
      _sharing = true;
      _note = null;
    });
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              path,
              mimeType: file.resolvedMimeType,
              name: file.fileName,
            ),
          ],
          subject: widget.shareSubject ?? file.fileName,
          sharePositionOrigin: origin,
        ),
      );
    } catch (e) {
      debugPrint('[FILE_DELIVERY] compartilhar: $e');
      if (mounted) {
        setState(() {
          _note = (
            ok: false,
            text: 'O aparelho não abriu as opções de envio. Use "Salvar no '
                'aparelho" e envie pelo app de arquivos.',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _save() async {
    final file = _file;
    if (file == null || _saving) return;
    setState(() {
      _saving = true;
      _note = null;
    });
    try {
      final ext = file.extension;
      final saved = await FilePicker.saveFile(
        dialogTitle: widget.saveDialogTitle,
        fileName: sanitizeFileName(file.fileName),
        type: ext.isEmpty ? FileType.any : FileType.custom,
        allowedExtensions: ext.isEmpty ? null : [ext],
        bytes: file.bytes,
      );
      if (!mounted) return;
      if (saved != null) {
        setState(() {
          _note = (
            ok: true,
            text: 'Arquivo salvo no aparelho. Abra pelo app de arquivos.',
          );
        });
      }
    } catch (e) {
      debugPrint('[FILE_DELIVERY] salvar: $e');
      if (mounted) {
        setState(() {
          _note = (
            ok: false,
            text: 'Não foi possível salvar no aparelho. Use "Compartilhar" e '
                'escolha onde guardar.',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final maxHeight = mq.size.height * 0.88;
    // Deitado/tela baixa: o rodapé desce para o fim da rolagem em vez de
    // comer a pouca altura útil.
    final lowHeight = maxHeight < 380;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final hairline = ThemeHelpers.borderLightColor(context);
    final footer = _buildFooter(context);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Container(
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.55),
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: muted.withValues(alpha: 0.32),
                  ),
                ),
              ),
              _buildHeader(context),
              Container(height: 1, color: hairline),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildBody(context),
                      if (lowHeight) ...[
                        const SizedBox(height: 18),
                        footer,
                      ],
                    ],
                  ),
                ),
              ),
              if (!lowHeight) ...[
                Container(height: 1, color: hairline),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: footer,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final text = ThemeHelpers.textColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final subtitle = widget.subtitle?.trim() ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                    height: 1.2,
                    color: text,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      color: muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Fechar',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(LucideIcons.x, size: 20, color: muted),
          ),
        ],
      ),
    );
  }

  String? get _typeTag {
    final file = _file;
    if (file != null && file.extension.isNotEmpty) {
      return file.extension.toUpperCase();
    }
    final expected = widget.expectedType?.trim() ?? '';
    return expected.isEmpty ? null : expected.toUpperCase();
  }

  Widget _buildBody(BuildContext context) {
    final failure = _failure;
    if (_phase == _Phase.failed && failure != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: SizedBox(
              width: 84,
              child: _Paper(
                kind: widget.paper,
                look: _PaperLook.failed,
                tone: failure.tone,
                typeTag: _typeTag,
              ),
            ),
          ),
          AppErrorState(cause: failure, onRetry: _generate, dense: true),
          if ((widget.failureHint ?? '').trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                widget.failureHint!.trim(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ),
            ),
        ],
      );
    }

    final info = _phase == _Phase.ready
        ? _buildReadyInfo(context)
        : _buildGeneratingInfo(context);
    final look =
        _phase == _Phase.ready ? _PaperLook.done : _PaperLook.building;
    final paper = _Paper(kind: widget.paper, look: look, typeTag: _typeTag);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Lado a lado só quando o texto fica com ~220dp úteis; abaixo disso
        // (320dp, fonte grande) a folha sobe e o texto usa a largura toda.
        if (constraints.maxWidth < 340) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: SizedBox(width: 96, child: paper)),
              const SizedBox(height: 18),
              info,
            ],
          );
        }
        final paperWidth =
            (constraints.maxWidth * 0.3).clamp(96.0, 140.0).toDouble();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: paperWidth, child: paper),
            const SizedBox(width: 18),
            Expanded(child: info),
          ],
        );
      },
    );
  }

  Widget _buildGeneratingInfo(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = ThemeHelpers.textColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final tone = isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
    final slow = _seconds >= widget.slowAfterSeconds;
    final clock =
        '${_seconds ~/ 60}:${(_seconds % 60).toString().padLeft(2, '0')}';
    final details = widget.details;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                widget.generatingTitle,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  height: 1.25,
                  color: text,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              clock,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                height: 1.5,
                color: tone,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 4,
            color: tone,
            backgroundColor: tone.withValues(alpha: 0.14),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          slow ? widget.slowHint : widget.generatingHint,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.4,
            fontWeight: FontWeight.w500,
            color: muted,
          ),
        ),
        if (details != null) ...[
          const SizedBox(height: 18),
          details,
        ],
      ],
    );
  }

  Widget _buildReadyInfo(BuildContext context) {
    final file = _file!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = ThemeHelpers.textColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final green =
        isDark ? AppColors.status.successDarkMode : AppColors.status.success;
    final note = _note;
    final readyNote = widget.readyNote?.call(file);
    final details = widget.details;
    final typeLabel =
        file.extension.isEmpty ? 'Arquivo' : file.extension.toUpperCase();
    final IconData fileIcon;
    switch (file.extension) {
      case 'xlsx':
      case 'xls':
      case 'csv':
        fileIcon = LucideIcons.fileSpreadsheet;
      case 'zip':
        fileIcon = LucideIcons.fileArchive;
      default:
        fileIcon = LucideIcons.fileText;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(LucideIcons.circleCheck, size: 18, color: green),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.readyTitle,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  height: 1.25,
                  color: text,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // O arquivo que vai sair: nome (quem recebe vê este nome) e tamanho.
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.background.backgroundTertiaryDarkMode
                : AppColors.background.backgroundSecondary,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ThemeHelpers.borderLightColor(context)),
          ),
          child: Row(
            children: [
              Icon(fileIcon, size: 20, color: muted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      file.fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                        color: text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$typeLabel · ${_fileSize(file.bytes.length)}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: muted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (readyNote != null && readyNote.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            readyNote,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              fontWeight: FontWeight.w500,
              color: muted,
            ),
          ),
        ],
        if (note != null) ...[
          const SizedBox(height: 10),
          _InlineNote(ok: note.ok, text: note.text),
        ],
        if (details != null) ...[
          const SizedBox(height: 18),
          details,
        ],
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);

    if (_phase != _Phase.ready) {
      return Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          style: TextButton.styleFrom(foregroundColor: muted),
          child: Text(_phase == _Phase.generating ? 'Cancelar' : 'Fechar'),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final green =
        isDark ? AppColors.status.successDarkMode : AppColors.status.success;
    final text = ThemeHelpers.textColor(context);
    const shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(13)),
    );
    const padding = EdgeInsets.symmetric(horizontal: 14, vertical: 14);
    const labelStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.w800);

    Widget label(String value) => FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value, maxLines: 1, softWrap: false),
        );

    Widget spinner(Color color) => SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        );

    final save = OutlinedButton.icon(
      onPressed: _saving ? null : _save,
      style: OutlinedButton.styleFrom(
        foregroundColor: text,
        side: BorderSide(color: ThemeHelpers.borderColor(context)),
        padding: padding,
        shape: shape,
        textStyle: labelStyle,
      ),
      icon: _saving ? spinner(text) : const Icon(LucideIcons.download, size: 18),
      label: label(_saving ? 'Salvando…' : 'Salvar no aparelho'),
    );

    final share = Builder(
      builder: (buttonContext) => FilledButton.icon(
        onPressed: _sharing ? null : () => _share(buttonContext),
        style: FilledButton.styleFrom(
          backgroundColor: green,
          foregroundColor: Colors.white,
          disabledBackgroundColor: green.withValues(alpha: 0.5),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.85),
          padding: padding,
          shape: shape,
          textStyle: labelStyle,
        ),
        icon: _sharing
            ? spinner(Colors.white)
            : const Icon(LucideIcons.share2, size: 18),
        label: label('Compartilhar'),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Estreito (320dp, fonte grande): empilha com o principal em cima.
        if (constraints.maxWidth < 340) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [share, const SizedBox(height: 8), save],
          );
        }
        return Row(
          children: [
            Expanded(child: save),
            const SizedBox(width: 10),
            Expanded(child: share),
          ],
        );
      },
    );
  }

  static String _fileSize(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).ceil()} KB';
    }
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1).replaceAll('.', ',')} MB';
  }
}

/// Resultado do salvar/compartilhar escrito na folha, com ícone de sentido.
class _InlineNote extends StatelessWidget {
  const _InlineNote({required this.ok, required this.text});

  final bool ok;
  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone = ok
        ? (isDark ? AppColors.status.successDarkMode : AppColors.status.success)
        : (isDark ? AppColors.status.errorDarkMode : AppColors.status.error);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            ok ? LucideIcons.circleCheck : LucideIcons.circleAlert,
            size: 16,
            color: tone,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: ThemeHelpers.textColor(context),
            ),
          ),
        ),
      ],
    );
  }
}

enum _PaperLook { building, done, failed }

/// Miniatura A4 do arquivo. Gerando, uma linha de impressão desce pela folha
/// e o que está abaixo dela ainda não saiu; pronta, ganha o selo verde;
/// com falha, fica apagada com o selo na cor da família do erro. A etiqueta
/// no canto diz o tipo (PDF, XLSX, ZIP).
class _Paper extends StatefulWidget {
  const _Paper({
    required this.kind,
    required this.look,
    this.tone,
    this.typeTag,
  });

  final FileDeliveryPaper kind;
  final _PaperLook look;

  /// Cor do selo de falha (família do erro).
  final Color? tone;
  final String? typeTag;

  @override
  State<_Paper> createState() => _PaperState();
}

class _PaperState extends State<_Paper> with SingleTickerProviderStateMixin {
  late final AnimationController _print = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  bool get _animate =>
      widget.look == _PaperLook.building &&
      !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _Paper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.look != widget.look) _sync();
  }

  void _sync() {
    if (_animate) {
      if (!_print.isAnimating) _print.repeat();
    } else {
      _print.stop();
    }
  }

  @override
  void dispose() {
    _print.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final paper =
        isDark ? AppColors.background.backgroundTertiaryDarkMode : Colors.white;
    final failed = widget.look == _PaperLook.failed;
    final done = widget.look == _PaperLook.done;
    final textColor = ThemeHelpers.textColor(context);
    final ink =
        textColor.withValues(alpha: failed ? 0.10 : (isDark ? 0.30 : 0.18));
    final green =
        isDark ? AppColors.status.successDarkMode : AppColors.status.success;
    final printHead =
        isDark ? AppColors.status.infoDarkMode : AppColors.status.info;

    Widget bar(double widthFactor, double height, {Color? color}) {
      return FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: widthFactor,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: color ?? ink,
            borderRadius: BorderRadius.circular(height / 2),
          ),
        ),
      );
    }

    final List<Widget> content;
    switch (widget.kind) {
      case FileDeliveryPaper.presentation:
        content = [
          Expanded(
            flex: 10,
            child: Container(
              decoration: BoxDecoration(
                color: ink.withValues(alpha: ink.a * 0.6),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Icon(
                LucideIcons.image,
                size: 14,
                color: textColor.withValues(alpha: failed ? 0.18 : 0.35),
              ),
            ),
          ),
          const SizedBox(height: 6),
          bar(0.9, 4),
          const SizedBox(height: 3),
          bar(0.6, 4),
          const SizedBox(height: 6),
          bar(
            0.5,
            6,
            color: failed ? null : green.withValues(alpha: done ? 0.8 : 0.45),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: bar(1, 4)),
              const SizedBox(width: 3),
              Expanded(child: bar(1, 4)),
              const SizedBox(width: 3),
              Expanded(child: bar(1, 4)),
            ],
          ),
          const Spacer(flex: 3),
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              Expanded(child: bar(0.7, 3)),
            ],
          ),
        ];
      case FileDeliveryPaper.document:
        content = [
          bar(0.7, 5),
          const SizedBox(height: 8),
          for (final f in const [1.0, 0.92, 0.97, 0.6]) ...[
            bar(f, 3),
            const SizedBox(height: 4),
          ],
          const SizedBox(height: 4),
          for (final f in const [0.95, 1.0, 0.85]) ...[
            bar(f, 3),
            const SizedBox(height: 4),
          ],
          const Spacer(),
          // Linha de assinatura.
          Row(
            children: [
              Expanded(child: bar(1, 1.5)),
              const SizedBox(width: 6),
              Expanded(child: bar(1, 1.5)),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(child: bar(0.6, 2.5)),
              const SizedBox(width: 6),
              Expanded(child: bar(0.6, 2.5)),
            ],
          ),
        ];
      case FileDeliveryPaper.spreadsheet:
        content = [
          bar(0.55, 5),
          const SizedBox(height: 8),
          for (var row = 0; row < 7; row++) ...[
            Row(
              children: [
                for (var col = 0; col < 3; col++) ...[
                  if (col > 0) const SizedBox(width: 3),
                  Expanded(
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(
                        color: row == 0
                            ? ink.withValues(alpha: ink.a * 1.6)
                            : ink.withValues(alpha: ink.a * 0.7),
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 3),
          ],
          const Spacer(),
        ];
    }

    final sheet = Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: ThemeHelpers.borderColor(context)),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: content,
      ),
    );

    final tag = widget.typeTag;
    final muted = ThemeHelpers.textSecondaryColor(context);

    return Padding(
      // Folga para o selo que sai do canto da folha.
      padding: const EdgeInsets.only(top: 8, right: 8),
      child: AspectRatio(
        aspectRatio: 1 / 1.414,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: sheet),
            if (tag != null)
              Positioned(
                left: 6,
                bottom: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: paper,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: ThemeHelpers.borderColor(context)),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                      color: muted,
                    ),
                  ),
                ),
              ),
            if (_animate)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LayoutBuilder(
                    builder: (context, constraints) => AnimatedBuilder(
                      animation: _print,
                      builder: (context, _) {
                        final y = constraints.maxHeight *
                            Curves.easeInOut.transform(_print.value);
                        return Stack(
                          children: [
                            // O que ainda não foi impresso fica velado.
                            Positioned(
                              left: 0,
                              right: 0,
                              top: y,
                              bottom: 0,
                              child: ColoredBox(
                                color: paper.withValues(alpha: 0.78),
                              ),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              top: (y - 1)
                                  .clamp(0.0, constraints.maxHeight)
                                  .toDouble(),
                              height: 2,
                              child: ColoredBox(color: printHead),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            if (widget.look != _PaperLook.building)
              Positioned(
                right: -8,
                top: -8,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: done ? green : (widget.tone ?? ink),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: ThemeHelpers.cardBackgroundColor(context),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    done ? LucideIcons.check : LucideIcons.x,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
