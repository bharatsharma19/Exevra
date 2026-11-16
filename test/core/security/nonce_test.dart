import 'dart:math';

import 'package:expense_manager/core/security/nonce.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sha256 matches the known vector', () {
    expect(
      Nonce.sha256Hex('abc'),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(Nonce.sha256Hex('abc'), hasLength(64));
  });

  test('nonces are long, URL-safe and different each time', () {
    final a = Nonce.generate();
    final b = Nonce.generate();
    expect(a, hasLength(32));
    expect(a, matches(RegExp(r'^[0-9A-Za-z._-]+$')));
    expect(a, isNot(b));
    expect(Nonce.sha256Hex(a), isNot(a));
  });

  test('the length is enforced and the source is injectable', () {
    expect(() => Nonce.generate(8), throwsArgumentError);
    expect(Nonce.generate(20, Random(1)), Nonce.generate(20, Random(1)));
  });
}
