import 'package:flutter/material.dart';

import 'app_toast.dart';

/// Atalhos para feedback consistente. Preferível a `SnackBar` cru.
abstract final class AppFeedback {
  static void show(
    BuildContext context,
    String message, {
    AppToastKind kind = AppToastKind.info,
    String? subtitle,
    Duration duration = const Duration(milliseconds: 3400),
  }) {
    AppToast.show(
      context,
      message: message,
      kind: kind,
      subtitle: subtitle,
      duration: duration,
    );
  }

  static void success(BuildContext context, String message, {String? subtitle}) =>
      AppToast.success(context, message, subtitle: subtitle);

  static void error(BuildContext context, String message, {String? subtitle}) =>
      AppToast.error(context, message, subtitle: subtitle);

  static void warning(BuildContext context, String message, {String? subtitle}) =>
      AppToast.warning(context, message, subtitle: subtitle);

  static void info(BuildContext context, String message, {String? subtitle}) =>
      AppToast.info(context, message, subtitle: subtitle);
}
