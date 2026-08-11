import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/navigation/main_navigation_settings.dart';
import 'package:y300/app/settings/app_appearance_settings.dart';
import 'package:y300/app/theme/app_theme_family.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';
import 'package:y300/features/forum/domain/models/forum_shell_mode.dart';
import 'package:y300/features/more/domain/models/about_app_info.dart';
import 'package:y300/features/more/presentation/data_storage_controller.dart';
import 'package:y300/features/more/presentation/more_text_resolver.dart';
import 'package:y300/l10n/app_localizations_zh.dart';

void main() {
  final l10n = AppLocalizationsZh();

  test('resolves theme and forum mode labels in the presentation layer', () {
    expect(
      MoreTextResolver.themeFamilyLabel(l10n, AppThemeFamily.moonWhite),
      '月白',
    );
    expect(
      MoreTextResolver.brightnessLabel(l10n, AppBrightnessPreference.light),
      '日间',
    );
    expect(
      MoreTextResolver.brightnessDescription(
        l10n,
        AppBrightnessPreference.system,
      ),
      '根据系统设置切换日间或夜间外观',
    );
    expect(
      MoreTextResolver.appearanceSummary(
        l10n,
        AppThemeFamily.warmPaper,
        AppBrightnessPreference.dark,
      ),
      '暖纸 · 夜间',
    );
    expect(
      MoreTextResolver.forumModeLabel(l10n, ForumShellMode.native),
      '解析模式',
    );
  });

  test('resolves navigation labels without a domain UI string', () {
    expect(
      MoreTextResolver.navigationLabel(l10n, MainShellDestination.more),
      '更多',
    );
  });

  test('maps stable storage descriptors to localized text', () {
    expect(
      MoreTextResolver.storageLabel(
        l10n,
        const StorageUsageLabelRef(
          kind: StorageUsageLabelKind.imageRole,
          code: 'thread_inline',
          qualifier: 'downloaded',
        ),
      ),
      '帖子图片（已下载）',
    );
    expect(
      MoreTextResolver.storageLabel(
        l10n,
        const StorageUsageLabelRef(
          kind: StorageUsageLabelKind.imageRole,
          code: 'composer_unused_attachment',
          qualifier: 'ephemeral',
        ),
      ),
      '未使用上传图片',
    );
    expect(
      MoreTextResolver.storageLabel(
        l10n,
        const StorageUsageLabelRef(
          kind: StorageUsageLabelKind.historyKind,
          code: 'entries',
          count: 12,
        ),
      ),
      '浏览记录：12',
    );
  });

  test(
    'resolves version and notice parameters without storing localized text',
    () {
      expect(
        MoreTextResolver.aboutVersion(
          l10n,
          const AboutAppInfo(version: '1.2.3', buildNumber: '45'),
        ),
        '版本 1.2.3 (45)',
      );
      expect(
        MoreTextResolver.storageNotice(
          l10n,
          const DataStorageNotice(
            code: DataStorageNoticeCode.diagnosticsExported,
            path: 'C:/diagnostics.json',
          ),
        ),
        '缓存诊断已导出：C:/diagnostics.json',
      );
    },
  );
}
