import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/data/image_cache_providers.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';

import 'continuous_image_decode_preheater.dart';
import 'continuous_image_reader_view.dart';

typedef ContinuousImageCacheRequestBuilder =
    ImageCacheRequest Function(ContinuousImageItem item);

class ContinuousImageReaderRoute extends ConsumerStatefulWidget {
  const ContinuousImageReaderRoute({
    super.key,
    required this.title,
    required this.items,
    required this.initialIndex,
    required this.requestBuilder,
    this.imageHeaderBuilder,
    this.mode = ContinuousImageReaderMode.vertical,
    this.layoutResolver = const ContinuousImageLayoutResolver(),
    this.fit = BoxFit.fitWidth,
    this.emptyText = '没有可阅读图片',
    this.listKey = const Key('continuous-image-reader-list'),
    this.pageKey = const Key('continuous-image-reader-page-view'),
    this.decodePreheatRadius = 1,
  });

  final String title;
  final List<ContinuousImageItem> items;
  final int initialIndex;
  final ContinuousImageCacheRequestBuilder requestBuilder;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ContinuousImageReaderMode mode;
  final ContinuousImageLayoutResolver layoutResolver;
  final BoxFit fit;
  final String emptyText;
  final Key listKey;
  final Key pageKey;
  final int decodePreheatRadius;

  @override
  ConsumerState<ContinuousImageReaderRoute> createState() =>
      _ContinuousImageReaderRouteState();
}

class _ContinuousImageReaderRouteState
    extends ConsumerState<ContinuousImageReaderRoute> {
  final ScrollController _scrollController = ScrollController();
  final InMemoryContinuousImageExtentRegistry _extentRegistry =
      InMemoryContinuousImageExtentRegistry();
  final ContinuousImageDecodePreheater _decodePreheater =
      const ContinuousImageDecodePreheater();
  final Set<String> _decodePreheatKeys = <String>{};
  late PageController _pageController;
  String? _jumpedRequestKey;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _initialIndex);
    _scheduleInitialJump();
    _scheduleDecodePreheat(_initialIndex);
  }

  @override
  void didUpdateWidget(covariant ContinuousImageReaderRoute oldWidget) {
    super.didUpdateWidget(oldWidget);
    final contentChanged =
        !identical(oldWidget.items, widget.items) ||
        oldWidget.initialIndex != widget.initialIndex;
    if (contentChanged) {
      _extentRegistry.clearForOwner(_ownerId);
      _decodePreheatKeys.clear();
      _jumpedRequestKey = null;
      _pageController.dispose();
      _pageController = PageController(initialPage: _initialIndex);
      _scheduleInitialJump();
    }
    if (contentChanged || oldWidget.mode != widget.mode) {
      _scheduleDecodePreheat(_initialIndex);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  int get _initialIndex {
    if (widget.items.isEmpty) {
      return 0;
    }
    return widget.initialIndex.clamp(0, widget.items.length - 1).toInt();
  }

  String get _ownerId {
    final items = widget.items;
    return items.isEmpty ? 'continuous-image-reader' : items.first.ownerId;
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(title: Text(widget.title), centerTitle: false),
      body: items.isEmpty
          ? Center(child: Text(widget.emptyText))
          : ContinuousImageReaderView(
              items: items,
              mode: widget.mode,
              scrollController: _scrollController,
              pageController: _pageController,
              layoutResolver: widget.layoutResolver,
              cacheExtent:
                  MediaQuery.sizeOf(context).height *
                  ContinuousImageFlowPolicy
                      .comicVerticalReading
                      .viewportCacheExtentFactor,
              onExtentResolved: _recordExtent,
              onPageChanged: _handlePageChanged,
              verticalListKey: widget.listKey,
              horizontalPageKey: widget.pageKey,
              slotKeyPrefix: 'continuous-image-reader-slot',
              itemBuilder: _buildImage,
            ),
    );
  }

  Widget _buildImage(
    BuildContext context,
    ContinuousImageItem item,
    int index, {
    required bool paged,
  }) {
    return CachedLibraryImage(
      request: widget.requestBuilder(item),
      fit: widget.fit,
      width: paged ? null : double.infinity,
      placeholder: const _ContinuousImageReaderPlaceholder(
        label: '图片加载中',
        icon: Icons.image_outlined,
      ),
      errorPlaceholder: const _ContinuousImageReaderPlaceholder(
        label: '图片加载失败',
        icon: Icons.broken_image_outlined,
      ),
      headerBuilder: widget.imageHeaderBuilder,
    );
  }

  void _recordExtent(ContinuousImageExtent extent) {
    _extentRegistry.record(extent);
  }

  void _handlePageChanged(int index) {
    _scheduleDecodePreheat(index);
  }

  void _scheduleDecodePreheat(int centerIndex) {
    if (widget.decodePreheatRadius < 0) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.mode != ContinuousImageReaderMode.horizontal) {
        return;
      }
      _decodePreheater.precacheWindow(
        context: context,
        items: widget.items,
        centerIndex: centerIndex,
        warmedKeys: _decodePreheatKeys,
        imageHeaderBuilder: widget.imageHeaderBuilder,
        localPathResolver: _cachedLocalPathFor,
        radius: widget.decodePreheatRadius,
        isMounted: () => mounted,
      );
    });
  }

  Future<String?> _cachedLocalPathFor(ContinuousImageItem item) async {
    final request = widget.requestBuilder(item);
    try {
      final result = await ref
          .read(imageCacheServiceProvider)
          .getCached(request.cacheKey);
      return result != null && result.success ? result.localPath : null;
    } catch (_) {
      return null;
    }
  }

  void _scheduleInitialJump() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToInitialIndex());
  }

  void _jumpToInitialIndex() {
    if (!mounted ||
        widget.mode != ContinuousImageReaderMode.vertical ||
        !_scrollController.hasClients ||
        widget.items.isEmpty ||
        _initialIndex <= 0) {
      return;
    }
    final key = '$_ownerId:${widget.initialIndex}:${widget.items.length}';
    if (_jumpedRequestKey == key) {
      return;
    }
    _jumpedRequestKey = key;
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) {
      return;
    }
    final offset = _extentRegistry
        .estimateOffsetForIndex(
          _initialIndex,
          widget.items,
          crossAxisExtent: MediaQuery.sizeOf(context).width,
          resolver: widget.layoutResolver,
        )
        .clamp(0.0, maxScroll)
        .toDouble();
    _scrollController.jumpTo(offset);
  }
}

class _ContinuousImageReaderPlaceholder extends StatelessWidget {
  const _ContinuousImageReaderPlaceholder({
    required this.label,
    required this.icon,
  });

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: scheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
