import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:purple_otel_sdk/purple_otel_sdk.dart';
import 'package:purple_otel_dio/purple_otel_dio.dart';
import 'package:test/test.dart';

final class _MockAdapter implements HttpClientAdapter {
  final int _status;
  final Map<String, String> _requestHeaders = {};

  _MockAdapter({int status = 200}) : _status = status;

  Map<String, String> get requestHeaders => _requestHeaders;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    _requestHeaders
        .addAll(options.headers.map((k, v) => MapEntry(k, v.toString())));
    return ResponseBody.fromString('{"ok":true}', _status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

final class _CaptureExporter implements SpanExporter {
  final List<Span> exported = [];
  @override
  Future<ExportResult> export(List<Span> items) async {
    exported.addAll(items);
    return ExportResult.success();
  }

  @override
  Future<void> shutdown() async {}
  @override
  Future<void> forceFlush() async {}
}

void main() {
  group('OtelDioInterceptor', () {
    test('creates span and injects traceparent on GET', () async {
      final exporter = _CaptureExporter();
      final provider = SDKTracerProvider(
        resource: Resource.empty,
        processors: [SimpleSpanProcessor(exporter)],
      );
      final mockAdapter = _MockAdapter();

      final dio = Dio()
        ..httpClientAdapter = mockAdapter
        ..addOtelInterceptor(provider.get('dio'))
        ..options.responseType = ResponseType.json;

      await dio.get('https://api.example.com/users');

      expect(mockAdapter.requestHeaders.containsKey('traceparent'), isTrue);
      expect(exporter.exported.length, 1);
    });

    test('completes span on successful response', () async {
      final exporter = _CaptureExporter();
      final provider = SDKTracerProvider(
        resource: Resource.empty,
        processors: [SimpleSpanProcessor(exporter)],
      );
      final dio = Dio()
        ..httpClientAdapter = _MockAdapter()
        ..addOtelInterceptor(provider.get('dio'));

      await dio.get('https://api.example.com/data');

      final span = exporter.exported.first as SDKSpan;
      expect(span.status.code, StatusCode.ok);
      expect(span.name, contains('GET'));
    });

    test('records error span on connection failure', () async {
      final exporter = _CaptureExporter();
      final provider = SDKTracerProvider(
        resource: Resource.empty,
        processors: [SimpleSpanProcessor(exporter)],
      );
      final dio = Dio()
        ..httpClientAdapter = _FailingAdapter()
        ..addOtelInterceptor(provider.get('dio'));

      try {
        await dio.get('https://unreachable.example.com');
      } catch (_) {}

      expect(exporter.exported.length, 1);
      final span = exporter.exported.first as SDKSpan;
      expect(span.status.code, StatusCode.error);
    });
  });
}

final class _FailingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(
      requestOptions: options,
      message: 'Connection refused',
      type: DioExceptionType.connectionError,
    );
  }

  @override
  void close({bool force = false}) {}
}
