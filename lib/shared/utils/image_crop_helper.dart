import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import '../../core/theme/app_colors.dart';

/// Utilitário para recorte de imagens
class ImageCropHelper {
  ImageCropHelper._();

  /// Recorta uma imagem do arquivo
  /// 
  /// [imagePath] - Caminho do arquivo de imagem
  /// [aspectRatio] - Proporção de aspecto desejada (null para livre)
  /// [compressFormat] - Formato de compressão (ImageCompressFormat.jpg ou ImageCompressFormat.png)
  /// [compressQuality] - Qualidade de compressão (0-100)
  /// [lockAspectRatio] - Se true, trava a proporção de aspecto
  static Future<File?> cropImage({
    required String imagePath,
    CropAspectRatio? aspectRatio,
    ImageCompressFormat compressFormat = ImageCompressFormat.jpg,
    int compressQuality = 85,
    bool lockAspectRatio = false,
  }) async {
    try {
      // Verificar se o arquivo existe
      final file = File(imagePath);
      if (!await file.exists()) {
        debugPrint('Arquivo de imagem não existe: $imagePath');
        return null;
      }

      debugPrint('Abrindo crop para imagem: $imagePath');
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: imagePath,
        aspectRatio: aspectRatio,
        compressFormat: compressFormat,
        compressQuality: compressQuality,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Recortar Imagem',
            toolbarColor: AppColors.primary.primary,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: aspectRatio != null
                ? CropAspectRatioPreset.square
                : CropAspectRatioPreset.original,
            lockAspectRatio: lockAspectRatio || aspectRatio != null,
            aspectRatioPresets: aspectRatio == null
                ? [
                    CropAspectRatioPreset.original,
                    CropAspectRatioPreset.square,
                    CropAspectRatioPreset.ratio3x2,
                    CropAspectRatioPreset.ratio4x3,
                    CropAspectRatioPreset.ratio16x9,
                  ]
                : [
                    CropAspectRatioPreset.original,
                    CropAspectRatioPreset.square,
                  ],
          ),
          IOSUiSettings(
            title: 'Recortar Imagem',
            aspectRatioLockEnabled: lockAspectRatio || aspectRatio != null,
            resetAspectRatioEnabled: aspectRatio == null && !lockAspectRatio,
            aspectRatioPresets: [
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio3x2,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio16x9,
            ],
          ),
        ],
      );

      if (croppedFile != null) {
        debugPrint('Imagem recortada com sucesso: ${croppedFile.path}');
        return File(croppedFile.path);
      }
      debugPrint('Crop cancelado ou retornou null');
      return null;
    } catch (e) {
      // Erro ao recortar - log do erro para debug
      debugPrint('Erro ao recortar imagem: $e');
      // Retorna null para indicar que houve erro ou cancelamento
      return null;
    }
  }

  /// Recorta uma imagem para formato quadrado/circular (ideal para avatares)
  static Future<File?> cropImageCircle({
    required String imagePath,
    int compressQuality = 85,
  }) async {
    return cropImage(
      imagePath: imagePath,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      lockAspectRatio: true,
      compressQuality: compressQuality,
    );
  }

  /// Recorta uma imagem para formato retangular (ideal para imagens de imóveis)
  /// [aspectRatio] - Proporção específica (null para livre)
  static Future<File?> cropImageRect({
    required String imagePath,
    CropAspectRatio? aspectRatio,
    int compressQuality = 85,
  }) async {
    return cropImage(
      imagePath: imagePath,
      aspectRatio: aspectRatio,
      lockAspectRatio: aspectRatio != null,
      compressQuality: compressQuality,
    );
  }
}
