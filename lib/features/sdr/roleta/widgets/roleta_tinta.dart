import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../models/sdr_roulette_rules.dart';

/// Tinta da Roleta de SDRs — a régua aprovada no web ("ficou PERFEITO",
/// 21/09/2026). Cor só com significado, a mesma em toda a tela:
///   · verde WhatsApp — NA ROLETA (recebe conversa) e a ação principal;
///   · âmbar          — FOLGA: pausa com prazo, em curso ou marcada;
///   · ardósia        — PAUSADO à mão (não é perigo: é estar fora);
///   · azul info      — LOCAÇÃO, o mesmo azul do selo Locação da lista;
///   · rosa           — só o destrutivo (cancelar a folga marcada).
/// Neutros grafite no escuro (#111116/#15151B/#0C0C11/#1C1C23, nunca
/// navy); no claro, papel branco com fio (ThemeHelpers/AppColors).
class RoletaTinta {
  RoletaTinta._();

  static bool escuro(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  // ─── Significado ─────────────────────────────────────────────────────────

  static Color verde(BuildContext c) {
    return escuro(c) ? const Color(0xFF25D366) : const Color(0xFF128C7E);
  }

  /// Tinta sobre o verde: branco no claro; no escuro o verde é vivo demais
  /// para texto branco (mesma escolha do web).
  static Color tintaSobreVerde(BuildContext c) {
    return escuro(c) ? const Color(0xFF06210F) : Colors.white;
  }

  static Color ambar(BuildContext c) {
    return escuro(c) ? const Color(0xFFF59E0B) : const Color(0xFFB45309);
  }

  static Color ardosia(BuildContext c) {
    return escuro(c) ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  }

  /// Ardósia da barra de composição (mais baixa que a do texto).
  static Color ardosiaBarra(BuildContext c) {
    return escuro(c) ? const Color(0xFF34343F) : const Color(0xFFD5DAE1);
  }

  static Color azul(BuildContext c) {
    return escuro(c) ? AppColors.status.infoDarkMode : AppColors.status.info;
  }

  static Color rosa(BuildContext c) {
    return escuro(c) ? const Color(0xFFFB7185) : const Color(0xFFE11D48);
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
  static Color painel(BuildContext c) {
    return escuro(c)
        ? const Color(0xFF111116)
        : AppColors.background.cardBackground;
  }

  /// Banda: placa de instrumento, rodapé da folha.
  static Color banda(BuildContext c) {
    return escuro(c) ? const Color(0xFF15151B) : const Color(0xFFF7F7F9);
  }

  /// Poço: trilho da barra de composição, trilho da chave desligada.
  static Color poco(BuildContext c) {
    return escuro(c)
        ? const Color(0xFF0C0C11)
        : AppColors.background.backgroundSecondary;
  }

  /// Chapa neutra: avatar de iniciais, botão Voltar.
  static Color chapa(BuildContext c) {
    return escuro(c)
        ? const Color(0xFF1C1C23)
        : AppColors.background.backgroundTertiary;
  }

  /// Campo preenchido (datas e motivo da folga).
  static Color campo(BuildContext c) {
    return escuro(c)
        ? const Color(0xFF0C0C11)
        : AppColors.background.backgroundTertiary;
  }

  /// Busca no estilo da caixa do WhatsApp (fill translúcido, sem borda).
  static Color campoDeBusca(BuildContext c) {
    return escuro(c)
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFF767680).withValues(alpha: 0.14);
  }

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

  /// No branco a borda É a separação; no grafite o fio basta.
  static Color bordaDoCartao(BuildContext c) {
    return escuro(c) ? fio(c) : ThemeHelpers.borderColor(c);
  }

  /// Claro: só o crisp de 1px da casa. Escuro: sem sombra (chapado).
  static List<BoxShadow>? sombraDoCartao(BuildContext c) {
    return escuro(c) ? null : ThemeHelpers.cardShadow(c);
  }

  /// Fundo translúcido do cabeçalho de seção preso no topo.
  static Color vidro(BuildContext c) {
    return escuro(c)
        ? const Color(0xFF0A0A0F).withValues(alpha: 0.82)
        : Colors.white.withValues(alpha: 0.9);
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
    RoletaTom.erro => (RoletaTinta.rosa(context), LucideIcons.circleAlert),
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
