import 'package:y300/features/content_rendering_shared/content_rendering.dart';

import '../../domain/models/novel_reader_marks.dart';

/// A visible source that may be verified again in another layout.
/// The fraction within a flowing image belongs only to the live handoff.
typedef NovelReaderNativeSourceLocation = ({
  ForumBodyIdentity identity,
  NovelReaderTextAnchor anchor,
  String? tablePath,
  double imageProgress,
});
