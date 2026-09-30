import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../models/bio_page_model.dart';

/// Widgets compartilhados entre **Meu Site** e **Link in Bio** — mesma
/// gramática flush das telas de referência (abas com sublinhado, cabeçalho
/// de painel com barra de acento, estados vazio/erro com retry).
///
/// Revisão 30/09/2026: cores de texto passam por [siteInk] (contraste AA no
/// claro), campos usam o fill terciário do app, e nada aqui pode estourar em
/// 320dp com texto a 130% — ver o comentário de cada peça.
///
/// Peças novas da revisão do Meu Site (30/09): [siteShowSnack] (aviso no
/// cartão do tema com ícone de significado), [SiteStep] (roteiro numerado com
/// trilho), [SiteCheckRow] (linha do "o que falta"), [SiteSwatchTile]
/// (amostra de cor em caixa fixa); [SiteSaveBar.docked] (barra fixa no pé),
/// [SiteSubsectionHeader.hint]/[SiteSubsectionHeader.trailing],
/// [SiteFilledField.helperText] e [SiteReadOnlyNotice.dense].

/// Converte cor hex vinda do backend ("#RRGGBB", "RGB" ou "#AARRGGBB") em
/// [Color]. Retorna `null` para valores ausentes/inválidos — quem chama
/// decide o fallback (em geral a cor da marca do app).
Color? siteParseHexColor(String? raw) {
  var hex = raw?.trim() ?? '';
  if (hex.isEmpty) return null;
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.length == 3) {
    hex = hex.split('').map((c) => '$c$c').join();
  }
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  final value = int.tryParse(hex, radix: 16);
  return value == null ? null : Color(value);
}

/// Tinta de TEXTO e de ÍCONE para um tom de status ou de acento.
///
/// No modo claro, os tons de status leem fraco sobre o branco (o âmbar
/// `#E6B84C` dá 1,9:1 — "Rascunho" quase some). Aqui o tom é escurecido na
/// direção do texto principal até passar de 4,5:1: o mesmo matiz, legível.
/// O âmbar parte do `warningText` (laranja queimado), que escurece bonito em
/// vez de virar oliva. No escuro, os tons `*DarkMode` já leem bem sobre o
/// grafite e voltam como vieram. Fundos e bordas seguem com o tom cru.
Color siteInk(BuildContext context, Color tone) {
  if (Theme.of(context).brightness == Brightness.dark) return tone;
  return _darkenForWhite(tone);
}

/// Fundo CHEIO que leva rótulo branco (botão de ação no tom da tela): o
/// mesmo tom escurecido até o branco passar de 4,5:1 — igual nos dois
/// temas. O verde de status com texto branco dava 3:1 no claro e 2:1 no
/// escuro (o `*DarkMode` é mais claro), e o `onPrimary` do tema escuro
/// ainda pintaria o rótulo de preto.
Color siteSolid(Color tone) => _darkenForWhite(tone);

Color _darkenForWhite(Color tone) {
  var ink = tone == AppColors.status.warning
      ? AppColors.message.warningText
      : tone;
  for (var i = 0; i < 12 && _contrastOnWhite(ink) < 4.6; i++) {
    ink = Color.lerp(ink, AppColors.text.text, 0.14)!;
  }
  return ink;
}

double _contrastOnWhite(Color color) =>
    1.05 / (color.computeLuminance() + 0.05);

/// Texto legível SOBRE uma cor vinda do cliente (cor da marca do site, cor
/// custom de um botão da bio): branco nos tons escuros, o texto principal
/// do app nos claros.
Color siteOnColor(Color background) =>
    ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Colors.white
        : AppColors.text.text;

/// Fill dos campos e controles "cheios" — o cinza terciário sólido do app
/// (claro `#EEF0F3` sobre o branco; escuro `#1A1A2A` sobre o grafite).
Color siteFieldFill(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;

/// Filete que contorna grupos (claro `#D6DAE1`; no escuro o `borderLight`,
/// que ainda aparece sobre o card grafite). Entre linhas flush use o
/// `borderLightColor`, um degrau mais leve.
Color siteHairline(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? ThemeHelpers.borderLightColor(context)
        : ThemeHelpers.borderColor(context);

/// Texto de aviso (snackbar) para uma ação que falhou: a causa em português
/// do dia a dia, nunca a exceção crua que o service monta ("Erro de
/// conexão: SocketException…"). A frase do back vale quando é de gente
/// ("Este domínio já está em uso"); conexão, sessão, permissão e servidor
/// têm frase própria.
String siteFailureMessage(
  String? message,
  int statusCode, {
  required String fallback,
}) {
  if (statusCode == 0) {
    return 'Não foi possível falar com o servidor — confira a internet e '
        'tente de novo.';
  }
  if (statusCode == 401) return 'Sua sessão expirou — entre novamente.';
  if (statusCode == 403) {
    return 'Seu usuário não tem permissão para isso — peça ao administrador.';
  }
  if (statusCode >= 500) {
    return 'O servidor falhou ao processar o pedido — tente de novo em '
        'instantes.';
  }
  final raw = (message ?? '').trim();
  final technical =
      raw.isEmpty ||
      raw.contains('Exception') ||
      raw.contains('Error') ||
      raw.startsWith('Erro de conexão');
  return technical ? fallback : raw;
}

/// Tom do aviso rápido: o ÍCONE diz se deu certo, se falhou ou se é só
/// informação. O texto segue na cor do tema — o snackbar do app é o cartão
/// do tema, e texto verde/vermelho sobre ele cairia para ~3:1 no claro.
enum SiteSnackTone { info, success, error }

/// Aviso rápido no cartão do tema com ícone de significado. Troca o aviso
/// anterior em vez de enfileirar (copiar três vezes não deixa três avisos na
/// fila); o texto quebra em quantas linhas precisar.
void siteShowSnack(
  BuildContext context,
  String message, {
  SiteSnackTone tone = SiteSnackTone.info,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final IconData icon;
  final Color color;
  if (tone == SiteSnackTone.success) {
    icon = LucideIcons.circleCheckBig;
    color = siteInk(
      context,
      isDark ? AppColors.status.greenDarkMode : AppColors.status.green,
    );
  } else if (tone == SiteSnackTone.error) {
    icon = LucideIcons.circleAlert;
    color = siteInk(
      context,
      isDark ? AppColors.status.errorDarkMode : AppColors.status.error,
    );
  } else {
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

/// Escala do texto do aparelho (1,0 a 1,6) — as larguras mínimas de coluna
/// e de botão crescem junto, para "caber" valer também com fonte grande.
double siteTextScale(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6).toDouble();

/// Ícone do botão da bio — o mesmo que a página pública desenha: o botão de
/// captação tem ícone próprio; o escolhido à mão no painel (Premium) vem
/// antes; sem escolha, é detectado pela URL. Usado na lista, no celular de
/// prévia e na folha de edição.
IconData bioLinkIcon(BioPageLink link) {
  if (link.isLeadForm) return LucideIcons.userRoundPlus;
  switch ((link.icon ?? '').trim()) {
    case 'whatsapp':
      return LucideIcons.messageCircle;
    case 'instagram':
      return LucideIcons.camera;
    case 'facebook':
      return LucideIcons.thumbsUp;
    case 'youtube':
      return LucideIcons.circlePlay;
    case 'tiktok':
      return LucideIcons.music2;
    case 'x':
      return LucideIcons.atSign;
    case 'linkedin':
      return LucideIcons.briefcaseBusiness;
    case 'telegram':
      return LucideIcons.send;
    case 'pinterest':
      return LucideIcons.pin;
    case 'spotify':
      return LucideIcons.music;
    case 'email':
      return LucideIcons.mail;
    case 'phone':
      return LucideIcons.phone;
    case 'maps':
      return LucideIcons.mapPin;
    case 'site':
      return LucideIcons.globe;
  }
  return bioLinkIconForUrl(link.url);
}

/// Detecção pela URL. O Lucide removeu os ícones de marca — usamos
/// equivalentes semânticos.
IconData bioLinkIconForUrl(String url) {
  final u = url.toLowerCase();
  if (u.contains('wa.me') || u.contains('whatsapp')) {
    return LucideIcons.messageCircle;
  }
  if (u.contains('instagram.com')) return LucideIcons.camera;
  if (u.contains('youtube.com') || u.contains('youtu.be')) {
    return LucideIcons.circlePlay;
  }
  if (u.contains('facebook.com') || u.contains('fb.com')) {
    return LucideIcons.thumbsUp;
  }
  if (u.contains('linkedin.com')) return LucideIcons.briefcaseBusiness;
  if (u.contains('tiktok.com')) return LucideIcons.music2;
  if (u.contains('t.me') || u.contains('telegram')) return LucideIcons.send;
  if (u.startsWith('mailto:')) return LucideIcons.mail;
  if (u.startsWith('tel:')) return LucideIcons.phone;
  return LucideIcons.globe;
}

// ─── Aba flush (ícone + rótulo + contagem + sublinhado) ──────────────────────

class SiteFlushTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final int? count;
  final Color tone;
  final bool selected;
  final VoidCallback onTap;

  /// Há alterações não salvas nesta aba — ponto âmbar ESTÁTICO ao lado do
  /// rótulo (sem pulsar), para a pessoa não perder o rascunho ao trocar de
  /// aba.
  final bool dirty;

  const SiteFlushTab({
    super.key,
    required this.icon,
    required this.label,
    this.count,
    required this.tone,
    required this.selected,
    required this.onTap,
    this.dirty = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final ink = siteInk(context, tone);
    final fg = selected ? ink : secondary;
    // Ponto de 7px é sinal gráfico: no claro, o âmbar cru some no branco.
    final amber = siteInk(
      context,
      isDark ? AppColors.status.warningDarkMode : AppColors.status.warning,
    );

    final labelText = Text(
      label,
      maxLines: 1,
      softWrap: false,
      style: theme.textTheme.labelLarge?.copyWith(
        color: fg,
        fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
        letterSpacing: 0.1,
      ),
    );
    final extras = <Widget>[
      if (count != null && count! > 0) ...[
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
          decoration: BoxDecoration(
            color: tone.withValues(alpha: selected ? 0.18 : 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            count! > 99 ? '99+' : '${count!}',
            maxLines: 1,
            style: theme.textTheme.labelSmall?.copyWith(
              color: selected ? ink : secondary,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ),
      ],
      if (dirty) ...[
        const SizedBox(width: 5),
        Tooltip(
          message: 'Alterações não salvas',
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: amber),
          ),
        ),
      ],
    ];

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          splashColor: tone.withValues(alpha: 0.12),
          highlightColor: tone.withValues(alpha: 0.06),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Aba estreita (4 abas em 320dp, 3 abas até ~360dp): ícone em
              // cima do rótulo, como a TabBar do app — o rótulo ganha a
              // largura inteira e não encolhe até ficar ilegível. O FittedBox
              // segue como rede de segurança para texto a 130%.
              final stacked = constraints.maxWidth < 104;
              final content = stacked
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 17, color: fg),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [labelText, ...extras],
                        ),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 16, color: fg),
                        const SizedBox(width: 6),
                        labelText,
                        ...extras,
                      ],
                    );
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: stacked ? 9 : 13,
                    ),
                    child: FittedBox(fit: BoxFit.scaleDown, child: content),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    height: 2.5,
                    decoration: BoxDecoration(
                      color: selected ? tone : Colors.transparent,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(3),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─── Cabeçalho de painel (barra de acento + título + hint) ───────────────────

class SitePanelHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String hint;
  final Color tone;

  const SitePanelHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 3.5,
          height: 34,
          decoration: BoxDecoration(
            color: tone,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  height: 1.32,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            color: tone.withValues(alpha: isDark ? 0.18 : 0.1),
          ),
          child: Icon(icon, color: siteInk(context, tone), size: 17),
        ),
      ],
    );
  }
}

// ─── Sub-seção (rótulo + linha) ──────────────────────────────────────────────

class SiteSubsectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;

  /// Frase curta sob o cabeçalho: para que serve o grupo, em português do
  /// dia a dia ("Por onde o visitante fala com você").
  final String? hint;

  /// Leitura curta à direita do filete (ex.: "3 de 5 prontos"). Fica com no
  /// máximo 30% da linha.
  final Widget? trailing;

  const SiteSubsectionHeader({
    super.key,
    required this.label,
    required this.icon,
    this.hint,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // O rótulo nunca estoura: ocupa no máximo ~70% da linha (50% quando
        // há leitura à direita) e quebra em duas se precisar ("ONDE CRIAR,
        // POR PROVEDOR" a 130% em 320dp); o filete fica com o resto.
        final hasTrailing = trailing != null;
        final maxLabel = constraints.maxWidth * (hasTrailing ? 0.5 : 0.7);
        final row = Row(
          children: [
            Icon(icon, size: 14, color: secondary),
            const SizedBox(width: 7),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxLabel),
              child: Text(
                label.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: secondary,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                  height: 1.3,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 1,
                color: ThemeHelpers.borderLightColor(context),
              ),
            ),
            if (hasTrailing) ...[
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * 0.3,
                ),
                child: trailing!,
              ),
            ],
          ],
        );
        if (hint == null) return row;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row,
            const SizedBox(height: 6),
            Text(
              hint!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Pill compacta ───────────────────────────────────────────────────────────

/// Selo de estado. O rótulo encolhe com reticências em vez de estourar — por
/// isso a pill vai SEMPRE num pai de largura limitada (Wrap, Column,
/// Expanded/Flexible), nunca solta como filho direto de uma Row.
class SiteMiniPill extends StatelessWidget {
  final String label;
  final Color tone;
  final IconData? icon;

  const SiteMiniPill({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = siteInk(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: isDark ? 0.4 : 0.34)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: ink),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ink,
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Linha de informação com ações no próprio item ───────────────────────────

class SiteInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueTone;
  final List<Widget> actions;

  /// Selo ou microlinha sob o valor (ex.: o estado do domínio). Fica DENTRO
  /// da coluna de texto — com o valor longo, desce junto em vez de espremer
  /// as ações da direita.
  final Widget? below;

  /// Valor técnico que a pessoa copia para outro sistema (host, IP): fonte
  /// monoespaçada, para não confundir 0/O e 1/l.
  final bool mono;

  const SiteInfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.valueTone,
    this.actions = const [],
    this.below,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 15, color: secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    fontSize: 9.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: valueTone ?? ThemeHelpers.textColor(context),
                    fontWeight: mono ? FontWeight.w700 : FontWeight.w800,
                    letterSpacing: mono ? 0 : -0.1,
                    fontFamily: mono ? 'monospace' : null,
                    fontFamilyFallback: mono
                        ? const ['Menlo', 'Courier New']
                        : null,
                  ),
                ),
                if (below != null) ...[const SizedBox(height: 6), below!],
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Botão de ação compacto usado dentro de linhas/itens (ações no item).
class SiteRowAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color tone;
  final VoidCallback? onTap;

  const SiteRowAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.tone,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final color = disabled
        ? ThemeHelpers.textSecondaryColor(context).withValues(alpha: 0.4)
        : tone;
    // Ícone na tinta legível (âmbar/azul crus leem fraco no branco); o
    // fundo e o filete seguem o tom cru.
    final iconColor = disabled ? color : siteInk(context, tone);
    return Semantics(
      button: true,
      enabled: !disabled,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        // Material transparente: dentro de um SiteCard (Container com cor), o
        // respingo do toque era pintado no Scaffold, ATRÁS do cartão — o
        // botão não dava retorno visual nenhum.
        child: Material(
          type: MaterialType.transparency,
          child: InkResponse(
            radius: 22,
            onTap: onTap,
            child: Container(
              width: 36,
              height: 36,
              margin: const EdgeInsets.only(left: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                color: color.withValues(alpha: disabled ? 0.06 : 0.1),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Icon(icon, size: 16, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Campo filled (formulários 2 colunas quando couber) ──────────────────────

class SiteFilledField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? icon;
  final int maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final String? prefixText;

  /// Cor de foco/cursor. Quando nula, usa o vermelho da marca (Meu Site).
  /// O Link in Bio passa o violeta da tela — lá o vermelho não entra.
  final Color? accent;

  /// Erro de validação local — pinta o filete e escreve a causa embaixo do
  /// próprio campo (em até duas linhas).
  final String? errorText;

  final TextCapitalization textCapitalization;

  /// Onde o texto aparece / para que serve, sob o campo (até 3 linhas). Some
  /// quando há [errorText] — o erro ocupa o lugar.
  final String? helperText;

  const SiteFilledField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.icon,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.enabled = true,
    this.onChanged,
    this.prefixText,
    this.accent,
    this.errorText,
    this.textCapitalization = TextCapitalization.none,
    this.helperText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final focusTone =
        accent ??
        (isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary);
    final danger = isDark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;
    // Campo CHEIO (padrão do app): o cinza terciário delimita o campo sobre
    // o branco sem depender de sombra; o filete fica leve e acende no foco.
    final fill = siteFieldFill(context);
    final borderColor = ThemeHelpers.borderLightColor(context);

    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color, width: width),
    );

    return TextField(
      controller: controller,
      enabled: enabled,
      maxLines: maxLines,
      minLines: maxLines > 1 ? maxLines : null,
      maxLength: maxLength,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      cursorColor: focusTone,
      onChanged: onChanged,
      style: TextStyle(
        color: ThemeHelpers.textColor(context),
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
        height: maxLines > 1 ? 1.38 : null,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintMaxLines: maxLines > 1 ? maxLines : 1,
        prefixText: prefixText,
        prefixStyle: TextStyle(
          color: secondary,
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
        ),
        counterText: maxLength == null ? null : '',
        alignLabelWithHint: maxLines > 1,
        labelStyle: TextStyle(
          color: secondary,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        floatingLabelStyle: TextStyle(
          color: errorText != null ? danger : siteInk(context, focusTone),
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
        hintStyle: TextStyle(
          color: secondary.withValues(alpha: 0.72),
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
        helperText: helperText,
        helperMaxLines: 3,
        helperStyle: TextStyle(
          color: secondary,
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
          height: 1.3,
        ),
        errorText: errorText,
        errorMaxLines: 2,
        errorStyle: TextStyle(
          color: siteInk(context, danger),
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
        prefixIcon: icon != null
            ? Icon(icon, size: 17, color: secondary)
            : null,
        filled: true,
        fillColor: enabled ? fill : fill.withValues(alpha: 0.6),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        enabledBorder: border(borderColor, 1),
        focusedBorder: border(focusTone.withValues(alpha: 0.7), 1.5),
        disabledBorder: border(borderColor.withValues(alpha: 0.5), 1),
        errorBorder: border(danger.withValues(alpha: 0.75), 1.2),
        focusedErrorBorder: border(danger, 1.5),
      ),
    );
  }
}

// ─── Duas colunas quando couber ──────────────────────────────────────────────

/// Dois campos lado a lado quando cada coluna tem a largura mínima; um
/// embaixo do outro quando não tem. O mínimo cresce com a escala do texto:
/// em 320dp, ou com a fonte a 130%, WhatsApp e Telefone empilham em vez de
/// virarem dois campos de 110dp em que o número rola escondido.
class SiteRow2 extends StatelessWidget {
  final Widget left;
  final Widget right;
  final double minColumnWidth;
  final double gap;

  const SiteRow2({
    super.key,
    required this.left,
    required this.right,
    this.minColumnWidth = 150,
    this.gap = 10,
  });

  @override
  Widget build(BuildContext context) {
    final scale = siteTextScale(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final column = (constraints.maxWidth - gap) / 2;
        final fits =
            constraints.maxWidth.isFinite && column >= minColumnWidth * scale;
        if (!fits) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, SizedBox(height: gap + 2), right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            SizedBox(width: gap),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

// ─── Botões que nunca estouram ───────────────────────────────────────────────

/// Rótulo de botão: uma linha, sem quebra, e ENCOLHE para caber em vez de
/// estourar ("Salvar alterações" ao lado de "Descartar" em 320dp com fonte
/// a 130%). Tamanho e peso fixos, para o par de botões não misturar o 16 do
/// tema do OutlinedButton com o 14 do FilledButton; a cor vem do botão.
class SiteButtonLabel extends StatelessWidget {
  final String text;

  const SiteButtonLabel(this.text, {super.key});

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

/// Par de botões — o secundário (Cancelar, Descartar, Verificar) à esquerda
/// e o principal à direita. Quando algum dos dois ficaria estreito demais
/// para o rótulo (320dp, fonte grande), empilham: o principal em cima, na
/// largura inteira.
class SiteActionPair extends StatelessWidget {
  final Widget primary;
  final Widget secondary;
  final int primaryFlex;
  final double minPrimary;
  final double minSecondary;

  const SiteActionPair({
    super.key,
    required this.primary,
    required this.secondary,
    this.primaryFlex = 1,
    this.minPrimary = 150,
    this.minSecondary = 110,
  });

  @override
  Widget build(BuildContext context) {
    final scale = siteTextScale(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final share = (constraints.maxWidth - gap) / (primaryFlex + 1);
        final fits =
            constraints.maxWidth.isFinite &&
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

// ─── Estados vazio / erro ────────────────────────────────────────────────────

class SiteEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Color tone;
  final Widget? action;

  const SiteEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.tone,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    // Selo tonal SÓLIDO com anel — o mesmo desenho do estado de erro do
    // app (o gradiente de antes era enfeite inventado); ícone na tinta
    // legível. Coluna de no máximo 420 para não esticar no tablet.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 4),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: tone.withValues(alpha: isDark ? 0.18 : 0.10),
                  border: Border.all(color: tone.withValues(alpha: 0.30)),
                ),
                child: Icon(icon, color: siteInk(context, tone), size: 26),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: secondary,
                  height: 1.45,
                ),
              ),
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Estado de erro com retry — delega ao padrão do app.
///
/// [statusCode] é o código HTTP da resposta que falhou; sem ele não dá para
/// separar "sem permissão" de "servidor fora do ar".
class SiteErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final int statusCode;
  final bool dense;

  const SiteErrorState({
    super.key,
    required this.message,
    required this.onRetry,
    this.statusCode = 0,
    this.dense = true,
  });

  @override
  Widget build(BuildContext context) {
    return AppErrorState.fromApi(
      message: message,
      statusCode: statusCode,
      onRetry: () async => onRetry(),
      dense: dense,
    );
  }
}

// ─── Acesso negado ───────────────────────────────────────────────────────────

class SiteDeniedView extends StatelessWidget {
  final String message;
  final String permissionLabel;

  const SiteDeniedView({
    super.key,
    required this.message,
    required this.permissionLabel,
  });

  /// Nome da permissão como aparece para o administrador — nunca o id
  /// técnico (`public_site:view`) na cara de quem não tem acesso.
  String get _permissionName {
    switch (permissionLabel) {
      case 'public_site:view':
        return 'Ver o Meu Site e o Link in Bio';
      case 'public_site:manage':
        return 'Gerenciar o Meu Site e o Link in Bio';
    }
    return permissionLabel;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    // Violeta = família "permissão" do estado de erro do app.
    final violet = isDark
        ? AppColors.status.purpleDarkMode
        : AppColors.status.purple;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: violet.withValues(alpha: isDark ? 0.18 : 0.10),
                  border: Border.all(color: violet.withValues(alpha: 0.30)),
                ),
                child: Icon(
                  LucideIcons.lock,
                  size: 25,
                  color: siteInk(context, violet),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ThemeHelpers.textColor(context),
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Quem libera é o administrador da empresa, na permissão '
                '“$_permissionName”.',
                textAlign: TextAlign.center,
                style: TextStyle(color: secondary, fontSize: 13, height: 1.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Somente leitura ─────────────────────────────────────────────────────────

/// Quem não pode editar vê os campos travados E o porquê — cadeado e quem
/// libera, em português (nunca o id técnico da permissão).
class SiteReadOnlyNotice extends StatelessWidget {
  final String text;

  /// Versão de linha (sem caixa): cadeado + motivo logo abaixo de um botão
  /// travado, sem pesar como um aviso.
  final bool dense;

  const SiteReadOnlyNotice({super.key, required this.text, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final amber = isDark
        ? AppColors.status.warningDarkMode
        : AppColors.status.warning;
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            LucideIcons.lock,
            size: dense ? 13 : 14,
            color: siteInk(context, amber),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: ThemeHelpers.textSecondaryColor(context),
              fontSize: dense ? 11.5 : 12,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
    if (dense) return row;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: amber.withValues(alpha: isDark ? 0.12 : 0.08),
        border: Border.all(color: amber.withValues(alpha: 0.3)),
      ),
      child: row,
    );
  }
}

// ─── Barra de salvar (aparece quando há alterações) ──────────────────────────

class SiteSaveBar extends StatelessWidget {
  final bool visible;
  final bool saving;
  final String label;
  final VoidCallback onSave;
  final VoidCallback? onDiscard;

  /// Frase acima dos botões — diz o estado e a consequência ("o site só
  /// muda depois de salvar"), para ninguém sair achando que já foi.
  final String pendingText;

  /// Barra FIXA no pé da tela: fundo do card, filete em cima, área segura do
  /// aparelho e conteúdo centralizado em [maxContentWidth]. Falso (o padrão)
  /// = a barra de sempre, no fim do painel — é a que vale com pouca altura
  /// útil (paisagem, teclado aberto), onde a fixa espremeria os campos.
  final bool docked;

  /// Largura máxima do conteúdo da barra fixa (tablet), já contando o recuo
  /// de 16 de cada lado — 752 alinha com uma coluna de 720.
  final double maxContentWidth;

  const SiteSaveBar({
    super.key,
    required this.visible,
    required this.saving,
    required this.onSave,
    this.onDiscard,
    this.label = 'Salvar alterações',
    this.pendingText = 'Alterações ainda não salvas.',
    this.docked = false,
    this.maxContentWidth = 752,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    // Salvar = confirmar → verde, escurecido até o rótulo branco passar de
    // 4,5:1 (o verde de status cru dava 3:1 no claro e 2:1 no escuro). O
    // vermelho da marca é identidade, não ação.
    final green = siteSolid(
      isDark ? AppColors.status.greenDarkMode : AppColors.status.green,
    );
    // Ponto ESTÁTICO (sem pulsar), âmbar legível no branco.
    final amber = siteInk(
      context,
      isDark ? AppColors.status.warningDarkMode : AppColors.status.warning,
    );

    final save = FilledButton.icon(
      onPressed: saving ? null : onSave,
      style: FilledButton.styleFrom(
        backgroundColor: green,
        foregroundColor: Colors.white,
        // Salvando: continua verde e o spinner branco segue visível (o
        // desabilitado padrão é cinza claro, onde o branco some).
        disabledBackgroundColor: green.withValues(alpha: 0.6),
        disabledForegroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      ),
      icon: saving
          ? const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(LucideIcons.check, size: 17),
      label: SiteButtonLabel(saving ? 'Salvando…' : label),
    );

    // Descartar é NEUTRO (nunca o vermelho que o tema dá aos botões de
    // texto). [iconOnly] = só o ícone com dica, para a barra fixa estreita.
    Widget discard({required bool iconOnly}) {
      final style = OutlinedButton.styleFrom(
        foregroundColor: secondary,
        side: BorderSide(color: ThemeHelpers.borderColor(context)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: iconOnly
            ? const EdgeInsets.symmetric(horizontal: 13, vertical: 13)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        minimumSize: iconOnly ? const Size(48, 46) : null,
      );
      if (iconOnly) {
        return Tooltip(
          message: 'Descartar alterações',
          child: OutlinedButton(
            onPressed: saving ? null : onDiscard,
            style: style,
            child: const Icon(
              LucideIcons.undo2,
              size: 17,
              semanticLabel: 'Descartar alterações',
            ),
          ),
        );
      }
      return OutlinedButton.icon(
        onPressed: saving ? null : onDiscard,
        style: style,
        icon: const Icon(LucideIcons.undo2, size: 15),
        label: const SiteButtonLabel('Descartar'),
      );
    }

    final pendingLine = Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: amber),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            pendingText,
            maxLines: docked ? 2 : null,
            overflow: docked ? TextOverflow.ellipsis : null,
            style: TextStyle(
              color: secondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ),
      ],
    );

    if (docked) {
      return AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.bottomCenter,
        child: !visible
            ? const SizedBox(width: double.infinity)
            : DecoratedBox(
                decoration: BoxDecoration(
                  color: ThemeHelpers.cardBackgroundColor(context),
                  border: Border(top: BorderSide(color: siteHairline(context))),
                ),
                child: SafeArea(
                  top: false,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxContentWidth),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final scale = siteTextScale(context);
                            final width = constraints.maxWidth;
                            // Largo: frase à esquerda, botões no tamanho do
                            // rótulo à direita, numa linha só.
                            if (width >= 560 * scale) {
                              return Row(
                                children: [
                                  Expanded(child: pendingLine),
                                  const SizedBox(width: 14),
                                  if (onDiscard != null) ...[
                                    discard(iconOnly: false),
                                    const SizedBox(width: 10),
                                  ],
                                  save,
                                ],
                              );
                            }
                            // Estreito: frase em cima e UMA fileira de
                            // botões — a barra fixa não pode virar duas
                            // fileiras em 320dp. Sem espaço para o rótulo,
                            // Descartar vira só o ícone (com dica) e Salvar
                            // fica com a largura.
                            final Widget buttons;
                            if (onDiscard == null) {
                              buttons = save;
                            } else if (width >= 360 * scale) {
                              buttons = SiteActionPair(
                                primaryFlex: 2,
                                minSecondary: 96,
                                primary: save,
                                secondary: discard(iconOnly: false),
                              );
                            } else {
                              buttons = Row(
                                children: [
                                  discard(iconOnly: true),
                                  const SizedBox(width: 10),
                                  Expanded(child: save),
                                ],
                              );
                            }
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                pendingLine,
                                const SizedBox(height: 8),
                                buttons,
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      );
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: !visible
          ? const SizedBox(width: double.infinity)
          : Container(
              margin: const EdgeInsets.only(top: 18),
              padding: const EdgeInsets.only(top: 14),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: siteHairline(context))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  pendingLine,
                  const SizedBox(height: 12),
                  if (onDiscard == null)
                    save
                  else
                    SiteActionPair(
                      primaryFlex: 2,
                      minSecondary: 96,
                      primary: save,
                      secondary: discard(iconOnly: false),
                    ),
                ],
              ),
            ),
    );
  }
}

// ─── Card padrão (sem borda lateral, sombra neutra) ──────────────────────────

class SiteCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const SiteCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    // Filete do token (#D6DAE1 no claro): no fundo branco a borda É a
    // separação — o preto a 5% de antes mal aparecia. Sombra só o crisp de
    // 1px do tema.
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: siteHairline(context)),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: child,
    );
  }
}

// ─── Roteiro numerado (passo com trilho) ─────────────────────────────────────

/// Situação de um passo do roteiro.
enum SiteStepState { todo, now, done, problem }

/// Passo numerado de um roteiro vertical (ex.: configurar o domínio): o nó
/// (número, ✓ verde quando feito, ! vermelho com problema) liga-se ao
/// próximo por um fio que fica verde quando o passo está feito; ao lado do
/// título, a situação escrita ("Feito", "Agora", "Depois", "Atenção"); abaixo,
/// a frase de apoio e o conteúdo do passo (campos, registros, botões).
///
/// O fio é um `Positioned` num `Stack` — sem IntrinsicHeight, porque o
/// conteúdo pode ter LayoutBuilder (que não mede altura intrínseca).
class SiteStep extends StatelessWidget {
  final int number;
  final String title;
  final SiteStepState state;

  /// Tom do passo em andamento ("Agora") — o acento da tela.
  final Color tone;
  final String? subtitle;
  final Widget? child;

  /// Último passo: sem fio para baixo.
  final bool last;

  /// Troca o rótulo padrão da situação.
  final String? stateLabel;

  const SiteStep({
    super.key,
    required this.number,
    required this.title,
    required this.state,
    required this.tone,
    this.subtitle,
    this.child,
    this.last = false,
    this.stateLabel,
  });

  static const double _node = 28;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final green = isDark
        ? AppColors.status.greenDarkMode
        : AppColors.status.green;
    final red = isDark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;

    final Color signal;
    final String label;
    if (state == SiteStepState.done) {
      signal = green;
      label = stateLabel ?? 'Feito';
    } else if (state == SiteStepState.problem) {
      signal = red;
      label = stateLabel ?? 'Atenção';
    } else if (state == SiteStepState.now) {
      signal = tone;
      label = stateLabel ?? 'Agora';
    } else {
      signal = secondary;
      label = stateLabel ?? 'Depois';
    }

    final solidNode =
        state == SiteStepState.done || state == SiteStepState.problem;
    final active = state == SiteStepState.now;
    final Widget mark = solidNode
        ? (state == SiteStepState.done
              ? const Icon(LucideIcons.check, size: 15, color: Colors.white)
              : const Text(
                  '!',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ))
        : Text(
            '$number',
            style: TextStyle(
              color: active ? siteInk(context, tone) : secondary,
              fontWeight: FontWeight.w900,
              fontSize: 12.5,
            ),
          );
    final node = Container(
      width: _node,
      height: _node,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: solidNode
            ? siteSolid(signal)
            : (active
                  ? tone.withValues(alpha: isDark ? 0.2 : 0.12)
                  : siteFieldFill(context)),
        border: solidNode
            ? null
            : Border.all(
                color: active ? tone : siteHairline(context),
                width: active ? 2 : 1,
              ),
      ),
      // O número/ícone encolhe com fonte grande em vez de vazar do nó.
      child: FittedBox(fit: BoxFit.scaleDown, child: mark),
    );

    return Stack(
      children: [
        if (!last)
          Positioned(
            left: _node / 2 - 1,
            top: _node + 4,
            bottom: 4,
            child: Container(
              width: 2,
              decoration: BoxDecoration(
                color: state == SiteStepState.done
                    ? green.withValues(alpha: 0.55)
                    : siteHairline(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.only(bottom: last ? 0 : 22),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              node,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: ThemeHelpers.textColor(context),
                                letterSpacing: -0.2,
                                height: 1.3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 104),
                            child: SiteMiniPill(label: label, tone: signal),
                          ),
                        ],
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                    if (child != null) ...[const SizedBox(height: 12), child!],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Linha do "o que falta" ──────────────────────────────────────────────────

/// Situação de um item de checklist.
enum SiteCheckState { done, missing, waiting, problem }

/// Linha de checklist ("o que falta para ir ao ar"): ícone da situação (✓
/// verde feito, círculo tracejado âmbar falta, relógio azul aguardando,
/// alerta vermelho problema), o item, a leitura numa frase e — quando o item
/// se resolve em outro lugar da tela — a seta que leva até lá.
class SiteCheckRow extends StatelessWidget {
  final String label;
  final String value;
  final SiteCheckState state;
  final VoidCallback? onTap;

  /// Filete sob a linha (desligue na última de um grupo).
  final bool divider;

  const SiteCheckRow({
    super.key,
    required this.label,
    required this.value,
    required this.state,
    this.onTap,
    this.divider = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final IconData icon;
    final Color tone;
    if (state == SiteCheckState.done) {
      icon = LucideIcons.circleCheckBig;
      tone = isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    } else if (state == SiteCheckState.waiting) {
      icon = LucideIcons.clock3;
      tone = isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
    } else if (state == SiteCheckState.problem) {
      icon = LucideIcons.circleAlert;
      tone = isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    } else {
      icon = LucideIcons.circleDashed;
      tone = isDark
          ? AppColors.status.warningDarkMode
          : AppColors.status.warning;
    }
    final ink = siteInk(context, tone);

    final content = Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: divider
          ? BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: ThemeHelpers.borderLightColor(context),
                ),
              ),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                    letterSpacing: -0.1,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: state == SiteCheckState.done ? secondary : ink,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(LucideIcons.chevronRight, size: 17, color: secondary),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    // Material transparente: o respingo aparece mesmo dentro de um SiteCard.
    return Semantics(
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

// ─── Amostra de cor (caixa fixa) ─────────────────────────────────────────────

/// Amostra de cor com a caixa em tamanho FIXO: a caixa nunca é espremida e o
/// nome e o código ao lado encolhem com reticências. [isDefault] = cor de
/// fábrica do modelo (ninguém escolheu uma ainda).
class SiteSwatchTile extends StatelessWidget {
  final String label;
  final Color color;

  /// Código da cor como a pessoa digitaria em outro sistema ("#A63126").
  final String code;

  /// Onde a cor aparece ("botões e destaques").
  final String? caption;
  final bool isDefault;
  final double boxSize;

  const SiteSwatchTile({
    super.key,
    required this.label,
    required this.color,
    required this.code,
    this.caption,
    this.isDefault = false,
    this.boxSize = 36,
  });

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Row(
      children: [
        Container(
          width: boxSize,
          height: boxSize,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: siteHairline(context)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ThemeHelpers.textColor(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.1,
                ),
              ),
              const SizedBox(height: 1),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: code,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontFamilyFallback: ['Menlo', 'Courier New'],
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (isDefault) const TextSpan(text: ' · padrão do modelo'),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: secondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (caption != null)
                Text(
                  caption!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: secondary, fontSize: 11, height: 1.3),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
