import 'package:html/dom.dart' as html_dom;
import 'package:y300/features/thread/domain/models/post_edit_models.dart';

final class DiscuzSuccessfulControls {
  const DiscuzSuccessfulControls({
    required this.fields,
    required this.namedControlNames,
    this.hasUnsupportedControlType = false,
  });

  final List<PostEditFormField> fields;
  final List<String> namedControlNames;
  final bool hasUnsupportedControlType;
}

class DiscuzSuccessfulControlExtractor {
  const DiscuzSuccessfulControlExtractor();

  DiscuzSuccessfulControls extract(html_dom.Element form) {
    final fields = <PostEditFormField>[];
    final names = <String>[];
    var hasUnsupportedControlType = false;

    for (final control in form.querySelectorAll('input, textarea, select')) {
      final name = control.attributes['name']?.trim() ?? '';
      if (name.isEmpty) {
        continue;
      }
      names.add(name);
      if (_isDisabled(control)) {
        continue;
      }

      if (control.localName == 'textarea') {
        fields.add(
          PostEditFormField(
            name: name,
            value: control.text,
            controlKind: PostEditFormControlKind.textarea,
          ),
        );
        continue;
      }
      if (control.localName == 'select') {
        if (_appendSelectFields(control, name, fields)) {
          hasUnsupportedControlType = true;
        }
        continue;
      }

      final type = (control.attributes['type'] ?? 'text').toLowerCase();
      switch (type) {
        case 'file' || 'submit' || 'button' || 'reset' || 'image':
          continue;
        case 'checkbox' || 'radio':
          if (!control.attributes.containsKey('checked')) {
            continue;
          }
          fields.add(
            PostEditFormField(
              name: name,
              value: control.attributes['value'] ?? 'on',
              controlKind: type == 'checkbox'
                  ? PostEditFormControlKind.checkbox
                  : PostEditFormControlKind.radio,
            ),
          );
        case 'hidden' ||
            'text' ||
            'search' ||
            'tel' ||
            'url' ||
            'email' ||
            'password' ||
            'number':
          fields.add(
            PostEditFormField(
              name: name,
              value: control.attributes['value'] ?? '',
              controlKind: type == 'hidden'
                  ? PostEditFormControlKind.hidden
                  : PostEditFormControlKind.text,
            ),
          );
        default:
          hasUnsupportedControlType = true;
      }
    }

    return DiscuzSuccessfulControls(
      fields: List.unmodifiable(fields),
      namedControlNames: List.unmodifiable(names),
      hasUnsupportedControlType: hasUnsupportedControlType,
    );
  }

  bool _appendSelectFields(
    html_dom.Element select,
    String name,
    List<PostEditFormField> fields,
  ) {
    final options = select.querySelectorAll('option');
    final enabledOptions = options.where((option) => !_isDisabled(option));
    final selected = enabledOptions
        .where((option) => option.attributes.containsKey('selected'))
        .toList(growable: false);
    final values = selected.isNotEmpty
        ? selected
        : (select.attributes.containsKey('multiple')
              ? const <html_dom.Element>[]
              : enabledOptions.isEmpty
              ? const <html_dom.Element>[]
              : <html_dom.Element>[enabledOptions.first]);
    for (final option in values) {
      fields.add(
        PostEditFormField(
          name: name,
          value: option.attributes['value'] ?? option.text,
          controlKind: PostEditFormControlKind.select,
        ),
      );
    }
    return !select.attributes.containsKey('multiple') && enabledOptions.isEmpty;
  }

  bool _isDisabled(html_dom.Element element) {
    if (element.attributes.containsKey('disabled')) {
      return true;
    }
    var parent = element.parent;
    while (parent != null) {
      final fieldset = parent.localName == 'fieldset' ? parent : null;
      if (fieldset == null) {
        parent = parent.parent;
        continue;
      }
      if (!fieldset.attributes.containsKey('disabled')) {
        parent = parent.parent;
        continue;
      }
      final firstLegend = fieldset.querySelector('legend');
      if (firstLegend == null || !_isDescendantOf(element, firstLegend)) {
        return true;
      }
      parent = parent.parent;
    }
    return false;
  }

  bool _isDescendantOf(html_dom.Element element, html_dom.Element ancestor) {
    var parent = element.parent;
    while (parent != null) {
      if (parent == ancestor) {
        return true;
      }
      parent = parent.parent;
    }
    return false;
  }
}
