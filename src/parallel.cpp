// parallel.cpp: Run Lua code in parallel

#include "shared.h"
#include <atomic>
#include <chrono>
#include <iomanip>
#include <iostream>
#include <mutex>
#include <string>
#include <thread>
#include <vector>
extern "C" {
#include "lua.h"
#include "lauxlib.h"
}
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>

// Open [threads] new Lua states (or use [threads] if a list of states), run
// code [pre] in each one, then run "return [func]" to get a function. Call the
// func(i) with i in 1 to n.
// TODO there are several problems here -- one, this doesn't handle errors prop
// erly in the case of non-string errors (see e.g. run_func.cpp); two, this doe
// sn't account for profile / debug mode.
extern "C" SEXP luajr_run_parallel(SEXP func, SEXP n, SEXP threads, SEXP pre)
{
    CheckSEXPLen(func, STRSXP, 1);
    CheckSEXPLen(n, INTSXP, 1);
    CheckSEXPLen(pre, STRSXP, 1);

    // Ensure n is sensible
    int n_iter = INTEGER(n)[0];
    if (n_iter < 0) // also covers NA_INTEGER
        Rf_error("Invalid number of iterations.");

    // Create or get Lua states for each thread
    std::vector<lua_State*> l;
    if (TYPEOF(threads) == INTSXP && Rf_length(threads) == 1)
    {
        int n_threads = INTEGER(threads)[0];
        if (n_threads <= 0) // also covers NA_INTEGER
            Rf_error("Invalid number of threads.");
        l.assign(n_threads, 0);
        for (unsigned int t = 0; t < l.size(); ++t)
            l[t] = luajr_newstate();
    }
    else if (TYPEOF(threads) == VECSXP && Rf_length(threads) > 0)
    {
        l.assign(Rf_length(threads), 0);
        for (unsigned int t = 0; t < l.size(); ++t)
        {
            l[t] = luajr_getstate(VECTOR_ELT(threads, t));
            for (unsigned int u = 0; u < t; ++u)
                if (l[u] == l[t])
                    Rf_error("Cannot use the same Lua state across multiple threads.");
        }
    }
    else
    {
        Rf_error("threads parameter must be either an integer or a list of Lua states.");
    }

    // Assemble statement that returns Lua function
    std::string cmd = "return ";
    cmd += CHAR(STRING_ELT(func, 0));

    // Get pre-run code
    const char* pre_code = 0;
    if (STRING_ELT(pre, 0) != NA_STRING)
        pre_code = CHAR(STRING_ELT(pre, 0));

    // The work itself
    std::atomic<int> iter { 0 };
    std::string error_msg;
    std::mutex pm;
    SEXP result = R_NilValue;

    auto work = [&](const unsigned int t)
    {
        // Run pre-code
        if (pre_code != 0)
        {
            int pre_code_error = luaL_loadstring(l[t], pre_code);
            if (!pre_code_error)
                pre_code_error = lua_pcall(l[t], 0, 0, 0); // Discard any return values
            if (pre_code_error)
            {
                std::lock_guard<std::mutex> lock { pm };
                error_msg.assign(1024, ' ');
                luajr_handle_lua_error(l[t], pre_code_error, "lua_parallel 'pre' execution", error_msg.data());
            }
        }

        // Has any thread produced an error?
        if (!error_msg.empty())
            return;

        // Run command to get function on stack
        int top0 = lua_gettop(l[t]);
        int err = luaL_loadstring(l[t], cmd.c_str());
        if (!err)
            err = lua_pcall(l[t], 0, LUA_MULTRET, 0);
        int nret = lua_gettop(l[t]) - top0;

        // Handle errors
        if (err) {
            // This and similar mutex locks are used to avoid writing
            // to error_message in multiple threads simultaneously.
            std::lock_guard<std::mutex> lock { pm };
            error_msg.assign(1024, ' ');
            luajr_handle_lua_error(l[t], err, "lua_parallel 'func' construction", error_msg.data());
        } else if (nret != 1) {
            std::lock_guard<std::mutex> lock { pm };
            error_msg = "lua_parallel expects `func' to evaluate to one value, not " +
                std::to_string(nret) + ".";
        } else if (lua_type(l[t], -1) != LUA_TFUNCTION) {
            std::lock_guard<std::mutex> lock { pm };
            error_msg = "lua_parallel expects `func' to evaluate to a function, not a " +
                std::string(lua_typename(l[t], lua_type(l[t], -1))) + ".";
        }

        // Has any thread produced an error?
        if (!error_msg.empty())
            return;

        // Get new top of stack (i.e. the function)
        top0 = lua_gettop(l[t]);

        // Do calls
        for (int i = ++iter; i <= n_iter; i = ++iter)
        {
            // Call the function with iteration number as argument
            int top1 = lua_gettop(l[t]);
            lua_pushvalue(l[t], top0);
            lua_pushinteger(l[t], i);
            err = lua_pcall(l[t], 1, LUA_MULTRET, 0);

            // Check for errors
            if (err)
            {
                std::lock_guard<std::mutex> lock { pm };
                error_msg.assign(1024, ' ');
                luajr_handle_lua_error(l[t], err, "lua_parallel 'func' execution", error_msg.data());
            }
            if (!error_msg.empty())
                return;

            // Push number of return values and index for assignment onto the
            // stack, unless there were no return values at all.
            nret = lua_gettop(l[t]) - top1;
            if (nret > 0)
            {
                lua_checkstack(l[t], 4);
                lua_pushinteger(l[t], nret);
                lua_pushinteger(l[t], i);
            }
        }
    };

    // Create and assign work to the threads
    std::vector<std::thread> thr;
    for (unsigned int t = 0; t < l.size(); ++t)
        thr.emplace_back(work, t);

    // Wait for threads to finish
    for (unsigned int t = 0; t < thr.size(); ++t)
        thr[t].join();

    // Handle errors
    if (!error_msg.empty())
    {
        // Close states, if lua_parallel created them
        if (TYPEOF(threads) == INTSXP)
            for (unsigned int t = 0; t < l.size(); ++t)
                lua_close(l[t]);
        // Otherwise, clear stacks (as may be quite full)
        if (TYPEOF(threads) == VECSXP)
            for (unsigned int t = 0; t < l.size(); ++t)
                lua_settop(l[t], 0);
        // Stop with error
        Rf_error("%s", error_msg.c_str());
    }

    // Assign computed values to list
    int nprotect = 0;
    for (unsigned int t = 0; t < l.size(); ++t)
    {
        while (lua_isnumber(l[t], -1))
        {
            if (result == R_NilValue)
            {
                result = PROTECT(Rf_allocVector(VECSXP, n_iter));
                ++nprotect;
            }
            int index = lua_tointeger(l[t], -1);
            int nret = lua_tointeger(l[t], -2);
            lua_pop(l[t], 2);
            SET_VECTOR_ELT(result, index - 1, luajr_return(l[t], nret));
        }
    }

    // Close states, if lua_parallel created them
    if (TYPEOF(threads) == INTSXP)
        for (unsigned int t = 0; t < l.size(); ++t)
            lua_close(l[t]);

    UNPROTECT(nprotect);
    return result;
}
