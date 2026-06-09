import 'package:flutter/material.dart';

class ReaderActionSheetItem<T extends Object> {
  const ReaderActionSheetItem({
    required this.id,
    required this.value,
    required this.icon,
    required this.label,
    this.enabled = true,
  });

  final String id;
  final T value;
  final IconData icon;
  final String label;
  final bool enabled;
}

class ReaderActionSheet<T extends Object> extends StatelessWidget {
  const ReaderActionSheet({
    super.key,
    required this.title,
    required this.items,
  });

  final String title;
  final List<ReaderActionSheetItem<T>> items;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        key: const Key('shared-reader-action-sheet'),
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          ReaderSheetTitle(title: title),
          for (final item in items)
            ListTile(
              key: Key('shared-reader-action-${item.id}'),
              leading: Icon(item.icon),
              title: Text(item.label),
              enabled: item.enabled,
              onTap: item.enabled
                  ? () => Navigator.of(context).pop<T>(item.value)
                  : null,
            ),
        ],
      ),
    );
  }
}

class ReaderSheetTitle extends StatelessWidget {
  const ReaderSheetTitle({
    super.key,
    required this.title,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}

class ReaderSegmentControl<T extends Object> extends StatelessWidget {
  const ReaderSegmentControl({
    super.key,
    required this.label,
    required this.value,
    required this.values,
    required this.labelBuilder,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final T value;
  final List<T> values;
  final String Function(T value) labelBuilder;
  final ValueChanged<T> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final control = SegmentedButton<T>(
            segments: [
              for (final item in values)
                ButtonSegment<T>(
                  value: item,
                  label: Text(labelBuilder(item)),
                ),
            ],
            selected: {value},
            showSelectedIcon: false,
            onSelectionChanged: enabled
                ? (selection) {
                    if (selection.isNotEmpty) {
                      onChanged(selection.first);
                    }
                  }
                : null,
          );
          if (constraints.maxWidth < 360) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(label),
                const SizedBox(height: 6),
                control,
              ],
            );
          }
          return Row(
            children: [
              SizedBox(width: 88, child: Text(label)),
              Expanded(child: control),
            ],
          );
        },
      ),
    );
  }
}
