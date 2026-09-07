import 'package:flutter_test/flutter_test.dart';
import 'package:limpopo_voice/main.dart';

void main() {
  group('shared audio cache hashing', () {
    test('produces a stable hash for the same language and text', () {
      const text = ' Hello World ';
      const language = 'en';

      final hashA = buildSharedAudioCacheHash(text, language);
      final hashB = buildSharedAudioCacheHash(' hello world ', language);

      expect(hashA, isNotEmpty);
      expect(hashA, equals(hashB));
    });

    test('changes when language or text changes', () {
      final hashA = buildSharedAudioCacheHash('hello world', 'en');
      final hashB = buildSharedAudioCacheHash('hello world', 'af');
      final hashC = buildSharedAudioCacheHash('goodbye world', 'en');

      expect(hashA, isNot(equals(hashB)));
      expect(hashA, isNot(equals(hashC)));
    });
  });
}
