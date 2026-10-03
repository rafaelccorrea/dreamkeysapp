import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../core/finance_api_client.dart';
import '../core/finance_format.dart';
import '../core/finance_route_names.dart';
import '../core/finance_visibility.dart';
import '../meu_financeiro/models/meu_financeiro_models.dart';
import '../meu_financeiro/widgets/meu_financeiro_widgets.dart';

/// Ganhos do card (`GET /repasses/earnings` → `brokers[0]`).
class MeuDinheiroData {
  final EarningsTotals totals;
  final int vendas;
  final double saldoAdiantamento;
  final double saldoDevedor;
  const MeuDinheiroData({
    required this.totals,
    this.vendas = 0,
    this.saldoAdiantamento = 0,
    this.saldoDevedor = 0,
  });

  /// `null` = esconder o card (sem corretor no escopo — igual ao web).
  static MeuDinheiroData? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final brokers = raw['brokers'];
    if (brokers is! List || brokers.isEmpty || brokers.first is! Map) {
      return null;
    }
    final b = (brokers.first as Map).map((k, v) => MapEntry(k.toString(), v));
    return MeuDinheiroData(
      totals: EarningsTotals.fromJson(b),
      vendas: b['sales'] is List ? (b['sales'] as List).length : 0,
      saldoAdiantamento: financeNum(b['saldoAdiantamento']),
      saldoDevedor: financeNum(b['saldoDevedor']),
    );
  }
}

/// "Meu dinheiro" na Home (`MeusGanhosCard.tsx`). UMA chamada por
/// montagem (sem PIN — rota liberada no back), sem cascata e sem cache de
/// valor; falha ou empresa sem o módulo = card some, em silêncio. Tocar
/// leva ao Meu Financeiro (que pede o PIN).
class MeuDinheiroCard extends StatefulWidget {
  final FinanceApiClient? client;
  const MeuDinheiroCard({super.key, this.client});

  @override
  State<MeuDinheiroCard> createState() => _MeuDinheiroCardState();
}

class _MeuDinheiroCardState extends State<MeuDinheiroCard> {
  MeuDinheiroData? _data;
  int _seq = 0;

  bool get _hasModule =>
      companyHasFinanceModule(
        ModuleAccessService.instance.selectedCompany?.availableModules,
      ) ==
      true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!_hasModule) return;
    final seq = ++_seq;
    final res = await (widget.client ?? FinanceApiClient.instance)
        .get<dynamic>('/repasses/earnings');
    if (!mounted || seq != _seq) return;
    setState(() => _data = res.success ? MeuDinheiroData.fromJson(res.data) : null);
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null || !_hasModule) return const SizedBox.shrink();
    final t = d.totals;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    Widget kpi(String label, double v, Color c) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11.5, color: secondary)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatBrl(v),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: c,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: FinanceCard(
        onTap: () =>
            Navigator.of(context).pushNamed(FinanceRouteNames.meuDashboard),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.wallet, size: 18, color: financeAccent(context)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Meu dinheiro',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                ),
                Text(
                  '${d.vendas} ${d.vendas == 1 ? 'venda' : 'vendas'}',
                  style: TextStyle(fontSize: 12, color: secondary),
                ),
                const SizedBox(width: 4),
                Icon(LucideIcons.chevronRight, size: 16, color: secondary),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                kpi('Nas minhas vendas', t.devido, const Color(0xFF2563EB)),
                kpi('Já recebi', t.recebido, FinanceTones.emerald),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                kpi('Retido do adiantamento', t.retido, const Color(0xFFB45309)),
                kpi('Tenho a receber', t.aReceber, const Color(0xFF0891B2)),
              ],
            ),
            if ((t.travado ?? 0) > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Não inclui ${formatBrl(t.travado!)} de fichas ainda sem '
                'assinatura — entra quando a ficha for assinada.',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: FinanceTones.amber,
                ),
              ),
            ],
            if (d.saldoAdiantamento > 0) ...[
              const SizedBox(height: 10),
              FinanceInlineNotice(
                color: FinanceTones.amber,
                icon: LucideIcons.handCoins,
                text:
                    'Você tem ${formatBrl(d.saldoAdiantamento)} de adiantamento em '
                    'aberto com a imobiliária'
                    '${d.saldoDevedor > d.saldoAdiantamento ? ' (dívida total, somando estornos: ${formatBrl(d.saldoDevedor)})' : ''}'
                    '. Ele é quitado aos poucos, retido dos seus próximos repasses.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
