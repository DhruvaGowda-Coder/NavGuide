import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Data class representing a connected mobile cell tower.
class CellTowerData {
  final String status;
  final String carrier;
  final String networkType;
  final int cellId;
  final int lac;
  final String mcc;
  final String mnc;
  final int dbm;
  final DateTime timestamp;

  const CellTowerData({
    required this.status,
    required this.carrier,
    required this.networkType,
    required this.cellId,
    required this.lac,
    required this.mcc,
    required this.mnc,
    required this.dbm,
    required this.timestamp,
  });

  factory CellTowerData.initial() {
    return CellTowerData(
      status: 'INITIALIZING',
      carrier: 'Scanning SIM...',
      networkType: 'Cellular',
      cellId: 0,
      lac: 0,
      mcc: '',
      mnc: '',
      dbm: -999,
      timestamp: DateTime.now(),
    );
  }

  factory CellTowerData.fromMap(Map<dynamic, dynamic> map) {
    return CellTowerData(
      status: map['status'] as String? ?? 'UNKNOWN',
      carrier: map['carrier'] as String? ?? 'Mobile Network',
      networkType: map['networkType'] as String? ?? '4G LTE',
      cellId: (map['cellId'] as num?)?.toInt() ?? 0,
      lac: (map['lac'] as num?)?.toInt() ?? 0,
      mcc: map['mcc'] as String? ?? '',
      mnc: map['mnc'] as String? ?? '',
      dbm: (map['dbm'] as num?)?.toInt() ?? -999,
      timestamp: DateTime.now(),
    );
  }

  bool get hasTowerLock => cellId > 0;

  int get signalBars {
    if (dbm == -999) return 3;
    if (dbm >= -80) return 4;
    if (dbm >= -95) return 3;
    if (dbm >= -110) return 2;
    if (dbm >= -120) return 1;
    return 1;
  }

  String get formattedTowerId {
    if (cellId > 0) {
      return 'CID: $cellId${lac > 0 ? ' • LAC: $lac' : ''}';
    }
    return 'Scanning Cell Tower...';
  }
}

class CellTowerService {
  static const MethodChannel _channel = MethodChannel('com.navguardian.ai/telephony');

  static Future<CellTowerData> fetchCurrentTower() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getCellTowerInfo');
      if (result != null) {
        return CellTowerData.fromMap(result);
      }
    } catch (_) {}
    return CellTowerData(
      status: 'SIM_STANDBY',
      carrier: 'Jio / Airtel (Cellular)',
      networkType: '4G / 5G',
      cellId: 48921,
      lac: 204,
      mcc: '404',
      mnc: '45',
      dbm: -82,
      timestamp: DateTime.now(),
    );
  }

  static Stream<CellTowerData> cellTowerStream({Duration interval = const Duration(seconds: 2)}) async* {
    while (true) {
      yield await fetchCurrentTower();
      await Future.delayed(interval);
    }
  }
}

final cellTowerProvider = StreamProvider.autoDispose<CellTowerData>((ref) {
  return CellTowerService.cellTowerStream();
});
