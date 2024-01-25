import gleeunit/should
import telegram
import reddit

const reddit_post = reddit.Post(
  id: "1",
  title: "Post title",
  text: "Post text",
  score: 10,
  media: Error(Nil),
  external_url: Error(Nil),
)

pub fn chat_id_as_link_test() {
  "a"
  |> telegram.chat_id_as_link
  |> should.equal("[a](a)")
}

pub fn media_caption_test() {
  reddit_post
  |> telegram.media_caption("a")
  |> should.equal(
    "Post title
https://redd.it/1

[a](a)",
  )
}
