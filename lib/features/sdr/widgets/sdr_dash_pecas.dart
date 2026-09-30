import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import 'sdr_tinta_legivel.dart';

// Peças visuais do Dash SDR (redesenho de 30/09/2026). Tudo por token; os
// números e as contas moram na página — aqui só o desenho.

final NumberFormat _inteiro = NumberFormat.decimalPattern('pt_BR');

/// Número inteiro em pt-BR ("1.284").
String sdrInt(num v) => _inteiro.format(v);

/// Percentual com uma casa e vírgula ("22,4%") — o `fmtPct` do web.
String sdrPct(double v) {
  if (!v.isFinite) return '0%';
  return '${v.toStringAsFixed(1).replaceAll('.', ',')}%';
}

/// Minutos em leitura humana ("12 min", "1,5 h") — o
/// `fmtSdrWhatsappLatencyMinutes` do web. Nulo quando não há amostra.
String? sdrMinutos(double? minutos) {
  if (minutos == null || !minutos.isFinite) return null;
  if (minutos < 60) return '${minutos.toStringAsFixed(0)} min';
  return '${(minutos / 60).toStringAsFixed(1).replaceAll('.', ',')} h';
}

const List<String> _meses = [
  'jan', 'fev', 'mar', 'abr', 'mai', 'jun', //
  'jul', 'ago', 'set', 'out', 'nov', 'dez',
];

/// "1 set" — sem o ponto da abreviação (o mesmo carimbo das outras telas).
String sdrDiaMes(DateTime d) => '${d.day} ${_meses[d.month - 1]}';

/// Papéis de cor da tela. O eixo (identidade do Dash SDR) é o petróleo
/// (`status.teal`): entradas, período, gente nova. Os sinais têm cor fixa:
/// âmbar = em qualificação / atenção, verde = transferido / bom, vermelho =
/// perdido / crítico. Leitura não é status: marca neutra.
abstract final class SdrTom {
  static bool _escuro(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark;

  static Color eixo(BuildContext c) =>
      _escuro(c) ? AppColors.status.tealDarkMode : AppColors.status.teal;

  static Color qualificacao(BuildContext c) => _escuro(c)
      ? AppColors.status.warningDarkMode
      : AppColors.message.warningText;

  static Color transferido(BuildContext c) =>
      _escuro(c) ? AppColors.status.greenDarkMode : AppColors.status.green;

  static Color perdido(BuildContext c) =>
      _escuro(c) ? AppColors.status.errorDarkMode : AppColors.status.error;

  /// Tinta de TEXTO e ícone pequeno a partir de um tom (≥ 4,5:1 no claro).
  static Color texto(BuildContext c, Color tom) => sdrTintaLegivel(c, tom);

  /// Trilho vazio das barras e fio das separações.
  static Color trilho(BuildContext c) => ThemeHelpers.borderLightColor(c);
}

/// Semáforo dos sinais de saúde do funil (mesmos cortes do web).
enum SdrSinal {
  bom('bom', LucideIcons.circleCheck),
  atencao('atenção', LucideIcons.triangleAlert),
  critico('crítico', LucideIcons.octagonAlert);

  const SdrSinal(this.palavra, this.icone);

  final String palavra;
  final IconData icone;

  Color tom(BuildContext c) => switch (this) {
        SdrSinal.bom => SdrTom.transferido(c),
        SdrSinal.atencao => SdrTom.qualificacao(c),
        SdrSinal.critico => SdrTom.perdido(c),
      };
}

/// Taxa de perda: crítico a partir de 30%, atenção a partir de 15%.
SdrSinal sdrSinalPerda(double pct) => pct >= 30
    ? SdrSinal.critico
    : pct >= 15
        ? SdrSinal.atencao
        : SdrSinal.bom;

/// Conversão: bom a partir de 30%, atenção a partir de 15%, crítico abaixo.
SdrSinal sdrSinalConversao(double pct) => pct >= 30
    ? SdrSinal.bom
    : pct >= 15
        ? SdrSinal.atencao
        : SdrSinal.critico;

/// Fio de separação (hairline) na largura do conteúdo.
class SdrFio extends StatelessWidget {
  const SdrFio({super.key, this.recuo = 0});

  /// Recuo à esquerda (linhas que começam depois de um índice ou ramal).
  final double recuo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: recuo),
      child: Container(height: 1, color: SdrTom.trilho(context)),
    );
  }
}

/// Cabeçalho de seção: chapa tonal com o ícone + título + dica. O título
/// quebra linha em vez de truncar; a dica tem até 3 linhas.
class SdrSecaoCabecalho extends StatelessWidget {
  const SdrSecaoCabecalho({
    super.key,
    required this.icone,
    required this.titulo,
    this.dica,
    this.trailing,
  });

  final IconData icone;
  final String titulo;
  final String? dica;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final eixo = SdrTom.eixo(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            color: eixo.withValues(alpha: isDark ? 0.18 : 0.10),
          ),
          child: Icon(icone, size: 16, color: SdrTom.texto(context, eixo)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  titulo,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                    letterSpacing: -0.3,
                    height: 1.2,
                  ),
                ),
              ),
              if (dica != null && dica!.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  dica!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Padding(padding: const EdgeInsets.only(top: 6), child: trailing!),
        ],
      ],
    );
  }
}

/// Trilho de participação: fundo neutro + parte cheia na cor do sinal.
/// Sem LayoutBuilder — pode morar dentro de `IntrinsicHeight`.
class SdrTrilho extends StatelessWidget {
  const SdrTrilho({
    super.key,
    required this.fracao,
    required this.cor,
    this.altura = 6,
  });

  /// 0–1 (valores fora da faixa são cortados).
  final double fracao;
  final Color cor;
  final double altura;

  @override
  Widget build(BuildContext context) {
    final f = fracao.isFinite ? fracao.clamp(0.0, 1.0) : 0.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: altura,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: SdrTom.trilho(context)),
            if (f > 0)
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                // Um fiapo visível mesmo com participação ínfima.
                widthFactor: math.max(f, 0.012),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: cor,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Minigráfico de linha (tendência) com área suave e o último ponto marcado.
class SdrMiniGrafico extends StatelessWidget {
  const SdrMiniGrafico({
    super.key,
    required this.valores,
    required this.cor,
    this.altura = 28,
  });

  final List<num> valores;
  final Color cor;
  final double altura;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: altura,
      child: CustomPaint(
        size: Size.infinite,
        painter: _MiniGraficoPainter(
          valores: valores.map((v) => v.toDouble()).toList(growable: false),
          cor: cor,
        ),
      ),
    );
  }
}

class _MiniGraficoPainter extends CustomPainter {
  _MiniGraficoPainter({required this.valores, required this.cor});

  final List<double> valores;
  final Color cor;

  @override
  void paint(Canvas canvas, Size size) {
    if (valores.length < 2 || size.width <= 0 || size.height <= 0) return;
    final maior = valores.reduce(math.max);
    final menor = valores.reduce(math.min);
    final faixa = (maior - menor).abs() < 0.0001 ? 1.0 : maior - menor;
    const margem = 3.0;
    final h = size.height - margem * 2;
    final passo = size.width / (valores.length - 1);
    Offset ponto(int i) => Offset(
          i * passo,
          margem + h - ((valores[i] - menor) / faixa) * h,
        );

    final linha = Path()..moveTo(ponto(0).dx, ponto(0).dy);
    for (var i = 1; i < valores.length; i++) {
      final p = ponto(i);
      linha.lineTo(p.dx, p.dy);
    }
    final area = Path.from(linha)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = cor.withValues(alpha: 0.12));
    canvas.drawPath(
      linha,
      Paint()
        ..color = cor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(ponto(valores.length - 1), 2.8, Paint()..color = cor);
  }

  @override
  bool shouldRepaint(covariant _MiniGraficoPainter old) =>
      old.cor != cor || old.valores.length != valores.length ||
      !_iguais(old.valores, valores);

  static bool _iguais(List<double> a, List<double> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Hachura diagonal — a marca do ECO (duplicado não ganha cor: não é gente).
class SdrHachuraPainter extends CustomPainter {
  SdrHachuraPainter({required this.traco, required this.fundo});

  final Color traco;
  final Color fundo;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = fundo);
    final p = Paint()
      ..color = traco
      ..strokeWidth = 1.2;
    const vao = 5.0;
    for (var x = -size.height; x < size.width; x += vao) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        p,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SdrHachuraPainter old) =>
      old.traco != traco || old.fundo != fundo;
}

/// Amostra da hachura (legenda e placar da peneira).
class SdrHachura extends StatelessWidget {
  const SdrHachura({super.key, this.largura, this.altura = 10, this.raio = 3});

  final double? largura;
  final double altura;
  final double raio;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(raio),
      child: SizedBox(
        width: largura,
        height: altura,
        child: CustomPaint(
          painter: SdrHachuraPainter(
            traco: ThemeHelpers.textSecondaryColor(context)
                .withValues(alpha: 0.55),
            fundo: SdrTom.trilho(context),
          ),
        ),
      ),
    );
  }
}

/// Barra da peneira: gente nova (sólido no eixo) × eco (hachura neutra).
class SdrBarraPeneira extends StatelessWidget {
  const SdrBarraPeneira({
    super.key,
    required this.novos,
    required this.eco,
    this.altura = 12,
  });

  final int novos;
  final int eco;
  final double altura;

  @override
  Widget build(BuildContext context) {
    final total = novos + eco;
    if (total <= 0) {
      return SdrTrilho(fracao: 0, cor: SdrTom.eixo(context), altura: altura);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: altura,
        child: Row(
          children: [
            if (novos > 0)
              Expanded(
                flex: novos,
                child: ColoredBox(color: SdrTom.eixo(context)),
              ),
            if (novos > 0 && eco > 0) const SizedBox(width: 2),
            if (eco > 0)
              Expanded(
                flex: eco,
                child: SdrHachura(altura: altura, raio: 0),
              ),
          ],
        ),
      ),
    );
  }
}

/// Régua dos últimos 30 dias com o recorte pintado (o "Período" do web).
/// Cada fatia é um dia; hoje é a última à direita.
class SdrReguaPeriodo extends StatelessWidget {
  const SdrReguaPeriodo({
    super.key,
    required this.inicio,
    required this.fim,
    this.altura = 8,
  });

  final DateTime inicio;
  final DateTime fim;
  final double altura;

  static const int dias = 30;

  @override
  Widget build(BuildContext context) {
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final eixo = SdrTom.eixo(context);
    final trilho = SdrTom.trilho(context);
    final ini = DateTime(inicio.year, inicio.month, inicio.day);
    final fi = DateTime(fim.year, fim.month, fim.day);
    bool dentro(int i) {
      final dia = hoje.subtract(Duration(days: dias - 1 - i));
      return !dia.isBefore(ini) && !dia.isAfter(fi);
    }

    return SizedBox(
      height: altura,
      child: Row(
        children: [
          for (var i = 0; i < dias; i++) ...[
            if (i > 0) const SizedBox(width: 1.5),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: dentro(i) ? eixo : trilho,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Pontilhado de chão — pé das leituras que não têm série para desenhar.
class SdrPontilhado extends StatelessWidget {
  const SdrPontilhado({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 5,
      child: CustomPaint(
        size: Size.infinite,
        painter: _PontilhadoPainter(cor: SdrTom.trilho(context)),
      ),
    );
  }
}

class _PontilhadoPainter extends CustomPainter {
  _PontilhadoPainter({required this.cor});

  final Color cor;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = cor;
    final y = size.height / 2;
    for (var x = 1.5; x < size.width; x += 6) {
      canvas.drawCircle(Offset(x, y), 1.5, p);
    }
  }

  @override
  bool shouldRepaint(covariant _PontilhadoPainter old) => old.cor != cor;
}

/// Uma camada do funil de conversão: trapézio centrado cujo topo e base são
/// frações da largura. Empilhadas, as camadas desenham o funil.
class SdrCamadaFunilPainter extends CustomPainter {
  SdrCamadaFunilPainter({
    required this.topo,
    required this.base,
    required this.cor,
  });

  final double topo;
  final double base;
  final Color cor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width;
    final t = topo.clamp(0.0, 1.0) * w;
    final b = base.clamp(0.0, 1.0) * w;
    final path = Path()
      ..moveTo((w - t) / 2, 0)
      ..lineTo((w + t) / 2, 0)
      ..lineTo((w + b) / 2, size.height)
      ..lineTo((w - b) / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = cor);
  }

  @override
  bool shouldRepaint(covariant SdrCamadaFunilPainter old) =>
      old.topo != topo || old.base != base || old.cor != cor;
}

/// Ramal da árvore do funil: o fio que desce da base (entradas) e entra em
/// cada estação. [ultimo] fecha em "└"; os outros seguem em "├".
class SdrRamalPainter extends CustomPainter {
  SdrRamalPainter({required this.cor, required this.ultimo, this.meio = 22});

  final Color cor;
  final bool ultimo;

  /// Altura (a partir do topo) onde o ramal entra na estação.
  final double meio;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = cor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const x = 6.0;
    final y = math.min(meio, size.height);
    canvas.drawLine(Offset(x, 0), Offset(x, ultimo ? y : size.height), p);
    canvas.drawLine(Offset(x, y), Offset(size.width - 2, y), p);
  }

  @override
  bool shouldRepaint(covariant SdrRamalPainter old) =>
      old.cor != cor || old.ultimo != ultimo || old.meio != meio;
}
