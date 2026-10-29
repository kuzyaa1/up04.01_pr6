import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/client.dart';
import '../models/client_query.dart';
import '../repositories/client_repository.dart';
import '../state/catalog_notifier.dart';
import '../state/catalog_notifiers.dart';
import '../state/session.dart';
import '../state/list_notifier.dart';
import '../widgets/common.dart';
import '../widgets/responsive.dart';
import '../widgets/entity_table.dart';
import '../widgets/state_views.dart';
import '../widgets/record_actions.dart';

class ClientListScreen extends StatefulWidget {
  final ClientQuery query;
  const ClientListScreen({super.key, required this.query});

  @override
  State<ClientListScreen> createState() => _ClientListScreenState();
}

class _ClientListScreenState extends State<ClientListScreen> {
  Timer? _timer;
  List<String> _clientTypes = Client.clientTypes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _sync();
      final clients = await context.read<ClientRepository>().all();
      final values = clients
          .map((client) => client.clientType)
          .where((type) => type.trim().isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      for (final type in Client.clientTypes) {
        if (!values.contains(type)) values.add(type);
      }
      if (mounted && values.isNotEmpty) {
        setState(() => _clientTypes = values);
      }
    });
  }

  @override
  void didUpdateWidget(covariant ClientListScreen old) {
    super.didUpdateWidget(old);
    if (old.query.toQueryParameters().toString() !=
        widget.query.toQueryParameters().toString()) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _sync() => context.read<ClientListNotifier>().applyQuery(widget.query);
  void _go(ClientQuery query) {
    final parameters = query.toQueryParameters();
    context.go(parameters.isEmpty
        ? '/clients'
        : Uri(path: '/clients', queryParameters: parameters).toString());
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<ClientListNotifier>();
    return AppScaffold(
      title: 'Клиенты',
      onRefresh: () => context.read<ClientListNotifier>().load(),
      index: 3,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Align(
            alignment: Alignment.centerRight,
            child: CreateButton(
                collection: 'clients',
                label: 'Новый клиент',
                onPressed: () => context.go('/clients/new')),
          ),
        ),
        const ReadOnlyNotice(),
        _filters(notifier),
        if (notifier.hasSelection) _selection(notifier),
        Expanded(child: _body(notifier)),
        if (notifier.status == LoadStatus.success && notifier.result.total > 0)
          Pager(
              page: notifier.result.page,
              totalPages: notifier.result.totalPages,
              total: notifier.result.total,
              size: notifier.result.size,
              onPage: (value) => _go(notifier.query.copyWith(page: value)),
              onSize: (value) => _go(notifier.query.copyWith(size: value))),
      ]),
    );
  }

  Widget _filters(ClientListNotifier notifier) =>
      AdaptiveFilters(child: _filterFields(notifier));

  Widget _filterFields(ClientListNotifier notifier) {
    final query = widget.query;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(spacing: 10, runSpacing: 10, children: [
        SizedBox(
            width: 300,
            child: QueryTextField(
                value: query.search,
                decoration: const InputDecoration(
                    labelText: 'Поиск: имя, телефон, абонемент',
                    border: OutlineInputBorder()),
                onChanged: (value) {
                  _timer?.cancel();
                  _timer = Timer(const Duration(milliseconds: 350),
                      () => _go(query.copyWith(search: value)));
                })),
        SizedBox(
            width: 200,
            child: DropdownButtonFormField<bool?>(
                value: query.hasCard,
                decoration: const InputDecoration(
                    labelText: 'Абонемент', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem<bool?>(value: null, child: Text('Любой')),
                  DropdownMenuItem<bool?>(value: true, child: Text('Есть')),
                  DropdownMenuItem<bool?>(value: false, child: Text('Нет')),
                ],
                onChanged: (value) => _go(query.copyWith(hasCard: value)))),
        SizedBox(
            width: 220,
            child: DropdownButtonFormField<String?>(
                value: _clientTypes.contains(query.clientType)
                    ? query.clientType
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Тип клиента', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Все типы')),
                  for (final type in _clientTypes)
                    DropdownMenuItem<String?>(
                        value: type,
                        child: Text(type,
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (value) => _go(query.copyWith(clientType: value)))),
        _numberField('Выдан с', query.yearFrom,
            (value) => _go(query.copyWith(yearFrom: value))),
        _numberField('Выдан по', query.yearTo,
            (value) => _go(query.copyWith(yearTo: value))),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Switch(
              value: query.includeDeleted,
              onChanged: (value) => _go(query.copyWith(includeDeleted: value))),
          const Text('Удалённые')
        ]),
        TextButton(
            onPressed: query.hasActiveFilters
                ? () => _go(ClientQuery(
                    size: query.size,
                    sortField: query.sortField,
                    sortAscending: query.sortAscending))
                : null,
            child: const Text('Сбросить')),
      ]),
    );
  }

  Widget _numberField(String label, int? value, ValueChanged<int?> onChanged) =>
      SizedBox(
          width: 140,
          child: QueryTextField(
              value: value?.toString(),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  labelText: label, border: OutlineInputBorder()),
              onFieldSubmitted: (text) => onChanged(int.tryParse(text))));
  Widget _selection(ClientListNotifier notifier) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: BulkActions(
          collection: 'clients',
          count: notifier.selected.length,
          onDelete: () async {
            if (await confirm(context, 'Удалить выбранных клиентов?')) {
              await notifier.deleteSelected();
            }
          },
          onErase: () async {
            if (await confirm(context, 'Стереть выбранных клиентов?',
                hard: true)) {
              await notifier.eraseSelected();
            }
          },
          onClearSelection: notifier.clearSelection,
        ),
      );
  Widget _body(ClientListNotifier notifier) {
    if (notifier.status != LoadStatus.success) {
      return ListStateView(notifier: notifier);
    }
    if (notifier.result.items.isEmpty) {
      return EmptyView(
        message: 'Клиенты не найдены',
        hint: 'Попробуйте другое имя или снимите фильтры.',
      );
    }
    if (MediaQuery.sizeOf(context).width < compactWidth) {
      return ListView(
          children: [for (final item in notifier.result.items) _card(item)]);
    }
    return EntityTable<Client>(
      items: notifier.result.items,
      id: (item) => item.id,
      selected: notifier.selected,
      toggle: notifier.toggle,
      sort: notifier.query.sortField,
      asc: notifier.query.sortAscending,
      onSort: (field) => _go(notifier.query.copyWith(
          sortField: field,
          sortAscending: field == notifier.query.sortField
              ? !notifier.query.sortAscending
              : true)),
      columns: [
        (
          'Клиент',
          'name',
          (item) => Text('${item.name}${item.isDeleted ? ' (удалён)' : ''}')
        ),
        ('Телефон', 'phone', (item) => Text(item.phone)),
        ('Email', 'email', (item) => Text(item.email)),
        ('Тип', null, (item) => Text(item.clientType)),
        ('Компания', null, (item) => Text(item.company)),
        ('Абонемент', 'cardNumber', (item) => Text(item.cardNumber)),
        (
          'Действует до',
          null,
          (item) => Text(item.cardExpiresAt.isEmpty ? '—' : item.cardExpiresAt)
        ),
      ],
      actions: (item) => _actions(item),
    );
  }

  Widget _card(Client item) => Card(
        child: ResponsiveRecordTile(
          leading: Checkbox(
              value: context
                  .watch<ClientListNotifier>()
                  .selected
                  .contains(item.id),
              onChanged: (_) =>
                  context.read<ClientListNotifier>().toggle(item.id)),
          title: Text(item.name),
          subtitle: Text('${item.email} · ${item.phone}\n'
              '${item.clientType}'
              '${item.company.isEmpty ? '' : ' · ${item.company}'}\n'
              'Абонемент: ${item.cardNumber}'
              ' с ${item.cardIssuedAt}'
              '${item.cardExpiresAt.isEmpty ? '' : ' по ${item.cardExpiresAt}'}'
              '${item.isDeleted ? ' · удалён' : ''}'),
          isThreeLine: true,
          trailing: Wrap(children: _actions(item)),
        ),
      );
  List<Widget> _actions(Client item) => RecordActions.buttons(
        collection: 'clients',
        context: context,
        onView: () => context.go('/clients/${item.id}'),
        permissions: context.watch<SessionStore>().permissions,
        onEdit: () => context.go('/clients/${item.id}/edit'),
        isDeleted: item.isDeleted,
        onSoftDelete: () => _delete(item, hard: false),
        onRestore: () => context.read<ClientListNotifier>().restore(item.id),
        onHardDelete: () => _delete(item, hard: true),
      );
  Future<void> _delete(Client item, {required bool hard}) async {
    final clients = context.read<ClientListNotifier>();
    final catalog = context.read<CatalogNotifier>();
    if (!mounted) return;
    if (await confirm(
        context,
        hard
            ? 'Стереть клиента «${item.name}»?'
            : 'Удалить клиента «${item.name}»?',
        hard: hard)) {
      if (hard) {
        await clients.hardDelete(item.id);
      } else {
        await clients.softDelete(item.id);
      }
      await catalog.load();
    }
  }
}
