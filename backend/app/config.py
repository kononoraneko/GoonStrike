from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "GoonStrike Backend"
    database_url: str = "postgresql+psycopg://goonstrike:goonstrike@localhost:5432/goonstrike"
    enable_dev_grants: bool = True
    auth_secret: str = "dev-change-me"
    access_token_minutes: int = 15
    refresh_token_days: int = 14
    registry_auth_required: bool = True
    registry_challenge_ttl_sec: int = 30
    registry_nonce_ttl_sec: int = 120
    registry_bootstrap_server_id: str = ""
    registry_bootstrap_key_id: str = ""
    registry_bootstrap_secret: str = ""
    registry_admin_token: str = ""
    admin_panel_allowed_origins: str = "http://127.0.0.1:5173,http://localhost:5173"

    model_config = SettingsConfigDict(env_file=".env", env_prefix="GOONSTRIKE_")


settings = Settings()
