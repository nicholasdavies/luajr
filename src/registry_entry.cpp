#include "registry_entry.h"
extern "C" {
#include "lua.h"
}

// Create a registry entry.
RegistryEntry::RegistryEntry(lua_State* L)
 : l(L)
{ }

// Delete the registry entry.
RegistryEntry::~RegistryEntry()
{
    lua_pushlightuserdata(l, (void*)this);  // push registry handle to stack
    lua_pushnil(l);                         // push nil to stack
    lua_settable(l, LUA_REGISTRYINDEX);     // set registry entry to nil
}

// Register the value at the top of the stack. Pops the value from the stack.
void RegistryEntry::Register()
{
    lua_pushlightuserdata(l, (void*)this);  // push registry handle to stack
    lua_insert(l, -2);                      // move registry handle below value on stack
    lua_settable(l, LUA_REGISTRYINDEX);     // set value in registry
}

// Put the registered value at the top of the stack.
void RegistryEntry::Get()
{
    lua_pushlightuserdata(l, (void*)this);  // push registry handle to stack
    lua_gettable(l, LUA_REGISTRYINDEX);     // get entry on stack
}

