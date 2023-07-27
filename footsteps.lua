
PLUGIN.name = "Footsteps"
PLUGIN.description = "Rewrites and improves on Source's handling of footsteps."
PLUGIN.author = "TankNut"

ix.config.Add("footstepVolumeMultiplier", 1, "A volume multiplier to use for footsteps.", nil, {
	data = {min = 0, max = 2, decimals = 1},
	category = "Footsteps",
})

ix.config.Add("silentCrouching", false, "Whether crouching is perfectly silent.", nil, {
	category = "Footsteps"
})

ix.config.Add("silentWalking", false, "Whether alt-walking is perfectly silent.", nil, {
	category = "Footsteps"
})

ix.config.Add("allowPersonalFootstepVolume", true, "Whether people can change the volume of their own footsteps.", nil, {
	category = "Footsteps"
})

ix.option.Add("footstepVolume", ix.type.number, 1, {
	min = 0.1,
	max = 2,
	decimals = 1,
	category = "footsteps"
})

ix.lang.AddTable("english", {
	optFootstepVolume = "Own footstep volume",
	optdFootstepVolume = "Changes the volume of your own footsteps, does not work if disabled by the server."
})

function PLUGIN:PlayerFootstep(client)
	return true
end

function PLUGIN:EntityEmitSound(info)
	-- It's an ugly way of doing it but short of recompiling all of the HL2 models you're not gonna be able to prevent their baked-in sounds from playing.
	if IsValid(info.Entity) and info.Entity:IsPlayer() and not IsEmittingPlayerStep and info.OriginalSoundName:find("step") then
		return false
	end
end

if CLIENT then
	function PLUGIN:InitPostEntity()
		local client = LocalPlayer()

		client.NextStepTime = 0
		client.NextStepSide = false
		client.StepSkip = 0
	end

	function PLUGIN:FinishMove(client, mv)
		if not IsFirstTimePredicted() or client.NextStepTime > CurTime() then
			return
		end

		if client:GetMoveType() == MOVETYPE_NOCLIP then
			return
		end

		if client:GetMoveType() != MOVETYPE_LADDER and not client:IsFlagSet(FL_ONGROUND) then
			return
		end

		if ix.config.Get("silentCrouching") and client:Crouching() then
			return
		end

		if ix.config.Get("silentWalking") and client:KeyDown(IN_WALK) then
			return
		end

		local vel = mv:GetVelocity():Length()

		if vel < hook.Run("GetMinStepSpeed", client) then
			return
		end

		local side = client.NextStepSide

		if hook.Run("HandlePlayerStep", client, side) == true then
			return
		end

		client.NextStepTime = CurTime() + hook.Run("GetNextStepTime", client, vel)
		client.NextStepSide = not side
	end

	function PLUGIN:HandlePlayerStep(client, side)
		-- Submerged footsteps play less often through a kinda weird method
		if client:WaterLevel() >= 1 then
			if client.StepSkip == 2 then
				client.StepSkip = 0
			else
				client.StepSkip = client.StepSkip + 1

				return true
			end
		end
	end

	-- GAMEMODE functions, act as fallbacks for hook.Run
	function GAMEMODE:GetMinStepSpeed(client)
		return client:GetWalkSpeed() * math.min(ix.config.Get("walkRatio"), client:GetCrouchedWalkSpeed()) - 1
	end

	function GAMEMODE:GetNextStepTime(client, vel)
		if client:GetMoveType() == MOVETYPE_LADDER then
			return 0.45
		end

		local val

		if client:WaterLevel() >= 1 then
			val = 0.6
		else
			if client:KeyDown(IN_WALK) and vel < 90 then
				val = 0.3 / (vel / 90)
			else
				val = math.max(math.Remap(vel, 90, 235, 0.45, 0.3), 0.1)
			end
		end

		if client:Crouching() then
			val = val + 0.1
		end

		return val
	end

	local ladderSurface = util.GetSurfaceData(util.GetSurfaceIndex("ladder"))
	local wadeSurface = util.GetSurfaceData(util.GetSurfaceIndex("wade"))

	function GAMEMODE:GetDefaultStepSound(client, side)
		if client:GetMoveType() == MOVETYPE_LADDER then
			return side and ladderSurface.stepRightSound or ladderSurface.stepLeftSound, 0.5
		elseif client:WaterLevel() >= 1 then
			return side and wadeSurface.stepRightSound or wadeSurface.stepLeftSound, client:IsRunning() and 0.65 or 0.25
		else
			local prop = client:GetSurfaceData()

			return side and prop.stepRightSound or prop.stepLeftSound, client:IsRunning() and 0.5 or 0.2
		end
	end

	function GAMEMODE:ModifyPlayerStep(client, data)
		local character = client:GetCharacter()

		if character then
			local faction = ix.faction.Get(character:GetFaction())

			if faction.ModifyPlayerStep and faction:ModifyPlayerStep(client, data) == true then
				return true
			end

			local class = ix.class.Get(character:GetClass())

			if class.ModifyPlayerStep and class:ModifyPlayerStep(client, data) == true then
				return true
			end
		end

		if client:Crouching() then
			data.volume = data.volume * 0.65
		end
	end

	function GAMEMODE:HandlePlayerStep(client, side)
		local snd, volume = hook.Run("GetDefaultStepSound", client, side)

		local data = {
			snd = snd,
			side = side,
			volume = volume,
			ladder = client:GetMoveType() == MOVETYPE_LADDER,
			submerged = client:WaterLevel() >= 1,
			running = client:IsRunning()
		}

		if hook.Run("ModifyPlayerStep", client, data) == false then
			return
		end

		volume = data.volume * ix.config.Get("footstepVolumeMultiplier")

		if ix.config.Get("allowPersonalFootstepVolume") then
			volume = volume * ix.option.Get("footstepVolume")
		end

		IsEmittingPlayerStep = true
		EmitSound(data.snd, client:GetPos(), client:EntIndex(), CHAN_AUTO, volume)
		IsEmittingPlayerStep = nil
	end
end

local playerMeta = FindMetaTable("Player")
local offset = Vector(0, 0, 16)

function playerMeta:GetSurfaceData()
	local mins, maxs = self:GetHull()
	local tr = util.TraceHull({
		start = self:GetPos(),
		endpos = self:GetPos() - offset,
		filter = {self},
		mins = mins,
		maxs = maxs,
		collisiongroup = COLLISION_GROUP_PLAYER_MOVEMENT
	})

	return util.GetSurfaceData(tr.SurfaceProps)
end