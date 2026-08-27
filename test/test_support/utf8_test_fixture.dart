import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Reads a committed UTF-8 fixture from `test/fixtures`.
///
/// Private `docs` files and paths outside the fixture root are intentionally
/// rejected so a clean checkout observes the same test inputs as a local run.
String readUtf8TestFixture(String relativePath) {
  final portablePath = relativePath.trim().replaceAll('\\', '/');
  final normalizedPath = p.posix.normalize(portablePath);
  final hasWindowsRoot = RegExp(r'^[a-zA-Z]:/').hasMatch(normalizedPath);
  if (portablePath.isEmpty ||
      p.posix.isAbsolute(normalizedPath) ||
      hasWindowsRoot ||
      normalizedPath == '..' ||
      normalizedPath.startsWith('../')) {
    throw ArgumentError.value(
      relativePath,
      'relativePath',
      'Fixture path must stay inside test/fixtures.',
    );
  }

  final fixtureRoot = p.normalize(Directory('test/fixtures').absolute.path);
  final fixturePath = p.normalize(
    p.joinAll(<String>[fixtureRoot, ...p.posix.split(normalizedPath)]),
  );
  if (!p.isWithin(fixtureRoot, fixturePath)) {
    throw ArgumentError.value(
      relativePath,
      'relativePath',
      'Fixture path must stay inside test/fixtures.',
    );
  }

  final fixture = File(fixturePath);
  if (!fixture.existsSync()) {
    throw StateError('Required test fixture is missing: $normalizedPath');
  }
  try {
    return utf8.decode(fixture.readAsBytesSync());
  } on FormatException catch (error) {
    throw StateError(
      'Test fixture is not valid UTF-8: $normalizedPath (${error.message})',
    );
  }
}
