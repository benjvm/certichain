import 'dart:convert';

/// Reject duplicate keys (including escaped equivalents) and bound parser work.
Object? decodeStrictJson(String source, {int maxBytes = 16384}) {
  if (source.length > maxBytes || utf8.encode(source).length > maxBytes) {
    throw const FormatException('JSON too large');
  }
  var at = 0, nodes = 0;
  Never fail() => throw const FormatException('Invalid JSON');
  void space() {
    while (at < source.length && ' \t\r\n'.contains(source[at])) {
      at++;
    }
  }

  String string() {
    final start = at++;
    while (at < source.length) {
      final c = source[at++];
      if (c == '\\') {
        at++;
        continue;
      }
      if (c == '"') return jsonDecode(source.substring(start, at)) as String;
    }
    return fail();
  }

  Object? value(int depth) {
    if (depth > 16 || ++nodes > 4096) fail();
    space();
    if (at >= source.length) fail();
    if (source[at] == '"') return string();
    if (source[at] == '{') {
      at++;
      space();
      final result = <String, Object?>{};
      if (at < source.length && source[at] == '}') {
        at++;
        return result;
      }
      while (true) {
        space();
        if (at >= source.length || source[at] != '"') fail();
        final key = string();
        space();
        if (result.containsKey(key) ||
            at >= source.length ||
            source[at++] != ':') {
          fail();
        }
        result[key] = value(depth + 1);
        space();
        if (at >= source.length) fail();
        final next = source[at++];
        if (next == '}') return result;
        if (next != ',') fail();
      }
    }
    if (source[at] == '[') {
      at++;
      space();
      final result = <Object?>[];
      if (at < source.length && source[at] == ']') {
        at++;
        return result;
      }
      while (true) {
        result.add(value(depth + 1));
        space();
        if (at >= source.length) fail();
        final next = source[at++];
        if (next == ']') return result;
        if (next != ',') fail();
      }
    }
    final token = RegExp(
      r'^(?:null|true|false|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)',
    ).firstMatch(source.substring(at));
    if (token == null) fail();
    at += token.end;
    final result = jsonDecode(token.group(0)!);
    if (result is num && !result.isFinite) fail();
    return result as Object?;
  }

  final result = value(0);
  space();
  if (at != source.length) fail();
  return result;
}

Map<String, Object?> closedObject(Object? value, Set<String> keys) {
  if (value is! Map<String, Object?> ||
      value.length != keys.length ||
      !value.keys.every(keys.contains)) {
    throw const FormatException('Invalid DTO');
  }
  return value;
}
