import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/property_service.dart';
import '../../../../shared/utils/error_cause.dart';
import '../../../../shared/utils/property_finalidade.dart';
import 'property_details_kit.dart';

/// Motivo da trava de ativar/desativar para quem não é gestão — a frase do
/// back (`assertUserMayToggleActive`).
const String kPropertyToggleActiveBlockedReason =
    'Apenas administradores e gestores podem ativar ou desativar imóveis. '
    'Para liberar o acesso, fale com o seu gestor ou com o suporte.';

/// Abre a folha de Ativo/Inativo do imóvel — paridade com o
/// `PropertyActiveToggle` + `PropertyDeactivationModal` do web (W:2164-2173,
/// modal 463-592).
///
/// - Imóvel ATIVO → "O que você quer desativar?": escopo Desativar por
///   completo / Tirar só da venda / Tirar só da locação (as duas parciais só
///   ficam escolhíveis com finalidade efetiva `ambos`; nos outros casos
///   aparecem travadas com o motivo do web), motivo OBRIGATÓRIO (os 9 de
///   [PropertyDeactivationReason]) e observação opcional (até 2000) →
///   `deactivateProperty(reason, notes, scope)`.
/// - Imóvel INATIVO → confirmação de reativação (mostra quando/por que foi
///   desativado) → `activateProperty` (`PATCH /properties/:id/activate`).
///   Resposta "já está ativo" conta como mudança (o web recarrega em
///   silêncio).
/// - [canToggle] `false` (quem não é master/admin/gestor — o gate é da
///   página, mesmo do web) abre a folha travada com o motivo; [lockedReason]
///   troca o texto (ex.: "Imóvel excluído — somente consulta").
///
/// Devolve `true` quando o servidor mudou algo — a página recarrega a ficha
/// (`_loadProperty()`); o aviso de sucesso já sai daqui.
Future<bool> showPropertyActivationSheet({
  required BuildContext context,
  required Property property,
  bool canToggle = true,
  String? lockedReason,
}) async {
  final outcome = PdkSheetOutcome();
  final custom = lockedReason?.trim() ?? '';
  final reason = custom.isNotEmpty
      ? custom
      : (canToggle ? null : kPropertyToggleActiveBlockedReason);
  await showPdkSheet<void>(
    context: context,
    builder: (_) {
      if (reason != null) {
        return _LockedToggleSheet(property: property, reason: reason);
      }
      if (property.isActive) {
        return _DeactivateSheet(property: property, outcome: outcome);
      }
      return _ActivateSheet(property: property, outcome: outcome);
    },
  );
  await outcome.settle();
  final message = outcome.message;
  if (outcome.changed && message != null && context.mounted) {
    pdkShowSnack(context, message, tone: PdkSnackTone.success);
  }
  return outcome.changed;
}

String _subtitleOf(Property property) {
  final code = property.code?.trim() ?? '';
  final title = property.title.trim();
  return [
    if (code.isNotEmpty) 'Imóvel $code',
    if (title.isNotEmpty) title,
  ].join(' · ');
}

// ─── Travada ────────────────────────────────────────────────────────────────

class _LockedToggleSheet extends StatelessWidget {
  const _LockedToggleSheet({required this.property, required this.reason});

  final Property property;
  final String reason;

  @override
  Widget build(BuildContext context) {
    final subtitle = _subtitleOf(property);
    return PdkSheetFrame(
      icon: LucideIcons.lockKeyhole,
      tone: PdkTone.violet(context),
      title: property.isActive ? 'Desativar imóvel' : 'Ativar imóvel',
      subtitle: subtitle.isEmpty ? null : subtitle,
      onClose: () => Navigator.of(context).pop(),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ActiveStateLine(property: property),
            const SizedBox(height: 14),
            PdkLockNote(
              title: property.isActive
                  ? 'Desativar está travado'
                  : 'Ativar está travado',
              reason: reason,
            ),
          ],
        ),
      ),
      footer: PdkNeutralButton(
        label: 'Fechar',
        onPressed: () => Navigator.of(context).pop(),
      ),
    );
  }
}

/// "Ativo no sistema" / "Inativo desde …" numa linha, com o ponto no tom.
class _ActiveStateLine extends StatelessWidget {
  const _ActiveStateLine({required this.property});

  final Property property;

  @override
  Widget build(BuildContext context) {
    final active = property.isActive;
    final tone = active ? PdkTone.green(context) : PdkTone.red(context);
    final since = pdkStamp(property.deactivatedAt);
    final text = active
        ? 'Ativo no sistema'
        : (since == null ? 'Inativo no sistema' : 'Inativo desde $since');
    return Row(
      children: [
        Icon(
          active ? LucideIcons.circleCheckBig : LucideIcons.circleOff,
          size: 16,
          color: pdkInk(context, tone),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: pdkInk(context, tone),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Ativar ─────────────────────────────────────────────────────────────────

class _ActivateSheet extends StatefulWidget {
  const _ActivateSheet({required this.property, required this.outcome});

  final Property property;
  final PdkSheetOutcome outcome;

  @override
  State<_ActivateSheet> createState() => _ActivateSheetState();
}

class _ActivateSheetState extends State<_ActivateSheet> {
  bool _submitting = false;
  ErrorCause? _error;

  void _submit() {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    widget.outcome.inFlight = _send();
  }

  Future<void> _send() async {
    final res = await PropertyService.instance.activateProperty(
      widget.property.id,
    );
    // "Propriedade já está ativa": o estado desejado já vale — o web só
    // recarrega em silêncio.
    final already = (res.message ?? '').toLowerCase().contains('já está');
    if (pdkApplied(res) || already) {
      widget.outcome.changed = true;
      widget.outcome.message = already ? null : 'Imóvel ativado.';
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = pdkFailureCause(res);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.property;
    final subtitle = _subtitleOf(p);
    final reasonLabel = (p.deactivationReasonLabel ?? '').trim().isNotEmpty
        ? p.deactivationReasonLabel!.trim()
        : PropertyDeactivationReason.labelOf(p.deactivationReason);
    final notes = p.deactivationNotes?.trim() ?? '';
    final secondary = ThemeHelpers.textSecondaryColor(context);

    return PopScope(
      canPop: !_submitting,
      child: PdkSheetFrame(
        icon: LucideIcons.power,
        tone: PdkTone.green(context),
        title: 'Reativar o imóvel?',
        subtitle: subtitle.isEmpty ? null : subtitle,
        onClose: _submitting ? null : () => Navigator.of(context).pop(),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ActiveStateLine(property: p),
              if (reasonLabel.isNotEmpty || notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                _DeactivationRecord(reason: reasonLabel, notes: notes),
              ],
              const SizedBox(height: 16),
              const PdkBlockLabel('O que acontece'),
              const SizedBox(height: 8),
              _EffectLine(
                icon: LucideIcons.circleCheckBig,
                tone: PdkTone.green(context),
                text: 'Volta a ser tratado como ativo no CRM.',
              ),
              const SizedBox(height: 6),
              // A desativação tira o imóvel do site e da vitrine; ativar
              // devolve ao CRM, não ao site (regra do back).
              _EffectLine(
                icon: LucideIcons.info,
                tone: secondary,
                text: 'O anúncio no site não volta sozinho — para anunciar '
                    'de novo, use "Republicar no site".',
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                PdkErrorNote(
                  title: 'Não foi possível ativar o imóvel',
                  cause: _error!,
                ),
              ],
            ],
          ),
        ),
        footer: PdkActionPair(
          primaryFlex: 2,
          minSecondary: 90,
          primary: PdkSolidButton(
            label: _submitting ? 'Ativando…' : 'Ativar imóvel',
            tone: PdkTone.green(context),
            icon: LucideIcons.power,
            busy: _submitting,
            onPressed: _submit,
          ),
          secondary: PdkNeutralButton(
            label: 'Cancelar',
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }
}

/// Registro da última desativação (motivo e observação), em papel.
class _DeactivationRecord extends StatelessWidget {
  const _DeactivationRecord({required this.reason, required this.notes});

  final String reason;
  final String notes;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ThemeHelpers.borderLightColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Motivo da desativação',
            style: TextStyle(
              color: secondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              reason,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              notes,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: secondary, fontSize: 12.5, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

class _EffectLine extends StatelessWidget {
  const _EffectLine({
    required this.icon,
    required this.tone,
    required this.text,
  });

  final IconData icon;
  final Color tone;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: pdkInk(context, tone)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: ThemeHelpers.textColor(context),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Desativar ──────────────────────────────────────────────────────────────

/// Escopo da desativação — o `value` é o `scope` do PATCH.
enum _Scope {
  all('all'),
  sale('sale'),
  rent('rent');

  const _Scope(this.value);

  final String value;
}

class _DeactivateSheet extends StatefulWidget {
  const _DeactivateSheet({required this.property, required this.outcome});

  final Property property;
  final PdkSheetOutcome outcome;

  @override
  State<_DeactivateSheet> createState() => _DeactivateSheetState();
}

class _DeactivateSheetState extends State<_DeactivateSheet> {
  _Scope _scope = _Scope.all;
  PropertyDeactivationReason? _reason;
  String? _reasonError;
  final TextEditingController _notes = TextEditingController();
  bool _submitting = false;
  ErrorCause? _error;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  PropertyFinalidade? get _finalidade => finalidadeEfetiva(
        finalidade: PropertyFinalidade.tryParse(widget.property.finalidade),
        salePrice: widget.property.salePrice,
        rentPrice: widget.property.rentPrice,
      );

  bool get _isBoth => _finalidade == PropertyFinalidade.ambos;

  /// Por que a opção parcial está travada — as frases do web
  /// (`motivoBloqueio`), que distinguem "só anunciado para X" de "já não é
  /// anunciado para X (o valor segue na ficha)".
  String _blockedReason({required bool sale}) {
    final f = _finalidade;
    final alvo = sale ? 'venda' : 'locação';
    if (f == null) {
      return 'Sem valor de venda nem de locação: use a desativação por '
          'completo.';
    }
    final isTarget = sale
        ? f == PropertyFinalidade.venda
        : f == PropertyFinalidade.locacao;
    if (isTarget) {
      return 'Este imóvel está marcado apenas para $alvo — use a desativação '
          'por completo.';
    }
    final bothPrices = (widget.property.salePrice ?? 0) > 0 &&
        (widget.property.rentPrice ?? 0) > 0;
    return 'Este imóvel já não é anunciado para $alvo'
        '${bothPrices ? ' (o valor segue preenchido na ficha, mas ele não entra nas buscas dessa finalidade).' : '.'}';
  }

  void _submit() {
    if (_submitting) return;
    if (_reason == null) {
      setState(() {
        _reasonError =
            'Selecione o motivo — ele alimenta as métricas da carteira.';
      });
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    widget.outcome.inFlight = _send(_reason!, _scope);
  }

  Future<void> _send(PropertyDeactivationReason reason, _Scope scope) async {
    final notes = _notes.text.trim();
    final res = await PropertyService.instance.deactivateProperty(
      widget.property.id,
      reason: reason.value,
      notes: notes.isEmpty ? null : notes,
      scope: scope.value,
    );
    if (pdkApplied(res)) {
      widget.outcome.changed = true;
      switch (scope) {
        case _Scope.all:
          widget.outcome.message = 'Imóvel desativado.';
        case _Scope.sale:
          widget.outcome.message =
              'Imóvel retirado da venda — segue anunciado para locação.';
        case _Scope.rent:
          widget.outcome.message =
              'Imóvel retirado da locação — segue anunciado para venda.';
      }
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = pdkFailureCause(res);
    });
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = _subtitleOf(widget.property);
    final red = PdkTone.red(context);
    final blue = PdkTone.blue(context);
    final amber = PdkTone.amber(context);
    final isBoth = _isBoth;
    final String actionLabel;
    switch (_scope) {
      case _Scope.all:
        actionLabel = 'Confirmar desativação';
      case _Scope.sale:
        actionLabel = 'Confirmar: tirar da venda';
      case _Scope.rent:
        actionLabel = 'Confirmar: tirar da locação';
    }

    return PopScope(
      canPop: !_submitting,
      child: PdkSheetFrame(
        icon: LucideIcons.powerOff,
        tone: red,
        title: 'O que você quer desativar?',
        subtitle: subtitle.isEmpty ? null : subtitle,
        onClose: _submitting ? null : () => Navigator.of(context).pop(),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PdkBlockLabel('Escopo'),
              const SizedBox(height: 10),
              PdkChoiceRow(
                icon: LucideIcons.powerOff,
                tone: red,
                title: 'Desativar por completo',
                description: 'O imóvel sai do site e deixa de ser tratado '
                    'como ativo — continua no cadastro.',
                selected: _scope == _Scope.all,
                onTap: _submitting
                    ? null
                    : () => setState(() => _scope = _Scope.all),
              ),
              const SizedBox(height: 8),
              PdkChoiceRow(
                icon: LucideIcons.tag,
                tone: blue,
                title: 'Tirar só da venda',
                description: 'Some dos resultados de compra no site; segue '
                    'anunciado para locação.',
                lockedReason: isBoth ? null : _blockedReason(sale: true),
                selected: _scope == _Scope.sale,
                onTap: _submitting
                    ? null
                    : () => setState(() => _scope = _Scope.sale),
              ),
              const SizedBox(height: 8),
              PdkChoiceRow(
                icon: LucideIcons.key,
                tone: amber,
                title: 'Tirar só da locação',
                description: 'Some dos resultados de aluguel no site; segue '
                    'anunciado para venda.',
                lockedReason: isBoth ? null : _blockedReason(sale: false),
                selected: _scope == _Scope.rent,
                onTap: _submitting
                    ? null
                    : () => setState(() => _scope = _Scope.rent),
              ),
              if (_scope != _Scope.all) ...[
                const SizedBox(height: 12),
                PdkNote(
                  icon: LucideIcons.info,
                  tone: amber,
                  text: 'O imóvel continua ativo no CRM e no site — só deixa '
                      'de aparecer em uma das operações. Para tirar do ar por '
                      'completo, escolha a primeira opção.',
                ),
              ],
              const SizedBox(height: 20),
              DropdownButtonFormField<PropertyDeactivationReason>(
                initialValue: _reason,
                isExpanded: true,
                // Altura pelo conteúdo: motivo longo em 2 linhas com fonte
                // grande não cabe nos 48 fixos do padrão.
                itemHeight: null,
                menuMaxHeight: 380,
                borderRadius: BorderRadius.circular(14),
                dropdownColor: ThemeHelpers.cardBackgroundColor(context),
                icon: Icon(
                  LucideIcons.chevronDown,
                  size: 18,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
                hint: Text(
                  'Selecione um motivo…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                decoration: pdkFieldDecoration(
                  context,
                  label: 'Motivo *',
                  accent: red,
                  errorText: _reasonError,
                ),
                selectedItemBuilder: (context) => [
                  for (final r in PropertyDeactivationReason.values)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        r.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: ThemeHelpers.textColor(context),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
                items: [
                  for (final r in PropertyDeactivationReason.values)
                    DropdownMenuItem<PropertyDeactivationReason>(
                      value: r,
                      child: Text(
                        r.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: ThemeHelpers.textColor(context),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) => setState(() {
                          _reason = value;
                          _reasonError = null;
                        }),
              ),
              const SizedBox(height: 14),
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
                  label: 'Observação (opcional)',
                  hint: 'Detalhes que ajudem o time a entender a decisão…',
                  accent: red,
                  multiline: true,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                PdkErrorNote(
                  title: _scope == _Scope.all
                      ? 'Não foi possível desativar o imóvel'
                      : 'Não foi possível tirar o imóvel desta operação',
                  cause: _error!,
                ),
              ],
            ],
          ),
        ),
        footer: PdkActionPair(
          primaryFlex: 2,
          minSecondary: 90,
          primary: PdkSolidButton(
            label: _submitting ? 'Aplicando…' : actionLabel,
            tone: red,
            icon: LucideIcons.powerOff,
            busy: _submitting,
            onPressed: _submit,
          ),
          secondary: PdkNeutralButton(
            label: 'Cancelar',
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }
}
