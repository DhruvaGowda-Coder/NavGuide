import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path_provider/path_provider.dart';

class GoogleUserProfile {
  final String id;
  final String email;
  final String displayName;
  final String? photoUrl;

  const GoogleUserProfile({
    required this.id,
    required this.email,
    required this.displayName,
    this.photoUrl,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'displayName': displayName,
    'photoUrl': photoUrl,
  };

  factory GoogleUserProfile.fromJson(Map<String, dynamic> json) =>
      GoogleUserProfile(
        id: json['id'] as String? ?? '',
        email: json['email'] as String? ?? '',
        displayName: json['displayName'] as String? ?? 'Rider',
        photoUrl: json['photoUrl'] as String?,
      );
}

class GoogleAuthService extends ChangeNotifier {
  static final GoogleAuthService _instance = GoogleAuthService._internal();
  factory GoogleAuthService() => _instance;
  GoogleAuthService._internal();

  GoogleUserProfile? _currentUser;
  bool _isLoading = false;
  bool _initialized = false;
  String? _lastError;

  GoogleUserProfile? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null && _currentUser!.email.isNotEmpty;
  bool get isLoading => _isLoading;
  String? get lastError => _lastError;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Only a native Google session counts as signed in. Older builds stored a
    // manually entered email locally, which made the UI look authenticated
    // without proving ownership of the account.
    try {
      await GoogleSignIn.instance.initialize(
        serverClientId: '496303044045-252bbfnoaoo32o0rpirj2et0l0gneev1.apps.googleusercontent.com',
      );

      GoogleSignIn.instance.authenticationEvents.listen((event) {
        if (event is GoogleSignInAuthenticationEventSignIn) {
          final account = event.user;
          _currentUser = GoogleUserProfile(
            id: account.id,
            email: account.email.trim().toLowerCase(),
            displayName: account.displayName ?? 'Google Rider',
            photoUrl: account.photoUrl,
          );
          _saveProfile();
          notifyListeners();
        } else if (event is GoogleSignInAuthenticationEventSignOut) {
          _currentUser = null;
          notifyListeners();
        }
      });

      await _loadSavedProfile();
    } catch (e) {
      debugPrint('[GoogleAuthService] Native Google Sign-In init: $e');
    }
  }

  Future<GoogleUserProfile?> signIn() async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();

    try {
      final account = await GoogleSignIn.instance.authenticate();
      _setCurrentUser(account);
      await _saveProfile();
      _isLoading = false;
      notifyListeners();
      return _currentUser;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('[GoogleAuthService] Native Google Sign-In error: $e');
    }

    _isLoading = false;
    notifyListeners();
    return _currentUser;
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    _currentUser = null;
    try {
      await _clearSavedProfile();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _saveProfile() async {
    if (_currentUser == null) return;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final file = File('${docDir.path}/my_google_auth.json');
      await file.writeAsString(jsonEncode(_currentUser!.toJson()));
    } catch (_) {}
  }

  Future<void> _loadSavedProfile() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final file = File('${docDir.path}/my_google_auth.json');
      if (!await file.exists()) return;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final profile = GoogleUserProfile.fromJson(json);
      if (profile.email.trim().isEmpty) return;
      _currentUser = profile;
      notifyListeners();
    } catch (_) {}
  }

  void _setCurrentUser(GoogleSignInAccount account) {
    _currentUser = GoogleUserProfile(
      id: account.id,
      email: account.email.trim().toLowerCase(),
      displayName: account.displayName ?? 'Google Rider',
      photoUrl: account.photoUrl,
    );
    _saveProfile();
    notifyListeners();
  }

  Future<void> _clearSavedProfile() async {
    _currentUser = null;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final file = File('${docDir.path}/my_google_auth.json');
      if (await file.exists()) await file.delete();
    } catch (_) {}
    notifyListeners();
  }
}
