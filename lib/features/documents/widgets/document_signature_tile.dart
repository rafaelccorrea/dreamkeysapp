import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../models/document_signature_model.dart';

/// Cor e ícone de cada status de assinatura (mesma leitura do web:
/// aguardando = âmbar, visualizado = azul, assinado = verde, rejeitado =
/// vermelho, expirado/cancelado = neutro).
Color signatureStatusColor(BuildContext context, DocumentSignatureStatus s) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  switch (s) {
    case DocumentSignatureStatus.pending:
      return dark ? AppColors.status.warningDarkMode : AppColors.status.warning;
    case DocumentSignatureStatus.viewed:
      return dark ? AppColors.status.infoDarkMode : AppColors.status.info;
    case DocumentSignatureStatus.signed:
      return dark ? AppColors.status.successDarkMode : AppColors.status.success;
    case DocumentSignatureStatus.rejected:
      return dark ? AppColors.status.errorDarkMode : AppColors.status.error;
    case DocumentSignatureStatus.expired:
    case DocumentSignatureStatus.cancelled:
      return ThemeHelpers.textSecondaryColor(context);
  }
}

IconData signatureStatusIcon(DocumentSignatureStatus s) {
  switch (s) {
    case DocumentSignatureStatus.pending:
      return Icons.schedule_rounded;
    case DocumentSignatureStatus.viewed:
      return Icons.visibility_outlined;
    case DocumentSignatureStatus.signed:
      return Icons.check_circle_outline_rounded;
    case DocumentSignatureStatus.rejected:
      return Icons.cancel_outlined;
    case DocumentSignatureStatus.expired:
      return Icons.timer_off_outlined;
    case DocumentSignatureStatus.cancelled:
      return Icons.block_outlined;
  }
}

/// Linha flush de uma assinatura — responde, sem abrir nada, quem assina,
/// em que pé está e o que dá para fazer:
///  - topo: iniciais do signatário (no tom do status), nome, selo do status
///    e a origem (cliente, usuário ou externo) com o e-mail;
///  - trilha: Enviado → Visto → Assinado (ou Rejeitado / Expirou /
///    Cancelado), com a data de cada passo e o prazo quando houver;
///  - motivo da recusa, quando houver;
///  - ações (enviar e reenviar e-mail, copiar link, abrir para assinar). Só
///    aparecem quando o chamador passa o callback — cada tela decide a regra
///    do web que aplica.
class DocumentSignatureTile extends StatelessWidget {
  final DocumentSignature signature;

  /// Título opcional acima do signatário (nome do documento), para quem
  /// mostra a linha fora de um grupo do próprio documento.
  final String? documentTitle;
  final VoidCallback? onTap;

  /// Abre o `signatureUrl` (Autentique) fora do app para assinar.
  final VoidCallback? onOpenLink;
  final VoidCallback? onCopyLink;
  final VoidCallback? onSendEmail;
  final VoidCallback? onResendEmail;

  /// Um e-mail desta assinatura está saindo: as ações travam e a linha
  /// avisa "Enviando e-mail…".
  final bool busy;

  const DocumentSignatureTile({
    super.key,
    required this.signature,
    this.documentTitle,
    this.onTap,
    this.onOpenLink,
    this.onCopyLink,
    this.onSendEmail,
    this.onResendEmail,
    this.busy = false,
  });

  static final DateFormat _hm = DateFormat('HH:mm');
  static final DateFormat _dm = DateFormat('dd/MM');
  static final DateFormat _dmy = DateFormat('dd/MM/yy');

  /// Dias de calendário de hoje até [d] (negativo = passado).
  static int _diasAte(DateTime d) {
    final l = d.toLocal();
    final agora = DateTime.now();
    final diff = DateTime(l.year, l.month, l.day)
        .difference(DateTime(agora.year, agora.month, agora.day));
    return (diff.inHours / 24).round();
  }

  /// Quando um passo aconteceu, do jeito que se fala: "hoje 14:32",
  /// "ontem 09:10", "12/09" ou "12/09/25" (outro ano).
  static String _quando(DateTime d) {
    final l = d.toLocal();
    final dias = _diasAte(l);
    if (dias == 0) return 'hoje ${_hm.format(l)}';
    if (dias == -1) return 'ontem ${_hm.format(l)}';
    return l.year == DateTime.now().year ? _dm.format(l) : _dmy.format(l);
  }

  /// Dia de um prazo: "hoje", "amanhã", "12/09" ou "12/09/27".
  static String _dia(DateTime d) {
    final l = d.toLocal();
    final dias = _diasAte(l);
    if (dias == 0) return 'hoje';
    if (dias == 1) return 'amanhã';
    return l.year == DateTime.now().year ? _dm.format(l) : _dmy.format(l);
  }

  static String _prazo(DateTime? prazo) {
    if (prazo == null) return 'pendente';
    return prazo.isAfter(DateTime.now())
        ? 'até ${_dia(prazo)}'
        : 'venceu ${_dia(prazo)}';
  }

  static String _iniciais(String nome) {
    final partes =
        nome.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return '';
    final primeira = partes.first.characters.first;
    if (partes.length == 1) return primeira.toUpperCase();
    return '$primeira${partes.last.characters.first}'.toUpperCase();
  }

  /// De onde veio o signatário — a mesma divisão da tela de envio.
  String get _origem {
    if ((signature.clientId ?? '').isNotEmpty || signature.client != null) {
      return 'Cliente';
    }
    if ((signature.userId ?? '').isNotEmpty || signature.user != null) {
      return 'Usuário';
    }
    return 'Externo';
  }

  /// Passos da trilha. "Visto" conta como feito quando o status já passou
  /// dele (visualizado, assinado ou rejeitado), mesmo sem a data.
  List<_Etapa> _etapas() {
    final s = signature;
    final viu = s.viewedAt != null ||
        s.status == DocumentSignatureStatus.viewed ||
        s.status == DocumentSignatureStatus.signed ||
        s.status == DocumentSignatureStatus.rejected;
    final fim = switch (s.status) {
      DocumentSignatureStatus.pending ||
      DocumentSignatureStatus.viewed =>
        _Etapa('Assinatura', _prazo(s.expiresAt), _Passo.atual),
      DocumentSignatureStatus.signed => _Etapa(
          'Assinado',
          s.signedAt == null ? null : _quando(s.signedAt!),
          _Passo.feito,
        ),
      DocumentSignatureStatus.rejected => _Etapa(
          'Rejeitado',
          s.rejectedAt == null ? null : _quando(s.rejectedAt!),
          _Passo.feito,
        ),
      DocumentSignatureStatus.expired => _Etapa(
          'Expirou',
          s.expiresAt == null ? null : _dia(s.expiresAt!),
          _Passo.feito,
        ),
      DocumentSignatureStatus.cancelled =>
        const _Etapa('Cancelado', null, _Passo.feito),
    };
    return [
      _Etapa('Enviado', _quando(s.createdAt), _Passo.feito),
      _Etapa(
        'Visto',
        s.viewedAt != null
            ? _quando(s.viewedAt!)
            : (viu ? null : 'ainda não'),
        viu ? _Passo.feito : _Passo.pendente,
      ),
      fim,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cor = signatureStatusColor(context, signature.status);
    final texto = ThemeHelpers.textColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final nome = signature.signerName.trim();
    final iniciais = _iniciais(nome);
    final email = signature.signerEmail.trim();
    final motivo = signature.rejectionReason?.trim() ?? '';
    final corRecusa =
        signatureStatusColor(context, DocumentSignatureStatus.rejected);

    final hasActions = onOpenLink != null ||
        onCopyLink != null ||
        onSendEmail != null ||
        onResendEmail != null;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Quem: iniciais no tom do status (a cor já adianta o pé).
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: cor.withValues(alpha: isDark ? 0.22 : 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: iniciais.isEmpty
                      ? Icon(
                          Icons.person_outline_rounded,
                          size: 18,
                          color: texto,
                        )
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            iniciais,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                              color: texto,
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (documentTitle != null &&
                          documentTitle!.trim().isNotEmpty) ...[
                        Text(
                          documentTitle!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                      ],
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              nome.isEmpty ? 'Signatário sem nome' : nome,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: texto,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _StatusPill(status: signature.status),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        email.isEmpty ? _origem : '$_origem · $email',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _Trilha(etapas: _etapas(), cor: cor),
            if (motivo.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: BoxDecoration(
                  color: corRecusa.withValues(alpha: isDark ? 0.16 : 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 15,
                      color: corRecusa,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(
                              text: 'Motivo da recusa: ',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            TextSpan(text: motivo),
                          ],
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: texto,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (hasActions || busy) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (busy) const _BusyChip(),
                  if (onSendEmail != null)
                    _ActionChip(
                      icon: Icons.mail_outline_rounded,
                      label: 'Enviar e-mail',
                      onTap: busy ? null : onSendEmail,
                    ),
                  if (onResendEmail != null)
                    _ActionChip(
                      icon: Icons.forward_to_inbox_rounded,
                      label: 'Reenviar e-mail',
                      onTap: busy ? null : onResendEmail,
                    ),
                  if (onCopyLink != null)
                    _ActionChip(
                      icon: Icons.link_rounded,
                      label: 'Copiar link',
                      onTap: busy ? null : onCopyLink,
                    ),
                  if (onOpenLink != null)
                    _ActionChip(
                      icon: Icons.open_in_new_rounded,
                      label: 'Abrir para assinar',
                      onTap: busy ? null : onOpenLink,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _Passo { feito, atual, pendente }

class _Etapa {
  final String rotulo;
  final String? quando;
  final _Passo passo;

  const _Etapa(this.rotulo, this.quando, this.passo);
}

/// Trilha de três passos em colunas iguais: ponto + filete até o próximo,
/// rótulo e data embaixo. Feito = ponto cheio no tom do status; o passo em
/// espera = anel no tom; o que não aconteceu = anel neutro.
class _Trilha extends StatelessWidget {
  final List<_Etapa> etapas;
  final Color cor;

  const _Trilha({required this.etapas, required this.cor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final texto = ThemeHelpers.textColor(context);
    final muted = ThemeHelpers.textSecondaryColor(context);
    final neutro = ThemeHelpers.borderColor(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < etapas.length; i++)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: etapas[i].passo == _Passo.feito
                            ? cor
                            : Colors.transparent,
                        border: etapas[i].passo == _Passo.feito
                            ? null
                            : Border.all(
                                color: etapas[i].passo == _Passo.atual
                                    ? cor
                                    : neutro,
                                width: 2,
                              ),
                      ),
                    ),
                    if (i < etapas.length - 1)
                      Expanded(
                        child: Container(
                          height: 2,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: etapas[i + 1].passo == _Passo.feito
                                ? cor
                                : neutro,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    etapas[i].rotulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: etapas[i].passo == _Passo.pendente
                          ? FontWeight.w600
                          : FontWeight.w800,
                      color:
                          etapas[i].passo == _Passo.pendente ? muted : texto,
                    ),
                  ),
                ),
                if (etapas[i].quando != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      etapas[i].quando!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Selo do status: fundo no tom, ícone no tom e rótulo na cor do texto (o
/// âmbar e o azul sobre branco não passam no contraste como texto).
class _StatusPill extends StatelessWidget {
  final DocumentSignatureStatus status;

  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final cor = signatureStatusColor(context, status);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 124),
      child: Container(
        padding: const EdgeInsets.fromLTRB(7, 3, 9, 3),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: isDark ? 0.20 : 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(signatureStatusIcon(status), size: 13, color: cor),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                status.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: ThemeHelpers.textColor(context),
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ação da linha: controle com corpo (fundo tonal neutro), ícone + rótulo.
class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ActionChip({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final texto = ThemeHelpers.textColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ativo = onTap != null;
    final fg = ativo
        ? texto
        : ThemeHelpers.textSecondaryColor(context).withValues(alpha: 0.6);
    return Material(
      color: texto.withValues(alpha: ativo ? (isDark ? 0.09 : 0.06) : 0.03),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BusyChip extends StatelessWidget {
  const _BusyChip();

  @override
  Widget build(BuildContext context) {
    final texto = ThemeHelpers.textColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: texto),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Enviando e-mail…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: texto,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
