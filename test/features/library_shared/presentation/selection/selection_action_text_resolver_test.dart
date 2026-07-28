import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_selection_action_adapter.dart';
import 'package:y300/features/library_shared/presentation/selection/selection_action_text_resolver.dart';
import 'package:y300/l10n/app_localizations_zh.dart';

void main() {
  final simplified = AppLocalizationsZh();
  final traditional = AppLocalizationsZhTw();

  test('resolves stable action ids in both Chinese locales', () {
    expect(
      SelectionActionTextResolver.label(
        simplified,
        SelectionActionIds.assignCategory,
      ),
      simplified.startupSelectionActionAssignCategory,
    );
    expect(
      SelectionActionTextResolver.label(
        traditional,
        SelectionActionIds.unfavorite,
      ),
      traditional.startupSelectionActionUnfavorite,
    );
    expect(
      SelectionActionTextResolver.label(simplified, 'unknown-action'),
      simplified.startupSelectionActionGeneric,
    );
    expect(
      SelectionActionTextResolver.label(traditional, 'unknown-action'),
      isNot(contains('unknown-action')),
    );
  });

  test('resolves structured selection results without adapter UI text', () {
    expect(
      SelectionActionTextResolver.resultMessage(
        simplified,
        SelectionActionIds.assignCategory,
        const SelectionActionResult(
          code: SelectionActionResultCode.success,
          changed: true,
          succeededCount: 3,
        ),
      ),
      simplified.startupSelectionCategoryAssigned(3),
    );
    expect(
      SelectionActionTextResolver.resultMessage(
        traditional,
        SelectionActionIds.unfavorite,
        const SelectionActionResult(
          code: SelectionActionResultCode.partialFailure,
          changed: true,
          succeededCount: 2,
          failedCount: 1,
        ),
      ),
      traditional.startupSelectionUnfavoritePartial(2, 1),
    );
    expect(
      SelectionActionTextResolver.resultMessage(
        simplified,
        SelectionActionIds.download,
        const SelectionActionResult(
          code: SelectionActionResultCode.noChange,
          deduplicatedCount: 2,
        ),
      ),
      simplified.startupSelectionDownloadAlreadyQueued,
    );
    expect(
      SelectionActionTextResolver.resultMessage(
        simplified,
        SelectionActionIds.assignCategory,
        const SelectionActionResult(
          code: SelectionActionResultCode.unsupported,
        ),
      ),
      simplified.startupSelectionUnsupported(
        simplified.startupSelectionActionAssignCategory,
      ),
    );
  });

  test('keeps legacy result messages as a migration fallback', () {
    expect(
      SelectionActionTextResolver.resultMessage(
        simplified,
        SelectionActionIds.download,
        const SelectionActionResult(message: 'legacy result'),
      ),
      'legacy result',
    );
  });

  test('includes counts in partial read and download results', () {
    expect(
      SelectionActionTextResolver.resultMessage(
        simplified,
        SelectionActionIds.markAllRead,
        const SelectionActionResult(
          code: SelectionActionResultCode.partialFailure,
          succeededCount: 2,
          failedCount: 1,
        ),
      ),
      simplified.startupSelectionReadStateChangedPartial(
        2,
        1,
        simplified.startupSelectionRead,
      ),
    );
    expect(
      SelectionActionTextResolver.resultMessage(
        traditional,
        SelectionActionIds.download,
        const SelectionActionResult(
          code: SelectionActionResultCode.partialFailure,
          enqueuedCount: 3,
          failedCount: 1,
        ),
      ),
      traditional.startupSelectionDownloadQueuedPartial(3, 1),
    );
  });
}
