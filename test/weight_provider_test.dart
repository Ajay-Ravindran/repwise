import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:repwise/providers/repwise_provider.dart';
import 'package:repwise/utils/repwise_storage.dart';

/// Captures whatever was last written, so tests can assert on persistence,
/// and can be seeded to test that state survives a reload.
class _CapturingStorage extends RepwiseStorage {
  _CapturingStorage({Map<String, dynamic>? initialState})
      : _state = initialState;

  Map<String, dynamic>? _state;
  Map<String, dynamic>? get lastWritten => _state;

  @override
  Future<Map<String, dynamic>?> readState() async => _state;

  @override
  Future<void> writeState(Map<String, dynamic> state) async {
    _state = state;
  }

  @override
  Future<File?> createExportFile(Map<String, dynamic> state) async => null;
}

void main() {
  group('RepwiseProvider weight tracking', () {
    test('logWeight adds a new entry for a day with no existing entry', () async {
      final provider = RepwiseProvider(storage: _CapturingStorage());
      await provider.initialize();

      provider.logWeight(82.5, date: DateTime(2026, 6, 1));

      expect(provider.weightEntries.length, equals(1));
      expect(provider.weightEntries.single.weight, equals(82.5));
      expect(provider.weightEntries.single.date, equals(DateTime(2026, 6, 1)));
    });

    test('logWeight overwrites the same day with the latest value', () async {
      final provider = RepwiseProvider(storage: _CapturingStorage());
      await provider.initialize();

      provider.logWeight(82.5, date: DateTime(2026, 6, 1));
      provider.logWeight(81.0, date: DateTime(2026, 6, 1));

      expect(provider.weightEntries.length, equals(1));
      expect(provider.weightEntries.single.weight, equals(81.0));
    });

    test('weightEntries is sorted ascending by date', () async {
      final provider = RepwiseProvider(storage: _CapturingStorage());
      await provider.initialize();

      provider.logWeight(80.0, date: DateTime(2026, 6, 5));
      provider.logWeight(82.0, date: DateTime(2026, 6, 1));

      final dates = provider.weightEntries.map((e) => e.date).toList();
      expect(dates, equals([DateTime(2026, 6, 1), DateTime(2026, 6, 5)]));
    });

    test('deleteWeightEntry removes the matching entry', () async {
      final provider = RepwiseProvider(storage: _CapturingStorage());
      await provider.initialize();
      provider.logWeight(82.5, date: DateTime(2026, 6, 1));
      final id = provider.weightEntries.single.id;

      provider.deleteWeightEntry(id);

      expect(provider.weightEntries, isEmpty);
    });

    test('weight entries persist across a reload of the same storage', () async {
      final storage = _CapturingStorage();
      final provider = RepwiseProvider(storage: storage);
      await provider.initialize();
      provider.logWeight(82.5, date: DateTime(2026, 6, 1));

      // Simulate app restart: new provider instance, same backing storage.
      final reloaded = RepwiseProvider(storage: storage);
      await reloaded.initialize();

      expect(reloaded.weightEntries.length, equals(1));
      expect(reloaded.weightEntries.single.weight, equals(82.5));
    });

    test('persisted state includes a weightEntries key with the logged entry', () async {
      final storage = _CapturingStorage();
      final provider = RepwiseProvider(storage: storage);
      await provider.initialize();

      provider.logWeight(82.5, date: DateTime(2026, 6, 1));
      // logWeight persists asynchronously (unawaited); wait for it to land.
      await Future<void>.delayed(Duration.zero);

      final written = storage.lastWritten;
      expect(written, isNotNull);
      expect(written!['weightEntries'], isA<List<dynamic>>());
      expect((written['weightEntries'] as List).length, equals(1));
    });
  });
}
