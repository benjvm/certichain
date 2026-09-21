import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app/config/app_config.dart';

void main() {
  test('missing and invalid configuration fails without echoing values', () {
    for (final entry in [
      ('', ''),
      ('https://private:password@example.com', 'sensitive'),
      ('https://example.com', 'sb_secret_sensitive'),
      ('https://example.com', ''),
    ]) {
      try {
        AppConfig(supabaseUrl: entry.$1, supabasePublishableKey: entry.$2);
        fail('Expected invalid configuration');
      } on FormatException catch (error) {
        expect(error.toString(), isNot(contains('sensitive')));
        expect(error.toString(), isNot(contains('password')));
        expect(error.toString(), contains('SUPABASE_'));
      }
    }
  });

  test('HTTPS public keys and debug local URLs are accepted', () {
    expect(
      AppConfig(
        supabaseUrl: 'https://example.com',
        supabasePublishableKey: 'sb_publishable_test',
      ).supabaseUrl,
      'https://example.com',
    );
    for (final host in ['127.0.0.1', '10.0.2.2']) {
      final url = 'http://$host:54321';
      expect(
        AppConfig(
          supabaseUrl: url,
          supabasePublishableKey: 'sb_publishable_test',
          allowLocalHttp: true,
        ).supabaseUrl,
        url,
      );
      expect(
        () => AppConfig(
          supabaseUrl: url,
          supabasePublishableKey: 'sb_publishable_test',
        ),
        throwsFormatException,
      );
    }
    expect(
      () => AppConfig(
        supabaseUrl: 'http://example.com',
        supabasePublishableKey: 'sb_publishable_test',
        allowLocalHttp: true,
      ),
      throwsFormatException,
    );
  });

  test('legacy anon allowed, privileged JWT rejected', () {
    for (final role in ['anon', 'service_role']) {
      final key =
          'e30.${base64Url.encode(utf8.encode(jsonEncode({'role': role})))}.signature';
      AppConfig create() => AppConfig(
        supabaseUrl: 'https://example.com',
        supabasePublishableKey: key,
      );
      if (role == 'anon') {
        expect(create, returnsNormally);
      } else {
        expect(create, throwsFormatException);
      }
    }
  });
}
