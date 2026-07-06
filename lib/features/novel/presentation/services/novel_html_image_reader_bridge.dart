import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_prepared_render_document.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';
import 'package:y300/features/thread/presentation/services/thread_image_reader_continuous_image_adapter.dart';

class NovelHtmlImageReaderBridge {
  const NovelHtmlImageReaderBridge({
    ThreadImageReaderContinuousImageAdapter readerAdapter =
        const ThreadImageReaderContinuousImageAdapter(),
  }) : _readerAdapter = readerAdapter;

  final ThreadImageReaderContinuousImageAdapter _readerAdapter;

  ThreadImageOpenRequest? buildOpenRequest({
    required String threadId,
    required String episodeId,
    required int postNumber,
    required String imageReferer,
    required ForumHtmlReadableImageSequence sequence,
    required ForumHtmlImageRequest imageRequest,
  }) {
    if (imageRequest.isSticker || sequence.entries.isEmpty) {
      return null;
    }
    final readableIndex = imageRequest.readableIndex;
    final entry = readableIndex == null
        ? _entryByUrl(sequence, imageRequest.url)
        : sequence.entryAt(readableIndex);
    if (entry == null) {
      return null;
    }
    if (entry.index < 0 || entry.index >= sequence.entries.length) {
      return null;
    }
    final group = ThreadPostImageGroup(
      tid: threadId,
      pid: episodeId,
      postNumber: postNumber,
      entries: sequence.entries.map(_readerEntryFor).toList(growable: false),
    );
    final readerRequest = ThreadImageOpenRequest(
      tid: threadId,
      pid: episodeId,
      postNumber: postNumber,
      referer: imageReferer,
      group: group,
      initialIndex: entry.index,
    );
    return ThreadImageOpenRequest(
      tid: readerRequest.tid,
      pid: readerRequest.pid,
      postNumber: readerRequest.postNumber,
      referer: readerRequest.referer,
      group: readerRequest.group,
      initialIndex: readerRequest.initialIndex,
      continuousImages: _readerAdapter.mapRequest(readerRequest),
    );
  }

  ForumHtmlReadableImageEntry? _entryByUrl(
    ForumHtmlReadableImageSequence sequence,
    String url,
  ) {
    final normalized = _normalize(url);
    for (final entry in sequence.entries) {
      if (_normalize(entry.url) == normalized ||
          _normalize(entry.rawSrc) == normalized) {
        return entry;
      }
    }
    return null;
  }

  ThreadPostImageEntry _readerEntryFor(ForumHtmlReadableImageEntry entry) {
    return ThreadPostImageEntry(
      url: entry.url,
      rawUrl: entry.rawSrc,
      indexInPost: entry.index,
      cacheKey: entry.cacheKey,
      aid: entry.attachmentId,
    );
  }

  String _normalize(String value) {
    return Uri.parse(
      'https://bbs.yamibo.com/',
    ).resolve(value.trim()).removeFragment().toString();
  }
}
