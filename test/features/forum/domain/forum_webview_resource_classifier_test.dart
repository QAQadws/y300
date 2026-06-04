import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/domain/models/forum_webview_resource_diagnostic_models.dart';
import 'package:y300/features/forum/domain/services/forum_webview_resource_classifier.dart';

void main() {
  const classifier = DefaultForumWebViewResourceClassifier();

  test('classifies forum resource urls into targeted kinds', () {
    expect(
      classifier.classify(
        Uri.parse('https://bbs.yamibo.com/static/image/smiley/1.gif'),
      ),
      ForumWebViewResourceKind.smiley,
    );
    expect(
      classifier.classify(
        Uri.parse('https://bbs.yamibo.com/data/attachment/forum/202606/1.png'),
      ),
      ForumWebViewResourceKind.attachment,
    );
    expect(
      classifier.classify(
        Uri.parse('https://bbs.yamibo.com/forum.php?mod=attachment&aid=123'),
      ),
      ForumWebViewResourceKind.attachment,
    );
    expect(
      classifier.classify(
        Uri.parse('https://bbs.yamibo.com/static/js/common.js'),
      ),
      ForumWebViewResourceKind.staticAsset,
    );
    expect(
      classifier.classify(
        Uri.parse('https://example.com/static/image/smiley/1.gif'),
      ),
      ForumWebViewResourceKind.other,
    );
  });
}
