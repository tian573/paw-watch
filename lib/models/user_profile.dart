import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum TrustTier {
  community,        // Level 1: Open community actions (Feed, check-in, update pin, report)
  verifiedRescuer,  // Level 2: Physical rescue missions, vet trips, temporary rescue claims
  trustedFoster,    // Level 3: In-home foster custody, vulnerable kitten intakes
}

class UserProfile {
  final String uid;
  final String displayName;
  final String email;
  final String? photoUrl;
  final String bio;
  final String city;
  final int totalXp;
  final int level;
  final double trustScore; // 0.0 - 5.0
  final int totalRescues;
  final int successfulRescues;
  final int completedFosters;
  final int activeFosters;
  final double checkInRate; // Percentage e.g. 96.0
  final int flagCount;
  final TrustTier trustTier;
  final DateTime joinedAt;
  final List<String> badges;
  final List<Map<String, dynamic>> reviews;
  final String role; // 'user' or 'admin'
  final bool isBanned;
  final bool isSuspended;
  final String? suspendReason;

  const UserProfile({
    required this.uid,
    required this.displayName,
    required this.email,
    this.photoUrl,
    this.bio = 'Passionate cat lover and community rescue volunteer. 🐾',
    this.city = 'Jakarta, Indonesia',
    this.totalXp = 0,
    this.level = 1,
    this.trustScore = 5.0,
    this.totalRescues = 0,
    this.successfulRescues = 0,
    this.completedFosters = 0,
    this.activeFosters = 0,
    this.checkInRate = 100.0,
    this.flagCount = 0,
    this.trustTier = TrustTier.community,
    required this.joinedAt,
    this.badges = const ['Newcomer PawWatcher 🐾'],
    this.reviews = const [],
    this.role = 'user',
    this.isBanned = false,
    this.isSuspended = false,
    this.suspendReason,
  });

  bool get isAdmin => role == 'admin' || email == 'admin@example.com';

  String get initials {
    final name = displayName.trim();
    if (name.isEmpty) return 'PW';
    final parts = name.split(' ');
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (name.length >= 2) {
      return name.substring(0, 2).toUpperCase();
    }
    return name[0].toUpperCase();
  }

  String get trustTierTitle {
    switch (trustTier) {
      case TrustTier.trustedFoster:
        return 'Trusted Foster';
      case TrustTier.verifiedRescuer:
        return 'Verified Rescuer';
      case TrustTier.community:
        return 'Community Member';
    }
  }

  String get trustTierSubtitle {
    switch (trustTier) {
      case TrustTier.trustedFoster:
        return 'Highest safety tier • Certified for in-home foster custody';
      case TrustTier.verifiedRescuer:
        return 'Qualified for on-the-way physical rescue & vet transports';
      case TrustTier.community:
        return 'Open to spotting, feeding & presence check-ins';
    }
  }

  IconData get trustTierIcon {
    switch (trustTier) {
      case TrustTier.trustedFoster:
        return Icons.verified_user_rounded;
      case TrustTier.verifiedRescuer:
        return Icons.shield_rounded;
      case TrustTier.community:
        return Icons.pets_rounded;
    }
  }

  Color get trustTierColor {
    switch (trustTier) {
      case TrustTier.trustedFoster:
        return const Color(0xFF673AB7); // Deep Purple
      case TrustTier.verifiedRescuer:
        return const Color(0xFF2E7D32); // Emerald Green
      case TrustTier.community:
        return const Color(0xFF9B8EC4); // Lavender
    }
  }

  bool get isEligibleForPhysicalRescue =>
      trustTier != TrustTier.community || successfulRescues >= 1;

  bool get isEligibleForFoster => trustTier == TrustTier.trustedFoster;

  static const int maxLevel = 100;
  bool get isMaxLevel => level >= maxLevel;

  int get xpForNextLevel => isMaxLevel ? maxLevel * 200 : level * 200;
  int get currentLevelBaseXp => (level - 1) * 200;
  double get levelProgress {
    if (isMaxLevel) return 1.0;
    final next = xpForNextLevel;
    final base = currentLevelBaseXp;
    if (next <= base) return 1.0;
    final progress = (totalXp - base) / (next - base);
    return progress.clamp(0.0, 1.0);
  }

  Map<String, dynamic> toMap() {
    return {
      'displayName': displayName,
      'email': email,
      'photoUrl': photoUrl,
      'bio': bio,
      'city': city,
      'totalXp': totalXp,
      'level': level,
      'trustScore': trustScore,
      'totalRescues': totalRescues,
      'successfulRescues': successfulRescues,
      'completedFosters': completedFosters,
      'activeFosters': activeFosters,
      'checkInRate': checkInRate,
      'flagCount': flagCount,
      'trustTier': trustTier.name,
      'joinedAt': Timestamp.fromDate(joinedAt),
      'badges': badges,
      'reviews': reviews,
      'role': role,
      'isBanned': isBanned,
      'isSuspended': isSuspended,
      'suspendReason': suspendReason,
    };
  }

  factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return UserProfile.fromMap(data, doc.id);
  }

  factory UserProfile.fromMap(Map<String, dynamic> data, String uid) {
    DateTime parsedJoined = DateTime.now();
    if (data['joinedAt'] is Timestamp) {
      parsedJoined = (data['joinedAt'] as Timestamp).toDate();
    } else if (data['joinedAt'] is String) {
      parsedJoined = DateTime.tryParse(data['joinedAt']) ?? DateTime.now();
    } else if (data['createdAt'] is Timestamp) {
      parsedJoined = (data['createdAt'] as Timestamp).toDate();
    }

    TrustTier tier = TrustTier.community;
    final tierStr = data['trustTier']?.toString();
    if (tierStr == 'trustedFoster') {
      tier = TrustTier.trustedFoster;
    } else if (tierStr == 'verifiedRescuer') {
      tier = TrustTier.verifiedRescuer;
    }

    final rawBadges = data['badges'];
    List<String> badgeList = ['Newcomer PawWatcher 🐾'];
    if (rawBadges is List) {
      badgeList = rawBadges.map((e) => e.toString()).toList();
    }

    final rawReviews = data['reviews'];
    List<Map<String, dynamic>> reviewList = [];
    if (rawReviews is List) {
      reviewList = rawReviews
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }

    final int rawTotalXp = (data['totalXp'] is num) ? (data['totalXp'] as num).toInt() : 0;
    final int rawXp = (data['xp'] is num) ? (data['xp'] as num).toInt() : 0;
    final int totalXp = rawTotalXp > rawXp ? rawTotalXp : rawXp;
    final int calculatedLevel =
        ((totalXp / 200).floor() + 1).clamp(1, maxLevel);

    final int succRescues = (data['successfulRescues'] is num)
        ? (data['successfulRescues'] as num).toInt()
        : 0;

    // Auto-derive trust tier if not explicitly saved:
    if (tierStr == null) {
      if (succRescues >= 10 && (data['completedFosters'] ?? 0) >= 3) {
        tier = TrustTier.trustedFoster;
      } else if (succRescues >= 3) {
        tier = TrustTier.verifiedRescuer;
      }
    }

    return UserProfile(
      uid: uid,
      displayName: data['displayName']?.toString() ??
          (data['name']?.toString() ?? 'PawWatcher'),
      email: data['email']?.toString() ?? '',
      photoUrl: data['photoUrl']?.toString(),
      bio: data['bio']?.toString() ??
          'Passionate cat lover and community rescue volunteer. 🐾',
      city: data['city']?.toString() ?? 'Jakarta, Indonesia',
      totalXp: totalXp,
      level: calculatedLevel,
      trustScore: (data['trustScore'] is num)
          ? (data['trustScore'] as num).toDouble()
          : 5.0,
      totalRescues: (data['totalRescues'] is num)
          ? (data['totalRescues'] as num).toInt()
          : 0,
      successfulRescues: succRescues,
      completedFosters: (data['completedFosters'] is num)
          ? (data['completedFosters'] as num).toInt()
          : 0,
      activeFosters: (data['activeFosters'] is num)
          ? (data['activeFosters'] as num).toInt()
          : 0,
      checkInRate: (data['checkInRate'] is num)
          ? (data['checkInRate'] as num).toDouble()
          : 100.0,
      flagCount: (data['flagCount'] is num)
          ? (data['flagCount'] as num).toInt()
          : 0,
      trustTier: tier,
      joinedAt: parsedJoined,
      badges: badgeList,
      reviews: reviewList,
      role: data['role']?.toString() ?? 'user',
      isBanned: data['isBanned'] == true,
      isSuspended: data['isSuspended'] == true,
      suspendReason: data['suspendReason']?.toString(),
    );
  }
}
