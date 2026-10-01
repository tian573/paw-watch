import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/sighting.dart';
import '../models/user_profile.dart';
import '../models/chat_message.dart';

class FirebaseService {
  static final FirebaseService instance = FirebaseService._internal();
  FirebaseService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static final Map<String, DateTime> _commentCooldowns = {};
  static final Map<String, String> _commentLastTexts = {};
  static const Duration commentCooldown = Duration(seconds: 15);

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
        try {
          final bytes = await photoFiles[i].readAsBytes();
          // Under 1MB: base64 data URI enables cross-device & cross-platform rendering
          if (bytes.lengthInBytes <= 900 * 1024) {
            urls.add('data:image/jpeg;base64,${base64Encode(bytes)}');
          } else {
            urls.add(photoFiles[i].path);
          }
        } catch (_) {
          urls.add(photoFiles[i].path);
        }
      }
    }

    return urls;
  }

  /// Uploads a local video file (MP4) to Firebase Storage
  Future<String?> uploadVideo(File videoFile, String sightingId) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ref = _storage
          .ref()
          .child('sightings')
          .child(sightingId)
          .child('videos')
          .child('${timestamp}_proof.mp4');

      final uploadTask = ref.putFile(
        videoFile,
        SettableMetadata(contentType: 'video/mp4'),
      );

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      debugPrint('Firebase Storage video upload notice: $e');
      // Fallback to local path so video attachment is not lost if upload fails or is in offline test
      return videoFile.path;
    }
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
    String? temperament,
    bool hasEarTip = false,
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

    List<String> tags = [];
    if (hasEarTip) {
      tags.add('✂️ Ear-Tipped (Spayed/Neutered)');
    }

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
      temperament: temperament,
      hasEarTip: hasEarTip,
      healthTags: tags,
    );

    // 2. Write to Cloud Firestore
    await docRef.set(sighting.toMap());

    // 3. Award +50 XP to the reporting user in Firestore
    if (user != null) {
      try {
        final userRef = _firestore.collection('users').doc(user.uid);
        await userRef.set({
          'xp': FieldValue.increment(50),
          'totalXp': FieldValue.increment(50),
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
      return snapshot.docs
          .map((doc) => Sighting.fromFirestore(doc))
          .toList();
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

  /// Add a comment / reply to a sighting with spam protection & cooldown
  Future<void> addComment({
    required String sightingId,
    required String text,
    String? parentId,
    bool anonymous = false,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) throw 'Comment cannot be empty.';

    final user = _auth.currentUser;
    final uid = user?.uid ?? 'anon';
    final isAdmin = isCurrentUserAdmin;

    // Anti-spam: Rate-limit cooldown (bypass for admins)
    if (!isAdmin) {
      final lastTime = _commentCooldowns[uid];
      if (lastTime != null) {
        final elapsed = DateTime.now().difference(lastTime);
        if (elapsed < commentCooldown) {
          final remaining = (commentCooldown - elapsed).inSeconds + 1;
          throw 'Please wait ${remaining}s before commenting again (spam cooldown).';
        }
      }

      // Anti-spam: Duplicate comment filter
      final lastText = _commentLastTexts[uid];
      if (lastText != null &&
          lastText.toLowerCase() == trimmed.toLowerCase() &&
          lastTime != null &&
          DateTime.now().difference(lastTime) < const Duration(minutes: 2)) {
        throw 'Duplicate comment detected. Please avoid posting identical messages.';
      }
    }

    final effectiveAnon = anonymous && !isAdmin;
    final name = effectiveAnon
        ? 'Anonymous'
        : (user?.displayName?.isNotEmpty == true
            ? user!.displayName!
            : (isAdmin ? 'PawWatch Admin' : (user?.email?.split('@').first ?? 'PawWatcher')));

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
      'authorRole': isAdmin ? 'admin' : 'user',
      'isAdmin': isAdmin,
      'text': trimmed,
      'parentId': parentId ?? '',
      'isAnonymous': effectiveAnon,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Increment commentCount on the sighting
    final sightingRef = _firestore.collection('sightings').doc(sightingId);
    batch.update(sightingRef, {'commentCount': FieldValue.increment(1)});

    await batch.commit();

    // Update cooldown records
    _commentCooldowns[uid] = DateTime.now();
    _commentLastTexts[uid] = trimmed;
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
    String? carePlanGoal,
    int? carePlanDurationDays,
    List<int>? careMilestoneDays,
    List<String>? customMilestoneTitles,
    String? temperament,
  }) async {
    final user = _auth.currentUser;
    final uid = user?.uid ?? 'anon';
    final name = anonymous
        ? 'Anonymous'
        : (user?.displayName?.isNotEmpty == true
            ? user!.displayName!
            : (user?.email?.split('@').first ?? 'PawWatcher'));

    // Rescuer focus rule: cannot log actions on another cat while "On My Way" or managing pending vet care
    if (uid != 'anon') {
      final activeTrip = await getActiveRescueTrip(uid);
      if (activeTrip != null && activeTrip.id != sightingId) {
        throw Exception(
            'You are currently on your way to another rescue (${activeTrip.title.isNotEmpty ? activeTrip.title : "Active Rescue"}). Please complete or cancel that rescue trip first.');
      }

      final activeVet = await getActiveVetCareSighting(uid);
      if (activeVet != null && activeVet.id != sightingId) {
        throw Exception(
            'You currently have a cat in vet custody awaiting verification or decision (${activeVet.title.isNotEmpty ? activeVet.title : "Vet Care Cat"}). Please decide the next step for that cat first.');
      }
    }

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
      'returnedToSpot': 100,
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
      'returnedToSpot': 'safely returned the feral cat to its colony territory (TNR). 🌿',
      'helpedOffline': 'reported that the cat was already helped or taken in by a local resident. 🏠',
    };

    final xp = xpMap[action] ?? 10;
    String message = autoMessages[action] ?? 'took action.';
    if ((action == 'tookIn' || action == 'holding') &&
        carePlanDurationDays != null &&
        carePlanDurationDays >= 3) {
      final effectiveGoal = carePlanGoal?.trim().isNotEmpty == true
          ? carePlanGoal!.trim()
          : 'Foster & Welfare Care';
      message =
          'took this cat into Foster Care for $carePlanDurationDays days ($effectiveGoal). Care plan activated! 🏡🐾';
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
    if (customNote != null && customNote.trim().isNotEmpty) {
      docData['customNote'] = customNote.trim();
    }
    if (carePlanGoal != null && carePlanGoal.isNotEmpty) {
      docData['carePlanGoal'] = carePlanGoal;
    }
    if (carePlanDurationDays != null && carePlanDurationDays >= 3) {
      docData['carePlanDurationDays'] = carePlanDurationDays;
    }
    if (careMilestoneDays != null && careMilestoneDays.isNotEmpty) {
      docData['careMilestoneDays'] = careMilestoneDays;
    }
    if (customMilestoneTitles != null && customMilestoneTitles.isNotEmpty) {
      docData['customMilestoneTitles'] = customMilestoneTitles;
    }
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
          'rescuerUserIds': FieldValue.arrayUnion([uid]),
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

        if (temperament != null && temperament.isNotEmpty) {
          updateFields['temperament'] = temperament;
          if (temperament == 'feral') {
            updateFields['category'] = 'Feral / Colony Cat';
          }
        }

        // Custody State Transitions:
        final isReporter = uid == reporterId;
        if (action == 'vet') {
          if (isReporter) {
            updateFields['hasVetVisit'] = true;
            updateFields['hasVetVisitFlag'] = true;
            updateFields['lastVetVisitAt'] = FieldValue.serverTimestamp();
            updateFields['lastVetRescuerId'] = uid;
            updateFields['lastVetRescuerName'] = name;
            if (sightingDoc.data()?['urgency']?.toString() == 'urgent') {
              updateFields['urgency'] = 'needsHelp';
            }
          } else {
            updateFields['pendingVetRescuerId'] = uid;
            updateFields['pendingVetRescuerName'] = name;
            updateFields['pendingVetProofUrl'] = finalProofUrl;
            if (customNote != null && customNote.trim().isNotEmpty) {
              updateFields['pendingVetNote'] = customNote.trim();
            }
          }
        } else if (action == 'tookIn' || action == 'holding') {
          updateFields['careStatus'] = 'inCare_foster';
          updateFields['careTakerId'] = uid;
          updateFields['careTakerName'] = name;
          updateFields['careStartedAt'] = FieldValue.serverTimestamp();
          if (carePlanGoal != null && carePlanGoal.isNotEmpty) {
            updateFields['carePlanGoal'] = carePlanGoal;
          }
          if (carePlanDurationDays != null && carePlanDurationDays >= 3) {
            updateFields['carePlanDurationDays'] = carePlanDurationDays;
          }
          if (careMilestoneDays != null && careMilestoneDays.isNotEmpty) {
            updateFields['careMilestoneDays'] = careMilestoneDays;
          }
          if (customMilestoneTitles != null && customMilestoneTitles.isNotEmpty) {
            updateFields['customMilestoneTitles'] = customMilestoneTitles;
          }
          // Clear physical rescue dispatch claim
          updateFields['rescueClaimed'] = false;
          updateFields['rescueClaimedBy'] = FieldValue.delete();
          updateFields['rescueClaimedByName'] = FieldValue.delete();
          updateFields['rescueClaimedAt'] = FieldValue.delete();
          updateFields['pendingHandoverRescuerId'] = FieldValue.delete();
          updateFields['pendingHandoverRescuerName'] = FieldValue.delete();
          updateFields['pendingHandoverUpdateId'] = FieldValue.delete();
        } else if (action == 'returnedToSpot') {
          updateFields['careStatus'] = 'resolved';
          updateFields['urgency'] = 'resolved';
          updateFields['category'] = 'Resolved';
          updateFields['resolvedByAction'] = 'returnedToSpot';
          updateFields['resolvedAt'] = FieldValue.serverTimestamp();
          updateFields['isSterilized'] = true;
          updateFields['hasVetVisitFlag'] = true;
          updateFields['healthTags'] = FieldValue.arrayUnion(
              ['✂️ Spayed / Neutered', '🩺 Vet Checked', '🌿 Returned to Colony']);
          if (updatedLatitude != null && updatedLongitude != null) {
            updateFields['latitude'] = updatedLatitude;
            updateFields['longitude'] = updatedLongitude;
            updateFields['updatedLatitude'] = updatedLatitude;
            updateFields['updatedLongitude'] = updatedLongitude;
          }
          if (updatedLocationAddress != null && updatedLocationAddress.isNotEmpty) {
            updateFields['locationAddress'] = updatedLocationAddress;
            updateFields['updatedLocationAddress'] = updatedLocationAddress;
          }
          updateFields['careTakerId'] = null;
          updateFields['careTakerName'] = null;
          updateFields['careStartedAt'] = null;
          updateFields['rescueClaimed'] = false;
          updateFields['rescueClaimedBy'] = FieldValue.delete();
          updateFields['rescueClaimedByName'] = FieldValue.delete();
          updateFields['rescueClaimedAt'] = FieldValue.delete();
          updateFields['lastVetRescuerId'] = FieldValue.delete();
          updateFields['lastVetRescuerName'] = FieldValue.delete();
          updateFields['pendingVetRescuerId'] = FieldValue.delete();
          updateFields['pendingVetRescuerName'] = FieldValue.delete();
          updateFields['pendingVetProofUrl'] = FieldValue.delete();
          updateFields['pendingVetClinicName'] = FieldValue.delete();
          updateFields['pendingVetNote'] = FieldValue.delete();
          updateFields['pendingHandoverRescuerId'] = FieldValue.delete();
          updateFields['pendingHandoverRescuerName'] = FieldValue.delete();
          updateFields['pendingHandoverUpdateId'] = FieldValue.delete();
          updateFields['pendingVetUpdateId'] = FieldValue.delete();
          updateFields['pendingOutcomeAction'] = FieldValue.delete();
          updateFields['pendingOutcomeNote'] = FieldValue.delete();
          updateFields['pendingOutcomeProofUrl'] = FieldValue.delete();
          updateFields['pendingOutcomeUpdateId'] = FieldValue.delete();
        } else if (action == 'sheltered' || markResolved) {
          updateFields['careStatus'] = 'resolved';
          updateFields['urgency'] = 'resolved';
          updateFields['category'] = 'Resolved';
          updateFields['resolvedByAction'] = action;
          updateFields['resolvedAt'] = FieldValue.serverTimestamp();
          updateFields['rescueClaimed'] = false;
          updateFields['rescueClaimedBy'] = FieldValue.delete();
          updateFields['rescueClaimedByName'] = FieldValue.delete();
          updateFields['rescueClaimedAt'] = FieldValue.delete();
          updateFields['pendingOutcomeAction'] = FieldValue.delete();
          updateFields['pendingOutcomeNote'] = FieldValue.delete();
          updateFields['pendingOutcomeProofUrl'] = FieldValue.delete();
          updateFields['pendingOutcomeUpdateId'] = FieldValue.delete();
          updateFields['careTakerId'] = FieldValue.delete();
          updateFields['careTakerName'] = FieldValue.delete();
          updateFields['careStartedAt'] = FieldValue.delete();
          if (updatedLatitude != null && updatedLongitude != null) {
            updateFields['latitude'] = updatedLatitude;
            updateFields['longitude'] = updatedLongitude;
            updateFields['updatedLatitude'] = updatedLatitude;
            updateFields['updatedLongitude'] = updatedLongitude;
          }
          if (updatedLocationAddress != null && updatedLocationAddress.isNotEmpty) {
            updateFields['locationAddress'] = updatedLocationAddress;
            updateFields['updatedLocationAddress'] = updatedLocationAddress;
          }
        } else if (action == 'rehomed') {
          updateFields['careStatus'] = 'resolved';
          updateFields['urgency'] = 'resolved';
          updateFields['category'] = 'Rehomed';
          updateFields['isOpenForAdoption'] = false;
          updateFields['resolvedByAction'] = action;
          updateFields['resolvedAt'] = FieldValue.serverTimestamp();
          updateFields['rescueClaimed'] = false;
          updateFields['rescueClaimedBy'] = FieldValue.delete();
          updateFields['rescueClaimedByName'] = FieldValue.delete();
          updateFields['rescueClaimedAt'] = FieldValue.delete();
          updateFields['pendingOutcomeAction'] = FieldValue.delete();
          updateFields['pendingOutcomeNote'] = FieldValue.delete();
          updateFields['pendingOutcomeProofUrl'] = FieldValue.delete();
          updateFields['pendingOutcomeUpdateId'] = FieldValue.delete();
          updateFields['careTakerId'] = FieldValue.delete();
          updateFields['careTakerName'] = FieldValue.delete();
          updateFields['careStartedAt'] = FieldValue.delete();
        }

        await _firestore
            .collection('sightings')
            .doc(sightingId)
            .update(updateFields);
      }
    } catch (e) {
      debugPrint('Parent sighting update notice: $e');
    }

    // 4. Calculate XP and check if direct award (reporter / agreed TNR return) or pending confirmation
    final isOngoingAction = action == 'fed' || action == 'stillHere' || action == 'moved' || action == 'notHere';
    final isReporter = uid == reporterId;
    final isDirectlyConfirmed = isReporter || action == 'returnedToSpot';
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
    docData['isReporterConfirmed'] = isDirectlyConfirmed;
    docData['pendingXp'] = effectiveXp;
    if (isDirectlyConfirmed) {
      docData['confirmedBy'] = isReporter ? uid : (reporterId.isNotEmpty ? reporterId : uid);
      docData['confirmedAt'] = FieldValue.serverTimestamp();
    }

    // 1. Post update to community feed
    final updateDocRef = await _firestore
        .collection('sightings')
        .doc(sightingId)
        .collection('updates')
        .add(docData);

    if (action == 'vet' && !isReporter) {
      await _firestore.collection('sightings').doc(sightingId).update({
        'pendingVetUpdateId': updateDocRef.id,
      });
    }

    // If reporter logged their own action OR action is directly confirmed (e.g. TNR colony return): award immediately
    if (user != null && !anonymous && isDirectlyConfirmed) {
      try {
        final userDocRef = _firestore.collection('users').doc(uid);
        final updates = <String, dynamic>{
          'lastActive': FieldValue.serverTimestamp(),
        };
        if (effectiveXp > 0) {
          updates['xp'] = FieldValue.increment(effectiveXp);
          updates['totalXp'] = FieldValue.increment(effectiveXp);
        }
        if (action == 'tookIn' || action == 'holding') {
          updates['activeFosters'] = FieldValue.increment(1);
          updates['successfulRescues'] = FieldValue.increment(1);
        }
        if (isOngoingAction) {
          existingCooldowns[sightingId] = FieldValue.serverTimestamp();
          updates['spotCooldowns'] = existingCooldowns;
        }
        await userDocRef.set(updates, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Direct XP award notice: $e');
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
      final authorName = data['authorName']?.toString() ?? 'Rescuer';
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

      // 2. Award pending XP, update trust stats, and apply spot cooldown
      if (authorId.isNotEmpty && authorId != 'anon') {
        final authorDoc =
            await _firestore.collection('users').doc(authorId).get();
        final authorData = authorDoc.data() ?? {};
        final authorCooldowns = Map<String, dynamic>.from(
            (authorData['spotCooldowns'] as Map<String, dynamic>?) ?? {});
        final updates = <String, dynamic>{
          'lastActive': FieldValue.serverTimestamp(),
          'successfulRescues': FieldValue.increment(1),
        };
        if (pendingXp > 0) {
          updates['xp'] = FieldValue.increment(pendingXp);
          updates['totalXp'] = FieldValue.increment(pendingXp);
        }
        if (action == 'tookIn' || action == 'holding') {
          updates['activeFosters'] = FieldValue.increment(1);
        } else if (action == 'rehomed' || action == 'sheltered') {
          updates['completedFosters'] = FieldValue.increment(1);
        }

        // Trust tier progression calculation
        final int currentSucc =
            ((authorData['successfulRescues'] is num)
                ? (authorData['successfulRescues'] as num).toInt()
                : 0) + 1;
        final double curScore = (authorData['trustScore'] is num)
            ? (authorData['trustScore'] as num).toDouble()
            : 5.0;
        final int compFosters = (authorData['completedFosters'] is num)
            ? (authorData['completedFosters'] as num).toInt()
            : 0;

        if (currentSucc >= 10 && compFosters >= 3 && curScore >= 4.7) {
          updates['trustTier'] = 'trustedFoster';
        } else if (currentSucc >= 3 && curScore >= 4.2) {
          updates['trustTier'] = 'verifiedRescuer';
        }

        if (isOngoingAction) {
          authorCooldowns[sightingId] = FieldValue.serverTimestamp();
          updates['spotCooldowns'] = authorCooldowns;
        }
        await _firestore
            .collection('users')
            .doc(authorId)
            .set(updates, SetOptions(merge: true));
      }

      if (action == 'vet') {
        final updateData = <String, dynamic>{
          'hasVetVisit': true,
          'hasVetVisitFlag': true,
          'lastVetVisitAt': FieldValue.serverTimestamp(),
          'lastVetRescuerId': authorId,
          'lastVetRescuerName': authorName,
          'pendingVetRescuerId': FieldValue.delete(),
          'pendingVetRescuerName': FieldValue.delete(),
          'pendingVetProofUrl': FieldValue.delete(),
          'pendingVetClinicName': FieldValue.delete(),
          'pendingVetNote': FieldValue.delete(),
          'pendingVetUpdateId': FieldValue.delete(),
        };
        try {
          final sightingDoc = await _firestore.collection('sightings').doc(sightingId).get();
          if (sightingDoc.data()?['urgency']?.toString() == 'urgent') {
            updateData['urgency'] = 'needsHelp';
          }
          await _firestore.collection('sightings').doc(sightingId).update(updateData);
        } catch (_) {}
      }

      return pendingXp;
    } catch (e) {
      debugPrint('Confirm rescue action notice: $e');
      return 0;
    }
  }

  /// Request Foster Custody Handover (when rescuer is not yet auto-certified Trusted Foster)
  Future<void> requestCustodyHandover({
    required String sightingId,
    required String customNote,
    File? proofPhotoFile,
    String? carePlanGoal,
    int carePlanDurationDays = 7,
    List<int>? careMilestoneDays,
    List<String>? customMilestoneTitles,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final uid = user.uid;
    final name = user.displayName?.isNotEmpty == true
        ? user.displayName!
        : (user.email?.split('@').first ?? 'PawWatcher');

    String? proofUrl;
    if (proofPhotoFile != null) {
      final urls = await uploadPhotos([proofPhotoFile], sightingId);
      if (urls.isNotEmpty) proofUrl = urls.first;
    }

    final userDoc = await _firestore.collection('users').doc(uid).get();
    final uData = userDoc.data() ?? {};
    final double trustScore = (uData['trustScore'] is num)
        ? (uData['trustScore'] as num).toDouble()
        : 5.0;
    final int succRescues = (uData['successfulRescues'] is num)
        ? (uData['successfulRescues'] as num).toInt()
        : 0;
    final String tier = uData['trustTier']?.toString() ?? 'community';

    final effectiveGoal = carePlanGoal?.trim().isNotEmpty == true
        ? carePlanGoal!.trim()
        : 'Foster & Welfare Care';

    // 1. Post Handover Request update
    final updateRef = await _firestore
        .collection('sightings')
        .doc(sightingId)
        .collection('updates')
        .add({
      'type': 'custodyRequest',
      'action': 'tookIn',
      'authorId': uid,
      'authorName': name,
      'trustScore': trustScore,
      'successfulRescues': succRescues,
      'trustTier': tier,
      'proofPhotoUrl': proofUrl,
      'carePlanGoal': effectiveGoal,
      'carePlanDurationDays': carePlanDurationDays,
      'careMilestoneDays': careMilestoneDays ?? [],
      'customMilestoneTitles': customMilestoneTitles ?? [],
      'text':
          'offered to take this cat into Foster Care for $carePlanDurationDays days ($effectiveGoal). Awaiting reporter confirmation. 🐾',
      'customNote': customNote.trim(),
      'status': 'pending', // 'pending', 'approved', 'declined'
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 2. Set pending handover on sighting doc
    await _firestore.collection('sightings').doc(sightingId).update({
      'pendingHandoverRescuerId': uid,
      'pendingHandoverRescuerName': name,
      'pendingHandoverUpdateId': updateRef.id,
      'carePlanGoal': effectiveGoal,
      'carePlanDurationDays': carePlanDurationDays,
      'careMilestoneDays': careMilestoneDays ?? [],
      'customMilestoneTitles': customMilestoneTitles ?? [],
    });
  }

  /// Reporter approves Foster Custody Handover
  Future<void> approveCustodyHandover({
    required String sightingId,
    String? updateId,
    required String rescuerUid,
    required String rescuerName,
    String? carePlanGoal,
    int? carePlanDurationDays,
    List<int>? careMilestoneDays,
    List<String>? customMilestoneTitles,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // 1. Mark request update approved if updateId exists
    if (updateId != null && updateId.isNotEmpty) {
      try {
        await _firestore
            .collection('sightings')
            .doc(sightingId)
            .collection('updates')
            .doc(updateId)
            .update({
          'status': 'approved',
          'approvedBy': user.uid,
          'approvedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {
        // Document might not exist or ID format differs
      }
    }

    final updateData = <String, dynamic>{
      'careStatus': 'inCare_foster',
      'careTakerId': rescuerUid,
      'careTakerName': rescuerName,
      'careStartedAt': FieldValue.serverTimestamp(),
      'pendingHandoverRescuerId': FieldValue.delete(),
      'pendingHandoverRescuerName': FieldValue.delete(),
      'pendingHandoverUpdateId': FieldValue.delete(),
      'rescueClaimed': false,
      'rescueClaimedBy': FieldValue.delete(),
      'rescueClaimedByName': FieldValue.delete(),
      'rescueClaimedAt': FieldValue.delete(),
      'rescuerUserIds': FieldValue.arrayUnion([rescuerUid]),
    };

    if (carePlanGoal != null && carePlanGoal.isNotEmpty) {
      updateData['carePlanGoal'] = carePlanGoal;
    }
    if (carePlanDurationDays != null && carePlanDurationDays >= 3) {
      updateData['carePlanDurationDays'] = carePlanDurationDays;
    }
    if (careMilestoneDays != null && careMilestoneDays.isNotEmpty) {
      updateData['careMilestoneDays'] = careMilestoneDays;
    }
    if (customMilestoneTitles != null && customMilestoneTitles.isNotEmpty) {
      updateData['customMilestoneTitles'] = customMilestoneTitles;
    }

    // 2. Transition Sighting to inCare_foster with rescuer custody
    await _firestore
        .collection('sightings')
        .doc(sightingId)
        .update(updateData);

    // 3. Post approved notice to feed
    await _firestore
        .collection('sightings')
        .doc(sightingId)
        .collection('updates')
        .add({
      'type': 'handoverApproved',
      'authorId': user.uid,
      'authorName': user.displayName ?? 'Reporter',
      'text':
          'approved foster custody handover to $rescuerName! 🐾 Care plan activated.',
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 4. Award XP (+150 XP) and increment active fosters on rescuer
    await _firestore.collection('users').doc(rescuerUid).set({
      'xp': FieldValue.increment(150),
      'totalXp': FieldValue.increment(150),
      'successfulRescues': FieldValue.increment(1),
      'activeFosters': FieldValue.increment(1),
      'lastActive': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Reporter declines Foster Custody Handover
  Future<void> declineCustodyHandover({
    required String sightingId,
    String? updateId,
    String? rescuerId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    if (updateId != null && updateId.isNotEmpty) {
      try {
        await _firestore
            .collection('sightings')
            .doc(sightingId)
            .collection('updates')
            .doc(updateId)
            .update({
          'status': 'declined',
          'declinedBy': user.uid,
          'declinedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    }

    final Map<String, dynamic> updateData = {
      'pendingHandoverRescuerId': FieldValue.delete(),
      'pendingHandoverRescuerName': FieldValue.delete(),
      'pendingHandoverUpdateId': FieldValue.delete(),
    };

    if (rescuerId != null && rescuerId.isNotEmpty) {
      updateData['declinedFosterUserIds'] = FieldValue.arrayUnion([rescuerId]);
    }

    await _firestore.collection('sightings').doc(sightingId).update(updateData);
  }

  /// Submit Day 1, Day 3, or Day 7 Care Milestone Check-In
  Future<int> submitCareMilestoneCheckIn({
    required String sightingId,
    required int milestoneDay,
    required String conditionStatus,
    required String careNote,
    File? proofPhotoFile,
    File? proofVideoFile,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return 0;
    final uid = user.uid;
    final name = user.displayName?.isNotEmpty == true
        ? user.displayName!
        : (user.email?.split('@').first ?? 'PawWatcher');

    String? proofUrl;
    if (proofPhotoFile != null) {
      final urls = await uploadPhotos([proofPhotoFile], sightingId);
      if (urls.isNotEmpty) proofUrl = urls.first;
    }

    String? proofVideoUrl;
    if (proofVideoFile != null) {
      proofVideoUrl = await uploadVideo(proofVideoFile, sightingId);
    }

    final int xp = milestoneDay == 1 ? 30 : (milestoneDay == 3 ? 40 : 60);

    // 1. Post to updates feed
    await _firestore
        .collection('sightings')
        .doc(sightingId)
        .collection('updates')
        .add({
      'type': 'milestoneCheckIn',
      'authorId': uid,
      'authorName': name,
      'milestoneDay': milestoneDay,
      'conditionStatus': conditionStatus,
      'proofPhotoUrl': proofUrl,
      if (proofVideoUrl != null && proofVideoUrl.isNotEmpty)
        'proofVideoUrl': proofVideoUrl,
      'text':
          'completed Day $milestoneDay Care Check-In: "$conditionStatus" 🐾',
      'customNote': careNote.trim(),
      'xpAwarded': xp,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 2. Update sighting doc
    await _firestore.collection('sightings').doc(sightingId).update({
      'latestCondition': conditionStatus,
      'lastCheckInAt': FieldValue.serverTimestamp(),
      'completedMilestones': FieldValue.arrayUnion([milestoneDay]),
    });

    // 3. Award XP to caretaker
    await _firestore.collection('users').doc(uid).set({
      'xp': FieldValue.increment(xp),
      'totalXp': FieldValue.increment(xp),
      'lastActive': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return xp;
  }

  /// Returns the sighting if the given user currently has an active "On My Way" rescue trip
  Future<Sighting?> getActiveRescueTrip(String uid) async {
    try {
      final snap = await _firestore
          .collection('sightings')
          .where('rescueClaimed', isEqualTo: true)
          .where('rescueClaimedBy', isEqualTo: uid)
          .get();
      for (final doc in snap.docs) {
        final s = Sighting.fromFirestore(doc);
        if (s.urgency != 'resolved' && s.isRescueClaimActive) {
          return s;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Returns the sighting if the given user currently has a pending vet verification or awaiting post-vet decision
  Future<Sighting?> getActiveVetCareSighting(String uid) async {
    try {
      final snap = await _firestore
          .collection('sightings')
          .where('pendingVetRescuerId', isEqualTo: uid)
          .get();
      for (final doc in snap.docs) {
        final s = Sighting.fromFirestore(doc);
        if (s.urgency != 'resolved' && s.isVetVisitPending) {
          return s;
        }
      }
      final snap2 = await _firestore
          .collection('sightings')
          .where('lastVetRescuerId', isEqualTo: uid)
          .get();
      for (final doc in snap2.docs) {
        final s = Sighting.fromFirestore(doc);
        if (s.urgency != 'resolved' && s.isAwaitingPostVetDecision) {
          return s;
        }
      }
      final snap3 = await _firestore
          .collection('sightings')
          .where('rescueClaimedBy', isEqualTo: uid)
          .get();
      for (final doc in snap3.docs) {
        final s = Sighting.fromFirestore(doc);
        if (s.urgency != 'resolved' && s.isAwaitingPostVetDecision) {
          return s;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Claim "I'm on my way" rescue button
  Future<void> claimRescue(String sightingId) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final name = user.displayName?.isNotEmpty == true
        ? user.displayName!
        : (user.email?.split('@').first ?? 'PawWatcher');

    // Rescuer focus rule: cannot claim On My Way on a new cat while already On My Way or managing pending vet care
    final activeTrip = await getActiveRescueTrip(user.uid);
    if (activeTrip != null && activeTrip.id != sightingId) {
      throw Exception(
          'You already have an active rescue mission for "${activeTrip.title.isNotEmpty ? activeTrip.title : "a cat"}". Please complete or cancel your current trip first.');
    }

    final activeVet = await getActiveVetCareSighting(user.uid);
    if (activeVet != null && activeVet.id != sightingId) {
      throw Exception(
          'You currently have a cat in vet custody awaiting verification or decision (${activeVet.title.isNotEmpty ? activeVet.title : "Vet Care Cat"}). Please complete that first.');
    }

    final sightingRef = _firestore.collection('sightings').doc(sightingId);
    await sightingRef.update({
      'rescueClaimed': true,
      'rescueClaimedBy': user.uid,
      'rescueClaimedByName': name,
      'rescueClaimedAt': FieldValue.serverTimestamp(),
      'rescuerUserIds': FieldValue.arrayUnion([user.uid]),
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

  /// Rescuer clicks "Can't Help" on an urgent dispatch notification
  Future<void> dismissDispatchForUser(String sightingId) async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await _firestore.collection('sightings').doc(sightingId).update({
        'declinedDispatchUserIds': FieldValue.arrayUnion([user.uid]),
      });
    } catch (_) {}
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
        'text': 'Rescue claim by $claimerName timed out after 45m without action proof. Spot is open again for rescuers! 🐾',
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

  /// Delete a sighting (owner only, disallowed if active community care, vet visit, or foster custody exists unless force is true)
  Future<void> deleteSighting(String sightingId, {bool force = false}) async {
    final docSnap =
        await _firestore.collection('sightings').doc(sightingId).get();
    if (!docSnap.exists) return;
    final data = docSnap.data() ?? {};

    final hasVet =
        data['hasVetVisit'] == true || data['hasVetVisitFlag'] == true;
    final isPendingVet = data['pendingVetRescuerId'] != null &&
        data['pendingVetRescuerId'].toString().isNotEmpty;
    final isInCare = data['careTakerId'] != null &&
        data['careTakerId'].toString().isNotEmpty;
    final isClaimed = data['rescueClaimed'] == true;
    final isResolved = data['urgency'] == 'resolved';

    if (!force && (hasVet || isPendingVet || isInCare || isClaimed || isResolved)) {
      throw Exception(
        'Cannot delete report: active rescue progress, medical records, or community care already exist for this cat.',
      );
    }

    await _firestore.collection('sightings').doc(sightingId).delete();
  }

  /// Revokes foster/rescue custody from a rescuer (e.g. if reported by reporter/admin for uploading another cat or fake update)
  Future<void> revokeRescueCustody({
    required String sightingId,
    required String rescuerUid,
    String? reason,
  }) async {
    final user = _auth.currentUser;
    final actorName = user?.displayName?.isNotEmpty == true
        ? user!.displayName!
        : 'Report Author';

    // 1. Reset custody fields on sighting
    await _firestore.collection('sightings').doc(sightingId).update({
      'careTakerId': FieldValue.delete(),
      'careTakerName': FieldValue.delete(),
      'isInCare': false,
      'isFosterCareActive': false,
      'rescueClaimed': false,
      'rescueClaimedBy': FieldValue.delete(),
      'rescueClaimedByName': FieldValue.delete(),
      'rescueClaimedAt': FieldValue.delete(),
      'pendingVetRescuerId': FieldValue.delete(),
      'pendingVetRescuerName': FieldValue.delete(),
      'urgency': 'urgent',
    });

    // 2. Post notice in updates feed
    await _firestore
        .collection('sightings')
        .doc(sightingId)
        .collection('updates')
        .add({
      'type': 'custodyRevoked',
      'authorId': user?.uid ?? 'system',
      'authorName': actorName,
      'revokedUid': rescuerUid,
      'reason': reason ?? 'Rescue claim was revoked due to verification/content report.',
      'text':
          'rescuer custody was revoked ($actorName). This rescue spot is reopened for the community! 🐾',
      'createdAt': FieldValue.serverTimestamp(),
    });
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

  /// Update cat temperament / socialization type (e.g. after clinic vet assessment)
  Future<void> updateCatTemperament({
    required String sightingId,
    required String temperament,
    String? reason,
  }) async {
    final user = _auth.currentUser;
    final data = <String, dynamic>{
      'temperament': temperament,
    };
    if (temperament == 'feral') {
      data['category'] = 'Feral / Colony Cat';
    } else if (temperament == 'kitten') {
      data['category'] = 'Kitten';
    }
    await _firestore.collection('sightings').doc(sightingId).update(data);

    final authorName = user?.displayName?.isNotEmpty == true
        ? user!.displayName!
        : (user?.email?.split('@').first ?? 'Rescuer');
    final temperamentLabel = temperament == 'feral'
        ? '🌿 Feral / Colony Adult'
        : (temperament == 'friendly'
            ? '💖 Friendly Pet'
            : (temperament == 'kitten'
                ? '🍼 Kitten'
                : '🐾 Shy / Timid Stray'));
    final noteText = reason?.trim().isNotEmpty == true
        ? 'updated cat classification to $temperamentLabel based on vet assessment: "${reason!.trim()}"'
        : 'updated cat classification to $temperamentLabel based on vet assessment.';

    await _firestore
        .collection('sightings')
        .doc(sightingId)
        .collection('updates')
        .add({
      'type': 'status_update',
      'action': 'temperament_updated',
      'authorId': user?.uid ?? 'anon',
      'authorName': authorName,
      'text': noteText,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Flag a sighting as inappropriate
  Future<void> flagSighting(
    String sightingId,
    String reason, {
    String? sightingTitle,
    String? photoUrl,
    String? locationName,
  }) async {
    final user = _auth.currentUser;
    await _firestore.collection('flags').add({
      'type': 'sighting',
      'sightingId': sightingId,
      'sightingTitle': sightingTitle,
      'photoUrl': photoUrl,
      'locationName': locationName,
      'reportedBy': user?.uid ?? 'anon',
      'reason': reason,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Report an unwanted or inappropriate chat message or photo
  Future<void> reportChatMessage({
    required String chatId,
    required String messageId,
    required String reason,
    String? photoUrl,
    String? messageText,
    String? senderName,
  }) async {
    final uid = _auth.currentUser?.uid ?? 'anon';
    final data = <String, dynamic>{
      'type': 'chat_message',
      'chatId': chatId,
      'messageId': messageId,
      'photoUrl': photoUrl,
      'reportedBy': uid,
      'reason': reason,
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (messageText != null) data['messageText'] = messageText;
    if (senderName != null) data['senderName'] = senderName;

    await _firestore.collection('flags').add(data);

    await _firestore
        .collection('coordinationChats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .set({
      'isReported': true,
      'reportedBy': uid,
      'reportReason': reason,
    }, SetOptions(merge: true));
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

  /// Edit custom note of a community update post or comment (author only)
  Future<void> editCommunityUpdateNote({
    required String sightingId,
    required String updateId,
    required String newCustomNote,
  }) async {
    final updateRef = _firestore
        .collection('sightings')
        .doc(sightingId)
        .collection('updates')
        .doc(updateId);

    final snap = await updateRef.get();
    final data = snap.data() ?? {};
    final type = data['type'] ?? 'comment';

    final updateFields = <String, dynamic>{
      'customNote': newCustomNote.trim(),
      'isEdited': true,
      'editedAt': FieldValue.serverTimestamp(),
    };

    // If it's a plain comment, also update text
    if (type == 'comment') {
      updateFields['text'] = newCustomNote.trim();
    }

    await updateRef.update(updateFields);
  }

  /// Soft-delete a comment or reply (author only)
  Future<void> deleteComment({
    required String sightingId,
    required String commentId,
  }) async {
    final commentRef = _firestore
        .collection('sightings')
        .doc(sightingId)
        .collection('updates')
        .doc(commentId);

    final snap = await commentRef.get();
    if (snap.exists && snap.data()?['type'] != null && snap.data()?['type'] != 'comment') {
      throw Exception('Community update posts cannot be deleted.');
    }

    final batch = _firestore.batch();
    batch.update(commentRef, {
      'text': '[Comment deleted]',
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
    });

    // Safely decrement comment count on sighting doc (never negative)
    final sightingRef = _firestore.collection('sightings').doc(sightingId);
    final sightingSnap = await sightingRef.get();
    final currentCount = (sightingSnap.data()?['commentCount'] as num?)?.toInt() ?? 0;
    if (currentCount > 0) {
      batch.update(sightingRef, {'commentCount': FieldValue.increment(-1)});
    } else {
      batch.update(sightingRef, {'commentCount': 0});
    }

    await batch.commit();
  }

  /// Report/flag a comment or reply
  Future<void> flagComment({
    required String sightingId,
    required String commentId,
    required String reason,
    String? commentText,
    String? authorName,
    String? sightingTitle,
  }) async {
    final user = _auth.currentUser;
    await _firestore.collection('flags').add({
      'type': 'comment',
      'sightingId': sightingId,
      'commentId': commentId,
      'commentText': commentText,
      'authorName': authorName,
      'sightingTitle': sightingTitle,
      'reportedBy': user?.uid ?? 'anon',
      'reason': reason,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Report/flag a user review or endorsement for admin review
  Future<void> flagReview({
    required String targetUserId,
    required String reviewerName,
    required String comment,
    required double rating,
    required String reason,
    String? details,
  }) async {
    final user = _auth.currentUser;
    await _firestore.collection('flags').add({
      'type': 'review',
      'targetUserId': targetUserId,
      'reviewerName': reviewerName,
      'comment': comment,
      'rating': rating,
      'reportedBy': user?.uid ?? 'anon',
      'reporterEmail': user?.email ?? '',
      'reason': reason,
      'details': details ?? '',
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Block a user from viewing a specific sighting report details
  Future<void> blockUserFromSighting({
    required String sightingId,
    required String blockedUid,
  }) async {
    await _firestore.collection('sightings').doc(sightingId).update({
      'blockedUserIds': FieldValue.arrayUnion([blockedUid]),
    });
  }

  /// Delete all comments from both the reporter and blocked user on this sighting
  Future<void> deleteCommentsBetweenUsers({
    required String sightingId,
    required String userA,
    required String userB,
  }) async {
    final querySnap = await _firestore
        .collection('sightings')
        .doc(sightingId)
        .collection('comments')
        .get();

    final batch = _firestore.batch();
    for (final doc in querySnap.docs) {
      final authorId = doc.data()['authorId']?.toString() ?? '';
      if (authorId.isNotEmpty && (authorId == userA || authorId == userB)) {
        batch.update(doc.reference, {
          'isDeleted': true,
          'text': '(comment deleted)',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
    await batch.commit();
  }

  /// Stream UserProfile with real-time trust score, trust tier, and XP progress
  Stream<UserProfile> streamUserProfile(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      if (!doc.exists) {
        final curUser = _auth.currentUser;
        return UserProfile(
          uid: uid,
          displayName: curUser?.displayName ?? 'PawWatcher',
          email: curUser?.email ?? '',
          joinedAt: DateTime.now(),
        );
      }
      return UserProfile.fromFirestore(doc);
    });
  }

  /// Get a single UserProfile once
  Future<UserProfile?> getUserProfile(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (doc.exists && doc.data() != null) {
      return UserProfile.fromFirestore(doc);
    }
    return null;
  }

  /// Submit a reporter review & rating for a rescuer after handover or rescue
  Future<void> submitRescuerReview({
    required String rescuerUid,
    required double rating, // 1.0 - 5.0
    required String comment,
    required String sightingId,
  }) async {
    final user = _auth.currentUser;
    final reviewerName = user?.displayName?.isNotEmpty == true
        ? user!.displayName!
        : (user?.email?.split('@').first ?? 'Reporter');
    final userRef = _firestore.collection('users').doc(rescuerUid);

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(userRef);
      if (!snap.exists) return;
      final data = snap.data() ?? {};
      final rawReviews = data['reviews'] as List? ?? [];
      final reviews =
          List<Map<String, dynamic>>.from(rawReviews.whereType<Map>());

      reviews.add({
        'reviewerId': user?.uid ?? 'anon',
        'reviewerName': reviewerName,
        'rating': rating,
        'comment': comment.trim(),
        'sightingId': sightingId,
        'createdAt': Timestamp.now(),
      });

      // Recalculate average trust score
      double sum = 0.0;
      for (final r in reviews) {
        sum += (r['rating'] as num?)?.toDouble() ?? 5.0;
      }
      final double newAvg = reviews.isNotEmpty ? (sum / reviews.length) : 5.0;
      final int succRescues = (data['successfulRescues'] is num)
          ? (data['successfulRescues'] as num).toInt()
          : 0;
      final int compFosters = (data['completedFosters'] is num)
          ? (data['completedFosters'] as num).toInt()
          : 0;

      // Check trust tier upgrade:
      String newTier = 'community';
      if (succRescues >= 10 && compFosters >= 3 && newAvg >= 4.7) {
        newTier = 'trustedFoster';
      } else if (succRescues >= 3 && newAvg >= 4.2) {
        newTier = 'verifiedRescuer';
      }

      tx.update(userRef, {
        'reviews': reviews,
        'trustScore': double.parse(newAvg.toStringAsFixed(1)),
        'trustTier': newTier,
      });
    });
  }

  /// Update user profile details
  Future<void> updateUserProfile({
    required String uid,
    String? displayName,
    String? bio,
    String? city,
    String? photoUrl,
  }) async {
    final data = <String, dynamic>{};
    if (displayName != null) data['displayName'] = displayName.trim();
    if (bio != null) data['bio'] = bio.trim();
    if (city != null) data['city'] = city.trim();
    if (photoUrl != null) data['photoUrl'] = photoUrl;

    if (data.isNotEmpty) {
      await _firestore.collection('users').doc(uid).set(data, SetOptions(merge: true));
      if (displayName != null && _auth.currentUser != null) {
        await _auth.currentUser!.updateDisplayName(displayName.trim());
      }
      if (photoUrl != null && _auth.currentUser != null) {
        await _auth.currentUser!.updatePhotoURL(photoUrl);
      }
    }
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

  // =========================================================================
  // DIRECT COORDINATION CHAT & CONVERSATIONS INBOX
  // =========================================================================

  /// Generate a consistent chatId for a sighting and two participants
  String getCoordinationChatId(String sightingId, String user1, String user2) {
    final list = [user1, user2]..sort();
    return '${sightingId}_${list[0]}_${list[1]}';
  }

  /// Stream messages in a coordination chat thread
  Stream<List<ChatMessage>> streamChatMessages(String chatId) {
    return _firestore
        .collection('coordinationChats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => ChatMessage.fromFirestore(d)).toList());
  }

  /// Stream all conversations for a user, sorted newest first
  Stream<List<Map<String, dynamic>>> streamUserChatThreads(String userId) {
    return _firestore
        .collection('coordinationChats')
        .where('participants', arrayContains: userId)
        .snapshots()
        .map((snap) {
          final list = snap.docs.map((d) {
            final data = d.data();
            data['chatId'] = d.id;
            return data;
          }).toList();
          list.sort((a, b) {
            final tsA = a['lastUpdatedAt'] as Timestamp?;
            final tsB = b['lastUpdatedAt'] as Timestamp?;
            if (tsA == null && tsB == null) return 0;
            if (tsA == null) return 1;
            if (tsB == null) return -1;
            return tsB.compareTo(tsA);
          });
          return list;
        });
  }

  /// Stream the coordination chat document itself (for participants and block status)
  Stream<DocumentSnapshot<Map<String, dynamic>>> streamChatDoc(String chatId) {
    return _firestore.collection('coordinationChats').doc(chatId).snapshots();
  }

  /// Delete a coordination chat thread and its messages
  Future<void> deleteChatThread(String chatId) async {
    final chatDocRef = _firestore.collection('coordinationChats').doc(chatId);
    final messagesSnap = await chatDocRef.collection('messages').get();
    final batch = _firestore.batch();
    for (final doc in messagesSnap.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(chatDocRef);
    await batch.commit();
  }

  /// Delete multiple coordination chat threads and their messages
  Future<void> deleteMultipleChatThreads(List<String> chatIds) async {
    for (final chatId in chatIds) {
      await deleteChatThread(chatId);
    }
  }

  /// Edit a coordination chat message text
  Future<void> editChatMessage({
    required String chatId,
    required String messageId,
    required String newText,
  }) async {
    final chatDocRef = _firestore.collection('coordinationChats').doc(chatId);
    final msgDocRef = chatDocRef.collection('messages').doc(messageId);

    await msgDocRef.update({
      'text': newText.trim(),
      'isEdited': true,
      'editedAt': FieldValue.serverTimestamp(),
    });

    try {
      final latestMsgQuery = await chatDocRef
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      if (latestMsgQuery.docs.isNotEmpty &&
          latestMsgQuery.docs.first.id == messageId) {
        await chatDocRef.update({
          'lastMessage': newText.trim(),
          'lastUpdatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('Sync lastMessage after edit notice: $e');
    }
  }

  /// Mark a single coordination chat message as deleted
  Future<void> deleteChatMessage({
    required String chatId,
    required String messageId,
  }) async {
    final chatDocRef = _firestore.collection('coordinationChats').doc(chatId);
    await chatDocRef.collection('messages').doc(messageId).update({
      'isDeleted': true,
      'text': 'This message was deleted',
      'photoUrl': FieldValue.delete(),
      'deletedAt': FieldValue.serverTimestamp(),
    });

    try {
      final latestMsgQuery = await chatDocRef
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      if (latestMsgQuery.docs.isNotEmpty &&
          latestMsgQuery.docs.first.id == messageId) {
        await chatDocRef.update({
          'lastMessage': '🚫 This message was deleted',
          'lastUpdatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('Sync lastMessage after delete notice: $e');
    }
  }

  /// Block a user in the chat thread
  Future<void> blockUserInChat({
    required String chatId,
    required String targetUserId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final myUid = user.uid;

    final chatDocRef = _firestore.collection('coordinationChats').doc(chatId);
    await chatDocRef.set({
      'blockedBy': FieldValue.arrayUnion([myUid]),
      'lastUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await chatDocRef.collection('messages').add({
      'senderId': 'system',
      'senderName': 'System',
      'text': '${user.displayName ?? 'User'} blocked this conversation.',
      'createdAt': FieldValue.serverTimestamp(),
      'isSystemMessage': true,
    });
  }

  /// Unblock a user in the chat thread
  Future<void> unblockUserInChat({
    required String chatId,
    required String targetUserId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final myUid = user.uid;

    final chatDocRef = _firestore.collection('coordinationChats').doc(chatId);
    await chatDocRef.set({
      'blockedBy': FieldValue.arrayRemove([myUid]),
      'lastUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await chatDocRef.collection('messages').add({
      'senderId': 'system',
      'senderName': 'System',
      'text': '${user.displayName ?? 'User'} unblocked this conversation.',
      'createdAt': FieldValue.serverTimestamp(),
      'isSystemMessage': true,
    });
  }

  /// Send a message in a coordination chat
  Future<void> sendChatMessage({
    required String chatId,
    required String sightingId,
    required String text,
    String? photoUrl,
    String? otherUserId,
    String? otherUserName,
    String? sightingTitle,
    String? sightingPhoto,
    bool isSystemMessage = false,
    String? replyToId,
    String? replyToSenderName,
    String? replyToText,
  }) async {
    final user = _auth.currentUser;
    if (user == null && !isSystemMessage) return;

    final senderId = user?.uid ?? 'system';
    final senderName = user?.displayName ?? 'Rescuer';

    final chatDocRef =
        _firestore.collection('coordinationChats').doc(chatId);

    // Check if chat is currently blocked
    if (!isSystemMessage) {
      final docSnap = await chatDocRef.get();
      if (docSnap.exists) {
        final data = docSnap.data();
        final blockedBy = (data?['blockedBy'] as List<dynamic>?)?.cast<String>() ?? [];
        if (blockedBy.isNotEmpty) {
          // Chat is blocked, do not allow sending
          return;
        }
      }
    }

    // Ensure participants list
    final List<String> parts = [senderId];
    if (otherUserId != null && otherUserId.isNotEmpty && otherUserId != senderId) {
      parts.add(otherUserId);
    } else {
      final segments = chatId.split('_');
      if (segments.length >= 3) {
        if (!parts.contains(segments[1])) parts.add(segments[1]);
        if (!parts.contains(segments[2])) parts.add(segments[2]);
      }
    }

    final otherParticipants = parts.where((p) => p != senderId).toList();

    final metadata = <String, dynamic>{
      'chatId': chatId,
      'sightingId': sightingId,
      'participants': parts,
      'lastMessage': text.trim(),
      'lastSenderId': senderId,
      'lastSenderName': senderName,
      'lastUpdatedAt': FieldValue.serverTimestamp(),
      'lastRead_$senderId': FieldValue.serverTimestamp(),
    };

    if (otherParticipants.isNotEmpty) {
      metadata['unreadBy'] = FieldValue.arrayUnion(otherParticipants);
    }

    if (sightingTitle != null) metadata['sightingTitle'] = sightingTitle;
    if (sightingPhoto != null) metadata['sightingPhoto'] = sightingPhoto;
    if (otherUserName != null) metadata['otherUserName'] = otherUserName;

    await chatDocRef.set(metadata, SetOptions(merge: true));

    // Add message
    final msgData = <String, dynamic>{
      'senderId': senderId,
      'senderName': senderName,
      'text': text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'photoUrl': photoUrl,
      'isSystemMessage': isSystemMessage,
    };
    if (replyToId != null) msgData['replyToId'] = replyToId;
    if (replyToSenderName != null) msgData['replyToSenderName'] = replyToSenderName;
    if (replyToText != null) msgData['replyToText'] = replyToText;

    await chatDocRef.collection('messages').add(msgData);
  }

  /// Mark a chat thread as read for a given user
  Future<void> markChatAsRead({
    required String chatId,
    required String userId,
  }) async {
    if (chatId.isEmpty || userId.isEmpty) return;
    try {
      final chatDocRef = _firestore.collection('coordinationChats').doc(chatId);
      await chatDocRef.set({
        'unreadBy': FieldValue.arrayRemove([userId]),
        'lastRead_$userId': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error marking chat as read: $e');
    }
  }

  /// Check if a chat thread has unread messages for a given user
  static bool isChatUnread(Map<String, dynamic> chat, String? currentUid) {
    if (currentUid == null || currentUid.isEmpty) return false;
    final lastSenderId = chat['lastSenderId']?.toString();
    // If current user is the last sender, they wrote it -> read
    if (lastSenderId == currentUid) return false;

    // Check explicit unreadBy array
    if (chat.containsKey('unreadBy') && chat['unreadBy'] is List) {
      final unreadList = (chat['unreadBy'] as List).map((e) => e.toString()).toList();
      return unreadList.contains(currentUid);
    }

    // Fallback for legacy chats: compare lastRead_$currentUid timestamp with lastUpdatedAt
    final lastRead = chat['lastRead_$currentUid'];
    final lastUpdatedAt = chat['lastUpdatedAt'];
    if (lastRead != null && lastUpdatedAt != null) {
      if (lastRead is Timestamp && lastUpdatedAt is Timestamp) {
        return lastUpdatedAt.compareTo(lastRead) > 0;
      }
    }

    // If last message exists and was sent by another user, and no read record exists
    return lastSenderId != null && lastSenderId.isNotEmpty && lastSenderId != currentUid;
  }

  // =========================================================================
  // CARETAKER OUTCOME CONFIRMATION & RESOLUTION (Rehomed / Sheltered / Return)
  // =========================================================================

  /// Caretaker directly completes and resolves care outcome (Rehomed, Sheltered, Returned TNR)
  /// without requiring reporter confirmation since caretaker has full custody.
  Future<int> completeCareOutcome({
    required String sightingId,
    required String outcomeAction, // 'rehomed', 'sheltered', 'returnedToSpot'
    required String note,
    File? proofPhotoFile,
    File? proofVideoFile,
    double? updatedLatitude,
    double? updatedLongitude,
    String? updatedLocationAddress,
    String? shelterOrClinicName,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return 0;
    final uid = user.uid;
    final name = user.displayName?.isNotEmpty == true
        ? user.displayName!
        : (user.email?.split('@').first ?? 'Caretaker');

    String? proofUrl;
    if (proofPhotoFile != null) {
      final urls = await uploadPhotos([proofPhotoFile], sightingId);
      if (urls.isNotEmpty) proofUrl = urls.first;
    }

    String? proofVideoUrl;
    if (proofVideoFile != null) {
      proofVideoUrl = await uploadVideo(proofVideoFile, sightingId);
    }

    final int earnedXp = outcomeAction == 'rehomed'
        ? 200
        : (outcomeAction == 'sheltered' ? 120 : 100);

    // 1. Post celebration announcement update to feed
    final actionText = outcomeAction == 'rehomed'
        ? 'successfully rehomed this cat with a loving forever family! 🏡🎉'
        : (outcomeAction == 'sheltered'
            ? 'safely transferred this cat to an animal shelter partner! 🏛️🐾'
            : 'completed recovery & neuter care and safely returned this cat as a protected Community Cat! 🌿🐾');

    final fullText = note.trim().isNotEmpty
        ? '$actionText "${note.trim()}"'
        : actionText;

    final updateDocData = <String, dynamic>{
      'type': 'outcomeResolved',
      'action': outcomeAction,
      'authorId': uid,
      'authorName': name,
      'proofPhotoUrl': proofUrl,
      if (proofVideoUrl != null && proofVideoUrl.isNotEmpty)
        'proofVideoUrl': proofVideoUrl,
      'text': fullText,
      'customNote': note.trim(),
      'xpAwarded': earnedXp,
      'status': 'completed',
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (updatedLatitude != null && updatedLongitude != null) {
      updateDocData['latitude'] = updatedLatitude;
      updateDocData['longitude'] = updatedLongitude;
    }
    if (updatedLocationAddress != null && updatedLocationAddress.isNotEmpty) {
      updateDocData['shelterAddress'] = updatedLocationAddress;
      updateDocData['locationAddress'] = updatedLocationAddress;
    }
    if (shelterOrClinicName != null && shelterOrClinicName.isNotEmpty) {
      updateDocData['shelterOrClinicName'] = shelterOrClinicName;
    }

    await _firestore
        .collection('sightings')
        .doc(sightingId)
        .collection('updates')
        .add(updateDocData);

    // 2. Award XP to caretaker & increment rescue count
    final userUpdates = <String, dynamic>{
      'xp': FieldValue.increment(earnedXp),
      'totalXp': FieldValue.increment(earnedXp),
      'successfulRescues': FieldValue.increment(1),
      'totalRescues': FieldValue.increment(1),
      'lastActive': FieldValue.serverTimestamp(),
    };
    if (outcomeAction == 'rehomed' || outcomeAction == 'sheltered') {
      userUpdates['completedFosters'] = FieldValue.increment(1);
    }
    await _firestore.collection('users').doc(uid).set(userUpdates, SetOptions(merge: true));

    // 3. Mark sighting outcome (TNR transitions to Community Cat, others to Resolved)
    final isTnr = outcomeAction == 'returnedToSpot';
    final updateFields = <String, dynamic>{
      'urgency': isTnr ? 'communityCare' : 'resolved',
      'resolvedByAction': outcomeAction,
      'resolvedAt': FieldValue.serverTimestamp(),
      'careStatus': isTnr ? 'onStreet' : 'resolved',
      'category': outcomeAction == 'rehomed'
          ? 'Rehomed'
          : (outcomeAction == 'sheltered'
              ? 'Sheltered'
              : (isTnr ? 'Community Cat' : 'Resolved')),
      'isOpenForAdoption': false,
      'rescueClaimed': false,
      'rescueClaimedBy': FieldValue.delete(),
      'rescueClaimedByName': FieldValue.delete(),
      'rescueClaimedAt': FieldValue.delete(),
      'pendingOutcomeAction': FieldValue.delete(),
      'pendingOutcomeNote': FieldValue.delete(),
      'pendingOutcomeProofUrl': FieldValue.delete(),
      'pendingOutcomeUpdateId': FieldValue.delete(),
      'rescuerUserIds': FieldValue.arrayUnion([uid]),
    };
    if (isTnr) {
      updateFields['isSterilized'] = true;
      updateFields['healthTags'] =
          FieldValue.arrayUnion(['✂️ Spayed / Neutered', '🩺 Vet Checked']);
    }
    updateFields['careTakerId'] = FieldValue.delete();
    updateFields['careTakerName'] = FieldValue.delete();
    updateFields['careStartedAt'] = FieldValue.delete();

    if (updatedLatitude != null && updatedLongitude != null) {
      updateFields['latitude'] = updatedLatitude;
      updateFields['longitude'] = updatedLongitude;
      updateFields['updatedLatitude'] = updatedLatitude;
      updateFields['updatedLongitude'] = updatedLongitude;
    }
    if (updatedLocationAddress != null && updatedLocationAddress.isNotEmpty) {
      updateFields['locationAddress'] = updatedLocationAddress;
      updateFields['updatedLocationAddress'] = updatedLocationAddress;
    }
    if (shelterOrClinicName != null && shelterOrClinicName.isNotEmpty) {
      updateFields['shelterOrClinicName'] = shelterOrClinicName;
    }
    if (proofVideoUrl != null && proofVideoUrl.isNotEmpty) {
      updateFields['outcomeVideoUrl'] = proofVideoUrl;
    }

    await _firestore
        .collection('sightings')
        .doc(sightingId)
        .update(updateFields);

    return earnedXp;
  }

  /// Caretaker completes foster milestones or decides to open cat for adoption
  Future<int> openCatForAdoption({
    required String sightingId,
    required String note,
    required File showcasePhotoFile,
    List<String>? healthTags,
    String? shelterOrClinicName,
    String? adoptionContact,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return 0;
    final uid = user.uid;
    final name = user.displayName?.isNotEmpty == true
        ? user.displayName!
        : (user.email?.split('@').first ?? 'Caretaker');

    String? photoUrl;
    final urls = await uploadPhotos([showcasePhotoFile], sightingId);
    if (urls.isNotEmpty) photoUrl = urls.first;

    const int earnedXp = 100;

    // 1. Post adoption announcement to feed
    final fullText = note.trim().isNotEmpty
        ? 'officially opened this cat for adoption! 🏡🐾 "${note.trim()}"'
        : 'officially opened this cat for adoption! 🏡🐾';

    await _firestore
        .collection('sightings')
        .doc(sightingId)
        .collection('updates')
        .add({
      'type': 'adoptionOpened',
      'action': 'adoptionOpened',
      'authorId': uid,
      'authorName': name,
      'proofPhotoUrl': photoUrl,
      'text': fullText,
      'customNote': note.trim(),
      'xpAwarded': earnedXp,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 2. Award XP to caretaker
    await _firestore.collection('users').doc(uid).set({
      'xp': FieldValue.increment(earnedXp),
      'totalXp': FieldValue.increment(earnedXp),
      'lastActive': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // 3. Update sighting category to 'Needs Home' and save adoption showcase profile
    final updateFields = <String, dynamic>{
      'category': 'Needs Home',
      'isOpenForAdoption': true,
      'careStatus': 'inCare_foster',
      'careTakerId': uid,
      'careTakerName': name,
      'urgency': 'needsHelp',
    };
    if (note.trim().isNotEmpty) {
      updateFields['adoptionNote'] = note.trim();
    }
    if (photoUrl != null) {
      updateFields['adoptionPhotoUrl'] = photoUrl;
      updateFields['photos'] = FieldValue.arrayUnion([photoUrl]);
    }
    if (healthTags != null && healthTags.isNotEmpty) {
      updateFields['healthTags'] = healthTags;
    }
    if (shelterOrClinicName != null && shelterOrClinicName.trim().isNotEmpty) {
      updateFields['shelterOrClinicName'] = shelterOrClinicName.trim();
    }
    if (adoptionContact != null && adoptionContact.trim().isNotEmpty) {
      updateFields['adoptionContact'] = adoptionContact.trim();
    }

    await _firestore
        .collection('sightings')
        .doc(sightingId)
        .update(updateFields);

    return earnedXp;
  }

  /// Prospective adopter submits adoption application / request to the caretaker
  Future<void> submitAdoptionApplication({
    required String sightingId,
    required String message,
    String? contactPhone,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final uid = user.uid;
    final name = user.displayName?.isNotEmpty == true
        ? user.displayName!
        : (user.email?.split('@').first ?? 'Adopter');

    final updateRef = await _firestore
        .collection('sightings')
        .doc(sightingId)
        .collection('updates')
        .add({
      'type': 'adoptionApplication',
      'action': 'adoptionRequested',
      'authorId': uid,
      'authorName': name,
      'text':
          'submitted an Adoption Application to adopt this cat! 🏡🐾 "${message.trim()}"',
      'customNote': message.trim(),
      'contactPhone': contactPhone?.trim(),
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Read current sighting to decide whether to set the "spotlight" applicant
    final sDoc =
        await _firestore.collection('sightings').doc(sightingId).get();
    final data = sDoc.data() ?? {};
    final currentApplicant = data['pendingAdoptionApplicantId']?.toString();
    final hasExistingApplicant =
        currentApplicant != null && currentApplicant.isNotEmpty;

    final Map<String, dynamic> updateData = {
      'adoptionApplicantCount': FieldValue.increment(1),
      'adoptionApplicantIds': FieldValue.arrayUnion([uid]),
    };

    // Only set the "spotlight" applicant fields if there isn't one already
    if (!hasExistingApplicant) {
      updateData['pendingAdoptionApplicantId'] = uid;
      updateData['pendingAdoptionApplicantName'] = name;
      updateData['pendingAdoptionMessage'] = message.trim();
      updateData['pendingAdoptionContact'] = contactPhone?.trim();
      updateData['pendingAdoptionUpdateId'] = updateRef.id;
    }

    await _firestore
        .collection('sightings')
        .doc(sightingId)
        .update(updateData);
  }

  /// Returns true if the current user has already submitted an adoption
  /// application for the given sighting (regardless of its current status).
  Future<bool> hasUserAlreadyRequestedAdoption(String sightingId) async {
    final user = _auth.currentUser;
    if (user == null) return false;
    final snap = await _firestore
        .collection('sightings')
        .doc(sightingId)
        .collection('updates')
        .where('type', isEqualTo: 'adoptionApplication')
        .where('authorId', isEqualTo: user.uid)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  /// Returns all pending adoption applications for a sighting, ordered newest first.
  Future<List<Map<String, dynamic>>> getAdoptionApplicants(
      String sightingId) async {
    final snap = await _firestore
        .collection('sightings')
        .doc(sightingId)
        .collection('updates')
        .where('type', isEqualTo: 'adoptionApplication')
        .get();
    final results = snap.docs
        .map((d) {
          final data = d.data();
          data['updateId'] = d.id;
          return data;
        })
        .where((d) => d['status'] == 'pending')
        .toList();
    // Sort newest first (createdAt may be a Timestamp or null)
    results.sort((a, b) {
      final aTs = a['createdAt'] as Timestamp?;
      final bTs = b['createdAt'] as Timestamp?;
      if (aTs == null && bTs == null) return 0;
      if (aTs == null) return 1;
      if (bTs == null) return -1;
      return bTs.compareTo(aTs);
    });
    return results;
  }

  /// Caretaker / reporter approves adoption application and rehomes the cat
  Future<void> approveAdoption({
    required String sightingId,
    String? updateId,
    required String applicantId,
    required String applicantName,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final uid = user.uid;
    final name = user.displayName?.isNotEmpty == true
        ? user.displayName!
        : (user.email?.split('@').first ?? 'Caretaker');

    if (updateId != null && updateId.isNotEmpty) {
      await _firestore
          .collection('sightings')
          .doc(sightingId)
          .collection('updates')
          .doc(updateId)
          .update({'status': 'approved'});
    }

    await _firestore
        .collection('sightings')
        .doc(sightingId)
        .collection('updates')
        .add({
      'type': 'adoptionApproved',
      'action': 'rehomed',
      'authorId': uid,
      'authorName': name,
      'text':
          'approved adoption application! $applicantName is now the loving forever adopter! 🏡🎉',
      'xpAwarded': 200,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await _firestore.collection('users').doc(uid).set({
      'xp': FieldValue.increment(200),
      'totalXp': FieldValue.increment(200),
      'lastActive': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _firestore.collection('users').doc(applicantId).set({
      'xp': FieldValue.increment(200),
      'totalXp': FieldValue.increment(200),
      'lastActive': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _firestore.collection('sightings').doc(sightingId).update({
      'urgency': 'resolved',
      'status': 'resolved',
      'category': 'Resolved',
      'resolvedAt': FieldValue.serverTimestamp(),
      'resolvedByAction': 'rehomed',
      'careStatus': 'resolved',
      'isOpenForAdoption': false,
      'pendingAdoptionApplicantId': FieldValue.delete(),
      'pendingAdoptionApplicantName': FieldValue.delete(),
      'pendingAdoptionMessage': FieldValue.delete(),
      'pendingAdoptionContact': FieldValue.delete(),
      'pendingAdoptionUpdateId': FieldValue.delete(),
      'pendingOutcomeAction': FieldValue.delete(),
      'pendingOutcomeNote': FieldValue.delete(),
      'pendingOutcomeProofUrl': FieldValue.delete(),
      'pendingOutcomeUpdateId': FieldValue.delete(),
      'careTakerId': FieldValue.delete(),
      'careTakerName': FieldValue.delete(),
      'careStartedAt': FieldValue.delete(),
    });
  }

  /// Caretaker / reporter declines adoption application.
  /// If there are other pending applicants, the next one is promoted
  /// into the "spotlight" fields shown on the pending adoption banner.
  Future<void> declineAdoption({
    required String sightingId,
    String? updateId,
    String? declinedApplicantId,
  }) async {
    if (updateId != null && updateId.isNotEmpty) {
      await _firestore
          .collection('sightings')
          .doc(sightingId)
          .collection('updates')
          .doc(updateId)
          .update({'status': 'declined'});
    }

    // Check for remaining pending applicants to promote
    final remaining = await _firestore
        .collection('sightings')
        .doc(sightingId)
        .collection('updates')
        .where('type', isEqualTo: 'adoptionApplication')
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt')
        .limit(1)
        .get();

    if (remaining.docs.isNotEmpty) {
      final next = remaining.docs.first;
      final nd = next.data();
      await _firestore.collection('sightings').doc(sightingId).update({
        'pendingAdoptionApplicantId': nd['authorId'],
        'pendingAdoptionApplicantName': nd['authorName'],
        'pendingAdoptionMessage': nd['customNote'] ?? '',
        'pendingAdoptionContact': nd['contactPhone'],
        'pendingAdoptionUpdateId': next.id,
      });
    } else {
      // No remaining applicants — clear the spotlight
      await _firestore.collection('sightings').doc(sightingId).update({
        'pendingAdoptionApplicantId': FieldValue.delete(),
        'pendingAdoptionApplicantName': FieldValue.delete(),
        'pendingAdoptionMessage': FieldValue.delete(),
        'pendingAdoptionContact': FieldValue.delete(),
        'pendingAdoptionUpdateId': FieldValue.delete(),
      });
    }
  }

  /// Caretaker / rescuer requests outcome confirmation (shelter transfer, rehome, TNR return)
  Future<void> requestOutcomeConfirmation({
    required String sightingId,
    required String outcomeAction, // 'rehomed', 'returnedToSpot', 'sheltered'
    required String note,
    File? proofPhotoFile,
    File? proofVideoFile,
    String? shelterOrClinicName,
    String? updatedLocationAddress,
    double? updatedLatitude,
    double? updatedLongitude,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    String? proofUrl;
    if (proofPhotoFile != null) {
      final urls = await uploadPhotos([proofPhotoFile], sightingId);
      if (urls.isNotEmpty) proofUrl = urls.first;
    }

    String? proofVideoUrl;
    if (proofVideoFile != null) {
      proofVideoUrl = await uploadVideo(proofVideoFile, sightingId);
    }

    final updateDocData = <String, dynamic>{
      'type': 'outcomeRequest',
      'action': outcomeAction,
      'authorId': user.uid,
      'authorName': user.displayName ?? 'Caretaker',
      'proofPhotoUrl': proofUrl,
      if (proofVideoUrl != null && proofVideoUrl.isNotEmpty)
        'proofVideoUrl': proofVideoUrl,
      'customNote': note.trim(),
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (shelterOrClinicName != null && shelterOrClinicName.isNotEmpty) {
      updateDocData['shelterOrClinicName'] = shelterOrClinicName;
    }
    if (updatedLocationAddress != null && updatedLocationAddress.isNotEmpty) {
      updateDocData['locationAddress'] = updatedLocationAddress;
      updateDocData['shelterAddress'] = updatedLocationAddress;
    }
    if (updatedLatitude != null && updatedLongitude != null) {
      updateDocData['latitude'] = updatedLatitude;
      updateDocData['longitude'] = updatedLongitude;
    }

    final updateRef = await _firestore
        .collection('sightings')
        .doc(sightingId)
        .collection('updates')
        .add(updateDocData);

    final sightingUpdates = <String, dynamic>{
      'pendingOutcomeAction': outcomeAction,
      'pendingOutcomeNote': note.trim(),
      'pendingOutcomeProofUrl': proofUrl,
      'pendingOutcomeUpdateId': updateRef.id,
    };
    if (shelterOrClinicName != null && shelterOrClinicName.isNotEmpty) {
      sightingUpdates['shelterOrClinicName'] = shelterOrClinicName;
    }
    if (updatedLocationAddress != null && updatedLocationAddress.isNotEmpty) {
      sightingUpdates['updatedLocationAddress'] = updatedLocationAddress;
    }
    if (updatedLatitude != null && updatedLongitude != null) {
      sightingUpdates['updatedLatitude'] = updatedLatitude;
      sightingUpdates['updatedLongitude'] = updatedLongitude;
    }

    await _firestore
        .collection('sightings')
        .doc(sightingId)
        .update(sightingUpdates);
  }

  /// Reporter / Admin approves the outcome confirmation
  Future<void> approveOutcomeConfirmation({
    required String sightingId,
    required String outcomeAction,
    String? updateId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    if (updateId != null && updateId.isNotEmpty) {
      try {
        await _firestore
            .collection('sightings')
            .doc(sightingId)
            .collection('updates')
            .doc(updateId)
            .update({
          'status': 'approved',
          'approvedBy': user.uid,
          'approvedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    }

    if (outcomeAction == 'rehomed') {
      await logRescueAction(
        sightingId: sightingId,
        action: 'rehomed',
        customNote: 'Adopted and permanently rehomed! 🎉',
      );
    } else if (outcomeAction == 'sheltered') {
      // Admin-approved shelter transfer: update sighting directly to avoid
      // completeCareOutcome using the admin's UID for XP and authorship.
      final sDoc =
          await _firestore.collection('sightings').doc(sightingId).get();
      final sData = sDoc.data() ?? {};
      final sName = sData['shelterOrClinicName']?.toString();
      final sAddr = sData['updatedLocationAddress']?.toString();
      final sLat = sData['updatedLatitude'];
      final sLng = sData['updatedLongitude'];
      final sNote = sData['pendingOutcomeNote']?.toString() ??
          'Transferred safely to registered animal shelter partner. 🏛️';
      final caretakerUid = sData['careTakerId']?.toString();
      final caretakerName = sData['careTakerName']?.toString() ?? 'Caretaker';

      // Post celebration update to the sighting's update feed
      final celebrationData = <String, dynamic>{
        'type': 'outcomeResolved',
        'action': 'sheltered',
        'authorId': caretakerUid ?? user.uid,
        'authorName': caretakerName,
        'text':
            'safely transferred this cat to an animal shelter partner! 🏛️🐾 "$sNote"',
        'customNote': sNote,
        'xpAwarded': 120,
        'status': 'completed',
        'createdAt': FieldValue.serverTimestamp(),
        'approvedBy': user.uid,
      };
      if (sName != null && sName.isNotEmpty) {
        celebrationData['shelterOrClinicName'] = sName;
      }
      if (sAddr != null && sAddr.isNotEmpty) {
        celebrationData['shelterAddress'] = sAddr;
        celebrationData['locationAddress'] = sAddr;
      }
      if (sLat is num && sLng is num) {
        celebrationData['latitude'] = sLat.toDouble();
        celebrationData['longitude'] = sLng.toDouble();
      }
      await _firestore
          .collection('sightings')
          .doc(sightingId)
          .collection('updates')
          .add(celebrationData);

      // Award XP to the original caretaker (not the admin)
      if (caretakerUid != null && caretakerUid.isNotEmpty) {
        try {
          await _firestore
              .collection('users')
              .doc(caretakerUid)
              .set(<String, dynamic>{
            'xp': FieldValue.increment(120),
            'totalXp': FieldValue.increment(120),
            'successfulRescues': FieldValue.increment(1),
            'totalRescues': FieldValue.increment(1),
            'completedFosters': FieldValue.increment(1),
            'lastActive': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (_) {}
      }

      // Mark sighting as resolved with all necessary fields
      final sightingResolveFields = <String, dynamic>{
        'urgency': 'resolved',
        'resolvedByAction': 'sheltered',
        'resolvedAt': FieldValue.serverTimestamp(),
        'careStatus': 'resolved',
        'category': 'Sheltered',
        'isOpenForAdoption': false,
        'rescueClaimed': false,
        'rescueClaimedBy': FieldValue.delete(),
        'rescueClaimedByName': FieldValue.delete(),
        'rescueClaimedAt': FieldValue.delete(),
        'pendingOutcomeAction': FieldValue.delete(),
        'pendingOutcomeNote': FieldValue.delete(),
        'pendingOutcomeProofUrl': FieldValue.delete(),
        'pendingOutcomeUpdateId': FieldValue.delete(),
        'careTakerId': FieldValue.delete(),
        'careTakerName': FieldValue.delete(),
        'careStartedAt': FieldValue.delete(),
      };
      if (caretakerUid != null && caretakerUid.isNotEmpty) {
        sightingResolveFields['rescuerUserIds'] =
            FieldValue.arrayUnion([caretakerUid]);
      }
      if (sLat is num && sLng is num) {
        sightingResolveFields['latitude'] = sLat.toDouble();
        sightingResolveFields['longitude'] = sLng.toDouble();
        sightingResolveFields['updatedLatitude'] = sLat.toDouble();
        sightingResolveFields['updatedLongitude'] = sLng.toDouble();
      }
      if (sAddr != null && sAddr.isNotEmpty) {
        sightingResolveFields['locationAddress'] = sAddr;
        sightingResolveFields['updatedLocationAddress'] = sAddr;
      }
      if (sName != null && sName.isNotEmpty) {
        sightingResolveFields['shelterOrClinicName'] = sName;
      }
      await _firestore
          .collection('sightings')
          .doc(sightingId)
          .update(sightingResolveFields);
    } else {
      await _firestore.collection('sightings').doc(sightingId).update({
        'urgency': 'communityCare',
        'category': 'Community Cat',
        'careStatus': 'onStreet',
        'resolvedByAction': 'returnedToSpot',
        'isSterilized': true,
        'healthTags':
            FieldValue.arrayUnion(['✂️ Spayed / Neutered', '🩺 Vet Checked']),
        'careTakerId': null,
        'careTakerName': null,
        'careStartedAt': null,
        'rescueClaimed': false,
        'rescueClaimedBy': FieldValue.delete(),
        'rescueClaimedByName': FieldValue.delete(),
        'rescueClaimedAt': FieldValue.delete(),
        'pendingOutcomeAction': FieldValue.delete(),
        'pendingOutcomeNote': FieldValue.delete(),
        'pendingOutcomeProofUrl': FieldValue.delete(),
        'pendingOutcomeUpdateId': FieldValue.delete(),
      });
    }

    await _firestore.collection('sightings').doc(sightingId).update({
      'pendingOutcomeAction': FieldValue.delete(),
      'pendingOutcomeNote': FieldValue.delete(),
      'pendingOutcomeProofUrl': FieldValue.delete(),
      'pendingOutcomeUpdateId': FieldValue.delete(),
    });
  }

  /// Reporter declines outcome confirmation
  Future<void> declineOutcomeConfirmation({
    required String sightingId,
    String? updateId,
  }) async {
    if (updateId != null && updateId.isNotEmpty) {
      try {
        await _firestore
            .collection('sightings')
            .doc(sightingId)
            .collection('updates')
            .doc(updateId)
            .update({
          'status': 'declined',
          'declinedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    }

    await _firestore.collection('sightings').doc(sightingId).update({
      'pendingOutcomeAction': FieldValue.delete(),
      'pendingOutcomeNote': FieldValue.delete(),
      'pendingOutcomeProofUrl': FieldValue.delete(),
      'pendingOutcomeUpdateId': FieldValue.delete(),
    });
  }

  /// Update Adoption Showcase profile (health badges, shelter name, contact)
  Future<void> updateAdoptionShowcaseProfile({
    required String sightingId,
    required List<String> healthTags,
    String? shelterOrClinicName,
    String? adoptionContact,
  }) async {
    final updateData = <String, dynamic>{
      'healthTags': healthTags,
    };
    if (shelterOrClinicName != null && shelterOrClinicName.trim().isNotEmpty) {
      updateData['shelterOrClinicName'] = shelterOrClinicName.trim();
    }
    if (adoptionContact != null && adoptionContact.trim().isNotEmpty) {
      updateData['adoptionContact'] = adoptionContact.trim();
    }

    await _firestore.collection('sightings').doc(sightingId).update(updateData);
  }

  /// Reporter approves a pending vet visit confirmation
  Future<void> approveVetVisitConfirmation({
    required String sightingId,
    required String rescuerId,
    String? updateId,
    int xp = 100,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // 1. Mark update as approved if updateId exists
    if (updateId != null && updateId.isNotEmpty) {
      try {
        await _firestore
            .collection('sightings')
            .doc(sightingId)
            .collection('updates')
            .doc(updateId)
            .update({
          'status': 'approved',
          'isReporterConfirmed': true,
          'confirmedBy': user.uid,
          'confirmedAt': FieldValue.serverTimestamp(),
          'approvedBy': user.uid,
          'approvedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    }

    // 2. Award XP to rescuer
    try {
      await _firestore.collection('users').doc(rescuerId).set({
        'xp': FieldValue.increment(xp),
        'totalXp': FieldValue.increment(xp),
        'totalRescues': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error awarding rescuer vet XP: $e');
    }

    // 3. Update sighting: hasVetVisit = true, clear pending fields, demote urgent to needsHelp
    final sightingDoc =
        await _firestore.collection('sightings').doc(sightingId).get();
    final currentUrgency = sightingDoc.data()?['urgency']?.toString();

    final rescuerName =
        sightingDoc.data()?['pendingVetRescuerName']?.toString() ?? 'Rescuer';

    final updateData = <String, dynamic>{
      'hasVetVisit': true,
      'hasVetVisitFlag': true,
      'lastVetVisitAt': FieldValue.serverTimestamp(),
      'vetVerifiedAt': FieldValue.serverTimestamp(),
      'lastVetRescuerId': rescuerId,
      'lastVetRescuerName': rescuerName,
      'pendingVetRescuerId': FieldValue.delete(),
      'pendingVetRescuerName': FieldValue.delete(),
      'pendingVetProofUrl': FieldValue.delete(),
      'pendingVetClinicName': FieldValue.delete(),
      'pendingVetNote': FieldValue.delete(),
      'pendingVetUpdateId': FieldValue.delete(),
      'rescueClaimed': false,
      'rescueClaimedBy': FieldValue.delete(),
      'rescueClaimedByName': FieldValue.delete(),
      'rescueClaimedAt': FieldValue.delete(),
    };

    if (currentUrgency == 'urgent') {
      updateData['urgency'] = 'needsHelp';
    }

    await _firestore
        .collection('sightings')
        .doc(sightingId)
        .update(updateData);
  }

  /// Reporter delegates post-vet custody to the rescuer to manage placement
  Future<void> delegatePostVetCustodyToRescuer(String sightingId) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final name = user.displayName?.isNotEmpty == true
        ? user.displayName!
        : (user.email?.split('@').first ?? 'Reporter');

    final sightingDoc =
        await _firestore.collection('sightings').doc(sightingId).get();
    final rescuerName =
        sightingDoc.data()?['lastVetRescuerName']?.toString() ??
        sightingDoc.data()?['pendingVetRescuerName']?.toString() ??
        'Rescuer';

    await _firestore.collection('sightings').doc(sightingId).update({
      'postVetCustody': 'rescuerInCharge',
      'postVetCustodyDelegatedAt': FieldValue.serverTimestamp(),
      'postVetCustodyDelegatedBy': user.uid,
    });

    await _firestore
        .collection('sightings')
        .doc(sightingId)
        .collection('updates')
        .add({
      'type': 'status_update',
      'action': 'custody_delegated',
      'authorId': user.uid,
      'authorName': name,
      'note': '$name placed $rescuerName in charge of next steps (foster, shelter, or adoption).',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Rescuer completed vet visit but cannot foster; requests community foster
  Future<void> requestCommunityFoster({
    required String sightingId,
    String? note,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final name = user.displayName?.isNotEmpty == true
        ? user.displayName!
        : (user.email?.split('@').first ?? 'Rescuer');

    final sightingRef = _firestore.collection('sightings').doc(sightingId);
    await sightingRef.update({
      'category': 'Needs Foster',
      'urgency': 'needsHelp',
      'isCommunityFosterRequested': true,
    });

    await sightingRef.collection('updates').add({
      'type': 'fosterRequest',
      'authorId': user.uid,
      'authorName': name,
      'text': note?.trim().isNotEmpty == true
          ? note!.trim()
          : "completed the veterinary checkup! Cat is medically cleared and looking for a community foster home. 🏡🐾",
      'isAnonymous': false,
      'parentId': '',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Reporter declines a pending vet visit confirmation
  Future<void> declineVetVisitConfirmation({
    required String sightingId,
    String? updateId,
  }) async {
    if (updateId != null && updateId.isNotEmpty) {
      try {
        await _firestore
            .collection('sightings')
            .doc(sightingId)
            .collection('updates')
            .doc(updateId)
            .update({
          'status': 'declined',
          'declinedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    }

    await _firestore.collection('sightings').doc(sightingId).update({
      'pendingVetRescuerId': FieldValue.delete(),
      'pendingVetRescuerName': FieldValue.delete(),
      'pendingVetProofUrl': FieldValue.delete(),
      'pendingVetClinicName': FieldValue.delete(),
      'pendingVetNote': FieldValue.delete(),
      'pendingVetUpdateId': FieldValue.delete(),
    });
  }

  /// Community suggestion for a new vet clinic or rescue shelter (Admin verifies)
  Future<void> submitClinicSuggestion({
    required String name,
    required String type, // 'clinic' or 'shelter'
    required String address,
    required double latitude,
    required double longitude,
    required String phone,
    String? operatingHours,
    bool is24Hours = false,
    List<String> services = const [],
    String? notes,
  }) async {
    final user = _auth.currentUser;
    final uid = user?.uid ?? 'anon';
    final userName = user?.displayName ?? user?.email ?? 'PawWatch Volunteer';

    final docRef = _firestore.collection('clinic_suggestions').doc();
    await docRef.set({
      'id': docRef.id,
      'name': name.trim(),
      'type': type,
      'address': address.trim(),
      'latitude': latitude,
      'longitude': longitude,
      'phone': phone.trim(),
      'operatingHours': operatingHours?.trim() ?? (is24Hours ? '24 Hours Emergency' : ''),
      'is24Hours': is24Hours,
      'services': services,
      'notes': notes?.trim() ?? '',
      'submittedBy': uid,
      'submittedByName': userName,
      'status': 'pending', // Pending review for "Verify Clinic Suggestion" use case
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ─────────────── ADMIN METHODS ───────────────

  /// Check if current user is admin
  bool get isCurrentUserAdmin {
    final email = _auth.currentUser?.email;
    return email == 'admin@example.com';
  }

  /// Stream all flags (pending) for admin review
  Stream<List<Map<String, dynamic>>> streamPendingFlags() {
    return _firestore
        .collection('flags')
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final data = d.data();
              data['docId'] = d.id;
              return data;
            }).toList())
        .handleError((_) => <Map<String, dynamic>>[]);
  }

  /// Stream all flags for admin (no status filter, fallback if index missing)
  Stream<List<Map<String, dynamic>>> streamAllFlags() {
    return _firestore
        .collection('flags')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final data = d.data();
              data['docId'] = d.id;
              return data;
            }).toList())
        .handleError((_) => <Map<String, dynamic>>[]);
  }

  /// Stream pending clinic/shelter suggestions
  Stream<List<Map<String, dynamic>>> streamPendingClinicSuggestions() {
    return _firestore
        .collection('clinic_suggestions')
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final data = d.data();
              data['docId'] = d.id;
              return data;
            }).toList())
        .handleError((_) => <Map<String, dynamic>>[]);
  }

  /// Stream all clinic suggestions
  Stream<List<Map<String, dynamic>>> streamAllClinicSuggestions() {
    return _firestore
        .collection('clinic_suggestions')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final data = d.data();
              data['docId'] = d.id;
              return data;
            }).toList())
        .handleError((_) => <Map<String, dynamic>>[]);
  }

  /// Ban a user
  Future<void> banUser(String targetUid, {String? reason}) async {
    String userEmail = '';
    try {
      final doc = await _firestore.collection('users').doc(targetUid).get();
      userEmail = (doc.data()?['email']?.toString() ?? '').toLowerCase().trim();
    } catch (_) {}

    await _firestore.collection('users').doc(targetUid).set({
      'isBanned': true,
      'bannedAt': FieldValue.serverTimestamp(),
      'bannedBy': _auth.currentUser?.uid ?? 'admin',
      'banReason': reason ?? 'Violation of community guidelines',
    }, SetOptions(merge: true));

    // Record in banned_users collection so ban persists even if deleted from users
    await _firestore.collection('banned_users').doc(targetUid).set({
      'uid': targetUid,
      'email': userEmail,
      'bannedAt': FieldValue.serverTimestamp(),
      'banReason': reason ?? 'Violation of community guidelines',
    }, SetOptions(merge: true));
  }

  /// Unban a user
  Future<void> unbanUser(String targetUid) async {
    await _firestore.collection('users').doc(targetUid).set({
      'isBanned': false,
      'bannedAt': FieldValue.delete(),
      'bannedBy': FieldValue.delete(),
      'banReason': FieldValue.delete(),
    }, SetOptions(merge: true));

    try {
      await _firestore.collection('banned_users').doc(targetUid).delete();
    } catch (_) {}
  }

  /// Delete / remove a user from the users collection (frees up space in user management)
  Future<void> deleteUserDocument(String targetUid) async {
    await _firestore.collection('users').doc(targetUid).delete();
  }

  /// Check if a user is currently banned
  Future<bool> isUserBanned(String targetUid, {String? email}) async {
    try {
      // 1. Check users collection
      final userDoc = await _firestore.collection('users').doc(targetUid).get();
      if (userDoc.exists && userDoc.data()?['isBanned'] == true) {
        return true;
      }

      // 2. Check banned_users collection by UID
      final bannedDoc =
          await _firestore.collection('banned_users').doc(targetUid).get();
      if (bannedDoc.exists) {
        return true;
      }

      // 3. Check banned_users by email if provided
      if (email != null && email.isNotEmpty) {
        final emailSnap = await _firestore
            .collection('banned_users')
            .where('email', isEqualTo: email.toLowerCase().trim())
            .limit(1)
            .get();
        if (emailSnap.docs.isNotEmpty) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Checks if a displayName is already taken in the users collection.
  /// Optionally exclude a specific UID (useful when editing own profile).
  Future<bool> isDisplayNameTaken(String name, {String? excludeUid}) async {
    final trimmed = name.trim().toLowerCase();
    if (trimmed.isEmpty) return false;
    try {
      final snap = await _firestore.collection('users').get();
      for (final doc in snap.docs) {
        if (excludeUid != null && doc.id == excludeUid) continue;
        final docName =
            (doc.data()['displayName']?.toString() ?? '').trim().toLowerCase();
        if (docName == trimmed) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Checks if an email is already registered in Firestore users or banned_users
  Future<bool> isEmailRegistered(String email) async {
    final trimmed = email.trim().toLowerCase();
    if (trimmed.isEmpty) return false;
    try {
      final snap = await _firestore
          .collection('users')
          .where('email', isEqualTo: trimmed)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) return true;

      final bannedSnap = await _firestore
          .collection('banned_users')
          .where('email', isEqualTo: trimmed)
          .limit(1)
          .get();
      if (bannedSnap.docs.isNotEmpty) return true;

      return false;
    } catch (_) {
      return false;
    }
  }

  /// Suspend a user temporarily
  Future<void> suspendUser(String targetUid, {String? reason, int days = 7}) async {
    await _firestore.collection('users').doc(targetUid).update({
      'isSuspended': true,
      'suspendedAt': FieldValue.serverTimestamp(),
      'suspendedBy': _auth.currentUser?.uid ?? 'admin',
      'suspendReason': reason ?? 'Temporary suspension',
      'suspendDays': days,
    });
  }

  /// Unsuspend a user
  Future<void> unsuspendUser(String targetUid) async {
    await _firestore.collection('users').doc(targetUid).update({
      'isSuspended': false,
      'suspendedAt': FieldValue.delete(),
      'suspendedBy': FieldValue.delete(),
      'suspendReason': FieldValue.delete(),
      'suspendDays': FieldValue.delete(),
    });
  }

  /// Admin: delete a comment (hard override, works for any comment type)
  Future<void> adminDeleteComment({
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
      'text': '[Removed by Admin]',
      'isDeleted': true,
      'deletedByAdmin': true,
      'deletedAt': FieldValue.serverTimestamp(),
      'deletedBy': _auth.currentUser?.uid ?? 'admin',
    });

    final sightingRef = _firestore.collection('sightings').doc(sightingId);
    final sightingSnap = await sightingRef.get();
    final currentCount = (sightingSnap.data()?['commentCount'] as num?)?.toInt() ?? 0;
    if (currentCount > 0) {
      batch.update(sightingRef, {'commentCount': FieldValue.increment(-1)});
    } else {
      batch.update(sightingRef, {'commentCount': 0});
    }
    await batch.commit();
  }

  /// Admin: delete a sighting/report with reason
  Future<void> adminDeleteSighting(String sightingId, {String? reason}) async {
    await _firestore.collection('sightings').doc(sightingId).update({
      'isDeleted': true,
      'deletedByAdmin': true,
      'deletedAt': FieldValue.serverTimestamp(),
      'deletedBy': _auth.currentUser?.uid ?? 'admin',
      'deletedReason': reason ?? 'Violated community guidelines',
    });
  }

  /// Admin: verify a clinic/shelter suggestion
  Future<void> verifyClinicSuggestion(String docId) async {
    String? shelterName;
    try {
      final docSnap =
          await _firestore.collection('clinic_suggestions').doc(docId).get();
      shelterName = docSnap.data()?['name']?.toString();
    } catch (_) {}

    await _firestore.collection('clinic_suggestions').doc(docId).update({
      'status': 'verified',
      'verifiedAt': FieldValue.serverTimestamp(),
      'verifiedBy': _auth.currentUser?.uid ?? 'admin',
    });

    if (shelterName != null && shelterName.isNotEmpty) {
      try {
        final pendingSightings = await _firestore
            .collection('sightings')
            .where('pendingOutcomeAction', isEqualTo: 'sheltered')
            .get();
        final targetName = shelterName.trim().toLowerCase();
        for (final sDoc in pendingSightings.docs) {
          final sData = sDoc.data();
          final sName = (sData['shelterOrClinicName'] ?? '').toString().trim().toLowerCase();
          if (sName == targetName || sName.isEmpty || targetName.isEmpty) {
            await approveOutcomeConfirmation(
              sightingId: sDoc.id,
              outcomeAction: 'sheltered',
              updateId: sData['pendingOutcomeUpdateId']?.toString(),
            );
          }
        }
      } catch (e) {
        debugPrint('Error approving pending shelter sightings: $e');
      }
    }
  }

  /// Self-healing check: automatically resolve any sightings whose requested shelter
  /// or rehoming outcome has been submitted or verified.
  Future<void> autoResolveVerifiedShelterSightings() async {
    try {
      final pendingSightings = await _firestore
          .collection('sightings')
          .where('pendingOutcomeAction', whereIn: ['sheltered', 'rehomed', 'returnedToSpot'])
          .get();
      for (final sDoc in pendingSightings.docs) {
        final sData = sDoc.data();
        final action = sData['pendingOutcomeAction']?.toString() ?? 'sheltered';
        await approveOutcomeConfirmation(
          sightingId: sDoc.id,
          outcomeAction: action,
          updateId: sData['pendingOutcomeUpdateId']?.toString(),
        );
      }
    } catch (e) {
      debugPrint('Error in autoResolveVerifiedShelterSightings: $e');
    }

    // Clean up any lingering custody for sightings that are resolved/sheltered/rehomed
    try {
      final resolvedSightings = await _firestore
          .collection('sightings')
          .where('category', whereIn: ['Resolved', 'Sheltered', 'Rehomed'])
          .get();
      for (final doc in resolvedSightings.docs) {
        final d = doc.data();
        if (d['careTakerId'] != null ||
            d['careStatus'] != 'resolved' ||
            d['urgency'] != 'resolved' ||
            d['pendingOutcomeAction'] != null) {
          await doc.reference.update({
            'urgency': 'resolved',
            'careStatus': 'resolved',
            'careTakerId': FieldValue.delete(),
            'careTakerName': FieldValue.delete(),
            'careStartedAt': FieldValue.delete(),
            'pendingOutcomeAction': FieldValue.delete(),
            'pendingOutcomeNote': FieldValue.delete(),
            'pendingOutcomeProofUrl': FieldValue.delete(),
            'pendingOutcomeUpdateId': FieldValue.delete(),
          });
        }
      }
    } catch (e) {
      debugPrint('Error cleaning up resolved sightings: $e');
    }
  }

  /// Admin: reject a clinic/shelter suggestion
  Future<void> rejectClinicSuggestion(String docId, {String? reason}) async {
    await _firestore.collection('clinic_suggestions').doc(docId).update({
      'status': 'rejected',
      'rejectedAt': FieldValue.serverTimestamp(),
      'rejectedBy': _auth.currentUser?.uid ?? 'admin',
      'rejectionReason': reason ?? '',
    });
  }

  /// Admin: resolve/dismiss a flag
  Future<void> resolveFlag(String flagDocId, {String action = 'dismissed'}) async {
    await _firestore.collection('flags').doc(flagDocId).update({
      'status': action,
      'resolvedAt': FieldValue.serverTimestamp(),
      'resolvedBy': _auth.currentUser?.uid ?? 'admin',
    });
  }

  /// Admin: delete a specific flag document
  Future<void> deleteFlag(String flagDocId) async {
    await _firestore.collection('flags').doc(flagDocId).delete();
  }

  /// Admin: clear all resolved/dismissed flags to free up space
  Future<int> clearResolvedFlags() async {
    final snap = await _firestore
        .collection('flags')
        .where('status', whereIn: ['resolved', 'dismissed'])
        .get();
    if (snap.docs.isEmpty) return 0;
    final batch = _firestore.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    return snap.docs.length;
  }

  /// Admin: create an announcement (appears in all users' notifications)
  Future<void> createAnnouncement({
    required String title,
    required String body,
    String? category,
  }) async {
    final user = _auth.currentUser;
    await _firestore.collection('announcements').add({
      'title': title.trim(),
      'body': body.trim(),
      'category': category ?? 'general',
      'createdBy': user?.uid ?? 'admin',
      'createdByName': user?.displayName ?? 'PawWatch Admin',
      'createdAt': FieldValue.serverTimestamp(),
      'isActive': true,
    });
  }

  /// Stream announcements (for all users' notification tab)
  Stream<List<Map<String, dynamic>>> streamAnnouncements() {
    return _firestore
        .collection('announcements')
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final data = d.data();
              data['docId'] = d.id;
              return data;
            }).toList())
        .handleError((_) => <Map<String, dynamic>>[]);
  }

  /// Admin: delete/deactivate an announcement
  Future<void> deleteAnnouncement(String docId) async {
    await _firestore.collection('announcements').doc(docId).update({
      'isActive': false,
      'deletedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Admin: create a new badge definition
  Future<void> createBadge({
    required String title,
    required String description,
    required String requirements,
    String? iconUrl,
  }) async {
    await _firestore.collection('badge_definitions').add({
      'title': title.trim(),
      'description': description.trim(),
      'requirements': requirements.trim(),
      'iconUrl': iconUrl,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': _auth.currentUser?.uid ?? 'admin',
      'isActive': true,
    });
  }

  /// Stream all badge definitions
  Stream<List<Map<String, dynamic>>> streamBadgeDefinitions() {
    return _firestore
        .collection('badge_definitions')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final data = d.data();
              data['docId'] = d.id;
              return data;
            }).toList())
        .handleError((_) => <Map<String, dynamic>>[]);
  }

  /// Ensures a Firestore user document exists for an authenticated user
  Future<void> ensureUserDoc(User user, {String? displayName}) async {
    try {
      if (await isUserBanned(user.uid, email: user.email)) {
        return;
      }
      final userRef = _firestore.collection('users').doc(user.uid);
      final doc = await userRef.get();
      final effectiveName = displayName?.trim().isNotEmpty == true
          ? displayName!.trim()
          : (user.displayName?.isNotEmpty == true
              ? user.displayName!
              : (user.email?.split('@').first ?? 'PawWatcher'));
      final role = (user.email == 'admin@example.com') ? 'admin' : 'user';

      if (!doc.exists) {
        await userRef.set({
          'uid': user.uid,
          'displayName': effectiveName,
          'email': user.email ?? '',
          'photoUrl': user.photoURL,
          'role': role,
          'xp': 0,
          'totalXp': 0,
          'level': 1,
          'trustScore': 5.0,
          'totalRescues': 0,
          'successfulRescues': 0,
          'completedFosters': 0,
          'activeFosters': 0,
          'checkInRate': 100.0,
          'flagCount': 0,
          'isBanned': false,
          'isSuspended': false,
          'joinedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'lastActive': FieldValue.serverTimestamp(),
          'badges': ['Newcomer PawWatcher 🐾'],
        });
      } else {
        final existingData = doc.data() ?? {};
        final updates = <String, dynamic>{
          'lastActive': FieldValue.serverTimestamp(),
        };
        if (existingData['email'] == null ||
            (existingData['email'] as String).isEmpty) {
          updates['email'] = user.email ?? '';
        }
        if (existingData['displayName'] == null ||
            (existingData['displayName'] as String).isEmpty) {
          updates['displayName'] = effectiveName;
        }
        if (user.email == 'admin@example.com' && existingData['role'] != 'admin') {
          updates['role'] = 'admin';
        }
        if (updates.isNotEmpty) {
          await userRef.set(updates, SetOptions(merge: true));
        }
      }
    } catch (e) {
      debugPrint('ensureUserDoc notice: $e');
    }
  }

  /// Discovers any user IDs from sightings, updates, and current auth state
  /// that are missing from the `users` collection, and auto-creates their user documents.
  Future<void> syncMissingUsersFromActivity() async {
    try {
      // 1. Ensure current authenticated user exists
      if (_auth.currentUser != null) {
        await ensureUserDoc(_auth.currentUser!);
      }

      // 2. Fetch all existing user IDs
      final usersSnap = await _firestore.collection('users').get();
      final existingUids = usersSnap.docs.map((d) => d.id).toSet();

      // 3. Collect user references from sightings
      final sightingsSnap = await _firestore.collection('sightings').get();
      final missingUsers = <String, String>{}; // uid -> name

      for (final sDoc in sightingsSnap.docs) {
        final data = sDoc.data();
        final repId = data['reporterId']?.toString();
        final repName = data['reporterName']?.toString();
        if (repId != null && repId.isNotEmpty && !existingUids.contains(repId)) {
          missingUsers[repId] = repName?.isNotEmpty == true ? repName! : 'PawWatcher';
        }

        final careId = data['careTakerId']?.toString();
        final careName = data['careTakerName']?.toString();
        if (careId != null && careId.isNotEmpty && !existingUids.contains(careId)) {
          missingUsers[careId] = careName?.isNotEmpty == true ? careName! : 'Caretaker';
        }

        final vetRescuerId = data['pendingVetRescuerId']?.toString() ?? data['lastVetRescuerId']?.toString();
        final vetRescuerName = data['pendingVetRescuerName']?.toString() ?? data['lastVetRescuerName']?.toString();
        if (vetRescuerId != null && vetRescuerId.isNotEmpty && !existingUids.contains(vetRescuerId)) {
          missingUsers[vetRescuerId] = vetRescuerName?.isNotEmpty == true ? vetRescuerName! : 'Vet Rescuer';
        }

        final rescuerUserIds = data['rescuerUserIds'];
        if (rescuerUserIds is List) {
          for (final rid in rescuerUserIds) {
            final rStr = rid.toString();
            if (rStr.isNotEmpty && !existingUids.contains(rStr)) {
              missingUsers.putIfAbsent(rStr, () => 'Community Rescuer');
            }
          }
        }
      }

      // 4. Batch create missing users so they appear in admin management
      for (final entry in missingUsers.entries) {
        final uid = entry.key;
        final name = entry.value;
        await _firestore.collection('users').doc(uid).set({
          'uid': uid,
          'displayName': name,
          'email': '',
          'role': 'user',
          'xp': 0,
          'totalXp': 0,
          'level': 1,
          'trustScore': 5.0,
          'totalRescues': 0,
          'successfulRescues': 0,
          'completedFosters': 0,
          'activeFosters': 0,
          'checkInRate': 100.0,
          'flagCount': 0,
          'isBanned': false,
          'isSuspended': false,
          'joinedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'lastActive': FieldValue.serverTimestamp(),
          'badges': ['Community Member 🐾'],
        }, SetOptions(merge: true));
        existingUids.add(uid);
      }
    } catch (e) {
      debugPrint('syncMissingUsersFromActivity notice: $e');
    }
  }

  /// Stream all users for admin user management
  Stream<List<UserProfile>> streamAllUsers() {
    return _firestore
        .collection('users')
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => UserProfile.fromFirestore(d))
              .toList();
          list.sort((a, b) =>
              a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
          return list;
        })
        .handleError((e) {
          debugPrint('streamAllUsers error: $e');
          return <UserProfile>[];
        });
  }

  /// Get user count
  Future<int> getUserCount() async {
    final snap = await _firestore.collection('users').count().get();
    return snap.count ?? 0;
  }

  /// Get sighting count
  Future<int> getSightingCount() async {
    final snap = await _firestore.collection('sightings').count().get();
    return snap.count ?? 0;
  }

  /// Get flag count
  Future<int> getFlagCount() async {
    final snap = await _firestore.collection('flags').count().get();
    return snap.count ?? 0;
  }

  /// Admin manually adds or registers a user document into Firestore
  Future<void> adminAddUser({
    required String displayName,
    required String email,
    String role = 'user',
  }) async {
    final sanitizedEmail = email.trim().toLowerCase();
    // Check if user with this email already exists
    final existingSnap = await _firestore
        .collection('users')
        .where('email', isEqualTo: sanitizedEmail)
        .limit(1)
        .get();

    String docId;
    if (existingSnap.docs.isNotEmpty) {
      docId = existingSnap.docs.first.id;
    } else {
      final slug = sanitizedEmail.contains('@') ? sanitizedEmail.split('@').first : sanitizedEmail;
      docId = 'user_${DateTime.now().millisecondsSinceEpoch}_$slug';
    }

    await _firestore.collection('users').doc(docId).set({
      'uid': docId,
      'displayName': displayName.trim(),
      'email': sanitizedEmail,
      'role': role,
      'xp': 0,
      'totalXp': 0,
      'level': 1,
      'trustScore': 5.0,
      'totalRescues': 0,
      'successfulRescues': 0,
      'completedFosters': 0,
      'activeFosters': 0,
      'checkInRate': 100.0,
      'flagCount': 0,
      'isBanned': false,
      'isSuspended': false,
      'joinedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'lastActive': FieldValue.serverTimestamp(),
      'badges': ['Newcomer PawWatcher 🐾'],
    }, SetOptions(merge: true));
  }
}
