## 0.1.2


## 0.1.0

- Initial release
- Dio Interceptor with automatic span creation
- W3C traceparent injection on every request
- HTTP semantic attributes (method, url, host, status_code)
- Error recording with DioException message, type, and stack trace
- Extension method: `dio.addOtelInterceptor(tracer)`
