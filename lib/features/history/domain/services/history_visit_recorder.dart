import 'package:y300/features/history/domain/models/history_models.dart';

abstract interface class HistoryVisitRecorder {
  Future<void> record(HistoryVisitDraft draft);
}
