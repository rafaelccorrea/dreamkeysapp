import 'package:flutter/material.dart';

import '../../../../core/routes/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/profile_service.dart';
import '../../../../shared/services/settings_service.dart';
import '../../../../shared/services/theme_service.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/skeleton_box.dart';
import '../../../../shared/widgets/vivid_chrome.dart';

/// Tela de Configurações — layout vívido (hero + cartões) alinhado às cores da marca.
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

  Color _accent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.primary.primaryDarkMode
          : AppColors.primary.primary;

  Future<void> _loadData() async {
    debugPrint('⚙️ [SETTINGS PAGE] Iniciando carregamento de dados');

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final settingsResponse = await SettingsService.instance.getSettings();
      final profileResponse = await ProfileService.instance.getProfile();

      if (mounted) {
        setState(() {
          if (settingsResponse.success && settingsResponse.data != null) {
            _settings = settingsResponse.data;
          }
          if (profileResponse.success && profileResponse.data != null) {
            _profile = profileResponse.data;
          }
          _isLoading = false;
          if (_settings == null && _profile == null) {
            _errorMessage = 'Erro ao carregar dados';
          }
        });
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [SETTINGS PAGE] Erro: $e\n$stackTrace');
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
    if (_settings == null) return;

    final currentNotifications = _settings!.notifications;
    final oldValue = getValue(currentNotifications);
    final newValue = !oldValue;

    final updatedNotifications = setValue(currentNotifications, newValue);
    final updatedSettings = Settings(
      notifications: updatedNotifications,
      language: _settings!.language,
      timezone: _settings!.timezone,
    );

    setState(() {
      _settings = updatedSettings;
    });

    final response = await SettingsService.instance.updateSettings(
      updatedSettings,
    );

    if (response.success) {
      if (response.data != null) {
        setState(() => _settings = response.data);
      }
    } else if (mounted) {
      setState(() {
        _settings = Settings(
          notifications: currentNotifications,
          language: _settings!.language,
          timezone: _settings!.timezone,
        );
      });
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
    final accent = _accent(context);

    return AppScaffold(
      title: 'Configurações',
      currentBottomNavIndex: 4,
      showBottomNavigation: true,
      body: _isLoading
          ? _buildSkeleton(context, theme, accent)
          : _errorMessage != null && _settings == null && _profile == null
          ? _buildErrorState(context, theme, accent)
          : RefreshIndicator(
              color: accent,
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    VividChrome.heroBanner(
                      context,
                      accent: accent,
                      eyebrow: 'Preferências',
                      title: 'Configurações',
                      subtitle:
                          'Canais de alerta, eventos e aparência do app. Os interruptores gravam no servidor quando a API responde.',
                      icon: Icons.settings_suggest_rounded,
                    ),
                    const SizedBox(height: 20),
                    if (_profile != null)
                      _buildProfileSpotlight(context, theme, accent, _profile!),
                    if (_profile != null) const SizedBox(height: 22),
                    _buildNotificationsSection(context, theme, accent),
                    const SizedBox(height: 22),
                    _buildNotificationPreferencesSection(context, theme, accent),
                    const SizedBox(height: 22),
                    _buildAppearanceSection(context, theme, accent),
                    const SizedBox(height: 22),
                    _buildAccountSection(context, theme, accent),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSkeleton(
    BuildContext context,
    ThemeData theme,
    Color accent,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkeletonBox(
            width: double.infinity,
            height: 118,
            borderRadius: 20,
          ),
          const SizedBox(height: 20),
          SkeletonBox(
            width: double.infinity,
            height: 112,
            borderRadius: 22,
          ),
          const SizedBox(height: 22),
          SkeletonText(
            width: 160,
            height: 18,
            margin: const EdgeInsets.only(bottom: 10),
          ),
          SkeletonCard(
            child: Column(
              children: List.generate(
                3,
                (i) => Padding(
                  padding: EdgeInsets.only(bottom: i < 2 ? 14 : 0),
                  child: Row(
                    children: [
                      SkeletonBox(width: 46, height: 46, borderRadius: 14),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonText(
                              width: 120,
                              height: 15,
                              margin: const EdgeInsets.only(bottom: 6),
                            ),
                            SkeletonText(width: 200, height: 12),
                          ],
                        ),
                      ),
                      SkeletonBox(width: 48, height: 30, borderRadius: 16),
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

  Widget _buildErrorState(
    BuildContext context,
    ThemeData theme,
    Color accent,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        VividChrome.heroBanner(
          context,
          accent: accent,
          eyebrow: 'Erro',
          title: 'Não foi possível carregar',
          subtitle:
              'Verifique a ligação e tente novamente. Se o problema persistir, contacte o suporte.',
          icon: Icons.cloud_off_rounded,
        ),
        const SizedBox(height: 20),
        VividChrome.mutedMessage(
          context,
          _errorMessage ?? 'Erro ao carregar dados',
          accent: accent,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _loadData,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Tentar novamente'),
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: ThemeHelpers.onPrimaryColor(context),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileSpotlight(
    BuildContext context,
    ThemeData theme,
    Color accent,
    Profile p,
  ) {
    final borderSoft = Colors.white.withValues(alpha: 0.35);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.2),
            AppColors.secondary.secondary.withValues(alpha: 0.12),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: accent.withValues(alpha: 0.38)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: borderSoft, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipOval(
                child: p.avatar != null && p.avatar!.isNotEmpty
                    ? Image.network(
                        p.avatar!,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _avatarFallback(accent),
                      )
                    : _avatarFallback(accent),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    p.email,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _roleChip(context, accent, p.role),
                      if (p.companyName != null &&
                          p.companyName!.trim().isNotEmpty)
                        _roleChip(
                          context,
                          AppColors.secondary.secondary,
                          p.companyName!.trim(),
                          filled: false,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatarFallback(Color accent) {
    return Container(
      width: 72,
      height: 72,
      color: accent.withValues(alpha: 0.15),
      alignment: Alignment.center,
      child: Icon(Icons.person_rounded, size: 36, color: accent),
    );
  }

  Widget _roleChip(
    BuildContext context,
    Color tone,
    String label, {
    bool filled = true,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: filled ? tone.withValues(alpha: 0.22) : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: tone.withValues(alpha: filled ? 0.35 : 0.55),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: ThemeHelpers.textColor(context),
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildVividSection({
    required BuildContext context,
    required ThemeData theme,
    required Color accent,
    required String sectionTitle,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VividChrome.sectionLabel(context, sectionTitle, accent: accent),
        VividChrome.insetCard(
          context,
          accent: accent,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: ThemeHelpers.borderColor(context)
                        .withValues(alpha: 0.35),
                  ),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNotificationsSection(
    BuildContext context,
    ThemeData theme,
    Color accent,
  ) {
    final notifications = _settings?.notifications;

    return _buildVividSection(
      context: context,
      theme: theme,
      accent: accent,
      sectionTitle: 'Canais de notificação',
      children: [
        _buildSwitchRow(
          context: context,
          theme: theme,
          accent: accent,
          title: 'Email',
          subtitle: 'Receber notificações por email',
          value: notifications?.email ?? true,
          icon: Icons.email_outlined,
          onChanged: (_) {
            _updateNotificationSetting(
              getValue: (n) => n.email,
              setValue: (n, v) => n.copyWith(email: v),
            );
          },
        ),
        _buildSwitchRow(
          context: context,
          theme: theme,
          accent: accent,
          title: 'Push',
          subtitle: 'Receber notificações push',
          value: notifications?.push ?? true,
          icon: Icons.notifications_active_outlined,
          onChanged: (_) {
            _updateNotificationSetting(
              getValue: (n) => n.push,
              setValue: (n, v) => n.copyWith(push: v),
            );
          },
        ),
        _buildSwitchRow(
          context: context,
          theme: theme,
          accent: accent,
          title: 'SMS',
          subtitle: 'Receber notificações por SMS',
          value: notifications?.sms ?? false,
          icon: Icons.sms_outlined,
          onChanged: (_) {
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
    Color accent,
  ) {
    final notifications = _settings?.notifications;

    return _buildVividSection(
      context: context,
      theme: theme,
      accent: accent,
      sectionTitle: 'O que notificar',
      children: [
        _buildSwitchRow(
          context: context,
          theme: theme,
          accent: accent,
          title: 'Novos matches',
          subtitle: 'Alertas quando surgirem matches',
          value: notifications?.newMatches ?? true,
          icon: Icons.favorite_rounded,
          onChanged: (_) {
            _updateNotificationSetting(
              getValue: (n) => n.newMatches,
              setValue: (n, v) => n.copyWith(newMatches: v),
            );
          },
        ),
        _buildSwitchRow(
          context: context,
          theme: theme,
          accent: accent,
          title: 'Novas mensagens',
          subtitle: 'Alertas de conversas',
          value: notifications?.newMessages ?? true,
          icon: Icons.chat_bubble_outline,
          onChanged: (_) {
            _updateNotificationSetting(
              getValue: (n) => n.newMessages,
              setValue: (n, v) => n.copyWith(newMessages: v),
            );
          },
        ),
        _buildSwitchRow(
          context: context,
          theme: theme,
          accent: accent,
          title: 'Compromissos',
          subtitle: 'Lembretes de agenda',
          value: notifications?.appointmentReminders ?? true,
          icon: Icons.event_available_outlined,
          onChanged: (_) {
            _updateNotificationSetting(
              getValue: (n) => n.appointmentReminders,
              setValue: (n, v) => n.copyWith(appointmentReminders: v),
            );
          },
        ),
      ],
    );
  }

  Widget _buildAppearanceSection(
    BuildContext context,
    ThemeData theme,
    Color accent,
  ) {
    return _buildVividSection(
      context: context,
      theme: theme,
      accent: accent,
      sectionTitle: 'Aparência',
      children: [
        _buildThemeRow(context, theme, accent),
      ],
    );
  }

  Widget _buildThemeRow(
    BuildContext context,
    ThemeData theme,
    Color accent,
  ) {
    final themeService = ThemeService.instance;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showThemeSheet(context, accent),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              _iconPlate(context, accent, themeService.getThemeIcon()),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tema do app',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      themeService.getThemeName(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: accent,
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showThemeSheet(BuildContext context, Color accent) async {
    final themeService = ThemeService.instance;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.paddingOf(sheetContext).bottom + 16,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: ThemeHelpers.cardBackgroundColor(sheetContext),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: accent.withValues(alpha: 0.25),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 28,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ThemeHelpers.textSecondaryColor(sheetContext)
                        .withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Tema',
                          style: Theme.of(sheetContext)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Column(
                    children: [
                      _themeOptionTile(
                        sheetContext,
                        accent,
                        ThemeMode.light,
                        'Claro',
                        'Melhor em ambientes luminosos',
                        Icons.light_mode_rounded,
                        themeService,
                      ),
                      _themeOptionTile(
                        sheetContext,
                        accent,
                        ThemeMode.dark,
                        'Escuro',
                        'Menos cansaço visual à noite',
                        Icons.dark_mode_rounded,
                        themeService,
                      ),
                      _themeOptionTile(
                        sheetContext,
                        accent,
                        ThemeMode.system,
                        'Sistema',
                        'Segue o tema do telemóvel',
                        Icons.brightness_auto_rounded,
                        themeService,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _themeOptionTile(
    BuildContext sheetContext,
    Color accent,
    ThemeMode mode,
    String title,
    String subtitle,
    IconData icon,
    ThemeService themeService,
  ) {
    final selected = themeService.themeMode == mode;
    final theme = Theme.of(sheetContext);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            await themeService.setThemeMode(mode);
            if (sheetContext.mounted) Navigator.pop(sheetContext);
          },
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: selected
                  ? LinearGradient(
                      colors: [
                        accent.withValues(alpha: 0.2),
                        AppColors.secondary.secondary
                            .withValues(alpha: 0.1),
                      ],
                    )
                  : null,
              color: selected
                  ? null
                  : ThemeHelpers.cardBackgroundColor(sheetContext),
              border: Border.all(
                color: selected
                    ? accent.withValues(alpha: 0.55)
                    : ThemeHelpers.borderColor(sheetContext)
                        .withValues(alpha: 0.4),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  _iconPlate(sheetContext, accent, icon),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color:
                                ThemeHelpers.textSecondaryColor(sheetContext),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    color: selected
                        ? accent
                        : ThemeHelpers.textSecondaryColor(sheetContext),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAccountSection(
    BuildContext context,
    ThemeData theme,
    Color accent,
  ) {
    return _buildVividSection(
      context: context,
      theme: theme,
      accent: accent,
      sectionTitle: 'Conta',
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.pushNamed(context, AppRoutes.profile);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  _iconPlate(context, accent, Icons.person_rounded),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Perfil',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: ThemeHelpers.textColor(context),
                          ),
                        ),
                        Text(
                          'Nome, contacto e foto',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ThemeHelpers.textSecondaryColor(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: accent,
                    size: 28,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _iconPlate(BuildContext context, Color accent, IconData icon) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.22),
            accent.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: accent, size: 22),
    );
  }

  Widget _buildSwitchRow({
    required BuildContext context,
    required ThemeData theme,
    required Color accent,
    required String title,
    required String subtitle,
    required bool value,
    required IconData icon,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _iconPlate(context, accent, icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: accent,
            activeTrackColor: accent.withValues(alpha: 0.45),
            inactiveTrackColor:
                ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }
}
