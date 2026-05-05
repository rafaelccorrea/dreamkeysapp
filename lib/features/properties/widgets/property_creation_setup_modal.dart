import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/property_service.dart';

/// Modos de origem de endereço — espelho do web `PropertyCreationAddressMode`.
enum PropertyCreationAddressMode {
  standalone,
  condominium,
  empreendimento,
}

extension PropertyCreationAddressModeX on PropertyCreationAddressMode {
  String get value {
    switch (this) {
      case PropertyCreationAddressMode.standalone:
        return 'standalone';
      case PropertyCreationAddressMode.condominium:
        return 'condominium';
      case PropertyCreationAddressMode.empreendimento:
        return 'empreendimento';
    }
  }

  static PropertyCreationAddressMode fromValue(String? v) {
    switch (v) {
      case 'condominium':
        return PropertyCreationAddressMode.condominium;
      case 'empreendimento':
        return PropertyCreationAddressMode.empreendimento;
      default:
        return PropertyCreationAddressMode.standalone;
    }
  }
}

/// Resultado retornado por `Navigator.pop` ao confirmar o setup.
/// Espelho de `PropertyCreationSetupPayload` do web.
class PropertyCreationSetupResult {
  final PropertyType type;
  final String teamId;
  final PropertyCreationAddressMode addressMode;
  final String? condominiumId;
  final String? empreendimentoId;
  final String? condominiumName;
  final String? empreendimentoName;

  const PropertyCreationSetupResult({
    required this.type,
    required this.teamId,
    required this.addressMode,
    this.condominiumId,
    this.empreendimentoId,
    this.condominiumName,
    this.empreendimentoName,
  });
}

/// Página fullscreen de pré-criação de imóvel — paridade total com o web
/// `PropertyCreationSetupModal.tsx`.
///
/// Coleta os 3 campos exigidos antes do wizard:
///  1. **Tipo do imóvel** (5 opções: house, apartment, commercial, land, rural)
///  2. **Equipe** (`teamId`) — vinda de `GET /properties/form-settings`
///  3. **Origem do endereço** (`addressMode`):
///     - `standalone` — endereço próprio
///     - `condominium` — vinculado a um condomínio (precisa permissão
///       `condominium:view` e selecionar o condomínio)
///     - `empreendimento` — vinculado a um empreendimento (precisa permissão
///       `empreendimento:view` e selecionar o empreendimento)
///
/// Regras alinhadas ao web (`PropertyCreationSetupModal.tsx` e
/// `CreatePropertyPage.tsx`):
///  - Botão "Continuar" desabilitado enquanto faltar campo obrigatório.
///  - Permissões desabilitam (não escondem) os modos vinculados.
///  - Ao fechar (X / back) sem confirmar, retorna `null` — o chamador deve
///    voltar para a lista de imóveis (igual `navigate('/properties')` do web).
///  - `initialTeamId` se válido → seleciona; caso contrário, primeira equipe.
class PropertyCreationSetupPage extends StatefulWidget {
  final PropertyType? initialType;
  final PropertyCreationAddressMode initialAddressMode;
  final String? initialCondominiumId;
  final String? initialEmpreendimentoId;
  final String? initialTeamId;

  const PropertyCreationSetupPage({
    super.key,
    this.initialType,
    this.initialAddressMode = PropertyCreationAddressMode.standalone,
    this.initialCondominiumId,
    this.initialEmpreendimentoId,
    this.initialTeamId,
  });

  @override
  State<PropertyCreationSetupPage> createState() =>
      _PropertyCreationSetupPageState();
}

class _PropertyCreationSetupPageState extends State<PropertyCreationSetupPage> {
  final PropertyService _propertyService = PropertyService.instance;

  PropertyType? _type;
  PropertyCreationAddressMode _addressMode =
      PropertyCreationAddressMode.standalone;
  String? _teamId;
  String? _condominiumId;
  String? _empreendimentoId;

  List<PropertyFormTeamOption> _teams = [];
  bool _teamsLoading = false;
  String? _teamsError;

  List<NamedEntityOption> _condominiums = [];
  bool _condominiumsLoading = false;
  String? _condominiumsError;
  bool _condominiumsLoaded = false;

  List<NamedEntityOption> _empreendimentos = [];
  bool _empreendimentosLoading = false;
  String? _empreendimentosError;
  bool _empreendimentosLoaded = false;

  late final bool _canPickCondo;
  late final bool _canPickEmp;

  @override
  void initState() {
    super.initState();
    final access = ModuleAccessService.instance;
    // Regras estritamente alinhadas ao backend (`PermissionsGuard`):
    //  - `EMPREENDIMENTO_VIEW` é liberado para qualquer usuário autenticado
    //    (linha 61-67 do guard) — nunca desabilitamos a opção.
    //  - `CONDOMINIUM_VIEW` segue regra geral: master/admin têm bypass; demais
    //    precisam de permissão explícita. `hasPermission` já considera bypass
    //    de master/admin/manager localmente.
    _canPickCondo = access.hasPermission('condominium:view');
    _canPickEmp = true;

    _type = widget.initialType;
    _addressMode = widget.initialAddressMode;
    if (_addressMode == PropertyCreationAddressMode.condominium &&
        !_canPickCondo) {
      _addressMode = PropertyCreationAddressMode.standalone;
    }
    _condominiumId = (widget.initialCondominiumId ?? '').trim().isEmpty
        ? null
        : widget.initialCondominiumId!.trim();
    _empreendimentoId = (widget.initialEmpreendimentoId ?? '').trim().isEmpty
        ? null
        : widget.initialEmpreendimentoId!.trim();

    _loadTeams();
    // Pré-carrega listas em background — quando o usuário abrir o seletor
    // já temos dados em memória, sem flicker.
    if (_canPickCondo) {
      _loadCondominiums();
    }
    _loadEmpreendimentos();
  }

  Future<void> _loadTeams() async {
    setState(() {
      _teamsLoading = true;
      _teamsError = null;
    });
    try {
      final r = await _propertyService.getPropertyFormSettings();
      if (!mounted) return;
      if (r.success && r.data != null) {
        final teams = r.data!.teams;
        setState(() {
          _teams = teams;
          _teamsLoading = false;
        });
        // Resolve initial teamId — same priority as the web modal.
        final initial = (widget.initialTeamId ?? '').trim();
        String? pick;
        if (initial.isNotEmpty) {
          for (final t in teams) {
            if (t.id.toLowerCase() == initial.toLowerCase()) {
              pick = t.id;
              break;
            }
          }
        }
        pick ??= teams.isNotEmpty ? teams.first.id : null;
        if (mounted) setState(() => _teamId = pick);
      } else {
        setState(() {
          _teamsLoading = false;
          _teamsError =
              'Não foi possível carregar as equipes permitidas no cadastro. Tente de novo.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _teamsLoading = false;
        _teamsError =
            'Não foi possível carregar as equipes permitidas no cadastro. Tente de novo.';
      });
    }
  }

  Future<void> _loadCondominiums() async {
    if (_condominiumsLoaded || _condominiumsLoading) return;
    setState(() {
      _condominiumsLoading = true;
      _condominiumsError = null;
    });
    try {
      final r = await _propertyService.listCondominiumsBrief();
      if (!mounted) return;
      if (r.success && r.data != null) {
        setState(() {
          _condominiums = r.data!;
          _condominiumsLoading = false;
          _condominiumsLoaded = true;
        });
      } else {
        setState(() {
          _condominiumsLoading = false;
          _condominiumsError =
              'Não foi possível listar condomínios. Verifique permissões ou tente novamente.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _condominiumsLoading = false;
        _condominiumsError =
            'Não foi possível listar condomínios. Verifique permissões ou tente novamente.';
      });
    }
  }

  Future<void> _loadEmpreendimentos() async {
    if (_empreendimentosLoaded || _empreendimentosLoading) return;
    setState(() {
      _empreendimentosLoading = true;
      _empreendimentosError = null;
    });
    try {
      final r = await _propertyService.listEmpreendimentosBrief();
      if (!mounted) return;
      if (r.success && r.data != null) {
        setState(() {
          _empreendimentos = r.data!;
          _empreendimentosLoading = false;
          _empreendimentosLoaded = true;
        });
      } else {
        setState(() {
          _empreendimentosLoading = false;
          _empreendimentosError =
              'Não foi possível listar empreendimentos. Verifique permissões ou tente novamente.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _empreendimentosLoading = false;
        _empreendimentosError =
            'Não foi possível listar empreendimentos. Verifique permissões ou tente novamente.';
      });
    }
  }

  bool get _confirmEnabled {
    if (_type == null) return false;
    if ((_teamId ?? '').isEmpty) return false;
    if (_teamsLoading || _teams.isEmpty) return false;
    // Apartamentos exigem vínculo a condomínio — não podem usar "Endereço
    // próprio". Se o usuário ainda está em standalone, força a corrigir.
    if (_type == PropertyType.apartment &&
        _addressMode == PropertyCreationAddressMode.standalone) {
      return false;
    }
    if (_addressMode == PropertyCreationAddressMode.condominium) {
      if (!_canPickCondo) return false;
      if ((_condominiumId ?? '').isEmpty) return false;
    }
    if (_addressMode == PropertyCreationAddressMode.empreendimento) {
      if (!_canPickEmp) return false;
      if ((_empreendimentoId ?? '').isEmpty) return false;
    }
    return true;
  }

  void _confirm() {
    if (!_confirmEnabled) return;
    String? condoName;
    String? empName;
    if (_addressMode == PropertyCreationAddressMode.condominium) {
      condoName = _condominiums
          .firstWhere(
            (c) => c.id == _condominiumId,
            orElse: () => const NamedEntityOption(id: '', name: ''),
          )
          .name;
      if (condoName.isEmpty) condoName = null;
    }
    if (_addressMode == PropertyCreationAddressMode.empreendimento) {
      empName = _empreendimentos
          .firstWhere(
            (e) => e.id == _empreendimentoId,
            orElse: () => const NamedEntityOption(id: '', name: ''),
          )
          .name;
      if (empName.isEmpty) empName = null;
    }
    Navigator.of(context).pop(
      PropertyCreationSetupResult(
        type: _type!,
        teamId: _teamId!.trim(),
        addressMode: _addressMode,
        condominiumId:
            _addressMode == PropertyCreationAddressMode.condominium
                ? _condominiumId!.trim()
                : null,
        empreendimentoId:
            _addressMode == PropertyCreationAddressMode.empreendimento
                ? _empreendimentoId!.trim()
                : null,
        condominiumName: condoName,
        empreendimentoName: empName,
      ),
    );
  }

  /// Apartamento exige vínculo a condomínio — paridade com a regra de
  /// negócio do CRM. "Endereço próprio" é desabilitado nesse tipo.
  bool get _isApartmentType => _type == PropertyType.apartment;

  /// Trocar o tipo do imóvel pode forçar uma reconfiguração do modo de
  /// endereço. Ao escolher **Apartamento**, o usuário não pode usar
  /// "Endereço próprio": migramos automaticamente para "Vinculado a
  /// condomínio" (se houver permissão).
  void _onTypeChanged(PropertyType newType) {
    setState(() {
      _type = newType;
      if (newType == PropertyType.apartment) {
        if (_addressMode == PropertyCreationAddressMode.standalone &&
            _canPickCondo) {
          _addressMode = PropertyCreationAddressMode.condominium;
        }
      }
    });
    if (newType == PropertyType.apartment &&
        _addressMode == PropertyCreationAddressMode.condominium) {
      _loadCondominiums();
    }
  }

  // ---------- UI helpers ----------

  Color _accent(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.primary.primaryLightDarkMode
        : AppColors.primary.primary;
  }

  Widget _eyebrow(BuildContext context, String text, {Widget? trailing}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
                fontSize: 11,
                color: _accent(context),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _hairline(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 1,
      color: isDark
          ? Colors.white.withValues(alpha: 0.06)
          : ThemeHelpers.borderColor(context).withValues(alpha: 0.40),
    );
  }

  Widget _requiredTag(BuildContext context) {
    final accent = _accent(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: accent.withValues(alpha: isDark ? 0.18 : 0.10),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Text(
        'OBRIGATÓRIO',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: accent,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  // ---------- Type grid ----------

  static const List<({PropertyType value, String label, IconData icon})>
      _typeOptions = [
    (value: PropertyType.house, label: 'Casa', icon: Icons.home_rounded),
    (
      value: PropertyType.apartment,
      label: 'Apartamento',
      icon: Icons.apartment_rounded
    ),
    (
      value: PropertyType.commercial,
      label: 'Comercial',
      icon: Icons.business_rounded
    ),
    (value: PropertyType.land, label: 'Terreno', icon: Icons.location_on_rounded),
    (value: PropertyType.rural, label: 'Rural', icon: Icons.cottage_rounded),
  ];

  Widget _typeGrid(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        // 2 colunas em telas estreitas, 3 nas mais largas — espelho do web
        // que usa `auto-fill, minmax(140px, 1fr)`.
        final crossAxisCount = c.maxWidth >= 480 ? 3 : 2;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.55,
          children: _typeOptions.map((opt) {
            final selected = _type == opt.value;
            return _typeCard(theme, opt.label, opt.icon, selected, () {
              _onTypeChanged(opt.value);
            });
          }).toList(),
        );
      },
    );
  }

  Widget _typeCard(
    ThemeData theme,
    String label,
    IconData icon,
    bool selected,
    VoidCallback onTap,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accent(context);
    final border = selected
        ? accent
        : (isDark
            ? Colors.white.withValues(alpha: 0.10)
            : ThemeHelpers.borderColor(context).withValues(alpha: 0.45));
    final bg = selected
        ? accent.withValues(alpha: isDark ? 0.16 : 0.08)
        : (isDark
            ? Colors.white.withValues(alpha: 0.035)
            : Colors.white.withValues(alpha: 0.65));
    final fg = selected
        ? accent
        : (isDark
            ? Colors.white.withValues(alpha: 0.92)
            : ThemeHelpers.textColor(context));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: selected ? 1.6 : 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: fg),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: fg,
                  fontSize: 13,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- Team picker ----------

  Widget _teamPicker(BuildContext context) {
    final theme = Theme.of(context);
    if (_teamsLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: _accent(context)),
            ),
            const SizedBox(width: 10),
            Text(
              'Carregando equipes…',
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
          ],
        ),
      );
    }
    if (_teamsError != null) {
      return Text(
        _teamsError!,
        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.status.error),
      );
    }
    if (_teams.isEmpty) {
      return Text(
        'Nenhuma equipe disponível no seletor. Verifique em Propriedades → '
        'configurações do formulário se há equipes permitidas para o cadastro.',
        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.status.error),
      );
    }
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accent(context);
    final softBorder = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : ThemeHelpers.borderColor(context).withValues(alpha: 0.55);
    final textSecondary = ThemeHelpers.textSecondaryColor(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _teamId,
          isExpanded: true,
          icon: const Icon(Icons.expand_more_rounded, size: 18),
          decoration: InputDecoration(
            labelText: 'Selecione a equipe',
            isDense: true,
            filled: true,
            fillColor: isDark
                ? Colors.white.withValues(alpha: 0.045)
                : Colors.white.withValues(alpha: 0.78),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 12, right: 6),
              child: Icon(Icons.groups_2_rounded, size: 18, color: accent),
            ),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 36, minHeight: 36),
            labelStyle: theme.textTheme.labelLarge?.copyWith(
              color: textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            floatingLabelStyle: theme.textTheme.labelMedium?.copyWith(
              color: accent,
              fontWeight: FontWeight.w800,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: softBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: softBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: accent, width: 1.4),
            ),
          ),
          items: _teams
              .map(
                (t) => DropdownMenuItem<String>(
                  value: t.id,
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _hexToColor(t.color),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          t.name.isNotEmpty ? t.name : t.id,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _teamId = v),
        ),
        const SizedBox(height: 8),
        Text(
          'Campo obrigatório: o imóvel fica vinculado à equipe escolhida. O '
          'valor inicial segue sua equipe (ou a do funil, quando existir).',
          style: theme.textTheme.bodySmall?.copyWith(
            color: textSecondary,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Color _hexToColor(String hex) {
    var h = hex.replaceAll('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    if (v == null) return Colors.grey;
    return Color(v);
  }

  // ---------- Address mode picker ----------

  Widget _addressModeBlock(BuildContext context) {
    final apt = _isApartmentType;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (apt) ...[
          _apartmentLockHint(context),
          const SizedBox(height: 12),
        ],
        _modeCard(
          context,
          mode: PropertyCreationAddressMode.standalone,
          icon: Icons.place_rounded,
          title: 'Endereço próprio',
          description: apt
              ? 'Não disponível para apartamentos — escolha um condomínio abaixo.'
              : 'Informe o CEP e complete o endereço manualmente (número, complemento etc.).',
          // Apartamentos exigem vínculo: "Endereço próprio" fica bloqueado.
          enabled: !apt,
        ),
        const SizedBox(height: 10),
        _modeCard(
          context,
          mode: PropertyCreationAddressMode.condominium,
          icon: Icons.apartment_rounded,
          title: 'Vinculado a condomínio',
          description: _canPickCondo
              ? (apt
                  ? 'Selecione o condomínio onde fica o apartamento; o endereço vem do cadastro.'
                  : 'Escolha o condomínio abaixo; o CEP e o endereço vêm do cadastro.')
              : 'Escolha o condomínio abaixo; o CEP e o endereço vêm do cadastro. (Sem permissão para condomínios.)',
          enabled: _canPickCondo,
        ),
        const SizedBox(height: 10),
        _modeCard(
          context,
          mode: PropertyCreationAddressMode.empreendimento,
          icon: Icons.location_city_rounded,
          title: 'Vinculado a empreendimento',
          description: _canPickEmp
              ? 'Escolha o empreendimento abaixo; o CEP e o endereço vêm do cadastro.'
              : 'Escolha o empreendimento abaixo; o CEP e o endereço vêm do cadastro. (Sem permissão para empreendimentos.)',
          enabled: _canPickEmp,
        ),
      ],
    );
  }

  /// Banner explicando por que "Endereço próprio" está bloqueado quando o
  /// tipo é Apartamento.
  Widget _apartmentLockHint(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accent(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: accent.withValues(alpha: isDark ? 0.14 : 0.07),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.40 : 0.30),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Apartamentos precisam estar vinculados a um condomínio. '
              'Selecione "Vinculado a condomínio" abaixo e escolha o cadastro — '
              'o endereço será preenchido automaticamente.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeCard(
    BuildContext context, {
    required PropertyCreationAddressMode mode,
    required IconData icon,
    required String title,
    required String description,
    required bool enabled,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accent(context);
    final selected = _addressMode == mode;
    final disabledOpacity = enabled ? 1.0 : 0.55;
    final border = !enabled
        ? (isDark
            ? Colors.white.withValues(alpha: 0.10)
            : ThemeHelpers.borderColor(context).withValues(alpha: 0.45))
        : selected
            ? accent
            : (isDark
                ? Colors.white.withValues(alpha: 0.10)
                : ThemeHelpers.borderColor(context).withValues(alpha: 0.45));
    final bg = !enabled
        ? (isDark
            ? Colors.white.withValues(alpha: 0.025)
            : Colors.white.withValues(alpha: 0.55))
        : selected
            ? accent.withValues(alpha: isDark ? 0.14 : 0.07)
            : (isDark
                ? Colors.white.withValues(alpha: 0.035)
                : Colors.white.withValues(alpha: 0.78));

    return Opacity(
      opacity: disabledOpacity,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: selected ? 1.6 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: !enabled
                  ? null
                  : () {
                      setState(() {
                        _addressMode = mode;
                        if (mode != PropertyCreationAddressMode.condominium) {
                          _condominiumId = null;
                        }
                        if (mode != PropertyCreationAddressMode.empreendimento) {
                          _empreendimentoId = null;
                        }
                      });
                      if (mode == PropertyCreationAddressMode.condominium) {
                        _loadCondominiums();
                      } else if (mode ==
                          PropertyCreationAddressMode.empreendimento) {
                        _loadEmpreendimentos();
                      }
                    },
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _radioCircle(selected: selected, enabled: enabled),
                    const SizedBox(width: 12),
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        color: accent.withValues(
                          alpha: isDark ? 0.18 : 0.10,
                        ),
                      ),
                      child: Icon(icon, size: 16, color: accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color:
                                  ThemeHelpers.textSecondaryColor(context),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (selected &&
                mode == PropertyCreationAddressMode.condominium &&
                enabled) ...[
              _hairline(context),
              Padding(
                padding: const EdgeInsets.fromLTRB(54, 12, 14, 14),
                child: _entityTrigger(
                  context,
                  selectedId: _condominiumId,
                  loading: _condominiumsLoading,
                  error: _condominiumsError,
                  cachedOptions: _condominiums,
                  hint: 'Buscar e selecionar condomínio',
                  emptyHint:
                      'Nenhum condomínio ativo encontrado. Cadastre no CRM primeiro.',
                  prefix: Icons.apartment_rounded,
                  kind: _PickerKind.condominium,
                  onPicked: (opt) => setState(() {
                    _condominiumId = opt?.id;
                    if (opt != null) {
                      // Adiciona ao cache local se ainda não existir, para
                      // que o trigger consiga exibir o nome sem nova fetch.
                      final exists = _condominiums.any((c) => c.id == opt.id);
                      if (!exists) _condominiums = [..._condominiums, opt];
                    }
                  }),
                ),
              ),
            ],
            if (selected &&
                mode == PropertyCreationAddressMode.empreendimento &&
                enabled) ...[
              _hairline(context),
              Padding(
                padding: const EdgeInsets.fromLTRB(54, 12, 14, 14),
                child: _entityTrigger(
                  context,
                  selectedId: _empreendimentoId,
                  loading: _empreendimentosLoading,
                  error: _empreendimentosError,
                  cachedOptions: _empreendimentos,
                  hint: 'Buscar e selecionar empreendimento',
                  emptyHint:
                      'Nenhum empreendimento ativo encontrado. Cadastre no CRM primeiro.',
                  prefix: Icons.location_city_rounded,
                  kind: _PickerKind.empreendimento,
                  onPicked: (opt) => setState(() {
                    _empreendimentoId = opt?.id;
                    if (opt != null) {
                      final exists =
                          _empreendimentos.any((e) => e.id == opt.id);
                      if (!exists) {
                        _empreendimentos = [..._empreendimentos, opt];
                      }
                    }
                  }),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _radioCircle({required bool selected, required bool enabled}) {
    final accent = _accent(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = !enabled
        ? (isDark
            ? Colors.white.withValues(alpha: 0.18)
            : ThemeHelpers.borderColor(context).withValues(alpha: 0.55))
        : selected
            ? accent
            : (isDark
                ? Colors.white.withValues(alpha: 0.30)
                : ThemeHelpers.borderColor(context).withValues(alpha: 0.65));
    return Container(
      width: 22,
      height: 22,
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected && enabled
            ? accent.withValues(alpha: 0.12)
            : Colors.transparent,
        border: Border.all(color: color, width: 2),
      ),
      alignment: Alignment.center,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: selected ? 10 : 0,
        height: selected ? 10 : 0,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled ? accent : color,
        ),
      ),
    );
  }

  /// Trigger "card" que abre uma bottom-sheet com busca paginada server-side.
  /// Substitui o `DropdownButtonFormField` para conseguir mostrar TODOS os
  /// condomínios/empreendimentos da empresa, com filtro por nome e scroll
  /// virtualizado — paridade com o `CondominiumSelector`/`EmpreendimentoSelector`
  /// do web (variant `embedded`).
  Widget _entityTrigger(
    BuildContext context, {
    required String? selectedId,
    required bool loading,
    required String? error,
    required List<NamedEntityOption> cachedOptions,
    required String hint,
    required String emptyHint,
    required IconData prefix,
    required _PickerKind kind,
    required ValueChanged<NamedEntityOption?> onPicked,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accent(context);
    final softBorder = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : ThemeHelpers.borderColor(context).withValues(alpha: 0.55);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    NamedEntityOption? selected;
    if (selectedId != null) {
      for (final o in cachedOptions) {
        if (o.id == selectedId) {
          selected = o;
          break;
        }
      }
    }
    final fillColor = isDark
        ? Colors.white.withValues(alpha: 0.045)
        : Colors.white.withValues(alpha: 0.85);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openEntityPickerSheet(
          context,
          kind: kind,
          selectedId: selectedId,
          onPicked: onPicked,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected != null
                  ? accent.withValues(alpha: 0.6)
                  : softBorder,
              width: selected != null ? 1.4 : 1,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  color: accent.withValues(alpha: isDark ? 0.18 : 0.10),
                ),
                child: Icon(prefix, size: 16, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selected != null) ...[
                      Text(
                        selected.name.isNotEmpty ? selected.name : selected.id,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                          letterSpacing: -0.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Toque para alterar',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: secondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ] else ...[
                      Text(
                        hint,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: secondary,
                        ),
                      ),
                      if (loading) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            SizedBox(
                              width: 11,
                              height: 11,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.6,
                                color: accent,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Carregando lista…',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: secondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ] else if (error != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          error,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.status.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ] else if (cachedOptions.isEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          emptyHint,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: secondary,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              if (selected != null)
                IconButton(
                  tooltip: 'Limpar seleção',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded, size: 18, color: secondary),
                  onPressed: () => onPicked(null),
                )
              else
                Icon(Icons.search_rounded, size: 18, color: secondary),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openEntityPickerSheet(
    BuildContext context, {
    required _PickerKind kind,
    required String? selectedId,
    required ValueChanged<NamedEntityOption?> onPicked,
  }) async {
    HapticFeedback.selectionClick();
    final picked = await showModalBottomSheet<NamedEntityOption>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _EntityPickerSheet(
        kind: kind,
        propertyService: _propertyService,
        initialSelectedId: selectedId,
        accent: _accent(context),
      ),
    );
    if (picked != null) onPicked(picked);
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accent(context);

    final bgDecoration = isDark
        ? BoxDecoration(color: AppColors.background.backgroundDarkMode)
        : BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.background.background,
                AppColors.background.backgroundSecondary,
              ],
            ),
          );

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: 'Cancelar',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Novo imóvel'),
      ),
      body: DecoratedBox(
        decoration: bgDecoration,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _heroHeader(theme, accent, isDark),
                      const SizedBox(height: 22),
                      _eyebrow(context, 'Tipo do imóvel'),
                      _hairline(context),
                      const SizedBox(height: 14),
                      _typeGrid(context),
                      const SizedBox(height: 26),
                      _eyebrow(
                        context,
                        'Equipe',
                        trailing: _requiredTag(context),
                      ),
                      _hairline(context),
                      const SizedBox(height: 14),
                      _teamPicker(context),
                      const SizedBox(height: 26),
                      _eyebrow(context, 'Endereço'),
                      _hairline(context),
                      const SizedBox(height: 14),
                      _addressModeBlock(context),
                      const SizedBox(height: 28),
                    ],
                  ),
                ),
              ),
              _footer(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroHeader(ThemeData theme, Color accent, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: isDark ? 0.55 : 0.85),
                accent.withValues(alpha: isDark ? 0.85 : 1.0),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: isDark ? 0.32 : 0.22),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.home_rounded, color: Colors.white, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: accent.withValues(alpha: isDark ? 0.18 : 0.10),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.40),
                  ),
                ),
                child: Text(
                  'CONFIGURAÇÃO INICIAL',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Novo imóvel',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Escolha o tipo, a equipe responsável e a origem do endereço. '
                'Se for condomínio ou empreendimento, selecione o cadastro. O '
                'CEP será preenchido na etapa Localização.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  height: 1.38,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _footer(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accent(context);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.02)
              : Colors.white.withValues(alpha: 0.65),
          border: Border(
            top: BorderSide(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : ThemeHelpers.borderColor(context).withValues(alpha: 0.40),
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Cancelar',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: _confirmEnabled ? _confirm : null,
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.arrow_forward_rounded, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Continuar',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// ENTITY PICKER SHEET (condomínio / empreendimento)
// ============================================================================

enum _PickerKind { condominium, empreendimento }

extension on _PickerKind {
  String get titleLabel => this == _PickerKind.condominium
      ? 'Selecionar condomínio'
      : 'Selecionar empreendimento';

  String get hintLabel => this == _PickerKind.condominium
      ? 'Buscar condomínio por nome'
      : 'Buscar empreendimento por nome';

  String get emptyLabel => this == _PickerKind.condominium
      ? 'Nenhum condomínio ativo encontrado.'
      : 'Nenhum empreendimento ativo encontrado.';

  IconData get icon => this == _PickerKind.condominium
      ? Icons.apartment_rounded
      : Icons.location_city_rounded;
}

/// Bottom sheet de busca paginada para condomínios/empreendimentos da empresa.
/// Aproveita a paginação do backend e o parâmetro `search` para filtrar
/// server-side, exibindo TODOS os registros (com scroll infinito) — paridade
/// com o `CondominiumSelector` (variant `embedded`) do web.
class _EntityPickerSheet extends StatefulWidget {
  final _PickerKind kind;
  final PropertyService propertyService;
  final String? initialSelectedId;
  final Color accent;

  const _EntityPickerSheet({
    required this.kind,
    required this.propertyService,
    required this.initialSelectedId,
    required this.accent,
  });

  @override
  State<_EntityPickerSheet> createState() => _EntityPickerSheetState();
}

class _EntityPickerSheetState extends State<_EntityPickerSheet> {
  static const int _pageSize = 25;

  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _debounce;

  final List<NamedEntityOption> _items = [];
  String _search = '';
  int _page = 1;
  int _totalPages = 1;
  int _total = 0;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _fetchPage(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final v = _searchCtrl.text;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      if (v.trim() == _search) return;
      setState(() => _search = v.trim());
      _fetchPage(reset: true);
    });
  }

  bool _onScrollNotification(ScrollNotification n) {
    if (_loading || _loadingMore) return false;
    if (_page >= _totalPages) return false;
    if (n is ScrollUpdateNotification || n is ScrollEndNotification) {
      final pos = n.metrics;
      if (pos.axis == Axis.vertical &&
          pos.pixels >= pos.maxScrollExtent - 280) {
        _fetchPage(reset: false);
      }
    }
    return false;
  }

  Future<void> _fetchPage({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
      });
    } else {
      setState(() => _loadingMore = true);
    }
    final pageToFetch = reset ? 1 : _page + 1;
    try {
      final r = widget.kind == _PickerKind.condominium
          ? await widget.propertyService.listCondominiumsPage(
              page: pageToFetch,
              limit: _pageSize,
              search: _search.isEmpty ? null : _search,
            )
          : await widget.propertyService.listEmpreendimentosPage(
              page: pageToFetch,
              limit: _pageSize,
              search: _search.isEmpty ? null : _search,
            );
      if (!mounted) return;
      if (r.success && r.data != null) {
        final data = r.data!;
        setState(() {
          if (reset) {
            _items
              ..clear()
              ..addAll(data.items);
          } else {
            _items.addAll(data.items);
          }
          _page = data.page;
          _totalPages = data.totalPages;
          _total = data.total;
          _loading = false;
          _loadingMore = false;
        });
      } else {
        setState(() {
          _error = r.message ??
              (widget.kind == _PickerKind.condominium
                  ? 'Erro ao listar condomínios'
                  : 'Erro ao listar empreendimentos');
          _loading = false;
          _loadingMore = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro de conexão.';
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final softBorder = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : ThemeHelpers.borderColor(context).withValues(alpha: 0.55);
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color: ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: secondary.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: widget.accent.withValues(alpha: 0.14),
                        border: Border.all(
                          color: widget.accent.withValues(alpha: 0.36),
                        ),
                      ),
                      child: Icon(widget.kind.icon,
                          color: widget.accent, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.kind.titleLabel,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.2,
                            ),
                          ),
                          if (_total > 0)
                            Text(
                              '$_total registro${_total == 1 ? '' : 's'} ativo${_total == 1 ? '' : 's'}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: secondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: TextField(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  textInputAction: TextInputAction.search,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    hintText: widget.kind.hintLabel,
                    isDense: true,
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.045)
                        : Colors.white.withValues(alpha: 0.85),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    prefixIcon: Icon(Icons.search_rounded,
                        size: 18, color: secondary),
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Limpar',
                            icon: Icon(Icons.close_rounded,
                                size: 18, color: secondary),
                            onPressed: () => _searchCtrl.clear(),
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: softBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: softBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: widget.accent, width: 1.4),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _buildList(context, theme, scrollController),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildList(
    BuildContext context,
    ThemeData theme,
    ScrollController scrollController,
  ) {
    if (_loading && _items.isEmpty) {
      return Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.4, color: widget.accent),
        ),
      );
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline_rounded,
                  color: AppColors.status.error, size: 32),
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.status.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () => _fetchPage(reset: true),
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.kind.icon, size: 32, color: widget.accent),
              const SizedBox(height: 10),
              Text(
                _search.isEmpty
                    ? widget.kind.emptyLabel
                    : 'Nenhum resultado para "$_search".',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _search.isEmpty
                    ? 'Cadastre no CRM primeiro para vincular o imóvel.'
                    : 'Tente outro termo ou limpe a busca.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: Scrollbar(
        controller: scrollController,
        child: ListView.separated(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
          itemCount: _items.length + (_loadingMore ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(height: 6),
          itemBuilder: (context, index) {
            if (index >= _items.length) {
              return Padding(
                padding: const EdgeInsets.all(14),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: widget.accent,
                    ),
                  ),
                ),
              );
            }
            final item = _items[index];
            final selected = item.id == widget.initialSelectedId;
            return _EntityRow(
              item: item,
              icon: widget.kind.icon,
              accent: widget.accent,
              selected: selected,
              onTap: () => Navigator.of(context).pop(item),
            );
          },
        ),
      ),
    );
  }
}

class _EntityRow extends StatelessWidget {
  final NamedEntityOption item;
  final IconData icon;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  const _EntityRow({
    required this.item,
    required this.icon,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: selected
                ? accent.withValues(alpha: isDark ? 0.16 : 0.08)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.025)
                    : Colors.white.withValues(alpha: 0.7)),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.45)
                  : ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  color: accent.withValues(alpha: isDark ? 0.18 : 0.10),
                ),
                child: Icon(icon, size: 16, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.name.isNotEmpty ? item.name : item.id,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        height: 1.15,
                        color: selected
                            ? accent
                            : ThemeHelpers.textColor(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.name.isEmpty)
                      Text(
                        'ID: ${item.id}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: secondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded, color: accent, size: 18)
              else
                Icon(Icons.chevron_right_rounded, color: secondary, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
