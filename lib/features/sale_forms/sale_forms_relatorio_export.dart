/// Relatório XLSX da lista de fichas de venda — espelha
/// `utils/saleFormsRelatorioExport.ts` do web (abas «Relatório fichas»,
/// «Auditoria detalhada» e «Como ler», mesmas colunas e formatos).
///
/// O web gera a planilha no navegador a partir de `GET /sistema/fichas-venda`
/// com `includeLastAuditChanges=true` (não há endpoint de exportação no
/// back); o app faz o mesmo, com [buildXlsx].
library;

import 'dart:typed_data';

import 'sale_form_audit_display.dart';
import 'xlsx/simple_xlsx.dart';

/// Mesmo recorte do web (`EXPORT_PAGE_SIZE` / `EXPORT_MAX_ROWS`).
const int kSaleFormsExportPageSize = 100;
const int kSaleFormsExportMaxRows = 5000;

String _s(Map<String, dynamic> r, String camel, String snake) {
  final v = r[camel] ?? r[snake];
  return v == null ? '' : v.toString().trim();
}

String _orDash(String s) => s.isEmpty ? '—' : s;

String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

/// `formatarDataHoraBrasilia`: dd/MM/aaaa HH:mm no horário de Brasília
/// (UTC−3, sem horário de verão desde 2019).
String saleFormsExportDateTime(dynamic raw) {
  if (raw == null) return '—';
  final d = DateTime.tryParse(raw.toString());
  if (d == null) return '—';
  final b = d.toUtc().subtract(const Duration(hours: 3));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(b.day)}/${two(b.month)}/${b.year} ${two(b.hour)}:${two(b.minute)}';
}

String _saleDate(Map<String, dynamic> r) {
  final raw = _s(r, 'saleDate', 'sale_date');
  if (raw.isEmpty) return '—';
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw);
  if (m != null) return '${m[3]}/${m[2]}/${m[1]}';
  return '—';
}

String _statusLabel(String s) {
  switch (s) {
    case 'finalized':
      return 'Finalizada';
    case 'processing':
      return 'Em processamento';
    case 'canceled':
      return 'Cancelada';
    default:
      return 'Aguardando assinatura';
  }
}

double _numField(Map<String, dynamic> r, String camel, String snake) {
  final v = r[camel] ?? r[snake];
  if (v == null || v == '') return 0;
  final n = v is num ? v.toDouble() : double.tryParse(v.toString());
  return n != null && n.isFinite ? n : 0;
}

String _phone(Map<String, dynamic> r, String camel, String snake) {
  final d = _digits(_s(r, camel, snake));
  return d.isEmpty ? '—' : saleFormMaskPhone(d);
}

/// `hasRealCpf` + `maskCPF`: só CPF de 11 dígitos aparece.
String _cpf(Map<String, dynamic> r, String camel, String snake) {
  final d = _digits(_s(r, camel, snake));
  return d.length == 11 ? saleFormMaskDoc(d) : '—';
}

const List<(String, String, String, String, String)> _partes = [
  ('Comprador', 'buyerName', 'buyer_name', 'buyerPhone', 'buyer_phone'),
  (
    'Cônjuge do comprador',
    'buyerSpouseName',
    'buyer_spouse_name',
    'buyerSpousePhone',
    'buyer_spouse_phone',
  ),
  ('Vendedor', 'sellerName', 'seller_name', 'sellerPhone', 'seller_phone'),
  (
    'Cônjuge do vendedor',
    'sellerSpouseName',
    'seller_spouse_name',
    'sellerSpousePhone',
    'seller_spouse_phone',
  ),
];

/// «Papel: Nome — telefone · …».
String saleFormsExportTelefones(Map<String, dynamic> r) {
  final out = <String>[];
  for (final p in _partes) {
    final tel = _phone(r, p.$4, p.$5);
    if (tel == '—') continue;
    final nome = _s(r, p.$2, p.$3);
    out.add(nome.isNotEmpty ? '${p.$1}: $nome — $tel' : '${p.$1}: $tel');
  }
  return out.isEmpty ? '—' : out.join(' · ');
}

String _share(dynamic pct, dynamic fixo) {
  final f = fixo is num ? fixo : num.tryParse('${fixo ?? ''}');
  if (f != null && f > 0) return saleFormMoney(f);
  final p = pct is num ? pct : num.tryParse('${pct ?? ''}');
  if (p != null && p > 0) {
    final s = p == p.roundToDouble() ? p.toInt().toString() : '$p';
    return '${s.replaceAll('.', ',')}%';
  }
  return '';
}

String _funcao(dynamic f) {
  switch ((f ?? '').toString().trim()) {
    case 'captador':
      return 'Captador';
    case 'sdr':
      return 'SDR';
    case 'outros':
      return 'Outros';
    default:
      return 'Corretor';
  }
}

/// «Papel: Nome (parte) · …» — corretores (com captadores) e gerências.
String saleFormsExportComissionados(Map<String, dynamic> r) {
  final cd = r['commissionsData'] ?? r['commissions_data'];
  if (cd is! Map) return '—';
  final out = <String>[];
  for (final c in (cd['corretores'] is List ? cd['corretores'] as List : [])) {
    if (c is! Map) continue;
    final nome = (c['nome'] ?? '').toString().trim().isNotEmpty
        ? c['nome'].toString().trim()
        : (c['id'] ?? '').toString().trim();
    if (nome.isEmpty) continue;
    final share = _share(c['porcentagem'], c['valorFixo']);
    var entry = share.isNotEmpty
        ? '${_funcao(c['funcao'])}: $nome ($share)'
        : '${_funcao(c['funcao'])}: $nome';
    final caps = (c['captadores'] is List ? c['captadores'] as List : [])
        .whereType<Map>()
        .map((cap) {
          final cn = (cap['nome'] ?? '').toString().trim();
          if (cn.isEmpty) return '';
          final cs = _share(cap['porcentagem'], null);
          return cs.isNotEmpty ? '$cn ($cs)' : cn;
        })
        .where((e) => e.isNotEmpty)
        .toList();
    if (caps.isNotEmpty) entry += ' — captador(es): ${caps.join(', ')}';
    out.add(entry);
  }
  for (final g in (cd['gerencias'] is List ? cd['gerencias'] as List : [])) {
    if (g is! Map) continue;
    final nome = (g['nome'] ?? '').toString().trim();
    final share = _share(g['porcentagem'], null);
    if (nome.isEmpty && share.isEmpty) continue;
    final nivel = g['nivel'] is num ? 'Gerência N${g['nivel']}' : 'Gerência';
    var entry = nome.isNotEmpty ? '$nivel: $nome' : nivel;
    if (share.isNotEmpty) entry += ' ($share)';
    out.add(entry);
  }
  return out.isEmpty ? '—' : out.join(' · ');
}

/// `formatSaleFormPropertyLine`.
String saleFormsExportPropertyLine(Map<String, dynamic> r) {
  final street = _s(r, 'propertyAddress', 'property_address');
  final num = _s(r, 'propertyNumber', 'property_number');
  final comp = _s(r, 'propertyComplement', 'property_complement');
  final neigh = _s(r, 'propertyNeighborhood', 'property_neighborhood');
  final city = _s(r, 'propertyCity', 'property_city');
  final st = _s(r, 'propertyState', 'property_state');
  final zip = _s(r, 'propertyZipCode', 'property_zip_code');
  String join(List<String> l, String sep) =>
      l.where((e) => e.isNotEmpty).join(sep);
  final line1 = join([street, join([num, comp], ', ')], ', ');
  final parts = [
    line1,
    neigh,
    join([city, st], '/'),
    if (zip.isNotEmpty) 'CEP $zip',
  ].where((e) => e.trim().isNotEmpty).toList();
  if (parts.isNotEmpty) return parts.join(' · ');
  final emp = r['empreendimentoData'] ?? r['empreendimento_data'];
  if (emp is Map) {
    final bits = [emp['incorporadora'], emp['empreendimento'], emp['unidade']]
        .map((e) => (e ?? '').toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (bits.isNotEmpty) return bits.join(' · ');
  }
  final code = _s(r, 'propertyCode', 'property_code');
  return code.isNotEmpty ? 'Cód. $code' : '—';
}

Map<String, dynamic>? _lastAudit(Map<String, dynamic> r) {
  final la = r['lastAudit'];
  return la is Map ? Map<String, dynamic>.from(la) : null;
}

/// `saleFormTraceabilityOneLine`.
String saleFormsExportTraceability(Map<String, dynamic> r) {
  final la = _lastAudit(r);
  final summary = (la?['summary'] ?? '').toString().trim();
  if (summary.isNotEmpty && summary != '—') return summary;
  final lines = <String>[];
  final deletedAt = r['deletedAt'] ?? r['deleted_at'];
  if (deletedAt != null && '$deletedAt'.isNotEmpty) {
    lines.add('Exclusão lógica em ${saleFormsExportDateTime(deletedAt)}.');
    final dr = _s(r, 'deletionReason', 'deletion_reason');
    if (dr.isNotEmpty) lines.add('Motivo da exclusão: $dr');
  }
  if (_s(r, 'status', 'status') == 'canceled') {
    lines.add('Ficha cancelada.');
    final cr = _s(r, 'cancellationReason', 'cancellation_reason');
    if (cr.isNotEmpty) lines.add('Motivo do cancelamento: $cr');
  }
  if (r['ativo'] == false && (deletedAt == null || '$deletedAt'.isEmpty)) {
    lines.add('Ficha desativada automaticamente (regra de rotina, ex.: '
        'ausência de vínculo).');
  }
  final refusedAt =
      r['signatureLockRefusedAt'] ?? r['signature_lock_refused_at'];
  if (refusedAt != null && '$refusedAt'.isNotEmpty) {
    lines.add('Recusa registrada no fluxo de assinatura pendente em '
        '${saleFormsExportDateTime(refusedAt)}.');
    final rr =
        _s(r, 'signatureLockRefusalReason', 'signature_lock_refusal_reason');
    if (rr.isNotEmpty) lines.add('Justificativa: $rr');
  }
  lines.add('Criada em ${saleFormsExportDateTime(r['createdAt'] ?? r['created_at'])}.');
  lines.add('Última atualização em '
      '${saleFormsExportDateTime(r['updatedAt'] ?? r['updated_at'])}.');
  return lines.join(' · ');
}

String _truncate(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max - 1)}…';

String _metaOneLine(Map<String, dynamic> meta) {
  final rows = saleFormAuditMetadataRows(meta);
  if (rows.isNotEmpty) {
    return _truncate(
      rows
          .map((e) =>
              '${e.label}: ${e.value.replaceAll(RegExp(r'\s+'), ' ').trim()}')
          .join(' | '),
      8000,
    );
  }
  final m = Map<String, dynamic>.from(meta)..remove('addedUserIds');
  return _truncate(m.toString(), 8000);
}

const List<String> kSaleFormsExportHeaders = [
  'Nº ficha',
  'Comprador',
  'Comprador — telefone',
  'Comprador — CPF',
  'Comprador — e-mail',
  'Cônjuge do comprador',
  'Cônjuge do comprador — telefone',
  'Cônjuge do comprador — CPF',
  'Vendedor',
  'Vendedor — telefone',
  'Vendedor — CPF',
  'Vendedor — e-mail',
  'Cônjuge do vendedor',
  'Cônjuge do vendedor — telefone',
  'Cônjuge do vendedor — CPF',
  'Telefones (todos os envolvidos)',
  'Criador (usuário)',
  'Data de criação',
  'Data da compra',
  'Mídia de origem',
  'Endereço do imóvel',
  'Valor venda',
  'Comissão total',
  'Comissionados',
  'Gestor responsável',
  'Externo',
  'Status',
  'Rastreabilidade (resumo)',
  'Última auditoria — data/hora',
  'Última auditoria — ação',
  'Última auditoria — usuário',
  'Última auditoria — qtd. campos',
  'Última auditoria — informações extras',
];

/// Uma linha da aba «Relatório fichas» (a partir do JSON da listagem).
List<String> saleFormsExportRow(Map<String, dynamic> r) {
  final la = _lastAudit(r);
  final user = r['user'];
  final meta = la?['metadata'];
  return [
    _s(r, 'formNumber', 'form_number'),
    _orDash(_s(r, 'buyerName', 'buyer_name')),
    _phone(r, 'buyerPhone', 'buyer_phone'),
    _cpf(r, 'buyerCpf', 'buyer_cpf'),
    _orDash(_s(r, 'buyerEmail', 'buyer_email')),
    _orDash(_s(r, 'buyerSpouseName', 'buyer_spouse_name')),
    _phone(r, 'buyerSpousePhone', 'buyer_spouse_phone'),
    _cpf(r, 'buyerSpouseCpf', 'buyer_spouse_cpf'),
    _orDash(_s(r, 'sellerName', 'seller_name')),
    _phone(r, 'sellerPhone', 'seller_phone'),
    _cpf(r, 'sellerCpf', 'seller_cpf'),
    _orDash(_s(r, 'sellerEmail', 'seller_email')),
    _orDash(_s(r, 'sellerSpouseName', 'seller_spouse_name')),
    _phone(r, 'sellerSpousePhone', 'seller_spouse_phone'),
    _cpf(r, 'sellerSpouseCpf', 'seller_spouse_cpf'),
    saleFormsExportTelefones(r),
    _orDash(user is Map ? (user['name'] ?? '').toString().trim() : ''),
    saleFormsExportDateTime(r['createdAt'] ?? r['created_at']),
    _saleDate(r),
    _orDash(_s(r, 'mediaSource', 'media_source')),
    saleFormsExportPropertyLine(r),
    saleFormMoney(_numField(r, 'saleValue', 'sale_value')),
    saleFormMoney(_numField(r, 'totalCommission', 'total_commission')),
    saleFormsExportComissionados(r),
    _orDash(_s(r, 'managerName', 'manager_name')),
    _orDash(_s(r, 'externalBrokerName', 'external_broker_name')),
    _statusLabel(_s(r, 'status', 'status')),
    saleFormsExportTraceability(r),
    la?['createdAt'] != null ? saleFormsExportDateTime(la!['createdAt']) : '—',
    la?['action'] != null
        ? saleFormAuditActionLabel(la!['action'].toString())
        : '—',
    la == null
        ? '—'
        : _orDash((la['userName'] ?? '').toString().trim()) == '—'
            ? 'Sistema'
            : la['userName'].toString().trim(),
    la == null ? '—' : '${la['changesCount'] ?? 0}',
    meta is Map ? _metaOneLine(Map<String, dynamic>.from(meta)) : '—',
  ];
}

const List<String> _detailHeaders = [
  'Nº ficha',
  'Comprador',
  'Data último evento',
  'Tipo evento',
  'Usuário evento',
  'Campo alterado',
  'Valor anterior',
  'Valor novo',
  'Código interno (opcional)',
];

/// Aba «Auditoria detalhada»: último evento de cada ficha.
List<List<String>> saleFormsExportAuditRows(List<Map<String, dynamic>> forms) {
  final out = <List<String>>[];
  for (final r in forms) {
    final la = _lastAudit(r);
    if (la == null) continue;
    final base = [
      _s(r, 'formNumber', 'form_number'),
      _orDash(_s(r, 'buyerName', 'buyer_name')),
      saleFormsExportDateTime(la['createdAt']),
      saleFormAuditActionLabel(la['action']?.toString()),
      (la['userName'] ?? '').toString().trim().isEmpty
          ? 'Sistema'
          : la['userName'].toString().trim(),
    ];
    final antes = out.length;
    final rawChanges = la['changes'] is List
        ? (la['changes'] as List)
            .whereType<Map>()
            .map((c) =>
                SaleFormAuditChange.fromJson(Map<String, dynamic>.from(c)))
            .toList()
        : <SaleFormAuditChange>[];
    final parts = saleFormPartitionAuditChanges(rawChanges);
    final meta = la['metadata'];
    if (parts.visible.isNotEmpty) {
      for (final c in parts.visible) {
        final f = c.field.trim().isEmpty ? '—' : c.field.trim();
        out.add([
          ...base,
          c.rotulo,
          saleFormAuditValue(f, c.before),
          saleFormAuditValue(f, c.after),
          f,
        ]);
      }
    } else if (meta is Map && meta.isNotEmpty) {
      final rows = saleFormAuditMetadataRows(Map<String, dynamic>.from(meta));
      if (rows.isNotEmpty) {
        for (final m in rows) {
          out.add([...base, m.label, '—', _truncate(m.value, 12000), '—']);
        }
      } else {
        out.add([
          ...base,
          'Informações extras (texto técnico)',
          '—',
          _truncate(meta.toString(), 12000),
          '—',
        ]);
      }
    } else if (parts.cosmeticCount > 0) {
      out.add([
        ...base,
        '(sem mudança visível — só formato interno do sistema)',
        '—',
        'Foram ${parts.cosmeticCount} registro(s) salvos em que data, valor '
            'em reais ou documento permaneceu o mesmo; só mudou a forma '
            'técnica de gravação.',
        '—',
      ]);
    }
    if (out.length == antes) {
      final s = (la['summary'] ?? '').toString().trim();
      out.add([
        ...base,
        'Resumo do último evento',
        '—',
        s.isNotEmpty && s != '—'
            ? s
            : '${saleFormAuditActionLabel(la['action']?.toString())} — '
                '${la['changesCount'] ?? 0} campo(s) neste evento.',
        '—',
      ]);
    }
  }
  return out;
}

const List<String> _comoLer = [
  'Como ler este Excel — fichas de venda',
  '',
  'Aba «Relatório fichas»: uma linha por ficha. Valores em reais e datas já '
      'vêm formatados para leitura.',
  'Envolvidos: cada parte tem colunas próprias — Comprador, Cônjuge do '
      'comprador, Vendedor e Cônjuge do vendedor — com nome, telefone, CPF e '
      'e-mail (quando informados na ficha). Telefone sai no formato (DDD) '
      '99999-9999; CPF só aparece quando é um CPF real (cadastro sem CPF '
      'mostra «—»).',
  'Coluna «Telefones (todos os envolvidos)»: os quatro telefones da ficha em '
      'uma célula só, no formato «Papel: Nome — telefone», separados por « · ».',
  'Coluna «Comissionados»: corretores, captadores e gerências que recebem '
      'comissão na ficha, no formato «Papel: Nome (parte)», separados por « · ». '
      'A parte é o percentual (%) ou o valor fixo em R\$ quando informado.',
  'Coluna «Mídia de origem»: origem do lead/venda registrada na ficha. Vazio '
      'aparece como «—».',
  'Aba «Auditoria detalhada»: último evento de cada ficha exportada. «Valor '
      'anterior» e «Valor novo» usam o mesmo padrão da tela (Raio-X): moeda em '
      'R\$, datas em DD/MM/AAAA, CPF/telefone/CEP quando aplicável.',
  'Coluna «Código interno (opcional)»: nome do campo no banco de dados; use '
      'só se o suporte pedir.',
  'Linhas omitidas na planilha: quando o sistema gravou uma alteração que '
      'não muda o valor na prática (ex.: 296000,00 e 296000), ela não aparece '
      'aqui — igual ao Raio-X.',
  '',
  'Se a aba «Auditoria detalhada» estiver vazia ou com aviso: confira os '
      'filtros da exportação ou se a ficha possui histórico de auditoria.',
];

/// Bytes do `.xlsx` com as três abas do web.
Uint8List buildSaleFormsRelatorioXlsx(List<Map<String, dynamic>> forms) {
  final main = XlsxSheet(
    name: 'Relatório fichas',
    rows: [
      kSaleFormsExportHeaders,
      for (final f in forms) saleFormsExportRow(f),
    ],
    columnWidths: const [
      12, 22, 16, 16, 26, 22, 16, 16, 22, 16, 16, 26, 22, 16, 16, 60, //
      22, 18, 14, 18, 36, 14, 14, 50, 20, 14, 20, 40, 20, 18, 22, 10, 48,
    ],
  );
  final detail = saleFormsExportAuditRows(forms);
  final audit = detail.isNotEmpty
      ? XlsxSheet(
          name: 'Auditoria detalhada',
          rows: [_detailHeaders, ...detail],
          columnWidths: const [12, 22, 20, 18, 22, 32, 28, 28, 22],
        )
      : XlsxSheet(
          name: 'Auditoria detalhada',
          headerRow: false,
          rows: const [
            ['Não há linhas na auditoria detalhada para o recorte exportado.'],
            [
              'Motivos comuns: nenhuma ficha com último evento de auditoria no '
                  'recorte exportado.',
            ],
            [''],
            [
              'Datas e valores na primeira aba já aparecem formatados (R\$, '
                  'DD/MM/AAAA).',
            ],
          ],
          columnWidths: const [100],
        );
  final help = XlsxSheet(
    name: 'Como ler',
    headerRow: false,
    rows: [
      for (final l in _comoLer) [l],
    ],
    columnWidths: const [110],
  );
  return buildXlsx([main, audit, help]);
}

/// `relatorio-fichas-AAAA-MM-DD-HHmm.xlsx` (hora local).
String saleFormsRelatorioFileName(DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'relatorio-fichas-${now.year}-${two(now.month)}-${two(now.day)}-'
      '${two(now.hour)}${two(now.minute)}.xlsx';
}
