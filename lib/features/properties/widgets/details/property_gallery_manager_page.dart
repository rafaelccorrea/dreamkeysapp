import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/navigation/adaptive_page_route.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/gallery_service.dart';
import '../../../../shared/services/property_service.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/shimmer_image.dart';
import '../../services/property_detail_extras_service.dart';
import '../../utils/gallery_media_rules.dart';
import 'property_details_kit.dart' show PdkSnackTone, PdkTone, pdkShowSnack;

/// Abre a **gestão da galeria** do imóvel (imoveis-28) — o equivalente da
/// etapa de fotos/vídeo da edição do web (`CreatePropertyPage`): reordenar
/// fotos (`PUT /gallery/reorder`), definir a capa, mostrar/ocultar cada foto
/// no site (`PUT /gallery/:id { showOnPublicSite }`), adicionar fotos e
/// enviar/trocar/remover o vídeo (`POST /gallery/upload-video`, até 1:40 e
/// 150 MB). [onMutated] avisa o detalhe para recarregar o imóvel ao voltar.
Future<void> openPropertyGalleryManager(
  BuildContext context, {
  required String propertyId,
  required List<PropertyImage> media,
  required bool canDelete,
  required VoidCallback onMutated,
}) {
  return Navigator.of(context).push<void>(
    adaptivePageRoute<void>(
      builder: (_) => PropertyGalleryManagerPage(
        propertyId: propertyId,
        media: media,
        canDelete: canDelete,
        onMutated: onMutated,
      ),
    ),
  );
}

class PropertyGalleryManagerPage extends StatefulWidget {
  final String propertyId;
  final List<PropertyImage> media;
  final bool canDelete;
  final VoidCallback onMutated;

  const PropertyGalleryManagerPage({
    super.key,
    required this.propertyId,
    required this.media,
    required this.canDelete,
    required this.onMutated,
  });

  @override
  State<PropertyGalleryManagerPage> createState() =>
      _PropertyGalleryManagerPageState();
}

class _PropertyGalleryManagerPageState
    extends State<PropertyGalleryManagerPage> {
  late List<PropertyImage> _photos;
  PropertyImage? _video;

  bool _reordering = false;
  bool _uploadingPhotos = false;
  bool _uploadingVideo = false;
  bool _removingVideo = false;
  final Set<String> _busyIds = {};

  @override
  void initState() {
    super.initState();
    _photos = galleryPhotosOf(widget.media).toList();
    _video = galleryVideoOf(widget.media);
  }

  void _mutated() => widget.onMutated();

  void _snack(String message, {PdkSnackTone tone = PdkSnackTone.info}) {
    if (!mounted) return;
    pdkShowSnack(context, message, tone: tone);
  }

  String _failMessage(String? raw, String fallback) {
    final m = raw?.trim() ?? '';
    return m.isEmpty ? fallback : m;
  }

  /// Relê a galeria do imóvel (depois de enviar fotos/vídeo, que voltam do
  /// back com ids novos).
  Future<void> _reload() async {
    final res = await PropertyService.instance.getPropertyById(widget.propertyId);
    if (!mounted || !res.success || res.data == null) return;
    final media = res.data!.images ?? const <PropertyImage>[];
    setState(() {
      _photos = galleryPhotosOf(media).toList();
      _video = galleryVideoOf(media);
    });
  }

  // ─── Ordem ────────────────────────────────────────────────────────────

  /// Aplica a nova ordem na hora e grava; falhou, volta a anterior (o mesmo
  /// otimismo das setas do web).
  Future<void> _applyOrder(List<PropertyImage> next) async {
    if (_reordering) return;
    final before = _photos;
    setState(() {
      _photos = next;
      _reordering = true;
    });
    final ids =
        (galleryReorderPayload(next)['imageIds'] as List).cast<String>();
    final res = await GalleryService.instance.reorderImages(ids);
    if (!mounted) return;
    setState(() {
      _reordering = false;
      if (!res.success) _photos = before;
    });
    if (res.success) {
      _mutated();
    } else {
      _snack(
        _failMessage(res.message, 'Erro ao reordenar'),
        tone: PdkSnackTone.error,
      );
    }
  }

  void _move(int from, int to) {
    if (from == to) return;
    _applyOrder(moveGalleryItem(_photos, from, to));
  }

  // ─── Capa / site / excluir ─────────────────────────────────────────────

  Future<void> _setMain(PropertyImage img) async {
    if (img.isMain || _busyIds.contains(img.id)) return;
    setState(() => _busyIds.add(img.id));
    final res = await GalleryService.instance.setMainImage(img.id);
    if (!mounted) return;
    setState(() {
      _busyIds.remove(img.id);
      if (res.success) {
        _photos = [
          for (final p in _photos) p.copyWith(isMain: p.id == img.id),
        ];
      }
    });
    if (res.success) {
      _mutated();
      _snack('Foto principal atualizada.', tone: PdkSnackTone.success);
    } else {
      _snack(
        _failMessage(res.message, 'Não foi possível definir a foto principal.'),
        tone: PdkSnackTone.error,
      );
    }
  }

  Future<void> _toggleSite(PropertyImage img) async {
    if (_busyIds.contains(img.id)) return;
    final show = img.showOnPublicSite == false;
    setState(() => _busyIds.add(img.id));
    final res = await PropertyDetailExtrasService.instance
        .setImageShowOnPublicSite(img.id, show: show);
    if (!mounted) return;
    setState(() {
      _busyIds.remove(img.id);
      if (res.success) {
        _photos = [
          for (final p in _photos)
            p.id == img.id ? p.copyWith(showOnPublicSite: show) : p,
        ];
      }
    });
    if (res.success) {
      _mutated();
      _snack(
        show
            ? 'A foto volta a aparecer no site.'
            : 'Foto oculta no site — segue no CRM.',
        tone: PdkSnackTone.success,
      );
    } else {
      _snack(
        _failMessage(res.message, 'Não foi possível mudar a foto no site.'),
        tone: PdkSnackTone.error,
      );
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.status.error,
              foregroundColor: Colors.white,
            ),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _deletePhoto(PropertyImage img) async {
    if (_busyIds.contains(img.id)) return;
    final ok = await _confirm(
      title: 'Excluir esta foto?',
      body: img.isMain
          ? 'Esta é a foto principal. Ao excluir, a próxima imagem assume como principal automaticamente. Esta ação não pode ser desfeita.'
          : 'A imagem será removida do imóvel e do armazenamento. Esta ação não pode ser desfeita.',
      action: 'Excluir',
    );
    if (!ok || !mounted) return;
    setState(() => _busyIds.add(img.id));
    final res = await GalleryService.instance.deleteImage(img.id);
    if (!mounted) return;
    setState(() {
      _busyIds.remove(img.id);
      if (res.success) _photos = [..._photos]..removeWhere((p) => p.id == img.id);
    });
    if (res.success) {
      _mutated();
      if (img.isMain) unawaited(_reload());
    } else {
      _snack(
        _failMessage(res.message, 'Não foi possível excluir a imagem.'),
        tone: PdkSnackTone.error,
      );
    }
  }

  // ─── Envio de fotos ────────────────────────────────────────────────────

  Future<void> _addPhotos() async {
    if (_uploadingPhotos) return;
    final picked = await ImagePicker().pickMultiImage(imageQuality: 92);
    if (picked.isEmpty || !mounted) return;
    setState(() => _uploadingPhotos = true);
    final res = await GalleryService.instance.uploadImages(
      propertyId: widget.propertyId,
      files: [for (final x in picked) File(x.path)],
    );
    if (!mounted) return;
    setState(() => _uploadingPhotos = false);
    if (res.success) {
      _mutated();
      await _reload();
      _snack(
        picked.length == 1
            ? 'Foto enviada.'
            : '${picked.length} fotos enviadas.',
        tone: PdkSnackTone.success,
      );
    } else {
      _snack(
        _failMessage(res.message, 'Não foi possível enviar as fotos.'),
        tone: PdkSnackTone.error,
      );
    }
  }

  // ─── Vídeo ─────────────────────────────────────────────────────────────

  /// Duração do arquivo (o web lê do `<video>`) pelo player nativo. `null`
  /// se o aparelho não conseguir abrir — aí o envio é BLOQUEADO
  /// (`requireDuration`), como no web: o back não mede a duração.
  Future<double?> _readDuration(File file) async {
    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize().timeout(const Duration(seconds: 20));
      final d = controller.value.duration;
      if (d <= Duration.zero) return null;
      return d.inMilliseconds / 1000.0;
    } catch (_) {
      return null;
    } finally {
      unawaited(controller.dispose());
    }
  }

  /// Capa do vídeo (o `captureVideoPoster` do web): um quadro JPEG tirado
  /// com a API nativa. Melhor esforço — falhou, o vídeo vai sem capa, igual
  /// ao web.
  Future<File?> _capturePoster(File video) async {
    try {
      final dir = await getTemporaryDirectory();
      final dest = File(
        '${dir.path}${Platform.pathSeparator}'
        'video-thumbnail-${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      final ok = await FcNativeVideoThumbnail()
          .saveThumbnailToFile(
            srcFile: video.path,
            destFile: dest.path,
            width: 1280,
            height: 1280,
            quality: 85,
          )
          .timeout(const Duration(seconds: 20));
      if (ok && await dest.exists() && await dest.length() > 0) return dest;
    } catch (_) {}
    return null;
  }

  Future<void> _pickVideo() async {
    if (_uploadingVideo) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      useSafeArea: true,
      backgroundColor: ThemeHelpers.cardBackgroundColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.film),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(LucideIcons.video),
              title: const Text('Gravar agora (até 1:40)'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final XFile? picked;
    try {
      picked = await ImagePicker().pickVideo(
        source: source,
        maxDuration:
            const Duration(seconds: kGalleryMaxVideoDurationSeconds),
      );
    } catch (_) {
      _snack(
        'Não foi possível abrir os vídeos do aparelho.',
        tone: PdkSnackTone.error,
      );
      return;
    }
    if (picked == null || !mounted) return;

    final file = File(picked.path);
    final name = picked.name.trim().isNotEmpty
        ? picked.name
        : picked.path.split(Platform.pathSeparator).last;
    final size = await file.length();
    if (!mounted) return;
    // Formato e tamanho antes de medir (rápido); a duração depois.
    final early = validateGalleryVideo(fileName: name, sizeBytes: size);
    if (early != null) {
      _snack(early, tone: PdkSnackTone.error);
      return;
    }

    setState(() => _uploadingVideo = true);
    final duration = await _readDuration(file);
    if (!mounted) return;
    // Sem duração medida não envia (o back não checa o 1:40).
    final error = validateGalleryVideo(
      fileName: name,
      sizeBytes: size,
      durationSeconds: duration,
      requireDuration: true,
    );
    if (error != null) {
      setState(() => _uploadingVideo = false);
      _snack(error, tone: PdkSnackTone.error);
      return;
    }

    final poster = await _capturePoster(file);
    if (!mounted) return;
    final res = await GalleryService.instance.uploadVideo(
      propertyId: widget.propertyId,
      file: file,
      fileName: name,
      mimeType: galleryVideoMimeType(name) ?? 'video/mp4',
      durationSeconds: duration!.round(),
      thumbnail: poster,
    );
    if (poster != null) {
      unawaited(poster.delete().then((_) {}, onError: (_) {}));
    }
    if (!mounted) return;
    setState(() => _uploadingVideo = false);
    if (res.success) {
      _mutated();
      await _reload();
      _snack(
        'Vídeo enviado — aparece no imóvel e no site.',
        tone: PdkSnackTone.success,
      );
    } else {
      _snack(
        _failMessage(res.message, 'Não foi possível enviar o vídeo.'),
        tone: PdkSnackTone.error,
      );
    }
  }

  Future<void> _removeVideo() async {
    final video = _video;
    if (video == null || _removingVideo) return;
    final ok = await _confirm(
      title: 'Remover o vídeo?',
      body: 'O vídeo sai do imóvel e do site. Esta ação não pode ser desfeita.',
      action: 'Remover',
    );
    if (!ok || !mounted) return;
    setState(() => _removingVideo = true);
    final res = await GalleryService.instance.deleteImage(video.id);
    if (!mounted) return;
    setState(() {
      _removingVideo = false;
      if (res.success) _video = null;
    });
    if (res.success) {
      _mutated();
      _snack('Vídeo removido.', tone: PdkSnackTone.success);
    } else {
      _snack(
        _failMessage(res.message, 'Não foi possível remover o vídeo.'),
        tone: PdkSnackTone.error,
      );
    }
  }

  // ─── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Fotos e vídeo',
      showBottomNavigation: false,
      showDrawer: false,
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: SliverToBoxAdapter(child: _buildVideoSection(context)),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
            sliver: SliverToBoxAdapter(child: _buildPhotosHeader(context)),
          ),
          if (_photos.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: _EmptyNote(
                  icon: LucideIcons.imageOff,
                  text: 'Nenhuma foto ainda. Toque em "Adicionar" para enviar.',
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
              sliver: SliverReorderableList(
                itemCount: _photos.length,
                // `onReorderItem` já entrega o destino ajustado.
                onReorderItem: _move,
                itemBuilder: (context, i) => _PhotoRow(
                  key: ValueKey('gm-${_photos[i].id}'),
                  index: i,
                  total: _photos.length,
                  image: _photos[i],
                  busy: _busyIds.contains(_photos[i].id) || _reordering,
                  canDelete: widget.canDelete,
                  onUp: i == 0 ? null : () => _move(i, i - 1),
                  onDown:
                      i == _photos.length - 1 ? null : () => _move(i, i + 1),
                  onSetMain: () => _setMain(_photos[i]),
                  onToggleSite: () => _toggleSite(_photos[i]),
                  onDelete: () => _deletePhoto(_photos[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPhotosHeader(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final hidden = _photos.where((p) => p.showOnPublicSite == false).length;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Fotos · ${_photos.length}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                hidden > 0
                    ? 'Arraste ou use as setas para ordenar · $hidden oculta(s) no site'
                    : 'Arraste ou use as setas para ordenar. A ordem vale no site.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: secondary,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        FilledButton.tonalIcon(
          onPressed: _uploadingPhotos ? null : _addPhotos,
          icon: _uploadingPhotos
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(LucideIcons.imagePlus, size: 16),
          label: Text(_uploadingPhotos ? 'Enviando…' : 'Adicionar'),
        ),
      ],
    );
  }

  Widget _buildVideoSection(BuildContext context) {
    final theme = Theme.of(context);
    final tone = PdkTone.violet(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final video = _video;
    final busy = _uploadingVideo || _removingVideo;
    final poster = video?.posterUrl;
    final duration = video?.durationSeconds;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: tone.withValues(alpha: 0.07),
        border: Border.all(color: tone.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(LucideIcons.video, color: tone, size: 18),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vídeo do imóvel',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Até 1:40 (100s), exibido também no site · MP4, MOV ou '
                      'WebM · máx. ${kGalleryMaxVideoBytes ~/ (1024 * 1024)}MB',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (video != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (poster != null)
                      ShimmerImage(
                        imageUrl: poster,
                        fit: BoxFit.cover,
                        errorWidget: Container(color: Colors.black87),
                      )
                    else
                      Container(color: Colors.black87),
                    const Center(
                      child: Icon(
                        Icons.play_circle_fill_rounded,
                        size: 54,
                        color: Colors.white,
                      ),
                    ),
                    if (duration != null && duration > 0)
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            formatGalleryVideoDuration(duration),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (video != null) const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : _pickVideo,
                  style: FilledButton.styleFrom(backgroundColor: tone),
                  icon: _uploadingVideo
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          video == null
                              ? LucideIcons.upload
                              : LucideIcons.refreshCw,
                          size: 16,
                        ),
                  label: Text(
                    _uploadingVideo
                        ? 'Enviando vídeo…'
                        : (video == null ? 'Enviar vídeo' : 'Trocar vídeo'),
                  ),
                ),
              ),
              if (video != null && widget.canDelete) ...[
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: busy ? null : _removeVideo,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: PdkTone.red(context),
                    side: BorderSide(
                      color: PdkTone.red(context).withValues(alpha: 0.6),
                    ),
                  ),
                  icon: _removingVideo
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(LucideIcons.trash2, size: 16),
                  label: const Text('Remover'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _PhotoRow extends StatelessWidget {
  final int index;
  final int total;
  final PropertyImage image;
  final bool busy;
  final bool canDelete;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback onSetMain;
  final VoidCallback onToggleSite;
  final VoidCallback onDelete;

  const _PhotoRow({
    super.key,
    required this.index,
    required this.total,
    required this.image,
    required this.busy,
    required this.canDelete,
    required this.onUp,
    required this.onDown,
    required this.onSetMain,
    required this.onToggleSite,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final hidden = image.showOnPublicSite == false;
    final amber = PdkTone.amber(context);
    final thumb = (image.thumbnailUrl ?? '').trim().isNotEmpty
        ? image.thumbnailUrl!
        : image.url;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: ThemeHelpers.borderLightColor(context)),
        ),
      ),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            enabled: !busy,
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(LucideIcons.gripVertical, size: 18, color: secondary),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Opacity(
              opacity: hidden ? 0.45 : 1,
              child: ShimmerImage(
                imageUrl: thumb,
                width: 74,
                height: 56,
                fit: BoxFit.cover,
                errorWidget: Container(
                  width: 74,
                  height: 56,
                  color: ThemeHelpers.borderLightColor(context),
                  child: Icon(LucideIcons.imageOff, size: 18, color: secondary),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Posição ${index + 1}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (image.isMain)
                      _Tag(label: 'Capa', tone: amber, icon: Icons.star_rounded),
                    if (hidden)
                      _Tag(
                        label: 'Oculta no site',
                        tone: secondary,
                        icon: Icons.visibility_off_rounded,
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          PopupMenuButton<String>(
            enabled: !busy,
            tooltip: 'Ações da foto',
            icon: Icon(Icons.more_vert_rounded, color: secondary),
            onSelected: (v) {
              switch (v) {
                case 'up':
                  onUp?.call();
                case 'down':
                  onDown?.call();
                case 'main':
                  onSetMain();
                case 'site':
                  onToggleSite();
                case 'delete':
                  onDelete();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'up',
                enabled: onUp != null,
                child: const ListTile(
                  dense: true,
                  leading: Icon(Icons.arrow_upward_rounded),
                  title: Text('Mover para cima'),
                ),
              ),
              PopupMenuItem(
                value: 'down',
                enabled: onDown != null,
                child: const ListTile(
                  dense: true,
                  leading: Icon(Icons.arrow_downward_rounded),
                  title: Text('Mover para baixo'),
                ),
              ),
              PopupMenuItem(
                value: 'main',
                enabled: !image.isMain,
                child: const ListTile(
                  dense: true,
                  leading: Icon(Icons.star_outline_rounded),
                  title: Text('Definir como capa'),
                ),
              ),
              PopupMenuItem(
                value: 'site',
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    hidden
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                  ),
                  title: Text(hidden ? 'Mostrar no site' : 'Ocultar do site'),
                ),
              ),
              if (canDelete)
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.delete_outline_rounded,
                      color: AppColors.status.error,
                    ),
                    title: Text(
                      'Excluir foto',
                      style: TextStyle(color: AppColors.status.error),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color tone;
  final IconData icon;

  const _Tag({required this.label, required this.tone, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: tone),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: tone,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  final IconData icon;
  final String text;

  const _EmptyNote({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26),
      child: Column(
        children: [
          Icon(icon, size: 28, color: secondary),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: secondary, height: 1.4),
          ),
        ],
      ),
    );
  }
}
