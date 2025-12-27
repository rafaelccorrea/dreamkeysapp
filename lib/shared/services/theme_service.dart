import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Serviço para gerenciar o tema da aplicação
class ThemeService extends ChangeNotifier {
  ThemeService._();
  
  static final ThemeService instance = ThemeService._();
  
  static const String _themeKey = 'app_theme_mode';
  
  ThemeMode _themeMode = ThemeMode.light;
  
  ThemeMode get themeMode => _themeMode;
  
  /// Inicializa o serviço de tema carregando a preferência salva
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeModeString = prefs.getString(_themeKey);
      
      if (themeModeString != null) {
        _themeMode = _themeModeFromString(themeModeString);
        debugPrint('✅ [THEME_SERVICE] Tema carregado: $_themeMode');
      } else {
        // Padrão: light
        _themeMode = ThemeMode.light;
        debugPrint('✅ [THEME_SERVICE] Tema padrão (light) aplicado');
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('❌ [THEME_SERVICE] Erro ao carregar tema: $e');
      _themeMode = ThemeMode.light;
    }
  }
  
  /// Define o tema e salva a preferência
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    
    _themeMode = mode;
    notifyListeners();
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeKey, _themeModeToString(mode));
      debugPrint('✅ [THEME_SERVICE] Tema alterado para: $mode');
    } catch (e) {
      debugPrint('❌ [THEME_SERVICE] Erro ao salvar tema: $e');
    }
  }
  
  /// Converte ThemeMode para String
  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
  
  /// Converte String para ThemeMode
  ThemeMode _themeModeFromString(String value) {
    switch (value) {
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      case 'light':
      default:
        return ThemeMode.light;
    }
  }
  
  /// Retorna o nome do tema para exibição
  String getThemeName() {
    switch (_themeMode) {
      case ThemeMode.light:
        return 'Claro';
      case ThemeMode.dark:
        return 'Escuro';
      case ThemeMode.system:
        return 'Sistema';
    }
  }
  
  /// Retorna o ícone do tema
  IconData getThemeIcon() {
    switch (_themeMode) {
      case ThemeMode.light:
        return Icons.light_mode;
      case ThemeMode.dark:
        return Icons.dark_mode;
      case ThemeMode.system:
        return Icons.brightness_auto;
    }
  }
}





