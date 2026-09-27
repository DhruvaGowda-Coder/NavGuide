enum CoachType {
  locoEngine,
  sleeper,
  ac3Tier,
  ac3Economy,
  ac2Tier,
  acFirstClass,
  chairCar,
  executiveChair,
  secondSitting,
  general,
  pantry,
  guardSlr,
}

enum BerthType {
  lower,
  middle,
  upper,
  sideLower,
  sideMiddle,
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
      case BerthType.sideMiddle:
        return 'Side Middle (SM)';
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

  /// Plain, simple explanation for any passenger
  String get passengerTip {
    switch (berthType) {
      case BerthType.lower:
        return 'Window-side bed at floor level. No ladder climbing needed. Ideal for seniors and families. During daytime (6 AM - 10 PM), passengers share this seat for sitting.';
      case BerthType.middle:
        return 'Bed folds down horizontally at night (10 PM - 6 AM). During daytime, it folds up as a backrest so lower berth passengers can sit comfortably.';
      case BerthType.upper:
        return 'Top bunk reached using the ladder. Best for undisturbed sleep and full privacy throughout the journey, day or night.';
      case BerthType.sideLower:
        return 'Features its own dedicated window and folding table. Converts from two daytime sitting seats into a single bed at night.';
      case BerthType.sideUpper:
        return 'Top single bunk located along the corridor. Gives good privacy and views over the walkway.';
      case BerthType.sideMiddle:
        return 'Middle side bunk in 3-Tier Economy. Folds down at night.';
      case BerthType.window:
        return 'Direct window-side seat with picturesque outdoor views throughout your ride.';
      case BerthType.middleSeat:
        return 'Middle seat placed between the window and aisle seats.';
      case BerthType.aisle:
        return 'Aisle seat with extra leg space and easy access to walk without disturbing others.';
      case BerthType.cabin:
        return 'Private lockable First Class compartment with premium bedding.';
    }
  }

  String get comfortTag {
    switch (berthType) {
      case BerthType.lower:
        return 'Window • No Climbing';
      case BerthType.middle:
        return 'Folds at 10 PM';
      case BerthType.upper:
        return 'Quiet • Private Top';
      case BerthType.sideLower:
        return 'Window + Table';
      case BerthType.sideUpper:
        return 'Corridor Single';
      case BerthType.sideMiddle:
        return 'Side Berth';
      case BerthType.window:
        return 'Scenic Window';
      case BerthType.middleSeat:
        return 'Center Seat';
      case BerthType.aisle:
        return 'Aisle Access';
      case BerthType.cabin:
        return 'Private Cabin';
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

  String get shortLabel {
    switch (type) {
      case CoachType.locoEngine:
        return 'Engine';
      case CoachType.sleeper:
        return 'Sleeper';
      case CoachType.ac3Tier:
        return '3rd AC';
      case CoachType.ac3Economy:
        return '3-Econ';
      case CoachType.ac2Tier:
        return '2nd AC';
      case CoachType.acFirstClass:
        return '1st AC';
      case CoachType.chairCar:
        return 'Chair Car';
      case CoachType.executiveChair:
        return 'Exec CC';
      case CoachType.secondSitting:
        return '2S Seater';
      case CoachType.general:
        return 'General';
      case CoachType.pantry:
        return 'Pantry';
      case CoachType.guardSlr:
        return 'Guard/SLR';
    }
  }

  String get typeDescription {
    switch (type) {
      case CoachType.locoEngine:
        return 'Locomotive Engine';
      case CoachType.sleeper:
        return 'Sleeper Class (Non-AC)';
      case CoachType.ac3Tier:
        return 'AC 3 Tier (3A)';
      case CoachType.ac3Economy:
        return 'AC 3 Tier Economy (3E)';
      case CoachType.ac2Tier:
        return 'AC 2 Tier (2A)';
      case CoachType.acFirstClass:
        return 'AC First Class (1A)';
      case CoachType.chairCar:
        return 'AC Chair Car (CC)';
      case CoachType.executiveChair:
        return 'Executive Chair Car (EC)';
      case CoachType.secondSitting:
        return 'Second Sitting (2S)';
      case CoachType.general:
        return 'General Unreserved (GEN)';
      case CoachType.pantry:
        return 'Pantry Car (Food & Pantry)';
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
    } else if (type == CoachType.ac3Economy) {
      // AC 3 Tier Economy has 83 berths (Side Middle present in some rakes)
      final rem = seatNumber % 9;
      final bay = ((seatNumber - 1) ~/ 9) + 1;
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
        case 8:
          bType = BerthType.sideMiddle;
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
        label: '$seatNumber (${isWin ? "Window" : "Bay $bay"})',
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
    } else if (type == CoachType.secondSitting) {
      // 2S (Second Sitting - 108 seats per coach, 3x3 layout)
      final mod = seatNumber % 6;
      final row = ((seatNumber - 1) ~/ 6) + 1;
      BerthType bType;
      bool isWin = false;

      switch (mod) {
        case 1:
        case 0:
          bType = BerthType.window;
          isWin = true;
          break;
        case 2:
        case 5:
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

  /// Returns authentic Indian Railways coach composition for any train
  List<CoachInfo> getCompositionForTrain(
    String trainNumber, {
    String? trainType,
    String? trainName,
  }) {
    final num = trainNumber.trim();
    final type = (trainType ?? '').toLowerCase();
    final name = (trainName ?? '').toLowerCase();

    // ── 1. VANDE BHARAT EXPRESS (Trainsets, 20xxx / 22xxx) ────────────────────
    if (num.startsWith('20') || type.contains('vande') || name.contains('vande')) {
      // 8-Coach vs 16-Coach standard IR Vande Bharat rakes
      final is16Car = num.contains('20608') || num.contains('20607') || num.contains('22436') || num.contains('22435') || num.contains('20704');
      if (is16Car) {
        return const [
          CoachInfo(coachCode: 'DTC', coachName: 'Front Cab (C1)', type: CoachType.chairCar, totalBerths: 44),
          CoachInfo(coachCode: 'C2', coachName: 'Motor Coach (CC)', type: CoachType.chairCar, totalBerths: 78),
          CoachInfo(coachCode: 'C3', coachName: 'Trailer Coach (CC)', type: CoachType.chairCar, totalBerths: 78),
          CoachInfo(coachCode: 'C4', coachName: 'Motor Coach (CC)', type: CoachType.chairCar, totalBerths: 78),
          CoachInfo(coachCode: 'C5', coachName: 'Trailer Coach (CC)', type: CoachType.chairCar, totalBerths: 78),
          CoachInfo(coachCode: 'C6', coachName: 'Motor Coach (CC)', type: CoachType.chairCar, totalBerths: 78),
          CoachInfo(coachCode: 'C7', coachName: 'Trailer Coach (CC)', type: CoachType.chairCar, totalBerths: 78),
          CoachInfo(coachCode: 'EC1', coachName: 'Executive Coach', type: CoachType.executiveChair, totalBerths: 52),
          CoachInfo(coachCode: 'EC2', coachName: 'Executive Coach', type: CoachType.executiveChair, totalBerths: 52),
          CoachInfo(coachCode: 'C8', coachName: 'Trailer Coach (CC)', type: CoachType.chairCar, totalBerths: 78),
          CoachInfo(coachCode: 'C9', coachName: 'Motor Coach (CC)', type: CoachType.chairCar, totalBerths: 78),
          CoachInfo(coachCode: 'C10', coachName: 'Trailer Coach (CC)', type: CoachType.chairCar, totalBerths: 78),
          CoachInfo(coachCode: 'C11', coachName: 'Motor Coach (CC)', type: CoachType.chairCar, totalBerths: 78),
          CoachInfo(coachCode: 'C12', coachName: 'Trailer Coach (CC)', type: CoachType.chairCar, totalBerths: 78),
          CoachInfo(coachCode: 'C13', coachName: 'Motor Coach (CC)', type: CoachType.chairCar, totalBerths: 78),
          CoachInfo(coachCode: 'NDTC', coachName: 'Rear Cab (C14)', type: CoachType.chairCar, totalBerths: 44),
        ];
      } else {
        // 8-car Vande Bharat rake
        return const [
          CoachInfo(coachCode: 'DTC', coachName: 'Driving Cab (C1)', type: CoachType.chairCar, totalBerths: 44),
          CoachInfo(coachCode: 'C2', coachName: 'Motor Coach (CC)', type: CoachType.chairCar, totalBerths: 78),
          CoachInfo(coachCode: 'C3', coachName: 'Trailer Coach (CC)', type: CoachType.chairCar, totalBerths: 78),
          CoachInfo(coachCode: 'EC1', coachName: 'Executive Coach', type: CoachType.executiveChair, totalBerths: 52),
          CoachInfo(coachCode: 'C4', coachName: 'Motor Coach (CC)', type: CoachType.chairCar, totalBerths: 78),
          CoachInfo(coachCode: 'C5', coachName: 'Trailer Coach (CC)', type: CoachType.chairCar, totalBerths: 78),
          CoachInfo(coachCode: 'C6', coachName: 'Motor Coach (CC)', type: CoachType.chairCar, totalBerths: 78),
          CoachInfo(coachCode: 'NDTC', coachName: 'Rear Cab (C7)', type: CoachType.chairCar, totalBerths: 44),
        ];
      }
    }

    // ── 2. SHATABDI EXPRESS (120xx series) ────────────────────────────────────
    if (num.startsWith('120') || type.contains('shatabdi') || name.contains('shatabdi')) {
      if (type.contains('jan') || name.contains('jan')) {
        // Jan Shatabdi: D1-D10 (2S) + C1-C2 (CC)
        return const [
          CoachInfo(coachCode: 'ENG', coachName: 'Locomotive', type: CoachType.locoEngine, totalBerths: 0),
          CoachInfo(coachCode: 'DL1', coachName: 'Guard / Luggage', type: CoachType.guardSlr, totalBerths: 0),
          CoachInfo(coachCode: 'D1', coachName: 'Second Sitting', type: CoachType.secondSitting, totalBerths: 108),
          CoachInfo(coachCode: 'D2', coachName: 'Second Sitting', type: CoachType.secondSitting, totalBerths: 108),
          CoachInfo(coachCode: 'D3', coachName: 'Second Sitting', type: CoachType.secondSitting, totalBerths: 108),
          CoachInfo(coachCode: 'D4', coachName: 'Second Sitting', type: CoachType.secondSitting, totalBerths: 108),
          CoachInfo(coachCode: 'C1', coachName: 'AC Chair Car', type: CoachType.chairCar, totalBerths: 73),
          CoachInfo(coachCode: 'C2', coachName: 'AC Chair Car', type: CoachType.chairCar, totalBerths: 73),
          CoachInfo(coachCode: 'D5', coachName: 'Second Sitting', type: CoachType.secondSitting, totalBerths: 108),
          CoachInfo(coachCode: 'D6', coachName: 'Second Sitting', type: CoachType.secondSitting, totalBerths: 108),
          CoachInfo(coachCode: 'D7', coachName: 'Second Sitting', type: CoachType.secondSitting, totalBerths: 108),
          CoachInfo(coachCode: 'DL2', coachName: 'Guard / Luggage', type: CoachType.guardSlr, totalBerths: 0),
        ];
      }

      // Standard All-AC Shatabdi
      return const [
        CoachInfo(coachCode: 'ENG', coachName: 'Locomotive', type: CoachType.locoEngine, totalBerths: 0),
        CoachInfo(coachCode: 'EOG', coachName: 'Power Car', type: CoachType.guardSlr, totalBerths: 0),
        CoachInfo(coachCode: 'C1', coachName: 'Chair Car', type: CoachType.chairCar, totalBerths: 78),
        CoachInfo(coachCode: 'C2', coachName: 'Chair Car', type: CoachType.chairCar, totalBerths: 78),
        CoachInfo(coachCode: 'C3', coachName: 'Chair Car', type: CoachType.chairCar, totalBerths: 78),
        CoachInfo(coachCode: 'C4', coachName: 'Chair Car', type: CoachType.chairCar, totalBerths: 78),
        CoachInfo(coachCode: 'E1', coachName: 'Exec Chair Car', type: CoachType.executiveChair, totalBerths: 52),
        CoachInfo(coachCode: 'E2', coachName: 'Exec Chair Car', type: CoachType.executiveChair, totalBerths: 52),
        CoachInfo(coachCode: 'C5', coachName: 'Chair Car', type: CoachType.chairCar, totalBerths: 78),
        CoachInfo(coachCode: 'C6', coachName: 'Chair Car', type: CoachType.chairCar, totalBerths: 78),
        CoachInfo(coachCode: 'C7', coachName: 'Chair Car', type: CoachType.chairCar, totalBerths: 78),
        CoachInfo(coachCode: 'EOG', coachName: 'Power Car', type: CoachType.guardSlr, totalBerths: 0),
      ];
    }

    // ── 3. RAJDHANI & TEJAS RAJDHANI (124xx, 123xx, 129xx, 22691) ─────────────
    if (type.contains('rajdhani') || name.contains('rajdhani') || num.startsWith('124') || num.startsWith('123') || num == '22691' || num == '22692') {
      return const [
        CoachInfo(coachCode: 'ENG', coachName: 'Locomotive', type: CoachType.locoEngine, totalBerths: 0),
        CoachInfo(coachCode: 'EOG', coachName: 'Power Car', type: CoachType.guardSlr, totalBerths: 0),
        CoachInfo(coachCode: 'B1', coachName: 'AC 3 Tier', type: CoachType.ac3Tier, totalBerths: 72),
        CoachInfo(coachCode: 'B2', coachName: 'AC 3 Tier', type: CoachType.ac3Tier, totalBerths: 72),
        CoachInfo(coachCode: 'B3', coachName: 'AC 3 Tier', type: CoachType.ac3Tier, totalBerths: 72),
        CoachInfo(coachCode: 'B4', coachName: 'AC 3 Tier', type: CoachType.ac3Tier, totalBerths: 72),
        CoachInfo(coachCode: 'M1', coachName: 'AC 3 Economy', type: CoachType.ac3Economy, totalBerths: 83),
        CoachInfo(coachCode: 'M2', coachName: 'AC 3 Economy', type: CoachType.ac3Economy, totalBerths: 83),
        CoachInfo(coachCode: 'PC', coachName: 'Hot Buffet Pantry', type: CoachType.pantry, totalBerths: 0),
        CoachInfo(coachCode: 'B5', coachName: 'AC 3 Tier', type: CoachType.ac3Tier, totalBerths: 72),
        CoachInfo(coachCode: 'B6', coachName: 'AC 3 Tier', type: CoachType.ac3Tier, totalBerths: 72),
        CoachInfo(coachCode: 'A1', coachName: 'AC 2 Tier', type: CoachType.ac2Tier, totalBerths: 54),
        CoachInfo(coachCode: 'A2', coachName: 'AC 2 Tier', type: CoachType.ac2Tier, totalBerths: 54),
        CoachInfo(coachCode: 'A3', coachName: 'AC 2 Tier', type: CoachType.ac2Tier, totalBerths: 54),
        CoachInfo(coachCode: 'H1', coachName: 'AC 1st Class', type: CoachType.acFirstClass, totalBerths: 24),
        CoachInfo(coachCode: 'EOG', coachName: 'Power Car', type: CoachType.guardSlr, totalBerths: 0),
      ];
    }

    // ── 4. DURONTO EXPRESS (122xx series) ─────────────────────────────────────
    if (type.contains('duronto') || name.contains('duronto') || num.startsWith('122')) {
      return const [
        CoachInfo(coachCode: 'ENG', coachName: 'Locomotive', type: CoachType.locoEngine, totalBerths: 0),
        CoachInfo(coachCode: 'EOG', coachName: 'Power Car', type: CoachType.guardSlr, totalBerths: 0),
        CoachInfo(coachCode: 'S1', coachName: 'Sleeper Class', type: CoachType.sleeper, totalBerths: 72),
        CoachInfo(coachCode: 'S2', coachName: 'Sleeper Class', type: CoachType.sleeper, totalBerths: 72),
        CoachInfo(coachCode: 'S3', coachName: 'Sleeper Class', type: CoachType.sleeper, totalBerths: 72),
        CoachInfo(coachCode: 'PC', coachName: 'Pantry Car', type: CoachType.pantry, totalBerths: 0),
        CoachInfo(coachCode: 'B1', coachName: 'AC 3 Tier', type: CoachType.ac3Tier, totalBerths: 72),
        CoachInfo(coachCode: 'B2', coachName: 'AC 3 Tier', type: CoachType.ac3Tier, totalBerths: 72),
        CoachInfo(coachCode: 'B3', coachName: 'AC 3 Tier', type: CoachType.ac3Tier, totalBerths: 72),
        CoachInfo(coachCode: 'A1', coachName: 'AC 2 Tier', type: CoachType.ac2Tier, totalBerths: 54),
        CoachInfo(coachCode: 'A2', coachName: 'AC 2 Tier', type: CoachType.ac2Tier, totalBerths: 54),
        CoachInfo(coachCode: 'H1', coachName: 'AC 1st Class', type: CoachType.acFirstClass, totalBerths: 24),
        CoachInfo(coachCode: 'EOG', coachName: 'Power Car', type: CoachType.guardSlr, totalBerths: 0),
      ];
    }

    // ── 5. GARIB RATH EXPRESS ─────────────────────────────────────────────────
    if (type.contains('garib') || name.contains('garib')) {
      return const [
        CoachInfo(coachCode: 'ENG', coachName: 'Locomotive', type: CoachType.locoEngine, totalBerths: 0),
        CoachInfo(coachCode: 'EOG', coachName: 'Power Car', type: CoachType.guardSlr, totalBerths: 0),
        CoachInfo(coachCode: 'G1', coachName: '3AC High Capacity', type: CoachType.ac3Economy, totalBerths: 81),
        CoachInfo(coachCode: 'G2', coachName: '3AC High Capacity', type: CoachType.ac3Economy, totalBerths: 81),
        CoachInfo(coachCode: 'G3', coachName: '3AC High Capacity', type: CoachType.ac3Economy, totalBerths: 81),
        CoachInfo(coachCode: 'G4', coachName: '3AC High Capacity', type: CoachType.ac3Economy, totalBerths: 81),
        CoachInfo(coachCode: 'G5', coachName: '3AC High Capacity', type: CoachType.ac3Economy, totalBerths: 81),
        CoachInfo(coachCode: 'G6', coachName: '3AC High Capacity', type: CoachType.ac3Economy, totalBerths: 81),
        CoachInfo(coachCode: 'G7', coachName: '3AC High Capacity', type: CoachType.ac3Economy, totalBerths: 81),
        CoachInfo(coachCode: 'G8', coachName: '3AC High Capacity', type: CoachType.ac3Economy, totalBerths: 81),
        CoachInfo(coachCode: 'EOG', coachName: 'Power Car', type: CoachType.guardSlr, totalBerths: 0),
      ];
    }

    // ── 6. MEMU & SUBURBAN PASSENGER (56xxx, 66xxx, 06xxx) ────────────────────
    if (type.contains('memu') || type.contains('passenger') || name.contains('memu') || name.contains('passenger') || num.startsWith('56') || num.startsWith('66') || num.startsWith('06')) {
      return const [
        CoachInfo(coachCode: 'DMC', coachName: 'Driving Motor Coach', type: CoachType.secondSitting, totalBerths: 80),
        CoachInfo(coachCode: 'TC1', coachName: 'Trailer Coach', type: CoachType.secondSitting, totalBerths: 108),
        CoachInfo(coachCode: 'TC2', coachName: 'Trailer Coach', type: CoachType.secondSitting, totalBerths: 108),
        CoachInfo(coachCode: 'TC3', coachName: 'Trailer Coach (Ladies)', type: CoachType.secondSitting, totalBerths: 108),
        CoachInfo(coachCode: 'TC4', coachName: 'Trailer Coach', type: CoachType.secondSitting, totalBerths: 108),
        CoachInfo(coachCode: 'TC5', coachName: 'Trailer Coach', type: CoachType.secondSitting, totalBerths: 108),
        CoachInfo(coachCode: 'TC6', coachName: 'Trailer Coach', type: CoachType.secondSitting, totalBerths: 108),
        CoachInfo(coachCode: 'NDMC', coachName: 'Rear Driving Cab', type: CoachType.secondSitting, totalBerths: 80),
      ];
    }

    // ── 7. STANDARD SUPERFAST / MAIL / EXPRESS LHB RAKE (Default) ─────────────
    // Most popular Indian Railways configuration (e.g. 12657 SBC-MAS Mail, 16589 Rani Chennamma, Karnataka Express, etc.)
    return const [
      CoachInfo(coachCode: 'ENG', coachName: 'Locomotive (WAP-7)', type: CoachType.locoEngine, totalBerths: 0),
      CoachInfo(coachCode: 'SLR', coachName: 'Luggage / Guard', type: CoachType.guardSlr, totalBerths: 0),
      CoachInfo(coachCode: 'GS1', coachName: 'General Unreserved', type: CoachType.general, totalBerths: 100),
      CoachInfo(coachCode: 'GS2', coachName: 'General Unreserved', type: CoachType.general, totalBerths: 100),
      CoachInfo(coachCode: 'S1', coachName: 'Sleeper Class', type: CoachType.sleeper, totalBerths: 72),
      CoachInfo(coachCode: 'S2', coachName: 'Sleeper Class', type: CoachType.sleeper, totalBerths: 72),
      CoachInfo(coachCode: 'S3', coachName: 'Sleeper Class', type: CoachType.sleeper, totalBerths: 72),
      CoachInfo(coachCode: 'S4', coachName: 'Sleeper Class', type: CoachType.sleeper, totalBerths: 72),
      CoachInfo(coachCode: 'S5', coachName: 'Sleeper Class', type: CoachType.sleeper, totalBerths: 72),
      CoachInfo(coachCode: 'S6', coachName: 'Sleeper Class', type: CoachType.sleeper, totalBerths: 72),
      CoachInfo(coachCode: 'PC', coachName: 'Pantry Car', type: CoachType.pantry, totalBerths: 0),
      CoachInfo(coachCode: 'M1', coachName: 'AC 3 Economy', type: CoachType.ac3Economy, totalBerths: 83),
      CoachInfo(coachCode: 'B1', coachName: 'AC 3 Tier', type: CoachType.ac3Tier, totalBerths: 72),
      CoachInfo(coachCode: 'B2', coachName: 'AC 3 Tier', type: CoachType.ac3Tier, totalBerths: 72),
      CoachInfo(coachCode: 'B3', coachName: 'AC 3 Tier', type: CoachType.ac3Tier, totalBerths: 72),
      CoachInfo(coachCode: 'B4', coachName: 'AC 3 Tier', type: CoachType.ac3Tier, totalBerths: 72),
      CoachInfo(coachCode: 'A1', coachName: 'AC 2 Tier', type: CoachType.ac2Tier, totalBerths: 54),
      CoachInfo(coachCode: 'A2', coachName: 'AC 2 Tier', type: CoachType.ac2Tier, totalBerths: 54),
      CoachInfo(coachCode: 'H1', coachName: 'AC 1st Class', type: CoachType.acFirstClass, totalBerths: 24),
      CoachInfo(coachCode: 'GS3', coachName: 'General Unreserved', type: CoachType.general, totalBerths: 100),
      CoachInfo(coachCode: 'SLR', coachName: 'Guard / Divyangjan', type: CoachType.guardSlr, totalBerths: 0),
    ];
  }
}
