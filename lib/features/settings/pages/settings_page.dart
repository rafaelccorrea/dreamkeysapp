import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/skeleton_box.dart';
import '../../../../shared/services/settings_service.dart';
import '../../../../shared/services/profile_service.dart';
import '../../../../shared/services/theme_service.dart';

/// Tela de Configurações
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isLoading = true;
  Settings? _settings;
  Profile? _profile;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    debugPrint('⚙️ [SETTINGS PAGE] Iniciando carregamento de dados');

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      debugPrint('⚙️ [SETTINGS PAGE] Buscando configurações...');
      final settingsResponse = await SettingsService.instance.getSettings();
      debugPrint(
        '⚙️ [SETTINGS PAGE] Configurações recebidas: success=${settingsResponse.success}',
      );

      debugPrint('⚙️ [SETTINGS PAGE] Buscando perfil...');
      final profileResponse = await ProfileService.instance.getProfile();
      debugPrint(
        '⚙️ [SETTINGS PAGE] Perfil recebido: success=${profileResponse.success}',
      );

      if (mounted) {
        setState(() {
          if (settingsResponse.success && settingsResponse.data != null) {
            _settings = settingsResponse.data;
            debugPrint(
              '✅ [SETTINGS PAGE] Configurações carregadas com sucesso',
            );
          } else {
            debugPrint('⚠️ [SETTINGS PAGE] Configurações não foram carregadas');
          }

          if (profileResponse.success && profileResponse.data != null) {
            _profile = profileResponse.data;
            debugPrint('✅ [SETTINGS PAGE] Perfil carregado com sucesso');
          } else {
            debugPrint('⚠️ [SETTINGS PAGE] Perfil não foi carregado');
          }

          _isLoading = false;

          if (_settings == null && _profile == null) {
            _errorMessage = 'Erro ao carregar dados';
            debugPrint('❌ [SETTINGS PAGE] Nenhum dado foi carregado');
          } else {
            debugPrint(
              '✅ [SETTINGS PAGE] Dados carregados: Settings=${_settings != null}, Profile=${_profile != null}',
            );
          }
        });
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [SETTINGS PAGE] Erro ao carregar dados: $e');
      debugPrint('❌ [SETTINGS PAGE] StackTrace: $stackTrace');
      if (mounted) {
        setState(() {
          _errorMessage = 'Erro ao conectar com o servidor';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateNotificationSetting({
    required bool Function(NotificationSettings) getValue,
    required NotificationSettings Function(NotificationSettings, bool) setValue,
  }) async {
    if (_settings == null) {
      debugPrint(
        '⚠️ [SETTINGS PAGE] Tentativa de atualizar configuração sem dados carregados',
      );
      return;
    }

    final currentNotifications = _settings!.notifications;
    final oldValue = getValue(currentNotifications);
    final newValue = !oldValue;

    debugPrint('⚙️ [SETTINGS PAGE] Atualizando configuração de notificação');
    debugPrint('   - Valor antigo: $oldValue');
    debugPrint('   - Novo valor: $newValue');

    final updatedNotifications = setValue(currentNotifications, newValue);
    final updatedSettings = Settings(
      notifications: updatedNotifications,
      language: _settings!.language,
      timezone: _settings!.timezone,
    );

    debugPrint('⚙️ [SETTINGS PAGE] Atualizando estado local...');
    setState(() {
      _settings = updatedSettings;
    });

    debugPrint('⚙️ [SETTINGS PAGE] Enviando atualização para API...');
    final response = await SettingsService.instance.updateSettings(
      updatedSettings,
    );

    debugPrint(
      '⚙️ [SETTINGS PAGE] Resposta da API: success=${response.success}',
    );

    if (response.success) {
      debugPrint('✅ [SETTINGS PAGE] Configuração atualizada com sucesso!');
      if (response.data != null) {
        setState(() {
          _settings = response.data;
        });
      }
    } else if (mounted) {
      debugPrint('❌ [SETTINGS PAGE] Erro ao atualizar: ${response.message}');
      // Reverter mudança em caso de erro
      setState(() {
        _settings = Settings(
          notifications: currentNotifications,
          language: _settings!.language,
          timezone: _settings!.timezone,
        );
      });
      debugPrint('⚙️ [SETTINGS PAGE] Configuração revertida ao valor anterior');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  response.message ?? 'Erro ao atualizar configuração',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.status.error,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Configurações',
      currentBottomNavIndex: 4,
      showBottomNavigation: true,
      body: _isLoading
          ? _buildSkeleton(context, theme)
          : _errorMessage != null && _settings == null
          ? _buildErrorState(context, theme)
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Seção de Notificações
                    _buildNotificationsSection(context, theme),
                    const SizedBox(height: 32),

                    // Seção de Preferências de Notificação
                    _buildNotificationPreferencesSection(context, theme),
                    const SizedBox(height: 32),

                    // Seção de Aparência
                    _buildAppearanceSection(context, theme),
                    const SizedBox(height: 32),

                    // Seção de Conta
                    _buildAccountSection(context, theme),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSkeleton(BuildContext context, ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Skeleton do perfil
          SkeletonCard(
            child: Row(
              children: [
                SkeletonBox(width: 64, height: 64, borderRadius: 32),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonText(
                        width: 150,
                        height: 20,
                        margin: const EdgeInsets.only(bottom: 8),
                      ),
                      SkeletonText(width: 200, height: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Skeleton de seções
          SkeletonText(
            width: 120,
            height: 18,
            margin: const EdgeInsets.only(bottom: 16),
          ),
          SkeletonCard(
            child: Column(
              children: List.generate(
                3,
                (index) => Padding(
                  padding: EdgeInsets.only(bottom: index < 2 ? 16 : 0),
                  child: Row(
                    children: [
                      SkeletonBox(width: 24, height: 24, borderRadius: 12),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonText(
                              width: 100,
                              height: 16,
                              margin: const EdgeInsets.only(bottom: 4),
                            ),
                            SkeletonText(width: 180, height: 14),
                          ],
                        ),
                      ),
                      SkeletonBox(width: 48, height: 28, borderRadius: 14),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Segunda seção
          SkeletonText(
            width: 120,
            height: 18,
            margin: const EdgeInsets.only(bottom: 16),
          ),
          SkeletonCard(
            child: Column(
              children: List.generate(
                2,
                (index) => Padding(
                  padding: EdgeInsets.only(bottom: index < 1 ? 16 : 0),
                  child: Row(
                    children: [
                      SkeletonBox(width: 24, height: 24, borderRadius: 12),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonText(
                              width: 120,
                              height: 16,
                              margin: const EdgeInsets.only(bottom: 4),
                            ),
                            SkeletonText(width: 200, height: 14),
                          ],
                        ),
                      ),
                      SkeletonBox(width: 48, height: 28, borderRadius: 14),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Terceira seção
          SkeletonText(
            width: 120,
            height: 18,
            margin: const EdgeInsets.only(bottom: 16),
          ),
          SkeletonCard(
            child: Column(
              children: List.generate(
                2,
                (index) => Padding(
                  padding: EdgeInsets.only(bottom: index < 1 ? 12 : 0),
                  child: Row(
                    children: [
                      SkeletonBox(width: 24, height: 24, borderRadius: 12),
                      const SizedBox(width: 16),
                      Expanded(child: SkeletonText(width: 150, height: 16)),
                      const Icon(
                        Icons.chevron_right,
                        color: Colors.transparent,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: AppColors.status.error),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Erro ao carregar dados',
              style: theme.textTheme.titleMedium?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary.primary,
                foregroundColor: ThemeHelpers.onPrimaryColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationsSection(BuildContext context, ThemeData theme) {
    final notifications = _settings?.notifications;

    return _buildSection(
      context: context,
      theme: theme,
      title: 'Notificações',
      children: [
        _buildSwitchTile(
          context: context,
          theme: theme,
          title: 'Email',
          subtitle: 'Receber notificações por email',
          value: notifications?.email ?? true,
          icon: Icons.email_outlined,
          onChanged: (value) {
            _updateNotificationSetting(
              getValue: (n) => n.email,
              setValue: (n, v) => n.copyWith(email: v),
            );
          },
        ),
        _buildSwitchTile(
          context: context,
          theme: theme,
          title: 'Push',
          subtitle: 'Receber notificações push',
          value: notifications?.push ?? true,
          icon: Icons.notifications_outlined,
          onChanged: (value) {
            _updateNotificationSetting(
              getValue: (n) => n.push,
              setValue: (n, v) => n.copyWith(push: v),
            );
          },
        ),
        _buildSwitchTile(
          context: context,
          theme: theme,
          title: 'SMS',
          subtitle: 'Receber notificações por SMS',
          value: notifications?.sms ?? false,
          icon: Icons.sms_outlined,
          onChanged: (value) {
            _updateNotificationSetting(
              getValue: (n) => n.sms,
              setValue: (n, v) => n.copyWith(sms: v),
            );
          },
        ),
      ],
    );
  }

  Widget _buildNotificationPreferencesSection(
    BuildContext context,
    ThemeData theme,
  ) {
    final notifications = _settings?.notifications;

    return _buildSection(
      context: context,
      theme: theme,
      title: 'Preferências de Notificação',
      children: [
        _buildSwitchTile(
          context: context,
          theme: theme,
          title: 'Novos Matches',
          subtitle: 'Notificar sobre novos matches',
          value: notifications?.newMatches ?? true,
          icon: Icons.favorite_outline,
          onChanged: (value) {
            _updateNotificationSetting(
              getValue: (n) => n.newMatches,
              setValue: (n, v) => n.copyWith(newMatches: v),
            );
          },
        ),
        _buildSwitchTile(
          context: context,
          theme: theme,
          title: 'Novas Mensagens',
          subtitle: 'Notificar sobre novas mensagens',
          value: notifications?.newMessages ?? true,
          icon: Icons.chat_bubble_outline,
          onChanged: (value) {
            _updateNotificationSetting(
              getValue: (n) => n.newMessages,
              setValue: (n, v) => n.copyWith(newMessages: v),
            );
          },
        ),
        _buildSwitchTile(
          context: context,
          theme: theme,
          title: 'Lembretes de Compromissos',
          subtitle: 'Notificar sobre lembretes de compromissos',
          value: notifications?.appointmentReminders ?? true,
          icon: Icons.calendar_today_outlined,
          onChanged: (value) {
            _updateNotificationSetting(
              getValue: (n) => n.appointmentReminders,
              setValue: (n, v) => n.copyWith(appointmentReminders: v),
            );
          },
        ),
      ],
    );
  }

  Widget _buildAppearanceSection(BuildContext context, ThemeData theme) {
    return _buildSection(
      context: context,
      theme: theme,
      title: 'Aparência',
      children: [_buildThemeTile(context, theme)],
    );
  }

  Widget _buildThemeTile(BuildContext context, ThemeData theme) {
    final themeService = ThemeService.instance;

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.primary.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          themeService.getThemeIcon(),
          color: AppColors.primary.primary,
          size: 20,
        ),
      ),
      title: Text(
        'Tema',
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: ThemeHelpers.textColor(context),
        ),
      ),
      subtitle: Text(
        themeService.getThemeName(),
        style: theme.textTheme.bodySmall?.copyWith(
          color: ThemeHelpers.textSecondaryColor(context),
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: ThemeHelpers.textSecondaryColor(context),
      ),
      onTap: () {
        _showThemeDialog(context);
      },
    );
  }

  void _showThemeDialog(BuildContext context) {
    final themeService = ThemeService.instance;
    final currentThemeMode = themeService.themeMode;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Escolher Tema'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<ThemeMode>(
              title: const Text('Claro'),
              subtitle: const Text('Usar tema claro'),
              value: ThemeMode.light,
              groupValue: currentThemeMode,
              onChanged: (value) async {
                if (value != null) {
                  await themeService.setThemeMode(value);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                }
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('Escuro'),
              subtitle: const Text('Usar tema escuro'),
              value: ThemeMode.dark,
              groupValue: currentThemeMode,
              onChanged: (value) async {
                if (value != null) {
                  await themeService.setThemeMode(value);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                }
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('Sistema'),
              subtitle: const Text('Seguir configuração do sistema'),
              value: ThemeMode.system,
              groupValue: currentThemeMode,
              onChanged: (value) async {
                if (value != null) {
                  await themeService.setThemeMode(value);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountSection(BuildContext context, ThemeData theme) {
    return _buildSection(
      context: context,
      theme: theme,
      title: 'Conta',
      children: [
        _buildListTile(
          context: context,
          theme: theme,
          title: 'Perfil',
          subtitle: 'Editar informações do perfil',
          icon: Icons.person_outline,
          onTap: () {
            // TODO: Navegar para tela de perfil
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Tela de perfil em breve'),
                duration: Duration(seconds: 2),
              ),
            );
          },
        ),
        _buildListTile(
          context: context,
          theme: theme,
          title: 'Alterar Senha',
          subtitle: 'Atualizar sua senha',
          icon: Icons.lock_outline,
          onTap: () {
            _showChangePasswordDialog(context);
          },
        ),
      ],
    );
  }

  Widget _buildSection({
    required BuildContext context,
    required ThemeData theme,
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: ThemeHelpers.textColor(context),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: ThemeHelpers.shadowColor(context),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildSwitchTile({
    required BuildContext context,
    required ThemeData theme,
    required String title,
    required String subtitle,
    required bool value,
    required IconData icon,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.primary.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.primary.primary, size: 20),
      ),
      title: Text(
        title,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: ThemeHelpers.textColor(context),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: ThemeHelpers.textSecondaryColor(context),
        ),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeTrackColor: AppColors.primary.primary.withOpacity(0.5),
        activeThumbColor: AppColors.primary.primary,
      ),
    );
  }

  Widget _buildListTile({
    required BuildContext context,
    required ThemeData theme,
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.primary.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.primary.primary, size: 20),
      ),
      title: Text(
        title,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: ThemeHelpers.textColor(context),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: ThemeHelpers.textSecondaryColor(context),
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: ThemeHelpers.textSecondaryColor(context),
      ),
      onTap: onTap,
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Alterar Senha'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: currentPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Senha Atual',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Campo obrigatório';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: newPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Nova Senha',
                      prefixIcon: Icon(Icons.lock),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Campo obrigatório';
                      }
                      if (value.length < 6) {
                        return 'Senha deve ter no mínimo 6 caracteres';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: confirmPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirmar Nova Senha',
                      prefixIcon: Icon(Icons.lock),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Campo obrigatório';
                      }
                      if (value != newPasswordController.text) {
                        return 'Senhas não coincidem';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading
                  ? null
                  : () {
                      Navigator.of(context).pop();
                    },
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (formKey.currentState!.validate()) {
                        setDialogState(() {
                          isLoading = true;
                        });

                        final response = await ProfileService.instance
                            .changePassword(
                              currentPassword: currentPasswordController.text,
                              newPassword: newPasswordController.text,
                            );

                        if (context.mounted) {
                          setDialogState(() {
                            isLoading = false;
                          });

                          if (response.success) {
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const Icon(
                                      Icons.check_circle,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'Senha alterada com sucesso',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                backgroundColor: AppColors.status.success,
                                behavior: SnackBarBehavior.floating,
                                margin: const EdgeInsets.all(16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const Icon(
                                      Icons.error_outline,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        response.message ??
                                            'Erro ao alterar senha',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                backgroundColor: AppColors.status.error,
                                behavior: SnackBarBehavior.floating,
                                margin: const EdgeInsets.all(16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          }
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary.primary,
                foregroundColor: ThemeHelpers.onPrimaryColor(context),
              ),
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('Alterar'),
            ),
          ],
        ),
      ),
    );
  }
}
