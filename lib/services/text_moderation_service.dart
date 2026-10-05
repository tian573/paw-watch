

class TextModerationService {
  TextModerationService._();


  static final Set<String> _profanityList = {

    'fuck', 'fucking', 'fucker', 'fucked', 'shit', 'shitty', 'bitch', 'bitches',
    'asshole', 'bastard', 'cunt', 'dick', 'pussy', 'whore', 'slut', 'nigger',
    'nigga', 'faggot', 'retard', 'cock', 'blowjob', 'piss', 'motherfucker',
    'bullshit', 'prick', 'twat', 'wanker',

    'anjing', 'anying', 'anjir', 'babi', 'bangsat', 'kontol', 'memek', 'ngentot',
    'entot', 'tahi', 'tai', 'pantek', 'goblok', 'bego', 'tolol', 'peler',
    'pepek', 'itil', 'bajingan', 'kampret', 'jancok', 'dancok', 'asu', 'jembut',
    'lonte', 'perek', 'silit', 'tetek', 'boobies', 'colmek', 'coli'
  };


  static bool hasProfanity(String text) {
    if (text.trim().isEmpty) return false;
    final normalized = text.toLowerCase();


    final tokens = RegExp(r'[a-zA-Z0-9]+')
        .allMatches(normalized)
        .map((m) => m.group(0)!)
        .toList();

    for (final token in tokens) {
      if (_profanityList.contains(token)) {
        return true;
      }
    }


    for (final word in _profanityList) {
      if (word.length >= 4 && normalized.contains(word)) {

        final pattern = RegExp(r'(^|\W)' + RegExp.escape(word) + r'($|\W)');
        if (pattern.hasMatch(normalized)) {
          return true;
        }
      }
    }
    return false;
  }


  static bool isLettersOnly(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    return RegExp(r"^[a-zA-Z\s'-]+$").hasMatch(trimmed);
  }


  static bool isEmojiOnlyOrSymbols(String text) {
    final stripped = text.replaceAll(RegExp(r'[\s\p{P}\p{S}]', unicode: true), '');
    return stripped.isEmpty;
  }


  static bool isGibberishOrSpam(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return true;


    if (isEmojiOnlyOrSymbols(trimmed)) return true;


    if (RegExp(r'(.)\1{3,}').hasMatch(trimmed.toLowerCase())) {
      return true;
    }


    final mashPatterns = [
      'asdf', 'sdfg', 'dfgh', 'fghj', 'ghjk', 'hjkl',
      'qwerty', 'werty', 'ertyu', 'rtyui', 'tyuio', 'yuio',
      'zxcvb', 'xcvbn', 'cvbnm',
      'qazwsx', 'wsxedc', 'edcrfv',
    ];
    final lowerNoSpace = trimmed.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    for (final p in mashPatterns) {
      if (lowerNoSpace.contains(p)) {
        return true;
      }
    }


    final words = RegExp(r'[a-zA-Z]+')
        .allMatches(trimmed.toLowerCase())
        .map((m) => m.group(0)!)
        .toList();

    for (final w in words) {

      if (w.length >= 4 && !RegExp(r'[aeiouy]').hasMatch(w)) {
        return true;
      }

      if (RegExp(r'[bcdfghjklmnpqrstvwxz]{5,}').hasMatch(w)) {
        return true;
      }
    }

    return false;
  }


  static String? validateDisplayName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Display name is required.';
    }
    final trimmed = value.trim();
    if (trimmed.length < 3) {
      return 'Display name must be at least 3 characters.';
    }
    if (!isLettersOnly(trimmed)) {
      return 'Display name can only contain letters (no numbers or symbols).';
    }
    if (hasProfanity(trimmed)) {
      return 'Display name contains inappropriate words.';
    }
    if (isGibberishOrSpam(trimmed)) {
      return 'Please enter a valid, real name.';
    }
    return null;
  }


  static String? validateTitle(
    String? value, {
    String label = 'Title',
    int minLength = 4,
    bool allowConnectors = true,
  }) {
    if (value == null || value.trim().isEmpty) {
      return '$label is required.';
    }
    final trimmed = value.trim();
    if (trimmed.length < minLength) {
      return '$label must be at least $minLength characters.';
    }
    final pattern = allowConnectors
        ? RegExp(r"^[a-zA-Z\s',&-]+$")
        : RegExp(r"^[a-zA-Z\s'-]+$");
    if (!pattern.hasMatch(trimmed)) {
      return '$label must contain only letters (no numbers or symbols).';
    }
    if (hasProfanity(trimmed)) {
      return '$label contains inappropriate words.';
    }
    if (isGibberishOrSpam(trimmed)) {
      return '$label must be actual words, not random letters or spam.';
    }
    return null;
  }


  static String? validateReportTitle(String? value) {
    return validateTitle(value, label: 'Title', minLength: 4, allowConnectors: true);
  }


  static String? validateDescription(String? value, {String fieldName = 'Description'}) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required.';
    }
    final trimmed = value.trim();
    if (trimmed.length < 8) {
      return '$fieldName must be at least 8 characters.';
    }
    if (isEmojiOnlyOrSymbols(trimmed)) {
      return '$fieldName cannot be just emojis or symbols.';
    }
    if (hasProfanity(trimmed)) {
      return '$fieldName contains inappropriate words.';
    }
    if (isGibberishOrSpam(trimmed)) {
      return 'Please write meaningful text, not random characters or spam.';
    }
    return null;
  }


  static String? validateChatMessage(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Message cannot be empty.';
    }
    final trimmed = value.trim();
    if (hasProfanity(trimmed)) {
      return '⚠️ Inappropriate words are not permitted in chat.';
    }
    if (isGibberishOrSpam(trimmed)) {
      return '⚠️ Message flagged as spam or invalid text.';
    }
    return null;
  }


  static String? validateComment(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter a comment.';
    }
    final trimmed = value.trim();
    if (trimmed.length < 2) {
      return 'Comment is too short.';
    }
    if (isEmojiOnlyOrSymbols(trimmed)) {
      return '⚠️ Comment cannot be just emojis or symbols. Please write actual words.';
    }
    if (hasProfanity(trimmed)) {
      return '⚠️ Inappropriate words are not permitted in community comments.';
    }
    if (isGibberishOrSpam(trimmed)) {
      return '⚠️ Please write actual words, not random characters or spam.';
    }
    return null;
  }


  static String? validateFacilityName(String? value, {String label = 'Foster home'}) {
    if (value == null || value.trim().isEmpty) {
      return '$label name is required.';
    }
    final trimmed = value.trim();
    if (trimmed.length < 3) {
      return '$label name must be at least 3 characters.';
    }
    if (isEmojiOnlyOrSymbols(trimmed)) {
      return '$label name cannot be only emojis.';
    }
    if (hasProfanity(trimmed)) {
      return '$label name contains inappropriate words.';
    }
    if (isGibberishOrSpam(trimmed)) {
      return 'Please enter a valid $label name.';
    }
    return null;
  }


  static String? validatePhoneNumber(String? value,
      {String label = 'Contact phone number'}) {
    if (value == null || value.trim().isEmpty) {
      return '$label is required.';
    }
    final trimmed = value.trim();

    final phoneRegex = RegExp(r'^\+?[0-9\s\-()]{8,18}$');
    if (!phoneRegex.hasMatch(trimmed)) {
      return '$label must be a valid phone number (digits only).';
    }

    final digitCount = trimmed.replaceAll(RegExp(r'\D'), '').length;
    if (digitCount < 8 || digitCount > 15) {
      return '$label must have between 8 and 15 digits.';
    }
    return null;
  }


  static String? validateAddress(String? value, {String label = 'Address'}) {
    if (value == null || value.trim().isEmpty) {
      return '$label is required.';
    }
    final trimmed = value.trim();
    if (trimmed.length < 5) {
      return '$label must be at least 5 characters.';
    }
    if (isEmojiOnlyOrSymbols(trimmed)) {
      return '$label cannot be just emojis or symbols.';
    }
    if (hasProfanity(trimmed)) {
      return '$label contains inappropriate words.';
    }
    if (isGibberishOrSpam(trimmed)) {
      return 'Please enter a valid, real $label.';
    }
    return null;
  }
}


