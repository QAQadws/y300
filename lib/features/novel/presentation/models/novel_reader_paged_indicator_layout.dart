import 'package:flutter/widgets.dart';

abstract final class NovelReaderPagedIndicatorLayout {
  static const double fontSize = 11;
  static const double lineHeight = 1.2;
  static const double rightInset = 2;
  static const double bottomInset = 2;
  static const double contentClearance = 4;

  static double reservedHeight(TextScaler textScaler) {
    return textScaler.scale(fontSize) * lineHeight +
        bottomInset +
        contentClearance;
  }
}
