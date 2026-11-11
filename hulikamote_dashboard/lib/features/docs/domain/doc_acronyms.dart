/// Short, plain meanings for the acronyms and tool names in the docs and the presentation.
/// Used for hover tooltips. A glossary entry from the docs site wins over these.
const Map<String, String> docAcronyms = {
  'CCTV': 'Closed-circuit television. Fixed cameras that send pictures to a few screens or recorders.',
  'RTSP': 'Real Time Streaming Protocol. The common way cameras send live video.',
  'TCP': 'A safe way to send data. Nothing is lost, so pictures stay clean.',
  'UDP': 'A fast way to send data. Pieces can get lost, so pictures can smear.',
  'AI': 'Artificial intelligence. Here: a program that finds vehicles in pictures.',
  'HTTP': 'The way web pages are sent over the internet.',
  'HTTPS': 'HTTP with protection. Others cannot read the data on the way.',
  'MJPEG': 'Video sent as a series of JPEG pictures. Simple and old. Many phone apps use it.',
  'JPEG': 'A common picture file type. Files are small.',
  'RTMP': 'Real-Time Messaging Protocol. A way for apps to send live video.',
  'HLS': 'HTTP Live Streaming. Video sent in short pieces over the web.',
  'ONVIF': 'A standard that lets cameras from different makers work with the same software.',
  'NVR': 'Network video recorder. A box that saves camera video.',
  'DVR': 'Digital video recorder. A box that saves CCTV video.',
  'IP': 'Internet Protocol. The rules for addresses and data on a network.',
  'FPS': 'Frames per second. How many pictures are shown each second.',
  'CPU': 'The main chip of a computer. It does the work.',
  'API': 'A way for one program to ask another program for data.',
  'URL': 'A web address.',
  'RFC': 'A public document that describes an internet standard.',
  'IETF': 'The group that writes internet standards.',
  'H.264': 'A way to shrink video so it can travel over a network. The most common one.',
  'H.265': 'A newer way to shrink video. Files are smaller than H.264.',
  'FFmpeg': 'A free tool that reads, changes and sends video.',
  'MediaMTX': 'A small program that takes live video and passes it on to viewers.',
  'IP address': 'A number that names a device on a network, for example 192.168.1.20.',
};

/// Case-insensitive lookup.
String? acronymMeaning(String key) {
  final direct = docAcronyms[key];
  if (direct != null) return direct;
  final lower = key.toLowerCase();
  for (final e in docAcronyms.entries) {
    if (e.key.toLowerCase() == lower) return e.value;
  }
  return null;
}

/// Whole-word match for the acronyms that are written in capitals (or as a tool name).
final RegExp acronymPattern = RegExp(
  r'(?<![A-Za-z0-9_./:-])(H\.264|H\.265|CCTV|RTSP|TCP|UDP|HTTPS|HTTP|MJPEG|JPEG|RTMP|HLS|ONVIF|NVR|DVR|FPS|CPU|API|URL|RFC|IETF|AI|IP|FFmpeg|MediaMTX)(?![A-Za-z0-9_])',
);
