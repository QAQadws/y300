import 'package:flutter/material.dart';

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
      child: Row(
        children: [
          SizedBox(width: 88, child: Text(label)),
          Expanded(
            child: SegmentedButton<T>(
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
            ),
          ),
        ],
      ),
    );
  }
}
