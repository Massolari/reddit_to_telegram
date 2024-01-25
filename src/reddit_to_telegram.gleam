import gleam/io
import gleam/list
import gleam/result
import gleam/function
import gleam/int
import reddit
import telegram
import bridge.{type Bridge}
import app_data.{type AppData}
import database
import sqlight

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
    Ok(_) -> io.println("Done")
    Error(error) -> io.println("Error: " <> error)
  }
}

fn start(
  data: AppData,
  bridges: List(Bridge),
  database: sqlight.Connection,
) -> Nil {
  io.println("Starting...")

  use bridge <- list.each(bridges)

  io.println("Getting posts from subreddit " <> bridge.subreddit <> "...")
  let result_posts =
    reddit.get_posts(data, bridge.subreddit, bridge.reddit_sort)

  case result_posts {
    Ok(posts) -> {
      let sent_messages =
        database
        |> database.get_messages(bridge.telegram_channel)
        |> result.unwrap([])

      let filtered_posts =
        posts
        |> filter_sent_posts(sent_messages)
        |> filter_low_score(10)

      io.println(
        "Sending messages to telegram channel "
        <> bridge.telegram_channel
        <> "...",
      )
      let inserted =
        filtered_posts
        |> telegram.send_messages(data, bridge.telegram_channel)
        |> list.filter_map(function.identity)

      io.println(
        inserted
        |> list.length
        |> int.to_string
        <> " messages sent",
      )

      let _ = database.add_messages(database, inserted, bridge.telegram_channel)

      Nil
    }
    Error(_) -> io.println("Error getting posts")
  }

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
