import 'package:html/parser.dart' as html;

import '../contracts/user_blog_comments.dart';
import '../url/forum_uri_resolver.dart';

/// Validated form data retained only by the comment adapter.
final class DiscuzBlogCommentForm {
  /// Creates a validated form.
  const DiscuzBlogCommentForm({
    required this.actionUri,
    required this.fields,
    required this.message,
  });

  /// Same-site submission destination.
  final Uri actionUri;

  /// Known form fields, with transport-owned referer and handle key omitted.
  final Map<String, String> fields;

  /// Existing editable message.
  final String message;

  /// Parses only the known mobile comment forms.
  static DiscuzBlogCommentForm parse(
    String source, {
    required Uri siteOrigin,
    required UserBlogCommentTarget target,
  }) {
    final payload =
        RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>').firstMatch(source)?.group(1) ??
        source;
    final document = html.parse(payload);
    final forms = document.querySelectorAll('form').where((form) {
      final action = form.attributes['action'] ?? '';
      return action.contains('ac=comment');
    }).toList();
    if (forms.length != 1) {
      throw const FormatException('blog_comment_form_missing');
    }
    final form = forms.single;
    if (form.attributes['method']?.toLowerCase() != 'post') {
      throw const FormatException('blog_comment_form_method');
    }
    final resolver = ForumUriResolver(siteOrigin: siteOrigin);
    final uri = resolver.resolve(form.attributes['action']!);
    final editing =
        target.action == UserBlogCommentAction.edit ||
        target.action == UserBlogCommentAction.delete;
    if (!resolver.isSameSite(uri) ||
        uri.scheme != siteOrigin.scheme ||
        uri.port != siteOrigin.port ||
        uri.userInfo.isNotEmpty ||
        uri.path != '/home.php' ||
        uri.queryParametersAll.values.any((values) => values.length != 1) ||
        uri.queryParameters['mod'] != 'spacecp' ||
        uri.queryParameters['ac'] != 'comment' ||
        (editing
            ? uri.queryParameters['op'] != target.action.name ||
                  uri.queryParameters['cid'] != target.commentId
            : uri.queryParameters['op'] != null ||
                  uri.queryParameters['cid'] != null) ||
        uri.queryParameters.keys.any(
          (key) => !{'mod', 'ac', 'op', 'cid', 'mobile'}.contains(key),
        )) {
      throw const FormatException('blog_comment_form_action');
    }
    const known = {
      'formhash',
      'referer',
      'id',
      'idtype',
      'cid',
      'handlekey',
      'commentsubmit',
      'quickcomment',
      'editsubmit',
      'deletesubmit',
      'message',
      'commentsubmit_btn',
      'editsubmit_btn',
      'deletesubmitbtn',
    };
    final fields = <String, String>{};
    for (final control in form.querySelectorAll(
      'input[name], textarea[name], select[name], button[name]',
    )) {
      final name = control.attributes['name']!;
      if (!known.contains(name)) {
        throw const FormatException('blog_comment_form_unsupported');
      }
      if (control.localName == 'button' ||
          control.attributes['type'] == 'submit') {
        continue;
      }
      if (fields.containsKey(name) ||
          control.attributes.containsKey('disabled')) {
        throw const FormatException('blog_comment_form_ambiguous');
      }
      fields[name] = control.localName == 'textarea'
          ? control.text
          : control.attributes['value'] ?? '';
    }
    final flag = switch (target.action) {
      UserBlogCommentAction.edit => 'editsubmit',
      UserBlogCommentAction.delete => 'deletesubmit',
      _ => 'commentsubmit',
    };
    if ((fields['formhash'] ?? '').isEmpty ||
        fields[flag] != 'true' ||
        (!editing &&
            (fields['id'] != target.blogId || fields['idtype'] != 'blogid')) ||
        (editing && fields.keys.any({'id', 'idtype', 'cid'}.contains)) ||
        (target.action == UserBlogCommentAction.reply &&
            fields['cid'] != target.commentId) ||
        (target.action == UserBlogCommentAction.add &&
            fields.containsKey('cid')) ||
        (target.action != UserBlogCommentAction.delete &&
            form.querySelector('textarea[name="message"]') == null) ||
        fields.keys.any(
          (key) =>
              {'commentsubmit', 'editsubmit', 'deletesubmit'}.contains(key) &&
              key != flag,
        )) {
      throw const FormatException('blog_comment_form_identity');
    }
    final message = fields.remove('message') ?? '';
    fields.remove('referer');
    fields.remove('handlekey');
    fields.remove('quickcomment');
    return DiscuzBlogCommentForm(
      actionUri: uri,
      fields: Map.unmodifiable(fields),
      message: message,
    );
  }
}
