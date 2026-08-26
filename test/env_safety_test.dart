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
}
