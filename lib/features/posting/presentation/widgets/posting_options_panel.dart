import 'package:flutter/material.dart';

/// 发帖页底部的"选项面板"。
///
/// 把"使用签名 / 允许通知作者 / 关闭 BBCode / 关闭表情解析 / 关闭 URL 解析"
/// 五个开关收在一处，避免页面 ListView 直接铺一长串 SwitchListTile。
/// 每个开关的 widget key 都是入参，方便页面用稳定 key 做查询、写测试。
class PostingOptionsPanel extends StatelessWidget {
  const PostingOptionsPanel({
    super.key,
    required this.useSignature,
    required this.allowNoticeAuthor,
    required this.bbCodeOff,
    required this.smileyOff,
    required this.parseUrlOff,
    required this.onUseSignatureChanged,
    required this.onAllowNoticeAuthorChanged,
    required this.onBbCodeOffChanged,
    required this.onSmileyOffChanged,
    required this.onParseUrlOffChanged,
    this.enabled = true,
    this.useSignatureKey,
    this.allowNoticeAuthorKey,
    this.bbCodeOffKey,
    this.smileyOffKey,
    this.parseUrlOffKey,
  });

  final bool useSignature;
  final bool allowNoticeAuthor;
  final bool bbCodeOff;
  final bool smileyOff;
  final bool parseUrlOff;
  final ValueChanged<bool> onUseSignatureChanged;
  final ValueChanged<bool> onAllowNoticeAuthorChanged;
  final ValueChanged<bool> onBbCodeOffChanged;
  final ValueChanged<bool> onSmileyOffChanged;
  final ValueChanged<bool> onParseUrlOffChanged;
  final bool enabled;
  final Key? useSignatureKey;
  final Key? allowNoticeAuthorKey;
  final Key? bbCodeOffKey;
  final Key? smileyOffKey;
  final Key? parseUrlOffKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _switch(
          widgetKey: useSignatureKey,
          title: '使用个人签名',
          value: useSignature,
          onChanged: onUseSignatureChanged,
        ),
        _switch(
          widgetKey: allowNoticeAuthorKey,
          title: '允许通知作者',
          value: allowNoticeAuthor,
          onChanged: onAllowNoticeAuthorChanged,
        ),
        _switch(
          widgetKey: bbCodeOffKey,
          title: '关闭 BBCode 解析',
          value: bbCodeOff,
          onChanged: onBbCodeOffChanged,
        ),
        _switch(
          widgetKey: smileyOffKey,
          title: '关闭表情解析',
          value: smileyOff,
          onChanged: onSmileyOffChanged,
        ),
        _switch(
          widgetKey: parseUrlOffKey,
          title: '关闭 URL 解析',
          value: parseUrlOff,
          onChanged: onParseUrlOffChanged,
        ),
      ],
    );
  }

  Widget _switch({
    required Key? widgetKey,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      key: widgetKey,
      value: value,
      onChanged: enabled ? onChanged : null,
      title: Text(title),
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }
}
