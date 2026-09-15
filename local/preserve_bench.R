# Compare ways of protecting R objects held by Lua.
# See "R object protection: release cost and a leak" in local/devnotes.txt.
#
# Usage, from the luajr directory: Rscript local/preserve_bench.R <scheme> <K>
#   scheme: R (R_PreserveObject), list (doubly-linked cons list), slots (VECSXP + free list)
#   K: number of long-lived protected objects
# Set R_HASH_PRECIOUS=TRUE in the environment with scheme R to test R's hashed
# precious list.

args = commandArgs(trailingOnly = TRUE)
scheme = args[1]
K = args[2]
M = "200000"
lag = "1000"

fill = function(code)
{
    code = gsub("@SCHEME@", scheme, code, fixed = TRUE)
    code = gsub("@K@", K, code, fixed = TRUE)
    code = gsub("@M@", M, code, fixed = TRUE)
    code = gsub("@LAG@", lag, code, fixed = TRUE)
    return (code)
}

setup = r"---(
local ffi = require("ffi")
local decls = {
    "SEXP Rf_allocVector(unsigned int, ptrdiff_t);",
    "SEXP Rf_cons(SEXP, SEXP);",
    "SEXP CAR(SEXP);",
    "SEXP CDR(SEXP);",
    "SEXP SETCAR(SEXP, SEXP);",
    "SEXP SETCDR(SEXP, SEXP);",
    "void SET_TAG(SEXP, SEXP);",
    "SEXP Rf_protect(SEXP);",
    "void Rf_unprotect(int);",
    "void R_PreserveObject(SEXP);",
    "void R_ReleaseObject(SEXP);",
    "SEXP SET_VECTOR_ELT(SEXP, ptrdiff_t, SEXP);",
    "SEXP VECTOR_ELT(SEXP, ptrdiff_t);",
    "extern SEXP R_NilValue;"
}
for _, d in ipairs(decls) do
    pcall(ffi.cdef, d)
end
local C = ffi.C
local nil_value = C.R_NilValue
local scheme = "@SCHEME@"

if scheme == "R" then
    PRESERVE = function(x)
        C.R_PreserveObject(x)
        return x
    end
    RELEASE = function(x)
        C.R_ReleaseObject(x)
    end
elseif scheme == "list" then
    local head = C.Rf_cons(nil_value, C.Rf_cons(nil_value, nil_value))
    C.R_PreserveObject(head)
    PRESERVE = function(x)
        C.Rf_protect(x)
        local nxt = C.CDR(head)
        local cell = C.Rf_protect(C.Rf_cons(head, nxt))
        C.SET_TAG(cell, x)
        C.SETCDR(head, cell)
        C.SETCAR(nxt, cell)
        C.Rf_unprotect(2)
        return cell
    end
    RELEASE = function(cell)
        local prev = C.CAR(cell)
        local nxt = C.CDR(cell)
        C.SETCDR(prev, nxt)
        C.SETCAR(nxt, prev)
    end
elseif scheme == "slots" then
    local cap = 1024
    local store = C.Rf_allocVector(19, cap)
    C.R_PreserveObject(store)
    local free = {}
    local nfree = 0
    local top = 0
    PRESERVE = function(x)
        local i
        if nfree > 0 then
            i = free[nfree]
            nfree = nfree - 1
        else
            if top == cap then
                C.Rf_protect(x)
                local new_store = C.Rf_allocVector(19, cap * 2)
                for j = 0, cap - 1 do
                    C.SET_VECTOR_ELT(new_store, j, C.VECTOR_ELT(store, j))
                end
                C.R_PreserveObject(new_store)
                C.R_ReleaseObject(store)
                store = new_store
                cap = cap * 2
                C.Rf_unprotect(1)
            end
            i = top
            top = top + 1
        end
        C.SET_VECTOR_ELT(store, i, x)
        return i
    end
    RELEASE = function(i)
        C.SET_VECTOR_ELT(store, i, nil_value)
        nfree = nfree + 1
        free[nfree] = i
    end
end

ALLOC = function()
    return C.Rf_allocVector(14, 1)
end

KEEP = {}
for i = 1, @K@ do
    KEEP[i] = PRESERVE(ALLOC())
end
)---"

churn = r"---(
local M = @M@
local lag = @LAG@
local ring = {}
for i = 1, lag do
    ring[i] = PRESERVE(ALLOC())
end
local t0 = os.clock()
for m = 1, M do
    local j = (m % lag) + 1
    local old = ring[j]
    ring[j] = PRESERVE(ALLOC())
    RELEASE(old)
end
CHURN_NS = (os.clock() - t0) / M * 1e9
)---"

invisible(gc(full = TRUE))
before = gc(full = TRUE)[, "used"]
luajr::lua(fill(setup))
after = gc(full = TRUE)[, "used"]
full_gc = min(replicate(5, system.time(gc(full = TRUE))[["elapsed"]]))
gct0 = gc.time()[1]
luajr::lua(fill(churn))
gct1 = gc.time()[1]
churn_ns = luajr::lua("return CHURN_NS")

k = as.numeric(K)
label = if (scheme == "R" && nzchar(Sys.getenv("R_HASH_PRECIOUS"))) "R hashed" else scheme
cat(sprintf("%-8s K = %-8s Ncells/object %5.2f  Vcells/object %5.2f  full gc %7.1f ms  churn %8.1f ns/op  gc in churn %5.2f s\n",
    label, K, (after[1] - before[1]) / k, (after[2] - before[2]) / k,
    full_gc * 1000, churn_ns, gct1 - gct0))
