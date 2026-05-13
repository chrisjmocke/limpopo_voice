import 'dart:convert';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class TranslationService {
  final String functionUrl;
  final http.Client _client = http.Client();

  String? _cachedIdToken;
  DateTime _idTokenFetchedAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _cachedAppCheckToken;
  DateTime _appCheckFetchedAt = DateTime.fromMillisecondsSinceEpoch(0);

  TranslationService({required this.functionUrl});

  Future<void> _refreshIdToken() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      user ??= (await FirebaseAuth.instance.signInAnonymously()).user;
      if (user == null) return;
      _cachedIdToken = await user.getIdToken(true);
      _idTokenFetchedAt = DateTime.now();
    } catch (e) {
      debugPrint('TranslationService: Token refresh failed: $e');
    }
  }

  Future<void> primeSession() async {
    try {
      await _buildHeaders();
    } catch (_) {
      // Best-effort warmup only.
    }
  }

  Future<Map<String, String>?> _buildHeaders() async {
    User? user = FirebaseAuth.instance.currentUser;
    user ??= (await FirebaseAuth.instance.signInAnonymously()).user;
    if (user == null) {
      debugPrint('TranslationService: No Firebase user available');
      return null;
    }

    final now = DateTime.now();
    if (_cachedIdToken == null ||
        now.difference(_idTokenFetchedAt) > const Duration(minutes: 45)) {
      _cachedIdToken = await user.getIdToken();
      _idTokenFetchedAt = now;
    }

    if (_cachedAppCheckToken == null ||
        now.difference(_appCheckFetchedAt) > const Duration(minutes: 8)) {
      try {
        // Do not force refresh every call; this significantly reduces TTS latency.
        _cachedAppCheckToken = await FirebaseAppCheck.instance.getToken(false);
      } catch (e) {
        // Some older/unsupported devices fail App Check token retrieval.
        debugPrint('TranslationService: App Check token unavailable: $e');
      } finally {
        _appCheckFetchedAt = now;
      }
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${_cachedIdToken ?? ''}',
    };
    if (_cachedAppCheckToken != null && _cachedAppCheckToken!.isNotEmpty) {
      headers['X-Firebase-AppCheck'] = _cachedAppCheckToken!;
    }
    return headers;
  }

  Future<Uint8List?> generateTranslation(
    String text,
    String targetLanguage, {
    String? voiceName,
  }) async {
    final input = text.trim();
    if (input.isEmpty || functionUrl.trim().isEmpty) {
      return null;
    }

    try {
      final headers = await _buildHeaders();
      if (headers == null) {
        return null;
      }

      final response = await _client.post(
        Uri.parse(functionUrl),
        headers: headers,
        body: jsonEncode({
          'text': input,
          'targetLanguage': targetLanguage,
          'skipTranslation': true,
          'isMale': true,
          'voiceName': voiceName,
          'ttsProvider': 'narakeet',
        }),
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 401) {
        // Token may be stale/invalid after app resume; refresh once and retry.
        await _refreshIdToken();
        final retryHeaders = await _buildHeaders();
        if (retryHeaders == null) {
          debugPrint('TranslationService: Unable to rebuild headers after 401');
          return null;
        }

        final retryResponse = await _client.post(
          Uri.parse(functionUrl),
          headers: retryHeaders,
          body: jsonEncode({
            'text': input,
            'targetLanguage': targetLanguage,
            'skipTranslation': true,
            'isMale': true,
            'voiceName': voiceName,
            'ttsProvider': 'narakeet',
          }),
        ).timeout(const Duration(seconds: 45));

        if (retryResponse.statusCode != 200) {
          debugPrint(
              'TranslationService: Function error ${retryResponse.statusCode} ${retryResponse.body}');
          return null;
        }

        final retryBody = jsonDecode(retryResponse.body);
        if (retryBody is! Map<String, dynamic>) {
          debugPrint('TranslationService: Unexpected retry response format');
          return null;
        }

        final retryAudioBase64 = retryBody['audioContent'] as String?;
        if (retryAudioBase64 == null || retryAudioBase64.isEmpty) {
          debugPrint('TranslationService: No audioContent in retry response');
          return null;
        }

        return base64Decode(retryAudioBase64);
      }

      if (response.statusCode != 200) {
        debugPrint(
            'TranslationService: Function error ${response.statusCode} ${response.body}');
        return null;
      }

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) {
        debugPrint('TranslationService: Unexpected response format');
        return null;
      }

      final audioBase64 = body['audioContent'] as String?;
      if (audioBase64 == null || audioBase64.isEmpty) {
        debugPrint('TranslationService: No audioContent in response');
        return null;
      }

      return base64Decode(audioBase64);
    } catch (e) {
      debugPrint('TranslationService: Exception $e');
      return null;
    }
  }
}
