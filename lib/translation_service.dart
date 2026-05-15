import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class TranslationService {
  final String functionUrl;
  final http.Client _client = http.Client();

  String? _lastErrorCode;
  String? _lastErrorDetails;

  String? _cachedIdToken;
  DateTime _idTokenFetchedAt = DateTime.fromMillisecondsSinceEpoch(0);

  String? get lastErrorCode => _lastErrorCode;
  String? get lastErrorDetails => _lastErrorDetails;

  TranslationService({required this.functionUrl});

  void _setLastError(String code, [String? details]) {
    _lastErrorCode = code;
    _lastErrorDetails = details;
  }

  void _clearLastError() {
    _lastErrorCode = null;
    _lastErrorDetails = null;
  }

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
      _setLastError('auth_unavailable', 'No Firebase user available');
      return null;
    }

    final now = DateTime.now();
    if (_cachedIdToken == null ||
        now.difference(_idTokenFetchedAt) > const Duration(minutes: 45)) {
      _cachedIdToken = await user.getIdToken();
      _idTokenFetchedAt = now;
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${_cachedIdToken ?? ''}',
    };
    return headers;
  }

  Future<Uint8List?> generateTranslation(
    String text,
    String targetLanguage, {
    String? voiceName,
    String ttsProvider = 'narakeet',
  }) async {
    _clearLastError();
    final input = text.trim();
    if (input.isEmpty || functionUrl.trim().isEmpty) {
      _setLastError('invalid_input', 'Empty input or function URL');
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
          'ttsProvider': ttsProvider,
        }),
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 401) {
        // Token may be stale/invalid after app resume; refresh once and retry.
        _setLastError('auth_unauthorized', response.body);
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
            'ttsProvider': ttsProvider,
          }),
        ).timeout(const Duration(seconds: 45));

        if (retryResponse.statusCode != 200) {
          debugPrint(
              'TranslationService: Function error ${retryResponse.statusCode} ${retryResponse.body}');
          _setLastError('function_http_error',
              '${retryResponse.statusCode}: ${retryResponse.body}');
          return null;
        }

        final retryBody = jsonDecode(retryResponse.body);
        if (retryBody is! Map<String, dynamic>) {
          debugPrint('TranslationService: Unexpected retry response format');
          _setLastError('invalid_response', 'Unexpected retry response format');
          return null;
        }

        final retryAudioBase64 = retryBody['audioContent'] as String?;
        if (retryAudioBase64 == null || retryAudioBase64.isEmpty) {
          debugPrint('TranslationService: No audioContent in retry response');
          _setLastError('missing_audio', 'No audioContent in retry response');
          return null;
        }

        _clearLastError();
        return base64Decode(retryAudioBase64);
      }

      if (response.statusCode != 200) {
        debugPrint(
            'TranslationService: Function error ${response.statusCode} ${response.body}');
        _setLastError(
            'function_http_error', '${response.statusCode}: ${response.body}');
        return null;
      }

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) {
        debugPrint('TranslationService: Unexpected response format');
        _setLastError('invalid_response', 'Unexpected response format');
        return null;
      }

      final offensiveContent = body['offensiveContent'] as bool? ?? false;
      if (offensiveContent) {
        _setLastError('offensive_filtered', 'Offensive content filtered');
        return null;
      }

      final audioBase64 = body['audioContent'] as String?;
      if (audioBase64 == null || audioBase64.isEmpty) {
        debugPrint('TranslationService: No audioContent in response');
        _setLastError('missing_audio', 'No audioContent in response');
        return null;
      }

      _clearLastError();
      return base64Decode(audioBase64);
    } catch (e) {
      debugPrint('TranslationService: Exception $e');
      _setLastError('exception', e.toString());
      return null;
    }
  }
}
