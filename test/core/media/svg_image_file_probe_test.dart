import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/media/svg_image_file_probe.dart';

void main() {
  late io.Directory directory;
  late SvgImageFileProbe probe;

  setUp(() {
    directory = io.Directory.systemTemp.createTempSync('avatar_svg_probe_');
    probe = SvgImageFileProbe();
  });
  tearDown(() => directory.deleteSync(recursive: true));

  for (final entry in <String, String>{
    'plain SVG': '<svg xmlns="http://www.w3.org/2000/svg"></svg>',
    'BOM and XML declaration':
        '\uFEFF \n<?xml version="1.0" encoding="UTF-8"?>\n<svg/>',
    'comments and processing instructions':
        '<!-- default avatar --><?xml-stylesheet href="avatar.css"?><svg/>',
    'doctype with quoted and internal delimiters':
        '<!DOCTYPE svg [<!ENTITY label "a > b">]><svg/>',
  }.entries) {
    test('recognizes ${entry.key} in a file named as JPEG', () async {
      final file = io.File('${directory.path}/avatar.jpg')
        ..writeAsStringSync(entry.value, encoding: utf8);
      expect(await probe.isSvg(file.path), isTrue);
    });
  }

  test('does not classify PNG, HTML, or corrupt content as SVG', () async {
    final file = io.File('${directory.path}/avatar.svg');
    for (final bytes in <List<int>>[
      base64Decode(_png),
      utf8.encode('<!doctype html><html><body><svg/></body></html>'),
      utf8.encode('<html><!-- <svg/> --></html>'),
      utf8.encode('broken image <svg/>'),
      utf8.encode('<!-- incomplete comment <svg/>'),
      utf8.encode('<svgSomething/>'),
      [],
    ]) {
      file.writeAsBytesSync(bytes, flush: true);
      expect(await probe.isSvg(file.path), isFalse);
    }
  });

  test(
    'bounds reads and leaves unrecognized content to the normal decoder',
    () async {
      final file = io.File('${directory.path}/large.jpg')
        ..writeAsStringSync('<!--${' ' * 9000}--><svg/>', encoding: utf8);
      expect(await probe.isSvg(file.path), isFalse);
    },
  );

  test(
    'rechecks replaced files instead of retaining a stale SVG decision',
    () async {
      final file = io.File('${directory.path}/avatar')
        ..writeAsStringSync('<svg/>', encoding: utf8);
      expect(await probe.isSvg(file.path), isTrue);
      file.writeAsBytesSync(base64Decode(_png), flush: true);
      expect(await probe.isSvg(file.path), isFalse);
    },
  );

  test(
    'missing and empty paths do not become synthetic default avatars',
    () async {
      expect(await probe.isSvg(''), isFalse);
      expect(await probe.isSvg('${directory.path}/missing'), isFalse);
    },
  );
}

const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';
