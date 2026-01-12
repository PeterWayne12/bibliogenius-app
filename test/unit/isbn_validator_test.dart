import 'package:flutter_test/flutter_test.dart';
import 'package:app/utils/isbn_validator.dart';

void main() {
  group('IsbnValidator', () {
    test('returns false for null or empty string', () {
      expect(IsbnValidator.isValid(null), false);
      expect(IsbnValidator.isValid(''), false);
    });

    test('validates ISBN-10 correctly', () {
      expect(IsbnValidator.isValid('0-306-40615-2'), true);
      expect(IsbnValidator.isValid('0306406152'), true);
      // Valid ISBN-10 with 'X' check digit
      expect(IsbnValidator.isValid('0-8044-2957-X'), true);
      expect(IsbnValidator.isValid('080442957X'), true);
    });

    test('invalidates bad ISBN-10', () {
      expect(
        IsbnValidator.isValid('0-306-40615-5'),
        false,
      ); // Wrong check digit
      expect(IsbnValidator.isValid('123456789'), false); // Too short
      expect(IsbnValidator.isValid('12345678901'), false); // Too long
    });

    test('validates ISBN-13 correctly', () {
      expect(IsbnValidator.isValid('978-0-306-40615-7'), true);
      expect(IsbnValidator.isValid('9780306406157'), true);
    });

    test('invalidates bad ISBN-13', () {
      expect(
        IsbnValidator.isValid('978-0-306-40615-8'),
        false,
      ); // Wrong check digit
      expect(IsbnValidator.isValid('9780306406158'), false);
    });

    test('invalidates non-book ISBN-13 prefix', () {
      // 977 is ISSN, typically not ISBN unless specific logic?
      // Validator code explicitly checks for 978 or 979
      expect(IsbnValidator.isValid('977-0-306-40615-7'), false);
    });

    test('handles whitespace and dashes', () {
      expect(IsbnValidator.isValid(' 978 - 0 - 306 - 40615 - 7 '), true);
    });
  });
}
