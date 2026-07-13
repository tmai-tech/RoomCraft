import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/room_model.dart';
import 'storage_service.dart';

/// Optional Google Sign-In + Firestore backup for room plans.
///
/// Best-effort: fails gracefully when Firebase / SHA config is incomplete.
class CloudSyncService {
  CloudSyncService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    GoogleSignIn? googleSignIn,
    StorageService? storage,
  })  : _auth = auth,
        _firestore = firestore,
        _googleSignIn = googleSignIn ?? GoogleSignIn(),
        _storage = storage ?? StorageService();

  FirebaseAuth? _auth;
  FirebaseFirestore? _firestore;
  final GoogleSignIn _googleSignIn;
  final StorageService _storage;

  bool _ready = false;

  User? get currentUser => _auth?.currentUser;
  bool get isSignedIn => currentUser != null;

  Future<bool> ensureReady() async {
    if (_ready) return true;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _auth ??= FirebaseAuth.instance;
      _firestore ??= FirebaseFirestore.instance;
      _ready = true;
      return true;
    } catch (e) {
      debugPrint('CloudSync init failed: $e');
      return false;
    }
  }

  Future<User?> signInWithGoogle() async {
    if (!await ensureReady()) {
      throw Exception(
        'Firebase not configured on this device. Check google-services.json / SHA fingerprints.',
      );
    }
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null; // cancelled
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final cred = await _auth!.signInWithCredential(credential);
    return cred.user;
  }

  Future<void> signOut() async {
    await ensureReady();
    await _googleSignIn.signOut();
    await _auth?.signOut();
  }

  CollectionReference<Map<String, dynamic>> _roomsCol(String uid) {
    return _firestore!.collection('users').doc(uid).collection('rooms');
  }

  /// Upload all local rooms to Firestore under the signed-in user.
  Future<int> backupAllLocalRooms() async {
    if (!await ensureReady()) throw Exception('Firebase unavailable');
    final user = _auth?.currentUser;
    if (user == null) throw Exception('Sign in first');

    final rooms = await _storage.loadRooms();
    final batch = _firestore!.batch();
    for (final room in rooms) {
      room.userId = user.uid;
      final ref = _roomsCol(user.uid).doc(room.id);
      batch.set(ref, room.toMap(), SetOptions(merge: true));
    }
    await batch.commit();
    return rooms.length;
  }

  /// Pull cloud rooms and merge into local storage (cloud wins on same id).
  Future<int> restoreFromCloud() async {
    if (!await ensureReady()) throw Exception('Firebase unavailable');
    final user = _auth?.currentUser;
    if (user == null) throw Exception('Sign in first');

    final snap = await _roomsCol(user.uid).get();
    var count = 0;
    for (final doc in snap.docs) {
      final room = RoomModel.tryFromMap(doc.data());
      if (room == null) continue;
      room.userId = user.uid;
      await _storage.saveRoom(room);
      count++;
    }
    return count;
  }
}
