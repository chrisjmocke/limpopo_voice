import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' show min;
import 'dart:async';
import 'package:http/http.dart' as http;

class TranslationService {
  final String apiKey;
  final String baseUrl = 'https://api.narakeet.com';

  TranslationService({required this.apiKey});

  /// Generates the audio translation from a text string.
  /// Narakeet API is asynchronous: POST submits job, then poll statusUrl for result.
  Future<Uint8List?> generateTranslation(String text, String voiceName) async {
    final endpoint = '$baseUrl/text-to-speech/mp3?voice=$voiceName';
    final url = Uri.parse(endpoint);

    try {
      print('TranslationService: POST $endpoint (voice=$voiceName)');

      final response = await http.post(
        url,
        headers: {
          'x-api-key': apiKey,
          'Content-Type': 'text/plain',
          'Accept': 'application/json',
        },
        body: utf8.encode(text),
      );

      print('TranslationService: Submit status: ${response.statusCode}');

      if (response.statusCode != 200) {
        print('API Error: ${response.statusCode} - ${response.body.substring(0, min(200, response.body.length))}');
        return null;
      }

      final jsonResponse = jsonDecode(response.body);
      final statusUrl = jsonResponse['statusUrl'] as String?;
      final taskId = jsonResponse['taskId'] as String?;

      if (statusUrl == null || taskId == null) {
        print('TranslationService: Missing taskId or statusUrl in response');
        return null;
      }

      print('TranslationService: Task ID: $taskId — polling...');
      return await _pollForAudio(statusUrl, taskId);
    } catch (e) {
      print('TranslationService: Submit error: $e');
      return null;
    }
  }

  bool _isMp3(Uint8List bytes) {
    if (bytes.isEmpty) return false;
    // ID3 header
    if (bytes.length > 2 && bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) return true;
    // MPEG sync word
    if (bytes.length > 1 && bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) return true;
    return false;
  }

  /// Poll the status URL until the audio is ready.
  /// statusUrl is a pre-signed S3 URL — no auth header needed.
  Future<Uint8List?> _pollForAudio(String statusUrl, String taskId, {int maxAttempts = 40}) async {
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final waitMs = attempt < 8 ? 250 : 500;
      await Future.delayed(Duration(milliseconds: waitMs));
      try {
        final response = await http.get(Uri.parse(statusUrl));
        final ct = response.headers['content-type'] ?? '';
        final bodyPreview = response.body.length > 300
            ? response.body.substring(0, 300)
            : response.body;
        print('TranslationService: Poll ${attempt + 1}/$maxAttempts — '
            'HTTP ${response.statusCode}, bytes: ${response.bodyBytes.length}, '
            'ct: $ct, body: $bodyPreview');

        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          // Check content-type for audio
          if (ct.contains('audio') || ct.contains('mpeg') || ct.contains('octet-stream')) {
            if (_isMp3(response.bodyBytes)) {
              print('TranslationService: Audio ready via content-type! ${response.bodyBytes.length} bytes');
              return response.bodyBytes;
            }
          }

          // Check raw bytes for MP3 magic
          if (_isMp3(response.bodyBytes)) {
            print('TranslationService: Audio ready via magic bytes! ${response.bodyBytes.length} bytes');
            return response.bodyBytes;
          }

          // Narakeet status payload uses finished/percent and returns the final MP3 URL in result.
          try {
            final json = jsonDecode(response.body);
            if (json is Map) {
              final finished = json['finished'] == true;
              final succeeded = json['succeeded'] == true;
              final percent = json['percent'];
              final message = json['message']?.toString() ?? '';

              print('TranslationService: JSON finished=$finished, succeeded=$succeeded, percent=$percent, message=$message');

              if (finished && !succeeded) {
                print('TranslationService: Task failed — ${json['message'] ?? json['error'] ?? 'unknown'}');
                return null;
              }

              if (finished && succeeded) {
                final audioUrl = json['result'] as String?;
                if (audioUrl != null && audioUrl.startsWith('http')) {
                  print('TranslationService: Fetching from result URL: $audioUrl');
                  final ar = await http.get(Uri.parse(audioUrl));
                  print('TranslationService: Result URL — ${ar.statusCode}, ${ar.bodyBytes.length} bytes');
                  if (ar.statusCode == 200 && ar.bodyBytes.isNotEmpty && _isMp3(ar.bodyBytes)) {
                    print('TranslationService: Audio fetched! ${ar.bodyBytes.length} bytes');
                    return ar.bodyBytes;
                  }
                }
              }
              // Not done yet — continue polling while finished is false.
            }
          } catch (jsonErr) {
            print('TranslationService: JSON parse error: $jsonErr');
          }
        } else if (response.statusCode == 404 || response.statusCode == 202) {
          continue;
        } else {
          print('TranslationService: Unexpected status ${response.statusCode}');
        }
      } catch (e) {
        print('TranslationService: Poll error: $e');
      }
    }

    print('TranslationService: Timeout after $maxAttempts attempts');
    return null;
  }
}
