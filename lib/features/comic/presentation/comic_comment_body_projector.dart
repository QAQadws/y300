import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/comic/presentation/comic_comment_content_projection.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

/// Removes reader images from a display copy, never from the source post.
class ComicCommentBodyProjector {
  ComicCommentBodyProjector(Iterable<String> chapterImageUrls)
    : imageKeys = Set.unmodifiable(chapterImageUrls.map(_imageKey).nonNulls);

  final Set<String> imageKeys;

  ComicCommentContentProjection project(ComicCommentContentProjection source) {
    if (imageKeys.isEmpty) return source;
    final candidates = _sourcePostIds(source);
    if (candidates.isEmpty) return source;
    return ComicCommentContentProjection(
      sourceResult: source.sourceResult,
      items: [
        for (final item in source.items)
          if (candidates.contains(item.sourceItem.pid))
            item.projectBody(_filterPost)
          else
            item,
      ],
      mode: source.mode,
      converterId: source.converterId,
      sourceRevision: source.sourceRevision,
      isConverted: source.isConverted,
      bodyRevision: Object.hashAll(imageKeys.toList()..sort()).toString(),
    );
  }

  Set<String> _sourcePostIds(ComicCommentContentProjection source) {
    final firstPosts = <String, ThreadPost>{};
    for (final item in source.items) {
      final post = item.sourceItem.post;
      if (post.isFirst || post.number == 1) firstPosts[post.pid] = post;
    }
    if (firstPosts.length != 1) return const {};
    final first = firstPosts.values.single;
    final authorId = first.authorId.trim();
    if (first.pid.trim().isEmpty ||
        first.number != 1 ||
        authorId.isEmpty ||
        authorId == '0') {
      return const {};
    }
    final candidates = <String>{};
    var expectedFloor = 1;
    for (final item in source.items) {
      final post = item.sourceItem.post;
      if (candidates.contains(post.pid)) continue;
      // Missing/ambiguous floors cannot prove that the OP run continues.
      if (post.pid.trim().isEmpty ||
          post.number != expectedFloor ||
          post.authorId.trim() != authorId) {
        break;
      }
      candidates.add(post.pid);
      expectedFloor++;
    }
    return candidates;
  }

  ThreadPost _filterPost(ThreadPost post) {
    final fragment = html.parseFragment(post.message);
    final images = fragment.querySelectorAll('img');
    final matchedIds = <String>{};
    final matchedImages = <dom.Element>{};
    final removedRegions = <dom.Node>{};
    for (final attachment in post.attachmentImages) {
      if (_matchesAttachment(attachment)) {
        final aid = attachment.aid.trim();
        if (aid.isNotEmpty) matchedIds.add(aid);
      }
    }
    for (final image in images) {
      if (_imageAttributes.any(
        (attribute) =>
            imageKeys.contains(_imageKey(image.attributes[attribute])),
      )) {
        matchedImages.add(image);
        final aid = _attachmentId(image);
        if (aid != null) matchedIds.add(aid);
      }
    }
    // A thumbnail and its full image may have different URLs but the same
    // explicit attachment ID. Only IDs proved by a matched URL are excluded.
    for (final image in images) {
      if (matchedImages.contains(image) ||
          matchedIds.contains(_attachmentId(image))) {
        _removeImage(image, removedRegions);
        matchedImages.add(image);
      }
    }
    _cleanRemovedRegions(fragment, removedRegions);
    final attachments = post.attachmentImages
        .where((attachment) {
          if (!DefaultForumImageSourcePipeline.isImageAttachment(attachment)) {
            return true;
          }
          return !_matchesAttachment(attachment) &&
              !matchedIds.contains(attachment.aid.trim());
        })
        .toList(growable: false);
    if (matchedImages.isEmpty &&
        attachments.length == post.attachmentImages.length) {
      return post;
    }
    return ThreadPost(
      pid: post.pid,
      author: post.author,
      authorId: post.authorId,
      message: matchedImages.isEmpty ? post.message : fragment.outerHtml,
      number: post.number,
      isFirst: post.isFirst,
      dateline: post.dateline,
      avatarUrl: post.avatarUrl,
      replyUrl: post.replyUrl,
      editUrl: post.editUrl,
      rateUrl: post.rateUrl,
      commentUrl: post.commentUrl,
      rateSummary: post.rateSummary,
      ratingSummary: post.ratingSummary,
      poll: post.poll,
      tagLinks: post.tagLinks,
      comments: post.comments,
      attachmentImages: attachments,
    );
  }

  bool _matchesAttachment(ForumPostAttachmentImage attachment) =>
      DefaultForumImageSourcePipeline.isImageAttachment(attachment) &&
      imageKeys.contains(
        _imageKey(
          DefaultForumImageSourcePipeline.joinAttachmentUrl(
            attachment.url,
            attachment.attachment,
          ),
        ),
      );

  static const _imageAttributes = [
    'zoomfile',
    'file',
    'data-original',
    'data-src',
    'src',
  ];

  static String? _imageKey(String? raw) {
    if (raw == null) return null;
    final normalized = DefaultForumImageSourcePipeline.normalizeImageSource(
      raw,
      urlResolver: const SiteUrlResolver().resolve,
    );
    if (normalized == null ||
        !DefaultForumImageSourcePipeline.isHttpImageUrl(normalized) ||
        DefaultForumImageSourcePipeline.isForumChromeImage(normalized)) {
      return null;
    }
    return Uri.tryParse(normalized)?.removeFragment().toString();
  }

  String? _attachmentId(dom.Element image) {
    final aid = image.attributes['aid']?.trim();
    if (aid != null && RegExp(r'^\d+$').hasMatch(aid)) return aid;
    return RegExp(r'^aimg_(\d+)$').firstMatch(image.id)?.group(1);
  }

  void _removeImage(dom.Element image, Set<dom.Node> removedRegions) {
    var parent = image.parentNode;
    final marker = dom.Comment('');
    image.replaceWith(marker);
    removedRegions.add(marker);
    while (parent is dom.Element &&
        const {
          'a',
          'span',
          'p',
          'div',
          'font',
          'strong',
          'b',
          'i',
          'em',
          'center',
        }.contains(parent.localName) &&
        parent.nodes.every((node) => _imageSpacing(node, removedRegions))) {
      final next = parent.parentNode;
      parent.replaceWith(marker);
      parent = next;
    }
  }

  bool _imageSpacing(dom.Node node, Set<dom.Node> removedRegions) =>
      removedRegions.contains(node) ||
      node is dom.Comment ||
      (node is dom.Text && node.text.trim().isEmpty) ||
      (node is dom.Element && node.localName == 'br');

  void _cleanRemovedRegions(dom.Node parent, Set<dom.Node> removedRegions) {
    for (final child in parent.nodes.toList()) {
      if (child is dom.Element) _cleanRemovedRegions(child, removedRegions);
    }
    final nodes = parent.nodes.toList();
    var index = 0;
    while (index < nodes.length) {
      if (!_imageSpacing(nodes[index], removedRegions)) {
        index++;
        continue;
      }
      final start = index;
      while (index < nodes.length &&
          _imageSpacing(nodes[index], removedRegions)) {
        index++;
      }
      final region = nodes.sublist(start, index);
      if (!region.any(removedRegions.contains)) continue;
      // Only whitespace connected to a removed image is changed. A middle
      // image run keeps a paragraph break; an empty image tail has no height.
      if (start > 0 && index < nodes.length) {
        final hasBreak = region.any(
          (node) => node is dom.Element && node.localName == 'br',
        );
        if (hasBreak) {
          parent.insertBefore(dom.Element.tag('br'), region.first);
          parent.insertBefore(dom.Element.tag('br'), region.first);
        }
      }
      for (final node in region) {
        node.remove();
      }
    }
  }
}
