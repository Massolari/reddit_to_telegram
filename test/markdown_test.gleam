import gleeunit/should
import reddit/markdown

pub fn empty_test() {
  ""
  |> markdown.reddit_to_telegram
  |> should.equal("")
}

pub fn simple_text_test() {
  "Hello, World!"
  |> markdown.reddit_to_telegram
  |> should.equal("Hello, World!")
}

pub fn bold_text_test() {
  "Hello, my **friend**!
My __good__ friend!"
  |> markdown.reddit_to_telegram
  |> should.equal("Hello, my <b>friend</b>!\nMy <b>good</b> friend!")
}

pub fn italic_text_test() {
  "Hello, my *friend*!
My _good_ friend!"
  |> markdown.reddit_to_telegram
  |> should.equal("Hello, my <i>friend</i>!\nMy <i>good</i> friend!")
}

pub fn bold_italic_nested_text_test() {
  "Hello, **my *friend***!
My __good _friend___!"
  |> markdown.reddit_to_telegram
  |> should.equal(
    "Hello, <b>my <i>friend</b></i>!\nMy <b>good <i>friend</b></i>!",
  )
}

pub fn bold_italic_text_test() {
  "Hello, ***my friend***!
My ___good friend___!"
  |> markdown.reddit_to_telegram
  |> should.equal(
    "Hello, <b><i>my friend</b></i>!\nMy <b><i>good friend</b></i>!",
  )
}

pub fn simple_link_test() {
  "Check out [this link](https://example.com)!"
  |> markdown.reddit_to_telegram
  |> should.equal("Check out <a href=\"https://example.com\">this link</a>!")
}

pub fn bold_italic_link_test() {
  "Check out [**this** _link_](https://example.com/some_cool_path)! It's **amazing**!"
  |> markdown.reddit_to_telegram
  |> should.equal(
    "Check out <a href=\"https://example.com/some_cool_path\"><b>this</b> <i>link</i></a>! It's <b>amazing</b>!",
  )
}

pub fn strikethrough_test() {
  "Hello, my ~~friend~~!"
  |> markdown.reddit_to_telegram
  |> should.equal("Hello, my <s>friend</s>!")
}

pub fn spoiler_test() {
  "Hello, my >!friend!<!"
  |> markdown.reddit_to_telegram
  |> should.equal("Hello, my <span class=\"tg-spoiler\">friend</span>!")
}

pub fn inline_code_test() {
  "Check this: `print(\"*Hello*, _World_!\")`"
  |> markdown.reddit_to_telegram
  |> should.equal("Check this: <code>print(\"*Hello*, _World_!\")</code>")
}

pub fn quote_test() {
  "A citation\n> Be brave!\n> No matter what\nMotivating!"
  |> markdown.reddit_to_telegram
  |> should.equal(
    "A citation\n<blockquote>Be brave!\nNo matter what</blockquote>\nMotivating!",
  )
}

pub fn backtick_code_block_test() {
  "Some code:\n```\nconst value_to_print = \"World\"\nprint(`Hello, ${value_to_print}!`)\n```Cool"
  |> markdown.reddit_to_telegram
  |> should.equal(
    "Some code:<pre>const value_to_print = \"World\"\nprint(`Hello, ${value_to_print}!`)</pre>Cool",
  )
}

pub fn spaces_code_block_test() {
  "Some code:\n    const value_to_print = \"World\"\n    print(`Hello, ${value_to_print}!`)\nAwesome!"
  |> markdown.reddit_to_telegram
  |> should.equal(
    "Some code:<pre>const value_to_print = \"World\"\nprint(`Hello, ${value_to_print}!`)</pre>\nAwesome!",
  )
}
