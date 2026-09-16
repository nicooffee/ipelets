label = "Unwrap circle"
about = "Unwrap a circle and selected boundary points to a line segment"

local TWO_PI = 2.0 * math.pi
local CIRCLE_REL_TOLERANCE = 1.0e-7
local BOUNDARY_REL_TOLERANCE = 1.0e-5
local BOUNDARY_ABS_TOLERANCE = 1.0e-3

local last_scale = "1"
local last_direction = 1

local function warn(model, message, details)
  model:warning("Cannot unwrap circle: " .. message, details)
end

local function is_finite(value)
  return value == value and value ~= math.huge and value ~= -math.huge
end

local function atan2(y, x)
  if x > 0.0 then
    return math.atan(y / x)
  elseif x < 0.0 then
    if y >= 0.0 then
      return math.atan(y / x) + math.pi
    else
      return math.atan(y / x) - math.pi
    end
  elseif y > 0.0 then
    return 0.5 * math.pi
  elseif y < 0.0 then
    return -0.5 * math.pi
  else
    return 0.0
  end
end

local function normalise_angle(angle)
  angle = angle % TWO_PI
  if angle < 0.0 then angle = angle + TWO_PI end
  return angle
end

local function world_position(reference)
  return reference:matrix() * reference:position()
end


local function circle_geometry(obj)
  if obj:type() ~= "path" then return nil end

  local shape = obj:shape()
  if #shape ~= 1 then return nil end

  local ellipse = shape[1]
  if ellipse.type ~= "ellipse" or not ellipse[1] then return nil end

  local matrix = obj:matrix() * ellipse[1]
  local centre = matrix * ipe.Vector(0.0, 0.0)
  local radius_vector_1 = matrix * ipe.Vector(1.0, 0.0) - centre
  local radius_vector_2 = matrix * ipe.Vector(0.0, 1.0) - centre
  local radius_1 = radius_vector_1:len()
  local radius_2 = radius_vector_2:len()

  if radius_1 <= 0.0 or radius_2 <= 0.0 then return nil end

  local radius_scale = math.max(radius_1, radius_2)
  local unequal_radii = math.abs(radius_1 - radius_2) / radius_scale
  local non_orthogonal = math.abs(radius_vector_1 ^ radius_vector_2)
    / (radius_1 * radius_2)

  if unequal_radii > CIRCLE_REL_TOLERANCE
      or non_orthogonal > CIRCLE_REL_TOLERANCE then
    return nil
  end

  return {
    centre = centre,
    radius = 0.5 * (radius_1 + radius_2),
  }
end

local function read_selection(model)
  local primary = nil
  local circle = nil
  local points = {}

  for index, obj, selection in model:page():objects() do
    if selection then
      if selection == 1 then
        primary = { index = index, object = obj }
      end

      if obj:type() == "reference" then
        -- The primary reference is the cut marker, not a data point.
        if selection ~= 1 then
          points[#points + 1] = {
            index = index,
            object = obj,
            position = world_position(obj),
          }
        end
      elseif obj:type() == "path" then
        local geometry = circle_geometry(obj)
        if not geometry then
          return nil,
            "a selected path is not a circle",
            "Use a circle created with Ipe's circle/ellipse tool. " ..
            "Ellipses and non-uniformly scaled circles are not accepted."
        end
        if circle then
          return nil,
            "more than one circle is selected",
            "Select exactly one circle."
        end
        circle = {
          index = index,
          object = obj,
          centre = geometry.centre,
          radius = geometry.radius,
        }
      else
        return nil,
          "the selection contains an unsupported object",
          "Select only one circle and point marks (reference objects)."
      end
    end
  end

  if not primary then
    return nil,
      "there is no primary selection",
      "Plain-click the cut-point mark first, then Shift-click the circle " ..
      "and the data-point marks."
  end
  if primary.object:type() ~= "reference" then
    return nil,
      "the primary selection is not a point mark",
      "The cut-point mark must be the primary selection."
  end
  if not circle then
    return nil,
      "no circle is selected",
      "Select exactly one circle as a secondary selection."
  end

  local cut_position = world_position(primary.object)
  local tolerance = math.max(
    BOUNDARY_ABS_TOLERANCE,
    BOUNDARY_REL_TOLERANCE * circle.radius)

  local cut_radius = (cut_position - circle.centre):len()
  if math.abs(cut_radius - circle.radius) > tolerance then
    return nil,
      "the cut point is not on the circle",
      string.format(
        "Its radial error is %.6g Ipe units; the tolerance is %.6g.",
        math.abs(cut_radius - circle.radius), tolerance)
  end

  for number, point in ipairs(points) do
    local point_radius = (point.position - circle.centre):len()
    if math.abs(point_radius - circle.radius) > tolerance then
      return nil,
        string.format("data-point mark %d is not on the circle", number),
        string.format(
          "Its radial error is %.6g Ipe units; the tolerance is %.6g.",
          math.abs(point_radius - circle.radius), tolerance)
    end
  end

  return {
    circle = circle,
    cut_object = primary.object,
    cut_position = cut_position,
    points = points,
    boundary_tolerance = tolerance,
  }
end

local function ask_options(model)
  while true do
    local dialog = ipeui.Dialog(model.ui:win(), "Unwrap circle")
    dialog:add("scale_label", "label", { label = "Scale factor:" }, 1, 1)
    dialog:add("scale", "input", { select_all = true }, 1, 2)
    dialog:add("direction_label", "label", { label = "Direction:" }, 2, 1)
    dialog:add("direction", "combo",
      { "Counter-clockwise", "Clockwise" }, 2, 2)
    dialog:add("explanation", "label", {
      label = "The factor scales the segment and point positions; " ..
        "point-marker sizes are unchanged."
    }, 3, 1, 1, 2)
    dialog:addButton("ok", "Ok", "accept")
    dialog:addButton("cancel", "Cancel", "reject")
    dialog:set("scale", last_scale)
    dialog:set("direction", last_direction)

    if not dialog:execute() then return nil end

    local scale_text = dialog:get("scale")
    local scale = tonumber(scale_text)
    local direction = dialog:get("direction") or 1

    if scale and is_finite(scale) and scale > 0.0 then
      last_scale = scale_text
      last_direction = direction
      return {
        scale = scale,
        clockwise = direction == 2,
      }
    end

    warn(model, "the scale factor is invalid",
      "Enter a finite number greater than zero.")
  end
end

local function line_attributes(circle)
  local attributes = { pathmode = "stroked" }
  local properties = {
    "stroke", "pen", "dashstyle", "opacity", "linecap", "linejoin"
  }

  for _, property in ipairs(properties) do
    local value = circle:get(property)
    if value ~= nil and value ~= "undefined" then
      attributes[property] = value
    end
  end

  return attributes
end

local function clone_at(point, target)
  local clone = point.object:clone()
  local displacement = target - point.position
  clone:setMatrix(ipe.Translation(displacement) * point.object:matrix())
  return clone
end

local function create_unwrapped_object(input, options)
  local centre = input.circle.centre
  local radius = input.circle.radius
  local length = options.scale * TWO_PI * radius

  if not is_finite(length) then return nil end

  -- Centre the generated segment horizontally below the original circle.
  -- The fixed minimum gap keeps the output distinct for small circles.
  local gap = math.max(16.0, 0.25 * radius)
  local left = ipe.Vector(
    centre.x - 0.5 * length,
    centre.y - radius - gap)
  local right = left + ipe.Vector(length, 0.0)

  local curve = {
    type = "curve",
    closed = false,
    { type = "segment", left, right },
  }
  local segment = ipe.Path(
    line_attributes(input.circle.object), { curve })

  local cut_vector = input.cut_position - centre
  local cut_angle = atan2(cut_vector.y, cut_vector.x)
  local mapped_points = {}

  for _, point in ipairs(input.points) do
    local point_vector = point.position - centre
    local angle = atan2(point_vector.y, point_vector.x)
    local delta

    if (point.position - input.cut_position):len()
        <= input.boundary_tolerance then
      delta = 0.0
    elseif options.clockwise then
      delta = normalise_angle(cut_angle - angle)
    else
      delta = normalise_angle(angle - cut_angle)
    end

    mapped_points[#mapped_points + 1] = {
      source = point,
      distance = options.scale * radius * delta,
    }
  end

  table.sort(mapped_points, function(first, second)
    if first.distance == second.distance then
      return first.source.index < second.source.index
    end
    return first.distance < second.distance
  end)

  -- Put the segment first so that point marks are drawn on top of it.
  local elements = { segment }
  for _, point in ipairs(mapped_points) do
    local target = left + ipe.Vector(point.distance, 0.0)
    elements[#elements + 1] = clone_at(point.source, target)
  end

  return ipe.Group(elements)
end

function run(model)
  local input, message, details = read_selection(model)
  if not input then
    warn(model, message, details)
    return
  end

  local options = ask_options(model)
  if not options then return end

  local output = create_unwrapped_object(input, options)
  if not output then
    warn(model, "the scaled circumference is too large",
      "Choose a smaller scale factor.")
    return
  end

  model:creation("unwrap circle", output)
end
