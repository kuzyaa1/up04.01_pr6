import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/api_exceptions.dart';
import '../core/validators.dart';
import '../state/session.dart';

String? registrationPasswordError(String? value) {
  final password = value ?? '';
  if (password.length < 8) return 'Не менее 8 символов';
  if (!RegExp(r'\d').hasMatch(password)) return 'Добавьте цифру';
  if (!RegExp(r'[^\p{L}\p{N}\s]', unicode: true).hasMatch(password)) {
    return 'Добавьте специальный символ';
  }
  return null;
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _email = TextEditingController(),
      _username = TextEditingController(),
      _password = TextEditingController(),
      _repeat = TextEditingController();
  Map<String, String> _errors = {};
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    for (final c in [_name, _email, _username, _password, _repeat]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _errors = {};
      _error = null;
    });
    if (!_form.currentState!.validate()) return;
    final auth = context.read<AuthRepository>();
    final session = context.read<SessionStore>();
    setState(() => _busy = true);
    try {
      await auth.register(
          username: _username.text.trim(),
          password: _password.text,
          fullName: _name.text.trim(),
          email: _email.text.trim());
      await session.signIn(auth, _username.text.trim(), _password.text);
      if (mounted) context.go('/');
    } on ValidationException catch (e) {
      if (mounted) {
        setState(() => _errors = e.errors);
        _form.currentState!.validate();
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(TextEditingController c, String label, String key,
          String? Function(String?) validator, {bool secret = false}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: TextFormField(
              controller: c,
              obscureText: secret,
              decoration: InputDecoration(
                  labelText: label, border: const OutlineInputBorder()),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              onChanged: (_) => setState(() {
                    _errors.remove(key);
                  }),
              validator: (value) => validator(value) ?? _errors[key]));
  @override
  Widget build(BuildContext context) {
    final password = _password.text;
    return Scaffold(
        appBar: AppBar(title: const Text('Регистрация клиента')),
        body: Center(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Form(
                        key: _form,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                  'Создайте аккаунт, чтобы бронировать залы и управлять своими записями.'),
                              const SizedBox(height: 20),
                              _field(_name, 'Имя и фамилия', 'fullName',
                                  V.required()),
                              _field(_email, 'Электронная почта', 'email',
                                  V.email()),
                              _field(_username, 'Логин', 'username',
                                  V.length(min: 3, max: 50)),
                              _field(_password, 'Пароль', 'password',
                                  registrationPasswordError,
                                  secret: true),
                              for (final rule in [
                                (password.length >= 8, 'Не менее 8 символов'),
                                (
                                  RegExp(r'\d').hasMatch(password),
                                  'Есть цифра'
                                ),
                                (
                                  RegExp(r'[^\p{L}\p{N}\s]', unicode: true)
                                      .hasMatch(password),
                                  'Есть специальный символ'
                                ),
                              ])
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Row(children: [
                                      Icon(
                                          rule.$1
                                              ? Icons.check_circle
                                              : Icons.radio_button_unchecked,
                                          size: 18,
                                          color: rule.$1 ? Colors.green : null),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(rule.$2))
                                    ])),
                              const SizedBox(height: 12),
                              _field(
                                  _repeat,
                                  'Повторите пароль',
                                  'repeat',
                                  (v) => v == _password.text && v!.isNotEmpty
                                      ? null
                                      : 'Пароли должны совпадать',
                                  secret: true),
                              if (_error != null)
                                Text(_error!,
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error)),
                              FilledButton(
                                  onPressed: _busy ? null : _submit,
                                  child: Text(_busy
                                      ? 'Создание аккаунта…'
                                      : 'Зарегистрироваться')),
                              TextButton(
                                  onPressed:
                                      _busy ? null : () => context.go('/login'),
                                  child:
                                      const Text('Уже есть аккаунт — войти')),
                            ]))))));
  }
}
