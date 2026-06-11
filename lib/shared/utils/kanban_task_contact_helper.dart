import '../../features/kanban/models/kanban_models.dart';

/// Extrai nome/telefone do lead a partir do card do funil.
class KanbanTaskContactHelper {
  KanbanTaskContactHelper._();

  static String leadDisplayName(KanbanTask task) {
    for (final c in task.contacts ?? const <KanbanTaskContactInput>[]) {
      final n = c.name?.trim();
      if (n != null && n.isNotEmpty) return n;
    }
    return task.title.trim().isNotEmpty ? task.title.trim() : 'Lead';
  }

  static String? leadPhone(KanbanTask task) {
    for (final c in task.contacts ?? const <KanbanTaskContactInput>[]) {
      final p = _digits(c.phone);
      if (p.length >= 10) return p;
    }
    final fromDesc = _extractPhone(task.description ?? '');
    if (fromDesc != null) return fromDesc;
    return _extractPhone(task.title);
  }

  static String? propertyHint(KanbanTask task) {
    final project = task.project?.name.trim();
    if (project != null && project.isNotEmpty) return project;
    final tags = task.displayTags;
    if (tags != null && tags.isNotEmpty) return tags.first;
    return null;
  }

  static String _digits(String? raw) =>
      (raw ?? '').replaceAll(RegExp(r'\D'), '');

  static String? _extractPhone(String text) {
    final match = RegExp(
      r'(?:\+?55\s?)?(?:\(?\d{2}\)?\s?)?\d{4,5}[-\s]?\d{4}',
    ).firstMatch(text);
    if (match == null) return null;
    final d = _digits(match.group(0));
    return d.length >= 10 ? d : null;
  }
}
