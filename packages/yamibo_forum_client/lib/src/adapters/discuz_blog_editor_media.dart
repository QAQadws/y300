import 'package:html/parser.dart' as html;

import '../contracts/forum_image_attachments.dart';
import '../contracts/user_blog_media.dart';

/// Source-proved upload credentials; retained only in the editor token.
final class DiscuzBlogEditorMedia {
  /// Keeps the upload hash private to the protocol layer.
  const DiscuzBlogEditorMedia({
    required this.uploadUri,
    required this.uid,
    required this.hash,
    required this.limits,
  });

  /// Verified album upload destination.
  final Uri uploadUri;

  /// Server-provided actor.
  final String uid;

  /// Transient upload hash, never expose or log.
  final String hash;

  /// Source-proved limits.
  final UserBlogImageUploadLimits limits;

  /// Missing or customized upload controls disable media without blocking text.
  static DiscuzBlogEditorMedia? parse(
    String source, {
    required Uri siteOrigin,
    required String actor,
  }) {
    try {
      return _parse(source, siteOrigin: siteOrigin, actor: actor);
    } on FormatException {
      return null;
    }
  }

  static DiscuzBlogEditorMedia? _parse(
    String source, {
    required Uri siteOrigin,
    required String actor,
  }) {
    final document = html.parse(source);
    if (document.querySelector('#icoImg_btn_imgattachlist') == null) {
      return null;
    }
    final matches = document
        .querySelectorAll('script')
        .expand(
          (script) => RegExp(
            r'\bvar\s+upload\s*=\s*new\s+SWFUpload\s*\(\s*\{([\s\S]*?)\}\s*\)',
          ).allMatches(script.text),
        )
        .toList();
    if (matches.length != 1) return null;
    final block = matches.single.group(1)!;
    String? value(String name) => RegExp(
      '''["']?${RegExp.escape(name)}["']?\\s*:\\s*["']([^"']*)["']''',
    ).firstMatch(block)?.group(1);
    final rawUri = value('upload_url');
    final uid = value('uid');
    final hash = value('hash');
    final extensions = value('file_types');
    final max = num.tryParse(value('file_size_limit') ?? '');
    if (rawUri == null ||
        uid != actor ||
        hash == null ||
        !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(hash) ||
        extensions == null ||
        max == null ||
        !max.isFinite ||
        max < 0) {
      return null;
    }
    final uri = siteOrigin.resolve(rawUri);
    if (uri.scheme != siteOrigin.scheme ||
        uri.host != siteOrigin.host ||
        uri.port != siteOrigin.port ||
        uri.userInfo.isNotEmpty ||
        uri.path != '/misc.php' ||
        uri.fragment.isNotEmpty ||
        uri.queryParameters.length != 3 ||
        uri.queryParametersAll.values.any((v) => v.length != 1) ||
        uri.queryParameters['mod'] != 'swfupload' ||
        uri.queryParameters['action'] != 'swfupload' ||
        uri.queryParameters['operation'] != 'album') {
      return null;
    }
    final allowed = <String>{};
    for (final pattern in extensions.split(';')) {
      final match = RegExp(r'^\*\.([a-zA-Z0-9]+)$').firstMatch(pattern.trim());
      if (match == null) return null;
      final extension = match.group(1)!.toLowerCase();
      if ({'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'}.contains(extension)) {
        allowed.add(extension);
      }
    }
    if (allowed.isEmpty) return null;
    final maximumBytes = max == 0 ? null : (max * 1024).floor();
    return DiscuzBlogEditorMedia(
      uploadUri: uri,
      uid: uid!,
      hash: hash,
      limits: UserBlogImageUploadLimits(
        maximumBytes: maximumBytes,
        extensionRules: List.unmodifiable([
          for (final extension in allowed)
            ForumImageAttachmentExtensionRule(
              extension: extension,
              maximumBytes: maximumBytes,
            ),
        ]),
      ),
    );
  }

  /// The standard home editor has exactly thirty comcom image smileys.
  static List<UserBlogSmiley> smileys(String source, Uri siteOrigin) {
    try {
      return _smileys(source, siteOrigin);
    } on FormatException {
      return const [];
    }
  }

  static List<UserBlogSmiley> _smileys(String source, Uri siteOrigin) {
    final document = html.parse(source);
    final editor = document.querySelector(
      'iframe[name="uchome-ifrHtmlEditor"]',
    );
    final editorUri = Uri.tryParse(editor?.attributes['src'] ?? '');
    if (editorUri == null || editorUri.queryParameters['mod'] != 'editor') {
      return const [];
    }
    final resolved = siteOrigin.resolveUri(editorUri);
    if (resolved.host != siteOrigin.host ||
        resolved.scheme != siteOrigin.scheme ||
        resolved.port != siteOrigin.port ||
        resolved.path != '/home.php') {
      return const [];
    }
    final roots = document
        .querySelectorAll('script')
        .expand(
          (script) => RegExp(
            r'''\bSTATICURL\s*=\s*['"]([^'"]+)['"]''',
          ).allMatches(script.text),
        )
        .map((match) => siteOrigin.resolve(match.group(1)!))
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
    return List.unmodifiable([
      for (var i = 1; i <= 30; i++)
        UserBlogSmiley(
          index: i,
          imageUri: root.resolve('image/smiley/comcom/$i.gif'),
        ),
    ]);
  }
}
