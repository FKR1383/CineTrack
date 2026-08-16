import 'package:flutter_test/flutter_test.dart';
import 'package:cinetrack_advanced/features/shared/models.dart';

void main() {
  test('media detail parses advanced fields and user progress', () {
    final detail = MediaDetail.fromJson({
      'media_id': 'tmdb-series-1396',
      'media_type': 'series',
      'title': 'Sample',
      'genres': ['Drama'],
      'rating_count': 2,
      'season_count': 2,
      'episode_count': 20,
      'countries': ['IR'],
      'directors': ['Director'],
      'cast': ['Actor'],
      'rating_distribution': {
        'total': 2,
        'percentages': {'1': 0, '2': 0, '3': 0, '4': 50, '5': 50},
        'counts': {'1': 0, '2': 0, '3': 0, '4': 1, '5': 1},
      },
      'user_state': {
        'watch_status': 'watching',
        'is_favorite': true,
        'user_rating': 5,
        'watched_episodes': 10,
        'remaining_episodes': 10,
        'progress_percent': 50,
        'progress_color': 'yellow',
        'progress_hex': '#FBC02D',
      },
    });

    expect(detail.mediaId, 'tmdb-series-1396');
    expect(detail.isSeries, isTrue);
    expect(detail.episodeCount, 20);
    expect(detail.userState?.progressPercent, 50);
    expect(detail.ratingDistribution.percentages[5], 50);
  });

  test('paginated response parses metadata', () {
    final page = PageResult<MediaSummary>.fromJson({
      'items': [
        {
          'media_id': 'tmdb-movie-603',
          'media_type': 'movie',
          'title': 'Movie',
          'genres': <String>[],
          'rating_count': 0,
        }
      ],
      'pagination': {
        'page': 1,
        'page_size': 20,
        'total': 21,
        'total_pages': 2,
        'has_next': true,
      },
    }, MediaSummary.fromJson);

    expect(page.items.single.mediaId, 'tmdb-movie-603');
    expect(page.items.single.title, 'Movie');
    expect(page.hasNext, isTrue);
    expect(page.totalPages, 2);
  });
}
