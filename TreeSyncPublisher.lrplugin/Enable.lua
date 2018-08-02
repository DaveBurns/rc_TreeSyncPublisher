--[[
        Enable.lua
--]]

if app then
    app:call( Call:new{ name='Enable', async=false, guard=App.guardSilent, main=function( call )
        -- consider logging the enabled state and implications.
    end } )
end
