import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class TranslationAndAudio {
  final String translation;
  final Uint8List audioContent;

  TranslationAndAudio({
    required this.translation,
    required this.audioContent,
  });
}

class TranslationService {
  final String functionUrl;
  final http.Client _client = http.Client();
  static Future<User?>? _anonymousSignInFuture;

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

  Future<User?> _ensureAuthenticatedUser() async {
    final existingUser = FirebaseAuth.instance.currentUser;
    if (existingUser != null) {
      debugPrint(
          '[TranslationService] Existing Firebase user: ${existingUser.uid}, email=${existingUser.email}');
      return existingUser;
    }

    if (_anonymousSignInFuture != null) {
      debugPrint('[TranslationService] Reusing in-flight anonymous sign-in.');
      return _anonymousSignInFuture!;
    }

    debugPrint('[TranslationService] Starting anonymous Firebase sign-in.');
    _anonymousSignInFuture = FirebaseAuth.instance
        .signInAnonymously()
        .then((credential) => credential.user)
        .whenComplete(() => _anonymousSignInFuture = null);

    final user = await _anonymousSignInFuture!;
    debugPrint(
        '[TranslationService] Anonymous Firebase user ready: ${user?.uid}, email=${user?.email}');
    return user;
  }

  Future<void> _refreshIdToken() async {
    try {
      final user = await _ensureAuthenticatedUser();
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
    final user = await _ensureAuthenticatedUser();
    if (user == null) {
      debugPrint('TranslationService: No Firebase user available');
      _setLastError('auth_unavailable', 'No Firebase user available');
      return null;
    }

    final now = DateTime.now();
    if (_cachedIdToken == null ||
        now.difference(_idTokenFetchedAt) > const Duration(minutes: 45)) {
      debugPrint(
          '[TranslationService] Fetching fresh Firebase ID token for uid=${user.uid}');
      _cachedIdToken = await user.getIdToken();
      _idTokenFetchedAt = now;
    }

    debugPrint(
        '[TranslationService] Token ready for uid=${user.uid}, length=${(_cachedIdToken ?? '').length}');

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${_cachedIdToken ?? ''}',
    };
    return headers;
  }

  Map<String, dynamic> buildRequestBody({
    required String text,
    required String targetLanguage,
    String? voiceName,
    String ttsProvider = 'narakeet',
    bool isMale = true,
    bool skipTranslation = false,
  }) {
    return {
      'text': text.trim(),
      'targetLanguage': targetLanguage,
      'skipTranslation': skipTranslation,
      'isMale': isMale,
      'voiceName': voiceName,
      'ttsProvider': ttsProvider,
    };
  }

  Future<String?> translateText(
    String text,
    String targetLanguage, {
    String? voiceName,
    String ttsProvider = 'narakeet',
  }) async {
    final input = text.trim();
    if (input.isEmpty || functionUrl.trim().isEmpty) {
      _setLastError('invalid_input', 'Empty input or function URL');
      return null;
    }

    try {
      final headers = await _buildHeaders();
      if (headers == null) return null;

      final requestBody = jsonEncode(buildRequestBody(
        text: input,
        targetLanguage: targetLanguage,
        voiceName: voiceName,
        ttsProvider: ttsProvider,
        isMale: true,
      ));

      final response = await _client
          .post(
            Uri.parse(functionUrl),
            headers: headers,
            body: requestBody,
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode != 200) {
        _setLastError(
            'function_http_error', '${response.statusCode}: ${response.body}');
        return null;
      }

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) {
        _setLastError('invalid_response', 'Unexpected response format');
        return null;
      }

      final errorMessage = body['error']?.toString();
      if (errorMessage != null && errorMessage.isNotEmpty) {
        _setLastError(
            'backend_error', body['details']?.toString() ?? errorMessage);
        return null;
      }

      final translated = body['translation']?.toString();
      if (translated == null || translated.trim().isEmpty) {
        _setLastError(
            'missing_translation', 'No translation in response payload');
        return null;
      }

      _clearLastError();
      return translated.trim();
    } catch (e) {
      _setLastError('exception', e.toString());
      return null;
    }
  }

  Future<Uint8List?> generateTranslation(
    String text,
    String targetLanguage, {
    String? voiceName,
    String ttsProvider = 'narakeet',
    bool skipTranslation = false,
  }) async {
    debugPrint(
        '[TranslationService] Attempting to generate translation for text: "$text", targetLanguage: $targetLanguage, ttsProvider: $ttsProvider, skipTranslation: $skipTranslation');
    _clearLastError();
    final input = text.trim();
    if (input.isEmpty || functionUrl.trim().isEmpty) {
      debugPrint(
          '[TranslationService] Invalid input or function URL. Input empty: ${input.isEmpty}, Function URL empty: ${functionUrl.trim().isEmpty}');
      _setLastError('invalid_input', 'Empty input or function URL');
      return null;
    }

    try {
      final headers = await _buildHeaders();
      if (headers == null) {
        debugPrint('[TranslationService] Failed to build headers.');
        return null;
      }
      debugPrint('[TranslationService] Headers built successfully.');

      final requestBodyMap = buildRequestBody(
        text: input,
        targetLanguage: targetLanguage,
        voiceName: voiceName,
        ttsProvider: ttsProvider,
        isMale: true,
        skipTranslation: skipTranslation,
      );
      final requestBody = jsonEncode(requestBodyMap);
      debugPrint('[TranslationService] Request body: $requestBody');

      final response = await _client
          .post(
            Uri.parse(functionUrl),
            headers: headers,
            body: requestBody,
          )
          .timeout(const Duration(seconds: 45));
      debugPrint(
          '[TranslationService] HTTP response status: ${response.statusCode}');
      debugPrint('[TranslationService] HTTP response body: ${response.body}');

      if (response.statusCode == 401) {
        debugPrint(
            '[TranslationService] Received 401, attempting token refresh.');
        // Token may be stale/invalid after app resume; refresh once and retry.
        _setLastError('auth_unauthorized', response.body);
        await _refreshIdToken();
        final retryHeaders = await _buildHeaders();
        if (retryHeaders == null) {
          debugPrint('TranslationService: Unable to rebuild headers after 401');
          return null;
        }
        debugPrint('[TranslationService] Retrying with refreshed token.');

        final retryResponse = await _client
            .post(
              Uri.parse(functionUrl),
              headers: retryHeaders,
              body: requestBody,
            )
            .timeout(const Duration(seconds: 45));

        debugPrint(
            '[TranslationService] Retry HTTP response status: ${retryResponse.statusCode}');
        debugPrint(
            '[TranslationService] Retry HTTP response body: ${retryResponse.body}');

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

      final errorMessage = body['error']?.toString();
      final errorDetails = body['details']?.toString();
      if (errorMessage != null && errorMessage.isNotEmpty) {
        debugPrint(
            'TranslationService: Backend error response: $errorMessage | $errorDetails');
        _setLastError('backend_error', errorDetails ?? errorMessage);
        return null;
      }

      final offensiveContent = body['offensiveContent'] as bool? ?? false;
      if (offensiveContent) {
        debugPrint('TranslationService: Offensive content filtered.');
        _setLastError('offensive_filtered', 'Offensive content filtered');
        return null;
      }

      final audioBase64 = body['audioContent'] as String?;
      if (audioBase64 == null || audioBase64.isEmpty) {
        debugPrint('TranslationService: No audioContent in response');
        _setLastError(
            'missing_audio', errorDetails ?? 'No audioContent in response');
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

  Future<TranslationAndAudio?> translateAndSynthesize(
    String text,
    String targetLanguage, {
    String? voiceName,
    String ttsProvider = 'narakeet',
    bool skipTranslation = false,
  }) async {
    debugPrint(
        '[TranslationService] Attempting translateAndSynthesize for text: "$text", targetLanguage: $targetLanguage, ttsProvider: $ttsProvider, skipTranslation: $skipTranslation');
    _clearLastError();
    final input = text.trim();
    if (input.isEmpty || functionUrl.trim().isEmpty) {
      debugPrint(
          '[TranslationService] Invalid input or function URL. Input empty: ${input.isEmpty}, Function URL empty: ${functionUrl.trim().isEmpty}');
      _setLastError('invalid_input', 'Empty input or function URL');
      return null;
    }

    try {
      final headers = await _buildHeaders();
      if (headers == null) {
        debugPrint(
            '[TranslationService] Failed to build headers in translateAndSynthesize.');
        return null;
      }
      debugPrint(
          '[TranslationService] Headers built successfully in translateAndSynthesize.');

      final requestBodyMap = buildRequestBody(
        text: input,
        targetLanguage: targetLanguage,
        voiceName: voiceName,
        ttsProvider: ttsProvider,
        isMale: true,
        skipTranslation: skipTranslation,
      );
      final requestBody = jsonEncode(requestBodyMap);
      debugPrint('[TranslationService] Request body: $requestBody');

      final response = await _client
          .post(
            Uri.parse(functionUrl),
            headers: headers,
            body: requestBody,
          )
          .timeout(const Duration(seconds: 45));
      debugPrint(
          '[TranslationService] HTTP response status: ${response.statusCode}');

      if (response.statusCode == 401) {
        debugPrint(
            '[TranslationService] Received 401 in translateAndSynthesize, attempting token refresh.');
        _setLastError('auth_unauthorized', response.body);
        await _refreshIdToken();
        final retryHeaders = await _buildHeaders();
        if (retryHeaders == null) {
          debugPrint('TranslationService: Unable to rebuild headers after 401');
          return null;
        }
        debugPrint(
            '[TranslationService] Retrying translateAndSynthesize with refreshed token.');

        final retryResponse = await _client
            .post(
              Uri.parse(functionUrl),
              headers: retryHeaders,
              body: requestBody,
            )
            .timeout(const Duration(seconds: 45));

        debugPrint(
            '[TranslationService] Retry HTTP response status: ${retryResponse.statusCode}');

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
        final retryTranslation = retryBody['translation']?.toString();
        if (retryAudioBase64 == null || retryAudioBase64.isEmpty) {
          debugPrint('TranslationService: No audioContent in retry response');
          _setLastError('missing_audio', 'No audioContent in retry response');
          return null;
        }
        if (retryTranslation == null || retryTranslation.trim().isEmpty) {
          debugPrint('TranslationService: No translation in retry response');
          _setLastError(
              'missing_translation', 'No translation in retry response');
          return null;
        }

        _clearLastError();
        return TranslationAndAudio(
          translation: retryTranslation.trim(),
          audioContent: base64Decode(retryAudioBase64),
        );
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

      final errorMessage = body['error']?.toString();
      final errorDetails = body['details']?.toString();
      if (errorMessage != null && errorMessage.isNotEmpty) {
        debugPrint(
            'TranslationService: Backend error response: $errorMessage | $errorDetails');
        _setLastError('backend_error', errorDetails ?? errorMessage);
        return null;
      }

      final offensiveContent = body['offensiveContent'] as bool? ?? false;
      if (offensiveContent) {
        debugPrint('TranslationService: Offensive content filtered.');
        _setLastError('offensive_filtered', 'Offensive content filtered');
        return null;
      }

      final audioBase64 = body['audioContent'] as String?;
      final translation = body['translation']?.toString();
      if (audioBase64 == null || audioBase64.isEmpty) {
        debugPrint('TranslationService: No audioContent in response');
        _setLastError(
            'missing_audio', errorDetails ?? 'No audioContent in response');
        return null;
      }
      if (translation == null || translation.trim().isEmpty) {
        debugPrint('TranslationService: No translation in response');
        _setLastError('missing_translation', 'No translation in response');
        return null;
      }

      _clearLastError();
      return TranslationAndAudio(
        translation: translation.trim(),
        audioContent: base64Decode(audioBase64),
      );
    } catch (e) {
      debugPrint('TranslationService: Exception $e');
      _setLastError('exception', e.toString());
      return null;
    }
  }
}
