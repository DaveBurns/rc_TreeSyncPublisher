--[[
        Help.lua
--]]


local Help = {}


local dbg = Object.getDebugFunction( 'HelpLocal' ) -- Usually not registered for conditional dbg support via plugin-manager, but can be (in Init.lua).



--[[
        Synopsis:           Provides help text as quick tips.
        
        Notes:              Accessed directly from plugin menu.
        
        Returns:            X
--]]        
function Help.locally()

    app:call( Call:new{ name = "HelpLocal", main=function( call )
    
        local m = {}
        m[#m + 1] = "Quick Tips"
        local msg = table.concat( m, "\n\n" )
        
        app:show( msg )
        
    end } )
end


Help.locally()
    
    
