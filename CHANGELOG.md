## 0.1.6

- Includes 0.1.4 and 0.1.5 below, which were tagged but never published to pub.dev.
- Releases are now published from GitHub Actions on version tags.

## 0.1.5

- `OtelDioInterceptor` emits the stable OpenTelemetry HTTP client semantic conventions (`http.request.method`, `url.full`, `url.scheme`, `server.address`, `server.port` and `http.response.status_code`) alongside the legacy `http.method`, `http.url`, `http.host` and `http.status_code` keys.

## 0.1.4

- Version bump only, no code changes.

## 0.1.3

- No release notes were recorded for this version.

## 0.1.2

- No release notes were recorded for this version.

## 0.1.0

- Initial release
- Dio Interceptor with automatic span creation
- W3C traceparent injection on every request
- HTTP semantic attributes (method, url, host, status_code)
- Error recording with DioException message, type, and stack trace
- Extension method: `dio.addOtelInterceptor(tracer)`
