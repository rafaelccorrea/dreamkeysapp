import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/profile_service.dart';
import '../../../../shared/services/tag_service.dart';
import '../../../../shared/utils/input_formatters.dart';
import '../../../../shared/utils/masks.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/custom_button.dart';
import '../../../../shared/widgets/custom_text_field.dart';
import '../../../../shared/widgets/skeleton_box.dart';

// ─── Paleta editorial (mesmo DNA da tela de Perfil) ─────────────────────────
// 1 cor de identidade por seção: vermelho da marca = conta/identidade;
// violeta = tags/perfil no CRM. Sem arco-íris.
Color _pBrand(bool d) =>
    d ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
Color _pViolet(bool d) => d ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED);

/// Edição de perfil — alinhada ao sistema editorial da tela de Perfil:
///   • Masthead (eyebrow + headline w900 + subtítulo), sem hero-card.
///   • Faixa de identidade com avatar (somente leitura) e nome AO VIVO.
///   • Seções full-bleed com header editorial e divisores finos.
///   • Telefone com máscara ((00) 00000-0000) — mesma do formulário de cliente.
///   • Tags como chips flush com a COR REAL de cada tag (dot + tom-sobre-tom).
/// Design flush: nada encapsulado em card; separação por divisor.
class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  Profile? _profile;
  List<Tag> _availableTags = [];
  List<String> _selectedTagIds = [];
  bool _isLoading = true;
  bool _isLoadingTags = false;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadTags();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await ProfileService.instance.getProfile();

      if (mounted) {
        if (response.success && response.data != null) {
          setState(() {
            _profile = response.data;
            _nameController.text = _profile!.name;
            // Exibe já formatado — a máscara acompanha a digitação depois.
            _phoneController.text = Masks.phone(
              _profile!.phone ?? _profile!.cellphone ?? '',
            );
            _selectedTagIds = _profile!.tagIds?.toList() ?? [];
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = response.message ?? 'Erro ao carregar perfil';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Erro ao conectar com o servidor';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadTags() async {
    setState(() {
      _isLoadingTags = true;
    });

    try {
      final response = await TagService.instance.getTags();

      if (mounted) {
        setState(() {
          if (response.success && response.data != null) {
            _availableTags = response.data!;
          }
          _isLoadingTags = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingTags = false;
        });
      }
    }
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    try {
      // Telefone segue SEM máscara para a API (dígitos), como a tela antiga
      // enviava — a máscara é só de exibição.
      final phoneDigits = Masks.unmaskPhone(_phoneController.text);
      final response = await ProfileService.instance.updateProfile(
        name: _nameController.text.trim(),
        phone: phoneDigits.isNotEmpty ? phoneDigits : null,
        tagIds: _selectedTagIds.isNotEmpty ? _selectedTagIds : null,
      );

      if (mounted) {
        if (response.success && response.data != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Perfil atualizado com sucesso!'),
              backgroundColor: AppColors.status.success,
            ),
          );
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao atualizar perfil'),
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
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final brand = _pBrand(isDark);
    final violet = _pViolet(isDark);

    return AppScaffold(
      title: 'Editar Perfil',
      currentBottomNavIndex: -1,
      userName: _profile?.name,
      userEmail: _profile?.email,
      userAvatar: _profile?.avatar,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: _isLoading
            ? Padding(
                key: const ValueKey('loading'),
                padding: const EdgeInsets.only(top: 4),
                child: _buildSkeleton(context),
              )
            : _errorMessage != null
            ? Padding(
                key: ValueKey<String>('e-${_errorMessage.hashCode}'),
                padding: const EdgeInsets.all(24),
                child: _buildErrorState(context, theme, brand),
              )
            : SingleChildScrollView(
                key: const ValueKey('ok'),
                padding: const EdgeInsets.only(top: 4, bottom: 40),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildMasthead(context, theme, brand),
                      const SizedBox(height: 16),
                      _buildIdentityStrip(context, theme, brand, violet),
                      const SizedBox(height: 18),
                      _sectionSeparator(context),
                      const SizedBox(height: 20),
                      _SectionHeader(
                        eyebrow: 'IDENTIDADE',
                        title: 'Dados pessoais',
                        subtitle:
                            'Nome exibido no CRM e telefone de contato da equipe.',
                        tone: brand,
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            CustomTextField(
                              controller: _nameController,
                              label: 'Nome Completo *',
                              prefixIcon: const Icon(Icons.person_outline),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Nome é obrigatório';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            CustomTextField(
                              controller: _phoneController,
                              label: 'Telefone',
                              prefixIcon: const Icon(Icons.phone_outlined),
                              keyboardType: TextInputType.phone,
                              inputFormatters: [PhoneInputFormatter()],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      _sectionSeparator(context),
                      const SizedBox(height: 20),
                      _SectionHeader(
                        eyebrow: 'PERFIL NO CRM',
                        title: 'Tags',
                        subtitle:
                            'Como você é classificado nas listas e filtros.',
                        tone: violet,
                        trailing: _isLoadingTags
                            ? null
                            : _CountPill(
                                label:
                                    '${_selectedTagIds.length} '
                                    '${_selectedTagIds.length == 1 ? 'selecionada' : 'selecionadas'}',
                                tone: violet,
                                active: _selectedTagIds.isNotEmpty,
                              ),
                      ),
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _buildTagsSelector(context, theme, violet),
                      ),
                      const SizedBox(height: 26),
                      _sectionSeparator(context),
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            CustomButton(
                              text: _isSaving
                                  ? 'Salvando...'
                                  : 'Salvar Alterações',
                              onPressed: _isSaving ? null : _handleSave,
                              icon: _isSaving ? null : Icons.save,
                              isLoading: _isSaving,
                            ),
                            const SizedBox(height: 10),
                            CustomButton(
                              text: 'Cancelar',
                              onPressed: () => Navigator.pop(context),
                              icon: Icons.close,
                              variant: ButtonVariant.secondary,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  // ─── Masthead (eyebrow + headline w900) ─────────────────────────────────

  Widget _buildMasthead(BuildContext context, ThemeData theme, Color brand) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'MINHA CONTA',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: brand,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.2,
                  fontSize: 10,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: brand.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'EDIÇÃO',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(
                    context,
                  ).withValues(alpha: 0.85),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.8,
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Editar perfil',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
              height: 1.02,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Nome, telefone e tags. A foto e a senha ficam na tela de Perfil.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Faixa de identidade: avatar (leitura) + nome AO VIVO ───────────────

  Widget _buildIdentityStrip(
    BuildContext context,
    ThemeData theme,
    Color brand,
    Color violet,
  ) {
    final email = _profile?.email ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _ReadonlyAvatar(profile: _profile, tone: brand),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nome espelha a digitação — mesmo conceito do preview vivo
                // usado no CRM web, na escala do mobile.
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _nameController,
                  builder: (context, value, _) {
                    final live = value.text.trim();
                    return Text(
                      live.isEmpty ? 'Seu nome' : live,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                        color: live.isEmpty
                            ? ThemeHelpers.textSecondaryColor(context)
                            : ThemeHelpers.textColor(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    );
                  },
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    email,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _CountPill(
            label: 'Foto no Perfil',
            tone: violet,
            active: false,
            icon: Icons.photo_camera_outlined,
          ),
        ],
      ),
    );
  }

  // ─── Divisor fino full-bleed ─────────────────────────────────────────────

  Widget _sectionSeparator(BuildContext context) {
    return Container(
      height: 1,
      color: ThemeHelpers.borderColor(context).withValues(alpha: 0.6),
    );
  }

  // ─── Skeleton (espelha o layout real) ───────────────────────────────────

  Widget _buildSkeleton(BuildContext context) {
    Widget line(double w, double h, [double r = 6]) =>
        SkeletonBox(width: w, height: h, borderRadius: r);
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          line(110, 10),
          const SizedBox(height: 10),
          line(190, 26),
          const SizedBox(height: 8),
          line(250, 12),
          const SizedBox(height: 20),
          Row(
            children: [
              const SkeletonBox(width: 52, height: 52, borderRadius: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    line(140, 14),
                    const SizedBox(height: 6),
                    line(180, 10),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          line(120, 10),
          const SizedBox(height: 8),
          line(160, 20),
          const SizedBox(height: 16),
          line(double.infinity, 56, 12),
          const SizedBox(height: 12),
          line(double.infinity, 56, 12),
          const SizedBox(height: 28),
          line(90, 10),
          const SizedBox(height: 8),
          line(110, 20),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(
              5,
              (_) => line(86, 34, 999),
            ),
          ),
          const SizedBox(height: 28),
          line(double.infinity, 50, 12),
          const SizedBox(height: 10),
          line(double.infinity, 50, 12),
        ],
      ),
    );
  }

  // ─── Erro (editorial, com retry) ─────────────────────────────────────────

  Widget _buildErrorState(BuildContext context, ThemeData theme, Color brand) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: brand.withValues(alpha: 0.12),
              border: Border.all(color: brand.withValues(alpha: 0.35)),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.error_outline_rounded, color: brand, size: 26),
          ),
          const SizedBox(height: 16),
          Text(
            'Erro ao carregar perfil',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
              color: ThemeHelpers.textColor(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _errorMessage ?? 'Erro desconhecido',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
          const SizedBox(height: 22),
          CustomButton(
            text: 'Tentar Novamente',
            onPressed: _loadProfile,
            icon: Icons.refresh,
          ),
        ],
      ),
    );
  }

  // ─── Tags (chips flush com a cor real da tag) ────────────────────────────

  Widget _buildTagsSelector(
    BuildContext context,
    ThemeData theme,
    Color violet,
  ) {
    if (_isLoadingTags) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: List.generate(
          4,
          (_) => const SkeletonBox(width: 86, height: 34, borderRadius: 999),
        ),
      );
    }

    if (_availableTags.isEmpty) {
      return Row(
        children: [
          Icon(
            Icons.sell_outlined,
            size: 18,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Nenhuma tag disponível na sua empresa.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _availableTags.map((tag) {
        final selected = _selectedTagIds.contains(tag.id);
        return _TagChip(
          tag: tag,
          selected: selected,
          fallbackTone: violet,
          onTap: () {
            setState(() {
              if (selected) {
                _selectedTagIds.remove(tag.id);
              } else {
                _selectedTagIds.add(tag.id);
              }
            });
          },
        );
      }).toList(),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// COMPONENTES INTERNOS — sistema editorial (mesmo DNA da tela de Perfil)
// ════════════════════════════════════════════════════════════════════════

/// Cabeçalho editorial de seção: barra tonal + eyebrow + título w900 +
/// subtítulo, com espaço para um chip à direita (contagem de tags).
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.eyebrow,
    required this.title,
    required this.tone,
    this.subtitle,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final String? subtitle;
  final Color tone;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 18,
                      height: 2,
                      decoration: BoxDecoration(
                        color: tone,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        eyebrow,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: tone,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.8,
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                    color: ThemeHelpers.textColor(context),
                    height: 1.05,
                    fontSize: 22,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }
}

/// Pill compacta tom-sobre-tom (contagem de tags / hint da foto).
class _CountPill extends StatelessWidget {
  const _CountPill({
    required this.label,
    required this.tone,
    required this.active,
    this.icon,
  });

  final String label;
  final Color tone;
  final bool active;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final color = active ? tone : muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: active ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 10.5,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Avatar somente leitura da faixa de identidade — a troca de foto vive na
/// tela de Perfil (evita duplicar o fluxo de upload aqui).
class _ReadonlyAvatar extends StatelessWidget {
  const _ReadonlyAvatar({required this.profile, required this.tone});

  final Profile? profile;
  final Color tone;

  String get _initials {
    final name = (profile?.name ?? '').trim();
    if (name.isEmpty) return '?';
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final avatar = profile?.avatar;
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: tone.withValues(alpha: 0.35), width: 1.5),
        color: tone.withValues(alpha: 0.1),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: (avatar != null && avatar.isNotEmpty)
          ? Image.network(
              avatar,
              fit: BoxFit.cover,
              width: 52,
              height: 52,
              errorBuilder: (_, _, _) => Text(
                _initials,
                style: TextStyle(
                  color: tone,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            )
          : Text(
              _initials,
              style: TextStyle(
                color: tone,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
    );
  }
}

/// Chip de tag flush: dot na COR REAL da tag + tom-sobre-tom quando
/// selecionada. Sem FilterChip do Material — coerência com o sistema.
class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.tag,
    required this.selected,
    required this.fallbackTone,
    required this.onTap,
  });

  final Tag tag;
  final bool selected;
  final Color fallbackTone;
  final VoidCallback onTap;

  Color get _tagColor {
    final raw = (tag.color ?? '').replaceAll('#', '').trim();
    if (raw.length == 6) {
      final parsed = int.tryParse(raw, radix: 16);
      if (parsed != null) return Color(0xFF000000 | parsed);
    }
    return fallbackTone;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = _tagColor;

    final borderColor = selected
        ? tone.withValues(alpha: 0.5)
        : ThemeHelpers.borderColor(context);
    final bgColor = selected
        ? tone.withValues(alpha: isDark ? 0.16 : 0.1)
        : Colors.transparent;
    final labelColor = selected
        ? (isDark ? Colors.white : ThemeHelpers.textColor(context))
        : ThemeHelpers.textSecondaryColor(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tone.withValues(alpha: selected ? 1 : 0.55),
                ),
              ),
              const SizedBox(width: 7),
              Text(
                tag.name,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: labelColor,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 5),
                Icon(Icons.check_rounded, size: 14, color: tone),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
