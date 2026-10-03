/// Rascunho local das fichas ("Retomar rascunho") — espelha
/// `utils/fichaRascunho.ts` + `useFormDraft` do web: só na criação, salvo
/// sozinho enquanto o usuário preenche, por usuário e empresa, e apagado
/// quando a ficha é criada.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/services/module_access_service.dart';

/// Versão do formato gravado. Mudou o formato → rascunho antigo é descartado
/// (como `RASCUNHO_FICHA_VERSAO` do web).
const int kFichaDraftVersao = 1;

/// Rascunho lido: os campos e quando foi salvo.
class FichaDraft {
  const FichaDraft({required this.data, required this.savedAt});
  final Map<String, dynamic> data;
  final DateTime savedAt;
}

/// Chave por tipo, usuário e empresa (`chaveRascunhoFicha`).
String fichaDraftKey(String tipo, {String? userId, String? companyId}) {
  final base = 'ficha_rascunho_$tipo';
  final u = (userId ?? '').trim();
  final c = (companyId ?? '').trim();
  if (u.isEmpty) return base;
  return c.isEmpty ? '${base}_$u' : '${base}_${u}_$c';
}

/// JSON gravado: `{v, savedAt, data}`.
String encodeFichaDraft(Map<String, dynamic> data, DateTime savedAt) =>
    jsonEncode({
      'v': kFichaDraftVersao,
      'savedAt': savedAt.toUtc().toIso8601String(),
      'data': data,
    });

/// `null` quando vazio, ilegível ou de outra versão.
FichaDraft? decodeFichaDraft(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final m = jsonDecode(raw);
    if (m is! Map || m['v'] != kFichaDraftVersao || m['data'] is! Map) {
      return null;
    }
    final at = DateTime.tryParse((m['savedAt'] ?? '').toString());
    return FichaDraft(
      data: Map<String, dynamic>.from(m['data'] as Map),
      savedAt: (at ?? DateTime.now()).toLocal(),
    );
  } catch (_) {
    return null;
  }
}

/// Rascunho "em branco" (nada que valha guardar): toda folha é `null`,
/// texto vazio, `false` ou coleção vazia. Só olha [campos] — tipo, equipe e
/// passo atual não contam (`isBlankSaleFormDraft`).
bool fichaDraftIsBlank(Object? campos) {
  if (campos == null || campos == false) return true;
  if (campos is String) return campos.trim().isEmpty;
  if (campos is num) return false;
  if (campos is bool) return !campos;
  if (campos is Map) return campos.values.every(fichaDraftIsBlank);
  if (campos is Iterable) return campos.every(fichaDraftIsBlank);
  return false;
}

/// Leitura e gravação no aparelho (`shared_preferences`).
class FichaDraftStore {
  FichaDraftStore._();
  static final FichaDraftStore instance = FichaDraftStore._();

  String _key(String tipo) {
    final m = ModuleAccessService.instance;
    return fichaDraftKey(tipo,
        userId: m.userId, companyId: m.selectedCompany?.id);
  }

  Future<FichaDraft?> ler(String tipo) async {
    try {
      final p = await SharedPreferences.getInstance();
      final key = _key(tipo);
      final d = decodeFichaDraft(p.getString(key));
      if (d == null && p.containsKey(key)) await p.remove(key);
      return d;
    } catch (e) {
      debugPrint('[FICHA_RASCUNHO] ler: $e');
      return null;
    }
  }

  Future<void> salvar(String tipo, Map<String, dynamic> data) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key(tipo), encodeFichaDraft(data, DateTime.now()));
    } catch (e) {
      debugPrint('[FICHA_RASCUNHO] salvar: $e');
    }
  }

  Future<void> limpar(String tipo) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_key(tipo));
    } catch (e) {
      debugPrint('[FICHA_RASCUNHO] limpar: $e');
    }
  }
}
