import gleam/option.{None}
import gleeunit/should
import reddit
import telegram

const reddit_post = reddit.Post(
  id: "1",
  title: "Post title",
  text: "Post text",
  score: 10,
  media: [],
  external_url: None,
  link_flair_text: None,
)

pub fn media_caption_test() {
  reddit_post
  |> telegram.media_caption("a")
  |> should.equal(
    "Post title

https://redd.it/1

a",
  )
}
