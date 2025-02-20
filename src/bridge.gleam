import gleam/dynamic/decode
import gleam/json
import gleam/result
import reddit
import simplifile

pub type Bridge {
  Bridge(
    subreddit: String,
    reddit_sort: reddit.Sort,
    telegram_channel: String,
    minimum_upvotes: Int,
    flair_include: List(String),
    flair_exclude: List(String),
  )
}

pub type Error {
  ReadFileError(simplifile.FileError)
  DecodeError(json.DecodeError)
}

pub fn get() -> Result(List(Bridge), Error) {
  use file <- result.try(
    simplifile.read("./bridges.json")
    |> result.map_error(fn(error) { ReadFileError(error) }),
  )

  file
  |> json.parse(bridges_decoder())
  |> result.map_error(fn(e) { DecodeError(e) })
}

@internal
pub fn bridges_decoder() -> decode.Decoder(List(Bridge)) {
  decode.list(bridge_decoder())
}

@internal
pub fn bridge_decoder() -> decode.Decoder(Bridge) {
  use subreddit <- decode.field("subreddit", decode.string)
  use reddit_sort <- decode.optional_field(
    "reddit_sort",
    reddit.Hot,
    reddit_sort_decoder(),
  )
  use telegram_channel <- decode.field("telegram_channel", decode.string)
  use minimum_upvotes <- decode.optional_field(
    "minimum_upvotes",
    10,
    decode.int,
  )
  use flair_include <- decode.optional_field(
    "flair_include",
    [],
    decode.list(decode.string),
  )
  use flair_exclude <- decode.optional_field(
    "flair_exclude",
    [],
    decode.list(decode.string),
  )
  decode.success(Bridge(
    subreddit:,
    reddit_sort:,
    telegram_channel:,
    minimum_upvotes:,
    flair_include:,
    flair_exclude:,
  ))
}

fn reddit_sort_decoder() -> decode.Decoder(reddit.Sort) {
  decode.string
  |> decode.then(fn(sort) {
    case sort {
      "hot" -> decode.success(reddit.Hot)
      "new" -> decode.success(reddit.New)
      "top" -> decode.success(reddit.Top)
      "rising" -> decode.success(reddit.Rising)
      _ -> decode.failure(reddit.Hot, "Invalid reddit sort: " <> sort)
    }
  })
}
