--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
if not gadgetHandler:IsSyncedCode() then
	return
end
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function gadget:GetInfo()
	return {
		name      = "Bait Prevention",
		desc      = "Prevents some units from Idle-firing or Move-firing at low value targets.",
		author    = "dyth68 and GoogleFrog",
		date      = "20 April 2020",
		license   = "GNU GPL, v2 or later",
		layer     = -1, -- vetoes targets, so is before ones that just modify priority
		enabled   = true  --  loaded by default?
	}
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local spValidUnitID         = Spring.ValidUnitID
local spGetGameFrame        = Spring.GetGameFrame
local spFindUnitCmdDesc     = Spring.FindUnitCmdDesc
local spEditUnitCmdDesc     = Spring.EditUnitCmdDesc
local spInsertUnitCmdDesc   = Spring.InsertUnitCmdDesc
local spGetUnitDefID        = Spring.GetUnitDefID
local spGetUnitLosState     = Spring.GetUnitLosState

local debugBait = false

-------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------
-- Value is the default state of the command
local baitPreventionDefaults, targetBaitLevelDefs, targetBaitLevelArmorDefs = include("LuaRules/Configs/bait_prevention_defs.lua")

local unitBaitLevel = {}
local unitDefCost = {}

for i = 1, #UnitDefs do
	local ud = UnitDefs[i]
	unitDefCost[i] = ud.cost
end
include("LuaRules/Configs/customcmds.h.lua")

local preventChaffShootingCmdDesc = {
	id      = CMD_PREVENT_BAIT,
	type    = CMDTYPE.ICON_MODE,
	name    = "Min metal for kill.",
	action  = 'preventchaffshootingmetallimit',
	tooltip = 'Enable to prevent units shooting at units which are very cheap.',
	params  = {0, 0, 35, 100, 300, 1000}
}

function ChaffShootingBlock(unitID, targetID, damage)
	if debugBait then
		Spring.Echo("==== BAIT CHECK ====", Spring.GetGameFrame())
		Spring.Utilities.UnitEcho(unitID)
	end
	if not (unitID and targetID and unitBaitLevel[unitID] and unitBaitLevel[unitID] ~= 0) then
		return false
	end

	if spValidUnitID(unitID) and spValidUnitID(targetID) then
		local gameFrame = spGetGameFrame()
		local targetVisiblityState = spGetUnitLosState(targetID, Spring.GetUnitTeam(unitID), true)
		local identified = (targetVisiblityState > 2)
		if debugBait then
			Spring.Echo("identified", identified)
		end
		if not identified then
			return true -- radar dots are classic bait.
		end
		local unitDefID = spGetUnitDefID(targetID)
		if debugBait then
			Spring.Echo("unitDefID", unitDefID)
			Spring.Echo("unitBaitLevel", unitBaitLevel[unitID])
			Spring.Echo("targetBaitLevelDefs", targetBaitLevelDefs[unitDefID])
		end
		if unitBaitLevel[unitID] >= targetBaitLevelDefs[unitDefID] then
			return true
		end
		if targetBaitLevelArmorDefs[unitDefID] and unitBaitLevel[unitID] >= targetBaitLevelArmorDefs[unitDefID] then
			local targetInLoS = (targetVisiblityState == 15)
			if not targetVisiblityState then
				return true
			end
			local armored, armorMultiple = Spring.GetUnitArmored(targetID)
			return (armored and true) or false
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- Command Handling 

local function PreventFiringAtChaffToggleCommand(unitID, unitDefID, state, cmdOptions)
	if unitBaitLevel[unitID] then
		local state = state or 1
		local cmdDescID = spFindUnitCmdDesc(unitID, CMD_PREVENT_BAIT)
		if cmdOptions and cmdOptions.right then
			state = (state - 2)%5
		end
		if (cmdDescID) then
			preventChaffShootingCmdDesc.params[1] = state
			spEditUnitCmdDesc(unitID, cmdDescID, {params = preventChaffShootingCmdDesc.params})
		end
		
		unitBaitLevel[unitID] = state
		return false
	end
	return true
end

function gadget:AllowCommand_GetWantedCommand()
	return {[CMD_PREVENT_BAIT] = true}
end

function gadget:AllowCommand_GetWantedUnitDefID()
	return true
end

function gadget:AllowCommand(unitID, unitDefID, teamID, cmdID, cmdParams, cmdOptions)
	if (cmdID == CMD_PREVENT_BAIT) then
		return PreventFiringAtChaffToggleCommand(unitID, unitDefID, cmdParams[1], cmdOptions)
	end
	return true  -- command was not used
end

--------------------------------------------------------------------------------
-- Unit Handling

function gadget:UnitCreated(unitID, unitDefID, teamID)
	if baitPreventionDefaults[unitDefID] then
		spInsertUnitCmdDesc(unitID, preventChaffShootingCmdDesc)
		unitBaitLevel[unitID] = 0
		PreventFiringAtChaffToggleCommand(unitID, unitDefID, baitPreventionDefaults[unitDefID])
	end
end

function gadget:UnitDestroyed(unitID)
	unitBaitLevel[unitID] = nil
end

function gadget:AllowWeaponTarget(unitID, targetID, attackerWeaponNum, attackerWeaponDefID, defPriority)
	if ChaffShootingBlock(unitID, targetID) then
		return false, defPriority
	end
	return true, defPriority
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local function ToggleDebugBait(cmd, line, words, player)
	if not Spring.IsCheatingEnabled() then
		return
	end
	debugBait = not debugBait
	Spring.Echo("Debug Bait", debugBait)
end

function gadget:Initialize()
	-- register command
	gadgetHandler:RegisterCMDID(CMD_PREVENT_BAIT)
	gadgetHandler:AddChatAction("debugbait", ToggleDebugBait, "")
	
	-- load active units
	for _, unitID in ipairs(Spring.GetAllUnits()) do
		local unitDefID = Spring.GetUnitDefID(unitID)
		local teamID = Spring.GetUnitTeam(unitID)
		gadget:UnitCreated(unitID, unitDefID, teamID)
	end
end
