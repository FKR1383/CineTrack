import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class PasswordDigest {
  const PasswordDigest({required this.hash, required this.salt});
  final String hash;
  final String salt;
}

class PasswordHasher {
  const PasswordHasher._();

  static const _iterations = 40000;
  static const _derivedLength = 32;

  static PasswordDigest hash(String password) {
    final random = Random.secure();
    final salt = Uint8List.fromList(List<int>.generate(16, (_) => random.nextInt(256)));
    final derived = _pbkdf2(utf8.encode(password), salt, _iterations, _derivedLength);
    return PasswordDigest(hash: base64Encode(derived), salt: base64Encode(salt));
  }

  static bool verify(String password, String encodedSalt, String encodedHash) {
    try {
      final salt = base64Decode(encodedSalt);
      final expected = base64Decode(encodedHash);
      final actual = _pbkdf2(utf8.encode(password), salt, _iterations, expected.length);
      var diff = 0;
      for (var i = 0; i < expected.length; i++) {
        diff |= expected[i] ^ actual[i];
      }
      return diff == 0;
    } catch (_) {
      return false;
    }
  }

  static Uint8List _pbkdf2(List<int> password, List<int> salt, int iterations, int length) {
    final hmac = Hmac(sha256, password);
    final output = BytesBuilder(copy: false);
    var blockIndex = 1;
    while (output.length < length) {
      final block = BytesBuilder(copy: false)
        ..add(salt)
        ..add([
          (blockIndex >> 24) & 0xff,
          (blockIndex >> 16) & 0xff,
          (blockIndex >> 8) & 0xff,
          blockIndex & 0xff,
        ]);
      var u = Uint8List.fromList(hmac.convert(block.takeBytes()).bytes);
      final t = Uint8List.fromList(u);
      for (var i = 1; i < iterations; i++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      output.add(t);
      blockIndex++;
    }
    return Uint8List.fromList(output.takeBytes().take(length).toList());
  }
}
