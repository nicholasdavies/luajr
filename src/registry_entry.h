#ifndef REGISTRY_ENTRY_H
#define REGISTRY_ENTRY_H

// Forward declaration
struct lua_State;
struct SEXPREC;
typedef struct SEXPREC* SEXP;

// RegistryEntry: an entry on the Lua registry, which cleans itself up upon
// destruction. First, push the desired value onto the top of the Lua stack,
// then create a new RegistryEntry. To get the entry onto the
// stack, use re->Get(). Note that RegistryEntry objects must be created by new,
// as the logic relies upon the object always having the same address.
class RegistryEntry
{
public:
    // Disarm all RegistryEntries within Lua state L.
    static void DisarmAll(lua_State* L);

    // Destroy a registry entry pointed to by an R external pointer when it is no
    // longer needed (i.e. at program exit or garbage collection of the R pointer).
    static void Finalize(SEXP xptr);

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

    // Is the internal state equal to this one?
    bool CheckState(lua_State* L);

private:
    lua_State* l; // lua_State in which registry is stored
};

#endif // REGISTRY_ENTRY_H
