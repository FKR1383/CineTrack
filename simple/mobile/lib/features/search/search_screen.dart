import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/api_exception.dart';
import '../../core/widgets/common_widgets.dart';
import '../auth/auth_controller.dart';
import '../media/media_detail_screen.dart';
import '../shared/models.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _query = TextEditingController();
  final _actor = TextEditingController();
  final _director = TextEditingController();
  final _genre = TextEditingController();
  final _year = TextEditingController();
  String? _mediaType;
  bool _showFilters = false;
  bool _loading = false;
  String? _error;
  List<MediaSummary> _items = [];
  int _page = 1;
  bool _hasNext = false;
  bool _searched = false;

  @override
  void dispose() {
    for (final controller in [_query, _actor, _director, _genre, _year]) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _hasSearchCriteria =>
      _query.text.trim().isNotEmpty ||
      _actor.text.trim().isNotEmpty ||
      _director.text.trim().isNotEmpty ||
      _genre.text.trim().isNotEmpty ||
      _year.text.trim().isNotEmpty ||
      _mediaType != null;

  Future<void> _search({required bool reset}) async {
    if (_loading) return;
    if (!_hasSearchCriteria) {
      setState(() {
        _searched = false;
        _error = null;
        _items = [];
        _page = 1;
        _hasNext = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _searched = true;
      if (reset) {
        _page = 1;
        _items = [];
      }
    });
    try {
      final result = await ref.read(repositoryProvider).search(
            query: _query.text,
            mediaType: _mediaType,
            actor: _actor.text,
            director: _director.text,
            genre: _genre.text,
            year: int.tryParse(_year.text.trim()),
            page: _page,
          );
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
    await _search(reset: false);
  }

  void _clearFilters() {
    _query.clear();
    _actor.clear();
    _director.clear();
    _genre.clear();
    _year.clear();
    setState(() {
      _mediaType = null;
      _searched = false;
      _error = null;
      _items = [];
      _page = 1;
      _hasNext = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('جست‌وجوی فیلم و سریال')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _query,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      hintText: 'نام فیلم یا سریال',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: (_) => _search(reset: true),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: () => setState(() => _showFilters = !_showFilters),
                  icon: Icon(_showFilters ? Icons.filter_alt_off : Icons.tune),
                  tooltip: 'فیلترهای پیشرفته',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'در مدل ساده، جست‌وجو مستقیماً از TMDB دریافت می‌شود و داده‌های شخصی روی دستگاه ذخیره می‌شوند.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _showFilters ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth > 650;
                          final fields = [
                            TextField(controller: _actor, decoration: const InputDecoration(labelText: 'نام بازیگر')),
                            TextField(controller: _director, decoration: const InputDecoration(labelText: 'نام کارگردان')),
                            TextField(controller: _genre, decoration: const InputDecoration(labelText: 'ژانر')),
                            TextField(
                              controller: _year,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'سال انتشار'),
                            ),
                          ];
                          if (!wide) {
                            return Column(
                              children: [for (final field in fields) Padding(padding: const EdgeInsets.only(bottom: 10), child: field)],
                            );
                          }
                          return GridView.count(
                            crossAxisCount: 2,
                            childAspectRatio: 5,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            children: fields,
                          );
                        },
                      ),
                      DropdownButtonFormField<String?>(
                        initialValue: _mediaType,
                        decoration: const InputDecoration(labelText: 'نوع اثر'),
                        items: const [
                          DropdownMenuItem<String?>(value: null, child: Text('همه')),
                          DropdownMenuItem<String?>(value: 'movie', child: Text('فیلم')),
                          DropdownMenuItem<String?>(value: 'series', child: Text('سریال')),
                        ],
                        onChanged: (value) => setState(() => _mediaType = value),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(onPressed: _clearFilters, icon: const Icon(Icons.clear_all), label: const Text('پاک کردن')),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: _loading ? null : () => _search(reset: true),
                            icon: const Icon(Icons.search),
                            label: const Text('اعمال فیلتر'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_loading && _items.isEmpty) const Expanded(child: LoadingView()),
          if (_error != null && _items.isEmpty)
            Expanded(child: ErrorView(message: _error!, onRetry: () => _search(reset: true))),
          if (!_loading && _error == null && _items.isEmpty && !_searched)
            const Expanded(
              child: EmptyView(
                message: 'نام فیلم یا سریال را وارد کنید و جست‌وجو را بزنید.',
                icon: Icons.manage_search,
              ),
            ),
          if (!_loading && _error == null && _items.isEmpty && _searched)
            const Expanded(
              child: EmptyView(
                message: 'اثری با این مشخصات در نتایج TMDB پیدا نشد.',
                icon: Icons.search_off,
              ),
            ),
          if (_items.isNotEmpty)
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _search(reset: true),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 1000
                        ? 6
                        : constraints.maxWidth >= 760
                            ? 5
                            : constraints.maxWidth >= 520
                                ? 4
                                : 2;
                    return GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.48,
                      ),
                      itemCount: _items.length + (_hasNext ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _items.length) {
                          return Center(
                            child: FilledButton.tonal(
                              onPressed: _loading ? null : _loadMore,
                              child: _loading ? const CircularProgressIndicator() : const Text('نتایج بیشتر'),
                            ),
                          );
                        }
                        final media = _items[index];
                        return MediaCard(
                          width: double.infinity,
                          media: media,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => MediaDetailScreen(mediaId: media.mediaId)),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
