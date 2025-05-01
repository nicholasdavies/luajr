local mymodule = {}

local fave_name = "Nick"

function mymodule.greet(name)
    print("Hello, " .. name .. "!")
    if name == fave_name then
        print("Incidentally, that's a great name. Nice one.")
    end
end

return mymodule
