import '../core/finance_format.dart';

Map<String, dynamic> _map(dynamic v) => v is Map
    ? v.map((k, val) => MapEntry(k.toString(), val))
    : <String, dynamic>{};

String? _str(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/// Item da fila (`approvalsApi.ts:63-112`).
class ApprovalItem {
  final String source; // PAYABLE | REQUEST | ADVANCE | DEAL_COST | REPASSE
  final String id;
  final String? code;
  final String title;
  final String? companyName;
  final String? counterparty;
  final double amount;
  final String? dueDate;
  final String? createdAt;
  final String? requestedByName;
  final String? stage;
  final bool canActByMe;
  final String? blockedReason;
  final String? priority;
  final ({int nivel, String papel})? etapaAtual;
  final List<String> possivelDuplicata;

  const ApprovalItem({
    required this.source,
    required this.id,
    required this.title,
    this.code,
    this.companyName,
    this.counterparty,
    this.amount = 0,
    this.dueDate,
    this.createdAt,
    this.requestedByName,
    this.stage,
    this.canActByMe = false,
    this.blockedReason,
    this.priority,
    this.etapaAtual,
    this.possivelDuplicata = const [],
  });

  String get key => '$source:$id';

  factory ApprovalItem.fromJson(Map<String, dynamic> j) {
    final etapa = j['etapaAtual'] is Map ? _map(j['etapaAtual']) : null;
    return ApprovalItem(
      source: j['source']?.toString() ?? '',
      id: j['id']?.toString() ?? '',
      code: _str(j['code']),
      title: j['title']?.toString() ?? '',
      companyName: _str(j['companyName']),
      counterparty: _str(j['counterparty']),
      amount: financeNum(j['amount']),
      dueDate: _str(j['dueDate']),
      createdAt: _str(j['createdAt']),
      requestedByName: _str(j['requestedByName']),
      stage: _str(j['stage']),
      canActByMe: j['canActByMe'] == true,
      blockedReason: _str(j['blockedReason']),
      priority: _str(j['priority']),
      etapaAtual: etapa == null
          ? null
          : (
              nivel: (etapa['nivel'] as num?)?.toInt() ?? 0,
              papel: etapa['papel']?.toString() ?? '',
            ),
      possivelDuplicata:
          (j['possivelDuplicata'] is List ? j['possivelDuplicata'] as List : [])
              .whereType<Map>()
              .map((e) => e['code']?.toString() ?? '')
              .where((s) => s.isNotEmpty)
              .toList(),
    );
  }
}

/// `GET /approvals/item` (`approvals.types.ts:278-316`).
class ApprovalItemDetail {
  final List<(String, String)> campos;
  final List<String> anexos;
  final List<
    ({int nivel, String papel, String status, String? aprovador, String? decididoEm, String? comentario})
  >
  cadeia;

  const ApprovalItemDetail({
    this.campos = const [],
    this.anexos = const [],
    this.cadeia = const [],
  });

  factory ApprovalItemDetail.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> maps(dynamic v) =>
        (v is List ? v : const []).whereType<Map>().map(_map).toList();
    return ApprovalItemDetail(
      campos: maps(j['campos'])
          .map((c) => (c['rotulo']?.toString() ?? '', c['valor']?.toString() ?? '—'))
          .where((c) => c.$1.isNotEmpty)
          .toList(),
      anexos: maps(j['anexos'])
          .map((a) => a['rotulo']?.toString() ?? 'Anexo')
          .toList(),
      cadeia: maps(j['cadeia'])
          .map(
            (c) => (
              nivel: (c['nivel'] as num?)?.toInt() ?? 0,
              papel: c['papel']?.toString() ?? '',
              status: c['status']?.toString() ?? '',
              aprovador: _str(c['aprovador'] is Map ? c['aprovador']['name'] : c['aprovador']),
              decididoEm: _str(c['decididoEm']),
              comentario: _str(c['comentario']),
            ),
          )
          .toList(),
    );
  }
}

/// Uma falha do lote.
class BulkFailure {
  final String source;
  final String id;
  final String error;
  final String? code;
  final List<String> suspeitos;
  const BulkFailure({
    required this.source,
    required this.id,
    required this.error,
    this.code,
    this.suspeitos = const [],
  });
  bool get duplicidade => code == 'LANCAMENTO_EM_DOBRO';
}

class BulkResult {
  final List<String> succeeded; // `source:id`
  final List<BulkFailure> failed;
  const BulkResult({this.succeeded = const [], this.failed = const []});

  BulkResult merge(BulkResult o) => BulkResult(
    succeeded: [...succeeded, ...o.succeeded],
    failed: [...failed, ...o.failed],
  );

  static BulkResult fromJson(dynamic raw) {
    final m = _map(raw);
    List<Map<String, dynamic>> maps(dynamic v) =>
        (v is List ? v : const []).whereType<Map>().map(_map).toList();
    return BulkResult(
      succeeded: maps(m['succeeded'])
          .map((s) => '${s['source']}:${s['id']}')
          .toList(),
      failed: maps(m['failed'])
          .map(
            (f) => BulkFailure(
              source: f['source']?.toString() ?? '',
              id: f['id']?.toString() ?? '',
              error: f['error']?.toString() ?? 'Falhou.',
              code: _str(f['code']),
              suspeitos: (f['suspeitos'] is List ? f['suspeitos'] as List : [])
                  .map((e) => e is Map ? (e['code'] ?? e['id']).toString() : '$e')
                  .toList(),
            ),
          )
          .toList(),
    );
  }
}

// ─── Regras puras ──────────────────────────────────────────────────────────

const Map<String, String> kApprovalSourceLabels = {
  'PAYABLE': 'Conta a pagar',
  'REQUEST': 'Solicitação',
  'ADVANCE': 'Adiantamento',
  'DEAL_COST': 'Custo de confissão',
  'REPASSE': 'Repasse',
};

String approvalSourceLabel(String s) => kApprovalSourceLabels[s] ?? s;

/// Motivo da recusa: ≥ 5 caracteres (back) e ≤ 500 (web).
String? validarMotivoRecusa(String reason) {
  final r = reason.trim();
  if (r.length < 5) {
    return 'Informe o motivo da reprovação (mínimo de 5 caracteres).';
  }
  if (r.length > 500) return 'O motivo pode ter até 500 caracteres.';
  return null;
}

/// Fatias do lote (o web manda de 10 em 10, em sequência).
List<List<T>> fatiasDoLote<T>(List<T> items, {int size = 10}) => [
  for (var i = 0; i < items.length; i += size)
    items.sublist(i, i + size > items.length ? items.length : i + size),
];

/// Adiantamento não é aprovado pelo lote (exige a taxa, um a um): separa.
({List<ApprovalItem> lote, List<ApprovalItem> adiantamentos})
separarParaAprovar(List<ApprovalItem> items) => (
  lote: items.where((i) => i.source != 'ADVANCE').toList(),
  adiantamentos: items.where((i) => i.source == 'ADVANCE').toList(),
);

/// Query da fila MEU_AVAL sem parâmetros iguais ao padrão do back
/// (`forbidNonWhitelisted`; `approvalsApi.ts:325-343`).
Map<String, Object?> meuAvalQuery({
  int page = 1,
  int pageSize = 25,
  String? search,
  String sortBy = 'dueDate',
  String sortDir = 'asc',
}) => {
  'situacao': 'MEU_AVAL',
  'page': page,
  'pageSize': pageSize,
  if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
  if (sortBy != 'dueDate') 'sortBy': sortBy,
  if (sortDir != 'asc') 'sortDir': sortDir,
};

double _round2(double v) => (v * 100).roundToDouble() / 100;

/// Valor cobrado do corretor com a taxa (`ModalAprovarAdiantamento`).
double cobradoComTaxa(double value, double feePercent) =>
    _round2(value + _round2(value * feePercent / 100));

/// Aprovar acima do saldo exige justificativa: sobra < −0,01 OU nada a
/// receber.
bool precisaJustificarTeto({
  required double saldoLivre,
  required double aReceber,
  required double cobrado,
}) => (saldoLivre - cobrado) < -0.01 || aReceber <= 0;

/// Texto do resultado do lote (`aprovacoesKit.ts:87-96`).
String resumoDoLote({
  required int ok,
  required int falhas,
  required bool aprovar,
}) {
  final verbo = aprovar ? 'aprovado' : 'recusado';
  if (falhas == 0) {
    return ok == 1 ? '1 item $verbo.' : '$ok itens ${verbo}s.';
  }
  if (ok == 0) {
    return 'Nenhum item $verbo. $falhas falha(s) — veja o motivo na lista.';
  }
  return '$ok $verbo(s), $falhas com falha — veja o motivo na lista.';
}
