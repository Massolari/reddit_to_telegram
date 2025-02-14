import gleeunit/should
import reddit.{Post}

const post = Post(
  id: "a",
  title: "foo",
  text: "bar",
  score: 10,
  media: [],
  external_url: Error(Nil),
  link_flair_text: "foo",
)

pub fn short_link_test() {
  post
  |> reddit.short_link
  |> should.equal("https://redd.it/" <> post.id)
}
