--[[
        TreeSyncOrdererExportFilter.lua
--]]


local TreeSyncOrdererExportFilter, dbg, dbgf = ExportFilter:newClass{ className='TreeSyncOrdererExportFilter', register=true }



-- local dialogEnding (reserved for future, and reminder of past usefulness..).



--- Constructor for extending class.
--
function TreeSyncOrdererExportFilter:newClass( t )
    return ExportFilter.newClass( self, t )
end



--- Constructor for new instance.
--
function TreeSyncOrdererExportFilter:new( t )
    local o = ExportFilter.new( self, t ) -- note: new export filter class (18/Nov/2013 23:10) requires parameter table (with filter-context or export-settings) and initializes filter id, name, & title.
    -- o.enablePropName = "my-prefferred-enable-prop-name..."
    return o
end



--- This function will check the status of the Export Dialog to determine 
--  if all required fields have been populated.
--
function TreeSyncOrdererExportFilter:updateFilterStatusMethod( name, value )

    local props = self.exportSettings -- convenience var.

    app:call( Call:new{ name=str:fmtx( "^1 - Update Filter Status", self.filterName ), async=true, guard=App.guardSilent, main=function( context )

        -- base class method no longer of concern once overridden in extended class.
        
        repeat -- once
        
            --if not props[self.enablePropName] then
            --    self:allowExport( "'^1' is disabled.", self.title )
            --    break
            --else
                props[self.enablePropName] = true
                app:assurePrefSupportFile( props.pluginManagerPreset ) -- ###0
                self:allowExport( "Nothing to configure - '^1' is ready...", app:getAppName() )

            --end
            
        	-- Process changes to named properties.
        	
        	if name ~= nil then
        	
        	    -- named property has changed
    
                if name == '###0' then
        	    elseif name == 'LR_exportFiltersFromThisPlugin' then
        	        --[[
                    local status = self:requireFilterInDialog( '###0' ) -- prompts if pre-requisite filter not present.
                    if not status then -- export has been denied.
                        return
                    end
                    --]]
        	    -- else nada.
                end
            	
            end
                
            -- process stuff not tied to change necessarily.
        until true
            
        self:updateSynopsis()
            
    end, finale=function( call )
        if not call.status then
            Debug.pause( call.message )
        end
    end } )
end



--- This optional function adds the observers for our required fields metachoice and metavalue so we can change
--  the dialog depending if they have been populated.
--
function TreeSyncOrdererExportFilter:startDialogMethod()
    self:logV( "*** start dialog method execution has begun." )
    local props = self.exportSettings
    -- dialogEnding = false

    -- self:requireFilterInDialog( '###0' )    

    view:setObserver( props, self.enablePropName, TreeSyncOrdererExportFilter, TreeSyncOrdererExportFilter.updateFilterStatus )

	--view:setObserver( props, 'pluginManagerPreset', TreeSyncOrdererExportFilter, TreeSyncOrdererExportFilter.updateFilterStatus )
	
	--view:setObserver( props, '###0', TreeSyncOrdererExportFilter, TreeSyncOrdererExportFilter.updateFilterStatus )
	
    --view:setObserver( props, 'LR_exportFiltersFromThisPlugin', TreeSyncOrdererExportFilter, TreeSyncOrdererExportFilter.updateFilterStatus )

    self:updateFilterStatusMethod() -- async/guarded.
end



-- reminder: this won't be called unless derived class provided an end-dialog function - if so, the method should be provided too.
function TreeSyncOrdererExportFilter:endDialogMethod()
    app:logV( "*** end dialog method execution has begun." )
    -- dialogEnding = true
end



-- 
function TreeSyncOrdererExportFilter:updateSynopsis()
    self.exportSettings[self.synopsisPropName] = "Ready..."
end



function TreeSyncOrdererExportFilter:getSectionTitle()
    return ExportFilter.getSectionTitle( self ) -- ###0 delete this line and uncomment one of those below, if desired.
    -- return str:fmtx( "^1 - ^2", app:getAppName(), self.title ) -- if > 1, prefix with app-name as qualifier.
    -- return self.title -- presumably author has named filter as desired for section title.
end



--- This function will create the section displayed on the export dialog 
--  when this filter is added to the export session.
--
function TreeSyncOrdererExportFilter:sectionForFilterInDialogMethod()-- vf, props )
    -- there are no sections defined in base class.
    
    local props = self.exportSettings
    
    --assert( self.enablePropName, "no enable prop name" )
    local it = { title = self:getSectionTitle(), spacing=5, synopsis=bind( self.synopsisPropName ) } -- minimal spacing, add more where needed.
    
    -- space - vertical implied
    local function space( n )
        it[#it + 1] = vf:spacer{ height=n or 5 }
    end

    -- separator - full horizontal, implied.
    local function sep()
        it[#it + 1] = vf:separator { fill_horizontal=1 }
    end

    it[#it + 1] = vf:static_text {
        title = "Instructions (short version):\n \n* Select a photo source (folder or collection) that corresponds\nto exported tree folder that will have photos to be ordered.\n* Select photos (all, or just those you know are to be exported/published).\n* Export to have sort order information prepared for TreeSync Publisher.\n \n(see plugin manager for long version)",
    }
    it[#it + 1] = vf:spacer{ height=5 }

	it[#it + 1] = self:sectionForFilterInDialogGetStatusView()

	return it
	
end



--  Issues warning if all visible photos aren't selected or there is no photo source (if that's even possible).
function TreeSyncOrdererExportFilter:shouldRenderPhotoMethod( photo )
    local settings = self.exportSettings or error( "no settings" )
    if not self.srcChecked then -- object recreated with this nil/false each export.
        -- primarily: checks to see that one source is selected.
        local go, noGo = tso:checkSel()
        if go then -- go
            -- a msg may have been logged.
        elseif go == nil then -- unsure
            app:logW( noGo ) -- log warning and keep on truckin'
        else -- go is false
            app:logW( noGo )
            --self:cancelExport() -- skip render all photos (not sure if it's copacetic to do this here or not ###3)
            self.denyAll = true -- denying all is about as good as a cancel-export anyway.
        end
        self.srcChecked = true
    end
    if self.denyAll then
        return false
    else
        return true
    end
end



--- Post process rendered photos (overrides base class).
--
--  @usage reminder: in Lr3 (or Lr4/5, if 'supportsVideo' is not set), videos will not be seen by this method.
--
--  @usage ordinarily, derived type would override this method, but maybe not..
--
function TreeSyncOrdererExportFilter:postProcessRenderedPhotosMethod()

    local functionContext = self.functionContext
    local filterContext = self.filterContext
    local exportSettings = filterContext.propertyTable
    assert( self.exportSettings ~= nil, "no export settings" )
    assert( exportSettings == self.exportSettings, "export settings mis-match" )

    app:service{ name=str:fmtx( "^1 - Post-Process Rendered Photos", self.filterName ), main=function( call ) -- called from task.
    
        assert( exportSettings, "no es" )
        
        -- Debug.lognpp( exportSettings )
        -- Debug.showLogFile()
        
        local srcs = catalog:getActiveSources()
        app:assert( #srcs == 1, "Sort ordering info is tied to source - only one at a time please.." ) -- Since ordering is tied to source, only one may be done at a time.
        local src = srcs[1]
        local srcName
        local srcType
        -- note: folders dont have local IDs, so path is used instead.
        app:assert( src.getName, "Photo source should be collection or folder.., '^1' isn't, it's '^2'", cat:getSourceName( src ), cat:getSourceType( src ) )
        srcName = src:getName()
        srcType = cat:getSourceType( src )
        -- reminder: TSP will need to be reading TSO's properties.
        
        assert( self.enablePropName, "no espn" )
        if exportSettings[self.enablePropName] then
            self:log( "Filter is enabled." )
        else
            self:log( "Filter is disabled, so it won't do anything." )
            self:passRenditionsThrough()
            return
        end
    
        local rendInfo = self:peruseRenditions{ rawIds={ 'fileFormat', 'uuid' }, fmtIds={ 'fileName' }, call=call } -- get photo/rendition info...
        if not tab:is( rendInfo ) then -- this happens if user cancels the "are you sure you want to overwrite" dialog box, which shouldn't be up, still..
            app:logV( "No rendition info." )
            return
        end
        -- load convenience vars with rendition info.
        local photos = rendInfo.photos or error( "no photo array" )
        local videos = rendInfo.videos or error( "no video array" )
        local union = rendInfo.union or error( "no union array" )
        local candidates = rendInfo.candidates or error( "no candidate renditions array" )
        local unionCache = rendInfo.unionCache or error( "no union metadata cache" )
        
        local staticSettings = { -- hopefully these won't matter, but in case they do, I'd rather they be deterministic.
      		LR_collisionHandling = "overwrite",
		    LR_export_destinationType = "specificFolder",
		    LR_export_destinationPathPrefix = LrPathUtils.getStandardFilePath( 'temp' ) or "_temp_", -- again, shan't be used, so don't die if user has wonked temp dir config.
		    LR_export_useSubfolder = false,
        }
        local renditionOptions = {
            filterSettings = function( renditionToSatisfy, exportSettings )
                tab:addItems( exportSettings, staticSettings ) -- overwrite.
            end            
        }

        local all = {}
        for r1, r2 in filterContext:renditions( renditionOptions ) do
            all[#all + 1] = r1.photo
            local s, m = LrTasks.pcall( r1.skipRender, r1 )
            if s then
                -- skipped (successfully), which means no error.
                -- Note: it does not seem to help setting rendition-is-done to true, I think if it's successfully skipped, Lr won't be considering whether it's "done".
            else
                local s, m = LrTasks.pcall( r2.renditionIsDone, r2, false, str:fmtx( "Unable to skip rendering - ^1", m ) )
                if s then
                    -- and there's an end on it (maintain sts/msg set due to error skipping render.
                else
                    -- override skip-render error with error from rendition-is-done method, I guess..
                end
            end
        end

        local index = 0
        local orderSet = {}
        app:log()
        app:log( "Ordering of '^1' (^2): ^3", srcName, srcType, src.localIdentifier or "folder" )
        app:log( "----------------------" )        
        for i, p in ipairs( all ) do
            index = index + 1
            local fn = unionCache:getFmt( p, 'fileName' )
            self:log( "#^1 ^2", index, fn )
            orderSet[unionCache:getRaw( p, 'uuid' )] = index
        end
        local name = { srcType } -- root of name array.
        if src.localIdentifier then -- typically this would be a collection (definitely not a folder), but could also be a collection set or publish service.
            name[2] = src.localIdentifier
        elseif src.getPath then -- folder
            name[2] = src:getPath()
        else
            error( "unknown or unsupported source type" ) -- this wont happen since get-name member is checked above.
        end
        fprops:setPropertyForPlugin( nil, name, orderSet )
        
    end, finale=function( call, status, message )
        self:postProcessRenderedPhotosFinale( call ) -- replace this with preferred handling, if desired.
    end }
end



-- method calling "boot-strap" functions:


-- no need for extended version of update-filter-status (static) function, since class is available for assuring filter before calling update method,
-- i.e. base-class assures filter of proper class.
-- function TreeSyncOrdererExportFilter.updateFilterStatus( id, props, name, value ) - not needed.



function TreeSyncOrdererExportFilter.startDialog( propertyTable )
    local filter = ExportFilter.assureFilter( TreeSyncOrdererExportFilter, propertyTable )
    filter:startDialogMethod()
end


--- This function will create the section displayed on the export dialog 
--  when this filter is added to the export session.
--
function TreeSyncOrdererExportFilter.sectionForFilterInDialog( vf, propertyTable )
    local filter = ExportFilter.assureFilter( TreeSyncOrdererExportFilter, propertyTable )
    return filter:sectionForFilterInDialogMethod() -- vf ignored.
end



function TreeSyncOrdererExportFilter.endDialog( propertyTable)
    local filter = ExportFilter.assureFilter( TreeSyncOrdererExportFilter, propertyTable )
    filter:endDialogMethod()
end



--- This function obtains access to the photos and removes entries that don't match the metadata filter.
--
--  @usage called *before* post-process-rendered-photos function (no cached metadata).
--  @usage base class has no say (need not be called).
--
function TreeSyncOrdererExportFilter.shouldRenderPhoto( exportSettings, photo )
    local filter = ExportFilter.assureFilter( TreeSyncOrdererExportFilter, exportSettings )
    return filter:shouldRenderPhotoMethod( photo )
end



--- Post process rendered photos.
--
function TreeSyncOrdererExportFilter.postProcessRenderedPhotos( functionContext, filterContext )
    local filter = ExportFilter.assureFilter( TreeSyncOrdererExportFilter, filterContext.propertyTable, { functionContext=functionContext, filterContext=filterContext } )
    filter:postProcessRenderedPhotosMethod()
end



-- Note: there are no base class export settings.
TreeSyncOrdererExportFilter.exportPresetFields = { -- note: no UI for enable/disable, but it stays set, to satisfy base class functions which may be observing it.
    { key = ExportFilter._getPropName( TreeSyncOrdererExportFilter:getClassName(), 'enable' ), default=true }, -- ###0 filter enable property name, if using such property, and/or standard synopsis feature..
}



TreeSyncOrdererExportFilter:inherit( ExportFilter ) -- inherit *non-overridden* members.



return TreeSyncOrdererExportFilter
