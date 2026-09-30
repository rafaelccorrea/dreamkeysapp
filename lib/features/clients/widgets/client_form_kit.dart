import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';

/// Peças do formulário de cliente (cadastro, edição e cônjuge) na gramática
/// aprovada da ficha de venda: campos `filled` leves com rótulo dentro do
/// campo, 2 colunas quando cabe, chips tonais, seções com cabeçalho e botões
/// com semântica (Cancelar neutro, confirmar em verde ou na marca).

// ─── Cores ──────────────────────────────────────────────────────────────────

/// Cor do formulário = vermelho da marca (sem paleta por seção: a identidade
/// de cada bloco vem do ícone e do título).
Color clientFormAccent(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;

/// Verde de confirmação (Salvar).
Color clientFormSuccess(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? AppColors.status.successDarkMode
        : AppColors.status.success;

/// Vermelho de erro e de ação destrutiva.
Color clientFormDanger(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;

/// Tema local dos campos: filled com o fill de input do app (legível sobre o
/// branco), sem borda em repouso, foco e cursor na marca, erro em vermelho.
/// Campos, selects e datas herdam daqui — ficam idênticos.
ThemeData clientFormTheme(BuildContext context) {
  final base = Theme.of(context);
  final isDark = base.brightness == Brightness.dark;
  final accent = clientFormAccent(context);
  final danger = clientFormDanger(context);
  final muted = ThemeHelpers.textSecondaryColor(context);
  final fill = isDark
      ? AppColors.background.backgroundTertiaryDarkMode
      : AppColors.background.backgroundTertiary;
  OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: width == 0
            ? BorderSide.none
            : BorderSide(color: color, width: width),
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
        color: accent,
        fontWeight: FontWeight.w700,
        fontSize: 13.5,
      ),
      hintStyle: TextStyle(
        color: muted.withValues(alpha: 0.75),
        fontWeight: FontWeight.w500,
      ),
      helperStyle: TextStyle(color: muted, fontSize: 11.5, height: 1.3),
      prefixStyle: TextStyle(
        color: ThemeHelpers.textColor(context),
        fontWeight: FontWeight.w700,
      ),
      suffixStyle: TextStyle(color: muted, fontWeight: FontWeight.w700),
      errorStyle: TextStyle(
        color: danger,
        fontWeight: FontWeight.w600,
        fontSize: 11.5,
        height: 1.25,
      ),
      errorMaxLines: 3,
      border: border(Colors.transparent, 0),
      enabledBorder: border(Colors.transparent, 0),
      disabledBorder: border(Colors.transparent, 0),
      focusedBorder: border(accent, 1.6),
      errorBorder: border(danger.withValues(alpha: 0.75), 1.2),
      focusedErrorBorder: border(danger, 1.6),
    ),
  );
}

// ─── Campos ─────────────────────────────────────────────────────────────────

/// Rótulo de campo; o asterisco dos obrigatórios sai na cor da marca.
class ClientFieldLabel extends StatelessWidget {
  const ClientFieldLabel(this.text, {super.key, this.isRequired = false});

  final String text;
  final bool isRequired;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: text,
        children: [
          if (isRequired)
            TextSpan(
              text: ' *',
              style: TextStyle(
                color: clientFormAccent(context),
                fontWeight: FontWeight.w900,
              ),
            ),
        ],
      ),
      semanticsLabel: isRequired ? '$text, obrigatório' : null,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Campo de texto do formulário — visual herdado de [clientFormTheme].
class ClientFormField extends StatelessWidget {
  const ClientFormField({
    super.key,
    required this.controller,
    required this.label,
    this.isRequired = false,
    this.hint,
    this.helper,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
    this.onChanged,
    this.maxLines = 1,
    this.maxLength,
    this.prefixText,
    this.suffixText,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String label;
  final bool isRequired;
  final String? hint;
  final String? helper;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final int? maxLength;
  final String? prefixText;
  final String? suffixText;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      onChanged: onChanged,
      minLines: 1,
      maxLines: maxLines,
      maxLength: maxLength,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: ThemeHelpers.textColor(context),
          ),
      decoration: InputDecoration(
        label: ClientFieldLabel(label, isRequired: isRequired),
        hintText: hint,
        helperText: helper,
        helperMaxLines: 3,
        counterText: maxLength != null ? '' : null,
        prefixText: prefixText,
        suffixText: suffixText,
        alignLabelWithHint: maxLines > 1,
      ),
    );
  }
}

/// Duas colunas quando cabem; em tela estreita (ou texto ampliado) empilha.
/// [minColumnWidth] é a largura mínima da coluna mais estreita com texto em
/// 100% — cresce junto com a escala de texto do aparelho.
class ClientFormRow2 extends StatelessWidget {
  const ClientFormRow2({
    super.key,
    required this.left,
    required this.right,
    this.leftFlex = 1,
    this.rightFlex = 1,
    this.minColumnWidth = 140,
    this.gap = 12,
  });

  final Widget left;
  final Widget right;
  final int leftFlex;
  final int rightFlex;
  final double minColumnWidth;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrowFlex = leftFlex < rightFlex ? leftFlex : rightFlex;
        final narrowest = (constraints.maxWidth - gap) *
            narrowFlex /
            (leftFlex + rightFlex);
        if (narrowest < minColumnWidth * scale) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [left, SizedBox(height: gap), right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: leftFlex, child: left),
            SizedBox(width: gap),
            Expanded(flex: rightFlex, child: right),
          ],
        );
      },
    );
  }
}

// ─── Rótulos e faixas ───────────────────────────────────────────────────────

/// Faixa de subgrupo dentro de uma seção (ícone + título + filete).
class ClientFormBand extends StatelessWidget {
  const ClientFormBand(
    this.title, {
    super.key,
    this.icon,
    this.topSpacing = 18,
  });

  final String title;
  final IconData? icon;
  final double topSpacing;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: EdgeInsets.only(top: topSpacing, bottom: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: muted),
                const SizedBox(width: 7),
              ],
              // Título com teto de 80%: o filete sempre vai até a margem.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * 0.8,
                ),
                child: Text(
                  title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.3,
                    color: ThemeHelpers.textColor(context),
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
            ],
          );
        },
      ),
    );
  }
}

/// Rótulo de um grupo de escolhas (chips), com apoio opcional.
class ClientFormCaption extends StatelessWidget {
  const ClientFormCaption(this.text, {super.key, this.hint});

  final String text;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(
              hint!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Escolhas ───────────────────────────────────────────────────────────────

/// Chip de escolha: sem seleção fica neutro; selecionado ganha fundo tonal e
/// borda na cor ([color], padrão = marca). Texto sempre na cor de texto do
/// tema — legível mesmo com tons claros como o âmbar.
class ClientChoiceChip extends StatelessWidget {
  const ClientChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone = color ?? clientFormAccent(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final radius = BorderRadius.circular(999);
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? tone.withValues(alpha: isDark ? 0.22 : 0.12)
                : Colors.transparent,
            borderRadius: radius,
            border: Border.all(
              color: selected
                  ? tone.withValues(alpha: 0.65)
                  : ThemeHelpers.borderColor(context),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: selected ? tone : muted),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? ThemeHelpers.textColor(context)
                            : muted,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Linha com interruptor, flush (sem caixa): ícone tonal que acende quando
/// ligado, título, apoio e o switch com trilho na marca.
class ClientSwitchRow extends StatelessWidget {
  const ClientSwitchRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = clientFormAccent(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: value
                      ? accent.withValues(alpha: isDark ? 0.22 : 0.12)
                      : ThemeHelpers.borderLightColor(context),
                ),
                child: Icon(icon, size: 17, color: value ? accent : muted),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch.adaptive(
                value: value,
                onChanged: onChanged,
                activeTrackColor: accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Seções ─────────────────────────────────────────────────────────────────

enum ClientSummaryTone { filled, error }

/// Resumo mostrado no cabeçalho de uma seção fechada ("o que já tem aqui").
class ClientSectionSummary {
  const ClientSectionSummary(this.text) : tone = ClientSummaryTone.filled;
  const ClientSectionSummary.error(this.text) : tone = ClientSummaryTone.error;

  final String text;
  final ClientSummaryTone tone;
}

/// Seção do formulário, flush: filete no topo, ícone tonal, título e uma
/// linha de apoio. Aberta, a linha explica o que há dentro; fechada, mostra
/// o resumo do que já foi preenchido (ou, vazia, continua explicando).
///
/// Fechada, o conteúdo sai da árvore — mesmo comportamento do ExpansionTile
/// que ela substitui.
class ClientFormSection extends StatefulWidget {
  const ClientFormSection({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.child,
    this.summary,
    this.collapsible = true,
    this.initiallyExpanded = false,
    this.forceExpanded = false,
    this.showDivider = true,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget child;

  /// Lido a cada desenho do cabeçalho fechado; `null` = mostra [description].
  final ClientSectionSummary? Function()? summary;
  final bool collapsible;
  final bool initiallyExpanded;

  /// Ao virar `true`, abre a seção (ex.: erro que mora dentro dela).
  final bool forceExpanded;
  final bool showDivider;

  /// Selo curto ao lado do título (ex.: "Obrigatório").
  final String? badge;

  @override
  State<ClientFormSection> createState() => _ClientFormSectionState();

  /// Abre a seção que contém [fieldContext] e as que a contêm (campo com
  /// erro de validação dentro de uma seção recolhida).
  static void revealAncestors(BuildContext fieldContext) {
    var state =
        fieldContext.findAncestorStateOfType<_ClientFormSectionState>();
    while (state != null) {
      state._open();
      state = state.context.findAncestorStateOfType<_ClientFormSectionState>();
    }
  }
}

class _ClientFormSectionState extends State<ClientFormSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _curve;
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = !widget.collapsible ||
        widget.initiallyExpanded ||
        widget.forceExpanded;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: _expanded ? 1 : 0,
    );
    _curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void didUpdateWidget(covariant ClientFormSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final mustOpen = !widget.collapsible ||
        (widget.forceExpanded && !oldWidget.forceExpanded);
    if (mustOpen && !_expanded) {
      _expanded = true;
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _open() {
    if (_expanded || !widget.collapsible) return;
    setState(() => _expanded = true);
    _controller.forward();
  }

  void _toggle() {
    if (!widget.collapsible) return;
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _controller.forward();
    } else {
      FocusScope.of(context).unfocus();
      _controller.reverse().then<void>((_) {
        // Terminou de fechar: redesenha para esconder o conteúdo.
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final closed = !_expanded && _controller.isDismissed;
    // Fechada, a seção NÃO sai da árvore: fica Offstage (sem pintar, sem
    // toque, sem foco, sem animação) para os campos continuarem no Form e
    // validarem no Salvar — antes, CPF/e-mail inválido recolhido passava.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeader(context),
        Offstage(
          offstage: closed,
          child: TickerMode(
            enabled: !closed,
            child: ExcludeFocus(
              excluding: closed,
              child: SizeTransition(
                sizeFactor: _curve,
                axisAlignment: -1,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 22),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = clientFormAccent(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final summary =
        !_expanded && widget.summary != null ? widget.summary!() : null;
    var lineColor = muted;
    var lineWeight = FontWeight.w500;
    if (summary != null) {
      lineWeight = FontWeight.w700;
      lineColor = summary.tone == ClientSummaryTone.error
          ? clientFormDanger(context)
          : ThemeHelpers.textColor(context);
    }

    final content = Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: widget.showDivider
          ? BoxDecoration(
              border: Border(
                top: BorderSide(color: ThemeHelpers.borderColor(context)),
              ),
            )
          : null,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.18 : 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(widget.icon, size: 18, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: ThemeHelpers.textColor(context),
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    if (widget.badge != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: isDark ? 0.2 : 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          widget.badge!.toUpperCase(),
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                            color: accent,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  summary?.text ?? widget.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: lineColor,
                    fontWeight: lineWeight,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          if (widget.collapsible) ...[
            const SizedBox(width: 8),
            AnimatedRotation(
              turns: _expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: _expanded ? accent : muted,
              ),
            ),
          ],
        ],
      ),
    );

    if (!widget.collapsible) return content;
    return Semantics(
      button: true,
      expanded: _expanded,
      child: InkWell(onTap: _toggle, child: content),
    );
  }
}

// ─── Ações ──────────────────────────────────────────────────────────────────

/// Par Cancelar (neutro) + confirmar (cor semântica), rótulos que encolhem
/// em vez de quebrar. [framed] = barra fixa com filete e fundo; sem moldura
/// é a versão que entra no fim da rolagem em tela baixa.
class ClientFormActionBar extends StatelessWidget {
  const ClientFormActionBar({
    super.key,
    required this.confirmLabel,
    required this.confirmIcon,
    required this.confirmColor,
    required this.onConfirm,
    required this.onCancel,
    this.cancelLabel = 'Cancelar',
    this.busy = false,
    this.busyLabel = 'Salvando…',
    this.framed = true,
    this.horizontalPadding = 16,
    this.maxContentWidth = 720,
  });

  final String confirmLabel;
  final IconData confirmIcon;
  final Color confirmColor;
  final VoidCallback onConfirm;
  final VoidCallback? onCancel;
  final String cancelLabel;
  final bool busy;
  final String busyLabel;
  final bool framed;
  final double horizontalPadding;
  final double maxContentWidth;

  @override
  Widget build(BuildContext context) {
    final buttons = Row(
      children: [
        Expanded(
          flex: 2,
          child: OutlinedButton(
            onPressed: busy ? null : onCancel,
            style: OutlinedButton.styleFrom(
              foregroundColor: ThemeHelpers.textSecondaryColor(context),
              side: BorderSide(color: ThemeHelpers.borderColor(context)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                cancelLabel,
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: FilledButton(
            onPressed: busy ? null : onConfirm,
            style: FilledButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: confirmColor.withValues(alpha: 0.55),
              disabledForegroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (busy)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  else
                    Icon(confirmIcon, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    busy ? busyLabel : confirmLabel,
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );

    if (!framed) return buttons;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        10,
        horizontalPadding,
        10 + safeBottom,
      ),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border(
          top: BorderSide(color: ThemeHelpers.borderColor(context)),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxContentWidth),
          child: buttons,
        ),
      ),
    );
  }
}
