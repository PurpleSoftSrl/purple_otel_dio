# purple_otel_dio

[![Pub Version](https://img.shields.io/pub/v/purple_otel_dio.svg)](https://pub.dev/packages/purple_otel_dio)
[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](LICENSE)
[![Dart](https://img.shields.io/badge/dart-%3E%3D3.2.0-blue.svg)](https://dart.dev)
[![Tests](https://img.shields.io/badge/tests-passed-brightgreen.svg)](test/)

**Zero-code distributed tracing for every Dio HTTP request.**

Add one line to your `Dio` instance and every outbound request becomes a fully traced
[OpenTelemetry](https://opentelemetry.io/) span — complete with W3C trace context
propagation, semantic HTTP attributes, error recording, and automatic span lifecycle
management. No manual span creation. No boilerplate. Just plug it in and your HTTP
traces appear in your backend.

---

## Features

- **Automatic `CLIENT` spans** — every request creates an OTel span named `GET api.example.com/users`, tagged with `SpanKind.client`, via Dio's interceptor chain
- **W3C `traceparent` injection** — trace context propagates automatically in outgoing request headers so downstream services link correctly in distributed traces
- **HTTP semantic attributes** — `http.method`, `http.url`, `http.host`, and `http.status_code` are set on every span, conforming to the [OpenTelemetry HTTP semantic conventions](https://opentelemetry.io/docs/specs/semconv/http/)
- **Error recording** — `DioException` failures capture the exception message, type, stack trace (`span.recordException`), and mark the span as errored
- **Status mapping** — 4xx and 5xx responses automatically set the span to error status; 2xx responses mark it ok
- **Extension method** — `.addOtelInterceptor(tracer)` on any `Dio` instance — no subclassing, no mixins, no DI tricks
- **Powered by `purple_otel_sdk`** — leverages the full OpenTelemetry SDK (sampling, batch processing, OTLP export, context propagation) under the hood

---

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  purple_otel_dio: ^0.1.0
  purple_otel_sdk: ^0.1.0   # required peer — provides Tracer, Span, exporters
  dio: ^5.7.0                 # the HTTP client being instrumented
```

Then run:

```bash
dart pub get
```

---

## Quick Start

Below is a complete, runnable example that wires up a `Dio` client with tracing
and exports spans to an OTLP collector (e.g. Jaeger, Grafana Tempo, Azure Monitor).

```dart
import 'package:dio/dio.dart';
import 'package:purple_otel_sdk/purple_otel_sdk.dart';
import 'package:purple_otel_dio/purple_otel_dio.dart';

Future<void> main() async {
  // 1. Create the OTel tracer provider with an OTLP exporter
  final tracerProvider = SDKTracerProvider(
    resource: Resource(
      attributes: [
        Attribute('service.name', AttributeValue.string('my-flutter-app')),
        Attribute('service.version', AttributeValue.string('1.0.0')),
      ],
    ),
    processors: [
      BatchSpanProcessor(
        OtlpHttpSpanExporter(
          endpoint: Uri.parse('http://localhost:4318/v1/traces'),
        ),
      ),
    ],
  );

  // 2. Get a named tracer
  final tracer = tracerProvider.get('http-client');

  // 3. Create Dio and add the interceptor — one line
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
    ..addOtelInterceptor(tracer);

  // 4. Every request automatically produces a traced span
  final users = await dio.get('/users');
  final posts = await dio.get('/posts');
  final result = await dio.post('/search', data: {'query': 'Flutter'});

  print('Status: ${users.statusCode}');

  // 5. Shut down to flush pending spans
  await tracerProvider.shutdown();
}
```

**What happens at runtime:**

1. `dio.get('/users')` fires → interceptor creates a span named `GET api.example.com/users`
2. A `traceparent` header is injected into the request (e.g. `00-<trace-id>-<span-id>-01`)
3. The response arrives → `http.status_code=200` is recorded, span marked OK, span ended
4. All three spans are exported as a batch to `localhost:4318/v1/traces`

---

## Before / After

### Without `purple_otel_dio` (~25 lines per endpoint)

```dart
Future<Response> getUsers(Dio dio, Tracer tracer) async {
  final span = tracer.startSpan('GET api.example.com/users',
      kind: SpanKind.client);
  span.setAttribute('http.method', AttributeValue.string('GET'));
  span.setAttribute('http.url',
      AttributeValue.string('https://api.example.com/users'));

  final carrier = <String, String>{};
  W3CTraceContextPropagator.inject(
      Context.root.withValue(spanContextKey, span), carrier);

  try {
    final response = await dio.get('/users',
        options: Options(headers: carrier));
    span.setAttribute('http.status_code',
        AttributeValue.int(response.statusCode ?? 0));
    span.setStatus(response.statusCode == 200
        ? SpanStatus.ok
        : SpanStatus.error('HTTP ${response.statusCode}'));
    return response;
  } on DioException catch (e) {
    span.recordException(e, stackTrace: e.stackTrace);
    span.setStatus(SpanStatus.error('${e.type.name}: ${e.message}'));
    rethrow;
  } finally {
    span.end();
  }
}
```

### With `purple_otel_dio` (1 line, once)

```dart
final dio = Dio()..addOtelInterceptor(tracer);

// That's it. All get/post/put/delete requests are traced.
final users = await dio.get('/users');
final posts = await dio.get('/posts');
final result = await dio.post('/search', data: {'query': 'Flutter'});
```

**Savings:** ~25 lines of manual instrumentation per endpoint → 1 line of setup total.
For an app with 10 API calls, that's ~250 lines eliminated.

---

## Interceptor Lifecycle

| Dio Hook | OTel Action | Details |
|---|---|---|
| `onRequest` | **Create span** | Starts a new `CLIENT` span named `{METHOD} {host}{path}`, sets `http.method`, `http.url`, `http.host` attributes |
| `onRequest` | **Inject traceparent** | Uses `W3CTraceContextPropagator.inject()` to add `traceparent` (and optionally `tracestate`) to the request headers |
| `onRequest` | **Store span** | Saves the span reference in `options.extra['otel_span']` for retrieval in `onResponse` / `onError` |
| `onResponse` | **Record status** | Sets `http.status_code` attribute from the response |
| `onResponse` | **Map status** | `statusCode >= 400` → span error; otherwise → span OK |
| `onResponse` | **End span** | Calls `span.end()`, closing the span timing |
| `onError` | **Record exception** | Calls `span.recordException(err, stackTrace: err.stackTrace)` |
| `onError` | **Set error** | Marks the span status as error with `{type}: {message}` |
| `onError` | **End span** | Calls `span.end()` so the error span is exported |

---

## How It Works

```
                     ┌─────────────────────────────────┐
                     │          Your Flutter App        │
                     │                                 │
                     │   dio.get('/users')              │
                     │         │                       │
                     │         ▼                       │
                     │  ┌──────────────────────────┐   │
                     │  │   OtelDioInterceptor      │   │
                     │  │                           │   │
                     │  │  onRequest:               │   │
                     │  │   1. tracer.startSpan()   │   │
                     │  │   2. set http.* attributes│   │
                     │  │   3. inject traceparent   │──────── traceparent: 00-abc123-def456-01
                     │  │   4. store span in extra  │   │
                     │  │                           │   │
                     │  │  onResponse:              │   │
                     │  │   5. set http.status_code │   │
                     │  │   6. set span status      │   │
                     │  │   7. span.end()           │   │
                     │  │                           │   │
                     │  │  onError:                 │   │
                     │  │   8. recordException()    │   │
                     │  │   9. set span status      │   │
                     │  │  10. span.end()           │   │
                     │  └──────────┬───────────────┘   │
                     │             │                   │
                     └─────────────┼───────────────────┘
                                   │
                     ┌─────────────▼───────────────────┐
                     │     SpanProcessor Pipeline      │
                     │                                 │
                     │  SimpleSpanProcessor /          │
                     │  BatchSpanProcessor             │
                     │         │                       │
                     │         ▼                       │
                     │  SpanExporter (OTLP / Console)  │
                     └─────────────┬───────────────────┘
                                   │
                                   ▼
                     ┌─────────────────────────────────┐
                     │  OTLP Collector / Backend       │
                     │  (Jaeger, Grafana Tempo, etc.)  │
                     └─────────────────────────────────┘
```

1. Your code calls `dio.get(...)` as usual
2. Dio invokes `onRequest` — the interceptor creates an OTel span, attaches HTTP attributes, and injects the `traceparent` header so the receiving service can continue the trace
3. Dio sends the HTTP request (now with distributed tracing headers)
4. When the response arrives, `onResponse` records the status code, maps the span status, and ends the span
5. If the request fails, `onError` records the exception with stack trace and ends the span as errored
6. The finished span flows through the configured `SpanProcessor` pipeline and is exported to your observability backend

---

## Real-World Example

A typical Flutter app with multiple API endpoints — all traced with zero ceremony:

```dart
import 'package:dio/dio.dart';
import 'package:purple_otel_sdk/purple_otel_sdk.dart';
import 'package:purple_otel_dio/purple_otel_dio.dart';

class ApiClient {
  late final Dio _dio;

  ApiClient({required Tracer tracer}) {
    _dio = Dio(BaseOptions(baseUrl: 'https://jsonplaceholder.typicode.com'))
      ..addOtelInterceptor(tracer);
  }

  Future<Response> getUsers() => _dio.get('/users');
  Future<Response> getUser(int id) => _dio.get('/users/$id');
  Future<Response> createPost(Map<String, dynamic> data) =>
      _dio.post('/posts', data: data);
  Future<Response> updatePost(int id, Map<String, dynamic> data) =>
      _dio.put('/posts/$id', data: data);
  Future<Response> deletePost(int id) => _dio.delete('/posts/$id');
}

Future<void> main() async {
  final tracerProvider = SDKTracerProvider(
    resource: Resource.empty,
    processors: [SimpleSpanProcessor(ConsoleSpanExporter())],
  );
  final tracer = tracerProvider.get('api-client');

  final api = ApiClient(tracer: tracer);

  // Each of these creates a distinct span with full HTTP attributes:
  //
  //   GET  jsonplaceholder.typicode.com/users        (200 OK)
  //   GET  jsonplaceholder.typicode.com/users/1       (200 OK)
  //   POST jsonplaceholder.typicode.com/posts         (201 Created)
  //   PUT  jsonplaceholder.typicode.com/posts/1       (200 OK)
  //   DELETE jsonplaceholder.typicode.com/posts/1     (200 OK)

  await api.getUsers();
  await api.getUser(1);
  await api.createPost({'title': 'Hello', 'body': 'World', 'userId': 1});
  await api.updatePost(1, {'title': 'Updated'});
  await api.deletePost(1);

  await tracerProvider.shutdown();
}
```

Every endpoint call above generates a properly-named span with the correct
HTTP method, full URL, status code, and W3C trace context — all without a
single line of manual instrumentation in `ApiClient`.

---

## Companion Packages

`purple_otel_dio` is part of the Purple OTel ecosystem:

| Package | Description |
|---|---|
| [`purple_otel_api`](https://pub.dev/packages/purple_otel_api) | OpenTelemetry API contracts — `Tracer`, `Span`, `Context`, `Attribute`, etc. |
| [`purple_otel_sdk`](https://pub.dev/packages/purple_otel_sdk) | OpenTelemetry SDK implementation — `SDKTracerProvider`, exporters, processors, samplers |
| `purple_otel_dio` | **This package** — auto-instrumentation for Dio HTTP client |
| [`purple_otel_flutter`](https://pub.dev/packages/purple_otel_flutter) | Flutter-specific instrumentation — navigation observers, widget lifecycle spans |
| [`purple_logger`](https://pub.dev/packages/purple_logger) | Structured logging framework |
| [`purple_logger_otel`](https://pub.dev/packages/purple_logger_otel) | Bridge: send `purple_logger` records as OTel log records |
| [`purple_logger_otel_sdk`](https://pub.dev/packages/purple_logger_otel_sdk) | OTel SDK log exporter integration for `purple_logger` |

---

---

---


---

## Built by PurpleSoft

**[PurpleSoft S.r.l.](https://www.purplesoft.io)** — software house with offices in Monza, Milano, and Lugano (Switzerland). Since 2017, we've been the team that companies call when the problem is too hard, too critical, or too late to fail.

> We build what doesn't exist yet.

### What we do

We don't "consult and recommend." We ship. Our engineers write production code across every layer of the stack — from bare-metal native bindings to cloud-native infrastructure, from machine learning pipelines to pixel-perfect mobile UI.

We ship mobile apps that control physical payment terminals via Flutter. We deploy ONNX AI models that run on phones instead of servers. We migrate enterprise ERP systems from SAP ECC to SAP S/4HANA without downtime, moving billions in financial transactions. We build distributed tracing pipelines that survive Black Friday traffic without dropping a single span. We write Flutter plugins for hardware that doesn't have one yet, and Dart packages for observability infrastructure the ecosystem was missing.

---

### Our proprietary SDK portfolio

When off-the-shelf solutions fall short, we build our own. These 10 SDKs are battle-tested across our enterprise projects:

| SDK | Capability |
|-----|-----------|
| **Purple.Authentication** | OAuth 2.0 / OpenID Connect — Google, Apple, Microsoft, Facebook, Instagram, LinkedIn, GitHub, and custom identity providers |
| **Purple.Authorization** | Role-based access control with granular permissions and custom policy rules |
| **Purple.Security** | Post-quantum cryptography using NIST-approved algorithms (CRYSTALS-Kyber, CRYSTALS-Dilithium) |
| **Purple.Payments** | Unified payment abstraction — PayPal, Stripe, SumUp, Nexi, GestPay, Google Pay, Apple Pay, Bitcoin, Ethereum, and 100+ cryptocurrencies |
| **Purple.Notification** | Cross-platform push notifications — iOS (APNs) and Android (FCM) with server-side batching |
| **Purple.Email** | Transactional email and marketing automation — SMTP, SendGrid, MailChimp, MailUp, Sendinblue, MailGun |
| **Purple.Bot** | Multi-platform chatbot integration — Telegram, WhatsApp Business API, Facebook Messenger |
| **Purple.Storage** | Cloud storage abstraction — Azure Blob Storage, Amazon S3, Google Cloud Storage, local filesystem |
| **Purple.Media** | Media processing — compression, format conversion, deduplication, client-side encryption |
| **Purple.Localization** | Multi-platform i18n — Flutter, Angular, VanillaJS, .NET with centralized translation management |

---

### Open source we maintain and contribute to

We don't just consume open source — we build and maintain it:

| Area | What we ship |
|------|-------------|
| **Observability** | Complete OpenTelemetry SDK for Dart/Flutter (traces, logs, metrics, OTLP export), enterprise structured logger with file rotation, auto-instrumentation for HTTP, Dio, and Flutter |
| **On-device AI** | ONNX runtime bindings for Dart with GPU acceleration, Litert/MediaPipe integration for LLM inference, neural text-to-speech (Kokoro engine) across all 6 Flutter platforms |
| **Speech** | Speech-to-text for Android and Windows, wake-word detection, Italian dialect support |
| **Payments** | Official Flutter plugin for SumUp POS terminals (card-present payments, NFC, receipt printing) |
| **Platform** | iOS Live Activities & Dynamic Island, high-performance in-memory cache with journaling, OpenAPI → Dart code generator |
| **Upstream** | Active contributions to HuggingFace Transformers, Microsoft Model Context Protocol SDK (official C# implementation), Ethereum EIP-2535 Diamond standard, ESP-OPUS audio codec |

---

### Microsoft Partner since 2018 · SumUp Partner · Dell Partner

---

### Trusted by

`ABB` `Intesa Sanpaolo` `Tenaris` `Reply` `Aubay` `Comune di Milano` `BCC` `FIMAP` `Alten` `Altran` `Prometeia` `illimity` `Be Shaping the Future` `DS Group` `NVALUE` `Inoptim` `Docflow` `P&C`

*and 40+ other enterprises across banking, manufacturing, energy, and public sector.*

---

> Your project can't wait. We've solved these exact problems for companies you know.
> Let's solve them for you.

[🌐 **purplesoft.io**](https://www.purplesoft.io) &nbsp;·&nbsp; [📧 **developers@purplesoft.io**](mailto:developers@purplesoft.io) &nbsp;·&nbsp; [📞 **+39 0362 148 3978**](tel:+3903621483978) &nbsp;·&nbsp; [💼 **LinkedIn**](https://www.linkedin.com/company/purplesoft-srl) &nbsp;·&nbsp; [🐙 **GitHub**](https://github.com/purplesoftsrl)

## License

GNU Affero General Public License v3.0 — see [LICENSE](LICENSE) for the full text.









