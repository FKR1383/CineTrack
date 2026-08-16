import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../features/shared/models.dart';

void showMessage(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 64, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('تلاش دوباره')),
            ],
          ),
        ),
      );
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.message, this.icon = Icons.inbox_outlined});
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 64, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message = 'در حال دریافت اطلاعات...'});
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(message),
            ],
          ),
        ),
      );
}

class TmdbAttributionCard extends StatelessWidget {
  const TmdbAttributionCard({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: compact ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: theme.colorScheme.primary)),
                  child: const Text('TMDB', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 10),
                const Expanded(child: Text('منبع مستقیم اطلاعات فیلم و سریال در مدل ساده')),
              ],
            ),
            const SizedBox(height: 8),
            const Directionality(
              textDirection: TextDirection.ltr,
              child: Text('This product uses the TMDB API but is not endorsed or certified by TMDB.', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}

class SecureAvatar extends StatelessWidget {
  const SecureAvatar({super.key, required this.url, required this.fallbackText, this.radius = 20});
  final String? url;
  final String fallbackText;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final path = url?.trim();
    final fallback = Text(
      fallbackText.isEmpty ? '؟' : fallbackText,
      style: TextStyle(fontSize: radius * 0.58, fontWeight: FontWeight.w600),
    );
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      return CircleAvatar(radius: radius, child: fallback);
    }
    return CircleAvatar(
      radius: radius,
      backgroundImage: FileImage(File(path)),
      onBackgroundImageError: (_, __) {},
      child: const SizedBox.shrink(),
    );
  }
}

class MediaPoster extends StatelessWidget {
  const MediaPoster({super.key, required this.url, this.width, this.height, this.borderRadius = 12});
  final String? url;
  final double? width;
  final double? height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    Widget placeholder() => Image.asset(
          'assets/images/poster_placeholder.png',
          width: width,
          height: height,
          fit: BoxFit.cover,
        );
    final imageUrl = url?.trim() ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: imageUrl.isEmpty
          ? placeholder()
          : CachedNetworkImage(
              imageUrl: imageUrl,
              width: width,
              height: height,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 180),
              placeholder: (_, __) => Container(
                width: width,
                height: height,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              errorWidget: (_, __, ___) => placeholder(),
            ),
    );
  }
}

class MediaCard extends StatelessWidget {
  const MediaCard({super.key, required this.media, required this.onTap, this.width = 148, this.progress});
  final MediaSummary media;
  final VoidCallback onTap;
  final double width;
  final ProgressModel? progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 2 / 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MediaPoster(url: media.posterUrl, borderRadius: 0),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          child: Text(
                            media.providerRating?.toStringAsFixed(1) ?? '—',
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                    if (progress != null)
                      Positioned(
                        right: 0,
                        left: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: (progress!.progressPercent / 100).clamp(0.0, 1.0).toDouble(),
                          minHeight: 7,
                          color: _hexColor(progress!.progressHex),
                          backgroundColor: Colors.black54,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(media.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('${media.releaseYear ?? '—'} • ${media.isSeries ? 'سریال' : 'فیلم'}', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _hexColor(String value) {
  final normalized = value.replaceFirst('#', '');
  return Color(int.tryParse('FF$normalized', radix: 16) ?? 0xFF212121);
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      );
}

class ResponsiveBody extends StatelessWidget {
  const ResponsiveBody({super.key, required this.child, this.maxWidth = 1100});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      );
}
