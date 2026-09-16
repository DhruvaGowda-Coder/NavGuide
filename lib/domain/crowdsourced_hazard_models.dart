import 'dart:convert';

/// Discrete types of crowdsourced road hazards reported by the community.
enum HazardType {
  pothole,
  flood,
  accident,
  construction,
  roadBlocked,
  poorRoad,
  other;

  String get displayName {
    switch (this) {
      case HazardType.pothole:
        return 'Pothole';
      case HazardType.flood:
        return 'Waterlogging / Flood';
      case HazardType.accident:
        return 'Accident Incident';
      case HazardType.construction:
        return 'Active Construction';
      case HazardType.roadBlocked:
        return 'Road Blocked / Closed';
      case HazardType.poorRoad:
        return 'Severe Rough Road';
      case HazardType.other:
        return 'General Hazard';
    }
  }

  /// Normalized baseline risk impact [0.0 - 1.0] contributed by this hazard type.
  double get defaultRiskWeight {
    switch (this) {
      case HazardType.pothole:
        return 0.35;
      case HazardType.flood:
        return 0.80;
      case HazardType.accident:
        return 0.70;
      case HazardType.construction:
        return 0.40;
      case HazardType.roadBlocked:
        return 1.00; // Critical hazard
      case HazardType.poorRoad:
        return 0.45;
      case HazardType.other:
        return 0.25;
    }
  }
}

/// A crowdsourced hazard report verified through community voting.
class CrowdsourcedHazardReport {
  const CrowdsourcedHazardReport({
    required this.id,
    required this.hazardType,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.roadName,
    required this.reportedAt,
    this.confirmationsCount = 1,
    this.rejectionsCount = 0,
    this.severity = 'HIGH',
    this.isUserReported = false,
  });

  final String id;
  final HazardType hazardType;
  final String description;
  final double latitude;
  final double longitude;
  final String roadName;
  final DateTime reportedAt;
  final int confirmationsCount;
  final int rejectionsCount;
  final String severity; // 'LOW', 'MEDIUM', 'HIGH', 'CRITICAL'
  final bool isUserReported;

  /// Laplace-smoothed reliability score in range [0.0 - 1.0].
  /// Higher confirmations boost score; rejections lower it.
  double get reliabilityScore {
    final total = confirmationsCount + rejectionsCount;
    if (total == 0) return 0.5;
    return (confirmationsCount + 1.0) / (total + 2.0);
  }

  /// Whether report is confirmed by community consensus (reliability >= 60% with >= 2 votes).
  bool get isCommunityConfirmed => reliabilityScore >= 0.60 && confirmationsCount >= 2;

  /// Returns a copy with updated community votes.
  CrowdsourcedHazardReport copyWith({
    int? confirmationsCount,
    int? rejectionsCount,
  }) {
    return CrowdsourcedHazardReport(
      id: id,
      hazardType: hazardType,
      description: description,
      latitude: latitude,
      longitude: longitude,
      roadName: roadName,
      reportedAt: reportedAt,
      confirmationsCount: confirmationsCount ?? this.confirmationsCount,
      rejectionsCount: rejectionsCount ?? this.rejectionsCount,
      severity: severity,
      isUserReported: isUserReported,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'hazardType': hazardType.name,
        'description': description,
        'latitude': latitude,
        'longitude': longitude,
        'roadName': roadName,
        'reportedAt': reportedAt.toIso8601String(),
        'confirmationsCount': confirmationsCount,
        'rejectionsCount': rejectionsCount,
        'severity': severity,
        'isUserReported': isUserReported,
      };

  factory CrowdsourcedHazardReport.fromJson(Map<String, dynamic> json) {
    return CrowdsourcedHazardReport(
      id: json['id'] as String,
      hazardType: HazardType.values.firstWhere(
        (e) => e.name == json['hazardType'],
        orElse: () => HazardType.other,
      ),
      description: json['description'] as String? ?? 'Community reported hazard',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      roadName: json['roadName'] as String? ?? 'Bangalore Road',
      reportedAt: DateTime.parse(json['reportedAt'] as String),
      confirmationsCount: json['confirmationsCount'] as int? ?? 1,
      rejectionsCount: json['rejectionsCount'] as int? ?? 0,
      severity: json['severity'] as String? ?? 'HIGH',
      isUserReported: json['isUserReported'] as bool? ?? false,
    );
  }
}

/// User feedback submitted upon completing a route journey.
class RouteRatingFeedback {
  const RouteRatingFeedback({
    required this.routeId,
    required this.ratingStars, // 1 to 5
    required this.perceivedSafety, // 'VERY_SAFE', 'SAFE', 'MODERATE', 'DANGEROUS'
    required this.feedbackNote,
    required this.submittedAt,
  });

  final String routeId;
  final int ratingStars;
  final String perceivedSafety;
  final String feedbackNote;
  final DateTime submittedAt;

  Map<String, dynamic> toJson() => {
        'routeId': routeId,
        'ratingStars': ratingStars,
        'perceivedSafety': perceivedSafety,
        'feedbackNote': feedbackNote,
        'submittedAt': submittedAt.toIso8601String(),
      };

  factory RouteRatingFeedback.fromJson(Map<String, dynamic> json) {
    return RouteRatingFeedback(
      routeId: json['routeId'] as String,
      ratingStars: json['ratingStars'] as int? ?? 5,
      perceivedSafety: json['perceivedSafety'] as String? ?? 'SAFE',
      feedbackNote: json['feedbackNote'] as String? ?? '',
      submittedAt: DateTime.parse(json['submittedAt'] as String),
    );
  }
}
