import gleam/io
import gleam/list
import reddit
import telegram
import bridge.{type Bridge}
import app_data.{type AppData}
import database

pub fn main() {
  let assert Ok(app_data) = app_data.get()
  let assert Ok(bridges) = bridge.get()
  // TODO: implement database logic to prevent sending the same post twice
  // let database = database.connect()

  start(app_data, bridges)
}

fn start(data: AppData, bridges: List(Bridge)) {
  io.println("Starting...")

  use bridge <- list.each(bridges)

  let result_posts = reddit.get_posts(data, bridge.subreddit)

  case result_posts {
    Ok(posts) -> telegram.send_messages(posts, data, bridge.telegram_channel)
    Error(_) -> io.println("Error getting posts")
  }

  Nil
}
