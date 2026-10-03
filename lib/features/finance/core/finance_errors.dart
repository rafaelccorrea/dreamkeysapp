import 'finance_config.dart';

/// Família do erro do Financeiro — decide o que a tela faz com ele.
enum FinanceErrorKind {
  /// 428 `FINANCE_PIN_REQUIRED`: o PIN abre por cima, sem perder a tela.
  pinRequired,

  /// 401: o Financeiro não reconheceu a sessão. NUNCA desloga o app — pode
  /// ser só "este usuário não alcança o Financeiro".
  unauthorized,

  /// 403 `COMPANY_NO_ACCESS`: a pessoa não tem acesso a esta empresa.
  companyNoAccess,

  /// 403 `COMPANY_NOT_PROVISIONED`: a empresa não tem o Financeiro.
  companyNotProvisioned,

  /// 403 de papel/permissão (`allowedRoles[]`).
  forbidden,

  /// 404.
  notFound,

  /// 409.
  conflict,

  /// 423 — trava de comprovante.
  receiptLock,

  /// 422/400 — validação ou regra de negócio (mensagem do back).
  validation,

  /// 429 — limite (PIN bloqueado, código recente…).
  tooMany,

  /// Sem rede / timeout.
  network,

  /// 5xx e o resto.
  server,
}

/// Erro normalizado de uma chamada ao Financeiro. Montado por
/// [FinanceError.fromResponse] — função pura, coberta por teste.
class FinanceError {
  final FinanceErrorKind kind;
  final int statusCode;
  final String? code;
  final String message;
  final List<String> allowedRoles;
  final Map<String, dynamic> body;

  const FinanceError({
    required this.kind,
    required this.statusCode,
    required this.message,
    this.code,
    this.allowedRoles = const [],
    this.body = const {},
  });

  /// Erros que vale a pena repetir (rede/servidor).
  bool get isRetryable =>
      kind == FinanceErrorKind.network || kind == FinanceErrorKind.server;

  /// Tentativas restantes do PIN (422 `PIN_INCORRETO`).
  int? get tentativasRestantes {
    final v = body['tentativasRestantes'];
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}');
  }

  /// Até quando o PIN está bloqueado (429 `PIN_BLOQUEADO`).
  DateTime? get bloqueadoAte {
    final v = body['bloqueadoAte'];
    if (v is! String || v.isEmpty) return null;
    return DateTime.tryParse(v)?.toLocal();
  }

  factory FinanceError.network({bool timeout = false}) => FinanceError(
    kind: FinanceErrorKind.network,
    statusCode: 0,
    code: timeout ? 'TIMEOUT' : null,
    message: timeout
        ? 'O Financeiro demorou para responder. Tente de novo.'
        : 'Sem conexão com o Financeiro. Verifique a internet e tente de novo.',
  );

  factory FinanceError.noCompany() => const FinanceError(
    kind: FinanceErrorKind.companyNoAccess,
    statusCode: 0,
    message:
        'Nenhuma empresa selecionada. Escolha uma empresa e tente de novo.',
  );

  /// Normaliza o corpo de erro do Nest (`{statusCode, message, code, …}`).
  factory FinanceError.fromResponse(int statusCode, dynamic decodedBody) {
    final body = decodedBody is Map
        ? decodedBody.map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};
    final code = body['code']?.toString();
    final rawMessage = _messageOf(body);
    final roles = body['allowedRoles'] is List
        ? (body['allowedRoles'] as List).map((e) => e.toString()).toList()
        : const <String>[];

    FinanceError build(FinanceErrorKind kind, String fallback) => FinanceError(
      kind: kind,
      statusCode: statusCode,
      code: code,
      message: rawMessage ?? fallback,
      allowedRoles: roles,
      body: body,
    );

    if (statusCode == 428 && code == FinanceConfig.pinRequiredCode) {
      return build(
        FinanceErrorKind.pinRequired,
        'Digite seu PIN para acessar o Financeiro.',
      );
    }
    switch (statusCode) {
      case 401:
        return FinanceError(
          kind: FinanceErrorKind.unauthorized,
          statusCode: 401,
          code: code,
          // Mensagem própria: o "Unauthorized" cru do back não diz nada.
          message:
              'O Financeiro não reconheceu seu acesso agora. Tente de novo; '
              'se continuar, fale com quem administra os acessos.',
          body: body,
        );
      case 403:
        if (code == 'COMPANY_NOT_PROVISIONED') {
          return FinanceError(
            kind: FinanceErrorKind.companyNotProvisioned,
            statusCode: 403,
            code: code,
            message:
                'Esta empresa ainda não tem o módulo Financeiro. Troque de '
                'empresa ou fale com o administrador.',
            body: body,
          );
        }
        if (code == 'COMPANY_NO_ACCESS') {
          return FinanceError(
            kind: FinanceErrorKind.companyNoAccess,
            statusCode: 403,
            code: code,
            message:
                'Você não tem acesso ao Financeiro desta empresa. Troque de '
                'empresa no seu perfil.',
            body: body,
          );
        }
        final quem = roles.isEmpty
            ? ''
            : ' Quem pode: ${roles.map(financeRoleLabel).join(', ')}.';
        return FinanceError(
          kind: FinanceErrorKind.forbidden,
          statusCode: 403,
          code: code,
          message: '${rawMessage ?? 'Seu papel não permite esta ação.'}$quem',
          allowedRoles: roles,
          body: body,
        );
      case 404:
        return build(FinanceErrorKind.notFound, 'Não encontrado.');
      case 409:
        return build(
          FinanceErrorKind.conflict,
          'Isto já foi alterado por outra pessoa. Atualize e tente de novo.',
        );
      case 423:
        return build(
          FinanceErrorKind.receiptLock,
          'Escrita bloqueada: há título aprovado sem comprovante há mais de 48 h.',
        );
      case 429:
        return build(
          FinanceErrorKind.tooMany,
          'Muitas tentativas. Aguarde um pouco e tente de novo.',
        );
      case 400:
      case 422:
        return build(FinanceErrorKind.validation, 'Dados inválidos.');
    }
    return build(
      FinanceErrorKind.server,
      'O Financeiro está com instabilidade. Tente de novo em instantes.',
    );
  }

  static String? _messageOf(Map<String, dynamic> body) {
    final m = body['message'];
    if (m is String && m.trim().isNotEmpty) return m.trim();
    if (m is List && m.isNotEmpty) {
      return m.map((e) => e.toString()).where((e) => e.isNotEmpty).join('\n');
    }
    return null;
  }

  @override
  String toString() =>
      'FinanceError($statusCode ${code ?? kind.name}: $message)';
}

/// Papel do Financeiro em português (mensagens de 403).
String financeRoleLabel(String role) {
  const labels = {
    'CORRETOR': 'Corretor',
    'GESTOR': 'Gestor',
    'DIRETOR': 'Diretor',
    'DIRETORIA': 'Diretoria',
    'RH': 'RH',
    'GESTOR_MARKETING': 'Gestor de marketing',
    'ANALISTA_FINANCEIRO': 'Analista financeiro',
    'GERENTE_FINANCEIRO': 'Gerente financeiro',
    'GERENTE': 'Gerente financeiro',
    'DIRETOR_FINANCEIRO': 'Diretor financeiro',
    'ADMIN': 'Administrador',
    'PENDENTE': 'Sem papel',
  };
  final key = role.trim().toUpperCase();
  final known = labels[key];
  if (known != null) return known;
  final words = key.toLowerCase().split('_').where((w) => w.isNotEmpty);
  final text = words.join(' ');
  return text.isEmpty ? role : '${text[0].toUpperCase()}${text.substring(1)}';
}
