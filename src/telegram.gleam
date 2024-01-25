import app_data.{type AppData}
import gleam/hackney
import gleam/http
import gleam/http/request
import gleam/io
import gleam/erlang/process
import gleam/result
import gleam/json
import gleam/list
import reddit

pub fn send_messages(
  posts: List(reddit.Post),
  data: AppData,
  chat_id: String,
) -> List(Result(String, Nil)) {
  use post <- list.map(posts)

  let result = send(post, data, chat_id)
  process.sleep(1000)
  result
}

fn send(
  post: reddit.Post,
  data: AppData,
  chat_id: String,
) -> Result(String, Nil) {
  let base_url = "https://api.telegram.org/bot" <> data.telegram_token

  let #(path, body) = case post.media {
    Ok(reddit.Media(url, reddit.Image)) -> {
      #("sendPhoto", photo_encode(url, post, chat_id))
    }
    Ok(reddit.Media(url, reddit.Gif)) -> {
      #("sendAnimation", animation_encode(url, post, chat_id))
    }
    Ok(reddit.Media(url, reddit.Video)) -> {
      #("sendVideo", video_encode(url, post, chat_id))
    }
    Error(_) -> {
      #("sendMessage", text_encode(post, chat_id))
    }
  }

  use request <- result.try(request.to(base_url <> "/" <> path))

  use response <- result.try(
    request
    |> request.set_method(http.Post)
    |> request.set_body(json.to_string(body))
    |> request.set_header("Content-Type", "application/json")
    |> hackney.send
    |> result.map_error(fn(e) {
      io.debug(e)
      Nil
    }),
  )

  case response.status == 200 {
    True -> {
      Ok(post.id)
    }
    False -> {
      io.debug(response)
      Error(Nil)
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

fn video_encode(url: String, post: reddit.Post, chat_id: String) {
  json.object([
    #("video", json.string(url)),
    parse_mode_json_field(),
    caption_json_field(post, chat_id),
    chat_id_json_field(chat_id),
  ])
}

fn text_encode(post: reddit.Post, chat_id: String) {
  json.object([
    #(
      "text",
      json.string(
        post.title
        <> "\n"
        <> "\n"
        <> post.text
        <> "\n"
        <> "\n"
        <> reddit.short_link(post)
        <> "\n"
        <> "\n"
        <> chat_id_as_link(chat_id),
      ),
    ),
    parse_mode_json_field(),
    chat_id_json_field(chat_id),
  ])
}
