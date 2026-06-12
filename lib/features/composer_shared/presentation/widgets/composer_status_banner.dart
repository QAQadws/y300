import 'package:flutter/material.dart';

/// 编辑器顶部的"状态条"——给 reply / posting 共用。
///
/// 三种渲染：
/// - [ComposerStatusBanner.loading]：左侧菊花 + 单行文本，给"正在加载元数据 / 准备楼层引用"用。
/// - [ComposerStatusBanner.error]：错误色描边 + 错误文案 + "重试"按钮。
/// - [ComposerStatusBanner.info]：默认描边 + 单行文本，可作"已恢复草稿"或楼层引用预览。
///
/// 内容侧的样式（描边色、内边距、圆角）保持一致，调用方只关心传"什么文案、点了重试做什么"。
class ComposerStatusBanner extends StatelessWidget {
  const ComposerStatusBanner._({
    super.key,
    required this.text,
    required _ComposerStatusBannerVariant variant,
    this.textKey,
    this.onRetry,
    this.retryButtonKey,
    this.retryLabel = '重试',
    this.maxLines,
  }) : _variant = variant;

  /// 加载态：左侧菊花 + 单行文本。
  const ComposerStatusBanner.loading({
    Key? key,
    required String text,
    Key? textKey,
  }) : this._(
          key: key,
          text: text,
          variant: _ComposerStatusBannerVariant.loading,
          textKey: textKey,
        );

  /// 错误态：错误色描边 + 文案 + 重试按钮。
  const ComposerStatusBanner.error({
    Key? key,
    required String text,
    required VoidCallback onRetry,
    Key? textKey,
    Key? retryButtonKey,
    String retryLabel = '重试',
  }) : this._(
          key: key,
          text: text,
          variant: _ComposerStatusBannerVariant.error,
          textKey: textKey,
          onRetry: onRetry,
          retryButtonKey: retryButtonKey,
          retryLabel: retryLabel,
        );

  /// 信息态：默认描边 + 文案。
  const ComposerStatusBanner.info({
    Key? key,
    required String text,
    Key? textKey,
    int? maxLines,
  }) : this._(
          key: key,
          text: text,
          variant: _ComposerStatusBannerVariant.info,
          textKey: textKey,
          maxLines: maxLines,
        );

  final String text;
  final _ComposerStatusBannerVariant _variant;
  final Key? textKey;
  final VoidCallback? onRetry;
  final Key? retryButtonKey;
  final String retryLabel;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isError = _variant == _ComposerStatusBannerVariant.error;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: isError ? colorScheme.error : colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(8),
        color: isError ? colorScheme.errorContainer : colorScheme.surface,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: _buildBody(colorScheme),
      ),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    switch (_variant) {
      case _ComposerStatusBannerVariant.loading:
        return Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(text, key: textKey)),
          ],
        );
      case _ComposerStatusBannerVariant.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              key: textKey,
              style: TextStyle(color: colorScheme.onErrorContainer),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              key: retryButtonKey,
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(retryLabel),
            ),
          ],
        );
      case _ComposerStatusBannerVariant.info:
        return Text(
          text,
          key: textKey,
          maxLines: maxLines,
          overflow: maxLines != null ? TextOverflow.ellipsis : null,
        );
    }
  }
}

enum _ComposerStatusBannerVariant {
  loading,
  error,
  info,
}
