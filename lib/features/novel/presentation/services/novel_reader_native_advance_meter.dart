import '../models/novel_reader_native_page_work.dart';

/// Constant-space accounting for one page phase. It retains no samples,
/// native resources, clocks or callbacks; the caller measures its existing call.
final class NovelReaderNativeAdvanceMeter {
  NovelReaderNativeAdvanceMeter({required Duration budget})
    : _budgetUs = budget.inMicroseconds {
    if (_budgetUs <= 0) throw ArgumentError.value(budget, 'budget');
  }
  final int _budgetUs;
  int _steps = 0;
  int _totalUs = 0;
  int _maxUs = 0;
  int _overBudgetSteps = 0;

  void record(int elapsedUs) {
    if (elapsedUs < 0) throw ArgumentError.value(elapsedUs, 'elapsedUs');
    _steps++;
    _totalUs += elapsedUs;
    if (elapsedUs > _maxUs) _maxUs = elapsedUs;
    if (elapsedUs > _budgetUs) _overBudgetSteps++;
  }

  NovelReaderNativeAdvanceWork get snapshot => NovelReaderNativeAdvanceWork(
    budgetUs: _budgetUs,
    steps: _steps,
    totalUs: _totalUs,
    maxUs: _maxUs,
    overBudgetSteps: _overBudgetSteps,
  );
}
