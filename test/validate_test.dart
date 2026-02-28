import 'package:test/test.dart';
import 'package:synthetic_api_cli/src/validate.dart';

void main() {
  group('validateConfig', () {
    test('passes for a minimal valid config', () {
      final config = {
        'version': 1,
        'routes': [
          {
            'method': 'GET',
            'path': '/',
            'response': {'status': 200, 'body': {}}
          }
        ]
      };

      final errors = validateConfig(config);
      expect(errors, isEmpty);
    });

    test("validateConfig reports invalid method and path", () {
      final config = {
        'routes': [
          {
            'method': 'FETCH',
            'path': 'health',
            'response': {'body': {}}
          }
        ]
      };

      final errors = validateConfig(config);
      expect(errors.length >= 2, true);
    });

    test("validateConfig reports invalid cors shape", () {
      final config = {
        'global': {
          'cors': {'origin': 42, 'allowCredentials': 'yes'}
        },
        'routes': [
          {
            'method': 'GET',
            'path': '/health',
            'response': {
              'status': 200,
              'body': {'ok': true}
            }
          }
        ]
      };

      final errors = validateConfig(config);
      print(errors.map((e) => '${e.path}: ${e.message}').toList());
      expect(errors.any((e) => e.path.contains('global.cors.origin')), true);
      expect(errors.any((e) => e.path.contains('global.cors.allowCredentials')),
          true);
    });
  });
}
