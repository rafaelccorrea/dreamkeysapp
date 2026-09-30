import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/api_service.dart';
import '../../../../shared/services/property_service.dart';
import '../../../../shared/utils/error_cause.dart';
import '../../../../shared/utils/property_finalidade.dart';
import '../../utils/property_edit_permissions.dart';
import '../../utils/property_status_visual.dart';
import 'property_details_kit.dart';

/// Motivo da trava de "Alugado, mas segue à venda" para quem não é gestão —
/// texto do web (`rentOutKeepSaleBlockedReason`).
const String kPropertyKeepSaleBlockedReason =
    'Disponível para gestores e administradores — peça a um deles para '
    'manter a venda no ar.';

/// Motivo para travar "Alterar status" (e "Editar") exatamente como o web:
/// imóvel excluído → só consulta; sem direito de editar a ficha → a frase de
/// [PropertyEditPermissionResult.reasonMessage] (autorização do proprietário
/// já assinada, para responsável/captador; ou sem vínculo). `null` = liberado.
/// Passe o `_editPermission` da página.
String? propertyStatusChangeLockReason({
  required Property property,
  required PropertyEditPermissionResult permission,
}) {
  if (property.isDeleted) return kPropertyDeletedReadOnlyReason;
  if (permission.canEdit) return null;
  return permission.reasonMessage;
}

/// Abre a folha "Alterar status do imóvel" — paridade com o
/// `PropertyStatusChangeModal` do web (W:2086-2105 + modal 510-612).
///
/// - Oferece só as transições diretas do web (`allowedTargetStatuses`,
///   alinhadas ao `validateStatusChange` do back) a partir do status CRU
///   gravado (`statusRaw`), com o efeito de cada uma escrito; sem transição,
///   explica o porquê.
/// - Observação opcional (vai no histórico).
/// - Imóvel de finalidade efetiva `ambos`, em Disponível, indo para Alugado:
///   escolha "Alugado, mas segue à venda" (padrão) × "Encerrar tudo como
///   Alugado". A primeira chama `deactivateProperty(reason: 'rented_by_us',
///   scope: 'rent')` — o status NÃO muda, a finalidade vira venda; exige
///   gestão, então com [canRentOutKeepSale] `false` fica travada com o motivo
///   do web (e vale o "Encerrar tudo").
/// - As demais escolhas chamam `changePropertyStatus` (`PATCH
///   /properties/:id/status {status, notes}`).
/// - [lockedReason] (ex.: `_editPermission.reasonMessage` quando a
///   autorização do proprietário já foi assinada, ou "imóvel excluído") abre a
///   folha travada: mostra o status atual e o motivo, sem ações.
///
/// A página decide quem pode abrir (mesma regra do botão "Editar": pode
/// editar a ficha). Devolve `true` quando o servidor mudou algo — a página
/// recarrega a ficha (`_loadProperty()`); o aviso de sucesso já sai daqui.
Future<bool> showPropertyStatusChangeSheet({
  required BuildContext context,
  required Property property,
  bool canRentOutKeepSale = false,
  String? lockedReason,
}) async {
  final outcome = PdkSheetOutcome();
  await showPdkSheet<void>(
    context: context,
    builder: (_) => _StatusChangeSheet(
      property: property,
      canRentOutKeepSale: canRentOutKeepSale,
      lockedReason: lockedReason,
      outcome: outcome,
    ),
  );
  await outcome.settle();
  final message = outcome.message;
  if (outcome.changed && message != null && context.mounted) {
    pdkShowSnack(context, message, tone: PdkSnackTone.success);
  }
  return outcome.changed;
}

/// Transições diretas — cópia do `allowedTargetStatuses` do web
/// (PropertyStatusChangeModal.tsx), na mesma ordem.
const Map<String, List<PropertyStatus>> _kTransitions = {
  'draft': [
    PropertyStatus.available,
    PropertyStatus.maintenance,
    PropertyStatus.pendingOwnerAuthorization,
  ],
  'available': [
    PropertyStatus.inService,
    PropertyStatus.rented,
    PropertyStatus.sold,
    PropertyStatus.maintenance,
    PropertyStatus.draft,
  ],
  // Funil de locação (fluxo linear — espelha validateStatusChange no back).
  'in_service': [
    PropertyStatus.visitScheduled,
    PropertyStatus.available,
    PropertyStatus.rented,
    PropertyStatus.sold,
  ],
  'visit_scheduled': [
    PropertyStatus.inVisit,
    PropertyStatus.inService,
    PropertyStatus.available,
    PropertyStatus.rented,
    PropertyStatus.sold,
  ],
  'in_visit': [
    PropertyStatus.inNegotiation,
    PropertyStatus.visitScheduled,
    PropertyStatus.available,
    PropertyStatus.rented,
    PropertyStatus.sold,
  ],
  'in_negotiation': [
    PropertyStatus.proposalReceived,
    PropertyStatus.inVisit,
    PropertyStatus.available,
    PropertyStatus.rented,
    PropertyStatus.sold,
  ],
  'proposal_received': [
    PropertyStatus.registrationAnalysis,
    PropertyStatus.inNegotiation,
    PropertyStatus.available,
    PropertyStatus.rented,
    PropertyStatus.sold,
  ],
  'registration_analysis': [
    PropertyStatus.documentation,
    PropertyStatus.proposalReceived,
    PropertyStatus.available,
    PropertyStatus.rented,
    PropertyStatus.sold,
  ],
  'documentation': [
    PropertyStatus.contractDrafting,
    PropertyStatus.registrationAnalysis,
    PropertyStatus.available,
    PropertyStatus.rented,
    PropertyStatus.sold,
  ],
  'contract_drafting': [
    PropertyStatus.signature,
    PropertyStatus.documentation,
    PropertyStatus.available,
    PropertyStatus.rented,
    PropertyStatus.sold,
  ],
  'signature': [
    PropertyStatus.rented,
    PropertyStatus.contractDrafting,
    PropertyStatus.available,
    PropertyStatus.sold,
  ],
  'rented': [
    PropertyStatus.available,
    PropertyStatus.sold,
    PropertyStatus.maintenance,
  ],
  'sold': [
    PropertyStatus.available,
    PropertyStatus.maintenance,
  ],
  'maintenance': [
    PropertyStatus.available,
    PropertyStatus.draft,
  ],
  // Pendentes ainda podem ser fechados (alugados/vendidos): a operação real
  // acontece antes da publicação/aprovação no site.
  'pending_approval': [
    PropertyStatus.draft,
    PropertyStatus.rented,
    PropertyStatus.sold,
  ],
  'pending_owner_authorization': [
    PropertyStatus.draft,
    PropertyStatus.rented,
    PropertyStatus.sold,
  ],
  'pending_publication': [
    PropertyStatus.draft,
    PropertyStatus.rented,
    PropertyStatus.sold,
  ],
};

/// O que cada status significa — as descrições do `STATUS_VISUAL` do web.
String _descriptionOf(PropertyStatus status) {
  switch (status) {
    case PropertyStatus.available:
      return 'Ativo e disponível para captação.';
    case PropertyStatus.rented:
      return 'Locação fechada — imóvel alugado.';
    case PropertyStatus.sold:
      return 'Venda concluída.';
    case PropertyStatus.maintenance:
      return 'Indisponível temporariamente.';
    case PropertyStatus.draft:
      return 'Volta a rascunho para editar e reenviar.';
    case PropertyStatus.pendingOwnerAuthorization:
      return 'Aguardando autorização do proprietário.';
    case PropertyStatus.pendingApproval:
      return 'Aguardando aprovação.';
    case PropertyStatus.pendingPublication:
      return 'Aguardando publicação no site.';
    case PropertyStatus.inService:
      return 'Atendimento de locação iniciado.';
    case PropertyStatus.visitScheduled:
      return 'Visita agendada com o cliente.';
    case PropertyStatus.inVisit:
      return 'Visita ao imóvel em andamento.';
    case PropertyStatus.inNegotiation:
      return 'Negociação de valores e condições.';
    case PropertyStatus.proposalReceived:
      return 'Proposta recebida do cliente.';
    case PropertyStatus.registrationAnalysis:
      return 'Análise cadastral do pretendente.';
    case PropertyStatus.documentation:
      return 'Coleta e conferência de documentos.';
    case PropertyStatus.contractDrafting:
      return 'Contrato em elaboração.';
    case PropertyStatus.signature:
      return 'Aguardando assinatura do contrato.';
  }
}

/// Mensagem de erro do back com os status em português — porte do
/// `humanizePropertyStatusError` do web ("Não é possível mudar de X para Y.
/// Status permitidos: …").
String? _humanizeStatusError(String? message) {
  final raw = message?.trim() ?? '';
  if (raw.isEmpty) return null;
  final transition = RegExp(
    r'status de (\w+) para (\w+)\.\s*Transições permitidas:\s*(.+)',
    caseSensitive: false,
  ).firstMatch(raw);
  if (transition != null) {
    final from = PropertyStatus.labelOf(transition.group(1));
    final to = PropertyStatus.labelOf(transition.group(2));
    final allowed = (transition.group(3) ?? '')
        .split(RegExp(r'[,;]'))
        .map((s) => PropertyStatus.labelOf(s.trim().replaceAll('.', '')))
        .where((s) => s.isNotEmpty)
        .join(', ');
    final base = 'Não é possível mudar de "$from" para "$to".';
    return allowed.isEmpty ? base : '$base Status permitidos: $allowed.';
  }
  return raw.replaceAllMapped(
    RegExp(
      r'\b(available|rented|sold|maintenance|draft|pending_approval|'
      r'pending_owner_authorization|pending_publication|in_service|'
      r'visit_scheduled|in_visit|in_negotiation|proposal_received|'
      r'registration_analysis|documentation|contract_drafting|signature)\b',
    ),
    (m) => PropertyStatus.labelOf(m.group(0)),
  );
}

class _StatusChangeSheet extends StatefulWidget {
  const _StatusChangeSheet({
    required this.property,
    required this.canRentOutKeepSale,
    required this.lockedReason,
    required this.outcome,
  });

  final Property property;
  final bool canRentOutKeepSale;
  final String? lockedReason;
  final PdkSheetOutcome outcome;

  @override
  State<_StatusChangeSheet> createState() => _StatusChangeSheetState();
}

class _StatusChangeSheetState extends State<_StatusChangeSheet> {
  late final String _current = widget.property.statusRaw
      .trim()
      .toLowerCase()
      .replaceAll('-', '_');
  late final List<PropertyStatus> _options =
      _kTransitions[_current] ?? const <PropertyStatus>[];
  late PropertyStatus? _selected = _options.isEmpty ? null : _options.first;

  /// Escolha do "Alugado" num imóvel `ambos`: segue à venda (padrão do web)
  /// ou encerra tudo.
  bool _keepSale = true;

  final TextEditingController _notes = TextEditingController();
  bool _submitting = false;
  ErrorCause? _error;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  bool get _locked => (widget.lockedReason ?? '').trim().isNotEmpty;

  PropertyFinalidade? get _finalidade => finalidadeEfetiva(
        finalidade: PropertyFinalidade.tryParse(widget.property.finalidade),
        salePrice: widget.property.salePrice,
        rentPrice: widget.property.rentPrice,
      );

  /// Só a partir de Disponível (regra do web): vindo do funil de locação o
  /// desfecho é o Alugado clássico.
  bool get _scopeChoiceVisible =>
      _selected == PropertyStatus.rented &&
      _current == PropertyStatus.available.value &&
      _finalidade == PropertyFinalidade.ambos;

  bool get _keepSaleActive =>
      _scopeChoiceVisible && widget.canRentOutKeepSale && _keepSale;

  bool get _canSubmit =>
      !_locked &&
      !_submitting &&
      _selected != null &&
      _selected!.value != _current;

  /// Etiqueta de direção no funil de locação ("Próxima etapa" / "Etapa
  /// anterior") — ajuda a ler a ordem sem decorar as 9 etapas.
  String? _badgeFor(PropertyStatus status) {
    final steps = PropertyStatusVisual.rentalFunnelSteps;
    final from = steps.indexWhere((s) => s.value == _current);
    final to = steps.indexOf(status);
    if (from < 0 || to < 0) return null;
    if (to == from + 1) return 'Próxima etapa';
    if (to == from - 1) return 'Etapa anterior';
    return null;
  }

  void _submit() {
    if (!_canSubmit) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    widget.outcome.inFlight = _send(_selected!, keepSale: _keepSaleActive);
  }

  Future<void> _send(PropertyStatus target, {required bool keepSale}) async {
    final notes = _notes.text.trim();
    final service = PropertyService.instance;
    final ApiResponse<Property> res;
    if (keepSale) {
      res = await service.deactivateProperty(
        widget.property.id,
        reason: PropertyDeactivationReason.rentedByUs.value,
        notes: notes.isEmpty ? null : notes,
        scope: 'rent',
      );
    } else {
      res = await service.changePropertyStatus(
        widget.property.id,
        status: target,
        notes: notes.isEmpty ? null : notes,
      );
    }

    if (pdkApplied(res)) {
      widget.outcome.changed = true;
      widget.outcome.message = keepSale
          ? 'Imóvel retirado da locação — segue anunciado para venda.'
          : 'Imóvel marcado como "${target.label}".';
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = pdkFailureCause(
        res,
        message: keepSale ? res.message : _humanizeStatusError(res.message),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final code = widget.property.code?.trim() ?? '';
    final title = widget.property.title.trim();
    final subtitle = [
      if (code.isNotEmpty) 'Imóvel $code',
      if (title.isNotEmpty) title,
    ].join(' · ');

    return PopScope(
      canPop: !_submitting,
      child: PdkSheetFrame(
        icon: LucideIcons.arrowLeftRight,
        tone: PdkTone.blue(context),
        title: 'Alterar status do imóvel',
        subtitle: subtitle.isEmpty ? null : subtitle,
        onClose: _submitting ? null : () => Navigator.of(context).pop(),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _locked || _options.isEmpty
                ? _closedBody(context, isDark)
                : _openBody(context, isDark),
          ),
        ),
        footer: _locked || _options.isEmpty
            ? PdkNeutralButton(
                label: 'Fechar',
                onPressed: () => Navigator.of(context).pop(),
              )
            : _footer(context),
      ),
    );
  }

  /// Travada ou sem transição: o status atual e o porquê.
  List<Widget> _closedBody(BuildContext context, bool isDark) {
    final current = PropertyStatusVisual.ofRaw(
      widget.property.status,
      widget.property.statusRaw,
      dark: isDark,
    );
    return [
      _TransitionLine(from: current, to: null),
      const SizedBox(height: 16),
      if (_locked)
        PdkLockNote(
          title: 'Alterar status está travado',
          reason: widget.lockedReason!.trim(),
        )
      else
        PdkNote(
          icon: LucideIcons.info,
          tone: ThemeHelpers.textSecondaryColor(context),
          text: 'Não há mudança direta a partir de "${current.label}". Use '
              'a edição da ficha ou as filas de aprovação quando for o caso.',
        ),
    ];
  }

  List<Widget> _openBody(BuildContext context, bool isDark) {
    final current = PropertyStatusVisual.ofRaw(
      widget.property.status,
      widget.property.statusRaw,
      dark: isDark,
    );
    final selected = _selected;
    final available = PropertyStatusVisual.of(
      PropertyStatus.available,
      dark: isDark,
    );
    final rented = PropertyStatusVisual.of(PropertyStatus.rented, dark: isDark);

    final PropertyStatusVisual? target;
    if (_keepSaleActive) {
      target = PropertyStatusVisual(
        label: 'Disponível — só venda',
        shortLabel: 'Disponível — só venda',
        color: available.color,
        icon: LucideIcons.tag,
      );
    } else if (selected != null) {
      target = PropertyStatusVisual.of(selected, dark: isDark);
    } else {
      target = null;
    }

    return [
      _TransitionLine(from: current, to: target),
      const SizedBox(height: 18),
      const PdkBlockLabel(
        'Novo status',
        hint: 'Só aparecem as mudanças diretas permitidas a partir do status '
            'atual.',
      ),
      const SizedBox(height: 10),
      for (var i = 0; i < _options.length; i++) ...[
        if (i > 0) const SizedBox(height: 8),
        () {
          final status = _options[i];
          final visual = PropertyStatusVisual.of(status, dark: isDark);
          return PdkChoiceRow(
            icon: visual.icon,
            tone: visual.color,
            title: status.label,
            description: _descriptionOf(status),
            badge: _badgeFor(status),
            selected: status == selected,
            onTap: _submitting
                ? null
                : () => setState(() {
                      _selected = status;
                      _error = null;
                    }),
          );
        }(),
      ],
      if (_scopeChoiceVisible) ...[
        const SizedBox(height: 20),
        const PdkBlockLabel(
          'Este imóvel também está à venda',
          hint: 'A locação fechou, mas a venda pode continuar valendo.',
        ),
        const SizedBox(height: 10),
        PdkChoiceRow(
          icon: LucideIcons.tag,
          tone: available.color,
          title: 'Alugado, mas segue à venda',
          description: 'Tira só da locação: a venda continua anunciada no '
              'site e o status do imóvel não muda.',
          lockedReason:
              widget.canRentOutKeepSale ? null : kPropertyKeepSaleBlockedReason,
          selected: _keepSaleActive,
          onTap: _submitting ? null : () => setState(() => _keepSale = true),
        ),
        const SizedBox(height: 8),
        PdkChoiceRow(
          icon: rented.icon,
          tone: rented.color,
          title: 'Encerrar tudo como Alugado',
          description: 'O imóvel sai do site por completo — venda inclusive.',
          selected: !_keepSaleActive,
          onTap: _submitting ? null : () => setState(() => _keepSale = false),
        ),
      ],
      const SizedBox(height: 20),
      TextField(
        controller: _notes,
        enabled: !_submitting,
        minLines: 2,
        maxLines: 5,
        maxLength: 2000,
        textCapitalization: TextCapitalization.sentences,
        style: TextStyle(
          color: ThemeHelpers.textColor(context),
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
        decoration: pdkFieldDecoration(
          context,
          label: 'Observações (opcional)',
          hint: 'Ex.: locação fechada com o cliente — registrar no histórico',
          multiline: true,
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 14),
        PdkErrorNote(
          title: _keepSaleActive
              ? 'Não foi possível tirar o imóvel da locação'
              : 'Não foi possível alterar o status',
          cause: _error!,
        ),
      ],
    ];
  }

  Widget _footer(BuildContext context) {
    final label = _submitting
        ? 'Salvando…'
        : (_keepSaleActive ? 'Tirar da locação' : 'Confirmar');
    return PdkActionPair(
      primaryFlex: 2,
      minSecondary: 90,
      primary: PdkSolidButton(
        label: label,
        tone: PdkTone.green(context),
        icon: LucideIcons.check,
        busy: _submitting,
        onPressed: _canSubmit ? _submit : null,
      ),
      secondary: PdkNeutralButton(
        label: 'Cancelar',
        onPressed: _submitting ? null : () => Navigator.of(context).pop(),
      ),
    );
  }
}

/// "Agora → Vai para": os dois status em selos; quebra de linha em tela
/// estreita (o rótulo longo "Aguardando autorização do proprietário" cabe).
class _TransitionLine extends StatelessWidget {
  const _TransitionLine({required this.from, required this.to});

  final PropertyStatusVisual from;
  final PropertyStatusVisual? to;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final next = to;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _StatusChip(visual: from, solid: false),
        if (next != null) ...[
          Icon(LucideIcons.arrowRight, size: 18, color: secondary),
          _StatusChip(visual: next, solid: true),
        ],
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.visual, required this.solid});

  final PropertyStatusVisual visual;

  /// Destino em tinta cheia (rótulo branco); atual em tom leve.
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone = visual.color;
    final fg = solid ? Colors.white : pdkInk(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: solid
            ? pdkSolid(tone)
            : tone.withValues(alpha: isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(999),
        border: solid ? null : Border.all(color: tone.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(visual.icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              visual.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
