import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/api_exception.dart';
import '../../core/widgets/common_widgets.dart';
import '../auth/auth_controller.dart';
import '../media/media_detail_screen.dart';
import '../shared/main_shell.dart';
import '../shared/models.dart';
import '../shared/ui_helpers.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key, required this.guestMode});

  final bool guestMode;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String? _status;
  List<LibraryEntry> _items = const [];
  bool _loading = false;
  bool _hasNext = false;
  int _page = 1;
  String? _error;

  bool get _authenticated =>
      ref.read(authControllerProvider).status == AuthStatus.authenticated;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_authenticated) _load(reset: true);
    });
  }

  Future<void> _load({required bool reset}) async {
    if (_loading || !_authenticated) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _page = 1;
        _items = const [];
      }
    });
    try {
      final result = await ref.read(repositoryProvider).library(status: _status, page: _page);
      if (!mounted) return;
      setState(() {
        _items = reset ? result.items : [..._items, ...result.items];
        _hasNext = result.hasNext;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    setState(() => _page += 1);
    await _load(reset: false);
  }

  Future<void> _setFilter(String? value) async {
    setState(() => _status = value);
    await _load(reset: true);
  }

  Future<void> _changeStatus(LibraryEntry entry, String? status) async {
    try {
      if (status == null) {
        await ref.read(repositoryProvider).removeFromLibrary(entry.media.mediaId);
      } else {
        await ref.read(repositoryProvider).setWatchStatus(entry.media.mediaId, status);
      }
      await _load(reset: true);
      if (mounted) showMessage(context, status == null ? 'از فهرست تماشا حذف شد.' : 'وضعیت تماشا تغییر کرد.');
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  Future<void> _toggleFavorite(LibraryEntry entry) async {
    try {
      await ref.read(repositoryProvider).setFavorite(entry.media.mediaId, !entry.isFavorite);
      await _load(reset: true);
      if (mounted) showMessage(context, entry.isFavorite ? 'از علاقه‌مندی حذف شد.' : 'به علاقه‌مندی افزوده شد.');
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  Future<void> _showStatusPicker(LibraryEntry entry) async {
    final selected = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('تغییر وضعیت تماشا'), leading: Icon(Icons.visibility_outlined)),
            for (final status in libraryStatuses.entries)
              RadioListTile<String>(
                value: status.key,
                groupValue: entry.watchStatus,
                title: Text(status.value),
                onChanged: (value) => Navigator.pop(context, value),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('حذف از فهرست تماشا'),
              onTap: () => Navigator.pop(context, '__remove__'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    await _changeStatus(entry, selected == '__remove__' ? null : selected);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    if (widget.guestMode || auth.status != AuthStatus.authenticated) {
      return Scaffold(
        appBar: AppBar(title: const Text('فهرست تماشا')),
        body: AuthRequiredView(message: 'فهرست تماشا، قسمت‌های مشاهده‌شده و علاقه‌مندی‌ها پس از ورود در دسترس هستند.'),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('فهرست تماشا'),
        actions: [
          IconButton(onPressed: _loading ? null : () => _load(reset: true), icon: const Icon(Icons.refresh), tooltip: 'به‌روزرسانی'),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 58,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                _FilterChip(label: 'همه', selected: _status == null, onTap: () => _setFilter(null)),
                for (final status in libraryStatuses.entries)
                  _FilterChip(
                    label: status.value,
                    selected: _status == status.key,
                    onTap: () => _setFilter(status.key),
                  ),
              ],
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading && _items.isEmpty) return const LoadingView(message: 'در حال دریافت فهرست تماشا...');
    if (_error != null && _items.isEmpty) return ErrorView(message: _error!, onRetry: () => _load(reset: true));
    if (_items.isEmpty) {
      return EmptyView(
        message: _status == null
            ? 'هنوز اثری به فهرست تماشا اضافه نکرده‌اید.'
            : 'در این وضعیت اثری وجود ندارد.',
        icon: Icons.video_library_outlined,
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: _items.length + (_hasNext ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _items.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: FilledButton.tonal(
                  onPressed: _loading ? null : _loadMore,
                  child: _loading
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('نمایش موارد بیشتر'),
                ),
              ),
            );
          }
          final entry = _items[index];
          return _LibraryEntryCard(
            entry: entry,
            onOpen: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => MediaDetailScreen(mediaId: entry.media.mediaId)),
            ).then((_) => _load(reset: true)),
            onStatus: () => _showStatusPicker(entry),
            onFavorite: () => _toggleFavorite(entry),
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
      );
}

class _LibraryEntryCard extends StatelessWidget {
  const _LibraryEntryCard({
    required this.entry,
    required this.onOpen,
    required this.onStatus,
    required this.onFavorite,
  });

  final LibraryEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onStatus;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final media = entry.media;
    final progress = entry.progress;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MediaPoster(url: media.posterUrl, width: 92, height: 138),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(media.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('${media.releaseYear ?? '—'} • ${mediaTypeLabel(media.mediaType)}'),
                    const SizedBox(height: 8),
                    Chip(
                      avatar: const Icon(Icons.visibility_outlined, size: 18),
                      label: Text(watchStatusLabel(entry.watchStatus)),
                    ),
                    if (progress != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: LinearProgressIndicator(
                              value: (progress.progressPercent / 100).clamp(0.0, 1.0).toDouble(),
                              minHeight: 10,
                              borderRadius: BorderRadius.circular(10),
                              color: colorFromHex(progress.progressHex),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text('${progress.progressPercent.toStringAsFixed(0)}٪'),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text('${progress.watchedEpisodes} دیده‌شده • ${progress.remainingEpisodes} باقی‌مانده', style: Theme.of(context).textTheme.bodySmall),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(onPressed: onStatus, icon: const Icon(Icons.edit_outlined), label: const Text('وضعیت')),
                        IconButton.filledTonal(
                          tooltip: entry.isFavorite ? 'حذف علاقه‌مندی' : 'افزودن به علاقه‌مندی',
                          onPressed: onFavorite,
                          icon: Icon(entry.isFavorite ? Icons.favorite : Icons.favorite_border),
                        ),
                      ],
                    ),
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
