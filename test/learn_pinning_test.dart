import 'package:flutter_test/flutter_test.dart';
import 'package:limpopo_voice/main.dart';

void main() {
  group('learn phrase pinning', () {
    test('moves pinned phrases to the top while preserving the rest of the order', () {
      final phrases = [
        {'text': 'first', 'en': 'one'},
        {'text': 'second', 'en': 'two', 'pinned': 'true'},
        {'text': 'third', 'en': 'three'},
        {'text': 'fourth', 'en': 'four', 'pinned': 'true'},
      ];

      final sorted = sortLearnPhrasesByPinned(phrases);

      expect(sorted.map((p) => p['text']), [
        'second',
        'fourth',
        'first',
        'third',
      ]);
    });
  });
}
