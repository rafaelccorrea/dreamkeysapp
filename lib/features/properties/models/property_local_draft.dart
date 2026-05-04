import 'dart:convert';

/// Rascunho local de cadastro de imóvel (não sincronizado com o servidor).
class PropertyLocalDraft {
  PropertyLocalDraft({
    required this.id,
    required this.displayTitle,
    required this.companyId,
    required this.updatedAt,
    required this.wizardStep,
    required this.formJson,
    required this.imagePaths,
  });

  final String id;
  final String displayTitle;
  final String companyId;
  final DateTime updatedAt;

  /// Última etapa onde o usuário salvou (`0 … totalSteps-1`).
  final int wizardStep;

  /// Estado serializado do formulário (`_freezeFormState` no wizard).
  final Map<String, dynamic> formJson;

  /// Paths absolutos das cópias de imagens no sandbox do app.
  final List<String> imagePaths;

  int get photoCount => imagePaths.length;

  Map<String, dynamic> toPersistenceMap() => {
        'id': id,
        'displayTitle': displayTitle,
        'companyId': companyId,
        'updatedAt': updatedAt.toIso8601String(),
        'wizardStep': wizardStep,
        'formJson': formJson,
        'imagePaths': imagePaths,
      };

  factory PropertyLocalDraft.fromPersistenceMap(Map<String, dynamic> m) {
    return PropertyLocalDraft(
      id: m['id']?.toString() ?? '',
      displayTitle: m['displayTitle']?.toString() ?? 'Sem título',
      companyId: m['companyId']?.toString() ?? '',
      updatedAt: DateTime.tryParse(m['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      wizardStep: (m['wizardStep'] is int)
          ? m['wizardStep'] as int
          : int.tryParse('${m['wizardStep']}') ?? 0,
      formJson: Map<String, dynamic>.from(
        (m['formJson'] is Map)
            ? (m['formJson'] as Map).cast<String, dynamic>()
            : {},
      ),
      imagePaths: (m['imagePaths'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .where((s) => s.isNotEmpty)
          .toList(),
    );
  }

  static String encodeList(List<PropertyLocalDraft> list) =>
      jsonEncode(list.map((e) => e.toPersistenceMap()).toList());

  static List<PropertyLocalDraft> decodeList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => PropertyLocalDraft.fromPersistenceMap(e.cast<String, dynamic>()))
          .where((e) => e.id.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }
}
