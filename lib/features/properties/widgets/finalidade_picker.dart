import 'package:flutter/material.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/utils/property_finalidade.dart';

/// Seletor da finalidade do imóvel — venda, locação ou as duas pontas.
///
/// É a primeira decisão do cadastro porque é a única que muda o formulário
/// inteiro: quais preços existem, quais são obrigatórios e o que a ficha
/// anuncia. Por isso os três cartões ocupam a largura cheia, empilhados, em
/// vez do grid de duas colunas usado pelo tipo do imóvel — aquele é uma
/// escolha de rótulo, esta é uma escolha de regra.
///
/// Herda a gramática do `_modeCard` da pré-criação (rádio + medalhão tonal +
/// título + descrição) e acrescenta o micro-chip de consequência, que diz o
/// que a etapa de valores vai cobrar.
class FinalidadePicker extends StatelessWidget {
  final PropertyFinalidade? value;
  final ValueChanged<PropertyFinalidade> onChanged;

  /// Finalidade deduzida dos preços de um cadastro antigo (não escolhida por
  /// ninguém). Marca o cartão com selo neutro em vez da tinta cheia — a cor
  /// fica reservada para a escolha confirmada.
  final bool inferido;

  const FinalidadePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.inferido = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < PropertyFinalidade.values.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _FinalidadeCard(
            finalidade: PropertyFinalidade.values[i],
            selected: value == PropertyFinalidade.values[i],
            inferido: inferido && value == PropertyFinalidade.values[i],
            onTap: () => onChanged(PropertyFinalidade.values[i]),
          ),
        ],
      ],
    );
  }
}

class _FinalidadeCard extends StatelessWidget {
  final PropertyFinalidade finalidade;
  final bool selected;
  final bool inferido;
  final VoidCallback onTap;

  const _FinalidadeCard({
    required this.finalidade,
    required this.selected,
    required this.inferido,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final ehAmbos = finalidade == PropertyFinalidade.ambos;
    final tint = FinalidadeTint.of(finalidade, isDark);

    final fundoRepouso = isDark
        ? Colors.white.withValues(alpha: 0.035)
        : Colors.white.withValues(alpha: 0.78);
    final bordaRepouso = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : ThemeHelpers.borderColor(context).withValues(alpha: 0.45);

    // Selecionado por dedução ganha borda mais fina e fundo mais fraco: o app
    // deduziu, o corretor ainda não confirmou.
    final larguraBorda = selected ? (inferido ? 1.2 : 1.6) : 1.0;
    final fundo = selected
        ? tint.withValues(alpha: isDark ? (inferido ? 0.08 : 0.16) : (inferido ? 0.05 : 0.08))
        : fundoRepouso;

    final conteudo = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14.4),
        color: fundo,
        // O "ambos" selecionado recebe a moldura em gradiente por fora; aqui
        // dentro ele fica sem borda para as duas não se somarem.
        border: ehAmbos && selected
            ? null
            : Border.all(
                color: selected
                    ? tint.withValues(alpha: inferido ? 0.55 : 1.0)
                    : bordaRepouso,
                width: larguraBorda,
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _radio(context, tint: tint, ehAmbos: ehAmbos, isDark: isDark),
          const SizedBox(width: 12),
          _medalhao(context, tint: tint, ehAmbos: ehAmbos, isDark: isDark),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        finalidade.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                    ),
                    if (inferido) ...[
                      const SizedBox(width: 8),
                      _seloInferido(context, isDark: isDark),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  finalidade.consequencia,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    height: 1.35,
                  ),
                ),
                // A consequência prática nasce dentro do cartão escolhido e
                // sai em fade — nunca some seco.
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topLeft,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 160),
                    opacity: selected ? 1 : 0,
                    // O filho fica MONTADO nos dois estados: se ele virar
                    // SizedBox no mesmo frame, a opacidade não tem o que
                    // desvanecer e a saída fica seca.
                    child: Padding(
                      padding: EdgeInsets.only(top: selected ? 9 : 0),
                      child: selected
                          ? _chipsConsequencia(context, isDark: isDark)
                          : const SizedBox(width: double.infinity),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        // A moldura de 1.6 existe em TODOS os cartões (transparente quando
        // não é o "ambos" selecionado): sem isso o cartão pulava 3,2dp no
        // instante da escolha.
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(1.6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: ehAmbos && selected
                ? FinalidadeTint.gradient(isDark)
                : null,
          ),
          child: conteudo,
        ),
      ),
    );
  }

  Widget _radio(
    BuildContext context, {
    required Color tint,
    required bool ehAmbos,
    required bool isDark,
  }) {
    // No "ambos" o anel fica neutro: quem diz que são as duas pontas é o
    // gradiente da moldura e os dois chips, não um anel de cor única.
    final cor = selected
        ? (ehAmbos ? ThemeHelpers.textColor(context) : tint)
        : (isDark
            ? Colors.white.withValues(alpha: 0.30)
            : ThemeHelpers.borderColor(context).withValues(alpha: 0.65));
    return Container(
      width: 22,
      height: 22,
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? cor.withValues(alpha: 0.12) : Colors.transparent,
        border: Border.all(color: cor, width: 2),
      ),
      alignment: Alignment.center,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: selected ? 10 : 0,
        height: selected ? 10 : 0,
        decoration: BoxDecoration(shape: BoxShape.circle, color: cor),
      ),
    );
  }

  Widget _medalhao(
    BuildContext context, {
    required Color tint,
    required bool ehAmbos,
    required bool isDark,
  }) {
    final icone = Icon(finalidadeIcon(finalidade), size: 17, color: tint);
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        // O ícone já nasce tintado no repouso — a cor é significado, não
        // recompensa por ter clicado. O que muda é a força do fundo.
        gradient: ehAmbos
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  FinalidadeTint.venda(isDark)
                      .withValues(alpha: isDark ? 0.18 : 0.10),
                  FinalidadeTint.locacao(isDark)
                      .withValues(alpha: isDark ? 0.18 : 0.10),
                ],
              )
            : null,
        color: ehAmbos ? null : tint.withValues(alpha: isDark ? 0.18 : 0.10),
      ),
      alignment: Alignment.center,
      child: ehAmbos
          ? ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (rect) =>
                  FinalidadeTint.gradient(isDark).createShader(rect),
              child: icone,
            )
          : icone,
    );
  }

  /// O que a etapa de valores vai cobrar. No "ambos" são DOIS chips, cada um
  /// na sua cor — é aí que se vê que são as duas pontas, sem inventar uma
  /// terceira tinta.
  Widget _chipsConsequencia(BuildContext context, {required bool isDark}) {
    final chips = <Widget>[];
    if (finalidade == PropertyFinalidade.ambos) {
      chips
        ..add(_chip(context,
            texto: 'VENDA',
            cor: FinalidadeTint.venda(isDark),
            isDark: isDark))
        ..add(_chip(context,
            texto: 'ALUGUEL',
            cor: FinalidadeTint.locacao(isDark),
            isDark: isDark));
    } else {
      chips.add(
        _chip(
          context,
          texto: finalidade == PropertyFinalidade.venda
              ? 'PEDE VALOR DE VENDA'
              : 'PEDE VALOR DE ALUGUEL',
          cor: FinalidadeTint.of(finalidade, isDark),
          isDark: isDark,
        ),
      );
    }
    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }

  Widget _chip(
    BuildContext context, {
    required String texto,
    required Color cor,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        color: cor.withValues(alpha: isDark ? 0.16 : 0.10),
        border: Border.all(color: cor.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, size: 12, color: cor),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
                color: cor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Selo do cadastro antigo: ardósia neutra, nunca colorida — dedução do
  /// sistema não é escolha humana.
  Widget _seloInferido(BuildContext context, {required bool isDark}) {
    final cor = ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: isDark
            ? Colors.white.withValues(alpha: 0.10)
            : ThemeHelpers.borderColor(context).withValues(alpha: 0.30),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.22)
              : ThemeHelpers.borderColor(context).withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_rounded, size: 11, color: cor),
          const SizedBox(width: 4),
          Text(
            'INFERIDO',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
              color: cor,
            ),
          ),
        ],
      ),
    );
  }
}
