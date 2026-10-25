import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Run from the repository root after replacing the approved source PNG.
Future<void> main() async {
  const sourcePath = 'assets/app_icon_source.png';
  final source = img.decodePng(await File(sourcePath).readAsBytes());
  if (source == null ||
      source.width != source.height ||
      source.width < 1024 ||
      source.frames.length != 1) {
    throw StateError('Expected one square PNG of at least 1024px: $sourcePath');
  }
  if (source.any((pixel) => pixel.a != pixel.maxChannelValue)) {
    throw StateError('The approved square source must be fully opaque.');
  }

  final square = _resize(source, 1024);
  final rounded = _roundCorners(square);
  final logo = _extractLogo(rounded);
  await _writePng('assets/app_icon.png', square);
  await _writePng('assets/app_icon_transparent.png', rounded);
  await _writePng('assets/splash_logo.png', _logoCanvas(logo, 768, 480));
  await _writePng(
    'assets/splash_logo_android12.png',
    _logoCanvas(logo, 1152, 512),
  );
  for (final entry in const {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  }.entries) {
    await _writePng(
      'android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png',
      _resize(rounded, entry.value),
    );
  }
  stdout.writeln('Generated app icons and splash logo sources from $sourcePath.');
  stdout.writeln('Next: dart run flutter_native_splash:create');
}

img.Image _resize(img.Image source, int size) => img.copyResize(
  source,
  width: size,
  height: size,
  interpolation: img.Interpolation.average,
);

img.Image _roundCorners(img.Image source) {
  final rounded = source.convert(numChannels: 4);
  final half = source.width / 2;
  final radius = source.width * 0.21;
  for (final pixel in rounded) {
    // Geometry alone changes alpha. Pale interior pixels are never mistaken
    // for background, unlike color-based removal of the whole icon tile.
    final dx = (pixel.x + 0.5 - half).abs() - (half - radius);
    final dy = (pixel.y + 0.5 - half).abs() - (half - radius);
    final outsideX = math.max(dx, 0.0);
    final outsideY = math.max(dy, 0.0);
    final distance =
        math.sqrt(outsideX * outsideX + outsideY * outsideY) +
        math.min(math.max(dx, dy), 0.0) -
        radius;
    pixel.a = (255 * (0.5 - distance).clamp(0.0, 1.0)).round();
  }
  return rounded;
}

img.Image _extractLogo(img.Image rounded) {
  final logo = img.Image(
    width: rounded.width,
    height: rounded.height,
    numChannels: 4,
  );
  // This is the approved cream/red artwork's matte, not a general-purpose
  // background remover. Recover edge coverage from green, then unmatte RGB
  // so its anti-aliased edges do not carry cream halos onto the splash.
  const background = [253.0, 252.0, 241.0];
  const foregroundGreen = 6.0;
  for (final pixel in rounded) {
    final coverage = ((background[1] - pixel.g) /
            (background[1] - foregroundGreen))
        .clamp(0.0, 1.0);
    if (pixel.a == 0 || coverage < 0.02) {
      continue;
    }
    int unmatte(num channel, double matte) =>
        ((channel - matte * (1 - coverage)) / coverage)
            .round()
            .clamp(0, 255)
            .toInt();
    logo.setPixelRgba(
      pixel.x,
      pixel.y,
      unmatte(pixel.r, background[0]),
      unmatte(pixel.g, background[1]),
      unmatte(pixel.b, background[2]),
      (pixel.a * coverage).round(),
    );
  }
  return logo;
}

img.Image _logoCanvas(img.Image logo, int size, int logoSize) {
  final canvas = img.Image(width: size, height: size, numChannels: 4);
  final inset = (size - logoSize) ~/ 2;
  return img.compositeImage(
    canvas,
    _resize(logo, logoSize),
    dstX: inset,
    dstY: inset,
  );
}

Future<void> _writePng(String path, img.Image image) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(img.encodePng(image));
}
