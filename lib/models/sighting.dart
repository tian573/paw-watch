import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class Sighting {
  final String id;
  final String reporterId;
  final String reporterName;
  final List<String> photoUrls;
  final double latitude;
  final double longitude;
  final String locationAddress;
  final String description;
  final String urgency; // 'urgent', 'needsHelp', 'resolved'
  final String category; // 'Kitten', 'Injured', 'Stray', 'Needs Foster', etc.
  final String title;
  final DateTime createdAt;
  final int commentCount;
  final int upvotes;
  final bool rescueClaimed;
  final String rescueClaimedBy;    // uid of claimer
  final String rescueClaimedByName; // display name of claimer
  final DateTime? rescueClaimedAt; // timestamp when on-my-way was claimed
  final DateTime? lastSeenAt;
  final String? lastSeenStatus; // 'still_here', 'moved', 'not_here', 'holding', 'fed', 'vet'
  final String? lastSeenNote;
  final String? routineHours;
  final double? updatedLatitude;
  final double? updatedLongitude;
  final String? updatedLocationAddress;
  final String? careStatus; // 'onStreet', 'inCare_vet', 'inCare_foster', 'inCare_shelter'
  final String? careTakerId;
  final String? careTakerName;
  final DateTime? careStartedAt;
  final String? resolvedByAction; // 'sheltered', 'rehomed', 'returnedToSpot', etc.
  final String? pendingHandoverRescuerId;
  final String? pendingHandoverRescuerName;
  final String? pendingHandoverUpdateId;
  final String? carePlanGoal;
  final int carePlanDurationDays;
  final List<int> careMilestoneDays;
  final List<String> customMilestoneTitles;
  final List<int> completedMilestones;
  final String? latestCondition;
  final DateTime? lastCheckInAt;
  final String? pendingOutcomeAction; // 'rehomed', 'returnedToSpot'
  final String? pendingOutcomeNote;
  final String? pendingOutcomeProofUrl;
  final String? pendingOutcomeUpdateId;
  final List<String> declinedFosterUserIds;
  final bool hasVetVisitFlag;
  final DateTime? lastVetVisitAt;
  final List<String> healthTags;
  final String? shelterOrClinicName;
  final String? adoptionContact;
  final String? pendingVetRescuerId;
  final String? pendingVetRescuerName;
  final String? pendingVetProofUrl;
  final String? pendingVetClinicName;
  final String? pendingVetNote;
  final String? pendingVetUpdateId;
  final String? lastVetRescuerId;
  final String? lastVetRescuerName;
  final bool isCommunityFosterRequested;
  final bool isOpenForAdoption;

  const Sighting({
    required this.id,
    required this.reporterId,
    required this.reporterName,
    required this.photoUrls,
    required this.latitude,
    required this.longitude,
    required this.locationAddress,
    required this.description,
    required this.urgency,
    required this.category,
    required this.createdAt,
    this.title = '',
    this.commentCount = 0,
    this.upvotes = 0,
    this.rescueClaimed = false,
    this.rescueClaimedBy = '',
    this.rescueClaimedByName = '',
    this.rescueClaimedAt,
    this.lastSeenAt,
    this.lastSeenStatus,
    this.lastSeenNote,
    this.routineHours,
    this.updatedLatitude,
    this.updatedLongitude,
    this.updatedLocationAddress,
    this.careStatus,
    this.careTakerId,
    this.careTakerName,
    this.careStartedAt,
    this.resolvedByAction,
    this.pendingHandoverRescuerId,
    this.pendingHandoverRescuerName,
    this.pendingHandoverUpdateId,
    this.carePlanGoal,
    this.carePlanDurationDays = 7,
    this.careMilestoneDays = const [],
    this.customMilestoneTitles = const [],
    this.completedMilestones = const [],
    this.latestCondition,
    this.lastCheckInAt,
    this.pendingOutcomeAction,
    this.pendingOutcomeNote,
    this.pendingOutcomeProofUrl,
    this.pendingOutcomeUpdateId,
    this.declinedFosterUserIds = const [],
    this.hasVetVisitFlag = false,
    this.lastVetVisitAt,
    this.healthTags = const [],
    this.shelterOrClinicName,
    this.adoptionContact,
    this.pendingVetRescuerId,
    this.pendingVetRescuerName,
    this.pendingVetProofUrl,
    this.pendingVetClinicName,
    this.pendingVetNote,
    this.pendingVetUpdateId,
    this.lastVetRescuerId,
    this.lastVetRescuerName,
    this.isCommunityFosterRequested = false,
    this.isOpenForAdoption = false,
  });

  bool get isVetVisitPending =>
      pendingVetRescuerId != null &&
      pendingVetRescuerId!.isNotEmpty;

  bool get isResolved => urgency == 'resolved';

  bool get isAdoptionShowcase =>
      !isResolved &&
      (isOpenForAdoption ||
          category == 'Needs Foster' ||
          careStatus == 'inCare_shelter' ||
          (healthTags.isNotEmpty && isInCare));

  bool isFosterDeclinedFor(String? uid) =>
      uid != null && uid.isNotEmpty && declinedFosterUserIds.contains(uid);

  bool get isInCare =>
      careStatus != null &&
      (careStatus == 'inCare_foster' || careStatus == 'inCare_shelter') &&
      urgency != 'resolved';

  int get daysInCare {
    final start = careStartedAt ?? createdAt;
    final diff = DateTime.now().difference(start).inDays;
    return diff < 0 ? 0 : diff;
  }

  int get effectiveDurationDays =>
      carePlanDurationDays >= 3 ? carePlanDurationDays : 7;

  List<int> get effectiveMilestoneDays {
    if (careMilestoneDays.isNotEmpty) return careMilestoneDays;
    return List.generate(effectiveDurationDays, (i) => i + 1);
  }

  DateTime? get careDeadline {
    if (careStartedAt == null) return null;
    return careStartedAt!.add(Duration(days: effectiveDurationDays));
  }

  int get daysRemainingUntilDeadline {
    if (careDeadline == null) return effectiveDurationDays - daysInCare;
    final diff = careDeadline!.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  bool isMilestoneDone(int day) => completedMilestones.contains(day);

  bool isMilestoneDue(int day) {
    if (isMilestoneDone(day)) return false;
    final idx = effectiveMilestoneDays.indexOf(day);
    if (idx <= 0) return true;
    final prevDay = effectiveMilestoneDays[idx - 1];
    return isMilestoneDone(prevDay) || daysInCare >= (day - 1);
  }

  bool get isAllMilestonesCompleted =>
      completedMilestones.length >= effectiveMilestoneDays.length;

  bool get areOutcomesUnlocked => isAllMilestonesCompleted;

  List<String> get effectiveMilestoneTitles {
    final d = effectiveMilestoneDays.length;
    if (customMilestoneTitles.isNotEmpty) {
      return List.generate(d, (i) {
        if (i < customMilestoneTitles.length &&
            customMilestoneTitles[i].trim().isNotEmpty) {
          return customMilestoneTitles[i].trim();
        }
        if (i == 0) return 'Intake, Quarantine & Safe Settle';
        if (i == d - 1) return 'Final Target Outcome & Review';
        return 'Day ${i + 1} Daily Care Check';
      });
    }

    return List.generate(d, (i) {
      if (i == 0) return 'Intake, Quarantine & Safe Settle';
      if (i == d - 1) return 'Final Target Outcome & Review';
      return 'Day ${i + 1} Daily Care Check';
    });
  }

  bool get isMedicalOrTriagePriority {
    final cat = category.toLowerCase();
    if (cat == 'needs foster' ||
        cat == 'rehomed' ||
        cat == 'spotted' ||
        cat == 'stray' ||
        cat == 'feeding spot') {
      return false;
    }
    return cat == 'injured' ||
        cat == 'needs vet' ||
        cat == 'trapped' ||
        cat == 'urgent rescue' ||
        cat == 'kitten' ||
        (urgency == 'urgent');
  }

  bool get hasVetVisit =>
      !isVetVisitPending &&
      (hasVetVisitFlag ||
          careStatus == 'inCare_vet' ||
          resolvedByAction == 'vet');

  String get careLabel {
    if (careStatus == 'inCare_vet') return 'At Vet Clinic';
    if (careStatus == 'inCare_foster') return 'In Foster Care';
    if (careStatus == 'inCare_shelter') return 'In Shelter';
    return '';
  }

  IconData get careIcon {
    if (careStatus == 'inCare_vet') return Icons.local_hospital_rounded;
    if (careStatus == 'inCare_foster') return Icons.home_rounded;
    if (careStatus == 'inCare_shelter') return Icons.domain_rounded;
    return Icons.favorite_rounded;
  }

  bool get isRescueClaimExpired {
    if (!rescueClaimed || rescueClaimedAt == null) return false;
    final diff = DateTime.now().difference(rescueClaimedAt!);
    return diff.inMinutes >= 45;
  }

  bool get isRescueClaimActive => rescueClaimed && !isRescueClaimExpired;

  int get rescueClaimRemainingMinutes {
    if (!rescueClaimed || rescueClaimedAt == null) return 0;
    final diff = DateTime.now().difference(rescueClaimedAt!);
    final rem = 45 - diff.inMinutes;
    return rem > 0 ? rem : 0;
  }

  bool get isPendingVerification =>
      isVetVisitPending ||
      (pendingVetRescuerId != null && pendingVetRescuerId!.isNotEmpty) ||
      (pendingHandoverRescuerId != null && pendingHandoverRescuerId!.isNotEmpty) ||
      (pendingOutcomeAction != null && pendingOutcomeAction!.isNotEmpty);

  bool get isAwaitingPostVetDecision =>
      hasVetVisit &&
      !isInCare &&
      urgency != 'resolved' &&
      resolvedByAction != 'returnedToSpot' &&
      resolvedByAction != 'sheltered' &&
      resolvedByAction != 'rehomed' &&
      careStatus != 'onStreet' &&
      careStatus != 'resolved' &&
      careStatus != 'inCare_foster' &&
      careStatus != 'inCare_shelter' &&
      !isCommunityFosterRequested &&
      (pendingHandoverRescuerId == null || pendingHandoverRescuerId!.isEmpty);

  String get pendingVerificationDescription {
    if (isVetVisitPending ||
        (pendingVetRescuerId != null && pendingVetRescuerId!.isNotEmpty)) {
      final name = pendingVetRescuerName?.isNotEmpty == true
          ? pendingVetRescuerName!
          : 'Rescuer';
      return '$name submitted vet visit • Awaiting verification';
    }
    if (pendingHandoverRescuerId != null &&
        pendingHandoverRescuerId!.isNotEmpty) {
      final name = pendingHandoverRescuerName?.isNotEmpty == true
          ? pendingHandoverRescuerName!
          : 'Rescuer';
      return '$name requested foster • Awaiting approval';
    }
    if (pendingOutcomeAction != null && pendingOutcomeAction!.isNotEmpty) {
      return 'Outcome proof submitted • Awaiting review';
    }
    if (isAwaitingPostVetDecision) {
      final name = lastVetRescuerName?.isNotEmpty == true
          ? lastVetRescuerName!
          : 'Rescuer';
      return '$name verified vet visit • Next step on hold';
    }
    return 'Verification submitted • Awaiting review';
  }

  bool get isEligibleForRadialDispatch {
    if (urgency == 'resolved' || isInCare) return false;
    if (hasVetVisit || isVetVisitPending || isPendingVerification || isAwaitingPostVetDecision) return false;
    if (rescueClaimed || isRescueClaimActive) return false;
    if (rescueClaimedBy.isNotEmpty) return false;

    final cat = category.toLowerCase();
    if (cat == 'needs foster' ||
        cat == 'rehomed' ||
        cat == 'stray' ||
        cat == 'stray cat' ||
        cat == 'feeding spot' ||
        cat == 'spotted') {
      return false;
    }

    if (cat == 'kitten') {
      return urgency == 'urgent';
    }

    return urgency == 'urgent' ||
        category == 'Injured' ||
        category == 'Needs Vet' ||
        category == 'Urgent Rescue';
  }

  String get status {
    if (urgency == 'resolved') return 'resolved';
    if (isInCare && careStatus != null) return careStatus!;
    if (isPendingVerification || isAwaitingPostVetDecision) return 'waiting';
    if (rescueClaimed || isRescueClaimActive || rescueClaimedBy.isNotEmpty) {
      return 'onTheWay';
    }
    if (hasVetVisit) return 'vetChecked';
    return urgency;
  }

  bool get isOneTimeTask =>
      category == 'Injured' ||
      category == 'Needs Vet' ||
      category == 'Kitten' ||
      category == 'Urgent Rescue' ||
      category == 'Needs Foster';

  bool get isOngoingCare => !isOneTimeTask;

  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    if (category.isNotEmpty) {
      if (category == 'Kitten') {
        if (urgency == 'urgent') return 'Vulnerable kitten needs urgent help';
        return 'Kitten spotted in the area';
      }
      if (category == 'Injured') return 'Injured cat needs vet attention';
      if (category == 'Needs Foster') return 'Looking for a foster or adopter';
      if (category == 'Needs Vet') return 'Sick cat needs medical care';
      if (category == 'Feeding Spot') return 'Cat feeding spot reported';
      if (category == 'Urgent Rescue') return 'Immediate rescue assistance needed';
      if (category == 'Resolved') return 'Cat safely rescued & treated';
      return '$category spotted';
    }
    if (urgency == 'urgent') return 'Immediate rescue assistance needed';
    if (urgency == 'resolved') return 'Cat safely rescued & treated';
    return 'Cat spotted in the area';
  }

  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inDays > 365) {
      return '${(difference.inDays / 365).floor()}y ago';
    } else if (difference.inDays >= 30) {
      return '${(difference.inDays / 30).floor()}mo ago';
    } else if (difference.inDays >= 7) {
      return '${(difference.inDays / 7).floor()}w ago';
    } else if (difference.inDays >= 1) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours >= 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes >= 1) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  static String extractCityOnly(String address) {
    if (address.trim().isEmpty) return 'Nearby Area';
    final parts = address
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length <= 1) return address;

    // Filter out parts containing street / house indicators or raw zip codes
    final filtered = parts.where((p) {
      final lower = p.toLowerCase();
      final hasStreet = lower.startsWith('jl') ||
          lower.startsWith('jalan') ||
          lower.startsWith('gang') ||
          lower.startsWith('gg.') ||
          lower.startsWith('no.') ||
          lower.contains('rt.') ||
          lower.contains('rw.') ||
          lower.contains('blok') ||
          lower.contains('kav.');
      final isPostalOnly = RegExp(r'^\d{4,6}$').hasMatch(p);
      return !hasStreet && !isPostalOnly;
    }).toList();

    if (filtered.isNotEmpty) {
      if (filtered.length >= 2) {
        return '${filtered[filtered.length - 2]}, ${filtered.last}';
      }
      return filtered.last;
    }
    return parts.last;
  }

  bool get isSheltered =>
      resolvedByAction == 'sheltered' ||
      lastSeenStatus == 'sheltered' ||
      careStatus == 'inCare_shelter';

  String get displayLocation {
    if (urgency == 'resolved' && !isSheltered) {
      return extractCityOnly(locationAddress);
    }
    return locationAddress;
  }

  String formatDistance(double? userLat, double? userLng) {
    if (userLat == null || userLng == null) return 'Nearby';
    try {
      final meters = Geolocator.distanceBetween(
        userLat,
        userLng,
        latitude,
        longitude,
      );
      if (meters < 1000) {
        return '${meters.round()}m away';
      } else {
        return '${(meters / 1000).toStringAsFixed(1)}km away';
      }
    } catch (_) {
      return 'Nearby';
    }
  }

  double calculateDistanceInMeters(double? userLat, double? userLng) {
    if (userLat == null || userLng == null) return 999999999.0;
    try {
      return Geolocator.distanceBetween(
        userLat,
        userLng,
        latitude,
        longitude,
      );
    } catch (_) {
      return 999999999.0;
    }
  }

  String get distance {
    // Default friendly distance label
    return 'Nearby';
  }

  int get imageCount => photoUrls.isNotEmpty ? photoUrls.length : 1;

  String get initials {
    final name = reporterName.trim();
    if (name.isEmpty) return 'PW';
    final parts = name.split(' ');
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (name.length >= 2) {
      return name.substring(0, 2).toUpperCase();
    }
    return name[0].toUpperCase();
  }

  Color get avatarColor {
    final colors = [
      const Color(0xFF7986CB),
      const Color(0xFF26A69A),
      const Color(0xFFEC407A),
      const Color(0xFFFF7043),
      const Color(0xFF66BB6A),
      const Color(0xFFAB47BC),
      const Color(0xFF42A5F5),
    ];
    final index = reporterName.hashCode.abs() % colors.length;
    return colors[index];
  }

  double get effectiveLatitude => updatedLatitude ?? latitude;
  double get effectiveLongitude => updatedLongitude ?? longitude;
  String get effectiveLocationAddress =>
      updatedLocationAddress ?? locationAddress;

  String get effectiveDisplayLocation {
    if (urgency == 'resolved' && !isSheltered) {
      return Sighting.extractCityOnly(effectiveLocationAddress);
    }
    return effectiveLocationAddress;
  }

  String get lastSeenFreshness {
    final seen = lastSeenAt ?? createdAt;
    final now = DateTime.now();
    final diff = now.difference(seen);

    if (lastSeenStatus == 'helpedOffline') {
      return 'Rescued / Taken in by Local Resident 🏠';
    }

    if (lastSeenStatus == 'holding') {
      return 'In Temporary Holding / Safe with Rescuer';
    }

    if (lastSeenStatus == 'not_here' || lastSeenStatus == 'notHere') {
      if (diff.inMinutes < 60) {
        return 'Checked: Not here (${diff.inMinutes < 1 ? 'just now' : '${diff.inMinutes}m ago'})';
      }
      if (diff.inHours < 24) {
        return 'Checked: Not here (${diff.inHours}h ago)';
      }
      return 'Checked: Not here (${diff.inDays}d ago)';
    }

    if (lastSeenStatus == 'moved') {
      if (diff.inMinutes < 60) {
        return 'Spotted & Moved (${diff.inMinutes < 1 ? 'just now' : '${diff.inMinutes}m ago'})';
      }
      return 'Moved Nearby (${diff.inHours}h ago)';
    }

    if (diff.inMinutes < 60) {
      return 'Active (Seen ${diff.inMinutes < 1 ? 'just now' : '${diff.inMinutes}m ago'})';
    } else if (diff.inHours < 6) {
      return 'Seen ${diff.inHours}h ago';
    } else if (diff.inHours < 24) {
      return 'Last seen ${diff.inHours}h ago';
    } else {
      return 'Last seen ${diff.inDays}d ago';
    }
  }

  Color get lastSeenFreshnessColor {
    if (lastSeenStatus == 'helpedOffline') return const Color(0xFF43A047);
    if (lastSeenStatus == 'holding') return const Color(0xFF9C27B0);
    if (lastSeenStatus == 'not_here' || lastSeenStatus == 'notHere') return const Color(0xFF78909C);
    if (lastSeenStatus == 'moved') return const Color(0xFFFF9800);
    final seen = lastSeenAt ?? createdAt;
    final diff = DateTime.now().difference(seen);
    if (diff.inHours < 6) return const Color(0xFF43A047);
    if (diff.inHours < 24) return const Color(0xFFFFA000);
    return const Color(0xFF9E9E9E);
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'reporterId': reporterId,
      'reporterName': reporterName,
      'photoUrls': photoUrls,
      'latitude': latitude,
      'longitude': longitude,
      'locationAddress': locationAddress,
      'description': description,
      'urgency': urgency,
      'category': category,
      'createdAt': Timestamp.fromDate(createdAt),
      'commentCount': commentCount,
      'upvotes': upvotes,
      'rescueClaimed': rescueClaimed,
      'rescueClaimedBy': rescueClaimedBy,
      'rescueClaimedByName': rescueClaimedByName,
      'rescueClaimedAt': rescueClaimedAt != null ? Timestamp.fromDate(rescueClaimedAt!) : null,
      'lastSeenAt': lastSeenAt != null ? Timestamp.fromDate(lastSeenAt!) : null,
      'lastSeenStatus': lastSeenStatus,
      'lastSeenNote': lastSeenNote,
      'routineHours': routineHours,
      'updatedLatitude': updatedLatitude,
      'updatedLongitude': updatedLongitude,
      'updatedLocationAddress': updatedLocationAddress,
      'careStatus': careStatus,
      'careTakerId': careTakerId,
      'careTakerName': careTakerName,
      'careStartedAt': careStartedAt != null ? Timestamp.fromDate(careStartedAt!) : null,
      'resolvedByAction': resolvedByAction,
      'pendingHandoverRescuerId': pendingHandoverRescuerId,
      'pendingHandoverRescuerName': pendingHandoverRescuerName,
      'pendingHandoverUpdateId': pendingHandoverUpdateId,
      'carePlanGoal': carePlanGoal,
      'carePlanDurationDays': carePlanDurationDays,
      'careMilestoneDays': careMilestoneDays,
      'customMilestoneTitles': customMilestoneTitles,
      'completedMilestones': completedMilestones,
      'latestCondition': latestCondition,
      'lastCheckInAt': lastCheckInAt != null ? Timestamp.fromDate(lastCheckInAt!) : null,
      'pendingOutcomeAction': pendingOutcomeAction,
      'pendingOutcomeNote': pendingOutcomeNote,
      'pendingOutcomeProofUrl': pendingOutcomeProofUrl,
      'pendingOutcomeUpdateId': pendingOutcomeUpdateId,
      'declinedFosterUserIds': declinedFosterUserIds,
      'pendingVetRescuerId': pendingVetRescuerId,
      'pendingVetRescuerName': pendingVetRescuerName,
      'pendingVetProofUrl': pendingVetProofUrl,
      'pendingVetClinicName': pendingVetClinicName,
      'pendingVetNote': pendingVetNote,
      'pendingVetUpdateId': pendingVetUpdateId,
      'lastVetRescuerId': lastVetRescuerId,
      'lastVetRescuerName': lastVetRescuerName,
      'isCommunityFosterRequested': isCommunityFosterRequested,
    };
  }

  factory Sighting.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Sighting.fromMap(data, doc.id);
  }

  factory Sighting.fromMap(Map<String, dynamic> data, String id) {
    DateTime parsedDate = DateTime.now();
    if (data['createdAt'] is Timestamp) {
      parsedDate = (data['createdAt'] as Timestamp).toDate();
    } else if (data['createdAt'] is String) {
      parsedDate = DateTime.tryParse(data['createdAt']) ?? DateTime.now();
    }

    DateTime? parsedLastSeen;
    if (data['lastSeenAt'] is Timestamp) {
      parsedLastSeen = (data['lastSeenAt'] as Timestamp).toDate();
    } else if (data['lastSeenAt'] is String) {
      parsedLastSeen = DateTime.tryParse(data['lastSeenAt']);
    }

    DateTime? parsedRescueClaimedAt;
    if (data['rescueClaimedAt'] is Timestamp) {
      parsedRescueClaimedAt = (data['rescueClaimedAt'] as Timestamp).toDate();
    } else if (data['rescueClaimedAt'] is String) {
      parsedRescueClaimedAt = DateTime.tryParse(data['rescueClaimedAt']);
    }

    DateTime? parsedCareStartedAt;
    if (data['careStartedAt'] is Timestamp) {
      parsedCareStartedAt = (data['careStartedAt'] as Timestamp).toDate();
    } else if (data['careStartedAt'] is String) {
      parsedCareStartedAt = DateTime.tryParse(data['careStartedAt']);
    }

    DateTime? parsedLastCheckInAt;
    if (data['lastCheckInAt'] is Timestamp) {
      parsedLastCheckInAt = (data['lastCheckInAt'] as Timestamp).toDate();
    } else if (data['lastCheckInAt'] is String) {
      parsedLastCheckInAt = DateTime.tryParse(data['lastCheckInAt']);
    }

    DateTime? parsedLastVetVisitAt;
    if (data['lastVetVisitAt'] is Timestamp) {
      parsedLastVetVisitAt = (data['lastVetVisitAt'] as Timestamp).toDate();
    } else if (data['lastVetVisitAt'] is String) {
      parsedLastVetVisitAt = DateTime.tryParse(data['lastVetVisitAt']);
    }

    final rawPhotos = data['photoUrls'];
    List<String> photos = [];
    if (rawPhotos is List) {
      photos = rawPhotos.map((e) => e.toString()).toList();
    } else if (rawPhotos is String && rawPhotos.isNotEmpty) {
      photos = [rawPhotos];
    }

    final rawCategory = data['category']?.toString() ?? 'Spotted';
    final normalizedCategory = (rawCategory == 'Stray Cat' || rawCategory == 'Stray')
        ? 'Spotted'
        : rawCategory;

    final rawUrgency = data['urgency']?.toString() ?? 'needsHelp';
    final normalizedUrgency = (rawUrgency == 'notUrgent' || rawUrgency == 'safe')
        ? 'resolved'
        : rawUrgency;

    final rawMilestones = data['completedMilestones'];
    List<int> milestones = [];
    if (rawMilestones is List) {
      milestones = rawMilestones.map((e) => (e is num) ? e.toInt() : int.tryParse(e.toString()) ?? 0).where((m) => m > 0).toList();
    }

    final isPendingVet = data['pendingVetRescuerId'] != null &&
        data['pendingVetRescuerId'].toString().isNotEmpty;

    final hasVet = !isPendingVet &&
        (data['hasVetVisitFlag'] == true ||
            data['hasVetVisit'] == true ||
            data['careStatus'] == 'inCare_vet' ||
            data['resolvedByAction'] == 'vet');

    final rawHealthTags = data['healthTags'];
    List<String> healthTagsList = [];
    if (rawHealthTags is List) {
      healthTagsList = rawHealthTags.map((e) => e.toString()).toList();
    } else if (hasVet) {
      healthTagsList = ['Vet Checked'];
    }

    return Sighting(
      id: id,
      title: data['title'] ?? '',
      reporterId: data['reporterId'] ?? '',
      reporterName: data['reporterName'] ?? 'Anonymous Rescuer',
      photoUrls: photos,
      latitude: (data['latitude'] is num) ? (data['latitude'] as num).toDouble() : -6.2615,
      longitude: (data['longitude'] is num) ? (data['longitude'] as num).toDouble() : 106.8106,
      locationAddress: data['locationAddress'] ?? 'Jakarta Selatan, Indonesia',
      description: data['description'] ?? '',
      urgency: normalizedUrgency,
      category: normalizedCategory,
      createdAt: parsedDate,
      commentCount: (data['commentCount'] is num) ? (data['commentCount'] as num).toInt() : 0,
      upvotes: (data['upvotes'] is num) ? (data['upvotes'] as num).toInt() : 0,
      rescueClaimed: data['rescueClaimed'] == true ||
          (data['rescueClaimedBy'] != null &&
              data['rescueClaimedBy'].toString().trim().isNotEmpty),
      rescueClaimedBy: data['rescueClaimedBy']?.toString() ?? '',
      rescueClaimedByName: data['rescueClaimedByName']?.toString() ?? '',
      rescueClaimedAt: parsedRescueClaimedAt,
      lastSeenAt: parsedLastSeen,
      lastSeenStatus: data['lastSeenStatus']?.toString(),
      lastSeenNote: data['lastSeenNote']?.toString(),
      routineHours: data['routineHours']?.toString(),
      updatedLatitude: (data['updatedLatitude'] is num)
          ? (data['updatedLatitude'] as num).toDouble()
          : null,
      updatedLongitude: (data['updatedLongitude'] is num)
          ? (data['updatedLongitude'] as num).toDouble()
          : null,
      updatedLocationAddress: data['updatedLocationAddress']?.toString(),
      careStatus: data['careStatus']?.toString(),
      careTakerId: data['careTakerId']?.toString(),
      careTakerName: data['careTakerName']?.toString(),
      careStartedAt: parsedCareStartedAt,
      resolvedByAction: data['resolvedByAction']?.toString(),
      pendingHandoverRescuerId: data['pendingHandoverRescuerId']?.toString(),
      pendingHandoverRescuerName:
          data['pendingHandoverRescuerName']?.toString(),
      pendingHandoverUpdateId: data['pendingHandoverUpdateId']?.toString(),
      carePlanGoal: data['carePlanGoal']?.toString(),
      carePlanDurationDays: (data['carePlanDurationDays'] is num)
          ? (data['carePlanDurationDays'] as num).toInt()
          : 7,
      careMilestoneDays: (data['careMilestoneDays'] is List)
          ? (data['careMilestoneDays'] as List)
              .map((e) => (e is num) ? e.toInt() : int.tryParse(e.toString()) ?? 0)
              .where((m) => m > 0)
              .toList()
          : [],
      customMilestoneTitles: (data['customMilestoneTitles'] is List)
          ? (data['customMilestoneTitles'] as List)
              .map((e) => e.toString())
              .toList()
          : [],
      completedMilestones: milestones,
      latestCondition: data['latestCondition']?.toString(),
      lastCheckInAt: parsedLastCheckInAt,
      pendingOutcomeAction: data['pendingOutcomeAction']?.toString(),
      pendingOutcomeNote: data['pendingOutcomeNote']?.toString(),
      pendingOutcomeProofUrl: data['pendingOutcomeProofUrl']?.toString(),
      pendingOutcomeUpdateId: data['pendingOutcomeUpdateId']?.toString(),
      declinedFosterUserIds: (data['declinedFosterUserIds'] is List)
          ? (data['declinedFosterUserIds'] as List)
              .map((e) => e.toString())
              .toList()
          : [],
      hasVetVisitFlag: hasVet,
      lastVetVisitAt: parsedLastVetVisitAt,
      healthTags: healthTagsList,
      shelterOrClinicName: data['shelterOrClinicName']?.toString(),
      adoptionContact: data['adoptionContact']?.toString(),
      pendingVetRescuerId: data['pendingVetRescuerId']?.toString(),
      pendingVetRescuerName: data['pendingVetRescuerName']?.toString(),
      pendingVetProofUrl: data['pendingVetProofUrl']?.toString(),
      pendingVetClinicName: data['pendingVetClinicName']?.toString(),
      pendingVetNote: data['pendingVetNote']?.toString(),
      pendingVetUpdateId: data['pendingVetUpdateId']?.toString(),
      lastVetRescuerId: data['lastVetRescuerId']?.toString() ??
          (data['pendingVetRescuerId']?.toString().isNotEmpty == true
              ? data['pendingVetRescuerId']?.toString()
              : null),
      lastVetRescuerName: data['lastVetRescuerName']?.toString() ??
          data['pendingVetRescuerName']?.toString(),
      isCommunityFosterRequested: data['isCommunityFosterRequested'] == true,
      isOpenForAdoption: data['isOpenForAdoption'] == true,
    );
  }
}
