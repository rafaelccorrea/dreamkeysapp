import 'dart:convert';

import 'package:Intellisys/features/properties/services/nearby_places_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('query Overpass igual à do web (amenity num statement só, com regex)',
      () {
    final q = buildOverpassQuery(-16.68, -49.25, 1800, kNearbyCategories);
    expect(q, startsWith('[out:json][timeout:15];'));
    expect(q, contains('nwr(around:1800,-16.68,-49.25)["shop"="supermarket"];'));
    expect(
      q,
      contains(
        'nwr(around:1800,-16.68,-49.25)'
        '["amenity"~"^(hospital|clinic|pharmacy|school)\$"];',
      ),
    );
    expect('nwr('.allMatches(q), hasLength(2));
    expect(q, endsWith('out center tags 200;'));
  });

  test('parse classifica, deduplica, limita por categoria e monta endereço',
      () {
    final body = {
      'elements': [
        {
          'type': 'node',
          'id': 1,
          'lat': -16.7,
          'lon': -49.2,
          'tags': {
            'amenity': 'pharmacy',
            'name': 'Drogaria',
            'addr:street': 'Rua 1',
            'addr:housenumber': '10',
            'addr:city': 'Goiânia',
          },
        },
        {
          'type': 'node',
          'id': 1,
          'lat': -16.7,
          'lon': -49.2,
          'tags': {'amenity': 'pharmacy'},
        },
        {
          'type': 'way',
          'id': 2,
          'center': {'lat': -16.71, 'lon': -49.21},
          'tags': {'shop': 'supermarket'},
        },
        {
          'type': 'node',
          'id': 3,
          'lat': -16.72,
          'lon': -49.22,
          'tags': {'amenity': 'clinic', 'name': 'Clínica'},
        },
        {
          'type': 'node',
          'id': 4,
          'lat': -16.73,
          'lon': -49.23,
          'tags': {'amenity': 'hospital', 'name': 'Hospital'},
        },
        {
          'type': 'node',
          'id': 5,
          'tags': {'amenity': 'school'},
        },
        {
          'type': 'node',
          'id': 6,
          'lat': 1,
          'lon': 1,
          'tags': {'amenity': 'bank'},
        },
      ],
    };
    final places =
        parseOverpassResponse(body, kNearbyCategories, maxPerCategory: 1);
    expect(places.map((p) => p.id), ['node/1', 'way/2', 'node/3']);
    expect(places[0].category, NearbyCategoryKey.pharmacy);
    expect(places[0].address, 'Rua 1, 10 · Goiânia');
    expect(places[1].name, 'Local sem nome');
    expect(places[1].lat, -16.71);
    expect(places[2].category, NearbyCategoryKey.health);
  });

  test('refaz a busca só ao andar ~300 m ou trocar a base', () {
    expect(
      shouldRefetchNearby(
        previous: null,
        next: (0, 0),
        anchoredOnSelection: false,
      ),
      isTrue,
    );
    expect(
      shouldRefetchNearby(
        previous: (-16.68, -49.25),
        next: (-16.681, -49.251),
        anchoredOnSelection: false,
      ),
      isFalse,
    );
    expect(
      shouldRefetchNearby(
        previous: (-16.68, -49.25),
        next: (-16.684, -49.25),
        anchoredOnSelection: false,
      ),
      isTrue,
    );
    expect(
      shouldRefetchNearby(
        previous: (-16.68, -49.25),
        next: (-16.68, -49.25),
        anchoredOnSelection: true,
      ),
      isTrue,
    );
  });

  group('fetch', () {
    final service = NearbyPlacesService.instance;
    tearDown(() => service.clientFactory = http.Client.new);

    test('cai para o segundo espelho e usa cache', () async {
      final hits = <String>[];
      service.clientFactory = () => MockClient((req) async {
            hits.add(req.url.host);
            if (req.url.host == 'overpass-api.de') {
              return http.Response('busy', 504);
            }
            expect(req.body, startsWith('data='));
            return http.Response(
              jsonEncode({
                'elements': [
                  {
                    'type': 'node',
                    'id': 9,
                    'lat': 1.0,
                    'lon': 2.0,
                    'tags': {'amenity': 'school', 'name': 'Escola'},
                  },
                ],
              }),
              200,
            );
          });
      final a = await service.fetch(lat: 10.12345, lng: 20.5);
      expect(a.single.name, 'Escola');
      expect(hits, ['overpass-api.de', 'overpass.kumi.systems']);
      final b = await service.fetch(lat: 10.12345, lng: 20.5);
      expect(b, same(a));
      expect(hits, hasLength(2));
    });

    test('todos os espelhos falham = indisponível (não lista vazia)', () {
      service.clientFactory =
          () => MockClient((_) async => http.Response('x', 500));
      expect(
        service.fetch(lat: 33.3, lng: 44.4),
        throwsA(isA<NearbyPlacesUnavailable>()),
      );
    });
  });
}
