import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/property_service.dart';
import '../../../../shared/utils/broker_contact_actions.dart';
import 'property_details_kit.dart';

/// Corpo da seção "Responsáveis" da ficha do imóvel — vai dentro do molde
/// flush da página (`_buildFlushSection(title: 'Responsáveis', …)`); monte a
/// seção só quando [PropertyResponsiblesSection.isVisible] for `true`.
///
/// Paridade com "Responsáveis e captadores" do web (PropertyDetailsPage
/// ~2603-2681), SEM repetir os captadores: no app eles já têm a seção
/// "Captação". Daqui sai cada responsável (principal primeiro, na ordem da
/// API) em linha flush com iniciais, nome, papel ("Responsável principal",
/// "Responsável adicional"; "… e captador" quando também capta — a dica
/// "Responsável e captador" do web), telefone/e-mail e as ações Ligar,
/// WhatsApp e E-mail no próprio item.
///
/// Espera da página o [Property] do `GET /properties/:id` (`responsibles`,
/// `responsibleUserId` e os captadores para a dica) e, opcionalmente, o id
/// do usuário logado para marcar "Você".
///
/// Reserva do web (W:1198-1245): quando o detalhe vem SEM `responsibles` (ou
/// vazio) e há `responsibleUserId`, a página busca o principal com
/// `PropertyDetailExtrasService.fetchMainResponsible(responsibleUserId)` e
/// passa o resultado em [fallback] (e no `fallback:` de [resolve] /
/// [isVisible]) — a seção não some.
class PropertyResponsiblesSection extends StatelessWidget {
  const PropertyResponsiblesSection({
    super.key,
    required this.property,
    this.currentUserId,
    this.tone,
    this.fallback,
  });

  final Property property;

  /// Id do usuário logado — a linha dele ganha a etiqueta "Você".
  final String? currentUserId;

  /// Tom das iniciais e da etiqueta (token cru). Padrão: azul de
  /// comunicação.
  final Color? tone;

  /// Responsáveis de reserva, usados só quando `property.responsibles` veio
  /// nulo ou vazio (o `fetchMainResponsible` da página).
  final List<PropertyResponsible>? fallback;

  /// Responsáveis na ordem da API (principal primeiro), sem repetir pessoa —
  /// a mesma dedupe do web (`dedupePropertyPeopleByIdOrEmail`: por id e por
  /// e-mail; item sem id sai). Sem lista na ficha, usa [fallback].
  static List<PropertyResponsible> resolve(
    Property property, {
    List<PropertyResponsible>? fallback,
  }) {
    final fromProperty = property.responsibles ?? const <PropertyResponsible>[];
    final raw = fromProperty.isNotEmpty
        ? fromProperty
        : (fallback ?? const <PropertyResponsible>[]);
    final seenIds = <String>{};
    final seenEmails = <String>{};
    final out = <PropertyResponsible>[];
    for (final person in raw) {
      final id = person.id.trim();
      final email = (person.email ?? '').trim().toLowerCase();
      if (id.isNotEmpty && seenIds.contains(id)) continue;
      if (email.isNotEmpty && seenEmails.contains(email)) continue;
      if (id.isNotEmpty) seenIds.add(id);
      if (email.isNotEmpty) seenEmails.add(email);
      if (id.isEmpty) continue;
      out.add(person);
    }
    return out;
  }

  /// A seção tem alguém para mostrar (com a reserva, quando houver).
  static bool isVisible(
    Property property, {
    List<PropertyResponsible>? fallback,
  }) =>
      resolve(property, fallback: fallback).isNotEmpty;

  static Set<String> _captorIds(Property property) {
    final ids = <String>{
      for (final c in property.captors ?? const <PropertyCaptor>[])
        if (c.id.trim().isNotEmpty) c.id.trim(),
      for (final id in property.capturedByIds ?? const <String>[])
        if (id.trim().isNotEmpty) id.trim(),
    };
    final single = property.capturedById?.trim() ?? '';
    if (single.isNotEmpty) ids.add(single);
    final legacy = property.capturedBy?.id.trim() ?? '';
    if (legacy.isNotEmpty) ids.add(legacy);
    return ids;
  }

  @override
  Widget build(BuildContext context) {
    final people = resolve(property, fallback: fallback);
    if (people.isEmpty) return const SizedBox.shrink();

    final captors = _captorIds(property);
    final primaryId = property.responsibleUserId.trim();
    final me = currentUserId?.trim() ?? '';
    final accent = tone ?? PdkTone.blue(context);
    final divider = ThemeHelpers.borderLightColor(context);
    final several = people.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < people.length; i++) ...[
          if (i > 0) Container(height: 1, color: divider),
          _ResponsibleRow(
            person: people[i],
            role: _roleOf(
              isPrimary: people[i].id == primaryId,
              several: several,
              isCaptor: captors.contains(people[i].id),
            ),
            isYou: me.isNotEmpty && people[i].id == me,
            tone: accent,
          ),
        ],
      ],
    );
  }

  static String _roleOf({
    required bool isPrimary,
    required bool several,
    required bool isCaptor,
  }) {
    final base = !several
        ? 'Responsável'
        : (isPrimary ? 'Responsável principal' : 'Responsável adicional');
    return isCaptor ? '$base e captador' : base;
  }
}

/// Linha flush de um responsável. As ações ficam à direita, só ícone (como
/// na Captação), quando sobra espaço para o nome; em tela estreita ou fonte
/// grande descem para baixo do texto, com rótulo e quebrando linha.
class _ResponsibleRow extends StatelessWidget {
  const _ResponsibleRow({
    required this.person,
    required this.role,
    required this.isYou,
    required this.tone,
  });

  final PropertyResponsible person;
  final String role;
  final bool isYou;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final name = (person.name ?? '').trim();
    final displayName = name.isNotEmpty ? name : 'Responsável';
    final phone = (person.phone ?? '').trim();
    final email = (person.email ?? '').trim();
    final hasPhone = BrokerContactActions.digitsOnly(phone).length >= 10;
    final blue = PdkTone.blue(context);
    final green = PdkTone.green(context);

    final contactLines = <Widget>[
      if (phone.isNotEmpty)
        _ContactLine(
          icon: LucideIcons.phone,
          text: BrokerContactActions.formatBrazilPhone(phone),
          tabular: true,
        ),
      if (email.isNotEmpty)
        _ContactLine(icon: LucideIcons.mail, text: email),
      if (phone.isEmpty && email.isEmpty)
        const _ContactLine(
          icon: LucideIcons.circleOff,
          text: 'Sem telefone nem e-mail no cadastro',
        ),
    ];

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ThemeHelpers.textColor(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                  letterSpacing: -0.1,
                ),
              ),
            ),
            if (isYou) ...[
              const SizedBox(width: 6),
              Container(
                margin: const EdgeInsets.only(top: 1),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: isDark ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Você',
                  style: TextStyle(
                    color: pdkInk(context, tone),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          role,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: secondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 4),
        ...contactLines,
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = pdkTextScale(context);
          final count = (hasPhone ? 2 : 0) + (email.isNotEmpty ? 1 : 0);
          final actionsWidth = count == 0 ? 0.0 : count * 40.0 + (count - 1) * 6;
          final textRoom = constraints.maxWidth -
              40 -
              12 -
              (count == 0 ? 0 : actionsWidth + 10);
          final inline = count == 0 || textRoom >= 150 * scale;

          final List<Widget> actions;
          if (inline) {
            actions = [
              if (hasPhone)
                PdkIconAction(
                  icon: LucideIcons.phone,
                  tooltip: 'Ligar',
                  tone: blue,
                  onTap: () => BrokerContactActions.callPhone(context, phone),
                ),
              if (hasPhone)
                PdkIconAction(
                  icon: LucideIcons.messageCircle,
                  tooltip: 'WhatsApp',
                  tone: green,
                  onTap: () =>
                      BrokerContactActions.openWhatsApp(context, phone),
                ),
              if (email.isNotEmpty)
                PdkIconAction(
                  icon: LucideIcons.mail,
                  tooltip: 'E-mail',
                  tone: blue,
                  onTap: () => pdkOpenEmail(context, email),
                ),
            ];
          } else {
            actions = [
              if (hasPhone)
                PdkContactChip(
                  icon: LucideIcons.phone,
                  label: 'Ligar',
                  tone: blue,
                  onTap: () => BrokerContactActions.callPhone(context, phone),
                ),
              if (hasPhone)
                PdkContactChip(
                  icon: LucideIcons.messageCircle,
                  label: 'WhatsApp',
                  tone: green,
                  onTap: () =>
                      BrokerContactActions.openWhatsApp(context, phone),
                ),
              if (email.isNotEmpty)
                PdkContactChip(
                  icon: LucideIcons.mail,
                  label: 'E-mail',
                  tone: blue,
                  onTap: () => pdkOpenEmail(context, email),
                ),
            ];
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PdkInitialsAvatar(
                name: displayName,
                tone: tone,
                imageUrl: person.avatar,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: inline
                    ? info
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          info,
                          const SizedBox(height: 9),
                          Wrap(spacing: 8, runSpacing: 8, children: actions),
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

/// Linha de contato (ícone + texto numa linha, reticências no fim).
class _ContactLine extends StatelessWidget {
  const _ContactLine({
    required this.icon,
    required this.text,
    this.tabular = false,
  });

  final IconData icon;
  final String text;
  final bool tabular;

  @override
  Widget build(BuildContext context) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 12, color: secondary),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: secondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFeatures:
                    tabular ? const [FontFeature.tabularFigures()] : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
