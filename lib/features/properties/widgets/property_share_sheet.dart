import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/property_service.dart';
import '../../../shared/utils/broker_contact_actions.dart';
import '../utils/public_property_link.dart';

/// Sheet "Compartilhar imóvel" — o hub de divulgação do corretor.
///
/// Resolve o link público do site da empresa (cacheado por sessão), mostra a
/// mensagem pronta que vai ser enviada e oferece os caminhos que o corretor
/// realmente usa: WhatsApp direto (escolhe o contato, mensagem já digitada),
/// share sheet nativo do sistema, copiar link/mensagem e abrir no navegador.
///
/// Chame apenas quando `property.isAvailableForSite == true` (mesmo gate dos
/// botões do web). Se a empresa não tiver site, o sheet explica em vez de
/// falhar silenciosamente.
Future<void> showPropertyShareSheet(
  BuildContext context,
  Property property,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => _PropertyShareSheet(property: property),
  );
}

const _whatsappGreen = Color(0xFF25D366);

class _PropertyShareSheet extends StatefulWidget {
  final Property property;

  const _PropertyShareSheet({required this.property});

  @override
  State<_PropertyShareSheet> createState() => _PropertyShareSheetState();
}

class _PropertyShareSheetState extends State<_PropertyShareSheet> {
  bool _loading = true;
  String? _url;

  /// Feedback de cópia INLINE (`'link'` | `'message'`) — snackbar ficaria
  /// escondido atrás do modal.
  String? _copiedTag;
  Timer? _copiedTimer;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _resolve() async {
    final url = await PublicPropertyLink.resolveUrl(widget.property);
    if (!mounted) return;
    setState(() {
      _url = url;
      _loading = false;
    });
  }

  String get _message => PublicPropertyLink.shareMessage(widget.property, _url);

  void _copy(String value, String tag) {
    Clipboard.setData(ClipboardData(text: value));
    HapticFeedback.selectionClick();
    _copiedTimer?.cancel();
    setState(() => _copiedTag = tag);
    _copiedTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _copiedTag = null);
    });
  }

  Future<void> _openOnSite() async {
    final url = _url;
    if (url == null) return;
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o navegador.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);
    final property = widget.property;
    final code = property.code?.trim();
    final maxHeight = MediaQuery.of(context).size.height * 0.88;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(
            color: ThemeHelpers.borderColor(context).withValues(alpha: 0.55),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.10),
            blurRadius: 22,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: muted.withValues(alpha: 0.32),
                  ),
                ),
              ),

              // ── Header editorial ─────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 12, 14, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'COMPARTILHAR IMÓVEL',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.primary.primary,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.6,
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            property.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.4,
                              color: ThemeHelpers.textColor(context),
                              height: 1.15,
                              fontSize: 19,
                            ),
                          ),
                          if (code != null && code.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Código $code',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: muted,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 22),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      ThemeHelpers.borderColor(context),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),

              // Corpo rolável — em tela baixa (landscape/aparelho pequeno)
              // o conteúdo rola em vez de estourar o Column.
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: _loading
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(
                            child: SizedBox(
                              width: 26,
                              height: 26,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2.6),
                            ),
                          ),
                        )
                      : _url == null
                          ? _buildNoSite(theme, muted)
                          : _buildContent(theme, isDark, muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Empresa sem site publicado — explica em vez de sumir com a opção.
  Widget _buildNoSite(ThemeData theme, Color muted) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(LucideIcons.globe, size: 18, color: muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'A empresa ainda não tem um site publicado',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Publique o site da empresa em Configurações → Meu Site para '
            'gerar links públicos dos imóveis.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: muted,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme, bool isDark, Color muted) {
    final url = _url!;
    final fieldFill = isDark
        ? AppColors.background.backgroundTertiaryDarkMode
        : AppColors.background.backgroundTertiary;
    final blue = isDark ? AppColors.status.blueDarkMode : AppColors.status.blue;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Link público (tap = copiar) ──────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
          child: Material(
            color: fieldFill,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _copy(url, 'link'),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: ThemeHelpers.borderLightColor(context),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.1,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (_copiedTag == 'link')
                      const Icon(Icons.check_rounded,
                          size: 16, color: Color(0xFF10B981))
                    else
                      Icon(Icons.content_copy_rounded, size: 16, color: muted),
                  ],
                ),
              ),
            ),
          ),
        ),

        // ── Mensagem pronta (preview + copiar) ───────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'MENSAGEM PRONTA',
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800,
                      color: muted,
                      fontSize: 9.5,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _copy(_message, 'message'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_copiedTag == 'message')
                            const Icon(Icons.check_rounded,
                                size: 12, color: Color(0xFF10B981))
                          else
                            Icon(Icons.content_copy_rounded,
                                size: 12, color: muted),
                          const SizedBox(width: 4),
                          Text(
                            _copiedTag == 'message' ? 'Copiado' : 'Copiar',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: _copiedTag == 'message'
                                  ? const Color(0xFF10B981)
                                  : muted,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              // Régua accent à esquerda — linguagem editorial do app.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 3,
                      decoration: BoxDecoration(
                        color: _whatsappGreen.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _message,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                          height: 1.5,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Ações ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ShareActionTile(
                icon: LucideIcons.messageCircle,
                label: 'Enviar no WhatsApp',
                subtitle: 'Escolha o contato — a mensagem já vai digitada',
                color: _whatsappGreen,
                onTap: () async {
                  final ok = await BrokerContactActions.shareViaWhatsApp(
                    context,
                    _message,
                  );
                  if (ok && mounted) Navigator.of(context).pop();
                },
              ),
              _ShareActionTile(
                icon: Icons.share_rounded,
                label: 'Compartilhar em outro app',
                subtitle: 'Instagram, e-mail, SMS e o que mais tiver',
                color: blue,
                onTap: () async {
                  final ok = await BrokerContactActions.shareText(
                    context,
                    _message,
                  );
                  if (ok && mounted) Navigator.of(context).pop();
                },
              ),
              _ShareActionTile(
                icon: LucideIcons.globe,
                label: 'Ver no site',
                subtitle: 'Abre a página pública no navegador',
                color: const Color(0xFF6366F1),
                onTap: _openOnSite,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tile de ação — mesma linguagem do sheet de ações rápidas dos imóveis.
class _ShareActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ShareActionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = ThemeHelpers.textSecondaryColor(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: color.withValues(alpha: 0.16),
        highlightColor: color.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: color.withValues(alpha: isDark ? 0.18 : 0.12),
                  border: Border.all(
                    color: color.withValues(alpha: isDark ? 0.34 : 0.22),
                  ),
                ),
                child: Icon(icon, size: 19, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.15,
                        color: ThemeHelpers.textColor(context),
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: muted,
                        fontSize: 11.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
