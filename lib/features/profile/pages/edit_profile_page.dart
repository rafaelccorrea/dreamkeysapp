import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/profile_service.dart';
import '../../../../shared/services/tag_service.dart';
import '../../../../shared/utils/error_cause.dart';
import '../../../../shared/utils/input_formatters.dart';
import '../../../../shared/utils/masks.dart';
import '../../../../shared/widgets/app_error_state.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/skeleton_box.dart';

// ─── Cores (só tokens) ──────────────────────────────────────────────────────
// Vermelho da marca = o formulário (foco, barras de seção); as tags vestem
// a própria cor cadastrada — violeta é só a reserva de tag sem cor.
Color _pBrand(bool d) =>
    d ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
Color _pTagFallback(bool d) =>
    d ? AppColors.status.purpleDarkMode : AppColors.status.purple;

/// Edição de perfil — gramática de formulário do app:
///   • Topo "Como a equipe te vê": prévia viva (nome e telefone espelham a
///     digitação; as tags marcadas aparecem na cor real).
///   • Campos `filled` leves; nome | telefone em 2 colunas quando cabem;
///     e-mail de acesso visível e travado (não muda por aqui).
///   • Telefone com máscara ((00) 00000-0000) — mesma do formulário de cliente.
///   • Tags como chips flush com a COR REAL de cada tag.
///   • Barra fixa: Cancelar neutro + Salvar verde; sai do caminho do
///     teclado em tela baixa.
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
  // Tags como estavam ao abrir — decide se o PUT /tags/user/:id/set é
  // necessário (a rota é só Admin/Master no back).
  Set<String> _initialTagIds = {};
  bool _isLoading = true;
  bool _isLoadingTags = false;
  bool _isSaving = false;
  String? _errorMessage;
  // Guardado junto da mensagem: sem o código HTTP não dá para distinguir
  // "sem permissão" de "servidor fora do ar".
  int _errorStatus = 0;
  ErrorCause? _errorCause;

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
      _errorStatus = 0;
      _errorCause = null;
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
            _initialTagIds = _selectedTagIds.toSet();
            _isLoading = false;
          });
          _loadUserTags(_profile!.id);
        } else {
          setState(() {
            _errorMessage = response.message ?? 'Erro ao carregar perfil';
            _errorStatus = response.statusCode;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorCause = ErrorCause.fromException(e);
          _errorMessage = 'Erro ao conectar com o servidor';
          _isLoading = false;
        });
      }
    }
  }

  /// Tags atuais do usuário — GET /tags/user/:userId, como o web. O GET
  /// /auth/profile não traz tagIds; sem isto a seleção nascia vazia e o
  /// salvar apagava as tags existentes.
  Future<void> _loadUserTags(String userId) async {
    if (userId.isEmpty) return;
    try {
      final res = await TagService.instance.getUserTags(userId);
      if (!mounted || !res.success || res.data == null) return;
      setState(() {
        _selectedTagIds = res.data!.map((t) => t.id).toList();
        _initialTagIds = _selectedTagIds.toSet();
      });
    } catch (_) {
      // Mantém o fallback de profile.tagIds (igual ao web).
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
      // Telefone segue SEM máscara (dígitos) — a máscara é só de exibição.
      // Como o web: name, phone e tagIds vão SEMPRE (phone vazio quando
      // apagado, tagIds vazio quando todas foram desmarcadas).
      final phoneDigits = Masks.unmaskPhone(_phoneController.text);
      final response = await ProfileService.instance.updateProfile(
        name: _nameController.text.trim(),
        phone: phoneDigits,
        tagIds: _selectedTagIds,
      );

      // O PUT /auth/profile descarta tagIds (whitelist); quem grava as tags
      // é o PUT /tags/user/:id/set — segundo passo do web.
      if (response.success && response.data != null) {
        final tagsChanged =
            _selectedTagIds.toSet().length != _initialTagIds.length ||
            !_selectedTagIds.toSet().containsAll(_initialTagIds);
        final userId = _profile?.id ?? '';
        if (tagsChanged && userId.isNotEmpty) {
          final tagsRes = await TagService.instance.setUserTags(
            userId,
            _selectedTagIds,
          );
          if (!tagsRes.success) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Dados salvos, mas as tags não: '
                    '${tagsRes.message ?? 'erro ao salvar as tags'}',
                  ),
                  backgroundColor: AppColors.status.error,
                ),
              );
            }
            return;
          }
          _initialTagIds = _selectedTagIds.toSet();
        }
      }

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

  /// Tablet/landscape largo: a coluna para em [_kMaxContentWidth] e
  /// centraliza — campo de 1000dp não é formulário.
  EdgeInsets _pagePadding({double top = 0, double bottom = 0}) {
    final w = MediaQuery.sizeOf(context).width;
    final side = w > _kMaxContentWidth ? (w - _kMaxContentWidth) / 2 : 0.0;
    return EdgeInsets.fromLTRB(side, top, side, bottom);
  }

  /// Campos `filled` leves: sem borda em repouso, foco na cor da marca — a
  /// mesma gramática do formulário de ficha.
  ThemeData _formTheme(BuildContext context, Color accent) {
    final base = Theme.of(context);
    final isDark = base.brightness == Brightness.dark;
    final fill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final error = isDark
        ? AppColors.status.errorDarkMode
        : AppColors.status.error;
    OutlineInputBorder b(Color c, double w) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: w == 0 ? BorderSide.none : BorderSide(color: c, width: w),
    );
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(primary: accent),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: accent,
        selectionColor: accent.withValues(alpha: 0.18),
        selectionHandleColor: accent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
        labelStyle: TextStyle(
          color: muted,
          fontWeight: FontWeight.w600,
          fontSize: 13.5,
        ),
        floatingLabelStyle: TextStyle(
          color: accent,
          fontWeight: FontWeight.w700,
          fontSize: 13.5,
        ),
        hintStyle: TextStyle(
          color: muted.withValues(alpha: 0.7),
          fontWeight: FontWeight.w500,
        ),
        helperStyle: TextStyle(
          color: muted,
          fontWeight: FontWeight.w600,
          fontSize: 11.5,
        ),
        errorStyle: TextStyle(
          color: error,
          fontWeight: FontWeight.w600,
          fontSize: 11.5,
        ),
        errorMaxLines: 2,
        helperMaxLines: 2,
        prefixIconColor: muted,
        border: b(Colors.transparent, 0),
        enabledBorder: b(Colors.transparent, 0),
        disabledBorder: b(Colors.transparent, 0),
        focusedBorder: b(accent, 1.6),
        errorBorder: b(error.withValues(alpha: 0.75), 1.2),
        focusedErrorBorder: b(error, 1.6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final brand = _pBrand(isDark);
    // Teclado aberto em tela baixa (landscape): a barra sai para o campo em
    // foco caber; volta sozinha quando o teclado fecha.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final hideBar = keyboardOpen && MediaQuery.sizeOf(context).height < 520;

    return AppScaffold(
      title: 'Editar Perfil',
      currentBottomNavIndex: -1,
      showBottomNavigation: false,
      userName: _profile?.name,
      userEmail: _profile?.email,
      userAvatar: _profile?.avatar,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: _isLoading
            ? KeyedSubtree(
                key: const ValueKey('loading'),
                child: _buildSkeleton(context),
              )
            : _errorMessage != null
            ? Padding(
                key: ValueKey<String>('e-${_errorMessage.hashCode}'),
                padding: const EdgeInsets.all(24),
                child: _buildErrorState(),
              )
            : Column(
                key: const ValueKey('ok'),
                children: [
                  Expanded(
                    child: Theme(
                      data: _formTheme(context, brand),
                      child: SingleChildScrollView(
                        padding: _pagePadding(top: 14, bottom: 28),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildLiveBadge(context, brand),
                              _sectionBreak(context),
                              _SectionHeader(
                                title: 'Dados pessoais',
                                subtitle:
                                    'Nome que aparece no CRM e telefone de contato da equipe.',
                                tone: brand,
                              ),
                              const SizedBox(height: 14),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: _kPadH,
                                ),
                                child: _buildPersonalFields(context),
                              ),
                              _sectionBreak(context),
                              _SectionHeader(
                                title: 'Tags',
                                subtitle:
                                    'Como você é classificado nas listas e filtros. Toque para marcar ou desmarcar.',
                                tone: brand,
                                trailing: _isLoadingTags
                                    ? null
                                    : _CountPill(
                                        label:
                                            '${_selectedTagIds.length} '
                                            '${_selectedTagIds.length == 1 ? 'marcada' : 'marcadas'}',
                                        tone: brand,
                                        active: _selectedTagIds.isNotEmpty,
                                      ),
                              ),
                              const SizedBox(height: 14),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: _kPadH,
                                ),
                                child: _buildTagsSelector(context),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (!hideBar) _buildSaveBar(context),
                ],
              ),
      ),
    );
  }

  // ─── Como a equipe te vê — prévia viva do que está sendo editado ────────

  Widget _buildLiveBadge(BuildContext context, Color brand) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final email = _profile?.email ?? '';
    final chosen = _availableTags
        .where((t) => _selectedTagIds.contains(t.id))
        .toList();
    const maxShown = 6;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kPadH),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'COMO A EQUIPE TE VÊ',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: secondary,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ReadonlyAvatar(profile: _profile, tone: brand),
              const SizedBox(width: 12),
              Expanded(
                // Nome e telefone espelham a digitação.
                child: ListenableBuilder(
                  listenable: Listenable.merge([
                    _nameController,
                    _phoneController,
                  ]),
                  builder: (context, _) {
                    final live = _nameController.text.trim();
                    final phone = _phoneController.text.trim();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          live.isEmpty ? 'Seu nome' : live,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                            height: 1.15,
                            color: live.isEmpty
                                ? secondary
                                : ThemeHelpers.textColor(context),
                          ),
                        ),
                        if (email.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: secondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 2),
                        Text(
                          phone.isEmpty ? 'Sem telefone' : phone,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: phone.isEmpty
                                ? secondary
                                : ThemeHelpers.textColor(context),
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
          if (chosen.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final t in chosen.take(maxShown))
                  _MiniTag(tag: t, fallbackTone: _pTagFallback(isDark)),
                if (chosen.length > maxShown)
                  Text(
                    '+${chosen.length - maxShown}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: secondary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.photo_camera_outlined, size: 14, color: secondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'A foto muda em Meu perfil, tocando nela.',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: secondary,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Dados pessoais — 2 colunas quando cabem, e-mail travado ─────────────

  Widget _buildPersonalFields(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final fieldStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: ThemeHelpers.textColor(context),
    );
    final email = _profile?.email ?? '';

    final name = TextFormField(
      controller: _nameController,
      textInputAction: TextInputAction.next,
      style: fieldStyle,
      decoration: const InputDecoration(
        labelText: 'Nome completo *',
        prefixIcon: Icon(Icons.person_outline_rounded, size: 19),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Nome é obrigatório';
        }
        return null;
      },
    );

    final phone = TextFormField(
      controller: _phoneController,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.done,
      inputFormatters: [PhoneInputFormatter()],
      style: fieldStyle,
      decoration: const InputDecoration(
        labelText: 'Telefone',
        hintText: '(00) 00000-0000',
        prefixIcon: Icon(Icons.phone_outlined, size: 19),
      ),
    );

    return LayoutBuilder(
      builder: (context, box) {
        // Duas colunas só quando cabem de verdade (tablet/landscape); em
        // celular em pé, ou com fonte grande, um campo por linha.
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final twoCols = scale <= 1.3 && box.maxWidth >= 520;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (twoCols)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: name),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: phone),
                ],
              )
            else ...[
              name,
              const SizedBox(height: 12),
              phone,
            ],
            if (email.isNotEmpty) ...[
              const SizedBox(height: 12),
              // Aparece travado e explicado: dá para ver e copiar, não para
              // mudar por aqui.
              TextFormField(
                initialValue: email,
                readOnly: true,
                style: fieldStyle?.copyWith(color: secondary),
                decoration: InputDecoration(
                  labelText: 'E-mail de acesso',
                  helperText: 'Não muda por aqui.',
                  prefixIcon: const Icon(Icons.mail_outline_rounded, size: 19),
                  suffixIcon: Tooltip(
                    message: 'Não muda por aqui',
                    child: Icon(
                      Icons.lock_outline_rounded,
                      size: 17,
                      color: secondary,
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  // ─── Barra de salvar — fixa, acima do teclado ────────────────────────────

  Widget _buildSaveBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirm = isDark
        ? AppColors.status.successDarkMode
        : AppColors.status.success;
    // Branco no claro; grafite no escuro (o verde escuro-mode é claro).
    final onConfirm = ThemeHelpers.onPrimaryColor(context);
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final height = keyboardOpen ? 46.0 : 52.0;
    final vPad = keyboardOpen ? 8.0 : 10.0;

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        vPad,
        16,
        vPad + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border(
          top: BorderSide(color: ThemeHelpers.borderColor(context)),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
          child: Row(
            children: [
              OutlinedButton(
                onPressed: _isSaving ? null : () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(0, height),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  foregroundColor: ThemeHelpers.textSecondaryColor(context),
                  side: BorderSide(color: ThemeHelpers.borderColor(context)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Cancelar',
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _isSaving ? null : _handleSave,
                  style: FilledButton.styleFrom(
                    backgroundColor: confirm,
                    foregroundColor: onConfirm,
                    disabledBackgroundColor: confirm.withValues(alpha: 0.55),
                    disabledForegroundColor: onConfirm,
                    minimumSize: Size(0, height),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isSaving
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: onConfirm,
                          ),
                        )
                      : const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_rounded, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Salvar alterações',
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Divisores ───────────────────────────────────────────────────────────

  Widget _sectionBreak(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Container(
        height: 1,
        color: ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
      ),
    );
  }

  // ─── Skeleton (espelha o layout real) ───────────────────────────────────

  Widget _buildSkeleton(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: _pagePadding(top: 14, bottom: 28),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: _kPadH),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SkeletonText(width: 130, height: 10),
            ),
            SizedBox(height: 12),
            Row(
              children: [
                SkeletonBox(width: 56, height: 56, borderRadius: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonText(width: 150, height: 15),
                      SizedBox(height: 6),
                      SkeletonText(width: 180, height: 11),
                      SizedBox(height: 6),
                      SkeletonText(width: 110, height: 11),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: SkeletonText(width: 210, height: 11),
            ),
            SizedBox(height: 36),
            Align(
              alignment: Alignment.centerLeft,
              child: SkeletonText(width: 140, height: 18),
            ),
            SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: SkeletonText(width: 240, height: 11),
            ),
            SizedBox(height: 16),
            SkeletonBox(height: 54, borderRadius: 12),
            SizedBox(height: 12),
            SkeletonBox(height: 54, borderRadius: 12),
            SizedBox(height: 12),
            SkeletonBox(height: 54, borderRadius: 12),
            SizedBox(height: 36),
            Align(
              alignment: Alignment.centerLeft,
              child: SkeletonText(width: 80, height: 18),
            ),
            SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SkeletonBox(width: 86, height: 34, borderRadius: 999),
                SkeletonBox(width: 70, height: 34, borderRadius: 999),
                SkeletonBox(width: 100, height: 34, borderRadius: 999),
                SkeletonBox(width: 78, height: 34, borderRadius: 999),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Erro (com a causa e "Tentar de novo") ───────────────────────────────

  Widget _buildErrorState() {
    // Exceção solta traz seu próprio diagnóstico; falha de API vem da resposta.
    final cause = _errorCause;
    if (cause != null) {
      return AppErrorState(cause: cause, onRetry: _loadProfile, dense: true);
    }
    return AppErrorState.fromApi(
      message: _errorMessage,
      statusCode: _errorStatus,
      onRetry: _loadProfile,
      dense: true,
    );
  }

  // ─── Tags (chips flush com a cor real da tag) ────────────────────────────

  Widget _buildTagsSelector(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.sell_outlined,
            size: 18,
            color: ThemeHelpers.textSecondaryColor(context),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sua empresa ainda não tem tags. Quando o administrador criar, elas aparecem aqui para você marcar.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
                fontWeight: FontWeight.w600,
                height: 1.35,
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
          fallbackTone: _pTagFallback(isDark),
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
// COMPONENTES INTERNOS — gramática de formulário flush
// ════════════════════════════════════════════════════════════════════════

/// Margem lateral da tela (gramática flush do app).
const double _kPadH = 16;

/// Largura máxima da coluna em tela larga.
const double _kMaxContentWidth = 720;

/// Cor de uma tag: a cor cadastrada (hex) ou a reserva do tema.
Color _tagColorOf(Tag tag, Color fallback) {
  final raw = (tag.color ?? '').replaceAll('#', '').trim();
  if (raw.length == 6) {
    final parsed = int.tryParse(raw, radix: 16);
    if (parsed != null) return Color(0xFF000000 | parsed);
  }
  return fallback;
}

/// Cabeçalho de seção do formulário — barra tonal, título, explicação curta
/// e, à direita, um selo opcional (contagem de tags).
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.tone,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Color tone;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kPadH),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 18,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: tone,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                    height: 1.2,
                    fontSize: 18,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      fontWeight: FontWeight.w500,
                      height: 1.35,
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

/// Selo compacto tom-sobre-tom (contagem de tags marcadas).
class _CountPill extends StatelessWidget {
  const _CountPill({
    required this.label,
    required this.tone,
    required this.active,
  });

  final String label;
  final Color tone;
  final bool active;

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
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 11,
          letterSpacing: 0.2,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Avatar somente leitura da prévia — a troca de foto vive em Meu perfil
/// (evita duplicar o fluxo de envio aqui).
class _ReadonlyAvatar extends StatelessWidget {
  const _ReadonlyAvatar({required this.profile, required this.tone});

  final Profile? profile;
  final Color tone;

  static const double _size = 56;

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
    final initials = Text(
      _initials,
      style: TextStyle(color: tone, fontWeight: FontWeight.w900, fontSize: 17),
    );
    return Container(
      width: _size,
      height: _size,
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
              width: _size,
              height: _size,
              errorBuilder: (_, _, _) => initials,
            )
          : initials,
    );
  }
}

/// Tag marcada na prévia — ponto na cor real + nome (corta se for longo).
class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.tag, required this.fallbackTone});

  final Tag tag;
  final Color fallbackTone;

  @override
  Widget build(BuildContext context) {
    final tone = _tagColorOf(tag, fallbackTone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: tone.withValues(alpha: 0.1),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: tone),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              tag.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: ThemeHelpers.textColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip de tag flush: ponto na COR REAL da tag + tom-sobre-tom quando
/// marcada. Nome longo corta com reticências (nunca estoura a linha).
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = _tagColorOf(tag, fallbackTone);

    final borderColor = selected
        ? tone.withValues(alpha: 0.5)
        : ThemeHelpers.borderColor(context);
    final bgColor = selected
        ? tone.withValues(alpha: isDark ? 0.16 : 0.1)
        : Colors.transparent;
    final labelColor = selected
        ? ThemeHelpers.textColor(context)
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
              Flexible(
                child: Text(
                  tag.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: labelColor,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 12.5,
                  ),
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
