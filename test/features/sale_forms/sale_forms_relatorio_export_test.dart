import 'package:Intellisys/features/sale_forms/sale_forms_relatorio_export.dart';
import 'package:Intellisys/features/sale_forms/signature_lock_policy.dart';
import 'package:flutter_test/flutter_test.dart';

String _plain(String s) => s.replaceAll('\u00A0', ' ');

Map<String, dynamic> _ficha() => {
      'formNumber': 'FV-0042',
      'status': 'finalized',
      'buyerName': 'Ana Souza',
      'buyerPhone': '11987654321',
      'buyerCpf': '12345678909',
      'buyerEmail': 'ana@x.com',
      'sellerName': 'Beto',
      'sellerCpf': '12345678000195', // CNPJ não sai na coluna de CPF
      'sellerSpousePhone': '1133334444',
      'user': {'name': 'Carla'},
      'createdAt': '2026-10-01T15:30:00.000Z',
      'updatedAt': '2026-10-02T15:30:00.000Z',
      'saleDate': '2026-09-20T00:00:00.000Z',
      'mediaSource': 'DISPAROS MANYCHAT',
      'propertyAddress': 'Rua A',
      'propertyNumber': '10',
      'propertyCity': 'Campinas',
      'propertyState': 'SP',
      'propertyZipCode': '13000-000',
      'saleValue': '500000.00',
      'totalCommission': 30000,
      'commissionsData': {
        'corretores': [
          {'nome': 'Dani', 'funcao': 'corretor', 'porcentagem': 2.5},
          {'nome': 'Edu', 'funcao': 'sdr', 'porcentagem': 0, 'valorFixo': 300},
        ],
        'gerencias': [
          {'nome': 'Fábio', 'nivel': 1, 'porcentagem': 1},
        ],
      },
      'lastAudit': {
        'createdAt': '2026-10-02T15:30:00.000Z',
        'action': 'update',
        'userName': 'Carla',
        'changesCount': 2,
        'changes': [
          {'field': 'saleValue', 'label': 'Valor', 'before': '450000', 'after': '500000'},
          {'field': 'saleDate', 'before': '2026-09-20', 'after': '2026-09-20T00:00:00Z'},
        ],
      },
    };

void main() {
  test('linha do relatório com as colunas do web', () {
    final row = saleFormsExportRow(_ficha());
    expect(row.length, kSaleFormsExportHeaders.length);
    String col(String h) => row[kSaleFormsExportHeaders.indexOf(h)];
    expect(col('Nº ficha'), 'FV-0042');
    expect(col('Comprador — telefone'), '(11) 98765-4321');
    expect(col('Comprador — CPF'), '123.456.789-09');
    expect(col('Vendedor — CPF'), '—');
    expect(col('Cônjuge do vendedor — telefone'), '(11) 3333-4444');
    expect(col('Criador (usuário)'), 'Carla');
    // 15:30 UTC = 12:30 em Brasília.
    expect(col('Data de criação'), '01/10/2026 12:30');
    expect(col('Data da compra'), '20/09/2026');
    expect(col('Mídia de origem'), 'DISPAROS MANYCHAT');
    expect(col('Endereço do imóvel'), 'Rua A, 10 · Campinas/SP · CEP 13000-000');
    expect(_plain(col('Valor venda')), 'R\$ 500.000,00');
    expect(col('Status'), 'Finalizada');
    expect(col('Última auditoria — ação'), 'Edição');
    expect(col('Última auditoria — qtd. campos'), '2');
  });

  test('telefones de todos os envolvidos numa célula', () {
    expect(
      saleFormsExportTelefones(_ficha()),
      'Comprador: Ana Souza — (11) 98765-4321 · '
      'Cônjuge do vendedor: (11) 3333-4444',
    );
  });

  test('comissionados: % ou valor fixo e gerência com nível', () {
    final s = _plain(saleFormsExportComissionados(_ficha()));
    expect(s, 'Corretor: Dani (2,5%) · SDR: Edu (R\$ 300,00) · '
        'Gerência N1: Fábio (1%)');
    expect(saleFormsExportComissionados({}), '—');
  });

  test('auditoria detalhada omite mudança só de formato', () {
    final rows = saleFormsExportAuditRows([_ficha()]);
    expect(rows.length, 1);
    expect(rows.single[5], 'Valor');
    expect(_plain(rows.single[7]), 'R\$ 500.000,00');
    expect(rows.single[8], 'saleValue');
  });

  test('rastreabilidade sem resumo do back monta as linhas', () {
    final s = saleFormsExportTraceability({
      'status': 'canceled',
      'cancellationReason': 'Desistiu',
      'ativo': true,
      'createdAt': '2026-10-01T03:00:00Z',
      'updatedAt': '2026-10-01T03:00:00Z',
    });
    expect(s, startsWith('Ficha cancelada. · Motivo do cancelamento: Desistiu'));
    expect(s, contains('Criada em 01/10/2026 00:00.'));
  });

  test('planilha completa gera bytes e nome no padrão do web', () {
    final bytes = buildSaleFormsRelatorioXlsx([_ficha()]);
    expect(bytes.length, greaterThan(500));
    expect(bytes.sublist(0, 2), [0x50, 0x4B]);
    expect(buildSaleFormsRelatorioXlsx(const []).isNotEmpty, isTrue);
    expect(saleFormsRelatorioFileName(DateTime(2026, 10, 3, 9, 5)),
        'relatorio-fichas-2026-10-03-0905.xlsx');
  });

  test('trava de assinatura: intervalo mínimo entre consultas', () {
    final t0 = DateTime(2026, 10, 3, 10);
    expect(signatureLockPodeConsultar(null, t0), isTrue);
    expect(
      signatureLockPodeConsultar(t0, t0.add(const Duration(milliseconds: 500))),
      isFalse,
    );
    expect(
      signatureLockPodeConsultar(t0, t0.add(kSignatureLockIntervaloMinimo)),
      isTrue,
    );
  });
}
