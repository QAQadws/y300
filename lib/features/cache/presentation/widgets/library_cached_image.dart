import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:y300/core/media/image_display_provider.dart';
import 'package:y300/core/media/image_downscale_policy.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/shared/widgets/forum_default_avatar.dart';

/// Shared image widget for library surfaces.
///
/// It always prefers an existing local file.  Network URLs are treated as a
/// fallback display source only; persistence into the stage-04 cache is handled
/// by repositories/services so UI widgets do not own cache policy.
///
/// 解码降采样：默认通过 [downscalePolicy] 按实际显示尺寸解码，避免大图按原图
/// 解码出超大 bitmap 反复驱逐运行时图片缓存。该控件被书架、详情头、阅读器、
/// 头像等多处复用，内置降采样可一次惠及全部调用点。
class LibraryCachedImage extends StatefulWidget {
  const LibraryCachedImage({
    super.key,
    this.localPath,
    this.imageUrl,
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
    this.headerBuilder,
    this.onImageResolved,
    this.onRemoteImageResolved,
    this.onImageFailed,
  });

  final String? localPath;
  final String? imageUrl;
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
  final ImageRequestHeaderBuilder? headerBuilder;
  final ValueChanged<Size>? onImageResolved;
  final VoidCallback? onRemoteImageResolved;
  final VoidCallback? onImageFailed;

  @override
  State<LibraryCachedImage> createState() => _LibraryCachedImageState();
}

class _LibraryCachedImageState extends State<LibraryCachedImage> {
  static const SiteUrlResolver _urlResolver = SiteUrlResolver();

  Future<Map<String, String>>? _headersFuture;
  String? _headersUrl;
  ImageRequestHeaderBuilder? _headersBuilder;
  bool _remoteResolved = false;
  bool _remoteResolveScheduled = false;
  String? _reportedImageIdentity;
  String? _reportedFailureIdentity;

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
        oldWidget.headerBuilder != widget.headerBuilder) {
      _headersFuture = null;
      _headersUrl = null;
      _headersBuilder = null;
      _remoteResolved = false;
      _remoteResolveScheduled = false;
      _reportedImageIdentity = null;
      _reportedFailureIdentity = null;
    }
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
        return _buildContent(context);
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
          if (frame != null || wasSynchronouslyLoaded) {
            _reportImageResolved(
              testProvider,
              'override:${identityHashCode(testProvider)}',
            );
            return child;
          }
          return widget.placeholder;
        },
        errorBuilder: (context, error, stackTrace) {
          _markImageFailed('override:${identityHashCode(testProvider)}');
          return _errorPlaceholder;
        },
      );
    }

    final local = widget.localPath?.trim();
    if (local != null && local.isNotEmpty) {
      final file = io.File(local);
      if (file.existsSync()) {
        final fileProvider = FileImage(file);
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
            if (frame != null || wasSynchronouslyLoaded) {
              _reportImageResolved(fileProvider, 'file:${file.path}');
              return child;
            }
            return widget.placeholder;
          },
          errorBuilder: (context, error, stackTrace) {
            _markImageFailed('file:${file.path}');
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
      final builder = widget.headerBuilder;
      if (builder == null) {
        return _buildRemoteImageShell(remote, const <String, String>{});
      }
      return FutureBuilder<Map<String, String>>(
        future: _headersFor(remote, builder),
        builder: (context, snapshot) {
          final headers = snapshot.connectionState == ConnectionState.done
              ? snapshot.data ?? const <String, String>{}
              : null;
          return _buildRemoteImageShell(remote, headers);
        },
      );
    }
    return widget.placeholder;
  }

  Future<Map<String, String>> _headersFor(
    String remote,
    ImageRequestHeaderBuilder builder,
  ) {
    final cached = _headersFuture;
    if (cached != null &&
        _headersUrl == remote &&
        identical(_headersBuilder, builder)) {
      return cached;
    }
    _headersUrl = remote;
    _headersBuilder = builder;
    _headersFuture = builder.buildHeaders(remote);
    return _headersFuture!;
  }

  Widget _buildRemoteImageShell(String remote, Map<String, String>? headers) {
    final children = <Widget>[
      if (!_remoteResolved) widget.placeholder,
      if (headers != null) _buildNetworkImage(remote, headers),
    ];
    return Stack(fit: StackFit.passthrough, children: children);
  }

  Widget _buildNetworkImage(String remote, Map<String, String> headers) {
    final provider =
        widget.remoteImageProviderOverride ??
        NetworkImage(remote, headers: headers.isEmpty ? null : headers);
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
        if (frame != null || wasSynchronouslyLoaded) {
          final isFirstFrame = !_remoteResolved && !_remoteResolveScheduled;
          _markRemoteResolved();
          if (isFirstFrame) {
            widget.onRemoteImageResolved?.call();
          }
          _reportImageResolved(provider, 'remote:$remote');
          return child;
        }
        return const SizedBox.shrink();
      },
      errorBuilder: (context, error, stackTrace) {
        _markRemoteResolved();
        _markImageFailed('remote:$remote');
        return _errorPlaceholder;
      },
    );
  }

  void _reportImageResolved(ImageProvider provider, String identity) {
    final callback = widget.onImageResolved;
    if (callback == null || _reportedImageIdentity == identity) {
      return;
    }
    _reportedImageIdentity = identity;
    final stream = provider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (imageInfo, _) {
        stream.removeListener(listener);
        final image = imageInfo.image;
        final size = Size(image.width.toDouble(), image.height.toDouble());
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            callback(size);
          }
        });
      },
      onError: (error, stackTrace) {
        stream.removeListener(listener);
        if (_reportedImageIdentity == identity) {
          _reportedImageIdentity = null;
        }
        _markImageFailed(identity);
      },
    );
    stream.addListener(listener);
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
