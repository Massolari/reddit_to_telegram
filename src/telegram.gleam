import app_data.{type AppData}
import form_data
import gleam/bit_array
import gleam/hackney
import gleam/http
import gleam/http/request
import gleam/int
import gleam/io
import gleam/erlang/process
import gleam/result
import gleam/json.{type Json}
import gleam/list
import reddit

pub fn send_messages(
  posts: List(reddit.Post),
  data: AppData,
  chat_id: String,
) -> List(Result(String, String)) {
  use post, index <- list.index_map(posts)

  // Add a delay between each message to avoid rate limiting
  case index {
    0 -> Nil
    _ -> process.sleep(1000)
  }

  send(post, data, chat_id)
}

fn send(
  post: reddit.Post,
  data: AppData,
  chat_id: String,
) -> Result(String, String) {
  case post.media {
    Ok(reddit.Media(url, reddit.Image)) -> {
      send_json("sendPhoto", photo_encode(url, post, chat_id), post, data)
    }
    Ok(reddit.Media(url, reddit.Gif)) -> {
      send_json(
        "sendAnimation",
        animation_encode(url, post, chat_id),
        post,
        data,
      )
    }
    Ok(reddit.Media(url, reddit.Video)) -> {
      url
      |> reddit.get_video
      |> result.try(send_video(_, chat_id, post, data))
      |> result.try_recover(fn(e) {
        io.println("Couldn't send video: " <> e)
        io.println("Sending message as text instead...")

        send_json("sendMessage", text_encode(post, chat_id), post, data)
      })
    }
    Error(_) -> {
      send_json("sendMessage", text_encode(post, chat_id), post, data)
    }
  }
}

fn send_json(
  path: String,
  body: Json,
  post: reddit.Post,
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

  case response.status == 200 {
    True -> {
      Ok(post.id)
    }
    False -> {
      Error(response.body)
    }
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
      form_data.Text("parse_mode", "Markdown"),
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
      "multipart/form-data; boundary="
      <> form.boundary,
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

pub fn chat_id_as_link(chat_id: String) {
  "[" <> chat_id <> "](" <> chat_id <> ")"
}

pub fn media_caption(post: reddit.Post, chat_id: String) {
  post.title
  <> "\n"
  <> reddit.short_link(post)
  <> "\n\n"
  <> chat_id_as_link(chat_id)
}

fn caption_json_field(post: reddit.Post, chat_id: String) {
  #("caption", json.string(media_caption(post, chat_id)))
}

fn parse_mode_json_field() {
  #("parse_mode", json.string("Markdown"))
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

fn animation_encode(url: String, post: reddit.Post, chat_id: String) {
  json.object([
    #("animation", json.string(url)),
    parse_mode_json_field(),
    caption_json_field(post, chat_id),
    chat_id_json_field(chat_id),
  ])
}

fn text_encode(post: reddit.Post, chat_id: String) {
  let external_url = case post.external_url {
    Ok(url) -> "\n" <> url
    Error(_) -> ""
  }

  let text = case post.text {
    "" -> ""
    _ -> "\n\n" <> post.text
  }

  json.object([
    #(
      "text",
      json.string(
        post.title
        <> external_url
        <> text
        <> "\n\n"
        <> reddit.short_link(post)
        <> "\n\n"
        <> chat_id_as_link(chat_id),
      ),
    ),
    parse_mode_json_field(),
    chat_id_json_field(chat_id),
  ])
}
