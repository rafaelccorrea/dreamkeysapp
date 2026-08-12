import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/services/sale_forms_service.dart';
import '../../../shared/widgets/app_error_state.dart';

/// Bottom sheet de ANEXOS da ficha de venda — lista os anexos (foto da ficha
/// física, comprovantes etc.), permite anexar (foto da câmera ou arquivo) e,
/// para gestores, aprovar/rejeitar cada anexo.
Future<void> showSaleFormAnexosSheet(
  BuildContext context, {
  required String saleFormId,
  String? formNumber,
  VoidCallback? onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    builder: (ctx) => _SaleFormAnexosSheet(
      saleFormId: saleFormId,
      formNumber: formNumber,
      onChanged: onChanged,
    ),
  );
}

class _SaleFormAnexosSheet extends StatefulWidget {
  const _SaleFormAnexosSheet({
    required this.saleFormId,
    required this.formNumber,
    this.onChanged,
  });

  final String saleFormId;
  final String? formNumber;
  final VoidCallback? onChanged;

  @override
  State<_SaleFormAnexosSheet> createState() => _SaleFormAnexosSheetState();
}

class _SaleFormAnexosSheetState extends State<_SaleFormAnexosSheet> {
  bool _loading = true;
  bool _uploading = false;
  String? _error;
  int _errorStatus = 0;
  List<SaleFormAttachment> _anexos = const [];
  final ImagePicker _picker = ImagePicker();

  Color get _accent => Theme.of(context).brightness == Brightness.dark
      ? AppColors.primary.primaryDarkMode
      : AppColors.primary.primary;

  bool get _isManager {
    final role = ModuleAccessService.instance.userRole?.toLowerCase();
    return role == 'manager' || role == 'admin' || role == 'master';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await SaleFormsService.instance.listAnexos(widget.saleFormId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _anexos = res.data!;
        _error = null;
        _errorStatus = 0;
      } else {
        _error = res.message ?? 'Erro ao carregar anexos.';
        _errorStatus = res.statusCode;
      }
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _chooseSource() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.photo_camera_outlined, color: _accent),
              title: const Text('Foto da câmera'),
              subtitle: const Text('Fotografar a ficha física'),
              onTap: () => Navigator.of(ctx).pop('camera'),
            ),
            ListTile(
              leading: Icon(Icons.attach_file_rounded, color: _accent),
              title: const Text('Escolher arquivo'),
              subtitle: const Text('PDF ou imagem do dispositivo'),
              onTap: () => Navigator.of(ctx).pop('file'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == 'camera') {
      await _pickFromCamera();
    } else if (choice == 'file') {
      await _pickFromFiles();
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (picked == null) return;
      await _upload(File(picked.path));
    } catch (_) {
      _snack('Não foi possível abrir a câmera.');
    }
  }

  Future<void> _pickFromFiles() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: kAnexoAllowedExtensions,
      );
      final path = result?.files.single.path;
      if (path == null) return;
      await _upload(File(path));
    } catch (_) {
      _snack('Não foi possível abrir o seletor de arquivos.');
    }
  }

  Future<void> _upload(File file) async {
    setState(() => _uploading = true);
    final res =
        await SaleFormsService.instance.uploadAnexo(widget.saleFormId, file);
    if (!mounted) return;
    setState(() => _uploading = false);
    if (res.success) {
      _snack('Anexo enviado.');
      widget.onChanged?.call();
      _load();
    } else {
      _snack(res.message ?? 'Erro ao enviar anexo.');
    }
  }

  Future<void> _aprovar(SaleFormAttachment a) async {
    final res =
        await SaleFormsService.instance.aprovarAnexo(widget.saleFormId, a.id);
    if (!mounted) return;
    if (res.success) {
      _snack('Anexo aprovado.');
      widget.onChanged?.call();
      _load();
    } else {
      _snack(res.message ?? 'Erro ao aprovar anexo.');
    }
  }

  Future<void> _rejeitar(SaleFormAttachment a) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rejeitar anexo'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Motivo (opcional)',
            hintText: 'Explique por que o anexo foi rejeitado',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.status.error,
            ),
            child: const Text('Rejeitar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null) return; // cancelou
    final res = await SaleFormsService.instance.rejeitarAnexo(
      widget.saleFormId,
      a.id,
      reason: reason.isEmpty ? null : reason,
    );
    if (!mounted) return;
    if (res.success) {
      _snack('Anexo rejeitado.');
      widget.onChanged?.call();
      _load();
    } else {
      _snack(res.message ?? 'Erro ao rejeitar anexo.');
    }
  }

  Future<void> _abrir(SaleFormAttachment a) async {
    if (a.fileUrl.isEmpty) return;
    final uri = Uri.tryParse(a.fileUrl);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scroll) {
        final theme = Theme.of(context);
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              _Header(
                formNumber: widget.formNumber,
                count: _anexos.length,
                onClose: () => Navigator.of(ctx).pop(),
              ),
              Expanded(child: _buildBody(scroll)),
              _buildActionBar(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(ScrollController scroll) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _anexos.isEmpty) {
      // Lista (e não Center) para o sheet continuar arrastável pelo corpo.
      return ListView(
        controller: scroll,
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        children: [
          AppErrorState.fromApi(
            message: _error,
            statusCode: _errorStatus,
            onRetry: _load,
            dense: true,
          ),
        ],
      );
    }
    if (_anexos.isEmpty) {
      return _EmptyState(accent: _accent);
    }
    return ListView.builder(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: _anexos.length,
      itemBuilder: (ctx, i) => _AnexoTile(
        anexo: _anexos[i],
        isManager: _isManager,
        onOpen: () => _abrir(_anexos[i]),
        onApprove: () => _aprovar(_anexos[i]),
        onReject: () => _rejeitar(_anexos[i]),
      ),
    );
  }

  Widget _buildActionBar(BuildContext context) {
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
        child: FilledButton.icon(
          onPressed: _uploading ? null : _chooseSource,
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            disabledBackgroundColor: _accent.withValues(alpha: 0.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: _uploading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.upload_file_rounded, size: 18),
          label: Text(
            _uploading ? 'Enviando…' : 'Anexar ficha física',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.formNumber,
    required this.count,
    required this.onClose,
  });
  final String? formNumber;
  final int count;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final num = formNumber?.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: muted.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      count > 0 ? 'ANEXOS · $count' : 'ANEXOS',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: muted,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.6,
                          ),
                    ),
                    Text(
                      num == null || num.isEmpty
                          ? 'Ficha de venda'
                          : 'Ficha de venda nº $num',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnexoTile extends StatelessWidget {
  const _AnexoTile({
    required this.anexo,
    required this.isManager,
    required this.onOpen,
    required this.onApprove,
    required this.onReject,
  });

  final SaleFormAttachment anexo;
  final bool isManager;
  final VoidCallback onOpen;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  Color _tone(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (anexo.status.toLowerCase()) {
      case 'approved':
        return isDark ? AppColors.status.greenDarkMode : AppColors.status.green;
      case 'rejected':
        return isDark ? AppColors.status.errorDarkMode : AppColors.status.error;
      default:
        return isDark
            ? AppColors.status.warningDarkMode
            : AppColors.status.warning;
    }
  }

  IconData get _icon {
    final ext = anexo.fileName.toLowerCase();
    if (ext.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    return Icons.image_outlined;
  }

  String _fmtSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final tone = _tone(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final isPending = anexo.status.toLowerCase() == 'pending_approval';
    final meta = [
      _fmtSize(anexo.fileSize),
      if (anexo.uploadedByName != null && anexo.uploadedByName!.isNotEmpty)
        'por ${anexo.uploadedByName}',
      if (anexo.createdAt != null)
        DateFormat('dd/MM/yyyy', 'pt_BR').format(anexo.createdAt!.toLocal()),
    ].where((e) => e.isNotEmpty).join(' • ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _accentFor(context).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_icon, size: 20, color: _accentFor(context)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        anexo.fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      if (meta.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            meta,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: muted),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    anexo.statusLabel.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: tone,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                          fontSize: 9.5,
                        ),
                  ),
                ),
              ],
            ),
          ),
          if (anexo.rejectionReason != null &&
              anexo.rejectionReason!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Motivo: ${anexo.rejectionReason}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppColors.status.errorDarkMode
                        : AppColors.status.error,
                  ),
            ),
          ],
          if (isManager && isPending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onReject,
                    icon: Icon(Icons.close_rounded,
                        size: 16, color: AppColors.status.error),
                    label: Text(
                      'Rejeitar',
                      style: TextStyle(color: AppColors.status.error),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: AppColors.status.error.withValues(alpha: 0.5),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Aprovar'),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          Theme.of(context).brightness == Brightness.dark
                              ? AppColors.status.greenDarkMode
                              : AppColors.status.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Color _accentFor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.primary.primaryDarkMode
          : AppColors.primary.primary;
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.folder_open_outlined,
                  size: 34, color: accent.withValues(alpha: 0.8)),
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhum anexo ainda',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Anexe a foto da ficha física assinada ou outros comprovantes '
              'usando o botão abaixo.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: muted,
                    height: 1.4,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
