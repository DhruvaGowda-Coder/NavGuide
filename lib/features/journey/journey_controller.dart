import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/telemetry.dart';

class JourneyState {
  const JourneyState({
    this.isRecording = false,
    this.activeJourneyId,
    this.elapsed = Duration.zero,
    this.gpsCount = 0,
    this.accelCount = 0,
    this.gyroCount = 0,
    this.magCount = 0,
    this.history = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  final bool isRecording;
  final String? activeJourneyId;
  final Duration elapsed;
  final int gpsCount;
  final int accelCount;
  final int gyroCount;
  final int magCount;
  final List<JourneyMetadata> history;
  final bool isLoading;
  final String? errorMessage;

  int get totalSamples => gpsCount + accelCount + gyroCount + magCount;

  JourneyState copyWith({
    bool? isRecording,
    String? Function()? activeJourneyId,
    Duration? elapsed,
    int? gpsCount,
    int? accelCount,
    int? gyroCount,
    int? magCount,
    List<JourneyMetadata>? history,
    bool? isLoading,
    String? Function()? errorMessage,
  }) => JourneyState(
    isRecording: isRecording ?? this.isRecording,
    activeJourneyId: activeJourneyId != null
        ? activeJourneyId()
        : this.activeJourneyId,
    elapsed: elapsed ?? this.elapsed,
    gpsCount: gpsCount ?? this.gpsCount,
    accelCount: accelCount ?? this.accelCount,
    gyroCount: gyroCount ?? this.gyroCount,
    magCount: magCount ?? this.magCount,
    history: history ?? this.history,
    isLoading: isLoading ?? this.isLoading,
    errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
  );
}

class JourneyController extends Notifier<JourneyState> {
  Timer? _ticker;
  DateTime? _recordingStartTime;

  @override
  JourneyState build() {
    ref.onDispose(() {
      _ticker?.cancel();
    });
    // Trigger initial load of history
    Future.microtask(loadHistory);
    return const JourneyState();
  }

  Future<void> loadHistory() async {
    state = state.copyWith(isLoading: true, errorMessage: () => null);
    try {
      final storage = ref.read(journeyStorageProvider);
      final list = await storage.listJourneys();
      state = state.copyWith(history: list, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: () => 'Failed to load journey history: $e',
      );
    }
  }

  Future<bool> startJourney() async {
    final recorder = ref.read(journeyRecordingServiceProvider);
    if (recorder.isRecording) return false;

    try {
      state = state.copyWith(isLoading: true, errorMessage: () => null);
      _recordingStartTime = DateTime.now();

      // Hook up live counter updates
      recorder.onStatsUpdate = (stats) {
        state = state.copyWith(
          gpsCount: stats.gpsCount,
          accelCount: stats.accelCount,
          gyroCount: stats.gyroCount,
          magCount: stats.magCount,
        );
      };

      final journeyId = await recorder.startJourney();

      // Start elapsed ticker
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_recordingStartTime != null) {
          state = state.copyWith(
            elapsed: DateTime.now().difference(_recordingStartTime!),
          );
        }
      });

      state = state.copyWith(
        isRecording: true,
        activeJourneyId: () => journeyId,
        elapsed: Duration.zero,
        gpsCount: 0,
        accelCount: 0,
        gyroCount: 0,
        magCount: 0,
        isLoading: false,
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: () => 'Failed to start journey recording: $e',
      );
      return false;
    }
  }

  Future<JourneyMetadata?> stopJourney() async {
    final recorder = ref.read(journeyRecordingServiceProvider);
    if (!recorder.isRecording) return null;

    try {
      state = state.copyWith(isLoading: true);
      _ticker?.cancel();
      _ticker = null;
      _recordingStartTime = null;

      final meta = await recorder.stopJourney();
      await loadHistory();

      state = state.copyWith(
        isRecording: false,
        activeJourneyId: () => null,
        elapsed: Duration.zero,
        isLoading: false,
      );
      return meta;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: () => 'Failed to stop journey recording: $e',
      );
      return null;
    }
  }

  Future<bool> deleteJourney(String journeyId) async {
    try {
      final storage = ref.read(journeyStorageProvider);
      final deleted = await storage.deleteJourney(journeyId);
      if (deleted) {
        await loadHistory();
      }
      return deleted;
    } catch (e) {
      state = state.copyWith(
        errorMessage: () => 'Failed to delete journey: $e',
      );
      return false;
    }
  }
}
