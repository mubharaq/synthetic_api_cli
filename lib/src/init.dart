import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

final _sampleConfig = {
  'version': 1,
  'global': {
    'latencyMs': [50, 250],
    'cors': {
      'enabled': true,
      'origin': '*',
      'methods': ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'],
      'headers': ['content-type', 'authorization', 'x-api-key']
    }
  },
  'auth': {
    'tokens': ['demo-token'],
    'apiKeys': ['demo-key']
  },
  'routes': [
    {
      'method': 'GET',
      'path': '/',
      'response': {
        'status': 200,
        'body': {
          'name': 'synthetic-api',
          'message': 'Welcome. Your mock API is running.',
          'docs': [
            'GET /health',
            'GET /__routes',
            'GET /users?page=1&limit=5',
            'GET /users/:id (Authorization: Bearer demo-token)',
            'POST /auth/login',
            'GET /analytics?range=7d (x-api-key: demo-key)'
          ]
        }
      }
    },
    {
      'method': 'GET',
      'path': '/users',
      'querySchema': {'page': 'number?', 'limit': 'number?'},
      'pagination': {
        'type': 'offset',
        'pageParam': 'page',
        'limitParam': 'limit',
        'defaultLimit': 5
      },
      'response': {'status': 200, 'bodyFrom': 'fixtures/users.json'},
      'errors': [
        {
          'status': 500,
          'code': 'temporary_failure',
          'message': 'Temporary failure. Retry.',
          'probability': 0.05
        }
      ]
    },
    {
      'method': 'GET',
      'path': '/users/:id',
      'auth': {'mode': 'bearer'},
      'response': {
        'status': 200,
        'body': {
          'userId': '{{params.id}}',
          'message': 'Secure endpoint response'
        }
      }
    },
    {
      'method': 'POST',
      'path': '/auth/login',
      'bodySchema': {'email': 'string', 'password': 'string'},
      'response': {
        'status': 200,
        'body': {'token': 'demo-token', 'expiresIn': 3600}
      }
    },
    {
      'method': 'GET',
      'path': '/analytics',
      'auth': {'mode': 'apiKey'},
      'querySchema': {'range': 'string?'},
      'response': {
        'status': 200,
        'body': {
          'visitors': 1821,
          'conversions': 77,
          'conversionRate': 0.042,
          'requestedRange': '{{query.range}}'
        }
      }
    }
  ]
};

final _sampleUsers = List.generate(
  30,
  (i) => {
    'id': i + 1,
    'name': 'User ${i + 1}',
    'role': i % 4 == 0 ? 'admin' : 'member',
    'email': 'user${i + 1}@example.com'
  },
);

String _renderYaml(String serviceName) => '''
services:
  - type: web
    name: $serviceName
    env: dart
    plan: free
    buildCommand: dart pub get
    startCommand: dart run bin/synthetic_api.dart dev --config synthetic-api.config.json --watch false
''';

const _dockerfile = '''
FROM dart:stable AS build
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get
COPY . .
RUN dart compile exe bin/synthetic_api.dart -o bin/synthetic_api

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/bin/synthetic_api /app/bin/
COPY --from=build /app/synthetic-api.config.json /app/
COPY --from=build /app/fixtures /app/fixtures/
ENTRYPOINT ["/app/bin/synthetic_api"]
CMD ["dev", "--config", "/app/synthetic-api.config.json", "--watch", "false"]
''';

const _dockerignore = '.DS_Store\n.git\n.gitignore\n';

const _railwayJson = '''
{
  "\$schema": "https://railway.app/railway.schema.json",
  "build": {
    "builder": "NIXPACKS"
  },
  "deploy": {
    "startCommand": "dart run bin/synthetic_api.dart dev --config synthetic-api.config.json --watch false",
    "restartPolicyType": "ON_FAILURE",
    "restartPolicyMaxRetries": 10
  }
}
''';

const _procfile =
    'web: dart run bin/synthetic_api.dart dev --config synthetic-api.config.json --watch false\n';

class InitResult {
  List<String> filesCreated;
  List<String> filesSkipped;
  List<String> filesUpdated;

  InitResult({
    required this.filesCreated,
    required this.filesSkipped,
    required this.filesUpdated,
  });
}

Future<InitResult> initializeProject({
  required String cwd,
  required String configFile,
  bool force = false,
}) async {
  final result = InitResult(
    filesCreated: [],
    filesSkipped: [],
    filesUpdated: [],
  );

  final configPath = _resolvePath(cwd, configFile);
  await _writeFile(configPath,
      JsonEncoder.withIndent('  ').convert(_sampleConfig), force, result);

  final usersPath = _resolvePath(cwd, 'fixtures/users.json');
  await _writeFile(usersPath,
      JsonEncoder.withIndent('  ').convert(_sampleUsers), force, result);

  final deployFiles = _buildDeployFiles(cwd);
  for (final file in deployFiles) {
    await _writeFile(
        file['path'] as String, file['content'] as String, force, result);
  }

  return result;
}

List<Map<String, String>> _buildDeployFiles(String cwd) {
  final serviceName = _sanitizeServiceName(path.basename(cwd));
  return [
    {'path': _resolvePath(cwd, 'railway.json'), 'content': _railwayJson},
    {
      'path': _resolvePath(cwd, 'render.yaml'),
      'content': _renderYaml(serviceName)
    },
    {'path': _resolvePath(cwd, 'Dockerfile'), 'content': _dockerfile},
    {'path': _resolvePath(cwd, '.dockerignore'), 'content': _dockerignore},
    {'path': _resolvePath(cwd, 'Procfile'), 'content': _procfile},
  ];
}

String _sanitizeServiceName(String name) {
  final sanitized = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9-]'), '-')
      .replaceAll(RegExp(r'^-+'), '')
      .replaceAll(RegExp(r'-+$'), '');
  return sanitized.isEmpty ? 'synthetic-api-service' : sanitized;
}

String _resolvePath(String cwd, String relativePath) {
  return path.join(cwd, relativePath);
}

Future<void> _writeFile(
  String filePath,
  String content,
  bool force,
  InitResult result,
) async {
  final file = File(filePath);
  if (await file.exists()) {
    if (!force) {
      result.filesSkipped.add(filePath);
      return;
    }
    result.filesUpdated.add(filePath);
  } else {
    result.filesCreated.add(filePath);
  }
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}
