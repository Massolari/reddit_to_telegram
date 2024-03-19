import app_data.{type AppData}
import gleam/bit_array
import gleam/bytes_builder
import gleam/bool
import gleam/dict
import gleam/dynamic
import gleam/hackney
import gleam/http
import gleam/http/request.{type Request}
import gleam/io
import gleam/json
import gleam/list
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
    external_url: Result(String, Nil),
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
    json.decode(
      from: response.body,
      using: dynamic.field(named: "access_token", of: dynamic.string),
    )
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
    json.decode(from: response.body, using: posts_decoder())
    |> result.map_error(fn(_) {
      io.debug(response)
      "Error decoding posts"
    })
  })
}

fn posts_decoder() -> dynamic.Decoder(List(Post)) {
  dynamic.field(
    named: "data",
    of: dynamic.field(
      named: "children",
      of: dynamic.list(of: dynamic.field("data", post_decoder())),
    ),
  )
}

fn post_decoder() -> dynamic.Decoder(Post) {
  dynamic.decode6(
    Post,
    dynamic.field(named: "id", of: dynamic.string),
    dynamic.field(named: "title", of: dynamic.string),
    text_decoder(),
    dynamic.field(named: "score", of: dynamic.int),
    media_decoder(),
    external_url_decoder(),
  )
}

fn text_decoder() -> dynamic.Decoder(String) {
  dynamic.field(named: "selftext", of: fn(dynamic) {
    dynamic.string(dynamic)
    |> result.map(fn(text) {
      text
      |> string.replace("&amp;", "")
      |> string.replace("#x200B;\n\n", "")
      |> string.replace("#x200B;\n", "")
      |> string.replace("#x200B;", "")
    })
  })
}

fn media_decoder() -> dynamic.Decoder(List(Media)) {
  dynamic.any([
    fn(dynamic) {
      is_video_decoder(dynamic)
      |> result.map(list.prepend([], _))
    },
    fn(dynamic) {
      url_decoder()(dynamic)
      |> result.map(list.prepend([], _))
    },
    fn(dynamic) { media_metadata_decoder()(dynamic) },
    fn(_) { Ok([]) },
  ])
}

fn is_video_decoder(
  json: dynamic.Dynamic,
) -> Result(Media, List(dynamic.DecodeError)) {
  dynamic.field(named: "is_video", of: fn(dynamic_is_video) {
    dynamic.bool(dynamic_is_video)
    |> result.try(fn(is_video) {
      case is_video {
        True -> {
          dynamic.field(
            named: "media",
            of: dynamic.field(
              named: "reddit_video",
              of: dynamic.decode2(
                fn(url: String, is_gif: Bool) {
                  case is_gif {
                    True -> Media(url, Gif)
                    False -> Media(url, Video)
                  }
                },
                dynamic.field(named: "fallback_url", of: dynamic.string),
                dynamic.field(named: "is_gif", of: dynamic.bool),
              ),
            ),
          )(json)
        }
        False -> Error([])
      }
    })
  })(json)
}

fn url_decoder() -> dynamic.Decoder(Media) {
  dynamic.field(named: "url", of: fn(dynamic_url) {
    dynamic.string(dynamic_url)
    |> result.try(media_from_url)
  })
}

fn media_metadata_decoder() -> dynamic.Decoder(List(Media)) {
  dynamic.field(named: "media_metadata", of: fn(dynamic_media_metadata) {
    use dict_dynamic <- result.try(
      dynamic_media_metadata
      |> dynamic.dict(of: dynamic.string, to: dynamic.dynamic)
      |> result.map(dict.values),
    )

    use acc, dynamic <- list.try_fold(dict_dynamic, [])

    dynamic
    |> metadata_decoder()
    |> result.map_error(fn(_) { [] })
    |> result.map(fn(media) { list.prepend(acc, media) })
  })
}

fn metadata_decoder() -> dynamic.Decoder(Media) {
  fn(dynamic_metadata) {
    dynamic.field(named: "e", of: fn(dynamic_e) {
      dynamic.string(dynamic_e)
      |> result.try(fn(e) {
        case e {
          "Image" -> {
            dynamic.field(
              named: "s",
              of: dynamic.field(named: "u", of: fn(dynamic_url) {
                dynamic.string(dynamic_url)
                |> result.map(fn(url) {
                  case url {
                    "https://preview.redd.it/" <> path ->
                      Media("https://i.redd.it/" <> path, Image)
                    _ -> Media(url, Image)
                  }
                })
              }),
            )(dynamic_metadata)
          }
          "AnimatedImage" -> {
            dynamic.field(
              named: "s",
              of: dynamic.field(named: "gif", of: fn(dynamic_url) {
                dynamic.string(dynamic_url)
                |> result.map(fn(url) { Media(url, Gif) })
              }),
            )(dynamic_metadata)
          }
          _ -> {
            io.println("Unknown media type: " <> e)
            Error([])
          }
        }
      })
    })(dynamic_metadata)
  }
}

fn media_from_url(url: String) -> Result(Media, dynamic.DecodeErrors) {
  use <- bool.guard(when: is_url_image(url), return: Ok(Media(url, Image)))
  use <- bool.guard(when: is_url_gif(url), return: Ok(Media(url, Gif)))
  Error([])
}

fn is_url_image(url: String) -> Bool {
  string.ends_with(url, ".jpg")
  || string.ends_with(url, ".jpeg")
  || string.ends_with(url, ".png")
}

fn is_url_gif(url: String) -> Bool {
  string.ends_with(url, ".gif") || string.ends_with(url, ".gifv")
}

fn external_url_decoder() -> dynamic.Decoder(Result(String, Nil)) {
  fn(json) {
    dynamic.field(named: "is_self", of: fn(dynamic_is_self) {
      dynamic.bool(dynamic_is_self)
      |> result.try(fn(is_self) {
        case is_self {
          True -> Ok(Error(Nil))
          False -> {
            dynamic.field(named: "url", of: fn(dynamic_url) {
              dynamic.string(dynamic_url)
              |> result.map(fn(url) {
                case string.contains(url, "reddit") {
                  True -> Error(Nil)
                  _ -> Ok(url)
                }
              })
            })(json)
          }
        }
      })
    })(json)
  }
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
    |> request.set_body(bytes_builder.new())
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
    |> request.set_body(bytes_builder.new())
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
