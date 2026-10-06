typedef ComicDuplicateMetadataFixture = ({String title, String? author});

const comicInteractionThreadTitle = '漫画互动测试';

const comicDuplicateMetadataBase = (title: '漫画标题', author: '作者名');
const comicDuplicateMetadataOther = (title: '另一部漫画', author: '另一位作者');
const comicDuplicateMetadataFormatted = (
  title: '  Ｃｏｍｉｃ　　Ｔｉｔｌｅ &amp; Friends  ',
  author: ' Ａｕｔｈｏｒ　 Ｎａｍｅ ',
);
const comicDuplicateMetadataPlain = (
  title: 'Comic Title & Friends',
  author: 'Author Name',
);

/// Duplicate matching consumes saved book names, not raw chapter subjects.
const comicDuplicateMetadataCases =
    <
      ({
        String id,
        ComicDuplicateMetadataFixture left,
        ComicDuplicateMetadataFixture right,
        bool matches,
      })
    >[
      (
        id: 'same title and author',
        left: comicDuplicateMetadataBase,
        right: comicDuplicateMetadataBase,
        matches: true,
      ),
      (
        id: 'normalizes whitespace fullwidth variants and entities',
        left: comicDuplicateMetadataFormatted,
        right: comicDuplicateMetadataPlain,
        matches: true,
      ),
      (
        id: 'same title with different authors',
        left: comicDuplicateMetadataBase,
        right: (title: '漫画标题', author: '另一位作者'),
        matches: false,
      ),
      (
        id: 'same author with different titles',
        left: comicDuplicateMetadataBase,
        right: (title: '另一部漫画', author: '作者名'),
        matches: false,
      ),
      (
        id: 'one author missing',
        left: comicDuplicateMetadataBase,
        right: (title: '漫画标题', author: null),
        matches: false,
      ),
      (
        id: 'both authors missing',
        left: (title: '漫画标题', author: null),
        right: (title: '漫画标题', author: null),
        matches: false,
      ),
      (
        id: 'whitespace authors are missing',
        left: (title: '漫画标题', author: ' \t '),
        right: (title: '漫画标题', author: '　'),
        matches: false,
      ),
      (
        id: 'one title missing',
        left: comicDuplicateMetadataBase,
        right: (title: '', author: '作者名'),
        matches: false,
      ),
      (
        id: 'both titles missing',
        left: (title: '', author: '作者名'),
        right: (title: '　\t', author: '作者名'),
        matches: false,
      ),
      (
        id: 'title case is significant',
        left: comicDuplicateMetadataPlain,
        right: (title: 'comic title & friends', author: 'Author Name'),
        matches: false,
      ),
      (
        id: 'author case is significant',
        left: comicDuplicateMetadataPlain,
        right: (title: 'Comic Title & Friends', author: 'author name'),
        matches: false,
      ),
      (
        id: 'traditional title is distinct',
        left: comicDuplicateMetadataBase,
        right: (title: '漫畫標題', author: '作者名'),
        matches: false,
      ),
      (
        id: 'traditional author is distinct',
        left: (title: '漫画标题', author: '桥本'),
        right: (title: '漫画标题', author: '橋本'),
        matches: false,
      ),
      (
        id: 'full long names distinguish identical search prefixes',
        left: (title: '这是一个超过十八个字符而且前半部分完全相同的标题甲', author: '作者名'),
        right: (title: '这是一个超过十八个字符而且前半部分完全相同的标题乙', author: '作者名'),
        matches: false,
      ),
      (
        id: 'saved names are not reparsed as chapter subjects',
        left: (title: '漫画标题 第1话', author: '作者名'),
        right: (title: '漫画标题 第2话', author: '作者名'),
        matches: false,
      ),
      (
        id: 'internal spaces and punctuation are significant',
        left: (title: 'Comic-Title', author: 'Author Name'),
        right: (title: 'Comic Title', author: 'AuthorName'),
        matches: false,
      ),
      (
        id: 'metadata components cannot collide through a delimiter',
        left: (title: 'Title|Author', author: 'Name'),
        right: (title: 'Title', author: 'Author|Name'),
        matches: false,
      ),
    ];

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
        id: 'bare_chapter_range_maps_group_author_and_source_label',
        rawTitle: '【星愿汉化组】【らる・ぶらん】魔法少女与前邪恶女干部 15-16',
        expectedNormalizedTitle: '魔法少女与前邪恶女干部',
        expectedTranslationGroup: '星愿汉化组',
        expectedAuthor: 'らる・ぶらん',
        expectedEpisodeLabel: '15-16',
      ),
      const ComicTitleParserCase(
        id: 'numbered_subtitle_then_position_marker',
        rawTitle: '【提灯喵汉化组】[柴田康平]和魔女的吸活 09 魔女和变容 后篇',
        expectedNormalizedTitle: '和魔女的吸活',
        expectedTranslationGroup: '提灯喵汉化组',
        expectedAuthor: '柴田康平',
        expectedEpisodeLabel: '09 魔女和变容 后篇',
      ),
      const ComicTitleParserCase(
        id: 'real_sample_chapter_with_trailing_punct_in_book',
        rawTitle: '【绿茶汉化组】[秋津貴央]小舞给大姐姐的投食日记。 第31话',
        expectedNormalizedTitle: '小舞给大姐姐的投食日记',
        expectedTranslationGroup: '绿茶汉化组',
        expectedAuthor: '秋津貴央',
        expectedEpisodeLabel: '第31话',
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
