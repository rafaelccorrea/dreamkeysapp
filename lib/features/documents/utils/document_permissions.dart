import '../../../shared/services/module_access_service.dart';

/// Permissões do módulo de documentos — espelho do `useDocumentPermissions`
/// do web (`imobx-front/src/hooks/useDocumentPermissions.ts`).
///
/// As rotas do web exigem o módulo `document_management` da empresa mais a
/// permissão da tela; as ações da biblioteca usam `canCreate`, `canUpdate`,
/// `canDelete`, `canApprove` e `canDownload`.
class DocumentPermissions {
  DocumentPermissions._();

  static const String moduleId = 'document_management';

  static const String view = 'document:read';
  static const String create = 'document:create';
  static const String update = 'document:update';
  static const String delete = 'document:delete';
  static const String approve = 'document:approve';
  static const String download = 'document:download';

  static ModuleAccessService get _m => ModuleAccessService.instance;

  static bool get moduleEnabled => _m.hasCompanyModule(moduleId);

  static bool get canView => _m.hasPermission(view);
  static bool get canCreate => _m.hasPermission(create);
  static bool get canUpdate => _m.hasPermission(update);
  static bool get canDelete => _m.hasPermission(delete);
  static bool get canApprove => _m.hasPermission(approve);
  static bool get canDownload => _m.hasPermission(download);

  /// Porta da biblioteca: módulo contratado + `document:read`.
  static bool get canOpenLibrary => moduleEnabled && canView;

  /// Revisão de item da pasta CRM: o back aceita `document:approve` ou
  /// `kanban:update` (além de admin e do responsável pelo card).
  static bool get canReviewFolderItems =>
      _m.hasPermission(approve) || _m.hasPermission('kanban:update');
}
