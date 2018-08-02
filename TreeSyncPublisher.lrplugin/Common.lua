--[[
        Common.lua
        
        Namespace shared by more than one plugin module.
        
        This can be upgraded to be a class if you prefer methods to static functions.
        Its generally not necessary though unless you plan to extend it, or create more
        than one...
--]]


local Common, dbg, dbgf = Object.register( "Common" )



-- get master collection set (and corresponding path) - fresh.
function Common.getMasterCollectionSet( exportSettings )
    local pub = exportSettings['isPubColl']
    local collSetId = exportSettings['collSetId']
    if not collSetId then
        return nil, "No collection set ID"
    end
    local collSet
    if pub then
        local ps = PublishServices:new() -- gimme a fresh one.
        collSet = ps:getCollectionSetByLocalIdentifier( collSetId ) -- auto-initializes (relatively quickly), still: best not to call this more than necessary.
    elseif collSetId == 'LrCatalog' then
        collSet = catalog
    else
        collSet = catalog:getCollectionByLocalIdentifier( collSetId )
    end
    if not collSet then
        return nil, str:fmtx( "Target collection set not found having ID: ^1", collSetId )
    end
    local collPath = collections:getFullCollPath( collSet, app:getPathSep() ) -- as of 28/Jun/2014, handles catalog as coll-set.
    --Debug.pauseIf( collSet==catalog, collPath )
    return collSet, collPath
end




--[[
        Get collection (not folder) leaf-path corresponding to photo (when dest-tree-type is coll).
        Note: the collection leaf-path will ultimately be used to compute a destination folder path, but still: it's a collection path
        that is returned.

        Parameters:
        ----------
        photo: subject photo
        rootPath: dest-path or source-path (sample).
        es is export settings
        o is tsp "export" object, or nil.

        returns leaf-path: path to a collection, computed if unambiguous, else chosen by user from list of possibilities.
        returns root-path: same as incoming, for sampling purposes, or plain exports; adjusted if publishing, so leaf-path will be interpreted relative to TSP publish collection set as root.
        returns coll: collection represented by leaf-path.
--]]
function getCollLeafPath( photo, rootPath, es, o )

    if es.collSetId then
        if not es.collSet or not str:is( es.collSetPath ) then
            local dum, dumr = Common.getMasterCollectionSet( es )
            if dum then -- ok
                es.collSet, es.collSetPath = dum, dumr
            else
                Debug.pause( "no master coll set", es.collSetId )
                return nil, dumr
            end
        else -- already set (hope it's fresh enough)
            --
        end
    else
        Debug.pauseIf( es.collSet or str:is( es.collSetPath ), "coll-set sans id?" )
        return nil, "Master collection set ID is not initialized."
    end

    -- reminder: 'o' is an Elare export/publish object, not a Lr publish-service object.
    local isPubColl = es.isPubColl -- convenience
    local collSetPath = es.collSetPath -- ditto
    local srvName = es.LR_publish_connectionName -- just in case..
    local isSample
    
    -- the main focus:
    local coll
    local leafPath
    
    --local tspSrv
    if o then -- export object - means getting coll/sub-path for actual exporting, as opposed to sampling..
        if o.exportContext then -- this should always be there.
            if es.photosToo then -- auto-mirror collections
                coll = o.exportContext.publishedCollection -- nil if non-publish export
                if coll then -- publishing export
                    assert( str:is( srvName ), "Publish service name is missing." )
                    leafPath = collections:getFullCollPath( coll, app:getPathSep() ) -- full meaning treat publish service as collection set (it stil wont start with a sep).
                    local p1 = collSetPath:find( "/" )
                    if p1 then
                        rootPath = srvName..collSetPath:sub( p1 )
                    else
                        rootPath = srvName
                    end
                    --Debug.pause( leafPath )
                else -- not publishing. usually exporting, but since this is a general purpose method, might also be used for maintenance run etc. - hmm...
                    Debug.pause( "dunno how to get root path in this case, yet." ) -- 
                end
            else -- if not photo matching, even publishing, collection path comes from source hierarchy, not tsp published collection.
                -- say no mo.
            end
        else -- should never happen.
            app:callingError( "Object is missing export context." )
        end
    else -- sample.. (maint-run?)
        if rootPath == es.sourcePath then
            isSample = true
        end
    end
    
    app:callingAssert( isPubColl ~= nil, "is pub coll?" )
    app:callingAssert( str:is( collSetPath ), "no coll set path" )

    --coll = nil -- ### to force coll finding logic for test purposes.    
    if not coll then -- not root-path either; this happens if it's not an export/publish context (e.g. sample photo, maint run..), or it's an export (not publish) context.
        -- the idea here is to try to find the proper collection for said photo, which unfortunately, will not always be correct (I'm trying..).
        local colls
        if isPubColl then -- mirroring published collection
            if es.smartCollsToo then
                if es.pubSrvs == nil then -- slow - make sure this is only done once per export.
                    es.pubSrvs = PublishServices:new()
                    app:pcall{ name="init", progress={ modal=true }, function( call )
                        es.pubSrvs:init( call ) -- note: this MUST include info for foreign plugins too.
                    end }
                -- else already done for this export.
                end
                local info = es.pubSrvs:getInfoForPhoto( photo ) -- includes smart collections - NOT just for this plugin.
                if info then -- pub info gotten for photo
                    colls = tab:createArray( info.pubCollSet ) -- includes smart collections.
                else
                    Debug.pause( "no publishing info for photo (are you sure it's publishded?)" )
                    return nil, "no publishing info for photo (are you sure it's publishded?)"
                end
            else
                colls = photo:getContainedPublishedCollections() -- excludes smart collections.
            end
        else
            colls = photo:getContainedCollections()
            if es.smartCollsToo then
                local smartColls
                smartColls = cat:getSmartColls( photo, es.collSet ) -- slow the first time, then faster: room for additional performance enhancement.
                tab:appendArray( colls, smartColls ) -- hopefully not more than 5-10 of these, if hundreds+ then this will be slow re-doing for every photo. ###3
            end
        end
        if not tab:isArray( colls ) then
            Debug.pause( "Photo is not published via any of the specified type of collections." )
            return nil, "Photo is not published via any of the specified type of collections."
        end
        local colls2 = {}
        local colls2s = {}
        for i, v in ipairs( colls ) do -- consider all collections the photo is in.
            local fcp = collections:getFullCollPath( v, app:getPathSep() ) -- "full" meaning "treat publish service as collection set" - it still won't start with a sep.
            if es.collSet == catalog or str:isBeginningWith( fcp, collSetPath ) then -- if mirroring catalog, then all gathered photo colls are game, otherwise limit to those in specified set.
                colls2[#colls2 + 1] = { title=fcp, value=v }
                colls2s[v] = true
            else
                Debug.pause( "Coll not relevant", fcp, collSetPath )
            end
        end
        if #colls == 0 then
            return nil, "photo not in any relevant collection(s)"
        elseif #colls2 == 1 then -- photo is in exactly one relevant collection - not ambiguous.
            coll = colls2[1].value
            app:logV( "Photo was in only one relevant collection." ) 
        else -- more than one
            assert( #colls2 > 1, "negative? (fractional??)" )
            local colls3
            for i, src in ipairs( catalog:getActiveSources() ) do
                if cat:getSourceType( src ):sub( -3 ) == 'ion' then -- collection
                    if colls2s[src] then -- selected collection is one that subject photo is in
                        if coll then -- ambiguous
                            if colls3 == nil then
                                colls3 = { { title=collections:getFullCollPath( coll, app:getPathSep() ), value=coll } }
                            end
                            colls3[#colls3 + 1] = { title=collections:getFullCollPath( src, app:getPathSep() ), value=src }
                        else
                            coll = src
                        end
                    -- else ignore selected collections which don't include subject photo
                    end
                -- else ignore non-collection sources
                end
            end
            if not coll then
                local colls = colls3 or colls2 -- take set whiddled down by collection selection, or all potential collections.
                if isSample then
                    coll = colls[1].value -- pick an arbitrary value for sampling
                    app:logV( "Picked an arbitrary collection for sampling purpose." )
                else
                    coll = dia:getPopupMenuSelection {
                        title = str:fmtx( "There are multiple collection possibilities for ^1", photo:getRawMetadata( 'path' ) ),
                        subtitle = str:fmtx( "Select intended collection" ),
                        items = colls,
                        --props = prefs,
                        --propName = app:getPrefKey( 'camCalProfile', modelTitle ),
                        --actionPrefKey = str:fmtx( "Select cam-cal profile for ^1", modelTitle ),
                    }
                    if coll then
                        app:logV( "User chose intended collection." )
                        -- if you want to export the same photo with a multitude of coll paths, then you have to do it multiple times, and choose a different one each time.
                        -- Don't like it? turn on coll mirroring and publish your photos instead.
                    else
                        return nil, "User opted out of choosing collection, thus it remains ambiguous.."
                    end
                end
            -- else user has a collection selected which was used to resolve ambiguity.
            end
        end                    
        if coll then
            leafPath = collections:getFullCollPath( coll, app:getPathSep() )
        else
            Debug.pause( "no coll" )
            return nil, "No eligible collections found."
        end
    end
    if leafPath then
        assert( coll, "no coll" ) -- sanity check: sub-path should be computed based on a collection (coll).
    else
        assert( rootPath, "no errm" )
    end
    return leafPath, rootPath, coll
end



                      
--[[
        Returns the part of leaf-path that follows the root-path prefix, or at least that's what it did when it only served folder paths.
        It's more complicated than that now, since it also serves collection paths, but it's still conceptually the same in either case.

        Useful for translating path from source to target tree, and vice-versa.
        
        *** Applies to BOTH folders and collections (dest-tree-type) and even flat, somewhat unexpectedly (source-path still checked to assure photo is in scope).

        Parameters:
        -----------
        rootPath: either publish-settings.dest-path (exporting), or export-params.source-path (e.g. source sampling), I guess it's never nil - not sure.
        leafPath: Complete path to photo/file, or folder, in destination space (exporting), or maybe source space (sampling).
            -- may be overwritten with re-computed value, if dest tree type is 'coll'.
        addl: subfolder in destination tree, e.g. child or sibling.
        photo: photo
        es: export settings
        o: export object, if called in export context, else nil.

        nil => leaf-path not in root-path tree, or else path formats are not normalized.
        
        Also returns collection-or-folder photo-source object.
--]]
function Common.getSubPath( rootPath, leafPath, addl, photo, es, o )
    local errMsg
    local tempSubPath
    local coll
    if es.destTreeType == 'coll' then
        leafPath, rootPath, coll = getCollLeafPath( photo, rootPath, es, o ) -- caches master-coll-set values for future reference, so if you need to assure freshness, clear before calling.
        if not leafPath then
            --Debug.pause( "no leaf path" ) - common: means photo being exported is outside of mirrored hierarchy.
            assert( rootPath, "no errm" )
            return nil, rootPath
        end
    elseif es.destTreeType == 'folder' then 
        app:callingAssert( str:is( rootPath ), "root path is missing" ) -- this can happen when initiating maint pub photos from manager. ###4 (can't recreate).
    else
        app:assert( es.destTreeType == 'flat', "?" )
    end
    local pos
    if str:is( rootPath ) then
        tempSubPath = leafPath:sub( rootPath:len() + 1 )
        pos = leafPath:find( rootPath, 1, true ) -- true => plain text. note: should be fast if *will* be found in first position, which it usually is.
    else
        tempSubPath = leafPath
        pos = 1
    end
    if pos == 1 then  -- leaf path begins with root path
        local collOrFldr
        if es.destTreeType ~= 'coll' then -- folder or flat.
            local fp = LrPathUtils.parent( photo:getRawMetadata( 'path' ) )         -- reminder: this is not used for computing sub-path.
            collOrFldr = cat:getFolderByPath( fp )
        else
            collOrFldr = coll
        end
        if str:is( addl ) then -- subfolder in destination.
            return LrPathUtils.standardizePath( LrPathUtils.child( tempSubPath, addl ) ), errMsg or collOrFldr
        else
            return tempSubPath, errMsg or collOrFldr
        end
    else
        Debug.pause( "path not child", pos, leafPath, rootPath )
        return nil, "leaf-path not in root-path tree, or else path formats are not normalized"
    end
end




-- would be more efficient to build in pieces, then assemble once, but this'll do...
--
function Common.insertVirtualCopyName( filename, props, photo, cache )
    local virt = lrMeta:getRaw( photo, 'isVirtualCopy', cache )
    if virt then
        local cn = lrMeta:getFmt( photo, 'copyName', cache )
        if str:is( cn ) then
            local tmpl = props.copyNameTemplate
            if str:is( tmpl ) then
                local new, n = tmpl:gsub( "{copy_name}", cn )
                if n == 0 then
                    app:logW( "Filename template not changed by copy-name insertion - probably an invalid virtual copy name, or there is a bug in this plugin." )
                end
                local newer = LrPathUtils.addExtension( LrPathUtils.removeExtension( filename ) .. new, LrPathUtils.extension( filename ) ) -- suffix the base name.
                return newer
            else
                app:error( "bad template" )
            end
        else
            app:error( "Virtual copy name can not be blank." )
        end
    else
        return filename -- no change
    end
end



-- used by get-dest-photo-path (which is somewhatofa misnomer, since it's really an exported file path - granted, it is "tied" to source photo).
function Common.getSourceBasedFileName( sourceFileName, destExtension )
    local destFileName = LrPathUtils.replaceExtension( sourceFileName, destExtension )
    return destFileName
end



--  get destination file path based on pub ID.
--
--  if tree-structured export, this amounts to removing the UUID suffix.
--  if flat export, this amounts to combining the filename (as child) with current value for dest-path (as parent).
--
--  returns path, msg
--
function Common.getDestPathFromPublishedId( id, settings )

    if settings == nil then
        app:callingError( "Must pass settings")
    end

    if settings.destTreeType == nil then -- this *may* be possible if user exports with an obsolete preset.
        app:callingError( "Must pass settings with dest-tree-type - to remedy: update your export preset, or re-save your publish settings.")
    end

    if not str:is( id ) then
        return nil, "No ID"
    end
    
    local dp = LrPathUtils.removeExtension( id ) -- extension is uuid, and base is dest-path.
    
    if str:is( dp ) then
        if LrPathUtils.isAbsolute( dp ) and str:is( LrPathUtils.extension( dp ) ) then -- needs to be an absolute path that points to a file having a "proper" extension.
            return dp -- correct in case of folder or flat (collection too I guess, or would know by now..).
        else
            return nil, "Bad ID: " .. id
        end
    else
        return nil, "Invalid ID: " .. id
    end
        

end



-- pub-coll-set is master-coll-set (a publish collection set).
-- to be clear order info is updated for all photos in all collections of mirrored set.
function Common.autoOrder( call, pubCollSet, es, pubSrvs )
    local saveEditFlags = {}
    local s, m = app:pcall{ name="Common_autoOrder", function( icall )
        assert( pubCollSet and pubCollSet.localIdentifier, "no coll-set or ID" )
        local sco
        if es.smartCollsToo then
            sco = SmartCollections:new{ noInit=true } -- quick
        end
        local function autoOrderColl( coll )
            app:log( "Considering order in collection: ^1", coll:getName() )
            local setEditFlags = {}
            if coll:isSmartCollection() then
                if es.smartCollsToo then
                    --tab:appendArray( photos, sco:getPhotos( coll, nil ) ) -- default options
                    local photos = sco:getPhotos( coll, nil )
                    for i, p in ipairs( photos ) do
                        -- @return table with pubPhotos, pubSrvSet, pubCollSet, or nil if photo not published.
                        local info = pubSrvs:getInfoForPhoto( p )
                        if info then
                            for i, pp in ipairs( info.pubPhotos ) do
                                local ppi = pubSrvs:getInfoForPubPhoto( pp ) -- srv-info & pub-coll
                                if ppi.pubColl == coll then -- same pub-coll as target of consideration.
                                    saveEditFlags[pp] = pp:getEditedFlag()
                                    setEditFlags[pp] = true
                                else
                                    -- different publish-coll - ignore.
                                end
                            end
                        else
                            Debug.pause( "not published ??" )
                        end                        
                    end
                else
                    app:logV( "Ignoring photos from smart collection: ^1", coll:getName() )
                end
            else
                --tab:appendArray( photos, coll:getPhotos() )
                local pubPhotos = coll:getPublishedPhotos()
                for i, pp in ipairs( pubPhotos ) do
                    saveEditFlags[pp] = pp:getEditedFlag()
                    setEditFlags[pp] = true
                end
            end
            if tab:is( setEditFlags ) then -- pub'd photos to-do
                local s, m = cat:update( 30, "Update Edit Flags (temporarily) for Ordering", function( context, phase )
                    for pp, _t in pairs( setEditFlags ) do
                        pp:setEditedFlag( true )
                    end
                end )
                if s then
                    app:log( "Edit flags set for ordering - doing mock publish." )
                    fprops:setPropertyForPlugin( _PLUGIN, 'pseudoExportForSortOrdering', coll.localIdentifier ) -- readable by sort-order filter.
                    local published
                    coll:publishNow( function()
                        published = true    
                    end )
                    app:sleep( math.huge, 1, function( et )
                        return published
                    end )
                else
                    app:logE( m )
                end
            else -- not published via this coll
                -- Debug.pause( "?" )
            end
        end
        local function autoOrderCollSet( collSet )
            for i, coll in ipairs( collSet:getChildCollections() ) do
                autoOrderColl( coll )
            end
            for i, set in ipairs( collSet:getChildCollectionSets() ) do
                autoOrderCollSet( set )
            end
        end
        autoOrderCollSet( pubCollSet )
    end, finale=function( icall )
        fprops:setPropertyForPlugin( _PLUGIN, 'pseudoExportForSortOrdering', false )
        if tab:is( saveEditFlags ) then
            local s, m = cat:update( 30, "Restore Published Status", function( context, phase )
                for pp, flag in pairs( saveEditFlags ) do
                    pp:setEditedFlag( flag )    
                end
            end )
            if s then
                app:log( "Restored publish status after ordering pseudo-publish run." )
            else
                app:logE( "Unable to restore publish status after ordering pseudo-publish run - ^1", m )
            end
        else
            app:logV( "No edit flags to restore." )
        end        
    end }
    return s, m
end



-- ###3 - consider making common method, and compare to dup/sync-set method in collection agent plugin.
-- returns nErrors, colls, stats
function syncCollSet( srcSet, destSet, smartCollsToo )
    local nErrors = app:getErrorCount()
    local colls = {} -- to publish
    local nCollAdded = 0
    local nCollRemoved = 0
    local nCollModified = 0
    local nCollTotal = 0
    local nCollSame = 0
    local nCollSetAdded = 0
    local nCollSetRemoved = 0
    local nCollSetTotal = 0
    local function syncColl( fromColl, toSet, toLookup, toLookup2 )
        local collPhotos = fromColl:getPhotos()
        local collName = fromColl:getName()
        local isSmart = fromColl:isSmartCollection()
        if isSmart then
            app:log( "Syncing smart collection: ^1", collName )
        else
            app:log( "Syncing non-smart collection: ^1", collName )
        end
        local searchDescr = isSmart and fromColl:getSearchDescription()
        local toColl = toLookup[collName]
        if not toColl then
            if #collPhotos > 0 then -- empty source collection.
                local s, m -- reminder: because coll-set is matching coll-set, there is less complexity as when coll-set emulating folder hierarchy, so logic here is simpler..
                if toLookup2[collName] then -- there is a set where a collection needs to be - kill the set.
                    s, m = cat:update( 20, "Remove collection set", function()
                        toLookup2[collName]:delete()
                        toLookup2[collName] = nil
                    end )
                else
                    s = true
                end
                if s then   
                    s, m = cat:update( 20, "Create collection "..collName, function( context, phase )
                        if phase == 1 then
                            if searchDescr then
                                toColl = destSet:createPublishedSmartCollection( collName, searchDescr, toSet, false )
                                return true -- done.
                            else
                                toColl = destSet:createPublishedCollection( collName, toSet, false ) -- no need to return pre-existing, since checking being done externally.
                                if toColl then
                                    return false -- not done - continue..
                                else
                                    return true -- done (same as returning nil).
                                end
                            end
                        elseif phase == 2 then
                            toColl:addPhotos( collPhotos )
                        else
                            error( "cat upd phase snafu" )
                        end
                    end )
                end 
                if s then
                    if toColl then
                        app:log( "Created collection: '^1' in '^2'", collName, cat:getSourceName( toSet ) )
                        colls[toColl] = destSet
                        nCollAdded = nCollAdded + 1
                        nCollTotal = nCollTotal + 1
                        toLookup[collName] = toColl
                    else
                        app:logE( "Unable to create collection: '^1' in '^2'", collName, cat:getSourceName( toSet ) )
                    end
                else
                    app:logE( m )
                end
            else
                app:logV( "Not syncing empty collections - if you want the empties too, do tell.." )
            end
        else -- to-coll already exists.
            nCollTotal = nCollTotal + 1 -- independent of errors setting search descriptor, or photos..
            if isSmart then -- *from* coll is smart.
                if not toColl:isSmartCollection() then -- must convert regular collection to smart collection.
                    local s, m = cat:update( 20, "Convert collection to smart", function()
                        if phase == 1 then
                            toColl:delete()
                            toColl = nil
                            nCollRemoved = nCollRemoved + 1 -- arguable that coll was removed, since it will be added right back, but I think this is justified..
                            toLookup[collName] = nil
                            return false
                        else
                            toColl = destSet:createPublishedSmartCollection( collName, searchDescr, toSet, false )
                            nCollAdded = nCollAdded + 1 -- conversion will result in 1-removed, 1-added, *and* 1-modified - seems strange, but I think it's OK.
                            toLookup[collName] = toColl
                            return true -- same as returning nil.
                        end
                    end )
                    if s then
                        if toColl then
                            app:log( "Converted regular collection to smart." )
                            nCollModified = nCollModified + 1
                            colls[toColl] = destSet
                        else
                            app:logE( "Unable to convert collection to smart." )
                        end
                    else
                        app:logE( m )
                    end
                else -- to-coll is smart (and so is from coll).
                    local currDescr = toColl:getSearchDescription()
                    if tab:isEquivalent( currDescr, searchDescr ) then
                        app:log( "Search descr is equivalent." )
                    else
                        local s, m = cat:update( 20, "Update search description", function()
                            toColl:setSearchDescription( searchDescr )
                        end )
                        if s then
                            app:log( "Search description updated." )
                            colls[toColl] = destSet
                            nCollModified = nCollModified + 1
                        else
                            app:logE( m )
                        end
                    end
                end
            else -- *from* coll is non-smart.
                if toColl:isSmartCollection() then -- to-coll is smart
                    local s, m = cat:update( 20, "Convert smart collection to non-smart.", function()
                        if phase == 1 then
                            toColl:delete()
                            toColl = nil
                            nCollRemoved = nCollRemoved + 1
                            toLookup[collName] = nil
                            return false
                        else
                            toColl = destSet:createPublishedCollection( collName, toSet, false )
                            nCollAdded = nCollAdded + 1
                            toLookup[collName] = toColl
                            return true -- same as returning nil.
                        end
                    end )
                    if s then
                        app:log( "Converted smart collection to non-smart." )
                        colls[toColl] = destSet
                        nCollModified = nCollModified + 1
                    else
                        app:logE( m )
                    end
                end
                local status, nAdded, nRemoved = LrTasks.pcall( cat.setCollectionPhotos, cat, toColl, collPhotos, 20 ) -- auto-wrapped, throws error if problem.
                if status then
                    if nAdded > 0 or nRemoved > 0 then
                        nCollModified = nCollModified + 1
                        if nAdded > 0 then
                            app:log( "Added ^1 to collection", nAdded )
                        end
                        if nRemoved > 0 then
                            app:log( "Removed ^1 from collection", nAdded )
                        end
                        colls[toColl] = destSet -- note modified collection ripe for re-publishing.
                    else
                        nCollSame = nCollSame + 1
                    end
                else
                    app:logE( nAdded )
                end
            end
        end
    end
    local function syncSet( fromSet, toSet )
        local toChildColls = toSet:getChildCollections() -- array
        local toChildCollsLookup = {}
        for j, c in ipairs( toChildColls ) do
            toChildCollsLookup[c:getName()] = c
        end
        local toChildCollSets = toSet:getChildCollectionSets()
        local toChildCollSetsLookup = {}
        for r, st in ipairs( toChildCollSets ) do
            toChildCollSetsLookup[st:getName()] = st
        end
        for i, v in ipairs( fromSet:getChildCollections() ) do -- breadth first
            syncColl( v, toSet, toChildCollsLookup, toChildCollSetsLookup )
        end
        for i, v in ipairs( fromSet:getChildCollectionSets() ) do -- depth second
            local setName = v:getName()
            local toChildSet = toChildCollSetsLookup[setName]
            if not toChildSet then
                local s, m = cat:update( 30, "Create collection set "..setName, function( context, phase )
                    if phase == 1 then
                        if toChildCollsLookup[setName] then -- there is a coll where a set needs to be.
                            toChildCollsLookup[setName]:delete()
                            toChildCollsLookup[setName] = nil
                            return false -- not deleted until transaction committed.
                        end
                    end
                    -- may be phase 1 (if pre-coll-deletion was required) or phase 2 (if not).
                    toChildSet = destSet:createPublishedCollectionSet( setName, toSet, false )
                end )
                if s then
                    if toChildSet then
                        app:log( "Created collection set." )
                        toChildCollSetsLookup[setName] = toChildSet
                        nCollSetAdded = nCollSetAdded + 1
                    else
                        app:logE( "Unable to create collection set: '^1' in '^2'", setName, cat:getSourceName( toSet ) )
                    end
                else
                    app:logE( m )
                end
            --else it already exists - either way: sync new or already existing, below..
            end
            if toChildSet then
                syncSet( v, toChildSet )
                nCollSetTotal = nCollSetTotal + 1
            end
        end
    end
    local function purgeSet( fromSet, toSet )
        local fromColls = fromSet:getChildCollections()
        local fromCollsLookup = {}
        for j, x in ipairs( fromColls ) do
            fromCollsLookup[x:getName()] = x
        end
        local fromCollSets = fromSet:getChildCollectionSets()
        local fromCollSetsLookup = {}
        for j, x in ipairs( fromCollSets ) do
            fromCollSetsLookup[x:getName()] = x
        end
        local toColls = toSet:getChildCollections()
        local toCollSets = toSet:getChildCollectionSets()
        for i, c in ipairs( toColls ) do
            local collName = c:getName()
            if not fromCollsLookup[collName] then
                local s, m = cat:update( 20, "Delete collection", function()
                    c:delete()
                end )
                if s then
                    app:log( "Deleted collection: ^1", collName )
                    nCollRemoved = nCollRemoved + 1
                else
                    app:logE( m )
                end
            -- else
            end
        end
        for i, c in ipairs( toCollSets ) do
            local fromCollSet = fromCollSetsLookup[c:getName()]
            if not fromCollSet then
                local s, m = cat:update( 20, "Delete collection set", function()
                    c:delete()
                end )
                if s then
                    app:log( "Deleted collection set: ^1", c:getName() )
                    nCollSetRemoved = nCollSetRemoved + 1
                else
                    app:logE( m )
                end
            else -- from collection set exists, but may have child collection and/or sets to cleanup.
                purgeSet( fromCollSet, c )
            end
        end
    end
    assert( destSet, "no dest set" )
    purgeSet( srcSet, destSet ) -- remove extraneous collections & sets (but not photos).
    syncSet( srcSet, destSet ) -- add collections, sets, and add/remove photos in existing collections to match.
    local summary = str:fmtx( "colls+^1, colls-^2, colls*^3, colls~^4, colls(total): ^5; sets+^6, sets-^7, coll-sets(total): ^8",
        nCollAdded,
        nCollRemoved,
        nCollModified,
        nCollSame,
        nCollTotal,
        nCollSetAdded,
        nCollSetRemoved,
        nCollSetTotal
    )
    return app:getErrorCount() - nErrors, colls, summary
end



-- ###3 - consider making common method, and compare to dup/sync-set method in collection agent plugin.
-- returns nErrors (number), colls (key is coll, value is dest-set), stats (string).
function syncFolderHierarchy( srcFolder, destSet, smartCollsToo )
    local nErrors = app:getErrorCount()
    local colls = {} -- to publish
    local nCollAdded = 0
    local nCollRemoved = 0
    local nCollModified = 0
    local nCollTotal = 0
    local nCollSame = 0
    local nCollSetAdded = 0
    local nCollSetRemoved = 0
    local nCollSetTotal = 0
    local function removeObsoleteFolderCollsOrSets( folderName, hasFolders, hasPhotos, toSet, toLookup, toLookup2 )
        local collName = "["..folderName.."]"
        local obsColl
        local obsSet
        if hasFolders then         -- obsolete, if existing:
            --  * collection where set should be.
            --  * child-less collection where child collection should be.
            collName = folderName
            obsColl = toLookup[collName]
            -- set won't be obsolete.
        else                        -- obsolete, if existing:
            --  * set where collection should be.
            --  * child collection where child-less collection should be.
            obsSet = toLookup2[folderName]
        end
        if not hasPhotos then
            obsColl = toLookup[collName]
        end
        if obsColl or obsSet then
            local obsCollName
            local obsSetName
            local s, m = cat:update( 20, "Delete obsolete collection and/or set", function()
                if obsColl then
                    obsCollName = obsColl:getName() -- not be available after deletion.
                    obsColl:delete()
                end
                if obsSet then
                    obsSetName = obsSet:getName() -- not be available after deletion.
                    obsSet:delete()
                end
            end )
            if s then
                if obsColl then
                    app:logV( "Deleted obsolete collection: ^1", obsCollName )
                    toLookup[collName] = nil
                    nCollRemoved = nCollRemoved + 1 -- whether this counts depends on replacement upon return - hmm... ###2
                end
                if obsSet then
                    app:logV( "Deleted obsolete collection set: ^1", obsSetName )
                    toLookup2[folderName] = nil
                    nCollSetRemoved = nCollSetRemoved + 1 -- whether this counts depends on replacement upon return - hmm... ###2
                end
            else
                app:logE( "Unable to delete requisite collection or set." )
                return false
            end
        else
            app:logV( "No obsolete collections or sets to delete." )
        end
        return true -- all good.
    end
    local function syncFolder( fromFolder, toSet, toLookup, toLookup2 )
        local collPhotos = fromFolder:getPhotos( false )
        local folderName = fromFolder:getName()
        local hasFolders = #fromFolder:getChildren() > 0 -- no need to hang on to child folders, just need to know if it has child folders.
        local hasPhotos = #collPhotos > 0
        local collName
        if hasFolders then -- there will need to a set with the same name as folder.
            if hasPhotos then -- there will also need to be a special photo collection.
                collName = "["..folderName.."]"
            -- else no need for a to-coll.
            end
        else
            if hasPhotos then
                collName = folderName
            -- else no need..
            end            
        end
        -- first remove obsolete folders which are no longer needed and might get in the way of what is needed.
        local s, m
        s = removeObsoleteFolderCollsOrSets( folderName, hasFolders, hasPhotos, toSet, toLookup, toLookup2 ) -- no 'm'
        if not s then return end -- no ret val ###2 should it log an error if no can remove-obs..?
        local toColl = collName and toLookup[collName] -- 
        if not toColl then
            if #collPhotos > 0 then -- source collection is empty.
                if s then
                    s, m = cat:update( 20, "Create collection "..collName, function( context, phase )
                        if phase == 1 then
                            toColl = destSet:createPublishedCollection( collName, toSet, false ) -- no need to return pre-existing, since checking being done externally.
                            if toColl then
                                return false -- not done - continue..
                            else
                                return true -- done (same as returning nil).
                            end
                        elseif phase == 2 then
                            toColl:addPhotos( collPhotos )
                        else
                            error( "cat upd phase snafu" )
                        end
                    end ) 
                end
                if s then
                    if toColl then
                        app:log( "Created collection: ^1 (^2 added)", collName, str:pluralize( #collPhotos, "photo" ) )
                        colls[toColl] = destSet
                        nCollAdded = nCollAdded + 1
                        nCollTotal = nCollTotal + 1
                        toLookup[collName] = toColl
                    else
                        app:logE( "Unable to create collection: ^1", collName )
                    end
                else
                    app:logE( m )
                end
            else
                app:log( "*** Not creating empty collections - if you want them too, do tell.." )
            end
        else
            nCollTotal = nCollTotal + 1 -- independent of errors setting search descriptor, or photos..
            local status, nAdded, nRemoved = LrTasks.pcall( cat.setCollectionPhotos, cat, toColl, collPhotos, 20 ) -- auto-wrapped, throws error if problem.
            if status then
                if nAdded > 0 or nRemoved > 0 then
                    nCollModified = nCollModified + 1
                    if nAdded > 0 then
                        app:log( "Added ^1 to collection", nAdded )
                    end
                    if nRemoved > 0 then
                        app:log( "Removed ^1 from collection", nAdded )
                    end
                    colls[toColl] = destSet -- modified collections are particularly ripe for processing.
                else
                    nCollSame = nCollSame + 1
                end
            else
                app:logE( nAdded )
            end
        end
    end
    local function syncFolderSet( fromFolder, toSet )
        local toSetName = cat:getSourceName( toSet )
        app:log( "Syncing from folder '^1' to collection set '^2'", fromFolder:getName(), toSetName )
        local toChildColls = toSet:getChildCollections() -- array
        local toChildCollsLookup = {}
        for j, c in ipairs( toChildColls ) do
            toChildCollsLookup[c:getName()] = c
        end
        local toChildCollSets = toSet:getChildCollectionSets()
        local toChildCollSetsLookup = {}
        for r, st in ipairs( toChildCollSets ) do
            toChildCollSetsLookup[st:getName()] = st
        end
        local childFolders = fromFolder:getChildren()
        for i, v in ipairs( childFolders ) do -- breadth first
            syncFolder( v, toSet, toChildCollsLookup, toChildCollSetsLookup ) -- removes obsolete collections and/or sets
        end
        for i, v in ipairs( childFolders ) do -- depth second
            local setName = v:getName()
            
            if #v:getChildren() > 0 then -- subfolder has children, thus warranting a to collection set.
                local toChildSet = toChildCollSetsLookup[setName]
                if not toChildSet then
                    local s, m = cat:update( 30, "Create collection set "..setName, function( context, phase )
                        toChildSet = destSet:createPublishedCollectionSet( setName, toSet, false )
                    end )
                    if s then
                        if toChildSet then
                            app:log( "Created collection set: '^1' in '^2'.", setName, cat:getSourceName( toSet ) )
                            nCollSetAdded = nCollSetAdded + 1
                            toChildCollSetsLookup[setName] = toChildSet
                        else
                            app:logE( "Unable to create collection set: ^1", setName, cat:getSourceName( toSet ) )
                        end
                    else
                        app:logE( m )
                    end
                --else it already exists - either way: sync new or already existing, below..
                end
                if toChildSet then
                    syncFolderSet( v, toChildSet )
                    nCollSetTotal = nCollSetTotal + 1
                    toChildCollSetsLookup[setName] = toChildSet
                end
            else -- folder has no child folders, so no need for a collection set here.
                app:logV( "Not creating collection set '^1', since it has no child folders", setName )
            end
        end
    end
    local function purgeFolderSet( fromFolder, toSet )
        local fromFolders = fromFolder:getChildren()
        local fromFoldersLookup = {}
        for j, x in ipairs( fromFolders ) do
            fromFoldersLookup[x:getName()] = x
        end
        local toColls = toSet:getChildCollections()
        for i, c in ipairs( toColls ) do
            local collName = c:getName()
            local folderName
            if collName:sub( 1, 1 ) == "[" and collName:sub( -1 ) == "]" then
                folderName = collName:sub( 2, -2 )
            else
                folderName = collName
            end
            local folder = fromFoldersLookup[folderName] -- folder associated with existing collection.
            if folder then
                local hasFolders = #folder:getChildren() > 0
                local hasPhotos = #folder:getPhotos( false ) > 0
                if not hasPhotos then
                    folder = nil -- obsolete collection
                elseif hasFolders then -- and photos
                    if folderName == collName then
                        folder = nil
                    end
                else -- has photos, but not folders
                    if folderName ~= collName then
                        folder = nil
                    end
                end
            end
            if not folder then
                local s, m = cat:update( 20, "Delete collection", function()
                    c:delete()
                end )
                if s then
                    app:log( "Deleted collection: ^1", collName )
                    nCollRemoved = nCollRemoved + 1
                else
                    app:logE( m )
                end
            -- else ok
            end
        end
        local fromCollSets = fromFolder:getChildren()
        local fromCollSetsLookup = {}
        for j, x in ipairs( fromCollSets ) do
            fromCollSetsLookup[x:getName()] = x
        end
        local toCollSets = toSet:getChildCollectionSets()
        for i, c in ipairs( toCollSets ) do
            local setName = c:getName()
            local fromCollSet = fromCollSetsLookup[setName]
            if not fromCollSet then
                local s, m = cat:update( 20, "Delete collection set", function()
                    c:delete()
                end )
                if s then
                    app:log( "Deleted collection set: ^1", seName )
                    nCollSetRemoved = nCollSetRemoved + 1
                else
                    app:logE( m )
                end
            else -- from collection set exists, but may have child collection and/or sets to cleanup.
                purgeFolderSet( fromCollSet, c )
            end
        end
    end
    assert( destSet, "no dest set" )
    purgeFolderSet( srcFolder, destSet ) -- remove extraneous collections & sets (but not photos).
    syncFolderSet( srcFolder, destSet ) -- add collections, sets, and add/remove photos in existing collections to match.
    -- note: n-removed includes conversions, this has been documented on web page.
    local summary = str:fmtx( "colls+^1, colls-^2, colls*^3, colls~^4, colls(total): ^5; sets+^6, sets-^7, coll-sets(total): ^8",
        nCollAdded,
        nCollRemoved,
        nCollModified,
        nCollSame,
        nCollTotal,
        nCollSetAdded,
        nCollSetRemoved,
        nCollSetTotal
    )
    return app:getErrorCount() - nErrors, colls, summary
end



-- sync-photos, meaning: photo-match + auto-order.
-- note: the photo-matching aspect works regardless of coll-set type, but the auto-ordering
-- only works when mirroring a publish service collection set.
-- Sets photos in one TSP collection to the sum of all photos in master collection set.
function Common.syncPhotos( call, photoMatch, autoOrder )

    app:callingAssert( call ~= nil, "call is nil" )
    app:callingAssert( photoMatch ~= nil, "pm is nil" )
    app:callingAssert( autoOrder ~= nil, "ao is nil" )
    local pubSrvs
    local nUpd = 0
    local pubCollSet = {}
    local sco = SmartCollections:new{ noInit=true } -- instant
    local tspSrvs = catalog:getPublishServices( _PLUGIN.id ) -- get TSP services.
    local summary = {} -- summary info, returned to caller - stats table indexed by server name.
    local sortedNotMatched = 0
    -- consider all TSP publish services.
    -- note: although master collection can (will usually) be from a foreign plugin, or native Lr,
    -- all we need is the collection ID (together with fairly quick init) to obtain the master coll set, and then it's photos are
    -- accessed directly (recursively), such that there is no need for the publish services info init.
    for i, tspSrv in ipairs( tspSrvs ) do
        repeat
            local srvName = tspSrv:getName()

            app:log()
            app:log( "Considering tsp publish service: ^1", srvName )
            
            -- first: photo-matching (only applicable if mirroring collection set, whether publish or not).
            -- (could be done second - doesn't matter)
            
            local es = tspSrv:getPublishSettings()["< contents >"] or error( "where's the pub-srv settings?" )
            local doPhotoMatch
            local doAutoOrder
            if photoMatch then
                if es.photosToo then -- user dictated photo-matching.
                    app:logV( "Photo-matching is enabled, so TSP collections will be re-synchronized (potentially modified) to match mirrored set." )
                    doPhotoMatch = true
                else
                    app:logV( "Publish service not configured for photo matching." )
                end
            end
            -- reminder: auto-sort-ordering depends on a mock (native) *publishing* of mirrored collections, which means mirrored set must be a publishing service or set.
            if autoOrder then
                doAutoOrder = es.destTreeType == 'coll' and es.isPubColl and es.assureOrder -- i.e. mirrored set is publish collection and is configured for sort-ordering.
                if not doAutoOrder then
                    app:logV( "Reminder: auto-ordering this way only works if mirroring a publish service collection set, since it depends on a mock publish (with TSO filter inserted)." )
                end
            end
            
            local masterCollSet, mPath
            if es.destTreeType == 'coll' then
                masterCollSet, mPath = Common.getMasterCollectionSet( es ) -- works whether psrv or cat set.
                if masterCollSet then
                    app:logV( "Got master collection set: ^1", mPath )
                else
                    app:logW( "Master collection set not found, ID: ^1", es.collSetId )            
                    break
                end
            end            

            if doPhotoMatch then -- photo matching is a go..
            
                -- photo matching:
                local nErrors, colls, stats
                if es.destTreeType == 'coll' then
                    assert( masterCollSet, "no master coll set" )
                    nErrors, colls, stats = syncCollSet( masterCollSet, tspSrv, es.smartCollsToo ) -- ideally, ordering and matching could be done in the same loop - maybe one day.. ###3.
                elseif es.destTreeType == 'folder' then
                    local srcFolder = cat:getFolderByPath( es.sourcePath, true ) -- bypass cache.
                    if srcFolder then
                        nErrors, colls, stats = syncFolderHierarchy( srcFolder, tspSrv )
                    else
                        app:logE( "No folder for path - invalid source path." )
                    end
                else -- flat
                    assert( es.destTreeType == 'flat' )
                    break
                end
                --Debug.pause( #photos )
                
                -- local s, nAdded, nRemoved = LrTasks.pcall( cat.setCollectionPhotos, cat, photoColl, photos, nil ) -- default tmo.
                -- Debug.pause( s, m, photoColl, #photos )
                if nErrors == 0 then
                    -- v11 (v10 stuff stripped out):
                    summary[srvName] = stats
                    tab:addItems( pubCollSet, colls )
                    nUpd = nUpd + 1
                else
                    --app:logE( "Unable to set to-be-published collection photos (^1) to match those in mirrored collection set: ^2 - ^3", #photos, mPath, nAdded )
                    app:log( "Unable to match coll set in TSP service - errors should have been logged.." )
                end
            -- else no photo matching
            end

            if doAutoOrder then
                assert( es.isPubColl, "oops" )
                local masterPluginId
                if masterCollSet.getService then
                    local ms = masterCollSet:getService()
                    masterPluginId = ms:getPluginId()
                elseif masterCollSet.getPluginId then
                    masterPluginId = masterCollSet:getPluginId()
                else
                    app:logE( "Unable to get master plugin ID." )
                    break
                end
                if pubSrvs == nil then
                    pubSrvs = PublishServices:new() -- quick.
                    pubSrvs:init( call, masterPluginId ) -- slow. ###2 optimize?
                    if call:isQuit() then return end
                end
                -- note: auto-ordering MUST be done to the mirrored collection *source* set, since that's where the photos are ordered correctly.
                local s, m = Common.autoOrder( call, masterCollSet, es, pubSrvs )
                if s then
                    app:logV( "Auto-ordered (ordering info auto-updated)." )
                    if es.assureOrder then -- user dictated sort-ordering
                        local colls = cat:getCollsInCollSet( tspSrv, true ) -- smart-colls too.
                        tab:addItems( pubCollSet, tab:createSet( colls, tspSrv ) ) -- merge colls in with set, if any are new.
                        if summary[srvName] == nil then -- not populated by photo-matching above.
                            summary[srvName] = "Sorted, not photo-matched" -- better stats? ###2
                            sortedNotMatched = sortedNotMatched + 1
                        else -- colls in this srv should be that of photo-matching computed above.
                            --assert( #colls == 1 and colls[1] == photoColl, "hm..." )
                            app:log( "Auto-ordering making for new info (not already existing from photo-matching)." )
                        end
                    else
                        app:logV( "Publish service not configured for sort ordering." )
                    end
                else
                    app:logE( "Not auto-ordered - ^1", m )
                end
            elseif autoOrder and es.assureOrder then
                app:log( "'^1' is not eligible for TSP auto-ordering in this fashion - consider using TSO's auto-ordering feature instead.", srvName )
            -- else mum's the word..
            end
        until true
        
    end -- end-of for each TSP service "defined" (existing).
    
    --local pubColls = tab:createArray( pubCollSet )
    app:log( "^1 updated.", str:pluralize( nUpd, "photo-matching service" ) )
    if sortedNotMatched > 0 then
        app:log( "^1 are ready to be published.", str:pluralize( sortedNotMatched, "additional auto-sort-ordered collection" ) )
    else
        app:logV( "No additional collections auto-(sort)-ordered." )
    end
    return summary, pubCollSet, sortedNotMatched
    --Debug.showLogFile()
end





return Common
