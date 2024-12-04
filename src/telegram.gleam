import app_data.{type AppData}
import form_data
import gleam/bit_array
import gleam/dynamic
import gleam/erlang/process
import gleam/hackney
import gleam/http
import gleam/http/request
import gleam/int
import gleam/io
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/pair
import gleam/result
import gleam/string
import reddit
import reddit/markdown

type InputMedia {
  InputMedia(url: String, type_: InputMediaType)
}

type InputMediaType {
  Video
  Animation
  Photo
}

fn delay_after(callback: fn() -> a) -> a {
  let result = callback()
  process.sleep(1000)
  result
}

pub fn send_messages(
  posts: List(reddit.Post),
  data: AppData,
  chat_id: String,
) -> List(#(String, Option(String))) {
  use post, index <- list.index_map(posts)

  // Add a delay between each message to avoid rate limiting
  case index {
    0 -> Nil
    _ -> process.sleep(1000)
  }

  case send(post, data, chat_id) {
    Ok(_post_id) -> None
    Error(error) -> Some(error)
  }
  |> pair.new(post.id, _)
}

fn send(
  post: reddit.Post,
  data: AppData,
  chat_id: String,
) -> Result(String, String) {
  case post.media {
    [] -> send_text(post, chat_id, data)
    [media] -> send_single_media(post, chat_id, data, media)
    multiple -> send_group_media(post, chat_id, data, multiple)
  }
}

fn send_single_media(
  post: reddit.Post,
  chat_id: String,
  data: AppData,
  media: reddit.Media,
) -> Result(String, String) {
  case media {
    reddit.Media(url, reddit.Image) ->
      send_json("sendPhoto", photo_encode(url, post, chat_id), post.id, data)
    reddit.Media(url, reddit.Gif) ->
      send_animation(url, Some(post), post.id, chat_id, data)
    reddit.Media(url, reddit.Video) -> {
      url
      |> reddit.get_video
      |> result.try(send_video(_, chat_id, post, data))
      |> result.try_recover(fn(e) {
        io.println("Couldn't send video: " <> e)
        io.println("Sending message as text instead...")

        send_text(post, chat_id, data)
      })
    }
  }
}

fn send_group_media(
  post: reddit.Post,
  chat_id: String,
  data: AppData,
  medias: List(reddit.Media),
) -> Result(String, String) {
  medias
  // Telegram's limit is 10 media per message
  |> list.sized_chunk(10)
  |> list.map(send_media_chunk(_, post, chat_id, data))
  |> list.filter(result.is_error(_))
  |> list.map(result.unwrap_error(_, ""))
  |> fn(errors) {
    case errors {
      [] -> send_text(post, chat_id, data)
      _ -> Error(string.join(errors, "\n"))
    }
  }
}

fn send_media_chunk(
  chunk: List(reddit.Media),
  post: reddit.Post,
  chat_id: String,
  data: AppData,
) -> Result(String, String) {
  let #(animations, other_medias) =
    chunk
    |> list.map(get_input_media)
    |> list.partition(fn(media) { media.type_ == Animation })

  let animations_result =
    list.try_each(animations, fn(animation) {
      delay_after(fn() {
        send_animation(animation.url, None, post.id, chat_id, data)
      })
    })
  // Telegram's sendMediaGroup doesn't support animations
  // so we send them separately
  use _ <- result.try(animations_result)

  case other_medias {
    [] -> Ok(post.id)
    _ ->
      delay_after(fn() {
        send_json(
          "sendMediaGroup",
          media_group_encode(other_medias, post, chat_id),
          post.id,
          data,
        )
      })
  }
}

fn get_input_media(media: reddit.Media) -> InputMedia {
  case media.type_ {
    reddit.Image -> InputMedia(url: media.url, type_: Photo)
    reddit.Gif -> InputMedia(url: media.url, type_: Animation)
    reddit.Video -> InputMedia(url: media.url, type_: Video)
  }
}

fn send_text(
  post: reddit.Post,
  chat_id: String,
  data: AppData,
) -> Result(String, String) {
  text_encode(post, chat_id)
  |> list.try_each(send_json("sendMessage", _, post.id, data))
  |> result.map(fn(_) { post.id })
}

fn send_json(
  path: String,
  body: Json,
  post_id: String,
  data: AppData,
) -> Result(String, String) {
  let base_url = "https://api.telegram.org/bot" <> data.telegram_token

  use request <- result.try(
    request.to(base_url <> "/" <> path)
    |> result.map_error(fn(_) { "Couldn't create JSON request" }),
  )

  use response <- result.try(
    request
    |> request.set_method(http.Post)
    |> request.set_body(json.to_string(body))
    |> request.set_header("Content-Type", "application/json")
    |> hackney.send
    |> result.map_error(fn(e) {
      io.debug(e)
      "Error sending JSON request"
    }),
  )

  case response.status {
    200 -> Ok(post_id)
    429 -> {
      let retry_after =
        response.body
        |> json.decode(retry_after_decoder())
        |> result.unwrap(60)

      io.println(
        "Rate limited, waiting " <> int.to_string(retry_after) <> " seconds...",
      )
      process.sleep(retry_after * 1000)
      send_json(path, body, post_id, data)
    }
    _ -> Error("Error sending post " <> post_id <> ": " <> response.body)
  }
}

fn send_video(
  filename: String,
  chat_id: String,
  post: reddit.Post,
  data: AppData,
) -> Result(String, String) {
  let base_url = "https://api.telegram.org/bot" <> data.telegram_token

  use request <- result.try(
    request.to(base_url <> "/sendVideo")
    |> result.map_error(fn(_) { "Couldn't create video request" }),
  )

  let form =
    form_data.new([
      form_data.Text("parse_mode", "HTML"),
      form_data.Text("caption", media_caption(post, chat_id)),
      form_data.Text("chat_id", chat_id),
      form_data.File(path: "./" <> filename, name: "video", extra_headers: [
        #("Content-Type", "video/mp4"),
      ]),
    ])

  io.println("Sending video...")
  use response <- result.try(
    request
    |> request.set_method(http.Post)
    |> request.set_body(form.body)
    |> request.set_header("Content-Length", int.to_string(form.length))
    |> request.set_header(
      "Content-Type",
      "multipart/form-data; boundary=" <> form.boundary,
    )
    |> hackney.send_bits
    |> result.map_error(fn(e) {
      io.debug(e)
      "Error sending video"
    }),
  )

  case response.status {
    200 -> {
      io.println("Video sent!")

      Ok(post.id)
    }
    status -> {
      io.debug(response)

      Error(
        "Error from server while sending video, HTTP status: "
        <> int.to_string(status)
        <> case bit_array.to_string(response.body) {
          Ok(body) -> " " <> body
          Error(_) -> ""
        },
      )
    }
  }
}

fn send_animation(
  url: String,
  post: Option(reddit.Post),
  post_id: String,
  chat_id: String,
  data: AppData,
) -> Result(String, String) {
  send_json(
    "sendAnimation",
    animation_encode(url, post, chat_id),
    post_id,
    data,
  )
}

pub fn media_caption(post: reddit.Post, chat_id: String) {
  post.title <> "\n\n" <> reddit.short_link(post) <> "\n\n" <> chat_id
}

fn caption_json_field(post: reddit.Post, chat_id: String) {
  #("caption", json.string(media_caption(post, chat_id)))
}

fn parse_mode_json_field() {
  #("parse_mode", json.string("HTML"))
}

fn chat_id_json_field(id: String) {
  #("chat_id", json.string(id))
}

fn photo_encode(url: String, post: reddit.Post, chat_id: String) {
  json.object([
    #("photo", json.string(url)),
    parse_mode_json_field(),
    caption_json_field(post, chat_id),
    chat_id_json_field(chat_id),
  ])
}

fn animation_encode(url: String, post: Option(reddit.Post), chat_id: String) {
  case post {
    Some(post) -> [caption_json_field(post, chat_id)]
    None -> []
  }
  |> list.append([
    #("animation", json.string(url)),
    parse_mode_json_field(),
    chat_id_json_field(chat_id),
  ])
  |> json.object
}

fn text_encode(post: reddit.Post, chat_id: String) -> List(Json) {
  let external_url = case post.external_url {
    Ok(url) -> "\n" <> url
    Error(_) -> ""
  }

  let post_text = case post.text {
    "" -> ""
    _ -> "\n\n" <> post.text
  }

  let text =
    post.title
    <> external_url
    <> markdown.reddit_to_telegram(post_text)
    <> "\n\n"
    <> reddit.short_link(post)
    <> "\n\n"
    <> chat_id

  text
  |> string.to_graphemes
  |> list.sized_chunk(4096)
  |> list.map(string.join(_, ""))
  |> list.map(fn(chunk) {
    json.object([
      #("text", json.string(chunk)),
      parse_mode_json_field(),
      chat_id_json_field(chat_id),
    ])
  })
}

fn media_group_encode(
  input_medias: List(InputMedia),
  post: reddit.Post,
  chat_id: String,
) {
  json.object([
    #("media", json.array(input_medias, input_media_encode)),
    parse_mode_json_field(),
    caption_json_field(post, chat_id),
    chat_id_json_field(chat_id),
  ])
}

fn input_media_encode(input_media: InputMedia) -> Json {
  json.object([
    #("media", json.string(input_media.url)),
    #(
      "type",
      json.string(case input_media.type_ {
        Photo -> "photo"
        Animation -> "animation"
        Video -> "video"
      }),
    ),
  ])
}

fn retry_after_decoder() -> dynamic.Decoder(Int) {
  dynamic.field("parameters", dynamic.field("retry_after", dynamic.int))
}
