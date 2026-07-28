import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/presentation/services/library_detail_text_resolver.dart';
import 'package:y300/features/library_shared/presentation/services/library_error_summary.dart';
import 'package:y300/features/library_shared/presentation/services/library_shelf_text_resolver.dart';
import 'package:y300/features/library_shared/presentation/services/library_task_text_resolver.dart';
import 'package:y300/l10n/app_localizations_zh.dart';

void main() {
  final simplified = AppLocalizationsZh();
  final traditional = AppLocalizationsZhTw();

  group('LibraryShelfTextResolver', () {
    test('localizes module, default category, and every sort field', () {
      expect(
        LibraryShelfTextResolver.moduleTitle(
          simplified,
          LibraryModuleKey.comic,
        ),
        '漫画',
      );
      expect(
        LibraryShelfTextResolver.moduleTitle(
          traditional,
          LibraryModuleKey.comic,
        ),
        '漫畫',
      );
      final defaultCategory = LibraryCategory(
        categoryId: 'default',
        name: 'Stored Default Name',
        sortOrder: 0,
        createdAt: DateTime(2026),
      );
      expect(
        LibraryShelfTextResolver.categoryName(simplified, defaultCategory),
        simplified.libraryShelfDefaultCategory,
      );
      for (final field in LibraryShelfSortField.values) {
        expect(
          LibraryShelfTextResolver.sortField(simplified, field),
          isNotEmpty,
          reason: field.name,
        );
        expect(
          LibraryShelfTextResolver.sortField(traditional, field),
          isNotEmpty,
          reason: field.name,
        );
      }
    });

    test('keeps a custom category name byte-for-byte unchanged', () {
      const rawName = 'Raw 分类名稱 01';
      final category = LibraryCategory(
        categoryId: 'custom-1',
        name: rawName,
        sortOrder: 1,
        createdAt: DateTime(2026),
      );

      expect(
        LibraryShelfTextResolver.categoryName(simplified, category),
        rawName,
      );
      expect(
        LibraryShelfTextResolver.categoryName(traditional, category),
        rawName,
      );
    });
  });

  group('LibraryDetailTextResolver', () {
    test('localizes structured refresh counts in both locales', () {
      final result = DetailRefreshResult.chaptersChanged(
        insertedCount: 1,
        updatedCount: 2,
      );

      expect(
        LibraryDetailTextResolver.refreshOutcome(simplified, result),
        simplified.libraryDetailRefreshChaptersChanged(1, 2),
      );
      expect(
        LibraryDetailTextResolver.refreshOutcome(traditional, result),
        traditional.libraryDetailRefreshChaptersChanged(1, 2),
      );
    });

    test('keeps raw chapter titles and hosts unchanged', () {
      const rawTitle = 'Raw 章節标题 EP.7';
      expect(
        LibraryDetailTextResolver.chapterTitle(traditional, rawTitle, '571564'),
        rawTitle,
      );

      const host = 'bbs.yamibo.com';
      const outcome = DetailManualChapterAddOutcome(
        code: DetailManualChapterAddOutcomeCode.invalidInput,
        inputErrorCode: DetailManualChapterInputErrorCode.unexpectedHost,
        expectedHost: host,
      );
      expect(
        LibraryDetailTextResolver.manualChapterInputError(traditional, outcome),
        contains(host),
      );
    });

    test('maps structured chapter progress without storing UI labels', () {
      const progress = LibraryChapterProgressInfo(
        kind: LibraryChapterProgressKind.currentPage,
        isCurrent: true,
        currentPage: 3,
        totalPages: 12,
        fraction: 0.25,
      );

      expect(
        LibraryDetailTextResolver.chapterProgress(simplified, progress),
        simplified.libraryChapterCurrentPageOfTotal(3, 12),
      );
      expect(
        LibraryDetailTextResolver.chapterProgress(traditional, progress),
        traditional.libraryChapterCurrentPageOfTotal(3, 12),
      );
    });
  });

  group('LibraryTaskTextResolver', () {
    test('localizes task status while preserving the raw subject', () {
      const rawSubject = '  Raw Server 标题 09  ';
      const progress = LibraryShelfTaskProgress(
        code: LibraryShelfTaskProgressCode.comicSearchWaiting,
        subject: rawSubject,
        estimatedDuration: Duration(milliseconds: 10500),
      );

      final simplifiedText = LibraryTaskTextResolver.message(
        simplified,
        progress,
      );
      final traditionalText = LibraryTaskTextResolver.message(
        traditional,
        progress,
      );
      expect(simplifiedText, contains(rawSubject));
      expect(traditionalText, contains(rawSubject));
      expect(simplifiedText, contains('11 秒'));
      expect(traditionalText, contains('11 秒'));
    });
  });

  group('LibraryErrorSummary', () {
    test('redacts links and complete secret values on one line', () {
      const raw =
          'failed https://secret.test/path?x=1 '
          'formhash=fh-secret uploadHash=up-secret\n'
          'Cookie: sid=session-secret; auth=auth-secret';

      final resolved = LibraryErrorSummary.resolve(simplified, raw);

      expect(resolved, contains(simplified.libraryErrorRedactedLink));
      expect(resolved, contains(simplified.libraryErrorRedactedSecret));
      expect(resolved, isNot(contains('secret.test')));
      expect(resolved, isNot(contains('fh-secret')));
      expect(resolved, isNot(contains('up-secret')));
      expect(resolved, isNot(contains('session-secret')));
      expect(resolved, isNot(contains('auth-secret')));
      expect(resolved, isNot(contains('\n')));
    });

    test('limits the final summary to 160 Unicode code points', () {
      final resolved = LibraryErrorSummary.resolve(
        traditional,
        List<String>.filled(200, '错').join(),
      );

      expect(resolved.runes.length, LibraryErrorSummary.maxLength);
      expect(resolved, endsWith('...'));
    });
  });
}
