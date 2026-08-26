import 'package:flutter/material.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/utils/broker_contact_actions.dart';
import '../../whatsapp/models/whatsapp_models.dart';
import '../../whatsapp/services/whatsapp_service.dart';
import '../services/kanban_service.dart';
import '../utils/kanban_message_vars.dart';
import '../utils/kanban_whatsapp_templates.dart';
import 'task_edit_sheets.dart';

// =============================================================================
// MENSAGEM PRONTA DO WHATSAPP (card do CRM)
// =============================================================================
//
// Tocar no WhatsApp não abre mais uma conversa MUDA: abre este sheet, o
// corretor escolhe um modelo, EDITA o texto se quiser e só então o WhatsApp
// abre com a mensagem já digitada (`wa.me/<ddi+ddd+numero>?text=...`).
//
// Três fontes, na ordem em que aparecem:
// 1. modelos LOCAIS do app (sempre existem — não dependem de permissão);
// 2. o texto da CADÊNCIA da coluna atual, quando a empresa configurou um
//    (`GET /kanban/columns/:id/cadence` → `messageText`);
// 3. a biblioteca "mensagem pronta" da empresa
//    (`GET /whatsapp/unofficial/quick-messages`, exige `whatsapp:view`).
// As duas remotas são ACRÉSCIMO: falharam, o sheet segue com os locais e
// nenhum erro técnico aparece na cara do corretor.
//
// Anatomia da casa: grabber 42×4 · eyebrow + título + fechar · divisor
// gradient · corpo rolável com teto de 85% · rodapé com a ação verde.

/// Emerald — mesma família de CONTATO/lead na tela de detalhes.
const Color _kMessageTone = Color(0xFF059669);

/// Indigo — cadência/percurso do funil (o mesmo tom das rotas do card).
const Color _kCadenceTone = Color(0xFF6366F1);

/// Sky — biblioteca da empresa (vínculo com algo que vive fora do card).
const Color _kLibraryTone = Color(0xFF0EA5E9);

/// Slate — escrever do zero é ausência de modelo, não uma família nova.
const Color _kBlankTone = Color(0xFF64748B);

Color _toneOf(KanbanMessageSource source) {
  switch (source) {
    case KanbanMessageSource.local:
      return _kMessageTone;
    case KanbanMessageSource.cadence:
      return _kCadenceTone;
    case KanbanMessageSource.library:
      return _kLibraryTone;
    case KanbanMessageSource.blank:
      return _kBlankTone;
  }
}

IconData _iconOf(KanbanMessageSource source) {
  switch (source) {
    case KanbanMessageSource.local:
      return Icons.forum_outlined;
    case KanbanMessageSource.cadence:
      return Icons.timeline_rounded;
    case KanbanMessageSource.library:
      return Icons.bookmarks_outlined;
    case KanbanMessageSource.blank:
      return Icons.edit_note_rounded;
  }
}

/// Abre o compositor e, se o corretor confirmar, dispara o WhatsApp com o
/// texto. Devolve `true` quando o app externo foi aberto.
Future<bool> showWhatsAppMessageSheet(
  BuildContext context, {
  required String phone,
  required KanbanMessageVars vars,
  String? columnId,
}) async {
  final pageContext = context;
  final text = await showModalBottomSheet<String>(
    context: pageContext,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => WhatsAppMessageSheet(
      phone: phone,
      vars: vars,
      columnId: columnId,
    ),
  );
  // `null` = fechou/cancelou. String vazia = "mensagem em branco" de
  // propósito: abre a conversa sem `?text=`, que é o comportamento antigo.
  if (text == null) return false;
  if (!pageContext.mounted) return false;
  return BrokerContactActions.openWhatsApp(pageContext, phone, message: text);
}

class WhatsAppMessageSheet extends StatefulWidget {
  const WhatsAppMessageSheet({
    super.key,
    required this.phone,
    required this.vars,
    this.columnId,
  });

  final String phone;
  final KanbanMessageVars vars;

  /// Coluna atual do card — usada para buscar o texto de cadência da etapa.
  final String? columnId;

  @override
  State<WhatsAppMessageSheet> createState() => _WhatsAppMessageSheetState();
}

class _WhatsAppMessageSheetState extends State<WhatsAppMessageSheet> {
  late final TextEditingController _text;
  final FocusNode _textFocus = FocusNode();
  late List<KanbanMessageTemplate> _locals;

  List<KanbanMessageTemplate> _cadence = const [];
  List<KanbanMessageTemplate> _library = const [];
  bool _loadingRemote = true;

  String? _selectedId;

  /// Modelo em branco — item fixo do fim da lista.
  late final KanbanMessageTemplate _blank;

  @override
  void initState() {
    super.initState();
    _locals = KanbanWhatsAppTemplates.build(widget.vars);
    _blank = const KanbanMessageTemplate(
      id: 'blank',
      title: 'Mensagem em branco',
      body: '',
      source: KanbanMessageSource.blank,
    );
    // Já abre com o primeiro modelo escolhido: o caminho mais curto é tocar
    // no WhatsApp e confirmar.
    final first = _locals.isNotEmpty ? _locals.first : _blank;
    _selectedId = first.id;
    _text = TextEditingController(text: first.body);
    _loadRemote();
  }

  @override
  void dispose() {
    _text.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  Future<void> _loadRemote() async {
    final columnId = widget.columnId?.trim();

    // As duas buscas são independentes e best-effort — nenhuma pode derrubar
    // o sheet nem virar mensagem de erro. O try/catch aqui é o cinto de
    // segurança: se QUALQUER uma escapar (Future.wait propaga o primeiro
    // erro), o spinner "Procurando modelos da empresa…" ficaria girando para
    // sempre em cima de uma lista que já está pronta.
    var cadence = const <KanbanMessageTemplate>[];
    var library = const <KanbanMessageTemplate>[];
    try {
      final results = await Future.wait<List<KanbanMessageTemplate>>([
        _loadCadence(columnId),
        _loadLibrary(),
      ]);
      cadence = results[0];
      library = results[1];
    } catch (_) {
      // Segue com os modelos locais.
    }

    if (!mounted) return;
    setState(() {
      _cadence = cadence;
      _library = library;
      _loadingRemote = false;
    });
  }

  Future<List<KanbanMessageTemplate>> _loadCadence(String? columnId) async {
    if (columnId == null || columnId.isEmpty) return const [];
    try {
      final res = await KanbanService.instance.getColumnCadence(columnId);
      final body = res.data?.messageText?.trim() ?? '';
      if (!res.success || body.isEmpty) return const [];
      return [
        KanbanMessageTemplate(
          id: 'cadence:$columnId',
          title: 'Modelo desta etapa',
          body: widget.vars.apply(body),
          source: KanbanMessageSource.cadence,
        ),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<List<KanbanMessageTemplate>> _loadLibrary() async {
    final List<WhatsAppQuickMessage> messages =
        await WhatsAppService.instance.getQuickMessages();
    return messages
        .map(
          (m) => KanbanMessageTemplate(
            id: 'quick:${m.id}',
            title: m.title.trim().isNotEmpty ? m.title.trim() : m.shortcut,
            body: widget.vars.apply(m.message),
            source: KanbanMessageSource.library,
          ),
        )
        .where((t) => t.body.trim().isNotEmpty)
        .toList();
  }

  void _select(KanbanMessageTemplate template) {
    setState(() {
      _selectedId = template.id;
      _text.text = template.body;
      _text.selection = TextSelection.collapsed(offset: _text.text.length);
    });
    if (template.source == KanbanMessageSource.blank) {
      // Escolheu escrever do zero: o cursor no campo é o próximo passo
      // natural (o teclado sobe e o shell se ajusta pelo `viewInsets`).
      _textFocus.requestFocus();
    }
  }

  void _submit() => Navigator.of(context).pop(_text.text.trim());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final border = ThemeHelpers.borderColor(context);

    final name = widget.vars.clientFirstName.trim();
    final property = widget.vars.propertyLabel?.trim();

    return TaskEditSheetShell(
      eyebrow: 'WhatsApp',
      title: name.isEmpty ? 'Mensagem pronta' : 'Mensagem para $name',
      tone: _kMessageTone,
      footer: Row(
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              // O tema global pinta TextButton de VERMELHO — cancelar não é
              // ação destrutiva, então a cor é forçada para o texto neutro.
              foregroundColor: secondary,
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
            ),
            child: const Text('Cancelar'),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TaskSheetPrimaryButton(
              label: 'Abrir WhatsApp',
              icon: Icons.chat_rounded,
              onPressed: _submit,
            ),
          ),
        ],
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ─── Destino: para quem vai e sobre o quê ───────────────────────
            _DestinationLine(
              icon: Icons.smartphone_rounded,
              text: taskMaskPhone(widget.phone),
            ),
            if (property != null && property.isNotEmpty) ...[
              const SizedBox(height: 6),
              _DestinationLine(
                icon: Icons.home_work_outlined,
                text: property,
              ),
            ],
            const SizedBox(height: 18),

            // ─── Modelos locais ─────────────────────────────────────────────
            const _SheetSectionHeader(
              overline: 'Modelos',
              title: 'Primeiro contato e retomada',
              accent: _kMessageTone,
            ),
            const SizedBox(height: 10),
            ..._rows(_locals),

            // ─── Cadência da etapa ──────────────────────────────────────────
            if (_cadence.isNotEmpty) ...[
              const SizedBox(height: 20),
              const _SheetSectionHeader(
                overline: 'Etapa',
                title: 'Texto da cadência desta coluna',
                accent: _kCadenceTone,
              ),
              const SizedBox(height: 10),
              ..._rows(_cadence),
            ],

            // ─── Biblioteca da empresa ──────────────────────────────────────
            if (_library.isNotEmpty) ...[
              const SizedBox(height: 20),
              const _SheetSectionHeader(
                overline: 'Empresa',
                title: 'Mensagens prontas da equipe',
                accent: _kLibraryTone,
              ),
              const SizedBox(height: 10),
              ..._rows(_library),
            ],

            if (_loadingRemote) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: secondary,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Procurando modelos da empresa…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: secondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // ─── Escrever do zero ───────────────────────────────────────────
            const SizedBox(height: 14),
            Container(height: 1, color: border.withValues(alpha: 0.45)),
            const SizedBox(height: 14),
            ..._rows([_blank]),

            // ─── Texto final (editável) ─────────────────────────────────────
            const SizedBox(height: 22),
            const _SheetSectionHeader(
              overline: 'Texto',
              title: 'Revise antes de enviar',
              accent: _kMessageTone,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _text,
              focusNode: _textFocus,
              minLines: 5,
              maxLines: 10,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              // Campo multilinha não fecha o teclado sozinho (não tem
              // "concluído"): tocar fora precisa tirar o foco na mão.
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              style: const TextStyle(height: 1.4, fontSize: 14),
              decoration: taskFieldDecoration(
                context,
                hint: 'Escreva a mensagem que o lead vai receber…',
                tone: _kMessageTone,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 13, color: secondary),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'O texto vai preenchido no WhatsApp — você ainda pode '
                    'ajustar por lá antes de enviar.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: secondary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _rows(List<KanbanMessageTemplate> items) {
    final widgets = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final t = items[i];
      final tone = _toneOf(t.source);
      if (i > 0) widgets.add(const SizedBox(height: 8));
      widgets.add(
        TaskSheetOptionRow(
          title: t.title,
          helper: t.source == KanbanMessageSource.blank
              ? 'Escrever do zero'
              : t.preview,
          tone: tone,
          selected: _selectedId == t.id,
          onTap: () => _select(t),
          leading: Icon(_iconOf(t.source), size: 17, color: tone),
        ),
      );
    }
    return widgets;
  }
}

/// Linha muda do topo: para quem/sobre o quê a mensagem vai.
class _DestinationLine extends StatelessWidget {
  const _DestinationLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Row(
      children: [
        Icon(icon, size: 14, color: secondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: secondary,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ],
    );
  }
}

/// Cabeçalho de seção da casa: barra 3.5×24 + overline + título.
class _SheetSectionHeader extends StatelessWidget {
  const _SheetSectionHeader({
    required this.overline,
    required this.title,
    required this.accent,
  });

  final String overline;
  final String title;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 3.5,
          height: 24,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                overline.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w800,
                  color: accent,
                  fontSize: 10,
                  height: 1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                  height: 1.1,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
