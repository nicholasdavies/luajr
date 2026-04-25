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

// Workers struct (matches workers_t in luajr.lua)
struct workers_t { lua_State** l; int n; };

// Open [threads] new Lua states (or use [threads] if a list of states), run
// code [pre] in each one, then run "return [func]" to get a function. Call the
// func(i) with i in 1 to n.
extern "C" SEXP luajr_run_parallel(SEXP func, SEXP n, SEXP threads, SEXP pre)
{
    CheckSEXPLen(func, STRSXP, 1);
    CheckSEXPLen(n, INTSXP, 1);
    CheckSEXPLen(pre, STRSXP, 1);

    // For any call to luajr_pcall
    static const int tflags = LUAJR_NO_PROFILE_COLLECT | LUAJR_NO_ERROR_HANDLING | LUAJR_TOOLING_ALL;

    // Ensure n is sensible
    int n_iter = INTEGER(n)[0];
    if (n_iter < 0) // also covers NA_INTEGER
        Rf_error("Invalid number of iterations.");

    // Don't multi-thread in debug mode
    bool single_thread = false;
    if (luajr_debug_mode())
    {
        single_thread = true;
        Rf_warningcall_immediate(R_NilValue, "luajr debugger is active, so lua_parallel will only use one thread.");
    }
    else if (luajr_profile_mode())
    {
        single_thread = true;
        Rf_warningcall_immediate(R_NilValue, "luajr profiler is active, so lua_parallel will only use one thread.");
    }

    // Create or get Lua states for each thread
    std::vector<lua_State*> l;
    if (TYPEOF(threads) == INTSXP && Rf_length(threads) == 1)
    {
        int n_threads = single_thread ? 1 : INTEGER(threads)[0];
        if (n_threads <= 0) // also covers NA_INTEGER
            Rf_error("Invalid number of threads.");
        l.assign(n_threads, 0);
        for (unsigned int t = 0; t < l.size(); ++t)
            l[t] = luajr_newstate();
    }
    else if (TYPEOF(threads) == VECSXP && Rf_length(threads) > 0)
    {
        l.assign(single_thread ? 1 : Rf_length(threads), 0);
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
                pre_code_error = luajr_pcall(l[t], 0, 0, 0, tflags); // Discard any return values
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
            err = luajr_pcall(l[t], 0, LUA_MULTRET, 0, tflags);
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
            err = luajr_pcall(l[t], 1, LUA_MULTRET, 0, tflags);

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

    // During parallel execution, it seems that input from the console is
    // not available, even if there is only one thread going. So, don't drop
    // into parallel execution if the number of threads is just one.
    // (This allows the debugger to carry on working.)
    if (l.size() > 1)
    {
        // Create and assign work to the threads
        std::vector<std::thread> thr;
        for (unsigned int t = 0; t < l.size(); ++t)
            thr.emplace_back(work, t);

        // Wait for threads to finish
        for (unsigned int t = 0; t < thr.size(); ++t)
            thr[t].join();
    }
    else
    {
        work(0);
    }

    // Collect any profiler data
    for (unsigned int t = 0; t < l.size(); ++t)
        luajr_profile_collect(l[t]);

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




// lua_CFunction: load a function + args into all worker states.
// Lua args: (workers_t, function, args...)
extern "C" int luajr_parallel_load(lua_State* L)
{
    workers_t* w = (workers_t*)lua_topointer(L, 1);
    int nvalues = lua_gettop(L) - 1;

    for (int t = 0; t < w->n; ++t)
    {
        lua_settop(w->l[t], 0);
        for (int a = 1; a <= nvalues; ++a)
            luajr_xpush(L, 1 + a, w->l[t]);
    }
    return 0;
}

// Get a hint as to the number of concurrent threads.
extern "C" int luajr_parallel_ncores()
{
    return std::thread::hardware_concurrency();
}

// Initialise workers: open w->n states.
// May reduce w->n in debug/profile mode.
extern "C" void luajr_parallel_newworkers(workers_t* w)
{
    // Don't multi-thread in debug mode
    bool single_thread = false;
    if (luajr_debug_mode()) {
        single_thread = true;
        Rf_warningcall_immediate(R_NilValue, "luajr debugger is active, so luajr.workers will only use one thread.");
    } else if (luajr_profile_mode()) {
        single_thread = true;
        Rf_warningcall_immediate(R_NilValue, "luajr profiler is active, so luajr.workers will only use one thread.");
    }

    w->n = single_thread ? 1 : w->n;
    if (w->n <= 0)
        Rf_error("Invalid number of threads.");

    w->l = new lua_State*[w->n];
    for (int t = 0; t < w->n; ++t)
        w->l[t] = luajr_newstate();
}

// Close workers and free state array.
extern "C" void luajr_parallel_closeworkers(workers_t* w)
{
    for (int t = 0; t < w->n; ++t)
        lua_close(w->l[t]);
    delete[] w->l;
    w->l = NULL;
    w->n = 0;
}

// Run the preloaded function in each worker, sequentially.
// Each worker's stack has [function, arg1, arg2, ...] from parallel_load.
// Calls function(arg1, arg2, ..., thread_id) with 1-based thread_id as last arg.
extern "C" void luajr_parallel_srun(workers_t* w)
{
    for (int t = 0; t < w->n; ++t)
    {
        int nargs = lua_gettop(w->l[t]) - 1;
        for (int i = 1; i <= nargs + 1; ++i)
            lua_pushvalue(w->l[t], i);
        lua_pushinteger(w->l[t], t + 1);
        int err = luajr_pcall(w->l[t], nargs + 1, 0, "parallel_srun", LUAJR_TOOLING_ALL);
        if (err)
        {
            const char* msg = lua_tostring(w->l[t], -1);
            Rf_error("parallel_srun: error in worker %d: %s", t, msg ? msg : "(unknown)");
        }
        luajr_profile_collect(w->l[t]);
    }
}

// Run the preloaded function in each worker, in parallel.
// Each worker's stack has [function, arg1, arg2, ...] from parallel_load.
// Calls function(arg1, arg2, ..., thread_id) with 1-based thread_id as last arg.
extern "C" void luajr_parallel_prun(workers_t* w)
{
    static const int tflags = LUAJR_NO_PROFILE_COLLECT | LUAJR_NO_ERROR_HANDLING | LUAJR_TOOLING_ALL;
    std::string error_msg;
    std::mutex pm;

    auto work = [&](int t)
    {
        int nargs = lua_gettop(w->l[t]) - 1;
        for (int i = 1; i <= nargs + 1; ++i)
            lua_pushvalue(w->l[t], i);
        lua_pushinteger(w->l[t], t + 1);
        int err = luajr_pcall(w->l[t], nargs + 1, 0, "parallel_prun", tflags);
        if (err)
        {
            std::lock_guard<std::mutex> lock { pm };
            if (error_msg.empty())
            {
                error_msg.assign(1024, ' ');
                luajr_handle_lua_error(w->l[t], err, "parallel_prun", error_msg.data());
            }
        }
    };

    // During parallel execution, console input is not available.
    // Use single thread if only one worker (allows debugger to work).
    if (w->n > 1)
    {
        std::vector<std::thread> thr;
        for (int t = 0; t < w->n; ++t)
            thr.emplace_back(work, t);
        for (int t = 0; t < w->n; ++t)
            thr[t].join();
    }
    else
    {
        work(0);
    }

    // Collect any profiler data
    for (int t = 0; t < w->n; ++t)
        luajr_profile_collect(w->l[t]);

    if (!error_msg.empty())
        Rf_error("%s", error_msg.c_str());
}

// Run the preloaded function across a range of iterations, distributed
// across workers using atomic work-stealing.
// Each worker's stack has [function, arg1, arg2, ...] from parallel_load.
// Calls function(i, arg1, arg2, ..., thread_id) for each iteration i in [i0, i1].
extern "C" void luajr_parallel_pfor(workers_t* w, int i0, int i1)
{
    static const int tflags = LUAJR_NO_PROFILE_COLLECT | LUAJR_NO_ERROR_HANDLING | LUAJR_TOOLING_ALL;
    std::atomic<int> iter { i0 };
    std::string error_msg;
    std::mutex pm;

    auto work = [&](int t)
    {
        int nargs = lua_gettop(w->l[t]) - 1;

        for (int i = iter++; i <= i1; i = iter++)
        {
            // Copy function and preloaded args
            for (int j = 1; j <= nargs + 1; ++j)
                lua_pushvalue(w->l[t], j);
            // Insert iteration index as first arg (after function)
            lua_pushinteger(w->l[t], i);
            // Move i before the preloaded args: swap it into position
            // Stack is now: [...base...] [func] [arg1] ... [argN] [i]
            // Want:         [...base...] [func] [i] [arg1] ... [argN] [thread_id]
            lua_insert(w->l[t], lua_gettop(w->l[t]) - nargs);
            // Append thread_id as last arg
            lua_pushinteger(w->l[t], t + 1);

            int err = luajr_pcall(w->l[t], nargs + 2, 0, "parallel_pfor", tflags);
            if (err)
            {
                std::lock_guard<std::mutex> lock { pm };
                if (error_msg.empty())
                {
                    error_msg.assign(1024, ' ');
                    luajr_handle_lua_error(w->l[t], err, "parallel_pfor", error_msg.data());
                }
            }
            if (!error_msg.empty())
                return;
        }
    };

    // Single-thread path for debugger compatibility
    if (w->n > 1)
    {
        std::vector<std::thread> thr;
        for (int t = 0; t < w->n; ++t)
            thr.emplace_back(work, t);
        for (int t = 0; t < w->n; ++t)
            thr[t].join();
    }
    else
    {
        work(0);
    }

    // Collect any profiler data
    for (int t = 0; t < w->n; ++t)
        luajr_profile_collect(w->l[t]);

    if (!error_msg.empty())
        Rf_error("%s", error_msg.c_str());
}
