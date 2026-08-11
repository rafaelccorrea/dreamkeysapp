import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import 'approval_actions_sheet.dart';

/// Como o proprietário vai assinar a autorização.
enum OwnerAuthSendMode {
  /// Template padrão gerado pelo sistema e enviado ao Autentique.
  digital,

  /// PDF próprio da empresa enviado ao Autentique no lugar do template.
  ownDocument,

  /// Documento já assinado em papel, anexado para validação do aprovador.
  physical,
}

/// Payload coletado pelo sheet de envio da autorização do proprietário.
/// Espelha o corpo aceito por `POST /properties/:id/owner-authorization/send`
/// (e as variantes multipart `send-document` / `upload-physical`).
class OwnerAuthSendRequest {
  final OwnerAuthSendMode mode;
  final File? file;
  final String signerName;
  final String signerEmail;
  final bool sendByEmail;
  final bool hasExclusivity;
  final bool exclusivityIndeterminate;
  final int exclusivityDays;
  final bool acceptsPlaca;

  /// `venda` | `locacao` | `venda_locacao`.
  final String operationType;

  /// `intellisys` (padrão) ou `company` para usar a logo da empresa no PDF.
  final String logoSource;

  const OwnerAuthSendRequest({
    required this.mode,
    required this.file,
    required this.signerName,
    required this.signerEmail,
    required this.sendByEmail,
    required this.hasExclusivity,
    required this.exclusivityIndeterminate,
    required this.exclusivityDays,
    required this.acceptsPlaca,
    required this.operationType,
    required this.logoSource,
  });
}

/// Sheet de **envio da autorização do proprietário**. Cobre as três vias do
/// web: template digital, PDF próprio da empresa e anexo assinado em papel.
Future<OwnerAuthSendRequest?> showOwnerAuthSendSheet({
  required BuildContext context,
  required String propertyTitle,
  required Color tone,
  String? ownerName,
  String? ownerEmail,
  OwnerAuthSendMode initialMode = OwnerAuthSendMode.digital,
  bool isResend = false,
}) {
  return showModalBottomSheet<OwnerAuthSendRequest>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: ThemeHelpers.cardBackgroundColor(context),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _OwnerAuthSendSheet(
      propertyTitle: propertyTitle,
      tone: tone,
      ownerName: ownerName,
      ownerEmail: ownerEmail,
      initialMode: initialMode,
      isResend: isResend,
    ),
  );
}

class _OwnerAuthSendSheet extends StatefulWidget {
  final String propertyTitle;
  final Color tone;
  final String? ownerName;
  final String? ownerEmail;
  final OwnerAuthSendMode initialMode;
  final bool isResend;

  const _OwnerAuthSendSheet({
    required this.propertyTitle,
    required this.tone,
    required this.ownerName,
    required this.ownerEmail,
    required this.initialMode,
    required this.isResend,
  });

  @override
  State<_OwnerAuthSendSheet> createState() => _OwnerAuthSendSheetState();
}

class _OwnerAuthSendSheetState extends State<_OwnerAuthSendSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.ownerName ?? '');
  late final TextEditingController _email =
      TextEditingController(text: widget.ownerEmail ?? '');
  final TextEditingController _days = TextEditingController(text: '40');

  late OwnerAuthSendMode _mode = widget.initialMode;
  bool _sendByEmail = true;
  bool _hasExclusivity = true;
  bool _exclusivityIndeterminate = false;
  bool _acceptsPlaca = true;
  bool _opVenda = true;
  bool _opLocacao = false;
  bool _companyLogo = false;
  File? _file;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _days.dispose();
    super.dispose();
  }

  bool get _needsFile =>
      _mode == OwnerAuthSendMode.physical ||
      _mode == OwnerAuthSendMode.ownDocument;

  bool get _isPhysical => _mode == OwnerAuthSendMode.physical;

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: _isPhysical
          ? const ['pdf', 'jpg', 'jpeg', 'png']
          : const ['pdf'],
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    setState(() {
      _file = File(path);
      _error = null;
    });
  }

  String? _validate() {
    if (_needsFile && _file == null) {
      return _isPhysical
          ? 'Anexe o documento assinado (PDF ou imagem).'
          : 'Anexe o PDF do documento de autorização.';
    }
    if (_isPhysical) return null;
    if (_name.text.trim().isEmpty) {
      return 'Nome do proprietário é obrigatório.';
    }
    if (_sendByEmail) {
      final email = _email.text.trim();
      if (email.isEmpty) {
        return 'E-mail do proprietário é obrigatório quando "Enviar por e-mail" está ligado.';
      }
      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
        return 'Informe um e-mail válido.';
      }
    }
    if (_mode == OwnerAuthSendMode.digital && !_opVenda && !_opLocacao) {
      return 'Selecione pelo menos uma operação (Venda ou Locação).';
    }
    return null;
  }

  void _submit() {
    final err = _validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    final operationType = _opVenda && _opLocacao
        ? 'venda_locacao'
        : (_opLocacao ? 'locacao' : 'venda');
    Navigator.of(context).pop(
      OwnerAuthSendRequest(
        mode: _mode,
        file: _file,
        signerName: _name.text.trim(),
        signerEmail: _email.text.trim(),
        sendByEmail: _sendByEmail,
        hasExclusivity: _hasExclusivity,
        exclusivityIndeterminate: _exclusivityIndeterminate,
        exclusivityDays: int.tryParse(_days.text.trim()) ?? 40,
        acceptsPlaca: _acceptsPlaca,
        operationType: operationType,
        logoSource: _companyLogo ? 'company' : 'intellisys',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final danger =
        isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ApprovalSheetGrabber(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 10, 0),
            child: ApprovalSheetHeader(
              eyebrow: 'PROPRIETÁRIO',
              title: widget.isResend
                  ? 'Enviar novamente para assinatura'
                  : 'Enviar para assinatura',
              subtitle: widget.propertyTitle,
              tone: widget.tone,
              icon: LucideIcons.fileSignature,
            ),
          ),
          const SizedBox(height: 14),
          ApprovalSheetDivider(tone: widget.tone),
          Flexible(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _sectionLabel('Como o proprietário assina'),
                  const SizedBox(height: 8),
                  _ModeTile(
                    icon: LucideIcons.penTool,
                    label: 'Assinatura digital (modelo do sistema)',
                    hint: 'Gera o documento padrão e envia ao Autentique.',
                    tone: widget.tone,
                    selected: _mode == OwnerAuthSendMode.digital,
                    onTap: () => setState(() {
                      _mode = OwnerAuthSendMode.digital;
                      _file = null;
                      _error = null;
                    }),
                  ),
                  const SizedBox(height: 8),
                  _ModeTile(
                    icon: LucideIcons.fileUp,
                    label: 'Assinatura digital com PDF da empresa',
                    hint: 'Envia o seu documento ao Autentique.',
                    tone: widget.tone,
                    selected: _mode == OwnerAuthSendMode.ownDocument,
                    onTap: () => setState(() {
                      _mode = OwnerAuthSendMode.ownDocument;
                      _file = null;
                      _error = null;
                    }),
                  ),
                  const SizedBox(height: 8),
                  _ModeTile(
                    icon: LucideIcons.paperclip,
                    label: 'Anexo assinado em papel',
                    hint: 'Um aprovador valida o anexo antes de liberar.',
                    tone: widget.tone,
                    selected: _isPhysical,
                    onTap: () => setState(() {
                      _mode = OwnerAuthSendMode.physical;
                      _file = null;
                      _error = null;
                    }),
                  ),
                  if (_needsFile) ...[
                    const SizedBox(height: 18),
                    _sectionLabel('Documento'),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _pickFile,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: widget.tone,
                        side: BorderSide(
                          color: widget.tone.withValues(alpha: 0.45),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      icon: const Icon(LucideIcons.upload, size: 16),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _file == null
                              ? 'Escolher arquivo'
                              : _file!.path.split(RegExp(r'[/\\]')).last,
                        ),
                      ),
                    ),
                  ],
                  if (!_isPhysical) ...[
                    const SizedBox(height: 18),
                    _sectionLabel('Proprietário'),
                    const SizedBox(height: 8),
                    _field(
                      controller: _name,
                      hint: 'Nome do proprietário',
                      icon: LucideIcons.user,
                    ),
                    const SizedBox(height: 10),
                    _field(
                      controller: _email,
                      hint: 'E-mail do proprietário',
                      icon: LucideIcons.mail,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),
                    _SwitchRow(
                      label: 'Enviar por e-mail',
                      hint: _sendByEmail
                          ? 'O proprietário recebe o link de assinatura por e-mail.'
                          : 'Nada é enviado: o link de assinatura volta aqui para você repassar.',
                      value: _sendByEmail,
                      tone: widget.tone,
                      onChanged: (v) => setState(() => _sendByEmail = v),
                    ),
                  ],
                  if (_mode == OwnerAuthSendMode.digital) ...[
                    const SizedBox(height: 18),
                    _sectionLabel('Operação autorizada'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _ChoiceChip(
                            label: 'Venda',
                            selected: _opVenda,
                            tone: widget.tone,
                            onTap: () => setState(() => _opVenda = !_opVenda),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ChoiceChip(
                            label: 'Locação',
                            selected: _opLocacao,
                            tone: widget.tone,
                            onTap: () =>
                                setState(() => _opLocacao = !_opLocacao),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _sectionLabel('Condições do documento'),
                    const SizedBox(height: 8),
                    _SwitchRow(
                      label: 'Exclusividade',
                      hint: 'A empresa fica com a exclusividade do imóvel.',
                      value: _hasExclusivity,
                      tone: widget.tone,
                      onChanged: (v) => setState(() => _hasExclusivity = v),
                    ),
                    if (_hasExclusivity) ...[
                      const SizedBox(height: 10),
                      _SwitchRow(
                        label: 'Prazo indeterminado',
                        hint: 'Sem data de término definida no documento.',
                        value: _exclusivityIndeterminate,
                        tone: widget.tone,
                        onChanged: (v) =>
                            setState(() => _exclusivityIndeterminate = v),
                      ),
                      if (!_exclusivityIndeterminate) ...[
                        const SizedBox(height: 10),
                        _field(
                          controller: _days,
                          hint: 'Dias de exclusividade',
                          icon: LucideIcons.calendarDays,
                          keyboardType: TextInputType.number,
                          formatters: [FilteringTextInputFormatter.digitsOnly],
                        ),
                      ],
                    ],
                    const SizedBox(height: 10),
                    _SwitchRow(
                      label: 'Autoriza placa no imóvel',
                      hint: 'Permite fixar a placa de divulgação.',
                      value: _acceptsPlaca,
                      tone: widget.tone,
                      onChanged: (v) => setState(() => _acceptsPlaca = v),
                    ),
                    const SizedBox(height: 10),
                    _SwitchRow(
                      label: 'Usar a logo da empresa',
                      hint: 'Desligado, o documento sai com a logo padrão.',
                      value: _companyLogo,
                      tone: widget.tone,
                      onChanged: (v) => setState(() => _companyLogo = v),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: danger.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: danger.withValues(alpha: 0.22)),
                      ),
                      child: Row(
                        children: [
                          Icon(LucideIcons.alertCircle,
                              size: 16, color: danger),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: danger,
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    _isPhysical
                        ? 'O anexo entra na fila para um aprovador validar antes de liberar o imóvel.'
                        : 'O documento vai para o Autentique e o imóvel segue assim que a assinatura chegar.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
          ApprovalSheetFooter(
            confirmLabel: _isPhysical ? 'Enviar anexo' : 'Enviar',
            confirmIcon: LucideIcons.send,
            confirmColor: kApprovalGreen,
            submitting: false,
            onConfirm: _submit,
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
            fontSize: 10,
          ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: formatters,
      style: TextStyle(
        color: ThemeHelpers.textColor(context),
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        prefixIcon: Icon(
          icon,
          size: 17,
          color: ThemeHelpers.textSecondaryColor(context),
        ),
        filled: true,
        fillColor: ThemeHelpers.backgroundColor(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: ThemeHelpers.borderColor(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: ThemeHelpers.borderColor(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: widget.tone, width: 1.4),
        ),
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String hint;
  final Color tone;
  final bool selected;
  final VoidCallback onTap;

  const _ModeTile({
    required this.icon,
    required this.label,
    required this.hint,
    required this.tone,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
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
                ? tone.withValues(alpha: isDark ? 0.14 : 0.07)
                : Colors.transparent,
            border: Border.all(
              color: selected
                  ? tone.withValues(alpha: 0.5)
                  : ThemeHelpers.borderColor(context),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 17,
                color:
                    selected ? tone : ThemeHelpers.textSecondaryColor(context),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: selected
                            ? tone
                            : ThemeHelpers.textColor(context),
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ThemeHelpers.textSecondaryColor(context),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                Icon(LucideIcons.check, size: 16, color: tone),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final String hint;
  final bool value;
  final Color tone;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.label,
    required this.hint,
    required this.value,
    required this.tone,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: ThemeHelpers.textColor(context),
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Switch.adaptive(
          value: value,
          activeThumbColor: tone,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color tone;
  final VoidCallback onTap;

  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.tone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: selected
                ? tone.withValues(alpha: isDark ? 0.18 : 0.10)
                : Colors.transparent,
            border: Border.all(
              color: selected
                  ? tone.withValues(alpha: 0.55)
                  : ThemeHelpers.borderColor(context),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? LucideIcons.checkCircle2 : LucideIcons.circle,
                size: 15,
                color:
                    selected ? tone : ThemeHelpers.textSecondaryColor(context),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: selected
                          ? tone
                          : ThemeHelpers.textSecondaryColor(context),
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
}
