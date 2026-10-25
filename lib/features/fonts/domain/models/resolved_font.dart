import 'font_identity.dart';

/// Published only after the requested font has finished loading.
final class ResolvedFont {
  const ResolvedFont({required this.id, required this.fontFamily});

  static const system = ResolvedFont(id: FontIdentity.system, fontFamily: null);

  final String id;
  final String? fontFamily;

  bool get isSystem => id == FontIdentity.system;

  /// Consumers use content identity, rather than a user-editable display name.
  String get cacheKey => id;

  @override
  bool operator ==(Object other) =>
      other is ResolvedFont && id == other.id && fontFamily == other.fontFamily;

  @override
  int get hashCode => Object.hash(id, fontFamily);
}
