import 'package:flutter_test/flutter_test.dart';
import 'package:Intellisys/features/properties/utils/gallery_media_rules.dart';
import 'package:Intellisys/shared/services/property_service.dart';

PropertyImage _img(String id, {String type = 'image', String url = 'u'}) =>
    PropertyImage(
      id: id,
      url: url,
      category: 'general',
      isMain: false,
      createdAt: '',
      mediaType: type,
    );

void main() {
  group('galleryReorderPayload', () {
    test('manda só as fotos, na ordem, sem vídeo/ids vazios/repetidos', () {
      final payload = galleryReorderPayload([
        _img('a'),
        _img('v', type: 'video'),
        _img('b'),
        _img(''),
        _img('a'),
        _img('c'),
      ]);
      expect(payload, {
        'imageIds': ['a', 'b', 'c'],
      });
    });
  });

  group('moveGalleryItem', () {
    test('setas trocam com o vizinho', () {
      expect(moveGalleryItem(['a', 'b', 'c'], 1, 0), ['b', 'a', 'c']);
      expect(moveGalleryItem(['a', 'b', 'c'], 1, 2), ['a', 'c', 'b']);
    });

    test('arrasto para o fim e para o início', () {
      expect(moveGalleryItem(['a', 'b', 'c', 'd'], 0, 3), ['b', 'c', 'd', 'a']);
      expect(moveGalleryItem(['a', 'b', 'c', 'd'], 3, 0), ['d', 'a', 'b', 'c']);
    });

    test('fora da faixa ou mesmo índice não muda (e devolve cópia)', () {
      final src = ['a', 'b'];
      final out = moveGalleryItem(src, 0, 5);
      expect(out, src);
      expect(identical(out, src), isFalse);
      expect(moveGalleryItem(src, 1, 1), src);
      expect(moveGalleryItem(src, -1, 0), src);
    });
  });

  group('validateGalleryVideo', () {
    test('aceita MP4/MOV/WebM dentro dos limites', () {
      expect(
        validateGalleryVideo(
          fileName: 'tour.MP4',
          sizeBytes: 10 * 1024 * 1024,
          durationSeconds: 99,
        ),
        isNull,
      );
      expect(
        validateGalleryVideo(fileName: 'a.mov', sizeBytes: 1),
        isNull,
      );
      expect(
        validateGalleryVideo(fileName: 'a.webm', sizeBytes: 1),
        isNull,
      );
    });

    test('recusa formato fora da lista', () {
      expect(
        validateGalleryVideo(fileName: 'clip.avi', sizeBytes: 1),
        contains('MP4, MOV ou WebM'),
      );
      expect(
        validateGalleryVideo(fileName: 'semextensao', sizeBytes: 1),
        isNotNull,
      );
    });

    test('recusa acima de 150 MB', () {
      expect(
        validateGalleryVideo(
          fileName: 'a.mp4',
          sizeBytes: kGalleryMaxVideoBytes + 1,
        ),
        'Vídeo muito grande (máximo 150MB)',
      );
      expect(
        validateGalleryVideo(fileName: 'a.mp4', sizeBytes: kGalleryMaxVideoBytes),
        isNull,
      );
    });

    test('requireDuration: sem duração medida bloqueia (mensagem do web)', () {
      for (final d in <double?>[null, 0, -1, double.nan]) {
        expect(
          validateGalleryVideo(
            fileName: 'a.mp4',
            sizeBytes: 1,
            durationSeconds: d,
            requireDuration: true,
          ),
          kGalleryVideoUnreadableMessage,
        );
      }
      expect(
        validateGalleryVideo(
          fileName: 'a.mp4',
          sizeBytes: 1,
          durationSeconds: 42,
          requireDuration: true,
        ),
        isNull,
      );
      // Formato/tamanho vêm antes da duração.
      expect(
        validateGalleryVideo(
          fileName: 'a.avi',
          sizeBytes: 1,
          requireDuration: true,
        ),
        contains('MP4, MOV ou WebM'),
      );
    });

    test('duração: 100,5 s passa (folga do web); acima recusa', () {
      expect(
        validateGalleryVideo(
          fileName: 'a.mp4',
          sizeBytes: 1,
          durationSeconds: 100.5,
        ),
        isNull,
      );
      expect(
        validateGalleryVideo(
          fileName: 'a.mp4',
          sizeBytes: 1,
          durationSeconds: 125,
        ),
        'Vídeo muito longo (2:05). Máximo de 1:40 (100s).',
      );
    });
  });

  group('galleryVideoMimeType', () {
    test('mapeia as extensões aceitas', () {
      expect(galleryVideoMimeType('x.mp4'), 'video/mp4');
      expect(galleryVideoMimeType('IMG_1.MOV'), 'video/quicktime');
      expect(galleryVideoMimeType('x.webm'), 'video/webm');
      expect(galleryVideoMimeType('x.mkv'), isNull);
    });
  });

  test('formatGalleryVideoDuration', () {
    expect(formatGalleryVideoDuration(100), '1:40');
    expect(formatGalleryVideoDuration(5), '0:05');
    expect(formatGalleryVideoDuration(0), '0:00');
  });

  test('galleryPhotosOf / galleryVideoOf separam foto e vídeo', () {
    final media = [
      _img('a'),
      _img('v', type: 'video'),
      _img('b', url: ' '),
      _img('c'),
    ];
    expect(galleryPhotosOf(media).map((e) => e.id), ['a', 'c']);
    expect(galleryVideoOf(media)?.id, 'v');
    expect(galleryVideoOf([_img('a')]), isNull);
  });
}
