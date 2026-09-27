enum UnionMemberStatus {
  pending,
  accepted,
  rejected,
}

enum GroupMembershipStatus {
  admin,
  accepted,
  pending,
  none,
}

enum VehicleCategory {
  allVehicles,
  bike,
  car,
  bus,
  truck,
  bicycle,
  soloWalker,
  other;

  String get displayName {
    switch (this) {
      case VehicleCategory.allVehicles:
        return 'All Vehicles (Mixed Convoy)';
      case VehicleCategory.bike:
        return 'Motorcycle / Scooter';
      case VehicleCategory.car:
        return 'Car / SUV';
      case VehicleCategory.bus:
        return 'Bus / Mini-Bus';
      case VehicleCategory.truck:
        return 'Truck / Heavy Vehicle';
      case VehicleCategory.bicycle:
        return 'Bicycle / Cycling';
      case VehicleCategory.soloWalker:
        return 'Solo Traveler';
      case VehicleCategory.other:
        return 'General Vehicle';
    }
  }

  String get shortLabel {
    switch (this) {
      case VehicleCategory.allVehicles:
        return 'Mixed Convoy';
      case VehicleCategory.bike:
        return 'Bike / Scooter';
      case VehicleCategory.car:
        return 'Car / SUV';
      case VehicleCategory.bus:
        return 'Bus / Van';
      case VehicleCategory.truck:
        return 'Truck';
      case VehicleCategory.bicycle:
        return 'Bicycle';
      case VehicleCategory.soloWalker:
        return 'Solo Walker';
      case VehicleCategory.other:
        return 'General';
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

class UnionChatMessage {
  final String id;
  final String senderName;
  final String senderMobile;
  final String text;
  final DateTime timestamp;
  final bool isHost;

  const UnionChatMessage({
    required this.id,
    required this.senderName,
    required this.senderMobile,
    required this.text,
    required this.timestamp,
    this.isHost = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderName': senderName,
        'senderMobile': senderMobile,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
        'isHost': isHost,
      };

  factory UnionChatMessage.fromJson(Map<String, dynamic> json) => UnionChatMessage(
        id: json['id'] as String? ?? 'msg_${DateTime.now().millisecondsSinceEpoch}',
        senderName: json['senderName'] as String? ?? 'Rider',
        senderMobile: json['senderMobile'] as String? ?? '',
        text: json['text'] as String? ?? '',
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
        isHost: json['isHost'] as bool? ?? false,
      );
}

class TravelUnionGroup {
  final String id;
  final String title;
  final String slogan;
  final String fromLocation;
  final String toLocation;
  final String viaHighway;
  final String departureDateStr;
  final String estimatedDuration;
  final int estimatedDistanceKm;
  final String routeType;
  final VehicleCategory category;
  final String statusTag;
  final List<String> tags;
  final String description;
  final String hostName;
  final String hostMobile;
  final String hostEmail;
  final double hostRating;
  final int hostRidesCount;
  final String hostBio;
  final String imageUrl;
  final String joinCode;
  final List<UnionMember> members;
  final List<UnionChatMessage> chatMessages;
  // Group star rating (average of all members who rated)
  final double groupRating;
  final int memberRatingsCount;
  final List<ConvoyLiveRider> liveRiders;
  final List<ConvoyEmergencyAlert> activeAlerts;
  final int maxMembers;
  final bool isPublicFeed;
  final DateTime createdAt;

  const TravelUnionGroup({
    required this.id,
    required this.title,
    this.slogan = 'Ride Together • Explore More',
    required this.fromLocation,
    required this.toLocation,
    this.viaHighway = 'Direct Route',
    required this.departureDateStr,
    this.estimatedDuration = '2-3 hrs',
    this.estimatedDistanceKm = 100,
    this.routeType = 'Highway',
    required this.category,
    this.statusTag = 'Upcoming',
    this.tags = const ['Group Ride', 'Highway'],
    this.description = 'Join our convoy for a safe, coordinated journey.',
    required this.hostName,
    required this.hostMobile,
    required this.hostEmail,
    this.hostRating = 0,
    this.hostRidesCount = 0,
    this.hostBio = 'Passionate Rider | Explorer',
    this.imageUrl = '',
    required this.joinCode,
    required this.members,
    this.chatMessages = const [],
    this.groupRating = 0.0,
    this.memberRatingsCount = 0,
    this.liveRiders = const [],
    this.activeAlerts = const [],
    this.maxMembers = 10,
    this.isPublicFeed = true,
    required this.createdAt,
  });

  List<UnionMember> get acceptedMembers =>
      members.where((m) => m.status == UnionMemberStatus.accepted).toList();

  List<UnionMember> get pendingRequests =>
      members.where((m) => m.status == UnionMemberStatus.pending).toList();

  bool get isFull => acceptedMembers.length >= maxMembers;

  bool get isPopular => hostRating >= 4.5 || acceptedMembers.length >= 2 || tags.contains('Popular');

  bool get hasActiveEmergency => activeAlerts.any((a) => !a.isResolved);

  ConvoyEmergencyAlert? get latestEmergency =>
      activeAlerts.where((a) => !a.isResolved).lastOrNull;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'slogan': slogan,
        'fromLocation': fromLocation,
        'toLocation': toLocation,
        'viaHighway': viaHighway,
        'departureDateStr': departureDateStr,
        'estimatedDuration': estimatedDuration,
        'estimatedDistanceKm': estimatedDistanceKm,
        'routeType': routeType,
        'category': category.name,
        'statusTag': statusTag,
        'tags': tags,
        'description': description,
        'hostName': hostName,
        'hostMobile': hostMobile,
        'hostEmail': hostEmail,
        'hostRating': hostRating,
        'hostRidesCount': hostRidesCount,
        'hostBio': hostBio,
        'imageUrl': imageUrl,
        'joinCode': joinCode,
        'members': members.map((m) => m.toJson()).toList(),
        'chatMessages': chatMessages.map((c) => c.toJson()).toList(),
        'liveRiders': liveRiders.map((r) => r.toJson()).toList(),
        'activeAlerts': activeAlerts.map((a) => a.toJson()).toList(),
        'maxMembers': maxMembers,
        'isPublicFeed': isPublicFeed,
        'createdAt': createdAt.toIso8601String(),
        'groupRating': groupRating,
        'memberRatingsCount': memberRatingsCount,
      };

  factory TravelUnionGroup.fromJson(Map<String, dynamic> json) => TravelUnionGroup(
        id: json['id'] as String,
        title: json['title'] as String,
        slogan: json['slogan'] as String? ?? 'Ride Beyond Limits',
        fromLocation: json['fromLocation'] as String,
        toLocation: json['toLocation'] as String,
        viaHighway: json['viaHighway'] as String? ?? '',
        departureDateStr: json['departureDateStr'] as String? ?? 'Today',
        estimatedDuration: json['estimatedDuration'] as String? ?? '3-4 hrs',
        estimatedDistanceKm: (json['estimatedDistanceKm'] as num?)?.toInt() ?? 120,
        routeType: json['routeType'] as String? ?? 'Highway',
        category: VehicleCategory.values.firstWhere(
          (c) => c.name == json['category'],
          orElse: () => VehicleCategory.bike,
        ),
        statusTag: json['statusTag'] as String? ?? 'Upcoming',
        tags: (json['tags'] as List<dynamic>?)?.map((t) => t.toString()).toList() ??
            ['Group Ride', 'Highway'],
        description: json['description'] as String? ??
            'A relaxed group ride. All riders are welcome. Let us ride safe and enjoy the journey!',
        hostName: json['hostName'] as String,
        hostMobile: json['hostMobile'] as String,
        hostEmail: json['hostEmail'] as String,
        hostRating: (json['hostRating'] as num?)?.toDouble() ?? 4.8,
        hostRidesCount: (json['hostRidesCount'] as num?)?.toInt() ?? 12,
        hostBio: json['hostBio'] as String? ?? 'Passionate Rider | Explorer',
        imageUrl: json['imageUrl'] as String? ?? '',
        joinCode: json['joinCode'] as String,
        members: (json['members'] as List<dynamic>?)
                ?.map((m) => UnionMember.fromJson(m as Map<String, dynamic>))
                .toList() ??
            [],
        chatMessages: (json['chatMessages'] as List<dynamic>?)
                ?.map((c) => UnionChatMessage.fromJson(c as Map<String, dynamic>))
                .toList() ??
            [],
        liveRiders: (json['liveRiders'] as List<dynamic>?)
                ?.map((r) => ConvoyLiveRider.fromJson(r as Map<String, dynamic>))
                .toList() ??
            [],
        activeAlerts: (json['activeAlerts'] as List<dynamic>?)
                ?.map((a) => ConvoyEmergencyAlert.fromJson(a as Map<String, dynamic>))
                .toList() ??
            [],
        maxMembers: json['maxMembers'] as int? ?? 10,
        isPublicFeed: json['isPublicFeed'] as bool? ?? true,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        groupRating: (json['groupRating'] as num?)?.toDouble() ?? 0.0,
        memberRatingsCount: (json['memberRatingsCount'] as num?)?.toInt() ?? 0,
      );

  TravelUnionGroup copyWith({
    String? id,
    String? title,
    String? slogan,
    String? fromLocation,
    String? toLocation,
    String? viaHighway,
    String? departureDateStr,
    String? estimatedDuration,
    int? estimatedDistanceKm,
    String? routeType,
    VehicleCategory? category,
    String? statusTag,
    List<String>? tags,
    String? description,
    String? hostName,
    String? hostMobile,
    String? hostEmail,
    double? hostRating,
    double? groupRating,
    int? memberRatingsCount,
    int? hostRidesCount,
    String? hostBio,
    String? imageUrl,
    String? joinCode,
    List<UnionMember>? members,
    List<UnionChatMessage>? chatMessages,
    List<ConvoyLiveRider>? liveRiders,
    List<ConvoyEmergencyAlert>? activeAlerts,
    int? maxMembers,
    bool? isPublicFeed,
    DateTime? createdAt,
  }) {
    return TravelUnionGroup(
      id: id ?? this.id,
      title: title ?? this.title,
      slogan: slogan ?? this.slogan,
      fromLocation: fromLocation ?? this.fromLocation,
      toLocation: toLocation ?? this.toLocation,
      viaHighway: viaHighway ?? this.viaHighway,
      departureDateStr: departureDateStr ?? this.departureDateStr,
      estimatedDuration: estimatedDuration ?? this.estimatedDuration,
      estimatedDistanceKm: estimatedDistanceKm ?? this.estimatedDistanceKm,
      routeType: routeType ?? this.routeType,
      category: category ?? this.category,
      statusTag: statusTag ?? this.statusTag,
      tags: tags ?? this.tags,
      description: description ?? this.description,
      hostName: hostName ?? this.hostName,
      hostMobile: hostMobile ?? this.hostMobile,
      hostEmail: hostEmail ?? this.hostEmail,
      hostRating: hostRating ?? this.hostRating,
      hostRidesCount: hostRidesCount ?? this.hostRidesCount,
      hostBio: hostBio ?? this.hostBio,
      imageUrl: imageUrl ?? this.imageUrl,
      joinCode: joinCode ?? this.joinCode,
      members: members ?? this.members,
      chatMessages: chatMessages ?? this.chatMessages,
      liveRiders: liveRiders ?? this.liveRiders,
      activeAlerts: activeAlerts ?? this.activeAlerts,
      maxMembers: maxMembers ?? this.maxMembers,
      isPublicFeed: isPublicFeed ?? this.isPublicFeed,
      createdAt: createdAt ?? this.createdAt,
      groupRating: groupRating ?? this.groupRating,
      memberRatingsCount: memberRatingsCount ?? this.memberRatingsCount,
    );
  }
}

class ConvoyLiveRider {
  final String id;
  final String name;
  final String mobile;
  final String vehicle;
  final VehicleCategory category;
  final double latitude;
  final double longitude;
  final double speedKmph;
  final double heading;
  final bool isHost;
  final bool isEmergency;
  final String emergencyReason;
  final DateTime lastUpdated;

  const ConvoyLiveRider({
    required this.id,
    required this.name,
    required this.mobile,
    this.vehicle = 'Bike',
    this.category = VehicleCategory.bike,
    required this.latitude,
    required this.longitude,
    this.speedKmph = 0.0,
    this.heading = 0.0,
    this.isHost = false,
    this.isEmergency = false,
    this.emergencyReason = '',
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mobile': mobile,
        'vehicle': vehicle,
        'category': category.name,
        'latitude': latitude,
        'longitude': longitude,
        'speedKmph': speedKmph,
        'heading': heading,
        'isHost': isHost,
        'isEmergency': isEmergency,
        'emergencyReason': emergencyReason,
        'lastUpdated': lastUpdated.toIso8601String(),
      };

  factory ConvoyLiveRider.fromJson(Map<String, dynamic> json) => ConvoyLiveRider(
        id: json['id'] as String? ?? 'rider_${DateTime.now().millisecondsSinceEpoch}',
        name: json['name'] as String? ?? 'Rider',
        mobile: json['mobile'] as String? ?? '',
        vehicle: json['vehicle'] as String? ?? 'Bike',
        category: VehicleCategory.values.firstWhere(
          (c) => c.name == json['category'],
          orElse: () => VehicleCategory.bike,
        ),
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
        speedKmph: (json['speedKmph'] as num?)?.toDouble() ?? 0.0,
        heading: (json['heading'] as num?)?.toDouble() ?? 0.0,
        isHost: json['isHost'] as bool? ?? false,
        isEmergency: json['isEmergency'] as bool? ?? false,
        emergencyReason: json['emergencyReason'] as String? ?? '',
        lastUpdated: DateTime.tryParse(json['lastUpdated'] as String? ?? '') ?? DateTime.now(),
      );

  ConvoyLiveRider copyWith({
    String? id,
    String? name,
    String? mobile,
    String? vehicle,
    VehicleCategory? category,
    double? latitude,
    double? longitude,
    double? speedKmph,
    double? heading,
    bool? isHost,
    bool? isEmergency,
    String? emergencyReason,
    DateTime? lastUpdated,
  }) {
    return ConvoyLiveRider(
      id: id ?? this.id,
      name: name ?? this.name,
      mobile: mobile ?? this.mobile,
      vehicle: vehicle ?? this.vehicle,
      category: category ?? this.category,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      speedKmph: speedKmph ?? this.speedKmph,
      heading: heading ?? this.heading,
      isHost: isHost ?? this.isHost,
      isEmergency: isEmergency ?? this.isEmergency,
      emergencyReason: emergencyReason ?? this.emergencyReason,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}

class ConvoyEmergencyAlert {
  final String id;
  final String unionId;
  final String riderId;
  final String riderName;
  final String riderMobile;
  final String emergencyType; // Crash / Breakdown / Puncture / Medical / Fuel / General
  final String note;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final bool isResolved;

  const ConvoyEmergencyAlert({
    required this.id,
    required this.unionId,
    required this.riderId,
    required this.riderName,
    required this.riderMobile,
    required this.emergencyType,
    this.note = '',
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.isResolved = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'unionId': unionId,
        'riderId': riderId,
        'riderName': riderName,
        'riderMobile': riderMobile,
        'emergencyType': emergencyType,
        'note': note,
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': timestamp.toIso8601String(),
        'isResolved': isResolved,
      };

  factory ConvoyEmergencyAlert.fromJson(Map<String, dynamic> json) => ConvoyEmergencyAlert(
        id: json['id'] as String? ?? 'sos_${DateTime.now().millisecondsSinceEpoch}',
        unionId: json['unionId'] as String? ?? '',
        riderId: json['riderId'] as String? ?? '',
        riderName: json['riderName'] as String? ?? 'Rider',
        riderMobile: json['riderMobile'] as String? ?? '',
        emergencyType: json['emergencyType'] as String? ?? 'General SOS',
        note: json['note'] as String? ?? '',
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
        isResolved: json['isResolved'] as bool? ?? false,
      );
}

// ─────────────────────────────────────────────
//  GROUPS (community layer above convoys)
// ─────────────────────────────────────────────

enum GroupMemberRole { member, admin }

class GroupMember {
  final String id;
  final String name;
  final String mobile;
  final GroupMemberRole role;
  final DateTime joinedAt;
  final bool isPending;

  const GroupMember({
    required this.id,
    required this.name,
    required this.mobile,
    this.role = GroupMemberRole.member,
    required this.joinedAt,
    this.isPending = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mobile': mobile,
        'role': role.name,
        'joinedAt': joinedAt.toIso8601String(),
        'isPending': isPending,
      };

  factory GroupMember.fromJson(Map<String, dynamic> json) => GroupMember(
        id: json['id'] as String? ?? 'gm_${DateTime.now().millisecondsSinceEpoch}',
        name: json['name'] as String? ?? 'Member',
        mobile: json['mobile'] as String? ?? '',
        role: GroupMemberRole.values.firstWhere(
          (r) => r.name == json['role'],
          orElse: () => GroupMemberRole.member,
        ),
        joinedAt: DateTime.tryParse(json['joinedAt'] as String? ?? '') ?? DateTime.now(),
        isPending: json['isPending'] as bool? ?? false,
      );

  GroupMember copyWith({
    String? id,
    String? name,
    String? mobile,
    GroupMemberRole? role,
    DateTime? joinedAt,
    bool? isPending,
  }) =>
      GroupMember(
        id: id ?? this.id,
        name: name ?? this.name,
        mobile: mobile ?? this.mobile,
        role: role ?? this.role,
        joinedAt: joinedAt ?? this.joinedAt,
        isPending: isPending ?? this.isPending,
      );
}

class GroupChatMessage {
  final String id;
  final String senderName;
  final String senderId;
  final String text;
  final DateTime timestamp;
  final bool isAdmin;

  const GroupChatMessage({
    required this.id,
    required this.senderName,
    required this.senderId,
    required this.text,
    required this.timestamp,
    this.isAdmin = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderName': senderName,
        'senderId': senderId,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
        'isAdmin': isAdmin,
      };

  factory GroupChatMessage.fromJson(Map<String, dynamic> json) => GroupChatMessage(
        id: json['id'] as String? ?? 'gcm_${DateTime.now().millisecondsSinceEpoch}',
        senderName: json['senderName'] as String? ?? 'Member',
        senderId: json['senderId'] as String? ?? '',
        text: json['text'] as String? ?? '',
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
        isAdmin: json['isAdmin'] as bool? ?? false,
      );
}

class TravelGroup {
  final String id;
  final String name;
  final String description;
  final String category;
  final bool isPublic;
  final List<GroupMember> members;
  final List<GroupChatMessage> chatMessages;
  final List<String> convoyIds;
  final DateTime createdAt;
  final String emoji;
  final String imageUrl;

  const TravelGroup({
    required this.id,
    required this.name,
    this.description = '',
    this.category = 'Travel',
    this.isPublic = true,
    this.members = const [],
    this.chatMessages = const [],
    this.convoyIds = const [],
    required this.createdAt,
    this.emoji = '👥',
    this.imageUrl = '',
  });

  List<GroupMember> get approvedMembers => members.where((m) => !m.isPending).toList();
  List<GroupMember> get pendingMembers => members.where((m) => m.isPending).toList();
  List<GroupMember> get admins =>
      members.where((m) => m.role == GroupMemberRole.admin && !m.isPending).toList();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'category': category,
        'isPublic': isPublic,
        'members': members.map((m) => m.toJson()).toList(),
        'chatMessages': chatMessages.map((c) => c.toJson()).toList(),
        'convoyIds': convoyIds,
        'createdAt': createdAt.toIso8601String(),
        'emoji': emoji,
        'imageUrl': imageUrl,
      };

  factory TravelGroup.fromJson(Map<String, dynamic> json) => TravelGroup(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Group',
        description: json['description'] as String? ?? '',
        category: json['category'] as String? ?? 'Travel',
        isPublic: json['isPublic'] as bool? ?? true,
        members: (json['members'] as List<dynamic>?)
                ?.map((m) => GroupMember.fromJson(m as Map<String, dynamic>))
                .toList() ??
            [],
        chatMessages: (json['chatMessages'] as List<dynamic>?)
                ?.map((c) => GroupChatMessage.fromJson(c as Map<String, dynamic>))
                .toList() ??
            [],
        convoyIds:
            (json['convoyIds'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        emoji: json['emoji'] as String? ?? '👥',
        imageUrl: json['imageUrl'] as String? ?? '',
      );

  TravelGroup copyWith({
    String? id,
    String? name,
    String? description,
    String? category,
    bool? isPublic,
    List<GroupMember>? members,
    List<GroupChatMessage>? chatMessages,
    List<String>? convoyIds,
    DateTime? createdAt,
    String? emoji,
    String? imageUrl,
  }) =>
      TravelGroup(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        category: category ?? this.category,
        isPublic: isPublic ?? this.isPublic,
        members: members ?? this.members,
        chatMessages: chatMessages ?? this.chatMessages,
        convoyIds: convoyIds ?? this.convoyIds,
        createdAt: createdAt ?? this.createdAt,
        emoji: emoji ?? this.emoji,
        imageUrl: imageUrl ?? this.imageUrl,
      );
}
