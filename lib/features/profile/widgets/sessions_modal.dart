import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/profile_service.dart';

/// Modal **flush** de gerenciamento de sessões/dispositivos.
///
/// Paleta coerente: **primary** no cabeçalho, **verde** para a sessão atual,
/// **vermelho** apenas nas ações de encerrar. Linhas flush (sem Card pesado).
class SessionsModal {
  /// Retorna quando o sheet é fechado (útil para atualizar contagem na tela pai).
  static Future<void> show({required BuildContext context}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (context) => const _SessionsModalContent(),
    );
  }
}

class _SessionsModalContent extends StatefulWidget {
  const _SessionsModalContent();

  @override
  State<_SessionsModalContent> createState() => _SessionsModalContentState();
}

class _SessionsModalContentState extends State<_SessionsModalContent> {
  List<Session> _sessions = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final response = await SessionService.instance.getSessions();
      if (!mounted) return;
      if (response.success && response.data != null) {
        setState(() {
          _sessions = response.data!;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = response.message ?? 'Erro ao carregar sessões';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Erro: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _endSession(String sessionId) async {
    try {
      final response = await SessionService.instance.endSession(sessionId);
      if (!mounted) return;
      if (response.success) {
        _snack('Sessão encerrada', AppColors.status.success);
        _loadSessions();
      } else {
        _snack(response.message ?? 'Erro ao encerrar sessão',
            AppColors.status.error);
      }
    } catch (e) {
      if (mounted) _snack('Erro: ${e.toString()}', AppColors.status.error);
    }
  }

  Future<void> _endAllOtherSessions() async {
    try {
      final response = await SessionService.instance.endAllOtherSessions();
      if (!mounted) return;
      if (response.success) {
        _snack('Outras sessões encerradas', AppColors.status.success);
        _loadSessions();
      } else {
        _snack(response.message ?? 'Erro ao encerrar sessões',
            AppColors.status.error);
      }
    } catch (e) {
      if (mounted) _snack('Erro: ${e.toString()}', AppColors.status.error);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  IconData _getDeviceIcon(String device) {
    final d = device.toLowerCase();
    if (d.contains('mobile') || d.contains('android') || d.contains('ios')) {
      return Icons.smartphone_rounded;
    } else if (d.contains('tablet') || d.contains('ipad')) {
      return Icons.tablet_rounded;
    }
    return Icons.computer_rounded;
  }

  String _formatLastActivity(String lastActivity) {
    try {
      final date = DateTime.parse(lastActivity);
      final diff = DateTime.now().difference(date);
      if (diff.inMinutes < 1) return 'Agora mesmo';
      if (diff.inHours < 1) return '${diff.inMinutes} min atrás';
      if (diff.inDays < 1) return '${diff.inHours}h atrás';
      if (diff.inDays < 7) return '${diff.inDays}d atrás';
      return DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(date);
    } catch (_) {
      return lastActivity;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final others = _sessions.where((s) => !s.isCurrent).length;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: primary.withValues(alpha: isDark ? 0.22 : 0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.16),
            blurRadius: 28,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  primary.withValues(alpha: 0.55),
                  primary.withValues(alpha: 0.28),
                ]),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
              child: _buildHeader(context, theme, isDark, primary, others),
            ),
            Flexible(child: _buildBody(context, theme, isDark, primary)),
            if (!_isLoading && _errorMessage == null && others > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: OutlinedButton.icon(
                  onPressed: _endAllOtherSessions,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.status.error,
                    side: BorderSide(
                      color: AppColors.status.error.withValues(alpha: 0.5),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Encerrar as outras sessões'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    Color primary,
    int others,
  ) {
    final subtitle = _isLoading
        ? 'Carregando…'
        : _sessions.isEmpty
            ? 'Nenhuma sessão ativa'
            : '${_sessions.length} ativa${_sessions.length == 1 ? '' : 's'}'
                '${others > 0 ? ' · $others em outro${others == 1 ? '' : 's'} aparelho${others == 1 ? '' : 's'}' : ''}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                primary.withValues(alpha: isDark ? 0.42 : 0.22),
                primary.withValues(alpha: isDark ? 0.22 : 0.12),
              ],
            ),
            border: Border.all(color: primary.withValues(alpha: 0.4)),
          ),
          child: Icon(Icons.devices_rounded, color: primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sessões e dispositivos',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                  color: ThemeHelpers.textColor(context),
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ),
            ],
          ),
        ),
        _CircleClose(onTap: () => Navigator.pop(context)),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    Color primary,
  ) {
    if (_isLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(color: primary)),
      );
    }
    if (_errorMessage != null) {
      return _stateMessage(
        context,
        theme,
        icon: Icons.cloud_off_rounded,
        color: AppColors.status.error,
        title: 'Não foi possível carregar',
        body: _errorMessage!,
        action: TextButton.icon(
          onPressed: _loadSessions,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Tentar novamente'),
          style: TextButton.styleFrom(foregroundColor: primary),
        ),
      );
    }
    if (_sessions.isEmpty) {
      return _stateMessage(
        context,
        theme,
        icon: Icons.devices_other_rounded,
        color: ThemeHelpers.textSecondaryColor(context),
        title: 'Nenhuma sessão ativa',
        body: 'Quando você entrar em um dispositivo, ele aparece aqui.',
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: _sessions.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: ThemeHelpers.borderLightColor(context),
      ),
      itemBuilder: (context, i) =>
          _buildSessionRow(context, theme, isDark, primary, _sessions[i]),
    );
  }

  Widget _stateMessage(
    BuildContext context,
    ThemeData theme, {
    required IconData icon,
    required Color color,
    required String title,
    required String body,
    Widget? action,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 36, 28, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              height: 1.4,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 12), action],
        ],
      ),
    );
  }

  Widget _buildSessionRow(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    Color primary,
    Session session,
  ) {
    final success =
        isDark ? AppColors.status.successDarkMode : AppColors.status.success;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final tone = session.isCurrent ? success : primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: tone.withValues(alpha: isDark ? 0.16 : 0.1),
              border: Border.all(color: tone.withValues(alpha: 0.28)),
            ),
            child: Icon(_getDeviceIcon(session.device), color: tone, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        session.device.isEmpty
                            ? 'Dispositivo'
                            : session.device,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: ThemeHelpers.textColor(context),
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (session.isCurrent) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: success.withValues(alpha: isDark ? 0.18 : 0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: success.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          'Este aparelho',
                          style: TextStyle(
                            color: success,
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (session.browser.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    session.operatingSystem != null &&
                            session.operatingSystem!.isNotEmpty
                        ? '${session.browser} · ${session.operatingSystem}'
                        : session.browser,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _metaChip(theme, secondary, Icons.schedule_rounded,
                        _formatLastActivity(session.lastActivity)),
                    if (session.ipAddress.isNotEmpty)
                      _metaChip(theme, secondary, Icons.public_rounded,
                          session.ipAddress),
                  ],
                ),
              ],
            ),
          ),
          if (!session.isCurrent)
            Padding(
              padding: const EdgeInsets.only(left: 6, top: 2),
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _endSession(session.id),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: danger.withValues(alpha: isDark ? 0.14 : 0.08),
                      border: Border.all(
                        color: danger.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Icon(Icons.logout_rounded, size: 16, color: danger),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _metaChip(
    ThemeData theme,
    Color color,
    IconData icon,
    String text,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

/// Botão circular de fechar — coerente com os demais sheets refinados.
class _CircleClose extends StatelessWidget {
  const _CircleClose({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: secondary.withValues(alpha: isDark ? 0.14 : 0.08),
            border: Border.all(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
            ),
          ),
          child: Icon(Icons.close_rounded, size: 19, color: secondary),
        ),
      ),
    );
  }
}
