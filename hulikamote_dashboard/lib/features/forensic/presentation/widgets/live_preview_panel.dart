import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../../core/utils/visible_poller.dart';
import '../../data/forensic_media.dart';
import 'fx.dart';

/// Builds the preview shown on the Video tab while an analysis still runs. The default uses media_kit; tests pass a stand-in.
typedef PreviewPanelBuilder = Widget Function(BuildContext context, String taskId, ForensicMedia media);

Widget defaultPreviewPanel(BuildContext context, String taskId, ForensicMedia media) =>
    LivePreviewPanel(taskId: taskId, media: media);

/// The backend writes the raw video in 30-second pieces next to the report (engine/segment_writer.py).
String previewPieceUrl(ForensicMedia media, String taskId, int piece) =>
    '${media.baseUrl}/snapshots/evidence/forensic/$taskId/output/evidence_raw_part${piece.toString().padLeft(4, '0')}.mp4';

/// How many of the [existing] pieces can be played: the newest one is still being written and cannot be opened.
int playablePieces(int existing) => existing > 0 ? existing - 1 : 0;

/// The number of the last piece that exists, asking from piece [from] upwards ([from] - 1 when that piece is missing).
Future<int> countPieces(Future<bool> Function(int piece) exists, {int from = 1}) async {
  var last = from - 1;
  while (await exists(last + 1)) {
    last++;
  }
  return last;
}

Future<bool> _headExists(String url) async {
  try {
    final res = await http.head(Uri.parse(url)).timeout(const Duration(seconds: 5));
    return res.statusCode == 200;
  } catch (_) {
    return false;
  }
}

/// While the analysis runs: plays the finished 30-second pieces of its video, one after the other. The pieces show the
/// drawn zones but not the boxes; the full replay (with boxes and the ticket timeline) appears when the analysis ends.
class LivePreviewPanel extends StatefulWidget {
  const LivePreviewPanel({super.key, required this.taskId, required this.media});

  final String taskId;
  final ForensicMedia media;

  @override
  State<LivePreviewPanel> createState() => _LivePreviewPanelState();
}

class _LivePreviewPanelState extends State<LivePreviewPanel> {
  late final Player _player = Player();
  late final VideoController _video = VideoController(_player);
  late final VisiblePoller _poller = VisiblePoller(interval: const Duration(seconds: 8), onTick: _refresh);
  final List<StreamSubscription<dynamic>> _subs = [];
  int _existing = 0; // pieces the backend has (the newest may still be written)
  int _added = 0; // pieces in the player's playlist
  int _index = 0;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _subs.add(_player.stream.playlist.listen((p) {
      if (mounted) setState(() => _index = p.index);
    }));
    _subs.add(_player.stream.playing.listen((v) {
      if (mounted) setState(() => _playing = v);
    }));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _poller.attach(context); // asks now, then every few seconds while this page is on screen
  }

  @override
  void dispose() {
    _poller.dispose();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  String _url(int piece) => previewPieceUrl(widget.media, widget.taskId, piece);

  Future<void> _refresh() async {
    _existing = await countPieces((p) => _headExists(_url(p)), from: _existing + 1);
    final playable = playablePieces(_existing);
    while (_added < playable && mounted) {
      final next = Media(_url(_added + 1));
      if (_added == 0) {
        await _player.open(Playlist([next]), play: false);
      } else {
        await _player.add(next);
      }
      _added++;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Fx.radius),
            child: Container(
              color: Colors.black,
              child: _added == 0
                  ? Center(
                      child: Text(
                        'The first 30 seconds are still being written.\nThis page looks again every few seconds.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    )
                  : Video(controller: _video, controls: NoVideoControls),
            ),
          ),
        ),
        Row(
          children: [
            IconButton(tooltip: 'Previous piece', onPressed: _added > 1 ? _player.previous : null, icon: const Icon(Icons.skip_previous)),
            IconButton(
              tooltip: _playing ? 'Pause' : 'Play',
              onPressed: _added == 0 ? null : _player.playOrPause,
              icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
            ),
            IconButton(tooltip: 'Next piece', onPressed: _added > 1 ? _player.next : null, icon: const Icon(Icons.skip_next)),
            Text(_added == 0 ? 'No piece ready yet' : 'Piece ${_index + 1} of $_added (30 seconds each)', style: Fx.caption(context)),
          ],
        ),
        Text(
          'Preview while the analysis runs: the finished pieces of the video, with the zones drawn and no boxes. '
          'The full replay with boxes and the ticket timeline appears when the analysis ends.',
          style: Fx.caption(context),
        ),
      ],
    );
  }
}
