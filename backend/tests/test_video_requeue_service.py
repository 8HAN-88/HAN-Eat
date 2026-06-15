"""Tests for video requeue / retranscode eligibility."""
from app.services.video_queue_service import VideoQueueService


class _RedisStub:
    def __init__(self):
        self.items = []

    def lpush(self, _key, value):
        self.items.append(value)


class _Vp:
    def __init__(self):
        self.id = 7
        self.upload_id = "u-1"
        self.file_key = "uploads/user_1/x.mp4"
        self.user_id = 1
        self.status = "completed"
        self.progress = 100.0
        self.error_message = "old"


class _Db:
    def __init__(self, vp):
        self.vp = vp
        self.commits = 0

    def commit(self):
        self.commits += 1

    def refresh(self, _obj):
        pass


def test_requeue_resets_status_and_pushes_redis(monkeypatch):
    vp = _Vp()
    db = _Db(vp)
    stub = _RedisStub()
    monkeypatch.setattr(
        "app.services.video_queue_service.redis_client",
        stub,
    )

    out = VideoQueueService.requeue_video_processing(db, vp)

    assert out.status == "pending"
    assert out.progress == 0.0
    assert out.error_message is None
    assert len(stub.items) == 1
    assert "u-1" in stub.items[0]
