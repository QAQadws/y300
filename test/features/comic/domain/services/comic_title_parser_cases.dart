class ComicTitleParserCase {
  const ComicTitleParserCase({
    required this.id,
    required this.rawTitle,
    required this.expectedNormalizedTitle,
    this.expectedEpisodeLabel,
    this.expectedTranslationGroup,
    this.expectedAuthor,
  });

  final String id;
  final String rawTitle;
  final String expectedNormalizedTitle;
  final String? expectedEpisodeLabel;
  final String? expectedTranslationGroup;
  final String? expectedAuthor;
}

class ComicTitleRuleSummaryCase {
  const ComicTitleRuleSummaryCase({
    required this.id,
    required this.rawTitle,
    required this.targetSummary,
  });

  final String id;
  final String rawTitle;
  final String targetSummary;
}

class ComicTitleAnalyzerCase {
  const ComicTitleAnalyzerCase({
    required this.id,
    required this.rawTitle,
    required this.expectedCleanBookName,
    required this.expectedSearchKeyword,
    this.expectedAuthorPrefix,
    this.expectedEpisodeLabel,
    this.expectedChapterNumber,
    this.expectedPossibleChapterNumbers = const <double>[],
  });

  final String id;
  final String rawTitle;
  final String expectedCleanBookName;
  final String expectedSearchKeyword;
  final String? expectedAuthorPrefix;
  final String? expectedEpisodeLabel;
  final double? expectedChapterNumber;
  final List<double> expectedPossibleChapterNumbers;
}

/// 兼容老 [ComicSubjectMetadata] 字段映射的样本，输入全部使用真实漫画帖子标题。
///
/// 阶段 0 早期曾用 GBK 解码为 UTF-8 的 mojibake 字面量构造样本，那是把源 Kotlin
/// 文件被错误解码后的字节当成测试数据，会让解析器误以为需要识别 mojibake。
/// 现在统一改成真实样本，避免这条错误路径在阶段 2/3 继续传播。
final List<ComicTitleParserCase> currentComicSubjectParserCases =
    <ComicTitleParserCase>[
      const ComicTitleParserCase(
        id: 'volume_marker_now_stripped',
        rawTitle: '[Scan] Comic Title Vol.2',
        expectedNormalizedTitle: 'Comic Title',
        expectedTranslationGroup: 'Scan',
        expectedEpisodeLabel: 'Vol.2',
      ),
      const ComicTitleParserCase(
        id: 'special_episode_now_classified',
        rawTitle: 'Comic Title 番外',
        expectedNormalizedTitle: 'Comic Title',
        expectedEpisodeLabel: '番外',
      ),
      const ComicTitleParserCase(
        id: 'translation_group_and_author_mapping',
        rawTitle: '[作者名][汉化组] 漫画标题 第2话上',
        expectedNormalizedTitle: '漫画标题',
        expectedEpisodeLabel: '第2话上',
        expectedTranslationGroup: '汉化组',
        expectedAuthor: '作者名',
      ),
      const ComicTitleParserCase(
        id: 'real_sample_translation_group_first',
        rawTitle: '【汉化工房九九组】[サンクス仮面]独行者们，青春挡不住！ 第1话',
        expectedNormalizedTitle: '独行者们，青春挡不住',
        expectedEpisodeLabel: '第1话',
        expectedTranslationGroup: '汉化工房九九组',
        expectedAuthor: 'サンクス仮面',
      ),
      const ComicTitleParserCase(
        id: 'real_sample_author_first',
        rawTitle: '【橋本ライドン】 来签订契约吧!精疲力竭的女子与爱照顾人的恶魔的同居生活 第12话 Kakukuroi汉化组',
        expectedNormalizedTitle: '来签订契约吧!精疲力竭的女子与爱照顾人的恶魔的同居生活',
        expectedEpisodeLabel: '第12话',
        expectedAuthor: '橋本ライドン',
      ),
      const ComicTitleParserCase(
        id: 'real_sample_final_episode',
        rawTitle: '【猫咪阳台】[嶋水えけ]憧憬的女仆与烟草相称-最终话',
        expectedNormalizedTitle: '憧憬的女仆与烟草相称',
        expectedEpisodeLabel: '最终话',
        // `猫咪阳台` 不带显式 `汉化/组` 后缀，按现有规则不归为 translation group；
        // 由 author 字段保留 last-bracket 语义记录 `嶋水えけ`。
        expectedAuthor: '嶋水えけ',
      ),
      const ComicTitleParserCase(
        id: 'html_amp_entity_is_decoded_in_normalized_title',
        rawTitle: '【提灯喵汉化组】[tMnR]无法传达的爱恋 完结番外－这份思念传达后的那线未来 &amp; 第七卷后记',
        expectedNormalizedTitle: '无法传达的爱恋',
        expectedTranslationGroup: '提灯喵汉化组',
        expectedAuthor: 'tMnR',
        expectedEpisodeLabel: '完结番外－这份思念传达后的那线未来 & 第七卷后记',
      ),
      const ComicTitleParserCase(
        id: 'volume_one_extra_keeps_original_episode_label',
        rawTitle: '【提灯喵汉化组】[梶川岳]爸爸的“玩”偶 第一卷番外',
        expectedNormalizedTitle: '爸爸的“玩”偶',
        expectedTranslationGroup: '提灯喵汉化组',
        expectedAuthor: '梶川岳',
        expectedEpisodeLabel: '第一卷番外',
      ),
      const ComicTitleParserCase(
        id: 'chapter_range_keeps_original_episode_label',
        rawTitle: '【个人汉化】[犬山あむ]大崎与小森 16~25话',
        expectedNormalizedTitle: '大崎与小森',
        expectedTranslationGroup: '个人汉化',
        expectedAuthor: '犬山あむ',
        expectedEpisodeLabel: '16~25话',
      ),
      const ComicTitleParserCase(
        id: 'numbered_subtitle_then_position_marker',
        rawTitle: '【提灯喵汉化组】[柴田康平]和魔女的吸活 09 魔女和变容 后篇',
        expectedNormalizedTitle: '和魔女的吸活',
        expectedTranslationGroup: '提灯喵汉化组',
        expectedAuthor: '柴田康平',
        expectedEpisodeLabel: '09 魔女和变容 后篇',
      ),
    ];

final List<ComicTitleRuleSummaryCase> stageOneComicTitleRuleSummaryCases =
    <ComicTitleRuleSummaryCase>[
      const ComicTitleRuleSummaryCase(
        id: 'strip_volume_marker',
        rawTitle: '[Scan] Comic Title Vol.2',
        targetSummary: 'strip volume or chapter markers from clean book name',
      ),
      const ComicTitleRuleSummaryCase(
        id: 'search_keyword_is_clean_book_name',
        rawTitle: '[Author][Group] Comic Title EP 2',
        targetSummary: 'keep searchKeyword equal to clean book name only',
      ),
      const ComicTitleRuleSummaryCase(
        id: 'extract_special_episode_number',
        rawTitle: 'Comic Title 番外',
        targetSummary:
            'map special episode markers to chapter number semantics',
      ),
    ];

/// petitparser-backed analyzer 直接消费的样本。每个样本都是真实漫画/合成漫画
/// 标题，覆盖：作者前缀、汉化组识别、章节标记（中/英/数字/特殊词）、章节修饰、
/// 搜索词长度裁剪、URL tid 提取等阶段 1 的 P0 规则。
final List<ComicTitleAnalyzerCase> stageOneComicTitleAnalyzerCases =
    <ComicTitleAnalyzerCase>[
      const ComicTitleAnalyzerCase(
        id: 'strip_brackets_and_volume_marker',
        rawTitle: '[Scan] Comic Title Vol.2',
        expectedCleanBookName: 'Comic Title',
        expectedSearchKeyword: 'Comic Title',
        expectedAuthorPrefix: null,
        expectedEpisodeLabel: 'Vol.2',
        expectedChapterNumber: 2,
        expectedPossibleChapterNumbers: <double>[2],
      ),
      const ComicTitleAnalyzerCase(
        id: 'author_prefix_ignores_translation_group',
        rawTitle: '[作者名][汉化组] 漫画标题 第2话上',
        expectedCleanBookName: '漫画标题',
        expectedSearchKeyword: '漫画标题',
        expectedAuthorPrefix: '作者名',
        expectedEpisodeLabel: '第2话上',
        expectedChapterNumber: 2.1,
        expectedPossibleChapterNumbers: <double>[2.1, 2],
      ),
      const ComicTitleAnalyzerCase(
        id: 'special_episode_maps_to_zero',
        rawTitle: 'Comic Title 番外',
        expectedCleanBookName: 'Comic Title',
        expectedSearchKeyword: 'Comic Title',
        expectedEpisodeLabel: '番外',
        expectedChapterNumber: 0,
        expectedPossibleChapterNumbers: <double>[0],
      ),
      const ComicTitleAnalyzerCase(
        id: 'final_episode_maps_to_999',
        rawTitle: 'Comic Title 最终话',
        expectedCleanBookName: 'Comic Title',
        expectedSearchKeyword: 'Comic Title',
        expectedEpisodeLabel: '最终话',
        expectedChapterNumber: 999,
        expectedPossibleChapterNumbers: <double>[999],
      ),
      const ComicTitleAnalyzerCase(
        id: 'circled_digit_becomes_decimal_suffix',
        rawTitle: 'Comic Title 第3话②',
        expectedCleanBookName: 'Comic Title',
        expectedSearchKeyword: 'Comic Title',
        expectedEpisodeLabel: '第3话②',
        expectedChapterNumber: 3.2,
        expectedPossibleChapterNumbers: <double>[3.2, 3],
      ),
      const ComicTitleAnalyzerCase(
        id: 'roman_numeral_episode',
        rawTitle: 'Comic Title EP IV',
        expectedCleanBookName: 'Comic Title',
        expectedSearchKeyword: 'Comic Title',
        expectedEpisodeLabel: 'EP4',
        expectedChapterNumber: 4,
        expectedPossibleChapterNumbers: <double>[4],
      ),
      const ComicTitleAnalyzerCase(
        id: 'full_width_digits_and_traditional_chapter_marker',
        rawTitle: '[漢化組]超級超級超級超級長的漫畫標題第１２話',
        expectedCleanBookName: '超級超級超級超級長的漫畫標題',
        expectedSearchKeyword: '超級超級超級超級長的漫畫標題',
        expectedAuthorPrefix: null,
        expectedEpisodeLabel: '第12话',
        expectedChapterNumber: 12,
        expectedPossibleChapterNumbers: <double>[12],
      ),
      // 真实样本：漫画区常见的“【汉化组】[作者]中文标题 第N话”格式。
      const ComicTitleAnalyzerCase(
        id: 'real_sample_translation_group_then_author_then_chapter',
        rawTitle: '【汉化工房九九组】[サンクス仮面]独行者们，青春挡不住！ 第1话',
        expectedCleanBookName: '独行者们，青春挡不住',
        expectedSearchKeyword: '独行者们，青春挡不住',
        expectedAuthorPrefix: 'サンクス仮面',
        expectedEpisodeLabel: '第1话',
        expectedChapterNumber: 1,
        expectedPossibleChapterNumbers: <double>[1],
      ),
      const ComicTitleAnalyzerCase(
        id: 'real_sample_chapter_followed_by_trailing_group',
        rawTitle: '【橋本ライドン】 来签订契约吧!精疲力竭的女子与爱照顾人的恶魔的同居生活 第12话 Kakukuroi汉化组',
        expectedCleanBookName: '来签订契约吧!精疲力竭的女子与爱照顾人的恶魔的同居生活',
        // 18 runes，超过裁剪阈值，按 Kotlin 行为截断成前 18 字符。
        expectedSearchKeyword: '来签订契约吧!精疲力竭的女子与爱照顾',
        expectedAuthorPrefix: '橋本ライドン',
        expectedEpisodeLabel: '第12话',
        expectedChapterNumber: 12,
        expectedPossibleChapterNumbers: <double>[12],
      ),
      const ComicTitleAnalyzerCase(
        id: 'real_sample_final_episode_with_separator',
        rawTitle: '【猫咪阳台】[嶋水えけ]憧憬的女仆与烟草相称-最终话',
        expectedCleanBookName: '憧憬的女仆与烟草相称',
        expectedSearchKeyword: '憧憬的女仆与烟草相称',
        expectedAuthorPrefix: '嶋水えけ',
        expectedEpisodeLabel: '最终话',
        expectedChapterNumber: 999,
        expectedPossibleChapterNumbers: <double>[999],
      ),
      const ComicTitleAnalyzerCase(
        id: 'real_sample_double_translation_group_with_chapter_dash_subnumber',
        rawTitle: '【绿茶汉化组×萌木汉化组】[波多ヒロ]青春新天地~机动战士高达：水星的魔女 第6-1话',
        // `第6-1话` 在阶段 1 第一批迁移中作为章节边界识别为 `第6`，
        // 后续阶段再扩展 `第X-Y` 子章节号。
        // analyzer 会先做 ASCII 半角化（`：`→`:`），所以清洗结果用半角冒号。
        expectedCleanBookName: '青春新天地~机动战士高达:水星的魔女',
        expectedSearchKeyword: '青春新天地~机动战士高达:水星的魔女',
        expectedAuthorPrefix: '波多ヒロ',
        expectedEpisodeLabel: '第6话',
        expectedChapterNumber: 6,
        expectedPossibleChapterNumbers: <double>[6],
      ),
      const ComicTitleAnalyzerCase(
        id: 'real_sample_trailing_plain_number',
        rawTitle: '【提灯喵汉化组】[ヒジキ]契约姐妹 28',
        expectedCleanBookName: '契约姐妹',
        expectedSearchKeyword: '契约姐妹',
        expectedAuthorPrefix: 'ヒジキ',
        expectedEpisodeLabel: '28',
        expectedChapterNumber: 28,
        expectedPossibleChapterNumbers: <double>[28],
      ),
      // 用户在阶段 1 反馈中提供的真实漫画标题，用来固定关键约束：
      //   - `~` 不再当作书名截断符，可以出现在书名内部和外缘。
      //   - `《...》/(...)/（...）` 等内嵌括号不再被当成前缀剥离。
      //   - `第N织` 这种非 `话/回/章` 章节单位也能识别。
      //   - 没有 `第` 但带章节单位的 `19话/16话/03话` 仍能识别为章节。
      //   - 章节正文里的 `19话（完结）`、`第08话 完结` 等尾巴会被章节边界截断。
      const ComicTitleAnalyzerCase(
        id: 'real_sample_final_episode_after_space',
        rawTitle: '【提灯喵汉化组】[鈴木先輩]半夜邻叫 最终话',
        expectedCleanBookName: '半夜邻叫',
        expectedSearchKeyword: '半夜邻叫',
        expectedAuthorPrefix: '鈴木先輩',
        expectedEpisodeLabel: '最终话',
        expectedChapterNumber: 999,
        expectedPossibleChapterNumbers: <double>[999],
      ),
      const ComicTitleAnalyzerCase(
        id: 'real_sample_trailing_padded_number',
        rawTitle: '【提灯喵汉化组】[水谷フーカ]以貌取我 01',
        expectedCleanBookName: '以貌取我',
        expectedSearchKeyword: '以貌取我',
        expectedAuthorPrefix: '水谷フーカ',
        expectedEpisodeLabel: '1',
        expectedChapterNumber: 1,
        expectedPossibleChapterNumbers: <double>[1],
      ),
      const ComicTitleAnalyzerCase(
        id: 'real_sample_inner_book_brackets_kept',
        rawTitle: '【牛肉汉化组】[언니]《我爱艾米》(나는에이미를사랑해) 第46话',
        // `《》/()` 不再当作前缀 bracket，因此原始书名（含中韩双语）保留。
        expectedCleanBookName: '《我爱艾米》(나는에이미를사랑해)',
        expectedSearchKeyword: '《我爱艾米》(나는에이미를사랑해)',
        expectedAuthorPrefix: '언니',
        expectedEpisodeLabel: '第46话',
        expectedChapterNumber: 46,
        expectedPossibleChapterNumbers: <double>[46],
      ),
      const ComicTitleAnalyzerCase(
        id: 'real_sample_bare_chapter_then_completion_tail',
        rawTitle: '【个人汉化】[あらた伊里] 也无风雨也无晴 19话（完结）',
        expectedCleanBookName: '也无风雨也无晴',
        expectedSearchKeyword: '也无风雨也无晴',
        expectedAuthorPrefix: 'あらた伊里',
        expectedEpisodeLabel: '第19话',
        expectedChapterNumber: 19,
        expectedPossibleChapterNumbers: <double>[19],
      ),
      const ComicTitleAnalyzerCase(
        id: 'real_sample_trailing_punct_then_plain_number',
        rawTitle: '【提灯喵汉化组】[矢坂しゅう]怎样才能成为发小的女友呢！？01',
        // 数字前的 `！？` 在 `_cleanupBookName` 的尾部标点剥离里被去掉。
        expectedCleanBookName: '怎样才能成为发小的女友呢',
        expectedSearchKeyword: '怎样才能成为发小的女友呢',
        expectedAuthorPrefix: '矢坂しゅう',
        expectedEpisodeLabel: '1',
        expectedChapterNumber: 1,
        expectedPossibleChapterNumbers: <double>[1],
      ),
      const ComicTitleAnalyzerCase(
        id: 'real_sample_zero_padded_chapter_with_completion_tail',
        rawTitle: '【一色汉化组】[とりいしづく]梦想和恋爱划算不来 第08话 完结',
        expectedCleanBookName: '梦想和恋爱划算不来',
        expectedSearchKeyword: '梦想和恋爱划算不来',
        expectedAuthorPrefix: 'とりいしづく',
        expectedEpisodeLabel: '第8话',
        expectedChapterNumber: 8,
        expectedPossibleChapterNumbers: <double>[8],
      ),
      const ComicTitleAnalyzerCase(
        id: 'real_sample_tilde_in_book_name_with_bare_chapter',
        rawTitle: '[汉化工房九九组][玉崎たま]无力圣女与无能王女 ~毫无魔力却被召唤的圣女的异世界救国记~ 16话「阿斯特拉」',
        // `~` 不再被截断或外缘剥离，整个副标题保留下来。
        expectedCleanBookName: '无力圣女与无能王女 ~毫无魔力却被召唤的圣女的异世界救国记~',
        // searchKeyword 取前 18 runes：`无力圣女与无能王女 ~毫无魔力却被召`。
        expectedSearchKeyword: '无力圣女与无能王女 ~毫无魔力却被召',
        expectedAuthorPrefix: '玉崎たま',
        expectedEpisodeLabel: '第16话',
        expectedChapterNumber: 16,
        expectedPossibleChapterNumbers: <double>[16],
      ),
      const ComicTitleAnalyzerCase(
        id: 'real_sample_chapter_after_chinese_comma_in_book',
        rawTitle: '【汉化工房九九组】[冬島暮]腹黑圣女和她捡来的兽耳邪神，今天也要一起惩治邪恶 第3话',
        expectedCleanBookName: '腹黑圣女和她捡来的兽耳邪神，今天也要一起惩治邪恶',
        // 26 runes，超过 18 字阈值。
        expectedSearchKeyword: '腹黑圣女和她捡来的兽耳邪神，今天也要',
        expectedAuthorPrefix: '冬島暮',
        expectedEpisodeLabel: '第3话',
        expectedChapterNumber: 3,
        expectedPossibleChapterNumbers: <double>[3],
      ),
      const ComicTitleAnalyzerCase(
        id: 'real_sample_special_extra_in_volume_label',
        rawTitle: '【提灯喵汉化组】[inee]LOVE·BULLET 二卷番外',
        expectedCleanBookName: 'LOVE·BULLET',
        expectedSearchKeyword: 'LOVE·BULLET',
        expectedAuthorPrefix: 'inee',
        expectedEpisodeLabel: '二卷番外',
        expectedChapterNumber: 2,
        expectedPossibleChapterNumbers: <double>[2],
      ),
      const ComicTitleAnalyzerCase(
        id: 'real_sample_chinese_numeral_with_zhi_chapter_unit',
        rawTitle: '【猫咪阳台】[sheepD]金丝雀渴望闪耀繁星-第十五织',
        // `织` 已加入章节单位字符集；`第十五` 走中文数字解析。
        expectedCleanBookName: '金丝雀渴望闪耀繁星',
        expectedSearchKeyword: '金丝雀渴望闪耀繁星',
        expectedAuthorPrefix: 'sheepD',
        expectedEpisodeLabel: '第15话',
        expectedChapterNumber: 15,
        expectedPossibleChapterNumbers: <double>[15],
      ),
      const ComicTitleAnalyzerCase(
        id: 'real_sample_chapter_with_trailing_punct_in_book',
        rawTitle: '【绿茶汉化组】[秋津貴央]小舞给大姐姐的投食日记。 第31话',
        expectedCleanBookName: '小舞给大姐姐的投食日记',
        expectedSearchKeyword: '小舞给大姐姐的投食日记',
        expectedAuthorPrefix: '秋津貴央',
        expectedEpisodeLabel: '第31话',
        expectedChapterNumber: 31,
        expectedPossibleChapterNumbers: <double>[31],
      ),
      const ComicTitleAnalyzerCase(
        id: 'real_sample_two_brackets_then_bare_chapter',
        rawTitle: '[汉化工房九九组][相崎うたう]可爱会毁灭一切 03话',
        expectedCleanBookName: '可爱会毁灭一切',
        expectedSearchKeyword: '可爱会毁灭一切',
        expectedAuthorPrefix: '相崎うたう',
        expectedEpisodeLabel: '第3话',
        expectedChapterNumber: 3,
        expectedPossibleChapterNumbers: <double>[3],
      ),
      const ComicTitleAnalyzerCase(
        id: 'real_sample_two_brackets_then_padded_trailing_number',
        rawTitle: '【提灯喵汉化组】[つづら涼]妈妈和女儿 01',
        expectedCleanBookName: '妈妈和女儿',
        expectedSearchKeyword: '妈妈和女儿',
        expectedAuthorPrefix: 'つづら涼',
        expectedEpisodeLabel: '1',
        expectedChapterNumber: 1,
        expectedPossibleChapterNumbers: <double>[1],
      ),
      const ComicTitleAnalyzerCase(
        id: 'real_sample_kana_author_then_chapter',
        rawTitle: '【一色汉化组】[シクシク]茉梦之歌 第5话',
        expectedCleanBookName: '茉梦之歌',
        expectedSearchKeyword: '茉梦之歌',
        expectedAuthorPrefix: 'シクシク',
        expectedEpisodeLabel: '第5话',
        expectedChapterNumber: 5,
        expectedPossibleChapterNumbers: <double>[5],
      ),
      const ComicTitleAnalyzerCase(
        id: 'real_sample_no_chapter_marker',
        rawTitle: '【绿茶汉化组】[夏村東和]憧憬随冬意渐浓',
        // 没有任何章节标记 → cleanBookName 为正文剩余部分，章节字段保持空。
        expectedCleanBookName: '憧憬随冬意渐浓',
        expectedSearchKeyword: '憧憬随冬意渐浓',
        expectedAuthorPrefix: '夏村東和',
        expectedEpisodeLabel: null,
        expectedChapterNumber: null,
        expectedPossibleChapterNumbers: <double>[],
      ),
      const ComicTitleAnalyzerCase(
        id: 'real_sample_html_amp_entity_is_decoded',
        rawTitle: '【提灯喵汉化组】[tMnR]无法传达的爱恋 完结番外－这份思念传达后的那线未来 &amp; 第七卷后记',
        expectedCleanBookName: '无法传达的爱恋',
        expectedSearchKeyword: '无法传达的爱恋',
        expectedAuthorPrefix: 'tMnR',
        expectedEpisodeLabel: '完结番外－这份思念传达后的那线未来 & 第七卷后记',
        expectedChapterNumber: 0,
        expectedPossibleChapterNumbers: <double>[0],
      ),
      // ========== 新增测试用例：episodeLabel 保留原始文本 ==========
      const ComicTitleAnalyzerCase(
        id: 'real_sample_trailing_number_then_position_marker',
        rawTitle: '[辰砂汉化][五十嵐純]致彼时繁花05 后篇',
        expectedCleanBookName: '致彼时繁花',
        expectedSearchKeyword: '致彼时繁花',
        expectedAuthorPrefix: '五十嵐純',
        expectedEpisodeLabel: '05 后篇',
        expectedChapterNumber: 5,
        expectedPossibleChapterNumbers: <double>[5],
      ),
      const ComicTitleAnalyzerCase(
        id: 'real_sample_volume_appendix_marker',
        rawTitle: '[汉化工房九九组][冬島暮]发小的异常可爱的妹妹 03卷附录',
        expectedCleanBookName: '发小的异常可爱的妹妹',
        expectedSearchKeyword: '发小的异常可爱的妹妹',
        expectedAuthorPrefix: '冬島暮',
        expectedEpisodeLabel: '03卷附录',
        expectedChapterNumber: 3,
        expectedPossibleChapterNumbers: <double>[3],
      ),
      const ComicTitleAnalyzerCase(
        id: 'real_sample_paren_subtitle_then_ordinal',
        rawTitle: '[百合會][murata]私の拳を受け止めて！（請接受我這一拳！）第一拳',
        expectedCleanBookName: '私の拳を受け止めて！（請接受我這一拳！）',
        expectedSearchKeyword: '私の拳を受け止めて！（請接受我這一拳',
        expectedAuthorPrefix: 'murata',
        expectedEpisodeLabel: '第一拳',
        expectedChapterNumber: 1,
        expectedPossibleChapterNumbers: <double>[1],
      ),
      const ComicTitleAnalyzerCase(
        id: 'real_sample_short_story_prefix_with_position',
        rawTitle: '【汉化工房九九组】[バリキオス]驱魔天使 前篇',
        expectedCleanBookName: '驱魔天使',
        expectedSearchKeyword: '驱魔天使',
        expectedAuthorPrefix: 'バリキオス',
        expectedEpisodeLabel: '前篇',
        expectedChapterNumber: 0,
        expectedPossibleChapterNumbers: <double>[0],
      ),
      const ComicTitleAnalyzerCase(
        id: 'real_sample_volume_prefix_special_greedy',
        rawTitle: '【提灯喵汉化组】[inee]LOVE·BULLET 二卷番外',
        expectedCleanBookName: 'LOVE·BULLET',
        expectedSearchKeyword: 'LOVE·BULLET',
        expectedAuthorPrefix: 'inee',
        expectedEpisodeLabel: '二卷番外',
        expectedChapterNumber: 2,
        expectedPossibleChapterNumbers: <double>[2],
      ),
      const ComicTitleAnalyzerCase(
        id: 'real_sample_personal_translation_no_author',
        rawTitle: '【个人汉化】茉梦之歌 1卷蜜瓜特典番外',
        expectedCleanBookName: '茉梦之歌',
        expectedSearchKeyword: '茉梦之歌',
        expectedAuthorPrefix: null,
        expectedEpisodeLabel: '1卷蜜瓜特典番外',
        expectedChapterNumber: 1,
        expectedPossibleChapterNumbers: <double>[1],
      ),
      const ComicTitleAnalyzerCase(
        id: 'real_sample_short_story_double_bracket_position_lower',
        rawTitle: '[短篇]【个人汉化】[碇理界] ハムスター大作戦（仓鼠大作战）下篇',
        expectedCleanBookName: 'ハムスター大作戦（仓鼠大作战）',
        expectedSearchKeyword: 'ハムスター大作戦（仓鼠大作战）',
        expectedAuthorPrefix: '碇理界',
        expectedEpisodeLabel: '下篇',
        expectedChapterNumber: 0,
        expectedPossibleChapterNumbers: <double>[0],
      ),
      const ComicTitleAnalyzerCase(
        id: 'real_sample_short_story_double_bracket_position_middle',
        rawTitle: '[短篇]【个人汉化】[碇理界] ハムスター大作戦（仓鼠大作战）中篇',
        expectedCleanBookName: 'ハムスター大作戦（仓鼠大作战）',
        expectedSearchKeyword: 'ハムスター大作戦（仓鼠大作战）',
        expectedAuthorPrefix: '碇理界',
        expectedEpisodeLabel: '中篇',
        expectedChapterNumber: 0,
        expectedPossibleChapterNumbers: <double>[0],
      ),
      const ComicTitleAnalyzerCase(
        id: 'real_sample_volume_one_extra',
        rawTitle: '【提灯喵汉化组】[梶川岳]爸爸的“玩”偶 第一卷番外',
        expectedCleanBookName: '爸爸的“玩”偶',
        expectedSearchKeyword: '爸爸的“玩”偶',
        expectedAuthorPrefix: '梶川岳',
        expectedEpisodeLabel: '第一卷番外',
        expectedChapterNumber: 1,
        expectedPossibleChapterNumbers: <double>[1],
      ),
      const ComicTitleAnalyzerCase(
        id: 'real_sample_chapter_range',
        rawTitle: '【个人汉化】[犬山あむ]大崎与小森 16~25话',
        expectedCleanBookName: '大崎与小森',
        expectedSearchKeyword: '大崎与小森',
        expectedAuthorPrefix: '犬山あむ',
        expectedEpisodeLabel: '16~25话',
        expectedChapterNumber: 16,
        expectedPossibleChapterNumbers: <double>[16, 25],
      ),
      const ComicTitleAnalyzerCase(
        id: 'real_sample_numbered_subtitle_then_position_marker',
        rawTitle: '【提灯喵汉化组】[柴田康平]和魔女的吸活 09 魔女和变容 后篇',
        expectedCleanBookName: '和魔女的吸活',
        expectedSearchKeyword: '和魔女的吸活',
        expectedAuthorPrefix: '柴田康平',
        expectedEpisodeLabel: '09 魔女和变容 后篇',
        expectedChapterNumber: 9,
        expectedPossibleChapterNumbers: <double>[9],
      ),
    ];
