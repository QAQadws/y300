import 'package:flutter/widgets.dart';

import 'forum_html_display_image.dart';

enum ForumHtmlImagePreparationOutcome { decoded, diskOnly, failed, cancelled }

/// Optional, bounded first-frame preparation without exposing App cache types.
abstract interface class ForumHtmlImagePredecodeHost {
  /// Checks an already displayed frame against the same decode budget without
  /// starting another download or decode. Unknown dimensions are not admitted.
  bool canRetainDisplayedImage({
    required ForumHtmlDisplayImage image,
    required Size intrinsicSize,
    required Size displaySize,
    required double devicePixelRatio,
    required int maxDecodedBytes,
  });

  Future<ForumHtmlImagePreparationOutcome> predecodeImage({
    required ForumHtmlDisplayImage image,
    required BuildContext context,
    required Size displaySize,
    required ForumHtmlImageWorkScope scope,
    required int maxDecodedBytes,
  });
}
