import 'package:flutter/material.dart';
import 'package:y300/l10n/app_localizations.dart';

/// 图片加载失败后的统一重试占位。
///
/// 漫画阅读器、帖子图片阅读器和帖子正文内联图的失败语义完全一致（一句提示 + 一
/// 个重试入口），差异只在可用空间：全屏阅读页高度充足，正文内联图可能只剩几十像
/// 素。因此这里按实际约束自动降级密度，调用方只负责外层取景（居中、宽高比或底
/// 色），不再各自复制一份失败 UI。
class ImageRetryPlaceholder extends StatelessWidget {
  const ImageRetryPlaceholder({
    super.key,
    required this.onRetry,
    this.message,
    this.retryLabel,
    this.icon = Icons.broken_image_outlined,
    this.retryButtonKey,
  });

  final VoidCallback onRetry;
  final String? message;
  final String? retryLabel;
  final IconData icon;

  /// 重试入口的 key。阅读器按图片 URL 区分同屏多张失败图，便于测试与定位。
  final Key? retryButtonKey;

  /// 低于此高度只留一个可点图标，再排文字必然溢出。
  static const double _iconOnlyMaxHeight = 44;

  /// 低于此宽度同样退化为图标：一行“提示 + 按钮”已经排不开。
  static const double _iconOnlyMaxWidth = 132;

  /// 低于此高度改用单行紧凑布局，够不上竖排三件套。
  static const double _compactMaxHeight = 112;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        switch (_resolveDensity(constraints)) {
          case _ImageRetryDensity.iconOnly:
            return _buildIconOnly(context, constraints);
          case _ImageRetryDensity.compact:
            return _buildCompact(context);
          case _ImageRetryDensity.comfortable:
            return _buildComfortable(context);
        }
      },
    );
  }

  /// 无界高度按充裕处理：竖向列表里的失败位本来就该给完整面板。
  _ImageRetryDensity _resolveDensity(BoxConstraints constraints) {
    final height = constraints.maxHeight;
    final width = constraints.maxWidth;
    if (height.isFinite && height < _iconOnlyMaxHeight) {
      return _ImageRetryDensity.iconOnly;
    }
    if (width.isFinite && width < _iconOnlyMaxWidth) {
      return _ImageRetryDensity.iconOnly;
    }
    if (height.isFinite && height < _compactMaxHeight) {
      return _ImageRetryDensity.compact;
    }
    return _ImageRetryDensity.comfortable;
  }

  Widget _buildIconOnly(BuildContext context, BoxConstraints constraints) {
    final available = constraints.maxHeight.isFinite
        ? constraints.maxHeight
        : _iconOnlyMaxHeight;
    final size = (available - 8).clamp(12.0, 20.0).toDouble();
    return Center(
      child: Tooltip(
        message: _retryLabel(context),
        child: InkResponse(
          key: retryButtonKey,
          onTap: onRetry,
          radius: size,
          child: Icon(icon, size: size, color: _iconColor(context)),
        ),
      ),
    );
  }

  Widget _buildCompact(BuildContext context) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18, color: _iconColor(context)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(_message(context), overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 4),
          TextButton(
            key: retryButtonKey,
            onPressed: onRetry,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(_retryLabel(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildComfortable(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 28, color: _iconColor(context)),
          const SizedBox(height: 8),
          Text(_message(context)),
          const SizedBox(height: 8),
          OutlinedButton(
            key: retryButtonKey,
            onPressed: onRetry,
            child: Text(_retryLabel(context)),
          ),
        ],
      ),
    );
  }

  Color _iconColor(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;

  String _message(BuildContext context) =>
      message ?? AppLocalizations.of(context).readerImageLoadFailed;

  String _retryLabel(BuildContext context) =>
      retryLabel ?? AppLocalizations.of(context).commonRetry;
}

enum _ImageRetryDensity { iconOnly, compact, comfortable }
