import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/shared/widgets/forum_default_avatar.dart';

/// Shared image widget for library surfaces.
///
/// It always prefers an existing local file.  Network URLs are treated as a
/// fallback display source only; persistence into the stage-04 cache is handled
/// by repositories/services so UI widgets do not own cache policy.
class LibraryCachedImage extends StatefulWidget {
  const LibraryCachedImage({
    super.key,
    this.localPath,
    this.imageUrl,
    this.imageProviderOverride,
    required this.fit,
    this.width,
    this.height,
    required this.placeholder,
    this.errorPlaceholder,
    this.headerBuilder,
    this.onImageResolved,
    this.onImageFailed,
  });

  final String? localPath;
  final String? imageUrl;
  @visibleForTesting
  final ImageProvider? imageProviderOverride;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget placeholder;
  final Widget? errorPlaceholder;
  final ImageRequestHeaderBuilder? headerBuilder;
  final ValueChanged<Size>? onImageResolved;
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

  @override
  void didUpdateWidget(covariant LibraryCachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.localPath != widget.localPath ||
        oldWidget.imageProviderOverride != widget.imageProviderOverride ||
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
    final testProvider = widget.imageProviderOverride;
    if (testProvider != null) {
      return Image(
        image: testProvider,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (frame != null || wasSynchronouslyLoaded) {
            _reportImageResolved(
              testProvider,
              'override:${identityHashCode(testProvider)}',
            );
          }
          return child;
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
        return Image.file(
          file,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (frame != null || wasSynchronouslyLoaded) {
              _reportImageResolved(FileImage(file), 'file:${file.path}');
            }
            return child;
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
    final provider = NetworkImage(
      remote,
      headers: headers.isEmpty ? null : headers,
    );
    return Image(
      image: provider,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      gaplessPlayback: true,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          _markRemoteResolved();
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
