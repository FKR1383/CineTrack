from fastapi import APIRouter

from app.api.v1 import admin, auth, library, lists, media, users

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(users.router)
api_router.include_router(media.router)
api_router.include_router(library.router)
api_router.include_router(lists.router)
api_router.include_router(admin.router)
