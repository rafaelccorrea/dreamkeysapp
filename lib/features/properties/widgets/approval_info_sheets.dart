import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/property_activity_models.dart';
import '../models/property_change_request.dart';
import '../services/property_activity_service.dart';
import '../services/property_approval_service.dart';
import 'approval_actions_sheet.dart';

String _fmtDateTime(DateTime? d) => d == null
    ? '—'
    : DateFormat("dd/MM/yyyy 'às' HH:mm", 'pt_BR').format(d.toLocal());

// ─── Histórico do imóvel ────────────────────────────────────────────────

/// Sheet do **histórico do imóvel** (`GET /properties/:id/history`) — mesmo
/// conteúdo do "Ver histórico" do menu de 3 pontinhos do web.
Future<void> showPropertyHistorySheet({
  required BuildContext context,
  required String propertyId,
  required String propertyTitle,
  required Color tone,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: ThemeHelpers.cardBackgroundColor(context),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _PropertyHistorySheet(
      propertyId: propertyId,
      propertyTitle: propertyTitle,
      tone: tone,
    ),
  );
}

class _PropertyHistorySheet extends StatefulWidget {
  final String propertyId;
  final String propertyTitle;
  final Color tone;

  const _PropertyHistorySheet({
    required this.propertyId,
    required this.propertyTitle,
    required this.tone,
  });

  @override
  State<_PropertyHistorySheet> createState() => _PropertyHistorySheetState();
}

class _PropertyHistorySheetState extends State<_PropertyHistorySheet> {
  bool _loading = true;
  List<PropertyHistoryEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await PropertyActivityService.instance
        .getHistory(widget.propertyId, limit: 200);
    if (!mounted) return;
    setState(() {
      _entries = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ApprovalSheetGrabber(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 10, 0),
          child: ApprovalSheetHeader(
            eyebrow: 'HISTÓRICO',
            title: 'Linha do tempo do imóvel',
            subtitle: widget.propertyTitle,
            tone: widget.tone,
            icon: LucideIcons.history,
          ),
        ),
        const SizedBox(height: 14),
        ApprovalSheetDivider(tone: widget.tone),
        Flexible(
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 42),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _entries.isEmpty
                  ? _EmptySheetState(
                      icon: LucideIcons.history,
                      title: 'Sem histórico registrado',
                      body: 'Nada foi registrado para este imóvel ainda.',
                      tone: widget.tone,
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      itemCount: _entries.length,
                      itemBuilder: (_, i) {
                        final e = _entries[i];
                        return _HistoryRow(
                          entry: e,
                          isLast: i == _entries.length - 1,
                          theme: theme,
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final PropertyHistoryEntry entry;
  final bool isLast;
  final ThemeData theme;

  const _HistoryRow({
    required this.entry,
    required this.isLast,
    required this.theme,
  });

  /// Cor do marcador por significado do evento — nada de "tudo vermelho".
  Color _tone(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final e = entry.event;
    if (e.contains('rejected') || e.contains('invalidated')) {
      return isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    }
    if (e.contains('approved') || e.contains('signed')) {
      return const Color(0xFF059669);
    }
    if (e.contains('requested') ||
        e.contains('sent') ||
        e.contains('reminder') ||
        e.contains('waived')) {
      return isDark
          ? AppColors.status.warningDarkMode
          : AppColors.status.warning;
    }
    if (e.contains('vote') || e.contains('thread')) {
      return isDark
          ? AppColors.status.purpleDarkMode
          : AppColors.status.purple;
    }
    return ThemeHelpers.textSecondaryColor(context);
  }

  @override
  Widget build(BuildContext context) {
    final tone = _tone(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(top: 5),
                decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1.5,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: ThemeHelpers.borderLightColor(context),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    propertyHistoryEventLabel(entry.event),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: ThemeHelpers.textColor(context),
                      height: 1.25,
                    ),
                  ),
                  if ((entry.description ?? '').isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      entry.description!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        height: 1.38,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(LucideIcons.clock, size: 11, color: secondary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          [
                            _fmtDateTime(entry.createdAt),
                            if ((entry.user?.name ?? '').isNotEmpty)
                              entry.user!.name!,
                          ].join(' · '),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: secondary,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Histórico de envios da autorização ─────────────────────────────────

/// Sheet do **histórico de envios** da autorização do proprietário
/// (`GET /properties/:id/owner-authorization/send-history`).
Future<void> showOwnerAuthSendHistorySheet({
  required BuildContext context,
  required String propertyId,
  required String propertyTitle,
  required Color tone,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: ThemeHelpers.cardBackgroundColor(context),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _OwnerAuthSendHistorySheet(
      propertyId: propertyId,
      propertyTitle: propertyTitle,
      tone: tone,
    ),
  );
}

class _OwnerAuthSendHistorySheet extends StatefulWidget {
  final String propertyId;
  final String propertyTitle;
  final Color tone;

  const _OwnerAuthSendHistorySheet({
    required this.propertyId,
    required this.propertyTitle,
    required this.tone,
  });

  @override
  State<_OwnerAuthSendHistorySheet> createState() =>
      _OwnerAuthSendHistorySheetState();
}

class _OwnerAuthSendHistorySheetState
    extends State<_OwnerAuthSendHistorySheet> {
  bool _loading = true;
  String? _error;
  OwnerAuthSendHistory _data = OwnerAuthSendHistory.empty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await PropertyApprovalService.instance
        .getOwnerAuthorizationSendHistory(widget.propertyId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _data = res.data!;
      } else {
        _error = res.message ?? 'Erro ao carregar o histórico de envios.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ApprovalSheetGrabber(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 10, 0),
          child: ApprovalSheetHeader(
            eyebrow: 'AUTORIZAÇÃO',
            title: 'Histórico de envios',
            subtitle: widget.propertyTitle,
            tone: widget.tone,
            icon: LucideIcons.send,
          ),
        ),
        const SizedBox(height: 14),
        ApprovalSheetDivider(tone: widget.tone),
        Flexible(
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 42),
                  child: Center(child: CircularProgressIndicator()),
                )
              : SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_error != null)
                        Text(
                          _error!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: secondary,
                          ),
                        )
                      else ...[
                        if (_data.signedAt != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: kApprovalGreen.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color:
                                    kApprovalGreen.withValues(alpha: 0.22),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  LucideIcons.badgeCheck,
                                  size: 17,
                                  color: kApprovalGreen,
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    'Assinado em ${_fmtDateTime(_data.signedAt)}'
                                    '${(_data.signedByName ?? '').isEmpty ? '' : ' por ${_data.signedByName}'}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: kApprovalGreen,
                                      fontWeight: FontWeight.w700,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (_data.entries.isEmpty)
                          Text(
                            'Nenhum envio registrado para este imóvel.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: secondary,
                            ),
                          )
                        else
                          for (var i = 0; i < _data.entries.length; i++)
                            _SendHistoryRow(
                              entry: _data.entries[i],
                              isLast: i == _data.entries.length - 1,
                            ),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _SendHistoryRow extends StatelessWidget {
  final OwnerAuthSendEntry entry;
  final bool isLast;

  const _SendHistoryRow({required this.entry, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final target = (entry.sentToName ?? '').isNotEmpty
        ? entry.sentToName!
        : (entry.sentToEmail ?? 'Destinatário não informado');
    return Container(
      decoration: isLast
          ? null
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: ThemeHelpers.borderLightColor(context),
                ),
              ),
            ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            target,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: ThemeHelpers.textColor(context),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if ((entry.sentToEmail ?? '').isNotEmpty &&
              (entry.sentToName ?? '').isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              entry.sentToEmail!,
              style: theme.textTheme.bodySmall?.copyWith(color: secondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 4),
          Text(
            [
              _fmtDateTime(entry.createdAt),
              if ((entry.sentByUserName ?? '').isNotEmpty)
                'por ${entry.sentByUserName}',
            ].join(' · '),
            style: theme.textTheme.labelSmall?.copyWith(
              color: secondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Conversa de aprovação ──────────────────────────────────────────────

/// Sheet da **conversa de aprovação** (aprovador ↔ responsável) — equivalente
/// mobile do `PropertyApprovalCommunicationPanel` embutido no card do web.
/// O gate é 100% server-side: 403 no GET esconde a conversa.
Future<void> showApprovalThreadSheet({
  required BuildContext context,
  required String propertyId,
  required String propertyTitle,
  required ApprovalType queue,
  required Color tone,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: ThemeHelpers.cardBackgroundColor(context),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _ApprovalThreadSheet(
      propertyId: propertyId,
      propertyTitle: propertyTitle,
      queue: queue,
      tone: tone,
    ),
  );
}

class _ApprovalThreadSheet extends StatefulWidget {
  final String propertyId;
  final String propertyTitle;
  final ApprovalType queue;
  final Color tone;

  const _ApprovalThreadSheet({
    required this.propertyId,
    required this.propertyTitle,
    required this.queue,
    required this.tone,
  });

  @override
  State<_ApprovalThreadSheet> createState() => _ApprovalThreadSheetState();
}

class _ApprovalThreadSheetState extends State<_ApprovalThreadSheet> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();

  bool _loading = true;
  bool _forbidden = false;
  bool _sending = false;
  String? _error;
  List<PropertyHistoryEntry> _messages = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await PropertyApprovalService.instance
        .getApprovalThread(widget.propertyId, context: widget.queue);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success) {
        _messages = res.data ?? const [];
      } else if (res.statusCode == 403) {
        _forbidden = true;
      } else {
        _error = res.message ?? 'Erro ao carregar a conversa.';
      }
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final res = await PropertyApprovalService.instance.postApprovalThreadMessage(
      widget.propertyId,
      message: text,
      queue: widget.queue,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (res.success && res.data != null) {
      setState(() {
        _messages = [..._messages, res.data!];
        _composer.clear();
      });
      _scrollToBottom();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message ?? 'Erro ao enviar mensagem.'),
          backgroundColor: AppColors.status.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final queueLabel = widget.queue == ApprovalType.availability
        ? 'Disponibilidade'
        : 'Publicação no site';

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ApprovalSheetGrabber(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 10, 0),
            child: ApprovalSheetHeader(
              eyebrow: 'CONVERSA · $queueLabel',
              title: 'Aprovador ↔ responsável',
              subtitle: widget.propertyTitle,
              tone: widget.tone,
              icon: LucideIcons.messagesSquare,
            ),
          ),
          const SizedBox(height: 14),
          ApprovalSheetDivider(tone: widget.tone),
          Flexible(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 42),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _forbidden
                    ? _EmptySheetState(
                        icon: LucideIcons.lock,
                        title: 'Conversa restrita',
                        body:
                            'Só aprovadores, gestão e quem responde pelo imóvel participam desta conversa.',
                        tone: widget.tone,
                      )
                    : _error != null
                        ? _EmptySheetState(
                            icon: LucideIcons.cloudOff,
                            title: 'Não foi possível carregar',
                            body: _error!,
                            tone: widget.tone,
                          )
                        : _messages.isEmpty
                            ? _EmptySheetState(
                                icon: LucideIcons.messageSquare,
                                title: 'Nenhuma mensagem ainda',
                                body:
                                    'Escreva abaixo para falar com quem responde por este imóvel.',
                                tone: widget.tone,
                              )
                            : ListView.builder(
                                controller: _scroll,
                                shrinkWrap: true,
                                padding:
                                    const EdgeInsets.fromLTRB(20, 14, 20, 8),
                                itemCount: _messages.length,
                                itemBuilder: (_, i) {
                                  final m = _messages[i];
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          [
                                            if ((m.user?.name ?? '').isNotEmpty)
                                              m.user!.name!
                                            else
                                              'Sistema',
                                            _fmtDateTime(m.createdAt),
                                          ].join(' · '),
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            color: secondary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          m.description ?? '',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                            color:
                                                ThemeHelpers.textColor(context),
                                            height: 1.4,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
          ),
          if (!_forbidden && _error == null)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: ThemeHelpers.borderColor(context)
                        .withValues(alpha: 0.35),
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _composer,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 4000,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Escreva uma mensagem…',
                        counterText: '',
                        isDense: true,
                        filled: true,
                        fillColor: ThemeHelpers.backgroundColor(context),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: ThemeHelpers.borderColor(context),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: ThemeHelpers.borderColor(context),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: widget.tone, width: 1.4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      onPressed:
                          _composer.text.trim().isEmpty || _sending
                              ? null
                              : _send,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kApprovalGreen,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            kApprovalGreen.withValues(alpha: 0.3),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(LucideIcons.send, size: 17),
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

// ─── Votação (multi-aprovadores) ────────────────────────────────────────

/// Resultado do sheet de voto.
class ApprovalVoteResult {
  final bool approved;
  final String comment;

  const ApprovalVoteResult({required this.approved, required this.comment});
}

/// Sheet de **voto** na fila (quando o multi-aprovadores está ligado). Mostra
/// o quórum atual (`GET /voting-status`) e coleta a decisão + comentário.
Future<ApprovalVoteResult?> showApprovalVoteSheet({
  required BuildContext context,
  required String propertyId,
  required String propertyTitle,
  required ApprovalType queue,
  required Color tone,
}) {
  return showModalBottomSheet<ApprovalVoteResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: ThemeHelpers.cardBackgroundColor(context),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _ApprovalVoteSheet(
      propertyId: propertyId,
      propertyTitle: propertyTitle,
      queue: queue,
      tone: tone,
    ),
  );
}

class _ApprovalVoteSheet extends StatefulWidget {
  final String propertyId;
  final String propertyTitle;
  final ApprovalType queue;
  final Color tone;

  const _ApprovalVoteSheet({
    required this.propertyId,
    required this.propertyTitle,
    required this.queue,
    required this.tone,
  });

  @override
  State<_ApprovalVoteSheet> createState() => _ApprovalVoteSheetState();
}

class _ApprovalVoteSheetState extends State<_ApprovalVoteSheet> {
  final TextEditingController _comment = TextEditingController();
  bool _loading = true;
  bool? _approved;
  ApprovalVotingStatus _status = ApprovalVotingStatus.empty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await PropertyApprovalService.instance
        .getVotingStatus(widget.propertyId, type: widget.queue);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) _status = res.data!;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ApprovalSheetGrabber(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 10, 0),
            child: ApprovalSheetHeader(
              eyebrow: 'VOTAÇÃO',
              title: widget.queue == ApprovalType.availability
                  ? 'Voto na disponibilidade'
                  : 'Voto na publicação',
              subtitle: widget.propertyTitle,
              tone: widget.tone,
              icon: LucideIcons.vote,
            ),
          ),
          const SizedBox(height: 14),
          ApprovalSheetDivider(tone: widget.tone),
          Flexible(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: _VoteStat(
                            label: 'A FAVOR',
                            value: '${_status.approvedCount}',
                            tone: kApprovalGreen,
                          ),
                        ),
                        Expanded(
                          child: _VoteStat(
                            label: 'CONTRA',
                            value: '${_status.rejectedCount}',
                            tone: danger,
                          ),
                        ),
                        Expanded(
                          child: _VoteStat(
                            label: 'QUÓRUM',
                            value: '${_status.quorum}',
                            tone: widget.tone,
                          ),
                        ),
                        Expanded(
                          child: _VoteStat(
                            label: 'FALTAM',
                            value: '${_status.pendingCount}',
                            tone: secondary,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _VoteChoice(
                          icon: LucideIcons.checkCircle2,
                          label: 'Aprovar',
                          tone: kApprovalGreen,
                          selected: _approved == true,
                          onTap: () => setState(() => _approved = true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _VoteChoice(
                          icon: LucideIcons.xCircle,
                          label: 'Recusar',
                          tone: danger,
                          selected: _approved == false,
                          onTap: () => setState(() => _approved = false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'COMENTÁRIO (OPCIONAL)',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _comment,
                    minLines: 2,
                    maxLines: 5,
                    maxLength: 500,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Justifique o voto para o time…',
                      counterText: '',
                      isDense: true,
                      filled: true,
                      fillColor: ThemeHelpers.backgroundColor(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: ThemeHelpers.borderColor(context),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: ThemeHelpers.borderColor(context),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: widget.tone, width: 1.4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
          ApprovalSheetFooter(
            confirmLabel: 'Registrar voto',
            confirmIcon: LucideIcons.vote,
            confirmColor: _approved == false ? danger : kApprovalGreen,
            submitting: false,
            onConfirm: _approved == null
                ? null
                : () => Navigator.of(context).pop(
                      ApprovalVoteResult(
                        approved: _approved!,
                        comment: _comment.text.trim(),
                      ),
                    ),
          ),
        ],
      ),
    );
  }
}

class _VoteStat extends StatelessWidget {
  final String label;
  final String value;
  final Color tone;

  const _VoteStat({
    required this.label,
    required this.value,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            color: tone,
            letterSpacing: 1.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: tone,
              fontSize: 20,
              height: 1,
            ),
          ),
        ),
      ],
    );
  }
}

class _VoteChoice extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color tone;
  final bool selected;
  final VoidCallback onTap;

  const _VoteChoice({
    required this.icon,
    required this.label,
    required this.tone,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: selected
                ? tone.withValues(alpha: isDark ? 0.18 : 0.10)
                : Colors.transparent,
            border: Border.all(
              color: selected
                  ? tone.withValues(alpha: 0.55)
                  : ThemeHelpers.borderColor(context),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color:
                    selected ? tone : ThemeHelpers.textSecondaryColor(context),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: selected
                          ? tone
                          : ThemeHelpers.textSecondaryColor(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Estado vazio compartilhado pelos sheets de leitura.
class _EmptySheetState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Color tone;

  const _EmptySheetState({
    required this.icon,
    required this.title,
    required this.body,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tone.withValues(alpha: 0.10),
              border: Border.all(color: tone.withValues(alpha: 0.28)),
            ),
            child: Icon(icon, color: tone, size: 25),
          ),
          const SizedBox(height: 13),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
