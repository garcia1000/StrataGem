local love = _G.love
-- handles the main game phases

local common = require "class.commons"
local inspect = require "inspect"	-- TODO: Fix netcode so this can be removed.

local PhaseManager = {}

function PhaseManager:init(game)
	self.game = game
	self.ai = common.instance(require "ai", game)
end

function PhaseManager:intro(dt)
	local game = self.game
	for player in game:players() do
		player.hand:update(dt)
	end
	if game.frame == 30 then
		game.particles.words.generateReady(self.game)
	end
	if game.frame == 120 then
		game.particles.words.generateGo(self.game)
		game.phase = "Action"
	end
end

function PhaseManager:action(dt)
	local game = self.game
	local client = game.client
	local ai = self.ai

	for player in game:players() do
		player.hand:update(dt)
		if player.actionPhase then
			player:actionPhase(dt)
		end
	end
	self.game.ui:update(dt)

	game.time_to_next = game.time_to_next - 1
	if game.type == "1P" then
		if not ai.finished then
			ai:placeholder(game.them_player)
		end
	end
	if game.time_to_next == 0 then
		love.mousereleased(love.mouse.getPosition())
		game.particles.wordEffects.clear(game.particles)
		game.phase = "Resolve"
		if game.type == "Netplay" then
			if not client.our_delta[game.turn] then
				client.prepareDelta("blank")
			end
		elseif game.type == "1P" then
			if ai.queued_action then
				ai.queued_action.func(table.unpack(ai.queued_action.args))
				ai.queued_action = false
			end
		end
	end

	-- This part checks that the state is the same
	-- We do it in this phase so that players don't need to wait
	-- Send it 50 frames after turn start, hope this removes the state bug?!
	if not client.synced and game.type == "Netplay" then
		if not client.sent_state then
			print("Queueing state-send")
			client.sendState(game.STATE_SEND_WAIT)
			client.sent_state = true
		end

		if client.received_state and client.opponent_received_state then
			-- all state sending is done, now compare them and raise an error if different
			print("Frame: " .. game.frame, "Time: " .. love.timer.getTime() - client.match_start_time,"States successfully exchanged")

			-- time adjustment for lag
			local our_frames_behind = client.their_state[game.turn].frame - client.our_state[game.turn].frame
			print("Frame: " .. game.frame, "Time: " .. love.timer.getTime() - client.match_start_time,"Our frames behind:", our_frames_behind)
			-- If we are behind in frames, it means we processed state more slowly
			-- We need to catch up (our_frames_behind) frames.
			-- Therefore, we add to time bucket (our_frames_behind * timestep).
			if our_frames_behind > 0 then
				print("Need to speed up by " .. our_frames_behind .. " frames")
				client.giving_frameback = our_frames_behind
			end

			if client.compareStates() then
				print("Frame: " .. game.frame, "Time: " .. love.timer.getTime() - client.match_start_time, "States match!")
				print("Player 1 meter: " .. game.p1.cur_mp, "Player 2 meter: " .. game.p2.cur_mp)
				client.synced = true
			else
				print("Frame: " .. game.frame, "Time: " .. love.timer.getTime() - client.match_start_time, "Desync.")
				print("Game turn: " .. game.turn)
				print("Our state:")
				for k, v in spairs(client.our_state[game.turn]) do print(k, v) end
				print("Their state:")
				for k, v in spairs(client.their_state[game.turn]) do print(k, v) end
				print("Desynced due to states not matching!")

				print("hey send garcia1000 ourstate.txt and theirstate.txt please")
				print("File path is:")
				print( love.filesystem.getSaveDirectory() )
				local write1 = inspect(client.our_state[game.turn])
				local write2 = inspect(client.their_state[game.turn])
				love.filesystem.write("ourstate.txt", write1)
				love.filesystem.write("theirstate.txt", write2)

				game.phase = "GameOver"
				--[[
				Need to do more stuff here
				--]]
			end
		end
	end
end

function PhaseManager:resolve(dt)
	local game = self.game

	if game.me_player.place_type == nil then
		print("PLACE TYPE BUG")
	end
	for player in game:players() do
		player.hand:afterActionPhaseUpdate()
	end
	self.game.ui:putPendingAtTop(game)
	game.particles.upGem.removeAll(game.particles) -- animation
	game.frozen = true
	game.phase = "GemTween"
end

function PhaseManager:applyGemTween(dt)
	local game = self.game
	local grid = game.stage.grid
	grid:updateGravity(dt) -- animation
	for player in self.game:players() do
		player.hand:update(dt)
	end
	local animation_done = grid:isSettled() -- function
	if animation_done then
		grid:dropColumns() -- state
		game.phase = "Gravity"
	end
end

function PhaseManager:applyGravity(dt)
	local game = self.game
	local grid = game.stage.grid

	grid:updateGravity(dt) -- animation
	for player in self.game:players() do
		player.hand:update(dt)
	end
	local animation_done = grid:isSettled() -- function
	if animation_done then
		for player in game:players() do
			player:afterGravity()
		end
		game.phase = "CheckMatches"
	end
end

function PhaseManager:getMatchedGems(dt)
	local _, matches = self.game.stage.grid:getMatchedGems() -- sets horizontal/vertical flags for matches
	print(matches)
	if matches > 0 then
		self.game.phase = "FlagGems"
	else
		self.game.phase = "ResolvedMatches"
	end
end

function PhaseManager:flagGems(dt)
	local gem_table = self.game.stage.grid:getMatchedGems() -- sets h/v flags
	self.game.stage.grid:flagMatchedGems() -- state
	for player in self.game:players() do
		player:beforeMatch(gem_table)
	end
	self.game.phase = "MatchAnimations"
end

local match_anim_phase, match_anim_count = "start", 0

function PhaseManager:matchAnimations(dt)
	local grid = self.game.stage.grid
	if match_anim_phase == "start" then
		grid:generateMatchExplodingGems() -- animation
		match_anim_phase, match_anim_count = "explode", 20
	elseif match_anim_phase == "explode" then
		match_anim_count = math.max(match_anim_count - 1, 0)
		if match_anim_count == 0 then
			local matches = grid:getMatchedGems()
			grid:generateMatchParticles() -- animation
			self.game.ui:screenshake(#matches) -- animation
			match_anim_phase, match_anim_count = "start", 0
			self.game.phase = "ResolvingMatches"
		end
	end
end

function PhaseManager:resolvingMatches(dt)
	local grid = self.game.stage.grid
	local p1, p2 = self.game.p1, self.game.p2
	local gem_table = grid:getMatchedGems()
	self.game.scoring_combo = self.game.scoring_combo + 1
	for player in self.game:players() do
		player:duringMatch(gem_table)
	end
	local p1dmg, p2dmg, p1super, p2super = grid:calculateScore()
	local p1_matched, p2_matched = grid:checkMatchedThisTurn()
	if not p1_matched then
		grid:removeAllGemOwners(p1)
	end
	if not p2_matched then
		grid:removeAllGemOwners(p2)
	end
	p1:addSuper(p1super)
	p2:addSuper(p2super)
	grid:removeMatchedGems()
	p1.hand:addDamage(p2dmg)
	p2.hand:addDamage(p1dmg)
	grid:dropColumnsAnim()
	grid:dropColumns()
	self.game.phase = "Gravity"
end

function PhaseManager:resolvedMatches(dt)
	local game = self.game

	if game.particles.getNumber("Damage") > 0 then
		for player in game:players() do
			player.hand:update(dt)
		end
	else	-- all damage particles finished
		for player in game:players() do
			player:afterMatch()
			player.hand:update(dt)
			player.place_type = "normal"
		end
		game.scoring_combo = 0
		game.stage.grid:setAllGemOwners(0)
		game.phase = "GetPiece"
	end
end

function PhaseManager:getPiece(dt)
	for player in self.game:players() do
		player.hand:destroyPlatformsAnim()
		player.hand:getNewTurnPieces()
	end
	self.game.phase = "PlatformsExploding"
end

function PhaseManager:platformsExploding(dt)
	if self.game.particles:getNumber("ExplodingPlatform") == 0 then
		self.game.phase = "PlatformsMoving"
	end
end

function PhaseManager:platformsMovingUp(dt)
	local game = self.game
	local grid = game.stage.grid
	local handsettled = true

	for player in game:players() do
		player.hand:update(dt)
		if not player.hand:isSettled() then
			handsettled = false
		end
	end

	grid:updateGravity(dt)

	if handsettled then
		for player in game:players() do	-- TODO: check if we can delete this
			player.hand:update(dt)
		end
		-- ignore garbage pushing gems up, creating matches, for now

		if grid:isSettled() then
		-- garbage can possibly push gems up, creating matches.
			local _, matches = grid:getMatchedGems()
			if matches > 0 then
				grid:setGarbageMatchFlags()
				game.phase = "Gravity"
			else
				game.phase = "Cleanup"
			end
		end
	end
end

function PhaseManager:cleanup(dt)
	local game = self.game
	local grid = game.stage.grid
	local p1, p2 = game.p1, game.p2

	grid:updateGrid()
	for player in game:players() do
		player:cleanup()
	end
	if game.type == "1P" then
		self.ai:clear()
	end
	p1.pieces_fallen, p2.pieces_fallen = 0, 0
	p1.dropped_piece, p2.dropped_piece = false, false
	p1.played_pieces, p2.played_pieces = {}, {}
	game.finished_getting_pieces = false
	grid:setAllGemOwners(0)

	for player in game:players() do
		player.hand:endOfTurnUpdate()
	end

	if grid:getLoser() then
		game.phase = "GameOver"
	elseif game.type == "Netplay" then
		game.phase = "Sync"
	else
		game:newTurn()
	end
end

function PhaseManager:sync(dt)
	self.game.client:newTurn()
	self.game:newTurn()
	-- If disconnected by server, change to vs AI
	if not self.game.client.connected then
		self.game.type = "1P"
		print("Disconnected from server :( changing to 1P mode")
		self.game:newTurn()
	end
end

function PhaseManager:gameOver(dt)
	local game = self.game
	local particles = game.particles

	local loser = game.stage.grid:getLoser()
	if loser == "P1" then
		print("P2 wins gg")
	elseif loser == "P2" then
		print("P1 wins gg")
	elseif loser == "Draw" then
		print("Draw gg")
	else
		print("Match ended unexpectedly, whopps!")
	end
	local damage_particles = particles:getNumber("Damage", game.p1) + particles:getNumber("Damage", game.p2)
	local super_particles = particles:getNumber("Super", game.p1) + particles:getNumber("Super", game.p2)
	local anims_done = (damage_particles == 0) and (super_particles == 0)
	if anims_done and game.type == "Netplay" then
		game.client:endMatch()
		game.statemanager:switch(require "gs_lobby")
	elseif anims_done and game.type == "1P" then
		game.statemanager:switch(require "gs_charselect")
	end
end

PhaseManager.lookup = {
	Intro = PhaseManager.intro,
	Action = PhaseManager.action,
	Resolve = PhaseManager.resolve,
	SuperFreeze = PhaseManager.superFreeze,
	GemTween = PhaseManager.applyGemTween,
	Gravity = PhaseManager.applyGravity,
	CheckMatches = PhaseManager.getMatchedGems,
	FlagGems = PhaseManager.flagGems,
	MatchAnimations = PhaseManager.matchAnimations,
	ResolvingMatches = PhaseManager.resolvingMatches,
	ResolvedMatches = PhaseManager.resolvedMatches,
	GetPiece = PhaseManager.getPiece,
	PlatformsExploding = PhaseManager.platformsExploding,
	PlatformsMoving = PhaseManager.platformsMovingUp,
	Cleanup = PhaseManager.cleanup,
	Sync = PhaseManager.sync,
	GameOver = PhaseManager.gameOver
}

function PhaseManager:run(...)
	local todo = PhaseManager.lookup[self.game.phase]
	assert(todo, "You did a typo for the current phase idiot - " .. self.game.phase)
	todo(self, ...)
	self.game.queue:update()
end

return common.class("PhaseManager", PhaseManager)
