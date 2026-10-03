import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/navigation/app_navigator.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/sale_forms_service.dart';
import '../pages/create_sale_form_page.dart';
import '../signature_lock_policy.dart';
import 'sale_form_tones.dart';

/// Trava por assinatura parada — paridade com `SignatureLockGate` +
/// `SaleFormSignatureLockModal` do web.
///
/// Consulta `GET /sistema/fichas-venda/assinatura-lock/status`; se o usuário
/// tem assinatura pendente além do prazo (`blocked`), abre uma folha que NÃO
/// fecha por gesto nem pelo voltar: o usuário assina (link do Autentique fora
/// do app), confirma que já assinou (nova consulta), abre a ficha ou registra
/// a recusa com motivo (>= 10 caracteres; o back cancela TODAS as assinaturas
/// ativas da ficha).
///
/// O link de cada item vem do painel `assinaturas/pendentes?escopo=minhas`
/// (a trava não traz o link) — mesma URL que o botão "Assinar" do web usa.
///
/// ATENÇÃO: cada consulta à trava incrementa o contador de avisos no back
/// (até `maxNotifications`). Chamar uma vez por entrada na tela, não em laço.
/// Falha de rede NUNCA bloqueia (igual ao web). Retorna `true` se a folha foi
/// exibida.
Future<bool> showSignatureLockIfBlocked(BuildContext context) async {
  if (_lockAberta) return false;
  if (!ModuleAccessService.instance.hasPermission('sale_form:view')) {
    return false;
  }
  final res = await SaleFormsService.instance.getSignatureLockStatus();
  if (!res.success || res.data == null || !res.data!.blocked) return false;
  if (res.data!.items.isEmpty) return false;
  final links = await _linksMeus();
  if (!context.mounted || _lockAberta) return false;
  _lockAberta = true;
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SignatureLockSheet(
        status: res.data!,
        links: links,
      ),
    );
  } finally {
    _lockAberta = false;
  }
  return true;
}

bool _lockAberta = false;

/// "Ir para a ficha" da trava: `true` = abre a edição (web
/// `/fichas-venda/:id/editar`, rota com `PermissionRoute sale_form:update`);
/// `false` = abre o detalhe. A própria edição cai para só leitura quando a
/// ficha está em assinatura, finalizada, cancelada ou excluída
/// (`saleFormEdicaoBloqueada`), como o `formLockedByStatus` do web.
bool signatureLockIrParaFichaAbreEdicao({required bool canUpdate}) => canUpdate;

/// Próximo estado da trava depois de uma recusa registrada (web:
/// `handleRefuse` → `checkStatus`). [consulta] é a nova consulta ao back:
///  - ok e não bloqueado (ou sem itens) → `null` (fecha);
///  - ok e bloqueado → o que o back devolveu;
///  - falha de rede → a lista local sem a ficha recusada (`null` se vazia).
SaleFormSignatureLockStatus? signatureLockAposRecusa({
  required SaleFormSignatureLockStatus atual,
  required String recusadaId,
  required SaleFormSignatureLockStatus? consulta,
  required bool consultaOk,
}) {
  if (consultaOk) {
    if (consulta == null || !consulta.blocked || consulta.items.isEmpty) {
      return null;
    }
    return consulta;
  }
  final restantes =
      atual.items.where((i) => i.saleFormId != recusadaId).toList();
  if (restantes.isEmpty) return null;
  return SaleFormSignatureLockStatus(
    blocked: true,
    maxNotifications: atual.maxNotifications,
    thresholdDays: atual.thresholdDays,
    items: restantes,
  );
}

/// Reavalia a trava ao longo do uso, como o `SignatureLockGate` do web
/// (consulta a cada troca de rota; o modal não fecha): a cada tela nova
/// ([SignatureLockRouteObserver], registrado no `MaterialApp`), ao montar a
/// Home, ao voltar o app para o primeiro plano e ao voltar da ficha aberta
/// pela própria trava. As telas das fichas de venda ficam de fora (o web pula
/// `/fichas-venda…`): as nomeadas pelo nome da rota, as sem nome por
/// [marcarTelaDeFicha].
///
/// O back conta no máximo um aviso por dia por ficha; o intervalo
/// [kSignatureLockIntervaloMinimo] só junta rajadas de troca de tela.
class SignatureLockWatcher with WidgetsBindingObserver {
  SignatureLockWatcher._();
  static final SignatureLockWatcher instance = SignatureLockWatcher._();

  bool _observando = false;
  DateTime? _ultimaConsulta;
  final Expando<bool> _telasDeFicha = Expando<bool>('telaDeFicha');

  /// Marca a rota de uma tela das fichas de venda aberta sem nome (detalhe,
  /// criação/edição, auditoria) — o web não consulta a trava nessas telas.
  void marcarTelaDeFicha(BuildContext context) {
    final r = ModalRoute.of(context);
    if (r != null) _telasDeFicha[r] = true;
  }

  /// `true` = ao entrar nesta rota a trava não é consultada.
  bool rotaIgnorada(Route<dynamic> route) =>
      _telasDeFicha[route] == true ||
      signatureLockRotaIgnorada(route.settings.name);

  /// Liga a reavaliação ao voltar para o primeiro plano (idempotente).
  void start() {
    if (_observando) return;
    _observando = true;
    WidgetsBinding.instance.addObserver(this);
  }

  /// Consulta a trava e abre a folha se bloqueado. Sem [force], respeita o
  /// intervalo mínimo. Usa o contexto do navegador raiz quando [context] é
  /// nulo.
  Future<bool> check({BuildContext? context, bool force = false}) async {
    final agora = DateTime.now();
    if (!force && !signatureLockPodeConsultar(_ultimaConsulta, agora)) {
      return false;
    }
    final ctx = context ?? appNavigatorKey.currentState?.overlay?.context;
    if (ctx == null || !ctx.mounted) return false;
    _ultimaConsulta = agora;
    return showSignatureLockIfBlocked(ctx);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Sem sessão (logout limpa as permissões) a folha nem consulta.
      check();
    }
  }
}

/// Observador do navegador raiz: a cada tela nova (push, replace ou volta
/// para uma tela), consulta a trava — `useEffect([location.pathname])` do
/// `SignatureLockGate` web. Diálogos e folhas não contam (no web não mudam a
/// rota). Espera a transição assentar e só consulta se a tela ainda for a do
/// topo e não for das fichas/login.
class SignatureLockRouteObserver extends NavigatorObserver {
  SignatureLockRouteObserver._();
  static final SignatureLockRouteObserver instance =
      SignatureLockRouteObserver._();

  static const Duration _assentar = Duration(milliseconds: 450);

  void _agendar(Route<dynamic>? route) {
    if (route is! PageRoute) return;
    Future<void>.delayed(_assentar, () {
      if (!route.isActive || !route.isCurrent) return;
      final w = SignatureLockWatcher.instance;
      if (w.rotaIgnorada(route)) return;
      final ctx = route.navigator?.overlay?.context;
      if (ctx == null || !ctx.mounted) return;
      w.check(context: ctx);
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _agendar(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Fechar diálogo/folha não troca a tela.
    if (route is PageRoute) _agendar(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _agendar(newRoute);
}

/// saleFormId → link de assinatura do usuário logado (http/https).
Future<Map<String, String>> _linksMeus() async {
  final r = await SaleFormsService.instance
      .listarAssinaturasPendentes(escopo: 'minhas');
  final out = <String, String>{};
  if (!r.success || r.data == null) return out;
  for (final f in r.data!.fichas) {
    for (final p in f.pendentes) {
      final link = p.linkAbrivel;
      if (p.ehVoce && link != null) out.putIfAbsent(f.saleFormId, () => link);
    }
  }
  return out;
}

class _SignatureLockSheet extends StatefulWidget {
  const _SignatureLockSheet({required this.status, required this.links});

  final SaleFormSignatureLockStatus status;
  final Map<String, String> links;

  @override
  State<_SignatureLockSheet> createState() => _SignatureLockSheetState();
}

class _SignatureLockSheetState extends State<_SignatureLockSheet> {
  late SaleFormSignatureLockStatus _status = widget.status;
  late Map<String, String> _links = widget.links;
  bool _verificando = false;
  String? _recusando;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  // Tons legíveis também no modo claro; o verde cheio fica para o botão.
  Color get _green => SaleFormTom.sucesso(context).texto;
  Color get _red => SaleFormTom.erro(context).texto;
  SaleFormTom get _warn => SaleFormTom.aviso(context);

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _assinar(SaleFormSignatureLockItem item) async {
    final link = _links[item.saleFormId];
    if (link == null) return;
    final ok = await launchUrl(
      Uri.parse(link),
      mode: LaunchMode.externalApplication,
    );
    if (!ok) _snack('Não foi possível abrir o link de assinatura.');
  }

  /// "Já assinei": remove a ficha na hora e confirma com o back. Resposta
  /// transitória sem trava não fecha se ainda havia outras fichas.
  Future<void> _jaAssinei(SaleFormSignatureLockItem item) async {
    final anteriores =
        _status.items.where((i) => i.saleFormId != item.saleFormId).toList();
    setState(() => _verificando = true);
    final res = await SaleFormsService.instance.getSignatureLockStatus();
    if (!mounted) return;
    setState(() => _verificando = false);
    if (res.success && res.data != null && res.data!.blocked) {
      final ainda = res.data!.items.any((i) => i.saleFormId == item.saleFormId);
      setState(() => _status = res.data!);
      if (ainda) {
        _snack('A assinatura da ficha ${item.formNumber} ainda consta como '
            'pendente. Se acabou de assinar, aguarde alguns segundos.');
      }
      if (res.data!.items.isEmpty) Navigator.of(context).pop();
      return;
    }
    if (res.success && anteriores.isNotEmpty) {
      setState(() => _status = SaleFormSignatureLockStatus(
            blocked: true,
            maxNotifications: _status.maxNotifications,
            thresholdDays: _status.thresholdDays,
            items: anteriores,
          ));
      return;
    }
    if (!res.success) {
      // Rede: não prende o usuário (mesma regra do web).
      if (anteriores.isEmpty) {
        Navigator.of(context).pop();
      } else {
        setState(() => _status = SaleFormSignatureLockStatus(
              blocked: true,
              maxNotifications: _status.maxNotifications,
              thresholdDays: _status.thresholdDays,
              items: anteriores,
            ));
      }
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _recusar(SaleFormSignatureLockItem item) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => _RecusaDialog(formNumber: item.formNumber, red: _red),
    );
    if (reason == null || !mounted) return;
    setState(() => _recusando = item.saleFormId);
    final res = await SaleFormsService.instance
        .recusarSignatureLock(item.saleFormId, reason);
    if (!mounted) return;
    setState(() => _recusando = null);
    if (!res.success) {
      _snack(res.message ?? 'Não foi possível registrar a recusa.');
      return;
    }
    _snack(res.data ?? 'Recusa registrada.');
    // Web (`SignatureLockGate.handleRefuse`): depois da recusa consulta a
    // trava de novo (`checkStatus`) — outra ficha pode ter entrado no prazo
    // nesse meio-tempo. Falha de rede não prende: fica a lista local sem a
    // ficha recusada.
    final restantes =
        _status.items.where((i) => i.saleFormId != item.saleFormId).toList();
    setState(() => _verificando = true);
    final again = await SaleFormsService.instance.getSignatureLockStatus();
    if (!mounted) return;
    setState(() => _verificando = false);
    final proximo = signatureLockAposRecusa(
      atual: _status,
      recusadaId: item.saleFormId,
      consulta: again.success ? again.data : null,
      consultaOk: again.success,
    );
    if (proximo == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _status = proximo);
    if (restantes.length != proximo.items.length ||
        proximo.items.any((i) => !_links.containsKey(i.saleFormId))) {
      final novos = await _linksMeus();
      if (mounted) setState(() => _links = novos);
    }
  }

  /// "Ir para a ficha" — web: `navigate('/fichas-venda/:id/editar')`. A
  /// edição do app, como a do web, relê a ficha e, em assinatura/finalizada/
  /// cancelada, vira só leitura (detalhe). Sem `sale_form:update` (a rota
  /// `/editar` do web exige) abre o detalhe. Ao voltar, reavalia a trava (no
  /// web o modal reaparece na rota seguinte).
  Future<void> _abrirFicha(SaleFormSignatureLockItem item) async {
    final nav = Navigator.of(context);
    final edicao = signatureLockIrParaFichaAbreEdicao(
      canUpdate: ModuleAccessService.instance.hasPermission('sale_form:update'),
    );
    nav.pop();
    if (edicao) {
      await nav.push<bool>(
        MaterialPageRoute(
          builder: (_) => CreateSaleFormPage(saleFormId: item.saleFormId),
        ),
      );
    } else {
      await nav.pushNamed(AppRoutes.saleFormDetails(item.saleFormId));
    }
    if (!nav.mounted) return;
    await SignatureLockWatcher.instance
        .check(context: nav.overlay?.context, force: true);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final t = Theme.of(context).textTheme;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final dias = _status.thresholdDays;
    final n = _status.items.length;
    final aviso = _warn;
    return PopScope(
      canPop: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: mq.size.height * 0.88),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + mq.padding.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: aviso.sinal
                              .withValues(alpha: _isDark ? 0.18 : 0.14),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(
                          LucideIcons.shieldAlert,
                          size: 21,
                          color: aviso.texto,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Assinatura pendente obrigatória',
                              style: t.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              n == 1
                                  ? '1 ficha esperando a sua assinatura'
                                  : '$n fichas esperando a sua assinatura',
                              style: t.bodySmall?.copyWith(
                                color: aviso.texto,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Você tem assinatura de ficha de venda pendente há mais de '
                    '$dias ${dias == 1 ? 'dia' : 'dias'}. Para continuar '
                    'usando o sistema, assine agora ou registre a recusa com '
                    'justificativa.',
                    style: t.bodySmall?.copyWith(color: muted, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  for (final item in _status.items) _buildItem(item),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItem(SaleFormSignatureLockItem item) {
    final t = Theme.of(context).textTheme;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final link = _links[item.saleFormId];
    final recusando = _recusando == item.saleFormId;
    final ocupado = _verificando || _recusando != null;
    final max = _status.maxNotifications;
    final vistos =
        item.notificationCount > max ? max : item.notificationCount;
    final tentativa =
        max > 0 ? '$vistos de $max' : '${item.notificationCount}';
    final fill = SaleFormTom.verdeDeConfirmar();
    final erro = SaleFormTom.erro(context);
    // Botões secundários: contorno com a cor do significado (verde = já
    // assinei, vermelho = recusar, neutro = abrir a ficha).
    ButtonStyle contorno(Color cor) => OutlinedButton.styleFrom(
          foregroundColor: cor,
          side: BorderSide(color: cor.withValues(alpha: 0.45)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.formNumber.isEmpty
                      ? 'Ficha sem número'
                      : 'Ficha ${item.formNumber}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: erro.sinal.withValues(alpha: _isDark ? 0.18 : 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.hourglass, size: 12, color: _red),
                    const SizedBox(width: 4),
                    Text(
                      item.daysPending == 1
                          ? 'há 1 dia'
                          : 'há ${item.daysPending} dias',
                      style: t.labelMedium?.copyWith(
                        color: _red,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Aviso $tentativa'
            '${item.signerEmail != null ? ' · ${item.signerEmail}' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.labelSmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: link != null
                ? FilledButton.icon(
                    onPressed: ocupado ? null : () => _assinar(item),
                    icon: const Icon(LucideIcons.penLine, size: 17),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Assinar agora',
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: fill,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: fill.withValues(alpha: 0.35),
                      disabledForegroundColor:
                          Colors.white.withValues(alpha: 0.85),
                      minimumSize: const Size(0, 50),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  )
                : OutlinedButton.icon(
                    onPressed: ocupado ? null : () => _abrirFicha(item),
                    icon: const Icon(LucideIcons.fileText, size: 17),
                    label: const Text('Ir para a ficha'),
                    style: contorno(ThemeHelpers.textColor(context)),
                  ),
          ),
          if (link != null) ...[
            const SizedBox(height: 6),
            Text(
              'Abre o Autentique fora do app. Depois, toque em "Já assinei".',
              style: t.labelSmall?.copyWith(color: muted, height: 1.35),
            ),
            // Web: "Ir para a ficha" sempre aparece na trava.
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: ocupado ? null : () => _abrirFicha(item),
                icon: const Icon(LucideIcons.fileText, size: 17),
                label: const Text('Ir para a ficha'),
                style: contorno(ThemeHelpers.textColor(context)),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: ocupado ? null : () => _jaAssinei(item),
                  icon: const Icon(LucideIcons.checkCheck, size: 16),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _verificando ? 'Verificando…' : 'Já assinei',
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                  style: contorno(_green),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: ocupado ? null : () => _recusar(item),
                  icon: const Icon(LucideIcons.ban, size: 16),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      recusando ? 'Registrando…' : 'Recusar',
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                  style: contorno(_red),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecusaDialog extends StatefulWidget {
  const _RecusaDialog({required this.formNumber, required this.red});
  final String formNumber;
  final Color red;

  @override
  State<_RecusaDialog> createState() => _RecusaDialogState();
}

class _RecusaDialogState extends State<_RecusaDialog> {
  final TextEditingController _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = _c.text.trim().length >= 10;
    return AlertDialog(
      backgroundColor: ThemeHelpers.cardBackgroundColor(context),
      title: Text('Recusar a assinatura da ficha ${widget.formNumber}?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ao confirmar, todas as assinaturas ativas desta ficha serão '
              'canceladas e o fluxo deverá ser reenviado para todos assinarem '
              'novamente.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    height: 1.4,
                  ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _c,
              autofocus: true,
              minLines: 3,
              maxLines: 5,
              maxLength: 2000,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Motivo da recusa *',
                hintText: 'Por que você não quer assinar esta ficha?',
                helperText: 'Mínimo de 10 caracteres.',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: ThemeHelpers.textSecondaryColor(context),
          ),
          child: const Text('Voltar'),
        ),
        FilledButton(
          onPressed: ok ? () => Navigator.of(context).pop(_c.text.trim()) : null,
          style: FilledButton.styleFrom(
            backgroundColor: widget.red,
            foregroundColor: Colors.white,
          ),
          child: const Text('Confirmar recusa'),
        ),
      ],
    );
  }
}
