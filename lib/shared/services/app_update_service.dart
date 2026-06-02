import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/constants/api_constants.dart';

/// Metadados da versão mais recente (TestFlight / backend).
class MobileLatestVersion {
  final String version;
  final int build;
  final String testFlightUrl;

  const MobileLatestVersion({
    required this.version,
    required this.build,
    required this.testFlightUrl,
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

  String get latestLabel => '$latestVersion ($latestBuild)';
}

/// Verifica se há build mais novo (TestFlight) consultando a API e, em fallback,
/// `assets/config/app_update.txt`. Aviso "soft": apenas informa.
class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  static const String defaultTestFlightUrl =
      'https://testflight.apple.com/join/V5dUfzYF';

  /// Evita repetir o popup na mesma sessão (exceto [checkForUpdate] com force).
  bool _checkedThisSession = false;

  /// Retorna info de atualização se houver versão/build mais novo; senão `null`.
  Future<AppUpdateInfo?> checkForUpdate({bool force = false}) async {
    if (_checkedThisSession && !force) return null;
    if (!Platform.isIOS) return null;

    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version.trim();
      final currentBuild = int.tryParse(info.buildNumber.trim()) ?? 0;

      final latest = await _resolveLatestIos();
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
        updateUrl: latest.testFlightUrl,
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
    return latest.build > currentBuild;
  }

  Future<MobileLatestVersion?> _resolveLatestIos() async {
    final remote = await _fetchFromApi();
    if (remote != null) return remote;
    return _loadFromAsset();
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
      if (version == null || version.isEmpty || build <= 0) return null;
      final url = (ios['testFlightUrl'] ?? ios['testflightUrl'])
              ?.toString()
              .trim() ??
          defaultTestFlightUrl;
      return MobileLatestVersion(
        version: version,
        build: build,
        testFlightUrl: url.isNotEmpty ? url : defaultTestFlightUrl,
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
      if (lines.length < 2) return null;
      final version = lines[0];
      final build = int.tryParse(lines[1]) ?? 0;
      if (build <= 0) return null;
      final url = lines.length >= 3 && lines[2].isNotEmpty
          ? lines[2]
          : defaultTestFlightUrl;
      return MobileLatestVersion(
        version: version,
        build: build,
        testFlightUrl: url,
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
