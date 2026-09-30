import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/tag_service.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/admin_user_model.dart';
import '../services/admin_users_service.dart';
import '../utils/permission_meta.dart';
import '../utils/permission_rules.dart';

/// Peças de acesso compartilhadas por Usuários, Criar e Editar usuário
/// (papel, gestores, grade de permissões, folhas, barra de salvar). Ficam
/// juntas para as telas — irmãs no web — não divergirem.

/// Largura máxima do conteúdo em tela larga/tablet (coluna central).
const double kUaMaxContentWidth = 720;

// ───────────────────────────────────────────────────────────────────────────
// Papel — cor, rótulo, ícone e explicação (fonte única das três telas)
// ───────────────────────────────────────────────────────────────────────────

/// Cor de identidade do papel, só por token: verde = Colaborador, azul =
/// Gestor, roxo = Administrativo/Proprietário, ardósia (tinta de texto
/// clara) = Gerenciador — neutro para não colidir com o roxo. [isDark]
/// escolhe a variante legível no tema escuro para ícones e acentos.
Color uaRoleTone(String role, {required bool isDark}) {
  switch (role.toLowerCase().trim()) {
    case 'master':
      return isDark ? AppColors.text.textLightDarkMode : AppColors.text.textLight;
    case 'admin':
      return isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
    case 'manager':
      return isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    default:
      return isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
  }
}

/// Amostra do papel para marcas de área (barra de composição, quadradinho
/// de legenda): o passo base, o mesmo nos dois temas (todos ≥ 3:1 no branco
/// e no grafite). Azul e roxo lado a lado ficam no limite de separação —
/// por isso a barra mantém o respiro entre as partes e a legenda numerada.
Color uaRoleSwatch(String role) => uaRoleTone(role, isDark: false);

/// Nome do papel — espelho do `translateUserRole` do web
/// (`imobx-front/src/utils/roleTranslations.ts`). Fonte ÚNICA de nomes de
/// papel nas telas de Usuários, Criar e Editar (lista, escolha de papel,
/// legenda, gestores): admin é "Proprietário" só para o dono da empresa.
String uaRoleLabel(String role, {bool isOwner = false}) {
  switch (role.toLowerCase().trim()) {
    case 'user':
      return 'Colaborador';
    case 'manager':
      return 'Gestor';
    case 'admin':
      return isOwner ? 'Proprietário' : 'Administrativo';
    case 'master':
      return 'Gerenciador';
    case 'leader':
      return 'Gestor da equipe';
    case 'member':
      return 'Membro';
    default:
      return role;
  }
}

IconData uaRoleIcon(String role) {
  switch (role.toLowerCase().trim()) {
    case 'master':
      return LucideIcons.crown;
    case 'admin':
      return LucideIcons.shieldCheck;
    case 'manager':
      return LucideIcons.users;
    default:
      return LucideIcons.userRound;
  }
}

/// O que o papel significa — as descrições dos cartões de papel do web
/// (`CreateUserPage`), com o lembrete do gestor obrigatório no Colaborador.
String uaRoleHint(String role) {
  switch (role.toLowerCase().trim()) {
    case 'master':
      return 'Acesso total à plataforma.';
    case 'admin':
      return 'Acesso administrativo completo com gestão de usuários.';
    case 'manager':
      return 'Gerencia equipes e colaboradores com permissões de usuário '
          'inclusas.';
    default:
      return 'Acesso básico com permissões limitadas ao que for concedido. '
          'Precisa de ao menos um gestor.';
  }
}

/// Uma opção de papel na escolha. [lockedReason] != null = aparece com
/// cadeado e, ao tocar, explica por que não dá para escolher. [isOwner]
/// nomeia o admin como "Proprietário" (dono da empresa).
class UaRoleChoice {
  const UaRoleChoice(this.value, {this.lockedReason, this.isOwner = false});
  final String value;
  final String? lockedReason;
  final bool isOwner;
}

/// Escolha de papel em linhas explicadas (ícone na cor do papel + o que ele
/// faz). Papel sem alçada não some: fica travado com o motivo.
class UaRolePicker extends StatelessWidget {
  const UaRolePicker({
    super.key,
    required this.current,
    required this.choices,
    required this.onChanged,
    this.enabled = true,
  });

  final String current;
  final List<UaRoleChoice> choices;
  final ValueChanged<String> onChanged;
  final bool enabled;

  void _tap(BuildContext context, UaRoleChoice choice) {
    final reason = choice.lockedReason;
    if (reason != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(reason),
          ),
        );
      return;
    }
    onChanged(choice.value);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < choices.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _UaRoleOption(
            choice: choices[i],
            selected: choices[i].value == current,
            enabled: enabled,
            onTap: () => _tap(context, choices[i]),
          ),
        ],
      ],
    );
  }
}

class _UaRoleOption extends StatelessWidget {
  const _UaRoleOption({
    required this.choice,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final UaRoleChoice choice;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone = uaRoleTone(choice.value, isDark: isDark);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final locked = choice.lockedReason != null;
    final radius = BorderRadius.circular(14);

    return Opacity(
      opacity: locked ? 0.65 : 1,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: radius,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
            decoration: BoxDecoration(
              color: selected
                  ? tone.withValues(alpha: isDark ? 0.14 : 0.08)
                  : Colors.transparent,
              borderRadius: radius,
              border: Border.all(
                color: selected
                    ? tone.withValues(alpha: isDark ? 0.6 : 0.55)
                    : ThemeHelpers.borderColor(context),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: isDark ? 0.18 : 0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(uaRoleIcon(choice.value), size: 18, color: tone),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        uaRoleLabel(choice.value, isOwner: choice.isOwner),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        locked ? choice.lockedReason! : uaRoleHint(choice.value),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: secondary,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Icon(
                    locked
                        ? LucideIcons.lock
                        : (selected
                            ? LucideIcons.circleCheckBig
                            : LucideIcons.circle),
                    size: locked ? 16 : 19,
                    color: locked
                        ? secondary
                        : (selected ? tone : secondary.withValues(alpha: 0.55)),
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

// ───────────────────────────────────────────────────────────────────────────
// Formulário — tema dos campos, duas colunas, cabeçalho de seção, avisos
// ───────────────────────────────────────────────────────────────────────────

/// Acento usado como TINTA de texto: só fica na cor se passar 4,5:1 sobre o
/// fundo em que está ([on]; padrão = fundo do card do tema). Senão vira a
/// tinta de texto — o acento continua nos ícones, bordas e barras. No claro,
/// verde, azul e roxo dos papéis caem para a tinta; vermelho da marca e
/// ardósia passam.
Color uaInk(BuildContext context, Color accent, {Color? on}) {
  final bg = on ?? ThemeHelpers.cardBackgroundColor(context);
  final la = accent.computeLuminance();
  final lb = bg.computeLuminance();
  final contrast =
      la > lb ? (la + 0.05) / (lb + 0.05) : (lb + 0.05) / (la + 0.05);
  return contrast >= 4.5 ? accent : ThemeHelpers.textColor(context);
}

/// Tema local dos campos — mesma receita do formulário de ficha aprovado:
/// fill sólido por token, sem borda em repouso, foco na cor do acento, erro
/// em vermelho. Inputs e selects herdam daqui e ficam idênticos.
ThemeData uaFormTheme(BuildContext context, Color accent) {
  final base = Theme.of(context);
  final isDark = base.brightness == Brightness.dark;
  final fill = isDark
      ? AppColors.background.backgroundTertiaryDarkMode
      : AppColors.background.backgroundTertiary;
  final muted = ThemeHelpers.textSecondaryColor(context);
  final labelInk = uaInk(context, accent);
  final error = isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
  OutlineInputBorder b(Color c, double w) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: w == 0 ? BorderSide.none : BorderSide(color: c, width: w),
      );
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(primary: accent),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: accent,
      selectionColor: accent.withValues(alpha: 0.18),
      selectionHandleColor: accent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: fill,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      labelStyle: TextStyle(
        color: muted,
        fontWeight: FontWeight.w600,
        fontSize: 13.5,
      ),
      floatingLabelStyle: TextStyle(
        color: labelInk,
        fontWeight: FontWeight.w700,
        fontSize: 13.5,
      ),
      hintStyle: TextStyle(
        color: muted.withValues(alpha: 0.7),
        fontWeight: FontWeight.w500,
      ),
      errorStyle: TextStyle(
        color: error,
        fontWeight: FontWeight.w600,
        fontSize: 11.5,
      ),
      errorMaxLines: 3,
      border: b(Colors.transparent, 0),
      enabledBorder: b(Colors.transparent, 0),
      disabledBorder: b(Colors.transparent, 0),
      focusedBorder: b(accent, 1.6),
      errorBorder: b(error.withValues(alpha: 0.75), 1.2),
      focusedErrorBorder: b(error, 1.6),
    ),
  );
}

/// Duas colunas quando cabe (largura e escala de fonte); senão empilha.
class UaTwoCols extends StatelessWidget {
  const UaTwoCols({super.key, required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final fits = c.maxWidth >= 360 &&
            MediaQuery.textScalerOf(context).scale(14) <= 16;
        if (!fits) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, const SizedBox(height: 12), right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 12),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

/// Cabeçalho de seção flush: ícone tonal + rótulo em caixa alta + filete
/// até a borda (+ [trailing] opcional, ex.: contagem). O rótulo nunca
/// empurra o filete para fora: larguras medidas pelo LayoutBuilder.
class UaSectionHeader extends StatelessWidget {
  const UaSectionHeader({
    super.key,
    required this.icon,
    required this.label,
    required this.accent,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hairline = ThemeHelpers.borderLightColor(context);
    return LayoutBuilder(
      builder: (context, c) {
        final trailW = trailing == null ? 0.0 : c.maxWidth * 0.34;
        var titleMax =
            c.maxWidth - 36 - 34 - (trailing == null ? 0 : trailW + 10);
        if (titleMax < 40) titleMax = 40;
        return Row(
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: isDark ? 0.18 : 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 14, color: accent),
            ),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: titleMax),
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Container(height: 1, color: hairline)),
            if (trailing != null) ...[
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: trailW),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: trailing,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Texto de apoio discreto sob um campo ou seção.
class UaHint extends StatelessWidget {
  const UaHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.35,
        color: ThemeHelpers.textSecondaryColor(context),
      ),
    );
  }
}

/// Linha de requisito sob o cabeçalho: âmbar + texto forte enquanto falta,
/// check verde + texto discreto quando já está atendido. Deixa o que é
/// obrigatório à vista ANTES de tocar em salvar.
class UaRequirementLine extends StatelessWidget {
  const UaRequirementLine({super.key, required this.met, required this.text});

  final bool met;
  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone = met
        ? (isDark ? AppColors.status.successDarkMode : AppColors.status.success)
        : (isDark
            ? AppColors.status.warningDarkMode
            : AppColors.message.warningText);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            met ? LucideIcons.circleCheck : LucideIcons.circleAlert,
            size: 15,
            color: tone,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: met ? FontWeight.w500 : FontWeight.w700,
              height: 1.35,
              color: met
                  ? ThemeHelpers.textSecondaryColor(context)
                  : ThemeHelpers.textColor(context),
            ),
          ),
        ),
      ],
    );
  }
}

/// Aviso inline (âmbar = trava/bloqueio; azul = informativo). Usado dentro
/// das folhas, onde o SnackBar da página ficaria escondido atrás do modal.
class UaNoticeBanner extends StatelessWidget {
  const UaNoticeBanner({super.key, required this.notice});

  final PermissionNotice notice;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone = notice.warning
        ? (isDark
            ? AppColors.status.warningDarkMode
            : AppColors.message.warningText)
        : (isDark ? AppColors.status.infoDarkMode : AppColors.message.infoText);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            notice.warning ? LucideIcons.triangleAlert : LucideIcons.info,
            size: 16,
            color: tone,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              notice.message,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: ThemeHelpers.textColor(context),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pílula de contagem ("12 de 40") — número em tinta de texto, acento só no
/// fundo e na borda (lê bem nos dois temas).
class UaCountPill extends StatelessWidget {
  const UaCountPill({super.key, required this.text, required this.accent});

  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.32)),
      ),
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: ThemeHelpers.textColor(context),
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Barra de salvar — pendências tocáveis + Cancelar neutro + Salvar verde
// ───────────────────────────────────────────────────────────────────────────

/// Item que ainda falta para salvar. Tocar leva até a seção.
class UaPending {
  const UaPending(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;
}

class UaSaveBar extends StatelessWidget {
  const UaSaveBar({
    super.key,
    required this.saveLabel,
    required this.onSave,
    this.saving = false,
    this.cancelLabel,
    this.onCancel,
    this.pendingTitle = 'Falta:',
    this.pending = const [],
  });

  final String saveLabel;

  /// null = botão desabilitado.
  final VoidCallback? onSave;
  final bool saving;

  /// null = sem botão de cancelar.
  final String? cancelLabel;
  final VoidCallback? onCancel;
  final String pendingTitle;
  final List<UaPending> pending;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirm =
        isDark ? AppColors.status.successDarkMode : AppColors.status.success;
    final secondary = ThemeHelpers.textSecondaryColor(context);

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border(
          top: BorderSide(color: ThemeHelpers.borderColor(context)),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        10 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kUaMaxContentWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (pending.isNotEmpty) ...[
                _UaPendingLine(title: pendingTitle, items: pending),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  if (cancelLabel != null) ...[
                    TextButton(
                      onPressed: saving ? null : onCancel,
                      style: TextButton.styleFrom(
                        // Cancelar nunca em vermelho: o tema pinta
                        // TextButton com a marca, então forçamos o neutro.
                        foregroundColor: secondary,
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        cancelLabel!,
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: saving ? null : onSave,
                      style: FilledButton.styleFrom(
                        backgroundColor: confirm,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            confirm.withValues(alpha: 0.35),
                        disabledForegroundColor:
                            Colors.white.withValues(alpha: 0.9),
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(LucideIcons.check, size: 18),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          saveLabel,
                          maxLines: 1,
                          softWrap: false,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UaPendingLine extends StatelessWidget {
  const _UaPendingLine({required this.title, required this.items});

  final String title;
  final List<UaPending> items;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final warn = isDark
        ? AppColors.status.warningDarkMode
        : AppColors.message.warningText;
    final textColor = ThemeHelpers.textColor(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Icon(LucideIcons.circleAlert, size: 15, color: warn),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
              for (final p in items)
                Material(
                  color: warn.withValues(alpha: isDark ? 0.16 : 0.12),
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    onTap: p.onTap,
                    borderRadius: BorderRadius.circular(999),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              p.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: textColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            LucideIcons.chevronRight,
                            size: 14,
                            color: textColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Avatar (foto ou iniciais tingidas na cor do papel — sem gradiente)
// ───────────────────────────────────────────────────────────────────────────

class UaAvatar extends StatelessWidget {
  const UaAvatar({
    super.key,
    required this.name,
    required this.url,
    required this.tone,
    this.size = 40,
    this.radius,
  });

  final String name;
  final String? url;
  final Color tone;
  final double size;
  final double? radius;

  String get _initials {
    final p = name.trim().split(RegExp(r'\s+'));
    if (p.isEmpty || p.first.isEmpty) return '?';
    if (p.length == 1) return p.first.substring(0, 1).toUpperCase();
    return '${p.first[0]}${p.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final r = BorderRadius.circular(radius ?? size * 0.32);
    final tint = tone.withValues(alpha: isDark ? 0.22 : 0.14);
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: tint, borderRadius: r),
      child: Text(
        _initials,
        textScaler: MediaQuery.textScalerOf(context).clamp(
          maxScaleFactor: 1.2,
        ),
        style: TextStyle(
          // Iniciais são texto: só levam o tom se passarem 4,5:1 sobre o
          // fundo tingido de verdade (o tingido já carrega a cor do papel).
          color: uaInk(
            context,
            tone,
            on: Color.alphaBlend(
              tint,
              ThemeHelpers.cardBackgroundColor(context),
            ),
          ),
          fontWeight: FontWeight.w900,
          fontSize: size * 0.36,
          letterSpacing: 0.2,
        ),
      ),
    );
    final hasPhoto = (url ?? '').trim().isNotEmpty;
    if (!hasPhoto) return fallback;
    return ClipRRect(
      borderRadius: r,
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
          url!,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback,
          loadingBuilder: (_, child, prog) => prog == null ? child : fallback,
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Gestor responsável — vaga vazia que ensina + linhas dos vinculados
// ───────────────────────────────────────────────────────────────────────────

/// Gestores responsáveis. Sem ninguém: uma vaga tocável (âmbar quando é
/// obrigatório). Com gestores: nome completo de cada um + remover, e o
/// atalho para vincular outro.
class UaManagerSelector extends StatelessWidget {
  const UaManagerSelector({
    super.key,
    required this.managers,
    required this.selected,
    required this.missing,
    required this.accent,
    required this.onAdd,
    required this.onRemove,
    this.enabled = true,
  });

  final List<AdminUser> managers;
  final Set<String> selected;
  final bool missing;
  final Color accent;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final chosen = managers.where((m) => selected.contains(m.id)).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final unknown =
        selected.where((id) => managers.every((m) => m.id != id)).toList();
    final empty = chosen.isEmpty && unknown.isEmpty;

    if (empty) {
      final tone = missing
          ? (isDark
              ? AppColors.status.warningDarkMode
              : AppColors.message.warningText)
          : accent;
      final radius = BorderRadius.circular(14);
      return Material(
        color: tone.withValues(alpha: isDark ? 0.10 : 0.06),
        borderRadius: radius,
        child: InkWell(
          onTap: enabled ? onAdd : null,
          borderRadius: radius,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: tone.withValues(alpha: 0.45)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: isDark ? 0.20 : 0.14),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(LucideIcons.userPlus, size: 18, color: tone),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Escolher gestor',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Nenhum gestor vinculado ainda.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(LucideIcons.chevronRight, size: 18, color: secondary),
              ],
            ),
          ),
        ),
      );
    }

    final hairline = ThemeHelpers.borderLightColor(context);
    final rows = <Widget>[
      for (final m in chosen)
        _UaChosenManagerRow(
          name: m.name,
          detail: m.email,
          avatarUrl: m.avatar,
          accent: accent,
          enabled: enabled,
          onRemove: () => onRemove(m.id),
        ),
      for (final id in unknown)
        _UaChosenManagerRow(
          name: 'Gestor vinculado',
          detail: 'Não aparece na lista de gestores desta empresa',
          avatarUrl: null,
          accent: accent,
          enabled: enabled,
          onRemove: () => onRemove(id),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0)
            Container(
              height: 1,
              margin: const EdgeInsets.only(left: 44),
              color: hairline,
            ),
          rows[i],
        ],
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: enabled ? onAdd : null,
            style: TextButton.styleFrom(
              foregroundColor: uaInk(context, accent),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 40),
            ),
            icon: const Icon(LucideIcons.userPlus, size: 16),
            label: const Text(
              'Vincular outro gestor',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }
}

class _UaChosenManagerRow extends StatelessWidget {
  const _UaChosenManagerRow({
    required this.name,
    required this.detail,
    required this.avatarUrl,
    required this.accent,
    required this.enabled,
    required this.onRemove,
  });

  final String name;
  final String detail;
  final String? avatarUrl;
  final Color accent;
  final bool enabled;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          UaAvatar(name: name, url: avatarUrl, tone: accent, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: secondary),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remover gestor',
            visualDensity: VisualDensity.compact,
            onPressed: enabled ? onRemove : null,
            icon: Icon(LucideIcons.x, size: 17, color: secondary),
          ),
        ],
      ),
    );
  }
}

class UaManagerRow extends StatelessWidget {
  const UaManagerRow({
    super.key,
    required this.user,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final AdminUser user;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final radius = BorderRadius.circular(12);
    return Material(
      color: selected
          ? accent.withValues(alpha: isDark ? 0.14 : 0.08)
          : Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              UaAvatar(
                name: user.name,
                url: user.avatar,
                tone: selected ? accent : secondary,
                size: 36,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                      ),
                    ),
                    Text(
                      '${uaRoleLabel(user.role, isOwner: user.owner)} · '
                      '${user.email}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: secondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected ? LucideIcons.circleCheckBig : LucideIcons.circle,
                size: 20,
                color: selected ? accent : secondary.withValues(alpha: 0.55),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Folha — casca (grabber, título à esquerda, fechar à direita) + busca
// ───────────────────────────────────────────────────────────────────────────

class UaSheetShell extends StatelessWidget {
  const UaSheetShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.child,
    this.icon,
    this.trailing,
    this.showClose = true,
  });

  final String title;
  final String subtitle;
  final Color accent;
  final Widget child;
  final IconData? icon;
  final Widget? trailing;
  final bool showClose;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final mq = MediaQuery.of(context);
    return Container(
      // Teto de 88% da altura: em paisagem/tela baixa o corpo rola dentro.
      constraints: BoxConstraints(maxHeight: mq.size.height * 0.88),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.6),
          ),
        ),
      ),
      padding: EdgeInsets.fromLTRB(16, 8, 10, 14 + mq.padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12, right: 6),
              decoration: BoxDecoration(
                color: ThemeHelpers.borderColor(context),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.18 : 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 18, color: accent),
                ),
                const SizedBox(width: 12),
              ],
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
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w900,
                          color: textColor,
                          letterSpacing: -0.3,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              if (showClose)
                IconButton(
                  tooltip: 'Fechar',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(LucideIcons.x, size: 20, color: secondary),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class UaSheetSearch extends StatelessWidget {
  const UaSheetSearch({
    super.key,
    required this.controller,
    required this.accent,
    required this.onChanged,
    this.hint = 'Buscar…',
  });

  final TextEditingController controller;
  final Color accent;
  final ValueChanged<String> onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 46),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.background.backgroundTertiaryDarkMode
            : AppColors.background.backgroundTertiary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(LucideIcons.search, size: 16, color: secondary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              cursorColor: accent,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: ThemeHelpers.textColor(context),
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                  color: secondary.withValues(alpha: 0.75),
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

/// Folha de escolha de gestores (busca + lista marcável + concluir).
Future<void> showUaManagerSheet({
  required BuildContext context,
  required List<AdminUser> managers,
  required Set<String> selected,
  required Color accent,
  required ValueChanged<String> onToggle,
}) async {
  final searchCtrl = TextEditingController();
  String q = '';
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheet) {
          final filtered = managers.where((m) {
            if (q.isEmpty) return true;
            return m.name.toLowerCase().contains(q) ||
                m.email.toLowerCase().contains(q);
          }).toList();
          final count = selected.length;
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final confirm = isDark
              ? AppColors.status.successDarkMode
              : AppColors.status.success;
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: UaSheetShell(
              title: 'Gestor responsável',
              subtitle: count == 0
                  ? 'Toque para vincular um ou mais gestores.'
                  : (count == 1
                      ? '1 gestor vinculado'
                      : '$count gestores vinculados'),
              accent: accent,
              icon: LucideIcons.users,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  UaSheetSearch(
                    controller: searchCtrl,
                    accent: accent,
                    hint: 'Buscar por nome ou e-mail',
                    onChanged: (v) =>
                        setSheet(() => q = v.trim().toLowerCase()),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: filtered.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 24,
                              horizontal: 8,
                            ),
                            child: Text(
                              q.isEmpty
                                  ? 'Nenhum gestor cadastrado nesta empresa. '
                                      'Crie um usuário com o papel Gestor '
                                      'para vinculá-lo aqui.'
                                  : 'Nenhum gestor com esse nome ou e-mail.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: ThemeHelpers.textSecondaryColor(ctx),
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 4),
                            itemBuilder: (_, i) {
                              final m = filtered[i];
                              return UaManagerRow(
                                user: m,
                                selected: selected.contains(m.id),
                                accent: accent,
                                onTap: () {
                                  onToggle(m.id);
                                  setSheet(() {});
                                },
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).maybePop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: confirm,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Concluir',
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
  searchCtrl.dispose();
}

// ───────────────────────────────────────────────────────────────────────────
// Permissões — categorias em linhas flush, contagem "N de M", travas
// ───────────────────────────────────────────────────────────────────────────

/// Quantas permissões VISÍVEIS estão marcadas (as ocultas, como galeria,
/// entram na seleção mas não na grade — contá-las dava "57 de 56").
int uaVisibleSelectedCount(PermissionSelection selection) {
  var n = 0;
  for (final e in selection.categories) {
    for (final p in e.value) {
      if (selection.selected.contains(p.id)) n++;
    }
  }
  return n;
}

/// Rótulos das permissões que o toque vai marcar junto (dependências que
/// ainda não estão marcadas) — mesma conta das regras, só para avisar antes.
List<String> _uaAlsoEnables(
  UserPermission p,
  PermissionSelection selection,
  Map<String, UserPermission> byName,
) {
  final out = <String>[];
  for (final name in PermissionRules.requiredNames(p.name)) {
    if (name == p.name || name.startsWith('gallery:')) continue;
    final q = byName[name];
    if (q == null || selection.selected.contains(q.id)) continue;
    final label = PermissionRules.labelOf(q);
    if (!out.contains(label)) out.add(label);
  }
  return out;
}

/// Linha de uma categoria: ícone, nome (até 2 linhas), "N de M", barra fina
/// e, quando há, quantas estão travadas e por quê.
class UaCategoryTile extends StatelessWidget {
  const UaCategoryTile({
    super.key,
    required this.category,
    required this.perms,
    required this.selection,
    required this.accent,
    required this.onTap,
  });

  final String category;
  final List<UserPermission> perms;
  final PermissionSelection selection;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final total = perms.length;
    final active = perms.where((p) => selection.selected.contains(p.id)).length;
    final frac = total == 0 ? 0.0 : active / total;
    final on = active > 0;

    var mandatory = 0;
    var adminOnly = 0;
    if (!selection.ownerLocked) {
      for (final p in perms) {
        if (selection.lockReason(p) == null) continue;
        if (PermissionRules.adminOnly.contains(p.name)) {
          adminOnly++;
        } else {
          mandatory++;
        }
      }
    }
    final notes = <String>[
      if (selection.ownerLocked) 'Só o usuário master altera',
      if (mandatory > 0)
        mandatory == 1 ? '1 obrigatória' : '$mandatory obrigatórias',
      if (adminOnly > 0)
        adminOnly == 1
            ? '1 exclusiva de administrador'
            : '$adminOnly exclusivas de administrador',
    ];

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: on
                      ? accent.withValues(alpha: isDark ? 0.18 : 0.12)
                      : ThemeHelpers.borderLightColor(context),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  PermissionMeta.categoryIcon(category),
                  size: 17,
                  color: on ? accent : secondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            PermissionMeta.categoryLabel(category),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: textColor,
                              height: 1.2,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '$active de $total',
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: on ? textColor : secondary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: frac,
                        minHeight: 4,
                        backgroundColor: ThemeHelpers.borderLightColor(context),
                        valueColor: AlwaysStoppedAnimation(accent),
                      ),
                    ),
                    if (notes.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(
                              LucideIcons.lock,
                              size: 11,
                              color: secondary,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              notes.join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: secondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                LucideIcons.chevronRight,
                size: 18,
                color: secondary.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Linha de uma permissão dentro da folha da categoria: caixa de marcar,
/// ação em destaque, descrição completa (quebra linha, nunca corta), o
/// cadeado com o motivo e o aviso do que o toque marca junto.
class UaPermRow extends StatelessWidget {
  const UaPermRow({
    super.key,
    required this.label,
    required this.description,
    required this.selected,
    required this.accent,
    required this.onTap,
    this.lockLabel,
    this.alsoEnables = const [],
  });

  final String label;
  final String? description;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  /// Quando presente, a linha está travada (obrigatória, só administrador,
  /// proprietário) — o toque ainda chega para explicar o motivo.
  final String? lockLabel;

  /// Permissões que o toque vai marcar junto (dependências).
  final List<String> alsoEnables;

  @override
  Widget build(BuildContext context) {
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final locked = lockLabel != null;
    final desc = (description ?? '').trim();
    final showDesc = desc.isNotEmpty && desc.toLowerCase() != label.toLowerCase();
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: selected
                        ? accent.withValues(alpha: locked ? 0.55 : 1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: selected
                          ? Colors.transparent
                          : ThemeHelpers.borderColor(context),
                      width: 1.6,
                    ),
                  ),
                  child: selected
                      ? const Icon(
                          Icons.check_rounded,
                          size: 15,
                          color: Colors.white,
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w700,
                        color: textColor,
                        height: 1.25,
                      ),
                    ),
                    if (showDesc) ...[
                      const SizedBox(height: 2),
                      Text(
                        desc,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: secondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (locked) ...[
                      const SizedBox(height: 5),
                      _UaInlineNote(icon: LucideIcons.lock, text: lockLabel!),
                    ] else if (alsoEnables.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      _UaInlineNote(
                        icon: LucideIcons.cornerDownRight,
                        text: 'Ao marcar, também ativa: '
                            '${alsoEnables.join(', ')}',
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UaInlineNote extends StatelessWidget {
  const _UaInlineNote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 12, color: secondary),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: secondary,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

/// Categorias de permissão em linhas flush com filete (1 coluna no celular,
/// 2 em tela larga — altura intrínseca, sem aspect ratio fixo).
class UaPermissionGrid extends StatelessWidget {
  const UaPermissionGrid({
    super.key,
    required this.selection,
    required this.accent,
    required this.onOpenCategory,
  });

  final PermissionSelection selection;
  final Color accent;
  final void Function(String category, List<UserPermission> perms)
      onOpenCategory;

  @override
  Widget build(BuildContext context) {
    final cats = selection.categories;
    if (cats.isEmpty) {
      return const UaHint(
        'Nenhuma permissão disponível no plano desta empresa.',
      );
    }
    final hairline = ThemeHelpers.borderLightColor(context);
    Widget tile(MapEntry<String, List<UserPermission>> e) => UaCategoryTile(
          category: e.key,
          perms: e.value,
          selection: selection,
          accent: accent,
          onTap: () => onOpenCategory(e.key, e.value),
        );
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 600 ? 2 : 1;
        final rows = <Widget>[];
        for (var i = 0; i < cats.length; i += cols) {
          if (i > 0) {
            rows.add(
              Container(
                height: 1,
                margin: EdgeInsets.only(left: cols == 1 ? 48 : 0),
                color: hairline,
              ),
            );
          }
          if (cols == 1) {
            rows.add(tile(cats[i]));
          } else {
            rows.add(
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: tile(cats[i])),
                    Container(
                      width: 1,
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      color: hairline,
                    ),
                    Expanded(
                      child: i + 1 < cats.length
                          ? tile(cats[i + 1])
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            );
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }
}

/// Folha de uma categoria: liga/desliga cada permissão com as regras do
/// web (fixas, dependências, alçada, proprietário). [onChanged] avisa a
/// página para redesenhar a grade.
Future<void> showUaPermissionCategorySheet({
  required BuildContext context,
  required PermissionSelection selection,
  required String category,
  required List<UserPermission> perms,
  required Color accent,
  required VoidCallback onChanged,
}) async {
  PermissionNotice? notice;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheet) {
          final ids = perms.map((p) => p.id).toSet();
          final allOn = ids.every(selection.selected.contains);
          final active =
              perms.where((p) => selection.selected.contains(p.id)).length;
          final byName = <String, UserPermission>{
            for (final e in selection.categories)
              for (final p in e.value) p.name: p,
          };
          final hairline = ThemeHelpers.borderLightColor(ctx);
          return UaSheetShell(
            title: PermissionMeta.categoryLabel(category),
            subtitle: '$active de ${perms.length} ativas',
            accent: accent,
            icon: PermissionMeta.categoryIcon(category),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!selection.ownerLocked)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        final n = selection.toggleCategory(category);
                        onChanged();
                        setSheet(() => notice = n);
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: uaInk(ctx, accent),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 38),
                      ),
                      icon: Icon(
                        allOn ? LucideIcons.squareCheckBig : LucideIcons.square,
                        size: 16,
                      ),
                      label: Text(
                        allOn ? 'Desmarcar todas' : 'Marcar todas',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                if (notice != null) ...[
                  const SizedBox(height: 4),
                  UaNoticeBanner(notice: notice!),
                  const SizedBox(height: 6),
                ],
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: perms.length,
                    separatorBuilder: (_, _) => Container(
                      height: 1,
                      margin: const EdgeInsets.only(left: 36),
                      color: hairline,
                    ),
                    itemBuilder: (_, i) {
                      final p = perms[i];
                      final isOn = selection.selected.contains(p.id);
                      final lock = selection.lockReason(p);
                      return UaPermRow(
                        label: PermissionMeta.actionLabel(p.name),
                        description: PermissionMeta.permissionDescription(
                          p.name,
                          fallback: p.description,
                        ),
                        selected: isOn,
                        accent: accent,
                        lockLabel: lock,
                        alsoEnables: isOn || lock != null
                            ? const []
                            : _uaAlsoEnables(p, selection, byName),
                        onTap: () {
                          final n = selection.toggle(p.id);
                          onChanged();
                          setSheet(() => notice = n);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

// ───────────────────────────────────────────────────────────────────────────
// Tags, select com cara de campo, folha de escolha única, cargo/superior
// ───────────────────────────────────────────────────────────────────────────

/// Tags do usuário (chips marcáveis) com teto — paridade com o
/// `TagSelector` do web (5 no cadastro, 10 na edição).
class UaTagSelector extends StatelessWidget {
  const UaTagSelector({
    super.key,
    required this.tags,
    required this.selected,
    required this.maxTags,
    required this.accent,
    required this.onToggle,
    this.loading = false,
    this.enabled = true,
  });

  final List<Tag> tags;
  final Set<String> selected;
  final int maxTags;
  final Color accent;
  final ValueChanged<String> onToggle;
  final bool loading;
  final bool enabled;

  Color _tagColor(Tag t) {
    final raw = (t.color ?? '').replaceAll('#', '').trim();
    if (raw.length == 6) {
      final v = int.tryParse(raw, radix: 16);
      if (v != null) return Color(0xFF000000 | v);
    }
    return accent;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    if (loading) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: List.generate(
          4,
          (i) => SkeletonBox(width: 70.0 + i * 12, height: 32, borderRadius: 999),
        ),
      );
    }
    if (tags.isEmpty) {
      return const UaHint(
        'Nenhuma tag cadastrada na empresa ainda — quando houver, elas '
        'aparecem aqui para marcar.',
      );
    }
    final atLimit = selected.length >= maxTags;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in tags)
              Builder(
                builder: (context) {
                  final on = selected.contains(t.id);
                  final tone = _tagColor(t);
                  final disabled = !enabled || (!on && atLimit);
                  return Opacity(
                    opacity: disabled && !on ? 0.5 : 1,
                    child: GestureDetector(
                      onTap: disabled ? null : () => onToggle(t.id),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: on
                              ? tone.withValues(alpha: isDark ? 0.18 : 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: on
                                ? tone.withValues(alpha: 0.55)
                                : ThemeHelpers.borderColor(context),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: tone,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                t.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: on
                                      ? ThemeHelpers.textColor(context)
                                      : secondary,
                                ),
                              ),
                            ),
                            if (on) ...[
                              const SizedBox(width: 5),
                              Icon(LucideIcons.check, size: 13, color: tone),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          atLimit
              ? 'Limite de $maxTags tags atingido — desmarque uma para trocar.'
              : '${selected.length} de $maxTags selecionadas',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: secondary,
          ),
        ),
      ],
    );
  }
}

/// Campo de escolha com a cara dos inputs `filled` da casa (abre folha).
/// Herda o tema local dos campos ([uaFormTheme]) — fica idêntico a eles.
class UaSelectField extends StatelessWidget {
  const UaSelectField({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.loading = false,
    this.enabled = true,
  });

  final String label;
  final String? value;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
  final bool loading;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final has = (value ?? '').isNotEmpty;
    return InkWell(
      onTap: enabled && !loading ? onTap : null,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        isEmpty: !has && !loading,
        decoration: InputDecoration(
          labelText: label,
          enabled: enabled,
          prefixIcon: Icon(icon, size: 17, color: secondary),
          suffixIcon: loading
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SkeletonBox(width: 16, height: 16, borderRadius: 4),
                )
              : Icon(LucideIcons.chevronDown, size: 17, color: secondary),
        ),
        child: Text(
          has ? value! : '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: ThemeHelpers.textColor(context),
          ),
        ),
      ),
    );
  }
}

/// Opção genérica de folha de escolha única.
class UaOption {
  final String? id;
  final String title;
  final String? subtitle;
  const UaOption({required this.id, required this.title, this.subtitle});
}

/// Folha de escolha única (com busca quando a lista é longa).
Future<UaOption?> showUaOptionSheet({
  required BuildContext context,
  required String title,
  required String subtitle,
  required List<UaOption> options,
  required String? currentId,
  required Color accent,
}) {
  final searchCtrl = TextEditingController();
  String q = '';
  return showModalBottomSheet<UaOption>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheet) {
          final filtered = options.where((o) {
            if (q.isEmpty || o.id == null) return true;
            return o.title.toLowerCase().contains(q) ||
                (o.subtitle ?? '').toLowerCase().contains(q);
          }).toList();
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final textColor = ThemeHelpers.textColor(ctx);
          final secondary = ThemeHelpers.textSecondaryColor(ctx);
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: UaSheetShell(
              title: title,
              subtitle: subtitle,
              accent: accent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (options.length > 8) ...[
                    UaSheetSearch(
                      controller: searchCtrl,
                      accent: accent,
                      onChanged: (v) =>
                          setSheet(() => q = v.trim().toLowerCase()),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 4),
                      itemBuilder: (_, i) {
                        final o = filtered[i];
                        final on = o.id == currentId;
                        final radius = BorderRadius.circular(12);
                        return Material(
                          color: on
                              ? accent.withValues(alpha: isDark ? 0.14 : 0.08)
                              : Colors.transparent,
                          borderRadius: radius,
                          child: InkWell(
                            onTap: () => Navigator.of(ctx).pop(o),
                            borderRadius: radius,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 11,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          o.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w800,
                                            color: o.id == null
                                                ? secondary
                                                : textColor,
                                          ),
                                        ),
                                        if ((o.subtitle ?? '').isNotEmpty)
                                          Text(
                                            o.subtitle!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: secondary,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    on
                                        ? LucideIcons.circleCheckBig
                                        : LucideIcons.circle,
                                    size: 18,
                                    color: on
                                        ? accent
                                        : secondary.withValues(alpha: 0.45),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  ).whenComplete(searchCtrl.dispose);
}

/// Cargo (escada da imobiliária) + superior direto — porte do
/// `CargoESuperiorFields` do web. Carrega a escada e os colegas; na edição
/// ([userId]) tira da lista de superiores a própria pessoa e quem está
/// abaixo dela (evita ciclo). Duas colunas quando cabe.
class UaHierarchyFields extends StatefulWidget {
  const UaHierarchyFields({
    super.key,
    required this.jobLevelId,
    required this.reportsToUserId,
    required this.accent,
    required this.onChanged,
    this.userId,
    this.enabled = true,
  });

  final String? jobLevelId;
  final String? reportsToUserId;
  final Color accent;
  final void Function(String? jobLevelId, String? reportsToUserId) onChanged;
  final String? userId;
  final bool enabled;

  @override
  State<UaHierarchyFields> createState() => _UaHierarchyFieldsState();
}

class _UaHierarchyFieldsState extends State<UaHierarchyFields> {
  bool _loading = true;
  List<JobLevelOption> _levels = const [];
  List<AdminUser> _colleagues = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = AdminUsersService.instance;
    final results = await Future.wait([
      svc.listJobLevels(),
      svc.listCompanyColleagues(),
    ]);
    if (!mounted) return;
    final levels = results[0];
    final colleagues = results[1];
    setState(() {
      _loading = false;
      if (levels.success && levels.data != null) {
        _levels = levels.data! as List<JobLevelOption>;
      }
      if (colleagues.success && colleagues.data != null) {
        _colleagues = colleagues.data! as List<AdminUser>;
      }
    });
  }

  List<AdminUser> get _superiors {
    final below = <String>{if (widget.userId != null) widget.userId!};
    var grew = widget.userId != null;
    while (grew) {
      grew = false;
      for (final c in _colleagues) {
        final r = c.reportsToUserId;
        if (r != null && below.contains(r) && !below.contains(c.id)) {
          below.add(c.id);
          grew = true;
        }
      }
    }
    final list = _colleagues.where((c) => !below.contains(c.id)).toList()
      ..sort((a, b) {
        final ra = a.jobLevelRank ?? 999;
        final rb = b.jobLevelRank ?? 999;
        if (ra != rb) return ra.compareTo(rb);
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return list;
  }

  Future<void> _pickLevel() async {
    final picked = await showUaOptionSheet(
      context: context,
      title: 'Cargo',
      subtitle: 'Escada de cargos da imobiliária',
      accent: widget.accent,
      currentId: widget.jobLevelId,
      options: [
        const UaOption(id: null, title: 'Sem cargo'),
        for (final l in _levels) UaOption(id: l.id, title: l.name),
      ],
    );
    if (picked == null || !mounted) return;
    widget.onChanged(picked.id, widget.reportsToUserId);
  }

  Future<void> _pickSuperior() async {
    final picked = await showUaOptionSheet(
      context: context,
      title: 'Superior direto',
      subtitle: 'A quem esta pessoa responde',
      accent: widget.accent,
      currentId: widget.reportsToUserId,
      options: [
        const UaOption(id: null, title: 'Sem superior'),
        for (final s in _superiors)
          UaOption(id: s.id, title: s.name, subtitle: s.jobLevelName),
      ],
    );
    if (picked == null || !mounted) return;
    widget.onChanged(widget.jobLevelId, picked.id);
  }

  @override
  Widget build(BuildContext context) {
    String? levelName;
    for (final l in _levels) {
      if (l.id == widget.jobLevelId) levelName = l.name;
    }
    String? superiorName;
    for (final c in _colleagues) {
      if (c.id == widget.reportsToUserId) superiorName = c.name;
    }
    final level = UaSelectField(
      label: 'Cargo',
      value: _loading ? null : (levelName ?? 'Sem cargo'),
      icon: LucideIcons.idCard,
      accent: widget.accent,
      loading: _loading,
      enabled: widget.enabled,
      onTap: _pickLevel,
    );
    final superior = UaSelectField(
      label: 'Superior direto',
      value: _loading ? null : (superiorName ?? 'Sem superior'),
      icon: LucideIcons.userCog,
      accent: widget.accent,
      loading: _loading,
      enabled: widget.enabled,
      onTap: _pickSuperior,
    );
    return UaTwoCols(left: level, right: superior);
  }
}
