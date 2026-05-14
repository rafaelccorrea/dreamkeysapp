import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/navigation/adaptive_page_route.dart';
import 'package:image_cropper/image_cropper.dart';

import '../../core/theme/app_colors.dart';
import '../widgets/square_photo_editor_page.dart';

/// Utilitário central de recorte de imagens.
///
/// Para fotos de imóvel (`cropImageRect` / `cropImageSquare`) usamos
/// uma tela **Flutter pura premium** que fica travada em 1:1 — corretores
/// não conseguem mais escolher proporções erradas (3:2, 4:3, 16:9) que
/// eram reprovadas na fila de aprovação.
///
/// Para avatar de perfil (`cropImageCircle`) seguimos com o
/// `image_cropper` nativo (que tem máscara circular pronta).
class ImageCropHelper {
  ImageCropHelper._();

  /// Recorta uma foto de imóvel em **proporção quadrada (1:1)**.
  ///
  /// Abre a tela `SquarePhotoEditorPage` (Flutter puro, dark-mode-aware,
  /// rule-of-thirds, pan/zoom). O usuário ajusta o enquadramento dentro
  /// do quadrado fixo e a saída é uma imagem PNG ~1024×1024px.
  ///
  /// Retorna `null` se o usuário cancelar (toca em "Cancelar" ou volta).
  ///
  /// **Por que travar 1:1**: imóveis em vitrine (web + apps de portal)
  /// ficam mais consistentes em quadrado; e a fila de aprovação rejeita
  /// fotos não-quadradas.
  static Future<File?> cropImageSquare({
    required BuildContext context,
    required String imagePath,
  }) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      debugPrint('Arquivo de imagem não existe: $imagePath');
      return null;
    }
    if (!context.mounted) return null;
    return Navigator.of(context).push<File?>(
      adaptivePageRoute<File?>(
        builder: (_) => SquarePhotoEditorPage(sourceFile: file),
        fullscreenDialog: true,
      ),
    );
  }

  /// **Compatibilidade**: alias histórico que aceitava `aspectRatio`
  /// livre. Agora redireciona para o cropper quadrado — o parâmetro
  /// `aspectRatio` e `compressQuality` são ignorados (o novo editor
  /// escolhe os valores ideais por padrão).
  ///
  /// Mantido como `cropImageRect` apenas para evitar quebrar os call
  /// sites existentes; novos usos devem chamar `cropImageSquare`
  /// diretamente.
  static Future<File?> cropImageRect({
    required BuildContext context,
    required String imagePath,
    @Deprecated('Ignorado — o novo editor é sempre 1:1.')
    CropAspectRatio? aspectRatio,
    @Deprecated('Ignorado — o novo editor escolhe a qualidade ideal.')
    int compressQuality = 85,
  }) {
    return cropImageSquare(context: context, imagePath: imagePath);
  }

  /// Recorta uma imagem para formato quadrado/circular (ideal para
  /// avatares). Continua usando o cropper nativo `image_cropper` que tem
  /// suporte pronto a máscara circular.
  static Future<File?> cropImageCircle({
    required String imagePath,
    int compressQuality = 85,
  }) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        debugPrint('Arquivo de imagem não existe: $imagePath');
        return null;
      }

      final croppedFile = await ImageCropper().cropImage(
        sourcePath: imagePath,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: compressQuality,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Recortar Avatar',
            toolbarColor: AppColors.primary.primary,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
            aspectRatioPresets: const [
              CropAspectRatioPreset.square,
            ],
          ),
          IOSUiSettings(
            title: 'Recortar Avatar',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
            aspectRatioPresets: const [
              CropAspectRatioPreset.square,
            ],
          ),
        ],
      );

      if (croppedFile != null) {
        return File(croppedFile.path);
      }
      return null;
    } catch (e) {
      debugPrint('Erro ao recortar avatar: $e');
      return null;
    }
  }
}
