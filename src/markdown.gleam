import gleam/list
import gleam/string
import gleam/regex
import gleam/option.{type Option, None, Some}

pub fn reddit_to_telegram(reddit_markdown: String) -> String {
  reddit_markdown
  |> format_code_blocks
  |> string.split("\n")
  |> list.map(convert_line)
  |> string.join("\n")
}

fn format_code_blocks(text: String) -> String {
  replace_regex(text, using: "```(.*)```", by: fn(content) {
    case content {
      [Some(content)] -> Some("<pre>" <> content <> "</pre>")
      _ -> None
    }
  })
}

fn convert_line(line: String) -> String {
  line
  // Links
  |> replace_regex(using: "\\[(.*?)\\]\\((.*?)\\)", by: fn(content) {
    case content {
      [Some(text), Some(link)] ->
        Some("<a href=\"" <> link <> "\">" <> text <> "</a>")
      _ -> None
    }
  })
  // Bold-italic
  |> replace_regex(
    using: "(?:\\*{3}(.*)\\*{3})|(?:_{3}(.*)_{3})",
    by: fn(content) {
      case content {
        [Some(content)] -> Some("<b><i>" <> content <> "</i></b>")
        [_, Some(content)] -> Some("<b><i>" <> content <> "</i></b>")
        _ -> None
      }
    },
  )
  // Bold
  |> replace_regex(
    using: "(?:\\*{2}(.*)\\*{2})|(?:_{2}(.*)_{2})",
    by: fn(content) {
      case content {
        [Some(content)] -> Some("<b>" <> content <> "</b>")
        [_, Some(content)] -> Some("<b>" <> content <> "</b>")
        _ -> None
      }
    },
  )
  // Italic
  |> replace_regex(using: "[_*](.*)[_*]", by: fn(content) {
    case content {
      [Some(content)] -> Some("<i>" <> content <> "</i>")
      _ -> None
    }
  })
  // Strikethrough
  |> replace_regex(using: "~{2}(.*)~{2}", by: fn(content) {
    case content {
      [Some(content)] -> Some("<s>" <> content <> "</s>")
      _ -> None
    }
  })
  // Spoiler
  |> replace_regex(using: ">!(.*)!<", by: fn(content) {
    case content {
      [Some(content)] -> Some("<tg-spoiler>" <> content <> "</tg-spoiler>")
      _ -> None
    }
  })
}

fn replace_regex(
  text text: String,
  using pattern: String,
  by replacement: fn(List(Option(String))) -> Option(String),
) -> String {
  let assert Ok(regex) = regex.from_string(pattern)

  let matches = regex.scan(with: regex, content: text)

  use new_text, match <- list.fold(over: matches, from: text)

  let new_chunk = replacement(match.submatches)

  case new_chunk {
    Some(chunk) -> string.replace(new_text, match.content, chunk)
    None -> new_text
  }
}
// **Douglas** => <b>Douglas</b>
// /\*\*(.*)\*\*/ => <b>$1</b>
