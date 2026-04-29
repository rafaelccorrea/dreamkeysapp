import '../constants/api_constants.dart';

/// Mensagens de erro de rede para chamadas à API.
class ApiConnectionMessage {
  ApiConnectionMessage._();

  static String forException(Object error) {
    final s = error.toString();
    final refused =
        s.contains('Connection refused') || s.contains('errno = 111');
    final loopback = s.contains('127.0.0.1') || s.contains('localhost');
    if (refused && loopback) {
      return 'Não foi possível conectar à API em 127.0.0.1. No celular físico '
          'esse endereço é o próprio aparelho, não o PC. Com USB, no PC rode: '
          'adb reverse tcp:3000 tcp:3000 e instale de novo (flutter run). Na '
          'Wi‑Fi, coloque o IPv4 do PC em assets/config/dev_lan_host.txt, em '
          'dev_network_config.dart (pcLanIPv4) ou --dart-define=DEV_LAN_HOST=... '
          'Verifique se o backend está '
          'ativo na porta 3000. Detalhe: $s';
    }

    final timedOut = s.contains('TimeoutException') ||
        s.contains('Future not completed');
    if (timedOut) {
      final base = ApiConstants.baseApiUrl;
      return 'Tempo esgotado ao falar com a API ($base). O app não recebeu resposta '
          'em 30s. Confira: (1) PC e telemóvel na mesma Wi‑Fi; (2) IPv4 atual do PC '
          'em assets/config/dev_lan_host.txt ou '
          '--dart-define=DEV_LAN_HOST=192.168.x.x; (3) URL fixa com '
          '--dart-define=API_BASE_URL=http://IP:3000; (4) se a URL for 127.0.0.1 no '
          'celular, use USB e adb reverse tcp:3000 tcp:3000; (5) backend a ouvir em '
          '0.0.0.0 (ex.: Nest listen 0.0.0.0), não só em localhost; (6) firewall do '
          'Windows a permitir a porta. Detalhe: $s';
    }

    return 'Erro de conexão: $s';
  }
}
