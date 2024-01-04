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

    # Loop until blank line received
    line = "."
    prev_line = ""
    while (line != "")
    {
        # Read a line
        if (prev_line == "") {
            line = readline("lua > ")
        } else {
            # If we're building up multi-line input, show a special prompt
            line = readline(" +    ")
            if (line == "") {
                # Exit multi-line if nothing entered
                line = "."
                prev_line = ""
                next
            } else {
                # Otherwise build up input
                line = paste(prev_line, line)
            }
        }

        # Try to execute the line, capturing any error
        err = tryCatch(lua(line, L = L), error = function(e) e)

        # If there is an error:
        if (!is.null(err)) {
            if (grepl("'<eof>'$", err$message)) {
                # Unexpected end of input: try to gather more input
                prev_line = line
                next
            } else if (crayon_available) {
                # Other error: show error message in red if possible
                cat(crayon::red(err$message), "\n")
            } else {
                # Or just in normal colour if not possible
                cat(err$message, "\n")
            }
        }
        prev_line = ""
    }
}
