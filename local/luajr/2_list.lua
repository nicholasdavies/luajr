------------------
-- 4. LIST TYPE --
------------------

-- Metatable for list
local mt_list = {
    __index = function(self, k)
        if type(k) == "number" then
            return self[0][k]
        else
            return self[0][self[0].names[k]]
        end
    end,

    __newindex = function(self, k, v)
        if type(k) == "number" then
            k = math.floor(k)
            if k < 1 or k > #self + 1 then
                error("Assignment out of list bounds.")
            end
            if v == nil then -- erasure
                table.remove(self[0], k)
                for n, j in pairs(self[0].names) do
                    if j == k then self[0].names[n] = nil end
                    if j > k then self[0].names[n] = j - 1 end
                end
            else
                self[0][k] = v
            end
        elseif type(k) == "string" then
            local i = self[0].names[k]
            if i == nil then
                self[0][#self + 1] = v
                self[0].names[k] = #self
            else
                if v == nil then -- erasure
                    table.remove(self[0], i)
                    for n, j in pairs(self[0].names) do
                        if j == i then self[0].names[n] = nil end
                        if j > i then self[0].names[n] = j - 1 end
                    end
                else
                    self[0][i] = v
                end
            end
        else
            error("Invalid key type " .. type(k) .. " in mt_list.__newindex().")
        end
    end,

    __len = function(self)
        return #self[0]
    end,

    __call = function(self, k, v)
        if type(k) ~= "string" then
            error("Can only set string-keyed attributes.")
        end
        if v == nil then
            return self[0][k]
        else
            self[0][k] = v
        end
    end,

    __pairs = function(self)
        -- inverse key lookup
        local inv = {}
        for k,v in pairs(self[0].names) do inv[v] = k end

        return function(t, k)
            -- get j as next numeric key
            local j = 0
            if type(k) == "number" then
                j = k + 1
            else
                j = t[0].names[k] + 1
            end

            -- check for past the end
            if j > #t then
                return nil
            end

            -- get k as either string if avail or integer
            if inv[j] ~= nil then
                k = inv[j]
            else
                k = j
            end

            return k, t[0][j]
        end, self, 0
    end,

    __ipairs = function(self)
        return ipairs(self[0])
    end
}

-- Constructor for list
local new_list = function()
    local list = { [0] = { names = {} } }
    setmetatable(list, mt_list)
    return list
end

-- List definition
luajr.list = new_list

-- List checker
luajr.is_list = function(obj) return getmetatable(obj) == mt_list end


