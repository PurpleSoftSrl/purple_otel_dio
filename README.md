# PurpleOTel Dio Instrumentation

[![Pub Version](https://img.shields.io/pub/v/purple_otel_dio.svg)](https://pub.dev/packages/purple_otel_dio)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

Auto-instrumentation for [Dio](https://pub.dev/packages/dio) — the most popular HTTP client for Flutter. Every Dio request becomes a traced span.

## Features

- **Automatic CLIENT spans** — every request creates a span via Dio's interceptor chain
- **W3C traceparent injection** — auto-propagates trace context in request headers
- **HTTP semantic attributes** — `http.method`, `http.url`, `http.host`, `http.status_code`
- **Error recording** — `DioException` captured with message, type, and stack trace
- **Extension method** — `.addOtelInterceptor(tracer)` on any `Dio` instance

## Quick Start

```dart
import 'package:dio/dio.dart';
import 'package:purple_otel_sdk/purple_otel_sdk.dart';
import 'package:purple_otel_dio/purple_otel_dio.dart';

void main() async {
  final tracer = SDKTracerProvider(
    resource: Resource.empty,
    processors: [SimpleSpanProcessor(ConsoleSpanExporter())],
  ).get('dio-client');

  final dio = Dio()..addOtelInterceptor(tracer);

  // Every request auto-creates a span
  final response = await dio.get('https://api.example.com/users');

  // Spans include: http.method=GET, http.status_code=200,
  //                traceparent header auto-injected
}
```

## Interceptor Lifecycle

| Dio Hook | OTel Action |
|----------|-------------|
| `onRequest` | Creates span, injects traceparent header, stores span in `options.extra` |
| `onResponse` | Sets `http.status_code`, sets span status (ok/error), ends span |
| `onError` | Records exception + stack, sets error status, ends span |

## License

Apache-2.0 — see [LICENSE](LICENSE).
