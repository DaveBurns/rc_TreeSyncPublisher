--[[
        TreeSyncPublish.lua
--]]


local TreeSyncPublish, dbg, dbgf = FtpPublish:newClass{ className = 'TreeSyncPublish' }



--[[
        To extend special publish class, which as far as I can see,
        would never be necessary, unless this came from a template,
        and plugin author did not want to change it, but extend instead.
--]]
function TreeSyncPublish:newClass( t )
    return FtpPublish.newClass( self, t )
end



--[[
        Called to create a new object to handle the export dialog box functionality.
--]]        
function TreeSyncPublish:newDialog( t )

    local o = FtpPublish.newDialog( self, t )
    o.propChgGate = Gate:new{ max = 50 }
    cat:initSmartColls() -- scrub arrays so new info used in get-sub-path, in case reglar coll-set and smart colls too.
    return o
    
end



--[[
        Called to create a new object to handle the export functionality.

        note: t includes function-context and export-context
--]]        
function TreeSyncPublish:newExport( t )

    local o = FtpPublish.newExport( self, t )
    assert( o.exportParams ~= nil, "ep nil" )
    o:initManagedPreset()
    local name = o.exportParams.LR_publish_connectionName or "export"
    o.cardFileNum = cat:getPropertyForPlugin( name .. '_cardFileNum' ) or 10000000
    o.fileToUpload = {}
    cat:initSmartColls() -- scrub arrays so new info used in get-sub-path, in case reglar coll-set and smart colls too.
    return o
    
end



-- Assures valid (reasonable) source path as much as possible (does NOT check that sample can have subpath computed, but that is done elsewhere).
-- mostly it just gets a sample photo based on source tree (folder or coll-set) specified, adjusting source-path if need be..
-- 
function TreeSyncPublish:_assureReasonableSourcePath( props )
    local photo
    local cant = props.LR_cantExportBecause -- save current setting.
    if props.destTreeType == 'coll' then
        -- note: get-master-coll-set does NOT depend on source-path.
        local collSet, collPath = Common.getMasterCollectionSet( props ) -- called a fair amount, but not repeatedly.
        if collSet==catalog then
            assert( collPath == 'Catalog', collPath )
            props.sourcePath = ""
        end
        if collSet then -- ###3 ideally I think: any-photo would be most-selected photo, if in subject set. On the other hand, maybe better if not,
            -- since arbitrary path used for any-coll (sample) photo.
            photo = cat:getAnyPhotoInCollSet( collSet, props.smartCollsToo ) -- also does not depend on source-path.
        else
            Debug.pause()
        end
        if str:is( props.sourcePath ) and not str:isBeginningWith( collPath, props.sourcePath ) then
            props.sourcePath = str:getRoot( collPath ) -- works, although it's a little iffy (treats collPath as dir-path, even though it's not) - luckily not critical..
        end
        if not photo then
            props.LR_cantExportBecause = "Setup not copacetic." -- since not legal, but something should be displayed (and button disabled) whilst bezel is up.
            app:displayInfo( "Unable to obtain sample photo from target collection set." )
        end
    else
        if not str:is( props.sourcePath ) or not fso:existsAs( props.sourcePath, 'directory' ) then
            local p = cat:getAnyPhoto()
            if p then
                local path = p:getRawMetadata( 'path' )
                local dirPath = LrPathUtils.parent( path )
                local topFolder = cat:getTopLevelFolder( dirPath, true )
                if topFolder then
                    props.sourcePath = cat:getFolderPath( topFolder )
                else
                    props.sourcePath = dirPath
                end
            end
        end
        if str:is( props.sourcePath ) then
            local folderTree = props.sourcePath
            photo = cat:getAnyPhotoInFolderTree( folderTree )
            if not photo then
                local p = cat:getAnyPhoto()
                if p then
                    local path = p:getRawMetadata( 'path' )
                    local dirPath = LrPathUtils.parent( path )
                    local topFolder = cat:getTopLevelFolder( dirPath, true )
                    if topFolder then
                        folderTree = cat:getFolderPath( topFolder )
                    else
                        folderTree = dirPath
                    end
                    photo = cat:getAnyPhotoInFolderTree( folderTree )
                    -- reminder: elsewhere it is assured that sample photo is within specified source tree, so if this photo not valid, it'll be caught.
                end
            end
            if not photo then
                props.LR_cantExportBecause = "Setup not copacetic."
                app:displayInfo( "Unable to obtain sample photo from target folder tree." )
            end
        else
            props.LR_cantExportBecause = "Setup not copacetic."
            app:displayInfo( "Unable to obtain sample photo - source path is blank." )
        end
    end
    if photo then
        props.LR_cantExportBecause = cant -- restore previous value.
    end
    return photo -- return best whack at a sample photo, or nil.
end



--[[
        Get sample photo from folder set or collection set to be mirrored.
--]]
function TreeSyncPublish:_getSamplePhoto( props )
    return self:_assureReasonableSourcePath( props )
end



--[[
        Loads site configuration from file backed prefs.
--]]
function TreeSyncPublish:initManagedPreset( ep )
    
    ep = ep or self.exportParams
    assert( ep ~= nil, "No export params / publish settings" )
    local presetName = ep.managedPreset -- convenience var.
    if not str:is( presetName ) then
        presetName = 'Default'
        Debug.pause( "No preset defined - using default." )
    end
    self.preset = app.prefMgr:getPreset( presetName, true ) -- reload backing file too.
    assert( self.preset ~= nil, "no preset" )
    
end



-- called as a service.
function TreeSyncPublish:clearJobs( props )
    -- ###
end


--[[ @16/Sep/2014 22:29 using base-class method (###2 delete after a while if no prob).
function TreeSyncPublish:_getExportParams( props )
    local myName = props.LR_publish_connectionName
    if str:is( myName ) then
        local services = catalog:getPublishServices( _PLUGIN.id )
        for i, service in ipairs( services ) do
            local name = service:getName()
            --Debug.logn( i, name )
            if name == myName then
                local ps = service:getPublishSettings()
                if ps ~= nil then
                    local ep = ps["< contents >"]
                    if ep ~= nil then
                        return ep
                    end
                else
                    Debug.pause( "?" )
                end
                break -- return nil, right?
            end
        end
    else
        return props
    end
end
--]]



function TreeSyncPublish:_computeDefaultSourcePath( props )
    app:call( Call:new{ name="Compute default source path", async=true, guard=App.guardSilent, main=function( call )
        self:_assureReasonableSourcePath( props )
    end } )
end




--   E X P O R T   D I A L O G   B O X   M E T H O D S



--- Process change to export-filenaming property - for cases when export filenaming may have some restrictions.
--
function TreeSyncPublish:processExportFilenamingChange( props, name, value )
    self.preset = nil -- assume nothing about chosen preset.
    local photo = self:_getSamplePhoto( props ) -- prefers most-sel, but accepts filmstrip[1] or all[1].
    if photo == nil then
        app:show{ warning="Unable to obtain sample photo based on setup to assure filenaming is copacetic - check source-path and collection set type/name..", actionPrefKey="Filenaming pre-check" }
        return
    end
    self:_assurePresetCache( props, photo ) --  true ) -- true => freshen for each change, since preset could be added - UPDATE: added presets don't work anyway, so may as well handled as non-existent.
    local checkTokens
    if name == 'LR_renamingTokensOn' then
        if value then
            -- app:show{ info="Renaming support has been recently added and is not thoroughly tested.", actionPrefKey = "Renaming" }
            checkTokens = props.LR_tokens
        end
    elseif name == 'LR_tokens' then
        checkTokens = value
    elseif name == 'LR_extensionCase' then
        -- Debug.pause( "No handling in base class for extension case change." )
    elseif name == 'LR_tokenCustomString' then
        -- Debug.pause( "No handling in base class for custom text change." )
    elseif name == 'LR_initialSequenceNumber' then
        -- Debug.pause( "No handling in base class for start number change." )
    else
        Debug.pause( "Unrecognized property name - ignored", name, value )
        return
    end
    if checkTokens then
        local preset = self:_getVerifiedPreset( checkTokens ) -- note: not a true preset object, but a reference to some harvested info...
        if preset then
            if self:_isSeqNum( preset.tokenString ) then
                app:show{ info="Renaming with sequence numbers may be asking for trouble if exporting via publishing service (non-publish exporting may be OK).", actionPrefKey = "Rename sequence number" }
                self.seqNum = 1
            else
                self.seqNum = nil
            end
            local s, t = LrTasks.pcall( self.getDestFilename, self, props, photo, nil ) -- nil => no cache.
            if s then
                app:logV( "Example filename: ^1", t )
            else
                app:show{ warning="There are some issues with the chosen filenaming preset - ^1", t }
            end
        else
--            Debug.pause( checkTokens )
            app:show{ warning="You may need to save filenaming preset and/or restart Lightroom to use the chosen filenaming scheme." }
            return
        end
    else
        -- Debug.pause( "not checking tokens" )
    end
end



--- Determine video format.
--
--  @param      props       export/publish settings - required.
--
function TreeSyncPublish:_getVideoFormat( props )
    if props.LR_export_videoFormat == 'original' then
        return 'original'
    elseif props.LR_export_videoFormat == "4e49434b-4832-3634-fbfb-fbfbfbfbfbfb" then
        return 'h.264'
    elseif props.LR_export_videoFormat == "3f3f3f3f-4450-5820-fbfb-fbfbfbfbfbfb" then
        return 'dpx'
    elseif str:is( props.LR_export_videoFormat ) then
        return 'unknown'
        --Debug.pause( "unknown video format", props.LR_export_videoFormat )
    else
        return nil, "No Video"
    end
end



function TreeSyncPublish:_assureCollSetProps( props )
    -- coll-set-id
    if props.destTreeType == 'coll' then
        local id = props['collSetId']
        --Debug.pause( id, value )
        if id then -- seems I should be checking if collection set ID is consistent with is-pub or not, on the other hand,
            -- user can select proper collection if not right - something to be said for leaving as is.. ###3.
            if props.collSet then
                props['collSubstring'] = props.collSetPath
            else
                props['collSubstring'] = "Click the 'Browse' button to define"
                props.LR_cantExportBecause = "Master collection set is not defined." -- ditto.
            end
        else -- user OK'd a nil/blank selection
            props['collSubstring'] = "Click the 'Browse' button to define"
            props.LR_cantExportBecause = "Master collection set is not defined." -- ditto.
        end
    -- else dont care
    end
end



--[[
        Publish parameter change handler. This would be in base property-service class.
        
        Note: can not be method, since calling sequence is fixed.
        Probably best if derived class just overwrites this if property
        change handling is desired
--]]        
function TreeSyncPublish:propertyChangeHandlerMethod( props, name, value )
    --app:call( Call:new{ name="pubPropChgHdlr", async=true, guard=App.guardSilent, main=function( call, props, name, value ) -- made async 1/Oct/2012 15:13, to support change-handling dialogs.
    -- gated not guarded - ###1 works better, and there are probably many others which should be handled in like fashion.
    -- note: when gated instead of guarded, no changes go unnoticed, so make sure prompt-once is used in app-show calls to avoid extraneous prompts.
    app:pcall{ name="tspPropChgHdlr", gate=self.propChgGate, function( call )
        
        --FtpPublish.propertyChangeHandlerMethod( self, props, name, value ) -- are we sure about this?
        props.LR_cantExportBecause = nil        -- set message below if anything not copacetic.
        -- current handling: last one to set it wins.
        
        --Debug.pauseIf( name=="collSetId", name, value )
        if props.destTreeType == 'coll' then -- then, and only then, will these be needed.
            props.collSet, props.collSetPath = Common.getMasterCollectionSet( props ) -- not quick, but not nearly as slow as psrv:init.. ###2
        end
        
        local myName = props.LR_publish_connectionName
        if name ~= nil then
            dbg( str:fmt( "Extended publish property changed, key: ^1, value: ^2", str:to( name ), str:to( value ) ) )
            repeat
                if name == 'smartCollsToo' then
                    if value then
                        if props.isPubColl then
                            local pubSrvs = PublishServices:new()
                            app:pcall{ name="Re-initialize publish service info", progress={ modal=true }, function( icall ) -- must be synchronous so not used before it's ready.
                                pubSrvs:init( icall ) -- this MUST include all plugins.
                            end, finale=function( icall )
                                if icall.status then
                                    props.pubSrvs = pubSrvs
                                else -- this has never happened yet, but defensive programming...
                                    Debug.pause( "bad init", icall.message )
                                    app:log( "*** Bad pub-srv init: ^1", icall.message )
                                    app:show{ error="Unable to initialize publish service info - ^1", icall.message }
                                    props.pubSrvs = nil -- don't try to use without re-trying initialization.
                                end
                            end }
                        else
                            cat:initSmartColls() -- immediate.
                        end
                    end
                elseif name == 'cardDelEna' then
                    if value then
                        props['cardDelMsg'] = "*** CARD DELETION IS ENABLED ***"
                    else
                        props['cardDelMsg'] = ""
                    end
                -- note: ftp-move option is no'mo'..
                elseif name == 'LR_renamingTokensOn' then
                    self:processExportFilenamingChange( props, name, value )
                elseif name == 'LR_tokens' then
                    self:processExportFilenamingChange( props, name, value )
                elseif name == 'LR_tokenCustomString' then
                    self:processExportFilenamingChange( props, name, value )
                elseif name == 'LR_initialSequenceNumber' then
                    self:processExportFilenamingChange( props, name, value )
                elseif name == 'LR_extensionCase' then
                    self:processExportFilenamingChange( props, name, value )
                elseif name == 'LR_export_videoFormat' then
                    local vfmt, vx = self:_getVideoFormat( props )
                    if vfmt ~= nil then
                        if vfmt == "dpx" then -- dpx, or so it seems to always be in my Lr copy.
                            local btn = app:show{ info="dpx video format is not supported - changing to original format until you can determine a better option (I recommend H.264)\n \nIf you are not exporting/publishing video, then choose 'Exclude Video Files' in the Video section." }
                            if btn == 'ok' then
                                props.LR_export_videoFormat = 'original'
                            else
                                app:show{ warning="Video export may not work correctly." }
                            end
                        elseif vfmt == "h.264" then
                            app:logV( "change to H.264" )
                        elseif vfmt == 'original' then
                            app:logV( "change to original video format" )
                        else
                            Debug.pause( "change to unexpected video format", vfmt ) -- "unknown".
                        end
                    else
                        app:logV( vx ) -- "No Video"
                    end
                else
                    --Debug.pause( name, value ) -- leave in for debugging.
                end
            until true
        end -- end of name-change based processing
        
        -- universal processing:
        repeat
            self:_confineServiceName( props )
            self:_assureCollSetProps( props )
            if str:is( props.LR_cantExportBecause ) then break end
        
            if props.destTreeType == 'coll' and props.collSetId then
                local catColl
                if props.collSetId == 'LrCatalog' then
                    catColl = catalog
                else
                    catColl = catalog:getCollectionByLocalIdentifier( props.collSetId ) -- will NOT get collections within publish services, but WILL get (non-publish) collection *sets*.
                end
                -- local pubColl = ### catalog:getPublishedCollectionByLocalIdentifier( props.collSetId ) -- maybe doesn't work with coll-sets - always returning nil, but documentation says it should work for sets too, hmm...
                if props.isPubColl then
                    if catColl then
                        assert( not pubColl, "both?" )
                        props.LR_cantExportBecause = "Collection set type is 'Published' but collection set chosen is 'Regular'."
                        break -- added this 27/Jun/2014 10:58, without it, the cant-export reason ends up being "generic" (since no source-subpath-is computable).
                    else
                        local pubSrvs = PublishServices:new()
                        local pubColl = pubSrvs:getCollectionSetByLocalIdentifier( props.collSetId ) -- used by common--get-master-coll-set - auto-initializes "fairly" quickly.
                        if not pubColl then
                            props.LR_cantExportBecause = "Collection set type is 'Published' but collection set name is invalid."
                            break -- added this 27/Jun/2014 10:58, without it, the cant-export reason ends up being "generic" (since no source-subpath-is computable).
                        end
                    -- else hunky dory
                    end
                else -- regular collection-set type is specified.
                    local pubSrvs = PublishServices:new()
                    local pubColl = pubSrvs:getCollectionSetByLocalIdentifier( props.collSetId ) -- used by common--get-master-coll-set - auto-initializes "fairly" quickly.
                    if pubColl then -- no regular collection set is chosen.
                        assert( not catColl, "both??" )
                        props.LR_cantExportBecause = "Collection set type is 'Regular' but collection set chosen is 'Published'."
                        break -- added this 27/Jun/2014 10:58, without it, the cant-export reason ends up being "generic" (since no source-subpath-is computable).
                    elseif not catColl then
                        props.LR_cantExportBecause = "Collection set type is 'Regular' but collection set name is invalid."
                        break -- added this 27/Jun/2014 10:58, without it, the cant-export reason ends up being "generic" (since no source-subpath-is computable).
                    -- else hunky dory
                    end
                end
            end
                
            if props.photosToo then -- photo matching
            
                -- v11:
                app:show{ info="As of TSP 11.0, with 'Photo Matching' enabled, TSP collection hierarchy will be modified to match mirrored folders or collection set when you click the 'Photo-match, auto-order, && publish' button in plugin manager.\n \nThe main benefit in so-doing, is to support publishing photos which are in multiple collections.",
                    actionPrefKey = "TSP collections re-done when photo-matching",
                    promptOnce = true,
                }

            end    

            -- assure order
            if props.assureOrder then
                local x = fprops:getPropertyForPlugin( 'com.robcole.TreeSyncOrderer', nil, false ) -- no-name => return all, force re-read?
                if tab:is( x ) then
                    if props.orderVia == 'captureTime' then -- option is checked
                        local usable, eh = exifTool:isUsable()
                        if usable then
                            -- good
                        else
                            app:show{ warning="Exiftool is not usable - ^1", eh }
                        end
                    else
                        --Debug.pause()
                    end
                else
                    -- no progress scope up, so no point in passing the call object here to the app-show method.
                    app:show{ warning="The file required for ordering is missing or does not contain requisite ordering information.\n \n'TreeSync Orderer' must be run for each mirrored (subfolder or) collection to be ordered. That can be done manually, but if you will be mirroring a publish collection set - automatic is more convenient (see button in plugin manager - at the bottom..).",
                        promptOnce = "assureOrder", -- any unique string key is fine: prompt only once per "session", unless assure-order is disabled and re-enabled.
                    }
                end
            else
                app:clearPromptOnce( "assureOrder" ) -- if assure-order has been cleared, re-enable prompting for next time it's set.
            end
            
            -- source path      
            if str:is( props.sourcePath ) then -- it use to be doing this for flat too, but that probably didn't make any sense.
                if props.destTreeType ~= 'coll' then
                    if fso:existsAs( props.sourcePath, 'directory' ) then
                        -- good
                    else
                        app:show( { warning="Source path must exist as a directory, '^1' doesn't." }, props.sourcePath )
                        props.LR_cantExportBecause = "Source Path does not exist as a directory."
                        break -- added this 27/Jun/2014 10:58, without it, the cant-export reason ends up being "generic" (since no source-subpath-is computable).
                    end
                else -- mirroring collection set.
                    if not str:isBeginningWith( props.collSetPath, props.sourcePath ) then
                        self:_assureReasonableSourcePath( props )
                    end
                end
            else
                self:_computeDefaultSourcePath( props ) -- glorified (and asynchronous) call to assure-reasonable-source-path (not entirely sure what I was thinkin' about here, but seems not causing any trouble..).
            end

            -- destination path
            if str:is( props.destPath ) then
                if fso:existsAs( props.destPath, 'directory' ) then
                    -- good
                else
                    app:show{ info="Destination path does not exist, '^1' directory will be created upon first export.",
                        subs = props.destPath,
                        actionPrefKey = "Destination will be created upon first expport",
                        promptOnce = true
                    } 
                end
            else
                if props.LR_editingExistingPublishConnection then
                    for k, v in props:pairs() do
                        Debug.logn( k, v )
                    end
                    props.destPath = LrPathUtils.child( LrPathUtils.getStandardFilePath( 'temp' ), str:fmt( "^1 - Local Destination - ^2", app:getAppName(), myName ) )
                else
                    props.destPath = LrFileUtils.chooseUniqueFileName( LrPathUtils.child( LrPathUtils.getStandardFilePath( 'temp' ), str:fmt( "^1 - Local Destination - ^2", app:getAppName(), "New" ) ) )
                end
            end

            -- scrutinize file-naming / smart-copy-naming.
            if props.LR_renamingTokensOn then
                if props.LR_tokens:find( "copy_name" ) then
                    if props.smartCopyName then
                        app:show{ warning="You can't have renaming with virtual copy name included, *and* smart virtual copy naming, at the same time. smart virtual copy naming will be disabled. consider selecting a new file naming preset, then re-enable smart virtual copy naming." }
                        props.smartCopyName = false
                    end
                end
            end
            
            local renameWithCopyName = ( props.LR_renamingTokensOn and props.LR_tokens:find( "copy_name" ) )
            if props.smartCopyName and renameWithCopyName then
                props.smartCopyName = false -- will trigger a change.
                app:show{ warning="'File Naming' includes 'Copy Name' so 'Smart Virtual Copy Naming' has been turned off. If that's not what you want, select a different 'File Naming' preset (without 'Copy Name') then re-enable 'Smart Virtual Copy Naming'." }
            elseif props.smartCopyName or renameWithCopyName then
                -- either one or the other is fine.
            else
                app:show{ warning="Virtual copy filenames will conflict with master photo filenames - not good. I recommend enabling 'Smart Virtual Copy Naming', or select a naming template that includes virtual copy name." }
                --props.smartCopyName = true - don't do this - user needs to be able to have both disabled if that's what he/she wants.
            end
            
            local anyPhoto = self:_getSamplePhoto( props ) -- assures a valid source-path too, if necessary and possible.
            if not anyPhoto then -- no source-path can happen when creating a new service.
                props.egPhoto = nil
                props.egPhotoPath = " \n \n \n \n \n" -- Lr seems to ignore "height-in-lines" spec if initial data not occupying all lines (or no data on line).
                props.filenameNonVirt = ""
                props.filenameVirtCopy = ""
                props.destFolderPath = " \n \n \n \n" -- ditto
                props.LR_cantExportBecause = "There are no valid photos in specified source tree as currently set up."
                break
            else
                props.egPhotoPath = " \n \n \n \n \n" -- ditto
                props.destFolderPath = " \n \n \n \n" -- ditto
                LrTasks.yield()
            end
            props.egPhoto = anyPhoto
            local anyPath = lrMeta:getRaw( anyPhoto, 'path' )
            local lines
            props.egPhotoPath, lines = dia:autoWrap( anyPath, 70 ) -- field is 50 of the widest characters. I can "always" get 40% more path characters in there.
            if lines > 5 then
                Debug.pause( "trunc", lines )
            end
            --Debug.pause( string.sub( props.egPhotoPath, -60 ) )
            local anyName = LrPathUtils.leafName( anyPath )
            local copyName = lrMeta:getFmt( anyPhoto, 'copyName', nil )
            props.collSet = nil -- clear cache ### (not sure this buys anything - I thought it might help with something that turned out to be (mostly) something else - now I'm afraid to take it out since working and seems maybe safer..
            local sourceSubfolderPath, whyNot = Common.getSubPath( props.sourcePath, LrPathUtils.parent( anyPath ), props.destPathSuffix, anyPhoto, props )
            if sourceSubfolderPath then
                props.egPhoto = anyPhoto
                self.exportParams = props -- icky ###2
                self.cache = lrMeta:createCache{ photos={ anyPhoto }, rawIds={ 'path', 'isVirtualCopy' }, fmtIds={ 'copyName' } } -- cache for sample is a bit overkill, but function calls for a cache.
                self.cache.rawMeta[anyPhoto].isVirtualCopy = false
                self.cache.fmtMeta[anyPhoto].copyName = ""
                local s, pth, fn = LrTasks.pcall( self.getDestPhotoPath, self, anyPhoto, sourceSubfolderPath, anyName, self.cache )
                self.cache.rawMeta[anyPhoto].isVirtualCopy = true
                self.cache.fmtMeta[anyPhoto].copyName = "Copy 1"
                local s2, pth2, fn2 = LrTasks.pcall( self.getDestPhotoPath, self, anyPhoto, sourceSubfolderPath, anyName, self.cache )
                if s then
                    --Debug.pause( fn )
                    props.filenameNonVirt = fn
                    if props.smartCopyName then
                        props.filenameVirtCopy = fn2
                    elseif props.LR_renamingTokensOn then
                        props.filenameVirtCopy = "Dictated by preset selected in 'File Naming' section above."
                    else
                        props.filenameVirtCopy = fn
                    end
                    local lines
                    props.destFolderPath, lines = dia:autoWrap( LrPathUtils.parent( pth ), 63 ) -- 45 + 40%.
                    if lines > 4 then
                        Debug.pause( "dtrunc", lines )
                    end
                else
                    --Debug.pause( pth2, fn2 )
                    props.filenameNonVirt = "Unable to get non-virtual filename"
                    props.filenameVirtCopy = "Unable to get virtual-copy filename"
                    props.destFolderPath = ""
                end
            else
                local set, pth = Common.getMasterCollectionSet( props )
                Debug.pause( whyNot, props.sourcePath, LrPathUtils.parent( anyPath ), props.destPathSuffix, anyPhoto, set, pth )
                props.filenameNonVirt = ""
                props.filenameVirtCopy = ""
                if props.destTreeType == 'coll' then
                    props.destFolderPath = "*** Selected photo not valid - check 'Collection Set Name' and 'Source Path'."
                else
                    props.destFolderPath = "*** Selected photo is not within the source (root) path."
                end
                props.LR_cantExportBecause = "Settings are invalid, or example photo is not within specified source tree."
            end
        until true
                
        -- cant get ftp settings to signal changes.        
    end, finale=function( call )
        self.propChgGate:exit()
    end }
end



--[[
        Called when dialog box is opening.
        
        Maybe derived type just overwrites this one, since property names must be hardcoded
        per export.
        
        Another option would be to just add all properties to the change handler, then derived
        function can just ignore changes, or not.
--]]        
function TreeSyncPublish:startDialogMethod( props )
	FtpPublish.startDialogMethod( self, props )
    --Debug.lognpp( props )
    
    self:propertyChangeHandlerMethod( props, nil ) -- no name.
    
	view:setObserver( props, 'sourcePath', TreeSyncPublish, FtpPublish.propertyChangeHandler )
	view:setObserver( props, 'destPath', TreeSyncPublish, FtpPublish.propertyChangeHandler )
	view:setObserver( props, 'destPathSuffix', TreeSyncPublish, FtpPublish.propertyChangeHandler )
	view:setObserver( props, 'cardDelEna', TreeSyncPublish, FtpPublish.propertyChangeHandler )
	view:setObserver( props, 'uploadImmed', TreeSyncPublish, FtpPublish.propertyChangeHandler )
	view:setObserver( props, 'collSetId', TreeSyncPublish, FtpPublish.propertyChangeHandler ) -- influences example path info displayed.
	-- ###2 (check all by passing no name?)
	view:setObserver( props, 'smartCollsToo', TreeSyncPublish, FtpPublish.propertyChangeHandler )
	view:setObserver( props, 'photosToo', TreeSyncPublish, FtpPublish.propertyChangeHandler )
	view:setObserver( props, 'assureOrder', TreeSyncPublish, FtpPublish.propertyChangeHandler )
	view:setObserver( props, 'orderVia', TreeSyncPublish, FtpPublish.propertyChangeHandler )

    -- filenaming:
	view:setObserver( props, 'LR_format', TreeSyncPublish, FtpPublish.propertyChangeHandler )
	view:setObserver( props, 'LR_renamingTokensOn', TreeSyncPublish, FtpPublish.propertyChangeHandler )
	view:setObserver( props, 'LR_tokens', TreeSyncPublish, FtpPublish.propertyChangeHandler )
	view:setObserver( props, 'LR_tokenCustomString', TreeSyncPublish, FtpPublish.propertyChangeHandler )
	view:setObserver( props, 'LR_initialSequenceNumber', TreeSyncPublish, FtpPublish.propertyChangeHandler )
	view:setObserver( props, 'LR_extensionCase', TreeSyncPublish, FtpPublish.propertyChangeHandler )
	view:setObserver( props, 'LR_export_videoPreset', TreeSyncPublish, FtpPublish.propertyChangeHandler )
	view:setObserver( props, 'LR_export_videoFormat', TreeSyncPublish, FtpPublish.propertyChangeHandler )
	view:setObserver( props, 'LR_export_videoFileHandling', TreeSyncPublish, FtpPublish.propertyChangeHandler )
	--view:setObserver( props, 'flat', TreeSyncPublish, FtpPublish.propertyChangeHandler ) -- influences example path info displayed.
	view:setObserver( props, 'destTreeType', TreeSyncPublish, FtpPublish.propertyChangeHandler ) -- influences example path info displayed.
	view:setObserver( props, 'isPubColl', TreeSyncPublish, FtpPublish.propertyChangeHandler ) -- influences example path info displayed.
	
	-- example path support
	view:setObserver( props, 'smartCopyName', TreeSyncPublish, FtpPublish.propertyChangeHandler )
	view:setObserver( props, 'copyNameTemplate', TreeSyncPublish, FtpPublish.propertyChangeHandler )

	--[[ location: not enabled for tree-sync, although I could have used it instead of destination path.
	view:setObserver( props, 'LR_export_destinationType', TreeSyncPublish, FtpPublish.propertyChangeHandler )
	view:setObserver( props, 'LR_export_useSubfolder', TreeSyncPublish, FtpPublish.propertyChangeHandler )
	view:setObserver( props, 'LR_export_destinationPathPrefix', TreeSyncPublish, FtpPublish.propertyChangeHandler )
	view:setObserver( props, 'LR_export_destinationPathSuffix', TreeSyncPublish, FtpPublish.propertyChangeHandler )
	--]]

	--[[ *** save for reminder: sFTP is not legal, since ftp-uploader app not supporting it.
    self.observeFtpPropertyChanges = { password=true, protocol=true }
    view:observeFtpPropertyChanges( self, props, 'ftpSettings', function( ftpProps, name, prev, value )
        if name == 'password' then
            return true, value
        elseif name == 'protocol' then
            if str:is( value ) then
                if value == 'ftp' then
                    return true, value
                else
                    return false, str:fmt( "^1 protocol is not supported.", value )
                end
            else
                return true, value
            end
        else
            app:error( "how so?" )
        end
    end )
    --]]
end



--[[
        Called when dialog box is closing.

        Seems to be called a little more than I'd like. ###2
        I need to have a singleton dialog box so the same warnings do not stack, or something like that...
--]]        
function TreeSyncPublish:endDialogMethod( props )
    -- *** Note: for reasons I do not understand, this may be a different set of props than at the start of dialog.
    -- FtpPublish.endDialogMethod( self, props )
    --self:_handlePasswordStorage( props )
    view:unobserveFtpPropertyChanges( self )
end



--[[
        Fetch top sections of export dialog box.
        
        Base export class replicates plugin manager top section.
        Override to change or add to sections.
--]]        
function TreeSyncPublish:sectionsForTopOfDialogMethod( vf, props )
    return FtpPublish.sectionsForTopOfDialogMethod( self, vf, props )
end



function TreeSyncPublish:browseTargetDir( props )

    app:call( Call:new{ name="browseTargetDir", async=true, guard=App.guardSilent, main=function( context )

        local paths = dia:selectFolder( { -- select save folder does not work on mac.
            title = app:getAppName() .. " - Select Destination Folder",
            label = "Select",
            canChooseFiles = false,
            canChooseDirectories = true,
            canCreateDirectories = true,
            allowsMultipleSelection = false,
            },
            props,
            'destPath'
            )
            
        --Debug.init(true)
        --Debug.pause( paths )

    end } )
    
end



local function isCompCommonAncestor( comp, i, s )

    for j, path in ipairs( s ) do
        local _ca = str:breakdownPath( path )
        if _ca[i] ~= comp then
            return false
        end
    
    end
    return true

end




function TreeSyncPublish:computeSourcePathOptions( props )

    app:call( Call:new { name="computeSourcePathOptions", async=true, guard=App.guardSilent, main=function( context )

        local targetPhotos
        local sourcePaths = {}
      
        targetPhotos = catalog:getTargetPhotos()
        local rawMeta = cat:getBatchRawMetadata( targetPhotos, { 'path', 'uuid' } )
        
        for i,targetPhoto in ipairs( targetPhotos ) do
            local path = LrPathUtils.parent( rawMeta[targetPhoto].path )
            sourcePaths[path] = true
        end
        
        local s = tab:createArray( sourcePaths )
        
        -- _debugTrace( "source paths:\n", table.concat( s, "\n" ) )
        
        local items = {}
        sourcePaths = {}
        local sourceComps = {}

        -- Note: source path is supported even if dest is flat, since it still does assure no rogue photos are exported.
        if props.destTreeType ~= 'coll' then -- folder + flat.       
            for i,path1 in ipairs( s ) do
                local comp1 = str:breakdownPath( path1 )
                sourceComps = {}
                for j,comp in ipairs( comp1 ) do
                
                    local ok = isCompCommonAncestor( comp, j, s )
                    if ok then
                        sourceComps[#sourceComps + 1] = comp
                    else
                        break
                    end
                end
                if #sourceComps > 0 then
                    local sourcePath = str:makePathFromComponents( sourceComps )
                    sourcePaths[sourcePath] = true
                end
            end
            s = tab:createArray( sourcePaths )
            local sourcePath = nil
            if #s == 0 then
                app:show( { warning="There is no common source root path - to remedy: select photo(s) to be exported which are all on the same drive.\n \n*** Note: you may need to define collection(s) of photos to be exported." } )
                return
            elseif #s == 1 then
                sourcePath = s[1]
            else
                app:show{ error="There seem to be ^1 common root paths - to remedy: select photo(s) to be exported which are all on the same drive..", #s }
                return
            end
                
            local parent = sourcePath
            while parent do
                items[#items + 1] = parent
                parent = LrPathUtils.parent( parent )
            end
        
        else -- coll
            --Debug.pause( props, props.destTreeType )
            local collSet, collPath = Common.getMasterCollectionSet( props )
            if collSet then
                local collComps = str:breakdownPath( collPath ) -- reminder: coll-path is from catalog/ps root *to* coll-set.
                items = { "", collComps[1] }
                local pth = collComps[1]
                for i = 2, #collComps do
                    pth = pth..app:pathSep()..collComps[i]
                    items[#items + 1] = pth
                end
            else
                app:show{ warning="Browse for collection set first." }
                return
            end
        --else
        --    app:show{ warning="Source Path not supported for ^1", props.destTreeType }
        --    return
        end
    
        -- probably no need for this double-wrapper:
        LrFunctionContext.callWithContext( 'Source Root Selection', function( context )
        
            local pt = LrBinding.makePropertyTable( context )
            
            pt.sourceRoot = items[#items]
            for i, it in ipairs( items ) do
                if it == props.sourcePath then
                    pt.sourceRoot = it
                    break
                end
            end
    
            local c = vf:column{
            
                bind_to_object = pt,
                
                vf:row{
                    vf:static_text{
                        title = "Select an appropriate source root path:",
                    },
                },
                
                vf:row{
                    vf:combo_box{
        				fill_horizontal = 1,
                        items = items,
                        value = LrView.bind( 'sourceRoot' ),
                    },
                },
            
            }
            
            local button = LrDialogs.presentModalDialog{
                title = app:getAppName() .. " - Select Source Path",
                contents = c,
            }
            
            if button == 'ok' then
                local val = str:to( pt.sourceRoot )
                if str:is( val ) or props.destTreeType == 'coll' then
                    props.sourcePath = val -- blank is legal if coll.
                else
                    app:show( { error="No source root property." } )
                end
            end
        
        end )
    
    end } )
    

end



function TreeSyncPublish:getFtpAppPgmArgs()
    error( "###" )
end



function TreeSyncPublish:startFtpUploader()
    error( "###" )
end



--[[
        Fetch bottom sections of export dialog box.
        
        Base export class returns nothing.
        Override to change or add to sections.
--]]        
function TreeSyncPublish:sectionsForBottomOfDialogMethod( vf, props )


	self:initManagedPreset( props ) -- assign self.preset for getting advanced prefs. (could be in start dialog, but only needed here so far).


    local section = { bind_to_object = props }
    
    section.title = app:getPluginName() .. " Settings"
    section.synopsis = nil
	section.spacing = vf:label_spacing()

    --   C O M M O N   O P T I O N S
    
    -- subsection header:
    section[#section + 1] =
        vf:static_text{
            title = "Common Options",
            fill_horizontal = .8,
            alignment = 'center'
        }
    section[#section + 1] = vf:spacer{ height=5 }
        
    -- subsection options
    section[#section + 1] = 
		vf:row {
			vf:static_text {
				title = "Destination Path:",
				alignment = 'left',
				width = share 'genLabelWidth',
				text_color = LrColor( 'blue' ),
				tooltip = "click to visit destination location",
                mouse_down = function( button )
                    if str:is( props.destPath ) and fso:existsAsDir( props.destPath ) then
                        LrShell.revealInShell( props.destPath )
                    else
                        app:show{ warning="Directory non-existent: ^1", props.destPath or "blank" }
                    end
                end,                    
			},

			vf:edit_field {
                tooltip = "Path to local folder where rendered photos will be copied (permanently, or temporarily before uploading).",
				width_in_chars = 40,
				width = share 'pathWidth',
				value = bind 'destPath',
			},
			vf:push_button {
                title = "Browse",
                tooltip = "Select and/or create destination folder (a.k.a. target directory).",
                width = share 'acol2Width',
                props = props,
                action = function( button )
                    self:browseTargetDir( button.props )
                end,                    
			},
		}

    section[#section + 1] = 
		vf:row {
			vf:static_text {
				title = "Destination Subfolder:",
				alignment = 'left',
				width = share 'genLabelWidth',
			},
			vf:edit_field {
                tooltip = str:fmtx( "Export to subfolder if desired - for child folder, enter simple name; for grand-child folder enter child-name^1grandchild-name; for sibling, enter ..^1name; for parent folder, enter ..^1..^1name, etc.", app:pathSep() ),
				width_in_chars = 40,
				width = share 'pathWidth',
				value = bind 'destPathSuffix',
			},
		}

    
    if props.flat then -- left over from previous version
        props.destTreeType = 'flat' -- migrate to new way.
        props.flat = nil
    end

    section[#section + 1] = vf:spacer{ height=1 }
    section[#section + 1] = vf:row {
        vf:static_text {
            title = "Destination Tree\n(make same as)",
	        width = share 'genLabelWidth',
        },
        vf:radio_button {
            title = "Source folder tree",
            value = bind 'destTreeType',
            checked_value = 'folder',
        },
        vf:radio_button {
            title = "Specified Collection Set",
            value = bind 'destTreeType',
            checked_value = 'coll',
        },
        vf:radio_button {
            title = "Flat (not tree)",
            value = bind 'destTreeType',
            checked_value = 'flat',
        },
    }
    
    local collEnaBinding = LrBinding.keyEquals( 'destTreeType', 'coll' )
        
    section[#section + 1] = vf:spacer{ height=1 }
    section[#section + 1] = vf:row {
	    vf:static_text{
	        title = "Collection Set Type",
	        width = share 'genLabelWidth',
	        enabled = collEnaBinding,
	    },
		vf:radio_button {
		    title = "Published",
			value = bind'isPubColl',
			checked_value=true,
			tooltip = "If checked, collection set will be a publish service, or a set within a publish service.",
	        enabled = collEnaBinding,
		},
		vf:radio_button {
		    title = "Regular",
			value = bind'isPubColl',
			checked_value=false,
			tooltip = "If checked, collection set will be a regular (non-publish) collection set.", -- ditto.
	        enabled = collEnaBinding,
		},
		vf:spacer{ width=15 },
		vf:checkbox {
		    value = bind'smartCollsToo',
		    title = "Smart Collections",
		    tooltip = "If checked, photos will be considered valid for export/publishing even if in smart collection within collection set - note: there will be a performance penalty at the beginning of each export/publish operation; if unchecked, only non-smart collections will be considered.",
            enabled = collEnaBinding,
		},
    }
    
    section[#section + 1] = vf:row {
	    vf:static_text{
	        title = "Collection Set Name",
	        width = share 'genLabelWidth',
	        enabled = collEnaBinding,
	    },
		vf:push_button {
		    title="Browse",
	        enabled = collEnaBinding,
		    action=function( button )
		        app:pcall{ name="Browse for collection set", async=true, progress=true, guard=App.guardVocal, main=function( call )
		            call:setCaption( "Dialog box needs your attention..." )
		            local popupItems = { { title="The Catalog As Collection Set (Experimental)", value='LrCatalog' }, { separator=true } }
		            tab:appendArray( popupItems, cat:getCollectionSetPopupItems( props.isPubColl ) )
    		        local button = app:show{ confirm="Select ^1 Collection Set",
    		            subs = props.isPubColl and "Publish" or "Regular", -- ###1 make this change to Exporder too.
    		            viewItems = {
                            vf:popup_menu {
                                bind_to_object = props,
                                value = bind 'collSetId',
                                items = popupItems,
                            }
                        }
                    }
                    -- Debug.pause( catalog:getPublishedCollectionByLocalIdentifier( props.collSetId ) ) - always nil: either broken or expects some other param.
                    -- Debug.pause( props.collSetId, Common.getMasterCollectionSet( props ) )
                end }
		    end,
		},
		vf:static_text {
		    title = bind'collSubstring',
		    width_in_chars = 50,
			tooltip = "Name (or path) of collection which defines the exported (destination) tree structure.",
	        enabled = collEnaBinding,
		},
    }
    
    local viaEnaBinding = binding:getMatchBinding{ props=props, trueKeys={ 'assureOrder' }, unValueTable={ destTreeType="flat" } }
    section[#section + 1] = vf:spacer{ height=5 }
    section[#section + 1] = vf:row {
		vf:checkbox {
		    value = bind'photosToo',
		    title = "Photo Matching",
	        width = share 'genLabelWidth',
		    tooltip = "If checked, TSP collection hierarchy (and hence photos-to-be-published) will be auto-created to match hierarchy of source folders or collection set being mirrored..\n \n****** If unchecked, then YOU must take responsibility for defining (via collections in this publish service) photos to-be-published, e.g. a metadata-based smart collection.",
            enabled = binding:getMatchBinding{ props=props, unValueTable = { destTreeType="flat" } }, -- disable if flat.
        },
		vf:spacer{ width=10 },
        vf:checkbox {
            title = "Sort Order Via",
            value = bind'assureOrder',
	        width = share 'genLabelWidth',
	        tooltip = "Touch export file date/time to reflect custom/user sort order.",
	        enabled = binding:getMatchBinding{ props=props, unValueTable = { destTreeType="flat" } }, -- disable if flat.
        },
        vf:radio_button {
            title = 'File Creation Time',
            value=bind'orderVia',
            checked_value = 'createdTime',
            enabled = bind'assureOrder',
	        tooltip = "Touch exported file creation dates to reflect custom/user sort order.",
	        enabled = viaEnaBinding,
        },
        --[[ mod time doesn't really make good sense to me.
        vf:radio_button {
            title = 'File Modification Time',
            value=bind'orderVia',
            checked_value = 'createdTime',
	        enabled = viaEnaBinding,
	        tooltip = "Touch exported file modification dates to reflect custom/user sort order.",
        },
        --]]
        vf:radio_button {
            title = 'Image Capture Time',
            value=bind'orderVia',
            checked_value = 'captureTime',
	        enabled = viaEnaBinding,
        },
    }
    
    section[#section + 1] = vf:spacer{ height=2 }
    --local folderEnaBinding = LrBinding.keyEquals( 'destTreeType', 'folder' ) - sp currently applies to all types.
    section[#section + 1] = 
			vf:row {
				vf:static_text {
					title = "Source Path:",
					alignment = 'left',
					width = share 'genLabelWidth',
					--enabled = folderEnaBinding,
				},
	
				vf:edit_field {
                    tooltip = "Serves 2 purposes: determines whether photos will be exportable (or publishable) - they have to be \"within\" the source branch defined by the source path, *and* determines the path depth of the exported (destination) tree. The shorter the source path, the deeper the destination tree. Generally you want this short enough to encompass all photos you plan to export with these settings, yet long enough to avoid having an excessively deep destination tree. If you don't know what to do, try the shortest path first, then go from there...",
					fill_horizonal = 1,
					width_in_chars = 40, 
					width = share 'pathWidth',
					value = bind 'sourcePath',
						-- TO DO: Should validate (is existing directory...).
					--enabled = folderEnaBinding,
				},
				vf:push_button {
                    title = "Select",
                    tooltip = "Compute options for source path based on selected photos (and destination tree type).",
                    width = share 'acol2Width',
                    props = props,
					--enabled = folderEnaBinding,
                    action = function( button )
                        self:computeSourcePathOptions( button.props )
                    end,                    
				},
			}
    section[#section + 1] = vf:spacer{ height=2 }
    
    section[#section + 1] = 
			vf:row {
				vf:checkbox {
					title = "Ignore Photos Buried In Stack (in folder of origin)",
                    tooltip = "If checked, photos buried under others in a stack (in folder of origin) are ignored; if un-checked, in-folder stacking is not considered.",
					value = bind 'ignoreBuried',
				},
				vf:checkbox {
					title = "Add to Catalog",
                    tooltip = "If checked, exported photos will be added to catalog (if not already in it); if un-checked, exported photos will accessible externally, but not inside Lightroom.",
					value = bind 'addToCatalog',
				},
			}
    section[#section + 1] = vf:spacer{ height=1 }
    section[#section + 1] = 
			vf:row {
			    vf:static_text {
			        title = "Original RAW Files",
					width = share 'genLabelWidth',
			    },
				vf:checkbox {
					title = "Include",
                    --tooltip = "If checked, xmp sidecars will accompany proprietary raw files into the destination (whether up-to-date, or not - just like originals with embedded xmp).",
					value = bind 'inclRaws',
					enabled = LrBinding.keyEquals( 'LR_format', 'ORIGINAL' ),
				},
				vf:checkbox {
					title = "If newer (or not present)",
                    --tooltip = "If checked, xmp sidecars will accompany proprietary raw files into the destination (whether up-to-date, or not - just like originals with embedded xmp).",
					enabled = LrBinding.keyEquals( 'LR_format', 'ORIGINAL' ),
					value = bind 'inclRawsIfSensible',
				},
			}
    section[#section + 1] = 
			vf:row {
			    vf:static_text {
			        title = "XMP Sidecars",
					width = share 'genLabelWidth',
			    },
				vf:checkbox {
					title = "Include",
                    --tooltip = "If checked, xmp sidecars will accompany proprietary raw files into the destination (whether up-to-date, or not - just like originals with embedded xmp).",
					value = bind 'inclXmp',
					enabled = LrBinding.keyEquals( 'LR_format', 'ORIGINAL' ),
				},
				vf:checkbox {
					title = "If significantly changed",
                    --tooltip = "If checked, xmp sidecars will accompany proprietary raw files into the destination (whether up-to-date, or not - just like originals with embedded xmp).",
					value = bind 'inclXmpIfChanged',
					enabled = LrBinding.keyEquals( 'LR_format', 'ORIGINAL' ),
				},
			}
    section[#section + 1] = vf:spacer{ height=1 }
    section[#section + 1] = 
			vf:row {
			    vf:static_text {
			        title = "Local Viewing App",
					width = share 'genLabelWidth',
			    },
				vf:edit_field {
                    --tooltip = "If checked, xmp sidecars will accompany proprietary raw files into the destination (whether up-to-date, or not - just like originals with embedded xmp).",
					value = bind 'localViewer',
					width_in_chars = 40,
					enabled = LrBinding.negativeOfKey( 'ftpMove' ),
				},
				vf:push_button {
					title = "Browse",
                    --tooltip = "If checked, xmp sidecars will accompany proprietary raw files into the destination (whether up-to-date, or not - just like originals with embedded xmp).",
					enabled = LrBinding.negativeOfKey( 'ftpMove' ),
					action = function( button )
					    app:call( Call:new{ name=button.title, async=true, guard=App.guardVocal, main=function( call )
					        local dir
					        if WIN_ENV then
					            dir = "C:\\Program Files"
					        else
					            dir = "/Applications"
					        end
					        local f = dia:selectFile( {
					            title=str:fmt( "^1 needs you to select an executable file for viewing photos...", app:getAppName() ),
					            initialDirectory = dir,
					        },
					        props,
					        'localViewer'
					        )
					    end } )
					end,
				},
			}

    section[#section + 1] = vf:spacer{ height=5 }
    section[#section + 1] = 
			vf:row {
			    vf:checkbox {
			        title = "Smart Virtual Copy Naming",
					--width = share 'genLabelWidth',
					value = bind 'smartCopyName',
			    },
                vf:spacer{ width=10 },
			    vf:edit_field {
			        title = "Virtual Copy Template",
					--width = share 'genLabelWidth',
					width_in_chars = 12,
					value = bind 'copyNameTemplate',
					immediate = true,
			    },
			}
    section[#section + 1] = vf:spacer{ height=10 }
    section[#section + 1] = vf:row {
        vf:static_text {
            title = 'Example: (based on photo below, as master, and as virtual copy named "Copy 1" )',
        }
    }
    section[#section + 1] = vf:row {
        vf:static_text {
            title = 'Source Photo Path:',
        },
        vf:static_text {
            title = bind 'egPhotoPath',
            width_in_chars = 50,
            height_in_lines = 5,
            --wrap = true,
        },
    }
    section[#section + 1] = vf:row {
        view:getThumbnailViewItem{ viewOptions = {
            photo = bind 'egPhoto',
        } },
    }
    section[#section + 1] = vf:row {
		    vf:static_text {
		        title = "Destination Photo Folder:",
		        width = share 'exa_lbl_wid',
		    },
			vf:static_text {
			    title = bind 'destFolderPath',
                width_in_chars = 45, -- label is wider than source photo file path
			    height_in_lines = 4, -- should never-the-less require few lines, since there will be no filename.
                --wrap = true,
			},
	    }
    section[#section + 1] = vf:row {
		    vf:static_text {
		        title = "Master Photo Filename:",
		        width = share 'exa_lbl_wid',
		    },
			vf:static_text {
			    title = bind 'filenameNonVirt',
			    fill_horizontal = 1,
			    --enabled = bind 'smartCopyName',
			},
	    }
    section[#section + 1] = vf:row {
		    vf:static_text {
		        title = "Virtual Copy Filename:",
		        width = share 'exa_lbl_wid',
		    },
			vf:static_text {
			    title = bind 'filenameVirtCopy',
			    fill_horizontal = 1,
			    --enabled = bind 'smartCopyName',
			},
	    }
			
			
	--   C A R D   P U B L I S H I N G   O P T I O N S		
	if self.preset:getPref( 'cardPubEna' ) then -- optional section.
	
	    -- subsection header:
        section[#section + 1] = vf:spacer{ height=5 }
        section[#section + 1] = vf:separator{ fill_horizontal=1 }
        section[#section + 1] =
            vf:static_text{
                title = "Card Publishing Options",
                fill_horizontal = .8,
                alignment = 'center'
            }
        section[#section + 1] = vf:spacer{ height=5 }
        
        -- subsection items:
        section[#section + 1] = 
    		vf:row {
    			vf:static_text {
    				title = "If 'Card Deletion' is enabled, then all files in DCIM subfolders will be deleted after export/publishing,\nsubject to your approval, after presenting a complete list.",
    			},
    			--vf:static_text {
    			--	title = "Path to DCIM folder on card",
    			--},
    		}
    	section[#section + 1] =
			vf:row {
				vf:checkbox {
					title = "Card Deletion",
					value = bind 'cardDelEna',
					width = share 'w1',
				},
				vf:static_text {
				    title = bind 'cardDelMsg',
				    fill_horizontal = 1,
				},
			}
        section[#section + 1] = 
    		vf:row {
    			vf:static_text {
    				title = "Path to DCIM folder on card",
					width = share 'w1',
    			},
    			vf:edit_field {
    			    value = bind 'dcimPath',    
    			    width_in_chars = 30,
    			    enabled = bind 'cardDelEna',
    			},
    			vf:push_button {
    			    title = 'Browse',
    			    enabled = bind 'cardDelEna',
    			    props = props,
    			    action = function( button )
    			        local folder = dia:selectFolder( { title = 'Select DCIM folder on card' },
    		                button.props,
    		                'dcimPath')
    			    end,
    			},
    		}
	    section[#section + 1] = vf:spacer{ height = 2 }
        section[#section + 1] = 
			vf:row {
				vf:checkbox {
					title = "Legacy filesystem compatibility - ensures 8.3 filename, for when destination is on old-style card...",
                    tooltip = "If checked, will assign filenames that satisfy card filesystem.",
					value = bind 'cardCompat',
					enabled = true -- LrBinding.negativeOfKey( 'LR_renamingTokensOn' ),
				},
			}
    end
    
    --   R E M O T E   P U B L I S H I N G   O P T I O N S

    local ftpAppRelBinding = bind'remPub'
    
    -- subsection header:
    section[#section + 1] = vf:spacer{ height = 5 }
    section[#section + 1] = vf:separator{ fill_horizontal=1 }
    section[#section + 1] =
        vf:static_text{
            title = "Remote Publishing Options",
            fill_horizontal = .8,
            alignment = 'center'
        }
    section[#section + 1] = vf:spacer{ height=5 }
    
    -- subsection items:
    
    section[#section + 1] = 
		vf:row {
			vf:checkbox {
				title = str:fmtx( "Remote Publishing" ), -- no longer considered experimental on Windows platform.
                tooltip = "if checked, publishing to remote host will be enabled; if unchecked, photos will be exported to local host only.",
				value = bind 'remPub',
                width = share 'genLabelWidth',
			},
    		vf:checkbox {
    		    title = "Start FTP App Automatically",
    		    value = bind 'uploadImmed',
    		    enabled = bind 'remPub',
    		    --tooltip = "if checked, files are uploaded immediately; if unchecked uploading will be deferred. If using FTP upload app, it will remember which files need to be uploaded later. If not using FTP upload app, published photos will be added to the \"These photos need to be uploaded\" collection when uploading is being deferred - a validation run can be used to upload & validate later.",
    		    tooltip = "if checked, FTP Aggregator app will be started, if not already running, prior to commencing with export/publishing. If FTP Aggregator is online (ftp enabled), exported files will be uploaded immediately after rendering; if unchecked, uploading will be deferred. FTP Aggregator app will remember which files need to be uploaded, so you can initiate uploading manually (by starting the FTP Aggregator app) at your convenience (like after all files are exported, or internet connection is available..).",
    		},
		}

    local enabledBinding = bind( 'remPub' )
    local s1 = section

    if str:is( props.LR_publish_connectionName ) then -- publish service: ftp serice name is same as publish connection name.
        app:logV( "publish service: ftp service name is same as publish connection name." )
    else
        s1[#s1 + 1] = vf:spacer{ height=7 }
        s1[#s1 + 1] = vf:row {
            vf:static_text {
                title = "Service Name",
	            width = share'lbl_wid_1',
	            enabled = enabledBinding,
            },
            vf:edit_field {
                value = bind'serviceName',
                --width_in_chars = 30,
                width = share 'dat_wid_2',
	            enabled = enabledBinding,
            },
        }
    end

    section[#section + 1] = vf:spacer{ height=5 }
    local ftpView = view:getFtpSettingsView( self, props, enabledBinding, false, { width=share'lbl_wid_1' }, { width=share'dat_wid_2' } )
    section[#section + 1] = ftpView
    section[#section + 1] = vf:spacer{ height=5 }

    section[#section + 1] = vf:spacer{ height=10 }
        s1[#s1 + 1] = 
			vf:row {
				vf:static_text {
					title = " ",
                    width = share 'genLabelWidth',
				},
				vf:static_text {
				    title = "Manual control - not normally needed:"
				},
            }
        s1[#s1 + 1] = 
			vf:row {
				vf:static_text {
					title = "FTP Control:",
                    width = share 'genLabelWidth',
				},
				vf:push_button {
                    title = 'Start FTP App',
                    enabled = bind'remPub',
                    props = props,
                    tooltip = "If 'Upload via External App' is enabled, this button is normally not needed - the app will start automatically. This button is to initiate uploading that has been deferred...",
                    action = function( button )
                        app:pcall{ name=button.title, async=true, guard=App.guardVocal, progress=true, function( call )
                            local s, m = ftpAgApp:assureRunning( button.props.ftpAggApp ) -- synchronous
                            call:setCaption( "Dialog box needs your attention.." )
                            if s then
                                app:show{ info="FTP Aggregator is running." }
                            else
                                app:show{ warning=m }
                            end
                        end }
                    end,
				},
				vf:push_button {
                    title = 'Stop FTP App',
                    props = props,
                    tooltip = "Convenience button - you can also close the app itself instead. But remember - it's an \"aggregator\" app now - so there may be other tasks it's doing...",
                    action = function( button )
                        app:pcall{ name=button.title, async=true, guard=App.guardVocal, progress=true, main=function( call )
                            local s, m = ftpAgApp:quit()
                            call:setCaption( "Dialog box needs your attention.." )
                            if s then
                                app:show{ info="FTP Aggregator quit." }
                            else
                                app:show{ info="FTP Aggregator did not respond - perhaps it wasn't running.." }
                            end
                        end }
                    end,
				},
				vf:push_button {
                    title = 'Remote Sync',
                    props = props,
                    tooltip = "Perform complete synchronization - remote tree will be mirror image of local tree afterward. Note: extraneous remote files may be deleted, depending on your answer to a prompt.",
                    action = function( button )
                        app:service{ name=button.title, async=true, guard=App.guardVocal, main=function( call )
                            if not self.exportParams then -- this is often the case.
                                --Debug.pause( "no export params, yet" )
                                self.exportParams = self:_getExportParams( props )
                            end
                            local settings = {
                                server = self.exportParams.server,                                
                                username = self.exportParams.username,                                
                                password = nil, -- no password          
                                port = self.exportParams.port,                                
                                protocol = self.exportParams.protocol,                                
                                passive = self.exportParams.passive,                                
                                path = self.exportParams.path,                                
                            }
                                
                            --[[
                            app:log()
                            app:log( "Synchronizing '^1' to '^2' (server: '^3', base path: '^4')", syncPair.localDir, syncPair.remoteDir, settings.server, settings.path )
                            app:logV( "Username: ^1", settings.username )
                            if str:is( settings.password ) then
                                app:logW( "Password is present in plain text (unencrypted)." )
                            else
                                app:logV( "*** Password is encrypted." )
                            end
                            app:logV( "Protocol: ^1", settings.protocol )
                            app:logV( "Port: ^1", settings.port )
                            app:logV( "Passive: ^1", settings.passive )
                            app:logV()
                            local dispDur = app:getPref( 'dispDur' ) or 3
                            if dispDur > 0 then
                                app:showBezel( { dur=dispDur, holdoff=1 }, "FTP Sync from '^1' to '^2'", syncPair.localDir, syncPair.remoteDir )
                            else
                                app:logV( "Not displaying sync commencement in bezel." )
                            end
                            --]]
                                
                            local ok = Ftp.assurePassword( settings )
                            if not ok then -- usually means user canceled.
                                app:logW( "No password - skipping upload." )
                                return
                            end
                            if not str:is( settings.password ) then -- I don't think it's possible for this to happen, since query method assures non-blank, else user must cancel.
                                Debug.pause( "blank password?" ) -- if it does, I want to know.
                                app:logW( "'Password' is blank - skipping upload." )
                                return
                            end
                            
                            -- get-dest-dir will read cfg if need be
                            local localDir = self.exportParams.destPath -- self:getDestDir( self.exportParams, nil, nil ) -- no photo, no cache.
                            --local remoteSubpath = self:getRemoteSubpath( self.exportParams ) 
                            --settings.path = str:parentSepChild( settings.path, "/", remoteSubpath ) -- combine server-root & remote-subpath for ftp-agg-app sake.
                            local doPurge
                            local button = app:show{ info="Upload new and/or changed files from local to remote host, and (optionally) purge extraneous remote files?\n \n* Local dir: ^1\n* Remote dir: ^2",
                                subs = { localDir, settings.path },
                                buttons = { dia:btn( "Yes - full sync (purge too)", 'ok' ), dia:btn( "Yes - upload only (no purging)", 'other' ) },
                                actionPrefKey = "Remote sync confirmation",
                            }
                            if button == 'ok' then
                                doPurge = true
                            elseif button == 'other' then
                                doPurge = false
                            elseif button == 'cancel' then
                                call:cancel()
                                return
                            else
                                error( "bad button" )
                            end
                            
                            local s, m = ftpAgApp:xSyncDir( settings, localDir, doPurge, 10 )
                            if s then
                                app:log( "Dir to be sync'd by FTP Aggregator app: "..localDir )
                            else
                                app:logE( m )
                            end
                        end }
                    end,
                    enabled = bind'remPub',
				},
				
				vf:push_button {
                    title = 'Clear Jobs',
                    props = props,
                    tooltip = "Will delete all existing upload jobs and reset job number to '1'.",
                    action = function( button )
                        app:service{ name=button.title, async=true, guard=App.guardVocal, main=function( call )
                            self:clearFtpJobs( button.props )
                        end }
                    end,
                    enabled = bind'remPub',
				},
            }


    --   a d v a n c e d   o p t i o n s
    -- subsection header:
    section[#section + 1] = vf:spacer{ height = 5 }
    section[#section + 1] = vf:separator{ fill_horizontal=1 }
    section[#section + 1] =
        vf:static_text{
            title = "Advanced Options",
            fill_horizontal = .8,
            alignment = 'center'
        }
    section[#section + 1] = vf:spacer{ height=5 }
    
    -- subsection items:
    
    section[#section + 1] = 
	    vf:row {
	        vf:static_text {
	            title = "Plugin Manager Preset:",
	        },
	        --[[ *** before:
	        vf:popup_menu {
	            value = bind 'managedPreset',
	            items = app.prefMgr:getPresetNames(),
	            width_in_chars = 20,
	        },
	        --]]
	        -- after:
	        app.prefMgr:makePresetPopup {
	            props = props,
	            valueBindTo = props, -- export-params
	            valueKey = 'managedPreset',
	            callback = function( v )
	                self:initManagedPreset( props )
	            end,
	        },
	        vf:static_text {
	            title = str:fmtx( "Plugin manager preset is used by ^1\nfor advanced settings only, for example:\n* Define things that trigger republishing.\n* Specify Remote URL for showing photos in browser.", app:getAppName() )
	        },
	    }

    section[#section + 1] = 
	    vf:row {
	        vf:checkbox {
	            title = "Permit suppression of export/publish errors and/or warnings",
	            tooltip = "Useful in an an auto-publishing (or multi-publishing) context, to keep the wheel turning all the way to the end, regardless of potential issues.. - errors and/or warnings will still be available in log file.",
	            value = bind 'permitSuppressionOfErrorsAndWarnings',
	        },
        }
        
    -- plugin author only:
    
    if not app:isRelease() then
        section[#section + 1] = vf:spacer{ height=20 }
        section[#section + 1] = vf:static_text {
            title = "For plugin author's eyes only:",
        }
        section[#section + 1] = vf:separator{ fill_horizontal=1 }
        section[#section + 1] = vf:spacer{ height=5 }
        section[#section + 1] = 
            vf:row {
                vf:push_button {
                    title = "Push me",
                    props = props,
                    action = function( button )
                        app:call( Call:new{ name="Pushin' it...", async=true, main=function( call )
                            local photo = catalog:getTargetPhoto()
                            local colls = photo:getContainedPublishedCollections() -- normal collections only - not smart!
                            local pubSrv = colls[1]:getService()
                            local settings = pubSrv:getPublishSettings()['< contents >']
                            Debug.lognpp( settings )
                        end, finale=function( call )
                            Debug.showLogFile()
                        end } )
                    end,
                }
        }
    end

    return { section }

end





--   E X P O R T   M E T H O D S



--[[
        Called when we have a photo from the catalog and we need its dest counterpart.
        Special handling required to deal with virtual copies,
        because the same source path applies to more than one target.

        *** Must be called with catalog access.
--]]
function TreeSyncPublish:getDestPhotoPath( renditionOrPhoto, sourceSubfolderPath, sourceFileName, cache )

    local _destFileName
    local destFileName
    
    local photo
    local rendition
    if renditionOrPhoto.getRawMetadata then -- Lr3-compatible way of checking whether this is an lr-photo.
        photo = renditionOrPhoto
    else
        rendition = renditionOrPhoto
        photo = rendition.photo
    end

    assert( photo ~= nil, "no photo" )
    assert( self.exportParams ~= nil, "no props" )
    
    if self.exportParams.LR_renamingTokensOn then -- rename via preset/template.
        _destFileName = self:getDestFilename( self.exportParams, photo, cache )
        --Debug.pause( destFileName )
    else -- permit default naming
        local destExtension = self:getDestExt( self.exportParams, photo, cache )
        if self.exportParams.cardCompat then
            assert( self.cardFileNum ~= nil, "where's da num" )
            if destExtension:len() > 3 then
                error( "ext overflow" )
            end
            if rendition ~= nil then
                if rendition.publishedPhotoId ~= nil then -- previously published
                    destFileName = LrPathUtils.leafName( LrPathUtils.removeExtension( rendition.publishedPhotoId ) ) -- accept previously published name
                    -- local destFolderPath = LrPathUtils.child( self.exportParams.destPath, sourceSubfolderPath ) - commented out 20/Aug/2012 17:21
                	-- local destFilePath = LrPathUtils.child( destFolderPath, destFileName ) - ditto
                    -- local destFilePath = Common.getDestPathFromPublishedId( rendition.publishedPhotoId ) -- @20/Aug/2012 17:21, using this instead. Howeber, @18/Feb/2014 3:37 this will fail without settings, so maybe this was a bug.
                    local destFilePath = Common.getDestPathFromPublishedId( rendition.publishedPhotoId, self.exportParams ) -- this @18/Feb/2014 3:37.
                    if fso:existsAsFile( destFilePath ) then
                        Debug.logn( "Got destfilename from previously pub'd ID" )
                    else
                        Debug.logn( "Destfilename based on previous pub ID is bogus - going for a new one..." )
                        destFileName = nil
                    end
                else
                    Debug.logn( "No previously pub'd ID" )
                end
            else
                Debug.logn( "No rend" )
            end
            if destFileName == nil then
                self.cardFileNum = self.cardFileNum + 1
                destFileName = string.format( "%08u.%s", self.cardFileNum, destExtension )
                Debug.logn( "Got new filename for card compat", destFileName )
            --else
            end
            
        else -- forget legacy card compatibility - name as desired.
            _destFileName = Common.getSourceBasedFileName( sourceFileName, destExtension )
        end        
    end

    if destFileName == nil then
        if self.exportParams.smartCopyName then
            destFileName = Common.insertVirtualCopyName( _destFileName, self.exportParams, photo, cache ) -- but only if photo is virtual copy.
        else
            destFileName = _destFileName
        end
    end
    
    local destFolderPath
    if self.exportParams.destTreeType == 'flat' then
        if str:is( self.exportParams.destPathSuffix ) then
            destFolderPath = LrPathUtils.child( self.exportParams.destPath, self.exportParams.destPathSuffix )
        else
            destFolderPath = self.exportParams.destPath    
        end
    else
        destFolderPath = LrPathUtils.child( self.exportParams.destPath, sourceSubfolderPath )
    end
	local destFilePath = LrPathUtils.child( destFolderPath, destFileName )
	
    return destFilePath, destFileName
end



function TreeSyncPublish:maintRun( markAsPublished )
    local serviceName
    if markAsPublished then
        serviceName = "Mark as Published"
    else
        serviceName = "Maintenance Run"
    end
    app:service{ name=serviceName, async=true, progress={ modal=true }, guard=App.guardVocal, main=function( call )
        self.call = call
        local pubSrvs = PublishServices:new()
        --pubSrvs:init( call ) -- I'm not sure if other plugin-info is needed, but better safe than sorry.. ###4 'til 15/Sep/2014 16:21 - all pub srvs. remove this line/reminder if no problems by 2016.
        pubSrvs:init( call, _PLUGIN.id ) -- theoretically, this feature should not care a hoot what info there is or is not for other publish services, I mean it could be that
            -- it would make a differences as to logged info (e.g. "not published at all" vs. "not published on this service"), so check it, but I want it to be faster, and therefore limited to TSP services.
        local pubSrv
        local photos = cat:getSelectedPhotos() -- selected photos
        if #photos == 0 then
            app:show{ warning="Select photo(s) first." }
            call:cancel()
            return
        end
        local pubCollSet = {} -- selected publish collections
        local pubColls = {} -- ditto, as array
        --[[
            self.pubPhotoLookup = {} -- for each pubPhoto index, a table with srvInfo and pubColl.
            self.photoLookup = {} -- for each photo (not pub-photo), a table containing array of published photos (pubPhotos), a set of publish services info (pubSrvInfo), and a set of published collections (pubCollSet).
            self.pubCollLookup = {} -- for each published collection index, associated publish service info (un-named, but in srvInfo format).
            self.pubSrvLookup = {} -- for each publish service index, a table of service info (un-named, but in srvInfo format).
            self.pluginLookup = {} -- for each plugin id implementing publish services, a table containing pluginId, and an array of service info (in srvInfo format).
        --]]        
        --  srvInfo format: srv, pluginId, pubColls, pubPhoto
        -- { srv=srv, pluginId=pluginId, pubColls={}, pubPhotos={} }

        call:setCaption( "Dialog box needs your attention..." ) -- may or may not prove true.
        
        for i, v in ipairs( catalog:getActiveSources() ) do
            local vType = cat:getSourceType( v )
            if vType == 'LrPublishedCollection' then
                local vSrv = v:getService()
                if pubSrv == nil then
                    pubSrv = vSrv
                elseif pubSrv ~= vSrv then -- different publish service.
                    app:show{ warning="Confine selected publish collection(s) to a single publish service, then try again." }
                    call:cancel()
                    return
                end
                assert( pubCollSet[v] == nil, "dup pub coll" )
                pubCollSet[v] = true
                pubColls[#pubColls + 1] = v
            end
        end
        if tab:isEmpty( pubCollSet ) then
            app:show{ warning="Select one or more publish collections, then try again." }
            call:cancel()
            return
        else
            assert( pubSrv, "no pub srv" )
        end
        assert( tab:countItems( pubCollSet ) == #pubColls, "dup pub coll(s) - hmm..." )

        local exportParams = pubSrv:getPublishSettings()['< contents >']
        assert( exportParams, "no export params" )
        self.exportParams = exportParams -- required for called function(s).
        self:initManagedPreset()
        
        call:setCaption( "Dialog box needs your attention..." )
        local ok = dia:isOk( "Proceed to do '^1' to ^2 in ^3? (publish service: '^4', ineligible items will be ignored)", call.name, str:plural( #photos, "selected item", true ), str:nItems( #pubColls, "publish collections" ), pubSrv:getName() )
        if ok then
            call:setCaption( "Acquiring additional metadata (time required: unknown)" )
        else
            call:cancel()
            return
        end
        
        local cache = lrMeta:createCache{}
        local rawMeta = cache:addRawMetadata( photos, { 'uuid', 'path', 'isVirtualCopy' } )
        local fmtMeta = cache:addFormattedMetadata( photos, { 'copyName' } )
        call:setCaption( "Doing ^1...", call.name )
        local todo = {}
        local getRemoteUrl = self.preset:getPref( 'getRemoteUrl' ) -- assign to self, in initManagedPreset? ###2
        if getRemoteUrl ~= nil then
            if type( getRemoteUrl ) == 'function' then
                app:logV( "Using getRemoteUrl function from managed preset." )
            else
                app:logW( "getRemoteUrl from managed preset is not a function (it should be)." )
                getRemoteUrl = nil
            end                
        end
        if getRemoteUrl == nil then
            getRemoteUrl = function()
                return nil, "No function for getting remote URL in advanced settings."
            end
            app:logV( "Using default getRemoteUrl function - consider configuring using advanced settings - preset manager section of plugin manager." )
        end
        
        for i, photo in ipairs( photos ) do
            repeat
                local photoName = cat:getPhotoNameDisp( photo, true, cache )
                app:log( "Considering photo: ^1", photoName )
                local pubCollsToDo = {}
                --  @return table with pubPhotos, pubSrvSet, pubCollSet
                local photoInfo = pubSrvs:getInfoForPhoto( photo ) -- pub-info, implied.
                if photoInfo and tab:is( photoInfo.pubPhotos ) then
                    local pubPhotoSet = {}
                    local pubPhotosToDo = {}
                    local pubSrvSettings = {}
                    for pubColl, v in pairs( photoInfo.pubCollSet ) do
                        if pubCollSet[pubColl] then -- this published collection that photo is in, is one that's selected.
                            pubCollsToDo[#pubCollsToDo + 1] = pubColl
                            if not markAsPublished then -- we need eligible published photos only.
                                for i, pubPhoto in ipairs( photoInfo.pubPhotos ) do
                                    --  @return table with srvInfo & pubColl.
                                    local pubPhotoInfo = pubSrvs:getInfoForPubPhoto( pubPhoto )
                                    if pubPhotoInfo.pubColl == pubColl then
                                        Debug.pause( "is subject", pubColl:getName() )
                                        if pubPhotoSet[pubPhoto] then
                                            Debug.pause( "Published photo is in more than one collection in the service." )
                                            local srv = pubColl:getService()
                                            local prm = pubSrvSettings[srv]
                                            if prm == nil then
                                                prm = srv:getPublishSettings()['< contents >']
                                                assert( prm, "no prm" )
                                                pubSrvSettings[srv] = prm
                                            end
                                            Debug.pause( prm.photosToo )
                                            if prm.photosToo then
                                                -- no longer a warning in this case, since one of the reasons the mirroring is now duplicating the collection hierarchy is
                                                -- to support the same photos in different collections.
                                                app:logV( "*** Published photo is in more than one collection in the service - not illegal, but so ya know.." )
                                            else
                                                app:logW( "Published photo is in more than one collection in the service - not illegal, but seems unorthodox to me (and is maybe a mistake..)." )
                                            end
                                        else
                                            pubPhotoSet[pubPhoto] = true
                                            pubPhotosToDo[#pubPhotosToDo + 1] = pubPhoto
                                        end
                                    else
                                        Debug.pause( "not subject", pubColl:getName(), pubPhotoInfo.pubColl:getName() )
                                    end
                                end
                                Debug.pauseIf( #pubPhotosToDo == 0 )
                            -- else X
                            end
                        else
                            Debug.pause( "not sel", pubColl:getName() )
                        end
                    end
                    if tab:isEmpty( pubCollsToDo ) then
                        -- none of the photo's published collections are selected ###2 (stat).
                        break
                    end
                elseif markAsPublished then
                    for i, src in ipairs( catalog:getActiveSources() ) do
                        local srcName = cat:getSourceName( src )
                        local srcType = cat:getSourceType( src )
                        if srcType == 'LrPublishedCollection' then
                            local srv = src:getService()
                            if srv:getPluginId() == _PLUGIN.id then
                                pubCollsToDo[#pubCollsToDo + 1] = src
                            else
                                app:logV( "*** mark as publish with foreign publish collection selected?" ) 
                            end
                        else
                            app:logV( "*** mark as publish with non-publish collection selected?" ) 
                        end
                    end
                else -- no photo info (photo not published), and not marking as published, so no can do nuthin with this photo.
                    -- stat ###2
                    break -- photo is not published
                end
            
                local photoPath = rawMeta[photo].path
                local uuid = rawMeta[photo].uuid
                local sourceFilePath = photoPath
            	local sourceFilename = LrPathUtils.leafName( sourceFilePath ) -- photo:getFormattedMetadata( 'fileName' ) -- not necessarily same extension as rendered filename.
    
            	local sourceFolderPath = LrPathUtils.parent( photoPath )
            	local sourceSubfolderPath
            	if sourceFolderPath ~= nil then
                    sourceSubfolderPath = Common.getSubPath( exportParams.sourcePath, sourceFolderPath, exportParams.destPathSuffix, photo, exportParams ) -- note: this does the right thing even if dest-tree-type is coll.
                    if sourceSubfolderPath == nil then
                        app:logW( "^1 is not in specified source path (^2) and can not be exported - either remove from collection or edit 'Source Path' setting to include it.", sourceFolderPath, exportParams.sourcePath )
                        return
                    else
                        Debug.pause( sourceSubfolderPath, sourceFolderPath, exportParams.destTreeType )
                    end
                else
                    app:logE( "No parent path for source: ^1", sourceFilePath )
                    return
                end
              	local destFilePath, destFileName = self:getDestPhotoPath( photo, sourceSubfolderPath, sourceFilename, cache ) -- nil rendition means nil return if lr-renaming tokens are on.
              	if destFilePath == nil then -- error already logged.
              	    break
              	elseif uuid then -- this clause added 6/Mar/2014 15:19, since it seems the reverse lookup piece was missing if things changed
                    local key = str:pathToPropForPluginKey( destFilePath )
                    --Debug.pause( key, uuid )
                    cat:setPropertyForPlugin( key, uuid ) -- Save mapping entry from destination file to source photo. Throws error if trouble.
                else
                    app:logE( "No uuid.")
                    break
              	end
                local photoId = LrPathUtils.addExtension( destFilePath, uuid )
                local photoUrl, errm = getRemoteUrl { -- "file://" .. destFilePath
                    photo = photo,
                    photoId = photoId,
                    settings = exportParams,
                }
                -- Note: url is optional, but recommended when ftp-upload'ing.
                    -- aids in configuration based on presence of dest files in main subdir.
                if markAsPublished then
                    for i, pubColl in ipairs( pubCollsToDo ) do
                        todo[#todo + 1] = function() -- note: add-photo will simply update photo (id+url) if photo already exists and is published.
                            pubColl:addPhotoByRemoteId( photo, photoId, photoUrl, true ) -- published
                            if photoUrl ~= nil then
                                app:log( "Marked dest path (^1) as published, ID: '^2', URL: '^3'", destFilePath, photoId, photoUrl )
                            else
                                app:log( "Marked dest path (^1) as published, ID: '^2', No URL", destFilePath, photoId )
                            end
                        end
                    end
                else
                    for i, pubPhoto in ipairs( pubPhotosToDo ) do
                        todo[#todo + 1] = function()
                            pubPhoto:setRemoteId( photoId )
                            if str:is( photoUrl ) then
                                pubPhoto:setRemoteUrl( photoUrl )
                                app:log( "Published dest path (^1) ID set to: '^2', URL: '^3'", destFilePath, photoId, photoUrl )
                            else
                                app:log( "Published dest path (^1) ID set to: '^2' - No URL.", destFilePath, photoId )
                            end
                        end
                    end
                end
                if self.call:isQuit() then
                    return
                else
                    self.call:setPortionComplete( i, #photos )
                end
            until true -- process one photo.
        end -- for photos
        if #todo > 0 then
            self.call:setCaption( "Updating catalog..." )
            local s, m = cat:update( 50, serviceName, function( context, phase )
                local i1 = ( phase - 1 ) * 1000 + 1
                local i2 = math.min( phase * 1000, #todo )
                app:logV( "Updating photos from ^1 to ^2", i1, i2 )
                for i = i1, i2 do
                    local func = todo[i]
                    func()
                    if self.call:isQuit() then
                        app:error( "Aborted catalog update - no changed should have been made to your catalog." )
                    else
                        self.call:setPortionComplete( i, #todo )
                        if i == #todo then
                            self.call:setCaption( "Finalizing..." )
                        end
                    end
                end
                if i2 < #todo then
                    return false
                end
            end )
            if s then
                app:log( "Info for selected photos successfully updated in Lightroom catalog." )
            else
                app:logE( m or "no error message provided" )
            end
        else
            app:logW( "nuthin to do" )
        end
        
    end }
end



--[[
        Called immediately after creating the export object which assigns
        function-context and export-context member variables.
        
        This is the one to override if you want to change everything about
        the rendering process (preserving nothing from the base export class).
--]]        
function TreeSyncPublish:processRenderedPhotosMethod()

    assert( self.exportParams ~= nil, "no export params" )
    local exportSettings = self.exportParams -- convenience var.
    assert( self.exportParams.uploadImmed ~= nil, "no sync param" )
    local srvName = self.exportParams.LR_publish_connectionName -- non-nil if publishing not exporting.
    -- do I even need aux-settings?  I mean, if we're assuring order and uploading too, then uploading should be deferred, period, right? ###2 (probably more complicated than need be, but I *think* the logic is correct).
    if str:is( srvName ) and auxSettings[srvName] then
        self.deferUploading = auxSettings[srvName].deferUploading
    else
        self.deferUploading = false
    end
    if exportSettings.assureOrder then -- we will be ordering
        self.deferUploading = exportSettings.remPub -- not sure it matters if not rem-pub, but hey..
    end
    if self.deferUploading then
        if exportSettings.remPub then
            app:logV( "Processing rendered photos - uploading is deferred." )
        end
    else
        if exportSettings.remPub then
            app:logV( "Processing rendered photos - uploading promptly (not deferred)." )
        end
    end
    
    self.srcSet = {}
    self.srcOrder = {} -- default so nothing croaks.
    
    if exportSettings.assureOrder then -- and exportSettings.destTreeType == 'coll' then
        local x = fprops:getPropertyForPlugin( 'com.robcole.TreeSyncOrderer', nil, true ) -- no-name => return all, force re-read.
        if tab:is( x ) then
            app:logV( "Sort order info obtained from TSO - dunno how fresh.." )
            self.srcOrder = x
            --Debug.lognpp( self.srcOrder )
            if exportSettings.orderVia == 'captureTime' then
                local us, eh = exifTool:isUsable()
                if us then
                    app:logV( "Exiftool seems usable." )
                else
                    app:logW( "Exiftool (required for ordering by capture time) is not usable - ^1.", eh )
                    self:cancelExport()
                    return
                end
            -- else more will be logged when the info is used.
            end
        else
            app:logW( "Run 'TreeSync Orderer' or disable (uncheck) 'Sort Order Via'" )
            self:cancelExport()
            return
        end
    end
    
    if self.exportParams.remPub then

        local s, m = FtpPublish.newFtpJob( self )
        if s then
            app:log( "FTP Service initialized for new job." )
            if self.exportParams.uploadImmed then
                local s, m = ftpAgApp:assureRunning( self.exportParams.ftpAggApp )
                if s then
                    app:log( "FTP Aggregator app is running." )
                else
                    app:logW( "FTP Aggregator app may not be running (or in any case, does not seem healthy) - you may have to stop it and/or restart it yourself. Additional info:\n^1", m or "none - sorry." )
                end
            -- else
            end
            
            Publish.processRenderedPhotosMethod( self ) -- ditto
            
        else
            app:logE( m ) -- not already logged
            self.call:abort( "Can't initialize ftp service." )
            return
        end
    else
        Publish.processRenderedPhotosMethod( self )
    end
    
    -- note: it's a problem for auto-publish that ordering won't get updated unless there is at least one "seed" photo being actually published ###1.
    LrTasks.yield()
    if exportSettings.assureOrder then -- we should be ordering
        -- ###1 check whether ordering is being done as part of (internal to) publishing, or external to - in auto-publishing context.
        self:orderColls() -- let orderer log problems with ordering info to be used..
    else
        app:log( "Not ordering exported files." )
    end
    
end



--- Function to go through and order photos - does NOT compute order info. ###1
--  Dunno if this works - I mean process-rendered photos works because an export object
--  is created for exporting, with a list of photos, but if no such initiation, how to know?
--  I guess a commmon function which does all..?
--[[
function TreeSyncPublish:orderPhotos()
    

end
--]]



-- this entire thing is driven by src-set (and src-order).
-- src-set: indexed by source folder or collection (depending on mirrored type) - value is table containing destination (exported) folder path, and file table (index is source photo, value is exported file path).
--   created by exported files, so no exported file no corresponding entries..
-- src-order: contents of tso properties file.
-- note: it might be better to establish relative order of files in source folders/collections, then only change date/time if relative order has changed. ###1
-- I think I'm gonna change the recommendation though - if user only selects published photos in mirrored sources the ordinals will always match up. hmm.. ###1
function TreeSyncPublish:orderColls()
    app:pcall{ name="Order exported files", async=false, function( call )
        assert( self.srcSet, "no src set" ) -- computed by TSP export.
        assert( self.srcOrder, "no src order" ) -- computed by TSO export.
        local pending = {}
        if self.exportParams.remPub then
            Debug.pauseIf( not self.deferUploading, "not deferring uploading, but probably should be" )
            local jobDir, eh = self:getJobDir() or error( "no job dir" )
            if fso:existsAsDir( jobDir ) then
                for file in LrFileUtils.files( jobDir ) do
                    if file:find( "upload_file" ) then -- filename: "DDD upload_file.txt".
                        local path, errm = fso:readFile( file ) -- contents of file is path of file to be uploaded.
                        if str:is( path ) and fso:existsAsFile( path ) then -- double-check legal file
                            pending[path] = file
                            app:logV( "Pending for upload as part of job ^1: ^2", self.jobNum, path )
                        elseif str:is( errm ) then
                            app:logV( "*** ^1", errm ) -- means can't be sure - may have been locked for read by upload app - just schedule for re-uploading: worst case - uploaded redundently.
                        else
                            Debug.pause( "?" )
                        end
                    end
                end
            elseif eh then
                app:logV( "No upload job dir, so no uploads pending - ^1.", eh )
            else
                app:logV( "No upload job dir, so no uploads pending." )
            end
        -- else no need..
        end
        --[[ obsolete: files will be deferred, so won't be pending (actually, they could be pending from another run, hmm...) ###1
        local function isPending( file )
            local jobFile = pending[modFile]
            if jobFile and fso:existsAsFile( jobFile ) then -- was pending, and still is pending
                --app:logV( "ordered file already pending upload." )
                return true
            else
                return false
            end
        end
        --]]
        if self.exportParams.orderVia == 'captureTime' then
            app:log( "Ordering via capture time." )
            self.ets = exifTool:openSession( app:getAppName().."-OrderByCaptureTime-"..LrUUID.generateUUID() ) -- make sure each session is unique - session should be closed upon finale..
            -- otherwise publishing can not be concurrent (I mean nix concurrent anyway, but just in case - better safe..).
        else
            app:log( "Ordering via file-created date." )
        end
        app:assert( self.deferUploading ~= nil, "deferred uploading uninit (nil)" )
        for src, ent in pairs( self.srcSet ) do -- go through collections containing at least some of the exported photos.
            repeat
                app:log()
                --local srcType = cat:getSourceType( src )
                local srcType = ent.srcType or error( "no src-type" )
                local srcId = src -- src.localIdentifier or src:getPath() or error( "?" )
                local srcName = LrPathUtils.leafName( src ) or src -- maybe cheating a little (using disk function for coll paths).     src:getName() -- folder or collection.
                local orderSet = fprops:getPropertyForPlugin( 'com.robcole.TreeSyncOrderer', { srcType, srcId } ) -- why not get from src-order? ###1
                if tab:is( orderSet ) then
                    app:logV( "Got ordering info for '^1' (^2) - ^3", srcName, srcId, srcType )
                else
                    -- Debug.pause( srcId, srcType ) - warning should suffice..
                    app:logV( "There is no sort-ordering information for collection '^1' - Type: ^2, ID: ^3", srcName, srcType, srcId )
                    app:logW( "There is no sort-ordering information for collection '^1'. It seems you need to re-run 'TreeSync Orderer', then re-do the export via 'TreeSync Publisher'.. - exported photos are probably not ordered correctly, yet.", srcName )
                    break
                end
                local folder = ent.folder
                app:log( "Ordering files in exported folder '^1' based on info created by 'TreeSync Orderer' for '^2' - hope it's current.", folder, srcName )
                 -- problem: if no exports into said folder, it won't be on the list
                local files = ent.files -- ###1: write-only: table - keys are UUID, values are paths.
                --Debug.pause( files, tab:countItems( files ) )
                local baseTime = LrDate.timeFromComponents( 2000, 1, 1, 0, 0, 0 ) -- note: windows app won't permit year 3000, or 1000. default tz
                local ord
                for file in LrFileUtils.files( folder ) do
                    app:log()
                    app:log( "Considering order of '^1'", file )
                    local key = str:pathToPropForPluginKey( file )
                    local id = cat:getPropertyForPlugin( key ) -- Save mapping entry from destination file to source photo. Throws error if trouble.
                    if id then
                        ord = orderSet[id]
                        if ord then -- value assigned when running TSO
                            app:log( "Order position number: ^1", ord ) -- setting to.
                            local orderTime = baseTime + ( ord * 60 ) -- one photo per minute based on ord.
                            local modFile -- file, if modified.
                            -- note: I need to either defer uploading or deal with the fact that uploader may have file open for uploading, and so modification
                            -- may error out. ###1 - it may be safest just to defer, although I hate it, since overlapped exporting and uploading is a feature.
                            -- note exported files seem not to have capture time, but that's when exporting using preview exporter in turbo mode, normally I think
                            -- they will have it.
                            if self.exportParams.orderVia == 'createdTime' then
                                -- other option is "modified-time".
                                local creTime = fso:getFileCreationDate( file ) or 0
                                local match = ( creTime == orderTime )
                                if not match then
                                    match = num:isWithin( creTime, orderTime, 5 ) -- so far has been exact match (Windows), but not sure if it always will be, e.g. Mac.
                                    if match then
                                        app:logV( "*** File created time not matching order time exactly, but close enough - diff: ^1", date:formatTimeDiffMsec( creTime - orderTime ) )
                                    else
                                        app:logV( "File created time significantly changed (presumably order changed), diff: ^1", date:formatTimeDiffMsec( creTime - orderTime ) )
                                    end
                                else
                                    app:logV( "File created time matched order time exactly." )
                                end
                                if not match then
                                    local s, m, c = app:changeFileDates { -- reminder, if created time is same as before, this is a no-op. If change required, modification time will be "now".
                                        file = file,
                                        createdTime = orderTime,
                                        -- preserve-previous-modification-time equals false.
                                    }
                                    if str:is( c ) then -- response content
                                        app:logV( c )
                                    end
                                    if s then -- status indicates it worked.
                                        modFile = file -- note: it wasn't called upon unless it needed to be cnanged, so if it worked, it's changed, regardless of 'm'.
                                        if str:is( m ) then -- maybe just qualification (already set or needed to be set).
                                            app:logV( m )
                                        else
                                            app:logV( "Ordinal set to: ^1", ord ) -- set to.
                                        end
                                    else
                                        app:logE( m or "bad status but no error message - hmm..." )
                                    end
                                else
                                    app:log( "Created time was already set as specified, or very close to it.." )
                                end
                            elseif self.exportParams.orderVia == 'captureTime' then
                                -- reminder: photo capture time has no bearing on exported capture time
                                local capTime
                                self.ets:addArg( "-S" ) -- no quotes required in session mode, since eol is delimiter.
                                self.ets:addArg( "-DateTimeOriginal" ) -- no quotes required in session mode, since eol is delimiter.
                                self.ets:setTarget( file )
                                local rslt, errm = self.ets:execute()
                                if str:is( rslt ) then -- exiftool responded.
                                    local stampFmtd = exifTool:getValueFromPairS( rslt ) -- note: returns string, maybe empty.
                                    local timeNumStruct, m = exifTool:parseDateTime( stampFmtd ) -- misnomer - elements are string.
                                    if timeNumStruct then
                                        capTime = LrDate.timeFromComponents( num:to( timeNumStruct.year ), num:to( timeNumStruct.month ), num:to( timeNumStruct.day ),
                                            num:to( timeNumStruct.hour ), num:to( timeNumStruct.minute ), num:to( timeNumStruct.second ) )
                                    else
                                        app:log( "*** Unable to obtain capture time via exif-tool - assuming it is incorrectly formatted - ^1.", m )
                                    end
                                elseif str:is( errm ) then
                                    app:logW( "*** Unable to obtain capture time via exif-tool - ^1.", errm )
                                else
                                    app:log( "Unable to obtain capture time via exif-tool - assuming it has not yet been assigned (not unusual for freshly exported files) - no error occurred." )
                                end
                                -- idea is to leave capture time alone if already set, so file not modified, not re-uploaded.., if ordering cap-time already ok.
                                local match
                                if capTime ~= nil then
                                    app:logV( "Previous capture time: ^1", exifTool:formatDateTime( capTime ) )
                                    match = ( capTime == orderTime ) -- so far has always been exact match.
                                    if not match then
                                        match = num:isWithin( capTime, orderTime, 5 )
                                        if match then
                                            app:logV( "*** Capture time not matching order time exactly, but close enough - diff: ^1", date:formatTimeDiffMsec( capTime - orderTime ) )
                                        else
                                            app:logV( "Capture time significantly changed (presumably order changed), diff: ^1", date:formatTimeDiffMsec( capTime - orderTime ) )
                                        end
                                    else
                                        app:logV( "Capture time not matched order time exactly." )
                                    end
                                -- else message logged above.
                                end
                                if not match then
                                    local tf = exifTool:formatDateTime( orderTime ) -- same as my favorite actually: YYYY-MM-DD HH:MM:SS
                                    self.ets:addArg( "-overwrite_original" )
                                    self.ets:addArg( "-DateTimeOriginal="..tf ) -- no quotes required in session mode, since eol is delimiter.
                                    self.ets:setTarget( file )
                                    -- local modTime = fso:getFileModificationDate( file ) - bad idea: we want modified stamp to be set, so file will be seen as changed and re-uploaded to reflect re-ordering.
                                    local rslt, errm = self.ets:execute()
                                    if str:is( rslt ) then -- exiftool responded.
                                        local s, m = exifTool:getUpdateStatus( rslt )
                                        if s then
                                            app:log( "Capture time updated via exif-tool for ordering purposes: ^1", tf )
                                            modFile = file
                                        else
                                            app:logW( "Unable to update capture time via exif-tool - ordering may not be correct - ^1.", m )
                                        end
                                    else
                                        app:logW( "Unable to update capture time via exif-tool - ordering may not be correct - ^1.", errm or "no error message" )
                                    end
                                else
                                    app:log( "Capture time already matches what would be set - no re-ordering ala capture time required." )
                                end
                                if modFile then
                                    if self.exportParams.remPub then
                                        -- note: it's not quite optimal: files are scheduled for upload when rendered, and again when sorted.
                                        -- the problem being I have no good way to know whether they've already been started, and they may
                                        -- need to be uploaded again, or they may not, depending on ordering. So it seems I need to either
                                        -- figure out a way to tell where they're at in the pipeline, defer all until post-export, or upload
                                        -- twice in some cases, which is how it is now ###1. I suppose it would be possible to go through the
                                        -- messages, but since they are supposed to be for recipient only after sending it makes me leary, i.e.
                                        -- there could be some interference or errors.. I suppose a simple way would be to store the message filename
                                        -- for file, then check if said filename still in message dir - that way I'd not have to open any files. hmm..
                                        local jobFile = pending[modFile]
                                        if jobFile and fso:existsAsFile( jobFile ) then -- was pending, and still is pending
                                            app:logV( "ordered file already pending upload." )
                                        else
                                            local s, m = self:uploadFile( modFile ) -- *** record, but defer..
                                            if s then
                                                app:logV( "sorted file scheduled for upload by FTP app: ^1", modFile )
                                            else
                                                Debug.pauseIf( not m, s )
                                                app:logE( m or "not sure why.." )
                                            end
                                        end
                                    end
                                -- else presumably enough already logged.
                                end
                            else
                                app:error( "Invalid order-via export param value" )
                            end
                        else -- ID but no ord
                            app:logW( "It seems a photo has been added since 'TreeSync Orderer' has been run, or something - consider running it again, then redo the export via 'TreeSync Publisher'.. - exported photos are probably not ordered correctly, yet." )
                        end
                    else -- no ID.
                        Debug.pause( "no ID for file", file, "key", key )
                        app:logW( "no ID for ^1", file )
                        break
                    end
                end
            until true
        end
        self:uploadFiles() -- upload "deferred" files, and end the job.
    end, finale=function( call )
        exifTool:closeSession( self.ets )
    end }
end



--[[
        Remove photos not to be rendered, or whatever.
        
        Default behavior is to do nothing except assume
        all exported photos will be rendered. Override
        for something different...
--]]
function TreeSyncPublish:checkBeforeRendering()
    -- FtpPublish.checkBeforeRendering( self ) - just blindly assigns n-photos-to-render from n-photos-to-export
    app:call( Call:new{ name="Check before rendering", async=false, guard=nil, main=function( call )
        assert( self.srvc ~= nil, "No service" )
        self.nPhotosToRender = self.nPhotosToExport
        self.srvc.nCopied = 0
        self.srvc.nXmpCopied = 0
        self.srvc.nNewFilesCreated = 0
    	self.srvc.nExistingFilesUpdated = 0
    	self.srvc.nBuriedIgnored = 0
    	
	    app:log()
	    app:log( "*****************   E X P O R T   /   P U B L I S H   *******************" )
	    app:log( "*************************************************************************" )
	    app:log()
	    
    	local cnt = 0

    	self.photosToExport = {}
        for _photo in self.exportSession:photosToExport() do -- session supports iterator, not array.
            self.photosToExport[#self.photosToExport + 1] = _photo
        end
    	self.cache = lrMeta:createCache{}
    	self.rawMeta = self.cache:addRawMetadata( self.photosToExport, { 'path', 'uuid', 'fileFormat', 'isVirtualCopy', 'isInStackInFolder', 'stackPositionInFolder', 'stackInFolderIsCollapsed' } )
    	self.fmtMeta = self.cache:addFormattedMetadata( self.photosToExport, { 'copyName' } )
        if self.exportParams.ignoreBuried then
            app:logInfo( "Ignoring photos buried in stack in folder of origin" )
        else
            app:logInfo( "Photos are being exported regardless of stack position in folder of origin." )
        end
        if self.exportParams.LR_renamingTokensOn then
            app:logV( "Renaming template is being employed - will attempt to pre-check destination names." )
        else
            app:logV( "Destination names will be pre-checked - default naming is being employed." )
        end
        if self.exportParams.LR_format == 'ORIGINAL' then
            if self.exportParams.inclRaws then
                if self.exportParams.inclRawsIfSensible then
                    app:log( "Original raws are being exported if newer or not pre-existing." )
                else
                    app:log( "Original raws are being exported unconditionally." )
                end
            end
            if self.exportParams.inclXmp then
                if self.exportParams.inclXmpIfChanged then
                    app:log( "Xmp sidecars are being included if significantly changed." )
                else
                    app:log( "Xmp sidecars are being included unconditionally." )
                end
            end
        -- else format is already logged.
        end
    	local pubColl
    	local pubPhotos
        local pubIds
        if self.exportContext.publishService then
        	pubColl = self.exportContext.publishedCollection
        	pubPhotos = pubColl:getPublishedPhotos()
            pubIds = {}
        end
        assert( self.preset ~= nil, "no cfg" )
        
        self.getRemoteUrl = self.preset:getPref( 'getRemoteUrl' )
        if self.getRemoteUrl ~= nil then
            if type( self.getRemoteUrl ) == 'function' then
                app:logV( "Using getRemoteUrl function from managed preset." )
            else
                app:logW( "getRemoteUrl from managed preset is not a function (it should be)." )
                self.getRemoteUrl = nil
            end                
        end
        if self.getRemoteUrl == nil then
            self.getRemoteUrl = function()
                return nil, "No function for getting remote URL in advanced settings."
            end
            app:logV( "Using default getRemoteUrl function - consider configuring using advanced settings - preset manager section of plugin manager." )
        end
        for i, _photo in ipairs( self.photosToExport ) do
            local removed = false
            local photoPath = self.rawMeta[_photo].path
            local photoName = cat:getPhotoNameDisp( _photo, true, self.cache )
            app:log( "Considering export of ^1", photoName )
            if self.exportParams.ignoreBuried then
                if cat:isBuriedInStack( _photo, self.rawMeta ) then
                    self.srvc.nBuriedIgnored = self.srvc.nBuriedIgnored + 1 -- present ###2
                    app:log( "Photo buried in stack - ignored." )
                    self.exportSession:removePhoto( _photo )
                    removed = true
                end
            end
            local fmt = self.cache:getRawMetadata( _photo, 'fileFormat' )
            if fmt == 'VIDEO' then -- make sure video are allowed, to avoid a harsher Lr error.
                if self.exportParams.LR_export_videoFileHandling == "exclude" then
                    app:logW( "Unable to export video - videos are not being included: check 'Video' settings in publishing manager, or export settings." )
                    self.exportSession:removePhoto( _photo )
                    removed = true
                end
            end
            if self.exportParams.LR_format == 'ORIGINAL' then
                if self.rawMeta[_photo].isVirtualCopy then
                    -- could have a stat for this, but it seems hardly worth the effort.
                    app:log( "Virtual copy being excluded from original format export." )
                    self.exportSession:removePhoto( _photo )
                    removed = true
                end
            -- else -- not buried, not original format.
            end
            local sourceFileMissing, smartPreviewQual = cat:isMissing( _photo, self.cache )
            if not sourceFileMissing then
                -- app:logV( "Source file exists." )
            elseif smartPreviewQual then
                app:logV( "Source file is missing, but smart-preview exists - photo will be subject to exporting, as far as TSP is concerned." )
            else
                app:logW( "Source file does not exist, nor smart preview (^1) - photo or video will not be exported.", photoPath )
                self.exportSession:removePhoto( _photo )
                removed = true
            end
            if not removed then
            
                local sourceFilePath = photoPath
            	local sourceFilename = LrPathUtils.leafName( sourceFilePath ) -- photo:getFormattedMetadata( 'fileName' ) -- not necessarily same extension as rendered filename.

            	local sourceFolderPath = LrPathUtils.parent( photoPath )
            	local sourceSubfolderPath
            	if sourceFolderPath ~= nil then
                    sourceSubfolderPath = Common.getSubPath( self.exportParams.sourcePath, sourceFolderPath, self.exportParams.destPathSuffix, _photo, self.exportParams )
                    if sourceSubfolderPath == nil then
                        app:logW( "^1 is not in specified source path (^2) and can not be exported - either remove from collection or edit 'Source Path' setting to include it.", sourceFolderPath, self.exportParams.sourcePath )
                        return
                    end
                else
                    app:logE( "No parent path for source: ^1", sourceFilePath )
                    return
                end
            
            	local destFilePath, destFileName = self:getDestPhotoPath( _photo, sourceSubfolderPath, sourceFilename, self.cache )
            	if destFilePath ~= nil then
            	    if str:isEqualIgnoringCase( destFilePath, sourceFilePath ) then
                        app:logW( "Destination path is same as source path (^1) - photo or video will not be exported.", photoPath )
                        self.exportSession:removePhoto( _photo )
                        -- removed = true - write-only at this point..
                	elseif self.exportContext.publishService then
                	    if pubIds[destFilePath] then -- you're the dup.
                            self.exportSession:removePhoto( _photo )
                            if self.rawMeta[_photo].isVirtualCopy then
                                app:logW( "Destination path already taken by '^1'. Virtual copy being excluded from export: '^2'", pubIds[destFilePath], str:fmt( "^1 (^2)", photoPath, self.fmtMeta[_photo].copyName ) )
                            else
                                app:logW( "Destination path already taken by '^1'. Photo being excluded from export: '^2'", pubIds[destFilePath], photoPath )
                            end
                            --removed = true - write-only.
                	    else -- first come first served.
                	        pubIds[destFilePath] = photoPath
                	        cnt = cnt + 1
                	        app:logV( "Approved for export #^1, source: ^2, destination: ^3", cnt, photoPath, destFilePath )
                	    end
                	-- else nada
                	end
                else
                    Debug.pause( "no dest path" ) -- dunno what conditions would result in this.
                end
            end -- end if not removed
        end
        self.pubPhotoIds = {}
    end, finale=function( call, status, message )
        -- Debug.pause( status, message )
    end } )
end



--  This still in use, albeit not much but a thin wrapper around ftp-publish upload func.
--  2nd param obsolete now..
function TreeSyncPublish:uploadFile( file )
    assert( self.exportParams, "no export params" )
    assert( self.deferUploading ~= nil, "def-upld nil" )
    if self.deferUploading then
        if not self.fileToUpload[file] then
            app:logV( "Uploading is deferred - queueing '^1' for uploading later.", file )
            self.fileToUpload[file] = true
        else
            app:logV( "Uploading is deferred - '^1' already queued for uploading later.", file )
        end
        return true
    else -- don't defer, schedule upload via aggregator now.
        local s, m = FtpPublish.uploadFile( self, file ) -- presumably logs something..
        return s, m
    end
end


--
function TreeSyncPublish:uploadFiles()
    Debug.pauseIf( self.deferUploading == nil, "deferred uploading param not init" )
    if tab:isNotEmpty( self.fileToUpload ) then
        if not self.deferUploading then
            Debug.pause( "uploading not deferred, yet there are files queued for upload - hmm..." )
            app:logW( "uploading not deferred, yet there are files queued for upload - hmm..." )
            -- really this should not happen, but I guess if they're queued for uplaod, they should be uploaded (?).
        end
        for file, _t in pairs( self.fileToUpload ) do
            assert( _t, "file for upload can not be dequeued" ) -- ###2 revisit if such is to be done..
            local s, m = FtpPublish.uploadFile( self, file ) -- auto-assures a new job first time.
            if s then
                app:log( "FTP aggregator app to upload: ^1", file )
                Debug.pause( "FTP aggregator app to upload:", file )
            else
                app:logW( "Unable to hand '^1' to FTP aggregator app for uploading - ^2", file, m )
            end
        end
        self.fileToUpload = {} -- ###2 (not really where this should be done..).
        if self.jobNum and self.taskNum then
            local srvcName = self:_getServiceName( self.exportParams )
            ftpAgApp:endOfJob( srvcName, self.jobNum, self.taskNum ) -- iffy ###2
        else
            Debug.pause( "No job-num or task-num." ) -- this should "never" happen, since the job/task should be auto-created upon first file upload.
            app:logW( "No job-num or task-num." ) 
        end
    elseif self.deferUploading then
        app:log( "*** No files to upload." ) -- unusual, but not an error..
    else
        app:logV( "Uploading not deferred and no files queued for uploading.." ) -- this is the normal case when not deferred - don't trip..
    end
end




--[[
        Process one rendered photo.
        
        Called in the renditions loop. This is the method to override if you
        want to do something different with the photos being rendered...
--]]
function TreeSyncPublish:processRenderedPhoto( rendition, renderedFilePath )
    self.nPhotosRendered = self.nPhotosRendered + 1 -- note: its rendered whether rendered photo can be handled correctly or not.

    local photo = rendition.photo
       
    if self.cache == nil then
        app:error( "no cached metadata" )
    end
    if self.rawMeta == nil then
        app:error( "no batched raw metadata" )
    end
    if self.rawMeta[photo] == nil then
        app:error( "no batched raw metadata for photo: " .. str:to( photo ) )
    end
    if self.rawMeta[photo].path == nil then
        app:error( "no batched raw metadata path for photo" )
    end
    
    local sourceFilePath = self.rawMeta[photo].path
    app:logV( "Considering export of '^1:", sourceFilePath )
	local sourceFilename = LrPathUtils.leafName( sourceFilePath ) -- photo:getFormattedMetadata( 'fileName' ) -- not necessarily same extension as rendered filename.
    local fmt = self.rawMeta[photo].fileFormat

	local sourceFolderPath = LrPathUtils.parent( sourceFilePath )
	local sourceSubfolderPath, collOrFldr
	if sourceFolderPath ~= nil then
        sourceSubfolderPath, collOrFldr = Common.getSubPath( self.exportParams.sourcePath, sourceFolderPath, self.exportParams.destPathSuffix, photo, self.exportParams, self )
        if sourceSubfolderPath then
            --
        else -- collOrFldr is errm, but not sure it's very informative.. ###2.
            app:logW( "^1 is not in specified source path (^2) and can not be exported - either remove from set of photos to export, or edit 'Source Path' setting to include it.", sourceFolderPath, self.exportParams.sourcePath )
            return
        end
    else
        app:logE( "No parent path for source: ^1", sourceFilePath )
        return
    end
        
	local renderedFilename = LrPathUtils.leafName( renderedFilePath ) -- @3/Jul/2014 12:04 - read-only.
	
	local destFilePath, destFileName = self:getDestPhotoPath( rendition, sourceSubfolderPath, sourceFilename, self.cache )
	--local destFileExists = fso:existsAsFile( destFilePath )
	--if self.exportParams.destTreeType ~= 'flat' then
    	if collOrFldr then
    	    local srcType -- type of entry.
    	    local srcPath -- path of ordered source.
    	    local destFolder = LrPathUtils.parent( destFilePath )
            if self.exportParams.destTreeType == 'coll' then
                -- src-type has to be the type of the mirrored/ordered source, not the exporting collection type.
                if self.exportParams.isPubColl then
                    srcType = 'LrPublishedCollection'
                else -- ###1: could this not be pub-service or catalog?
                    srcType = 'LrCollection'
                end
        	    local collPath = collections:getFullCollPath( collOrFldr )
        	    local comps = str:splitPath( collPath ) -- root is #1.
        	    local coll, path = Common.getMasterCollectionSet( self.exportParams ) -- returns coll-set, and coll-set-path. ###1 best not to keep recomputing the same thing.
        	    if coll then
        	        comps[1] = str:getRoot( path )
            	    srcPath = str:componentsToPath( comps, "/" )
            	    --Debug.pause( srcPath )
            	else
            	    srcPath = collOrFldr -- ###1 probably should just throw an error a log an error.., right?
            	    Debug.pause( "?", srcPath )
            	end
        	else -- folder or flat
        	    -- tested 'flat' 24/Sep/2014 - seems fine (export and publish).
        	    srcType = 'LrFolder'
        	    srcPath = collOrFldr:getPath() -- always correct in case of 'folder'? ###1
        	end
    	    if self.srcSet[srcPath] == nil then
    	        self.srcSet[srcPath] = { srcType=srcType, folder=destFolder, files={} }
    	    end
    	    local files = self.srcSet[srcPath].files
    	    files[self.cache:getRaw( photo, 'uuid' )] = destFilePath
    	else
    	    Debug.pause( "no coll or fldr" )
    	end
    -- else 
    -- end

    local uuid = self.rawMeta[photo].uuid -- cache? ###2
    local photoId = LrPathUtils.addExtension( destFilePath, uuid ) -- assures uniqueness, so there will never be a "duplicate remote-id" error upon export.
    local photoUrl, errm = self.getRemoteUrl { -- "file://" .. destFilePath
        photo = photo,
        photoId = photoId,
        settings = self.exportParams,
    }
	
	local exported
    local moveSrc
    local copyXmp
    local xmpSrc
    local xmpDest
    if self.exportParams.LR_format == 'ORIGINAL' and fmt == 'RAW' then
        -- consider raw file.
        if self.exportParams.inclRaws then
            local srcModTime = fso:getFileModificationDate( sourceFilePath )
            if srcModTime then
                local destModTime = fso:getFileModificationDate( destFilePath )
                if destModTime then
                    if srcModTime > (destModTime + 2) then -- fudge factor of 2 used in case file-time not same rez, e.g. when target is a card.
                        moveSrc = true
                        app:logV( "Source raw modified." )
                    elseif srcModTime == destModTime then
                        app:logV( "Source raw has not been modified." )
                    elseif destModTime > (srcModTime + 2) then
                        app:logW( "Dest raw newer than source raw." )
                    else
                        app:logV( "Source raw mod time is appx same as dest raw mod time." )
                    end
                else
                    app:logV( "Destination raw not pre-existing: " .. destFilePath )
                    moveSrc = true
                end
            else
                app:logW( "Source file not found: " .. sourceFilePath )                        
            end
        else
            app:logV( "Raw file is not being included." )
        end
        -- consider xmp
        if self.exportParams.inclXmp then
            xmpSrc = LrPathUtils.replaceExtension( sourceFilePath, "xmp" )
            xmpDest = LrPathUtils.replaceExtension( destFilePath, "xmp" )
            if fso:existsAsFile( xmpSrc ) then
                if self.exportParams.inclXmpIfChanged then
                    if fso:existsAsFile( xmpDest ) then
                        local isChanged, orMessage = xmp:isChanged( xmpSrc, xmpDest )
                        if isChanged then
                            copyXmp = true
                            app:logV( "XMP file has changed, significantly." )
                        elseif isChanged == nil then -- message guaranteed.
                            local errm = orMessage or "no reason given - sorry"
                            app:logE( errm )
                        elseif orMessage then -- message may be present
                            app:logV( orMessage )
                        else
                            app:logV( "xmp unchanged" )
                        end
                    else
                        app:logV( "xmp dest does not pre-exist: ^1", xmpDest )
                        copyXmp = true
                    end
                else -- include unconditionally.
                    copyXmp = true
                end
            else
                app:logV( "xmp src does not exist: ^1", xmpSrc )
                -- cant copy something that does not exist.
            end
        else
            -- nothing further required - not including xmp.
            app:logV( "XMP is not being included." )
        end
    else
        moveSrc = true
    end
	                
    if moveSrc then -- note: not necessarily "source", i.e. often is the copy rendered to a temp location (comment added 27/Jan/2014 17:33).
        local fileMoved, comment, overwritten, dirsCreated = fso:moveFile( renderedFilePath, destFilePath, true, true )
        if fileMoved then
	        self.srvc.nCopied = self.srvc.nCopied + 1
            exported = true
            
            if self.exportParams.remPub then
                local s, m = self:uploadFile( destFilePath )
                if s then
                    app:logV( "exported file scheduled for upload by FTP app: ^1", destFilePath )
                else
                    Debug.pauseIf( not m, s )
                    app:logE( m or "not sure why.." )
                    return
                end
            end
            
    		if not overwritten then
    			self.srvc.nNewFilesCreated = self.srvc.nNewFilesCreated + 1
    			app:log( "New File Created #^1: ^2", self.srvc.nNewFilesCreated, destFilePath )
    		else -- existing file overwritten/updated.
    			self.srvc.nExistingFilesUpdated = self.srvc.nExistingFilesUpdated + 1
    			app:log( "Existing File Updated #^1: ^2", self.srvc.nExistingFilesUpdated, destFilePath )
    		end
            
        else
            app:logE( "File not exported - " .. str:to( comment ) )
        end
    else
        exported = true
    end
    
    if copyXmp then
        local s, m = fso:copyFile( xmpSrc, xmpDest,
            false, -- dir already there
            true,  -- overwrite OK
            true   -- avoid unnecessary update
        )
        if s then
            self.srvc.nXmpCopied = self.srvc.nXmpCopied + 1
            app:log( "XMP sidecar #^1 copied from '^2' to '^3'.", self.srvc.nXmpCopied, xmpSrc, xmpDest )
            if self.exportParams.remPub then
                local s, m = self:uploadFile( xmpDest ) -- this was 'xmpDext' until 27/Jan/2014 17:12 - obviously a bug.
                if s then
                    app:logV( "xmp file scheduled for upload by FTP app: ^1", xmpDest )
                else
                    app:logE( m or "?" )
                    return
                end
            end
        else
            app:logE( m or "??" )
            exported = false
        end
    -- else
    end
    
    if exported then
        if self.exportParams.addToCatalog then
            local inCat = cat:findPhotoByPath( destFilePath ) -- desparate?
            if inCat then
                app:logV( "Already in catalog: ^1", destFilePath )
            else
                local s, m = cat:update( 30, "Add Exported Photo To Catalog", function( context, phase )
                    catalog:addPhoto( destFilePath )
                end )
                if s then
                    app:log( "Added to catalog: ^1", destFilePath )
                else
                    app:logE( "Not already existing in catalog, yet not able to add to catalog: '^1' - ^2", destFilePath, m )
                    exported = false
                end
            end
        else
            -- app:logV( "Not adding to catalog..." )
        end
    end

	if exported then

        if self.exportContext.publishService then
            
            app:log( "Published ^1", sourceFilePath )
            local id = rendition.publishedPhotoId
            if id ~=nil and id ~= photoId then
                app:logV( "Attempting to change published photo id from '^1' to '^2'", id, photoId )
            end
    		rendition:recordPublishedPhotoId( photoId )
    		
            app:logV( "Recorded published photo destination (Id): ^1", photoId )
            if str:is( photoUrl ) then
  		        rendition:recordPublishedPhotoUrl( photoUrl )
                app:logV( "Recorded published photo Url: ^1", photoUrl )
            else
                app:logV( "Recorded published photo sans Url." )
  		    end
    	else
    	    -- app:logV( "No ID or URL defined for rendition when doing non-publishing export." )
            app:log( "Exported ^1", sourceFilePath )
    	end

		-- added 18/Feb/2014 11:16 ( delete wasn't working until after a maint-run ).
        local key = str:pathToPropForPluginKey( destFilePath )
        --Debug.pause( key, uuid )  		        
        cat:setPropertyForPlugin( key, uuid ) -- Save mapping entry from destination file to source photo. Throws error if trouble.
  		        
    -- else handled
	end

    
end



--[[
        Process one rendering failure.
        
        process-rendered-photo or process-rendering-failure -
        one or the other will be called depending on whether
        the photo was successfully rendered or not.
        
        Default behavior is to log an error and keep on truckin'...
--]]
function TreeSyncPublish:processRenderingFailure( rendition, message )
    if not message then error( "no message", 4 ) end
    FtpPublish.processRenderingFailure( self, rendition, message )
end



--[[
        Handle special export service...
        
        Note: The base export service method essentially divides the export
        task up and calls individual methods for doing the pieces. This is
        the one to override to change what get logged at the outset of the
        service, or you the partitioning into sub-tasks is not to your liking...
--]]
function TreeSyncPublish:service()
    FtpPublish.service( self )
end



-- Get root of local export tree.
--
-- this tidbit is used to determine sub-path, which is used to set local path for ftp purposes, which is used
-- to determine remote path.
--
function TreeSyncPublish:getDestDir( props, photo, _cache ) -- dest *root* dir, I think (hope).
    return props.destPath
end



--[[
        Handle special export finale...
--]]
function TreeSyncPublish:finale( service, status, message )
    local name = self.exportParams.LR_publish_connectionName or "export"
    service:enableSuppressionOfFinalDialogBoxDespiteErrorsAndWarnings( self.exportParams.permitSuppressionOfErrorsAndWarnings and "Export/publish errors and/or warnings" or nil ) -- enable (apk), or disable (nil).
    cat:setPropertyForPlugin( name .. '_cardFileNum', self.cardFileNum )
    app:log()
    app:logInfo( str:fmt( "^1 finale, statistics:\n^2 total export candidates\n^3 photos rendered\n^4 copied to local tree\n^5 new files created\n^6 existing files updated\n^7 buried in stack/ignored\n^8 xmp sidecars copied", service.name,
        self.nPhotosToExport,
        self.nPhotosRendered,
        self.srvc.nCopied,
        self.srvc.nNewFilesCreated,
    	self.srvc.nExistingFilesUpdated,
        self.srvc.nBuriedIgnored,
        self.srvc.nXmpCopied
        ))
    -- else no action
    if self.exportParams.cardDelEna then
        repeat
            local dcimDir = self.exportParams.dcimPath
            local toDel = {}
            if fso:existsAsDir( dcimDir ) then
                for file in LrFileUtils.recursiveFiles( dcimDir ) do
                    toDel[#toDel + 1] = file
                end
            else
                app:show{ warning="^1 does not exist - no files will be deleted (check DCIM path).", dcimDir }
                break
            end
            if #toDel > 0 then
                app:log( "The following ^1 files will be deleted if you approve:", #toDel )
                app:log( table.concat( toDel, "\n" ) )
                app:log()
                local answer
                repeat
                    answer = app:show{ info="Delete ^1 in ^2 and subfolders?",
                        subs = { str:plural( #toDel, "file", true ), dcimDir },
                        buttons = { dia:btn( "Show Log File", 'ok' ), dia:btn( "Yes", 'other' ), dia:btn( "No", 'cancel' ) },
                    }
                    if answer == 'ok' then
                        app:showLogFile()
                    elseif answer == 'other' then
                        app:log( "*** Deletion approved." )
                        break
                    elseif answer == 'cancel' then
                        app:log( "Deletion NOT approved." )
                        break
                    else
                        error( "bad answer" )
                    end
                until false
                if answer == 'other' then
                    app:log( "Proceeding to delete files..." )
                    local cnt = 0
                    for i, file in ipairs( toDel ) do
                        app:logStart( "Deleting " .. file )
                        local moved, qual = fso:moveToTrash( file )
                        if moved then
                            if str:is( qual ) then
                                app:logFinish( " - ^1.", qual )
                            else
                                app:logFinish( " - moved to trash." )
                            end
                            cnt = cnt + 1
                        else
                            app:logFinish( " - NOT deleted: ^1", str:to( qual ) )
                        end
                    end
                    app:log( "^1 deleted.", str:plural( cnt, "file", true ) )
                else
                    app:log( "Not deleting files" )
                end
            else
                app:log( "No files to delete in ^1 or its subfolders.", dcimDir )
            end
        until true
    end
    if self.exportParams.remPub then
        FtpPublish.finale( self, service, status, message ) -- this is all about ftp (i.e. end-of-job), so don't do it if not ftp'ing (rem-pub).
    end
end



-----------------------------------------------------------------------------------------





--   R E T U R N   E X P O R T   D E F I N I T I O N   T A B L E   T O   L I G H T R O O M

-- TreeSyncPublish.showSections = { 'postProcessing' }
TreeSyncPublish.hideSections = {
    'exportLocation',               -- "location" is being handled as special (note: also missing will be options to overwrite without asking, or append unique suffix...).
}


local exportParams = {}
exportParams[#exportParams + 1] = { key = 'remPub', default = false }
exportParams[#exportParams + 1] = { key = 'uploadImmed', default = false }
exportParams[#exportParams + 1] = { key = "managedPreset", default = 'Default' }
exportParams[#exportParams + 1] = { key = 'sourcePath', default = "" }
exportParams[#exportParams + 1] = { key = 'smartCollsToo', default = false }
exportParams[#exportParams + 1] = { key = 'photosToo', default = false }
exportParams[#exportParams + 1] = { key = 'destPath', default = "" }
exportParams[#exportParams + 1] = { key = 'destPathSuffix', default = "" }
exportParams[#exportParams + 1] = { key = 'ignoreBuried', default = false }
--exportParams[#exportParams + 1] = { key = 'flat', default = false } - auto migrated, presumably (untested).
exportParams[#exportParams + 1] = { key = 'destTreeType', default = 'folder' } -- coll(set), or flat(no-tree).
exportParams[#exportParams + 1] = { key = 'collSetId', default = nil }
exportParams[#exportParams + 1] = { key = 'isPubColl', default = true }
exportParams[#exportParams + 1] = { key = 'inclRaws', default = true } -- applies to "original" format only.
exportParams[#exportParams + 1] = { key = 'inclRawsIfSensible', default = true } -- ditto
exportParams[#exportParams + 1] = { key = 'inclXmp', default = true } -- applies to "original" format only - sidecars.
exportParams[#exportParams + 1] = { key = 'inclXmpIfChanged', default = false } -- ditto
exportParams[#exportParams + 1] = { key = 'cardDelEna', default = false }
exportParams[#exportParams + 1] = { key = 'cardDelMsg', default = false }
exportParams[#exportParams + 1] = { key = 'dcimPath', default = "" }
exportParams[#exportParams + 1] = { key = 'cardCompat', default = false }
exportParams[#exportParams + 1] = { key = 'localViewer', default = "" }
exportParams[#exportParams + 1] = { key = 'smartCopyName', default = true }
exportParams[#exportParams + 1] = { key = 'copyNameTemplate', default = " ({copy_name})" }
exportParams[#exportParams + 1] = { key = 'filenameNonVirt', default = "" }
exportParams[#exportParams + 1] = { key = 'filenameVirtCopy', default = "" }
exportParams[#exportParams + 1] = { key = 'egPhotoPath', default = "" }
exportParams[#exportParams + 1] = { key = 'destFolderPath', default = "" }
exportParams[#exportParams + 1] = { key = 'addToCatalog', default = false }
exportParams[#exportParams + 1] = { key = 'assureOrder', default = false }
exportParams[#exportParams + 1] = { key = 'orderVia', default = "createdTime" } -- other options will be 'modifiedTime' and 'captureTime' - the later to require exiftool.

exportParams[#exportParams + 1] = { key = 'permitSuppressionOfErrorsAndWarnings', default=false }

-- no need for inbox, since it can simply be an ftp setting (server-path).

--      local s, cm, c = app:changeFileDates{ modifiedTime=LrDate.currentTime() } -- touch last-mod.
--      local s, cm, c = app:changeFileDates{ createdTime=LrDate.currentTime() } -- touch created.
--      local s, cm, c = app:changeFileDates{ modifiedTime=now, createdTime=now } -- touch both ('now' set to current time).
--      local s, cm, c = app:changeFileDates{ modifiedTime=LrDate.currentTime() - 86400 } -- set last mod to 24 hours ago.
--      local s, cm, c = app:changeFileDates{ createdTime=LrDate.currentTime() - 86400 } -- set created to 24hours ago.
--      local s, cm, c = app:changeFileDates{ modifiedTime=now, createdTime=LrDate.currentTime() - 86400 } -- created 24 hours ago, modified now.
--
--  @return status
--  @return message
--  @return content

TreeSyncPublish.exportPresetFields = tab:appendArray( exportParams, FtpPublish.exportPresetFields )

TreeSyncPublish.canExportVideo = true



----------------------------------------------------
--   P U B L I S H   S P E C I F I C   S U P P O R T
----------------------------------------------------



--------------------------------------------------------------------------------
--- (optional) Plug-in defined value declares whether this plug-in supports the Lightroom
 -- publish feature. If not present, this plug-in is available in Export only.
 -- When true, this plug-in can be used for both Export and Publish. When 
 -- set to the string "only", the plug-in is visible only in Publish.
	-- @name exportServiceProvider.supportsIncrementalPublish
	-- @class property
TreeSyncPublish.supportsIncrementalPublish = true

--------------------------------------------------------------------------------
--- (string) Plug-in defined value is the filename of the icon to be displayed
 -- for this publish service provider, in the Publish Services panel, the Publish 
 -- Manager dialog, and in the header shown when a published collection is selected.
 -- The icon must be in PNG format and no more than 26 pixels wide or 19 pixels tall.
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @name TreeSyncPublish.small_icon
	-- @class property
TreeSyncPublish.small_icon = 'are-cee_logo.png'

--------------------------------------------------------------------------------
--- (optional, string) Plug-in defined value customizes the behavior of the
 -- Description entry in the Publish Manager dialog. If the user does not provide
 -- an explicit name choice, Lightroom can provide one based on another entry
 -- in the publishSettings property table. This entry contains the name of the
 -- property that should be used in this case.
	-- @name TreeSyncPublish.publish_fallbackNameBinding
	-- @class property
TreeSyncPublish.publish_fallbackNameBinding = nil -- ###2: there is really no property available to give a good (& new & unique) name - make user name them...

--------------------------------------------------------------------------------
--- (optional, string) Plug-in defined value customizes the name of a published
 -- collection to match the terminology used on the service you are targeting.
 -- <p>This string is typically used in combination with verbs that take action on
 -- the published collection, such as "Create ^1" or "Rename ^1".</p>
 -- <p>If not provided, Lightroom uses the default name, "Published Collection." </p>
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @name TreeSyncPublish.titleForPublishedCollection
	-- @class property
	
TreeSyncPublish.titleForPublishedCollection = "Photo Collection"

--------------------------------------------------------------------------------
--- (optional, string) Plug-in defined value customizes the name of a published
 -- collection to match the terminology used on the service you are targeting.
 -- <p>Unlike <code>titleForPublishedCollection</code>, this string is typically
 -- used by itself. In English, these strings nay be the same, but in
 -- other languages (notably German), you may have to use a different form
 -- of the name to be gramatically correct. If you are localizing your plug-in,
 -- use a separate translation key to make this possible.</p>
 -- <p>If not provided, Lightroom uses the value of
 -- <code>titleForPublishedCollection</code> instead.</p>
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @name TreeSyncPublish.titleForPublishedCollection_standalone
	-- @class property

--TreeSyncPublish.titleForPublishedCollection_standalone = LOC "$$$/Flickr/TitleForPublishedCollection/Standalone=Photoset"

--------------------------------------------------------------------------------
--- (optional, string) Plug-in defined value customizes the name of a published
 -- collection set to match the terminology used on the service you are targeting.
 -- <p>This string is typically used in combination with verbs that take action on
 -- the published collection set, such as "Create ^1" or "Rename ^1".</p>
 -- <p>If not provided, Lightroom uses the default name, "Published Collection Set." </p>
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @name TreeSyncPublish.titleForPublishedCollectionSet
	-- @class property
	
TreeSyncPublish.titleForPublishedCollectionSet = "Collection Set" -- not used for Flickr plug-in

--------------------------------------------------------------------------------
--- (optional, string) Plug-in defined value customizes the name of a published
 -- collection to match the terminology used on the service you are targeting.
 -- <p>Unlike <code>titleForPublishedCollectionSet</code>, this string is typically
 -- used by itself. In English, these strings may be the same, but in
 -- other languages (notably German), you may have to use a different form
 -- of the name to be gramatically correct. If you are localizing your plug-in,
 -- use a separate translation key to make this possible.</p>
 -- <p>If not provided, Lightroom uses the value of
 -- <code>titleForPublishedCollectionSet</code> instead.</p>
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @name TreeSyncPublish.titleForPublishedCollectionSet_standalone
	-- @class property

--TreeSyncPublish.titleForPublishedCollectionSet_standalone = "(something)" -- not used for Flickr plug-in

--------------------------------------------------------------------------------
--- (optional, string) Plug-in defined value customizes the name of a published
 -- smart collection to match the terminology used on the service you are targeting.
 -- <p>This string is typically used in combination with verbs that take action on
 -- the published smart collection, such as "Create ^1" or "Rename ^1".</p>
 -- <p>If not provided, Lightroom uses the default name, "Published Smart Collection." </p>
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
 	-- @name TreeSyncPublish.titleForPublishedSmartCollection
	-- @class property

TreeSyncPublish.titleForPublishedSmartCollection = "Smart Collection"

--------------------------------------------------------------------------------
--- (optional, string) Plug-in defined value customizes the name of a published
 -- smart collection to match the terminology used on the service you are targeting.
 -- <p>Unlike <code>titleForPublishedSmartCollection</code>, this string is typically
 -- used by itself. In English, these strings may be the same, but in
 -- other languages (notably German), you may have to use a different form
 -- of the name to be gramatically correct. If you are localizing your plug-in,
 -- use a separate translation key to make this possible.</p>
 -- <p>If not provided, Lightroom uses the value of
 -- <code>titleForPublishedSmartCollectionSet</code> instead.</p>
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @name TreeSyncPublish.titleForPublishedSmartCollection_standalone
	-- @class property

--TreeSyncPublish.titleForPublishedSmartCollection_standalone = LOC "$$$/Flickr/TitleForPublishedSmartCollection/Standalone=Smart Photoset"

--------------------------------------------------------------------------------
--- (optional) If you provide this plug-in defined callback function, Lightroom calls it to
 -- retrieve the default collection behavior for this publish service, then use that information to create
 -- a built-in <i>default collection</i> for this service (if one does not yet exist). 
 -- This special collection is marked in italics and always listed at the top of the list of published collections.
 -- <p>This callback should return a table that configures the default collection. The
 -- elements of the configuration table are optional, and default as shown.</p>
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @param publishSettings (table) The settings for this publish service, as specified
		-- by the user in the Publish Manager dialog. Any changes that you make in
		-- this table do not persist beyond the scope of this function call.
	-- @return (table) A table with the following fields:
	  -- <ul>
	   -- <li><b>defaultCollectionName</b>: (string) The name for the default
	   -- 	collection. If not specified, the name is "untitled" (or
	   --   a language-appropriate equivalent). </li>
	   -- <li><b>defaultCollectionCanBeDeleted</b>: (Boolean) True to allow the 
	   -- 	user to delete the default collection. Default is true. </li>
	   -- <li><b>canAddCollection</b>: (Boolean)  True to allow the 
	   -- 	user to add collections through the UI. Default is true. </li>
	   -- <li><b>maxCollectionSetDepth</b>: (number) A maximum depth to which 
	   --  collection sets can be nested, or zero to disallow collection sets. 
 	   --  If not specified, unlimited nesting is allowed. </li>
	  -- </ul>
	-- @name TreeSyncPublish.getCollectionBehaviorInfo
	-- @class function
function TreeSyncPublish.getCollectionBehaviorInfo( publishSettings )

	return {
		defaultCollectionName = str:fmt( "Regular Collection" ), -- simple enough. thought about "Photos To Publish" but seems misleading if user defines smart collection too.
		    -- Note: default name for smart coll is 'Smart Publish Collection'.
		defaultCollectionCanBeDeleted = true,
		canAddCollection = true,
		-- maxCollectionSetDepth = 0, - unlimited.
			-- Collection sets are not supported through the Flickr sample plug-in.
	}
	
end

--------------------------------------------------------------------------------
--- When set to the string "disable", the "Go to Published Collection" context-menu item
 -- is disabled (dimmed) for this publish service.
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @name TreeSyncPublish.titleForGoToPublishedCollection
	-- @class property

TreeSyncPublish.titleForGoToPublishedCollection = "Show Destination of Local Tree"

--------------------------------------------------------------------------------
--- (optional) This plug-in defined callback function is called when the user chooses
 -- the "Go to Published Collection" context-menu item.
 -- <p>If this function is not provided, Lightroom uses the URL	recorded for the published collection via
 -- <a href="LrExportSession.html#exportSession:recordRemoteCollectionUrl"><code>exportSession:recordRemoteCollectionUrl</code></a>.</p>
 -- <p>This is not a blocking call. It is called from within a task created
 -- using the <a href="LrTasks.html"><code>LrTasks</code></a> namespace. In most
 -- cases, you should not need to start your own task within this function.</p>
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @name TreeSyncPublish.goToPublishedCollection
	-- @class function
	-- @param publishSettings (table) The settings for this publish service, as specified
		-- by the user in the Publish Manager dialog. Any changes that you make in
		-- this table do not persist beyond the scope of this function call.
	-- @param info (table) A table with these fields:
	 -- <ul>
	  -- <li><b>publishedCollectionInfo</b>: (<a href="LrPublishedCollectionInfo.html"><code>LrPublishedCollectionInfo</code></a>)
	  --  	An object containing  publication information for this published collection.</li>
	  -- <li><b>photo</b>: (<a href="LrPhoto.html"><code>LrPhoto</code></a>) The photo object. </li>
	  -- <li><b>publishedPhoto</b>: (<a href="LrPublishedPhoto.html"><code>LrPublishedPhoto</code></a>)
	  -- 	The object that contains information previously recorded about this photo's publication.</li>
	  -- <li><b>remoteId</b>: (string or number) The ID for this published collection
	  -- 	that was stored via <a href="LrExportSession.html#exportSession:recordRemoteCollectionId"><code>exportSession:recordRemoteCollectionId</code></a></li>
	  -- <li><b>remoteUrl</b>: (optional, string) The URL, if any, that was recorded for the published collection via
	  -- <a href="LrExportSession.html#exportSession:recordRemoteCollectionUrl"><code>exportSession:recordRemoteCollectionUrl</code></a>.</li>
	 -- </ul>

function TreeSyncPublish.goToPublishedCollection( publishSettings, info ) -- note: this is redundent, since dest-path is already clickable - oh well..
    app:call( Call:new{ name=TreeSyncPublish.titleForGoToPublishedCollection, async=false, main=function( call )
        local destPath = publishSettings.destPath
        if str:is( destPath ) then
            destPath = LrPathUtils.standardizePath( destPath )
            if fso:existsAsDir( destPath ) then
                LrShell.revealInShell( destPath )
            else
                app:show{ warning="Destination '^1' does not yet exist - try exporting or publishing first.", destPath }
            end
        else
            app:show{ error="No destination path is blank." }
        end
    end } )
end

--------------------------------------------------------------------------------
--- (optional, string) Plug-in defined value overrides the label for the 
 -- "Go to Published Photo" context-menu item, allowing you to use something more appropriate to
 -- your service. Set to the special value "disable" to disable (dim) the menu item for this service. 
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @name TreeSyncPublish.titleForGoToPublishedPhoto
	-- @class property
TreeSyncPublish.titleForGoToPublishedPhoto = "Show Published Photo"

--------------------------------------------------------------------------------
--- (optional) This plug-in defined callback function is called when the user chooses the
 -- "Go to Published Photo" context-menu item.
 -- <p>If this function is not provided, Lightroom invokes the URL recorded for the published photo via
 -- <a href="LrExportRendition.html#exportRendition:recordPublishedPhotoUrl"><code>exportRendition:recordPublishedPhotoUrl</code></a>.</p>
 -- <p>This is not a blocking call. It is called from within a task created
 -- using the <a href="LrTasks.html"><code>LrTasks</code></a> namespace. In most
 -- cases, you should not need to start your own task within this function.</p>
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @name TreeSyncPublish.goToPublishedPhoto
	-- @class function
	-- @param publishSettings (table) The settings for this publish service, as specified
		-- by the user in the Publish Manager dialog. Any changes that you make in
		-- this table do not persist beyond the scope of this function call.
	-- @param info (table) A table with these fields:
	 -- <ul>
	  -- <li><b>publishedCollectionInfo</b>: (<a href="LrPublishedCollectionInfo.html"><code>LrPublishedCollectionInfo</code></a>)
	  --  	An object containing  publication information for this published collection.</li>
	  -- <li><b>photo</b>: (<a href="LrPhoto.html"><code>LrPhoto</code></a>) The photo object. </li>
	  -- <li><b>publishedPhoto</b>: (<a href="LrPublishedPhoto.html"><code>LrPublishedPhoto</code></a>)
	  -- 	The object that contains information previously recorded about this photo's publication.</li>
	  -- <li><b>remoteId</b>: (string or number) The ID for this published photo
	  -- 	that was stored via <a href="LrExportRendition.html#exportRendition:recordPublishedPhotoId"><code>exportRendition:recordPublishedPhotoId</code></a></li>
	  -- <li><b>remoteUrl</b>: (optional, string) The URL, if any, that was recorded for the published photo via
	  -- <a href="LrExportRendition.html#exportRendition:recordPublishedPhotoUrl"><code>exportRendition:recordPublishedPhotoUrl</code></a>.</li>
	 -- </ul>

-- Not used for Flickr plug-in.

function TreeSyncPublish.goToPublishedPhoto( publishSettings, info )
    assert( publishSettings ~= nil, "no publish-settings" )
    assert( info ~= nil, "no info" )
    assert( info.remoteId ~= nil, "no info--remote-id" )
    assert( info.photo ~= nil, "no info--photo" )
    local fmt = info.photo:getRawMetadata( 'fileFormat' )
    local viewer = publishSettings.localViewer
    app:assert( publishSettings.managedPreset ~= nil, "no pm-preset" )
    local viewerParams = app:getPref( 'localViewerParams', publishSettings.managedPreset )
    local path, orNot = Common.getDestPathFromPublishedId( info.remoteId, publishSettings )
    local url
    if path then
        local showRemote
        if publishSettings.remPub then
            if publishSettings.ftpMove then
                showRemote = true -- no local version should exist.
            else
                local button = app:show{ confirm="Show local or remote version of published photo?",
                    buttons = { dia:btn( "Local", 'ok' ), dia:btn( "Remote", 'other' ) },
                    actionPrefKey = "Show local or remote version of published photo",
                }
                if button == 'other' then 
                    showRemote = true
                -- else false
                end
            end
        -- else show-remote is false.
        end
        if not showRemote then
            if fso:existsAsFile( path ) then
                if str:is( viewer ) then
                    local s, m, c = app:executeCommand( viewer, viewerParams, path )
                    if s then
                        app:logV( "Viewing via command: ^1", str:to( c ) )
                    else
                        app:logV( "*** Not sure if viewer worked, more: ^1", str:to( m ) )
                    end
                    return -- done
                else
                    app:log( "Showing photo in browser, since local viewer is blank in publish settings." )
                    url = "file://" .. path
                end            
            else
                app:show{ warning="Local version does not exist: ^1", path }
                return
            end
        else -- show-remote
            url = info.remoteUrl
        end
        if str:is( url ) then
            if fmt == 'VIDEO' then
                app:show{ warning="Can't play video file directly in web browser - consider configuring a local viewer that can play video." }
                return
            else
                LrHttp.openUrlInBrowser( url )
            end
        else
            app:show{ warning="No URL - try a maintenance run." }
        end
    else
        app:show{ warning="^1 - consider a maintenance run.", orNot }
    end
end



--------------------------------------------------------------------------------
--- (optional) This plug-in defined callback function is called when the user creates
 -- a new publish service via the Publish Manager dialog. It allows your plug-in
 -- to perform additional initialization.
 -- <p>This is not a blocking call. It is called from within a task created
 -- using the <a href="LrTasks.html"><code>LrTasks</code></a> namespace. In most
 -- cases, you should not need to start your own task within this function.</p>
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @name TreeSyncPublish.didCreateNewPublishService
	-- @class function
	-- @param publishSettings (table) The settings for this publish service, as specified
		-- by the user in the Publish Manager dialog. Any changes that you make in
		-- this table do not persist beyond the scope of this function call.
	-- @param info (table) A table with these fields:
	 -- <ul>
	  -- <li><b>connectionName</b>: (string) the name of the newly-created service</li>
	  -- <li><b>publishService</b>: (<a href="LrPublishService.html"><code>LrPublishService</code></a>)
	  -- 	The publish service object.</li>
	 -- </ul>

-- Not used for Flickr plug-in.

function TreeSyncPublish.didCreateNewPublishService( publishSettings, info )
    local dflt = app:getInfo( 'LrExportServiceProvider' ).title
    if info.connectionName == dflt then
        app:show{ warning="Please give this publish service a name in the 'Description' field using the Publishing Manager." }
    else
        Debug.logn( info.connectionName )
        Debug.showLogFile()
    end
end



--------------------------------------------------------------------------------
--- (optional) This plug-in defined callback function is called when the user creates
 -- a new publish service via the Publish Manager dialog. It allows your plug-in
 -- to perform additional initialization.
 -- <p>This is not a blocking call. It is called from within a task created
 -- using the <a href="LrTasks.html"><code>LrTasks</code></a> namespace. In most
 -- cases, you should not need to start your own task within this function.</p>
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @name TreeSyncPublish.didUpdatePublishService
	-- @class function
	-- @param publishSettings (table) The settings for this publish service, as specified
		-- by the user in the Publish Manager dialog. Any changes that you make in
		-- this table do not persist beyond the scope of this function call.
	-- @param info (table) A table with these fields:
	 -- <ul>
	  -- <li><b>connectionName</b>: (string) the name of the newly-created service</li>
	  -- <li><b>nPublishedPhotos</b>: (number) how many photos are currently published on the service</li>
	  -- <li><b>publishService</b>: (<a href="LrPublishService.html"><code>LrPublishService</code></a>)
	  -- 	The publish service object.</li>
	  -- <li><b>changedMoreThanName</b>: (boolean) true if any setting other than the name
	  --  (description) has changed</li>
	 -- </ul>

--[[ Not used for Flickr plug-in.

function TreeSyncPublish.didUpdatePublishService( publishSettings, info )
end

--]]

--------------------------------------------------------------------------------
--- (optional) This plug-in defined callback function is called when the user
 -- has attempted to delete the publish service from Lightroom.
 -- It provides an opportunity for you to customize the confirmation dialog.
 -- <p>Do not use this hook to actually tear down the service. Instead, use
 -- <a href="#TreeSyncPublish.willDeletePublishService"><code>willDeletePublishService</code></a>
 -- for that purpose.
 -- <p>This is not a blocking call. It is called from within a task created
 -- using the <a href="LrTasks.html"><code>LrTasks</code></a> namespace. In most
 -- cases, you should not need to start your own task within this function.</p>
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @name TreeSyncPublish.shouldDeletePublishService
	-- @class function
	-- @param publishSettings (table) The settings for this publish service, as specified
		-- by the user in the Publish Manager dialog. Any changes that you make in
		-- this table do not persist beyond the scope of this function call.
	-- @param info (table) A table with these fields:
	  -- <ul>
		-- <li><b>publishService</b>: (<a href="LrPublishService.html"><code>LrPublishService</code></a>)
		-- 	The publish service object.</li>
		-- <li><b>nPhotos</b>: (number) The number of photos contained in
		-- 	published collections within this service.</li>
		-- <li><b>connectionName</b>: (string) The name assigned to this publish service connection by the user.</li>
	  -- </ul>
	-- @return (string) 'cancel', 'delete', or nil (to allow Lightroom's default
		-- dialog to be shown instead)

--[[ Not used for Flickr plug-in.

function TreeSyncPublish.shouldDeletePublishService( publishSettings, info )
end

--]]

--------------------------------------------------------------------------------
--- (optional) This plug-in defined callback function is called when the user
 -- has confirmed the deletion of the publish service from Lightroom.
 -- It provides a final opportunity for	you to remove private data
 -- immediately before the publish service is removed from the Lightroom catalog.
 -- <p>Do not use this hook to present user interface (aside from progress,
 -- if the operation will take a long time). Instead, use 
 -- <a href="#TreeSyncPublish.shouldDeletePublishService"><code>shouldDeletePublishService</code></a>
 -- for that purpose.
 -- <p>This is not a blocking call. It is called from within a task created
 -- using the <a href="LrTasks.html"><code>LrTasks</code></a> namespace. In most
 -- cases, you should not need to start your own task within this function.</p>
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @name TreeSyncPublish.willDeletePublishService
	-- @class function
	-- @param publishSettings (table) The settings for this publish service, as specified
		-- by the user in the Publish Manager dialog. Any changes that you make in
		-- this table do not persist beyond the scope of this function call.
	-- @param info (table) A table with these fields:
	 -- <ul>
		-- <li><b>publishService</b>: (<a href="LrPublishService.html"><code>LrPublishService</code></a>)
		-- 	The publish service object.</li>
		-- <li><b>nPhotos</b>: (number) The number of photos contained in
		-- 	published collections within this service.</li>
		-- <li><b>connectionName</b>: (string) The name assigned to this publish service connection by the user.</li>
	-- </ul>

--[[ Not used for Flickr plug-in.

function TreeSyncPublish.willDeletePublishService( publishSettings, info )
end

--]]

--------------------------------------------------------------------------------
--- (optional) This plug-in defined callback function is called when the user
 -- has attempted to delete one or more published collections defined by your
 -- plug-in from Lightroom. It provides an opportunity for you to customize the
 -- confirmation dialog.
 -- <p>Do not use this hook to actually tear down the collection(s). Instead, use
 -- <a href="#TreeSyncPublish.deletePublishedCollection"><code>deletePublishedCollection</code></a>
 -- for that purpose.
 -- <p>This is not a blocking call. It is called from within a task created
 -- using the <a href="LrTasks.html"><code>LrTasks</code></a> namespace. In most
 -- cases, you should not need to start your own task within this function.</p>
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @name TreeSyncPublish.shouldDeletePublishedCollection
	-- @class function
	-- @param publishSettings (table) The settings for this publish service, as specified
		-- by the user in the Publish Manager dialog. Any changes that you make in
		-- this table do not persist beyond the scope of this function call.
	-- @param info (table) A table with these fields:
	 -- <ul>
		-- <li><b>collections</b>: (array of <a href="LrPublishedCollection.html"><code>LrPublishedCollection</code></a>
		--  or <a href="LrPublishedCollectionSet.html"><code>LrPublishedCollectionSet</code></a>)
		-- 	The published collection objects.</li>
		-- <li><b>nPhotos</b>: (number) The number of photos contained in the
		-- 	published collection. Only present if there is a single published collection
		--  to be deleted.</li>
		-- <li><b>nChildren</b>: (number) The number of child collections contained within the
		-- 	published collection set. Only present if there is a single published collection set
		--  to be deleted.</li>
		-- <li><b>hasItemsOnService</b>: (boolean) True if one or more photos have been
		--  published through the collection(s) to be deleted.</li>
	-- </ul>
	-- @return (string) "ignore", "cancel", "delete", or nil
	 -- (If you return nil, Lightroom's default dialog will be displayed.)

--[[ Not used for Flickr plug-in.

function TreeSyncPublish.shouldDeletePublishedCollection( publishSettings, info )
end

--]]

--------------------------------------------------------------------------------
--- (optional) This plug-in defined callback function is called when the user
 -- has attempted to delete one or more photos from the Lightroom catalog that are
 -- published through your service. It provides an opportunity for you to customize
 -- the confirmation dialog.
 -- <p>Do not use this hook to actually delete photo(s). Instead, if the user
 -- confirms the deletion for all relevant services. Lightroom will call
 -- <a href="#TreeSyncPublish.deletePhotosFromPublishedCollection"><code>deletePhotosFromPublishedCollection</code></a>
 -- for that purpose.
 -- <p>This is not a blocking call. It is called from within a task created
 -- using the <a href="LrTasks.html"><code>LrTasks</code></a> namespace. In most
 -- cases, you should not need to start your own task within this function.</p>
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @name TreeSyncPublish.shouldDeletePhotosFromServiceOnDeleteFromCatalog
	-- @class function
	-- @param publishSettings (table) The settings for this publish service, as specified
		-- by the user in the Publish Manager dialog. Any changes that you make in
		-- this table do not persist beyond the scope of this function call.
	-- @param nPhotos (number) The number of photos that are being deleted. At least
		-- one of these photos is published through this service; some may only be published
		-- on other services or not published at all.
	-- @return (string) What action should Lightroom take?
		-- <ul>
			-- <li><b>"ignore"</b>: Leave the photos on the service and simply forget about them.</li>
			-- <li><b>"cancel"</b>: Stop the attempt to delete the photos.
			-- <li><b>"delete"</b>: Have Lightroom delete the photos immediately from the service.
				-- (Your plug-in will receive a call to its
				-- <a href="#TreeSyncPublish.deletePhotosFromPublishedCollection"><code>deletePhotosFromPublishedCollection</code></a>
				-- in this case.)</li>
			-- <li><b>nil</b>: Allow Lightroom's built-in confirmation dialog to be displayed.</li>
		-- </ul>

--[[ Not used for Flickr plug-in.

function TreeSyncPublish.shouldDeletePhotosFromServiceOnDeleteFromCatalog( publishSettings, nPhotos )
end

--]]

--------------------------------------------------------------------------------
--- This plug-in defined callback function is called when one or more photos
 -- have been removed from a published collection and need to be removed from
 -- the service. If the service you are supporting allows photos to be deleted
 -- via its API, you should do that from this function.
 -- <p>As each photo is deleted, you should call the <code>deletedCallback</code>
 -- function to inform Lightroom that the deletion was successful. This will cause
 -- Lightroom to remove the photo from the "Delete Photos to Remove" group in the
 -- Library grid.</p>
 -- <p>This is not a blocking call. It is called from within a task created
 -- using the <a href="LrTasks.html"><code>LrTasks</code></a> namespace. In most
 -- cases, you should not need to start your own task within this function.</p>
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @name TreeSyncPublish.deletePhotosFromPublishedCollection
	-- @class function
	-- @param publishSettings (table) The settings for this publish service, as specified
		-- by the user in the Publish Manager dialog. Any changes that you make in
		-- this table do not persist beyond the scope of this function call.
	-- @param arrayOfPhotoIds (table) The remote photo IDs that were declared by this plug-in
		-- when they were published.
	-- @param deletedCallback (function) This function must be called for each photo ID
		-- as soon as the deletion is confirmed by the remote service. It takes a single
		-- argument: the photo ID from the arrayOfPhotoIds array.

function TreeSyncPublish.deletePhotosFromPublishedCollection( publishSettings, arrayOfPhotoIds, deletedCallback )
    -- note: remote-id is "local-destination-path.uuid".
    local tsp
    
    app:service{ name="Delete Photos From Published Collection", async=false, guard=App.guardVocal, main=function( call )
    
        tsp = TreeSyncPublish:new{ exportParams = publishSettings }
        if publishSettings.remPub then
        
            -- ftp app can get in the way of deleting empty folders, since it may be cwd'd to them...
            -- that's been remedied in the ftp app, with the side-effect that it may stay logged in forever, since
            -- it keeps issuing the command to cd to root. ###2
            local ftpSettings = {
                server = publishSettings.server,
                username = publishSettings.username,
                password = publishSettings.password,
                protocol = publishSettings.protocol,
                port = publishSettings.port,
                passive = publishSettings.passive,
                path = publishSettings.path,
            }
        
            assert( ftpSettings.server ~= nil, "no ftp server in publish service settings" )
            local ok = Ftp.assurePassword( ftpSettings ) -- this call required to get password from encrypted store, if not in preset. If not in encrypted store either, then prompt.
            if not ok then
                call:cancel()
                return
            end
            
            local s, m = tsp:newFtpJob() -- assure dirs, assign job-num & init task-num..
            if not s then
                app:logE( m )
                return
            end
            
            if publishSettings.uploadImmed then
                local s, m = ftpAgApp:assureRunning()
                if not s then
                    app:logE( m )
                    return
                end
            end

        end
        
        local localFilesToDelete = {}
    	for i, photoId in ipairs( arrayOfPhotoIds ) do
            local destPath, msg = Common.getDestPathFromPublishedId( photoId, publishSettings )
            if destPath then
                if fso:existsAsFile( destPath ) then
                    app:log( "To be deleted: ^1", destPath )
                    localFilesToDelete[#localFilesToDelete + 1] = destPath
                else
                end
            else
            end
        end

        local doDel = false
        if #localFilesToDelete > 0 then        
            app:log()
            app:log()
            app:log( "Published photos to be deleted from publish destination:")
            app:log()
        	for i, photoId in ipairs( arrayOfPhotoIds ) do
                local destPath, msg = Common.getDestPathFromPublishedId( photoId, publishSettings )
                if destPath then
                    if fso:existsAsFile( destPath ) then
                        app:log( "To be deleted: ^1", destPath )
                        localFilesToDelete[#localFilesToDelete + 1] = destPath
                    else
                    end
                else
                end
            end
            app:log()
            app:log()
        
            repeat
                local answer = app:show{ info="Delete ^1? List of files to delete are in log file.",
                    subs = { str:plural( #arrayOfPhotoIds, "target photo", true ) },
                    buttons = { dia:btn( "Yes - Delete Target Photos", 'ok' ), dia:btn( "View Log File", 'view_logs') }, -- , dia:btn( "No - Just Pretend...", 'other' ) }, -- and cancel.
                    actionPrefKey = "Delete photos confirmation",
                }
                if answer == 'ok' then
                    doDel = true
                    break
                elseif answer == 'cancel' then
                    return
                elseif answer == 'other' then
                    -- continue with do-Del = false
                    break
                elseif answer == 'view_logs' then
                    app:showLogFile()
                else
                    error( "bad answer" )
                end
            until false
    
        else
            app:log( "No local files to delete." )
        end        
    
        local cs, cp
        if publishSettings.destType == 'coll' then
            cs, cp = Common.getMasterCollectionSet( publishSettings )
        end

        app:log( "Deleting photos from publish destination:" )
        local problems = {}
        
    	for i, photoId in ipairs( arrayOfPhotoIds ) do
    
    		--###2FlickrAPI.deletePhoto( publishSettings, { photoId = photoId, suppressErrorCodes = { [ 1 ] = true } } )
    							-- If Flickr says photo not found, ignore that.

            repeat
    							
                local destPath, msg = Common.getDestPathFromPublishedId( photoId, publishSettings )
                
                local localFileHandled = true
                
                if destPath then
                    if fso:existsAsFile( destPath ) then
                        if doDel then
                            local del, qual = fso:moveToTrash( destPath )
                            if del then
                                if str:is( qual ) then
                                    app:log( "Destination deleted or moved to trash: ^1", qual )
                                else
                                    app:log( "Destination moved to trash: ^1", destPath )
                                end
                                local ext = LrStringUtils.lower( LrPathUtils.extension( destPath ) )
                                if ext ~= 'jpg' and ext ~= 'dng' and ext ~= 'tif' and ext ~='psd' then -- its either raw or video.
                                    local xmpSidecar = LrPathUtils.replaceExtension( destPath, 'xmp' )
                                    if fso:existsAsFile( xmpSidecar ) then
                                        local del, qual = fso:moveToTrash( xmpSidecar )
                                        if del then
                                            if str:is( qual ) then
                                                app:log( "xmp sidecar deleted or moved to trash: ^1", qual )
                                            else
                                                app:log( "xmp sidecar moved to trash: ^1", xmpSidecar )
                                            end
                                        else
                                            app:log( "Unable to delete xmp sidecar - ^1", str:to( qual ) )
                                        end
                                    else
                                        app:logV( "No sidecar for ^1 to delete.", destPath )
                                    end
                                else
                                    app:logV( "Not considering deletion of sidecar for ^1", destPath )
                                end
                            else
                                app:logE( "Unable to delete destination file - ^1", str:to( qual ) )
                                localFileHandled = false
                            end
                        else
                            app:log( "Not deleting ^1", destPath )
                        end
                    else
                        app:log( "Deleted photo no longer exists locally: ^1", destPath )
                    end
                    -- app:logV( "Photo deleted from published collection, remote id=^1 (invoking callback)", photoId )
                    
                    -- Whether file exists or not, it should be purged from remote host as well, if it exists there, and ftp-upload is enabled.
                    if localFileHandled then
                        if publishSettings.remPub then
                            local photo, addl
                            addl = publishSettings.destPathSuffix -- a tad convoluted.
                            local uuid = LrPathUtils.extension( photoId )
                            photo = catalog:findPhotoByUuid( uuid or "asdf" )
                            if photo then
                                 -- good
                            else
                                Debug.pause()
                                app:logE( "Unable to find photo from ID - consider a maintenance run.." )
                                break -- ###2 does maintenance run remedy this?
                            end
                            local remotePath = Common.getSubPath( publishSettings.destPath, destPath, addl, photo, publishSettings )
                            if str:is( remotePath ) then
                                remotePath = str:replaceBackSlashesWithForwardSlashes( remotePath )
                                --local s, m = ftp:removeFile( remotePath )
                                local s, m = tsp:purgeFile( destPath ) -- seems backwards (passing local file path to delete remote file), but that's how it works..
                                if s then
                                    app:log( "^1 scheduled for removal from remote host by ftp aggregator app.", remotePath ) -- ###1 is it handling emptied-dir?
                                    deletedCallback( photoId )
                                else
                                    app:logE( "Unable to remove '^1' from remote host, error message: ^2", m )
                                    problems[#problems + 1] = photoId
                                end
                            else
                                app:logE( "^1 not prefixed with ^2 - consider a maintenance run.", destPath, publishSettings.destPath )
                                problems[#problems + 1] = photoId
                            end
                        else
                            deletedCallback( photoId )
                        end
                    else
                        -- don't consider handling remote file.
                        problems[#problems + 1] = photoId
                    end
                    
                else
                    app:logE( msg .. " - consider a maintenance run." )
                    problems[#problems + 1] = photoId
                end
            until true    
    	end -- for
    	
    	if #problems > 0 then
    	    if dia:isOk( "^1 - consider to be deleted despite problems?", str:plural( #problems, "problem", true ) ) then
    	        for i, problemId in ipairs( problems ) do
                    deletedCallback( problemId )
    	        end
    	    else
    	        app:logW( "^1 remain.", str:plural( #problems, "problem", true ) )
    	    end
    	-- else no problems
    	end
    end, finale=function( call )
        if publishSettings.remPub then
            assert( tsp, "no tsp" )
            --FtpExport.finale( tsp, call ) -- get-srvc-name, then end-of-job.
            local srvcName = tsp:_getServiceName( publishSettings )
            ftpAgApp:endOfJob( srvcName, tsp.jobNum, tsp.taskNum )
        end
    end }	
	
end

--------------------------------------------------------------------------------
--- (optional) This plug-in defined callback function is called whenever a new
 -- publish service is created and whenever the settings for a publish service
 -- are changed. It allows the plug-in to specify which metadata should be
 -- considered when Lightroom determines whether an existing photo should be
 -- moved to the "Modified Photos to Re-Publish" status.
 -- <p>This is a blocking call.</p>
	-- @name TreeSyncPublish.metadataThatTriggersRepublish
	-- @class function
	-- @param publishSettings (table) The settings for this publish service, as specified
		-- by the user in the Publish Manager dialog. Any changes that you make in
		-- this table do not persist beyond the scope of this function call.
	-- @return (table) A table containing one or more of the following elements
		-- as key, Boolean true or false as a value, where true means that a change
		-- to the value does trigger republish status, and false means changes to the
		-- value are ignored:
		-- <ul>
		  -- <li><b>default</b>: All built-in metadata that appears in XMP for the file.
		  -- You can override this default behavior by explicitly naming any of these
		  -- specific fields:
		    -- <ul>
			-- <li><b>rating</b></li>
			-- <li><b>label</b></li>
			-- <li><b>title</b></li>
			-- <li><b>caption</b></li>
			-- <li><b>gps</b></li>
			-- <li><b>gpsAltitude</b></li>
			-- <li><b>creator</b></li>
			-- <li><b>creatorJobTitle</b></li>
			-- <li><b>creatorAddress</b></li>
			-- <li><b>creatorCity</b></li>
			-- <li><b>creatorStateProvince</b></li>
			-- <li><b>creatorPostalCode</b></li>
			-- <li><b>creatorCountry</b></li>
			-- <li><b>creatorPhone</b></li>
			-- <li><b>creatorEmail</b></li>
			-- <li><b>creatorUrl</b></li>
			-- <li><b>headline</b></li>
			-- <li><b>iptcSubjectCode</b></li>
			-- <li><b>descriptionWriter</b></li>
			-- <li><b>iptcCategory</b></li>
			-- <li><b>iptcOtherCategories</b></li>
			-- <li><b>dateCreated</b></li>
			-- <li><b>intellectualGenre</b></li>
			-- <li><b>scene</b></li>
			-- <li><b>location</b></li>
			-- <li><b>city</b></li>
			-- <li><b>stateProvince</b></li>
			-- <li><b>country</b></li>
			-- <li><b>isoCountryCode</b></li>
			-- <li><b>jobIdentifier</b></li>
			-- <li><b>instructions</b></li>
			-- <li><b>provider</b></li>
			-- <li><b>source</b></li>
			-- <li><b>copyright</b></li>
			-- <li><b>rightsUsageTerms</b></li>
			-- <li><b>copyrightInfoUrl</b></li>
			-- <li><b>copyrightStatus</b></li>
			-- <li><b>keywords</b></li>
		    -- </ul>
		  -- <li><b>customMetadata</b>: All plug-in defined custom metadata (defined by any plug-in).</li>
		  -- <li><b><i>(plug-in ID)</i>.*</b>: All custom metadata defined by the plug-in with the specified ID.</li>
		  -- <li><b><i>(plug-in ID).(field ID)</i></b>: One specific custom metadata field defined by the plug-in with the specified ID.</li>
		-- </ul>

function TreeSyncPublish.metadataThatTriggersRepublish( publishSettings )

    if publishSettings.managedPreset == nil then
        Debug.pause( "no pm-preset" )
        publishSettings.managedPreset = 'Default'
    end
    -- local triggers = app:getPref( 'triggers' ) - pre 28/Jun/2014 14:48.
    local triggers = app:getPref( 'triggers', publishSettings.managedPreset ) -- post 28/Jun/2014 14:48. ###2 delete comment if no issues come 2016.
    if triggers then
        app:logV( "Using triggers configured in advanced settings." )
    else
        app:logW( "No triggers configured - falling back to defaults." )
        triggers = {
            -- ###2
    		default = false,
    		title = true,
    		caption = true,
    		keywords = true,
    		gps = true,
    		dateCreated = true,
    		-- also (not used by Flickr sample plug-in):
    			-- customMetadata = true,
    			-- com.whoever.plugin_name.* = true,
    			-- com.whoever.plugin_name.field_name = true,
        }
    end
	return triggers

end

--------------------------------------------------------------------------------
--- (optional) This plug-in defined callback function is called when the user
 -- creates a new published collection or edits an existing one. It can add
 -- additional controls to the dialog box for editing this collection. These controls
 -- can be used to configure behaviors specific to this collection (such as
 -- privacy or appearance on a web service).
 -- <p>This is a blocking call. If you need to start a long-running task (such as
 -- network access), create a task using the <a href="LrTasks.html"><code>LrTasks</code></a>
 -- namespace.</p>
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @name TreeSyncPublish.viewForCollectionSettings
	-- @class function
	-- @param f (<a href="LrView.html#LrView.osFactory"><code>LrView.osFactory</code></a> object)
		-- A view factory object.
	-- @param publishSettings (table) The settings for this publish service, as specified
		-- by the user in the Publish Manager dialog. Any changes that you make in
		-- this table do not persist beyond the scope of this function call.
	-- @param info (table) A table with these fields:
	 -- <ul>
		-- <li><b>collectionSettings</b>: (<a href="LrObservableTable.html"><code>LrObservableTable</code></a>)
			-- Plug-in specific settings for this collection. The settings in this table
			-- are not interpreted by Lightroom in any way, except that they are stored
			-- with the collection. These settings can be accessed via
			-- <a href="LrPublishedCollection.html#pubCollection:getCollectionInfoSummary"><code>LrPublishedCollection:getCollectionInfoSummary</code></a>.
			-- The values in this table must be numbers, strings, or Booleans.
			-- There is a special property in this table, <code>LR_canSaveCollection</code>
			-- which allows you to disable the Edit or Create button in the collection dialog.
			-- (If set to true, the Edit / Create button is enabled; if false, it is disabled.)</li>
		-- <li><b>collectionType</b>: (string) Either "collection" or "smartCollection"
			-- (see also: <code>viewForCollectionSetSettings</code>)</li>
		-- <li><b>isDefaultCollection</b>: (Boolean) True if this is the default collection.</li>
		-- <li><b>name</b>: (name) The name of this collection.</li>
		-- <li><b>parents</b>: (table) An array of information about parents of this collection, in which each element contains:
			-- <ul>
				-- <li><b>localCollectionId</b>: (number) The local collection ID.</li>
				-- <li><b>name</b>: (string) Name of the collection set.</li>
				-- <li><b>remoteCollectionId</b>: (number or string) The remote collection ID assigned by the server.</li>
			-- </ul>
		-- This field is only present when editing an existing published collection.
		-- </li>
		-- <li><b>pluginContext</b>: (<a href="LrObservableTable.html"><code>LrObservableTable</code></a>)
			-- This is a place for your plug-in to store transient state while the collection
			-- settings dialog is running. It is passed to your plug-in's
			-- <code>endDialogForCollectionSettings</code> callback, and then discarded.</li>
		-- <li><b>publishedCollection</b>: (<a href="LrPublishedCollection.html"><code>LrPublishedCollection</code></a>)
			-- The published collection object being edited, or nil when creating a new
			-- collection.</li>
		-- <li><b>publishService</b>: (<a href="LrPublishService.html"><code>LrPublishService</code></a>)
		-- 	The publish service object to which this collection belongs.</li>
	-- </ul>
	-- @return (table) A single view description created from one of the methods in
		-- the view factory. (We recommend that <code>f:groupBox</code> be the outermost view.)
 
--[[ Not used for Flickr plug-in. This is an example of how this function might work.

function TreeSyncPublish.viewForCollectionSettings( f, publishSettings, info )

	local collectionSettings = assert( info.collectionSettings )
	
	-- Fill in default parameters. This code sample targets a hypothetical service
	-- that allows users to enable or disable ratings and comments on a per-collection
	-- basis.

	if collectionSettings.enableRating == nil then
		collectionSettings.enableRating = false
	end

	if collectionSettings.enableComments == nil then
		collectionSettings.enableComments = false
	end
	
	local bind = import 'LrView'.bind

	return f:group_box {
		title = "Sample Plug-in Collection Settings",  -- this should be localized via LOC
		size = 'small',
		fill_horizontal = 1,
		bind_to_object = assert( collectionSettings ),
		
		f:column {
			fill_horizontal = 1,
			spacing = f:label_spacing(),

			f:checkbox {
				title = "Enable Rating",  -- this should be localized via LOC
				value = bind 'enableRating',
			},

			f:checkbox {
				title = "Enable Comments",  -- this should be localized via LOC
				value = bind 'enableComments',
			},
		},
		
	}

end
--]]

--------------------------------------------------------------------------------
--- (optional) This plug-in defined callback function is called when the user
 -- creates a new published collection set or edits an existing one. It can add
 -- additional controls to the dialog box for editing this collection set. These controls
 -- can be used to configure behaviors specific to this collection set (such as
 -- privacy or appearance on a web service).
 -- <p>This is a blocking call. If you need to start a long-running task (such as
 -- network access), create a task using the <a href="LrTasks.html"><code>LrTasks</code></a>
 -- namespace.</p>
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @name TreeSyncPublish.viewForCollectionSetSettings
	-- @class function
	-- @param f (<a href="LrView.html#LrView.osFactory"><code>LrView.osFactory</code></a> object)
		-- A view factory object.
	-- @param publishSettings (table) The settings for this publish service, as specified
		-- by the user in the Publish Manager dialog. Any changes that you make in
		-- this table do not persist beyond the scope of this function call.
	-- @param info (table) A table with these fields:
	 -- <ul>
		-- <li><b>collectionSettings</b>: (<a href="LrObservableTable.html"><code>LrObservableTable</code></a>)
			-- plug-in specific settings for this collection set. The settings in this table
			-- are not interpreted by Lightroom in any way, except that they are stored
			-- with the collection set. These settings can be accessed via
			-- <a href="LrPublishedCollectionSet.html#pubCollectionSet:getCollectionSetInfoSummary"><code>LrPublishedCollection:getCollectionSetInfoSummary</code></a>.
			-- The values in this table must be numbers, strings, or Booleans.
			-- There is a special property in this table, <code>LR_canSaveCollection</code>
			-- which allows you to disable the Edit or Create button in the collection dialog.
			-- (If set to true, the Edit / Create button is enabled; if false, it is disabled.)</li>
		-- <li><b>collectionType</b>: (string) "collectionSet"</li>
		-- <li><b>isDefaultCollection</b>: (Boolean) true if this is the default collection (will always be false)</li>
		-- <li><b>name</b>: (name) the name of this collection</li>
		-- <li><b>parents</b>: (table) An array of information about parents of this collection, in which each element contains:
			-- <ul>
				-- <li><b>localCollectionId</b>: (number) The local collection ID.</li>
				-- <li><b>name</b>: (string) Name of the collection set.</li>
				-- <li><b>remoteCollectionId</b>: (number or string) The remote collection ID assigned by the server.</li>
			-- </ul>  
		-- This field is only present when editing an existing published collection set. </li>
		-- <li><b>pluginContext</b>: (<a href="LrObservableTable.html"><code>LrObservableTable</code></a>)
			-- This is a place for your plug-in to store transient state while the collection set
			-- settings dialog is running. It will be passed to your plug-in during the
			-- <code>endDialogForCollectionSettings</code> and then discarded.</li>
		-- <li><b>publishedCollection</b>: (<a href="LrPublishedCollectionSet.html"><code>LrPublishedCollectionSet</code></a>)
			-- The published collection set object being edited. Will be nil when creating a new
			-- collection Set.</li>
		-- <li><b>publishService</b>: (<a href="LrPublishService.html"><code>LrPublishService</code></a>)
		-- 	The publish service object.</li>
	-- </ul>
	-- @return (table) A single view description created from one of the methods in
		-- the view factory. (We recommend that <code>f:groupBox</code> be the outermost view.)

--[[ Not used for Flickr plug-in.

function TreeSyncPublish.viewForCollectionSetSettings( f, publishSettings, info )
	-- See viewForCollectionSettings example above.
end

--]]

--------------------------------------------------------------------------------
--- (optional) This plug-in defined callback function is called when the user
 -- closes the dialog for creating a new published collection or editing an existing
 -- one. It is only called if you have also provided the <code>viewForCollectionSettings</code>
 -- callback, and is your opportunity to clean up any tasks or processes you may
 -- have started while the dialog was running.
 -- <p>This is a blocking call. If you need to start a long-running task (such as
 -- network access), create a task using the <a href="LrTasks.html"><code>LrTasks</code></a>
 -- namespace.</p>
 -- <p>Your code should <b>not</b> update the server from here. That should be done
 -- via the <code>updateCollectionSettings</code> callback. (If, for instance, the
 -- settings changes are later undone; this callback is not called again, but
 -- <code>updateCollectionSettings</code> is.)</p>
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @name TreeSyncPublish.endDialogForCollectionSettings
	-- @class function
	-- @param publishSettings (table) The settings for this publish service, as specified
		-- by the user in the Publish Manager dialog. Any changes that you make in
		-- this table do not persist beyond the scope of this function call.
	-- @param info (table) A table with these fields:
	 -- <ul>
		-- <li><b>collectionSettings</b>: (<a href="LrObservableTable.html"><code>LrObservableTable</code></a>)
			-- Plug-in specific settings for this collection. The settings in this table
			-- are not interpreted by Lightroom in any way, except that they are stored
			-- with the collection. These settings can be accessed via
			-- <a href="LrPublishedCollection.html#pubCollection:getCollectionInfoSummary"><code>LrPublishedCollection:getCollectionInfoSummary</code></a>.
			-- The values in this table must be numbers, strings, or Booleans.</li>
		-- <li><b>collectionType</b>: (string) Either "collection" or "smartCollection"</li>
		-- <li><b>isDefaultCollection</b>: (Boolean) True if this is the default collection.</li>
		-- <li><b>name</b>: (name) The name of this collection.</li>
		-- <li><b>parents</b>: (table) An array of information about parents of this collection, in which each element contains:
		   -- <ul>
			-- <li><b>localCollectionId</b>: (number) The local collection ID.</li>
			-- <li><b>name</b>: (string) Name of the collection set.</li>
			-- <li><b>remoteCollectionId</b>: (number or string) The remote collection ID assigned by the server.</li>
		   -- </ul>
		-- This field is only present when editing an existing published collection.
		-- </li>
		-- <li><b>pluginContext</b>: (<a href="LrObservableTable.html"><code>LrObservableTable</code></a>)
		-- 	This is a place for your plug-in to store transient state while the collection
		-- 	settings dialog is running. It is passed to your plug-in's
		-- 	<code>endDialogForCollectionSettings</code> callback, and then discarded.</li>
		-- <li><b>publishedCollection</b>: (<a href="LrPublishedCollection.html"><code>LrPublishedCollection</code></a>)
		-- 	The published collection object being edited.</li>
		-- <li><b>publishService</b>: (<a href="LrPublishService.html"><code>LrPublishService</code></a>)
		-- 	The publish service object to which this collection belongs.</li>
		-- <li><b>why</b>: (string) The button that was used to close the dialog, one of "ok" or "cancel".
	-- </ul>

--[[ Not used for Flickr plug-in. This is an example of how this function might work.

function TreeSyncPublish.endDialogForCollectionSettings( publishSettings, info )
	-- not used for Flickr plug-in
end

--]]

--------------------------------------------------------------------------------
--- (optional) This plug-in defined callback function is called when the user
 -- closes the dialog for creating a new published collection set or editing an existing
 -- one. It is only called if you have also provided the <code>viewForCollectionSetSettings</code>
 -- callback, and is your opportunity to clean up any tasks or processes you may
 -- have started while the dialog was running.
 -- <p>This is a blocking call. If you need to start a long-running task (such as
 -- network access), create a task using the <a href="LrTasks.html"><code>LrTasks</code></a>
 -- namespace.</p>
 -- <p>Your code should <b>not</b> update the server from here. That should be done
 -- via the <code>updateCollectionSetSettings</code> callback. (If, for instance, the
 -- settings changes are later undone; this callback will not be called again;
 -- <code>updateCollectionSetSettings</code> will be.)</p>
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @name TreeSyncPublish.endDialogForCollectionSetSettings
	-- @class function
	-- @param publishSettings (table) The settings for this publish service, as specified
		-- by the user in the Publish Manager dialog. Any changes that you make in
		-- this table do not persist beyond the scope of this function call.
	-- @param info (table) A table with these fields:
	 -- <ul>
		-- <li><b>collectionSettings</b>: (<a href="LrObservableTable.html"><code>LrObservableTable</code></a>)
			-- plug-in specific settings for this collection set. The settings in this table
			-- are not interpreted by Lightroom in any way, except that they are stored
			-- with the collection set. These settings can be accessed via
			-- <a href="LrPublishedCollectionSet.html#pubCollectionSet:getCollectionSetInfoSummary"><code>LrPublishedCollectionSet:getCollectionSetInfoSummary</code></a>.
			-- The values in this table must be numbers, strings, or Booleans.</li>
		-- <li><b>collectionType</b>: (string) "collectionSet"</li>
		-- <li><b>isDefaultCollection</b>: (boolean) true if this is the default collection (will always be false)</li>
		-- <li><b>name</b>: (name) the name of this collection set</li>
		-- <li><b>parents</b>: (table) An array of information about parents of this collection, in which each element contains:
		   -- <ul>
			-- <li><b>localCollectionId</b>: (number) The local collection ID.</li>
			-- <li><b>name</b>: (string) Name of the collection set.</li>
			-- <li><b>remoteCollectionId</b>: (number or string) The remote collection ID assigned by the server.</li>
		   -- </ul>
			-- This field is only present when editing an existing published collection set.
			-- </li>
		-- <li><b>pluginContext</b>: (<a href="LrObservableTable.html"><code>LrObservableTable</code></a>)
			-- This is a place for your plug-in to store transient state while the collection set
			-- settings dialog is running. It will be passed to your plug-in during the
			-- <code>endDialogForCollectionSettings</code> and then discarded.</li>
		-- <li><b>publishedCollectionSet</b>: (<a href="LrPublishedCollectionSet.html"><code>LrPublishedCollectionSet</code></a>)
		-- 	The published collection set object being edited.</li>
		-- <li><b>publishService</b>: (<a href="LrPublishService.html"><code>LrPublishService</code></a>)
		-- 	The publish service object.</li>
		-- <li><b>why</b>: (string) Why the dialog was closed. Either "ok" or "cancel".
	-- </ul>

--[[ Not used for Flickr plug-in. This is an example of how this function might work.

function TreeSyncPublish.endDialogForCollectionSetSettings( publishSettings, info )
	-- not used for Flickr plug-in
end

--]]

--------------------------------------------------------------------------------
--- (optional) This plug-in defined callback function is called when the user
 -- has changed the per-collection settings defined via the <code>viewForCollectionSettings</code>
 -- callback. It is your opportunity to update settings on your web service to
 -- match the new settings.
 -- <p>This is not a blocking call. It is called from within a task created
 -- using the <a href="LrTasks.html"><code>LrTasks</code></a> namespace. In most
 -- cases, you should not need to start your own task within this function.</p>
 -- <p>Your code should <b>not</b> use this callback function to clean up from the
 -- dialog. This callback is not be called if the user cancels the dialog.</p>
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @name TreeSyncPublish.updateCollectionSettings
	-- @class function
	-- @param publishSettings (table) The settings for this publish service, as specified
		-- by the user in the Publish Manager dialog. Any changes that you make in
		-- this table do not persist beyond the scope of this function call.
	-- @param info (table) A table with these fields:
	 -- <ul>
		-- <li><b>collectionSettings</b>: (<a href="LrObservableTable.html"><code>LrObservableTable</code></a>)
			-- Plug-in specific settings for this collection. The settings in this table
			-- are not interpreted by Lightroom in any way, except that they are stored
			-- with the collection. These settings can be accessed via
			-- <a href="LrPublishedCollection.html#pubCollection:getCollectionInfoSummary"><code>LrPublishedCollection:getCollectionInfoSummary</code></a>.
			-- The values in this table must be numbers, strings, or Booleans.
		-- <li><b>isDefaultCollection</b>: (Boolean) True if this is the default collection.</li>
		-- <li><b>name</b>: (name) The name of this collection.</li>
		-- <li><b>parents</b>: (table) An array of information about parents of this collection, in which each element contains:
			-- <ul>
				-- <li><b>localCollectionId</b>: (number) The local collection ID.</li>
				-- <li><b>name</b>: (string) Name of the collection set.</li>
				-- <li><b>remoteCollectionId</b>: (number or string) The remote collection ID assigned by the server.</li>
			-- </ul> </li>
		-- <li><b>publishedCollection</b>: (<a href="LrPublishedCollection.html"><code>LrPublishedCollection</code></a>
			-- or <a href="LrPublishedCollectionSet.html"><code>LrPublishedCollectionSet</code></a>)
		-- 	The published collection object being edited.</li>
		-- <li><b>publishService</b>: (<a href="LrPublishService.html"><code>LrPublishService</code></a>)
		-- 	The publish service object to which this collection belongs.</li>
	-- </ul>
 
--[[ Not used for Flickr plug-in.

function TreeSyncPublish.updateCollectionSettings( publishSettings, info )
end

--]]

--------------------------------------------------------------------------------
--- (optional) This plug-in defined callback function is called when the user
 -- has changed the per-collection set settings defined via the <code>viewForCollectionSetSettings</code>
 -- callback. It is your opportunity to update settings on your web service to
 -- match the new settings.
 -- <p>This is not a blocking call. It is called from within a task created
 -- using the <a href="LrTasks.html"><code>LrTasks</code></a> namespace. In most
 -- cases, you should not need to start your own task within this function.</p>
 -- <p>Your code should <b>not</b> use this callback function to clean up from the
 -- dialog. This callback will not be called if the user cancels the dialog.</p>
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @name TreeSyncPublish.updateCollectionSetSettings
	-- @class function
	-- @param publishSettings (table) The settings for this publish service, as specified
	-- 	by the user in the Publish Manager dialog. Any changes that you make in
	-- 	this table do not persist beyond the scope of this function call.
	-- @param info (table) A table with these fields:
	 -- <ul>
		-- <li><b>collectionSettings</b>: (<a href="LrObservableTable.html"><code>LrObservableTable</code></a>)
		-- 	Plug-in specific settings for this collection set. The settings in this table
		-- 	are not interpreted by Lightroom in any way, except that they are stored
		--  with the collection set. These settings can be accessed via
		--  <a href="LrPublishedCollectionSet.html#pubCollectionSet:getCollectionSetInfoSummary"><code>LrPublishedCollectionSet:getCollectionSetInfoSummary</code></a>.
		--  The values in this table must be numbers, strings, or Booleans.
		-- <li><b>isDefaultCollection</b>: (Boolean) True if this is the default collection (always false in this case).</li>
		-- <li><b>name</b>: (name) The name of this collection set.</li>
		-- <li><b>parents</b>: (table) An array of information about parents of this collection, in which each element contains:
			-- <ul>
				-- <li><b>localCollectionId</b>: (number) The local collection ID.</li>
				-- <li><b>name</b>: (string) Name of the collection set.</li>
				-- <li><b>remoteCollectionId</b>: (number or string) The remote collection ID assigned by the server.</li>
			-- </ul>  
		-- </li>
		-- <li><b>publishedCollection</b>: (<a href="LrPublishedCollectionSet.html"><code>LrPublishedCollectionSet</code></a>)
		-- 	The published collection set object being edited.</li>
		-- <li><b>publishService</b>: (<a href="LrPublishService.html"><code>LrPublishService</code></a>)
		-- 	The publish service object.</li>
	-- </ul>

--[[ Not used for Flickr plug-in.

function TreeSyncPublish.updateCollectionSetSettings( publishSettings, info )
end

--]]

--------------------------------------------------------------------------------
--- (optional) This plug-in defined callback function is called when new or updated
 -- photos are about to be published to the service. It allows you to specify whether
 -- the user-specified sort order should be followed as-is or reversed. The Flickr
 -- sample plug-in uses this to reverse the order on the Photostream so that photos
 -- appear in the Flickr web interface in the same sequence as they are shown in the 
 -- library grid.
 -- <p>This is not a blocking call. It is called from within a task created
 -- using the <a href="LrTasks.html"><code>LrTasks</code></a> namespace. In most
 -- cases, you should not need to start your own task within this function.</p>
	-- @param collectionInfo
	-- @name TreeSyncPublish.shouldReverseSequenceForPublishedCollection
	-- @class function
	-- @param publishSettings (table) The settings for this publish service, as specified
		-- by the user in the Publish Manager dialog. Any changes that you make in
		-- this table do not persist beyond the scope of this function call.
	-- @param publishedCollectionInfo (<a href="LrPublishedCollectionInfo.html"><code>LrPublishedCollectionInfo</code></a>) an object containing publication information for this published collection.
	-- @return (boolean) true to reverse the sequence when publishing new photos

function TreeSyncPublish.shouldReverseSequenceForPublishedCollection( publishSettings, collectionInfo )

	return collectionInfo.isDefaultCollection

end

--------------------------------------------------------------------------------
--- (Boolean) If this plug-in defined property is set to true, Lightroom will
 -- enable collections from this service to be sorted manually and will call
 -- the <a href="#TreeSyncPublish.imposeSortOrderOnPublishedCollection"><code>imposeSortOrderOnPublishedCollection</code></a>
 -- callback to cause photos to be sorted on the service after each Publish
 -- cycle.
	-- @name TreeSyncPublish.supportsCustomSortOrder
	-- @class property

TreeSyncPublish.supportsCustomSortOrder = true
	
--------------------------------------------------------------------------------
--- (optional) This plug-in defined callback function is called after each time
 -- that photos are published via this service assuming the published collection
 -- is set to "User Order." Your plug-in should ensure that the photos are displayed
 -- in the designated sequence on the service.
 -- <p>This is not a blocking call. It is called from within a task created
 -- using the <a href="LrTasks.html"><code>LrTasks</code></a> namespace. In most
 -- cases, you should not need to start your own task within this function.</p>
	-- @name TreeSyncPublish.imposeSortOrderOnPublishedCollection
	-- @class function
	-- @param publishSettings (table) The settings for this publish service, as specified
		-- by the user in the Publish Manager dialog. Any changes that you make in
		-- this table do not persist beyond the scope of this function call.
	-- @param info (table) A table with these fields:
	 -- <ul>
		-- <li><b>collectionSettings</b>: (<a href="LrObservableTable.html"><code>LrObservableTable</code></a>)
			-- plug-in specific settings for this collection set. The settings in this table
			-- are not interpreted by Lightroom in any way, except that they are stored
			-- with the collection set. These settings can be accessed via
			-- <a href="LrPublishedCollectionSet.html#pubCollectionSet:getCollectionSetInfoSummary"><code>LrPublishedCollectionSet:getCollectionSetInfoSummary</code></a>.
			-- The values in this table must be numbers, strings, or Booleans.
		-- <li><b>isDefaultCollection</b>: (boolean) true if this is the default collection (will always be false)</li>
		-- <li><b>name</b>: (name) the name of this collection set</li>
		-- <li><b>parents</b>: (table) array of information about parents of this collection set;
			-- each element of the array will contain:
				-- <ul>
					-- <li><b>localCollectionId</b>: (number) local collection ID</li>
					-- <li><b>name</b>: (string) name of the collection set</li>
					-- <li><b>remoteCollectionId</b>: (number of string) remote collection ID</li>
				-- </ul>
			-- </li>
		-- <li><b>remoteCollectionId</b>: (string or number) The ID for this published collection
		-- 	that was stored via <a href="LrExportSession.html#exportSession:recordRemoteCollectionId"><code>exportSession:recordRemoteCollectionId</code></a></li>
		-- <li><b>publishedUrl</b>: (optional, string) The URL, if any, that was recorded for the published collection via
		-- <a href="LrExportSession.html#exportSession:recordRemoteCollectionUrl"><code>exportSession:recordRemoteCollectionUrl</code></a>.</li>
	 -- <ul>
	-- @param remoteIdSequence (array of string or number) The IDs for each published photo
		-- 	that was stored via <a href="LrExportRendition.html#exportRendition:recordPublishedPhotoId"><code>exportRendition:recordPublishedPhotoId</code></a>
	-- @return (boolean) true to reverse the sequence when publishing new photos
--[[
-- ### - Note: this could be used for order of tree sync collection, but NOT the collection it's mirroring, if such resides in a different publish service,
-- which usually (always?) it does..
function TreeSyncPublish.imposeSortOrderOnPublishedCollection( publishSettings, info, remoteIdSequence )

	local photosetId = info.remoteCollectionId

	if photosetId then

		-- Get existing list of photos from the photoset. We want to be sure that we don't
		-- remove photos that were posted to this photoset by some other means by doing
		-- this call, so we look for photos that were missed and reinsert them at the end.

		local existingPhotoSequence = FlickrAPI.listPhotosFromPhotoset( publishSettings, { photosetId = photosetId } )

		-- Make a copy of the remote sequence from LR and then tack on any photos we didn't see earlier.
		
		local combinedRemoteSequence = {}
		local remoteIdsInSequence = {}
		
		for i, id in ipairs( remoteIdSequence ) do
			combinedRemoteSequence[ i ] = id
			remoteIdsInSequence[ id ] = true
		end
		
		for _, id in ipairs( existingPhotoSequence ) do
			if not remoteIdsInSequence[ id ] then
				combinedRemoteSequence[ #combinedRemoteSequence + 1 ] = id
			end
		end
		
		--FlickrAPI.setPhotosetSequence( publishSettings, {
		--						photosetId = photosetId,
		--						primary = existingPhotoSequence.primary,
		--						photoIds = combinedRemoteSequence } )
								
	end

end
--]]

-------------------------------------------------------------------------------
--- This plug-in defined callback function is called when the user attempts to change the name
 -- of a collection, to validate that the new name is acceptable for this service.
 -- <p>This is a blocking call. You should use it only to validate easily-verified
 -- characteristics of the name, such as illegal characters in the name. For
 -- characteristics that require validation against a server (such as duplicate
 -- names), you should accept the name here and reject the name when the server-side operation
 -- is attempted.</p>
	-- @name TreeSyncPublish.validatePublishedCollectionName
	-- @class function
 	-- @param proposedName (string) The name as currently typed in the new/rename/edit
		-- collection dialog.
	-- @return (Boolean) True if the name is acceptable, false if not
	-- @return (string) If the name is not acceptable, a string that describes the reason, suitable for display.

--[[ Not used for Flickr plug-in.

function TreeSyncPublish.validatePublishedCollectionName( proposedName )
	return true
end

--]]

-------------------------------------------------------------------------------
--- (Boolean) This plug-in defined value, when true, disables (dims) the Rename Published
 -- Collection command in the context menu of the Publish Services panel 
 -- for all published collections created by this service. 
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @name TreeSyncPublish.disableRenamePublishedCollection
	-- @class property

-- TreeSyncPublish.disableRenamePublishedCollection = true -- not used for Flickr sample plug-in

-------------------------------------------------------------------------------
--- (Boolean) This plug-in defined value, when true, disables (dims) the Rename Published
 -- Collection Set command in the context menu of the Publish Services panel
 -- for all published collection sets created by this service. 
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @name TreeSyncPublish.disableRenamePublishedCollectionSet
	-- @class property

-- TreeSyncPublish.disableRenamePublishedCollectionSet = true -- not used for Flickr sample plug-in

-------------------------------------------------------------------------------
--- This plug-in callback function is called when the user has renamed a
 -- published collection via the Publish Services panel user interface. This is
 -- your plug-in's opportunity to make the corresponding change on the service.
 -- <p>If your plug-in is unable to update the remote service for any reason,
 -- you should throw a Lua error from this function; this causes Lightroom to revert the change.</p>
 -- <p>This is not a blocking call. It is called from within a task created
 -- using the <a href="LrTasks.html"><code>LrTasks</code></a> namespace. In most
 -- cases, you should not need to start your own task within this function.</p>
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @name TreeSyncPublish.renamePublishedCollection
	-- @class function
	-- @param publishSettings (table) The settings for this publish service, as specified
		-- by the user in the Publish Manager dialog. Any changes that you make in
		-- this table do not persist beyond the scope of this function call.
	-- @param info (table) A table with these fields:
	 -- <ul>
	  -- <li><b>isDefaultCollection</b>: (Boolean) True if this is the default collection.</li>
	  -- <li><b>name</b>: (string) The new name being assigned to this collection.</li>
		-- <li><b>parents</b>: (table) An array of information about parents of this collection, in which each element contains:
			-- <ul>
				-- <li><b>localCollectionId</b>: (number) The local collection ID.</li>
				-- <li><b>name</b>: (string) Name of the collection set.</li>
				-- <li><b>remoteCollectionId</b>: (number or string) The remote collection ID assigned by the server.</li>
			-- </ul> </li>
 	  -- <li><b>publishService</b>: (<a href="LrPublishService.html"><code>LrPublishService</code></a>)
	  -- 	The publish service object.</li>
	  -- <li><b>publishedCollection</b>: (<a href="LrPublishedCollection.html"><code>LrPublishedCollection</code></a>
		-- or <a href="LrPublishedCollectionSet.html"><code>LrPublishedCollectionSet</code></a>)
	  -- 	The published collection object being renamed.</li>
	  -- <li><b>remoteId</b>: (string or number) The ID for this published collection
	  -- 	that was stored via <a href="LrExportSession.html#exportSession:recordRemoteCollectionId"><code>exportSession:recordRemoteCollectionId</code></a></li>
	  -- <li><b>remoteUrl</b>: (optional, string) The URL, if any, that was recorded for the published collection via
	  -- <a href="LrExportSession.html#exportSession:recordRemoteCollectionUrl"><code>exportSession:recordRemoteCollectionUrl</code></a>.</li>
	 -- </ul>
--[[
function TreeSyncPublish.renamePublishedCollection( publishSettings, info )

	if info.remoteId then

		--FlickrAPI.createOrUpdatePhotoset( publishSettings, {
		--					photosetId = info.remoteId,
		--					title = info.name,
		--				} )

	end
		
end
--]]

-------------------------------------------------------------------------------
--- This plug-in callback function is called when the user has reparented a
 -- published collection via the Publish Services panel user interface. This is
 -- your plug-in's opportunity to make the corresponding change on the service.
 -- <p>If your plug-in is unable to update the remote service for any reason,
 -- you should throw a Lua error from this function; this causes Lightroom to revert the change.</p>
 -- <p>This is not a blocking call. It is called from within a task created
 -- using the <a href="LrTasks.html"><code>LrTasks</code></a> namespace. In most
 -- cases, you should not need to start your own task within this function.</p>
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @name TreeSyncPublish.reparentPublishedCollection
	-- @class function
	-- @param publishSettings (table) The settings for this publish service, as specified
		-- by the user in the Publish Manager dialog. Any changes that you make in
		-- this table do not persist beyond the scope of this function call.
	-- @param info (table) A table with these fields:
	 -- <ul>
	  -- <li><b>isDefaultCollection</b>: (Boolean) True if this is the default collection.</li>
	  -- <li><b>name</b>: (string) The new name being assigned to this collection.</li>
		-- <li><b>parents</b>: (table) An array of information about parents of this collection, in which each element contains:
			-- <ul>
				-- <li><b>localCollectionId</b>: (number) The local collection ID.</li>
				-- <li><b>name</b>: (string) Name of the collection set.</li>
				-- <li><b>remoteCollectionId</b>: (number or string) The remote collection ID assigned by the server.</li>
			-- </ul> </li>
 	  -- <li><b>publishService</b>: (<a href="LrPublishService.html"><code>LrPublishService</code></a>)
	  -- 	The publish service object.</li>
	  -- <li><b>publishedCollection</b>: (<a href="LrPublishedCollection.html"><code>LrPublishedCollection</code></a>
		-- or <a href="LrPublishedCollectionSet.html"><code>LrPublishedCollectionSet</code></a>)
	  -- 	The published collection object being renamed.</li>
	  -- <li><b>remoteId</b>: (string or number) The ID for this published collection
	  -- 	that was stored via <a href="LrExportSession.html#exportSession:recordRemoteCollectionId"><code>exportSession:recordRemoteCollectionId</code></a></li>
	  -- <li><b>remoteUrl</b>: (optional, string) The URL, if any, that was recorded for the published collection via
	  -- <a href="LrExportSession.html#exportSession:recordRemoteCollectionUrl"><code>exportSession:recordRemoteCollectionUrl</code></a>.</li>
	 -- </ul>

--[[ Not used for Flickr plug-in.

function TreeSyncPublish.reparentPublishedCollection( publishSettings, info )
end

--]]

-------------------------------------------------------------------------------
--- This plug-in callback function is called when the user has deleted a
 -- published collection via the Publish Services panel user interface. This is
 -- your plug-in's opportunity to make the corresponding change on the service.
 -- <p>If your plug-in is unable to update the remote service for any reason,
 -- you should throw a Lua error from this function; this causes Lightroom to revert the change.</p>
 -- <p>This is not a blocking call. It is called from within a task created
 -- using the <a href="LrTasks.html"><code>LrTasks</code></a> namespace. In most
 -- cases, you should not need to start your own task within this function.</p>
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @name TreeSyncPublish.deletePublishedCollection
	-- @class function
	-- @param publishSettings (table) The settings for this publish service, as specified
		-- by the user in the Publish Manager dialog. Any changes that you make in
		-- this table do not persist beyond the scope of this function call.
	-- @param info (table) A table with these fields:
	 -- <ul>
	  -- <li><b>isDefaultCollection</b>: (Boolean) True if this is the default collection.</li>
	  -- <li><b>name</b>: (string) The new name being assigned to this collection.</li>
		-- <li><b>parents</b>: (table) An array of information about parents of this collection, in which each element contains:
			-- <ul>
				-- <li><b>localCollectionId</b>: (number) The local collection ID.</li>
				-- <li><b>name</b>: (string) Name of the collection set.</li>
				-- <li><b>remoteCollectionId</b>: (number or string) The remote collection ID assigned by the server.</li>
			-- </ul> </li>
 	  -- <li><b>publishService</b>: (<a href="LrPublishService.html"><code>LrPublishService</code></a>)
	  -- 	The publish service object.</li>
	  -- <li><b>publishedCollection</b>: (<a href="LrPublishedCollection.html"><code>LrPublishedCollection</code></a>
		-- or <a href="LrPublishedCollectionSet.html"><code>LrPublishedCollectionSet</code></a>)
	  -- 	The published collection object being renamed.</li>
	  -- <li><b>remoteId</b>: (string or number) The ID for this published collection
	  -- 	that was stored via <a href="LrExportSession.html#exportSession:recordRemoteCollectionId"><code>exportSession:recordRemoteCollectionId</code></a></li>
	  -- <li><b>remoteUrl</b>: (optional, string) The URL, if any, that was recorded for the published collection via
	  -- <a href="LrExportSession.html#exportSession:recordRemoteCollectionUrl"><code>exportSession:recordRemoteCollectionUrl</code></a>.</li>
	 -- </ul>
--[[
function TreeSyncPublish.deletePublishedCollection( publishSettings, info )

	import 'LrFunctionContext'.callWithContext( 'TreeSyncPublish.deletePublishedCollection', function( context )
	
		local progressScope = LrDialogs.showModalProgressDialog {
							title = LOC( "$$$/Flickr/DeletingCollectionAndContents=Deleting photoset ^[^1^]", info.name ),
							functionContext = context }
	
		if info and info.photoIds then
		
			for i, photoId in ipairs( info.photoIds ) do
			
				if progressScope:isCanceled() then break end
			
				progressScope:setPortionComplete( i - 1, #info.photoIds )
				--###FlickrAPI.deletePhoto( publishSettings, { photoId = photoId } )
			
			end
		
		end
	
		if info and info.remoteId then
	
			--###FlickrAPI.deletePhotoset( publishSettings, {
			--					photosetId = info.remoteId,
			--					suppressError = true,
									-- Flickr has probably already deleted the photoset
									-- when the last photo was deleted.
			--				} )
	
		end
			
	end )

end
--]]

--------------------------------------------------------------------------------
--- (optional) This plug-in defined callback function is called (if supplied)  
 -- to retrieve comments from the remote service, for a single collection of photos 
 -- that have been published through this service. This function is called:
  -- <ul>
    -- <li>For every photo in the published collection each time <i>any</i> photo
	-- in the collection is published or re-published.</li>
 	-- <li>When the user clicks the Refresh button in the Library module's Comments panel.</li>
	-- <li>After the user adds a new comment to a photo in the Library module's Comments panel.</li>
  -- </ul>
 -- <p>This function is not called for unpublished photos or collections that do not contain any published photos.</p>
 -- <p>The body of this function should have a loop that looks like this:</p>
	-- <pre>
		-- function TreeSyncPublish.getCommentsFromPublishedCollection( settings, arrayOfPhotoInfo, commentCallback )<br/>
			--<br/>
			-- &nbsp;&nbsp;&nbsp;&nbsp;for i, photoInfo in ipairs( arrayOfPhotoInfo ) do<br/>
				--<br/>
				-- &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;-- Get comments from service.<br/>
				--<br/>
				-- &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;local comments = (depends on your plug-in's service)<br/>
				--<br/>
				-- &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;-- Convert comments to Lightroom's format.<br/>
				--<br/>
				-- &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;local commentList = {}<br/>
				-- &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;for i, comment in ipairs( comments ) do<br/>
					-- &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;table.insert( commentList, {<br/>
						-- &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;commentId = (comment ID, if any, from service),<br/>
						-- &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;commentText = (text of user comment),<br/>
						-- &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;dateCreated = (date comment was created, if available; Cocoa date format),<br/>
						-- &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;username = (user ID, if any, from service),<br/>
						-- &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;realname = (user's actual name, if available),<br/>
						-- &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;url = (URL, if any, for the comment),<br/>
					-- &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;} )<br/>
					--<br/>
				-- &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;end<br/>
				--<br/>
				-- &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;-- Call Lightroom's callback function to register comments.<br/>
				--<br/>
				-- &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;commentCallback { publishedPhoto = photoInfo, comments = commentList }<br/>
			--<br/>
			-- &nbsp;&nbsp;&nbsp;&nbsp;end<br/>
			--<br/>
		-- end
	-- </pre>
 -- <p>This is not a blocking call. It is called from within a task created
 -- using the <a href="LrTasks.html"><code>LrTasks</code></a> namespace. In most
 -- cases, you should not need to start your own task within this function.</p>
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @param publishSettings (table) The settings for this publish service, as specified
		-- by the user in the Publish Manager dialog. Any changes that you make in
		-- this table do not persist beyond the scope of this function call.
	-- @param arrayOfPhotoInfo (table) An array of tables with a member table for each photo.
		-- Each member table has these fields:
		-- <ul>
			-- <li><b>photo</b>: (<a href="LrPhoto.html"><code>LrPhoto</code></a>) The photo object.</li>
			-- <li><b>publishedPhoto</b>: (<a href="LrPublishedPhoto.html"><code>LrPublishedPhoto</code></a>)
			--	The publishing data for that photo.</li>
			-- <li><b>remoteId</b>: (string or number) The remote systems unique identifier
			-- 	for the photo, as previously recorded by the plug-in.</li>
			-- <li><b>url</b>: (string, optional) The URL for the photo, as assigned by the
			--	remote service and previously recorded by the plug-in.</li>
			-- <li><b>commentCount</b>: (number) The number of existing comments
			-- 	for this photo in Lightroom's catalog database.</li>
		-- </ul>
	-- @param commentCallback (function) A callback function that your implementation should call to record
		-- new comments for each photo; see example.
--[[
function TreeSyncPublish.getCommentsFromPublishedCollection( publishSettings, arrayOfPhotoInfo, commentCallback )
    -- ###
end
--]]

--------------------------------------------------------------------------------
--- (optional, string) This plug-in defined property allows you to customize the
 -- name of the viewer-defined ratings that are obtained from the service via
 -- <a href="#TreeSyncPublish.getRatingsFromPublishedCollection"><code>getRatingsFromPublishedCollection</code></a>.
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @name TreeSyncPublish.titleForPhotoRating
	-- @class property
--###ExtendedPublish.titleForPhotoRating = LOC "$$$/Flickr/TitleForPhotoRating=Favorite Count"

--------------------------------------------------------------------------------
--- (optional) This plug-in defined callback function is called (if supplied)
 -- to retrieve ratings from the remote service, for a single collection of photos 
 -- that have been published through this service. This function is called:
  -- <ul>
    -- <li>For every photo in the published collection each time <i>any</i> photo
	-- in the collection is published or re-published.</li>
 	-- <li>When the user clicks the Refresh button in the Library module's Comments panel.</li>
	-- <li>After the user adds a new comment to a photo in the Library module's Comments panel.</li>
  -- </ul>
  -- <p>The body of this function should have a loop that looks like this:</p>
	-- <pre>
		-- function TreeSyncPublish.getRatingsFromPublishedCollection( settings, arrayOfPhotoInfo, ratingCallback )<br/>
			--<br/>
			-- &nbsp;&nbsp;&nbsp;&nbsp;for i, photoInfo in ipairs( arrayOfPhotoInfo ) do<br/>
				--<br/>
				-- &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;-- Get ratings from service.<br/>
				--<br/>
				-- &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;local ratings = (depends on your plug-in's service)<br/>
				-- &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;-- WARNING: The value for ratings must be a single number.<br/>
				-- &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;-- This number is displayed in the Comments panel, but is not<br/>
				-- &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;-- otherwise parsed by Lightroom.<br/>
				--<br/>
				-- &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;-- Call Lightroom's callback function to register rating.<br/>
				--<br/>
				-- &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;ratingCallback { publishedPhoto = photoInfo, rating = rating }<br/>
			--<br/>
			-- &nbsp;&nbsp;&nbsp;&nbsp;end<br/>
			--<br/>
		-- end
	-- </pre>
 -- <p>This is not a blocking call. It is called from within a task created
 -- using the <a href="LrTasks.html"><code>LrTasks</code></a> namespace. In most
 -- cases, you should not need to start your own task within this function.</p>
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @param publishSettings (table) The settings for this publish service, as specified
		-- by the user in the Publish Manager dialog. Any changes that you make in
		-- this table do not persist beyond the scope of this function call.
	-- @param arrayOfPhotoInfo (table) An array of tables with a member table for each photo.
		-- Each member table has these fields:
		-- <ul>
			-- <li><b>photo</b>: (<a href="LrPhoto.html"><code>LrPhoto</code></a>) The photo object.</li>
			-- <li><b>publishedPhoto</b>: (<a href="LrPublishedPhoto.html"><code>LrPublishedPhoto</code></a>)
			--	The publishing data for that photo.</li>
			-- <li><b>remoteId</b>: (string or number) The remote systems unique identifier
			-- 	for the photo, as previously recorded by the plug-in.</li>
			-- <li><b>url</b>: (string, optional) The URL for the photo, as assigned by the
			--	remote service and previously recorded by the plug-in.</li>
		-- </ul>
	-- @param ratingCallback (function) A callback function that your implementation should call to record
		-- new ratings for each photo; see example.
--[[
function TreeSyncPublish.getRatingsFromPublishedCollection( publishSettings, arrayOfPhotoInfo, ratingCallback )
    -- ###
end
--]]

--------------------------------------------------------------------------------
--- (optional) This plug-in defined callback function is called whenever a
 -- published photo is selected in the Library module. Your implementation should
 -- return true if there is a viable connection to the publish service and
 -- comments can be added at this time. If this function is not implemented,
 -- the new comment section of the Comments panel in the Library is left enabled
 -- at all times for photos published by this service. If you implement this function,
 -- it allows you to disable the Comments panel temporarily if, for example,
 -- the connection to your server is down.
 -- <p>This is not a blocking call. It is called from within a task created
 -- using the <a href="LrTasks.html"><code>LrTasks</code></a> namespace. In most
 -- cases, you should not need to start your own task within this function.</p>
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @param publishSettings (table) The settings for this publish service, as specified
		-- by the user in the Publish Manager dialog. Any changes that you make in
		-- this table do not persist beyond the scope of this function call.
	-- @return (Boolean) True if comments can be added at this time.
--[[
function TreeSyncPublish.canAddCommentsToService( publishSettings )
	return false -- ###
end
--]]

--------------------------------------------------------------------------------
--- (optional) This plug-in defined callback function is called when the user adds 
 -- a new comment to a published photo in the Library module's Comments panel. 
 -- Your implementation should publish the comment to the service.
 -- <p>This is not a blocking call. It is called from within a task created
 -- using the <a href="LrTasks.html"><code>LrTasks</code></a> namespace. In most
 -- cases, you should not need to start your own task within this function.</p>
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @param publishSettings (table) The settings for this publish service, as specified
		-- by the user in the Publish Manager dialog. Any changes that you make in
		-- this table do not persist beyond the scope of this function call.
	-- @param remotePhotoId (string or number) The remote ID of the photo as previously assigned
		-- via a call to <code>recordRemotePhotoId()</code>.
	-- @param commentText (string) The text of the new comment.
	-- @return (Boolean) True if comment was successfully added to service.
--[[
function TreeSyncPublish.addCommentToPublishedPhoto( publishSettings, remotePhotoId, commentText )
    return false -- ###
end
--]]



TreeSyncPublish:inherit( FtpPublish )



return TreeSyncPublish

