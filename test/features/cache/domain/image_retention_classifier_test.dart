import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_retention_classifier.dart';

void main() {
  group('ImageRetentionClassifier.defaultFor', () {
    test('covers are protected assets', () {
      expect(
        ImageRetentionClassifier.defaultFor(ImageCacheRole.cover),
        ImageRetentionClass.protected,
      );
      expect(
        ImageRetentionClassifier.defaultFor(ImageCacheRole.customCover),
        ImageRetentionClass.protected,
      );
    });

    test(
      'stickers, carousel/forum head and forum icon are sticky long-term',
      () {
        expect(
          ImageRetentionClassifier.defaultFor(ImageCacheRole.remoteSmiley),
          ImageRetentionClass.sticky,
        );
        expect(
          ImageRetentionClassifier.defaultFor(ImageCacheRole.forumHeadImage),
          ImageRetentionClass.sticky,
        );
        expect(
          ImageRetentionClassifier.defaultFor(ImageCacheRole.forumIcon),
          ImageRetentionClass.sticky,
        );
      },
    );

    test('thread/avatar/blog/online comic-novel images are ephemeral', () {
      for (final role in <ImageCacheRole>[
        ImageCacheRole.threadInline,
        ImageCacheRole.threadAttachment,
        ImageCacheRole.avatar,
        ImageCacheRole.blogInline,
        ImageCacheRole.comicPage,
        ImageCacheRole.novelInline,
      ]) {
        expect(
          ImageRetentionClassifier.defaultFor(role),
          ImageRetentionClass.ephemeral,
          reason: 'role $role should be ephemeral',
        );
      }
    });

    test('isClearableByDefault is true only for ephemeral roles', () {
      expect(
        ImageRetentionClassifier.isClearableByDefault(
          ImageCacheRole.threadInline,
        ),
        isTrue,
      );
      expect(
        ImageRetentionClassifier.isClearableByDefault(
          ImageCacheRole.remoteSmiley,
        ),
        isFalse,
      );
      expect(
        ImageRetentionClassifier.isClearableByDefault(ImageCacheRole.cover),
        isFalse,
      );
    });

    test('every role has a defined classification', () {
      for (final role in ImageCacheRole.values) {
        // 不抛异常即覆盖完整（switch 无 default，新增 role 会被编译器强制处理）。
        expect(ImageRetentionClassifier.defaultFor(role), isNotNull);
      }
    });
  });
}
