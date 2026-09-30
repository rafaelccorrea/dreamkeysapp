import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/proposals_dashboard_service.dart';
import 'pd_common.dart';

/// Assinaturas paradas: quem está segurando a proposta e há quantos dias.
/// ≥ 7 dias = vermelho, ≥ 3 = âmbar (mesma régua do web). Com [onOpen], a
/// linha abre as assinaturas da proposta — reenviar ou copiar o link sem
/// sair do painel.
class PdBottleneckList extends StatefulWidget {
  const PdBottleneckList({super.key, required this.items, this.onOpen});

  final List<ProposalsSignatureBottleneck> items;
  final ValueChanged<ProposalsSignatureBottleneck>? onOpen;

  @override
  State<PdBottleneckList> createState() => _PdBottleneckListState();
}

class _PdBottleneckListState extends State<PdBottleneckList> {
  static const int _collapsed = 5;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = PdTones.of(context);
    final items = widget.items;
    if (items.isEmpty) {
      return const PdEmptyLine(
        'Nenhuma assinatura esperando. Fila limpa.',
        hint: 'Quando um signatário demora para assinar, ele aparece aqui '
            'com os dias de espera — do mais antigo para o mais novo.',
        icon: LucideIcons.circleCheck,
      );
    }
    final shown = _expanded ? items : items.take(_collapsed).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const PdHairline(indent: 56),
          _row(t, shown[i]),
        ],
        if (items.length > _collapsed)
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: t.text,
              padding: const EdgeInsets.symmetric(horizontal: 0),
            ),
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(
              _expanded
                  ? 'Mostrar menos'
                  : 'Ver as ${items.length} assinaturas esperando',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
      ],
    );
  }

  Widget _row(PdTones t, ProposalsSignatureBottleneck g) {
    final tone = g.pendingDays >= 7
        ? t.red
        : g.pendingDays >= 3
            ? t.amberText
            : t.muted;
    final number =
        g.proposalNumber.isEmpty ? '' : 'Nº ${g.proposalNumber} · ';
    final open = widget.onOpen;
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    pdDays(g.pendingDays),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                      color: tone,
                    ),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'de espera',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: t.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  g.signerName.isEmpty ? 'Signatário sem nome' : g.signerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${number}Etapa ${g.etapa} · ${pdEtapaNome(g.etapa)}'
                  '${g.signerEmail != null ? ' · ${g.signerEmail}' : ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                    color: t.muted,
                  ),
                ),
              ],
            ),
          ),
          if (open != null) ...[
            const SizedBox(width: 8),
            Icon(LucideIcons.chevronRight, size: 16, color: t.muted),
          ],
        ],
      ),
    );
    if (open == null) return content;
    return Semantics(
      button: true,
      label: 'Abrir assinaturas da proposta ${g.proposalNumber}',
      child: InkWell(onTap: () => open(g), child: content),
    );
  }
}

/// Contrapropostas do recorte: barra única empilhada + três números.
class PdCounterProposals extends StatelessWidget {
  const PdCounterProposals({super.key, required this.stats});

  final ProposalsCounterStats stats;

  @override
  Widget build(BuildContext context) {
    final t = PdTones.of(context);
    final s = stats;
    if (s.total == 0 && s.pendente == 0 && s.aprovada == 0 && s.recusada == 0) {
      return const PdEmptyLine(
        'Nenhuma contraproposta no período.',
        hint: 'Quando o proprietário responder uma proposta com outro valor '
            'ou condição, a contraproposta entra nesta conta.',
        icon: LucideIcons.handshake,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PdStackedBar(
          height: 10,
          segments: [
            PdSegment(s.aprovada, t.green),
            PdSegment(s.pendente, t.amber),
            PdSegment(s.recusada, t.red),
          ],
        ),
        const SizedBox(height: 14),
        PdLedger(
          gap: 10,
          children: [
            PdFigure(
              value: pdInt.format(s.aprovada),
              label: 'Aprovadas',
              tone: t.green,
              size: 19,
            ),
            PdFigure(
              value: pdInt.format(s.pendente),
              label: 'Esperando resposta',
              tone: t.amber,
              size: 19,
            ),
            PdFigure(
              value: pdInt.format(s.recusada),
              label: 'Recusadas',
              tone: t.red,
              size: 19,
            ),
          ],
        ),
      ],
    );
  }
}

/// Score de chance de fechamento (0–100) das propostas em aberto. Com
/// [onOpen], a linha abre as assinaturas da proposta para empurrá-la.
class PdScoreList extends StatefulWidget {
  const PdScoreList({super.key, required this.items, this.onOpen});

  final List<ProposalsScoreItem> items;
  final ValueChanged<ProposalsScoreItem>? onOpen;

  @override
  State<PdScoreList> createState() => _PdScoreListState();
}

class _PdScoreListState extends State<PdScoreList> {
  static const int _collapsed = 6;
  bool _expanded = false;

  Color _tone(PdTones t, int score) => score >= 70
      ? t.green
      : score >= 40
          ? t.amber
          : t.red;

  @override
  Widget build(BuildContext context) {
    final t = PdTones.of(context);
    final items = widget.items;
    if (items.isEmpty) {
      return const PdEmptyLine(
        'Nenhuma proposta em aberto para pontuar.',
        hint: 'As propostas em andamento do recorte aparecem aqui com a '
            'chance de virar venda, da maior para a menor.',
        icon: LucideIcons.gauge,
      );
    }
    final shown = _expanded ? items : items.take(_collapsed).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Régua da nota, antes das linhas: a cor do mostrador tem nome.
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            PdLegendItem(color: t.green, label: 'Alta (70 ou mais)'),
            PdLegendItem(color: t.amber, label: 'Média (40 a 69)'),
            PdLegendItem(color: t.red, label: 'Baixa (menos de 40)'),
          ],
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const PdHairline(indent: 56),
          _row(t, shown[i]),
        ],
        if (items.length > _collapsed)
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: t.text,
              padding: const EdgeInsets.symmetric(horizontal: 0),
            ),
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(
              _expanded ? 'Mostrar menos' : 'Ver as ${items.length} propostas',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
      ],
    );
  }

  Widget _row(PdTones t, ProposalsScoreItem item) {
    final tone = _tone(t, item.score);
    final number =
        item.proposalNumber.isEmpty ? '' : 'Nº ${item.proposalNumber} · ';
    final open = widget.onOpen;
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: CustomPaint(
              painter: _GaugePainter(
                fraction: item.score / 100,
                color: tone,
                track: t.track,
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${item.score}',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: t.text,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.proponentName.isEmpty
                      ? 'Proponente não informado'
                      : item.proponentName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${number}Etapa ${item.etapaAtual}/3 · '
                  '${pdPlural(item.assinaturasConcluidas, 'assinatura', 'assinaturas')} · '
                  'aberta há ${pdPlural(item.ageDays, 'dia', 'dias')}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                    color: t.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 92),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                pdBrlCompact.format(item.proposedPrice),
                maxLines: 1,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: t.text,
                ),
              ),
            ),
          ),
          if (open != null) ...[
            const SizedBox(width: 6),
            Icon(LucideIcons.chevronRight, size: 16, color: t.muted),
          ],
        ],
      ),
    );
    if (open == null) return content;
    return Semantics(
      button: true,
      label: 'Abrir assinaturas da proposta ${item.proposalNumber}',
      child: InkWell(onTap: () => open(item), child: content),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.fraction,
    required this.color,
    required this.track,
  });

  final double fraction;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 4.0;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    // Arco aberto embaixo (270°), como um mostrador.
    const start = math.pi * 0.75;
    const sweep = math.pi * 1.5;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(rect, start, sweep, false, base);
    final f = fraction.clamp(0.0, 1.0).toDouble();
    if (f > 0) {
      canvas.drawArc(
        rect,
        start,
        sweep * f,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.fraction != fraction || old.color != color || old.track != track;
}
