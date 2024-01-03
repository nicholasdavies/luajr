#' Run an interactive LuaJIT shell
#'
#' When in interactive mode, provides a basic read-eval-print loop with LuaJIT.
#'
#' @inheritParams lua
#'
#' @return Nothing.
#'
#' @export
lua_shell = function(L = NULL)
{
    # Short-circuit if not in interactive mode
    if (!interactive())
        return (invisible())

    # See if crayon package is available
    crayon_available = requireNamespace("crayon", quietly = TRUE);

    # Error reporting
    do_error = function(e)
    {
        if (crayon_available) {
            cat(crayon::red(e$message), "\n")
        } else {
            cat(e$message, "\n")
        }
    }

    # Loop until blank line received
    line = "."
    while (line != "")
    {
        # Read a line
        line = readline("lua > ")

        # Try to execute the line, print error message if error thrown
        tryCatch(lua(line, L = L), error = do_error)
    }
}
