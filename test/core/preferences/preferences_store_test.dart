import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/preferences/preference_key.dart';
import 'package:y300/core/preferences/preferences_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('typed keys include their value type in equality', () {
    const stringKey = PreferenceKey<String>('test.same-name');
    const anotherStringKey = PreferenceKey<String>('test.same-name');
    const intKey = PreferenceKey<int>('test.same-name');

    expect(stringKey, anotherStringKey);
    expect(stringKey.hashCode, anotherStringKey.hashCode);
    expect(stringKey, isNot(intKey));
  });

  test('store reads and writes supported typed values', () async {
    final store = SharedPreferencesStore();
    const boolKey = PreferenceKey<bool>('test.bool');
    const intKey = PreferenceKey<int>('test.int');
    const doubleKey = PreferenceKey<double>('test.double');
    const stringKey = PreferenceKey<String>('test.string');
    const stringsKey = PreferenceKey<List<String>>('test.strings');

    await store.write(boolKey, true);
    await store.write(intKey, 7);
    await store.write(doubleKey, 1.5);
    await store.write(stringKey, 'value');
    await store.write(stringsKey, <String>['a', 'b']);

    expect(await store.read(boolKey), isTrue);
    expect(await store.read(intKey), 7);
    expect(await store.read(doubleKey), 1.5);
    expect(await store.read(stringKey), 'value');
    expect(await store.read(stringsKey), <String>['a', 'b']);
    expect(await store.contains(stringKey), isTrue);

    await store.remove(stringKey);
    expect(await store.contains(stringKey), isFalse);
  });

  test('wrong stored types are treated as absent', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'test.value': 3});
    final store = SharedPreferencesStore();

    expect(await store.read(const PreferenceKey<String>('test.value')), isNull);
  });

  test('one store resolves its SharedPreferences client once', () async {
    var loadCount = 0;
    final store = SharedPreferencesStore(
      loader: () async {
        loadCount += 1;
        return SharedPreferences.getInstance();
      },
    );
    const key = PreferenceKey<bool>('test.cached-client');

    await store.write(key, true);
    await store.read(key);
    await store.contains(key);

    expect(loadCount, 1);
  });
}
