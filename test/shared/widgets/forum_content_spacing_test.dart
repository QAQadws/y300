import 'package:flutter_test/flutter_test.dart';
import 'package:y300/shared/widgets/forum_content_spacing.dart';

void main() {
  group('ForumContentSpacing derived tokens', () {
    test('readable body inset is the sum of the two horizontal knobs', () {
      expect(
        ForumContentSpacing.readableBodyHorizontal,
        ForumContentSpacing.pageHorizontal +
            ForumContentSpacing.postBodyHorizontal,
      );
    });

    test('quill surface padding lands quill text on the post text inset', () {
      expect(
        ForumContentSpacing.composerQuillSurfaceHorizontal +
            ForumContentSpacing.quillInnerHorizontal,
        ForumContentSpacing.readableBodyHorizontal,
      );
    });

    test('source editor padding lands source text on the post text inset', () {
      expect(
        ForumContentSpacing.composerSourceEditorHorizontal +
            ForumContentSpacing.composerPageHorizontal,
        ForumContentSpacing.readableBodyHorizontal,
      );
    });

    test('composer body top matches the post body segment top', () {
      expect(
        ForumContentSpacing.composerBodyTop,
        ForumContentSpacing.postCardBodyTop,
      );
    });

    // The two composer paddings are differences, so shrinking the post insets
    // far enough turns them negative and silently clips the editor instead of
    // aligning it. Fail here rather than on a device.
    test('derived composer paddings stay non-negative', () {
      expect(
        ForumContentSpacing.composerQuillSurfaceHorizontal,
        greaterThanOrEqualTo(0),
        reason:
            'readableBodyHorizontal must stay >= quillInnerHorizontal '
            '(${ForumContentSpacing.quillInnerHorizontal})',
      );
      expect(
        ForumContentSpacing.composerSourceEditorHorizontal,
        greaterThanOrEqualTo(0),
        reason:
            'readableBodyHorizontal must stay >= composerPageHorizontal '
            '(${ForumContentSpacing.composerPageHorizontal})',
      );
    });
  });
}
