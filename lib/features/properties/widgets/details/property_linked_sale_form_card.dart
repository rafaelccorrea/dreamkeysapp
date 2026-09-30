import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/property_service.dart';
import '../../services/property_detail_extras_service.dart';
import 'property_details_kit.dart';
import 'property_file_delivery.dart';

/// Corpo da seção "Ficha de venda vinculada" — paridade com o
/// `LinkedSaleFormSummaryCard` do web (220-318). Vai dentro do molde flush
/// da página (`_buildFlushSection(title: 'Ficha de venda vinculada', …)`),
/// só quando [isVisible] (o detalhe trouxe `linkedSaleForm`).
///
/// Mostra: número da ficha (toque copia), status em pílula ("Finalizada",
/// "Em assinatura", "Aguardando envio para assinatura", "Cancelada"), "Ver
/// ficha" ([onOpenForm] com o id da ficha — sem ele o botão não aparece),
/// "PDF assinado" quando `canDownloadSignedPdf` (ficha finalizada) e os
/// participantes (criador, membros, signatários com o estado da assinatura).
///
/// "PDF assinado" chama `GET /sistema/fichas-venda/por-imovel/:propertyId/
/// pdf-assinado` (PDF, ou ZIP quando há mais de um documento) e abre a folha
/// "arquivo pronto" (Compartilhar / Salvar no aparelho).
class PropertyLinkedSaleFormCard extends StatefulWidget {
  const PropertyLinkedSaleFormCard({
    super.key,
    required this.propertyId,
    required this.form,
    this.onOpenForm,
  });

  final String propertyId;
  final PropertyLinkedSaleForm form;

  /// Abre a ficha de venda (recebe o id da ficha).
  final ValueChanged<String>? onOpenForm;

  static bool isVisible(Property property) => property.linkedSaleForm != null;

  /// Status da ficha → rótulo (`translateLinkedSaleFormSheetStatus` do web).
  static String statusLabel(String status) {
    switch (status.trim().toLowerCase()) {
      case 'finalized':
        return 'Finalizada';
      case 'processing':
        return 'Em assinatura';
      case 'canceled':
      case 'cancelled':
        return 'Cancelada';
      case 'waiting_for_signature':
        return 'Aguardando envio para assinatura';
      default:
        return status.trim();
    }
  }

  @override
  State<PropertyLinkedSaleFormCard> createState() =>
      _PropertyLinkedSaleFormCardState();
}

enum _ParticipantTone {
  creator,
  member,
  signerDone,
  signerWait,
  signerOther,
  neutral,
}

class _PropertyLinkedSaleFormCardState
    extends State<PropertyLinkedSaleFormCard> {
  bool _downloading = false;

  Future<void> _copyNumber() async {
    final text = widget.form.formNumber.trim();
    if (text.isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      pdkShowSnack(
        context,
        'Número da ficha copiado.',
        tone: PdkSnackTone.success,
      );
    } catch (_) {
      if (!mounted) return;
      pdkShowSnack(
        context,
        'Não foi possível copiar o número.',
        tone: PdkSnackTone.error,
      );
    }
  }

  Future<void> _downloadPdf() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    final res = await PropertyDetailExtrasService.instance
        .downloadLinkedSaleFormSignedPdf(widget.propertyId);
    if (!mounted) return;
    setState(() => _downloading = false);
    final file = res.data;
    if (!res.success || file == null) {
      final server = (res.message ?? '').trim();
      pdkShowSnack(
        context,
        server.isNotEmpty
            ? server
            : 'Erro ao baixar PDF. ${pdkFailureCause(res).cause}',
        tone: PdkSnackTone.error,
      );
      return;
    }
    final number = widget.form.formNumber.trim();
    await showPropertyFileReadySheet(
      context,
      file: file,
      title: file.isZip ? 'PDFs assinados da ficha' : 'PDF assinado da ficha',
      subtitle: number.isEmpty ? null : 'Ficha de venda nº $number',
      shareSubject: number.isEmpty
          ? 'Ficha de venda assinada'
          : 'Ficha de venda nº $number — assinada',
      hint: file.isZip
          ? 'A ficha tem mais de um documento assinado: eles vêm juntos num '
              'arquivo compactado (.zip).'
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final form = widget.form;
    final participants = _sorted(form.participants);
    final divider = ThemeHelpers.borderLightColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    final actions = <Widget>[
      if (widget.onOpenForm != null)
        PdkNeutralButton(
          label: 'Ver ficha',
          icon: LucideIcons.eye,
          onPressed: () => widget.onOpenForm!(form.id),
        ),
      if (form.canDownloadSignedPdf)
        PdkSolidButton(
          label: _downloading ? 'Preparando…' : 'PDF assinado',
          tone: PdkTone.green(context),
          icon: LucideIcons.printer,
          busy: _downloading,
          onPressed: _downloadPdf,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _NumberChip(number: form.formNumber, onTap: _copyNumber),
            _StatusPill(status: form.status),
          ],
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 12),
          if (actions.length == 2)
            PdkActionPair(
              primary: actions[1],
              secondary: actions[0],
              minPrimary: 140,
              minSecondary: 110,
            )
          else
            Align(alignment: Alignment.centerLeft, child: actions.first),
        ],
        if (!form.canDownloadSignedPdf) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(LucideIcons.info, size: 14, color: secondary),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'O PDF assinado fica disponível quando a ficha for '
                  'finalizada.',
                  style: TextStyle(
                    color: secondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (participants.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(height: 1, color: divider),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'PARTICIPANTES',
                  style: TextStyle(
                    color: secondary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
              Text(
                participants.length == 1
                    ? '1 pessoa'
                    : '${participants.length} pessoas',
                style: TextStyle(
                  color: secondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < participants.length; i++) ...[
            if (i > 0) Container(height: 1, color: divider),
            _ParticipantRow(participant: participants[i]),
          ],
        ],
      ],
    );
  }

  /// Criador → membros → signatários, por nome
  /// (`sortLinkedSaleFormParticipants` do web).
  static List<PropertyLinkedSaleFormParticipant> _sorted(
    List<PropertyLinkedSaleFormParticipant> list,
  ) {
    int rank(PropertyLinkedSaleFormParticipant p) {
      final r = p.role.toLowerCase();
      if (r == 'criador') return 0;
      if (r.contains('membro_vinculado') || r.contains('membro vinculado')) {
        return 1;
      }
      if (r.contains('signat')) return 2;
      return 3;
    }

    final out = [...list];
    out.sort((a, b) {
      final d = rank(a) - rank(b);
      if (d != 0) return d;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }
}

_ParticipantTone _toneOf(String role) {
  final r = role.toLowerCase();
  if (r == 'criador') return _ParticipantTone.creator;
  if (r.contains('membro_vinculado') || r.contains('membro vinculado')) {
    return _ParticipantTone.member;
  }
  if (r.contains('signat')) {
    if (r.contains('signed')) return _ParticipantTone.signerDone;
    if (r.contains('pending') || r.contains('viewed')) {
      return _ParticipantTone.signerWait;
    }
    return _ParticipantTone.signerOther;
  }
  return _ParticipantTone.neutral;
}

/// Rótulo curto do papel (`shortLinkedSaleFormParticipantRole` do web).
String _shortRole(String role) {
  final r = role.toLowerCase();
  if (r == 'criador') return 'Criador';
  if (r.contains('membro_vinculado') || r.contains('membro vinculado')) {
    return 'Membro';
  }
  if (r.contains('signat')) {
    if (r.contains('signed')) return 'Assinado';
    if (r.contains('pending')) return 'Pendente';
    if (r.contains('viewed')) return 'Visualizou';
    if (r.contains('rejected')) return 'Recusado';
    if (r.contains('expired')) return 'Expirado';
    if (r.contains('cancel')) return 'Cancelado';
    return 'Signatário';
  }
  final raw = role.trim();
  return raw.isEmpty ? 'Participante' : raw.replaceAll('_', ' ');
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({required this.participant});

  final PropertyLinkedSaleFormParticipant participant;

  @override
  Widget build(BuildContext context) {
    final Color tone;
    switch (_toneOf(participant.role)) {
      case _ParticipantTone.creator:
        tone = PdkTone.blue(context);
      case _ParticipantTone.member:
        tone = PdkTone.violet(context);
      case _ParticipantTone.signerDone:
        tone = PdkTone.green(context);
      case _ParticipantTone.signerWait:
        tone = PdkTone.amber(context);
      case _ParticipantTone.signerOther:
        tone = PdkTone.red(context);
      case _ParticipantTone.neutral:
        tone = ThemeHelpers.textSecondaryColor(context);
    }
    final email = participant.email?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _shortRole(participant.role).toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: pdkInk(context, tone),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            participant.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: ThemeHelpers.textColor(context),
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
          if (email.isNotEmpty)
            Text(
              email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ThemeHelpers.textSecondaryColor(context),
                fontSize: 12,
                height: 1.35,
              ),
            ),
        ],
      ),
    );
  }
}

/// "NÚMERO  4521" com o ícone de copiar — toque copia (o
/// `PropertyHeroCodeInline` do web).
class _NumberChip extends StatelessWidget {
  const _NumberChip({required this.number, required this.onTap});

  final String number;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(color: ThemeHelpers.borderLightColor(context)),
    );
    final value = number.trim().isEmpty ? 'sem número' : number.trim();
    return Tooltip(
      message: 'Copiar número da ficha',
      child: Material(
        color: Colors.transparent,
        shape: shape,
        child: InkWell(
          onTap: number.trim().isEmpty ? null : onTap,
          customBorder: shape,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'NÚMERO',
                    style: TextStyle(
                      color: secondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ThemeHelpers.textColor(context),
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(LucideIcons.copy, size: 13, color: secondary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final s = status.trim().toLowerCase();
    final Color tone;
    if (s == 'finalized') {
      tone = PdkTone.green(context);
    } else if (s == 'processing') {
      tone = PdkTone.amber(context);
    } else if (s == 'waiting_for_signature') {
      tone = PdkTone.blue(context);
    } else {
      tone = PdkTone.red(context);
    }
    final label = PropertyLinkedSaleFormCard.statusLabel(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.32)),
      ),
      child: Text(
        label.isEmpty ? 'Sem status' : label.toUpperCase(),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: pdkInk(context, tone),
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
