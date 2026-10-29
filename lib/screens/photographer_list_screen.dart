import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/photographer.dart';
import '../models/photographer_query.dart';
import '../state/catalog_notifier.dart';
import '../state/session.dart';
import '../state/list_notifier.dart';
import '../state/list_notifiers.dart';
import '../widgets/common.dart';
import '../widgets/responsive.dart';
import '../widgets/entity_table.dart';
import '../widgets/state_views.dart';
import '../widgets/record_actions.dart';

class PhotographerListScreen extends StatefulWidget {
  final PhotographerQuery query;
  const PhotographerListScreen({super.key, required this.query});

  @override
  State<PhotographerListScreen> createState() => _PhotographerListScreenState();
}

class _PhotographerListScreenState extends State<PhotographerListScreen> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didUpdateWidget(covariant PhotographerListScreen old) {
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
      context.read<PhotographerListNotifier>().applyQuery(widget.query);
  void _go(PhotographerQuery query) {
    final parameters = query.toQueryParameters();
    context.go(parameters.isEmpty
        ? '/photographers'
        : Uri(path: '/photographers', queryParameters: parameters).toString());
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<PhotographerListNotifier>();
    final catalog = context.watch<CatalogNotifier>();
    return AppScaffold(
      title: 'Фотографы',
      onRefresh: () => context.read<PhotographerListNotifier>().load(),
      index: 2,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Align(
            alignment: Alignment.centerRight,
            child: CreateButton(
                collection: 'photographers',
                label: 'Новый фотограф',
                onPressed: () => context.go('/photographers/new')),
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

  Widget _filters(PhotographerListNotifier notifier, CatalogNotifier catalog) =>
      AdaptiveFilters(child: _filterFields(notifier, catalog));

  Widget _filterFields(
      PhotographerListNotifier notifier, CatalogNotifier catalog) {
    final query = widget.query;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(spacing: 10, runSpacing: 10, children: [
        SizedBox(
            width: 280,
            child: QueryTextField(
                value: query.search,
                decoration: const InputDecoration(
                    labelText: 'Поиск: фамилия, имя, специализация',
                    border: OutlineInputBorder()),
                onChanged: (value) {
                  _timer?.cancel();
                  _timer = Timer(const Duration(milliseconds: 350),
                      () => _go(query.copyWith(search: value)));
                })),
        SizedBox(
            width: 240,
            child: DropdownButtonFormField<String?>(
                value: catalog.specializations.contains(query.specialization)
                    ? query.specialization
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Специализация', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Все специализации')),
                  for (final value in catalog.specializations)
                    DropdownMenuItem<String?>(value: value, child: Text(value)),
                ],
                onChanged: (value) =>
                    _go(query.copyWith(specialization: value)))),
        SizedBox(
            width: 230,
            child: DropdownButtonFormField<int?>(
                value: catalog.halls.any((h) => h.id == query.hallId)
                    ? query.hallId
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Работает в зале', border: OutlineInputBorder()),
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
        _numberField('Стаж от', query.experienceFrom,
            (value) => _go(query.copyWith(experienceFrom: value))),
        _numberField('Стаж до', query.experienceTo,
            (value) => _go(query.copyWith(experienceTo: value))),
        _numberField('Ставка от', query.rateFrom,
            (value) => _go(query.copyWith(rateFrom: value))),
        _numberField('Ставка до', query.rateTo,
            (value) => _go(query.copyWith(rateTo: value))),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Switch(
              value: query.includeDeleted,
              onChanged: (value) => _go(query.copyWith(includeDeleted: value))),
          const Text('Удалённые')
        ]),
        TextButton(
            onPressed: query.hasActiveFilters
                ? () => _go(PhotographerQuery(
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
  Widget _selection(PhotographerListNotifier notifier) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: BulkActions(
          collection: 'photographers',
          count: notifier.selected.length,
          onDelete: () async {
            if (await confirm(context, 'Удалить выбранных фотографов?')) {
              await notifier.deleteSelected();
            }
          },
          onErase: () async {
            if (await confirm(context, 'Стереть выбранных фотографов?',
                hard: true)) {
              await notifier.eraseSelected();
            }
          },
          onClearSelection: notifier.clearSelection,
        ),
      );
  Widget _body(PhotographerListNotifier notifier, CatalogNotifier catalog) {
    if (notifier.status != LoadStatus.success) {
      return ListStateView(notifier: notifier);
    }
    if (notifier.result.items.isEmpty) {
      return EmptyView(
        message: 'Фотографы не найдены',
        hint: 'Попробуйте другое имя или снимите фильтры.',
      );
    }
    if (MediaQuery.sizeOf(context).width < compactWidth) {
      return ListView(children: [
        for (final item in notifier.result.items) _card(item, catalog)
      ]);
    }
    return EntityTable<Photographer>(
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
          'Фамилия',
          'lastName',
          (item) => Text('${item.lastName}${item.isDeleted ? ' (удалён)' : ''}')
        ),
        ('Имя', 'firstName', (item) => Text(item.firstName)),
        (
          'Специализация',
          'specialization',
          (item) => Text(item.specialization)
        ),
        (
          'Стаж',
          'experienceYears',
          (item) => Text('${item.experienceYears} лет')
        ),
        ('Ставка', 'hourlyRate', (item) => Text('${item.hourlyRate} ₽')),
        (
          'Залы',
          null,
          (item) => Text(item.hallIds.map(catalog.hallName).join(', '))
        ),
        ('Броней', null, (item) => Text('${item.bookingIds.length}')),
      ],
      actions: (item) => _actions(item),
    );
  }

  Widget _card(Photographer item, CatalogNotifier catalog) => Card(
        child: ResponsiveRecordTile(
          leading: Checkbox(
              value: context
                  .watch<PhotographerListNotifier>()
                  .selected
                  .contains(item.id),
              onChanged: (_) =>
                  context.read<PhotographerListNotifier>().toggle(item.id)),
          title: Text(item.fullName),
          subtitle: Text('${item.specialization}\n'
              'Стаж ${item.experienceYears} лет · ${item.hourlyRate} ₽/час\n'
              'Залы: ${item.hallIds.map(catalog.hallName).join(', ')}'
              '${item.isDeleted ? ' · удалён' : ''}'),
          isThreeLine: true,
          trailing: Wrap(children: _actions(item)),
        ),
      );
  List<Widget> _actions(Photographer item) => RecordActions.buttons(
        collection: 'photographers',
        context: context,
        onView: () => context.go('/photographers/${item.id}'),
        permissions: context.watch<SessionStore>().permissions,
        onEdit: () => context.go('/photographers/${item.id}/edit'),
        isDeleted: item.isDeleted,
        onSoftDelete: () => _delete(item, hard: false),
        onRestore: () =>
            context.read<PhotographerListNotifier>().restore(item.id),
        onHardDelete: () => _delete(item, hard: true),
      );
  Future<void> _delete(Photographer item, {required bool hard}) async {
    final photographers = context.read<PhotographerListNotifier>();
    final catalog = context.read<CatalogNotifier>();
    if (!mounted) return;
    if (await confirm(
        context,
        hard
            ? 'Стереть фотографа «${item.fullName}»?'
            : 'Удалить фотографа «${item.fullName}»?',
        hard: hard)) {
      if (hard) {
        await photographers.hardDelete(item.id);
      } else {
        await photographers.softDelete(item.id);
      }
      await catalog.load();
    }
  }
}
