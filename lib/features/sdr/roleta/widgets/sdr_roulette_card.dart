import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/sdr_availability.dart';
import '../models/sdr_roulette_rules.dart';
import 'roleta_tinta.dart';

/// "12/10, 18:00" — o `toLocaleString('pt-BR', dia/mês/hora/minuto)` do web.
final DateFormat _dataCurta = DateFormat('dd/MM, HH:mm', 'pt_BR');

String _curta(DateTime? d) => d == null ? '' : _dataCurta.format(d);

/// Avatar de iniciais em chapa NEUTRA (acabou o avatar em 10 cores
/// sorteadas). A cor que existe é a do ponto de situação no canto — e ela
/// quer dizer algo. Com foto, a foto cobre as iniciais (que ficam por baixo
/// enquanto ela carrega ou se ela falhar).
class SdrRouletteAvatar extends StatelessWidget {
  final SdrAvailability sdr;
  final double size;

  /// Ponto de situação no canto (verde/âmbar/ardósia). Sem ele, só o avatar.
  final SdrSituation? situacao;

  /// Cor do anel do ponto — o fundo por trás do avatar.
  final Color? anel;

  const SdrRouletteAvatar({
    super.key,
    required this.sdr,
    required this.size,
    this.situacao,
    this.anel,
  });

  @override
  Widget build(BuildContext context) {
    final url = sdr.userAvatarUrl;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final placa = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: RoletaTinta.chapa(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: EdgeInsets.all(size * 0.14),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                SdrRouletteRules.iniciais(sdr.userName),
                maxLines: 1,
                style: TextStyle(
                  fontSize: size * 0.36,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                  color: RoletaTinta.texto(context),
                ),
              ),
            ),
          ),
          if (url != null)
            Image.network(
              url,
              fit: BoxFit.cover,
              cacheWidth: (size * dpr).round(),
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          // Fio interno: o avatar não se dissolve na chapa do cartão.
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: RoletaTinta.fio(context)),
            ),
          ),
        ],
      ),
    );

    final s = situacao;
    if (s == null) return placa;
    const ponto = 11.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          placa,
          Positioned(
            right: -3,
            bottom: -3,
            child: Container(
              width: ponto + 4,
              height: ponto + 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: RoletaTinta.daSituacao(context, s),
                border: Border.all(
                  color: anel ?? RoletaTinta.painel(context),
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cada SDR é um cartão solto (borda própria, 8px entre eles, padding 12) —
/// no web as linhas coladas por fio foram recusadas ("encavalado", Edson
/// 21/09/2026). No celular as ações secundárias (Só locação e folga) descem
/// para uma linha própria sob o texto, na largura do cartão (passam também
/// por baixo da chave): lado a lado com a chave, o nome não teria espaço em
/// 320dp. A chave fica no alto, alinhada ao avatar, com a legenda do que ela
/// faz agora ("Recebe" / "Não recebe" / "Único ativo") — o gestor não
/// precisa adivinhar o que muda ao tocar.
class SdrRouletteCard extends StatelessWidget {
  final SdrAvailability sdr;

  /// Único SDR ativo: a chave fica travada (tocar explica a regra).
  final bool ultimoAtivo;
  final bool alternando;
  final bool marcandoLocacao;

  /// Tolerância do web: sem `soLocacao` em nenhum item, a marca some.
  final bool marcacaoDisponivel;
  final DateTime agora;
  final VoidCallback onToggle;
  final VoidCallback onScheduleLeave;
  final VoidCallback onToggleLocacao;

  const SdrRouletteCard({
    super.key,
    required this.sdr,
    required this.ultimoAtivo,
    required this.alternando,
    required this.marcandoLocacao,
    required this.marcacaoDisponivel,
    required this.agora,
    required this.onToggle,
    required this.onScheduleLeave,
    required this.onToggleLocacao,
  });

  static String _rotuloDaSituacao(SdrSituation s) {
    switch (s) {
      case SdrSituation.roleta:
        return 'Na roleta';
      case SdrSituation.folga:
        return 'De folga';
      case SdrSituation.pausado:
        return 'Pausado';
    }
  }

  @override
  Widget build(BuildContext context) {
    final situacao = SdrRouletteRules.situacaoDo(sdr);
    final corSituacao = RoletaTinta.daSituacao(context, situacao);
    final marcada = SdrRouletteRules.folgaMarcada(sdr, agora);
    final deLocacao = SdrRouletteRules.ehSdrDeLocacao(sdr);
    final secundario = RoletaTinta.textoSecundario(context);
    final motivoDaPausa = sdr.pauseReason;
    final motivoEmCurso = sdr.pauseReason ?? sdr.scheduledPauseReason;
    final motivoMarcado = sdr.leaveReason;
    final volta = sdr.scheduledPauseEnd ?? sdr.pauseEnd;

    final conversas = sdr.conversationsCount;

    final texto = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          sdr.userName.isEmpty ? 'Sem nome' : sdr.userName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            height: 1.3,
            color: RoletaTinta.texto(context),
          ),
        ),
        const SizedBox(height: 3),
        Wrap(
          spacing: 10,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              _rotuloDaSituacao(situacao),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: corSituacao,
              ),
            ),
            if (sdr.checkInActive)
              Tooltip(
                message: 'Check-in vigente na imobiliária',
                child: _Detalhe(
                  icone: LucideIcons.building2,
                  texto: 'no escritório',
                  cor: secundario,
                ),
              ),
            if (conversas != null)
              _Detalhe(
                icone: LucideIcons.messageCircle,
                texto:
                    conversas == 1 ? '1 conversa' : '$conversas conversas',
                cor: secundario,
              ),
            if (deLocacao)
              _Detalhe(
                icone: LucideIcons.keyRound,
                texto: 'locação',
                cor: RoletaTinta.azul(context),
                forte: true,
              ),
          ],
        ),
        if (situacao == SdrSituation.folga)
          _Nota(
            icone: LucideIcons.treePalm,
            corIcone: corSituacao,
            traco: corSituacao,
            partes: [
              if (volta != null) ...[
                const _Parte('Volta '),
                _Parte(_curta(volta), forte: true),
              ] else
                const _Parte('De folga'),
              if (motivoEmCurso != null) _Parte(' · $motivoEmCurso'),
            ],
          ),
        if (marcada)
          _Nota(
            icone: LucideIcons.calendarClock,
            corIcone: RoletaTinta.ambar(context),
            // Ainda não começou: o traço fica neutro, só o ícone carrega o
            // âmbar.
            traco: RoletaTinta.fioForte(context),
            partes: [
              const _Parte('Folga marcada '),
              _Parte(_curta(sdr.scheduledPauseStart), forte: true),
              const _Parte(' → '),
              _Parte(_curta(sdr.scheduledPauseEnd), forte: true),
              if (motivoMarcado != null) _Parte(' · $motivoMarcado'),
            ],
          ),
        if (situacao == SdrSituation.pausado &&
            motivoDaPausa != null &&
            motivoDaPausa != SdrRouletteRules.pausaManual)
          _Nota(
            icone: LucideIcons.circlePause,
            corIcone: corSituacao,
            traco: corSituacao,
            partes: [_Parte(motivoDaPausa)],
          ),
      ],
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: RoletaTinta.painel(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: RoletaTinta.bordaDoCartao(context)),
        boxShadow: RoletaTinta.sombraDoCartao(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SdrRouletteAvatar(sdr: sdr, size: 38, situacao: situacao),
              const SizedBox(width: 12),
              Expanded(child: texto),
              const SizedBox(width: 8),
              _ChaveDaRoleta(
                ligada: sdr.isActive,
                travada: ultimoAtivo,
                ocupada: alternando,
                onTap: onToggle,
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Ações na largura do cartão, recuadas até o texto (avatar 38 +
          // respiro 12) e passando por baixo da chave. Em tela estreita
          // (< 360dp) o recuo sai para as duas caberem na mesma linha; com
          // fonte grande o Wrap desce a segunda.
          Padding(
            padding: EdgeInsets.only(
              left: MediaQuery.sizeOf(context).width < 360 ? 0 : 50,
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (marcacaoDisponivel)
                  _MarcaLocacao(
                    ligada: deLocacao,
                    ocupada: marcandoLocacao,
                    onTap: onToggleLocacao,
                  ),
                _BotaoFolga(
                  destacado: marcada || situacao == SdrSituation.folga,
                  marcada: marcada,
                  onTap: onScheduleLeave,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Detalhe da linha de meta (check-in, conversas, locação). Dentro do Wrap
/// a largura é frouxa: o Flexible deixa o texto encolher com reticências em
/// vez de estourar a linha.
class _Detalhe extends StatelessWidget {
  final IconData? icone;
  final String texto;
  final Color cor;
  final bool forte;

  const _Detalhe({
    this.icone,
    required this.texto,
    required this.cor,
    this.forte = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icone != null) ...[
          Icon(icone, size: 12, color: cor),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: forte ? FontWeight.w700 : FontWeight.w500,
              color: cor,
            ),
          ),
        ),
      ],
    );
  }
}

class _Parte {
  final String texto;
  final bool forte;

  const _Parte(this.texto, {this.forte = false});
}

/// Nota da situação escrita na linha — sem caixa em volta (informativo é
/// flush); o traço de 2px diz de que situação ela é.
class _Nota extends StatelessWidget {
  final IconData icone;
  final Color corIcone;
  final Color traco;
  final List<_Parte> partes;

  const _Nota({
    required this.icone,
    required this.corIcone,
    required this.traco,
    required this.partes,
  });

  @override
  Widget build(BuildContext context) {
    final forte = TextStyle(
      fontWeight: FontWeight.w700,
      color: RoletaTinta.texto(context),
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.only(left: 9),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: traco, width: 2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1.5),
            child: Icon(icone, size: 13, color: corIcone),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  for (final p in partes)
                    TextSpan(text: p.texto, style: p.forte ? forte : null),
                ],
              ),
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: RoletaTinta.textoSecundario(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

//// Marca "Só locação": desligada = contorno apagado com a chave; ligada =
/// azul cheio com check (o mesmo azul do selo Locação da lista de
/// conversas). O rótulo diz o efeito — "Só locação" —, não só o assunto.
class _MarcaLocacao extends StatelessWidget {
  final bool ligada;
  final bool ocupada;
  final VoidCallback onTap;

  const _MarcaLocacao({
    required this.ligada,
    required this.ocupada,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final azul = RoletaTinta.azul(context);
    final fg = ligada
        ? RoletaTinta.tintaSobreCor(context)
        : RoletaTinta.textoSecundario(context);
    final forma = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: ligada
          ? BorderSide.none
          : BorderSide(color: RoletaTinta.fioForte(context)),
    );
    return Tooltip(
      message: SdrRouletteRules.dicaDaMarcaDeLocacao(ligada),
      child: Semantics(
        button: true,
        toggled: ligada,
        label: 'SDR de locação',
        child: AnimatedOpacity(
          opacity: ocupada ? 0.6 : 1,
          duration: const Duration(milliseconds: 150),
          child: Material(
            color: ligada ? azul : Colors.transparent,
            shape: forma,
            child: InkWell(
              onTap: ocupada ? null : onTap,
              customBorder: forma,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 36),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        ligada ? LucideIcons.check : LucideIcons.keyRound,
                        size: 13,
                        color: fg,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          'Só locação',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight:
                                ligada ? FontWeight.w800 : FontWeight.w600,
                            color: fg,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Folga do SDR: âmbar quando há folga em curso ou marcada.
class _BotaoFolga extends StatelessWidget {
  final bool destacado;
  final bool marcada;
  final VoidCallback onTap;

  const _BotaoFolga({
    required this.destacado,
    required this.marcada,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ambar = RoletaTinta.ambar(context);
    final fg = destacado ? ambar : RoletaTinta.textoSecundario(context);
    final forma = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(
        color: destacado ? ambar : RoletaTinta.fioForte(context),
      ),
    );
    return Tooltip(
      message: marcada ? 'Ver ou cancelar a folga marcada' : 'Agendar folga',
      child: Semantics(
        button: true,
        child: Material(
          color: Colors.transparent,
          shape: forma,
          child: InkWell(
            onTap: onTap,
            customBorder: forma,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      marcada
                          ? LucideIcons.calendarClock
                          : LucideIcons.calendarDays,
                      size: 13,
                      color: fg,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        marcada ? 'Folga marcada' : 'Agendar folga',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight:
                              destacado ? FontWeight.w700 : FontWeight.w600,
                          color: fg,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Chave de verdade: trilho verde ligada, poço com botão ardósia desligada,
/// e a legenda embaixo dizendo o que ela faz AGORA — "Recebe" (verde) /
/// "Não recebe" / "Único ativo" (cadeado). Travada (último ativo) fica
/// esmaecida, mas o toque continua valendo para explicar a regra — como no
/// web. A legenda encolhe (FittedBox) em vez de alargar a coluna da chave.
class _ChaveDaRoleta extends StatelessWidget {
  final bool ligada;
  final bool travada;
  final bool ocupada;
  final VoidCallback onTap;

  const _ChaveDaRoleta({
    required this.ligada,
    required this.travada,
    required this.ocupada,
    required this.onTap,
  });

  static const double _largura = 60;

  @override
  Widget build(BuildContext context) {
    final fioForte = RoletaTinta.fioForte(context);
    final secundario = RoletaTinta.textoSecundario(context);
    final dica = travada
        ? 'A roleta precisa de pelo menos 1 SDR ativo'
        : ligada
            ? 'Tirar da roleta'
            : 'Colocar na roleta';
    final legenda = travada
        ? 'Único ativo'
        : ligada
            ? 'Recebe'
            : 'Não recebe';
    final corDaLegenda =
        ligada && !travada ? RoletaTinta.verde(context) : secundario;
    return Tooltip(
      message: dica,
      child: Semantics(
        label: dica,
        child: SizedBox(
          width: _largura,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AbsorbPointer(
                absorbing: ocupada,
                child: AnimatedOpacity(
                  opacity: ocupada ? 0.6 : (travada ? 0.55 : 1),
                  duration: const Duration(milliseconds: 150),
                  child: Switch.adaptive(
                    value: ligada,
                    onChanged: (_) => onTap(),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    activeThumbColor: Colors.white,
                    activeTrackColor: RoletaTinta.verde(context),
                    inactiveThumbColor: RoletaTinta.ardosia(context),
                    inactiveTrackColor: RoletaTinta.poco(context),
                    trackOutlineColor: WidgetStateProperty.resolveWith<Color?>(
                      (states) => states.contains(WidgetState.selected)
                          ? Colors.transparent
                          : fioForte,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 3),
              ExcludeSemantics(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (travada) ...[
                        Icon(LucideIcons.lock, size: 10, color: corDaLegenda),
                        const SizedBox(width: 3),
                      ],
                      Text(
                        legenda,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                          color: corDaLegenda,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
