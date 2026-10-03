import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/api_service.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../core/finance_access.dart';
import '../../core/finance_errors.dart';
import '../../core/finance_format.dart';
import '../../core/finance_me.dart';
import '../../core/finance_route_names.dart';
import '../../core/widgets/finance_form_widgets.dart';
import '../../meu_financeiro/models/meu_financeiro_models.dart';
import '../../meu_financeiro/services/meu_financeiro_service.dart';
import '../../meu_financeiro/widgets/finance_sheet.dart';
import '../../meu_financeiro/widgets/meu_financeiro_widgets.dart';
import '../models/request_models.dart';
import '../services/requests_service.dart';
import '../widgets/anexo_picker.dart';

/// Detalhe da solicitação (`SolicitacaoDetalhePage.tsx`): cadeia,
/// comentários, anexos, cancelar, editar/corrigir. Os botões seguem as
/// `permissoes` do back.
class SolicitacaoDetalhePage extends StatefulWidget {
  final String requestId;
  final RequestsService? service;

  const SolicitacaoDetalhePage({
    super.key,
    required this.requestId,
    this.service,
  });

  @override
  State<SolicitacaoDetalhePage> createState() => _SolicitacaoDetalhePageState();
}

class _SolicitacaoDetalhePageState extends State<SolicitacaoDetalhePage> {
  RequestsService get _svc => widget.service ?? RequestsService.instance;

  FinanceRequest? _r;
  FinanceError? _error;
  FinanceMe? _me;
  bool _loading = true;
  bool _busy = false;
  final TextEditingController _comment = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Detalhe + /auth/me em paralelo.
    final results = await Future.wait<Object>([
      _svc.detail(widget.requestId),
      FinanceMeService.instance.load(),
    ]);
    if (!mounted) return;
    final det = results[0] as Section<FinanceRequest>;
    final me = results[1] as ApiResponse<FinanceMe?>;
    setState(() {
      _loading = false;
      _r = det.data ?? _r;
      _error = det.error;
      if (me.success) _me = me.data;
    });
  }

  Future<void> _send() async {
    final text = _comment.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() => _busy = true);
    final err = await _svc.comment(widget.requestId, text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      financeSnack(context, err.message, error: true);
      return;
    }
    _comment.clear();
    FocusScope.of(context).unfocus();
    _load();
  }

  Future<void> _cancel() async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar solicitação?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Esta ação não pode ser desfeita.'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Motivo (opcional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: FinanceTones.rose),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancelar solicitação'),
          ),
        ],
      ),
    );
    final reason = reasonCtrl.text;
    reasonCtrl.dispose();
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final err = await _svc.cancel(widget.requestId, reason: reason);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      financeSnack(context, err.message, error: true);
      if (err.kind == FinanceErrorKind.conflict) _load();
      return;
    }
    financeSnack(context, 'Solicitação cancelada.');
    _load();
  }

  Future<void> _edit() async {
    final changed = await Navigator.of(
      context,
    ).pushNamed(FinanceRouteNames.editarSolicitacao(widget.requestId));
    if (changed != null && mounted) _load();
  }

  Future<void> _addAnexo() async {
    final a = await pickAnexo(context, limiteBytes: limiteAnexoBytes(_me));
    if (a == null || !mounted) return;
    setState(() => _busy = true);
    final erro = await _svc.uploadAttachment(
      widget.requestId,
      filename: a.name,
      bytes: a.bytes,
      mimeType: a.mime,
      multipart: usaUploadMultipart(_me),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    financeSnack(
      context,
      erro == null ? 'Anexo enviado.' : 'O anexo não entrou: $erro',
      error: erro != null,
    );
    _load();
  }

  Future<void> _removeAnexo(RequestAttachment a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover este anexo?'),
        content: Text(a.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = await _svc.removeAttachment(widget.requestId, a.id);
    if (!mounted) return;
    if (err != null) {
      financeSnack(context, err.message, error: true);
      return;
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return AppScaffold(
      title: r?.code ?? 'Solicitação',
      showDrawer: false,
      showBottomNavigation: false,
      body: _loading && r == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
          : r == null
          ? ListView(
              padding: const EdgeInsets.all(20),
              children: [
                FinanceInlineNotice(
                  text: _error?.message ?? 'Solicitação não encontrada.',
                  onRetry: _load,
                ),
              ],
            )
          : RefreshIndicator(onRefresh: _load, child: _content(context, r)),
    );
  }

  Widget _content(BuildContext context, FinanceRequest r) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final meId = _me?.userId;
    final podeEditar = r.podeEditar(meId: meId);
    final podeCancelar = r.podeCancelar(meId: meId);
    final reprovada = r.status == 'REPROVADO';
    final ultimaRecusa = r.approvals
        .where((a) => a.status == 'REPROVADO')
        .lastOrNull;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
      children: [
        if (_error != null) ...[
          FinanceInlineNotice(text: _error!.message, onRetry: _load),
          const SizedBox(height: 12),
        ],
        FinanceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  FinancePill(
                    label: requestStatusLabel(r.status),
                    color: FinanceTones.requestStatus(r.status),
                  ),
                  const SizedBox(width: 8),
                  FinancePill(
                    label: 'Prioridade ${requestPriorityLabel(r.priority).toLowerCase()}',
                    color: r.priority == 'URGENTE' || r.priority == 'ALTA'
                        ? FinanceTones.rose
                        : FinanceTones.slate,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                r.title,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  requestTypeLabel(r.type),
                  if (r.company != null) r.company!.name,
                  'criada em ${formatFinanceDateTime(r.createdAt, pattern: 'dd/MM/yyyy HH:mm')}',
                ].join(' · '),
                style: TextStyle(fontSize: 12.5, color: secondary),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _valor(context, 'Solicitado', r.amountRequested),
                  ),
                  if (r.amountApproved != null)
                    Expanded(
                      child: _valor(
                        context,
                        'Aprovado',
                        r.amountApproved!,
                        color: FinanceTones.emerald,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (reprovada && ultimaRecusa?.comment != null) ...[
          const SizedBox(height: 12),
          FinanceInlineNotice(
            text:
                'Recusada por ${approvalRoleLabel(ultimaRecusa!.role)}'
                '${ultimaRecusa.approverName == null ? '' : ' (${ultimaRecusa.approverName})'}: '
                '${ultimaRecusa.comment}',
          ),
        ],
        if (podeEditar || podeCancelar) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              if (podeEditar)
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: financeAccent(context),
                      minimumSize: const Size.fromHeight(46),
                    ),
                    onPressed: _busy ? null : _edit,
                    icon: Icon(
                      reprovada ? LucideIcons.rotateCcw : LucideIcons.pencil,
                      size: 16,
                    ),
                    label: Text(reprovada ? 'Corrigir e reenviar' : 'Editar'),
                  ),
                ),
              if (podeEditar && podeCancelar) const SizedBox(width: 10),
              if (podeCancelar)
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: FinanceTones.rose,
                      minimumSize: const Size.fromHeight(46),
                    ),
                    onPressed: _busy ? null : _cancel,
                    icon: const Icon(LucideIcons.ban, size: 16),
                    label: const Text('Cancelar'),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        _cadeia(context, r),
        const SizedBox(height: 12),
        FinanceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FinanceSectionHeader(
                title: 'Dados do pedido',
                icon: LucideIcons.clipboardList,
              ),
              FinanceField('Justificativa', r.justification.isEmpty ? '—' : r.justification),
              if (r.category != null) FinanceField('Categoria', r.category!.name),
              if (r.costCenter != null)
                FinanceField('Centro de custo', r.costCenter!.name),
              if (r.supplier != null) FinanceField('Fornecedor', r.supplier!.name),
              if (r.department != null)
                FinanceField('Departamento', r.department!),
              if (r.paymentMethod != null)
                FinanceField(
                  'Forma de pagamento',
                  paymentMethodLabel(r.paymentMethod),
                ),
              if (r.creditCard != null) FinanceField('Cartão', r.creditCard!.name),
              if (r.purchaseDate != null)
                FinanceField(
                  'Data da compra',
                  formatFinanceDate(r.purchaseDate, pattern: 'dd/MM/yyyy'),
                ),
              if ((r.installments ?? 0) > 1)
                FinanceField('Parcelas', '${r.installments}x'),
              if (r.notes != null) FinanceField('Observações', r.notes!),
              for (final e in r.camposExtras.entries)
                FinanceField(
                  e.key,
                  e.value is bool ? (e.value ? 'Sim' : 'Não') : '${e.value}',
                ),
            ],
          ),
        ),
        if (r.beneficiaries.isNotEmpty) ...[
          const SizedBox(height: 12),
          FinanceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FinanceSectionHeader(
                  title: 'Rateio entre empresas',
                  icon: LucideIcons.split,
                ),
                for (final b in r.beneficiaries)
                  FinanceRow(
                    title:
                        (b['company'] is Map ? b['company']['name'] : null)
                            ?.toString() ??
                        'Empresa',
                    value: formatBrl(financeNum(b['amount'])),
                  ),
              ],
            ),
          ),
        ],
        if (r.payables.isNotEmpty) ...[
          const SizedBox(height: 12),
          FinanceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FinanceSectionHeader(
                  title: 'Contas a pagar geradas',
                  icon: LucideIcons.receipt,
                ),
                for (final p in r.payables)
                  FinanceRow(
                    title: p['code']?.toString() ?? 'Título',
                    meta: 'vence ${formatFinanceDate(p['dueDate']?.toString())}',
                    value: formatBrl(financeNum(p['amount'])),
                    pill: FinancePill(
                      label: _payableStatus(p['status']?.toString()),
                      color: FinanceTones.slate,
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        _anexos(context, r),
        const SizedBox(height: 12),
        _comentarios(context, r),
      ],
    );
  }

  static String _payableStatus(String? s) {
    const m = {
      'PENDENTE': 'Pendente',
      'APROVADO': 'Aprovado',
      'PAGO': 'Pago',
      'CANCELADO': 'Cancelado',
      'VENCIDO': 'Vencido',
    };
    return m[s] ?? (s ?? '—');
  }

  Widget _valor(BuildContext context, String label, double v, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            formatBrl(v),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: color ?? ThemeHelpers.textColor(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _cadeia(BuildContext context, FinanceRequest r) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return FinanceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FinanceSectionHeader(
            title: 'Cadeia de aprovação',
            icon: LucideIcons.listChecks,
          ),
          if (r.approvals.isEmpty)
            FinanceEmpty(
              text: r.status == 'APROVADO' || r.status == 'CONCLUIDO'
                  ? 'Aprovada automaticamente pela alçada.'
                  : 'Sem etapas registradas.',
            )
          else
            for (final a in r.approvals)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      a.status == 'APROVADO'
                          ? LucideIcons.circleCheck
                          : a.status == 'REPROVADO'
                          ? LucideIcons.circleX
                          : LucideIcons.circleDashed,
                      size: 18,
                      color: a.status == 'APROVADO'
                          ? FinanceTones.emerald
                          : a.status == 'REPROVADO'
                          ? FinanceTones.rose
                          : FinanceTones.amber,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${a.level}. ${approvalRoleLabel(a.role)} · '
                            '${approvalStepStatusLabel(a.status)}',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: ThemeHelpers.textColor(context),
                            ),
                          ),
                          if (a.approverName != null || a.decidedAt != null)
                            Text(
                              [
                                ?a.approverName,
                                if (a.decidedAt != null)
                                  formatFinanceDateTime(
                                    a.decidedAt,
                                    pattern: 'dd/MM/yy HH:mm',
                                  ),
                              ].join(' · '),
                              style: TextStyle(fontSize: 12, color: secondary),
                            ),
                          if (a.comment != null)
                            Text(
                              '"${a.comment}"',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontStyle: FontStyle.italic,
                                color: secondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _anexos(BuildContext context, FinanceRequest r) {
    final aberta = r.status != 'CANCELADO' && r.status != 'CONCLUIDO';
    final limite = limiteAnexoBytes(_me) ~/ (1024 * 1024);
    return FinanceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FinanceSectionHeader(
            title: 'Anexos',
            icon: LucideIcons.paperclip,
            subtitle: 'PDF, JPG, PNG ou WebP · até $limite MB',
            trailing: aberta
                ? IconButton(
                    tooltip: 'Anexar',
                    onPressed: _busy ? null : _addAnexo,
                    icon: Icon(
                      LucideIcons.plus,
                      size: 20,
                      color: financeAccent(context),
                    ),
                  )
                : null,
          ),
          if (r.attachments.isEmpty)
            const FinanceEmpty(text: 'Nenhum anexo.')
          else
            for (final a in r.attachments)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  a.name.toLowerCase().endsWith('.pdf')
                      ? LucideIcons.fileText
                      : LucideIcons.image,
                  size: 20,
                ),
                title: Text(a.name, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  formatFinanceDateTime(a.createdAt, pattern: 'dd/MM/yy HH:mm'),
                ),
                trailing: aberta
                    ? IconButton(
                        tooltip: 'Remover',
                        icon: const Icon(LucideIcons.trash2, size: 18),
                        onPressed: () => _removeAnexo(a),
                      )
                    : null,
              ),
        ],
      ),
    );
  }

  Widget _comentarios(BuildContext context, FinanceRequest r) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return FinanceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FinanceSectionHeader(
            title: 'Conversa',
            icon: LucideIcons.messageCircle,
          ),
          if (r.comments.isEmpty)
            const FinanceEmpty(text: 'Nenhum comentário ainda.')
          else
            for (final c in r.comments)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: c.authorId != null && c.authorId == _me?.userId
                      ? financeAccent(context).withValues(alpha: 0.08)
                      : ThemeHelpers.borderLightColor(
                          context,
                        ).withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        c.authorName ?? 'Alguém',
                        if (c.kind == 'REPROVACAO') 'reprovou',
                        if (c.kind == 'APROVACAO') 'aprovou',
                        if (c.kind == 'REENVIO') 'reenviou',
                        formatFinanceDateTime(c.createdAt, pattern: 'dd/MM HH:mm'),
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: secondary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(c.body, style: const TextStyle(fontSize: 13.5)),
                  ],
                ),
              ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _comment,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 1000,
                  decoration: financeInputDecoration(
                    context,
                    label: 'Escreva um comentário',
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 22),
                child: IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: financeAccent(context),
                  ),
                  onPressed: _busy ? null : _send,
                  icon: const Icon(LucideIcons.send, size: 18),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
