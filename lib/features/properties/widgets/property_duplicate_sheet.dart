import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/property_service.dart';
import 'approval_actions_sheet.dart';

/// Âmbar de alerta (mesmo tom do `MdWarning` do modal do web).
const Color _kDuplicateTone = Color(0xFFD97706);

/// Folha "Possível imóvel duplicado" — paridade com o
/// `PropertyDuplicateWarningModal` do web (variante endereço).
///
/// - [submitPhase] `false`: aviso ao sair da etapa de Localização
///   ("Voltar e revisar" / "Continuar cadastro").
/// - [submitPhase] `true`: aviso antes de gravar ou após o 409
///   `PROPERTY_DUPLICATE_DETECTED` ("Cancelar" / "Cadastrar como duplicado").
///
/// Cada candidato tem "Abrir", que empilha o detalhe do imóvel por cima do
/// cadastro (no web abre em nova aba); ao voltar, a folha continua aberta.
///
/// Devolve `true` só quando a pessoa escolhe seguir.
Future<bool> showPropertyDuplicateSheet({
  required BuildContext context,
  required List<PropertyDuplicateCandidate> duplicates,
  required bool submitPhase,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: ThemeHelpers.cardBackgroundColor(context),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _PropertyDuplicateSheet(
      duplicates: duplicates,
      submitPhase: submitPhase,
    ),
  );
  return result == true;
}

class _PropertyDuplicateSheet extends StatelessWidget {
  final List<PropertyDuplicateCandidate> duplicates;
  final bool submitPhase;

  const _PropertyDuplicateSheet({
    required this.duplicates,
    required this.submitPhase,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = 'Encontramos imóvel(is) que coincidem nos dados decisivos: '
        'em condomínio, mesmo condomínio e mesma unidade/lote/quadra; em '
        'imóvel de rua, mesmo endereço completo e mesmo complemento.'
        '${submitPhase ? ' Deseja cadastrar mesmo assim?' : ' Você pode revisar os imóveis existentes ou continuar o cadastro.'}';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ApprovalSheetGrabber(),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 2, 10, 0),
          child: ApprovalSheetHeader(
            eyebrow: 'Duplicidade de endereço',
            title: 'Possível imóvel duplicado',
            tone: _kDuplicateTone,
            icon: LucideIcons.alertTriangle,
          ),
        ),
        const SizedBox(height: 14),
        const ApprovalSheetDivider(tone: _kDuplicateTone),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            children: [
              Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  height: 1.42,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              if (duplicates.isEmpty)
                Text(
                  'Não foi possível listar os imóveis coincidentes agora.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    height: 1.35,
                  ),
                )
              else
                for (var i = 0; i < duplicates.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      color: ThemeHelpers.borderColor(context)
                          .withValues(alpha: 0.45),
                    ),
                  _CandidateRow(candidate: duplicates[i]),
                ],
            ],
          ),
        ),
        ApprovalSheetFooter(
          cancelLabel: submitPhase ? 'Cancelar' : 'Voltar e revisar',
          confirmLabel:
              submitPhase ? 'Cadastrar como duplicado' : 'Continuar cadastro',
          confirmIcon:
              submitPhase ? LucideIcons.copyPlus : LucideIcons.arrowRight,
          confirmColor: _kDuplicateTone,
          submitting: false,
          onConfirm: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

/// Linha de um candidato: título, código + endereço, cidade/UF + unidade e
/// complemento (mesmas linhas do card do web), com "Abrir" à direita.
class _CandidateRow extends StatelessWidget {
  final PropertyDuplicateCandidate candidate;

  const _CandidateRow({required this.candidate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final c = candidate;

    final street = [c.street, c.number].where((s) => s.isNotEmpty).join(', ');
    final addressLine = [
      if (c.code != null) 'Código #${c.code}',
      [street, c.neighborhood].where((s) => s.isNotEmpty).join(' - '),
    ].where((s) => s.isNotEmpty).join(' · ');
    final cityLine = [
      [c.city, c.state].where((s) => s.isNotEmpty).join('/'),
      if (c.propertyUnity != null) 'Unidade/Lote: ${c.propertyUnity}',
    ].where((s) => s.isNotEmpty).join(' · ');

    final lineStyle = theme.textTheme.bodySmall?.copyWith(
      color: secondary,
      height: 1.35,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.title.isEmpty ? 'Imóvel sem título' : c.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                    height: 1.25,
                  ),
                ),
                if (addressLine.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(addressLine, style: lineStyle),
                ],
                if (cityLine.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(cityLine, style: lineStyle),
                ],
                if (c.complement != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Complemento: ${c.complement}',
                    style: lineStyle?.copyWith(fontStyle: FontStyle.italic),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () => Navigator.of(context)
                .pushNamed(AppRoutes.propertyDetails(c.id)),
            style: TextButton.styleFrom(
              foregroundColor: _kDuplicateTone,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              textStyle: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            icon: const Icon(LucideIcons.externalLink, size: 15),
            label: const Text('Abrir'),
          ),
        ],
      ),
    );
  }
}
