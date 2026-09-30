import 'sdr_availability.dart';

/// Situação que a tela mostra — derivada do status (web: `situacaoDo`).
enum SdrSituation { roleta, folga, pausado }

/// Filtros da lista (palavra + sublinhado, com contagem).
enum SdrRouletteFilter { todos, roleta, folga, pausado, locacao }

/// Atalho de duração da folga (web: `ATALHOS_DE_DURACAO`).
class SdrLeaveShortcut {
  final String label;
  final (DateTime, DateTime) Function(DateTime agora) range;

  const SdrLeaveShortcut(this.label, this.range);
}

/// Regras e textos da Roleta de SDRs — espelho, com as mesmas palavras, de
/// `imobx-front/src/components/whatsapp/SDRAvailabilityPanel.tsx`,
/// `utils/whatsappSdrDeLocacao.ts` e `utils/whatsappDisponibilidadeSdr.ts`.
///
/// O back (`sdr-availability.service.ts`) é a autoridade: só líder SDR,
/// `whatsapp:manage_config` ou admin mexem (403 para os demais); a roleta
/// nunca fica sem 1 SDR ativo; a folga agendada começa e termina sozinha
/// (`processScheduledReactivations` roda a cada listagem).
class SdrRouletteRules {
  SdrRouletteRules._();

  // ─── Dica do botão de entrada (web: `dicaDaDisponibilidadeDosSdrs`) ──────

  static const String dicaDistribuicaoLigada =
      'Quem está pausado não entra na roleta de conversas nem no sorteio do lead do site.';
  static const String dicaDistribuicaoDesligada =
      'A roleta de conversas está desligada; a pausa vale para o sorteio do card na chegada e do lead do site.';

  /// Botão sempre clicável: a pausa vale nos dois estados (roleta de
  /// conversas e/ou sorteio do lead do site). Só a dica muda.
  static String dicaDaDisponibilidade({required bool distribuicaoDesligada}) {
    return distribuicaoDesligada
        ? dicaDistribuicaoDesligada
        : dicaDistribuicaoLigada;
  }

  // ─── Roleta ──────────────────────────────────────────────────────────────

  static const String ultimoAtivo =
      'A roleta deve ter pelo menos 1 SDR ativo. Reative outro SDR antes de pausar este.';

  /// Motivo que o web manda ao pausar à mão (o back usa o mesmo padrão).
  static const String pausaManual = 'Pausado manualmente';

  static const String rodape =
      'A roleta sempre mantém pelo menos 1 SDR recebendo. Folga agendada pausa e devolve o SDR sozinha.';

  static const List<String> motivos = <String>[
    'Férias',
    'Folga',
    'Atestado',
    'Treinamento',
  ];

  static SdrSituation situacaoDo(SdrAvailability s) {
    if (s.isActive) return SdrSituation.roleta;
    if (s.status == SdrAvailabilityStatus.pausedScheduled) {
      return SdrSituation.folga;
    }
    return SdrSituation.pausado;
  }

  /// Folga marcada para o futuro (o SDR ainda recebe até lá).
  static bool folgaMarcada(SdrAvailability s, [DateTime? agora]) {
    final inicio = s.scheduledPauseStart;
    if (inicio == null || s.status == SdrAvailabilityStatus.pausedScheduled) {
      return false;
    }
    return inicio.isAfter(agora ?? DateTime.now());
  }

  /// O modal oferece "Cancelar a folga já marcada" (web: `hasPending`).
  static bool temFolgaPendente(SdrAvailability s) {
    return s.scheduledPauseStart != null &&
        s.status != SdrAvailabilityStatus.pausedScheduled;
  }

  /// Recusa do back pela regra do "pelo menos 1 SDR ativo".
  static bool ehRegraDoUltimoAtivo(String? mensagem) {
    final m = mensagem ?? '';
    return m.contains('pelo menos 1 SDR ativo') || m.contains('último SDR');
  }

  // ─── SDR de locação (web: `whatsappSdrDeLocacao.ts`) ─────────────────────

  static const String dicaLocacaoLigada =
      'SDR de locação: recebe só conversas de locação, e os cards dele nascem no funil de locação. Toque para voltar a receber venda.';
  static const String dicaLocacaoDesligada =
      'Marcar como SDR de locação: passa a receber só conversas de locação, com o card no funil de locação.';
  static const String marcacaoIndisponivel =
      'A marcação de SDR de locação ainda não está disponível neste servidor.';

  /// O back já manda `soLocacao`? Sem o campo em NENHUM item, a marcação some.
  static bool marcacaoDeLocacaoDisponivel(Iterable<SdrAvailability> itens) {
    return itens.any((item) => item.soLocacao != null);
  }

  static bool ehSdrDeLocacao(SdrAvailability s) => s.soLocacao == true;

  static int contarSdrsDeLocacao(Iterable<SdrAvailability> itens) {
    return itens.where(ehSdrDeLocacao).length;
  }

  static String dicaDaMarcaDeLocacao(bool soLocacao) {
    return soLocacao ? dicaLocacaoLigada : dicaLocacaoDesligada;
  }

  static String avisoAposMarcarSdr(String nome, bool soLocacao) {
    return soLocacao
        ? '$nome agora é SDR de locação: só conversas de locação.'
        : '$nome volta a receber conversas de venda.';
  }

  /// Texto do web quando a marcação falha sem explicação do back.
  static const String erroAoMarcarLocacao = 'Erro ao marcar SDR de locação';

  /// 404 da ROTA (back antigo, sem a marcação): o Nest responde
  /// "Cannot PATCH …" (ou um proxy devolve 404 sem JSON). Um 404 com motivo
  /// de negócio ("SDR não está na equipe do WhatsApp desta empresa.") é
  /// mostrado como veio.
  static bool ehRotaAusente(int statusCode, String? mensagem) {
    if (statusCode != 404) return false;
    final m = (mensagem ?? '').trim();
    return m.isEmpty ||
        m == 'Erro desconhecido' ||
        m == erroAoMarcarLocacao ||
        m.startsWith('Cannot ');
  }

  // ─── Folga ───────────────────────────────────────────────────────────────

  /// O campo de data e hora tem precisão de minuto (web: datetime-local).
  static DateTime aoMinuto(DateTime d) {
    return DateTime(d.year, d.month, d.day, d.hour, d.minute);
  }

  static final List<SdrLeaveShortcut> atalhos = <SdrLeaveShortcut>[
    SdrLeaveShortcut('Resto de hoje', (agora) {
      final a = aoMinuto(agora);
      return (a, DateTime(a.year, a.month, a.day, 23, 59));
    }),
    SdrLeaveShortcut('Amanhã', (agora) {
      final a = DateTime(agora.year, agora.month, agora.day + 1);
      return (a, DateTime(a.year, a.month, a.day, 23, 59));
    }),
    SdrLeaveShortcut('7 dias', (agora) {
      final a = aoMinuto(agora);
      return (a, a.add(const Duration(days: 7)));
    }),
    SdrLeaveShortcut('15 dias', (agora) {
      final a = aoMinuto(agora);
      return (a, a.add(const Duration(days: 15)));
    }),
  ];

  /// "3 dias e 4 h", "5 h", "40 min" — a duração da folga dita como se fala.
  /// `null` quando o fim não vem depois do início.
  static String? duracao(DateTime inicio, DateTime fim) {
    if (!fim.isAfter(inicio)) return null;
    final min = (fim.difference(inicio).inMilliseconds / 60000).round();
    final dias = min ~/ 1440;
    final horas = (min % 1440) ~/ 60;
    final minutos = min % 60;
    final rotuloDias = '$dias dia${dias > 1 ? 's' : ''}';
    if (dias > 0) return horas > 0 ? '$rotuloDias e $horas h' : rotuloDias;
    if (horas > 0) return minutos > 0 ? '$horas h $minutos min' : '$horas h';
    return '$minutos min';
  }

  // ─── Texto ───────────────────────────────────────────────────────────────

  static String iniciais(String nome) {
    final partes = nome
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2);
    final s = partes.map((p) => String.fromCharCode(p.runes.first)).join();
    return s.isEmpty ? '?' : s.toUpperCase();
  }

  /// Busca sem acento e sem caixa (web: `semAcento`).
  static String semAcento(String s) {
    const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const para = 'aaaaaeeeeiiiiooooouuuucn';
    final b = StringBuffer();
    for (final r in s.toLowerCase().runes) {
      final ch = String.fromCharCode(r);
      final i = de.indexOf(ch);
      b.write(i >= 0 ? para[i] : ch);
    }
    return b.toString();
  }

  /// Ordem alfabética como o `localeCompare('pt-BR')` do web.
  static int compararNomes(SdrAvailability a, SdrAvailability b) {
    final c = semAcento(a.userName).compareTo(semAcento(b.userName));
    return c != 0 ? c : a.userName.compareTo(b.userName);
  }
}
