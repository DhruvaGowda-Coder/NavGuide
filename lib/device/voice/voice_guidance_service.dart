import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class VoiceGuidanceService {
  VoiceGuidanceService() {
    _initTts();
  }

  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;
  bool _isMuted = false;

  String? _lastSpokenText;
  DateTime? _lastSpokenTime;

  bool get isMuted => _isMuted;

  /// Pronunciation and phonetics normalizer for Indian roads, addresses, and landmarks
  static String normalizePronunciation(String text) {
    var s = text;
    // 1. Remove parenthetical descriptions, e.g. "(Heritage Dosa)" -> ""
    s = s.replaceAll(RegExp(r'\([^)]*\)'), ' ');

    // 2. Expand common Indian road and address abbreviations
    s = s.replaceAll(RegExp(r'\bRd\.?\b', caseSensitive: false), 'Road');
    s = s.replaceAll(RegExp(r'\bSt\.?\b', caseSensitive: false), 'Street');
    s = s.replaceAll(RegExp(r'\bHwy\.?\b', caseSensitive: false), 'Highway');
    s = s.replaceAllMapped(RegExp(r'\bNH\s*[-]?\s*(\d+)', caseSensitive: false), (m) => 'National Highway ${m[1]}');
    s = s.replaceAllMapped(RegExp(r'\bSH\s*[-]?\s*(\d+)', caseSensitive: false), (m) => 'State Highway ${m[1]}');
    s = s.replaceAll(RegExp(r'\bOpp\.?\b', caseSensitive: false), 'opposite');
    s = s.replaceAll(RegExp(r'\bNr\.?\b', caseSensitive: false), 'near');
    s = s.replaceAll(RegExp(r'\bBldg\.?\b', caseSensitive: false), 'building');
    s = s.replaceAll(RegExp(r'\bApts?\.?\b', caseSensitive: false), 'Apartments');
    s = s.replaceAll(RegExp(r'\bJn\.?\b', caseSensitive: false), 'Junction');
    s = s.replaceAll(RegExp(r'\bSq\.?\b', caseSensitive: false), 'Square');
    s = s.replaceAll(RegExp(r'\bMTR\b'), 'M T R');
    s = s.replaceAll(RegExp(r'\bBLR\b', caseSensitive: false), 'Bangalore');

    // 3. Clean symbols that cause TTS to read literal words like "slash", "hash", "hyphen"
    s = s.replaceAll(RegExp(r'[/\\#_~|@*]'), ' ');
    s = s.replaceAll(RegExp(r'[-–—]'), ' ');

    // 4. Collapse extra spaces
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  Future<void> _initTts() async {
    try {
      await _flutterTts.setLanguage('en-IN');

      // Select natural Indian English voice if available on device
      final voices = await _flutterTts.getVoices;
      if (voices is List) {
        for (final v in voices) {
          if (v is Map) {
            final locale = v['locale']?.toString() ?? '';
            if (locale == 'en-IN' || locale.startsWith('en_IN')) {
              await _flutterTts.setVoice({
                'name': v['name'],
                'locale': v['locale'],
              });
              break;
            }
          }
        }
      }

      // 0.48 speech rate gives a relaxed, crystal-clear Indian English pace
      await _flutterTts.setSpeechRate(0.48);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      _isInitialized = true;
    } catch (e) {
      debugPrint('VoiceGuidanceService: Init error: $e');
    }
  }

  void toggleMute() {
    _isMuted = !_isMuted;
    if (_isMuted) {
      stop();
    } else {
      speak('Voice navigation enabled');
    }
  }

  void setMuted(bool mute) {
    _isMuted = mute;
    if (_isMuted) {
      stop();
    }
  }

  Future<void> speak(String text, {bool force = false}) async {
    if (_isMuted) return;
    if (!_isInitialized) await _initTts();

    final cleanText = normalizePronunciation(text);
    if (cleanText.isEmpty) return;

    final now = DateTime.now();
    // Debounce identical instructions unless forced
    if (!force &&
        _lastSpokenText == cleanText &&
        _lastSpokenTime != null &&
        now.difference(_lastSpokenTime!).inSeconds < 7) {
      return;
    }

    _lastSpokenText = cleanText;
    _lastSpokenTime = now;

    try {
      await _flutterTts.stop();
      await _flutterTts.speak(cleanText);
    } catch (e) {
      debugPrint('VoiceGuidanceService: Speak error: $e');
    }
  }

  Future<void> speakNavigationStart(String destinationName) async {
    final cleanDest = normalizePronunciation(destinationName);
    await speak('Starting navigation to $cleanDest. Drive safely.', force: true);
  }

  Future<void> speakManeuver({
    required String instruction,
    required double distanceMeters,
  }) async {
    if (_isMuted) return;

    String spokenPhrase;
    if (distanceMeters <= 50) {
      spokenPhrase = '$instruction now.';
    } else if (distanceMeters < 120) {
      spokenPhrase = 'In 100 meters, $instruction.';
    } else if (distanceMeters < 280) {
      spokenPhrase = 'In 200 meters, $instruction.';
    } else if (distanceMeters < 400) {
      spokenPhrase = 'In 300 meters, $instruction.';
    } else if (distanceMeters < 650) {
      spokenPhrase = 'In 500 meters, $instruction.';
    } else {
      final km = (distanceMeters / 1000).toStringAsFixed(1);
      spokenPhrase = 'In $km kilometers, $instruction.';
    }

    await speak(spokenPhrase);
  }

  Future<void> speakHazard({
    required String hazardType,
    required double distanceMeters,
  }) async {
    if (_isMuted) return;
    final dist = (distanceMeters / 10).round() * 10;
    final cleanType = normalizePronunciation(hazardType);
    await speak('Caution. $cleanType reported $dist meters ahead.', force: true);
  }

  Future<void> speakArrival(String destinationName) async {
    final cleanDest = normalizePronunciation(destinationName);
    await speak('You have arrived at your destination: $cleanDest.', force: true);
  }

  Future<void> stop() async {
    try {
      await _flutterTts.stop();
    } catch (_) {}
  }

  void dispose() {
    stop();
  }
}
