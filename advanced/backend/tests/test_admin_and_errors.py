def test_rbac_and_standard_errors(client, auth_headers, admin_headers):
    forbidden = client.get("/api/v1/admin/stats", headers=auth_headers)
    assert forbidden.status_code == 403
    assert forbidden.json()["error"]["code"] == "admin_required"
    assert forbidden.json()["error"]["request_id"]

    stats = client.get("/api/v1/admin/stats", headers=admin_headers)
    assert stats.status_code == 200
    assert stats.json()["users_total"] >= 2

    admin_profile = client.get("/api/v1/users/me", headers=admin_headers)
    assert admin_profile.status_code == 200
    admin_id = admin_profile.json()["id"]

    disable_self = client.patch(
        f"/api/v1/admin/users/{admin_id}",
        headers=admin_headers,
        json={"is_active": False},
    )
    assert disable_self.status_code == 400
    assert disable_self.json()["error"]["code"] == "cannot_disable_self"

    demote_self = client.patch(
        f"/api/v1/admin/users/{admin_id}",
        headers=admin_headers,
        json={"role": "user"},
    )
    assert demote_self.status_code == 400
    assert demote_self.json()["error"]["code"] == "cannot_demote_self"

    invalid = client.put(
        "/api/v1/me/ratings/tmdb-movie-603",
        headers=auth_headers,
        json={"score": 9},
    )
    assert invalid.status_code == 422
    assert invalid.json()["error"]["code"] == "validation_error"

    missing = client.get("/api/v1/media/tmdb-movie-999999999")
    assert missing.status_code == 404
    assert missing.json()["error"]["message"]



def test_deleting_media_cache_preserves_user_data(client, auth_headers, admin_headers):
    # Ensure the media row exists, then attach user-owned data to it.
    assert client.get('/api/v1/media/tmdb-movie-603').status_code == 200
    rating = client.put(
        '/api/v1/me/ratings/tmdb-movie-603',
        headers=auth_headers,
        json={'score': 5},
    )
    assert rating.status_code == 200, rating.text
    comment = client.post(
        '/api/v1/media/tmdb-movie-603/comments',
        headers=auth_headers,
        json={'text': 'Keep this comment', 'is_spoiler': False},
    )
    assert comment.status_code == 201, comment.text

    cleared = client.delete('/api/v1/admin/media/tmdb-movie-603', headers=admin_headers)
    assert cleared.status_code == 200, cleared.text
    assert 'محفوظ' in cleared.json()['message']

    # The stable media record and all user-owned associations must survive.
    detail = client.get('/api/v1/media/tmdb-movie-603', headers=auth_headers)
    assert detail.status_code == 200
    assert detail.json()['user_state']['user_rating'] == 5
    comments = client.get('/api/v1/media/tmdb-movie-603/comments')
    assert comments.status_code == 200
    assert any(item['text'] == 'Keep this comment' for item in comments.json()['items'])
    library = client.get('/api/v1/me/library', headers=auth_headers)
    assert library.status_code == 200
