/// OCR language tags passed to [OcrReader.setLanguage].
///
/// Use BCP-47 tags such as [english] or [chineseSimplified], or [system]
/// to follow the device language.
class OcrLanguage {
  OcrLanguage._();

  /// Follow the device / user profile language.
  static const String system = 'system';

  /// English (United States).
  static const String english = 'en-US';

  /// Chinese (Simplified, China).
  static const String chineseSimplified = 'zh-Hans-CN';

  /// Chinese (Traditional, Taiwan).
  static const String chineseTraditional = 'zh-Hant-TW';

  /// Japanese (Japan).
  static const String japanese = 'ja-JP';

  /// Korean (Korea).
  static const String korean = 'ko-KR';
}
