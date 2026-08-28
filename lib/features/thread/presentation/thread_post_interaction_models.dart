import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

/// Presentation projection that preserves the existing single-score sheet.
final class ThreadPostRateForm {
  const ThreadPostRateForm({
    required this.preparation,
    required this.dimension,
  });

  final ThreadPostRatingPreparation preparation;
  final ThreadPostRatingDimension dimension;

  String get scoreName => dimension.id;
  int get scoreMin => dimension.minimum;
  int get scoreMax => dimension.maximum;
  int get todayRemaining => dimension.todayRemaining;
  int get defaultScore => dimension.defaultScore;
  List<String> get reasonOptions => preparation.reasonSuggestions;
  bool get notifyAuthorDefault => preparation.notifyAuthorByDefault;
}

final class ThreadPostRateDraft {
  const ThreadPostRateDraft({
    required this.form,
    required this.score,
    required this.reason,
    required this.notifyAuthor,
  });

  final ThreadPostRateForm form;
  final int score;
  final String reason;
  final bool notifyAuthor;

  ThreadPostRatingSubmission toSubmission() => ThreadPostRatingSubmission(
    preparation: form.preparation,
    scores: <String, int>{
      for (final dimension in form.preparation.dimensions)
        dimension.id: dimension.initialScore,
      form.scoreName: score,
    },
    reason: reason,
    notifyAuthor: notifyAuthor,
  );
}

final class ThreadPostCommentForm {
  const ThreadPostCommentForm({required this.preparation});

  final ThreadPostCommentPreparation preparation;
  int get maxLength => preparation.maxLength;
}

final class ThreadPostCommentDraft {
  const ThreadPostCommentDraft({required this.form, required this.message});

  final ThreadPostCommentForm form;
  final String message;

  ThreadPostCommentSubmission toSubmission() => ThreadPostCommentSubmission(
    preparation: form.preparation,
    message: message,
  );
}
