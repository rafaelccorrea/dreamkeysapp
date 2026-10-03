import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Intellisys/shared/utils/input_formatters.dart';
import 'package:Intellisys/shared/utils/masks.dart';
import 'package:Intellisys/shared/utils/validators.dart';

TextEditingValue _fmt(TextInputFormatter f, String oldText, String newText) =>
    f.formatEditUpdate(
      TextEditingValue(text: oldText),
      TextEditingValue(text: newText),
    );

void main() {
  group('telefone com DDI 55 (transv-20)', () {
    test('brPhoneDigits tira o DDI de número completo', () {
      expect(Masks.brPhoneDigits('+55 (11) 98765-4321'), '11987654321');
      expect(Masks.brPhoneDigits('5511987654321'), '11987654321');
      expect(Masks.brPhoneDigits('551133334444'), '1133334444');
    });

    test('brPhoneDigits não mexe em número sem DDI (inclusive DDD 55)', () {
      expect(Masks.brPhoneDigits('(55) 99876-5432'), '55998765432');
      expect(Masks.brPhoneDigits('1133334444'), '1133334444');
      expect(Masks.brPhoneDigits(''), '');
    });

    test('Masks.phone e unmaskPhone usam o número sem DDI', () {
      expect(Masks.phone('5511987654321'), '(11) 98765-4321');
      expect(Masks.unmaskPhone('+55 11 98765-4321'), '11987654321');
    });

    test('formatter: colar número com +55 não corta o fim', () {
      final v = _fmt(PhoneInputFormatter(), '', '+55 11 98765-4321');
      expect(v.text, '(11) 98765-4321');
    });

    test('formatter: dígito a mais em número completo só trunca', () {
      final v = _fmt(PhoneInputFormatter(), '(55) 99876-5432', '(55) 99876-54321');
      expect(v.text, '(55) 99876-5432');
    });

    test('Validators.phone aceita número com DDI', () {
      expect(Validators.phone('+55 11 98765-4321'), isNull);
      expect(Validators.phone('11987654321'), isNull);
      expect(Validators.phone('119876'), isNotNull);
    });
  });

  group('CNPJ alfanumérico (transv-21)', () {
    // Exemplo oficial do SERPRO: base 12ABC34501DE → DV 35.
    const alnum = '12ABC34501DE35';
    const numeric = '11222333000181';

    test('valida CNPJ numérico e alfanumérico', () {
      expect(Validators.isValidCnpj(numeric), isTrue);
      expect(Validators.isValidCnpj('11.222.333/0001-81'), isTrue);
      expect(Validators.isValidCnpj(alnum), isTrue);
      expect(Validators.isValidCnpj('12.abc.345/01de-35'), isTrue);
    });

    test('recusa DV errado e DV com letra', () {
      expect(Validators.isValidCnpj('12ABC34501DE36'), isFalse);
      expect(Validators.isValidCnpj('11222333000182'), isFalse);
      expect(Validators.isValidCnpj('12ABC34501DEAB'), isFalse);
      expect(Validators.isValidCnpj('12ABC'), isFalse);
    });

    test('Validators.cnpj devolve mensagens', () {
      expect(Validators.cnpj('12.ABC.345/01DE-35'), isNull);
      expect(Validators.cnpj('11.222.333/0001-81'), isNull);
      expect(Validators.cnpj('11111111111111'), 'CNPJ inválido');
      expect(Validators.cnpj('12ABC'), 'CNPJ deve conter 14 caracteres');
      expect(Validators.cnpj(''), 'CNPJ é obrigatório');
    });

    test('máscara aceita letras, põe maiúsculas e mantém DV numérico', () {
      expect(Masks.cnpj('12abc34501de35'), '12.ABC.345/01DE-35');
      expect(Masks.cnpj(numeric), '11.222.333/0001-81');
      expect(Masks.cnpj('12ABC34501DEX3'), '12.ABC.345/01DE-3');
      expect(Masks.cnpj('12ABC34501DE3599'), '12.ABC.345/01DE-35');
      expect(Masks.unmaskCnpj('12.abc.345/01de-35'), alnum);
    });

    test('formatter de CNPJ não descarta letras', () {
      final v = _fmt(CnpjInputFormatter(), '', '12abc34501de35');
      expect(v.text, '12.ABC.345/01DE-35');
    });

    test('documento dinâmico CPF ↔ CNPJ', () {
      expect(Masks.isCpfDocument('123.456.789-09'), isTrue);
      expect(Masks.isCpfDocument('12A'), isFalse);
      expect(Masks.isCpfDocument('112223330001'), isFalse);
      expect(Masks.cpfOrCnpj('12345678909'), '123.456.789-09');
      expect(Masks.cpfOrCnpj('12abc34501de35'), '12.ABC.345/01DE-35');
    });
  });
}
