import 'package:Intellisys/features/inspections/utils/inspection_checklist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InspectionChecklist — igual ao detalhe da web', () {
    test('traduz chaves conhecidas em inglês e português', () {
      expect(InspectionChecklist.chave('walls'), 'Paredes');
      expect(InspectionChecklist.chave('LIVING_ROOM'), 'Sala');
      expect(InspectionChecklist.chave('area_externa'), 'Área Externa');
    });

    test('chave desconhecida vira título com espaços', () {
      expect(InspectionChecklist.chave('caixa_dagua'), 'Caixa Dagua');
    });

    test('traduz valores e mantém o desconhecido', () {
      expect(
        InspectionChecklist.valor('needs_maintenance'),
        'Precisa Manutenção',
      );
      expect(InspectionChecklist.valor('YES'), 'Sim');
      expect(InspectionChecklist.valor('trincado'), 'trincado');
      expect(InspectionChecklist.valor(null), '');
    });

    test('cores por significado', () {
      expect(InspectionChecklist.cor('excellent'), const Color(0xFF10B981));
      expect(InspectionChecklist.cor('Ruim'), const Color(0xFFDC2626));
      expect(
        InspectionChecklist.cor('precisa reparo'),
        const Color(0xFFEF4444),
      );
      expect(InspectionChecklist.cor('ok'), isNull);
    });
  });
}
