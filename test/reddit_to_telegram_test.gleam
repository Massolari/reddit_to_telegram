import gleam/int
import gleam/list
import gleam/option.{None}
import gleeunit
import gleeunit/should
import reddit
import reddit_to_telegram

fn test_posts() -> List(reddit.Post) {
  list.range(1, 10)
  |> list.map(fn(i) {
    let id = int.to_string(i)
    reddit.Post(
      id:,
      title: "a" <> id,
      text: "b" <> id,
      score: i * 10,
      media: [],
      external_url: None,
      link_flair_text: None,
    )
  })
}

pub fn main() {
  gleeunit.main()
}

// gleeunit test functions end in `_test`
pub fn filter_sent_post_test() {
  let filtered_posts = list.drop(test_posts(), 3)
  test_posts()
  |> reddit_to_telegram.filter_sent_posts(["1", "2", "3"])
  |> should.equal(filtered_posts)
}

pub fn filter_low_score_test() {
  let filtered_posts = list.drop(test_posts(), 5)
  test_posts()
  |> reddit_to_telegram.filter_low_score(60)
  |> should.equal(filtered_posts)
}
