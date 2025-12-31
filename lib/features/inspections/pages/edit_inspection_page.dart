import 'package:flutter/material.dart';
import '../../../shared/widgets/app_scaffold.dart';

/// Página de edição de vistoria
class EditInspectionPage extends StatelessWidget {
  final String inspectionId;

  const EditInspectionPage({
    super.key,
    required this.inspectionId,
  });

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Editar Vistoria',
      body: Center(
        child: Text('Formulário de edição da vistoria: $inspectionId'),
      ),
    );
  }
}
