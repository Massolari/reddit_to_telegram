import birdie
import bridge.{Bridge}
import gleam/json
import gleam/string
import gleeunit/should
import reddit
import simplifile

const sample_bridge = Bridge(
  subreddit: "test",
  reddit_sort: reddit.Hot,
  telegram_channel: "@test",
  minimum_upvotes: 10,
  flair_include: ["test1", "test2"],
  flair_exclude: ["exclude1"],
)

pub fn bridges_decoder_test() {
  let assert Ok(json) = simplifile.read("./test/sample_bridges.json")
  json
  |> json.parse(bridge.bridges_decoder())
  |> string.inspect
  |> birdie.snap(title: "Bridges decoder")
}

pub fn bridge_decoder_test() {
  let json =
    "{
    \"subreddit\": \"test\",
    \"reddit_sort\": \"hot\",
    \"telegram_channel\": \"@test\",
    \"minimum_upvotes\": 10,
    \"flair_include\": [\"test1\", \"test2\"],
    \"flair_exclude\": [\"exclude1\"]
  }"

  let assert Ok(decoded) =
    json
    |> json.parse(bridge.bridge_decoder())

  decoded
  |> should.equal(sample_bridge)
}

pub fn invalid_sort_test() {
  let json =
    "{
    \"subreddit\": \"test\",
    \"reddit_sort\": \"invalid\",
    \"telegram_channel\": \"@test\"
  }"

  json
  |> json.parse(bridge.bridge_decoder())
  |> should.be_error
}
