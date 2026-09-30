import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/property_service.dart';
import '../../../../shared/utils/broker_contact_actions.dart';
import 'property_details_kit.dart';

/// Corpo da seção "Proprietário" da ficha do imóvel — vai dentro do molde
/// flush da página (`_buildFlushSection(title: 'Proprietário', …)`). Monte a
/// seção só quando [PropertyOwnerSection.isVisible] for `true`; fora disso o
/// widget devolve `SizedBox.shrink()`.
///
/// Regra IGUAL à do web (`PropertyDetailsOwnerSection.tsx`):
/// - `canViewOwnerData != true` e `ownerDataRestricted == true` → "Dados
///   restritos" com cadeado e o motivo (proprietário restrito, sem acesso);
/// - `canViewOwnerData != true` nos demais casos (inclusive campo ausente) →
///   nada;
/// - pode ver, mas nenhum dado preenchido → nada;
/// - pode ver → nome, e-mail, telefone, CPF/CNPJ e endereço, cada linha com
///   Copiar; telefone com Ligar e WhatsApp; e-mail com Escrever.
///
/// Espera da página só o [Property] do `GET /properties/:id` (os campos
/// `owner`, `canViewOwnerData` e `ownerDataRestricted`).
class PropertyOwnerSection extends StatelessWidget {
  const PropertyOwnerSection({super.key, required this.property});

  final Property property;

  /// A seção existe para este imóvel e este usuário (mesma regra do web).
  static bool isVisible(Property property) {
    if (property.canViewOwnerData != true) {
      return property.ownerDataRestricted == true;
    }
    return _rowsOf(property.owner).isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    if (property.canViewOwnerData != true) {
      if (property.ownerDataRestricted == true) {
        return const _RestrictedOwner();
      }
      return const SizedBox.shrink();
    }
    final rows = _rowsOf(property.owner);
    if (rows.isEmpty) return const SizedBox.shrink();

    final divider = ThemeHelpers.borderLightColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Container(height: 1, color: divider),
          _OwnerRowTile(row: rows[i]),
        ],
      ],
    );
  }
}

enum _OwnerField { name, email, phone, document, address }

class _OwnerRow {
  const _OwnerRow({
    required this.field,
    required this.icon,
    required this.label,
    required this.value,
    required this.raw,
  });

  final _OwnerField field;
  final IconData icon;
  final String label;

  /// O que aparece (formatado).
  final String value;

  /// Valor cru (telefone e e-mail para as ações).
  final String raw;
}

/// Linhas na ordem do web; só entra o que estiver preenchido.
List<_OwnerRow> _rowsOf(PropertyOwner? owner) {
  if (owner == null) return const [];
  final rows = <_OwnerRow>[];
  final name = owner.name?.trim() ?? '';
  final email = owner.email?.trim() ?? '';
  final phone = owner.phone?.trim() ?? '';
  final document = owner.document?.trim() ?? '';
  final address = owner.address?.trim() ?? '';

  if (name.isNotEmpty) {
    rows.add(_OwnerRow(
      field: _OwnerField.name,
      icon: LucideIcons.userRound,
      label: 'Nome',
      value: name,
      raw: name,
    ));
  }
  if (email.isNotEmpty) {
    rows.add(_OwnerRow(
      field: _OwnerField.email,
      icon: LucideIcons.mail,
      label: 'E-mail',
      value: email,
      raw: email,
    ));
  }
  if (phone.isNotEmpty) {
    rows.add(_OwnerRow(
      field: _OwnerField.phone,
      icon: LucideIcons.phone,
      label: 'Telefone',
      value: BrokerContactActions.formatBrazilPhone(phone),
      raw: phone,
    ));
  }
  if (document.isNotEmpty) {
    final digits = document.replaceAll(RegExp(r'\D'), '');
    rows.add(_OwnerRow(
      field: _OwnerField.document,
      icon: LucideIcons.idCard,
      label: digits.length == 11
          ? 'CPF'
          : (digits.length == 14 ? 'CNPJ' : 'CPF / CNPJ'),
      value: _formatDocument(document),
      raw: document,
    ));
  }
  if (address.isNotEmpty) {
    rows.add(_OwnerRow(
      field: _OwnerField.address,
      icon: LucideIcons.mapPin,
      label: 'Endereço',
      value: address,
      raw: address,
    ));
  }
  return rows;
}

/// CPF (11 dígitos) → 000.000.000-00; CNPJ (14) → 00.000.000/0000-00; o
/// resto como veio — mesma regra do `formatOwnerDocument` do web.
String _formatDocument(String doc) {
  final d = doc.replaceAll(RegExp(r'\D'), '');
  if (d.length == 11) {
    return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-'
        '${d.substring(9)}';
  }
  if (d.length == 14) {
    return '${d.substring(0, 2)}.${d.substring(2, 5)}.${d.substring(5, 8)}/'
        '${d.substring(8, 12)}-${d.substring(12)}';
  }
  return doc.trim();
}

/// Uma linha flush: selo neutro com o ícone, rótulo + valor (o endereço em
/// até 4 linhas, o resto em até 2), ações de contato rotuladas embaixo do
/// valor (quebram linha em vez de estourar) e Copiar à direita.
class _OwnerRowTile extends StatelessWidget {
  const _OwnerRowTile({required this.row});

  final _OwnerRow row;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: row.value));
    if (!context.mounted) return;
    pdkShowSnack(context, '${row.label} copiado.', tone: PdkSnackTone.success);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final plate = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;

    final actions = <Widget>[
      if (row.field == _OwnerField.phone) ...[
        PdkContactChip(
          icon: LucideIcons.phone,
          label: 'Ligar',
          tone: PdkTone.blue(context),
          onTap: () => BrokerContactActions.callPhone(context, row.raw),
        ),
        PdkContactChip(
          icon: LucideIcons.messageCircle,
          label: 'WhatsApp',
          tone: PdkTone.green(context),
          onTap: () => BrokerContactActions.openWhatsApp(context, row.raw),
        ),
      ],
      if (row.field == _OwnerField.email)
        PdkContactChip(
          icon: LucideIcons.mail,
          label: 'Escrever',
          tone: PdkTone.blue(context),
          onTap: () => pdkOpenEmail(context, row.raw),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: plate,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(row.icon, size: 17, color: secondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: secondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  row.value,
                  maxLines: row.field == _OwnerField.address ? 4 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ThemeHelpers.textColor(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                    letterSpacing: -0.1,
                    fontFeatures: row.field == _OwnerField.phone ||
                            row.field == _OwnerField.document
                        ? const [FontFeature.tabularFigures()]
                        : null,
                  ),
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          PdkIconAction(
            icon: LucideIcons.copy,
            tooltip: row.field == _OwnerField.document
                ? 'Copiar ${row.label}'
                : 'Copiar ${row.label.toLowerCase()}',
            onTap: () => _copy(context),
          ),
        ],
      ),
    );
  }
}

/// "Dados restritos" — o motivo no lugar dos dados (regra da casa: travar
/// com o porquê em vez de sumir). Texto do web.
class _RestrictedOwner extends StatelessWidget {
  const _RestrictedOwner();

  @override
  Widget build(BuildContext context) {
    return const PdkLockNote(
      title: 'Dados restritos',
      reason: 'Os dados do proprietário deste imóvel (nome, contato, '
          'documento e endereço) são restritos. Fale com um administrador '
          'para liberar o acesso.',
    );
  }
}
