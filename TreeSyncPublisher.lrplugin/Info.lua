--[[
        Info.lua
--]]

return {
    appName = "TreeSync Publisher",
    shortAppName = "TSP",
    author = "Rob Cole",
    authorsWebsite = "www.robcole.com",
    donateUrl = "http://www.robcole.com/Rob/Donate",
    platforms = { 'Windows', 'Mac' },
    pluginId = "com.robcole.lightroom.TreeSyncPublisher",
    xmlRpcUrl = "http://www.robcole.com/Rob/_common/cfpages/XmlRpc.cfm",
    LrPluginName = "rc TreeSync Publisher",
    LrSdkMinimumVersion = 3.0,
    LrSdkVersion = 5.0,
    LrPluginInfoUrl = "http://www.robcole.com/Rob/ProductsAndServices/TreeSyncPublisherLrPlugin",
    LrPluginInfoProvider = "TreeSyncManager.lua",
    LrToolkitIdentifier = "com.robcole.TreeSyncPublisher",
    LrInitPlugin = "Init.lua",
    LrShutdownPlugin = "Shutdown.lua",
    LrExportServiceProvider = {
        title = "rc TreeSync Publisher",
        file = "TreeSyncPublish.lua",
        builtInPresetsDir = "Export Presets",
    },
    LrMetadataTagsetFactory = "Tagsets.lua",
    VERSION = { display = "11.0    Build: 2014-09-26 14:56:44" },
}
