import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class TranslationService {
  final String apiKey;
  final String baseUrl = 'https://api.narakeet.com';

  TranslationService({required this.apiKey});

  Future<Uint8List?> generateTranslation(String text, String voiceName) async {
    final endpoint = '$baseUrl/text-to-speech/mp3?voice=$voiceName';
    try {
      print('TranslationService: POST $endpoint (voice=$voiceName)');

      // Step 1: Submit job
      final submitResp = await http.post(
        Uri.parse(endpoint),
        headers: {'x-api-key': apiKey, 'Content-Type': 'text/plain'},
        body: utf8.encode(text),
      );

      print('TranslationService: Submit status: ${submitResp.statusCode}');
      if (submitResp.statusCode != 200) {
        print('TranslationService: Submit error — ${submitResp.body}');
        return null;
      }

      final jobJson = jsonDecode(submitResp.body);
      final statusUrl = jobJson['statusUrl'] as String?;
      final taskId   = jobJson['taskId']    as String?;

      if (statusUrl == null || taskId == null) {
        print('TranslationService: Missing taskId/statusUrl');
        return null;
      }

      print('TranslationService: Task ID: $taskId — polling...');
      return await _pollForAudio(statusUrl, taskId);
    } catch (e) {
      print('TranslationService: Exception — $e');
      return null;
    }
  }

  Future<Uint8List?> _pollForAudio(String statusUrl, String taskId,
      {int maxAttempts = 40}) async {
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      // Fast at first, then slow down
      await Future.delayed(Duration(milliseconds: attempt < 8 ? 250 : 500));

      try {
        // Pre-signed S3 URL — no auth header needed
        final resp = await http.get(Uri.parse(statusUrl));
        final ct = resp.headers['content-type'] ?? '';
        print('TranslationService: Poll ${attempt + 1}/$maxAttempts — '
            'HTTP ${resp.statusCode}, bytes: ${resp.bodyBytes.length}, ct: $ct, '
            'body: ${resp.body.length > 200 ? resp.body.substring(0, 200) : resp.body}');

        if (resp.statusCode != 200) continue;

        final data = jsonDecode(resp.body);
        final finished  = data['finished']  == true;
        final succeeded = data['succeeded'] == true;
        final percent   = data['percent']   ?? 0;
        final message   = data['message']   ?? '';
        print('TranslationService: JSON finished=$finished, succeeded=$succeeded, '
            'percent=$percent, message=$message');

        if (finished && succeeded) {
          final resultUrl = data['result'] as String?;
          if (resultUrl == null) {
            print('TranslationService: finished but no result URL');
            return null;
          }
          print('TranslationService: Fetching from result URL: $resultUrl');
          final audioResp = await http.get(Uri.parse(resultUrl));
          print('TranslationService: Result URL — ${audioResp.statusCode}, '
              '${audioResp.bodyBytes.length} bytes');
          if (audioResp.statusCode == 200 && audioResp.bodyBytes.isNotEmpty) {
            print('TranslationService: Audio fetched! ${audioResp.bodyBytes.length} bytes');
            return audioResp.bodyBytes;
          }
          return null;
        }

        if (finished && !succeeded) {
          print('TranslationService: Task failed — $message');
          return null;
        }
      } catch (e) {
        print('TranslationService: Poll error — $e');
      }
    }
    print('TranslationService: Timed out after $maxAttempts polls');
    return null;
  }

  bool _isMp3(Uint8List bytes) {
    if (bytes.length < 4) return false;
    // ID3 tag
    if (bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) return true;
    // MPEG sync word
    if (bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) return true;
    return false;
  }
}
