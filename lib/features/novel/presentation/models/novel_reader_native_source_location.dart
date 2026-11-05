import 'package:y300/features/content_rendering_shared/content_rendering.dart';

import '../../domain/models/novel_reader_marks.dart';

/// A visible source that may be verified again in another layout.
typedef NovelReaderNativeSourceLocation = ({
  ForumBodyIdentity identity,
  NovelReaderTextAnchor anchor,
  String? tablePath,
});
