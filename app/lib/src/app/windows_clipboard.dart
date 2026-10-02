// Copying on Windows with the markers that keep a value out of the clipboard history (Win+V), out of the
// cloud clipboard shared with other PCs, and away from clipboard monitors.
// https://learn.microsoft.com/windows/win32/dataxchg/clipboard-formats#cloud-clipboard-and-clipboard-history-formats
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

const _cfUnicodeText = 13;
const _gmemMoveable = 0x0002;

/// The markers and their DWORD values: "Exclude…" just needs to be there, the other two say "no".
const _privacyFormats = {
  'ExcludeClipboardContentFromMonitorProcessing': 0,
  'CanIncludeInClipboardHistory': 0,
  'CanUploadToCloudClipboard': 0,
};

class _Win32 {
  _Win32() {
    final user32 = DynamicLibrary.open('user32.dll');
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    openClipboard = user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('OpenClipboard');
    emptyClipboard = user32.lookupFunction<Int32 Function(), int Function()>('EmptyClipboard');
    closeClipboard = user32.lookupFunction<Int32 Function(), int Function()>('CloseClipboard');
    setClipboardData = user32.lookupFunction<IntPtr Function(Uint32, IntPtr), int Function(int, int)>('SetClipboardData');
    registerClipboardFormat =
        user32.lookupFunction<Uint32 Function(Pointer<Utf16>), int Function(Pointer<Utf16>)>('RegisterClipboardFormatW');
    findWindow = user32.lookupFunction<IntPtr Function(Pointer<Utf16>, Pointer<Utf16>), int Function(Pointer<Utf16>, Pointer<Utf16>)>(
        'FindWindowW');
    globalAlloc = kernel32.lookupFunction<IntPtr Function(Uint32, IntPtr), int Function(int, int)>('GlobalAlloc');
    globalLock = kernel32.lookupFunction<Pointer<Void> Function(IntPtr), Pointer<Void> Function(int)>('GlobalLock');
    globalUnlock = kernel32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('GlobalUnlock');
    globalFree = kernel32.lookupFunction<IntPtr Function(IntPtr), int Function(int)>('GlobalFree');
  }

  late final int Function(int) openClipboard;
  late final int Function() emptyClipboard;
  late final int Function() closeClipboard;
  late final int Function(int, int) setClipboardData;
  late final int Function(Pointer<Utf16>) registerClipboardFormat;
  late final int Function(Pointer<Utf16>, Pointer<Utf16>) findWindow;
  late final int Function(int, int) globalAlloc;
  late final Pointer<Void> Function(int) globalLock;
  late final int Function(int) globalUnlock;
  late final int Function(int) globalFree;

  /// Global memory filled by [fill]; 0 if it could not be allocated.
  int alloc(int bytes, void Function(Pointer<Void> p) fill) {
    final h = globalAlloc(_gmemMoveable, bytes);
    if (h == 0) return 0;
    final p = globalLock(h);
    if (p == nullptr) {
      globalFree(h);
      return 0;
    }
    fill(p);
    globalUnlock(h);
    return h;
  }

  /// Hands [handle] to the clipboard, which owns it from then on; frees it if the clipboard refuses it.
  bool put(int format, int handle) {
    if (handle == 0) return false;
    if (setClipboardData(format, handle) != 0) return true;
    globalFree(handle);
    return false;
  }
}

_Win32? _win32;

/// Copies [text] marked as private. Returns false if it was not possible (the caller then uses a normal copy).
bool copyPrivateWindows(String text) {
  if (!Platform.isWindows) return false;
  try {
    final w = _win32 ??= _Win32();
    // The clipboard needs an owner window: the app's own window (the clipboard may refuse a null owner).
    final owner = using((arena) => w.findWindow('FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16(allocator: arena), 'The Vault'.toNativeUtf16(allocator: arena)));
    var open = false;
    // Another program may be using the clipboard for a moment: try a few times.
    for (var i = 0; i < 10 && !open; i++) {
      open = w.openClipboard(owner) != 0;
      if (!open) sleep(const Duration(milliseconds: 15));
    }
    if (!open) return false;
    try {
      w.emptyClipboard();
      final units = text.codeUnits;
      final textHandle = w.alloc((units.length + 1) * 2, (p) {
        final chars = p.cast<Uint16>().asTypedList(units.length + 1);
        chars.setAll(0, units);
        chars[units.length] = 0;
      });
      if (!w.put(_cfUnicodeText, textHandle)) return false;
      for (final MapEntry(key: name, value: value) in _privacyFormats.entries) {
        final format = using((arena) => w.registerClipboardFormat(name.toNativeUtf16(allocator: arena)));
        if (format == 0) continue;
        w.put(format, w.alloc(4, (p) => p.cast<Uint32>().value = value));
      }
      return true;
    } finally {
      w.closeClipboard();
    }
  } catch (_) {
    return false;
  }
}
