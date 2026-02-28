import 'dart:io';

Future<void> startTunnel({int port = 4010, String provider = "auto"}) async {
  final normalized = _resolveProvider(provider);

  if (normalized == null) {
    throw Exception(
        "No supported tunnel client found. Install cloudflared or ngrok.");
  }

  final command = _buildCommand(normalized, port);

  print("Starting $normalized tunnel for http://localhost:$port");
  final process = await Process.start(
    command['command'] as String,
    command['args'] as List<String>,
    mode: ProcessStartMode.inheritStdio,
  );
  await process.exitCode;
}

bool _hasBinary(String provider) {
  final result = Process.runSync('which', [provider]);
  return result.exitCode == 0;
}

String? _resolveProvider(String provider) {
  if (provider == "cloudflared") {
    return _hasBinary("cloudflared") ? "cloudflared" : null;
  }

  if (provider == "ngrok") {
    return _hasBinary("ngrok") ? "ngrok" : null;
  }

  if (_hasBinary("cloudflared")) {
    return "cloudflared";
  }

  if (_hasBinary("ngrok")) {
    return "ngrok";
  }

  return null;
}

Map<String, dynamic> _buildCommand(String provider, int port) {
  if (provider == "cloudflared") {
    return {
      "command": "cloudflared",
      "args": ["tunnel", "--url", "http://localhost:$port"]
    };
  }

  return {
    "command": "ngrok",
    "args": ["http", port]
  };
}
