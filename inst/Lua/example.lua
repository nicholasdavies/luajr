local mymodule = {}

mymodule.fave_name = "Nick"
mymodule.x = {y = 1}

function mymodule.greet(name)
    print("Hello, " .. name .. "!")
    if name == mymodule.fave_name then
        print("Incidentally, that's a great name. Nice one.")
    end
end

function mymodule.greets(name)
    local greeting = "Hello, " .. name .. "!"
    if name == mymodule.fave_name then
        greeting = greeting .. " Nice one!"
    end
    return greeting
end

return mymodule
