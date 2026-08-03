import 'package:y300/features/cache/domain/models/image_cache_models.dart';

/// 图片保留等级的**单一分类来源**。
///
/// 背景：保留等级此前散落在各 request 构造器里手写，容易出现同类图片分类不一致
/// （例如轮播图/版块顶部图被错标为 ephemeral）。本分类器把“某 role 默认属于哪一
/// 保留等级”收敛到一处，落实《图片与列表加载性能优化方案》的三分原则：
///
/// - **资产（protected）**：用户拥有、丢失即数据丢失。封面、自定义封面。
///   （已下载章节图在下载时单独标 downloaded，不经本默认分类。）
/// - **长期缓存（sticky）**：可再生但复用率高、需要稳定存在与更新。表情、
///   论坛轮播图/版块顶部图、版块图标。普通清理默认保留。
/// - **可清缓存（ephemeral）**：偶发浏览、丢了重下即可。帖子正文图/附件、头像、
///   博客正文图、在线浏览的漫画/小说图。容量压力下优先淘汰。
///
/// 注意：这是“按 role 的默认值”。调用方仍可在特殊场景显式覆盖（如阅读会话把
/// 帖子图升级为 recentReader、下载升级为 downloaded）。
abstract final class ImageRetentionClassifier {
  static ImageRetentionClass defaultFor(ImageCacheRole role) {
    switch (role) {
      case ImageCacheRole.cover:
      case ImageCacheRole.customCover:
        return ImageRetentionClass.protected;
      case ImageCacheRole.remoteSmiley:
      case ImageCacheRole.forumHeadImage:
      case ImageCacheRole.forumIcon:
        return ImageRetentionClass.sticky;
      case ImageCacheRole.threadInline:
      case ImageCacheRole.threadAttachment:
      case ImageCacheRole.avatar:
      case ImageCacheRole.blogInline:
      case ImageCacheRole.comicPage:
      case ImageCacheRole.novelInline:
      case ImageCacheRole.composerUnusedAttachment:
        return ImageRetentionClass.ephemeral;
    }
  }

  /// 是否属于“可清缓存”（普通一键清理会清掉的部分）。
  static bool isClearableByDefault(ImageCacheRole role) {
    return defaultFor(role) == ImageRetentionClass.ephemeral;
  }
}
