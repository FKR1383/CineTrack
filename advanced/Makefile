.PHONY: backend-install backend-test backend-run openapi tls deploy update smoke backup mobile-test mobile-run mobile-release
backend-install:
	cd backend && python -m pip install -e '.[dev]'
backend-test:
	cd backend && PYTHONPATH=. python -m pytest -q && python -m compileall -q app tests alembic
backend-run:
	cd backend && python -m uvicorn app.main:app --reload
openapi:
	python scripts/export_openapi.py
tls:
	./scripts/generate_tls.sh
deploy:
	sudo SERVER_IP=$${SERVER_IP:-31.57.118.82} ./scripts/deploy_native_ubuntu.sh
update:
	sudo ./scripts/update_native_backend.sh
smoke:
	./scripts/smoke_test.sh
backup:
	sudo ./scripts/backup.sh
mobile-test:
	cd mobile && flutter pub get && flutter analyze && flutter test
mobile-run:
	SERVER_IP=$${SERVER_IP:-31.57.118.82} ./scripts/run_flutter.sh
mobile-release:
	SERVER_IP=$${SERVER_IP:-31.57.118.82} ./scripts/build_android.sh
