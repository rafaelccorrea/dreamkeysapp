import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';

/// Código de 6 dígitos em caixas, com UM campo de texto por baixo.
///
/// As caixas são só a leitura visual; quem recebe o teclado é um campo único
/// e invisível que cobre a área. Assim colar o código copiado do autenticador,
/// o preenchimento automático do sistema (`oneTimeCode`) e apagar funcionam
/// como num campo comum — com 6 campos de 1 dígito, colar não funcionava.
///
/// A largura das caixas sai da largura disponível (320dp cabe) e o dígito
/// fica num FittedBox, então texto a 130% não estoura a caixa.
class TwoFactorCodeInput extends StatefulWidget {
  static const int length = 6;

  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool enabled;
  final bool autofocus;

  /// Pinta as caixas de erro até a pessoa digitar de novo (quem decide é a tela).
  final bool hasError;

  /// Chamado quando o código chega aos 6 dígitos.
  final ValueChanged<String>? onCompleted;

  /// Botão "concluído" do teclado.
  final ValueChanged<String>? onSubmitted;

  /// Espaço extra ao rolar até o campo — deixa o botão de baixo à vista com o
  /// teclado aberto.
  final EdgeInsets scrollPadding;

  const TwoFactorCodeInput({
    super.key,
    required this.controller,
    this.focusNode,
    this.enabled = true,
    this.autofocus = false,
    this.hasError = false,
    this.onCompleted,
    this.onSubmitted,
    this.scrollPadding = const EdgeInsets.only(bottom: 160),
  });

  @override
  State<TwoFactorCodeInput> createState() => _TwoFactorCodeInputState();
}

class _TwoFactorCodeInputState extends State<TwoFactorCodeInput> {
  FocusNode? _ownFocus;

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant TwoFactorCodeInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownFocus)?.removeListener(_onFocus);
      _focus.addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    _focus.removeListener(_onFocus);
    _ownFocus?.dispose();
    super.dispose();
  }

  String _lastNotified = '';

  void _onText() {
    if (!mounted) return;
    setState(() {});
    final code = widget.controller.text;
    if (code.length == TwoFactorCodeInput.length && code != _lastNotified) {
      _lastNotified = code;
      widget.onCompleted?.call(code);
    } else if (code.length < TwoFactorCodeInput.length) {
      _lastNotified = '';
    }
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final errorColor =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final fill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    final border = ThemeHelpers.borderColor(context);
    final textColor = ThemeHelpers.textColor(context);

    final code = widget.controller.text;
    final focused = _focus.hasFocus && widget.enabled;
    // Caixa "da vez": a próxima a preencher (ou a última, com o código cheio).
    final current = code.length.clamp(0, TwoFactorCodeInput.length - 1);

    return Semantics(
      label: 'Código de 6 dígitos',
      textField: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 360.0;
          final narrow = maxW < 300;
          final gap = narrow ? 6.0 : 8.0;
          // 3 + 3 com um respiro maior no meio: lê-se "123 456".
          final middleGap = gap * 2;
          // Teto de 56 em tela larga; sem piso — em tela estreitíssima a caixa
          // encolhe em vez de estourar a linha.
          final rawW =
              (maxW - gap * 4 - middleGap) / TwoFactorCodeInput.length;
          final boxW = rawW > 56.0 ? 56.0 : rawW;
          final boxH = (boxW * 1.22).clamp(48.0, 64.0);

          Widget box(int i) {
            final digit = i < code.length ? code[i] : '';
            final isCurrent = focused && i == current;
            final Color borderColor;
            final double borderWidth;
            if (widget.hasError) {
              borderColor = errorColor;
              borderWidth = 1.5;
            } else if (isCurrent) {
              borderColor = accent;
              borderWidth = 2;
            } else if (digit.isNotEmpty) {
              borderColor = textColor.withValues(alpha: 0.35);
              borderWidth = 1.2;
            } else {
              borderColor = border;
              borderWidth = 1;
            }
            return AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: boxW,
              height: boxH,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: widget.enabled ? fill : fill.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: borderWidth),
              ),
              child: digit.isNotEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          digit,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: boxW * 0.52,
                            fontWeight: FontWeight.w700,
                            color: widget.hasError ? errorColor : textColor,
                            height: 1,
                          ),
                        ),
                      ),
                    )
                  : (isCurrent
                        // Traço de cursor na caixa da vez (estático, sem piscar).
                        ? Container(
                            width: 2,
                            height: boxH * 0.38,
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          )
                        : null),
            );
          }

          final boxes = <Widget>[];
          for (var i = 0; i < TwoFactorCodeInput.length; i++) {
            if (i > 0) {
              boxes.add(SizedBox(width: i == 3 ? middleGap : gap));
            }
            boxes.add(box(i));
          }

          return SizedBox(
            height: boxH,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: boxes,
                ),
                // Campo real, invisível, cobrindo as caixas: toque foca,
                // toque longo oferece "Colar".
                Positioned.fill(
                  child: Opacity(
                    opacity: 0,
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _focus,
                      enabled: widget.enabled,
                      autofocus: widget.autofocus,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      autocorrect: false,
                      enableSuggestions: false,
                      showCursor: false,
                      maxLength: TwoFactorCodeInput.length,
                      scrollPadding: widget.scrollPadding,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(
                          TwoFactorCodeInput.length,
                        ),
                      ],
                      onSubmitted: widget.onSubmitted,
                      decoration: const InputDecoration(
                        counterText: '',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isCollapsed: true,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Lê a área de transferência e devolve só os dígitos, se formarem um código.
Future<String?> lerCodigoDaAreaDeTransferencia() async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  final digits = (data?.text ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.length < TwoFactorCodeInput.length) return null;
  return digits.substring(0, TwoFactorCodeInput.length);
}
