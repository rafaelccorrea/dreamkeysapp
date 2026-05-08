import '../../core/constants/api_constants.dart';

class AvatarUrlResolver {
  AvatarUrlResolver._();

  static const String _defaultCloudFrontBase =
      String.fromEnvironment(
        'MEDIA_CDN_BASE_URL',
        defaultValue: 'https://d2psivjvetbfrj.cloudfront.net',
      );

  static String get _cloudFrontBase {
    var v = _defaultCloudFrontBase.trim();
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }

  static String? resolve(String? rawUrl) {
    final value = rawUrl?.trim();
    if (value == null || value.isEmpty) return null;

    final lower = value.toLowerCase();
    final isHttp = lower.startsWith('http://') || lower.startsWith('https://');
    if (isHttp) {
      final uri = Uri.tryParse(value);
      if (uri != null) {
        final host = uri.host.toLowerCase();
        // Bucket S3 bloqueado para acesso público direto: sempre servir pelo CDN.
        if (host == 'dream-keys.s3.us-east-1.amazonaws.com') {
          final path = uri.path.startsWith('/') ? uri.path : '/${uri.path}';
          return '$_cloudFrontBase$path';
        }
      }
      return value;
    }

    // Compatibilidade com respostas antigas que devolvem caminho relativo.
    if (value.startsWith('/')) {
      if (_cloudFrontBase.isNotEmpty) return '$_cloudFrontBase$value';
      return '${ApiConstants.baseApiUrl}$value';
    }

    if (_cloudFrontBase.isNotEmpty) return '$_cloudFrontBase/$value';
    return '${ApiConstants.baseApiUrl}/$value';
  }
}
