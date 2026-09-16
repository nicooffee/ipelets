
label = "Dense Graphs"

revertOriginal = _G.revertOriginal

about = [[
Create complete graphs, complete multipartite graphs, and complete split graphs.

This ipelet is part of Ipe.
]]

V = ipe.Vector
M = ipe.Matrix

transformShape = _G.transformShape

local PI_1_2 = 1.57079632679489661923
local MAT_ROT45 = M(0, 1, -1, 0)

local function segmentPath(attributes, a, b)
  return ipe.Path(attributes, { {
    type = "curve", closed = false,
    { type = "segment", a, b }
  } })
end

function checkPrimaryIsCircle(model, arc_ok)
  local p = model:page()
  local prim = p:primarySelection()
  if not prim then model.ui:explain("no selection") return end
  local obj = p[prim]
  if obj:type() == "path" then
    local shape = obj:shape()
    if #shape == 1 then
      local s = shape[1]
      if s.type == "ellipse" then
	return prim, obj, s[1]:translation(), shape
      end
      if arc_ok and s.type == "curve" and #s == 1 and s[1].type == "arc" then
	return prim, obj, s[1].arc:matrix():translation(), shape
      end
    end
  end
  if arc_ok then
    model:warning("Primary selection is not an arc, a circle, or an ellipse")
  else
    model:warning("Primary selection is not a circle or an ellipse")
  end
end

local function completeGraph(model)
  local prim, obj, pos, shape = checkPrimaryIsCircle(model, false)
  if not prim then return end

  local str = model:getString("Enter number of corners")
  if not str or str:match("^%s*$") then return end
  local k = tonumber(str)
  if not k or k < 3 or k > 1000 then
    model:warning("Enter a number between 3 and 1000!")
    return
  end

  local m = shape[1][1]
  local center = m:translation()
  local radius = (m * V(1,0) - center):len()
  local alpha = 2 * math.pi / k

  -- Precompute vertices
  local verts = {}
  for i = 0, k-1 do
    verts[i] = center + radius * ipe.Direction(i * alpha)
  end

  local mat = obj:matrix()

  -- Edges: one object per pair
  local elements = {}
  for i = 0, k-1 do
    for j = i+1, k-1 do
      local edge = segmentPath(model.attributes, verts[i], verts[j])
      edge:setMatrix(mat)
      elements[#elements+1] = edge
    end
  end

  -- Vertices: one Reference (mark) per vertex
  for i = 0, k-1 do
    local mark = ipe.Reference(model.attributes, model.attributes.markshape, verts[i])
    mark:setMatrix(mat)
    elements[#elements+1] = mark
  end

  model:creation("create regular k-clique", ipe.Group(elements))
end

local function arcToBeziers(m, theta)
  local K = 0.55197038140111286
  local beziers = {}
  while theta > 0 do
    if theta >= PI_1_2 then
      beziers[#beziers+1] = {
        type = "spline", m * V(1, 0), m * V(1, K),
        m * V(K, 1), m * V(0, 1)
      }
      theta = theta - PI_1_2
      m = m * MAT_ROT45
    else
      local st, ct, k = math.sin(theta), math.cos(theta),
        4 * math.tan(theta / 4) / 3
      beziers[#beziers+1] = {
        type = "spline", m * V(1, 0), m * V(1, k),
        m * V(ct + k * st, st - k * ct), m * V(ct, st)
      }
      break
    end
  end
  return beziers
end

local function bezierLenLUT(splinePath, n)
  local a, b, c, d = table.unpack(splinePath)
  local lut = { 0 }
  local lastP = nil
  for i = 0, n do
    local t = i / n
    local tn = 1 - t
    local p = tn * tn * tn * a + 3 * t * tn * tn * b +
      3 * t * t * tn * c + t * t * t * d
    if i > 0 then
      lut[#lut+1] = lut[#lut] + (p - lastP):len()
    end
    lastP = p
  end
  return lut
end

local function preprocessPath(path)
  local newPath = { closed = false }
  if path.type ~= "curve" or path.closed then return nil end

  for _, subpath in ipairs(path) do
    if subpath.type == "segment" then
      newPath[#newPath+1] = subpath
    elseif subpath.type == "spline" or subpath.type == "oldspline" or
        subpath.type == "cardinal" or subpath.type == "spiro" then
      local beziers = ipe.splineToBeziers(subpath, false)
      for _, bez in ipairs(beziers) do
        newPath[#newPath+1] = bez
      end
    elseif subpath.type == "arc" then
      local alpha, beta = subpath.arc:angles()
      local beziers = arcToBeziers(
        subpath.arc:matrix() * ipe.Rotation(alpha),
        ipe.normalizeAngle(beta - alpha, 0)
      )
      if #beziers > 0 then
        beziers[1][1] = subpath[1]
        beziers[#beziers][4] = subpath[2]
      end
      for _, bez in ipairs(beziers) do
        newPath[#newPath+1] = bez
      end
    else
      return nil
    end
  end
  return newPath
end

local function createPathLengths(path)
  local res = { total = 0 }
  for _, subpath in ipairs(path) do
    if subpath.type == "segment" then
      if subpath[1] ~= subpath[2] then
        local len = (subpath[2] - subpath[1]):len()
        res[#res+1] = {
          start = res.total, len = len, type = "segment", segment = subpath
        }
        res.total = res.total + len
      end
    elseif subpath.type == "spline" then
      if subpath[1] ~= subpath[2] or subpath[1] ~= subpath[3] or
          subpath[1] ~= subpath[4] then
        local lut = bezierLenLUT(subpath, 50)
        local len = lut[#lut]
        res[#res+1] = {
          start = res.total, len = len, type = "spline",
          spline = subpath, lut = lut
        }
        res.total = res.total + len
      end
    else
      return nil
    end
  end

  if #res == 0 or res.total <= 0 then return nil end
  return res
end

local function getOpenPath(obj)
  if obj:type() ~= "path" then return nil end
  local shape = obj:shape()
  if #shape ~= 1 then return nil end
  local path = preprocessPath(shape[1])
  if not path then return nil end
  transformShape(obj:matrix(), { path })

  local lengths = createPathLengths(path)
  if not lengths then return nil end
  return { lengths = lengths }
end

local function getCircle(obj)
  if obj:type() ~= "path" then return nil end
  local shape = obj:shape()
  if #shape == 1 and shape[1].type == "ellipse" then
    return obj, shape
  end
  return nil
end

local function pointsOnCircle(obj, shape, count)
  local pts = {}
  local m = shape[1][1]
  local center = m:translation()
  local radius = (m * V(1,0) - center):len()
  local alpha = 2 * math.pi / count
  local mat = obj:matrix()

  for i = 0, count - 1 do
    pts[#pts+1] = mat * (center + radius * ipe.Direction(i * alpha))
  end
  return pts
end

local function selectedCircleAndPath(model)
  local p = model:page()
  if not p:hasSelection() then
    model.ui:explain("no selection")
    return nil
  end

  local circles = {}
  local paths = {}
  local invalid = 0
  for i = 1, #p do
    if p:select(i) then
      local obj = p[i]
      local cobj, shape = getCircle(obj)
      if cobj then
        circles[#circles+1] = { obj = cobj, shape = shape }
      else
        local path = getOpenPath(obj)
        if path then
          paths[#paths+1] = path
        else
          invalid = invalid + 1
        end
      end
    end
  end

  if #circles ~= 1 or #paths ~= 1 or invalid ~= 0 then
    model:warning(
      "Select exactly one circle or ellipse and exactly one open path.",
      "Found " .. #circles .. " circle(s), " .. #paths ..
        " open path(s), and " .. invalid .. " invalid selected object(s)."
    )
    return nil
  end

  return circles[1], paths[1]
end

local function selectedOpenPaths(model)
  local p = model:page()
  local prim = p:primarySelection()
  if not prim then
    model.ui:explain("no selection")
    return nil
  end

  local result = {}
  for i = 1, #p do
    if i ~= prim and p:select(i) then
      local path = getOpenPath(p[i])
      if path then
        result[#result+1] = path
      end
    end
  end

  local primPath = getOpenPath(p[prim])
  if primPath then
    result[#result+1] = primPath
  end

  return result
end

local function pointAtDistance(lengths, dist)
  if dist <= 0 then
    if lengths[1].type == "segment" then return lengths[1].segment[1] end
    return lengths[1].spline[1]
  end
  if dist >= lengths.total then
    local last = lengths[#lengths]
    if last.type == "segment" then return last.segment[2] end
    return last.spline[4]
  end

  local cur = 1
  while cur < #lengths and lengths[cur].start + lengths[cur].len < dist do
    cur = cur + 1
  end

  local entry = lengths[cur]
  local localDist = dist - entry.start
  if entry.type == "segment" then
    local s, e = entry.segment[1], entry.segment[2]
    local t = localDist / entry.len
    return (1 - t) * s + t * e
  end

  local lut = entry.lut
  local j = 2
  while j < #lut and localDist > lut[j] do
    j = j + 1
  end
  local denom = lut[j] - lut[j - 1]
  local frac = (denom > 0) and ((localDist - lut[j - 1]) / denom) or 0
  local t = (j - 2 + frac) / (#lut - 1)
  local a, b, c, d = table.unpack(entry.spline)
  local tn = 1 - t
  return tn * tn * tn * a + 3 * t * tn * tn * b +
    3 * t * t * tn * c + t * t * t * d
end

local function pointsOnOpenPath(path, count)
  local pts = {}
  if count == 1 then
    pts[1] = pointAtDistance(path.lengths, 0.5 * path.lengths.total)
    return pts
  end

  for i = 1, count do
    local dist = path.lengths.total * (i - 1) / (count - 1)
    pts[i] = pointAtDistance(path.lengths, dist)
  end
  return pts
end

local function parseCommaSeparatedCounts(str)
  if not str or str:match("^%s*$") then return nil end

  local counts = {}
  for part in (str .. ","):gmatch("(.-),") do
    local nstr = part:match("^%s*(%d+)%s*$")
    if not nstr then return nil end
    local value = tonumber(nstr)
    if not value or value < 1 or value > 1000 then return nil end
    counts[#counts+1] = value
  end
  if #counts == 0 then return nil end
  return counts
end

local function multipartiteGraph(model)
  local paths = selectedOpenPaths(model)
  if not paths then return end
  if #paths < 2 then
    model:warning("Select at least two open paths.")
    return
  end

  local str = model:getString(
    "Enter n1,n2,...,nr (one value per open path; primary path last)"
  )
  if not str or str:match("^%s*$") then return end
  local counts = parseCommaSeparatedCounts(str)
  if not counts then
    model:warning("Enter integers between 1 and 1000 separated by commas.")
    return
  end
  if #counts ~= #paths then
    model:warning(
      "Enter exactly one value for each selected open path.",
      "Found " .. #paths .. " open path(s) and " .. #counts .. " value(s)."
    )
    return
  end

  local parts = {}
  for i = 1, #paths do
    parts[i] = pointsOnOpenPath(paths[i], counts[i])
  end

  local elements = {}
  for i = 1, #parts do
    for j = i + 1, #parts do
      for a = 1, #parts[i] do
        for b = 1, #parts[j] do
          elements[#elements+1] = segmentPath(
            model.attributes, parts[i][a], parts[j][b]
          )
        end
      end
    end
  end

  for i = 1, #parts do
    for j = 1, #parts[i] do
      elements[#elements+1] = ipe.Reference(
        model.attributes, model.attributes.markshape, parts[i][j]
      )
    end
  end

  model:creation("create complete multipartite graph", ipe.Group(elements))
end

local function splitGraph(model)
  local circle, path = selectedCircleAndPath(model)
  if not circle then return end

  local str = model:getString("Enter n,m (n clique vertices, m independent vertices)")
  if not str or str:match("^%s*$") then return end
  local counts = parseCommaSeparatedCounts(str)
  if not counts or #counts ~= 2 then
    model:warning("Enter two integers between 1 and 1000 in the form n,m.")
    return
  end
  local n, m = counts[1], counts[2]
  if n < 1 or m < 1 then
    model:warning("Both n and m must be at least 1.")
    return
  end

  local clique = pointsOnCircle(circle.obj, circle.shape, n)
  local independent = pointsOnOpenPath(path, m)

  local elements = {}
  for i = 1, n do
    for j = i + 1, n do
      elements[#elements+1] = segmentPath(model.attributes, clique[i], clique[j])
    end
  end
  for i = 1, n do
    for j = 1, m do
      elements[#elements+1] = segmentPath(
        model.attributes, clique[i], independent[j]
      )
    end
  end

  for i = 1, n do
    elements[#elements+1] = ipe.Reference(
      model.attributes, model.attributes.markshape, clique[i]
    )
  end
  for j = 1, m do
    elements[#elements+1] = ipe.Reference(
      model.attributes, model.attributes.markshape, independent[j]
    )
  end

  model:creation("create complete split graph", ipe.Group(elements))
end

methods = {
  { label = "Complete Graph", run = completeGraph },
  { label = "Complete Multipartite Graph", run = multipartiteGraph },
  { label = "Complete Split Graph", run = splitGraph },
}


----------------------------------------------------------------------
