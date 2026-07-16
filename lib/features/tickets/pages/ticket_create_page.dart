import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../models/ticket_models.dart';
import '../services/ticket_service.dart';

const String _kTicketDetailRoute = '/tickets/detail';

/// Limite de anexo — paridade web (15 MB por imagem).
const int _kMaxAttachmentBytes = 15 * 1024 * 1024;

/// Tela **Abrir ticket** — porta o modal de criação da `TicketsPage` web:
/// título, categoria (a prioridade é classificada depois pela equipe de
/// tecnologia), descrição e prints. Para "Erro / Bug" e "Melhoria" o print
/// é obrigatório, como no web.
class TicketCreatePage extends StatefulWidget {
  const TicketCreatePage({super.key});

  @override
  State<TicketCreatePage> createState() => _TicketCreatePageState();
}

class _TicketCreatePageState extends State<TicketCreatePage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  TicketCategory _category = TicketCategory.question;
  final List<XFile> _attachments = [];
  bool _submitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Color get _accent => Theme.of(context).brightness == Brightness.dark
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;

  /// Tema local dos campos — visual filled, mesma régua dos steps da ficha.
  ThemeData _formTheme(BuildContext context) {
    final base = Theme.of(context);
    final isDark = base.brightness == Brightness.dark;
    final fill = isDark
        ? Colors.white.withValues(alpha: 0.045)
        : Colors.black.withValues(alpha: 0.025);
    final muted = ThemeHelpers.textSecondaryColor(context);
    OutlineInputBorder b(Color c, double w) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: w == 0 ? BorderSide.none : BorderSide(color: c, width: w),
    );
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(primary: _accent),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: _accent,
        selectionColor: _accent.withValues(alpha: 0.18),
        selectionHandleColor: _accent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fill,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 15,
        ),
        labelStyle: TextStyle(
          color: muted,
          fontWeight: FontWeight.w600,
          fontSize: 13.5,
        ),
        floatingLabelStyle: TextStyle(
          color: _accent,
          fontWeight: FontWeight.w700,
          fontSize: 13.5,
        ),
        hintStyle: TextStyle(
          color: muted.withValues(alpha: 0.7),
          fontWeight: FontWeight.w500,
        ),
        border: b(Colors.transparent, 0),
        enabledBorder: b(Colors.transparent, 0),
        focusedBorder: b(_accent, 1.6),
        errorBorder: b(
          Theme.of(context).brightness == Brightness.dark
              ? AppColors.status.errorDarkMode
              : AppColors.status.error,
          1.2,
        ),
        focusedErrorBorder: b(
          Theme.of(context).brightness == Brightness.dark
              ? AppColors.status.errorDarkMode
              : AppColors.status.error,
          1.6,
        ),
      ),
    );
  }

  // ─── Anexos ──────────────────────────────────────────────────────────────

  Future<void> _pickFromGallery() async {
    try {
      final picked = await _picker.pickMultiImage(imageQuality: 85);
      if (picked.isEmpty) return;
      await _addFiles(picked);
    } catch (_) {
      _showSnack('Não foi possível abrir a galeria.');
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (picked == null) return;
      await _addFiles([picked]);
    } catch (_) {
      _showSnack('Não foi possível abrir a câmera.');
    }
  }

  Future<void> _addFiles(List<XFile> files) async {
    var rejected = 0;
    for (final file in files) {
      final size = await File(file.path).length();
      if (size > _kMaxAttachmentBytes) {
        rejected++;
        continue;
      }
      _attachments.add(file);
    }
    if (!mounted) return;
    setState(() {});
    if (rejected > 0) {
      _showSnack('$rejected imagem(ns) acima do limite de 15 MB.');
    }
  }

  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ─── Envio ───────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_category.requiresAttachment && _attachments.isEmpty) {
      _showSnack(
        'Para "${_category.label}" é obrigatório anexar ao menos um print.',
      );
      return;
    }

    setState(() => _submitting = true);
    final res = await TicketService.instance.create(
      CreateTicketPayload(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        category: _category,
      ),
    );

    if (!mounted) return;
    if (!res.success || res.data == null) {
      setState(() => _submitting = false);
      _showSnack(res.message ?? 'Erro ao abrir o ticket');
      return;
    }

    final ticket = res.data!;
    var failed = 0;
    for (final file in _attachments) {
      final upload = await TicketService.instance.uploadAttachment(
        ticket.id,
        File(file.path),
      );
      if (!upload.success) failed++;
    }

    if (!mounted) return;
    setState(() => _submitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? 'Ticket aberto com sucesso!'
              : 'Ticket criado, mas $failed anexo(s) não subiram. Reenvie na conversa.',
        ),
      ),
    );
    Navigator.of(
      context,
    ).pushReplacementNamed(_kTicketDetailRoute, arguments: ticket.id);
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Abrir ticket',
      showBottomNavigation: false,
      body: Theme(
        data: _formTheme(context),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  _buildHero(context),
                  const SizedBox(height: 20),
                  _sectionLabel(
                    context,
                    LucideIcons.squarePen,
                    'TÍTULO',
                    tone: _accent,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _titleController,
                    maxLength: 200,
                    textInputAction: TextInputAction.next,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Resumo do problema ou solicitação *',
                    ),
                    validator: (value) {
                      final v = (value ?? '').trim();
                      if (v.isEmpty) return 'Informe um título';
                      if (v.length < 5) return 'Use ao menos 5 caracteres';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  _sectionLabel(
                    context,
                    LucideIcons.shapes,
                    'CATEGORIA',
                    tone: ticketCategoryColor(context, _category),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'A prioridade é classificada pela equipe de tecnologia após o atendimento.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildCategoryPicker(context),
                  const SizedBox(height: 20),
                  _sectionLabel(
                    context,
                    LucideIcons.alignLeft,
                    'DESCRIÇÃO',
                    tone: Theme.of(context).brightness == Brightness.dark
                        ? AppColors.status.greenDarkMode
                        : AppColors.status.green,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _descriptionController,
                    maxLength: 5000,
                    minLines: 5,
                    maxLines: 12,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'O que aconteceu? *',
                      hintText:
                          'Descreva com detalhes: em que tela, o que você esperava e o que aconteceu. Passos para reproduzir aceleram muito o atendimento.',
                      alignLabelWithHint: true,
                    ),
                    validator: (value) {
                      final v = (value ?? '').trim();
                      if (v.isEmpty) return 'Descreva o problema';
                      if (v.length < 20) {
                        return 'Detalhe um pouco mais (mín. 20 caracteres)';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  _sectionLabel(
                    context,
                    LucideIcons.paperclip,
                    _category.requiresAttachment
                        ? 'PRINTS · OBRIGATÓRIO'
                        : 'PRINTS · OPCIONAL',
                    tone: Theme.of(context).brightness == Brightness.dark
                        ? AppColors.status.warningDarkMode
                        : AppColors.status.warning,
                  ),
                  const SizedBox(height: 10),
                  if (_category.requiresAttachment)
                    _buildAttachmentNotice(context),
                  _buildAttachmentsArea(context),
                ],
              ),
            ),
            _buildSubmitBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
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
                color: _accent,
                boxShadow: [
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.55),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Text(
              'SUPORTE · NOVO TICKET',
              style: theme.textTheme.labelSmall?.copyWith(
                color: _accent,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.2,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Fale com a equipe',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: ThemeHelpers.textColor(context),
            letterSpacing: -0.6,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Quanto mais contexto e prints, mais rápido o atendimento. Você acompanha as respostas na conversa do ticket.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: secondary,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(
    BuildContext context,
    IconData icon,
    String label, {
    required Color tone,
  }) {
    return Row(
      children: [
        Icon(icon, size: 13, color: tone),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: tone,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
            fontSize: 10.5,
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Container(
              height: 1,
              color: ThemeHelpers.borderLightColor(
                context,
              ).withValues(alpha: 0.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryPicker(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final category in TicketCategory.values)
              _CategoryChip(
                category: category,
                selected: category == _category,
                onTap: () => setState(() => _category = category),
              ),
          ],
        ),
        const SizedBox(height: 10),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Row(
            key: ValueKey(_category),
            children: [
              Icon(
                ticketCategoryIcon(_category),
                size: 13,
                color: ticketCategoryColor(context, _category),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _category.hint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(
                      context,
                    ).withValues(alpha: isDark ? 0.9 : 1),
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAttachmentNotice(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final amber = isDark
        ? AppColors.status.warningDarkMode
        : AppColors.status.warning;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: amber.withValues(alpha: isDark ? 0.12 : 0.08),
        border: Border.all(color: amber.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.triangleAlert, size: 15, color: amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Para "${_category.label}" é obrigatório anexar ao menos um print que evidencie o problema.',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
                color: ThemeHelpers.textColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentsArea(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_attachments.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _attachments.length; i++)
                _AttachmentThumb(
                  file: _attachments[i],
                  onRemove: () => _removeAttachment(i),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(
              child: _PickerButton(
                icon: LucideIcons.images,
                label: 'Galeria',
                onTap: _pickFromGallery,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PickerButton(
                icon: LucideIcons.camera,
                label: 'Câmera',
                onTap: _pickFromCamera,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Imagens PNG ou JPG, até 15 MB cada — ajudam a agilizar o atendimento.',
          style: TextStyle(fontSize: 11.5, color: secondary, height: 1.3),
        ),
      ],
    );
  }

  Widget _buildSubmitBar(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border(
          top: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: SizedBox(
        height: 50,
        child: ElevatedButton.icon(
          onPressed: _submitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            disabledBackgroundColor: _accent.withValues(alpha: 0.5),
            disabledForegroundColor: Colors.white70,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
              : const Icon(LucideIcons.send, size: 17),
          label: Text(
            _submitting ? 'Abrindo…' : 'Abrir ticket',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 15,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ),
    );
  }
}

/// Chip de categoria — tint + borda na cor semântica quando selecionado.
class _CategoryChip extends StatelessWidget {
  final TicketCategory category;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone = ticketCategoryColor(context, category);
    final neutral = ThemeHelpers.textSecondaryColor(context);
    final fg = selected ? tone : neutral;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: selected
                ? tone.withValues(alpha: isDark ? 0.16 : 0.1)
                : Colors.transparent,
            border: Border.all(
              color: selected
                  ? tone.withValues(alpha: 0.45)
                  : ThemeHelpers.borderColor(context),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(ticketCategoryIcon(category), size: 14, color: fg),
              const SizedBox(width: 6),
              Text(
                category.label,
                style: TextStyle(
                  color: selected ? tone : ThemeHelpers.textColor(context),
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Miniatura da imagem escolhida, com botão de remover no canto.
class _AttachmentThumb extends StatelessWidget {
  final XFile file;
  final VoidCallback onRemove;

  const _AttachmentThumb({required this.file, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            File(file.path),
            width: 84,
            height: 84,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.6),
              ),
              child: const Icon(LucideIcons.x, size: 13, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

/// Botão de origem do anexo (galeria/câmera) — outline discreto.
class _PickerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PickerButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final neutral = ThemeHelpers.textSecondaryColor(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: ThemeHelpers.borderColor(context)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: neutral),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
