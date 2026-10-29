import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/api_exceptions.dart';
import '../core/router.dart';
import '../state/session.dart';

/// Экран входа в систему.
///
/// Токен доступа хранится в `localStorage` (на web это
/// `SharedPreferences`). Хранить там пароль или признак администратора
/// нельзя: пользователь видит содержимое `localStorage` в DevTools и может
/// его изменить. Поэтому проверка прав всегда выполняется на сервере.
class LoginScreen extends StatefulWidget {
  /// Адрес, на который человека отправили до входа.
  ///
  /// Роутер запоминает его в параметре `from`, чтобы после входа
  /// вернуть человека туда, куда он шёл, а не на главную.
  final String? from;

  const LoginScreen({super.key, this.from});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = context.read<SessionStore>();
      await session.signIn(context.read<AuthRepository>(),
          _usernameController.text.trim(), _passwordController.text);

      // Справочники могли устареть: у клиента видны только его бронирования.
      if (!mounted) return;
      final from = widget.from;
      context.go(safeReturnLocation(from));
    } on UnauthorizedException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on NetworkException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Не удалось войти: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.camera_alt_outlined, size: 56),
                  const SizedBox(height: 12),
                  Text(
                    'FocusFrame',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    'Система бронирования фотостудии',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (session.notice != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(session.notice!)),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Логин',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                            ? 'Укажите логин'
                            : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Пароль',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => (value == null || value.isEmpty)
                        ? 'Укажите пароль'
                        : null,
                    onFieldSubmitted: (_) => _login(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(children: [
                        Icon(Icons.error_outline,
                            color:
                                Theme.of(context).colorScheme.onErrorContainer),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer,
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _login,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Войти'),
                  ),
                  TextButton(
                      onPressed: _busy ? null : () => context.go('/register'),
                      child: const Text('Создать аккаунт')),
                  const SizedBox(height: 24),
                  if (session.isAuthenticated)
                    OutlinedButton(
                      onPressed: () => context.go('/'),
                      child: Text(
                        'Продолжить как ${session.user?.fullName ?? 'гость'}',
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    'Учебные учётные записи: manager / manager123, '
                    'admin / admin123, client / client123',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
