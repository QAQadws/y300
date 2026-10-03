import 'package:html/parser.dart' as html;

import '../contracts/forum_friend_operations.dart';

/// Complete supported friendship form, excluding unknown form controls.
final class DiscuzFriendForm {
  /// Creates a source form projection.
  const DiscuzFriendForm({
    required this.uri,
    required this.action,
    required this.hidden,
    required this.groups,
    required this.selectedGroupId,
  });

  /// Exact form endpoint.
  final Uri uri;

  /// Effect inferred from the source submit field.
  final ForumFriendAction action;

  /// Protected hidden fields, kept only in the adapter's token.
  final Map<String, String> hidden;

  /// Source group choices.
  final List<ForumFriendGroup> groups;

  /// Initial source group.
  final String? selectedGroupId;

  /// Validates the complete normal mobile GET form.
  static DiscuzFriendForm parse(
    String source, {
    required Uri origin,
    required String actor,
    required String target,
    required bool removing,
  }) {
    final document = html.parse(source);
    final actors = document
        .querySelectorAll('script')
        .expand(
          (node) => RegExp(
            r'''(?:^|[,;\s])discuz_uid\s*=\s*(['"])(\d+)\1''',
          ).allMatches(node.text),
        )
        .toList();
    if (actors.length != 1 || actors.single.group(2) != actor) {
      throw const FormatException('friend_actor_unverified');
    }
    final forms = document.querySelectorAll('form');
    if (forms.length != 1) {
      throw const FormatException('friend_form_ambiguous');
    }
    final form = forms.single;
    final id = form.id;
    final action = switch (id) {
      _ when id == 'friendform_$target' && removing => ForumFriendAction.remove,
      _ when id == 'addform_$target' && !removing => ForumFriendAction.request,
      _ when id == 'addratifyform_$target' && !removing =>
        ForumFriendAction.approve,
      _ => throw const FormatException('friend_form_target_invalid'),
    };
    if (form.attributes['method']?.toLowerCase() != 'post') {
      throw const FormatException('friend_form_method_unsupported');
    }
    final uri = origin.resolve(form.attributes['action'] ?? '');
    final query = Map<String, String>.of(uri.queryParameters);
    final mobile = query.remove('mobile');
    if (uri.scheme != origin.scheme ||
        uri.host != origin.host ||
        uri.port != origin.port ||
        uri.userInfo.isNotEmpty ||
        uri.path != '/home.php' ||
        uri.hasFragment ||
        uri.queryParametersAll.values.any((item) => item.length != 1) ||
        (mobile != null && mobile != '2')) {
      throw const FormatException('friend_form_action_untrusted');
    }
    if (action == ForumFriendAction.remove) {
      if (query.remove('confirm') != '1' || query.remove('loc') != '1') {
        throw const FormatException('friend_form_confirmation_missing');
      }
    }
    final expected = {
      'mod': 'spacecp',
      'ac': 'friend',
      'op': removing ? 'ignore' : 'add',
      'uid': target,
    };
    if (query.length != expected.length ||
        !expected.entries.every((entry) => query[entry.key] == entry.value)) {
      throw const FormatException('friend_form_action_untrusted');
    }
    final submitField = switch (action) {
      ForumFriendAction.request => 'addsubmit',
      ForumFriendAction.approve => 'add2submit',
      ForumFriendAction.remove => 'friendsubmit',
    };
    final hidden = <String, String>{};
    final groups = <ForumFriendGroup>[];
    String? selected;
    var noteCount = 0;
    var groupCount = 0;
    for (final control in form.querySelectorAll(
      'input, select, textarea, button',
    )) {
      final name = control.attributes['name'];
      if (name == null || control.attributes.containsKey('disabled')) {
        throw const FormatException('friend_form_control_unsupported');
      }
      final type = (control.attributes['type'] ?? 'text').toLowerCase();
      if (control.localName == 'button' && name == '${submitField}_btn') {
        continue;
      }
      if (control.localName == 'input' &&
          type == 'hidden' &&
          {
            'referer',
            'formhash',
            'handlekey',
            'from',
            submitField,
          }.contains(name)) {
        if (hidden.containsKey(name)) {
          throw const FormatException('friend_form_field_repeated');
        }
        hidden[name] = control.attributes['value'] ?? '';
      } else if (control.localName == 'input' &&
          type == 'text' &&
          name == 'note' &&
          action == ForumFriendAction.request) {
        noteCount++;
      } else if (control.localName == 'select' &&
          name == 'gid' &&
          action == ForumFriendAction.request &&
          !control.attributes.containsKey('multiple')) {
        groupCount++;
        for (final option in control.querySelectorAll('option')) {
          final optionId = option.attributes['value'] ?? '';
          _addGroup(groups, optionId, option.text);
          if (option.attributes.containsKey('selected')) {
            if (selected != null) {
              throw const FormatException('friend_group_ambiguous');
            }
            selected = optionId;
          }
        }
      } else if (control.localName == 'input' &&
          type == 'radio' &&
          name == 'gid' &&
          action == ForumFriendAction.approve) {
        groupCount++;
        final label = control.parent?.localName == 'label'
            ? control.parent!.text
            : '';
        final optionId = control.attributes['value'] ?? '';
        _addGroup(groups, optionId, label);
        if (control.attributes.containsKey('checked')) {
          if (selected != null) {
            throw const FormatException('friend_group_ambiguous');
          }
          selected = optionId;
        }
      } else {
        throw const FormatException('friend_form_control_unsupported');
      }
    }
    if (!RegExp(r'^[a-fA-F0-9]{8}$').hasMatch(hidden['formhash'] ?? '') ||
        hidden[submitField] != 'true' ||
        (action == ForumFriendAction.request &&
            (noteCount != 1 || groupCount != 1)) ||
        (action == ForumFriendAction.approve && groupCount == 0) ||
        (action != ForumFriendAction.remove && groups.isEmpty)) {
      throw const FormatException('friend_form_incomplete');
    }
    return DiscuzFriendForm(
      uri: uri,
      action: action,
      hidden: Map.unmodifiable(hidden),
      groups: List.unmodifiable(groups),
      selectedGroupId: selected ?? (groups.isEmpty ? null : groups.first.id),
    );
  }

  static void _addGroup(
    List<ForumFriendGroup> groups,
    String id,
    String rawName,
  ) {
    final name = rawName.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (!RegExp(r'^\d+$').hasMatch(id) ||
        name.isEmpty ||
        groups.any((item) => item.id == id)) {
      throw const FormatException('friend_group_invalid');
    }
    groups.add(ForumFriendGroup(id: id, name: name));
  }
}
