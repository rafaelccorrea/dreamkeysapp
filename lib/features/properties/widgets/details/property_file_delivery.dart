import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/utils/error_cause.dart';
import '../../../documents/utils/document_file_actions.dart';
import '../../services/property_detail_extras_service.dart';
import 'property_details_kit.dart';

/// Arquivo já gravado no temporário do aparelho, pronto para a folha do
/// sistema (compartilhar) ou para o seletor de salvar.
class PropertyLocalFile {
  const PropertyLocalFile({
    required this.path,
    required this.name,
    required this.mimeType,
    required this.size,
  });

  final String path;
  final String name;
  final String mimeType;
  final int size;

  XFile toXFile() => XFile(path, mimeType: mimeType, name: name);
}

/// Entrega dos arquivos da ficha (fotos, autorização assinada, PDF da ficha
/// de venda): grava no temporário, abre a folha do sistema com âncora (iPad
/// exige) e salva UM arquivo pelo seletor nativo — a mesma receita da folha
/// "Apresentação em PDF". Sem ZIP no app: várias fotos vão juntas na mesma
/// folha de compartilhar.
class PropertyFileDelivery {
  PropertyFileDelivery._();

  /// Grava [file] no temporário (com [name] no lugar do nome do servidor,
  /// quando dado). Lança em falha de disco.
  static Future<PropertyLocalFile> persist(
    PropertyDownloadedFile file, {
    String? name,
  }) async {
    final fileName =
        DocumentFileActions.sanitizeFileName(name ?? file.fileName);
    final path = await DocumentFileActions.saveBytes(file.bytes, fileName);
    return PropertyLocalFile(
      path: path,
      name: fileName,
      mimeType: file.mimeType,
      size: file.size,
    );
  }

  /// Retângulo do widget na tela — âncora da folha de compartilhar.
  static Rect? originOf(BuildContext context) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Abre a folha do sistema com [files]. `false` quando o aparelho não
  /// abriu as opções de envio.
  static Future<bool> share(
    List<PropertyLocalFile> files, {
    String? subject,
    Rect? origin,
  }) async {
    if (files.isEmpty) return false;
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [for (final f in files) f.toXFile()],
          subject: subject,
          sharePositionOrigin: origin,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('[PROPERTY_FILES] compartilhar: $e');
      return false;
    }
  }

  /// Salva UM arquivo pelo seletor do sistema. `true` = salvo; `false` = a
  /// pessoa desistiu. Lança quando o aparelho não conseguiu salvar.
  static Future<bool> saveOne(
    PropertyLocalFile file, {
    String? dialogTitle,
  }) async {
    final bytes = await File(file.path).readAsBytes();
    final ext = _extensionOf(file.name);
    final saved = await FilePicker.saveFile(
      dialogTitle: dialogTitle ?? 'Salvar arquivo',
      fileName: file.name,
      type: ext.isEmpty ? FileType.any : FileType.custom,
      allowedExtensions: ext.isEmpty ? null : <String>[ext],
      bytes: bytes,
    );
    return saved != null;
  }

  /// "820 KB" / "1,4 MB".
  static String sizeLabel(int bytes) {
    if (bytes < 1024 * 1024) {
      final kb = (bytes / 1024).ceil();
      return '${kb < 1 ? 1 : kb} KB';
    }
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1).replaceAll('.', ',')} MB';
  }

  /// Rótulo curto do tipo ("PDF", "ZIP", "JPG", "Imagem").
  static String typeLabel(String mimeType, String name) {
    final ext = _extensionOf(name);
    if (ext.isNotEmpty) return ext.toUpperCase();
    final m = mimeType.toLowerCase();
    if (m.contains('pdf')) return 'PDF';
    if (m.contains('zip')) return 'ZIP';
    if (m.startsWith('image/')) return 'Imagem';
    return 'Arquivo';
  }

  static String _extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    final ext = name.substring(dot + 1).toLowerCase();
    return ext.length > 5 ? '' : ext;
  }
}

/// Abre a folha "arquivo pronto": nome, tipo e tamanho do que veio do
/// servidor, com Compartilhar (verde) e Salvar no aparelho (neutro). O
/// resultado fica escrito na própria folha — o aviso da página ficaria
/// atrás dela.
///
/// Grava o arquivo no temporário antes de abrir; se o aparelho não
/// conseguir, avisa com a causa e não abre.
Future<void> showPropertyFileReadySheet(
  BuildContext context, {
  required PropertyDownloadedFile file,
  required String title,
  String? subtitle,
  String? shareSubject,
  String? hint,
}) async {
  final PropertyLocalFile local;
  try {
    local = await PropertyFileDelivery.persist(file);
  } catch (e) {
    debugPrint('[PROPERTY_FILES] gravar: $e');
    if (!context.mounted) return;
    pdkShowSnack(
      context,
      'O arquivo chegou, mas o aparelho não conseguiu guardá-lo. Libere '
      'espaço e tente de novo.',
      tone: PdkSnackTone.error,
    );
    return;
  }
  if (!context.mounted) return;
  await showPdkSheet<void>(
    context: context,
    builder: (_) => _FileReadySheet(
      file: local,
      title: title,
      subtitle: subtitle,
      shareSubject: shareSubject ?? title,
      hint: hint,
    ),
  );
}

class _FileReadySheet extends StatefulWidget {
  const _FileReadySheet({
    required this.file,
    required this.title,
    required this.shareSubject,
    this.subtitle,
    this.hint,
  });

  final PropertyLocalFile file;
  final String title;
  final String? subtitle;
  final String shareSubject;
  final String? hint;

  @override
  State<_FileReadySheet> createState() => _FileReadySheetState();
}

class _FileReadySheetState extends State<_FileReadySheet> {
  bool _sharing = false;
  bool _saving = false;

  /// Resultado de salvar/compartilhar, escrito na folha.
  ({bool ok, String text})? _note;

  Future<void> _share(BuildContext anchor) async {
    if (_sharing) return;
    final origin = PropertyFileDelivery.originOf(anchor);
    setState(() {
      _sharing = true;
      _note = null;
    });
    final ok = await PropertyFileDelivery.share(
      [widget.file],
      subject: widget.shareSubject,
      origin: origin,
    );
    if (!mounted) return;
    setState(() {
      _sharing = false;
      if (!ok) {
        _note = (
          ok: false,
          text: 'O aparelho não abriu as opções de envio. Use "Salvar no '
              'aparelho" e envie pelo app de arquivos.',
        );
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _note = null;
    });
    try {
      final saved = await PropertyFileDelivery.saveOne(
        widget.file,
        dialogTitle: widget.title,
      );
      if (!mounted) return;
      if (saved) {
        setState(() {
          _note = (
            ok: true,
            text: 'Arquivo salvo no aparelho. Abra pelo app de arquivos.',
          );
        });
      }
    } catch (e) {
      debugPrint('[PROPERTY_FILES] salvar: $e');
      if (!mounted) return;
      setState(() {
        _note = (
          ok: false,
          text: 'Não foi possível salvar no aparelho. Use "Compartilhar" e '
              'escolha onde guardar.',
        );
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final green = PdkTone.green(context);
    final note = _note;
    final hint = widget.hint?.trim() ?? '';
    return PdkSheetFrame(
      icon: LucideIcons.fileCheck,
      tone: green,
      title: widget.title,
      subtitle: widget.subtitle,
      onClose: () => Navigator.of(context).maybePop(),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PropertyFileCard(
              name: widget.file.name,
              mimeType: widget.file.mimeType,
              size: widget.file.size,
            ),
            if (hint.isNotEmpty) ...[
              const SizedBox(height: 12),
              PdkNote(
                icon: LucideIcons.info,
                tone: PdkTone.blue(context),
                text: hint,
              ),
            ],
            if (note != null) ...[
              const SizedBox(height: 12),
              PropertyInlineResult(ok: note.ok, text: note.text),
            ],
          ],
        ),
      ),
      footer: PdkActionPair(
        primary: Builder(
          builder: (anchor) => PdkSolidButton(
            label: 'Compartilhar',
            tone: green,
            icon: LucideIcons.share2,
            busy: _sharing,
            onPressed: () => _share(anchor),
          ),
        ),
        secondary: PdkNeutralButton(
          label: _saving ? 'Salvando…' : 'Salvar no aparelho',
          icon: LucideIcons.download,
          onPressed: _saving ? null : _save,
        ),
        minPrimary: 140,
        minSecondary: 150,
      ),
    );
  }
}

/// Cartão do arquivo: ícone do tipo, nome (até 2 linhas) e "PDF · 820 KB".
class PropertyFileCard extends StatelessWidget {
  const PropertyFileCard({
    super.key,
    required this.name,
    required this.mimeType,
    required this.size,
    this.caption,
  });

  final String name;
  final String mimeType;
  final int size;

  /// Linha extra sob o tipo/tamanho (ex.: "3 fotos").
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final m = mimeType.toLowerCase();
    final IconData icon;
    if (m.contains('zip')) {
      icon = LucideIcons.fileArchive;
    } else if (m.startsWith('image/')) {
      icon = LucideIcons.image;
    } else {
      icon = LucideIcons.fileText;
    }
    final meta = '${PropertyFileDelivery.typeLabel(mimeType, name)} · '
        '${PropertyFileDelivery.sizeLabel(size)}';
    final extra = caption?.trim() ?? '';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.background.backgroundTertiaryDarkMode
            : AppColors.background.backgroundSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ThemeHelpers.borderLightColor(context)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: muted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  extra.isEmpty ? meta : '$extra · $meta',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
    );
  }
}

/// Resultado de salvar/compartilhar escrito na folha, com ícone de sentido.
class PropertyInlineResult extends StatelessWidget {
  const PropertyInlineResult({super.key, required this.ok, required this.text});

  final bool ok;
  final String text;

  @override
  Widget build(BuildContext context) {
    final tone = ok ? PdkTone.green(context) : PdkTone.red(context);
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              ok ? LucideIcons.circleCheck : LucideIcons.circleAlert,
              size: 16,
              color: pdkInk(context, tone),
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
      ),
    );
  }
}

/// Aviso de falha de download com a causa (sem exceção crua), no desenho
/// do kit. [what] = o que não deu certo ("Não foi possível baixar …").
void propertyShowDownloadFailure(
  BuildContext context,
  String what,
  ErrorCause cause,
) {
  pdkShowSnack(context, '$what ${cause.cause}', tone: PdkSnackTone.error);
}
