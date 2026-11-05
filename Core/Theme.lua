local _, addon = ...

-- Colours and fonts of the window, the popups and the setup. The colours are the ForeverDB
-- design tokens (foreverdb-server packages/ui/src/styles/globals.css, documented in the
-- storybook's tokens.mdx), converted from OKLCH to sRGB. The fonts are the game's own:
-- Friz Quadrata through GameFontNormal and Arial Narrow through NumberFontNormal, so no
-- font file ships with the addon.

local Theme = {}
addon.Theme = Theme

Theme.colors = {
    background = { 0.062, 0.080, 0.094 },
    sidebar = { 0.042, 0.063, 0.079 },
    card = { 0.103, 0.126, 0.143 },
    popover = { 0.136, 0.164, 0.185 },
    secondary = { 0.158, 0.195, 0.222 },
    muted = { 0.131, 0.154, 0.172 },
    foreground = { 0.931, 0.891, 0.825 },
    mutedForeground = { 0.655, 0.630, 0.585 },
    primary = { 0.828, 0.685, 0.404 },
    primaryForeground = { 0.102, 0.084, 0.049 },
    border = { 0.260, 0.223, 0.173 },
    input = { 0.353, 0.291, 0.205 },
    success = { 0.533, 0.894, 0.548 },
    warning = { 0.962, 0.682, 0.225 },
    azure = { 0.320, 0.747, 0.848 },
    -- foreground at 6 %, the lines between rows
    hairline = { 0.931, 0.891, 0.825, 0.06 },
}

-- r, g, b, a of a colour; `alpha` overrides the colour's own.
function Theme.Color(name, alpha)
    local color = Theme.colors[name] or Theme.colors.foreground
    return color[1], color[2], color[3], alpha or color[4] or 1
end

local function frizPath()
    local path = GameFontNormal and GameFontNormal:GetFont()
    return path or "Fonts\\FRIZQT__.TTF"
end

local function narrowPath()
    local path = NumberFontNormal and NumberFontNormal:GetFont()
    return path or "Fonts\\ARIALN.TTF"
end

-- name → { path function, size }
local FONT_SPECS = {
    caption = { frizPath, 12 },
    small = { frizPath, 13 },
    body = { frizPath, 14 },
    title = { frizPath, 17 },
    wordmark = { frizPath, 18 },
    heading = { frizPath, 30 },
    number = { narrowPath, 14 },
}

local fonts = {}

-- A shared font object per name, created on first use.
function Theme.Font(name)
    local font = fonts[name]
    if font then
        return font
    end
    local spec = FONT_SPECS[name] or FONT_SPECS.body
    font = CreateFont("ForeverCollectFont_" .. name)
    font:SetFont(spec[1](), spec[2], "")
    font:SetShadowOffset(0, 0)
    fonts[name] = font
    return font
end
