import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Família do erro — define cor, ícone e, principalmente, QUEM pode resolver.
///
/// A distinção importa mais que a estética: erro de rede o usuário resolve
/// sozinho; erro de permissão só o administrador resolve; erro de servidor
/// ninguém na ponta resolve. Dizer "Algo deu errado" nos três casos é o que
/// fazia o corretor tentar de novo dez vezes sem chance de sucesso.
enum ErrorKind {
  /// Sem internet, DNS, servidor fora do ar, timeout.
  conexao,

  /// Sessão expirada / token inválido — precisa entrar de novo.
  sessao,

  /// Empresa não resolvida — caso específico do app multiempresa.
  empresa,

  /// Falta permissão para a operação.
  permissao,

  /// O registro não existe (ou foi removido/arquivado).
  ausente,

  /// Dados recusados pelo servidor (validação, conflito, regra de negócio).
  dados,

  /// Excesso de tentativas.
  limite,

  /// Falha do lado do servidor (5xx).
  servidor,

  /// Não classificado.
  desconhecido,
}

/// Diagnóstico pronto para exibição: o QUE houve, POR QUE e O QUE FAZER.
class ErrorCause {
  /// Título curto (sem ponto final).
  final String title;

  /// A causa REAL, em uma frase. Quando o servidor manda uma explicação
  /// específica, é ela que aparece aqui — não uma genérica.
  final String cause;

  /// O próximo passo concreto de quem está lendo.
  final String action;

  final ErrorKind kind;
  final IconData icon;
  final Color tone;

  /// Linha técnica para suporte (código HTTP + mensagem crua). Fica atrás de
  /// um "ver detalhe" — útil para o chamado, sem poluir a tela.
  final String? technical;

  /// Repetir a operação tem chance real de dar certo? Falso em permissão,
  /// sessão e ausente — nesses casos insistir só frustra.
  final bool retryable;

  const ErrorCause({
    required this.title,
    required this.cause,
    required this.action,
    required this.kind,
    required this.icon,
    required this.tone,
    required this.retryable,
    this.technical,
  });

  static const Color _rose = Color(0xFFE11D48);
  static const Color _amber = Color(0xFFD97706);
  static const Color _violet = Color(0xFF8B5CF6);
  static const Color _slate = Color(0xFF64748B);
  static const Color _sky = Color(0xFF0EA5E9);
  static const Color _indigo = Color(0xFF6366F1);

  /// Traduz uma falha de API no diagnóstico.
  ///
  /// [message] é a mensagem que o backend devolveu — quase sempre a
  /// informação mais valiosa da tela ("CPF já cadastrado", "imóvel sem
  /// captador"). Ela é preservada como causa sempre que for específica.
  factory ErrorCause.fromApi({
    String? message,
    int statusCode = 0,
    Object? error,
  }) {
    final crua = (message ?? '').trim();
    final tecnica = _tecnica(crua, statusCode, error);

    // Genérica = não acrescenta nada ao que o código HTTP já diz. Nesse caso
    // preferimos a explicação da família a repetir "erro ao carregar".
    final especifica = _ehEspecifica(crua) ? crua : null;

    if (crua.contains('Company ID não encontrado')) {
      return ErrorCause(
        title: 'Empresa não selecionada',
        cause:
            'O aplicativo não conseguiu identificar em qual empresa você está '
            'operando, então bloqueou a consulta antes de enviá-la.',
        action: 'Toque em recarregar. Se persistir, saia e entre novamente.',
        kind: ErrorKind.empresa,
        icon: LucideIcons.building2,
        tone: _indigo,
        retryable: true,
        technical: tecnica,
      );
    }

    if (statusCode == 0) {
      return ErrorCause(
        title: 'Sem resposta do servidor',
        cause: especifica ??
            'O aparelho não conseguiu falar com o servidor. Costuma ser '
                'internet instável, mas também acontece quando o servidor está '
                'fora do ar.',
        action: 'Confira sua conexão e tente de novo.',
        kind: ErrorKind.conexao,
        icon: LucideIcons.wifiOff,
        tone: _amber,
        retryable: true,
        technical: tecnica,
      );
    }

    if (statusCode == 401) {
      return ErrorCause(
        title: 'Sessão expirada',
        cause: especifica ??
            'Sua sessão venceu ou foi encerrada em outro aparelho. Por '
                'segurança, o acesso precisa ser renovado.',
        action: 'Entre novamente para continuar.',
        kind: ErrorKind.sessao,
        icon: LucideIcons.userX,
        tone: _rose,
        retryable: false,
        technical: tecnica,
      );
    }

    if (statusCode == 403) {
      return ErrorCause(
        title: 'Sem permissão',
        cause: especifica ??
            'Seu usuário não tem permissão para esta operação. Não é uma '
                'falha do aplicativo: o acesso é definido pelo administrador.',
        action: 'Peça a liberação ao administrador da sua empresa.',
        kind: ErrorKind.permissao,
        icon: LucideIcons.lock,
        tone: _violet,
        retryable: false,
        technical: tecnica,
      );
    }

    if (statusCode == 404) {
      return ErrorCause(
        title: 'Não encontrado',
        cause: especifica ??
            'O registro não existe mais. Pode ter sido excluído ou movido por '
                'outra pessoa depois que esta tela foi aberta.',
        action: 'Volte e atualize a lista.',
        kind: ErrorKind.ausente,
        icon: LucideIcons.searchX,
        tone: _slate,
        retryable: false,
        technical: tecnica,
      );
    }

    if (statusCode == 429) {
      return ErrorCause(
        title: 'Muitas tentativas',
        cause: especifica ??
            'O servidor recebeu pedidos demais deste aparelho em pouco tempo '
                'e passou a recusá-los temporariamente.',
        action: 'Aguarde alguns instantes e tente de novo.',
        kind: ErrorKind.limite,
        icon: LucideIcons.hourglass,
        tone: _amber,
        retryable: true,
        technical: tecnica,
      );
    }

    if (statusCode >= 500) {
      return ErrorCause(
        title: 'Falha no servidor',
        cause: especifica ??
            'O servidor encontrou um erro ao processar o pedido. O problema '
                'não está no seu aparelho nem no que você digitou.',
        action: 'Tente de novo em instantes. Se continuar, avise o suporte.',
        kind: ErrorKind.servidor,
        icon: LucideIcons.serverCrash,
        tone: _rose,
        retryable: true,
        technical: tecnica,
      );
    }

    if (statusCode >= 400) {
      return ErrorCause(
        title: 'Pedido recusado',
        cause: especifica ??
            'O servidor recusou os dados enviados. Normalmente falta um campo '
                'obrigatório ou algum valor conflita com um registro existente.',
        action: 'Revise os dados e tente novamente.',
        kind: ErrorKind.dados,
        icon: LucideIcons.circleAlert,
        tone: _amber,
        retryable: true,
        technical: tecnica,
      );
    }

    return ErrorCause(
      title: 'Não foi possível concluir',
      cause: especifica ??
          'A operação falhou sem que o servidor explicasse o motivo.',
      action: 'Tente novamente.',
      kind: ErrorKind.desconhecido,
      icon: LucideIcons.circleAlert,
      tone: _sky,
      retryable: true,
      technical: tecnica,
    );
  }

  /// Traduz uma exceção solta (fora do fluxo de `ApiResponse`).
  factory ErrorCause.fromException(Object e) {
    final txt = e.toString();
    final ehRede = txt.contains('SocketException') ||
        txt.contains('Failed host lookup') ||
        txt.contains('Connection closed') ||
        txt.contains('Connection refused');
    final ehTimeout = txt.contains('TimeoutException');

    if (ehRede || ehTimeout) {
      return ErrorCause(
        title: ehTimeout ? 'O servidor demorou demais' : 'Sem conexão',
        cause: ehTimeout
            ? 'O pedido foi enviado, mas a resposta não chegou no tempo '
                'esperado. Conexão lenta ou servidor sobrecarregado.'
            : 'Não foi possível alcançar o servidor. Verifique se o aparelho '
                'está conectado à internet.',
        action: 'Tente novamente em instantes.',
        kind: ErrorKind.conexao,
        icon: ehTimeout ? LucideIcons.hourglass : LucideIcons.wifiOff,
        tone: _amber,
        retryable: true,
        technical: txt,
      );
    }

    return ErrorCause(
      title: 'Erro inesperado',
      cause: 'O aplicativo encontrou uma falha ao executar esta operação.',
      action: 'Tente novamente. Se continuar, envie o detalhe ao suporte.',
      kind: ErrorKind.desconhecido,
      icon: LucideIcons.circleAlert,
      tone: _sky,
      retryable: true,
      technical: txt,
    );
  }

  /// Mensagens vagas do backend não valem como "causa": repetir "Erro ao
  /// carregar" na tela é exatamente o que o usuário reclamou.
  static bool _ehEspecifica(String m) {
    if (m.isEmpty) return false;
    if (m.length < 12) return false;
    final baixo = m.toLowerCase();
    const vagas = [
      'erro ao carregar',
      'erro ao buscar',
      'erro interno',
      'algo deu errado',
      'ocorreu um erro',
      'erro desconhecido',
      'internal server error',
      'bad request',
      'unauthorized',
      'forbidden',
      'not found',
    ];
    for (final v in vagas) {
      if (baixo == v || baixo.startsWith('$v.') || baixo.startsWith('$v:')) {
        return false;
      }
    }
    return true;
  }

  static String? _tecnica(String message, int statusCode, Object? error) {
    final partes = <String>[];
    if (statusCode > 0) partes.add('HTTP $statusCode');
    if (message.isNotEmpty) partes.add(message);
    if (error != null) {
      final e = error.toString().trim();
      if (e.isNotEmpty && e != message && e != 'null') partes.add(e);
    }
    return partes.isEmpty ? null : partes.join(' · ');
  }
}
