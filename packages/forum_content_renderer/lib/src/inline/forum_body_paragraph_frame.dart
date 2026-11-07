import 'dart:collection';

import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../paragraph/forum_body_native_request.dart';
import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_geometry.dart'
    show forumBodyPaintedTextRanges;
import '../paragraph/forum_body_paragraph_layout.dart';
import '../paragraph/forum_body_paragraph_line_frames.dart';
import '../paragraph/forum_body_paragraph_row.dart';
import '../paragraph/forum_body_text_layout.dart';
import '../paragraph/forum_body_text_request.dart';
import '../paragraph/forum_body_text_request_preparation.dart';
import 'forum_body_emphasis_paragraph_metrics.dart';
import 'forum_body_emphasis_row_allocation.dart';

part 'forum_body_emphasis_allocated_layout.dart';
part 'forum_body_emphasis_allocated_scene_input.dart';
part 'forum_body_emphasis_fragment_layout.dart';
part 'forum_body_emphasis_fragment_preparation.dart';

typedef ForumBodyFontFrameStep = ({
  int partsPrepared,
  int nativeLayoutsBuilt,
  int picturesRecorded,
  bool waitingForLayoutBudget,
});

Never _allocatedSourceMismatch() =>
    throw const ForumBodyEmphasisAllocationException(
      ForumBodyEmphasisAllocationFailure.source,
    );
