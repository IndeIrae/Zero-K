--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  file:    unit_global_build_command.lua
--  brief:   Fork of Central Build AI, which originally replaced Central Build Group AI
--  
--	author: aeonios (mtroyka)
--	Copyright (C) 2015.
--
--	original by:  Troy H. Cheek
--  Copyright (C) 2009.
--  
--	Licensed under the terms of the GNU GPL, v2 or later.
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--              CAUTION! CAUTION! CAUTION!
-- This widget is very complicated and very easy to break.
-- Only regular users who are familiar with its behavior should make changes/clean-up.

local version = "v1.1"
function widget:GetInfo()
  return {
    name      = "Global Build Command",
    desc      = version.. "\nGlobal Build Command gives you a global, persistent build queue for all workers that automatically assigns workers to the nearest jobs.\n \nInstructions: Enable this " ..
"then give any worker build-related commands. Placing buildings on top of existing jobs while holding \255\200\200\200Shift\255\255\255\255 cancels them, and without shift replaces them. \n" ..
"You can also exclude workers from GBC's control by adding them to the exclusion group (default control group 0). " ..
"Hit \255\255\90\90alt-s\255\255\255\255 to get an area select for removing jobs.\n \n" .. "It can also handle repair/reclaim/res, and automatically converts area res to reclaim for targets that cannot be resurrected.\n \n" ..
"Configuration is in \nGame->Worker AI",
    author    = "aeonios",
    date      = "July 20, 2009, 8 March 2014",
    license   = "GNU GPL, v2 or later",
    layer     = 10,
    enabled   = false  --  loaded by default?
  }
end

--  Global Build Command creates and manages a global, persistent build queue for all 
--	workers that automatically assigns workers to the nearest jobs based on a cost model.
--	It manages all the workers that are added to a user-configurable control group
--  and captures and manages build jobs as well as repair, reclaim and resurrect
--	in both single-target and area forms.

-- Organization:
-- 1) Top (init, GameFrame)
-- 2) GL Drawing Code
-- 3) Event Handlers (Callins)
-- 4) Core Logic
-- 5) Helper Functions

-- Note: Some of the code here is specific to Zero-K, however there are notes for this
-- if you are porting it to another game. If you have any questions feel free to ask
-- on the forums or email me at aeonioshaplo@gmail.com.

-- CHANGELOG (NEW) --
--	v1.0 (aeonios) Apr, 2015 --
--		-Removed code for detecting enemies, due to bad/intractable behavior.
--		-Cleaned/organized/reduced the old code. Added comments, sections, and section headers for easier browsing.
--		-Simplified the way workers are handled and removed references to 'assist' and 'guard' mechanics.
--		-Implemented a simplified, consistent cost model to replace the old convoluted one.
--		-Implemented handling of reclaim/repair/resurrect and area forms.
--		-Implemented an area job remove tool.
--		-Added user configurability through Chili options.
--		-Improved performance somewhat and fixed numerous bugs and unhandled edge cases from the old code.
--		-Improved the interface a bit and made it more consistent with the game's normal interface conventions.
--		- ++ bells and whistles.

---- CHANGELOG (OLD)-----
--	the following is from Central Build AI, which contains information that I found useful in understanding
--	how the code works, and which documents certain Spring/ZK quirks that you may want to know about.
--	
-- msafwan(xponen)	v1.355	(26Jan2015)	:	1) all builder re-assign job every 4 second (even if already assigned a job)
--											2) keep queue for unfinished building
--											3) lower priority (and/or removal) for queue at enemy infested area
--
-- msafwan,			v1.21	(7oct2012)	: 	fix some cases where unit become 'idle' but failed to be registered by CBA, 
--											make CBA assign all job at once rather than sending 1 by 1 after every some gameframe delay,
-- msafwan,			v1.2	(4sept2012)	: 	made it work with ZK "cmd_mex_placement.lua" mex queue, 
--											reduce the tendency to make a huge blob of constructor (where all constructor do same job),
--											reduce chance of some constructor not given job when player have alot of constructor,
-- rafal,			v1.1	(2May2012)	:	Don't fetch full Spring.GetCommandQueue in cases when only the first command is needed - instead using
--											GetCommandQueue(unitID, 1)
-- KingRaptor,		v1.1	(24dec2011)	:	Removed the "remove in 85.0" stuff
-- versus666,		v1.1	(16dec2011)	: 	mostly changed the layer order to get a logical priority among widgets.
-- KingRaptor,		v1.1	(8dec2011)	:	Fixed the remaining unitdef tags for 85.0
-- versus666,		v1.1	(7jan2011)	: 	Made CBA, cmd_retreat, gui_nuke_button, gui_team_platter.lua, unit_auto_group to obey F5 (gui hidden).
-- KingRaptor,		v1.1	(2Nov2010)	:	Moved version number from name to description. 
-- lccquantum,		v1.1	(2Nov2010)	:	central_build_AI is disabled by default (people will wonder why their builders are acting wierd when in group 0)
-- versus666,		v1.1	(1Nov2010)	: 	introduced into ZK

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Declarations ----------------------------------------------------------------
include("keysym.h.lua")

options_path = 'Game/Worker AI'

options_order = {
	'exclusionGroupID',
	'separateConstructors',
	'splitArea',
	'autoConvertRes',
	'autoRepair',
	'cleanWrecks',
	'intelliCost',
	'alwaysShow'
}

options = {
	exclusionGroupID = {
    name = 'Exclusion Group #',
    type = 'number',
    min = 0, max = 9, step = 1,
    value = 0,
    OnChange = function(self)
		groupHasChanged = true
	end,
	},
	
	separateConstructors = {
		name = 'Separate Constructors',
		type = 'bool',
		desc = 'Replace factory inherited orders for constructors so that they can be assigned jobs immediately.\n (default = true)',
		value = true,
	},
	
	splitArea = {
		name = 'Split Area Commands',
		type = 'bool',
		desc = 'Automatically capture single targets from area commands so that more workers will be assigned to those jobs.\n (default = true)',
		value = true,
	},
	
	autoConvertRes = {
		name = 'Convert Resurrect',
		type = 'bool',
		desc = 'Convert area resurrect into reclaim for targets that can\'t be resurrected.\n (Note: Only has any effect if Split Area Commands is enabled)\n (default = true)',
		value = true,
	},
	
	autoRepair = {
		name = 'Auto-Repair',
		type = 'bool',
		desc = 'Automatically add repair jobs whenever units are damaged.\n (Note: If this is enabled, repair jobs will only be visible when \255\200\200\200shift\255\255\255\255 is held!) \n (default = false)',
		value = false,
	},
	
	cleanWrecks = {
		name = 'Clean Up Wrecks',
		type = 'bool',
		desc = 'Automatically add reclaim/res for wrecks near your base. This does not target map features and is not a replacement for area reclaim/res.\n (default = false)',
		value = false,
	},
	
	intelliCost = {
		name = 'Intelligent Cost Model',
		type = 'bool',
		desc = 'Tries to optimize build order for better worker safety and faster overall construction, but makes it \nmore difficult to control what gets built first.\n (default = true)',
		value = true,
	},
	
	alwaysShow = {
		name = 'Always Show',
		type = 'bool',
		desc = 'If this is enabled queued commands will always be displayed, otherwise they are only visible when \255\200\200\200shift\255\255\255\255 is held.\n (default = false)',
		value = false,
	}
}

-- "Localized" API calls, because they run ~33% faster in lua.
local Echo					= Spring.Echo
local spIsGUIHidden			= Spring.IsGUIHidden
local spGetUnitDefID		= Spring.GetUnitDefID
local spGetFeatureDefID		= Spring.GetFeatureDefID
local spGetGroupList		= Spring.GetGroupList
local spGetGroupUnits		= Spring.GetGroupUnits
local spGetSelectedUnits	= Spring.GetSelectedUnits
local spIsUnitInView 		= Spring.IsUnitInView
local spIsAABBInView		= Spring.IsAABBInView
local spIsSphereInView		= Spring.IsSphereInView
local spGetTeamUnits		= Spring.GetTeamUnits
local spGetUnitsInCylinder	= Spring.GetUnitsInCylinder
local spGetUnitViewPosition = Spring.GetUnitViewPosition
local spGetCommandQueue    	= Spring.GetCommandQueue
local spGetUnitPosition		= Spring.GetUnitPosition
local spGetUnitDirection	= Spring.GetUnitDirection
local spGetUnitHealth		= Spring.GetUnitHealth
local spGetUnitTeam			= Spring.GetUnitTeam
local spIsUnitAllied		= Spring.IsUnitAllied
local spGiveOrderToUnit    	= Spring.GiveOrderToUnit
local spGiveOrderToUnitArray = Spring.GiveOrderToUnitArray
local spGetMyPlayerID       = Spring.GetMyPlayerID
local spGetMyTeamID			= Spring.GetMyTeamID
local spGetMyAllyTeamID		= Spring.GetMyAllyTeamID
local spGetFeatureTeam		= Spring.GetFeatureTeam
local spGetFeaturePosition	= Spring.GetFeaturePosition
local spGetFeaturesInCylinder = Spring.GetFeaturesInCylinder
local spGetAllFeatures		= Spring.GetAllFeatures
local spGetLocalPlayerID	= Spring.GetLocalPlayerID
local spGetPlayerInfo		= Spring.GetPlayerInfo
local spGetSpectatingState	= Spring.GetSpectatingState
local spGetModKeyState		= Spring.GetModKeyState
local spGetKeyState			= Spring.GetKeyState
local spTestBuildOrder		= Spring.TestBuildOrder
local spSelectUnitMap		= Spring.SelectUnitMap
local spGetUnitsInCylinder 	= Spring.GetUnitsInCylinder
local spGetUnitsInRectangle = Spring.GetUnitsInRectangle
local spGetUnitAllyTeam 	= Spring.GetUnitAllyTeam
local spGetUnitIsStunned 	= Spring.GetUnitIsStunned
local spValidUnitID			= Spring.ValidUnitID
local spValidFeatureID		= Spring.ValidFeatureID
local spUnitIsDead			= Spring.GetUnitIsDead
local spIsPosInLos			= Spring.IsPosInLos
local spGetGroundHeight		= Spring.GetGroundHeight
local spRequestPath			= Spring.RequestPath

local spWorldToScreenCoords = Spring.WorldToScreenCoords
local spTraceScreenRay		= Spring.TraceScreenRay
local spSetMouseCursor		= Spring.SetMouseCursor
local spPlaySoundFile		= Spring.PlaySoundFile

local glPushMatrix	= gl.PushMatrix
local glPopMatrix	= gl.PopMatrix
local glLoadIdentity = gl.LoadIdentity
local glTranslate	= gl.Translate
local glBillboard	= gl.Billboard
local glColor		= gl.Color
local glText		= gl.Text
local glTexture		= gl.Texture
local glTexRect		= gl.TexRect
local glBeginEnd	= gl.BeginEnd
local GL_LINE_STRIP	= GL.LINE_STRIP
local glDepthTest	= gl.DepthTest
local glRotate		= gl.Rotate
local glUnitShape	= gl.UnitShape
local glVertex		= gl.Vertex
local glGroundCircle = gl.DrawGroundCircle
local glLineWidth	=	gl.LineWidth
local glCreateList	= gl.CreateList
local glCallList	= gl.CallList
local glDeleteList	= gl.DeleteList

local CMD_WAIT    	= CMD.WAIT
local CMD_MOVE     	= CMD.MOVE
local CMD_PATROL  	= CMD.PATROL
local CMD_REPAIR    = CMD.REPAIR
local CMD_INSERT    = CMD.INSERT
local CMD_REMOVE    = CMD.REMOVE
local CMD_RECLAIM	= CMD.RECLAIM
local CMD_GUARD		= CMD.GUARD
local CMD_STOP		= CMD.STOP
local CMD_TERRAFORM_INTERNAL = 39801

local abs	= math.abs
local floor	= math.floor
local huge	= math.huge
local sqrt 	= math.sqrt
local max	= math.max
local min	= math.min
local modf	= math.modf

local nextFrame	= 2
local myTeamID = spGetMyTeamID()
local textColor = {0.7, 1.0, 0.7, 1.0}
local textSize = 12.0

-- Zero-K specific icons for drawing repair/reclaim/resurrect, customize if porting!
local rec_icon = "LuaUI/Images/commands/Bold/reclaim.png"
local rep_icon = "LuaUI/Images/commands/Bold/repair.png"
local res_icon = "LuaUI/Images/commands/Bold/resurrect.png"
local rec_color = {0.6, 0.0, 1.0, 1.0}
local rep_color = {0.0, 0.8, 0.4, 1.0}
local res_color = {0.4, 0.8, 1.0, 1.0}

--	"global" for this widget.  This is probably not a recommended practice.
local myUnits = {}	--  list of units in the Central Build group, of the form myUnits[unitID] = commandType
local myQueue = {}  --  list of commands for Central Build group, of the form myQueue[BuildHash(cmd)] = cmd
local busyUnits = {} -- list of units that are currently assigned jobs, of the form busyUnits[unitID] = BuildHash(cmd)
local idlers = {} -- list of units marked idle by widget:UnitIdle, which need to be double checked due to gadget conflicts. Form is idlers[index] = unitID
local excludedUnits = {} -- list of units which belong to the excluded group and thus will not be managed by GBC.
local activeJobs = {} -- list of jobs that have been started, using the UnitID of the building so that we can check completeness via UnitFinished
local idleCheck = false -- flag if any units went idle
local areaCmdList = {} -- a list of area commands, for persistently capturing individual reclaim/repair/resurrect jobs from LOS-limited areas. Same form as myQueue.
local reassignedUnits = {} -- list of units that have already been assigned/reassigned jobs and which don't need to be reassigned until we've cycled through all workers.
local groupHasChanged = true	--	Flag if group members have changed.
local hasRes = false
local queueCount = 0 -- the number of jobs currently on the queue, which must be updated every assignment frame since #aTable only works for arrays

-- variables used by the area job remove feature
local removeToolIsActive = false
local selectionStarted = false
local selectionCoords = {}
local selectionRadius = 0
local hasBeenUsed = false

-- drawing lists for GL
local BuildList = {}
local areaList = {}
local stRepList = {}
local stRecList = {}
local stResList = {}
--------------------------------------------
--List of prefix used as value for myUnits[]
local commandType = {
	drec = 'drec', -- indicates direct orders from the user, or from other source external to this widget.
	buildQueue = 'queu', -- indicates that the worker is under GBC control.
	idle = 'idle',
	mov = 'mov' -- indicates that the constructor was in the way of another constructor's job, and is being moved
}
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Top -------------------------------------------------------------------------

function widget:Initialize()
	if spGetSpectatingState() then
		Echo( "<Global Build Command>: Spectator mode. Widget removed." )
		widgetHandler:RemoveWidget()
		return
	end
	
	-- add all existing workers to GBC.
	local units = spGetTeamUnits(myTeamID)
	--if #units > 0 then
		for _, uid in ipairs(units) do
			local unitDefID = spGetUnitDefID(uid)
			local ud = UnitDefs[unitDefID]
			local _,_,nanoframe = spGetUnitIsStunned(uid)
			if (not nanoframe and ud.isBuilder and ud.speed > 0) then -- if the unit is a mobile builder
				local cmd = GetFirstCommand(uid) -- find out if it already has any orders
				if cmd and cmd.id then -- if so we mark it as drec
					myUnits[uid] = {cmdtype=commandType.drec, unreachable={}}
				else -- otherwise we mark it as idle
					myUnits[uid] = {cmdtype=commandType.idle, unreachable={}}
				end
				UpdateOneWorkerPathing(unitID) -- then precalculate pathing info
			end
		end
	--end
	
	-- screen the exclusion group
	UpdateOneGroupsDetails(options.exclusionGroupID.value)
	
	-- ZK compatability stuff
	WG.GlobalBuildCommand = { -- add compatibility functions to a table in widget globlals
		CommandNotifyPreQue = CommandNotifyPreQue, --an event which is called by "unit_initial_queue.lua" to notify other widgets that it is giving pregame commands to the commander.
		CommandNotifyMex = CommandNotifyMex, --an event which is called by "cmd_mex_placement.lua" to notify other widgets of mex build commands.
		CommandNotifyTF = CommandNotifyTF, -- an event called by "gui_lasso_terraform.lua" to notify other widgets of terraform commands.
		CommandNotifyRaiseAndBuild = CommandNotifyRaiseAndBuild -- an event called by "gui_lasso_terraform.lua" to notify other widgets of raise-and-build commands.
	}
end

--	The main process loop, which calls the core code to update state and assign orders as often as ping allows.
function widget:GameFrame(thisFrame)
	if thisFrame == 1 then -- initialize, using GameFrame since we need to properly account for lag
		nextFrame = 30 + ping()
		return
	end
	
	if ( thisFrame < nextFrame ) then 
		return
	end
	
	if groupHasChanged then -- if our control group has added or removed units
		UpdateOneGroupsDetails(options.exclusionGroupID.value) -- update it
	end
	
	if idleCheck then -- if our idle list has been updated
		CheckIdlers() -- then check and process it
	end
	
	CheckForRes() -- check if our group includes any units with resurrect, update the global flag
	
	CleanBuilders() -- remove any dead/captured/nonexistent constructors from myUnits and update bookkeeping
	
	queueCount = 0 -- reset the queue count
	for _, cmd in pairs(myQueue) do -- perform validity checks for all the jobs in the queue, and remove any which are no longer valid
		queueCount = queueCount + 1 -- count the jobs on the queue while checking them, for the constructor separator
		if not cmd.tfparams then -- ZK-specific: prevents combo TF-build operations from being removed by CleanOrders until the terraform is finished.
			CleanOrders(cmd, false) -- note: also marks workers whose jobs are invalidated as idle, so that they can be reassigned immediately.
		end
	end
	
	CleanBusy() -- removes workers from busyUnits if the job they're assigned to doesn't exist. Prevents crashes.
	
	if options.splitArea.value then -- if splitting area jobs is enabled
		UpdateAreaCommands() -- capture targets from area repair/reclaim/resurrect commands as they fall into LOS.
	end
	
	if options.cleanWrecks.value then -- if auto-reclaim/res is enabled
		CleanWrecks() -- capture all non-map-feature targets in LOS
	end
	
	CaptureTF() -- ZK-Specific: captures "terraunits" from ZK terraform, and adds repair jobs for them.
	
	local unitsToWork = FindEligibleWorker()	-- compile list of eligible units and assign them jobs.
	if (#unitsToWork > 0) then
		CleanPathing(unitsToWork) -- garbage collect pathing for jobs that no longer exist
		GiveWorkToUnits(unitsToWork)
	end
	
	nextFrame = thisFrame + ping()	-- repeat as quickly as ping allows.
end


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- GL Drawing Code -------------------------------------------------------------
--[[
HOW THIS WORKS:
	widget:Update()
		Pre-sorts myQueue by visibility and type for drawing.
	widget:DrawWorldPreUnit()
		Calls the functions for drawing building outlines and area command circles, since these need to be drawn first.
	widget:DrawWorld()
		Draws status tags on units, calls the functions for drawing building "ghosts" for build jobs, and
		command icons for other jobs.
	widget:DrawScreen()
		Changes the cursor if the area job remove tool is active.
	DrawBuildLines()
		Draws building outlines for build jobs, using DrawOutline().
	DrawAreaLines()
		Draws ground circles for area commands.
	DrawBuildingGhosts()
		Produces the gl code for drawing building ghosts for build jobs.
	DrawSTIcons()
		Draws command icons for single-target commands, takes a list as input rather than globals
		directly, since it's used to draw 3 different icon types.
]]--

-- Run pre-draw visibility checks, and sort myQueue for drawing.
function widget:Update(dt)
	if spIsGUIHidden() then
		return
	end
	
	buildList = {}
	areaList = {}
	stRepList = {}
	stRecList = {}
	stResList = {}
	
	local alt, ctrl, meta, shift = spGetModKeyState()
	if shift or options.alwaysShow.value then
		for _, myCmd in pairs(myQueue) do
			local cmd = myCmd.id
			if cmd < 0 then -- check visibility for building jobs
				local x, y, z, h = myCmd.x, myCmd.y, myCmd.z, myCmd.h
				if spIsAABBInView(x-1,y-1,z-1,x+1,y+1,z+1) then
					buildList[#buildList+1] = myCmd
				end
			elseif not myCmd.target then -- check visibility for area commands
				local x, y, z, r = myCmd.x, myCmd.y, myCmd.z, myCmd.r
				if spIsSphereInView(x, y, z, r+25) then
					areaList[#areaList+1] = myCmd
				end
			elseif myCmd.x -- check visibility for single-target commands
			or spValidUnitID(myCmd.target) then -- note we have to check units for validity to avoid nil errors, since the main validity checks may not have been run yet
				local x, y, z
				if myCmd.x then
					x, y, z = myCmd.x, myCmd.y, myCmd.z
				else
					x, y, z = spGetUnitPosition(myCmd.target)
				end
				local newCmd = {x=x, y=y, z=z} 
				if spIsSphereInView(x, y, z, 100) then
					if cmd == 40 then
						stRepList[#stRepList+1] = newCmd
					elseif cmd == 90 then
						stRecList[#stRecList+1] = newCmd
					else
						-- skip assigning x, y, z since res only targets features, which don't move
						stResList[#stResList+1] = newCmd
					end
				end
			end
		end
	end
end

-- Draw area command circles, building outlines and other ground decals
function widget:DrawWorldPreUnit()
	if (WG.Cutscene and WG.Cutscene.IsInCutscene()) or spIsGUIHidden() then
		return
	end

	local alt, ctrl, meta, shift = spGetModKeyState()
	-- Draw The selection circle for area job remove tool, if active
	if selectionStarted and selectionRadius > 0 then
		glColor(1.0, 0.0, 0.0, 0.6)
		glLineWidth(4)
		glGroundCircle(selectionCoords.x, selectionCoords.y, selectionCoords.z, selectionRadius, 64)
		glColor(1, 1, 1, 1)
		glLineWidth(1)
	end
	
	if shift or options.alwaysShow.value then
		glColor(0.0, 0.65, 1.0, 1) -- building outline color
		glLineWidth(1)
		
		DrawBuildLines() -- draw building outlines
		
		if shift and options.alwaysShow.value then
			glLineWidth(4)
		else
			glLineWidth(2)
		end
		
		DrawAreaLines() -- draw circles for area repair/reclaim/res
	end
	glColor(1, 1, 1, 1)
	glLineWidth(1)
end

--  Paint 'cb' tags on units, draw ghosts of items in central build queue.
--  Text stuff mostly borrowed from gunblob's Group Label and trepan/JK's BuildETA.
--  Ghost stuff borrowed from very_bad_soldier's Ghost Radar.
function widget:DrawWorld()
    if spIsGUIHidden() then
		return
	end
	local alt, ctrl, meta, shift = spGetModKeyState()
		
	--if removeToolIsActive then -- draw the cursor if the job remove tool is active
		--spSetMouseCursor("cursorrepair")
	--end
	glDepthTest(false)
	glColor(textColor)
	for unitID,myCmd in pairs(myUnits) do	-- show user which units are in our group
		if spIsUnitInView(unitID) then
			local ux, uy, uz = spGetUnitViewPosition(unitID)
			glPushMatrix()
			glTranslate(ux, uy, uz)
			glBillboard()
			glText(myCmd.cmdtype, -10.0, -15.0, textSize, "con")
			glPopMatrix()
		end -- if InView
	end -- for unitID in group
	    
	if shift or options.alwaysShow.value then
		if shift and options.alwaysShow.value then
			glColor(1, 1, 1, 0.5) -- 0.5 alpha
		else
			glColor(1, 1, 1, 0.35) -- 0.35 alpha
		end
		
		glDepthTest(true)
		glPushMatrix()
		DrawBuildingGhosts() -- draw building ghosts
		glPopMatrix()
		glDepthTest(false)
		
		glTexture(true)
		if shift and options.alwaysShow.value then -- increase the opacity of command icons when shift is held
			glColor(1, 1, 1, 0.8)
		else
			glColor(1, 1, 1, 0.6)
		end
		
		DrawAreaIcons() -- draw icons for area commands
		
		if shift and options.alwaysShow.value then -- increase the opacity of command icons when shift is held
			glColor(1, 1, 1, 0.7)
		else
			glColor(1, 1, 1, 0.4)
		end
		
		-- draw icons for single-target commands
		if not (options.autoRepair.value and not shift) then -- don't draw repair icons if autorepair is enabled, unless shift is held
			glTexture(rep_icon)
			DrawSTIcons(stRepList)
		end
		
		glTexture(rec_icon)
		DrawSTIcons(stRecList)
		
		glTexture(res_icon)
		DrawSTIcons(stResList)
	end
	glTexture(false)
	glColor(1, 1, 1, 1)
end

-- This function changes the mouse cursor if the job remove tool is active.
function widget:DrawScreen()
	if removeToolIsActive and not spIsGUIHidden() then -- draw the cursor if the job remove tool is active
		spSetMouseCursor("cursorrepair")
	end
end

function DrawBuildLines()
	for _,cmd in pairs(buildList) do -- draw outlines for building jobs
		--local cmd = buildList[i]
		local x, y, z, h = cmd.x, cmd.y, cmd.z, cmd.h
		local bcmd = abs(cmd.id)
		glBeginEnd(GL_LINE_STRIP, DrawOutline, bcmd, x, y, z, h)
	end
end

function DrawOutline(cmd,x,y,z,h)
	local ud = UnitDefs[cmd]
	local baseX = ud.xsize * 4 -- ud.buildingDecalSizeX
	local baseZ = ud.zsize * 4 -- ud.buildingDecalSizeY
	if (h == 1 or h==3) then
		baseX,baseZ = baseZ,baseX
	end
	glVertex(x-baseX,y,z-baseZ)
	glVertex(x-baseX,y,z+baseZ)
	glVertex(x+baseX,y,z+baseZ)
	glVertex(x+baseX,y,z-baseZ)
	glVertex(x-baseX,y,z-baseZ)
end

function DrawAreaLines()
	for _,cmd in pairs(areaList) do -- draw circles for area repair/reclaim/resurrect jobs
		--local cmd = areaList[i]
		local x, y, z, r = cmd.x, cmd.y, cmd.z, cmd.r
		if cmd.id == 40 then
			glColor(rep_color)
		elseif cmd.id == 90 then
			glColor(rec_color)
		else
			glColor(res_color)
		end
		glGroundCircle(x, y, z, r, 32)
	end
end

function DrawBuildingGhosts()
	for _,myCmd in pairs(buildList) do -- draw building "ghosts"
		--local myCmd = buildList[i]
		local bcmd = abs(myCmd.id)
		local x, y, z, h = myCmd.x, myCmd.y, myCmd.z, myCmd.h
		local degrees = h * 90
		glLoadIdentity()
		glTranslate(x, y, z)
		glRotate(degrees, 0, 1.0, 0 )
		glUnitShape(bcmd, myTeamID, false, false, false)
	end
end

function DrawAreaIcons()
	for i=1, #areaList do -- draw area command icons
		local myCmd = areaList[i]
		local x, y, z = myCmd.x, myCmd.y, myCmd.z
		glPushMatrix()
		if myCmd.id == 40 then
			glTexture(rep_icon)
		elseif myCmd.id == 90 then
			glTexture(rec_icon)
		else
			glTexture(res_icon)
		end
		glRotate(0, 0, 1.0, 0)
		glTranslate(x-75, y, z+75)
		glBillboard()
		glTexRect(0, 0, 150, 150)
		glPopMatrix()
	end
end

function DrawSTIcons(myList)
	local alt, ctrl, meta, shift = spGetModKeyState()
	for i=1, #myList do -- draw single-target command icons
		local myCmd = myList[i]
		local x, y, z = myCmd.x, myCmd.y, myCmd.z
		glPushMatrix()
		glRotate(0, 0, 1.0, 0)
		glTranslate(x-33, y, z+33)
		glBillboard()
		glTexRect(0, 0, 66, 66)
		glPopMatrix()
	end
end


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Event Handlers --------------------------------------------------------------
--[[
HOW THIS WORKS:
	widget:PlayerChanged()
		Detects when the player resigns, and disables the widget.
	widget:GroupChanged()
		Detects when our control group has changed, and sets a flag for updating myUnits.
	widget:UnitDamaged()
		Automatically adds repair jobs for damaged units, if enabled.
	widget:UnitFromFactory()
		Separates constructors from the factory stream, if enabled. Uses ZK-specific,
		factory-dependent values for clearing distance.
	widget:UnitCreated()
		Detects when new non-factory units are started, and if the builder is one of ours
		it records the association between the started unit and the job it represents.
		It also removes jobs when start-nanoframe-only mode is used, and updates ZK-specific
		raise-and-build commands to normal commands after the terraform finishes.
	widget:UnitFinished()
		Detects when a finished unit is from one of our jobs, and performs necessary cleanup.
	widget:UnitDestroyed()
		Performs cleanup whenever a worker or building nanoframe dies.
	widget:UnitTaken()
		Performs cleanup whenever a worker or building nanoframe is captured by the enemy.
	widget:UnitIdle()
		This catches units from our group as they go idle, and marks them for
		deferred processing. This is necessary because UnitIdle sometimes misfires
		during build jobs, for unknown reasons.
	CommandNotifyMex()
		ZK-Specific: Captures mex commands from the cmd_mex_placement widget.
	CommandNotifyTF()
		ZK-Specific: Captures terraform commands from gui_lasso_terraform widget.
	CommandNotifyRaiseAndBuild()
		ZK-Specific: Captures raise-and-build commands from gui_lasso_terraform widget.
	widget:CommandNotify()
		This captures all the build-related commands from units in our group,
		and adds them to the global queue.

 -- area job removal tool stuff --
	widget:KeyPress()
		Captures the hotkey for job remove, sets the tool as active.
	widget:KeyRelease()
		Captures releases for the shift key, for correct shift behavior.
	widget:MousePress()
		Captures the starting coords for the area select, sets state.
	widget:MouseMove()
		Tracks the mouse after a selection has started, and updates the selection
		radius for drawing.
	widget:MouseRelease()
		Captures the final values for the area select and activates the removal function.
		Also updates state depending on shift, to allow for additional selections or to deactivate
		the tool.
]]--


--  Detect when player enters spectator mode (thanks to SeanHeron).
function widget:PlayerChanged(playerID)
	if spGetSpectatingState() then
		Echo( "<Global Build Command> Spectator mode. Widget removed." )
		WG.GlobalBuildCommand = nil
		widgetHandler:RemoveWidget()
		return
	end
end

--	This function detects that a new group has been defined or changed.
--  Borrowed from gunblob's UnitGroups v5.1
function widget:GroupChanged(groupId)  
	if groupId == options.exclusionGroupID.value then
		groupHasChanged = true 
		-- note: Use it to set a flag because it fires before all units it's going to put into group have actually been put in.
	end
end

-- This function detects when our workers have started a job
function widget:UnitCreated(unitID, unitDefID, unitTeam, builderID)
	if busyUnits[builderID] then -- if the builder is one of our busy workers
		local key = busyUnits[builderID]
		local myCmd = myQueue[key]
		
		if myCmd.tfparams then -- ZK-Specific: For combo terraform-build commands, convert to normal build commands once the building has started
			myQueue[key].tfparams = nil
			UpdateOneJobPathing(key) -- update pathing, since terraform can change the results
		end
			
		if myCmd.q then -- if given with 'start-only', then cancel the job as soon as it's started
			StopAnyWorker(key)
			myQueue[key] = nil
		else -- otherwise track the unitID in activeJobs so that UnitFinished can remove it from the queue
			activeJobs[unitID] = key
		end
	end
	
	-- add new workers to the worker group. technically it only applies to commanders for UnitCreated.
	local ud = UnitDefs[unitDefID]
	local _,_,nanoframe = spGetUnitIsStunned(unitID)
	if (not nanoframe and ud.isBuilder and ud.speed > 0) then -- if the new unit is a mobile builder
		-- init our commander as idle, since the initial queue widget will notify us later when it gives the com commands.
		myUnits[unitID] = {cmdtype=commandType.idle, unreachable={}}
		UpdateOneWorkerPathing(unitID) -- then precalculate pathing info
	end
end

-- This function detects when a unit was finished and it was from a job on the queue, and does necessary cleanup
function widget:UnitFinished(unitID, unitDefID, unitTeam)
	if activeJobs[unitID] then
		local key = activeJobs[unitID]
		if myQueue[key] then
			StopAnyWorker(key)
			myQueue[key] = nil
		end
		activeJobs[unitID] = nil
	end
	
	-- add new workers to the worker list.
	local ud = UnitDefs[unitDefID]
	if (ud.isBuilder and ud.speed > 0) then -- if the new unit is a mobile builder
		local cmd = GetFirstCommand(unitID) -- find out if it already has any orders
		if cmd and cmd.id then -- if so we mark it as drec
		myUnits[unitID] = {cmdtype=commandType.drec, unreachable={}}
		else -- otherwise we mark it as idle
			myUnits[unitID] = {cmdtype=commandType.idle, unreachable={}}
		end
		UpdateOneWorkerPathing(unitID) -- then precalculate pathing info
	end
end

-- This function cleans up when workers or building nanoframes are killed
function widget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam)
	if myUnits[unitID] then
		myUnits[unitID] = nil
		if busyUnits[unitID] then
			local key = busyUnits[unitID]
			myQueue[key].assignedUnits[unitID] = nil
			busyUnits[unitID] = nil
		end
	elseif activeJobs[unitID] then
		activeJobs[unitID] = nil
	elseif excludedUnits[unitID] then
		excludedUnits[unitID] = nil
	end
end

-- This function cleans up when workers or nanoframes are captured by an enemy
function widget:UnitTaken(unitID, unitDefID, unitTeam, newTeam)
	if myUnits[unitID] then
		myUnits[unitID] = nil
		if busyUnits[unitID] then
			local key = busyUnits[unitID]
			if myQueue[key] then
				myQueue[key].assignedUnits[unitID] = nil
			end
			busyUnits[unitID] = nil
		end
	elseif activeJobs[unitID] then
		local key = activeJobs[unitID]
		if myQueue[key] then
			StopAnyWorker(key)
			myQueue[key] = nil -- remove jobs from the queue when nanoframes are captured, since the job will be obstructed anyway
		end
		activeJobs[unitID] = nil
	end
end

-- This function implements auto-repair
function widget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID, attackerDefID, attackerTeam)
	if unitTeam == myTeamID and options.autoRepair.value then
		local myCmd = {id=40, target=unitID, assignedUnits={}}
		local hash = BuildHash(myCmd)
		if not myQueue[hash] then
			myQueue[hash] = myCmd
		end
	end
end

-- This function implements the constructor seperator, borrowed from the old "unit no stuck in factory" widget by msafwan
-- Note: Zero-K specific factDefIDs, customize if porting to another game!
function widget:UnitFromFactory(unitID, unitDefID, unitTeam, factID, factDefID, userOrders)
	if unitTeam == spGetMyTeamID() and UnitDefs[unitDefID].isBuilder and options.separateConstructors.value then -- if it's our unit, and is a builder, and constructor separator is enabled
		local facScale -- how far our unit will be told to move
		if queueCount == 0 then -- if the queue is empty, we need to increase clearance to stop the fac from getting jammed with idle workers
			facScale = 500
		elseif factDefID == 299 then -- boatfac, needs a huge clearance
			facScale = 250
		elseif factDefID == 295 then -- hoverfac, needs extra clearance
			facScale = 140
		else -- other facs
			facScale = 100
		end
		
		local dx,_,dz = spGetUnitDirection(unitID)
		local x,y,z = spGetUnitPosition(unitID)
		dx = dx*facScale
		dz = dz*facScale
		spGiveOrderToUnit(unitID, CMD_MOVE, {x+dx, y, z+dz}, {""}) -- replace the fac rally orders with a short distance move.
	end
end

--	If unit detected as idle and it's one of ours, mark it as idle so that it can be assigned work. Note: some ZK gadgets cause false positives for this, which is why we use deferred checks.
function widget:UnitIdle(unitID, unitDefID, teamID)
	if myUnits[unitID] then -- if it's one of ours
		idlers[#idlers+1] = unitID -- add it to the idle list to be double-checked at assignment time.
		idleCheck = true -- set the flag so that the idle list will be processed
		return
	end
end

--	A ZK compatibility function: receive broadcasted event from "unit_initial_queue.lua" (ZK specific) which 
function CommandNotifyPreQue(unitID)
	if myUnits[unitID] then
		myUnits[unitID].cmdtype = commandType.drec
	end
end

--	A ZK compatibility function: receive broadcasted event from "cmd_mex_placement.lua" (ZK specific) which notify us that it has its own mex queue
function CommandNotifyMex(id,params,options, isAreaMex)
	local groundHeight = spGetGroundHeight(params[1],params[3])
	params[2] = math.max(0, groundHeight)
	local returnValue = widget:CommandNotify(id, params, options, true, isAreaMex)
	return returnValue
end

-- A ZK compatibility function: recieves command events broadcast from "gui_lasso_terraform.lua"
function CommandNotifyTF(unitArray, params, shift)
	local ours = false -- ensure that the order was given to at least one unit that's in our group
	for i=1, #unitArray do
		local unitID = unitArray[i]
		if myUnits[unitID] then
			ours = true
			break
		end
	end
	if not ours then
	return false -- and stop here if not
	end
	
	local captureThis = false
	for i=1, #unitArray do
		local unitID = unitArray[i]
		if myUnits[unitID] then -- if it's one of our units
			if busyUnits[unitID] then -- if the worker is also still on our busy list
				local key = busyUnits[unitID]
				myQueue[key].assignedUnits[unitID] = nil -- remove it from its current job listing
				busyUnits[unitID] = nil -- and from busy units
			end
		
			if shift then -- if the command was given with shift
				spGiveOrderToUnit(unitID, CMD_TERRAFORM_INTERNAL, params, {""}) -- give the unit the TF order immediately so that it creates the 'terraunits'
				myUnits[unitID].cmdtype = commandType.idle -- mark it as idle so that it gets reassigned
				reassignedUnits[unitID] = nil -- ensure that it gets reassigned as soon as it creates the terraunits
				captureThis = true -- return true to tell gui_lasso_terraform that we handled the command externally
				nextFrame = nextFrame + 5 -- delay the next assignment frame slightly to ensure that the terraunit is created properly
				break -- we don't need to process more than one unit if shift was held
			else -- if the command was not given with shift
				myUnits[unitID].cmdtype = commandType.drec -- mark our unit as under direct orders and let gui_lasso_terraform handle it
				captureThis = false
			end
		end
	end
	return captureThis
end

-- ZK-Specific: This function captures combination raise-and-build commands
function CommandNotifyRaiseAndBuild(unitArray, cmdID, x, y, z, h, tfparams, shift)
	Spring.Echo("CommandNotifyRaiseAndBuild was Received!")
	local ours = false -- ensure that the order was given to at least one unit that's in our group
	for i=1, #unitArray do
		local unitID = unitArray[i]
		if myUnits[unitID] then
			ours = true
			break
		end
	end
	if not ours then
		return false -- and stop here if not
	end
	
	local captureThis = false
	local hotkey = string.byte("q")
	local isQ = spGetKeyState(hotkey)
	local myCmd
	if isQ then
		myCmd = {id=cmdID, x=x, y=y, z=z, h=h, tfparams=true, assignedUnits={}, q=true}
	else
		myCmd = {id=cmdID, x=x, y=y, z=z, h=h, tfparams=true, assignedUnits={}}
	end
	
	local hash = BuildHash(myCmd)
	
	if CleanOrders(myCmd, true) or not shift then
		myQueue[hash] = myCmd
		UpdateOneJobPathing(hash)
	end
	
	for i=1, #unitArray do
		local unitID = unitArray[i]
		if myUnits[unitID] then -- if it's one of our units
			if busyUnits[unitID] then -- if the worker is also still on our busy list
				local key = busyUnits[unitID]
				myQueue[key].assignedUnits[unitID] = nil -- remove it from its current job listing
				busyUnits[unitID] = nil -- and from busy units
			end
		
			if shift then -- if the command was given with shift
				spGiveOrderToUnit(unitID, CMD_TERRAFORM_INTERNAL, tfparams, {""}) -- give the unit the TF order immediately so that it creates the 'terraunits'
				myUnits[unitID].cmdtype = commandType.idle -- mark it as idle so that it gets reassigned
				reassignedUnits[unitID] = nil -- ensure that it gets reassigned as soon as it creates the terraunits
				captureThis = true -- return true to tell gui_lasso_terraform that we handled the command externally
				nextFrame = nextFrame + 5 -- delay the next assignment frame slightly to ensure that the terraunit is created properly
				break -- we don't need to process more than one unit if shift was held
			else -- if the command was not given with shift
			myUnits[unitID].cmdtype = commandType.drec -- mark our unit as under direct orders and let gui_lasso_terraform handle it
			captureThis = false
			end
		end
	end
	return captureThis
end

--  This function captures build-related commands given to units in our group and adds them to the queue, and also tracks unit state (ie direct orders vs queued).
--  Thanks to Niobium for pointing out CommandNotify().
function widget:CommandNotify(id, params, options, isZkMex, isAreaMex)
	if id < 0 and params[1]==nil and params[2]==nil and params[3]==nil then -- Global Build Command doesn't handle unit-build commands for factories.
		return
	end
	if options.meta then --skip special insert command (spacebar). Handled by CommandInsert() widget
		return
	end
	
	local selectedUnits = spGetSelectedUnits()
	for _, unitID in pairs(selectedUnits) do	-- check selected units...
		if myUnits[unitID] then	--  was issued to one of our units.
			if ( id < 0 ) then --if the order is for building something
				local hotkey = string.byte("q")
				local isQ = spGetKeyState(hotkey)
				local x, y, z, h = params[1], params[2], params[3], params[4]
				local myCmd
				if isQ then
					myCmd = {id=id, x=x, y=y, z=z, h=h, assignedUnits={}, q=true}
				else
					myCmd = {id=id, x=x, y=y, z=z, h=h, assignedUnits={}}
				end
				local hash = BuildHash(myCmd)
				if CleanOrders(myCmd, true) or not options.shift then -- check if the job site is obstructed, and clear up any other jobs that overlap.
					myQueue[hash] = myCmd	-- add it to queue if clear
					UpdateOneJobPathing(hash)
				end

				if ( options.shift ) then -- if the command was given with shift
					return true	-- we return true to take ownership of the command from Spring.
				else -- for direct orders
                    if busyUnits[unitID] then -- if our unit was interrupted by a direct order while performing a job
						myQueue[busyUnits[unitID]].assignedUnits[unitID] = nil -- remove it from the list of workers assigned to its previous job
					end
					busyUnits[unitID] = hash -- add the worker to our busy list
					myUnits[unitID].cmdtype = commandType.drec -- and mark it as under direct orders
					myQueue[hash].assignedUnits[unitID] = true -- add it to the assignment list for its new job
				end
			elseif id == 40 or id == 90 or id == 125 then -- if the command is for repair, reclaim or ressurect
				if #params > 1 then -- if the order is an area order
					local x, y, z, r = params[1], params[2], params[3], params[4]
					
					if id == 90 then -- check for specific unit reclaim
						local mx,my,mz = spWorldToScreenCoords(x, y, z) -- convert the center point to screen coords
						local cType,uid = spTraceScreenRay(mx,my) -- trace a screen ray back to see if it was placed on top of a unit
						if cType == "unit" and spGetUnitTeam(uid) == myTeamID then -- if it's a unit, and one of ours, then convert to specific unit reclaim
							local unitDefID = spGetUnitDefID(uid)
							ReclaimSpecificUnit(unitDefID, x, z, r, options.shift)
							return true -- capture the command regardless, since this can't easily be given as a direct order
						end
					end
						
					local myCmd = {}
					if options.alt then -- ZK-Specific Behavior: alt makes area jobs 'permanent', thus we need to record if it was used so we can maintain that behavior.
						-- note if you wanted to emulate this same behavior for some other game, it would require only a minor change to IdleCheck().
						myCmd = {id=id, x=x, y=y, z=z, r=r, alt=true, assignedUnits={}}
					else
						myCmd = {id=id, x=x, y=y, z=z, r=r, alt=false, assignedUnits={}}
					end
					local hash = BuildHash(myCmd)
					myQueue[hash] = myCmd -- add the job to the queue
					areaCmdList[hash] = myCmd -- and also to the area command update list, for capturing single targets.
					UpdateOneJobPathing(hash)
					if options.shift then -- for queued jobs
						return true -- capture the command
					else -- for direct orders
						if busyUnits[unitID] then -- if our unit was interrupted by a direct order while performing a job
							myQueue[busyUnits[unitID]].assignedUnits[unitID] = nil -- remove it from the list of workers assigned to its previous job
						end
						busyUnits[unitID] = hash -- add the worker to our busy list
						myUnits[unitID].cmdtype = commandType.drec -- and mark it as under direct orders
						myQueue[hash].assignedUnits[unitID] = true -- add it to the assignment list for its new job
					end
				else --otherwise if it was single-target
					local target = params[1]
					local x, y, z = 0
					local myCmd
					-- cache job position for features, since the targets are unlikely to move
					if target >= Game.maxUnits then -- if the target is a feature (such as a wreck)
						x, y, z = spGetFeaturePosition((target - Game.maxUnits)) -- translate targetID to featureID, get the position
						myCmd = {id=id, target=target, x=x, y=y, z=z, assignedUnits={}}
					else -- if the target is a unit
						myCmd = {id=id, target=target, assignedUnits={}}
					end
					
					local hash = BuildHash(myCmd)
					if not myQueue[hash] then -- if the job wasn't already on the queue
						myQueue[hash] = myCmd -- add the command to the queue
						if myCmd.x then -- if our target is not a unit
							UpdateOneJobPathing(hash) -- then cache pathing info
						end
					elseif options.shift then -- if it was already on the queue, and given with shift then cancel it
						StopAnyWorker(hash)
						myQueue[hash] = nil
					end
					
					-- note: area repair/reclaim/resurrect commands are add only, and do not cancel anything if used twice on the same targets.
					-- single-target repair/reclaim/resurrect commands on the other hand are add/cancel, as with other jobs.
					if options.shift then --and if the command was given with shift
						return true -- return true to capture it
					else
						if busyUnits[unitID] then -- if our unit was interrupted by a direct order while performing a job
							myQueue[busyUnits[unitID]].assignedUnits[unitID] = nil -- remove it from the list of workers assigned to its previous job
						end
						myUnits[unitID].cmdtype = commandType.drec -- otherwise mark it as under user direction
						busyUnits[unitID] = hash -- and add it to our busy list for cost calculations
						myQueue[hash].assignedUnits[unitID] = true
					end
				end
			else -- if the order is not for build-power related things, ex move orders
				myUnits[unitID].cmdtype = commandType.drec -- then the unit is just marked as under user direction and we let spring handle it.
				if busyUnits[unitID] then -- if our unit was interrupted by a direct non-build order while performing a job
					myQueue[busyUnits[unitID]].assignedUnits[unitID] = nil -- remove it from the list of workers assigned to its previous job
					busyUnits[unitID] = nil -- we remove it from the list of workers with building jobs
				end
			end
		end
	end
	return false
end


-- The following functions are used by the area job removal tool --
-------------------------------------------------------------------
-- This function gets the hotkey event for triggering the area job remove tool.
function widget:KeyPress(key, mods, isRepeat)
	local hotkey = string.byte("s")
	if key == hotkey and mods.alt then
		removeToolIsActive = true
	elseif key == KEYSYMS.ESCAPE and removeToolIsActive then
		removeToolIsActive = false
		selectionStarted = false
		selectionRadius = 0
		selectionCoords = {}
	end
end

function widget:KeyRelease(key)
	if hasBeenUsed and key == 304 then -- if shift is released and the command has been used at least once, cancel it.
		removeToolIsActive = false
		selectionStarted = false
		selectionRadius = 0
		selectionCoords = {}
		hasBeenUsed = false
	end
end

function widget:MousePress(x, y, button)
	if removeToolIsActive then
		local _, coords = spTraceScreenRay(x, y, true, true) -- get ground coords from mouse position
		if coords then -- nil check in case the mouse points to an area that does not refer to world-space
			local sx, sy, sz = coords[1], coords[2], coords[3]
			selectionCoords = {x=sx, y=sy, z=sz}
			selectionStarted = true
			return true
		end
	end
	return false
end
			
function widget:MouseMove(x, y, dx, dy, button)
	if selectionStarted then
		local _, coords = spTraceScreenRay(x, y, true, true) -- get ground coords from mouse position
		if coords then
			local sx, sz = coords[1], coords[3]
			selectionRadius = Distance(sx, sz, selectionCoords.x, selectionCoords.z)
		end
	end
end

function widget:MouseRelease(x, y, button)
	if selectionStarted then
		local alt, ctrl, meta, shift = spGetModKeyState()
		local _, coords = spTraceScreenRay(x, y, true, true) -- get ground coords from mouse position
		if coords then
			local sx, sz = coords[1], coords[3]
			selectionRadius = Distance(sx, sz, selectionCoords.x, selectionCoords.z)
		end
		
		if selectionRadius > 0 then -- if we have a real selection, call RemoveJobs
			RemoveJobs(selectionCoords.x, selectionCoords.z, selectionRadius)
		end
		
		selectionStarted = false
		selectionRadius = 0
		selectionCoords = {}
		spPlaySoundFile("sounds/reply/builder_start.wav", 1) -- Note: Zero-K Specific sound. Customize if porting!
		
		if not shift then
			removeToolIsActive = false
			hasBeenUsed = false
		else
			hasBeenUsed = true
			return true
		end
	end
	return false
end
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Core Logic ------------------------------------------------------------------

--[[
HOW THIS WORKS:
	FindEligibleWorker() 
		Sorts through our group and returns a list of workers to be assigned,
		ensuring that we cycle through all workers (more or less) evenly. Does not consider workers that are under direct orders.
	GiveWorkToUnits()
		Iterates over the list returned by FindEligibleWorker(), calling FindCheapestJob() for each,
		and if FindCheapestJob() returns a job it gives the command to the worker and updates relevant info.
	FindCheapestJob()
		For a given worker as input, iterates over myQueue, checking each job to see if the worker can build and reach it,
		and if so calls CostOfJob() for each job to get the cost.
		It caches the cheapest job it finds and returns it after iterating over all jobs.
	CostOfJob()
		Implements the cost model used to find the cheapest job, and can be modified,
		extended or replaced to adjust the assignment behavior. (or if porting)
	CheckForRes()
		Determines if any of the units in our group can use resurrect, and sets a global flag.
	UpdateAreaCommands()
		Calls SplitAreaCommand for each area command on the queue, if the splitArea option is enabled.
	SplitAreaCommand()
		Captures individual targets from area repair/reclaim/resurrect orders and adds them to the queue as they enter LOS.
	CleanWrecks()
		Captures ALL wreckage/debris/eggs that fall into los, and implements the auto-reclaim-res feature. Ignores map features.
	CheckIdlers()
		Processes units that had UnitIdle called on them to ensure that they were really idle, and does cleanup for jobs such as
		area commands where there's no other way to tell if the job is done.
	CaptureTF()
		ZK-Specific, locates 'terraunits' that mark terraform points and adds repair jobs for them.
	CleanOrders()
		Takes a build command as input, and checks the build site for blockage or overlap with existing jobs,
		then removes any jobs that are blocked, finished, invalid or conflicting.
]]--


-- This function returns a list of workers from our group to be assigned/reassigned jobs.
function FindEligibleWorker()
	local unitsToWork = {}
	local gaveWork = false
	for unitID,myCmd in pairs(myUnits) do
		if myCmd.cmdtype == commandType.idle then -- first we assign idle units
			if #unitsToWork < 25 and (not reassignedUnits[unitID]) then
				--NOTE: we limit the number of workers processed per cycle since the main loop is triple-nested and may reach very large iteration counts.
				unitsToWork[#unitsToWork+1] = unitID
				reassignedUnits[unitID] = true
				gaveWork = true
			end
		end
	end
	--if we still have room after assigning idle workers then we can mark queue-assigned workers to be reassigned in case lower cost jobs become available.
	if #unitsToWork < 25 then
		for unitID,cmdstate in pairs(myUnits) do
			if (not reassignedUnits[unitID]) then
				if cmdstate.cmdtype == commandType.buildQueue then
					unitsToWork[#unitsToWork+1] = unitID
					gaveWork = true
					reassignedUnits[unitID] = true
					if (#unitsToWork == 25) then
						break
					end
				end
			end
		end
		if not gaveWork then --no more unit to be reassigned? then reset list
			reassignedUnits = {}
		end
	end
	return unitsToWork
end

-- This function finds work for all the workers compiled in our eligible worker list and issues the orders.
function GiveWorkToUnits(unitsToWork)
	for i=1, #unitsToWork do
		local unitID = unitsToWork[i]
		local myJob = FindCheapestJob(unitID) -- find the cheapest job
		if myJob and (not busyUnits[unitID] or busyUnits[unitID] ~= hash) then -- if myJob returns a job rather than nil
		-- if the unit has already been assigned to the same job, we also prevent order spam
		-- note, order spam stops workers from moving other workers out of the way if they're standing on each other's jobs, and also causes network spam and path-calculation spam.
			local hash = BuildHash(myJob)
			if busyUnits[unitID] then -- if we're reassigning, we need to update the entry stored in the queue
				key = busyUnits[unitID]
				myQueue[key].assignedUnits[unitID] = nil
			end
			if myJob.id < 0 then -- for build jobs
				if not myJob.tfparams then -- for normal build jobs, ZK-specific guard, remove if porting
					spGiveOrderToUnit(unitID, myJob.id, {myJob.x, myJob.y, myJob.z, myJob.h}, {""}) -- issue the cheapest job as an order to the unit
					busyUnits[unitID] = hash -- save the command info for bookkeeping
					myUnits[unitID].cmdtype = commandType.buildQueue -- and mark the unit as under CB control.
					myQueue[hash].assignedUnits[unitID] = true -- save info for CostOfJob and StopAnyWorker
				else -- ZK-Specific: for combination raise-and-build jobs
					local localUnits = spGetUnitsInCylinder(myJob.x, myJob.z, 200)
					for i=1, #localUnits do -- locate the 'terraunit' if it still exists, and give a repair order for it
						local target = localUnits[i]
						local udid = spGetUnitDefID(target)
						local unitDef = UnitDefs[udid]
						if string.match(unitDef.humanName, "erraform") ~= nil and spGetUnitTeam(target) == myTeamID then
							spGiveOrderToUnit(unitID, CMD_REPAIR, {target}, {""})
							break
						end
					end
					spGiveOrderToUnit(unitID, myJob.id, {myJob.x, myJob.y, myJob.z, myJob.h}, {"shift"}) -- add the build part of the command to the end of the queue with options shift
					busyUnits[unitID] = hash -- save the command info for bookkeeping
					myUnits[unitID].cmdtype = commandType.buildQueue -- and mark the unit as under CB control.
					myQueue[hash].assignedUnits[unitID] = true
				end -- end zk-specific guard
			else -- for repair/reclaim/resurrect
				if not myJob.target then -- for area commands
					if not spIsPosInLos(myJob.x, myJob.y, myJob.z, spGetMyAllyTeamID()) then -- if the job is outside of LOS, we need to convert it to a move command or else the units won't bother exploring it.
						spGiveOrderToUnit(unitID, CMD_MOVE, {myJob.x, myJob.y, myJob.z}, {""})
						if myJob.alt then -- if alt was held, the job should remain 'permanent'
							spGiveOrderToUnit(unitID, myJob.id, {myJob.x, myJob.y, myJob.z, myJob.r}, {"alt", "shift"})
						else -- for normal area jobs
							spGiveOrderToUnit(unitID, myJob.id, {myJob.x, myJob.y, myJob.z, myJob.r}, {"shift"}) -- note: we add options->shift here to add our reclaim job to the unit's queue after the move order, to prevent it from falsely going idle.
						end
					elseif myJob.alt then -- if alt was held, the job should remain 'permanent'
						spGiveOrderToUnit(unitID, myJob.id, {myJob.x, myJob.y, myJob.z, myJob.r}, {"alt"})
					else -- for normal area jobs
						spGiveOrderToUnit(unitID, myJob.id, {myJob.x, myJob.y, myJob.z, myJob.r}, {""})
					end
					busyUnits[unitID] = hash -- save the command info for bookkeeping
					myUnits[unitID].cmdtype = commandType.buildQueue -- and mark the unit as under CB control.
					myQueue[hash].assignedUnits[unitID] = true
				else -- for single-target commands
					spGiveOrderToUnit(unitID, myJob.id, {myJob.target}, {""}) -- issue the cheapest job as an order to the unit
					busyUnits[unitID] = hash -- save the command info for bookkeeping
					myUnits[unitID].cmdtype = commandType.buildQueue -- and mark the unit as under CB control.
					myQueue[hash].assignedUnits[unitID] = true
				end
			end
		elseif not myJob then
			myUnits[unitID].cmdtype = commandType.idle -- otherwise if no valid job is found mark it as idle
		end
	end
end

-- This function returns the cheapest job for a given worker, given the cost model implemented in CostOfJob(). 
function FindCheapestJob(unitID)
    local cachedJob = nil -- the cheapest job that we've seen
    local cachedCost = 0 -- the cost of the currently cached cheapest job
    local ux, uy, uz = spGetUnitPosition(unitID)	-- unit location
    
    -- if the worker has already been assigned to a job, we cache it first to increase job 'stickiness'
    if busyUnits[unitID] then
		local key = busyUnits[unitID]
		local jx, jy, jz
		cachedJob = myQueue[key]
		
		if not cachedJob then
			Echo("Global Build Command: Invalid Job:" .. key)
		end
		
		if cachedJob.x then -- for jobs with explicit locations, or for which we've cached locations
			jx, jy, jz = cachedJob.x, cachedJob.y, cachedJob.z --the location of the current job
		else -- for repair jobs and reclaim jobs targetting units
			jx, jy, jz = spGetUnitPosition(cachedJob.target)
		end
		
		local unitDefID = spGetUnitDefID(unitID)
		local buildDist = UnitDefs[unitDefID].buildDistance
		local moveID = UnitDefs[unitDefID].moveDef.id
		
		if moveID then -- for ground units, just cache the cost
			if options.intelliCost.value then
				cachedCost = IntelliCost(unitID, key, ux, uz, jx, jz)
			else
				cachedCost = FlatCost(unitID, key, ux, uz, jx, jz)
			end
		else -- for air units, reduce the cost of their current job since they tend to wander around while building
			if options.intelliCost.value then
				cachedCost = IntelliCost(unitID, key, ux, uz, jx, jz) - (buildDist + 40)
			else
				cachedCost = FlatCost(unitID, key, ux, uz, jx, jz) - (buildDist + 40)
			end
		end
	end
   
	for hash, tmpJob in pairs(myQueue) do -- here we compare our unit to each job in the queue
		local cmd = tmpJob.id
		local jx, jy, jz
		
		if tmpJob.target and tmpJob.target == unitID then
		-- ignore self-targetting commands
		else
			-- get job position
			if tmpJob.x then -- for jobs with explicit locations, or for which we've cached locations
				jx, jy, jz = tmpJob.x, tmpJob.y, tmpJob.z --the location of the current job
			else -- for repair jobs and reclaim jobs targetting units
				jx, jy, jz = spGetUnitPosition(tmpJob.target)
			end
        
			-- check pathing and/or whether the worker can build the job or not (stored in the same key)
			local isReachableAndBuildable = true
			if myUnits[unitID].unreachable[hash] then -- check cached values
				isReachableAndBuildable = false
			elseif not tmpJob.x and not IsTargetReachable(unitID, jx, jy, jz) then -- for jobs targetting units, which may be mobile, always calculate pathing.
				isReachableAndBuildable = false
			end
			
			if isReachableAndBuildable then
				local tmpCost -- calculate the job cost, depending on the cost model the user has chosen
				if options.intelliCost.value then
					tmpCost = IntelliCost(unitID, hash, ux, uz, jx, jz)
				else
					tmpCost = FlatCost(unitID, hash, ux, uz, jx, jz)
				end
				if not cachedJob or tmpCost < cachedCost then -- then if there is no cached job or if tmpJob is cheaper, replace the cached job with tmpJob and update the cost
					cachedJob = tmpJob
					cachedCost = tmpCost
				end
			end
		end
	end
    return cachedJob -- after iterating over the entire queue, the resulting cached job will be the cheapest, return it.
end       
                    
-- This function implements the 'intelligent' cost model for assigning jobs.
function IntelliCost(unitID, hash, ux, uz, jx, jz)
	local job = myQueue[hash]
    local distance = Distance(ux, uz, jx, jz) -- the distance between our worker and job
    
    local costMod = 1 -- our cost modifier, the number of other units assigned to the same job + 1.
    
    -- note we only count workers that are roughly closer/equal distance to the job,
    -- so that can achieve both "find the job closest to worker x" and "find the worker closest to their job"
    -- at the same time. You probably should not change this, since it accounts for a lot of edge cases
    -- but does not directly determine the behavior.
	for unit,_ in pairs(job.assignedUnits) do -- for all units that have been recorded as assigned to this job
		if ( unitID ~= unit) and spValidUnitID(unit) then -- excluding our current worker.
			local ix, _, iz = spGetUnitPosition(unit)
			local idist = Distance(ix, iz, jx, jz)
			local rdist = max(distance, 200) -- round distance up to 200, to equalize priority at small distances
			local deltadist = abs(idist - distance) -- calculate the absolute difference in distance, for considering large distances
			if idist < rdist or (distance > 500 and deltadist < 500) then -- and for each one that is rounded closer/equal-dist to the job vs our worker, we increment our cost weight.
				costMod = costMod + 1 -- this way we naturally prioritize closer workers so that more distant workers won't kick us off an otherwise efficient job.
			end
		end
	end
	
	-- The following cost calculation produces a number of different effects:
	
	-- It prioritizes small defenses highly, and encourages two workers per small defense structure.
	-- This is to improve worker safety and deter light raiding more effectively.
	
	-- Small energy is penalized slightly to encourage workers to cap mexes consistently earlier when expanding.
	
	-- Expensive jobs have an initial starting penalty, which disappears once a worker has been assigned
	-- to that job, and after that there is no penalty for additional mobbing so that the jobs are
	-- generally guaranteed to finish quickly once started.
	
	-- Resurrect always has a high priority and no mobbing penalty, due to its exclusivity.
	
	-- Repair and reclaim have the same cost penalty as for starting expensive jobs,
	-- but the second worker on those jobs is free. This is mainly to prevent workers
	-- from trampling trees that other workers are trying to reclaim, but also works
	-- well for repair since mobbing is usually beneficial for that. It also helps
	-- to keep workers from advancing too far ahead of your combat units when
	-- reclaiming wreckage, and reclaim also helps to distract workers from following
	-- combat units into the enemy's base trying to repair them.
	
	-- If you want to change the assignment behavior, the stuff below is what you should edit.
	-- Note that cost represents a distance, which is why cost modifiers use addition,
	-- and the 'magic constants' for that were chosen based on typical map scaling.
	-- Metal cost for "expensive" jobs is also based on Zero-K scaling, so you may want to adjust that if porting.
	-- FindCheapestJob() always chooses the shortest apparent distance, so smaller cost values mean higher priority.
	
	local cost
	local unitDef = UnitDefs[abs(job.id)]
	local metalCost = false
	
	if job.id < 0 then -- for build jobs, get the metal cost
		metalCost = unitDef.cost
	end
	
	if costMod == 1 then -- for starting new jobs
		if (metalCost and metalCost > 300) or job.id == 40 or job.id == 90 then -- for expensive jobs, repair and reclaim
			cost = distance + 400
		elseif unitDef.reloadTime > 0 or job.id == 125 then -- for small defenses and resurrect
			cost = distance - 150
		elseif string.match(unitDef.humanName, "Solar") or string.match(unitDef.humanName, "Wind") then -- for small energy
			cost = distance + 100
		else -- for resurrect and all other small build jobs
			cost = distance
		end
	else -- for assisting other workers
		if (metalCost and metalCost > 300) or job.id == 125 then -- for expensive buildings and resurrect
			cost = distance
		elseif unitDef.reloadTime > 0 then -- for small defenses, allow up to two workers before increasing cost
			cost = distance - 150 + (800 * (costMod - 2))
		elseif job.id == 40 or job.id == 90 then -- for repair and reclaim
			cost = distance + (200 * costMod)
		else -- for all other small build jobs
			cost = distance + (600 * costMod)
		end
	end
	return cost
end                 

-- This function implements the 'flat' cost model for assigning jobs.
function FlatCost(unitID, hash, ux, uz, jx, jz)
	local job = myQueue[hash]
    local distance = Distance(ux, uz, jx, jz) -- the distance between our worker and job
    
    local costMod = 1 -- our cost modifier, the number of other units assigned to the same job + 1.
    
    -- note we only count workers that are roughly closer/equal distance to the job,
    -- so that can achieve both "find the job closest to worker x" and "find the worker closest to their job"
    -- at the same time. You probably should not change this, since it accounts for a lot of edge cases
    -- but does not directly determine the behavior.
	for unit,_ in pairs(job.assignedUnits) do -- for all units that have been recorded as assigned to this job
		if ( unitID ~= unit) and spValidUnitID(unit) then -- excluding our current worker.
			local ix, _, iz = spGetUnitPosition(unit)
			local idist = Distance(ix, iz, jx, jz)
			local rdist = max(distance, 200) -- round distance up to 200, to equalize priority at small distances
			local deltadist = abs(idist - distance) -- calculate the absolute difference in distance, for considering large distances
			if idist < rdist or (distance > 500 and deltadist < 500) then -- and for each one that is rounded closer/equal-dist to the job vs our worker, we increment our cost weight.
				costMod = costMod + 1 -- this way we naturally prioritize closer workers so that more distant workers won't kick us off an otherwise efficient job.
			end
		end
	end
	
	-- The goal of the flat cost model is to provide consistent behavior that is easily directed
	-- by the player's actions.
	
	-- Repair, reclaim and resurrect are the same as for intellicost.
	
	-- All build jobs are cost=distance for starting new jobs.
	
	-- Expensive jobs have no mobbing penalty, while small defenses
	-- allow up to 2 workers per job before the cost increases.
	
	-- all other small jobs have a high penalty for assisting.
	
	-- If you want to change the assignment behavior, the stuff below is what you should edit.
	-- Note that cost represents a distance, which is why cost modifiers use addition,
	-- and the 'magic constants' for that were chosen based on typical map scaling.
	-- Metal cost for "expensive" jobs is also based on Zero-K scaling, so you may want to adjust that if porting.
	-- FindCheapestJob() always chooses the shortest apparent distance, so smaller cost values mean higher priority.
	
	local cost
	local unitDef = UnitDefs[abs(job.id)]
	local metalCost = false
	
	if job.id < 0 then -- for build jobs, get the metal cost
		metalCost = unitDef.cost
	end
	
	if costMod == 1 then -- for starting new jobs
		if job.id == 40 or job.id == 90 then -- for repair and reclaim
			cost = distance + 400
		else -- for everything else
			cost = distance
		end
	else -- for assisting other workers
		if (metalCost and metalCost > 300) or job.id == 125 then -- for expensive jobs and resurrect, no mobbing penalty
			cost = distance
		elseif unitDef.reloadTime > 0 then -- for small defenses, allow up to two workers before increasing cost
			cost = distance + (800 * (costMod - 2))
		elseif job.id == 40 or job.id == 90 then -- for repair and reclaim
			cost = distance + (200 * costMod)
		else 
			cost = distance + (600 * costMod) -- for all other jobs, assist is expensive
		end
	end
	return cost
end

-- This function checks if our group includes a unit that can resurrect
function CheckForRes()
	hasRes = false -- check whether the player has any units that can res
	for unitID, _ in pairs(myUnits) do
		local udid = spGetUnitDefID(unitID)
		if UnitDefs[udid].canResurrect then
			hasRes = true
			break
		end
	end
end

-- This function updates area commands and captures individual targets as they fall into LOS.
function UpdateAreaCommands()
	for _, cmd in pairs(areaCmdList) do -- update area commands as new targets fall into LOS
		SplitAreaCommand(cmd.id, cmd.x, cmd.z, cmd.r)
	end
end

-- This function splits area repair/reclaim/resurrect commands into single-target commands so that we can assign workers to them more efficiently.
function SplitAreaCommand(id, x, z, r)
	if id == 40 then -- for repair commands
		local unitList = spGetUnitsInCylinder(x, z, r*1.1)
		for i=1, #unitList do -- for all units in our selected area
			local unitID = unitList[i]
			local hp, maxhp, _, _, _ = spGetUnitHealth(unitID)
			if hp ~= maxhp and spIsUnitAllied(unitID) then -- if the unit is damaged, allied, and alive
				local myCmd = {id=id, target=unitID, assignedUnits={}}
				local hash = BuildHash(myCmd)
				if not myQueue[hash] then -- if the job isn't already on the queue, add it.
					myQueue[hash] = myCmd -- note: this is to prevent assignedUnits from being invalidated
					-- note we don't cache pathing for repair jobs, since they may target mobile units with varying pathing types
				end
			end
		end
	elseif id == 90 then -- else for reclaim
		local featureList = spGetFeaturesInCylinder(x, z, r*1.1)
		for i=1, #featureList do
			local featureID = featureList[i]
			local fdef = spGetFeatureDefID(featureID)
			if FeatureDefs[fdef].reclaimable then -- if it's reclaimable
				local target = featureID + Game.maxUnits -- convert FeatureID to absoluteID for spGiveOrderToUnit
				local tx, ty, tz = spGetFeaturePosition(featureID)
				local myCmd = {id=id, target=target, x=tx, y=ty, z=tz, assignedUnits={}} -- construct a new command
				local hash = BuildHash(myCmd)
				if not myQueue[hash] then -- if the job isn't already on the queue, add it.
					myQueue[hash] = myCmd -- note: this is to prevent assignedUnits from being invalidated
					UpdateOneJobPathing(hash)
				end
			end
		end
	else -- else for resurrect
		local featureList = spGetFeaturesInCylinder(x, z, r*1.1)
		for i=1, #featureList do -- for each feature in our selection area
			local featureID = featureList[i]
			local fdef = spGetFeatureDefID(featureID)
			local thisfeature = FeatureDefs[fdef]
			if string.match(thisfeature["tooltip"], "reck") then -- if it's resurrectable
				local target = featureID + Game.maxUnits -- convert featureID to absoluteID for spGiveOrderToUnit
				local tx, ty, tz = spGetFeaturePosition(featureID)
				local myCmd = {id=id, target=target, x=tx, y=ty, z=tz, assignedUnits={}} -- construct a new command
				local hash = BuildHash(myCmd)
				if not myQueue[hash] then -- if the job isn't already on the queue, add it.
					myQueue[hash] = myCmd -- note: this is to prevent assignedUnits from being invalidated
					UpdateOneJobPathing(hash)
				end
			elseif FeatureDefs[fdef].reclaimable and options.autoConvertRes.value then -- otherwise if it's reclaimable, and res-conversion is enabled convert to a reclaim order
				local target = featureID + Game.maxUnits -- convert featureID to absoluteID for spGiveOrderToUnit
				local tx, ty, tz = spGetFeaturePosition(featureID)
				local myCmd = {id=90, target=target, x=tx, y=ty, z=tz, assignedUnits={}} -- construct a new command
				local hash = BuildHash(myCmd)
				if not myQueue[hash] then -- if the job isn't already on the queue, add it.
					myQueue[hash] = myCmd -- note: this is to prevent assignedUnits from being invalidated
					UpdateOneJobPathing(hash)
				end
			end
		end
	end
end

-- This function implements specific-unit reclaim
function ReclaimSpecificUnit(unitDefID, x, z, r, shift)
	local targets = spGetUnitsInCylinder(x, z, r)
	
	for i=1, #targets do -- identify all the intended targets and add them to the queue
		local target = targets[i]
		if spGetUnitDefID(target) == unitDefID and spGetUnitTeam(target) == myTeamID then -- if the unit is ours and of the specified type
		-- note: the "is ours" part can be removed for games that allow reclaiming the enemy
			local myCmd = {id=90, target=target, assignedUnits={}}
			local hash = BuildHash(myCmd)
			if not myQueue[hash] then -- build a new command and add it to the queue if it isn't already
				myQueue[hash] = myCmd
			end
		end
	end
end

-- This function double checks units marked idle to ensure that they actually don't have any commands, then officially marks them idle if not.
function CheckIdlers()
	for i=1, #idlers do
		local unitID = idlers[i]
		if myUnits[unitID] then -- we need to ensure that the unit hasn't died or left the group since it went idle, because this check is deferred
			local cmd1 = GetFirstCommand(unitID) -- we need to check that the unit's command queue is empty, because other gadgets may invoke UnitIdle erroneously.
			if ( cmd1 and cmd1.id) then 
			-- if there's a command on the queue, do nothing and let it be removed from the idle list.
			else -- otherwise if the unit is really idle
				myUnits[unitID].cmdtype = commandType.idle -- then mark it as idle
				reassignedUnits[unitID] = nil
				if busyUnits[unitID] then -- if the worker is also still on our busy list
					local key = busyUnits[unitID]
					if areaCmdList[key] then -- if it was an area command
						areaCmdList[key] = nil -- remove it from the area update list
						StopAnyWorker(key)
						myQueue[key] = nil -- remove the job from the queue, since UnitIdle is the only way to tell completeness for area jobs.
						busyUnits[unitID] = nil
					end
				end
			end
		end
	end
	idlers = {} -- clear the idle list, since we've processed it.
	idleCheck = false -- reset the flag
end

--This function captures res/reclaim targets near the player's base/workers.
function CleanWrecks()
	local featureList = spGetAllFeatures() -- returns all features in LOS, as well as all map features, which we ignore here because they may cause units to suicide into enemy territory.
	
	if hasRes and options.autoConvertRes.value then
		for i=1, #featureList do
			local featureID = featureList[i]
			local fdef = spGetFeatureDefID(featureID)
			local thisfeature = FeatureDefs[fdef]
			if string.match(thisfeature["tooltip"], "reck") then -- if it's resurrectable
				local target = featureID + Game.maxUnits -- convert featureID to absoluteID for spGiveOrderToUnit
				local tx, ty, tz = spGetFeaturePosition(featureID)
				local myCmd = {id=125, target=target, x=tx, y=ty, z=tz, assignedUnits={}} -- construct a new command
				local hash = BuildHash(myCmd)
				if not myQueue[hash] then -- if the job isn't already on the queue, add it.
					myQueue[hash] = myCmd -- note: this is to prevent assignedUnits from being invalidated
					UpdateOneJobPathing(hash) -- and to prevent redundant pathing calculations
				end
			elseif string.match(thisfeature["tooltip"], "ebris") or string.match(thisfeature["tooltip"], "Egg") then -- otherwise if it's a reclaimable wreck
				local target = featureID + Game.maxUnits -- convert featureID to absoluteID for spGiveOrderToUnit
				local tx, ty, tz = spGetFeaturePosition(featureID)
				local myCmd = {id=90, target=target, x=tx, y=ty, z=tz, assignedUnits={}} -- construct a new command
				local hash = BuildHash(myCmd)
				if not myQueue[hash] then -- if the job isn't already on the queue, add it.
					myQueue[hash] = myCmd -- note: this is to prevent assignedUnits from being invalidated
					UpdateOneJobPathing(hash)
				end
			end
		end
	else
		for i=1, #featureList do
			local featureID = featureList[i]
			local fdef = spGetFeatureDefID(featureID)
			local thisfeature = FeatureDefs[fdef]
		
			if string.match(thisfeature["tooltip"], "ebris") or string.match(thisfeature["tooltip"], "Egg") or string.match(thisfeature["tooltip"], "reck") then -- if it's a non-map-feature reclaimable
				local target = featureID + Game.maxUnits -- convert featureID to absoluteID for spGiveOrderToUnit
				local tx, ty, tz = spGetFeaturePosition(featureID)
				local myCmd = {id=90, target=target, x=tx, y=ty, z=tz, assignedUnits={}} -- construct a new command
				local hash = BuildHash(myCmd)
				if not myQueue[hash] then -- if the job isn't already on the queue, add it.
					myQueue[hash] = myCmd -- note: this is to prevent assignedUnits from being invalidated
					UpdateOneJobPathing(hash)
				end
			end
		end
	end
end

-- ZK-Specific: Adds repair commands for 'terraunits'
function CaptureTF()
	local teamUnits = spGetTeamUnits(myTeamID) -- get all of the player's units
	for i=1, #teamUnits do
		unitID = teamUnits[i]
		unitDID = spGetUnitDefID(unitID)
		unitDef = UnitDefs[unitDID]
		if string.match(unitDef.humanName, "erraform") then -- identify 'terraunits'
			local myCmd = {id=40, target=unitID, assignedUnits={}}
			local hash = BuildHash(myCmd)
			if not myQueue[hash] then -- add repair jobs for them if they're not already on the queue
				myQueue[hash] = myCmd
			end
		end
	end
end

-- This function removes dead/captured constructors from myUnits, needed because Spring calls widget:GameFrame before anything else.
function CleanBuilders()
	for unitID,_ in pairs(myUnits) do
		if not spValidUnitID(unitID) or spUnitIsDead(unitID) or spGetUnitTeam(unitID) ~= myTeamID then
		-- if a unit does not exist, is dead, or no longer belongs to our team..
			if busyUnits[unitID] then -- if the unit has an assigned job, update bookkeeping
				myJob = busyUnits[unitID]
				myQueue[myJob].assignedUnits[unitID] = nil
				busyUnits[unitID] = nil
			end
			myUnits[unitID] = nil -- remove the unit from the list of constructors
		end
	end
end

-- This function removes workers from the busy list in the case that the job the worker is assigned to does not actually exist.
-- It is unclear why this happens, but it is known to cause crashes.
function CleanBusy()
	for unitID, key in pairs(busyUnits) do
		if not myQueue[key] then
			Spring.Echo("GBC: A busy unit was found with a nonexistent job: " .. key)
			busyUnits[unitID] = nil
		end
	end
end

-- This function removes duplicate orders, processes cancel requests, and handles blocked builds. Returns true when a job site is clean or cleanable, false otherwise.
function CleanOrders(cmd, isNew)
	local isClear = true
	local hash = BuildHash(cmd)
	if cmd.id < 0 then -- for build orders
		local xSize = nil --variables for checking queue overlaping
		local zSize = nil
		local isNano = false
		local isObstructed = false
	
		local blockageType = {
			obstructed = 0, --also applies to blocked by another structure
			mobiles = 1,
			free = 2
		}
	
	
		local cmdID = abs(cmd.id)
		local cx = cmd.x
		local cy = cmd.y
		local cz = cmd.z
		local ch = cmd.h -- building facing
		
		if ch == 0 or ch == 2 then --get building facing. Reference: unit_prevent_lab_hax.lua by googlefrog
			xSize = UnitDefs[cmdID].xsize*4
			zSize = UnitDefs[cmdID].zsize*4
		else
			xSize = UnitDefs[cmdID].zsize*4
			zSize = UnitDefs[cmdID].xsize*4
		end

		local canBuildThisThere,_ = spTestBuildOrder(cmdID,cx,cy,cz,ch) --check if build site is blocked by buildings & terrain
	
		if canBuildThisThere == blockageType.free then -- if our job is not obstructed by anything
		-- do nothing, leave isClear set to true.
		else -- otherwise if our job is blocked by something
			local r = ( sqrt(xSize^2+zSize^2) /2 )+75 -- convert the rectangular diagonal into a radius, buffer it for increased reliability with small buildings.
			local blockingUnits = spGetUnitsInCylinder(cx+(xSize/2), cz+(zSize/2), r)
			for i=1, #blockingUnits do
				local blockerID = blockingUnits[i]
				local blockerDefID = spGetUnitDefID(blockerID)
				if blockerDefID == cmdID and myTeamID == spGetUnitTeam(blockerID) then -- if the blocker matches the building we're trying to build, and is ours
					local _,_,nanoframe = spGetUnitIsStunned(blockerID) -- determine if it's still under construction
					if nanoframe then
						isNano = true -- set isNano to true so that it will not be removed.
					else -- otherwise the job is finished, and we should garbage collect activeJobs
						activeJobs[blockerID] = nil -- note this only stops a tiny space leak should a free starting fac be added to the queue
						-- but it was cheap, so whatever.
					end
				elseif canBuildThisThere == blockageType.mobiles and myUnits[blockerID] and UnitDefs[blockerDefID].moveDef.id and myUnits[blockerID].cmdtype ~= commandType.drec and not IsEmpty(cmd.assignedUnits) then
				-- if blocked by a mobile unit, and it's one of our constructors, and not a flying unit, and it's not under direct orders, and there's actually a worker assigned to the job...
					local x,y,z = spGetUnitPosition(blockerID)
					local dx, dz = GetNormalizedDirection(cx, cz, x, z) 
					dx = dx*50
					dz = dz*50
					spGiveOrderToUnit(blockerID, CMD_MOVE, {x+dx, y, z+dz}, {""}) -- move it out of the way
					myUnits[blockerID].cmdtype = commandType.mov -- and mark it with a special state so the move order doesn't get clobbered
					if busyUnits[blockerID] then -- also remove it from busyUnits if necessary, and remove its assignment listing from myQueue
						key = busyUnits[blockerID]
						myQueue[key].assignedUnits[blockerID] = nil
						busyUnits[blockerID] = nil
					end
				end
			end
			
			if canBuildThisThere == blockageType.obstructed and not isNano then -- terrain or other un-clearable obstruction is blocking, mark as obstructed.
					isObstructed = true
			end
		
			if isObstructed and not isNano then -- note, we need to wait until ALL obstructions have been accounted for before cleaning up blocked jobs, or else we may not correctly identify the nanoframe if it's the main obstructor.
				if myQueue[hash] then
					StopAnyWorker(hash)
					myQueue[hash] = nil
				end
				isClear = false
			end
		end
		
		if isNew and isClear then -- if the job we're checking is new and the construction site is clear, then we need to check for overlap with existing jobs and remove any that are in the way.
			for key,qcmd in pairs(myQueue) do
				if qcmd.id < 0 then -- if the command we're looking at is actually a build order
					local x, z, h = qcmd.x, qcmd.z, qcmd.h
					local xSize_queue = nil
					local zSize_queue = nil
					
					local aqcmd = abs(qcmd.id)
			
					
					if h == 0 or h == 2 then --get building facing for queued jobs. Reference: unit_prevent_lab_hax.lua by googlefrog
						xSize_queue = UnitDefs[aqcmd].xsize*4
						zSize_queue = UnitDefs[aqcmd].zsize*4
					else
						xSize_queue = UnitDefs[aqcmd].zsize*4
						zSize_queue = UnitDefs[aqcmd].xsize*4
					end
		
					local minTolerance = xSize_queue + xSize -- check minimum tolerance in x direction
					local axisDist = abs (x - cx) -- check actual separation in x direction
					if axisDist < minTolerance then -- if too close in x direction
						minTolerance = zSize_queue + zSize -- check minimum tolerance in z direction
						axisDist = abs (z - cz) -- check actual separation in z direction
						if axisDist < minTolerance then -- if too close in z direction
							-- then there is overlap and we should remove the old job from the queue.
							StopAnyWorker(key)
							myQueue[key] = nil
							isClear = false
						end
					end
				end
			end
		end
	elseif cmd.target then -- for repair, reclaim and resurrect orders that are not area orders
		if cmd.id == 40 then -- for repair orders
			local target = cmd.target
			local good = false
		
			if spValidUnitID(target) and spIsUnitAllied(target) then -- if the unit still exists, and hasn't been captured
				local hp, maxhp, _, _, _= spGetUnitHealth(target) -- get the unit hp
				local _,_,isNano = spGetUnitIsStunned(target) -- and determine if it's still under construction (note: this is an annoying edge case)
				if hp ~= maxhp or isNano then -- if our target is still damaged or under construction
					good = true
				end
			end
			if not good then -- if our target is no longer valid, or has full hp
				StopAnyWorker(hash)
				myQueue[hash] = nil
				isClear = false
			end
		else -- for reclaim and resurrect orders
			local target = cmd.target
			local good = false
			
			if hasRes then 
				if cmd.id == 125 then -- for resurrect, check for conflicting reclaim orders, and remove them
					myCmd = {id=90, target=target}
					xhash = BuildHash(myCmd)
					if myQueue[xhash] then
						StopAnyWorker(xhash)
						myQueue[xhash] = nil
					end
				end
			elseif cmd.id == 125 then -- otherwise if there are no units that can resurrect in our group, remove res orders
				StopAnyWorker(hash)
				myQueue[hash] = nil
				return false
			end
		
			if target >= Game.maxUnits then -- if the target is a feature, ex wreckage
				featureID = target - Game.maxUnits
				if spValidFeatureID(featureID) then -- if the feature still exists, then it hasn't finished being reclaimed or resurrected
					good = true
				end
			else -- if the target is a unit
				if spValidUnitID(target) then -- if the unit still exists, then it hasn't been reclaimed fully yet
					good = true
				end
			end
			if not good then -- if our target no longer exists, ie fully reclaimed or resurrected
				StopAnyWorker(hash)
				myQueue[hash] = nil
				isClear = false
			end
		end
	end
	return isClear
end


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Helper Functions ------------------------------------------------------------
--[[
HOW THIS WORKS:
	UpdateOneGroupsDetails()
		Adds and removes units from myUnits as they enter or leave the exclusion group, or when the exclusion group number changes.
	CanBuildThis()
		Determines whether a given worker can perform a given job or not.
	IsTargetReachable()
		Checks pathing between a unit and destination, to determine if a worker
		can reach a given build site.
	UpdateOneWorkerPathing()
		Caches pathing info for one worker for every job in myQueue. This is called
		whenever a new unit enters our group, and adds the hash of any job that cannot be reached
		and/or performed to 'myUnits[unitID].unreachable'. Does not do anything for commands targetting
		units (ie repair, reclaim), since they may move and invalidate cached pathing info.
	UpdateOneJobPathing()
		Caches pathing info for one job for every worker in myUnits. This is called whenever a new
		job is added to the queue, and does basically the same thing as UpdateOneWorkerPathing().
	CleanPathing()
		Performs garbage collection for unreachable caches, removing jobs that are no longer on the queue.
	RemoveJobs()
		Takes an area select as input, and removes any job from the queue that falls within it. Used by the job
		removal tool.
	Distance()
		Simple 2D distance calculation.
	GetFirstCommand()
		Returns the first command in a unit's queue, if there is one, otherwise nil.
	ping()
		Returns the greater of 15 frames or latency, so that we can avoid clobbering the network.
	BuildHash()
		Takes a command (formatted for myQueue) as input, and returns a unique identifier
		to use as a hash table key. Allows duplicate jobs to be easily identified, and to easily
		check for the presence of any arbitrary job in myQueue.
	StopAnyWorker()
		Takes a key to myQueue as input, stops all workers moving towards a given job, removes them from the relevant lists, and marks
		them idle if not under direct orders. Called when jobs are finished, cancelled, or otherwise
		invalidated.
--]]

--  This function actually updates the list of builders in the CB group (myGroup).
--	Also borrowed from gunblob's UnitGroups v5.1
function UpdateOneGroupsDetails(myGroupId)
	local units = spGetGroupUnits(myGroupId)
	for _, unitID in ipairs(units) do	--  remove newly excluded units
		if (myUnits[unitID]) then
			myUnits[unitID] = nil
			if busyUnits[unitID] then
				local key = busyUnits[unitID]
				myQueue[key].assignedUnits[unitID] = nil
				busyUnits[unitID] = nil
			end
			excludedUnits[unitID] = true
		end
	end
	
	for unitID,_ in pairs(excludedUnits) do	--  add units that are no longer excluded
		local isInThere = false
		for _,unit2 in ipairs(units) do
			if ( unitID == unit2 ) then
				isInThere = true
				break
			end
		end
		if (not isInThere) then
			excludedUnits[unitID] = nil
			local cmd = GetFirstCommand(unitID) -- find out if it already has any orders
			if cmd and cmd.id then -- if so we mark it as drec
			myUnits[unitID] = {cmdtype=commandType.drec, unreachable={}}
			else -- otherwise we mark it as idle
				myUnits[unitID] = {cmdtype=commandType.idle, unreachable={}}
			end
			UpdateOneWorkerPathing(unitID) -- then precalculate pathing info
		end
	end
	groupHasChanged = false
end

--This function tells us if a unit can perform the job in question.
function CanBuildThis(cmdID, unitID)
	local unitDefID = spGetUnitDefID(unitID)
	local unitDef = UnitDefs[unitDefID]
	if cmdID < 0 then -- for build jobs
		local bcmd = abs(cmdID) -- abs the command ID to get the unitDefID that it refers to
		for _, options in ipairs(unitDef.buildOptions) do
			if ( options == bcmd ) then -- check whether our unit can build it
				return true 
			end
		end
		return false
	elseif cmdID == 40 or cmdID == 90 then -- for repair and reclaim, all builders can do this, return true
		return true
	elseif unitDef.canResurrect then -- for ressurect
		return true
	end
	return false
end

-- This function process result of Spring.PathRequest() to say whether target is reachable or not
function IsTargetReachable(unitID, tx,ty,tz)
	local ox, oy, oz = spGetUnitPosition(unitID)	-- unit location
	local unitDefID = spGetUnitDefID(unitID)
	local buildDist = UnitDefs[unitDefID].buildDistance -- build range
    local moveID = UnitDefs[unitDefID].moveDef.id -- unit pathing type
    if moveID then -- air units have no moveID, and we don't need to calculate pathing for them.
	    local path = spRequestPath( moveID,ox,oy,oz,tx,ty,tz, 10)
	    if path then
		    local waypoints = path:GetPathWayPoints()
		    local finalCoord = waypoints[#waypoints]
		    if finalCoord then -- unknown why sometimes NIL
			    local dx, dz = finalCoord[1]-tx, finalCoord[3]-tz
			    local dist = sqrt(dx*dx + dz*dz)
			    if dist < buildDist + 40 then -- is within radius?
				    return true -- within reach
			    else
				    return false -- not within reach
			    end
            else
                return true -- if finalCoord is nil for some reason, return true
		    end
	    else
		    return true -- if path is nil for some reason, return true
		    -- note: it usually returns nil for very short distances, which is why returning true is a much better default here
	    end
    else
	    return true --for air units; always reachable
    end	
end

-- This function caches pathing when a new worker enters the group.
function UpdateOneWorkerPathing(unitID)
	for hash, cmd in pairs(myQueue) do -- check pathing vs each job in the queue, mark any that can't be reached
		local jx, jy, jz = 0
		-- get job position
		if cmd.x then -- for all jobs not targetting units (ie not repair or unit reclaim)
			jx, jy, jz = cmd.x, cmd.y, cmd.z --the location of the current job
		
			if not IsTargetReachable(unitID, jx, jy, jz) or not CanBuildThis(cmd.id, unitID) then -- if the worker can't reach the job, or can't build it, add it to the worker's unreachable list
				myUnits[unitID].unreachable[hash] = true
			end
		end
	end
end

-- This function caches pathing when a new job is added to the queue
function UpdateOneJobPathing(hash)
	local cmd = myQueue[hash]
	-- get job position
	if cmd.x then -- for build jobs, and non-repair jobs that we cache the coords and pathing for
		local jx, jy, jz = cmd.x, cmd.y, cmd.z --the location of the current job
	
		for unitID, _ in pairs(myUnits) do -- check pathing for each unit, mark any that can't be reached.
			if spValidUnitID(unitID) then -- note that this function can be called before validity checks are run, and some of our units may have died.
				if not IsTargetReachable(unitID, jx, jy, jz) or not CanBuildThis(cmd.id, unitID) then -- if the worker can't reach the job, or can't build it, add it to the worker's unreachable list
					myUnits[unitID].unreachable[hash] = true
				end
			end
		end
	end
end

-- This function performs garbage collection for cached pathing
function CleanPathing(iUnits)
	for i=1, #iUnits do
		local unitID = iUnits[i]
		for hash,_ in pairs(myUnits[unitID].unreachable) do
			if not myQueue[hash] then -- remove old, invalid jobs from the unreachable list
				myUnits[unitID].unreachable[hash] = nil
			end
		end
	end
end

-- This function implements area removal for GBC jobs.
function RemoveJobs(x, z, r)
	for key, cmd in pairs(myQueue) do
		local inRadius = false
		
		if cmd.id < 0 then -- for build jobs
			local cmdID = abs(cmd.id)
			local cx = cmd.x
			local cz = cmd.z
			local ch = cmd.h -- building facing
			local xSize, zSize = 0
		
			if ch == 0 or ch == 2 then --get building facing. Reference: unit_prevent_lab_hax.lua by googlefrog
				xSize = UnitDefs[cmdID].xsize*4
				zSize = UnitDefs[cmdID].zsize*4
			else
				xSize = UnitDefs[cmdID].zsize*4
				zSize = UnitDefs[cmdID].xsize*4
			end
			 -- get the distances to the four corner vertices of the building footprint
			local dist1 = Distance(x, z, cx, cz)
			local dist2 = Distance(x, z, cx+xSize, cz)
			local dist3 = Distance(x, z, cx, cz+zSize)
			local dist4 = Distance(x, z, cx+xSize, cz+zSize)
			
			if dist1 < r or dist2 < r or dist3 < r or dist4 < r then -- if any of the corners falls within the radius, then mark the job for removal
				inRadius = true
			end
		elseif cmd.x then -- for area reclaim/repair/resurrect
			local jdist = Distance(x, z, cmd.x, cmd.z)
			if jdist < r then
				inRadius = true
			end
		else -- for single-target repair/reclaim/resurrect
			local jx, jz = 0
			local jdist = 0
			local target = cmd.target
			if target >= Game.maxUnits and spValidFeatureID(target-Game.maxUnits) then -- note wrecks and things become invalid/nil when outside of LOS, which we need to check for
				jx, _, jz = spGetFeaturePosition(target-Game.maxUnits)
				jdist = Distance(x, z, jx, jz)
				if jdist < r then
					inRadius = true
				end
			elseif target < Game.maxUnits and spValidUnitID(target)then
				jx, _, jz = spGetUnitPosition(target)
				jdist = Distance(x, z, jx, jz)
				if jdist < r then
					inRadius = true
					local udid = spGetUnitDefID(target)
					local unitDef = UnitDefs[udid]
					if string.match(unitDef.humanName, "erraform") ~= nil then -- if the target was a 'terraunit', self-destruct it
						spGiveOrderToUnit(target, 65, {}, {""})
					end
				end
			end
		end
		if inRadius then -- if the job was inside of our circle
			StopAnyWorker(key) -- release any workers assigned to the job
			myQueue[key] = nil -- and remove it from the queue
			areaCmdList[key] = nil -- and from area commands
		end
	end
end

--	Borrowed distance calculation from Google Frog's Area Mex
function Distance(x1,z1,x2,z2)
  local dis = sqrt((x1-x2)*(x1-x2)+(z1-z2)*(z1-z2))
  return dis
end

-- Produces a normalized direction from two points.
function GetNormalizedDirection(x1, z1, x2, z2)
	local x = x2 - x1
	local z = z2 - z1
	local d = math.sqrt((x*x) + (z*z))
	
	x = x/d
	z = z/d
	return x, z
end

-- determines if a table is empty, because lua does not provide a built in way to do that.
function IsEmpty(table)
	for _ in pairs(table) do
		return false
	end
	return true
end

--	Borrowed this from CarRepairer's Retreat.  Returns only first command in queue.
function GetFirstCommand(unitID)
	local queue = spGetCommandQueue(unitID, 1)
	return queue[1]
end

--	Prevent CBAI from canceling orders that just haven't made it to host yet
--	because of high ping. Donated by SkyStar.
function ping()
	local playerID = spGetLocalPlayerID()
	local tname, _, tspec, tteam, tallyteam, tping, tcpu = spGetPlayerInfo(playerID)  
	tping = (tping*1000-((tping*1000)%1)) /100 * 4
	return max( tping, 15 ) --wait minimum 0.5 sec delay
end

--	Generate unique key value for each command using its parameters.
--  Much easier than expected once I learned Lua can use *anything* for a key.
function BuildHash(myCmd)
	if myCmd.id < 0 then -- for build orders
		return myCmd.id .. "@" .. myCmd.x .. "x" .. myCmd.z
	elseif myCmd.target then -- for single-target repair/reclaim/ressurect
		return myCmd.id .. "@" .. myCmd.target
	else -- for area repair/reclaim/resurrect
		return myCmd.id .. "@" .. myCmd.x .. "x" .. myCmd.z .. "z" .. myCmd.r .. "r" .. tostring(myCmd.alt)
	end
end

-- Tell any worker for construction of "myQueue[key]" to stop the job immediately
-- Used only when jobs are known to be finished or cancelled
function StopAnyWorker(key)
	-- debugging crap
	if not myQueue[key] then
		Spring.Echo("GBC: Fatal error, tried to stop workers for a nonexisting job:" .. key)
	end
	-- end debugging crap
	local myCmd = myQueue[key]
	for unit,_ in pairs(myCmd.assignedUnits) do
		if myUnits[unit].cmdtype == commandType.buildQueue then -- for units that are under GBC control
			spGiveOrderToUnit(unit, CMD_REMOVE, {myCmd.id}, {"alt"}) -- remove the current order
			-- note: options "alt" with CMD_REMOVE tells it to use params as command ids, which is what we want.
			spGiveOrderToUnit(unit, CMD_STOP, {}, {""}) -- and replace it with a stop order
			-- note: giving a unit a stop order does not automatically cancel other orders as it does when a player uses it, which is why we also have to use CMD_REMOVE here.
			myUnits[unit].cmdtype = commandType.idle -- mark them as idle
			busyUnits[unit] = nil -- remove their entries from busyUnits, since the job is done
			reassignedUnits[unit] = nil -- and remove them from our reassigned units list, so that they will be immediately processed
		else -- otherwise for units under drec
			busyUnits[unit] = nil -- we remove the unit from busyUnits and let Spring handle it until it goes idle on its own.
		end
	end
end