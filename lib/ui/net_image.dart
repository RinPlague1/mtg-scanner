import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Disk cache for card pictures. The package default keeps only 200 images,
/// far fewer than a collection, so allow more. Least-recently-shown pictures
/// are dropped first once it's full, and any not shown for 60 days expire.
final cardImageCache = CacheManager(Config(
  'cardImages',
  stalePeriod: const Duration(days: 60),
  maxNrOfCacheObjects: 5000,
));

/// Deletes every saved card picture (they download again when next shown).
Future<void> clearImageCache() async {
  await cardImageCache.emptyCache();
  PaintingBinding.instance.imageCache
    ..clear()
    ..clearLiveImages();
}

/// A network image kept in a disk cache (so card pictures load instantly
/// after the first time, even after restarting the app) and decoded at the
/// size it's shown (so many more fit in the memory cache while scrolling).
class NetImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit? fit;

  /// Cache under this key instead of the URL (for links that change, such as
  /// signed proxy-photo links).
  final String? cacheKey;

  /// Shown if the image can't be loaded.
  final WidgetBuilder? fallback;

  /// Shown while it loads (default: nothing).
  final WidgetBuilder? loading;

  const NetImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.cacheKey,
    this.fallback,
    this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    Widget image(double? shownWidth) => CachedNetworkImage(
          imageUrl: url,
          cacheKey: cacheKey,
          cacheManager: cardImageCache,
          width: width,
          height: height,
          fit: fit,
          memCacheWidth: shownWidth == null || !shownWidth.isFinite ? null : (shownWidth * dpr).round(),
          fadeInDuration: const Duration(milliseconds: 120),
          fadeOutDuration: Duration.zero,
          placeholder: loading == null ? null : (context, _) => loading!(context),
          errorWidget: (context, _, _) => fallback?.call(context) ?? SizedBox(width: width, height: height),
        );
    if (width != null) return image(width);
    if (height != null) return image(null);
    // Size from the layout (grid tiles).
    return LayoutBuilder(builder: (context, c) => image(c.hasBoundedWidth ? c.maxWidth : null));
  }
}
