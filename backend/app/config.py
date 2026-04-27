from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "GoonStrike Backend"
    database_url: str = "postgresql+psycopg://goonstrike:goonstrike@localhost:5432/goonstrike"

    model_config = SettingsConfigDict(env_file=".env", env_prefix="GOONSTRIKE_")


settings = Settings()
