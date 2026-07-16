import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/ticket_models.dart';
import '../services/ticket_service.dart';
import '../widgets/ticket_attachment_view.dart';

String _formatFullDate(DateTime? date) {
  if (date == null) return '—';
  return DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(date.toLocal());
}

String _formatRelative(DateTime? date) {
  if (date == null) return '—';
  final d = date.toLocal();
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'agora';
  if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'há ${diff.inHours}h';
  if (diff.inDays == 1) return 'ontem';
  if (diff.inDays < 30) return 'há ${diff.inDays} dias';
  return DateFormat('dd/MM/yyyy', 'pt_BR').format(d);
}

/// Duração legível a partir de minutos (paridade com o web).
String? _formatDuration(int? minutes) {
  if (minutes == null || minutes < 0) return null;
  if (minutes < 1) return 'menos de 1 min';
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final restMin = minutes % 60;
  if (hours < 24) return restMin > 0 ? '${hours}h ${restMin}min' : '${hours}h';
  final days = hours ~/ 24;
  final restHours = hours % 24;
  return restHours > 0 ? '${days}d ${restHours}h' : '${days}d';
}

String _initials(String? name) {
  final n = (name ?? '').trim();
  if (n.isEmpty) return '?';
  final parts = n.split(RegExp(r'\s+'));
  if (parts.length == 1) {
    return parts.first
        .substring(0, parts.first.length >= 2 ? 2 : 1)
        .toUpperCase();
  }
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

/// Tela **Detalhe do ticket** — porta a visão do solicitante do
/// `TicketDetailPage` web: hero flush com categoria/status/prioridade/SLA,
/// papéis do atendimento, descrição, conversa com anexos e composer para
/// responder. Excluir só enquanto não há atendimento (regra do backend).
class TicketDetailPage extends StatefulWidget {
  final String ticketId;

  const TicketDetailPage({super.key, required this.ticketId});

  @override
  State<TicketDetailPage> createState() => _TicketDetailPageState();
}

class _TicketDetailPageState extends State<TicketDetailPage> {
  TicketDetail? _detail;
  bool _loading = true;
  String? _error;

  final TextEditingController _composerController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  bool _sending = false;
  int _uploadingCount = 0;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _composerController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Color _accentColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;

  // ─── Dados ───────────────────────────────────────────────────────────────

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final res = await TicketService.instance.getDetail(widget.ticketId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _detail = res.data;
        _error = null;
      } else if (!silent || _detail == null) {
        _error = res.message ?? 'Ticket não encontrado';
      }
    });
  }

  Future<void> _send() async {
    final text = _composerController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final res = await TicketService.instance.addComment(widget.ticketId, text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (res.success) {
      _composerController.clear();
      await _load(silent: true);
      _scrollToBottom();
    } else {
      _showSnack(res.message ?? 'Erro ao enviar a mensagem');
    }
  }

  Future<void> _attach(ImageSource source) async {
    XFile? file;
    try {
      file = await _picker.pickImage(source: source, imageQuality: 85);
    } catch (_) {
      _showSnack(
        source == ImageSource.camera
            ? 'Não foi possível abrir a câmera.'
            : 'Não foi possível abrir a galeria.',
      );
      return;
    }
    if (file == null) return;
    setState(() => _uploadingCount++);
    final res = await TicketService.instance.uploadAttachment(
      widget.ticketId,
      File(file.path),
    );
    if (!mounted) return;
    setState(() => _uploadingCount = (_uploadingCount - 1).clamp(0, 99));
    if (res.success) {
      _showSnack('Anexo enviado');
      await _load(silent: true);
      _scrollToBottom();
    } else {
      _showSnack(res.message ?? 'Erro ao enviar o anexo');
    }
  }

  void _showAttachSheet() {
    final neutral = ThemeHelpers.textSecondaryColor(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: ThemeHelpers.cardBackgroundColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: neutral.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(LucideIcons.images, color: neutral, size: 20),
              title: const Text(
                'Escolher da galeria',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _attach(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: Icon(LucideIcons.camera, color: neutral, size: 20),
              title: const Text(
                'Tirar foto',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _attach(ImageSource.camera);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final ticket = _detail?.ticket;
    if (ticket == null) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final danger = isDark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ThemeHelpers.cardBackgroundColor(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(LucideIcons.triangleAlert, color: danger, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Excluir ticket?',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
              ),
            ),
          ],
        ),
        content: Text(
          'Como ainda não há atendimento, você pode excluir "${ticket.title}". Esta ação não poderá ser desfeita.',
          style: const TextStyle(height: 1.4, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: danger),
            child: const Text(
              'Excluir',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    final res = await TicketService.instance.remove(widget.ticketId);
    if (!mounted) return;
    setState(() => _deleting = false);
    if (res.success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ticket excluído')));
      Navigator.of(context).pop();
    } else {
      _showSnack(res.message ?? 'Erro ao excluir o ticket');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ticket = _detail?.ticket;
    final canDelete = ticket != null && ticket.isUnattended;

    return AppScaffold(
      title: 'Ticket',
      showBottomNavigation: false,
      actions: [
        if (canDelete)
          IconButton(
            tooltip: 'Excluir — disponível enquanto não há atendimento',
            onPressed: _deleting ? null : _confirmDelete,
            icon: _deleting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.trash2, size: 20),
          ),
      ],
      body: _loading && _detail == null
          ? _buildSkeleton(context)
          : _detail == null
          ? _buildError(context)
          : _buildLoaded(context, _detail!),
    );
  }

  Widget _buildLoaded(BuildContext context, TicketDetail detail) {
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            color: _accentColor(context),
            onRefresh: () => _load(silent: true),
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHero(context, detail.ticket),
                  const SizedBox(height: 20),
                  _buildConversation(context, detail),
                  if (detail.rootAttachments.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _buildRootAttachments(context, detail),
                  ],
                  if (detail.statusHistory.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _buildStatusHistory(context, detail),
                  ],
                ],
              ),
            ),
          ),
        ),
        _buildComposer(context),
      ],
    );
  }

  // ─── Hero flush ──────────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context, Ticket ticket) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final categoryTone = ticketCategoryColor(context, ticket.category);
    final statusTone = ticketStatusColor(context, ticket.status);
    final priorityTone = ticketPriorityColor(context, ticket.priority);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Eyebrow da categoria.
        Row(
          children: [
            Icon(
              ticketCategoryIcon(ticket.category),
              size: 13,
              color: categoryTone,
            ),
            const SizedBox(width: 6),
            Text(
              ticket.category.label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: categoryTone,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.8,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          ticket.title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            color: ThemeHelpers.textColor(context),
            letterSpacing: -0.5,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _pill(
              context,
              ticket.status.label,
              statusTone,
              icon: ticketStatusIcon(ticket.status),
            ),
            _pill(
              context,
              ticket.priority.label,
              priorityTone,
              icon: LucideIcons.zap,
            ),
            if (ticket.slaStatus != TicketSlaStatus.unknown)
              _pill(
                context,
                'SLA · ${ticket.slaStatus.label}',
                _slaTone(context, ticket.slaStatus),
              ),
          ],
        ),
        const SizedBox(height: 14),
        // Meta compacta: aberto em + 1ª resposta.
        Row(
          children: [
            Expanded(
              child: _metaBlock(
                context,
                'ABERTO EM',
                _formatRelative(ticket.createdAt),
                _formatFullDate(ticket.createdAt),
              ),
            ),
            Container(
              width: 1,
              height: 30,
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _metaBlock(
                context,
                '1ª RESPOSTA',
                ticket.firstResponseAt != null
                    ? (_formatDuration(ticket.firstResponseMinutes) ??
                          _formatRelative(ticket.firstResponseAt))
                    : 'Aguardando',
                ticket.firstResponseAt != null
                    ? _formatFullDate(ticket.firstResponseAt)
                    : 'O suporte ainda não respondeu',
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // Papéis do atendimento.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _roleChip(
              context,
              LucideIcons.user,
              'Relator',
              ticket.createdByName ?? ticket.createdByEmail ?? '—',
            ),
            _roleChip(
              context,
              LucideIcons.headset,
              'Atendente',
              ticket.attendantLabel ?? 'Não atribuído',
            ),
            _roleChip(
              context,
              LucideIcons.code,
              'Desenvolvedor',
              ticket.developerLabel ?? 'Não atribuído',
            ),
          ],
        ),
        if (ticket.description.trim().isNotEmpty) ...[
          const SizedBox(height: 14),
          // Descrição original — bloco flush com filete da categoria.
          Container(
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: categoryTone.withValues(alpha: isDark ? 0.5 : 0.4),
                  width: 3,
                ),
              ),
            ),
            child: Text(
              ticket.description.trim(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Color _slaTone(BuildContext context, TicketSlaStatus status) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (status) {
      case TicketSlaStatus.onTime:
        return isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
      case TicketSlaStatus.warning:
        return isDark
            ? AppColors.status.warningDarkMode
            : AppColors.status.warning;
      case TicketSlaStatus.late:
        return isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
      case TicketSlaStatus.pending:
      case TicketSlaStatus.unknown:
        return ThemeHelpers.textSecondaryColor(context);
    }
  }

  Widget _pill(
    BuildContext context,
    String label,
    Color color, {
    IconData? icon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: isDark ? 0.4 : 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaBlock(
    BuildContext context,
    String label,
    String value,
    String sub,
  ) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            color: secondary,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: ThemeHelpers.textColor(context),
            letterSpacing: -0.2,
            height: 1.0,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 3),
        Text(
          sub,
          style: TextStyle(fontSize: 10.5, color: secondary, height: 1.0),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _roleChip(
    BuildContext context,
    IconData icon,
    String role,
    String name,
  ) {
    final neutral = ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ThemeHelpers.borderLightColor(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: neutral),
          const SizedBox(width: 6),
          Text(
            '$role · ',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: neutral,
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: ThemeHelpers.textColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Conversa ────────────────────────────────────────────────────────────

  Widget _sectionMarker(
    BuildContext context,
    Color tone,
    String label, {
    String? hint,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: tone,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: tone.withValues(alpha: 0.5), blurRadius: 6),
            ],
          ),
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: tone,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
            fontSize: 10.5,
          ),
        ),
        if (hint != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: theme.textTheme.labelSmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
                fontWeight: FontWeight.w600,
                fontSize: 10.5,
              ),
            ),
          ),
        ] else
          const Spacer(),
      ],
    );
  }

  Widget _buildConversation(BuildContext context, TicketDetail detail) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final emerald = isDark
        ? AppColors.status.greenDarkMode
        : AppColors.status.green;
    final comments = detail.comments;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionMarker(
          context,
          emerald,
          'CONVERSA',
          hint: comments.isEmpty
              ? 'Envie a primeira mensagem'
              : '${comments.length} mensage${comments.length == 1 ? 'm' : 'ns'}',
        ),
        const SizedBox(height: 12),
        if (comments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Column(
              children: [
                Icon(
                  LucideIcons.messagesSquare,
                  size: 26,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
                const SizedBox(height: 8),
                Text(
                  'Nenhuma resposta ainda',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'A equipe de suporte responde por aqui — você também pode complementar abaixo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
              ],
            ),
          )
        else
          for (var i = 0; i < comments.length; i++)
            _MessageBubble(comment: comments[i])
                .animate(key: ValueKey('m-${comments[i].id}'))
                .fadeIn(
                  delay: Duration(milliseconds: 25 * i.clamp(0, 10)),
                  duration: 200.ms,
                ),
      ],
    );
  }

  Widget _buildRootAttachments(BuildContext context, TicketDetail detail) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final blue = isDark ? AppColors.status.infoDarkMode : AppColors.status.info;
    final items = detail.rootAttachments;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionMarker(
          context,
          blue,
          'ANEXOS DO TICKET',
          hint: '${items.length} arquivo${items.length == 1 ? '' : 's'}',
        ),
        const SizedBox(height: 12),
        TicketAttachmentGallery(attachments: items),
      ],
    );
  }

  Widget _buildStatusHistory(BuildContext context, TicketDetail detail) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final purple = isDark
        ? AppColors.status.purpleDarkMode
        : AppColors.status.purple;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final items = detail.statusHistory;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionMarker(context, purple, 'HISTÓRICO DE STATUS'),
        const SizedBox(height: 12),
        for (var i = 0; i < items.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(top: 5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ticketStatusColor(context, items[i].toStatus),
                      ),
                    ),
                    if (i < items.length - 1)
                      Expanded(
                        child: Container(
                          width: 2,
                          margin: const EdgeInsets.only(top: 3),
                          color: ThemeHelpers.borderLightColor(context),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: i < items.length - 1 ? 14 : 0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              if (items[i].fromStatus != null) ...[
                                TextSpan(
                                  text: items[i].fromStatus!.label,
                                  style: TextStyle(color: secondary),
                                ),
                                TextSpan(
                                  text: '  →  ',
                                  style: TextStyle(color: secondary),
                                ),
                              ],
                              TextSpan(
                                text: items[i].toStatus.label,
                                style: TextStyle(
                                  color: ticketStatusColor(
                                    context,
                                    items[i].toStatus,
                                  ),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${items[i].changedByName != null ? '${items[i].changedByName} · ' : ''}${_formatFullDate(items[i].createdAt)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: secondary,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ─── Composer ────────────────────────────────────────────────────────────

  Widget _buildComposer(BuildContext context) {
    final accent = _accentColor(context);
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final hasText = _composerController.text.trim().isNotEmpty;

    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        10,
        12,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border(
          top: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_uploadingCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Enviando $_uploadingCount anexo${_uploadingCount > 1 ? 's' : ''}…',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: neutral,
                    ),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              InkResponse(
                radius: 22,
                onTap: _showAttachSheet,
                child: Padding(
                  padding: const EdgeInsets.all(9),
                  child: Icon(LucideIcons.paperclip, size: 19, color: neutral),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: TextField(
                    controller: _composerController,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    cursorColor: accent,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: ThemeHelpers.textColor(context),
                      height: 1.35,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Escreva uma resposta…',
                      hintStyle: TextStyle(
                        color: neutral.withValues(alpha: 0.75),
                        fontWeight: FontWeight.w500,
                        fontSize: 13.5,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Enviar — na cor da marca quando há texto.
              Material(
                color: hasText && !_sending
                    ? accent
                    : accent.withValues(alpha: 0.35),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: hasText && !_sending ? _send : null,
                  child: SizedBox(
                    width: 42,
                    height: 42,
                    child: _sending
                        ? const Padding(
                            padding: EdgeInsets.all(11),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            LucideIcons.sendHorizontal,
                            size: 18,
                            color: Colors.white,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Estados ─────────────────────────────────────────────────────────────

  Widget _buildSkeleton(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonText(width: 110, height: 11, borderRadius: 999),
          const SizedBox(height: 12),
          const SkeletonText(width: double.infinity, height: 24),
          const SizedBox(height: 6),
          const SkeletonText(width: 200, height: 24),
          const SizedBox(height: 14),
          Row(
            children: const [
              SkeletonText(width: 78, height: 22, borderRadius: 999),
              SizedBox(width: 6),
              SkeletonText(width: 64, height: 22, borderRadius: 999),
              SizedBox(width: 6),
              SkeletonText(width: 88, height: 22, borderRadius: 999),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: const [
              Expanded(child: SkeletonText(width: double.infinity, height: 34)),
              SizedBox(width: 14),
              Expanded(child: SkeletonText(width: double.infinity, height: 34)),
            ],
          ),
          const SizedBox(height: 18),
          const SkeletonText(width: double.infinity, height: 14),
          const SizedBox(height: 6),
          const SkeletonText(width: double.infinity, height: 14),
          const SizedBox(height: 6),
          const SkeletonText(width: 180, height: 14),
          const SizedBox(height: 26),
          const SkeletonText(width: 90, height: 11, borderRadius: 999),
          const SizedBox(height: 14),
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 34, height: 34, borderRadius: 999),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SkeletonBox(
                      width: double.infinity,
                      height: 66,
                      borderRadius: 14,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger = isDark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: danger.withValues(alpha: 0.12),
                border: Border.all(color: danger.withValues(alpha: 0.32)),
              ),
              child: Icon(LucideIcons.cloudOff, color: danger, size: 28),
            ),
            const SizedBox(height: 14),
            Text(
              _error ?? 'Ticket não encontrado',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _load(),
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Bolha de mensagem ────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final TicketComment comment;

  const _MessageBubble({required this.comment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final isSupport = comment.isFromUniao;
    // Suporte = violeta (voz da equipe), solicitante = cor da marca.
    final tone = isSupport
        ? (isDark ? AppColors.status.purpleDarkMode : AppColors.status.purple)
        : (isDark
              ? AppColors.primary.primaryDarkMode
              : AppColors.primary.primary);

    final avatar = Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tone.withValues(alpha: isDark ? 0.2 : 0.12),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      alignment: Alignment.center,
      child: isSupport
          ? Icon(LucideIcons.headset, size: 15, color: tone)
          : Text(
              _initials(comment.authorName),
              style: TextStyle(
                color: tone,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
    );

    final bubble = Container(
      padding: const EdgeInsets.fromLTRB(13, 10, 13, 9),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(isSupport ? 4 : 14),
          topRight: Radius.circular(isSupport ? 14 : 4),
          bottomLeft: const Radius.circular(14),
          bottomRight: const Radius.circular(14),
        ),
        border: Border.all(color: tone.withValues(alpha: isDark ? 0.28 : 0.2)),
        boxShadow: ThemeHelpers.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  comment.authorName ?? 'Usuário',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: isDark ? 0.16 : 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isSupport ? 'Suporte' : 'Você',
                  style: TextStyle(
                    color: tone,
                    fontWeight: FontWeight.w800,
                    fontSize: 9.5,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
          if (comment.body.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              comment.body.trim(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w500,
                height: 1.42,
              ),
            ),
          ],
          if (comment.attachments.isNotEmpty) ...[
            const SizedBox(height: 8),
            TicketAttachmentGallery(attachments: comment.attachments),
          ],
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              _formatRelative(comment.createdAt),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: secondary,
              ),
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: isSupport
            ? [
                avatar,
                const SizedBox(width: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 26),
                    child: bubble,
                  ),
                ),
              ]
            : [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 26),
                    child: bubble,
                  ),
                ),
                const SizedBox(width: 8),
                avatar,
              ],
      ),
    );
  }
}
