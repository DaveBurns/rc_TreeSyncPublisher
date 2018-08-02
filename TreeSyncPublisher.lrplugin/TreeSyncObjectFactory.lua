--[[
        TreeSyncObjectFactory.lua
        
        Creates special objects used in the guts of the framework.
        
        This is what you edit to change the classes of framework objects
        that you have extended.
--]]

local TreeSyncObjectFactory, dbg, dbgf = ObjectFactory:newClass{ className = 'TreeSyncObjectFactory', register = false }



--- Constructor for extending class.
--
--  @usage  I doubt this will be necessary, since there is generally
--          only one special object factory per plugin, mostly present
--          for the sake of completeness...
--
function TreeSyncObjectFactory:newClass( t )
    return ObjectFactory.newClass( self, t )
end



--- Constructor for new instance.
--
function TreeSyncObjectFactory:new( t )
    local o = ObjectFactory.new( self, t )
    return o
end



--  Framework module loader.
--
--  @usage      Generally better to handle in other ways,
--              but this method can help when in a jam...
--
function TreeSyncObjectFactory:frameworkModule( spec )
--    if spec == 'System/Preferences' then
--        return nil
--    else
        return ObjectFactory.frameworkModule( self, spec )
--    end
end



--- Creates instance object of specified class.
--
--  @param      class       class object OR string specifying class.
--  @param      ...         initial table params forwarded to 'new' constructor.
--
function TreeSyncObjectFactory:newObject( class, ... )
    if type( class ) == 'table' then
        --if class == Manager then
        --    return TreeSyncManager:new( ... )
        --end
    elseif type( class ) == 'string' then
        if class == 'Manager' then
            return TreeSyncManager:new( ... )
        elseif class == 'ExportDialog' then
            return TreeSyncPublish:newDialog( ... )
        elseif class == 'Export' then
            return TreeSyncPublish:newExport( ... )
        elseif class == 'PublishDialog' then
            return TreeSyncPublish:newDialog( ... )
        elseif class == 'Publish' then
            return TreeSyncPublish:newExport( ... )
        end
    end
    return ObjectFactory.newObject( self, class, ... )
end



return TreeSyncObjectFactory 
-- the end.