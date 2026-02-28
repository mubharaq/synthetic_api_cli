import 'package:args/command_runner.dart';
import 'package:synthetic_api_cli/src/commands/dev_command.dart';
import 'package:synthetic_api_cli/src/commands/init_command.dart';
import 'package:synthetic_api_cli/src/commands/tunnel_command.dart';
import 'package:synthetic_api_cli/src/commands/validate_command.dart';

Future<void> runCli(List<String> arguments) async {
  final runner = CommandRunner<void>(
    'synthetic-api',
    'Declarative mock API server for frontend development',
  );

  runner.addCommand(ValidateCommand());
  runner.addCommand(DevCommand());
  runner.addCommand(TunnelCommand());
  runner.addCommand(InitCommand());

  await runner.run(arguments);
}
