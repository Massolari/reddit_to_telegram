import gleam/list

pub type AppResult(a) {
  AppOk(a)
  AppWarning(String)
  AppError(String)
}

pub fn try(
  result: Result(a, String),
  fun: fn(a) -> AppResult(b),
) -> AppResult(b) {
  case result {
    Ok(value) -> fun(value)
    Error(error) -> AppError(error)
  }
}

pub fn partition(
  app_results: List(AppResult(a)),
) -> #(List(String), List(String)) {
  list.fold(app_results, #([], []), fn(acc, app_result) {
    let #(warnings, errors) = acc

    case app_result {
      AppOk(_) -> acc
      AppWarning(warning) -> #(list.append(warnings, [warning]), errors)
      AppError(error) -> #(warnings, list.append(errors, [error]))
    }
  })
}
