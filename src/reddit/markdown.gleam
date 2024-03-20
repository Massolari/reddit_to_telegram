import gleam/io
import gleam/string
import gleam/regex.{type Regex, Match}
import gleam/result
import gleam/option.{type Option, None, Some}

pub fn reddit_to_telegram(markdown: String) -> String {
  markdown
  |> parse_helper("")
}

fn text_style_regex(delimiter: Delimiter) -> Regex {
  let #(start, end) = case delimiter {
    Same(d) -> #(d, d)
    Different(d1, d2) -> #(d1, d2)
  }

  let assert Ok(regex) = regex.from_string("^" <> start <> "(.*?)" <> end <> "")

  regex
}

fn link_regex() -> Regex {
  let assert Ok(regex) = regex.from_string("^\\[(.*?)\\]\\((.*?)\\)")

  regex
}

fn inline_code_regex() -> Regex {
  let assert Ok(regex) = regex.from_string("^`(.*?)`")

  regex
}

fn quote_regex() -> Regex {
  let assert Ok(regex) = regex.from_string("^(\n> [\\w\\W]*?)\n[^(> )]")

  regex
}

type CodeBlockDelimiter {
  Backticks
  Spaces
}

fn backtick_code_block_regex() -> Regex {
  let assert Ok(regex) = regex.from_string("^\n```([\\w\\W]*?)\n```")

  regex
}

fn spaces_code_block_regex() -> Regex {
  let assert Ok(regex) = regex.from_string("^(\n    [\\w\\W]*?)\n[^(    )]")

  regex
}

fn parse_helper(markdown: String, parsed: String) -> String {
  case markdown {
    "" -> parsed
    "**" <> _rest ->
      apply_style(
        delimiter: Same("**"),
        replace_tags: #("<b>", "</b>"),
        on: markdown,
        resulting: parsed,
      )
    "__" <> _rest ->
      apply_style(
        delimiter: Same("__"),
        replace_tags: #("<b>", "</b>"),
        on: markdown,
        resulting: parsed,
      )
    "*" <> _rest ->
      apply_style(
        delimiter: Same("*"),
        replace_tags: #("<i>", "</i>"),
        on: markdown,
        resulting: parsed,
      )
    "_" <> _rest ->
      apply_style(
        delimiter: Same("_"),
        replace_tags: #("<i>", "</i>"),
        on: markdown,
        resulting: parsed,
      )
    "[" <> _rest -> apply_link(markdown, parsed)
    "~~" <> _rest ->
      apply_style(
        delimiter: Same("~~"),
        replace_tags: #("<s>", "</s>"),
        on: markdown,
        resulting: parsed,
      )
    ">!" <> _rest ->
      apply_style(
        delimiter: Different(">!", "!<"),
        replace_tags: #("<span class=\"tg-spoiler\">", "</span>"),
        on: markdown,
        resulting: parsed,
      )
    "`" <> _rest -> apply_inline_code(markdown, parsed)
    "\n> " <> _rest -> apply_quote(markdown, parsed)
    "\n```" <> _rest -> apply_code_block(Backticks, markdown, parsed)
    "\n    " <> _rest -> apply_code_block(Spaces, markdown, parsed)
    _ ->
      case string.pop_grapheme(markdown) {
        Ok(#(first, rest)) -> parse_helper(rest, parsed <> first)
        Error(_) -> parsed
      }
  }
}

type Delimiter {
  Same(String)
  Different(String, String)
}

fn apply_style(
  delimiter delimiter: Delimiter,
  replace_tags style: #(String, String),
  on markdown: String,
  resulting parsed: String,
) -> String {
  let escape = string.replace(_, each: "*", with: "\\*")
  let delimiter_escaped = case delimiter {
    Same(d) -> Same(escape(d))
    Different(d1, d2) -> Different(escape(d1), escape(d2))
  }

  apply_formatting(
    text_style_regex(delimiter_escaped),
    fn(content) {
      case content {
        [Some(styled_content)] -> Some(style.0 <> styled_content <> style.1)
        _ -> None
      }
    },
    markdown,
    parsed,
  )
}

fn apply_link(markdown: String, parsed: String) -> String {
  let style_applied =
    replace(markdown, using: link_regex(), by: fn(content) {
      case content {
        [Some(text), Some(link)] ->
          Some("<a href=\"" <> link <> "\">" <> text <> "</a>")
        _ -> None
      }
    })

  case style_applied {
    Some(new_markdown) -> {
      case string.split_once(new_markdown, ">") {
        Ok(#(first, rest)) -> parse_helper(rest, parsed <> first <> ">")
        Error(Nil) -> {
          io.debug("No closing '>' found after applying link style.")

          parse_helper(new_markdown, parsed)
        }
      }
    }
    None -> parse_helper(string.drop_left(markdown, 1), parsed <> "[")
  }
}

fn apply_inline_code(markdown: String, parsed: String) -> String {
  let style_applied =
    replace(markdown, using: inline_code_regex(), by: fn(content) {
      case content {
        [Some(code)] -> Some("<code>" <> code <> "</code>")
        _ -> None
      }
    })

  case style_applied {
    Some(new_markdown) -> {
      case string.split_once(new_markdown, "</code>") {
        Ok(#(first, rest)) -> parse_helper(rest, parsed <> first <> "</code>")
        Error(Nil) -> {
          io.debug("No closing '</code>' found after applying inline code.")

          parse_helper(new_markdown, parsed)
        }
      }
    }
    None -> parse_helper(string.drop_left(markdown, 1), parsed <> "`")
  }
}

fn apply_quote(markdown: String, parsed: String) -> String {
  let style_applied = case regex.scan(with: quote_regex(), content: markdown) {
    [Match(content: _, submatches: [Some(quote)])] -> {
      let parsed_quote =
        quote
        // Get rid of the leading "\n> "
        |> string.drop_left(3)
        |> string.replace("\n> ", "\n")

      let replaced =
        string.replace(
          markdown,
          quote,
          "\n<blockquote>" <> parsed_quote <> "</blockquote>",
        )

      Some(replaced)
    }
    _ -> None
  }

  case style_applied {
    Some(new_markdown) -> {
      case string.split_once(new_markdown, "</blockquote>") {
        Ok(#(first, rest)) ->
          parse_helper(rest, parsed <> first <> "</blockquote>")
        Error(Nil) -> {
          io.debug(
            "No closing '</blockquote>' found after applying quote style.",
          )

          parse_helper(new_markdown, parsed)
        }
      }
    }
    None -> parse_helper(string.drop_left(markdown, 1), parsed)
  }
}

fn apply_code_block(
  delimiter: CodeBlockDelimiter,
  markdown: String,
  parsed: String,
) -> String {
  let #(regex, block_formatter) = case delimiter {
    Backticks -> #(backtick_code_block_regex(), fn(quote) {
      string.drop_left(quote, 1)
    })
    Spaces -> #(spaces_code_block_regex(), fn(quote) {
      quote
      |> string.drop_left(5)
      |> string.replace("\n    ", "\n")
    })
  }

  let style_applied = case regex.scan(with: regex, content: markdown) {
    [Match(content: content, submatches: [Some(code_block)])] -> {
      let parsed_quote = block_formatter(code_block)
      let replace_target = case delimiter {
        // Only the content between the backticks
        Backticks -> content
        // Include the leading 4 spaces in the replace target
        Spaces -> code_block
      }

      let replaced =
        string.replace(
          markdown,
          replace_target,
          "<pre>" <> parsed_quote <> "</pre>",
        )

      Some(replaced)
    }
    _ -> None
  }

  case style_applied {
    Some(new_markdown) -> {
      case string.split_once(new_markdown, "</pre>") {
        Ok(#(first, rest)) -> parse_helper(rest, parsed <> first <> "</pre>")
        Error(Nil) -> {
          io.debug("No closing '</pre>' found after applying code block style.")

          parse_helper(new_markdown, parsed)
        }
      }
    }
    None -> parse_helper(string.drop_left(markdown, 1), parsed)
  }
}

fn apply_formatting(
  regex: Regex,
  style: fn(List(Option(String))) -> Option(String),
  markdown: String,
  parsed: String,
) -> String {
  let style_applied = replace(markdown, using: regex, by: style)

  case style_applied {
    Some(new_markdown) -> parse_helper(new_markdown, parsed)
    None -> {
      let first_char =
        markdown
        |> string.first
        |> result.unwrap("")

      parse_helper(string.drop_left(markdown, 1), parsed <> first_char)
    }
  }
}

fn replace(
  text text: String,
  using regex: Regex,
  by replacement: fn(List(Option(String))) -> Option(String),
) -> Option(String) {
  case regex.scan(with: regex, content: text) {
    [Match(content: matched, submatches: submatches)] -> {
      submatches
      |> replacement
      |> option.map(string.replace(text, matched, _))
    }
    _ -> None
  }
}
