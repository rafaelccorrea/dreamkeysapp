import 'package:shared_preferences/shared_preferences.dart';

/// Últimas telas visitadas — "continuar de onde parou" no Início.
class RecentNavigationCache {
  RecentNavigationCache._();
  static final RecentNavigationCache instance = RecentNavigationCache._();

  static const _routeKey = 'broker_recent_route_v1';
  static const _labelKey = 'broker_recent_label_v1';
  static const _extraKey = 'broker_recent_extra_v1';

  String? _route;
  String? _label;
  String? _extra;
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _route = prefs.getString(_routeKey);
    _label = prefs.getString(_labelKey);
    _extra = prefs.getString(_extraKey);
    _loaded = true;
  }

  Future<void> save({
    required String route,
    required String label,
    String? extra,
  }) async {
    _route = route;
    _label = label;
    _extra = extra;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_routeKey, route);
    await prefs.setString(_labelKey, label);
    if (extra != null) {
      await prefs.setString(_extraKey, extra);
    } else {
      await prefs.remove(_extraKey);
    }
  }

  String? get route => _route;
  String? get label => _label;
  String? get extra => _extra;
  bool get hasRecent => _route != null && _route!.isNotEmpty;
}
