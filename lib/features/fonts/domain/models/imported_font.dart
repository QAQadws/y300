/// A durable, device-local font entry. Paths remain relative to its repository.
final class ImportedFont {
  const ImportedFont({
    required this.id,
    required this.displayName,
    required this.storageFileName,
    required this.byteLength,
  });

  final String id;
  final String displayName;
  final String storageFileName;
  final int byteLength;

  @override
  bool operator ==(Object other) =>
      other is ImportedFont &&
      id == other.id &&
      displayName == other.displayName &&
      storageFileName == other.storageFileName &&
      byteLength == other.byteLength;

  @override
  int get hashCode => Object.hash(id, displayName, storageFileName, byteLength);
}
