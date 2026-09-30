import 'dart:io' show Directory, File;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../features/workspace/models/admin_user_model.dart';
import '../../../features/workspace/models/company_team_model.dart';
import '../../../features/workspace/services/admin_users_service.dart';
import '../../../features/workspace/services/company_team_service.dart';
import '../../../shared/services/sale_forms_service.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../pages/create_sale_form_page.dart';
import '../pages/sale_form_detail_page.dart';
import 'sale_form_row_rules.dart';
import 'sale_form_signatures_sheet.dart';
import 'sale_form_tones.dart';

/// Executa uma ação do menu da ficha (lista e detalhe usam o mesmo caminho,
/// espelho do menu web). Devolve `true` quando a ficha mudou e a tela deve
/// recarregar.
Future<bool> runSaleFormRowAction(
  BuildContext context,
  SaleForm form,
  SaleFormRowAction action,
) async {
  final rules = SaleFormRowRules(form);
  switch (action) {
    case SaleFormRowAction.ver:
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => SaleFormDetailPage(saleFormId: form.id),
        ),
      );
      return changed == true;

    case SaleFormRowAction.usuariosVinculados:
      await _showLinkedUsers(context, form);
      return false;

    case SaleFormRowAction.motivo:
      final m = rules.auditMotivo;
      if (m != null) await _showTextSheet(context, m.title, m.body);
      return false;

    case SaleFormRowAction.pdfSistema:
      await openSaleFormPdf(context, form, 'sistema');
      return false;

    case SaleFormRowAction.pdfAssinaturas:
      await openSaleFormPdf(context, form, 'assinaturas');
      return false;

    case SaleFormRowAction.assinaturas:
      var changed = false;
      await showSaleFormSignaturesSheet(
        context,
        saleFormId: form.id,
        formNumber: form.formNumber,
        canInvalidate: rules.canCancelSignaturesForResend,
        onChanged: () => changed = true,
      );
      return changed;

    case SaleFormRowAction.cancelarAssinaturas:
      final ok = await _confirm(
        context,
        title: 'Cancelar assinaturas (reenvio)',
        message:
            'As assinaturas da ficha nº ${form.formNumber} serão invalidadas no Autentique. Depois disso a ficha pode ser editada e enviada de novo.',
        confirmLabel: 'Cancelar assinaturas',
        danger: true,
      );
      if (!ok || !context.mounted) return false;
      final res = await SaleFormsService.instance.invalidarAssinaturas(form.id);
      if (!context.mounted) return false;
      _snack(
        context,
        res.success
            ? 'Assinaturas canceladas. A ficha pode ser editada e reenviada.'
            : (res.message ?? 'Falha ao cancelar as assinaturas.'),
        ok: res.success,
      );
      return res.success;

    case SaleFormRowAction.editar:
      final motivo = rules.editBlockReason;
      if (motivo != null) {
        await _showTextSheet(context, 'Edição bloqueada', motivo);
        return false;
      }
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => CreateSaleFormPage(saleFormId: form.id),
        ),
      );
      return changed == true;

    case SaleFormRowAction.trocarEquipe:
      final team = await _pickTeam(context, currentTeamId: form.teamId);
      if (team == null || !context.mounted) return false;
      final res =
          await SaleFormsService.instance.alterarEquipe(form.id, team.id);
      if (!context.mounted) return false;
      _snack(
        context,
        res.success
            ? 'Equipe alterada para ${team.name}.'
            : (res.message ?? 'Falha ao trocar a equipe.'),
        ok: res.success,
      );
      return res.success;

    case SaleFormRowAction.transferir:
      final user = await _pickUser(
        context,
        excludeUserId: form.raw['userId']?.toString(),
        title: 'Transferir responsabilidade',
        help:
            'Ficha nº ${form.formNumber} — o novo usuário passará a ser o criador da ficha no sistema (e propostas vinculadas com o mesmo criador, se houver).',
      );
      if (user == null || !context.mounted) return false;
      final res = await SaleFormsService.instance
          .transferirResponsabilidade(form.id, user.id);
      if (!context.mounted) return false;
      _snack(
        context,
        res.success
            ? 'Responsabilidade transferida para ${user.name}.'
            : (res.message ?? 'Falha ao transferir.'),
        ok: res.success,
      );
      return res.success;

    case SaleFormRowAction.distrato:
      final reason = await askSaleFormReason(
        context,
        title: 'Distratar ficha de venda',
        message:
            'A venda será cancelada no Financeiro por distrato. Confirma o distrato da ficha nº ${form.formNumber}? O Financeiro conclui com o contrato de distrato ou o comprovante de arquivamento no PipeImob; até lá os envolvidos são lembrados todo dia.',
        confirmLabel: 'Distratar',
      );
      if (reason == null || !context.mounted) return false;
      final res =
          await SaleFormsService.instance.abrirDistrato(form.id, reason);
      if (!context.mounted) return false;
      _snack(
        context,
        res.success
            ? 'Distrato aberto. O Financeiro foi avisado.'
            : (res.message ?? 'Falha ao abrir o distrato.'),
        ok: res.success,
      );
      return res.success;

    case SaleFormRowAction.cancelarFicha:
      final reason = await askSaleFormReason(
        context,
        title: 'Cancelar ficha de venda',
        message:
            'A ficha nº ${form.formNumber} será cancelada e não poderá mais ser enviada para assinatura.',
        confirmLabel: 'Cancelar ficha',
      );
      if (reason == null || !context.mounted) return false;
      final res = await SaleFormsService.instance.cancelar(form.id, reason);
      if (!context.mounted) return false;
      _snack(
        context,
        res.success ? 'Ficha cancelada.' : (res.message ?? 'Falha ao cancelar.'),
        ok: res.success,
      );
      return res.success;

    case SaleFormRowAction.excluir:
      final reason = await askSaleFormReason(
        context,
        title: 'Excluir ficha de venda',
        message:
            'Excluir a ficha nº ${form.formNumber}? Esta ação fica em auditoria.',
        confirmLabel: 'Excluir',
      );
      if (reason == null || !context.mounted) return false;
      final res = await SaleFormsService.instance.excluir(form.id, reason);
      if (!context.mounted) return false;
      _snack(
        context,
        res.success ? 'Ficha excluída.' : (res.message ?? 'Falha ao excluir.'),
        ok: res.success,
      );
      return res.success;
  }
}

/// Baixa e abre o PDF da ficha (`sistema` = sem assinatura; `assinaturas` =
/// PDF(s) assinado(s) no Autentique — ZIP quando há mais de um).
Future<void> openSaleFormPdf(
  BuildContext context,
  SaleForm form,
  String modo,
) async {
  _snack(context, 'Gerando o PDF…', ok: true, curto: true);
  final res = await SaleFormsService.instance.downloadPdf(form.id, modo: modo);
  if (!context.mounted) return;
  if (!res.success || res.data == null) {
    _snack(context, res.message ?? 'Erro ao baixar o PDF.');
    return;
  }
  try {
    final ext = res.data!.contentType.contains('zip') ? 'zip' : 'pdf';
    final num = form.formNumber.trim().isNotEmpty ? form.formNumber : form.id;
    final file = File(
      '${Directory.systemTemp.path}/ficha_venda_${num}_$modo.$ext',
    );
    await file.writeAsBytes(res.data!.bytes);
    final ok = await launchUrl(
      Uri.file(file.path),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) _snack(context, 'PDF salvo em ${file.path}');
  } catch (e) {
    if (context.mounted) _snack(context, 'Erro ao abrir o PDF: $e');
  }
}

/// Motivo obrigatório (cancelar, excluir, distratar) — mesmo diálogo do web.
Future<String?> askSaleFormReason(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final controller = TextEditingController();
  final muted = ThemeHelpers.textSecondaryColor(context);
  final danger = Theme.of(context).brightness == Brightness.dark
      ? AppColors.status.errorDarkMode
      : AppColors.status.error;
  final res = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        backgroundColor: ThemeHelpers.cardBackgroundColor(ctx),
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message, style: TextStyle(color: muted, height: 1.4)),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                onChanged: (_) => setLocal(() {}),
                decoration: const InputDecoration(
                  labelText: 'Motivo *',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: muted),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Voltar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: danger,
              foregroundColor: Colors.white,
            ),
            onPressed: controller.text.trim().isEmpty
                ? null
                : () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  return res;
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool danger = false,
}) async {
  final muted = ThemeHelpers.textSecondaryColor(context);
  final dark = Theme.of(context).brightness == Brightness.dark;
  // Confirmar = verde cheio nos dois temas (o verde claro do escuro deixa o
  // texto branco ilegível); destrutivo = vermelho.
  final tone = danger
      ? (dark ? AppColors.status.errorDarkMode : AppColors.status.error)
      : SaleFormTom.verdeDeConfirmar();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ThemeHelpers.cardBackgroundColor(ctx),
      title: Text(title),
      content: Text(message, style: TextStyle(color: muted, height: 1.4)),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: muted),
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Voltar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: tone,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

void _snack(
  BuildContext context,
  String msg, {
  bool ok = false,
  bool curto = false,
}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      content: Text(msg),
      duration: Duration(seconds: curto ? 2 : 4),
      backgroundColor: ok ? AppColors.status.success : AppColors.status.error,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

// ── Sheets ─────────────────────────────────────────────────────────────────

/// Casca comum: cabeçalho à esquerda + fechar à direita, teto de altura,
/// corpo rolável (nunca estoura em tela baixa/landscape).
Future<T?> _sheet<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required Widget Function(BuildContext ctx) body,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: ThemeHelpers.cardBackgroundColor(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) {
      final mq = MediaQuery.of(ctx);
      // Pouca altura útil (teclado aberto em paisagem, tela baixa): o
      // cabeçalho encolhe para o corpo continuar com espaço para rolar.
      final apertado = mq.size.height - mq.viewInsets.bottom < 420;
      return AnimatedPadding(
        duration: const Duration(milliseconds: 160),
        padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: mq.size.height * 0.88),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  apertado ? 10 : 16,
                  8,
                  apertado ? 6 : 10,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: apertado ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: ThemeHelpers.textColor(ctx),
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              maxLines: apertado ? 2 : null,
                              overflow: apertado ? TextOverflow.ellipsis : null,
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.35,
                                color: ThemeHelpers.textSecondaryColor(ctx),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fechar',
                      onPressed: () => Navigator.pop(ctx),
                      icon: Icon(
                        LucideIcons.x,
                        size: 20,
                        color: ThemeHelpers.textSecondaryColor(ctx),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(child: body(ctx)),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> _showTextSheet(
  BuildContext context,
  String title,
  String body,
) {
  return _sheet<void>(
    context,
    title: title,
    body: (ctx) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Text(
        body,
        style: TextStyle(
          fontSize: 14,
          height: 1.5,
          color: ThemeHelpers.textColor(ctx),
        ),
      ),
    ),
  );
}

Future<void> _showLinkedUsers(BuildContext context, SaleForm form) {
  return showFichaPeopleSheet(
    context,
    title: 'Usuários vinculados',
    subtitle:
        'Ficha nº ${form.formNumber} — quem pode ver e acompanhar esta ficha.',
    emptyText: 'Nenhum usuário vinculado além de quem criou a ficha.',
    load: () async {
      final res = await SaleFormsService.instance.getById(form.id);
      if (!res.success || res.data == null) {
        throw res.message ?? 'Não foi possível carregar os usuários.';
      }
      return linkedUsersFromRaw(res.data!.raw['linkedUsers']);
    },
  );
}

/// `linkedUsers: [{ userId, user: { name, email } }]` (venda e proposta).
List<({String name, String? email})> linkedUsersFromRaw(dynamic raw) {
  final users = <({String name, String? email})>[];
  if (raw is! List) return users;
  for (final e in raw) {
    if (e is! Map) continue;
    final u = e['user'];
    final nome = (u is Map ? u['name'] : null)?.toString().trim() ?? '';
    final id = e['userId']?.toString() ?? '';
    // Sem nome no cadastro: rótulo legível (id não vai para a tela); o
    // e-mail, quando vem, aparece embaixo e diferencia um do outro.
    final name = nome.isNotEmpty
        ? nome
        : (id.isEmpty ? '' : 'Usuário sem nome no cadastro');
    if (name.isEmpty) continue;
    users.add((
      name: name,
      email: (u is Map ? u['email'] : null)?.toString(),
    ));
  }
  return users;
}

/// Folha de texto (motivo, edição bloqueada) — pública para a proposta.
Future<void> showFichaTextSheet(
  BuildContext context,
  String title,
  String body,
) =>
    _showTextSheet(context, title, body);

/// Folha com lista de pessoas carregada sob demanda (usuários vinculados).
Future<void> showFichaPeopleSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required String emptyText,
  required Future<List<({String name, String? email})>> Function() load,
}) {
  return _sheet<void>(
    context,
    title: title,
    subtitle: subtitle,
    body: (ctx) => _PessoasCorpo(load: load, emptyText: emptyText),
  );
}

/// Corpo da folha de pessoas: esqueleto das linhas enquanto carrega, erro
/// com "Tentar de novo" (chama o mesmo [load]) e vazio com ícone.
class _PessoasCorpo extends StatefulWidget {
  const _PessoasCorpo({required this.load, required this.emptyText});
  final Future<List<({String name, String? email})>> Function() load;
  final String emptyText;

  @override
  State<_PessoasCorpo> createState() => _PessoasCorpoState();
}

class _PessoasCorpoState extends State<_PessoasCorpo> {
  late Future<List<({String name, String? email})>> _fut = widget.load();

  void _tentarDeNovo() => setState(() => _fut = widget.load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<({String name, String? email})>>(
      future: _fut,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _LinhasSkeleton();
        }
        if (snap.hasError) {
          return _AvisoSheet(
            icon: LucideIcons.circleAlert,
            texto: snap.error.toString(),
            acao: 'Tentar de novo',
            onAcao: _tentarDeNovo,
          );
        }
        final users = snap.data ?? const [];
        if (users.isEmpty) {
          return _AvisoSheet(
            icon: LucideIcons.usersRound,
            texto: widget.emptyText,
          );
        }
        return ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          itemCount: users.length,
          separatorBuilder: (_, _) => Divider(
            height: 1,
            color: ThemeHelpers.borderLightColor(ctx),
          ),
          itemBuilder: (ctx, i) => _PessoaLinha(
            nome: users[i].name,
            apoio: users[i].email,
          ),
        );
      },
    );
  }
}

Future<CompanyTeam?> _pickTeam(
  BuildContext context, {
  String? currentTeamId,
}) {
  return _sheet<CompanyTeam>(
    context,
    title: 'Trocar equipe',
    subtitle:
        'Só equipes ativas que participam de fichas de venda. A troca é registrada na auditoria.',
    body: (ctx) => _EquipesCorpo(currentTeamId: currentTeamId),
  );
}

/// Lista de equipes da troca: esqueleto, erro com a causa real (código HTTP
/// preservado) e "Tentar de novo", vazio que explica. A equipe atual fica
/// marcada e não é tocável.
class _EquipesCorpo extends StatefulWidget {
  const _EquipesCorpo({this.currentTeamId});
  final String? currentTeamId;

  @override
  State<_EquipesCorpo> createState() => _EquipesCorpoState();
}

class _EquipesCorpoState extends State<_EquipesCorpo> {
  bool _loading = true;
  String? _erro;
  int _erroStatus = 0;
  List<CompanyTeam> _teams = const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    final res = await CompanyTeamService.instance.listTeams(
      status: 'active',
      limit: 100,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _teams = res.data!.teams
            .where((t) => t.isActive && t.useInSaleForms)
            .toList();
      } else {
        _erro = res.message ?? 'Não foi possível carregar as equipes.';
        _erroStatus = res.statusCode;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _LinhasSkeleton();
    if (_erro != null) {
      return SingleChildScrollView(
        child: AppErrorState.fromApi(
          message: _erro,
          statusCode: _erroStatus,
          onRetry: _carregar,
          dense: true,
        ),
      );
    }
    if (_teams.isEmpty) {
      return const _AvisoSheet(
        icon: LucideIcons.usersRound,
        texto: 'Nenhuma equipe ativa participa de fichas de venda. Isso se '
            'ajusta no cadastro de cada equipe.',
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: _teams.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: ThemeHelpers.borderLightColor(context),
      ),
      itemBuilder: (ctx, i) {
        final t = _teams[i];
        final atual = t.id == widget.currentTeamId;
        return _PessoaLinha(
          nome: t.name,
          apoio: atual ? 'Equipe atual' : null,
          cor: _hex(t.color),
          marcado: atual,
          onTap: atual ? null : () => Navigator.pop(ctx, t),
        );
      },
    );
  }
}

Future<AdminUser?> _pickUser(
  BuildContext context, {
  String? excludeUserId,
  required String title,
  String? help,
}) {
  return _sheet<AdminUser>(
    context,
    title: title,
    subtitle: help,
    body: (ctx) => _UserPicker(excludeUserId: excludeUserId),
  );
}

class _UserPicker extends StatefulWidget {
  const _UserPicker({this.excludeUserId});
  final String? excludeUserId;

  @override
  State<_UserPicker> createState() => _UserPickerState();
}

class _UserPickerState extends State<_UserPicker> {
  final _search = TextEditingController();
  List<AdminUser> _all = const [];
  bool _loading = true;
  String? _error;
  int _errorStatus = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_loading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final res = await AdminUsersService.instance.listUsers(
      page: 1,
      limit: 500,
      compact: true,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success && res.data != null) {
        _error = null;
        _all = res.data!.users
            .where((u) => u.id != widget.excludeUserId && u.isActiveInCompany)
            .toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      } else {
        _error = res.message ?? 'Erro ao carregar usuários da empresa.';
        _errorStatus = res.statusCode;
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final list = q.isEmpty
        ? _all
        : _all
            .where((u) =>
                u.name.toLowerCase().contains(q) ||
                u.email.toLowerCase().contains(q))
            .toList();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent =
        isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;
    final hair = ThemeHelpers.borderLightColor(context);
    OutlineInputBorder borda(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c, width: w),
        );
    final Widget corpo;
    if (_loading) {
      corpo = const _LinhasSkeleton();
    } else if (_error != null) {
      corpo = SingleChildScrollView(
        child: AppErrorState.fromApi(
          message: _error,
          statusCode: _errorStatus,
          onRetry: _load,
          dense: true,
        ),
      );
    } else if (list.isEmpty) {
      corpo = _AvisoSheet(
        icon: LucideIcons.searchX,
        texto: q.isEmpty
            ? 'Nenhum outro usuário ativo na empresa.'
            : 'Ninguém encontrado para "${_search.text.trim()}". Confira o '
                'nome ou busque pelo e-mail.',
      );
    } else {
      corpo = ListView.separated(
        shrinkWrap: true,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: list.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          color: ThemeHelpers.borderLightColor(context),
        ),
        itemBuilder: (ctx, i) => _PessoaLinha(
          nome: list[i].name,
          apoio: list[i].email,
          onTap: () => Navigator.pop(ctx, list[i]),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Buscar por nome ou e-mail',
              isDense: true,
              prefixIcon: Icon(LucideIcons.search, size: 18, color: accent),
              filled: true,
              fillColor: isDark
                  ? AppColors.background.backgroundTertiaryDarkMode
                  : AppColors.background.backgroundTertiary,
              contentPadding: const EdgeInsets.symmetric(vertical: 13),
              border: borda(hair),
              enabledBorder: borda(hair),
              focusedBorder: borda(accent.withValues(alpha: 0.65), 1.4),
            ),
          ),
        ),
        Flexible(child: corpo),
      ],
    );
  }
}

/// Linha flush com avatar de iniciais (pessoa) ou ponto de cor (equipe).
/// [marcado] = a escolha atual (check no lugar do chevron, sem toque).
class _PessoaLinha extends StatelessWidget {
  const _PessoaLinha({
    required this.nome,
    this.apoio,
    this.cor,
    this.onTap,
    this.marcado = false,
  });
  final String nome;
  final String? apoio;
  final Color? cor;
  final VoidCallback? onTap;
  final bool marcado;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    final partes = nome.trim().split(RegExp(r'\s+'));
    final ini = partes.isEmpty || partes.first.isEmpty
        ? '?'
        : (partes.length == 1
                ? partes.first[0]
                : '${partes.first[0]}${partes.last[0]}')
            .toUpperCase();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (cor ?? muted).withValues(alpha: 0.14),
                border: Border.all(
                  color: (cor ?? muted).withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                ini,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: cor ?? ThemeHelpers.textColor(context),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nome,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: ThemeHelpers.textColor(context),
                    ),
                  ),
                  if (apoio != null && apoio!.isNotEmpty)
                    Text(
                      apoio!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                ],
              ),
            ),
            if (marcado)
              Icon(
                LucideIcons.circleCheck,
                size: 18,
                color: SaleFormTom.sucesso(context).texto,
              )
            else if (onTap != null)
              Icon(LucideIcons.chevronRight, size: 18, color: muted),
          ],
        ),
      ),
    );
  }
}

/// Esqueleto das linhas de pessoa/equipe (avatar + nome + linha de apoio).
class _LinhasSkeleton extends StatelessWidget {
  const _LinhasSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        for (var i = 0; i < 4; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              children: const [
                SkeletonBox(width: 36, height: 36, borderRadius: 18),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 150, height: 13, borderRadius: 6),
                      SizedBox(height: 6),
                      SkeletonBox(width: 190, height: 11, borderRadius: 6),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Vazio ou erro dentro de uma folha: ícone, frase e (opcional) uma ação
/// neutra.
class _AvisoSheet extends StatelessWidget {
  const _AvisoSheet({
    required this.icon,
    required this.texto,
    this.acao,
    this.onAcao,
  });
  final IconData icon;
  final String texto;
  final String? acao;
  final VoidCallback? onAcao;

  @override
  Widget build(BuildContext context) {
    final muted = ThemeHelpers.textSecondaryColor(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 26, color: muted),
          const SizedBox(height: 10),
          Text(
            texto,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.4, color: muted),
          ),
          if (acao != null && onAcao != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onAcao,
              icon: const Icon(LucideIcons.rotateCw, size: 16),
              label: Text(acao!),
              style: OutlinedButton.styleFrom(
                foregroundColor: ThemeHelpers.textColor(context),
                side: BorderSide(color: ThemeHelpers.borderColor(context)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Color? _hex(String? v) {
  final s = (v ?? '').replaceAll('#', '').trim();
  if (s.length != 6) return null;
  final n = int.tryParse(s, radix: 16);
  return n == null ? null : Color(0xFF000000 | n);
}
