import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../../kanban/models/kanban_models.dart';
import '../models/sdr_extra_models.dart';
import '../models/sdr_metrics_model.dart';
import 'sdr_dash_pecas.dart';

/// Qual estação do funil abriu o detalhe.
enum SdrDetalheTipo { entradas, qualificacao, transferidos, perdidos }

/// Busca (ou reaproveita) as listas completas do recorte atual. `forcar`
/// descarta o que estiver guardado — usado no "Tentar de novo".
typedef SdrCarregarListas = Future<ApiResponse<SdrLeadLists>> Function({
  bool forcar,
});

/// Detalhe de uma estação do funil — o painel de detalhe do web
/// (`renderFunnelDrillPanel`, SDRDashboardPage.tsx) numa folha, com os
/// mesmos recortes, agrupamentos, cruzamentos e campos dos cartões:
///   - Leads no período: coorte de entrada por estado (em qualificação ou
///     perdido), filtro por estado;
///   - Em qualificação: agrupar por SDR, funil, etapa ou fonte; ordem por
///     grupo e prazo;
///   - Leads perdidos: "entraram no período" × "marcadas no período";
///     agrupar por motivo, SDR ou funil;
///   - Transferências: filtros de funis de origem e destino, lista com os
///     dois cards (SDR e corretor), totais por grupo e as três tabelas
///     cruzadas com subtotal por origem.
Future<void> mostrarSdrDetalhe(
  BuildContext context, {
  required SdrDetalheTipo tipo,
  required SdrMetrics metricas,
  required SdrCarregarListas carregar,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.black54,
    backgroundColor: Colors.transparent,
    builder: (_) => _SdrDetalheSheet(
      tipo: tipo,
      metricas: metricas,
      carregar: carregar,
    ),
  );
}

/// "Agrupar por" da lista Em qualificação (os mesmos do web).
enum _AgruparQualif {
  sdr('SDR (com quem)'),
  funil('Funil'),
  etapa('Etapa (coluna)'),
  fonte('Fonte');

  const _AgruparQualif(this.rotulo);
  final String rotulo;
}

/// "Agrupar por" das perdas marcadas no período (os mesmos do web).
enum _AgruparPerda {
  motivo('Motivo de perda'),
  sdr('SDR'),
  funil('Funil');

  const _AgruparPerda(this.rotulo);
  final String rotulo;
}

/// Um grupo do resumo (rótulo + quantos).
class _Grupo {
  const _Grupo(this.rotulo, this.contagem);

  final String rotulo;
  final int contagem;
}

/// Um par "Rótulo: valor" de uma linha do cartão (rótulo nulo = só o valor).
typedef _Par = (String?, String);

class _SdrDetalheSheet extends StatefulWidget {
  const _SdrDetalheSheet({
    required this.tipo,
    required this.metricas,
    required this.carregar,
  });

  final SdrDetalheTipo tipo;
  final SdrMetrics metricas;
  final SdrCarregarListas carregar;

  @override
  State<_SdrDetalheSheet> createState() => _SdrDetalheSheetState();
}

class _SdrDetalheSheetState extends State<_SdrDetalheSheet> {
  static const int _kLote = 30;
  static const int _kGruposResumo = 6;

  ApiResponse<SdrLeadLists>? _resp;
  bool _carregando = true;

  /// A folha pode trocar de estação por dentro (dos perdidos da coorte para
  /// as perdas marcadas), como o seletor de leitura do web.
  late SdrDetalheTipo _tipo = widget.tipo;

  /// Leads no período: estados marcados no resumo (vazio = todos).
  final Set<String> _estados = <String>{};

  /// Perdidos: `false` = entraram no período (coorte — o número da estação);
  /// `true` = marcadas no período (data da perda).
  bool _perdasMarcadas = false;
  _AgruparPerda _agruparPerda = _AgruparPerda.motivo;
  _AgruparQualif _agruparQualif = _AgruparQualif.sdr;

  /// Grupos marcados no resumo (Em qualificação e perdas marcadas).
  final Set<String> _grupos = <String>{};
  bool _gruposAbertos = false;

  /// Transferências: 0 = lista, 1 = por grupo, 2 = cruzamentos.
  int _abaTransfer = 0;
  final Set<String> _origens = <String>{};
  final Set<String> _destinos = <String>{};

  /// Seções de "Por grupo" abertas por inteiro.
  final Set<String> _secoesAbertas = <String>{};

  int _visiveis = _kLote;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar({bool forcar = false}) async {
    // Na abertura já nasce carregando (sem setState dentro do initState).
    if (!_carregando) setState(() => _carregando = true);
    final r = await widget.carregar(forcar: forcar);
    if (!mounted) return;
    setState(() {
      _resp = r;
      _carregando = false;
    });
  }

  SdrLeadLists? get _listas =>
      (_resp?.success ?? false) ? _resp!.data : null;

  SdrSummary get _s => widget.metricas.summary;

  void _recomecarLista() {
    _visiveis = _kLote;
  }

  // ─── Texto e ordem ─────────────────────────────────────────────────────────

  static String? _texto(String? v) {
    final t = v?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  /// `drillDimLabel` do web: vazio vira "—".
  static String _rotulo(String? v) => _texto(v) ?? '—';

  static String _motivo(String? raw) {
    final t = _texto(raw);
    if (t == null) return 'Sem motivo';
    return KanbanLossReason.tryParse(t)?.label ?? t;
  }

  static const Map<String, String> _acentos = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'é': 'e', 'ê': 'e', 'í': 'i', //
    'ó': 'o', 'ô': 'o', 'õ': 'o', 'ú': 'u', 'ü': 'u', 'ç': 'c',
  };

  /// Ordem alfabética do português (sem caixa nem acento).
  static int _comparar(String a, String b) {
    String chave(String s) =>
        s.toLowerCase().split('').map((c) => _acentos[c] ?? c).join();
    return chave(a).compareTo(chave(b));
  }

  static int _ms(DateTime? d) => d?.millisecondsSinceEpoch ?? 0;

  /// Prazo: mais cedo primeiro; sem prazo por último.
  static int _msPrazo(DateTime? d) =>
      d?.millisecondsSinceEpoch ?? 8640000000000000;

  /// "12/09/26 14:32" (só a data quando não há hora).
  static String _dataHora(DateTime? d) {
    if (d == null) return '—';
    final l = d.toLocal();
    String dois(int n) => n.toString().padLeft(2, '0');
    final data = '${dois(l.day)}/${dois(l.month)}/${dois(l.year % 100)}';
    if (l.hour == 0 && l.minute == 0) return data;
    return '$data ${dois(l.hour)}:${dois(l.minute)}';
  }

  static List<_Grupo> _contar(
    List<SdrLeadRow> lista,
    String Function(SdrLeadRow) chave,
  ) {
    final conta = <String, int>{};
    for (final r in lista) {
      final k = chave(r);
      conta[k] = (conta[k] ?? 0) + 1;
    }
    return conta.entries.map((e) => _Grupo(e.key, e.value)).toList()
      ..sort((a, b) => b.contagem.compareTo(a.contagem));
  }

  Color _tomDoEstado(BuildContext context, String? estado) => switch (estado) {
        'Perdido' => SdrTom.perdido(context),
        'Transferido' => SdrTom.transferido(context),
        _ => SdrTom.qualificacao(context),
      };

  // ─── Transferências ────────────────────────────────────────────────────────

  List<SdrLeadRow> _transferenciasFiltradas(SdrLeadLists l) {
    return l.transferred.where((t) {
      final de = _rotulo(t.fromTeam);
      final para = _rotulo(t.toTeam);
      return (_origens.isEmpty || _origens.contains(de)) &&
          (_destinos.isEmpty || _destinos.contains(para));
    }).toList(growable: false);
  }

  /// Os agregados da API quando a lista não está filtrada; com filtro de
  /// origem/destino (ou payload antigo sem agregados), a conta sai da própria
  /// lista — `aggregateTransferList` do web.
  SdrTransferAggregates _agregados(
    SdrLeadLists l,
    List<SdrLeadRow> filtradas,
  ) {
    final base = widget.metricas.transferAggregates;
    if (filtradas.length == l.transferred.length) {
      if (base.isEmpty && l.transferred.isNotEmpty) {
        return _agregarLocal(l.transferred);
      }
      return base;
    }
    return _agregarLocal(filtradas);
  }

  static SdrTransferAggregates _agregarLocal(List<SdrLeadRow> lista) {
    final porOrigem = <String, int>{};
    final porDestino = <String, int>{};
    final porSdr = <String, int>{};
    final porQuem = <String, int>{};
    final porCorretor = <String, int>{};
    final o2d = <(String, String), int>{};
    final o2c = <(String, String), int>{};
    final o2q = <(String, String), int>{};
    void soma<K>(Map<K, int> m, K k) => m[k] = (m[k] ?? 0) + 1;
    for (final t in lista) {
      final de = _rotulo(t.fromTeam);
      final para = _rotulo(t.toTeam);
      final corretor = _rotulo(t.assignedTo);
      final quem = _rotulo(t.transferredBy);
      soma(porOrigem, de);
      soma(porDestino, para);
      soma(porSdr, _rotulo(t.agentName));
      soma(porQuem, quem);
      soma(porCorretor, corretor);
      soma(o2d, (de, para));
      soma(o2c, (de, corretor));
      soma(o2q, (de, quem));
    }
    List<SdrLabelCount> ordena(Map<String, int> m) => m.entries
        .map((e) => SdrLabelCount(label: e.key, count: e.value))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    List<SdrFluxo> fluxos(Map<(String, String), int> m) => m.entries
        .map((e) => SdrFluxo(
              origem: e.key.$1,
              destino: e.key.$2,
              contagem: e.value,
            ))
        .toList(growable: false);
    return SdrTransferAggregates(
      byDestinationTeam: ordena(porDestino),
      byDestinationFunnel: const [],
      byAttendant: ordena(porSdr),
      byTransferredBy: ordena(porQuem),
      byResponsible: ordena(porCorretor),
      byFunnel: ordena(porOrigem),
      originToDestinationFunnel: fluxos(o2d),
      originToResponsible: fluxos(o2c),
      originToTransferredBy: fluxos(o2q),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  ({String titulo, String subtitulo, IconData icone, Color tom}) _cabecalho(
      BuildContext context) {
    switch (_tipo) {
      case SdrDetalheTipo.entradas:
        return (
          titulo: 'Leads no período',
          subtitulo:
              '${sdrInt(_s.totalEntries)} entradas (CRM): cada lead segue em qualificação ou se perdeu. Os transferidos saíram do funil.',
          icone: LucideIcons.logIn,
          tom: SdrTom.eixo(context),
        );
      case SdrDetalheTipo.qualificacao:
        return (
          titulo: 'Em qualificação',
          subtitulo:
              '${sdrInt(_s.inQualification)} leads abertos no SDR, com totais por SDR, funil, etapa ou fonte.',
          icone: LucideIcons.hourglass,
          tom: SdrTom.qualificacao(context),
        );
      case SdrDetalheTipo.transferidos:
        return (
          titulo: 'Transferências',
          subtitulo:
              'Origem, destino, quem transferiu e quem recebeu, pela data da transferência.',
          icone: LucideIcons.arrowRightLeft,
          tom: SdrTom.transferido(context),
        );
      case SdrDetalheTipo.perdidos:
        return (
          titulo: 'Leads perdidos',
          subtitulo: 'Totais por dimensão e a lista de quem se perdeu.',
          icone: LucideIcons.circleX,
          tom: SdrTom.perdido(context),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final cab = _cabecalho(context);
    final l = _listas;
    final nTransfer = l == null
        ? _s.transferred
        : _transferenciasFiltradas(l).length;

    // Material (não Container decorado): o toque das linhas desenha a onda
    // aqui — sobre um fundo opaco ela ficaria escondida.
    return SizedBox(
      height: mq.size.height * 0.88,
      child: Material(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: ThemeHelpers.borderColor(context),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            _cabecalhoFolha(context, cab),
            if (_tipo == SdrDetalheTipo.perdidos)
              _abas(
                context,
                itens: [
                  ('Entraram no período', _s.lostByEntry),
                  ('Marcados no período', _s.lost),
                ],
                ativa: _perdasMarcadas ? 1 : 0,
                tom: cab.tom,
                onTap: (i) => setState(() {
                  _perdasMarcadas = i == 1;
                  _grupos.clear();
                  _gruposAbertos = false;
                  _recomecarLista();
                }),
              ),
            if (_tipo == SdrDetalheTipo.transferidos)
              _abas(
                context,
                itens: [
                  ('Transferências', nTransfer),
                  ('Por grupo', null),
                  ('Cruzamentos', null),
                ],
                ativa: _abaTransfer,
                tom: cab.tom,
                onTap: (i) => setState(() => _abaTransfer = i),
              ),
            Container(height: 1, color: SdrTom.trilho(context)),
            Expanded(child: _corpo(context, cab.tom)),
          ],
        ),
      ),
    );
  }

  Widget _cabecalhoFolha(
    BuildContext context,
    ({String titulo, String subtitulo, IconData icone, Color tom}) cab,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 6, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: cab.tom.withValues(alpha: isDark ? 0.18 : 0.10),
            ),
            child: Icon(
              cab.icone,
              size: 17,
              color: SdrTom.texto(context, cab.tom),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cab.titulo,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                    letterSpacing: -0.3,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  cab.subtitulo,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Fechar',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(
              LucideIcons.x,
              size: 20,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
        ],
      ),
    );
  }

  /// Abas com sublinhado (rolam na horizontal quando não cabem).
  Widget _abas(
    BuildContext context, {
    required List<(String, int?)> itens,
    required int ativa,
    required Color tom,
    required ValueChanged<int> onTap,
  }) {
    final theme = Theme.of(context);
    final tinta = SdrTom.texto(context, tom);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          for (var i = 0; i < itens.length; i++)
            InkWell(
              onTap: i == ativa ? null : () => onTap(i),
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: i == ativa ? tinta : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: itens[i].$1),
                      if (itens[i].$2 != null)
                        TextSpan(
                          text: '  ${sdrInt(itens[i].$2!)}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: i == ativa
                        ? tinta
                        : ThemeHelpers.textSecondaryColor(context),
                    fontWeight: i == ativa ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _corpo(BuildContext context, Color tom) {
    final fundo = MediaQuery.paddingOf(context).bottom + 20;

    if (_carregando) return _esqueleto(context, fundo);

    final l = _listas;
    if (l == null) {
      return ListView(
        padding: EdgeInsets.fromLTRB(16, 24, 16, fundo),
        children: [
          AppErrorState.fromApi(
            message: _resp?.message,
            statusCode: _resp?.statusCode ?? 0,
            onRetry: () => _carregar(forcar: true),
            dense: true,
          ),
        ],
      );
    }

    final itens = switch (_tipo) {
      SdrDetalheTipo.entradas => _itensEntradas(context, l, tom),
      SdrDetalheTipo.qualificacao => _itensQualificacao(context, l, tom),
      SdrDetalheTipo.perdidos => _itensPerdidos(context, l, tom),
      SdrDetalheTipo.transferidos => _itensTransferidos(context, l, tom),
    };
    return ListView.builder(
      padding: EdgeInsets.only(bottom: fundo),
      itemCount: itens.length,
      itemBuilder: (context, i) => itens[i],
    );
  }

  // ─── Leads no período ─────────────────────────────────────────────────────

  List<Widget> _itensEntradas(
    BuildContext context,
    SdrLeadLists l,
    Color tom,
  ) {
    final todos = [...l.period]
      ..sort((a, b) => _ms(b.createdAt).compareTo(_ms(a.createdAt)));
    final lista = _estados.isEmpty
        ? todos
        : todos.where((r) => _estados.contains(r.stateLabel)).toList();
    // Resumo pelos números do painel (coorte de entrada), como o web.
    final grupos = <_Grupo>[
      if (_s.inQualification > 0) _Grupo('Em qualificação', _s.inQualification),
      if (_s.lostByEntry > 0) _Grupo('Perdido', _s.lostByEntry),
    ]..sort((a, b) => b.contagem.compareTo(a.contagem));

    return [
      if (grupos.isNotEmpty)
        _resumo(
          context,
          titulo: 'Por estado',
          dica: _estados.isEmpty
              ? 'Toque num estado para listar só ele (pode marcar mais de um).'
              : null,
          grupos: grupos,
          total: todos.length,
          marcados: _estados,
          tomDo: (g) => _tomDoEstado(context, g),
          onToggle: (g) => setState(() {
            if (!_estados.remove(g)) _estados.add(g);
            _recomecarLista();
          }),
        ),
      if (_estados.length == 1 && _estados.contains('Perdido'))
        _leituraPerdas(context, podeTrocar: true),
      _cabecalhoLista(
        context,
        mostrando: lista.length,
        total: todos.length,
        filtrado: _estados.isNotEmpty,
        onLimpar: () => setState(() {
          _estados.clear();
          _recomecarLista();
        }),
      ),
      if (lista.isEmpty)
        _vazio(
          context,
          todos.isEmpty
              ? 'Nenhum lead no período.'
              : 'Nenhum lead neste filtro. Limpe o filtro ou ajuste o recorte.',
        ),
      ..._cartoes(lista, (r, ultima) => _cartaoPeriodo(context, r, ultima)),
      _mais(context, lista.length),
    ];
  }

  // ─── Em qualificação ──────────────────────────────────────────────────────

  List<Widget> _itensQualificacao(
    BuildContext context,
    SdrLeadLists l,
    Color tom,
  ) {
    String chave(SdrLeadRow r) => switch (_agruparQualif) {
          _AgruparQualif.funil => _rotulo(r.funnel),
          _AgruparQualif.etapa => _rotulo(r.columnTitle),
          _AgruparQualif.fonte => _texto(r.source) ?? 'Sem fonte',
          _AgruparQualif.sdr => _rotulo(r.agentName),
        };
    final ordenada = [...l.qualification]
      ..sort((a, b) {
        final c = _comparar(chave(a), chave(b));
        if (c != 0) return c;
        final d = _msPrazo(a.dueDate).compareTo(_msPrazo(b.dueDate));
        if (d != 0) return d;
        return _ms(b.createdAt).compareTo(_ms(a.createdAt));
      });
    final grupos = _contar(ordenada, chave);
    final lista = _grupos.isEmpty
        ? ordenada
        : ordenada.where((r) => _grupos.contains(chave(r))).toList();

    return [
      _agruparPor(
        context,
        opcoes: [for (final o in _AgruparQualif.values) o.rotulo],
        ativa: _agruparQualif.index,
        tom: tom,
        onTap: (i) => setState(() {
          _agruparQualif = _AgruparQualif.values[i];
          _grupos.clear();
          _gruposAbertos = false;
          _recomecarLista();
        }),
      ),
      if (grupos.isNotEmpty)
        _resumo(
          context,
          dica: _grupos.isEmpty
              ? 'A lista já vem ordenada por esta dimensão. Toque nos grupos para filtrar.'
              : null,
          grupos: grupos,
          total: ordenada.length,
          marcados: _grupos,
          tomDo: (_) => tom,
          onToggle: _alternarGrupo,
        ),
      _cabecalhoLista(
        context,
        mostrando: lista.length,
        total: ordenada.length,
        filtrado: _grupos.isNotEmpty,
        onLimpar: _limparGrupos,
      ),
      if (lista.isEmpty) _vazio(context, 'Nenhum lead em qualificação neste recorte.'),
      ..._cartoes(
        lista,
        (r, ultima) => _cartaoQualificacao(context, r, ultima, tom),
      ),
      _mais(context, lista.length),
    ];
  }

  void _alternarGrupo(String g) => setState(() {
        if (!_grupos.remove(g)) _grupos.add(g);
        _recomecarLista();
      });

  void _limparGrupos() => setState(() {
        _grupos.clear();
        _recomecarLista();
      });

  // ─── Leads perdidos ───────────────────────────────────────────────────────

  List<Widget> _itensPerdidos(
    BuildContext context,
    SdrLeadLists l,
    Color tom,
  ) {
    if (!_perdasMarcadas) {
      // Coorte de entrada (o número da estação): a lista do período em
      // «Perdido», como o web abre ao tocar em Perdidos.
      final lista = l.period.where((r) => r.stateLabel == 'Perdido').toList()
        ..sort((a, b) => _ms(b.createdAt).compareTo(_ms(a.createdAt)));
      return [
        _leituraPerdas(context, podeTrocar: false),
        _cabecalhoLista(context, mostrando: lista.length),
        if (lista.isEmpty)
          _vazio(context, 'Nenhum lead que entrou no período se perdeu.'),
        ..._cartoes(lista, (r, ultima) => _cartaoPeriodo(context, r, ultima)),
        _mais(context, lista.length),
      ];
    }

    String chave(SdrLeadRow r) => switch (_agruparPerda) {
          _AgruparPerda.motivo => _motivo(r.lossReason),
          _AgruparPerda.sdr => _rotulo(r.agentName),
          _AgruparPerda.funil => _rotulo(r.funnel),
        };
    final ordenada = [...l.lost]
      ..sort((a, b) {
        final c = _comparar(chave(a), chave(b));
        if (c != 0) return c;
        return _ms(b.date).compareTo(_ms(a.date));
      });
    final grupos = _contar(ordenada, chave);
    final lista = _grupos.isEmpty
        ? ordenada
        : ordenada.where((r) => _grupos.contains(chave(r))).toList();

    return [
      _leituraPerdas(context, podeTrocar: false),
      _agruparPor(
        context,
        opcoes: [for (final o in _AgruparPerda.values) o.rotulo],
        ativa: _agruparPerda.index,
        tom: tom,
        onTap: (i) => setState(() {
          _agruparPerda = _AgruparPerda.values[i];
          _grupos.clear();
          _gruposAbertos = false;
          _recomecarLista();
        }),
      ),
      if (grupos.isNotEmpty)
        _resumo(
          context,
          dica: _grupos.isEmpty
              ? 'A lista já vem ordenada por esta dimensão. Toque num grupo para filtrar.'
              : null,
          grupos: grupos,
          total: ordenada.length,
          marcados: _grupos,
          tomDo: (_) => tom,
          onToggle: _alternarGrupo,
        ),
      _cabecalhoLista(
        context,
        mostrando: lista.length,
        total: ordenada.length,
        filtrado: _grupos.isNotEmpty,
        onLimpar: _limparGrupos,
      ),
      if (lista.isEmpty) _vazio(context, 'Nenhuma perda marcada neste recorte.'),
      ..._cartoes(lista, (r, ultima) => _cartaoPerda(context, r, ultima)),
      _mais(context, lista.length),
    ];
  }

  /// As duas leituras dos perdidos e por que diferem (o "LeituraEco" do web).
  Widget _leituraPerdas(BuildContext context, {required bool podeTrocar}) {
    final theme = Theme.of(context);
    final secundaria = ThemeHelpers.textSecondaryColor(context);
    final forte = TextStyle(
      fontWeight: FontWeight.w900,
      color: ThemeHelpers.textColor(context),
    );
    final diff = _s.lost - _s.lostByEntry;
    final List<InlineSpan> texto = diff > 0
        ? [
            TextSpan(text: sdrInt(diff), style: forte),
            const TextSpan(
              text:
                  ' perdas marcadas no período são de leads que entraram antes dele. A estação Perdidos usa a leitura por entrada.',
            ),
          ]
        : diff < 0
            ? [
                TextSpan(text: sdrInt(-diff), style: forte),
                const TextSpan(
                  text:
                      ' leads que entraram no período foram perdidos depois dele. A estação Perdidos usa a leitura por entrada.',
                ),
              ]
            : const [
                TextSpan(text: 'As duas leituras coincidem neste recorte.'),
              ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(LucideIcons.info, size: 14, color: secundaria),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text.rich(
                  TextSpan(children: texto),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: secundaria,
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          if (podeTrocar)
            TextButton.icon(
              onPressed: () => setState(() {
                _tipo = SdrDetalheTipo.perdidos;
                _perdasMarcadas = true;
                _grupos.clear();
                _gruposAbertos = false;
                _recomecarLista();
              }),
              style: TextButton.styleFrom(
                foregroundColor: ThemeHelpers.textColor(context),
                padding: const EdgeInsets.symmetric(horizontal: 0),
              ),
              icon: const Icon(LucideIcons.arrowRight, size: 14),
              label: Text(
                'Ver as ${sdrInt(_s.lost)} marcadas no período',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Transferências ───────────────────────────────────────────────────────

  List<Widget> _itensTransferidos(
    BuildContext context,
    SdrLeadLists l,
    Color tom,
  ) {
    if (l.transferred.isEmpty) {
      return [
        _vazio(
          context,
          'Nenhuma transferência encontrada no período e nos filtros selecionados.',
        ),
      ];
    }
    final filtradas = _transferenciasFiltradas(l);
    final itens = <Widget>[_filtrosOrigemDestino(context, l)];

    if (_abaTransfer == 0) {
      itens.add(_cabecalhoLista(
        context,
        mostrando: filtradas.length,
        total: l.transferred.length,
        filtrado: _origens.isNotEmpty || _destinos.isNotEmpty,
        singular: 'transferência',
        plural: 'transferências',
        onLimpar: () => setState(() {
          _origens.clear();
          _destinos.clear();
          _recomecarLista();
        }),
      ));
      if (filtradas.isEmpty) {
        itens.add(_vazio(
          context,
          'Nenhuma transferência com os filtros de origem e destino.',
        ));
      }
      itens.addAll(_cartoes(
        filtradas,
        (r, ultima) => _cartaoTransferencia(context, r, ultima),
      ));
      itens.add(_mais(context, filtradas.length));
      return itens;
    }

    final a = _agregados(l, filtradas);
    final total = filtradas.isEmpty ? 1 : filtradas.length;
    if (_abaTransfer == 1) {
      itens.addAll([
        _secaoGrupos(context, 'Por funil / equipe (origem)', a.byFunnel, total, tom),
        if (a.byDestinationFunnel.isNotEmpty)
          _secaoGrupos(
            context,
            'Por funil de destino',
            a.byDestinationFunnel,
            total,
            tom,
          ),
        _secaoGrupos(
          context,
          'Por equipe de destino',
          a.byDestinationTeam,
          total,
          tom,
        ),
        _secaoGrupos(
          context,
          'Quem executou a transferência',
          a.byTransferredBy,
          total,
          tom,
        ),
        _secaoGrupos(
          context,
          'SDR dono do lead (tarefa original)',
          a.byAttendant,
          total,
          tom,
        ),
        _secaoGrupos(
          context,
          'Por responsável (corretor que recebeu)',
          a.byResponsible,
          total,
          tom,
        ),
      ]);
      return itens;
    }

    final semFunilDestino = a.byDestinationFunnel.isEmpty;
    itens.addAll([
      _cruzamento(
        context,
        semFunilDestino
            ? 'Origem → equipe de destino'
            : 'Origem → funil de destino',
        a.originToDestinationFunnel,
        nota: semFunilDestino
            ? 'Sem nome de funil na API: mostra a equipe de destino.'
            : null,
      ),
      _cruzamento(context, 'Origem → quem transferiu', a.originToTransferredBy),
      _cruzamento(
        context,
        'Origem → corretor (quem recebeu)',
        a.originToResponsible,
      ),
    ]);
    return itens;
  }

  /// "Funis origem" / "Funis destino" do web, em duas linhas que abrem a
  /// escolha (várias opções; nada marcado = todos).
  Widget _filtrosOrigemDestino(BuildContext context, SdrLeadLists l) {
    List<String> opcoes(String? Function(SdrLeadRow) campo) {
      final nomes = <String>{};
      for (final t in l.transferred) {
        final n = _texto(campo(t));
        if (n != null) nomes.add(n);
      }
      return nomes.toList()..sort(_comparar);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        children: [
          _linhaFiltro(
            context,
            icone: LucideIcons.logIn,
            rotulo: 'Funis origem',
            marcados: _origens,
            onTap: () => _escolher(
              context,
              titulo: 'Funis origem',
              opcoes: opcoes((t) => t.fromTeam),
              marcados: _origens,
            ),
          ),
          Container(height: 1, color: SdrTom.trilho(context)),
          _linhaFiltro(
            context,
            icone: LucideIcons.arrowUpRight,
            rotulo: 'Funis destino',
            marcados: _destinos,
            onTap: () => _escolher(
              context,
              titulo: 'Funis destino',
              opcoes: opcoes((t) => t.toTeam),
              marcados: _destinos,
            ),
          ),
        ],
      ),
    );
  }

  Widget _linhaFiltro(
    BuildContext context, {
    required IconData icone,
    required String rotulo,
    required Set<String> marcados,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final secundaria = ThemeHelpers.textSecondaryColor(context);
    final valor = marcados.isEmpty
        ? 'Todos'
        : marcados.length == 1
            ? marcados.first
            : '${marcados.length} marcados';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Icon(icone, size: 15, color: secundaria),
            const SizedBox(width: 8),
            Text(
              rotulo,
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                valor,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: marcados.isEmpty
                      ? secundaria
                      : ThemeHelpers.textColor(context),
                  fontWeight:
                      marcados.isEmpty ? FontWeight.w600 : FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(LucideIcons.chevronRight, size: 16, color: secundaria),
          ],
        ),
      ),
    );
  }

  Future<void> _escolher(
    BuildContext context, {
    required String titulo,
    required List<String> opcoes,
    required Set<String> marcados,
  }) async {
    final escolha = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black54,
      backgroundColor: Colors.transparent,
      builder: (_) => _EscolhaMultipla(
        titulo: titulo,
        opcoes: opcoes,
        iniciais: marcados,
      ),
    );
    if (escolha == null || !mounted) return;
    setState(() {
      marcados
        ..clear()
        ..addAll(escolha);
      _recomecarLista();
    });
  }

  /// Totais de uma dimensão da transferência (os cards de resumo do web).
  Widget _secaoGrupos(
    BuildContext context,
    String titulo,
    List<SdrLabelCount> grupos,
    int total,
    Color tom,
  ) {
    final theme = Theme.of(context);
    final aberta = _secoesAbertas.contains(titulo);
    final visiveis =
        aberta ? grupos : grupos.take(_kGruposResumo).toList(growable: false);
    final maior = grupos.isEmpty || grupos.first.count <= 0
        ? 1
        : grupos.first.count;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tituloCaixaAlta(context, titulo),
          const SizedBox(height: 6),
          if (grupos.isEmpty)
            Text(
              'Sem dados neste recorte.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
          for (final g in visiveis)
            _LinhaGrupo(
              rotulo: g.label,
              contagem: g.count,
              fatia: g.count / total,
              barra: g.count / maior,
              tom: tom,
              marcado: false,
            ),
          if (grupos.length > _kGruposResumo)
            _verMais(
              context,
              aberto: aberta,
              total: grupos.length,
              onTap: () => setState(() {
                if (!_secoesAbertas.remove(titulo)) _secoesAbertas.add(titulo);
              }),
            ),
        ],
      ),
    );
  }

  /// Tabela cruzada do web (origem → destino) em linhas: cada origem em
  /// ordem alfabética, seus destinos do maior para o menor e o subtotal.
  Widget _cruzamento(
    BuildContext context,
    String titulo,
    List<SdrFluxo> fluxos, {
    String? nota,
  }) {
    final theme = Theme.of(context);
    final secundaria = ThemeHelpers.textSecondaryColor(context);
    final porOrigem = <String, List<SdrFluxo>>{};
    for (final f in fluxos) {
      (porOrigem[f.origem] ??= <SdrFluxo>[]).add(f);
    }
    final origens = porOrigem.keys.toList()..sort(_comparar);
    final estiloValor = theme.textTheme.bodySmall?.copyWith(
      color: ThemeHelpers.textColor(context),
      fontWeight: FontWeight.w900,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tituloCaixaAlta(context, titulo),
          if (nota != null) ...[
            const SizedBox(height: 2),
            Text(
              nota,
              style: theme.textTheme.labelSmall?.copyWith(color: secundaria),
            ),
          ],
          const SizedBox(height: 6),
          if (origens.isEmpty)
            Text(
              'Nenhum dado de cruzamento neste recorte.',
              style: theme.textTheme.bodySmall?.copyWith(color: secundaria),
            ),
          for (var i = 0; i < origens.length; i++) ...[
            if (i > 0) Container(height: 1, color: SdrTom.trilho(context)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    origens[i],
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textColor(context),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  for (final f in (porOrigem[origens[i]]!
                    ..sort((a, b) => b.contagem.compareTo(a.contagem))))
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(
                              LucideIcons.arrowRight,
                              size: 12,
                              color: secundaria,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              f.destino,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: ThemeHelpers.textColor(context),
                                height: 1.3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(sdrInt(f.contagem), style: estiloValor),
                        ],
                      ),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          'Subtotal enviado de «${origens[i]}»',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: secundaria,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        sdrInt(porOrigem[origens[i]]!
                            .fold<int>(0, (s, f) => s + f.contagem)),
                        style: estiloValor,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Peças da folha ───────────────────────────────────────────────────────

  Widget _tituloCaixaAlta(BuildContext context, String texto) {
    return Text(
      texto.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            fontWeight: FontWeight.w900,
            letterSpacing: 1.0,
            height: 1.35,
          ),
    );
  }

  /// "Agrupar por" do web como opções com sublinhado (rolam quando não
  /// cabem).
  Widget _agruparPor(
    BuildContext context, {
    required List<String> opcoes,
    required int ativa,
    required Color tom,
    required ValueChanged<int> onTap,
  }) {
    final theme = Theme.of(context);
    final tinta = SdrTom.texto(context, tom);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tituloCaixaAlta(context, 'Agrupar por'),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < opcoes.length; i++)
                  InkWell(
                    onTap: i == ativa ? null : () => onTap(i),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(2, 8, 12, 7),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: i == ativa ? tinta : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Text(
                        opcoes[i],
                        maxLines: 1,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: i == ativa
                              ? tinta
                              : ThemeHelpers.textSecondaryColor(context),
                          fontWeight:
                              i == ativa ? FontWeight.w900 : FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Resumo por grupo que filtra a lista (vários grupos de uma vez).
  Widget _resumo(
    BuildContext context, {
    String? titulo,
    String? dica,
    required List<_Grupo> grupos,
    required int total,
    required Set<String> marcados,
    required Color Function(String) tomDo,
    required ValueChanged<String> onToggle,
  }) {
    final theme = Theme.of(context);
    final base = total <= 0 ? 1 : total;
    final maior = grupos.isEmpty || grupos.first.contagem <= 0
        ? 1
        : grupos.first.contagem;
    final visiveis = _gruposAbertos
        ? grupos
        : grupos.take(_kGruposResumo).toList(growable: false);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (titulo != null) _tituloCaixaAlta(context, titulo),
          if (dica != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                dica,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  height: 1.35,
                ),
              ),
            ),
          const SizedBox(height: 6),
          for (final g in visiveis)
            InkWell(
              onTap: () => onToggle(g.rotulo),
              child: _LinhaGrupo(
                rotulo: g.rotulo,
                contagem: g.contagem,
                fatia: g.contagem / base,
                barra: g.contagem / maior,
                tom: tomDo(g.rotulo),
                marcado: marcados.contains(g.rotulo),
              ),
            ),
          if (grupos.length > _kGruposResumo)
            _verMais(
              context,
              aberto: _gruposAbertos,
              total: grupos.length,
              onTap: () => setState(() => _gruposAbertos = !_gruposAbertos),
            ),
        ],
      ),
    );
  }

  Widget _verMais(
    BuildContext context, {
    required bool aberto,
    required int total,
    required VoidCallback onTap,
  }) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: ThemeHelpers.textSecondaryColor(context),
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
        ),
        icon: Icon(
          aberto ? LucideIcons.chevronUp : LucideIcons.chevronDown,
          size: 15,
        ),
        label: Text(
          aberto ? 'Ver menos' : 'Ver os ${sdrInt(total)}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _cabecalhoLista(
    BuildContext context, {
    required int mostrando,
    int? total,
    bool filtrado = false,
    VoidCallback? onLimpar,
    String singular = 'lead',
    String plural = 'leads',
  }) {
    final theme = Theme.of(context);
    final quantos =
        mostrando == 1 ? '1 $singular' : '${sdrInt(mostrando)} $plural';
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: SdrTom.trilho(context))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: quantos),
                  if (filtrado && total != null)
                    TextSpan(
                      text: ' · ${sdrInt(total)} no total',
                      style: TextStyle(
                        color: ThemeHelpers.textSecondaryColor(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              maxLines: 2,
              style: theme.textTheme.labelLarge?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (filtrado && onLimpar != null)
            TextButton(
              onPressed: onLimpar,
              style: TextButton.styleFrom(
                foregroundColor: ThemeHelpers.textSecondaryColor(context),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text(
                'Mostrar todos',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }

  /// O lote visível da lista, já como cartões.
  Iterable<Widget> _cartoes(
    List<SdrLeadRow> lista,
    Widget Function(SdrLeadRow, bool ultima) cartao,
  ) {
    final n = lista.length > _visiveis ? _visiveis : lista.length;
    return [for (var i = 0; i < n; i++) cartao(lista[i], i == n - 1)];
  }

  void _abrir(BuildContext context, String? taskId) {
    final id = _texto(taskId);
    if (id == null) return;
    Navigator.of(context).pushNamed(AppRoutes.kanbanTaskDetails(id));
  }

  // ─── Cartões (os campos do web) ───────────────────────────────────────────

  Widget _cartaoPeriodo(BuildContext context, SdrLeadRow r, bool ultima) {
    final tom = _tomDoEstado(context, r.stateLabel);
    return _Cartao(
      titulo: r.title,
      cabecalho: _Estado(
        texto: r.stateLabel ?? 'Em qualificação',
        tom: tom,
        icone: r.stateLabel == 'Perdido'
            ? LucideIcons.circleX
            : LucideIcons.hourglass,
      ),
      linhas: [
        [('SDR', _rotulo(r.agentName))],
        [('Funil', _rotulo(r.funnel)), ('Etapa', _rotulo(r.columnTitle))],
        [('Fonte', _rotulo(r.source)), ('Camp.', _rotulo(r.campaign))],
        [('Entrada', _dataHora(r.createdAt ?? r.date))],
      ],
      onTap: () => _abrir(context, r.taskId),
      ultima: ultima,
    );
  }

  Widget _cartaoQualificacao(
    BuildContext context,
    SdrLeadRow r,
    bool ultima,
    Color tom,
  ) {
    final theme = Theme.of(context);
    return _Cartao(
      titulo: r.title,
      cabecalho: Text(
        'SDR: ${_rotulo(r.agentName)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium?.copyWith(
          color: SdrTom.texto(context, tom),
          fontWeight: FontWeight.w900,
        ),
      ),
      linhas: [
        [('Funil', _rotulo(r.funnel)), ('Etapa', _rotulo(r.columnTitle))],
        [('Qualific.', _rotulo(r.qualification))],
        [('Fonte / camp.', '${_rotulo(r.source)} · ${_rotulo(r.campaign)}')],
        [
          ('Entrada', _dataHora(r.createdAt ?? r.date)),
          ('Prazo', _dataHora(r.dueDate)),
        ],
      ],
      onTap: () => _abrir(context, r.taskId),
      ultima: ultima,
    );
  }

  Widget _cartaoPerda(BuildContext context, SdrLeadRow r, bool ultima) {
    return _Cartao(
      titulo: r.title,
      linhas: [
        [('SDR', _rotulo(r.agentName))],
        [('Motivo', _motivo(r.lossReason))],
        [
          ('Funil', _rotulo(r.funnel)),
          ('Etapa (perda)', _rotulo(r.columnTitle)),
        ],
        [('Fonte', _rotulo(r.source))],
        [('Perdido em', _dataHora(r.date))],
      ],
      onTap: () => _abrir(context, r.taskId),
      ultima: ultima,
    );
  }

  Widget _cartaoTransferencia(
    BuildContext context,
    SdrLeadRow r,
    bool ultima,
  ) {
    final theme = Theme.of(context);
    final forte = TextStyle(
      color: ThemeHelpers.textColor(context),
      fontWeight: FontWeight.w900,
    );
    final estiloLink = TextButton.styleFrom(
      foregroundColor: ThemeHelpers.textColor(context),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(0, 34),
      side: BorderSide(color: ThemeHelpers.borderColor(context)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
    );
    return _Cartao(
      titulo: r.title,
      cabecalho: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: _rotulo(r.fromTeam), style: forte),
            const TextSpan(text: '  →  '),
            TextSpan(text: _rotulo(r.toTeam), style: forte),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium?.copyWith(
          color: SdrTom.texto(context, SdrTom.transferido(context)),
        ),
      ),
      linhas: [
        [('SDR', _rotulo(r.agentName)), ('Corretor', _rotulo(r.assignedTo))],
        [('Transferido por', _rotulo(r.transferredBy)), (null, _dataHora(r.date))],
        [('Fonte / camp.', '${_rotulo(r.source)} · ${_rotulo(r.campaign)}')],
        [('Etapa atual', _rotulo(r.columnTitle))],
      ],
      acoes: [
        if (_texto(r.originalTaskId) != null)
          TextButton.icon(
            onPressed: () => _abrir(context, r.originalTaskId),
            style: estiloLink,
            icon: const Icon(LucideIcons.externalLink, size: 13),
            label: const Text(
              'Card do SDR',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
        if (_texto(r.duplicatedTaskId) != null)
          TextButton.icon(
            onPressed: () => _abrir(context, r.duplicatedTaskId),
            style: estiloLink,
            icon: const Icon(LucideIcons.externalLink, size: 13),
            label: const Text(
              'Card do corretor',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
      ],
      ultima: ultima,
    );
  }

  // ─── Estados da folha ─────────────────────────────────────────────────────

  Widget _vazio(BuildContext context, String texto) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      child: Column(
        children: [
          Icon(
            LucideIcons.inbox,
            size: 28,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
          const SizedBox(height: 10),
          Text(
            texto,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _mais(BuildContext context, int total) {
    final mostrando = total > _visiveis ? _visiveis : total;
    if (mostrando >= total) return const SizedBox(height: 8);
    final theme = Theme.of(context);
    final proximo = (total - mostrando) < _kLote ? total - mostrando : _kLote;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          Text(
            'Mostrando ${sdrInt(mostrando)} de ${sdrInt(total)}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => setState(() => _visiveis += _kLote),
            style: OutlinedButton.styleFrom(
              foregroundColor: ThemeHelpers.textColor(context),
              side: BorderSide(color: ThemeHelpers.borderColor(context)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              minimumSize: const Size(0, 42),
              padding: const EdgeInsets.symmetric(horizontal: 18),
            ),
            icon: const Icon(LucideIcons.chevronDown, size: 16),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Carregar mais ${sdrInt(proximo)}',
                maxLines: 1,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Esqueleto fiel ao cartão, com o aviso de que a lista completa pode
  /// demorar (a consulta com as listas é pesada — até 2 minutos).
  Widget _esqueleto(BuildContext context, double fundo) {
    final theme = Theme.of(context);
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 14, 16, fundo),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              LucideIcons.hourglass,
              size: 14,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Buscando a lista completa. Em empresa grande isso pode levar até 2 minutos.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < 6; i++) ...[
          const Row(
            children: [
              Expanded(child: SkeletonText(width: 170, height: 13)),
              SizedBox(width: 12),
              SkeletonText(width: 40, height: 10),
            ],
          ),
          const SizedBox(height: 8),
          const SkeletonText(width: 120, height: 10),
          const SizedBox(height: 6),
          const SkeletonText(width: 230, height: 10),
          const SizedBox(height: 6),
          const SkeletonText(width: 190, height: 10),
          const SizedBox(height: 14),
          Container(height: 1, color: SdrTom.trilho(context)),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

// ─── Linha de grupo (resumo e totais) ────────────────────────────────────────

class _LinhaGrupo extends StatelessWidget {
  const _LinhaGrupo({
    required this.rotulo,
    required this.contagem,
    required this.fatia,
    required this.barra,
    required this.tom,
    required this.marcado,
  });

  final String rotulo;
  final int contagem;

  /// Participação no total (0–1) — vira o percentual.
  final double fatia;

  /// Tamanho da barra em relação ao maior grupo (0–1).
  final double barra;
  final Color tom;
  final bool marcado;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tinta = SdrTom.texto(context, tom);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (marcado) ...[
                Icon(LucideIcons.check, size: 14, color: tinta),
                const SizedBox(width: 5),
              ],
              Expanded(
                child: Text(
                  rotulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: marcado ? tinta : ThemeHelpers.textColor(context),
                    fontWeight: marcado ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                sdrInt(contagem),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textColor(context),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 46,
                child: Text(
                  sdrPct(fatia * 100),
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          SdrTrilho(fracao: barra, cor: tom, altura: 5),
        ],
      ),
    );
  }
}

// ─── Estado do lead (ícone + palavra na cor do estado) ───────────────────────

class _Estado extends StatelessWidget {
  const _Estado({required this.texto, required this.tom, required this.icone});

  final String texto;
  final Color tom;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    final tinta = SdrTom.texto(context, tom);
    return Row(
      children: [
        Icon(icone, size: 13, color: tinta),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: tinta,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
      ],
    );
  }
}

// ─── Cartão de lead (linha flush) ────────────────────────────────────────────

/// Título, uma linha de destaque (estado, SDR ou origem → destino), linhas
/// "Rótulo: valor" com os campos do web e, quando há, ações. Toque abre o
/// card quando [onTap] existe (a transferência tem dois cards: botões).
class _Cartao extends StatelessWidget {
  const _Cartao({
    required this.titulo,
    required this.linhas,
    required this.ultima,
    this.cabecalho,
    this.acoes = const [],
    this.onTap,
  });

  final String titulo;
  final Widget? cabecalho;
  final List<List<_Par>> linhas;
  final List<Widget> acoes;
  final VoidCallback? onTap;
  final bool ultima;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secundaria = ThemeHelpers.textSecondaryColor(context);
    final forte = TextStyle(
      color: ThemeHelpers.textColor(context),
      fontWeight: FontWeight.w800,
    );
    final estilo = theme.textTheme.labelSmall?.copyWith(
      color: secundaria,
      fontSize: 11.5,
      height: 1.4,
    );

    List<InlineSpan> spans(List<_Par> linha) => [
          for (var i = 0; i < linha.length; i++) ...[
            if (i > 0) const TextSpan(text: ' · '),
            if (linha[i].$1 != null)
              TextSpan(text: '${linha[i].$1}: ', style: forte),
            TextSpan(text: linha[i].$2),
          ],
        ];

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        decoration: BoxDecoration(
          border: ultima
              ? null
              : Border(bottom: BorderSide(color: SdrTom.trilho(context))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    titulo,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: ThemeHelpers.textColor(context),
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                    ),
                  ),
                  if (cabecalho != null) ...[
                    const SizedBox(height: 4),
                    cabecalho!,
                  ],
                  for (final linha in linhas) ...[
                    const SizedBox(height: 3),
                    Text.rich(
                      TextSpan(children: spans(linha)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: estilo,
                    ),
                  ],
                  if (acoes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 6, children: acoes),
                  ],
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  LucideIcons.chevronRight,
                  size: 16,
                  color: secundaria.withValues(alpha: 0.7),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Escolha de várias opções (funis de origem / destino) ────────────────────

class _EscolhaMultipla extends StatefulWidget {
  const _EscolhaMultipla({
    required this.titulo,
    required this.opcoes,
    required this.iniciais,
  });

  final String titulo;
  final List<String> opcoes;
  final Set<String> iniciais;

  @override
  State<_EscolhaMultipla> createState() => _EscolhaMultiplaState();
}

class _EscolhaMultiplaState extends State<_EscolhaMultipla> {
  late final Set<String> _marcados = Set<String>.from(widget.iniciais);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.of(context);
    final secundaria = ThemeHelpers.textSecondaryColor(context);
    final verde = SdrTom.texto(context, SdrTom.transferido(context));
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: mq.size.height * 0.7),
      child: Material(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 6, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.titulo,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(LucideIcons.x, size: 20, color: secundaria),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: SdrTom.trilho(context)),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  for (final o in widget.opcoes)
                    InkWell(
                      onTap: () => setState(() {
                        if (!_marcados.remove(o)) _marcados.add(o);
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 11,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _marcados.contains(o)
                                  ? LucideIcons.squareCheck
                                  : LucideIcons.square,
                              size: 18,
                              color: _marcados.contains(o) ? verde : secundaria,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                o,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: ThemeHelpers.textColor(context),
                                  fontWeight: _marcados.contains(o)
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(height: 1, color: SdrTom.trilho(context)),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + mq.padding.bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _marcados.isEmpty
                        ? 'Nada marcado · vale para todos'
                        : _marcados.length == 1
                            ? '1 marcado'
                            : '${_marcados.length} marcados',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: secundaria,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => setState(_marcados.clear),
                          style: TextButton.styleFrom(
                            foregroundColor: secundaria,
                            minimumSize: const Size(0, 44),
                          ),
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'Limpar',
                              maxLines: 1,
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () =>
                              Navigator.of(context).pop(Set<String>.from(_marcados)),
                          style: FilledButton.styleFrom(
                            backgroundColor: verde,
                            foregroundColor:
                                ThemeHelpers.onPrimaryColor(context),
                            minimumSize: const Size(0, 44),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'Aplicar',
                              maxLines: 1,
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
