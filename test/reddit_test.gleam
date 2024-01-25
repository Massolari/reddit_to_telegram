import reddit.{Post}
import gleeunit/should

const post = Post(
  id: "a",
  title: "foo",
  text: "bar",
  score: 10,
  media: Error(Nil),
  external_url: Error(Nil),
)

pub fn short_link_test() {
  post
  |> reddit.short_link
  |> should.equal("https://redd.it/" <> post.id)
}
