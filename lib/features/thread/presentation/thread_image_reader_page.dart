import 'package:flutter/material.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/presentation/engine/engine.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/domain/models/thread_image_reader_exit_result.dart';
import 'package:y300/features/thread/presentation/services/thread_image_reader_capability.dart';
import 'package:y300/l10n/app_localizations.dart';

/// 帖子图片阅读器页面。
///
/// 基于共享 [ImageReaderEngine]，通过 [ThreadImageReaderCapability] 注入帖子图片
/// 专属能力（内容来源、缓存请求、图片渲染），获得与漫画同源的阅读体验（模式切换 /
/// 缩放 / 滑块 / 页码 / 显示设置），但不含书签 / 下载 / 章节 / 上一话下一话等 detail
/// 强相关项。
class ThreadImageReaderPage extends StatefulWidget {
  const ThreadImageReaderPage({
    super.key,
    required this.request,
    this.imageReferer,
    this.diagnosticRecorder = const NoopContinuousImageDiagnosticRecorder(),
    this.onBeforeExit,
  });

  final ThreadImageOpenRequest request;
  final String? imageReferer;
  final ContinuousImageDiagnosticRecorder diagnosticRecorder;
  final Future<void> Function(ThreadImageReaderExitResult result)? onBeforeExit;

  @override
  State<ThreadImageReaderPage> createState() => _ThreadImageReaderPageState();
}

class _ThreadImageReaderPageState extends State<ThreadImageReaderPage> {
  ThreadImageReaderCapability? _capability;
  bool _systemExitInFlight = false;

  @override
  void didUpdateWidget(ThreadImageReaderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.request, widget.request) ||
        oldWidget.imageReferer != widget.imageReferer ||
        !identical(oldWidget.diagnosticRecorder, widget.diagnosticRecorder)) {
      _capability?.retire();
      _capability = null;
      _systemExitInFlight = false;
    }
  }

  @override
  void dispose() {
    _capability?.retire();
    super.dispose();
  }

  Future<void> _exitFromSystem() async {
    final capability = _capability;
    if (_systemExitInFlight || capability == null) return;
    _systemExitInFlight = true;
    final result = capability.exitResult;
    await capability.onExit();
    if (!mounted || !identical(_capability, capability)) return;
    if (ModalRoute.of(context)?.isCurrent ?? false) {
      Navigator.of(context).pop(result);
    } else {
      _systemExitInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final capability = _capability ??= ThreadImageReaderCapability(
      request: widget.request,
      imageReferer: widget.imageReferer,
      diagnosticRecorder: widget.diagnosticRecorder,
      title: l10n.threadImageReaderTitle,
      displayLabel: l10n.threadImageDisplay,
      downloadLabel: l10n.threadImageDownload,
      onBeforeExit: widget.onBeforeExit,
    );
    capability.updatePresentation(
      title: l10n.threadImageReaderTitle,
      displayLabel: l10n.threadImageDisplay,
      downloadLabel: l10n.threadImageDownload,
      onBeforeExit: widget.onBeforeExit,
    );
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _exitFromSystem();
      },
      child: Listener(
        onPointerDown: (_) => capability.noteInteraction(),
        onPointerSignal: (_) => capability.noteScrollInteraction(),
        child: NotificationListener<ScrollStartNotification>(
          onNotification: (notification) {
            if (notification.dragDetails != null) {
              capability.noteScrollInteraction();
            }
            return false;
          },
          child: KeyedSubtree(
            // Rebinding starts a fresh reader session; localization/chrome rebuilds
            // retain both the engine and its transient return position.
            key: ObjectKey(capability),
            child: ImageReaderEngine(
              key: const Key('thread-image-reader-engine'),
              listKey: const Key('thread-image-reader-list'),
              pageKey: const Key('thread-image-reader-page-view'),
              slotKeyPrefix: 'thread-image-reader-image-slot',
              capability: capability,
            ),
          ),
        ),
      ),
    );
  }
}
