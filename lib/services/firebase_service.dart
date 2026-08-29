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

    final category = _determineCategory(description, urgency);
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
      category: category,
      createdAt: now,
      commentCount: 0,
      upvotes: 0,
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
