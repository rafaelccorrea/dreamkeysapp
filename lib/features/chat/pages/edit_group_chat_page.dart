import 'package:flutter/material.dart';
import '../../../shared/widgets/app_scaffold.dart';

/// Página para editar configurações de um grupo
class EditGroupChatPage extends StatefulWidget {
  final String roomId;

  const EditGroupChatPage({super.key, required this.roomId});

  @override
  State<EditGroupChatPage> createState() => _EditGroupChatPageState();
}

class _EditGroupChatPageState extends State<EditGroupChatPage> {
  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Editar Grupo',
      showDrawer: false,
      showBottomNavigation: false,
      body: Center(
        child: Text(
          'Edit Group Chat Page - Room: ${widget.roomId}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
    );
  }
}

