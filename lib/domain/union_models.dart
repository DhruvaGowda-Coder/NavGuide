enum UnionMemberStatus {
  pending,
  accepted,
  rejected,
}

enum VehicleCategory {
  bike,
  car,
  bicycle,
  soloWalker,
  other;

  String get displayName {
    switch (this) {
      case VehicleCategory.bike:
        return 'Motorcycle / Scooter';
      case VehicleCategory.car:
        return 'Car / SUV';
      case VehicleCategory.bicycle:
        return 'Bicycle / Cycling';
      case VehicleCategory.soloWalker:
        return 'Solo Traveler';
      case VehicleCategory.other:
        return 'General Vehicle';
    }
  }
}

class UnionMember {
  final String id;
  final String name;
  final String mobile;
  final String email;
  final String vehicle;
  final VehicleCategory category;
  final UnionMemberStatus status;
  final DateTime joinedAt;

  const UnionMember({
    required this.id,
    required this.name,
    required this.mobile,
    required this.email,
    required this.vehicle,
    required this.category,
    required this.status,
    required this.joinedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mobile': mobile,
        'email': email,
        'vehicle': vehicle,
        'category': category.name,
        'status': status.name,
        'joinedAt': joinedAt.toIso8601String(),
      };

  factory UnionMember.fromJson(Map<String, dynamic> json) => UnionMember(
        id: json['id'] as String,
        name: json['name'] as String,
        mobile: json['mobile'] as String,
        email: json['email'] as String,
        vehicle: json['vehicle'] as String? ?? 'Vehicle',
        category: VehicleCategory.values.firstWhere(
          (c) => c.name == json['category'],
          orElse: () => VehicleCategory.bike,
        ),
        status: UnionMemberStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => UnionMemberStatus.accepted,
        ),
        joinedAt: DateTime.tryParse(json['joinedAt'] as String? ?? '') ?? DateTime.now(),
      );
}

class TravelUnionGroup {
  final String id;
  final String title;
  final String fromLocation;
  final String toLocation;
  final String departureDateStr;
  final VehicleCategory category;
  final String hostName;
  final String hostMobile;
  final String hostEmail;
  final String joinCode;
  final List<UnionMember> members;
  final int maxMembers;
  final DateTime createdAt;

  const TravelUnionGroup({
    required this.id,
    required this.title,
    required this.fromLocation,
    required this.toLocation,
    required this.departureDateStr,
    required this.category,
    required this.hostName,
    required this.hostMobile,
    required this.hostEmail,
    required this.joinCode,
    required this.members,
    this.maxMembers = 10,
    required this.createdAt,
  });

  List<UnionMember> get acceptedMembers =>
      members.where((m) => m.status == UnionMemberStatus.accepted).toList();

  List<UnionMember> get pendingRequests =>
      members.where((m) => m.status == UnionMemberStatus.pending).toList();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'fromLocation': fromLocation,
        'toLocation': toLocation,
        'departureDateStr': departureDateStr,
        'category': category.name,
        'hostName': hostName,
        'hostMobile': hostMobile,
        'hostEmail': hostEmail,
        'joinCode': joinCode,
        'members': members.map((m) => m.toJson()).toList(),
        'maxMembers': maxMembers,
        'createdAt': createdAt.toIso8601String(),
      };

  factory TravelUnionGroup.fromJson(Map<String, dynamic> json) => TravelUnionGroup(
        id: json['id'] as String,
        title: json['title'] as String,
        fromLocation: json['fromLocation'] as String,
        toLocation: json['toLocation'] as String,
        departureDateStr: json['departureDateStr'] as String? ?? 'Today',
        category: VehicleCategory.values.firstWhere(
          (c) => c.name == json['category'],
          orElse: () => VehicleCategory.bike,
        ),
        hostName: json['hostName'] as String,
        hostMobile: json['hostMobile'] as String,
        hostEmail: json['hostEmail'] as String,
        joinCode: json['joinCode'] as String,
        members: (json['members'] as List<dynamic>?)
                ?.map((m) => UnionMember.fromJson(m as Map<String, dynamic>))
                .toList() ??
            [],
        maxMembers: json['maxMembers'] as int? ?? 10,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      );
}
