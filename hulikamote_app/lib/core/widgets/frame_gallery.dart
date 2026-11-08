import 'package:flutter/material.dart';

import '../services/photo_source.dart';
import '../ui/app_theme.dart';
import '../ui/tokens.dart';
import '../ui/widgets.dart';

/// The photos of a ticket as small pictures. Tap one to open them full screen: swipe to move, pinch to zoom.
class FrameGallery extends StatelessWidget {
  const FrameGallery({super.key, required this.names});

  /// File names under the laptop's evidence folder (online: paths in the cloud bucket).
  final List<String> names;

  static String url(String name) => PhotoSource.url(name);

  /// What a close-up is, from its file name: "detail_helmet_1793….jpg" is the picture the helmet check looked at (the
  /// laptop names them like that; online the name is the last part of the path). Null for an ordinary photo.
  static String? caption(String name) {
    final base = name.split('/').last;
    if (!base.startsWith('detail_')) return null;
    return switch (base.substring('detail_'.length).split('_').first) {
      'helmet' => 'Helmet check',
      'seatbelt' => 'Seatbelt check',
      'phone' => 'Phone check',
      'mirror' => 'Side-mirror check',
      _ => 'Close-up',
    };
  }

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle('Photos (${names.length})'),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: Sp.x2, mainAxisSpacing: Sp.x2, childAspectRatio: 1.3),
        itemCount: names.length,
        itemBuilder: (context, i) => Semantics(
          button: true,
          label: '${caption(names[i]) == null ? '' : '${caption(names[i])}. '}Photo ${i + 1} of ${names.length}. Opens it full screen.',
          excludeSemantics: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(Rd.md),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FrameViewer(names: names, initial: i))),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Rd.md),
              child: Stack(fit: StackFit.expand, children: [
                Image.network(
                  url(names[i]),
                  headers: PhotoSource.headers,
                  fit: BoxFit.cover,
                  cacheWidth: 360,
                  errorBuilder: (_, __, ___) => Container(color: context.colors.surfaceContainerHighest, child: Icon(Icons.broken_image_outlined, color: context.muted)),
                  loadingBuilder: (context, child, progress) => progress == null ? child : const Skeleton(height: double.infinity, radius: 0),
                ),
                if (caption(names[i]) != null)
                  Positioned(
                    left: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(6)),
                      child: Text(caption(names[i])!, style: const TextStyle(color: Colors.white, fontSize: 10)),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// One photo at a time, full screen.
class FrameViewer extends StatefulWidget {
  const FrameViewer({super.key, required this.names, this.initial = 0});

  final List<String> names;
  final int initial;

  @override
  State<FrameViewer> createState() => _FrameViewerState();
}

class _FrameViewerState extends State<FrameViewer> {
  late final PageController _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          'Photo ${_index + 1} of ${widget.names.length}${FrameGallery.caption(widget.names[_index]) == null ? '' : ' · ${FrameGallery.caption(widget.names[_index])}'}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: widget.names.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) => InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Center(
            child: Image.network(
              FrameGallery.url(widget.names[i]),
              headers: PhotoSource.headers,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
            ),
          ),
        ),
      ),
    );
  }
}
