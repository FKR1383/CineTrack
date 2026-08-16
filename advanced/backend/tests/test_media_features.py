import uuid


def test_guest_home_search_and_details(client):
    home = client.get("/api/v1/media/home")
    assert home.status_code == 200, home.text
    assert home.json()["popular_movies"]
    assert home.json()["popular_series"]

    search = client.get("/api/v1/media/search", params={"q": "Matrix"})
    assert search.status_code == 200, search.text
    assert search.json()["items"][0]["media_id"] == "tmdb-movie-603"

    filtered = client.get(
        "/api/v1/media/search", params={"director": "Christopher Nolan", "genre": "Action"}
    )
    assert filtered.status_code == 200
    assert any(item["title"] == "Inception" for item in filtered.json()["items"])

    detail = client.get("/api/v1/media/tmdb-movie-27205")
    assert detail.status_code == 200
    assert detail.json()["directors"] == ["Christopher Nolan"]
    assert detail.json()["rating_distribution"]["total"] == 0


def test_library_episode_progress_rating_and_stats(client, auth_headers):
    status = client.put(
        "/api/v1/me/library/tmdb-series-1396",
        headers={**auth_headers, "Idempotency-Key": str(uuid.uuid4())},
        json={"status": "watching"},
    )
    assert status.status_code == 200, status.text

    seasons = client.get("/api/v1/media/tmdb-series-1396/seasons", headers=auth_headers)
    assert seasons.status_code == 200, seasons.text
    episode_id = seasons.json()[0]["episodes"][0]["episode_id"]
    mark = client.put(
        f"/api/v1/me/episodes/{episode_id}",
        headers={**auth_headers, "Idempotency-Key": "episode-1"},
        json={"watched": True},
    )
    assert mark.status_code == 200
    assert mark.json()["watched_episodes"] == 1
    assert mark.json()["remaining_episodes"] == 9
    assert mark.json()["progress_color"] == "yellow"

    duplicate = client.put(
        f"/api/v1/me/episodes/{episode_id}",
        headers={**auth_headers, "Idempotency-Key": "episode-1"},
        json={"watched": True},
    )
    assert duplicate.status_code == 200
    assert duplicate.json()["watched_episodes"] == 1

    rating = client.put(
        "/api/v1/me/ratings/tmdb-series-1396",
        headers={**auth_headers, "Idempotency-Key": "rate-one"},
        json={"score": 5},
    )
    assert rating.status_code == 200
    assert rating.json()["percentages"]["5"] == 100.0
    edited = client.put(
        "/api/v1/me/ratings/tmdb-series-1396",
        headers={**auth_headers, "Idempotency-Key": "rate-two"},
        json={"score": 4},
    )
    assert edited.status_code == 200
    assert edited.json()["counts"]["4"] == 1
    assert edited.json()["counts"]["5"] == 0

    favorite = client.put("/api/v1/me/favorites/tmdb-series-1396", headers=auth_headers)
    assert favorite.status_code == 200
    favorites = client.get(
        "/api/v1/me/library", headers=auth_headers, params={"watch_status": "favorite"}
    )
    assert favorites.status_code == 200
    assert favorites.json()["pagination"]["total"] == 1

    stats = client.get("/api/v1/users/me/stats", headers=auth_headers)
    assert stats.status_code == 200
    assert stats.json()["watched_episodes"] == 1
    assert stats.json()["favorites_count"] == 1
    assert stats.json()["average_user_rating"] == 4.0

    activity = client.get("/api/v1/users/me/activity", headers=auth_headers)
    assert activity.status_code == 200
    assert "episode" in {item["kind"] for item in activity.json()["items"]}


def test_spoiler_comments_lists_and_reports(client, auth_headers, admin_headers):
    comment = client.post(
        "/api/v1/media/tmdb-movie-603/comments",
        headers={**auth_headers, "Idempotency-Key": "comment-one"},
        json={"text": "A spoiler-aware comment", "is_spoiler": True},
    )
    assert comment.status_code == 201, comment.text
    comment_id = comment.json()["id"]
    listing = client.get("/api/v1/media/tmdb-movie-603/comments", headers=auth_headers)
    assert listing.status_code == 200
    assert listing.json()["items"][0]["is_spoiler"] is True

    report = client.post(
        f"/api/v1/comments/{comment_id}/reports",
        headers=auth_headers,
        json={"reason": "Inappropriate"},
    )
    assert report.status_code == 201
    reports = client.get("/api/v1/admin/reports", headers=admin_headers)
    assert reports.status_code == 200
    assert reports.json()[0]["comment_id"] == comment_id

    remove = client.delete(f"/api/v1/admin/comments/{comment_id}", headers=admin_headers)
    assert remove.status_code == 200

    created = client.post(
        "/api/v1/me/lists",
        headers=auth_headers,
        json={"name": "Best Action", "description": "My picks", "is_public": False},
    )
    assert created.status_code == 201
    list_id = created.json()["id"]
    add = client.post(
        f"/api/v1/me/lists/{list_id}/items",
        headers=auth_headers,
        json={"media_id": "tmdb-movie-603"},
    )
    assert add.status_code == 201
    detail = client.get(f"/api/v1/me/lists/{list_id}", headers=auth_headers)
    assert detail.status_code == 200
    assert detail.json()["items"][0]["title"] == "The Matrix"

    activity = client.get("/api/v1/users/me/activity", headers=auth_headers)
    assert activity.status_code == 200
    assert "custom_list" in {item["kind"] for item in activity.json()["items"]}


def test_all_progress_color_states(client, auth_headers):
    initial = client.get('/api/v1/media/tmdb-series-71912', headers=auth_headers)
    assert initial.status_code == 200
    assert initial.json()['user_state']['progress_color'] == 'black'

    paused_empty = client.put(
        '/api/v1/me/library/tmdb-series-71912',
        headers=auth_headers,
        json={'status': 'paused'},
    )
    assert paused_empty.status_code == 200
    assert paused_empty.json()['progress_color'] == 'red'

    seasons = client.get('/api/v1/media/tmdb-series-71912/seasons', headers=auth_headers)
    episode_id = seasons.json()[0]['episodes'][0]['episode_id']
    client.put(
        f'/api/v1/me/episodes/{episode_id}',
        headers=auth_headers,
        json={'watched': True},
    )
    paused = client.put(
        '/api/v1/me/library/tmdb-series-71912',
        headers=auth_headers,
        json={'status': 'paused'},
    )
    assert paused.status_code == 200
    assert paused.json()['progress_color'] == 'red'

    ongoing_complete = client.put(
        '/api/v1/me/library/tmdb-series-71912',
        headers=auth_headers,
        json={'status': 'completed'},
    )
    assert ongoing_complete.status_code == 200
    assert ongoing_complete.json()['progress_percent'] == 100.0
    assert ongoing_complete.json()['progress_color'] == 'green'

    all_watched = client.get('/api/v1/media/tmdb-series-71912/seasons', headers=auth_headers)
    assert all(
        episode['watched']
        for season in all_watched.json()
        for episode in season['episodes']
    )

    reopened = client.put(
        f'/api/v1/me/episodes/{episode_id}',
        headers=auth_headers,
        json={'watched': False},
    )
    assert reopened.status_code == 200
    assert reopened.json()['remaining_episodes'] == 1
    assert reopened.json()['progress_color'] == 'yellow'
    reopened_detail = client.get('/api/v1/media/tmdb-series-71912', headers=auth_headers)
    assert reopened_detail.json()['user_state']['watch_status'] == 'watching'

    recompleted = client.put(
        '/api/v1/me/library/tmdb-series-71912',
        headers=auth_headers,
        json={'status': 'completed'},
    )
    assert recompleted.json()['progress_percent'] == 100.0
    assert recompleted.json()['progress_color'] == 'green'

    ended_complete = client.put(
        '/api/v1/me/library/tmdb-series-1396',
        headers=auth_headers,
        json={'status': 'completed'},
    )
    assert ended_complete.status_code == 200
    assert ended_complete.json()['progress_percent'] == 100.0
    assert ended_complete.json()['progress_color'] == 'purple'


def test_search_calls_provider_on_every_request(client, fake_tmdb, monkeypatch):
    from app.services import media as media_service

    calls = {"count": 0}
    original = fake_tmdb.search

    def counted_search(**kwargs):
        calls["count"] += 1
        return original(**kwargs)

    fake_tmdb.search = counted_search
    monkeypatch.setattr(media_service, "get_media_provider", lambda: fake_tmdb)
    first = client.get("/api/v1/media/search", params={"q": "Matrix"})
    second = client.get("/api/v1/media/search", params={"q": "Matrix"})
    assert first.status_code == 200
    assert second.status_code == 200
    assert calls["count"] == 2


def test_client_facing_poster_url_is_same_origin_backend_route(client):
    detail = client.get("/api/v1/media/tmdb-movie-603")
    assert detail.status_code == 200
    assert detail.json()["poster_url"] == "/api/v1/media/tmdb-movie-603/poster"
