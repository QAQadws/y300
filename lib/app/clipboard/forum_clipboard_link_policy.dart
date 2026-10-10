import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/forum/domain/services/yamibo_forum_link_resolver.dart';

enum ForumClipboardLinkKind { thread, threadPost, forum }

final class ForumClipboardLinkCandidate {
  const ForumClipboardLinkCandidate({
    required this.url,
    required this.kind,
    required this.fingerprint,
  });

  final String url;
  final ForumClipboardLinkKind kind;
  final String fingerprint;
}

/// Local recommendation only. External URLs and actions are ignored; multiple
/// inequivalent forum browsing targets or limited scans fail closed.
final class ForumClipboardLinkPolicy {
  const ForumClipboardLinkPolicy({
    ForumHttpTextLinkDetector detector = const ForumHttpTextLinkDetector(),
    YamiboForumLinkResolver resolver = const YamiboForumLinkResolver(),
  }) : _detector = detector,
       _resolver = resolver;

  final ForumHttpTextLinkDetector _detector;
  final YamiboForumLinkResolver _resolver;

  ForumClipboardLinkCandidate? resolve(String text) {
    final scan = _detector.detect(text);
    if (scan.isLimited) return null;
    final candidates = <String, ForumClipboardLinkCandidate>{};
    for (final link in scan.links) {
      final destination = _resolver.resolveBrowsable(link.text);
      if (destination == null) continue;
      final identity = _resolver.resolveBrowsingIdentity(link.text);
      if (identity == null) continue;
      final kind = switch (identity.kind) {
        YamiboForumLinkKind.thread => ForumClipboardLinkKind.thread,
        YamiboForumLinkKind.threadPost => ForumClipboardLinkKind.threadPost,
        YamiboForumLinkKind.forumDisplay => ForumClipboardLinkKind.forum,
        _ => null,
      };
      if (kind == null) continue;
      // Unsupported browser parameters have no proven equivalence rules. Keep
      // their exact URL text in the identity instead of merging by base TID.
      final key = destination.kind == YamiboForumLinkKind.managedWebView
          ? ['managed', link.text]
          : switch (kind) {
              ForumClipboardLinkKind.thread => [
                kind.name,
                identity.tid,
                identity.page ?? 1,
              ],
              ForumClipboardLinkKind.threadPost => [
                kind.name,
                identity.tid,
                identity.page ?? 1,
                identity.pid,
              ],
              ForumClipboardLinkKind.forum => [
                kind.name,
                identity.forumId,
                identity.page ?? 1,
              ],
            };
      final fingerprint = sha256
          .convert(utf8.encode(jsonEncode(key)))
          .toString();
      candidates.putIfAbsent(
        fingerprint,
        () => ForumClipboardLinkCandidate(
          url: link.text,
          kind: kind,
          fingerprint: fingerprint,
        ),
      );
    }
    return candidates.length == 1 ? candidates.values.single : null;
  }
}
