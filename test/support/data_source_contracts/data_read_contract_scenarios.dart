import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/data_source/data_read_contract.dart';

void expectSuccessfulReadContract<T, C>(
  DataReadResult<T, C> result, {
  required bool Function(C capabilities) hasKnownIdentity,
}) {
  expect(result, isA<DataReadSuccess<T, C>>());
  final success = result as DataReadSuccess<T, C>;
  expect(hasKnownIdentity(success.capabilities), isTrue);
  expect(success.metadata.origin, isNot(DataReadOrigin.unknown));
}

void expectSourceNeutralFailure<T, C>(
  DataReadResult<T, C> result, {
  required DataReadFailureKind kind,
}) {
  expect(result, isA<DataReadFailure<T, C>>());
  final failure = result as DataReadFailure<T, C>;
  expect(failure.kind, kind);
  expect(failure.diagnosticMessage, isNotEmpty);
  expect(
    failure.diagnosticMessage,
    isNot(anyOf(contains('<html'), contains('Set-Cookie'))),
  );
}
