import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../services/property_settings_service.dart';
import '../widgets/property_settings_kit.dart';
import 'owner_data_visibility_page.dart';
import 'property_approval_settings_page.dart';
import 'property_form_settings_page.dart';
import 'property_protected_fields_page.dart';

/// Hub "Configurações de imóveis" — reúne as telas de configuração que a
/// web tem em rotas soltas (`/properties/form-settings`,
/// `/properties/approval-settings`, `/properties/protected-fields-config`,
/// `/properties/owner-data-visibility`) e lista só as que o usuário pode
/// abrir. Use [isAvailable] para decidir se mostra a entrada no menu.
class PropertySettingsHubPage extends StatelessWidget {
  const PropertySettingsHubPage({super.key});

  static ModuleAccessService get _access => ModuleAccessService.instance;

  static bool get _module =>
      _access.isModuleAvailableForCompany(PropertySettingsGates.moduleId);

  static bool _manage() => PropertySettingsGates.canManageApprovalSettings(
        role: _access.userRole,
        explicitPermissions: _access.userPermissionNames,
        moduleAvailable: _module,
      );

  /// "Regras do formulário" (web: `property:manage_approval_settings`,
  /// `noRoleBypass` — mas o back e o `hasPermission` do web liberam
  /// master/admin; gestor só com a permissão explícita).
  static bool canOpenFormSettings() => _manage();

  /// "Configuração de aprovações" (`property:manage_approval_settings`).
  static bool canOpenApprovalSettings() => _manage();

  /// "Campos protegidos" (`property:manage_approval_settings`).
  static bool canOpenProtectedFields() => _manage();

  /// "Dados do proprietário": admin/master OU
  /// `property:view_protected_owner_data` explícita.
  static bool canOpenOwnerDataVisibility() =>
      PropertySettingsGates.canViewOwnerData(
        role: _access.userRole,
        explicitPermissions: _access.userPermissionNames,
        moduleAvailable: _module,
      );

  /// Alguma das telas abre para este usuário.
  static bool isAvailable() =>
      canOpenFormSettings() ||
      canOpenApprovalSettings() ||
      canOpenProtectedFields() ||
      canOpenOwnerDataVisibility();

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Configurações de imóveis',
      showBottomNavigation: false,
      body: ListenableBuilder(
        listenable: ModuleAccessService.instance,
        builder: (context, _) => _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final entries = <_HubEntry>[
      if (canOpenFormSettings())
        _HubEntry(
          icon: LucideIcons.listChecks,
          color: PsPalette.indigo(context),
          title: 'Regras do formulário',
          description:
              'Campos obrigatórios além do mínimo do sistema, equipes no '
              'seletor, o que acontece com os imóveis de quem é desativado e '
              'o catálogo de cômodos e infraestrutura.',
          tags: const ['Campos', 'Equipes', 'Sucessão', 'Catálogo'],
          builder: (_) => const PropertyFormSettingsPage(),
        ),
      if (canOpenApprovalSettings())
        _HubEntry(
          icon: LucideIcons.badgeCheck,
          color: PsPalette.primary(context),
          title: 'Aprovações',
          description:
              'Regras do fluxo de aprovação (disponibilidade, publicação, '
              'autorização do proprietário), votação por aprovadores e quem '
              'está autorizado a aprovar.',
          tags: const ['Regras', 'Votação', 'Aprovadores'],
          builder: (_) => const PropertyApprovalSettingsPage(),
        ),
      if (canOpenProtectedFields())
        _HubEntry(
          icon: LucideIcons.lock,
          color: PsPalette.amber(context),
          title: 'Campos protegidos',
          description:
              'Faz toda alteração de dados da ficha virar uma solicitação '
              'para os aprovadores de edição.',
          tags: const ['Solicitações', 'Aprovadores de edição'],
          builder: (_) => const PropertyProtectedFieldsPage(),
        ),
      if (canOpenOwnerDataVisibility())
        _HubEntry(
          icon: LucideIcons.eyeOff,
          color: PsPalette.teal(context),
          title: 'Dados do proprietário',
          description:
              'Quem enxerga os dados do proprietário nos imóveis com '
              'proprietário restrito, além de admin e master.',
          tags: const ['Sigilo', 'Habilitados'],
          builder: (_) => const OwnerDataVisibilityPage(),
        ),
    ];

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        PsHero(
          eyebrow: 'Imóveis · Configuração',
          title: 'Configurações de imóveis',
          icon: LucideIcons.settings2,
          color: PsPalette.indigo(context),
          subtitle:
              'As regras valem para toda a empresa: cadastro, aprovações, '
              'campos protegidos e o sigilo do proprietário.',
          chips: [
            PsChip(
              label: entries.length == 1
                  ? 'tela disponível para você'
                  : 'telas disponíveis para você',
              value: '${entries.length}',
              color: PsPalette.indigo(context),
              icon: LucideIcons.layoutGrid,
            ),
          ],
        ),
        if (entries.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: PsEmpty(
              icon: LucideIcons.lock,
              text: 'Você não tem acesso a nenhuma configuração de imóveis. '
                  'Peça a um administrador a permissão de gerenciar as '
                  'configurações de aprovação.',
            ),
          ),
        for (final e in entries) _HubCard(entry: e),
      ],
    );
  }
}

class _HubEntry {
  const _HubEntry({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.tags,
    required this.builder,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final List<String> tags;
  final WidgetBuilder builder;
}

class _HubCard extends StatelessWidget {
  const _HubCard({required this.entry});

  final _HubEntry entry;

  @override
  Widget build(BuildContext context) {
    final dark = psDark(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final c = entry.color;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: entry.builder)),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: c.withValues(alpha: dark ? 0.3 : 0.18)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  c.withValues(alpha: dark ? 0.12 : 0.05),
                  Colors.transparent,
                ],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PsRoundel(icon: entry.icon, color: c, size: 46, filled: true),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.description,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.42,
                          color: muted,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final t in entry.tags)
                            PsBadge(label: t, color: c),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 12, left: 4),
                  child: Icon(LucideIcons.chevronRight, size: 20, color: muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
