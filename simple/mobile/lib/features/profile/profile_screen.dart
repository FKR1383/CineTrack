import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/errors/api_exception.dart';
import '../../core/widgets/common_widgets.dart';
import '../../core/storage/cache_maintenance.dart';
import '../../core/storage/local_database.dart';
import '../auth/auth_controller.dart';
import '../media/media_detail_screen.dart';
import '../shared/main_shell.dart';
import '../shared/models.dart';
import '../shared/ui_helpers.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, required this.guestMode});

  final bool guestMode;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  UserStats? _stats;
  List<ActivityItem> _activity = const [];
  bool _loading = false;
  String? _error;
  bool _avatarBusy = false;

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
      final repository = ref.read(repositoryProvider);
      final values = await Future.wait<Object>([
        repository.profile(),
        repository.stats(),
        repository.activity(),
      ]);
      final user = values[0] as UserModel;
      if (!mounted) return;
      ref.read(authControllerProvider.notifier).setUser(user);
      setState(() {
        _stats = values[1] as UserStats;
        _activity = values[2] as List<ActivityItem>;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editProfile(UserModel user) async {
    final firstName = TextEditingController(text: user.firstName);
    final lastName = TextEditingController(text: user.lastName);
    final username = TextEditingController(text: user.username);
    final email = TextEditingController(text: user.email);
    final bio = TextEditingController(text: user.bio ?? '');
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ویرایش پروفایل'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(child: TextField(controller: firstName, decoration: const InputDecoration(labelText: 'نام'))),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(controller: lastName, decoration: const InputDecoration(labelText: 'نام خانوادگی'))),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: username,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'نام کاربری', helperText: 'حروف انگلیسی، عدد، نقطه، خط تیره یا زیرخط'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'ایمیل'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bio,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: 'توضیح کوتاه درباره شما'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
          FilledButton(
            onPressed: () {
              if (firstName.text.trim().isEmpty ||
                  lastName.text.trim().isEmpty ||
                  username.text.trim().length < 3 ||
                  !email.text.contains('@')) {
                return;
              }
              Navigator.pop(context, {
                'first_name': firstName.text.trim(),
                'last_name': lastName.text.trim(),
                'username': username.text.trim(),
                'email': email.text.trim(),
                'bio': bio.text.trim(),
              });
            },
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
    if (values == null) return;
    try {
      final updated = await ref.read(repositoryProvider).updateProfile(values);
      ref.read(authControllerProvider.notifier).setUser(updated);
      if (mounted) showMessage(context, 'پروفایل به‌روزرسانی شد.');
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  Future<void> _pickAvatar() async {
    if (_avatarBusy) return;
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (image == null) return;
    setState(() => _avatarBusy = true);
    try {
      final updated = await ref.read(repositoryProvider).uploadAvatar(image.path);
      ref.read(authControllerProvider.notifier).setUser(updated);
      if (mounted) showMessage(context, 'تصویر پروفایل تغییر کرد.');
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _deleteAvatar() async {
    if (_avatarBusy) return;
    setState(() => _avatarBusy = true);
    try {
      final updated = await ref.read(repositoryProvider).deleteAvatar();
      ref.read(authControllerProvider.notifier).setUser(updated);
      if (mounted) showMessage(context, 'تصویر پروفایل حذف شد.');
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('خروج امن'),
        content: const Text('از حساب کاربری خارج می‌شوید و نشست ذخیره‌شده روی این دستگاه حذف می‌شود.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('خروج')),
        ],
      ),
    );
    if (confirmed == true) await ref.read(authControllerProvider.notifier).logout();
  }

  Future<void> _clearCacheSafely() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('پاک‌سازی کش'),
        content: const Text('فقط پاسخ‌های TMDB، جزئیات موقت و کش تصاویر پاک می‌شوند. امتیازها، نظرها، لیست‌ها، وضعیت تماشا و حساب کاربری شما حذف نمی‌شوند.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('پاک‌سازی')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await CacheMaintenanceService(LocalDatabase.instance).clearProviderCacheSafely();
    if (mounted) showMessage(context, 'کش با موفقیت پاک شد (${result.apiEntries} پاسخ API). اطلاعات شخصی محفوظ ماند.');
  }

  Future<void> _toggleBiometric(bool enabled) async {
    final ok = await ref.read(authControllerProvider.notifier).setBiometricEnabled(enabled);
    if (!mounted) return;
    showMessage(context, ok ? (enabled ? 'ورود بیومتریک فعال شد.' : 'ورود بیومتریک غیرفعال شد.') : 'بیومتریک در دسترس نیست یا تأیید نشد.', error: !ok);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    if (widget.guestMode || auth.status != AuthStatus.authenticated || auth.user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('پروفایل')),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: const [
            SizedBox(height: 24),
            AuthRequiredView(message: 'برای مشاهده پروفایل، آمار فعالیت و تاریخچه خود وارد حساب شوید.'),
            ResponsiveBody(child: TmdbAttributionCard()),
          ],
        ),
      );
    }
    final user = auth.user!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('پروفایل و آمار'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh), tooltip: 'به‌روزرسانی'),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout), tooltip: 'خروج امن'),
        ],
      ),
      body: _loading && _stats == null
          ? const LoadingView()
          : _error != null && _stats == null
              ? ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 32),
                    children: [
                      ResponsiveBody(child: _ProfileHeader(
                        user: user,
                        avatarBusy: _avatarBusy,
                        onEdit: () => _editProfile(user),
                        onAvatar: _pickAvatar,
                        onDeleteAvatar: user.avatarUrl == null ? null : _deleteAvatar,
                      )),
                      ResponsiveBody(
                        child: Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Column(
                            children: [
                              SwitchListTile(
                                secondary: const Icon(Icons.fingerprint),
                                title: const Text('ورود بیومتریک'),
                                subtitle: const Text('نشست ورود تا ۳۰ روز معتبر است؛ در اجرای بعدی برنامه با بیومتریک قفل را باز کنید.'),
                                value: auth.biometricEnabled,
                                onChanged: _toggleBiometric,
                              ),
                              const Divider(height: 1),
                              ListTile(
                                leading: const Icon(Icons.cleaning_services_outlined),
                                title: const Text('پاک‌سازی امن کش'),
                                subtitle: const Text('فقط کش TMDB و تصاویر پاک می‌شود؛ امتیازها، نظرها، لیست‌ها و وضعیت تماشا باقی می‌مانند.'),
                                trailing: const Icon(Icons.chevron_left),
                                onTap: _clearCacheSafely,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_stats != null) ResponsiveBody(child: _StatsGrid(stats: _stats!)),
                      ResponsiveBody(child: _ActivitySection(items: _activity)),
                      const ResponsiveBody(child: TmdbAttributionCard()),
                    ],
                  ),
                ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.user,
    required this.avatarBusy,
    required this.onEdit,
    required this.onAvatar,
    required this.onDeleteAvatar,
  });

  final UserModel user;
  final bool avatarBusy;
  final VoidCallback onEdit;
  final VoidCallback onAvatar;
  final VoidCallback? onDeleteAvatar;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final info = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.fullName, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                Directionality(textDirection: TextDirection.ltr, child: Text('@${user.username}')),
                Directionality(textDirection: TextDirection.ltr, child: Text(user.email)),
                if (user.bio?.isNotEmpty == true) ...[
                  const SizedBox(height: 10),
                  Text(user.bio!),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(onPressed: onEdit, icon: const Icon(Icons.edit_outlined), label: const Text('ویرایش اطلاعات')),
                    OutlinedButton.icon(onPressed: avatarBusy ? null : onAvatar, icon: const Icon(Icons.photo_camera_outlined), label: const Text('تغییر تصویر')),
                    if (onDeleteAvatar != null)
                      TextButton.icon(onPressed: avatarBusy ? null : onDeleteAvatar, icon: const Icon(Icons.delete_outline), label: const Text('حذف تصویر')),
                  ],
                ),
              ],
            );
            final avatarWidget = Stack(
              alignment: Alignment.center,
              children: [
                SecureAvatar(
                  radius: 58,
                  url: user.avatarUrl,
                  fallbackText: firstCharacter(user.firstName),
                ),
                if (avatarBusy) const CircularProgressIndicator(),
              ],
            );
            if (constraints.maxWidth > 650) {
              return Row(children: [avatarWidget, const SizedBox(width: 24), Expanded(child: info)]);
            }
            return Column(children: [avatarWidget, const SizedBox(height: 18), info]);
          },
        ),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats});
  final UserStats stats;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _StatData(Icons.movie_outlined, 'فیلم مشاهده‌شده', '${stats.watchedMovies}'),
      _StatData(Icons.live_tv_outlined, 'سریال مشاهده‌شده', '${stats.watchedSeries}'),
      _StatData(Icons.playlist_play, 'قسمت مشاهده‌شده', '${stats.watchedEpisodes}'),
      _StatData(Icons.schedule, 'زمان تقریبی تماشا', '${stats.approximateWatchHours.toStringAsFixed(1)} ساعت'),
      _StatData(Icons.category_outlined, 'ژانر محبوب', stats.favoriteGenre ?? 'نامشخص'),
      _StatData(Icons.star_outline, 'میانگین امتیاز شما', stats.averageUserRating?.toStringAsFixed(2) ?? '—'),
      _StatData(Icons.favorite_outline, 'علاقه‌مندی‌ها', '${stats.favoritesCount}'),
      _StatData(Icons.playlist_add_check, 'فهرست‌های شخصی', '${stats.customListsCount}'),
    ];
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('آمار فعالیت شما', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 900 ? 4 : constraints.maxWidth >= 500 ? 2 : 1;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: cards.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    childAspectRatio: columns == 1 ? 4.2 : 2.2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemBuilder: (_, index) => _StatCard(data: cards[index]),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StatData {
  const _StatData(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.data});
  final _StatData data;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(child: Icon(data.icon)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data.value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    Text(data.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _ActivitySection extends StatelessWidget {
  const _ActivitySection({required this.items});
  final List<ActivityItem> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('آخرین فعالیت‌ها', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: EmptyView(message: 'هنوز فعالیتی ثبت نشده است.', icon: Icons.history),
              )
            else
              for (final item in items)
                ListTile(
                  leading: CircleAvatar(child: Icon(_activityIcon(item.kind))),
                  title: Text(item.mediaTitle),
                  subtitle: Text('${activityLabel(item.kind)}${item.detail?.isNotEmpty == true ? ' • ${item.detail}' : ''}\n${formatDate(item.occurredAt)}'),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_left),
                  onTap: item.mediaId.isEmpty
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MediaDetailScreen(mediaId: item.mediaId))),
                ),
          ],
        ),
      ),
    );
  }

  static IconData _activityIcon(String kind) => switch (kind) {
        'watch_status' => Icons.visibility_outlined,
        'favorite' => Icons.favorite_outline,
        'rating' => Icons.star_outline,
        'comment' => Icons.comment_outlined,
        'episode' => Icons.play_circle_outline,
        _ => Icons.history,
      };
}
