import app_data.{type AppData}
import bridge.{type Bridge}
import database
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/pair
import gleam/result
import reddit
import sqlight
import telegram

pub fn main() {
  let result = {
    io.println("Loading app data...")
    use app_data <- result.try(app_data.get())
    io.println("Loading bridges...")
    use bridges <- result.try(bridge.get())
    io.println("Connecting to database...")
    use database <- result.map(database.connect())

    start(app_data, bridges, database)
  }

  case result {
    Ok(results) -> {
      io.println("Done!")

      let #(_, errors) = result.partition(results)

      case errors {
        [] -> Nil
        _ -> {
          io.println("Errors: ")

          list.each(errors, io.println)
        }
      }
    }
    Error(error) -> io.println("Error: " <> error)
  }
}

fn start(
  data: AppData,
  bridges: List(Bridge),
  database: sqlight.Connection,
) -> List(Result(Nil, String)) {
  io.println("Starting...")

  use bridge <- list.map(bridges)

  io.println("Getting posts from subreddit " <> bridge.subreddit <> "...")

  use posts <- result.map(
    reddit.get_posts(data, bridge.subreddit, bridge.reddit_sort)
    |> result.map_error(fn(error) {
      "Error getting posts for the subreddit "
      <> bridge.subreddit
      <> ": "
      <> error
    }),
  )

  let sent_messages =
    database
    |> database.get_messages(bridge.telegram_channel)
    |> result.unwrap([])

  let filtered_posts =
    posts
    |> filter_sent_posts(sent_messages)
    |> filter_low_score(bridge.minimum_upvotes)
    |> filter_flair(bridge.flair_include, bridge.flair_exclude)

  io.println(
    "Sending "
    <> int.to_string(list.length(filtered_posts))
    <> " posts to telegram channel "
    <> bridge.telegram_channel
    <> "...",
  )
  let sent =
    telegram.send_messages(filtered_posts, data, bridge.telegram_channel)

  log_sent_messages(sent)

  let sent_ids = list.map(sent, pair.first)

  let _ = database.add_messages(database, sent_ids, bridge.telegram_channel)

  Nil
}

pub fn filter_sent_posts(
  posts: List(reddit.Post),
  sent: List(String),
) -> List(reddit.Post) {
  list.filter(posts, fn(post) { !list.contains(sent, post.id) })
}

pub fn filter_low_score(
  posts: List(reddit.Post),
  minimum: Int,
) -> List(reddit.Post) {
  list.filter(posts, fn(post) { post.score >= minimum })
}

pub fn filter_flair(
  posts: List(reddit.Post),
  include: List(String),
  exclude: List(String),
) -> List(reddit.Post) {
  let include_filter = case include {
    [] -> fn(_post) { True }
    _ -> fn(post: reddit.Post) { list.contains(include, post.link_flair_text) }
  }

  list.filter(posts, fn(post) {
    include_filter(post) && !list.contains(exclude, post.link_flair_text)
  })
}

fn log_sent_messages(sent: List(#(String, Option(String)))) {
  use #(post_id, error) <- list.each(sent)

  io.print("Sent message for post " <> post_id <> " ")

  case error {
    None -> io.println("successfully")
    Some(error) -> io.println("with error: " <> error)
  }
}
