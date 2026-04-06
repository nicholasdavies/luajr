# Written by AI.
#
# get_rapi(name)
# Look up an R C API function/macro/variable by name:
#  1. Check which API index it appears in (R-exts.html)
#  2. Search R headers for its declaration
#  3. Return the C signature, or report if it's a macro / not found

get_rapi <- function(name) {
    # Paths
    rexts_path <- file.path(R.home("doc"), "manual", "R-exts.html")
    include_dir <- R.home("include")

    if (!file.exists(rexts_path)) stop("Cannot find R-exts.html at ", rexts_path)
    if (!dir.exists(include_dir)) stop("Cannot find R include dir at ", include_dir)

    # --- Step 1: Check API indexes ---
    html <- readLines(rexts_path, warn = FALSE)
    full <- paste(html, collapse = "\n")

    # Extract index sections
    api_section <- regmatches(full, regexpr(
        '(?s)<h2[^>]*id="API-index-1".*?</table>\\s*</div>', full, perl = TRUE))
    exp_section <- regmatches(full, regexpr(
        '(?s)<h2[^>]*id="Experimental-API-index-1".*?</table>\\s*</div>', full, perl = TRUE))
    emb_section <- regmatches(full, regexpr(
        '(?s)<h2[^>]*id="Embedding-API-index-1".*?</table>\\s*</div>', full, perl = TRUE))

    # Search for name in each index (encoded with _005f for underscores)
    name_escaped <- gsub("_", "_005f", name, fixed = TRUE)
    pattern <- paste0("<code>", name_escaped, "</code>|<code>", name, "</code>")

    in_api <- length(api_section) > 0 && grepl(pattern, api_section, perl = TRUE)
    in_exp <- length(exp_section) > 0 && grepl(pattern, exp_section, perl = TRUE)
    in_emb <- length(emb_section) > 0 && grepl(pattern, emb_section, perl = TRUE)

    index_name <- if (in_api) "API"
        else if (in_exp) "Experimental API"
        else if (in_emb) "Embedding API"
        else "none"

    cat(sprintf("Index: %s\n", index_name))

    # --- Step 2: Search R headers for declaration ---
    headers <- list.files(include_dir, pattern = "\\.h$", recursive = TRUE,
                          full.names = TRUE)

    # Names to search for: the given name, plus the unprefixed form if Rf_
    search_names <- name
    if (startsWith(name, "Rf_")) {
        search_names <- c(name, sub("^Rf_", "", name))
    }

    found_func <- list()
    found_macro <- list()
    found_var <- list()

    for (sname in search_names) {
        # Patterns to search for:
        #  - Function declaration: return_type name(
        #  - Macro: #define name
        #  - Variable: extern type name;
        func_pattern <- paste0("\\b\\(?", sname, "\\)?\\s*\\(")
        macro_pattern <- paste0("^\\s*#\\s*define\\s+", sname, "\\b")
        var_pattern <- paste0("^\\s*(extern|LibExtern)\\b.*\\b", sname, "\\s*[;\\[]")

        for (hdr in headers) {
            lines <- readLines(hdr, warn = FALSE)
            rel <- sub(paste0(include_dir, "/"), "", hdr, fixed = TRUE)

            # Check for function declarations
            func_hits <- grep(func_pattern, lines, perl = TRUE)
            for (i in func_hits) {
                line <- lines[i]
                # Skip if this is actually a #define
                if (grepl("^\\s*#", line)) next
                # Skip if inside a comment
                if (grepl("^\\s*\\*|^\\s*/[/*]", line)) next

                # Try to grab full signature (may span multiple lines)
                sig <- line
                j <- i
                while (!grepl("\\)", sig) && j < min(i + 10, length(lines))) {
                    j <- j + 1
                    sig <- paste(sig, trimws(lines[j]))
                }
                # Clean up
                sig <- trimws(sig)
                sig <- gsub("\\s+", " ", sig)
                # Trim to closing paren + semicolon
                sig <- sub("\\)\\s*;.*", ");", sig)

                found_func[[length(found_func) + 1]] <- list(
                    header = rel, line = i, signature = sig,
                    searched_as = sname
                )
            }

            # Check for macro definitions
            macro_hits <- grep(macro_pattern, lines, perl = TRUE)
            for (i in macro_hits) {
                # Gather continuation lines
                sig <- lines[i]
                j <- i
                while (grepl("\\\\\\s*$", sig) && j < min(i + 20, length(lines))) {
                    j <- j + 1
                    sig <- paste(sub("\\\\\\s*$", "", sig), trimws(lines[j]))
                }
                sig <- trimws(sig)
                sig <- gsub("\\s+", " ", sig)

                found_macro[[length(found_macro) + 1]] <- list(
                    header = rel, line = i, definition = sig,
                    searched_as = sname
                )
            }

            # Check for extern variable declarations
            var_hits <- grep(var_pattern, lines, perl = TRUE)
            for (i in var_hits) {
                line <- lines[i]
                if (grepl("^\\s*#", line)) next
                if (grepl("^\\s*\\*|^\\s*/[/*]", line)) next
                sig <- trimws(line)
                sig <- gsub("\\s+", " ", sig)

                found_var[[length(found_var) + 1]] <- list(
                    header = rel, line = i, declaration = sig,
                    searched_as = sname
                )
            }
        }

        # If we found results with this name, don't try the next variant
        if (length(found_func) > 0 || length(found_macro) > 0 || length(found_var) > 0) break
    }

    # --- Step 3: Report ---
    if (length(found_func) > 0) {
        cat("Function declaration(s):\n")
        for (f in found_func) {
            note <- if (f$searched_as != name) sprintf(" (found as %s)", f$searched_as) else ""
            cat(sprintf("  %s:%d%s\n  %s\n\n", f$header, f$line, note, f$signature))
        }
    }

    if (length(found_macro) > 0) {
        cat("Macro definition(s):\n")
        for (m in found_macro) {
            note <- if (m$searched_as != name) sprintf(" (found as %s)", m$searched_as) else ""
            cat(sprintf("  %s:%d%s\n  %s\n\n", m$header, m$line, note, m$definition))
        }
    }

    if (length(found_var) > 0) {
        cat("Variable declaration(s):\n")
        for (v in found_var) {
            note <- if (v$searched_as != name) sprintf(" (found as %s)", v$searched_as) else ""
            cat(sprintf("  %s:%d%s\n  %s\n\n", v$header, v$line, note, v$declaration))
        }
    }

    if (length(found_func) == 0 && length(found_macro) == 0 && length(found_var) == 0) {
        cat("Not found in R headers.\n")
    }

    invisible(list(index = index_name, functions = found_func, macros = found_macro, variables = found_var))
}


# add_rapi(name)
# Look up an R C API function or variable and, if found, add it to inst/Lua/R.lua.
add_rapi <- function(name) {
    r_lua_path <- file.path("inst", "Lua", "R.lua")
    if (!file.exists(r_lua_path)) stop("Cannot find ", r_lua_path)

    # Look up the function
    info <- get_rapi(name)

    # Must be a function, not (only) a macro
    if (length(info$functions) == 0) {
        if (length(info$macros) > 0) {
            cat(name, "is a macro, not a function. Cannot add to R.lua.\n")
        } else {
            cat(name, "not found in R headers.\n")
        }
        return(invisible(NULL))
    }

    # If multiple declarations, let user pick
    func <- NULL
    if (length(info$functions) == 1) {
        func <- info$functions[[1]]
    } else {
        cat("Multiple declarations found:\n")
        for (i in seq_along(info$functions)) {
            cat(sprintf("  [%d] %s:%d  %s\n", i,
                info$functions[[i]]$header, info$functions[[i]]$line,
                info$functions[[i]]$signature))
        }
        choice <- as.integer(readline("Choose declaration [1]: "))
        if (is.na(choice)) choice <- 1L
        func <- info$functions[[choice]]
    }

    sig <- func$signature

    # Strip the macro-suppression parens from name: "SEXP (STRING_ELT)(" -> "SEXP STRING_ELT("
    sig <- gsub(paste0("\\(", name, "\\)"), name, sig)

    cat("\nSignature to add:\n  ", sig, "\n")

    # Read current R.lua
    lines <- readLines(r_lua_path)

    # Check if already present
    if (any(grepl(paste0("\\b", name, "\\b"), lines))) {
        cat(name, "is already in R.lua.\n")
        return(invisible(NULL))
    }

    # Prompt user
    ok <- readline("Add to R.lua? [Y/n] ")
    if (tolower(ok) %in% c("n", "no")) {
        cat("Skipped.\n")
        return(invisible(NULL))
    }

    # --- Insert ffi.cdef declaration ---
    cdef_marker <- "// === R API declarations ==="
    cdef_end <- "]]"
    cdef_start_idx <- grep(cdef_marker, lines, fixed = TRUE)
    cdef_end_idx <- which(lines == cdef_end & seq_along(lines) > cdef_start_idx)[1]

    # Gather existing declarations between markers
    existing_decls <- lines[rlang::seq2(cdef_start_idx + 1, cdef_end_idx - 1)]
    existing_decls <- existing_decls[nzchar(trimws(existing_decls))]

    # Add new declaration and sort
    new_decl <- sig
    all_decls <- c(existing_decls, new_decl)
    # Sort by function name (extract name for sorting)
    decl_names <- sub("^.*?\\b([A-Za-z_][A-Za-z0-9_]*)\\s*\\(.*", "\\1", all_decls)
    all_decls <- all_decls[order(decl_names)]

    # --- Insert binding ---
    bind_marker <- "-- === R API bindings ==="
    bind_start_idx <- grep(bind_marker, lines, fixed = TRUE)
    return_idx <- grep("^return R$", lines)

    # Gather existing bindings
    existing_binds <- lines[rlang::seq2(bind_start_idx + 1, return_idx - 1)]
    existing_binds <- existing_binds[nzchar(trimws(existing_binds))]

    # Create binding line
    new_bind <- sprintf("R.%s = C.%s", name, name)
    all_binds <- c(existing_binds, new_bind)
    # Sort by name
    bind_names <- sub("^R\\.", "", sub(" =.*", "", all_binds))
    all_binds <- all_binds[order(bind_names)]

    # --- Rebuild file ---
    # Structure: [preamble ... marker] [decls] []] ... bind_marker] [binds] [\n] [return R ...]
    new_lines <- c(
        lines[1:cdef_start_idx],          # up to and including cdef marker
        all_decls,                          # sorted declarations
        lines[cdef_end_idx:bind_start_idx], # ]] through bind marker
        all_binds,                          # sorted bindings
        "",
        lines[return_idx:length(lines)]     # return R to end
    )

    writeLines(new_lines, r_lua_path)
    cat("Added", name, "to R.lua.\n")
    invisible(sig)
}
