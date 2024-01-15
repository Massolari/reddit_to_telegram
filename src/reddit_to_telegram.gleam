import gleam/io
import gleam/list
import gleam/result
import gleam/function
import reddit
import telegram
import bridge.{type Bridge}
import app_data.{type AppData}
import database
import sqlight

pub fn main() {
  let result = {
    use app_data <- result.try(app_data.get())
    use bridges <- result.try(bridge.get())
    use database <- result.map(database.connect())

    let _ = start(app_data, bridges, database)
    database
  }

  case result {
    Ok(_) -> io.println("Done")
    Error(error) -> io.println("Error: " <> error)
  }
}

fn start(data: AppData, bridges: List(Bridge), database: sqlight.Connection) {
  io.println("Starting...")

  use bridge <- list.each(bridges)

  let result_posts = reddit.get_posts(data, bridge.subreddit)

  case result_posts {
    Ok(posts) -> {
      let sent_messages =
        database
        |> database.get_messages(bridge.telegram_channel)
        |> result.unwrap([])

      let filtered_posts =
        posts
        |> filter_sent_posts(sent_messages)
        |> filter_low_score

      let inserted =
        filtered_posts
        |> telegram.send_messages(data, bridge.telegram_channel)
        |> list.filter_map(function.identity)

      let _ = database.add_messages(database, inserted, bridge.telegram_channel)

      Nil
    }
    Error(_) -> io.println("Error getting posts")
  }

  Nil
}

fn filter_sent_posts(
  posts: List(reddit.Post),
  sent: List(String),
) -> List(reddit.Post) {
  list.filter(posts, fn(post) { !list.contains(sent, post.id) })
}

fn filter_low_score(posts: List(reddit.Post)) -> List(reddit.Post) {
  list.filter(posts, fn(post) { post.score >= 10 })
}
