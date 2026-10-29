import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/form_outcome.dart';
import '../models/booking.dart';
import '../models/booking_query.dart';
import '../state/catalog_notifier.dart';
import '../state/catalog_notifiers.dart';
import '../state/session.dart';
import '../state/list_notifier.dart';
import '../widgets/common.dart';
import '../widgets/responsive.dart';
import '../widgets/entity_table.dart';
import '../widgets/state_views.dart';
import '../widgets/record_actions.dart';

class BookingListScreen extends StatefulWidget {
  final BookingQuery query;
  const BookingListScreen({super.key, required this.query});

  @override
  State<BookingListScreen> createState() => _BookingListScreenState();
}

class _BookingListScreenState extends State<BookingListScreen> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didUpdateWidget(covariant BookingListScreen old) {
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

  void _sync() => context.read<BookingListNotifier>().applyQuery(widget.query);
  void _go(BookingQuery query) {
    final parameters = query.toQueryParameters();
    context.go(parameters.isEmpty
        ? '/bookings'
        : Uri(path: '/bookings', queryParameters: parameters).toString());
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<BookingListNotifier>();
    final catalog = context.watch<CatalogNotifier>();
    return AppScaffold(
      title: 'Бронирования',
      onRefresh: () => context.read<BookingListNotifier>().load(),
      index: 0,
      child: Column(children: [
        _toolbar(),
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

  Widget _toolbar() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Align(
          alignment: Alignment.centerRight,
          child: CreateButton(
            collection: 'bookings',
            label: 'Новое бронирование',
            onPressed: () => context.go('/bookings/new'),
          ),
        ),
      );
  Widget _filters(BookingListNotifier notifier, CatalogNotifier catalog) =>
      AdaptiveFilters(child: _filterFields(notifier, catalog));

  Widget _filterFields(BookingListNotifier notifier, CatalogNotifier catalog) {
    final query = widget.query;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(spacing: 10, runSpacing: 10, children: [
        SizedBox(
            width: 280,
            child: QueryTextField(
                value: query.search,
                decoration: const InputDecoration(
                    labelText: 'Поиск: клиент, код, тип',
                    border: OutlineInputBorder()),
                onChanged: (value) {
                  _timer?.cancel();
                  _timer = Timer(const Duration(milliseconds: 350),
                      () => _go(query.copyWith(search: value)));
                })),
        SizedBox(
            width: 240,
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
        SizedBox(
            width: 260,
            child: DropdownButtonFormField<int?>(
                value: catalog.photographers
                        .any((p) => p.id == query.photographerId)
                    ? query.photographerId
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Фотограф', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<int?>(
                      value: null, child: Text('Все фотографы')),
                  for (final photographer in catalog.photographers)
                    DropdownMenuItem<int?>(
                        value: photographer.id,
                        child: Text(photographer.fullName,
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (value) =>
                    _go(query.copyWith(photographerId: value)))),
        SizedBox(
            width: 230,
            child: DropdownButtonFormField<String?>(
                value: catalog.shootingTypes.contains(query.shootingType)
                    ? query.shootingType
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Тип съёмки', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Все типы')),
                  for (final type in catalog.shootingTypes)
                    DropdownMenuItem<String?>(
                        value: type,
                        child: Text(type,
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (value) =>
                    _go(query.copyWith(shootingType: value)))),
        _numberField('Участников от', query.participantsFrom,
            (value) => _go(query.copyWith(participantsFrom: value))),
        _numberField('Участников до', query.participantsTo,
            (value) => _go(query.copyWith(participantsTo: value))),
        _dateField('Дата с', query.dateFrom,
            (value) => _go(query.copyWith(dateFrom: value))),
        _dateField('Дата по', query.dateTo,
            (value) => _go(query.copyWith(dateTo: value))),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Switch(
              value: query.includeDeleted,
              onChanged: (value) => _go(query.copyWith(includeDeleted: value))),
          const Text('Удалённые')
        ]),
        TextButton(
            onPressed: query.hasActiveFilters
                ? () => _go(BookingQuery(
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
          width: 150,
          child: QueryTextField(
              value: value?.toString(),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  labelText: label, border: OutlineInputBorder()),
              onFieldSubmitted: (text) => onChanged(int.tryParse(text))));
  Widget _dateField(
          String label, String? value, ValueChanged<String?> onChanged) =>
      SizedBox(
          width: 170,
          child: QueryTextField(
              value: value,
              decoration: InputDecoration(
                  labelText: label, border: OutlineInputBorder()),
              onFieldSubmitted: (text) =>
                  onChanged(text.trim().isEmpty ? null : text.trim())));
  Widget _selection(BookingListNotifier notifier) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: BulkActions(
          collection: 'bookings',
          count: notifier.selected.length,
          onDelete: () async {
            if (await confirm(context, 'Удалить выбранные бронирования?')) {
              await notifier.deleteSelected();
            }
          },
          onErase: () async {
            if (await confirm(context, 'Стереть выбранные бронирования?',
                hard: true)) {
              await notifier.eraseSelected();
            }
          },
          onClearSelection: notifier.clearSelection,
        ),
      );
  Widget _body(BookingListNotifier notifier, CatalogNotifier catalog) {
    if (notifier.status != LoadStatus.success) {
      return ListStateView(notifier: notifier);
    }
    if (notifier.result.items.isEmpty) {
      return EmptyView(
        message: 'Бронирования не найдены',
        hint: 'Попробуйте другое условие или снимите фильтры.',
      );
    }
    if (MediaQuery.sizeOf(context).width < compactWidth) {
      return ListView(children: [
        for (final item in notifier.result.items) _card(item, catalog)
      ]);
    }
    return EntityTable<Booking>(
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
          'Дата',
          'date',
          (item) => Text('${_formatDate(item.date)}'
              '${item.isDeleted ? ' (удалено)' : ''}')
        ),
        ('Клиент', 'clientName', (item) => Text(item.clientName)),
        ('Код', null, (item) => Text(item.accessCode)),
        ('Зал', null, (item) => Text(catalog.hallName(item.hallId))),
        (
          'Фотографы',
          null,
          (item) => Text(
              item.photographerIds.map(catalog.photographerName).join(', '))
        ),
        ('Тип', 'shootingType', (item) => Text(item.shootingType)),
        ('Часы', 'durationHours', (item) => Text('${item.durationHours}')),
        ('Участники', 'participants', (item) => Text('${item.participants}')),
      ],
      actions: (item) => _actions(item, catalog),
    );
  }

  Widget _card(Booking item, CatalogNotifier catalog) => Card(
        child: ResponsiveRecordTile(
          leading: Checkbox(
              value: context
                  .watch<BookingListNotifier>()
                  .selected
                  .contains(item.id),
              onChanged: (_) =>
                  context.read<BookingListNotifier>().toggle(item.id)),
          title: Text('${item.clientName} · ${_formatDate(item.date)}'),
          subtitle: Text(
              '${catalog.hallName(item.hallId)} · ${item.shootingType}\n'
              '${item.photographerIds.map(catalog.photographerName).join(', ')} · '
              '${item.durationHours} ч · ${item.participants} чел.\n'
              'Код: ${item.accessCode}'
              '${item.isDeleted ? ' · удалено' : ''}'),
          isThreeLine: true,
          trailing: Wrap(children: _actions(item, catalog)),
        ),
      );
  List<Widget> _actions(Booking item, CatalogNotifier catalog) {
    final buttons = RecordActions.buttons(
      collection: 'bookings',
      context: context,
      onView: () => context.go('/bookings/${item.id}'),
      permissions: context.watch<SessionStore>().permissions,
      onEdit: () => context.go('/bookings/${item.id}/edit'),
      isDeleted: item.isDeleted,
      onSoftDelete: () => _delete(item, hard: false),
      onRestore: () => context.read<BookingListNotifier>().restore(item.id),
      onHardDelete: () => _delete(item, hard: true),
    );

    if (item.isDeleted ||
        !context.watch<SessionStore>().permissions.canUpdate) {
      return buttons;
    }

    // Отменить бронирование можно только пока оно активное.
    if (item.status == 'active') {
      buttons.insert(
        0,
        IconButton(
          tooltip: 'Отменить бронирование',
          onPressed: () => _cancel(item),
          icon: const Icon(Icons.event_busy),
        ),
      );
    }

    // Завершить бронирование предлагается всегда: если оно уже закрыто,
    // сервер ответит 409, и приложение покажет это понятным сообщением.
    buttons.insert(
      0,
      IconButton(
        tooltip: 'Завершить бронирование',
        onPressed: () => _complete(item),
        icon: const Icon(Icons.task_alt),
      ),
    );
    return buttons;
  }

  /// Отменяет бронирование.
  ///
  /// Сервер проверяет состояние бронирования и отвечает 409, если оно уже
  /// закрыто. Приложение показывает этот ответ пользователю понятным
  /// сообщением, а не пустым экраном.
  Future<void> _cancel(Booking item) async {
    final notifier = context.read<BookingListNotifier>();
    if (!mounted) return;
    if (!await confirm(
      context,
      'Отменить бронирование «${item.clientName}» на ${_formatDate(item.date)}?',
    )) {
      return;
    }
    try {
      await notifier.cancel(item.id);
      if (!mounted) return;
      toast(context, 'Бронирование отменено.');
    } on Object catch (error) {
      if (!mounted) return;
      final outcome = toFormOutcome(error);
      showFormError(context, outcome);
    }
  }

  /// Завершает бронирование.
  ///
  /// Если бронирование уже закрыто, сервер отвечает 409 — приложение
  /// показывает сообщение пользователю.
  Future<void> _complete(Booking item) async {
    final notifier = context.read<BookingListNotifier>();
    if (!mounted) return;
    if (!await confirm(
      context,
      'Завершить бронирование «${item.clientName}» на ${_formatDate(item.date)}?',
    )) {
      return;
    }
    try {
      await notifier.complete(item.id);
      if (!mounted) return;
      toast(context, 'Бронирование завершено.');
    } on Object catch (error) {
      if (!mounted) return;
      final outcome = toFormOutcome(error);
      showFormError(context, outcome);
    }
  }

  Future<void> _delete(Booking item, {required bool hard}) async {
    final notifier = context.read<BookingListNotifier>();
    final catalog = context.read<CatalogNotifier>();
    if (!mounted) return;
    if (!await confirm(
        context,
        hard
            ? 'Стереть бронирование «${item.clientName}»?'
            : 'Удалить бронирование «${item.clientName}»?',
        hard: hard)) {
      return;
    }
    if (hard) {
      await notifier.hardDelete(item.id);
      await catalog.load();
    } else {
      await notifier.softDelete(item.id);
    }
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
}
