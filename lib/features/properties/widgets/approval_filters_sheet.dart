import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/theme_helpers.dart';
import '../services/property_approval_service.dart';
import 'approval_actions_sheet.dart';

/// Tom dos filtros — índigo. Filtro não é aprovação nem risco: fica fora das
/// famílias verde/âmbar/vermelho para não competir com o significado delas.
const Color _kFiltersTone = Color(0xFF4F46E5);

/// Filtros avançados das filas de aprovação.
///
/// Paridade com o painel de filtros do web: os campos granulares
/// (responsável, código, título, proprietário) só valem quando a busca global
/// está vazia — é a mesma regra do `mergePendingTextQuery`, já implementada
/// em [ApprovalListFilters.toQueryParams]. Por isso o sheet avisa quando a
/// busca global está preenchida: ali os granulares são ignorados pela API.
///
/// Devolve `null` se o usuário fechar sem aplicar; devolve
/// [ApprovalListFilters.empty] quando ele limpa tudo.
Future<ApprovalListFilters?> showApprovalFiltersSheet({
  required BuildContext context,
  required ApprovalListFilters current,
  required bool globalSearchActive,
}) {
  return showModalBottomSheet<ApprovalListFilters>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ApprovalFiltersSheet(
      current: current,
      globalSearchActive: globalSearchActive,
    ),
  );
}

class _ApprovalFiltersSheet extends StatefulWidget {
  final ApprovalListFilters current;
  final bool globalSearchActive;

  const _ApprovalFiltersSheet({
    required this.current,
    required this.globalSearchActive,
  });

  @override
  State<_ApprovalFiltersSheet> createState() => _ApprovalFiltersSheetState();
}

class _ApprovalFiltersSheetState extends State<_ApprovalFiltersSheet> {
  late final TextEditingController _responsible;
  late final TextEditingController _code;
  late final TextEditingController _title;
  late final TextEditingController _owner;

  @override
  void initState() {
    super.initState();
    _responsible = TextEditingController(text: widget.current.responsibleName);
    _code = TextEditingController(text: widget.current.propertyCode);
    _title = TextEditingController(text: widget.current.propertyTitle);
    _owner = TextEditingController(text: widget.current.ownerName);
  }

  @override
  void dispose() {
    _responsible.dispose();
    _code.dispose();
    _title.dispose();
    _owner.dispose();
    super.dispose();
  }

  String? _clean(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  void _apply() {
    Navigator.of(context).pop(
      ApprovalListFilters(
        responsibleName: _clean(_responsible),
        propertyCode: _clean(_code),
        propertyTitle: _clean(_title),
        ownerName: _clean(_owner),
        // Preserva os vínculos que não são editáveis por texto.
        teamId: widget.current.teamId,
        responsibleUserId: widget.current.responsibleUserId,
      ),
    );
  }

  void _clearAll() {
    _responsible.clear();
    _code.clear();
    _title.clear();
    _owner.clear();
    setState(() {});
  }

  bool get _anyFilled =>
      _responsible.text.trim().isNotEmpty ||
      _code.text.trim().isNotEmpty ||
      _title.text.trim().isNotEmpty ||
      _owner.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Teto de 0.85 da tela + o teclado: o sheet nunca fica atrás do teclado
    // nem estoura em aparelho pequeno.
    final maxHeight = media.size.height * 0.85;
    final cardColor = ThemeHelpers.cardBackgroundColor(context);

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(22),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ApprovalSheetGrabber(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 12, 14),
                child: ApprovalSheetHeader(
                  eyebrow: 'Refinar',
                  title: 'Filtros da fila',
                  subtitle:
                      'Combine os campos para estreitar a lista da aba atual.',
                  tone: _kFiltersTone,
                  icon: LucideIcons.slidersHorizontal,
                ),
              ),
              const ApprovalSheetDivider(tone: _kFiltersTone),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.globalSearchActive) ...[
                        _GlobalSearchNotice(),
                        const SizedBox(height: 16),
                      ],
                      _FilterField(
                        controller: _responsible,
                        label: 'Responsável',
                        hint: 'Nome do corretor responsável',
                        icon: LucideIcons.userRound,
                        onChanged: () => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      _FilterField(
                        controller: _code,
                        label: 'Código do imóvel',
                        hint: 'Ex.: 30224',
                        icon: LucideIcons.hash,
                        keyboardType: TextInputType.text,
                        onChanged: () => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      _FilterField(
                        controller: _title,
                        label: 'Título do imóvel',
                        hint: 'Parte do título do anúncio',
                        icon: LucideIcons.house,
                        onChanged: () => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      _FilterField(
                        controller: _owner,
                        label: 'Proprietário',
                        hint: 'Nome do proprietário',
                        icon: LucideIcons.userCheck,
                        onChanged: () => setState(() {}),
                      ),
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _anyFilled ? _clearAll : null,
                          style: TextButton.styleFrom(
                            // Limpar não é destrutivo — cinza, nunca vermelho
                            // (o tema global pinta TextButton de vermelho).
                            foregroundColor:
                                ThemeHelpers.textSecondaryColor(context),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: const Icon(LucideIcons.eraser, size: 15),
                          label: const Text(
                            'Limpar filtros',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              ),
              ApprovalSheetFooter(
                confirmLabel: 'Aplicar filtros',
                confirmIcon: LucideIcons.check,
                confirmColor: kApprovalGreen,
                submitting: false,
                onConfirm: _apply,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Aviso de que a busca global vence os campos granulares — a mesma regra que
/// a API aplica. Sem isto o usuário preenche quatro campos e não entende por
/// que a lista não mudou.
class _GlobalSearchNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const amber = Color(0xFFD97706);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: amber.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.info, size: 15, color: amber),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'A busca do topo está preenchida e tem prioridade: enquanto '
              'houver texto nela, estes campos são ignorados.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final VoidCallback onChanged;

  const _FilterField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.onChanged,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = ThemeHelpers.textColor(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final filled = controller.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 13,
              color: filled ? _kFiltersTone : secondary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  color: filled ? _kFiltersTone : secondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textInputAction: TextInputAction.next,
          cursorColor: _kFiltersTone,
          onChanged: (_) => onChanged(),
          style: TextStyle(
            color: textColor,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: secondary.withValues(alpha: 0.7),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            isDense: true,
            filled: true,
            fillColor: isDark
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.black.withValues(alpha: 0.03),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: filled
                    ? _kFiltersTone.withValues(alpha: 0.45)
                    : ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: _kFiltersTone.withValues(alpha: 0.75),
                width: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
