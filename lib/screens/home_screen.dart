import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/permissions.dart';
import '../state/session.dart';
import '../widgets/common.dart';
import '../widgets/responsive.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    final user = session.user;
    final permissions = session.permissions;
    final entities = [
      (
        Icons.event_available,
        'Бронирования',
        '/bookings',
        'Центральная сущность: связь с залами, клиентами и фотографами'
      ),
      (Icons.meeting_room, 'Залы', '/halls', 'Один ко многим с бронированиями'),
      (
        Icons.camera_alt,
        'Фотографы',
        '/photographers',
        'Многие ко многим с залами и бронированиями'
      ),
      (Icons.people, 'Клиенты', '/clients', 'Один к одному с абонементом'),
      (
        Icons.lightbulb_outline,
        'Оборудование',
        '/equipment',
        'Многие к одному с залами'
      ),
    ];
    return AppScaffold(
      title: 'FocusFrame — фотостудия',
      index: -1,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Система бронирования фотостудии',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                const Text(
                  'Выберите зал для съёмки, управляйте своими бронированиями '
                  'или откройте рабочий раздел своей роли.',
                ),
                const SizedBox(height: 16),
                _sessionCard(context, session, user),
                const SizedBox(height: 24),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  if (permissions.canBookOwn)
                    FilledButton.icon(
                        onPressed: () => context.go('/my-bookings/new'),
                        icon: const Icon(Icons.add),
                        label: const Text('Забронировать зал')),
                  if (permissions.canUseClientPortal)
                    FilledButton.icon(
                        onPressed: () => context.go('/my-bookings'),
                        icon: const Icon(Icons.event),
                        label: const Text('Мои бронирования')),
                  if (permissions.canUseManagerWorkspace)
                    FilledButton.icon(
                        onPressed: () => context.go('/manager'),
                        icon: const Icon(Icons.work),
                        label: const Text('Рабочее место менеджера')),
                  if (permissions.canManageUsers)
                    FilledButton.icon(
                        onPressed: () => context.go('/admin/users'),
                        icon: const Icon(Icons.manage_accounts),
                        label: const Text('Пользователи и роли')),
                  if (permissions.canViewStatistics)
                    OutlinedButton.icon(
                        onPressed: () => context.go('/admin/statistics'),
                        icon: const Icon(Icons.bar_chart),
                        label: const Text('Статистика студии')),
                ]),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final entity in entities.where((e) =>
                        e.$3 != '/clients' || permissions.canManageClients))
                      SizedBox(
                        width: MediaQuery.sizeOf(context).width < phoneWidth
                            ? MediaQuery.sizeOf(context).width - 48
                            : 250,
                        child: Card(
                          child: InkWell(
                            onTap: () => context.go(entity.$3),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(entity.$1, size: 28),
                                  const SizedBox(height: 8),
                                  Text(entity.$2,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  const SizedBox(height: 4),
                                  Text(entity.$4,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sessionCard(
      BuildContext context, SessionStore session, AppUser? user) {
    final permissions = session.permissions;
    if (user == null) {
      return Card(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.info_outline),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Вы не вошли в систему: каталог доступен для чтения, '
                    'но изменять записи нельзя — сервер вернёт 401 или 403.',
                  ),
                ),
                FilledButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Войти'),
                ),
              ]),
              const SizedBox(height: 12),
              _permissionsList(context, permissions),
            ],
          ),
        ),
      );
    }
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.account_circle_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.fullName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      'Роль: ${permissions.role.title} · ${user.email}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (permissions.isReadOnly &&
                  MediaQuery.sizeOf(context).width >= phoneWidth)
                const Chip(
                  avatar: Icon(Icons.lock_outline, size: 16),
                  label: Text('каталог: просмотр'),
                ),
            ]),
            const SizedBox(height: 12),
            _permissionsList(context, permissions),
          ],
        ),
      ),
    );
  }

  Widget _permissionsList(BuildContext context, Permissions permissions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Что вам доступно:',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        for (final rule in permissions.summary)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(children: [
              Icon(
                rule.startsWith('Изменение') ? Icons.block : Icons.check,
                size: 16,
                color: rule.startsWith('Изменение')
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                  child:
                      Text(rule, style: Theme.of(context).textTheme.bodySmall)),
            ]),
          ),
      ],
    );
  }
}
