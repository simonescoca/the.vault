// Operating-system integrations behind an interface (replaced by fakes in tests).
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:url_launcher/url_launcher.dart';

abstract class PlatformServices {
  /// macos | windows | linux
  String get platform;

  /// "Touch ID" / "Windows Hello".
  String get biometricName;

  String defaultDeviceName();

  Future<bool> biometricsAvailable();
  Future<bool> authenticate(String reason);

  Future<void> openUrl(Uri uri);
  Future<bool> openFile(String path);

  Future<List<File>> pickFiles();
  Future<String?> pickFile({List<String>? extensions});
  Future<String?> saveFileDialog(String suggestedName, {List<String>? extensions});

  Future<void> setClipboard(String text);
  Future<String?> getClipboard();
}

class SystemPlatformServices implements PlatformServices {
  final _auth = LocalAuthentication();

  @override
  String get platform => Platform.isMacOS ? 'macos' : (Platform.isWindows ? 'windows' : 'linux');

  @override
  String get biometricName => Platform.isMacOS ? 'Touch ID' : 'Windows Hello';

  @override
  String defaultDeviceName() {
    if (Platform.isWindows) {
      final n = Platform.environment['COMPUTERNAME'];
      if (n != null && n.isNotEmpty) return n;
    }
    var h = Platform.localHostname;
    if (h.endsWith('.local')) h = h.substring(0, h.length - 6);
    h = h.replaceAll('-', ' ').trim();
    if (h.isEmpty) return Platform.isMacOS ? 'Mac' : 'PC';
    return h.length > 60 ? h.substring(0, 60) : h;
  }

  @override
  Future<bool> biometricsAvailable() async {
    if (!(Platform.isMacOS || Platform.isWindows)) return false;
    try {
      if (!await _auth.isDeviceSupported()) return false;
      final list = await _auth.getAvailableBiometrics();
      return list.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        // On macOS only Touch ID: if it fails the app PIN is used, not the Mac password.
        // Windows does not support biometricOnly (Windows Hello decides the method).
        biometricOnly: Platform.isMacOS,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> openUrl(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Future<bool> openFile(String path) => launchUrl(Uri.file(path));

  @override
  Future<List<File>> pickFiles() async {
    final r = await FilePicker.pickFiles();
    return [for (final f in r) if (f.path != null) File(f.path!)];
  }

  @override
  Future<String?> pickFile({List<String>? extensions}) async {
    final r = await FilePicker.pickFile(
      type: extensions == null ? FileType.any : FileType.custom,
      allowedExtensions: extensions,
    );
    return r?.path;
  }

  /// Asks where to save; the caller then writes the file (large files are streamed, not held in memory).
  @override
  Future<String?> saveFileDialog(String suggestedName, {List<String>? extensions}) async {
    final uri = await FilePicker.saveFile(
      fileName: suggestedName,
      bytes: Uint8List(0),
      type: extensions == null ? FileType.any : FileType.custom,
      allowedExtensions: extensions,
    );
    return uri?.toFilePath();
  }

  @override
  Future<void> setClipboard(String text) => Clipboard.setData(ClipboardData(text: text));

  @override
  Future<String?> getClipboard() async => (await Clipboard.getData(Clipboard.kTextPlain))?.text;
}
