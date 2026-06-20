import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/thread/presentation/widgets/thread_post_html.dart';

void main() {
  testWidgets(
    'ThreadPostHtml renders post images through request header builder',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ThreadPostHtml(
            data: '<img file="data/attachment/forum/page-1.jpg" />',
            imageHeaderBuilder: const _StaticImageHeaderBuilder(
              <String, String>{
                'Referer': 'https://bbs.yamibo.com/',
                'Cookie': 'auth=token123',
              },
            ),
          ),
        ),
      );

      await tester.pump();

      final image = tester.widget<Image>(find.byType(Image));
      expect(
        image.image,
        isA<NetworkImage>().having(
          (provider) => provider.url,
          'url',
          'https://bbs.yamibo.com/data/attachment/forum/page-1.jpg',
        ),
      );
      final provider = image.image as NetworkImage;
      expect(provider.headers, <String, String>{
        'Referer': 'https://bbs.yamibo.com/',
        'Cookie': 'auth=token123',
      });
    },
  );

  testWidgets(
    'ThreadPostHtml normalizes lazy-load attributes with shared defaults',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ThreadPostHtml(
            data:
                '<img data-original="//bbs.yamibo.com/data/attachment/forum/page-2.jpg" />',
          ),
        ),
      );

      await tester.pump();

      final image = tester.widget<Image>(find.byType(Image));
      expect(
        image.image,
        isA<NetworkImage>().having(
          (provider) => provider.url,
          'url',
          'https://bbs.yamibo.com/data/attachment/forum/page-2.jpg',
        ),
      );
    },
  );

  testWidgets(
    'ThreadPostHtml prefers desktop attachment file over placeholder src',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ThreadPostHtml(
            data:
                '<img src="static/image/common/none.gif" file="data/attachment/forum/page-real.jpg" />',
          ),
        ),
      );

      await tester.pump();

      final image = tester.widget<Image>(find.byType(Image));
      expect(
        image.image,
        isA<NetworkImage>().having(
          (provider) => provider.url,
          'url',
          'https://bbs.yamibo.com/data/attachment/forum/page-real.jpg',
        ),
      );
    },
  );
}

class _StaticImageHeaderBuilder implements ImageRequestHeaderBuilder {
  const _StaticImageHeaderBuilder(this.headers);

  final Map<String, String> headers;

  @override
  Future<Map<String, String>> buildHeaders(String imageUrl) async => headers;
}
