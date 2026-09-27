import 'dart:convert';
import 'dart:io' as io;

/// Identifies SVG before a cached file reaches Flutter's raster image codec.
/// Reads only a bounded prefix and never treats HTML or an arbitrary decoding
/// failure as evidence that the file is an SVG.
final class SvgImageFileProbe {
  static const int _prefixLimit = 8192;
  static final _root = RegExp(r'^<svg(?:\s|/?>)');
  final Map<String, Future<bool>> _pending = {};

  Future<bool> isSvg(String localPath) {
    final path = localPath.trim();
    if (path.isEmpty) return Future.value(false);
    final pending = _pending[path];
    if (pending != null) return pending;
    late final Future<bool> task;
    task = _readPrefix(path).whenComplete(() {
      if (identical(_pending[path], task)) _pending.remove(path);
    });
    _pending[path] = task;
    return task;
  }

  Future<bool> _readPrefix(String path) async {
    try {
      final file = await io.File(path).open();
      try {
        var prefix = utf8.decode(
          await file.read(_prefixLimit),
          allowMalformed: true,
        );
        if (prefix.startsWith('\uFEFF')) prefix = prefix.substring(1);
        while (true) {
          prefix = prefix.trimLeft();
          if (prefix.startsWith('<?')) {
            final end = prefix.indexOf('?>', 2);
            if (end < 0) return false;
            prefix = prefix.substring(end + 2);
          } else if (prefix.startsWith('<!--')) {
            final end = prefix.indexOf('-->', 4);
            if (end < 0) return false;
            prefix = prefix.substring(end + 3);
          } else if (prefix.startsWith('<!DOCTYPE')) {
            final end = _doctypeEnd(prefix);
            if (end < 0) return false;
            prefix = prefix.substring(end + 1);
          } else {
            return _root.hasMatch(prefix);
          }
        }
      } finally {
        await file.close();
      }
    } on io.FileSystemException {
      // A missing/unreadable file must retain the ordinary image failure path.
      return false;
    }
  }

  int _doctypeEnd(String prefix) {
    var quote = 0;
    var subsetDepth = 0;
    for (var index = 9; index < prefix.length; index += 1) {
      final char = prefix.codeUnitAt(index);
      if (quote != 0) {
        if (char == quote) quote = 0;
      } else if (char == 0x22 || char == 0x27) {
        quote = char;
      } else if (char == 0x5b) {
        subsetDepth += 1;
      } else if (char == 0x5d && subsetDepth > 0) {
        subsetDepth -= 1;
      } else if (char == 0x3e && subsetDepth == 0) {
        return index;
      }
    }
    return -1;
  }
}
