import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/whatsapp_models.dart';
import '../services/whatsapp_service.dart';
import '../widgets/whatsapp_conversation_card.dart'
    show WhatsAppAvatar, whatsAppSourceIcon;
import '../widgets/whatsapp_message_bubble.dart';
import '../widgets/whatsapp_send_template_sheet.dart';

/// Tela **Conversa do WhatsApp** (`/whatsapp/:phoneNumber`) — thread de
/// mensagens de um contato, com envio de texto (canal oficial ou QR Code) e
/// de template quando a janela de 24h da API oficial está fechada.
///
/// Paridade com o `WhatsAppConversationViewer.tsx` do painel:
/// - mensagens do backend em ordem desc (paginação por offset);
/// - marca as recebidas como lidas ao abrir;
/// - texto livre só com QR Code ativo OU janela de 24h aberta;
/// - "Finalizar conversa" tira a thread das abas ativas.
class WhatsAppConversationPage extends StatefulWidget {
  final String phoneNumber;
  final WhatsAppConversation? conversation;

  const WhatsAppConversationPage({
    super.key,
    required this.phoneNumber,
    this.conversation,
  });

  @override
  State<WhatsAppConversationPage> createState() =>
      _WhatsAppConversationPageState();
}

class _WhatsAppConversationPageState extends State<WhatsAppConversationPage> {
  static const int _pageSize = 50;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _composerController = TextEditingController();
  final FocusNode _composerFocus = FocusNode();

  /// Mensagens em ordem cronológica (mais antiga → mais recente).
  List<WhatsAppMessage> _messages = const [];
  int _total = 0;
  bool _loading = true;
  bool _loadingOlder = false;
  String? _error;
  bool _sending = false;
  WhatsAppIntegrationStatus? _integrationStatus;
  Timer? _pollTimer;

  bool get _hasOlder => _messages.length < _total;

  bool get _canSend =>
      ModuleAccessService.instance.hasPermission('whatsapp:send');

  /// Canal não oficial (QR Code) ativo para o atendimento?
  bool get _usesUnofficial => _integrationStatus?.usesUnofficialChat ?? false;

  /// Última mensagem recebida do contato (para a janela de 24h).
  WhatsAppMessage? get _lastInbound {
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].isInbound) return _messages[i];
    }
    return null;
  }

  /// Janela de 24h da API oficial — paridade com o painel: aberta se a última
  /// mensagem do contato tem menos de 24h.
  bool get _is24hWindowOpen {
    final last = _lastInbound?.createdAt;
    if (last == null) return false;
    return DateTime.now().difference(last.toLocal()).inHours < 24;
  }

  /// Texto livre permitido? QR Code sempre; oficial exige janela aberta.
  bool get _canSendFreeText => _usesUnofficial || _is24hWindowOpen;

  String get _displayName {
    final c = widget.conversation;
    if (c != null && c.displayName.trim().isNotEmpty) return c.displayName;
    final fromMessages = _messages
        .where((m) => (m.contactName ?? '').trim().isNotEmpty)
        .map((m) => m.contactName!.trim());
    if (fromMessages.isNotEmpty) return fromMessages.last;
    return formatWhatsAppPhone(widget.phoneNumber);
  }

  String? get _clientId =>
      widget.conversation?.clientId ??
      _messages.where((m) => m.clientId != null).map((m) => m.clientId).lastOrNull;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    // Poll leve enquanto a thread está aberta (o painel usa socket/poll).
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && !_loading && !_sending) _syncLatest();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _scrollController.dispose();
    _composerController.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    unawaited(_loadIntegrationStatus());
    await _loadMessages();
  }

  Future<void> _loadIntegrationStatus() async {
    final status = await WhatsAppService.instance.getIntegrationStatus();
    if (!mounted) return;
    setState(() => _integrationStatus = status);
  }

  Future<void> _loadMessages() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await WhatsAppService.instance.getMessages(
      phoneNumber: widget.phoneNumber,
      limit: _pageSize,
      offset: 0,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        // Backend devolve desc (mais recente primeiro) → inverte p/ cronológica.
        _messages = res.data!.messages.reversed.toList();
        _total = res.data!.total;
      } else {
        _error = res.message ?? 'Erro ao carregar mensagens';
      }
    });
    if (res.success) _markInboundAsRead();
  }

  /// Ressincroniza a primeira página sem "piscar" a tela (poll / pós-envio).
  Future<void> _syncLatest() async {
    final res = await WhatsAppService.instance.getMessages(
      phoneNumber: widget.phoneNumber,
      limit: _pageSize,
      offset: 0,
    );
    if (!mounted || !res.success || res.data == null) return;
    final latest = res.data!.messages.reversed.toList();
    // Preserva as páginas antigas já carregadas: mantém as mensagens que não
    // estão na primeira página e anexa a página nova.
    final latestIds = latest.map((m) => m.id).toSet();
    final older = _messages.where((m) => !latestIds.contains(m.id)).toList();
    final hadNew = latest.length + older.length != _messages.length;
    setState(() {
      _messages = [...older, ...latest];
      _total = res.data!.total;
    });
    if (hadNew) _markInboundAsRead();
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasOlder) return;
    setState(() => _loadingOlder = true);
    final res = await WhatsAppService.instance.getMessages(
      phoneNumber: widget.phoneNumber,
      limit: _pageSize,
      offset: _messages.length,
    );
    if (!mounted) return;
    setState(() {
      _loadingOlder = false;
      if (res.success && res.data != null) {
        final older = res.data!.messages.reversed.toList();
        final existing = _messages.map((m) => m.id).toSet();
        _messages = [
          ...older.where((m) => !existing.contains(m.id)),
          ..._messages,
        ];
        _total = res.data!.total;
      }
    });
  }

  /// Marca como lidas as recebidas ainda não lidas (page atual) — espelha o
  /// comportamento do painel ao abrir a conversa.
  void _markInboundAsRead() {
    final unread = _messages.where((m) => m.isUnread).take(40).toList();
    if (unread.isEmpty) return;
    unawaited(Future.wait(
      unread.map((m) => WhatsAppService.instance.markAsRead(m.id)),
    ));
  }

  // ─── Ações ───────────────────────────────────────────────────────────────

  Future<void> _sendText() async {
    final text = _composerController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final res = await WhatsAppService.instance.sendText(
      to: widget.phoneNumber,
      message: text,
      clientId: _clientId,
      viaUnofficial: _usesUnofficial,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (res.success) {
      _composerController.clear();
      await _syncLatest();
      _scrollToBottom();
    } else {
      _showSnack(res.message ?? 'Erro ao enviar mensagem', isError: true);
    }
  }

  Future<void> _openTemplateSheet() async {
    final sent = await WhatsAppSendTemplateSheet.show(
      context,
      phoneNumber: widget.phoneNumber,
      clientId: _clientId,
    );
    if (!mounted) return;
    if (sent) {
      _showSnack('Template enviado.');
      await _syncLatest();
      _scrollToBottom();
    }
  }

  Future<void> _finalizeConversation() async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: ThemeHelpers.cardBackgroundColor(ctx),
        title: Text(
          'Finalizar conversa?',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: ThemeHelpers.textColor(ctx),
          ),
        ),
        content: Text(
          'A conversa sai das abas de atendimento. Se o contato mandar uma '
          'nova mensagem, ela reabre automaticamente.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: ThemeHelpers.textSecondaryColor(ctx),
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor:
                  Theme.of(ctx).brightness == Brightness.dark
                      ? AppColors.primary.primaryDarkMode
                      : AppColors.primary.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final res = await WhatsAppService.instance
        .finalizeConversation(widget.phoneNumber);
    if (!mounted) return;
    if (res.success) {
      _showSnack('Conversa finalizada.');
      Navigator.of(context).maybePop(true);
    } else {
      _showSnack(res.message ?? 'Erro ao finalizar conversa', isError: true);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? (isDark ? AppColors.status.errorDarkMode : AppColors.status.error)
            : (isDark
                ? AppColors.status.greenDarkMode
                : AppColors.status.green),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _scrollToBottom() {
    // Lista reversa: o "fundo" (mensagem mais recente) é o offset 0.
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'WhatsApp',
      showBottomNavigation: false,
      body: Column(
        children: [
          _buildContactHeader(context),
          Expanded(child: _buildThread(context)),
          _buildComposerArea(context),
        ],
      ),
    );
  }

  // ─── Cabeçalho do contato (compacto, estilo iOS) ─────────────────────────

  Widget _buildContactHeader(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    final last = _messages.isNotEmpty ? _messages.last : null;
    final avatarUrl = widget.conversation?.lastMessage?.contactAvatarUrl ??
        last?.contactAvatarUrl;

    // Origem do canal — resolve pela última mensagem; cai no status global.
    var source = last?.integrationSource ?? WhatsAppIntegrationSource.unknown;
    if (source == WhatsAppIntegrationSource.unknown &&
        _integrationStatus != null &&
        _integrationStatus!.hasAnyChannel) {
      source = _integrationStatus!.chatSource;
    }

    final assigned = (last?.assignedToName ??
            widget.conversation?.lastMessage?.assignedToName ??
            '')
        .trim();

    // Linha de status compacta: telefone · canal · atendente.
    final statusParts = <String>[formatWhatsAppPhone(widget.phoneNumber)];
    if (source != WhatsAppIntegrationSource.unknown) {
      statusParts.add(source.label);
    }
    if (assigned.isNotEmpty) statusParts.add(assigned.split(' ').first);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 9, 8, 9),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: Row(
        children: [
          WhatsAppAvatar(name: _displayName, imageUrl: avatarUrl, size: 40),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _displayName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                    letterSpacing: -0.3,
                    fontSize: 16,
                    height: 1.15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (source != WhatsAppIntegrationSource.unknown) ...[
                      Icon(
                        whatsAppSourceIcon(source),
                        size: 11,
                        color: secondary.withValues(alpha: 0.85),
                      ),
                      const SizedBox(width: 3.5),
                    ],
                    Flexible(
                      child: Text(
                        statusParts.join(' · '),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: secondary,
                          fontWeight: FontWeight.w500,
                          fontSize: 11.5,
                          height: 1.2,
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
          PopupMenuButton<String>(
            icon: Icon(LucideIcons.ellipsisVertical,
                size: 19, color: secondary),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            color: ThemeHelpers.cardBackgroundColor(context),
            onSelected: (value) {
              switch (value) {
                case 'template':
                  _openTemplateSheet();
                  break;
                case 'finalize':
                  _finalizeConversation();
                  break;
                case 'refresh':
                  _loadMessages();
                  break;
              }
            },
            itemBuilder: (ctx) => [
              if (_canSend)
                PopupMenuItem(
                  value: 'template',
                  child: _menuRow(ctx, LucideIcons.badgeCheck,
                      'Enviar template'),
                ),
              PopupMenuItem(
                value: 'refresh',
                child: _menuRow(ctx, LucideIcons.refreshCw, 'Atualizar'),
              ),
              PopupMenuItem(
                value: 'finalize',
                child: _menuRow(
                    ctx, LucideIcons.circleCheckBig, 'Finalizar conversa'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _menuRow(BuildContext context, IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 16, color: ThemeHelpers.textSecondaryColor(context)),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: ThemeHelpers.textColor(context),
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
          ),
        ),
      ],
    );
  }

  // ─── Thread ──────────────────────────────────────────────────────────────

  /// Chave de "remetente" para agrupamento de bolhas sequenciais — contato,
  /// IA ou usuário do sistema.
  static String _authorKey(WhatsAppMessage m) {
    if (!m.isOutbound) return 'in';
    if (m.isAiResponse) return 'out-ai';
    return 'out-${m.userId ?? m.userName ?? ''}';
  }

  Widget _buildThread(BuildContext context) {
    if (_loading && _messages.isEmpty) return _buildSkeleton(context);
    if (_error != null && _messages.isEmpty) return _buildError(context);
    if (_messages.isEmpty) return _buildEmpty(context);

    // Monta em ordem cronológica com separadores de dia e agrupamento de
    // mensagens sequenciais do mesmo remetente; inverte no final — com
    // `reverse: true` a mensagem mais recente fica colada no composer.
    final children = <Widget>[];
    DateTime? currentDay;
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      final created = m.createdAt?.toLocal();
      var dayChanged = false;
      if (created != null) {
        final day = DateTime(created.year, created.month, created.day);
        if (currentDay == null || day != currentDay) {
          currentDay = day;
          dayChanged = true;
          children.add(WhatsAppDaySeparator(date: day));
        }
      }

      final prev = i > 0 ? _messages[i - 1] : null;
      final isFirst =
          dayChanged || prev == null || _authorKey(prev) != _authorKey(m);

      // Última do grupo: a próxima não existe, muda de remetente ou de dia.
      var isLast = true;
      if (i < _messages.length - 1) {
        final next = _messages[i + 1];
        if (_authorKey(next) == _authorKey(m)) {
          final nc = next.createdAt?.toLocal();
          final sameDay = nc != null &&
              created != null &&
              nc.year == created.year &&
              nc.month == created.month &&
              nc.day == created.day;
          isLast = !(sameDay || (nc == null && created == null));
        }
      }

      children.add(WhatsAppMessageBubble(
        message: m,
        isFirstInGroup: isFirst,
        isLastInGroup: isLast,
      ));
    }

    if (_hasOlder || _loadingOlder) {
      children.insert(
        0,
        Padding(
          padding: const EdgeInsets.only(bottom: 10, top: 2),
          child: Center(
            child: _loadingOlder
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                  )
                : OutlinedButton.icon(
                    onPressed: _loadOlder,
                    icon: const Icon(LucideIcons.history, size: 14),
                    label: const Text('Carregar mensagens anteriores'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          ThemeHelpers.textSecondaryColor(context),
                      side: BorderSide(
                          color: ThemeHelpers.borderColor(context)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
          ),
        ),
      );
    }

    return ListView(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      children: children.reversed.toList(),
    );
  }

  Widget _buildSkeleton(BuildContext context) {
    // Fiel à thread nova: bolhas agrupadas (margem menor dentro do grupo).
    Widget bubble({
      required bool own,
      required double width,
      bool grouped = false,
      double height = 46,
    }) {
      return Align(
        alignment: own ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.only(bottom: grouped ? 2 : 10),
          child: SkeletonBox(width: width, height: height, borderRadius: 18),
        ),
      );
    }

    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      children: [
        bubble(own: false, width: 210, height: 56),
        bubble(own: true, width: 180, grouped: true),
        bubble(own: true, width: 140),
        bubble(own: false, width: 240, grouped: true, height: 64),
        bubble(own: false, width: 150),
        bubble(own: true, width: 220, height: 56),
        bubble(own: false, width: 190),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
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
                gradient: LinearGradient(colors: [
                  green.withValues(alpha: 0.18),
                  green.withValues(alpha: 0.06),
                ]),
                border: Border.all(color: green.withValues(alpha: 0.32)),
              ),
              child: Icon(LucideIcons.messagesSquare, color: green, size: 28),
            ),
            const SizedBox(height: 14),
            Text(
              'Nenhuma mensagem ainda',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: ThemeHelpers.textColor(context),
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _canSendFreeText
                  ? 'Envie a primeira mensagem pelo campo abaixo.'
                  : 'Envie um template para iniciar a conversa pela API oficial.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
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
              _error ?? 'Erro ao carregar mensagens',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loadMessages,
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Composer ────────────────────────────────────────────────────────────

  Widget _buildComposerArea(BuildContext context) {
    if (!_canSend) return const SizedBox.shrink();
    // Aguardando primeiro load para decidir a UI do composer.
    if (_loading && _messages.isEmpty && _integrationStatus == null) {
      return const SizedBox.shrink();
    }
    if (!_canSendFreeText) return _buildWindowClosedBanner(context);
    return _buildComposer(context);
  }

  /// Banner âmbar quando a janela de 24h da API oficial está fechada —
  /// convite direto para reabrir com template (paridade com o painel).
  Widget _buildWindowClosedBanner(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.backgroundColor(context),
        border: Border(
          top: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: amber.withValues(alpha: isDark ? 0.13 : 0.09),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: amber.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.clock3, size: 15, color: amber),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      _lastInbound == null
                          ? 'Conversa ainda não iniciada pelo contato'
                          : 'Janela de 24h expirada',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: amber,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'A API oficial só permite texto livre até 24h após a última '
                'mensagem do contato. Envie um template aprovado para reabrir.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _openTemplateSheet,
                  icon: const Icon(LucideIcons.badgeCheck, size: 16),
                  label: const Text(
                    'Enviar template',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: amber,
                    foregroundColor:
                        isDark ? Colors.black : Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Composer estilo iOS: campo arredondado em superfície clara + botão de
  /// enviar circular VERDE (identidade WhatsApp), seta pra cima.
  Widget _buildComposer(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final green =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final fieldFill = ThemeHelpers.cardBackgroundColor(context);
    final hairline = ThemeHelpers.borderLightColor(context);
    final hasText = _composerController.text.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.backgroundColor(context),
        border: Border(top: BorderSide(color: hairline)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Atalho de template (sempre disponível no canal oficial).
            if (!_usesUnofficial)
              Padding(
                padding: const EdgeInsets.only(right: 7, bottom: 3),
                child: InkResponse(
                  radius: 21,
                  onTap: _openTemplateSheet,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: fieldFill,
                      shape: BoxShape.circle,
                      border: Border.all(color: hairline),
                    ),
                    child:
                        Icon(LucideIcons.badgeCheck, size: 18, color: secondary),
                  ),
                ),
              ),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: fieldFill,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.10)
                        : Colors.black.withValues(alpha: 0.08),
                    width: 0.8,
                  ),
                ),
                child: TextField(
                  controller: _composerController,
                  focusNode: _composerFocus,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  cursorColor: green,
                  style: TextStyle(
                    color: ThemeHelpers.textColor(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                    letterSpacing: -0.1,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Mensagem',
                    hintStyle: TextStyle(
                      color: secondary.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w400,
                      fontSize: 15,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 11.5),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            const SizedBox(width: 7),
            Padding(
              padding: const EdgeInsets.only(bottom: 1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: !hasText || _sending
                      ? green.withValues(alpha: isDark ? 0.35 : 0.4)
                      : green,
                  shape: BoxShape.circle,
                  boxShadow: !hasText || _sending
                      ? null
                      : [
                          BoxShadow(
                            color: green.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                            spreadRadius: -2,
                          ),
                        ],
                ),
                child: Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _sending ? null : _sendText,
                    child: Center(
                      child: _sending
                          ? const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              LucideIcons.arrowUp,
                              size: 21,
                              color: Colors.white,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
