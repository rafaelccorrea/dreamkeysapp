import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/property_service.dart';
import 'property_details_kit.dart';

/// Um campo preenchido da ficha adicional.
class PropertyAdditionalInfoItem {
  const PropertyAdditionalInfoItem({
    required this.label,
    required this.value,
    this.long = false,
  });

  /// Rótulo do web (`propertyExtendedImportRows`).
  final String label;

  /// Valor pronto para ler (data formatada, "Sim", número pt-BR).
  final String value;

  /// Texto longo — ocupa a linha inteira.
  final bool long;
}

/// Grupo da ficha adicional (só entra com ao menos um campo preenchido).
class PropertyAdditionalInfoGroup {
  const PropertyAdditionalInfoGroup({
    required this.title,
    required this.items,
  });

  final String title;
  final List<PropertyAdditionalInfoItem> items;
}

/// Corpo da seção "Ficha adicional" — paridade com o bloco
/// `propertyExtendedImportRows` do web (W:393-500, 2378-2402): os campos
/// extras/importados do cadastro, SÓ os preenchidos, com os mesmos rótulos
/// do web, agrupados por assunto (datas e aprovação, anúncio, prédio e
/// unidade, locação e garantias, proprietário). Datas no formato
/// "12/09/2026 · 14:32", marcadores como "Sim", números em pt-BR.
///
/// Vai dentro do molde flush da página (título "Ficha adicional"); monte só
/// quando [isVisible]. Espera o [Property] do detalhe (`additionalInfo` e as
/// datas/motivos da fila de aprovação).
class PropertyAdditionalInfoSection extends StatelessWidget {
  const PropertyAdditionalInfoSection({super.key, required this.property});

  final Property property;

  /// Frase de apoio sob o título (a do web, sem o jargão técnico).
  static const String lead = 'Dados importados ou campos extras do cadastro.';

  static bool isVisible(Property property) =>
      groupsOf(property).isNotEmpty;

  /// Os grupos com os campos preenchidos, na ordem do web dentro de cada um.
  static List<PropertyAdditionalInfoGroup> groupsOf(Property p) {
    final info = p.additionalInfo ?? const PropertyAdditionalInfo();
    final groups = <PropertyAdditionalInfoGroup>[];

    void addGroup(String title, List<PropertyAdditionalInfoItem?> raw) {
      final items = raw.whereType<PropertyAdditionalInfoItem>().toList();
      if (items.isNotEmpty) {
        groups.add(PropertyAdditionalInfoGroup(title: title, items: items));
      }
    }

    PropertyAdditionalInfoItem? date(String label, String? iso) {
      final stamp = pdkStamp(iso);
      return stamp == null
          ? null
          : PropertyAdditionalInfoItem(label: label, value: stamp);
    }

    PropertyAdditionalInfoItem? text(
      String label,
      String? value, {
      bool long = false,
    }) {
      final v = value?.trim() ?? '';
      return v.isEmpty
          ? null
          : PropertyAdditionalInfoItem(label: label, value: v, long: long);
    }

    PropertyAdditionalInfoItem? yes(String label, bool? value) =>
        value == true
            ? PropertyAdditionalInfoItem(label: label, value: 'Sim')
            : null;

    PropertyAdditionalInfoItem? number(
      String label,
      num? value, {
      String suffix = '',
    }) {
      if (value == null || !value.isFinite) return null;
      return PropertyAdditionalInfoItem(
        label: label,
        value: '${_formatNumber(value)}$suffix',
      );
    }

    addGroup('Datas e aprovação', [
      date('Última atualização (ficha)', info.lastUpdateEntryAt),
      date('Vendido em', info.soldAt),
      date('Alugado em', info.rentedAt),
      date('Publicação solicitada em', p.publicationRequestedAt),
      date('Publicação aprovada em', p.publicationApprovedAt),
      date('Publicação recusada em', p.publicationRejectedAt),
      text(
        'Motivo recusa publicação',
        p.publicationRejectionReason,
        long: true,
      ),
      date('Disponibilidade recusada em', p.availabilityRejectedAt),
      text(
        'Motivo recusa disponibilidade',
        p.availabilityRejectionReason,
        long: true,
      ),
    ]);

    addGroup('Anúncio e divulgação', [
      yes('Alto padrão', info.isHighStandard),
      yes('Com placa', info.hasPlaque),
      yes('Exclusividade', info.hasExclusivity),
      yes('Privado', info.isPrivate),
      text('Código alternativo', info.alternativeCode),
      text('Horário de visita', info.visitTime),
      text('Contato (divulgação)', info.siteContact),
      text('Próximos / entorno', info.nearby, long: true),
      text('Meta description (SEO)', info.siteMetaDescription, long: true),
    ]);

    final lotArea = info.lotArea;
    addGroup('Prédio e unidade', [
      number('Ano construção', info.builtYear),
      text('Unidade', info.propertyUnity),
      number('Andar (unidade)', info.unitFloor),
      number('Andares (edifício)', info.floors),
      number('Blocos / torres', info.buildings),
      number('Elevadores', info.elevators),
      text('Posição solar', info.sunPosition),
      text('Situação', info.propertySituation),
      lotArea != null && lotArea > 0
          ? number('Área do lote (m²)', lotArea)
          : null,
      text('Medida lote', info.lotMeasureType),
    ]);

    addGroup('Locação e garantias', [
      yes('Aceita caução', info.bail),
      yes('Aceita fiança', info.suretyBond),
      yes('Aplicação fiança', info.bondApplication),
      yes('CredPago', info.credpagoGuarantee),
      yes('Fiador', info.guarantor),
      text('Regras', info.houseRules, long: true),
    ]);

    addGroup('Proprietário', [
      number('% proprietário', info.ownersPercentage, suffix: '%'),
      number('Taxa proprietário', info.ownersRate),
    ]);

    return groups;
  }

  static String _formatNumber(num value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return NumberFormat.decimalPatternDigits(
      locale: 'pt_BR',
      decimalDigits: 2,
    ).format(value);
  }

  @override
  Widget build(BuildContext context) {
    final groups = groupsOf(property);
    if (groups.isEmpty) return const SizedBox.shrink();
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final divider = ThemeHelpers.borderLightColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          lead,
          style: TextStyle(color: secondary, fontSize: 12.5, height: 1.45),
        ),
        for (var i = 0; i < groups.length; i++) ...[
          SizedBox(height: i == 0 ? 12 : 14),
          if (i > 0) ...[
            Container(height: 1, color: divider),
            const SizedBox(height: 12),
          ],
          _GroupBlock(group: groups[i]),
        ],
      ],
    );
  }
}

/// Um grupo: título curto e a grade de pares — 2 colunas quando cabem (texto
/// longo sempre na linha inteira), 1 coluna em tela estreita/fonte grande.
class _GroupBlock extends StatelessWidget {
  const _GroupBlock({required this.group});

  final PropertyAdditionalInfoGroup group;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          group.title.toUpperCase(),
          style: TextStyle(
            color: secondary,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 16.0;
            final scale = pdkTextScale(context);
            final width = constraints.maxWidth;
            final twoColumns = width >= 360 * scale;
            final half = (width - gap) / 2;
            return Wrap(
              spacing: gap,
              runSpacing: 12,
              children: [
                for (final item in group.items)
                  SizedBox(
                    width: twoColumns && !item.long ? half : width,
                    child: _Cell(item: item),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.item});

  final PropertyAdditionalInfoItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: ThemeHelpers.textSecondaryColor(context),
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          item.value,
          maxLines: item.long ? 12 : 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: ThemeHelpers.textColor(context),
            fontSize: 13.5,
            fontWeight: item.long ? FontWeight.w500 : FontWeight.w700,
            height: 1.4,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
