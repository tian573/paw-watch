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
  final String urgency;
  final String category;
  final String title;
  final DateTime createdAt;
  final int commentCount;
  final int upvotes;
  final bool rescueClaimed;
  final String rescueClaimedBy;
  final String rescueClaimedByName;
  final DateTime? rescueClaimedAt;
  final DateTime? lastSeenAt;
  final String? lastSeenStatus;
  final String? lastSeenNote;
  final String? routineHours;
  final double? updatedLatitude;
  final double? updatedLongitude;
  final String? updatedLocationAddress;
  final String? careStatus;
  final String? careTakerId;
  final String? careTakerName;
  final DateTime? careStartedAt;
  final DateTime? resolvedAt;
  final String? resolvedByAction;
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
  final String? pendingOutcomeAction;
  final String? pendingOutcomeNote;
  final String? pendingOutcomeProofUrl;
  final String? pendingOutcomeUpdateId;
  final List<String> declinedFosterUserIds;
  final List<String> declinedDispatchUserIds;
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
  final String? adoptionNote;
  final String? temperament;
  final bool hasEarTip;
  final String? postVetCustody;
  final DateTime? vetVerifiedAt;
  final String? pendingAdoptionApplicantId;
  final String? pendingAdoptionApplicantName;
  final String? pendingAdoptionMessage;
  final String? pendingAdoptionContact;
  final String? pendingAdoptionUpdateId;
  final int adoptionApplicantCount;
  final List<String> rescuerUserIds;
  final List<String> blockedUserIds;
  final String? outcomeVideoUrl;
  final bool isDeleted;
  final bool deletedByAdmin;
  final DateTime? deletedAt;
  final String? deletedBy;
  final String? deletedReason;

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
    this.resolvedAt,
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
    this.declinedDispatchUserIds = const [],
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
    this.adoptionNote,
    this.temperament,
    this.hasEarTip = false,
    this.postVetCustody,
    this.vetVerifiedAt,
    this.pendingAdoptionApplicantId,
    this.pendingAdoptionApplicantName,
    this.pendingAdoptionMessage,
    this.pendingAdoptionContact,
    this.pendingAdoptionUpdateId,
    this.adoptionApplicantCount = 0,
    this.rescuerUserIds = const [],
    this.blockedUserIds = const [],
    this.outcomeVideoUrl,
    this.isDeleted = false,
    this.deletedByAdmin = false,
    this.deletedAt,
    this.deletedBy,
    this.deletedReason,
  });


  bool get isPostVetDecisionWindowExpired {
    final verifiedDate = vetVerifiedAt ?? lastVetVisitAt;
    if (verifiedDate == null) return false;
    final expiry = verifiedDate.add(const Duration(hours: 24));
    return DateTime.now().isAfter(expiry);
  }


  Duration? get postVetDecisionTimeRemaining {
    final verifiedDate = vetVerifiedAt ?? lastVetVisitAt;
    if (verifiedDate == null) return null;
    final expiry = verifiedDate.add(const Duration(hours: 24));
    final remaining = expiry.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }


  bool get isRescuerCustodyDelegated =>
      hasVetVisit ||
      postVetCustody == 'rescuerInCharge' ||
      (isAwaitingPostVetDecision && isPostVetDecisionWindowExpired);

  bool get isVetVisitPending => false;

  bool get isResolved => urgency == 'resolved';


  bool get isAutoArchived {
    if (!isResolved) return false;
    final date = resolvedAt ?? lastVetVisitAt ?? createdAt;
    return DateTime.now().difference(date).inDays >= 30;
  }

  bool get isAdoptionShowcase =>
      category == 'Needs Foster' ||
      category == 'Needs Home' ||
      category == 'Rehomed' ||
      isOpenForAdoption;


  bool get isNeedsHome {
    if (isResolved) return false;
    if (urgency == 'urgent') return false;
    final cat = category.toLowerCase().trim();
    if (cat == 'feeding spot' ||
        cat == 'community cat' ||
        cat == 'community care' ||
        cat == 'stray feeding' ||
        cat == 'stray colony') {
      return false;
    }
    return cat == 'needs foster' ||
        cat == 'needs home' ||
        cat == 'rehomed' ||
        cat.contains('foster') ||
        cat.contains('adopt') ||
        cat.contains('rehome') ||
        isOpenForAdoption ||
        postVetCustody == 'openForAdoption' ||
        pendingOutcomeAction == 'rehomed' ||
        urgency == 'needsHome';
  }

  bool isFosterDeclinedFor(String? uid) =>
      uid != null && uid.isNotEmpty && declinedFosterUserIds.contains(uid);

  bool isDispatchDismissedFor(String? uid) =>
      uid != null && uid.isNotEmpty && declinedDispatchUserIds.contains(uid);


  bool isUserInvolved(String? uid) {
    if (uid == null || uid.isEmpty) return false;
    return reporterId == uid ||
        careTakerId == uid ||
        lastVetRescuerId == uid ||
        pendingVetRescuerId == uid ||
        pendingHandoverRescuerId == uid ||
        (rescueClaimed && rescueClaimedBy == uid) ||
        (rescueClaimedBy == uid) ||
        pendingAdoptionApplicantId == uid ||
        rescuerUserIds.contains(uid);
  }

  bool get hasActionHistory =>
      hasVetVisit ||
      isVetVisitPending ||
      isInCare ||
      rescueClaimed ||
      rescuerUserIds.isNotEmpty ||
      (lastSeenStatus != null &&
          lastSeenStatus!.isNotEmpty &&
          lastSeenStatus != 'still_here') ||
      (careTakerId != null && careTakerId!.isNotEmpty) ||
      (pendingVetRescuerId != null && pendingVetRescuerId!.isNotEmpty) ||
      (resolvedByAction != null && resolvedByAction!.isNotEmpty) ||
      (pendingHandoverRescuerId != null && pendingHandoverRescuerId!.isNotEmpty) ||
      (pendingOutcomeAction != null && pendingOutcomeAction!.isNotEmpty);

  bool get isInCare =>
      careStatus != null &&
      (careStatus == 'inCare_foster' || careStatus == 'inCare_shelter') &&
      urgency != 'resolved' &&
      !isResolved &&
      !isFinishedOrResolved &&
      resolvedByAction != 'returnedToSpot' &&
      resolvedByAction != 'rehomed' &&
      resolvedByAction != 'sheltered' &&
      category != 'Resolved' &&
      category != 'Sheltered' &&
      category != 'Rehomed';

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

  int get completedMilestoneCount => completedMilestones.length;


  int get nextPendingMilestoneDay {
    for (final day in effectiveMilestoneDays) {
      if (!isMilestoneDone(day)) {
        return day;
      }
    }
    return effectiveMilestoneDays.isNotEmpty ? effectiveMilestoneDays.last : 1;
  }

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
    if (isTnrCommunityCat) return false;
    final cat = category.toLowerCase();
    if (cat == 'needs foster' ||
        cat == 'needs home' ||
        cat == 'rehomed' ||
        cat == 'spotted' ||
        cat == 'stray' ||
        cat == 'feeding spot' ||
        cat == 'community cat' ||
        cat == 'community care') {
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

  bool get isVetVisitVerified =>
      !isVetVisitPending &&
      (hasVetVisit || hasVetVisitFlag || vetVerifiedAt != null);

  bool get isTnrCommunityCat =>
      urgency != 'resolved' &&
      (resolvedByAction == 'returnedToSpot' ||
          urgency == 'communityCare' ||
          ((category == 'Community Cat' ||
                  category == 'Community Care' ||
                  category == 'Feral / Colony Cat') &&
              urgency != 'urgent' &&
              urgency != 'needsHelp' &&
              !hasVetVisit &&
              !isInCare));

  String get careLabel {
    if (isOpenForAdoption || category == 'Needs Home') return 'Needs Home';
    if (isTnrCommunityCat) return 'Community Cat';
    if (careStatus == 'inCare_vet') return 'At Vet Clinic';
    if (careStatus == 'inCare_foster') return 'In Foster Care';
    if (careStatus == 'inCare_shelter') return 'In Shelter';
    return '';
  }

  IconData get careIcon {
    if (isOpenForAdoption || category == 'Needs Home') return Icons.home_outlined;
    if (isTnrCommunityCat) return Icons.pets;
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
      urgency != 'resolved' &&
      resolvedByAction != 'returnedToSpot' &&
      ((pendingHandoverRescuerId != null &&
              pendingHandoverRescuerId!.isNotEmpty) ||
          (pendingOutcomeAction != null && pendingOutcomeAction!.isNotEmpty) ||
          (pendingAdoptionApplicantId != null &&
              pendingAdoptionApplicantId!.isNotEmpty));

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
      !isOpenForAdoption &&
      (pendingOutcomeAction == null || pendingOutcomeAction!.isEmpty) &&
      (pendingHandoverRescuerId == null || pendingHandoverRescuerId!.isEmpty);

  String get pendingVerificationDescription {
    if (pendingAdoptionApplicantId != null &&
        pendingAdoptionApplicantId!.isNotEmpty) {
      return 'Adoption request received from ${pendingAdoptionApplicantName ?? "an applicant"} — awaiting confirmation.';
    }
    if (pendingHandoverRescuerId != null &&
        pendingHandoverRescuerId!.isNotEmpty) {
      return 'Foster custody handover submitted — awaiting reporter verification.';
    }
    if (isVetVisitPending ||
        (pendingVetRescuerId != null && pendingVetRescuerId!.isNotEmpty)) {
      return 'Vet Clinic Visit submitted — awaiting reporter verification.';
    }
    if (pendingOutcomeAction != null && pendingOutcomeAction!.isNotEmpty) {
      if (pendingOutcomeAction == 'sheltered') {
        return 'Shelter transfer submitted — awaiting admin verification.';
      }
      return 'Outcome confirmation requested — awaiting reporter verification.';
    }
    return 'Action logged — awaiting reporter verification.';
  }

  bool get isEligibleForRadialDispatch {
    if (isDeleted) return false;
    if (urgency == 'resolved' || urgency == 'communityCare' || isInCare || isTnrCommunityCat) return false;
    if (hasVetVisit || isVetVisitPending || isPendingVerification || isAwaitingPostVetDecision) return false;
    if (rescueClaimed || isRescueClaimActive) return false;
    if (rescueClaimedBy.isNotEmpty) return false;

    final cat = category.toLowerCase();
    if (cat == 'needs foster' ||
        cat == 'needs home' ||
        cat == 'rehomed' ||
        cat == 'stray' ||
        cat == 'stray cat' ||
        cat == 'community cat' ||
        cat == 'community care' ||
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
    if (urgency == 'resolved' ||
        careStatus == 'resolved' ||
        category == 'Resolved') {
      return 'resolved';
    }
    if (isTnrCommunityCat) return 'communityCat';
    if (isOpenForAdoption || category == 'Needs Home') return 'needsHome';
    if (isInCare && careStatus != null) return careStatus!;
    if (isPendingVerification || isAwaitingPostVetDecision) return 'waiting';
    if (rescueClaimed || isRescueClaimActive || rescueClaimedBy.isNotEmpty) {
      return 'onTheWay';
    }
    if (hasVetVisit) return 'vetChecked';
    return urgency;
  }

  bool get isOneTimeTask =>
      !isTnrCommunityCat &&
      (category == 'Injured' ||
          category == 'Needs Vet' ||
          category == 'Kitten' ||
          category == 'Urgent Rescue' ||
          category == 'Needs Foster' ||
          category == 'Needs Home');

  bool get isOngoingCare => !isOneTimeTask;


  bool get canTnrReturn =>
      isFeral &&
      temperament != 'friendly' &&
      temperament != 'kitten';

  bool get isFeral =>
      temperament == 'feral' ||
      category == 'Feral / Colony Cat' ||
      category == 'Community Cat' ||
      isTnrCommunityCat;

  bool get isFriendly => temperament == 'friendly';
  bool get isKitten => category == 'Kitten' || temperament == 'kitten';

  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    if (category.isNotEmpty) {
      if (category == 'Kitten') {
        if (urgency == 'urgent') return 'Vulnerable kitten needs urgent help';
        return 'Kitten spotted in the area';
      }
      if (category == 'Injured') return 'Injured cat needs vet attention';
      if (category == 'Needs Foster' || category == 'Needs Home') return 'Looking for a foster or adopter';
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
      careStatus == 'inCare_shelter' ||
      category == 'Sheltered';

  bool get isRehomed =>
      resolvedByAction == 'rehomed' ||
      pendingOutcomeAction == 'rehomed' ||
      lastSeenStatus == 'rehomed' ||
      category == 'Rehomed';

  bool get isFinishedOrResolved =>
      isResolved ||
      isSheltered ||
      isRehomed ||
      isTnrReturned ||
      category == 'Resolved' ||
      category == 'Sheltered' ||
      category == 'Rehomed' ||
      careStatus == 'resolved' ||
      urgency == 'resolved' ||
      (resolvedByAction != null && resolvedByAction!.isNotEmpty);

  bool get isTnrReturned =>
      resolvedByAction == 'returnedToSpot' ||
      pendingOutcomeAction == 'returnedToSpot' ||
      healthTags.contains('🌿 Returned to Colony') ||
      healthTags.contains('Returned to Colony') ||
      (isFeral &&
          (isResolved ||
              careStatus == 'onStreet' ||
              careStatus == 'resolved' ||
              urgency == 'communityCare'));

  String get displayLocation {
    if (urgency == 'resolved' && !isSheltered && !isTnrReturned) {
      return extractCityOnly(effectiveLocationAddress);
    }
    return effectiveLocationAddress;
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
    if (urgency == 'resolved' && !isSheltered && !isTnrReturned) {
      return Sighting.extractCityOnly(effectiveLocationAddress);
    }
    return effectiveLocationAddress;
  }


  bool get shouldShowLastSeenFreshness {
    if (isAutoArchived || isResolved || urgency == 'resolved') return false;
    if (isInCare || isSheltered || isOpenForAdoption || isNeedsHome) return false;
    if (careStatus == 'inCare_foster' ||
        careStatus == 'inCare_shelter' ||
        careStatus == 'inCare_vet' ||
        careStatus == 'resolved') {
      return false;
    }

    return isTnrCommunityCat ||
        category == 'Community Cat' ||
        category == 'Community Care' ||
        category == 'Feral / Colony Cat' ||
        category == 'Feeding Spot' ||
        category == 'Stray' ||
        category == 'Stray Cat' ||
        isMedicalOrTriagePriority ||
        urgency == 'urgent' ||
        category == 'Injured' ||
        category == 'Needs Vet' ||
        category == 'Trapped' ||
        category == 'Urgent Rescue' ||
        category == 'Kitten';
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
      'photos': photoUrls,
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
      'resolvedAt': resolvedAt != null ? Timestamp.fromDate(resolvedAt!) : null,
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
      'isOpenForAdoption': isOpenForAdoption,
      'adoptionNote': adoptionNote,
      'temperament': temperament,
      'hasEarTip': hasEarTip,
      'postVetCustody': postVetCustody,
      'vetVerifiedAt': vetVerifiedAt?.toIso8601String(),
      'pendingAdoptionApplicantId': pendingAdoptionApplicantId,
      'pendingAdoptionApplicantName': pendingAdoptionApplicantName,
      'pendingAdoptionMessage': pendingAdoptionMessage,
      'pendingAdoptionContact': pendingAdoptionContact,
      'pendingAdoptionUpdateId': pendingAdoptionUpdateId,
      'adoptionApplicantCount': adoptionApplicantCount,
      'rescuerUserIds': rescuerUserIds,
      'blockedUserIds': blockedUserIds,
      'isDeleted': isDeleted,
      'deletedByAdmin': deletedByAdmin,
      'deletedAt': deletedAt != null ? Timestamp.fromDate(deletedAt!) : null,
      'deletedBy': deletedBy,
      'deletedReason': deletedReason,
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

    DateTime? parsedVetVerifiedAt;
    if (data['vetVerifiedAt'] is Timestamp) {
      parsedVetVerifiedAt = (data['vetVerifiedAt'] as Timestamp).toDate();
    } else if (data['vetVerifiedAt'] is String) {
      parsedVetVerifiedAt = DateTime.tryParse(data['vetVerifiedAt']);
    } else {
      parsedVetVerifiedAt = parsedLastVetVisitAt;
    }

    DateTime? parsedResolvedAt;
    if (data['resolvedAt'] is Timestamp) {
      parsedResolvedAt = (data['resolvedAt'] as Timestamp).toDate();
    } else if (data['resolvedAt'] is String) {
      parsedResolvedAt = DateTime.tryParse(data['resolvedAt']);
    }

    DateTime? parsedDeletedAt;
    if (data['deletedAt'] is Timestamp) {
      parsedDeletedAt = (data['deletedAt'] as Timestamp).toDate();
    } else if (data['deletedAt'] is String) {
      parsedDeletedAt = DateTime.tryParse(data['deletedAt']);
    }

    final isDeletedVal = data['isDeleted'] == true;
    final deletedByAdminVal = data['deletedByAdmin'] == true ||
        (isDeletedVal && (data['deletedBy'] == 'admin' || data['deletedBy'] != null));

    final rawPhotos = data['photoUrls'] ?? data['photos'];
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
    final rawStatus = data['status']?.toString();
    final rawCareStatus = data['careStatus']?.toString();
    final rawResolvedByAction = data['resolvedByAction']?.toString();
    final isExplicitlyResolved = rawUrgency == 'resolved' ||
        rawUrgency == 'notUrgent' ||
        rawUrgency == 'safe' ||
        rawStatus == 'resolved' ||
        rawCareStatus == 'resolved' ||
        normalizedCategory == 'Resolved' ||
        normalizedCategory == 'Sheltered' ||
        normalizedCategory == 'Rehomed' ||
        rawResolvedByAction == 'sheltered' ||
        rawResolvedByAction == 'rehomed' ||
        data['resolved'] == true ||
        data['isResolved'] == true;
    final normalizedUrgency = isExplicitlyResolved ? 'resolved' : rawUrgency;

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
      commentCount: (data['commentCount'] is num && (data['commentCount'] as num).toInt() > 0)
          ? (data['commentCount'] as num).toInt()
          : 0,
      upvotes: (data['upvotes'] is num && (data['upvotes'] as num).toInt() > 0)
          ? (data['upvotes'] as num).toInt()
          : 0,
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
      resolvedAt: parsedResolvedAt,
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
      declinedDispatchUserIds: (data['declinedDispatchUserIds'] is List)
          ? (data['declinedDispatchUserIds'] as List)
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
      adoptionNote: data['adoptionNote']?.toString(),
      temperament: data['temperament']?.toString(),
      hasEarTip: data['hasEarTip'] == true,
      postVetCustody: data['postVetCustody']?.toString(),
      vetVerifiedAt: parsedVetVerifiedAt,
      pendingAdoptionApplicantId: data['pendingAdoptionApplicantId']?.toString(),
      pendingAdoptionApplicantName:
          data['pendingAdoptionApplicantName']?.toString(),
      pendingAdoptionMessage: data['pendingAdoptionMessage']?.toString(),
      pendingAdoptionContact: data['pendingAdoptionContact']?.toString(),
      pendingAdoptionUpdateId: data['pendingAdoptionUpdateId']?.toString(),
      adoptionApplicantCount: (data['adoptionApplicantCount'] is num)
          ? (data['adoptionApplicantCount'] as num).toInt()
          : 0,
      rescuerUserIds: (data['rescuerUserIds'] is List)
          ? (data['rescuerUserIds'] as List).map((e) => e.toString()).toList()
          : [],
      blockedUserIds: (data['blockedUserIds'] is List)
          ? (data['blockedUserIds'] as List).map((e) => e.toString()).toList()
          : [],
      outcomeVideoUrl: data['outcomeVideoUrl']?.toString() ??
          data['proofVideoUrl']?.toString(),
      isDeleted: isDeletedVal,
      deletedByAdmin: deletedByAdminVal,
      deletedAt: parsedDeletedAt,
      deletedBy: data['deletedBy']?.toString(),
      deletedReason: data['deletedReason']?.toString(),
    );
  }
}


