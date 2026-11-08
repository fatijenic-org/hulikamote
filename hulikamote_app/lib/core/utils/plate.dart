/// "abc 1234" and "ABC-1234" are the same plate: capitals and digits only.
String normalizePlate(String text) => text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

const maxPlateChars = 12;
const minPasswordChars = 6;

/// What is wrong with each field of the sign-up form, in words for the motorist. A field that is fine is not in the map.
/// Keys: name, plate, email, password, repeat.
Map<String, String> signUpErrors({
  required String name,
  required String plate,
  required String password,
  required String repeat,
  String email = '',
}) {
  final errors = <String, String>{};
  if (name.trim().isEmpty) errors['name'] = 'Enter your name.';
  final key = normalizePlate(plate);
  if (key.isEmpty) {
    errors['plate'] = 'Enter your plate number.';
  } else if (key.length > maxPlateChars) {
    errors['plate'] = 'A plate has at most $maxPlateChars letters and digits.';
  }
  if (email.trim().isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim())) {
    errors['email'] = 'That does not look like an e-mail address.';
  }
  if (password.length < minPasswordChars) errors['password'] = 'The password needs at least $minPasswordChars characters.';
  if (repeat != password) errors['repeat'] = 'The two passwords are not the same.';
  return errors;
}

/// The first thing wrong with a sign-up form (in the order the fields appear); null when it is fine.
String? validateSignUp({required String name, required String plate, required String password, required String repeat, String email = ''}) {
  final errors = signUpErrors(name: name, plate: plate, password: password, repeat: repeat, email: email);
  for (final field in const ['name', 'plate', 'email', 'password', 'repeat']) {
    if (errors.containsKey(field)) return errors[field];
  }
  return null;
}

/// A hint under the password box that reacts as the person types.
String passwordHint(String password) {
  if (password.isEmpty) return 'At least $minPasswordChars characters.';
  if (password.length < minPasswordChars) return '${minPasswordChars - password.length} more to go.';
  return password.length >= 10 ? 'Strong.' : 'Good. A longer one is stronger.';
}
