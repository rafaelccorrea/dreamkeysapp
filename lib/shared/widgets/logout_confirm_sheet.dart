import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/theme_helpers.dart';

/// Tons do modal de saída. Cor com SIGNIFICADO: rosa é a ação de sair
/// (destrutiva-leve), âmbar avisa o que termina, esmeralda diz o que
/// continua valendo e o azul lembra o que NÃO se perde.
const Color _kExitTone = Color(0xFFE11D48);
const Color _kWarnTone = Color(0xFFD97706);
const Color _kKeepTone = Color(0xFF059669);
const Color _kSafeTone = Color(0xFF0EA5E9);

/// Confirmação de logout.
///
/// Substitui o `AlertDialog` padrão, que não dizia nada além de "Sair": a
/// pessoa não sabia se perdia dados, se precisaria da senha ou se a
/// biometria continuaria valendo. Aqui as três respostas estão na tela,
/// cada uma com sua cor — e o cabeçalho mostra de QUAL conta se está
/// saindo, que importa em aparelho compartilhado.
///
/// Devolve `true` quando o usuário confirma.
Future<bool?> showLogoutConfirmSheet({
  required BuildContext context,
  required String? userName,
  required String? userEmail,
  required bool biometricEnabled,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _LogoutConfirmSheet(
      userName: userName,
      userEmail: userEmail,
      biometricEnabled: biometricEnabled,
    ),
  );
}

class _LogoutConfirmSheet extends StatelessWidget {
  final String? userName;
  final String? userEmail;
  final bool biometricEnabled;

  const _LogoutConfirmSheet({
    required this.userName,
    required this.userEmail,
    required this.biometricEnabled,
  });

  String get _nome {
    final n = (userName ?? '').trim();
    return n.isEmpty ? 'Usuário' : n;
  }

  String get _inicial => _nome[0].toUpperCase();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
      child: Container(
        decoration: BoxDecoration(
          color: ThemeHelpers.cardBackgroundColor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Grabber 42×4 — anatomia da casa.
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 10),
              child: Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ThemeHelpers.borderColor(context)
                        .withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      color: _kExitTone.withValues(alpha: isDark ? 0.20 : 0.12),
                    ),
                    child: const Icon(
                      LucideIcons.logOut,
                      color: _kExitTone,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SESSÃO',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4,
                            color: _kExitTone,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Sair da conta',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.2,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: Icon(LucideIcons.x, size: 18, color: secondary),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Fechar',
                  ),
                ],
              ),
            ),
            // Divisor gradient na cor da ação.
            Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _kExitTone.withValues(alpha: 0.30),
                    ThemeHelpers.borderLightColor(context)
                        .withValues(alpha: 0.25),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // DE QUAL conta se está saindo — em aparelho
                    // compartilhado esta é a informação que evita o erro.
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _kExitTone.withValues(
                              alpha: isDark ? 0.22 : 0.13,
                            ),
                            border: Border.all(
                              color: _kExitTone.withValues(alpha: 0.35),
                              width: 1.2,
                            ),
                          ),
                          child: Text(
                            _inicial,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: _kExitTone,
                            ),
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _nome,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.1,
                                  color: textColor,
                                ),
                              ),
                              if ((userEmail ?? '').trim().isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  userEmail!.trim(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: secondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // O QUE ACONTECE — uma linha por consequência, cada uma
                    // com a cor do seu significado.
                    _OutcomeRow(
                      icon: LucideIcons.smartphone,
                      tone: _kWarnTone,
                      title: 'A sessão termina neste aparelho',
                      subtitle:
                          'Você continua conectado onde já estiver logado.',
                    ),
                    const SizedBox(height: 12),
                    _OutcomeRow(
                      icon: biometricEnabled
                          ? LucideIcons.scanFace
                          : LucideIcons.keyRound,
                      tone: biometricEnabled ? _kKeepTone : _kSafeTone,
                      title: biometricEnabled
                          ? 'Face ID / digital continua ativo'
                          : 'Volta com e-mail e senha',
                      subtitle: biometricEnabled
                          ? 'Para voltar, basta um toque na tela de login.'
                          : 'A biometria pode ser ativada depois de entrar.',
                    ),
                    const SizedBox(height: 12),
                    _OutcomeRow(
                      icon: LucideIcons.databaseBackup,
                      tone: _kSafeTone,
                      title: 'Nada é apagado',
                      subtitle:
                          'Leads, imóveis e conversas ficam na sua conta.',
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ),
            // Rodapé: Cancelar NUNCA vermelho (o tema global pinta
            // TextButton de vermelho — forçamos o cinza).
            Container(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                16 + media.padding.bottom * 0.5,
              ),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color:
                        ThemeHelpers.borderColor(context).withValues(alpha: .35),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: TextButton.styleFrom(
                        foregroundColor: secondary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                        textStyle: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Ficar conectado'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kExitTone,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                        textStyle: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      icon: const Icon(LucideIcons.logOut, size: 17),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Sair da conta'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Uma consequência do logout: ícone tonal + título + explicação curta.
class _OutcomeRow extends StatelessWidget {
  final IconData icon;
  final Color tone;
  final String title;
  final String subtitle;

  const _OutcomeRow({
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: tone.withValues(alpha: isDark ? 0.18 : 0.10),
          ),
          child: Icon(icon, size: 15, color: tone),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.1,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
