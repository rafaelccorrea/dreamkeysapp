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

  const MobileLatestVersion({
    required this.version,
    required this.build,
    required this.updateUrl,
  });
}

/// Resultado da checagem de atualização.
class AppUpdateInfo {
  final String currentVersion;
  final String currentBuild;
  final String latestVersion;
  final int latestBuild;
  final String updateUrl;

  const AppUpdateInfo({
    required this.currentVersion,
    required this.currentBuild,
    required this.latestVersion,
    required this.latestBuild,
    required this.updateUrl,
  });

  String get currentLabel =>
      latestBuild > 0 ? '$currentVersion ($currentBuild)' : currentVersion;

  String get latestLabel =>
      latestBuild > 0 ? '$latestVersion ($latestBuild)' : latestVersion;
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
    // Android fica de fora por ora: a Play não expõe lookup público e o
    // update lá já é empurrado pela própria loja.
    if (!Platform.isIOS) return null;

    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version.trim();
      final currentBuild = int.tryParse(info.buildNumber.trim()) ?? 0;

      final latest = await _resolveLatestIos(info.packageName);
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

  Future<MobileLatestVersion?> _fetchFromApi() async {
    try {
      final base = ApiConstants.baseUrl;
      final uri = Uri.parse('$base/app/mobile-version');
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      if (body is! Map) return null;
      final ios = body['ios'];
      if (ios is! Map) return null;
      final version = ios['version']?.toString().trim();
      final buildRaw = ios['build'];
      final build = buildRaw is int
          ? buildRaw
          : int.tryParse(buildRaw?.toString() ?? '') ?? 0;
      if (version == null || version.isEmpty) return null;
      final url = (ios['appStoreUrl'] ?? ios['updateUrl'])
          ?.toString()
          .trim();
      if (url == null || url.isEmpty) return null;
      return MobileLatestVersion(
        version: version,
        build: build,
        updateUrl: url,
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
