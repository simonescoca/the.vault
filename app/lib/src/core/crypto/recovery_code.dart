import 'dart:typed_data';

/// The emergency code: 15 random bytes (120 bits) written as 24 Crockford Base32 characters
/// in groups of four, e.g. `K7QM-3XRP-9HTV-2WQD-8F4N-J6YB`.
class RecoveryCode {
  RecoveryCode._(this.bytes);

  static const byteLength = 15;
  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  final Uint8List bytes;

  factory RecoveryCode.random(Uint8List random15) {
    if (random15.length != byteLength) {
      throw ArgumentError('the emergency code needs $byteLength random bytes');
    }
    return RecoveryCode._(Uint8List.fromList(random15));
  }

  /// Parses what the user typed. Accepts lowercase, spaces and dashes, and the usual
  /// look-alikes (O→0, I/L→1). Returns null if it is not a valid code.
  static RecoveryCode? tryParse(String input) {
    final chars = input.toUpperCase().replaceAll(RegExp(r'[\s\-_.]'), '');
    if (chars.length != 24) return null;
    var buffer = 0;
    var bits = 0;
    final out = BytesBuilder();
    for (final rune in chars.runes) {
      var c = String.fromCharCode(rune);
      if (c == 'O') c = '0';
      if (c == 'I' || c == 'L') c = '1';
      final v = _alphabet.indexOf(c);
      if (v < 0) return null;
      buffer = (buffer << 5) | v;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.addByte((buffer >> bits) & 0xff);
        buffer &= (1 << bits) - 1;
      }
    }
    final b = out.toBytes();
    if (b.length != byteLength) return null;
    return RecoveryCode._(b);
  }

  /// The 24 characters without separators.
  String get compact {
    final sb = StringBuffer();
    var buffer = 0;
    var bits = 0;
    for (final byte in bytes) {
      buffer = (buffer << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        sb.write(_alphabet[(buffer >> bits) & 31]);
        buffer &= (1 << bits) - 1;
      }
    }
    return sb.toString();
  }

  /// Groups of four characters separated by dashes.
  String get formatted {
    final c = compact;
    final groups = <String>[];
    for (var i = 0; i < c.length; i += 4) {
      groups.add(c.substring(i, i + 4));
    }
    return groups.join('-');
  }

  @override
  String toString() => 'RecoveryCode(****)';
}
