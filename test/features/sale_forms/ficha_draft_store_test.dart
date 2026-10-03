import 'package:Intellisys/features/sale_forms/ficha_draft_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chave por tipo, usuário e empresa (chaveRascunhoFicha)', () {
    expect(fichaDraftKey('venda'), 'ficha_rascunho_venda');
    expect(fichaDraftKey('venda', userId: 'u1'), 'ficha_rascunho_venda_u1');
    expect(fichaDraftKey('venda', userId: 'u1', companyId: 'c9'),
        'ficha_rascunho_venda_u1_c9');
    expect(fichaDraftKey('proposta', companyId: 'c9'),
        'ficha_rascunho_proposta');
  });

  test('ida e volta do JSON gravado', () {
    final at = DateTime.utc(2026, 10, 3, 12);
    final raw = encodeFichaDraft({
      'type': 'terceiros',
      'campos': {'saleValue': '1.000,00'},
    }, at);
    final d = decodeFichaDraft(raw)!;
    expect(d.data['type'], 'terceiros');
    expect((d.data['campos'] as Map)['saleValue'], '1.000,00');
    expect(d.savedAt.toUtc(), at);
  });

  test('ilegível, vazio ou de outra versão é descartado', () {
    expect(decodeFichaDraft(null), isNull);
    expect(decodeFichaDraft(''), isNull);
    expect(decodeFichaDraft('{quebrado'), isNull);
    expect(decodeFichaDraft('{"v":99,"data":{}}'), isNull);
    expect(decodeFichaDraft('{"v":$kFichaDraftVersao}'), isNull);
  });

  test('em branco: só vazio, null, false e coleções vazias', () {
    expect(fichaDraftIsBlank(null), isTrue);
    expect(
      fichaDraftIsBlank({
        'saleValue': '  ',
        'hasBuyerSpouse': false,
        'debtConfession': null,
        'participants': [],
        'buyer': {'name': '', 'birth': {'v': null, 'na': false}},
      }),
      isTrue,
    );
    expect(fichaDraftIsBlank({'buyer': {'name': 'Ana'}}), isFalse);
    expect(fichaDraftIsBlank({'parcelado': true}), isFalse);
    expect(fichaDraftIsBlank({'participants': [{}]}), isTrue);
    expect(
      fichaDraftIsBlank({
        'participants': [
          {'userId': 'u1'},
        ],
      }),
      isFalse,
    );
    expect(fichaDraftIsBlank({'debtConfession': false}), isTrue);
  });
}
