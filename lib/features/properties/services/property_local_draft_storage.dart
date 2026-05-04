import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/services/secure_storage_service.dart';
import '../models/property_local_draft.dart';

/// Persistência de rascunhos locais (JSON + pasta de imagens por rascunho).
class PropertyLocalDraftStorage {
  PropertyLocalDraftStorage._();

  static final PropertyLocalDraftStorage instance =
      PropertyLocalDraftStorage._();

  static const _prefsNamespace = 'property_local_drafts_v1';

  Future<String> _scopeKey() async {
    final companyId =
        (await SecureStorageService.instance.getCompanyId()) ?? '_no_company';
    return '${_prefsNamespace}_$companyId';
  }

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<Directory> draftsRootDirectory() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'property_local_drafts'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Directory draftDirectorySync(String draftId, Directory root) =>
      Directory(p.join(root.path, draftId));

  Future<List<PropertyLocalDraft>> loadAllForCurrentCompany() async {
    final key = await _scopeKey();
    final raw = (await _prefs).getString(key);
    final list = PropertyLocalDraft.decodeList(raw);
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  Future<PropertyLocalDraft?> getById(String id) async {
    final all = await loadAllForCurrentCompany();
    try {
      return all.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(PropertyLocalDraft draft) async {
    final key = await _scopeKey();
    final prefs = await _prefs;
    final all = PropertyLocalDraft.decodeList(prefs.getString(key))
      ..removeWhere((e) => e.id == draft.id);
    all.add(draft);
    all.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await prefs.setString(key, PropertyLocalDraft.encodeList(all));
  }

  Future<void> delete(String draftId) async {
    final key = await _scopeKey();
    final prefs = await _prefs;
    final all =
        PropertyLocalDraft.decodeList(prefs.getString(key))
          ..removeWhere((e) => e.id == draftId);
    await prefs.setString(key, PropertyLocalDraft.encodeList(all));

    try {
      final root = await draftsRootDirectory();
      final dir = draftDirectorySync(draftId, root);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      // Best-effort: pasta órfã não impede remoção do índice
      // ignore
    }
  }

  /// Copia arquivos de imagem para a pasta do rascunho; retorna paths absolutos.
  Future<List<String>> copyImagesToDraftFolder({
    required String draftId,
    required List<File> sources,
  }) async {
    final root = await draftsRootDirectory();
    final dir = draftDirectorySync(draftId, root);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);

    final out = <String>[];
    var i = 0;
    for (final f in sources) {
      try {
        if (!await f.exists()) continue;
        final ext = p.extension(f.path).replaceFirst('.', '').toLowerCase();
        final safeExt =
            ['jpg', 'jpeg', 'png', 'webp'].contains(ext) ? ext : 'jpg';
        final dest =
            File(p.join(dir.path, 'img_${i.toString().padLeft(4, '0')}.$safeExt'));
        await f.copy(dest.path);
        out.add(dest.path);
        i++;
      } catch (_) {
        continue;
      }
    }
    return out;
  }
}
