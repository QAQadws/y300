import 'dart:async';

import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_widget_post_renderer.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

class NovelReaderPaginationMeasureRequest {
  const NovelReaderPaginationMeasureRequest({
    required this.html,
    required this.chapter,
    required this.key,
  });

  final String html;
  final NovelReaderPreparedChapter chapter;
  final NovelReaderPaginationKey key;
}

class NovelReaderPaginationMeasureResult {
  const NovelReaderPaginationMeasureResult({required this.height});

  final double height;
}

abstract interface class NovelReaderPaginationMeasureAdapter {
  Future<NovelReaderPaginationMeasureResult> measure(
    NovelReaderPaginationMeasureRequest request,
  );
}

/// Measures the same HTML renderer used by the vertical reader in a temporary
/// offstage overlay entry. It never becomes part of reader page state.
final class NovelReaderHtmlPaginationMeasureAdapter
    implements NovelReaderPaginationMeasureAdapter {
  NovelReaderHtmlPaginationMeasureAdapter({
    required BuildContext hostContext,
    required this.theme,
    required this.preferences,
    required this.sourceId,
    this.threadId,
    this.imageCacheOwnerId,
    this.imageHeaderBuilder,
    this.timeout = const Duration(milliseconds: 800),
  }) : _hostContext = hostContext;

  final BuildContext _hostContext;
  final ForumHtmlThemeContext theme;
  final ForumHtmlReaderPreferences preferences;
  final String sourceId;
  final String? threadId;
  final String? imageCacheOwnerId;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final Duration timeout;

  @override
  Future<NovelReaderPaginationMeasureResult> measure(
    NovelReaderPaginationMeasureRequest request,
  ) async {
    final overlay = Overlay.maybeOf(_hostContext, rootOverlay: true);
    if (overlay == null) {
      throw const NovelReaderPaginationException(
        code: 'measurementHostUnavailable',
        message: 'No overlay is available for HTML pagination measurement.',
      );
    }
    // The coordinator can be started while a FutureBuilder is building.
    // Wait until that frame is complete before mutating the overlay.
    await WidgetsBinding.instance.endOfFrame;

    final completer = Completer<NovelReaderPaginationMeasureResult>();
    var removed = false;
    late final OverlayEntry entry;
    void removeEntry() {
      if (removed) {
        return;
      }
      removed = true;
      entry.remove();
    }

    final preparedDocument = request.chapter.renderDocument.copyWith(
      preparedHtml: request.html,
    );
    entry = OverlayEntry(
      builder: (context) {
        return Positioned(
          left: 0,
          top: 0,
          width: request.key.viewportWidthPx.toDouble(),
          child: IgnorePointer(
            child: Opacity(
              opacity: 0,
              child: _NovelReaderPaginationMeasureProbe(
                onMeasured: (height) {
                  if (!completer.isCompleted) {
                    completer.complete(
                      NovelReaderPaginationMeasureResult(height: height),
                    );
                  }
                },
                child: ForumHtmlWidgetPostRenderer(
                  html: request.html,
                  theme: theme,
                  preparedDocument: preparedDocument,
                  preferences: preferences,
                  sourceId: sourceId,
                  threadId: threadId,
                  imageHeaderBuilder: imageHeaderBuilder,
                  imageCacheOwnerId: imageCacheOwnerId,
                ),
              ),
            ),
          ),
        );
      },
    );

    try {
      overlay.insert(entry);
      return await completer.future.timeout(
        timeout,
        onTimeout: () => throw const NovelReaderPaginationException(
          code: 'measurementTimeout',
          message: 'HTML pagination candidate measurement timed out.',
        ),
      );
    } finally {
      removeEntry();
    }
  }
}

class _NovelReaderPaginationMeasureProbe extends StatefulWidget {
  const _NovelReaderPaginationMeasureProbe({
    required this.onMeasured,
    required this.child,
  });

  final ValueChanged<double> onMeasured;
  final Widget child;

  @override
  State<_NovelReaderPaginationMeasureProbe> createState() =>
      _NovelReaderPaginationMeasureProbeState();
}

class _NovelReaderPaginationMeasureProbeState
    extends State<_NovelReaderPaginationMeasureProbe> {
  bool _reported = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportSize());
  }

  @override
  Widget build(BuildContext context) => widget.child;

  void _reportSize() {
    if (!mounted || _reported) {
      return;
    }
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reportSize());
      return;
    }
    _reported = true;
    widget.onMeasured(renderObject.size.height);
  }
}

class NovelReaderPaginationException implements Exception {
  const NovelReaderPaginationException({
    required this.code,
    required this.message,
  });

  final String code;
  final String message;

  @override
  String toString() => 'NovelReaderPaginationException($code): $message';
}
