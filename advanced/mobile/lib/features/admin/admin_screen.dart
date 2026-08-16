import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/api_exception.dart';
import '../../core/widgets/common_widgets.dart';
import '../auth/auth_controller.dart';
import '../media/media_detail_screen.dart';
import '../shared/models.dart';
import '../shared/ui_helpers.dart';

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  Map<String, dynamic> _stats = const {};
  List<UserModel> _users = const [];
  List<Map<String, dynamic>> _reports = const [];
  List<MediaSummary> _media = const [];
  bool _loading = true;
  String? _error;
  String _userQuery = '';
  int _userPage = 1;
  bool _usersHaveNext = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
      _userPage = 1;
    });
    try {
      final repository = ref.read(repositoryProvider);
      final values = await Future.wait<Object>([
        repository.adminStats(),
        repository.adminUsers(query: _userQuery, page: 1),
        repository.adminReports(),
        repository.adminMedia(),
      ]);
      if (!mounted) return;
      final users = values[1] as PageResult<UserModel>;
      setState(() {
        _stats = values[0] as Map<String, dynamic>;
        _users = users.items;
        _usersHaveNext = users.hasNext;
        _reports = values[2] as List<Map<String, dynamic>>;
        _media = values[3] as List<MediaSummary>;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMoreUsers() async {
    if (!_usersHaveNext) return;
    try {
      final nextPage = _userPage + 1;
      final result = await ref.read(repositoryProvider).adminUsers(query: _userQuery, page: nextPage);
      if (!mounted) return;
      setState(() {
        _userPage = nextPage;
        _users = [..._users, ...result.items];
        _usersHaveNext = result.hasNext;
      });
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  Future<void> _searchUsers(String query) async {
    _userQuery = query.trim();
    try {
      final result = await ref.read(repositoryProvider).adminUsers(query: _userQuery, page: 1);
      if (!mounted) return;
      setState(() {
        _userPage = 1;
        _users = result.items;
        _usersHaveNext = result.hasNext;
      });
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  Future<void> _updateUser(UserModel user, {String? role, bool? active}) async {
    try {
      await ref.read(repositoryProvider).adminUpdateUser(user.id, role: role, active: active);
      await _loadAll();
      if (mounted) showMessage(context, 'تنظیمات کاربر به‌روزرسانی شد.');
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  Future<void> _resolveReport(Map<String, dynamic> report) async {
    var status = report['status']?.toString() ?? 'open';
    final note = TextEditingController(text: report['resolution_note']?.toString() ?? '');
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('رسیدگی به گزارش'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'وضعیت گزارش'),
                  items: const [
                    DropdownMenuItem(value: 'open', child: Text('باز')),
                    DropdownMenuItem(value: 'reviewed', child: Text('بررسی‌شده')),
                    DropdownMenuItem(value: 'resolved', child: Text('حل‌شده')),
                    DropdownMenuItem(value: 'dismissed', child: Text('ردشده')),
                  ],
                  onChanged: (value) => setDialogState(() => status = value ?? status),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: 'یادداشت رسیدگی (اختیاری)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
            FilledButton(
              onPressed: () => Navigator.pop(context, {'status': status, 'note': note.text.trim()}),
              child: const Text('ذخیره'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    try {
      await ref.read(repositoryProvider).resolveReport(
            report['id'].toString(),
            result['status']!,
            note: result['note'],
          );
      await _loadAll();
      if (mounted) showMessage(context, 'گزارش به‌روزرسانی شد.');
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  Future<void> _deleteReportedComment(Map<String, dynamic> report) async {
    final commentId = report['comment_id']?.toString();
    if (commentId == null || commentId.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف نظر گزارش‌شده'),
        content: const Text('نظر نامناسب برای همیشه حذف شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف نظر')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(repositoryProvider).adminDeleteComment(commentId);
      await ref.read(repositoryProvider).resolveReport(report['id'].toString(), 'resolved', note: 'نظر توسط مدیر حذف شد.');
      await _loadAll();
      if (mounted) showMessage(context, 'نظر حذف و گزارش حل‌شده ثبت شد.');
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  Future<void> _refreshMedia(MediaSummary media) async {
    try {
      await ref.read(repositoryProvider).adminRefreshMedia(media.mediaId);
      await _loadAll();
      if (mounted) showMessage(context, 'اطلاعات اثر از سرویس خارجی تازه‌سازی شد.');
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  Future<void> _editMedia(MediaSummary media) async {
    final title = TextEditingController(text: media.title);
    final originalTitle = TextEditingController(text: media.originalTitle ?? '');
    final plot = TextEditingController(text: media.plot ?? '');
    final poster = TextEditingController(text: media.posterUrl ?? '');
    final genres = TextEditingController(text: media.genres.join('، '));
    final status = TextEditingController(text: media.releaseStatus ?? '');
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('ویرایش داده ذخیره‌شده: ${media.title}'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: title, decoration: const InputDecoration(labelText: 'عنوان')),
                const SizedBox(height: 10),
                TextField(controller: originalTitle, decoration: const InputDecoration(labelText: 'عنوان اصلی')),
                const SizedBox(height: 10),
                TextField(controller: plot, minLines: 3, maxLines: 7, decoration: const InputDecoration(labelText: 'خلاصه داستان')),
                const SizedBox(height: 10),
                TextField(controller: genres, decoration: const InputDecoration(labelText: 'ژانرها (جداشده با ویرگول)')),
                const SizedBox(height: 10),
                TextField(controller: status, decoration: const InputDecoration(labelText: 'وضعیت انتشار')),
                const SizedBox(height: 10),
                TextField(controller: poster, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'آدرس پوستر')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
          FilledButton(
            onPressed: () {
              if (title.text.trim().isEmpty) return;
              Navigator.pop(context, {
                'title': title.text.trim(),
                'original_title': originalTitle.text.trim().isEmpty ? null : originalTitle.text.trim(),
                'plot': plot.text.trim().isEmpty ? null : plot.text.trim(),
                'poster_url': poster.text.trim().isEmpty ? null : poster.text.trim(),
                'genres': genres.text.split(RegExp(r'[,،]')).map((value) => value.trim()).where((value) => value.isNotEmpty).toList(),
                'release_status': status.text.trim().isEmpty ? null : status.text.trim(),
              });
            },
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
    if (values == null) return;
    try {
      await ref.read(repositoryProvider).adminUpdateMedia(media.mediaId, values);
      await _loadAll();
      if (mounted) showMessage(context, 'اطلاعات ذخیره‌شده ویرایش شد.');
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  Future<void> _deleteMedia(MediaSummary media) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('پاک‌سازی کش اثر'),
        content: Text('کش اطلاعات و پوستر «${media.title}» پاک شود؟ امتیازها، نظرها، لیست‌ها و سوابق تماشای کاربران حذف نمی‌شوند و اطلاعات TMDB در درخواست بعدی دوباره دریافت می‌شود.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('پاک‌سازی')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(repositoryProvider).adminDeleteMedia(media.mediaId);
      await _loadAll();
      if (mounted) showMessage(context, 'کش اثر پاک شد و داده‌های کاربران محفوظ ماند.');
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    if (user?.isAdmin != true) {
      return const Scaffold(body: EmptyView(message: 'دسترسی مدیر سامانه لازم است.', icon: Icons.block));
    }
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مدیریت سامانه'),
          actions: [IconButton(onPressed: _loading ? null : _loadAll, icon: const Icon(Icons.refresh))],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.analytics_outlined), text: 'آمار کلی'),
              Tab(icon: Icon(Icons.people_outline), text: 'کاربران'),
              Tab(icon: Icon(Icons.report_outlined), text: 'گزارش‌ها'),
              Tab(icon: Icon(Icons.storage_outlined), text: 'آثار ذخیره‌شده'),
            ],
          ),
        ),
        body: _loading && _stats.isEmpty
            ? const LoadingView(message: 'در حال دریافت اطلاعات مدیریتی...')
            : _error != null && _stats.isEmpty
                ? ErrorView(message: _error!, onRetry: _loadAll)
                : TabBarView(
                    children: [
                      _StatsTab(stats: _stats),
                      _UsersTab(
                        users: _users,
                        hasNext: _usersHaveNext,
                        onSearch: _searchUsers,
                        onLoadMore: _loadMoreUsers,
                        onRole: (user, role) => _updateUser(user, role: role),
                        onActive: (user, active) => _updateUser(user, active: active),
                      ),
                      _ReportsTab(reports: _reports, onResolve: _resolveReport, onDeleteComment: _deleteReportedComment),
                      _MediaTab(media: _media, onOpen: _openMedia, onRefresh: _refreshMedia, onEdit: _editMedia, onDelete: _deleteMedia),
                    ],
                  ),
      ),
    );
  }

  void _openMedia(MediaSummary media) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MediaDetailScreen(mediaId: media.mediaId)));
  }
}

class _StatsTab extends StatelessWidget {
  const _StatsTab({required this.stats});
  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, String)>[
      (Icons.people_outline, 'کل کاربران', '${stats['users_total'] ?? 0}'),
      (Icons.verified_user_outlined, 'کاربران فعال', '${stats['users_active'] ?? 0}'),
      (Icons.movie_outlined, 'کل آثار', '${stats['media_total'] ?? 0}'),
      (Icons.local_movies_outlined, 'فیلم‌ها', '${stats['movies_total'] ?? 0}'),
      (Icons.live_tv_outlined, 'سریال‌ها', '${stats['series_total'] ?? 0}'),
      (Icons.comment_outlined, 'نظرها', '${stats['comments_total'] ?? 0}'),
      (Icons.report_problem_outlined, 'گزارش‌های باز', '${stats['open_reports'] ?? 0}'),
      (Icons.star_outline, 'امتیازها', '${stats['ratings_total'] ?? 0}'),
      (Icons.favorite_outline, 'علاقه‌مندی‌ها', '${stats['favorites_total'] ?? 0}'),
      (Icons.visibility_outlined, 'ورودی‌های تماشا', '${stats['watched_entries_total'] ?? 0}'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000 ? 4 : constraints.maxWidth >= 620 ? 3 : 2;
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: 1.45,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (_, index) {
            final item = items[index];
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(item.$1, size: 36),
                    const SizedBox(height: 8),
                    Text(item.$3, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                    Text(item.$2, textAlign: TextAlign.center),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _UsersTab extends StatefulWidget {
  const _UsersTab({
    required this.users,
    required this.hasNext,
    required this.onSearch,
    required this.onLoadMore,
    required this.onRole,
    required this.onActive,
  });

  final List<UserModel> users;
  final bool hasNext;
  final ValueChanged<String> onSearch;
  final VoidCallback onLoadMore;
  final void Function(UserModel, String) onRole;
  final void Function(UserModel, bool) onActive;

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: widget.onSearch,
            decoration: InputDecoration(
              labelText: 'جست‌وجوی نام، نام کاربری یا ایمیل',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(onPressed: () => widget.onSearch(_search.text), icon: const Icon(Icons.arrow_forward)),
            ),
          ),
        ),
        Expanded(
          child: widget.users.isEmpty
              ? const EmptyView(message: 'کاربری پیدا نشد.', icon: Icons.person_search_outlined)
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: widget.users.length + (widget.hasNext ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == widget.users.length) {
                      return Center(child: FilledButton.tonal(onPressed: widget.onLoadMore, child: const Text('کاربران بیشتر')));
                    }
                    final user = widget.users[index];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Text(firstCharacter(user.firstName))),
                        title: Text('${user.fullName} (@${user.username})'),
                        subtitle: Directionality(textDirection: TextDirection.ltr, child: Text(user.email)),
                        trailing: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            DropdownButton<String>(
                              value: user.role,
                              items: const [
                                DropdownMenuItem(value: 'user', child: Text('کاربر')),
                                DropdownMenuItem(value: 'admin', child: Text('مدیر')),
                              ],
                              onChanged: (value) {
                                if (value != null && value != user.role) widget.onRole(user, value);
                              },
                            ),
                            Switch(value: user.isActive, onChanged: (value) => widget.onActive(user, value)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ReportsTab extends StatelessWidget {
  const _ReportsTab({required this.reports, required this.onResolve, required this.onDeleteComment});
  final List<Map<String, dynamic>> reports;
  final ValueChanged<Map<String, dynamic>> onResolve;
  final ValueChanged<Map<String, dynamic>> onDeleteComment;

  @override
  Widget build(BuildContext context) {
    if (reports.isEmpty) return const EmptyView(message: 'گزارشی ثبت نشده است.', icon: Icons.task_alt);
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: reports.length,
      itemBuilder: (context, index) {
        final report = reports[index];
        final status = report['status']?.toString() ?? 'open';
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('گزارش از ${report['reporter_username'] ?? 'کاربر'}', style: const TextStyle(fontWeight: FontWeight.bold))),
                    Chip(label: Text(_reportStatus(status))),
                  ],
                ),
                const SizedBox(height: 6),
                Text(report['reason']?.toString() ?? ''),
                if (report['resolution_note']?.toString().isNotEmpty == true) ...[
                  const SizedBox(height: 6),
                  Text('یادداشت مدیر: ${report['resolution_note']}'),
                ],
                const SizedBox(height: 6),
                Text(formatDate(DateTime.tryParse(report['created_at']?.toString() ?? '')), style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.tonalIcon(onPressed: () => onResolve(report), icon: const Icon(Icons.fact_check_outlined), label: const Text('رسیدگی')),
                    if (report['comment_id'] != null)
                      OutlinedButton.icon(onPressed: () => onDeleteComment(report), icon: const Icon(Icons.delete_outline), label: const Text('حذف نظر')),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _reportStatus(String value) => switch (value) {
        'open' => 'باز',
        'reviewed' => 'بررسی‌شده',
        'resolved' => 'حل‌شده',
        'dismissed' => 'ردشده',
        _ => value,
      };
}

class _MediaTab extends StatelessWidget {
  const _MediaTab({
    required this.media,
    required this.onOpen,
    required this.onRefresh,
    required this.onEdit,
    required this.onDelete,
  });
  final List<MediaSummary> media;
  final ValueChanged<MediaSummary> onOpen;
  final ValueChanged<MediaSummary> onRefresh;
  final ValueChanged<MediaSummary> onEdit;
  final ValueChanged<MediaSummary> onDelete;

  @override
  Widget build(BuildContext context) {
    if (media.isEmpty) return const EmptyView(message: 'داده ذخیره‌شده‌ای وجود ندارد.', icon: Icons.storage_outlined);
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: media.length,
      itemBuilder: (context, index) {
        final item = media[index];
        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(10),
            leading: MediaPoster(url: item.posterUrl, width: 48, height: 72),
            title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${item.mediaId} • ${mediaTypeLabel(item.mediaType)} • ${item.releaseYear ?? '—'}'),
            onTap: () => onOpen(item),
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'refresh') onRefresh(item);
                if (value == 'edit') onEdit(item);
                if (value == 'delete') onDelete(item);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'refresh', child: Text('تازه‌سازی از TMDB')),
                PopupMenuItem(value: 'edit', child: Text('ویرایش داده ذخیره‌شده')),
                PopupMenuItem(value: 'delete', child: Text('حذف داده ذخیره‌شده')),
              ],
            ),
          ),
        );
      },
    );
  }
}
