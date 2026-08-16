import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/api_exception.dart';
import '../../core/widgets/common_widgets.dart';
import '../auth/auth_controller.dart';
import '../media/media_detail_screen.dart';
import '../shared/models.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, required this.guestMode});

  final bool guestMode;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late Future<HomeSections> _future = _load();

  Future<HomeSections> _load() => ref.read(repositoryProvider).home();

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  void _open(MediaSummary media) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MediaDetailScreen(mediaId: media.mediaId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Cine Track Simple'),
            Text(
              widget.guestMode ? 'حالت مهمان' : 'سلام ${user?.firstName ?? ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh), tooltip: 'به‌روزرسانی'),
        ],
      ),
      body: FutureBuilder<HomeSections>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const LoadingView();
          if (snapshot.hasError) {
            final message = snapshot.error is ApiException
                ? (snapshot.error as ApiException).message
                : 'دریافت صفحه اصلی با خطا مواجه شد.';
            return ErrorView(message: message, onRetry: _refresh);
          }
          final data = snapshot.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const _HeroBanner(),
                _MediaSection(title: 'فیلم‌های محبوب', items: data.popularMovies, onTap: _open),
                _MediaSection(title: 'سریال‌های محبوب', items: data.popularSeries, onTap: _open),
                _MediaSection(title: 'آثار جدید', items: data.newReleases, onTap: _open),
                _MediaSection(title: 'بالاترین امتیاز', items: data.topRated, onTap: _open),
                _MediaSection(
                  title: 'پیشنهاد برای شما',
                  subtitle: 'پیشنهادهای عمومی بر اساس ترندهای TMDB',
                  items: data.recommendations,
                  onTap: _open,
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.tertiary,
            ],
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'هر چیزی که می‌بینید، یک‌جا مدیریت کنید',
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'وضعیت تماشا، قسمت‌ها، امتیازها، نظرها و فهرست‌های شخصی',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
            SizedBox(width: 12),
            Icon(Icons.movie_filter_rounded, color: Colors.white, size: 72),
          ],
        ),
      ),
    );
  }
}

class _MediaSection extends StatelessWidget {
  const _MediaSection({
    required this.title,
    required this.items,
    required this.onTap,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<MediaSummary> items;
  final ValueChanged<MediaSummary> onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(title: title, subtitle: subtitle),
        SizedBox(
          height: 310,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, index) => MediaCard(
              media: items[index],
              onTap: () => onTap(items[index]),
            ),
          ),
        ),
      ],
    );
  }
}
