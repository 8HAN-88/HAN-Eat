import importlib.util
from pathlib import Path


def _load():
    path = Path(__file__).resolve().parents[2] / "scripts" / "ensure_prod_env.py"
    spec = importlib.util.spec_from_file_location("ensure_prod_env", path)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_ensure_prod_env_replaces_default_secret(tmp_path):
    mod = _load()
    env = tmp_path / ".env"
    env.write_text(
        "APP_ENV=development\n"
        "DEBUG=true\n"
        "SKIP_GOOGLE_ID_TOKEN_VERIFICATION=true\n"
        "SECRET_KEY=dev-only-change-with-SECRET_KEY-env-in-production\n"
    )
    notes = mod.ensure_prod_env(env)
    text = env.read_text()
    assert "APP_ENV=production" in text
    assert "DEBUG=false" in text
    assert "SKIP_GOOGLE_ID_TOKEN_VERIFICATION=false" in text
    assert "dev-only-change-with-SECRET_KEY-env-in-production" not in text
    assert any("replaced" in note for note in notes)
    secret = next(
        line.split("=", 1)[1] for line in text.splitlines() if line.startswith("SECRET_KEY=")
    )
    assert len(secret) >= 32


def test_ensure_prod_env_keeps_real_secret(tmp_path):
    mod = _load()
    env = tmp_path / ".env"
    real = "prod-device-token-" + ("k" * 24)
    env.write_text(f"SECRET_KEY={real}\n")
    notes = mod.ensure_prod_env(env)
    assert f"SECRET_KEY={real}" in env.read_text()
    assert any("kept" in note for note in notes)
