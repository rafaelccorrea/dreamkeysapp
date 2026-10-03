import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/property_service.dart';
import '../services/property_owner_check_service.dart';
import 'approval_actions_sheet.dart';

/// Âmbar de alerta (mesmo tom do `MdWarning` do modal do web), por token.
/// No escuro o texto/ícone usa a variante clara; o botão de seguir fica no
/// âmbar escuro nos dois temas para o texto branco ter contraste.
Color _duplicateTone(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? AppColors.status.warningDarkMode
        : AppColors.message.warningText;

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
    // Teto de altura: cabeçalho e rodapé fixos, a lista rola no meio (vale
    // para 1 candidato ou 20, retrato ou paisagem).
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.88,
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

/// Folha "Este proprietário já possui imóveis" — variante `owner` do
/// `PropertyDuplicateWarningModal` do web, aberta ao sair da etapa do
/// Proprietário no cadastro (`runOwnerExistingGate`). Cada imóvel traz o
/// selo do que coincidiu (CPF/CNPJ ou Telefone).
///
/// Devolve `true` só quando a pessoa escolhe "Continuar cadastro".
Future<bool> showPropertyOwnerExistingSheet({
  required BuildContext context,
  required String ownerName,
  required List<PropertyOwnerMatch> matches,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: ThemeHelpers.cardBackgroundColor(context),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.88,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _PropertyDuplicateSheet(
      duplicates: [for (final m in matches) m.property],
      submitPhase: false,
      ownerName: ownerName.trim().isEmpty ? 'este proprietário' : ownerName.trim(),
      matchLabels: {
        for (final m in matches)
          if (m.matchLabel != null) m.property.id: m.matchLabel!,
      },
    ),
  );
  return result == true;
}

class _PropertyDuplicateSheet extends StatelessWidget {
  final List<PropertyDuplicateCandidate> duplicates;
  final bool submitPhase;

  /// Preenchido = variante "proprietário já cadastrado".
  final String? ownerName;
  final Map<String, String> matchLabels;

  const _PropertyDuplicateSheet({
    required this.duplicates,
    required this.submitPhase,
    this.ownerName,
    this.matchLabels = const {},
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = _duplicateTone(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final n = duplicates.length;
    final isOwner = ownerName != null;

    // Título curto (cabe em 2 linhas em 320dp com texto a 130%); a contagem
    // abre o corpo, em destaque — responde de cara "quantos já existem".
    final title = isOwner
        ? 'Este proprietário já possui imóveis'
        : n == 0
            ? 'Possível imóvel duplicado'
            : 'Endereço já cadastrado';
    final countLine = isOwner
        ? (n == 1
            ? '1 imóvel cadastrado para $ownerName.'
            : '$n imóveis cadastrados para $ownerName.')
        : n == 0
            ? null
            : n == 1
                ? '1 imóvel coincide com este endereço.'
                : '$n imóveis coincidem com este endereço.';
    final guidance = isOwner
        ? 'Verifique se não é o mesmo imóvel que você está cadastrando.'
        : submitPhase
            ? 'Confira antes de gravar. Se for mesmo outro imóvel, cadastre como '
                'duplicado.'
            : 'Abra para conferir. Se for outro imóvel, siga com o cadastro.';
    final criterion = isOwner
        ? 'Coincide o CPF/CNPJ ou o telefone informado para o proprietário.'
        : 'Coincidem os dados decisivos: em condomínio, o mesmo '
            'condomínio e unidade/lote/quadra; em imóvel de rua, o '
            'mesmo endereço completo e complemento.';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ApprovalSheetGrabber(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 10, 0),
          child: ApprovalSheetHeader(
            eyebrow:
                isOwner ? 'Proprietário já cadastrado' : 'Duplicidade de endereço',
            title: title,
            tone: tone,
            icon: LucideIcons.alertTriangle,
          ),
        ),
        const SizedBox(height: 14),
        ApprovalSheetDivider(tone: tone),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    if (countLine != null)
                      TextSpan(
                        text: '$countLine ',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    TextSpan(text: guidance),
                  ],
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: ThemeHelpers.textColor(context),
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              // Critério em segundo plano: explica por que "coincide" sem
              // disputar com a lista, que é o que a pessoa precisa ver.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(LucideIcons.info, size: 14, color: secondary),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      criterion,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (duplicates.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Não conseguimos listar os imóveis coincidentes agora. '
                    'Você ainda pode voltar e revisar o endereço.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: ThemeHelpers.textColor(context),
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                for (var i = 0; i < duplicates.length; i++) ...[
                  Divider(
                    height: 1,
                    color:
                        ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
                  ),
                  _CandidateRow(
                    candidate: duplicates[i],
                    tone: tone,
                    matchLabel: matchLabels[duplicates[i].id],
                  ),
                ],
            ],
          ),
        ),
        // SafeArea embaixo: o `useSafeArea` do sheet só protege o topo; sem
        // isto os botões encostam na barra de gestos.
        SafeArea(
          top: false,
          child: ApprovalSheetFooter(
            cancelLabel: submitPhase ? 'Cancelar' : 'Voltar e revisar',
            confirmLabel:
                submitPhase ? 'Cadastrar como duplicado' : 'Continuar cadastro',
            confirmIcon:
                submitPhase ? LucideIcons.copyPlus : LucideIcons.arrowRight,
            confirmColor: AppColors.message.warningText,
            submitting: false,
            onConfirm: () => Navigator.of(context).pop(true),
          ),
        ),
      ],
    );
  }
}

/// Linha de um candidato: código em destaque, título, endereço, cidade/UF +
/// unidade e complemento (mesmas linhas do card do web), com "Abrir" à
/// direita. Linha flush com filete — nada de card dentro do sheet.
class _CandidateRow extends StatelessWidget {
  final PropertyDuplicateCandidate candidate;
  final Color tone;

  /// Selo do que coincidiu na variante proprietário ("CPF/CNPJ"/"Telefone").
  final String? matchLabel;

  const _CandidateRow({
    required this.candidate,
    required this.tone,
    this.matchLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final c = candidate;

    final street = [c.street, c.number].where((s) => s.isNotEmpty).join(', ');
    final addressLine =
        [street, c.neighborhood].where((s) => s.isNotEmpty).join(' - ');
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
                if (c.code != null || matchLabel != null) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (c.code != null)
                        Text(
                          'Código #${c.code}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: tone,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      if (matchLabel != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: tone.withValues(alpha: 0.12),
                            border:
                                Border.all(color: tone.withValues(alpha: 0.40)),
                          ),
                          child: Text(
                            matchLabel!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: tone,
                              fontWeight: FontWeight.w800,
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                ],
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
                  Text(
                    addressLine,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: lineStyle,
                  ),
                ],
                if (cityLine.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    cityLine,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: lineStyle,
                  ),
                ],
                if (c.complement != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Complemento: ${c.complement}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
              foregroundColor: tone,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              textStyle: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            icon: const Icon(LucideIcons.externalLink, size: 15),
            label: const Text('Abrir', maxLines: 1, softWrap: false),
          ),
        ],
      ),
    );
  }
}
