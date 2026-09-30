import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/api_service.dart';
import '../../../../shared/services/property_service.dart';
import '../../../../shared/widgets/file_delivery_sheet.dart';
import '../../services/property_detail_extras_service.dart';
import 'property_details_kit.dart';

/// Certificado da autorização do proprietário ASSINADA — paridade com o
/// `OwnerAuthorizationCertificate` do web (92-265), o documento de forma
/// própria aprovado em ouro: moldura dupla com cantoneiras, ficha em pares,
/// medalhão com carimbo "Assinada", floreio de assinatura e o botão de ouro.
///
/// Quem baixa (regra do web, permanente):
/// - admin/master → qualquer imóvel;
/// - responsável ou captador vinculado → os seus;
/// - gestor → os seus e os da equipe (responsável/captador entre os
///   usuários que ele alcança — `GET /hierarchy/accessible-users`).
///
/// Quem não pode NÃO deixa de ver: o certificado aparece travado, sem o nome
/// do proprietário ("Dados restritos") e com "Download restrito" + o motivo.
/// Enquanto a equipe do gestor é conferida, fica travado (nunca liberado por
/// engano).
///
/// Baixar: `GET /properties/:id/owner-authorization/signed-pdf` → folha
/// "arquivo pronto" (Compartilhar / Salvar no aparelho).
///
/// A página monta dentro da seção "Documentos", ANTES da lista de documentos,
/// só quando [isVisible] (autorização assinada). Passe o [Property] do
/// detalhe, o id e o papel do usuário logado
/// (`ModuleAccessService.instance.userId` / `.userRole`).
class PropertyOwnerAuthCertificate extends StatefulWidget {
  const PropertyOwnerAuthCertificate({
    super.key,
    required this.property,
    required this.currentUserId,
    required this.userRole,
  });

  final Property property;
  final String? currentUserId;
  final String? userRole;

  /// A autorização está assinada (`ownerAuthSignedAt` ou status `signed`).
  static bool isVisible(Property property) =>
      (property.ownerAuthSignedAt ?? '').trim().isNotEmpty ||
      (property.ownerAuthStatus ?? '').trim().toLowerCase() == 'signed';

  /// Todas as pessoas ligadas ao imóvel (responsáveis e captadores, sem
  /// repetir) — `linkedUserIds` do web.
  static Set<String> linkedUserIds(Property p) {
    final ids = <String>{};
    void add(String? id) {
      final v = id?.trim() ?? '';
      if (v.isNotEmpty) ids.add(v);
    }

    add(p.responsibleUserId);
    for (final id in p.responsibleUserIds ?? const <String>[]) {
      add(id);
    }
    for (final r in p.responsibles ?? const <PropertyResponsible>[]) {
      add(r.id);
    }
    add(p.capturedById);
    for (final id in p.capturedByIds ?? const <String>[]) {
      add(id);
    }
    add(p.capturedBy?.id);
    for (final c in p.captors ?? const <PropertyCaptor>[]) {
      add(c.id);
    }
    return ids;
  }

  @override
  State<PropertyOwnerAuthCertificate> createState() =>
      _PropertyOwnerAuthCertificateState();
}

class _PropertyOwnerAuthCertificateState
    extends State<PropertyOwnerAuthCertificate> {
  /// Gestor: a equipe dele inclui alguém vinculado? `null` = conferindo.
  bool? _teamSees;
  bool _downloading = false;

  String get _role => widget.userRole?.trim().toLowerCase() ?? '';
  String get _me => widget.currentUserId?.trim() ?? '';

  bool get _elevated => _role == 'master' || _role == 'admin';

  bool get _linked =>
      _me.isNotEmpty &&
      PropertyOwnerAuthCertificate.linkedUserIds(widget.property).contains(_me);

  bool get _needsTeam => _role == 'manager' && !_elevated && !_linked;

  bool get _allowed =>
      _me.isNotEmpty &&
      (_elevated || _linked || (_needsTeam && _teamSees == true));

  @override
  void initState() {
    super.initState();
    _checkTeam();
  }

  @override
  void didUpdateWidget(covariant PropertyOwnerAuthCertificate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.property.id != widget.property.id ||
        oldWidget.currentUserId != widget.currentUserId ||
        oldWidget.userRole != widget.userRole) {
      _teamSees = null;
      _checkTeam();
    }
  }

  Future<void> _checkTeam() async {
    if (!PropertyOwnerAuthCertificate.isVisible(widget.property) ||
        !_needsTeam) {
      return;
    }
    final propertyId = widget.property.id;
    final res =
        await PropertyDetailExtrasService.instance.getAccessibleUserIds();
    if (!mounted || widget.property.id != propertyId) return;
    final accessible = res.data ?? const <String>{};
    final linked = PropertyOwnerAuthCertificate.linkedUserIds(widget.property);
    setState(() {
      _teamSees = res.success && linked.any(accessible.contains);
    });
  }

  /// PDF da autorização assinada pela folha de arquivo do app
  /// (Compartilhar / Salvar no aparelho).
  Future<void> _download() async {
    if (_downloading || !_allowed) return;
    setState(() => _downloading = true);
    final p = widget.property;
    final code = p.code?.trim() ?? '';
    await showFileDeliverySheet(
      context,
      title: 'Autorização assinada',
      subtitle: [
        if (code.isNotEmpty) 'Imóvel $code',
        if (p.title.trim().isNotEmpty) p.title.trim(),
      ].join(' · '),
      expectedType: 'PDF',
      generatingTitle: 'Buscando a autorização assinada…',
      generatingHint: 'O PDF vem do Autentique com a assinatura do '
          'proprietário.',
      readyTitle: 'Autorização pronta',
      shareSubject: 'Autorização do proprietário assinada',
      saveDialogTitle: 'Salvar autorização assinada',
      load: () async {
        final res = await PropertyDetailExtrasService.instance
            .downloadOwnerAuthorizationSignedPdf(p.id);
        final file = res.data;
        if (!res.success || file == null) {
          return ApiResponse.error(
            message: res.message ?? '',
            statusCode: res.statusCode,
            data: res.error,
          );
        }
        return ApiResponse.success(
          data: DeliverableFile(
            bytes: file.bytes,
            fileName: file.fileName,
            mimeType: file.mimeType,
          ),
          statusCode: res.statusCode,
        );
      },
    );
    if (mounted) setState(() => _downloading = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.property;
    if (!PropertyOwnerAuthCertificate.isVisible(p)) {
      return const SizedBox.shrink();
    }
    final gold = _gold(context);
    final allowed = _allowed;
    final ownerName = !allowed ||
            p.canViewOwnerData == false ||
            p.ownerDataRestricted == true
        ? null
        : _nonEmpty(p.owner?.name);

    return Semantics(
      container: true,
      label: 'Certificado da autorização do proprietário',
      child: _CertificatePaper(
        gold: gold,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = pdkTextScale(context);
            final wide = constraints.maxWidth >= 540 * scale;
            final text = _buildText(context, gold, ownerName, allowed);
            final seal = _buildSeal(context, gold, allowed);
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: text),
                  const SizedBox(width: 18),
                  SizedBox(width: 180, child: seal),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [text, const SizedBox(height: 18), seal],
            );
          },
        ),
      ),
    );
  }

  Widget _buildText(
    BuildContext context,
    Color gold,
    String? ownerName,
    bool allowed,
  ) {
    final p = widget.property;
    final ink = pdkInk(context, gold);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final sent = _stamp(p.ownerAuthSentAt);
    final signed = _stamp(p.ownerAuthSignedAt);
    final code = p.code?.trim() ?? '';
    final register = p.id.length >= 8
        ? p.id.substring(0, 8).toUpperCase()
        : p.id.toUpperCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(LucideIcons.scrollText, size: 14, color: ink),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'CERTIFICADO DE ASSINATURA',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ink,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 1,
                color: gold.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Autorização do proprietário',
          style: TextStyle(
            color: ThemeHelpers.textColor(context),
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Documento assinado e registrado. Continua disponível em qualquer '
          'fase do imóvel — disponível, vendido ou desativado.',
          style: TextStyle(color: secondary, fontSize: 12.5, height: 1.4),
        ),
        const SizedBox(height: 12),
        _Pair(
          label: 'Imóvel',
          gold: gold,
          value: Text.rich(
            TextSpan(
              children: [
                if (code.isNotEmpty) ...[
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: _CodeChip(code: code, gold: gold),
                  ),
                  const TextSpan(text: '  '),
                ],
                TextSpan(text: p.title.trim()),
              ],
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: _valueStyle(context),
          ),
        ),
        _Pair(
          label: 'Proprietário',
          gold: gold,
          value: ownerName != null
              ? Text(
                  ownerName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _valueStyle(context),
                )
              : Row(
                  children: [
                    Icon(
                      LucideIcons.lock,
                      size: 13,
                      color: pdkInk(context, PdkTone.violet(context)),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        'Dados restritos',
                        style: _valueStyle(context).copyWith(
                          color: secondary,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        if (sent != null)
          _Pair(
            label: 'Enviada em',
            gold: gold,
            value: _DateValue(date: sent.date, time: sent.time),
          ),
        _Pair(
          label: 'Assinada em',
          gold: gold,
          isLast: true,
          value: signed != null
              ? _DateValue(date: signed.date, time: signed.time)
              : Text('Registrada', style: _valueStyle(context)),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 18,
          runSpacing: 10,
          children: [
            _Register(
              label: 'Registro',
              gold: gold,
              child: Text(
                register,
                style: TextStyle(
                  color: ThemeHelpers.textColor(context),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            _Register(
              label: 'Validade',
              gold: gold,
              icon: LucideIcons.shield,
              text: 'Permanente',
            ),
            _Register(
              label: 'Acesso',
              gold: gold,
              icon: allowed ? LucideIcons.badgeCheck : LucideIcons.lock,
              text: allowed ? 'Liberado para você' : 'Restrito',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSeal(BuildContext context, Color gold, bool allowed) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final ink = pdkInk(context, gold);
    final checking = _needsTeam && _teamSees == null;

    final Widget action;
    if (allowed) {
      action = FilledButton(
        onPressed: _downloading ? null : _download,
        style: FilledButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: AppColors.text.text,
          disabledBackgroundColor: gold.withValues(alpha: 0.7),
          disabledForegroundColor: AppColors.text.text.withValues(alpha: 0.8),
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_downloading)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.text.text,
                ),
              )
            else
              const Icon(LucideIcons.download, size: 17),
            const SizedBox(width: 8),
            Flexible(
              child: PdkButtonLabel(
                _downloading ? 'Preparando…' : 'Baixar documento assinado',
              ),
            ),
          ],
        ),
      );
    } else {
      action = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton(
            onPressed: null,
            style: OutlinedButton.styleFrom(
              disabledForegroundColor: secondary,
              side: BorderSide(color: ThemeHelpers.borderColor(context)),
              minimumSize: const Size(0, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.lock,
                  size: 16,
                  color: pdkInk(context, PdkTone.violet(context)),
                ),
                const SizedBox(width: 8),
                const Flexible(child: PdkButtonLabel('Download restrito')),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            checking
                ? 'Conferindo se o imóvel é da sua equipe…'
                : 'Só o responsável, o captador, o gestor da equipe ou a '
                    'administração podem baixar.',
            textAlign: TextAlign.center,
            style: TextStyle(color: secondary, fontSize: 11.5, height: 1.35),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: _Medallion(gold: gold)),
        const SizedBox(height: 8),
        Center(
          child: Transform.rotate(
            angle: -0.07,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: ink, width: 1.4),
              ),
              child: Text(
                'ASSINADA',
                style: TextStyle(
                  color: ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.4,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: SizedBox(
            width: 150,
            height: 38,
            child: CustomPaint(
              painter: _SignaturePainter(color: ink.withValues(alpha: 0.85)),
            ),
          ),
        ),
        Center(
          child: Container(
            width: 170,
            height: 1,
            margin: const EdgeInsets.only(top: 2, bottom: 5),
            color: gold.withValues(alpha: 0.45),
          ),
        ),
        Text(
          'Assinatura eletrônica · Autentique',
          textAlign: TextAlign.center,
          style: TextStyle(color: secondary, fontSize: 11, height: 1.3),
        ),
        const SizedBox(height: 14),
        action,
      ],
    );
  }

  TextStyle _valueStyle(BuildContext context) => TextStyle(
        color: ThemeHelpers.textColor(context),
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        height: 1.35,
      );

  static String? _nonEmpty(String? v) {
    final t = v?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  static ({String date, String time})? _stamp(String? iso) {
    final raw = iso?.trim() ?? '';
    if (raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    final local = parsed.toLocal();
    return (
      date: DateFormat('dd/MM/yyyy').format(local),
      time: DateFormat('HH:mm').format(local),
    );
  }
}

/// Ouro da assinatura — a tinta reservada ao certificado (token amarelo do
/// app; texto e ícone passam por `pdkInk`).
Color _gold(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? AppColors.status.yellowDarkMode
        : AppColors.status.yellow;

/// Papel com moldura dupla (borda + linha interna) e quatro cantoneiras.
class _CertificatePaper extends StatelessWidget {
  const _CertificatePaper({required this.gold, required this.child});

  final Color gold;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: gold.withValues(alpha: isDark ? 0.5 : 0.6)),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      padding: const EdgeInsets.all(5),
      child: CustomPaint(
        foregroundPainter: _CornersPainter(color: gold),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: gold.withValues(alpha: 0.28)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: child,
        ),
      ),
    );
  }
}

class _CornersPainter extends CustomPainter {
  const _CornersPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const arm = 12.0;
    const inset = 3.0;
    final w = size.width;
    final h = size.height;
    final corners = <List<Offset>>[
      [const Offset(inset, inset + arm), const Offset(inset, inset),
        const Offset(inset + arm, inset)],
      [Offset(w - inset - arm, inset), Offset(w - inset, inset),
        Offset(w - inset, inset + arm)],
      [Offset(inset, h - inset - arm), Offset(inset, h - inset),
        Offset(inset + arm, h - inset)],
      [Offset(w - inset - arm, h - inset), Offset(w - inset, h - inset),
        Offset(w - inset, h - inset - arm)],
    ];
    for (final c in corners) {
      final path = Path()
        ..moveTo(c[0].dx, c[0].dy)
        ..lineTo(c[1].dx, c[1].dy)
        ..lineTo(c[2].dx, c[2].dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CornersPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Medalhão de ouro com anel tracejado e o selo verificado em branco.
class _Medallion extends StatelessWidget {
  const _Medallion({required this.gold});

  final Color gold;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      height: 78,
      child: CustomPaint(
        painter: _DashedRingPainter(color: pdkInk(context, gold)),
        child: Center(
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: pdkSolid(gold),
            ),
            child: const Icon(
              LucideIcons.badgeCheck,
              size: 30,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedRingPainter extends CustomPainter {
  const _DashedRingPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 1;
    const dashes = 36;
    const sweep = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * sweep,
        sweep * 0.55,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRingPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Floreio de assinatura — o mesmo traço do SVG do web (viewBox 132×34),
/// parado (sem animação).
class _SignaturePainter extends CustomPainter {
  const _SignaturePainter({required this.color});

  final Color color;

  static const List<List<double>> _curves = <List<double>>[
    [10, -14, 18, -16, 22, -10],
    [3, 5, -3, 12, -6, 10],
    [-4, -3, 6, -16, 16, -18],
    [8, -2, 6, 10, 2, 14],
    [-3, 3, 2, 6, 10, 0],
    [8, -6, 16, -10, 22, -8],
    [5, 2, 0, 10, -4, 10],
    [-5, 0, 3, -12, 12, -12],
    [8, 0, 8, 10, 14, 8],
    [8, -3, 18, -14, 36, -6],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 132;
    final sy = size.height / 34;
    final path = Path()..moveTo(4 * sx, 24 * sy);
    for (final c in _curves) {
      path.relativeCubicTo(
        c[0] * sx,
        c[1] * sy,
        c[2] * sx,
        c[3] * sy,
        c[4] * sx,
        c[5] * sy,
      );
    }
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Par rótulo/valor da ficha, separado por filete; em tela estreita (ou
/// fonte grande) o valor desce para baixo do rótulo.
class _Pair extends StatelessWidget {
  const _Pair({
    required this.label,
    required this.value,
    required this.gold,
    this.isLast = false,
  });

  final String label;
  final Widget value;
  final Color gold;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final labelText = Text(
      label.toUpperCase(),
      style: TextStyle(
        color: ThemeHelpers.textSecondaryColor(context),
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: gold.withValues(alpha: 0.22)),
          bottom: isLast
              ? BorderSide(color: gold.withValues(alpha: 0.22))
              : BorderSide.none,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = pdkTextScale(context);
          if (constraints.maxWidth < 300 * scale) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [labelText, const SizedBox(height: 3), value],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 104 * scale,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: labelText,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: value),
            ],
          );
        },
      ),
    );
  }
}

class _DateValue extends StatelessWidget {
  const _DateValue({required this.date, required this.time});

  final String date;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: date,
            style: TextStyle(
              color: ThemeHelpers.textColor(context),
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(
            text: '  às $time',
            style: TextStyle(
              color: ThemeHelpers.textSecondaryColor(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
    );
  }
}

class _CodeChip extends StatelessWidget {
  const _CodeChip({required this.code, required this.gold});

  final String code;
  final Color gold;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: gold.withValues(alpha: isDark ? 0.16 : 0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: gold.withValues(alpha: 0.4)),
      ),
      child: Text(
        code,
        style: TextStyle(
          color: pdkInk(context, gold),
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Bloco do rodapé do certificado (Registro / Validade / Acesso).
class _Register extends StatelessWidget {
  const _Register({
    required this.label,
    required this.gold,
    this.icon,
    this.text,
    this.child,
  });

  final String label;
  final Color gold;
  final IconData? icon;
  final String? text;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final ink = pdkInk(context, gold);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: ink,
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 3),
        child ??
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 13, color: ink),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    text ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ThemeHelpers.textColor(context),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
      ],
    );
  }
}
