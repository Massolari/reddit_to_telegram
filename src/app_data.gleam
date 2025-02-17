import dotenv_gleam
import envoy
import gleam/result

pub type AppData {
  AppData(
    username: String,
    password: String,
    client_id: String,
    client_secret: String,
    telegram_token: String,
  )
}

pub fn get() -> Result(AppData, String) {
  dotenv_gleam.config()

  use username <- result.try(get_env("REDDIT_USERNAME"))
  use password <- result.try(get_env("REDDIT_PASSWORD"))
  use client_id <- result.try(get_env("REDDIT_CLIENT_ID"))
  use client_secret <- result.try(get_env("REDDIT_CLIENT_SECRET"))
  use telegram_token <- result.map(get_env("TELEGRAM_TOKEN"))

  AppData(
    username: username,
    password: password,
    client_id: client_id,
    client_secret: client_secret,
    telegram_token: telegram_token,
  )
}

fn get_env(key: String) -> Result(String, String) {
  key
  |> envoy.get
  |> result.map_error(fn(_) { "Missing " <> key <> " environment variable" })
}
