import app_data.{type AppData}
import gleam/bit_array
import gleam/bool
import gleam/bytes_tree
import gleam/dict
import gleam/dynamic/decode
import gleam/hackney
import gleam/http
import gleam/http/request.{type Request}
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import shellout
import simplifile

pub type Post {
  Post(
    id: String,
    title: String,
    text: String,
    score: Int,
    media: List(Media),
    external_url: Option(String),
    link_flair_text: Option(String),
  )
}

pub type Sort {
  Hot
  New
  Top
  Rising
}

pub type Media {
  Media(url: String, type_: MediaType)
}

pub type MediaType {
  Image
  Gif
  Video
}

pub fn short_link(post: Post) -> String {
  "https://redd.it/" <> post.id
}

pub fn get_posts(
  data: AppData,
  subreddit: String,
  sort: Sort,
) -> Result(List(Post), String) {
  use token <- result.try(get_token(data))

  get_threads(token, data, subreddit, sort)
}

fn get_token(data: AppData) -> Result(String, String) {
  use request <- result.try(
    request.to("https://www.reddit.com/api/v1/access_token")
    |> result.map_error(fn(_) { "Error creating token request" }),
  )

  let credentials =
    { data.client_id <> ":" <> data.client_secret }
    |> bit_array.from_string
    |> bit_array.base64_encode(True)

  request
  |> request.set_header("Authorization", "Basic " <> credentials)
  |> set_user_agent(data)
  |> request.set_header("Content-Type", "application/x-www-form-urlencoded")
  |> request.set_body(
    "grant_type=password&username="
    <> data.username
    <> "&password="
    <> data.password,
  )
  |> request.set_method(http.Post)
  |> hackney.send
  |> result.map_error(fn(_) { "Error getting the token" })
  |> result.try(fn(response) {
    response.body
    |> json.parse(decode.at(["access_token"], decode.string))
    |> result.map_error(fn(_) {
      io.debug(response)
      "Error decoding the token"
    })
  })
}

fn set_user_agent(request: Request(a), data: AppData) -> Request(a) {
  request.set_header(
    request,
    "User-Agent",
    "reddit_to_telegram by /u/" <> data.username,
  )
}

fn get_threads(
  token: String,
  data: AppData,
  subreddit: String,
  sort: Sort,
) -> Result(List(Post), String) {
  let sort_string = case sort {
    Hot -> "hot"
    New -> "new"
    Top -> "top"
    Rising -> "rising"
  }

  use request <- result.try(
    request.to(
      "https://oauth.reddit.com/r/"
      <> subreddit
      <> "/"
      <> sort_string
      <> "?limit=20",
    )
    |> result.map_error(fn(_) { "Error creating threads request" }),
  )

  request
  |> request.set_header("Authorization", "Bearer " <> token)
  |> set_user_agent(data)
  |> hackney.send
  |> result.map_error(fn(_) { "Error getting the threads" })
  |> result.try(fn(response) {
    response.body
    |> json.parse(posts_decoder())
    |> result.map_error(fn(e) { "Error decoding posts: " <> string.inspect(e) })
  })
}

@internal
pub fn posts_decoder() -> decode.Decoder(List(Post)) {
  decode.at(
    ["data", "children"],
    decode.list(decode.at(["data"], post_decoder())),
  )
}

fn post_decoder() -> decode.Decoder(Post) {
  use id <- decode.field("id", decode.string)
  use title <- decode.field("title", decode.string)
  use text <- decode.field("selftext", text_decoder())
  use score <- decode.field("score", decode.int)
  use media <- media_decoder()
  use external_url <- external_url_decoder()
  use link_flair_text <- decode.field(
    "link_flair_text",
    decode.optional(decode.string),
  )
  decode.success(Post(
    id:,
    title:,
    text:,
    score:,
    media:,
    external_url:,
    link_flair_text:,
  ))
}

fn text_decoder() -> decode.Decoder(String) {
  decode.string
  |> decode.map(fn(text) {
    text
    |> string.replace("&amp;", "")
    |> string.replace("#x200B;\n\n", "")
    |> string.replace("#x200B;\n", "")
    |> string.replace("#x200B;", "")
  })
}

fn media_decoder(
  next: fn(List(Media)) -> decode.Decoder(final),
) -> decode.Decoder(final) {
  decode.one_of(
    is_video_decoder()
      |> decode.map(list.prepend([], _)),
    [
      url_decoder()
        |> decode.map(list.prepend([], _)),
      media_metadata_decoder(),
      decode.success([]),
    ],
  )
  |> decode.then(next)
}

fn is_video_decoder() -> decode.Decoder(Media) {
  use is_video <- decode.field("is_video", decode.bool)

  case is_video {
    True -> {
      use fallback_url <- decode.subfield(
        ["media", "reddit_video", "fallback_url"],
        decode.string,
      )
      use is_gif <- decode.subfield(
        ["media", "reddit_video", "is_gif"],
        decode.bool,
      )

      decode.success(
        Media(fallback_url, case is_gif {
          True -> Gif
          False -> Video
        }),
      )
    }
    False -> decode.failure(Media("", Video), "Error decoding is_video")
  }
}

fn url_decoder() -> decode.Decoder(Media) {
  use url <- decode.field("url", decode.string)

  media_from_url(url)
}

fn media_metadata_decoder() -> decode.Decoder(List(Media)) {
  use dict_dynamic <- decode.optional_field(
    "media_metadata",
    [],
    decode.dict(decode.string, decode.dynamic) |> decode.map(dict.values),
  )

  dict_dynamic
  |> list.fold([], fn(acc, dynamic) {
    dynamic
    |> decode.run(metadata_decoder())
    |> result.map(fn(media) { list.prepend(acc, media) })
    |> result.unwrap(acc)
  })
  |> decode.success
}

fn metadata_decoder() -> decode.Decoder(Media) {
  use e <- decode.field("e", decode.string)

  case e {
    "Image" -> {
      decode.at(
        ["s", "u"],
        decode.string
          |> decode.map(fn(url) {
            case url {
              "https://preview.redd.it/" <> path ->
                Media("https://i.redd.it/" <> path, Image)
              _ -> Media(url, Image)
            }
          }),
      )
    }
    "AnimatedImage" -> {
      decode.at(
        ["s", "gif"],
        decode.string
          |> decode.map(fn(url) { Media(url, Gif) }),
      )
    }
    _ -> {
      io.println("Unknown media type: " <> e)
      decode.failure(Media("", Image), "Unknown media type")
    }
  }
}

fn media_from_url(url: String) -> decode.Decoder(Media) {
  use <- bool.guard(
    when: is_url_image(url),
    return: decode.success(Media(url, Image)),
  )
  use <- bool.guard(
    when: is_url_gif(url),
    return: decode.success(Media(url, Gif)),
  )
  decode.failure(Media(url, Image), "Error decoding media from url")
}

fn is_url_image(url: String) -> Bool {
  string.ends_with(url, ".jpg")
  || string.ends_with(url, ".jpeg")
  || string.ends_with(url, ".png")
}

fn is_url_gif(url: String) -> Bool {
  string.ends_with(url, ".gif") || string.ends_with(url, ".gifv")
}

fn external_url_decoder(
  next: fn(Option(String)) -> decode.Decoder(final),
) -> decode.Decoder(final) {
  use is_self <- decode.field("is_self", decode.bool)

  case is_self {
    True -> decode.success(None)
    False -> {
      use url <- decode.field("url", decode.string)
      case string.contains(url, "reddit") {
        True -> decode.failure(None, "Error decoding external url")
        False -> decode.success(Some(url))
      }
    }
  }
  |> decode.then(next)
}

pub fn get_video(url: String) -> Result(String, String) {
  let video_filename = "video.mp4"
  let audio_filename = "audio.mp4"

  use audio_url <- result.try(
    url
    |> string.split("DASH")
    |> list.first
    |> result.map(fn(url) { url <> "DASH_AUDIO_128.mp4" })
    |> result.map_error(fn(_) { "Error getting audio url" }),
  )

  use request <- result.try(
    request.to(url)
    |> result.map_error(fn(_) { "Error creating video request" }),
  )

  io.println("Downloading video...")

  use video_response <- result.try(
    request
    |> request.set_body(bytes_tree.new())
    |> hackney.send_bits
    |> result.map_error(fn(e) {
      io.debug(e)
      "Error getting video"
    }),
  )
  io.println("Downloaded video")

  io.println("Writing video file...")
  use _ <- result.try(
    simplifile.write_bits(video_filename, video_response.body)
    |> result.map_error(fn(_) { "Error writing video file" }),
  )

  use request <- result.try(
    request.to(audio_url)
    |> result.map_error(fn(_) { "Error creating audio request" }),
  )

  io.println("Downloading audio...")
  use audio_response <- result.try(
    request
    |> request.set_body(bytes_tree.new())
    |> hackney.send_bits
    |> result.map_error(fn(_) { "Error getting audio" }),
  )
  io.println("Downloaded audio")

  io.println("Writing audio file...")
  use _ <- result.try(
    simplifile.write_bits(audio_filename, audio_response.body)
    |> result.map_error(fn(_) { "Error writing audio file" }),
  )

  let filename = "video_with_audio.mp4"

  io.println("Merging video and audio...")
  use _ <- result.try(
    shellout.command(
      run: "ffmpeg",
      with: [
        "-i",
        video_filename,
        "-i",
        audio_filename,
        "-c:v",
        "copy",
        "-c:a",
        "aac",
        "-strict",
        "experimental",
        filename,
        "-hide_banner",
        "-loglevel",
        "panic",
        "-y",
      ],
      in: ".",
      opt: [],
    )
    |> result.map_error(fn(error) { error.1 }),
  )
  io.println("Merged video and audio")

  io.println("Removing video and audio files...")
  let rm_result =
    shellout.command(
      run: "rm",
      with: [video_filename, audio_filename],
      in: ".",
      opt: [],
    )

  case rm_result {
    Ok(_) -> io.println("Removed video and audio files")
    Error(_) -> io.println("Error removing video and audio files")
  }

  Ok(filename)
}
