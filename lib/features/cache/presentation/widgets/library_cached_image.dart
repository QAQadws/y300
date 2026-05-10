import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/site_url_resolver.dart';

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
    required this.fit,
    this.width,
    this.height,
    required this.placeholder,
    this.headerBuilder,
  });

  final String? localPath;
  final String? imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget placeholder;
  final ImageRequestHeaderBuilder? headerBuilder;

  @override
  State<LibraryCachedImage> createState() => _LibraryCachedImageState();
}

class _LibraryCachedImageState extends State<LibraryCachedImage> {
  static const SiteUrlResolver _urlResolver = SiteUrlResolver();

  Future<Map<String, String>>? _headersFuture;
  String? _headersUrl;
  ImageRequestHeaderBuilder? _headersBuilder;

  @override
  void didUpdateWidget(covariant LibraryCachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl || oldWidget.headerBuilder != widget.headerBuilder) {
      _headersFuture = null;
      _headersUrl = null;
      _headersBuilder = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = widget.localPath?.trim();
    if (local != null && local.isNotEmpty) {
      final file = io.File(local);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          errorBuilder: (context, error, stackTrace) => widget.placeholder,
        );
      }
    }

    final remote = _normalizeRemoteUrl(widget.imageUrl);
    if (remote != null && remote.isNotEmpty) {
      final builder = widget.headerBuilder;
      if (builder == null) {
        return _buildNetworkImage(remote, const <String, String>{});
      }
      return FutureBuilder<Map<String, String>>(
        future: _headersFor(remote, builder),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return widget.placeholder;
          }
          return _buildNetworkImage(remote, snapshot.data ?? const <String, String>{});
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
    if (cached != null && _headersUrl == remote && identical(_headersBuilder, builder)) {
      return cached;
    }
    _headersUrl = remote;
    _headersBuilder = builder;
    _headersFuture = builder.buildHeaders(remote);
    return _headersFuture!;
  }

  Widget _buildNetworkImage(String remote, Map<String, String> headers) {
    return Image.network(
      remote,
      headers: headers.isEmpty ? null : headers,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      errorBuilder: (context, error, stackTrace) => widget.placeholder,
    );
  }

  String? _normalizeRemoteUrl(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return _urlResolver.resolve(trimmed) ?? trimmed;
  }
}
