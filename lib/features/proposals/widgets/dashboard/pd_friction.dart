import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/proposals_dashboard_service.dart';
import 'pd_common.dart';

/// Assinaturas paradas: quem está segurando a proposta e há quantos dias.
/// ≥ 7 dias = vermelho, ≥ 3 = âmbar (mesma régua do web).
class PdBottleneckList extends StatefulWidget {
  const PdBottleneckList({super.key, required this.items});

  final List<ProposalsSignatureBottleneck> items;

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
      return const PdEmptyLine('Nenhuma assinatura parada. Fila limpa.');
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
              padding: EdgeInsets.zero,
            ),
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(
              _expanded
                  ? 'Mostrar menos'
                  : 'Ver as ${items.length} assinaturas paradas',
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
            ? t.amber
            : t.muted;
    final number = g.proposalNumber.isEmpty ? '' : '#${g.proposalNumber} · ';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: FittedBox(
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
                  '${number}Etapa ${g.etapa}/3'
                  '${g.signerEmail != null ? ' · ${g.signerEmail}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: t.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
      return const PdEmptyLine('Nenhuma contraproposta no período.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PdStackedBar(
          height: 10,
          segments: [
            PdSegment(s.aprovada, t.green),
            PdSegment(s.pendente, t.amber),
            PdSegment(s.recusada, t.red),
          ],
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _cell(t, 'Aprovadas', s.aprovada, t.green)),
              _divider(t),
              Expanded(child: _cell(t, 'Pendentes', s.pendente, t.amber)),
              _divider(t),
              Expanded(child: _cell(t, 'Recusadas', s.recusada, t.red)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _divider(PdTones t) => Container(
        width: 1,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        color: t.hairline,
      );

  Widget _cell(PdTones t, String label, int value, Color tone) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            pdInt.format(value),
            maxLines: 1,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: value > 0 ? tone : t.muted,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: t.muted,
          ),
        ),
      ],
    );
  }
}

/// Score de chance de fechamento (0–100) das propostas em aberto.
class PdScoreList extends StatefulWidget {
  const PdScoreList({super.key, required this.items});

  final List<ProposalsScoreItem> items;

  @override
  State<PdScoreList> createState() => _PdScoreListState();
}

class _PdScoreListState extends State<PdScoreList> {
  static const int _collapsed = 6;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = PdTones.of(context);
    final items = widget.items;
    if (items.isEmpty) {
      return const PdEmptyLine('Nenhuma proposta em aberto para pontuar.');
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
              padding: EdgeInsets.zero,
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
    final tone = item.score >= 70
        ? t.green
        : item.score >= 40
            ? t.amber
            : t.red;
    final number = item.proposalNumber.isEmpty ? '' : '#${item.proposalNumber} · ';
    return Padding(
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
                  '${item.assinaturasConcluidas} assinaturas · '
                  '${item.ageDays} ${item.ageDays == 1 ? 'dia' : 'dias'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
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
        ],
      ),
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
