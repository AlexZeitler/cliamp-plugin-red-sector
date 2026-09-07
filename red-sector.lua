-- Wireframe equalizer after the vector part of the Red Sector Inc. RSI
-- Megademo (Amiga, 1989). Five hollow bars stand on a common ground line,
-- each one driven by two spectrum bands. The whole group rotates as a rigid
-- body while a curve of points turns behind it. Hidden edges are removed with
-- per-face backface culling, so a bar shows its front, one side and its
-- slanted top, the way the original vector objects do. Bars carry the
-- terminal's spectrum colours, the point curve stays dim behind them.

local p = plugin.register({
    name = "red-sector",
    type = "visualizer",
})

local ESC = string.char(27)
local RESET = ESC .. "[0m"
local TAU = math.pi * 2

-- Cell colour tags, low to high. A cell keeps the highest tag drawn into it,
-- so bars always win over the point curve behind them. The curve's tag sits
-- below the three bar tags for exactly that reason.
local TAG_POINT = 1
local TAG_LOW, TAG_MID, TAG_HIGH = 2, 3, 4

-- ANSI 16 so the picture follows the terminal theme. The bar colours match
-- what cliamp's own spectrum uses on its default theme: bright green, bright
-- yellow, bright red. The curve is one colour throughout, plain white at
-- normal intensity, as the demo draws its points.
local TAG_COLOR = {
    [TAG_POINT] = ESC .. "[37m", -- white
    [TAG_LOW] = ESC .. "[92m",
    [TAG_MID] = ESC .. "[93m",
    [TAG_HIGH] = ESC .. "[91m",
}

-- Braille dot bit table for a 2x4 grid: BIT[dotRow+1][dotCol+1].
local BIT = {
    [1] = { [1] = 0x01, [2] = 0x08 },
    [2] = { [1] = 0x02, [2] = 0x10 },
    [3] = { [1] = 0x04, [2] = 0x20 },
    [4] = { [1] = 0x40, [2] = 0x80 },
}

local BRAILLE_BASE = 0x2800

-- UTF-8 encode a Braille codepoint (0x2800..0x28FF, always 3 bytes).
local function brailleChar(bits)
    local cp = BRAILLE_BASE + bits
    local b1 = 0xE0 + math.floor(cp / 4096)
    local b2 = 0x80 + math.floor(cp / 64) % 64
    local b3 = 0x80 + cp % 64
    return string.char(b1, b2, b3)
end

local BAR_COUNT = 5
local BAR_HALF_WIDTH = 0.26
local BAR_HALF_DEPTH = 0.26
local BAR_PITCH = 0.78    -- centre-to-centre distance between neighbours
local GROUND_Y = -1.05    -- common base line all bars stand on
local MIN_HEIGHT = 0.40
local MAX_HEIGHT = 2.30

-- The original bars do not end in a flat lid. One inclined plane cuts the top,
-- so a bar stands taller on one side than on the other and its cap is a
-- slanted face. The drop is measured off an upright bar in the demo: the top
-- falls by a little more than half the bar's own depth. Which side sits lower
-- does not show, because the object turns all the way round.
--
-- The drop must stay below MIN_HEIGHT or a quiet bar would sink through the
-- ground line. At half of it a bar at rest still keeps a shaft under the cut.
local SLANT_DROP = 0.20 -- how far the top falls across the depth of a bar

local FOCAL = 3.2
local CAMERA_Z = 6.0
local ZOOM_AMPLITUDE = 1.5  -- how far the object drifts towards the viewer
local MAX_STRETCH = 2.0     -- how far the picture may be widened past its height
local COMFORT_DOT_ROWS = 40 -- height at which no widening is needed any more

-- Rotation speeds in radians per frame. The demo tumbles the object around
-- two axes at unrelated rates, so it never repeats a pose for long.
local SPIN_Y = 0.105
local SPIN_X = 0.073      -- unrelated to SPIN_Y, so poses keep changing
local ZOOM_RATE = 0.011

-- The eight corners of a bar, as signs on its base centre. Height is filled
-- in per frame, so only the signs live here. A top corner on the front side
-- carries the drop of the inclined cut.
local CORNER_X = { -1, 1, 1, -1, -1, 1, 1, -1 }
local CORNER_Z = { -1, -1, -1, -1, 1, 1, 1, 1 }
local CORNER_TOP = { false, false, true, true, false, false, true, true }

-- Faces wound so the cross product of the first two edges points inwards.
-- A face is then visible when that normal points away from the viewer. The
-- inclined cut leaves the top a flat quad, so the winding still holds.
local FACES = {
    { 1, 2, 3, 4 }, -- front
    { 6, 5, 8, 7 }, -- back
    { 1, 4, 8, 5 }, -- left
    { 2, 6, 7, 3 }, -- right
    { 4, 3, 7, 8 }, -- top
    { 1, 5, 6, 2 }, -- bottom
}

-- The demo puts no starfield behind the object. It draws a curve of points
-- and keeps changing its shape: a closed ring, three arms winding out of the
-- centre, a tight spiral, a three-petal rosette. All of them are one curve
-- with three numbers changed, so the plugin holds one figure for a while and
-- then travels to the next.
--
-- Three arms start 120 degrees apart and each one walks a sweep of the
-- circle. sweep is how far it walks: at exactly a third the three meet end to
-- end and close the figure, beyond that they wind past each other. inner is
-- where an arm begins, as a share of the radius, so a low value opens the
-- centre into a spiral. lobe folds the radius in and out three times around,
-- which is what turns a ring into petals. A negative radius is not an error
-- there: it carries the point through the centre and out the far side, and
-- that is how a rosette closes.
local ARM_COUNT = 3
-- The list starts on the tight spiral, the one figure whose arms begin at the
-- centre, so the curve opens out of the origin. The plain closed ring is not
-- in the list: next to the bars it reads as a circle drawn around them rather
-- than as one of the figures.
local FIGURES = {
    { sweep = TAU * 0.85, inner = 0.08, lobe = 0.00 }, -- tight spiral
    { sweep = TAU * 0.55, inner = 0.25, lobe = 0.00 }, -- three open arms
    { sweep = TAU * 0.45, inner = 0.30, lobe = 0.50 }, -- curled arms
    { sweep = TAU / 3,   inner = 1.00, lobe = 0.45 }, -- three rounded lobes
    { sweep = TAU / 3,   inner = 1.00, lobe = 0.90 }, -- three petals
}
local FIGURE_RATE = 0.0060         -- how fast the list is walked, per frame
local FIGURE_HOLD = 0.55           -- share of a figure's turn spent standing still
local POINT_SPIN = 0.014           -- how fast the curve turns inside its own plane

-- The curve is anchored to the panel, not to the object. In the demo its
-- centre holds the same spot on screen while the object tumbles around it, so
-- it is laid out in dots and never touches the perspective that carries the
-- bars. It stays in x and y: the plane does not tip, does not travel in depth
-- and does not wander. Only its radius changes.
local POINT_RADIUS = 0.85          -- share of the shorter half panel, at full breath
-- Breathing is the only change of size the curve has left, so it carries the
-- growing and shrinking the demo shows. It runs slowly. The share is bounded
-- well under a half: at a half the curve shrinks to a tenth of its radius and
-- disappears inside the object, where the bars overdraw it. It is phased off
-- the cosine, so the first frame sits at the smallest radius and the curve
-- opens rather than closes.
local POINT_PULSE = 0.009
local PULSE_DEPTH = 0.25           -- share of the radius the breathing takes

-- On the first frames the curve grows out of the origin instead of appearing
-- at full size. This runs off the frame counter, so it plays once, when the
-- counter is still near zero.
local OPEN_FRAMES = 90

-- Each band sits at its own resting level and moves only a little around it:
-- in a measured stream the bass band hovers near the top while the treble
-- bands stay low, and every one of them swings by about a tenth. Read as
-- absolute heights that draws the fixed shape of the mix, not the beat. So
-- every bar tracks its own ceiling and floor and shows where the level sits
-- between them. The ceiling sinks and the floor climbs slowly, which lets the
-- pair follow a change of track without flattening a steady passage.
local ceiling = {}
local floorLevel = {}
local heights = {}
for i = 1, BAR_COUNT do
    -- Start wide open, so the first frames pull both ends onto the real range.
    ceiling[i] = 0
    floorLevel[i] = 1
    heights[i] = MIN_HEIGHT
end

local ENVELOPE_RELAX = 0.001 -- per frame, how fast ceiling and floor close in
local MIN_ENVELOPE = 0.06    -- narrowest span that still counts as movement

local function plot(grid, tags, cols, dotCols, dotRows, x, y, tag)
    if x < 0 or x >= dotCols or y < 0 or y >= dotRows then return end
    grid[y * dotCols + x + 1] = true
    local cell = math.floor(y / 4) * cols + math.floor(x / 2) + 1
    if (tags[cell] or 0) < tag then tags[cell] = tag end
end

local function drawLine(grid, tags, cols, dotCols, dotRows, x0, y0, x1, y1, tag)
    local dx = x1 - x0
    local dy = y1 - y0
    local span = math.abs(dx)
    if math.abs(dy) > span then span = math.abs(dy) end
    local steps = math.floor(span) + 1
    if steps > 512 then steps = 512 end
    for s = 0, steps do
        local t = s / steps
        plot(grid, tags, cols, dotCols, dotRows,
            math.floor(x0 + dx * t + 0.5),
            math.floor(y0 + dy * t + 0.5), tag)
    end
end

-- Rotate a model point around Y then X and project it. Returns the rotated
-- point plus its projected position in world units, before any panel scaling.
local function place(x, y, z, cosX, sinX, cosY, sinY, camZ)
    local x1 = x * cosY + z * sinY
    local z1 = -x * sinY + z * cosY
    local y1 = y * cosX - z1 * sinX
    local z2 = y * sinX + z1 * cosX
    local depth = z2 + camZ
    if depth < 0.35 then depth = 0.35 end
    local f = FOCAL / depth
    return x1, y1, z2, x1 * f, y1 * f
end

-- The point curve, drawn in the same space as the bars so both share one
-- perspective. It carries its own rotation and its own path through the
-- scene, so it turns and travels against the object instead of with it.
local function drawPointCurve(grid, tags, cols, dotCols, dotRows, frame)
    local perArm = math.floor(dotCols * dotRows / 130 / ARM_COUNT)
    if perArm < 8 then perArm = 8 end
    if perArm > 32 then perArm = 32 end

    -- Walk the list of figures. Each one stands still for most of its turn,
    -- then eases across to the next, so a shape is readable before it goes.
    local walk = frame * FIGURE_RATE
    local step = math.floor(walk)
    local here = FIGURES[step % #FIGURES + 1]
    local next_ = FIGURES[(step + 1) % #FIGURES + 1]

    local m = (walk - step - FIGURE_HOLD) / (1 - FIGURE_HOLD)
    if m < 0 then m = 0 end
    m = m * m * (3 - 2 * m) -- ease in and out, so no figure snaps into the next

    local sweep = here.sweep + (next_.sweep - here.sweep) * m
    local inner = here.inner + (next_.inner - here.inner) * m
    local lobe = here.lobe + (next_.lobe - here.lobe) * m
    -- A Braille cell holds two dots across and four down, and a terminal cell
    -- is about twice as tall as it is wide. A dot is therefore close to
    -- square, so a circle in dots reads as a circle.
    local halfPanel = math.min(dotCols, dotRows) / 2
    local radius = POINT_RADIUS * halfPanel *
        (1 - PULSE_DEPTH - PULSE_DEPTH * math.cos(frame * POINT_PULSE))

    local opening = frame / OPEN_FRAMES
    if opening > 1 then opening = 1 end
    radius = radius * opening * opening * (3 - 2 * opening)

    local originX = dotCols / 2
    local originY = dotRows / 2
    local phase = frame * POINT_SPIN

    for arm = 0, ARM_COUNT - 1 do
        local armAngle = arm * TAU / ARM_COUNT
        for k = 0, perArm - 1 do
            local t = k / perArm
            local theta = armAngle + t * sweep + phase
            local r = radius * (inner + (1 - inner) * t) *
                (1 - lobe + lobe * math.cos(ARM_COUNT * theta))

            plot(grid, tags, cols, dotCols, dotRows,
                math.floor(originX + r * math.cos(theta) + 0.5),
                math.floor(originY - r * math.sin(theta) + 0.5), TAG_POINT)
        end
    end
end

function p:render(bands, frame, rows, cols)
    if rows < 1 or cols < 8 then return "" end

    local dotCols = cols * 2
    local dotRows = rows * 4
    local grid = {}
    local tags = {}

    -- Two bands per bar, taking the louder of the pair. Averaging would let a
    -- silent band halve its partner, and the top band is empty on most
    -- material because the encoder cuts everything above 16 kHz.
    local tiers = {}
    for i = 1, BAR_COUNT do
        local a = bands[i * 2 - 1] or 0
        local b = bands[i * 2] or 0
        local level = a
        if b > level then level = b end
        if level < 0 then level = 0 end
        if level > 1 then level = 1 end

        -- Track the band's own range, then read the level against it.
        if level > ceiling[i] then
            ceiling[i] = level
        else
            ceiling[i] = ceiling[i] - ENVELOPE_RELAX
        end
        if level < floorLevel[i] then
            floorLevel[i] = level
        else
            floorLevel[i] = floorLevel[i] + ENVELOPE_RELAX
        end
        if ceiling[i] < floorLevel[i] + MIN_ENVELOPE then
            ceiling[i] = floorLevel[i] + MIN_ENVELOPE
        end

        local norm = (level - floorLevel[i]) / (ceiling[i] - floorLevel[i])
        if norm < 0 then norm = 0 end
        if norm > 1 then norm = 1 end

        local target = MIN_HEIGHT + norm * (MAX_HEIGHT - MIN_HEIGHT)
        local rate = 0.28
        if target > heights[i] then rate = 0.75 end
        heights[i] = heights[i] + (target - heights[i]) * rate

        -- Colour follows the level, using the thresholds of cliamp's spectrum.
        local shown = (heights[i] - MIN_HEIGHT) / (MAX_HEIGHT - MIN_HEIGHT)
        if shown >= 0.6 then
            tiers[i] = TAG_HIGH
        elseif shown >= 0.3 then
            tiers[i] = TAG_MID
        else
            tiers[i] = TAG_LOW
        end
    end

    local ay = frame * SPIN_Y
    local ax = frame * SPIN_X
    local cosY, sinY = math.cos(ay), math.sin(ay)
    local cosX, sinX = math.cos(ax), math.sin(ax)
    local camZ = CAMERA_Z + math.sin(frame * ZOOM_RATE) * ZOOM_AMPLITUDE

    -- Scale against a hull the object can never exceed, not against the bars
    -- as they stand this frame. Fitting the live shape would blow a quiet
    -- picture up to full height and leave the bars looking motionless. The
    -- cut only takes material away, so the hull is the plain box.
    local hullX = (BAR_COUNT - 1) / 2 * BAR_PITCH + BAR_HALF_WIDTH
    local minX, maxX = 1e9, -1e9
    local minY, maxY = 1e9, -1e9
    for sx = -1, 1, 2 do
        for sy = 0, 1 do
            for sz = -1, 1, 2 do
                local y = GROUND_Y
                if sy == 1 then y = GROUND_Y + MAX_HEIGHT end
                local _, _, _, hx, hy = place(sx * hullX, y, sz * BAR_HALF_DEPTH,
                    cosX, sinX, cosY, sinY, camZ)
                if hx < minX then minX = hx end
                if hx > maxX then maxX = hx end
                if hy < minY then minY = hy end
                if hy > maxY then maxY = hy end
            end
        end
    end

    local spanX = math.max(maxX - minX, 0.001)
    local spanY = math.max(maxY - minY, 0.001)

    -- Breathe in and out, the way the demo pulls the object towards the
    -- viewer and back. The upper bound leaves a margin at full size.
    local zoom = 0.55 + 0.30 * (0.5 + 0.5 * math.sin(frame * ZOOM_RATE))
    local fitY = (dotRows - 1) / spanY * zoom

    -- A short panel starves the object of height, so the bars are widened to
    -- stay apart. Once the panel is tall enough the picture keeps the
    -- object's own proportions.
    local stretch = COMFORT_DOT_ROWS / dotRows
    if stretch < 1 then stretch = 1 end
    if stretch > MAX_STRETCH then stretch = MAX_STRETCH end
    local fitX = math.min(fitY * stretch, (dotCols - 1) / spanX)

    local centreX = dotCols / 2 - (minX + maxX) / 2 * fitX
    local centreY = dotRows / 2 + (minY + maxY) / 2 * fitY

    -- Order does not decide what a cell shows, the tag does.
    drawPointCurve(grid, tags, cols, dotCols, dotRows, frame)

    local rx, ry, rz = {}, {}, {}
    local px, py = {}, {}

    for bar = 1, BAR_COUNT do
        local baseX = (bar - 1 - (BAR_COUNT - 1) / 2) * BAR_PITCH
        local topY = GROUND_Y + heights[bar]

        for c = 1, 8 do
            local y = GROUND_Y
            if CORNER_TOP[c] then
                y = topY
                -- The front pair sits lower. That single step is the cut.
                if CORNER_Z[c] < 0 then y = y - SLANT_DROP end
            end
            local x1, y1, z2, sx, sy = place(
                baseX + CORNER_X[c] * BAR_HALF_WIDTH, y,
                CORNER_Z[c] * BAR_HALF_DEPTH,
                cosX, sinX, cosY, sinY, camZ)
            rx[c], ry[c], rz[c] = x1, y1, z2
            px[c] = centreX + sx * fitX
            py[c] = centreY - sy * fitY
        end

        for fi = 1, #FACES do
            local face = FACES[fi]
            local i1, i2, i3 = face[1], face[2], face[3]
            local ux, uy, uz = rx[i2] - rx[i1], ry[i2] - ry[i1], rz[i2] - rz[i1]
            local vx, vy, vz = rx[i3] - rx[i2], ry[i3] - ry[i2], rz[i3] - rz[i2]
            local cnx = uy * vz - uz * vy
            local cny = uz * vx - ux * vz
            local cnz = ux * vy - uy * vx
            -- View vector from the camera to the first corner of the face.
            if cnx * rx[i1] + cny * ry[i1] + cnz * (rz[i1] + camZ) > 0 then
                for e = 1, 4 do
                    local from, to = face[e], face[e % 4 + 1]
                    drawLine(grid, tags, cols, dotCols, dotRows,
                        px[from], py[from], px[to], py[to], tiers[bar])
                end
            end
        end
    end

    local lines = {}
    for row = 0, rows - 1 do
        local parts = {}
        local dotRowStart = row * 4
        local cur = 0
        for col = 0, cols - 1 do
            local bits = 0
            local dotColStart = col * 2
            for dr = 1, 4 do
                local idx = (dotRowStart + dr - 1) * dotCols + dotColStart + 1
                if grid[idx] then bits = bits + BIT[dr][1] end
                if grid[idx + 1] then bits = bits + BIT[dr][2] end
            end

            local tag = 0
            if bits ~= 0 then tag = tags[row * cols + col + 1] or TAG_POINT end
            if tag ~= cur then
                if cur ~= 0 then parts[#parts + 1] = RESET end
                if tag ~= 0 then parts[#parts + 1] = TAG_COLOR[tag] end
                cur = tag
            end
            parts[#parts + 1] = brailleChar(bits)
        end
        if cur ~= 0 then parts[#parts + 1] = RESET end
        lines[row + 1] = table.concat(parts)
    end

    return table.concat(lines, "\n")
end
