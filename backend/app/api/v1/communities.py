"""
API endpoints для сообществ
"""
from fastapi import APIRouter

router = APIRouter()


@router.get("/{community_id}")
async def get_community(community_id: int):
    """Получить информацию о сообществе"""
    # TODO: реализовать
    return {"id": community_id, "message": "Not implemented yet"}

