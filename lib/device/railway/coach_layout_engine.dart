enum CoachType {
  locoEngine,
  sleeper,
  ac3Tier,
  ac2Tier,
  acFirstClass,
  chairCar,
  executiveChair,
  general,
  pantry,
  guardSlr,
}

enum BerthType {
  lower,
  middle,
  upper,
  sideLower,
  sideUpper,
  window,
  middleSeat,
  aisle,
  cabin,
}

class SeatInfo {
  final int seatNumber;
  final BerthType berthType;
  final int bayNumber;
  final bool isWindow;
  final String label;

  const SeatInfo({
    required this.seatNumber,
    required this.berthType,
    required this.bayNumber,
    required this.isWindow,
    required this.label,
  });

  String get berthName {
    switch (berthType) {
      case BerthType.lower:
        return 'Lower Berth (LB)';
      case BerthType.middle:
        return 'Middle Berth (MB)';
      case BerthType.upper:
        return 'Upper Berth (UB)';
      case BerthType.sideLower:
        return 'Side Lower (SL)';
      case BerthType.sideUpper:
        return 'Side Upper (SU)';
      case BerthType.window:
        return 'Window Seat (W)';
      case BerthType.middleSeat:
        return 'Middle Seat (M)';
      case BerthType.aisle:
        return 'Aisle Seat (A)';
      case BerthType.cabin:
        return 'First Class Cabin';
    }
  }
}

class CoachInfo {
  final String coachCode;
  final String coachName;
  final CoachType type;
  final int totalBerths;

  const CoachInfo({
    required this.coachCode,
    required this.coachName,
    required this.type,
    required this.totalBerths,
  });

  String get typeDescription {
    switch (type) {
      case CoachType.locoEngine:
        return 'Locomotive Engine';
      case CoachType.sleeper:
        return 'Sleeper Class (Non-AC)';
      case CoachType.ac3Tier:
        return 'AC 3 Tier (3A)';
      case CoachType.ac2Tier:
        return 'AC 2 Tier (2A)';
      case CoachType.acFirstClass:
        return 'AC First Class (1A)';
      case CoachType.chairCar:
        return 'AC Chair Car (CC)';
      case CoachType.executiveChair:
        return 'Executive Chair Car (EC)';
      case CoachType.general:
        return 'General Unreserved (GEN)';
      case CoachType.pantry:
        return 'Pantry Car (PC)';
      case CoachType.guardSlr:
        return 'Guard & Luggage Van (SLR)';
    }
  }

  /// Calculates seat/berth information for any given seat number offline
  SeatInfo? resolveSeat(int seatNumber) {
    if (seatNumber < 1 || seatNumber > totalBerths) return null;

    if (type == CoachType.sleeper || type == CoachType.ac3Tier) {
      final rem = seatNumber % 8;
      final bay = ((seatNumber - 1) ~/ 8) + 1;
      BerthType bType;
      bool isWin = false;

      switch (rem) {
        case 1:
        case 4:
          bType = BerthType.lower;
          isWin = true;
          break;
        case 2:
        case 5:
          bType = BerthType.middle;
          break;
        case 3:
        case 6:
          bType = BerthType.upper;
          break;
        case 7:
          bType = BerthType.sideLower;
          isWin = true;
          break;
        case 0:
        default:
          bType = BerthType.sideUpper;
          break;
      }
      return SeatInfo(
        seatNumber: seatNumber,
        berthType: bType,
        bayNumber: bay,
        isWindow: isWin,
        label: '$seatNumber (${isWin ? "Window" : "Main Bay"})',
      );
    } else if (type == CoachType.ac2Tier) {
      final rem = seatNumber % 6;
      final bay = ((seatNumber - 1) ~/ 6) + 1;
      BerthType bType;
      bool isWin = false;

      switch (rem) {
        case 1:
        case 3:
          bType = BerthType.lower;
          isWin = true;
          break;
        case 2:
        case 4:
          bType = BerthType.upper;
          break;
        case 5:
          bType = BerthType.sideLower;
          isWin = true;
          break;
        case 0:
        default:
          bType = BerthType.sideUpper;
          break;
      }
      return SeatInfo(
        seatNumber: seatNumber,
        berthType: bType,
        bayNumber: bay,
        isWindow: isWin,
        label: '$seatNumber (Bay $bay)',
      );
    } else if (type == CoachType.chairCar || type == CoachType.executiveChair) {
      final mod = seatNumber % 5;
      final row = ((seatNumber - 1) ~/ 5) + 1;
      BerthType bType;
      bool isWin = false;

      switch (mod) {
        case 1:
        case 0:
          bType = BerthType.window;
          isWin = true;
          break;
        case 2:
          bType = BerthType.middleSeat;
          break;
        default:
          bType = BerthType.aisle;
          break;
      }
      return SeatInfo(
        seatNumber: seatNumber,
        berthType: bType,
        bayNumber: row,
        isWindow: isWin,
        label: 'Seat $seatNumber (Row $row)',
      );
    }

    return SeatInfo(
      seatNumber: seatNumber,
      berthType: BerthType.lower,
      bayNumber: 1,
      isWindow: false,
      label: 'Seat $seatNumber',
    );
  }
}

class CoachLayoutEngine {
  static final CoachLayoutEngine _instance = CoachLayoutEngine._internal();
  factory CoachLayoutEngine() => _instance;
  CoachLayoutEngine._internal();

  /// Returns sequential coach composition for a train
  List<CoachInfo> getCompositionForTrain(String trainNumber) {
    if (trainNumber.contains('20608') || trainNumber.contains('20607')) {
      // Vande Bharat Composition (16 coaches)
      return const [
        CoachInfo(coachCode: 'ENG', coachName: 'Loco Cab', type: CoachType.locoEngine, totalBerths: 0),
        CoachInfo(coachCode: 'C1', coachName: 'Chair Car', type: CoachType.chairCar, totalBerths: 78),
        CoachInfo(coachCode: 'C2', coachName: 'Chair Car', type: CoachType.chairCar, totalBerths: 78),
        CoachInfo(coachCode: 'C3', coachName: 'Chair Car', type: CoachType.chairCar, totalBerths: 78),
        CoachInfo(coachCode: 'C4', coachName: 'Chair Car', type: CoachType.chairCar, totalBerths: 78),
        CoachInfo(coachCode: 'E1', coachName: 'Exec Chair Car', type: CoachType.executiveChair, totalBerths: 52),
        CoachInfo(coachCode: 'E2', coachName: 'Exec Chair Car', type: CoachType.executiveChair, totalBerths: 52),
        CoachInfo(coachCode: 'C5', coachName: 'Chair Car', type: CoachType.chairCar, totalBerths: 78),
        CoachInfo(coachCode: 'C6', coachName: 'Chair Car', type: CoachType.chairCar, totalBerths: 78),
        CoachInfo(coachCode: 'C7', coachName: 'Chair Car', type: CoachType.chairCar, totalBerths: 78),
        CoachInfo(coachCode: 'C8', coachName: 'Chair Car', type: CoachType.chairCar, totalBerths: 78),
        CoachInfo(coachCode: 'ENG', coachName: 'Rear Cab', type: CoachType.locoEngine, totalBerths: 0),
      ];
    } else if (trainNumber.contains('12007') || trainNumber.contains('12008')) {
      // Shatabdi Express Composition
      return const [
        CoachInfo(coachCode: 'ENG', coachName: 'Loco Engine', type: CoachType.locoEngine, totalBerths: 0),
        CoachInfo(coachCode: 'EOG', coachName: 'Power Car', type: CoachType.guardSlr, totalBerths: 0),
        CoachInfo(coachCode: 'C1', coachName: 'Chair Car', type: CoachType.chairCar, totalBerths: 78),
        CoachInfo(coachCode: 'C2', coachName: 'Chair Car', type: CoachType.chairCar, totalBerths: 78),
        CoachInfo(coachCode: 'C3', coachName: 'Chair Car', type: CoachType.chairCar, totalBerths: 78),
        CoachInfo(coachCode: 'E1', coachName: 'Exec Chair Car', type: CoachType.executiveChair, totalBerths: 52),
        CoachInfo(coachCode: 'C4', coachName: 'Chair Car', type: CoachType.chairCar, totalBerths: 78),
        CoachInfo(coachCode: 'C5', coachName: 'Chair Car', type: CoachType.chairCar, totalBerths: 78),
        CoachInfo(coachCode: 'C6', coachName: 'Chair Car', type: CoachType.chairCar, totalBerths: 78),
        CoachInfo(coachCode: 'EOG', coachName: 'Power Car', type: CoachType.guardSlr, totalBerths: 0),
      ];
    }

    // Default Superfast Mail & Express Composition (e.g. 12657 Bengaluru - Chennai Mail)
    return const [
      CoachInfo(coachCode: 'ENG', coachName: 'Locomotive', type: CoachType.locoEngine, totalBerths: 0),
      CoachInfo(coachCode: 'SLR', coachName: 'Guard / Luggage', type: CoachType.guardSlr, totalBerths: 0),
      CoachInfo(coachCode: 'GEN', coachName: 'General', type: CoachType.general, totalBerths: 100),
      CoachInfo(coachCode: 'S1', coachName: 'Sleeper Class', type: CoachType.sleeper, totalBerths: 72),
      CoachInfo(coachCode: 'S2', coachName: 'Sleeper Class', type: CoachType.sleeper, totalBerths: 72),
      CoachInfo(coachCode: 'S3', coachName: 'Sleeper Class', type: CoachType.sleeper, totalBerths: 72),
      CoachInfo(coachCode: 'S4', coachName: 'Sleeper Class', type: CoachType.sleeper, totalBerths: 72),
      CoachInfo(coachCode: 'S5', coachName: 'Sleeper Class', type: CoachType.sleeper, totalBerths: 72),
      CoachInfo(coachCode: 'S6', coachName: 'Sleeper Class', type: CoachType.sleeper, totalBerths: 72),
      CoachInfo(coachCode: 'PC', coachName: 'Pantry Car', type: CoachType.pantry, totalBerths: 0),
      CoachInfo(coachCode: 'B1', coachName: 'AC 3 Tier', type: CoachType.ac3Tier, totalBerths: 72),
      CoachInfo(coachCode: 'B2', coachName: 'AC 3 Tier', type: CoachType.ac3Tier, totalBerths: 72),
      CoachInfo(coachCode: 'B3', coachName: 'AC 3 Tier', type: CoachType.ac3Tier, totalBerths: 72),
      CoachInfo(coachCode: 'B4', coachName: 'AC 3 Tier', type: CoachType.ac3Tier, totalBerths: 72),
      CoachInfo(coachCode: 'A1', coachName: 'AC 2 Tier', type: CoachType.ac2Tier, totalBerths: 54),
      CoachInfo(coachCode: 'A2', coachName: 'AC 2 Tier', type: CoachType.ac2Tier, totalBerths: 54),
      CoachInfo(coachCode: 'H1', coachName: 'AC 1st Class', type: CoachType.acFirstClass, totalBerths: 24),
      CoachInfo(coachCode: 'GEN', coachName: 'General', type: CoachType.general, totalBerths: 100),
      CoachInfo(coachCode: 'SLR', coachName: 'Guard / Luggage', type: CoachType.guardSlr, totalBerths: 0),
    ];
  }
}
