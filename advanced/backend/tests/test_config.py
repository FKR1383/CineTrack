from app.config import Settings


def test_comma_separated_list_environment_values(monkeypatch):
    monkeypatch.setenv('JWT_SECRET', 'x' * 40)
    monkeypatch.setenv('CORS_ORIGINS', 'https://31.57.118.82,https://example.test')
    monkeypatch.setenv('ALLOWED_IMAGE_TYPES', 'image/jpeg,image/png,image/webp')

    settings = Settings(_env_file=None)

    assert settings.cors_origins == [
        'https://31.57.118.82',
        'https://example.test',
    ]
    assert settings.allowed_image_types == [
        'image/jpeg',
        'image/png',
        'image/webp',
    ]
