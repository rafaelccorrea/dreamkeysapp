import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/sdr_settings_model.dart';
import '../services/sdr_service.dart';

/// Configurações do **SDR com IA** — paridade funcional com a
/// `SDRSettingsPage.tsx` do painel web, reorganizada para mobile:
/// hero flush com o interruptor mestre, seções flush com eyebrow + filete
/// (mesma gramática do dashboard SDR), toggles na própria linha, steppers
/// compactos para números, time-pickers para o horário de atendimento e
/// barra de ações fixa (Resetar / Salvar).
///
/// Gating: módulo `whatsapp_ai` + permissão `whatsapp:manage_config`.
/// O backend ainda restringe a escrita ao líder SDR / admin (403 tratado).
class SdrSettingsPage extends StatefulWidget {
  const SdrSettingsPage({super.key});

  @override
  State<SdrSettingsPage> createState() => _SdrSettingsPageState();
}

class _SdrSettingsPageState extends State<SdrSettingsPage> {
  static const double _kPadH = 16;

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  /// Estado editável da tela (campos não textuais).
  SdrSettings? _settings;

  /// Última versão persistida — base do indicador de alterações não salvas.
  SdrSettings? _original;

  final TextEditingController _greetingCtrl = TextEditingController();
  final TextEditingController _signatureCtrl = TextEditingController();
  final TextEditingController _blacklistCtrl = TextEditingController();

  bool get _hasAccess =>
      ModuleAccessService.instance.hasCompanyModule('whatsapp_ai') &&
      ModuleAccessService.instance.hasPermission('whatsapp:manage_config');

  @override
  void initState() {
    super.initState();
    _greetingCtrl.addListener(_onTextChanged);
    _signatureCtrl.addListener(_onTextChanged);
    _blacklistCtrl.addListener(_onTextChanged);
    _loadSettings();
  }

  @override
  void dispose() {
    _greetingCtrl.dispose();
    _signatureCtrl.dispose();
    _blacklistCtrl.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  // ─── Cores semânticas (mesma régua do dashboard SDR) ───────────────────────

  Color _accent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.primary.primaryDarkMode
          : AppColors.primary.primary;

  Color _green(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.status.greenDarkMode
          : AppColors.status.green;

  Color _amber(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.status.warningDarkMode
          : AppColors.status.warning;

  Color _red(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.status.errorDarkMode
          : AppColors.status.error;

  Color _blue(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.status.blueDarkMode
          : AppColors.status.blue;

  Color _purple(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.status.purpleDarkMode
          : AppColors.status.purple;

  Color _fieldFill(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.background.backgroundTertiaryDarkMode
          : AppColors.background.backgroundTertiary;

  // ─── Dados ─────────────────────────────────────────────────────────────────

  Future<void> _loadSettings() async {
    if (!_hasAccess) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final res = await SdrService.instance.getSettings();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (res.success && res.data != null) {
        _applyLoaded(res.data!);
      } else {
        _errorMessage =
            res.message ?? 'Erro ao carregar configurações do SDR';
      }
    });
  }

  /// Sincroniza estado + controllers com uma versão persistida.
  void _applyLoaded(SdrSettings s) {
    _settings = s;
    _original = s;
    _greetingCtrl.text = s.greetingMessage;
    _signatureCtrl.text = s.signature;
    _blacklistCtrl.text = s.phraseBlacklist.join('\n');
  }

  /// Estado atual da tela (campos + textos), pronto para o PUT.
  SdrSettings _currentSettings() {
    final base = _settings ?? SdrSettings.defaults();
    final blacklist = _blacklistCtrl.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList(growable: false);
    return base.copyWith(
      greetingMessage: _greetingCtrl.text.length > 500
          ? _greetingCtrl.text.substring(0, 500)
          : _greetingCtrl.text,
      signature: _signatureCtrl.text.length > 200
          ? _signatureCtrl.text.substring(0, 200)
          : _signatureCtrl.text,
      phraseBlacklist: blacklist,
    );
  }

  bool get _isDirty {
    if (_original == null || _settings == null) return false;
    return jsonEncode(_currentSettings().toUpdateJson()) !=
        jsonEncode(_original!.toUpdateJson());
  }

  void _patch(SdrSettings Function(SdrSettings s) fn) {
    final s = _settings;
    if (s == null || _isSaving) return;
    setState(() => _settings = fn(s));
  }

  Future<void> _save({SdrSettings? override, String? successMessage}) async {
    if (_isSaving) return;
    final payload = override ?? _currentSettings();
    setState(() => _isSaving = true);
    final res = await SdrService.instance.updateSettings(payload);
    if (!mounted) return;
    setState(() {
      _isSaving = false;
      if (res.success && res.data != null) {
        _applyLoaded(res.data!);
      }
    });
    if (res.success) {
      _showSnack(
        successMessage ?? 'Configurações salvas com sucesso!',
        ok: true,
      );
    } else {
      _showSnack(
        res.message ?? 'Erro ao salvar configurações do SDR',
        ok: false,
      );
    }
  }

  Future<void> _confirmReset() async {
    final accent = _accent(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          backgroundColor: ThemeHelpers.cardBackgroundColor(ctx),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(LucideIcons.rotateCcw, color: accent, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Resetar configurações?',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Todas as configurações do SDR serão restauradas para os valores '
            'padrão. Esta ação não pode ser desfeita.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textSecondaryColor(ctx),
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'Cancelar',
                style: TextStyle(
                  color: ThemeHelpers.textSecondaryColor(ctx),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(LucideIcons.rotateCcw, size: 16),
              label: const Text(
                'Resetar',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    // Paridade com o web: reset = PUT com o DTO padrão completo.
    await _save(
      override: SdrSettings.defaults(),
      successMessage: 'Configurações resetadas para os valores padrão!',
    );
  }

  void _showSnack(String msg, {required bool ok}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            ok ? AppColors.status.success : AppColors.status.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ─── Horário de atendimento ────────────────────────────────────────────────

  TimeOfDay _parseHms(String hms, TimeOfDay fallback) {
    final parts = hms.split(':');
    final h = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
    final m = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (h == null || h < 0 || h > 23) return fallback;
    return TimeOfDay(hour: h, minute: (m ?? 0).clamp(0, 59));
  }

  String _toHms(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  Future<void> _pickBusinessHour({required bool isStart}) async {
    final s = _settings;
    if (s == null) return;
    final initial = _parseHms(
      isStart ? s.businessHoursStart : s.businessHoursEnd,
      isStart
          ? const TimeOfDay(hour: 8, minute: 0)
          : const TimeOfDay(hour: 18, minute: 0),
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText:
          isStart ? 'Início do atendimento da IA' : 'Fim do atendimento da IA',
      cancelText: 'Cancelar',
      confirmText: 'Confirmar',
    );
    if (picked == null || !mounted) return;
    _patch((s) => isStart
        ? s.copyWith(businessHoursStart: _toHms(picked))
        : s.copyWith(businessHoursEnd: _toHms(picked)));
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_hasAccess) {
      return const AppScaffold(
        title: 'Configurações do SDR',
        showBottomNavigation: false,
        showDrawer: false,
        body: _DeniedView(),
      );
    }

    return AppScaffold(
      title: 'Configurações do SDR',
      showBottomNavigation: false,
      showDrawer: false,
      body: _isLoading
          ? _buildSkeleton(context)
          : _errorMessage != null
              ? _buildError(context)
              : _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final s = _settings!;
    final disabled = !s.enabled || _isSaving;

    final sections = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHero(context, s),
        const SizedBox(height: 22),

        // Gerais.
        _SectionHeader(
          tone: _accent(context),
          label: 'Configurações gerais',
          hint: 'Resposta automática e atraso mínimo entre respostas.',
        ),
        _ToggleRow(
          title: 'Resposta automática',
          description: 'O SDR responde sozinho as mensagens recebidas.',
          value: s.autoRespond,
          tone: _accent(context),
          disabled: disabled,
          onChanged: (v) => _patch((s) => s.copyWith(autoRespond: v)),
        ),
        _StepperRow(
          title: 'Atraso de resposta',
          description:
              'Espera antes de enviar. Mínimo de 8s para evitar gargalos.',
          value: s.responseDelaySeconds,
          min: 8,
          max: 60,
          step: 1,
          unit: 'seg',
          tone: _accent(context),
          disabled: disabled,
          onChanged: (v) =>
              _patch((s) => s.copyWith(responseDelaySeconds: v)),
        ),

        // Ações automáticas.
        _SectionHeader(
          tone: _purple(context),
          label: 'O que o sistema faz sozinho',
          hint: 'Ações executadas sem intervenção humana ao receber mensagens.',
        ),
        _ToggleRow(
          title: 'Criar cliente automaticamente',
          description:
              'Cria um cliente com os dados da conversa. Recomendado: desativado.',
          value: s.canCreateLead,
          tone: _purple(context),
          disabled: disabled,
          onChanged: (v) => _patch((s) => s.copyWith(canCreateLead: v)),
        ),
        _ToggleRow(
          title: 'Criar tarefa no funil automaticamente',
          description:
              'Cria uma tarefa no funil sozinho. Recomendado: desativado.',
          value: s.canAddToFunnel,
          tone: _purple(context),
          disabled: disabled,
          onChanged: (v) => _patch((s) => s.copyWith(canAddToFunnel: v)),
        ),

        // Gestão de leads.
        _SectionHeader(
          tone: _blue(context),
          label: 'Gestão de leads',
          hint: 'Alterar status, adicionar notas e atribuir leads a corretores.',
        ),
        _ToggleRow(
          title: 'Atualizar status de leads',
          description: 'Permite que o SDR atualize o status dos leads.',
          value: s.canUpdateLeadStatus,
          tone: _blue(context),
          disabled: disabled,
          onChanged: (v) => _patch((s) => s.copyWith(canUpdateLeadStatus: v)),
        ),
        _ToggleRow(
          title: 'Adicionar notas',
          description: 'Permite que o SDR adicione notas aos leads.',
          value: s.canAddLeadNote,
          tone: _blue(context),
          disabled: disabled,
          onChanged: (v) => _patch((s) => s.copyWith(canAddLeadNote: v)),
        ),
        _ToggleRow(
          title: 'Atribuir leads',
          description: 'Permite que o SDR atribua leads a corretores.',
          value: s.canAssignLead,
          tone: _blue(context),
          disabled: disabled,
          onChanged: (v) => _patch((s) => s.copyWith(canAssignLead: v)),
        ),

        // Gestão de visitas.
        _SectionHeader(
          tone: _green(context),
          label: 'Gestão de visitas',
          hint: 'Agendamento, reagendamento, cancelamento e confirmação.',
        ),
        _ToggleRow(
          title: 'Agendar visitas',
          description: 'Permite que o SDR agende visitas aos imóveis.',
          value: s.canScheduleVisit,
          tone: _green(context),
          disabled: disabled,
          onChanged: (v) => _patch((s) => s.copyWith(canScheduleVisit: v)),
        ),
        _ToggleRow(
          title: 'Reagendar visitas',
          description: 'Permite que o SDR reagende visitas existentes.',
          value: s.canRescheduleVisit,
          tone: _green(context),
          disabled: disabled,
          onChanged: (v) => _patch((s) => s.copyWith(canRescheduleVisit: v)),
        ),
        _ToggleRow(
          title: 'Cancelar visitas',
          description: 'Permite que o SDR cancele visitas.',
          value: s.canCancelVisit,
          tone: _green(context),
          disabled: disabled,
          onChanged: (v) => _patch((s) => s.copyWith(canCancelVisit: v)),
        ),
        _ToggleRow(
          title: 'Exigir confirmação',
          description: 'Exige confirmação do cliente antes de agendar visita.',
          value: s.requireVisitConfirmation,
          tone: _green(context),
          disabled: disabled,
          onChanged: (v) =>
              _patch((s) => s.copyWith(requireVisitConfirmation: v)),
        ),

        // Comunicação.
        _SectionHeader(
          tone: _blue(context),
          label: 'Comunicação',
          hint: 'Canais e tipos de mensagem que o SDR pode enviar.',
        ),
        _ToggleRow(
          title: 'Enviar WhatsApp',
          description: 'Permite que o SDR envie mensagens via WhatsApp.',
          value: s.canSendWhatsapp,
          tone: _blue(context),
          disabled: disabled,
          onChanged: (v) => _patch((s) => s.copyWith(canSendWhatsapp: v)),
        ),
        _ToggleRow(
          title: 'Enviar e-mail',
          description: 'Permite que o SDR envie e-mails.',
          value: s.canSendEmail,
          tone: _blue(context),
          disabled: disabled,
          onChanged: (v) => _patch((s) => s.copyWith(canSendEmail: v)),
        ),
        _ToggleRow(
          title: 'Enviar SMS',
          description: 'Permite que o SDR envie SMS.',
          value: s.canSendSms,
          tone: _blue(context),
          disabled: disabled,
          onChanged: (v) => _patch((s) => s.copyWith(canSendSms: v)),
        ),
        _ToggleRow(
          title: 'Enviar folhetos de imóveis',
          description: 'Permite que o SDR envie folhetos de imóveis.',
          value: s.canSendPropertyBrochure,
          tone: _blue(context),
          disabled: disabled,
          onChanged: (v) =>
              _patch((s) => s.copyWith(canSendPropertyBrochure: v)),
        ),

        // Follow-ups.
        _SectionHeader(
          tone: _amber(context),
          label: 'Follow-ups e lembretes',
          hint: 'Retornos automáticos e lembretes após o último contato.',
        ),
        _ToggleRow(
          title: 'Agendar follow-ups',
          description: 'Permite que o SDR agende follow-ups automáticos.',
          value: s.canScheduleFollowup,
          tone: _amber(context),
          disabled: disabled,
          onChanged: (v) => _patch((s) => s.copyWith(canScheduleFollowup: v)),
        ),
        _ToggleRow(
          title: 'Enviar lembretes',
          description: 'Permite que o SDR envie lembretes automáticos.',
          value: s.canSendReminders,
          tone: _amber(context),
          disabled: disabled,
          onChanged: (v) => _patch((s) => s.copyWith(canSendReminders: v)),
        ),
        _StepperRow(
          title: 'Dias para follow-up automático',
          description: 'Dias após o último contato (1–30).',
          value: s.autoFollowupDays,
          min: 1,
          max: 30,
          step: 1,
          unit: 'dias',
          tone: _amber(context),
          disabled: disabled,
          onChanged: (v) => _patch((s) => s.copyWith(autoFollowupDays: v)),
        ),

        // Inteligência de negócio.
        _SectionHeader(
          tone: _purple(context),
          label: 'Inteligência de negócio',
          hint: 'Recomendação, financiamento, comparação e info de bairros.',
        ),
        _ToggleRow(
          title: 'Recomendar imóveis',
          description: 'Recomenda imóveis com base no perfil do cliente.',
          value: s.canRecommendProperties,
          tone: _purple(context),
          disabled: disabled,
          onChanged: (v) =>
              _patch((s) => s.copyWith(canRecommendProperties: v)),
        ),
        _ToggleRow(
          title: 'Calcular financiamento',
          description: 'Calcula simulações de financiamento.',
          value: s.canCalculateFinancing,
          tone: _purple(context),
          disabled: disabled,
          onChanged: (v) =>
              _patch((s) => s.copyWith(canCalculateFinancing: v)),
        ),
        _ToggleRow(
          title: 'Comparar imóveis',
          description: 'Compara diferentes imóveis.',
          value: s.canCompareProperties,
          tone: _purple(context),
          disabled: disabled,
          onChanged: (v) => _patch((s) => s.copyWith(canCompareProperties: v)),
        ),
        _ToggleRow(
          title: 'Informações de bairro',
          description: 'Fornece informações sobre bairros.',
          value: s.canProvideNeighborhoodInfo,
          tone: _purple(context),
          disabled: disabled,
          onChanged: (v) =>
              _patch((s) => s.copyWith(canProvideNeighborhoodInfo: v)),
        ),

        // Limites.
        _SectionHeader(
          tone: _red(context),
          label: 'Limites e restrições',
          hint: 'Tetos por busca, mensagens e visitas para evitar uso excessivo.',
        ),
        _StepperRow(
          title: 'Máximo de imóveis por busca',
          description: 'Entre 1 e 12.',
          value: s.maxPropertiesPerSearch,
          min: 1,
          max: 12,
          step: 1,
          unit: 'imóveis',
          tone: _red(context),
          disabled: disabled,
          onChanged: (v) =>
              _patch((s) => s.copyWith(maxPropertiesPerSearch: v)),
        ),
        _StepperRow(
          title: 'Máximo de mensagens por dia',
          description: 'Entre 1 e 50.',
          value: s.maxMessagesPerDay,
          min: 1,
          max: 50,
          step: 1,
          unit: 'msg/dia',
          tone: _red(context),
          disabled: disabled,
          onChanged: (v) => _patch((s) => s.copyWith(maxMessagesPerDay: v)),
        ),
        _StepperRow(
          title: 'Máximo de visitas por dia',
          description: 'Entre 1 e 10.',
          value: s.maxVisitsPerDay,
          min: 1,
          max: 10,
          step: 1,
          unit: 'visitas',
          tone: _red(context),
          disabled: disabled,
          onChanged: (v) => _patch((s) => s.copyWith(maxVisitsPerDay: v)),
        ),

        // Horário de atendimento.
        _SectionHeader(
          tone: _amber(context),
          label: 'Horário de atendimento',
          hint:
              'Janela em que a IA atende (horário local da empresa). Fora dela, '
              'as mensagens aguardam o próximo expediente.',
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            children: [
              Expanded(
                child: _TimeControl(
                  label: 'Início',
                  value: SdrSettings.hourLabel(s.businessHoursStart),
                  tone: _amber(context),
                  fill: _fieldFill(context),
                  disabled: disabled,
                  onTap: () => _pickBusinessHour(isStart: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TimeControl(
                  label: 'Fim',
                  value: SdrSettings.hourLabel(s.businessHoursEnd),
                  tone: _amber(context),
                  fill: _fieldFill(context),
                  disabled: disabled,
                  onTap: () => _pickBusinessHour(isStart: false),
                ),
              ),
            ],
          ),
        ),
        _ToggleRow(
          title: 'Atender nos fins de semana',
          description: 'Sábados e domingos entram na janela de atendimento.',
          value: s.workOnWeekends,
          tone: _amber(context),
          disabled: disabled,
          onChanged: (v) => _patch((s) => s.copyWith(workOnWeekends: v)),
        ),

        // Personalização.
        _SectionHeader(
          tone: _green(context),
          label: 'Personalização',
          hint: 'Saudação, assinatura e tom de voz do Zezin.',
        ),
        _TextArea(
          label: 'Mensagem de saudação',
          controller: _greetingCtrl,
          hint:
              'Ex: Olá! Sou o Zezin, assistente da sua imobiliária. Como posso te ajudar hoje?',
          maxLength: 500,
          minLines: 3,
          fill: _fieldFill(context),
          disabled: disabled,
        ),
        _TextArea(
          label: 'Assinatura',
          controller: _signatureCtrl,
          hint: 'Ex: Atenciosamente, Zezin — Equipe da sua imobiliária',
          maxLength: 200,
          minLines: 2,
          fill: _fieldFill(context),
          disabled: disabled,
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            'Tom de voz',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textColor(context),
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tone in SdrTone.values)
                _ToneChip(
                  label: tone.label,
                  selected: s.tone == tone,
                  accent: _green(context),
                  fill: _fieldFill(context),
                  disabled: disabled,
                  onTap: () => _patch((s) => s.copyWith(tone: tone)),
                ),
            ],
          ),
        ),

        // IA e contexto.
        _SectionHeader(
          tone: _purple(context),
          label: 'IA e contexto',
          hint:
              'Janela de contexto, reengajamento, blacklist e confirmação de handoff.',
        ),
        _StepperRow(
          title: 'Janela de contexto',
          description:
              'Horas da conversa usadas como contexto (1–168). Depois, trata como novo atendimento.',
          value: s.aiContextHours,
          min: 1,
          max: 168,
          step: 1,
          unit: 'horas',
          tone: _purple(context),
          disabled: disabled,
          onChanged: (v) => _patch((s) => s.copyWith(aiContextHours: v)),
        ),
        _ToggleRow(
          title: 'Reengajamento automático',
          description:
              'Mensagens de reengajamento após inatividade (quando implementado).',
          value: s.reengagementEnabled,
          tone: _purple(context),
          disabled: disabled,
          onChanged: (v) => _patch((s) => s.copyWith(reengagementEnabled: v)),
        ),
        _StepperRow(
          title: 'Horas para reengajamento',
          description:
              'Horas de inatividade antes de considerar reengajamento (1–168).',
          value: s.reengagementHours,
          min: 1,
          max: 168,
          step: 1,
          unit: 'horas',
          tone: _purple(context),
          disabled: disabled || !s.reengagementEnabled,
          onChanged: (v) => _patch((s) => s.copyWith(reengagementHours: v)),
        ),
        _ToggleRow(
          title: 'Confirmar antes do atendente',
          description:
              'Ao pedir atendente humano, a IA confirma antes do handoff (quando implementado).',
          value: s.requireHandoffConfirmation,
          tone: _purple(context),
          disabled: disabled,
          onChanged: (v) =>
              _patch((s) => s.copyWith(requireHandoffConfirmation: v)),
        ),
        _TextArea(
          label: 'Blacklist de frases',
          controller: _blacklistCtrl,
          hint:
              'Uma frase por linha. Mensagens da IA que contenham alguma delas serão bloqueadas.',
          minLines: 3,
          fill: _fieldFill(context),
          disabled: disabled,
          helper:
              'Frases que a IA não pode usar na resposta (uma por linha). '
              'Deixe vazio para não bloquear.',
        ),
      ],
    );

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(_kPadH, 10, _kPadH, 28),
            child: sections
                .animate(key: const ValueKey('sdr-settings-content'))
                .fadeIn(duration: 240.ms),
          ),
        ),
        _buildActionBar(context),
      ],
    );
  }

  // ─── Hero flush com interruptor mestre ─────────────────────────────────────

  Widget _buildHero(BuildContext context, SdrSettings s) {
    final theme = Theme.of(context);
    final accent = _accent(context);
    final green = _green(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final dot = s.enabled ? green : secondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dot,
                boxShadow: [
                  BoxShadow(
                    color: dot.withValues(alpha: 0.55),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'SDR COM IA · CONFIGURAÇÕES',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.2,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          s.enabled ? 'SDR ativado' : 'SDR desativado',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: ThemeHelpers.textColor(context),
            letterSpacing: -0.6,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Defina o que o Zezin pode fazer no atendimento ao lead: resposta '
          'automática, gestão de leads e visitas, comunicação, limites de uso '
          'e tom de voz.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: secondary,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: BoxDecoration(
            color: ThemeHelpers.cardBackgroundColor(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: s.enabled
                  ? green.withValues(alpha: 0.35)
                  : ThemeHelpers.borderLightColor(context),
            ),
            boxShadow: ThemeHelpers.cardShadow(context),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: (s.enabled ? green : secondary)
                      .withValues(alpha: 0.14),
                ),
                child: Icon(
                  s.enabled ? LucideIcons.botMessageSquare : LucideIcons.botOff,
                  color: s.enabled ? green : secondary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.enabled
                          ? 'Assistente em operação'
                          : 'Assistente pausado',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.enabled
                          ? 'O assistente está atuando no pré-atendimento.'
                          : 'Ative para o assistente começar a responder.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: secondary,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch.adaptive(
                value: s.enabled,
                activeTrackColor: green,
                onChanged: _isSaving
                    ? null
                    : (v) {
                        HapticFeedback.selectionClick();
                        _patch((s) => s.copyWith(enabled: v));
                      },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Barra de ações fixa ───────────────────────────────────────────────────

  Widget _buildActionBar(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accent(context);
    final amber = _amber(context);
    final dirty = _isDirty;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(_kPadH, 10, _kPadH, 10 + bottomInset),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border(
          top: BorderSide(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.45),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (dirty && !_isSaving)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.circleAlert, size: 12, color: amber),
                  const SizedBox(width: 5),
                  Text(
                    'Alterações não salvas',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: amber,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: OutlinedButton.icon(
                  onPressed: _isSaving ? null : _confirmReset,
                  icon: const Icon(LucideIcons.rotateCcw, size: 16),
                  label: const Text(
                    'Resetar',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ThemeHelpers.textSecondaryColor(context),
                    side: BorderSide(color: ThemeHelpers.borderColor(context)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 4,
                child: FilledButton.icon(
                  onPressed: _isSaving || !dirty ? null : () => _save(),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(LucideIcons.check, size: 18),
                  label: Text(
                    _isSaving ? 'Salvando…' : 'Salvar',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: accent.withValues(alpha: 0.35),
                    disabledForegroundColor: Colors.white70,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Estados ───────────────────────────────────────────────────────────────

  Widget _buildError(BuildContext context) {
    final theme = Theme.of(context);
    final danger = _red(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
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
              _errorMessage ?? 'Erro ao carregar configurações do SDR',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loadSettings,
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  /// Skeleton fiel ao layout: eyebrow, título, card do interruptor mestre e
  /// seções com linhas de toggle.
  Widget _buildSkeleton(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(_kPadH, 14, _kPadH, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              SkeletonBox(width: 9, height: 9, borderRadius: 999),
              SizedBox(width: 9),
              SkeletonText(width: 210, height: 11, borderRadius: 4),
            ],
          ),
          const SizedBox(height: 12),
          const SkeletonText(width: 160, height: 26, borderRadius: 8),
          const SizedBox(height: 8),
          const SkeletonText(width: double.infinity, height: 12, borderRadius: 4),
          const SizedBox(height: 5),
          const SkeletonText(width: 220, height: 12, borderRadius: 4),
          const SizedBox(height: 16),
          const SkeletonBox(width: double.infinity, height: 68, borderRadius: 16),
          const SizedBox(height: 26),
          for (var section = 0; section < 3; section++) ...[
            Row(
              children: const [
                SkeletonBox(width: 7, height: 7, borderRadius: 999),
                SizedBox(width: 9),
                SkeletonText(width: 150, height: 11, borderRadius: 4),
              ],
            ),
            const SizedBox(height: 14),
            for (var row = 0; row < 2; row++) ...[
              Row(
                children: const [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonText(width: 170, height: 13, borderRadius: 4),
                        SizedBox(height: 6),
                        SkeletonText(
                            width: double.infinity,
                            height: 10,
                            borderRadius: 4),
                      ],
                    ),
                  ),
                  SizedBox(width: 16),
                  SkeletonBox(width: 46, height: 26, borderRadius: 999),
                ],
              ),
              const SizedBox(height: 18),
            ],
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

// ─── Cabeçalho de seção flush (eyebrow + filete) ─────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.tone,
    required this.label,
    this.hint,
  });

  final Color tone;
  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: tone,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: tone.withValues(alpha: 0.45),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    color: tone,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Container(
                    height: 1,
                    color: ThemeHelpers.borderLightColor(context)
                        .withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(
              hint!,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                height: 1.35,
                color: secondary.withValues(alpha: 0.9),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Linha de toggle (ação no próprio item) ──────────────────────────────────

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.description,
    required this.value,
    required this.tone,
    required this.onChanged,
    this.disabled = false,
  });

  final String title;
  final String description;
  final bool value;
  final Color tone;
  final bool disabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: ThemeHelpers.textColor(context),
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: secondary,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch.adaptive(
              value: value,
              activeTrackColor: tone,
              onChanged: disabled
                  ? null
                  : (v) {
                      HapticFeedback.selectionClick();
                      onChanged(v);
                    },
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Linha com stepper numérico compacto ─────────────────────────────────────

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.title,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.unit,
    required this.tone,
    required this.onChanged,
    this.disabled = false,
  });

  final String title;
  final String description;
  final int value;
  final int min;
  final int max;
  final int step;
  final String unit;
  final Color tone;
  final bool disabled;
  final ValueChanged<int> onChanged;

  void _bump(int delta) {
    final next = (value + delta).clamp(min, max);
    if (next != value) {
      HapticFeedback.selectionClick();
      onChanged(next);
    }
  }

  Widget _stepButton(BuildContext context, IconData icon, bool enabled,
      VoidCallback onTap) {
    final color = enabled ? tone : ThemeHelpers.textSecondaryColor(context);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color.withValues(alpha: enabled ? 0.12 : 0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: ThemeHelpers.textColor(context),
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: secondary,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _stepButton(
              context,
              LucideIcons.minus,
              !disabled && value > min,
              () => _bump(-step),
            ),
            SizedBox(
              width: 58,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$value',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: tone,
                      letterSpacing: -0.3,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    unit,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: secondary,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
            _stepButton(
              context,
              LucideIcons.plus,
              !disabled && value < max,
              () => _bump(step),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Controle de horário (abre showTimePicker) ───────────────────────────────

class _TimeControl extends StatelessWidget {
  const _TimeControl({
    required this.label,
    required this.value,
    required this.tone,
    required this.fill,
    required this.onTap,
    this.disabled = false,
  });

  final String label;
  final String value;
  final Color tone;
  final Color fill;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ThemeHelpers.borderLightColor(context)),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: isDark ? 0.20 : 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(LucideIcons.clock3, size: 17, color: tone),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                        color: ThemeHelpers.textSecondaryColor(context),
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                        letterSpacing: -0.2,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                LucideIcons.chevronDown,
                size: 15,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Campo de texto multilinha (filled) ──────────────────────────────────────

class _TextArea extends StatelessWidget {
  const _TextArea({
    required this.label,
    required this.controller,
    required this.hint,
    required this.fill,
    this.maxLength,
    this.minLines = 3,
    this.disabled = false,
    this.helper,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final Color fill;
  final int? maxLength;
  final int minLines;
  final bool disabled;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: controller,
              enabled: !disabled,
              minLines: minLines,
              maxLines: minLines + 4,
              maxLength: maxLength,
              textCapitalization: TextCapitalization.sentences,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textColor(context),
                height: 1.4,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintMaxLines: 3,
                hintStyle: theme.textTheme.bodySmall?.copyWith(
                  color: secondary.withValues(alpha: 0.75),
                  height: 1.4,
                ),
                filled: true,
                fillColor: fill,
                counterText: '',
                contentPadding: const EdgeInsets.all(12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: ThemeHelpers.borderLightColor(context),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppColors.primary.primaryDarkMode
                        : AppColors.primary.primary,
                    width: 1.4,
                  ),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: ThemeHelpers.borderLightColor(context),
                  ),
                ),
              ),
            ),
            if (helper != null) ...[
              const SizedBox(height: 6),
              Text(
                helper!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: secondary.withValues(alpha: 0.85),
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Chip de tom de voz (tint, nunca preenchimento sólido) ───────────────────

class _ToneChip extends StatelessWidget {
  const _ToneChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.fill,
    required this.onTap,
    this.disabled = false,
  });

  final String label;
  final bool selected;
  final Color accent;
  final Color fill;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fg = selected
        ? accent
        : ThemeHelpers.textColor(context).withValues(alpha: 0.82);
    final bg =
        selected ? accent.withValues(alpha: isDark ? 0.18 : 0.10) : fill;
    final border = selected ? accent : ThemeHelpers.borderLightColor(context);
    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border, width: selected ? 1.2 : 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(LucideIcons.check, size: 13, color: fg),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontSize: 12.5,
                  color: fg,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Acesso negado ───────────────────────────────────────────────────────────

class _DeniedView extends StatelessWidget {
  const _DeniedView();

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.lock, size: 38, color: secondary),
            const SizedBox(height: 12),
            Text(
              'Você não tem acesso às configurações do SDR.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Solicite ao administrador o módulo de IA no WhatsApp e a permissão de gestão do atendimento.',
              textAlign: TextAlign.center,
              style: TextStyle(color: secondary, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
