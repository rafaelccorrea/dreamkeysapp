import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/zezin_models.dart';
import '../services/zezin_service.dart';
import '../widgets/zezin_history_sheet.dart';
import '../widgets/zezin_message_bubble.dart';

/// Chat com o **Zezin** — assistente de IA do CRM (paridade com
/// `ZezinAskPage.tsx` do imobx-front). Interface conversacional com
/// streaming, histórico de conversas (threads), sugestões de pergunta e
/// follow-ups gerados por IA.
///
/// Disponibilidade é decidida pelo backend (`GET /whatsapp/zezin/availability`
/// — admin/dono + plano Pro + módulo `ai_assistant`); aqui apenas espelhamos
/// o estado, como no web.
class ZezinAskPage extends StatefulWidget {
  const ZezinAskPage({super.key});

  @override
  State<ZezinAskPage> createState() => _ZezinAskPageState();
}

class _ZezinAskPageState extends State<ZezinAskPage> {
  static const double _kPadH = 16;

  /// Rota central da tela de configuração (constante local até a fiação
  /// central promover para `AppRoutes.zezinConfig`).
  static const String _configRoute = '/zezin/config';

  final ZezinService _service = ZezinService.instance;

  ZezinAvailability? _availability;
  bool _availabilityLoading = true;
  String? _availabilityError;

  List<ZezinSuggestedQuestion> _suggestions = const [];
  List<ZezinSuggestedQuestion> _followUps = const [];
  bool _suggestionsVisible = true;

  List<ZezinThreadSummary> _threads = const [];
  bool _threadsLoaded = false;
  bool _threadsLoading = false;

  /// Conversa atual (threadId = sectionId nas próximas mensagens).
  String? _threadId;
  String? _threadTitle;
  bool _threadMessagesLoading = false;
  String? _threadMessagesError;

  List<ZezinChatMessage> _messages = [];
  bool _sending = false;

  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ─── Cores ───────────────────────────────────────────────────────────────

  /// Violeta = identidade da IA (paridade com o #8B5CF6 do Zezin no web).
  Color _tone(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.status.purpleDarkMode
        : AppColors.status.purple;
  }

  // ─── Dados ───────────────────────────────────────────────────────────────

  Future<void> _bootstrap() async {
    setState(() {
      _availabilityLoading = true;
      _availabilityError = null;
    });
    final res = await _service.getAvailability();
    if (!mounted) return;
    if (!res.success) {
      setState(() {
        _availabilityLoading = false;
        _availabilityError =
            res.message ?? 'Não foi possível verificar o Zezin.';
      });
      return;
    }
    setState(() {
      _availabilityLoading = false;
      _availability = res.data ?? ZezinAvailability.unavailable;
    });
    if (_availability?.available == true) {
      // Sugestões + histórico em paralelo (nenhum bloqueia o chat).
      // ignore: unawaited_futures
      _loadSuggestions();
      // ignore: unawaited_futures
      _loadThreads();
    }
  }

  Future<void> _loadSuggestions() async {
    final res = await _service.getSuggestedQuestions();
    if (!mounted) return;
    setState(() {
      _suggestions = res.success ? (res.data ?? const []) : const [];
    });
  }

  Future<void> _loadFollowUps() async {
    if (_messages.length < 2) return;
    final res = await _service.getFollowUpSuggestions();
    if (!mounted) return;
    setState(() {
      _followUps = res.success ? (res.data ?? const []) : const [];
    });
  }

  Future<void> _loadThreads() async {
    if (_threadsLoading) return;
    setState(() => _threadsLoading = true);
    final res = await _service.getHistory(limit: 50);
    if (!mounted) return;
    setState(() {
      _threadsLoading = false;
      _threadsLoaded = true;
      if (res.success) _threads = res.data ?? const [];
    });
  }

  Future<void> _selectThread(ZezinThreadSummary thread) async {
    setState(() {
      _threadId = thread.threadId;
      _threadTitle = thread.title;
      _messages = [];
      _followUps = const [];
      _threadMessagesLoading = true;
      _threadMessagesError = null;
    });
    final res = await _service.getThreadMessages(thread.threadId);
    if (!mounted) return;
    setState(() {
      _threadMessagesLoading = false;
      if (res.success) {
        _messages = ZezinChatMessage.fromHistory(res.data ?? const []);
      } else {
        _threadMessagesError =
            res.message ?? 'Não foi possível carregar a conversa.';
      }
    });
    _scrollToBottom(jump: true);
    if (_messages.length >= 2) {
      // ignore: unawaited_futures
      _loadFollowUps();
    }
  }

  void _newConversation() {
    setState(() {
      _threadId = null;
      _threadTitle = null;
      _messages = [];
      _followUps = const [];
      _threadMessagesError = null;
    });
    _inputFocus.requestFocus();
  }

  /// Título derivado da primeira pergunta (paridade com
  /// `getConversationTitle` do web).
  String _conversationTitle(String userMessage, {int maxLength = 48}) {
    final trimmed = userMessage.trim();
    if (trimmed.isEmpty) return 'Conversa';
    final firstLine = trimmed.split('\n').first.trim();
    final sentence = firstLine.split(RegExp(r'[.!?]')).first.trim();
    final base = sentence.isEmpty ? firstLine : sentence;
    if (base.length <= maxLength) return base;
    final cut = base.substring(0, maxLength);
    final lastSpace = cut.lastIndexOf(' ');
    final end = lastSpace > maxLength * 0.6 ? lastSpace : maxLength;
    return '${cut.substring(0, end).trim()}…';
  }

  /// Atualiza/insere a conversa na lista local do histórico após um envio
  /// bem-sucedido — sem refetch (paridade com o web).
  void _bumpThreadSummary(String conversationId, String lastUserMessage) {
    final exists = _threads.any((t) => t.threadId == conversationId);
    if (exists) {
      _threads = _threads
          .map((t) => t.threadId == conversationId
              ? t.copyWith(
                  updatedAt: DateTime.now(),
                  messageCount: t.messageCount + 1,
                )
              : t)
          .toList();
    } else {
      final title = _conversationTitle(lastUserMessage);
      _threadTitle = title;
      _threads = [
        ZezinThreadSummary(
          threadId: conversationId,
          title: title,
          updatedAt: DateTime.now(),
          messageCount: 1,
        ),
        ..._threads,
      ];
    }
  }

  // ─── Envio (streaming + fallback) ────────────────────────────────────────

  Future<void> _send([String? text]) async {
    final toSend = (text ?? _inputController.text).trim();
    if (toSend.isEmpty || _sending) return;
    _inputController.clear();

    final now = DateTime.now().microsecondsSinceEpoch;
    final userMsg = ZezinChatMessage(
      id: 'user-$now',
      role: ZezinChatRole.user,
      content: toSend,
    );
    final assistantMsg = ZezinChatMessage(
      id: 'assistant-$now',
      role: ZezinChatRole.assistant,
      content: '',
      isStreaming: true,
    );
    setState(() {
      _messages = [..._messages, userMsg, assistantMsg];
      _sending = true;
    });
    _scrollToBottom();

    var receivedAny = false;
    await _service.askStream(
      message: toSend,
      sectionId: _threadId,
      onChunk: (chunk) {
        receivedAny = true;
        if (!mounted) return;
        setState(() => assistantMsg.content += chunk);
        _scrollToBottom();
      },
      onDone: (conversationId) {
        if (!mounted) return;
        setState(() {
          assistantMsg.isStreaming = false;
          _sending = false;
          if (conversationId != null && conversationId.isNotEmpty) {
            _threadId = conversationId;
            _bumpThreadSummary(conversationId, toSend);
          }
          if (!receivedAny && assistantMsg.content.isEmpty) {
            assistantMsg.content =
                'Não recebi resposta do Zezin. Tente novamente.';
            assistantMsg.isError = true;
          }
        });
        _scrollToBottom();
        // Pequeno delay para o backend commitar a conversa antes do
        // follow-up (paridade web).
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) _loadFollowUps();
        });
      },
      onError: (message) {
        if (!mounted) return;
        if (!receivedAny) {
          // Stream falhou antes do primeiro chunk → fallback sem streaming.
          _fallbackAsk(toSend, assistantMsg, message);
          return;
        }
        setState(() {
          _sending = false;
          assistantMsg.isStreaming = false;
          assistantMsg.isError = true;
          assistantMsg.content = assistantMsg.content.isEmpty
              ? message
              : '${assistantMsg.content}\n\n[Erro: $message]';
        });
        _scrollToBottom();
      },
    );
  }

  Future<void> _fallbackAsk(
    String question,
    ZezinChatMessage assistantMsg,
    String streamError,
  ) async {
    final res = await _service.ask(question);
    if (!mounted) return;
    setState(() {
      _sending = false;
      assistantMsg.isStreaming = false;
      if (res.success && (res.data ?? '').trim().isNotEmpty) {
        assistantMsg.content = res.data!.trim();
      } else {
        assistantMsg.content = res.message ?? streamError;
        assistantMsg.isError = true;
      }
    });
    _scrollToBottom();
  }

  void _scrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (jump) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  // ─── Histórico (sheet) ───────────────────────────────────────────────────

  Future<void> _openHistory() async {
    if (!_threadsLoaded && !_threadsLoading) {
      await _loadThreads();
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => ZezinHistorySheet(
        threads: _threads,
        activeThreadId: _threadId,
        onSelect: _selectThread,
        onNewConversation: _newConversation,
        onRename: (threadId, title) async {
          final res = await _service.updateHistoryTitle(threadId, title);
          if (res.success && mounted) {
            setState(() {
              _threads = _threads
                  .map((t) =>
                      t.threadId == threadId ? t.copyWith(title: title) : t)
                  .toList();
              if (_threadId == threadId) _threadTitle = title;
            });
          } else if (mounted) {
            _showSnack(res.message ?? 'Não foi possível atualizar o título.');
          }
          return res.success;
        },
        onDelete: (threadId) async {
          final res = await _service.deleteThread(threadId);
          if (res.success && mounted) {
            setState(() {
              _threads =
                  _threads.where((t) => t.threadId != threadId).toList();
            });
            if (_threadId == threadId) _newConversation();
          } else if (mounted) {
            _showSnack(res.message ?? 'Não foi possível excluir.');
          }
          return res.success;
        },
      ),
    );
    // Sincroniza a lista quando o usuário reabrir depois.
    // ignore: unawaited_futures
    _loadThreads();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Zezin',
      showBottomNavigation: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = _tone(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final available = _availability?.available == true;
    final title = _threadTitle?.trim().isNotEmpty == true
        ? _threadTitle!.trim()
        : 'Pergunte ao Zezin';

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.6),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_kPadH, 10, _kPadH, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [
                    tone.withValues(alpha: isDark ? 0.3 : 0.18),
                    tone.withValues(alpha: isDark ? 0.12 : 0.07),
                  ],
                ),
                border: Border.all(color: tone.withValues(alpha: 0.32)),
              ),
              child: Icon(LucideIcons.bot, color: tone, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: tone,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: tone.withValues(alpha: 0.5),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          'ZEZIN · ASSISTENTE IA',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: tone,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w900,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                      height: 1.05,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Respostas com os dados reais da sua empresa.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (available) ...[
              _headerIconButton(
                context,
                icon: LucideIcons.history,
                tooltip: 'Histórico de conversas',
                onTap: _openHistory,
              ),
              const SizedBox(width: 6),
              _headerIconButton(
                context,
                icon: LucideIcons.squarePen,
                tooltip: 'Nova conversa',
                onTap: _newConversation,
              ),
              const SizedBox(width: 6),
              _headerIconButton(
                context,
                icon: LucideIcons.settings2,
                tooltip: 'Configuração do Zezin',
                onTap: () => Navigator.of(context).pushNamed(_configRoute),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _headerIconButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: isDark
                  ? Colors.white.withValues(alpha: 0.055)
                  : Colors.black.withValues(alpha: 0.04),
            ),
            child: Center(child: Icon(icon, size: 18, color: secondary)),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_availabilityLoading) return _buildChatSkeleton(context);
    if (_availabilityError != null) {
      return _buildErrorState(
        context,
        message: _availabilityError!,
        onRetry: _bootstrap,
      );
    }
    if (_availability?.available != true) return _buildDeniedState(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _buildChatArea(context)),
        _buildSuggestionsStrip(context),
        _buildInputArea(context),
      ],
    );
  }

  // ─── Área do chat ────────────────────────────────────────────────────────

  Widget _buildChatArea(BuildContext context) {
    if (_threadMessagesLoading) return _buildChatSkeleton(context);
    if (_threadMessagesError != null) {
      return _buildErrorState(
        context,
        message: _threadMessagesError!,
        onRetry: () {
          final id = _threadId;
          if (id != null) {
            final thread = _threads.firstWhere(
              (t) => t.threadId == id,
              orElse: () => ZezinThreadSummary(
                threadId: id,
                title: _threadTitle ?? 'Conversa',
              ),
            );
            _selectThread(thread);
          }
        },
      );
    }
    if (_messages.isEmpty) return _buildWelcome(context);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(_kPadH, 16, _kPadH, 12),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        return ZezinMessageBubble(
          key: ValueKey(msg.id),
          message: msg,
        );
      },
    );
  }

  /// Estado inicial — boas-vindas + sugestões de pergunta em lista tocável
  /// (ações no próprio item).
  Widget _buildWelcome(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = _tone(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final configured = _availability?.configConfigured == true;

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(_kPadH, 20, _kPadH, 16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: tone.withValues(alpha: isDark ? 0.28 : 0.18),
            ),
            boxShadow: ThemeHelpers.cardShadow(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(11),
                      gradient: LinearGradient(
                        colors: [
                          tone.withValues(alpha: isDark ? 0.32 : 0.2),
                          tone.withValues(alpha: isDark ? 0.14 : 0.08),
                        ],
                      ),
                    ),
                    child: Icon(LucideIcons.bot, size: 18, color: tone),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Zezin',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: tone,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Oi! Pode me perguntar o que quiser sobre vendas, metas, '
                'leads, imóveis ou clientes — eu uso os dados da empresa e '
                'respondo na hora.'
                '${configured ? ' Se preferir, também atendo pelo WhatsApp no número configurado em Integrações.' : ''}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: ThemeHelpers.textColor(context),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ).animate().fadeIn(duration: 260.ms),
        if (!configured) ...[
          const SizedBox(height: 12),
          _buildConfigNotice(context),
        ],
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 22),
          Row(
            children: [
              Icon(LucideIcons.sparkles, size: 13, color: tone),
              const SizedBox(width: 6),
              Text(
                'SUGESTÕES PARA COMEÇAR',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                  fontSize: 10.5,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Container(
                    height: 1,
                    color: ThemeHelpers.borderLightColor(context)
                        .withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < _suggestions.length && i < 6; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildWelcomeSuggestion(context, _suggestions[i])
                  .animate()
                  .fadeIn(
                    delay: Duration(milliseconds: 60 * i),
                    duration: 220.ms,
                  ),
            ),
        ] else ...[
          const SizedBox(height: 22),
          Center(
            child: Text(
              'Digite sua pergunta abaixo para começar.',
              style: theme.textTheme.bodySmall?.copyWith(color: secondary),
            ),
          ),
        ],
      ],
    );
  }

  /// Aviso discreto quando o WhatsApp do Zezin ainda não foi configurado —
  /// âmbar = atenção; toca e vai direto para a configuração.
  Widget _buildConfigNotice(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pushNamed(_configRoute),
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: amber.withValues(alpha: isDark ? 0.12 : 0.09),
            border: Border.all(color: amber.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.info, size: 16, color: amber),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'WhatsApp ainda não configurado — o chat aqui já funciona; '
                  'configure o número para o Zezin atender também no WhatsApp.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.arrow_forward_rounded, size: 16, color: amber),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeSuggestion(
      BuildContext context, ZezinSuggestedQuestion q) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = _tone(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _sending ? null : () => _send(q.message),
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: ThemeHelpers.cardBackgroundColor(context),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.sparkles, size: 15, color: tone),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  q.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                LucideIcons.arrowUp,
                size: 14,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Sugestões acima do input ────────────────────────────────────────────

  Widget _buildSuggestionsStrip(BuildContext context) {
    // Follow-ups quando a conversa já tem trocas; senão as fixas.
    final useFollowUp = _messages.length >= 2 && _followUps.isNotEmpty;
    final list = useFollowUp ? _followUps : _suggestions;
    // Na tela de boas-vindas as sugestões já aparecem no corpo.
    if (_messages.isEmpty || list.isEmpty || _sending) {
      return const SizedBox.shrink();
    }
    final tone = _tone(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () =>
              setState(() => _suggestionsVisible = !_suggestionsVisible),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(_kPadH, 6, _kPadH, 4),
            child: Row(
              children: [
                Icon(LucideIcons.sparkles, size: 12, color: tone),
                const SizedBox(width: 6),
                Text(
                  useFollowUp ? 'CONTINUE A CONVERSA' : 'SUGESTÕES',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: tone,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.3,
                    fontSize: 9.5,
                  ),
                ),
                const Spacer(),
                Icon(
                  _suggestionsVisible
                      ? Icons.expand_more_rounded
                      : Icons.expand_less_rounded,
                  size: 18,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ],
            ),
          ),
        ),
        if (_suggestionsVisible)
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(_kPadH, 0, _kPadH, 6),
              itemCount: list.length > 8 ? 8 : list.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final q = list[index];
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _send(q.message),
                    borderRadius: BorderRadius.circular(999),
                    child: Ink(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: tone.withValues(alpha: isDark ? 0.12 : 0.07),
                        border:
                            Border.all(color: tone.withValues(alpha: 0.3)),
                      ),
                      child: Center(
                        widthFactor: 1,
                        child: Text(
                          q.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: isDark
                                ? tone
                                : ThemeHelpers.textColor(context),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  // ─── Input ───────────────────────────────────────────────────────────────

  Widget _buildInputArea(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = _tone(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final hasText = _inputController.text.trim().isNotEmpty;
    final canSend = hasText && !_sending;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.6),
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(_kPadH, 10, _kPadH, 10),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: ThemeHelpers.cardBackgroundColor(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                ),
                child: TextField(
                  controller: _inputController,
                  focusNode: _inputFocus,
                  enabled: !_sending,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  textCapitalization: TextCapitalization.sentences,
                  cursorColor: tone,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                  decoration: InputDecoration(
                    hintText: _sending
                        ? 'Zezin está respondendo…'
                        : 'Pergunte algo ao Zezin…',
                    hintStyle: theme.textTheme.bodyMedium?.copyWith(
                      color: secondary.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w500,
                    ),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _send(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: canSend ? () => _send() : null,
                borderRadius: BorderRadius.circular(999),
                child: Ink(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: canSend
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              tone,
                              Color.lerp(tone, const Color(0xFF6366F1), 0.5)!,
                            ],
                          )
                        : null,
                    color: canSend
                        ? null
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.07)
                            : Colors.black.withValues(alpha: 0.06)),
                  ),
                  child: Center(
                    child: _sending
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: tone,
                            ),
                          )
                        : Icon(
                            LucideIcons.send,
                            size: 19,
                            color: canSend ? Colors.white : secondary,
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

  // ─── Estados: skeleton / erro / indisponível ─────────────────────────────

  /// Skeleton fiel ao chat real — bolhas alternadas (usuário à direita,
  /// assistente à esquerda com header).
  Widget _buildChatSkeleton(BuildContext context) {
    Widget bubble({required bool user, required double width}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          mainAxisAlignment:
              user ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            SkeletonBox(
              width: width,
              height: user ? 44 : 76,
              borderRadius: 18,
            ),
          ],
        ),
      );
    }

    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(_kPadH, 16, _kPadH, 16),
      children: [
        bubble(user: true, width: 190),
        bubble(user: false, width: 260),
        bubble(user: true, width: 150),
        bubble(user: false, width: 280),
        bubble(user: true, width: 210),
      ],
    );
  }

  Widget _buildErrorState(
    BuildContext context, {
    required String message,
    required VoidCallback onRetry,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
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
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeniedState(BuildContext context) {
    final theme = Theme.of(context);
    final tone = _tone(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [
                  tone.withValues(alpha: 0.18),
                  tone.withValues(alpha: 0.06),
                ]),
                border: Border.all(color: tone.withValues(alpha: 0.32)),
              ),
              child: Icon(LucideIcons.lock, color: tone, size: 26),
            ),
            const SizedBox(height: 14),
            Text(
              'Zezin não disponível',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: ThemeHelpers.textColor(context),
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'O Zezin é exclusivo para administradores no plano Pro com o '
              'módulo Assistente de IA. Verifique seu plano e permissões.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _bootstrap,
              style: OutlinedButton.styleFrom(
                foregroundColor: tone,
                side: BorderSide(color: tone.withValues(alpha: 0.45)),
              ),
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Verificar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
