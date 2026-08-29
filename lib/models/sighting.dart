import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
  });

  String get status => urgency;

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
      urgency: data['urgency'] ?? 'needsHelp',
      category: normalizedCategory,
      createdAt: parsedDate,
      commentCount: (data['commentCount'] is num) ? (data['commentCount'] as num).toInt() : 0,
      upvotes: (data['upvotes'] is num) ? (data['upvotes'] as num).toInt() : 0,
    );
  }
}
