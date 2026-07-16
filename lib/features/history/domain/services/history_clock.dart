abstract interface class HistoryClock {
  DateTime now();
}

final class SystemHistoryClock implements HistoryClock {
  const SystemHistoryClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}
