import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/constants/api_constants.dart';

/// Metadados da versão mais recente publicada (App Store / backend).
class MobileLatestVersion {
  final String version;
  final int build;
  final String updateUrl;

  /// O que mudou, quando a fonte informa. Vazio = a tela não promete nada.
  final List<String> notes;

  const MobileLatestVersion({
    required this.version,
    required this.build,
    required this.updateUrl,
    this.notes = const [],
  });
}

/// A loja de onde a atualização vem. O texto e o ícone da tela mudam com
/// isto — dizer "App Store" para quem está no Android é mentira visível.
enum AppStoreKind {
  appStore('App Store'),
  playStore('Play Store');

  const AppStoreKind(this.label);
  final String label;
}

/// Resultado da checagem de atualização.
class AppUpdateInfo {
  final String currentVersion;
  final String currentBuild;
  final String latestVersion;
  final int latestBuild;
  final String updateUrl;

  /// De qual loja a atualização vem (decide texto e ícone da tela).
  final AppStoreKind store;

  /// O que mudou, quando a fonte informa.
  final List<String> notes;

  const AppUpdateInfo({
    required this.currentVersion,
    required this.currentBuild,
    required this.latestVersion,
    required this.latestBuild,
    required this.updateUrl,
    required this.store,
    this.notes = const [],
  });

  String get currentLabel =>
      latestBuild > 0 ? '$currentVersion ($currentBuild)' : currentVersion;

  String get latestLabel =>
      latestBuild > 0 ? '$latestVersion ($latestBuild)' : latestVersion;

  /// Quantas versões MENORES o usuário está atrás, dentro do mesmo major.
  /// 0 = só a build mudou. Não inventa número quando o major pula: para
  /// isso existe [saltoDeMajor] — dizer "10 versões atrás" seria mentira.
  int get versionsBehind {
    final atual = _partes(currentVersion);
    final nova = _partes(latestVersion);
    if (_at(nova, 0) != _at(atual, 0)) return 0;
    final minors = _at(nova, 1) - _at(atual, 1);
    return minors > 0 ? minors : 0;
  }

  /// A versão publicada mudou de major — salto grande, tom próprio na tela.
  bool get saltoDeMajor =>
      _at(_partes(latestVersion), 0) > _at(_partes(currentVersion), 0);

  static List<int> _partes(String v) => v
      .split('+')
      .first
      .split('.')
      .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList();

  static int _at(List<int> l, int i) => i < l.length ? l[i] : 0;
}

/// Verifica se há versão mais nova em PRODUÇÃO.
///
/// Fonte da verdade no iOS: a PRÓPRIA App Store, via iTunes Lookup pelo
/// bundle id (sem depender de backend). Fallbacks: endpoint
/// `/app/mobile-version` do backend e, por último, o asset
/// `assets/config/app_update.txt`. Aviso "soft": apenas informa — o botão
/// leva pra página do app na loja. (TestFlight morreu: o app está em
/// produção; não reintroduzir.)
class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  /// Evita repetir o popup na mesma sessão (exceto [checkForUpdate] com force).
  bool _checkedThisSession = false;

  /// Retorna info de atualização se houver versão mais nova; senão `null`.
  Future<AppUpdateInfo?> checkForUpdate({bool force = false}) async {
    if (_checkedThisSession && !force) return null;
    // Android entrou: a Play não tem lookup público, então a fonte é o
    // backend (`/app/mobile-version`) e a URL da loja é derivada do pacote.
    // Antes o método abortava aqui e METADE da base nunca era avisada.
    if (!Platform.isIOS && !Platform.isAndroid) return null;

    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version.trim();
      final currentBuild = int.tryParse(info.buildNumber.trim()) ?? 0;

      final latest = Platform.isIOS
          ? await _resolveLatestIos(info.packageName)
          : await _resolveLatestAndroid(info.packageName);
      if (latest == null) {
        if (!force) _checkedThisSession = true;
        return null;
      }

      if (!_isUpdateAvailable(
        currentVersion: currentVersion,
        currentBuild: currentBuild,
        latest: latest,
      )) {
        if (!force) _checkedThisSession = true;
        return null;
      }

      if (!force) _checkedThisSession = true;

      return AppUpdateInfo(
        currentVersion: currentVersion,
        currentBuild: info.buildNumber.trim(),
        latestVersion: latest.version,
        latestBuild: latest.build,
        updateUrl: latest.updateUrl,
        store: Platform.isIOS
            ? AppStoreKind.appStore
            : AppStoreKind.playStore,
        notes: latest.notes,
      );
    } catch (e) {
      debugPrint('[AppUpdate] checagem falhou: $e');
      return null;
    }
  }

  bool _isUpdateAvailable({
    required String currentVersion,
    required int currentBuild,
    required MobileLatestVersion latest,
  }) {
    final versionCmp = _compareVersions(latest.version, currentVersion);
    if (versionCmp > 0) return true;
    if (versionCmp < 0) return false;
    // A App Store não expõe o número de build — quando a fonte tem build
    // (backend/asset), desempata por ele; lookup manda build 0 (= empate).
    return latest.build > currentBuild;
  }

  Future<MobileLatestVersion?> _resolveLatestIos(String bundleId) async {
    final store = await _fetchFromAppStore(bundleId);
    if (store != null) return store;
    final remote = await _fetchFromApi();
    if (remote != null) return remote;
    return _loadFromAsset();
  }

  /// iTunes Lookup — a versão que está NO AR na App Store + o link da
  /// página do app (`trackViewUrl`).
  Future<MobileLatestVersion?> _fetchFromAppStore(String bundleId) async {
    try {
      final uri = Uri.parse(
        'https://itunes.apple.com/lookup?bundleId=$bundleId&country=br',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      if (body is! Map) return null;
      final results = body['results'];
      if (results is! List || results.isEmpty) return null;
      final app = results.first;
      if (app is! Map) return null;
      final version = app['version']?.toString().trim();
      final url = app['trackViewUrl']?.toString().trim();
      if (version == null || version.isEmpty) return null;
      if (url == null || url.isEmpty) return null;
      return MobileLatestVersion(version: version, build: 0, updateUrl: url);
    } catch (e) {
      debugPrint('[AppUpdate] iTunes lookup indisponível: $e');
      return null;
    }
  }

  /// Android: a Play Store não tem lookup público como o iTunes, então a
  /// versão vem do backend. A URL da loja é DERIVADA do pacote — é
  /// determinística, não precisa ser configurada e nunca fica velha.
  Future<MobileLatestVersion?> _resolveLatestAndroid(String pkg) async {
    final remote = await _fetchFromApi(plataforma: 'android');
    if (remote == null) return null;
    final url = remote.updateUrl.isNotEmpty
        ? remote.updateUrl
        : 'https://play.google.com/store/apps/details?id=$pkg';
    return MobileLatestVersion(
      version: remote.version,
      build: remote.build,
      updateUrl: url,
      notes: remote.notes,
    );
  }

  Future<MobileLatestVersion?> _fetchFromApi({
    String plataforma = 'ios',
  }) async {
    try {
      final base = ApiConstants.baseUrl;
      final uri = Uri.parse('$base/app/mobile-version');
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      if (body is! Map) return null;
      final node = body[plataforma];
      if (node is! Map) return null;
      final version = node['version']?.toString().trim();
      final buildRaw = node['build'];
      final build = buildRaw is int
          ? buildRaw
          : int.tryParse(buildRaw?.toString() ?? '') ?? 0;
      if (version == null || version.isEmpty) return null;
      // No Android a URL é opcional (derivada do pacote); no iOS ela é
      // obrigatória, porque não dá para montar o link da App Store sem o id.
      final url =
          (node['appStoreUrl'] ?? node['playStoreUrl'] ?? node['updateUrl'])
              ?.toString()
              .trim() ??
          '';
      if (url.isEmpty && plataforma != 'android') return null;
      final notasRaw = node['notes'];
      final notas = notasRaw is List
          ? notasRaw
              .map((e) => e?.toString().trim() ?? '')
              .where((e) => e.isNotEmpty)
              .toList()
          : const <String>[];
      return MobileLatestVersion(
        version: version,
        build: build,
        updateUrl: url,
        notes: notas,
      );
    } catch (e) {
      debugPrint('[AppUpdate] API indisponível: $e');
      return null;
    }
  }

  Future<MobileLatestVersion?> _loadFromAsset() async {
    try {
      final raw = await rootBundle.loadString('assets/config/app_update.txt');
      final lines = raw
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .toList();
      // Formato: versão / build / URL da página na App Store (obrigatória).
      if (lines.length < 3 || lines[2].isEmpty) return null;
      final version = lines[0];
      final build = int.tryParse(lines[1]) ?? 0;
      return MobileLatestVersion(
        version: version,
        build: build,
        updateUrl: lines[2],
      );
    } catch (e) {
      debugPrint('[AppUpdate] asset app_update.txt: $e');
      return null;
    }
  }

  /// Compara "a" e "b" no formato x.y.z. Retorna >0 se a>b, 0 se igual, <0 se a<b.
  int _compareVersions(String a, String b) {
    List<int> parse(String v) => v
        .split('+')
        .first
        .split('.')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();

    final pa = parse(a);
    final pb = parse(b);
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x - y;
    }
    return 0;
  }
}
