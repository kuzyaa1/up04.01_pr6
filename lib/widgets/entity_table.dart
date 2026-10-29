import 'package:flutter/material.dart';

class EntityTable<T> extends StatelessWidget {
  final List<T> items;
  final int Function(T) id;
  final Set<int> selected;
  final ValueChanged<int> toggle;
  final List<(String, String?, Widget Function(T))> columns;
  final String sort;
  final bool asc;
  final ValueChanged<String> onSort;
  final List<Widget> Function(T) actions;
  final bool Function(T)? isDeleted;
  const EntityTable(
      {super.key,
      required this.items,
      required this.id,
      required this.selected,
      required this.toggle,
      required this.columns,
      required this.sort,
      required this.asc,
      required this.onSort,
      required this.actions,
      this.isDeleted});
  @override
  Widget build(BuildContext context) {
    final sortIndex = columns.indexWhere((column) => column.$2 == sort);
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          sortColumnIndex: sortIndex < 0 ? null : sortIndex + 1,
          sortAscending: asc,
          columns: [
            const DataColumn(label: Text('')),
            for (final column in columns)
              DataColumn(
                label: Text(column.$1),
                onSort:
                    column.$2 == null ? null : (_, __) => onSort(column.$2!),
              ),
            const DataColumn(label: Text('Действия')),
          ],
          rows: [
            for (final item in items)
              DataRow(cells: [
                DataCell(Checkbox(
                    value: selected.contains(id(item)),
                    onChanged: (_) => toggle(id(item)))),
                for (final column in columns)
                  DataCell(ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 230),
                    child: DefaultTextStyle.merge(
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      child: column.$3(item),
                    ),
                  )),
                DataCell(Row(
                    mainAxisSize: MainAxisSize.min, children: actions(item))),
              ]),
          ],
        ),
      ),
    );
  }
}
