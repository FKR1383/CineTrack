def test_register_login_refresh_logout_and_profile(client):
    register = client.post(
        "/api/v1/auth/register-json",
        json={
            "first_name": "Ali",
            "last_name": "Karimi",
            "username": "ali.k",
            "email": "Ali@example.com",
            "password": "Password123",
            "bio": "Hello",
        },
    )
    assert register.status_code == 201, register.text
    body = register.json()
    assert body["user"]["email"] == "ali@example.com"

    duplicate = client.post(
        "/api/v1/auth/register-json",
        json={
            "first_name": "Other",
            "last_name": "User",
            "username": "ali.k",
            "email": "other@example.com",
            "password": "Password123",
        },
    )
    assert duplicate.status_code == 409
    assert duplicate.json()["error"]["code"] == "duplicate_username"

    login = client.post(
        "/api/v1/auth/login",
        json={"email": "ali@example.com", "password": "Password123", "remember_me": False},
    )
    assert login.status_code == 200
    refreshed = client.post(
        "/api/v1/auth/refresh", json={"refresh_token": login.json()["refresh_token"]}
    )
    assert refreshed.status_code == 200, refreshed.text

    headers = {"Authorization": f"Bearer {refreshed.json()['access_token']}"}
    profile = client.patch(
        "/api/v1/users/me",
        headers=headers,
        json={"first_name": "Alireza", "bio": "Updated"},
    )
    assert profile.status_code == 200
    assert profile.json()["first_name"] == "Alireza"

    logout = client.post(
        "/api/v1/auth/logout", json={"refresh_token": refreshed.json()["refresh_token"]}
    )
    assert logout.status_code == 200
    rejected = client.post(
        "/api/v1/auth/refresh", json={"refresh_token": refreshed.json()["refresh_token"]}
    )
    assert rejected.status_code == 401


def test_password_reset(client):
    client.post(
        "/api/v1/auth/register-json",
        json={
            "first_name": "Neda",
            "last_name": "R",
            "username": "neda",
            "email": "neda@example.com",
            "password": "Before123",
        },
    )
    forgot = client.post(
        "/api/v1/auth/password/forgot", json={"email": "neda@example.com"}
    )
    assert forgot.status_code == 200
    token = forgot.json()["debug_reset_token"]
    reset = client.post(
        "/api/v1/auth/password/reset",
        json={"token": token, "new_password": "After1234"},
    )
    assert reset.status_code == 200
    login = client.post(
        "/api/v1/auth/login",
        json={"email": "neda@example.com", "password": "After1234", "remember_me": True},
    )
    assert login.status_code == 200


def test_server_rejects_whitespace_only_required_text(client, auth_headers):
    register = client.post(
        '/api/v1/auth/register-json',
        json={
            'first_name': '   ',
            'last_name': 'User',
            'username': 'space-user',
            'email': 'space@example.com',
            'password': 'Password123',
        },
    )
    assert register.status_code == 422
    assert register.json()['error']['code'] == 'validation_error'

    custom_list = client.post(
        '/api/v1/me/lists',
        headers=auth_headers,
        json={'name': '   ', 'description': 'ignored'},
    )
    assert custom_list.status_code == 422

    comment = client.post(
        '/api/v1/media/tmdb-movie-603/comments',
        headers=auth_headers,
        json={'text': '   ', 'is_spoiler': False},
    )
    assert comment.status_code == 422


def test_login_session_is_thirty_days_even_without_remember_flag(client):
    from datetime import datetime, timezone

    client.post(
        "/api/v1/auth/register-json",
        json={
            "first_name": "Thirty",
            "last_name": "Days",
            "username": "thirtydays",
            "email": "thirty@example.com",
            "password": "Password123",
        },
    )
    response = client.post(
        "/api/v1/auth/login",
        json={"email": "thirty@example.com", "password": "Password123", "remember_me": False},
    )
    assert response.status_code == 200, response.text
    expiry = datetime.fromisoformat(response.json()["refresh_token_expires_at"].replace("Z", "+00:00"))
    remaining = expiry - datetime.now(timezone.utc)
    assert remaining.total_seconds() > 29 * 24 * 3600
