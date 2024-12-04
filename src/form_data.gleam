import gleam/bytes_tree.{type BytesTree}
import gleam/dynamic
import gleam/list

@external(erlang, "hackney_multipart", "encode_form")
fn encode_form(
  parts: List(dynamic.Dynamic),
  boundary: String,
) -> #(BytesTree, Int)

@external(erlang, "hackney_multipart", "boundary")
fn generate_boundary() -> String

pub type Entry {
  File(path: String, name: String, extra_headers: List(#(String, String)))
  Text(name: String, value: String)
}

pub type FormData {
  FormData(body: BytesTree, length: Int, boundary: String)
}

pub fn new(parts: List(Entry)) -> FormData {
  let boundary = generate_boundary()

  let #(body, length) =
    parts
    |> list.map(fn(part) {
      case part {
        File(path, name, extra_headers) ->
          dynamic.from(File(
            path: path,
            name: name,
            extra_headers: extra_headers,
          ))
        Text(name, value) -> dynamic.from(#(name, value))
      }
    })
    |> encode_form(boundary)

  FormData(body: body, length: length, boundary: boundary)
}
