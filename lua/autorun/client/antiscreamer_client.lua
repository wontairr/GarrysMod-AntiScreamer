print("Anti-Screamer: Client Loaded")

-- 🚨 vvv CHANGE THESE vvv 🚨 --
// YOU MUST NOT REMOVE THE QUOTES \\

-- Change this to the filename this script is in.
local fileName                  = "antiscreamer_client.lua"
-- You need to change the name of this to something unique and make sure it ends with .txt
local ignoreListFileName        = "IGNORELISTFILENAME_CHANGEME"
-- You need to change the name of this to something unique.
local thinkHookName             = "AntiScreamer_Think_"
-- This command opens the stack viewer
local StackViewerConsoleCommand = "antiscreamer_stackviewer"

//\\ YOU MUST NOT REMOVE THE QUOTES //
-- 🚨 ^^^ CHANGE ABOVE ^^^ 🚨 --

local function genRandomString()
    local letters = "abcdefghijklmnopqrstuvwxyz"
    local randomString = ""
    for i = 1, 16 do
        local index = math.random(1, #letters)
        randomString = randomString .. letters:sub(index, index)
    end
    return randomString
end

thinkHookName = thinkHookName .. genRandomString()

local isWorkshop = string.find(debug.getinfo(1,"S").short_src,"addons/") != 1

local date = os.date("*t",os.time())

local mods              = engine.GetAddons()
local ignoreList        = {}


// Read ignore list (GITHUB DOWNLOAD ONLY)
if ignoreListFileName != "IGNORELISTFILENAME_CHANGEME" and !isWorkshop then
    print("Anti-Screamer: Reading Ignore List... (".. ignoreListFileName ..")")
    local readList = file.Read(ignoreListFileName,"DATA")
    if readList != nil and #readList > 1 then
        ignoreList = util.JSONToTable(readList,false,true)
        print("Anti-Screamer: Ignore List read successfully!")
    else
        print("Anti-Screamer: FAILED to read Ignore List!")
    end
end

// Only includes titles
local lastUpdatedMods   = {}

local modListMaxDays    = 16

// lazy fill of lastupdatedmods
timer.Simple(0,function()
    for _,mod in ipairs(mods) do
        if !mod.mounted then continue end
        local diffInSeconds = os.time() - mod.updated
        local daysAgo = math.floor(diffInSeconds / (24 * 60 * 60))
        if daysAgo > modListMaxDays then continue end
        
        table.insert(lastUpdatedMods,mod.title)
    end
end)


local enabled = true

local suspiciousArgs = {
    [ScrW()] = true,
    [ScrH()] = true,
}
local fileBlackList = {
    ["777.lua"]                         = true,
    ["bigmoney.lua"]                    = true,
    ["bigwinatreltscasinio777.lua"]     = true,
    ["woodingcam.lua"]                  = true,
    ["screamer.lua"]                    = true
}

local functionsToOverride = {
    ["Surface"] = 
    {
        "DrawTexturedRect",
        "DrawTexturedRectRotated",
        "DrawTexturedRectUV",
        "DrawPoly",
        "DrawRect",
        "DrawOutlinedRect",
        "PlaySound",
        "SetMaterial",
        "SetTexture",
    },
    ["Render"] = 
    {
        "DrawTextureToScreen",
        "DrawTextureToScreenRect",
        "DrawScreenQuad",
        "DrawScreenQuadEx",
    },
    ["Draw"] = {
        "TexturedQuad",
    },
    ["Sound"] = 
    {
        "Play",
        "PlayFile",
        "PlayURL"
    },
    ["Debug"] = 
    {
        "getinfo"
    },
    ["File"]  =
    {
      "Write",
      "Delete",  
      "Rename",
      "Append"
    },
    ["Global"] = 
    {
        "EmitSound",
        "CreateSound"
    }
}

local originalFuncs = {
    ["Surface"]     = {},
    ["Render"]      = {},
    ["Draw"]        = {},
    ["Sound"]       = {},
    ["Debug"]       = {},
    ["File"]        = {},
    ["Global"]      = {}
}

// Fill original functions for later restoration and use
for _,funcName in ipairs(functionsToOverride["Surface"]) do
    originalFuncs["Surface"][funcName] = surface[funcName]
end
for _,funcName in ipairs(functionsToOverride["Render"]) do
    originalFuncs["Render"][funcName] = render[funcName]
end
for _,funcName in ipairs(functionsToOverride["Draw"]) do
    originalFuncs["Draw"][funcName] = draw[funcName]
end
for _,funcName in ipairs(functionsToOverride["Sound"]) do
    originalFuncs["Sound"][funcName] = sound[funcName]
end
for _,funcName in ipairs(functionsToOverride["Global"]) do
    originalFuncs["Global"][funcName] = _G[funcName]
end
for _,funcName in ipairs(functionsToOverride["Debug"]) do
    originalFuncs["Debug"][funcName] = debug[funcName]
end
for _,funcName in ipairs(functionsToOverride["File"]) do
    originalFuncs["File"][funcName] = file[funcName]
end

// Holds data about functions that were ran.
local stack = {

}

// How long until a stack item is deleted
local stackDeleteDelay = 10

local function AntiScreamer_AddToStack(info,funcName,argsIn,originalFunction)
    local source      = info.source or "Unknown Source"


    local returnOriginalFunction = false 
    returnOriginalFunction =  string.find(source,fileName) 
    or string.find(source,"@lua/derma") 
    or string.find(source,"@lua/vgui") 
    or string.find(source,"@lua/skins/default")

    if returnOriginalFunction then 
        return originalFunction(unpack(argsIn)) 
    end
    
    local shortSource = info.short_src or "Unknown Short Source"
    local fileName = string.GetFileFromFilename(shortSource)
    if ignoreList[shortSource] then return nil end
    
    local foundAddonName = nil

    for _,mod in ipairs(lastUpdatedMods) do
        if file.Exists(shortSource,mod) then
            foundAddonName = mod
        end
    end
    
    local identifier = util.SHA256(source .. funcName)

    if not stack[funcName] then
        stack[funcName] = {}
    end

    local sus = {"",""}

    if stack[funcName][identifier] then
        if CurTime() - stack[funcName][identifier].time <= 0.25 then
            sus = {"Possibly Suspicious","This addon is running this function constantly, likely in a hook or loop."}
        end
        if fileBlackList[fileName] or string.find(shortSource,"screamer") != nil then
            sus = {"Blacklisted Files Detected",
            "This lua file ( " .. fileName ..  ") calling the function is in the blacklist, very likely a screamer!"}
        end
    end

    if funcName == "SetTexture" then
        argsIn[1] = "[TexID: " .. argsIn[1] .. "] " .. surface.GetTextureNameByID(argsIn[1])
    end

    stack[funcName][identifier]  =     {
        args        = argsIn,
        source      = source, 
        shortSource = shortSource, 
        time        = CurTime(),
        suspicious  = sus,
        addonName   = foundAddonName or nil
    }
    //print("Added to stack:", funcName, identifier)
    //PrintTable(stack)
    return nil
end

local function AntiScreamer_OverrideFunc(funcName,argsIn,originalFunction)
    local debugInfo = originalFuncs.Debug.getinfo(2,"Sn")
    return AntiScreamer_AddToStack(debugInfo,funcName,argsIn,originalFunction)
end
// OVERRIDE
local function AntiScreamer_OverrideBaseFunctions()
    if !enabled then return end
    for _,funcName in ipairs(functionsToOverride.Surface) do
        surface[funcName] = function(...) return AntiScreamer_OverrideFunc(funcName,{...},originalFuncs.Surface[funcName]) end
    end
    for _,funcName in ipairs(functionsToOverride.Render) do
        render[funcName] = function(...) return AntiScreamer_OverrideFunc(funcName,{...},originalFuncs.Render[funcName]) end
    end 
    for _,funcName in ipairs(functionsToOverride.Sound) do
        sound[funcName] = function(...) return AntiScreamer_OverrideFunc(funcName,{...},originalFuncs.Sound[funcName]) end
    end
    for _,funcName in ipairs(functionsToOverride.Draw) do
        draw[funcName] = function(...) return AntiScreamer_OverrideFunc(funcName,{...},originalFuncs.Draw[funcName]) end
    end
    for _,funcName in ipairs(functionsToOverride.Debug) do
        debug[funcName] = function(...) return AntiScreamer_OverrideFunc(funcName,{...},originalFuncs.Debug[funcName]) end
    end
    for _,funcName in ipairs(functionsToOverride.File) do
        file[funcName] = function(...) return AntiScreamer_OverrideFunc(funcName,{...},originalFuncs.File[funcName]) end
    end
    for _,funcName in ipairs(functionsToOverride.Global) do
        _G[funcName] = function(...) return AntiScreamer_OverrideFunc(funcName,{...},originalFuncs.Global[funcName]) end
    end
end
// RETURN TO ORIGINAL
local function AntiScreamer_ResetBaseFunctions()
    timer.Remove(thinkHookName)

    for _,funcName in ipairs(functionsToOverride.Surface) do
        surface[funcName] = originalFuncs.Surface[funcName]
    end
    for _,funcName in ipairs(functionsToOverride.Render) do
        render[funcName] = originalFuncs.Render[funcName]
    end 
    for _,funcName in ipairs(functionsToOverride.Sound) do
        sound[funcName] = originalFuncs.Sound[funcName]
    end
    for _,funcName in ipairs(functionsToOverride.Draw) do
        draw[funcName] = originalFuncs.Draw[funcName]
    end
    for _,funcName in ipairs(functionsToOverride.Debug) do
        debug[funcName] = originalFuncs.Debug[funcName]
    end
    for _,funcName in ipairs(functionsToOverride.File) do
        file[funcName] = originalFuncs.File[funcName]
    end
    for _,funcName in ipairs(functionsToOverride.Global) do
        _G[funcName] = originalFuncs.Global[funcName]
    end
end


local function AntiScreamer_Hook()
    AntiScreamer_OverrideBaseFunctions()
end

local function AntiScreamer_HookExists()
    return timer.Exists(thinkHookName)
end

local function AntiScreamer_AddHook()
    if !enabled then return end
    timer.Create(thinkHookName,0.01,0,AntiScreamer_Hook)
end

local validationTimerName = thinkHookName .. "_validator"
 
local function AntiScreamer_Timer_HookValidator()
    if !enabled then return end
    // Simple timers are undetectable and unchangable (to my knowledge)
    if !timer.Exists(validationTimerName) then timer.Create(validationTimerName,1,0,AntiScreamer_Timer_HookValidator) end
    if AntiScreamer_HookExists() then
        return
    end
    if !enabled then timer.Remove(thinkHookName) return end
    AntiScreamer_Hook()
    AntiScreamer_AddHook()

end


// Creates hook
AntiScreamer_Timer_HookValidator()
// Stops any possible screamer sounds that autorun instantly
timer.Simple(0,function()
    RunConsoleCommand("stopsound")
end)

//
//
-- 🌟🌟 UI Section Start 🌟🌟 
-- 🌟🌟 UI Section Start 🌟🌟
-- 🌟🌟 UI Section Start 🌟🌟
//
//

surface.CreateFont("AntiScreamer_StackFont", {
    font = "Arial",
    size = 18,
    weight = 900,
    antialias = true,
})

//local function Check(bool,ifTrue,ifFalse) if bool then return ifTrue end return ifFalse end end

local nodeCache = {}

// Used to close floating frames that are children of the main frame
local framesToClose = {}

local lastRefreshButtonTime = 0

local function AddNodeSpecial(name,icon,treenode,identifier,remove)
    local node = nil

    if isstring(identifier) then
        if nodeCache[identifier] and !remove then
            node = nodeCache[identifier]
        else
            if remove and nodeCache[identifier] then nodeCache[identifier]:Remove() end
            node = treenode:AddNode(name,icon)
            nodeCache[identifier] = node
        end
    end
    if !IsValid(node) then node = treenode:AddNode(name,icon) end

    if node.Label then
        node.Label:SetFont("AntiScreamer_StackFont")
        node.Label:SetText(name)
    end
    if node.Icon then
        node.Icon:SetSize(19,19)
    end
    return node   
end

local asHelpText = ""
local asHelpText2 = ""

local optionsButtonMenu = function(self) end

local lastStackCount = 0

local frame = nil

local function CreateStackViewer(delayRefresh)
    if IsValid(frame) then return end
    frame = vgui.Create("DFrame")
    frame:SetSize(600,720)
    frame:SetSizable(true)
    frame:Center()
    frame:SetTitle("Anti-Screamer Stack Viewer")
    frame:MakePopup()

    if delayRefresh == nil then delayRefresh = false end

    stackTree = vgui.Create("DTree",frame)
    stackTree.Expand = false
    stackTree.DoRightClick = function(self,node)
        local menu = DermaMenu()
        menu:AddOption("Copy Name",function() SetClipboardText(node:GetText()) end)
        if node.Addon then
            menu:AddOption("Add to Ignore List",function() 
                if isWorkshop then notification.AddLegacy("Feature is Github version only for security reasons! Visit the workshop page to learn more.",NOTIFY_ERROR,6) return end
                notification.AddLegacy(node.Addon .. " added to ignore list. (You may see it's entry for 10 more seconds)",NOTIFY_HINT,6)
                ignoreList[node.Addon] = true
                if IsValid(framesToClose.ignoredModsFrame) then framesToClose.ignoredModsFrame.fillList() end
                stackTree:Clear() nodeCache = {}
                stackTree.RefreshTree() 
                originalFuncs.File.Write(ignoreListFileName,util.TableToJSON(ignoreList,false))
            end)
        end
        menu:Open()
    end

    frame.OnClose = function() 
        nodeCache = {} 
        for _,frame in pairs(framesToClose) do 
            if IsValid(frame) then 
                frame:Close() 
            end 
        end 
        framesToClose = {} 
    end

    ---------------------------------------------------------------
    stackTree:Dock(FILL)

    // Fills the stack tree
    stackTree.RefreshTree = 
    function()
        stackTree:SetLineHeight(35)
        local count = 0
        if #stack != lastStackCount then stackTree:Clear() nodeCache = {} end
        lastStackCount = #stack
        for funcName,funcStack in pairs(stack) do
            count = count + 1
            local node = AddNodeSpecial(funcName,"icon16/application_osx_terminal.png",stackTree, "funcNode_" .. count )
            node.isFuncNode = true
            local count2 = 0
            if !IsValid(node) then continue end

            for identifier,stackInfo in pairs(funcStack) do
                local idTail = "_" .. count .. "_" .. count2
                
                local time      = stackInfo.time or -1
                // remove after delay
                if CurTime() - time >= stackDeleteDelay then 
                    funcStack[identifier] = nil 
                    local nodeName = "addonNode" .. idTail
                    if count > 0 and nodeCache[nodeName] then 
                        nodeCache[nodeName]:Remove() 
                    end 
                    continue 
                end
                count2 = count2 + 1
                local source    = stackInfo.source or "Unknown Source"
                local shortSrc  = stackInfo.shortSource or "Unknown Source"
                local addon     = string.match(source,"addons/(.-)/")
                if addon == nil then
                    local short = stackInfo.addonName or shortSrc
                    if short == shortSrc then shortSrc:sub(5,-1) end
                    addon = short
                end
                local args      = stackInfo.args or {}
                local sus       = stackInfo.suspicious or {"",""}


                // Addon name tree
                local addonNode = AddNodeSpecial("Addon: " .. addon,"icon16/bricks.png",node,"addonNode" .. idTail)
                addonNode.Addon = stackInfo.shortSource
                // Time since it was called
                AddNodeSpecial(string.format("%.1f", CurTime() - time) .. " seconds ago...","icon16/clock.png",addonNode, "time"  .. idTail)
                // The arguments for the function call
                local argsNode = AddNodeSpecial("Arguments","icon16/script_code.png",addonNode,"args" .. idTail,true)
                for _,arg in ipairs(args) do
                    if suspiciousArgs[arg] then sus = {"Suspicious","A suspicious argument was used to run this function: " .. tostring(arg)} end
                    AddNodeSpecial(tostring(arg),"icon16/shape_square.png",argsNode)
                end
                // full source if u want it
                local fullSource = AddNodeSpecial("Full Source","icon16/table.png",addonNode,"fullSource"  .. idTail, true)
     
                local lastNode = fullSource
                local parts = {}
                for part in string.gmatch(source, "[^/]+") do
                    table.insert(parts, 1, part)
                end
                for _, part in ipairs(parts) do
                    lastNode = AddNodeSpecial(part,"icon16/folder.png",lastNode)
                end
                
                node.Label:SetText(funcName .. " (".. sus[1] ..")")
                addonNode.Label:SetText(addonNode.Label:GetValue() .. " (".. sus[1] ..")")
                addonNode:SetTooltip(sus[2])
            end
        end
    end

    if delayRefresh then
        timer.Simple(1.0,function()
            if !IsValid(stackTree) then return end
            stackTree.RefreshTree()
        end)
    else
        stackTree.RefreshTree()
    end
    ---------------------------------------------------------------

    local bottomPanel = vgui.Create("DPanel",frame)
    bottomPanel:Dock(BOTTOM)
    bottomPanel:SetTall(50)

    ---------------------------------------------------------------
    local refreshButton = vgui.Create("DButton",bottomPanel)
    refreshButton:Dock(FILL)
    refreshButton:SetText("Refresh")
    refreshButton.DoClick = function()
        stackTree.RefreshTree()
    end
    ---------------------------------------------------------------
    local expandButton = vgui.Create("DButton",bottomPanel)
    expandButton:SetWide(80)
    expandButton:Dock(LEFT)
    expandButton:DockMargin(5,0,0,0)
    expandButton:SetText("Expand")
    expandButton.DoClick = function() 
        stackTree.Expand = !stackTree.Expand 
        for _,node in pairs(nodeCache) do
            if node.isFuncNode then
                node:ExpandRecurse(stackTree.Expand)        
            end
        end
    end

    ---------------------------------------------------------------
    local clearButton = vgui.Create("DButton",bottomPanel)
    clearButton:SetWide(80)
    clearButton:Dock(LEFT)
    clearButton:DockMargin(2,0,2,0)
    clearButton:SetText("Clear")
    clearButton.DoClick = function()
        stackTree:Clear()  nodeCache = {}
        stackTree.RefreshTree()
    end
    ---------------------------------------------------------------

 
    local autoRefreshCheckBox = vgui.Create("DCheckBoxLabel",bottomPanel)
    local optionsButton       = vgui.Create("DButton",bottomPanel)
    local helpButton = vgui.Create("DButton",bottomPanel)
    helpButton:Dock(RIGHT) helpButton:DockMargin(20,0,5,0)
    helpButton:SetText("Help")
    helpButton.DoClick = function()
        if IsValid(framesToClose.helpFrame) then return end
        ---------------------------------------------------------------
        local helpFrame = vgui.Create("DFrame") framesToClose.helpFrame = helpFrame
        helpFrame:SetTitle("Help")
        helpFrame:SetSize(600,800) 
        helpFrame:Center() helpFrame:SetPos(helpFrame:GetPos() - 150)
        helpFrame:MakePopup()
        ---------------------------------------------------------------

        local whiteBG = vgui.Create("DPanel",helpFrame)
        whiteBG:Dock(FILL)

        ---------------------------------------------------------------
        local helpText = vgui.Create("DLabel",helpFrame)
        helpText:SetSize(600,400)       helpText:SetPos(8,30)
        helpText:SetText(asHelpText)    helpText:SetMultiline(true)
        helpText:SetDark(true)          helpText:SetFont("AntiScreamer_StackFont")
        helpText:SetWrap(true)          helpText:SetContentAlignment(7)
        ---------------------------------------------------------------
        
        ---------------------------------------------------------------
        local helpText2 = vgui.Create("DLabel",helpFrame)
        helpText2:SetPos(8,330)         helpText2:SetSize(600,400)
        helpText2:SetText(asHelpText2)  helpText2:SetMultiline(true)
        helpText2:SetDark(true)         helpText2:SetFont("AntiScreamer_StackFont")
        helpText2:SetWrap(true)         helpText2:SetContentAlignment(7)
        ---------------------------------------------------------------
    end

    ---------------------------------------------------------------
    autoRefreshCheckBox:DockMargin(10,0,20,0)
    autoRefreshCheckBox:SetDark(true)
    autoRefreshCheckBox:Dock(RIGHT)
    autoRefreshCheckBox:SetText("Auto Refresh")
    autoRefreshCheckBox:SetValue(timer.Exists("AntiScreamer_RefreshTimer"))

    
    autoRefreshCheckBox.OnChange = function(self,val)
        if val then
            timer.Create("AntiScreamer_RefreshTimer",0.5,0,function()
                if IsValid(stackTree) then

                    stackTree.RefreshTree()
                else
                    timer.Remove("AntiScreamer_RefreshTimer")
                end
            end)
        else
            timer.Remove("AntiScreamer_RefreshTimer")
        end
        if self:GetValue() == false then timer.Remove("AntiScreamer_RefreshTimer") end
    end
    ---------------------------------------------------------------

    ---------------------------------------------------------------
    optionsButton:Dock(RIGHT)
    optionsButton:DockMargin(0,0,0,0)
    optionsButton:SetText("Options")

    optionsButton.DoClick = optionsButtonMenu
    ---------------------------------------------------------------
    
end

optionsButtonMenu = function(self) 
    if IsValid(framesToClose.optionsFrame) then return end
    local optionsFrame = vgui.Create("DFrame") framesToClose.optionsFrame = optionsFrame
    optionsFrame:SetTitle("Options")
    optionsFrame:SetSize(400,300)
    optionsFrame:Center()
    optionsFrame:SetPos(optionsFrame:GetX() + 200,optionsFrame:GetY() + 70)
    optionsFrame:MakePopup()
    ---------------------------------------------------------------
    

    local optionsList = vgui.Create("DListLayout", optionsFrame)
    optionsList:Dock(FILL)

    ---------------------------------------------------------------
    local enableDisableButton = vgui.Create("DButton",optionsList)
    enableDisableButton:SetColor(enabled and Color(25,160,75) or Color(161,35,62))
    enableDisableButton:SetText(enabled and "Enabled" or "Disabled")
    enableDisableButton.DoClick = function()
        enabled = !enabled
        enableDisableButton:SetText(enabled and "Enabled" or "Disabled")
        enableDisableButton:SetColor(enabled and Color(25,160,75) or Color(161,35,62))
        if enabled then
            AntiScreamer_Timer_HookValidator()
        else
            AntiScreamer_ResetBaseFunctions()
            timer.Remove(validationTimerName)
        end
    end
    ---------------------------------------------------------------

    ---------------------------------------------------------------
    local viewUpdatedMods = vgui.Create("DButton",optionsList)
    viewUpdatedMods:SetText("View Updated Addons")
    viewUpdatedMods.DoClick = function()
        if IsValid(framesToClose.modsFrame) then return end
        ---------------------------------------------------------------
        local modsFrame = vgui.Create("DFrame") framesToClose.modsFrame = modsFrame
        modsFrame:SetTitle("Last Updated Addons")
        modsFrame:SetSize(400,600)
        modsFrame:Center()
        modsFrame:SetPos(optionsFrame:GetPos() + 400)
        modsFrame:MakePopup()
        ---------------------------------------------------------------

        ---------------------------------------------------------------
        local topPanel = vgui.Create("DPanel",modsFrame)
        topPanel:SetPos(0,25)
        topPanel:SetTall(45)
        topPanel:SetWide(400)
        ---------------------------------------------------------------
        
        local maxDays = vgui.Create("DNumberWang",topPanel) 
        maxDays:SetMinMax(0,1500)
        maxDays:SetPos(90,14)
        maxDays:SetValue(modListMaxDays)
        local label = vgui.Create("DLabel",topPanel) label:SetText("Max Days Ago: ") 
        label:SetPos(5,18) label:SizeToContents() label:SetDark(true)
        
        local modsList = nil


        local function fillModsList()
            modsList:Clear()
            lastUpdatedMods = {}
            for _,mod in ipairs(mods) do
                if !mod.mounted then continue end
                local diffInSeconds = os.time() - mod.updated
                local daysAgo = math.floor(diffInSeconds / (24 * 60 * 60))
                if daysAgo > modListMaxDays then continue end
                
                table.insert(lastUpdatedMods,mod.title)

                local modId = tostring(mod.wsid)

                local modButton = modsList:Add("DButton")
                modButton:Dock(TOP)
                modButton:DockMargin( 0, 0, 0, 5 )
                modButton:SetContentAlignment(6)
                modButton:SetText(mod.title .. "\n\n(" .. daysAgo .. " days ago)")
                modButton.DoClick = function()
                    steamworks.ViewFile(mod.wsid)
                end

                local modIcon = vgui.Create("DImage",modButton)
                modIcon:SetPos(40,10)
                local iconMat = nil

                // Get Addon Icon and put it on the mod button.
                steamworks.FileInfo( mod.wsid, function( result )
                    steamworks.Download( result.previewid, true, function( name )
                        iconMat = AddonMaterial( name )
                        if iconMat == nil then
                            iconMat = Material("icon16/bricks.png")
                        end
                        if IsValid(modIcon) then modIcon:SetMaterial(iconMat) end
                        
                    end)
                end)
     
                modIcon:SetSize(60,60)
                modButton:SetTall(80)
            end
        end
        maxDays.OnValueChanged = function(self,val)
            modListMaxDays = math.Clamp(val,0,1500)
            fillModsList()
        end
        modsList = vgui.Create("DScrollPanel", modsFrame)
        modsList:SetPos(0,75)
        modsList:SetTall(520) modsList:SetWide(400)
        fillModsList()

    end
    ---------------------------------------------------------------

    ---------------------------------------------------------------
    local viewIgnoredMods = vgui.Create("DButton",optionsList)
    viewIgnoredMods:SetText("Edit Ignored Script Paths")
    viewIgnoredMods.DoClick = function()
        if IsValid(framesToClose.ignoredModsFrame) then return end
        ---------------------------------------------------------------
        local modsFrame = vgui.Create("DFrame")
        modsFrame:SetTitle("Edit Ignored Script Paths (CLICK TO REMOVE)")
        modsFrame:SetSize(500,500)
        modsFrame:Center()
        modsFrame:SetPos(optionsFrame:GetPos() + 400)
        modsFrame:MakePopup()
        
        local modsList = vgui.Create("DScrollPanel", modsFrame)
        modsList:Dock(FILL)
        local function fillModsList()
            modsList:Clear()
            for path,v in pairs(ignoreList) do
                local button = modsList:Add("DButton")
                button:SetText(path)
                button:Dock( TOP )
                button:DockMargin( 0, 0, 0, 5 )
                button.DoClick = function () 
                    button:Remove() 
                    ignoreList[path] = nil
                    if not string.EndsWith(ignoreListFileName,".txt") or isWorkshop then
                        originalFuncs.File.Write(ignoreListFileName,util.TableToJSON(ignoreList,false))
                    end
                end
            end
        end
        fillModsList()
        modsFrame.fillList = fillModsList
        framesToClose.ignoredModsFrame = modsFrame
        ---------------------------------------------------------------        
    end

    ---------------------------------------------------------------
end

asHelpText = [[
Stack Viewer 101:

Using the stack viewer, you are able to see what drawing/sound functions have been called recently.
The tree starts with function names, then inside are all the addons that are calling that function with extra details.
    
These functions that are watched are not malicious by themselves, but can be used to display/play screamers.

The stack viewer will mark a function (and the addon that calls it) as suspicious if it does the following:

    - Calls the function more than once in a second
    - Uses the screen width or height as an argument

]]
asHelpText2 = [[
Like the functions themselves, these things are not always malicious, but are used by screamers.

It is up to you to determine if a mod is trying to display a screamer. Here are some tips:

    - Investigate the arguments used in the function.
    - Check how recent the addon was updated (Old mods that are updated recently could be suspicious)
    - If an entity mod/weapon mod/etc is calling drawing functions, it could be suspicious (HUD mods for example shouldn't be suspicious, since they rely on these functions)
]]

list.Set( "DesktopWindows", "My Custom Context Menu Icon", {
	title = "Anti-Screamer Stack Viewer",
	icon = "icon64/icon_antiscreamer.png",
	init = function( icon, window )
		CreateStackViewer()
	end
} )

// Remove the "--" from the line below to be able to open the stack viewer with a console command (CHANGE THE CONSOLE COMMAND NAME AT THE TOP)

--concommand.Add(StackViewerConsoleCommand,CreateStackViewer)


// Remove the code below if you don't want it to open on map start.
local function lazyStartupCheck()
    if LocalPlayer() != NULL then
        CreateStackViewer(true)
    else
        timer.Simple(0.1,lazyStartupCheck)
    end
end
lazyStartupCheck()