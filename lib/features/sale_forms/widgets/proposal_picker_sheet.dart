import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/purchase_proposals_service.dart';
import '../../../shared/utils/input_formatters.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../services/sale_form_proposal_link_service.dart';

// ─── Rótulos (mesmos dados do card do `SelectPropostaModal` do web) ─────────

/// Número da proposta para a tela. Sem número cadastrado: "sem número" — o
/// id interno não vai para a tela (a busca ainda casa pelo começo do id).
String propostaNumeroLabel(PurchaseProposal p) {
  final n = p.proposalNumber.trim();
  return n.isNotEmpty ? n : 'sem número';
}

/// Valor proposto em reais ("R$ 1.250.000,00") ou `null` sem valor.
String? propostaValorLabel(PurchaseProposal p) {
  final v = p.proposedPrice;
  if (v == null) return null;
  return 'R\$ ${CurrencyInputFormatter.format(v)}';
}

/// Data da proposta sem fuso ("2026-09-20T00:00:00.000Z" → 20/09/2026).
String? propostaDataLabel(PurchaseProposal p) {
  final s = (p.raw['proposalDate'] ?? '').toString().trim();
  if (s.isEmpty) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
  final d = m != null
      ? DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!))
      : DateTime.tryParse(s);
  return d == null ? null : DateFormat('dd/MM/yyyy').format(d);
}

/// Imóvel em uma linha: endereço + número · cidade/UF (ou o código).
String propostaImovelLabel(PurchaseProposal p) {
  final rua = p.propertyAddress ?? p.propertyStreet;
  final partes = <String>[
    if (rua != null) p.propertyNumber != null ? '$rua, ${p.propertyNumber}' : rua,
    if (p.propertyCity != null)
      p.propertyState != null
          ? '${p.propertyCity}/${p.propertyState}'
          : p.propertyCity!,
  ];
  if (partes.isNotEmpty) return partes.join(' · ');
  final cod = p.propertyCode ?? p.propertyRegistry;
  if (cod != null) return 'Imóvel $cod';
  return 'Imóvel não informado';
}

// ─── Folha de seleção ───────────────────────────────────────────────────────

/// "Preencher a partir de uma proposta" (`SelectPropostaModal` do web):
/// propostas finalizadas ainda sem ficha de venda, com busca. Devolve a
/// proposta tocada (resumo da lista — quem chama carrega o detalhe) ou
/// `null` ("Criar ficha sem proposta" / fechar).
Future<PurchaseProposal?> showSaleFormProposalPicker(
  BuildContext context, {
  required Color accent,
  String? selectedId,
}) {
  return showModalBottomSheet<PurchaseProposal>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ProposalPickerSheet(accent: accent, selectedId: selectedId),
  );
}

class _ProposalPickerSheet extends StatefulWidget {
  const _ProposalPickerSheet({required this.accent, this.selectedId});
  final Color accent;
  final String? selectedId;
  @override
  State<_ProposalPickerSheet> createState() => _ProposalPickerSheetState();
}

class _ProposalPickerSheetState extends State<_ProposalPickerSheet> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  /// Candidatas da carga inicial (as mesmas 100 do web).
  List<PurchaseProposal> _base = const [];
  bool _loading = true;
  String? _erro;
  int _erroStatus = 0;

  /// Busca no back (alcança além das 100 da carga inicial).
  String _q = '';
  List<PurchaseProposal> _hitsServidor = const [];
  bool _buscando = false;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    final res = await SaleFormProposalLinkService.instance.listarCandidatas();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _base = res.data!;
      } else {
        _erro = res.message ?? 'Erro ao carregar propostas.';
        _erroStatus = res.statusCode;
      }
    });
  }

  void _onBusca(String v) {
    final q = v.trim();
    setState(() {
      _q = q;
      _hitsServidor = const [];
      _buscando = q.isNotEmpty;
    });
    _debounce?.cancel();
    if (q.isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 350), () => _buscar(q));
  }

  Future<void> _buscar(String q) async {
    final seq = ++_seq;
    final res =
        await SaleFormProposalLinkService.instance.listarCandidatas(search: q);
    if (!mounted || seq != _seq || q != _q) return;
    setState(() {
      _buscando = false;
      _hitsServidor = res.success && res.data != null ? res.data! : const [];
    });
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[áàâãä]'), 'a')
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[íìîï]'), 'i')
      .replaceAll(RegExp('[óòôõö]'), 'o')
      .replaceAll(RegExp('[úùûü]'), 'u')
      .replaceAll('ç', 'c');

  bool _casa(PurchaseProposal p, String q) {
    final nq = _norm(q);
    // Sem número, a busca continua casando pelo começo do id (como antes).
    final semNumero = p.proposalNumber.trim().isEmpty;
    final campos = [
      propostaNumeroLabel(p),
      if (semNumero) p.id.length > 8 ? p.id.substring(0, 8) : p.id,
      p.proponentName ?? '',
      p.ownerName ?? '',
      propostaImovelLabel(p),
      p.propertyCode ?? '',
    ];
    if (campos.any((c) => _norm(c).contains(nq))) return true;
    final dq = q.replaceAll(RegExp(r'\D'), '');
    if (dq.length < 3) return false;
    return [p.proponentCpf, p.ownerCpf]
        .any((c) => (c ?? '').replaceAll(RegExp(r'\D'), '').contains(dq));
  }

  /// Filtro local imediato + o que o back achou (sem repetir).
  List<PurchaseProposal> get _visiveis {
    if (_q.isEmpty) return _base;
    final out = _base.where((p) => _casa(p, _q)).toList();
    final ids = out.map((p) => p.id).toSet();
    for (final p in _hitsServidor) {
      if (ids.add(p.id)) out.add(p);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final text = ThemeHelpers.textColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = widget.accent;
    final hair = ThemeHelpers.borderLightColor(context);
    final teclado = mq.viewInsets.bottom > 0;
    // Pouca altura útil (teclado aberto em paisagem, tela baixa): sem alça.
    final apertado = mq.size.height - mq.viewInsets.bottom < 420;
    OutlineInputBorder borda(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c, width: w),
        );

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.88),
        child: Container(
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!apertado)
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10),
                    decoration: BoxDecoration(
                      color: ThemeHelpers.borderColor(context),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              // Cabeçalho fixo e enxuto: título à esquerda, fechar à direita.
              Padding(
                padding: EdgeInsets.fromLTRB(18, apertado ? 8 : 12, 10, 6),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: isDark ? 0.22 : 0.14),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child:
                          Icon(LucideIcons.handshake, size: 17, color: accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Preencher a partir de uma proposta',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          height: 1.15,
                          letterSpacing: -0.2,
                          color: text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Fechar',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(LucideIcons.x, size: 18, color: muted),
                    ),
                  ],
                ),
              ),
              // Um corpo rolável só: explicação, busca e lista juntas — com
              // o teclado aberto em paisagem nada fica espremido fora da tela.
              Flexible(
                child: CustomScrollView(
                  shrinkWrap: true,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Comprador, vendedor, imóvel e valor entram na '
                              'ficha. Ao criar, a ficha fica vinculada à '
                              'proposta.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.3,
                                fontWeight: FontWeight.w500,
                                color: muted,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _searchCtrl,
                              textInputAction: TextInputAction.search,
                              onChanged: _onBusca,
                              cursorColor: accent,
                              decoration: InputDecoration(
                                hintText:
                                    'Buscar por número, proponente ou imóvel…',
                                prefixIcon: Icon(
                                  LucideIcons.search,
                                  size: 18,
                                  color: accent,
                                ),
                                suffixIcon: _q.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'Limpar busca',
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () {
                                          _searchCtrl.clear();
                                          _onBusca('');
                                        },
                                        icon: Icon(
                                          LucideIcons.x,
                                          size: 16,
                                          color: muted,
                                        ),
                                      ),
                                isDense: true,
                                filled: true,
                                fillColor: isDark
                                    ? AppColors
                                        .background.backgroundTertiaryDarkMode
                                    : AppColors.background.backgroundTertiary,
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 13),
                                border: borda(hair),
                                enabledBorder: borda(hair),
                                focusedBorder: borda(accent, 1.6),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                      sliver: _corpo(context),
                    ),
                  ],
                ),
              ),
              // "Criar ficha sem proposta" = fechar. Some com o teclado aberto
              // (o "x" do topo faz o mesmo) para não roubar a altura da lista.
              if (!teclado)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    18,
                    0,
                    18,
                    6 + mq.padding.bottom,
                  ),
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: muted,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Criar ficha sem proposta',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Corpo como sliver: esqueleto, erro (causa + tentar de novo), vazio
  /// (sem candidatas × busca sem resultado) ou a lista.
  Widget _corpo(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    if (_loading) return const SliverToBoxAdapter(child: _SkeletonList());
    if (_erro != null) {
      return SliverToBoxAdapter(
        child: AppErrorState.fromApi(
          message: _erro,
          statusCode: _erroStatus,
          onRetry: _carregar,
          dense: true,
        ),
      );
    }
    final lista = _visiveis;
    if (lista.isEmpty) {
      if (_q.isNotEmpty && _buscando) {
        return const SliverToBoxAdapter(child: _SkeletonList(linhas: 2));
      }
      return SliverToBoxAdapter(
        child: _q.isEmpty
            ? const _Aviso(
                icon: LucideIcons.inbox,
                titulo: 'Nenhuma proposta disponível para vincular.',
                texto: 'Só entram propostas finalizadas. Propostas já '
                    'vinculadas a fichas de venda não aparecem aqui.',
              )
            : _Aviso(
                icon: LucideIcons.searchX,
                titulo: 'Nenhuma proposta encontrada.',
                texto: 'Nada casa com "$_q" entre as propostas finalizadas '
                    'sem ficha de venda.',
              ),
      );
    }
    return SliverList.separated(
      itemCount: lista.length + (_buscando ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        if (i >= lista.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: widget.accent),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Buscando mais propostas…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: muted),
                  ),
                ),
              ],
            ),
          );
        }
        final p = lista[i];
        return _ProposalTile(
          proposta: p,
          accent: widget.accent,
          selected: p.id == widget.selectedId,
          onTap: () => Navigator.of(context).pop(p),
        );
      },
    );
  }
}

class _ProposalTile extends StatelessWidget {
  const _ProposalTile({
    required this.proposta,
    required this.accent,
    required this.selected,
    required this.onTap,
  });
  final PurchaseProposal proposta;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = proposta;
    final text = ThemeHelpers.textColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final valor = propostaValorLabel(p);
    final data = propostaDataLabel(p);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: isDark ? 0.12 : 0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.55)
                  : ThemeHelpers.borderColor(context).withValues(alpha: 0.6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: isDark ? 0.2 : 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        propostaNumeroLabel(p),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                          color: accent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p.proponentName ?? 'Proponente não informado',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: text,
                      ),
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 6),
                    Icon(LucideIcons.check, size: 16, color: accent),
                  ],
                ],
              ),
              const SizedBox(height: 7),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(LucideIcons.house, size: 13, color: muted),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      propostaImovelLabel(p),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.3,
                        fontWeight: FontWeight.w500,
                        color: muted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(LucideIcons.calendar, size: 13, color: muted),
                  const SizedBox(width: 6),
                  Text(
                    data ?? 'Sem data',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: muted,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Valor nunca vira reticências: encolhe para caber.
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          valor ?? 'Sem valor',
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.2,
                            color: valor == null ? muted : text,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Esqueleto da lista enquanto carrega (mesma silhueta do cartão).
class _SkeletonList extends StatelessWidget {
  const _SkeletonList({this.linhas = 4});
  final int linhas;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < linhas; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Row(
                  children: [
                    SkeletonBox(width: 54, height: 16, borderRadius: 6),
                    SizedBox(width: 8),
                    Expanded(child: SkeletonText(height: 14)),
                    SizedBox(width: 40),
                  ],
                ),
                SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: SkeletonText(height: 11)),
                    SizedBox(width: 30),
                  ],
                ),
                SizedBox(height: 10),
                Row(
                  children: [
                    SkeletonBox(width: 70, height: 11, borderRadius: 6),
                    Spacer(),
                    SkeletonBox(width: 90, height: 14, borderRadius: 6),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Vazio / erro da folha: ícone, frase e (opcional) uma ação.
class _Aviso extends StatelessWidget {
  const _Aviso({
    required this.icon,
    required this.titulo,
    required this.texto,
  });
  final IconData icon;
  final String titulo;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 26, color: muted),
          const SizedBox(height: 10),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            texto,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w500,
              color: muted,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Entrada no formulário ──────────────────────────────────────────────────

/// Linha do topo de "Dados gerais" (só ao criar): o botão "Preencher a partir
/// de uma proposta" do web ou, já escolhida, a proposta de origem com
/// "Trocar" e remover o vínculo (os campos preenchidos ficam — como no web).
class SaleFormProposalPrefillBar extends StatelessWidget {
  const SaleFormProposalPrefillBar({
    super.key,
    required this.accent,
    required this.proposta,
    required this.carregando,
    required this.onEscolher,
    required this.onRemover,
  });
  final Color accent;
  final PurchaseProposal? proposta;
  final bool carregando;
  final VoidCallback onEscolher;
  final VoidCallback onRemover;

  @override
  Widget build(BuildContext context) {
    final text = ThemeHelpers.textColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = proposta;

    final Widget marca = Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.22 : 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: carregando
          ? Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: accent),
              ),
            )
          : Icon(p == null ? LucideIcons.handshake : LucideIcons.link2,
              size: 18, color: accent),
    );

    if (p == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: carregando ? null : onEscolher,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: accent.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  marca,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          carregando
                              ? 'Carregando proposta…'
                              : 'Preencher a partir de uma proposta',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: accent,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Traz comprador, vendedor, imóvel e valor de uma '
                          'proposta finalizada.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            fontWeight: FontWeight.w500,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(LucideIcons.chevronRight, size: 16, color: muted),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final valor = propostaValorLabel(p);
    final detalhe = [
      p.proponentName ?? 'Proponente não informado',
      if (valor != null) valor,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.55)),
        ),
        child: Row(
          children: [
            marca,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Proposta ${propostaNumeroLabel(p)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      color: text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detalhe,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: muted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Vinculada à ficha ao criar.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            TextButton(
              onPressed: carregando ? null : onEscolher,
              style: TextButton.styleFrom(
                foregroundColor: accent,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Trocar',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
            IconButton(
              tooltip: 'Remover vínculo com a proposta',
              visualDensity: VisualDensity.compact,
              onPressed: carregando ? null : onRemover,
              icon: Icon(LucideIcons.x, size: 16, color: muted),
            ),
          ],
        ),
      ),
    );
  }
}
