import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/telemetry.dart';

enum TrackingStatus {
  idle,
  requesting,
  waiting,
  live,
  denied,
  blocked,
  disabled,
  error,
  paused,
}

class TrackingState {
  const TrackingState(this.status, {this.fix, this.message});
  final TrackingStatus status;
  final GeoFix? fix;
  final String? message;
}

final locationControllerProvider =
    NotifierProvider<LocationController, TrackingState>(LocationController.new);

class LocationController extends Notifier<TrackingState> {
  StreamSubscription<GeoFix>? _positions;
  StreamSubscription<bool>? _services;
  Timer? _timeout;
  int _generation = 0;
  bool _enabled = false;

  @override
  TrackingState build() {
    ref.listen(foregroundProvider, (_, active) {
      if (!active) {
        _cancel();
        state = const TrackingState(TrackingStatus.paused);
      } else if (_enabled) {
        start(requestPermission: false);
      } else {
        state = const TrackingState(TrackingStatus.idle);
      }
    });
    ref.onDispose(_cancel);
    return const TrackingState(TrackingStatus.idle);
  }

  void _cancel() {
    _generation++;
    _positions?.cancel();
    _services?.cancel();
    _timeout?.cancel();
    _positions = null;
    _services = null;
  }

  void stop() {
    _enabled = false;
    _cancel();
    state = const TrackingState(TrackingStatus.idle);
  }

  Future<void> start({bool requestPermission = true}) async {
    _enabled = true;
    _cancel();
    final generation = _generation;
    state = const TrackingState(TrackingStatus.requesting);
    final service = ref.read(locationServiceProvider);
    try {
      final access = await service.access(request: requestPermission);
      if (generation != _generation) return;
      final status = switch (access) {
        LocationAccess.granted => TrackingStatus.waiting,
        LocationAccess.denied => TrackingStatus.denied,
        LocationAccess.deniedForever => TrackingStatus.blocked,
        LocationAccess.serviceDisabled => TrackingStatus.disabled,
      };
      state = TrackingState(status);
      if (access != LocationAccess.granted) return;
      _services = service.serviceChanges().listen(
        (enabled) async {
          if (generation != _generation) return;
          if (!enabled) {
            final check = await service.access(request: false);
            if (generation != _generation) return;
            if (check == LocationAccess.serviceDisabled) {
              _cancel();
              state = const TrackingState(TrackingStatus.disabled);
            }
          }
        },
        onError: (Object error) {
          // Position stream remains the source of truth on platforms without this API.
        },
      );
      _timeout = Timer(const Duration(seconds: 25), () {
        if (generation == _generation && state.fix == null) {
          state = const TrackingState(
            TrackingStatus.waiting,
            message: 'Still waiting for a GPS fix. Try moving outdoors.',
          );
        }
      });
      _positions = service.watch().listen(
        (fix) {
          if (generation != _generation) return;
          _timeout?.cancel();
          state = TrackingState(TrackingStatus.live, fix: fix);
        },
        onError: (Object error) {
          if (generation != _generation) return;
          _cancel();
          state = const TrackingState(
            TrackingStatus.error,
            message: 'Location stream failed. Check permissions and retry.',
          );
        },
        onDone: () {
          if (generation != _generation) return;
          _cancel();
          state = const TrackingState(
            TrackingStatus.error,
            message: 'Location stream stopped. Retry to reconnect.',
          );
        },
      );
    } catch (_) {
      if (generation != _generation) return;
      _cancel();
      state = const TrackingState(
        TrackingStatus.error,
        message: 'Location is unavailable. Check device settings and retry.',
      );
    }
  }

  Future<void> openSettings({required bool location}) async {
    try {
      final service = ref.read(locationServiceProvider);
      final opened = await (location
          ? service.openLocationSettings()
          : service.openAppSettings());
      if (!opened) {
        state = const TrackingState(
          TrackingStatus.error,
          message: 'Open system settings manually, then return and retry.',
        );
      }
    } catch (_) {
      state = const TrackingState(
        TrackingStatus.error,
        message: 'Unable to open settings automatically.',
      );
    }
  }
}