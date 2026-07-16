import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/zezin_models.dart';
import '../services/zezin_service.dart';

/// Configuração do **Zezin** — número + token do WhatsApp Business
/// (paridade com `ZezinConfigPage.tsx` do imobx-front). Com a configuração
/// ativa, quem mandar mensagem para o número no WhatsApp também recebe a
/// resposta da IA — o chat do app funciona independentemente disso.
class ZezinConfigPage extends StatefulWidget {
  const ZezinConfigPage({super.key});

  @override
  State<ZezinConfigPage> createState() => _ZezinConfigPageState();
}

class _ZezinConfigPageState extends State<ZezinConfigPage> {
  static const double _kPadH = 16;

  final ZezinService _service = ZezinService.instance;

  ZezinAvailability? _availability;
  bool _loading = true;
  String? _loadError;

  ZezinConfig? _existingConfig;
  bool _saving = false;
  bool _showToken = false;
  bool _isActive = true;

  final TextEditingController _phoneNumberIdController =
      TextEditingController();
  final TextEditingController _apiTokenController = TextEditingController();
  final TextEditingController _phoneNumberController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _phoneNumberIdController.dispose();
    _apiTokenController.dispose();
    _phoneNumberController.dispose();
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
      _loading = true;
      _loadError = null;
    });
    final availabilityRes = await _service.getAvailability();
    if (!mounted) return;
    if (!availabilityRes.success) {
      setState(() {
        _loading = false;
        _loadError =
            availabilityRes.message ?? 'Não foi possível verificar o Zezin.';
      });
      return;
    }
    final availability = availabilityRes.data ?? ZezinAvailability.unavailable;
    if (!availability.available) {
      setState(() {
        _loading = false;
        _availability = availability;
      });
      return;
    }

    final configRes = await _service.getConfig();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _availability = availability;
      if (configRes.success) {
        _existingConfig = configRes.data;
        _phoneNumberIdController.text = _existingConfig?.phoneNumberId ?? '';
        _phoneNumberController.text = _existingConfig?.phoneNumber ?? '';
        // Token nunca é reexibido (vem mascarado do backend).
        _apiTokenController.clear();
        _isActive = _existingConfig?.isActive ?? true;
      } else {
        _loadError =
            configRes.message ?? 'Não foi possível carregar a configuração.';
      }
    });
  }

  bool get _canSave {
    if (_saving) return false;
    if (_phoneNumberIdController.text.trim().isEmpty) return false;
    // Primeira configuração exige o token completo.
    if (_existingConfig == null && _apiTokenController.text.trim().isEmpty) {
      return false;
    }
    return true;
  }

  Future<void> _save() async {
    final phoneNumberId = _phoneNumberIdController.text.trim();
    final apiToken = _apiTokenController.text.trim();
    final phoneNumber = _phoneNumberController.text.trim();

    if (phoneNumberId.isEmpty) {
      _showSnack('O ID do número de telefone é obrigatório.', isError: true);
      return;
    }
    if (_existingConfig == null && apiToken.isEmpty) {
      _showSnack(
        'O token de acesso é obrigatório na primeira configuração.',
        isError: true,
      );
      return;
    }

    setState(() => _saving = true);

    final res = _existingConfig != null && apiToken.isEmpty
        // Atualização parcial sem trocar o token (paridade web: PUT).
        ? await _service.updateConfig(
            phoneNumberId: phoneNumberId,
            phoneNumber: phoneNumber.isEmpty ? null : phoneNumber,
            isActive: _isActive,
          )
        : await _service.createOrUpdateConfig(
            phoneNumberId: phoneNumberId,
            apiToken: apiToken,
            phoneNumber: phoneNumber.isEmpty ? null : phoneNumber,
            isActive: _isActive,
          );

    if (!mounted) return;
    setState(() => _saving = false);

    if (res.success) {
      _showSnack('Configuração do Zezin salva com sucesso!');
      // Recarrega para refletir o token mascarado + status.
      // ignore: unawaited_futures
      _bootstrap();
    } else {
      _showSnack(
        res.message ?? 'Erro ao salvar configuração.',
        isError: true,
      );
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError
            ? (isDark ? AppColors.status.errorDarkMode : AppColors.status.error)
            : null,
        content: Text(message),
      ),
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Configurar Zezin',
      showBottomNavigation: false,
      showDrawer: false,
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return _buildSkeleton(context);
    if (_loadError != null) return _buildErrorState(context);
    if (_availability?.available != true) return _buildDeniedState(context);
    return _buildForm(context);
  }

  // ─── Hero flush ──────────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = _tone(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final amber =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;

    // Cor por significado: verde = ativa, âmbar = inativa/pendente.
    final (statusColor, statusIcon, statusLabel) = _existingConfig == null
        ? (amber, LucideIcons.triangleAlert, 'Não configurado')
        : _existingConfig!.isActive
            ? (emerald, LucideIcons.badgeCheck, 'Configuração ativa')
            : (amber, LucideIcons.power, 'Configuração inativa');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
                  BoxShadow(color: tone.withValues(alpha: 0.5), blurRadius: 6),
                ],
              ),
            ),
            const SizedBox(width: 7),
            Text(
              'ZEZIN · WHATSAPP',
              style: theme.textTheme.labelSmall?.copyWith(
                color: tone,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.8,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Configuração do Zezin',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: ThemeHelpers.textColor(context),
            letterSpacing: -0.6,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Informe o número e o token do WhatsApp Business para o Zezin '
          'responder também no WhatsApp — quem mandar mensagem para esse '
          'número recebe a resposta da IA com os dados da empresa.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: secondary,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _heroChip(context, statusIcon, statusLabel, statusColor),
            if (_existingConfig?.phoneNumber?.trim().isNotEmpty == true)
              _heroChip(
                context,
                LucideIcons.phone,
                _existingConfig!.phoneNumber!.trim(),
                secondary,
              ),
          ],
        ),
      ],
    );
  }

  Widget _heroChip(
      BuildContext context, IconData icon, String label, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: isDark ? 0.4 : 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Formulário ──────────────────────────────────────────────────────────

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = _tone(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final emerald =
        isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
    final hasExisting = _existingConfig != null;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(_kPadH, 12, _kPadH, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHero(context),
          const SizedBox(height: 20),

          _sectionHeader(
            context,
            icon: LucideIcons.hash,
            eyebrow: 'CREDENCIAIS',
            title: 'Número e token do WhatsApp',
            hint:
                'Dados do painel do Facebook (WhatsApp Business → Números de telefone).',
          ),
          const SizedBox(height: 14),

          _fieldLabel(context, 'ID do número de telefone', required: true),
          const SizedBox(height: 6),
          _buildTextField(
            context,
            controller: _phoneNumberIdController,
            hint: 'Ex.: 123456789012345',
            icon: LucideIcons.hash,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          _helpText(
            context,
            'No painel do Facebook, copie o "ID do número" (Phone Number ID).',
          ),
          const SizedBox(height: 16),

          _fieldLabel(context, 'Token de acesso', required: !hasExisting),
          const SizedBox(height: 6),
          _buildTextField(
            context,
            controller: _apiTokenController,
            hint: hasExisting
                ? 'Deixe em branco para não alterar'
                : 'Cole o token permanente',
            icon: LucideIcons.keyRound,
            obscure: !_showToken,
            suffix: IconButton(
              onPressed: _saving
                  ? null
                  : () => setState(() => _showToken = !_showToken),
              tooltip: _showToken ? 'Ocultar token' : 'Mostrar token',
              icon: Icon(
                _showToken ? LucideIcons.eyeOff : LucideIcons.eye,
                size: 17,
                color: secondary,
              ),
            ),
          ),
          _helpText(
            context,
            hasExisting
                ? 'O token atual está salvo (${_existingConfig?.apiTokenMasked ?? '••••'}). '
                    'Preencha apenas se quiser trocá-lo.'
                : 'Chave de acesso permanente do WhatsApp Business '
                    '(Configurações do sistema → WhatsApp).',
          ),
          const SizedBox(height: 16),

          _fieldLabel(context, 'Número de telefone (opcional)'),
          const SizedBox(height: 6),
          _buildTextField(
            context,
            controller: _phoneNumberController,
            hint: '5511999999999',
            icon: LucideIcons.smartphone,
            keyboardType: TextInputType.phone,
            maxLength: 15,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          _helpText(
            context,
            'Formato internacional, só dígitos — apenas para identificação.',
          ),
          const SizedBox(height: 20),

          // Ativa/inativa — ação no próprio item.
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _saving
                  ? null
                  : () => setState(() => _isActive = !_isActive),
              borderRadius: BorderRadius.circular(14),
              child: Ink(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: ThemeHelpers.cardBackgroundColor(context),
                  border: Border.all(
                    color: _isActive
                        ? emerald.withValues(alpha: 0.35)
                        : ThemeHelpers.borderLightColor(context),
                  ),
                  boxShadow: ThemeHelpers.cardShadow(context, strength: 0.5),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isActive ? LucideIcons.circleCheck : LucideIcons.power,
                      size: 17,
                      color: _isActive ? emerald : secondary,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Configuração ativa',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: ThemeHelpers.textColor(context),
                            ),
                          ),
                          Text(
                            _isActive
                                ? 'O Zezin responde no WhatsApp deste número.'
                                : 'Respostas no WhatsApp ficam pausadas.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: _isActive,
                      activeTrackColor: emerald,
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _isActive = v),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Salvar.
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _canSave ? _save : null,
              style: FilledButton.styleFrom(
                backgroundColor: tone,
                foregroundColor: Colors.white,
                disabledBackgroundColor: tone.withValues(alpha: 0.35),
                disabledForegroundColor: Colors.white70,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  letterSpacing: 0.1,
                ),
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(LucideIcons.save, size: 18),
              label: Text(
                _saving
                    ? 'Salvando…'
                    : hasExisting
                        ? 'Atualizar configuração'
                        : 'Salvar configuração',
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Como funciona — informativo flush em violeta (identidade da IA).
          _sectionHeader(
            context,
            icon: LucideIcons.messageCircle,
            eyebrow: 'COMO FUNCIONA',
            title: 'Zezin no app e no WhatsApp',
            hint: 'O mesmo assistente, em dois canais.',
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: tone.withValues(alpha: isDark ? 0.1 : 0.06),
              border: Border.all(color: tone.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow(
                  context,
                  LucideIcons.bot,
                  'O chat "Pergunte ao Zezin" do app já funciona sem esta '
                  'configuração — ela é só para o canal WhatsApp.',
                ),
                const SizedBox(height: 10),
                _infoRow(
                  context,
                  LucideIcons.messageCircle,
                  'Com número e token ativos, quem enviar mensagem para o '
                  'número recebe a resposta da IA direto no WhatsApp.',
                ),
                const SizedBox(height: 10),
                _infoRow(
                  context,
                  LucideIcons.shieldCheck,
                  'Não compartilhe o token em canais inseguros; rotacione a '
                  'chave se suspeitar de vazamento.',
                ),
              ],
            ),
          ),
        ],
      ).animate().fadeIn(duration: 240.ms),
    );
  }

  Widget _sectionHeader(
    BuildContext context, {
    required IconData icon,
    required String eyebrow,
    required String title,
    required String hint,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = _tone(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: tone.withValues(alpha: isDark ? 0.2 : 0.12),
          ),
          child: Icon(icon, color: tone, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                  Text(
                    eyebrow,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: tone,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  height: 1.32,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _fieldLabel(BuildContext context, String label,
      {bool required = false}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    return Row(
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: ThemeHelpers.textColor(context),
          ),
        ),
        if (required) ...[
          const SizedBox(width: 3),
          Text(
            '*',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: danger,
            ),
          ),
        ],
      ],
    );
  }

  Widget _helpText(BuildContext context, String text) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.only(top: 5, left: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1.5),
            child: Icon(LucideIcons.info, size: 12, color: secondary),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondary,
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    BuildContext context, {
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone = _tone(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return TextField(
      controller: controller,
      enabled: !_saving,
      obscureText: obscure,
      keyboardType: keyboardType,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      cursorColor: tone,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: ThemeHelpers.textColor(context),
        fontWeight: FontWeight.w700,
      ),
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
        hintStyle: theme.textTheme.bodyMedium?.copyWith(
          color: secondary.withValues(alpha: 0.7),
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: Icon(icon, size: 17, color: secondary),
        suffixIcon: suffix,
        filled: true,
        fillColor: ThemeHelpers.cardBackgroundColor(context),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: tone.withValues(alpha: isDark ? 0.55 : 0.45),
            width: 1.4,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: ThemeHelpers.borderLightColor(context),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);
    final tone = _tone(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: tone),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ThemeHelpers.textColor(context),
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  // ─── Estados: skeleton / erro / indisponível ─────────────────────────────

  /// Skeleton fiel ao formulário real (hero + campos + botão).
  Widget _buildSkeleton(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(_kPadH, 12, _kPadH, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          SkeletonText(width: 130, height: 11, borderRadius: 999),
          SizedBox(height: 10),
          SkeletonText(width: 230, height: 24, borderRadius: 8),
          SizedBox(height: 8),
          SkeletonText(width: double.infinity, height: 13),
          SizedBox(height: 6),
          SkeletonText(width: 280, height: 13),
          SizedBox(height: 14),
          SkeletonBox(width: 150, height: 26, borderRadius: 999),
          SizedBox(height: 26),
          SkeletonText(width: 170, height: 12),
          SizedBox(height: 8),
          SkeletonBox(width: double.infinity, height: 50, borderRadius: 14),
          SizedBox(height: 18),
          SkeletonText(width: 130, height: 12),
          SizedBox(height: 8),
          SkeletonBox(width: double.infinity, height: 50, borderRadius: 14),
          SizedBox(height: 18),
          SkeletonText(width: 200, height: 12),
          SizedBox(height: 8),
          SkeletonBox(width: double.infinity, height: 50, borderRadius: 14),
          SizedBox(height: 22),
          SkeletonBox(width: double.infinity, height: 62, borderRadius: 14),
          SizedBox(height: 22),
          SkeletonBox(width: double.infinity, height: 52, borderRadius: 15),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
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
              _loadError ?? 'Não foi possível carregar.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _bootstrap,
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
              'A configuração do Zezin é exclusiva para administradores no '
              'plano Pro com o módulo Assistente de IA.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondary,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
