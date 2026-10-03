import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/theme_helpers.dart';
import '../../core/finance_format.dart';
import '../models/drill_models.dart';
import '../models/meu_financeiro_models.dart';
import '../services/meu_financeiro_service.dart';
import 'finance_sheet.dart';
import 'meu_financeiro_widgets.dart';

Color _saleStatusColor(String s) {
  switch (s) {
    case 'RECEIVED':
      return FinanceTones.emerald;
    case 'OVERDUE':
    case 'CANCELLED':
      return FinanceTones.rose;
    case 'WAITING_FOR_SIGNATURE':
    case 'EM_CONFERENCIA':
      return FinanceTones.amber;
    default:
      return FinanceTones.sky;
  }
}

/// "Consulta da venda" — somente leitura (`DrawerVendaConsulta.tsx`).
Future<void> showVendaConsultaSheet(
  BuildContext context, {
  required String saleId,
  bool hidden = false,
  MeuFinanceiroService? service,
}) {
  final svc = service ?? MeuFinanceiroService.instance;
  return showFinanceSheet<void>(
    context,
    title: 'Consulta da venda',
    builder: (ctx, scroll) => FinanceAsyncBody<VendaConsulta>(
      scroll: scroll,
      load: () => svc.vendaConsulta(saleId),
      builder: (ctx, v) => _VendaConsultaView(v: v, hidden: hidden, scroll: scroll),
    ),
  );
}

class _VendaConsultaView extends StatelessWidget {
  final VendaConsulta v;
  final bool hidden;
  final ScrollController scroll;

  const _VendaConsultaView({
    required this.v,
    required this.hidden,
    required this.scroll,
  });

  String _brl(double x) => formatBrl(x, hidden: hidden);

  String _pct(double p) {
    final s = p.toStringAsFixed(p.truncateToDouble() == p ? 0 : 2);
    return '${s.replaceAll('.', ',')}%';
  }

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final total = v.parcelas.length;
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        Text(
          v.titulo,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: ThemeHelpers.textColor(context),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (v.fichaVenda != null)
              Text(
                'Ficha ${v.fichaVenda}',
                style: TextStyle(fontSize: 12.5, color: secondary),
              ),
            FinancePill(
              label: saleStatusLabel(v.status),
              color: _saleStatusColor(v.status),
            ),
          ],
        ),
        const FinanceBlockTitle('O imóvel'),
        FinanceField('Empreendimento', v.empreendimento ?? '—'),
        FinanceField('Endereço', v.endereco ?? '—'),
        FinanceField('Unidade', v.unidade ?? '—'),
        if (v.incorporadora != null)
          FinanceField('Incorporadora', v.incorporadora!),
        if (v.saleType != null)
          FinanceField(
            'Tipo',
            v.saleType == 'TERCEIROS'
                ? 'Imóvel de terceiros'
                : v.saleType == 'EMPREENDIMENTO'
                ? 'Empreendimento'
                : humanizeFinanceCode(v.saleType!),
          ),
        const FinanceBlockTitle('O cliente'),
        FinanceField(
          v.compradores.length > 1 ? 'Compradores' : 'Comprador',
          v.compradores.isEmpty ? '—' : v.compradores.join(', '),
        ),
        FinanceField(
          v.vendedores.length > 1 ? 'Vendedores' : 'Vendedor',
          v.vendedores.isEmpty ? '—' : v.vendedores.join(', '),
        ),
        const FinanceBlockTitle('A venda'),
        FinanceField(
          'Data da venda',
          formatFinanceDate(v.saleDate, pattern: 'dd/MM/yyyy'),
        ),
        FinanceField('VGV', _brl(v.vgv)),
        FinanceField(
          'Comissão total (VGC)',
          v.vgc == null
              ? '—'
              : '${_brl(v.vgc!)}${v.comissaoPct == null ? '' : ' · ${_pct(v.comissaoPct!)}'}',
        ),
        FinanceField(
          v.empresas.length > 1 ? 'Empresas' : 'Empresa',
          v.empresas.isEmpty ? '—' : v.empresas.join(', '),
        ),
        FinanceField('Parcelas', '$total'),
        const FinanceBlockTitle('O cronograma'),
        if (v.parcelas.isEmpty)
          const FinanceEmpty(
            text: 'Esta venda ainda não tem cronograma de parcelas.',
          )
        else
          for (final p in v.parcelas)
            FinanceRow(
              title: '${p.numero}/$total',
              subtitle: p.recebidaEm != null
                  ? 'recebida em ${formatFinanceDate(p.recebidaEm, pattern: 'dd/MM/yyyy')}'
                  : 'prevista para ${formatFinanceDate(p.previstaPara, pattern: 'dd/MM/yyyy')}',
              value: _brl(p.valor),
              pill: FinancePill(
                label: saleStatusLabel(p.status),
                color: _saleStatusColor(p.status),
              ),
            ),
        const FinanceBlockTitle('Quem participa'),
        if (v.participantes.isEmpty)
          const FinanceEmpty(text: 'Nenhum participante registrado nesta venda.')
        else
          for (final p in v.participantes) _participante(context, p),
        const SizedBox(height: 16),
        Text(
          'Consulta somente leitura. Alterações na venda são feitas no módulo '
          'de Vendas do Financeiro (web), por quem tem acesso a ele.',
          style: TextStyle(fontSize: 12, height: 1.4, color: secondary),
        ),
      ],
    );
  }

  Widget _participante(BuildContext context, VendaParticipante p) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final papeis = p.papeis
        .map(
          (x) =>
              '${papelNaVendaLabel(x.papel)}${x.percentual == null ? '' : ' · ${_pct(x.percentual!)}'}',
        )
        .join(' · ');
    final t = p.totais;
    Widget cell(String l, double val, Color? c) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l, style: TextStyle(fontSize: 11, color: secondary)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _brl(val),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: c ?? ThemeHelpers.textColor(context),
              ),
            ),
          ),
        ],
      ),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ThemeHelpers.borderLightColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            p.nome ?? 'Participante',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          if (papeis.isNotEmpty)
            Text(papeis, style: TextStyle(fontSize: 12, color: secondary)),
          if (t != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                cell('Devido', t.devido, null),
                cell('Recebido', t.recebido, FinanceTones.emerald),
                cell(
                  'Retido',
                  t.retido,
                  t.retido > 0 ? FinanceTones.amber : null,
                ),
                cell('A receber', t.aReceber, FinanceTones.sky),
              ],
            ),
            if ((t.bonificacao ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'incl. ${_brl(t.bonificacao!)} de bonificação',
                  style: TextStyle(fontSize: 11.5, color: secondary),
                ),
              ),
            if ((t.travado ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '+ ${_brl(t.travado!)} travado · ficha ainda sem assinatura, '
                  'fora dos valores acima',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: FinanceTones.amber,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// "De onde vem este repasse" (`DrawerOrigemRepasse.tsx`).
Future<void> showRepasseOrigemSheet(
  BuildContext context, {
  required String repasseId,
  bool hidden = false,
  MeuFinanceiroService? service,
}) {
  final svc = service ?? MeuFinanceiroService.instance;
  return showFinanceSheet<void>(
    context,
    title: 'De onde vem este repasse',
    builder: (ctx, scroll) => FinanceAsyncBody<RepasseOrigem>(
      scroll: scroll,
      load: () => svc.origem(repasseId),
      builder: (ctx, o) => _OrigemView(
        o: o,
        hidden: hidden,
        scroll: scroll,
        onAbrirVenda: o.saleId == null
            ? null
            : () {
                Navigator.of(ctx).pop();
                showVendaConsultaSheet(
                  context,
                  saleId: o.saleId!,
                  hidden: hidden,
                  service: svc,
                );
              },
      ),
    ),
  );
}

class _OrigemView extends StatelessWidget {
  final RepasseOrigem o;
  final bool hidden;
  final ScrollController scroll;
  final VoidCallback? onAbrirVenda;

  const _OrigemView({
    required this.o,
    required this.hidden,
    required this.scroll,
    this.onAbrirVenda,
  });

  String _brl(double x) => formatBrl(x, hidden: hidden);
  String _d(String? iso) => formatFinanceDate(iso, pattern: 'dd/MM/yyyy');

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final pct = o.meuPercentual;
    final pctTxt = pct == null
        ? '—'
        : '${pct.toStringAsFixed(pct.truncateToDouble() == pct ? 0 : 2).replaceAll('.', ',')}%';
    final semDesconto = o.nfValor <= 0 && o.retido <= 0;
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        if (o.origem == 'titulo') ...[
          const FinanceBlockTitle('O título'),
          FinanceField('Código', o.tituloCodigo ?? '—'),
          if (o.tituloDescricao != null)
            FinanceField('Descrição', o.tituloDescricao!),
          if (o.tituloCliente != null) FinanceField('Cliente', o.tituloCliente!),
          FinanceField('Quem paga', o.empresa ?? '—'),
        ] else ...[
          const FinanceBlockTitle('A venda'),
          FinanceField('Ficha', o.ficha ?? '—'),
          FinanceField('Empreendimento', o.empreendimento ?? '—'),
          if (o.unidade != null) FinanceField('Unidade', o.unidade!),
          FinanceField('Comprador', o.comprador ?? '—'),
          FinanceField('Data da venda', _d(o.dataVenda)),
          FinanceField('Quem paga', o.empresa ?? '—'),
          if (onAbrirVenda != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onAbrirVenda,
                icon: const Icon(LucideIcons.fileText, size: 16),
                label: const Text('Abrir a ficha da venda'),
              ),
            ),
        ],
        const FinanceBlockTitle('A parcela'),
        if (o.parcelaNumero != null)
          FinanceField('Parcela', '${o.parcelaNumero} de ${o.totalDeParcelas}'),
        FinanceField('Valor da parcela', _brl(o.valorDaParcela)),
        FinanceField('Prevista para', _d(o.previstaPara)),
        FinanceField(
          'Recebida em',
          o.recebidaEm == null ? 'ainda não recebida' : _d(o.recebidaEm),
        ),
        if (o.contaQueRecebeu != null) FinanceField('Conta', o.contaQueRecebeu!),
        const FinanceBlockTitle('A minha fatia'),
        FinanceField('Comissão total da parcela', _brl(o.totalDaParcela)),
        FinanceField('Meu papel na venda', papelNaVendaLabel(o.meuPapel)),
        FinanceField('Meu percentual', pctTxt),
        if (pct != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '$pctTxt de ${_brl(o.totalDaParcela)} = ${_brl(o.meuValorBruto)}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: ThemeHelpers.textColor(context),
              ),
            ),
          ),
        const FinanceBlockTitle('O que foi descontado'),
        FinanceField('Bruto', _brl(o.meuValorBruto)),
        if (o.nfValor > 0)
          FinanceField(
            'Nota fiscal${o.nfPercent == null ? '' : ' (${o.nfPercent!.toStringAsFixed(o.nfPercent!.truncateToDouble() == o.nfPercent ? 0 : 2).replaceAll('.', ',')}%)'}',
            '− ${_brl(o.nfValor)}',
            valueColor: FinanceTones.rose,
          ),
        if (o.retido > 0)
          FinanceField(
            'Retido para quitar adiantamento',
            '− ${_brl(o.retido)}',
            valueColor: FinanceTones.rose,
          ),
        FinanceField(
          o.status == 'PAID' ? 'Recebido' : 'A receber',
          _brl(o.liquido),
          bold: true,
        ),
        if (semDesconto)
          Text(
            'Nenhum desconto nesta parcela — o bruto é o que cai na conta.',
            style: TextStyle(fontSize: 12, color: secondary),
          ),
        if (o.bonusValue > 0)
          Text(
            'incl. ${_brl(o.bonusValue)} de bonificação',
            style: TextStyle(fontSize: 12, color: secondary),
          ),
        const FinanceBlockTitle('O que ainda vem desta venda'),
        if (o.aindaVem.isEmpty)
          const FinanceEmpty(text: 'Não há mais parcelas suas nesta venda.')
        else
          for (final p in o.aindaVem)
            FinanceRow(
              title: 'Parcela ${p.numero}',
              subtitle:
                  '${_d(p.previstaPara)} · ${proximoStatusLabel(p.status)}',
              value: _brl(p.meuValor),
            ),
        const SizedBox(height: 8),
        FinanceCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Ainda a receber desta venda',
                  style: TextStyle(fontSize: 13, color: secondary),
                ),
              ),
              Text(
                _brl(o.totalAReceber),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: FinanceTones.sky,
                ),
              ),
            ],
          ),
        ),
        if (o.aDescontar > 0) ...[
          const SizedBox(height: 10),
          FinanceInlineNotice(
            color: FinanceTones.amber,
            icon: LucideIcons.info,
            text:
                'Você tem ${_brl(o.aDescontar)} de adiantamento em aberto, que '
                'será descontado dos próximos repasses — de qualquer venda, não '
                'só desta.',
          ),
        ],
      ],
    );
  }
}
