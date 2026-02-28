import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:synthetic_api_cli/src/server.dart';

late int testPort;
late dynamic closeServer;

void main() {
  setUp(() async {
    final result = await startServer(
      configPath: 'synthetic-api.config.json',
      port: 0, // port 0 = OS picks a free port
      watchConfig: false,
    );
    testPort = result.port;
    closeServer = result.close;
  });

  tearDown(() async {
    await closeServer();
  });

  group('server test', () {
    test("serve health endpoint", () async {
      final response = await invoke(path: "/health");

      expect(response.status, 200);
      expect(response.body['status'], "ok");
      expect(response.body['timestamp'], isA<String>());
    });

    test("serves routes index endpoint", () async {
      final response = await invoke(path: "/__routes");

      expect(response.status, 200);
      expect(response.body['routes'] is List, true);
      expect(response.body['routes'].any((entry) => entry['path'] == "/health"),
          true);
      expect(
          response.body['routes'].any((entry) => entry['path'] == "/__routes"),
          true);
      expect(response.body['routes'].any((entry) => entry['path'] == "/users"),
          true);
    });

    test('serves paginated users', () async {
      final response = await invoke(path: "/users?page=2&limit=3");

      expect(response.status, 200);
      expect(response.body['data'] is List, true);
      expect((response.body['data'] as List).length, 3);
      expect(response.body['pagination']['page'], 2);
      expect(response.body['pagination']['limit'], 3);
    });

    test('serves cursor paginated friends - last page', () async {
      final response = await invoke(path: "/friends?cursor=6&limit=3");

      expect(response.status, 200);
      expect(response.body['data'] is List, true);
      expect((response.body['data'] as List).length, 1);
      expect(response.body['pagination']['type'], 'cursor');
      expect(response.body['pagination']['nextCursor'], null);
      expect(response.body['pagination']['total'], 7);
    });

    test('simulates error with probability 1.0', () async {
      final response = await invoke(path: "/unstable");

      expect(response.status, 503);
      expect(response.body['error'], 'always_fails');
      expect(response.body['message'], 'Guaranteed failure.');
    });

    test('serves root route', () async {
      final response = await invoke(path: "/");

      expect(response.status, 200);
      expect(response.body['name'], "synthetic-api");
      expect(response.body['message'], isA<String>());
      expect(response.body['docs'], isA<List>());
    });

    test('enforces bearer auth', () async {
      final response = await invoke(path: "/users/5");

      expect(response.status, 401);
      expect(response.body['error'], "unauthorized");
      expect(response.body['message'], "Missing or invalid token");

      final authenticatedResponse = await invoke(
          path: "/users/5", headers: {"Authorization": "Bearer demo-token"});

      expect(authenticatedResponse.status, 200);
      expect(authenticatedResponse.body['userId'], "5");
    });

    test('validates request body', () async {
      final response = await invoke(
          path: "/auth/login",
          method: "POST",
          body: jsonEncode({"username": "test"}));

      expect(response.status, 400);
      expect(response.body['error'], "validation_error");
      expect(response.body['details'] is List, true);
    });

    test("applies CORS headers to normal and preflight requests", () async {
      final normal = await invoke(
          path: "/health", headers: {"origin": "https://frontend.example"});

      expect(normal.status, 200);
      expect(normal.headers.value('access-control-allow-origin'), isNotNull);
      expect(normal.headers.value('access-control-allow-methods'), isNotNull);

      final preflight =
          await invoke(path: "/users", method: "OPTIONS", headers: {
        "origin": "https://frontend.example",
        "access-control-request-method": "GET",
        "access-control-request-headers": "content-type,authorization"
      });

      expect(preflight.status, 204);
      expect(preflight.body, null);
      expect(preflight.headers.value('access-control-allow-origin'), isNotNull);
      expect(
          preflight.headers.value('access-control-allow-methods'), isNotNull);
    });

    test("returns not_found for preflight on undeclared route", () async {
      final response = await invoke(
          path: "/does-not-exist",
          method: "OPTIONS",
          headers: {
            "origin": "https://frontend.example",
            "access-control-request-method": "GET"
          });

      expect(response.status, 404);
      expect(response.body['error'], "not_found");
      expect(response.headers.value('access-control-allow-origin'), isNotNull);
    });
  });
}

Future<({dynamic body, HttpHeaders headers, int status})> invoke({
  String method = 'GET',
  String path = '/',
  Map<String, String> headers = const {},
  String? body,
  int? customPort,
}) async {
  final client = HttpClient();
  final port = customPort ?? testPort;
  final request = await client.openUrl(
    method,
    Uri.parse('http://localhost:$port$path'),
  );

  headers.forEach((key, value) {
    request.headers.set(key, value);
  });

  if (body != null) {
    request.write(body);
  }

  final response = await request.close();
  final responseBody = await response.transform(utf8.decoder).join();
  client.close();

  return (
    body: responseBody.isNotEmpty ? jsonDecode(responseBody) : null,
    headers: response.headers,
    status: response.statusCode,
  );
}
