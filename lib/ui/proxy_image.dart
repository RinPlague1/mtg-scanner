import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/decks.dart';
import '../services.dart';
import 'card_gallery.dart';

/// Lets the user choose a photo of their proxy, shrunk to card-image size
/// (672 px wide PNG, a few hundred KB). Null if cancelled.
Future<Uint8List?> pickProxyImage() async {
  const group = XTypeGroup(
    label: 'Images',
    extensions: ['jpg', 'jpeg', 'png', 'webp', 'heic'],
    mimeTypes: ['image/*'],
  );
  final file = await openFile(acceptedTypeGroups: [group]);
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: 672);
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
  frame.image.dispose();
  if (data == null) throw Exception('Could not read that image');
  return data.buffer.asUint8List();
}

/// A deck card's picture: the owner's proxy photo when there is one,
/// otherwise the official Scryfall image.
class DeckCardImage extends StatelessWidget {
  final AppServices services;
  final DeckCard card;
  final double? width;
  final BoxFit fit;
  final double radius;

  /// Full-size official image (for the gallery viewer).
  final bool large;
  const DeckCardImage(this.services, this.card,
      {super.key, this.width, this.fit = BoxFit.cover, this.radius = 8, this.large = false});

  Widget _placeholder(BuildContext context) => Container(
        width: width,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(4),
        child: width != null && width! < 60
            ? const Icon(Icons.style, size: 18)
            : Text(card.name, textAlign: TextAlign.center),
      );

  Widget _official(BuildContext context) {
    final url = card.card?.imageUrl;
    if (url == null) return _placeholder(context);
    if (large) return CardGalleryScreen.networkCard(url, card.name);
    return Image.network(url, width: width, fit: fit, errorBuilder: (_, _, _) => _placeholder(context));
  }

  @override
  Widget build(BuildContext context) {
    final path = card.proxyImage;
    final cached = path == null ? null : services.backend.cachedProxyUrl(path);
    final Widget child = path == null
        ? _official(context)
        : cached != null
            ? Image.network(cached, width: width, fit: fit, errorBuilder: (_, _, _) => _official(context))
            : FutureBuilder<String?>(
            future: services.backend.proxyImageUrl(path),
            builder: (context, snap) {
              final url = snap.data;
              if (url == null) return snap.connectionState == ConnectionState.done ? _official(context) : _placeholder(context);
              return Image.network(url, width: width, fit: fit, errorBuilder: (_, _, _) => _official(context));
            },
          );
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: child);
  }
}
