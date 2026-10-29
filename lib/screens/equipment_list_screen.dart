import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/equipment.dart';
import '../models/equipment_query.dart';
import '../state/catalog_notifier.dart';
import '../state/catalog_notifiers.dart';
import '../state/session.dart';
import '../state/list_notifier.dart';
import '../widgets/common.dart';
import '../widgets/responsive.dart';
import '../widgets/entity_table.dart';
import '../widgets/state_views.dart';
import '../widgets/record_actions.dart';

class EquipmentListScreen extends StatefulWidget {
  final EquipmentQuery query;
  const EquipmentListScreen({super.key, required this.query});

  @override
  State<EquipmentListScreen> createState() => _EquipmentListScreenState();
}

class _EquipmentListScreenState extends State<EquipmentListScreen> {
  Timer? _timer;
  List<String> _categories = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _sync();
      final catalog = context.read<CatalogNotifier>();
      await catalog.load();
      if (mounted) {
        setState(() => _categories = catalog.equipmentCategories);
      }
    });
  }

  @override
  void didUpdateWidget(covariant EquipmentListScreen old) {
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

  void _sync() =>
      context.read<EquipmentListNotifier>().applyQuery(widget.query);
  void _go(EquipmentQuery query) {
    final parameters = query.toQueryParameters();
    context.go(parameters.isEmpty
        ? '/equipment'
        : Uri(path: '/equipment', queryParameters: parameters).toString());
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<EquipmentListNotifier>();
    final catalog = context.watch<CatalogNotifier>();
    return AppScaffold(
      title: 'Оборудование',
      onRefresh: () => context.read<EquipmentListNotifier>().load(),
      index: 4,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Align(
            alignment: Alignment.centerRight,
            child: CreateButton(
                collection: 'equipment',
                label: 'Новое оборудование',
                onPressed: () => context.go('/equipment/new')),
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

  Widget _filters(EquipmentListNotifier notifier, CatalogNotifier catalog) =>
      AdaptiveFilters(child: _filterFields(notifier, catalog));

  Widget _filterFields(
      EquipmentListNotifier notifier, CatalogNotifier catalog) {
    final query = widget.query;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(spacing: 10, runSpacing: 10, children: [
        SizedBox(
            width: 260,
            child: QueryTextField(
                value: query.search,
                decoration: const InputDecoration(
                    labelText: 'Поиск: название, категория, производитель',
                    border: OutlineInputBorder()),
                onChanged: (value) {
                  _timer?.cancel();
                  _timer = Timer(const Duration(milliseconds: 350),
                      () => _go(query.copyWith(search: value)));
                })),
        SizedBox(
            width: 200,
            child: DropdownButtonFormField<String?>(
                value: _categories.contains(query.category)
                    ? query.category
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Категория', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Все категории')),
                  for (final value in _categories)
                    DropdownMenuItem<String?>(value: value, child: Text(value)),
                ],
                onChanged: (value) => _go(query.copyWith(category: value)))),
        SizedBox(
            width: 220,
            child: DropdownButtonFormField<int?>(
                value: catalog.halls.any((h) => h.id == query.hallId)
                    ? query.hallId
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Зал', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<int?>(
                      value: null, child: Text('Все залы')),
                  for (final hall in catalog.halls)
                    DropdownMenuItem<int?>(
                        value: hall.id,
                        child: Text(hall.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (value) => _go(query.copyWith(hallId: value)))),
        _numberField('Кол-во от', query.quantityFrom,
            (value) => _go(query.copyWith(quantityFrom: value))),
        _numberField('Кол-во до', query.quantityTo,
            (value) => _go(query.copyWith(quantityTo: value))),
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
                ? () => _go(EquipmentQuery(
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
  Widget _selection(EquipmentListNotifier notifier) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: BulkActions(
          collection: 'equipment',
          count: notifier.selected.length,
          onDelete: () async {
            if (await confirm(context, 'Удалить выбранное оборудование?')) {
              await notifier.deleteSelected();
            }
          },
          onErase: () async {
            if (await confirm(context, 'Стереть выбранное оборудование?',
                hard: true)) {
              await notifier.eraseSelected();
            }
          },
          onClearSelection: notifier.clearSelection,
        ),
      );
  Widget _body(EquipmentListNotifier notifier, CatalogNotifier catalog) {
    if (notifier.status != LoadStatus.success) {
      return ListStateView(notifier: notifier);
    }
    if (notifier.result.items.isEmpty) {
      return EmptyView(
        message: 'Оборудование не найдено',
        hint: 'Попробуйте другое название или снимите фильтры.',
      );
    }
    if (MediaQuery.sizeOf(context).width < compactWidth) {
      return ListView(children: [
        for (final item in notifier.result.items) _card(item, catalog)
      ]);
    }
    return EntityTable<Equipment>(
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
          (item) => Text('${item.name}${item.isDeleted ? ' (удалено)' : ''}')
        ),
        ('Категория', 'category', (item) => Text(item.category)),
        ('Производитель', null, (item) => Text(item.manufacturer)),
        ('Зал', 'hall', (item) => Text(catalog.hallName(item.hallId))),
        ('Кол-во', 'quantity', (item) => Text('${item.quantity}')),
        ('Цена/день', 'pricePerDay', (item) => Text('${item.pricePerDay} ₽')),
      ],
      actions: (item) => _actions(item),
    );
  }

  Widget _card(Equipment item, CatalogNotifier catalog) => Card(
        child: ResponsiveRecordTile(
          leading: Checkbox(
              value: context
                  .watch<EquipmentListNotifier>()
                  .selected
                  .contains(item.id),
              onChanged: (_) =>
                  context.read<EquipmentListNotifier>().toggle(item.id)),
          title: Text(item.name),
          subtitle: Text('${item.category} · ${catalog.hallName(item.hallId)}\n'
              '${item.quantity} шт. · ${item.pricePerDay} ₽/день'
              '${item.isDeleted ? ' · удалено' : ''}'),
          isThreeLine: true,
          trailing: Wrap(children: _actions(item)),
        ),
      );
  List<Widget> _actions(Equipment item) => RecordActions.buttons(
        collection: 'equipment',
        context: context,
        onView: () => context.go('/equipment/${item.id}'),
        permissions: context.watch<SessionStore>().permissions,
        onEdit: () => context.go('/equipment/${item.id}/edit'),
        isDeleted: item.isDeleted,
        onSoftDelete: () => _delete(item, hard: false),
        onRestore: () => context.read<EquipmentListNotifier>().restore(item.id),
        onHardDelete: () => _delete(item, hard: true),
      );
  Future<void> _delete(Equipment item, {required bool hard}) async {
    final equipment = context.read<EquipmentListNotifier>();
    final catalog = context.read<CatalogNotifier>();
    if (!mounted) return;
    if (await confirm(
        context,
        hard
            ? 'Стереть оборудование «${item.name}»?'
            : 'Удалить оборудование «${item.name}»?',
        hard: hard)) {
      if (hard) {
        await equipment.hardDelete(item.id);
      } else {
        await equipment.softDelete(item.id);
      }
      await catalog.load();
    }
  }
}
