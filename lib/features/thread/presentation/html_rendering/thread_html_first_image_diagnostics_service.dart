import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_render_plan.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_prepared_render_document.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_widget_post_renderer.dart';
import 'package:y300/features/thread/presentation/html_rendering/thread_html_image_reader_bridge.dart';

class ThreadHtmlFirstImageDiagnosticsReport {
  const ThreadHtmlFirstImageDiagnosticsReport({
    required this.pid,
    required this.htmlLength,
    required this.totalImageCount,
    required this.readableImageCount,
    required this.skippedStickerCount,
    required this.skippedNonNetworkCount,
    required this.legacyPlanImageCount,
    required this.duplicatedReadableUrlCount,
    required this.attachmentTaggedCount,
    required this.sequenceDiff,
    this.lastFailureReason,
    this.lastTapStatus,
  });

  final String pid;
  final int htmlLength;
  final int totalImageCount;
  final int readableImageCount;
  final int skippedStickerCount;
  final int skippedNonNetworkCount;
  final int legacyPlanImageCount;
  final int duplicatedReadableUrlCount;
  final int attachmentTaggedCount;
  final ThreadHtmlFirstImageSequenceDiff sequenceDiff;
  final ThreadHtmlImageReaderBridgeFailureReason? lastFailureReason;
  final String? lastTapStatus;

  String get summaryText {
    return 'HTML 图片 $totalImageCount，可读 $readableImageCount，'
        '表情 $skippedStickerCount，非网络/无效 $skippedNonNetworkCount';
  }

  String get sequenceDiffText {
    return '旧 plan $legacyPlanImageCount，缺失 ${sequenceDiff.missingFromHtmlFirst.length}，'
        '额外 ${sequenceDiff.extraInHtmlFirst.length}，重复 URL $duplicatedReadableUrlCount，'
        'attachmentId $attachmentTaggedCount';
  }

  String get failureBreakdownText {
    final reason = lastFailureReason;
    if (reason == null) {
      return lastTapStatus ?? '尚未点击 HTML-first 图片';
    }
    return '${_failureReasonLabel(reason)}：${lastTapStatus ?? '无可打开图片'}';
  }

  String _failureReasonLabel(ThreadHtmlImageReaderBridgeFailureReason reason) {
    return switch (reason) {
      ThreadHtmlImageReaderBridgeFailureReason.sticker => '表情已忽略',
      ThreadHtmlImageReaderBridgeFailureReason.emptySequence => '无可读序列',
      ThreadHtmlImageReaderBridgeFailureReason.unmatchedImage => '未匹配图片',
      ThreadHtmlImageReaderBridgeFailureReason.invalidInitialIndex => '图片序号无效',
    };
  }
}

class ThreadHtmlFirstImageSequenceDiff {
  const ThreadHtmlFirstImageSequenceDiff({
    required this.missingFromHtmlFirst,
    required this.extraInHtmlFirst,
    required this.matchedAttachmentIds,
    required this.matchedUrls,
  });

  final List<String> missingFromHtmlFirst;
  final List<String> extraInHtmlFirst;
  final List<String> matchedAttachmentIds;
  final List<String> matchedUrls;

  bool get hasDifference =>
      missingFromHtmlFirst.isNotEmpty || extraInHtmlFirst.isNotEmpty;
}

class ThreadHtmlFirstImageDiagnosticsService {
  const ThreadHtmlFirstImageDiagnosticsService();

  ThreadHtmlFirstImageDiagnosticsReport buildReport({
    required ThreadPost post,
    required ThreadPostBodyRenderPlan legacyPlan,
    required ForumHtmlPreparedRenderDocument preparedDocument,
    ForumHtmlImageRequest? lastImageRequest,
    ThreadHtmlImageReaderBridgeResult? lastBridgeResult,
    String? lastTapStatus,
  }) {
    return ThreadHtmlFirstImageDiagnosticsReport(
      pid: post.pid,
      htmlLength: post.message.length,
      totalImageCount: preparedDocument.totalImageCount,
      readableImageCount: preparedDocument.readableImageCount,
      skippedStickerCount: preparedDocument.skippedStickerCount,
      skippedNonNetworkCount: preparedDocument.skippedNonNetworkCount,
      legacyPlanImageCount: legacyPlan.images.length,
      duplicatedReadableUrlCount: preparedDocument.duplicatedReadableUrlCount,
      attachmentTaggedCount: preparedDocument.attachmentTaggedCount,
      sequenceDiff: _diff(
        legacyPlan: legacyPlan,
        preparedDocument: preparedDocument,
      ),
      lastFailureReason: lastBridgeResult?.failureReason,
      lastTapStatus:
          lastTapStatus ??
          _tapStatus(request: lastImageRequest, result: lastBridgeResult),
    );
  }

  ThreadHtmlFirstImageSequenceDiff _diff({
    required ThreadPostBodyRenderPlan legacyPlan,
    required ForumHtmlPreparedRenderDocument preparedDocument,
  }) {
    final htmlUrls = preparedDocument.sequence.entries
        .map((entry) => _normalize(entry.url))
        .where((url) => url.isNotEmpty)
        .toSet();
    final legacyUrls = legacyPlan.images
        .map((image) => _normalize(image.url))
        .where((url) => url.isNotEmpty)
        .toSet();

    final htmlAttachmentIds = preparedDocument.sequence.entries
        .map((entry) => entry.attachmentId?.trim())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    final legacyAttachmentIds = legacyPlan.images
        .map((image) => image.aid?.trim())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();

    return ThreadHtmlFirstImageSequenceDiff(
      missingFromHtmlFirst: legacyUrls
          .where((url) => !htmlUrls.contains(url))
          .toList(growable: false),
      extraInHtmlFirst: htmlUrls
          .where((url) => !legacyUrls.contains(url))
          .toList(growable: false),
      matchedAttachmentIds: htmlAttachmentIds
          .where(legacyAttachmentIds.contains)
          .toList(growable: false),
      matchedUrls: htmlUrls.where(legacyUrls.contains).toList(growable: false),
    );
  }

  String? _tapStatus({
    required ForumHtmlImageRequest? request,
    required ThreadHtmlImageReaderBridgeResult? result,
  }) {
    if (request == null || result == null) {
      return null;
    }
    final openRequest = result.request;
    if (openRequest != null) {
      final index = request.readableIndex;
      final via = index == null ? 'aid/url fallback' : 'readableIndex=$index';
      return '打开 index=${openRequest.initialIndex}（$via）';
    }
    if (request.isSticker) {
      return '表情不进入阅读器';
    }
    return '降级复制 URL：${request.url}';
  }

  String _normalize(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final resolved = ForumHtmlWidgetPostRenderer.forumBaseUri.resolve(trimmed);
    return resolved.removeFragment().toString();
  }
}
