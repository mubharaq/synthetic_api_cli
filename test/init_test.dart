import 'dart:io';

import 'package:synthetic_api_cli/src/init.dart';
import 'package:test/test.dart';
import 'package:path/path.dart' as path;

void main() {
  group('validateInit', () {
    test("initializeProject scaffolds deploy-ready files", () async {
      final cwd = await Directory.systemTemp.createTemp("synthetic-api-init--");

      try {
        final result = await initializeProject(
            cwd: cwd.path, configFile: "synthetic-api.config.json");

        final expectedFiles = [
          path.join(cwd.path, "synthetic-api.config.json"),
          path.join(cwd.path, "fixtures/users.json"),
          path.join(cwd.path, "Dockerfile"),
          path.join(cwd.path, ".dockerignore"),
          path.join(cwd.path, "render.yaml"),
          path.join(cwd.path, "railway.json"),
          path.join(cwd.path, "Procfile")
        ];
        print(result.filesCreated);
        print(expectedFiles);
        for (var entry in expectedFiles) {
          expect(result.filesCreated.contains(entry), true);
        }
        expect(result.filesSkipped.isEmpty, true);
      } finally {
        await cwd.delete(recursive: true);
      }
    });

    test("initializeProject skips existing files instead of failing", () async {
      final cwd =
          await Directory.systemTemp.createTemp("synthetic-api-init-skip-");

      try {
        final first = await initializeProject(
            cwd: cwd.path, configFile: "synthetic-api.json");
        final second = await initializeProject(
            cwd: cwd.path, configFile: "synthetic-api.json");

        expect(first.filesCreated.isEmpty, false);
        expect(second.filesCreated.length, 0);
        expect(second.filesSkipped.length >= 7, true);
      } finally {
        await cwd.delete(recursive: true);
      }
    });
  });
}
