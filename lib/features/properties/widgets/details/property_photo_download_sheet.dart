import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/property_service.dart';
import '../../../../shared/utils/error_cause.dart';
import '../../../../shared/widgets/app_error_state.dart';
import '../../../../shared/widgets/skeleton_box.dart';
import '../../services/property_detail_extras_service.dart';
import 'property_details_kit.dart';
import 'property_file_delivery.dart';

/// Motivo do cadeado de "Baixar fotos" — a frase curta de permissão do web
/// (`getPermissionBlockedShort('property:download_images')`).
const String kPropertyDownloadImagesLockedReason =
    'Sem a permissão "Baixar imagens do imóvel". Fale com o seu gestor ou '
    'com o suporte.';

/// Abre a folha "Baixar fotos" da galeria — paridade com o menu de download
/// do `PropertyImageCarousel` do web (211-308, 727-795): foto atual, todas
/// ou escolher várias. Sem ZIP no app: as fotos saem uma a uma e vão juntas
/// na folha do sistema (Compartilhar); com UMA foto também dá para "Salvar
/// no aparelho".
///
/// Regras iguais ao web:
/// - só com `property:download_images` ([canDownload]; master/admin passam
///   direto — calcule com `PropertyDetailExtrasService.webHasPermission`);
///   sem ela a folha abre TRAVADA com o motivo;
/// - cada foto vem de `GET /gallery/images/:id/file` (cai na URL pública da
///   foto quando o proxy falha); foto que não está mais no armazenamento
///   fica de fora e a folha diz quantas;
/// - depois do download, registra `POST /properties/:id/track-download`
///   (`single` para uma foto, `zip` com a quantidade para várias — os dois
///   valores que o back aceita; vira "Download de imagens em ZIP (N)" no
///   histórico, como no web);
/// - nomes: `foto-01-marca-dagua.jpg` (foto atual) e `{código-título}-01.jpg`
///   (várias), com a extensão real do arquivo.
///
/// [images] = a galeria como a página mostra (vídeos são ignorados aqui);
/// [currentImageId] = a foto na tela (sem ele, a primeira).
Future<void> showPropertyPhotoDownloadSheet(
  BuildContext context, {
  required String propertyId,
  required List<PropertyImage> images,
  required bool canDownload,
  String? currentImageId,
  String? propertyCode,
  String? propertyTitle,
  String? lockedReason,
}) {
  final photos = images
      .where((i) => !i.isVideo && i.url.trim().isNotEmpty)
      .toList(growable: false);
  var current = photos.indexWhere((p) => p.id == currentImageId);
  if (current < 0) current = 0;
  final baseName = _slugify(
    [
      propertyCode?.trim() ?? '',
      propertyTitle?.trim() ?? '',
    ].where((s) => s.isNotEmpty).join('-'),
  );
  final custom = lockedReason?.trim() ?? '';
  final reason = custom.isNotEmpty
      ? custom
      : (canDownload ? null : kPropertyDownloadImagesLockedReason);
  return showPdkSheet<void>(
    context: context,
    builder: (_) => _PhotoDownloadSheet(
      propertyId: propertyId,
      photos: photos,
      currentIndex: current,
      baseName: baseName,
      lockedReason: reason,
    ),
  );
}

enum _Scope { current, all, pick }

enum _Phase { choose, working, ready, failed }

class _PhotoDownloadSheet extends StatefulWidget {
  const _PhotoDownloadSheet({
    required this.propertyId,
    required this.photos,
    required this.currentIndex,
    required this.baseName,
    this.lockedReason,
  });

  final String propertyId;
  final List<PropertyImage> photos;
  final int currentIndex;
  final String baseName;
  final String? lockedReason;

  @override
  State<_PhotoDownloadSheet> createState() => _PhotoDownloadSheetState();
}

class _PhotoDownloadSheetState extends State<_PhotoDownloadSheet> {
  _Scope _scope = _Scope.current;
  _Phase _phase = _Phase.choose;
  final Set<String> _picked = <String>{};
  bool _pickEmptyWarning = false;

  /// Nova tentativa (ou cancelar) descarta o laço em andamento.
  int _attempt = 0;
  int _done = 0;
  int _total = 0;
  int _missing = 0;
  List<PropertyLocalFile> _files = const <PropertyLocalFile>[];
  ErrorCause? _failure;
  bool _sharing = false;
  bool _saving = false;
  ({bool ok, String text})? _note;

  int get _count => widget.photos.length;

  List<PropertyImage> get _chosen {
    switch (_scope) {
      case _Scope.current:
        return <PropertyImage>[widget.photos[widget.currentIndex]];
      case _Scope.all:
        return widget.photos;
      case _Scope.pick:
        return widget.photos.where((p) => _picked.contains(p.id)).toList();
    }
  }

  Future<void> _start() async {
    final chosen = _chosen;
    if (chosen.isEmpty) {
      setState(() => _pickEmptyWarning = true);
      return;
    }
    final attempt = ++_attempt;
    final single = _scope == _Scope.current;
    setState(() {
      _phase = _Phase.working;
      _done = 0;
      _total = chosen.length;
      _missing = 0;
      _files = const <PropertyLocalFile>[];
      _failure = null;
      _note = null;
      _pickEmptyWarning = false;
    });

    final service = PropertyDetailExtrasService.instance;
    final files = <PropertyLocalFile>[];
    var missing = 0;
    for (var i = 0; i < chosen.length; i++) {
      final photo = chosen[i];
      final res = await service.downloadGalleryImage(
        photo.id,
        fallbackUrl: photo.url,
      );
      if (!mounted || attempt != _attempt) return;
      final file = res.data;
      if (res.success && file != null) {
        final ext = PropertyDetailExtrasService.extensionForMime(file.mimeType);
        final name = single
            ? 'foto-${_pad(widget.currentIndex + 1)}-marca-dagua.$ext'
            : '${widget.baseName}-${_pad(files.length + 1)}.$ext';
        try {
          files.add(await PropertyFileDelivery.persist(file, name: name));
        } catch (e) {
          debugPrint('[PHOTO_DOWNLOAD] gravar: $e');
          if (!mounted || attempt != _attempt) return;
          setState(() {
            _phase = _Phase.failed;
            _failure = ErrorCause.fromException(e);
          });
          return;
        }
      } else if (res.statusCode == 404) {
        // Registro sem arquivo no armazenamento: fica de fora (o web pula).
        missing++;
      } else {
        // Falha de verdade (rede, permissão, servidor): o web interrompe o
        // pacote inteiro — aqui também, com a causa.
        setState(() {
          _phase = _Phase.failed;
          _failure = pdkFailureCause(res);
        });
        return;
      }
      if (!mounted || attempt != _attempt) return;
      setState(() => _done = i + 1);
    }

    if (files.isEmpty) {
      setState(() {
        _phase = _Phase.failed;
        _failure = _allMissingCause(context, single: single);
      });
      return;
    }

    // Registro no histórico (melhor esforço, igual ao web).
    unawaited(
      service.trackImageDownload(
        widget.propertyId,
        kind: single ? 'single' : 'zip',
        count: single ? 1 : chosen.length,
      ),
    );

    setState(() {
      _phase = _Phase.ready;
      _files = files;
      _missing = missing;
    });
  }

  void _cancelWork() {
    setState(() {
      _attempt++;
      _phase = _Phase.choose;
    });
  }

  Future<void> _share(BuildContext anchor) async {
    if (_sharing || _files.isEmpty) return;
    final origin = PropertyFileDelivery.originOf(anchor);
    setState(() {
      _sharing = true;
      _note = null;
    });
    final ok = await PropertyFileDelivery.share(
      _files,
      subject: _files.length == 1 ? 'Foto do imóvel' : 'Fotos do imóvel',
      origin: origin,
    );
    if (!mounted) return;
    setState(() {
      _sharing = false;
      if (!ok) {
        _note = (
          ok: false,
          text: _files.length == 1
              ? 'O aparelho não abriu as opções de envio. Use "Salvar no '
                  'aparelho".'
              : 'O aparelho não abriu as opções de envio. Tente de novo em '
                  'instantes.',
        );
      }
    });
  }

  Future<void> _save() async {
    if (_saving || _files.length != 1) return;
    setState(() {
      _saving = true;
      _note = null;
    });
    try {
      final saved = await PropertyFileDelivery.saveOne(
        _files.first,
        dialogTitle: 'Salvar foto',
      );
      if (!mounted) return;
      if (saved) {
        setState(() {
          _note = (
            ok: true,
            text: 'Foto salva no aparelho. Abra pelo app de arquivos.',
          );
        });
      }
    } catch (e) {
      debugPrint('[PHOTO_DOWNLOAD] salvar: $e');
      if (!mounted) return;
      setState(() {
        _note = (
          ok: false,
          text: 'Não foi possível salvar no aparelho. Use "Compartilhar" e '
              'escolha onde guardar.',
        );
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _count;
    final subtitle = count == 0
        ? 'Nenhuma foto neste imóvel'
        : (count == 1 ? '1 foto neste imóvel' : '$count fotos neste imóvel');
    final locked = (widget.lockedReason ?? '').trim();
    if (locked.isNotEmpty) {
      return PdkSheetFrame(
        icon: LucideIcons.lockKeyhole,
        tone: PdkTone.violet(context),
        title: 'Baixar fotos',
        subtitle: subtitle,
        onClose: () => Navigator.of(context).maybePop(),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: PdkLockNote(
            title: 'Baixar fotos está travado',
            reason: locked,
          ),
        ),
        footer: PdkNeutralButton(
          label: 'Fechar',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      );
    }

    final blue = PdkTone.blue(context);
    return PdkSheetFrame(
      icon: LucideIcons.imageDown,
      tone: blue,
      title: 'Baixar fotos',
      subtitle: subtitle,
      onClose: () => Navigator.of(context).maybePop(),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: count == 0 ? _buildEmpty(context) : _buildBody(context),
      ),
      footer: count == 0
          ? PdkNeutralButton(
              label: 'Fechar',
              onPressed: () => Navigator.of(context).maybePop(),
            )
          : _buildFooter(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_phase) {
      case _Phase.choose:
        return _buildChoose(context);
      case _Phase.working:
        return _buildWorking(context);
      case _Phase.ready:
        return _buildReady(context);
      case _Phase.failed:
        final failure = _failure ?? _allMissingCause(context, single: false);
        return AppErrorState(cause: failure, onRetry: _start, dense: true);
    }
  }

  Widget _buildEmpty(BuildContext context) {
    return PdkNote(
      icon: LucideIcons.imageOff,
      tone: PdkTone.blue(context),
      text: 'Este imóvel ainda não tem fotos para baixar. Assim que alguém '
          'enviar fotos pela edição do imóvel, elas aparecem aqui.',
    );
  }

  Widget _buildChoose(BuildContext context) {
    final count = _count;
    final green = PdkTone.green(context);
    final blue = PdkTone.blue(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PdkBlockLabel(
          'O que você quer baixar?',
          hint: 'As fotos saem do armazenamento do sistema no tamanho '
              'original.',
        ),
        const SizedBox(height: 12),
        PdkChoiceRow(
          icon: LucideIcons.image,
          tone: blue,
          title: 'Foto atual',
          description: count == 1
              ? 'A única foto do imóvel.'
              : 'A foto ${widget.currentIndex + 1} de $count — a que está na '
                  'tela.',
          selected: _scope == _Scope.current,
          onTap: () => setState(() {
            _scope = _Scope.current;
            _pickEmptyWarning = false;
          }),
        ),
        if (count > 1) ...[
          const SizedBox(height: 8),
          PdkChoiceRow(
            icon: LucideIcons.images,
            tone: green,
            title: 'Todas as fotos',
            description: 'As $count fotos, uma a uma, prontas para '
                'compartilhar.',
            selected: _scope == _Scope.all,
            onTap: () => setState(() {
              _scope = _Scope.all;
              _pickEmptyWarning = false;
            }),
          ),
          const SizedBox(height: 8),
          PdkChoiceRow(
            icon: LucideIcons.listChecks,
            tone: PdkTone.amber(context),
            title: 'Escolher várias',
            description: 'Toque nas fotos que quer levar.',
            selected: _scope == _Scope.pick,
            onTap: () => setState(() => _scope = _Scope.pick),
          ),
        ],
        if (_scope == _Scope.pick) ...[
          const SizedBox(height: 16),
          _buildPickHeader(context),
          const SizedBox(height: 10),
          _PhotoPickGrid(
            photos: widget.photos,
            picked: _picked,
            onToggle: (id) => setState(() {
              if (!_picked.remove(id)) _picked.add(id);
              _pickEmptyWarning = false;
            }),
          ),
          if (_pickEmptyWarning) ...[
            const SizedBox(height: 10),
            PdkNote(
              icon: LucideIcons.circleAlert,
              tone: PdkTone.amber(context),
              text: 'Selecione pelo menos uma imagem.',
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildPickHeader(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final n = _picked.length;
    final all = n == _count;
    return Row(
      children: [
        Expanded(
          child: Text(
            n == 0
                ? 'Nenhuma selecionada'
                : (n == 1 ? '1 selecionada' : '$n selecionadas'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: ThemeHelpers.textColor(context),
              fontSize: 13,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: () => setState(() {
            if (all) {
              _picked.clear();
            } else {
              _picked
                ..clear()
                ..addAll(widget.photos.map((p) => p.id));
              _pickEmptyWarning = false;
            }
          }),
          style: TextButton.styleFrom(
            foregroundColor: secondary,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          child: PdkButtonLabel(all ? 'Nenhuma' : 'Todas'),
        ),
      ],
    );
  }

  Widget _buildWorking(BuildContext context) {
    final blue = PdkTone.blue(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final total = _total == 0 ? 1 : _total;
    final label = _total <= 1
        ? 'Baixando a foto…'
        : 'Baixando ${math.min(_done + 1, _total)} de $_total…';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            color: ThemeHelpers.textColor(context),
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 10),
        Semantics(
          label: 'Andamento do download',
          value: '$_done de $_total',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: _total <= 1 ? null : _done / total,
              color: blue,
              backgroundColor: blue.withValues(alpha: 0.14),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Pode levar alguns segundos por foto. Ao terminar, você escolhe '
          'para onde enviar.',
          style: TextStyle(color: secondary, fontSize: 12.5, height: 1.4),
        ),
      ],
    );
  }

  Widget _buildReady(BuildContext context) {
    final files = _files;
    final green = PdkTone.green(context);
    final note = _note;
    final totalSize = files.fold<int>(0, (sum, f) => sum + f.size);
    final title = files.length == 1
        ? 'Foto pronta'
        : '${files.length} fotos prontas';
    final names = files.length <= 2
        ? files.map((f) => f.name).join(', ')
        : '${files.first.name}, ${files[1].name} e mais ${files.length - 2}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                LucideIcons.circleCheck,
                size: 18,
                color: pdkInk(context, green),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: ThemeHelpers.textColor(context),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        PropertyFileCard(
          name: names,
          mimeType: files.first.mimeType,
          size: totalSize,
          caption: files.length == 1 ? null : '${files.length} arquivos',
        ),
        if (_missing > 0) ...[
          const SizedBox(height: 10),
          PdkNote(
            icon: LucideIcons.imageOff,
            tone: PdkTone.amber(context),
            text: _missing == 1
                ? '1 foto não está mais no armazenamento e ficou de fora.'
                : '$_missing fotos não estão mais no armazenamento e ficaram '
                    'de fora.',
          ),
        ],
        if (files.length > 1) ...[
          const SizedBox(height: 10),
          PdkNote(
            icon: LucideIcons.info,
            tone: PdkTone.blue(context),
            text: 'Para guardar todas de uma vez, toque em Compartilhar e '
                'escolha "Salvar imagens" (iPhone) ou a Galeria/Arquivos '
                '(Android).',
          ),
        ],
        if (note != null) ...[
          const SizedBox(height: 10),
          PropertyInlineResult(ok: note.ok, text: note.text),
        ],
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
    final green = PdkTone.green(context);
    switch (_phase) {
      case _Phase.choose:
        final n = _scope == _Scope.current
            ? 1
            : (_scope == _Scope.all ? _count : _picked.length);
        final label = _scope == _Scope.current
            ? 'Baixar foto'
            : (n == 1 ? 'Baixar 1 foto' : 'Baixar $n fotos');
        return PdkActionPair(
          primary: PdkSolidButton(
            label: label,
            tone: green,
            icon: LucideIcons.download,
            onPressed: _start,
          ),
          secondary: PdkNeutralButton(
            label: 'Cancelar',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          minPrimary: 150,
          minSecondary: 110,
        );
      case _Phase.working:
        return PdkNeutralButton(
          label: 'Parar',
          icon: LucideIcons.x,
          onPressed: _cancelWork,
        );
      case _Phase.ready:
        final share = Builder(
          builder: (anchor) => PdkSolidButton(
            label: _files.length == 1
                ? 'Compartilhar'
                : 'Compartilhar (${_files.length})',
            tone: green,
            icon: LucideIcons.share2,
            busy: _sharing,
            onPressed: () => _share(anchor),
          ),
        );
        if (_files.length == 1) {
          return PdkActionPair(
            primary: share,
            secondary: PdkNeutralButton(
              label: _saving ? 'Salvando…' : 'Salvar no aparelho',
              icon: LucideIcons.download,
              onPressed: _saving ? null : _save,
            ),
            minPrimary: 140,
            minSecondary: 150,
          );
        }
        return PdkActionPair(
          primary: share,
          secondary: PdkNeutralButton(
            label: 'Fechar',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        );
      case _Phase.failed:
        return PdkActionPair(
          primary: PdkNeutralButton(
            label: 'Escolher de novo',
            icon: LucideIcons.listChecks,
            onPressed: () => setState(() => _phase = _Phase.choose),
          ),
          secondary: PdkNeutralButton(
            label: 'Fechar',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        );
    }
  }

  /// Nenhuma das fotos escolhidas está no armazenamento.
  ErrorCause _allMissingCause(BuildContext context, {required bool single}) {
    return ErrorCause(
      title: single ? 'Foto indisponível' : 'Fotos indisponíveis',
      cause: single
          ? 'O arquivo desta foto não está mais no armazenamento do sistema.'
          : 'Os arquivos das fotos escolhidas não estão mais no armazenamento '
              'do sistema.',
      action: 'Atualize a galeria do imóvel; se continuar, fale com o '
          'suporte.',
      kind: ErrorKind.ausente,
      icon: LucideIcons.imageOff,
      tone: PdkTone.amber(context),
      retryable: true,
    );
  }
}

/// Grade de miniaturas para "Escolher várias": colunas pela largura (3 em
/// 320dp, até 6 no tablet), quadrados, marca verde na escolhida.
class _PhotoPickGrid extends StatelessWidget {
  const _PhotoPickGrid({
    required this.photos,
    required this.picked,
    required this.onToggle,
  });

  final List<PropertyImage> photos;
  final Set<String> picked;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final width = constraints.maxWidth;
        final cols = (width / 104).floor().clamp(3, 6);
        final tile = (width - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < photos.length; i++)
              _PhotoPickTile(
                photo: photos[i],
                index: i,
                size: tile,
                selected: picked.contains(photos[i].id),
                onTap: () => onToggle(photos[i].id),
              ),
          ],
        );
      },
    );
  }
}

class _PhotoPickTile extends StatelessWidget {
  const _PhotoPickTile({
    required this.photo,
    required this.index,
    required this.size,
    required this.selected,
    required this.onTap,
  });

  final PropertyImage photo;
  final int index;
  final double size;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final green = PdkTone.green(context);
    final thumb = (photo.thumbnailUrl ?? '').trim().isNotEmpty
        ? photo.thumbnailUrl!.trim()
        : photo.url;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final radius = BorderRadius.circular(10);
    return Semantics(
      button: true,
      selected: selected,
      label: 'Foto ${index + 1}',
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: radius,
                child: Image.network(
                  thumb,
                  fit: BoxFit.cover,
                  cacheWidth: (size * dpr).round(),
                  loadingBuilder: (context, child, progress) =>
                      progress == null
                          ? child
                          : SkeletonBox(
                              width: size,
                              height: size,
                              borderRadius: 10,
                            ),
                  errorBuilder: (context, error, stack) => Container(
                    color: ThemeHelpers.borderLightColor(context),
                    alignment: Alignment.center,
                    child: Icon(
                      LucideIcons.imageOff,
                      size: 20,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    color: selected
                        ? green
                        : ThemeHelpers.borderLightColor(context),
                    width: selected ? 3 : 1,
                  ),
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? pdkSolid(green)
                        : Colors.black.withValues(alpha: 0.35),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: selected
                      ? const Icon(
                          LucideIcons.check,
                          size: 13,
                          color: Colors.white,
                        )
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _pad(int n) => n.toString().padLeft(2, '0');

/// Nome-base dos arquivos — `slugifyBaseName` do web: sem acento, só letras,
/// números, "-" e "_", até 80 caracteres; vazio vira "imovel".
String _slugify(String name) {
  const from = 'áàâãäåÁÀÂÃÄÅéèêëÉÈÊËíìîïÍÌÎÏóòôõöÓÒÔÕÖúùûüÚÙÛÜçÇñÑ';
  const to = 'aaaaaaAAAAAAeeeeEEEEiiiiIIIIoooooOOOOOuuuuUUUUcCnN';
  final buffer = StringBuffer();
  for (final rune in name.runes) {
    final ch = String.fromCharCode(rune);
    final i = from.indexOf(ch);
    buffer.write(i >= 0 ? to[i] : ch);
  }
  var slug = buffer
      .toString()
      .replaceAll(RegExp(r'[^a-zA-Z0-9\-_]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.length > 80) slug = slug.substring(0, 80);
  return slug.isEmpty ? 'imovel' : slug;
}
