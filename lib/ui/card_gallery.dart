import 'package:flutter/material.dart';

import '../data/card_db.dart' show imageAtSize;
import 'net_image.dart';

/// Full-screen card viewer: swipe left/right through [count] cards, pinch to
/// zoom. [image] draws card i; [title]/[subtitle] caption it; [actions]
/// (optional) adds buttons under the card, e.g. "Edit".
class CardGalleryScreen extends StatefulWidget {
  final int count;
  final int initialIndex;
  final Widget Function(BuildContext context, int i) image;
  final String Function(int i) title;
  final String Function(int i)? subtitle;
  final List<Widget> Function(BuildContext context, int i)? actions;

  const CardGalleryScreen({
    super.key,
    required this.count,
    required this.image,
    required this.title,
    this.initialIndex = 0,
    this.subtitle,
    this.actions,
  });

  /// Convenience for plain Scryfall image links.
  static Widget networkCard(String? url, String name) {
    if (url == null) {
      return Center(child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 20)));
    }
    return NetImage(
      imageAtSize(url, 'large'),
      fit: BoxFit.contain,
      // Show the smaller image (usually already cached) while the large one loads.
      loading: (_) => Stack(alignment: Alignment.center, children: [
        NetImage(url, fit: BoxFit.contain),
        const CircularProgressIndicator(),
      ]),
      fallback: (_) => NetImage(url, fit: BoxFit.contain),
    );
  }

  @override
  State<CardGalleryScreen> createState() => _CardGalleryScreenState();
}

class _CardGalleryScreenState extends State<CardGalleryScreen> {
  late final _pages = PageController(initialPage: widget.initialIndex, viewportFraction: 0.92);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sub = widget.subtitle?.call(_index);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1} / ${widget.count}'),
      ),
      body: Column(children: [
        Expanded(
          child: PageView.builder(
            controller: _pages,
            itemCount: widget.count,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 0.716,
                    child: ClipRRect(borderRadius: BorderRadius.circular(16), child: widget.image(context, i)),
                  ),
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(widget.title(_index),
                  textAlign: TextAlign.center, style: theme.textTheme.titleMedium?.copyWith(color: Colors.white)),
              if (sub != null && sub.isNotEmpty)
                Text(sub, textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70)),
              if (widget.actions != null) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 8, alignment: WrapAlignment.center, children: widget.actions!(context, _index)),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}
