import sqlight.{type Connection}
import gleam/dynamic
import gleam/result

pub fn connect() {
  let assert Ok(connection) = sqlight.open("file:data.sqlite3")

  let _ = setup(connection)

  connection
}

fn setup(connection: Connection) {
  let create_sent_messages_table =
    "
    CREATE TABLE IF NOT EXISTS sent_messages (
      id INTEGER PRIMARY KEY,
      thread_id TEXT NOT NULL,
      chat_id TEXT NOT NULL,
    );
    "

  sqlight.exec(create_sent_messages_table, on: connection)
}

pub fn get_messages(
  connection: Connection,
  chat_id: String,
) -> Result(List(String), sqlight.Error) {
  sqlight.query(
    "SELECT thread_id FROM sent_messages WHERE chat_id = ?",
    on: connection,
    with: [sqlight.text(chat_id)],
    expecting: dynamic.string,
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
