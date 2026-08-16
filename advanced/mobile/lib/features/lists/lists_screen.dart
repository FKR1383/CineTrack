import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/api_exception.dart';
import '../../core/widgets/common_widgets.dart';
import '../auth/auth_controller.dart';
import '../media/media_detail_screen.dart';
import '../shared/main_shell.dart';
import '../shared/models.dart';
import '../shared/repository.dart';

class ListsScreen extends ConsumerStatefulWidget {
  const ListsScreen({super.key, required this.guestMode});

  final bool guestMode;

  @override
  ConsumerState<ListsScreen> createState() => _ListsScreenState();
}

class _ListsScreenState extends ConsumerState<ListsScreen> {
  List<CustomListModel> _lists = const [];
  bool _loading = false;
  String? _error;

  bool get _authenticated =>
      ref.read(authControllerProvider).status == AuthStatus.authenticated;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_authenticated) _load();
    });
  }

  Future<void> _load() async {
    if (!_authenticated) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final lists = await ref.read(repositoryProvider).customLists();
      if (mounted) setState(() => _lists = lists);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Map<String, dynamic>?> _listDialog({CustomListModel? list}) {
    final name = TextEditingController(text: list?.name ?? '');
    final description = TextEditingController(text: list?.description ?? '');
    var isPublic = list?.isPublic ?? false;
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(list == null ? 'فهرست شخصی جدید' : 'ویرایش فهرست'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  maxLength: 120,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'نام فهرست'),
                ),
                TextField(
                  controller: description,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: 'توضیحات (اختیاری)'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('فهرست عمومی'),
                  subtitle: const Text('برای توسعه‌های آینده و اشتراک‌گذاری قابل مشاهده خواهد بود.'),
                  value: isPublic,
                  onChanged: (value) => setDialogState(() => isPublic = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty) return;
                Navigator.pop(context, {
                  'name': name.text.trim(),
                  'description': description.text.trim(),
                  'is_public': isPublic,
                });
              },
              child: const Text('ذخیره'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _create() async {
    final values = await _listDialog();
    if (values == null) return;
    try {
      await ref.read(repositoryProvider).createList(
            name: values['name'] as String,
            description: values['description'] as String,
            isPublic: values['is_public'] as bool,
          );
      await _load();
      if (mounted) showMessage(context, 'فهرست شخصی ساخته شد.');
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  Future<void> _edit(CustomListModel list) async {
    final values = await _listDialog(list: list);
    if (values == null) return;
    try {
      await ref.read(repositoryProvider).updateList(
            list.id,
            name: values['name'] as String,
            description: values['description'] as String,
            isPublic: values['is_public'] as bool,
          );
      await _load();
      if (mounted) showMessage(context, 'فهرست ویرایش شد.');
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  Future<void> _delete(CustomListModel list) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف فهرست شخصی'),
        content: Text('فهرست «${list.name}» و ارتباط آثار آن حذف شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(repositoryProvider).deleteList(list.id);
      await _load();
      if (mounted) showMessage(context, 'فهرست حذف شد.');
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    if (widget.guestMode || auth.status != AuthStatus.authenticated) {
      return Scaffold(
        appBar: AppBar(title: const Text('فهرست‌های شخصی')),
        body: AuthRequiredView(message: 'برای ساخت فهرست‌های دلخواه و افزودن آثار به آن‌ها وارد حساب شوید.'),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('فهرست‌های شخصی'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh), tooltip: 'به‌روزرسانی'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('فهرست جدید'),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading && _lists.isEmpty) return const LoadingView(message: 'در حال دریافت فهرست‌ها...');
    if (_error != null && _lists.isEmpty) return ErrorView(message: _error!, onRetry: _load);
    if (_lists.isEmpty) {
      return const EmptyView(
        message: 'هنوز فهرست شخصی نساخته‌اید. برای نمونه «بهترین فیلم‌های اکشن» را بسازید.',
        icon: Icons.playlist_add,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
        itemCount: _lists.length,
        itemBuilder: (context, index) {
          final list = _lists[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: CircleAvatar(
                child: Icon(list.isPublic ? Icons.public : Icons.lock_outline),
              ),
              title: Text(list.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text([
                  '${list.itemCount} اثر',
                  list.isPublic ? 'عمومی' : 'خصوصی',
                  if (list.description?.isNotEmpty == true) list.description!,
                ].join(' • ')),
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => CustomListDetailScreen(listId: list.id)),
              ).then((_) => _load()),
              trailing: PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') _edit(list);
                  if (value == 'delete') _delete(list);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                  PopupMenuItem(value: 'delete', child: Text('حذف')),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class CustomListDetailScreen extends ConsumerStatefulWidget {
  const CustomListDetailScreen({super.key, required this.listId});

  final String listId;

  @override
  ConsumerState<CustomListDetailScreen> createState() => _CustomListDetailScreenState();
}

class _CustomListDetailScreenState extends ConsumerState<CustomListDetailScreen> {
  CustomListModel? _list;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ref.read(repositoryProvider).customList(widget.listId);
      if (mounted) setState(() => _list = list);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _remove(MediaSummary media) async {
    try {
      await ref.read(repositoryProvider).removeListItem(widget.listId, media.mediaId);
      await _load();
      if (mounted) showMessage(context, 'اثر از فهرست حذف شد.');
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  Future<void> _addBySearch() async {
    final selected = await showDialog<MediaSummary>(
      context: context,
      builder: (_) => _MediaSearchDialog(repository: ref.read(repositoryProvider)),
    );
    if (selected == null) return;
    try {
      await ref.read(repositoryProvider).addListItem(widget.listId, selected.mediaId);
      await _load();
      if (mounted) showMessage(context, '«${selected.title}» به فهرست افزوده شد.');
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_list?.name ?? 'فهرست شخصی'),
        actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addBySearch,
        icon: const Icon(Icons.search),
        label: const Text('یافتن و افزودن اثر'),
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _content(_list!),
    );
  }

  Widget _content(CustomListModel list) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
        children: [
          Card(
            child: ListTile(
              leading: Icon(list.isPublic ? Icons.public : Icons.lock_outline),
              title: Text(list.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(list.description?.isNotEmpty == true ? list.description! : 'بدون توضیحات'),
              trailing: Chip(label: Text('${list.itemCount} اثر')),
            ),
          ),
          const SizedBox(height: 8),
          if (list.items.isEmpty)
            const SizedBox(
              height: 360,
              child: EmptyView(message: 'این فهرست هنوز اثری ندارد.', icon: Icons.playlist_add),
            )
          else
            for (final media in list.items)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(10),
                  leading: MediaPoster(url: media.posterUrl, width: 54, height: 81),
                  title: Text(media.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${media.releaseYear ?? '—'} • ${media.mediaType == 'series' ? 'سریال' : 'فیلم'}'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => MediaDetailScreen(mediaId: media.mediaId)),
                  ),
                  trailing: IconButton(
                    tooltip: 'حذف از فهرست',
                    onPressed: () => _remove(media),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _MediaSearchDialog extends StatefulWidget {
  const _MediaSearchDialog({required this.repository});
  final CineTrackRepository repository;

  @override
  State<_MediaSearchDialog> createState() => _MediaSearchDialogState();
}

class _MediaSearchDialogState extends State<_MediaSearchDialog> {
  final _controller = TextEditingController();
  List<MediaSummary> _items = const [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.repository.search(query: _controller.text, page: 1);
      if (mounted) setState(() => _items = result.items);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('جست‌وجو و افزودن اثر'),
      content: SizedBox(
        width: 620,
        height: 520,
        child: Column(
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                labelText: 'نام فیلم یا سریال',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(onPressed: _loading ? null : _search, icon: const Icon(Icons.arrow_forward)),
              ),
            ),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            Expanded(
              child: _items.isEmpty
                  ? const EmptyView(message: 'نام اثر را جست‌وجو کنید.', icon: Icons.search)
                  : ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final media = _items[index];
                        return ListTile(
                          leading: MediaPoster(url: media.posterUrl, width: 42, height: 63),
                          title: Text(media.title),
                          subtitle: Text('${media.releaseYear ?? '—'} • ${media.mediaType == 'series' ? 'سریال' : 'فیلم'}'),
                          onTap: () => Navigator.pop(context, media),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن'))],
    );
  }
}
