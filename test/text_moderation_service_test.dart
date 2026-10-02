import 'package:flutter_test/flutter_test.dart';
import 'package:paw_watch/services/text_moderation_service.dart';

void main() {
  group('TextModerationService Tests', () {
    test('validateDisplayName checks', () {
      expect(TextModerationService.validateDisplayName('Jo'), isNotNull);
      expect(TextModerationService.validateDisplayName('John123'), isNotNull);
      expect(TextModerationService.validateDisplayName('Cat🐱Lover'), isNotNull);
      expect(TextModerationService.validateDisplayName('fuck'), isNotNull);
      expect(TextModerationService.validateDisplayName('John Doe'), isNull);
      expect(TextModerationService.validateDisplayName("O'Connor"), isNull);
    });

    test('validateReportTitle checks', () {
      expect(TextModerationService.validateReportTitle('Cat'), isNotNull);
      expect(TextModerationService.validateReportTitle('12345'), isNotNull);
      expect(TextModerationService.validateReportTitle('🐱🐱🐱🐱'), isNotNull);
      expect(TextModerationService.validateReportTitle('asdfghjkl'), isNotNull);
      expect(TextModerationService.validateReportTitle('Injured Orange Tabby'), isNull);
    });

    test('validateDescription checks', () {
      expect(TextModerationService.validateDescription('Short'), isNotNull);
      expect(TextModerationService.validateDescription('🐱🐱🐱🐱🐱🐱🐱🐱🐱'), isNotNull);
      expect(TextModerationService.validateDescription('zzzzzzzzzzzzzz'), isNotNull);
      expect(TextModerationService.validateDescription('Found this cat resting near the park entrance, needs food.'), isNull);
    });

    test('validateChatMessage checks', () {
      expect(TextModerationService.validateChatMessage(''), isNotNull);
      expect(TextModerationService.validateChatMessage('🐱'), isNotNull);
      expect(TextModerationService.validateChatMessage('aaaaaa'), isNotNull);
      expect(TextModerationService.validateChatMessage('Hello there, is the cat still there?'), isNull);
    });

    test('validatePhoneNumber checks', () {
      expect(TextModerationService.validatePhoneNumber('123'), isNotNull);
      expect(TextModerationService.validatePhoneNumber('phone12345678'), isNotNull);
      expect(TextModerationService.validatePhoneNumber('+6281234567890'), isNull);
      expect(TextModerationService.validatePhoneNumber('0812-3456-7890'), isNull);
    });
  });
}
