import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import '../../../trimmer/domain/trimmer_controller.dart';
import '../../../trimmer/presentation/screens/trimmer_screen.dart';
import '../../../trimmer/presentation/widgets/trim_player.dart';

class VideoUtilitiesScreen extends StatefulWidget {
  const VideoUtilitiesScreen({super.key});

  @override
  State<VideoUtilitiesScreen> createState() => _VideoUtilitiesScreenState();
}

class _VideoUtilitiesScreenState extends State<VideoUtilitiesScreen> {
  /// Kept here (not in the trimmer page) so the open videos and the running exports survive leaving the page.
  final _trimmer = TrimmerController();
  TrimPlayer? _player;                 // made the first time the trimmer opens, then reused: starting a player is slow
  bool _trimming = false;

  @override
  void dispose() {
    _trimmer.dispose();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _convertVideo() async {
    try {
      PlatformFile? file = await FilePicker.pickFile(type: FileType.video);
      if (file == null || file.path == null) return;
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Converting video to H.264...\nThis may take a few minutes depending on your GPU.', textAlign: TextAlign.center),
            ],
          ),
        ),
      );
      
      final response = await http.post(
        Uri.parse('http://127.0.0.1:8000/api/forensic/convert'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"file_path": file.path!}),
      );
      
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // close loading
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Success! Video saved at: ${data["output_path"]}'), backgroundColor: Colors.green));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${response.body}'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_trimming) {
      return Scaffold(
        body: TrimmerScreen(controller: _trimmer, player: _player ??= defaultTrimPlayer(), onBack: () => setState(() => _trimming = false)),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Video Utilities')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.handyman, size: 80, color: Colors.blueAccent),
            const SizedBox(height: 24),
            const Text('Standalone Video Tools', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const SizedBox(
              width: 500,
              child: Text(
                'Trim long CCTV or dashcam footage into as many clips as you need, drag the edges on a timeline, and export them together. Or convert a raw video to a web-safe MP4.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 40),
            ListenableBuilder(
              listenable: _trimmer,
              builder: (context, _) => ElevatedButton.icon(
              onPressed: () => setState(() => _trimming = true),
              icon: const Icon(Icons.content_cut),
              label: Text(_trimmer.activeJobCount > 0 ? 'Video Trimmer (${_trimmer.activeJobCount} exporting)' : 'Video Trimmer'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            )),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _convertVideo,
              icon: const Icon(Icons.movie_filter),
              label: const Text('Format Converter (Raw to Web-Safe MP4)'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                foregroundColor: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
