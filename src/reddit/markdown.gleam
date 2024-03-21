import gleam/io
import gleam/string
import gleam/regex.{type Regex, Match}
import gleam/result
import gleam/option.{type Option, None, Some}

type ParseResult {
  ParseResult(from: String, result: String)
}

type CodeBlockDelimiter {
  Backticks
  Spaces
}

type TextStyleDelimiter {
  Same(String)
  Different(String, String)
}

pub fn reddit_to_telegram(markdown: String) -> String {
  let parsing =
    markdown
    |> ParseResult(result: "")
    |> parse

  parsing.result
}

fn parse(parsing: ParseResult) -> ParseResult {
  case parsing.from {
    "**" <> _rest ->
      parsing
      |> apply_style(delimiter: Same("**"), replace_tags: #("<b>", "</b>"))
      |> parse

    "__" <> _rest ->
      parsing
      |> apply_style(delimiter: Same("__"), replace_tags: #("<b>", "</b>"))
      |> parse

    "*" <> _rest ->
      parsing
      |> apply_style(delimiter: Same("*"), replace_tags: #("<i>", "</i>"))
      |> parse

    "_" <> _rest ->
      parsing
      |> apply_style(delimiter: Same("_"), replace_tags: #("<i>", "</i>"))
      |> parse

    "[" <> _rest ->
      parsing
      |> apply_link
      |> parse

    "~~" <> _rest ->
      parsing
      |> apply_style(delimiter: Same("~~"), replace_tags: #("<s>", "</s>"))
      |> parse

    ">!" <> _rest ->
      parsing
      |> apply_style(delimiter: Different(">!", "!<"), replace_tags: #(
        "<span class=\"tg-spoiler\">",
        "</span>",
      ))
      |> parse

    "`" <> _rest ->
      parsing
      |> apply_inline_code
      |> parse

    "\n> " <> _rest ->
      parsing
      |> apply_quote
      |> parse

    "\n```" <> _rest ->
      parsing
      |> apply_code_block(Backticks)
      |> parse

    "\n    " <> _rest ->
      parsing
      |> apply_code_block(Spaces)
      |> parse

    _ ->
      case string.pop_grapheme(parsing.from) {
        Ok(#(first, rest)) ->
          ParseResult(from: rest, result: parsing.result <> first)
          |> parse
        Error(_) -> parsing
      }
  }
}

fn apply_style(
  parsing: ParseResult,
  delimiter delimiter: TextStyleDelimiter,
  replace_tags style: #(String, String),
) -> ParseResult {
  let escape = string.replace(_, each: "*", with: "\\*")
  let delimiter_escaped = case delimiter {
    Same(d) -> Same(escape(d))
    Different(d1, d2) -> Different(escape(d1), escape(d2))
  }

  apply_formatting(parsing, text_style_regex(delimiter_escaped), fn(content) {
    case content {
      [Some(styled_content)] -> Some(style.0 <> styled_content <> style.1)
      _ -> None
    }
  })
}

fn apply_link(parsing: ParseResult) -> ParseResult {
  let style_applied =
    replace(parsing.from, using: link_regex(), by: fn(content) {
      case content {
        [Some(text), Some(link)] ->
          Some("<a href=\"" <> link <> "\">" <> text <> "</a>")
        _ -> None
      }
    })

  case style_applied {
    Some(new_markdown) -> {
      case string.split_once(new_markdown, ">") {
        Ok(#(first, rest)) ->
          ParseResult(from: rest, result: parsing.result <> first <> ">")
        Error(Nil) -> {
          io.debug("No closing '>' found after applying link style.")

          ParseResult(from: new_markdown, result: parsing.result)
        }
      }
    }
    None ->
      ParseResult(string.drop_left(parsing.from, 1), parsing.result <> "[")
  }
}

fn apply_inline_code(parsing: ParseResult) -> ParseResult {
  let style_applied =
    replace(parsing.from, using: inline_code_regex(), by: fn(content) {
      case content {
        [Some(code)] -> Some("<code>" <> code <> "</code>")
        _ -> None
      }
    })

  case style_applied {
    Some(new_markdown) -> {
      case string.split_once(new_markdown, "</code>") {
        Ok(#(first, rest)) ->
          ParseResult(from: rest, result: parsing.result <> first <> "</code>")
        Error(Nil) -> {
          io.debug("No closing '</code>' found after applying inline code.")

          ParseResult(from: new_markdown, result: parsing.result)
        }
      }
    }
    None ->
      ParseResult(
        from: string.drop_left(parsing.from, 1),
        result: parsing.result <> "`",
      )
  }
}

fn apply_quote(parsing: ParseResult) -> ParseResult {
  let style_applied = case
    regex.scan(with: quote_regex(), content: parsing.from)
  {
    [Match(content: _, submatches: [Some(quote)])] -> {
      let parsed_quote =
        quote
        // Get rid of the leading "\n> "
        |> string.drop_left(3)
        |> string.replace("\n> ", "\n")

      let replaced =
        string.replace(
          parsing.from,
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
          ParseResult(
            from: rest,
            result: parsing.result <> first <> "</blockquote>",
          )
        Error(Nil) -> {
          io.debug(
            "No closing '</blockquote>' found after applying quote style.",
          )

          ParseResult(from: new_markdown, result: parsing.result)
        }
      }
    }
    None ->
      ParseResult(
        from: string.drop_left(parsing.from, 1),
        result: parsing.result,
      )
  }
}

fn apply_code_block(
  parsing: ParseResult,
  delimiter: CodeBlockDelimiter,
) -> ParseResult {
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

  let style_applied = case regex.scan(with: regex, content: parsing.from) {
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
          parsing.from,
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
        Ok(#(first, rest)) ->
          ParseResult(from: rest, result: parsing.result <> first <> "</pre>")
        Error(Nil) -> {
          io.debug("No closing '</pre>' found after applying code block style.")

          ParseResult(from: new_markdown, result: parsing.result)
        }
      }
    }
    None ->
      ParseResult(
        from: string.drop_left(parsing.from, 1),
        result: parsing.result,
      )
  }
}

fn apply_formatting(
  parsing: ParseResult,
  regex: Regex,
  style: fn(List(Option(String))) -> Option(String),
) -> ParseResult {
  let style_applied = replace(parsing.from, using: regex, by: style)

  case style_applied {
    Some(new_markdown) ->
      ParseResult(from: new_markdown, result: parsing.result)
    None -> {
      let first_char =
        parsing.from
        |> string.first
        |> result.unwrap("")

      ParseResult(
        from: string.drop_left(parsing.from, 1),
        result: parsing.result <> first_char,
      )
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

fn text_style_regex(delimiter: TextStyleDelimiter) -> Regex {
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

fn backtick_code_block_regex() -> Regex {
  let assert Ok(regex) = regex.from_string("^\n```([\\w\\W]*?)\n```")

  regex
}

fn spaces_code_block_regex() -> Regex {
  let assert Ok(regex) = regex.from_string("^(\n    [\\w\\W]*?)\n[^(    )]")

  regex
}
