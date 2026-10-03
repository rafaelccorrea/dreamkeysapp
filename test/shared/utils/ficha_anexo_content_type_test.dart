import 'package:Intellisys/shared/utils/ficha_anexo_content_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('contentType do anexo da ficha (venda e proposta)', () {
    test('tipos aceitos pelo back saem com o mimetype certo', () {
      expect(fichaAnexoContentType('ficha.pdf')?.mimeType, 'application/pdf');
      expect(fichaAnexoContentType('foto.jpg')?.mimeType, 'image/jpeg');
      expect(fichaAnexoContentType('foto.jpeg')?.mimeType, 'image/jpeg');
      expect(fichaAnexoContentType('scan.png')?.mimeType, 'image/png');
      expect(fichaAnexoContentType('scan.webp')?.mimeType, 'image/webp');
    });

    test('extensão em maiúsculas e caminho completo', () {
      expect(
        fichaAnexoContentType('/data/user/0/cache/FICHA ASSINADA.PDF')
            ?.mimeType,
        'application/pdf',
      );
      expect(
        fichaAnexoContentType(r'C:\tmp\IMG_0001.JPG')?.mimeType,
        'image/jpeg',
      );
    });

    test('fora da lista ou sem extensão: null (o cliente já barra antes)', () {
      expect(fichaAnexoContentType('planilha.xlsx'), isNull);
      expect(fichaAnexoContentType('foto.heic'), isNull);
      expect(fichaAnexoContentType('sem_extensao'), isNull);
      expect(fichaAnexoContentType('pasta.pdf/arquivo'), isNull);
    });
  });
}
