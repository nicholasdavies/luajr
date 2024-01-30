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

// Open [threads] new Lua states, run code [pre] in each one, then run
// "return [func]" and call it with integers 1 to n across the threads
extern "C" SEXP luajr_run_parallel(SEXP func, SEXP n, SEXP threads, SEXP pre)
{
    CheckSEXP(func, STRSXP, 1);
    CheckSEXP(n, INTSXP, 1);
    CheckSEXP(threads, INTSXP, 1);
    CheckSEXP(pre, STRSXP, 1);

    // Further checks on parameters
    int n_iter = INTEGER(n)[0];
    if (n_iter < 0) // also covers NA_INTEGER
        Rf_error("Invalid number of iterations.");
    int n_threads = INTEGER(threads)[0];
    if (n_threads <= 0) // also covers NA_INTEGER
        Rf_error("Invalid number of threads.");

    // Assemble statement that returns Lua function
    std::string cmd = "return ";
    cmd += CHAR(STRING_ELT(func, 0));

    // Get pre-run code
    const char* pre_code = 0;
    if (STRING_ELT(pre, 0) != NA_STRING)
        pre_code = CHAR(STRING_ELT(pre, 0));

    // Create Lua states for each thread
    std::vector<lua_State*> l(n_threads, 0);
    for (unsigned int t = 0; t < l.size(); ++t)
        l[t] = luajr_newstate();

    // The work itself
    std::atomic<int> iter { 0 };
    std::string error_msg;
    std::mutex pm;
    SEXP result = PROTECT(Rf_allocVector3(VECSXP, n_iter, NULL));

    auto work = [&](const unsigned int t)
    {
        // Run pre-code
        if (pre_code != 0)
        {
            if (luaL_dostring(l[t], pre_code))
            {
                std::lock_guard<std::mutex> lock { pm };
                error_msg = lua_tostring(l[t], -1);
            }
            lua_settop(l[t], 0); // Discard any return values
        }

        // Has any thread produced an error?
        if (!error_msg.empty())
            return;

        // Run command to get function on stack
        int top0 = lua_gettop(l[t]);
        int err = luaL_dostring(l[t], cmd.c_str());
        int nret = lua_gettop(l[t]) - top0;

        // Handle errors
        if (err) {
            std::lock_guard<std::mutex> lock { pm };
            error_msg = lua_tostring(l[t], -1);
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

        // Get new top of stack
        top0 = lua_gettop(l[t]);

        for (int i = 0; (i = ++iter) <= n_iter; )
        {
            // Call the function with iteration number as argument
            lua_pushvalue(l[t], -1);
            lua_pushinteger(l[t], i);
            err = lua_pcall(l[t], 1, LUA_MULTRET, 0);
            nret = lua_gettop(l[t]) - top0;

            // Store computed value and handle errors
            {
                std::lock_guard<std::mutex> lock { pm };

                // Did this iteration produce an error?
                if (err != 0)
                    error_msg = lua_tostring(l[t], -1);

                // Has any thread produced an error?
                if (!error_msg.empty())
                    return;

                // Store result
                SET_VECTOR_ELT(result, i - 1, luajr_return(l[t], nret));
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

    // Close states
    for (unsigned int t = 0; t < l.size(); ++t)
        lua_close(l[t]);

    // Handle errors and return
    UNPROTECT(1);
    if (!error_msg.empty())
        Rf_error("Error running parallel task: %s", error_msg.c_str());

    return result;
}
