import 'package:y300/features/posting/domain/models/posting_models.dart';

/// 发帖草稿 `extras` 编解码器。
///
/// `ComposerDraftSnapshot.extras` 是 `Map<String, String>` —— composer_shared
/// 留给业务侧自由扩展的草稿键值口袋。如果让 controller 直接用字符串字面量
/// （`'typeid' / 'tags' / 'special' / ...`）读写，迁移字段时 controller / 测试 /
/// codec 三处都要改。把"业务字段 ↔ 字符串 KV"的映射收在这里，让 controller
/// 只面对结构化值对象。
///
/// 兼容性：[decode] 对所有缺字段都回退默认值，老版本只写过 typeid 的草稿
/// 也能完整恢复。
class PostingDraftExtrasCodec {
  const PostingDraftExtrasCodec();

  static const String _kTypeid = 'typeid';
  static const String _kAllowNoticeAuthor = 'allowNoticeAuthor';
  static const String _kBbCodeOff = 'bbCodeOff';
  static const String _kSmileyOff = 'smileyOff';
  static const String _kParseUrlOff = 'parseurlOff';
  static const String _kTags = 'tags';
  static const String _kSpecial = 'special';
  static const String _kPollMultiple = 'pollMultiple';
  static const String _kPollMaxChoices = 'pollMaxChoices';
  static const String _kPollExpirationDays = 'pollExpirationDays';
  static const String _kPollOvert = 'pollOvert';
  static const String _kPollVisibility = 'pollVisibility';
  static const String _kPollOptions = 'pollOptions';

  /// tags / pollOptions 的分隔符。Discuz tags form 字段本身就用英文逗号；
  /// 投票选项用换行——本地草稿沿用相同分隔，让"看一眼草稿 KV 就能还原"。
  static const String _tagsSeparator = ',';
  static const String _pollOptionsSeparator = '\n';

  Map<String, String> encode({
    required String? selectedTypeId,
    required bool allowNoticeAuthor,
    required bool bbCodeOff,
    required bool smileyOff,
    required bool parseUrlOff,
    required List<String> tags,
    required NewThreadSpecial special,
    required NewThreadPollDraft? poll,
  }) {
    final result = <String, String>{};
    if (selectedTypeId != null && selectedTypeId.trim().isNotEmpty) {
      result[_kTypeid] = selectedTypeId.trim();
    }
    if (allowNoticeAuthor) result[_kAllowNoticeAuthor] = '1';
    if (bbCodeOff) result[_kBbCodeOff] = '1';
    if (smileyOff) result[_kSmileyOff] = '1';
    if (parseUrlOff) result[_kParseUrlOff] = '1';
    if (tags.isNotEmpty) {
      result[_kTags] = tags.join(_tagsSeparator);
    }
    // special 仅当不是 normal 时落盘，进一步压缩"老草稿没这字段"的兼容路径。
    if (special != NewThreadSpecial.normal) {
      result[_kSpecial] = _specialToString(special);
    }
    if (poll != null) {
      if (poll.options.isNotEmpty) {
        // 选项里若混进了换行字符会破坏分隔；这里做简单转义为空格——
        // 选项本身的 trim 在 normalizer 阶段做，这里不重复。
        result[_kPollOptions] = poll.options
            .map((option) => option.replaceAll('\n', ' ').replaceAll('\r', ' '))
            .join(_pollOptionsSeparator);
      }
      if (poll.multiple) result[_kPollMultiple] = '1';
      if (poll.maxChoices > 1) {
        result[_kPollMaxChoices] = poll.maxChoices.toString();
      }
      if (poll.expirationDays > 0) {
        result[_kPollExpirationDays] = poll.expirationDays.toString();
      }
      if (poll.overt) result[_kPollOvert] = '1';
      if (poll.visibilityPoll) result[_kPollVisibility] = '1';
    }
    return result;
  }

  PostingDraftExtras decode(Map<String, String> raw) {
    return PostingDraftExtras(
      selectedTypeId: _readNonEmpty(raw[_kTypeid]),
      allowNoticeAuthor: _readBool(raw[_kAllowNoticeAuthor]),
      bbCodeOff: _readBool(raw[_kBbCodeOff]),
      smileyOff: _readBool(raw[_kSmileyOff]),
      parseUrlOff: _readBool(raw[_kParseUrlOff]),
      tags: _readTags(raw[_kTags]),
      special: _readSpecial(raw[_kSpecial]),
      poll: _readPoll(raw),
    );
  }

  String? _readNonEmpty(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  bool _readBool(String? value) {
    if (value == null) return false;
    final normalized = value.trim().toLowerCase();
    return normalized == '1' || normalized == 'true';
  }

  int _readInt(String? value, {int fallback = 0}) {
    if (value == null) return fallback;
    return int.tryParse(value.trim()) ?? fallback;
  }

  List<String> _readTags(String? value) {
    if (value == null || value.trim().isEmpty) return const <String>[];
    return value
        .split(_tagsSeparator)
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
  }

  NewThreadSpecial _readSpecial(String? value) {
    if (value == null) return NewThreadSpecial.normal;
    switch (value.trim().toLowerCase()) {
      case 'poll':
      case '1':
        return NewThreadSpecial.poll;
      default:
        return NewThreadSpecial.normal;
    }
  }

  /// 仅当 raw 至少包含一个 poll 字段时返回非空 NewThreadPollDraft；
  /// 这样普通帖草稿不会无中生有出空 poll 对象，UI 重启后还是普通帖。
  NewThreadPollDraft? _readPoll(Map<String, String> raw) {
    final hasAnyPollField = raw.containsKey(_kPollOptions) ||
        raw.containsKey(_kPollMultiple) ||
        raw.containsKey(_kPollMaxChoices) ||
        raw.containsKey(_kPollExpirationDays) ||
        raw.containsKey(_kPollOvert) ||
        raw.containsKey(_kPollVisibility);
    if (!hasAnyPollField) {
      // 但若 special 显式声明是 poll，给一个空 draft，让 UI 进入 poll 模式。
      if (_readSpecial(raw[_kSpecial]) == NewThreadSpecial.poll) {
        return NewThreadPollDraft.empty;
      }
      return null;
    }
    final optionsRaw = raw[_kPollOptions];
    final options = optionsRaw == null || optionsRaw.isEmpty
        ? const <String>[]
        : optionsRaw.split(_pollOptionsSeparator).toList(growable: false);
    return NewThreadPollDraft(
      options: options,
      multiple: _readBool(raw[_kPollMultiple]),
      maxChoices: _readInt(raw[_kPollMaxChoices], fallback: 1),
      expirationDays: _readInt(raw[_kPollExpirationDays]),
      overt: _readBool(raw[_kPollOvert]),
      visibilityPoll: _readBool(raw[_kPollVisibility]),
    );
  }

  String _specialToString(NewThreadSpecial special) {
    switch (special) {
      case NewThreadSpecial.normal:
        return 'normal';
      case NewThreadSpecial.poll:
        return 'poll';
    }
  }
}

/// 草稿 extras 解码后的结构化视图。
class PostingDraftExtras {
  const PostingDraftExtras({
    this.selectedTypeId,
    this.allowNoticeAuthor = false,
    this.bbCodeOff = false,
    this.smileyOff = false,
    this.parseUrlOff = false,
    this.tags = const <String>[],
    this.special = NewThreadSpecial.normal,
    this.poll,
  });

  static const PostingDraftExtras empty = PostingDraftExtras();

  final String? selectedTypeId;
  final bool allowNoticeAuthor;
  final bool bbCodeOff;
  final bool smileyOff;
  final bool parseUrlOff;
  final List<String> tags;
  final NewThreadSpecial special;
  final NewThreadPollDraft? poll;
}
