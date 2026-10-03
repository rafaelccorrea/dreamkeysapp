import 'package:Intellisys/features/sale_forms/sale_form_media_sources.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Mídia de origem (paridade com midiasOrigemFichaVenda.ts)', () {
    test('lista oficial grava "DISPAROS MANYCHAT", não "DISPAROS"', () {
      expect(kSaleFormMediaSourcesOficiais, contains('DISPAROS MANYCHAT'));
      expect(kSaleFormMediaSourcesOficiais, isNot(contains('DISPAROS')));
      expect(kSaleFormMediaSourcesOficiais.length, 20);
    });

    test('lista completa = oficial + legado sem equivalentes', () {
      final c = kSaleFormMediaSourcesCompleta;
      // Oficiais primeiro, na mesma ordem.
      expect(c.take(20).toList(), kSaleFormMediaSourcesOficiais);
      // "Site"/"Google Ads"/"placa" equivalem a oficiais: não entram.
      expect(c, isNot(contains('Site')));
      expect(c, isNot(contains('Google Ads')));
      expect(c, isNot(contains('placa')));
      // "Instagram" entra; "instagram" é o mesmo e não duplica.
      expect(c, contains('Instagram'));
      expect(c, isNot(contains('instagram')));
      expect(c, contains('outro'));
      final chaves = c.map(saleFormMediaSourceKey).toList();
      expect(chaves.toSet().length, chaves.length);
    });

    test('chave ignora caixa e espaços repetidos', () {
      expect(saleFormMediaSourceKey('  google   ads '), 'GOOGLE ADS');
    });

    test('edição mantém o valor gravado, inclusive legado e "DISPAROS"', () {
      expect(saleFormStoredMediaSource('DISPAROS'), 'DISPAROS');
      expect(saleFormStoredMediaSource(' Facebook '), 'Facebook');
      expect(saleFormStoredMediaSource('DISPAROS MANYCHAT'),
          'DISPAROS MANYCHAT');
      expect(saleFormStoredMediaSource(''), isNull);
      expect(saleFormStoredMediaSource(null), isNull);
    });

    test('opções incluem o valor atual quando ele não está na lista', () {
      final antigo = saleFormMediaSourceOptions('DISPAROS');
      expect(antigo.last, 'DISPAROS');
      expect(antigo.length, kSaleFormMediaSourcesCompleta.length + 1);

      final legado = saleFormMediaSourceOptions('Facebook');
      expect(legado.length, kSaleFormMediaSourcesCompleta.length);

      final livre = saleFormMediaSourceOptions('Panfleto da feira');
      expect(livre, contains('Panfleto da feira'));

      expect(saleFormMediaSourceOptions(null), kSaleFormMediaSourcesCompleta);
    });

    test('rótulo em maiúsculas sem mudar o valor gravado', () {
      expect(saleFormMediaSourceLabel('Indicação'), 'INDICAÇÃO');
    });
  });
}
