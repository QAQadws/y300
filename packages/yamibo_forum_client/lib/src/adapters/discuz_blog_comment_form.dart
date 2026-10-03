import 'package:html/parser.dart' as html;

import '../contracts/user_blog_comments.dart';
import '../url/forum_uri_resolver.dart';
import 'discuz_friend_literal_parser.dart';

/// Validated form data retained only by the comment adapter.
final class DiscuzBlogCommentForm {
  /// Creates a validated form.
  const DiscuzBlogCommentForm({
    required this.actionUri,
    required this.fields,
    required this.message,
    this.smilies = const [],
  });

  /// Same-site submission destination.
  final Uri actionUri;

  /// Known form fields, with transport-owned referer and handle key omitted.
  final Map<String, String> fields;

  /// Existing editable message.
  final String message;

  /// Dedicated home comment codes and resources, never forum sticker codes.
  final List<UserBlogCommentSmiley> smilies;

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
      smilies: target.action == UserBlogCommentAction.delete
          ? const []
          : _smilies(
              document
                  .querySelectorAll('script')
                  .where((script) {
                    final type = (script.attributes['type'] ?? '')
                        .trim()
                        .toLowerCase();
                    return !script.attributes.containsKey('src') &&
                        const {
                          '',
                          'text/javascript',
                          'application/javascript',
                          'text/ecmascript',
                          'application/ecmascript',
                        }.contains(type);
                  })
                  .map((script) => script.text),
              siteOrigin,
            ),
    );
  }
}

List<UserBlogCommentSmiley> _smilies(Iterable<String> scripts, Uri siteOrigin) {
  try {
    final roots = scripts
        .expand(_staticUrlValues)
        .map(siteOrigin.resolve)
        .toSet();
    if (roots.length != 1) return const [];
    final root = roots.single;
    if (!{'http', 'https'}.contains(root.scheme) ||
        root.host.isEmpty ||
        root.userInfo.isNotEmpty ||
        root.query.isNotEmpty ||
        root.fragment.isNotEmpty ||
        !root.path.endsWith('/')) {
      return const [];
    }
    // home.js showFace advertises exactly 1..30; class_bbcode uses these codes
    // even though the touch template has no smiley picker of its own.
    return List.unmodifiable([
      for (var index = 1; index <= 30; index++)
        UserBlogCommentSmiley(
          index: index,
          code: '[em:$index:]',
          imageUri: root.resolve('image/smiley/comcom/$index.gif'),
        ),
    ]);
  } on FormatException {
    return const [];
  }
}

Iterable<String> _staticUrlValues(String script) sync* {
  final tokens = _scriptTokens(script);
  var depth = 0;
  for (var index = 0; index < tokens.length; index++) {
    final token = tokens[index];
    if (const {'(', '[', '{'}.contains(token)) depth++;
    if (const {')', ']', '}'}.contains(token)) depth--;
    if (token != 'STATICURL') continue;
    final next = index + 1 < tokens.length ? tokens[index + 1] : '';
    final following = index + 2 < tokens.length ? tokens[index + 2] : '';
    final previous = index > 0 ? tokens[index - 1] : '';
    if (next == '=' && following == '=') continue;
    if (next != '=') {
      if ((const {'+', '-', '*', '/', '%', '&', '|', '^', '?'}.contains(next) &&
              (following == '=' || following == next)) ||
          (index > 1 &&
              const {'+', '-'}.contains(previous) &&
              tokens[index - 2] == previous)) {
        throw const FormatException('blog_comment_static_assignment');
      }
      continue;
    }
    final terminator = index + 3 < tokens.length ? tokens[index + 3] : '';
    // The stock header declares simple global scalars. A computed value,
    // nested/property assignment, or later unknown reassignment proves no root.
    if (depth != 0 ||
        !const {'', 'var', 'let', 'const', ',', ';'}.contains(previous) ||
        !const {'', ',', ';'}.contains(terminator) ||
        !(following.startsWith("'") || following.startsWith('"'))) {
      throw const FormatException('blog_comment_static_assignment');
    }
    yield DiscuzFriendLiteralParser().parse('{0:$following}')["0"] as String;
  }
}

List<String> _scriptTokens(String source) {
  if (source.length > 131072) {
    throw const FormatException('blog_comment_static_size');
  }
  final tokens = <String>[];
  final whitespace = RegExp(r'\s');
  final identifierStart = RegExp(r'[a-zA-Z_$]');
  final identifierPart = RegExp(r'[a-zA-Z0-9_$]');
  var offset = 0;
  while (offset < source.length) {
    final char = source[offset];
    if (whitespace.hasMatch(char)) {
      offset++;
      continue;
    }
    if (source.startsWith('//', offset) || source.startsWith('<!--', offset)) {
      final end = source.indexOf(RegExp(r'[\r\n]'), offset);
      offset = end < 0 ? source.length : end;
      continue;
    }
    if (source.startsWith('/*', offset)) {
      final end = source.indexOf('*/', offset + 2);
      if (end < 0) throw const FormatException('blog_comment_static_comment');
      offset = end + 2;
      continue;
    }
    if (char == "'" || char == '"' || char == '`') {
      final start = offset++;
      while (offset < source.length && source[offset] != char) {
        offset += source[offset] == r'\' ? 2 : 1;
      }
      if (offset >= source.length) {
        throw const FormatException('blog_comment_static_string');
      }
      final literal = source.substring(start, ++offset);
      if (char == '`' &&
          literal.contains(r'${') &&
          RegExp(r'\bSTATICURL\b').hasMatch(literal)) {
        throw const FormatException('blog_comment_static_template');
      }
      tokens.add(literal);
      continue;
    }
    // A regex literal is another opaque value, not declaration evidence.
    if (char == '/' &&
        (tokens.isEmpty ||
            const {
              '=',
              '(',
              '[',
              '{',
              ':',
              ';',
              ',',
              '!',
              '?',
              '&',
              '|',
              'return',
              'case',
              'throw',
            }.contains(tokens.last))) {
      offset++;
      var inClass = false;
      while (offset < source.length) {
        final current = source[offset++];
        if (current == r'\') {
          offset++;
        } else if (current == '[') {
          inClass = true;
        } else if (current == ']') {
          inClass = false;
        } else if (current == '/' && !inClass) {
          break;
        }
      }
      tokens.add('/regex/');
      continue;
    }
    if (identifierStart.hasMatch(char)) {
      final start = offset++;
      while (offset < source.length &&
          identifierPart.hasMatch(source[offset])) {
        offset++;
      }
      tokens.add(source.substring(start, offset));
    } else {
      tokens.add(char);
      offset++;
    }
  }
  return tokens;
}
