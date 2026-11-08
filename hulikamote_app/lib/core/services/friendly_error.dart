import 'portal_api.dart';

/// What to tell the motorist when something fails: the system's own plain-words message, or a calm generic one.
String friendlyMessage(Object error) => error is PortalException ? error.message : 'Something went wrong. Please try again.';

/// The system could not be reached at all (no internet, wrong Wi-Fi, laptop off), as opposed to refusing a request.
bool isConnectionProblem(Object error) => error is PortalException && error.message.startsWith('Cannot reach');
