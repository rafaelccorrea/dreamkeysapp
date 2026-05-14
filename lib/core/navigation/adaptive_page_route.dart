import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';

/// Verdadeiro em **iOS nativo** (não web): alinha transição, gesto de voltar na
/// borda e [Scaffold.drawerEnableOpenDragGesture] com o comportamento de sistema.
///
/// Usa [defaultTargetPlatform] (não `dart:io` [Platform]) para ser válido em
/// compilações web e em testes.
bool get useCupertinoNativeTransitions =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// Rota de ecrã completo: [MaterialPageRoute] fora do iOS; no iOS,
/// [CupertinoPageRoute] (gesto de deslizar da esquerda para a direita).
///
/// **PopScope**: numa rota, qualquer [PopScope] com `canPop: false` faz o
/// `Navigator` reportar `doNotPop` e o gesto de borda **fica desativado** —
/// use `canPop: true` em ecrãs que devem voltar com gesto.
Route<T> adaptivePageRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
  bool fullscreenDialog = false,
}) {
  if (useCupertinoNativeTransitions) {
    return CupertinoPageRoute<T>(
      settings: settings,
      fullscreenDialog: fullscreenDialog,
      builder: builder,
    );
  }
  return MaterialPageRoute<T>(
    settings: settings,
    fullscreenDialog: fullscreenDialog,
    builder: builder,
  );
}
