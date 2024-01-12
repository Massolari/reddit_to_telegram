import app_data.{type AppData}
import gleam/bit_array
import gleam/bool
import gleam/dynamic
import gleam/hackney
import gleam/http
import gleam/http/request.{type Request}
import gleam/io
import gleam/json
import gleam/result
import gleam/string

pub type Post {
  Post(
    id: String,
    title: String,
    text: String,
    score: Int,
    media: Result(Media, Nil),
  )
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

pub fn get_posts(data: AppData, subreddit: String) -> Result(List(Post), Nil) {
  let assert Ok(token) = get_token(data)

  get_hot(token, data, subreddit)
}

fn get_token(data: AppData) -> Result(String, Nil) {
  let assert Ok(request) =
    request.to("https://www.reddit.com/api/v1/access_token")

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
  |> result.map_error(fn(_) { Nil })
  |> result.try(fn(response) {
    json.decode(
      from: response.body,
      using: dynamic.field(named: "access_token", of: dynamic.string),
    )
    |> result.map_error(fn(_) {
      io.println("Error decoding the token")
      io.debug(response)
      Nil
    })
  })
}

fn set_user_agent(request: Request(a), data: AppData) -> Request(a) {
  request.set_header(
    request,
    "User-Agent",
    "reddit_to_telegram by /u/"
    <> data.username,
  )
}

fn get_hot(
  token: String,
  data: AppData,
  subreddit: String,
) -> Result(List(Post), Nil) {
  let assert Ok(request) =
    request.to("https://oauth.reddit.com/r/" <> subreddit <> "/hot?limit=10")

  request
  |> request.set_header("Authorization", "Bearer " <> token)
  |> set_user_agent(data)
  |> hackney.send
  |> result.map_error(fn(_) { Nil })
  |> result.try(fn(response) {
    json.decode(from: response.body, using: posts_decoder())
    |> result.map_error(fn(_) {
      io.println("Error decoding posts")
      io.debug(response)
      Nil
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
  dynamic.decode5(
    Post,
    dynamic.field(named: "id", of: dynamic.string),
    dynamic.field(named: "title", of: dynamic.string),
    dynamic.field(named: "selftext", of: dynamic.string),
    dynamic.field(named: "score", of: dynamic.int),
    media_decoder(),
  )
}

fn media_decoder() -> dynamic.Decoder(Result(Media, Nil)) {
  fn(json) {
    dynamic.any([
      fn(dynamic) {
        is_video_decoder(json)(dynamic)
        |> result.map(Ok)
      },
      fn(dynamic) {
        url_decoder()(dynamic)
        |> result.map(Ok)
      },
      fn(_) { Ok(Error(Nil)) },
    ])(json)
  }
}

fn is_video_decoder(json: dynamic.Dynamic) -> dynamic.Decoder(Media) {
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
                  let media = case is_gif {
                    True -> Media(url, Gif)
                    False -> Media(url, Video)
                  }

                  media
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
  })
}

fn url_decoder() -> dynamic.Decoder(Media) {
  dynamic.field(named: "url", of: fn(dynamic_url) {
    dynamic.string(dynamic_url)
    |> result.try(media_from_url)
  })
}

// TODO: It's not possible for Telegram to show images from reddit, so we need to
// download them and send them as files.
//
// fn media_metadata_decoder() -> dynamic.Decoder(Media) {
//   dynamic.field(named: "media_metadata", of: fn(dynamic_media_metadata) {
//     dynamic.dict(of: dynamic.string, to: dynamic.dynamic)(dynamic_media_metadata,
//     )
//     |> result.try(fn(dict_dynamic) {
//       dict_dynamic
//       |> dict.values
//       // TODO: handle multiple images
//       |> list.first
//       // List(DecodeError)
//       |> result.map_error(fn(_) { [] })
//       |> result.try(metadata_decoder())
//     })
//   })
// }
//
// fn metadata_decoder() -> dynamic.Decoder(Media) {
//   fn(dynamic_metadata) {
//     dynamic.field(named: "e", of: fn(dynamic_e) {
//       dynamic.string(dynamic_e)
//       |> result.try(fn(e) {
//         case e {
//           "Image" -> {
//             dynamic.field(
//               named: "s",
//               of: dynamic.field(named: "u", of: fn(dynamic_url) {
//                 dynamic.string(dynamic_url)
//                 |> result.map(fn(url) { Media(url, Image) })
//               }),
//             )(dynamic_metadata)
//           }
//           "AnimatedImage" -> {
//             dynamic.field(
//               named: "s",
//               of: dynamic.field(named: "gif", of: fn(dynamic_url) {
//                 dynamic.string(dynamic_url)
//                 |> result.map(fn(url) { Media(url, Gif) })
//               }),
//             )(dynamic_metadata)
//           }
//           _ -> {
//             io.println("Unknown media type: " <> e)
//             Error([])
//           }
//         }
//       })
//     })(dynamic_metadata)
//   }
// }

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
