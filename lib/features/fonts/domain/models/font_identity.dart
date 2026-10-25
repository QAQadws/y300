abstract final class FontIdentity {
  static const system = 'system';

  static final RegExp _importedId = RegExp(r'^[0-9a-f]{64}$');

  static bool isImported(String value) => _importedId.hasMatch(value);

  /// Content identity also isolates engine registrations with equal file names.
  static String runtimeFamily(String id) {
    if (!isImported(id)) {
      throw ArgumentError.value(id, 'id', 'Expected a font content hash');
    }
    return 'Y300ImportedFont_$id';
  }
}
