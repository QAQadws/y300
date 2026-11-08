import 'package:flutter/material.dart';
import 'package:forum_content_renderer/experimental_continuous.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

ForumBodyReaderStyle reader() => ForumBodyReaderStyle(
  textStyle: const TextStyle(
    fontFamily: 'Ahem',
    fontSize: 10,
    height: 1,
    color: Colors.black,
  ),
  fontRevision: 'test-ahem',
  linkColor: Colors.blue,
  paragraphAfter: 0,
);

ForumBodyDocument document(String html) => const ForumBodyParser().parse(
  html: html,
  sourceId: 'continuous',
  conversionIdentity: 'none',
);

Widget scene(
  ForumBodyDocument body,
  ForumBodyContinuousController controller, {
  double width = 150,
  TextScaler scaler = TextScaler.noScaling,
  ValueChanged<ForumBodyContinuousHit>? onTap,
  VoidCallback? onLongPress,
  GlobalKey? boundary,
  Map<String, ForumBodyInlineImageSource> images = const {},
  ForumHtmlImageHost? imageHost,
  ValueChanged<ForumBodyInlineImageSource>? onImageTap,
}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        child: SingleChildScrollView(
          child: RepaintBoundary(
            key: boundary,
            child: GestureDetector(
              onLongPress: onLongPress,
              child: ForumBodyContinuous(
                document: body,
                reader: reader(),
                textScaler: scaler,
                controller: controller,
                onTap: onTap,
                imageSources: images,
                imageHost: imageHost,
                onImageTap: onImageTap,
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);
