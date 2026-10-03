import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../models/approval_chat_inbox_item.dart';
import '../services/property_approval_service.dart';
import '../widgets/approval_info_sheets.dart';

/// **Caixa de conversas de aprovação** (imoveis-33) — equivalente mobile da
/// `ApprovalChatInboxPage` do web (`/properties/approval-chats`): uma linha
/// por imóvel × fila (cadastro ou site), com prévia da última mensagem e
/// contador de não lidas. Tocar abre a conversa (o mesmo sheet do card da
/// fila) e marca como vista (`POST .../approval-thread/mark-seen`).
class ApprovalChatInboxPage extends StatefulWidget {
  const ApprovalChatInboxPage({super.key});

  @override
  State<ApprovalChatInboxPage> createState() => _ApprovalChatInboxPageState();
}

class _ApprovalChatInboxPageState extends State<ApprovalChatInboxPage> {
  final TextEditingController _search = TextEditingController();

  bool _loading = true;
  String? _error;
  int _errorStatus = 0;
  List<ApprovalChatInboxItem> _items = const [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool subtle = false}) async {
    if (!subtle) {
      setState(() {
        _loading = true;
        _error = null;
        _errorStatus = 0;
      });
    }
    final res = await PropertyApprovalService.instance.getApprovalChatInbox();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success) {
        _items = res.data ?? const [];
        _error = null;
        _errorStatus = 0;
      } else if (!subtle) {
        _error = res.message ?? 'Não foi possível carregar as conversas.';
        _errorStatus = res.statusCode;
      }
    });
  }

  Color _tone(BuildContext context, ApprovalChatInboxItem it) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (it.isPublication) {
      return isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    }
    return isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;
  }

  Future<void> _open(ApprovalChatInboxItem it) async {
    final queue =
        it.isPublication ? ApprovalType.publication : ApprovalType.availability;
    // Marca como vista ao abrir (o web zera o contador ao abrir a conversa).
    // Otimista: o número some na hora; a lista recarrega ao fechar.
    if (it.hasUnread) {
      setState(() {
        _items = [
          for (final x in _items) x.key == it.key ? x.markedAsSeen() : x,
        ];
      });
    }
    PropertyApprovalService.instance
        .markApprovalThreadSeen(it.propertyId, context: queue);
    await showApprovalThreadSheet(
      context: context,
      propertyId: it.propertyId,
      propertyTitle: it.propertyTitle.isEmpty ? 'Imóvel' : it.propertyTitle,
      queue: queue,
      tone: _tone(context, it),
    );
    if (!mounted) return;
    await _load(subtle: true);
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Conversas de aprovação',
      showBottomNavigation: false,
      showDrawer: false,
      body: RefreshIndicator(
        onRefresh: () => _load(subtle: true),
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final filtered = ApprovalChatInboxItem.filter(_items, _query);
    final unread = ApprovalChatInboxItem.totalUnread(_items);
    final availability = _items.where((x) => !x.isPublication).length;
    final publication = _items.length - availability;

    final header = <Widget>[
      Text(
        'INBOX DE APROVAÇÕES',
        style: theme.textTheme.labelSmall?.copyWith(
          color: secondary,
          fontWeight: FontWeight.w800,
          letterSpacing: 2.2,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'Diálogo de cada imóvel por fila — cadastro ou publicação no site.',
        style: theme.textTheme.bodySmall?.copyWith(color: secondary, height: 1.4),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _StatChip(
            icon: LucideIcons.messagesSquare,
            label: 'Conversas',
            value: _items.length,
            tone: const Color(0xFF7C3AED),
          ),
          _StatChip(
            icon: LucideIcons.messageSquareDot,
            label: 'Não lidas',
            value: unread,
            tone: const Color(0xFFE11D48),
          ),
          _StatChip(
            icon: LucideIcons.house,
            label: 'Cadastro',
            value: availability,
            tone: const Color(0xFFD97706),
          ),
          _StatChip(
            icon: LucideIcons.globe,
            label: 'Site',
            value: publication,
            tone: const Color(0xFF059669),
          ),
        ],
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _search,
        onChanged: (v) => setState(() => _query = v),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Buscar por imóvel, código ou mensagem',
          prefixIcon: const Icon(LucideIcons.search, size: 18),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Limpar',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                ),
          isDense: true,
          filled: true,
          fillColor: ThemeHelpers.cardBackgroundColor(context),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: ThemeHelpers.borderColor(context)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: ThemeHelpers.borderColor(context)),
          ),
        ),
      ),
      const SizedBox(height: 10),
    ];

    Widget content;
    if (_loading) {
      content = const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_error != null) {
      content = Padding(
        padding: const EdgeInsets.only(top: 24),
        child: AppErrorState.fromApi(
          statusCode: _errorStatus,
          message: _error,
          onRetry: _load,
        ),
      );
    } else if (filtered.isEmpty) {
      content = _EmptyInbox(searching: _items.isNotEmpty);
    } else {
      content = Column(
        children: [
          for (var i = 0; i < filtered.length; i++)
            _InboxRow(
              item: filtered[i],
              tone: _tone(context, filtered[i]),
              onTap: () => _open(filtered[i]),
              onOpenProperty: () => Navigator.of(context).pushNamed(
                AppRoutes.propertyDetails(filtered[i].propertyId),
              ),
            ).animate(key: ValueKey('inbox-${filtered[i].key}')).fadeIn(
                  delay: Duration(milliseconds: 30 * (i < 10 ? i : 10)),
                  duration: 200.ms,
                ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
      children: [...header, content],
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final Color tone;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.16 : 0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: tone),
          const SizedBox(width: 6),
          Text(
            '$label ',
            style: TextStyle(
              color: ThemeHelpers.textSecondaryColor(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            '$value',
            style: TextStyle(
              color: tone,
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _InboxRow extends StatelessWidget {
  final ApprovalChatInboxItem item;
  final Color tone;
  final VoidCallback onTap;
  final VoidCallback onOpenProperty;

  const _InboxRow({
    required this.item,
    required this.tone,
    required this.onTap,
    required this.onOpenProperty,
  });

  String get _initials {
    final words = item.propertyTitle
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      final w = words.first;
      return (w.length > 1 ? w.substring(0, 2) : w).toUpperCase();
    }
    return (words.first[0] + words.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final unreadTone =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final time = formatApprovalInboxTime(item.lastMessageAt);

    return InkWell(
      onTap: onTap,
      onLongPress: onOpenProperty,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
          ),
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        tone.withValues(alpha: 0.85),
                        tone.withValues(alpha: 0.55),
                      ],
                    ),
                  ),
                  child: Text(
                    _initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ThemeHelpers.backgroundColor(context),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      item.isPublication ? LucideIcons.globe : LucideIcons.house,
                      size: 12,
                      color: tone,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.propertyTitle.isEmpty
                              ? 'Sem título'
                              : item.propertyTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: item.hasUnread
                                ? FontWeight.w900
                                : FontWeight.w700,
                            color: ThemeHelpers.textColor(context),
                          ),
                        ),
                      ),
                      if (time.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          time,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: item.hasUnread ? unreadTone : secondary,
                            fontWeight: item.hasUnread
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.previewLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: item.hasUnread
                                ? ThemeHelpers.textColor(context)
                                : secondary,
                            fontWeight: item.hasUnread
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: tone.withValues(alpha: isDark ? 0.18 : 0.10),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          item.isPublication ? 'Site' : 'Cadastro',
                          style: TextStyle(
                            color: tone,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (item.hasUnread) ...[
                        const SizedBox(width: 6),
                        Container(
                          constraints: const BoxConstraints(minWidth: 20),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: unreadTone,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${item.unreadCount}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Abrir imóvel',
              visualDensity: VisualDensity.compact,
              onPressed: onOpenProperty,
              icon: Icon(LucideIcons.externalLink, size: 17, color: secondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyInbox extends StatelessWidget {
  final bool searching;

  const _EmptyInbox({required this.searching});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    const tone = Color(0xFF7C3AED);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 8),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tone.withValues(alpha: 0.10),
              border: Border.all(color: tone.withValues(alpha: 0.28)),
            ),
            child: const Icon(LucideIcons.messagesSquare, color: tone, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            searching ? 'Nenhum resultado' : 'Nada por aqui ainda',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            searching
                ? 'Tente outro termo na busca.'
                : 'Envie a primeira mensagem na fila de aprovações ou na ficha do imóvel para aparecer aqui.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
