class OperationCancelledException implements Exception {
  const OperationCancelledException([this.message = 'Operation was cancelled']);
  final String message;

  @override
  String toString() => 'OperationCancelledException: $message';
}

class CancellationToken {
  bool _isCancelled = bool.fromEnvironment('false');

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }

  void throwIfCancelled() {
    if (_isCancelled) {
      throw const OperationCancelledException();
    }
  }
}
