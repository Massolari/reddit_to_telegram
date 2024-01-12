import gleam/dynamic
import simplifile
import gleam/json
import gleam/result

pub type Bridge {
  Bridge(subreddit: String, telegram_channel: String)
}

pub fn get() -> Result(List(Bridge), String) {
  simplifile.read("./bridges.json")
  |> result.map_error(fn(_) { "File bridges.json not found" })
  |> result.try(bridges_decoder)
}

fn bridges_decoder(json: String) -> Result(List(Bridge), String) {
  json.decode(from: json, using: dynamic.list(of: bridge_decoder()))
  |> result.map_error(fn(_) { "Couldn't decode bridges" })
}

fn bridge_decoder() -> dynamic.Decoder(Bridge) {
  dynamic.decode2(
    Bridge,
    dynamic.field("subreddit", dynamic.string),
    dynamic.field("telegram_channel", dynamic.string),
  )
}
