import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/condominium_models.dart';
import '../models/development_models.dart';
import '../services/development_service.dart';
import '../widgets/estate_form_sections.dart';
import '../widgets/estate_shared.dart';

/// Linha editável de link do material da equipe.
class _LinkDraft {
  final String id;
  final TextEditingController label;
  final TextEditingController url;

  _LinkDraft({String? id, String? labelText, String? urlText})
      : id = id ?? 'link-${DateTime.now().microsecondsSinceEpoch}',
        label = TextEditingController(text: labelText ?? ''),
        url = TextEditingController(text: urlText ?? '');

  void dispose() {
    label.dispose();
    url.dispose();
  }
}

/// Criar/editar **empreendimento** — campos fiéis à `CreateEmpreendimentoPage`
/// do web: identificação, endereço (CEP→ViaCEP), contato e material da equipe
/// (notas + links). Arquivos do material são gerenciados pelo painel web
/// (upload multipart fora do escopo mobile).
class DevelopmentFormPage extends StatefulWidget {
  final String? developmentId;

  const DevelopmentFormPage({super.key, this.developmentId});

  bool get isEdit => developmentId != null;

  @override
  State<DevelopmentFormPage> createState() => _DevelopmentFormPageState();
}

class _DevelopmentFormPageState extends State<DevelopmentFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _data = EstateFormData();
  final _playbookNotes = TextEditingController();
  final List<_LinkDraft> _links = [];

  bool _loadingExisting = false;
  String? _loadError;
  bool _submitting = false;
  int _existingFilesCount = 0;

  bool get _isEdit => widget.isEdit;

  bool get _canSubmit => _isEdit
      ? ModuleAccessService.instance.hasPermission('condominium:update')
      : ModuleAccessService.instance.hasPermission('condominium:create');

  Color _accent(BuildContext context) => EstateTones.purple(context);

  @override
  void initState() {
    super.initState();
    if (_isEdit) _loadExisting();
  }

  @override
  void dispose() {
    _data.dispose();
    _playbookNotes.dispose();
    for (final l in _links) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _loadExisting() async {
    setState(() {
      _loadingExisting = true;
      _loadError = null;
    });
    final res =
        await DevelopmentService.instance.getById(widget.developmentId!);
    if (!mounted) return;
    setState(() {
      _loadingExisting = false;
      if (res.success && res.data != null) {
        _prefill(res.data!);
      } else {
        _loadError = res.message ?? 'Erro ao carregar empreendimento';
      }
    });
  }

  void _prefill(Development d) {
    _data.name.text = d.name;
    _data.description.text = d.description ?? '';
    _data.zipCode.text = d.zipCode;
    _data.street.text = d.street;
    _data.number.text = d.number;
    _data.complement.text = d.complement ?? '';
    _data.neighborhood.text = d.neighborhood;
    _data.city.text = d.city;
    _data.uf = d.state.trim().isEmpty ? null : d.state.trim().toUpperCase();
    _data.phone.text = d.phone ?? '';
    _data.email.text = d.email ?? '';
    _data.cnpj.text = d.cnpj ?? '';
    _data.website.text = d.website ?? '';
    _data.isActive = d.isActive;

    _playbookNotes.text = d.materialNotes;
    for (final l in _links) {
      l.dispose();
    }
    _links
      ..clear()
      ..addAll(d.playbookKit.links.map(
        (l) => _LinkDraft(id: l.id, labelText: l.label, urlText: l.url),
      ));
    _existingFilesCount = d.playbookKit.files.length;
  }

  Future<void> _submit() async {
    if (!_canSubmit) {
      _snack(
        'Você não tem permissão para ${_isEdit ? 'editar' : 'criar'} empreendimentos',
        error: true,
      );
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      _snack('Corrija os campos destacados antes de salvar', error: true);
      return;
    }

    // Links precisam de rótulo E URL (paridade com o web).
    final badLink = _links.any((l) {
      final label = l.label.text.trim();
      final url = l.url.text.trim();
      return (label.isEmpty) != (url.isEmpty);
    });
    if (badLink) {
      _snack('Cada link do material precisa de rótulo e URL', error: true);
      return;
    }

    setState(() => _submitting = true);

    if (!_isEdit) {
      final similar = await DevelopmentService.instance
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

    final links = _links
        .map((l) => {
              'id': l.id,
              'label': l.label.text.trim(),
              'url': l.url.text.trim(),
            })
        .where((l) =>
            (l['label'] as String).isNotEmpty && (l['url'] as String).isNotEmpty)
        .toList();

    final payload = _data.buildPayload(includeComplement: true);
    payload['playbookKit'] = {
      'notes': _playbookNotes.text.trim(),
      'links': links,
    };
    if (_isEdit) payload['isActive'] = _data.isActive;

    final res = _isEdit
        ? await DevelopmentService.instance
            .update(widget.developmentId!, payload)
        : await DevelopmentService.instance.create(payload);
    if (!mounted) return;
    setState(() => _submitting = false);

    if (res.success) {
      _snack(_isEdit ? 'Empreendimento atualizado' : 'Empreendimento criado');
      Navigator.of(context).pop(true);
    } else {
      _snack(res.message ?? 'Erro ao salvar empreendimento', error: true);
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
              'Já existem empreendimentos com nome parecido. Confira antes '
              'de criar um duplicado:',
              style: TextStyle(height: 1.4),
            ),
            const SizedBox(height: 12),
            for (final s in similar.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(LucideIcons.blocks,
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
    final title = _isEdit ? 'Editar empreendimento' : 'Novo empreendimento';
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
                showComplement: true,
                nameLabel: 'Nome do empreendimento',
                nameHint: 'Ex.: Reserva do Horizonte',
              ),
              const SizedBox(height: 24),
              _divider(context),
              _buildPlaybookSection(context),
              if (_isEdit) ...[
                const SizedBox(height: 24),
                _divider(context),
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
                      : (_isEdit
                          ? 'Salvar alterações'
                          : 'Criar empreendimento'),
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

  Widget _buildPlaybookSection(BuildContext context) {
    final purple = EstateTones.purple(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EstateSectionHeader(
          tone: purple,
          label: 'Material da equipe',
          hint: 'Notas e links internos (tabelas, pastas, apresentações) '
              'visíveis para quem pode ver o empreendimento.',
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _playbookNotes,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Notas internas',
            hintText: 'Condições comerciais, contatos da incorporadora…',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < _links.length; i++) _buildLinkRow(context, i),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _links.add(_LinkDraft())),
            icon: const Icon(LucideIcons.plus, size: 15),
            label: const Text('Adicionar link'),
            style: OutlinedButton.styleFrom(
              foregroundColor: purple,
              side: BorderSide(color: purple.withValues(alpha: 0.45)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              textStyle:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
        if (_isEdit && _existingFilesCount > 0) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(LucideIcons.paperclip, size: 13, color: secondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$_existingFilesCount arquivo${_existingFilesCount == 1 ? '' : 's'} '
                  'anexado${_existingFilesCount == 1 ? '' : 's'} — '
                  'gerencie os arquivos pelo painel web.',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: secondary,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildLinkRow(BuildContext context, int index) {
    final link = _links[index];
    final danger = EstateTones.danger(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: link.label,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Rótulo',
                hintText: 'Tabela de preços',
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: link.url,
              keyboardType: TextInputType.url,
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'\s')),
              ],
              decoration: const InputDecoration(
                labelText: 'URL',
                hintText: 'https://…',
              ),
            ),
          ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: IconButton(
              onPressed: () => setState(() {
                final removed = _links.removeAt(index);
                removed.dispose();
              }),
              tooltip: 'Remover link',
              icon: Icon(LucideIcons.trash2, size: 17, color: danger),
            ),
          ),
        ],
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
          hint: 'Empreendimentos inativos saem dos seletores de imóveis.',
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

  Widget _divider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Container(
        height: 1,
        color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.7),
      ),
    );
  }

  Widget _buildSkeleton(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonText(width: 160, height: 12, borderRadius: 5),
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
              Expanded(child: SkeletonBox(height: 52, borderRadius: 14)),
              SizedBox(width: 12),
              Expanded(child: SkeletonBox(height: 52, borderRadius: 14)),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < 3; i++) ...[
            const SkeletonBox(
                width: double.infinity, height: 52, borderRadius: 14),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 12),
          const SkeletonText(width: 150, height: 12, borderRadius: 5),
          const SizedBox(height: 16),
          const SkeletonBox(
              width: double.infinity, height: 96, borderRadius: 14),
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
                  ? 'Você não tem permissão para editar empreendimentos.'
                  : 'Você não tem permissão para criar empreendimentos.',
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
