import sqlight.{type Connection}
import gleam/dynamic
import gleam/result
import gleam/list
import gleam/io
import gleam/string

pub fn connect() {
  use connection <- result.map(
    sqlight.open("file:./db/data.sqlite3")
    |> result.map_error(fn(error) { error.message }),
  )

  let _ = setup(connection)

  connection
}

fn setup(connection: Connection) {
  let create_sent_messages_table =
    "CREATE TABLE IF NOT EXISTS sent_messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      thread_id TEXT NOT NULL,
      chat_id TEXT NOT NULL
    )
    "

  create_sent_messages_table
  |> sqlight.exec(on: connection)
  |> result.map_error(io.debug)
}

pub fn get_messages(
  connection: Connection,
  chat_id: String,
) -> Result(List(String), sqlight.Error) {
  sqlight.query(
    "SELECT thread_id FROM sent_messages WHERE chat_id = ?",
    on: connection,
    with: [sqlight.text(chat_id)],
    expecting: dynamic.element(0, dynamic.string),
  )
}

pub fn add_message(
  connection: Connection,
  thread_id: String,
  chat_id: String,
) -> Result(List(Nil), sqlight.Error) {
  sqlight.query(
    "INSERT INTO sent_messages (thread_id, chat_id) VALUES (?, ?)",
    on: connection,
    with: [sqlight.text(thread_id), sqlight.text(chat_id)],
    expecting: fn(_) { Ok(Nil) },
  )
}

pub fn add_messages(
  connection: Connection,
  thread_ids: List(String),
  chat_id: String,
) -> Result(List(Nil), sqlight.Error) {
  let query_values =
    thread_ids
    |> list.length
    |> list.repeat("(?, ?)", _)
    |> string.join(", ")

  let sql =
    "INSERT INTO sent_messages (thread_id, chat_id) VALUES " <> query_values

  sqlight.query(
    sql,
    on: connection,
    with: list.flat_map(thread_ids, fn(id) {
      [sqlight.text(id), sqlight.text(chat_id)]
    }),
    expecting: fn(_) { Ok(Nil) },
  )
}
