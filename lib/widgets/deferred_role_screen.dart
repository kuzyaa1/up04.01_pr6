import 'package:flutter/material.dart';
import '../screens/role_screen.dart' deferred as roles;
import 'state_views.dart';

/// Administrative and personal workspaces are downloaded when first opened.
class DeferredRoleScreen extends StatefulWidget {
  const DeferredRoleScreen({super.key, required this.kind});
  final String kind;
  @override
  State<DeferredRoleScreen> createState() => _DeferredRoleScreenState();
}

class _DeferredRoleScreenState extends State<DeferredRoleScreen> {
  late Future<void> _library = roles.loadLibrary();
  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
        future: _library,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              body: ErrorView(
                message: 'Не удалось загрузить раздел. Проверьте соединение.',
                onRetry: () => setState(() => _library = roles.loadLibrary()),
              ),
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(body: LoadingView());
          }
          return roles.RoleScreen(kind: widget.kind);
        },
      );
}
