import '../../core/finance_format.dart';
import 'meu_financeiro_models.dart';

Map<String, dynamic> _map(dynamic v) => v is Map
    ? v.map((k, val) => MapEntry(k.toString(), val))
    : <String, dynamic>{};

String? _str(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

List<Map<String, dynamic>> _maps(dynamic v) =>
    (v is List ? v : const []).whereType<Map>().map(_map).toList();

List<String> _strings(dynamic v) => (v is List ? v : const [])
    .map((e) => e?.toString().trim() ?? '')
    .where((s) => s.isNotEmpty)
    .toList();

// ─── GET /repasses/broker-dashboard/vendas/:saleId ──────────────────────────
// `venda-consulta.service.ts:57-82`; web `DrawerVendaConsulta.tsx`.

class VendaParcela {
  final int numero;
  final double valor;
  final String? previstaPara;
  final String? recebidaEm;
  final String status;
  const VendaParcela({
    required this.numero,
    required this.valor,
    required this.status,
    this.previstaPara,
    this.recebidaEm,
  });
}

class VendaParticipante {
  final String brokerId;
  final String? nome;
  final List<({String papel, double? percentual})> papeis;

  /// `null` = fora do seu escopo (não é da sua conta).
  final EarningsTotals? totais;

  const VendaParticipante({
    required this.brokerId,
    this.nome,
    this.papeis = const [],
    this.totais,
  });
}

class VendaConsulta {
  final String saleId;
  final String? fichaVenda;
  final String status;
  final String? saleDate;
  final String? saleType;
  final String? empreendimento;
  final String? endereco;
  final String? unidade;
  final String? incorporadora;
  final List<String> compradores;
  final List<String> vendedores;
  final List<String> empresas;
  final double vgv;
  final double? vgc;
  final double? comissaoPct;
  final List<VendaParcela> parcelas;
  final List<VendaParticipante> participantes;

  const VendaConsulta({
    required this.saleId,
    required this.status,
    this.fichaVenda,
    this.saleDate,
    this.saleType,
    this.empreendimento,
    this.endereco,
    this.unidade,
    this.incorporadora,
    this.compradores = const [],
    this.vendedores = const [],
    this.empresas = const [],
    this.vgv = 0,
    this.vgc,
    this.comissaoPct,
    this.parcelas = const [],
    this.participantes = const [],
  });

  factory VendaConsulta.fromJson(Map<String, dynamic> j) {
    final imovel = _map(j['imovel']);
    final valores = _map(j['valores']);
    return VendaConsulta(
      saleId: j['saleId']?.toString() ?? '',
      fichaVenda: _str(j['fichaVenda']),
      status: j['status']?.toString() ?? '',
      saleDate: _str(j['saleDate']),
      saleType: _str(j['saleType']),
      empreendimento: _str(imovel['empreendimento']),
      endereco: _str(imovel['endereco']),
      unidade: _str(imovel['unidade']),
      incorporadora: _str(imovel['incorporadora']),
      compradores: _strings(j['compradores']),
      vendedores: _strings(j['vendedores']),
      empresas: _strings(j['empresas']),
      vgv: financeNum(valores['vgv']),
      vgc: financeNumOrNull(valores['vgc']),
      comissaoPct: financeNumOrNull(valores['comissaoPct']),
      parcelas: _maps(j['parcelas'])
          .map(
            (p) => VendaParcela(
              numero: (p['numero'] as num?)?.toInt() ?? 0,
              valor: financeNum(p['valor']),
              previstaPara: _str(p['previstaPara']),
              recebidaEm: _str(p['recebidaEm']),
              status: p['status']?.toString() ?? '',
            ),
          )
          .toList(),
      participantes: _maps(j['participantes'])
          .map(
            (p) => VendaParticipante(
              brokerId: p['brokerId']?.toString() ?? '',
              nome: _str(p['nome']),
              papeis: _maps(p['papeis'])
                  .map(
                    (x) => (
                      papel: x['papel']?.toString() ?? '',
                      percentual: financeNumOrNull(x['percentual']),
                    ),
                  )
                  .toList(),
              totais: p['totais'] is Map
                  ? EarningsTotals.fromJson(_map(p['totais']))
                  : null,
            ),
          )
          .toList(),
    );
  }

  /// `rotuloDaVenda`: empreendimento → endereço → comprador → ficha → id.
  String get titulo =>
      empreendimento ??
      endereco ??
      (compradores.isNotEmpty ? compradores.first : null) ??
      (fichaVenda != null ? 'Ficha $fichaVenda' : null) ??
      (saleId.isEmpty ? '—' : saleId);
}

/// `SALE_STATUS_LABELS` (`vendasConstants.ts:11-18`).
String saleStatusLabel(String s) {
  const labels = {
    'WAITING_FOR_SIGNATURE': 'Aguardando assinatura',
    'EM_CONFERENCIA': 'Em conferência',
    'PENDING': 'A vencer',
    'RECEIVED': 'Recebido',
    'OVERDUE': 'Em atraso',
    'CANCELLED': 'Cancelado',
  };
  return labels[s] ?? humanizeFinanceCode(s);
}

/// `papelNaVenda.ts:2-11` (+ SDR/pré-atendimento do drawer da origem).
String papelNaVendaLabel(String? papel) {
  switch ((papel ?? '').toUpperCase()) {
    case 'CORRETOR':
      return 'Corretor';
    case 'CAPTADOR':
      return 'Captador';
    case 'GESTOR':
    case 'GERENTE':
      return 'Gerente';
    case 'GESTOR_EM_TREINAMENTO':
      return 'Gerente em treinamento';
    case 'DIRETOR':
      return 'Diretor';
    case 'ATENDENTE':
    case 'SDR':
      return 'SDR / atendente';
    case 'PRE_ATENDIMENTO':
      return 'Pré-atendimento';
    case 'OUTROS':
      return 'Outros';
    default:
      return 'Participante';
  }
}

/// Código cru → texto ("EM_ANALISE" → "Em analise"); nunca o código.
String humanizeFinanceCode(String code) {
  final s = code.trim().toLowerCase().replaceAll('_', ' ');
  if (s.isEmpty) return '—';
  return '${s[0].toUpperCase()}${s.substring(1)}';
}

// ─── GET /repasses/:id/origem ───────────────────────────────────────────────
// `repasse-origem.service.ts:120-137,342-414`; web `DrawerOrigemRepasse.tsx`.

class RepasseOrigem {
  final String repasseId;
  final String status;
  final String origem; // venda | titulo
  final String? saleId;
  final String? ficha;
  final String? empreendimento;
  final String? unidade;
  final String? comprador;
  final String? dataVenda;
  final String? empresa;
  final String? tituloCodigo;
  final String? tituloDescricao;
  final String? tituloCliente;
  final int? parcelaNumero;
  final int totalDeParcelas;
  final double valorDaParcela;
  final String? previstaPara;
  final String? recebidaEm;
  final String? contaQueRecebeu;
  final double totalDaParcela;
  final String? meuPapel;
  final double? meuPercentual;
  final double meuValorBruto;
  final double? nfPercent;
  final double nfValor;
  final double retido;
  final double liquido;
  final double bonusValue;
  final List<({int numero, String? previstaPara, double meuValor, String status})>
  aindaVem;
  final double totalAReceber;
  final double aDescontar;

  const RepasseOrigem({
    required this.repasseId,
    required this.status,
    this.origem = 'venda',
    this.saleId,
    this.ficha,
    this.empreendimento,
    this.unidade,
    this.comprador,
    this.dataVenda,
    this.empresa,
    this.tituloCodigo,
    this.tituloDescricao,
    this.tituloCliente,
    this.parcelaNumero,
    this.totalDeParcelas = 0,
    this.valorDaParcela = 0,
    this.previstaPara,
    this.recebidaEm,
    this.contaQueRecebeu,
    this.totalDaParcela = 0,
    this.meuPapel,
    this.meuPercentual,
    this.meuValorBruto = 0,
    this.nfPercent,
    this.nfValor = 0,
    this.retido = 0,
    this.liquido = 0,
    this.bonusValue = 0,
    this.aindaVem = const [],
    this.totalAReceber = 0,
    this.aDescontar = 0,
  });

  factory RepasseOrigem.fromJson(Map<String, dynamic> j) {
    final venda = _map(j['venda']);
    final titulo = j['titulo'] is Map ? _map(j['titulo']) : null;
    final parcela = _map(j['parcela']);
    final comissao = _map(j['comissao']);
    final descontos = _map(j['descontos']);
    final bonus = _map(j['bonificacao']);
    final ainda = _map(j['aindaVem']);
    return RepasseOrigem(
      repasseId: j['repasseId']?.toString() ?? '',
      status: j['status']?.toString() ?? '',
      origem: j['origem']?.toString() ?? 'venda',
      saleId: _str(venda['saleId']),
      ficha: _str(venda['ficha']),
      empreendimento: _str(venda['empreendimento']),
      unidade: _str(venda['unidade']),
      comprador: _str(venda['comprador']),
      dataVenda: _str(venda['dataVenda']),
      empresa: _str(venda['empresa']) ?? _str(titulo?['empresa']),
      tituloCodigo: _str(titulo?['codigo']),
      tituloDescricao: _str(titulo?['descricao']),
      tituloCliente: _str(titulo?['cliente']),
      parcelaNumero: (parcela['numero'] as num?)?.toInt(),
      totalDeParcelas: (parcela['totalDeParcelas'] as num?)?.toInt() ?? 0,
      valorDaParcela: financeNum(parcela['valorDaParcela']),
      previstaPara: _str(parcela['previstaPara']),
      recebidaEm: _str(parcela['recebidaEm']),
      contaQueRecebeu: _str(parcela['contaQueRecebeu']),
      totalDaParcela: financeNum(comissao['totalDaParcela']),
      meuPapel: _str(comissao['meuPapel']),
      meuPercentual: financeNumOrNull(comissao['meuPercentual']),
      meuValorBruto: financeNum(comissao['meuValorBruto']),
      nfPercent: financeNumOrNull(descontos['nfPercent']),
      nfValor: financeNum(descontos['nfValor']),
      retido: financeNum(descontos['retido']),
      liquido: financeNum(descontos['liquido']),
      bonusValue: financeNum(bonus['bonusValue']),
      aindaVem: _maps(ainda['parcelas'])
          .map(
            (p) => (
              numero: (p['numero'] as num?)?.toInt() ?? 0,
              previstaPara: _str(p['previstaPara']),
              meuValor: financeNum(p['meuValor']),
              status: p['status']?.toString() ?? '',
            ),
          )
          .toList(),
      totalAReceber: financeNum(ainda['totalAReceber']),
      aDescontar: financeNum(ainda['aDescontar']),
    );
  }
}

// ─── GET /repasses/broker-dashboard/assinaturas ─────────────────────────────

class AssinaturaFicha {
  final String saleId;
  final String? brokerName;
  final String? fichaVenda;
  final String? propertyName;
  final String? unit;
  final String? propertyAddress;
  final String? clientName;
  final int parcelas;
  final double valor;

  const AssinaturaFicha({
    required this.saleId,
    this.brokerName,
    this.fichaVenda,
    this.propertyName,
    this.unit,
    this.propertyAddress,
    this.clientName,
    this.parcelas = 0,
    this.valor = 0,
  });

  factory AssinaturaFicha.fromJson(Map<String, dynamic> j) => AssinaturaFicha(
    saleId: j['saleId']?.toString() ?? '',
    brokerName: _str(j['brokerName']),
    fichaVenda: _str(j['fichaVenda']),
    propertyName: _str(j['propertyName']),
    unit: _str(j['unit']),
    propertyAddress: _str(j['propertyAddress']),
    clientName: _str(j['clientName']),
    parcelas: (j['parcelas'] as num?)?.toInt() ?? 0,
    valor: financeNum(j['valor']),
  );

  String get title =>
      propertyName ??
      propertyAddress ??
      clientName ??
      (fichaVenda != null ? 'Ficha $fichaVenda' : 'Venda');

  String get subtitle => [
    // O cliente só vai aqui quando o título já é o imóvel.
    if (propertyName != null || propertyAddress != null) ?clientName,
    if (unit != null) 'Un. $unit',
    ?fichaVenda,
  ].join(' · ');
}

// ─── Status rail e clique no mês (MeuFinanceiroPage.tsx:274-287,705-714) ────

/// Opções do rail "Status" da visão a-receber (o back atual sempre manda
/// `totals.travado`, então "Aguardando assinatura" fica de fora).
const List<(String, String)> kProximosStatusRail = [
  ('EM_CONFERENCIA', 'Em conferência'),
  ('PENDING', 'Pendente'),
  ('APPROVED', 'Aprovado'),
];

/// Recorte de um mês clicado no gráfico: `[1º dia, último dia]`; o mês
/// CORRENTE abre o início (`from` nulo) para incluir os atrasados.
(String?, String?) mesDoGraficoRange(String ym, DateTime today) {
  final d = DateTime.tryParse('$ym-01');
  if (d == null) return (null, null);
  final fim = DateTime(d.year, d.month + 1, 0);
  final atual = d.year == today.year && d.month == today.month;
  return (
    atual ? null : financeQueryDate(DateTime(d.year, d.month, 1)),
    financeQueryDate(fim),
  );
}

/// Janela do gráfico no celular: 6 meses para trás e 5 à frente do mês
/// atual (o back manda 12 para trás e 6 à frente).
List<MonthlyEarning> janelaDoGrafico(
  List<MonthlyEarning> mensal,
  DateTime today, {
  int antes = 6,
  int depois = 5,
}) {
  final ini = DateTime(today.year, today.month - antes, 1);
  final fim = DateTime(today.year, today.month + depois, 1);
  String key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
  final a = key(ini);
  final b = key(fim);
  return mensal
      .where((m) => m.month.compareTo(a) >= 0 && m.month.compareTo(b) <= 0)
      .toList();
}
