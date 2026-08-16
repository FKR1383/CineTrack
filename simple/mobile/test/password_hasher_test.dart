import 'package:flutter_test/flutter_test.dart';
import 'package:cinetrack_simple/core/security/password_hasher.dart';

void main() {
  test('local password hashing verifies correct password only', () {
    final digest = PasswordHasher.hash('StrongPass123');
    expect(PasswordHasher.verify('StrongPass123', digest.salt, digest.hash), isTrue);
    expect(PasswordHasher.verify('WrongPass123', digest.salt, digest.hash), isFalse);
  });
}
