import birdie
import gleam/json
import gleam/option.{None}
import gleam/string
import gleeunit/should
import reddit.{Post}
import simplifile

const post = Post(
  id: "a",
  title: "foo",
  text: "bar",
  score: 10,
  media: [],
  external_url: None,
  link_flair_text: None,
)

pub fn short_link_test() {
  post
  |> reddit.short_link
  |> should.equal("https://redd.it/" <> post.id)
}

pub fn posts_decoder_test() {
  let assert Ok(json) = simplifile.read("./test/sample_reddit_threads.json")
  json
  |> json.parse(reddit.posts_decoder())
  |> string.inspect
  |> birdie.snap(title: "Posts decoder")
}
