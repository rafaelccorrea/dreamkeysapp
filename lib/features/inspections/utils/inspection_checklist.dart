import 'package:flutter/material.dart';

/// Checklist da vistoria — mesmas traduções e cores do detalhe da web
/// (`VistoriaDetailPage.tsx`: translateChecklistKey/translateChecklistValue
/// e o `ChecklistValue`). vistorias-02, 03/10/2026.
class InspectionChecklist {
  InspectionChecklist._();

  static const Map<String, String> _chaves = {
    'walls': 'Paredes',
    'paredes': 'Paredes',
    'doors': 'Portas',
    'portas': 'Portas',
    'windows': 'Janelas',
    'janelas': 'Janelas',
    'floor': 'Piso',
    'piso': 'Piso',
    'ceiling': 'Teto',
    'teto': 'Teto',
    'plumbing': 'Encanamento',
    'encanamento': 'Encanamento',
    'electrical': 'Elétrica',
    'eletrica': 'Elétrica',
    'painting': 'Pintura',
    'pintura': 'Pintura',
    'kitchen': 'Cozinha',
    'cozinha': 'Cozinha',
    'bathroom': 'Banheiro',
    'banheiro': 'Banheiro',
    'bedroom': 'Quarto',
    'quarto': 'Quarto',
    'living_room': 'Sala',
    'sala': 'Sala',
    'garage': 'Garagem',
    'garagem': 'Garagem',
    'yard': 'Quintal',
    'quintal': 'Quintal',
    'external_area': 'Área Externa',
    'area_externa': 'Área Externa',
  };

  static const Map<String, String> _valores = {
    'excellent': 'Excelente',
    'excelente': 'Excelente',
    'good': 'Bom',
    'bom': 'Bom',
    'regular': 'Regular',
    'needs_maintenance': 'Precisa Manutenção',
    'precisa_manutencao': 'Precisa Manutenção',
    'needs repair': 'Precisa Manutenção',
    'precisa reparo': 'Precisa Manutenção',
    'poor': 'Ruim',
    'ruim': 'Ruim',
    'ok': 'OK',
    'yes': 'Sim',
    'sim': 'Sim',
    'no': 'Não',
    'nao': 'Não',
    'não': 'Não',
  };

  /// Chave conhecida traduzida; senão "minha_chave" → "Minha Chave".
  static String chave(String key) {
    final t = _chaves[key.toLowerCase()];
    if (t != null) return t;
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  static String valor(Object? value) {
    final s = value?.toString() ?? '';
    return _valores[s.toLowerCase()] ?? s;
  }

  /// Cor do valor (null = cor de texto normal), igual à web.
  static Color? cor(Object? value) {
    final v = (value?.toString() ?? '').toLowerCase();
    if (v == 'excelente' || v == 'excellent') return const Color(0xFF10B981);
    if (v == 'bom' || v == 'good') return const Color(0xFF3B82F6);
    if (v == 'regular') return const Color(0xFFF59E0B);
    const manutencao = {
      'precisa_manutencao',
      'precisa manutenção',
      'needs_maintenance',
      'needs maintenance',
      'precisa reparo',
      'needs repair',
    };
    if (manutencao.contains(v)) return const Color(0xFFEF4444);
    if (v == 'ruim' || v == 'poor') return const Color(0xFFDC2626);
    return null;
  }
}
