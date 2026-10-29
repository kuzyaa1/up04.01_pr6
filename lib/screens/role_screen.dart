import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/permissions.dart';
import '../models/booking.dart';
import '../repositories/role_repository.dart';
import '../state/session.dart';
import '../widgets/common.dart';
import '../widgets/state_views.dart';

class RoleScreen extends StatefulWidget {
  const RoleScreen({super.key, required this.kind});
  final String kind;
  @override
  State<RoleScreen> createState() => _RoleScreenState();
}

class _RoleScreenState extends State<RoleScreen> {
  late Future<Object> _data = _load();
  int? _busy;
  Future<Object> _load() {
    final repo = context.read<RoleRepository>();
    return switch (widget.kind) {
      'client' => repo.myBookings(),
      'manager' => repo.summary('/manager/workspace'),
      'users' => repo.users(),
      _ => repo.summary('/admin/statistics'),
    };
  }

  void _reload() => setState(() => _data = _load());
  Future<void> _action(int id, Future<void> Function() action) async {
    if (_busy != null) return;
    setState(() => _busy = id);
    try {
      await action();
      if (mounted) _reload();
    } on Object catch (e) {
      if (mounted) await showOperationError(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  String get _title => switch (widget.kind) {
        'client' => 'Мои бронирования',
        'manager' => 'Рабочее место менеджера',
        'users' => 'Пользователи и роли',
        _ => 'Статистика студии'
      };
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
          leading: BackButton(onPressed: () => context.go('/')),
          actions: [
            IconButton(
                onPressed: _reload,
                tooltip: 'Обновить',
                icon: const Icon(Icons.refresh)),
            const SessionAction()
          ]),
      body: FutureBuilder<Object>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ErrorView(
                  message: snapshot.error.toString(), onRetry: _reload);
            }
            if (!snapshot.hasData) return const LoadingView();
            return Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: ListView(
                        padding: const EdgeInsets.all(24),
                        children: _content(snapshot.data!))));
          }));
  List<Widget> _content(Object data) {
    if (widget.kind == 'client') {
      final rows = data as List<Booking>;
      return [
        const Text(
            'Выбирайте зал и дату съёмки. Здесь отображаются только ваши бронирования.'),
        const SizedBox(height: 16),
        FilledButton.icon(
            onPressed: () => context.go('/my-bookings/new'),
            icon: const Icon(Icons.add),
            label: const Text('Забронировать зал')),
        const SizedBox(height: 16),
        if (rows.isEmpty)
          const Text(
              'У вас пока нет бронирований. Выберите зал и оформите первую запись.'),
        for (final b in rows)
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b.accessCode,
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(
                            '${b.date.toIso8601String().split('T').first} · ${b.durationHours} ч · ${b.shootingType}'),
                        Text(switch (b.status) {
                          'active' => 'Активно',
                          'cancelled' => 'Отменено',
                          _ => 'Завершено'
                        }),
                        if (b.status == 'active')
                          TextButton.icon(
                              onPressed: _busy != null
                                  ? null
                                  : () => _action(
                                      b.id,
                                      () => context
                                          .read<RoleRepository>()
                                          .extend(b.id)),
                              icon: const Icon(Icons.more_time),
                              label: const Text('Продлить на 1 час')),
                      ]))),
      ];
    }
    if (widget.kind == 'users') {
      final rows = data as List<AppUser>;
      return [
        const Text(
            'Роль определяет доступ к функциям студии. Собственную роль администратора изменить нельзя.'),
        const SizedBox(height: 16),
        for (final u in rows)
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(u.fullName,
                            style: Theme.of(context).textTheme.titleMedium),
                        Text('${u.username} · ${u.email}'),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                            value: u.role,
                            decoration: const InputDecoration(
                                labelText: 'Роль',
                                border: OutlineInputBorder()),
                            items: [
                              for (final role in UserRole.values)
                                DropdownMenuItem(
                                    value: role.name, child: Text(role.title))
                            ],
                            onChanged: _busy != null ||
                                    u.id ==
                                        context.read<SessionStore>().user?.id
                                ? null
                                : (role) {
                                    if (role != null) {
                                      _action(
                                          u.id,
                                          () => context
                                              .read<RoleRepository>()
                                              .changeRole(u.id, role));
                                    }
                                  }),
                      ]))),
      ];
    }
    final values = data as Map<String, dynamic>;
    const labels = {
      'users': 'Пользователей',
      'halls': 'Залов',
      'clients': 'Клиентов',
      'bookings': 'Бронирований',
      'activeBookings': 'Активных бронирований',
      'deletedRecords': 'Записей в корзине'
    };
    return [
      for (final entry in values.entries)
        ListTile(
            title: Text(labels[entry.key] ?? entry.key),
            trailing: Text('${entry.value}',
                style: Theme.of(context).textTheme.titleLarge)),
      if (widget.kind == 'manager') ...[
        const Divider(),
        FilledButton.icon(
            onPressed: () => context.go('/bookings/new'),
            icon: const Icon(Icons.add),
            label: const Text('Оформить бронирование')),
        TextButton(
            onPressed: () => context.go('/clients'),
            child: const Text('Работа с клиентами')),
        TextButton(
            onPressed: () => context.go('/bookings'),
            child: const Text('Управление бронированиями')),
      ],
    ];
  }
}
