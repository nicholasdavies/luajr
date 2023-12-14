# TODO probably want to make this optional, i.e. calls to API which
# require a lua_State* check that the internal state is non-null and if it is null
# load a lua_State*; this way, could have e.g. a vector of lua_State*s
# which are created with e.g. lua_state_push() and deleted with lua_state_pop()
# which would allow for multiple states (thread-safe?) and the resetting
# of the main state. So the main state would have "ID" 0, and if API calls do not
# indicate a state, the default state is the one with ID 0; if API calls indicate
# a state with ID > 0, then this is used if there but is an error if it is not
# there; and if API calls use the state with ID == 0, this is created if needed.
# note that the vector of lua_State*s should be static and not exported in this
# case. Or maybe that doesn't make a difference. But don't export.
.onLoad <- function(libname, pkgname) {
    # here
    invisible()
}

.onUnload <- function(libname, pkgname) {
    # here
    invisible()
}
