import 'package:Intellisys/features/public_site/models/public_site_config_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// integ-F1 (03/10/2026): com `homeBlocks` vazio no back, salvar/reordenar
/// uma seção no app gravava os presets do app — sem `lead_form` — e o site
/// público perdia o formulário de captação.
void main() {
  const templates = [
    'modern',
    'classic',
    'corporate',
    'luxury',
    'compact',
    'premium',
  ];

  group('PublicSiteBlockCatalog.defaultsFor', () {
    test('todo template inclui o formulário de captação antes do CTA', () {
      for (final t in templates) {
        final types = PublicSiteBlockCatalog.defaultsFor(t)
            .map((b) => b.type)
            .toList();
        expect(types, contains('lead_form'), reason: t);
        expect(types.last, 'cta', reason: t);
        expect(types[types.length - 2], 'lead_form', reason: t);
      }
    });

    test('presets iguais aos do back/web (public-site-blocks.types.ts)', () {
      expect(
        PublicSiteBlockCatalog.defaultsFor('modern').map((b) => b.type),
        [
          'hero', 'categories', 'featured_cards', 'property_grid',
          'process', 'testimonials', 'about', 'lead_form', 'cta',
        ],
      );
      expect(
        PublicSiteBlockCatalog.defaultsFor('premium').map((b) => b.type),
        [
          'hero', 'ribbon', 'featured_carousel', 'featured_cards',
          'property_grid', 'about', 'testimonials', 'trust', 'lead_form',
          'cta',
        ],
      );
      expect(
        PublicSiteBlockCatalog.defaultsFor('compact').map((b) => b.type),
        ['hero', 'property_grid', 'lead_form', 'cta'],
      );
    });

    test('ids no formato `tipo-posição` (mesmo do back)', () {
      final blocks = PublicSiteBlockCatalog.defaultsFor('compact');
      expect(blocks.map((b) => b.id), [
        'hero-1',
        'property_grid-2',
        'lead_form-3',
        'cta-4',
      ]);
      expect(blocks.every((b) => b.enabled), isTrue);
    });

    test('template desconhecido cai no modern', () {
      expect(
        PublicSiteBlockCatalog.defaultsFor('xyz').map((b) => b.type),
        PublicSiteBlockCatalog.defaultsFor('modern').map((b) => b.type),
      );
    });

    test('catálogo tem rótulo para lead_form e ribbon', () {
      expect(PublicSiteBlockCatalog.labelOf('lead_form'),
          'Formulário de captação');
      expect(PublicSiteBlockCatalog.labelOf('ribbon'), 'Fita de assinatura');
    });
  });

  group('PublicSiteConfig.editorHomeBlocks', () {
    test('sem seções salvas, o payload de salvar preserva o formulário', () {
      final cfg = PublicSiteConfig.fromJson({
        'id': 'c1',
        'companyId': 'co1',
        'templateId': 'luxury',
        'homeBlocks': <dynamic>[],
        'isPublished': true,
      });

      // Simula o _saveBlocks: reordena (move o CTA para o topo) e salva.
      final draft = List.of(cfg.editorHomeBlocks);
      final cta = draft.removeLast();
      draft.insert(0, cta);
      final payload = [for (final b in draft) b.toJson()];

      expect(payload.map((e) => e['type']), contains('lead_form'));
      final leadForm = payload.firstWhere((e) => e['type'] == 'lead_form');
      expect(leadForm['enabled'], isTrue);
    });

    test('com seções salvas, usa as do back sem misturar defaults', () {
      final cfg = PublicSiteConfig.fromJson({
        'id': 'c1',
        'companyId': 'co1',
        'templateId': 'modern',
        'homeBlocks': [
          {'id': 'hero-1', 'type': 'hero', 'enabled': true},
          {
            'id': 'lead_form-2',
            'type': 'lead_form',
            'enabled': false,
            'settings': {'title': 'Fale conosco'},
          },
        ],
        'isPublished': true,
      });

      final blocks = cfg.editorHomeBlocks;
      expect(blocks.map((b) => b.type), ['hero', 'lead_form']);
      expect(blocks[1].enabled, isFalse);
      expect(blocks[1].toJson()['settings'], {'title': 'Fale conosco'});
    });
  });
}
