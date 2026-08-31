import 'dart:async';
import 'dart:io' as io;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/media/image_display_provider.dart';
import 'package:y300/core/media/image_downscale_policy.dart';
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/image_loading/data/app_image_providers.dart';
import 'package:y300/shared/widgets/forum_default_avatar.dart';

enum LibraryImageFrameSource { localFile, remote, override }

/// Shared image widget for library surfaces.
///
/// It always prefers an existing local file.  Network URLs are treated as a
/// fallback display source only; persistence into the stage-04 cache is handled
/// by repositories/services so UI widgets do not own cache policy.
///
/// 解码降采样：默认通过 [downscalePolicy] 按实际显示尺寸解码，避免大图按原图
/// 解码出超大 bitmap 反复驱逐运行时图片缓存。该控件被书架、详情头、阅读器、
/// 头像等多处复用，内置降采样可一次惠及全部调用点。
class LibraryCachedImage extends ConsumerStatefulWidget {
  const LibraryCachedImage({
    super.key,
    this.localPath,
    this.imageUrl,
    this.cacheKey,
    this.referer,
    this.imageProviderOverride,
    this.remoteImageProviderOverride,
    required this.fit,
    this.width,
    this.height,
    this.decodeDisplaySize,
    this.alignment = Alignment.center,
    this.downscalePolicy = const WidthBoundImageDownscalePolicy(),
    required this.placeholder,
    this.errorPlaceholder,
    this.onFirstFrameRendered,
    this.onImageFailed,
    this.onLocalImageDecodeFailed,
    this.fadeInDuration = Duration.zero,
    this.retryToken = 0,
  });

  final String? localPath;
  final String? imageUrl;
  final String? cacheKey;
  final String? referer;
  @visibleForTesting
  final ImageProvider? imageProviderOverride;
  @visibleForTesting
  final ImageProvider? remoteImageProviderOverride;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Size? decodeDisplaySize;

  /// `BoxFit.cover` 下的对齐点（自定义封面焦点）。默认居中。
  final AlignmentGeometry alignment;
  final ImageDownscalePolicy downscalePolicy;
  final Widget placeholder;
  final Widget? errorPlaceholder;
  final ValueChanged<LibraryImageFrameSource>? onFirstFrameRendered;
  final VoidCallback? onImageFailed;
  final void Function(Object error, StackTrace? stackTrace)?
  onLocalImageDecodeFailed;

  /// Duration used to cross-fade the placeholder into an asynchronously
  /// decoded first frame. Synchronous image-cache hits remain immediate.
  final Duration fadeInDuration;

  /// 重试代次。调用方自增即可让本控件重新解码一次同一来源。
  ///
  /// 失败重试必须换掉 [Image] 元素：provider 相等时 `Image` 不会重新 resolve，
  /// 仅靠 setState 无法把已失败的流拉回来。
  final int retryToken;

  @override
  ConsumerState<LibraryCachedImage> createState() => _LibraryCachedImageState();
}

class _LibraryCachedImageState extends ConsumerState<LibraryCachedImage> {
  static const SiteUrlResolver _urlResolver = SiteUrlResolver();

  bool _remoteResolved = false;
  bool _remoteResolveScheduled = false;
  String? _reportedFirstFrameIdentity;
  String? _reportedFailureIdentity;
  String? _reportedDecodeFailureIdentity;
  String? _evictedFailureIdentity;
  int _retryEpoch = 0;

  /// 本帧解码目标（宽度优先策略结果），供网络分支与 contain 文件分支复用。
  /// 本帧显示框尺寸与 DPR，供 cover 感知降采样解析复用。
  Size _displaySize = Size.zero;
  double _devicePixelRatio = 1;
  ImageDecodeTarget _decodeTarget = ImageDecodeTarget.none;

  @override
  void didUpdateWidget(covariant LibraryCachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.localPath != widget.localPath ||
        oldWidget.imageProviderOverride != widget.imageProviderOverride ||
        oldWidget.remoteImageProviderOverride !=
            widget.remoteImageProviderOverride ||
        oldWidget.cacheKey != widget.cacheKey ||
        oldWidget.referer != widget.referer) {
      _resetLoadState();
    }
    if (oldWidget.retryToken != widget.retryToken) {
      _retryEpoch += 1;
      _resetLoadState();
    }
  }

  void _resetLoadState() {
    _remoteResolved = false;
    _remoteResolveScheduled = false;
    _reportedFirstFrameIdentity = null;
    _reportedFailureIdentity = null;
    _reportedDecodeFailureIdentity = null;
    _evictedFailureIdentity = null;
  }

  @override
  Widget build(BuildContext context) {
    // 在布局阶段确定解码目标像素：优先用显式 width/height，否则取布局约束，
    // 由 downscalePolicy 统一翻译为 cacheWidth/cacheHeight，供下方各分支复用。
    return LayoutBuilder(
      builder: (context, constraints) {
        // 显式 width/height 可能是 double.infinity（如竖向阅读 width: infinity 表示
        // 撑满列宽），此时退回布局约束取真实宽度，否则会被当成无界而跳过降采样。
        final decodeDisplaySize = widget.decodeDisplaySize;
        _displaySize =
            decodeDisplaySize != null &&
                decodeDisplaySize.width.isFinite &&
                decodeDisplaySize.width > 0
            ? decodeDisplaySize
            : Size(
                _finiteOr(widget.width, constraints.maxWidth),
                _finiteOr(widget.height, constraints.maxHeight),
              );
        _devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
        _decodeTarget = widget.downscalePolicy.resolve(
          displaySize: _displaySize,
          devicePixelRatio: _devicePixelRatio,
        );
        // 带上重试代次：换 key 才能丢掉已失败的 Image 元素与其 ImageStream。
        return KeyedSubtree(
          key: ValueKey<int>(_retryEpoch),
          child: _buildContent(context),
        );
      },
    );
  }

  /// 取 [preferred]（若为有限正值），否则回退到 [fallback]（仍要求有限），
  /// 都不可用时返回 NaN，交由策略判定为“无界、不降采样”。
  double _finiteOr(double? preferred, double fallback) {
    if (preferred != null && preferred.isFinite) {
      return preferred;
    }
    return fallback.isFinite ? fallback : double.nan;
  }

  Widget _buildContent(BuildContext context) {
    final testProvider = widget.imageProviderOverride;
    if (testProvider != null) {
      return Image(
        image: testProvider,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        alignment: widget.alignment,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          final isResolved = frame != null || wasSynchronouslyLoaded;
          if (isResolved) {
            _reportFirstFrameRendered(
              'override:${identityHashCode(testProvider)}',
              LibraryImageFrameSource.override,
            );
          }
          return _buildFirstFrameTransition(
            context: context,
            child: child,
            isResolved: isResolved,
            wasSynchronouslyLoaded: wasSynchronouslyLoaded,
            identity: 'override:${identityHashCode(testProvider)}',
          );
        },
        errorBuilder: (context, error, stackTrace) {
          final identity = 'override:${identityHashCode(testProvider)}';
          _reportLocalDecodeFailure(identity, error, stackTrace);
          _markImageFailed(identity);
          return _errorPlaceholder;
        },
      );
    }

    final local = widget.localPath?.trim();
    if (local != null && local.isNotEmpty) {
      final file = io.File(local);
      if (file.existsSync()) {
        // cover 用 cover 感知降采样修复横长竖短图模糊；其它 fit 走宽度优先策略。
        final displayProvider = resolveDownscaledFileImageProvider(
          localPath: file.path,
          fit: widget.fit,
          displaySize: _displaySize,
          devicePixelRatio: _devicePixelRatio,
          downscalePolicy: widget.downscalePolicy,
        );
        return Image(
          image: displayProvider,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          alignment: widget.alignment,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            final isResolved = frame != null || wasSynchronouslyLoaded;
            if (isResolved) {
              _reportFirstFrameRendered(
                'file:${file.path}',
                LibraryImageFrameSource.localFile,
              );
            }
            return _buildFirstFrameTransition(
              context: context,
              child: child,
              isResolved: isResolved,
              wasSynchronouslyLoaded: wasSynchronouslyLoaded,
              identity: 'file:${file.path}',
            );
          },
          errorBuilder: (context, error, stackTrace) {
            final identity = 'file:${file.path}';
            _evictFailedProvider(displayProvider, identity);
            _reportLocalDecodeFailure(identity, error, stackTrace);
            _markImageFailed(identity);
            return _errorPlaceholder;
          },
        );
      }
    }

    final remote = _normalizeRemoteUrl(widget.imageUrl);
    if (remote != null && remote.isNotEmpty) {
      if (isForumDefaultOrUnsupportedAvatarUrl(remote)) {
        return _errorPlaceholder;
      }
      return _buildRemoteImageShell(remote);
    }
    return widget.placeholder;
  }

  Widget _buildRemoteImageShell(String remote) {
    final override = widget.remoteImageProviderOverride;
    if (override != null) {
      return _buildNetworkImage(remote, override);
    }
    final manager = ref.watch(appImageCacheManagerProvider);
    return manager.when(
      data: (value) => _buildNetworkImage(
        remote,
        CachedNetworkImageProvider(
          remote,
          cacheKey: widget.cacheKey?.trim().isNotEmpty == true
              ? widget.cacheKey!.trim()
              : remote,
          cacheManager: value.rawCacheManager,
          headers: widget.referer == null
              ? null
              : <String, String>{'Referer': widget.referer.toString()},
        ),
      ),
      loading: () => widget.placeholder,
      error: (error, stackTrace) {
        final identity = 'cache-manager:$remote';
        _markRemoteResolved();
        _markImageFailed(identity);
        return _errorPlaceholder;
      },
    );
  }

  Widget _buildNetworkImage(String remote, ImageProvider provider) {
    final displayProvider = widget.decodeDisplaySize == null
        ? ResizeImage.resizeIfNeeded(
            _decodeTarget.cacheWidth,
            _decodeTarget.cacheHeight,
            provider,
          )
        : resolveDownscaledImageProvider(
            base: provider,
            fit: widget.fit,
            displaySize: _displaySize,
            devicePixelRatio: _devicePixelRatio,
            downscalePolicy: widget.downscalePolicy,
          );
    return Image(
      image: displayProvider,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      alignment: widget.alignment,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        final isResolved = frame != null || wasSynchronouslyLoaded;
        if (isResolved) {
          _markRemoteResolved();
          _reportFirstFrameRendered(
            'remote:$remote',
            LibraryImageFrameSource.remote,
          );
        }
        return _buildFirstFrameTransition(
          context: context,
          child: child,
          isResolved: isResolved,
          wasSynchronouslyLoaded: wasSynchronouslyLoaded,
          identity: 'remote:$remote',
        );
      },
      errorBuilder: (context, error, stackTrace) {
        _markRemoteResolved();
        _evictFailedProvider(displayProvider, 'remote:$remote');
        _markImageFailed('remote:$remote');
        return _errorPlaceholder;
      },
    );
  }

  Widget _buildFirstFrameTransition({
    required BuildContext context,
    required Widget child,
    required bool isResolved,
    required bool wasSynchronouslyLoaded,
    required String identity,
  }) {
    final duration = widget.fadeInDuration;
    if (wasSynchronouslyLoaded ||
        duration <= Duration.zero ||
        MediaQuery.disableAnimationsOf(context)) {
      return isResolved ? child : widget.placeholder;
    }
    return AnimatedSwitcher(
      duration: duration,
      reverseDuration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          fit: StackFit.passthrough,
          alignment: Alignment.center,
          children: <Widget>[...previousChildren, ?currentChild],
        );
      },
      child: KeyedSubtree(
        key: ValueKey<String>(
          isResolved ? 'image:$identity' : 'placeholder:$identity',
        ),
        child: isResolved ? child : widget.placeholder,
      ),
    );
  }

  /// 失败即从 Flutter 图片缓存驱逐，否则重试可能拿回同一个已失败的 completer。
  ///
  /// 未降采样时（无界宽度 → [ImageDecodeTarget.none]，provider 不被 `ResizeImage`
  /// 包装）失败的 completer 会留在图片缓存的 pending 表里，新监听者加入时被立刻
  /// 重放同一个异常，重试恒为空转。必须用真正被 resolve 的 display provider：
  /// 包装后缓存 key 是复合 key，驱逐内层 provider 不会命中它。
  void _evictFailedProvider(ImageProvider provider, String identity) {
    if (_evictedFailureIdentity == identity) {
      return;
    }
    _evictedFailureIdentity = identity;
    unawaited(provider.evict().catchError((Object _) => false));
  }

  void _reportFirstFrameRendered(
    String identity,
    LibraryImageFrameSource source,
  ) {
    final callback = widget.onFirstFrameRendered;
    if (callback == null || _reportedFirstFrameIdentity == identity) {
      return;
    }
    _reportedFirstFrameIdentity = identity;
    callback(source);
  }

  void _markImageFailed(String identity) {
    final callback = widget.onImageFailed;
    if (callback == null || _reportedFailureIdentity == identity) {
      return;
    }
    _reportedFailureIdentity = identity;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        callback();
      }
    });
  }

  void _reportLocalDecodeFailure(
    String identity,
    Object error,
    StackTrace? stackTrace,
  ) {
    final callback = widget.onLocalImageDecodeFailed;
    if (callback == null || _reportedDecodeFailureIdentity == identity) {
      return;
    }
    _reportedDecodeFailureIdentity = identity;
    callback(error, stackTrace);
  }

  void _markRemoteResolved() {
    if (_remoteResolved || _remoteResolveScheduled) {
      return;
    }
    _remoteResolveScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _remoteResolved = true;
        _remoteResolveScheduled = false;
      });
    });
  }

  Widget get _errorPlaceholder => widget.errorPlaceholder ?? widget.placeholder;

  String? _normalizeRemoteUrl(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return _urlResolver.resolve(trimmed) ?? trimmed;
  }
}
