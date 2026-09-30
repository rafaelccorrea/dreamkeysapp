/// Kit das peças da ficha do imóvel (prefixo `Pdk` = property details kit),
/// usado pelas seções e folhas de `widgets/details/`: tintas legíveis por
/// token, moldura das folhas (teto 0,88 acima do teclado, rolagem única,
/// rodapé que desce para a rolagem em tela baixa), par de botões que empilha
/// em 320dp/130%, rótulo que encolhe em vez de cortar, linha de escolha,
/// aviso de erro com a causa e trava com o motivo. Só apresentação: nenhuma
/// regra de negócio mora aqui.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/api_service.dart';
import '../../../../shared/utils/error_cause.dart';

/// Motivo único para as ações travadas de imóvel EXCLUÍDO (soft delete): no
/// web a ficha excluída abre só para consulta, sem nenhuma ação de escrita.
const String kPropertyDeletedReadOnlyReason =
    'Imóvel excluído — a ficha fica só para consulta.';

// ─── Tintas ─────────────────────────────────────────────────────────────────

const double _kContrasteMinimo = 4.5;

final Map<(int, bool), Color> _inkCache = <(int, bool), Color>{};

/// Tinta de TEXTO (e ícone pequeno) legível a partir de um tom de status.
///
/// No claro os tons de status ficam perto de 3:1 no branco; aqui o token é
/// misturado com a cor de texto do tema só até passar de 4,5:1 sobre o fill
/// terciário (logo também no branco). Mesmo matiz, sem hex novo; no escuro os
/// tokens já passam e voltam como vieram. É a mesma conta do
/// `sdrTintaLegivel`/`visitInk` da casa.
Color pdkInk(BuildContext context, Color tone) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return _inkCache.putIfAbsent((tone.toARGB32(), dark), () {
    final fundo = dark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    final texto = ThemeHelpers.textColor(context);
    for (var passo = 0; passo <= 50; passo++) {
      final c = Color.lerp(tone, texto, passo / 50)!;
      if (_contraste(c, fundo) >= _kContrasteMinimo) return c;
    }
    return texto;
  });
}

/// Fundo CHEIO que leva rótulo branco (botão de confirmar/destrutivo): o tom
/// escurecido até o branco passar de 4,5:1 — igual nos dois temas (o verde de
/// status com branco dava 3:1 no claro e 2:1 no escuro). Mesma conta do
/// `siteSolid`.
Color pdkSolid(Color tone) {
  var ink = tone == AppColors.status.warning
      ? AppColors.message.warningText
      : tone;
  for (var i = 0; i < 12 && _contrasteNoBranco(ink) < 4.6; i++) {
    ink = Color.lerp(ink, AppColors.text.text, 0.14)!;
  }
  return ink;
}

double _contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final claro = la > lb ? la : lb;
  final escuro = la > lb ? lb : la;
  return (claro + 0.05) / (escuro + 0.05);
}

double _contrasteNoBranco(Color color) =>
    1.05 / (color.computeLuminance() + 0.05);

/// Tons de significado resolvidos pelo tema (token cru — para fundo, filete e
/// anel; para texto e ícone pequeno passe por [pdkInk]).
class PdkTone {
  const PdkTone._();

  static bool _dark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Confirmar, disponível, WhatsApp.
  static Color green(BuildContext context) => _dark(context)
      ? AppColors.status.greenDarkMode
      : AppColors.status.green;

  /// Destrutivo, recusa, desativação.
  static Color red(BuildContext context) => _dark(context)
      ? AppColors.status.errorDarkMode
      : AppColors.status.error;

  /// Espera, atenção.
  static Color amber(BuildContext context) => _dark(context)
      ? AppColors.status.warningDarkMode
      : AppColors.message.warningText;

  /// Comunicação (ligar), venda.
  static Color blue(BuildContext context) => _dark(context)
      ? AppColors.status.infoDarkMode
      : AppColors.message.infoText;

  /// Permissão, cadeado.
  static Color violet(BuildContext context) => _dark(context)
      ? AppColors.status.purpleDarkMode
      : AppColors.status.purple;
}

/// Escala do texto do aparelho (1,0 a 1,6) — larguras mínimas crescem junto,
/// para "caber" valer também com fonte grande.
double pdkTextScale(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6).toDouble();

// ─── Datas e falhas ─────────────────────────────────────────────────────────

/// Data ISO → "12/09/2026 · 14:32" no fuso do aparelho (o mesmo formato do
/// web). `null` quando vazia ou inválida — a tela simplesmente não mostra.
String? pdkStamp(String? iso) {
  final v = iso?.trim() ?? '';
  if (v.isEmpty) return null;
  final parsed = DateTime.tryParse(v);
  if (parsed == null) return null;
  final local = parsed.toLocal();
  return '${DateFormat('dd/MM/yyyy').format(local)} · '
      '${DateFormat('HH:mm').format(local)}';
}

/// `true` quando o servidor aplicou a operação — inclusive no 2xx cujo corpo
/// o app não conseguiu ler (a mudança aconteceu; quem abriu recarrega a
/// ficha).
bool pdkApplied(ApiResponse<dynamic> response) =>
    response.success ||
    (response.statusCode >= 200 && response.statusCode < 300);

/// Diagnóstico de uma falha para a tela, sem exceção crua: a mensagem do
/// servidor segue quando é específica; o "Erro de conexão: <exceção>" montado
/// pelos serviços vira a explicação da família (sem resposta do servidor).
ErrorCause pdkFailureCause(ApiResponse<dynamic> response, {String? message}) {
  var raw = (message ?? response.message ?? '').trim();
  if (raw.startsWith('Erro de conexão') ||
      raw.startsWith('Erro ao processar dados')) {
    raw = '';
  }
  return ErrorCause.fromApi(
    message: raw.isEmpty ? null : raw,
    statusCode: response.statusCode,
  );
}

// ─── Avisos e contato ───────────────────────────────────────────────────────

/// Tom do aviso rápido.
enum PdkSnackTone { success, error, info }

/// Aviso no cartão do tema com ícone de significado (o mesmo desenho do
/// `siteShowSnack`: fundo saturado com texto escuro não lia). Chame com um
/// `context` montado — o da página, depois que a folha fechou.
void pdkShowSnack(
  BuildContext context,
  String message, {
  PdkSnackTone tone = PdkSnackTone.info,
}) {
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final IconData icon;
  final Color color;
  switch (tone) {
    case PdkSnackTone.success:
      icon = LucideIcons.circleCheckBig;
      color = pdkInk(context, PdkTone.green(context));
    case PdkSnackTone.error:
      icon = LucideIcons.circleAlert;
      color = pdkInk(context, PdkTone.red(context));
    case PdkSnackTone.info:
      icon = LucideIcons.info;
      color = ThemeHelpers.textSecondaryColor(context);
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 19, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

/// Abre o aplicativo de e-mail já endereçado. Falha vira aviso em português.
Future<void> pdkOpenEmail(BuildContext context, String email) async {
  final to = email.trim();
  if (to.isEmpty) return;
  var opened = false;
  try {
    opened = await launchUrl(Uri(scheme: 'mailto', path: to));
  } catch (_) {
    opened = false;
  }
  if (!opened && context.mounted) {
    pdkShowSnack(
      context,
      'Não foi possível abrir o aplicativo de e-mail.',
      tone: PdkSnackTone.error,
    );
  }
}

// ─── Folhas ─────────────────────────────────────────────────────────────────

/// Resultado de uma folha que grava no servidor. Guarda o pedido em voo: se a
/// folha for fechada no meio (voltar do sistema), quem abriu ainda espera o
/// pedido terminar e sabe se algo mudou.
class PdkSheetOutcome {
  PdkSheetOutcome();

  /// O servidor aplicou a mudança.
  bool changed = false;

  /// Frase de sucesso para o aviso depois que a folha fecha.
  String? message;

  /// Pedido em andamento (se houver).
  Future<void>? inFlight;

  /// Espera o pedido em voo (sem propagar erro).
  Future<void> settle() async {
    final pending = inFlight;
    if (pending == null) return;
    try {
      await pending;
    } catch (_) {}
  }
}

/// Abre uma folha da ficha com o comportamento da casa: controle de
/// rolagem, área segura no topo, fundo transparente (a [PdkSheetFrame]
/// desenha o cartão) e véu escuro.
Future<T?> showPdkSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: builder,
  );
}

/// Moldura das folhas da ficha: pegador + cabeçalho da casa (selo, título à
/// esquerda, fechar à direita, filete), corpo rolável e rodapé fixo.
///
/// Responsividade: teto de 0,88 da altura ACIMA do teclado; o corpo é o único
/// trecho que rola; com pouca altura (paisagem, teclado aberto) a frase do
/// cabeçalho some e o rodapé desce para o fim da rolagem — só o último filho
/// muda, então o campo em edição não perde o foco.
class PdkSheetFrame extends StatelessWidget {
  const PdkSheetFrame({
    super.key,
    required this.icon,
    required this.tone,
    required this.title,
    this.subtitle,
    required this.body,
    this.footer,
    this.onClose,
  });

  /// Ícone do selo do cabeçalho.
  final IconData icon;

  /// Tom do selo (token cru; o ícone passa por [pdkInk]).
  final Color tone;

  final String title;

  /// Frase de apoio sob o título (some em tela baixa).
  final String? subtitle;

  /// Conteúdo rolável (já com o próprio respiro lateral).
  final Widget body;

  /// Rodapé com as ações (a moldura põe o filete e a área segura).
  final Widget? footer;

  /// Fechar do cabeçalho; `null` desativa (ex.: enquanto grava).
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    final room = mq.size.height - keyboard;
    final maxHeight = math.max(0.0, room * 0.88);
    final footerInScroll = room < 420;
    final compactHeader = room < 520;
    final footerBox = footer == null
        ? null
        : Container(
            padding: EdgeInsets.fromLTRB(18, 12, 18, 14 + mq.padding.bottom),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: ThemeHelpers.borderLightColor(context)),
              ),
            ),
            child: footer,
          );

    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboard),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Container(
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(22),
            ),
            border: Border.all(color: ThemeHelpers.borderLightColor(context)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, compact: compactHeader),
              Flexible(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      body,
                      if (footerInScroll && footerBox != null) footerBox,
                    ],
                  ),
                ),
              ),
              if (!footerInScroll && footerBox != null) footerBox,
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, {required bool compact}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sub = subtitle?.trim() ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 8, bottom: 8),
            decoration: BoxDecoration(
              color: ThemeHelpers.borderColor(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 2, 12, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: tone.withValues(alpha: isDark ? 0.18 : 0.1),
                  border: Border.all(color: tone.withValues(alpha: 0.3)),
                ),
                child: Icon(icon, color: pdkInk(context, tone), size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: ThemeHelpers.textColor(context),
                          letterSpacing: -0.3,
                          height: 1.2,
                        ),
                      ),
                      if (!compact && sub.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          sub,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PdkCloseButton(onTap: onClose),
            ],
          ),
        ),
        Container(height: 1, color: ThemeHelpers.borderLightColor(context)),
      ],
    );
  }
}

/// Fechar do cabeçalho — quadrado neutro com filete (nunca vermelho).
class PdkCloseButton extends StatelessWidget {
  const PdkCloseButton({super.key, this.onTap});

  /// `null` = desativado.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(color: ThemeHelpers.borderLightColor(context)),
    );
    final color = ThemeHelpers.textSecondaryColor(context);
    return Tooltip(
      message: 'Fechar',
      child: Material(
        color: Colors.transparent,
        shape: shape,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(
              LucideIcons.x,
              size: 17,
              color: onTap == null ? color.withValues(alpha: 0.4) : color,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Botões ─────────────────────────────────────────────────────────────────

/// Rótulo de botão que encolhe em vez de cortar (320dp com fonte 130%).
class PdkButtonLabel extends StatelessWidget {
  const PdkButtonLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.1,
        ),
      ),
    );
  }
}

/// Par de botões — o secundário (Cancelar, Ver fila) à esquerda e o principal
/// à direita. Quando algum ficaria estreito demais para o rótulo (320dp, fonte
/// grande), empilham: o principal em cima, na largura inteira.
class PdkActionPair extends StatelessWidget {
  const PdkActionPair({
    super.key,
    required this.primary,
    required this.secondary,
    this.primaryFlex = 1,
    this.minPrimary = 150,
    this.minSecondary = 110,
  });

  final Widget primary;
  final Widget secondary;
  final int primaryFlex;
  final double minPrimary;
  final double minSecondary;

  @override
  Widget build(BuildContext context) {
    final scale = pdkTextScale(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final share = (constraints.maxWidth - gap) / (primaryFlex + 1);
        final fits = constraints.maxWidth.isFinite &&
            share >= minSecondary * scale &&
            share * primaryFlex >= minPrimary * scale;
        if (!fits) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [primary, const SizedBox(height: 8), secondary],
          );
        }
        return Row(
          children: [
            Expanded(child: secondary),
            const SizedBox(width: gap),
            Expanded(flex: primaryFlex, child: primary),
          ],
        );
      },
    );
  }
}

/// Botão neutro de contorno (Cancelar, Fechar, Ver fila) — o tema pintaria de
/// vermelho.
class PdkNeutralButton extends StatelessWidget {
  const PdkNeutralButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.trailingIcon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Ícone depois do rótulo (ex.: seta de "ir").
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: secondary,
        side: BorderSide(color: ThemeHelpers.borderColor(context)),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16),
            const SizedBox(width: 7),
          ],
          Flexible(child: PdkButtonLabel(label)),
          if (trailingIcon != null) ...[
            const SizedBox(width: 4),
            Icon(trailingIcon, size: 16),
          ],
        ],
      ),
    );
  }
}

/// Botão CHEIO com rótulo branco no tom dado (verde de confirmar, vermelho
/// destrutivo). O fundo passa por [pdkSolid]; com [busy] mostra o progresso
/// no lugar do ícone e fica desativado.
class PdkSolidButton extends StatelessWidget {
  const PdkSolidButton({
    super.key,
    required this.label,
    required this.tone,
    this.onPressed,
    this.icon,
    this.busy = false,
  });

  final String label;
  final Color tone;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final fill = pdkSolid(tone);
    return FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: fill,
        foregroundColor: Colors.white,
        disabledBackgroundColor: fill.withValues(alpha: busy ? 0.72 : 0.38),
        disabledForegroundColor: Colors.white.withValues(alpha: 0.9),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy) ...[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
          ] else if (icon != null) ...[
            Icon(icon, size: 17),
            const SizedBox(width: 7),
          ],
          Flexible(child: PdkButtonLabel(label)),
        ],
      ),
    );
  }
}

/// Ação de contato rotulada no próprio item ("Ligar", "WhatsApp", "E-mail"):
/// fundo tonal, ícone e rótulo na tinta legível, alvo de 40dp.
class PdkContactChip extends StatelessWidget {
  const PdkContactChip({
    super.key,
    required this.icon,
    required this.label,
    required this.tone,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = pdkInk(context, tone);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(color: tone.withValues(alpha: 0.32)),
    );
    return Material(
      color: tone.withValues(alpha: isDark ? 0.16 : 0.09),
      shape: shape,
      child: InkWell(
        onTap: onTap,
        customBorder: shape,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: ink),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ink,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.05,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ação só de ícone (40dp, dica no toque longo): tonal quando tem [tone],
/// neutra com filete quando não tem (ex.: Copiar).
class PdkIconAction extends StatelessWidget {
  const PdkIconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.tone,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final t = tone;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(
        color: t == null
            ? ThemeHelpers.borderLightColor(context)
            : t.withValues(alpha: 0.32),
      ),
    );
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        onTap: onTap,
        excludeSemantics: true,
        child: Material(
          color: t == null
              ? Colors.transparent
              : t.withValues(alpha: isDark ? 0.16 : 0.09),
          shape: shape,
          child: InkWell(
            onTap: onTap,
            customBorder: shape,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(
                icon,
                size: 17,
                color: t == null
                    ? ThemeHelpers.textSecondaryColor(context)
                    : pdkInk(context, t),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Blocos de conteúdo ─────────────────────────────────────────────────────

/// Cabeçalho de bloco dentro da folha ("Novo status", "Escopo") com dica
/// opcional embaixo.
class PdkBlockLabel extends StatelessWidget {
  const PdkBlockLabel(
    this.text, {
    super.key,
    this.hint,
    this.mandatory = false,
  });

  final String text;
  final String? hint;

  /// Marca de obrigatório (asterisco vermelho).
  final bool mandatory;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final hintText = hint?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            text: text,
            children: [
              if (mandatory)
                TextSpan(
                  text: ' *',
                  style: TextStyle(color: pdkInk(context, PdkTone.red(context))),
                ),
            ],
          ),
          style: TextStyle(
            color: ThemeHelpers.textColor(context),
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.1,
          ),
        ),
        if (hintText.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            hintText,
            style: TextStyle(color: secondary, fontSize: 12, height: 1.35),
          ),
        ],
      ],
    );
  }
}

/// Linha de escolha (rádio) das folhas: selo com o ícone no tom, título,
/// descrição do efeito real, etiqueta opcional ("Próxima etapa") e marca de
/// seleção. Com [lockedReason] fica travada: cadeado no lugar da marca e o
/// motivo no lugar da descrição (legível, não apagado).
class PdkChoiceRow extends StatelessWidget {
  const PdkChoiceRow({
    super.key,
    required this.icon,
    required this.tone,
    required this.title,
    required this.selected,
    this.description,
    this.badge,
    this.lockedReason,
    this.onTap,
  });

  final IconData icon;
  final Color tone;
  final String title;
  final bool selected;
  final String? description;
  final String? badge;
  final String? lockedReason;

  /// `null` = desativada (sem reação ao toque).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locked = (lockedReason ?? '').trim().isNotEmpty;
    final active = selected && !locked;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final ink = pdkInk(context, tone);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(
        color: active ? tone : ThemeHelpers.borderLightColor(context),
        width: active ? 1.4 : 1,
      ),
    );
    final desc = locked ? lockedReason!.trim() : (description?.trim() ?? '');
    final badgeText = badge?.trim() ?? '';

    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: active,
      enabled: !locked && onTap != null,
      button: true,
      child: Material(
        color: active
            ? tone.withValues(alpha: isDark ? 0.14 : 0.07)
            : Colors.transparent,
        shape: shape,
        child: InkWell(
          onTap: locked ? null : onTap,
          customBorder: shape,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Opacity(
                  opacity: locked ? 0.45 : 1,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: isDark ? 0.2 : 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 18, color: ink),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              color: locked
                                  ? secondary
                                  : ThemeHelpers.textColor(context),
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                              letterSpacing: -0.1,
                            ),
                          ),
                          if (badgeText.isNotEmpty && !locked)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: tone.withValues(
                                  alpha: isDark ? 0.2 : 0.1,
                                ),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                badgeText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: ink,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (desc.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          desc,
                          style: TextStyle(
                            color: secondary,
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: locked
                      ? Icon(
                          LucideIcons.lock,
                          size: 18,
                          color: pdkInk(context, PdkTone.violet(context)),
                        )
                      : _RadioMark(selected: active, tone: tone),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RadioMark extends StatelessWidget {
  const _RadioMark({required this.selected, required this.tone});

  final bool selected;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? tone : ThemeHelpers.borderColor(context),
          width: 2,
        ),
      ),
      alignment: Alignment.center,
      child: selected
          ? Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
            )
          : null,
    );
  }
}

/// Aviso tonal curto (ícone + texto) — informação, não erro.
class PdkNote extends StatelessWidget {
  const PdkNote({
    super.key,
    required this.icon,
    required this.tone,
    required this.text,
  });

  final IconData icon;
  final Color tone;
  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 16, color: pdkInk(context, tone)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Falha dita com a causa: o que não deu certo ([title]), por quê e o que
/// fazer — sem exceção crua. Tom pelo tipo do erro (permissão violeta,
/// conexão âmbar, demais vermelho).
class PdkErrorNote extends StatelessWidget {
  const PdkErrorNote({super.key, required this.title, required this.cause});

  final String title;
  final ErrorCause cause;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color tone;
    switch (cause.kind) {
      case ErrorKind.permissao:
        tone = PdkTone.violet(context);
      case ErrorKind.conexao:
      case ErrorKind.limite:
        tone = PdkTone.amber(context);
      default:
        tone = PdkTone.red(context);
    }
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: isDark ? 0.12 : 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tone.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(cause.icon, size: 17, color: pdkInk(context, tone)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: ThemeHelpers.textColor(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    cause.cause,
                    style: TextStyle(
                      color: ThemeHelpers.textColor(context),
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    cause.action,
                    style: TextStyle(
                      color: secondary,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Trava com motivo — cadeado violeta (permissão), o que está travado e o
/// porquê/quem libera. Usada no lugar de esconder a ação.
class PdkLockNote extends StatelessWidget {
  const PdkLockNote({super.key, required this.title, required this.reason});

  final String title;
  final String reason;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final violet = PdkTone.violet(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 13),
      decoration: BoxDecoration(
        color: violet.withValues(alpha: isDark ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: violet.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: violet.withValues(alpha: isDark ? 0.2 : 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              LucideIcons.lockKeyhole,
              size: 18,
              color: pdkInk(context, violet),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: ThemeHelpers.textColor(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  reason,
                  style: TextStyle(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontSize: 12.5,
                    height: 1.4,
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

/// Decoração dos campos das folhas: CHEIO (fill terciário), filete leve que
/// acende no foco com a tinta do [accent], rótulo dentro do campo e erro sob
/// ele (até 2 linhas).
InputDecoration pdkFieldDecoration(
  BuildContext context, {
  required String label,
  String? hint,
  Color? accent,
  String? errorText,
  bool multiline = false,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final secondary = ThemeHelpers.textSecondaryColor(context);
  final focus = accent ?? PdkTone.blue(context);
  final danger = PdkTone.red(context);
  final fill = isDark
      ? AppColors.background.backgroundTertiaryDarkMode
      : AppColors.background.backgroundTertiary;

  OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );

  return InputDecoration(
    labelText: label,
    hintText: hint,
    hintMaxLines: multiline ? 3 : 1,
    alignLabelWithHint: multiline,
    filled: true,
    fillColor: fill,
    counterText: '',
    isDense: false,
    contentPadding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
    labelStyle: TextStyle(
      color: secondary,
      fontWeight: FontWeight.w600,
      fontSize: 13,
    ),
    floatingLabelStyle: TextStyle(
      color: errorText != null ? pdkInk(context, danger) : pdkInk(context, focus),
      fontWeight: FontWeight.w700,
      fontSize: 13,
    ),
    hintStyle: TextStyle(
      color: secondary.withValues(alpha: 0.72),
      fontWeight: FontWeight.w500,
      fontSize: 13,
    ),
    errorText: errorText,
    errorMaxLines: 2,
    errorStyle: TextStyle(
      color: pdkInk(context, danger),
      fontSize: 12,
      fontWeight: FontWeight.w600,
    ),
    border: border(ThemeHelpers.borderLightColor(context), 1),
    enabledBorder: border(ThemeHelpers.borderLightColor(context), 1),
    focusedBorder: border(focus, 1.6),
    errorBorder: border(danger.withValues(alpha: 0.7), 1.2),
    focusedErrorBorder: border(danger, 1.6),
    disabledBorder: border(
      ThemeHelpers.borderLightColor(context).withValues(alpha: 0.6),
      1,
    ),
  );
}

/// Avatar de iniciais (primeira letra do primeiro e do último nome) em chapa
/// tonal sólida — sem gradiente; foto quando houver [imageUrl].
class PdkInitialsAvatar extends StatelessWidget {
  const PdkInitialsAvatar({
    super.key,
    required this.name,
    required this.tone,
    this.imageUrl,
    this.size = 40,
  });

  final String name;
  final Color tone;
  final String? imageUrl;
  final double size;

  static String initialsOf(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final url = imageUrl?.trim() ?? '';
    final initials = Text(
      initialsOf(name),
      maxLines: 1,
      style: TextStyle(
        color: pdkInk(context, tone),
        fontSize: size * 0.36,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.2,
      ),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tone.withValues(alpha: isDark ? 0.22 : 0.13),
        border: Border.all(color: tone.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: url.isEmpty
          ? FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(padding: const EdgeInsets.all(4), child: initials),
            )
          : Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, error, stack) => FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: initials,
                ),
              ),
            ),
    );
  }
}
