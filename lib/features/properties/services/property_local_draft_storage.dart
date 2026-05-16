import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/services/secure_storage_service.dart';
import '../models/property_local_draft.dart';

/// Storage de rascunhos de cadastro de imóvel.
///
/// **Híbrido por design:**
///
/// - **Rascunhos nomeados** (lista visível ao usuário) → REST `/property-drafts`,
///   privado por usuário, sincronizado entre web e mobile. Apenas os campos
///   do formulário (`formJson` + `wizardStep`) são enviados — espelha a decisão
///   de produto: imagens não são sincronizadas.
///
/// - **Rascunho anônimo** (auto-save em background do form em andamento) →
///   `SharedPreferences` local. Não vai para o servidor (paridade com
///   `imobx_createProperty_draft` do web), permanece no aparelho.
///
/// - **Imagens** → arquivos locais em `applicationSupport/property_local_drafts/<draftId>/`,
///   indexadas por `draftId` em `SharedPreferences`. Quando um rascunho é
///   aberto em outro dispositivo (sincronizado pelo backend), o usuário verá
///   o restante do formulário, mas reanexará imagens neste aparelho.
class PropertyLocalDraftStorage {
  PropertyLocalDraftStorage._();

  static final PropertyLocalDraftStorage instance =
      PropertyLocalDraftStorage._();

  /// Auto-save anônimo (não nomeado) — local-only, paridade com o web.
  static const _prefsAnonymousNamespace = 'property_anonymous_draft_v1';

  /// Índice de imagens locais por rascunho remoto: `Map<draftId, List<path>>`.
  static const _prefsImageIndexNamespace = 'property_drafts_local_images_v1';

  final ApiService _api = ApiService.instance;

  Future<String> _anonymousScopeKey() async {
    final companyId =
        (await SecureStorageService.instance.getCompanyId()) ?? '_no_company';
    return '${_prefsAnonymousNamespace}_$companyId';
  }

  Future<String> _imageIndexKey() async {
    final companyId =
        (await SecureStorageService.instance.getCompanyId()) ?? '_no_company';
    return '${_prefsImageIndexNamespace}_$companyId';
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

  // ─── Índice local de imagens ────────────────────────────────────────────

  Future<Map<String, List<String>>> _readImageIndex() async {
    try {
      final key = await _imageIndexKey();
      final raw = (await _prefs).getString(key);
      if (raw == null || raw.trim().isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, List<String>>{};
      decoded.forEach((k, v) {
        if (k is String && v is List) {
          out[k] = v.map((e) => e.toString()).toList();
        }
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeImageIndex(Map<String, List<String>> index) async {
    try {
      final key = await _imageIndexKey();
      await (await _prefs).setString(key, jsonEncode(index));
    } catch (_) {
      // best-effort
    }
  }

  Future<List<String>> getLocalImagePaths(String draftId) async {
    final idx = await _readImageIndex();
    final list = idx[draftId] ?? const <String>[];
    return list.where((p) => File(p).existsSync()).toList();
  }

  Future<void> setLocalImagePaths(
    String draftId,
    List<String> paths,
  ) async {
    final idx = await _readImageIndex();
    if (paths.isEmpty) {
      idx.remove(draftId);
    } else {
      idx[draftId] = paths;
    }
    await _writeImageIndex(idx);
  }

  // ─── API remota → modelo local ─────────────────────────────────────────

  PropertyLocalDraft _fromApi(
    Map<String, dynamic> raw,
    Map<String, List<String>> imageIndex,
  ) {
    final id = raw['id']?.toString() ?? '';
    final name = raw['name']?.toString() ?? 'Sem título';
    final companyId = raw['companyId']?.toString() ?? '';
    final updatedAt =
        DateTime.tryParse(raw['updatedAt']?.toString() ?? '') ??
            DateTime.tryParse(raw['createdAt']?.toString() ?? '') ??
            DateTime.now();

    final payload = (raw['payload'] is Map)
        ? Map<String, dynamic>.from(raw['payload'] as Map)
        : <String, dynamic>{};
    final wizardStep = (payload['wizardStep'] is int)
        ? payload['wizardStep'] as int
        : int.tryParse('${payload['wizardStep']}') ?? 0;
    final formJson = (payload['formJson'] is Map)
        ? Map<String, dynamic>.from(payload['formJson'] as Map)
        : <String, dynamic>{};

    return PropertyLocalDraft(
      id: id,
      displayTitle: name,
      companyId: companyId,
      updatedAt: updatedAt,
      wizardStep: wizardStep,
      formJson: formJson,
      imagePaths: imageIndex[id] ?? const <String>[],
    );
  }

  Map<String, dynamic> _toApiPayload(PropertyLocalDraft draft) {
    return {
      'name': draft.displayTitle.trim().isEmpty
          ? 'Sem título'
          : draft.displayTitle.trim(),
      'payload': {
        'wizardStep': draft.wizardStep,
        'formJson': draft.formJson,
      },
    };
  }

  // ─── Lista / leitura ────────────────────────────────────────────────────

  Future<List<PropertyLocalDraft>> loadAllForCurrentCompany() async {
    try {
      final res = await _api.get<List<dynamic>>(ApiConstants.propertyDrafts);
      if (!res.success || res.data == null) return [];
      final imageIndex = await _readImageIndex();
      final list = res.data!
          .whereType<Map>()
          .map((e) => _fromApi(e.cast<String, dynamic>(), imageIndex))
          .where((d) => d.id.isNotEmpty)
          .toList();
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return list;
    } catch (e) {
      debugPrint('❌ [PROPERTY_DRAFTS] loadAll: $e');
      return [];
    }
  }

  Future<PropertyLocalDraft?> getById(String id) async {
    if (id.isEmpty) return null;
    try {
      final res = await _api.get<Map<String, dynamic>>(
        ApiConstants.propertyDraftById(id),
      );
      if (!res.success || res.data == null) return null;
      final imageIndex = await _readImageIndex();
      return _fromApi(res.data!, imageIndex);
    } catch (e) {
      debugPrint('❌ [PROPERTY_DRAFTS] getById: $e');
      return null;
    }
  }

  // ─── Save (POST/PUT) ───────────────────────────────────────────────────

  /// Upsert remoto.
  ///
  /// Se `draft.id` for vazio ou começar com `ld_` (id temporário gerado
  /// localmente), faz `POST /property-drafts` e retorna o draft com o
  /// id gerado pelo servidor. Caso contrário, faz `PUT /property-drafts/:id`.
  ///
  /// `imagePaths` do `draft` é ignorado (imagens não viajam pela API).
  /// Use [setLocalImagePaths] após o upsert para persistir o índice local
  /// das imagens copiadas.
  Future<PropertyLocalDraft> save(PropertyLocalDraft draft) async {
    final body = _toApiPayload(draft);
    final isLocalId = draft.id.isEmpty || draft.id.startsWith('ld_');

    if (!isLocalId) {
      final res = await _api.put<Map<String, dynamic>>(
        ApiConstants.propertyDraftById(draft.id),
        body: body,
      );
      if (res.success && res.data != null) {
        final imageIndex = await _readImageIndex();
        return _fromApi(res.data!, imageIndex);
      }
      // Fallback: rascunho não existe mais no backend → cria novo.
      if (res.statusCode == 404) {
        return _createNewRemote(body, draft.imagePaths);
      }
      throw StateError(res.message ?? 'Erro ao salvar rascunho');
    }

    return _createNewRemote(body, draft.imagePaths);
  }

  Future<PropertyLocalDraft> _createNewRemote(
    Map<String, dynamic> body,
    List<String> imagePaths,
  ) async {
    final res = await _api.post<Map<String, dynamic>>(
      ApiConstants.propertyDrafts,
      body: body,
    );
    if (!res.success || res.data == null) {
      throw StateError(res.message ?? 'Erro ao criar rascunho');
    }
    final imageIndex = await _readImageIndex();
    final created = _fromApi(res.data!, imageIndex);
    if (imagePaths.isNotEmpty) {
      await setLocalImagePaths(created.id, imagePaths);
      return PropertyLocalDraft(
        id: created.id,
        displayTitle: created.displayTitle,
        companyId: created.companyId,
        updatedAt: created.updatedAt,
        wizardStep: created.wizardStep,
        formJson: created.formJson,
        imagePaths: imagePaths,
      );
    }
    return created;
  }

  // ─── Delete ────────────────────────────────────────────────────────────

  Future<void> delete(String draftId) async {
    if (draftId.isEmpty) return;
    try {
      await _api.delete<void>(ApiConstants.propertyDraftById(draftId));
    } catch (e) {
      debugPrint('❌ [PROPERTY_DRAFTS] delete remote: $e');
    }
    await setLocalImagePaths(draftId, const []);
    try {
      final root = await draftsRootDirectory();
      final dir = draftDirectorySync(draftId, root);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // Best-effort: pasta órfã não impede remoção do índice.
    }
  }

  // ─── Anonymous auto-save (local) ───────────────────────────────────────

  /// Lê o rascunho anônimo (auto-save) da empresa atual.
  ///
  /// Continua **local-only** — paridade com `imobx_createProperty_draft` do
  /// web. Não sincroniza para evitar tráfego a cada digitação.
  Future<Map<String, dynamic>?> getAnonymous() async {
    try {
      final key = await _anonymousScopeKey();
      final raw = (await _prefs).getString(key);
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveAnonymous(Map<String, dynamic> data) async {
    try {
      final key = await _anonymousScopeKey();
      await (await _prefs).setString(key, jsonEncode(data));
    } catch (_) {
      // Best-effort: não interrompe o fluxo de criação.
    }
  }

  Future<void> clearAnonymous() async {
    try {
      final key = await _anonymousScopeKey();
      await (await _prefs).remove(key);
    } catch (_) {
      // ignore
    }
  }

  // ─── Imagens ───────────────────────────────────────────────────────────

  /// Copia arquivos de imagem para a pasta do rascunho; retorna paths
  /// absolutos. O caller é responsável por chamar [setLocalImagePaths]
  /// para persistir esses paths no índice local — `save()` por si só
  /// não toca em imagens.
  Future<List<String>> copyImagesToDraftFolder({
    required String draftId,
    required List<File> sources,
  }) async {
    if (draftId.isEmpty) return const [];
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
