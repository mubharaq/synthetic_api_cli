import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;

class LoadedConfig {
  final Map<String, dynamic> config;
  final String configPath;
  final String configDir;

  LoadedConfig({
    required this.config,
    required this.configPath,
    required this.configDir,
  });
}

Future<LoadedConfig> loadConfig(String configPath) async {
  final absolutePath = path.absolute(configPath);
  final file = File(absolutePath);
  final rawText = await file.readAsString();
  final config = jsonDecode(rawText) as Map<String, dynamic>;

  return LoadedConfig(
    config: config,
    configPath: absolutePath,
    configDir: path.dirname(absolutePath),
  );
}
