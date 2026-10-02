// Site icons for the list, fetched directly from each site (no third-party service) and cached locally.
// The cache is encrypted with a key derived from the vault key, under hashed names: the local database does
// not reveal which sites are in the vault.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../storage/local_db.dart';
import '../vault/vault_controller.dart';

class FaviconService extends ChangeNotifier {
  FaviconService(this.db, this.cipher, {http.Client? client, this.enabled = true}) : _http = client ?? http.Client();

  final LocalDb db;
  final CacheCipher cipher;
  final http.Client _http;
  final bool enabled;
  final Map<String, Uint8List?> _mem = {};
  final Set<String> _inflight = {};
  int _running = 0;
  final List<String> _queue = [];

  static const _retryAfterFailure = Duration(days: 1);
  static const _refreshAfter = Duration(days: 30);
  /// Looks like a browser: sites do not learn that their visitor uses The Vault.
  static const _ua = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15';

  static String domainOf(Uri u) => u.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');

  String _stored(String domain) => cipher.name('favicon', domain);

  /// The icon of [domain] if known; schedules a download otherwise.
  Uint8List? icon(String domain) {
    if (domain.isEmpty) return null;
    if (_mem.containsKey(domain)) return _mem[domain];
    final name = _stored(domain);
    final cached = db.favicon(name);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (cached != null) {
      Uint8List? data;
      try {
        data = cached.data == null ? null : cipher.open(name, cached.data!);
      } catch (_) {
        data = null; // unreadable entry: fetched again below
      }
      _mem[domain] = data;
      final age = Duration(milliseconds: now - cached.fetchedAt);
      final stale = data == null ? (cached.data != null || age > _retryAfterFailure) : age > _refreshAfter;
      if (stale) _schedule(domain);
      return data;
    }
    _mem[domain] = null;
    _schedule(domain);
    return null;
  }

  void _schedule(String domain) {
    if (!enabled || _inflight.contains(domain)) return;
    _inflight.add(domain);
    _queue.add(domain);
    _pump();
  }

  void _pump() {
    while (_running < 3 && _queue.isNotEmpty) {
      final d = _queue.removeAt(0);
      _running++;
      unawaited(_fetch(d).whenComplete(() {
        _running--;
        _inflight.remove(d);
        _pump();
      }));
    }
  }

  Future<void> _fetch(String domain) async {
    Uint8List? png;
    try {
      png = await _discover(domain);
    } catch (_) {
      png = null;
    }
    try {
      final name = _stored(domain);
      db.setFavicon(name, png == null ? null : cipher.seal(name, png), DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      return; // vault locked or database closed (signed out) meanwhile
    }
    _mem[domain] = png;
    notifyListeners();
  }

  Future<http.Response?> _get(Uri u, int maxBytes) async {
    final req = http.Request('GET', u)
      ..headers['User-Agent'] = _ua
      ..followRedirects = true
      ..maxRedirects = 5;
    final resp = await _http.send(req).timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200) {
      await resp.stream.drain<void>();
      return null;
    }
    final b = BytesBuilder(copy: false);
    await for (final chunk in resp.stream.timeout(const Duration(seconds: 8))) {
      b.add(chunk);
      if (b.length > maxBytes) break;
    }
    return http.Response.bytes(b.toBytes(), resp.statusCode, headers: resp.headers, request: resp.request);
  }

  Future<Uint8List?> _discover(String domain) async {
    final home = Uri.https(domain, '/');
    final candidates = <Uri>[];
    try {
      final page = await _get(home, 512 * 1024);
      if (page != null) {
        final base = page.request?.url ?? home;
        candidates.addAll(iconLinks(utf8.decode(page.bodyBytes, allowMalformed: true), base));
      }
    } catch (_) {}
    candidates.add(Uri.https(domain, '/favicon.ico'));
    for (final u in candidates) {
      try {
        final r = await _get(u, 300 * 1024);
        if (r == null) continue;
        final png = toPng(r.bodyBytes);
        if (png != null) return png;
      } catch (_) {}
    }
    return null;
  }

  /// Icon URLs declared in a page, best first (apple-touch-icon, large PNGs, then the rest; no SVG).
  static List<Uri> iconLinks(String html, Uri base) {
    final out = <(Uri, int)>[];
    for (final m in RegExp(r'<link\b[^>]*>', caseSensitive: false).allMatches(html)) {
      final tag = m.group(0)!;
      String? attr(String name) {
        final r = RegExp('$name\\s*=\\s*("([^"]*)"|\'([^\']*)\'|([^\\s>]+))', caseSensitive: false).firstMatch(tag);
        return r == null ? null : (r.group(2) ?? r.group(3) ?? r.group(4));
      }

      final rel = (attr('rel') ?? '').toLowerCase();
      if (!rel.contains('icon')) continue;
      final href = attr('href');
      if (href == null || href.isEmpty || href.startsWith('data:')) continue;
      if (href.toLowerCase().contains('.svg') || (attr('type') ?? '').contains('svg')) continue;
      final u = base.resolve(href.trim());
      if (u.scheme != 'https' && u.scheme != 'http') continue;
      var score = 10;
      if (rel.contains('apple-touch-icon')) score = 100;
      final sizes = attr('sizes');
      final size = int.tryParse(RegExp(r'(\d+)x').firstMatch(sizes ?? '')?.group(1) ?? '');
      if (size != null) score = size >= 32 && size <= 256 ? 50 + size ~/ 8 : 20;
      out.add((u, score));
    }
    out.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final e in out) e.$1];
  }

  /// Largest side accepted: a small file can declare a huge picture, and decoding it would exhaust memory.
  static const maxSide = 1024;

  static bool _sideOk(int w, int h) => w > 0 && h > 0 && w <= maxSide && h <= maxSide;

  /// Decodes any common image format (including .ico) and returns a PNG of at most 64×64, or null.
  /// The size the file declares is checked before decoding, and only the first frame is decoded.
  static Uint8List? toPng(Uint8List bytes) {
    if (bytes.length < 8) return null;
    try {
      final isIco = bytes[0] == 0 && bytes[1] == 0 && bytes[2] == 1 && bytes[3] == 0;
      final decoded = isIco ? _decodeIco(bytes) : _decodeFirstFrame(bytes);
      if (decoded == null || decoded.width < 8 || decoded.height < 8) return null;
      final resized = decoded.width > 64 ? img.copyResize(decoded, width: 64, height: 64, interpolation: img.Interpolation.average) : decoded;
      return Uint8List.fromList(img.encodePng(resized));
    } catch (_) {
      return null;
    }
  }

  static img.Image? _decodeFirstFrame(Uint8List bytes) {
    final decoder = img.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (decoder == null || info == null || !_sideOk(info.width, info.height)) return null;
    return decoder.decodeFrame(0);
  }

  /// .ico: picks the best picture (up to 256 px) whose real declared size is acceptable, and decodes only it.
  static img.Image? _decodeIco(Uint8List bytes) {
    final d = ByteData.sublistView(bytes);
    final count = d.getUint16(4, Endian.little);
    var best = -1, bestSide = 0;
    for (var i = 0; i < count && 6 + 16 * (i + 1) <= bytes.length; i++) {
      final e = 6 + 16 * i;
      final side = bytes[e] == 0 ? 256 : bytes[e];
      final size = d.getUint32(e + 8, Endian.little);
      final offset = d.getUint32(e + 12, Endian.little);
      if (size < 8 || offset + size > bytes.length) continue;
      final data = Uint8List.sublistView(bytes, offset, offset + size);
      if (!_icoPictureOk(data) || side <= bestSide) continue;
      best = i;
      bestSide = side;
    }
    if (best < 0) return null;
    final ico = img.IcoDecoder();
    return ico.startDecode(bytes) == null ? null : ico.decodeFrame(best);
  }

  /// A picture inside an .ico is a PNG or a bitmap without file header (its height counts the mask too).
  static bool _icoPictureOk(Uint8List data) {
    if (data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47) {
      final info = img.PngDecoder().startDecode(data);
      return info != null && _sideOk(info.width, info.height);
    }
    if (data.length < 12) return false;
    final d = ByteData.sublistView(data);
    return _sideOk(d.getInt32(4, Endian.little), d.getInt32(8, Endian.little).abs() ~/ 2);
  }

  @override
  void dispose() {
    _http.close();
    super.dispose();
  }
}
