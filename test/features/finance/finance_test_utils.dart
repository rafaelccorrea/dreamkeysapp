import 'dart:convert';

/// JWT sem assinatura válida (o app só lê o payload), no formato do token do
/// PIN do back: `{typ:'fpin', k, em (ms), iat, exp (s)}`.
String fakePinJwt(
  DateTime issuedAt, {
  Duration ttl = const Duration(hours: 2),
  String userKey = 'user-1',
}) {
  String b64(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final header = b64({'alg': 'HS256', 'typ': 'JWT'});
  final payload = b64({
    'typ': 'fpin',
    'k': userKey,
    'em': issuedAt.millisecondsSinceEpoch,
    'iat': issuedAt.millisecondsSinceEpoch ~/ 1000,
    'exp': issuedAt.add(ttl).millisecondsSinceEpoch ~/ 1000,
  });
  return '$header.$payload.assinatura';
}

/// Relógio controlável.
class FakeClock {
  DateTime now;
  FakeClock(this.now);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}
