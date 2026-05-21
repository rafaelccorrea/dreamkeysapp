/// Ícones alinhados ao painel **Intellisys** (`imobx-front`): o menu lateral usa
/// [Lucide React](https://lucide.dev) — ver `src/config/drawerIcons.tsx`.
///
/// No Flutter, use a mesma família via [LucideIcons]:
/// ```dart
/// import 'package:lucide_icons_flutter/lucide_icons.dart';
/// Icon(LucideIcons.home, size: AppIconSize.md);
/// ```
library;

export 'package:lucide_icons_flutter/lucide_icons.dart' show LucideIcons;

/// Tamanhos úteis (Lucide = traço único; equivalente visual ao web ~20–24px).
class AppIconSize {
  AppIconSize._();
  static const double xs = 18;
  static const double sm = 20;
  static const double md = 22;
  static const double lg = 24;
}
