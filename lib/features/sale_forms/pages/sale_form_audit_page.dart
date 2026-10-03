import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/sale_forms_service.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../sale_form_audit_display.dart';
import '../widgets/sale_form_signature_lock_sheet.dart';
import '../widgets/sale_form_tones.dart';

/// Histórico da ficha ("Raio-X" do web, `SaleFormsPage.tsx`): cada evento
/// com quem fez, quando e o que mudou (antes → depois), na leitura do web
/// (datas BR, R$, CPF, telefone, CEP; mudança só de formato fica de fora).
/// Fonte: `GET /sistema/fichas-venda/:id/auditoria`.
class SaleFormAuditPage extends StatefulWidget {
  const SaleFormAuditPage({
    super.key,
    required this.saleFormId,
    this.formNumber,
  });

  final String saleFormId;
  final String? formNumber;

  @override
  State<SaleFormAuditPage> createState() => _SaleFormAuditPageState();
}

class _SaleFormAuditPageState extends State<SaleFormAuditPage> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Web: a trava não abre nas telas `/fichas-venda…`.
    SignatureLockWatcher.instance.marcarTelaDeFicha(context);
  }

  bool _loading = true;
  String? _erro;
  int _erroStatus = 0;
  List<SaleFormAuditEntry> _eventos = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    final res = await SaleFormsService.instance.getAuditoria(widget.saleFormId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _eventos = res.data!.map(SaleFormAuditEntry.fromJson).toList()
          // Mais recente primeiro.
          ..sort((a, b) {
            final da = a.createdAt, db = b.createdAt;
            if (da == null || db == null) return 0;
            return db.compareTo(da);
          });
      } else {
        _erro = res.message ?? 'Não foi possível carregar o histórico.';
        _erroStatus = res.statusCode;
      }
    });
  }

  double _margem(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w > 752 ? (w - 720) / 2 : 16;
  }

  @override
  Widget build(BuildContext context) {
    final n = (widget.formNumber ?? '').trim();
    return AppScaffold(
      title: n.isEmpty ? 'Histórico da ficha' : 'Histórico · Nº $n',
      showBottomNavigation: false,
      body: _loading
          ? _Esqueleto(margem: _margem(context))
          : _erro != null
              ? AppErrorState.fromApi(
                  message: _erro,
                  statusCode: _erroStatus,
                  onRetry: _load,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _eventos.isEmpty ? _vazio() : _lista(context),
                ),
    );
  }

  Widget _vazio() {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
      children: [
        Icon(LucideIcons.history, size: 40, color: muted),
        const SizedBox(height: 12),
        Text(
          'Sem eventos registrados',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          kSaleFormAuditEmpty,
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, height: 1.4),
        ),
      ],
    );
  }

  Widget _lista(BuildContext context) {
    final m = _margem(context);
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(m, 14, m, 28),
      itemCount: _eventos.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          final total = _eventos.length;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              total == 1 ? '1 evento' : '$total eventos',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w800,
                  ),
            ),
          );
        }
        final e = _eventos[i - 1];
        return _EventoCard(evento: e, ultimo: i == _eventos.length);
      },
    );
  }
}

/// Um evento: marcador na linha do tempo, ação, autor e data, e o que
/// mudou.
class _EventoCard extends StatelessWidget {
  const _EventoCard({required this.evento, required this.ultimo});
  final SaleFormAuditEntry evento;
  final bool ultimo;

  SaleFormTom _tom(BuildContext c) {
    switch (evento.action) {
      case 'create':
        return SaleFormTom.sucesso(c);
      case 'cancel':
      case 'delete_soft':
      case 'signature_lock_refuse':
      case 'invalidate_signatures':
        return SaleFormTom.erro(c);
      case 'transfer_responsibility':
      case 'linked_users_add':
        return SaleFormTom.aviso(c);
      default:
        return SaleFormTom.info(c);
    }
  }

  IconData get _icone {
    switch (evento.action) {
      case 'create':
        return LucideIcons.filePlus;
      case 'cancel':
        return LucideIcons.ban;
      case 'delete_soft':
        return LucideIcons.trash2;
      case 'invalidate_signatures':
      case 'signature_lock_refuse':
        return LucideIcons.penOff;
      case 'transfer_responsibility':
        return LucideIcons.arrowLeftRight;
      case 'linked_users_add':
        return LucideIcons.userPlus;
      default:
        return LucideIcons.pencil;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tom = _tom(context);
    final quando = evento.createdAt == null
        ? '—'
        : DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR')
            .format(evento.createdAt!.toLocal());
    final parts = saleFormPartitionAuditChanges(evento.changes);
    final meta = saleFormAuditMetadataRows(evento.metadata);
    final email = (evento.userEmail ?? '').trim();

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 34,
            child: Column(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: tom.sinal.withValues(alpha: isDark ? 0.2 : 0.13),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_icone, size: 15, color: tom.texto),
                ),
                if (!ultimo)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: ThemeHelpers.borderLightColor(context),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    evento.actionLabel,
                    style: t.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${evento.autor} · $quando',
                    style: t.bodySmall?.copyWith(color: muted),
                  ),
                  // Web: e-mail de quem alterou, embaixo do nome.
                  if (email.isNotEmpty)
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.labelSmall?.copyWith(color: muted),
                    ),
                  if (parts.visible.isNotEmpty) ...[
                    if (parts.cosmeticCount > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        saleFormAuditCosmeticHint(parts.cosmeticCount),
                        style: t.labelSmall?.copyWith(
                          color: muted,
                          fontStyle: FontStyle.italic,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    for (final c in parts.visible) _Mudanca(change: c),
                  ] else ...[
                    const SizedBox(height: 8),
                    Text(
                      saleFormAuditNoChangeText(
                        evento.action,
                        parts.cosmeticCount,
                      ),
                      style: t.bodySmall?.copyWith(color: muted, height: 1.35),
                    ),
                  ],
                  // Web: "Informações extras" sempre que há metadados, com o
                  // registro técnico (JSON) recolhido.
                  if (evento.temInfoExtra) ...[
                    const SizedBox(height: 10),
                    _InfoExtra(metadata: evento.metadata, linhas: meta),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Campo alterado: rótulo e "antes → depois".
class _Mudanca extends StatelessWidget {
  const _Mudanca({required this.change});
  final SaleFormAuditChange change;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final antes = saleFormAuditValue(change.field, change.before);
    final depois = saleFormAuditValue(change.field, change.after);
    final erro = SaleFormTom.erro(context);
    final ok = SaleFormTom.sucesso(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            change.rotulo,
            style: t.labelMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          const SizedBox(height: 6),
          _Valor(rotulo: 'Antes', valor: antes, cor: erro.texto, muted: muted),
          const SizedBox(height: 4),
          _Valor(rotulo: 'Depois', valor: depois, cor: ok.texto, muted: muted),
        ],
      ),
    );
  }
}

class _Valor extends StatelessWidget {
  const _Valor({
    required this.rotulo,
    required this.valor,
    required this.cor,
    required this.muted,
  });
  final String rotulo;
  final String valor;
  final Color cor;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            rotulo.toUpperCase(),
            style: t.labelSmall?.copyWith(
              color: cor,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            valor,
            style: t.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: valor == '—' ? muted : ThemeHelpers.textColor(context),
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _MetaLinha extends StatelessWidget {
  const _MetaLinha({required this.rotulo, required this.valor});
  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rotulo,
            style: t.labelSmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            valor,
            style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// "Informações extras" do web: linhas legíveis (ou o aviso de fallback) e
/// "Ver registro técnico (JSON)" recolhido.
class _InfoExtra extends StatelessWidget {
  const _InfoExtra({required this.metadata, required this.linhas});
  final Map<String, dynamic>? metadata;
  final List<({String label, String value})> linhas;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final borda = ThemeHelpers.borderColor(context).withValues(alpha: 0.7);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borda),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Informações extras',
            style: t.labelMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          if (linhas.isNotEmpty)
            for (final r in linhas) _MetaLinha(rotulo: r.label, valor: r.value)
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                kSaleFormAuditMetaFallback,
                style: t.bodySmall?.copyWith(color: muted, height: 1.35),
              ),
            ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              dense: true,
              visualDensity: VisualDensity.compact,
              title: Text(
                'Ver registro técnico (JSON)',
                style: t.labelMedium?.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: borda.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SelectableText(
                      saleFormAuditMetadataJson(metadata),
                      style: t.labelSmall?.copyWith(
                        fontFamily: 'monospace',
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Esqueleto extends StatelessWidget {
  const _Esqueleto({required this.margem});
  final double margem;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(margem, 14, margem, 28),
      children: [
        const SkeletonBox(width: 80, height: 14, borderRadius: 6),
        const SizedBox(height: 16),
        for (var i = 0; i < 4; i++) ...[
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 30, height: 30, borderRadius: 999),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 120, height: 14, borderRadius: 6),
                    SizedBox(height: 6),
                    SkeletonBox(width: 180, height: 11, borderRadius: 6),
                    SizedBox(height: 10),
                    SkeletonBox(height: 64, borderRadius: 12),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
        ],
      ],
    );
  }
}
