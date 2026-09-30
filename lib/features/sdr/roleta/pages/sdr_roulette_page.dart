import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../shared/services/module_access_service.dart';
import '../../../../shared/widgets/app_error_state.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/skeleton_box.dart';
import '../models/sdr_availability.dart';
import '../models/sdr_roulette_rules.dart';
import '../services/sdr_roulette_service.dart';
import '../widgets/roleta_tinta.dart';
import '../widgets/schedule_leave_sheet.dart';
import '../widgets/sdr_roulette_card.dart';
import '../widgets/sdr_roulette_plate.dart';

/// **Roleta de distribuição** — a "Disponibilidade dos SDRs" do WhatsApp do
/// web (`SDRAvailabilityPanel.tsx`, aberto pelo `WhatsAppPage.tsx`), em tela
/// cheia: no celular a lista de até 175 pessoas (União) precisa do espaço.
///
/// Mesmos dados, ações e regras do web: situação de cada SDR (na roleta, de
/// folga, pausado), check-in vigente, ligar/tirar da roleta (sempre com pelo
/// menos 1 ativo), agendar e cancelar folga, marca de SDR de locação (some
/// quando o back não manda `soLocacao`), busca, filtros com contagem e
/// seções com cabeçalho preso. Quem decide é o back: só líder SDR,
/// `whatsapp:manage_config` ou admin — o 403 dele aparece como veio.
class SdrRoulettePage extends StatefulWidget {
  const SdrRoulettePage({super.key});

  /// Gate da entrada, o mesmo do botão "Disponibilidade dos SDRs" do web:
  /// `hasPermission('whatsapp:manage_config')` (master/admin/manager passam
  /// pelo bypass de papel do [ModuleAccessService]).
  /// Igual ao web (`usePermissionsOptimized.hasPermission`): só admin e
  /// master passam sem a permissão; gestor precisa de
  /// `whatsapp:manage_config` de verdade (o `hasPermission` do app libera
  /// gestor em tudo, então o gestor é checado pela lista crua).
  static bool canOpen() {
    const perm = 'whatsapp:manage_config';
    final m = ModuleAccessService.instance;
    if ((m.userRole ?? '').toLowerCase() == 'manager') {
      return m.userPermissionNames.contains(perm);
    }
    return m.hasPermission(perm);
  }

  /// Dica do botão de entrada (título/aria-label no web). O botão é sempre
  /// clicável: com a distribuição automática desligada, a pausa ainda vale
  /// para o sorteio do card na chegada e do lead do site.
  static String hintFor({required bool distributionOff}) {
    return SdrRouletteRules.dicaDaDisponibilidade(
      distribuicaoDesligada: distributionOff,
    );
  }

  @override
  State<SdrRoulettePage> createState() => _SdrRoulettePageState();
}

class _SdrRoulettePageState extends State<SdrRoulettePage> {
  static const double _kPadH = 16;

  /// Respiro final: o botão flutuante do chat (56px a 80px do fundo).
  static const double _kPadBottom = 96;

  final SdrRouletteService _service = SdrRouletteService.instance;
  final TextEditingController _buscaCtrl = TextEditingController();

  List<SdrAvailability> _sdrs = const [];
  bool _carregando = true;
  bool _atualizando = false;
  bool _carregouUmaVez = false;
  String? _erro;
  int _erroStatus = 0;

  String _busca = '';
  SdrRouletteFilter _filtro = SdrRouletteFilter.todos;

  final Set<String> _alternando = <String>{};
  final Set<String> _marcando = <String>{};
  bool _folhaAberta = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  // ─── Dados ───────────────────────────────────────────────────────────────

  /// Primeira carga: esqueleto. Depois: a lista fica na tela e só o ícone de
  /// atualizar gira; falha vira aviso sem apagar o que já se via.
  Future<void> _carregar() async {
    final comLista = _carregouUmaVez;
    if (comLista) {
      if (_atualizando) return;
      setState(() => _atualizando = true);
    } else if (!_carregando || _erro != null) {
      setState(() {
        _carregando = true;
        _erro = null;
        _erroStatus = 0;
      });
    }

    final r = await _service.list();
    if (!mounted) return;

    final dados = r.data;
    setState(() {
      _carregando = false;
      _atualizando = false;
      if (r.success && dados != null) {
        _sdrs = dados;
        _carregouUmaVez = true;
        _erro = null;
        _erroStatus = 0;
      } else if (!comLista) {
        _erro = r.message ?? 'Erro ao carregar disponibilidade dos SDRs';
        _erroStatus = r.statusCode;
      }
    });
    if (comLista && !r.success) {
      _avisar(
        r.message ?? 'Erro ao carregar disponibilidade dos SDRs',
        RoletaTom.erro,
      );
    }
  }

  void _avisar(String texto, RoletaTom tom) {
    if (!mounted) return;
    mostrarAvisoDaRoleta(context, texto, tom);
  }

  void _trocar(String userId, SdrAvailability Function(SdrAvailability) f) {
    _sdrs = [for (final s in _sdrs) s.userId == userId ? f(s) : s];
  }

  /// Liga/tira da roleta. Não deixa pausar o último ativo (a regra também
  /// vale no back, que responde 403 com a explicação).
  Future<void> _alternar(SdrAvailability sdr) async {
    if (_alternando.contains(sdr.userId)) return;
    final ativos = _sdrs.where((s) => s.isActive).length;
    if (sdr.isActive && ativos == 1) {
      _avisar(SdrRouletteRules.ultimoAtivo, RoletaTom.aviso);
      return;
    }
    final ligar = !sdr.isActive;
    setState(() => _alternando.add(sdr.userId));
    final r = await _service.toggle(
      sdr.userId,
      isActive: ligar,
      pauseReason: ligar ? null : SdrRouletteRules.pausaManual,
    );
    if (!mounted) return;
    setState(() {
      _alternando.remove(sdr.userId);
      if (r.success) {
        _trocar(
          sdr.userId,
          (s) => s.withManualAvailability(
            ligar,
            pauseReason: SdrRouletteRules.pausaManual,
          ),
        );
      }
    });
    if (r.success) {
      _avisar(
        ligar
            ? '${sdr.displayName} voltou para a roleta'
            : '${sdr.displayName} saiu da roleta',
        RoletaTom.sucesso,
      );
      return;
    }
    final mensagem = r.message ?? 'Erro ao alterar disponibilidade';
    _avisar(
      mensagem,
      SdrRouletteRules.ehRegraDoUltimoAtivo(mensagem)
          ? RoletaTom.aviso
          : RoletaTom.erro,
    );
  }

  /// Marca "SDR de locação": só conversas de locação, card no funil de
  /// locação. Independe da pausa (um SDR pausado continua marcado).
  Future<void> _marcarLocacao(SdrAvailability sdr) async {
    if (_marcando.contains(sdr.userId)) return;
    final proximo = !SdrRouletteRules.ehSdrDeLocacao(sdr);
    setState(() => _marcando.add(sdr.userId));
    final r = await _service.setSoLocacao(sdr.userId, proximo);
    if (!mounted) return;
    final salvo = r.data ?? proximo;
    setState(() {
      _marcando.remove(sdr.userId);
      if (r.success) _trocar(sdr.userId, (s) => s.withSoLocacao(salvo));
    });
    if (r.success) {
      _avisar(
        SdrRouletteRules.avisoAposMarcarSdr(sdr.displayName, salvo),
        RoletaTom.sucesso,
      );
      return;
    }
    if (SdrRouletteRules.ehRotaAusente(r.statusCode, r.message)) {
      _avisar(SdrRouletteRules.marcacaoIndisponivel, RoletaTom.aviso);
      return;
    }
    _avisar(
      r.message ?? SdrRouletteRules.erroAoMarcarLocacao,
      RoletaTom.erro,
    );
  }

  Future<void> _abrirFolga(SdrAvailability sdr) async {
    // Toque duplo não empilha duas folhas.
    if (_folhaAberta) return;
    _folhaAberta = true;
    final resultado = await showScheduleLeaveSheet(context, sdr: sdr);
    _folhaAberta = false;
    if (!mounted || resultado == null) return;
    switch (resultado) {
      case SdrLeaveSheetResult.scheduled:
        _avisar('Folga agendada para ${sdr.displayName}', RoletaTom.sucesso);
      case SdrLeaveSheetResult.canceled:
        _avisar(
          'Folga agendada de ${sdr.displayName} cancelada',
          RoletaTom.sucesso,
        );
    }
    unawaited(_carregar());
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'WhatsApp',
      showBottomNavigation: false,
      // Aberta a partir do WhatsApp: "voltar" no lugar do menu. Se um dia
      // virar destino do menu (pilha vazia), o menu volta.
      showDrawer: !Navigator.of(context).canPop(),
      actions: [
        _AcaoAtualizar(
          girando: _carregando || _atualizando,
          onPressed: () => unawaited(_carregar()),
        ),
      ],
      body: _corpo(context),
    );
  }

  Widget _corpo(BuildContext context) {
    if (!_carregouUmaVez) {
      final erro = _erro;
      if (erro != null && !_carregando) {
        return AppErrorState.fromApi(
          message: erro,
          statusCode: _erroStatus,
          onRetry: _carregar,
        );
      }
      return _esqueleto(context);
    }
    return RefreshIndicator(
      color: RoletaTinta.verde(context),
      onRefresh: _carregar,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: _slivers(context),
      ),
    );
  }

  List<Widget> _slivers(BuildContext context) {
    final agora = DateTime.now();
    final sdrs = _sdrs;
    final marcacaoDisponivel =
        SdrRouletteRules.marcacaoDeLocacaoDisponivel(sdrs);
    // Sem a marcação no back, o filtro Locação some: volta para Todos.
    final filtro =
        (!marcacaoDisponivel && _filtro == SdrRouletteFilter.locacao)
            ? SdrRouletteFilter.todos
            : _filtro;

    var nRoleta = 0;
    var nFolga = 0;
    var nPausado = 0;
    var marcadas = 0;
    for (final s in sdrs) {
      switch (SdrRouletteRules.situacaoDo(s)) {
        case SdrSituation.roleta:
          nRoleta++;
        case SdrSituation.folga:
          nFolga++;
        case SdrSituation.pausado:
          nPausado++;
      }
      if (SdrRouletteRules.folgaMarcada(s, agora)) marcadas++;
    }
    final nLocacao = SdrRouletteRules.contarSdrsDeLocacao(sdrs);
    final naRoleta = sdrs.where((s) => s.isActive).toList();

    final termo = SdrRouletteRules.semAcento(_busca.trim());
    final visiveis = sdrs.where((s) {
      if (termo.isNotEmpty &&
          !SdrRouletteRules.semAcento(s.userName).contains(termo)) {
        return false;
      }
      switch (filtro) {
        case SdrRouletteFilter.todos:
          return true;
        case SdrRouletteFilter.locacao:
          return SdrRouletteRules.ehSdrDeLocacao(s);
        case SdrRouletteFilter.folga:
          return SdrRouletteRules.situacaoDo(s) == SdrSituation.folga ||
              SdrRouletteRules.folgaMarcada(s, agora);
        case SdrRouletteFilter.roleta:
          return SdrRouletteRules.situacaoDo(s) == SdrSituation.roleta;
        case SdrRouletteFilter.pausado:
          return SdrRouletteRules.situacaoDo(s) == SdrSituation.pausado;
      }
    }).toList()
      ..sort(SdrRouletteRules.compararNomes);

    final filtros = <(SdrRouletteFilter, String, int)>[
      (SdrRouletteFilter.todos, 'Todos', sdrs.length),
      (SdrRouletteFilter.roleta, 'Na roleta', nRoleta),
      (SdrRouletteFilter.folga, 'De folga', nFolga + marcadas),
      (SdrRouletteFilter.pausado, 'Pausados', nPausado),
      if (marcacaoDisponivel)
        (SdrRouletteFilter.locacao, 'Locação', nLocacao),
    ];

    const ordem = <(SdrSituation, String)>[
      (SdrSituation.roleta, 'Recebendo agora'),
      (SdrSituation.folga, 'De folga'),
      (SdrSituation.pausado, 'Fora da roleta'),
    ];
    final secoes = <(SdrSituation, String, List<SdrAvailability>)>[
      for (final o in ordem)
        (
          o.$1,
          o.$2,
          visiveis
              .where((s) => SdrRouletteRules.situacaoDo(s) == o.$1)
              .toList(),
        ),
    ].where((s) => s.$3.isNotEmpty).toList();

    final ativos = nRoleta;

    return [
      SliverToBoxAdapter(child: _cabecalho(context, sdrs.length)),
      SliverToBoxAdapter(
        child: SdrRoulettePlate(
          naRoleta: nRoleta,
          deFolga: nFolga,
          pausados: nPausado,
          marcadas: marcadas,
          deLocacao: nLocacao,
          mostrarLocacao: marcacaoDisponivel,
          quemRecebe: naRoleta,
        ),
      ),
      SliverToBoxAdapter(child: _ferragens(context, filtros, filtro)),
      if (sdrs.isEmpty)
        SliverToBoxAdapter(
          child: _vazio(
            context,
            icone: LucideIcons.users,
            titulo: 'Nenhum SDR na roleta',
            texto:
                'Escolha a equipe responsável na configuração do WhatsApp.',
          ),
        )
      else if (visiveis.isEmpty)
        SliverToBoxAdapter(
          child: _vazio(
            context,
            icone: LucideIcons.userRoundSearch,
            titulo: 'Ninguém com esse filtro',
            texto: _busca.trim().isNotEmpty
                ? 'Nenhum SDR com "${_busca.trim()}".'
                : 'Troque o filtro acima.',
          ),
        )
      else
        for (var i = 0; i < secoes.length; i++)
          _secao(
            context,
            situacao: secoes[i].$1,
            titulo: secoes[i].$2,
            itens: secoes[i].$3,
            ultima: i == secoes.length - 1,
            ativos: ativos,
            marcacaoDisponivel: marcacaoDisponivel,
            agora: agora,
          ),
      SliverToBoxAdapter(child: _rodape(context)),
      SliverToBoxAdapter(
        child: SizedBox(
          height: _kPadBottom + MediaQuery.paddingOf(context).bottom,
        ),
      ),
    ];
  }

  // ─── Cabeçalho ───────────────────────────────────────────────────────────

  /// Cabeçalho da casa: título + contagem apagada + subtítulo, flush.
  Widget _cabecalho(BuildContext context, int total) {
    final secundario = RoletaTinta.textoSecundario(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(_kPadH, 6, _kPadH, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.users, size: 18, color: secundario),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Roleta de distribuição',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                    height: 1.15,
                    color: RoletaTinta.texto(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$total',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: secundario,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Text(
              'Quem recebe as conversas que chegam na fila do WhatsApp',
              style: TextStyle(fontSize: 12.5, height: 1.35, color: secundario),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Busca + filtros ─────────────────────────────────────────────────────

  Widget _ferragens(
    BuildContext context,
    List<(SdrRouletteFilter, String, int)> filtros,
    SdrRouletteFilter ativo,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_kPadH, 14, _kPadH, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _campoDeBusca(context),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: RoletaTinta.fioForte(context)),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < filtros.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                        right: i == filtros.length - 1 ? 0 : 18,
                      ),
                      child: _PalavraDoFiltro(
                        rotulo: filtros[i].$2,
                        n: filtros[i].$3,
                        ativa: filtros[i].$1 == ativo,
                        onTap: () => setState(() => _filtro = filtros[i].$1),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Busca preenchida, no estilo da caixa do WhatsApp; filtra na hora.
  Widget _campoDeBusca(BuildContext context) {
    final secundario = RoletaTinta.textoSecundario(context);
    final temTexto = _busca.isNotEmpty;
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: RoletaTinta.campoDeBusca(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const SizedBox(width: 11),
          Icon(LucideIcons.search, size: 17, color: secundario),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _buscaCtrl,
              textInputAction: TextInputAction.search,
              cursorColor: RoletaTinta.verde(context),
              style: TextStyle(
                color: RoletaTinta.texto(context),
                fontSize: 15,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.1,
              ),
              decoration: InputDecoration(
                hintText: 'Buscar SDR pelo nome',
                hintStyle: TextStyle(
                  color: secundario.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w400,
                  fontSize: 15,
                ),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              onChanged: (v) => setState(() => _busca = v),
            ),
          ),
          if (temTexto)
            Semantics(
              button: true,
              label: 'Limpar busca',
              child: InkResponse(
                radius: 16,
                onTap: () {
                  _buscaCtrl.clear();
                  setState(() => _busca = '');
                },
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: secundario.withValues(alpha: 0.35),
                  ),
                  child: const Icon(
                    LucideIcons.x,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 10),
        ],
      ),
    );
  }

  // ─── Seções ──────────────────────────────────────────────────────────────

  /// Seção com cabeçalho preso no topo enquanto a lista dela rola (o
  /// `position: sticky` do web): o grupo empurra o cabeçalho para fora quando
  /// a seção acaba.
  Widget _secao(
    BuildContext context, {
    required SdrSituation situacao,
    required String titulo,
    required List<SdrAvailability> itens,
    required bool ultima,
    required int ativos,
    required bool marcacaoDisponivel,
    required DateTime agora,
  }) {
    return SliverMainAxisGroup(
      key: ValueKey('secao-${situacao.name}'),
      slivers: [
        PinnedHeaderSliver(
          child: _CabecaDaSecao(
            titulo: titulo,
            n: itens.length,
            cor: RoletaTinta.daSituacao(context, situacao),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(_kPadH, 0, _kPadH, ultima ? 0 : 6),
          sliver: SliverList.builder(
            itemCount: itens.length,
            itemBuilder: (context, i) {
              final sdr = itens[i];
              return Padding(
                key: ValueKey('sdr-${sdr.userId}'),
                padding: EdgeInsets.only(bottom: i == itens.length - 1 ? 0 : 8),
                child: SdrRouletteCard(
                  sdr: sdr,
                  ultimoAtivo: sdr.isActive && ativos == 1,
                  alternando: _alternando.contains(sdr.userId),
                  marcandoLocacao: _marcando.contains(sdr.userId),
                  marcacaoDisponivel: marcacaoDisponivel,
                  agora: agora,
                  onToggle: () => _alternar(sdr),
                  onScheduleLeave: () => _abrirFolga(sdr),
                  onToggleLocacao: () => _marcarLocacao(sdr),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _vazio(
    BuildContext context, {
    required IconData icone,
    required String titulo,
    required String texto,
  }) {
    final secundario = RoletaTinta.textoSecundario(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 12),
      child: Column(
        children: [
          Icon(icone, size: 30, color: secundario.withValues(alpha: 0.6)),
          const SizedBox(height: 10),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: RoletaTinta.texto(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            texto,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, height: 1.4, color: secundario),
          ),
        ],
      ),
    );
  }

  /// Rodapé informativo, flush (sem caixa).
  Widget _rodape(BuildContext context) {
    final secundario = RoletaTinta.textoSecundario(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(_kPadH, 20, _kPadH, 0),
      child: Container(
        padding: const EdgeInsets.only(top: 12),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: RoletaTinta.fio(context))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1.5),
              child: Icon(LucideIcons.info, size: 14, color: secundario),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                SdrRouletteRules.rodape,
                style: TextStyle(fontSize: 11.5, height: 1.45, color: secundario),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Esqueleto ───────────────────────────────────────────────────────────

  /// Esqueleto fiel ao layout: cabeçalho, placa (manchete, pilha, barra,
  /// leituras), busca, filtros, cabeçalho de seção e cartões.
  Widget _esqueleto(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(_kPadH, 8, _kPadH, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SkeletonBox(width: 18, height: 18, borderRadius: 5),
                    SizedBox(width: 8),
                    Flexible(
                      child: SkeletonText(
                        width: 190,
                        height: 17,
                        borderRadius: 5,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 7),
                Padding(
                  padding: EdgeInsets.only(left: 26),
                  child: FractionallySizedBox(
                    widthFactor: 0.8,
                    child: SkeletonText(height: 11, borderRadius: 4),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              color: RoletaTinta.banda(context),
              border: Border(
                top: BorderSide(color: RoletaTinta.fio(context)),
                bottom: BorderSide(color: RoletaTinta.fio(context)),
              ),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SkeletonBox(width: 40, height: 34, borderRadius: 8),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FractionallySizedBox(
                            widthFactor: 0.7,
                            child: SkeletonText(height: 13, borderRadius: 4),
                          ),
                          SizedBox(height: 6),
                          FractionallySizedBox(
                            widthFactor: 0.8,
                            child: SkeletonText(height: 10, borderRadius: 4),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 8),
                    SkeletonBox(width: 30, height: 30, borderRadius: 999),
                    SizedBox(width: 4),
                    SkeletonBox(width: 30, height: 30, borderRadius: 999),
                    SizedBox(width: 4),
                    SkeletonBox(width: 30, height: 30, borderRadius: 999),
                  ],
                ),
                SizedBox(height: 14),
                SkeletonBox(width: double.infinity, height: 6, borderRadius: 999),
                SizedBox(height: 10),
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    SkeletonText(width: 74, height: 11, borderRadius: 4),
                    SkeletonText(width: 70, height: 11, borderRadius: 4),
                    SkeletonText(width: 80, height: 11, borderRadius: 4),
                  ],
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(_kPadH, 14, _kPadH, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SkeletonBox(height: 42, borderRadius: 12),
                SizedBox(height: 16),
                Wrap(
                  spacing: 18,
                  runSpacing: 8,
                  children: [
                    SkeletonText(width: 52, height: 12, borderRadius: 4),
                    SkeletonText(width: 74, height: 12, borderRadius: 4),
                    SkeletonText(width: 70, height: 12, borderRadius: 4),
                    SkeletonText(width: 68, height: 12, borderRadius: 4),
                  ],
                ),
                SizedBox(height: 12),
              ],
            ),
          ),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: _kPadH),
            color: RoletaTinta.fioForte(context),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 16, 18, 10),
            child: Row(
              children: [
                SkeletonBox(width: 7, height: 7, borderRadius: 999),
                SizedBox(width: 7),
                SkeletonText(width: 110, height: 10, borderRadius: 4),
              ],
            ),
          ),
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.fromLTRB(_kPadH, 0, _kPadH, 8),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                decoration: BoxDecoration(
                  color: RoletaTinta.painel(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: RoletaTinta.bordaDoCartao(context)),
                  boxShadow: RoletaTinta.sombraDoCartao(context),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 38, height: 38, borderRadius: 999),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FractionallySizedBox(
                            widthFactor: 0.62,
                            child: SkeletonText(height: 13, borderRadius: 4),
                          ),
                          SizedBox(height: 7),
                          FractionallySizedBox(
                            widthFactor: 0.4,
                            child: SkeletonText(height: 10, borderRadius: 4),
                          ),
                          SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              SkeletonBox(width: 78, height: 30, borderRadius: 8),
                              SkeletonBox(width: 108, height: 30, borderRadius: 8),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 10),
                    SkeletonBox(width: 44, height: 26, borderRadius: 999),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Peças da página ─────────────────────────────────────────────────────────

/// Filtro em palavra + sublinhado verde, com contagem. Uma cópia invisível em
/// peso 800 reserva a largura: a fila não dança ao engordar.
class _PalavraDoFiltro extends StatelessWidget {
  final String rotulo;
  final int n;
  final bool ativa;
  final VoidCallback onTap;

  const _PalavraDoFiltro({
    required this.rotulo,
    required this.n,
    required this.ativa,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final texto = RoletaTinta.texto(context);
    final secundario = RoletaTinta.textoSecundario(context);
    const forte = TextStyle(fontSize: 13, fontWeight: FontWeight.w800);
    return Semantics(
      button: true,
      selected: ativa,
      child: InkWell(
        onTap: ativa ? null : onTap,
        borderRadius: BorderRadius.circular(6),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(1, 10, 1, 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Visibility(
                          visible: false,
                          maintainSize: true,
                          maintainAnimation: true,
                          maintainState: true,
                          child: Text(rotulo, maxLines: 1, style: forte),
                        ),
                        Text(
                          rotulo,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                ativa ? FontWeight.w800 : FontWeight.w600,
                            color: ativa ? texto : secundario,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '$n',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: secundario,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                height: 3,
                decoration: BoxDecoration(
                  color: ativa ? RoletaTinta.verde(context) : Colors.transparent,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(2),
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

/// Cabeçalho de seção preso: ponto na cor da situação, título em caixa alta
/// e contagem. Vidro translúcido para os cartões passarem por baixo.
class _CabecaDaSecao extends StatelessWidget {
  final String titulo;
  final int n;
  final Color cor;

  const _CabecaDaSecao({
    required this.titulo,
    required this.n,
    required this.cor,
  });

  @override
  Widget build(BuildContext context) {
    final secundario = RoletaTinta.textoSecundario(context);
    final estilo = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.0,
      color: secundario,
    );
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: ColoredBox(
          color: RoletaTinta.vidro(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: cor),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    titulo.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: estilo,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  '$n',
                  style: estilo.copyWith(
                    letterSpacing: 0,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Atualizar da barra (ferramenta à direita): gira enquanto carrega, como o
/// ícone do web.
class _AcaoAtualizar extends StatefulWidget {
  final bool girando;
  final VoidCallback onPressed;

  const _AcaoAtualizar({required this.girando, required this.onPressed});

  @override
  State<_AcaoAtualizar> createState() => _AcaoAtualizarState();
}

class _AcaoAtualizarState extends State<_AcaoAtualizar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _giro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.girando) _giro.repeat();
  }

  @override
  void didUpdateWidget(covariant _AcaoAtualizar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.girando && !_giro.isAnimating) {
      _giro.repeat();
    } else if (!widget.girando && _giro.isAnimating) {
      _giro
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _giro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = RoletaTinta.texto(context);
    return Tooltip(
      message: 'Atualizar',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.girando ? null : widget.onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: RotationTransition(
                turns: _giro,
                child: Icon(
                  LucideIcons.rotateCw,
                  size: 20,
                  color: c.withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
