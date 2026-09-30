import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/services/sale_forms_service.dart';

/// Família de cor de um significado (status da ficha, prazo, envio) — uma
/// fonte só para lista, card, detalhe, filtros e assinaturas.
///
/// [sinal] pinta ponto, borda, barra e fundo tonal (`AppColors.status`);
/// [texto] é a mesma família num tom que se lê sobre o fundo branco (o âmbar
/// e o azul de status somem como texto no modo claro — lá entra o
/// `AppColors.message.*Text`). No escuro os dois coincidem.
class SaleFormTom {
  const SaleFormTom(this.sinal, this.texto);

  final Color sinal;
  final Color texto;

  static bool _dark(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark;

  static SaleFormTom aviso(BuildContext c) => _dark(c)
      ? SaleFormTom(
          AppColors.status.warningDarkMode,
          AppColors.message.warningTextDarkMode,
        )
      : SaleFormTom(AppColors.status.warning, AppColors.message.warningText);

  static SaleFormTom info(BuildContext c) => _dark(c)
      ? SaleFormTom(
          AppColors.status.infoDarkMode,
          AppColors.message.infoTextDarkMode,
        )
      : SaleFormTom(AppColors.status.info, AppColors.message.infoText);

  static SaleFormTom sucesso(BuildContext c) => _dark(c)
      ? SaleFormTom(
          AppColors.status.successDarkMode,
          AppColors.message.successTextDarkMode,
        )
      : SaleFormTom(AppColors.status.success, AppColors.message.successText);

  static SaleFormTom erro(BuildContext c) => _dark(c)
      ? SaleFormTom(
          AppColors.status.errorDarkMode,
          AppColors.status.errorDarkMode,
        )
      : SaleFormTom(AppColors.status.error, AppColors.status.error);

  /// Cor do status da ficha — a mesma do card, dos filtros e do detalhe.
  static SaleFormTom doStatus(BuildContext c, SaleFormStatus s) {
    switch (s) {
      case SaleFormStatus.finalized:
        return sucesso(c);
      case SaleFormStatus.canceled:
        return erro(c);
      case SaleFormStatus.processing:
        return info(c);
      case SaleFormStatus.waitingForSignature:
        return aviso(c);
    }
  }

  /// Preenchimento de botão com texto branco: o verde de confirmação cheio
  /// nos dois temas (o tom claro do escuro deixa o branco ilegível).
  static Color verdeDeConfirmar() => AppColors.status.success;
}
