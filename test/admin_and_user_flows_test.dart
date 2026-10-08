import 'package:flutter_test/flutter_test.dart';
import 'package:paw_watch/models/user_profile.dart';
import 'package:paw_watch/models/sighting.dart';
import 'package:paw_watch/services/text_moderation_service.dart';

void main() {
  group('Admin & User Role Logic Tests', () {
    test('Admin role verification by role and email', () {
      final adminByRole = UserProfile(
        uid: 'adm1',
        displayName: 'Admin User',
        email: 'staff@organization.org',
        role: 'admin',
        joinedAt: DateTime.now(),
      );
      expect(adminByRole.isAdmin, isTrue);

      final adminByEmail = UserProfile(
        uid: 'adm2',
        displayName: 'Root Admin',
        email: 'admin@example.com',
        role: 'user',
        joinedAt: DateTime.now(),
      );
      expect(adminByEmail.isAdmin, isTrue);

      final normalUser = UserProfile(
        uid: 'usr1',
        displayName: 'Jane Doe',
        email: 'jane@example.com',
        role: 'user',
        joinedAt: DateTime.now(),
      );
      expect(normalUser.isAdmin, isFalse);
    });

    test('User status flags (active, suspended, banned)', () {
      final bannedUser = UserProfile(
        uid: 'b1',
        displayName: 'Spammer',
        email: 'spammer@test.com',
        isBanned: true,
        joinedAt: DateTime.now(),
      );
      expect(bannedUser.isBanned, isTrue);

      final suspendedUser = UserProfile(
        uid: 's1',
        displayName: 'Cooldown User',
        email: 'temp@test.com',
        isSuspended: true,
        suspendReason: 'Inappropriate language',
        joinedAt: DateTime.now(),
      );
      expect(suspendedUser.isSuspended, isTrue);
      expect(suspendedUser.suspendReason, equals('Inappropriate language'));
    });

    test('User initials helper produces clean 2-letter tokens', () {
      final u1 = UserProfile(uid: '1', displayName: 'Jane Doe', email: 'j@d.com', joinedAt: DateTime.now());
      expect(u1.initials, equals('JD'));

      final u2 = UserProfile(uid: '2', displayName: 'PawWatch', email: 'pw@d.com', joinedAt: DateTime.now());
      expect(u2.initials, equals('PA'));

      final u3 = UserProfile(uid: '3', displayName: '', email: 'empty@d.com', joinedAt: DateTime.now());
      expect(u3.initials, equals('PW'));
    });
  });

  group('Flag Resolution Logic Tests', () {
    String resolveFlagType(Map<String, dynamic> f) {
      final raw = (f['type']?.toString() ?? '').toLowerCase().trim();
      if (raw == 'comment' || raw == 'comment_flag') return 'comment';
      if (raw == 'sighting' || raw == 'sighting_flag') return 'sighting';
      if (raw == 'review' || raw == 'review_flag') return 'review';
      if (raw == 'chat_message' || raw == 'chat' || raw == 'chat_flag') return 'chat_message';

      if (f['commentId'] != null && f['commentId'].toString().trim().isNotEmpty) {
        return 'comment';
      }
      if (f['sightingId'] != null && f['sightingId'].toString().trim().isNotEmpty) {
        return 'sighting';
      }
      if (f['chatId'] != null && f['chatId'].toString().trim().isNotEmpty) {
        return 'chat_message';
      }
      if (f['targetUserId'] != null && f['targetUserId'].toString().trim().isNotEmpty) {
        return 'review';
      }
      return raw.isNotEmpty ? raw : 'unknown';
    }

    test('Correctly identifies explicit flag types', () {
      expect(resolveFlagType({'type': 'sighting'}), equals('sighting'));
      expect(resolveFlagType({'type': 'comment'}), equals('comment'));
      expect(resolveFlagType({'type': 'review'}), equals('review'));
      expect(resolveFlagType({'type': 'chat_message'}), equals('chat_message'));
    });

    test('Correctly infers flag type from document keys when type is omitted', () {
      expect(resolveFlagType({'sightingId': 's_123', 'commentId': 'c_456'}), equals('comment'));
      expect(resolveFlagType({'sightingId': 's_123'}), equals('sighting'));
      expect(resolveFlagType({'chatId': 'chat_99'}), equals('chat_message'));
      expect(resolveFlagType({'targetUserId': 'usr_55'}), equals('review'));
    });
  });

  group('Sighting Model Logic Tests', () {
    test('Sighting displayTitle fallback', () {
      final sWithTitle = Sighting(
        id: 's1',
        reporterId: 'u1',
        reporterName: 'Jane D.',
        photoUrls: const [],
        latitude: -6.26,
        longitude: 106.81,
        title: 'Injured Kitten in Kemang',
        category: 'Kitten',
        description: 'Found this kitten near the shop.',
        urgency: 'urgent',
        createdAt: DateTime.now(),
        locationAddress: 'Jl. Kemang',
      );
      expect(sWithTitle.displayTitle, equals('Injured Kitten in Kemang'));

      final sWithoutTitle = Sighting(
        id: 's2',
        reporterId: 'u1',
        reporterName: 'John D.',
        photoUrls: const [],
        latitude: -6.27,
        longitude: 106.80,
        title: '',
        category: 'Cat',
        description: 'Found this cat near the street.',
        urgency: 'needsHelp',
        createdAt: DateTime.now(),
        locationAddress: 'Jl. Fatmawati',
      );
      expect(sWithoutTitle.displayTitle.isNotEmpty, isTrue);
    });
  });

  group('Text Moderation Anti-Spam & Content Tests', () {
    test('Rejects abusive or spam comments', () {
      expect(TextModerationService.hasProfanity('fuck this'), isTrue);
      expect(TextModerationService.hasProfanity('Friendly stray cat'), isFalse);
    });

    test('Validates report description length and quality', () {
      expect(TextModerationService.validateDescription('Short'), isNotNull);
      expect(
        TextModerationService.validateDescription('Found this cat resting under a parked car near Blok M square.'),
        isNull,
      );
    });
  });

  group('Admin Report & Comment Deletion Tests', () {
    test('Sighting deserializes isDeleted and deletedByAdmin correctly from map', () {
      final activeDoc = {
        'reporterId': 'u1',
        'reporterName': 'Alice',
        'title': 'Stray Tabby',
        'category': 'Stray',
        'urgency': 'needsHelp',
        'createdAt': '2026-09-30T10:00:00Z',
        'latitude': -6.2,
        'longitude': 106.8,
        'locationAddress': 'Jakarta',
        'description': 'Stray cat around the park',
      };
      final activeSighting = Sighting.fromMap(activeDoc, 's-active');
      expect(activeSighting.isDeleted, isFalse);
      expect(activeSighting.deletedByAdmin, isFalse);

      final deletedDoc = {
        'reporterId': 'u1',
        'reporterName': 'Alice',
        'title': 'Spam Sighting',
        'category': 'Stray',
        'urgency': 'needsHelp',
        'createdAt': '2026-09-30T10:00:00Z',
        'latitude': -6.2,
        'longitude': 106.8,
        'locationAddress': 'Jakarta',
        'description': 'Fake description',
        'isDeleted': true,
        'deletedByAdmin': true,
        'deletedBy': 'admin-uid',
        'deletedAt': '2026-09-30T12:00:00Z',
      };
      final deletedSighting = Sighting.fromMap(deletedDoc, 's-deleted');
      expect(deletedSighting.isDeleted, isTrue);
      expect(deletedSighting.deletedByAdmin, isTrue);
      expect(deletedSighting.deletedBy, equals('admin-uid'));
      expect(deletedSighting.deletedAt, isNotNull);
    });

    test('Deleted sightings are filtered out from feed and map circulation', () {
      final s1 = Sighting(
        id: 's1',
        reporterId: 'u1',
        reporterName: 'User 1',
        photoUrls: const [],
        latitude: -6.2,
        longitude: 106.8,
        locationAddress: 'Jakarta',
        description: 'Active cat report',
        urgency: 'needsHelp',
        category: 'Stray',
        createdAt: DateTime.now(),
        isDeleted: false,
      );

      final s2Deleted = Sighting(
        id: 's2',
        reporterId: 'u2',
        reporterName: 'User 2',
        photoUrls: const [],
        latitude: -6.2,
        longitude: 106.8,
        locationAddress: 'Jakarta',
        description: 'Deleted cat report',
        urgency: 'urgent',
        category: 'Injured',
        createdAt: DateTime.now(),
        isDeleted: true,
        deletedByAdmin: true,
        deletedReason: 'Spam or fraudulent sighting',
      );

      final rawList = [s1, s2Deleted];
      final mapCirculationList = rawList.where((s) => !s.isDeleted).toList();

      expect(mapCirculationList.length, equals(1));
      expect(mapCirculationList.first.id, equals('s1'));
      expect(mapCirculationList.any((s) => s.id == 's2'), isFalse);
    });

    test('Deleted sightings preserve deletedReason and are excluded from radial dispatch', () {
      final s = Sighting(
        id: 's-tombstone',
        reporterId: 'u1',
        reporterName: 'Reporter Bob',
        photoUrls: const [],
        latitude: -6.2,
        longitude: 106.8,
        locationAddress: 'Kemang',
        description: 'False alarm report',
        urgency: 'urgent',
        category: 'Injured',
        createdAt: DateTime.now(),
        isDeleted: true,
        deletedByAdmin: true,
        deletedReason: 'Wrong location / prank report',
      );

      expect(s.isDeleted, isTrue);
      expect(s.deletedByAdmin, isTrue);
      expect(s.deletedReason, equals('Wrong location / prank report'));
      expect(s.isEligibleForRadialDispatch, isFalse);

      final map = s.toMap();
      expect(map['deletedReason'], equals('Wrong location / prank report'));
      expect(map['isDeleted'], isTrue);

      final restored = Sighting.fromMap(map, 's-tombstone');
      expect(restored.deletedReason, equals('Wrong location / prank report'));
      expect(restored.isDeleted, isTrue);
    });

    test('Comments discussion thread retains deleted comments as tombstones without erasing them', () {
      final updates = [
        {
          'id': 'c1',
          'authorId': 'u1',
          'authorName': 'Alice',
          'text': 'Normal comment',
          'type': 'comment',
          'parentId': '',
          'isDeleted': false,
        },
        {
          'id': 'c2',
          'authorId': 'u2',
          'authorName': 'Spammer',
          'text': '[Removed by Admin]',
          'type': 'comment',
          'parentId': '',
          'isDeleted': true,
          'deletedByAdmin': true,
          'deletedBy': 'admin',
        },
        {
          'id': 'c3',
          'authorId': 'u3',
          'authorName': 'Bob',
          'text': 'Reply to c1',
          'type': 'comment',
          'parentId': 'c1',
          'isDeleted': false,
        },
        {
          'id': 'c4',
          'authorId': 'u4',
          'authorName': 'Troll',
          'text': '[Removed by Admin]',
          'type': 'comment',
          'parentId': 'c1',
          'isDeleted': true,
          'deletedByAdmin': true,
        },
      ];

      // Top-level comments logic: keep all parentId == '' even if isDeleted == true
      final top = updates.where((u) => (u['parentId'] ?? '') == '').toList();
      expect(top.length, equals(2));
      expect(top.map((c) => c['id']), containsAll(['c1', 'c2']));

      // Replies logic: keep all replies even if deleted
      List<Map<String, dynamic>> getReplies(String parentId) {
        return updates.where((r) => r['parentId'] == parentId).toList();
      }

      final c1Replies = getReplies('c1');
      expect(c1Replies.length, equals(2));
      expect(c1Replies.map((r) => r['id']), containsAll(['c3', 'c4']));

      // Verify admin tombstone classification
      bool isDeletedByAdmin(Map<String, dynamic> c) {
        final isDeleted = c['isDeleted'] == true;
        return isDeleted &&
            (c['deletedByAdmin'] == true ||
                c['deletedBy'] == 'admin' ||
                (c['text']?.toString().toLowerCase().contains('admin') ?? false));
      }

      expect(isDeletedByAdmin(updates[0]), isFalse);
      expect(isDeletedByAdmin(updates[1]), isTrue);
      expect(isDeletedByAdmin(updates[2]), isFalse);
      expect(isDeletedByAdmin(updates[3]), isTrue);
    });

    test('Admin comments and replies tagging and authority badge logic', () {
      final comments = [
        {
          'id': 'c1',
          'authorId': 'u1',
          'authorName': 'Alice',
          'authorRole': 'user',
          'isAdmin': false,
          'isAnonymous': false,
        },
        {
          'id': 'c2',
          'authorId': 'adm-99',
          'authorName': 'PawWatch Admin',
          'authorRole': 'admin',
          'isAdmin': true,
          'isAnonymous': false,
        },
        {
          'id': 'c3',
          'authorId': 'adm-99',
          'authorName': 'Anonymous',
          'authorRole': 'admin',
          'isAdmin': true,
          'isAnonymous': true,
        },
      ];

      bool checkIsAuthorAdmin(Map<String, dynamic> c) {
        final isAnon = c['isAnonymous'] == true;
        return !isAnon &&
            (c['isAdmin'] == true ||
                c['authorRole'] == 'admin' ||
                (c['authorName']?.toString().toLowerCase().contains('admin') ?? false));
      }

      expect(checkIsAuthorAdmin(comments[0]), isFalse);
      expect(checkIsAuthorAdmin(comments[1]), isTrue);
      // If marked anonymous, admin badge is suppressed
      expect(checkIsAuthorAdmin(comments[2]), isFalse);
    });
  });

  group('Notification Bell Unread Dot & Deletion Logic Tests', () {
    bool computeHasUnread({
      required List<Map<String, dynamic>> announcements,
      required Set<String> readNotificationIds,
      required Set<String> dismissedAnnouncementIds,
    }) {
      final activeAnnouncements = announcements.where((a) {
        final id = a['docId']?.toString();
        return id != null && !dismissedAnnouncementIds.contains(id);
      }).toList();

      return activeAnnouncements.any((a) {
        final id = a['docId']?.toString();
        return id != null && !readNotificationIds.contains(id);
      });
    }

    test('Initial empty state has no unread dot', () {
      final hasUnread = computeHasUnread(
        announcements: [],
        readNotificationIds: {},
        dismissedAnnouncementIds: {},
      );
      expect(hasUnread, isFalse);
    });

    test('Unread dot appears when there is an unread announcement', () {
      final announcements = [
        {'docId': 'ann-1', 'title': 'Rabies Clinic', 'isActive': true},
      ];
      final hasUnread = computeHasUnread(
        announcements: announcements,
        readNotificationIds: {},
        dismissedAnnouncementIds: {},
      );
      expect(hasUnread, isTrue);
    });

    test('Unread dot disappears once notifications are opened / marked as read', () {
      final announcements = [
        {'docId': 'ann-1', 'title': 'Rabies Clinic', 'isActive': true},
      ];
      final readIds = <String>{};

      // Before reading
      expect(
        computeHasUnread(
          announcements: announcements,
          readNotificationIds: readIds,
          dismissedAnnouncementIds: {},
        ),
        isTrue,
      );

      // User opens modal -> marks as read
      readIds.add('ann-1');

      // After opening modal
      expect(
        computeHasUnread(
          announcements: announcements,
          readNotificationIds: readIds,
          dismissedAnnouncementIds: {},
        ),
        isFalse,
      );
    });

    test('Unread dot reappears when a new notification arrives', () {
      final announcements = <Map<String, dynamic>>[
        {'docId': 'ann-1', 'title': 'Clinic', 'isActive': true},
      ];
      final readIds = <String>{'ann-1'};

      // Both previously read
      expect(
        computeHasUnread(
          announcements: announcements,
          readNotificationIds: readIds,
          dismissedAnnouncementIds: {},
        ),
        isFalse,
      );

      // New announcement arrives
      announcements.add({'docId': 'ann-2', 'title': 'Emergency Adoption', 'isActive': true});

      // Dot reappears
      expect(
        computeHasUnread(
          announcements: announcements,
          readNotificationIds: readIds,
          dismissedAnnouncementIds: {},
        ),
        isTrue,
      );
    });

    test('Deleting/dismissing a notification removes it from unread computation', () {
      final announcements = [
        {'docId': 'ann-1', 'title': 'Clinic', 'isActive': true},
      ];
      final dismissedAnnouncements = <String>{};

      expect(
        computeHasUnread(
          announcements: announcements,
          readNotificationIds: {},
          dismissedAnnouncementIds: dismissedAnnouncements,
        ),
        isTrue,
      );

      // User deletes announcement
      dismissedAnnouncements.add('ann-1');

      expect(
        computeHasUnread(
          announcements: announcements,
          readNotificationIds: {},
          dismissedAnnouncementIds: dismissedAnnouncements,
        ),
        isFalse,
      );
    });

    test('Clear All notifications dismisses all active items', () {
      final announcements = [
        {'docId': 'ann-1', 'title': 'Clinic', 'isActive': true},
        {'docId': 'ann-2', 'title': 'Adoption Fair', 'isActive': true},
      ];
      final dismissedAnnouncements = <String>{};
      final readIds = <String>{};

      // Clear all
      for (final a in announcements) {
        final id = a['docId'] as String;
        dismissedAnnouncements.add(id);
        readIds.add(id);
      }

      final activeAnnouncements = announcements
          .where((a) => !dismissedAnnouncements.contains(a['docId']))
          .toList();

      expect(activeAnnouncements, isEmpty);
      expect(
        computeHasUnread(
          announcements: announcements,
          readNotificationIds: readIds,
          dismissedAnnouncementIds: dismissedAnnouncements,
        ),
        isFalse,
      );
    });
  });

  group('Sighting Action History & Edit/Delete Lock Tests', () {
    test('Newly reported sighting does not lock editing and deletion', () {
      final freshSighting = Sighting(
        id: 'sight-fresh',
        reporterId: 'user-reporter',
        reporterName: 'Reporter',
        title: 'Calico cat near park bench',
        description: 'Spotted resting peacefully under a tree',
        urgency: 'low',
        category: 'Spotted',
        latitude: 1.3521,
        longitude: 103.8198,
        locationAddress: 'Central Park',
        photoUrls: ['https://example.com/cat.jpg'],
        createdAt: DateTime.now(),
        lastSeenAt: DateTime.now(),
        lastSeenStatus: 'still_here',
      );

      expect(freshSighting.hasActionHistory, isFalse);
    });

    test('Sighting with genuine action log locks editing and deletion', () {
      final actionLoggedSighting = Sighting(
        id: 'sight-active',
        reporterId: 'user-reporter',
        reporterName: 'Reporter',
        title: 'Injured cat near drain',
        description: 'Limping left paw',
        urgency: 'urgent',
        category: 'Needs Help',
        latitude: 1.3521,
        longitude: 103.8198,
        locationAddress: 'Block 123',
        photoUrls: ['https://example.com/cat.jpg'],
        createdAt: DateTime.now(),
        lastSeenAt: DateTime.now(),
        lastSeenStatus: 'stillHere',
        rescuerUserIds: ['volunteer-1'],
        hasVetVisitFlag: true,
      );

      expect(actionLoggedSighting.hasActionHistory, isTrue);
    });
  });
}

