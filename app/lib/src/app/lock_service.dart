// PIN and biometric unlock (docs/SPEC.md §3).
import '../core/account/identity.dart';
import '../core/crypto/vault_crypto.dart';
import '../core/storage/secret_store.dart';
import 'platform_services.dart';

sealed class PinResult {}

class PinOk extends PinResult {}

class PinWrong extends PinResult {
  PinWrong(this.attemptsLeft, this.waitSeconds);

  /// Shown from the 5th error on (null before).
  final int? attemptsLeft;

  /// Seconds before the next attempt is allowed (0 = none).
  final int waitSeconds;
}

class PinLockedOut extends PinResult {
  PinLockedOut(this.waitSeconds);
  final int waitSeconds;
}

/// Too many errors: the device must be wiped.
class PinWipe extends PinResult {}

class LockService {
  LockService(this.secrets, this.platform, {DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  final SecretStore secrets;
  final PlatformServices platform;
  final DateTime Function() _now;

  static const maxAttempts = 10;
  static const _waits = [30, 60, 120, 300, 600];

  Future<bool> hasPin() async => (await secrets.read(SecretKeys.pinHash)) != null;

  Future<void> setPin(String pin) async {
    await secrets.write(SecretKeys.pinHash, await VaultCrypto.hashPin(pin));
    await secrets.delete(SecretKeys.pinFails);
    await secrets.delete(SecretKeys.pinLockedUntil);
  }

  Future<int> _fails() async => int.tryParse(await secrets.read(SecretKeys.pinFails) ?? '') ?? 0;

  /// Seconds to wait before another attempt is accepted.
  Future<int> lockoutRemaining() async {
    final until = int.tryParse(await secrets.read(SecretKeys.pinLockedUntil) ?? '') ?? 0;
    final left = ((until - _now().millisecondsSinceEpoch) / 1000).ceil();
    return left > 0 ? left : 0;
  }

  Future<PinResult> verifyPin(String pin) async {
    final wait = await lockoutRemaining();
    if (wait > 0) return PinLockedOut(wait);
    final hash = await secrets.read(SecretKeys.pinHash);
    if (hash != null && await VaultCrypto.verifyPin(hash, pin)) {
      await secrets.delete(SecretKeys.pinFails);
      await secrets.delete(SecretKeys.pinLockedUntil);
      return PinOk();
    }
    final fails = await _fails() + 1;
    await secrets.write(SecretKeys.pinFails, '$fails');
    if (fails >= maxAttempts) return PinWipe();
    if (fails < 5) return PinWrong(null, 0);
    final w = _waits[(fails - 5).clamp(0, _waits.length - 1)];
    await secrets.write(SecretKeys.pinLockedUntil, '${_now().millisecondsSinceEpoch + w * 1000}');
    return PinWrong(maxAttempts - fails, w);
  }

  Future<bool> biometricsEnabled() async => (await secrets.read(SecretKeys.biometrics)) == '1';

  Future<void> setBiometricsEnabled(bool v) => v ? secrets.write(SecretKeys.biometrics, '1') : secrets.delete(SecretKeys.biometrics);

  Future<bool> canUseBiometrics() async => await biometricsEnabled() && await platform.biometricsAvailable();
}
