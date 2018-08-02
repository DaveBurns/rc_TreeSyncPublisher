--[[
        Disable.lua
--]]

if app then
    app:call( Call:new{ name='Disable', async=false, guard=App.guardSilent, main=function( call )
        -- app:log( app:getAppName() .. " is disabled - it must be enabled for menu, metadata, and/or export functionality..." )
    end } )
end
