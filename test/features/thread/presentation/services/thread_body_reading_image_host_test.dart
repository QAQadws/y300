import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/thread/presentation/services/thread_body_reading_image_host.dart';

void main() {
  testWidgets('waits only for viewport images and rejects old first frames', (
    tester,
  ) async {
    final viewportKey = GlobalKey();
    final delegate = _Host();
    final tracker = ThreadBodyReadingImageTracker(() {});
    addTearDown(tracker.dispose);
    final host = ThreadBodyReadingImageHost(
      delegate: delegate,
      tracker: tracker,
    );
    var identity = 'a';
    Widget scene() => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          key: viewportKey,
          width: 400,
          height: 200,
          child: SingleChildScrollView(
            child: Column(
              children: [
                host.buildImage(
                  image: _Image(identity),
                  fit: BoxFit.contain,
                  placeholder: const SizedBox(),
                  width: 400,
                  height: 120,
                ),
                const SizedBox(height: 300),
                host.buildImage(
                  image: _Image('offscreen'),
                  fit: BoxFit.contain,
                  placeholder: const SizedBox(),
                  width: 400,
                  height: 120,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(scene());
    final viewport =
        viewportKey.currentContext!.findRenderObject()! as RenderBox;
    expect(tracker.readyIn(viewport), isFalse);
    final oldFirstFrame = delegate.firstFrames['a']!;
    oldFirstFrame();
    expect(
      tracker.readyIn(viewport),
      isTrue,
      reason: 'screen-external image does not block',
    );
    identity = 'replacement';
    await tester.pumpWidget(scene());
    expect(tracker.readyIn(viewport), isFalse);
    oldFirstFrame();
    expect(tracker.readyIn(viewport), isFalse);
    delegate.firstFrames['replacement']!();
    expect(tracker.readyIn(viewport), isTrue);
  });

  testWidgets('retains bounded predecode and the original display callbacks', (
    tester,
  ) async {
    final delegate = _Host();
    final tracker = ThreadBodyReadingImageTracker(() {});
    addTearDown(tracker.dispose);
    final host = ThreadBodyReadingImageHost(
      delegate: delegate,
      tracker: tracker,
    );
    final image = _Image('image');
    final scope = ForumHtmlImageWorkToken();
    late BuildContext context;
    var firstFrames = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return host.buildImage(
              image: image,
              fit: BoxFit.contain,
              placeholder: const SizedBox(),
              onFirstFrameRendered: () => firstFrames++,
            );
          },
        ),
      ),
    );
    delegate.firstFrames['image']!();
    expect(firstFrames, 1);
    expect(
      host.canRetainDisplayedImage(
        image: image,
        intrinsicSize: const Size(200, 100),
        displaySize: const Size(100, 50),
        devicePixelRatio: 2,
        maxDecodedBytes: 1000,
      ),
      isTrue,
    );
    expect(
      await host.predecodeImage(
        image: image,
        context: context,
        displaySize: const Size(100, 50),
        scope: scope,
        maxDecodedBytes: 1000,
      ),
      ForumHtmlImagePreparationOutcome.decoded,
    );
    expect(delegate.predecodeCalls, 1);
    expect(delegate.diskCalls, 0);
    await host.prefetchDisk(image, scope: scope);
    expect(delegate.diskCalls, 1);
  });
}

class _Image implements ForumHtmlDisplayImage {
  _Image(this.identity);
  @override
  final String identity;
  @override
  String get cacheKey => identity;
  @override
  String get sourceUrl => 'https://example.test/$identity.jpg';
  @override
  bool get isSticker => false;
  @override
  Size? get htmlSize => const Size(400, 120);
  @override
  ForumHtmlImageLayout get initialLayout =>
      const ForumHtmlImageLayout(displaySize: Size(400, 120));
}

class _Host implements ForumHtmlImageHost, ForumHtmlImagePredecodeHost {
  final firstFrames = <String, VoidCallback>{};
  int predecodeCalls = 0;
  int diskCalls = 0;
  @override
  ForumHtmlDisplayImage? resolveImage({
    required Uri url,
    required int? imageIndex,
    required bool isSticker,
    Size? htmlSize,
  }) => null;
  @override
  Future<({Size size, ForumHtmlImageLayout layout})?> loadDimensions(
    ForumHtmlDisplayImage image,
  ) async => null;
  @override
  void onBlockImageResolved(ForumHtmlDisplayImage image, Size size) {}
  @override
  Future<void> prefetchDisk(
    ForumHtmlDisplayImage image, {
    required ForumHtmlImageWorkScope scope,
  }) async {
    diskCalls++;
  }

  @override
  bool canRetainDisplayedImage({
    required ForumHtmlDisplayImage image,
    required Size intrinsicSize,
    required Size displaySize,
    required double devicePixelRatio,
    required int maxDecodedBytes,
  }) => true;
  @override
  Future<ForumHtmlImagePreparationOutcome> predecodeImage({
    required ForumHtmlDisplayImage image,
    required BuildContext context,
    required Size displaySize,
    required ForumHtmlImageWorkScope scope,
    required int maxDecodedBytes,
  }) async {
    predecodeCalls++;
    return ForumHtmlImagePreparationOutcome.decoded;
  }

  @override
  Widget buildImage({
    required ForumHtmlDisplayImage image,
    required BoxFit fit,
    required Widget placeholder,
    double? width,
    double? height,
    Widget? errorPlaceholder,
    VoidCallback? onRetry,
    ValueChanged<Size>? onImageResolved,
    VoidCallback? onImageFailed,
    VoidCallback? onFirstFrameRendered,
    bool showDelayedLoadingIndicator = false,
    bool waitForCacheWrite = false,
    int retryToken = 0,
  }) {
    firstFrames[image.identity as String] = onFirstFrameRendered!;
    return SizedBox(width: width ?? 100, height: height ?? 100);
  }
}
