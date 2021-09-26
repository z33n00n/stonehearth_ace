local rng = _radiant.math.get_default_rng()
local WeatherState = require 'stonehearth.services.server.weather.weather_state'

local AceWeatherState = class()

AceWeatherState._ace_old_create = WeatherState.create
function AceWeatherState:create(uri)
   self:_ace_old_create(uri)
   self:_load_ace_values()
end

AceWeatherState._ace_old_restore = WeatherState.restore
function AceWeatherState:restore()
   self:_ace_old_restore()

   if not self._sv.sunlight or type(self._sv.unsheltered_debuff) == 'string' or type(self._sv.unsheltered_animal_debuff) == 'string' then
      self:_load_ace_values()
   end
end

function AceWeatherState:start(instigating_player_id)
   self._sv.is_active = true

   if self._sv.thoughts then
      self:_for_each_player_character(function(citizen)
            radiant.entities.add_thought(citizen, self._sv.thoughts[rng:get_int(1, #self._sv.thoughts)])
         end)
   end

   if self._sv.unsheltered_debuff or self._sv.unsheltered_animal_debuff or self._sv.unsheltered_npc_debuff then
      self._sv._unsheltered_debuff_timer = stonehearth.calendar:set_persistent_interval('weather buff', self._sv.buff_application_interval, radiant.bind(self, '_apply_buffs'))
      self:_apply_buffs()
   end

   if self._sv.subject_matter then
      self:_for_each_player_character(function(citizen)
            local subjects = citizen:get_component('stonehearth:subject_matter')
            if subjects then
                  subjects:add_subject(self._sv.subject_matter)
            end
         end)
   end

   if self._sv.vision_multiplier then
      stonehearth.terrain:set_sight_radius_multiplier(self._sv.vision_multiplier)  -- We could technically be overriding something, but fine for now.
   end

   if self._sv.script_controller and self._sv.script_controller.start then
      self._sv.script_controller:start(instigating_player_id)
   end

   self.__saved_variables:mark_changed()

   radiant.events.trigger(radiant, 'stonehearth_ace:weather_state_started', self)
end

function AceWeatherState:_load_ace_values()
   local json = radiant.resources.load_json(self._sv.uri, true, true)
   self._json = json
   self._sv._base_sunlight = json.sunlight or 1
   self._sv.sunlight = self._sv._base_sunlight
   self._sv._base_humidity = json.humidity or 0
   self._sv.humidity = self._sv._base_humidity
   self._sv.frozen = json.frozen or false
	self._sv.unsheltered_npc_debuff = json.unsheltered_npc_debuff or nil
   self._sv.music_sound_key = json.music_sound_key or nil
   self._sv.buff_application_interval = json.buff_application_interval or '20m'
   
   if type(self._sv.unsheltered_debuff) == 'string' then
      self._sv.unsheltered_debuff = { self._sv.unsheltered_debuff }
   end
   if type(self._sv.unsheltered_animal_debuff) == 'string' then
      self._sv.unsheltered_animal_debuff = { self._sv.unsheltered_animal_debuff }
   end
	if type(self._sv.unsheltered_npc_debuff) == 'string' then
      self._sv.unsheltered_npc_debuff = { self._sv.unsheltered_npc_debuff }
   end

   self.__saved_variables:mark_changed()
end

function AceWeatherState:_apply_buffs()
   local add_buff = function(entity, buff)
      local location = radiant.entities.get_world_grid_location(entity)
      if not location then
         return
      end
      if stonehearth.terrain:is_sheltered(location) then
         return
      end
      if self._sv.unsheltered_resistance_buff and radiant.entities.has_buff(entity, self._sv.unsheltered_resistance_buff) then
         return
      end
      
      radiant.entities.add_buff(entity, buff)
   end

   local try_apply_buffs = function(debuffs, fn_apply)
      if debuffs then
         for _, debuff in ipairs(debuffs) do
            if type(debuff) == 'string' then
               fn_apply(debuff)
            else
               if debuff.time == 'day' and stonehearth.calendar:is_daytime() then
                  fn_apply(debuff.debuff)
               elseif debuff.time == 'night' and not stonehearth.calendar:is_daytime() then
                  fn_apply(debuff.debuff)
               else
                  if type(debuff.time) == 'number' and debuff.end_time and type(debuff.end_time) == 'number' then
                     local now = stonehearth.calendar:get_time_and_date()
                     if debuff.time < now.hour and now.hour < debuff.end_time then
                        fn_apply(debuff.debuff)
                     end
                  end
               end
            end
         end
      end
   end

   -- Citizen debuff
   try_apply_buffs(self._sv.unsheltered_debuff,
      function(debuff)
         self:_for_each_player_character(function(citizen)
            add_buff(citizen, debuff)
         end)
      end)

   -- Pasture animal debuff
   try_apply_buffs(self._sv.unsheltered_animal_debuff,
      function(debuff)
         for player_id, _ in pairs(stonehearth.player:get_non_npc_players()) do
            for _, animal in pairs(stonehearth.town:get_town(player_id):get_pasture_animals()) do
               add_buff(animal, debuff)
            end
         end
      end)
	
	-- NPC debuff
   try_apply_buffs(self._sv.unsheltered_npc_debuff,
   function(debuff)
      self:_for_common_npc_character(function(npc)
         add_buff(npc, debuff)
      end)
   end)
end

function AceWeatherState:_for_common_npc_character(fn)
   local pops = stonehearth.population:get_all_populations()
   for player_id, pop in pairs(pops) do
		if stonehearth.constants.weather.kingdoms_affected_by_weather[player_id] then
         for _, citizen in pop:get_citizens():each() do
            fn(citizen)
			end
		end
	end
end

function AceWeatherState:get_unsheltered_animal_debuffs()
   return self._sv.unsheltered_animal_debuff
end

function AceWeatherState:get_unsheltered_npc_debuffs()
   return self._sv.unsheltered_npc_debuff
end

function AceWeatherState:set_sunlight(value)
   self._sv.sunlight = value
   self.__saved_variables:mark_changed()
end

function AceWeatherState:get_sunlight()
   return self._sv.sunlight
end

function AceWeatherState:get_base_sunlight()
   return self._sv._base_sunlight
end

function AceWeatherState:set_humidity(value)
   self._sv.humidity = value
   self.__saved_variables:mark_changed()
end

function AceWeatherState:get_humidity()
   return self._sv.humidity
end

function AceWeatherState:get_base_humidity()
   return self._sv._base_humidity
end

function AceWeatherState:get_frozen()
   return self._sv.frozen
end

function AceWeatherState:get_json()
   return self._json
end

return AceWeatherState
