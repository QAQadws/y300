import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../contracts/profile_and_blog.dart';
import '../contracts/user_blog_operations.dart';

/// Parses the complete editor, because the touch editor omits access fields.
final class DiscuzBlogEditorForm {
  /// Keeps complete source fields inside the adapter's transient form ticket.
  DiscuzBlogEditorForm({
    required this.actionUri,
    required this.fields,
    required this.siteCategories,
    required this.personalCategories,
    required this.siteCategoryRequired,
    required this.canCreateCategory,
    required this.canPublishFeed,
  });

  /// Verified endpoint matching the requested edit or publishing operation.
  final Uri actionUri;

  /// Complete source values, including access fields; never expose or persist.
  final Map<String, String> fields;

  /// Advertised site categories with normalized source identifiers.
  final List<UserBlogCategory> siteCategories;

  /// Author-owned category choices, separate from the create-category option.
  final List<UserBlogCategory> personalCategories;

  /// Whether the source omits the optional site-category choice.
  final bool siteCategoryRequired;

  /// Whether the form explicitly permits a new personal category.
  final bool canCreateCategory;

  /// Whether the form exposes a feed-publication control.
  final bool canPublishFeed;

  /// Exposes editable content and a privacy summary while retaining access fields.
  UserBlogEditorPreparation preparation(
    UserBlogTarget target,
    UserBlogOperationToken token,
  ) => UserBlogEditorPreparation(
    target: target,
    token: token,
    subject: fields['subject']!,
    bodyHtml: fields['message']!,
    tags: fields['tag']!,
    siteCategories: siteCategories,
    personalCategories: personalCategories,
    siteCategoryId: fields['catid'] ?? '0',
    personalCategoryId: fields['classid']!,
    siteCategoryRequired: siteCategoryRequired,
    canCreateCategory: canCreateCategory,
    canPublishFeed: canPublishFeed,
    publishFeed: fields['makefeed'] == '1',
    visibility: UserBlogVisibility.values[int.parse(fields['friend']!)],
    commentsEnabled: fields['noreply'] != '1',
  );

  /// Validates the complete editor instead of defaulting missing privacy inputs.
  static DiscuzBlogEditorForm parse(
    String source, {
    required Uri siteOrigin,
    required UserBlogTarget target,
  }) {
    final document = html.parse(source);
    final forms = document.querySelectorAll('form#ttHtmlEditor');
    if (forms.length != 1) {
      throw const FormatException('blog_complete_editor_missing');
    }
    final form = forms.single;
    final action = blogFormAction(form, siteOrigin: siteOrigin, target: target);
    if (target.action == UserBlogAction.edit) {
      final matches = document.querySelectorAll('#pt a[href]').where((node) {
        final uri = siteOrigin.resolve(node.attributes['href']!);
        return sameBlogSite(uri, siteOrigin) &&
            uri.path == '/home.php' &&
            uri.queryParametersAll.values.every(
              (values) => values.length == 1,
            ) &&
            uri.queryParameters['mod'] == 'space' &&
            uri.queryParameters['do'] == 'blog' &&
            uri.queryParameters['id'] == target.blogId &&
            uri.queryParameters['uid'] == target.ownerUserId;
      });
      if (matches.isEmpty) {
        throw const FormatException('blog_editor_owner_unverified');
      }
    }
    const contentNames = {
      'formhash',
      'blogsubmit',
      'subject',
      'message',
      'classid',
      'catid',
      'tag',
      'friend',
      'noreply',
      'password',
      'target_names',
      'hot',
      'makefeed',
    };
    // Unused controls from the standard desktop image menu. No picture IDs or
    // uploaded files are accepted here, so these controls have no server effect.
    const auxiliary = {
      'selectgroup',
      'savealbumid',
      'newalbum',
      'view_albumid',
    };
    final fields = <String, String>{};
    for (final control in form.querySelectorAll(
      'input[name], textarea[name], select[name], button[name]',
    )) {
      final name = control.attributes['name']!;
      if (auxiliary.contains(name)) continue;
      if (!contentNames.contains(name) ||
          fields.containsKey(name) ||
          control.attributes.containsKey('disabled')) {
        throw const FormatException('blog_editor_controls_unsupported');
      }
      if (control.localName == 'select') {
        final value = selectedBlogOption(control);
        // category_showselect uses an empty option for the optional site
        // category; the public contract and PHP integer handling use zero.
        fields[name] = name == 'catid' && value.isEmpty ? '0' : value;
      } else if (control.localName == 'textarea') {
        fields[name] = control.text;
      } else if (control.localName == 'input') {
        final type = control.attributes['type'] ?? 'text';
        if (type == 'checkbox') {
          if (!{'makefeed', 'noreply'}.contains(name) ||
              control.attributes['value'] != '1') {
            throw const FormatException('blog_editor_checkbox_unsupported');
          }
          fields[name] = control.attributes.containsKey('checked') ? '1' : '0';
        } else if (type == 'text' || type == 'hidden' || type == 'password') {
          fields[name] = control.attributes['value'] ?? '';
        } else {
          throw const FormatException('blog_editor_input_unsupported');
        }
      } else {
        throw const FormatException('blog_editor_control_unsupported');
      }
    }
    if (!fields.keys.toSet().containsAll({
          'formhash',
          'blogsubmit',
          'subject',
          'message',
          'classid',
          'tag',
          'friend',
          'noreply',
          'password',
          'target_names',
        }) ||
        fields['formhash']!.trim().isEmpty ||
        fields['blogsubmit'] != 'true' ||
        !RegExp(r'^[0-4]$').hasMatch(fields['friend']!) ||
        (fields['friend'] == '4' && fields['password']!.trim().isEmpty) ||
        (fields['friend'] == '2' && fields['target_names']!.trim().isEmpty) ||
        !{'0', '1'}.contains(fields['noreply'])) {
      throw const FormatException('blog_editor_access_unverified');
    }
    final personal = blogCategoryOptions(
      form.querySelector('select[name="classid"]'),
    );
    final site = blogCategoryOptions(
      form.querySelector('select[name="catid"]'),
    );
    final createCategory =
        form.querySelector(
          'select[name="classid"] option[value="addoption"]',
        ) !=
        null;
    if (!personal.any((value) => value.id == fields['classid']) ||
        (fields['catid'] != null &&
            !site.any((value) => value.id == fields['catid']))) {
      throw const FormatException('blog_editor_category_invalid');
    }
    final requiredCategory =
        site.isNotEmpty &&
        (!site.any((value) => value.id == '0') ||
            document
                .querySelectorAll('script')
                .any(
                  (script) =>
                      RegExp(r'catObj\.value\s*<\s*1').hasMatch(script.text),
                ));
    return DiscuzBlogEditorForm(
      actionUri: action,
      fields: Map.unmodifiable(fields),
      siteCategories: site,
      personalCategories: personal,
      siteCategoryRequired: requiredCategory,
      canCreateCategory: createCategory,
      canPublishFeed: fields.containsKey('makefeed'),
    );
  }
}

/// Resolves the form endpoint and verifies its operation and article identity.
Uri blogFormAction(
  Element form, {
  required Uri siteOrigin,
  required UserBlogTarget target,
}) {
  final action = form.attributes['action'];
  if (action == null || form.attributes['method']?.toLowerCase() != 'post') {
    throw const FormatException('blog_form_action_missing');
  }
  final uri = siteOrigin.resolve(action);
  final expectedOp = switch (target.action) {
    UserBlogAction.delete => 'delete',
    UserBlogAction.pin || UserBlogAction.unpin => 'stick',
    _ => null,
  };
  final id = uri.queryParameters['blogid'];
  if (!sameBlogSite(uri, siteOrigin) ||
      uri.path != '/home.php' ||
      uri.hasFragment ||
      uri.queryParameters['mod'] != 'spacecp' ||
      uri.queryParameters['ac'] != 'blog' ||
      uri.queryParameters['op'] != expectedOp ||
      (target.action == UserBlogAction.create
          ? id != null && id != '' && id != '0'
          : id != target.blogId) ||
      uri.queryParametersAll.values.any((values) => values.length != 1) ||
      uri.queryParameters.keys.any(
        (key) => !{'mod', 'ac', 'blogid', 'op', 'mobile'}.contains(key),
      )) {
    throw const FormatException('blog_form_action_invalid');
  }
  return uri;
}

/// Compares the exact source authority without accepting credentialed URLs.
bool sameBlogSite(Uri uri, Uri origin) =>
    uri.scheme == origin.scheme &&
    uri.host == origin.host &&
    uri.port == origin.port &&
    uri.userInfo.isEmpty;

/// Reads an unambiguous source selection, including the first-option default.
String selectedBlogOption(Element select) {
  if (select.attributes.containsKey('multiple')) {
    throw const FormatException('blog_form_multiselect_unsupported');
  }
  final options = select.querySelectorAll('option');
  final selected = options
      .where((option) => option.attributes.containsKey('selected'))
      .toList();
  if (options.isEmpty || selected.length > 1) {
    throw const FormatException('blog_form_selection_invalid');
  }
  return (selected.isEmpty ? options.first : selected.single)
          .attributes['value'] ??
      '';
}

/// Extracts category choices while rejecting conflicting duplicate identities.
List<UserBlogCategory> blogCategoryOptions(Element? select) {
  if (select == null) return const [];
  final values = <String, UserBlogCategory>{};
  for (final option in select.querySelectorAll('option')) {
    final rawId = option.attributes['value'] ?? '';
    final id = rawId.isEmpty && select.attributes['name'] == 'catid'
        ? '0'
        : rawId;
    if (id == 'addoption') continue;
    if (!RegExp(r'^(0|[1-9]\d*)$').hasMatch(id) || values.containsKey(id)) {
      throw const FormatException('blog_category_options_invalid');
    }
    if (option.attributes.containsKey('disabled')) continue;
    values[id] = UserBlogCategory(id: id, name: option.text.trim());
  }
  return List.unmodifiable(values.values);
}
