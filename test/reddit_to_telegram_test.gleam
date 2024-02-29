import gleeunit
import gleam/list
import gleeunit/should
import reddit_to_telegram
import reddit

const test_posts = [
  reddit.Post(
    id: "1",
    title: "a",
    text: "b",
    score: 10,
    media: [],
    external_url: Error(Nil),
  ),
  reddit.Post(
    id: "2",
    title: "a2",
    text: "b2",
    score: 20,
    media: [],
    external_url: Error(Nil),
  ),
  reddit.Post(
    id: "3",
    title: "a3",
    text: "b3",
    score: 30,
    media: [],
    external_url: Error(Nil),
  ),
  reddit.Post(
    id: "4",
    title: "a4",
    text: "b4",
    score: 40,
    media: [],
    external_url: Error(Nil),
  ),
  reddit.Post(
    id: "5",
    title: "a5",
    text: "b5",
    score: 50,
    media: [],
    external_url: Error(Nil),
  ),
  reddit.Post(
    id: "6",
    title: "a6",
    text: "b6",
    score: 60,
    media: [],
    external_url: Error(Nil),
  ),
  reddit.Post(
    id: "7",
    title: "a7",
    text: "b7",
    score: 70,
    media: [],
    external_url: Error(Nil),
  ),
  reddit.Post(
    id: "8",
    title: "a8",
    text: "b8",
    score: 80,
    media: [],
    external_url: Error(Nil),
  ),
  reddit.Post(
    id: "9",
    title: "a9",
    text: "b9",
    score: 90,
    media: [],
    external_url: Error(Nil),
  ),
  reddit.Post(
    id: "10",
    title: "a10",
    text: "b10",
    score: 100,
    media: [],
    external_url: Error(Nil),
  ),
]

pub fn main() {
  gleeunit.main()
}

// gleeunit test functions end in `_test`
pub fn filter_sent_post_test() {
  let filtered_posts = list.drop(test_posts, 3)
  test_posts
  |> reddit_to_telegram.filter_sent_posts(["1", "2", "3"])
  |> should.equal(filtered_posts)
}

pub fn filter_low_score_test() {
  let filtered_posts = list.drop(test_posts, 5)
  test_posts
  |> reddit_to_telegram.filter_low_score(60)
  |> should.equal(filtered_posts)
}
