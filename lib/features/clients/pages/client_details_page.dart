import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/feature_visibility.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/module_access_service.dart';
import '../../../shared/utils/broker_contact_actions.dart';
import '../../../shared/utils/masks.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../../matches/widgets/matches_badge.dart';
import '../models/client_model.dart';
import '../services/client_service.dart';
import '../utils/client_phone_rules.dart';
import '../widgets/client_interactions_panel.dart';
import '../widgets/transfer_client_modal.dart';

/// Verde do WhatsApp — cor de identidade da marca, sem equivalente em
/// `AppColors` (mesmo par da lista de clientes e do Kanban).
const Color _kWhatsappGreen = Color(0xFF25D366);
const Color _kWhatsappGreenDeep = Color(0xFF128C7E);

/// Página de detalhes do cliente.
///
/// Responde, de cima para baixo: quem é (nome, situação, tipo, origem),
/// quem cuida dele e desde quando, como falar com ele agora (WhatsApp,
/// ligar, e-mail), o que falta no cadastro, o que ele procura, o histórico
/// de contatos e, por fim, os dados completos em seções flush.
class ClientDetailsPage extends StatefulWidget {
  final String clientId;

  const ClientDetailsPage({super.key, required this.clientId});

  @override
  State<ClientDetailsPage> createState() => _ClientDetailsPageState();
}

class _ClientDetailsPageState extends State<ClientDetailsPage> {
  final ClientService _clientService = ClientService.instance;
  Client? _client;
  bool _isLoading = true;
  String? _errorMessage;
  // O código HTTP viaja junto: é ele que separa "sem permissão" de "fora do ar".
  int _errorStatus = 0;
  Object? _errorRaw;

  static final NumberFormat _currency =
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 2);

  /// Largura máxima do conteúdo em tablet/tela larga.
  static const double _kMaxContentWidth = 720;

  @override
  void initState() {
    super.initState();
    _loadClient();
  }

  Color _accentColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;
  }

  Future<void> _loadClient() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _errorStatus = 0;
      _errorRaw = null;
    });

    try {
      final response = await _clientService.getClientById(widget.clientId);
      if (!mounted) return;

      if (response.success && response.data != null) {
        setState(() {
          _client = response.data;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = response.message ?? 'Erro ao carregar cliente';
          _errorStatus = response.statusCode;
          _errorRaw = response.error;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Erro ao conectar com o servidor';
        _errorStatus = 0;
        _errorRaw = e;
        _isLoading = false;
      });
    }
  }

  bool _can(String permission) =>
      ModuleAccessService.instance.hasPermission(permission);

  /// Regra da casa: sem permissão a ação fica travada e o toque explica.
  bool _guard(String permission) {
    if (_can(permission)) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Você não tem permissão para esta ação. Fale com um administrador.',
        ),
        backgroundColor: AppColors.status.warning,
      ),
    );
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Cliente',
      actions: _client == null ? null : [_buildMenu(context)],
      // Recarregar (puxar ou voltar da edição) mantém a ficha na tela; o
      // esqueleto só aparece enquanto ainda não há cliente nenhum.
      body: _isLoading && _client == null
          ? _buildSkeleton(context)
          : _client == null
              ? _buildErrorState(context)
              : RefreshIndicator(
                  onRefresh: _loadClient,
                  color: AppColors.primary.primary,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    padding: const EdgeInsets.only(top: 8, bottom: 32),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints:
                            const BoxConstraints(maxWidth: _kMaxContentWidth),
                        child: _buildContent(context),
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final c = _client!;
    final missing = _missingEssentials(c);
    final notes = (c.notes ?? '').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildIdentity(context),
        const SizedBox(height: 18),
        _buildFacts(context),
        const SizedBox(height: 18),
        _buildContactActions(context, missing),
        if (notes.isNotEmpty) ...[
          _sectionGap(context),
          _buildNotesSection(context, notes),
        ],
        if (_hasPreferences()) ...[
          _sectionGap(context),
          _buildPreferencesSection(context),
        ],
        _sectionGap(context),
        // Histórico de contatos (ligações, visitas, propostas) e o
        // registro de um novo — o próximo passo depois de falar com ele.
        // A chave acompanha o cliente carregado: cada recarga (puxar ou
        // voltar da edição) remonta o painel e relê as interações, como
        // acontecia quando a ficha inteira virava esqueleto.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClientInteractionsPanel(key: ObjectKey(c), clientId: c.id),
        ),
        _sectionGap(context),
        _buildBasicInfoSection(context),
        if (_hasAddress()) ...[
          _sectionGap(context),
          _buildAddressSection(context),
        ],
        if (_hasProfessionalInfo()) ...[
          _sectionGap(context),
          _buildProfessionalSection(context),
        ],
        if (_hasFinancialInfo()) ...[
          _sectionGap(context),
          _buildFinancialSection(context),
        ],
        if (c.spouse != null) ...[
          _sectionGap(context),
          _buildSpouseSection(context),
        ],
      ],
    );
  }

  // ───────────────────── Menu do topo ─────────────────────

  Widget _buildMenu(BuildContext context) {
    final pm = AppTheme.styledPopupMenuOf(context);
    return PopupMenuButton<String>(
      tooltip: 'Mais opções',
      icon: Icon(
        Icons.more_vert,
        color: ThemeHelpers.textColor(context).withValues(alpha: 0.88),
      ),
      color: pm.color,
      surfaceTintColor: pm.surfaceTintColor,
      elevation: pm.elevation,
      shadowColor: pm.shadowColor,
      shape: pm.shape,
      position: PopupMenuPosition.under,
      onSelected: (value) async {
        switch (value) {
          case 'edit':
            await Navigator.pushNamed(
              context,
              AppRoutes.clientEdit(_client!.id),
            );
            _loadClient();
            break;
          case 'matches':
            Navigator.pushNamed(
              context,
              AppRoutes.matchesByClient(_client!.id),
            );
            break;
          case 'transfer':
            _showTransferModal();
            break;
          case 'delete':
            _deleteClient();
            break;
        }
      },
      itemBuilder: (_) => [
        _lockableMenuItem(
          value: 'edit',
          icon: Icons.edit_outlined,
          label: 'Editar',
          permission: 'client:update',
        ),
        // Matches oculto no app: item fora do menu.
        if (FeatureVisibility.matchesEnabled)
          const PopupMenuItem(
            value: 'matches',
            child: Row(children: [
              Icon(Icons.handshake_outlined, size: 18),
              SizedBox(width: 10),
              Flexible(child: Text('Ver matches')),
            ]),
          ),
        _lockableMenuItem(
          value: 'transfer',
          icon: Icons.swap_horiz_rounded,
          label: 'Transferir',
          permission: 'client:transfer',
        ),
        const PopupMenuDivider(),
        _lockableMenuItem(
          value: 'delete',
          icon: Icons.delete_outline,
          label: 'Excluir',
          permission: 'client:delete',
          destructive: true,
        ),
      ],
    );
  }

  /// Mesmas permissões do web (`client:update`, `client:transfer`,
  /// `client:delete`); sem ela o item fica travado com cadeado.
  PopupMenuItem<String> _lockableMenuItem({
    required String value,
    required IconData icon,
    required String label,
    required String permission,
    bool destructive = false,
  }) {
    final allowed = ModuleAccessService.instance.hasPermission(permission);
    final color = !allowed
        ? ThemeHelpers.textSecondaryColor(context).withValues(alpha: 0.6)
        : (destructive ? AppColors.status.error : null);
    return PopupMenuItem<String>(
      value: value,
      enabled: allowed,
      child: Row(children: [
        Icon(
          allowed ? icon : Icons.lock_outline_rounded,
          size: 18,
          color: color,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color),
          ),
        ),
      ]),
    );
  }

  // ───────────────────── Quem é ─────────────────────

  Widget _buildIdentity(BuildContext context) {
    final c = _client!;
    final theme = Theme.of(context);

    // Matches oculto no app: o nome fica sem o badge (o wrapper só
    // volta com o flag — permissões/módulo seguem no widget).
    final nameText = Text(
      c.name.trim().isEmpty ? 'Cliente sem nome' : c.name,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w900,
        fontSize: 21,
        height: 1.15,
        letterSpacing: -0.4,
        color: ThemeHelpers.textColor(context),
      ),
    );
    final Widget name = FeatureVisibility.matchesEnabled
        ? MatchesBadge(
            clientId: c.id,
            onClick: () => Navigator.pushNamed(
              context,
              AppRoutes.matchesByClient(c.id),
            ),
            child: nameText,
          )
        : nameText;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InitialsAvatar(initials: _initials(c.name)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: name,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _StatusPill(
                      label: c.status.label,
                      tone: _statusTone(context, c.status),
                    ),
                    _OutlineTag(icon: _typeIcon(c.type), label: c.type.label),
                    if (!c.isActive)
                      const _OutlineTag(
                        icon: Icons.block_rounded,
                        label: 'Cadastro desativado',
                      ),
                    if (c.leadSource != null)
                      _OutlineTag(
                        icon: Icons.campaign_outlined,
                        label: 'Origem: ${c.leadSource!.label}',
                      ),
                    if (c.spouse != null)
                      const _OutlineTag(
                        icon: Icons.favorite_outline,
                        label: 'Com cônjuge',
                      ),
                    if (c.mcmvInterested == true)
                      const _OutlineTag(
                        icon: Icons.home_outlined,
                        label: 'Interesse no MCMV',
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Quem cuida do cliente e há quanto tempo ele está na carteira.
  Widget _buildFacts(BuildContext context) {
    final c = _client!;
    final responsible = c.responsibleUser?.name.trim() ?? '';
    final captor = c.capturedBy?.name.trim() ?? '';
    final since = _formatDateOrNull(c.createdAt);
    final updated = _relativeDay(
      c.updatedAt.trim().isNotEmpty ? c.updatedAt : c.createdAt,
    );

    final facts = <_InfoItem>[
      if (responsible.isNotEmpty)
        _InfoItem(Icons.support_agent, 'Atendido por', responsible),
      if (captor.isNotEmpty && c.capturedById != c.responsibleUserId)
        _InfoItem(Icons.person_pin_circle_outlined, 'Captado por', captor),
      if (since != null) _InfoItem(Icons.event_outlined, 'Cliente desde', since),
      if (updated != null)
        _InfoItem(Icons.update_rounded, 'Atualizado', updated),
    ];
    if (facts.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _InfoGrid(items: facts, columnsWide: 4),
    );
  }

  // ───────────────────── Falar com ele agora ─────────────────────

  /// Os três canais sempre no mesmo lugar: o que não tem cadastro aparece
  /// apagado e diz o que falta. Abaixo, o próximo passo do cadastro.
  Widget _buildContactActions(BuildContext context, List<String> missing) {
    final c = _client!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final whatsapp = (c.whatsapp ?? '').trim();
    final phone = c.phone.trim();
    final email = c.email.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ChannelButton(
                  icon: Icons.chat_outlined,
                  label: 'WhatsApp',
                  missingLabel: 'Sem WhatsApp',
                  tone: isDark ? _kWhatsappGreen : _kWhatsappGreenDeep,
                  onTap: whatsapp.isEmpty
                      ? null
                      : () => _launchUri(
                            'https://wa.me/${BrokerContactActions.whatsappDigits(whatsapp)}',
                          ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ChannelButton(
                  icon: Icons.call_rounded,
                  label: 'Ligar',
                  missingLabel: 'Sem telefone',
                  tone: isDark
                      ? AppColors.status.infoDarkMode
                      : AppColors.message.infoText,
                  onTap: phone.isEmpty
                      ? null
                      : () => _launchUri('tel:${_onlyDigits(phone)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ChannelButton(
                  icon: Icons.mail_outline_rounded,
                  label: 'E-mail',
                  missingLabel: 'Sem e-mail',
                  tone: ThemeHelpers.textColor(context),
                  onTap: email.isEmpty
                      ? null
                      : () => _launchUri('mailto:$email'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (missing.isNotEmpty) ...[
            _buildCompletenessHint(context, missing),
            const SizedBox(height: 8),
          ],
          _buildEditButton(
            context,
            label: missing.isNotEmpty ? 'Completar cadastro' : 'Editar cadastro',
          ),
        ],
      ),
    );
  }

  /// "Cadastro incompleto — faltam CPF e endereço": o próximo passo do
  /// cadastro, dito em palavras (o botão logo abaixo leva à edição).
  Widget _buildCompletenessHint(BuildContext context, List<String> missing) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tone =
        isDark ? AppColors.status.warningDarkMode : AppColors.status.warning;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.12 : 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: isDark ? 0.40 : 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.playlist_add_check_rounded, size: 20, color: tone),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Cadastro incompleto',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Falta${missing.length == 1 ? '' : 'm'}: ${_joinPt(missing)}.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditButton(BuildContext context, {required String label}) {
    final canEdit = _can('client:update');
    final muted = ThemeHelpers.textSecondaryColor(context);
    return OutlinedButton.icon(
      onPressed: _openEdit,
      icon: Icon(
        canEdit ? Icons.edit_outlined : Icons.lock_outline_rounded,
        size: 18,
        color: canEdit ? _accentColor(context) : muted,
      ),
      label: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor:
            canEdit ? ThemeHelpers.textColor(context) : muted,
        side: BorderSide(color: ThemeHelpers.borderColor(context)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
      ),
    );
  }

  Future<void> _openEdit() async {
    final c = _client;
    if (c == null || !_guard('client:update')) return;
    await Navigator.pushNamed(context, AppRoutes.clientEdit(c.id));
    if (!mounted) return;
    _loadClient();
  }

  /// O que falta para o cadastro servir a uma ficha: telefone, e-mail, CPF
  /// e endereço (só leitura dos campos — nenhuma regra nova de validação).
  List<String> _missingEssentials(Client c) {
    final hasAnyPhone = c.phone.trim().isNotEmpty ||
        (c.whatsapp ?? '').trim().isNotEmpty ||
        (c.secondaryPhone ?? '').trim().isNotEmpty;
    return [
      if (!hasAnyPhone) 'telefone',
      if (c.email.trim().isEmpty) 'e-mail',
      if (c.cpf.trim().isEmpty) 'CPF',
      if (c.address.trim().isEmpty || c.city.trim().isEmpty) 'endereço',
    ];
  }

  String _joinPt(List<String> items) {
    if (items.length <= 1) return items.join();
    return '${items.sublist(0, items.length - 1).join(', ')} e ${items.last}';
  }

  // ───────────────────── Seções ─────────────────────

  Widget _sectionGap(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Divider(
        height: 1,
        thickness: 1,
        color: ThemeHelpers.borderColor(context).withValues(alpha: 0.7),
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Widget child,
    String? hint,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 19, color: _accentColor(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    fontSize: 15.5,
                    letterSpacing: -0.2,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
              ),
              if (hint != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildNotesSection(BuildContext context, String notes) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return _section(
      context,
      icon: Icons.sticky_note_2_outlined,
      title: 'Observações',
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.background.backgroundSecondaryDarkMode
              : AppColors.background.backgroundSecondary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ThemeHelpers.borderLightColor(context)),
        ),
        child: Text(
          notes,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: ThemeHelpers.textColor(context),
            height: 1.45,
          ),
        ),
      ),
    );
  }

  bool _hasPreferences() {
    final c = _client!;
    return (c.preferredPropertyType ?? '').isNotEmpty ||
        (c.preferredCity ?? '').isNotEmpty ||
        (c.preferredNeighborhood ?? '').isNotEmpty ||
        c.minValue != null ||
        c.maxValue != null ||
        c.minBedrooms != null ||
        c.maxBedrooms != null ||
        (c.minArea != null && c.maxArea != null);
  }

  /// O que o cliente procura — a faixa de preço vem em destaque, é o número
  /// que decide a conversa.
  Widget _buildPreferencesSection(BuildContext context) {
    final c = _client!;
    final theme = Theme.of(context);

    String? priceRange;
    String priceLabel = 'Faixa de preço';
    if (c.minValue != null && c.maxValue != null) {
      priceRange =
          '${_currency.format(c.minValue)} a ${_currency.format(c.maxValue)}';
    } else if (c.minValue != null) {
      priceLabel = 'Valor mínimo';
      priceRange = 'A partir de ${_currency.format(c.minValue)}';
    } else if (c.maxValue != null) {
      priceLabel = 'Valor máximo';
      priceRange = 'Até ${_currency.format(c.maxValue)}';
    }

    final items = <_InfoItem>[
      if ((c.preferredPropertyType ?? '').isNotEmpty)
        _InfoItem(
          Icons.home_outlined,
          'Tipo de imóvel',
          c.preferredPropertyType!,
        ),
      if ((c.preferredCity ?? '').isNotEmpty)
        _InfoItem(
          Icons.location_city_outlined,
          'Cidade',
          c.preferredCity!,
        ),
      if ((c.preferredNeighborhood ?? '').isNotEmpty)
        _InfoItem(
          Icons.place_outlined,
          'Bairro',
          c.preferredNeighborhood!,
        ),
      if (c.minBedrooms != null && c.maxBedrooms != null)
        _InfoItem(
          Icons.bed_outlined,
          'Quartos',
          '${c.minBedrooms} a ${c.maxBedrooms}',
        ),
      if (c.minArea != null && c.maxArea != null)
        _InfoItem(
          Icons.square_foot_outlined,
          'Área',
          '${c.minArea!.toStringAsFixed(0)} a ${c.maxArea!.toStringAsFixed(0)} m²',
        ),
    ];

    return _section(
      context,
      icon: Icons.manage_search_rounded,
      title: 'O que procura',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (priceRange != null) ...[
            Text(
              priceLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 11,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                priceRange,
                maxLines: 1,
                softWrap: false,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  letterSpacing: -0.4,
                  color: ThemeHelpers.textColor(context),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            if (items.isNotEmpty) const SizedBox(height: 14),
          ],
          if (items.isNotEmpty) _InfoGrid(items: items),
        ],
      ),
    );
  }

  Widget _buildBasicInfoSection(BuildContext context) {
    final c = _client!;
    final items = <_InfoItem>[
      if (c.phone.isNotEmpty)
        _InfoItem(
          Icons.phone_outlined,
          'Telefone',
          ClientPhoneRules.maskAuto(c.phone),
        ),
      if ((c.whatsapp ?? '').isNotEmpty)
        _InfoItem(
          Icons.chat_outlined,
          'WhatsApp',
          ClientPhoneRules.maskAuto(c.whatsapp),
        ),
      if ((c.secondaryPhone ?? '').isNotEmpty)
        _InfoItem(
          Icons.phone_outlined,
          'Telefone secundário',
          ClientPhoneRules.maskAuto(c.secondaryPhone),
        ),
      if (c.email.isNotEmpty)
        _InfoItem(
          Icons.alternate_email_rounded,
          'E-mail',
          c.email,
          wide: true,
        ),
      if (c.cpf.isNotEmpty)
        _InfoItem(Icons.fingerprint_rounded, 'CPF', _formatCpf(c.cpf)),
      if ((c.rg ?? '').isNotEmpty)
        _InfoItem(Icons.credit_card_outlined, 'RG', c.rg!),
      if ((c.birthDate ?? '').isNotEmpty)
        _InfoItem(
          Icons.cake_outlined,
          'Nascimento',
          _formatDate(c.birthDate),
        ),
      if (c.maritalStatus != null)
        _InfoItem(
          Icons.favorite_outline,
          'Estado civil',
          c.maritalStatus!.label,
        ),
      if (c.hasDependents == true)
        _InfoItem(
          Icons.family_restroom_outlined,
          'Dependentes',
          (c.numberOfDependents ?? 0).toString(),
        ),
    ];

    return _section(
      context,
      icon: Icons.badge_outlined,
      title: 'Contato e documentos',
      child: items.isEmpty
          ? _emptySectionText(
              context,
              'Nenhum contato ou documento cadastrado ainda.',
            )
          : _InfoGrid(items: items),
    );
  }

  bool _hasAddress() {
    final c = _client!;
    return c.address.isNotEmpty ||
        c.neighborhood.isNotEmpty ||
        c.city.isNotEmpty ||
        c.zipCode.isNotEmpty;
  }

  Widget _buildAddressSection(BuildContext context) {
    final c = _client!;
    return _section(
      context,
      icon: Icons.location_on_outlined,
      title: 'Endereço',
      child: _InfoGrid(
        items: [
          if (c.address.isNotEmpty)
            _InfoItem(
              Icons.location_on_outlined,
              'Endereço',
              c.address,
              wide: true,
            ),
          if (c.neighborhood.isNotEmpty)
            _InfoItem(Icons.place_outlined, 'Bairro', c.neighborhood),
          if (c.city.isNotEmpty)
            _InfoItem(
              Icons.location_city_outlined,
              'Cidade',
              c.state.isNotEmpty ? '${c.city} - ${c.state}' : c.city,
            ),
          if (c.zipCode.isNotEmpty)
            _InfoItem(
              Icons.markunread_mailbox_outlined,
              'CEP',
              Masks.cep(c.zipCode),
            ),
        ],
      ),
    );
  }

  bool _hasProfessionalInfo() {
    final c = _client!;
    return c.employmentStatus != null ||
        (c.companyName ?? '').isNotEmpty ||
        (c.jobPosition ?? '').isNotEmpty ||
        c.isRetired == true ||
        (c.contractType ?? '').isNotEmpty;
  }

  Widget _buildProfessionalSection(BuildContext context) {
    final c = _client!;
    return _section(
      context,
      icon: Icons.work_outline,
      title: 'Vida profissional',
      child: _InfoGrid(
        items: [
          if (c.employmentStatus != null)
            _InfoItem(
              Icons.work_outline,
              'Situação',
              c.employmentStatus!.label,
            ),
          if ((c.companyName ?? '').isNotEmpty)
            _InfoItem(Icons.business_outlined, 'Empresa', c.companyName!),
          if ((c.jobPosition ?? '').isNotEmpty)
            _InfoItem(Icons.badge_outlined, 'Cargo', c.jobPosition!),
          if ((c.contractType ?? '').isNotEmpty)
            _InfoItem(
              Icons.description_outlined,
              'Contrato',
              c.contractType!,
            ),
          if (c.isRetired == true)
            _InfoItem(Icons.work_off_outlined, 'Aposentado', 'Sim'),
        ],
      ),
    );
  }

  bool _hasFinancialInfo() {
    final c = _client!;
    return c.monthlyIncome != null ||
        c.familyIncome != null ||
        c.creditScore != null ||
        (c.bankName ?? '').isNotEmpty ||
        (c.bankAgency ?? '').isNotEmpty ||
        c.hasProperty == true ||
        c.hasVehicle == true;
  }

  Widget _buildFinancialSection(BuildContext context) {
    final c = _client!;
    return _section(
      context,
      icon: Icons.account_balance_wallet_outlined,
      title: 'Dados financeiros',
      child: _InfoGrid(
        items: [
          if (c.monthlyIncome != null)
            _InfoItem(
              Icons.attach_money_outlined,
              'Renda mensal',
              _currency.format(c.monthlyIncome),
            ),
          if (c.familyIncome != null)
            _InfoItem(
              Icons.family_restroom_outlined,
              'Renda familiar',
              _currency.format(c.familyIncome),
            ),
          if (c.creditScore != null)
            _InfoItem(
              Icons.credit_score_outlined,
              'Score de crédito',
              '${c.creditScore} de 1000',
            ),
          if ((c.bankName ?? '').isNotEmpty)
            _InfoItem(
              Icons.account_balance_outlined,
              'Banco',
              c.bankName!,
            ),
          if ((c.bankAgency ?? '').isNotEmpty)
            _InfoItem(
              Icons.account_balance_outlined,
              'Agência',
              c.bankAgency!,
            ),
          if (c.hasProperty == true)
            _InfoItem(Icons.house_outlined, 'Imóvel próprio', 'Sim'),
          if (c.hasVehicle == true)
            _InfoItem(
              Icons.directions_car_outlined,
              'Veículo',
              'Sim',
            ),
        ],
      ),
    );
  }

  Widget _buildSpouseSection(BuildContext context) {
    final spouse = _client!.spouse!;
    return _section(
      context,
      icon: Icons.favorite_outline,
      title: 'Cônjuge',
      child: _InfoGrid(
        items: [
          _InfoItem(
            Icons.person_outline,
            'Nome',
            spouse.name.trim().isEmpty ? 'Sem nome' : spouse.name,
            wide: true,
          ),
          if ((spouse.cpf ?? '').isNotEmpty)
            _InfoItem(
              Icons.fingerprint_rounded,
              'CPF',
              _formatCpf(spouse.cpf!),
            ),
          if ((spouse.phone ?? '').isNotEmpty)
            _InfoItem(
              Icons.phone_outlined,
              'Telefone',
              ClientPhoneRules.maskAuto(spouse.phone),
            ),
          if ((spouse.email ?? '').isNotEmpty)
            _InfoItem(
              Icons.alternate_email_rounded,
              'E-mail',
              spouse.email!,
              wide: true,
            ),
        ],
      ),
    );
  }

  Widget _emptySectionText(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: ThemeHelpers.textSecondaryColor(context),
      ),
    );
  }

  // ───────────────────── Skeleton / Error ─────────────────────

  /// Esqueleto FIEL à ficha: identidade, fatos em duas colunas, os três
  /// canais de contato e uma seção de dados.
  Widget _buildSkeleton(BuildContext context) {
    Widget factCell() => const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 16, height: 16, borderRadius: 4),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(flex: 5, child: SkeletonText(height: 9)),
                      Spacer(flex: 5),
                    ],
                  ),
                  SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(flex: 8, child: SkeletonText(height: 13)),
                      Spacer(flex: 2),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );

    Widget pairRow() => Row(
          children: [
            Expanded(child: factCell()),
            const SizedBox(width: 16),
            Expanded(child: factCell()),
          ],
        );

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 60, height: 60, borderRadius: 30),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(flex: 8, child: SkeletonText(height: 20)),
                            Spacer(flex: 2),
                          ],
                        ),
                        SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(flex: 5, child: SkeletonText(height: 16)),
                            Spacer(flex: 5),
                          ],
                        ),
                        SizedBox(height: 10),
                        Row(
                          children: [
                            SkeletonBox(
                                width: 78, height: 22, borderRadius: 999),
                            SizedBox(width: 6),
                            SkeletonBox(
                                width: 92, height: 22, borderRadius: 999),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              pairRow(),
              const SizedBox(height: 14),
              pairRow(),
              const SizedBox(height: 20),
              const Row(
                children: [
                  Expanded(child: SkeletonBox(height: 64, borderRadius: 14)),
                  SizedBox(width: 8),
                  Expanded(child: SkeletonBox(height: 64, borderRadius: 14)),
                  SizedBox(width: 8),
                  Expanded(child: SkeletonBox(height: 64, borderRadius: 14)),
                ],
              ),
              const SizedBox(height: 12),
              const SkeletonBox(height: 46, borderRadius: 12),
              const SizedBox(height: 28),
              const Row(
                children: [
                  SkeletonBox(width: 19, height: 19, borderRadius: 5),
                  SizedBox(width: 8),
                  Expanded(flex: 4, child: SkeletonText(height: 15)),
                  Spacer(flex: 6),
                ],
              ),
              const SizedBox(height: 16),
              pairRow(),
              const SizedBox(height: 14),
              pairRow(),
              const SizedBox(height: 14),
              pairRow(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    // Carregou sem falha e mesmo assim não veio cliente: é registro ausente,
    // não queda de conexão — 404 traduz isso corretamente.
    final semFalha = _errorMessage == null && _errorStatus == 0;
    return AppErrorState.fromApi(
      message: _errorMessage,
      statusCode: semFalha ? 404 : _errorStatus,
      error: _errorRaw,
      onRetry: _loadClient,
      secondaryLabel: 'Voltar',
      onSecondary: () => Navigator.pop(context),
    );
  }

  // ───────────────────── Actions ─────────────────────

  Future<void> _showTransferModal() async {
    if (_client == null) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        clipBehavior: Clip.antiAlias,
        child: TransferClientModal(
          clientId: _client!.id,
          clientName: _client!.name,
          currentResponsibleUserId: _client!.responsibleUserId,
          currentResponsibleName: _client!.responsibleUser?.name,
        ),
      ),
    );
    if (result == true) _loadClient();
  }

  Future<void> _deleteClient() async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.status.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.warning_amber_rounded,
                color: AppColors.status.error,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Excluir cliente?')),
          ],
        ),
        content: Text(
          'Esta ação remove permanentemente o cliente "${_client!.name}". '
          'Não será possível desfazer.',
          style: theme.textTheme.bodyMedium,
        ),
        actions: [
          // Cancelar é neutro: o tema pinta TextButton de vermelho.
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              foregroundColor: ThemeHelpers.textSecondaryColor(ctx),
            ),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.status.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed != true || _client == null) return;
    final response = await _clientService.deleteClient(_client!.id);
    if (!mounted) return;

    if (response.success) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Cliente excluído com sucesso!'),
          backgroundColor: AppColors.status.success,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response.message ?? 'Erro ao excluir cliente'),
          backgroundColor: AppColors.status.error,
        ),
      );
    }
  }

  Future<void> _launchUri(String uri) async {
    final parsed = Uri.tryParse(uri);
    if (parsed == null) return;
    try {
      await launchUrl(parsed, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir esse link')),
      );
    }
  }

  // ───────────────────── Helpers ─────────────────────

  String _initials(String name) {
    if (name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  String _formatDate(String? value) {
    if (value == null || value.isEmpty) return '-';
    try {
      return DateFormat('dd/MM/yyyy').format(DateTime.parse(value));
    } catch (_) {
      return value;
    }
  }

  String? _formatDateOrNull(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    return DateFormat('dd/MM/yyyy').format(parsed.toLocal());
  }

  /// "hoje", "ontem", "há 3 dias" ou a data — leitura rápida de recência.
  String? _relativeDay(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    final date = parsed.toLocal();
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(date.year, date.month, date.day))
        .inDays;
    if (days <= 0) return 'Hoje';
    if (days == 1) return 'Ontem';
    if (days < 7) return 'Há $days dias';
    return DateFormat('dd/MM/yyyy').format(date);
  }

  String _formatCpf(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 11) return value;
    return Masks.cpf(digits);
  }

  String _onlyDigits(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

  IconData _typeIcon(ClientType type) {
    switch (type) {
      case ClientType.buyer:
        return Icons.shopping_bag_outlined;
      case ClientType.seller:
        return Icons.sell_outlined;
      case ClientType.renter:
        return Icons.vpn_key_outlined;
      case ClientType.lessor:
        return Icons.home_work_outlined;
      case ClientType.investor:
        return Icons.trending_up_outlined;
      case ClientType.general:
        return Icons.person_outline;
    }
  }

  /// Cor de SIGNIFICADO do status (tokens). No selo pinta ponto, fundo e
  /// borda; o texto fica na cor do texto, legível nos dois temas.
  Color _statusTone(BuildContext context, ClientStatus status) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    switch (status) {
      case ClientStatus.active:
        return dark ? AppColors.status.successDarkMode : AppColors.status.success;
      case ClientStatus.contacted:
        return dark ? AppColors.status.infoDarkMode : AppColors.status.info;
      case ClientStatus.interested:
        return dark ? AppColors.status.warningDarkMode : AppColors.status.warning;
      case ClientStatus.closed:
        return dark ? AppColors.status.purpleDarkMode : AppColors.status.purple;
      case ClientStatus.inactive:
        return ThemeHelpers.textSecondaryColor(context);
    }
  }
}

// ───────────────────── Peças da ficha ─────────────────────

class _InfoItem {
  const _InfoItem(this.icon, this.label, this.value, {this.wide = false});

  final IconData icon;
  final String label;
  final String value;

  /// Valor longo (e-mail, endereço): ocupa a linha inteira.
  final bool wide;
}

/// Grade de rótulo + valor: duas colunas no celular (valores longos na
/// linha inteira), [columnsWide] em tela larga; uma coluna abaixo de 300dp.
class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.items, this.columnsWide = 3});

  final List<_InfoItem> items;
  final int columnsWide;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const gap = 16.0;
        final columns = width < 300 ? 1 : (width >= 560 ? columnsWide : 2);
        final cell = columns == 1
            ? width
            : ((width - gap * (columns - 1)) / columns).floorToDouble();
        return Wrap(
          spacing: gap,
          runSpacing: 14,
          children: [
            for (final item in items)
              SizedBox(
                width: item.wide || columns == 1 ? width : cell,
                child: _InfoCell(item: item),
              ),
          ],
        );
      },
    );
  }
}

class _InfoCell extends StatelessWidget {
  const _InfoCell({required this.item});

  final _InfoItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(item.icon, size: 16, color: muted),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: ThemeHelpers.textColor(context),
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Avatar de iniciais neutro (a cor da ficha fica para o significado).
class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 60,
      height: 60,
      padding: const EdgeInsets.all(8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark
            ? AppColors.background.backgroundTertiaryDarkMode
            : AppColors.background.backgroundTertiary,
        border: Border.all(color: ThemeHelpers.borderColor(context)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          initials,
          maxLines: 1,
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            height: 1.0,
            color: ThemeHelpers.textColor(context),
          ),
        ),
      ),
    );
  }
}

/// Selo de status: ponto e fundo na cor do significado, texto legível.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.tone});

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: isDark ? 0.18 : 0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: isDark ? 0.45 : 0.36)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
                height: 1.2,
                color: ThemeHelpers.textColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Etiqueta neutra com contorno (tipo, origem, cônjuge…).
class _OutlineTag extends StatelessWidget {
  const _OutlineTag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: ThemeHelpers.borderColor(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: muted),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
                height: 1.2,
                color: muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Canal de contato da ficha (WhatsApp, Ligar, E-mail). Sem o dado no
/// cadastro, fica apagado e diz o que falta — não some do lugar.
class _ChannelButton extends StatelessWidget {
  const _ChannelButton({
    required this.icon,
    required this.label,
    required this.missingLabel,
    required this.tone,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String missingLabel;
  final Color tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enabled = onTap != null;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final fg = enabled ? tone : muted.withValues(alpha: 0.7);
    final radius = BorderRadius.circular(14);

    return Material(
      color: enabled
          ? tone.withValues(alpha: isDark ? 0.14 : 0.08)
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: enabled
              ? tone.withValues(alpha: isDark ? 0.40 : 0.30)
              : ThemeHelpers.borderLightColor(context),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(borderRadius: radius),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 21, color: fg),
                const SizedBox(height: 5),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    enabled ? label : missingLabel,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: enabled ? 13 : 12,
                      fontWeight: enabled ? FontWeight.w800 : FontWeight.w600,
                      height: 1.1,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
