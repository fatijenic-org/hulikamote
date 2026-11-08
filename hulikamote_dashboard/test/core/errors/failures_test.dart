import 'package:flutter_test/flutter_test.dart';
import 'package:hulikamote_dashboard/core/errors/failures.dart';

void main() {
  group('ServerFailure', () {
    test('should be a subclass of Failure and equate properly', () {
      // Arrange
      const message = 'Server down';
      const failure1 = ServerFailure(message);
      const failure2 = ServerFailure(message);
      const failure3 = ServerFailure('Different error');

      // Act & Assert
      expect(failure1, isA<Failure>());
      expect(failure1.message, equals(message));
      expect(failure1, equals(failure2)); // Testing Equatable
      expect(failure1, isNot(equals(failure3)));
    });
  });
}
