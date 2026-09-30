import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/widgets/file_delivery_sheet.dart';
import '../services/property_presentation_service.dart';

/// Folha "Apresentação em PDF" — gera o PDF do imóvel para enviar ao cliente
/// (o mesmo do botão da ficha web) e entrega pela folha de arquivo do app
/// ([showFileDeliverySheet]): Compartilhar (WhatsApp, e-mail…) e Salvar no
/// aparelho.
///
/// "O que vai no PDF" responde a dúvida de quem vai mandar ao cliente: vão
/// fotos, valores e o contato de quem gerou; não vão os dados do proprietário
/// nem o endereço completo.
Future<void> showPropertyPresentationPdfSheet(
  BuildContext context, {
  required String propertyId,
  required String propertyTitle,
  String? propertyCode,
}) {
  final code = (propertyCode ?? '').trim();
  final subtitle = [
    if (code.isNotEmpty) '#$code',
    propertyTitle.trim(),
  ].where((s) => s.isNotEmpty).join(' · ');

  return showFileDeliverySheet(
    context,
    title: 'Apresentação em PDF',
    subtitle: subtitle,
    paper: FileDeliveryPaper.presentation,
    expectedType: 'PDF',
    generatingTitle: 'Gerando a apresentação…',
    generatingHint: 'O servidor monta o PDF com as fotos do imóvel. Costuma '
        'levar menos de 1 minuto.',
    slowHint: 'Está levando mais que o normal. Aguarde mais um pouco: o '
        'servidor tem até 1 minuto e meio para montar o PDF.',
    readyTitle: 'Apresentação pronta',
    details: const _WhatGoesInThePdf(),
    shareSubject: 'Apresentação — $propertyTitle',
    saveDialogTitle: 'Salvar apresentação',
    load: () async {
      final res = await PropertyPresentationService.instance.download(
        propertyId,
      );
      final pdf = res.data;
      if (!res.success || pdf == null) {
        return ApiResponse.error(
          message: res.message ?? '',
          statusCode: res.statusCode,
          data: res.error,
        );
      }
      return ApiResponse.success(
        data: DeliverableFile(
          bytes: pdf.bytes,
          fileName: pdf.fileName,
          mimeType: 'application/pdf',
        ),
        statusCode: res.statusCode,
      );
    },
  );
}

/// "O que vai no PDF" — o que o back coloca na apresentação
/// (`PropertyPresentationPdfService`): fotos, valores, características,
/// descrição e o contato de quem gerou com a marca da imobiliária.
class _WhatGoesInThePdf extends StatelessWidget {
  const _WhatGoesInThePdf();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = ThemeHelpers.textColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final green =
        isDark ? AppColors.status.successDarkMode : AppColors.status.success;

    Widget row(IconData icon, String label, {bool included = true}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 16, color: included ? green : muted),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: included ? FontWeight.w600 : FontWeight.w500,
                  color: included ? text : muted,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'O que vai no PDF',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.1,
            color: text,
          ),
        ),
        const SizedBox(height: 6),
        row(LucideIcons.check, 'Fotos do imóvel'),
        row(LucideIcons.check, 'Valores e características'),
        row(LucideIcons.check, 'Descrição do anúncio'),
        row(LucideIcons.check, 'Seu nome e contato, com a marca da imobiliária'),
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(vertical: 6),
          color: ThemeHelpers.borderLightColor(context),
        ),
        row(
          LucideIcons.eyeOff,
          'Fica de fora: dados do proprietário e endereço completo',
          included: false,
        ),
      ],
    );
  }
}
