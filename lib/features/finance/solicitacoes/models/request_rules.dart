import '../../core/finance_format.dart';
import 'request_models.dart';

/// Estado do formulário "Nova solicitação" / "Editar" (puro — testado).
/// Fonte: WEB `DrawerSolicitacaoForm.tsx:207-278,698-922`,
/// `utils/notasSolicitacao.ts`, `desfechoDaCriacao.ts`; FIN `requests.dto.ts`.
class SolicitacaoForm {
  String? companyId;
  RequestTipo? tipo;
  String? naturezaId;

  /// Grupo da natureza escolhida (vira o `type`); sem tipo, o enum direto.
  String? type;
  String title = '';
  String justification = '';
  double? amount;
  String priority = 'MEDIA';
  String? categoryId;
  String? costCenterId;
  String? supplierId;
  String department = '';
  String? paymentMethod;
  String notes = '';
  String outrosDescricao = '';
  Map<String, dynamic> camposExtras = {};
  String? creditCardId;
  DateTime? purchaseDate;
  bool cartaoParcelado = false;
  int installments = 2;
  bool rateio = false;
  List<({String? companyId, double? amount})> beneficiaries = [];
  int qtdAnexos = 0;

  bool get ehCartao => paymentMethod == 'CARTAO_CREDITO';

  /// `type` efetivo do envio.
  String get effectiveType => (type == null || type!.isEmpty) ? 'OUTROS' : type!;

  /// "Outros" sem tipo configurado exige a descrição.
  bool get exigeDescricaoOutros => tipo == null && effectiveType == 'OUTROS';

  Map<String, dynamic> toDraft() => {
    'companyId': companyId,
    'naturezaId': naturezaId,
    'type': type,
    'title': title,
    'justification': justification,
    'amount': amount,
    'priority': priority,
    'categoryId': categoryId,
    'costCenterId': costCenterId,
    'supplierId': supplierId,
    'department': department,
    'paymentMethod': paymentMethod,
    'notes': notes,
    'outrosDescricao': outrosDescricao,
    'camposExtras': camposExtras,
    'creditCardId': creditCardId,
    'purchaseDate': purchaseDate?.toIso8601String(),
    'cartaoParcelado': cartaoParcelado,
    'installments': installments,
  };

  void applyDraft(Map<String, dynamic> d) {
    String? s(String k) {
      final v = d[k];
      return v == null || v.toString().isEmpty ? null : v.toString();
    }

    companyId = s('companyId') ?? companyId;
    naturezaId = s('naturezaId');
    type = s('type');
    title = s('title') ?? '';
    justification = s('justification') ?? '';
    amount = financeNumOrNull(d['amount']);
    priority = s('priority') ?? 'MEDIA';
    categoryId = s('categoryId');
    costCenterId = s('costCenterId');
    supplierId = s('supplierId');
    department = s('department') ?? '';
    paymentMethod = s('paymentMethod');
    notes = s('notes') ?? '';
    outrosDescricao = s('outrosDescricao') ?? '';
    camposExtras = d['camposExtras'] is Map
        ? Map<String, dynamic>.from(d['camposExtras'] as Map)
        : {};
    creditCardId = s('creditCardId');
    purchaseDate = s('purchaseDate') == null
        ? null
        : DateTime.tryParse(s('purchaseDate')!);
    cartaoParcelado = d['cartaoParcelado'] == true;
    installments = (d['installments'] as num?)?.toInt() ?? 2;
  }

  bool get isEmpty =>
      title.trim().isEmpty &&
      justification.trim().isEmpty &&
      (amount ?? 0) == 0 &&
      notes.trim().isEmpty;
}

/// Validações do formulário. Devolve `{campo: mensagem}` (vazio = ok).
Map<String, String> validarSolicitacao(
  SolicitacaoForm f, {
  bool edicao = false,
}) {
  final e = <String, String>{};
  if ((f.companyId ?? '').isEmpty) e['companyId'] = 'Empresa é obrigatória';
  final tipo = f.tipo;
  if (tipo == null) {
    if ((f.type ?? '').isEmpty) e['type'] = 'Escolha o tipo da solicitação';
  } else if (tipo.base('natureza').visivel &&
      tipo.base('natureza').obrigatorio &&
      (f.naturezaId ?? '').isEmpty) {
    e['naturezaId'] = 'Escolha a natureza da solicitação.';
  }
  if (f.title.trim().isEmpty) e['title'] = 'Informe o título';
  if (f.justification.trim().isEmpty) {
    e['justification'] = 'A justificativa é obrigatória';
  }
  if ((f.amount ?? 0) <= 0) {
    e['amount'] = 'O valor solicitado deve ser maior que zero';
  }
  if (f.exigeDescricaoOutros && f.outrosDescricao.trim().isEmpty) {
    e['outrosDescricao'] = 'Descreva o que é esse "Outros"';
  }
  if (tipo != null) {
    void base(String campo, String chave, bool vazio, String msg) {
      final b = tipo.base(campo);
      if (b.visivel && b.obrigatorio && vazio) e[chave] = msg;
    }

    base(
      'fornecedor',
      'supplierId',
      (f.supplierId ?? '').isEmpty,
      'Informe o fornecedor',
    );
    base(
      'formaDePagamento',
      'paymentMethod',
      (f.paymentMethod ?? '').isEmpty,
      'Informe a forma de pagamento',
    );
    base(
      'centroDeCusto',
      'costCenterId',
      (f.costCenterId ?? '').isEmpty,
      'Informe o centro de custo',
    );
    base(
      'departamento',
      'department',
      f.department.trim().isEmpty,
      'Informe o departamento',
    );
    base(
      'observacoes',
      'notes',
      f.notes.trim().isEmpty,
      'Preencha as observações',
    );
    if (!edicao) {
      base(
        'comprovante',
        'anexos',
        f.qtdAnexos == 0,
        'Anexe o comprovante',
      );
    }
    for (final c in tipo.campos) {
      if (!c.obrigatorio || c.kind == 'SIM_NAO') continue;
      final v = f.camposExtras[c.chave];
      if (v == null || v.toString().trim().isEmpty) {
        e['campo:${c.chave}'] = 'Preencha "${c.rotulo}"';
      }
    }
  }
  if (f.ehCartao) {
    if ((f.creditCardId ?? '').isEmpty) {
      e['creditCardId'] = 'Selecione o cartão de crédito da compra.';
    }
    if (f.purchaseDate == null) {
      e['purchaseDate'] = 'Informe a data da compra no cartão.';
    }
    if (f.cartaoParcelado && (f.installments < 2 || f.installments > 24)) {
      e['installments'] = 'Parcelado: de 2 a 24 parcelas.';
    }
    if (f.rateio) {
      e['rateio'] =
          'Compra no cartão não pode ter rateio com outra empresa.';
    }
  }
  if (f.rateio && !f.ehCartao) {
    final erro = validarRateio(f.beneficiaries, f.amount ?? 0);
    if (erro != null) e['rateio'] = erro;
  }
  return e;
}

/// Soma do rateio tem de bater com o valor (±0,01).
String? validarRateio(
  List<({String? companyId, double? amount})> rows,
  double valor,
) {
  if (rows.isEmpty) return 'Inclua ao menos uma empresa no rateio.';
  for (final r in rows) {
    if ((r.companyId ?? '').isEmpty) return 'Escolha a empresa de cada linha.';
    if ((r.amount ?? 0) <= 0) return 'Cada empresa do rateio precisa de valor.';
  }
  final soma = rows.fold<double>(0, (s, r) => s + (r.amount ?? 0));
  if ((soma - valor).abs() > 0.01) {
    return 'A soma dos beneficiários deve igualar o valor solicitado';
  }
  return null;
}

/// "Outros" vai dentro de `notes` (`notasSolicitacao.ts:15-22`).
String juntarNotas(String outrosDescricao, String notes) {
  final d = outrosDescricao.trim();
  final n = notes.trim();
  if (d.isEmpty) return n;
  return n.isEmpty ? 'Tipo (Outros): $d' : 'Tipo (Outros): $d\n$n';
}

/// Inverso de [juntarNotas] (edição).
({String outros, String notes}) separarNotas(String? raw) {
  final s = raw ?? '';
  const prefix = 'Tipo (Outros): ';
  if (!s.startsWith(prefix)) return (outros: '', notes: s);
  final resto = s.substring(prefix.length);
  final i = resto.indexOf('\n');
  if (i < 0) return (outros: resto.trim(), notes: '');
  return (outros: resto.substring(0, i).trim(), notes: resto.substring(i + 1));
}

String _ymd(DateTime d) => financeQueryDate(d);

/// Corpo do POST /requests (nova) ou PATCH /requests/:id (edição).
/// Campos ocultos pelo tipo não vão; na edição não vai `tipoId`; corrigir
/// reprovada leva `companyId`, `beneficiaries` e `mensagem`.
Map<String, dynamic> buildRequestBody(
  SolicitacaoForm f, {
  bool edicao = false,
  bool corrigindoReprovada = false,
  String? mensagem,
}) {
  final tipo = f.tipo;
  bool visivel(String campo) => tipo == null || tipo.base(campo).visivel;
  final reembolso = tipo?.ehReembolso ?? false;
  final extras = <String, dynamic>{};
  f.camposExtras.forEach((k, v) {
    if (v == null) return;
    if (v is String && v.trim().isEmpty) return;
    extras[k] = v;
  });
  final body = <String, dynamic>{
    'type': f.effectiveType,
    if (!edicao && tipo != null) 'tipoId': tipo.id,
    if ((f.naturezaId ?? '').isNotEmpty) 'naturezaId': f.naturezaId,
    if (extras.isNotEmpty) 'camposExtras': extras,
    'title': f.title.trim(),
    'justification': f.justification.trim(),
    'amountRequested': double.parse((f.amount ?? 0).toStringAsFixed(2)),
    'priority': f.priority,
    if (!edicao || corrigindoReprovada) 'companyId': f.companyId,
    if (f.categoryId != null || edicao) 'categoryId': f.categoryId ?? '',
    if (visivel('centroDeCusto') && (f.costCenterId != null || edicao))
      'costCenterId': f.costCenterId ?? '',
    if (!reembolso &&
        visivel('fornecedor') &&
        (f.supplierId != null || edicao))
      'supplierId': f.supplierId ?? '',
    if (visivel('departamento') &&
        (f.department.trim().isNotEmpty || edicao))
      'department': f.department.trim(),
    if (visivel('formaDePagamento') && (f.paymentMethod != null || edicao))
      'paymentMethod': f.paymentMethod ?? '',
    'notes': juntarNotas(f.outrosDescricao, f.notes),
    if (f.ehCartao) ...{
      'creditCardId': f.creditCardId,
      'purchaseDate': f.purchaseDate == null ? null : _ymd(f.purchaseDate!),
      'installments': f.cartaoParcelado ? f.installments : 1,
    },
  };
  final mandaRateio = !edicao || corrigindoReprovada;
  if (mandaRateio && f.rateio && !f.ehCartao) {
    body['beneficiaries'] = [
      for (final b in f.beneficiaries)
        {'companyId': b.companyId, 'amount': b.amount},
    ];
  } else if (corrigindoReprovada) {
    body['beneficiaries'] = <Map<String, dynamic>>[];
  }
  if (!edicao) body['qtdAnexos'] = f.qtdAnexos;
  if (corrigindoReprovada) {
    final m = (mensagem ?? '').trim();
    if (m.isNotEmpty) body['mensagem'] = m;
  }
  return body;
}

/// Depois de timeout ou 409 no POST: a solicitação entrou? Mesmo título
/// (sem caixa/espaços), mesmo valor em centavos, mesma empresa e criada há
/// no máximo 10 min (`desfechoDaCriacao.ts:72-115`). Várias → a mais nova.
FinanceRequest? acharRecemCriada(
  List<FinanceRequest> rows, {
  required String title,
  required double amount,
  required String companyId,
  required DateTime now,
}) {
  final t = title.trim().toLowerCase();
  final cents = (amount * 100).round();
  FinanceRequest? best;
  DateTime? bestAt;
  for (final r in rows) {
    if (r.title.trim().toLowerCase() != t) continue;
    if ((r.amountRequested * 100).round() != cents) continue;
    if (r.company?.id != companyId) continue;
    final at = DateTime.tryParse(r.createdAt ?? '');
    if (at == null) continue;
    if (now.difference(at) > const Duration(minutes: 10)) continue;
    if (bestAt == null || at.isAfter(bestAt)) {
      best = r;
      bestAt = at;
    }
  }
  return best;
}

// ─── Anexos ─────────────────────────────────────────────────────────────────

const Map<String, String> kAnexoMimes = {
  'pdf': 'application/pdf',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
};

String? anexoMime(String filename) {
  final i = filename.lastIndexOf('.');
  if (i < 0) return null;
  return kAnexoMimes[filename.substring(i + 1).toLowerCase()];
}

/// `null` = ok; senão a mensagem do web.
String? validarAnexo(String filename, int bytes, {required int limiteBytes}) {
  if (anexoMime(filename) == null) {
    return 'Tipo não aceito: só PDF, JPG, PNG ou WebP';
  }
  if (bytes > limiteBytes) {
    final mb = (bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',');
    final lim = (limiteBytes / (1024 * 1024)).round();
    return 'O arquivo "$filename" tem $mb MB e o limite de envio é $lim MB. '
        'Reduza o arquivo (ou envie uma foto) e tente de novo.';
  }
  return null;
}

/// Chave do rascunho local (por tipo, pessoa e empresa).
String rascunhoKey({String? tipoId, String? userId, String? companyId}) =>
    'imob_draft_fin.solicitacao${tipoId == null ? '' : '.$tipoId'}_'
    '${userId ?? ''}_${companyId ?? ''}';
