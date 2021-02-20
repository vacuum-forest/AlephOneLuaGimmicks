--[[
	
	"Superdimensional Death Traps" by Kuurin (Feb. 19, 2021) 

	Turn your platforms into localized trans-dimensional rifts capable of tearing just about any damn thing apart with the energy flux between dimensions!

	Usage:
	Set up a platform as in the example map. Mark each platform as 'secret', and for those that emerge from the ceiling, mark these as 'locked' in addition.

]]

Triggers = {}

-- Configuration
-----------------------------------------------------------

debugEnable = false

trapArousalRadius = 3		-- Distance at which trap is aware of monsters from center of trap polygon

trapVerticalRange = 0.125 	-- Vertical distance from monster for contact damage
trapSideRange = 0.1			-- Perpendicular distance to trap side for contact damage when extended

trapCooldownActive = 150	-- Period in ticks before trap can be triggered again
trapCooldownIdle = 60	

trapPlatformDelay = 120		-- Delay period for all trapped platforms (in ticks)

deathTraps = {}

-- Trigger Functions
-----------------------------------------------------------

function Triggers.init()
	
	normalPolygons = {}
	
	for p in Polygons() do
		if p.type == "normal" then
			table.insert(normalPolygons, p)
		end
	end
	
	initializeDeathTraps()
	
end


function Triggers.platform_activated(polygon)
	
	local platform = Platforms[polygon.permutation]
	
	if platform._isDeathTrap then
		noteToSelf("PlatformTrigger: " .. tostring(platform._status))
		if platform._status == "waiting" then
			setDeathTrapStatus(platform, "active extending")
		elseif platform._status == "active contracting" then
			setDeathTrapStatus(platform, "cooldown")
		end
		
	end
	
end


function Triggers.idle()

	timersIdleUpkeep()

	updateDeathTraps()
	
end



-- Platform Functions
-----------------------------------------------------------

function gatherPlatformSurfaces(platform)
		
	noteToSelf("Parameterizing platform #" .. platform.index .. "...")

	platform._surfaces = { platform.polygon }
	
	for line in platform.polygon.lines() do
	
		local side
		if line.clockwise_polygon == platform.polygon then
			side = line.ccw_side
		else
			side = line.cw_side
		end
		
		table.insert(platform._surfaces, side)
		
	end
	
end


function setStatic(platform, active)

	local nextMode = active and "static" or "normal"

	if platform._mode ~= nextMode then

		platform._mode = nextMode

		for k, v in ipairs(platform._surfaces) do
			local targetSurface
			if platform._orientation == "floor" then
				targetSurface = is_polygon(v) and v.floor or v.primary
			else
				targetSurface = is_polygon(v) and v.ceiling or v.primary
			end
			targetSurface.transfer_mode = nextMode
		end

	end
	
end



-- Death Trap Functions
-----------------------------------------------------------

function initializeDeathTraps()

	for platform in Platforms() do
		
		if platform.secret and platform.type == "spht platform" then
			
			noteToSelf("Trapping platform #" .. platform.index)
			
			if platform.locked then
				platform._orientation = "ceiling"
			else
				platform._orientation = "floor"
			end
			
			platform._isDeathTrap = true
			platform._canEatMonsters = platform.monster_controllable
			platform._canEatPlayers = platform.player_controllable
			platform._victimsNearby = false
			platform._mode = "normal"
			platform._cooldown = 0
			platform._status = "idle"
			platform._lastDirection = platform.extending
			platform._zapRadius = math.sqrt(platform.polygon.area / math.pi) * 1.41
			
			local span = platform.polygon.ceiling.z - platform.polygon.floor.z
			platform._extendSpeed = span / 7
			platform._contractSpeed = span / 28
			
			gatherPlatformSurfaces(platform)
			table.insert(deathTraps, platform)
			
		end
		
	end
	
end


function updateDeathTraps()
	
	findDeathTrapVictims()
	
	for key, trap in ipairs(deathTraps) do
	
		local status = trap._status
	
		if status == "idle" then
		
			if trap.active then
				setStatic(trap, true)
				setDeathTrapStatus(trap, "active extending")
			else
				if trap._cooldown > 0 then
					trap._cooldown = trap._cooldown - 1
				else
					if trap._victimsNearby then
						setDeathTrapStatus(trap, "waiting")
					end
				end
			end
		
		elseif status == "waiting" then
		
			if not trap._victimsNearby then
				
				if not trap._shutDown then
					
					trap._shutDown = function()
						trap._cooldown = trapCooldownIdle
						setDeathTrapStatus(trap, "idle")
						trap._shutDown = nil
					end
					
					setActiveNoise(trap, "transformer", 0.2, true)
					createTimer(52, false, trap._shutDown)
					
				end
				
			end
		
		elseif status == "active extending" then
		
			if trap._lastDirection ~= trap.extending then
				setDeathTrapStatus(trap, "active stopped")
			end
			
			damageTrappedMonsters(trap)
		
		elseif status == "active stopped" then
		
			damageTrappedMonsters(trap)
		
		elseif status == "active contracting" then
		
			damageTrappedMonsters(trap)
	
		elseif status == "cooldown" then
		
			damageTrappedMonsters(trap)
		
			if trap._cooldown > 0 then
				trap._cooldown = trap._cooldown - 1
				if trap._cooldown == 60 then
					setActiveNoise(trap, "sparking transformer", 0.2, true)
				end
			else
				trap._cooldown = trapCooldownIdle
				setDeathTrapStatus(trap, "idle")
			end
		
		else
		
		end
		
		trap._lastDirection = trap.extending
		
	end
	
end


function setDeathTrapStatus(trap, status)

	local polygon = trap.polygon
	local x = polygon.x
	local y = polygon.y
	local z = polygon.z
	
	if status == "idle" then
		
		trap.monster_controllable = false
		trap.player_controllable = false
		
		removeActiveNoises(trap)
		polygon:play_sound(x, y, z, "hunter exploding", 2.5)
		setStatic(trap, false)
		
	elseif status == "waiting" then
		
		polygon:play_sound(x, y, z, "spht projectile flyby", 2)
		
		setActiveNoise(trap, "transformer", 0.2)
		
		trap.monster_controllable = trap._canEatMonsters
		trap.player_controllable = trap._canEatPlayers
		
		setStatic(trap, true)
		
	elseif status == "active extending" then
		
		polygon:play_sound(x, y, z, "teleport in", 1.2)
		
		setActiveNoise(trap, "sparking transformer", 0.2)
		
		trap.speed = trap._extendSpeed
		
		trap.monster_controllable = false
		trap.player_controllable = false
		
		
	elseif status == "active stopped" then
		
		trap.speed = trap._contractSpeed
		
		local nextStatus = function()
			setDeathTrapStatus(trap, "active contracting")
		end
		
		local transition = createTimer(trapPlatformDelay, false, nextStatus)
		
	elseif status == "active contracting" then
		
		polygon:play_sound(x, y, z, "teleport out", 0.5)
	
	elseif status == "cooldown" then
		
		trap._cooldown = trapCooldownActive
		
	else
		
	end
	
	trap._status = status
	
	noteToSelf("Deathtrap " .. tostring(trap.index) .. " has status " .. status .. ".")
	
end


function findDeathTrapVictims()
	
	for key, trap in ipairs(deathTraps) do
		trap._victimsNearby = false
	end
	
	for monster in Monsters() do 
		
		if isAlive(monster) then
			
			for key, trap in ipairs(deathTraps) do
			
				if not trap._victimsNearby then
				
					if (monster.player and trap._canEatPlayers) or (not monster.player and trap._canEatMonsters) then
					
						local distance = getDistance(monster.x, monster.y, trap.polygon)
			
						if distance <= trapArousalRadius then
							
							if not trap._victimsNearby then
								trap._victimsNearby = { monster }
							else
								table.insert(trap._victimsNearby, monster)
							end
							
						end
		
					end
			
				end
			
			end
			
		end
		
	end
	
end


function damageTrappedMonsters(trap)
	
	if trap._victimsNearby then
	
		for k, monster in ipairs(trap._victimsNearby) do
		
			if isAlive(monster) then
			
				if trap._status == "cooldown" then
				
					if monster.polygon == trap.polygon and checkVerticalProximity(monster, trap) then
						damageContact(monster, trap)
					end
				
				else
					
					if monster.polygon == trap.polygon and checkVerticalProximity(monster, trap) then
						damageTeleport(monster)
					elseif checkSideProximity(monster, trap) then
						damageContact(monster, trap)
					end
					
				end
			
			end
		
		end
		
	end
	
end


function checkSideProximity(monster, trap)
	
	local monsterWithinHeightRange
	if trap._orientation == "floor" then
		monsterWithinHeightRange = monster.z <= trap.floor_height
	else
		monsterWithinHeightRange = monster.z >= trap.ceiling_height
	end
	
	if monsterWithinHeightRange then
	
		local closeLine = trap.polygon:find_line_crossed_leaving(trap.polygon.x, trap.polygon.y, monster.x, monster.y)
	
		if closeLine then
		
			local p1 = closeLine.endpoints[0]
			local p2 = closeLine.endpoints[1]
			local angle = angleDifference(getBearing(p1, p2), getBearing(p1, monster))
			local proximity = math.sin(math.rad(angle)) * getDistance(p1.x, p1.y, monster)
		
			if proximity - monster.type.radius <= trapSideRange then
				return true
			end
		
		end 
		
	end
	
	return false
	
end


function checkVerticalProximity(monster, trap)

	local dz
	if trap._orientation == "floor" then
		dz = monster.z - trap.floor_height
	else
		dz = trap.ceiling_height - (monster.z + monster.type.height)
		if monster.player then
			dz = dz - 0.2
		end
	end
	
	if dz <= trapVerticalRange then
		return true
	end
	
	return false
	
end


function damageTeleport(monster)

	if monster.player then
	
		if not monster.player._isTeleporting then
			monster.player._isTeleporting = true
			monster.player:teleport(selectRandomNormalPolygon())
			monster.player._teleportDamage = function()
				monster:damage(1000, "teleporter")
				monster.player._isTeleporting = false
				monster.player.yaw = Game.random(360)
			end
			createTimer(5,false,monster.player._teleportDamage)
		end
	
	else
	
		monster:damage(1000, "teleporter")
	
	end

end


function damageContact(monster, trap)

	local swatDirection = getBearing(trap.polygon, monster)

	monster:play_sound("destroy control panel")
	monster:accelerate(swatDirection, 0.5, 0.2)
	monster:damage(500, "fusion")

end



-- Timers
-----------------------------------------------------------

Timers = {}

TimerList = {}

function createTimer(period, repeating, action, immediate)

	local timer = Timers:new()
	
	timer.period = period - 1
	timer.repeating = repeating
	timer.action = action
	
	if immediate then
		timer.count = 0
	else
		timer.count = period
	end
	
	timer.status = "live"
	
	table.insert(TimerList, timer)
	
	return timer
	
end


function Timers:execute()

	self.action()

	if self.repeating then
	
		self:reset()
	
	else
		
		self.status = "dead"
		
	end
	
end


function Timers:reset()
	
	self.count = self.period
	
end


function Timers:kill()

	self.status = "dead"

end


function Timers:evaluate()

	if self.status == "dead" then
		self = nil
		return
	end

	if self.count <= 0 then
		self:execute()
		return
	end
	
	self.count = self.count - 1
	
end


function Timers:new()
	
	o = {}
    setmetatable(o, self)
    self.__index = self
	return o
	
end


function timersIdleUpkeep()

	local newSet = {}

	for i = 1, # TimerList, 1 do
		
		TimerList[i]:evaluate()
		if TimerList[i].status == "live" then
			table.insert(newSet, TimerList[i])
		end
		
	end

	TimerList = newSet
	
end



-- Noises
-----------------------------------------------------------

function setActiveNoise(trap, sound, pitch, die)
	
	if not die then
		die = false
	end
	
	for k, target in ipairs(trap._surfaces) do
	
		removeActiveNoise(target)

		if is_polygon(target) then
			local x = target.x
			local y = target.y
			local z
			if trap._orientation == "floor" then
				z = trap.floor_height
			else
				z = trap.ceiling_height
			end
			target._noise = function()
				target:play_sound(x, y, z, sound, pitch)
			end
		else
			target._noise = function()
				target:play_sound(sound, pitch)
			end
		end

		target._noisePeriod = math.floor(Sounds[sound]._period)

		target._activeNoise = createTimer(target._noisePeriod, not die, target._noise, true)
		
	end
	
end


function removeActiveNoise(surface)

	if surface._activeNoise then
		if surface._activeNoise.status == "live" then
			surface._activeNoise:kill()
		end
	end
	
end


function removeActiveNoises(trap)

	for k, target in ipairs(trap._surfaces) do
	
		removeActiveNoise(target)
		
	end
	
end


Sounds["transformer"]._period = 38
Sounds["sparking transformer"]._period = 36



-- Assorted Functions
-----------------------------------------------------------

function selectRandomNormalPolygon()
	
	local random = Game.random(# normalPolygons) + 1
	return normalPolygons[random]

end


function isAlive(monster)

	if monster.valid then
		
		if monster.visible then
			
			local victimLife = monster.player and monster.player.life or monster.life
			
			if monster.type.class == "tick" then
				
				if monster.action ~= "dying hard" and monster.action ~= "dying soft" and monster.action ~= "dying flaming" then
					
					return true
					
				else
					
					return false
					
				end
				
			end
			
			if victimLife > 0 then
				
				return true
				
			end
			
		end
		
	end

end


function getDistance(x, y, object)
	
	return math.sqrt((object.x - x)^2 + (object.y - y)^2)
	
end


function getBearing(from, to)
	
	local x = to.x - from.x
	local y = to.y - from.y
	local theta = math.deg(math.atan(y/x))
	if x < 0 then
		return theta + 180
	elseif y < 0 then
		return theta + 360
	else
		return theta
	end
	
end


function angleDifference(a, b)

	return (a - b + 540) % 360 - 180

end


function noteToSelf(message)

	if not debugEnable then
		return
	else
		local note = "Note at tick #" .. tostring(Game.ticks) .. ": " .. tostring(message)
		Players.print(note)
	end
	
end


