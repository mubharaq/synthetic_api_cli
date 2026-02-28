import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as path;
import 'package:synthetic_api_cli/src/config.dart';
import 'package:synthetic_api_cli/src/validate.dart';
import 'package:synthetic_api_cli/src/validation_error.dart';

final _random = Random();

class CompiledRoute {
  final String method;
  final String path;
  final RegExp regex;
  final List<String> paramNames;
  final Map<String, dynamic> route;

  CompiledRoute({
    required this.method,
    required this.path,
    required this.regex,
    required this.paramNames,
    required this.route,
  });
}

class CorsSettings {
  final Object origin;
  final List<String> methods;
  final List<String> headers;
  final List<String> exposedHeaders;
  final bool allowCredentials;
  final int maxAge;

  CorsSettings({
    required this.origin,
    required this.methods,
    required this.headers,
    required this.exposedHeaders,
    required this.allowCredentials,
    required this.maxAge,
  });

  factory CorsSettings.defaults() {
    return CorsSettings(
      origin: '*',
      methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
      headers: ["content-type", "authorization", "x-api-key"],
      exposedHeaders: [],
      allowCredentials: false,
      maxAge: 600,
    );
  }
}

class HttpError {
  final int status;
  final String message;

  HttpError({required this.status, required this.message});
}

class Runtime {
  final Map<String, dynamic> config;
  final String configPath;
  final String configDir;
  final List<CompiledRoute> routes;
  final Map<String, dynamic> fixtureCache;

  Runtime({
    required this.config,
    required this.configPath,
    required this.configDir,
    required this.routes,
    required this.fixtureCache,
  });
}

Future<({int port, Future<void> Function() close})> startServer({
  required String configPath,
  int port = 4010,
  bool watchConfig = true,
}) async {
  var runtime = await createRuntime(configPath);

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  final activePort = server.port;
  print('synthetic-api running at http://localhost:$activePort');

  if (watchConfig) {
    File(runtime.configPath).watch().listen((_) async {
      try {
        runtime = await createRuntime(configPath);
        print('Reloaded config.');
      } catch (e) {
        print('Config reload failed: $e');
      }
    });
  }

  unawaited(server.forEach((request) {
    handleRequest(request, runtime);
  }));

  return (port: activePort, close: () => server.close());
}

Future<void> handleRequest(HttpRequest request, Runtime runtime) async {
  try {
    await _processRequest(request, runtime);
  } on HttpError catch (e) {
    _sendJson(request.response, e.status, {
      'error': 'request_error',
      'message': e.message,
    });
  } catch (e) {
    _sendJson(request.response, 500, {
      'error': 'internal_server_error',
      'message': e.toString(),
    });
  }
}

Future<void> _processRequest(HttpRequest request, Runtime runtime) async {
  final method = request.method.toUpperCase();
  final uri = request.uri;
  final pathname = uri.path;
  final headers = _normalizeHeaders(request.headers);
  final query = _parseQuery(uri.queryParameters);
  final cors = _getCorsSettings(runtime.config);

  if (cors != null) {
    _applyCorsHeaders(request.response, headers, cors);
    if (method == 'OPTIONS') {
      if (!_isKnownPath(pathname, runtime)) {
        await _sendJson(request.response, 404, {
          'error': 'not_found',
          'message': '$method $pathname is not declared.',
        });
        return;
      }
      await _sendEmpty(request.response, 204);
      return;
    }
  }

  if (await _handleSystemRoute(method, pathname, runtime, request.response)) {
    return;
  }
  final route = _matchRoute(runtime.routes, method, pathname);
  if (route == null) {
    await _sendJson(request.response, 404, {
      'error': 'not_found',
      'message': '$method $pathname is not declared.',
    });
    return;
  }

  final params = _extractParams(route, pathname);
  final body = await _readBody(request);

  final authError = _evaluateAuth(route, runtime.config, headers, query);
  if (authError != null) {
    await _sendJson(request.response, 401, authError);
    return;
  }

  final validationErrors = <ValidationError>[];
  if (route.route['querySchema'] != null) {
    validationErrors.addAll(validateData(query, route.route['querySchema']));
  }
  if (route.route['headersSchema'] != null) {
    validationErrors
        .addAll(validateData(headers, route.route['headersSchema']));
  }
  if (route.route['bodySchema'] != null) {
    validationErrors.addAll(validateData(body, route.route['bodySchema']));
  }

  if (validationErrors.isNotEmpty) {
    await _sendJson(request.response, 400, {
      'error': 'validation_error',
      'details': validationErrors.map((e) => e.toString()).toList(),
    });
    return;
  }
  final simulatedError = _pickErrors(route);
  if (simulatedError != null) {
    await Future.delayed(
        Duration(milliseconds: _getLatency(route, runtime.config)));
    await _sendJson(request.response, simulatedError['status'] as int, {
      'error': simulatedError['code'] ?? 'simulated_error',
      'message': simulatedError['message'] ?? 'Simulated error',
    });
    return;
  }
  final responseBody = await _buildResponseBody(route, runtime, {
    'params': params,
    'query': query,
    'body': body,
    'headers': headers,
  });
  await Future.delayed(
      Duration(milliseconds: _getLatency(route, runtime.config)));
  await _sendJson(request.response,
      route.route['response']['status'] as int? ?? 200, responseBody);
}

Future<dynamic> _buildResponseBody(
  CompiledRoute route,
  Runtime runtime,
  Map<String, dynamic> context,
) async {
  final response = route.route['response'] as Map<String, dynamic>;
  dynamic body;
  if (response.containsKey('body')) {
    body = jsonDecode(jsonEncode(response['body']));
  } else {
    body = await _loadFixture(response['bodyFrom'] as String, runtime);
  }
  final pagination = route.route['pagination'];
  if (pagination == null) {
    return _applyTemplate(body, context);
  }
  final dataSource = body is List ? body : body['data'] as List?;
  if (dataSource is! List) {
    return {
      'error': "invalid_pagination_source",
      'message': "Pagination requires an array response body or { data: [] }."
    };
  }
  final paginationType = pagination['type'] as String?;
  final limitParam = pagination['limitParam'] as String? ?? 'limit';
  final defaultLimit = pagination['defaultLimit'] as int? ?? 10;
  final queryLimit = context['query'][limitParam] as int?;
  final limit =
      (queryLimit != null && queryLimit > 0) ? queryLimit : defaultLimit;

  if (paginationType == "offset") {
    final pageParam = pagination['pageParam'] as String? ?? 'page';
    final queryPageParam = context['query'][pageParam] as int?;
    final page =
        queryPageParam != null && queryPageParam > 0 ? queryPageParam : 1;
    final start = (page - 1) * limit;
    final end = start + limit;
    final sliced = dataSource.sublist(start, end.clamp(0, dataSource.length));

    return {
      'data': _applyTemplate(jsonDecode(jsonEncode(sliced)), context),
      'pagination': {
        'type': "offset",
        'page': page,
        'limit': limit,
        'total': dataSource.length,
        'totalPages': max(1, (dataSource.length / limit).ceil())
      }
    };
  }

  final cursorParam = pagination['cursorParam'] as String? ?? 'cursor';
  final cursorRaw = context['query'][cursorParam];
  final offset = cursorRaw is int
      ? cursorRaw
      : int.tryParse(cursorRaw?.toString() ?? '0') ?? 0;
  final safeOffset = offset >= 0 ? offset : 0;
  final end = safeOffset + limit;
  final sliced =
      dataSource.sublist(safeOffset, end.clamp(0, dataSource.length));
  final nextCursor =
      safeOffset + limit < dataSource.length ? '${safeOffset + limit}' : null;

  return {
    'data': _applyTemplate(jsonDecode(jsonEncode(sliced)), context),
    'pagination': {
      'type': "cursor",
      'limit': limit,
      'nextCursor': nextCursor,
      'total': dataSource.length
    }
  };
}

Future<dynamic> _loadFixture(String relativePath, Runtime runtime) async {
  if (runtime.fixtureCache.containsKey(relativePath)) {
    return jsonDecode(jsonEncode(runtime.fixtureCache[relativePath]));
  }
  final absolutePath = path.join(runtime.configDir, relativePath);
  final raw = await File(absolutePath).readAsString();
  final parsed = jsonDecode(raw);
  runtime.fixtureCache[relativePath] = parsed;
  return jsonDecode(jsonEncode(parsed));
}

Future<Map<String, dynamic>> _readBody(HttpRequest request) async {
  final requestMethod = request.method.toUpperCase();
  if (requestMethod == 'GET' || requestMethod == 'HEAD') return {};
  final bytes = await request.fold<List<int>>(
    [],
    (previous, chunk) => [...previous, ...chunk],
  );
  final rawText = utf8.decode(bytes).trim();
  if (rawText.isEmpty) return {};
  try {
    return jsonDecode(rawText);
  } catch (e) {
    throw HttpError(status: 400, message: 'Invalid JSON body');
  }
}

Map<String, dynamic>? _evaluateAuth(
  CompiledRoute route,
  Map<String, dynamic> config,
  Map<String, String> headers,
  Map<String, dynamic> query,
) {
  final auth = route.route['auth'];
  if (auth == null) return null;
  final mode = auth['mode'];
  if (mode == 'none') return null;
  if (mode == 'bearer') {
    final authorization = headers['authorization'] ?? '';
    final token = authorization.toLowerCase().startsWith("bearer ")
        ? authorization.substring(7).trim()
        : null;
    final validToken = auth['token'];
    final configTokens = config['auth']['tokens'];

    final allowed = validToken != null
        ? [validToken]
        : configTokens is List
            ? configTokens
            : [];

    if (token == null || !allowed.contains(token)) {
      return {'error': "unauthorized", 'message': "Missing or invalid token"};
    }

    return null;
  }
  if (mode == 'apiKey') {
    final keyFromHeader = headers["x-api-key"];
    final keyFromQuery = query["apiKey"] as String?;
    final authKey = auth['key'];
    final configAuthKeys = config['auth']['apiKeys'];

    final allowed = authKey != null
        ? [authKey]
        : configAuthKeys is List
            ? configAuthKeys
            : [];

    final candidate = keyFromHeader ?? keyFromQuery;
    if (candidate == null || !allowed.contains(candidate)) {
      return {'error': 'unauthorized', 'message': 'Invalid API key.'};
    }
    return null;
  }

  return null;
}

Map<String, String> _extractParams(CompiledRoute route, String pathname) {
  final match = route.regex.firstMatch(pathname);
  if (match == null) return {};
  final params = <String, String>{};
  for (int i = 0; i < route.paramNames.length; i++) {
    params[route.paramNames[i]] = match.group(i + 1) ?? '';
  }
  return params;
}

CompiledRoute? _matchRoute(
    List<CompiledRoute> routes, String method, String pathname) {
  for (final route in routes) {
    if (route.method == method && route.regex.hasMatch(pathname)) {
      return route;
    }
  }
  return null;
}

bool _isKnownPath(String pathname, Runtime runtime) {
  if (pathname == '/health' || pathname == '/__routes') return true;
  return runtime.routes.any((route) => route.regex.hasMatch(pathname));
}

Future<bool> _handleSystemRoute(String method, String pathname, Runtime runtime,
    HttpResponse response) async {
  if (method == 'GET' && pathname == '/health') {
    await _sendJson(response, 200,
        {'status': 'ok', 'timestamp': DateTime.now().toIso8601String()});
    return true;
  }
  if (method == 'GET' && pathname == '/__routes') {
    await _sendJson(response, 200, {
      'count': runtime.routes.length + 2,
      'routes': [
        {'method': "GET", 'path': "/health", 'auth': "none", 'system': true},
        {'method': "GET", 'path': "/__routes", 'auth': "none", 'system': true},
        ...runtime.routes.map((route) => {
              'method': route.method,
              'path': route.path,
              'auth': route.route['auth']?['mode'] ?? 'none',
              'pagination': route.route['pagination']?['type'],
              'system': false,
            }),
      ]
    });
    return true;
  }
  return false;
}

CorsSettings? _getCorsSettings(Map<String, dynamic> config) {
  final cors = config['global']?['cors'];
  if (cors == null || cors == false) return null;
  if (cors == true) {
    return CorsSettings.defaults();
  }
  if (cors is! Map<String, dynamic>) {
    return null;
  }

  return CorsSettings(
    origin: cors['origin'] ?? '*',
    methods: (cors['methods'] as List?)?.cast<String>() ??
        CorsSettings.defaults().methods,
    headers: (cors['headers'] as List?)?.cast<String>() ??
        CorsSettings.defaults().headers,
    exposedHeaders: (cors['exposedHeaders'] as List?)?.cast<String>() ??
        CorsSettings.defaults().exposedHeaders,
    allowCredentials: cors['allowCredentials'] ?? false,
    maxAge: cors['maxAge'] ?? 600,
  );
}

void _applyCorsHeaders(
    HttpResponse response, Map<String, String> headers, CorsSettings cors) {
  final requestOrigin = headers['origin'];
  final allowedOrigin = _resolveAllowedOrigin(cors, requestOrigin);
  if (allowedOrigin != null) {
    response.headers.set('access-control-allow-origin', allowedOrigin);
    if (allowedOrigin != "*") {
      _appendVaryHeader(response, 'origin');
    }
  }
  if (cors.methods.isNotEmpty) {
    response.headers
        .set('access-control-allow-methods', cors.methods.join(','));
  }
  if (cors.headers.isNotEmpty) {
    response.headers
        .set('access-control-allow-headers', cors.headers.join(','));
  }
  if (cors.exposedHeaders.isNotEmpty) {
    response.headers
        .set('access-control-expose-headers', cors.exposedHeaders.join(','));
  }
  if (cors.maxAge > 0) {
    response.headers.set('access-control-max-age', cors.maxAge.toString());
  }
  if (cors.allowCredentials) {
    response.headers.set('access-control-allow-credentials', 'true');
  }
}

String? _resolveAllowedOrigin(CorsSettings cors, String? requestOrigin) {
  final corsOrigin = cors.origin;
  if (corsOrigin is List) {
    if (requestOrigin == null) return null;
    return corsOrigin.contains(requestOrigin) ? requestOrigin : null;
  }
  if (corsOrigin is String) {
    if (corsOrigin == "*") {
      if (cors.allowCredentials && requestOrigin != null) {
        return requestOrigin;
      }
      return "*";
    }
    return corsOrigin;
  }
  return '*';
}

void _appendVaryHeader(HttpResponse response, String value) {
  final current = response.headers.value("vary");
  if (current == null) {
    response.headers.set("vary", value);
    return;
  }

  final parts = current.split(",").map((entry) => entry.trim().toLowerCase());
  if (!parts.contains(value.toLowerCase())) {
    response.headers.set("vary", "$current, $value");
  }
}

Map<String, String> _normalizeHeaders(HttpHeaders headers) {
  final normalized = <String, String>{};
  headers.forEach((name, values) {
    normalized[name.toLowerCase()] = values.join(',');
  });
  return normalized;
}

Map<String, dynamic> _parseQuery(Map<String, String> queryParameters) {
  final query = <String, dynamic>{};
  queryParameters.forEach((key, value) {
    query[key] = _coerceValue(value);
  });
  return query;
}

dynamic _coerceValue(String value) {
  if (value == 'true') return true;
  if (value == 'false') return false;
  if (num.tryParse(value) != null) return num.parse(value);
  return value;
}

Future<void> _sendJson(
    HttpResponse response, int status, Map<String, dynamic> body) async {
  response.statusCode = status;
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(body));
  await response.close();
}

Future<void> _sendEmpty(HttpResponse response, int status) async {
  response.statusCode = status;
  await response.close();
}

Future<Runtime> createRuntime(String configPath) async {
  final loadedConfig = await loadConfig(configPath);
  final errors = validateConfig(loadedConfig.config);
  if (errors.isNotEmpty) {
    throw Exception(
        'Config validation failed: \n${errors.map((e) => '- $e').join('\n')}');
  }
  final routes = loadedConfig.config['routes'] as List;

  final compiledRoutes = routes
      .map((route) => compilePath(
          route['method'] as String, route['path'] as String, route))
      .toList();

  return Runtime(
      config: loadedConfig.config,
      configPath: loadedConfig.configPath,
      configDir: loadedConfig.configDir,
      routes: compiledRoutes,
      fixtureCache: {});
}

CompiledRoute compilePath(
    String method, String path, Map<String, dynamic> route) {
  if (path == '/') {
    return CompiledRoute(
      method: method,
      path: path,
      regex: RegExp(r'^/$'),
      paramNames: [],
      route: route,
    );
  }
  var parameterNames = <String>[];
  final segments = path.split('/').where((s) => s.isNotEmpty).map((part) {
    if (part.startsWith(':')) {
      parameterNames.add(part.substring(1));
      return r'([^/]+)';
    }
    return _escapeRegex(part);
  });

  return CompiledRoute(
    method: method,
    path: path,
    regex: RegExp('^/${segments.join('/')}\$'),
    paramNames: parameterNames,
    route: route,
  );
}

String _escapeRegex(String unescaped) {
  return unescaped.replaceAllMapped(RegExp(r'[.*+?^${}()|[\]\\]'), (m) {
    return '\\${m[0]}';
  });
}

Map<String, dynamic>? _pickErrors(CompiledRoute route) {
  final errors = route.route['errors'];
  if (errors == null || errors is! List) return null;
  if (errors.isEmpty) return null;
  for (final entry in errors) {
    final errorProbability = entry['probability'];
    if (errorProbability == null || errorProbability is! num) continue;
    if (_random.nextDouble() < errorProbability) {
      return entry;
    }
  }
  return null;
}

int _getLatency(CompiledRoute route, Map<String, dynamic> config) {
  final latency = route.route['latencyMs'] ?? config['latencyMs'];
  if (latency is! List || latency.length != 2) return 0;
  final min = latency[0];
  final max = latency[1];
  if (min is! int || max is! int || min < 0 || max < 0 || min > max) {
    return 0;
  }
  return ((max - min + 1) * _random.nextDouble()).floor() + min;
}

dynamic _applyTemplate(dynamic payload, dynamic context) {
  if (payload is String) {
    return payload.replaceAllMapped(RegExp(r'\{\{\s*([a-zA-Z0-9_.]+)\s*\}\}'),
        (match) {
      final expression = match.group(1);
      if (expression == null) return match.group(0)!;
      final resolved = _resolveTemplatePath(expression, context);
      if (resolved == null) {
        return "";
      }
      if (resolved is String) {
        return resolved;
      }
      return jsonEncode(resolved);
    });
  }
  if (payload is List) {
    return payload.map((item) => _applyTemplate(item, context)).toList();
  }
  if (payload is Map<String, dynamic>) {
    return payload
        .map((key, value) => MapEntry(key, _applyTemplate(value, context)));
  }
  return payload;
}

dynamic _resolveTemplatePath(String expression, dynamic context) {
  final segments = expression.split(".");
  var current = context;

  for (final segment in segments) {
    if (current == null ||
        current is! Map<String, dynamic> ||
        !current.containsKey(segment)) {
      return null;
    }
    current = current[segment];
  }

  return current;
}
