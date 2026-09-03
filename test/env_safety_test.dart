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
    );

    final encoded = item.toJson();
    final decoded = HistoryItem.fromJson(encoded);

    expect(decoded.inputLang, 'English');
    expect(decoded.outputLang, 'Sepedi');
    expect(decoded.original, 'Hello');
    expect(decoded.translated, 'Dumela');
    expect(decoded.phonetic, 'du-me-la');
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
}
