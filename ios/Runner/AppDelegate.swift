import Flutter
import UIKit
import UserNotifications
#if canImport(FirebaseCore)
import FirebaseCore
#endif

/// AppDelegate do Intellisys.
///
/// Push notifications:
///   1. Inicializa o Firebase nativo apenas se `GoogleService-Info.plist` existir
///      no bundle. Sem ele, o app abre normalmente (sem push remoto), em vez
///      de crashar — útil no desenvolvimento antes de subir as credenciais.
///   2. Adota `UNUserNotificationCenter.current().delegate = self` para que
///      foreground / tap sejam capturados pelo `flutter_local_notifications`
///      e pelo `firebase_messaging`. O proxy do FlutterFire (habilitado no
///      `Info.plist` por defeito) repassa o APNs token para o `Messaging`.
@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    configureFirebaseIfAvailable()

    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Inicializa o Firebase só quando há `GoogleService-Info.plist` no bundle
  /// **com valores reais**. Um plist placeholder (com `REPLACE_WITH_*`) ou
  /// `FirebaseApp.configure()` chamado sem plist faz o processo explodir,
  /// então preferimos ficar silenciosamente sem push do que crashar.
  private func configureFirebaseIfAvailable() {
    #if canImport(FirebaseCore)
    guard
      let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
      let dict = NSDictionary(contentsOfFile: path)
    else {
      NSLog("[Push] GoogleService-Info.plist ausente — push remoto desligado.")
      return
    }

    let isPlaceholder = dict.allValues.contains { value in
      if let s = value as? String { return s.hasPrefix("REPLACE_WITH") }
      return false
    }
    guard !isPlaceholder else {
      NSLog("[Push] GoogleService-Info.plist com placeholders — push remoto desligado. " +
            "Substitua pelo arquivo real do Firebase Console (ver PUSH_SETUP.md).")
      return
    }

    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
    }
    #endif
  }
}
