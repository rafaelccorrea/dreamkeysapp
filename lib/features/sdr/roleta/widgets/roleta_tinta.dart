import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../widgets/sdr_tinta_legivel.dart';
import '../models/sdr_roulette_rules.dart';

/// Tinta da Roleta de SDRs — a régua aprovada no web ("ficou PERFEITO",
/// 21/09/2026). Cor só com significado, a mesma em toda a tela:
///   · verde     — NA ROLETA (recebe conversa) e a ação principal;
///   · âmbar     — FOLGA: pausa com prazo, em curso ou marcada;
///   · ardósia   — PAUSADO à mão (não é perigo: é estar fora);
///   · azul info — LOCAÇÃO, o mesmo azul do selo Locação da lista;
///   · vermelho  — só o destrutivo (cancelar a folga marcada) e o erro.
///
/// Revisão 30/09/2026: tudo por token da casa (`AppColors`/`ThemeHelpers`),
/// sem hex solto — o verde é o `status.green` que o WhatsApp do app já usa;
/// o âmbar do claro parte do `message.warningText` (o `status.warning`
/// #E6B84C some no branco); neutros saem de `AppColors.background`.
///
/// Contraste real no claro: as cores de significado saem por
/// [sdrTintaLegivel] (≥ 4,5:1 sobre o fill terciário, logo sobre o branco e
/// a banda) — são texto, ícone pequeno ou fundo de botão com texto branco na
/// tela toda. No escuro os tokens já passam e voltam como vieram.
class RoletaTinta {
  RoletaTinta._();

  static bool escuro(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  // ─── Significado ─────────────────────────────────────────────────────────

  static Color verde(BuildContext c) {
    return sdrTintaLegivel(
      c,
      escuro(c) ? AppColors.status.greenDarkMode : AppColors.status.green,
    );
  }

  /// Tinta sobre o verde: branco no claro; no escuro o verde é claro demais
  /// para texto branco (a mesma regra da cor primária da casa).
  static Color tintaSobreVerde(BuildContext c) => tintaSobreCor(c);

  /// Texto sobre qualquer cor de significado cheia (verde, azul, âmbar):
  /// branco no claro (as tintas legíveis passam de 4,5:1 com ele); escuro
  /// no escuro, onde os tons são claros demais para branco.
  static Color tintaSobreCor(BuildContext c) {
    return ThemeHelpers.onPrimaryColor(c);
  }

  static Color ambar(BuildContext c) {
    return sdrTintaLegivel(
      c,
      escuro(c)
          ? AppColors.status.warningDarkMode
          : AppColors.message.warningText,
    );
  }

  static Color ardosia(BuildContext c) {
    return sdrTintaLegivel(
      c,
      escuro(c) ? AppColors.text.textLightDarkMode : AppColors.text.textLight,
    );
  }

  /// Ardósia da barra de composição (mais baixa que a do texto).
  static Color ardosiaBarra(BuildContext c) {
    return ardosia(c).withValues(alpha: escuro(c) ? 0.42 : 0.45);
  }

  static Color azul(BuildContext c) {
    return sdrTintaLegivel(
      c,
      escuro(c) ? AppColors.status.infoDarkMode : AppColors.status.info,
    );
  }

  /// Destrutivo e erro — o vermelho de erro da casa.
  static Color vermelho(BuildContext c) {
    return sdrTintaLegivel(
      c,
      escuro(c) ? AppColors.status.errorDarkMode : AppColors.status.error,
    );
  }

  static Color daSituacao(BuildContext c, SdrSituation s) {
    switch (s) {
      case SdrSituation.roleta:
        return verde(c);
      case SdrSituation.folga:
        return ambar(c);
      case SdrSituation.pausado:
        return ardosia(c);
    }
  }

  // ─── Neutros ─────────────────────────────────────────────────────────────

  static Color texto(BuildContext c) => ThemeHelpers.textColor(c);

  static Color textoSecundario(BuildContext c) {
    return ThemeHelpers.textSecondaryColor(c);
  }

  /// Chapa dos cartões e da folha (sheet).
  static Color painel(BuildContext c) => ThemeHelpers.cardBackgroundColor(c);

  /// Banda: placa de instrumento, rodapé da folha.
  static Color banda(BuildContext c) {
    return escuro(c)
        ? AppColors.background.backgroundSecondaryDarkMode
        : AppColors.background.backgroundSecondary;
  }

  /// Poço: trilho da barra de composição, trilho da chave desligada.
  static Color poco(BuildContext c) {
    return escuro(c)
        ? AppColors.background.backgroundDarkMode
        : AppColors.background.backgroundTertiary;
  }

  /// Chapa neutra: avatar de iniciais, botão Voltar.
  static Color chapa(BuildContext c) {
    return escuro(c)
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
  }

  /// Campo preenchido (datas e motivo da folga): afundado no painel.
  static Color campo(BuildContext c) => poco(c);

  /// Busca no estilo da caixa do WhatsApp (fill sólido, sem borda).
  static Color campoDeBusca(BuildContext c) => chapa(c);

  static Color fio(BuildContext c) {
    return escuro(c)
        ? Colors.white.withValues(alpha: 0.08)
        : ThemeHelpers.borderLightColor(c);
  }

  static Color fioForte(BuildContext c) {
    return escuro(c)
        ? Colors.white.withValues(alpha: 0.16)
        : ThemeHelpers.borderColor(c);
  }

  /// No branco a borda É a separação; no escuro o fio basta.
  static Color bordaDoCartao(BuildContext c) {
    return escuro(c) ? fio(c) : ThemeHelpers.borderColor(c);
  }

  /// Claro: só o crisp de 1px da casa. Escuro: sem sombra (chapado).
  static List<BoxShadow>? sombraDoCartao(BuildContext c) {
    return escuro(c) ? null : ThemeHelpers.cardShadow(c);
  }

  /// Fundo translúcido do cabeçalho de seção preso no topo.
  static Color vidro(BuildContext c) {
    return ThemeHelpers.backgroundColor(c).withValues(
      alpha: escuro(c) ? 0.86 : 0.92,
    );
  }
}

/// Tom do aviso rápido — a cor diz o que houve.
enum RoletaTom { sucesso, aviso, erro }

/// Aviso rápido da roleta (o toast do web): ícone e fio na cor do tom sobre a
/// chapa do SnackBar da casa.
void mostrarAvisoDaRoleta(BuildContext context, String texto, RoletaTom tom) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final (Color cor, IconData icone) = switch (tom) {
    RoletaTom.sucesso => (RoletaTinta.verde(context), LucideIcons.circleCheck),
    RoletaTom.aviso => (RoletaTinta.ambar(context), LucideIcons.triangleAlert),
    RoletaTom.erro => (RoletaTinta.vermelho(context), LucideIcons.circleAlert),
  };
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: Duration(seconds: tom == RoletaTom.erro ? 5 : 3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: cor.withValues(alpha: 0.55), width: 1.1),
        ),
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icone, size: 18, color: cor),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(texto)),
          ],
        ),
      ),
    );
}
