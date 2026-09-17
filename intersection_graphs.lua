----------------------------------------------------------------------
-- Intersection Graphs ipelet
----------------------------------------------------------------------
label = "Intersection Graphs"
about = [[ Draw intersection graphs of geometric objects. This ipelet was generated using IA. ]]

V = ipe.Vector

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function getDisk(obj)
  if obj:type() ~= "path" then return nil end
  local shape = obj:shape()
  if #shape ~= 1 or shape[1].type ~= "ellipse" then return nil end
  local M = obj:matrix() * shape[1][1]
  local center = M:translation()
  local radius = (M * V(1,0) - center):len()
  return center, radius
end

local function getRectangle(obj)
  if obj:type() ~= "path" then return nil end
  local shape = obj:shape()
  if #shape ~= 1 or shape[1].type ~= "curve" or not shape[1].closed then return nil end
  local curve = shape[1]
  if #curve ~= 3 then return nil end
  for i = 1, 3 do
    if curve[i].type ~= "segment" then return nil end
  end

  local mat = obj:matrix()
  local verts = {
    mat * curve[1][1],
    mat * curve[2][1],
    mat * curve[3][1],
    mat * curve[3][2],
  }

  local xs = { verts[1].x, verts[2].x, verts[3].x, verts[4].x }
  local ys = { verts[1].y, verts[2].y, verts[3].y, verts[4].y }

  local minx = math.min(xs[1], xs[2], xs[3], xs[4])
  local maxx = math.max(xs[1], xs[2], xs[3], xs[4])
  local miny = math.min(ys[1], ys[2], ys[3], ys[4])
  local maxy = math.max(ys[1], ys[2], ys[3], ys[4])

  local center = V((minx + maxx) * 0.5, (miny + maxy) * 0.5)
  return { minx=minx, maxx=maxx, miny=miny, maxy=maxy }, center
end

local function rectsIntersect(a, b)
  return a.minx < b.maxx and b.minx < a.maxx
     and a.miny < b.maxy and b.miny < a.maxy
end

local function getSegment(obj)
  if obj:type() ~= "path" then return nil end
  local shape = obj:shape()
  if #shape ~= 1 or shape[1].type ~= "curve" or shape[1].closed then return nil end
  local curve = shape[1]
  if #curve ~= 1 or curve[1].type ~= "segment" then return nil end
  local mat = obj:matrix()
  local p = mat * curve[1][1]
  local q = mat * curve[1][2]
  local center = V((p.x + q.x) * 0.5, (p.y + q.y) * 0.5)
  return p, q, center
end

-- Returns t such that a + t*(b-a) is the intersection, or nil
local function segmentsIntersect(p1, p2, p3, p4)
  local d1 = p2 - p1
  local d2 = p4 - p3
  local denom = d1.x * d2.y - d1.y * d2.x
  if math.abs(denom) < 1e-10 then return nil end  -- parallel
  local t = ((p3.x - p1.x) * d2.y - (p3.y - p1.y) * d2.x) / denom
  local u = ((p3.x - p1.x) * d1.y - (p3.y - p1.y) * d1.x) / denom
  if t >= 0 and t <= 1 and u >= 0 and u <= 1 then return true end
  return nil
end

----------------------------------------------------------------------
-- Methods
----------------------------------------------------------------------

local function diskIntersectionGraph(model)
  local p = model:page()

  local disks = {}
  for i = 1, #p do
    if p:select(i) then
      local center, radius = getDisk(p[i])
      if center then
        disks[#disks+1] = { center = center, radius = radius }
      end
    end
  end

  if #disks < 2 then
    model:warning("Select at least 2 disks.")
    return
  end

  local subpaths = {}
  for i = 1, #disks do
    for j = i+1, #disks do
      local dist = (disks[i].center - disks[j].center):len()
      if dist <= disks[i].radius + disks[j].radius then
        subpaths[#subpaths+1] = {
          type = "curve", closed = false,
          { type = "segment", disks[i].center, disks[j].center }
        }
      end
    end
  end

  local elements = {}
  if #subpaths > 0 then
    elements[#elements+1] = ipe.Path(model.attributes, subpaths)
  end
  for _, d in ipairs(disks) do
    elements[#elements+1] = ipe.Reference(
      model.attributes, model.attributes.markshape, d.center
    )
  end

  model:creation("intersection graph of disks", ipe.Group(elements))
end

local function openDiskIntersectionGraph(model)
  local p = model:page()

  local disks = {}
  for i = 1, #p do
    if p:select(i) then
      local center, radius = getDisk(p[i])
      if center then
        disks[#disks+1] = { center = center, radius = radius }
      end
    end
  end

  if #disks < 2 then
    model:warning("Select at least 2 disks.")
    return
  end

  local subpaths = {}
  for i = 1, #disks do
    for j = i+1, #disks do
      local dist = (disks[i].center - disks[j].center):len()
      if dist < disks[i].radius + disks[j].radius then
        subpaths[#subpaths+1] = {
          type = "curve", closed = false,
          { type = "segment", disks[i].center, disks[j].center }
        }
      end
    end
  end

  local elements = {}
  if #subpaths > 0 then
    elements[#elements+1] = ipe.Path(model.attributes, subpaths)
  end
  for _, d in ipairs(disks) do
    elements[#elements+1] = ipe.Reference(
      model.attributes, model.attributes.markshape, d.center
    )
  end

  model:creation("intersection graph of disks", ipe.Group(elements))
end

local function rectangleIntersectionGraph(model)
  local p = model:page()

  local rects = {}
  for i = 1, #p do
    if p:select(i) then
      local bbox, center = getRectangle(p[i])
      if bbox then
        rects[#rects+1] = { bbox = bbox, center = center }
      end
    end
  end

  if #rects < 2 then
    model:warning("Select at least 2 rectangles.")
    return
  end

  local subpaths = {}
  for i = 1, #rects do
    for j = i+1, #rects do
      if rectsIntersect(rects[i].bbox, rects[j].bbox) then
        subpaths[#subpaths+1] = {
          type = "curve", closed = false,
          { type = "segment", rects[i].center, rects[j].center }
        }
      end
    end
  end

  local elements = {}
  if #subpaths > 0 then
    elements[#elements+1] = ipe.Path(model.attributes, subpaths)
  end
  for _, r in ipairs(rects) do
    elements[#elements+1] = ipe.Reference(
      model.attributes, model.attributes.markshape, r.center
    )
  end

  model:creation("intersection graph of rectangles", ipe.Group(elements))
end

local function segmentIntersectionGraph(model)
  local p = model:page()

  local segs = {}
  for i = 1, #p do
    if p:select(i) then
      local p1, p2, center = getSegment(p[i])
      if p1 then
        segs[#segs+1] = { p1=p1, p2=p2, center=center }
      end
    end
  end

  if #segs < 2 then
    model:warning("Select at least 2 segments.")
    return
  end

  local subpaths = {}
  for i = 1, #segs do
    for j = i+1, #segs do
      if segmentsIntersect(segs[i].p1, segs[i].p2, segs[j].p1, segs[j].p2) then
        subpaths[#subpaths+1] = {
          type = "curve", closed = false,
          { type = "segment", segs[i].center, segs[j].center }
        }
      end
    end
  end

  local elements = {}
  if #subpaths > 0 then
    elements[#elements+1] = ipe.Path(model.attributes, subpaths)
  end
  for _, s in ipairs(segs) do
    elements[#elements+1] = ipe.Reference(
      model.attributes, model.attributes.markshape, s.center
    )
  end

  model:creation("intersection graph of segments", ipe.Group(elements))
end
----------------------------------------------------------------------

methods = {
  { label = "Disks", run = diskIntersectionGraph },
  { label = "Disks (Open)", run = openDiskIntersectionGraph },
  { label = "Rectangles", run = rectangleIntersectionGraph },
  { label = "Segments", run = segmentIntersectionGraph },
  -- add more here, e.g.:
  -- { label = "Segments", run = segmentIntersectionGraph },
  -- { label = "Rectangles", run = rectangleIntersectionGraph },
}
----------------------------------------------------------------------