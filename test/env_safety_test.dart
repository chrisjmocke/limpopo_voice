import 'package:flutter_test/flutter_test.dart';
import 'package:limpopo_voice/main.dart';
import 'package:limpopo_voice/translation_service.dart';

void main() {
  test('safe env lookup returns empty without crashing when dotenv is not initialized', () {
    expect(() => safeDotEnvString('TRANSLATE_FUNCTION_URL'), returnsNormally);
    expect(safeDotEnvString('TRANSLATE_FUNCTION_URL'), isEmpty);
  });

  test('translation requests do not skip translation by default', () {
    final service = TranslationService(functionUrl: 'https://example.test');
    final body = service.buildRequestBody(
      text: 'Good morning',
      targetLanguage: 'Sepedi',
      voiceName: 'Mpho',
      ttsProvider: 'narakeet',
    );

    expect(body['skipTranslation'], isFalse);
    expect(body['targetLanguage'], 'Sepedi');
    expect(body['text'], 'Good morning');
    expect(body['translatedText'], 'Good morning');
  });

  test('translation request payload with skipTranslation populates both text and translatedText', () {
    final service = TranslationService(functionUrl: 'https://example.test');
    final body = service.buildRequestBody(
      text: 'Dumela',
      targetLanguage: 'Sepedi',
      voiceName: 'Mpho',
      ttsProvider: 'narakeet',
      skipTranslation: true,
    );

    expect(body['skipTranslation'], isTrue);
    expect(body['text'], 'Dumela');
    expect(body['translatedText'], 'Dumela');
  });

  test('legacy hasAudio payloads map to audioGenerated and isDeferred safely', () {
    final legacy = HistoryItem.fromJson({
      'inputLang': 'English',
      'outputLang': 'Sepedi',
      'original': 'Hello',
      'translated': 'Dumela',
      'time': DateTime.utc(2024, 1, 2, 3, 4, 5).toIso8601String(),
      'hasAudio': false,
    });

    expect(legacy.audioGenerated, isFalse);
    expect(legacy.isDeferred, isTrue);
    expect(legacy.hasAudio, isFalse);
  });

  test('Google sign-in uses the Firebase web client ID for Android release builds', () {
    final id = getGoogleServerClientId();

    expect(id, isNotEmpty);
    expect(id, contains('apps.googleusercontent.com'));
    expect(id, contains('587321848459'));
  });

  test('UI language mode returns fully localized labels for English and Afrikaans', () {
    expect(localizedUiText('translate', AppUiLanguage.english), 'Translate');
    expect(localizedUiText('history', AppUiLanguage.english), 'History');
    expect(localizedUiText('translate', AppUiLanguage.afrikaans), 'Vertaal');
    expect(localizedUiText('history', AppUiLanguage.afrikaans), 'Geskiedenis');
    expect(localizedUiText('sign_in', AppUiLanguage.english), 'Sign In');
    expect(localizedUiText('sign_in', AppUiLanguage.afrikaans), 'Meld aan');
    expect(localizedUiText('continue_with_google', AppUiLanguage.afrikaans), 'Gaan voort met Google');
  });

  test('voice-note uploads warn when they exceed 5 seconds and require more than one credit', () {
    expect(isVoiceNoteWithinTranslationCap(const Duration(seconds: 5)), isTrue);
    expect(isVoiceNoteWithinTranslationCap(const Duration(seconds: 6)), isFalse);
    expect(calculateVoiceNoteTranslationCredits(const Duration(seconds: 4)), 1);
    expect(calculateVoiceNoteTranslationCredits(const Duration(seconds: 5)), 1);
    expect(calculateVoiceNoteTranslationCredits(const Duration(seconds: 6)), 2);
    expect(calculateVoiceNoteTranslationCredits(const Duration(seconds: 9)), 2);
  });

  test('audio upload payload checks reject oversized files before the backend sees them', () {
    expect(isAudioPayloadTooLarge(4 * 1024 * 1024), isFalse);
    expect(isAudioPayloadTooLarge(6 * 1024 * 1024), isTrue);
    expect(maxAudioUploadPayloadBytes, greaterThan(0));
  });

  test('learn playback speed selector supports 1.0x, 0.75x, and 0.5x', () {
    expect(learnPlaybackRateForSelection(LearnPlaybackSpeed.normal), 1.0);
    expect(learnPlaybackRateForSelection(LearnPlaybackSpeed.slow), 0.75);
    expect(learnPlaybackRateForSelection(LearnPlaybackSpeed.slowest), 0.5);
  });

  test('history cache round-trips through JSON without losing values', () {
    final item = HistoryItem(
      'English',
      'Sepedi',
      'Hello',
      'Dumela',
      DateTime.utc(2024, 1, 2, 3, 4, 5),
      phonetic: 'du-me-la',
      audioGenerated: false,
    );

    final encoded = item.toJson();
    final decoded = HistoryItem.fromJson(encoded);

    expect(decoded.inputLang, 'English');
    expect(decoded.outputLang, 'Sepedi');
    expect(decoded.original, 'Hello');
    expect(decoded.translated, 'Dumela');
    expect(decoded.phonetic, 'du-me-la');
    expect(decoded.audioGenerated, isFalse);
    expect(decoded.time.isAtSameMomentAs(item.time), isTrue);
  });

  test('learn and history lists are capped at 100 entries keeping the newest items', () {
    final longHistory = List.generate(150, (index) => HistoryItem(
          'English',
          'Sepedi',
          'Text ${149 - index}',
          'Translation ${149 - index}',
          DateTime.utc(2024, 1, 2, 3, 149 - index),
        ));

    final trimmedHistory = limitEntries(longHistory, 100);
    final longLearn = List.generate(150, (index) => {'text': 'Phrase ${149 - index}'});
    final trimmedLearn = limitEntries(longLearn, 100);

    expect(trimmedHistory.length, 100);
    expect(trimmedLearn.length, 100);
    expect(trimmedHistory.first.original, 'Text 149');
    expect(trimmedLearn.first['text'], 'Phrase 149');
  });

  test('swipe routing always reaches the next tab even on moderate drags', () {
    expect(nextTabForSwipe('translate', dragDelta: -80.0), 'history');
    expect(nextTabForSwipe('history', dragDelta: -80.0), 'learn');
    expect(nextTabForSwipe('history', dragDelta: 80.0), 'translate');
    expect(nextTabForSwipe('learn', dragDelta: 80.0), 'history');
  });

  test('fragment cache helpers normalize text and generate reusable fragment keys', () {
    final normalized = normalizeCacheText('  Hello,   world!  ');
    expect(normalized, 'hello world');

    final keys = buildFragmentCacheKeys('Hello world again', maxWords: 2);
    expect(keys, contains('hello'));
    expect(keys, contains('world'));
    expect(keys, contains('hello world'));
    expect(keys.length, greaterThanOrEqualTo(3));
  });

  test('pending auth return intent preserves the buy credits route and clears safely', () {
    final route = normalizePendingAuthReturnRoute('buy_credits');
    final payload = buildPendingAuthReturnIntent(route: route);

    expect(route, 'buy_credits');
    expect(payload['route'], 'buy_credits');
    expect(clearPendingAuthReturnIntent(payload), isEmpty);
  });

}
