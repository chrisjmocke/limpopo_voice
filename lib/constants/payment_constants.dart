class PaymentConstants {
  static const String plan100Code = 'PLN_2t2fvh0gmfjshy7';
  static const String plan300Code = 'PLN_ietxwof2rdpsfpt';
  static const String plan700Code = 'PLN_qq7y0nbwj2x75ff';

  static const Map<String, int> codeToCredits = {
    plan100Code: 100,
    plan300Code: 300,
    plan700Code: 700,
  };

  static const Map<int, String> creditsToCode = {
    100: plan100Code,
    300: plan300Code,
    700: plan700Code,
  };
}
