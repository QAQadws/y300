import 'package:flutter/material.dart';
import 'package:y300/l10n/app_localizations.dart';

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
  const ReaderSheetTitle({super.key, required this.title});

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
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final control = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in values)
                _ReaderChoiceButton(
                  key: ValueKey<String>('reader-segment-${labelBuilder(item)}'),
                  label: labelBuilder(item),
                  selected: item == value,
                  enabled: enabled,
                  scheme: scheme,
                  onPressed: () => onChanged(item),
                ),
            ],
          );
          if (constraints.maxWidth < 360) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [Text(label), const SizedBox(height: 6), control],
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

class _ReaderChoiceButton extends StatelessWidget {
  const _ReaderChoiceButton({
    super.key,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.scheme,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final ColorScheme scheme;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? scheme.onPrimaryContainer : scheme.onSurface;
    final border = selected ? scheme.primary : scheme.outline;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: selected
          ? AppLocalizations.of(context).readerSelectedSemantics(label)
          : label,
      child: OutlinedButton(
        onPressed: enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          backgroundColor: selected ? scheme.primaryContainer : null,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          side: BorderSide(
            color: selected ? Colors.transparent : border,
            width: selected ? 0 : 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: TextStyle(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}
