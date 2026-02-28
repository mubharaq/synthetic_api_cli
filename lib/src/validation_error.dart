class ValidationError {
  final String path;
  final String message;

  const ValidationError({required this.path, required this.message});

  @override
  String toString() => '$path: $message';
}
