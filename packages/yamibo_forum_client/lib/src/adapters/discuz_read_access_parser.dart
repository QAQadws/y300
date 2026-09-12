import 'package:html/dom.dart';

import '../contracts/thread_read_access.dart';

/// Parses only the thread control, never attachment permission controls.
final class DiscuzReadAccessParser {
  /// Creates a stateless parser for the topic permission control.
  const DiscuzReadAccessParser();

  /// Rejects ambiguous values; an edit without selected evidence stays unknown.
  ThreadReadAccess parse(Element form, {required bool creating}) {
    final controls = form.querySelectorAll('[name="readperm"]');
    if (controls.isEmpty) return ThreadReadAccess.unavailable;
    if (controls.length != 1) {
      throw const FormatException('read_access_duplicate_control');
    }
    final control = controls.single;
    if (control.localName == 'input' &&
        control.attributes['type']?.toLowerCase() == 'hidden') {
      return ThreadReadAccess(
        canModify: false,
        currentValue: _value(control.attributes['value'] ?? ''),
      );
    }
    if (control.localName != 'select' ||
        control.attributes.containsKey('multiple')) {
      throw const FormatException('read_access_control_unsupported');
    }
    final names = <int, List<String>>{};
    final selected = <int>{};
    for (final option in control.querySelectorAll('option')) {
      final value = _value(option.attributes['value'] ?? option.text);
      final label = option.text.trim();
      if (option.attributes.containsKey('selected')) selected.add(value);
      // Disabled choices still prove the current value, but cannot be selected.
      if (discuzControlDisabled(option)) continue;
      final labels = names.putIfAbsent(value, () => []);
      if (label.isNotEmpty && !labels.contains(label)) labels.add(label);
    }
    if (selected.length > 1) {
      throw const FormatException('read_access_selection_ambiguous');
    }
    final canModify = !discuzControlDisabled(control);
    return ThreadReadAccess(
      canModify: canModify,
      // For an edit, no selected option can also mean an obsolete threshold.
      // The adapter must read the thread before treating it as unrestricted.
      currentValue: selected.singleOrNull ?? (creating ? 0 : null),
      options: List.unmodifiable([
        for (final entry in names.entries)
          ThreadReadAccessOption(
            value: entry.key,
            groupNames: List.unmodifiable(entry.value),
          ),
      ]),
    );
  }

  int _value(String raw) {
    final text = raw.trim();
    final value = text.isEmpty ? 0 : int.tryParse(text);
    if (value == null || value < 0 || value > 255) {
      throw const FormatException('read_access_value_invalid');
    }
    return value;
  }
}

/// HTML disabled-state semantics, including the first fieldset legend exception.
bool discuzControlDisabled(Element control) {
  if (control.attributes.containsKey('disabled')) return true;
  var parent = control.parent;
  while (parent != null) {
    if (parent.localName == 'optgroup' &&
        parent.attributes.containsKey('disabled')) {
      return true;
    }
    if (parent.localName == 'fieldset' &&
        parent.attributes.containsKey('disabled')) {
      final legend = parent.children
          .where((e) => e.localName == 'legend')
          .firstOrNull;
      if (legend == null || !legend.contains(control)) return true;
    }
    parent = parent.parent;
  }
  return false;
}
