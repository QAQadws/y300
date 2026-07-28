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
      simplified.librarySelectionActionAssignCategory,
    );
    expect(
      SelectionActionTextResolver.label(
        traditional,
        SelectionActionIds.unfavorite,
      ),
      traditional.librarySelectionActionUnfavorite,
    );
    expect(
      SelectionActionTextResolver.label(simplified, 'unknown-action'),
      simplified.librarySelectionActionGeneric,
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
        const SelectionActionOutcome(
          code: SelectionActionOutcomeCode.success,
          changed: true,
          succeededCount: 3,
        ),
      ),
      simplified.librarySelectionCategoryAssigned(3),
    );
    expect(
      SelectionActionTextResolver.resultMessage(
        traditional,
        SelectionActionIds.unfavorite,
        const SelectionActionOutcome(
          code: SelectionActionOutcomeCode.partialFailure,
          changed: true,
          succeededCount: 2,
          failedCount: 1,
        ),
      ),
      traditional.librarySelectionUnfavoritePartial(2, 1),
    );
    expect(
      SelectionActionTextResolver.resultMessage(
        simplified,
        SelectionActionIds.download,
        const SelectionActionOutcome(
          code: SelectionActionOutcomeCode.noChange,
          deduplicatedCount: 2,
        ),
      ),
      simplified.librarySelectionDownloadAlreadyQueued,
    );
    expect(
      SelectionActionTextResolver.resultMessage(
        simplified,
        SelectionActionIds.assignCategory,
        const SelectionActionOutcome(
          code: SelectionActionOutcomeCode.unsupported,
        ),
      ),
      simplified.librarySelectionUnsupported(
        simplified.librarySelectionActionAssignCategory,
      ),
    );
  });

  test('includes counts in partial read and download results', () {
    expect(
      SelectionActionTextResolver.resultMessage(
        simplified,
        SelectionActionIds.markAllRead,
        const SelectionActionOutcome(
          code: SelectionActionOutcomeCode.partialFailure,
          succeededCount: 2,
          failedCount: 1,
        ),
      ),
      simplified.librarySelectionReadStateChangedPartial(
        2,
        1,
        simplified.librarySelectionRead,
      ),
    );
    expect(
      SelectionActionTextResolver.resultMessage(
        traditional,
        SelectionActionIds.download,
        const SelectionActionOutcome(
          code: SelectionActionOutcomeCode.partialFailure,
          enqueuedCount: 3,
          failedCount: 1,
        ),
      ),
      traditional.librarySelectionDownloadQueuedPartial(3, 1),
    );
  });
}
