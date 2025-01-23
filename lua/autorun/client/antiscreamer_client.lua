print("Anti-Screamer: Client Loaded")

-- 🚨 vvv CHANGE THESE vvv 🚨 --
// YOU MUST NOT REMOVE THE QUOTES \\

-- Change this to the filename this script is in.
local fileName                  = "antiscreamer_client.lua"

-- You need to change the name of this to something unique and make sure it ends with .txt
local ignoreListFileName        = "IGNORELISTFILENAME_CHANGEME"

-- You need to change the name of this to something unique.
local thinkHookName             = "AntiScreamer_Think_"

-- This command opens the stack viewer (scroll down to the very bottom to uncomment the concommand)
local StackViewerConsoleCommand = "antiscreamer_stackviewer"

-- This command will disable the antiscreamer the next time you start up a map. ofcourse making the mod obsolete but it's useful. (scroll down to the very bottom to uncomment the concommand)
local AntiScreamerDisableCommand = "antiscreamer_changeme"

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
for _,mod in ipairs(mods) do
    if !mod.mounted then continue end
    local diffInSeconds = os.time() - mod.updated
    local daysAgo = math.floor(diffInSeconds / (24 * 60 * 60))
    if daysAgo > modListMaxDays then continue end
        
    table.insert(lastUpdatedMods,mod.title)
end



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

local libraryIcons = {
    ["surface"]     = "icon16/picture_edit.png",
    ["draw"]        = "icon16/picture_edit.png",
    ["render"]      = "icon16/picture_edit.png",
    ["sound"]       = "icon16/sound.png",
    ["file"]        = "icon16/page_edit.png"
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


local ogFuncs = {
    Input = {
        isKeyDown = input.IsKeyDown,
    },
    Util = {
        SHA256 = util.SHA256,
        TableToJSON = util.TableToJSON,
        JSONToTable = util.JSONToTable,
    },
    Timer = {
        Create = timer.Create,
        Remove = timer.Remove,
        Exists = timer.Exists,
    },
    String = {
        find = string.find,
        match = string.match,
        gmatch = string.gmatch,
	EndsWith = string.EndsWith
    },
    isValid = IsValid,
    Ipairs = ipairs,
    Pairs  = pairs,
    curTime = CurTime,
    unPack  = unpack,
    RunCMD  = RunConsoleCommand,
    VGUI = {
        Create = vgui.Create,
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

local IMPORTANCE = {
    LOW     = 0,
    NORMAL  = 1,
    MEDIUM  = 2,
    HIGH    = 3
}

// Fill original functions for later restoration and use
for _,funcName in ogFuncs.Ipairs(functionsToOverride["Surface"]) do
    originalFuncs["Surface"][funcName] = surface[funcName]
end
for _,funcName in ogFuncs.Ipairs(functionsToOverride["Render"]) do
    originalFuncs["Render"][funcName] = render[funcName]
end
for _,funcName in ogFuncs.Ipairs(functionsToOverride["Draw"]) do
    originalFuncs["Draw"][funcName] = draw[funcName]
end
for _,funcName in ogFuncs.Ipairs(functionsToOverride["Sound"]) do
    originalFuncs["Sound"][funcName] = sound[funcName]
end
for _,funcName in ogFuncs.Ipairs(functionsToOverride["Global"]) do
    originalFuncs["Global"][funcName] = _G[funcName]
end
for _,funcName in ogFuncs.Ipairs(functionsToOverride["Debug"]) do
    originalFuncs["Debug"][funcName] = debug[funcName]
end
for _,funcName in ogFuncs.Ipairs(functionsToOverride["File"]) do
    originalFuncs["File"][funcName] = file[funcName]
end

// Holds data about functions that were ran.
local stack = {

}

// How long until a stack item is deleted
local stackDeleteDelay = 10

local function SetSuspicious(preSus,newSus)
    // return preSus if newSus importance is less otherwise newsus
    return preSus[3] > newSus[3] and preSus or newSus
end

local function AntiScreamer_AddToStack(info,funcName,argsIn,originalFunction,libraryName)
    local source      = info.source or "Unknown Source"
    
    local returnOriginalFunction = false 
    returnOriginalFunction =  ogFuncs.String.find(source,fileName) 
    or ogFuncs.String.find(source,"@lua/derma") 
    or ogFuncs.String.find(source,"@lua/vgui") 
    or ogFuncs.String.find(source,"@lua/skins/default")
    
    
    if returnOriginalFunction then 
        return originalFunction(ogFuncs.unPack(argsIn)) 
    end
    
    local shortSource = info.short_src or "Unknown Short Source"
    local fileName = string.GetFileFromFilename(shortSource)
    if ignoreList[shortSource] then return nil end
    
    local foundAddonName = nil
    
    for _,mod in ogFuncs.Ipairs(lastUpdatedMods) do
        if file.Exists(shortSource,mod) then
            foundAddonName = mod
        end
    end
    
    local identifier = ogFuncs.Util.SHA256(source .. funcName)
    
    if not stack[funcName] then
        stack[funcName] = {}
    end
    stack[funcName].library = libraryName

    local sus = {"","",IMPORTANCE.LOW}

    if stack[funcName][identifier] then
        if ogFuncs.curTime() - stack[funcName][identifier].time <= 0.25 then
            sus = SetSuspicious(sus,{
                "Possibly Suspicious",
                "This addon is running this function constantly, likely in a hook or loop.",
                IMPORTANCE.LOW
            })
        end
    end
    if fileBlackList[fileName] or ogFuncs.String.find(shortSource,"screamer") != nil then
        sus = SetSuspicious(sus,{
            "Blacklisted Files Detected",
            "This lua file ( " .. fileName ..  ") calling the function is in the blacklist, very likely a screamer!",
            IMPORTANCE.HIGH
        })
    end

    if funcName == "SetTexture" then
        argsIn[1] = "[TexID: " .. argsIn[1] .. "] " .. surface.GetTextureNameByID(argsIn[1])
    end

    stack[funcName][identifier]  =     {
        args        = argsIn,
        source      = source, 
        shortSource = shortSource, 
        time        = ogFuncs.curTime(),
        suspicious  = sus,
        addonName   = foundAddonName or nil
    }
   
    //print("Added to stack:", funcName, identifier)
    //PrintTable(stack)
    return nil
end

local function AntiScreamer_OverrideFunc(funcName,argsIn,originalFunction,libraryName)
    local debugInfo = originalFuncs.Debug.getinfo(2,"Sn")
    return AntiScreamer_AddToStack(debugInfo,funcName,argsIn,originalFunction,libraryName)
end
// OVERRIDE
local function AntiScreamer_OverrideBaseFunctions()
    if !enabled then return end
    for _,funcName in ogFuncs.Ipairs(functionsToOverride.Surface) do
        surface[funcName] = function(...) return AntiScreamer_OverrideFunc(funcName,{...},originalFuncs.Surface[funcName],"surface") end
    end
    for _,funcName in ogFuncs.Ipairs(functionsToOverride.Render) do
        render[funcName] = function(...) return AntiScreamer_OverrideFunc(funcName,{...},originalFuncs.Render[funcName],"render") end
    end 
    for _,funcName in ogFuncs.Ipairs(functionsToOverride.Sound) do
        sound[funcName] = function(...) return AntiScreamer_OverrideFunc(funcName,{...},originalFuncs.Sound[funcName],"sound") end
    end
    for _,funcName in ogFuncs.Ipairs(functionsToOverride.Draw) do
        draw[funcName] = function(...) return AntiScreamer_OverrideFunc(funcName,{...},originalFuncs.Draw[funcName],"draw") end
    end
    for _,funcName in ogFuncs.Ipairs(functionsToOverride.Debug) do
        debug[funcName] = function(...) return AntiScreamer_OverrideFunc(funcName,{...},originalFuncs.Debug[funcName],"debug") end
    end
    for _,funcName in ogFuncs.Ipairs(functionsToOverride.File) do
        file[funcName] = function(...) return AntiScreamer_OverrideFunc(funcName,{...},originalFuncs.File[funcName],"file") end
    end
    for _,funcName in ogFuncs.Ipairs(functionsToOverride.Global) do
        _G[funcName] = function(...) return AntiScreamer_OverrideFunc(funcName,{...},originalFuncs.Global[funcName],"global") end
    end
end
// RETURN TO ORIGINAL
local function AntiScreamer_ResetBaseFunctions()
    timer.Remove(thinkHookName)

    for _,funcName in ogFuncs.Ipairs(functionsToOverride.Surface) do
        surface[funcName] = originalFuncs.Surface[funcName]
    end
    for _,funcName in ogFuncs.Ipairs(functionsToOverride.Render) do
        render[funcName] = originalFuncs.Render[funcName]
    end 
    for _,funcName in ogFuncs.Ipairs(functionsToOverride.Sound) do
        sound[funcName] = originalFuncs.Sound[funcName]
    end
    for _,funcName in ogFuncs.Ipairs(functionsToOverride.Draw) do
        draw[funcName] = originalFuncs.Draw[funcName]
    end
    for _,funcName in ogFuncs.Ipairs(functionsToOverride.Debug) do
        debug[funcName] = originalFuncs.Debug[funcName]
    end
    for _,funcName in ogFuncs.Ipairs(functionsToOverride.File) do
        file[funcName] = originalFuncs.File[funcName]
    end
    for _,funcName in ogFuncs.Ipairs(functionsToOverride.Global) do
        _G[funcName] = originalFuncs.Global[funcName]
    end
end


local function AntiScreamer_Hook()
    AntiScreamer_OverrideBaseFunctions()
end

local function AntiScreamer_HookExists()
    return ogFuncs.Timer.Exists(thinkHookName)
end

local function AntiScreamer_AddHook()
    if !enabled then return end
    ogFuncs.Timer.Create(thinkHookName,0.01,0,AntiScreamer_Hook)
end

local validationTimerName = thinkHookName .. "_validator"
 
local function AntiScreamer_Timer_HookValidator()
    if !enabled then return end
    // Simple timers are undetectable and unchangable (to my knowledge)
    if !ogFuncs.Timer.Exists(validationTimerName) then ogFuncs.Timer.Create(validationTimerName,1,0,AntiScreamer_Timer_HookValidator) end
    if AntiScreamer_HookExists() then
        return
    end
    if !enabled then ogFuncs.Timer.Remove(thinkHookName) return end
    AntiScreamer_Hook()
    AntiScreamer_AddHook()

end

local function AntiScreamer_Toggle()
    enabled = !enabled
    if enabled then
        AntiScreamer_Timer_HookValidator()
    else
        AntiScreamer_ResetBaseFunctions()
        ogFuncs.Timer.Remove(validationTimerName)
    end
end




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
    if !ogFuncs.isValid(node) then node = treenode:AddNode(name,icon) end

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
local showUpdatedModsWindow = function(self) end

local lastStackCount = 0

local frame = nil

local function CreateStackViewer(delayRefresh)
    if ogFuncs.isValid(frame) then return end
    frame = ogFuncs.VGUI.Create("DFrame")
    frame:SetSize(600,720)
    frame:SetSizable(true)
    frame:Center()
    frame:SetTitle("Anti-Screamer Stack Viewer")
    frame:MakePopup()
    frame:SetSkin("Default")

    if delayRefresh == nil then delayRefresh = false end

    stackTree = ogFuncs.VGUI.Create("DTree",frame)
    stackTree.Expand = false
    stackTree.DoRightClick = function(self,node)
        local menu = DermaMenu()
        menu:SetSkin("Default")
        menu:AddOption("Copy Name",function() SetClipboardText(node:GetText()) end)
        if node.Addon then
            menu:AddOption("Add to Ignore List",function() 
                if isWorkshop then notification.AddLegacy("Feature is Github version only for security reasons! Visit the workshop page to learn more.",NOTIFY_ERROR,6) return end
		if not ogFuncs.String.EndsWith(ignoreListFileName,".txt") then notification.AddLegacy("You need to set a proper ignore list file name! Needs to end with '.txt'",NOTIFY_ERROR,6) return end
                notification.AddLegacy(node.Addon .. " added to ignore list. (You may see it's entry for 10 more seconds)",NOTIFY_HINT,6)
                ignoreList[node.Addon] = true
                if ogFuncs.isValid(framesToClose.ignoredModsFrame) then framesToClose.ignoredModsFrame.fillList() end
                stackTree:Clear() nodeCache = {}
                stackTree.RefreshTree() 
                originalFuncs.File.Write(ignoreListFileName,ogFuncs.Util.TableToJSON(ignoreList,false))
            end)
        end
        menu:Open()
    end

    frame.OnClose = function() 
        nodeCache = {} 
        for _,frame in ogFuncs.Pairs(framesToClose) do 
            if ogFuncs.isValid(frame) then 
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
        stackTree.Expand = false
        local count = 0
        
        if #stack != lastStackCount then stackTree:Clear() nodeCache = {} end
        lastStackCount = #stack

        for funcName,funcStack in ogFuncs.Pairs(stack) do

            count = count + 1

            local library = funcStack.library or ""

            local icon = "icon16/application_osx_terminal.png"
            if libraryIcons[library] then 
                icon = libraryIcons[library] 
            else
                icon = "icon16/application_osx_terminal.png"
            end
            // CODE ABOVE DOESNT WORK CAUSE GMOD HATES ME

            if library != "file" then library = "" end

            local node = AddNodeSpecial(funcName,"icon16/application_osx_terminal.png",stackTree, "funcNode_" .. count )
            node.isFuncNode = true

            local count2 = 0

            if !ogFuncs.isValid(node) then continue end

            for identifier,stackInfo in ogFuncs.Pairs(funcStack) do
                local idTail = "_" .. count .. "_" .. count2
                
                local time      = stackInfo.time or -1
                // remove after delay
                if ogFuncs.curTime() - time >= stackDeleteDelay then 
                    funcStack[identifier] = nil 
                    local nodeName = "addonNode" .. idTail
                    if count > 0 and nodeCache[nodeName] then 
                        nodeCache[nodeName]:Remove() 
                        nodeCache[nodeName] = nil
                    end 
                    continue 
                end

                count2 = count2 + 1

                local source    = stackInfo.source or "Unknown Source"
                local shortSrc  = stackInfo.shortSource or "Unknown Source"

                local addon     = ogFuncs.String.match(source,"addons/(.-)/")
                if addon == nil then
                    local short = stackInfo.addonName or shortSrc
                    if short == shortSrc then shortSrc:sub(5,-1) end
                    addon = short
                end

                local args      = stackInfo.args or {}
                local sus       = stackInfo.suspicious or {"","",0}

                local addonNodeName = "addonNode" .. idTail
                // Addon name tree
                local addonNode = AddNodeSpecial("Addon: " .. addon,sus[3] != IMPORTANCE.HIGH and "icon16/bricks.png" or "icon16/bullet_error.png",node,addonNodeName)
                addonNode.Addon = stackInfo.shortSource
                // Time since it was called
                local timeNodeName = "time" .. idTail
                AddNodeSpecial(string.format("%.1f", ogFuncs.curTime() - time) .. " seconds ago...","icon16/clock.png",addonNode, timeNodeName)
                // The arguments for the function call
                local argsNodeName = "args" .. idTail
                local argsNode = AddNodeSpecial("Arguments","icon16/script_code.png",addonNode,argsNodeName,true)
                for _,arg in ogFuncs.Ipairs(args) do
                    if suspiciousArgs[arg] then 
                        sus = SetSuspicious(sus,{
                            "Suspicious",
                            "A suspicious argument was used to run this function: " .. tostring(arg),
                            IMPORTANCE.LOW
                        })
                    end
                    AddNodeSpecial(tostring(arg),"icon16/shape_square.png",argsNode)
                end
                local fullSourceNodeName = "fullSource" .. idTail
                // full source if u want it
                local fullSource = AddNodeSpecial("Full Source","icon16/table.png",addonNode,fullSourceNodeName, true)
     
                local lastNode = fullSource
                local parts = {}
                for part in ogFuncs.String.gmatch(source, "[^/]+") do
                    table.insert(parts, 1, part)
                end
                for _, part in ogFuncs.Ipairs(parts) do
                    lastNode = AddNodeSpecial(part,"icon16/folder.png",lastNode)
                end
                
                node.Label:SetText(library .. ((#library > 0) and "." or "") .. funcName .. " (".. sus[1] ..")")
                addonNode.Label:SetText(addonNode.Label:GetValue() .. " (".. sus[1] ..")")
                addonNode:SetTooltip(sus[2])
            end
        end
    end

    if delayRefresh then
        timer.Simple(1.0,function()
            if !ogFuncs.isValid(stackTree) then return end
            stackTree.RefreshTree()
        end)
    else
        stackTree.RefreshTree()
    end
    ---------------------------------------------------------------

    local bottomPanel = ogFuncs.VGUI.Create("DPanel",frame)
    bottomPanel:Dock(BOTTOM)
    bottomPanel:SetTall(50)

    ---------------------------------------------------------------
    local refreshButton = ogFuncs.VGUI.Create("DButton",bottomPanel)
    refreshButton:Dock(FILL)
    refreshButton:SetText("Refresh")
    refreshButton.DoClick = function()
        stackTree.RefreshTree()
    end
    ---------------------------------------------------------------
    local expandButton = ogFuncs.VGUI.Create("DButton",bottomPanel)
    expandButton:SetWide(80)
    expandButton:Dock(LEFT)
    expandButton:DockMargin(5,0,0,0)
    expandButton:SetText("Expand")
    expandButton.DoClick = function() 
        stackTree.Expand = !stackTree.Expand 
        for _,node in ogFuncs.Pairs(nodeCache) do
            if node.isFuncNode then
                node:ExpandRecurse(stackTree.Expand)        
            end
        end
    end
    
    ---------------------------------------------------------------
    local clearButton = ogFuncs.VGUI.Create("DButton",bottomPanel)
    clearButton:SetWide(80)
    clearButton:Dock(LEFT)
    clearButton:DockMargin(2,0,2,0)
    clearButton:SetText("Clear")
    clearButton:SetTooltip("Hold SHIFT and click to expand the tree after clear.")
    clearButton.DoClick = function()
        stackTree:Clear()  nodeCache = {}
        stackTree.RefreshTree()
        if input.IsKeyDown(KEY_LSHIFT) then
            expandButton.DoClick()
        end
    end
    ---------------------------------------------------------------

 
    local autoRefreshCheckBox = ogFuncs.VGUI.Create("DCheckBoxLabel",bottomPanel)
    local optionsButton       = ogFuncs.VGUI.Create("DButton",bottomPanel)
    local helpButton = ogFuncs.VGUI.Create("DButton",bottomPanel)
    helpButton:Dock(RIGHT) helpButton:DockMargin(20,0,5,0)
    helpButton:SetText("Help")
    helpButton.DoClick = function()
        if ogFuncs.isValid(framesToClose.helpFrame) then return end
        ---------------------------------------------------------------
        local helpFrame = ogFuncs.VGUI.Create("DFrame") framesToClose.helpFrame = helpFrame
        helpFrame:SetTitle("Help")
        helpFrame:SetSize(615,800) 
        helpFrame:Center() helpFrame:SetPos(helpFrame:GetPos() - 150)
        helpFrame:MakePopup()
        helpFrame:SetSkin("Default")
        ---------------------------------------------------------------

        local whiteBG = ogFuncs.VGUI.Create("DPanel",helpFrame)
        whiteBG:Dock(FILL)

        ---------------------------------------------------------------
        local helpText = ogFuncs.VGUI.Create("DLabel",helpFrame)
        helpText:SetSize(600,400)       helpText:SetPos(8,30)
        helpText:SetText(asHelpText)    helpText:SetMultiline(true)
        helpText:SetDark(true)          helpText:SetFont("AntiScreamer_StackFont")
        helpText:SetWrap(true)          helpText:SetContentAlignment(7)
        ---------------------------------------------------------------
        
        ---------------------------------------------------------------
        local helpText2 = ogFuncs.VGUI.Create("DLabel",helpFrame)
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
    autoRefreshCheckBox:SetValue(ogFuncs.Timer.Exists("AntiScreamer_RefreshTimer"))

    
    autoRefreshCheckBox.OnChange = function(self,val)
        if val then
            ogFuncs.Timer.Create("AntiScreamer_RefreshTimer",0.5,0,function()
                if ogFuncs.isValid(stackTree) then

                    stackTree.RefreshTree()
                else
                    ogFuncs.Timer.Remove("AntiScreamer_RefreshTimer")
                end
            end)
        else
            ogFuncs.Timer.Remove("AntiScreamer_RefreshTimer")
        end
        if self:GetValue() == false then ogFuncs.Timer.Remove("AntiScreamer_RefreshTimer") end
    end
    ---------------------------------------------------------------

    ---------------------------------------------------------------
    optionsButton:Dock(RIGHT)
    optionsButton:DockMargin(0,0,0,0)
    optionsButton:SetText("Options")
    optionsButton:SetTooltip("Hold SHIFT while clicking to quick-toggle the Anti-Screamer.\nHold SHIFT while RIGHT clicking to see updated addons")


    optionsButton.OnMousePressed = function(self,mouse)
        if mouse == MOUSE_RIGHT then
            if input.IsKeyDown(KEY_LSHIFT) then
                showUpdatedModsWindow(nil, optionsButton)
            end
        elseif mouse == MOUSE_LEFT then
            if input.IsKeyDown(KEY_LSHIFT) then
                AntiScreamer_Toggle()
                notification.AddLegacy("Anti-Screamer is " .. (enabled and "ON" or "OFF"),(enabled and NOTIFY_GENERIC or NOTIFY_ERROR),3)
            else
                optionsButtonMenu()
            end
        end
    end
    ---------------------------------------------------------------
    
end

showUpdatedModsWindow = function(self,panel)
    if ogFuncs.isValid(framesToClose.modsFrame) then return end
    ---------------------------------------------------------------
    local modsFrame = ogFuncs.VGUI.Create("DFrame") framesToClose.modsFrame = modsFrame
    modsFrame:SetTitle("Last Updated Addons")
    modsFrame:SetSize(400,600)
    modsFrame:Center()
    modsFrame:SetPos(panel:GetPos() + 400)
    modsFrame:MakePopup()
    modsFrame:SetSkin("Default")
    ---------------------------------------------------------------

    ---------------------------------------------------------------
    local topPanel = ogFuncs.VGUI.Create("DPanel",modsFrame)
    topPanel:SetPos(0,25)
    topPanel:SetTall(45)
    topPanel:SetWide(400)
    ---------------------------------------------------------------
    
    local maxDays = ogFuncs.VGUI.Create("DNumberWang",topPanel) 
    maxDays:SetMinMax(0,1500)
    maxDays:SetPos(90,14)
    maxDays:SetValue(modListMaxDays)
    local label = ogFuncs.VGUI.Create("DLabel",topPanel) label:SetText("Max Days Ago: ") 
    label:SetPos(5,18) label:SizeToContents() label:SetDark(true)
    
    local modsList = nil


    local function fillModsList()
        modsList:Clear()
        lastUpdatedMods = {}
        for _,mod in ogFuncs.Ipairs(mods) do
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

            local modIcon = ogFuncs.VGUI.Create("DImage",modButton)
            modIcon:SetPos(40,10)
            local iconMat = nil

            // Get Addon Icon and put it on the mod button.
            steamworks.FileInfo( mod.wsid, function( result )
                steamworks.Download( result.previewid, true, function( name )
                    iconMat = AddonMaterial( name )
                    if iconMat == nil then
                        iconMat = Material("icon16/bricks.png")
                    end
                    if ogFuncs.isValid(modIcon) then modIcon:SetMaterial(iconMat) end
                    
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
    modsList = ogFuncs.VGUI.Create("DScrollPanel", modsFrame)
    modsList:SetPos(0,75)
    modsList:SetTall(520) modsList:SetWide(400)
    fillModsList()
end

optionsButtonMenu = function(self) 
    if ogFuncs.isValid(framesToClose.optionsFrame) then return end
    local optionsFrame = ogFuncs.VGUI.Create("DFrame") framesToClose.optionsFrame = optionsFrame
    optionsFrame:SetTitle("Options")
    optionsFrame:SetSize(400,300)
    optionsFrame:Center()
    optionsFrame:SetPos(optionsFrame:GetX() + 200,optionsFrame:GetY() + 70)
    optionsFrame:MakePopup()
    optionsFrame:SetSkin("Default")
    ---------------------------------------------------------------
    

    local optionsList = ogFuncs.VGUI.Create("DListLayout", optionsFrame)
    optionsList:Dock(FILL)

    ---------------------------------------------------------------
    local enableDisableButton = ogFuncs.VGUI.Create("DButton",optionsList)
    enableDisableButton:SetColor(enabled and Color(25,160,75) or Color(161,35,62))
    enableDisableButton:SetText(enabled and "Enabled" or "Disabled")
    enableDisableButton.DoClick = function()
        AntiScreamer_Toggle()
        enableDisableButton:SetText(enabled and "Enabled" or "Disabled")
        enableDisableButton:SetColor(enabled and Color(25,160,75) or Color(161,35,62))
    end
    ---------------------------------------------------------------

    ---------------------------------------------------------------
    local viewUpdatedMods = ogFuncs.VGUI.Create("DButton",optionsList)
    viewUpdatedMods:SetText("View Updated Addons")
    viewUpdatedMods.DoClick = function(self) showUpdatedModsWindow(self,optionsFrame) end
    ---------------------------------------------------------------

    ---------------------------------------------------------------
    local viewIgnoredMods = ogFuncs.VGUI.Create("DButton",optionsList)
    viewIgnoredMods:SetText("Edit Ignored Script Paths")
    viewIgnoredMods.DoClick = function()
        if ogFuncs.isValid(framesToClose.ignoredModsFrame) then return end
        ---------------------------------------------------------------
        local modsFrame = ogFuncs.VGUI.Create("DFrame")
        modsFrame:SetTitle("Edit Ignored Script Paths (CLICK TO REMOVE)")
        modsFrame:SetSize(500,500)
        modsFrame:Center()
        modsFrame:SetPos(optionsFrame:GetPos() + 400)
        modsFrame:MakePopup()
        modsFrame:SetSkin("Default")
        
        local modsList = ogFuncs.VGUI.Create("DScrollPanel", modsFrame)
        modsList:Dock(FILL)
        local function fillModsList()
            modsList:Clear()
            for path,v in ogFuncs.Pairs(ignoreList) do
                local button = modsList:Add("DButton")
                button:SetText(path)
                button:Dock( TOP )
                button:DockMargin( 0, 0, 0, 5 )
                button.DoClick = function () 
                    button:Remove() 
                    ignoreList[path] = nil
		    if ogFuncs.String.EndsWith(ignoreListFileName,".txt") and not isWorkshop then
                        originalFuncs.File.Write(ignoreListFileName,ogFuncs.Util.TableToJSON(ignoreList,false))
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

Using the stack viewer, you are able to see what drawing/sound/etc functions have been called recently.
The tree starts with function names, then inside are all the addons that are calling that function with extra details.
    
These functions that are watched are not malicious by themselves, but can be used to display/play screamers.

The stack viewer will mark a function (and the addon that calls it) as suspicious if it does the following:

    - Calls the function more than once in a second
    - Uses the screen width or height as an argument
    - Is being called by a script file with a blacklisted name.

]]
asHelpText2 = [[
Like the functions themselves, these things are not always malicious, but are used by screamers.

It is up to you to determine if a mod is trying to display a screamer. Here are some tips:
    - Investigate the arguments used in the function.
    - Check how recent the addon was updated (Old mods that are updated recently could be suspicious)
    - If an entity mod/weapon mod/etc is calling drawing functions, it could be suspicious (HUD mods for example shouldn't be suspicious, since they rely on these functions)

PS: Sometimes entries can appear to duplicate in the Stack-Viewer, click the "Clear" button to fix it.
]]

list.Set( "DesktopWindows", "Stack Viewer Icon Button", {
	title = "Anti-Screamer Stack Viewer",
	icon = "icon64/icon_antiscreamer.png",
	init = function( icon, window )
		CreateStackViewer()
	end
} )

hook.Add("HUDPaint","AntiScreamer_Notify_" .. genRandomString(),function()
    if enabled then
        draw.SimpleText("Anti-Screamer is currently enabled. Please finish checking the Stack-Viewer then disable it in it's options.","Trebuchet24",5,ScrH(),Color(255,0,0,255),TEXT_ALIGN_LEFT,TEXT_ALIGN_BOTTOM)
    end
end)

// Remove the "--" from the line below to be able to *open the stack viewer* with a console command (CHANGE THE CONSOLE COMMAND NAME AT THE TOP)
--concommand.Add(StackViewerConsoleCommand,CreateStackViewer)

// !!🚨 ** ABOVE AND BELOW COMMANDS ARE DIFFERENT ** 🚨!! \\

// Remove the "--" from the line below to be able to *disable the antiscreamer* with a console command (CHANGE THE CONSOLE COMMAND NAME AT THE TOP)
--CreateClientConVar(AntiScreamerDisableCommand,"0",true,false,"Toggles the Anti-Screamer on map start (REQUIRES MAP RESTART)",0,1)


// Creates hook, don't touch!
if AntiScreamerDisableCommand != "antiscreamer_changeme" and GetConVar(AntiScreamerDisableCommand):GetBool() == true then
    print("!!WARNING!! VVV")
    print("!!>>>>>>>!! Anti-Screamer is disabled via the command: '" .. AntiScreamerDisableCommand .. "'")
    print("!!WARNING!! ^^^")
else
    AntiScreamer_Timer_HookValidator()
end
// Stops any possible screamer sounds that autorun instantly
timer.Simple(0,function()
    ogFuncs.RunCMD("stopsound")
end)


// Remove the code below if you don't want it to open on map start.
local function lazyStartupCheck()
    if LocalPlayer() != NULL then
        CreateStackViewer(true)
    else
        timer.Simple(0.1,lazyStartupCheck)
    end
end
		
if AntiScreamerDisableCommand != "antiscreamer_changeme" and GetConVar(AntiScreamerDisableCommand):GetBool() == true then
    -- GENIUS CODE
else
    lazyStartupCheck()
end
