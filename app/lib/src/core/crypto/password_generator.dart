import 'package:sodium/sodium_sumo.dart';

class PasswordOptions {
  const PasswordOptions({
    this.length = 20,
    this.upper = true,
    this.lower = true,
    this.digits = true,
    this.symbols = true,
  });

  final int length;
  final bool upper;
  final bool lower;
  final bool digits;
  final bool symbols;

  static const minLength = 8;
  static const maxLength = 64;

  PasswordOptions copyWith({int? length, bool? upper, bool? lower, bool? digits, bool? symbols}) => PasswordOptions(
        length: length ?? this.length,
        upper: upper ?? this.upper,
        lower: lower ?? this.lower,
        digits: digits ?? this.digits,
        symbols: symbols ?? this.symbols,
      );

  bool get anyEnabled => upper || lower || digits || symbols;
}

/// Cryptographically random passwords with at least one character from every enabled group.
class PasswordGenerator {
  PasswordGenerator(this.sodium);

  final SodiumSumo sodium;

  static const upperChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const lowerChars = 'abcdefghijklmnopqrstuvwxyz';
  static const digitChars = '0123456789';
  // No quotes, backslash, backtick or spaces: they break many sign-up forms.
  static const symbolChars = '!@#\$%^&*()-_=+[]{};:,.?/~';

  int _uniform(int n) => sodium.randombytes.uniform(n);

  String generate(PasswordOptions o) {
    final groups = <String>[
      if (o.upper) upperChars,
      if (o.lower) lowerChars,
      if (o.digits) digitChars,
      if (o.symbols) symbolChars,
    ];
    if (groups.isEmpty) groups.add(lowerChars);
    final length = o.length.clamp(PasswordOptions.minLength, PasswordOptions.maxLength);
    final all = groups.join();
    final chars = <String>[for (final g in groups) g[_uniform(g.length)]];
    while (chars.length < length) {
      chars.add(all[_uniform(all.length)]);
    }
    // Fisher–Yates shuffle so the guaranteed characters are not at the start.
    for (var i = chars.length - 1; i > 0; i--) {
      final j = _uniform(i + 1);
      final t = chars[i];
      chars[i] = chars[j];
      chars[j] = t;
    }
    return chars.join();
  }
}
