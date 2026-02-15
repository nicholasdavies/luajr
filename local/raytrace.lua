-- Vector math
local function vec3(x, y, z)
    return {x = x or 0, y = y or 0, z = z or 0}
end

local function vadd(a, b)
    return vec3(a.x + b.x, a.y + b.y, a.z + b.z)
end

local function vsub(a, b)
    return vec3(a.x - b.x, a.y - b.y, a.z - b.z)
end

local function vmul(v, s)
    return vec3(v.x * s, v.y * s, v.z * s)
end

local function vdot(a, b)
    return a.x * b.x + a.y * b.y + a.z * b.z
end

local function vnorm(v)
    local len = math.sqrt(vdot(v, v))
    if len > 0 then
        return vec3(v.x / len, v.y / len, v.z / len)
    end
    return v
end

local function vlength(v)
    return math.sqrt(vdot(v, v))
end

-- Ray
local function ray(origin, direction)
    return {origin = origin, direction = direction}
end

local function ray_at(r, t)
    return vadd(r.origin, vmul(r.direction, t))
end

-- Sphere
local function sphere(center, radius, color, material)
    return {
        type = "sphere",
        center = center,
        radius = radius,
        color = color,
        material = material or {reflective = 0, diffuse = 1}
    }
end

local function intersect_sphere(s, r)
    local oc = vsub(r.origin, s.center)
    local a = vdot(r.direction, r.direction)
    local b = 2.0 * vdot(oc, r.direction)
    local c = vdot(oc, oc) - s.radius * s.radius
    local discriminant = b * b - 4 * a * c

    if discriminant < 0 then
        return nil
    end

    local t = (-b - math.sqrt(discriminant)) / (2.0 * a)
    if t > 0.001 then  -- Avoid self-intersection
        return t
    end
    return nil
end

-- Plane
local function plane(point, normal, color, material)
    return {
        type = "plane",
        point = point,
        normal = vnorm(normal),
        color = color,
        material = material or {reflective = 0, diffuse = 1}
    }
end

local function intersect_plane(p, r)
    local denom = vdot(p.normal, r.direction)
    if math.abs(denom) > 0.0001 then
        local t = vdot(vsub(p.point, r.origin), p.normal) / denom
        if t > 0.001 then
            return t
        end
    end
    return nil
end

-- Scene intersection
local function find_closest_intersection(scene, r)
    local closest_t = math.huge
    local closest_obj = nil

    for _, obj in ipairs(scene.objects) do
        local t
        if obj.type == "sphere" then
            t = intersect_sphere(obj, r)
        elseif obj.type == "plane" then
            t = intersect_plane(obj, r)
        end

        if t and t < closest_t then
            closest_t = t
            closest_obj = obj
        end
    end

    if closest_obj then
        return closest_t, closest_obj
    end
    return nil, nil
end

-- Get surface normal
local function get_normal(obj, point)
    if obj.type == "sphere" then
        return vnorm(vsub(point, obj.center))
    elseif obj.type == "plane" then
        return obj.normal
    end
    return vec3(0, 1, 0)
end

-- Lighting
local function compute_lighting(scene, point, normal, view_dir)
    local color = vec3(0, 0, 0)

    for _, light in ipairs(scene.lights) do
        local light_dir = vnorm(vsub(light.position, point))
        local light_dist = vlength(vsub(light.position, point))

        -- Check for shadows
        local shadow_ray = ray(point, light_dir)
        local shadow_t, shadow_obj = find_closest_intersection(scene, shadow_ray)

        if not shadow_t or shadow_t > light_dist then
            -- Not in shadow
            local diffuse = math.max(0, vdot(normal, light_dir))
            color = vadd(color, vmul(light.color, diffuse * light.intensity))
        end
    end

    -- Ambient
    color = vadd(color, vmul(scene.ambient, 0.1))

    return color
end

-- Main ray tracing function
local function trace_ray(scene, r, depth)
    if depth <= 0 then
        return scene.background
    end

    local t, obj = find_closest_intersection(scene, r)

    if not obj then
        return scene.background
    end

    local hit_point = ray_at(r, t)
    local normal = get_normal(obj, hit_point)
    local lighting = compute_lighting(scene, hit_point, normal, vmul(r.direction, -1))

    -- Base color with lighting
    local color = vec3(
        obj.color.x * lighting.x,
        obj.color.y * lighting.y,
        obj.color.z * lighting.z
    )

    -- Reflections
    if obj.material.reflective > 0 then
        local reflect_dir = vsub(r.direction, vmul(normal, 2 * vdot(r.direction, normal)))
        local reflect_ray = ray(hit_point, reflect_dir)
        local reflect_color = trace_ray(scene, reflect_ray, depth - 1)

        color = vadd(
            vmul(color, 1 - obj.material.reflective),
            vmul(reflect_color, obj.material.reflective)
        )
    end

    return color
end

-- Render
local function render(scene, width, height)
    local image = {}
    local aspect = width / height
    local max_depth = 3

    for y = 0, height - 1 do
        for x = 0, width - 1 do
            -- Create ray from camera through pixel
            local u = (2 * x / width - 1) * aspect
            local v = 1 - 2 * y / height

            local ray_dir = vnorm(vec3(u, v, -1))
            local r = ray(scene.camera, ray_dir)

            -- Trace ray
            local color = trace_ray(scene, r, max_depth)

            -- Clamp and convert to 0-255
            local function clamp(x)
                return math.max(0, math.min(255, math.floor(x * 255)))
            end

            table.insert(image, {
                r = clamp(color.x),
                g = clamp(color.y),
                b = clamp(color.z)
            })
        end
    end

    return image
end

-- Create a test scene
local function create_scene()
    return {
        camera = vec3(0, 1, 4),
        background = vec3(0.2, 0.3, 0.4),
        ambient = vec3(1, 1, 1),
        objects = {
            -- Three spheres with different materials
            sphere(vec3(-1, 0.5, 1), 0.5, vec3(1, 0.2, 0.2), {reflective = 0.3, diffuse = 0.7}),
            sphere(vec3(0, 0.5, -2), 0.5, vec3(0.2, 1, 0.2), {reflective = 0.6, diffuse = 0.4}),
            sphere(vec3(1, 0.5, -1.5), 0.5, vec3(0.2, 0.2, 1), {reflective = 0.1, diffuse = 0.9}),
            -- Ground plane
            plane(vec3(0, 0, 0), vec3(0, 1, 0), vec3(0.5, 0.5, 0.5), {reflective = 0.2, diffuse = 0.8}),
        },
        lights = {
            {position = vec3(2, 3, 2), color = vec3(1, 1, 1), intensity = 0.8},
            {position = vec3(-2, 2, 1), color = vec3(1, 1, 1), intensity = 0.4},
        }
    }
end

-- Main function
local function main()
    local width = 400
    local height = 300

    print("Rendering " .. width .. "x" .. height .. " image...")
    local scene = create_scene()
    local image = render(scene, width, height)
    print("Done!")

    return image, width, height
end

return main()
