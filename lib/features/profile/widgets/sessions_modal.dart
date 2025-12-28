import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/profile_service.dart';

/// Modal para gerenciamento de sessões
class SessionsModal {
  static void show({
    required BuildContext context,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
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

      if (mounted) {
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

      if (mounted) {
        if (response.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Sessão encerrada com sucesso'),
              backgroundColor: AppColors.status.success,
            ),
          );
          _loadSessions();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao encerrar sessão'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    }
  }

  Future<void> _endAllOtherSessions() async {
    try {
      final response = await SessionService.instance.endAllOtherSessions();

      if (mounted) {
        if (response.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Todas as outras sessões foram encerradas'),
              backgroundColor: AppColors.status.success,
            ),
          );
          _loadSessions();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao encerrar sessões'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    }
  }

  IconData _getDeviceIcon(String device) {
    final deviceLower = device.toLowerCase();
    if (deviceLower.contains('mobile') || deviceLower.contains('android') || deviceLower.contains('ios')) {
      return Icons.smartphone;
    } else if (deviceLower.contains('tablet') || deviceLower.contains('ipad')) {
      return Icons.tablet;
    }
    return Icons.computer;
  }

  String _formatLastActivity(String lastActivity) {
    try {
      final date = DateTime.parse(lastActivity);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inMinutes < 1) {
        return 'Agora mesmo';
      } else if (difference.inHours < 1) {
        return '${difference.inMinutes} minutos atrás';
      } else if (difference.inDays < 1) {
        return '${difference.inHours} horas atrás';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} dias atrás';
      } else {
        return DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format(date);
      }
    } catch (e) {
      return lastActivity;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(
                  Icons.devices_outlined,
                  color: AppColors.primary.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Sessões Ativas',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

          // Conteúdo
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 48,
                                color: AppColors.status.error,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: ThemeHelpers.textColor(context),
                                ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _loadSessions,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Tentar Novamente'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _sessions.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.devices_other_outlined,
                                    size: 48,
                                    color: ThemeHelpers.textSecondaryColor(context),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Nenhuma sessão ativa',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: ThemeHelpers.textColor(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: _sessions.length,
                            itemBuilder: (context, index) {
                              final session = _sessions[index];
                              return _buildSessionCard(context, theme, isDark, session);
                            },
                          ),
          ),

          // Botão de encerrar todas
          if (!_isLoading && _errorMessage == null && _sessions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _endAllOtherSessions,
                  icon: const Icon(Icons.logout),
                  label: const Text('Encerrar Todas as Outras Sessões'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.status.error,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: BorderSide(
                      color: AppColors.status.error,
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSessionCard(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    Session session,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _getDeviceIcon(session.device),
                    color: AppColors.primary.primary,
                    size: 24,
                  ),
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
                              session.device,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: ThemeHelpers.textColor(context),
                              ),
                            ),
                          ),
                          if (session.isCurrent)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.status.success.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Sessão Atual',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.status.success,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        session.browser,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!session.isCurrent)
                  IconButton(
                    icon: const Icon(Icons.logout, size: 20),
                    onPressed: () => _endSession(session.id),
                    tooltip: 'Encerrar sessão',
                    color: AppColors.status.error,
                  ),
              ],
            ),
            if (session.operatingSystem != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.desktop_windows_outlined,
                    size: 16,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    session.operatingSystem!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    session.ipAddress,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                  ),
                ),
                Icon(
                  Icons.access_time_outlined,
                  size: 16,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatLastActivity(session.lastActivity),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}




