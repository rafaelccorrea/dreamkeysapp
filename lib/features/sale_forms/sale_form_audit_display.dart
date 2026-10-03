/// Leitura da auditoria ("Raio-X") da ficha de venda — espelha
/// `utils/saleFormAuditLabels.ts` e `utils/saleFormAuditDisplay.ts` do web.
///
/// Entrada do back (`GET /sistema/fichas-venda/:id/auditoria`):
/// `{id, createdAt, action, userId?, userName?, userEmail?,
///   changes: [{field, label?, before?, after?}], metadata?, summary?}`.
library;

import 'dart:convert';

import 'package:intl/intl.dart';

/// `auditActionLabelPt`.
String saleFormAuditActionLabel(String? action) {
  switch ((action ?? '').trim()) {
    case 'update':
      return 'Edição';
    case 'create':
      return 'Criação';
    case 'cancel':
      return 'Cancelamento';
    case 'delete_soft':
      return 'Exclusão lógica';
    case 'invalidate_signatures':
      return 'Invalidação assinaturas';
    case 'signature_lock_refuse':
      return 'Recusa pendência assinatura';
    case 'transfer_responsibility':
      return 'Transferência responsável';
    case 'linked_users_add':
      return 'Usuários vinculados';
    default:
      final a = (action ?? '').trim();
      return a.isEmpty ? 'Evento' : a;
  }
}

const Set<String> _dateFields = {
  'saleDate',
  'buyerBirthDate',
  'buyerSpouseBirthDate',
  'sellerBirthDate',
  'sellerSpouseBirthDate',
};
const Set<String> _moneyFields = {
  'saleValue',
  'totalCommission',
  'goalValue',
  'valorEntrada',
};
const Set<String> _cpfFields = {
  'buyerCpf',
  'sellerCpf',
  'buyerSpouseCpf',
  'sellerSpouseCpf',
  'gestorCpf',
};
const Set<String> _phoneFields = {
  'buyerPhone',
  'sellerPhone',
  'buyerSpousePhone',
  'sellerSpousePhone',
};
const Set<String> _cepFields = {
  'propertyZipCode',
  'buyerZipCode',
  'sellerZipCode',
  'buyerSpouseZipCode',
  'sellerSpouseZipCode',
};

bool _isDateField(String field) {
  if (_dateFields.contains(field)) return true;
  if (field.endsWith('BirthDate')) return true;
  if (field.endsWith('At') && field != 'saleDate') {
    return !field.contains('Count');
  }
  return false;
}

/// Data canônica `AAAA-MM-DD` sem efeito de fuso.
String? _dateCanonical(String? raw) {
  if (raw == null) return null;
  final s = raw.trim();
  if (s.isEmpty || s == '—') return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
  if (m != null) return '${m[1]}-${m[2]}-${m[3]}';
  final d = DateTime.tryParse(s);
  if (d == null) return null;
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

String _brDate(String canon) {
  final p = canon.split('-');
  return '${p[2]}/${p[1]}/${p[0]}';
}

double? _numOf(String? s) {
  if (s == null) return null;
  return double.tryParse(s.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.'));
}

String _digits(String? s) => (s ?? '').replaceAll(RegExp(r'\D'), '');

/// R$ em pt-BR (`formatCurrencyValue` do web).
String saleFormMoney(num v) =>
    NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(v);

/// CPF (11 dígitos) ou CNPJ (14); outro tamanho volta como veio.
String saleFormMaskDoc(String d) {
  if (d.length == 11) {
    return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-'
        '${d.substring(9)}';
  }
  if (d.length == 14) {
    return '${d.substring(0, 2)}.${d.substring(2, 5)}.${d.substring(5, 8)}/'
        '${d.substring(8, 12)}-${d.substring(12)}';
  }
  return d;
}

/// Telefone BR "(DDD) 99999-9999" / "(DDD) 9999-9999"; tira o 55.
String saleFormMaskPhone(String raw) {
  var d = _digits(raw);
  if (d.length > 11 && d.startsWith('55')) d = d.substring(2);
  if (d.length == 11) {
    return '(${d.substring(0, 2)}) ${d.substring(2, 7)}-${d.substring(7)}';
  }
  if (d.length == 10) {
    return '(${d.substring(0, 2)}) ${d.substring(2, 6)}-${d.substring(6)}';
  }
  return raw.trim();
}

/// `auditValuesSemanticallyEqual`: mesmo valor com formato diferente.
bool saleFormAuditValuesEqual(String field, String? before, String? after) {
  final b = before == null || before.isEmpty ? null : before.trim();
  final a = after == null || after.isEmpty ? null : after.trim();
  if (b == a) return true;
  if ((b == null || b == '—') && (a == null || a == '—')) return true;
  if (_isDateField(field) || field == 'deletedAt') {
    final db = _dateCanonical(b);
    final da = _dateCanonical(a);
    if (db != null && da != null) return db == da;
  }
  if (_moneyFields.contains(field)) {
    final nb = _numOf(b);
    final na = _numOf(a);
    if (nb != null && na != null) return (nb - na).abs() < 0.005;
  }
  if (_cpfFields.contains(field) || field.endsWith('Cpf')) {
    final db = _digits(b);
    final da = _digits(a);
    if (db.length >= 11 && da.length >= 11 && db == da) return true;
  }
  return false;
}

/// Uma alteração de campo da auditoria.
class SaleFormAuditChange {
  const SaleFormAuditChange({
    required this.field,
    this.label,
    this.before,
    this.after,
  });
  final String field;
  final String? label;
  final String? before;
  final String? after;

  String get rotulo {
    final l = (label ?? '').trim();
    if (l.isNotEmpty) return l;
    return field.trim().isEmpty ? '—' : field.trim();
  }

  static String? _raw(dynamic v) {
    if (v == null) return null;
    if (v is Map || v is List) return jsonEncode(v);
    return v.toString();
  }

  factory SaleFormAuditChange.fromJson(Map<String, dynamic> j) =>
      SaleFormAuditChange(
        field: (j['field'] ?? '').toString(),
        label: j['label']?.toString(),
        before: _raw(j['before']),
        after: _raw(j['after']),
      );
}

/// `partitionAuditChanges`: separa o que mudou de verdade do que só mudou
/// de formato interno.
({List<SaleFormAuditChange> visible, int cosmeticCount})
    saleFormPartitionAuditChanges(List<SaleFormAuditChange> changes) {
  final visible = <SaleFormAuditChange>[];
  var cosmetic = 0;
  for (final c in changes) {
    if (saleFormAuditValuesEqual(c.field, c.before, c.after)) {
      cosmetic++;
    } else {
      visible.add(c);
    }
  }
  return (visible: visible, cosmeticCount: cosmetic);
}

/// `formatAuditValueForDisplay`.
String saleFormAuditValue(String field, String? value) {
  if (value == null) return '—';
  final s = value.trim();
  if (s.isEmpty || s == '—') return '—';
  if (field == 'commissionsData' ||
      field == 'collaboratorsData' ||
      field == 'empreendimentoData') {
    return _jsonHuman(field, s);
  }
  if (_isDateField(field) || field == 'deletedAt') {
    final d = _dateCanonical(s);
    if (d != null) return _brDate(d);
  }
  if (_moneyFields.contains(field)) {
    final n = _numOf(s);
    if (n != null) return saleFormMoney(n);
  }
  if (_cpfFields.contains(field) || field.endsWith('Cpf')) {
    final d = _digits(s);
    if (d.length == 11 || d.length == 14) return saleFormMaskDoc(d);
  }
  if (_phoneFields.contains(field) || field.endsWith('Phone')) {
    return saleFormMaskPhone(s);
  }
  if (_cepFields.contains(field) || field.endsWith('ZipCode')) {
    final d = _digits(s);
    if (d.length == 8) return '${d.substring(0, 5)}-${d.substring(5)}';
  }
  if (field == 'status') {
    const map = {
      'waiting_for_signature': 'Aguardando assinatura',
      'processing': 'Em processamento',
      'finalized': 'Finalizada',
      'canceled': 'Cancelada',
    };
    return map[s] ?? s;
  }
  if (s.startsWith('{') || s.startsWith('[')) return _jsonHuman(field, s);
  return s;
}

String _pctText(dynamic v) => '${v.toString().replaceAll('.', ',')}%';

String _jsonHuman(String field, String jsonStr) {
  dynamic o;
  try {
    o = jsonDecode(jsonStr);
  } catch (_) {
    return jsonStr;
  }
  if (o is! Map) return jsonStr;
  if (field == 'commissionsData') {
    final lines = <String>[];
    final corretores = o['corretores'] is List ? o['corretores'] as List : [];
    final gerencias = o['gerencias'] is List ? o['gerencias'] as List : [];
    if (corretores.isNotEmpty) {
      lines.add('Corretores / captadores:');
      for (var i = 0; i < corretores.length; i++) {
        final r = corretores[i];
        if (r is! Map) continue;
        final nome = (r['nome'] ?? r['name'] ?? 'Corretor ${i + 1}').toString();
        final pct = r['porcentagem'] != null ? ' — ${_pctText(r['porcentagem'])}' : '';
        final func = r['funcao'] != null ? ' (${r['funcao']})' : '';
        final vf = r['valorFixo'] != null ? ' — R\$ fixo: ${r['valorFixo']}' : '';
        lines.add('  • $nome$func$pct$vf');
      }
    }
    if (gerencias.isNotEmpty) {
      lines.add('Gerências:');
      for (var i = 0; i < gerencias.length; i++) {
        final r = gerencias[i];
        if (r is! Map) continue;
        final nome =
            (r['nome'] ?? 'Gerência nível ${r['nivel'] ?? i + 1}').toString();
        final pct = r['porcentagem'] != null ? ' — ${_pctText(r['porcentagem'])}' : '';
        lines.add('  • $nome$pct');
      }
    }
    return lines.isEmpty ? jsonStr : lines.join('\n');
  }
  if (field == 'collaboratorsData') {
    final pre = (o['preAtendimento'] ?? '').toString().trim();
    final cen = (o['centralCaptacao'] ?? '').toString().trim();
    final parts = [
      if (pre.isNotEmpty) 'Pré-atendimento / central: $pre',
      if (cen.isNotEmpty) 'Captação: $cen',
    ];
    return parts.isEmpty ? jsonStr : parts.join('\n');
  }
  if (field == 'empreendimentoData') {
    final bits = <String>[
      for (final k in const [
        'incorporadora',
        'empreendimento',
        'unidade',
        'dataEntrada',
        'formaPagamento',
      ])
        if ((o[k] ?? '').toString().trim().isNotEmpty)
          '$k: ${o[k].toString().trim()}',
    ];
    final ve = o['valorEntrada'];
    final n = ve is num ? ve : double.tryParse('${ve ?? ''}');
    if (n != null) bits.add('Valor entrada: ${saleFormMoney(n)}');
    return bits.isEmpty ? jsonStr : bits.join('\n');
  }
  return jsonStr;
}

/// `buildFriendlyAuditMetadataRows`: metadados em linhas legíveis.
List<({String label, String value})> saleFormAuditMetadataRows(
    Map<String, dynamic>? metadata) {
  final m = metadata ?? const {};
  final out = <({String label, String value})>[];
  if (m['formNumber'] != null) {
    out.add((label: 'Número da ficha', value: m['formNumber'].toString()));
  }
  final added = m['addedUsers'];
  final addedIds = m['addedUserIds'];
  if (added is List && added.isNotEmpty) {
    final nomes = added.whereType<Map>().map((u) {
      final n = (u['name'] ?? '').toString().trim();
      final e = (u['email'] ?? '').toString().trim();
      final nome = n.isEmpty ? 'Sem nome' : n;
      return e.isEmpty ? nome : '$nome ($e)';
    }).toList();
    out.add((label: 'Usuários incluídos na ficha', value: nomes.join('\n')));
  } else if (addedIds is List && addedIds.isNotEmpty) {
    out.add((
      label: 'Usuários vinculados',
      value: '${addedIds.length} pessoa(s) vinculada(s).',
    ));
  }
  if (m['invalidatedSignatures'] != null) {
    out.add((
      label: 'Assinaturas afetadas',
      value: '${m['invalidatedSignatures']} registro(s) de assinatura.',
    ));
  }
  if (m['previousCreatorUserId'] != null || m['newCreatorUserId'] != null) {
    out.add((
      label: 'Transferência de responsável',
      value: 'Quem era o responsável: ${m['previousCreatorUserId'] ?? '—'}\n'
          'Novo responsável: ${m['newCreatorUserId'] ?? '—'}',
    ));
  }
  final props = m['purchaseProposalIds'];
  if (props is List && props.isNotEmpty) {
    out.add((
      label: 'Propostas vinculadas ajustadas',
      value: '${props.length} proposta(s) atualizadas junto com a ficha.',
    ));
  }
  return out;
}

/// `stripAuditMetadataIdsForJson` + `JSON.stringify(…, null, 2)`: o
/// "registro técnico (JSON)" do web, sem `addedUserIds`.
String saleFormAuditMetadataJson(Map<String, dynamic>? metadata) {
  final m = Map<String, dynamic>.from(metadata ?? const {})
    ..remove('addedUserIds');
  return const JsonEncoder.withIndent('  ').convert(m);
}

/// Frase do web quando o evento não tem mudança visível de campo.
String saleFormAuditNoChangeText(String action, int cosmeticCount) {
  if (action == 'linked_users_add') {
    return 'Nenhum dado do formulário foi alterado. Em «Informações extras» '
        'abaixo aparecem as pessoas que passaram a ter acesso à ficha.';
  }
  if (cosmeticCount > 0) {
    return 'Não há mudanças visíveis: as diferenças eram só de formato '
        'interno (mesmos valores).';
  }
  return 'Nenhuma alteração de campo neste evento.';
}

/// Aviso do web quando há mudança visível e linhas só de formato.
String saleFormAuditCosmeticHint(int cosmeticCount) =>
    'Omitimos $cosmeticCount linha(s) em que o valor para você não mudou — '
    'só o formato interno (ex.: data ou valor monetário com outra escrita).';

/// "Informações extras" sem linha legível (web `AuditMetaFallback`).
const String kSaleFormAuditMetaFallback =
    'O sistema guardou informações adicionais neste passo. Se precisar de '
    'ajuda, abra o registro técnico abaixo ou fale com o suporte.';

/// Lista vazia (web `AuditEmptyState`).
const String kSaleFormAuditEmpty =
    'Nenhum registro de auditoria para esta ficha. Isso pode ocorrer em '
    'eventos anteriores à migração ou quando a ficha ainda não possui '
    'alterações gravadas no histórico.';

/// Um evento da auditoria, já pronto para a tela.
class SaleFormAuditEntry {
  const SaleFormAuditEntry({
    required this.id,
    required this.action,
    required this.createdAt,
    required this.userName,
    required this.userEmail,
    required this.changes,
    required this.metadata,
    required this.summary,
  });

  final String id;
  final String action;
  final DateTime? createdAt;
  final String? userName;
  final String? userEmail;
  final List<SaleFormAuditChange> changes;
  final Map<String, dynamic>? metadata;
  final String? summary;

  String get actionLabel => saleFormAuditActionLabel(action);

  /// Web: `userName` ou "Sistema" (o e-mail aparece embaixo, à parte).
  String get autor {
    final n = (userName ?? '').trim();
    return n.isNotEmpty ? n : 'Sistema';
  }

  /// Web: "Informações extras" aparece sempre que o evento tem metadados.
  bool get temInfoExtra => metadata != null;

  factory SaleFormAuditEntry.fromJson(Map<String, dynamic> j) {
    String? sn(dynamic v) {
      final s = (v ?? '').toString().trim();
      return s.isEmpty ? null : s;
    }

    final user = j['user'];
    final rawChanges = j['changes'];
    final meta = j['metadata'];
    return SaleFormAuditEntry(
      id: (j['id'] ?? '').toString(),
      action: (j['action'] ?? '').toString(),
      createdAt: DateTime.tryParse((j['createdAt'] ?? '').toString()),
      userName: sn(j['userName']) ?? (user is Map ? sn(user['name']) : null),
      userEmail: sn(j['userEmail']) ?? (user is Map ? sn(user['email']) : null),
      changes: rawChanges is List
          ? rawChanges
              .whereType<Map>()
              .map((c) =>
                  SaleFormAuditChange.fromJson(Map<String, dynamic>.from(c)))
              .toList()
          : const [],
      metadata: meta is Map ? Map<String, dynamic>.from(meta) : null,
      summary: sn(j['summary']),
    );
  }
}
