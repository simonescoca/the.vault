// Text helpers: accent-insensitive comparison, URL and email detection, site names.

const _accents = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', 'ă': 'a', 'ą': 'a',
  'ç': 'c', 'ć': 'c', 'č': 'c', 'ď': 'd', 'đ': 'd',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ė': 'e', 'ę': 'e', 'ě': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i', 'į': 'i', 'ı': 'i',
  'ł': 'l', 'ñ': 'n', 'ń': 'n', 'ň': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o', 'ő': 'o',
  'ř': 'r', 'ś': 's', 'š': 's', 'ş': 's', 'ß': 'ss', 'ť': 't', 'ţ': 't',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ů': 'u', 'ű': 'u', 'ų': 'u',
  'ý': 'y', 'ÿ': 'y', 'ź': 'z', 'ż': 'z', 'ž': 'z', 'æ': 'ae', 'œ': 'oe',
};

/// Lower-case, accent-free form used for search and sorting.
String fold(String s) {
  final lower = s.toLowerCase();
  final sb = StringBuffer();
  for (final r in lower.runes) {
    final ch = String.fromCharCode(r);
    sb.write(_accents[ch] ?? ch);
  }
  return sb.toString();
}

final _emailRe = RegExp(r"^[^\s@<>()]+@[^\s@<>()]+\.[^\s@<>()]{2,}$");

bool isEmail(String v) => _emailRe.hasMatch(v.trim());

// Common web TLDs that are safe to link without a scheme. File-extension look-alikes
// (md, sh, py, rs, pl, ps, cc, js…) are deliberately left out.
const _webTlds = {
  'com', 'net', 'org', 'it', 'eu', 'io', 'app', 'dev', 'co', 'uk', 'de', 'fr', 'es', 'ch', 'at', 'nl', 'be',
  'pt', 'se', 'no', 'dk', 'fi', 'ie', 'gr', 'cz', 'sk', 'hu', 'ro', 'bg', 'hr', 'si', 'lu', 'li', 'mt', 'sm',
  'va', 'us', 'ca', 'au', 'nz', 'jp', 'cn', 'kr', 'in', 'br', 'mx', 'ar', 'cl', 'ru', 'ua', 'tr', 'il', 'za',
  'info', 'biz', 'me', 'tv', 'ai', 'gov', 'edu', 'mil', 'int', 'xyz', 'online', 'site', 'store', 'shop',
  'tech', 'cloud', 'email', 'live', 'news', 'blog', 'page', 'web', 'link', 'bank', 'pro', 'name', 'mobi',
  'agency', 'studio', 'design', 'media', 'network', 'digital', 'company', 'services', 'solutions', 'world',
  'one', 'top', 'club', 'art', 'travel', 'health', 'education', 'academy', 'center', 'group', 'team', 'zone',
};

const _websiteKeys = ['sito', 'web', 'url', 'link', 'site', 'dominio', 'domain', 'home', 'pagina', 'page', 'portale', 'portal', 'indirizzo'];

final _bareDomainRe = RegExp(r'^([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+([a-z]{2,24})(:\d{1,5})?(/\S*)?$', caseSensitive: false);

/// If [value] is a web address, returns it as an absolute https/http URI, otherwise null.
/// [key] helps with bare domains: under a "website"-like key any alphabetic TLD is accepted.
Uri? detectUrl(String value, {String key = ''}) {
  final v = value.trim();
  if (v.isEmpty || v.contains(RegExp(r'\s')) || isEmail(v)) return null;
  final lower = v.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    final u = Uri.tryParse(v);
    return (u != null && u.host.contains('.') || u?.host == 'localhost') ? u : null;
  }
  if (lower.startsWith('www.')) return Uri.tryParse('https://$v');
  final m = _bareDomainRe.firstMatch(v);
  if (m == null) return null;
  final tld = m.group(2)!.toLowerCase();
  final k = fold(key);
  final websiteKey = _websiteKeys.any(k.contains);
  if (_webTlds.contains(tld) || websiteKey) return Uri.tryParse('https://$v');
  return null;
}

/// Normalizes a link typed by the user ("netflix.com/account" → "https://netflix.com/account").
/// Returns null when it is not a usable web address.
String? normalizeLink(String input) {
  final v = input.trim();
  if (v.isEmpty || v.contains(RegExp(r'\s'))) return null;
  final lower = v.toLowerCase();
  final withScheme = (lower.startsWith('http://') || lower.startsWith('https://')) ? v : 'https://$v';
  final u = Uri.tryParse(withScheme);
  if (u == null || !(u.scheme == 'http' || u.scheme == 'https')) return null;
  if (!(u.host.contains('.') || u.host == 'localhost') || u.host.startsWith('.') || u.host.endsWith('.')) return null;
  return withScheme;
}

const _secondLevel = {'co', 'com', 'org', 'net', 'gov', 'ac', 'edu'};

/// Human name of a site: "https://www.netflix.com/browse" → "Netflix", "mail.google.co.uk" → "Google".
String siteName(Uri uri) {
  final labels = uri.host.toLowerCase().split('.').where((l) => l.isNotEmpty).toList();
  if (labels.isEmpty) return '';
  if (labels.length == 1) return _capitalize(labels.first);
  var i = labels.length - 2;
  if (labels.length >= 3 && _secondLevel.contains(labels[i]) && labels.last.length == 2) i--;
  return _capitalize(labels[i]);
}

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
