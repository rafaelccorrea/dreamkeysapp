import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/services/property_service.dart';

/// Visual unificado do status do imóvel — usado em paridade entre a
/// lista (`PropertiesPage`) e a tela de detalhes (`PropertyDetailsPage`).
///
/// Cada status tem cor, ícone e label dedicados — exatamente o mesmo
/// mapeamento usado no drawer de filtros, garantindo consistência visual
/// (Disponível → verde, Vendido → roxo, Pendentes → âmbar, etc.).
class PropertyStatusVisual {
  const PropertyStatusVisual({
    required this.label,
    required this.shortLabel,
    required this.color,
    required this.icon,
  });

  final String label;
  final String shortLabel;
  final Color color;
  final IconData icon;

  /// Resolve a partir do enum `PropertyStatus`.
  factory PropertyStatusVisual.of(PropertyStatus status) {
    switch (status) {
      case PropertyStatus.draft:
        return PropertyStatusVisual(
          label: status.label,
          shortLabel: status.shortLabel,
          color: const Color(0xFF6366F1),
          icon: LucideIcons.fileEdit,
        );
      case PropertyStatus.pendingApproval:
        return PropertyStatusVisual(
          label: status.label,
          shortLabel: status.shortLabel,
          color: const Color(0xFFF59E0B),
          icon: LucideIcons.clock,
        );
      case PropertyStatus.pendingOwnerAuthorization:
        return PropertyStatusVisual(
          label: status.label,
          shortLabel: status.shortLabel,
          color: const Color(0xFF8B5CF6),
          icon: LucideIcons.userCheck,
        );
      case PropertyStatus.available:
        return PropertyStatusVisual(
          label: status.label,
          shortLabel: status.shortLabel,
          color: const Color(0xFF10B981),
          icon: LucideIcons.checkCircle2,
        );
      case PropertyStatus.rented:
        return PropertyStatusVisual(
          label: status.label,
          shortLabel: status.shortLabel,
          color: const Color(0xFF06B6D4),
          icon: LucideIcons.key,
        );
      case PropertyStatus.sold:
        return PropertyStatusVisual(
          label: status.label,
          shortLabel: status.shortLabel,
          color: const Color(0xFF8B5CF6),
          icon: LucideIcons.tag,
        );
      case PropertyStatus.maintenance:
        return PropertyStatusVisual(
          label: status.label,
          shortLabel: status.shortLabel,
          color: const Color(0xFFEF4444),
          icon: LucideIcons.wrench,
        );
    }
  }
}

/// Pill de status do imóvel — variante padrão (cor accent + fill leve).
///
/// Use nos cards da lista e na identidade da tela de detalhes pra dar
/// visibilidade imediata ao corretor (mais útil que descobrir o status
/// só clicando no imóvel).
class PropertyStatusPill extends StatelessWidget {
  const PropertyStatusPill({
    super.key,
    required this.status,
    this.short = false,
    this.solid = false,
    this.dense = false,
    this.onTap,
    this.actionSuffix,
  });

  /// Status do imóvel.
  final PropertyStatus status;

  /// Quando `true`, usa o label curto (ex.: "Aguard. proprietário").
  /// Útil em cards estreitos.
  final bool short;

  /// Quando `true`, renderiza com fundo sólido (cor) + texto branco.
  /// Use em cima de imagens/herós onde o pill precisa contrastar.
  final bool solid;

  /// Quando `true`, reduz padding e fonte (para uso em cards pequenos).
  final bool dense;

  /// Quando informado, torna o pill interativo (ex.: desfazer venda).
  final VoidCallback? onTap;

  /// Texto extra após o label (ex.: " · Desvender").
  final String? actionSuffix;

  @override
  Widget build(BuildContext context) {
    final v = PropertyStatusVisual.of(status);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (solid) {
      return _wrapInteractive(_renderSolid(v));
    }

    return _wrapInteractive(
      Container(
        padding: dense
            ? const EdgeInsets.symmetric(horizontal: 7, vertical: 3)
            : const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: v.color.withValues(alpha: isDark ? 0.18 : 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: v.color.withValues(alpha: isDark ? 0.50 : 0.42),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(v.icon, size: dense ? 11 : 12, color: v.color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                _labelText(v),
                style: TextStyle(
                  color: v.color,
                  fontWeight: FontWeight.w900,
                  fontSize: dense ? 9.5 : 10.5,
                  letterSpacing: 0.2,
                  height: 1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _labelText(PropertyStatusVisual v) {
    final base = short ? v.shortLabel : v.label;
    if (actionSuffix == null || actionSuffix!.isEmpty) return base;
    return '$base$actionSuffix';
  }

  Widget _wrapInteractive(Widget child) {
    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: child,
      ),
    );
  }

  Widget _renderSolid(PropertyStatusVisual v) {
    return Container(
      padding: dense
          ? const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5)
          : const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: v.color,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: v.color.withValues(alpha: 0.45),
            blurRadius: 8,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(v.icon, size: dense ? 11 : 12, color: Colors.white),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              _labelText(v),
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: dense ? 9.5 : 10.5,
                letterSpacing: 0.3,
                height: 1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pill de **situação** — ativo no cadastro / inativo / publicação no site.
/// Complementa o `PropertyStatusPill` (que é "estado de negócio").
class PropertySituationPill extends StatelessWidget {
  const PropertySituationPill({
    super.key,
    required this.isActive,
    required this.isAvailableForSite,
    this.dense = false,
  });

  final bool isActive;
  final bool isAvailableForSite;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color color;
    final IconData icon;
    final String label;

    if (!isActive) {
      color = const Color(0xFF6B7280); // gray
      icon = LucideIcons.minusCircle;
      label = 'Inativo';
    } else if (isAvailableForSite) {
      color = const Color(0xFF10B981); // green
      icon = LucideIcons.globe;
      label = 'Ativo · no site';
    } else {
      color = const Color(0xFF10B981); // green
      icon = LucideIcons.checkCircle2;
      label = 'Ativo';
    }

    return Container(
      padding: dense
          ? const EdgeInsets.symmetric(horizontal: 7, vertical: 3)
          : const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.50 : 0.42),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: dense ? 11 : 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: dense ? 9.5 : 10.5,
              letterSpacing: 0.2,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
