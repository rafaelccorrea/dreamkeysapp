// Gere valores reais com: dart pub global activate flutterfire_cli && flutterfire configure
// Até lá, o app compila; FCM só funciona após configurar o projeto Firebase e substituir estes valores.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
class DefaultFirebaseOptions {
  /// `true` quando ainda há placeholders de [flutterfire configure] nesta plataforma.
  /// Nesse caso **não** chame `Firebase.initializeApp` no iOS: o SDK nativo pode encerrar
  /// o processo (crash ao abrir) em vez de propagar erro para o Dart.
  static bool looksLikePlaceholder(FirebaseOptions o) {
    const k = 'REPLACE_WITH';
    return o.apiKey.contains(k) ||
        o.appId.contains(k) ||
        o.projectId.contains(k) ||
        o.messagingSenderId.contains(k);
  }

  /// Firebase pronto para uso neste dispositivo (sem placeholders na opção da plataforma).
  static bool get isFirebaseConfigured {
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return !looksLikePlaceholder(android);
      case TargetPlatform.iOS:
        return !looksLikePlaceholder(ios);
      default:
        return false;
    }
  }

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Firebase web não é usado neste app.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions não definido para ${defaultTargetPlatform.name}',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCR7HQ7n7nLpRuzxbzjiK3inmDLOBu4W88',
    appId: '1:213709429896:android:b9a3267431c41a5b24133d',
    messagingSenderId: '213709429896',
    projectId: 'intellisys-68ea0',
    storageBucket: 'intellisys-68ea0.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyC0tznbXaxwPepgcjDqnCbmgekP4LWIP1w',
    appId: '1:213709429896:ios:66196bcf49edcab124133d',
    messagingSenderId: '213709429896',
    projectId: 'intellisys-68ea0',
    storageBucket: 'intellisys-68ea0.firebasestorage.app',
    iosBundleId: 'com.dreamkeys.corretor',
  );
}
