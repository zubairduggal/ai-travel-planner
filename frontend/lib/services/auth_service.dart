import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Identifies how the current user signed in (used for re-authentication).
enum AuthProviderType {
  guest,
  emailPassword,
  google,
  apple,
}

/// Lightweight immutable representation of an authenticated user.
@immutable
class AuthUser {
  const AuthUser({
    required this.uid,
    required this.providerType,
    this.email,
    this.displayName,
  });

  final String uid;
  final AuthProviderType providerType;
  final String? email;
  final String? displayName;
}

/// Standardized authentication error mapped from Firebase / Google / Apple SDKs.
class AuthException implements Exception {
  const AuthException({
    required this.code,
    required this.message,
  });

  final String code;
  final String message;

  bool get requiresRecentLogin => code == 'requires-recent-login';
  bool get isCancelled => code == 'cancelled';

  @override
  String toString() => 'AuthException($code): $message';
}

/// Authentication service contract (MFR-01, MFR-02, MFR-03).
abstract class AuthService {
  bool get isFirebaseReady;
  AuthUser? get currentUser;
  Stream<AuthUser?> get authStateChanges;

  Future<AuthUser> signInWithEmail({
    required String email,
    required String password,
  });

  Future<AuthUser> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  });

  Future<AuthUser> signInWithGoogle();

  Future<AuthUser> signInWithApple();

  Future<void> signOut();

  Future<void> reauthenticateWithPassword(String password);

  Future<void> reauthenticateWithGoogle();

  Future<void> reauthenticateWithApple();

  Future<void> deleteAccount();
}

/// Production Firebase Auth implementation supporting Email, Google v7+, and Apple.
class FirebaseAuthService implements AuthService {
  FirebaseAuthService({
    String? googleServerClientId,
  }) : _googleServerClientId = googleServerClientId ??
            const String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  final String _googleServerClientId;
  bool _googleInitialized = false;

  @override
  bool get isFirebaseReady => Firebase.apps.isNotEmpty;

  FirebaseAuth _requireAuth() {
    if (!isFirebaseReady) {
      throw const AuthException(
        code: 'firebase-not-configured',
        message:
            'Firebase is not configured for this build yet. Add '
            'google-services.json / GoogleService-Info.plist or continue in Guest Mode.',
      );
    }
    return FirebaseAuth.instance;
  }

  @override
  AuthUser? get currentUser {
    if (!isFirebaseReady) return null;
    final user = FirebaseAuth.instance.currentUser;
    return user == null ? null : _mapFirebaseUser(user);
  }

  @override
  Stream<AuthUser?> get authStateChanges {
    if (!isFirebaseReady) {
      return const Stream<AuthUser?>.empty();
    }
    return FirebaseAuth.instance.authStateChanges().map(
          (user) => user == null ? null : _mapFirebaseUser(user),
        );
  }

  AuthUser _mapFirebaseUser(User user) {
    final providerIds = user.providerData.map((p) => p.providerId).toSet();
    final AuthProviderType type;
    if (providerIds.contains('google.com')) {
      type = AuthProviderType.google;
    } else if (providerIds.contains('apple.com')) {
      type = AuthProviderType.apple;
    } else {
      type = AuthProviderType.emailPassword;
    }

    return AuthUser(
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
      providerType: type,
    );
  }

  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    await GoogleSignIn.instance.initialize(
      serverClientId:
          _googleServerClientId.isEmpty ? null : _googleServerClientId,
    );
    _googleInitialized = true;
  }

  Future<OAuthCredential> _obtainGoogleCredential() async {
    await _ensureGoogleInitialized();
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw const AuthException(
        code: 'unsupported-platform',
        message: 'Google Sign-In is not supported on this platform.',
      );
    }
    try {
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      final authz = await account.authorizationClient.authorizationForScopes(
        const ['email', 'profile'],
      );
      if (idToken == null && authz?.accessToken == null) {
        throw const AuthException(
          code: 'missing-google-token',
          message: 'Google Sign-In did not return a valid authentication token.',
        );
      }
      return GoogleAuthProvider.credential(
        idToken: idToken,
        accessToken: authz?.accessToken,
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthException(
          code: 'cancelled',
          message: 'Google Sign-In was cancelled.',
        );
      }
      throw AuthException(
        code: 'google-sign-in-failed',
        message: e.description ?? 'Google Sign-In failed. Please try again.',
      );
    }
  }

  AuthException _mapFirebaseException(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return const AuthException(
          code: 'invalid-email',
          message: 'Please enter a valid email address.',
        );
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return const AuthException(
          code: 'invalid-credential',
          message: 'Incorrect email or password. Please check and try again.',
        );
      case 'email-already-in-use':
        return const AuthException(
          code: 'email-already-in-use',
          message: 'An account already exists with this email. Try signing in.',
        );
      case 'weak-password':
        return const AuthException(
          code: 'weak-password',
          message: 'Password is too weak. Use at least 6 characters.',
        );
      case 'requires-recent-login':
        return const AuthException(
          code: 'requires-recent-login',
          message:
              'For your security, please verify your sign-in before deleting your account.',
        );
      case 'network-request-failed':
        return const AuthException(
          code: 'network-request-failed',
          message: 'No internet connection. Check your network and try again.',
        );
      case 'too-many-requests':
        return const AuthException(
          code: 'too-many-requests',
          message: 'Too many attempts. Please wait a moment and try again.',
        );
      default:
        return AuthException(
          code: e.code,
          message: e.message ?? 'Authentication failed. Please try again.',
        );
    }
  }

  @override
  Future<AuthUser> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final auth = _requireAuth();
    try {
      final cred = await auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = cred.user;
      if (user == null) {
        throw const AuthException(
          code: 'no-user',
          message: 'Unable to sign in right now.',
        );
      }
      return _mapFirebaseUser(user);
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseException(e);
    }
  }

  @override
  Future<AuthUser> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final auth = _requireAuth();
    try {
      final cred = await auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = cred.user;
      if (user == null) {
        throw const AuthException(
          code: 'no-user',
          message: 'Unable to create your account right now.',
        );
      }
      final trimmedName = displayName?.trim();
      if (trimmedName != null && trimmedName.isNotEmpty) {
        await user.updateDisplayName(trimmedName);
        await user.reload();
      }
      return _mapFirebaseUser(auth.currentUser ?? user);
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseException(e);
    }
  }

  @override
  Future<AuthUser> signInWithGoogle() async {
    final auth = _requireAuth();
    try {
      final credential = await _obtainGoogleCredential();
      final userCred = await auth.signInWithCredential(credential);
      final user = userCred.user;
      if (user == null) {
        throw const AuthException(
          code: 'no-user',
          message: 'Google Sign-In failed to create a session.',
        );
      }
      return _mapFirebaseUser(user);
    } on AuthException {
      rethrow;
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseException(e);
    }
  }

  @override
  Future<AuthUser> signInWithApple() async {
    final auth = _requireAuth();
    try {
      final provider = AppleAuthProvider()
        ..addScope('email')
        ..addScope('name');
      final userCred = await auth.signInWithProvider(provider);
      final user = userCred.user;
      if (user == null) {
        throw const AuthException(
          code: 'no-user',
          message: 'Sign in with Apple failed to create a session.',
        );
      }
      return _mapFirebaseUser(user);
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseException(e);
    }
  }

  @override
  Future<void> signOut() async {
    if (!isFirebaseReady) return;
    if (_googleInitialized) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
    await FirebaseAuth.instance.signOut();
  }

  @override
  Future<void> reauthenticateWithPassword(String password) async {
    final auth = _requireAuth();
    final user = auth.currentUser;
    if (user == null || user.email == null) {
      throw const AuthException(
        code: 'no-user',
        message: 'No active email account to re-authenticate.',
      );
    }
    try {
      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(cred);
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseException(e);
    }
  }

  @override
  Future<void> reauthenticateWithGoogle() async {
    final auth = _requireAuth();
    final user = auth.currentUser;
    if (user == null) {
      throw const AuthException(
        code: 'no-user',
        message: 'No active Google account to re-authenticate.',
      );
    }
    try {
      final cred = await _obtainGoogleCredential();
      await user.reauthenticateWithCredential(cred);
    } on AuthException {
      rethrow;
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseException(e);
    }
  }

  @override
  Future<void> reauthenticateWithApple() async {
    final auth = _requireAuth();
    final user = auth.currentUser;
    if (user == null) {
      throw const AuthException(
        code: 'no-user',
        message: 'No active Apple account to re-authenticate.',
      );
    }
    try {
      final provider = AppleAuthProvider()
        ..addScope('email')
        ..addScope('name');
      await user.reauthenticateWithProvider(provider);
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseException(e);
    }
  }

  @override
  Future<void> deleteAccount() async {
    final auth = _requireAuth();
    final user = auth.currentUser;
    if (user == null) return;
    try {
      await user.delete();
      if (_googleInitialized) {
        try {
          await GoogleSignIn.instance.signOut();
        } catch (_) {}
      }
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseException(e);
    }
  }
}
