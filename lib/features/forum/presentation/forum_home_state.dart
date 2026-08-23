import 'package:y300/features/cache/domain/models/document_cache_models.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/forum/data/models/forum_home_chrome_models.dart';
import 'package:y300/features/forum/domain/repositories/forum_directory_repository.dart';

enum ForumSectionType { regular, favorite, uncategorized }

enum ForumHomeNoticeCode { refreshFailed }

class ForumHomeNotice {
  const ForumHomeNotice({required this.code, this.detail});

  final ForumHomeNoticeCode code;
  final String? detail;
}

class ForumHomeForumDisplayItem {
  const ForumHomeForumDisplayItem({
    required this.fid,
    required this.title,
    required this.description,
    required this.todayPosts,
  });

  final String fid;
  final String title;
  final String description;
  final int? todayPosts;
}

/// 论坛首页中一个可展示分组，通常对应一个分类
class ForumSection {
  const ForumSection({
    required this.sourceIdentity,
    required this.title,
    required this.items,
    this.type = ForumSectionType.regular,
  });

  /// Stable identity for presentation state; never use a converted title.
  final String sourceIdentity;
  final String title;
  final List<ForumHomeForumDisplayItem> items;
  final ForumSectionType type;
}

/// 首页渲染模型，避免页面直接依赖后端原始结构
class ForumHomeViewData {
  ForumHomeViewData({
    required this.sections,
    required this.isLoggedIn,
    this.carouselItems = const <ForumHomeCarouselItem>[],
  });

  final List<ForumSection> sections;
  final bool isLoggedIn;
  final List<ForumHomeCarouselItem> carouselItems;

  int get sectionCount => sections.length;

  int get regularForumCount => sections
      .where((section) => section.type == ForumSectionType.regular)
      .fold<int>(0, (sum, section) => sum + section.items.length);

  int get forumCount {
    final countedFids = <String>{};
    var count = 0;
    for (final section in sections) {
      for (final item in section.items) {
        if (countedFids.add(item.fid)) {
          count++;
        }
      }
    }
    return count;
  }
}

class ForumHomePageState {
  const ForumHomePageState({
    required this.viewData,
    required this.requestProfile,
    required this.isRefreshing,
    required this.lastUpdatedAt,
    this.capabilities,
    this.readMetadata,
    this.refreshNotice,
    @Deprecated('Use refreshNotice and presentation localization instead.')
    this.refreshHint,
  });

  final ForumHomeViewData viewData;
  final DocumentRequestProfile requestProfile;
  final bool isRefreshing;
  final DateTime lastUpdatedAt;
  final ForumDirectoryReadCapabilities? capabilities;
  final DataReadMetadata? readMetadata;

  final ForumHomeNotice? refreshNotice;

  @Deprecated('Use refreshNotice and presentation localization instead.')
  final String? refreshHint;

  bool supports(ForumDirectoryCapability capability) {
    return capabilities?.supports(capability) ?? false;
  }

  ForumHomePageState copyWith({
    ForumHomeViewData? viewData,
    DocumentRequestProfile? requestProfile,
    bool? isRefreshing,
    DateTime? lastUpdatedAt,
    ForumDirectoryReadCapabilities? capabilities,
    DataReadMetadata? readMetadata,
    ForumHomeNotice? refreshNotice,
    String? refreshHint,
    bool clearHint = false,
  }) {
    return ForumHomePageState(
      viewData: viewData ?? this.viewData,
      requestProfile: requestProfile ?? this.requestProfile,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      capabilities: capabilities ?? this.capabilities,
      readMetadata: readMetadata ?? this.readMetadata,
      refreshNotice: clearHint ? null : (refreshNotice ?? this.refreshNotice),
      refreshHint: clearHint ? null : (refreshHint ?? this.refreshHint),
    );
  }
}
