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

/// Detalhe de uma estação do funil — o "abre o detalhe em cards" do web,
/// numa folha: recortes no topo, resumo agrupado e a lista de leads (toque
/// abre o card no Kanban).
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

/// Um recorte (aba) do detalhe.
class _Recorte {
  const _Recorte(this.rotulo, this.contagem);

  final String rotulo;
  final int? contagem;
}

/// Uma linha do resumo agrupado.
class _Grupo {
  const _Grupo(this.rotulo, this.contagem);

  final String rotulo;
  final int contagem;
}

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
  static const int _kGruposResumo = 5;

  ApiResponse<SdrLeadLists>? _resp;
  bool _carregando = true;

  /// Recorte escolhido (estado, leitura da perda ou dimensão da transferência).
  int _recorte = 0;

  /// Grupo escolhido no resumo — filtra a lista.
  String? _grupo;
  bool _gruposAbertos = false;
  int _visiveis = _kLote;

  static const List<String> _estados = [
    'Em qualificação',
    'Transferido',
    'Perdido',
    'Cancelado',
  ];

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

  void _trocarRecorte(int i) {
    if (i == _recorte) return;
    setState(() {
      _recorte = i;
      _grupo = null;
      _gruposAbertos = false;
      _visiveis = _kLote;
    });
  }

  // ─── Conteúdo por estação ────────────────────────────────────────────────

  ({String titulo, String subtitulo, IconData icone, Color tom}) _cabecalho(
      BuildContext context) {
    final s = widget.metricas.summary;
    switch (widget.tipo) {
      case SdrDetalheTipo.entradas:
        return (
          titulo: 'Entradas no período',
          subtitulo:
              '${sdrInt(s.totalEntries)} cards criados no funil SDR. Toque num lead para abrir o card.',
          icone: LucideIcons.logIn,
          tom: SdrTom.eixo(context),
        );
      case SdrDetalheTipo.qualificacao:
        return (
          titulo: 'Em qualificação',
          subtitulo:
              '${sdrInt(s.inQualification)} leads abertos no SDR agora, com quem está cada um.',
          icone: LucideIcons.hourglass,
          tom: SdrTom.qualificacao(context),
        );
      case SdrDetalheTipo.transferidos:
        return (
          titulo: 'Transferidos',
          subtitulo:
              '${sdrInt(s.transferred)} transferências no período, pela data do evento.',
          icone: LucideIcons.arrowRightLeft,
          tom: SdrTom.transferido(context),
        );
      case SdrDetalheTipo.perdidos:
        return (
          titulo: 'Perdidos',
          subtitulo:
              'Quem entrou no período e se perdeu, ou perdas marcadas no período.',
          icone: LucideIcons.circleX,
          tom: SdrTom.perdido(context),
        );
    }
  }

  List<_Recorte> _recortes() {
    final s = widget.metricas.summary;
    final l = _listas;
    switch (widget.tipo) {
      case SdrDetalheTipo.entradas:
        // Os estados só aparecem com a lista na mão: antes disso não dá para
        // saber quais existem, e a aba trocaria de lugar ao carregar.
        if (l == null) return const [];
        return [
          for (final r in _rotulosEntradas())
            _Recorte(
              r,
              r == 'Todos'
                  ? l.period.length
                  : l.period.where((x) => x.stateLabel == r).length,
            ),
        ];
      case SdrDetalheTipo.perdidos:
        return [
          _Recorte(
            'Entraram no período',
            l == null
                ? s.lostByEntry
                : l.period.where((r) => r.stateLabel == 'Perdido').length,
          ),
          _Recorte('Marcados no período', l == null ? s.lost : l.lost.length),
        ];
      case SdrDetalheTipo.transferidos:
        return const [
          _Recorte('Destino', null),
          _Recorte('Corretor', null),
          _Recorte('Quem transferiu', null),
          _Recorte('SDR', null),
        ];
      case SdrDetalheTipo.qualificacao:
        return const [];
    }
  }

  /// Rótulos dos recortes de "Entradas" na ordem em que aparecem (só os
  /// estados que existem na lista).
  List<String> _rotulosEntradas() {
    final l = _listas;
    return [
      'Todos',
      for (final e in _estados)
        if (l != null && l.period.any((r) => r.stateLabel == e)) e,
    ];
  }

  /// Lista do recorte atual, antes do filtro de grupo.
  List<SdrLeadRow> _base(SdrLeadLists l) {
    switch (widget.tipo) {
      case SdrDetalheTipo.entradas:
        final rotulos = _rotulosEntradas();
        final r = _recorte < rotulos.length ? rotulos[_recorte] : 'Todos';
        return r == 'Todos'
            ? l.period
            : l.period.where((x) => x.stateLabel == r).toList();
      case SdrDetalheTipo.qualificacao:
        return l.qualification;
      case SdrDetalheTipo.transferidos:
        return l.transferred;
      case SdrDetalheTipo.perdidos:
        return _recorte == 0
            ? l.period.where((x) => x.stateLabel == 'Perdido').toList()
            : l.lost;
    }
  }

  /// Chave de agrupamento de uma linha (nula = a estação não agrupa).
  String? _chave(SdrLeadRow r) {
    switch (widget.tipo) {
      case SdrDetalheTipo.qualificacao:
        return _texto(r.agentName) ?? 'Sem SDR';
      case SdrDetalheTipo.perdidos:
        if (_recorte == 1) return _motivo(r.detail) ?? 'Sem motivo';
        return _texto(r.agentName) ?? 'Sem SDR';
      case SdrDetalheTipo.entradas:
      case SdrDetalheTipo.transferidos:
        return null;
    }
  }

  String _tituloResumo() {
    switch (widget.tipo) {
      case SdrDetalheTipo.qualificacao:
        return 'Com quem está';
      case SdrDetalheTipo.perdidos:
        return _recorte == 1 ? 'Por motivo' : 'Por SDR';
      case SdrDetalheTipo.transferidos:
        return const [
          'Para qual equipe foram',
          'Corretor que recebeu',
          'Quem executou a transferência',
          'SDR dono do lead',
        ][_recorte < 0 ? 0 : (_recorte > 3 ? 3 : _recorte)];
      case SdrDetalheTipo.entradas:
        return '';
    }
  }

  List<_Grupo> _grupos(List<SdrLeadRow> base) {
    if (widget.tipo == SdrDetalheTipo.transferidos) {
      final a = widget.metricas.transferAggregates;
      final fonte = switch (_recorte) {
        0 => a.byDestinationTeam,
        1 => a.byResponsible,
        2 => a.byTransferredBy,
        _ => a.byAttendant,
      };
      return [for (final g in fonte) _Grupo(g.label, g.count)];
    }
    final conta = <String, int>{};
    for (final r in base) {
      final k = _chave(r);
      if (k == null) return const [];
      conta[k] = (conta[k] ?? 0) + 1;
    }
    final out = conta.entries.map((e) => _Grupo(e.key, e.value)).toList()
      ..sort((a, b) => b.contagem.compareTo(a.contagem));
    return out;
  }

  static String? _texto(String? v) {
    final t = v?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  static String? _motivo(String? raw) {
    final t = _texto(raw);
    if (t == null) return null;
    return KanbanLossReason.tryParse(t)?.label ?? t;
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final cab = _cabecalho(context);
    final recortes = _recortes();
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
          if (recortes.isNotEmpty) _abas(context, recortes, cab.tom),
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
            child:
                Icon(cab.icone, size: 17, color: SdrTom.texto(context, cab.tom)),
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

  /// Recortes em abas com sublinhado (rolam na horizontal quando não cabem).
  Widget _abas(BuildContext context, List<_Recorte> recortes, Color tom) {
    final theme = Theme.of(context);
    final ativo = SdrTom.texto(context, tom);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          for (var i = 0; i < recortes.length; i++)
            InkWell(
              onTap: () => _trocarRecorte(i),
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: i == _recorte ? ativo : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: recortes[i].rotulo),
                      if (recortes[i].contagem != null)
                        TextSpan(
                          text: '  ${sdrInt(recortes[i].contagem!)}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: i == _recorte
                        ? ativo
                        : ThemeHelpers.textSecondaryColor(context),
                    fontWeight: i == _recorte ? FontWeight.w800 : FontWeight.w600,
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

    final base = _base(l);
    final grupos = _grupos(base);
    final filtraPorGrupo = widget.tipo != SdrDetalheTipo.transferidos;
    final lista = (_grupo != null && filtraPorGrupo)
        ? base.where((r) => _chave(r) == _grupo).toList()
        : base;
    final mostrar = lista.length > _visiveis ? _visiveis : lista.length;

    final itens = <Widget>[
      if (grupos.isNotEmpty) ...[
        _resumo(context, grupos, tom, filtraPorGrupo),
        Container(height: 8, color: ThemeHelpers.backgroundColor(context)),
      ],
      _cabecalhoLista(context, lista.length),
    ];

    if (lista.isEmpty) {
      itens.add(_vazio(context));
    }

    return ListView.builder(
      padding: EdgeInsets.only(bottom: fundo),
      itemCount: itens.length + mostrar + 1,
      itemBuilder: (context, i) {
        if (i < itens.length) return itens[i];
        final j = i - itens.length;
        if (j < mostrar) {
          return _LinhaLead(
            lead: lista[j],
            tipo: widget.tipo,
            ultima: j == mostrar - 1,
          );
        }
        return _maisControle(context, mostrar, lista.length);
      },
    );
  }

  Widget _resumo(
    BuildContext context,
    List<_Grupo> grupos,
    Color tom,
    bool filtravel,
  ) {
    final theme = Theme.of(context);
    final secundaria = ThemeHelpers.textSecondaryColor(context);
    final maior = grupos.first.contagem <= 0 ? 1 : grupos.first.contagem;
    final visiveis = _gruposAbertos
        ? grupos
        : grupos.take(_kGruposResumo).toList(growable: false);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _tituloResumo().toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: secundaria,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
          if (filtravel)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Toque num grupo para filtrar a lista.',
                style: theme.textTheme.labelSmall?.copyWith(color: secundaria),
              ),
            ),
          const SizedBox(height: 8),
          for (final g in visiveis)
            _linhaGrupo(context, g, maior, tom, filtravel),
          if (grupos.length > _kGruposResumo)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    setState(() => _gruposAbertos = !_gruposAbertos),
                style: TextButton.styleFrom(
                  foregroundColor: secundaria,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                ),
                icon: Icon(
                  _gruposAbertos
                      ? LucideIcons.chevronUp
                      : LucideIcons.chevronDown,
                  size: 15,
                ),
                label: Text(
                  _gruposAbertos
                      ? 'Ver menos'
                      : 'Ver os ${grupos.length} grupos',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _linhaGrupo(
    BuildContext context,
    _Grupo g,
    int maior,
    Color tom,
    bool filtravel,
  ) {
    final theme = Theme.of(context);
    final escolhido = filtravel && _grupo == g.rotulo;
    final tinta = SdrTom.texto(context, tom);
    final conteudo = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (escolhido) ...[
                Icon(LucideIcons.check, size: 14, color: tinta),
                const SizedBox(width: 5),
              ],
              Expanded(
                child: Text(
                  g.rotulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color:
                        escolhido ? tinta : ThemeHelpers.textColor(context),
                    fontWeight: escolhido ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                sdrInt(g.contagem),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textColor(context),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          SdrTrilho(fracao: g.contagem / maior, cor: tom, altura: 5),
        ],
      ),
    );
    if (!filtravel) return conteudo;
    return InkWell(
      onTap: () => setState(() {
        _grupo = escolhido ? null : g.rotulo;
        _visiveis = _kLote;
      }),
      child: conteudo,
    );
  }

  Widget _cabecalhoLista(BuildContext context, int total) {
    final theme = Theme.of(context);
    final secundaria = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              total == 1 ? '1 lead' : '${sdrInt(total)} leads',
              style: theme.textTheme.labelLarge?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (_grupo != null)
            TextButton.icon(
              onPressed: () => setState(() {
                _grupo = null;
                _visiveis = _kLote;
              }),
              style: TextButton.styleFrom(
                foregroundColor: secundaria,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              icon: const Icon(LucideIcons.x, size: 14),
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 170),
                child: Text(
                  _grupo!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _vazio(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
      child: Column(
        children: [
          Icon(
            LucideIcons.inbox,
            size: 30,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
          const SizedBox(height: 10),
          Text(
            'Nenhum lead neste recorte',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Troque o recorte acima ou o período nos filtros do painel.',
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

  Widget _maisControle(BuildContext context, int mostrando, int total) {
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

  /// Esqueleto fiel à linha de lead, com o aviso de que a lista completa
  /// pode demorar (a consulta com as listas é pesada — até 2 minutos).
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

/// Uma linha de lead: quem, contato e origem, com quem está e onde, o
/// desfecho (motivo, destino ou estado) e a data. Toque abre o card.
class _LinhaLead extends StatelessWidget {
  const _LinhaLead({
    required this.lead,
    required this.tipo,
    required this.ultima,
  });

  final SdrLeadRow lead;
  final SdrDetalheTipo tipo;
  final bool ultima;

  static String? _t(String? v) {
    final s = v?.trim() ?? '';
    return s.isEmpty ? null : s;
  }

  String? _data() {
    final d = lead.date?.toLocal();
    if (d == null) return null;
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final dia = DateTime(d.year, d.month, d.day);
    final diff = hoje.difference(dia).inDays;
    if (diff == 0) return 'hoje';
    if (diff == 1) return 'ontem';
    return sdrDiaMes(d);
  }

  /// Desfecho da linha: motivo da perda, destino da transferência ou, na
  /// lista de entradas, o estado atual.
  ({IconData icone, Color tom, String texto})? _desfecho(BuildContext c) {
    final estado = lead.stateLabel;
    if (lead.detail != null && estado == 'Perdido') {
      final raw = lead.detail!.trim();
      final motivo = KanbanLossReason.tryParse(raw)?.label ?? raw;
      return (
        icone: LucideIcons.circleX,
        tom: SdrTom.perdido(c),
        texto: 'Motivo: $motivo',
      );
    }
    if (lead.detail != null && estado == 'Transferido') {
      return (
        icone: LucideIcons.arrowUpRight,
        tom: SdrTom.transferido(c),
        texto: 'Para: ${lead.detail}',
      );
    }
    if (tipo == SdrDetalheTipo.entradas && estado != null) {
      final tom = switch (estado) {
        'Transferido' => SdrTom.transferido(c),
        'Perdido' => SdrTom.perdido(c),
        'Em qualificação' => SdrTom.qualificacao(c),
        _ => ThemeHelpers.textSecondaryColor(c),
      };
      final icone = switch (estado) {
        'Transferido' => LucideIcons.arrowRightLeft,
        'Perdido' => LucideIcons.circleX,
        'Em qualificação' => LucideIcons.hourglass,
        _ => LucideIcons.ban,
      };
      return (icone: icone, tom: tom, texto: estado);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secundaria = ThemeHelpers.textSecondaryColor(context);
    final data = _data();
    final contato = [
      _t(lead.contactName) != null &&
              _t(lead.contactName) != _t(lead.title)
          ? _t(lead.contactName)
          : null,
      _t(lead.contactPhone),
      _t(lead.source),
      if (_t(lead.campaign) != null) 'camp. ${_t(lead.campaign)}',
    ].whereType<String>().join(' · ');
    final onde = [
      if (_t(lead.agentName) != null) 'SDR ${_t(lead.agentName)}',
      _t(lead.funnel),
      _t(lead.columnTitle),
    ].whereType<String>().join(' · ');
    final desfecho = _desfecho(context);
    final estilo = theme.textTheme.labelSmall?.copyWith(
      color: secundaria,
      fontSize: 11.5,
      height: 1.35,
    );

    return InkWell(
      onTap: lead.taskId.isEmpty
          ? null
          : () => Navigator.of(context)
              .pushNamed(AppRoutes.kanbanTaskDetails(lead.taskId)),
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          lead.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: ThemeHelpers.textColor(context),
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                          ),
                        ),
                      ),
                      if (data != null) ...[
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(data, style: estilo),
                        ),
                      ],
                    ],
                  ),
                  if (contato.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      contato,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: estilo,
                    ),
                  ],
                  if (onde.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      onde,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: estilo,
                    ),
                  ],
                  if (desfecho != null) ...[
                    const SizedBox(height: 5),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(
                            desfecho.icone,
                            size: 13,
                            color: SdrTom.texto(context, desfecho.tom),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            desfecho.texto,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: ThemeHelpers.textColor(context),
                              fontWeight: FontWeight.w700,
                              fontSize: 11.5,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
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
        ),
      ),
    );
  }
}
