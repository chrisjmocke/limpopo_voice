import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:paystack_flutter_sdk/paystack_flutter_sdk.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'translation_service.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    debugPrint("Firebase init error: $e");
  }

  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Env load error: $e");
  }
  runApp(const LetsTalkApp());
}

class LetsTalkApp extends StatefulWidget {
  const LetsTalkApp({super.key});
  @override
  State<LetsTalkApp> createState() => _LetsTalkAppState();
}

class _LetsTalkAppState extends State<LetsTalkApp> {
  ThemeMode _themeMode = ThemeMode.dark;
  void _toggleTheme() => setState(() => _themeMode =
      _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Let\'s Talk',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        fontFamily: 'monospace',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF000000),
          primary: const Color(0xFF000000),
          secondary: const Color(0xFF000000),
          brightness: Brightness.light,
          background: const Color(0xFFF7F7F7),
          surface: const Color(0xFFF7F7F7),
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F7F7),
        canvasColor: const Color(0xFFF7F7F7),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'monospace',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF000000),
          primary: const Color(0xFF000000),
          secondary: const Color(0xFF000000),
          brightness: Brightness.dark,
          background: const Color(0xFF000000),
          surface: const Color(0xFF000000),
        ),
        scaffoldBackgroundColor: const Color(0xFF000000),
        canvasColor: const Color(0xFF000000),
        useMaterial3: true,
      ),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: const TextScaler.linear(1.0)),
          child: DefaultTextStyle.merge(
            style: const TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w900,
              fontSize: 18,
              shadows: [
                Shadow(
                  color: Color(0x66000000),
                  blurRadius: 0,
                  offset: Offset(1.5, 0),
                ),
                Shadow(
                  color: Color(0x66000000),
                  blurRadius: 0,
                  offset: Offset(-1.5, 0),
                ),
                Shadow(
                  color: Color(0x66000000),
                  blurRadius: 0,
                  offset: Offset(0, 1.5),
                ),
                Shadow(
                  color: Color(0x4D000000),
                  blurRadius: 0,
                  offset: Offset(0, -1),
                ),
                Shadow(
                  color: Color(0x55000000),
                  blurRadius: 0,
                  offset: Offset(1, 1),
                ),
                Shadow(
                  color: Color(0x55000000),
                  blurRadius: 0,
                  offset: Offset(-1, 1),
                ),
                Shadow(
                  color: Color(0x66000000),
                  blurRadius: 2,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: HomeScreen(onToggleTheme: _toggleTheme),
    );
  }
}

class _CreditTier {
  final String name;
  final int secs;
  final String price;
  const _CreditTier(this.name, this.secs, this.price);
}

class _OrganizationPoolUpdate {
  final String action;
  final String organizationId;
  final String organizationName;
  final String inviteCode;
  final int sharedCredits;

  const _OrganizationPoolUpdate({
    required this.action,
    required this.organizationId,
    required this.organizationName,
    required this.inviteCode,
    required this.sharedCredits,
  });
}

class _PendingAccountMigration {
  final String? organizationId;
  final String? organizationName;
  final String? organizationInviteCode;
  final String role;

  const _PendingAccountMigration({
    required this.organizationId,
    required this.organizationName,
    required this.organizationInviteCode,
    required this.role,
  });

  bool get hasOrganization => organizationId != null && organizationId!.isNotEmpty;
  bool get ownsOrganization => hasOrganization && role == 'owner';
}

const _tiers = [
  _CreditTier('Micro', 30, 'R9.99'),
  _CreditTier('Basic', 180, 'R49.99'),
  _CreditTier('Pro', 600, 'R169.99'),
  _CreditTier('Enterprise', 1500, 'R419.99'),
  _CreditTier('Organisation', 5000, 'R899.99')
];
const int _usageCostSecs = 5;
const bool _enableClientFirestoreCache = false;
const String _organizationTierName = 'Organisation';
const int _organizationUsageCost = 1;

class HistoryItem {
  final String inputLang, outputLang, original, translated;
  final String? phonetic;
  final DateTime time;
  HistoryItem(this.inputLang, this.outputLang, this.original, this.translated,
      this.time,
      {this.phonetic});
}

class HomeScreen extends StatefulWidget {
  final VoidCallback onToggleTheme;
  const HomeScreen({super.key, required this.onToggleTheme});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
          final FocusNode _inputFocusNode = FocusNode();
        final Set<int> _selectedHistoryIndexes = {};
        final bool _showClearAll = false;
      String? _userEmail;
      Future<void> _deleteUserPhrase(int idx) async {
        final sure = await _confirmDeleteLearnPhrase();
        if (sure) {
          setState(() {
            final lang = _selectedLearnLang;
            final list = _userLearnPhrasesByLang[lang];
            if (list != null && idx < list.length) {
              list.removeAt(idx);
              _userLearnPhrasesByLang[lang] = List.from(list);
            }
          });
        }
      }

      Future<bool> _confirmDeleteLearnPhrase() async {
        final result = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            return AlertDialog(
              title: const Text('Are you sure?'),
              content: const Text('Delete this phrase from Learn?'),
              backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
              surfaceTintColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white : Color(0xFF000000))),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF000000),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Clear', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
        return result == true;
      }
    final Map<String, List<Map<String, String>>> _userLearnPhrasesByLang = {};

    Future<bool> _sendToLearnMultipleLangs({
      required String translated,
      required String original,
      required String phonetic,
      required List<String> langs,
    }) async {
      bool duplicateFound = false;
      for (final lang in langs) {
        final key = lang;
        final phraseList = (_userLearnPhrasesByLang[key] ?? []);
        if (phraseList.any((p) => p['text'] == translated)) {
          duplicateFound = true;
          break;
        }
      }
      if (duplicateFound) {
        await showDialog(
          context: context,
          builder: (ctx) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            return AlertDialog(
              title: const Text('Duplicate'),
              content: const Text('This phrase already exists in Learn.'),
              backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
              surfaceTintColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white : Color(0xFF000000))),
                ),
              ],
            );
          },
        );
        return false;
      }
      setState(() {
        for (final lang in langs) {
          final key = lang;
          final phraseList = (_userLearnPhrasesByLang[key] ?? []).toList();
          phraseList.insert(0, {
            'text': translated,
            'en': original,
            if (phonetic.isNotEmpty) 'phonetic': phonetic,
          });
          while (phraseList.length > 5) {
            phraseList.removeLast();
          }
          _userLearnPhrasesByLang[key] = phraseList;
          _learnFocusTextByLang[lang] = translated;
          _learnFocusMeaningByLang[lang] = original;
          _learnFocusPhoneticByLang[lang] = phonetic.isEmpty ? null : phonetic;
        }
      });
      _showSnack('Sentence sent to selected languages (max 5 per language)');
      return true;
    }
  static const List<String> _offensiveWords = [
    'fuck',
    'fucking',
    'fucker',
    'shit',
    'bullshit',
    'shitty',
    'bitch',
    'bitches',
    'biatch',
    'bastard',
    'asshole',
    'ass',
    'arse',
    'arsehole',
    'damn',
    'goddamn',
    'hell',
    'bloody',
    'crap',
    'dick',
    'dildo',
    'wanker',
    'jerkoff',
    'cunt',
    'piss',
    'pissed',
    'cock',
    'penis',
    'vagina',
    'motherfucker',
    'mf',
    'nigger',
    'nigga',
    'slut',
    'whore',
    'idiot',
    'moron',
    'stupid',
    'retard',
    'kak',
    'k@k',
    'kaffir',
    'poes',
    'p0es',
    'naai',
    'naaier',
    'bliksem',
    'fok',
    'fokken',
    'domkop',
    'god damn',
  ];

  static const int _firstSpeechChunkMaxChars = 42;
  static const int _speechChunkMaxChars = 90;
  static const Duration _firstChunkFetchTimeout = Duration(seconds: 55);
  static const Duration _nextChunkFetchTimeout = Duration(seconds: 55);
  static const String _defaultProcessSpeechUrl =
      'https://africa-south1-limpopo-voice-prod.cloudfunctions.net/processSpeech';

  static final RegExp _offensiveWordRegex = RegExp(
    '\\b(${_offensiveWords.map(RegExp.escape).join('|')})\\b',
    caseSensitive: false,
  );

  static final RegExp _maskedProfanityRegex = RegExp(
    r'([a-zA-Z]\*{2,}|@[*$]+)',
    caseSensitive: false,
  );

  static final List<RegExp> _offensiveFlexibleRegexes = _offensiveWords
      .map(_buildFlexibleOffensiveRegex)
      .toList(growable: false);

  static RegExp _buildFlexibleOffensiveRegex(String word) {
    final compact = word.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (compact.isEmpty) {
      return RegExp(r'$.');
    }

    final chars = compact.split('').map(RegExp.escape).join(r'[\W_]*');
    return RegExp(
      '(?<![A-Za-z0-9])$chars(?![A-Za-z0-9])',
      caseSensitive: false,
    );
  }

  static const String _disclaimerText =
    "'Let's Talk' uses advanced AI to provide translations. However, automated translation is not perfect. 'Let's Talk' is not responsible for any inaccurate, misleading, or offensive translations generated by the system. By using this app, you agree to use these translations at your own risk.";

  Future<void> _showDisclaimerInfo() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disclaimer'),
        content: const SingleChildScrollView(
          child: Text(_disclaimerText),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFF000000),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _activeTab = 'translate';
  Future<void>? _startupInitFuture;
  final stt.SpeechToText _speech = stt.SpeechToText();
  late final TranslationService _translationService;
  late final AudioPlayer _audioPlayer;
  bool _speechAvailable = false;
  bool _isTalking = false;
  bool _isTranslating = false;
  bool _isPlayingAudio = false;
  String _selectedInputLang = 'English';
  String _selectedOutputLang = 'Sepedi';
  final _inputLangs = [
    'English',
    'Afrikaans',
    'isiNdebele',
    'isiXhosa',
    'isiZulu',
    'Sepedi',
    'Sesotho',
    'Setswana',
    'siSwati',
    'Tshivenda',
    'Xitsonga',
  ];
  final _outputLangs = [
    'isiNdebele',
    'isiXhosa',
    'isiZulu',
    'Sepedi',
    'Sesotho',
    'Setswana',
    'siSwati',
    'Tshivenda',
    'Xitsonga',
    'English',
    'Afrikaans',
  ];
  final _locales = {
    'Afrikaans': 'af-ZA',
    'English': 'en-ZA',
    'isiNdebele': 'nr-ZA',
    'isiXhosa': 'xh-ZA',
    'isiZulu': 'zu-ZA',
    'Sepedi': 'nso-ZA',
    'Sesotho': 'st-ZA',
    'Setswana': 'tn-ZA',
    'siSwati': 'ss-ZA',
    'Tshivenda': 've-ZA',
    'Xitsonga': 'ts-ZA',
  };
  final _translateCodes = {
    'Afrikaans': 'af',
    'English': 'en',
    'isiNdebele': 'nr',
    'isiXhosa': 'xh',
    'isiZulu': 'zu',
    'Sepedi': 'nso',
    'Sesotho': 'st',
    'Setswana': 'tn',
    'siSwati': 'ss',
    'Tshivenda': 've',
    'Xitsonga': 'ts',
  };
  static const _voiceNames = {
    'Afrikaans': 'Rolanda',
    'English': 'Aletta',
    'isiNdebele': 'Dumisani',
    'isiXhosa': 'Lindiwe',
    'isiZulu': 'Nandi',
    'Sepedi': 'Mpho',
    'Sesotho': 'Palesa',
    'Setswana': 'Bokang',
    'siSwati': 'Nomcebo',
    'Tshivenda': 'Mulalo',
    'Xitsonga': 'Basetsana',
  };
  static const Set<String> _southAfricanLanguages = {
    'Afrikaans',
    'English',
    'isiNdebele',
    'isiXhosa',
    'isiZulu',
    'Sepedi',
    'Sesotho',
    'Setswana',
    'siSwati',
    'Tshivenda',
    'Xitsonga',
  };
  String _spokenText = '';
  String _translatedText = '';
  String _spokenRawText = '';
  String _translatedRawText = '';
  String _phoneticText = '';
  String _spokenLang = '';
  String _translatedLang = '';
  final TextEditingController _tttController = TextEditingController();
  int _credits = 30;
  String? _authUid;
  String? _authEmail;
  String? _installId;
  String? _deviceId;
  String? _organizationId;
  String? _organizationName;
  String? _organizationInviteCode;
  String _organizationRole = 'personal';
  int? _organizationSharedCredits;
  bool _authBusy = false;
  final List<HistoryItem> _history = [];
  String _selectedLearnLang = 'Sepedi';
  final Map<String, String> _learnFocusTextByLang = {};
  final Map<String, String> _learnFocusMeaningByLang = {};
  final Map<String, String?> _learnFocusPhoneticByLang = {};
  bool _exportingHistory = false;
  bool _sharingCurrentTranslation = false;
  Timer? _autocorrectTimer;

  static const Map<String, List<Map<String, String>>> _learnPhrasesByLang = {
    'English': [
      {'text': 'Hello, how are you?', 'en': 'Hello, how are you?'},
      {'text': 'Thank you very much.', 'en': 'Thank you very much.'},
      {'text': 'Please help me.', 'en': 'Please help me.'},
      {'text': 'Goodbye, see you later.', 'en': 'Goodbye, see you later.'},
    ],
    'Sepedi': [
      {'text': 'Dumela, o phela bjang?', 'en': 'Hello, how are you?'},
      {'text': 'Ke a leboga kudu.', 'en': 'Thank you very much.'},
      {'text': 'Hle, nthuše.', 'en': 'Please help me.'},
      {'text': 'Sala gabotse.', 'en': 'Goodbye.'},
    ],
    'Xitsonga': [
      {'text': 'Avuxeni, u njhani?', 'en': 'Hello, how are you?'},
      {'text': 'Ndza nkhensa swinene.', 'en': 'Thank you very much.'},
      {'text': 'Ndzi kombela mpfuno.', 'en': 'Please help me.'},
      {'text': 'Endla kahle.', 'en': 'Goodbye.'},
    ],
    'Tshivenda': [
      {'text': 'Ndaa, ni hone?', 'en': 'Hello, how are you?'},
      {'text': 'Ndo livhuwa vhukuma.', 'en': 'Thank you very much.'},
      {'text': 'Ndi humbela thuso.', 'en': 'Please help me.'},
      {'text': 'Salani zwavhudi.', 'en': 'Goodbye.'},
    ],
    'Setswana': [
      {'text': 'Dumela, o tsogile jang?', 'en': 'Hello, how are you?'},
      {'text': 'Ke a go leboga thata.', 'en': 'Thank you very much.'},
      {'text': 'Tsweetswee nthuse.', 'en': 'Please help me.'},
      {'text': 'Tsamaya sentle.', 'en': 'Goodbye.'},
    ],
    'isiXhosa': [
      {'text': 'Molo, unjani?', 'en': 'Hello, how are you?'},
      {'text': 'Enkosi kakhulu.', 'en': 'Thank you very much.'},
      {'text': 'Nceda undincede.', 'en': 'Please help me.'},
      {'text': 'Hamba kakuhle.', 'en': 'Goodbye.'},
    ],
    'isiZulu': [
      {'text': 'Sawubona, unjani?', 'en': 'Hello, how are you?'},
      {'text': 'Ngiyabonga kakhulu.', 'en': 'Thank you very much.'},
      {'text': 'Ngicela ungisize.', 'en': 'Please help me.'},
      {'text': 'Hamba kahle.', 'en': 'Goodbye.'},
    ],
    'siSwati': [
      {'text': 'Sawubona, wentani?', 'en': 'Hello, how are you?'},
      {'text': 'Ngiyabonga kakhulu.', 'en': 'Thank you very much.'},
      {'text': 'Ngicela ungisize.', 'en': 'Please help me.'},
      {'text': 'Sala kahle.', 'en': 'Goodbye.'},
    ],
    'Sesotho': [
      {'text': 'Dumela, o phela jwang?', 'en': 'Hello, how are you?'},
      {'text': 'Ke a leboha haholo.', 'en': 'Thank you very much.'},
      {'text': 'Ka kopo nthuse.', 'en': 'Please help me.'},
      {'text': 'Sala hantle.', 'en': 'Goodbye.'},
    ],
    'isiNdebele': [
      {'text': 'Lotjhani, unjani?', 'en': 'Hello, how are you?'},
      {'text': 'Ngiyathokoza khulu.', 'en': 'Thank you very much.'},
      {'text': 'Ngicela ungisize.', 'en': 'Please help me.'},
      {'text': 'Sala kahle.', 'en': 'Goodbye.'},
    ],
    'Afrikaans': [
      {'text': 'Hallo, hoe gaan dit?', 'en': 'Hello, how are you?'},
      {'text': 'Baie dankie.', 'en': 'Baie dankie.'},
      {'text': 'Help my asseblief.', 'en': 'Help my asseblief.'},
      {'text': 'Totsiens.', 'en': 'Totsiens.'},
    ],
  };

  String _normalizeLanguageLabel(String language) {
    final cleaned = language
        .replaceAll('(', '')
        .replaceAll(')', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned == 'English South African Accent') return 'English';
    if (cleaned == 'Sepedi Northern Sotho') return 'Sepedi';
    if (cleaned == 'Sesotho Southern Sotho') return 'Sesotho';
    return cleaned;
  }

  String _ttsProviderForLanguage(String language) {
    final normalized = _normalizeLanguageLabel(language);
    return _southAfricanLanguages.contains(normalized) ? 'narakeet' : 'google';
  }

  String _translationFunctionUrl() {
    final configured = (dotenv.env['TRANSLATE_FUNCTION_URL'] ?? '').trim();
    if (configured.isNotEmpty) {
      return configured;
    }

    debugPrint(
      'TRANSLATE_FUNCTION_URL missing. Falling back to default processSpeech endpoint.',
    );
    return _defaultProcessSpeechUrl;
  }

  String? _voiceNameForLanguage(String language) {
    final normalized = _normalizeLanguageLabel(language);
    final provider = _ttsProviderForLanguage(normalized);
    if (provider == 'narakeet') {
      return _voiceNames[normalized] ?? 'Aletta';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _selectedInputLang = _normalizeLanguageLabel(_selectedInputLang);
    _selectedOutputLang = _normalizeLanguageLabel(_selectedOutputLang);
    _selectedLearnLang = _normalizeLanguageLabel(_selectedLearnLang);
    if (!_inputLangs.contains(_selectedInputLang)) {
      _selectedInputLang = _inputLangs.first;
    }
    if (!_outputLangs.contains(_selectedOutputLang)) {
      _selectedOutputLang = _outputLangs.first;
    }
    if (!_outputLangs.contains(_selectedLearnLang)) {
      _selectedLearnLang = _outputLangs.first;
    }
    _audioPlayer = AudioPlayer();
    final functionUrl = _translationFunctionUrl();
    _translationService = TranslationService(functionUrl: functionUrl);
    _translationService.primeSession();
    _configureAudioPlayback();
    _initSpeech();
    unawaited(Paystack().initialize('pk_test_d8de1c368577b34a06507f38cf0bf989b47522a5', true));
    _tttController.addListener(_onInputChanged);
    _startupInitFuture = _checkInstallIdAndFreeTrial();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showDisclaimerIfFirstInstall();
    });
  }

  String _generateUUID() {
    const chars = 'abcdef0123456789';
    final random = Random();
    return List.generate(32, (_) => chars[random.nextInt(chars.length)]).join();
  }

  bool _isAnonymousUser([User? user]) {
    final currentUser = user ?? FirebaseAuth.instance.currentUser;
    return currentUser?.isAnonymous ?? false;
  }

  bool _isPaymentReadyUser([User? user]) {
    final currentUser = user ?? FirebaseAuth.instance.currentUser;
    final email = (currentUser?.email ?? _authEmail ?? '').trim();
    return currentUser != null && !currentUser.isAnonymous && email.isNotEmpty;
  }

  String _authStatusLabel() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'Not signed in';
    if (user.isAnonymous) return 'Guest session';
    final providerIds = user.providerData.map((item) => item.providerId).toSet();
    if (providerIds.contains('google.com')) return 'Google account';
    if (providerIds.contains('password')) {
      return user.emailVerified ? 'Email account' : 'Email account - verify inbox';
    }
    return 'Signed in';
  }

  Future<void> _syncAuthState(User? user, {bool reloadOrganization = true}) async {
    if (!mounted) {
      _authUid = user?.uid;
      _authEmail = user?.email;
      if (user == null) {
        _organizationId = null;
        _organizationName = null;
        _organizationInviteCode = null;
        _organizationRole = 'personal';
        _organizationSharedCredits = null;
      }
      return;
    }

    setState(() {
      _authUid = user?.uid;
      _authEmail = user?.email;
      if (user == null) {
        _organizationId = null;
        _organizationName = null;
        _organizationInviteCode = null;
        _organizationRole = 'personal';
        _organizationSharedCredits = null;
      }
    });

    if (user == null) return;

    // Reload user to get latest profile data (including photoURL)
    try {
      await user.reload();
    } catch (e) {
      debugPrint('Failed to reload user: $e');
    }

    await _ensureUserProfileDocument();
    
    // Load persisted credits for authenticated users
    if (!user.isAnonymous) {
      await _loadCreditsFromFirestore();
    }
    
    if (reloadOrganization) {
      await _loadOrganizationMembership();
    }
  }

  _PendingAccountMigration? _capturePendingAccountMigration() {
    if (_organizationId == null || _organizationId!.isEmpty) {
      return null;
    }

    return _PendingAccountMigration(
      organizationId: _organizationId,
      organizationName: _organizationName,
      organizationInviteCode: _organizationInviteCode,
      role: _organizationRole,
    );
  }

  Future<void> _restorePendingAccountMigration(_PendingAccountMigration? migration) async {
    if (migration == null || !migration.hasOrganization || migration.ownsOrganization) {
      return;
    }

    final userRef = _userDocRef();
    if (userRef == null) return;

    await userRef.set({
      'organizationId': migration.organizationId,
      'organizationRole': migration.role,
      'organizationInviteCode': migration.organizationInviteCode,
      'organizationName': migration.organizationName,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    setState(() {
      _organizationId = migration.organizationId;
      _organizationRole = migration.role;
      _organizationInviteCode = migration.organizationInviteCode;
      _organizationName = migration.organizationName;
    });
    await _refreshOrganizationDetails();
  }

  bool _canSwitchFromGuestToExistingAccount(_PendingAccountMigration? migration) {
    if (migration?.ownsOrganization == true) {
      _showSnack(
        'This guest session owns an organisation. Upgrade this same guest with Google or a new email account to keep ownership.',
      );
      return false;
    }
    return true;
  }

  String _friendlyAuthError(FirebaseAuthException error) {
    switch (error.code) {
      case 'account-exists-with-different-credential':
        return 'That email is already linked to a different sign-in method.';
      case 'credential-already-in-use':
        return 'That account already exists. Sign in to it instead of creating a new guest upgrade.';
      case 'email-already-in-use':
        return 'That email address is already registered. Use Sign In instead.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'invalid-credential':
      case 'wrong-password':
      case 'invalid-password':
      case 'user-not-found':
        return 'The email or password is incorrect.';
      case 'weak-password':
        return 'Use a stronger password with at least 6 characters.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many sign-in attempts. Please try again later.';
      default:
        return error.message ?? 'Authentication failed. Please try again.';
    }
  }

  Future<void> _showAuthOptionsDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
        surfaceTintColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
        title: Text(
          'Sign In',
          style: TextStyle(color: isDark ? Colors.white : const Color(0xFF000000)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Use Google or email so payments, receipts, and organisation ownership stay attached to a real account.',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? Colors.white10 : Colors.black,
                  foregroundColor: Colors.white,
                ),
                onPressed: _authBusy
                    ? null
                    : () {
                        Navigator.of(ctx).pop();
                        _signInWithGoogle();
                      },
                icon: const Icon(Icons.login),
                label: const Text('Continue with Google'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _authBusy
                    ? null
                    : () {
                        Navigator.of(ctx).pop();
                        _showEmailAuthDialog(createAccount: true);
                      },
                icon: const Icon(Icons.email_outlined),
                label: const Text('Create email account'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _authBusy
                    ? null
                    : () {
                        Navigator.of(ctx).pop();
                        _showEmailAuthDialog(createAccount: false);
                      },
                child: const Text('Sign in with email'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFF000000),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEmailAuthDialog({required bool createAccount}) async {
    final emailController = TextEditingController(text: (_authEmail ?? '').trim());
    final passwordController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    bool obscurePassword = true;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            scrollable: true,
            backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
            surfaceTintColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
            title: Text(
              createAccount ? 'Create Email Account' : 'Email Sign In',
              style: TextStyle(color: isDark ? Colors.white : const Color(0xFF000000)),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      onPressed: () {
                        setDialogState(() => obscurePassword = !obscurePassword);
                      },
                      icon: Icon(obscurePassword ? Icons.visibility : Icons.visibility_off),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  createAccount
                      ? 'Creating an email account keeps this guest profile, its organisation link, and future payments on one recoverable account.'
                      : 'Use this only when you already have an email account for Let\'s Talk.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white : const Color(0xFF000000))),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFF000000),
                  foregroundColor: Colors.white,
                ),
                onPressed: _authBusy
                    ? null
                    : () async {
                        Navigator.of(ctx).pop();
                        await _signInWithEmail(
                          emailController.text,
                          passwordController.text,
                          createAccount: createAccount,
                        );
                      },
                child: Text(createAccount ? 'Create' : 'Sign In'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _signInWithGoogle() async {
    if (_authBusy) return;
    if (mounted) {
      setState(() => _authBusy = true);
    } else {
      _authBusy = true;
    }

    final auth = FirebaseAuth.instance;
    final currentUser = auth.currentUser;
    final migration = _capturePendingAccountMigration();

    try {
      final googleUser = await GoogleSignIn(scopes: const ['email']).signIn();
      if (googleUser == null) {
        return;
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential result;
      if (currentUser != null && currentUser.isAnonymous) {
        try {
          result = await currentUser.linkWithCredential(credential);
        } on FirebaseAuthException catch (e) {
          if (e.code != 'credential-already-in-use' &&
              e.code != 'account-exists-with-different-credential') {
            rethrow;
          }
          if (!_canSwitchFromGuestToExistingAccount(migration)) {
            return;
          }
          result = await auth.signInWithCredential(credential);
          await _syncAuthState(result.user, reloadOrganization: false);
          await _restorePendingAccountMigration(migration);
          _showSnack('Signed in with Google.');
          return;
        }
        
        // Update user profile with Google account details
        if (result.user != null) {
          try {
            final photoUrl = googleUser.photoUrl;
            final displayName = googleUser.displayName;
            
            if (displayName != null && displayName.isNotEmpty) {
              await result.user!.updateDisplayName(displayName);
            }
            if (photoUrl != null && photoUrl.isNotEmpty) {
              await result.user!.updatePhotoURL(photoUrl);
            }
            
            // Reload user to get updated profile data
            await result.user!.reload();
          } catch (e) {
            debugPrint('Failed to update user profile: $e');
          }
        }
      } else {
        result = await auth.signInWithCredential(credential);
      }

      // Update user profile with Google account details
      if (result.user != null) {
        try {
          final photoUrl = googleUser.photoUrl;
          final displayName = googleUser.displayName;
          
          if (displayName != null && displayName.isNotEmpty) {
            await result.user!.updateDisplayName(displayName);
          }
          if (photoUrl != null && photoUrl.isNotEmpty) {
            await result.user!.updatePhotoURL(photoUrl);
          }
          
          // Reload user to get updated profile data
          await result.user!.reload();
        } catch (e) {
          debugPrint('Failed to update user profile: $e');
        }
      }

      await _syncAuthState(result.user);
      _showSnack('Signed in with Google.');
    } on FirebaseAuthException catch (e) {
      _showSnack(_friendlyAuthError(e));
    } on PlatformException catch (e) {
      final msg = (e.message ?? '').toLowerCase();
      final details = (e.details?.toString() ?? '').toLowerCase();
      if (msg.contains('developer_error') || details.contains('developer_error')) {
        _showSnack('Google sign-in config error. Enable Google provider in Firebase and refresh android/app/google-services.json.');
      } else {
        _showSnack('Google sign-in failed: ${e.code}');
      }
      debugPrint('Google sign-in platform error: code=${e.code}, message=${e.message}, details=${e.details}');
    } catch (e) {
      debugPrint('Google sign-in failed: $e');
      _showSnack('Google sign-in failed. Please try again.');
    } finally {
      if (!mounted) {
        _authBusy = false;
      } else {
        setState(() => _authBusy = false);
      }
    }
  }

  Future<void> _signInWithEmail(
    String rawEmail,
    String rawPassword, {
    required bool createAccount,
  }) async {
    final email = rawEmail.trim();
    final password = rawPassword.trim();
    if (email.isEmpty || password.isEmpty) {
      _showSnack('Enter both email and password.');
      return;
    }
    if (createAccount && password.length < 6) {
      _showSnack('Use a password with at least 6 characters.');
      return;
    }
    if (_authBusy) return;

    if (mounted) {
      setState(() => _authBusy = true);
    } else {
      _authBusy = true;
    }

    final auth = FirebaseAuth.instance;
    final currentUser = auth.currentUser;
    final migration = _capturePendingAccountMigration();
    final credential = EmailAuthProvider.credential(email: email, password: password);

    try {
      UserCredential result;
      if (createAccount) {
        if (currentUser != null && currentUser.isAnonymous) {
          result = await currentUser.linkWithCredential(credential);
        } else {
          result = await auth.createUserWithEmailAndPassword(email: email, password: password);
        }
        await _syncAuthState(result.user);
        if (result.user != null && !(result.user!.emailVerified)) {
          await result.user!.sendEmailVerification();
        }
        _showSnack('Email account ready. Verification email sent.');
      } else {
        if (currentUser != null && currentUser.isAnonymous && !_canSwitchFromGuestToExistingAccount(migration)) {
          return;
        }
        result = await auth.signInWithEmailAndPassword(email: email, password: password);
        await _syncAuthState(result.user, reloadOrganization: false);
        await _restorePendingAccountMigration(migration);
        _showSnack('Signed in with email.');
      }
    } on FirebaseAuthException catch (e) {
      _showSnack(_friendlyAuthError(e));
    } catch (e) {
      debugPrint('Email auth failed: $e');
      _showSnack('Email sign-in failed. Please try again.');
    } finally {
      if (!mounted) {
        _authBusy = false;
      } else {
        setState(() => _authBusy = false);
      }
    }
  }

  Future<void> _signOutToGuest() async {
    if (_authBusy) return;
    if (mounted) {
      setState(() => _authBusy = true);
    } else {
      _authBusy = true;
    }

    try {
      await GoogleSignIn().signOut().catchError((_) {});
      await FirebaseAuth.instance.signOut();
      await _ensureSignedIn();
      await _ensureUserProfileDocument();
      await _loadOrganizationMembership();
      _showSnack('Signed out. Continuing as guest.');
    } catch (e) {
      debugPrint('Sign-out failed: $e');
      _showSnack('Could not sign out right now.');
    } finally {
      if (!mounted) {
        _authBusy = false;
      } else {
        setState(() => _authBusy = false);
      }
    }
  }

  Future<bool> _ensurePaymentReadyAccount() async {
    if (_isPaymentReadyUser()) {
      return true;
    }

    _showSnack('Sign in with Google or email before buying credits.');
    await _showAuthOptionsDialog();
    return false;
  }

  Future<void> _ensureSignedIn() async {
    try {
      final auth = FirebaseAuth.instance;
      var user = auth.currentUser;
      if (user == null) {
        final credential = await auth.signInAnonymously();
        user = credential.user;
      }

      await _syncAuthState(user);
    } catch (e) {
      debugPrint('Firebase Auth sign-in failed: $e');
      if (mounted) {
        _showSnack('Sign-in failed. Please check your connection.');
      }
    }
  }

  String _displayUserIdentity() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.isAnonymous) {
      return 'Guest session';
    }

    final email = _authEmail;
    if (email != null && email.trim().isNotEmpty) {
      return email;
    }

    final uid = _authUid;
    if (uid != null && uid.isNotEmpty) {
      final short = uid.length > 8 ? uid.substring(0, 8) : uid;
      return 'ID: $short';
    }

    return 'Not signed in';
  }

  ImageProvider? _getUserProfileImage() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.photoURL != null && user.photoURL!.isNotEmpty) {
      return NetworkImage(user.photoURL!);
    }
    return null;
  }

  String _paystackInitUrl() {
    final configured = (dotenv.env['PAYSTACK_INIT_URL'] ?? '').trim();
    if (configured.isNotEmpty) {
      return configured;
    }
    return 'https://africa-south1-limpopo-voice-prod.cloudfunctions.net/createPaystackTransactionHttp';
  }

  Future<Map<String, String>?> _buildAuthorizedJsonHeaders({bool forceRefresh = false}) async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      user ??= (await FirebaseAuth.instance.signInAnonymously()).user;
      if (user == null) return null;

      final idToken = await user.getIdToken(forceRefresh);
      return {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      };
    } catch (e) {
      debugPrint('Auth header build failed: $e');
      return null;
    }
  }

  Future<String?> _requestPaystackAccessCode(_CreditTier tier, double amount) async {
    final headers = await _buildAuthorizedJsonHeaders();
    if (headers == null) {
      _showSnack('Could not authenticate payment request.');
      return null;
    }

    final payload = {
      'amountCents': (amount * 100).round(),
      'email': _authEmail ?? '',
      'orgId': tier.name == _organizationTierName ? _organizationId : null,
    };

    final uri = Uri.parse(_paystackInitUrl());
    http.Response response;

    try {
      response = await http
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      debugPrint('Paystack init request failed: $e');
      return null;
    }

    if (response.statusCode == 401) {
      final refreshedHeaders = await _buildAuthorizedJsonHeaders(forceRefresh: true);
      if (refreshedHeaders == null) return null;
      try {
        response = await http
            .post(uri, headers: refreshedHeaders, body: jsonEncode(payload))
            .timeout(const Duration(seconds: 30));
      } catch (e) {
        debugPrint('Paystack init retry failed: $e');
        return null;
      }
    }

    if (response.statusCode != 200) {
      debugPrint('Paystack init HTTP ${response.statusCode}: ${response.body}');
      return null;
    }

    try {
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return null;
      final accessCode = body['access_code'] as String?;
      return (accessCode != null && accessCode.trim().isNotEmpty) ? accessCode.trim() : null;
    } catch (e) {
      debugPrint('Paystack init response parse failed: $e');
      return null;
    }
  }

  DocumentReference<Map<String, dynamic>>? _userDocRef() {
    final id = _authUid;
    if (id == null || id.isEmpty) return null;
    return FirebaseFirestore.instance.collection('users').doc(id);
  }

  String _newInviteCode() {
    final random = Random();
    final suffix = (1000 + random.nextInt(9000)).toString();
    return 'LT-ORG-$suffix';
  }

  Future<void> _ensureUserProfileDocument() async {
    final ref = _userDocRef();
    if (ref == null) return;
    await ref.set({
      'userId': _authUid,
      'authUid': _authUid,
      'email': _authEmail,
      'installId': _installId,
      'credits': _credits,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _loadCreditsFromFirestore() async {
    final ref = _userDocRef();
    if (ref == null) return;

    try {
      final doc = await ref.get();
      if (doc.exists) {
        final credits = (doc.data()?['credits'] as num?)?.toInt();
        if (credits != null && credits >= 0) {
          if (mounted) {
            setState(() => _credits = credits);
          } else {
            _credits = credits;
          }
          debugPrint('Loaded credits from Firestore: $_credits');
        }
      }
    } catch (e) {
      debugPrint('Failed to load credits: $e');
    }
  }

  Future<void> _updateCreditsInFirestore() async {
    final ref = _userDocRef();
    if (ref == null) return;

    try {
      await ref.update({
        'credits': _credits,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('Saved credits to Firestore: $_credits');
    } catch (e) {
      debugPrint('Failed to save credits: $e');
    }
  }

  Future<void> _refreshOrganizationDetails() async {
    final orgId = _organizationId;
    if (orgId == null || orgId.isEmpty) {
      if (!mounted) return;
      setState(() => _organizationSharedCredits = null);
      return;
    }

    try {
      final orgSnap = await FirebaseFirestore.instance
          .collection('organizations')
          .doc(orgId)
          .get();
      if (!orgSnap.exists) return;

      final data = orgSnap.data() ?? <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _organizationName = (data['name'] as String?) ?? _organizationName;
        _organizationInviteCode =
            (data['inviteCode'] as String?) ?? _organizationInviteCode;
        _organizationSharedCredits = (data['sharedCredits'] as num?)?.toInt();
      });
    } catch (e) {
      debugPrint('Organization refresh failed: $e');
    }
  }

  Future<void> _loadOrganizationMembership() async {
    final ref = _userDocRef();
    if (ref == null) return;

    try {
      final snap = await ref.get();
      final data = snap.data();
      if (!mounted) return;

      setState(() {
        _organizationId = data?['organizationId'] as String?;
        _organizationRole = (data?['organizationRole'] as String?) ?? 'personal';
        _organizationName = data?['organizationName'] as String?;
        _organizationInviteCode = data?['organizationInviteCode'] as String?;
      });
      await _refreshOrganizationDetails();
    } catch (e) {
      debugPrint('Organization membership load failed: $e');
    }
  }

  Future<void> _joinOrganizationByCode(String codeInput) async {
    final code = codeInput.trim().toUpperCase();
    if (code.isEmpty) {
      _showSnack('Enter an invite code first.');
      return;
    }

    final userRef = _userDocRef();
    if (userRef == null) {
      _showSnack('Profile not ready yet. Try again in a moment.');
      return;
    }

    try {
      final query = await FirebaseFirestore.instance
          .collection('organizations')
          .where('inviteCode', isEqualTo: code)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        _showSnack('Invite code not found.');
        return;
      }

      final orgDoc = query.docs.first;
      final orgData = orgDoc.data();
      await userRef.set({
        'organizationId': orgDoc.id,
        'organizationRole': 'member',
        'organizationInviteCode': orgData['inviteCode'],
        'organizationName': orgData['name'],
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _organizationId = orgDoc.id;
        _organizationRole = 'member';
        _organizationInviteCode = orgData['inviteCode'] as String?;
        _organizationName = orgData['name'] as String?;
      });
      await _refreshOrganizationDetails();
      _showSnack('Joined ${_organizationName ?? 'organization'} successfully.');
    } catch (e) {
      debugPrint('Join organization failed: $e');
      _showSnack('Could not join organization right now.');
    }
  }

  Future<void> _showJoinOrganizationDialog() async {
    final codeController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
        surfaceTintColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
        title: Text(
          'Join Shared Organisation',
          style: TextStyle(color: isDark ? Colors.white : const Color(0xFF000000)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: codeController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Invite code',
                hintText: 'LT-ORG-1234',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter the invite code shared by your organisation owner to connect to the shared credit pool.',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white : const Color(0xFF000000))),
          ),
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFF000000),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final code = codeController.text;
              Navigator.of(ctx).pop();
              await _joinOrganizationByCode(code);
            },
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }

  Future<void> _showOrganizationStatusDialog() async {
    final orgId = _organizationId;
    if (orgId == null || orgId.isEmpty) {
      await _showJoinOrganizationDialog();
      return;
    }

    await _refreshOrganizationDetails();
    if (!mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = _organizationName?.trim().isNotEmpty == true
        ? _organizationName!.trim()
        : 'Organisation';
    final inviteCode = _organizationInviteCode?.trim().isNotEmpty == true
        ? _organizationInviteCode!.trim()
        : '-';
    final roleLabel = _organizationRole.toUpperCase();
    final balanceLabel = _organizationSharedCredits != null
        ? '${_organizationSharedCredits!} shared credits'
        : 'Shared balance loading';

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
        surfaceTintColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
        title: Text(
          'Organisation',
          style: TextStyle(color: isDark ? Colors.white : const Color(0xFF000000)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF000000),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Role: $roleLabel',
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
            ),
            const SizedBox(height: 4),
            Text(
              'Pool: $balanceLabel',
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
            ),
            const SizedBox(height: 4),
            Text(
              'Invite code: $inviteCode',
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
            ),
            const SizedBox(height: 10),
            Text(
              _organizationRole == 'owner'
                  ? 'Use this code to invite staff, students, patients, or colleagues into the shared pool.'
                  : 'You are linked to this shared pool. Ask the owner if you need a new invite code or more credits.',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: inviteCode == '-'
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: inviteCode));
                    if (!mounted) return;
                    _showSnack('Invite code copied.');
                  },
            child: Text(
              'Copy code',
              style: TextStyle(color: isDark ? Colors.white : const Color(0xFF000000)),
            ),
          ),
          if (_organizationRole == 'owner')
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _showManageOrganizationDialog();
              },
              child: Text(
                'Manage',
                style: TextStyle(color: isDark ? Colors.white : const Color(0xFF000000)),
              ),
            ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _showOrganizationActivityDialog();
            },
            child: Text(
              'Activity',
              style: TextStyle(color: isDark ? Colors.white : const Color(0xFF000000)),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFF000000),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<bool> _canPurchaseOrganizationTier() async {
    final uid = _authUid;
    if (uid == null || uid.isEmpty) {
      _showSnack('Organisation setup unavailable. Please wait for sign-in and try again.');
      return false;
    }

    final orgId = _organizationId;
    if (orgId == null || orgId.isEmpty) {
      return true;
    }

    try {
      final orgSnap = await FirebaseFirestore.instance
          .collection('organizations')
          .doc(orgId)
          .get();
      if (!orgSnap.exists) {
        return true;
      }

      final data = orgSnap.data() ?? <String, dynamic>{};
      final ownerUid = (data['ownerUid'] as String?)?.trim();
      if (ownerUid != null && ownerUid.isNotEmpty && ownerUid != uid) {
        _showSnack('Only the organisation owner can top up the shared pool.');
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('Organization purchase precheck failed: $e');
      _showSnack('Could not verify organisation access right now.');
      return false;
    }
  }

  Future<_OrganizationPoolUpdate?> _createOrTopUpOrganizationPool(_CreditTier tier) async {
    final userRef = _userDocRef();
    final uid = _authUid;
    if (uid == null || uid.isEmpty || userRef == null) {
      _showSnack('Organisation setup unavailable. Please wait for sign-in and try again.');
      return null;
    }

    final db = FirebaseFirestore.instance;
    var orgId = _organizationId;
    final inviteCode = (_organizationInviteCode != null && _organizationInviteCode!.isNotEmpty)
        ? _organizationInviteCode!
        : _newInviteCode();
    final orgName = (_organizationName != null && _organizationName!.isNotEmpty)
        ? _organizationName!
        : 'My Organisation';

    if (orgId == null || orgId.isEmpty) {
      orgId = db.collection('organizations').doc().id;
    }

    final orgRef = db.collection('organizations').doc(orgId);

    try {
      final update = await db.runTransaction<_OrganizationPoolUpdate>((tx) async {
        final orgSnap = await tx.get(orgRef);
        final now = FieldValue.serverTimestamp();

        if (!orgSnap.exists) {
          tx.set(orgRef, {
            'name': orgName,
            'ownerUid': uid,
            'inviteCode': inviteCode,
            'sharedCredits': tier.secs,
            'tierType': 'organization',
            'createdAt': now,
            'updatedAt': now,
          });
          tx.set(userRef, {
            'organizationId': orgId,
            'organizationRole': 'owner',
            'organizationInviteCode': inviteCode,
            'organizationName': orgName,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          return _OrganizationPoolUpdate(
            action: 'created',
            organizationId: orgId!,
            organizationName: orgName,
            inviteCode: inviteCode,
            sharedCredits: tier.secs,
          );
        } else {
          final data = orgSnap.data() ?? <String, dynamic>{};
          final ownerUid = (data['ownerUid'] as String?)?.trim();
          if (ownerUid != null && ownerUid.isNotEmpty && ownerUid != uid) {
            throw StateError('organization-owner-required');
          }

          final existingName = (data['name'] as String?)?.trim();
          final existingInviteCode = (data['inviteCode'] as String?)?.trim();
          final resolvedName = (existingName != null && existingName.isNotEmpty)
              ? existingName
              : orgName;
          final resolvedInviteCode =
              (existingInviteCode != null && existingInviteCode.isNotEmpty)
                  ? existingInviteCode
                  : inviteCode;
          final currentCredits = (data['sharedCredits'] as num?)?.toInt() ?? 0;
          final nextCredits = currentCredits + tier.secs;
          tx.update(orgRef, {
            'sharedCredits': nextCredits,
            'updatedAt': now,
            'tierType': 'organization',
          });
          tx.set(userRef, {
            'organizationId': orgId,
            'organizationRole': 'owner',
            'organizationInviteCode': resolvedInviteCode,
            'organizationName': resolvedName,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          return _OrganizationPoolUpdate(
            action: 'topped_up',
            organizationId: orgId!,
            organizationName: resolvedName,
            inviteCode: resolvedInviteCode,
            sharedCredits: nextCredits,
          );
        }
      });

      if (!mounted) return null;
      setState(() {
        _organizationId = update.organizationId;
        _organizationRole = 'owner';
        _organizationInviteCode = update.inviteCode;
        _organizationName = update.organizationName;
        _organizationSharedCredits = update.sharedCredits;
      });
      await _refreshOrganizationDetails();
      await _logOrganizationActivity(
        organizationId: update.organizationId,
        action: update.action == 'created' ? 'pool_created' : 'pool_topped_up',
        creditsDelta: tier.secs,
        creditsAfter: update.sharedCredits,
        tierName: tier.name,
      );
      await _showOrganizationOwnerInfo();
      return update;
    } catch (e) {
      debugPrint('Organisation top-up failed: $e');
      if (e is StateError && e.message == 'organization-owner-required') {
        _showSnack('Only the organisation owner can top up the shared pool.');
      } else {
        _showSnack('Could not top up organisation pool right now.');
      }
      return null;
    }
  }

  Future<void> _showOrganizationOwnerInfo() async {
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final code = _organizationInviteCode ?? '-';
    final name = _organizationName ?? 'My Organisation';

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
        surfaceTintColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
        title: Text(
          'Organisation Ready',
          style: TextStyle(color: isDark ? Colors.white : const Color(0xFF000000)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF000000),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Invite code: $code',
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
            ),
            const SizedBox(height: 8),
            Text(
              'Share this code with co-workers or students so they can join your pool.',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (!mounted) return;
              _showSnack('Invite code copied.');
            },
            child: Text('Copy code', style: TextStyle(color: isDark ? Colors.white : const Color(0xFF000000))),
          ),
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFF000000),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _logOrganizationActivity({
    required String organizationId,
    required String action,
    required int creditsDelta,
    int? creditsAfter,
    String? tierName,
    double? amount,
    String? note,
  }) async {
    final uid = _authUid;
    if (uid == null || uid.isEmpty || organizationId.isEmpty) return;

    try {
      await FirebaseFirestore.instance
          .collection('organizations')
          .doc(organizationId)
          .collection('activity')
          .add({
        'action': action,
        'creditsDelta': creditsDelta,
        'creditsAfter': creditsAfter,
        'tierName': tierName,
        'amount': amount,
        'note': note,
        'actorUid': uid,
        'actorRole': _organizationRole,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Organization activity log failed: $e');
    }
  }

  Future<void> _showManageOrganizationDialog() async {
    if (_organizationId == null || _organizationId!.isEmpty || _organizationRole != 'owner') {
      _showSnack('Only organisation owners can manage settings.');
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nameController = TextEditingController(text: _organizationName ?? 'My Organisation');
    bool regenerateInviteCode = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              scrollable: true,
              backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
              surfaceTintColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
              title: Text(
                'Manage Organisation',
                style: TextStyle(color: isDark ? Colors.white : const Color(0xFF000000)),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Organisation name'),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Current code: ${_organizationInviteCode ?? '-'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Regenerating the code will stop the old code from being used for new joins.',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: regenerateInviteCode,
                    onChanged: (value) {
                      setDialogState(() => regenerateInviteCode = value ?? false);
                    },
                    title: Text(
                      'Regenerate invite code',
                      style: TextStyle(color: isDark ? Colors.white : const Color(0xFF000000)),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white : const Color(0xFF000000))),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF000000),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await _updateOrganizationSettings(
                      nameController.text,
                      regenerateInviteCode: regenerateInviteCode,
                    );
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showOrganizationActivityDialog() async {
    final orgId = _organizationId;
    if (orgId == null || orgId.isEmpty) {
      _showSnack('Join an organisation first to view activity.');
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activityStream = FirebaseFirestore.instance
        .collection('organizations')
        .doc(orgId)
        .collection('activity')
        .orderBy('createdAt', descending: true)
        .limit(40)
        .snapshots();

    String formatTimestamp(dynamic value) {
      if (value is Timestamp) {
        final dt = value.toDate().toLocal();
        final y = dt.year.toString().padLeft(4, '0');
        final m = dt.month.toString().padLeft(2, '0');
        final d = dt.day.toString().padLeft(2, '0');
        final hh = dt.hour.toString().padLeft(2, '0');
        final mm = dt.minute.toString().padLeft(2, '0');
        return '$y-$m-$d $hh:$mm';
      }
      return 'Pending time';
    }

    String formatDelta(dynamic value) {
      final amount = (value as num?)?.toInt() ?? 0;
      return amount > 0 ? '+$amount' : amount.toString();
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
        surfaceTintColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
        title: Text(
          'Organisation Activity',
          style: TextStyle(color: isDark ? Colors.white : const Color(0xFF000000)),
        ),
        content: SizedBox(
          width: 520,
          height: 380,
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: activityStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Could not load activity right now.',
                    style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
                    textAlign: TextAlign.center,
                  ),
                );
              }

              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return Center(
                  child: Text(
                    'No activity yet.',
                    style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
                  ),
                );
              }

              return ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (_, __) => Divider(
                  color: isDark ? Colors.white12 : Colors.black12,
                  height: 1,
                ),
                itemBuilder: (context, index) {
                  final data = docs[index].data();
                  final action = (data['action'] as String?) ?? 'activity';
                  final creditsAfter = (data['creditsAfter'] as num?)?.toInt();
                  final tierName = data['tierName'] as String?;
                  final actorRole = (data['actorRole'] as String?) ?? 'member';

                  final subtitleParts = <String>[
                    formatTimestamp(data['createdAt']),
                    'delta ${formatDelta(data['creditsDelta'])}',
                    if (creditsAfter != null) 'pool $creditsAfter',
                    'role ${actorRole.toUpperCase()}',
                    if (tierName != null && tierName.isNotEmpty) 'tier $tierName',
                  ];

                  return ListTile(
                    dense: true,
                    leading: Icon(
                      action == 'credit_spent'
                          ? Icons.remove_circle_outline
                          : (action == 'settings_updated'
                              ? Icons.settings
                              : Icons.add_circle_outline),
                      color: isDark ? Colors.white : const Color(0xFF000000),
                    ),
                    title: Text(
                      action.replaceAll('_', ' '),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF000000),
                      ),
                    ),
                    subtitle: Text(
                      subtitleParts.join(' • '),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFF000000),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateOrganizationSettings(
    String newName, {
    required bool regenerateInviteCode,
  }) async {
    final orgId = _organizationId;
    if (orgId == null || orgId.isEmpty || _organizationRole != 'owner') {
      _showSnack('Only organisation owners can update settings.');
      return;
    }

    final orgRef = FirebaseFirestore.instance.collection('organizations').doc(orgId);
    final trimmedName = newName.trim().isEmpty ? (_organizationName ?? 'My Organisation') : newName.trim();
    final updatedCode = regenerateInviteCode ? _newInviteCode() : _organizationInviteCode;

    try {
      await orgRef.update({
        'name': trimmedName,
        'inviteCode': updatedCode,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final userRef = _userDocRef();
      if (userRef != null) {
        await userRef.set({
          'organizationName': trimmedName,
          'organizationInviteCode': updatedCode,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (!mounted) return;
      setState(() {
        _organizationName = trimmedName;
        _organizationInviteCode = updatedCode;
      });

      _showSnack('Organisation settings updated.');
      await _logOrganizationActivity(
        organizationId: orgId,
        action: 'settings_updated',
        creditsDelta: 0,
        creditsAfter: _organizationSharedCredits,
        note: regenerateInviteCode ? 'name_changed_and_code_regenerated' : 'name_changed',
      );
    } catch (e) {
      debugPrint('Organization settings update failed: $e');
      _showSnack('Could not update organisation settings right now.');
    }
  }

  Future<void> _getAndStoreDeviceId() async {
    try {
      if (_deviceId != null && _deviceId!.isNotEmpty) {
        return; // Already retrieved
      }

      final prefs = await SharedPreferences.getInstance();
      const deviceIdKey = 'device_id_v1';
      
      String? deviceId = prefs.getString(deviceIdKey);
      if (deviceId == null || deviceId.isEmpty) {
        // Get hardware device ID
        final deviceInfo = DeviceInfoPlugin();
        
        if (Platform.isAndroid) {
          final androidInfo = await deviceInfo.androidInfo;
          deviceId = androidInfo.id; // Android ID (persists across uninstalls on most devices)
        } else if (Platform.isIOS) {
          final iosInfo = await deviceInfo.iosInfo;
          deviceId = iosInfo.identifierForVendor; // iOS identifier (persists for same vendor)
        } else {
          deviceId = _generateUUID(); // Fallback for other platforms
        }
        
        if (deviceId != null && deviceId.isNotEmpty) {
          await prefs.setString(deviceIdKey, deviceId);
          debugPrint('Stored device ID: $deviceId');
        }
      }

      if (mounted) {
        setState(() => _deviceId = deviceId);
      } else {
        _deviceId = deviceId;
      }
    } catch (e) {
      debugPrint('Failed to get device ID: $e');
    }
  }

  Future<bool> _hasDeviceUsedFreeTrial() async {
    if (_deviceId == null || _deviceId!.isEmpty) {
      return false;
    }

    try {
      final db = FirebaseFirestore.instance;
      final docRef = db.collection('global_device_installs').doc(_deviceId);
      final docSnapshot = await docRef.get();
      
      return docSnapshot.exists && docSnapshot.data()?['used_free_trial'] == true;
    } catch (e) {
      debugPrint('Failed to check device free trial status: $e');
      return false;
    }
  }

  Future<void> _markDeviceAsUsedFreeTrial() async {
    if (_deviceId == null || _deviceId!.isEmpty) {
      return;
    }

    try {
      final db = FirebaseFirestore.instance;
      final docRef = db.collection('global_device_installs').doc(_deviceId);
      
      await docRef.set({
        'used_free_trial': true,
        'first_seen': FieldValue.serverTimestamp(),
        'last_seen': FieldValue.serverTimestamp(),
        'device_info': {
          'platform': Platform.isAndroid ? 'android' : Platform.isIOS ? 'ios' : 'unknown',
        }
      }, SetOptions(merge: true)).catchError((e) {
        debugPrint('Failed to mark device as used free trial: $e');
      });
    } catch (e) {
      debugPrint('Error marking device free trial: $e');
    }
  }

  Future<void> _checkInstallIdAndFreeTrial() async {
    try {
      // Get device ID (persists across uninstalls)
      await _getAndStoreDeviceId();
      
      await _ensureSignedIn();
      final uid = _authUid;
      if (uid == null || uid.isEmpty) {
        debugPrint('Install ID check skipped: missing auth uid.');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      const installIdKey = 'lets_talk_install_id_v1';
      
      String? installId = prefs.getString(installIdKey);
      if (installId == null) {
        installId = _generateUUID();
        await prefs.setString(installIdKey, installId);
        debugPrint('Generated new install ID: $installId');
      } else {
        debugPrint('Retrieved existing install ID: $installId');
      }

      if (mounted) {
        setState(() => _installId = installId);
      } else {
        _installId = installId;
      }

        final db = FirebaseFirestore.instance;
        final docRef = db
          .collection('users')
          .doc(uid)
          .collection('device_installs')
          .doc(installId);
      final docSnapshot = await docRef.get();
      
      if (docSnapshot.exists && docSnapshot.data()?['used_free_trial'] == true) {
        debugPrint('Install ID $installId already used free trial');
      } else {
        await docRef.set({
          'used_free_trial': true,
          'first_seen': FieldValue.serverTimestamp(),
          'last_seen': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).catchError((e) {
          debugPrint('Failed to record device install: $e');
        });
        debugPrint('Install ID $installId registered for first free trial use');
      }

      await _ensureUserProfileDocument();
      await _loadOrganizationMembership();
    } catch (e) {
      debugPrint('Error checking install ID: $e');
    }
  }

  String _getCacheKey(String text, String language, String voice) {
    final normalized = text.toLowerCase().trim();
    return '${normalized}_${language}_$voice';
  }

  bool _isFirestorePermissionDenied(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('permission-denied') ||
        msg.contains('missing or insufficient permissions');
  }

  Future<String?> _getCachedTranslation(String text, String language) async {
    if (!_enableClientFirestoreCache) return null;
    try {
      final db = FirebaseFirestore.instance;
      final cacheKey = _getCacheKey(text, language, '');
      final docSnapshot = await db
          .collection('cache_translations')
          .doc(cacheKey)
          .get();
      
      if (docSnapshot.exists) {
        final translation = docSnapshot.data()?['translation'] as String?;
        debugPrint('Cache HIT for translation: "$text" -> "$translation"');
        return translation;
      }
      return null;
    } catch (e) {
      if (!_isFirestorePermissionDenied(e)) {
        debugPrint('Error fetching cached translation: $e');
      }
      return null;
    }
  }

  Future<void> _saveCacheTranslation(String text, String language, String translation) async {
    if (!_enableClientFirestoreCache) return;
    try {
      final db = FirebaseFirestore.instance;
      final cacheKey = _getCacheKey(text, language, '');
      await db.collection('cache_translations').doc(cacheKey).set({
        'original_text': text,
        'language': language,
        'translation': translation,
        'cached_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).catchError((e) {
        if (!_isFirestorePermissionDenied(e)) {
          debugPrint('Failed to cache translation: $e');
        }
      });
    } catch (e) {
      if (!_isFirestorePermissionDenied(e)) {
        debugPrint('Error saving cached translation: $e');
      }
    }
  }

  Future<String?> _getCachedAudio(String text, String language, String voice) async {
    if (!_enableClientFirestoreCache) return null;
    try {
      final db = FirebaseFirestore.instance;
      final cacheKey = _getCacheKey(text, language, voice);
      final docSnapshot = await db
          .collection('cache_audio')
          .doc(cacheKey)
          .get();
      
      if (docSnapshot.exists) {
        final audioBase64 = docSnapshot.data()?['audio_base64'] as String?;
        if (audioBase64 != null && audioBase64.isNotEmpty) {
          debugPrint('Cache HIT for audio: "$text" (language=$language, voice=$voice)');
          return audioBase64;
        }
      }
      return null;
    } catch (e) {
      if (!_isFirestorePermissionDenied(e)) {
        debugPrint('Error fetching cached audio: $e');
      }
      return null;
    }
  }

  Future<void> _saveCacheAudio(String text, String language, String voice, String audioBase64) async {
    if (!_enableClientFirestoreCache) return;
    try {
      final db = FirebaseFirestore.instance;
      final cacheKey = _getCacheKey(text, language, voice);
      await db.collection('cache_audio').doc(cacheKey).set({
        'original_text': text,
        'language': language,
        'voice': voice,
        'audio_base64': audioBase64,
        'cached_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).catchError((e) {
        if (!_isFirestorePermissionDenied(e)) {
          debugPrint('Failed to cache audio: $e');
        }
      });
    } catch (e) {
      if (!_isFirestorePermissionDenied(e)) {
        debugPrint('Error saving cached audio: $e');
      }
    }
  }

  Future<void> _configureAudioPlayback() async {
    try {
      await _audioPlayer.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: false,
            contentType: AndroidContentType.speech,
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.gain,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Audio context setup failed: $e');
    }

    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);
      await _audioPlayer.setVolume(1.0);
    } catch (e) {
      debugPrint('Audio release mode setup failed: $e');
    }

  }

  Future<void> _showDisclaimerIfFirstInstall() async {
    final prefs = await SharedPreferences.getInstance();
    const key = 'disclaimerAcceptedV5';
    final accepted = prefs.getBool(key) ?? false;
    if (accepted || !mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF000000),
        surfaceTintColor: const Color(0xFF000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFF7F7F7), width: 2.5),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final wordmarkWidth = (constraints.maxWidth * 0.9).clamp(220.0, 320.0);
                return Center(
                  child: SizedBox(
                    width: wordmarkWidth,
                    child: _buildHeaderWordmark(true),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            const Text(
              'Disclaimer',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: const SingleChildScrollView(
          child: Text(
            _disclaimerText,
            style: TextStyle(color: Colors.white),
          ),
        ),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          Builder(
            builder: (ctx2) {
              return TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Accept and Close', style: TextStyle(color: Colors.black)),
              );
            },
          ),
        ],
      ),
    );
  }

  void _onInputChanged() {
    _autocorrectTimer?.cancel();
    if (_tttController.text.trim().length < 4) return;
    _autocorrectTimer =
        Timer(const Duration(milliseconds: 700), _runAutocorrect);
  }

  Future<void> _runAutocorrect() async {
    final text = _tttController.text;
    if (text.trim().length < 4) return;
    final source = _translateCodes[_selectedInputLang] ?? 'auto';
    final uri = Uri.parse(
      'https://translate.googleapis.com/translate_a/single?client=gtx&sl=$source&tl=en&dt=t&dt=ss&q=${Uri.encodeQueryComponent(text)}',
    );
    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) return;
      final decoded = jsonDecode(response.body) as List?;
      if (decoded == null || decoded.length <= 7) return;
      final ssArr = decoded[7];
      if (ssArr is! List || ssArr.isEmpty) return;
      final corrected = ssArr[0];
      if (corrected is! String || corrected.isEmpty || corrected == text) {
        return;
      }
      _tttController.removeListener(_onInputChanged);
      _tttController.value = TextEditingValue(
        text: corrected,
        selection: TextSelection.collapsed(offset: corrected.length),
      );
      _tttController.addListener(_onInputChanged);
    } catch (_) {}
  }

  Future<void> _initSpeech() async {
    final ok = await _speech.initialize(onError: (e) => debugPrint('STT: $e'));
    setState(() => _speechAvailable = ok);
  }

  void _startListening() async {
    if (!_speechAvailable) {
      _showSnack('Microphone not available');
      return;
    }
    setState(() {
      _isTalking = true;
      _spokenText = '';
      _translatedText = '';
      _phoneticText = '';
      _spokenLang = '';
      _translatedLang = '';
    });
    await _speech.listen(
      onResult: (r) {
        setState(() {
          _spokenRawText = r.recognizedWords;
          _spokenText = _maskProfanityForDisplay(_spokenRawText);
          _spokenLang = _selectedInputLang;
        });
        if (r.finalResult && _spokenRawText.isNotEmpty) {
          _doTranslate(_spokenRawText);
        }
      },
      localeId: _locales[_selectedInputLang] ?? 'en-ZA',
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 20),
    );
  }

  void _stopListening() async {
    await _speech.stop();
    setState(() => _isTalking = false);
  }

  Future<bool> _consumeUsageAllowance() async {
    final orgId = _organizationId;
    if (orgId != null && orgId.isNotEmpty) {
      try {
        final orgRef = FirebaseFirestore.instance.collection('organizations').doc(orgId);
        final remainingCredits = await FirebaseFirestore.instance.runTransaction<int?>((tx) async {
          final snap = await tx.get(orgRef);
          if (!snap.exists) return null;
          final current = (snap.data()?['sharedCredits'] as num?)?.toInt() ?? 0;
          if (current < _organizationUsageCost) {
            return -1;
          }
          final updated = current - _organizationUsageCost;
          tx.update(orgRef, {
            'sharedCredits': updated,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return updated;
        });

        if (remainingCredits == null) {
          _showSnack('Organisation not found.');
          return false;
        }
        if (remainingCredits < 0) {
          _showSnack('Organisation pool is empty. Please top up.');
          _showCreditTiers();
          return false;
        }

        if (mounted) {
          setState(() => _organizationSharedCredits = remainingCredits);
        }
        await _logOrganizationActivity(
          organizationId: orgId,
          action: 'credit_spent',
          creditsDelta: -_organizationUsageCost,
          creditsAfter: remainingCredits,
          note: 'translation',
        );
        _showSnack(
          'Used $_organizationUsageCost org credit | Pool: $remainingCredits remaining',
        );
        return true;
      } catch (e) {
        debugPrint('Organisation pool debit failed: $e');
        _showSnack('Could not use organisation pool.');
        return false;
      }
    }

    // Check if user is trying to use free trial credits and device already used them
    if (_credits == 30) {
      final alreadyUsed = await _hasDeviceUsedFreeTrial();
      if (alreadyUsed) {
        _showSnack('This device already used free trial credits. Please purchase credits to continue.');
        _showCreditTiers();
        return false;
      }
    }

    if (_credits >= _usageCostSecs) {
      setState(() => _credits -= _usageCostSecs);
      
      // Save updated credits to Firestore
      unawaited(_updateCreditsInFirestore());
      
      // Mark device as used free trial when consuming first free credit
      if (_credits < 30) {
        await _markDeviceAsUsedFreeTrial();
        debugPrint('Device marked as used free trial');
      }
      
      _showSnack('Used $_usageCostSecs sec | Balance: $_credits sec remaining');
      return true;
    }
    _showCreditTiers();
    return false;
  }

  Future<void> _doTranslate(String input) async {
    if (!await _consumeUsageAllowance()) {
      return;
    }
    setState(() => _isTranslating = true);
    final result = await _translateText(input);
    if (!mounted) {
      return;
    }

    setState(() {
      _translatedRawText = result;
      _translatedText = _maskProfanityForDisplay(result);
      _translatedLang = _selectedOutputLang;
      _isTranslating = false;
    });

    _history.insert(
        0,
        HistoryItem(
            _selectedInputLang,
            _selectedOutputLang,
            _maskProfanityForDisplay(input),
            _maskProfanityForDisplay(result),
            DateTime.now(),
            phonetic: _phoneticText));
    await _speakTranslatedText(result);
  }

  String _maskProfanityForDisplay(String text) {
    if (text.trim().isEmpty) return text;
    String masked = text.replaceAllMapped(_offensiveWordRegex, (_) => '@#\$');
    masked = masked.replaceAllMapped(_maskedProfanityRegex, (_) => '@#\$');
    for (final pattern in _offensiveFlexibleRegexes) {
      masked = masked.replaceAllMapped(pattern, (_) => '@#\$');
    }
    return masked;
  }

  String _silenceProfanityForSpeech(String text) {
    if (text.trim().isEmpty) return text;
    String silenced = text.replaceAllMapped(_offensiveWordRegex, (_) => '');
    silenced = silenced.replaceAllMapped(_maskedProfanityRegex, (_) => '');
    for (final pattern in _offensiveFlexibleRegexes) {
      silenced = silenced.replaceAllMapped(pattern, (_) => '');
    }
    return silenced.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  bool _containsProfanity(String text) {
    if (text.trim().isEmpty) return false;
    if (_offensiveWordRegex.hasMatch(text)) return true;
    if (_maskedProfanityRegex.hasMatch(text)) return true;
    return _offensiveFlexibleRegexes.any((pattern) => pattern.hasMatch(text));
  }

  Future<String> _translateText(String input) async {
    final source = _translateCodes[_selectedInputLang] ?? 'auto';
    final target = _translateCodes[_selectedOutputLang] ?? 'en';
    final needsPhonetics = _selectedOutputLang == 'Hindi' ||
        _selectedOutputLang == 'Urdu' ||
        _selectedOutputLang == 'Mandarin';

    final cached = await _getCachedTranslation(input, _selectedOutputLang);
    if (cached != null && cached.isNotEmpty) {
      _phoneticText = '';
      return cached;
    }

    final uri = Uri.parse(
      'https://translate.googleapis.com/translate_a/single?client=gtx&sl=$source&tl=$target&dt=t${needsPhonetics ? '&dt=rm' : ''}&q=${Uri.encodeQueryComponent(input)}',
    );

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        _phoneticText = '';
        return input;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is List && decoded.isNotEmpty && decoded[0] is List) {
        final pieces = decoded[0] as List;
        final translated = pieces
            .whereType<List>()
            .map(
                (segment) => segment.isNotEmpty ? segment.first.toString() : '')
            .join();

        if (needsPhonetics) {
          final phonetic = pieces
              .whereType<List>()
              .map((s) =>
                  s.length > 2 && s[2] != null ? s[2].toString().trim() : '')
              .where((s) => s.isNotEmpty)
              .join(' ')
              .trim();
          final fallback =
              (phonetic.isEmpty && decoded.length > 1 && decoded[1] is String)
                  ? (decoded[1] as String).trim()
                  : '';
          _phoneticText = phonetic.isNotEmpty ? phonetic : fallback;
        } else {
          _phoneticText = '';
        }

        final result = translated.trim().isEmpty ? input : translated.trim();
        await _saveCacheTranslation(input, _selectedOutputLang, result);
        return result;
      }
      _phoneticText = '';
      return input;
    } catch (_) {
      _phoneticText = '';
      return input;
    }
  }

  Future<void> _speakText(String text, String language) async {
    if (_containsProfanity(text)) {
      return;
    }

    final safeForSpeech = _silenceProfanityForSpeech(text);
    if (safeForSpeech.trim().isEmpty) return;
    try {
      final provider = _ttsProviderForLanguage(language);
      final voiceName = _voiceNameForLanguage(language);
      final audioData = await _generateAudioWithCache(
        safeForSpeech,
        language,
        voiceName,
        provider: provider,
      );
      if (audioData != null && audioData.isNotEmpty) {
        await _audioPlayer.play(BytesSource(audioData));
      } else {
        _showSnack(_narakeetUnavailableMessage());
      }
    } catch (e) {
      debugPrint('Audio playback error: $e');
      _showSnack('Audio error: $e');
    }
  }

  Future<Uint8List?> _generateAudioWithCache(
      String text, String language, String? voice,
      {required String provider}) async {
    final cacheVoiceKey = '$provider|${voice ?? ''}';
    final cachedBase64 = await _getCachedAudio(text, language, cacheVoiceKey);
    if (cachedBase64 != null) {
      return base64Decode(cachedBase64);
    }

    final audioData = await _translationService.generateTranslation(
      text,
      language,
      voiceName: voice,
      ttsProvider: provider,
    );

    if (audioData != null && audioData.isNotEmpty) {
      final audioBase64 = base64Encode(audioData);
      await _saveCacheAudio(text, language, cacheVoiceKey, audioBase64);
    }

    return audioData;
  }

  Future<void> _speakTranslatedText(String text) async {
    if (_containsProfanity(text)) {
      return;
    }

    final safeForSpeech = _silenceProfanityForSpeech(text);
    if (safeForSpeech.trim().isEmpty) {
      return;
    }

    final Stopwatch ttsStopwatch = Stopwatch()..start();

    try {
      setState(() => _isPlayingAudio = true);

      final provider = _ttsProviderForLanguage(_selectedOutputLang);
      final voiceName = _voiceNameForLanguage(_selectedOutputLang);
      final chunks = _buildRealtimeSpeechChunks(safeForSpeech);
      if (chunks.isEmpty) {
        _showSnack(_narakeetUnavailableMessage());
        return;
      }

      final chunkRequests = chunks
          .map((chunk) {
            return _generateAudioWithCache(
              chunk,
              _selectedOutputLang,
              voiceName,
              provider: provider,
            );
          })
          .toList(growable: false);

      bool playedAny = false;
      await _audioPlayer.stop();

      for (int i = 0; i < chunkRequests.length; i++) {
        final audioData = await chunkRequests[i].timeout(
          i == 0 ? _firstChunkFetchTimeout : _nextChunkFetchTimeout,
          onTimeout: () => null,
        );
        if (audioData == null || audioData.isEmpty) {
          continue;
        }

        await _audioPlayer.play(BytesSource(audioData));
        playedAny = true;

        try {
          await _audioPlayer.onPlayerComplete.first
              .timeout(const Duration(seconds: 45));
        } catch (_) {}
      }

      ttsStopwatch.stop();
      if (playedAny) {
        _showSnack('${(ttsStopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2)} seconds');
      }

      if (!playedAny) {
        _showSnack(_narakeetUnavailableMessage());
      }
    } catch (e) {
      _showSnack('Narakeet audio error. Please try again.');
    } finally {
      setState(() => _isPlayingAudio = false);
    }
  }

  List<String> _buildRealtimeSpeechChunks(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return const [];

    final sentences = normalized
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final chunks = <String>[];
    var maxChars = _firstSpeechChunkMaxChars;

    for (final sentence in sentences) {
      if (sentence.length <= maxChars) {
        chunks.add(sentence);
        maxChars = _speechChunkMaxChars;
        continue;
      }

      final words = sentence.split(' ');
      var buffer = StringBuffer();

      for (final word in words) {
        final candidate = buffer.isEmpty ? word : '${buffer.toString()} $word';
        if (candidate.length > maxChars && buffer.isNotEmpty) {
          chunks.add(buffer.toString());
          maxChars = _speechChunkMaxChars;
          buffer = StringBuffer(word);
        } else {
          buffer = StringBuffer(candidate);
        }
      }

      if (buffer.isNotEmpty) {
        chunks.add(buffer.toString());
        maxChars = _speechChunkMaxChars;
      }
    }

    return chunks;
  }

  void _submitTTT() {
    final t = _tttController.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _spokenRawText = t;
      _spokenText = _maskProfanityForDisplay(t);
      _spokenLang = _selectedInputLang;
      _translatedRawText = '';
      _translatedText = '';
      _phoneticText = '';
      _translatedLang = '';
    });
    _doTranslate(t);
    _tttController.clear();
    FocusScope.of(context).unfocus();
  }

  void _resetOutput() => setState(() {
        _spokenText = '';
      _spokenRawText = '';
        _translatedText = '';
      _translatedRawText = '';
        _phoneticText = '';
        _spokenLang = '';
        _translatedLang = '';
      });

  Future<void> _shareCurrentTranslationPackage() async {
    final inputDisplay = _spokenText.trim();
    final outputDisplay = _translatedText.trim();
    if (inputDisplay.isEmpty || outputDisplay.isEmpty) {
      _showSnack('Translate first so input and output can be shared.');
      return;
    }

    if (_sharingCurrentTranslation) return;
    setState(() => _sharingCurrentTranslation = true);

    try {
      final inputRaw = _spokenRawText.trim().isNotEmpty ? _spokenRawText.trim() : inputDisplay;
      final outputRaw =
          _translatedRawText.trim().isNotEmpty ? _translatedRawText.trim() : outputDisplay;
      final inputLang = _spokenLang.isNotEmpty ? _spokenLang : _selectedInputLang;
      final outputLang = _translatedLang.isNotEmpty ? _translatedLang : _selectedOutputLang;
      final dir = await getTemporaryDirectory();
      final nowSuffix = DateTime.now().millisecondsSinceEpoch;

      final payload = StringBuffer()
        ..writeln('Let\'s Talk Translation')
        ..writeln()
        ..writeln('Input ($inputLang):')
        ..writeln(inputDisplay)
        ..writeln()
        ..writeln('Output ($outputLang):')
        ..writeln(outputDisplay);

      if (_phoneticText.trim().isNotEmpty) {
        payload
          ..writeln()
          ..writeln('Phonetics:')
          ..writeln(_phoneticText.trim());
      }

      final files = <XFile>[];

      final inputProvider = _ttsProviderForLanguage(inputLang);
      final inputVoice = _voiceNameForLanguage(inputLang);
      final safeInputForSpeech = _silenceProfanityForSpeech(inputRaw);
      final inputSpeechText =
          safeInputForSpeech.isNotEmpty ? safeInputForSpeech : inputRaw;
      var hasInputMp3 = false;
      if (inputSpeechText.isNotEmpty) {
        var inputAudio = await _generateAudioWithCache(
          inputSpeechText,
          inputLang,
          inputVoice,
          provider: inputProvider,
        );
        inputAudio ??= await _translationService.generateTranslation(
          inputSpeechText,
          inputLang,
          voiceName: inputVoice,
          ttsProvider: inputProvider,
        );
        if (inputAudio != null && inputAudio.isNotEmpty) {
          final inFile = File('${dir.path}/lets_talk_input_$nowSuffix.mp3');
          await inFile.writeAsBytes(inputAudio, flush: true);
          files.add(XFile(inFile.path, mimeType: 'audio/mpeg'));
          hasInputMp3 = true;
        }
      }

      final outputProvider = _ttsProviderForLanguage(outputLang);
      final outputVoice = _voiceNameForLanguage(outputLang);
      final safeOutputForSpeech = _silenceProfanityForSpeech(outputRaw);
      final outputSpeechText =
          safeOutputForSpeech.isNotEmpty ? safeOutputForSpeech : outputRaw;
      var hasOutputMp3 = false;
      if (outputSpeechText.isNotEmpty) {
        var outputAudio = await _generateAudioWithCache(
          outputSpeechText,
          outputLang,
          outputVoice,
          provider: outputProvider,
        );
        outputAudio ??= await _translationService.generateTranslation(
          outputSpeechText,
          outputLang,
          voiceName: outputVoice,
          ttsProvider: outputProvider,
        );
        if (outputAudio != null && outputAudio.isNotEmpty) {
          final outFile = File('${dir.path}/lets_talk_output_$nowSuffix.mp3');
          await outFile.writeAsBytes(outputAudio, flush: true);
          files.add(XFile(outFile.path, mimeType: 'audio/mpeg'));
          hasOutputMp3 = true;
        }
      }

      if (!hasInputMp3 || !hasOutputMp3) {
        _showSnack('Could not generate both input and output MP3 files. Please try again.');
        return;
      }

      final inputTextFile = File('${dir.path}/lets_talk_input_$nowSuffix.txt');
      await inputTextFile.writeAsString(
        'Input Language: $inputLang\n\n$inputDisplay\n',
        flush: true,
      );
      files.add(XFile(inputTextFile.path, mimeType: 'text/plain'));

      final outputTextFile = File('${dir.path}/lets_talk_output_$nowSuffix.txt');
      await outputTextFile.writeAsString(
        'Output Language: $outputLang\n\n$outputDisplay\n',
        flush: true,
      );
      files.add(XFile(outputTextFile.path, mimeType: 'text/plain'));

      await Share.shareXFiles(
        files,
        subject: 'Let\'s Talk Translation',
        text: payload.toString(),
      );
    } catch (e) {
      debugPrint('Share translation package error: $e');
      _showSnack('Could not prepare share package. Try again.');
    } finally {
      if (mounted) {
        setState(() => _sharingCurrentTranslation = false);
      }
    }
  }

  void _showSnack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  m,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      );

  Future<void> _sendHistoryToLearn(HistoryItem item) async {
    final phonetic = (item.phonetic ?? '').trim();
    final normalizedOutputLang = _normalizeLanguageLabel(item.outputLang);
    final sent = await _sendToLearnMultipleLangs(
      translated: item.translated,
      original: item.original,
      phonetic: phonetic,
      langs: [normalizedOutputLang],
    );
    if (sent) {
      setState(() {
        _selectedLearnLang = normalizedOutputLang;
        _activeTab = 'learn';
      });
    }
  }

  String _narakeetUnavailableMessage() =>
      'Narakeet unavailable. Check connection & try again.';

  void _showQrShare() {
    const appUrl = 'https://dummy.link/letstalk';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor:
            isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
        surfaceTintColor:
            isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Share App',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black26,
                        blurRadius: 8,
                        offset: const Offset(0, 2))
                  ],
                ),
                padding: const EdgeInsets.all(12),
                child: QrImageView(
                  data: appUrl,
                  version: QrVersions.auto,
                  size: 200,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF000000),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF000000),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Let\'s Talk',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : const Color(0xFF000000))),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
                child: const Text('Close', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreditTiers() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Material(
          color: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
          surfaceTintColor:
              isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
          child: SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.9,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
              Row(
                children: [
                  Icon(Icons.account_balance_wallet,
                      color: isDark ? Colors.white : const Color(0xFF000000)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Credit Packages',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF000000),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Center(
                      child: Column(
                        children: [
                          Text(
                            'Translations capped',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          Text(
                            'at 5 seconds',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Chip(
                    label: Text(
                      _organizationId != null && _organizationId!.isNotEmpty
                          ? 'Org Pool: ${_organizationSharedCredits ?? 0} credits'
                          : 'Balance: $_credits sec',
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF000000),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    backgroundColor: isDark ? Colors.black : Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ..._tiers.map((tier) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? Colors.white10 : Colors.black,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showPaymentGateways(tier);
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              tier.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            tier.name == _organizationTierName
                                ? '${tier.secs} credits'
                                : '${tier.secs} sec',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            tier.price,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showPaymentGateways(_CreditTier tier) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Material(
          color: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
          surfaceTintColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
          child: SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.9,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                    'Choose Payment Gateway',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF000000),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tier.name == _organizationTierName
                        ? '${tier.name} • ${tier.secs} credits • ${tier.price}'
                        : '${tier.name} • ${tier.secs} sec • ${tier.price}',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? Colors.white10 : Colors.black,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 108),
                        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _startPaystackTierPayment(tier);
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset('assets/paystack.png', width: 46, height: 46),
                          const SizedBox(width: 16),
                          const Text(
                            'Paystack',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? Colors.white10 : Colors.black,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 108),
                        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _startPayPalTierPayment(tier);
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset('assets/paypal.png', width: 46, height: 46),
                          const SizedBox(width: 16),
                          const Text(
                            'PayPal',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  double _tierAmountFromPrice(String price) {
    final cleaned = price.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(cleaned) ?? 0;
  }

  bool _allowPaystackSandboxSimulation() {
    final raw = (dotenv.env['PAYSTACK_SANDBOX_BYPASS'] ?? '').trim().toLowerCase();
    final enabledByEnv = raw == '1' || raw == 'true' || raw == 'yes' || raw == 'on';
    return kDebugMode || enabledByEnv;
  }

  Future<void> _completeTierPurchase(
    _CreditTier tier, {
    required double amount,
    required String status,
    required String reference,
  }) async {
    if (!mounted) return;

    if (tier.name == _organizationTierName) {
      final orgUpdate = await _createOrTopUpOrganizationPool(tier);
      if (orgUpdate == null) return;
      _showSnack(
        orgUpdate.action == 'created'
            ? 'Organisation created with ${tier.secs} shared credits (${tier.name}) [Paystack Sandbox].'
            : 'Organisation pool topped up: ${tier.secs} credits (${tier.name}) [Paystack Sandbox].',
      );
    } else {
      setState(() => _credits += tier.secs);
      // Save updated credits to Firestore after purchase
      unawaited(_updateCreditsInFirestore());
      _showSnack('Credits added: ${tier.secs} sec (${tier.name}) [Paystack Sandbox].');
    }

    try {
      await FirebaseFirestore.instance.collection('payment_events').add({
        'userId': _authUid,
        'organizationId': _organizationId,
        'tierName': tier.name,
        'secondsAdded': tier.secs,
        'amountPaid': amount,
        'status': status,
        'reference': reference,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Do not block crediting if telemetry logging fails.
    }
  }

  Future<void> _simulatePaystackSandboxPayment(
    _CreditTier tier,
    double amount,
  ) async {
    final ref = 'SIM-${DateTime.now().millisecondsSinceEpoch}';
    await _completeTierPurchase(
      tier,
      amount: amount,
      status: 'completed_sandbox_paystack_simulated',
      reference: ref,
    );
  }

  void _startPaystackTierPayment(_CreditTier tier) async {
    final paymentReady = await _ensurePaymentReadyAccount();
    if (!paymentReady) return;

    if (tier.name == _organizationTierName) {
      final allowed = await _canPurchaseOrganizationTier();
      if (!allowed) return;
    }

    final amount = _tierAmountFromPrice(tier.price);

    String? accessCode = dotenv.env['PAYSTACK_TEST_ACCESS_CODE'];
    accessCode = (accessCode != null && accessCode.trim().isNotEmpty)
        ? accessCode.trim()
        : await _requestPaystackAccessCode(tier, amount);

    if (accessCode == null || accessCode.isEmpty) {
      if (_allowPaystackSandboxSimulation()) {
        try {
          _showSnack(
            'Paystack backend unavailable. Running simulated sandbox payment.',
          );
          await _simulatePaystackSandboxPayment(tier, amount);
        } catch (e) {
          debugPrint('Sandbox simulation error: $e');
          _showSnack('Sandbox simulation failed: ${e.toString()}');
        }
      } else {
        _showSnack(
          'Could not get Paystack sandbox access code.',
        );
      }
      return;
    }

    try {
      final response = await Paystack().launch(accessCode);
      final isSuccess = response.status.toLowerCase() == 'success';

      if (isSuccess) {
        await _completeTierPurchase(
          tier,
          amount: amount,
          status: 'completed_sandbox_paystack',
          reference: response.reference,
        );
      } else {
        _showSnack('Payment failed: ${response.message}');
      }
    } catch (e) {
      debugPrint('Paystack error: $e');
      _showSnack('Payment error: ${e.toString()}');
    }
  }

  void _startPayPalTierPayment(_CreditTier tier) {
    _showSnack('PayPal integration coming soon. Use Paystack for now.');
  }
  Widget _buildHeaderWordmark(bool isDark) {
    final titleColor = isDark ? Colors.white : const Color(0xFF1F2D40);
    final subtitleColor = isDark ? Colors.white70 : const Color(0xFF2C3A4B);

    return SizedBox(
      height: 88,
      child: AspectRatio(
        aspectRatio: 616 / 218,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: isDark
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF0D1A2A),
                      Color(0xFF08111B),
                      Color(0xFF03070D),
                    ],
                  ),
                )
              : null,
          child: FittedBox(
            fit: BoxFit.contain,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'let\'s talk',
                  style: TextStyle(
                    color: titleColor,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w900,
                    fontSize: 120,
                    height: 1.02,
                    letterSpacing: 0.6,
                    shadows: [
                      Shadow(
                        color: Colors.black.withOpacity(isDark ? 0.65 : 0.28),
                        blurRadius: 0,
                        offset: const Offset(1, 0),
                      ),
                      Shadow(
                        color: Colors.black.withOpacity(isDark ? 0.65 : 0.28),
                        blurRadius: 0,
                        offset: const Offset(-1, 0),
                      ),
                      Shadow(
                        color: Colors.black.withOpacity(isDark ? 0.65 : 0.28),
                        blurRadius: 0,
                        offset: const Offset(0, 1),
                      ),
                      Shadow(
                        color: Colors.black.withOpacity(isDark ? 0.65 : 0.28),
                        blurRadius: 0,
                        offset: const Offset(0, -1),
                      ),
                      Shadow(
                        color: Colors.black.withOpacity(isDark ? 0.7 : 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'SOUTH AFRICA',
                  style: TextStyle(
                    color: subtitleColor,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w800,
                    fontSize: 48,
                    letterSpacing: 3.0,
                    height: 1,
                    shadows: [
                      Shadow(
                        color: Colors.black.withOpacity(isDark ? 0.55 : 0.2),
                        blurRadius: 0,
                        offset: const Offset(1, 0),
                      ),
                      Shadow(
                        color: Colors.black.withOpacity(isDark ? 0.55 : 0.2),
                        blurRadius: 0,
                        offset: const Offset(-1, 0),
                      ),
                      Shadow(
                        color: Colors.black.withOpacity(isDark ? 0.65 : 0.2),
                        blurRadius: 5,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final pageName = _activeTab == 'history'
        ? 'History'
        : (_activeTab == 'learn' ? 'Learn' : 'Translate');
    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          onHorizontalDragEnd: (details) {
            // Improved swipe logic:
            // - If on Translate and swipe left: go to History if not empty, else go to Learn
            // - If on History and swipe left: go to Learn
            // - If on History and swipe right: go to Translate
            // - If on Learn and swipe right: go to History if not empty, else go to Translate
            if (_activeTab == 'translate' && details.primaryVelocity != null && details.primaryVelocity! < -200) {
              if (_history.isNotEmpty) {
                setState(() => _activeTab = 'history');
              } else {
                setState(() => _activeTab = 'learn');
              }
            } else if (_activeTab == 'history' && details.primaryVelocity != null) {
              if (details.primaryVelocity! < -200) {
                setState(() => _activeTab = 'learn');
              } else if (details.primaryVelocity! > 200) {
                setState(() => _activeTab = 'translate');
              }
            } else if (_activeTab == 'learn' && details.primaryVelocity != null && details.primaryVelocity! > 200) {
              if (_history.isNotEmpty) {
                setState(() => _activeTab = 'history');
              } else {
                setState(() => _activeTab = 'translate');
              }
            }
          },
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(
                opacity: animation,
                child: child,
              );
            },
            layoutBuilder: (currentChild, previousChildren) => Stack(
              children: [
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            ),
            child: KeyedSubtree(
              key: ValueKey(_activeTab),
              child: Column(children: [
          // Top bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: SizedBox(
              height: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: PopupMenuButton<String>(
                      icon: Icon(Icons.menu, color: isDark ? Colors.white : Colors.black),
                      tooltip: 'Menu',
                      color: isDark ? const Color(0xFF222222) : Colors.white,
                      surfaceTintColor: isDark ? const Color(0xFF222222) : Colors.white,
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'about',
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, size: 18, color: isDark ? Colors.white : Colors.black),
                              const SizedBox(width: 12),
                              Text('About', style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'translate',
                          child: Row(
                            children: [
                              Icon(Icons.translate, size: 18, color: isDark ? Colors.white : Colors.black),
                              const SizedBox(width: 12),
                              Text('Translate', style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'history',
                          child: Row(
                            children: [
                              Icon(Icons.history, size: 18, color: isDark ? Colors.white : Colors.black),
                              const SizedBox(width: 12),
                              Text('History', style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'learn',
                          child: Row(
                            children: [
                              Icon(Icons.school, size: 18, color: isDark ? Colors.white : Colors.black),
                              const SizedBox(width: 12),
                              Text('Learn', style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'theme',
                          child: Row(
                            children: [
                              Icon(
                                isDark ? Icons.light_mode : Icons.dark_mode,
                                size: 18,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                isDark ? 'Light Mode' : 'Dark Mode',
                                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                              ),
                            ],
                          ),
                        ),
                      ],
                      onSelected: (value) {
                        if (value == 'about') {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('About'),
                              content: const Text(
                                "'Let’s Talk' helps you instantly translate South African languages out loud. Just speak slowly and clearly while pressing the 'Talk' button, then instantly share translations with friends, save phrases to your Learn tab for practice, and easily manage your translation history."
                              ),
                              actions: [
                                Builder(
                                  builder: (ctx2) {
                                    final isDark = Theme.of(ctx2).brightness == Brightness.dark;
                                    return TextButton(
                                      style: TextButton.styleFrom(
                                        backgroundColor: const Color(0xFF000000),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      ),
                                      onPressed: () => Navigator.of(ctx).pop(),
                                      child: const Text('Close'),
                                    );
                                  },
                                ),
                              ],
                            ),
                          );
                        } else if (value == 'translate') {
                          setState(() => _activeTab = 'translate');
                        } else if (value == 'history') {
                          setState(() => _activeTab = 'history');
                        } else if (value == 'learn') {
                          setState(() => _activeTab = 'learn');
                        } else if (value == 'theme') {
                          widget.onToggleTheme();
                        }
                      },
                    ),
                  ),
                  Center(
                    child: _buildHeaderWordmark(isDark),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: PopupMenuButton<int>(
                      tooltip: 'User menu',
                      icon: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundImage: _getUserProfileImage(),
                            backgroundColor: isDark ? Colors.white12 : Colors.black,
                            child: _getUserProfileImage() == null
                                ? Icon(
                                    Icons.person,
                                    size: 17,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                          if (!_isAnonymousUser())
                            const Positioned(
                              right: -1,
                              bottom: -1,
                              child: CircleAvatar(
                                radius: 5,
                                backgroundColor: Color(0xFF17C964),
                              ),
                            ),
                        ],
                      ),
                      color: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
                      surfaceTintColor:
                          isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
                      offset: const Offset(0, 40),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      itemBuilder: (context) {
                        final isDark = Theme.of(context).brightness == Brightness.dark;
                        return [
                          PopupMenuItem(
                            value: 1,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundImage: _getUserProfileImage(),
                                      backgroundColor: isDark ? Colors.grey[400] : Colors.black,
                                      child: _getUserProfileImage() == null
                                          ? Icon(Icons.person, size: 24, color: Colors.white)
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('User', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF000000))),
                                        Text(_displayUserIdentity(), style: TextStyle(fontSize: 12, color: isDark ? Colors.grey : Colors.black54)),
                                        Text(_authStatusLabel(), style: TextStyle(fontSize: 11, color: isDark ? Colors.white70 : Colors.black54)),
                                      ],
                                    ),
                                  ],
                                ),
                                const Divider(height: 18),
                                if (_isAnonymousUser())
                                  ListTile(
                                    leading: Icon(Icons.login, color: isDark ? Colors.white : Colors.black),
                                    title: Text('Sign In', style: TextStyle(color: isDark ? Colors.white : const Color(0xFF000000))),
                                    subtitle: Text(
                                      'Google or email for payments and organisation ownership',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark ? Colors.white70 : Colors.black54,
                                      ),
                                    ),
                                    onTap: () {
                                      Navigator.pop(context);
                                      _showAuthOptionsDialog();
                                    },
                                  ),
                                if (!_isAnonymousUser())
                                  ListTile(
                                    leading: Icon(Icons.logout, color: isDark ? Colors.white : Colors.black),
                                    title: Text('Sign Out', style: TextStyle(color: isDark ? Colors.white : const Color(0xFF000000))),
                                    subtitle: Text(
                                      'Return to a guest session on this device',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark ? Colors.white70 : Colors.black54,
                                      ),
                                    ),
                                    onTap: () {
                                      Navigator.pop(context);
                                      _signOutToGuest();
                                    },
                                  ),
                                ListTile(
                                  leading: Icon(Icons.qr_code_2, color: isDark ? Colors.white : Colors.black),
                                  title: Text('Share App', style: TextStyle(color: isDark ? Colors.white : const Color(0xFF000000))),
                                  onTap: () {
                                    Navigator.pop(context);
                                    _showQrShare();
                                  },
                                ),
                                ListTile(
                                  leading: Icon(Icons.account_balance_wallet, color: isDark ? Colors.white : Colors.black),
                                  title: Text('Credits', style: TextStyle(color: isDark ? Colors.white : const Color(0xFF000000))),
                                  onTap: () {
                                    Navigator.pop(context);
                                    _showCreditTiers();
                                  },
                                ),
                                ListTile(
                                  leading: Icon(Icons.groups, color: isDark ? Colors.white : Colors.black),
                                  title: Text(
                                    _organizationId != null && _organizationId!.isNotEmpty
                                        ? 'Organisation'
                                        : 'Join Organisation',
                                    style: TextStyle(color: isDark ? Colors.white : const Color(0xFF000000)),
                                  ),
                                  subtitle: Text(
                                    _organizationId != null && _organizationId!.isNotEmpty
                                        ? '${_organizationName ?? 'Organisation'} • ${_organizationRole.toUpperCase()} • ${_organizationSharedCredits ?? 0} credits'
                                        : 'Use invite code to join a shared pool',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? Colors.white70 : Colors.black54,
                                    ),
                                  ),
                                  onTap: () {
                                    Navigator.pop(context);
                                    if (_organizationId != null && _organizationId!.isNotEmpty) {
                                      _showOrganizationStatusDialog();
                                    } else {
                                      _showJoinOrganizationDialog();
                                    }
                                  },
                                ),
                                if (_organizationId != null && _organizationId!.isNotEmpty)
                                  ListTile(
                                    leading: Icon(Icons.history, color: isDark ? Colors.white : Colors.black),
                                    title: Text(
                                      'Organisation Activity',
                                      style: TextStyle(color: isDark ? Colors.white : const Color(0xFF000000)),
                                    ),
                                    subtitle: Text(
                                      'View recent pool top-ups and spend',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark ? Colors.white70 : Colors.black54,
                                      ),
                                    ),
                                    onTap: () {
                                      Navigator.pop(context);
                                      _showOrganizationActivityDialog();
                                    },
                                  ),
                                if (_organizationRole == 'owner')
                                  ListTile(
                                    leading: Icon(Icons.manage_accounts, color: isDark ? Colors.white : Colors.black),
                                    title: Text(
                                      'Manage Organisation',
                                      style: TextStyle(color: isDark ? Colors.white : const Color(0xFF000000)),
                                    ),
                                    subtitle: Text(
                                      'Rename or regenerate invite code',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark ? Colors.white70 : Colors.black54,
                                      ),
                                    ),
                                    onTap: () {
                                      Navigator.pop(context);
                                      _showManageOrganizationDialog();
                                    },
                                  ),
                                ListTile(
                                  leading: Icon(Icons.info_outline,
                                      color: isDark ? Colors.white : Colors.black),
                                  title: Text('Disclaimer',
                                      style: TextStyle(
                                          color: isDark
                                              ? Colors.white
                                              : const Color(0xFF000000))),
                                  onTap: () {
                                    Navigator.pop(context);
                                    _showDisclaimerInfo();
                                  },
                                ),
                                // Add more user actions here if needed
                              ],
                            ),
                          ),
                        ];
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _activeTab = 'translate'),
                    child: Container(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Translate',
                        style: TextStyle(
                          fontSize: _activeTab == 'translate' ? 14 : 11,
                          fontWeight: FontWeight.w700,
                          color: _activeTab == 'translate'
                              ? (isDark ? Colors.white : Colors.black)
                              : (isDark ? Colors.white54 : Colors.black54),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _activeTab = 'history'),
                    child: Container(
                      alignment: Alignment.center,
                      child: Text(
                        'History',
                        style: TextStyle(
                          fontSize: _activeTab == 'history' ? 14 : 11,
                          fontWeight: FontWeight.w700,
                          color: _activeTab == 'history'
                              ? (isDark ? Colors.white : Colors.black)
                              : (isDark ? Colors.white54 : Colors.black54),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _activeTab = 'learn'),
                    child: Container(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Learn',
                        style: TextStyle(
                          fontSize: _activeTab == 'learn' ? 14 : 11,
                          fontWeight: FontWeight.w700,
                          color: _activeTab == 'learn'
                              ? (isDark ? Colors.white : Colors.black)
                              : (isDark ? Colors.white54 : Colors.black54),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: _activeTab == 'translate'
                ? _buildTranslateTab(isDark)
                : (_activeTab == 'history'
                    ? _buildHistoryTab(isDark)
                    : _buildLearnTab(isDark)),
          ),
        ]),
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmClearSentFromHistory() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          title: const Text('sure?'),
          content: const Text(
            'This will delete the phrase sent from History on the Learn page.',
          ),
          backgroundColor:
              isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
          surfaceTintColor:
              isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white : Color(0xFF000000))),
            ),
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF000000),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Clear', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  Widget _buildLearnTab(bool isDark) {
    final learnPhraseKey = _selectedLearnLang;
    final userPhrases = _userLearnPhrasesByLang[learnPhraseKey] ?? [];
    final defaultPhrases = _learnPhrasesByLang[learnPhraseKey] ?? _learnPhrasesByLang['English']!;
    final phrases = [
      ...userPhrases,
      ...defaultPhrases.where((def) => !userPhrases.any((u) => u['text'] == def['text'])),
    ]; // Avoid duplicate default if user added same
    final currentLearnText = _learnFocusTextByLang[_selectedLearnLang] ?? '';
    final hasHistoryFocus = currentLearnText.trim().isNotEmpty;
    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Center(
            child: Text(
              'Learn Everyday Phrases',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF000000),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _langDrop(
            _selectedLearnLang,
            _outputLangs,
            (v) => setState(() => _selectedLearnLang = v!),
            isDark,
          ),
          const SizedBox(height: 14),
          ...phrases.asMap().entries.map((entry) {
            final idx = entry.key;
            final phrase = entry.value;
            final isUserPhrase = idx < userPhrases.length;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? Colors.white12 : const Color(0xFFE3F0FF), // soft blue pastel
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? Colors.white24 : Colors.black26,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          phrase['text'] ?? '',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: isDark ? Colors.white : const Color(0xFF000000),
                          ),
                        ),
                        if ((phrase['phonetic'] ?? '').isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            phrase['phonetic']!,
                            style: TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: isDark ? Colors.white70 : const Color(0xFF000000),
                            ),
                          ),
                        ],
                        const SizedBox(height: 3),
                        Text(
                          phrase['en'] ?? '',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.white60
                                : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.volume_up),
                    tooltip: 'Listen',
                    onPressed: () =>
                        _speakText(phrase['text'] ?? '', _selectedLearnLang),
                  ),
                  if (isUserPhrase)
                    IconButton(
                      icon: Icon(Icons.close, color: isDark ? Colors.white70 : Colors.black54),
                      tooltip: 'Delete',
                      onPressed: () => _deleteUserPhrase(idx),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    ),
    // Bottom left home icon
    Positioned(
      bottom: 18,
      right: 18,
      child: FloatingActionButton(
        heroTag: 'learn_home',
        mini: true,
        backgroundColor: isDark ? Colors.white12 : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black,
        elevation: 2,
        onPressed: () => setState(() => _activeTab = 'translate'),
        tooltip: 'Home',
        child: const Icon(Icons.home),
      ),
    ),
  ],
);
  }

  Widget _buildTranslateTab(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxHeight = (constraints.maxHeight - 260) * 0.42;
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 8),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Input box
                  GestureDetector(
                    onTap: () {
                      FocusScope.of(context).requestFocus(_inputFocusNode);
                    },
                    child: Container(
                      width: double.infinity,
                      height: boxHeight,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white12 : const Color(0xFFE0F8D8),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: isDark ? Colors.white24 : Colors.black26),
                      ),
                      child: Stack(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: _langDrop(
                                      _selectedInputLang,
                                      _inputLangs,
                                      (v) {
                                        setState(() {
                                          _selectedInputLang = v!;
                                          _spokenText = '';
                                          _spokenRawText = '';
                                          _translatedText = '';
                                          _translatedRawText = '';
                                          _phoneticText = '';
                                          _tttController.clear();
                                        });
                                      },
                                      isDark,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Expanded(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // Text area (with padding to avoid wall)
                                    Expanded(
                                      child: Stack(
                                        children: [
                                          if (_spokenText.isNotEmpty && _tttController.text.isEmpty)
                                            Align(
                                              alignment: Alignment.topLeft,
                                              child: Text(
                                                _spokenText,
                                                style: TextStyle(
                                                  fontFamily: 'monospace',
                                                  fontSize: 14,
                                                  color: isDark ? Colors.white : Colors.black,
                                                ),
                                              ),
                                            ),
                                          Align(
                                            alignment: Alignment.topLeft,
                                            child: TextField(
                                              controller: _tttController,
                                              focusNode: _inputFocusNode,
                                              autofocus: false,
                                              enableSuggestions: true,
                                              autocorrect: true,
                                              keyboardType: TextInputType.multiline,
                                              textCapitalization: TextCapitalization.sentences,
                                              cursorColor: isDark ? Colors.white : Colors.black,
                                              style: TextStyle(
                                                fontFamily: 'monospace',
                                                fontSize: 14,
                                                color: isDark ? Colors.white : Colors.black,
                                              ),
                                              decoration: const InputDecoration(
                                                border: InputBorder.none,
                                                hintText: '',
                                                isDense: true,
                                                contentPadding: EdgeInsets.zero,
                                              ),
                                              minLines: 1,
                                              maxLines: 3,
                                              readOnly: true,
                                              onChanged: (_) => setState(() {}),
                                              onSubmitted: (_) => _submitTTT(),
                                              textInputAction: TextInputAction.newline,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Wall to the right
                                    Container(
                                      width: 32,
                                      color: Colors.transparent,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          // Replay icon (bottom right)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: IconButton(
                              icon: const Icon(Icons.replay, size: 26),
                              tooltip: 'Replay Input',
                              color: isDark ? Colors.white : Colors.black,
                              onPressed: _spokenText.isNotEmpty
                                  ? () => _speakText(_spokenText, _selectedInputLang)
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // SWAP BUTTON (moved up by 4px)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Center(
                      child: Transform.translate(
                        offset: const Offset(0, -4), // Move up by 4 pixels
                        child: Material(
                          color: isDark ? Colors.black : Colors.white,
                          shape: const CircleBorder(),
                          elevation: 2,
                          child: IconButton(
                            icon: Icon(
                              Icons.swap_vert,
                              size: 36,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                            tooltip: 'Swap languages',
                            onPressed: () => setState(() {
                              final tmp = _selectedInputLang;
                              _selectedInputLang = _selectedOutputLang;
                              _selectedOutputLang = tmp;
                            }),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Output box
                  Container(
                    width: double.infinity,
                    height: boxHeight,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white12 : const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isDark ? Colors.white24 : Colors.black26),
                    ),
                    child: Stack(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: _langDrop(
                                    _selectedOutputLang,
                                    _outputLangs,
                                    (v) {
                                      setState(() {
                                        _selectedOutputLang = v!;
                                        _spokenText = '';
                                        _spokenRawText = '';
                                        _translatedText = '';
                                        _translatedRawText = '';
                                        _phoneticText = '';
                                        _tttController.clear();
                                      });
                                    },
                                    isDark,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Text area (with padding to avoid wall)
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.topLeft,
                                      child: Text(
                                        _translatedText.isNotEmpty ? _translatedText : '',
                                        style: TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 14,
                                          color: isDark ? Colors.white : Colors.black,
                                        ),
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  // Wall to the right
                                  Container(
                                    width: 32,
                                    color: Colors.transparent,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        // Replay icon (bottom right)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: IconButton(
                            icon: const Icon(Icons.replay, size: 26),
                            tooltip: 'Replay Output',
                            color: isDark ? Colors.white : Colors.black,
                            onPressed: _translatedText.isNotEmpty
                                ? () => _speakText(_translatedText, _selectedOutputLang)
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Send to Learn button
                  if (_translatedText.isNotEmpty && !_isTranslating)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Center(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark ? Colors.transparent : const Color(0xFFE3F0FF),
                            foregroundColor: isDark ? Colors.white : Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                            minimumSize: const Size(0, 24),
                            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide.none),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.school, size: 10),
                          label: const Text('Send to Learn', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                          onPressed: () async {
                            final sent = await _sendToLearnMultipleLangs(
                              translated: _translatedText,
                              original: _spokenText.isNotEmpty ? _spokenText : _tttController.text,
                              phonetic: _phoneticText,
                              langs: [_selectedOutputLang],
                            );
                            if (sent) {
                              setState(() {
                                _selectedLearnLang = _selectedOutputLang;
                                _activeTab = 'learn';
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  if (_isTranslating)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: LinearProgressIndicator(
                        color: Colors.white,
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (isDark)
                          IconButton(
                            onPressed: (_spokenText.isNotEmpty &&
                                    _translatedText.isNotEmpty &&
                                    !_sharingCurrentTranslation)
                                ? _shareCurrentTranslationPackage
                                : null,
                            icon: Icon(
                              Icons.share,
                              size: 24,
                              color: Colors.white,
                            ),
                            tooltip: 'Share',
                            padding: const EdgeInsets.all(8),
                          )
                        else
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.10),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: IconButton(
                              onPressed: (_spokenText.isNotEmpty &&
                                      _translatedText.isNotEmpty &&
                                      !_sharingCurrentTranslation)
                                  ? _shareCurrentTranslationPackage
                                  : null,
                              icon: const Icon(
                                Icons.share,
                                size: 24,
                                color: Colors.black,
                              ),
                              tooltip: 'Share',
                              padding: const EdgeInsets.all(8),
                            ),
                          ),
                        GestureDetector(
                          onTapDown: (_) => _startListening(),
                          onTapUp: (_) => _stopListening(),
                          onTapCancel: () {},
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: _isTalking ? 130 : 120,
                            height: _isTalking ? 130 : 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isTalking ? Colors.red : Colors.green,
                              boxShadow: [
                                BoxShadow(
                                  color: (_isTalking ? Colors.red : Colors.green)
                                      .withOpacity(0.4),
                                  blurRadius: _isTalking ? 20 : 10,
                                  spreadRadius: _isTalking ? 4 : 2,
                                )
                              ],
                            ),
                            child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(_isTalking ? Icons.mic : Icons.mic_none,
                                      color: Colors.white, size: 40),
                                  const SizedBox(height: 4),
                                  Text(
                                    _isTalking ? 'LISTENING' : 'HOLD TO TALK',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5),
                                  ),
                                ]),
                          ),
                        ),
                        if (isDark)
                          IconButton(
                            onPressed: _spokenText.isNotEmpty ? _resetOutput : null,
                            icon: Icon(
                              Icons.refresh,
                              size: 28,
                              color: Colors.white,
                            ),
                            tooltip: 'New Translation',
                            padding: const EdgeInsets.all(12),
                          )
                        else
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.10),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: IconButton(
                              onPressed: _spokenText.isNotEmpty ? _resetOutput : null,
                              icon: const Icon(
                                Icons.refresh,
                                size: 28,
                                color: Colors.black,
                              ),
                              tooltip: 'New Translation',
                              padding: const EdgeInsets.all(12),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _langDrop(String value, List<String> langs,
      ValueChanged<String?> onChanged, bool isDark) {
    // Detect if this is the main output dropdown by checking langs and value
    final isOutputDropdown =
      langs.length == 12 &&
      (langs.contains('isiZulu') && langs.contains('Afrikaans')) &&
      value == _selectedOutputLang;
    final isInputDropdown =
      langs.length == 11 &&
      (langs.contains('isiZulu') && langs.contains('Afrikaans')) &&
      value == _selectedInputLang;
    final dropdownColor = isDark
      ? const Color(0xFF000000)
      : isOutputDropdown
        ? const Color(0xFFFFF3E0)
        : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: isDark
          ? Colors.transparent
          : isOutputDropdown
            ? const Color(0xFFFFF3E0)
            : isInputDropdown
              ? const Color(0xFFE0F8D8)
              : Colors.transparent,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          canvasColor: dropdownColor,
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: value,
            dropdownColor: dropdownColor,
            style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF000000),
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                fontSize: 16),
            items: langs
                .map((e) => DropdownMenuItem(
                    value: e,
                    child: Text(
                      e,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
                    )))
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  Widget _outBox(String label, String text, Color color, bool isDark) {
    // Use the passed color for the background in light mode, else white12 in dark mode
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white12 : color,
        borderRadius: BorderRadius.circular(12),
        border: isDark ? null : Border.all(
          color: Colors.black26,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(
                fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : const Color(0xFF000000),
                fontSize: 12,
                fontFamily: 'monospace')),
        const SizedBox(height: 6),
        Text(text,
            style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white : const Color(0xFF000000),
                fontFamily: 'monospace')),
      ]),
    );
  }

  Future<void> _exportHistory() async {
    if (_history.isEmpty) return;
    setState(() => _exportingHistory = true);
    try {
      final dir = await getTemporaryDirectory();
      final files = <XFile>[];

      // Build text summary file
      final buf = StringBuffer();
      buf.writeln('Let\'s Talk — Translation History');
      buf.writeln('Exported: ${DateTime.now().toString().substring(0, 16)}');
      buf.writeln();
      for (int i = 0; i < _history.length; i++) {
        final item = _history[i];
        buf.writeln('[${i + 1}] ${item.inputLang} -> ${item.outputLang}  '
            '${item.time.hour.toString().padLeft(2, "0")}:${item.time.minute.toString().padLeft(2, "0")}');
        buf.writeln('Original:    ${item.original}');
        buf.writeln('Translation: ${item.translated}');
        buf.writeln();
      }
      final txtFile = File('${dir.path}/letstalk_voice_history.txt');
      await txtFile.writeAsString(buf.toString());
      files.add(XFile(txtFile.path, mimeType: 'text/plain'));

      // Generate audio files
      for (int i = 0; i < _history.length; i++) {
        final item = _history[i];
        try {
          final inProvider = _ttsProviderForLanguage(item.inputLang);
          final inVoice = _voiceNameForLanguage(item.inputLang);
          final inAudio = await _translationService.generateTranslation(
            item.original,
            item.inputLang,
            voiceName: inVoice,
            ttsProvider: inProvider,
          );
          if (inAudio != null && inAudio.isNotEmpty) {
            final mp3 = File(
                '${dir.path}/entry_${i + 1}_${item.inputLang}_original.mp3');
            await mp3.writeAsBytes(inAudio);
            files.add(XFile(mp3.path, mimeType: 'audio/mpeg'));
          }
        } catch (_) {}
        try {
          final outProvider = _ttsProviderForLanguage(item.outputLang);
          final outVoice = _voiceNameForLanguage(item.outputLang);
          final outAudio = await _translationService.generateTranslation(
            item.translated,
            item.outputLang,
            voiceName: outVoice,
            ttsProvider: outProvider,
          );
          if (outAudio != null && outAudio.isNotEmpty) {
            final mp3 = File(
                '${dir.path}/entry_${i + 1}_${item.outputLang}_translation.mp3');
            await mp3.writeAsBytes(outAudio);
            files.add(XFile(mp3.path, mimeType: 'audio/mpeg'));
          }
        } catch (_) {}
      }

      if (files.isNotEmpty) {
        await Share.shareXFiles(files,
            subject: 'Let\'s Talk — Translation History');
      }
    } catch (e) {
      debugPrint('Export error: $e');
      _showSnack('Export failed');
    } finally {
      setState(() => _exportingHistory = false);
    }
  }

  Widget _buildHistoryTab(bool isDark) {
    if (_history.isEmpty) {
      // If history is empty and tab is history, auto-switch to Translate
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _activeTab == 'history') {
          setState(() => _activeTab = 'translate');
        }
      });
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history,
                size: 64, color: isDark ? Colors.white30 : Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No translations yet',
                style: TextStyle(
                    color: isDark ? Colors.white38 : Colors.grey.shade500,
                    fontSize: 16)),
          ],
        ),
      );
    }
    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Share History Icon Button (far left)
                  Material(
                    color: isDark ? Colors.black : Colors.white,
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: IconButton(
                      onPressed: _history.isEmpty ? null : _exportHistory,
                      icon: Icon(
                        Icons.share,
                        size: 20,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                      tooltip: 'Share History',
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                  const Spacer(),
                  // Clear History Icon Button (far right)
                  Material(
                    color: isDark ? Colors.black : Colors.white,
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: IconButton(
                      onPressed: () async {
                        final sure = await showDialog<bool>(
                          context: context,
                          builder: (ctx) {
                            final isDark = Theme.of(ctx).brightness == Brightness.dark;
                            return AlertDialog(
                              title: const Text('Are you sure?'),
                              content: const Text('Clear all History?'),
                              backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
                              surfaceTintColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(false),
                                  child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white : Color(0xFF000000))),
                                ),
                                TextButton(
                                  style: TextButton.styleFrom(
                                    backgroundColor: const Color(0xFF000000),
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: () => Navigator.of(ctx).pop(true),
                                  child: const Text('Clear', style: TextStyle(color: Colors.white)),
                                ),
                              ],
                            );
                          },
                        );
                        if (sure == true) {
                          setState(() {
                            _history.clear();
                          });
                        }
                      },
                      icon: const Icon(
                        Icons.delete_sweep,
                        size: 24,
                        color: Colors.red,
                      ),
                      tooltip: 'Clear History',
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _history.length,
                itemBuilder: (context, i) {
                  final item = _history[i];
                  final selected = _selectedHistoryIndexes.contains(i);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    color: isDark ? Colors.white12 : const Color(0xFFFFEBEE), // pastel red
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListTile(
                          title: Text(item.translated,
                              style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.bold)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('From: ${item.inputLang}'),
                              Text('To: ${item.outputLang}'),
                              if ((item.phonetic ?? '').isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Text('Phonetics: ${item.phonetic}',
                                      style: TextStyle(
                                          fontStyle: FontStyle.italic,
                                          color: isDark ? Colors.white70 : Colors.black87)),
                                ),
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text('Original: ${item.original}'),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.volume_up),
                                tooltip: 'Repeat',
                                onPressed: () => _speakText(item.translated, item.outputLang),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDark ? Colors.transparent : const Color(0xFFE3F0FF),
                                foregroundColor: isDark ? Colors.white : Colors.black,
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                minimumSize: const Size(0, 24),
                                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide.none),
                                elevation: 0,
                              ),
                              icon: const Icon(Icons.school, size: 10),
                              label: const Text('Send to Learn', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                              onPressed: () async {
                                await _sendHistoryToLearn(item);
                              },
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        // Bottom right home icon
        Positioned(
          bottom: 18,
          right: 18,
          child: FloatingActionButton(
            heroTag: 'history_home',
            mini: true,
            backgroundColor: isDark ? Colors.white12 : Colors.white,
            foregroundColor: isDark ? Colors.white : Colors.black,
            elevation: 2,
            onPressed: () => setState(() => _activeTab = 'translate'),
            tooltip: 'Home',
            child: const Icon(Icons.home),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _speech.stop();
    _audioPlayer.release();
    _autocorrectTimer?.cancel();
    _tttController.dispose();
    super.dispose();
  }
}
