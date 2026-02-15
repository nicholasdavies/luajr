// parallel.cpp: Run Lua code in parallel

#include "shared.h"
#include <map>
#include <unordered_set>
#include <vector>
#include <string>
#include <algorithm>
extern "C" {
#include "lua.h"
#include "lauxlib.h"
#include "luajit_build.h"
}
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>

static std::string debug_mode = "off";
static std::string profile_mode = "off";
static std::string jit_mode = "on";

static std::unordered_set<std::string> profile_pool;
typedef std::unordered_set<std::string>::iterator pool_it;
static std::map<lua_State*, std::vector<pool_it>> profile_data;

static std::vector<std::string> debug_modes { "step", "error", "off" };
static std::vector<std::string> profile_modes;
static std::vector<std::string> jit_modes { "on", "off" };

static const char* profile_start = R"(
local registry = debug.getregistry()
registry.luajr_pd = registry.luajr_pd or {}
local luajr_pd = registry.luajr_pd
local chunk_size = 1024
local good = true

local mode = tostring(({...})[1])
local max_depth = 200
mode = mode:gsub('d([%d]+)', function(n)
    max_depth = math.floor(tonumber(n))
    return "" -- remove the match
end)

local max_chunks = math.ceil(128 * 1024^2 / (8 * chunk_size))
mode = mode:gsub('z([%d%.]+)', function(n)
    max_chunks = math.ceil(tonumber(n) * 1024^2 / (8 * chunk_size))
    max_chunks = math.max(max_chunks, 1)
    return "" -- remove the match
end)

local profcheck = function(slots)
    local c = #luajr_pd
    if c == 0 or #luajr_pd[c] + slots > chunk_size then
        if c >= max_chunks then
            good = false
            luajr_pd[c][#luajr_pd[c]] = "%%%"
        else
            table.insert(luajr_pd, table.new(chunk_size, 0))
        end
    end
end

local profstore = function(val)
    if good then
        table.insert(luajr_pd[#luajr_pd], val or "")
    end
end

local profile = require 'jit.profile'
local util = require 'jit.util'

local cb = function(thread, samples, vmstate)
    local level = 0

    profcheck(2)
    profstore(vmstate)
    profstore(samples)

    while true do
        if level >= max_depth then break end

        local info = debug.getinfo(thread, level, "Sln")
        if not info then break end

        profcheck(5)
        profstore(info.source)
        profstore(info.what)
        profstore(info.currentline)
        profstore(info.name)
        profstore(info.namewhat)

        level = level + 1
    end

    profcheck(1)
    profstore("%%")
end

profile.start(mode, cb)
)";

// Like luaL_loadstring, but produce an R error on failure
extern "C" void luajr_loadstring(lua_State* L, const char* str)
{
    luajr_handle_lua_error(L, luaL_loadstring(L, str), "string", 0);
}

// Like luaL_dostring, but produce an R error on failure, and with support for luajr tooling
extern "C" void luajr_dostring(lua_State* L, const char* str, int tooling)
{
    luajr_loadstring(L, str);
    luajr_pcall(L, 0, LUA_MULTRET, "string", tooling);
}

// Like luaL_loadfile, but produce an R error on failure
extern "C" void luajr_loadfile(lua_State* L, const char* filename)
{
    luajr_handle_lua_error(L, luaL_loadfile(L, filename), "file", 0);
}

// Like luaL_dofile, but produce an R error on failure, and with support for luajr tooling
extern "C" void luajr_dofile(lua_State* L, const char* filename, int tooling)
{
    luajr_loadfile(L, filename);
    luajr_pcall(L, 0, LUA_MULTRET, "file", tooling);
}

// Like luaL_loadbuffer, but produce an R error on failure
extern "C" void luajr_loadbuffer(lua_State *L, const char *buff, unsigned int sz, const char *name)
{
    luajr_handle_lua_error(L, luaL_loadbuffer(L, buff, sz, name), "buffer", 0);
}

// Buffer for error messages from luajr_handle_lua_error
// The use of this is what makes this function non-thread-safe unless
// LUAJR_NO_ERROR_HANDLING is set.
static char errbuf[1024];

// Like lua_pcall, but produce an R error on failure (unless the flag
// LUAJR_NO_ERROR_HANDLING is set), and with support for luajr tooling.
// Note: this function is only thread-safe with LUAJR_NO_ERROR_HANDLING
// and LUAJR_NO_PROFILE_COLLECT set.
extern "C" int luajr_pcall(lua_State* L, int nargs, int nresults, const char* what, int tooling)
{
    // Note: this currently assumes that there will be no errors in any Lua
    // code or commands run here, except for potentially in the pcall itself.

    // Stack index of debugger.lua's error handler (zero if inactive)
    int errfunc = 0;

    // Pre run: Activate debugger, profiler, JIT setttings.
    if (tooling & LUAJR_TOOLING_ALL)
    {
        if (debug_mode == "error")
        {
            // Activate debugger on error.
    	    // Grab the error handler (dbg.msgh function)
    	    // The use of tooling & ~LUAJR_TOOLING_ALL is to turn off debugging
    	    // and profiling, but keep LUAJR_NO_ERROR_HANDLING as is.
	        luajr_dostring(L, "return luajr.dbg_msgh()", tooling & ~LUAJR_TOOLING_ALL);

	        // Move the error handler just below the function
	        errfunc = lua_gettop(L) - (1 + nargs);
	        lua_insert(L, errfunc);
        }
        else if (debug_mode == "step")
        {
            // Step through each line of code.

            // When this function (luajr_pcall) is called, the function to call
            // and the arguments to pass are on the top of the stack. The trick
            // is to reinterpret the function + arguments at the top of the
            // stack themselves as arguments to another function to be pcalled;
            // that new function first activates the debugger, then calls the
            // original function with the original arguments. The debugger is
            // activated via a special luajr.dbg_step_into() which "preloads"
            // the debugger.lua commands with an "n" and an "s", which step
            // into the original function (rather than starting the debugger
            // in the "outer" function).
            luajr_loadstring(L, "luajr.dbg_step_into() return ({...})[1](select(2, ...))");
            lua_insert(L, -(nargs + 2)); // Put "outer" function below "original" function
            ++nargs; // The "original" function is the new 1st argument
        }

        if (profile_mode != "off")
        {
            // Any profiling mode: Start the profiler, with profile_mode an
            // argument to the code in profile_start (defined above).
            luajr_loadstring(L, profile_start);
            lua_pushstring(L, profile_mode.c_str());
            luajr_pcall(L, 1, LUA_MULTRET, "profile start", tooling & ~LUAJR_TOOLING_ALL);
        }

        if (jit_mode == "off")
        {
            // JIT mode off: turn off JIT compiler.
            luaJIT_setmode(L, 0, LUAJIT_MODE_ENGINE | LUAJIT_MODE_OFF);
        }
    }

    // Do the call, keeping track if there was an error
    int lua_err = lua_pcall(L, nargs, nresults, errfunc);

    // Post run
    if (tooling & LUAJR_TOOLING_ALL)
    {
        if (debug_mode == "error")
        {
            // Debug on error: remove the error handler from the stack.
	        lua_remove(L, errfunc);
        }

        if (debug_mode != "off")
        {
            // Any debug mode: clear debugger.lua's hook.
            // This is a call to debug.sethook(). We don't want to actually
            // load this as a string and run it, as that itself could get
            // caught in the debugger.
            lua_getglobal(L, "debug");
            lua_getfield(L, -1, "sethook");
            lua_call(L, 0, 0);
            lua_pop(L, 1); // debug
        }

        if (profile_mode != "off")
        {
            // Any profiling mode: collect the profiling data in profile_data

            // Stop the profiler
            luajr_dostring(L, "require 'jit.profile'.stop()", tooling & ~LUAJR_TOOLING_ALL);

            // Profile collection is not thread-safe, so make this optional
            if (!(tooling & LUAJR_NO_PROFILE_COLLECT))
                luajr_profile_collect(L);
        }

        if (jit_mode == "off")
        {
            // JIT mode off: turn JIT back on.
            luaJIT_setmode(L, 0, LUAJIT_MODE_ENGINE | LUAJIT_MODE_ON);
        }
    }

    // Handle any error that arose during the pcall.
    if (tooling & LUAJR_NO_ERROR_HANDLING)
    {
        return lua_err;
    }

    // Get the error using our static errbuf
    int errcode = luajr_handle_lua_error(L, lua_err, what, errbuf);

    // Propagate error
    if (errcode == 1) {
        if (errfunc != 0 && lua_err == LUA_ERRERR) {
            // If this function has set an errfunc, then the break-on-error
            // debug mode is active. Therefore, if an error has occurred within
            // the error handler (LUA_ERRERR), and hasn't been caught by
            // debugger.lua, then that is very likely to be the user quit command.
            Rf_errorcall(R_NilValue, "Quit debugger.");
        }
        Rf_error("%s", errbuf);
    } else if (errcode == 2) {
        Rf_errorcall(R_NilValue, "%s", errbuf);
    }

    return LUA_OK;
}

// Set mode for calls to luajr_pcall().
extern "C" SEXP luajr_set_mode(SEXP debug, SEXP profile, SEXP jit)
{
    // Argument checking
    auto arg = [](SEXP s, const char* what, std::string& current,
            const char* onval, std::vector<std::string>& modes) -> const char* {
        if (TYPEOF(s) == LGLSXP && Rf_length(s) == 1)
            return LOGICAL(s)[0] == TRUE ? onval : "off";

        CheckSEXPLen(s, STRSXP, 1);

        if (STRING_ELT(s, 0) == R_BlankString)
            return current.c_str();

        const char* str = CHAR(STRING_ELT(s, 0));

        if (strcmp(str, "on") == 0)
            str = onval;

        if (!modes.empty()) {
            if (std::find(modes.begin(), modes.end(), str) == modes.end()) {
                Rf_error("Invalid mode '%s' for %s", CHAR(STRING_ELT(s, 0)), what);
            }
        }
        return str;
    };

    // Get settings
    const char* debug_str = arg(debug, "debug", debug_mode, "step", debug_modes);
    const char* profile_str = arg(profile, "profile", profile_mode, "li10", profile_modes);
    const char* jit_str = arg(jit, "jit", jit_mode, "on", jit_modes);

    debug_mode = debug_str;
    profile_mode = profile_str;
    jit_mode = jit_str;

    return R_NilValue;
}

// Get current modes for calls to luajr_pcall().
extern "C" SEXP luajr_get_mode()
{
    SEXP ret = PROTECT(Rf_allocVector(STRSXP, 3));
    SET_STRING_ELT(ret, 0, Rf_mkChar(debug_mode.c_str()));
    SET_STRING_ELT(ret, 1, Rf_mkChar(profile_mode.c_str()));
    SET_STRING_ELT(ret, 2, Rf_mkChar(jit_mode.c_str()));

    SEXP names = PROTECT(Rf_allocVector(STRSXP, 3));
    SET_STRING_ELT(names, 0, Rf_mkChar("debug"));
    SET_STRING_ELT(names, 1, Rf_mkChar("profile"));
    SET_STRING_ELT(names, 2, Rf_mkChar("jit"));
    Rf_setAttrib(ret, R_NamesSymbol, names);

    UNPROTECT(2);
    return ret;
}

// Is debugger on?
extern "C" int luajr_debug_mode()
{
    if (debug_mode == "off")
        return LUAJR_DEBUG_MODE_OFF;
    else if (debug_mode == "error")
        return LUAJR_DEBUG_MODE_ERROR;
    else if (debug_mode == "step")
        return LUAJR_DEBUG_MODE_STEP;
    else
        Rf_error("Invalid debug mode \"%s\" set.", debug_mode.c_str());
}

// Is profiler on?
extern "C" int luajr_profile_mode()
{
    if (profile_mode == "off")
        return LUAJR_PROFILE_MODE_OFF;
    else
        return LUAJR_PROFILE_MODE_ON;
}

// Internalize profiler data from state L.
void luajr_profile_collect(lua_State* L)
{
    // Get luajr profile data on stack
    lua_getfield(L, LUA_REGISTRYINDEX, "luajr_pd");

    // Quit if no profile data to collect
    if (lua_isnil(L, -1)) {
        lua_pop(L, 1); // luajr_pd
        return;
    }

    // Find profile data string vector
    auto pd = profile_data.find(L);
    if (pd == profile_data.end()) {
        // first is iterator, second is status code
        pd = profile_data.emplace(L, std::vector<pool_it>()).first;
    }

    // Iterate through profile data
    lua_pushnil(L);
    while (lua_next(L, -2) != 0)
    {
        lua_pushnil(L);
        while (lua_next(L, -2) != 0)
        {
            auto [it, inserted] = profile_pool.insert(lua_tostring(L, -1));
            pd->second.push_back(it);
            lua_pop(L, 1);
        }
        lua_pop(L, 1);
    }

    // Clear profile data in Lua registry
    lua_newtable(L);
    lua_setfield(L, LUA_REGISTRYINDEX, "luajr_pd");

    lua_pop(L, 1); // luajr_pd
}

// Extract profiler data.
extern "C" SEXP luajr_profile_data(SEXP flush)
{
    CheckSEXPLen(flush, LGLSXP, 1);

    SEXP ret = PROTECT(Rf_allocVector(VECSXP, profile_data.size()));
    size_t j = 0;
    for (auto& l : profile_data)
    {
        SEXP ptr;
        if (l.first == L0) {
            ptr = PROTECT(Rf_mkString("default"));
        } else {
            char buffer[40];
            snprintf(buffer, 39, "%p", (void*)l.first);
            ptr = PROTECT(Rf_mkString(buffer));
        }
        SEXP data = PROTECT(Rf_allocVector(STRSXP, l.second.size()));

        size_t i = 0;
        for (auto& x : l.second)
        {
            SET_STRING_ELT(data, i, Rf_mkChar(x->c_str()));
            ++i;
        }

        SEXP entry = PROTECT(Rf_allocVector(VECSXP, 2));
        SET_VECTOR_ELT(entry, 0, ptr);
        SET_VECTOR_ELT(entry, 1, data);
        SET_VECTOR_ELT(ret, j, entry);
        UNPROTECT(3);
        ++j;
    }

    if (LOGICAL(flush)[0] == TRUE)
        profile_data.clear();

    UNPROTECT(1);

    return ret;
}
