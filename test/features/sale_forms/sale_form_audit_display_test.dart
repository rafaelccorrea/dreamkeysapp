import 'package:Intellisys/features/sale_forms/sale_form_audit_display.dart';
import 'package:flutter_test/flutter_test.dart';

String _plain(String s) => s.replaceAll('\u00A0', ' ');

void main() {
  test('rótulo das ações (auditActionLabelPt)', () {
    expect(saleFormAuditActionLabel('update'), 'Edição');
    expect(saleFormAuditActionLabel('linked_users_add'), 'Usuários vinculados');
    expect(saleFormAuditActionLabel('algo_novo'), 'algo_novo');
    expect(saleFormAuditActionLabel(''), 'Evento');
  });

  group('mudança só de formato não aparece', () {
    test('data, dinheiro e CPF equivalentes', () {
      expect(
        saleFormAuditValuesEqual(
            'saleDate', '2026-09-20', '2026-09-20T00:00:00.000Z'),
        isTrue,
      );
      expect(saleFormAuditValuesEqual('saleValue', '296000,00', '296000'),
          isTrue);
      expect(saleFormAuditValuesEqual('buyerCpf', '123.456.789-09',
          '12345678909'), isTrue);
      expect(saleFormAuditValuesEqual('saleValue', '1000', '2000'), isFalse);
      expect(saleFormAuditValuesEqual('buyerName', null, ''), isTrue);
    });

    test('partition separa visíveis e cosméticas', () {
      final p = saleFormPartitionAuditChanges(const [
        SaleFormAuditChange(field: 'saleValue', before: '10', after: '10.00'),
        SaleFormAuditChange(field: 'buyerName', before: 'A', after: 'B'),
      ]);
      expect(p.visible.single.field, 'buyerName');
      expect(p.cosmeticCount, 1);
    });
  });

  group('valor formatado como na tela do web', () {
    test('datas, R\$, CPF/CNPJ, telefone, CEP e status', () {
      expect(saleFormAuditValue('saleDate', '2026-09-20T00:00:00Z'),
          '20/09/2026');
      expect(_plain(saleFormAuditValue('saleValue', '296000')),
          'R\$ 296.000,00');
      expect(saleFormAuditValue('buyerCpf', '12345678909'), '123.456.789-09');
      expect(saleFormAuditValue('sellerCpf', '12345678000195'),
          '12.345.678/0001-95');
      expect(saleFormAuditValue('buyerPhone', '5511987654321'),
          '(11) 98765-4321');
      expect(saleFormAuditValue('propertyZipCode', '01310100'), '01310-100');
      expect(saleFormAuditValue('status', 'finalized'), 'Finalizada');
      expect(saleFormAuditValue('buyerName', null), '—');
      expect(saleFormAuditValue('buyerName', '  '), '—');
    });

    test('comissões em texto legível', () {
      final s = saleFormAuditValue(
        'commissionsData',
        '{"corretores":[{"nome":"Ana","funcao":"corretor","porcentagem":2.5}],'
            '"gerencias":[{"nome":"Beto","nivel":1,"porcentagem":1}]}',
      );
      expect(s, contains('Ana (corretor) — 2,5%'));
      expect(s, contains('Gerências:'));
      expect(s, contains('Beto — 1%'));
    });
  });

  test('metadados em linhas legíveis', () {
    final rows = saleFormAuditMetadataRows({
      'formNumber': 'FV-10',
      'addedUsers': [
        {'name': 'Ana', 'email': 'ana@x.com'},
        {'name': ''},
      ],
      'invalidatedSignatures': 3,
    });
    expect(rows.map((r) => r.label), [
      'Número da ficha',
      'Usuários incluídos na ficha',
      'Assinaturas afetadas',
    ]);
    expect(rows[1].value, 'Ana (ana@x.com)\nSem nome');
  });

  test('entrada do back: autor "Sistema" e changes com objeto', () {
    final e = SaleFormAuditEntry.fromJson({
      'id': '1',
      'action': 'update',
      'createdAt': '2026-10-01T12:00:00Z',
      'changes': [
        {
          'field': 'commissionsData',
          'label': 'Comissões',
          'before': null,
          'after': {'corretores': []},
        },
      ],
    });
    expect(e.autor, 'Sistema');
    expect(e.actionLabel, 'Edição');
    expect(e.changes.single.after, '{"corretores":[]}');
    expect(e.changes.single.rotulo, 'Comissões');
  });
}
