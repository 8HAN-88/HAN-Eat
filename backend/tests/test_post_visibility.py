"""Post visibility: public / followers / private."""
from app.services.post_visibility import can_view_post_fields, search_visibility_clause
from app.models.user import User


def test_public_post_is_visible_without_login():
    assert can_view_post_fields(
        None, visibility="public", author_id=1, viewer=None
    )


def test_private_post_only_author():
    author = User(id=3, email="a@t.test", password_hash="h", name="A")
    other = User(id=4, email="b@t.test", password_hash="h", name="B")
    assert can_view_post_fields(
        None, visibility="private", author_id=3, viewer=author
    )
    assert not can_view_post_fields(
        None, visibility="private", author_id=3, viewer=other
    )
    assert not can_view_post_fields(
        None, visibility="private", author_id=3, viewer=None
    )


def test_followers_post_hidden_from_anonymous():
    assert not can_view_post_fields(
        None, visibility="followers", author_id=1, viewer=None
    )


def test_search_clause_anonymous_is_public_only():
    clause = search_visibility_clause(None)
    assert clause is not None


def test_private_profile_locked_for_stranger():
    from app.services.post_visibility import profile_locked_for_viewer

    owner = User(id=8, email="o@t.test", password_hash="h", name="O", is_private=True)
    stranger = User(id=9, email="s@t.test", password_hash="h", name="S")
    assert profile_locked_for_viewer(None, owner, owner) is False
    assert profile_locked_for_viewer(None, owner, None) is True
    assert profile_locked_for_viewer(None, owner, stranger) is True
    public = User(id=10, email="p@t.test", password_hash="h", name="P", is_private=False)
    assert profile_locked_for_viewer(None, public, stranger) is False
