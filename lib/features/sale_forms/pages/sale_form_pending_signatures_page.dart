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
import '../widgets/sale_form_tones.dart';

/// Fichas › Assinaturas pendentes — paridade com
/// `SaleFormPendingSignaturesPage.tsx` (web, 25/09/2026).
///
/// Duas estações:
///  - **Esperando por mim**: o que espera a MINHA assinatura — o painel "sua
///    vez" responde de cara quantas são e tem o botão para assinar a mais
///    antiga; "Assinar" abre o link do Autentique fora do app (mesmo fluxo
///    do web);
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
  SaleFormTom get _ok => SaleFormTom.sucesso(context);
  SaleFormTom get _trava => SaleFormTom.erro(context);
  SaleFormTom get _atencao => SaleFormTom.aviso(context);
  SaleFormTom get _info => SaleFormTom.info(context);

  /// Margem lateral: 16 no celular; em tela larga o conteúdo fica numa
  /// coluna de até 720 centralizada.
  double _margem(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w > 752 ? (w - 720) / 2 : 16;
  }

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

  /// "desde hoje" / "há 3 dias".
  String _haQuanto(int dias) =>
      dias <= 0 ? 'desde hoje' : 'há ${_textoDias(dias)}';

  /// Tom da urgência (âmbar perto da trava, vermelho na trava); null = no
  /// prazo.
  SaleFormTom? _tomUrgencia(int dias) {
    final u = _urgencia(dias);
    if (u == 'trava') return _trava;
    if (u == 'atencao') return _atencao;
    return null;
  }

  /// Rótulo do recorte "paradas" — o mesmo limite da trava, em dias.
  String get _rotuloParadas {
    final dias = _diasParaTravar < 1 ? 1 : _diasParaTravar;
    return 'Paradas há $dias+ ${dias == 1 ? 'dia' : 'dias'}';
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

  /// Esqueleto fiel à tela: estações, painel "sua vez", busca e fichas com
  /// barra de progresso e linha de signatário.
  Widget _buildSkeleton() {
    final m = _margem(context);
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(m, 8, m, 40),
      children: [
        Row(
          children: const [
            Expanded(child: SkeletonBox(height: 38, borderRadius: 8)),
            SizedBox(width: 12),
            Expanded(child: SkeletonBox(height: 38, borderRadius: 8)),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: const [
            SkeletonBox(width: 44, height: 44, borderRadius: 13),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 170, height: 22, borderRadius: 6),
                  SizedBox(height: 8),
                  SkeletonBox(width: 120, height: 12, borderRadius: 6),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const SkeletonBox(height: 12, width: 240, borderRadius: 6),
        const SizedBox(height: 12),
        const SkeletonBox(height: 52, borderRadius: 14),
        const SizedBox(height: 22),
        const SkeletonBox(height: 46, borderRadius: 12),
        const SizedBox(height: 10),
        Row(
          children: const [
            SkeletonBox(width: 180, height: 32, borderRadius: 10),
            Spacer(),
            SkeletonBox(width: 56, height: 12, borderRadius: 6),
          ],
        ),
        const SizedBox(height: 24),
        for (var i = 0; i < 3; i++) ...[
          Row(
            children: const [
              SkeletonBox(width: 110, height: 16, borderRadius: 6),
              Spacer(),
              SkeletonBox(width: 64, height: 16, borderRadius: 999),
            ],
          ),
          const SizedBox(height: 8),
          const SkeletonBox(height: 14, width: 220, borderRadius: 6),
          const SizedBox(height: 12),
          const SkeletonBox(height: 5, borderRadius: 3),
          const SizedBox(height: 12),
          const SkeletonBox(height: 66, borderRadius: 12),
          const SizedBox(height: 26),
        ],
      ],
    );
  }

  Widget _buildFalha() {
    final m = _margem(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(m, 56, m, 40),
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
    final m = _margem(context);
    final minhas = _ativo == 'minhas';
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(m, _todas != null ? 6 : 18, m, 40),
      children: [
        if (_todas != null) ...[
          _buildEstacoes(),
          const SizedBox(height: 18),
        ],
        minhas ? _buildSuaVez() : _buildPainelTodas(),
        const SizedBox(height: 22),
        _buildBarra(fichas.length),
        const SizedBox(height: 18),
        _SecaoLabel(
          minhas ? 'FICHAS COM A SUA ASSINATURA' : 'COM ASSINATURA EM ABERTO',
          accent: _accent,
        ),
        const SizedBox(height: 4),
        Text(
          minhas
              ? 'Assine direto no Autentique; os outros pendentes da ficha '
                  'aparecem junto.'
              : 'A mais parada primeiro. Toque no número para abrir a ficha.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
                height: 1.35,
              ),
        ),
        const SizedBox(height: 4),
        if (fichas.isEmpty)
          _buildVazio()
        else
          for (final f in fichas) _buildFicha(f),
      ],
    );
  }

  /// "Sua vez": quantas assinaturas esperam por você e o botão para assinar
  /// a mais antiga agora — a pergunta de quem abre esta tela.
  Widget _buildSuaVez() {
    final t = Theme.of(context).textTheme;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final text = ThemeHelpers.textColor(context);
    final ok = _ok;
    final meus = _meusComLink;
    final prox = meus.isEmpty ? null : meus.first;

    // A estação "minhas" não respondeu (só "todas" veio): não dá para dizer
    // que não há nada — diz o que houve e como tentar de novo.
    if (_minhas == null) {
      return _PainelEstado(
        icon: LucideIcons.circleAlert,
        tom: _atencao,
        titulo: 'Não deu para carregar as suas assinaturas',
        texto: 'Puxe a tela para baixo para tentar de novo.',
      );
    }

    if (prox == null) {
      final esperando = _minhas?.resumoMinhas ?? 0;
      if (esperando > 0) {
        return _PainelEstado(
          icon: LucideIcons.hourglass,
          tom: _atencao,
          titulo: esperando == 1
              ? '1 assinatura espera por você'
              : '$esperando assinaturas esperam por você',
          texto: 'O link ainda não foi gerado. Abra a ficha abaixo para '
              'acompanhar.',
        );
      }
      return _PainelEstado(
        icon: LucideIcons.circleCheck,
        tom: ok,
        titulo: 'Nada esperando pela sua assinatura',
        texto: 'Quando uma ficha precisar de você, ela aparece aqui e o link '
            'chega no seu e-mail.',
      );
    }

    final f = prox.ficha;
    final a = prox.a;
    final n = meus.length;
    final tomDias = _tomUrgencia(a.diasPendente);
    final partes = [f.buyerName, f.sellerName]
        .map((v) => v?.trim() ?? '')
        .where((v) => v.isNotEmpty)
        .join(' × ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: ok.sinal.withValues(alpha: _isDark ? 0.18 : 0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(LucideIcons.penLine, size: 20, color: ok.texto),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$n',
                      style: t.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: text,
                        height: 1.0,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    TextSpan(
                      text: n == 1
                          ? '  assinatura esperando por você'
                          : '  assinaturas esperando por você',
                      style: t.bodyMedium?.copyWith(
                        color: muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'A mais antiga: '),
              TextSpan(
                text: f.formNumber.isEmpty
                    ? 'ficha sem número'
                    : 'ficha ${f.formNumber}',
                style: TextStyle(fontWeight: FontWeight.w800, color: text),
              ),
              if (partes.isNotEmpty) TextSpan(text: ' · $partes'),
              TextSpan(
                text: ' · ${_haQuanto(a.diasPendente)}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: tomDias?.texto ?? muted,
                ),
              ),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: t.bodySmall?.copyWith(color: muted, height: 1.35),
        ),
        const SizedBox(height: 12),
        _BotaoAssinar(
          label: n == 1 ? 'Assinar agora' : 'Assinar a mais antiga agora',
          grande: true,
          onTap: _loading ? null : () => _assinar(a),
        ),
        const SizedBox(height: 8),
        Text(
          'Abre o Autentique fora do app. Depois de assinar, puxe a tela para '
          'atualizar.',
          style: t.labelSmall?.copyWith(color: muted, height: 1.35),
        ),
      ],
    );
  }

  /// Estação "Todas que vejo": o tamanho da fila (leituras) e a cobrança em
  /// lote por e-mail.
  Widget _buildPainelTodas() {
    final t = Theme.of(context).textTheme;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final r = _todas;
    if (r == null) return const SizedBox.shrink();
    final leituras = <(String, String, Color?)>[
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
        _rotuloParadas.toLowerCase(),
        r.resumoParadas > 0 ? _trava.texto : null,
      ),
      if (r.resumoSemEmail > 0)
        ('${r.resumoSemEmail}', 'sem e-mail', _atencao.texto),
    ];
    final cobraveis = _fichas.where((f) => _comEmail(f).isNotEmpty).toList();
    final pessoas =
        cobraveis.fold<int>(0, (n, f) => n + _comEmail(f).length);
    final recorte = _soParadas || _busca.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            for (final l in leituras)
              _Leitura(valor: l.$1, rotulo: l.$2, cor: l.$3),
          ],
        ),
        const SizedBox(height: 14),
        _BotaoRico(
          icon: LucideIcons.mailPlus,
          title: _lote != null
              ? 'Cobrando ${_lote!.feitas} de ${_lote!.total}…'
              : 'Cobrar todas por e-mail',
          subtitle: cobraveis.isEmpty
              ? 'Ninguém com e-mail para cobrar'
              : '${cobraveis.length} '
                  '${cobraveis.length == 1 ? 'ficha' : 'fichas'}'
                  ' · $pessoas ${pessoas == 1 ? 'pessoa' : 'pessoas'}'
                  '${recorte ? ' do recorte' : ''}',
          color: _info.texto,
          filled: false,
          onTap: _loading || _lote != null || cobraveis.isEmpty
              ? null
              : _cobrarTodas,
          textTheme: t,
        ),
        const SizedBox(height: 8),
        Text(
          'O link sai por e-mail quando a ficha vai para assinatura. Daqui '
          'você cobra de novo por e-mail, WhatsApp ou copiando o link.',
          style: t.labelSmall?.copyWith(color: muted, height: 1.35),
        ),
      ],
    );
  }

  Widget _buildEstacoes() {
    final muted = ThemeHelpers.textSecondaryColor(context);
    Widget estacao(String chave, String nome, int? n) {
      final on = _ativo == chave;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          child: InkWell(
            onTap: () => setState(() => _escopo = chave),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.fromLTRB(6, 11, 6, 11),
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
              // Nome + contagem nunca cortam: em 320dp encolhem juntos.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      nome,
                      maxLines: 1,
                      softWrap: false,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: on ? FontWeight.w900 : FontWeight.w600,
                            color: on ? ThemeHelpers.textColor(context) : muted,
                          ),
                    ),
                    // Sem resposta dessa estação: sem número (não é zero).
                    if (n != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color:
                              (on ? _accent : muted).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$n',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: on ? _accent : muted,
                                  ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
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
    final hair = ThemeHelpers.borderLightColor(context);
    final fill = _isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    final paradas =
        (_atual?.fichas ?? const <SaleFormWithPendingSignatures>[])
            .where(_parada)
            .length;
    OutlineInputBorder borda(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c, width: w),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _busca,
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.search,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Ficha, comprador ou signatário',
            prefixIcon: Icon(LucideIcons.search, size: 18, color: _accent),
            suffixIcon: _busca.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpar',
                    icon: Icon(LucideIcons.x, size: 16, color: muted),
                    onPressed: () => setState(_busca.clear),
                  ),
            filled: true,
            fillColor: fill,
            contentPadding: const EdgeInsets.symmetric(vertical: 13),
            border: borda(hair),
            enabledBorder: borda(hair),
            focusedBorder: borda(_accent.withValues(alpha: 0.65), 1.4),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: _ChipParadas(
                  ativo: _soParadas,
                  rotulo: _rotuloParadas,
                  quantas: paradas,
                  tom: _trava,
                  onTap: () => setState(() => _soParadas = !_soParadas),
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
            'Limpe a busca ou desligue "$_rotuloParadas" para ver todas.',
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
    final ok = _ok;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 8),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: ok.sinal.withValues(alpha: _isDark ? 0.16 : 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(LucideIcons.circleCheck, size: 24, color: ok.texto),
          ),
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
    final ok = _ok;
    final partes = [f.buyerName, f.sellerName]
        .map((v) => v?.trim() ?? '')
        .where((v) => v.isNotEmpty)
        .join(' × ');
    final pct = f.total > 0 ? (f.assinadas / f.total).clamp(0.0, 1.0) : 0.0;
    final cobraveis = _comEmail(f).length;
    final cobrando = _enviando.contains('ficha:${f.saleFormId}');
    final df = DateFormat('dd/MM', 'pt_BR');
    final criador = f.criadorName?.trim() ?? '';
    final origem = <String>[
      if (f.enviadaEm != null)
        'Enviada em ${df.format(f.enviadaEm!.toLocal())}',
      if (criador.isNotEmpty) 'criada por $criador',
    ];
    // Só os envios que existem — "—" não informa nada.
    final envios = <String>[
      if (f.ultimoEmailEm != null)
        'E-mail em ${df.format(f.ultimoEmailEm!.toLocal())}',
      if (f.ultimoWhatsAppEm != null)
        'WhatsApp em ${df.format(f.ultimoWhatsAppEm!.toLocal())}',
    ];
    // "Você" primeiro: o que é seu para assinar fica no topo da ficha.
    final pendentes = <SaleFormPendingSignature>[
      ...f.pendentes.where((p) => p.ehVoce),
      ...f.pendentes.where((p) => !p.ehVoce),
    ];

    return Container(
      padding: const EdgeInsets.only(top: 18, bottom: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: hair)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    onTap: () => _abrirFicha(f),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              f.formNumber.isEmpty
                                  ? 'Ficha sem número'
                                  : 'Ficha ${f.formNumber}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.titleSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: _accent,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            LucideIcons.externalLink,
                            size: 13,
                            color: _accent,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _Dias(
                texto: _haQuanto(f.diasPendente),
                tom: _tomUrgencia(f.diasPendente),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            partes.isEmpty ? 'Sem comprador informado' : partes,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (origem.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              origem.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.labelSmall?.copyWith(color: muted),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 5,
                    color: ok.sinal,
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
                        color: f.assinadas > 0 ? ok.texto : null,
                      ),
                    ),
                    TextSpan(text: ' de ${f.total} assinaram'),
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
                  envios.isEmpty
                      ? 'Nenhum envio registrado'
                      : envios.join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelSmall?.copyWith(color: muted, height: 1.3),
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 176),
                child: _AcaoPequena(
                  icon: LucideIcons.mailPlus,
                  label: cobrando ? 'Enviando…' : 'Cobrar por e-mail',
                  cor: _info.texto,
                  busy: cobrando,
                  tooltip: cobraveis == 0
                      ? 'Ninguém com e-mail e link nesta ficha'
                      : 'Reenviar o link a todos os pendentes com e-mail',
                  onTap: cobrando || cobraveis == 0
                      ? null
                      : () => _cobrarFicha(f),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final a in pendentes) _buildPendente(f, a),
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
    final ok = _ok;
    final info = _info;
    final temLink = a.linkAbrivel != null;
    final temEmail = a.signerEmail?.trim().isNotEmpty ?? false;
    final cobrando = _enviando.contains('sig:${a.signatureId}');
    final df = DateFormat('dd/MM', 'pt_BR');
    final eu = a.ehVoce;

    final Widget acoes;
    if (eu) {
      acoes = temLink
          ? _BotaoAssinar(label: 'Assinar agora', onTap: () => _assinar(a))
          : Text(
              'O link ainda não foi gerado. Abra a ficha para acompanhar.',
              style: t.labelSmall?.copyWith(color: muted, height: 1.35),
            );
    } else if (!temLink) {
      acoes = Text(
        'Link ainda não gerado — nada para enviar por enquanto.',
        style: t.labelSmall?.copyWith(color: muted, height: 1.35),
      );
    } else {
      acoes = Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _AcaoPequena(
            icon: LucideIcons.mailPlus,
            label: cobrando ? 'Enviando…' : 'E-mail',
            cor: info.texto,
            busy: cobrando,
            tooltip:
                temEmail ? 'Enviar o link por e-mail' : 'Sem e-mail cadastrado',
            onTap: !temEmail || cobrando ? null : () => _cobrarSignatario(f, a),
          ),
          _AcaoPequena(
            icon: LucideIcons.messageCircle,
            label: 'WhatsApp',
            cor: ok.texto,
            tooltip: 'Abrir o WhatsApp com a mensagem e o link',
            onTap: () => _whatsApp(f, a),
          ),
          _AcaoPequena(
            icon: LucideIcons.copy,
            label: 'Copiar link',
            cor: muted,
            onTap: () => _copiar(a),
          ),
        ],
      );
    }

    final corpo = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      // Sem nome e sem e-mail o modelo devolve "—".
                      a.nomeExibido == '—'
                          ? 'Signatário sem nome'
                          : a.nomeExibido,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (eu) ...[
                    const SizedBox(width: 6),
                    _VoceBadge(color: ok.texto),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _Dias(
              texto: _haQuanto(a.diasPendente),
              tom: _tomUrgencia(a.diasPendente),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          temEmail ? a.signerEmail!.trim() : 'Sem e-mail cadastrado',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.bodySmall?.copyWith(color: muted),
        ),
        const SizedBox(height: 2),
        Text(
          [
            a.abriu
                ? 'Abriu o link${a.viewedAt != null ? ' em ${df.format(a.viewedAt!.toLocal())}' : ''}'
                : 'Ainda não abriu o link',
            if (a.lembretesWhatsApp > 0)
              '${a.lembretesWhatsApp} '
                  '${a.lembretesWhatsApp == 1 ? 'lembrete' : 'lembretes'} no WhatsApp',
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: t.labelSmall?.copyWith(
            color: a.abriu ? info.texto : muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        acoes,
      ],
    );

    // A sua linha ganha fundo tonal verde (é o que você tem para fazer);
    // as dos outros são linhas flush com filete.
    return Container(
      margin: EdgeInsets.only(top: eu ? 10 : 6),
      padding: eu
          ? const EdgeInsets.fromLTRB(12, 10, 12, 12)
          : const EdgeInsets.fromLTRB(0, 10, 0, 4),
      decoration: eu
          ? BoxDecoration(
              color: ok.sinal.withValues(alpha: _isDark ? 0.10 : 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ok.sinal.withValues(alpha: 0.28)),
            )
          : BoxDecoration(
              border: Border(
                top: BorderSide(color: ThemeHelpers.borderLightColor(context)),
              ),
            ),
      child: corpo,
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

/// Número + rótulo curto (leitura da fila).
class _Leitura extends StatelessWidget {
  const _Leitura({required this.valor, required this.rotulo, this.cor});
  final String valor;
  final String rotulo;
  final Color? cor;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: valor,
            style: t.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: cor ?? ThemeHelpers.textColor(context),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          TextSpan(
            text: ' $rotulo',
            style: t.bodySmall?.copyWith(
              color: cor ?? ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Há quanto tempo está pendente — pílula na cor da urgência (âmbar perto
/// da trava, vermelho na trava); texto neutro quando ainda está no prazo.
class _Dias extends StatelessWidget {
  const _Dias({required this.texto, this.tom});
  final String texto;
  final SaleFormTom? tom;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    final c = tom;
    if (c == null) {
      return Text(
        texto,
        maxLines: 1,
        style: style?.copyWith(
          color: ThemeHelpers.textSecondaryColor(context),
          fontWeight: FontWeight.w800,
        ),
      );
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.sinal.withValues(alpha: isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.hourglass, size: 11, color: c.texto),
          const SizedBox(width: 4),
          Text(
            texto,
            maxLines: 1,
            style: style?.copyWith(color: c.texto, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

/// Recorte "paradas" — chip de alternância na cor da trava (mesma gramática
/// dos atalhos de status da lista de fichas).
class _ChipParadas extends StatelessWidget {
  const _ChipParadas({
    required this.ativo,
    required this.rotulo,
    required this.quantas,
    required this.tom,
    required this.onTap,
  });
  final bool ativo;
  final String rotulo;
  final int quantas;
  final SaleFormTom tom;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final style = Theme.of(context).textTheme.labelMedium;
    return Semantics(
      button: true,
      selected: ativo,
      child: Material(
        color: ativo ? tom.sinal.withValues(alpha: 0.13) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: tom.sinal.withValues(alpha: ativo ? 0.55 : 0.3),
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.hourglass,
                  size: 14,
                  color: ativo ? tom.texto : muted,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    rotulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: ativo ? tom.texto : muted,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$quantas',
                  style: style?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ativo ? tom.texto : ThemeHelpers.textColor(context),
                    fontFeatures: const [FontFeature.tabularFigures()],
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

/// Estado do painel "sua vez" quando não há o que assinar agora.
class _PainelEstado extends StatelessWidget {
  const _PainelEstado({
    required this.icon,
    required this.tom,
    required this.titulo,
    required this.texto,
  });
  final IconData icon;
  final SaleFormTom tom;
  final String titulo;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tom.sinal.withValues(alpha: isDark ? 0.10 : 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tom.sinal.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: tom.texto),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: t.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  texto,
                  style: t.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    height: 1.4,
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

/// Botão verde de assinar — cheio, largura inteira, texto branco. O rótulo
/// encolhe para caber (nunca corta).
class _BotaoAssinar extends StatelessWidget {
  const _BotaoAssinar({
    required this.label,
    required this.onTap,
    this.grande = false,
  });
  final String label;
  final VoidCallback? onTap;
  final bool grande;

  @override
  Widget build(BuildContext context) {
    final fill = SaleFormTom.verdeDeConfirmar();
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: Icon(LucideIcons.penLine, size: grande ? 18 : 16),
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, maxLines: 1, softWrap: false),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: fill,
          foregroundColor: Colors.white,
          disabledBackgroundColor: fill.withValues(alpha: 0.35),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.85),
          minimumSize: Size(0, grande ? 52 : 44),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(grande ? 14 : 12),
          ),
          textStyle: TextStyle(
            fontSize: grande ? 15.5 : 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

/// Ação compacta com rótulo (ícone sozinho não se explica no dia a dia).
class _AcaoPequena extends StatelessWidget {
  const _AcaoPequena({
    required this.icon,
    required this.label,
    required this.cor,
    required this.onTap,
    this.busy = false,
    this.tooltip,
  });
  final IconData icon;
  final String label;
  final Color cor;
  final VoidCallback? onTap;
  final bool busy;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final botao = Opacity(
      opacity: enabled || busy ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: ThemeHelpers.borderColor(context)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                busy
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cor,
                        ),
                      )
                    : Icon(icon, size: 15, color: cor),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final dica = tooltip;
    return dica == null ? botao : Tooltip(message: dica, child: botao);
  }
}

/// Ação principal da estação "Todas" (paridade com o "botão rico" do web):
/// título + linha de apoio, largura inteira.
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
