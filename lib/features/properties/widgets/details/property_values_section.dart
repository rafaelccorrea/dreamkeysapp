import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/property_service.dart';
import '../../../../shared/utils/property_finalidade.dart';
import 'property_details_kit.dart';

final NumberFormat _brl = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: r'R$',
  decimalDigits: 2,
);

/// Corpo da seção "Valores" da ficha — paridade com o
/// `PropertyDetailsValuesSection` do web. Vai dentro do molde flush da
/// página (`_buildFlushSection(title: 'Valores', …)`); monte só quando
/// [isVisible] for `true`.
///
/// - Venda e Aluguel aparecem quando preenchidos; o valor que a FINALIDADE
///   não anuncia ganha o selo "não anunciado" e a explicação do web (o número
///   continua à vista — é dado da ficha — mas não entra nas buscas nem no
///   site).
/// - Condomínio e IPTU numa linha, quando maiores que zero.
/// - Bloco "Negociação" (mesmas linhas e textos do web): aceita negociação,
///   aceita permuta (até X), mínimos de venda/aluguel e o que fazer com
///   ofertas abaixo do mínimo.
///
/// Espera só o [Property] do `GET /properties/:id` (`finalidade`, preços,
/// `condominiumFee`, `iptu`, `acceptsNegotiation`, `acceptsExchange`,
/// `exchangeMaxValue`, `minSalePrice`, `minRentPrice`,
/// `offerBelowMin(Sale|Rent)Action`).
class PropertyValuesSection extends StatelessWidget {
  const PropertyValuesSection({super.key, required this.property});

  final Property property;

  /// Há algo para mostrar (preço, taxa ou negociação).
  static bool isVisible(Property property) =>
      property.salePrice != null ||
      property.rentPrice != null ||
      _hasExtras(property) ||
      hasNegotiation(property);

  /// Mesma condição do web para o bloco "Negociação".
  static bool hasNegotiation(Property p) =>
      p.acceptsNegotiation == true ||
      p.acceptsExchange != null ||
      (p.minSalePrice ?? 0) > 0 ||
      (p.minRentPrice ?? 0) > 0 ||
      (p.offerBelowMinSaleAction ?? '').trim().isNotEmpty ||
      (p.offerBelowMinRentAction ?? '').trim().isNotEmpty;

  static bool _hasExtras(Property p) =>
      (p.condominiumFee ?? 0) > 0 || (p.iptu ?? 0) > 0;

  /// Rótulo da política de oferta abaixo do mínimo (`offerBelowActionLabel`
  /// do web). Valor desconhecido aparece como veio.
  static String offerBelowActionLabel(String? action) {
    switch ((action ?? '').trim()) {
      case 'reject':
        return 'Recusar automaticamente';
      case 'pending':
        return 'Manter pendente';
      case 'notify':
        return 'Notificar a equipe';
      default:
        return (action ?? '').trim();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = property;
    final fora = valorForaDaFinalidade(
      finalidade: PropertyFinalidade.tryParse(p.finalidade),
      salePrice: p.salePrice,
      rentPrice: p.rentPrice,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final saleTone = isDark
        ? AppColors.message.successTextDarkMode
        : AppColors.message.successText;
    final rentTone = isDark
        ? AppColors.message.warningTextDarkMode
        : AppColors.message.warningText;

    final prices = <Widget>[
      if (p.salePrice != null)
        _PriceBlock(
          label: 'Venda',
          value: _brl.format(p.salePrice),
          tone: saleTone,
          notAdvertised: fora.venda,
          notAdvertisedHint: 'O imóvel não está anunciado para venda — o '
              'valor segue guardado na ficha, mas não entra nas buscas de '
              'compra nem no site.',
        ),
      if (p.rentPrice != null)
        _PriceBlock(
          label: 'Aluguel',
          value: _brl.format(p.rentPrice),
          tone: rentTone,
          notAdvertised: fora.locacao,
          notAdvertisedHint: 'O imóvel não está anunciado para locação — o '
              'valor segue guardado na ficha, mas não entra nas buscas de '
              'aluguel nem no site.',
        ),
    ];

    final children = <Widget>[];
    if (prices.isNotEmpty) {
      children.add(_PricesRow(prices: prices));
    }
    if (_hasExtras(p)) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 14));
      children.add(_ExtrasLine(condominiumFee: p.condominiumFee, iptu: p.iptu));
    }
    if (hasNegotiation(p)) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 16));
      children.add(_NegotiationBlock(property: p));
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// Venda e Aluguel lado a lado quando os dois cabem (cada um com ~150dp na
/// escala do texto); senão, um embaixo do outro com filete.
class _PricesRow extends StatelessWidget {
  const _PricesRow({required this.prices});

  final List<Widget> prices;

  @override
  Widget build(BuildContext context) {
    if (prices.length == 1) return prices.first;
    final scale = pdkTextScale(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final half = (constraints.maxWidth - 20) / 2;
        if (constraints.maxWidth.isFinite && half >= 150 * scale) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: prices[0]),
                Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  color: ThemeHelpers.borderLightColor(context),
                ),
                Expanded(child: prices[1]),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            prices[0],
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(vertical: 12),
              color: ThemeHelpers.borderLightColor(context),
            ),
            prices[1],
          ],
        );
      },
    );
  }
}

class _PriceBlock extends StatelessWidget {
  const _PriceBlock({
    required this.label,
    required this.value,
    required this.tone,
    required this.notAdvertised,
    required this.notAdvertisedHint,
  });

  final String label;
  final String value;
  final Color tone;
  final bool notAdvertised;
  final String notAdvertisedHint;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final amber = PdkTone.amber(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: secondary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
            if (notAdvertised)
              Tooltip(
                message: notAdvertisedHint,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: amber.withValues(alpha: isDark ? 0.2 : 0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: amber.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    'NÃO ANUNCIADO',
                    style: TextStyle(
                      color: pdkInk(context, amber),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              color: tone,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        if (notAdvertised) ...[
          const SizedBox(height: 4),
          Text(
            notAdvertisedHint,
            style: TextStyle(color: secondary, fontSize: 12, height: 1.4),
          ),
        ],
      ],
    );
  }
}

/// "CONDOMÍNIO R$ X · IPTU R$ Y" — quebra linha em vez de estourar.
class _ExtrasLine extends StatelessWidget {
  const _ExtrasLine({this.condominiumFee, this.iptu});

  final double? condominiumFee;
  final double? iptu;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final hasCondo = (condominiumFee ?? 0) > 0;
    final hasIptu = (iptu ?? 0) > 0;

    Widget extra(String label, double value) {
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${label.toUpperCase()}  ',
              style: TextStyle(
                color: secondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
            TextSpan(
              text: _brl.format(value),
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontSize: 14,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 14,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (hasCondo) extra('Condomínio', condominiumFee!),
        if (hasCondo && hasIptu)
          Text(
            '·',
            style: TextStyle(color: secondary, fontWeight: FontWeight.w800),
          ),
        if (hasIptu) extra('IPTU', iptu!),
      ],
    );
  }
}

/// Bloco "Negociação" — linhas rótulo/valor com filete; em tela estreita (ou
/// fonte grande) o valor desce para baixo do rótulo.
class _NegotiationBlock extends StatelessWidget {
  const _NegotiationBlock({required this.property});

  final Property property;

  @override
  Widget build(BuildContext context) {
    final p = property;
    final rows = <({String label, String value})>[
      (
        label: 'Aceita negociação',
        value: p.acceptsNegotiation == true ? 'Sim' : 'Não',
      ),
      if (p.acceptsExchange != null)
        (
          label: 'Aceita permuta',
          value: p.acceptsExchange!
              ? ((p.exchangeMaxValue ?? 0) > 0
                  ? 'Sim, até ${_brl.format(p.exchangeMaxValue)}'
                  : 'Sim')
              : 'Não',
        ),
      if ((p.minSalePrice ?? 0) > 0)
        (label: 'Mín. venda', value: _brl.format(p.minSalePrice)),
      if ((p.minRentPrice ?? 0) > 0)
        (label: 'Mín. aluguel', value: _brl.format(p.minRentPrice)),
      if ((p.offerBelowMinSaleAction ?? '').trim().isNotEmpty)
        (
          label: 'Se oferta de venda abaixo do mín.',
          value: PropertyValuesSection.offerBelowActionLabel(
            p.offerBelowMinSaleAction,
          ),
        ),
      if ((p.offerBelowMinRentAction ?? '').trim().isNotEmpty)
        (
          label: 'Se oferta de aluguel abaixo do mín.',
          value: PropertyValuesSection.offerBelowActionLabel(
            p.offerBelowMinRentAction,
          ),
        ),
    ];
    final divider = ThemeHelpers.borderLightColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              LucideIcons.handshake,
              size: 15,
              color: pdkInk(context, PdkTone.green(context)),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                'Negociação',
                style: TextStyle(
                  color: ThemeHelpers.textColor(context),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Container(height: 1, color: divider),
          _LabelValueRow(label: rows[i].label, value: rows[i].value),
        ],
      ],
    );
  }
}

class _LabelValueRow extends StatelessWidget {
  const _LabelValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final labelText = Text(
      label,
      style: TextStyle(color: secondary, fontSize: 12.5, height: 1.35),
    );
    final valueText = Text(
      value,
      style: TextStyle(
        color: ThemeHelpers.textColor(context),
        fontSize: 13.5,
        fontWeight: FontWeight.w800,
        height: 1.35,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = pdkTextScale(context);
          if (constraints.maxWidth < 360 * scale) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [labelText, const SizedBox(height: 2), valueText],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: labelText),
              const SizedBox(width: 12),
              Flexible(
                child: Align(
                  alignment: Alignment.topRight,
                  child: DefaultTextStyle.merge(
                    textAlign: TextAlign.right,
                    child: valueText,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
