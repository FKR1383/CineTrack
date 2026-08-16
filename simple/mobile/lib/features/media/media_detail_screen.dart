import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/api_exception.dart';
import '../../core/widgets/common_widgets.dart';
import '../auth/auth_controller.dart';
import '../shared/models.dart';
import '../shared/repository.dart';
import '../shared/ui_helpers.dart';

class MediaDetailScreen extends ConsumerStatefulWidget {
  const MediaDetailScreen({super.key, required this.mediaId});

  final String mediaId;

  @override
  ConsumerState<MediaDetailScreen> createState() => _MediaDetailScreenState();
}

class _MediaDetailScreenState extends ConsumerState<MediaDetailScreen> {
  MediaDetail? _detail;
  List<SeasonModel> _seasons = const [];
  List<CommentModel> _comments = const [];
  String? _error;
  bool _loading = true;
  bool _commentsLoading = false;
  bool _actionBusy = false;
  int _commentPage = 1;
  bool _commentsHaveNext = false;
  final Set<String> _episodeBusy = <String>{};

  CineTrackRepository get _repository => ref.read(repositoryProvider);
  bool get _authenticated =>
      ref.read(authControllerProvider).status == AuthStatus.authenticated;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Render core TMDB details as soon as they arrive. Secondary sections are
      // loaded concurrently so a slow episode/comment request cannot hold the
      // entire page behind a spinner.
      final detail = await _repository.mediaDetail(widget.mediaId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });

      final values = await Future.wait<Object>([
        if (detail.isSeries)
          _repository.seasons(widget.mediaId)
        else
          Future<List<SeasonModel>>.value(<SeasonModel>[]),
        _repository.comments(widget.mediaId),
      ]);
      if (!mounted) return;
      final seasons = values[0] as List<SeasonModel>;
      final comments = values[1] as PageResult<CommentModel>;
      setState(() {
        _seasons = seasons;
        _comments = comments.items;
        _commentPage = comments.page;
        _commentsHaveNext = comments.hasNext;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'دریافت جزئیات اثر با خطا مواجه شد.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reloadDetail({bool includeSeasons = false}) async {
    try {
      final detail = await _repository.mediaDetail(widget.mediaId);
      List<SeasonModel>? seasons;
      if (includeSeasons && detail.isSeries) {
        seasons = await _repository.seasons(widget.mediaId);
      }
      if (!mounted) return;
      setState(() {
        _detail = detail;
        if (seasons != null) _seasons = seasons;
      });
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  Future<void> _loadComments({required bool reset}) async {
    if (_commentsLoading) return;
    setState(() => _commentsLoading = true);
    try {
      final page = reset ? 1 : _commentPage + 1;
      final result = await _repository.comments(widget.mediaId, page: page);
      if (!mounted) return;
      setState(() {
        _comments = reset ? result.items : [..._comments, ...result.items];
        _commentPage = result.page;
        _commentsHaveNext = result.hasNext;
      });
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _commentsLoading = false);
    }
  }

  bool _ensureAuthenticated() {
    if (_authenticated) return true;
    showMessage(context, 'برای انجام این عملیات ابتدا وارد حساب کاربری شوید.', error: true);
    return false;
  }

  Future<void> _runAction(
    Future<void> Function() action,
    String success, {
    bool includeSeasons = false,
  }) async {
    if (!_ensureAuthenticated() || _actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      await action();
      await _reloadDetail(includeSeasons: includeSeasons);
      if (mounted) showMessage(context, success);
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _setWatchStatus(String? status) async {
    if (status == null) {
      await _runAction(
        () => _repository.removeFromLibrary(widget.mediaId),
        'اثر از فهرست تماشا حذف شد.',
      );
      return;
    }
    await _runAction(
      () async {
        await _repository.setWatchStatus(widget.mediaId, status);
      },
      'وضعیت تماشا ثبت شد.',
    );
  }

  Future<void> _toggleFavorite() async {
    final enabled = !(_detail?.userState?.isFavorite ?? false);
    await _runAction(
      () => _repository.setFavorite(widget.mediaId, enabled),
      enabled ? 'به علاقه‌مندی‌ها افزوده شد.' : 'از علاقه‌مندی‌ها حذف شد.',
    );
  }

  Future<void> _setRating(int score) async {
    await _runAction(
      () async {
        await _repository.rate(widget.mediaId, score);
      },
      'امتیاز شما ثبت شد.',
    );
  }

  Future<void> _removeRating() async {
    await _runAction(
      () => _repository.removeRating(widget.mediaId),
      'امتیاز شما حذف شد.',
    );
  }

  Future<void> _markEpisode(EpisodeModel episode, bool watched) async {
    if (!_ensureAuthenticated() || _episodeBusy.contains(episode.episodeId)) return;
    setState(() => _episodeBusy.add(episode.episodeId));
    try {
      await _repository.markEpisode(episode.episodeId, watched);
      await _reloadDetail(includeSeasons: true);
      if (mounted) {
        showMessage(context, watched ? 'قسمت مشاهده‌شده علامت خورد.' : 'علامت مشاهده حذف شد.');
      }
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _episodeBusy.remove(episode.episodeId));
    }
  }

  Future<void> _showAddToList() async {
    if (!_ensureAuthenticated()) return;
    try {
      final lists = await _repository.customLists();
      if (!mounted) return;
      if (lists.isEmpty) {
        showMessage(context, 'ابتدا از بخش «فهرست‌ها» یک فهرست شخصی بسازید.');
        return;
      }
      final selected = await showModalBottomSheet<CustomListModel>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                leading: Icon(Icons.playlist_add),
                title: Text('افزودن به فهرست شخصی'),
                subtitle: Text('یک فهرست را انتخاب کنید'),
              ),
              for (final item in lists)
                ListTile(
                  leading: Icon(item.isPublic ? Icons.public : Icons.lock_outline),
                  title: Text(item.name),
                  subtitle: Text('${item.itemCount} اثر${item.description?.isNotEmpty == true ? ' • ${item.description}' : ''}'),
                  onTap: () => Navigator.pop(context, item),
                ),
            ],
          ),
        ),
      );
      if (selected == null) return;
      await _repository.addListItem(selected.id, widget.mediaId);
      if (mounted) showMessage(context, 'اثر به «${selected.name}» افزوده شد.');
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  Future<Map<String, dynamic>?> _commentDialog({CommentModel? existing}) {
    final controller = TextEditingController(text: existing?.text ?? '');
    var spoiler = existing?.isSpoiler ?? false;
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'ثبت نظر' : 'ویرایش نظر'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: 4000,
                  decoration: const InputDecoration(
                    labelText: 'متن نظر',
                    alignLabelWithHint: true,
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('این نظر حاوی اسپویل است'),
                  subtitle: const Text('متن ابتدا برای دیگر کاربران مخفی می‌شود.'),
                  value: spoiler,
                  onChanged: (value) => setDialogState(() => spoiler = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isEmpty) return;
                Navigator.pop(context, {'text': text, 'is_spoiler': spoiler});
              },
              child: const Text('ذخیره'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addComment() async {
    if (!_ensureAuthenticated()) return;
    final values = await _commentDialog();
    if (values == null) return;
    try {
      await _repository.addComment(
        widget.mediaId,
        text: values['text'] as String,
        isSpoiler: values['is_spoiler'] as bool,
      );
      await _loadComments(reset: true);
      if (mounted) showMessage(context, 'نظر ثبت شد.');
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  Future<void> _editComment(CommentModel comment) async {
    final values = await _commentDialog(existing: comment);
    if (values == null) return;
    try {
      await _repository.editComment(
        comment.id,
        text: values['text'] as String,
        isSpoiler: values['is_spoiler'] as bool,
      );
      await _loadComments(reset: true);
      if (mounted) showMessage(context, 'نظر ویرایش شد.');
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  Future<void> _deleteComment(CommentModel comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف نظر'),
        content: const Text('این نظر برای همیشه حذف شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.deleteComment(comment.id);
      await _loadComments(reset: true);
      if (mounted) showMessage(context, 'نظر حذف شد.');
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  Future<void> _reportComment(CommentModel comment) async {
    if (!_ensureAuthenticated()) return;
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('گزارش نظر نامناسب'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 5,
          maxLength: 500,
          decoration: const InputDecoration(labelText: 'دلیل گزارش'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.length >= 3) Navigator.pop(context, value);
            },
            child: const Text('ارسال گزارش'),
          ),
        ],
      ),
    );
    if (reason == null) return;
    try {
      await _repository.reportComment(comment.id, reason);
      if (mounted) showMessage(context, 'گزارش روی همین دستگاه ذخیره شد.');
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(_detail?.title ?? 'جزئیات اثر'),
        actions: [
          IconButton(
            tooltip: 'به‌روزرسانی',
            onPressed: _loading ? null : _loadAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const LoadingView(message: 'در حال دریافت جزئیات اثر...')
          : _error != null
              ? ErrorView(message: _error!, onRetry: _loadAll)
              : _buildContent(_detail!),
    );
  }

  Widget _buildContent(MediaDetail media) {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          ResponsiveBody(child: _Header(media: media)),
          ResponsiveBody(child: _PersonalActions(
            media: media,
            enabled: !_actionBusy,
            authenticated: _authenticated,
            onWatchStatus: _setWatchStatus,
            onFavorite: _toggleFavorite,
            onRating: _setRating,
            onRemoveRating: _removeRating,
            onAddToList: _showAddToList,
          )),
          if (media.isSeries) ...[
            ResponsiveBody(child: _ProgressCard(state: media.userState)),
            ResponsiveBody(child: _SeasonsSection(
              seasons: _seasons,
              busyEpisodeIds: _episodeBusy,
              authenticated: _authenticated,
              onChanged: _markEpisode,
            )),
          ],
          ResponsiveBody(child: _RatingSection(media: media)),
          ResponsiveBody(
            child: _CommentsSection(
              comments: _comments,
              authenticated: _authenticated,
              loading: _commentsLoading,
              hasNext: _commentsHaveNext,
              onAdd: _addComment,
              onEdit: _editComment,
              onDelete: _deleteComment,
              onReport: _reportComment,
              onLoadMore: () => _loadComments(reset: false),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.media});

  final MediaDetail media;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 720;
          final poster = MediaPoster(
            url: media.posterUrl,
            width: wide ? 230 : 170,
            height: wide ? 345 : 255,
            borderRadius: 20,
          );
          final details = Expanded(
            child: Padding(
              padding: EdgeInsetsDirectional.only(start: wide ? 24 : 0, top: wide ? 8 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    media.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  if (media.originalTitle?.isNotEmpty == true && media.originalTitle != media.title) ...[
                    const SizedBox(height: 4),
                    Text(media.originalTitle!, style: Theme.of(context).textTheme.titleMedium),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _InfoChip(icon: Icons.movie_outlined, text: mediaTypeLabel(media.mediaType)),
                      _InfoChip(icon: Icons.calendar_month_outlined, text: _yearRange(media)),
                      _InfoChip(icon: Icons.schedule, text: minutesLabel(media.runtimeMinutes)),
                      _InfoChip(icon: Icons.live_tv_outlined, text: releaseStatusLabel(media.releaseStatus)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [for (final genre in media.genres) Chip(label: Text(genre))],
                  ),
                  const SizedBox(height: 14),
                  Text(media.plot?.isNotEmpty == true ? media.plot! : 'خلاصه داستان ثبت نشده است.'),
                  const SizedBox(height: 16),
                  _MetaLine(label: 'کشور سازنده', value: media.countries.join('، ')),
                  _MetaLine(label: 'کارگردان', value: media.directors.join('، ')),
                  _MetaLine(label: 'بازیگران', value: media.cast.join('، ')),
                  if (media.isSeries) ...[
                    _MetaLine(label: 'تعداد فصل', value: '${media.seasonCount ?? _unknown(media)}'),
                    _MetaLine(label: 'تعداد قسمت', value: '${media.episodeCount ?? _unknown(media)}'),
                  ],
                ],
              ),
            ),
          );
          if (wide) return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [poster, details]);
          return Column(children: [Center(child: poster), Row(children: [details])]);
        },
      ),
    );
  }

  static String _yearRange(MediaDetail media) {
    if (media.releaseYear == null) return 'سال نامشخص';
    if (media.endYear != null && media.endYear != media.releaseYear) {
      return '${media.releaseYear}–${media.endYear}';
    }
    return '${media.releaseYear}';
  }

  static String _unknown(MediaDetail _) => '—';
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Chip(
        avatar: Icon(icon, size: 18),
        label: Text(text),
      );
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _PersonalActions extends StatelessWidget {
  const _PersonalActions({
    required this.media,
    required this.enabled,
    required this.authenticated,
    required this.onWatchStatus,
    required this.onFavorite,
    required this.onRating,
    required this.onRemoveRating,
    required this.onAddToList,
  });

  final MediaDetail media;
  final bool enabled;
  final bool authenticated;
  final ValueChanged<String?> onWatchStatus;
  final VoidCallback onFavorite;
  final ValueChanged<int> onRating;
  final VoidCallback onRemoveRating;
  final VoidCallback onAddToList;

  @override
  Widget build(BuildContext context) {
    final state = media.userState;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('مدیریت شخصی', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (!authenticated) const Chip(avatar: Icon(Icons.lock_outline, size: 18), label: Text('نیازمند ورود')),
              ],
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final controls = <Widget>[
                  DropdownButtonFormField<String?>(
                    initialValue: state?.watchStatus,
                    decoration: const InputDecoration(labelText: 'وضعیت تماشا', prefixIcon: Icon(Icons.visibility_outlined)),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('بدون وضعیت / حذف از فهرست')),
                      for (final item in watchStatuses.entries)
                        DropdownMenuItem<String?>(value: item.key, child: Text(item.value)),
                    ],
                    onChanged: enabled ? onWatchStatus : null,
                  ),
                  FilledButton.tonalIcon(
                    onPressed: enabled ? onFavorite : null,
                    icon: Icon(state?.isFavorite == true ? Icons.favorite : Icons.favorite_border),
                    label: Text(state?.isFavorite == true ? 'حذف علاقه‌مندی' : 'افزودن به علاقه‌مندی'),
                  ),
                  OutlinedButton.icon(
                    onPressed: enabled ? onAddToList : null,
                    icon: const Icon(Icons.playlist_add),
                    label: const Text('افزودن به فهرست شخصی'),
                  ),
                ];
                if (constraints.maxWidth > 760) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(flex: 2, child: controls[0]),
                      const SizedBox(width: 12),
                      Expanded(child: controls[1]),
                      const SizedBox(width: 12),
                      Expanded(child: controls[2]),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    controls[0],
                    const SizedBox(height: 10),
                    controls[1],
                    const SizedBox(height: 10),
                    controls[2],
                  ],
                );
              },
            ),
            const Divider(height: 32),
            Text('امتیاز شما', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (var score = 1; score <= 5; score++)
                  IconButton(
                    tooltip: '$score ستاره',
                    onPressed: enabled ? () => onRating(score) : null,
                    icon: Icon(
                      (state?.userRating ?? 0) >= score ? Icons.star_rounded : Icons.star_border_rounded,
                      color: Theme.of(context).colorScheme.tertiary,
                      size: 34,
                    ),
                  ),
                if (state?.userRating != null)
                  TextButton.icon(
                    onPressed: enabled ? onRemoveRating : null,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('حذف امتیاز'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.state});
  final UserMediaState? state;

  @override
  Widget build(BuildContext context) {
    final progress = state?.progressPercent ?? 0;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('پیشرفت تماشای سریال', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${progress.toStringAsFixed(0)}٪', style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: (progress / 100).clamp(0.0, 1.0).toDouble(),
              minHeight: 12,
              borderRadius: BorderRadius.circular(20),
              color: colorFromHex(state?.progressHex ?? '#212121'),
            ),
            const SizedBox(height: 10),
            Text('${state?.watchedEpisodes ?? 0} قسمت مشاهده‌شده • ${state?.remainingEpisodes ?? 0} قسمت باقی‌مانده'),
            const SizedBox(height: 8),
            const Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                _ProgressLegend(color: Colors.black, label: 'شروع نشده'),
                _ProgressLegend(color: Colors.yellow, label: 'قسمت باقی مانده'),
                _ProgressLegend(color: Colors.red, label: 'متوقف'),
                _ProgressLegend(color: Colors.green, label: 'قسمت آینده دارد'),
                _ProgressLegend(color: Colors.purple, label: 'کامل و پایان‌یافته'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressLegend extends StatelessWidget {
  const _ProgressLegend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class _SeasonsSection extends StatelessWidget {
  const _SeasonsSection({
    required this.seasons,
    required this.busyEpisodeIds,
    required this.authenticated,
    required this.onChanged,
  });

  final List<SeasonModel> seasons;
  final Set<String> busyEpisodeIds;
  final bool authenticated;
  final void Function(EpisodeModel, bool) onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle(title: 'فصل‌ها و قسمت‌ها', subtitle: 'هر قسمت مشاهده‌شده را علامت بزنید.'),
            if (seasons.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: EmptyView(message: 'اطلاعات فصل‌ها و قسمت‌ها در دسترس نیست.', icon: Icons.tv_off_outlined),
              )
            else
              for (final season in seasons)
                ExpansionTile(
                  initiallyExpanded: season.seasonNumber == 1,
                  leading: CircleAvatar(child: Text('${season.seasonNumber}')),
                  title: Text(season.title?.isNotEmpty == true ? season.title! : 'فصل ${season.seasonNumber}'),
                  subtitle: Text('${season.episodeCount} قسمت'),
                  children: [
                    for (final episode in season.episodes)
                      CheckboxListTile(
                        value: episode.watched,
                        onChanged: !authenticated || busyEpisodeIds.contains(episode.episodeId)
                            ? null
                            : (value) => onChanged(episode, value ?? false),
                        secondary: busyEpisodeIds.contains(episode.episodeId)
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                            : CircleAvatar(child: Text('${episode.episodeNumber}')),
                        title: Text('قسمت ${episode.episodeNumber}: ${episode.title}'),
                        subtitle: Text([
                          if (episode.releaseDate != null) formatDate(episode.releaseDate).split(' ').first,
                          if (episode.runtimeMinutes != null) minutesLabel(episode.runtimeMinutes),
                          if (episode.plot?.isNotEmpty == true) episode.plot!,
                        ].join(' • '), maxLines: 3, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                ),
          ],
        ),
      ),
    );
  }
}

class _RatingSection extends StatelessWidget {
  const _RatingSection({required this.media});
  final MediaDetail media;

  @override
  Widget build(BuildContext context) {
    final distribution = media.ratingDistribution;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('امتیازها', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 18,
              runSpacing: 10,
              children: [
                _Score(label: 'TMDB', value: media.providerRating?.toStringAsFixed(1) ?? '—', scale: 10, subtitle: media.providerVoteCount == null ? null : '${media.providerVoteCount} رأی'),
                _Score(label: 'کاربران Cine Track Simple', value: media.appRating?.toStringAsFixed(1) ?? '—', scale: 5, subtitle: '${distribution.total} رأی'),
              ],
            ),
            const SizedBox(height: 18),
            for (var star = 5; star >= 1; star--)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(width: 52, child: Text('$star ستاره')),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: ((distribution.percentages[star] ?? 0) / 100).clamp(0.0, 1.0).toDouble(),
                        minHeight: 10,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(width: 76, child: Text('${(distribution.percentages[star] ?? 0).toStringAsFixed(0)}٪ (${distribution.counts[star] ?? 0})')),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Score extends StatelessWidget {
  const _Score({required this.label, required this.value, required this.scale, this.subtitle});
  final String label;
  final String value;
  final int scale;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 42),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$value / $scale', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              Text(label),
              if (subtitle != null) Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      );
}

class _CommentsSection extends StatelessWidget {
  const _CommentsSection({
    required this.comments,
    required this.authenticated,
    required this.loading,
    required this.hasNext,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onReport,
    required this.onLoadMore,
  });

  final List<CommentModel> comments;
  final bool authenticated;
  final bool loading;
  final bool hasNext;
  final VoidCallback onAdd;
  final ValueChanged<CommentModel> onEdit;
  final ValueChanged<CommentModel> onDelete;
  final ValueChanged<CommentModel> onReport;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('نظر کاربران', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
                FilledButton.icon(
                  onPressed: authenticated ? onAdd : onAdd,
                  icon: const Icon(Icons.add_comment_outlined),
                  label: Text(authenticated ? 'ثبت نظر' : 'ورود و ثبت نظر'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (comments.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: EmptyView(message: 'هنوز نظری ثبت نشده است.', icon: Icons.mode_comment_outlined),
              )
            else
              for (final comment in comments)
                _CommentCard(
                  comment: comment,
                  onEdit: () => onEdit(comment),
                  onDelete: () => onDelete(comment),
                  onReport: () => onReport(comment),
                ),
            if (hasNext)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: FilledButton.tonal(
                    onPressed: loading ? null : onLoadMore,
                    child: loading
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('نظرهای بیشتر'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CommentCard extends StatefulWidget {
  const _CommentCard({
    required this.comment,
    required this.onEdit,
    required this.onDelete,
    required this.onReport,
  });

  final CommentModel comment;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onReport;

  @override
  State<_CommentCard> createState() => _CommentCardState();
}

class _CommentCardState extends State<_CommentCard> {
  bool _spoilerRevealed = false;

  @override
  Widget build(BuildContext context) {
    final comment = widget.comment;
    final hideText = comment.isSpoiler && !_spoilerRevealed;
    return Card.outlined(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SecureAvatar(
              url: comment.userAvatarUrl,
              fallbackText: firstCharacter(comment.username).toUpperCase(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(comment.username, style: const TextStyle(fontWeight: FontWeight.bold))),
                      if (comment.isSpoiler) const Chip(avatar: Icon(Icons.warning_amber_rounded, size: 16), label: Text('اسپویل')),
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') widget.onEdit();
                          if (value == 'delete') widget.onDelete();
                          if (value == 'report') widget.onReport();
                        },
                        itemBuilder: (_) => [
                          if (comment.ownComment) const PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                          if (comment.ownComment) const PopupMenuItem(value: 'delete', child: Text('حذف')),
                          if (!comment.ownComment) const PopupMenuItem(value: 'report', child: Text('گزارش')),
                        ],
                      ),
                    ],
                  ),
                  Text(formatDate(comment.createdAt), style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  if (hideText)
                    InkWell(
                      onTap: () => setState(() => _spoilerRevealed = true),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Column(
                          children: [
                            Icon(Icons.visibility_off_outlined),
                            SizedBox(height: 6),
                            Text('این نظر حاوی اسپویل است؛ برای نمایش ضربه بزنید.'),
                          ],
                        ),
                      ),
                    )
                  else
                    SelectableText(comment.text),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
