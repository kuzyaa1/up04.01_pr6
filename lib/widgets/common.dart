import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../state/session.dart';
import '../core/api_exceptions.dart';
import '../core/errors.dart';
import 'responsive.dart';

const compactWidth = tableWidth;

/// Keeps URL-driven filters in sync without losing focus while typing.
class QueryTextField extends StatefulWidget {
  final String? value;
  final InputDecoration decoration;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  const QueryTextField(
      {super.key,
      this.value,
      required this.decoration,
      this.keyboardType,
      this.onChanged,
      this.onFieldSubmitted});
  @override
  State<QueryTextField> createState() => _QueryTextFieldState();
}

class _QueryTextFieldState extends State<QueryTextField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value ?? '');
  @override
  void didUpdateWidget(covariant QueryTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        _controller.text != (widget.value ?? '')) {
      final text = widget.value ?? '';
      _controller.value = TextEditingValue(
          text: text, selection: TextSelection.collapsed(offset: text.length));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextFormField(
      controller: _controller,
      decoration: widget.decoration,
      keyboardType: widget.keyboardType,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onFieldSubmitted);
}

class AppScaffold extends StatelessWidget {
  final String title;
  final int index;
  final Widget child;
  final List<Widget> actions;

  /// Что делает кнопка «Обновить» в шапке.
  ///
  /// Нужна именно на вебе: страницу держат открытой часами, а данные за
  /// это время меняются. Тянуть за список сверху, как на телефоне, в
  /// браузере никто не станет.
  final VoidCallback? onRefresh;

  const AppScaffold(
      {super.key,
      required this.title,
      required this.index,
      required this.child,
      this.actions = const [],
      this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final destinations = [
      (Icons.event_available, 'Бронирования', '/bookings'),
      (Icons.meeting_room, 'Залы', '/halls'),
      (Icons.camera_alt, 'Фотографы', '/photographers'),
      (Icons.people, 'Клиенты', '/clients'),
      (Icons.lightbulb_outline, 'Оборудование', '/equipment'),
    ];
    final permissions = context.watch<SessionStore>().permissions;
    final visible = destinations
        .where((d) => d.$3 != '/clients' || permissions.canManageClients)
        .toList();
    visible.insert(0, (Icons.home_outlined, 'Главная', '/'));
    final visibleIndex = index < 0
        ? 0
        : visible.indexOf(destinations[index]).clamp(0, visible.length - 1);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < phoneWidth;
    final app = AppBar(
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [
        ...actions,
        if (onRefresh != null)
          IconButton(
            tooltip: 'Обновить данные',
            icon: const Icon(Icons.refresh),
            onPressed: onRefresh,
          ),
        const SessionAction(),
      ],
    );
    if (compact) {
      return Scaffold(
          appBar: app,
          body: SafeArea(child: child),
          bottomNavigationBar: NavigationBar(
              labelBehavior:
                  NavigationDestinationLabelBehavior.onlyShowSelected,
              selectedIndex: visibleIndex,
              onDestinationSelected: (i) => context.go(visible[i].$3),
              destinations: [
                for (final d in visible)
                  NavigationDestination(icon: Icon(d.$1), label: d.$2)
              ]));
    }
    return Scaffold(
        appBar: app,
        body: Row(children: [
          NavigationRail(
              selectedIndex: visibleIndex,
              extended: width >= 1200,
              onDestinationSelected: (i) => context.go(visible[i].$3),
              destinations: [
                for (final d in visible)
                  NavigationRailDestination(icon: Icon(d.$1), label: Text(d.$2))
              ]),
          const VerticalDivider(width: 1),
          Expanded(
              child: Center(
                  child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: contentWidth),
            child: child,
          )))
        ]));
  }
}

/// Кнопка текущего пользователя и выход из системы.
///
/// Показывает, под кем выполнен вход, и позволяет завершить сессию.
class SessionAction extends StatelessWidget {
  const SessionAction({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    final user = session.user;
    if (user == null) {
      return IconButton(
        tooltip: 'Войти',
        onPressed: () => context.go('/login'),
        icon: const Icon(Icons.login),
      );
    }
    return PopupMenuButton<String>(
      tooltip: user.fullName,
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            CircleAvatar(
                radius: 14,
                child: Text(user.fullName.isEmpty
                    ? '?'
                    : user.fullName[0].toUpperCase())),
            if (MediaQuery.sizeOf(context).width >= phoneWidth) ...[
              const SizedBox(width: 8),
              ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(user.fullName, overflow: TextOverflow.ellipsis)),
            ],
          ])),
      onSelected: (value) async {
        if (value == 'home') {
          context.go('/');
          return;
        }
        if (value != 'logout') return;
        await session.logout();
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(user.fullName,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(user.role, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        const PopupMenuItem<String>(value: 'home', child: Text('Главная')),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'logout',
          child: Text('Выйти'),
        ),
      ],
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

class Pager extends StatelessWidget {
  final int page, totalPages, total, size;
  final ValueChanged<int> onPage, onSize;
  const Pager(
      {super.key,
      required this.page,
      required this.totalPages,
      required this.total,
      required this.size,
      required this.onPage,
      required this.onSize});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Всего: $total'),
            DropdownButton<int>(
                value: size,
                items: [10, 25, 50]
                    .map((x) => DropdownMenuItem(value: x, child: Text('$x')))
                    .toList(),
                onChanged: (x) {
                  if (x != null) onSize(x);
                }),
            IconButton(
                tooltip: 'Первая страница',
                onPressed: page > 1 ? () => onPage(1) : null,
                icon: const Icon(Icons.first_page)),
            IconButton(
                tooltip: 'Предыдущая страница',
                onPressed: page > 1 ? () => onPage(page - 1) : null,
                icon: const Icon(Icons.chevron_left)),
            Text('$page / $totalPages'),
            IconButton(
                tooltip: 'Следующая страница',
                onPressed: page < totalPages ? () => onPage(page + 1) : null,
                icon: const Icon(Icons.chevron_right)),
            IconButton(
                tooltip: 'Последняя страница',
                onPressed: page < totalPages ? () => onPage(totalPages) : null,
                icon: const Icon(Icons.last_page))
          ]));
}

Future<bool> confirm(BuildContext context, String text,
        {bool hard = false, String? title}) async =>
    (await showDialog<bool>(
        context: context,
        builder: (x) => AlertDialog(
                title: Text(title ??
                    (hard ? 'Физическое удаление' : 'Логическое удаление')),
                content: Text(text),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(x, false),
                      child: const Text('Отмена')),
                  FilledButton(
                      onPressed: () => Navigator.pop(x, true),
                      child: Text(hard ? 'Стереть' : 'Удалить'))
                ]))) ??
    false;
void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
    ));
}

/// A rejected mutation must not replace a successfully loaded list with an
/// error screen. Keep the server's explanation visible until it is dismissed.
Future<void> showOperationError(BuildContext context, Object error) async {
  if (!context.mounted) return;
  if (error is ConflictException || error is LinkedRecordsException) {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Операция не выполнена'),
        content: Text('${error.toString()}\n\nДанные не изменены.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
    return;
  }
  toast(context, error.toString());
}
