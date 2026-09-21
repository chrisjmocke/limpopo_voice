import 'package:flutter_test/flutter_test.dart';

void main() {
  test('calculates OCR credit cost by rounded-up 80-character blocks', () {
    const charsPerCredit = 80;

    int calculateCredits(String text) {
      if (text.trim().isEmpty) return 0;
      return (text.length / charsPerCredit).ceil();
    }

    expect(calculateCredits(''), 0);
    expect(calculateCredits('a' * 80), 1);
    expect(calculateCredits('a' * 81), 2);
    expect(calculateCredits('hello world'), 1);
    expect(calculateCredits('a' * 160), 2);
  });
}
