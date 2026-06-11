import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/shell_visual_tokens.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/utils/masks.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../../matches/widgets/matches_badge.dart';
import '../models/client_model.dart';
import '../services/client_service.dart';
import '../widgets/client_interactions_panel.dart';
import '../widgets/transfer_client_modal.dart';

/// Página de detalhes do cliente — painel elevado + ações rápidas.
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

  static final NumberFormat _currency =
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    _loadClient();
  }

  Color _accentColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFFF4D67)
        : AppColors.primary.primary;
  }

  Future<void> _loadClient() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
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
          _isLoading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Erro ao conectar com o servidor';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Detalhes do Cliente',
      actions: _client == null
          ? null
          : [
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
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
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(children: [
                      Icon(Icons.edit_outlined, size: 18),
                      SizedBox(width: 10),
                      Text('Editar'),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'matches',
                    child: Row(children: [
                      Icon(Icons.handshake_outlined, size: 18),
                      SizedBox(width: 10),
                      Text('Ver matches'),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'transfer',
                    child: Row(children: [
                      Icon(Icons.swap_horiz_rounded, size: 18),
                      SizedBox(width: 10),
                      Text('Transferir'),
                    ]),
                  ),
                  PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_outline, size: 18, color: Colors.red),
                      SizedBox(width: 10),
                      Text('Excluir', style: TextStyle(color: Colors.red)),
                    ]),
                  ),
                ],
              ),
            ],
      body: _isLoading
          ? _buildSkeleton(context)
          : _errorMessage != null && _client == null
              ? _buildErrorState(context)
              : _client == null
                  ? _buildErrorState(context)
                  : RefreshIndicator(
                      onRefresh: _loadClient,
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildHero(context),
                            const SizedBox(height: 14),
                            _buildContactActions(context),
                            const SizedBox(height: 14),
                            _buildBasicInfoCard(context),
                            const SizedBox(height: 14),
                            _buildAddressCard(context),
                            if (_hasProfessionalInfo()) ...[
                              const SizedBox(height: 14),
                              _buildProfessionalCard(context),
                            ],
                            if (_hasFinancialInfo()) ...[
                              const SizedBox(height: 14),
                              _buildFinancialCard(context),
                            ],
                            if (_hasPreferences()) ...[
                              const SizedBox(height: 14),
                              _buildPreferencesCard(context),
                            ],
                            if (_client!.spouse != null) ...[
                              const SizedBox(height: 14),
                              _buildSpouseCard(context),
                            ],
                            if ((_client!.notes ?? '').trim().isNotEmpty) ...[
                              const SizedBox(height: 14),
                              _buildNotesCard(context),
                            ],
                            const SizedBox(height: 14),
                            ClientInteractionsPanel(clientId: _client!.id),
                          ],
                        ),
                      ),
                    ),
    );
  }

  // ───────────────────── Hero ─────────────────────

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final typeColor = _typeColor(_client!.type);
    final statusColor = _statusColor(_client!.status);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  typeColor.withValues(alpha: 0.18),
                  typeColor.withValues(alpha: 0.06),
                ]
              : [
                  Colors.white,
                  typeColor.withValues(alpha: 0.10),
                ],
        ),
        border: Border.all(color: typeColor.withValues(alpha: 0.30)),
        boxShadow: [
          BoxShadow(
            color: typeColor.withValues(alpha: isDark ? 0.18 : 0.10),
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: -4,
          ),
        ],
      ),
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      typeColor.withValues(alpha: 0.95),
                      typeColor.withValues(alpha: 0.65),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: typeColor.withValues(alpha: 0.40),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  _initials(_client!.name),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.0,
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: _client!.isActive
                        ? AppColors.status.success
                        : AppColors.status.error,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: ThemeHelpers.cardBackgroundColor(context),
                      width: 3,
                    ),
                  ),
                  child: Icon(
                    _client!.isActive
                        ? Icons.check_rounded
                        : Icons.close_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          MatchesBadge(
            clientId: _client!.id,
            onClick: () => Navigator.pushNamed(
              context,
              AppRoutes.matchesByClient(_client!.id),
            ),
            child: Text(
              _client!.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
                color: ThemeHelpers.textColor(context),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              _heroBadge(
                context,
                _client!.type.label,
                typeColor,
                icon: _iconForType(_client!.type),
              ),
              _heroBadge(context, _client!.status.label, statusColor),
              if (_client!.leadSource != null)
                _heroBadge(
                  context,
                  _client!.leadSource!.label,
                  Colors.indigo,
                  icon: Icons.share_rounded,
                ),
              if (_client!.mcmvInterested == true)
                _heroBadge(
                  context,
                  'MCMV',
                  Colors.deepOrange,
                  icon: Icons.home_work_rounded,
                ),
            ],
          ),
          if (_client!.responsibleUser != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: ThemeHelpers.borderColor(context).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: ThemeHelpers.borderLightColor(context),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.assignment_ind_outlined,
                    size: 14,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Responsável: ${_client!.responsibleUser!.name}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _heroBadge(
    BuildContext context,
    String label,
    Color color, {
    IconData? icon,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────── Contact Actions ─────────────────────

  Widget _buildContactActions(BuildContext context) {
    final accent = _accentColor(context);
    final whatsapp = (_client!.whatsapp ?? '').trim();
    final phone = _client!.phone.trim();
    final email = _client!.email.trim();

    final actions = <Widget>[];
    if (whatsapp.isNotEmpty) {
      actions.add(_quickAction(
        context,
        icon: Icons.chat_outlined,
        label: 'WhatsApp',
        color: const Color(0xFF25D366),
        onTap: () => _launchUri('https://wa.me/${_onlyDigits(whatsapp)}'),
      ));
    }
    if (phone.isNotEmpty) {
      actions.add(_quickAction(
        context,
        icon: Icons.call_rounded,
        label: 'Ligar',
        color: const Color(0xFF3B82F6),
        onTap: () => _launchUri('tel:${_onlyDigits(phone)}'),
      ));
    }
    if (email.isNotEmpty) {
      actions.add(_quickAction(
        context,
        icon: Icons.alternate_email_rounded,
        label: 'Email',
        color: const Color(0xFFF59E0B),
        onTap: () => _launchUri('mailto:$email'),
      ));
    }
    actions.add(_quickAction(
      context,
      icon: Icons.edit_outlined,
      label: 'Editar',
      color: accent,
      onTap: () async {
        await Navigator.pushNamed(
          context,
          AppRoutes.clientEdit(_client!.id),
        );
        _loadClient();
      },
    ));

    if (actions.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: ShellVisualTokens.elevatedPanelDecoration(
        context,
        accent,
        style: ShellElevatedPanelStyle.profile,
      ),
      child: Row(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: 36,
                color: ThemeHelpers.borderLightColor(context)
                    .withValues(alpha: 0.6),
              ),
            Expanded(child: actions[i]),
          ],
        ],
      ),
    );
  }

  Widget _quickAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: color.withValues(alpha: 0.28)),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: ThemeHelpers.textColor(context),
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────── Info Cards ─────────────────────

  Widget _buildBasicInfoCard(BuildContext context) {
    final c = _client!;
    return _section(
      context,
      icon: Icons.badge_outlined,
      title: 'Informações básicas',
      items: [
        if (c.email.isNotEmpty)
          _infoEntry(Icons.alternate_email_rounded, 'Email', c.email),
        if (c.phone.isNotEmpty)
          _infoEntry(Icons.phone_outlined, 'Telefone', Masks.phone(c.phone)),
        if ((c.secondaryPhone ?? '').isNotEmpty)
          _infoEntry(
            Icons.phone_outlined,
            'Telefone secundário',
            Masks.phone(c.secondaryPhone!),
          ),
        if ((c.whatsapp ?? '').isNotEmpty)
          _infoEntry(
            Icons.chat_outlined,
            'WhatsApp',
            Masks.phone(c.whatsapp!),
          ),
        if (c.cpf.isNotEmpty)
          _infoEntry(Icons.fingerprint_rounded, 'CPF', _formatCpf(c.cpf)),
        if ((c.rg ?? '').isNotEmpty)
          _infoEntry(Icons.credit_card_outlined, 'RG', c.rg!),
        if ((c.birthDate ?? '').isNotEmpty)
          _infoEntry(
            Icons.cake_outlined,
            'Nascimento',
            _formatDate(c.birthDate),
          ),
        if (c.maritalStatus != null)
          _infoEntry(
            Icons.favorite_outline,
            'Estado civil',
            c.maritalStatus!.label,
          ),
        if (c.hasDependents == true)
          _infoEntry(
            Icons.family_restroom_outlined,
            'Dependentes',
            (c.numberOfDependents ?? 0).toString(),
          ),
      ],
    );
  }

  Widget _buildAddressCard(BuildContext context) {
    final c = _client!;
    return _section(
      context,
      icon: Icons.location_on_outlined,
      title: 'Endereço',
      items: [
        if (c.address.isNotEmpty)
          _infoEntry(Icons.location_on_outlined, 'Endereço', c.address),
        if (c.neighborhood.isNotEmpty)
          _infoEntry(Icons.place_outlined, 'Bairro', c.neighborhood),
        if (c.city.isNotEmpty)
          _infoEntry(
            Icons.location_city_outlined,
            'Cidade',
            c.state.isNotEmpty ? '${c.city} - ${c.state}' : c.city,
          ),
        if (c.zipCode.isNotEmpty)
          _infoEntry(
            Icons.markunread_mailbox_outlined,
            'CEP',
            Masks.cep(c.zipCode),
          ),
      ],
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

  Widget _buildProfessionalCard(BuildContext context) {
    final c = _client!;
    return _section(
      context,
      icon: Icons.work_outline,
      title: 'Vida profissional',
      items: [
        if (c.employmentStatus != null)
          _infoEntry(
            Icons.work_outline,
            'Situação',
            c.employmentStatus!.label,
          ),
        if ((c.companyName ?? '').isNotEmpty)
          _infoEntry(Icons.business_outlined, 'Empresa', c.companyName!),
        if ((c.jobPosition ?? '').isNotEmpty)
          _infoEntry(Icons.badge_outlined, 'Cargo', c.jobPosition!),
        if ((c.contractType ?? '').isNotEmpty)
          _infoEntry(
            Icons.description_outlined,
            'Contrato',
            c.contractType!,
          ),
        if (c.isRetired == true)
          _infoEntry(Icons.work_off_outlined, 'Aposentado', 'Sim'),
      ],
    );
  }

  bool _hasFinancialInfo() {
    final c = _client!;
    return c.monthlyIncome != null ||
        c.familyIncome != null ||
        c.creditScore != null ||
        (c.bankName ?? '').isNotEmpty;
  }

  Widget _buildFinancialCard(BuildContext context) {
    final c = _client!;
    return _section(
      context,
      icon: Icons.account_balance_wallet_outlined,
      title: 'Dados financeiros',
      items: [
        if (c.monthlyIncome != null)
          _infoEntry(
            Icons.attach_money_outlined,
            'Renda mensal',
            _currency.format(c.monthlyIncome),
          ),
        if (c.familyIncome != null)
          _infoEntry(
            Icons.family_restroom_outlined,
            'Renda familiar',
            _currency.format(c.familyIncome),
          ),
        if (c.creditScore != null)
          _infoEntry(
            Icons.credit_score_outlined,
            'Score de crédito',
            '${c.creditScore}/1000',
          ),
        if ((c.bankName ?? '').isNotEmpty)
          _infoEntry(
            Icons.account_balance_outlined,
            'Banco',
            c.bankName!,
          ),
        if ((c.bankAgency ?? '').isNotEmpty)
          _infoEntry(
            Icons.account_balance_outlined,
            'Agência',
            c.bankAgency!,
          ),
        if (c.hasProperty == true)
          _infoEntry(Icons.house_outlined, 'Imóvel próprio', 'Sim'),
        if (c.hasVehicle == true)
          _infoEntry(
            Icons.directions_car_outlined,
            'Veículo',
            'Sim',
          ),
      ],
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
        c.maxBedrooms != null;
  }

  Widget _buildPreferencesCard(BuildContext context) {
    final c = _client!;
    return _section(
      context,
      icon: Icons.tune_rounded,
      title: 'Preferências imobiliárias',
      items: [
        if ((c.preferredPropertyType ?? '').isNotEmpty)
          _infoEntry(
            Icons.home_outlined,
            'Tipo preferido',
            c.preferredPropertyType!,
          ),
        if ((c.preferredCity ?? '').isNotEmpty)
          _infoEntry(
            Icons.location_city_outlined,
            'Cidade preferida',
            c.preferredCity!,
          ),
        if ((c.preferredNeighborhood ?? '').isNotEmpty)
          _infoEntry(
            Icons.place_outlined,
            'Bairro preferido',
            c.preferredNeighborhood!,
          ),
        if (c.minValue != null && c.maxValue != null)
          _infoEntry(
            Icons.attach_money_outlined,
            'Faixa de preço',
            '${_currency.format(c.minValue)} – ${_currency.format(c.maxValue)}',
          )
        else if (c.minValue != null)
          _infoEntry(
            Icons.attach_money_outlined,
            'Valor mínimo',
            _currency.format(c.minValue),
          )
        else if (c.maxValue != null)
          _infoEntry(
            Icons.attach_money_outlined,
            'Valor máximo',
            _currency.format(c.maxValue),
          ),
        if (c.minBedrooms != null && c.maxBedrooms != null)
          _infoEntry(
            Icons.bed_outlined,
            'Quartos',
            '${c.minBedrooms} a ${c.maxBedrooms}',
          ),
        if (c.minArea != null && c.maxArea != null)
          _infoEntry(
            Icons.square_foot_outlined,
            'Área',
            '${c.minArea!.toStringAsFixed(0)} a ${c.maxArea!.toStringAsFixed(0)} m²',
          ),
      ],
    );
  }

  Widget _buildSpouseCard(BuildContext context) {
    final spouse = _client!.spouse!;
    return _section(
      context,
      icon: Icons.favorite_outline,
      title: 'Cônjuge',
      items: [
        _infoEntry(Icons.person_outline, 'Nome', spouse.name),
        if ((spouse.cpf ?? '').isNotEmpty)
          _infoEntry(
            Icons.fingerprint_rounded,
            'CPF',
            _formatCpf(spouse.cpf!),
          ),
        if ((spouse.phone ?? '').isNotEmpty)
          _infoEntry(
            Icons.phone_outlined,
            'Telefone',
            Masks.phone(spouse.phone!),
          ),
        if ((spouse.email ?? '').isNotEmpty)
          _infoEntry(Icons.alternate_email_rounded, 'Email', spouse.email!),
      ],
    );
  }

  Widget _buildNotesCard(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accentColor(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.42),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                  spreadRadius: -3,
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: accent.withValues(alpha: 0.10),
                  border: Border.all(color: accent.withValues(alpha: 0.22)),
                ),
                child: Icon(Icons.sticky_note_2_outlined,
                    size: 19, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Observações',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _client!.notes ?? '',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ThemeHelpers.textColor(context),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────── Section helper ─────────────────────

  Widget _section(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<Widget> items,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accentColor(context);

    final realItems = items.whereType<Widget>().toList();
    if (realItems.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.42),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                  spreadRadius: -3,
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: accent.withValues(alpha: 0.10),
                    border: Border.all(color: accent.withValues(alpha: 0.22)),
                  ),
                  child: Icon(icon, size: 19, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...realItems,
          ],
        ),
      ),
    );
  }

  Widget _infoEntry(IconData icon, String label, String value) {
    return Builder(builder: (context) {
      final theme = Theme.of(context);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: ThemeHelpers.borderColor(context).withValues(alpha: 0.18),
              ),
              child: Icon(
                icon,
                size: 16,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: ThemeHelpers.textSecondaryColor(context),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: ThemeHelpers.textColor(context),
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  // ───────────────────── Skeleton / Error ─────────────────────

  Widget _buildSkeleton(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      child: Column(
        children: [
          const SkeletonBox(
              width: double.infinity, height: 220, borderRadius: 24),
          const SizedBox(height: 14),
          const SkeletonBox(
              width: double.infinity, height: 96, borderRadius: 20),
          const SizedBox(height: 14),
          ...List.generate(
            3,
            (index) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: SkeletonBox(
                width: double.infinity,
                height: 200,
                borderRadius: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.status.error.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_outlined,
                size: 46,
                color: AppColors.status.error,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Não foi possível carregar este cliente',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: ThemeHelpers.textColor(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _errorMessage ?? 'Cliente não encontrado',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _loadClient,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tentar novamente'),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Voltar'),
            ),
          ],
        ),
      ),
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.status.error,
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

  String _formatCpf(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 11) return value;
    return Masks.cpf(digits);
  }

  String _onlyDigits(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

  Color _typeColor(ClientType type) {
    switch (type) {
      case ClientType.buyer:
        return const Color(0xFF3B82F6);
      case ClientType.seller:
        return const Color(0xFFF59E0B);
      case ClientType.renter:
        return const Color(0xFF10B981);
      case ClientType.lessor:
        return const Color(0xFF06B6D4);
      case ClientType.investor:
        return const Color(0xFF8B5CF6);
      case ClientType.general:
        return const Color(0xFF64748B);
    }
  }

  IconData _iconForType(ClientType type) {
    switch (type) {
      case ClientType.buyer:
        return Icons.shopping_bag_outlined;
      case ClientType.seller:
        return Icons.sell_outlined;
      case ClientType.renter:
        return Icons.home_outlined;
      case ClientType.lessor:
        return Icons.business_outlined;
      case ClientType.investor:
        return Icons.trending_up_outlined;
      case ClientType.general:
        return Icons.person_outline;
    }
  }

  Color _statusColor(ClientStatus status) {
    switch (status) {
      case ClientStatus.active:
        return AppColors.status.success;
      case ClientStatus.inactive:
        return AppColors.status.error;
      case ClientStatus.contacted:
        return AppColors.status.info;
      case ClientStatus.interested:
        return AppColors.status.warning;
      case ClientStatus.closed:
        return Colors.grey;
    }
  }
}
