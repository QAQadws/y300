import 'package:flutter/services.dart';

abstract interface class ClipboardTextReader {
  Future<String?> readText();
}

class PlatformClipboardTextReader implements ClipboardTextReader {
  const PlatformClipboardTextReader();

  @override
  Future<String?> readText() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text;
}
