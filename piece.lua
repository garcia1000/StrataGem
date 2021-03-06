--[[
This is the module for a piece. A piece is one of the (usually 2-gem) pieces
in the player's hand.

Most of the methods are to do with how to handle the piece when it's dropped
into the basin.
--]]
local love = _G.love
local common = require "class.commons"
local tween = require "/libraries/tween"
local Pic = require "pic"
local Gem = require "gem"
local reverseTable = require "/helpers/utilities".reverseTable
local pointIsInRect = require "/helpers/utilities".pointIsInRect
local images = require "images"

local Piece = {}
function Piece:init(tbl)
	self.game = tbl.game

	self.game.inits.ID.piece = self.game.inits.ID.piece + 1
	local tocopy = {"x", "y", "owner", "player_num", "gem_table"}
	for i = 1, #tocopy do
		local item = tocopy[i]
		self[item] = tbl[item]
		if tbl[item] == nil and item ~= "gem_table" then
			print("No " .. item .. " received!")
		end
	end
	self.ID = self.game.inits.ID.piece
	self.size = self.size or 2
	self.rotation = 0
	self.rotation_index = 0
	self.is_horizontal = true
	self:addGems(tbl.gem_freq_table, tbl.gem_replace_table)
	self.getx = self.owner.hand.getx
	self.hand_idx = tbl.hand_idx
end

--[[
	Optional:
	gem_freq_table - a table of color probabilities in the form
		{red = 1, blue = 2, green = 3, ...}
	gem_replace_table - a table of {color = image} e.g.
		{{color = "red"}, {color = "wild", image = dog.png}}
		It also accepts {color = "red", image = dog.png}
 --]]
function Piece:create(params)
	assert(params.game, "Game object not received!")
	assert(params.hand_idx, "Piece creation location hand index not received!")
	assert(params.owner, "Owner not received!")
	assert(params.player_num, "Owner number not received!")
	assert(params.x, "x-location not received!")
	assert(params.y, "y-location not received!")

	return common.instance(self, params)
end

function Piece:updateGems()
	if self.is_horizontal then
		for i = 1, self.size do
			self.gems[i].x =
				self.x
				- (self.gems[i].width / 2) * (self.size - 1)
				+ (i - 1) * self.gems[i].width
			self.gems[i].y = self.y
		end
	else
		for i = 1, self.size do
			self.gems[i].x = self.x
			self.gems[i].y =
				self.y
				- (self.gems[i].height / 2) * (self.size - 1)
				+ (i - 1) * self.gems[i].height
		end
	end
end

function Piece:screenshake(frames)
	self.shake = frames or 6
end

-- use gem_replace_table to force a specific color or custom gem
function Piece:addGems(gem_freq_table, gem_replace_table)
	self.gems = {}
	for i = 1, self.size do
		local gem_color = Gem.random(self.game, gem_freq_table)
		self.gems[i] = Gem:create{
			game = self.game,
			x = self.x,
			y = self.y,
			color = gem_color,
		}
		self.gems[i].is_in_piece = self
	end

	-- uses the real rng to decide which gem to replace, if single gem
	if gem_replace_table then
		if not gem_replace_table[1] then -- provided as single table
			local color = gem_replace_table.color
			local image = gem_replace_table.image
			local explode = gem_replace_table.exploding_gem_image
			local grey = gem_replace_table.grey_exploding_gem_image
			local pop = gem_replace_table.pop_particle_image
			local pos = self.game.rng:random(self.size)
			self.gems[pos]:setColor(color, image, explode, grey, pop)
		else
			for i = 1, #gem_replace_table do
				local color = gem_replace_table[i].color
				local image = gem_replace_table[i].image
				local explode = gem_replace_table[i].exploding_gem_image
				local grey = gem_replace_table[i].grey_exploding_gem_image
				local pop = gem_replace_table[i].pop_particle_image
				self.gems[i]:setColor(color, image, explode, grey, pop)
			end
		end
	end
	self:updateGems()
end

function Piece:change(target)
	self.queued_moves = self.queued_moves or {}
	Pic.change(self, target)
	self:updateGems()
end

function Piece:resolve()
	Pic.resolve(self)
end

function Piece:wait(frames)
	Pic.wait(self, frames)
end

function Piece:update(dt)
	Pic.update(self, dt)
	if self.shake then
		self.shake = self.shake - 1
		if self.shake == 0 then self.shake = nil end
	end
	if self._rotateTween then
		local complete = self._rotateTween:update(dt)
		if complete then self._rotateTween = nil end
	end
end

function Piece:isStationary()
	return not self.move_func
end

function Piece:rotate()
	if self._rotateTween then self._rotateTween:set(math.huge) end

	self.rotation_index = (self.rotation_index + 1) % 4
	self.is_horizontal = self.rotation_index % 2 == 0
	if self.is_horizontal then
		self.gems = reverseTable(self.gems)
	end

	self:updateGems()
	self.rotation = self.rotation % (2 * math.pi)

	--[[ piece has already rotated pi/2 clockwise. But we show
		the piece from its original starting location --]]
	local new_rotation = self.rotation
	self.rotation = self.rotation - (0.5 * math.pi)
	self._rotateTween = tween.new(1, self, {rotation = new_rotation}, 'outExpo')

	self.game.sound:newSFX("gemrotate")
end
-- same as rotate, but animations not shown
function Piece:ai_rotate()
	self.is_horizontal = not self.is_horizontal
	if self.is_horizontal then
		self.gems = reverseTable(self.gems)
	end
	self.rotation_index = (self.rotation_index + 1) % 4
end

function Piece:breakUp()
	local player = self.owner
	for i = 0, player.hand_size do
		if self == player.hand[i].piece then
			Pic.clear(self)
			player.hand[i].piece = nil
		end
	end
	return self.gems
end

-- draw gems with displacement depending on piece is_horizontal
function Piece:draw(params)
	local game = self.game
	local frame = game.frame
	local stage = game.stage
	--screen shake translation
	local h_shake, v_shake = 0, 0
	if self.shake then
		h_shake = math.floor(self.shake * (frame % 7 / 2 + frame % 13 / 4 + frame % 23 / 6 - 5))
		v_shake = math.floor(self.shake * (frame % 5 * 2/3 + frame % 11 / 4 + frame % 17 / 6 - 5))
	end

	local gem_darkened = params.darkened
	if (not self.owner:canPlacePiece() or game.current_phase ~= "Action") and
	self.owner == game.me_player then
		gem_darkened = 0.5
	end

	-- draw the gems
	love.graphics.push("all")
		love.graphics.translate(h_shake, v_shake)
		for i = 1, self.size do
			local gem_params = {piece = self, darkened = gem_darkened}
			for k, v in pairs(params) do gem_params[k] = v end
			self.gems[i]:draw(gem_params)
		end
	love.graphics.pop()
end

function Piece:getRect()
	local x = self.x - (self.gems[1].width / 2) * self.size
	local w = self.gems[1].width * self.size
	local y = self.y - (self.gems[1].height / 2) * self.size
	local h = self.gems[1].height * self.size
	return x, y, w, h
end

-- Returns the piece columns as an array of size (piece.size).
-- Shift can be either -1 or +1, used when the input is over the midline;
-- it forces the gem to be dropped to the left or the right of midline.
function Piece:getColumns(shift)
	local stage = self.game.stage
	local grid = self.game.grid
	local ret = {}
	shift = shift or 0
	if shift then shift = shift * images.GEM_WIDTH end

	if self.is_horizontal then
		for i = 1, self.size do
			ret[i] = false
			for j = 1, grid.COLUMNS do
				local in_this_column = pointIsInRect(
					self.gems[i].x + shift,
					self.gems[i].y,
					table.unpack(grid.active_rect[j])
				)
				if in_this_column then ret[i] = j end
			end
		end

	elseif not self.is_horizontal then
		for i = 1, self.size do ret[i] = false	end -- set array length
		for j = 1, grid.COLUMNS do
			local in_this_column = pointIsInRect(
				self.gems[1].x + shift,
				self.gems[1].y,
				table.unpack(grid.active_rect[j])
			)
			if in_this_column then
				for k = 1, #ret do ret[k] = j end
			end
		end

	else
		print("Exception: invalid horizontality")
	end
	return ret
end

-- Checks that all gems are within columns 1-8 and not overlapping midline.
-- accepts optional boolean to test for midline-shifted piece
function Piece:isDropLegal(test_shifted_piece)
	local shift = nil
	if test_shifted_piece then
		local midline, on_left = self:isOnMidline()
		if midline then	shift = on_left and -1 or 1	end
	end
	local cols = self:getColumns(shift)
	local gems_in_my_basin = 0
	for i = 1, self.size do
		if not cols[i] then
			return false
		elseif cols[i] >= self.owner.start_col and cols[i] <= self.owner.end_col then
			gems_in_my_basin = gems_in_my_basin + 1
		end
	end
	return gems_in_my_basin == self.size or gems_in_my_basin == 0
end

-- Checks that the drop location is legal, and also that the player has the
-- meter to play it. If gem is over midline, this function takes shift in order
-- to force the drop to a legal position.
function Piece:isDropValid(shift)
	local player = self.owner
	local place_type
	local cols = self:getColumns(shift)
	local gems_in_my_basin = 0
	if self.game.current_phase ~= "Action" then return false end
	for i = 1, self.size do
		if not cols[i] then
			return false
		elseif cols[i] >= player.start_col and cols[i] <= player.end_col then
			gems_in_my_basin = gems_in_my_basin + 1
		end
	end
	if not player.dropped_piece then
		if gems_in_my_basin == self.size then
			place_type = "normal"
		elseif gems_in_my_basin == 0 and self:isValidRush() then
			place_type = "rush"
		else
			return false
		end
	elseif gems_in_my_basin == self.size and player.cur_burst >= player.current_double_cost
		and player.dropped_piece == "normal" then
			place_type = "double"
	else
		return false
	end
	return true, place_type
end

-- Checks if the drop location is overlapping the midline.
function Piece:isOnMidline()
	local player = self.owner
	local cols = self:getColumns()
	local my_col, enemy_col = false, false
	for i = 1, self.size do
		if cols[i]
		and cols[i] >= player.start_col
		and cols[i] <= player.end_col then
			my_col = true
		elseif cols[i]
		and cols[i] >= player.enemy.start_col
		and cols[i] <= player.enemy.end_col then
			enemy_col = true
		end
	end

	if (my_col and enemy_col) then
		return true, self.game.stage:isOnLeft()
	else
		return false, nil
	end
end

-- Checks whether the rush placement is valid
-- current_rush_cost is optional
function Piece:isValidRush()
	local grid = self.game.grid
	local player = self.owner
	local cols = self:getColumns()
	local enough_burst = player.cur_burst >= player.current_rush_cost
	local row_ok = true
	for i = 1, self.size do
		local empty_row = grid:getFirstEmptyRow(cols[i], true)
		if empty_row < grid.RUSH_ROW then
			row_ok = false
			if self.game.particles.no_rush_check[cols[i]] == 0 then
				self.game.particles.words.generateNoRush(self.game, cols[i])
			else
				self.game.particles.no_rush_check[cols[i]] = 2
			end
		end
	end
	return enough_burst and row_ok
end

-- Generates dust when playing is holding the piece.
function Piece:generateDust()
	local game = self.game
	if game.frame % 12 == 0 then
		for i = 1, self.size do
			local gem = self.gems[i]
			local x_drift = (math.random() - 0.5) * gem.width
			local y_drift = (math.random() - 0.5) * gem.height
			game.particles.dust.generateFalling(game, gem, x_drift, y_drift)
		end
	end
end

-- When player picks up a piece. Called from gs_main.lua.
function Piece:select()
	local game = self.game
	game.active_piece = self
	self:resolve()
	for i = 1, self.size do -- generate some particles!
		local x, y, color = self.gems[i].x, self.gems[i].y, self.gems[i].color
		game.particles.dust.generateFountain(
			game,
			x,
			y,
			color,
			math.random(2, 6)
		)
	end
end

-- When player releases a piece. Called from gs_main.lua.
function Piece:deselect()
	local player = self.owner
	local shift = 0
	local midline, on_left = self:isOnMidline()
	if midline then
		if on_left then	shift = -1 else	shift = 1 end
	end
	local valid, place_type = self:isDropValid(shift)
	local cols = self:getColumns(shift)
	local go_ahead = (place_type == "normal") or
		(place_type == "rush" and self:isValidRush()) or
		(place_type == "double" and player.cur_burst >= player.current_double_cost)
	local char_ability_ok = player:pieceDroppedOK(self, shift)

	if valid
	and not self.game.inputs_frozen
	and go_ahead
	and char_ability_ok
	and self.game.current_phase == "Action" then
		self:dropIntoBasin(cols)
	else -- snap back to original place. Pic.change interferes with rotate tween
		self.x = player.hand[self.hand_idx].x
		self.y = player.hand[self.hand_idx].y
		self:updateGems()
	end
end

-- Transfers piece from player's hand into basin.
-- No error checking, assumes this is a valid move! Be careful please.
function Piece:dropIntoBasin(coords, received_from_opponent)
	local game = self.game
	local grid = game.grid
	local player = self.owner
	local hand = player.hand
	local start_col = player.player_num == 1 and 1 or 5
	local end_col = player.player_num == 1 and 4 or 8

	-- not received_from_opponent means it's our piece being placed
	-- therefore, so we need to send it to them
	if game.type == "Singleplayer" and not received_from_opponent then
		game.ai:writePlayerDelta(self, coords)
	elseif game.type == "Netplay" and not received_from_opponent then
		game.client:writeDeltaPiece(self, coords)
	end

	-- see if gem is in own columns or enemy columns
	local in_own_col, in_enemy_col = false, false
	for _, col in ipairs(coords) do
		if col >= start_col and col <= end_col then
			in_own_col = true
		else
			in_enemy_col = true
		end
		assert(
			(in_own_col and not in_enemy_col) or (not in_own_col and in_enemy_col),
			"Invalid piece column placement"
		)
	end

	-- place the gem into the holding area
	local row_adj -- how many rows down from the top to place the gem
	if player.dropped_piece == "normal" then
		if in_own_col then -- doublecast
			assert(player.cur_burst >= player.current_double_cost, "No meter for doublecast")

			row_adj = 2
			player.cur_burst = player.cur_burst - player.current_double_cost
			player.dropped_piece = "doubled"
			for i = 1, #self.gems do self.gems[i].place_type = "double" end
		else
			error("Attempted to doublecast with a rush piece")
		end
	elseif player.dropped_piece == "rushed" then
		error("Attempted to play another piece with rush already played")
	elseif player.dropped_piece == "doubled" then
		error("Attempted to play another piece with doublecast already played")
	else
		if in_own_col then -- normal
			row_adj = 4
			player.dropped_piece = "normal"
		else -- rush
			assert(player.cur_burst >= player.current_rush_cost, "No meter for rush")
			row_adj = 0
			player.cur_burst = player.cur_burst - player.current_rush_cost
			player.dropped_piece = "rushed"
			for i = 1, #self.gems do self.gems[i].place_type = "rush" end
		end
	end

	local locations = {}
	if self.is_horizontal then
		for i = 1, #self.gems do
			self.gems[i].is_from_horizontal_piece = true
			locations[i] = {1 + row_adj, coords[i]}
		end
	else
		for i = 1, #self.gems do
			self.gems[i].is_from_vertical_piece = true
			locations[i] = {i + row_adj, coords[i]}
		end
	end

	hand:movePieceToGrid(grid, self, locations)
	player.played_pieces[#player.played_pieces+1] = self.gems

	self:breakUp()

	-- refresh for new position for placement shadows if doublecast
	if player.dropped_piece == "doubled" then
		for _, v in pairs(game.particles.allParticles.PlacedGem) do
			if v.place_type == "normal" then v:tweenDown(true) end
		end
	end

	player:updateFurtherAction()
end

function Piece:getGems()
	local gems, index = {}, 0
	for i = 1, #self.gems do gems[#gems+1] = self.gems[i] end

	return function()
		index = index + 1
		return gems[index], index
	end
end

return common.class("Piece", Piece)
