/// Canonical novel title inputs shared by pure policy and App integration tests.
library;

class NovelTitleFixture {
  const NovelTitleFixture({
    required this.id,
    required this.raw,
    required this.expectedSanitized,
    this.note,
  });

  /// 用作 group 标签和 expect reason 的简短稳定标识。
  final String id;

  /// 原始论坛标题（可能带 &amp;、前导括号 token）。
  final String raw;

  /// 经过 NovelTitleSanitizer.sanitize 后预期得到的标题。
  final String expectedSanitized;

  /// 给 reviewer 的解释，便于以后维护。
  final String? note;
}

class NovelChapterTitleCase {
  const NovelChapterTitleCase({
    required this.id,
    required this.normalizedCandidate,
    required this.expectedTitle,
  });

  final String id;
  final String normalizedCandidate;
  final String expectedTitle;
}

/// The HTML source associated with this candidate stays in the App fixture.
const decimalActNumberAfterEditNoticeFixture = NovelChapterTitleCase(
  id: 'decimal-act-number-after-edit-notice',
  normalizedCandidate: 'ACT13.5 现实中真的会发生这种事吗？',
  expectedTitle: 'ACT13.5 现实中真的会发生这种事吗？',
);

const novelChapterTitleCases = <NovelChapterTitleCase>[
  decimalActNumberAfterEditNoticeFixture,
];

/// 用户在 2026-06-15 提供的样例 + 常见边界。
const novelTitleFixtures = <NovelTitleFixture>[
  NovelTitleFixture(
    id: 'zhafan-yachitsu',
    raw: '[渣翻] （やちつ）醉酒上床的对象竟是前女友（2026.6.15 更新 第22话）',
    expectedSanitized: '（やちつ）醉酒上床的对象竟是前女友（2026.6.15 更新 第22话）',
    note: '一个前导方括号；全角圆括号包裹的译者名应当保留',
  ),
  NovelTitleFixture(
    id: 'haneda-uka',
    raw:
        '[个人翻译][长篇][羽田宇佐]一周一次买下同班同学的那些事'
        '（2026.6.14更新至第420话）',
    expectedSanitized: '一周一次买下同班同学的那些事（2026.6.14更新至第420话）',
    note: '三连前导方括号都应剥掉',
  ),
  NovelTitleFixture(
    id: 'rino-yimei',
    raw:
        '【個人翻譯】【莉乃】單戀的同班同學成了我的義妹'
        '(2026.6.15更新至第12話)',
    expectedSanitized: '單戀的同班同學成了我的義妹(2026.6.15更新至第12話)',
    note: '中文方头括号也要识别',
  ),
  NovelTitleFixture(
    id: 'shimaino-yuriskiy',
    raw: '[个人渣翻][シマイノ＝ユリスキー]总觉得妹妹的距离很近(全56话完结)',
    expectedSanitized: '总觉得妹妹的距离很近(全56话完结)',
  ),
  NovelTitleFixture(
    id: 'inukai-anzu',
    raw:
        '【自翻】【文庫版】【犬甘あんず】敗給了性格惡劣的天才青梅，'
        '初體驗全部被奪走這件事 第四卷 【完結】',
    expectedSanitized:
        '敗給了性格惡劣的天才青梅，初體驗全部被奪走這件事 '
        '第四卷 【完結】',
    note: '尾部的【完結】不能被剥掉，只剥前导三个【...】',
  ),
  // ↓ 用户在 2026-06-15 二轮提供的样例：含全角方括号 ［］ (U+FF3B/U+FF3D)。
  NovelTitleFixture(
    id: 'harukawa-rei',
    raw:
        '［搬运+翻译］［春川　レイ］ 转生女仆，但大小姐的样子有点怪 '
        '10.2更新至番外6',
    expectedSanitized: '转生女仆，但大小姐的样子有点怪 10.2更新至番外6',
    note: '两个前导全角方括号；译者名内含全角空格 U+3000 也要正常剥掉',
  ),
  NovelTitleFixture(
    id: 'feng-fen',
    raw: '【翻译】［风-フェン-］爱意复杂化（6.30更新番外11）（完结）',
    expectedSanitized: '爱意复杂化（6.30更新番外11）（完结）',
    note: '中文方头 + 全角方括号混合前导；正文里的（）必须保留',
  ),
  NovelTitleFixture(
    id: '4ka-chigusa',
    raw:
        '［自译］［4kaえんぴつ/千種みのり］【完结】【单行本已发售】'
        '来购买成人用品的优等生1上（2026/2/28番外③）',
    expectedSanitized: '来购买成人用品的优等生1上（2026/2/28番外③）',
    note:
        '四个前导括号（2 全角 + 2 中文方头）全剥；'
        '前导【完结】可以剥，但与 inukai-anzu 末尾【完結】对照：只剥前导。',
  ),
];

/// Existing sanitizer boundary cases, separate from the supplied title corpus.
const novelTitleEdgeFixtures = <NovelTitleFixture>[
  NovelTitleFixture(
    id: 'empty-title',
    raw: '',
    expectedSanitized: '',
    note: '空字符串原样返回',
  ),
  NovelTitleFixture(
    id: 'whitespace-only',
    raw: '   \t  ',
    expectedSanitized: '',
    note: '仅空白返回空',
  ),
  NovelTitleFixture(
    id: 'already-clean',
    raw: '一周一次买下同班同学的那些事',
    expectedSanitized: '一周一次买下同班同学的那些事',
    note: '已清洗的标题不再变化',
  ),
  NovelTitleFixture(
    id: 'amp-entity',
    raw: 'Foo &amp; Bar',
    expectedSanitized: 'Foo & Bar',
    note: '&amp; 实体解码为 &',
  ),
  NovelTitleFixture(
    id: 'entity-in-leading-token',
    raw: '[A&amp;B]Title',
    expectedSanitized: 'Title',
    note: '解码后剥前导括号',
  ),
  NovelTitleFixture(
    id: 'brackets-in-body',
    raw: '[漢化]内文 [注释] 结尾',
    expectedSanitized: '内文 [注释] 结尾',
    note: '只剥前导，正文中的方括号保留',
  ),
  NovelTitleFixture(
    id: 'mixed-leading-brackets',
    raw: '【组】[人]Title',
    expectedSanitized: 'Title',
    note: '混搭中文和英文括号都被剥',
  ),
  NovelTitleFixture(
    id: 'stop-at-first-body-token',
    raw: '[A]Body[B]',
    expectedSanitized: 'Body[B]',
    note: '遇到第一个非括号 token 立即停止剥离',
  ),
  NovelTitleFixture(
    id: 'unclosed-leading-bracket',
    raw: '[未闭合标题正文',
    expectedSanitized: '[未闭合标题正文',
    note: '括号未闭合时不会越界吞内容',
  ),
];
