"""Тесты опросов в постах."""
import pytest

from app.services.post_poll_service import build_poll_body, enrich_body_poll


def test_build_poll_body_ok():
    body = build_poll_body("Что на ужин?", ["Паста", "Салат"])
    poll = body["poll"]
    assert poll["question"] == "Что на ужин?"
    assert len(poll["options"]) == 2
    assert poll["options"][0]["index"] == 0
    assert poll["is_closed"] is False


def test_build_poll_body_requires_question():
    with pytest.raises(ValueError, match="question"):
        build_poll_body("  ", ["A", "B"])


def test_build_poll_body_requires_two_options():
    with pytest.raises(ValueError, match="at least 2"):
        build_poll_body("Q?", ["only one"])


def test_enrich_body_poll_counts_and_percentages():
    body = {
        "poll": {
            "question": "Q?",
            "options": [
                {"index": 0, "text": "A"},
                {"index": 1, "text": "B"},
            ],
            "is_closed": False,
        }
    }
    enriched = enrich_body_poll(
        db=None,  # type: ignore[arg-type]
        post_id=1,
        body=body,
        viewer_user_id=None,
        vote_counts={0: 3, 1: 1},
        voted_index=None,
    )
    assert enriched is not None
    opts = enriched["poll"]["options"]
    assert opts[0]["votes"] == 3
    assert opts[1]["votes"] == 1
    assert opts[0]["percentage"] == 75.0
    assert opts[1]["percentage"] == 25.0


def test_update_poll_in_post_ok_without_votes():
    class _Post:
        type = "poll"
        id = 3
        body = {
            "poll": {
                "question": "Старое?",
                "options": [{"index": 0, "text": "A"}, {"index": 1, "text": "B"}],
                "is_closed": False,
            }
        }

    class _Db:
        def query(self, *_args, **_kwargs):
            return self

        def filter(self, *_args, **_kwargs):
            return self

        def scalar(self):
            return 0

    from app.services.post_poll_service import update_poll_in_post

    update_poll_in_post(_Db(), _Post(), "Новое?", ["X", "Y", "Z"])
    assert _Post.body["poll"]["question"] == "Новое?"
    assert len(_Post.body["poll"]["options"]) == 3
    assert _Post.body["poll"]["options"][2]["text"] == "Z"


def test_update_poll_in_post_rejects_when_votes_exist():
    class _Post:
        type = "poll"
        id = 2
        body = {"poll": {"question": "Q?", "options": [], "is_closed": False}}

    class _Db:
        def query(self, *_args, **_kwargs):
            return self

        def filter(self, *_args, **_kwargs):
            return self

        def scalar(self):
            return 3

    from app.services.post_poll_service import update_poll_in_post

    with pytest.raises(ValueError, match="первого голоса"):
        update_poll_in_post(_Db(), _Post(), "New?", ["A", "B"])


def test_update_poll_in_post_rejects_when_closed():
    class _Post:
        type = "poll"
        id = 1
        body = {"poll": {"question": "Q?", "options": [], "is_closed": True}}

    class _Db:
        def query(self, *_args, **_kwargs):
            return self

        def filter(self, *_args, **_kwargs):
            return self

        def scalar(self):
            return 0

    from app.services.post_poll_service import update_poll_in_post

    with pytest.raises(ValueError, match="закрыт"):
        update_poll_in_post(_Db(), _Post(), "New?", ["A", "B"])


def test_enrich_body_poll_includes_voted_index():
    body = build_poll_body("Q?", ["A", "B"])
    enriched = enrich_body_poll(
        db=None,  # type: ignore[arg-type]
        post_id=5,
        body=body,
        viewer_user_id=42,
        vote_counts={0: 1},
        voted_index=0,
    )
    assert enriched is not None
    assert enriched["poll"]["voted_option_index"] == 0
