import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/finance_pin_store.dart';
import '../../core/widgets/finance_form_widgets.dart';
import '../models/request_rules.dart';

/// Arquivo escolhido para anexar (em memória até o envio).
class AnexoLocal {
  final String name;
  final List<int> bytes;
  final String mime;
  const AnexoLocal(this.name, this.bytes, this.mime);

  String get sizeLabel {
    final kb = bytes.length / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
    return '${(kb / 1024).toStringAsFixed(1).replaceAll('.', ',')} MB';
  }
}

/// Câmera / galeria / arquivo (PDF, JPG, PNG, WebP). Valida tipo e tamanho
/// ([limiteBytes]) antes de devolver. O seletor do sistema leva o app ao
/// segundo plano: `holdBackgroundLock` evita trancar o PIN no meio.
Future<AnexoLocal?> pickAnexo(
  BuildContext context, {
  required int limiteBytes,
}) async {
  final origem = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(LucideIcons.camera),
            title: const Text('Tirar foto'),
            onTap: () => Navigator.pop(ctx, 'camera'),
          ),
          ListTile(
            leading: const Icon(LucideIcons.image),
            title: const Text('Escolher da galeria'),
            onTap: () => Navigator.pop(ctx, 'galeria'),
          ),
          ListTile(
            leading: const Icon(LucideIcons.fileText),
            title: const Text('Arquivo (PDF ou imagem)'),
            onTap: () => Navigator.pop(ctx, 'arquivo'),
          ),
        ],
      ),
    ),
  );
  if (origem == null) return null;

  AnexoLocal? out;
  try {
    out = await FinancePinStore.instance.holdBackgroundLock(() async {
      if (origem == 'arquivo') {
        final r = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: kAnexoMimes.keys.toList(),
        );
        final f = r?.files.single;
        if (f == null) return null;
        final bytes = f.path == null ? await f.readAsBytes() : await File(f.path!).readAsBytes();
        return AnexoLocal(f.name, bytes, anexoMime(f.name) ?? 'application/octet-stream');
      }
      // Foto: a compressão do image_picker mantém abaixo de 5 MB.
      final x = await ImagePicker().pickImage(
        source: origem == 'camera' ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 2400,
        maxHeight: 2400,
      );
      if (x == null) return null;
      final bytes = await x.readAsBytes();
      var name = x.name;
      if (anexoMime(name) == null) name = '$name.jpg';
      return AnexoLocal(name, bytes, anexoMime(name) ?? 'image/jpeg');
    });
  } catch (e) {
    if (context.mounted) {
      financeSnack(context, 'Não foi possível abrir o arquivo.', error: true);
    }
    return null;
  }
  if (out == null) return null;
  final erro = validarAnexo(out.name, out.bytes.length, limiteBytes: limiteBytes);
  if (erro != null) {
    if (context.mounted) financeSnack(context, erro, error: true);
    return null;
  }
  return out;
}
