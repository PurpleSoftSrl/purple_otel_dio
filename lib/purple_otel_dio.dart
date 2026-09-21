import 'package:dio/dio.dart';
import 'package:purple_otel_sdk/purple_otel_sdk.dart';

final class OtelDioInterceptor extends Interceptor {
  final Tracer _tracer;

  OtelDioInterceptor({required Tracer tracer}) : _tracer = tracer;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final span = _tracer.startSpan(
      '${options.method} ${options.uri.host}${options.uri.path}',
      kind: SpanKind.client,
    );

    span.setAttribute('http.method', AttributeValue.string(options.method));
    span.setAttribute(
        'http.url', AttributeValue.string(options.uri.toString()));
    span.setAttribute('http.host', AttributeValue.string(options.uri.host));

    // Stable OTel HTTP client semantic conventions (v1.23+), emitted alongside
    // the legacy http.* keys above during the transition to the stable spec.
    span.setAttribute(
        'http.request.method', AttributeValue.string(options.method));
    span.setAttribute(
        'url.full', AttributeValue.string(options.uri.toString()));
    span.setAttribute('url.scheme', AttributeValue.string(options.uri.scheme));
    span.setAttribute(
        'server.address', AttributeValue.string(options.uri.host));
    span.setAttribute('server.port', AttributeValue.int(options.uri.port));

    final carrier = <String, String>{};
    final ctx = Context.root.withValue(spanContextKey, span);
    W3CTraceContextPropagator.inject(ctx, carrier);

    for (final entry in carrier.entries) {
      options.headers[entry.key] = entry.value;
    }

    options.extra['otel_span'] = span;
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final span = response.requestOptions.extra['otel_span'] as Span?;
    if (span == null) return handler.next(response);

    span.setAttribute(
        'http.status_code', AttributeValue.int(response.statusCode ?? 0));
    span.setAttribute('http.response.status_code',
        AttributeValue.int(response.statusCode ?? 0));

    if (response.statusCode != null && response.statusCode! >= 500) {
      span.setStatus(SpanStatus.error('HTTP ${response.statusCode}'));
    } else if (response.statusCode != null && response.statusCode! >= 400) {
      span.setStatus(SpanStatus.error('HTTP ${response.statusCode}'));
    } else {
      span.setStatus(SpanStatus.ok);
    }

    span.end();
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final span = err.requestOptions.extra['otel_span'] as Span?;
    if (span == null) return handler.next(err);

    span.recordException(err, stackTrace: err.stackTrace);
    span.setStatus(SpanStatus.error('${err.type.name}: ${err.message}'));
    span.end();
    handler.next(err);
  }
}

extension OtelDioExtension on Dio {
  void addOtelInterceptor(Tracer tracer) {
    interceptors.add(OtelDioInterceptor(tracer: tracer));
  }
}
