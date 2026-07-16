import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/theme_helpers.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../models/ticket_models.dart';
import '../services/ticket_service.dart';

/// Galeria de anexos de um ticket/mensagem: imagens em miniaturas tocáveis
/// (zoom em tela cheia) e demais arquivos como chips que abrem no navegador.
/// Espelha o `AttachmentList` do TicketDetailPage web.
class TicketAttachmentGallery extends StatelessWidget {
  final List<TicketAttachment> attachments;

  const TicketAttachmentGallery({super.key, required this.attachments});

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    final images = attachments.where((a) => a.isImage).toList();
    final files = attachments.where((a) => !a.isImage).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (images.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final image in images)
                TicketImageAttachment(attachment: image),
            ],
          ),
        if (files.isNotEmpty) ...[
          if (images.isNotEmpty) const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final file in files)
                _TicketFileAttachmentChip(attachment: file),
            ],
          ),
        ],
      ],
    );
  }
}

/// Miniatura de anexo de imagem — resolve a fonte sob demanda (URL assinada
/// ou bytes autenticados) e abre em tela cheia com zoom ao tocar.
class TicketImageAttachment extends StatefulWidget {
  final TicketAttachment attachment;
  final double size;

  const TicketImageAttachment({
    super.key,
    required this.attachment,
    this.size = 84,
  });

  @override
  State<TicketImageAttachment> createState() => _TicketImageAttachmentState();
}

class _TicketImageAttachmentState extends State<TicketImageAttachment> {
  TicketAttachmentSource? _source;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final source = await TicketService.instance.resolveAttachment(
      widget.attachment.id,
    );
    if (!mounted) return;
    setState(() {
      if (source != null && source.hasData) {
        _source = source;
      } else {
        _failed = true;
      }
    });
  }

  Widget _image({required BoxFit fit}) {
    final source = _source!;
    if (source.bytes != null) {
      return Image.memory(source.bytes!, fit: fit);
    }
    return Image.network(
      source.url!,
      fit: fit,
      errorBuilder: (context, error, stackTrace) =>
          _Fallback(size: widget.size),
    );
  }

  void _openFullScreen() {
    if (_source == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _FullScreenImagePage(
          title: widget.attachment.fileName,
          image: _image(fit: BoxFit.contain),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    Widget child;
    if (_failed) {
      child = _Fallback(size: widget.size);
    } else if (_source == null) {
      child = SkeletonBox(
        width: widget.size,
        height: widget.size,
        borderRadius: 12,
      );
    } else {
      child = GestureDetector(
        onTap: _openFullScreen,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: _image(fit: BoxFit.cover),
        ),
      );
    }

    return ClipRRect(
      borderRadius: radius,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: ThemeHelpers.borderLightColor(context)),
        ),
        child: child,
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  final double size;

  const _Fallback({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      color: ThemeHelpers.borderLightColor(context).withValues(alpha: 0.4),
      child: Icon(
        LucideIcons.imageOff,
        size: 20,
        color: ThemeHelpers.textSecondaryColor(context),
      ),
    );
  }
}

/// Visualizador em tela cheia com pinch-to-zoom.
class _FullScreenImagePage extends StatelessWidget {
  final String title;
  final Widget image;

  const _FullScreenImagePage({required this.title, required this.image});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Center(
        child: InteractiveViewer(minScale: 0.6, maxScale: 5, child: image),
      ),
    );
  }
}

/// Chip de anexo não-imagem — abre a URL assinada no navegador.
class _TicketFileAttachmentChip extends StatefulWidget {
  final TicketAttachment attachment;

  const _TicketFileAttachmentChip({required this.attachment});

  @override
  State<_TicketFileAttachmentChip> createState() =>
      _TicketFileAttachmentChipState();
}

class _TicketFileAttachmentChipState extends State<_TicketFileAttachmentChip> {
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    final source = await TicketService.instance.resolveAttachment(
      widget.attachment.id,
    );
    if (!mounted) return;
    setState(() => _opening = false);
    final url = source?.url;
    if (url != null && url.isNotEmpty) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Não foi possível abrir este anexo agora.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final neutral = ThemeHelpers.textSecondaryColor(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: _open,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: ThemeHelpers.borderColor(context)),
            color: ThemeHelpers.cardBackgroundColor(context),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_opening)
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: neutral,
                  ),
                )
              else
                Icon(LucideIcons.paperclip, size: 13, color: neutral),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  widget.attachment.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: ThemeHelpers.textColor(context),
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
