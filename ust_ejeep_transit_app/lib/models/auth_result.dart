import 'user_model.dart';

/// Sealed class representing the result of an authentication attempt.
///
/// Use pattern matching to handle both outcomes:
/// ```dart
/// switch (result) {
///   case AuthSuccess(:final user, :final token):
///     // handle success
///   case AuthFailure(:final errorCode, :final message):
///     // handle failure
/// }
/// ```
sealed class AuthResult {
  const AuthResult();
}

/// Successful authentication — carries the authenticated [User] and a [token].
final class AuthSuccess extends AuthResult {
  final User user;
  final String token;

  const AuthSuccess({
    required this.user,
    required this.token,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AuthSuccess &&
        other.user == user &&
        other.token == token;
  }

  @override
  int get hashCode => Object.hash(user, token);

  @override
  String toString() =>
      'AuthSuccess(user: $user, token: ${token.isNotEmpty ? '[redacted]' : '[empty]'})';
}

/// Failed authentication — carries an [errorCode] and a human-readable [message].
final class AuthFailure extends AuthResult {
  final String errorCode;
  final String message;

  const AuthFailure({
    required this.errorCode,
    required this.message,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AuthFailure &&
        other.errorCode == errorCode &&
        other.message == message;
  }

  @override
  int get hashCode => Object.hash(errorCode, message);

  @override
  String toString() =>
      'AuthFailure(errorCode: $errorCode, message: $message)';
}
