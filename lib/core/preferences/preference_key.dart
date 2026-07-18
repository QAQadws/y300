import 'package:flutter/foundation.dart';

/// A typed key for one value in the device preference store.
@immutable
final class PreferenceKey<T extends Object> {
  const PreferenceKey(this.name);

  final String name;

  @override
  bool operator ==(Object other) =>
      other is PreferenceKey<T> && other.name == name;

  @override
  int get hashCode => Object.hash(runtimeType, name);

  @override
  String toString() => 'PreferenceKey<$T>($name)';
}
