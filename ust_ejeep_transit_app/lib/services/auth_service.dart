import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;

import '../models/models.dart';

/// Service wrapping Firebase Authentication for both driver (email/password)
/// and student (anonymous) sign-in flows.
///
/// All methods return [AuthResult] variants ([AuthSuccess] / [AuthFailure])
/// rather than throwing, so callers can use exhaustive pattern matching
/// without try/catch boilerplate.
class AuthService {
  /// The underlying Firebase Auth instance.
  /// Exposed as a field so it can be overridden in tests.
  final firebase_auth.FirebaseAuth _firebaseAuth;

  /// The Firestore instance used to fetch driver profiles.
  /// Exposed as a field so it can be overridden in tests.
  final FirebaseFirestore _firestore;

  /// Creates an [AuthService].
  ///
  /// [firebaseAuth] defaults to [firebase_auth.FirebaseAuth.instance] and can
  /// be injected for testing.
  /// [firestore] defaults to [FirebaseFirestore.instance] and can be injected
  /// for testing.
  AuthService({
    firebase_auth.FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
  })  : _firebaseAuth = firebaseAuth ?? firebase_auth.FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  // ---------------------------------------------------------------------------
  // Driver sign-in
  // ---------------------------------------------------------------------------

  /// Signs in a driver using email and password, then fetches the driver's
  /// Firestore profile to populate [User.displayName] and [User.routeId].
  ///
  /// Returns [AuthSuccess] with [UserRole.driver] on success.
  /// Returns [AuthFailure] with:
  /// - `MISSING_CREDENTIALS` if [email] or [password] is empty.
  /// - `ACCOUNT_NOT_PROVISIONED` if no Firestore document exists at
  ///   `/drivers/{uid}`.
  /// - `PROFILE_FETCH_ERROR` on any Firestore error.
  /// - The Firebase error code on [firebase_auth.FirebaseAuthException].
  /// - `UNKNOWN_ERROR` for any other exception.
  Future<AuthResult> signInDriver(String email, String password) async {
    // Guard: reject empty credentials before hitting Firebase.
    if (email.trim().isEmpty || password.isEmpty) {
      return const AuthFailure(
        errorCode: 'MISSING_CREDENTIALS',
        message: 'Email and password are required.',
      );
    }

    // ── Step 1: Firebase Auth sign-in ──────────────────────────────────────
    firebase_auth.UserCredential credential;
    try {
      credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on firebase_auth.FirebaseAuthException catch (e) {
      return AuthFailure(
        errorCode: e.code,
        message: e.message ?? 'Authentication failed.',
      );
    } catch (e) {
      return AuthFailure(
        errorCode: 'UNKNOWN_ERROR',
        message: e.toString(),
      );
    }

    final firebaseUser = credential.user!;

    // ── Step 2: Fetch Firestore driver profile ─────────────────────────────
    DocumentSnapshot<Map<String, dynamic>> doc;
    try {
      doc = await _firestore
          .collection('drivers')
          .doc(firebaseUser.uid)
          .get();
    } catch (e) {
      // Clean up the auth session so the user is not left in a half-signed-in
      // state when the profile cannot be fetched.
      await _firebaseAuth.signOut();
      return AuthFailure(
        errorCode: 'PROFILE_FETCH_ERROR',
        message: e.toString(),
      );
    }

    // ── Step 3: Guard — account must be provisioned in Firestore ──────────
    if (!doc.exists) {
      // Sign out to avoid leaving the user in a partially authenticated state.
      await _firebaseAuth.signOut();
      return const AuthFailure(
        errorCode: 'ACCOUNT_NOT_PROVISIONED',
        message:
            'Your driver account has not been set up. '
            'Please contact the UST transport office.',
      );
    }

    // ── Step 4: Build User from Firestore data ─────────────────────────────
    final data = doc.data()!;
    final token = await firebaseUser.getIdToken() ?? '';

    final user = User(
      uid: firebaseUser.uid,
      email: firebaseUser.email,
      displayName: data['displayName'] as String?,
      role: UserRole.driver,
      routeId: data['routeId'] as String?,
    );

    return AuthSuccess(user: user, token: token);
  }

  // ---------------------------------------------------------------------------
  // Student (anonymous) sign-in
  // ---------------------------------------------------------------------------

  /// Signs in a student anonymously.
  ///
  /// Returns [AuthSuccess] with [UserRole.anonymous] on success.
  /// Returns [AuthFailure] with the Firebase error code on
  /// [firebase_auth.FirebaseAuthException], or `UNKNOWN_ERROR` otherwise.
  Future<AuthResult> signInStudentAnonymously() async {
    try {
      final credential = await _firebaseAuth.signInAnonymously();

      final firebaseUser = credential.user!;
      final token = await firebaseUser.getIdToken() ?? '';

      final user = User(
        uid: firebaseUser.uid,
        role: UserRole.anonymous,
      );

      return AuthSuccess(user: user, token: token);
    } on firebase_auth.FirebaseAuthException catch (e) {
      return AuthFailure(
        errorCode: e.code,
        message: e.message ?? 'Authentication failed.',
      );
    } catch (e) {
      return AuthFailure(
        errorCode: 'UNKNOWN_ERROR',
        message: e.toString(),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Sign-out
  // ---------------------------------------------------------------------------

  /// Signs out the currently authenticated user (driver or student).
  Future<void> signOut() async {
    await _firebaseAuth.signOut();
  }

  // ---------------------------------------------------------------------------
  // Current user helpers
  // ---------------------------------------------------------------------------

  /// Returns the currently signed-in [User], or `null` if no session exists.
  ///
  /// Role is inferred from the Firebase user:
  /// - Anonymous Firebase users → [UserRole.anonymous]
  /// - Email/password Firebase users → [UserRole.driver]
  ///
  /// Note: [User.displayName] and [User.routeId] are not populated here
  /// because they require a Firestore round-trip. Use [signInDriver] to
  /// obtain a fully-populated [User].
  User? getCurrentUser() {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) return null;

    final role =
        firebaseUser.isAnonymous ? UserRole.anonymous : UserRole.driver;

    return User(
      uid: firebaseUser.uid,
      email: firebaseUser.email,
      displayName: firebaseUser.displayName,
      role: role,
    );
  }

  /// Returns `true` if [user] has the [UserRole.driver] role.
  bool isDriver(User user) => user.role == UserRole.driver;

  // ---------------------------------------------------------------------------
  // Auth state stream
  // ---------------------------------------------------------------------------

  /// A stream that emits the current Firebase user whenever the authentication
  /// state changes (sign-in, sign-out, token refresh).
  ///
  /// Emits `null` when no user is signed in.
  /// Consumers can map this to [getCurrentUser] to obtain the app-level [User].
  Stream<firebase_auth.User?> get authStateChanges =>
      _firebaseAuth.authStateChanges();
}
