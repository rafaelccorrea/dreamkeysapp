import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/services/property_service.dart';

/// Ícone e tom de cada um dos 16 tipos de imóvel.
///
/// Os 5 tipos originais mantêm os ícones que o app já usava. Os novos seguem o
/// agrupamento do `typeIconMap` do web (`PropertyCreationSetupModal`): sobrado
/// é "casa"; studio, loft, kitnet, duplex e triplex são "apartamento";
/// cobertura, sala comercial, loja e galpão têm ícone próprio; fazenda é
/// "campo", como rural.
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

  /// Tom por família — as cores que o drawer já usava para os 5 tipos
  /// originais; os novos herdam a cor da família.
  static Color tone(PropertyType type) {
    switch (type) {
      case PropertyType.house:
      case PropertyType.townhouse:
        return const Color(0xFF10B981);
      case PropertyType.apartment:
      case PropertyType.penthouse:
      case PropertyType.studio:
      case PropertyType.loft:
      case PropertyType.kitnet:
      case PropertyType.duplex:
      case PropertyType.triplex:
        return const Color(0xFF3B82F6);
      case PropertyType.commercial:
      case PropertyType.office:
      case PropertyType.store:
      case PropertyType.warehouse:
        return const Color(0xFFF59E0B);
      case PropertyType.land:
        return const Color(0xFF84CC16);
      case PropertyType.farm:
      case PropertyType.rural:
        return const Color(0xFFA16207);
    }
  }
}
