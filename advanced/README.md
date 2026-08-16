# Cine Track Advanced — Flutter + FastAPI + TMDB

نسخهٔ کامل مدل پیشرفتهٔ پروژهٔ «مدیریت و دنبال‌کردن فیلم و سریال» با فرانت‌اند Flutter/Dart و بک‌اند واقعی FastAPI.

> تصمیم پروژه: منبع اطلاعات فیلم/سریال در این نسخه **TMDB API** است. صورت پروژهٔ اولیه نام IMDb را ذکر می‌کند؛ بنابراین این یک جایگزینی آگاهانهٔ provider است، نه ادعای استفاده از IMDb. معماری پیشرفته، دیتابیس کاربران، احراز هویت، لیست‌ها، امتیازها، نظرها، فصل/قسمت و سایر نیازمندی‌ها همان مدل پیشرفته هستند.

```text
Flutter Android (Persian RTL)
        |
        | HTTPS + certificate pinning
        v
Nginx -> FastAPI -> PostgreSQL
                 -> Redis
                 -> TMDB API
                 -> TMDB image CDN (server-side poster proxy/cache only)
```

Flutter هیچ credential مربوط به TMDB و هیچ درخواست مستقیم به `api.themoviedb.org` یا `image.tmdb.org` ندارد.

## قابلیت‌های اصلی

- جست‌وجوی واقعی و آنلاین TMDB بر اساس عنوان، نوع، سال، ژانر، بازیگر و کارگردان.
- صفحهٔ Home واقعی: فیلم‌های محبوب، سریال‌های محبوب، آثار جدید، آثار برتر و پیشنهادها.
- جزئیات فیلم/سریال: عنوان، عنوان اصلی، داستان، ژانر، سال/تاریخ، runtime، کشور، عوامل، بازیگران، rating provider و rating کاربران Cine Track.
- فصل‌ها و قسمت‌های واقعی TMDB، علامت‌گذاری قسمت‌های دیده‌شده، تعداد باقی‌مانده و درصد پیشرفت.
- posterهای واقعی TMDB با **proxy/cache سمت backend**؛ تصاویر به WebP بهینه و از origin خود Cine Track سرو می‌شوند.
- Guest / User / Admin.
- ثبت‌نام، ورود، logout امن، نشست ۱روزه/۳۰روزه، refresh-token rotation و بازیابی رمز.
- PostgreSQL برای کاربران، media cache، watch status، episodes, ratings, comments, favorites, custom lists, reports و audit log.
- Redis برای cacheهای کوتاه‌مدت و fallback؛ PostgreSQL cache پایدار.
- امتیاز ۱ تا ۵، توزیع درصدی، نظر و spoiler، گزارش نظر، favorites و personal lists.
- آمار و history کاربر.
- Admin panel برای کاربران، گزارش‌ها، نظرات، cache و آمار سامانه.
- HTTPS، CA خصوصی، certificate pinning، Argon2، JWT، RBAC، rate limiting، validation و idempotency.
- Swagger/OpenAPI.
- استقرار native روی Ubuntu بدون Docker؛ مناسب VPS یک‌گیگابایتی.

## ساختار

```text
backend/                     FastAPI + SQLAlchemy + Alembic
mobile/                      Flutter/Dart Android app
scripts/                     deploy/update/TMDB/TLS/build/backup tools
docs/                        architecture, audit, API, deployment, testing
deploy/                      TLS templates/runtime material location
```

## نکتهٔ امنیتی TMDB

**هیچ TMDB token یا API key واقعی داخل این ZIP قرار ندارد.** credential فقط باید روی سرور در `/etc/timetv/timetv.env` ذخیره شود. اگر credential را در چت، screenshot یا repository عمومی نمایش داده‌اید، قبل از production آن را در TMDB rotate کنید.

تنظیم امن روی سرور:

```bash
sudo ./scripts/configure_tmdb.sh /etc/timetv/timetv.env
```

اسکریپت token را با input مخفی دریافت می‌کند و آن را چاپ نمی‌کند.

## به‌روزرسانی سرور فعلی شما

اگر native stack قبلی در `/opt/timetv` و `/etc/timetv/timetv.env` فعال است:

```bash
cd /root/Cine Track-TMDB-Advanced
sudo ./scripts/configure_tmdb.sh /etc/timetv/timetv.env
sudo ./scripts/update_native_backend.sh
```

سپس:

```bash
systemctl status timetv-backend nginx postgresql redis-server --no-pager
curl http://127.0.0.1:8000/ready
journalctl -u timetv-backend -f
```

تست مستقیم TMDB:

```bash
cd /opt/timetv/backend
set -a
source /etc/timetv/timetv.env
set +a
PYTHONPATH=/opt/timetv/backend /opt/timetv/venv/bin/python \
  /root/Cine Track-TMDB-Advanced/scripts/check_tmdb_live.py Interstellar
```

خروجی موفق با `TMDB LIVE OK` شروع می‌شود.

## نصب از صفر روی Ubuntu

```bash
cd /root/Cine Track-TMDB-Advanced
SERVER_IP=31.57.118.82 ./scripts/bootstrap_env.sh
./scripts/configure_tmdb.sh .env
sudo SERVER_IP=31.57.118.82 ./scripts/deploy_native_ubuntu.sh
```

بعد از deploy:

```text
API      https://31.57.118.82/api/v1
Swagger  https://31.57.118.82/docs
Ready    https://31.57.118.82/ready
```

## اجرای backend برای توسعهٔ محلی

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -U pip
pip install -e '.[dev]'
cp .env.example .env
# TMDB_READ_ACCESS_TOKEN را فقط در فایل محلی .env وارد کنید
python -m alembic upgrade head
python -m app.seed
uvicorn app.main:app --reload
```

Swagger: `http://127.0.0.1:8000/docs`

تست‌ها:

```bash
cd backend
PYTHONPATH=. pytest -q
```

## اجرای Flutter روی گوشی/Emulator با سرور اصلی

ابتدا fingerprint همان certificate فعال سرور باید در `deploy/tls/fingerprint.sha256` روی سیستم توسعه وجود داشته باشد.

```bash
cd mobile
PIN="$(tr -d '[:space:]' < ../deploy/tls/fingerprint.sha256)"

env -u PUB_HOSTED_URL -u FLUTTER_STORAGE_BASE_URL \
flutter run \
  --dart-define="API_BASE_URL=https://31.57.118.82/api/v1" \
  --dart-define="CERT_SHA256=$PIN"
```

برای APK Release:

```bash
cd mobile
PIN="$(tr -d '[:space:]' < ../deploy/tls/fingerprint.sha256)"

env -u PUB_HOSTED_URL -u FLUTTER_STORAGE_BASE_URL \
flutter build apk --release \
  --dart-define="API_BASE_URL=https://31.57.118.82/api/v1" \
  --dart-define="CERT_SHA256=$PIN"
```

خروجی:

```text
mobile/build/app/outputs/flutter-apk/app-release.apk
```

یا از ریشهٔ پروژه برای build امضاشده APK/AAB:

```bash
./scripts/generate_android_keystore.sh   # فقط بار اول
SERVER_IP=31.57.118.82 ./scripts/build_android.sh
```

## Poster pipeline

```text
TMDB poster_path
    -> backend stores private upstream URL
    -> GET /api/v1/media/{media_id}/poster
    -> server downloads only on cache miss
    -> validates TMDB image origin/content/size
    -> resize + WebP
    -> /var/lib/timetv/uploads/posters
    -> Flutter fetches through pinned API connection
```

بنابراین مشکل قبلی `placehold.co` حذف شده است.

## مستندات

- `docs/TMDB_SETUP.md`
- `docs/ADVANCED_MODEL_AUDIT.md`
- `docs/ADVANCED_MODEL_FEATURE_CHECKLIST.md`
- `docs/REQUIREMENTS_TRACEABILITY.md`
- `docs/ARCHITECTURE.md`
- `docs/DATABASE.md`
- `docs/API_CONNECTION.md`
- `docs/DEPLOYMENT_UBUNTU.md`
- `docs/SECURITY.md`
- `docs/TESTING.md`
- `docs/BUILD_VALIDATION.txt`
- `docs/OPERATIONS.md`
- `docs/openapi.json`
- `docs/project-requirements-fa.pdf`

## TMDB attribution

اپ شامل notice زیر در صفحهٔ ورود و پروفایل است:

> This product uses the TMDB API but is not endorsed or certified by TMDB.

برای انتشار عمومی، شرایط و branding فعلی TMDB را نیز بررسی کنید.


## Final login, biometric and cache behavior

- Every successful login is remembered for **30 days**.
- Biometric unlock is optional and can be enabled at login or later from Profile. It protects a still-valid remembered session; secure logout removes that session and disables biometric unlock.
- Android biometric authentication uses the Flutter `local_auth` plugin and requires an enrolled fingerprint/face on the device.
- Admin **cache cleanup** invalidates provider/poster cache only; it no longer deletes the Media row, so ratings, comments, favorites, lists and viewing history are preserved.
- App display name: **Cine Track** with the blue/black Cine Track branding.
