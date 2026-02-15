#include "registry_entry.h"
extern "C" {
#include "lua.h"
}
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>

// Disarm all RegistryEntries within Lua state L.
void RegistryEntry::DisarmAll(lua_State* L)
{
    // Get luajrx table from registry on stack
    lua_getfield(L, LUA_REGISTRYINDEX, "luajrx");

    // Iterate through all entries, disarming each
    lua_pushnil(L);
    while (lua_next(L, -2) != 0)
    {
        RegistryEntry* re = reinterpret_cast<RegistryEntry*>(lua_touserdata(L, -2));
        re->l = 0;
        lua_pop(L, 1);
    }
}

// Destroy a registry entry pointed to by an R external pointer when it is no
// longer needed (i.e. at program exit or garbage collection of the R pointer).
void RegistryEntry::Finalize(SEXP xptr)
{
    delete reinterpret_cast<RegistryEntry*>(R_ExternalPtrAddr(xptr));
    R_ClearExternalPtr(xptr);
}

// Create a registry entry, registering and popping the value at the top of the stack.
RegistryEntry::RegistryEntry(lua_State* L)
 : l(L)
{
    lua_getfield(l, LUA_REGISTRYINDEX, "luajrx");   // Get luajrx table from registry on stack
    lua_insert(l, -2);                              // Move luajrx table below value
    lua_pushlightuserdata(l, (void*)this);          // Push registry key to stack
    lua_insert(l, -2);                              // Move registry key below value on stack
    lua_rawset(l, -3);                              // Set value in luajrx table; pops key & value
    lua_pop(l, 1);                                  // Pop luajrx
}

// Delete the registry entry.
RegistryEntry::~RegistryEntry()
{
    if (l == 0) return;
    lua_getfield(l, LUA_REGISTRYINDEX, "luajrx");   // Get luajrx table from registry on stack
    lua_pushlightuserdata(l, (void*)this);          // Push registry key to stack
    lua_pushnil(l);                                 // Push nil to stack
    lua_rawset(l, -3);                              // Erase value in luajrx table; pops key & nil
    lua_pop(l, 1);                                  // Pop luajrx
}

// Put the registered value at the top of the stack.
void RegistryEntry::Get()
{
    if (l == 0) { Rf_error("Invalid registry entry retrieval: Lua state closed."); return; }
    lua_getfield(l, LUA_REGISTRYINDEX, "luajrx");   // Get luajrx table from registry on stack
    lua_pushlightuserdata(l, (void*)this);          // Push registry key to stack
    lua_rawget(l, -2);                              // Get value on stack
    lua_remove(l, -2);                              // Remove luajrx table from stack
}

// Get the associated Lua state.
lua_State* RegistryEntry::GetState()
{
    return l;
}

// Is the associated state equal to this one?
bool RegistryEntry::CheckState(lua_State* L)
{
    return (l != 0) && (l == L);
}

