#ifndef REGISTRY_ENTRY_H
#define REGISTRY_ENTRY_H

// [[Rcpp::plugins(cpp11)]]

// Forward declaration
struct lua_State;

// RegistryEntry: an entry on the Lua registry, which cleans itself up upon
// destruction. First, push the desired value onto the Lua stack, then create
// a new RegistryEntry, then call re->Register(). To get the entry onto the
// stack, use re->Get(). Note that RegistryEntry objects must be created by new,
// as the logic relies upon the object always having the same address.
class RegistryEntry
{
public:
    // Disarm all RegistryEntries within Lua state L.
    static void DisarmAll(lua_State* L);

    // Create a registry entry, registering and popping the value at the top of the stack.
    RegistryEntry(lua_State* L);

    // No copy constructor.
    RegistryEntry(const RegistryEntry&) = delete;

    // No assignment operator.
    RegistryEntry& operator=(const RegistryEntry&) = delete;

    // Delete the registry entry.
    ~RegistryEntry();

    // Put the registered value at the top of the stack.
    void Get();

private:
    lua_State* l; // lua_State in which registry is stored
};

#endif // REGISTRY_ENTRY_H
