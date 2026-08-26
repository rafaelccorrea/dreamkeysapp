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
  /// Canal por onde os deep links chegam ao Flutter: esquema `dreamkeys://` e
  /// Universal Links `https://intellisysbr.com/sistema/...`.
  /// O roteamento default do engine (`FlutterDeepLinkingEnabled`) foi
  /// DESLIGADO no Info.plist: ele empurrava o path cru pro Navigator e caía
  /// em "Página não encontrada". Aqui o link vai inteiro pro Dart, que decide
  /// a rota (DeepLinkService).
  private var deepLinkChannel: FlutterMethodChannel?

  /// Último link ainda não consumido pelo Dart. Cobre o cold start: o handler
  /// do Flutter ainda não existe quando o iOS entrega a URL, então o Dart
  /// busca via `getInitialLink` depois que sobe.
  private var pendingDeepLink: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    configureFirebaseIfAvailable()

    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    // Cold start via URL (app fechado): a URL vem nas launchOptions.
    if let url = launchOptions?[.url] as? URL, url.scheme == "dreamkeys" {
      pendingDeepLink = url.absoluteString
    }

    GeneratedPluginRegistrant.register(with: self)
    let ok = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    registerLiveActivityCacheChannel()
    registerDeepLinkChannel()
    return ok
  }

  /// Warm start (app vivo em background/foreground): iOS entrega a URL aqui.
  /// Também é chamado logo após o launch num cold start via URL — o
  /// `pendingDeepLink` + dedupe no Dart cobrem a dupla entrega.
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if url.scheme == "dreamkeys" {
      pendingDeepLink = url.absoluteString
      deepLinkChannel?.invokeMethod("onLink", arguments: url.absoluteString)
      return true
    }
    return super.application(app, open: url, options: options)
  }

  /// Universal Links (https://intellisysbr.com/sistema/...). O iOS NÃO chama
  /// `application(_:open:)` para eles — chega tudo por aqui, tanto no cold
  /// start (logo após o `didFinishLaunching`, que já registrou o canal) quanto
  /// no warm start. Alimenta o MESMO `pendingDeepLink` + canal do esquema
  /// `dreamkeys://`: no cold start o handler Dart ainda não existe e o link é
  /// resgatado pelo `getInitialLink`; o dedupe do Dart cobre a dupla entrega.
  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
       let url = userActivity.webpageURL {
      pendingDeepLink = url.absoluteString
      deepLinkChannel?.invokeMethod("onLink", arguments: url.absoluteString)
      return true
    }
    return super.application(
      application,
      continue: userActivity,
      restorationHandler: restorationHandler
    )
  }

  private func registerDeepLinkChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "com.dreamkeys.corretor/deep_link",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "getInitialLink":
        result(self?.pendingDeepLink)
        self?.pendingDeepLink = nil
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    deepLinkChannel = channel
  }

  private func registerLiveActivityCacheChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "com.dreamkeys.corretor/live_activity",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard let ud = UserDefaults(suiteName: "group.com.dreamkeys.corretor") else {
        result(false)
        return
      }
      switch call.method {
      case "cacheIslandPayload":
        guard let args = call.arguments as? [String: Any] else {
          result(false)
          return
        }
        for (key, value) in args {
          if let s = value as? String {
            ud.set(s, forKey: "island_\(key)")
          }
        }
        ud.synchronize()
        result(true)
      case "clearIslandPayload":
        for key in ["userName", "companyName", "statusPhase", "expiresAtEpoch", "checkedInAtEpoch", "status"] {
          ud.removeObject(forKey: "island_\(key)")
        }
        ud.synchronize()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
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
