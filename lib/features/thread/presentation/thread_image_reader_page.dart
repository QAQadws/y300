import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/presentation/continuous_image/continuous_image_presentation.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';

class ThreadImageReaderPage extends StatefulWidget {
  const ThreadImageReaderPage({
    super.key,
    required this.request,
    this.imageHeaderBuilder,
    ContinuousImageLayoutResolver layoutResolver =
        const ContinuousImageLayoutResolver(),
  }) : _layoutResolver = layoutResolver;

  final ThreadImageOpenRequest request;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ContinuousImageLayoutResolver _layoutResolver;

  @override
  State<ThreadImageReaderPage> createState() => _ThreadImageReaderPageState();
}

class _ThreadImageReaderPageState extends State<ThreadImageReaderPage> {
  final ScrollController _scrollController = ScrollController();
  final InMemoryContinuousImageExtentRegistry _extentRegistry =
      InMemoryContinuousImageExtentRegistry();
  String? _jumpedRequestKey;

  List<ContinuousImageItem> get _items => widget.request.continuousImages;

  @override
  void initState() {
    super.initState();
    _scheduleInitialJump();
  }

  @override
  void didUpdateWidget(covariant ThreadImageReaderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.request, widget.request)) {
      _extentRegistry.clearForOwner(_ownerId);
      _jumpedRequestKey = null;
      _scheduleInitialJump();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(title: const Text('图片阅读'), centerTitle: false),
      body: items.isEmpty
          ? const Center(child: Text('没有可阅读图片'))
          : ListView.builder(
              key: const Key('thread-image-reader-list'),
              controller: _scrollController,
              cacheExtent:
                  MediaQuery.sizeOf(context).height *
                  ContinuousImageFlowPolicy
                      .comicVerticalReading
                      .viewportCacheExtentFactor,
              padding: EdgeInsets.zero,
              itemCount: items.length,
              itemBuilder: (context, index) {
                return _ThreadImageReaderItem(
                  item: items[index],
                  layoutResolver: widget._layoutResolver,
                  imageHeaderBuilder: widget.imageHeaderBuilder,
                  onExtentResolved: _recordExtent,
                );
              },
            ),
    );
  }

  String get _ownerId {
    final items = _items;
    return items.isEmpty ? 'thread:${widget.request.tid}' : items.first.ownerId;
  }

  void _recordExtent(ContinuousImageExtent extent) {
    _extentRegistry.record(extent);
  }

  void _scheduleInitialJump() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToInitialIndex());
  }

  void _jumpToInitialIndex() {
    final items = _items;
    if (!mounted ||
        !_scrollController.hasClients ||
        items.isEmpty ||
        widget.request.initialIndex <= 0) {
      return;
    }
    final key =
        '${widget.request.tid}:${widget.request.pid}:${widget.request.initialIndex}:${items.length}';
    if (_jumpedRequestKey == key) {
      return;
    }
    _jumpedRequestKey = key;
    final targetIndex = widget.request.initialIndex.clamp(0, items.length - 1);
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) {
      return;
    }
    final offset = _extentRegistry
        .estimateOffsetForIndex(
          targetIndex,
          items,
          crossAxisExtent: MediaQuery.sizeOf(context).width,
          resolver: widget._layoutResolver,
        )
        .clamp(0.0, maxScroll)
        .toDouble();
    _scrollController.jumpTo(offset);
  }
}

class _ThreadImageReaderItem extends StatelessWidget {
  const _ThreadImageReaderItem({
    required this.item,
    required this.layoutResolver,
    required this.imageHeaderBuilder,
    required this.onExtentResolved,
  });

  final ContinuousImageItem item;
  final ContinuousImageLayoutResolver layoutResolver;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ValueChanged<ContinuousImageExtent> onExtentResolved;

  @override
  Widget build(BuildContext context) {
    final hint = layoutResolver.resolveInitialHint(item: item);
    return Padding(
      padding: EdgeInsets.only(bottom: item.spacingAfter),
      child: ContinuousImageExtentObserver(
        item: item,
        aspectRatio: hint.aspectRatio,
        dimensionSource: hint.source,
        onExtentResolved: onExtentResolved,
        child: AspectRatio(
          aspectRatio: hint.aspectRatio,
          child: CachedLibraryImage(
            request: ImageCacheRequest(
              cacheKey: item.cacheKey,
              sourceUrl: item.url,
              ownerType: ImageCacheOwnerType.thread,
              ownerId: item.ownerId,
              role: ImageCacheRole.threadInline,
              imageIndex: item.index,
              retentionClass: ImageRetentionClass.recentReader,
            ),
            fit: BoxFit.fitWidth,
            placeholder: const _ThreadImageReaderPlaceholder(
              label: '图片加载中',
              icon: Icons.image_outlined,
            ),
            errorPlaceholder: const _ThreadImageReaderPlaceholder(
              label: '图片加载失败',
              icon: Icons.broken_image_outlined,
            ),
            headerBuilder: imageHeaderBuilder,
          ),
        ),
      ),
    );
  }
}

class _ThreadImageReaderPlaceholder extends StatelessWidget {
  const _ThreadImageReaderPlaceholder({
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
