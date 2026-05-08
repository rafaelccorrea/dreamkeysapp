import '../../core/constants/api_constants.dart';

class AvatarUrlResolver {
  AvatarUrlResolver._();

  static String? resolve(String? rawUrl) {
    final value = rawUrl?.trim();
    if (value == null || value.isEmpty) return null;

    final lower = value.toLowerCase();
    final isHttp = lower.startsWith('http://') || lower.startsWith('https://');
    if (isHttp) return value;

    // Compatibilidade com respostas antigas que devolvem caminho relativo.
    if (value.startsWith('/')) {
      return '${ApiConstants.baseApiUrl}$value';
    }

    return value;
  }
}
