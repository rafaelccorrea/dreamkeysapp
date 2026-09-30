import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/sale_forms_service.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../widgets/sale_form_anexos_sheet.dart';
import '../widgets/sale_form_card.dart';
import '../widgets/sale_form_row_actions.dart';
import '../widgets/sale_form_row_rules.dart';
import '../widgets/sale_form_signatures_sheet.dart';
import '../widgets/sale_form_tones.dart';

/// Visualização (read-only) de uma ficha de venda — Fase 1.
///
/// De cima para baixo: quem é (nº, status, tipo, comprador), quanto vale,
/// o que dá para fazer (Editar + menu), o andamento (assinaturas e anexos)
/// e os dados em seções. Campo sem valor não aparece.
class SaleFormDetailPage extends StatefulWidget {
  const SaleFormDetailPage({super.key, required this.saleFormId});

  final String saleFormId;

  @override
  State<SaleFormDetailPage> createState() => _SaleFormDetailPageState();
}

class _SaleFormDetailPageState extends State<SaleFormDetailPage> {
  bool _loading = true;
  String? _error;
  // Sem o código HTTP não dá para distinguir "sem permissão" de "fora do ar".
  int _errorStatus = 0;
  SaleForm? _form;

  // Resumo de assinaturas/anexos (carregado após a ficha; null = ainda carregando).
  int? _sigTotal;
  int? _sigSigned;
  int? _anexoCount;

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
        _error = null;
        _errorStatus = 0;
      } else {
        _error = res.message ?? 'Erro ao carregar a ficha de venda.';
        _errorStatus = res.statusCode;
      }
    });
    if (res.success && res.data != null) {
      _loadSummary();
    }
  }

  /// Busca contagens de assinaturas e anexos para o resumo — falha em silêncio
  /// (os pontos de entrada continuam abrindo os sheets normalmente).
  Future<void> _loadSummary() async {
    final sigsFut =
        SaleFormsService.instance.listSignatures(widget.saleFormId);
    final anexosFut = SaleFormsService.instance.listAnexos(widget.saleFormId);
    final sigsRes = await sigsFut;
    final anexosRes = await anexosFut;
    if (!mounted) return;
    setState(() {
      if (sigsRes.success && sigsRes.data != null) {
        // Mesma conta do Status do sheet: links cancelados/expirados (de um
        // envio anterior) não entram no "X de Y".
        final ativas = sigsRes.data!.where((s) {
          final st = s.status.toLowerCase();
          return st != 'cancelled' && st != 'canceled' && st != 'expired';
        }).toList();
        _sigTotal = ativas.length;
        _sigSigned = ativas.where((s) => s.isSigned).length;
      }
      if (anexosRes.success && anexosRes.data != null) {
        _anexoCount = anexosRes.data!.length;
      }
    });
  }

  void _openSignatures() {
    showSaleFormSignaturesSheet(
      context,
      saleFormId: widget.saleFormId,
      formNumber: _form?.formNumber,
      canInvalidate: _form != null &&
          SaleFormRowRules(_form!).canCancelSignaturesForResend,
      onChanged: _loadSummary,
    );
  }

  Future<void> _onAction(SaleForm f, SaleFormRowAction a) async {
    final changed = await runSaleFormRowAction(context, f, a);
    if (!mounted || !changed) return;
    // Excluída/cancelada volta para a lista já recarregada.
    if (a == SaleFormRowAction.excluir) {
      Navigator.of(context).pop(true);
      return;
    }
    await _load();
    _loadSummary();
  }

  void _openAnexos() {
    showSaleFormAnexosSheet(
      context,
      saleFormId: widget.saleFormId,
      formNumber: _form?.formNumber,
      onChanged: _loadSummary,
    );
  }

  /// Dinheiro formatado; `null` quando não há valor (o campo some).
  String? _money(double? v) => v == null
      ? null
      : NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(v);

  /// Margem lateral: 16 no celular; em tela larga, coluna de até 720.
  double _margem(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w > 752 ? (w - 720) / 2 : 16;
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Ficha de venda',
      showBottomNavigation: false,
      body: _loading
          ? _DetalheSkeleton(margem: _margem(context))
          : _error != null
              ? _buildError()
              : _buildContent(_form!),
    );
  }

  Widget _buildError() {
    return AppErrorState.fromApi(
      message: _error,
      statusCode: _errorStatus,
      onRetry: _load,
    );
  }

  Widget _buildContent(SaleForm f) {
    final theme = Theme.of(context);
    final tom = SaleFormTom.doStatus(context, f.status);
    final erro = SaleFormTom.erro(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final m = _margem(context);
    final vendedor = f.sellerName?.trim() ?? '';
    final comissao = _money(f.totalCommission);

    // Endereço do imóvel resumido.
    final propLoc = [
      f.propertyNeighborhood?.trim(),
      f.propertyCity?.trim(),
      f.propertyState?.trim(),
    ].where((e) => e != null && e.isNotEmpty).join(', ');

    return ListView(
      padding: EdgeInsets.fromLTRB(m, 14, m, 28),
      children: [
        // ── Cabeçalho ──────────────────────────────────────────────────
        // Wrap: nº, status e tipo quebram de linha em vez de estourar.
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Etiqueta(
              texto: f.formNumber.isEmpty ? 'Sem nº' : 'Nº ${f.formNumber}',
              tom: tom,
            ),
            _Etiqueta(
              texto: f.statusLabel.toUpperCase(),
              tom: tom,
              pilula: true,
            ),
            _Etiqueta(
              texto: f.saleFormType.label.toUpperCase(),
              tom: SaleFormTom(muted, muted),
            ),
            if (f.deletedAt != null)
              _Etiqueta(texto: 'EXCLUÍDA', tom: erro, pilula: true),
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
        if (vendedor.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Vendedor: $vendedor',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              flex: 3,
              child: _Valor(
                rotulo: 'VALOR DA VENDA',
                valor: _money(f.saleValue) ?? 'Não informado',
                destaque: true,
                vazio: f.saleValue == null,
              ),
            ),
            if (comissao != null) ...[
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _Valor(
                  rotulo: 'COMISSÃO',
                  valor: comissao,
                  alinharFim: true,
                ),
              ),
            ],
          ],
        ),

        const SizedBox(height: 18),
        _AcoesDaFicha(
          rules: SaleFormRowRules(f),
          onAction: (a) => _onAction(f, a),
        ),

        if (f.status == SaleFormStatus.canceled &&
            (f.cancellationReason?.isNotEmpty ?? false)) ...[
          const SizedBox(height: 14),
          _ReasonBox(
            title: f.distratoAberto
                ? 'Motivo do distrato'
                : 'Motivo do cancelamento',
            reason: f.cancellationReason!,
            tom: erro,
          ),
        ],
        if (f.deletedAt != null && (f.deletionReason?.isNotEmpty ?? false)) ...[
          const SizedBox(height: 14),
          _ReasonBox(
            title: 'Motivo da exclusão',
            reason: f.deletionReason!,
            tom: erro,
          ),
        ],

        const SizedBox(height: 24),

        // ── Assinaturas & Anexos ───────────────────────────────────────
        _buildDocumentsSection(context),

        const SizedBox(height: 24),

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
            // Só o texto exibido muda: o valor gravado segue
            // `nao_aplicavel` (Não aplicável).
            _Field(
              'Modelo de comissão',
              f.commissionPaymentModel == CommissionPaymentModel.naoAplicavel
                  ? 'Não se aplica'
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

  /// Seção flush com os dois pontos de entrada (assinaturas + anexos), cada um
  /// com um resumo carregado no load.
  Widget _buildDocumentsSection(BuildContext context) {
    String sigSummary() {
      if (_sigTotal == null) return 'Toque para ver e enviar';
      if (_sigTotal == 0) return 'Nenhuma assinatura enviada ainda';
      final assinadas = _sigSigned ?? 0;
      if (assinadas >= _sigTotal!) return 'Todos assinaram (${_sigTotal!})';
      return '$assinadas de ${_sigTotal!} assinaram';
    }

    String anexoSummary() {
      if (_anexoCount == null) return 'Toque para ver os anexos';
      if (_anexoCount == 0) return 'Nenhum anexo ainda';
      return _anexoCount == 1 ? '1 anexo' : '${_anexoCount!} anexos';
    }

    final total = _sigTotal ?? 0;
    final progresso = total > 0
        ? ((_sigSigned ?? 0) / total).clamp(0.0, 1.0).toDouble()
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _TituloSecao(
          icon: Icons.folder_outlined,
          title: 'ASSINATURAS E ANEXOS',
        ),
        const SizedBox(height: 12),
        _ActionCard(
          icon: Icons.draw_outlined,
          tom: SaleFormTom.sucesso(context),
          title: 'Assinaturas',
          subtitle: sigSummary(),
          progresso: progresso,
          onTap: _openSignatures,
        ),
        const SizedBox(height: 10),
        _ActionCard(
          icon: Icons.attach_file_rounded,
          tom: SaleFormTom.info(context),
          title: 'Anexos',
          subtitle: anexoSummary(),
          onTap: _openAnexos,
        ),
      ],
    );
  }

  String? _join(String? a, String? b) {
    final parts = [a?.trim(), b?.trim()].where((e) => e != null && e.isNotEmpty);
    return parts.isEmpty ? null : parts.join(' / ');
  }
}

/// Etiqueta do cabeçalho (nº, status, tipo): tom no fundo e no texto; a
/// pílula (status) ganha borda.
class _Etiqueta extends StatelessWidget {
  const _Etiqueta({
    required this.texto,
    required this.tom,
    this.pilula = false,
  });
  final String texto;
  final SaleFormTom tom;
  final bool pilula;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: pilula ? 4 : 3),
      decoration: BoxDecoration(
        color: tom.sinal.withValues(alpha: isDark ? 0.16 : 0.12),
        borderRadius: BorderRadius.circular(pilula ? 999 : 6),
        border: pilula
            ? Border.all(
                color: tom.sinal.withValues(alpha: isDark ? 0.4 : 0.45),
              )
            : null,
      ),
      child: Text(
        texto,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: tom.texto,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
              fontSize: pilula ? 10 : 11,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
      ),
    );
  }
}

/// Valor em destaque (rótulo + número). Nunca vira reticências: encolhe
/// para caber em tela estreita ou fonte grande.
class _Valor extends StatelessWidget {
  const _Valor({
    required this.rotulo,
    required this.valor,
    this.destaque = false,
    this.alinharFim = false,
    this.vazio = false,
  });
  final String rotulo;
  final String valor;
  final bool destaque;
  final bool alinharFim;
  final bool vazio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final TextStyle? style;
    if (vazio) {
      style = theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: muted,
      );
    } else if (destaque) {
      style = theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w900,
        letterSpacing: -0.6,
        height: 1.05,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
    } else {
      style = theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w900,
        letterSpacing: -0.3,
        height: 1.05,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
    }
    return Column(
      crossAxisAlignment:
          alinharFim ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          rotulo,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: muted,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment:
              alinharFim ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(valor, maxLines: 1, softWrap: false, style: style),
        ),
      ],
    );
  }
}

class _ReasonBox extends StatelessWidget {
  const _ReasonBox({
    required this.title,
    required this.reason,
    required this.tom,
  });
  final String title;
  final String reason;
  final SaleFormTom tom;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tom.sinal.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tom.sinal.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: tom.texto,
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

/// Cartão de ação (abre um bottom sheet) — ícone tonal, título, resumo,
/// barra de andamento opcional e chevron.
class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.tom,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.progresso,
  });

  final IconData icon;
  final SaleFormTom tom;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// 0..1 — quantos já assinaram; null = sem barra.
  final double? progresso;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = progresso;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.7),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tom.sinal.withValues(alpha: isDark ? 0.18 : 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 20, color: tom.texto),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                    ),
                    if (p != null) ...[
                      const SizedBox(height: 7),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: p,
                          minHeight: 4,
                          backgroundColor: ThemeHelpers.borderLightColor(
                            context,
                          ),
                          valueColor: AlwaysStoppedAnimation(tom.sinal),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Título de seção: ícone + rótulo + filete até a margem.
class _TituloSecao extends StatelessWidget {
  const _TituloSecao({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Row(
      children: [
        Icon(icon, size: 14, color: muted),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textColor(context),
              letterSpacing: 1.4,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            color: ThemeHelpers.borderLightColor(
              context,
            ).withValues(alpha: 0.8),
          ),
        ),
      ],
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TituloSecao(icon: icon, title: title),
          const SizedBox(height: 10),
          ...visible,
        ],
      ),
    );
  }
}

/// Linha rótulo | valor. Em tela estreita ou fonte grande o rótulo sobe e o
/// valor fica embaixo, com a largura toda.
class _Field extends StatelessWidget {
  const _Field(this.label, this.value);
  final String label;
  final String? value;

  bool get hasValue => value != null && value!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!hasValue) return const SizedBox.shrink();
    final muted = ThemeHelpers.textSecondaryColor(context);
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: muted,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        );
    final valueStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: LayoutBuilder(
        builder: (context, c) {
          final escala = MediaQuery.textScalerOf(context).scale(1);
          if (c.maxWidth < 300 || escala > 1.3) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: labelStyle),
                const SizedBox(height: 2),
                Text(value!, style: valueStyle),
              ],
            );
          }
          final larguraRotulo = (c.maxWidth * 0.36).clamp(96.0, 140.0);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: larguraRotulo.toDouble(),
                child: Text(label, style: labelStyle),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(value!, style: valueStyle)),
            ],
          );
        },
      ),
    );
  }
}

/// Faixa de ações do detalhe: Editar em chapa (com cadeado e motivo quando a
/// ficha não pode mudar — o web bloqueia e informa, não esconde) + o mesmo
/// menu de ações da listagem.
class _AcoesDaFicha extends StatelessWidget {
  const _AcoesDaFicha({required this.rules, required this.onAction});
  final SaleFormRowRules rules;
  final ValueChanged<SaleFormRowAction> onAction;

  @override
  Widget build(BuildContext context) {
    final text = ThemeHelpers.textColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bloqueada = !rules.canEdit;
    return Row(
      children: [
        if (rules.showEdit)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => onAction(SaleFormRowAction.editar),
              icon: Icon(
                bloqueada ? Icons.lock_outline_rounded : Icons.edit_outlined,
                size: 18,
                color: bloqueada ? muted : text,
              ),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  bloqueada ? 'Editar · bloqueada' : 'Editar ficha',
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: bloqueada ? muted : text,
                  ),
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: text,
                minimumSize: const Size(0, 44),
                backgroundColor: dark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.black.withValues(alpha: 0.025),
                side: BorderSide(color: ThemeHelpers.borderColor(context)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          )
        else
          const Spacer(),
        const SizedBox(width: 10),
        SaleFormActionsMenu(
          rules: rules,
          onAction: onAction,
          noDetalhe: true,
        ),
      ],
    );
  }
}

/// Esqueleto fiel ao detalhe: etiquetas, comprador, valor, ações, os dois
/// cartões (assinaturas/anexos) e seções de campos.
class _DetalheSkeleton extends StatelessWidget {
  const _DetalheSkeleton({required this.margem});
  final double margem;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(margem, 14, margem, 28),
      children: [
        Row(
          children: const [
            SkeletonBox(width: 64, height: 20, borderRadius: 6),
            SizedBox(width: 6),
            SkeletonBox(width: 118, height: 20, borderRadius: 999),
            SizedBox(width: 6),
            SkeletonBox(width: 72, height: 20, borderRadius: 6),
          ],
        ),
        const SizedBox(height: 14),
        const SkeletonBox(width: 240, height: 26, borderRadius: 8),
        const SizedBox(height: 8),
        const SkeletonBox(width: 160, height: 14, borderRadius: 6),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: const [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonText(width: 90, height: 9),
                  SizedBox(height: 7),
                  SkeletonBox(width: 150, height: 24, borderRadius: 6),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SkeletonText(width: 60, height: 9),
                  SizedBox(height: 7),
                  SkeletonBox(width: 90, height: 18, borderRadius: 6),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: const [
            Expanded(child: SkeletonBox(height: 44, borderRadius: 12)),
            SizedBox(width: 10),
            SkeletonBox(width: 44, height: 44, borderRadius: 12),
          ],
        ),
        const SizedBox(height: 28),
        const SkeletonBox(width: 170, height: 12, borderRadius: 6),
        const SizedBox(height: 14),
        const SkeletonBox(height: 66, borderRadius: 14),
        const SizedBox(height: 10),
        const SkeletonBox(height: 66, borderRadius: 14),
        const SizedBox(height: 28),
        for (var s = 0; s < 2; s++) ...[
          const SkeletonBox(width: 120, height: 12, borderRadius: 6),
          const SizedBox(height: 12),
          for (var i = 0; i < 4; i++) ...[
            Row(
              children: const [
                SkeletonBox(width: 96, height: 12, borderRadius: 6),
                SizedBox(width: 10),
                Expanded(child: SkeletonText(height: 14)),
              ],
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}
