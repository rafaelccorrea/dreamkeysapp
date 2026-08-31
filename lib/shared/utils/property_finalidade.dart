/// Finalidade do imóvel — a regra que decide se ele é anunciado para venda,
/// para locação ou para os dois.
///
/// Porte fiel de `imobx-front/src/utils/propertyFinalidade.ts` e de
/// `imobx/src/properties/utils/property-finalidade.util.ts`. As três pontas
/// precisam concordar: a listagem pública, os feeds de portais e a desativação
/// parcial derivam daqui.
///
/// Existem DOIS eixos no cadastro e eles podem divergir:
///  - `finalidade`: o recorte declarado. É o que manda nos filtros, no site
///    público e na desativação parcial.
///  - `salePrice` / `rentPrice`: valores preenchidos na ficha.
///
/// Cadastro antigo não tem `finalidade` gravada (null) e nesses casos ela é
/// DERIVADA dos preços. Quando existe, ela VENCE: um imóvel marcado só para
/// locação que ficou com preço de venda preenchido continua fora das buscas de
/// venda — e a tela precisa dizer isso em vez de anunciar um valor que não vale.
library;

import 'package:flutter/material.dart';

/// As três finalidades possíveis. O `value` é o que viaja para a API
/// (`create-property.dto.ts` aceita `'venda' | 'locacao' | 'ambos'`).
enum PropertyFinalidade {
  venda('venda', 'Venda', 'VENDA'),
  locacao('locacao', 'Locação', 'LOCAÇÃO'),
  ambos('ambos', 'Venda e locação', 'VENDA E LOCAÇÃO');

  const PropertyFinalidade(this.value, this.label, this.shortLabel);

  /// Valor enviado e recebido da API.
  final String value;

  /// Rótulo de leitura ("Venda e locação").
  final String label;

  /// Rótulo curto em caixa alta, para pastilhas e chips.
  final String shortLabel;

  /// O imóvel é anunciado para venda? (e portanto o valor de venda vale)
  bool get anunciaVenda =>
      this == PropertyFinalidade.venda || this == PropertyFinalidade.ambos;

  /// O imóvel é anunciado para locação? (e portanto o aluguel vale)
  bool get anunciaLocacao =>
      this == PropertyFinalidade.locacao || this == PropertyFinalidade.ambos;

  /// Frase curta do que a escolha implica, usada no cartão selecionado.
  String get consequencia {
    switch (this) {
      case PropertyFinalidade.venda:
        return 'Anunciado só para compra.';
      case PropertyFinalidade.locacao:
        return 'Anunciado só para alugar.';
      case PropertyFinalidade.ambos:
        return 'Anunciado nas duas pontas ao mesmo tempo.';
    }
  }

  static PropertyFinalidade? tryParse(Object? raw) {
    final s = raw?.toString().trim().toLowerCase();
    if (s == null || s.isEmpty) return null;
    for (final f in PropertyFinalidade.values) {
      if (f.value == s) return f;
    }
    return null;
  }
}

/// Tinta semântica de cada finalidade. Azul = compra, âmbar = posse/chave —
/// os mesmos hex do web (`CaptorRoleSlots.tsx`), com o degrau 400 no escuro
/// para manter contraste sobre o grafite.
///
/// `ambos` NÃO ganha cor própria: usa as duas em gradiente. Uma terceira cor
/// aqui seria decoração, não significado.
class FinalidadeTint {
  const FinalidadeTint._();

  static const Color vendaLight = Color(0xFF2563EB);
  static const Color vendaDark = Color(0xFF60A5FA);
  static const Color locacaoLight = Color(0xFFD97706);
  static const Color locacaoDark = Color(0xFFFBBF24);

  static Color venda(bool isDark) => isDark ? vendaDark : vendaLight;
  static Color locacao(bool isDark) => isDark ? locacaoDark : locacaoLight;

  /// Cor principal de uma finalidade. Para `ambos` devolve o azul — quem
  /// carrega o "são os dois" é o gradiente, não uma cor única.
  static Color of(PropertyFinalidade f, bool isDark) =>
      f == PropertyFinalidade.locacao ? locacao(isDark) : venda(isDark);

  /// Gradiente do "ambos": azul da venda → âmbar da locação.
  static LinearGradient gradient(bool isDark) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [venda(isDark), locacao(isDark)],
      );
}

/// Ícone de cada finalidade — Material rounded, que é o vocabulário do
/// formulário de imóvel (o resto do app usa lucide).
IconData finalidadeIcon(PropertyFinalidade f) {
  switch (f) {
    case PropertyFinalidade.venda:
      return Icons.sell_rounded;
    case PropertyFinalidade.locacao:
      return Icons.vpn_key_rounded;
    case PropertyFinalidade.ambos:
      return Icons.swap_horiz_rounded;
  }
}

bool _temValor(Object? valor) {
  if (valor == null) return false;
  if (valor is num) return valor > 0;
  final n = double.tryParse(valor.toString().replaceAll(',', '.'));
  return n != null && n > 0;
}

/// Finalidade efetiva: a gravada ou, em cadastro antigo, a derivada dos preços.
/// `null` quando não há finalidade nem preço nenhum — aí não há o que deduzir.
PropertyFinalidade? finalidadeEfetiva({
  PropertyFinalidade? finalidade,
  Object? salePrice,
  Object? rentPrice,
}) {
  if (finalidade != null) return finalidade;
  final venda = _temValor(salePrice);
  final locacao = _temValor(rentPrice);
  if (venda && locacao) return PropertyFinalidade.ambos;
  if (venda) return PropertyFinalidade.venda;
  if (locacao) return PropertyFinalidade.locacao;
  return null;
}

/// O imóvel anuncia venda? Sem finalidade gravada, cai no fallback derivado.
bool anunciaVenda({
  PropertyFinalidade? finalidade,
  Object? salePrice,
  Object? rentPrice,
}) {
  final f = finalidadeEfetiva(
    finalidade: finalidade,
    salePrice: salePrice,
    rentPrice: rentPrice,
  );
  return f?.anunciaVenda ?? false;
}

/// O imóvel anuncia locação? Sem finalidade gravada, cai no fallback derivado.
bool anunciaLocacao({
  PropertyFinalidade? finalidade,
  Object? salePrice,
  Object? rentPrice,
}) {
  final f = finalidadeEfetiva(
    finalidade: finalidade,
    salePrice: salePrice,
    rentPrice: rentPrice,
  );
  return f?.anunciaLocacao ?? false;
}

/// Valor preenchido que a finalidade NÃO reconhece — ex.: preço de venda num
/// imóvel marcado só para locação. Serve para a tela explicar a divergência em
/// vez de simplesmente esconder (ou apagar) o número.
({bool venda, bool locacao}) valorForaDaFinalidade({
  PropertyFinalidade? finalidade,
  Object? salePrice,
  Object? rentPrice,
}) {
  return (
    venda: _temValor(salePrice) &&
        !anunciaVenda(
          finalidade: finalidade,
          salePrice: salePrice,
          rentPrice: rentPrice,
        ),
    locacao: _temValor(rentPrice) &&
        !anunciaLocacao(
          finalidade: finalidade,
          salePrice: salePrice,
          rentPrice: rentPrice,
        ),
  );
}
