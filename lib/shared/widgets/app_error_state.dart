import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/theme_helpers.dart';
import '../utils/error_cause.dart';

/// Estado de erro padrão do app — a peça única que substitui as dezenas de
/// telas de erro improvisadas, cada uma com seu ícone e seu "Ops!".
///
/// Estrutura (de cima para baixo): selo tonal · título · **causa real** ·
/// próximo passo · ação. O detalhe técnico fica recolhido: serve ao chamado
/// de suporte sem transformar a tela num despejo de stack trace.
///
/// A cor NÃO é decorativa: vem da família do erro ([ErrorCause.tone]), então
/// permissão (violeta), conexão (âmbar) e falha de servidor (rosa) se
/// distinguem antes mesmo da leitura.
class AppErrorState extends StatefulWidget {
  final ErrorCause cause;

  /// Recarregar. Quando nulo — ou quando o erro não é repetível — o botão
  /// não aparece: oferecer "tentar novamente" para falta de permissão é
  /// convidar o usuário a bater na mesma porta.
  final Future<void> Function()? onRetry;

  /// Ação alternativa (ex.: "Entrar novamente" numa sessão expirada).
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// Compacto para dentro de listas/abas; o padrão centraliza na tela.
  final bool dense;

  const AppErrorState({
    super.key,
    required this.cause,
    this.onRetry,
    this.secondaryLabel,
    this.onSecondary,
    this.dense = false,
  });

  /// Atalho: monta o diagnóstico a partir da resposta da API.
  factory AppErrorState.fromApi({
    Key? key,
    String? message,
    int statusCode = 0,
    Object? error,
    Future<void> Function()? onRetry,
    String? secondaryLabel,
    VoidCallback? onSecondary,
    bool dense = false,
  }) {
    return AppErrorState(
      key: key,
      cause: ErrorCause.fromApi(
        message: message,
        statusCode: statusCode,
        error: error,
      ),
      onRetry: onRetry,
      secondaryLabel: secondaryLabel,
      onSecondary: onSecondary,
      dense: dense,
    );
  }

  @override
  State<AppErrorState> createState() => _AppErrorStateState();
}

class _AppErrorStateState extends State<AppErrorState> {
  bool _verDetalhe = false;
  bool _recarregando = false;

  Future<void> _retry() async {
    final acao = widget.onRetry;
    if (acao == null || _recarregando) return;
    setState(() => _recarregando = true);
    try {
      await acao();
    } finally {
      if (mounted) setState(() => _recarregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cause;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final mostrarRetry = widget.onRetry != null && c.retryable;

    final corpo = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Selo: quadrado tonal com anel — mesma família dos ícones de seção.
        Container(
          width: widget.dense ? 46 : 58,
          height: widget.dense ? 46 : 58,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.dense ? 15 : 18),
            color: c.tone.withValues(alpha: isDark ? 0.18 : 0.10),
            border: Border.all(color: c.tone.withValues(alpha: 0.30)),
          ),
          child: Icon(c.icon, size: widget.dense ? 21 : 26, color: c.tone),
        ),
        SizedBox(height: widget.dense ? 12 : 16),
        Text(
          c.title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: widget.dense ? 15 : 17,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.2,
            color: textColor,
          ),
        ),
        const SizedBox(height: 8),
        // A CAUSA — o motivo pelo qual esta tela existe.
        Text(
          c.cause,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: widget.dense ? 12.5 : 13.5,
            height: 1.45,
            fontWeight: FontWeight.w500,
            color: secondary,
          ),
        ),
        const SizedBox(height: 14),
        // Próximo passo, destacado numa faixa tonal discreta.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: c.tone.withValues(alpha: isDark ? 0.12 : 0.07),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: c.tone.withValues(alpha: 0.22)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.arrowRight, size: 14, color: c.tone),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  c.action,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                    color: textColor.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (mostrarRetry || widget.onSecondary != null) ...[
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (mostrarRetry)
                ElevatedButton.icon(
                  onPressed: _recarregando ? null : _retry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.tone,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: c.tone.withValues(alpha: 0.4),
                    disabledForegroundColor:
                        Colors.white.withValues(alpha: 0.8),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                  icon: _recarregando
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(LucideIcons.rotateCw, size: 15),
                  label: Text(_recarregando ? 'Carregando…' : 'Tentar de novo'),
                ),
              if (widget.onSecondary != null)
                OutlinedButton(
                  onPressed: widget.onSecondary,
                  style: OutlinedButton.styleFrom(
                    // Nunca vermelho por padrão: a cor da ação secundária
                    // acompanha a família do erro.
                    foregroundColor: c.tone,
                    side: BorderSide(color: c.tone.withValues(alpha: 0.45)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                  child: Text(widget.secondaryLabel ?? 'Voltar'),
                ),
            ],
          ),
        ],
        if (c.technical != null) ...[
          const SizedBox(height: 14),
          _DetalheTecnico(
            texto: c.technical!,
            aberto: _verDetalhe,
            tone: c.tone,
            onToggle: () => setState(() => _verDetalhe = !_verDetalhe),
          ),
        ],
      ],
    );

    if (widget.dense) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        child: corpo,
      );
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: corpo,
        ),
      ),
    );
  }
}

/// Linha técnica recolhida — some da vista, mas fica a um toque para quem
/// precisa abrir chamado. Copiável, porque ninguém transcreve stack trace.
class _DetalheTecnico extends StatelessWidget {
  final String texto;
  final bool aberto;
  final Color tone;
  final VoidCallback onToggle;

  const _DetalheTecnico({
    required this.texto,
    required this.aberto,
    required this.tone,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton.icon(
          onPressed: onToggle,
          style: TextButton.styleFrom(
            foregroundColor: secondary,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: Icon(
            aberto ? LucideIcons.chevronUp : LucideIcons.chevronDown,
            size: 13,
          ),
          label: Text(
            aberto ? 'Ocultar detalhe técnico' : 'Ver detalhe técnico',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: aberto
              ? Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: ThemeHelpers.borderColor(context)
                          .withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SelectableText(
                          texto,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.4,
                            fontFamily: 'monospace',
                            color: secondary,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copiar',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: texto));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Detalhe copiado'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        icon: Icon(LucideIcons.copy, size: 14, color: tone),
                      ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
