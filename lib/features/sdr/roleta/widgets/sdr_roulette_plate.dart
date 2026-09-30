import 'package:flutter/material.dart';

import '../models/sdr_availability.dart';
import 'roleta_tinta.dart';
import 'sdr_roulette_card.dart';

/// Placa de instrumento, em banda: quantos recebem agora (número-manchete na
/// cor do significado), quem são (pilha de avatares), a composição da equipe
/// (barra fina verde/âmbar/ardósia) e as leituras flush — antes de qualquer
/// lista.
class SdrRoulettePlate extends StatelessWidget {
  final int naRoleta;
  final int deFolga;
  final int pausados;

  /// Folgas marcadas para o futuro (o SDR ainda recebe até lá).
  final int marcadas;
  final int deLocacao;

  /// Tolerância do web: sem a marcação no back, a leitura de locação some.
  final bool mostrarLocacao;

  /// Quem recebe agora, na ordem que o back devolveu (como a pilha do web).
  final List<SdrAvailability> quemRecebe;

  const SdrRoulettePlate({
    super.key,
    required this.naRoleta,
    required this.deFolga,
    required this.pausados,
    required this.marcadas,
    required this.deLocacao,
    required this.mostrarLocacao,
    required this.quemRecebe,
  });

  @override
  Widget build(BuildContext context) {
    final verde = RoletaTinta.verde(context);
    final ambar = RoletaTinta.ambar(context);
    final secundario = RoletaTinta.textoSecundario(context);
    // Tela estreita: menos rostos na pilha para a manchete respirar.
    final maxNaPilha = MediaQuery.sizeOf(context).width < 360 ? 3 : 5;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: RoletaTinta.banda(context),
        border: Border(
          top: BorderSide(color: RoletaTinta.fio(context)),
          bottom: BorderSide(color: RoletaTinta.fio(context)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Fonte do sistema muito grande: a manchete encolhe em vez de
              // empurrar a pilha para fora da tela.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '$naRoleta',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                      letterSpacing: -1.0,
                      color: verde,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      naRoleta == 1 ? 'SDR recebendo' : 'SDRs recebendo',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        color: RoletaTinta.texto(context),
                      ),
                    ),
                    Text(
                      'agora, pelo rodízio',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                        color: secundario,
                      ),
                    ),
                  ],
                ),
              ),
              if (quemRecebe.isNotEmpty) ...[
                const SizedBox(width: 8),
                _Pilha(sdrs: quemRecebe, maximo: maxNaPilha),
              ],
            ],
          ),
          const SizedBox(height: 14),
          _Composicao(roleta: naRoleta, folga: deFolga, pausado: pausados),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _Leitura(n: naRoleta, rotulo: 'na roleta', cor: verde),
              _Leitura(
                n: deFolga,
                rotulo: 'de folga',
                cor: ambar,
                extra: marcadas > 0
                    ? ' · $marcadas marcada${marcadas > 1 ? 's' : ''}'
                    : null,
                corExtra: ambar,
              ),
              _Leitura(
                n: pausados,
                rotulo: pausados == 1 ? 'pausado' : 'pausados',
                cor: RoletaTinta.ardosia(context),
              ),
              if (mostrarLocacao && deLocacao > 0)
                _Leitura(
                  n: deLocacao,
                  rotulo: 'de locação',
                  cor: RoletaTinta.azul(context),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Pilha de avatares de quem recebe: 8px de sobreposição e anel na cor da
/// banda; o excedente vira "+N".
class _Pilha extends StatelessWidget {
  final List<SdrAvailability> sdrs;
  final int maximo;

  const _Pilha({required this.sdrs, required this.maximo});

  static const double _avatar = 30;
  static const double _anel = 2;
  static const double _sobreposicao = 8;

  @override
  Widget build(BuildContext context) {
    final banda = RoletaTinta.banda(context);
    final visiveis = sdrs.take(maximo).toList();
    final resto = sdrs.length - visiveis.length;
    const externo = _avatar + _anel * 2;
    const encaixe = (externo - _sobreposicao) / externo;

    Widget comAnel(Widget filho) {
      return Container(
        padding: const EdgeInsets.all(_anel),
        decoration: BoxDecoration(
          color: banda,
          borderRadius: BorderRadius.circular(999),
        ),
        child: filho,
      );
    }

    return Semantics(
      label: 'Na roleta: ${sdrs.map((s) => s.displayName).join(', ')}',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < visiveis.length; i++)
              Align(
                alignment: Alignment.centerLeft,
                widthFactor:
                    (i == visiveis.length - 1 && resto == 0) ? 1.0 : encaixe,
                child: comAnel(
                  SdrRouletteAvatar(sdr: visiveis[i], size: _avatar),
                ),
              ),
            if (resto > 0)
              comAnel(
                Container(
                  height: _avatar,
                  constraints: const BoxConstraints(
                    minWidth: _avatar,
                    maxWidth: 46,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: RoletaTinta.chapa(context),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  // Center com widthFactor: a ficha abraça o texto (mín. 30,
                  // teto 46) e o FittedBox só encolhe com fonte gigante.
                  child: Center(
                    widthFactor: 1,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '+$resto',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: RoletaTinta.texto(context),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Barra de composição da equipe: verde (na roleta), âmbar (de folga) e
/// ardósia (pausados), proporcional, com 2px de respiro entre as faixas.
class _Composicao extends StatelessWidget {
  final int roleta;
  final int folga;
  final int pausado;

  const _Composicao({
    required this.roleta,
    required this.folga,
    required this.pausado,
  });

  @override
  Widget build(BuildContext context) {
    final faixas = <(int, Color)>[
      (roleta, RoletaTinta.verde(context)),
      (folga, RoletaTinta.ambar(context)),
      (pausado, RoletaTinta.ardosiaBarra(context)),
    ].where((f) => f.$1 > 0).toList();

    final filhos = <Widget>[];
    for (var i = 0; i < faixas.length; i++) {
      if (i > 0) filhos.add(const SizedBox(width: 2));
      filhos.add(
        Expanded(
          flex: faixas[i].$1,
          child: ColoredBox(color: faixas[i].$2),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 6,
        color: RoletaTinta.poco(context),
        child: filhos.isEmpty
            ? null
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: filhos,
              ),
      ),
    );
  }
}

/// Leitura flush: número forte na cor do significado + rótulo apagado.
class _Leitura extends StatelessWidget {
  final int n;
  final String rotulo;
  final Color cor;
  final String? extra;
  final Color? corExtra;

  const _Leitura({
    required this.n,
    required this.rotulo,
    required this.cor,
    this.extra,
    this.corExtra,
  });

  @override
  Widget build(BuildContext context) {
    final complemento = extra;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$n',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: cor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          TextSpan(text: ' $rotulo'),
          if (complemento != null)
            TextSpan(text: complemento, style: TextStyle(color: corExtra)),
        ],
      ),
      style: TextStyle(
        fontSize: 12,
        height: 1.3,
        color: RoletaTinta.textoSecundario(context),
      ),
    );
  }
}
