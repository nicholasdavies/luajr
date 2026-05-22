// parallel.cpp: Run Lua code in parallel

#include "shared.h"
#include <atomic>
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

// Get a hint as to the number of concurrent threads.
extern "C" int luajr_parallel_ncores()
{
    return std::thread::hardware_concurrency();
}

// Initialise workers: open w->n states.
extern "C" void luajr_parallel_newworkers(lua_State* L, workers_t* w)
{
    if (w->n <= 0)
        luajr_error(L, "Invalid number of threads.");

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

// Load a function + args into all worker states (lua_CFunction).
// The runners below (srun, prun, pfor) use the preloaded functions and arguments.
// Lua args to this function: (workers_t, function, args...)
extern "C" int luajr_parallel_load_cf(lua_State* L)
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

// Clear all worker stacks (i.e., on error)
static void clear_worker_stacks(workers_t* w)
{
    for (int t = 0; t < w->n; ++t)
        lua_settop(w->l[t], 0);
}

// Sequentially run the preloaded function in each worker.
// Calls function(arg1, arg2, ..., thread_id) with 1-based thread_id as last arg.
extern "C" void luajr_parallel_srun(lua_State* L, workers_t* w)
{
    for (int t = 0; t < w->n; ++t)
    {
        // Function and args are on stack from parallel_load; push all followed by thread_id.
        int nargs = lua_gettop(w->l[t]) - 1;
        for (int i = 1; i <= nargs + 1; ++i)
            lua_pushvalue(w->l[t], i);
        lua_pushinteger(w->l[t], t + 1);

        // Run, handle any errors, and collect profile data
        int err = luajr_pcall(w->l[t], nargs + 1, 0, "parallel_srun", LUAJR_TOOLING_ALL);
        if (err)
        {
            std::string error_msg(1024, ' ');
            luajr_handleerror(w->l[t], err, "parallel_srun", &error_msg[0]);
            clear_worker_stacks(w);
            luajr_error(L, "%s", error_msg.c_str());
        }
        luajr_flushprofile(w->l[t]);
    }
}

// Parallel-run the preloaded function in each worker.
// Calls function(arg1, arg2, ..., thread_id) with 1-based thread_id as last arg.
extern "C" void luajr_parallel_prun(lua_State* L, workers_t* w)
{
    // For any call to luajr_pcall: don't automatically collect profile data,
    // don't automatically propagate errors, and allow tooling.
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
                luajr_handleerror(w->l[t], err, "parallel_prun", &error_msg[0]);
            }
        }
    };

    // Use sequential execution in debug/profile mode, or if only one worker.
    if (w->n > 1 && !luajr_indebug() && !luajr_inprofile())
    {
        std::vector<std::thread> thr;
        for (int t = 0; t < w->n; ++t)
            thr.emplace_back(work, t);
        for (int t = 0; t < w->n; ++t)
            thr[t].join();
    }
    else
    {
        for (int t = 0; t < w->n; ++t)
            work(t);
    }

    // Collect any profiler data
    for (int t = 0; t < w->n; ++t)
        luajr_flushprofile(w->l[t]);

    if (!error_msg.empty())
    {
        clear_worker_stacks(w);
        luajr_error(L, "%s", error_msg.c_str());
    }
}

// Run the preloaded function across a range of iterations, distributed
// across workers using atomic work-stealing.
// Calls function(i, arg1, arg2, ..., thread_id) for each iteration i in [i0, i1].
extern "C" void luajr_parallel_pfor(lua_State* L, workers_t* w, int i0, int i1)
{
    // For any call to luajr_pcall: don't automatically collect profile data,
    // don't automatically propagate errors, and allow tooling.
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
                    luajr_handleerror(w->l[t], err, "parallel_pfor", &error_msg[0]);
                }
            }
            if (!error_msg.empty())
                return;
        }
    };

    // Use sequential execution in debug/profile mode, or if only one worker.
    if (w->n > 1 && !luajr_indebug() && !luajr_inprofile())
    {
        std::vector<std::thread> thr;
        for (int t = 0; t < w->n; ++t)
            thr.emplace_back(work, t);
        for (int t = 0; t < w->n; ++t)
            thr[t].join();
    }
    else
    {
        for (int t = 0; t < w->n; ++t)
            work(t);
    }

    // Collect any profiler data
    for (int t = 0; t < w->n; ++t)
        luajr_flushprofile(w->l[t]);

    if (!error_msg.empty())
    {
        clear_worker_stacks(w);
        luajr_error(L, "%s", error_msg.c_str());
    }
}
