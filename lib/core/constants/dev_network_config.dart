/// Rede local — desenvolvimento com **celular físico** (Android/iOS) na mesma Wi‑Fi do PC.
///
/// **Android (USB + debug):** deixe vazio e use `adb reverse tcp:3000 tcp:3000` — a API vai em 127.0.0.1.
///
/// **Wi‑Fi:** IPv4 do PC em `assets/config/dev_lan_host.txt`, aqui em [pcLanIPv4]
/// ou `flutter run --dart-define=DEV_LAN_HOST=192.168.1.15`
///
/// **API em produção** (mesma base que `imobx-front` `apiConfig.ts` por omissão): [productionApiBaseUrl].
/// Ative com `assets/config/api_target.txt` → primeira linha `production`.
class DevNetworkConfig {
  DevNetworkConfig._();

  /// Base pública quando `api_target.txt` = `production` (evita timeout na LAN / firewall).
  static const String productionApiBaseUrl = 'https://api.dreamkeys.com.br';

  /// IPv4 do PC na LAN (`ipconfig`). Tem prioridade sobre `assets/config/dev_lan_host.txt`.
  /// Vazio = usa o arquivo / 127.0.0.1 + adb no Android debug (ver comentário da classe).
  static const String pcLanIPv4 = '';
}
