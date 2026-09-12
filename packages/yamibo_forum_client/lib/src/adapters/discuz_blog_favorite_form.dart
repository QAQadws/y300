import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import '../contracts/user_blog_favorites.dart';

/// The touch bookmark form; delete forms are used only to prove an existing ID.
final class DiscuzBlogFavoriteForm {
  DiscuzBlogFavoriteForm._(this.actionUri, this.fields);

  /// Validated, same-site submission endpoint.
  final Uri actionUri;

  /// Hidden fields excluding the untrusted referer; never expose to UI or logs.
  final Map<String, String> fields;

  /// Reads a complete new-bookmark form, rejecting extra validation or plugins.
  static DiscuzBlogFavoriteForm parse(
    String source,
    Uri origin,
    UserBlogFavoriteTarget target,
  ) {
    final (form, uri) = _form(source, origin);
    final query = uri.queryParameters;
    if (form.id != 'favoriteform_${target.blogId}' ||
        query['id'] != target.blogId ||
        query['spaceuid'] != target.ownerUserId ||
        !query.keys.every(
          {'mod', 'ac', 'type', 'id', 'spaceuid', 'mobile'}.contains,
        )) {
      throw const FormatException('blog_favorite_target_mismatch');
    }
    return DiscuzBlogFavoriteForm._(uri, _fields(form, existing: false));
  }

  /// Proves a current-account bookmark ID after reading its exact targeted GET.
  /// This never returns a delete ticket or allows the delete form to be posted.
  static String existingId(String source, Uri origin) {
    final (form, uri) = _form(source, origin);
    final query = uri.queryParameters;
    final id = query['favid'] ?? '';
    if (query['op'] != 'delete' ||
        !RegExp(r'^[1-9]\d*$').hasMatch(id) ||
        form.id != 'favoriteform_$id' ||
        !query.keys.every(
          {'mod', 'ac', 'op', 'favid', 'type', 'mobile'}.contains,
        )) {
      throw const FormatException('blog_favorite_existing_unproved');
    }
    _fields(form, existing: true);
    return id;
  }

  /// A source business notice may mean a duplicate. Text alone is not proof.
  static bool isNotice(String source) {
    final document = html.parse(source);
    return document.querySelector('form') == null &&
        document.querySelector('#messagetext, .jump_c, .alert_error') != null;
  }

  static (Element, Uri) _form(String source, Uri origin) {
    final document = html.parse(source);
    final forms = document.querySelectorAll('form[id^="favoriteform_"]');
    if (forms.length != 1) {
      throw const FormatException('blog_favorite_form_missing');
    }
    final form = forms.single;
    if (document
        .querySelectorAll('[form]')
        .any((node) => node.attributes['form'] == form.id)) {
      throw const FormatException('blog_favorite_external_controls');
    }
    final uri = origin.resolve(form.attributes['action'] ?? '');
    if (form.attributes['method']?.toLowerCase() != 'post' ||
        (form.attributes['onsubmit'] ?? '').trim().isNotEmpty ||
        !{
          null,
          'application/x-www-form-urlencoded',
        }.contains(form.attributes['enctype']) ||
        uri.scheme != origin.scheme ||
        uri.host != origin.host ||
        uri.port != origin.port ||
        uri.userInfo.isNotEmpty ||
        uri.path != '/home.php' ||
        uri.hasFragment ||
        uri.queryParametersAll.values.any((values) => values.length != 1) ||
        uri.queryParameters['mod'] != 'spacecp' ||
        uri.queryParameters['ac'] != 'favorite' ||
        uri.queryParameters['type'] != 'blog' ||
        uri.queryParameters['mobile'] != '2') {
      throw const FormatException('blog_favorite_form_unsupported');
    }
    return (form, uri);
  }

  static Map<String, String> _fields(Element form, {required bool existing}) {
    final flag = existing ? 'deletesubmit' : 'favoritesubmit';
    final button = existing ? 'deletesubmitbtn' : 'favoritesubmit_btn';
    final fields = <String, String>{};
    final names = <String>{};
    for (final control in form.querySelectorAll(
      'input[name], textarea[name], select[name], button[name]',
    )) {
      final name = control.attributes['name']!;
      if (!names.add(name) ||
          control.attributes.containsKey('disabled') ||
          control.attributes.containsKey('readonly') ||
          const {
            'formaction',
            'formmethod',
            'formenctype',
            'formtarget',
            'formnovalidate',
            'onclick',
          }.any(control.attributes.containsKey)) {
        throw const FormatException('blog_favorite_control_unsupported');
      }
      if (name == button &&
          control.localName == 'input' &&
          control.attributes['type'] == 'submit') {
        continue;
      }
      // The touch template fills this with a localized placeholder, not saved
      // data. Native input starts empty and posts only the reader's own note.
      if (!existing &&
          name == 'description' &&
          control.localName == 'textarea') {
        continue;
      }
      if (!{'formhash', 'referer', flag}.contains(name) ||
          control.localName != 'input' ||
          control.attributes['type'] != 'hidden') {
        throw const FormatException('blog_favorite_control_unsupported');
      }
      fields[name] = control.attributes['value'] ?? '';
    }
    if ((fields['formhash'] ?? '').trim().isEmpty ||
        fields[flag] != 'true' ||
        (!existing && !names.contains('description'))) {
      throw const FormatException('blog_favorite_form_incomplete');
    }
    fields.remove('referer');
    return Map.unmodifiable(fields);
  }
}
