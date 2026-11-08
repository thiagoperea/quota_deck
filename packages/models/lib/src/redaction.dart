final List<(RegExp, String)> _patterns = [
  (RegExp(r'oc_[A-Za-z0-9_-]{20,}'), 'oc_<redacted>'),
  (RegExp(r'sk-ant-[A-Za-z0-9_-]{20,}'), 'sk-ant-<redacted>'),
  (RegExp(r'sk-[A-Za-z0-9_-]{20,}'), 'sk-<redacted>'),
  (RegExp(r'ya29\.[A-Za-z0-9._-]+'), 'ya29.<redacted>'),
  (RegExp(r'eyJ[A-Za-z0-9._-]{20,}'), '<jwt>'),
  (
    RegExp(r'go-keyring-base64:[A-Za-z0-9+/=]+'),
    'go-keyring-base64:<redacted>',
  ),
  (
    RegExp(r'(Bearer\s+)[A-Za-z0-9._-]+', caseSensitive: false),
    r'$1<redacted>',
  ),
  (
    RegExp(
      r'((?:token|secret|key|authorization|cookie|password)\s*[:=]\s*)[^\s,}]+',
      caseSensitive: false,
    ),
    r'$1<redacted>',
  ),
];

String _apply(RegExp pattern, String replacement, String input) {
  return input.replaceAllMapped(pattern, (match) {
    if (!replacement.contains(r'$1')) return replacement;
    final group = match.groupCount >= 1 ? (match.group(1) ?? '') : '';
    return replacement.replaceAll(r'$1', group);
  });
}

String redact(String input) {
  var out = input;
  for (final (pattern, replacement) in _patterns) {
    out = _apply(pattern, replacement, out);
  }
  return out;
}

bool isSensitiveKey(String key) {
  final k = key.toLowerCase().replaceAll(RegExp(r'[-_]'), '');
  return k.contains('token') ||
      k.contains('secret') ||
      k.contains('password') ||
      k.contains('authorization') ||
      k.contains('cookie') ||
      k.contains('apikey') ||
      k.contains('credential');
}

String maskEmail(String? email) {
  if (email == null || email.isEmpty || !email.contains('@')) {
    return email ?? '';
  }
  final at = email.indexOf('@');
  final user = email.substring(0, at);
  final domain = email.substring(at + 1);
  final dot = domain.lastIndexOf('.');
  final tld = dot >= 0 ? domain.substring(dot) : '';
  final maskedUser = user.length > 2
      ? '${user.substring(0, 2)}***'
      : '$user***';
  final maskedDomain = domain.isEmpty ? '' : '${domain[0]}***$tld';
  return '$maskedUser@$maskedDomain';
}
