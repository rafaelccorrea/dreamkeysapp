import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/sale_forms_service.dart';
import '../../../shared/widgets/app_scaffold.dart';

/// Visualização (read-only) de uma ficha de venda — Fase 1.
class SaleFormDetailPage extends StatefulWidget {
  const SaleFormDetailPage({super.key, required this.saleFormId});

  final String saleFormId;

  @override
  State<SaleFormDetailPage> createState() => _SaleFormDetailPageState();
}

class _SaleFormDetailPageState extends State<SaleFormDetailPage> {
  bool _loading = true;
  String? _error;
  SaleForm? _form;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await SaleFormsService.instance.getById(widget.saleFormId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _form = res.data;
      } else {
        _error = res.message ?? 'Erro ao carregar a ficha de venda.';
      }
    });
  }

  Color _statusTone(SaleFormStatus s) {
    switch (s) {
      case SaleFormStatus.finalized:
        return const Color(0xFF16A34A);
      case SaleFormStatus.canceled:
        return const Color(0xFFDC2626);
      case SaleFormStatus.processing:
        return const Color(0xFF6366F1);
      case SaleFormStatus.waitingForSignature:
        return const Color(0xFFD97706);
    }
  }

  String _money(double? v) => v == null
      ? '—'
      : NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(v);

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Ficha de venda',
      showBottomNavigation: false,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildContent(_form!),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(SaleForm f) {
    final theme = Theme.of(context);
    final tone = _statusTone(f.status);
    final muted = ThemeHelpers.textSecondaryColor(context);

    // Endereço do imóvel resumido.
    final propLoc = [
      f.propertyNeighborhood?.trim(),
      f.propertyCity?.trim(),
      f.propertyState?.trim(),
    ].where((e) => e != null && e.isNotEmpty).join(', ');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        // ── Cabeçalho ──────────────────────────────────────────────────
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                f.formNumber.isEmpty ? '—' : 'Nº ${f.formNumber}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: tone.withValues(alpha: 0.3)),
              ),
              child: Text(
                f.status.label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                  fontSize: 10,
                ),
              ),
            ),
            const Spacer(),
            Text(
              f.saleFormType.label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: muted,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          f.buyerName?.trim().isNotEmpty == true
              ? f.buyerName!
              : 'Comprador não informado',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Valor da venda',
          style: theme.textTheme.labelSmall?.copyWith(
            color: muted,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _money(f.saleValue),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            color: tone,
            letterSpacing: -0.5,
          ),
        ),

        if (f.status == SaleFormStatus.canceled &&
            (f.cancellationReason?.isNotEmpty ?? false)) ...[
          const SizedBox(height: 14),
          _ReasonBox(
            title: 'Motivo do cancelamento',
            reason: f.cancellationReason!,
            tone: const Color(0xFFDC2626),
          ),
        ],
        if (f.deletedAt != null && (f.deletionReason?.isNotEmpty ?? false)) ...[
          const SizedBox(height: 14),
          _ReasonBox(
            title: 'Motivo da exclusão',
            reason: f.deletionReason!,
            tone: const Color(0xFFDC2626),
          ),
        ],

        const SizedBox(height: 22),

        // ── Comprador ──────────────────────────────────────────────────
        _Section(
          icon: Icons.person_outline,
          title: 'COMPRADOR',
          children: [
            _Field('Nome', f.buyerName),
            _Field('CPF/CNPJ', f.buyerCpf),
            _Field('E-mail', f.buyerEmail),
            _Field('Telefone', f.buyerPhone),
            _Field('Cidade/UF', _join(f.buyerCity, f.buyerState)),
          ],
        ),

        // ── Vendedor ───────────────────────────────────────────────────
        _Section(
          icon: Icons.person_outline,
          title: 'VENDEDOR',
          children: [
            _Field('Nome', f.sellerName),
            _Field('CPF/CNPJ', f.sellerCpf),
            _Field('E-mail', f.sellerEmail),
            _Field('Telefone', f.sellerPhone),
          ],
        ),

        // ── Imóvel / Empreendimento ────────────────────────────────────
        if (f.saleFormType.isEmpreendimento)
          _Section(
            icon: Icons.domain_outlined,
            title: 'EMPREENDIMENTO',
            children: [
              _Field('Incorporadora',
                  f.empreendimentoData?['incorporadora']?.toString()),
              _Field('Empreendimento',
                  f.empreendimentoData?['empreendimento']?.toString()),
              _Field('Unidade', f.empreendimentoData?['unidade']?.toString()),
              _Field('Forma de pagamento',
                  f.empreendimentoData?['formaPagamento']?.toString()),
            ],
          )
        else
          _Section(
            icon: Icons.home_work_outlined,
            title: 'IMÓVEL',
            children: [
              _Field('Código', f.propertyCode),
              _Field('Localização', propLoc.isEmpty ? null : propLoc),
            ],
          ),

        // ── Financeiro ─────────────────────────────────────────────────
        _Section(
          icon: Icons.attach_money_rounded,
          title: 'FINANCEIRO',
          children: [
            _Field('Valor da venda', _money(f.saleValue)),
            _Field('Comissão total', _money(f.totalCommission)),
            _Field('Meta', _money(f.goalValue)),
            _Field(
              'Modelo de comissão',
              f.commissionPaymentModel == CommissionPaymentModel.naoAplicavel
                  ? 'Não aplicável'
                  : 'Obrigatório',
            ),
          ],
        ),

        // ── Comissões / corretores ─────────────────────────────────────
        if (f.corretores.isNotEmpty)
          _Section(
            icon: Icons.groups_outlined,
            title: 'CORRETORES',
            children: [
              for (final c in f.corretores)
                if (c is Map)
                  _Field(
                    (c['nome'] ?? c['name'] ?? 'Corretor').toString(),
                    c['porcentagem'] != null ? '${c['porcentagem']}%' : null,
                  ),
            ],
          ),

        // ── Geral ──────────────────────────────────────────────────────
        _Section(
          icon: Icons.info_outline,
          title: 'GERAL',
          children: [
            _Field('Equipe', f.teamName),
            _Field('Unidade de venda', f.saleUnit),
            _Field('Mídia de origem', f.mediaSource),
            _Field('Gerente', f.managerName),
            _Field('Corretor externo', f.externalBrokerName),
            _Field('Criado por', f.creatorName),
            _Field(
              'Criado em',
              f.createdAt != null
                  ? DateFormat('dd/MM/yyyy HH:mm', 'pt_BR')
                      .format(f.createdAt!.toLocal())
                  : null,
            ),
            _Field('Descrição', f.description),
          ],
        ),
      ],
    );
  }

  String? _join(String? a, String? b) {
    final parts = [a?.trim(), b?.trim()].where((e) => e != null && e.isNotEmpty);
    return parts.isEmpty ? null : parts.join(' / ');
  }
}

class _ReasonBox extends StatelessWidget {
  const _ReasonBox(
      {required this.title, required this.reason, required this.tone});
  final String title;
  final String reason;
  final Color tone;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: tone,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            reason,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

/// Seção read-only — título com filete + lista de campos. Some inteira se
/// nenhum campo tiver valor.
class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.children,
  });
  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final visible = children.whereType<_Field>().where((f) => f.hasValue).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: muted),
              const SizedBox(width: 7),
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 1,
                  color: ThemeHelpers.borderLightColor(context)
                      .withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...visible,
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);
  final String label;
  final String? value;

  bool get hasValue => value != null && value!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!hasValue) return const SizedBox.shrink();
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
