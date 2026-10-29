import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/hall_query.dart';
import '../models/studio_hall.dart';
import '../state/catalog_notifier.dart';
import '../state/session.dart';
import '../state/list_notifier.dart';
import '../state/list_notifiers.dart';
import '../widgets/common.dart';
import '../widgets/responsive.dart';
import '../widgets/entity_table.dart';
import '../widgets/state_views.dart';
import '../widgets/record_actions.dart';

class HallListScreen extends StatefulWidget {
  final HallQuery query;
  const HallListScreen({super.key, required this.query});

  @override
  State<HallListScreen> createState() => _HallListScreenState();
}

class _HallListScreenState extends State<HallListScreen> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didUpdateWidget(covariant HallListScreen old) {
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

  void _sync() => context.read<HallListNotifier>().applyQuery(widget.query);
  void _go(HallQuery query) {
    final parameters = query.toQueryParameters();
    context.go(parameters.isEmpty
        ? '/halls'
        : Uri(path: '/halls', queryParameters: parameters).toString());
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<HallListNotifier>();
    final catalog = context.watch<CatalogNotifier>();
    return AppScaffold(
      title: 'Залы студии',
      onRefresh: () => context.read<HallListNotifier>().load(),
      index: 1,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Align(
            alignment: Alignment.centerRight,
            child: CreateButton(
                collection: 'halls',
                label: 'Новый зал',
                onPressed: () => context.go('/halls/new')),
          ),
        ),
        const ReadOnlyNotice(),
        _filters(notifier, catalog),
        if (notifier.hasSelection) _selection(notifier),
        Expanded(child: _body(notifier, catalog)),
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

  Widget _filters(HallListNotifier notifier, CatalogNotifier catalog) =>
      AdaptiveFilters(child: _filterFields(notifier, catalog));

  Widget _filterFields(HallListNotifier notifier, CatalogNotifier catalog) {
    final query = widget.query;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(spacing: 10, runSpacing: 10, children: [
        SizedBox(
            width: 280,
            child: QueryTextField(
                value: query.search,
                decoration: const InputDecoration(
                    labelText: 'Поиск: название или код',
                    border: OutlineInputBorder()),
                onChanged: (value) {
                  _timer?.cancel();
                  _timer = Timer(const Duration(milliseconds: 350),
                      () => _go(query.copyWith(search: value)));
                })),
        SizedBox(
            width: 230,
            child: DropdownButtonFormField<String?>(
                value: catalog.hallStyles.contains(query.style)
                    ? query.style
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Стиль', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Все стили')),
                  for (final style in catalog.hallStyles)
                    DropdownMenuItem<String?>(
                        value: style,
                        child: Text(style,
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (value) => _go(query.copyWith(style: value)))),
        _numberField('Мест от', query.capacityFrom,
            (value) => _go(query.copyWith(capacityFrom: value))),
        _numberField('Мест до', query.capacityTo,
            (value) => _go(query.copyWith(capacityTo: value))),
        _numberField('Цена от', query.priceFrom,
            (value) => _go(query.copyWith(priceFrom: value))),
        _numberField('Цена до', query.priceTo,
            (value) => _go(query.copyWith(priceTo: value))),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Switch(
              value: query.includeDeleted,
              onChanged: (value) => _go(query.copyWith(includeDeleted: value))),
          const Text('Удалённые')
        ]),
        TextButton(
            onPressed: query.hasActiveFilters
                ? () => _go(HallQuery(
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
  Widget _selection(HallListNotifier notifier) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: BulkActions(
          collection: 'halls',
          count: notifier.selected.length,
          onDelete: () async {
            if (await confirm(context, 'Удалить выбранные залы?')) {
              await notifier.deleteSelected();
            }
          },
          onErase: () async {
            if (await confirm(context, 'Стереть выбранные залы?', hard: true)) {
              await notifier.eraseSelected();
            }
          },
          onClearSelection: notifier.clearSelection,
        ),
      );
  Widget _body(HallListNotifier notifier, CatalogNotifier catalog) {
    if (notifier.status != LoadStatus.success) {
      return ListStateView(notifier: notifier);
    }
    if (notifier.result.items.isEmpty) {
      return EmptyView(
        message: 'Залы по заданным условиям не найдены',
        hint: 'Попробуйте другое название или снимите фильтры.',
      );
    }
    if (MediaQuery.sizeOf(context).width < compactWidth) {
      return ListView(
          children: [for (final item in notifier.result.items) _card(item)]);
    }
    return EntityTable<StudioHall>(
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
          'Название',
          'name',
          (item) => Text('${item.name}${item.isDeleted ? ' (удалён)' : ''}')
        ),
        ('Код', null, (item) => Text(item.code)),
        ('Стиль', 'style', (item) => Text(item.style)),
        ('Мест', 'capacity', (item) => Text('${item.capacity}')),
        ('Цена/час', 'hourlyRate', (item) => Text('${item.hourlyRate} ₽')),
        ('Брони', null, (item) => Text('${item.bookingIds.length}')),
        ('Оборуд.', null, (item) => Text('${item.equipmentIds.length}')),
      ],
      actions: (item) => _actions(item),
    );
  }

  Widget _card(StudioHall item) => Card(
        child: ResponsiveRecordTile(
          leading: Checkbox(
              value:
                  context.watch<HallListNotifier>().selected.contains(item.id),
              onChanged: (_) =>
                  context.read<HallListNotifier>().toggle(item.id)),
          title: Text(item.name),
          subtitle: Text('${item.code} · ${item.style}\n'
              '${item.capacity} чел. · ${item.hourlyRate} ₽/час\n'
              'Бронирований: ${item.bookingIds.length} · '
              'Оборудования: ${item.equipmentIds.length}'
              '${item.isDeleted ? ' · удалён' : ''}'),
          isThreeLine: true,
          trailing: Wrap(children: _actions(item)),
        ),
      );
  List<Widget> _actions(StudioHall item) => RecordActions.buttons(
        collection: 'halls',
        context: context,
        onBook: context.watch<SessionStore>().permissions.canBookOwn
            ? () => context.go('/my-bookings/new?hallId=${item.id}')
            : null,
        onView: () => context.go('/halls/${item.id}'),
        permissions: context.watch<SessionStore>().permissions,
        onEdit: () => context.go('/halls/${item.id}/edit'),
        isDeleted: item.isDeleted,
        onSoftDelete: () => _delete(item, hard: false),
        onRestore: () => context.read<HallListNotifier>().restore(item.id),
        onHardDelete: () => _delete(item, hard: true),
      );
  Future<void> _delete(StudioHall item, {required bool hard}) async {
    final halls = context.read<HallListNotifier>();
    final catalog = context.read<CatalogNotifier>();
    if (!mounted) return;
    if (await confirm(context,
        hard ? 'Стереть зал «${item.name}»?' : 'Удалить зал «${item.name}»?',
        hard: hard)) {
      if (hard) {
        await halls.hardDelete(item.id);
      } else {
        await halls.softDelete(item.id);
      }
      await catalog.load();
    }
  }
}
