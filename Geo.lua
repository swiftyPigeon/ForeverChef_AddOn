local ADDON_NAME, FC = ...

-- Map helpers shared by the recorders.
local Geo = {}
FC.Geo = Geo

local ZONE_TYPE = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3

-- Walks up from sub-maps (caves, city districts) to the owning zone so positions
-- are stored on the zone's map, where waypoints can be placed.
-- Returns nil when the client only knows the continent (it briefly reports
-- the continent map at some city gates and right after loading).
function Geo.ZoneMapID(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    while info and info.mapType and info.mapType > ZONE_TYPE and info.parentMapID and info.parentMapID ~= 0 do
        info = C_Map.GetMapInfo(info.parentMapID)
    end
    if not info or (info.mapType and info.mapType < ZONE_TYPE) then return nil end
    return info.mapID
end
