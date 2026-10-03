import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/theme_helpers.dart';
import '../../core/finance_errors.dart';
import '../services/meu_financeiro_service.dart';
import 'meu_financeiro_widgets.dart';

/// Abre uma folha modal alta (90 %) do Financeiro.
Future<T?> showFinanceSheet<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext, ScrollController) builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scroll) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ThemeHelpers.borderLightColor(ctx),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                        color: ThemeHelpers.textColor(ctx),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(LucideIcons.x, size: 20),
                  ),
                ],
              ),
            ),
            Expanded(child: builder(ctx, scroll)),
          ],
        ),
      ),
    ),
  );
}

/// Conteúdo que carrega uma [Section] ao abrir (esqueleto → dado | erro).
class FinanceAsyncBody<T> extends StatefulWidget {
  final Future<Section<T>> Function() load;
  final Widget Function(BuildContext, T) builder;
  final ScrollController? scroll;

  const FinanceAsyncBody({
    super.key,
    required this.load,
    required this.builder,
    this.scroll,
  });

  @override
  State<FinanceAsyncBody<T>> createState() => _FinanceAsyncBodyState<T>();
}

class _FinanceAsyncBodyState<T> extends State<FinanceAsyncBody<T>> {
  Section<T>? _res;

  @override
  void initState() {
    super.initState();
    _go();
  }

  Future<void> _go() async {
    if (_res != null) setState(() => _res = null);
    final r = await widget.load();
    if (mounted) setState(() => _res = r);
  }

  @override
  Widget build(BuildContext context) {
    final r = _res;
    if (r == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }
    if (!r.ok || r.data == null) {
      final e = r.error;
      return ListView(
        controller: widget.scroll,
        padding: const EdgeInsets.all(20),
        children: [
          FinanceInlineNotice(
            text: e?.kind == FinanceErrorKind.notFound
                ? (e!.message.isEmpty ? 'Não encontrado.' : e.message)
                : (e?.message ?? 'Não foi possível carregar.'),
            onRetry: _go,
          ),
        ],
      );
    }
    return widget.builder(context, r.data as T);
  }
}

/// Bloco "rótulo: valor" das folhas de detalhe.
class FinanceField extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;

  const FinanceField(
    this.label,
    this.value, {
    super.key,
    this.valueColor,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: valueColor ?? ThemeHelpers.textColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Título de bloco (caixa alta) das folhas.
class FinanceBlockTitle extends StatelessWidget {
  final String text;
  const FinanceBlockTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w800,
          color: financeAccent(context),
        ),
      ),
    );
  }
}
