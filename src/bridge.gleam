import gleam/dynamic
import simplifile
import gleam/json
import gleam/result
import gleam/option
import reddit

pub type Bridge {
  Bridge(
    subreddit: String,
    reddit_sort: reddit.Sort,
    telegram_channel: String,
    minimum_upvotes: Int,
  )
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
  dynamic.decode4(
    Bridge,
    dynamic.field("subreddit", dynamic.string),
    reddit_sort_decoder(),
    dynamic.field("telegram_channel", dynamic.string),
    minimum_upvotes_decoder(),
  )
}

fn reddit_sort_decoder() -> dynamic.Decoder(reddit.Sort) {
  fn(json) {
    json
    |> dynamic.optional_field("reddit_sort", fn(dynamic_sort) {
      dynamic_sort
      |> dynamic.string
      |> result.try(fn(sort) {
        case sort {
          "hot" -> Ok(reddit.Hot)
          "new" -> Ok(reddit.New)
          "top" -> Ok(reddit.Top)
          "rising" -> Ok(reddit.Rising)
          _ -> Error([])
        }
      })
    })
    |> result.map(option.unwrap(_, reddit.Hot))
  }
}

fn minimum_upvotes_decoder() -> dynamic.Decoder(Int) {
  fn(json) {
    json
    |> dynamic.field("minimum_upvotes", dynamic.int)
    |> result.unwrap(10)
    |> Ok
  }
}
