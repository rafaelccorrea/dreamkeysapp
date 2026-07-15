import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/condominium_models.dart';
import '../services/condominium_service.dart';
import '../widgets/estate_form_sections.dart';
import '../widgets/estate_shared.dart';

/// Criar/editar **condomínio** — campos fiéis à `CreateCondominiumPage` do
/// web (nome, descrição, CEP→ViaCEP, endereço, contato) com o design filled
/// do wizard da ficha de venda. Antes de criar, verifica cadastros parecidos
/// (`check-similarity`) e pede confirmação, como no web.
class CondominiumFormPage extends StatefulWidget {
  final String? condominiumId;

  const CondominiumFormPage({super.key, this.condominiumId});

  bool get isEdit => condominiumId != null;

  @override
  State<CondominiumFormPage> createState() => _CondominiumFormPageState();
}

class _CondominiumFormPageState extends State<CondominiumFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _data = EstateFormData();

  bool _loadingExisting = false;
  String? _loadError;
  bool _submitting = false;

  bool get _isEdit => widget.isEdit;

  bool get _canSubmit => _isEdit
      ? ModuleAccessService.instance.hasPermission('condominium:update')
      : ModuleAccessService.instance.hasPermission('condominium:create');

  Color _accent(BuildContext context) => EstateTones.blue(context);

  @override
  void initState() {
    super.initState();
    if (_isEdit) _loadExisting();
  }

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    setState(() {
      _loadingExisting = true;
      _loadError = null;
    });
    final res =
        await CondominiumService.instance.getById(widget.condominiumId!);
    if (!mounted) return;
    setState(() {
      _loadingExisting = false;
      if (res.success && res.data != null) {
        _prefill(res.data!);
      } else {
        _loadError = res.message ?? 'Erro ao carregar condomínio';
      }
    });
  }

  void _prefill(Condominium c) {
    _data.name.text = c.name;
    _data.description.text = c.description ?? '';
    _data.zipCode.text = c.zipCode;
    _data.street.text = c.street;
    _data.number.text = c.number;
    _data.complement.text = c.complement ?? '';
    _data.neighborhood.text = c.neighborhood;
    _data.city.text = c.city;
    _data.uf = c.state.trim().isEmpty ? null : c.state.trim().toUpperCase();
    _data.phone.text = c.phone ?? '';
    _data.email.text = c.email ?? '';
    _data.cnpj.text = c.cnpj ?? '';
    _data.website.text = c.website ?? '';
    _data.isActive = c.isActive;
  }

  Future<void> _submit() async {
    if (!_canSubmit) {
      _snack(
        'Você não tem permissão para ${_isEdit ? 'editar' : 'criar'} condomínios',
        error: true,
      );
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      _snack('Corrija os campos destacados antes de salvar', error: true);
      return;
    }

    setState(() => _submitting = true);

    // Aviso de duplicata (apenas na criação — paridade com o web).
    if (!_isEdit) {
      final similar = await CondominiumService.instance
          .checkSimilarity(_data.name.text.trim());
      if (!mounted) return;
      if (similar.success &&
          similar.data != null &&
          similar.data!.hasSimilar) {
        final proceed = await _confirmSimilar(similar.data!.similar);
        if (!mounted) return;
        if (proceed != true) {
          setState(() => _submitting = false);
          return;
        }
      }
    }

    final payload = _data.buildPayload();
    if (_isEdit) payload['isActive'] = _data.isActive;

    final res = _isEdit
        ? await CondominiumService.instance
            .update(widget.condominiumId!, payload)
        : await CondominiumService.instance.create(payload);
    if (!mounted) return;
    setState(() => _submitting = false);

    if (res.success) {
      _snack(_isEdit ? 'Condomínio atualizado' : 'Condomínio criado');
      Navigator.of(context).pop(true);
    } else {
      _snack(res.message ?? 'Erro ao salvar condomínio', error: true);
    }
  }

  Future<bool?> _confirmSimilar(List<SimilarEstate> similar) {
    final amber = EstateTones.amber(context);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(LucideIcons.triangleAlert, color: amber, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Cadastro parecido',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Já existem condomínios com nome parecido. Confira antes de '
              'criar um duplicado:',
              style: TextStyle(height: 1.4),
            ),
            const SizedBox(height: 12),
            for (final s in similar.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(LucideIcons.building2,
                        size: 15,
                        color: ThemeHelpers.textSecondaryColor(ctx)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        [
                          s.name,
                          [s.city, s.state]
                              .where((v) => v.trim().isNotEmpty)
                              .join(' - '),
                        ].where((v) => v.trim().isNotEmpty).join(' · '),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Revisar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: amber),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Criar mesmo assim'),
          ),
        ],
      ),
    );
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            error ? AppColors.status.error : AppColors.status.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEdit ? 'Editar condomínio' : 'Novo condomínio';
    if (!_canSubmit) {
      return AppScaffold(
        title: title,
        showBottomNavigation: false,
        body: _denied(context),
      );
    }
    Widget body;
    if (_loadingExisting) {
      body = _buildSkeleton(context);
    } else if (_loadError != null) {
      body = EstateErrorState(message: _loadError!, onRetry: _loadExisting);
    } else {
      body = _buildForm(context);
    }
    return AppScaffold(
      title: title,
      showBottomNavigation: false,
      body: body,
    );
  }

  Widget _buildForm(BuildContext context) {
    final accent = _accent(context);
    return Theme(
      data: estateFormTheme(context, accent),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EstateFormSections(
                data: _data,
                accent: accent,
                nameLabel: 'Nome do condomínio',
                nameHint: 'Ex.: Residencial das Palmeiras',
              ),
              if (_isEdit) ...[
                const SizedBox(height: 24),
                _buildStatusSwitch(context),
              ],
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(_isEdit ? LucideIcons.save : LucideIcons.plus,
                        size: 17),
                label: Text(
                  _submitting
                      ? 'Salvando…'
                      : (_isEdit ? 'Salvar alterações' : 'Criar condomínio'),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed:
                    _submitting ? null : () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ThemeHelpers.textSecondaryColor(context),
                  side: BorderSide(color: ThemeHelpers.borderColor(context)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusSwitch(BuildContext context) {
    final green = EstateTones.green(context);
    final amber = EstateTones.amber(context);
    final tone = _data.isActive ? green : amber;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EstateSectionHeader(
          tone: tone,
          label: 'Status',
          hint: 'Condomínios inativos saem dos seletores de imóveis.',
        ),
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          value: _data.isActive,
          onChanged: (v) => setState(() => _data.isActive = v),
          contentPadding: EdgeInsets.zero,
          activeTrackColor: green,
          title: Text(
            _data.isActive ? 'Ativo' : 'Inativo',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: tone,
            ),
          ),
          subtitle: Text(
            _data.isActive
                ? 'Disponível para vincular a imóveis.'
                : 'Oculto nos seletores; o histórico é mantido.',
            style: TextStyle(
              fontSize: 12,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSkeleton(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonText(width: 140, height: 12, borderRadius: 5),
          const SizedBox(height: 16),
          for (var i = 0; i < 3; i++) ...[
            const SkeletonBox(
                width: double.infinity, height: 52, borderRadius: 14),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 12),
          const SkeletonText(width: 110, height: 12, borderRadius: 5),
          const SizedBox(height: 16),
          Row(
            children: const [
              Expanded(
                  child: SkeletonBox(height: 52, borderRadius: 14)),
              SizedBox(width: 12),
              Expanded(
                  child: SkeletonBox(height: 52, borderRadius: 14)),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < 3; i++) ...[
            const SkeletonBox(
                width: double.infinity, height: 52, borderRadius: 14),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _denied(BuildContext context) {
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
              _isEdit
                  ? 'Você não tem permissão para editar condomínios.'
                  : 'Você não tem permissão para criar condomínios.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ThemeHelpers.textColor(context),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
