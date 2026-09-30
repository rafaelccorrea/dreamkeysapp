import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/api_service.dart';
import '../../../../shared/services/property_service.dart';
import '../../../../shared/utils/broker_contact_actions.dart';
import '../../../../shared/utils/error_cause.dart';
import '../../../../shared/widgets/app_error_state.dart';
import '../../../../shared/widgets/skeleton_box.dart';
import '../../services/property_detail_extras_service.dart';
import 'property_details_kit.dart';

/// Qual vínculo a seção mostra.
enum PropertyLinkedEntityKind { condominium, empreendimento }

/// Motivo do cadeado de "Alterar vínculo" (permissão `property:update`).
const String kPropertyChangeLinkLockedReason =
    'Sem a permissão "Editar imóveis". Fale com o seu gestor ou com o '
    'suporte.';

/// Motivo de não mostrar os detalhes do condomínio/empreendimento (o web
/// libera a leitura com qualquer permissão do módulo de condomínios).
const String kPropertyLinkedEntityViewLockedReason =
    'Sem a permissão "Gestão de Condomínios - Visualizar". Fale com o seu '
    'gestor ou com o suporte.';

/// Corpo das seções "Condomínio" e "Empreendimento" da ficha — paridade com
/// o `PropertyDetailsCondominiumSection` e o
/// `PropertyDetailsEmpreendimentoSection` do web. Vai dentro do molde flush
/// da página (título "Condomínio" / "Empreendimento"); monte só quando
/// [isVisible].
///
/// Mostra o nome (toque copia), a pílula Ativo/Inativo, a descrição e as
/// linhas do cadastro: endereço completo, telefone (Ligar/WhatsApp), e-mail,
/// CNPJ, site (abre) e, no condomínio, a "Taxa informada no imóvel". Lê
/// sozinho `GET /condominiums/:id` / `GET /empreendimentos/:id` quando
/// [canView]; sem ela, o cadeado com o motivo no lugar dos detalhes.
///
/// "Ver cadastro" chama [onOpenRecord] com o id (sem ele, não aparece).
/// "Alterar vínculo" abre o seletor (busca, só ativos, "Carregar mais",
/// "Remover …") e grava `PATCH /properties/:id {condominiumId |
/// empreendimentoId}` (`null` desfaz); deu certo → aviso do web e
/// [onLinkChanged] (imóvel devolvido, ou `null` = recarregue a ficha). Sem
/// [canChangeLink], o atalho aparece travado com o motivo; [lockedReason]
/// trava pelo motivo dado (ex.: imóvel excluído).
///
/// Gates do web: [canView] = [canViewFor]; [canChangeLink] =
/// `property:update` (master/admin/gestor passam por papel — use
/// `PropertyDetailExtrasService.webHasPermission`).
class PropertyLinkedEntitySection extends StatefulWidget {
  const PropertyLinkedEntitySection.condominium({
    super.key,
    required this.property,
    required this.canView,
    required this.canChangeLink,
    this.onOpenRecord,
    this.onLinkChanged,
    this.lockedReason,
  }) : kind = PropertyLinkedEntityKind.condominium;

  const PropertyLinkedEntitySection.empreendimento({
    super.key,
    required this.property,
    required this.canView,
    required this.canChangeLink,
    this.onOpenRecord,
    this.onLinkChanged,
    this.lockedReason,
  }) : kind = PropertyLinkedEntityKind.empreendimento;

  final PropertyLinkedEntityKind kind;
  final Property property;
  final bool canView;
  final bool canChangeLink;
  final ValueChanged<String>? onOpenRecord;
  final ValueChanged<Property?>? onLinkChanged;
  final String? lockedReason;

  /// Id do vínculo no imóvel.
  static String linkedId(PropertyLinkedEntityKind kind, Property property) =>
      (kind == PropertyLinkedEntityKind.condominium
              ? property.condominiumId
              : property.empreendimentoId)
          ?.trim() ??
      '';

  /// Mesma condição do web: há vínculo e (pode ver, ou o detalhe trouxe o
  /// nome, ou pode alterar).
  static bool isVisible(
    PropertyLinkedEntityKind kind,
    Property property, {
    required bool canView,
    required bool canChangeLink,
  }) {
    if (linkedId(kind, property).isEmpty) return false;
    final name = (kind == PropertyLinkedEntityKind.condominium
                ? property.condominiumName
                : property.empreendimentoName)
            ?.trim() ??
        '';
    return canView || name.isNotEmpty || canChangeLink;
  }

  /// Gate de leitura do web, com a regra de papel do web: condomínio =
  /// `condominium:view`; empreendimento = qualquer de
  /// `condominium:view|create|update|delete` (o
  /// `canShowDrawerItem('condominium:view')` da seção do web).
  static bool canViewFor(
    PropertyLinkedEntityKind kind, {
    required String? role,
    required List<String> explicitPermissions,
  }) {
    final perms = kind == PropertyLinkedEntityKind.condominium
        ? const <String>['condominium:view']
        : const <String>[
            'condominium:view',
            'condominium:create',
            'condominium:update',
            'condominium:delete',
          ];
    return perms.any(
      (p) => PropertyDetailExtrasService.webHasPermission(
        role: role,
        explicitPermissions: explicitPermissions,
        permission: p,
      ),
    );
  }

  @override
  State<PropertyLinkedEntitySection> createState() =>
      _PropertyLinkedEntitySectionState();
}

class _Texts {
  const _Texts(this.kind);

  final PropertyLinkedEntityKind kind;

  bool get _condo => kind == PropertyLinkedEntityKind.condominium;

  String get label => _condo ? 'Condomínio' : 'Empreendimento';
  String get noun => _condo ? 'condomínio' : 'empreendimento';
  String get menu => _condo ? 'Condomínios' : 'Empreendimentos';
  String get fallbackName =>
      _condo ? 'Condomínio vinculado' : 'Empreendimento vinculado';
  String get copied => _condo
      ? 'Nome do condomínio copiado.'
      : 'Nome do empreendimento copiado.';
  String get noDetails => _condo
      ? 'Este imóvel está vinculado a um condomínio, mas não há detalhes '
          'disponíveis para exibição.'
      : 'Este imóvel está vinculado a um empreendimento, mas não há '
          'detalhes disponíveis para exibição.';
  String get updated => _condo
      ? 'Vínculo com condomínio atualizado'
      : 'Vínculo com empreendimento atualizado';
  String get search =>
      _condo ? 'Buscar condomínio...' : 'Buscar empreendimento...';
  String get notFound => _condo
      ? 'Nenhum condomínio encontrado'
      : 'Nenhum empreendimento encontrado';
  String get noneRegistered => _condo
      ? 'Nenhum condomínio cadastrado'
      : 'Nenhum empreendimento cadastrado';
  String get remove => _condo ? 'Remover condomínio' : 'Remover empreendimento';
  String get pickerTitle =>
      _condo ? 'Alterar condomínio' : 'Alterar empreendimento';
  String get placeholder => _condo
      ? 'Selecione um condomínio...'
      : 'Selecione um empreendimento...';
}

class _PropertyLinkedEntitySectionState
    extends State<PropertyLinkedEntitySection> {
  PropertyLinkedEntity? _entity;
  bool _loading = false;
  ApiResponse<PropertyLinkedEntity>? _failure;

  _Texts get _t => _Texts(widget.kind);

  String get _id =>
      PropertyLinkedEntitySection.linkedId(widget.kind, widget.property);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PropertyLinkedEntitySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldId = PropertyLinkedEntitySection.linkedId(
      oldWidget.kind,
      oldWidget.property,
    );
    if (oldId != _id || (widget.canView && !oldWidget.canView)) {
      _entity = null;
      _failure = null;
      _load();
    }
  }

  Future<void> _load() async {
    final id = _id;
    if (id.isEmpty || !widget.canView) return;
    setState(() {
      _loading = true;
      _failure = null;
    });
    final service = PropertyDetailExtrasService.instance;
    final res = widget.kind == PropertyLinkedEntityKind.condominium
        ? await service.getCondominium(id)
        : await service.getEmpreendimento(id);
    if (!mounted || _id != id) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _entity = res.data;
      } else {
        _failure = res;
      }
    });
  }

  String get _displayName {
    final fromEntity = _entity?.name.trim() ?? '';
    if (fromEntity.isNotEmpty) return fromEntity;
    final fromProperty = (widget.kind == PropertyLinkedEntityKind.condominium
                ? widget.property.condominiumName
                : widget.property.empreendimentoName)
            ?.trim() ??
        '';
    return fromProperty.isNotEmpty ? fromProperty : _t.fallbackName;
  }

  Future<void> _copyName() async {
    try {
      await Clipboard.setData(ClipboardData(text: _displayName));
      if (!mounted) return;
      pdkShowSnack(context, _t.copied, tone: PdkSnackTone.success);
    } catch (_) {
      if (!mounted) return;
      pdkShowSnack(
        context,
        'Não foi possível copiar o nome.',
        tone: PdkSnackTone.error,
      );
    }
  }

  Future<void> _changeLink() async {
    final outcome = PdkSheetOutcome();
    Property? updated;
    await showPdkSheet<void>(
      context: context,
      builder: (_) => _EntityPickerSheet(
        kind: widget.kind,
        propertyId: widget.property.id,
        currentId: _id,
        currentName: _displayName,
        outcome: outcome,
        onSaved: (p) => updated = p,
      ),
    );
    await outcome.settle();
    if (!mounted || !outcome.changed) return;
    pdkShowSnack(context, _t.updated, tone: PdkSnackTone.success);
    widget.onLinkChanged?.call(updated);
  }

  @override
  Widget build(BuildContext context) {
    final entity = _entity;
    final lockReason = widget.lockedReason?.trim() ?? '';
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final description = entity?.description?.trim() ?? '';
    final rows = _rowsOf(context, entity);
    final canChange = widget.canChangeLink && lockReason.isEmpty;

    final actions = <Widget>[
      if (widget.canView && widget.onOpenRecord != null)
        PdkNeutralButton(
          label: 'Ver cadastro',
          icon: LucideIcons.eye,
          onPressed: () => widget.onOpenRecord!(_id),
        ),
      if (canChange)
        PdkNeutralButton(
          label: 'Alterar vínculo',
          icon: LucideIcons.pencil,
          onPressed: _changeLink,
        ),
    ];

    final Widget details;
    if (!widget.canView) {
      details = _LockLine(
        text: 'Detalhes travados. $kPropertyLinkedEntityViewLockedReason',
      );
    } else if (_loading && entity == null) {
      details = const _RowsSkeleton();
    } else if (entity == null && _failure != null) {
      final f = _failure!;
      details = AppErrorState.fromApi(
        message: f.message,
        statusCode: f.statusCode,
        error: f.error,
        onRetry: _load,
        dense: true,
      );
    } else if (rows.isEmpty) {
      details = Text(
        _t.noDetails,
        style: TextStyle(color: secondary, fontSize: 12.5, height: 1.45),
      );
    } else {
      final divider = ThemeHelpers.borderLightColor(context);
      details = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Container(height: 1, color: divider),
            rows[i],
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _NameChip(
              label: _t.label,
              name: _displayName,
              onTap: _copyName,
            ),
            if (entity?.isActive != null)
              _ActivePill(active: entity!.isActive!),
          ],
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 12),
          if (actions.length == 2)
            PdkActionPair(
              primary: actions[1],
              secondary: actions[0],
              minPrimary: 150,
              minSecondary: 120,
            )
          else
            Align(alignment: Alignment.centerLeft, child: actions.first),
        ],
        if (!canChange) ...[
          const SizedBox(height: 10),
          _LockLine(
            text: lockReason.isNotEmpty
                ? 'Alterar vínculo: $lockReason'
                : 'Alterar vínculo: $kPropertyChangeLinkLockedReason',
          ),
        ],
        if (description.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            description,
            style: TextStyle(
              color: ThemeHelpers.textColor(context),
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
        ],
        const SizedBox(height: 10),
        details,
      ],
    );
  }

  /// Linhas na ordem do web; só entra o que estiver preenchido.
  List<Widget> _rowsOf(BuildContext context, PropertyLinkedEntity? e) {
    final rows = <Widget>[];
    final address = e?.fullAddress.trim() ?? '';
    if (address.isNotEmpty) {
      rows.add(_InfoRow(
        icon: LucideIcons.mapPin,
        label: 'Endereço',
        value: address,
        maxLines: 4,
      ));
    }
    final phone = e?.phone?.trim() ?? '';
    if (phone.isNotEmpty) {
      final digits = BrokerContactActions.digitsOnly(phone);
      rows.add(_InfoRow(
        icon: LucideIcons.phone,
        label: 'Telefone',
        value: _formatPhone(phone),
        tabular: true,
        actions: digits.length >= 10
            ? [
                PdkIconAction(
                  icon: LucideIcons.phone,
                  tooltip: 'Ligar',
                  tone: PdkTone.blue(context),
                  onTap: () => BrokerContactActions.callPhone(context, phone),
                ),
                PdkIconAction(
                  icon: LucideIcons.messageCircle,
                  tooltip: 'WhatsApp',
                  tone: PdkTone.green(context),
                  onTap: () =>
                      BrokerContactActions.openWhatsApp(context, phone),
                ),
              ]
            : const <Widget>[],
      ));
    }
    final email = e?.email?.trim() ?? '';
    if (email.isNotEmpty) {
      rows.add(_InfoRow(
        icon: LucideIcons.mail,
        label: 'E-mail',
        value: email,
        actions: [
          PdkIconAction(
            icon: LucideIcons.mail,
            tooltip: 'Escrever',
            tone: PdkTone.blue(context),
            onTap: () => pdkOpenEmail(context, email),
          ),
        ],
      ));
    }
    final cnpj = e?.cnpj?.trim() ?? '';
    if (cnpj.isNotEmpty) {
      rows.add(_InfoRow(
        icon: LucideIcons.receipt,
        label: 'CNPJ',
        value: _formatCnpj(cnpj),
        tabular: true,
      ));
    }
    final website = e?.website?.trim() ?? '';
    if (website.isNotEmpty) {
      final url = RegExp(r'^https?://', caseSensitive: false).hasMatch(website)
          ? website
          : 'https://$website';
      rows.add(_InfoRow(
        icon: LucideIcons.globe,
        label: 'Site',
        value: website,
        actions: [
          PdkIconAction(
            icon: LucideIcons.externalLink,
            tooltip: 'Abrir o site',
            tone: PdkTone.blue(context),
            onTap: () => _openUrl(context, url),
          ),
        ],
      ));
    }
    final fee = widget.property.condominiumFee ?? 0;
    if (widget.kind == PropertyLinkedEntityKind.condominium && fee > 0) {
      rows.add(_InfoRow(
        icon: LucideIcons.banknote,
        label: 'Taxa informada no imóvel',
        value: NumberFormat.currency(
          locale: 'pt_BR',
          symbol: r'R$',
          decimalDigits: 2,
        ).format(fee),
        tabular: true,
      ));
    }
    return rows;
  }

  static Future<void> _openUrl(BuildContext context, String url) async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      pdkShowSnack(
        context,
        'Não foi possível abrir o site no navegador.',
        tone: PdkSnackTone.error,
      );
    }
  }

  /// `formatPhoneBR` do web: 11 dígitos (xx) xxxxx-xxxx, 10 dígitos (xx)
  /// xxxx-xxxx; o resto como veio.
  static String _formatPhone(String phone) {
    final d = phone.replaceAll(RegExp(r'\D'), '');
    if (d.length == 11) {
      return '(${d.substring(0, 2)}) ${d.substring(2, 7)}-${d.substring(7)}';
    }
    if (d.length == 10) {
      return '(${d.substring(0, 2)}) ${d.substring(2, 6)}-${d.substring(6)}';
    }
    return phone.trim();
  }

  /// `formatCnpj` do web: 14 dígitos → 00.000.000/0000-00.
  static String _formatCnpj(String cnpj) {
    final d = cnpj.replaceAll(RegExp(r'\D'), '');
    if (d.length != 14) return cnpj.trim();
    return '${d.substring(0, 2)}.${d.substring(2, 5)}.${d.substring(5, 8)}/'
        '${d.substring(8, 12)}-${d.substring(12)}';
  }
}

/// Nome do vínculo em chip ("CONDOMÍNIO  Residencial X" + copiar).
class _NameChip extends StatelessWidget {
  const _NameChip({
    required this.label,
    required this.name,
    required this.onTap,
  });

  final String label;
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(color: ThemeHelpers.borderLightColor(context)),
    );
    return Tooltip(
      message: 'Copiar nome',
      child: Material(
        color: Colors.transparent,
        shape: shape,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      color: secondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ThemeHelpers.textColor(context),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(LucideIcons.copy, size: 13, color: secondary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivePill extends StatelessWidget {
  const _ActivePill({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone = active ? PdkTone.green(context) : PdkTone.red(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.32)),
      ),
      child: Text(
        active ? 'ATIVO' : 'INATIVO',
        style: TextStyle(
          color: pdkInk(context, tone),
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Cadeado + motivo numa linha (não esconde: diz por que não dá).
class _LockLine extends StatelessWidget {
  const _LockLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            LucideIcons.lock,
            size: 14,
            color: pdkInk(context, PdkTone.violet(context)),
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: ThemeHelpers.textSecondaryColor(context),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

/// Linha flush do cadastro: selo com o ícone, rótulo + valor e as ações no
/// próprio item (à direita; descem quando não cabem).
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.maxLines = 2,
    this.tabular = false,
    this.actions = const <Widget>[],
  });

  final IconData icon;
  final String label;
  final String value;
  final int maxLines;
  final bool tabular;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: secondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: ThemeHelpers.textColor(context),
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            height: 1.35,
            fontFeatures:
                tabular ? const [FontFeature.tabularFigures()] : null,
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = pdkTextScale(context);
          final actionsWidth = actions.isEmpty
              ? 0.0
              : actions.length * 40.0 + (actions.length - 1) * 6 + 10;
          final inline = actions.isEmpty ||
              constraints.maxWidth - 48 - actionsWidth >= 140 * scale;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.background.backgroundTertiaryDarkMode
                      : AppColors.background.backgroundTertiary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: secondary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: inline
                    ? info
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          info,
                          const SizedBox(height: 8),
                          Wrap(spacing: 6, runSpacing: 6, children: actions),
                        ],
                      ),
              ),
              if (inline && actions.isNotEmpty) ...[
                const SizedBox(width: 10),
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  actions[i],
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _RowsSkeleton extends StatelessWidget {
  const _RowsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                const SkeletonBox(width: 36, height: 36, borderRadius: 10),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FractionallySizedBox(
                        widthFactor: 0.3,
                        child: SkeletonBox(height: 10, borderRadius: 4),
                      ),
                      const SizedBox(height: 6),
                      FractionallySizedBox(
                        widthFactor: i == 0 ? 0.85 : 0.55,
                        child: const SkeletonBox(height: 13, borderRadius: 6),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─── Seletor "Alterar vínculo" ──────────────────────────────────────────────

class _EntityPickerSheet extends StatefulWidget {
  const _EntityPickerSheet({
    required this.kind,
    required this.propertyId,
    required this.currentId,
    required this.currentName,
    required this.outcome,
    required this.onSaved,
  });

  final PropertyLinkedEntityKind kind;
  final String propertyId;
  final String currentId;
  final String currentName;
  final PdkSheetOutcome outcome;
  final ValueChanged<Property?> onSaved;

  @override
  State<_EntityPickerSheet> createState() => _EntityPickerSheetState();
}

class _EntityPickerSheetState extends State<_EntityPickerSheet> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;

  /// Escolha atual: id, ou vazio = sem vínculo ("Remover …").
  late String _selected = widget.currentId;

  List<PropertyLinkedEntity> _items = const <PropertyLinkedEntity>[];
  int _page = 0;
  int _totalPages = 1;
  int _total = 0;
  bool _loading = false;
  bool _loadingMore = false;
  ApiResponse<PropertyLinkedEntityPage>? _failure;
  int _request = 0;

  bool _saving = false;
  ErrorCause? _saveError;

  _Texts get _t => _Texts(widget.kind);

  @override
  void initState() {
    super.initState();
    _fetch(1);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _fetch(1));
  }

  Future<void> _fetch(int page) async {
    final request = ++_request;
    final append = page > 1;
    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        _loading = true;
        _failure = null;
      }
    });
    final service = PropertyDetailExtrasService.instance;
    final search = _search.text;
    final res = widget.kind == PropertyLinkedEntityKind.condominium
        ? await service.listCondominiums(page: page, search: search)
        : await service.listEmpreendimentos(page: page, search: search);
    if (!mounted || request != _request) return;
    final data = res.data;
    setState(() {
      _loading = false;
      _loadingMore = false;
      if (!res.success || data == null) {
        if (!append) {
          _items = const <PropertyLinkedEntity>[];
          _failure = res;
        } else {
          pdkShowSnack(
            context,
            'Não foi possível carregar mais. ${pdkFailureCause(res).cause}',
            tone: PdkSnackTone.error,
          );
        }
        return;
      }
      if (append) {
        final seen = _items.map((e) => e.id).toSet();
        _items = [
          ..._items,
          ...data.items.where((e) => !seen.contains(e.id)),
        ];
      } else {
        _items = data.items;
      }
      _page = data.page;
      _totalPages = data.totalPages;
      _total = data.total;
    });
  }

  void _save() {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    widget.outcome.inFlight = _send();
  }

  Future<void> _send() async {
    final service = PropertyDetailExtrasService.instance;
    final id = _selected.trim().isEmpty ? null : _selected.trim();
    final res = widget.kind == PropertyLinkedEntityKind.condominium
        ? await service.linkCondominium(widget.propertyId, id)
        : await service.linkEmpreendimento(widget.propertyId, id);
    if (pdkApplied(res)) {
      widget.outcome.changed = true;
      widget.onSaved(res.data);
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saveError = pdkFailureCause(res);
    });
  }

  @override
  Widget build(BuildContext context) {
    final changed = _selected != widget.currentId;
    final blue = PdkTone.blue(context);
    return PdkSheetFrame(
      icon: widget.kind == PropertyLinkedEntityKind.condominium
          ? LucideIcons.building2
          : LucideIcons.building,
      tone: blue,
      title: _t.pickerTitle,
      subtitle: widget.currentId.isEmpty
          ? _t.placeholder
          : 'Hoje: ${widget.currentName}',
      onClose: _saving ? null : () => Navigator.of(context).maybePop(),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              enabled: !_saving,
              decoration: pdkFieldDecoration(
                context,
                label: _t.search.replaceAll('...', ''),
                hint: _t.search,
                accent: blue,
              ).copyWith(
                prefixIcon: const Icon(LucideIcons.search, size: 18),
              ),
            ),
            const SizedBox(height: 12),
            if (widget.currentId.isNotEmpty) ...[
              PdkChoiceRow(
                icon: LucideIcons.unlink,
                tone: PdkTone.red(context),
                title: _t.remove,
                description: 'O imóvel fica sem vínculo com ${_t.noun}.',
                selected: _selected.isEmpty,
                onTap: _saving ? null : () => setState(() => _selected = ''),
              ),
              const SizedBox(height: 8),
            ],
            ..._buildList(context),
            if (_saveError != null) ...[
              const SizedBox(height: 12),
              PdkErrorNote(
                title: 'Erro ao atualizar vínculo',
                cause: _saveError!,
              ),
            ],
          ],
        ),
      ),
      footer: PdkActionPair(
        primary: PdkSolidButton(
          label: _saving ? 'Salvando…' : 'Salvar',
          tone: PdkTone.green(context),
          icon: LucideIcons.check,
          busy: _saving,
          onPressed: changed ? _save : null,
        ),
        secondary: PdkNeutralButton(
          label: 'Cancelar',
          onPressed: _saving ? null : () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }

  List<Widget> _buildList(BuildContext context) {
    if (_loading && _items.isEmpty) {
      return const [_RowsSkeleton()];
    }
    final failure = _failure;
    if (failure != null && _items.isEmpty) {
      return [
        AppErrorState.fromApi(
          message: failure.message,
          statusCode: failure.statusCode,
          error: failure.error,
          onRetry: () => _fetch(1),
          dense: true,
        ),
      ];
    }
    if (_items.isEmpty) {
      return [
        PdkNote(
          icon: LucideIcons.searchX,
          tone: PdkTone.blue(context),
          text: _search.text.trim().isNotEmpty
              ? '${_t.notFound}. Confira o nome buscado.'
              : '${_t.noneRegistered}. O cadastro é feito no menu '
                  '${_t.menu}.',
        ),
      ];
    }
    final hasMore = _page > 0 && _page < _totalPages;
    return [
      for (final item in _items) ...[
        PdkChoiceRow(
          icon: widget.kind == PropertyLinkedEntityKind.condominium
              ? LucideIcons.building2
              : LucideIcons.building,
          tone: PdkTone.blue(context),
          title: item.name.isEmpty ? _t.fallbackName : item.name,
          description: item.pickerAddressLine.isEmpty
              ? null
              : item.pickerAddressLine,
          badge: item.id == widget.currentId ? 'Atual' : null,
          selected: _selected == item.id,
          onTap: _saving ? null : () => setState(() => _selected = item.id),
        ),
        const SizedBox(height: 8),
      ],
      if (hasMore)
        Align(
          alignment: Alignment.center,
          child: PdkNeutralButton(
            label: _loadingMore
                ? 'Carregando…'
                : 'Carregar mais (${_items.length} de $_total)',
            icon: LucideIcons.chevronDown,
            onPressed: _loadingMore || _saving ? null : () => _fetch(_page + 1),
          ),
        ),
    ];
  }
}
