import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/services/property_service.dart';

/// Ícone e família de cada um dos 16 tipos de imóvel.
///
/// Os 5 tipos originais mantêm os ícones que o app já usava. Os novos seguem o
/// agrupamento do `typeIconMap` do web (`PropertyCreationSetupModal`): sobrado
/// é "casa"; studio, loft, kitnet, duplex e triplex são "apartamento";
/// cobertura, sala comercial, loja e galpão têm ícone próprio; fazenda é
/// "campo", como rural.
///
/// Tipo NÃO tem cor própria: cor é significado (status), e 16 tons seriam
/// arco-íris. Quem diferencia o tipo é o ícone e o grupo ([family]).
class PropertyTypeVisual {
  const PropertyTypeVisual._();

  /// Ícone Material arredondado (seletor de tipo e resumo do wizard).
  static IconData rounded(PropertyType type) {
    switch (type) {
      case PropertyType.house:
      case PropertyType.townhouse:
        return Icons.home_rounded;
      case PropertyType.apartment:
      case PropertyType.studio:
      case PropertyType.loft:
      case PropertyType.kitnet:
      case PropertyType.duplex:
      case PropertyType.triplex:
        return Icons.apartment_rounded;
      case PropertyType.penthouse:
        return Icons.villa_rounded;
      case PropertyType.commercial:
      case PropertyType.office:
        return Icons.business_rounded;
      case PropertyType.store:
        return Icons.storefront_rounded;
      case PropertyType.warehouse:
        return Icons.warehouse_rounded;
      case PropertyType.land:
        return Icons.location_on_rounded;
      case PropertyType.farm:
      case PropertyType.rural:
        return Icons.cottage_rounded;
    }
  }

  /// Ícone Material contornado (card da lista e hero do detalhe).
  static IconData outlined(PropertyType type) {
    switch (type) {
      case PropertyType.house:
      case PropertyType.townhouse:
        return Icons.home_outlined;
      case PropertyType.apartment:
      case PropertyType.studio:
      case PropertyType.loft:
      case PropertyType.kitnet:
      case PropertyType.duplex:
      case PropertyType.triplex:
        return Icons.apartment;
      case PropertyType.penthouse:
        return Icons.villa_outlined;
      case PropertyType.commercial:
      case PropertyType.store:
        return Icons.storefront_outlined;
      case PropertyType.office:
        return Icons.business_outlined;
      case PropertyType.warehouse:
        return Icons.warehouse_outlined;
      case PropertyType.land:
        return Icons.terrain_outlined;
      case PropertyType.farm:
      case PropertyType.rural:
        return Icons.agriculture_outlined;
    }
  }

  /// Ícone Lucide (chips do drawer de filtros).
  static IconData lucide(PropertyType type) {
    switch (type) {
      case PropertyType.house:
      case PropertyType.townhouse:
        return LucideIcons.home;
      case PropertyType.apartment:
      case PropertyType.studio:
      case PropertyType.loft:
      case PropertyType.kitnet:
      case PropertyType.duplex:
      case PropertyType.triplex:
        return LucideIcons.building2;
      case PropertyType.penthouse:
        return LucideIcons.building;
      case PropertyType.commercial:
      case PropertyType.store:
        return LucideIcons.store;
      case PropertyType.office:
        return LucideIcons.briefcase;
      case PropertyType.warehouse:
        return LucideIcons.warehouse;
      case PropertyType.farm:
        return LucideIcons.tractor;
      case PropertyType.land:
      case PropertyType.rural:
        return LucideIcons.trees;
    }
  }

  /// Família do tipo — só agrupamento de LEITURA (seletores e filtros): 16
  /// pastilhas soltas viram três blocos que a pessoa reconhece de cara. Não
  /// entra em payload nem em regra.
  static PropertyTypeFamily family(PropertyType type) {
    switch (type) {
      case PropertyType.house:
      case PropertyType.townhouse:
      case PropertyType.apartment:
      case PropertyType.penthouse:
      case PropertyType.studio:
      case PropertyType.loft:
      case PropertyType.kitnet:
      case PropertyType.duplex:
      case PropertyType.triplex:
        return PropertyTypeFamily.residencial;
      case PropertyType.commercial:
      case PropertyType.office:
      case PropertyType.store:
      case PropertyType.warehouse:
        return PropertyTypeFamily.comercial;
      case PropertyType.farm:
      case PropertyType.land:
      case PropertyType.rural:
        return PropertyTypeFamily.terra;
    }
  }

  /// Os tipos agrupados por família, cada grupo na ordem do enum (a mesma de
  /// `PropertyTypeOptions` do web). Grupo vazio não sai.
  static List<(PropertyTypeFamily, List<PropertyType>)> grouped() {
    return [
      for (final f in PropertyTypeFamily.values)
        (
          f,
          [
            for (final t in PropertyType.values)
              if (family(t) == f) t,
          ],
        ),
    ].where((g) => g.$2.isNotEmpty).toList();
  }
}

/// Famílias de tipo de imóvel (agrupamento visual).
enum PropertyTypeFamily {
  residencial('Residencial'),
  comercial('Comercial'),
  terra('Terreno e rural');

  const PropertyTypeFamily(this.label);

  final String label;
}
