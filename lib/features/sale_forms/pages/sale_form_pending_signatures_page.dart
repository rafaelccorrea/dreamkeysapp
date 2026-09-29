import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/sale_forms_service.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';

/// Fichas › Assinaturas pendentes — paridade com
/// `SaleFormPendingSignaturesPage.tsx` (web, 25/09/2026).
///
/// Duas estações:
///  - **Esperando por mim**: o que espera a MINHA assinatura — "Assinar" abre
///    o link do Autentique fora do app (mesmo fluxo do web);
///  - **Todas que vejo**: cada ficha com assinatura em aberto, quem falta, há
///    quantos dias, se abriu o link e o último envio — com a cobrança ali
///    mesmo (e-mail, WhatsApp manual, copiar link).
///
/// "Todas" aparece só quando o back responde a ela (a hierarquia decide);
/// a primeira abertura começa em "minhas" quando há algo esperando por mim.
class SaleFormPendingSignaturesPage extends StatefulWidget {
  const SaleFormPendingSignaturesPage({super.key});

  @override
  State<SaleFormPendingSignaturesPage> createState() =>
      _SaleFormPendingSignaturesPageState();
}

class _SaleFormPendingSignaturesPageState
    extends State<SaleFormPendingSignaturesPage> {
  static const double _padH = 16;

  SaleFormPendingSignaturesResponse? _minhas;
  SaleFormPendingSignaturesResponse? _todas;
  bool _loading = true;
  String? _falha;
  int _falhaStatus = 0;

  /// 'minhas' | 'todas' — null até a primeira carga decidir.
  String? _escopo;
  final TextEditingController _busca = TextEditingController();
  bool _soParadas = false;

  /// Chaves em envio: `ficha:<id>` (lote da ficha) ou `sig:<id>`.
  final Set<String> _enviando = {};
  ({int feitas, int total})? _lote;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _accent =>
      _isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
  Color get _green =>
      _isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
  Color get _trava =>
      _isDark ? AppColors.status.errorDarkMode : AppColors.status.error;

  Future<void> _carregar() async {
    setState(() {
      _loading = true;
      _falha = null;
    });
    final fMinhas = SaleFormsService.instance
        .listarAssinaturasPendentes(escopo: 'minhas');
    final fTodas =
        SaleFormsService.instance.listarAssinaturasPendentes(escopo: 'todas');
    final rMinhas = await fMinhas;
    final rTodas = await fTodas;
    if (!mounted) return;
    setState(() {
      _minhas = rMinhas.success ? rMinhas.data : null;
      _todas = rTodas.success ? rTodas.data : null;
      if (_minhas == null && _todas == null) {
        final r = rTodas.success ? rMinhas : rTodas;
        _falha = r.message ??
            'Não foi possível carregar as assinaturas pendentes.';
        _falhaStatus = r.statusCode;
      }
      _escopo ??= ((_minhas?.resumoMinhas ?? 0) > 0 || _todas == null)
          ? 'minhas'
          : 'todas';
      if (_escopo == 'todas' && _todas == null) _escopo = 'minhas';
      _loading = false;
    });
  }

  // ─── Regras (espelho de regrasDasAssinaturas.ts) ─────────────────────────

  String get _ativo => _escopo ?? 'minhas';
  SaleFormPendingSignaturesResponse? get _atual =>
      _ativo == 'todas' ? _todas : _minhas;
  int get _diasParaTravar => _atual?.diasParaTravar ?? 3;

  /// 'trava' | 'atencao' | null
  String? _urgencia(int dias) {
    final trava = _diasParaTravar < 1 ? 1 : _diasParaTravar;
    if (dias >= trava) return 'trava';
    final limiar = trava - 1 < 2 ? trava - 1 : 2;
    if (dias >= limiar && dias > 0) return 'atencao';
    return null;
  }

  String _textoDias(int dias) {
    if (dias <= 0) return 'hoje';
    return dias == 1 ? '1 dia' : '$dias dias';
  }

  bool _parada(SaleFormWithPendingSignatures f) =>
      f.pendentes.any((p) => _urgencia(p.diasPendente) == 'trava');

  List<SaleFormPendingSignature> _comEmail(SaleFormWithPendingSignatures f) =>
      f.pendentes
          .where((p) =>
              (p.signerEmail?.trim().isNotEmpty ?? false) &&
              (p.signatureUrl?.trim().isNotEmpty ?? false))
          .toList();

  String _normalizar(String? v) {
    const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const para = 'aaaaaeeeeiiiiooooouuuucn';
    final s = (v ?? '').toLowerCase().trim();
    final b = StringBuffer();
    for (final ch in s.split('')) {
      final i = de.indexOf(ch);
      b.write(i >= 0 ? para[i] : ch);
    }
    return b.toString();
  }

  bool _casaBusca(SaleFormWithPendingSignatures f) {
    final t = _normalizar(_busca.text);
    if (t.isEmpty) return true;
    final campos = <String?>[
      f.formNumber,
      f.buyerName,
      f.sellerName,
      f.criadorName,
      for (final p in f.pendentes) ...[p.signerName, p.signerEmail],
    ];
    return campos.any((c) => _normalizar(c).contains(t));
  }

  List<SaleFormWithPendingSignatures> get _fichas => (_atual?.fichas ?? const [])
      .where((f) => _casaBusca(f) && (!_soParadas || _parada(f)))
      .toList();

  /// Meus pendentes com link, do mais antigo ao mais novo.
  List<({SaleFormWithPendingSignatures ficha, SaleFormPendingSignature a})>
      get _meusComLink {
    final out =
        <({SaleFormWithPendingSignatures ficha, SaleFormPendingSignature a})>[];
    for (final f in _minhas?.fichas ?? const <SaleFormWithPendingSignatures>[]) {
      for (final p in f.pendentes) {
        if (p.ehVoce && p.linkAbrivel != null) out.add((ficha: f, a: p));
      }
    }
    out.sort((x, y) => y.a.diasPendente.compareTo(x.a.diasPendente));
    return out;
  }

  // ─── Ações ───────────────────────────────────────────────────────────────

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _assinar(SaleFormPendingSignature a) async {
    final link = a.linkAbrivel;
    if (link == null) {
      _snack('Link ainda não gerado: abra a ficha.');
      return;
    }
    final ok = await launchUrl(
      Uri.parse(link),
      mode: LaunchMode.externalApplication,
    );
    if (!ok) _snack('Não foi possível abrir o link de assinatura.');
  }

  Future<void> _cobrarFicha(SaleFormWithPendingSignatures f) async {
    final chave = 'ficha:${f.saleFormId}';
    if (_enviando.contains(chave)) return;
    setState(() => _enviando.add(chave));
    final r = await SaleFormsService.instance.reenviarTodosEmail(f.saleFormId);
    if (!mounted) return;
    setState(() => _enviando.remove(chave));
    if (r.success && r.data != null) {
      final d = r.data!;
      if (d.sent > 0) {
        _snack('${f.formNumber}: ${d.sent} e-mail(s) enviado(s)'
            '${d.skippedNoEmail > 0 ? ' · ${d.skippedNoEmail} sem e-mail' : ''}.');
      } else {
        _snack(d.motivo ?? '${f.formNumber}: nenhum e-mail enviado.');
      }
      _carregar();
    } else {
      _snack(r.message ?? 'Erro ao enviar por e-mail.');
    }
  }

  Future<void> _cobrarSignatario(
    SaleFormWithPendingSignatures f,
    SaleFormPendingSignature a,
  ) async {
    final chave = 'sig:${a.signatureId}';
    if (_enviando.contains(chave)) return;
    setState(() => _enviando.add(chave));
    final r = await SaleFormsService.instance
        .reenviarUmEmail(f.saleFormId, a.signatureId);
    if (!mounted) return;
    setState(() => _enviando.remove(chave));
    if (r.success && r.data != null) {
      _snack(r.data!.sent > 0
          ? 'Link enviado para ${a.signerEmail}.'
          : (r.data!.motivo ?? 'O e-mail não foi enviado.'));
      _carregar();
    } else {
      _snack(r.message ?? 'Erro ao enviar por e-mail.');
    }
  }

  /// Cobrança em lote, ficha a ficha (o back ignora quem recebeu há < 5 min).
  Future<void> _cobrarTodas() async {
    final alvo = _fichas.where((f) => _comEmail(f).isNotEmpty).toList();
    if (_lote != null || alvo.isEmpty) return;
    var enviados = 0;
    var recusadas = 0;
    setState(() => _lote = (feitas: 0, total: alvo.length));
    for (var i = 0; i < alvo.length; i++) {
      final r =
          await SaleFormsService.instance.reenviarTodosEmail(alvo[i].saleFormId);
      if (r.success && r.data != null) {
        enviados += r.data!.sent;
      } else {
        recusadas++;
      }
      if (!mounted) return;
      setState(() => _lote = (feitas: i + 1, total: alvo.length));
    }
    if (!mounted) return;
    setState(() => _lote = null);
    _snack(enviados > 0
        ? '$enviados e-mail(s) enviado(s) em ${alvo.length - recusadas} '
            'ficha(s)${recusadas > 0 ? ' · $recusadas já tinham sido cobradas há pouco' : ''}.'
        : 'Nenhum e-mail enviado. As fichas podem ter sido cobradas há poucos minutos.');
    _carregar();
  }

  Future<void> _copiar(SaleFormPendingSignature a) async {
    final link = a.linkAbrivel;
    if (link == null) return;
    await Clipboard.setData(ClipboardData(text: link));
    _snack('Link copiado. Envie só ao signatário correspondente.');
  }

  Future<void> _whatsApp(
    SaleFormWithPendingSignatures f,
    SaleFormPendingSignature a,
  ) async {
    final link = a.linkAbrivel;
    if (link == null) return;
    final nome = a.signerName?.trim().split(RegExp(r'\s+')).first ?? '';
    final msg = 'Olá${nome.isNotEmpty ? ', $nome' : ''}! Segue o link para '
        'assinar a ficha de venda ${f.formNumber}:\n\n$link';
    await launchUrl(
      Uri.parse('https://wa.me/?text=${Uri.encodeComponent(msg)}'),
      mode: LaunchMode.externalApplication,
    );
  }

  void _abrirFicha(SaleFormWithPendingSignatures f) {
    Navigator.of(context).pushNamed(AppRoutes.saleFormDetails(f.saleFormId));
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Assinaturas pendentes',
      showBottomNavigation: false,
      actions: [
        IconButton(
          tooltip: 'Atualizar',
          onPressed: _loading ? null : _carregar,
          icon: const Icon(LucideIcons.refreshCw, size: 18),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: _carregar,
        color: _accent,
        child: _loading && _atual == null
            ? _buildSkeleton()
            : (_falha != null && _atual == null)
                ? _buildFalha()
                : _buildConteudo(),
      ),
    );
  }

  Widget _buildSkeleton() {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(_padH, 18, _padH, 40),
      children: [
        const SkeletonBox(height: 12, width: 150, borderRadius: 6),
        const SizedBox(height: 10),
        const SkeletonBox(height: 26, width: 230, borderRadius: 8),
        const SizedBox(height: 12),
        const SkeletonBox(height: 16, borderRadius: 6),
        const SizedBox(height: 18),
        const SkeletonBox(height: 52, borderRadius: 14),
        const SizedBox(height: 18),
        const SkeletonBox(height: 40, borderRadius: 12),
        const SizedBox(height: 22),
        for (var i = 0; i < 3; i++) ...[
          const SkeletonBox(height: 18, width: 180, borderRadius: 6),
          const SizedBox(height: 10),
          const SkeletonBox(height: 50, borderRadius: 10),
          const SizedBox(height: 8),
          const SkeletonBox(height: 50, borderRadius: 10),
          const SizedBox(height: 24),
        ],
      ],
    );
  }

  Widget _buildFalha() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(_padH, 56, _padH, 40),
      children: [
        AppErrorState.fromApi(
          message: _falha,
          statusCode: _falhaStatus,
          onRetry: _carregar,
          dense: true,
        ),
      ],
    );
  }

  Widget _buildConteudo() {
    final fichas = _fichas;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(_padH, 18, _padH, 40),
      children: [
        _buildHero(),
        const SizedBox(height: 16),
        _buildAcaoPrincipal(),
        const SizedBox(height: 18),
        if (_todas != null) ...[
          _buildEstacoes(),
          const SizedBox(height: 14),
        ],
        _buildBarra(fichas.length),
        const SizedBox(height: 16),
        _SecaoLabel(
          _ativo == 'minhas'
              ? 'ESPERANDO A SUA ASSINATURA'
              : 'COM ASSINATURA EM ABERTO',
          accent: _accent,
        ),
        const SizedBox(height: 4),
        Text(
          _ativo == 'minhas'
              ? 'Assine direto no Autentique; os outros pendentes da ficha '
                  'aparecem junto.'
              : 'A mais parada primeiro. Toque no número para abrir a ficha.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
                height: 1.35,
              ),
        ),
        const SizedBox(height: 6),
        if (fichas.isEmpty)
          _buildVazio()
        else
          for (final f in fichas) _buildFicha(f),
      ],
    );
  }

  Widget _buildHero() {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final t = Theme.of(context).textTheme;
    final r = _todas;
    final leituras = <(String, String, Color?)>[
      ('${_minhas?.resumoMinhas ?? 0}', 'esperando por você', null),
      if (r != null) ...[
        (
          '${r.resumoFichas}',
          r.resumoFichas == 1 ? 'ficha aberta' : 'fichas abertas',
          null,
        ),
        (
          '${r.resumoAssinaturas}',
          r.resumoAssinaturas == 1
              ? 'assinatura em falta'
              : 'assinaturas em falta',
          null,
        ),
        (
          '${r.resumoParadas}',
          'no prazo da trava',
          r.resumoParadas > 0 ? _trava : null,
        ),
        if (r.resumoSemEmail > 0) ('${r.resumoSemEmail}', 'sem e-mail', null),
      ],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'FICHAS · ASSINATURAS',
          style: t.labelSmall?.copyWith(
            color: _accent,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Assinaturas pendentes',
          style: t.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            for (final l in leituras)
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: l.$1,
                      style: t.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: l.$3 ?? ThemeHelpers.textColor(context),
                      ),
                    ),
                    TextSpan(
                      text: ' ${l.$2}',
                      style: t.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Quem falta assinar em cada ficha, há quanto tempo e se já abriu o '
          'link. O link sai por e-mail assim que a ficha vai para assinatura; '
          'daqui dá para cobrar de novo por e-mail, WhatsApp ou copiando o link.',
          style: t.bodySmall?.copyWith(color: muted, height: 1.4),
        ),
      ],
    );
  }

  Widget _buildAcaoPrincipal() {
    final t = Theme.of(context).textTheme;
    if (_ativo == 'minhas') {
      final meus = _meusComLink;
      final prox = meus.isEmpty ? null : meus.first;
      return _BotaoRico(
        icon: LucideIcons.penLine,
        title: 'Assinar a próxima',
        subtitle: prox == null
            ? 'nada esperando por você'
            : '${meus.length} esperando por você · ${prox.ficha.formNumber}',
        color: _green,
        filled: true,
        onTap: _loading || prox == null ? null : () => _assinar(prox.a),
        textTheme: t,
      );
    }
    final cobraveis = _fichas.where((f) => _comEmail(f).isNotEmpty).toList();
    final pessoas =
        cobraveis.fold<int>(0, (n, f) => n + _comEmail(f).length);
    final recorte = _soParadas || _busca.text.trim().isNotEmpty;
    return _BotaoRico(
      icon: LucideIcons.mailPlus,
      title: _lote != null
          ? 'Cobrando ${_lote!.feitas} de ${_lote!.total}…'
          : 'Cobrar por e-mail',
      subtitle: cobraveis.isEmpty
          ? 'ninguém com e-mail para cobrar'
          : '${cobraveis.length} ${cobraveis.length == 1 ? 'ficha' : 'fichas'}'
              ' · $pessoas ${pessoas == 1 ? 'pessoa' : 'pessoas'}'
              '${recorte ? ' do recorte' : ''}',
      color: _accent,
      filled: false,
      onTap: _loading || _lote != null || cobraveis.isEmpty
          ? null
          : _cobrarTodas,
      textTheme: t,
    );
  }

  Widget _buildEstacoes() {
    final muted = ThemeHelpers.textSecondaryColor(context);
    Widget estacao(String chave, String nome, int? n) {
      final on = _ativo == chave;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _escopo = chave),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: on
                      ? _accent
                      : ThemeHelpers.borderLightColor(context),
                  width: on ? 2 : 1,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    nome,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: on ? FontWeight.w900 : FontWeight.w600,
                          color: on ? ThemeHelpers.textColor(context) : muted,
                        ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                    color: (on ? _accent : muted).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    n == null ? '—' : '$n',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: on ? _accent : muted,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        estacao('minhas', 'Esperando por mim', _minhas?.resumoFichas),
        estacao('todas', 'Todas que vejo', _todas?.resumoFichas),
      ],
    );
  }

  Widget _buildBarra(int quantas) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final paradas =
        (_atual?.fichas ?? const <SaleFormWithPendingSignatures>[])
            .where(_parada)
            .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _busca,
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Ficha, comprador ou signatário',
            prefixIcon: const Icon(LucideIcons.search, size: 18),
            suffixIcon: _busca.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpar',
                    icon: const Icon(LucideIcons.x, size: 16),
                    onPressed: () => setState(_busca.clear),
                  ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Flexible(
              child: FilterChip(
                selected: _soParadas,
                onSelected: (v) => setState(() => _soParadas = v),
                showCheckmark: false,
                avatar: Icon(
                  LucideIcons.hourglass,
                  size: 15,
                  color: _soParadas ? _trava : muted,
                ),
                label: Text(
                  'No prazo da trava · $paradas',
                  overflow: TextOverflow.ellipsis,
                ),
                selectedColor: _trava.withValues(alpha: 0.14),
                side: BorderSide(
                  color: _soParadas
                      ? _trava.withValues(alpha: 0.5)
                      : ThemeHelpers.borderLightColor(context),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '$quantas ${quantas == 1 ? 'ficha' : 'fichas'}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVazio() {
    final (titulo, texto) = (_busca.text.trim().isNotEmpty || _soParadas)
        ? (
            'Nenhuma ficha neste recorte.',
            'Limpe a busca ou desligue "No prazo da trava" para ver todas.',
          )
        : _ativo == 'minhas'
            ? (
                'Nada esperando pela sua assinatura.',
                'Quando uma ficha precisar de você, ela aparece aqui e o link '
                    'chega no seu e-mail.',
              )
            : (
                'Todas as fichas estão assinadas.',
                'Uma ficha entra aqui quando é enviada para assinatura e sai '
                    'quando o último signatário assina.',
              );
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 8),
      child: Column(
        children: [
          Icon(LucideIcons.circleCheck,
              size: 30, color: _green.withValues(alpha: 0.8)),
          const SizedBox(height: 12),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            texto,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: muted,
                  height: 1.4,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildFicha(SaleFormWithPendingSignatures f) {
    final t = Theme.of(context).textTheme;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final hair = ThemeHelpers.borderLightColor(context);
    final partes = [f.buyerName, f.sellerName]
        .map((v) => v?.trim() ?? '')
        .where((v) => v.isNotEmpty)
        .join(' × ');
    final pct = f.total > 0 ? (f.assinadas / f.total).clamp(0.0, 1.0) : 0.0;
    final cobraveis = _comEmail(f).length;
    final cobrando = _enviando.contains('ficha:${f.saleFormId}');
    final df = DateFormat('dd/MM', 'pt_BR');
    String curta(DateTime? d) => d == null ? '—' : df.format(d.toLocal());

    return Container(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: hair)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () => _abrirFicha(f),
                      borderRadius: BorderRadius.circular(6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              f.formNumber.isEmpty ? 'Ficha' : f.formNumber,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.titleSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: _accent,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(LucideIcons.externalLink,
                              size: 13, color: _accent),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      partes.isEmpty ? 'Sem comprador informado' : partes,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Enviada em ${curta(f.enviadaEm)}'
                      '${f.criadorName != null ? ' · ${f.criadorName}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.labelSmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 4,
                    color: _green,
                    backgroundColor: hair,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${f.assinadas}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: f.assinadas > 0 ? _green : null,
                      ),
                    ),
                    TextSpan(text: ' de ${f.total} assinadas'),
                  ],
                ),
                style: t.labelSmall?.copyWith(color: muted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'E-mail ${curta(f.ultimoEmailEm)} · '
                  'WhatsApp ${curta(f.ultimoWhatsAppEm)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelSmall?.copyWith(color: muted),
                ),
              ),
              TextButton.icon(
                onPressed:
                    cobrando || cobraveis == 0 ? null : () => _cobrarFicha(f),
                icon: cobrando
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.mailPlus, size: 16),
                label: Text(cobrando ? 'Enviando…' : 'Cobrar por e-mail'),
                style: TextButton.styleFrom(
                  foregroundColor: _accent,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          for (final a in f.pendentes) _buildPendente(f, a),
        ],
      ),
    );
  }

  Widget _buildPendente(
    SaleFormWithPendingSignatures f,
    SaleFormPendingSignature a,
  ) {
    final t = Theme.of(context).textTheme;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final urg = _urgencia(a.diasPendente);
    final corDias = urg == 'trava'
        ? _trava
        : urg == 'atencao'
            ? (_isDark
                ? AppColors.status.warningDarkMode
                : AppColors.status.warning)
            : muted;
    final azul = _isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;
    final temLink = a.linkAbrivel != null;
    final temEmail = a.signerEmail?.trim().isNotEmpty ?? false;
    final cobrando = _enviando.contains('sig:${a.signatureId}');
    final df = DateFormat('dd/MM', 'pt_BR');

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: ThemeHelpers.borderLightColor(context)),
          left: BorderSide(
            color: a.ehVoce ? _accent : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        a.nomeExibido,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (a.ehVoce) ...[
                      const SizedBox(width: 6),
                      _VoceBadge(color: _accent),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                a.diasPendente <= 0
                    ? 'desde hoje'
                    : 'há ${_textoDias(a.diasPendente)}',
                style: t.labelSmall?.copyWith(
                  color: corDias,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            temEmail ? a.signerEmail!.trim() : 'sem e-mail cadastrado',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 2),
          Text(
            [
              a.abriu
                  ? 'Abriu o link${a.viewedAt != null ? ' em ${df.format(a.viewedAt!.toLocal())}' : ''}'
                  : 'Ainda não abriu',
              if (a.lembretesWhatsApp > 0)
                '${a.lembretesWhatsApp} '
                    '${a.lembretesWhatsApp == 1 ? 'lembrete' : 'lembretes'} no WhatsApp',
            ].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.labelSmall?.copyWith(
              color: a.abriu ? azul : muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          if (a.ehVoce)
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: temLink ? () => _assinar(a) : null,
                icon: const Icon(LucideIcons.penLine, size: 16),
                label: Text(temLink ? 'Assinar' : 'Link ainda não gerado'),
                style: FilledButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            )
          else
            Row(
              children: [
                IconButton(
                  tooltip: temEmail
                      ? 'Enviar o link por e-mail'
                      : 'Sem e-mail cadastrado',
                  visualDensity: VisualDensity.compact,
                  onPressed: !temLink || !temEmail || cobrando
                      ? null
                      : () => _cobrarSignatario(f, a),
                  icon: cobrando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(LucideIcons.mailPlus, size: 18),
                ),
                IconButton(
                  tooltip: 'Abrir o WhatsApp com a mensagem e o link',
                  visualDensity: VisualDensity.compact,
                  onPressed: temLink ? () => _whatsApp(f, a) : null,
                  icon: const Icon(LucideIcons.messageCircle, size: 18),
                ),
                IconButton(
                  tooltip: 'Copiar o link',
                  visualDensity: VisualDensity.compact,
                  onPressed: temLink ? () => _copiar(a) : null,
                  icon: const Icon(LucideIcons.copy, size: 17),
                ),
                if (!temLink)
                  Flexible(
                    child: Text(
                      'link ainda não gerado',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.labelSmall?.copyWith(color: muted),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

// ─── Peças ──────────────────────────────────────────────────────────────────

class _SecaoLabel extends StatelessWidget {
  const _SecaoLabel(this.text, {required this.accent});
  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 15,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.3,
                  color: ThemeHelpers.textColor(context),
                  fontSize: 11,
                ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            color: ThemeHelpers.borderLightColor(context),
          ),
        ),
      ],
    );
  }
}

class _VoceBadge extends StatelessWidget {
  const _VoceBadge({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        'VOCÊ',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
              fontSize: 9.5,
            ),
      ),
    );
  }
}

/// Ação principal da tela (paridade com o "botão rico" do web): título +
/// linha de apoio, largura inteira.
class _BotaoRico extends StatelessWidget {
  const _BotaoRico({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.filled,
    required this.onTap,
    required this.textTheme,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool filled;
  final VoidCallback? onTap;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = filled ? Colors.white : color;
    final base = filled ? color : Colors.transparent;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: base,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: filled
                  ? null
                  : Border.all(color: color.withValues(alpha: 0.55)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: fg),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall?.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(
                          color: fg.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
