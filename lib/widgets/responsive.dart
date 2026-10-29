import 'package:flutter/material.dart';

/// Breakpoints are based on the viewport, so resizing keeps the current state.
const phoneWidth = 600.0;
const tableWidth = 1000.0;
const contentWidth = 1440.0;

class AdaptiveFilters extends StatelessWidget {
  const AdaptiveFilters({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= tableWidth) return child;
    return ExpansionTile(
      key: const PageStorageKey('catalog-filters'),
      title: const Text('Поиск и фильтры'),
      leading: const Icon(Icons.tune),
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .32),
          child: SingleChildScrollView(child: child),
        ),
      ],
    );
  }
}

/// Actions are below the text instead of competing for a narrow ListTile row.
class ResponsiveRecordTile extends StatelessWidget {
  const ResponsiveRecordTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.isThreeLine = false,
  });
  final Widget title;
  final Widget? subtitle, leading, trailing;
  final bool isThreeLine;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (leading != null)
              Tooltip(message: 'Выбрать запись', child: leading),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DefaultTextStyle.merge(
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                        child: title),
                    if (subtitle != null) ...[
                      const SizedBox(height: 6),
                      DefaultTextStyle.merge(
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                          child: subtitle!),
                    ],
                  ]),
            ),
          ]),
          if (trailing != null)
            Align(alignment: Alignment.centerRight, child: trailing),
        ]),
      );
}
