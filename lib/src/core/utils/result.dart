/// Dart 3 Sealed class pattern for returning Success or Failure (like Either)
sealed class Result<S, F> {
  const Result();

  /// Functional fold to handle both cases conveniently
  T fold<T>(T Function(F failure) onFailure, T Function(S success) onSuccess) {
    if (this is Success<S, F>) {
      return onSuccess((this as Success<S, F>).value);
    } else if (this is FailureResult<S, F>) {
      return onFailure((this as FailureResult<S, F>).failure);
    }
    throw StateError('Result is neither Success nor FailureResult');
  }
}

class Success<S, F> extends Result<S, F> {
  final S value;
  const Success(this.value);
}

class FailureResult<S, F> extends Result<S, F> {
  final F failure;
  const FailureResult(this.failure);
}
