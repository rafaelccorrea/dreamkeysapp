import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/whatsapp_models.dart';
import '../services/whatsapp_service.dart';

/// Bottom-sheet **Enviar template** — fora da janela de 24h da API oficial,
/// só template aprovado pela Meta chega ao cliente.
///
/// Regra espelhada de `SendWhatsAppTemplate.tsx` (painel web):
///  - lista os APROVADOS de `WhatsAppService.getTemplates()` (exige
///    `whatsapp:manage_config`), com busca por nome, categoria, idioma e
///    texto; um aprovado só já abre direto;
///  - escolher abre a PRÉVIA: a bolha como sai na conversa, com cabeçalho
///    (texto ou mídia), corpo com as variáveis preenchidas AO VIVO, rodapé e
///    botões. Variáveis do cabeçalho de texto e do corpo são obrigatórias (a
///    Meta recusa o envio incompleto): o Enviar trava dizendo quantas faltam;
///  - as variáveis de NOME e de CÓDIGO DO IMÓVEL já chegam preenchidas quando
///    a conversa sabe o dado e o template confirma (exemplo da Meta + texto
///    antes da variável — `whatsappTemplateVariaveis.ts`); debaixo de cada
///    campo, as sugestões da conversa; o que a pessoa digita nunca é trocado;
///  - sem a lista (403, lista vazia ou falha) sobra a digitação manual do
///    nome + variáveis opcionais, sem prévia — enviar só exige
///    `whatsapp:send`.
///
/// Envio: `WhatsAppService.sendTemplate` → `POST /whatsapp/send-template`
/// com `to`, `templateName`, `parameters` (corpo, na ordem {{1}}…{{n}}),
/// `headerParameters` (cabeçalho de texto), `languageCode` (idioma do
/// template) e `clientId`. Cabeçalho de mídia vai como no web: sem parâmetro.
///
/// Fecha com `true` quando o envio deu certo.
class WhatsAppSendTemplateSheet extends StatefulWidget {
  final String phoneNumber;
  final String? clientId;

  /// Nome da conversa (apelido do WhatsApp ou cadastro): alimenta as
  /// variáveis de nome ("Olá, {{1}}").
  final String? nomeDoContato;

  /// Nome do cadastro do cliente — vale quando o [nomeDoContato] não dá um
  /// nome (apelido só de emoji ou ponto), como no web.
  final String? nomeDoCadastro;

  /// Imóvel ligado à conversa, quando quem abre o sheet já o tem: alimenta as
  /// variáveis de código ("imóvel {{2}}") e as sugestões.
  final String? codigoDoImovel;
  final String? tituloDoImovel;

  /// Card do CRM ligado à conversa: o sheet busca nele o imóvel vinculado,
  /// como o web (`GET /kanban/tasks/:id/fields` → `property`), em paralelo.
  final String? kanbanTaskId;

  const WhatsAppSendTemplateSheet({
    super.key,
    required this.phoneNumber,
    this.clientId,
    this.nomeDoContato,
    this.nomeDoCadastro,
    this.codigoDoImovel,
    this.tituloDoImovel,
    this.kanbanTaskId,
  });

  /// Abre o sheet e devolve `true` se um template foi enviado.
  static Future<bool> show(
    BuildContext context, {
    required String phoneNumber,
    String? clientId,
    String? nomeDoContato,
    String? nomeDoCadastro,
    String? codigoDoImovel,
    String? tituloDoImovel,
    String? kanbanTaskId,
  }) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      // Tablet/paisagem: largura máxima; a prévia vai ao lado das variáveis
      // quando a folha passa de 680.
      constraints: const BoxConstraints(maxWidth: 720),
      builder: (_) => WhatsAppSendTemplateSheet(
        phoneNumber: phoneNumber,
        clientId: clientId,
        nomeDoContato: nomeDoContato,
        nomeDoCadastro: nomeDoCadastro,
        codigoDoImovel: codigoDoImovel,
        tituloDoImovel: tituloDoImovel,
        kanbanTaskId: kanbanTaskId,
      ),
    );
    return sent == true;
  }

  @override
  State<WhatsAppSendTemplateSheet> createState() =>
      _WhatsAppSendTemplateSheetState();
}

enum _Fase { carregando, erro, lista, compor, manual }

/// Por que o sheet caiu na digitação manual — muda a explicação.
enum _MotivoManual { semPermissao, listaVazia, falhaNaLista }

class _WhatsAppSendTemplateSheetState extends State<WhatsAppSendTemplateSheet> {
  final _buscaController = TextEditingController();
  final _nomeController = TextEditingController();

  /// Variáveis do corpo e do cabeçalho de texto, por posição ({{1}} = 0). O
  /// que a pessoa digitou fica ao trocar de template.
  final List<TextEditingController> _vars = [];
  final List<TextEditingController> _varsCabecalho = [];

  /// O que NÓS preenchemos em cada posição ('' onde a pessoa manda) e quais
  /// campos a pessoa já tocou — tocado nunca é recalculado (regra do web).
  final List<String> _autoCorpo = [];
  final List<String> _autoCabecalho = [];
  final List<bool> _tocadoCorpo = [];
  final List<bool> _tocadoCabecalho = [];

  /// Variáveis da digitação manual (opcionais; a pessoa adiciona).
  final List<TextEditingController> _varsManuais = [];

  /// O que a conversa sabe: nome do contato e imóvel (este pode chegar
  /// depois, pelo card).
  late _ContextoVariaveis _ctx;

  _Fase _fase = _Fase.carregando;
  _MotivoManual _motivoManual = _MotivoManual.semPermissao;
  List<_Modelo> _modelos = const [];
  _Modelo? _escolhido;
  bool _enviando = false;

  String? _erroMensagem;
  int _erroStatus = 0;
  Object? _erroDetalhe;

  /// Recusa do último envio, dita no rodapé até a pessoa mexer de novo.
  String? _erroEnvio;

  @override
  void initState() {
    super.initState();
    _ctx = _ContextoVariaveis.de(
      nomeDoContato: widget.nomeDoContato,
      nomeDoCadastro: widget.nomeDoCadastro,
      codigoDoImovel: widget.codigoDoImovel,
      tituloDoImovel: widget.tituloDoImovel,
    );
    // As duas buscas partem juntas; a do imóvel nunca segura o modal.
    _carregar();
    _buscarImovelDoCard();
  }

  @override
  void dispose() {
    _buscaController.dispose();
    _nomeController.dispose();
    for (final c in _vars) {
      c.dispose();
    }
    for (final c in _varsCabecalho) {
      c.dispose();
    }
    for (final c in _varsManuais) {
      c.dispose();
    }
    super.dispose();
  }

  // ─── Dados ─────────────────────────────────────────────────────────────────

  Future<void> _carregar() async {
    if (_fase != _Fase.carregando) {
      setState(() => _fase = _Fase.carregando);
    }
    final res = await WhatsAppService.instance.getTemplates();
    if (!mounted) return;
    if (res.success) {
      final aprovados = <_Modelo>[
        for (final t in res.data ?? const <WhatsAppTemplate>[])
          if (t.isApproved) _Modelo.de(t),
      ];
      setState(() {
        _modelos = aprovados;
        // Um aprovado só: abre a prévia dele (o web já o deixa escolhido).
        if (aprovados.length == 1) {
          _abrir(aprovados.first);
        } else {
          _fase = _Fase.lista;
        }
      });
      return;
    }
    setState(() {
      if (res.statusCode == 403) {
        // Sem `whatsapp:manage_config`: não vê a lista, mas pode enviar.
        _motivoManual = _MotivoManual.semPermissao;
        _fase = _Fase.manual;
      } else {
        _erroMensagem = res.message;
        _erroStatus = res.statusCode;
        _erroDetalhe = res.error;
        _fase = _Fase.erro;
      }
    });
  }

  /// Imóvel do card ligado à conversa, pelo mesmo caminho do web
  /// (`buscarImovelDaConversa`): `GET /kanban/tasks/:id/fields` →
  /// `property.code` / `property.title`. Sem card, sem permissão ou sem
  /// resposta, simplesmente não há sugestão de imóvel.
  Future<void> _buscarImovelDoCard() async {
    final id = (widget.kanbanTaskId ?? '').trim();
    if (id.isEmpty) return;
    // `KanbanService.getTaskById` faz este mesmo GET, mas o `KanbanTask` do
    // app não guarda o imóvel: aqui a resposta é lida crua, com a mesma
    // constante.
    final res = await ApiService.instance
        .get<dynamic>(ApiConstants.kanbanTaskFields(id));
    if (!mounted || !res.success) return;
    final card = res.data;
    final imovel = card is Map ? card['property'] : null;
    if (imovel is! Map) return;
    final codigo = (imovel['code'] ?? '').toString().trim();
    final titulo = (imovel['title'] ?? '').toString().trim();
    if (codigo.isEmpty && titulo.isEmpty) return;
    setState(() {
      _ctx = _ctx.comImovel(
        codigo: codigo.isEmpty ? null : codigo,
        titulo: titulo.isEmpty ? null : titulo,
      );
      // Como o web: o contexto novo recalcula só os campos "nossos" do
      // template aberto — o que a pessoa digitou não muda.
      final m = _escolhido;
      if (m != null) _recalcularTudo(m);
    });
  }

  /// Prepara a composição (sem setState — quem chama envolve): campos no
  /// tamanho do template e o preenchimento automático recalculado.
  void _abrir(_Modelo m) {
    _recalcularTudo(m);
    _escolhido = m;
    _erroEnvio = null;
    _fase = _Fase.compor;
  }

  void _recalcularTudo(_Modelo m) {
    _garantirCampos(
      _varsCabecalho,
      _autoCabecalho,
      _tocadoCabecalho,
      m.varsNoCabecalho,
    );
    _garantirCampos(_vars, _autoCorpo, _tocadoCorpo, m.varsNoCorpo);
    _recalcular(
      _varsCabecalho,
      _autoCabecalho,
      _tocadoCabecalho,
      n: m.varsNoCabecalho,
      exemplo: m.exemploDoCabecalho,
      texto: m.textoCabecalho,
    );
    _recalcular(
      _vars,
      _autoCorpo,
      _tocadoCorpo,
      n: m.varsNoCorpo,
      exemplo: m.exemploDoCorpo,
      texto: m.textoCorpo,
    );
  }

  void _garantirCampos(
    List<TextEditingController> campos,
    List<String> autos,
    List<bool> tocados,
    int n,
  ) {
    while (campos.length < n) {
      campos.add(TextEditingController());
    }
    while (autos.length < n) {
      autos.add('');
    }
    while (tocados.length < n) {
      tocados.add(false);
    }
  }

  /// `recalcularVariaveis` do web: campo tocado nunca muda; dos outros, é
  /// "nosso" o vazio ou o que ainda tem exatamente o valor que nós pusemos —
  /// só esses são recalculados (inclusive para vazio, quando o template novo
  /// não tem evidência).
  void _recalcular(
    List<TextEditingController> campos,
    List<String> autos,
    List<bool> tocados, {
    required int n,
    required String? Function(int) exemplo,
    required String? texto,
  }) {
    for (var i = 0; i < n; i++) {
      final atual = campos[i].text;
      final anterior = autos[i];
      final nosso = !tocados[i] &&
          (atual.trim().isEmpty || (anterior.isNotEmpty && atual == anterior));
      if (!nosso) {
        autos[i] = '';
        continue;
      }
      final sugerido = _sugerirValor(exemplo(i), _ctx, texto, i);
      if (campos[i].text != sugerido) campos[i].text = sugerido;
      autos[i] = sugerido;
    }
  }

  /// Digitou: o campo passa a ser da pessoa, de vez.
  void _aoDigitar({required bool cabecalho, required int i}) {
    setState(() {
      (cabecalho ? _tocadoCabecalho : _tocadoCorpo)[i] = true;
      (cabecalho ? _autoCabecalho : _autoCorpo)[i] = '';
      _erroEnvio = null;
    });
  }

  /// Tocou numa sugestão: vale como digitado.
  void _usarSugestao({
    required bool cabecalho,
    required int i,
    required String valor,
  }) {
    final campo = (cabecalho ? _varsCabecalho : _vars)[i];
    campo.value = TextEditingValue(
      text: valor,
      selection: TextSelection.collapsed(offset: valor.length),
    );
    setState(() {
      (cabecalho ? _tocadoCabecalho : _tocadoCorpo)[i] = true;
      (cabecalho ? _autoCabecalho : _autoCorpo)[i] = '';
      _erroEnvio = null;
    });
  }

  /// Algum campo deste template está com valor que NÓS pusemos.
  bool _algumAutomatico(_Modelo m) {
    for (var i = 0; i < m.varsNoCabecalho; i++) {
      if (_autoCabecalho[i].isNotEmpty) return true;
    }
    for (var i = 0; i < m.varsNoCorpo; i++) {
      if (_autoCorpo[i].isNotEmpty) return true;
    }
    return false;
  }

  void _escolher(_Modelo m) {
    FocusScope.of(context).unfocus();
    setState(() => _abrir(m));
  }

  void _voltarParaLista() {
    FocusScope.of(context).unfocus();
    setState(() {
      _erroEnvio = null;
      _fase = _Fase.lista;
    });
  }

  void _irParaManual(_MotivoManual motivo) {
    FocusScope.of(context).unfocus();
    setState(() {
      _motivoManual = motivo;
      _erroEnvio = null;
      _fase = _Fase.manual;
    });
  }

  void _adicionarVariavelManual() {
    setState(() => _varsManuais.add(TextEditingController()));
  }

  void _removerVariavelManual(int index) {
    final c = _varsManuais[index];
    setState(() => _varsManuais.removeAt(index));
    // Descarta depois do quadro: o campo ainda está preso ao controller
    // enquanto sai da árvore.
    WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
  }

  List<_Modelo> get _filtrados {
    final termo = _normalizar(_buscaController.text.trim());
    if (termo.isEmpty) return _modelos;
    return _modelos.where((m) => m.busca.contains(termo)).toList();
  }

  /// Variáveis vazias do template escolhido (cabeçalho de texto + corpo).
  int get _faltam {
    final m = _escolhido;
    if (m == null) return 0;
    var faltam = 0;
    for (var i = 0; i < m.varsNoCabecalho; i++) {
      if (_varsCabecalho[i].text.trim().isEmpty) faltam++;
    }
    for (var i = 0; i < m.varsNoCorpo; i++) {
      if (_vars[i].text.trim().isEmpty) faltam++;
    }
    return faltam;
  }

  bool get _podeEnviar {
    if (_enviando) return false;
    if (_fase == _Fase.compor) return _escolhido != null && _faltam == 0;
    if (_fase == _Fase.manual) return _nomeController.text.trim().isNotEmpty;
    return false;
  }

  Future<void> _enviar() async {
    if (!_podeEnviar) return;
    final String nome;
    final List<String> parametros;
    final List<String> parametrosDoCabecalho;
    final String? idioma;
    final m = _escolhido;
    if (_fase == _Fase.compor && m != null) {
      // Como o web: corpo e cabeçalho na ordem {{1}}…{{n}}, todas
      // preenchidas (trava acima), e o idioma do template no catálogo.
      nome = m.t.name;
      parametros = [
        for (var i = 0; i < m.varsNoCorpo; i++) _vars[i].text.trim(),
      ];
      parametrosDoCabecalho = [
        for (var i = 0; i < m.varsNoCabecalho; i++)
          _varsCabecalho[i].text.trim(),
      ];
      idioma = m.t.language;
    } else {
      // Nome digitado: sem catálogo não há cabeçalho nem idioma conhecidos
      // (o back usa pt_BR), como no web.
      nome = _nomeController.text.trim();
      parametros = _varsManuais
          .map((c) => c.text.trim())
          .where((v) => v.isNotEmpty)
          .toList();
      parametrosDoCabecalho = const [];
      idioma = null;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _enviando = true;
      _erroEnvio = null;
    });
    final res = await WhatsAppService.instance.sendTemplate(
      to: widget.phoneNumber,
      templateName: nome,
      parameters: parametros,
      headerParameters: parametrosDoCabecalho,
      languageCode: idioma,
      clientId: widget.clientId,
    );
    if (!mounted) return;
    if (res.success) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _enviando = false;
      _erroEnvio = _causaDoEnvio(res.message, res.statusCode);
    });
  }

  /// Causa em português — a exceção crua ("Erro de conexão: …") que o
  /// serviço devolve não ajuda quem está no atendimento.
  String _causaDoEnvio(String? mensagem, int status) {
    final msg = (mensagem ?? '').trim();
    if (status == 0) {
      if (msg.isEmpty || msg.startsWith('Erro de conexão')) {
        return 'Sem conexão com o servidor. Confira a internet e tente de '
            'novo.';
      }
      return msg;
    }
    if (msg.isNotEmpty) return msg;
    return 'O servidor recusou o envio (erro $status). Tente de novo.';
  }

  // ─── Casca ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final teclado = mq.viewInsets.bottom;
        final alturaTotal = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : mq.size.height;
        // Teto de 88% da tela e nunca atrás do teclado.
        final teto = math.max(
          0.0,
          math.min(mq.size.height * 0.88, alturaTotal - teclado),
        );
        // Teclado aberto ou tela deitada: sai a alça e o subtítulo e o rodapé
        // encolhe; abaixo de 250 o rodapé desce para o fim da rolagem. A
        // árvore do corpo não muda com isso (o campo em foco não perde o
        // teclado).
        final compacto = teto < 420;
        final rodapeNaRolagem = teto < 250;
        final largo = constraints.maxWidth >= 680;
        final temRodape = _fase == _Fase.compor || _fase == _Fase.manual;

        return Padding(
          padding: EdgeInsets.only(bottom: teclado),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: teto),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: ThemeHelpers.backgroundColor(context),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border.all(
                  color:
                      ThemeHelpers.borderColor(context).withValues(alpha: 0.40),
                ),
              ),
              // Material transparente acima do fundo: o toque das linhas
              // aparece (no Material do sheet ele ficava atrás da cor).
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _alca(context, visivel: !compacto),
                    _cabecalho(context, compacto: compacto),
                    Flexible(
                      child: _corpo(
                        context,
                        largo: largo,
                        rodape: temRodape && rodapeNaRolagem
                            ? _rodape(
                                context,
                                compacto: true,
                                fixo: false,
                                largo: largo,
                              )
                            : null,
                        folgaFinal: temRodape ? 12 : 16 + mq.padding.bottom,
                      ),
                    ),
                    if (temRodape && !rodapeNaRolagem)
                      _rodape(
                        context,
                        compacto: compacto,
                        fixo: true,
                        largo: largo,
                      )
                    else
                      const SizedBox.shrink(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _alca(BuildContext context, {required bool visivel}) {
    return SizedBox(
      height: visivel ? 18 : 0,
      child: visivel
          ? Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color:
                      ThemeHelpers.borderColor(context).withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            )
          : null,
    );
  }

  /// Regra da casa: título à esquerda, fechar à direita.
  Widget _cabecalho(BuildContext context, {required bool compacto}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: EdgeInsets.fromLTRB(16, compacto ? 4 : 2, 6, compacto ? 4 : 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: Row(
        children: [
          if (!compacto) ...[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _verde(isDark).withValues(alpha: isDark ? 0.18 : 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                LucideIcons.messageSquareText,
                size: 19,
                color: _tintaVerde(isDark),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Enviar template',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                if (!compacto) ...[
                  const SizedBox(height: 1),
                  Text(
                    'Para ${formatWhatsAppPhone(widget.phoneNumber)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed:
                _enviando ? null : () => Navigator.of(context).pop(false),
            tooltip: 'Fechar',
            visualDensity: compacto ? VisualDensity.compact : null,
            icon: Icon(LucideIcons.x, size: 20, color: secondary),
          ),
        ],
      ),
    );
  }

  Widget _corpo(
    BuildContext context, {
    required bool largo,
    required Widget? rodape,
    required double folgaFinal,
  }) {
    final List<Widget> filhos = switch (_fase) {
      _Fase.carregando => _conteudoCarregando(context),
      _Fase.erro => _conteudoErro(context),
      _Fase.lista => _conteudoLista(context),
      _Fase.compor => _conteudoCompor(context, largo: largo),
      _Fase.manual => _conteudoManual(context),
    };
    return SingleChildScrollView(
      // Uma rolagem por fase: trocar de fase volta ao topo.
      key: ValueKey<_Fase>(_fase),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(bottom: rodape == null ? folgaFinal : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ...filhos,
          ?rodape,
        ],
      ),
    );
  }

  // ─── Lista ─────────────────────────────────────────────────────────────────

  List<Widget> _conteudoCarregando(BuildContext context) {
    return [
      _introJanela(context),
      _campoBusca(context, habilitado: false),
      const SizedBox(height: 8),
      for (var i = 0; i < 5; i++) _LinhaEsqueleto(ultima: i == 4),
    ];
  }

  List<Widget> _conteudoErro(BuildContext context) {
    return [
      AppErrorState.fromApi(
        message: _erroMensagem,
        statusCode: _erroStatus,
        error: _erroDetalhe,
        onRetry: _carregar,
        secondaryLabel: 'Digitar o nome',
        onSecondary: () => _irParaManual(_MotivoManual.falhaNaLista),
        dense: true,
      ),
    ];
  }

  List<Widget> _conteudoLista(BuildContext context) {
    if (_modelos.isEmpty) {
      return [
        _introJanela(context),
        _EstadoVazio(
          icone: LucideIcons.inbox,
          titulo: 'Nenhum template aprovado',
          texto: 'Templates são criados e aprovados na Meta, no Gerenciador '
              'do WhatsApp da empresa. Quando um for aprovado, ele aparece '
              'aqui com a prévia. Se você sabe o nome exato de um aprovado, '
              'dá para digitar.',
          acao: _botaoNeutro(
            context,
            icone: LucideIcons.pencilLine,
            rotulo: 'Digitar o nome do template',
            onPressed: () => _irParaManual(_MotivoManual.listaVazia),
          ),
        ),
      ];
    }
    final filtrados = _filtrados;
    return [
      _introJanela(context),
      _campoBusca(context, habilitado: true),
      _linhaContagem(context, filtrados.length),
      if (filtrados.isEmpty)
        _EstadoVazio(
          icone: LucideIcons.searchX,
          titulo: 'Nenhum template com “${_buscaController.text.trim()}”',
          texto: 'A busca olha o nome, a categoria, o idioma e o texto da '
              'mensagem. Tente outra palavra.',
          acao: _botaoNeutro(
            context,
            icone: LucideIcons.x,
            rotulo: 'Limpar busca',
            onPressed: () => setState(_buscaController.clear),
          ),
        )
      else
        for (var i = 0; i < filtrados.length; i++)
          _LinhaDoModelo(
            modelo: filtrados[i],
            ultima: i == filtrados.length - 1,
            jaEscolhido: _escolhido?.chave == filtrados[i].chave,
            onTap: () => _escolher(filtrados[i]),
          ),
    ];
  }

  /// A regra da Meta dita onde a dúvida aparece: na hora de escolher.
  Widget _introJanela(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(LucideIcons.info, size: 15, color: secondary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Fora da janela de 24h, o WhatsApp oficial só entrega template '
              'aprovado pela Meta. Quando o cliente responder, a conversa '
              'volta a ficar livre por 24h.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _campoBusca(BuildContext context, {required bool habilitado}) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final temTexto = _buscaController.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: TextField(
        controller: _buscaController,
        enabled: habilitado,
        onChanged: (_) => setState(() {}),
        textInputAction: TextInputAction.search,
        style: TextStyle(
          color: ThemeHelpers.textColor(context),
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        decoration: _decoracaoCampo(
          context,
          hint: habilitado
              ? 'Buscar pelo nome ou pelo texto'
              : 'Carregando templates…',
          prefixo: Icon(LucideIcons.search, size: 18, color: secondary),
          sufixo: temTexto && habilitado
              ? IconButton(
                  tooltip: 'Limpar busca',
                  onPressed: () => setState(_buscaController.clear),
                  icon: Icon(LucideIcons.x, size: 17, color: secondary),
                )
              : null,
        ),
      ),
    );
  }

  Widget _linhaContagem(BuildContext context, int achados) {
    final theme = Theme.of(context);
    final total = _modelos.length;
    final buscando = _buscaController.text.trim().isNotEmpty;
    final texto = buscando
        ? '$achados de $total ${total == 1 ? 'template' : 'templates'}'
        : '$total ${total == 1 ? 'template aprovado' : 'templates aprovados'}'
            ' · toque para ver a prévia';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        texto,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium?.copyWith(
          color: ThemeHelpers.textSecondaryColor(context),
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
      ),
    );
  }

  // ─── Composição (prévia + variáveis) ───────────────────────────────────────

  List<Widget> _conteudoCompor(BuildContext context, {required bool largo}) {
    final m = _escolhido!;
    final valores = <String>[
      for (var i = 0; i < m.varsNoCorpo; i++) _vars[i].text,
    ];
    final valoresCabecalho = <String>[
      for (var i = 0; i < m.varsNoCabecalho; i++) _varsCabecalho[i].text,
    ];
    if (largo) {
      return [
        _barraVoltar(context),
        _identidade(context, m),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _PreviaDoTemplate(
                modelo: m,
                valores: valores,
                valoresCabecalho: valoresCabecalho,
                painel: true,
              ),
            ),
            SizedBox(
              width: 320,
              child: _secaoVariaveis(context, m, recuoTopo: 0),
            ),
          ],
        ),
      ];
    }
    return [
      _barraVoltar(context),
      _identidade(context, m),
      _PreviaDoTemplate(
        modelo: m,
        valores: valores,
        valoresCabecalho: valoresCabecalho,
        painel: false,
      ),
      _secaoVariaveis(context, m, recuoTopo: 16),
    ];
  }

  /// Voltar é neutro: o tema pinta TextButton de vermelho.
  Widget _barraVoltar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 16, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _enviando ? null : _voltarParaLista,
          icon: const Icon(LucideIcons.chevronLeft, size: 18),
          label: const Text(
            'Voltar para a lista',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          style: TextButton.styleFrom(
            foregroundColor: ThemeHelpers.textSecondaryColor(context),
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _identidade(BuildContext context, _Modelo m) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            m.nomeLegivel,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w800,
              fontSize: 19,
              letterSpacing: -0.3,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            m.descricao,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _secaoVariaveis(
    BuildContext context,
    _Modelo m, {
    required double recuoTopo,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final nCabecalho = m.varsNoCabecalho;
    final nCorpo = m.varsNoCorpo;
    final total = nCabecalho + nCorpo;
    if (total == 0) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16, recuoTopo, 16, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                LucideIcons.circleCheck,
                size: 16,
                color: _tintaVerde(isDark),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Este template não tem variáveis: sai exatamente como na '
                'prévia.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textColor(context),
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final faltam = _faltam;
    final String resumo;
    if (total == 1) {
      resumo = faltam == 0 ? 'Preenchida' : 'Falta preencher';
    } else if (faltam == 0) {
      resumo = 'Todas preenchidas';
    } else {
      resumo = faltam == 1 ? 'Falta 1 de $total' : 'Faltam $faltam de $total';
    }
    // Como o web: a ajuda diz de onde vieram os valores já preenchidos.
    final temSugestao =
        _sugestoesDisponiveis(_ctx, _TipoVariavel.desconhecido).isNotEmpty;
    final String origem;
    if (_algumAutomatico(m)) {
      origem = ' Já preenchidas com o que a conversa sabe — confira e edite '
          'à vontade.';
    } else if (temSugestao) {
      origem = ' Sugestões da conversa abaixo de cada campo.';
    } else {
      origem = '';
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(16, recuoTopo, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  total == 1 ? 'Variável' : 'Variáveis',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  resumo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color:
                        faltam == 0 ? _tintaVerde(isDark) : _tintaAmbar(isDark),
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Na ordem em que aparecem na mensagem; a prévia acompanha o que '
            'você digita.$origem A Meta recusa o envio se faltar alguma.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondary,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
          if (nCabecalho > 0) ...[
            const SizedBox(height: 14),
            _tituloDoGrupo(context, 'Cabeçalho'),
            for (var i = 0; i < nCabecalho; i++) ...[
              const SizedBox(height: 8),
              _campoVariavel(
                context,
                m,
                cabecalho: true,
                i: i,
                ultimo: nCorpo == 0 && i == nCabecalho - 1,
              ),
            ],
          ],
          if (nCorpo > 0) ...[
            if (nCabecalho > 0) ...[
              const SizedBox(height: 14),
              _tituloDoGrupo(context, 'Corpo'),
            ],
            for (var i = 0; i < nCorpo; i++) ...[
              SizedBox(height: nCabecalho > 0 ? 8 : 10),
              _campoVariavel(
                context,
                m,
                cabecalho: false,
                i: i,
                ultimo: i == nCorpo - 1,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _tituloDoGrupo(BuildContext context, String titulo) {
    final theme = Theme.of(context);
    return Text(
      titulo.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelSmall?.copyWith(
        color: ThemeHelpers.textSecondaryColor(context),
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
        fontSize: 11,
      ),
    );
  }

  Widget _campoVariavel(
    BuildContext context,
    _Modelo m, {
    required bool cabecalho,
    required int i,
    required bool ultimo,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = (cabecalho ? _varsCabecalho : _vars)[i];
    final exemplo = cabecalho ? m.exemploDoCabecalho(i) : m.exemploDoCorpo(i);
    final leitura = _lerVariavel(
      exemplo,
      cabecalho ? m.textoCabecalho : m.textoCorpo,
      i,
    );
    final sugestoes = _sugestoesDisponiveis(_ctx, leitura.tipo);
    final preenchida = c.text.trim().isNotEmpty;
    final ex = (exemplo ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: c,
          enabled: !_enviando,
          onChanged: (_) => _aoDigitar(cabecalho: cabecalho, i: i),
          textInputAction:
              ultimo ? TextInputAction.done : TextInputAction.next,
          textCapitalization: TextCapitalization.sentences,
          maxLines: 1,
          style: TextStyle(
            color: ThemeHelpers.textColor(context),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          decoration: _decoracaoCampo(
            context,
            hint: ex.isNotEmpty ? 'ex.: $ex' : 'Valor da variável ${i + 1}',
            prefixo: Padding(
              padding: const EdgeInsets.only(left: 12, right: 8),
              child: Text(
                '{{${i + 1}}}',
                style: TextStyle(
                  color:
                      preenchida ? _tintaVerde(isDark) : _tintaAmbar(isDark),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            prefixoConstraints:
                const BoxConstraints(minWidth: 0, minHeight: 0),
            sufixo: preenchida
                ? Icon(LucideIcons.check, size: 17, color: _tintaVerde(isDark))
                : null,
          ),
        ),
        if (sugestoes.isNotEmpty)
          _linhaDeSugestoes(
            context,
            sugestoes,
            valorAtual: c.text,
            aoEscolher: (valor) =>
                _usarSugestao(cabecalho: cabecalho, i: i, valor: valor),
          ),
      ],
    );
  }

  /// O que a conversa sabe, sob o campo — links de texto, sem pílula.
  Widget _linhaDeSugestoes(
    BuildContext context,
    List<_Sugestao> sugestoes, {
    required String valorAtual,
    required ValueChanged<String> aoEscolher,
  }) {
    final theme = Theme.of(context);
    final atual = valorAtual.trim();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 2, right: 2),
                child: Text(
                  'Usar',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              for (final s in sugestoes)
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                  child: _LinkDeSugestao(
                    sugestao: s,
                    ativa: atual == s.valor,
                    onTap: _enviando ? null : () => aoEscolher(s.valor),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ─── Digitação manual ──────────────────────────────────────────────────────

  List<Widget> _conteudoManual(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final String explicacao;
    switch (_motivoManual) {
      case _MotivoManual.semPermissao:
        explicacao = 'Sua conta não vê a lista de templates: ela pede a '
            'permissão de configurar o WhatsApp. Digite o nome exato de um '
            'template aprovado na Meta — o envio funciona igual, só sem '
            'prévia.';
      case _MotivoManual.listaVazia:
        explicacao = 'A lista veio sem templates aprovados. Se você sabe o '
            'nome exato de um aprovado na Meta, digite aqui — sem a lista, '
            'não há prévia.';
      case _MotivoManual.falhaNaLista:
        explicacao = 'A lista de templates não carregou. Digite o nome exato '
            'de um template aprovado na Meta — sem a lista, não há prévia.';
    }
    final rotuloEstilo = theme.textTheme.titleSmall?.copyWith(
      color: ThemeHelpers.textColor(context),
      fontWeight: FontWeight.w800,
      fontSize: 15,
    );
    final ajudaEstilo = theme.textTheme.bodySmall?.copyWith(
      color: secondary,
      fontWeight: FontWeight.w500,
      height: 1.4,
    );
    return [
      _notaManual(context, explicacao),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nome do template', style: rotuloEstilo),
            const SizedBox(height: 6),
            TextField(
              controller: _nomeController,
              enabled: !_enviando,
              onChanged: (_) => setState(() => _erroEnvio = null),
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              decoration: _decoracaoCampo(
                context,
                hint: 'ex.: boas_vindas',
                prefixo:
                    Icon(LucideIcons.fileText, size: 17, color: secondary),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Igual ao aprovado na Meta: minúsculas e sublinhado, sem espaço.',
              style: ajudaEstilo,
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Variáveis',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: rotuloEstilo,
              ),
            ),
            TextButton.icon(
              onPressed: _enviando ? null : _adicionarVariavelManual,
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('Adicionar', maxLines: 1),
              style: TextButton.styleFrom(
                foregroundColor: ThemeHelpers.textColor(context),
                minimumSize: const Size(0, 40),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: Text(
          _varsManuais.isEmpty
              ? 'Opcional. Se o template tiver {{1}}, {{2}}…, adicione os '
                  'valores na mesma ordem.'
              : 'Na ordem do texto do template: {{1}}, {{2}}…',
          style: ajudaEstilo,
        ),
      ),
      for (var i = 0; i < _varsManuais.length; i++)
        KeyedSubtree(
          key: ObjectKey(_varsManuais[i]),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 6, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _varsManuais[i],
                    enabled: !_enviando,
                    onChanged: (_) => setState(() => _erroEnvio = null),
                    maxLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(
                      color: ThemeHelpers.textColor(context),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: _decoracaoCampo(
                      context,
                      hint: 'Valor da variável ${i + 1}',
                      prefixo: Padding(
                        padding: const EdgeInsets.only(left: 12, right: 8),
                        child: Text(
                          '{{${i + 1}}}',
                          style: TextStyle(
                            color: secondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      prefixoConstraints:
                          const BoxConstraints(minWidth: 0, minHeight: 0),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remover variável',
                  onPressed:
                      _enviando ? null : () => _removerVariavelManual(i),
                  icon: Icon(LucideIcons.trash2, size: 17, color: secondary),
                ),
              ],
            ),
          ),
        ),
      if (_motivoManual == _MotivoManual.falhaNaLista)
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 14, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _enviando ? null : _carregar,
              icon: const Icon(LucideIcons.rotateCw, size: 16),
              label: const Text(
                'Carregar a lista de novo',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: TextButton.styleFrom(
                foregroundColor: secondary,
                minimumSize: const Size(0, 40),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
          ),
        ),
    ];
  }

  /// Aviso tonal, sem faixa lateral.
  Widget _notaManual(BuildContext context, String texto) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final info = isDark
        ? AppColors.message.infoTextDarkMode
        : AppColors.message.infoText;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: info.withValues(alpha: isDark ? 0.14 : 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(LucideIcons.info, size: 16, color: info),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              texto,
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Rodapé ────────────────────────────────────────────────────────────────

  /// Estado em palavras (o motivo da trava, o ok ou a recusa) + Enviar verde.
  Widget _rodape(
    BuildContext context, {
    required bool compacto,
    required bool fixo,
    required bool largo,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mq = MediaQuery.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    IconData iconeEstado;
    Color tintaEstado;
    String textoEstado;
    String rotuloBotao;
    IconData iconeBotao;
    if (_fase == _Fase.compor) {
      final n = _escolhido!.totalVars;
      final faltam = _faltam;
      if (faltam > 0) {
        iconeEstado = LucideIcons.lock;
        tintaEstado = _tintaAmbar(isDark);
        if (faltam == n) {
          textoEstado = n == 1
              ? 'Preencha a variável para liberar o envio.'
              : 'Preencha as $n variáveis para liberar o envio.';
        } else {
          textoEstado = faltam == 1
              ? 'Falta 1 de $n variáveis para liberar o envio.'
              : 'Faltam $faltam de $n variáveis para liberar o envio.';
        }
        rotuloBotao =
            faltam == 1 ? 'Falta 1 variável' : 'Faltam $faltam variáveis';
        iconeBotao = LucideIcons.lock;
      } else {
        iconeEstado = LucideIcons.circleCheck;
        tintaEstado = _tintaVerde(isDark);
        textoEstado = n == 0
            ? 'Sem variáveis: sai exatamente como na prévia.'
            : 'Tudo preenchido. Confira a prévia e envie.';
        rotuloBotao = 'Enviar template';
        iconeBotao = LucideIcons.sendHorizontal;
      }
    } else if (_nomeController.text.trim().isEmpty) {
      iconeEstado = LucideIcons.lock;
      tintaEstado = _tintaAmbar(isDark);
      textoEstado = 'Digite o nome do template para liberar o envio.';
      rotuloBotao = 'Digite o nome';
      iconeBotao = LucideIcons.lock;
    } else {
      iconeEstado = LucideIcons.info;
      tintaEstado = secondary;
      textoEstado = 'O nome precisa ser igual ao aprovado na Meta.';
      rotuloBotao = 'Enviar template';
      iconeBotao = LucideIcons.sendHorizontal;
    }
    final erro = _erroEnvio;
    if (erro != null) {
      iconeEstado = LucideIcons.circleAlert;
      tintaEstado = _tintaErro(isDark);
      textoEstado = 'Não foi enviado. $erro';
    }
    if (_enviando) rotuloBotao = 'Enviando…';
    final mostrarEstado = !compacto || erro != null;

    final estado = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(iconeEstado, size: 15, color: tintaEstado),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            textoEstado,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textColor(context).withValues(alpha: 0.9),
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ),
      ],
    );

    final botao = SizedBox(
      height: compacto ? 44 : 50,
      child: FilledButton(
        onPressed: _podeEnviar ? _enviar : null,
        style: FilledButton.styleFrom(
          backgroundColor: _verde(isDark),
          foregroundColor: ThemeHelpers.onPrimaryColor(context),
          disabledBackgroundColor: _campo(isDark),
          disabledForegroundColor: secondary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_enviando)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: secondary,
                  ),
                )
              else
                Icon(iconeBotao, size: 17),
              const SizedBox(width: 8),
              Text(rotuloBotao, maxLines: 1, softWrap: false),
            ],
          ),
        ),
      ),
    );

    final Widget conteudo;
    if (largo) {
      conteudo = Row(
        children: [
          Expanded(child: mostrarEstado ? estado : const SizedBox.shrink()),
          const SizedBox(width: 16),
          SizedBox(width: 260, child: botao),
        ],
      );
    } else {
      conteudo = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (mostrarEstado) ...[
            estado,
            SizedBox(height: compacto ? 8 : 10),
          ],
          botao,
        ],
      );
    }

    return Container(
      decoration: fixo
          ? BoxDecoration(
              color: ThemeHelpers.backgroundColor(context),
              border: Border(
                top: BorderSide(color: ThemeHelpers.borderLightColor(context)),
              ),
            )
          : null,
      padding: EdgeInsets.fromLTRB(
        16,
        compacto ? 8 : 12,
        16,
        (compacto ? 8 : 12) + mq.padding.bottom,
      ),
      child: conteudo,
    );
  }

  // ─── Peças ─────────────────────────────────────────────────────────────────

  /// Campo filled da casa, foco no verde do canal.
  InputDecoration _decoracaoCampo(
    BuildContext context, {
    required String hint,
    Widget? prefixo,
    BoxConstraints? prefixoConstraints,
    Widget? sufixo,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borda = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: ThemeHelpers.borderLightColor(context)),
    );
    return InputDecoration(
      hintText: hint,
      hintMaxLines: 1,
      hintStyle: TextStyle(
        color: ThemeHelpers.textSecondaryColor(context).withValues(alpha: 0.8),
        fontWeight: FontWeight.w500,
        fontSize: 14,
      ),
      prefixIcon: prefixo,
      prefixIconConstraints: prefixoConstraints,
      suffixIcon: sufixo,
      filled: true,
      fillColor: _campo(isDark),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: borda,
      enabledBorder: borda,
      disabledBorder: borda,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _verde(isDark), width: 1.4),
      ),
    );
  }

  /// Ação de apoio: contorno neutro (nunca o vermelho do tema).
  Widget _botaoNeutro(
    BuildContext context, {
    required IconData icone,
    required String rotulo,
    required VoidCallback? onPressed,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: ThemeHelpers.textColor(context),
        side: BorderSide(
          color: isDark
              ? ThemeHelpers.textSecondaryColor(context).withValues(alpha: 0.30)
              : ThemeHelpers.borderColor(context),
        ),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 16),
            const SizedBox(width: 8),
            Text(rotulo, maxLines: 1, softWrap: false),
          ],
        ),
      ),
    );
  }
}

// ─── Linhas da lista ─────────────────────────────────────────────────────────

/// Linha flush com filete (inset 16): nome legível, categoria · idioma ·
/// variáveis, e o trecho do corpo em até 2 linhas.
class _LinhaDoModelo extends StatelessWidget {
  final _Modelo modelo;
  final bool ultima;
  final bool jaEscolhido;
  final VoidCallback onTap;

  const _LinhaDoModelo({
    required this.modelo,
    required this.ultima,
    required this.jaEscolhido,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final textColor = ThemeHelpers.textColor(context);
    final trecho = modelo.trecho;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(0, 13, 12, 13),
          decoration: BoxDecoration(
            border: ultima
                ? null
                : Border(
                    bottom: BorderSide(
                      color: ThemeHelpers.borderLightColor(context),
                    ),
                  ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      modelo.nomeLegivel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      modelo.descricao,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    if (trecho.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        trecho,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: textColor.withValues(alpha: 0.72),
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  jaEscolhido
                      ? LucideIcons.circleCheck
                      : LucideIcons.chevronRight,
                  size: 18,
                  color: jaEscolhido ? _tintaVerde(isDark) : secondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Esqueleto com a forma da linha: nome, meta e 2 linhas de trecho.
class _LinhaEsqueleto extends StatelessWidget {
  final bool ultima;

  const _LinhaEsqueleto({required this.ultima});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(0, 14, 16, 14),
        decoration: BoxDecoration(
          border: ultima
              ? null
              : Border(
                  bottom: BorderSide(
                    color: ThemeHelpers.borderLightColor(context),
                  ),
                ),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FractionallySizedBox(
              widthFactor: 0.55,
              child: SkeletonBox(height: 15, borderRadius: 5),
            ),
            SizedBox(height: 7),
            FractionallySizedBox(
              widthFactor: 0.38,
              child: SkeletonBox(height: 11, borderRadius: 4),
            ),
            SizedBox(height: 9),
            FractionallySizedBox(
              widthFactor: 0.92,
              child: SkeletonBox(height: 12, borderRadius: 4),
            ),
            SizedBox(height: 5),
            FractionallySizedBox(
              widthFactor: 0.7,
              child: SkeletonBox(height: 12, borderRadius: 4),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vazio que ensina: o que aparece aqui e o que fazer.
class _EstadoVazio extends StatelessWidget {
  final IconData icone;
  final String titulo;
  final String texto;
  final Widget? acao;

  const _EstadoVazio({
    required this.icone,
    required this.titulo,
    required this.texto,
    this.acao,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final acao = this.acao;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: _campo(isDark),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ThemeHelpers.borderLightColor(context)),
            ),
            child: Icon(icone, size: 22, color: secondary),
          ),
          const SizedBox(height: 14),
          Text(
            titulo,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              color: ThemeHelpers.textColor(context),
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            texto,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          if (acao != null) ...[
            const SizedBox(height: 16),
            acao,
          ],
        ],
      ),
    );
  }
}

// ─── Prévia ──────────────────────────────────────────────────────────────────

/// O "papel" da conversa com a bolha do template. Faixa de largura inteira
/// no celular; painel ao lado das variáveis em tela larga.
class _PreviaDoTemplate extends StatelessWidget {
  final _Modelo modelo;
  final List<String> valores;
  final List<String> valoresCabecalho;
  final bool painel;

  const _PreviaDoTemplate({
    required this.modelo,
    required this.valores,
    required this.valoresCabecalho,
    required this.painel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final filete = ThemeHelpers.borderLightColor(context);
    return Container(
      margin: painel ? const EdgeInsets.fromLTRB(16, 0, 8, 0) : EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: _papel(isDark),
        borderRadius: painel ? BorderRadius.circular(16) : null,
        border: painel
            ? Border.all(color: filete)
            : Border(
                top: BorderSide(color: filete),
                bottom: BorderSide(color: filete),
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(LucideIcons.eye, size: 14, color: secondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Prévia: é assim que o cliente recebe',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _BolhaDaPrevia(
            modelo: modelo,
            valores: valores,
            valoresCabecalho: valoresCabecalho,
          ),
          if (modelo.totalVars > 0) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                _ItemLegenda(
                  cor: _tintaAmbar(isDark),
                  rotulo: 'falta preencher',
                ),
                _ItemLegenda(cor: _verde(isDark), rotulo: 'preenchida'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A bolha de saída de `whatsapp_message_bubble.dart` (verde suave sólido,
/// filete verde, cauda embaixo à direita, hora + ✓✓), com os botões do
/// template abaixo, como no WhatsApp.
class _BolhaDaPrevia extends StatelessWidget {
  final _Modelo modelo;
  final List<String> valores;
  final List<String> valoresCabecalho;

  const _BolhaDaPrevia({
    required this.modelo,
    required this.valores,
    required this.valoresCabecalho,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final verde = _verde(isDark);
    final corBolha = isDark
        ? Color.alphaBlend(
            verde.withValues(alpha: 0.30),
            AppColors.background.cardBackgroundDarkMode,
          )
        : Color.alphaBlend(verde.withValues(alpha: 0.16), Colors.white);
    final corFilete = verde.withValues(alpha: isDark ? 0.26 : 0.22);
    final textColor = ThemeHelpers.textColor(context);
    final metaColor =
        ThemeHelpers.textSecondaryColor(context).withValues(alpha: 0.85);
    final base = (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      color: textColor,
      fontSize: 15,
      height: 1.35,
      letterSpacing: -0.1,
    );
    final marcas = _MarcasDaPrevia.de(context);

    final agora = DateTime.now();
    final hora = '${agora.hour.toString().padLeft(2, '0')}:'
        '${agora.minute.toString().padLeft(2, '0')}';

    final textoCorpo = modelo.textoCorpo;
    final corpo =
        textoCorpo != null && textoCorpo.trim().isNotEmpty ? textoCorpo : null;
    final textoCabecalho = modelo.textoCabecalho;
    final cabecalho = modelo.cabecalhoEmTexto &&
            textoCabecalho != null &&
            textoCabecalho.trim().isNotEmpty
        ? textoCabecalho
        : null;
    final textoRodape = modelo.textoRodape;
    final rodape = textoRodape != null && textoRodape.trim().isNotEmpty
        ? textoRodape.trim()
        : null;
    final midia = modelo.cabecalhoDeMidia;

    return LayoutBuilder(
      builder: (context, constraints) {
        final largura = math.min(constraints.maxWidth * 0.86, 340.0);
        return Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: largura,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: midia
                      ? const EdgeInsets.fromLTRB(4, 4, 4, 6)
                      : const EdgeInsets.fromLTRB(12, 8, 12, 6),
                  decoration: BoxDecoration(
                    color: corBolha,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(18),
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(4),
                    ),
                    border: Border.all(color: corFilete, width: 0.8),
                    boxShadow: isDark
                        ? null
                        : ThemeHelpers.cardShadow(context, strength: 0.35),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (midia)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _MidiaDoCabecalho(
                            formato: modelo.formatoCabecalho ?? '',
                          ),
                        ),
                      Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: midia ? 8 : 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (cabecalho != null) ...[
                              Text.rich(
                                TextSpan(
                                  children: _spansDoTexto(
                                    cabecalho,
                                    valoresCabecalho,
                                    base.copyWith(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15.5,
                                    ),
                                    marcas,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                            ],
                            if (corpo != null)
                              Text.rich(
                                TextSpan(
                                  children: _spansDoTexto(
                                    corpo,
                                    valores,
                                    base,
                                    marcas,
                                  ),
                                ),
                              )
                            else if (modelo.semEstrutura)
                              Text(
                                'A Meta não devolveu o texto deste template. '
                                'O envio funciona, mas a prévia não pode ser '
                                'montada.',
                                style: base.copyWith(
                                  color: metaColor,
                                  fontSize: 13.5,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            if (rodape != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                rodape,
                                style: base.copyWith(
                                  color: metaColor,
                                  fontSize: 12.5,
                                  height: 1.3,
                                ),
                              ),
                            ],
                            const SizedBox(height: 3),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      hora,
                                      maxLines: 1,
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        color: metaColor,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w500,
                                        height: 1.2,
                                      ),
                                    ),
                                    const SizedBox(width: 3.5),
                                    Icon(
                                      LucideIcons.checkCheck,
                                      size: 13,
                                      color: metaColor,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                for (final b in modelo.botoes) ...[
                  const SizedBox(height: 3),
                  _BotaoDaPrevia(botao: b, cor: corBolha, filete: corFilete),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Cabeçalho de mídia: a Meta guarda a imagem/vídeo/documento de exemplo,
/// que a API não devolve — a prévia diz o que vai ali.
class _MidiaDoCabecalho extends StatelessWidget {
  final String formato;

  const _MidiaDoCabecalho({required this.formato});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    IconData icone = LucideIcons.image;
    if (formato == 'VIDEO') {
      icone = LucideIcons.video;
    } else if (formato == 'DOCUMENT') {
      icone = LucideIcons.fileText;
    } else if (formato == 'LOCATION') {
      icone = LucideIcons.mapPin;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 1.91,
        child: Container(
          color: _campo(isDark),
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icone, size: 26, color: secondary),
              const SizedBox(height: 6),
              Text(
                '${_rotuloMidia(formato)} do template',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: secondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botão do template sob a bolha: mesma cor da bolha, texto em azul de link.
class _BotaoDaPrevia extends StatelessWidget {
  final WhatsAppTemplateButton botao;
  final Color cor;
  final Color filete;

  const _BotaoDaPrevia({
    required this.botao,
    required this.cor,
    required this.filete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final link = isDark
        ? AppColors.message.infoTextDarkMode
        : AppColors.message.infoText;
    IconData icone = LucideIcons.reply;
    if (botao.type == 'URL') {
      icone = LucideIcons.externalLink;
    } else if (botao.type == 'PHONE_NUMBER') {
      icone = LucideIcons.phone;
    } else if (botao.type == 'COPY_CODE' || botao.type == 'OTP') {
      icone = LucideIcons.copy;
    }
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: cor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: filete, width: 0.8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icone, size: 15, color: link),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              botao.text.isEmpty ? 'Botão' : botao.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: link,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemLegenda extends StatelessWidget {
  final Color cor;
  final String rotulo;

  const _ItemLegenda({required this.cor, required this.rotulo});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: cor.withValues(alpha: 0.30),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: cor),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          rotulo,
          maxLines: 1,
          style: theme.textTheme.labelSmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            fontWeight: FontWeight.w600,
            fontSize: 11.5,
          ),
        ),
      ],
    );
  }
}

/// Realce das variáveis na prévia: preenchida = texto normal com marca verde
/// leve; vazia = "{{n}}" em âmbar legível com sublinhado tracejado.
class _MarcasDaPrevia {
  final TextStyle cheia;
  final TextStyle vazia;

  const _MarcasDaPrevia({required this.cheia, required this.vazia});

  factory _MarcasDaPrevia.de(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ambar = _tintaAmbar(isDark);
    final ambarToken = isDark
        ? AppColors.message.warningTextDarkMode
        : AppColors.message.warningText;
    return _MarcasDaPrevia(
      cheia: TextStyle(
        fontWeight: FontWeight.w600,
        backgroundColor:
            _verde(isDark).withValues(alpha: isDark ? 0.30 : 0.22),
      ),
      vazia: TextStyle(
        color: ambar,
        fontWeight: FontWeight.w800,
        backgroundColor: ambarToken.withValues(alpha: isDark ? 0.20 : 0.16),
        decoration: TextDecoration.underline,
        decorationStyle: TextDecorationStyle.dashed,
        decorationColor: ambar,
      ),
    );
  }
}

/// {{n}} vira variável (valor digitado ou "{{n}}" realçado); *negrito*,
/// _itálico_ e ~riscado~ viram estilo, como no WhatsApp (só em borda de
/// palavra: "minha_pagina_nova" fica como está).
final RegExp _reMarcacao = RegExp(
  r'\{\{\s*(\d+)\s*\}\}'
  r'|(?<!\w)\*([^*\n]+)\*(?!\w)'
  r'|(?<!\w)_([^_\n]+)_(?!\w)'
  r'|(?<!\w)~([^~\n]+)~(?!\w)',
);

List<InlineSpan> _spansDoTexto(
  String texto,
  List<String> valores,
  TextStyle base,
  _MarcasDaPrevia marcas,
) {
  final spans = <InlineSpan>[];
  var ultimo = 0;
  for (final m in _reMarcacao.allMatches(texto)) {
    if (m.start > ultimo) {
      spans.add(TextSpan(text: texto.substring(ultimo, m.start), style: base));
    }
    final numero = m.group(1);
    if (numero != null) {
      final indice = (int.tryParse(numero) ?? 0) - 1;
      final valor = indice >= 0 && indice < valores.length
          ? valores[indice].trim()
          : '';
      spans.add(
        TextSpan(
          text: valor.isNotEmpty ? valor : '{{$numero}}',
          style: base.merge(valor.isNotEmpty ? marcas.cheia : marcas.vazia),
        ),
      );
    } else if (m.group(2) != null) {
      spans.addAll(_spansDoTexto(
        m.group(2)!,
        valores,
        base.copyWith(fontWeight: FontWeight.w700),
        marcas,
      ));
    } else if (m.group(3) != null) {
      spans.addAll(_spansDoTexto(
        m.group(3)!,
        valores,
        base.copyWith(fontStyle: FontStyle.italic),
        marcas,
      ));
    } else if (m.group(4) != null) {
      spans.addAll(_spansDoTexto(
        m.group(4)!,
        valores,
        base.copyWith(decoration: TextDecoration.lineThrough),
        marcas,
      ));
    }
    ultimo = m.end;
  }
  if (ultimo < texto.length) {
    spans.add(TextSpan(text: texto.substring(ultimo), style: base));
  }
  return spans;
}

// ─── Template do catálogo ────────────────────────────────────────────────────

/// Template aprovado + a busca pronta. A estrutura (cabeçalho, corpo, rodapé,
/// botões e exemplos das variáveis) vem do próprio [WhatsAppTemplate].
class _Modelo {
  final WhatsAppTemplate t;

  /// Nome, idioma, categoria e textos, minúsculos e sem acento.
  final String busca;

  const _Modelo._(this.t, this.busca);

  factory _Modelo.de(WhatsAppTemplate t) {
    final busca = _normalizar(
      [
        t.name,
        _nomeLegivel(t.name),
        t.language,
        _idioma(t.language),
        t.category ?? '',
        _categoria(t.category),
        t.header?.text ?? '',
        t.body?.text ?? '',
        t.footer?.text ?? '',
      ].join(' '),
    );
    return _Modelo._(t, busca);
  }

  /// Nome + idioma: a Meta aceita o mesmo nome em idiomas diferentes.
  String get chave => '${t.name}|${t.language}';

  bool get cabecalhoEmTexto => t.hasTextHeader;
  bool get cabecalhoDeMidia => t.hasMediaHeader;
  String? get formatoCabecalho => t.header?.format;
  String? get textoCabecalho => t.header?.text;
  String? get textoCorpo => t.body?.text;
  String? get textoRodape => t.footer?.text;
  List<WhatsAppTemplateButton> get botoes => t.buttons;

  int get varsNoCabecalho => t.headerVariables;
  int get varsNoCorpo => t.bodyVariables;
  int get totalVars => varsNoCabecalho + varsNoCorpo;

  String? exemploDoCabecalho(int i) =>
      _naPosicao(t.header?.exampleHeaderText, i);

  String? exemploDoCorpo(int i) => _naPosicao(t.body?.exampleBodyText, i);

  bool get semEstrutura =>
      t.header == null &&
      (textoCorpo ?? '').trim().isEmpty &&
      (textoRodape ?? '').trim().isEmpty &&
      botoes.isEmpty;

  String get nomeLegivel => _nomeLegivel(t.name);

  /// Corpo sem marcação, numa linha só (a lista mostra até 2).
  String get trecho => (textoCorpo ?? '')
      .replaceAll(RegExp(r'[*_~]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String get descricao {
    final categoria = _categoria(t.category);
    return [
      if (categoria.isNotEmpty) categoria,
      _idioma(t.language),
      totalVars == 0 ? 'sem variáveis' : _variaveis(totalVars),
      if (cabecalhoDeMidia)
        'com ${_rotuloMidia(formatoCabecalho ?? '').toLowerCase()}',
    ].join(' · ');
  }
}

String? _naPosicao(List<String>? lista, int i) =>
    lista != null && i >= 0 && i < lista.length ? lista[i] : null;

// ─── Preenchimento automático (porte de `whatsappTemplateVariaveis.ts`) ──────
//
// O exemplo da Meta ("João", "12345") é pista, não semântica: "Bauru" também
// é só letras e "250000" também é só dígitos. O valor só entra SOZINHO quando
// o exemplo e o texto logo antes da variável concordam ("Olá, {{1}}!" /
// "no imóvel {{2}}"); sem as duas, o campo fica vazio e só as sugestões
// aparecem.

enum _TipoVariavel { nome, codigo, desconhecido }

class _Leitura {
  final _TipoVariavel tipo;

  /// Exemplo e texto concordam: só aí o campo é preenchido sozinho.
  final bool forte;

  const _Leitura(this.tipo, this.forte);
}

class _Sugestao {
  final String rotulo;
  final String valor;

  const _Sugestao(this.rotulo, this.valor);
}

/// O que a conversa sabe do cliente; tudo opcional.
class _ContextoVariaveis {
  final String? nomeDoContato;
  final String? codigoDoImovel;
  final String? tituloDoImovel;

  const _ContextoVariaveis({
    this.nomeDoContato,
    this.codigoDoImovel,
    this.tituloDoImovel,
  });

  /// Como o web: o nome da conversa vale se dele sai um primeiro nome; senão
  /// (apelido só de emoji ou ponto), o nome do cadastro.
  factory _ContextoVariaveis.de({
    String? nomeDoContato,
    String? nomeDoCadastro,
    String? codigoDoImovel,
    String? tituloDoImovel,
  }) {
    final contato = (nomeDoContato ?? '').trim();
    final cadastro = (nomeDoCadastro ?? '').trim();
    final contatoServe = _primeiroNome(contato).isNotEmpty;
    final nome = contatoServe || cadastro.isEmpty ? contato : cadastro;
    final codigo = (codigoDoImovel ?? '').trim();
    final titulo = (tituloDoImovel ?? '').trim();
    return _ContextoVariaveis(
      nomeDoContato: nome.isEmpty ? null : nome,
      codigoDoImovel: codigo.isEmpty ? null : codigo,
      tituloDoImovel: titulo.isEmpty ? null : titulo,
    );
  }

  /// Imóvel que chegou do card; o que já veio de quem abriu o sheet vale.
  _ContextoVariaveis comImovel({String? codigo, String? titulo}) {
    return _ContextoVariaveis(
      nomeDoContato: nomeDoContato,
      codigoDoImovel: codigoDoImovel ?? codigo,
      tituloDoImovel: tituloDoImovel ?? titulo,
    );
  }
}

/// Palavras que ficam minúsculas dentro de um nome próprio.
const _conectivos = {
  'da',
  'de',
  'do',
  'das',
  'dos',
  'e',
  'di',
  'del',
  'van',
  'von',
};

final RegExp _reEspacos = RegExp(r'\s+');
final RegExp _reSoDigitos = RegExp(r'^\d+$');
final RegExp _reSoLetras = RegExp(r"^[\p{L}][\p{L}'’.-]*$", unicode: true);
final RegExp _reComecaMaiuscula = RegExp(r'^\p{Lu}', unicode: true);

/// "João" / "Maria Silva" → nome; "12345" → código; ausente ou ambíguo
/// ("Rua 7", "AP-12") → desconhecido.
_TipoVariavel _tipoDoExemplo(String? exemplo) {
  final e = (exemplo ?? '').trim();
  if (e.isEmpty) return _TipoVariavel.desconhecido;
  if (_reSoDigitos.hasMatch(e)) return _TipoVariavel.codigo;
  final palavras = e.split(_reEspacos);
  if (palavras.length > 4) return _TipoVariavel.desconhecido;
  if (!palavras.every(_reSoLetras.hasMatch)) {
    return _TipoVariavel.desconhecido;
  }
  if (palavras.length == 1) return _TipoVariavel.nome;
  final proprio = palavras.every(
    (p) =>
        _conectivos.contains(p.toLowerCase()) ||
        _reComecaMaiuscula.hasMatch(p),
  );
  return proprio ? _TipoVariavel.nome : _TipoVariavel.desconhecido;
}

final RegExp _reSaudacaoAntes = RegExp(
  r'(?:^|\s)(?:ol[áa]|oi|bom dia|boa tarde|boa noite|prezad[oa]s?|car[oa]s?'
  r'|tudo bem)[\s,!]*$',
  caseSensitive: false,
  unicode: true,
);

/// "imóvel" logo antes da variável anuncia o código dele sozinho.
const _chaveImovel = {'imóvel', 'imovel'};

/// Chaves genéricas de código: só valem com "imóvel" no mesmo trecho (senão
/// "referência {{1}}" de cobrança receberia o código do imóvel).
const _chaveCodigo = {
  'código',
  'codigo',
  'cód',
  'cod',
  'ref',
  'referência',
  'referencia',
};

/// Ligações toleradas entre a palavra-chave e a variável: "do imóvel nº:".
const _enchimentoCodigo = {
  'do',
  'da',
  'de',
  'o',
  'a',
  'no',
  'na',
  'n',
  'nº',
  'n°',
  'no.',
  'num',
  'número',
  'numero',
};

/// Trecho logo antes da primeira ocorrência de {{n}} (sem marcação).
String? _textoAntesDe(String? texto, int indice) {
  if (texto == null || texto.isEmpty) return null;
  final pos = texto.indexOf('{{${indice + 1}}}');
  if (pos < 0) return null;
  return texto
      .substring(math.max(0, pos - 60), pos)
      .replaceAll(RegExp(r'[*_~]'), '');
}

/// Vocativo depois de saudação é NOME; "imóvel" (ou "código"/"ref" com
/// "imóvel" no trecho) logo antes é CÓDIGO. Sem isso, nada.
_TipoVariavel? _evidenciaNoTexto(String? texto, int indice) {
  final antes = _textoAntesDe(texto, indice);
  if (antes == null) return null;
  if (_reSaudacaoAntes.hasMatch(antes)) return _TipoVariavel.nome;
  final tokens = antes
      .toLowerCase()
      .split(RegExp(r'[\s:#,]+'))
      .where((t) => t.isNotEmpty)
      .toList();
  while (tokens.isNotEmpty && _enchimentoCodigo.contains(tokens.last)) {
    tokens.removeLast();
  }
  String semPonto(String t) => t.replaceAll(RegExp(r'\.+$'), '');
  if (tokens.isEmpty) return null;
  final ultimo = semPonto(tokens.last);
  if (ultimo.isEmpty) return null;
  if (_chaveImovel.contains(ultimo)) return _TipoVariavel.codigo;
  if (_chaveCodigo.contains(ultimo) &&
      tokens.any((t) => _chaveImovel.contains(semPonto(t)))) {
    return _TipoVariavel.codigo;
  }
  return null;
}

_Leitura _lerVariavel(String? exemplo, String? texto, int indice) {
  final doExemplo = _tipoDoExemplo(exemplo);
  final doTexto = _evidenciaNoTexto(texto, indice);
  final tipo = doExemplo != _TipoVariavel.desconhecido
      ? doExemplo
      : (doTexto ?? _TipoVariavel.desconhecido);
  final forte = doExemplo != _TipoVariavel.desconhecido && doTexto == doExemplo;
  return _Leitura(tipo, forte);
}

/// Nomes que o sistema inventa quando não sabe o nome: nunca viram "Olá,
/// Cliente!".
final RegExp _reNomeGenerico = RegExp(
  r'^\s*(cliente|lead|contato|contact|usu[áa]rio|user|sem nome|desconhecido)\b',
  caseSensitive: false,
  unicode: true,
);
final RegExp _reForaDeNome = RegExp(r"[^\p{L}'’.-]", unicode: true);
final RegExp _reLetra = RegExp(r'\p{L}', unicode: true);

/// Só as palavras que são nome: sai emoji, número e pontuação solta do
/// apelido ("Rafa 🏠" → "Rafa"); nome genérico do sistema ("Cliente
/// WhatsApp 5511…") e o que não passa por nome (só dígitos) viram nada.
List<String> _palavrasDeNome(String? nome) {
  final bruto = nome ?? '';
  if (_reNomeGenerico.hasMatch(bruto)) return const [];
  final palavras = bruto
      .split(_reEspacos)
      .map((p) => p.replaceAll(_reForaDeNome, ''))
      .where(_reLetra.hasMatch)
      .toList();
  // Um nome tem letras e mais de um caractere; "R" ou "x" não é nome.
  if (palavras.isEmpty || palavras.every((p) => p.length < 2)) return const [];
  return palavras;
}

String _capitalizarPalavra(String p) => p
    .toLowerCase()
    .split('-')
    .map((s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1))
    .join('-');

/// "MARIA DA SILVA" → "Maria da Silva".
String _nomeCapitalizado(String? nome) {
  final palavras = _palavrasDeNome(nome);
  return [
    for (var i = 0; i < palavras.length; i++)
      i > 0 && _conectivos.contains(palavras[i].toLowerCase())
          ? palavras[i].toLowerCase()
          : _capitalizarPalavra(palavras[i]),
  ].join(' ');
}

/// "MARIA DA SILVA" → "Maria"; sem nome utilizável → "".
String _primeiroNome(String? nome) {
  final palavras = _palavrasDeNome(nome);
  return palavras.isEmpty ? '' : _capitalizarPalavra(palavras.first);
}

String _valorParaTipo(_TipoVariavel tipo, _ContextoVariaveis ctx) {
  return switch (tipo) {
    _TipoVariavel.nome => _primeiroNome(ctx.nomeDoContato),
    _TipoVariavel.codigo => (ctx.codigoDoImovel ?? '').trim(),
    _TipoVariavel.desconhecido => '',
  };
}

/// Valor automático: só com evidência forte e com o dado na mão.
String _sugerirValor(
  String? exemplo,
  _ContextoVariaveis ctx,
  String? texto,
  int indice,
) {
  final leitura = _lerVariavel(exemplo, texto, indice);
  return leitura.forte ? _valorParaTipo(leitura.tipo, ctx) : '';
}

/// Sugestões sob o campo, filtradas pelo tipo da variável (nome → nomes;
/// código → imóvel; desconhecido → tudo).
List<_Sugestao> _sugestoesDisponiveis(
  _ContextoVariaveis ctx,
  _TipoVariavel tipo,
) {
  final lista = <_Sugestao>[];
  if (tipo != _TipoVariavel.codigo) {
    final primeiro = _primeiroNome(ctx.nomeDoContato);
    final completo = _nomeCapitalizado(ctx.nomeDoContato);
    if (primeiro.isNotEmpty) lista.add(_Sugestao('primeiro nome', primeiro));
    if (completo.isNotEmpty && completo != primeiro) {
      lista.add(_Sugestao('nome completo', completo));
    }
  }
  if (tipo != _TipoVariavel.nome) {
    final codigo = (ctx.codigoDoImovel ?? '').trim();
    if (codigo.isNotEmpty) lista.add(_Sugestao('código do imóvel', codigo));
    final titulo = (ctx.tituloDoImovel ?? '').trim();
    if (titulo.isNotEmpty && titulo != codigo) {
      lista.add(_Sugestao('título do imóvel', titulo));
    }
  }
  return lista;
}

/// Sugestão como link de texto (valor + de onde vem) — sem pílula.
class _LinkDeSugestao extends StatelessWidget {
  final _Sugestao sugestao;
  final bool ativa;
  final VoidCallback? onTap;

  const _LinkDeSugestao({
    required this.sugestao,
    required this.ativa,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tinta = _tintaVerde(isDark);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              ativa ? LucideIcons.check : LucideIcons.cornerDownLeft,
              size: 13,
              color: tinta,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: sugestao.valor,
                      style: TextStyle(
                        color: tinta,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(
                      text: ' · ${sugestao.rotulo}',
                      style: TextStyle(
                        color: ThemeHelpers.textSecondaryColor(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Utilitários ─────────────────────────────────────────────────────────────

/// "boas_vindas_2" → "Boas vindas 2".
String _nomeLegivel(String bruto) {
  final s = bruto
      .replaceAll(RegExp(r'[_\-.]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (s.isEmpty) return 'Template sem nome';
  return s[0].toUpperCase() + s.substring(1);
}

String _chaveIdioma(String codigo) =>
    codigo.trim().replaceAll('-', '_').toLowerCase();

String _idioma(String codigo) {
  final c = _chaveIdioma(codigo);
  switch (c) {
    case '':
      return 'idioma não informado';
    case 'pt_br':
      return 'Português (BR)';
    case 'pt_pt':
      return 'Português (PT)';
    case 'en_us':
      return 'Inglês (EUA)';
    case 'en_gb':
      return 'Inglês (Reino Unido)';
    case 'es_ar':
      return 'Espanhol (Argentina)';
    case 'es_mx':
      return 'Espanhol (México)';
  }
  if (c.startsWith('pt')) return 'Português';
  if (c.startsWith('en')) return 'Inglês';
  if (c.startsWith('es')) return 'Espanhol';
  return codigo.trim();
}

String _categoria(String? bruta) {
  final c = (bruta ?? '').trim().toUpperCase();
  switch (c) {
    case '':
      return '';
    case 'MARKETING':
      return 'Marketing';
    case 'UTILITY':
      return 'Utilidade';
    case 'AUTHENTICATION':
      return 'Autenticação';
  }
  final minusculas = c.toLowerCase();
  return minusculas[0].toUpperCase() + minusculas.substring(1);
}

String _rotuloMidia(String formato) {
  switch (formato) {
    case 'IMAGE':
      return 'Imagem';
    case 'VIDEO':
      return 'Vídeo';
    case 'DOCUMENT':
      return 'Documento';
    case 'LOCATION':
      return 'Localização';
  }
  return 'Mídia';
}

String _variaveis(int n) => n == 1 ? '1 variável' : '$n variáveis';

/// Minúsculas e sem acento, para a busca achar "confirmacao" em "Confirmação".
String _normalizar(String s) {
  const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const para = 'aaaaaeeeeiiiiooooouuuucn';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = de.indexOf(ch);
    b.write(i >= 0 ? para[i] : ch);
  }
  return b.toString();
}

// ─── Tintas (só tokens) ──────────────────────────────────────────────────────

Color _verde(bool isDark) =>
    isDark ? AppColors.status.greenDarkMode : AppColors.status.green;

/// Verde de TEXTO: o token puro some no claro; puxado para a tinta do texto
/// (a mesma conta da bolha da conversa), sem hex novo.
Color _tintaVerde(bool isDark) => isDark
    ? AppColors.status.greenDarkMode
    : Color.lerp(AppColors.message.successText, AppColors.text.text, 0.35)!;

/// Âmbar de TEXTO: `warningText` puro dá ~3:1 no branco; puxado para a tinta
/// do texto passa de 5:1 (também sobre a bolha verde).
Color _tintaAmbar(bool isDark) => isDark
    ? AppColors.message.warningTextDarkMode
    : Color.lerp(AppColors.message.warningText, AppColors.text.text, 0.3)!;

Color _tintaErro(bool isDark) =>
    isDark ? AppColors.message.errorTextDarkMode : AppColors.message.errorText;

/// Fill sólido dos campos (e do botão travado).
Color _campo(bool isDark) => isDark
    ? AppColors.background.backgroundTertiaryDarkMode
    : AppColors.background.backgroundTertiary;

/// Fundo da conversa atrás da bolha.
Color _papel(bool isDark) => isDark
    ? AppColors.background.backgroundSecondaryDarkMode
    : AppColors.background.backgroundSecondary;
