local love = _G.love

local common = require "class.commons"
local Character = require "character"
local image = require 'image'

local Hailey = {}

Hailey.full_size_image = love.graphics.newImage('images/characters/hailey.png')
Hailey.small_image = love.graphics.newImage('images/characters/haileysmall.png')
Hailey.character_id = "Hailey"
Hailey.meter_gain = {red = 4, blue = 8, green = 4, yellow = 4}
--[[
Hailey.super_images = {
	word = image.UI.super.blue_word,
	partial = image.UI.super.blue_partial,
	full = image.UI.super.blue_full,
	glow = {image.UI.super.blue_glow1, image.UI.super.blue_glow2, image.UI.super.blue_glow3, image.UI.super.blue_glow4}
}
--]]
Hailey.burst_images = {
	word = image.UI.burst.blue_word,
	partial = image.UI.burst.blue_partial,
	full = image.UI.burst.blue_full,
	glow = {image.UI.burst.blue_glow1, image.UI.burst.blue_glow2}
}

return common.class("Hailey", Hailey, Character)