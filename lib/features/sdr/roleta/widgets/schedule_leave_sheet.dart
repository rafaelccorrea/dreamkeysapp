import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/theme_helpers.dart';
import '../models/sdr_availability.dart';
import '../models/sdr_roulette_rules.dart';
import '../services/sdr_roulette_service.dart';
import 'roleta_tinta.dart';
import 'sdr_roulette_card.dart';

/// O que a folha fez — a página avisa e recarrega a lista.
enum SdrLeaveSheetResult { scheduled, canceled }

final DateFormat _diaDoCampo = DateFormat('EEE, dd/MM/yyyy', 'pt_BR');
final DateFormat _horaDoCampo = DateFormat('HH:mm', 'pt_BR');

/// "12/10, 18:00" — o mesmo formato curto do cartão.
final DateFormat _dataCurta = DateFormat('dd/MM, HH:mm', 'pt_BR');

/// Folha "Agendar folga" (o modal do web): atalhos de duração e de motivo,
/// duração calculada ao vivo, validação fim > início, Agendar em verde com
/// Voltar (neutro) empilhado abaixo. Havendo folga já marcada, ela aparece
/// no alto do corpo, escrita por extenso, com o "Cancelar esta folga" em
/// vermelho ao lado do que ele apaga — não mais um link perdido no rodapé.
///
/// Teto de altura (88% do que sobra acima do teclado), corpo em
/// Flexible > SingleChildScrollView e o viewInsets do teclado no padding:
/// nada estoura em paisagem nem com o teclado aberto no motivo.
Future<SdrLeaveSheetResult?> showScheduleLeaveSheet(
  BuildContext context, {
  required SdrAvailability sdr,
}) {
  return showModalBottomSheet<SdrLeaveSheetResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _ScheduleLeaveSheet(sdr: sdr),
  );
}

class _ScheduleLeaveSheet extends StatefulWidget {
  final SdrAvailability sdr;

  const _ScheduleLeaveSheet({required this.sdr});

  @override
  State<_ScheduleLeaveSheet> createState() => _ScheduleLeaveSheetState();
}

class _ScheduleLeaveSheetState extends State<_ScheduleLeaveSheet> {
  final SdrRouletteService _service = SdrRouletteService.instance;
  late final TextEditingController _motivo;
  late final bool _temFolgaMarcada;

  DateTime? _inicio;
  DateTime? _fim;
  bool _enviando = false;
  bool _cancelando = false;
  String? _erro;
  bool _erroEhAviso = false;

  bool get _ocupado => _enviando || _cancelando;

  bool get _fimAntesDoInicio {
    final inicio = _inicio;
    final fim = _fim;
    return inicio != null && fim != null && !fim.isAfter(inicio);
  }

  @override
  void initState() {
    super.initState();
    final s = widget.sdr;
    _temFolgaMarcada = SdrRouletteRules.temFolgaPendente(s);
    final inicio = s.scheduledPauseStart;
    final fim = s.scheduledPauseEnd;
    _inicio = inicio == null ? null : SdrRouletteRules.aoMinuto(inicio);
    _fim = fim == null ? null : SdrRouletteRules.aoMinuto(fim);
    _motivo = TextEditingController(text: s.leaveReason ?? '');
  }

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  // ─── Ações ───────────────────────────────────────────────────────────────

  void _mostrarErro(String mensagem, {required bool aviso}) {
    setState(() {
      _erro = mensagem;
      _erroEhAviso = aviso;
    });
  }

  void _aplicarAtalho(SdrLeaveShortcut atalho) {
    if (_ocupado) return;
    final (inicio, fim) = atalho.range(DateTime.now());
    setState(() {
      _inicio = inicio;
      _fim = fim;
      _erro = null;
    });
  }

  void _aplicarMotivo(String motivo) {
    if (_ocupado) return;
    _motivo.value = TextEditingValue(
      text: motivo,
      selection: TextSelection.collapsed(offset: motivo.length),
    );
    setState(() => _erro = null);
  }

  Future<void> _escolher({required bool inicio}) async {
    if (_ocupado) return;
    FocusScope.of(context).unfocus();
    final agora = DateTime.now();
    final atual = inicio ? _inicio : _fim;
    final base = atual ?? (inicio ? agora : (_inicio ?? agora));
    final primeiro = DateTime(agora.year - 1, agora.month, agora.day);
    final ultimo = DateTime(agora.year + 3, agora.month, agora.day);
    final inicial = base.isBefore(primeiro)
        ? primeiro
        : (base.isAfter(ultimo) ? ultimo : base);

    final dia = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: primeiro,
      lastDate: ultimo,
      locale: const Locale('pt', 'BR'),
      helpText: inicio ? 'Sai da roleta' : 'Volta para a roleta',
      builder: _temaDoSeletor,
    );
    if (dia == null || !mounted) return;

    final horaBase = TimeOfDay.fromDateTime(base);
    final hora = await showTimePicker(
      context: context,
      initialTime: horaBase,
      helpText: inicio ? 'Hora da saída' : 'Hora da volta',
      builder: _temaDoSeletor,
    );
    if (!mounted) return;
    final h = hora ?? horaBase;
    final escolhido = DateTime(dia.year, dia.month, dia.day, h.hour, h.minute);
    setState(() {
      if (inicio) {
        _inicio = escolhido;
      } else {
        _fim = escolhido;
      }
      _erro = null;
    });
  }

  Future<void> _agendar() async {
    if (_ocupado) return;
    final inicio = _inicio;
    final fim = _fim;
    if (inicio == null || fim == null) {
      _mostrarErro('Preencha o início e o fim da folga', aviso: true);
      return;
    }
    if (!fim.isAfter(inicio)) {
      _mostrarErro('O fim da folga precisa ser depois do início', aviso: true);
      return;
    }
    final motivo = _motivo.text.trim();
    if (motivo.isEmpty) {
      _mostrarErro('Informe o motivo da folga', aviso: true);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _enviando = true;
      _erro = null;
    });
    final r = await _service.schedulePause(
      widget.sdr.userId,
      start: inicio,
      end: fim,
      reason: motivo,
    );
    if (!mounted) return;
    if (r.success) {
      Navigator.of(context).pop(SdrLeaveSheetResult.scheduled);
      return;
    }
    // A mensagem do back explica a regra (último ativo, permissão, datas).
    final mensagem = r.message ?? 'Erro ao agendar folga';
    setState(() {
      _enviando = false;
      _erro = mensagem;
      _erroEhAviso = SdrRouletteRules.ehRegraDoUltimoAtivo(mensagem);
    });
  }

  Future<void> _cancelarFolga() async {
    if (_ocupado) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _cancelando = true;
      _erro = null;
    });
    final r = await _service.cancelScheduledPause(widget.sdr.userId);
    if (!mounted) return;
    if (r.success) {
      Navigator.of(context).pop(SdrLeaveSheetResult.canceled);
      return;
    }
    setState(() {
      _cancelando = false;
      _erro = r.message ?? 'Erro ao cancelar folga agendada';
      _erroEhAviso = false;
    });
  }

  /// Seletores no âmbar da folga, 24 h, grafite no escuro; Cancelar neutro
  /// (o tema global pinta TextButton de vermelho).
  Widget _temaDoSeletor(BuildContext ctx, Widget? child) {
    final base = Theme.of(ctx);
    final escuro = base.brightness == Brightness.dark;
    final ambar = RoletaTinta.ambar(ctx);
    final painel = RoletaTinta.painel(ctx);
    final secundario = RoletaTinta.textoSecundario(ctx);
    final esquema = base.colorScheme.copyWith(
      primary: ambar,
      onPrimary: ThemeHelpers.onPrimaryColor(ctx),
      primaryContainer: ambar.withValues(alpha: escuro ? 0.22 : 0.14),
      onPrimaryContainer: RoletaTinta.texto(ctx),
      surface: painel,
      surfaceContainerHigh: painel,
      surfaceContainerHighest: RoletaTinta.chapa(ctx),
      surfaceTint: Colors.transparent,
    );
    return MediaQuery(
      data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
      child: Theme(
        data: base.copyWith(
          colorScheme: esquema,
          inputDecorationTheme: base.inputDecorationTheme.copyWith(
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: ambar, width: 2),
            ),
          ),
          datePickerTheme: base.datePickerTheme.copyWith(
            backgroundColor: painel,
            surfaceTintColor: Colors.transparent,
            cancelButtonStyle: TextButton.styleFrom(
              foregroundColor: secundario,
            ),
            confirmButtonStyle: TextButton.styleFrom(foregroundColor: ambar),
          ),
          timePickerTheme: base.timePickerTheme.copyWith(
            backgroundColor: painel,
            cancelButtonStyle: TextButton.styleFrom(
              foregroundColor: secundario,
            ),
            confirmButtonStyle: TextButton.styleFrom(foregroundColor: ambar),
          ),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final teclado = mq.viewInsets.bottom;
    final alturaMaxima = math.max(0.0, (mq.size.height - teclado) * 0.88);
    // Com teclado aberto (ou tela baixa, paisagem) o rodapé desce para o fim
    // da rolagem: fixo, ele espremeria o campo do motivo até sumir. Só o
    // ÚLTIMO filho de cada coluna muda — o campo em edição não é recriado e
    // não perde o foco.
    final rodapeNaRolagem = teclado > 0 || mq.size.height < 560;
    final rodape = _rodape(context);

    return PopScope(
      canPop: !_ocupado,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: teclado),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: alturaMaxima),
          child: Container(
            decoration: BoxDecoration(
              color: RoletaTinta.painel(context),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _cabeca(context),
                Flexible(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _corpo(context),
                        if (rodapeNaRolagem) rodape,
                      ],
                    ),
                  ),
                ),
                if (!rodapeNaRolagem) rodape,
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Pegador + cabeçalho da casa: título à esquerda, fechar à direita.
  Widget _cabeca(BuildContext context) {
    final secundario = RoletaTinta.textoSecundario(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 8, bottom: 8),
            decoration: BoxDecoration(
              color: RoletaTinta.fioForte(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 2, 12, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(LucideIcons.treePalm, size: 17, color: secundario),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Agendar folga',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                              color: RoletaTinta.texto(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Padding(
                      padding: const EdgeInsets.only(left: 25),
                      child: Text(
                        'Sai da roleta no início e volta sozinho no fim',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: secundario,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _BotaoFechar(
                onTap: _ocupado ? null : () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Container(height: 1, color: RoletaTinta.fio(context)),
      ],
    );
  }

  Widget _corpo(BuildContext context) {
    final sdr = widget.sdr;
    final situacao = SdrRouletteRules.situacaoDo(sdr);
    final inicio = _inicio;
    final fim = _fim;
    final duracao = (inicio != null && fim != null)
        ? SdrRouletteRules.duracao(inicio, fim)
        : null;
    final motivoAtual = _motivo.text.trim();
    final secundario = RoletaTinta.textoSecundario(context);
    final fimAntes = _fimAntesDoInicio;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _QuemFolga(sdr: sdr, situacao: situacao),
          if (_temFolgaMarcada) ...[
            const SizedBox(height: 12),
            _FolgaJaMarcada(
              sdr: sdr,
              cancelando: _cancelando,
              onCancelar: _ocupado ? null : _cancelarFolga,
            ),
          ],
          const SizedBox(height: 18),
          const _Rotulo('Duração rápida'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final atalho in SdrRouletteRules.atalhos)
                _Ficha(
                  rotulo: atalho.label,
                  onTap: () => _aplicarAtalho(atalho),
                ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, caixa) {
              final saida = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Rotulo('Sai da roleta'),
                  const SizedBox(height: 8),
                  _CampoDeData(
                    valor: inicio,
                    invalido: false,
                    onTap: () => _escolher(inicio: true),
                  ),
                ],
              );
              final volta = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Rotulo('Volta para a roleta'),
                  const SizedBox(height: 8),
                  _CampoDeData(
                    valor: fim,
                    invalido: fimAntes,
                    onTap: () => _escolher(inicio: false),
                  ),
                ],
              );
              // Lado a lado só com folga de largura (paisagem, tablet); no
              // celular em pé, um embaixo do outro.
              if (caixa.maxWidth >= 520) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: saida),
                    const SizedBox(width: 12),
                    Expanded(child: volta),
                  ],
                );
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [saida, const SizedBox(height: 14), volta],
              );
            },
          ),
          if (fimAntes || duracao != null) ...[
            const SizedBox(height: 8),
            fimAntes
                ? Text(
                    'A volta precisa ser depois da saída.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: RoletaTinta.vermelho(context),
                    ),
                  )
                : Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'Folga de '),
                        TextSpan(
                          text: duracao,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: RoletaTinta.ambar(context),
                          ),
                        ),
                      ],
                    ),
                    style: TextStyle(fontSize: 12, color: secundario),
                  ),
          ],
          const SizedBox(height: 18),
          const _Rotulo('Motivo'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in SdrRouletteRules.motivos)
                _Ficha(
                  rotulo: m,
                  ativa: motivoAtual == m,
                  onTap: () => _aplicarMotivo(m),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _campoDoMotivo(context),
        ],
      ),
    );
  }

  Widget _campoDoMotivo(BuildContext context) {
    final secundario = RoletaTinta.textoSecundario(context);
    final borda = OutlineInputBorder(
      borderRadius: BorderRadius.circular(11),
      borderSide: BorderSide(color: RoletaTinta.fioForte(context)),
    );
    // A coluna do back é varchar(255): o contador aparece perto do limite.
    final perto = _motivo.text.length > 200;
    return TextField(
      controller: _motivo,
      enabled: !_ocupado,
      minLines: 2,
      maxLines: 4,
      maxLength: 255,
      textCapitalization: TextCapitalization.sentences,
      cursorColor: RoletaTinta.ambar(context),
      onChanged: (_) => setState(() => _erro = null),
      style: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
        height: 1.35,
        color: RoletaTinta.texto(context),
      ),
      decoration: InputDecoration(
        hintText: 'Ou escreva o motivo — ex.: férias de 15 dias',
        hintStyle: TextStyle(
          fontSize: 13,
          color: secundario.withValues(alpha: 0.8),
        ),
        filled: true,
        fillColor: RoletaTinta.campo(context),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 11,
        ),
        counterText: perto ? null : '',
        border: borda,
        enabledBorder: borda,
        disabledBorder: borda,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(
            color: secundario.withValues(alpha: 0.7),
            width: 1.4,
          ),
        ),
      ),
    );
  }

  /// Agendar no verde da ação principal, Voltar (neutro) empilhado abaixo.
  /// O erro de qualquer ação (inclusive do cancelar lá do alto) aparece
  /// aqui, junto dos botões.
  Widget _rodape(BuildContext context) {
    final verde = RoletaTinta.verde(context);
    final tinta = RoletaTinta.tintaSobreVerde(context);
    final erro = _erro;
    final corDoErro =
        _erroEhAviso ? RoletaTinta.ambar(context) : RoletaTinta.vermelho(context);
    final seguro = MediaQuery.paddingOf(context).bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(18, 14, 18, 16 + seguro),
      decoration: BoxDecoration(
        color: RoletaTinta.banda(context),
        border: Border(top: BorderSide(color: RoletaTinta.fio(context))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (erro != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    _erroEhAviso
                        ? LucideIcons.triangleAlert
                        : LucideIcons.circleAlert,
                    size: 15,
                    color: corDoErro,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    erro,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                      color: corDoErro,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            height: 46,
            child: FilledButton(
              onPressed: _ocupado ? null : _agendar,
              style: FilledButton.styleFrom(
                backgroundColor: verde,
                foregroundColor: tinta,
                disabledBackgroundColor: verde.withValues(alpha: 0.55),
                disabledForegroundColor: tinta.withValues(alpha: 0.85),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_enviando)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(tinta),
                        ),
                      )
                    else
                      const Icon(LucideIcons.treePalm, size: 17),
                    const SizedBox(width: 8),
                    Text(
                      _enviando ? 'Agendando…' : 'Agendar folga',
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 42,
            child: TextButton(
              onPressed: _ocupado ? null : () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                backgroundColor: RoletaTinta.chapa(context),
                foregroundColor: RoletaTinta.texto(context),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                  side: BorderSide(color: RoletaTinta.fio(context)),
                ),
              ),
              child: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Voltar',
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Quem sai: avatar, nome e a situação de agora, numa banda.
class _QuemFolga extends StatelessWidget {
  final SdrAvailability sdr;
  final SdrSituation situacao;

  const _QuemFolga({required this.sdr, required this.situacao});

  @override
  Widget build(BuildContext context) {
    final banda = RoletaTinta.banda(context);
    final agora = switch (situacao) {
      SdrSituation.roleta => 'Na roleta agora',
      SdrSituation.folga => 'De folga agora',
      SdrSituation.pausado => 'Fora da roleta agora',
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: banda,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: RoletaTinta.fio(context)),
      ),
      child: Row(
        children: [
          SdrRouletteAvatar(
            sdr: sdr,
            size: 40,
            situacao: situacao,
            anel: banda,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sdr.userName.isEmpty ? 'Sem nome' : sdr.userName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: RoletaTinta.texto(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  agora,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: RoletaTinta.daSituacao(context, situacao),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A folga que JÁ está marcada, por extenso (quando sai, quando volta, por
/// quê), com o cancelar vermelho logo abaixo do que ele apaga. Informativo
/// flush: sem caixa, só o traço âmbar de 2px da folga (o mesmo da nota do
/// cartão). Os campos da folha já vêm preenchidos com ela.
class _FolgaJaMarcada extends StatelessWidget {
  final SdrAvailability sdr;
  final bool cancelando;

  /// `null` enquanto a folha está ocupada (agendando ou cancelando).
  final VoidCallback? onCancelar;

  const _FolgaJaMarcada({
    required this.sdr,
    required this.cancelando,
    required this.onCancelar,
  });

  @override
  Widget build(BuildContext context) {
    final ambar = RoletaTinta.ambar(context);
    final vermelho = RoletaTinta.vermelho(context);
    final inicio = sdr.scheduledPauseStart;
    final fim = sdr.scheduledPauseEnd;
    final motivo = sdr.leaveReason;
    final forte = TextStyle(
      fontWeight: FontWeight.w700,
      color: RoletaTinta.texto(context),
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Container(
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: ambar, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1.5),
                child: Icon(LucideIcons.calendarClock, size: 14, color: ambar),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Folga já marcada',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: ambar,
                        ),
                      ),
                      const TextSpan(text: '\nSai '),
                      TextSpan(
                        text: inicio == null ? '—' : _dataCurta.format(inicio),
                        style: forte,
                      ),
                      const TextSpan(text: ' · volta '),
                      TextSpan(
                        text: fim == null ? '—' : _dataCurta.format(fim),
                        style: forte,
                      ),
                      if (motivo != null && motivo.trim().isNotEmpty)
                        TextSpan(text: ' · $motivo'),
                    ],
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: RoletaTinta.textoSecundario(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Destrutivo: vermelho com texto branco, do tamanho do rótulo.
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 38),
            child: FilledButton.icon(
              onPressed: onCancelar,
              icon: cancelando
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(LucideIcons.calendarX2, size: 15),
              label: Text(
                cancelando ? 'Cancelando…' : 'Cancelar esta folga',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
              style: FilledButton.styleFrom(
                backgroundColor: vermelho,
                foregroundColor: Colors.white,
                disabledBackgroundColor: vermelho.withValues(alpha: 0.45),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.85),
                elevation: 0,
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                textStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Rotulo extends StatelessWidget {
  final String texto;

  const _Rotulo(this.texto);

  @override
  Widget build(BuildContext context) {
    return Text(
      texto.toUpperCase(),
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        color: RoletaTinta.textoSecundario(context),
      ),
    );
  }
}

/// Ficha de atalho (duração ou motivo). Ativa = âmbar da folga.
class _Ficha extends StatelessWidget {
  final String rotulo;
  final bool ativa;
  final VoidCallback onTap;

  const _Ficha({required this.rotulo, required this.onTap, this.ativa = false});

  @override
  Widget build(BuildContext context) {
    final ambar = RoletaTinta.ambar(context);
    final forma = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(9),
      side: BorderSide(color: ativa ? ambar : RoletaTinta.fioForte(context)),
    );
    return Semantics(
      button: true,
      selected: ativa,
      child: Material(
        color: ativa
            ? ambar.withValues(alpha: RoletaTinta.escuro(context) ? 0.16 : 0.10)
            : Colors.transparent,
        shape: forma,
        child: InkWell(
          onTap: onTap,
          customBorder: forma,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 34),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                widthFactor: 1,
                child: Text(
                  rotulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: ativa ? FontWeight.w800 : FontWeight.w600,
                    color: ativa ? ambar : RoletaTinta.texto(context),
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

/// Campo de data e hora (o datetime-local do web): um toque abre o dia e
/// depois a hora.
class _CampoDeData extends StatelessWidget {
  final DateTime? valor;
  final bool invalido;
  final VoidCallback onTap;

  const _CampoDeData({
    required this.valor,
    required this.invalido,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final secundario = RoletaTinta.textoSecundario(context);
    final texto = RoletaTinta.texto(context);
    final v = valor;
    final raio = BorderRadius.circular(12);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: raio,
        child: Ink(
          decoration: BoxDecoration(
            color: RoletaTinta.campo(context),
            borderRadius: raio,
            border: Border.all(
              color: invalido
                  ? RoletaTinta.vermelho(context)
                  : RoletaTinta.fioForte(context),
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 46),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(LucideIcons.calendarDays, size: 16, color: secundario),
                  const SizedBox(width: 10),
                  Expanded(
                    child: v == null
                        ? Text(
                            'Escolher data e hora',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13.5, color: secundario),
                          )
                        // Encolhe em vez de cortar: com fonte grande em
                        // 320dp as reticências comeriam a hora.
                        : FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: _diaDoCampo.format(v)),
                                TextSpan(
                                  text: '  ·  ',
                                  style: TextStyle(
                                    color: secundario,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                TextSpan(text: _horaDoCampo.format(v)),
                              ],
                            ),
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: texto,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                  ),
                  const SizedBox(width: 6),
                  Icon(LucideIcons.chevronDown, size: 16, color: secundario),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fechar 30px com fio — ferramenta do cabeçalho da casa.
class _BotaoFechar extends StatelessWidget {
  final VoidCallback? onTap;

  const _BotaoFechar({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final forma = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(9),
      side: BorderSide(color: RoletaTinta.fio(context)),
    );
    return Tooltip(
      message: 'Fechar',
      child: Material(
        color: Colors.transparent,
        shape: forma,
        child: InkWell(
          onTap: onTap,
          customBorder: forma,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(
              LucideIcons.x,
              size: 17,
              color: RoletaTinta.textoSecundario(context),
            ),
          ),
        ),
      ),
    );
  }
}
