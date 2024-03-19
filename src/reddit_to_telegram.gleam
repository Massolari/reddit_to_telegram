import gleam/io
import gleam/list
import gleam/result
import gleam/pair
import gleam/string
import gleam/int
import reddit
import telegram
import bridge.{type Bridge}
import app_data.{type AppData}
import app_result.{type AppResult, AppError, AppOk, AppWarning}
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

  io.println("Done!")

  case result {
    Ok(warnings_errors) -> {
      let #(warnings, errors) = app_result.partition(warnings_errors)

      case warnings {
        [] -> Nil
        _ -> {
          io.println("Warnings:")

          list.each(warnings, io.println)
        }
      }

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
) -> List(AppResult(String)) {
  io.println("Starting...")

  use bridge <- list.map(bridges)

  io.println("Getting posts from subreddit " <> bridge.subreddit <> "...")

  use posts <- app_result.try(
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
    |> filter_low_score(10)

  io.println(
    "Sending messages to telegram channel " <> bridge.telegram_channel <> "...",
  )
  let #(inserted, errors) =
    filtered_posts
    |> telegram.send_messages(data, bridge.telegram_channel)
    |> list.partition(with: result.is_ok)
    |> pair.map_first(result.values)
    |> pair.map_second(list.map(_, result.unwrap_error(_, "")))

  io.println(
    inserted
    |> list.length
    |> int.to_string
    <> " messages sent",
  )

  let _ = database.add_messages(database, inserted, bridge.telegram_channel)

  let error_string = string.join(errors, "\n")

  case inserted, errors {
    [], [_, ..] -> AppError(error_string)

    _, [_, ..] -> AppWarning(error_string)

    _, _ -> AppOk("")
  }
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
