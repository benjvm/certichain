import 'dart:async';
import 'dart:js_interop';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

http.Client createPublicHttpClient() => _AnonymousFetchClient();

// BrowserClient's withCredentials=false still sends SAME-ORIGIN cookies.
// Explicit omit is needed even when a deployment proxies Edge under the app.
class _AnonymousFetchClient extends http.BaseClient {
  final _requests = <web.AbortController>{};
  bool _closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) throw http.ClientException('Public client closed');
    if (request.headers.keys.any(
      (k) =>
          const ['authorization', 'apikey', 'cookie'].contains(k.toLowerCase()),
    )) {
      throw http.ClientException('Credentials forbidden in public client');
    }
    final abort = web.AbortController();
    _requests.add(abort);
    if (request case http.Abortable(:final abortTrigger?)) {
      unawaited(abortTrigger.whenComplete(() => abort.abort()));
    }
    try {
      final bytes = await request.finalize().toBytes();
      final response = await web.window
          .fetch(
            request.url.toString().toJS,
            web.RequestInit(
              method: request.method,
              body: bytes.toJS,
              headers: request.headers.jsify() as web.HeadersInit,
              credentials: 'omit',
              redirect: 'error',
              cache: 'no-store',
              referrerPolicy: 'no-referrer',
              signal: abort.signal,
            ),
          )
          .toDart;
      final headers = <String, String>{};
      for (final name in const [
        'retry-after',
        'content-type',
        'content-length',
        'cache-control',
      ]) {
        final value = response.headers.get(name);
        if (value != null) headers[name] = value;
      }
      final reader =
          response.body?.getReader() as web.ReadableStreamDefaultReader?;
      Stream<List<int>> body() async* {
        try {
          if (reader != null) {
            while (true) {
              final chunk = await reader.read().toDart;
              if (chunk.done) break;
              yield (chunk.value! as JSUint8Array).toDart;
            }
          }
        } catch (_) {
          throw http.ClientException('Public response stream failed');
        } finally {
          abort.abort();
          _requests.remove(abort);
          if (reader != null) {
            await reader.cancel().toDart.catchError((Object _) => null);
            reader.releaseLock();
          }
        }
      }

      return http.StreamedResponse(
        body(),
        response.status,
        headers: headers,
        request: request,
      );
    } catch (_) {
      abort.abort();
      _requests.remove(abort);
      throw http.ClientException('Public request failed');
    }
  }

  @override
  void close() {
    _closed = true;
    for (final request in _requests) {
      request.abort();
    }
    _requests.clear();
  }
}
