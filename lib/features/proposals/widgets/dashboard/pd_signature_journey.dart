import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/proposals_dashboard_service.dart';
import 'pd_common.dart';

class _Station {
  final String label;
  final int value;
  final Color color;

  const _Station(this.label, this.value, this.color);
}

/// Jornada da proposta como trilho de estações: processamento → etapas de
/// assinatura → finalizada; as saídas (cancelada/excluída) ficam num ramal
/// abaixo, separadas do caminho principal.
class PdSignatureRail extends StatelessWidget {
  const PdSignatureRail({super.key, required this.funnel});

  final ProposalsFunnel funnel;

  @override
  Widget build(BuildContext context) {
    final t = PdTones.of(context);
    final main = [
      _Station('Em processamento', funnel.processing, t.blue),
      _Station('Etapa 1 concluída', funnel.etapa1Concluida, t.amber),
      _Station('Etapa 2 concluída', funnel.etapa2Concluida, t.amber),
      _Station('Etapa 3 concluída', funnel.etapa3Concluida, t.green),
      _Station('Finalizada', funnel.finalized, t.green),
    ];
    final exits = [
      _Station('Cancelada', funnel.canceled, t.amber),
      _Station('Excluída', funnel.excluida, t.red),
    ];
    final max = [...main, ...exits].fold<int>(0, (m, s) => math.max(m, s.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < main.length; i++)
          _row(
            context,
            main[i],
            max,
            first: i == 0,
            last: i == main.length - 1,
            lineColor: t.track,
          ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(left: 28),
          child: Text(
            'SAÍDAS',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: t.muted,
            ),
          ),
        ),
        const SizedBox(height: 2),
        for (var i = 0; i < exits.length; i++)
          _row(
            context,
            exits[i],
            max,
            first: true,
            last: true,
            lineColor: Colors.transparent,
          ),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    _Station s,
    int max, {
    required bool first,
    required bool last,
    required Color lineColor,
  }) {
    final t = PdTones.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 18,
            child: CustomPaint(
              painter: _StationPainter(
                color: s.value > 0 ? s.color : t.track,
                line: lineColor,
                first: first,
                last: last,
                hollow: s.value == 0,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: t.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        pdInt.format(s.value),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: s.value > 0 ? t.text : t.muted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  PdMeter(
                    fraction: max == 0 ? 0 : s.value / max,
                    color: s.color,
                    height: 5,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StationPainter extends CustomPainter {
  _StationPainter({
    required this.color,
    required this.line,
    required this.first,
    required this.last,
    required this.hollow,
  });

  final Color color;
  final Color line;
  final bool first;
  final bool last;
  final bool hollow;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    const cy = 16.0;
    final lp = Paint()
      ..color = line
      ..strokeWidth = 2;
    if (!first) canvas.drawLine(Offset(cx, 0), Offset(cx, cy), lp);
    if (!last) canvas.drawLine(Offset(cx, cy), Offset(cx, size.height), lp);
    if (hollow) {
      canvas.drawCircle(
        Offset(cx, cy),
        4.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color,
      );
    } else {
      canvas.drawCircle(Offset(cx, cy), 5.5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _StationPainter old) =>
      old.color != color ||
      old.line != line ||
      old.first != first ||
      old.last != last ||
      old.hollow != hollow;
}

/// Assinaturas por etapa (assinadas / pendentes / canceladas) + prazos
/// médios. Os prazos vêm em dias.
class PdSignatureStages extends StatelessWidget {
  const PdSignatureStages({super.key, required this.signatures});

  final ProposalsSignatures signatures;

  @override
  Widget build(BuildContext context) {
    final t = PdTones.of(context);
    final s = signatures;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _figure(
                  t,
                  pdDays(s.tempoMedioPorSignatario),
                  'por signatário, em média',
                ),
              ),
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                color: t.hairline,
              ),
              Expanded(
                child: _figure(
                  t,
                  pdDays(s.tempoMedioAtePropostaConcluida),
                  'até a proposta concluir',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (s.porEtapa.isEmpty)
          const PdEmptyLine('Nenhuma assinatura no período.')
        else
          for (final e in s.porEtapa)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Etapa ${e.etapa}',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: t.text,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${pdInt.format(e.signed)} assinadas · '
                          '${pdInt.format(e.pending)} pendentes · '
                          '${pdInt.format(e.cancelled)} canceladas',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: t.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  PdStackedBar(
                    height: 8,
                    segments: [
                      PdSegment(e.signed, t.green),
                      PdSegment(e.pending, t.amber),
                      PdSegment(e.cancelled, t.muted.withValues(alpha: 0.5)),
                    ],
                  ),
                ],
              ),
            ),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            _legend(t, t.green, '${pdInt.format(s.totalAssinadas)} assinadas'),
            _legend(t, t.amber, '${pdInt.format(s.totalPendentes)} pendentes'),
            _legend(
              t,
              t.muted.withValues(alpha: 0.5),
              '${pdInt.format(s.totalCanceladas)} canceladas',
            ),
          ],
        ),
      ],
    );
  }

  Widget _figure(PdTones t, String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: t.text,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 2,
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

  Widget _legend(PdTones t, Color c, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PdDot(color: c),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: t.text,
          ),
        ),
      ],
    );
  }
}
