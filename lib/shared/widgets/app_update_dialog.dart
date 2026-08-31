import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/theme_helpers.dart';
import '../services/app_update_service.dart';

/// Tom da atualização: VIOLETA.
///
/// As outras quatro cores do app já têm dono — verde confirma, vermelho é erro
/// ou destruição, âmbar é atenção, azul é informação. Uma versão nova não é
/// nada disso: é novidade. O vermelho da marca, que estava aqui antes, fazia
/// um aviso de lançamento parecer alarme.
const Color _kNovoLight = Color(0xFF7C3AED);
const Color _kNovoDark = Color(0xFFA78BFA);

Color _tomNovo(bool isDark) => isDark ? _kNovoDark : _kNovoLight;

/// Checa atualização e, se houver, mostra um aviso dispensável ("soft").
Future<void> maybePromptAppUpdate(
  BuildContext context, {
  bool force = false,
}) async {
  final info = await AppUpdateService.instance.checkForUpdate(force: force);
  if (info == null || !context.mounted) return;
  await showAppUpdateDialog(context, info);
}

/// URL pública da política de privacidade (mesma do web / App Store Connect).
const String kPrivacyPolicyUrl =
    'https://intellisysbr.com/sistema/politica-de-privacidade';

Future<bool> openPrivacyPolicyUrl() async {
  final uri = Uri.tryParse(kPrivacyPolicyUrl);
  if (uri == null) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Abre a página do app na loja da plataforma.
Future<bool> openAppStoreUpdateUrl(String url) async {
  if (url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> showAppUpdateDialog(
  BuildContext context,
  AppUpdateInfo info,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AppUpdateSheet(info: info),
  );
}

/// Folha de atualização disponível.
///
/// A anatomia é a da casa (pegador 42×4, sobrancelha, divisor em gradiente,
/// rodapé), mas o miolo é próprio: o herói aqui é a DISTÂNCIA entre a versão
/// que a pessoa tem e a que existe. Números soltos não dizem nada; o salto,
/// sim.
class _AppUpdateSheet extends StatefulWidget {
  final AppUpdateInfo info;
  const _AppUpdateSheet({required this.info});

  @override
  State<_AppUpdateSheet> createState() => _AppUpdateSheetState();
}

class _AppUpdateSheetState extends State<_AppUpdateSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _viagem;

  @override
  void initState() {
    super.initState();
    // A partícula percorre o trilho e some em fade no fim — o ciclo recomeça
    // do zero já invisível, então nunca há reset seco.
    _viagem = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _viagem.dispose();
    super.dispose();
  }

  IconData get _iconeLoja => widget.info.store == AppStoreKind.appStore
      ? Icons.apple
      : Icons.storefront_rounded;

  /// O tom do aviso sobe com o atraso: uma build atrás é convite, três versões
  /// atrás é cobrança. Continua sem vermelho — atraso não é erro do usuário.
  String get _frase {
    final atras = widget.info.versionsBehind;
    final loja = widget.info.store.label;
    if (widget.info.saltoDeMajor) {
      return 'Esta é uma virada de versão, com mudanças grandes. Atualize pela '
          '$loja para continuar acompanhando o sistema.';
    }
    if (atras >= 3) {
      return 'Você está $atras versões atrás. Atualize pela $loja para voltar '
          'a receber correções e novidades.';
    }
    if (atras >= 1) {
      return 'Uma versão nova já está na $loja com melhorias e correções.';
    }
    return 'Há uma build mais recente na $loja com correções desta mesma '
        'versão.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    final tom = _tomNovo(isDark);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
      child: Container(
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pegador 42×4 — anatomia da casa.
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 10),
                child: Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: ThemeHelpers.borderColor(
                        context,
                      ).withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 8, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        color: tom.withValues(alpha: isDark ? 0.20 : 0.12),
                      ),
                      child: Icon(LucideIcons.sparkles, color: tom, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ATUALIZAÇÃO',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4,
                              color: tom,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Versão ${widget.info.latestVersion} disponível',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.2,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(LucideIcons.x, size: 18, color: secondary),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Fechar',
                    ),
                  ],
                ),
              ),
              // Divisor em gradiente na cor da ação.
              Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      tom.withValues(alpha: 0.30),
                      ThemeHelpers.borderLightColor(
                        context,
                      ).withValues(alpha: 0.25),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SaltoDeVersao(
                        atual: widget.info.currentLabel,
                        nova: widget.info.latestLabel,
                        tom: tom,
                        progresso: _viagem,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        _frase,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: secondary,
                          height: 1.5,
                        ),
                      ),
                      if (widget.info.notes.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Icon(
                              LucideIcons.listChecks,
                              size: 13,
                              color: secondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'O QUE MUDA',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.4,
                                color: secondary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Container(
                                height: 1,
                                color: secondary.withValues(alpha: 0.18),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        for (final nota in widget.info.notes)
                          _LinhaNota(texto: nota, tom: tom),
                      ],
                      const SizedBox(height: 16),
                      // De ONDE vem a atualização. Dizer "App Store" para quem
                      // está no Android é o tipo de detalhe que derruba a
                      // confiança na mensagem inteira.
                      Container(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: ThemeHelpers.borderColor(
                              context,
                            ).withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(_iconeLoja, size: 16, color: secondary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Baixar pela ${widget.info.store.label}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: textColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Icon(
                              LucideIcons.externalLink,
                              size: 14,
                              color: secondary,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: ThemeHelpers.borderColor(
                        context,
                      ).withValues(alpha: 0.45),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          // O tema global pinta TextButton com o vermelho da
                          // marca: sem isto o toque em "Agora não" acende
                          // vermelho, como se adiar fosse destrutivo.
                          foregroundColor: secondary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Agora não',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: tom,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await openAppStoreUpdateUrl(widget.info.updateUrl);
                        },
                        icon: const Icon(
                          LucideIcons.arrowUpToLine,
                          size: 17,
                        ),
                        label: const FittedBox(
                          child: Text(
                            'Atualizar agora',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// O salto entre a versão instalada e a publicada.
///
/// Duas pastilhas ligadas por um trilho: a de trás em ardósia (o que você tem),
/// a da frente na cor da novidade (o que existe). Uma partícula percorre o
/// trilho em laço e desaparece em fade antes de recomeçar — a leitura é
/// "daqui para lá", não dois números soltos lado a lado.
class _SaltoDeVersao extends StatelessWidget {
  final String atual;
  final String nova;
  final Color tom;
  final Animation<double> progresso;

  const _SaltoDeVersao({
    required this.atual,
    required this.nova,
    required this.tom,
    required this.progresso,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: _PastilhaVersao(
            rotulo: 'VOCÊ ESTÁ NA',
            valor: atual,
            cor: secondary,
            preenchida: false,
          ),
        ),
        SizedBox(
          width: 46,
          height: 34,
          child: AnimatedBuilder(
            animation: progresso,
            builder: (context, _) => CustomPaint(
              painter: _TrilhoPainter(
                t: progresso.value,
                cor: tom,
                trilho: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.08),
              ),
            ),
          ),
        ),
        Expanded(
          child: _PastilhaVersao(
            rotulo: 'DISPONÍVEL',
            valor: nova,
            cor: tom,
            preenchida: true,
          ),
        ),
      ],
    );
  }
}

class _PastilhaVersao extends StatelessWidget {
  final String rotulo;
  final String valor;
  final Color cor;
  final bool preenchida;

  const _PastilhaVersao({
    required this.rotulo,
    required this.valor,
    required this.cor,
    required this.preenchida,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: preenchida
            ? cor.withValues(alpha: isDark ? 0.16 : 0.09)
            : (isDark
                  ? Colors.white.withValues(alpha: 0.035)
                  : Colors.black.withValues(alpha: 0.025)),
        border: Border.all(
          color: preenchida
              ? cor.withValues(alpha: isDark ? 0.42 : 0.30)
              : ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
          width: preenchida ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            rotulo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: preenchida
                  ? cor
                  : ThemeHelpers.textSecondaryColor(context),
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valor,
              maxLines: 1,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: preenchida
                    ? ThemeHelpers.textColor(context)
                    : ThemeHelpers.textSecondaryColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Trilho com a partícula que viaja da versão antiga para a nova.
///
/// A opacidade cai nos últimos 25% do percurso: quando o laço reinicia, a
/// partícula já está invisível. É o que evita o "pulo" de volta ao início.
class _TrilhoPainter extends CustomPainter {
  final double t;
  final Color cor;
  final Color trilho;

  _TrilhoPainter({required this.t, required this.cor, required this.trilho});

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    const margem = 4.0;
    final x0 = margem;
    final x1 = size.width - margem;

    final linha = Paint()
      ..color = trilho
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(x0, y), Offset(x1, y), linha);

    // Ponta de seta discreta encostada na versão nova.
    final seta = Paint()
      ..color = cor.withValues(alpha: 0.55)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(x1 - 4.5, y - 3.5), Offset(x1, y), seta);
    canvas.drawLine(Offset(x1 - 4.5, y + 3.5), Offset(x1, y), seta);

    // Partícula: percorre o trilho e some em fade no último quarto.
    final avanco = Curves.easeInOut.transform(t);
    final x = x0 + (x1 - x0) * avanco;
    final opacidade = t < 0.75 ? 1.0 : (1 - (t - 0.75) / 0.25);
    final ponto = Paint()..color = cor.withValues(alpha: opacidade.clamp(0, 1));
    canvas.drawCircle(Offset(x, y), 2.6, ponto);

    // Rastro curto atrás da partícula — dá direção sem virar enfeite.
    final rastro = Paint()
      ..shader = LinearGradient(
        colors: [
          cor.withValues(alpha: 0.0),
          cor.withValues(alpha: 0.35 * opacidade.clamp(0, 1)),
        ],
      ).createShader(Rect.fromLTRB(x - 14, y - 2, x, y + 2))
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset((x - 14).clamp(x0, x1), y), Offset(x, y), rastro);
  }

  @override
  bool shouldRepaint(_TrilhoPainter old) =>
      old.t != t || old.cor != cor || old.trilho != trilho;
}

/// Uma linha de "o que muda", quando a fonte informa as notas.
class _LinhaNota extends StatelessWidget {
  final String texto;
  final Color tom;
  const _LinhaNota({required this.texto, required this.tom});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(shape: BoxShape.circle, color: tom),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textColor(context),
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
