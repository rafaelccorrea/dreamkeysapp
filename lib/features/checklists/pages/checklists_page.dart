import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';
import '../../../../shared/services/module_access_service.dart';
import '../../../../shared/services/sale_checklists_service.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/vivid_chrome.dart';

/// Lista de checklists (`GET /sale-checklists`).
class ChecklistsPage extends StatefulWidget {
  const ChecklistsPage({super.key});

  @override
  State<ChecklistsPage> createState() => _ChecklistsPageState();
}

class _ChecklistsPageState extends State<ChecklistsPage> {
  List<SaleChecklistListItem>? _items;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await SaleChecklistsService.instance.listChecklists();
    if (!mounted) return;
    if (r.success && r.data != null) {
      setState(() {
        _items = r.data;
        _loading = false;
      });
    } else {
      setState(() {
        _error = r.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).brightness == Brightness.dark
        ? AppColors.primary.primaryDarkMode
        : AppColors.primary.primary;

    final can = ModuleAccessService.instance
        .hasCompanyModule('checklist_management');

    return AppScaffold(
      title: 'Checklists',
      currentBottomNavIndex: -1,
      showBottomNavigation: false,
      body: !can
          ? ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                VividChrome.heroBanner(
                  context,
                  accent: accent,
                  eyebrow: 'Produtividade',
                  title: 'Checklists',
                  subtitle:
                      'O módulo checklist_management tem de estar ativo na empresa.',
                  icon: Icons.lock_outline_rounded,
                ),
                const SizedBox(height: 16),
                VividChrome.mutedMessage(
                  context,
                  'Sem acesso ao módulo de checklists.',
                  accent: accent,
                ),
              ],
            )
          : RefreshIndicator(
              color: accent,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  VividChrome.heroBanner(
                    context,
                    accent: accent,
                    eyebrow: 'Produtividade',
                    title: 'Checklists',
                    subtitle:
                        'Listas de venda — dados de GET /sale-checklists (somente leitura).',
                    icon: Icons.checklist_rtl_rounded,
                  ),
                  const SizedBox(height: 14),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_error != null)
                    VividChrome.mutedMessage(
                      context,
                      _error!,
                      accent: accent,
                    )
                  else if (_items == null || _items!.isEmpty)
                    VividChrome.mutedMessage(
                      context,
                      'Nenhum checklist encontrado.',
                      accent: accent,
                    )
                  else
                    ...List.generate(_items!.length, (i) {
                      final c = _items![i];
                      return Padding(
                        padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            color: ThemeHelpers.cardBackgroundColor(context),
                            border: Border.all(
                              color: accent.withValues(alpha: 0.22),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.05),
                                blurRadius: 14,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${c.type.toUpperCase()} · ${c.status}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${c.itemsCount} itens',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: accent,
                                ),
                              ),
                              if (c.notes != null &&
                                  c.notes!.trim().isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  c.notes!.trim(),
                                  style: TextStyle(
                                    color: ThemeHelpers.textSecondaryColor(
                                      context,
                                    ),
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
