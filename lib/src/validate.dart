import 'validation_error.dart';

const _httpMethods = {
  'GET',
  'POST',
  'PUT',
  'PATCH',
  'DELETE',
  'HEAD',
  'OPTIONS'
};

List<ValidationError> validateConfig(Map<String, dynamic> config) {
  final errors = <ValidationError>[];

  final global = config['global'];
  if (global != null && global is! Map<String, dynamic>) {
    errors.add(ValidationError(
      path: 'global',
      message: 'must be an object',
    ));
  } else if (global is Map<String, dynamic> && global['cors'] != null) {
    errors.addAll(_validateCorsConfig(global['cors'], 'global.cors'));
  }

  if (config['routes'] == null ||
      config['routes'] is! List ||
      (config['routes'] as List).isEmpty) {
    errors.add(ValidationError(
      path: 'routes',
      message: 'must be a non-empty array',
    ));
    return errors;
  }

  final routes = config['routes'] as List;
  for (var i = 0; i < routes.length; i++) {
    errors.addAll(_validateRoute(routes[i], i));
  }

  return errors;
}

List<ValidationError> _validateCorsConfig(dynamic cors, String path) {
  final errors = <ValidationError>[];
  if (cors is bool) {
    return errors;
  }
  if (cors is! Map<String, dynamic>) {
    errors.add(
        ValidationError(path: path, message: 'must be an object or a boolean'));
    return errors;
  }
  final enableCors = cors['enabled'];
  if (enableCors != null && enableCors is! bool) {
    errors.add(
        ValidationError(path: '$path.enabled', message: 'must be a boolean'));
  }
  final origin = cors['origin'];
  if (origin != null && (origin is! String && origin is! List)) {
    errors.add(ValidationError(
        path: '$path.origin', message: 'must be a string or array'));
  }
  final methods = cors['methods'];
  if (methods != null &&
      (methods is! List || methods.any((e) => e is! String))) {
    errors.add(ValidationError(
        path: '$path.methods', message: 'must be an array of strings'));
  }
  final headers = cors['headers'];
  if (headers != null &&
      (headers is! List || headers.any((e) => e is! String))) {
    errors.add(ValidationError(
        path: '$path.headers', message: 'must be an array of strings'));
  }
  final allowCredentials = cors['allowCredentials'];
  if (allowCredentials != null && allowCredentials is! bool) {
    errors.add(ValidationError(
        path: '$path.allowCredentials', message: 'must be a boolean'));
  }
  final exposedHeaders = cors['exposedHeaders'];
  if (exposedHeaders != null &&
      (exposedHeaders is! List || exposedHeaders.any((e) => e is! String))) {
    errors.add(ValidationError(
        path: '$path.exposedHeaders', message: 'must be an array of strings'));
  }
  final maxAge = cors['maxAge'];
  if (maxAge != null && (maxAge is! int || maxAge < 0)) {
    errors.add(ValidationError(
        path: '$path.maxAge', message: 'must be a non-negative integer'));
  }
  return errors;
}

List<ValidationError> _validateRoute(dynamic route, int index) {
  final errors = <ValidationError>[];
  final prefix = 'routes[$index]';

  if (route is! Map<String, dynamic>) {
    errors.add(ValidationError(path: prefix, message: 'must be an object'));
    return errors;
  }

  final method = route['method'];
  final path = route['path'];
  final response = route['response'];
  final auth = route['auth'];
  final latencyMs = route['latencyMs'];
  final pagination = route['pagination'];
  final requestErrors = route['errors'];
  if (method is! String || method.isEmpty) {
    errors.add(ValidationError(
      path: '$prefix.method',
      message: 'must be a non-empty string',
    ));
  } else if (!_httpMethods.contains(method.toUpperCase())) {
    errors.add(ValidationError(
      path: '$prefix.method',
      message: 'must be one of ${_httpMethods.join(', ')}',
    ));
  }
  if (path is! String || path.isEmpty || !path.startsWith('/')) {
    errors.add(ValidationError(
        path: '$prefix.path', message: 'must start with / and be non-empty'));
  }

  if (response is! Map<String, dynamic>) {
    errors.add(ValidationError(
        path: '$prefix.response', message: 'must be an object'));
  } else {
    final hasBody = response.containsKey('body');
    final hasBodyFrom = response['bodyFrom'] is String;
    final status = response['status'];
    if (!hasBody && !hasBodyFrom) {
      errors.add(ValidationError(
          path: '$prefix.response',
          message: 'must have either body or bodyFrom'));
    }
    if (status != null && (status is! int || status <= 0)) {
      errors.add(ValidationError(
          path: '$prefix.response.status',
          message: 'must be a positive integer'));
    }
  }

  if (auth != null) {
    if (auth is! Map<String, dynamic> || !auth.containsKey('mode')) {
      errors.add(ValidationError(
          path: '$prefix.auth', message: 'must be an object with a mode'));
    } else {
      final mode = auth['mode'];
      if (mode is! String || mode.isEmpty) {
        errors.add(ValidationError(
            path: '$prefix.auth.mode', message: 'must be a non-empty string'));
      } else if (!['none', 'bearer', 'apiKey'].contains(mode)) {
        errors.add(ValidationError(
            path: '$prefix.auth.mode',
            message: 'must be one of none, bearer, apiKey'));
      }
    }
  }

  if (latencyMs != null) {
    if (latencyMs is! List || latencyMs.length != 2) {
      errors.add(ValidationError(
        path: '$prefix.latencyMs',
        message: 'must be an array of two integers',
      ));
    } else {
      final min = latencyMs[0];
      final max = latencyMs[1];
      if (min is! int || max is! int || min < 0 || max < 0) {
        errors.add(ValidationError(
          path: '$prefix.latencyMs',
          message: 'must be an array of two positive integers',
        ));
      } else if (min > max) {
        errors.add(ValidationError(
          path: '$prefix.latencyMs',
          message: 'min must be less than or equal to max',
        ));
      }
    }
  }

  if (pagination != null) {
    if (pagination is! Map<String, dynamic> ||
        !pagination.containsKey('type')) {
      errors.add(ValidationError(
        path: '$prefix.pagination',
        message: 'must be an object with a type',
      ));
    } else {
      final type = pagination['type'];
      if (type is! String || type.isEmpty) {
        errors.add(ValidationError(
          path: '$prefix.pagination.type',
          message: 'must be a non-empty string',
        ));
      } else if (!['offset', 'cursor'].contains(type)) {
        errors.add(ValidationError(
          path: '$prefix.pagination.type',
          message: 'must be one of offset, cursor',
        ));
      }
    }
  }

  if (requestErrors != null) {
    if (requestErrors is! List) {
      errors.add(ValidationError(
        path: '$prefix.errors',
        message: 'must be an array',
      ));
    } else {
      for (var i = 0; i < requestErrors.length; i++) {
        final error = requestErrors[i];
        if (error is! Map<String, dynamic>) {
          errors.add(ValidationError(
            path: '$prefix.errors[$i]',
            message: 'must be an object',
          ));
          continue;
        }
        final errorStatus = error['status'];
        final errorProbability = error['probability'];
        if (errorStatus == null || errorStatus is! int || errorStatus <= 0) {
          errors.add(ValidationError(
            path: '$prefix.errors[$i].status',
            message: 'must be a positive integer',
          ));
        }
        if (errorProbability == null ||
            errorProbability is! num ||
            errorProbability < 0 ||
            errorProbability > 1) {
          errors.add(ValidationError(
            path: '$prefix.errors[$i].probability',
            message: 'must be a number between 0 and 1',
          ));
        }
      }
    }
  }

  return errors;
}

List<ValidationError> validateData(dynamic data, dynamic schema,
    {String path = 'request'}) {
  final errors = <ValidationError>[];
  errors.addAll(_validateRecursive(data, schema, path));
  return errors;
}

List<ValidationError> _validateRecursive(
    dynamic data, dynamic schema, String path) {
  final errors = <ValidationError>[];
  if (schema is String) {
    return _validateStringSchema(data, schema, path);
  }
  if (schema is List && schema.length == 1) {
    for (var i = 0; i < (data as List).length; i++) {
      errors.addAll(_validateRecursive(data[i], schema[0], '$path[$i]'));
    }
    return errors;
  }
  if (schema is Map<String, dynamic>) {
    if (data is! Map<String, dynamic>) {
      errors.add(ValidationError(
          path: path, message: 'must be an object with ${schema.length} keys'));
      return errors;
    }
    for (final entry in schema.entries) {
      final key = entry.key;
      final childSchema = entry.value;
      final expected = childSchema is String ? childSchema : null;
      final optional = expected != null ? expected.endsWith("?") : false;
      final currentPath = '$path.$key';

      if (!data.containsKey(key) || data[key] == null) {
        if (!optional) {
          errors
              .add(ValidationError(path: currentPath, message: 'is required.'));
        }
        continue;
      }

      final childErrors =
          _validateRecursive(data[key], childSchema, currentPath);
      if (childErrors.isNotEmpty) {
        errors.addAll(childErrors);
      }
    }
    return errors;
  }
  errors.add(ValidationError(path: path, message: 'Unsupported schema type'));
  return errors;
}

List<ValidationError> _validateStringSchema(
    dynamic data, String schema, String path) {
  final errors = <ValidationError>[];
  final optional = schema.endsWith('?');
  final normalized = optional ? schema.substring(0, schema.length - 1) : schema;

  if (data == null) {
    if (!optional) {
      errors.add(ValidationError(path: path, message: 'is required'));
    }
    return errors;
  }

  if (normalized.endsWith('[]')) {
    final itemType = normalized.substring(0, normalized.length - 2);
    if (data is! List) {
      errors.add(ValidationError(path: path, message: 'must be an array'));
      return errors;
    }
    for (var i = 0; i < data.length; i++) {
      errors.addAll(_validateStringSchema(data[i], itemType, '$path[$i]'));
    }
    return errors;
  }

  switch (normalized) {
    case 'string':
      if (data is! String) {
        errors.add(ValidationError(path: path, message: 'must be a string'));
      }
    case 'number':
      if (data is! num) {
        errors.add(ValidationError(path: path, message: 'must be a number'));
      }
    case 'boolean':
      if (data is! bool) {
        errors.add(ValidationError(path: path, message: 'must be a boolean'));
      }
    case 'array':
      if (data is! List) {
        errors.add(ValidationError(path: path, message: 'must be an array'));
      }
    case 'object':
      if (data is! Map) {
        errors.add(ValidationError(path: path, message: 'must be an object'));
      }
    case 'any':
      break;
    default:
      errors.add(ValidationError(
          path: path, message: "unsupported type '$normalized'"));
  }

  return errors;
}
