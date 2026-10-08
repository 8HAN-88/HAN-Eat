"""Production must refuse a default JWT secret / debug / skip-Google."""
from app.core import production_startup as prod


def test_non_production_has_no_issues(monkeypatch):
    monkeypatch.setattr(prod.settings, "APP_ENV", "development")
    assert prod.collect_production_issues() == []
    assert prod.collect_fatal_production_issues() == []
    prod.enforce_production_readiness()


def test_default_secret_is_fatal_in_production(monkeypatch):
    monkeypatch.setattr(prod.settings, "APP_ENV", "production")
    monkeypatch.setattr(prod.settings, "DEBUG", False)
    monkeypatch.setattr(
        prod.settings,
        "SECRET_KEY",
        "dev-only-change-with-SECRET_KEY-env-in-production",
    )
    monkeypatch.setattr(prod.settings, "SKIP_GOOGLE_ID_TOKEN_VERIFICATION", False)
    fatal = prod.collect_fatal_production_issues()
    assert any("SECRET_KEY" in msg for msg in fatal)
    try:
        prod.enforce_production_readiness()
        raise AssertionError("expected RuntimeError")
    except RuntimeError as exc:
        assert "SECRET_KEY" in str(exc)


def test_debug_and_skip_google_are_fatal(monkeypatch):
    monkeypatch.setattr(prod.settings, "APP_ENV", "production")
    monkeypatch.setattr(prod.settings, "DEBUG", True)
    monkeypatch.setattr(prod.settings, "SECRET_KEY", "x" * 40)
    monkeypatch.setattr(prod.settings, "SKIP_GOOGLE_ID_TOKEN_VERIFICATION", True)
    fatal = prod.collect_fatal_production_issues()
    assert any("DEBUG" in msg for msg in fatal)
    assert any("SKIP_GOOGLE" in msg for msg in fatal)
