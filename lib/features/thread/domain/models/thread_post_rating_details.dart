import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

final class ThreadPostRatingDetails {
  const ThreadPostRatingDetails({
    required this.participantCount,
    required this.totalScoreText,
    required this.ratings,
  });

  final int participantCount;
  final String totalScoreText;
  final List<ThreadPostRating> ratings;
}
