import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/sighting.dart';

class FirebaseService {
  static final FirebaseService instance = FirebaseService._internal();
  FirebaseService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;

  /// Uploads a list of local photo files to Firebase Storage
  Future<List<String>> uploadPhotos(List<File> photoFiles, String sightingId) async {
    final List<String> urls = [];

    for (int i = 0; i < photoFiles.length; i++) {
      try {
        final file = photoFiles[i];
        final filename = 'photo_${i}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final ref = _storage.ref().child('sightings').child(sightingId).child(filename);

        final uploadTask = ref.putFile(
          file,
          SettableMetadata(contentType: 'image/jpeg'),
        );

        final snapshot = await uploadTask;
        final downloadUrl = await snapshot.ref.getDownloadURL();
        urls.add(downloadUrl);
      } catch (e) {
        debugPrint('Firebase Storage photo upload notice: $e');
        // If storage rule or network blocks upload, store local path as fallback
        urls.add(photoFiles[i].path);
      }
    }

    return urls;
  }

  /// Automatically categorizes the sighting based on description and urgency
  String _determineCategory(String description, String urgency) {
    final desc = description.toLowerCase();
    if (desc.contains('kitten') || desc.contains('baby') || desc.contains('anak kucing')) {
      return 'Kitten';
    }
    if (desc.contains('injured') ||
        desc.contains('hurt') ||
        desc.contains('luka') ||
        desc.contains('limp') ||
        desc.contains('hit') ||
        desc.contains('tabrak')) {
      return 'Injured';
    }
    if (desc.contains('feed') || desc.contains('food') || desc.contains('makan')) {
      return 'Feeding Spot';
    }
    if (urgency == 'urgent') {
      return 'Urgent Rescue';
    }
    if (urgency == 'resolved') {
      return 'Resolved';
    }
    return 'Spotted';
  }

  /// Creates a new sighting in Cloud Firestore, uploads photos, and awards +50 XP
  Future<Sighting> createSighting({
    required String title,
    required List<File> photos,
    required double latitude,
    required double longitude,
    required String locationAddress,
    required String description,
    required String urgency,
    String? category,
    String? routineHours,
  }) async {
    final docRef = _firestore.collection('sightings').doc();
    final sightingId = docRef.id;

    // 1. Upload photos to Firebase Storage
    List<String> photoUrls = [];
    if (photos.isNotEmpty) {
      photoUrls = await uploadPhotos(photos, sightingId);
    }

    final user = _auth.currentUser;
    final reporterId = user?.uid ?? 'anonymous_user';
    final reporterName = user?.displayName?.isNotEmpty == true
        ? user!.displayName!
        : (user?.email?.split('@').first ?? 'PawWatcher');

    final finalCategory = (category != null && category.trim().isNotEmpty)
        ? category.trim()
        : _determineCategory(description, urgency);
    final now = DateTime.now();

    final sighting = Sighting(
      id: sightingId,
      title: title.trim(),
      reporterId: reporterId,
      reporterName: reporterName,
      photoUrls: photoUrls,
      latitude: latitude,
      longitude: longitude,
      locationAddress: locationAddress,
      description: description,
      urgency: urgency,
      category: finalCategory,
      createdAt: now,
      commentCount: 0,
      upvotes: 0,
      routineHours: routineHours?.trim(),
      lastSeenAt: now,
      lastSeenStatus: 'still_here',
    );

    // 2. Write to Cloud Firestore
    await docRef.set(sighting.toMap());

    // 3. Award +50 XP to the reporting user in Firestore
    if (user != null) {
      try {
        final userRef = _firestore.collection('users').doc(user.uid);
        await userRef.set({
          'xp': FieldValue.increment(50),
          'reportsCount': FieldValue.increment(1),
          'lastActive': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('XP update notice: $e');
      }
    }

    return sighting;
  }

  /// Streams all sightings in real-time from Cloud Firestore
  Stream<List<Sighting>> streamSightings() {
    return _firestore
        .collection('sightings')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => Sighting.fromFirestore(doc)).toList();
    });
  }

  /// Stream a single sighting document by ID
  Stream<Sighting?> streamSightingById(String sightingId) {
    return _firestore
        .collection('sightings')
        .doc(sightingId)
        .snapshots()
        .map((doc) => doc.exists ? Sighting.fromFirestore(doc) : null);
  }

  /// Stream comments (and action-auto-posts) for a sighting, sorted by time
  Stream<List<Map<String, dynamic>>> streamCommunityUpdates(String sightingId) {
    return _firestore
        .collection('sightings')
        .doc(sightingId)
        .collection('updates')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final data = d.data();
              data['id'] = d.id;
              return data;
            }).toList());
  }

  /// Add a comment / reply to a sighting
  Future<void> addComment({
    required String sightingId,
    required String text,
    String? parentId,
    bool anonymous = false,
  }) async {
    final user = _auth.currentUser;
    final uid = user?.uid ?? 'anon';
    final name = anonymous
        ? 'Anonymous'
        : (user?.displayName?.isNotEmpty == true
            ? user!.displayName!
            : (user?.email?.split('@').first ?? 'PawWatcher'));

    final batch = _firestore.batch();

    final updateRef = _firestore
        .collection('sightings')
        .doc(sightingId)
        .collection('updates')
        .doc();

    batch.set(updateRef, {
      'type': 'comment',
      'authorId': uid,
      'authorName': name,
      'text': text.trim(),
      'parentId': parentId ?? '',
      'isAnonymous': anonymous,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Increment commentCount on the sighting
    final sightingRef = _firestore.collection('sightings').doc(sightingId);
    batch.update(sightingRef, {'commentCount': FieldValue.increment(1)});

    await batch.commit();
  }

  /// Log a rescue action (Fed, Vet Visit, Took In, etc.) with verified photo proof
  Future<int> logRescueAction({
    required String sightingId,
    required String action, // 'fed', 'vet', 'tookIn', 'sheltered', 'rehomed', 'stillHere', 'moved', 'notHere', 'holding', 'helpedOffline'
    bool anonymous = false,
    File? proofPhotoFile,
    String? proofPhotoUrl,
    String? customNote,
    double? updatedLatitude,
    double? updatedLongitude,
    String? updatedLocationAddress,
    bool markResolved = false,
  }) async {
    final user = _auth.currentUser;
    final uid = user?.uid ?? 'anon';
    final name = anonymous
        ? 'Anonymous'
        : (user?.displayName?.isNotEmpty == true
            ? user!.displayName!
            : (user?.email?.split('@').first ?? 'PawWatcher'));

    String? finalProofUrl = proofPhotoUrl;
    if (proofPhotoFile != null) {
      final uploaded = await uploadPhotos([proofPhotoFile], sightingId);
      if (uploaded.isNotEmpty) {
        finalProofUrl = uploaded.first;
      }
    }

    const xpMap = {
      'fed': 30,
      'vet': 100,
      'tookIn': 150,
      'sheltered': 120,
      'rehomed': 200,
      'stillHere': 15,
      'moved': 25,
      'notHere': 10,
      'holding': 100,
      'helpedOffline': 30,
    };

    const autoMessages = {
      'fed': 'gave the cat some food.',
      'vet': 'took the cat to the vet.',
      'tookIn': 'took the cat in and is taking care of it.',
      'sheltered': 'brought the cat to a shelter.',
      'rehomed': 'found a loving home for the cat! 🎉',
      'stillHere': 'confirmed the cat is still at this spot.',
      'moved': 'spotted the cat nearby and updated location.',
      'notHere': 'checked this spot, but the cat is not here right now.',
      'holding': 'secured the cat in temporary holding / foster care.',
      'helpedOffline': 'reported that the cat was already helped or taken in by a local resident. 🏠',
    };

    final xp = xpMap[action] ?? 10;
    String message = autoMessages[action] ?? 'took action.';
    if (customNote != null && customNote.trim().isNotEmpty) {
      message = '$message "${customNote.trim()}"';
    }

    final docData = <String, dynamic>{
      'type': 'action',
      'action': action,
      'authorId': uid,
      'authorName': name,
      'text': message,
      'isAnonymous': anonymous,
      'parentId': '',
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (finalProofUrl != null && finalProofUrl.isNotEmpty) {
      docData['proofPhotoUrl'] = finalProofUrl;
    }
    if (updatedLocationAddress != null && updatedLocationAddress.isNotEmpty) {
      docData['updatedLocationAddress'] = updatedLocationAddress;
    }

    // 2. Update parent Sighting document with In-Care custody and last-seen state
    String reporterId = '';
    try {
      final sightingDoc =
          await _firestore.collection('sightings').doc(sightingId).get();
      if (sightingDoc.exists) {
        reporterId = sightingDoc.data()?['reporterId']?.toString() ?? '';
        final updateFields = <String, dynamic>{
          'lastSeenAt': FieldValue.serverTimestamp(),
          'lastSeenStatus': action,
          'rescueClaimed': false,
          'rescueClaimedBy': '',
          'rescueClaimedByName': '',
          'rescueClaimedAt': null,
        };
        if (customNote != null && customNote.trim().isNotEmpty) {
          updateFields['lastSeenNote'] = customNote.trim();
        }
        if (updatedLatitude != null && updatedLongitude != null) {
          updateFields['updatedLatitude'] = updatedLatitude;
          updateFields['updatedLongitude'] = updatedLongitude;
        }
        if (updatedLocationAddress != null && updatedLocationAddress.isNotEmpty) {
          updateFields['updatedLocationAddress'] = updatedLocationAddress;
        }

        // Custody State Transitions:
        if (action == 'vet') {
          updateFields['careStatus'] = 'inCare_vet';
          updateFields['careTakerId'] = uid;
          updateFields['careTakerName'] = name;
          updateFields['careStartedAt'] = FieldValue.serverTimestamp();
        } else if (action == 'tookIn' || action == 'holding') {
          updateFields['careStatus'] = 'inCare_foster';
          updateFields['careTakerId'] = uid;
          updateFields['careTakerName'] = name;
          updateFields['careStartedAt'] = FieldValue.serverTimestamp();
        } else if (action == 'sheltered' || markResolved) {
          updateFields['careStatus'] = 'resolved';
          updateFields['urgency'] = 'resolved';
          updateFields['resolvedByAction'] = action;
          updateFields['resolvedAt'] = FieldValue.serverTimestamp();
          if (updatedLatitude != null && updatedLongitude != null) {
            updateFields['latitude'] = updatedLatitude;
            updateFields['longitude'] = updatedLongitude;
          }
          if (updatedLocationAddress != null && updatedLocationAddress.isNotEmpty) {
            updateFields['locationAddress'] = updatedLocationAddress;
          }
        } else if (action == 'returnedToSpot') {
          updateFields['careStatus'] = 'onStreet';
          updateFields['careTakerId'] = null;
          updateFields['careTakerName'] = null;
          updateFields['careStartedAt'] = null;
        } else if (action == 'rehomed') {
          updateFields['careStatus'] = 'resolved';
          updateFields['urgency'] = 'resolved';
          updateFields['resolvedByAction'] = action;
          updateFields['resolvedAt'] = FieldValue.serverTimestamp();
        }

        await _firestore
            .collection('sightings')
            .doc(sightingId)
            .update(updateFields);
      }
    } catch (e) {
      debugPrint('Parent sighting update notice: $e');
    }

    // 4. Calculate XP and check if direct award (reporter) or pending confirmation (community rescuer)
    final isOngoingAction = action == 'fed' || action == 'stillHere' || action == 'moved' || action == 'notHere';
    final isReporter = uid == reporterId;
    int effectiveXp = xp;
    Map<String, dynamic> existingCooldowns = {};

    // Check 2-hour spot cooldown on ongoing actions (feeding / presence checks)
    if (user != null && !anonymous) {
      try {
        final userDoc = await _firestore.collection('users').doc(uid).get();
        final userData = userDoc.data() ?? {};
        final rawCooldowns = (userData['spotCooldowns'] as Map<String, dynamic>?) ?? {};
        existingCooldowns = Map<String, dynamic>.from(rawCooldowns);

        final lastSpotTimestamp = existingCooldowns[sightingId] ?? userData['spotCooldowns.$sightingId'];
        DateTime? lastSpotUpdate;
        if (lastSpotTimestamp is Timestamp) {
          lastSpotUpdate = lastSpotTimestamp.toDate();
        } else if (lastSpotTimestamp is String) {
          lastSpotUpdate = DateTime.tryParse(lastSpotTimestamp);
        }

        if (lastSpotUpdate != null && DateTime.now().difference(lastSpotUpdate).inMinutes < 120) {
          if (isOngoingAction) {
            effectiveXp = 0; // On 2-hour cooldown for this spot
          }
        }
      } catch (e) {
        debugPrint('Spot cooldown check notice: $e');
      }
    }

    // Attach confirmation state and pending XP to the update document
    docData['isReporterConfirmed'] = isReporter;
    docData['pendingXp'] = effectiveXp;
    if (isReporter) {
      docData['confirmedBy'] = uid;
      docData['confirmedAt'] = FieldValue.serverTimestamp();
    }

    // 1. Post update to community feed
    await _firestore
        .collection('sightings')
        .doc(sightingId)
        .collection('updates')
        .add(docData);

    // If reporter logged their own action and eligible for XP: award immediately
    if (user != null && !anonymous && isReporter) {
      try {
        final userDocRef = _firestore.collection('users').doc(uid);
        final updates = <String, dynamic>{
          'lastActive': FieldValue.serverTimestamp(),
        };
        if (effectiveXp > 0) {
          updates['xp'] = FieldValue.increment(effectiveXp);
        }
        if (isOngoingAction) {
          existingCooldowns[sightingId] = FieldValue.serverTimestamp();
          updates['spotCooldowns'] = existingCooldowns;
        }
        await userDocRef.set(updates, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Direct reporter XP award notice: $e');
      }
    }

    return isReporter ? effectiveXp : 0;
  }

  /// Reporter confirms a community rescue action with a verified checkmark & awards pending XP
  Future<int> confirmRescueAction(String sightingId, String updateId) async {
    final user = _auth.currentUser;
    if (user == null) return 0;

    try {
      final updateRef = _firestore
          .collection('sightings')
          .doc(sightingId)
          .collection('updates')
          .doc(updateId);

      final updateDoc = await updateRef.get();
      if (!updateDoc.exists) return 0;
      final data = updateDoc.data() ?? {};
      if (data['isReporterConfirmed'] == true) return 0;

      final authorId = data['authorId']?.toString() ?? '';
      final action = data['action']?.toString() ?? '';
      final isOngoingAction = action == 'fed' || action == 'stillHere' || action == 'moved' || action == 'notHere';
      final pendingXp = (data['pendingXp'] is num)
          ? (data['pendingXp'] as num).toInt()
          : (action == 'fed'
              ? 30
              : (action == 'vet'
                  ? 100
                  : (action == 'tookIn'
                      ? 150
                      : (action == 'rehomed' ? 200 : 15))));

      // 1. Mark as verified by reporter
      await updateRef.update({
        'isReporterConfirmed': true,
        'confirmedBy': user.uid,
        'confirmedAt': FieldValue.serverTimestamp(),
      });

      // 2. Award pending XP to the rescuer and apply spot cooldown
      if (authorId.isNotEmpty && authorId != 'anon') {
        final authorDoc = await _firestore.collection('users').doc(authorId).get();
        final authorData = authorDoc.data() ?? {};
        final authorCooldowns = Map<String, dynamic>.from((authorData['spotCooldowns'] as Map<String, dynamic>?) ?? {});
        final updates = <String, dynamic>{
          'lastActive': FieldValue.serverTimestamp(),
        };
        if (pendingXp > 0) {
          updates['xp'] = FieldValue.increment(pendingXp);
        }
        if (isOngoingAction) {
          authorCooldowns[sightingId] = FieldValue.serverTimestamp();
          updates['spotCooldowns'] = authorCooldowns;
        }
        await _firestore.collection('users').doc(authorId).set(updates, SetOptions(merge: true));
      }

      return pendingXp;
    } catch (e) {
      debugPrint('Confirm rescue action notice: $e');
      return 0;
    }
  }

  /// Claim "I'm on my way" rescue button
  Future<void> claimRescue(String sightingId) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final name = user.displayName?.isNotEmpty == true
        ? user.displayName!
        : (user.email?.split('@').first ?? 'PawWatcher');

    final sightingRef = _firestore.collection('sightings').doc(sightingId);
    await sightingRef.update({
      'rescueClaimed': true,
      'rescueClaimedBy': user.uid,
      'rescueClaimedByName': name,
      'rescueClaimedAt': FieldValue.serverTimestamp(),
    });

    // Post auto-update
    await _firestore
        .collection('sightings')
        .doc(sightingId)
        .collection('updates')
        .add({
      'type': 'onMyWay',
      'authorId': user.uid,
      'authorName': name,
      'text': "is on their way to help! (45m arrival window) 🐾",
      'isAnonymous': false,
      'parentId': '',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Check and expire a rescue claim that timed out past 45 mins without action
  Future<void> checkAndExpireRescueClaim(String sightingId) async {
    try {
      final doc = await _firestore.collection('sightings').doc(sightingId).get();
      if (!doc.exists) return;
      final data = doc.data() ?? {};
      final bool claimed = data['rescueClaimed'] == true;
      final claimerUid = data['rescueClaimedBy']?.toString() ?? '';
      final claimerName = data['rescueClaimedByName']?.toString() ?? 'Rescuer';
      final claimedAt = data['rescueClaimedAt'];

      if (!claimed || claimedAt == null) return;

      DateTime parsedClaimedAt = DateTime.now();
      if (claimedAt is Timestamp) {
        parsedClaimedAt = claimedAt.toDate();
      } else if (claimedAt is String) {
        parsedClaimedAt = DateTime.tryParse(claimedAt) ?? DateTime.now();
      }

      final diff = DateTime.now().difference(parsedClaimedAt);
      if (diff.inMinutes < 45) return; // Still within 45m window

      // 1. Release the spot
      await _firestore.collection('sightings').doc(sightingId).update({
        'rescueClaimed': false,
        'rescueClaimedBy': '',
        'rescueClaimedByName': '',
        'rescueClaimedAt': null,
      });

      // 2. Invalidate onMyWay updates
      final updatesSnap = await _firestore
          .collection('sightings')
          .doc(sightingId)
          .collection('updates')
          .where('type', isEqualTo: 'onMyWay')
          .get();

      for (final uDoc in updatesSnap.docs) {
        if (uDoc.data()['isCancelled'] != true) {
          await uDoc.reference.update({
            'isCancelled': true,
            'cancelledAt': FieldValue.serverTimestamp(),
          });
        }
      }

      // 3. Post timeout notice to community feed
      await _firestore
          .collection('sightings')
          .doc(sightingId)
          .collection('updates')
          .add({
        'type': 'onMyWayCancelled',
        'authorId': 'system',
        'authorName': 'PawWatch Bot',
        'text': 'Rescue claim timed out after 45m without action proof. Spot is open again for rescuers! 🐾',
        'isAnonymous': false,
        'parentId': '',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 4. Ghosting accountability: deduct 30 XP from abandoned claimant
      if (claimerUid.isNotEmpty) {
        await _firestore.collection('users').doc(claimerUid).set({
          'xp': FieldValue.increment(-30),
          'abandonedClaimsCount': FieldValue.increment(1),
          'lastGhostedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Check expire rescue claim notice: $e');
    }
  }

  /// Cancel "I'm on my way" claim (by claimant or reporter)
  Future<void> cancelRescueClaim(String sightingId) async {
    final user = _auth.currentUser;
    final name = user?.displayName?.isNotEmpty == true
        ? user!.displayName!
        : (user?.email?.split('@').first ?? 'PawWatcher');

    await _firestore.collection('sightings').doc(sightingId).update({
      'rescueClaimed': false,
      'rescueClaimedBy': '',
      'rescueClaimedByName': '',
      'rescueClaimedAt': null,
    });

    // 1. Mark existing active onMyWay updates for this sighting as cancelled
    try {
      final updatesSnap = await _firestore
          .collection('sightings')
          .doc(sightingId)
          .collection('updates')
          .where('type', isEqualTo: 'onMyWay')
          .get();

      for (final doc in updatesSnap.docs) {
        if (doc.data()['isCancelled'] != true) {
          await doc.reference.update({
            'isCancelled': true,
            'cancelledAt': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (e) {
      debugPrint('Cancel updates notice: $e');
    }

    // 2. Post a clear community notice that the trip was cancelled
    await _firestore
        .collection('sightings')
        .doc(sightingId)
        .collection('updates')
        .add({
      'type': 'onMyWayCancelled',
      'authorId': user?.uid ?? 'anon',
      'authorName': name,
      'text': 'cancelled their rescue trip. This spot is open for anyone to help! 🐾',
      'isAnonymous': false,
      'parentId': '',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Delete a sighting (owner only)
  Future<void> deleteSighting(String sightingId) async {
    await _firestore.collection('sightings').doc(sightingId).delete();
  }

  /// Update sighting title and/or description (owner only)
  Future<void> updateSighting(String sightingId, {String? title, String? description}) async {
    final data = <String, dynamic>{};
    if (title != null) data['title'] = title.trim();
    if (description != null) data['description'] = description.trim();
    if (data.isNotEmpty) {
      await _firestore.collection('sightings').doc(sightingId).update(data);
    }
  }

  /// Flag a sighting as inappropriate
  Future<void> flagSighting(String sightingId, String reason) async {
    final user = _auth.currentUser;
    await _firestore.collection('flags').add({
      'type': 'sighting',
      'sightingId': sightingId,
      'reportedBy': user?.uid ?? 'anon',
      'reason': reason,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Edit a comment or reply (author only)
  Future<void> editComment({
    required String sightingId,
    required String commentId,
    required String newText,
  }) async {
    await _firestore
        .collection('sightings')
        .doc(sightingId)
        .collection('updates')
        .doc(commentId)
        .update({
      'text': newText.trim(),
      'isEdited': true,
      'editedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Soft-delete a comment or reply (author only)
  Future<void> deleteComment({
    required String sightingId,
    required String commentId,
  }) async {
    final batch = _firestore.batch();
    final commentRef = _firestore
        .collection('sightings')
        .doc(sightingId)
        .collection('updates')
        .doc(commentId);

    batch.update(commentRef, {
      'text': '[Comment deleted]',
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
    });

    // Decrement comment count on sighting doc
    final sightingRef = _firestore.collection('sightings').doc(sightingId);
    batch.update(sightingRef, {'commentCount': FieldValue.increment(-1)});

    await batch.commit();
  }

  /// Report/flag a comment or reply
  Future<void> flagComment({
    required String sightingId,
    required String commentId,
    required String reason,
  }) async {
    final user = _auth.currentUser;
    await _firestore.collection('flags').add({
      'type': 'comment',
      'sightingId': sightingId,
      'commentId': commentId,
      'reportedBy': user?.uid ?? 'anon',
      'reason': reason,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Sample seed sightings for initial empty state display
  static List<Sighting> get sampleSightings => [
        Sighting(
          id: 'seed_1',
          reporterId: 'seed_user_1',
          reporterName: 'Jane D.',
          photoUrls: [],
          latitude: -6.2615,
          longitude: 106.8106,
          locationAddress: 'Jl. Kemang Raya, Jakarta Selatan',
          description: 'Seems scared and hungry.\nHanging around the trash area.',
          urgency: 'urgent',
          category: 'Kitten',
          createdAt: DateTime.now().subtract(const Duration(minutes: 15)),
          commentCount: 2,
        ),
        Sighting(
          id: 'seed_2',
          reporterId: 'seed_user_2',
          reporterName: 'Rafi A.',
          photoUrls: [],
          latitude: -6.2750,
          longitude: 106.8000,
          locationAddress: 'Jl. Cipete Raya, Jakarta Selatan',
          description: 'Checked and treated.\nDoing well now and resting at the clinic.',
          urgency: 'resolved',
          category: 'Vet Visit',
          createdAt: DateTime.now().subtract(const Duration(hours: 2)),
          commentCount: 4,
        ),
        Sighting(
          id: 'seed_3',
          reporterId: 'seed_user_3',
          reporterName: 'Sinta P.',
          photoUrls: [],
          latitude: -6.2550,
          longitude: 106.7900,
          locationAddress: 'Jl. Radio Dalam, Jakarta Selatan',
          description: "Can't take care of this kitten for long.\nLooking for a kind foster or adopter.",
          urgency: 'needsHelp',
          category: 'Kitten',
          createdAt: DateTime.now().subtract(const Duration(hours: 3)),
          commentCount: 5,
        ),
        Sighting(
          id: 'seed_4',
          reporterId: 'seed_user_4',
          reporterName: 'Bima W.',
          photoUrls: [],
          latitude: -6.2900,
          longitude: 106.7950,
          locationAddress: 'Jl. Fatmawati, Jakarta Selatan',
          description: 'Limping badly. Looks like it was hit.\nNeeds immediate vet attention.',
          urgency: 'urgent',
          category: 'Injured',
          createdAt: DateTime.now().subtract(const Duration(hours: 4)),
          commentCount: 7,
        ),
        Sighting(
          id: 'seed_5',
          reporterId: 'seed_user_5',
          reporterName: 'Citra M.',
          photoUrls: [],
          latitude: -6.2600,
          longitude: 106.8050,
          locationAddress: 'Jl. Panglima Polim, Jakarta Selatan',
          description: 'Found a loving family for this cutie.\nSo happy it worked out.',
          urgency: 'resolved',
          category: 'Rehomed',
          createdAt: DateTime.now().subtract(const Duration(hours: 5)),
          commentCount: 12,
        ),
      ];
}
