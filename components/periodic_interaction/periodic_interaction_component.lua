--[[
   Behaves similarly to 'stonehearth:workshop':
    - gets "reserved" by a single person at a time; only that person can use it until the interaction sequence is complete
    - if that person changes jobs, they'll unreserve it
   Allow for selection of none, all, or a specific qualified user with ownership-style UI
   Allow for selection of one of many "modes" of interaction with a dropdown (hide if only one mode available)
    - each mode has usage requirements (job, level, general cooldown, eqiupped item, etc.)
    - each mode can specify multiple weighted sequences; selection is chosen on activate for all modes
    - each sequence specifies one or more ordered interactions
    - each interaction has a cooldown, possible rewards, chance to complete the sequence, required ingredient?

   json component data (most fields are optional):
   "stonehearth_ace:periodic_interaction": {
      "default_model": "model_name",
      "reset_effect": "stonehearth_ace:effects:reset_effect",
      "transform_after_using_key": "disable_after_use",
      "transform_after_num_uses": 5,
      "allow_mode_selection": true,
      "modes": {
         "find_native_seed": {
            "ai_status_key": "stonehearth_ace:ai.actions.status_text.periodic_interaction.find_native_seed.default",
            "ui_data": {
               "display_name": "i18n(stonehearth_ace:jobs.herbalist.herbalist_exploration_garden.periodic_interaction.modes.find_native_seed.name)",
               "description": "i18n(stonehearth_ace:jobs.herbalist.herbalist_exploration_garden.periodic_interaction.modes.find_native_seed.description)"
            },
            "cooldown": "12h",
            "requirements": {
               "job": "stonehearth:jobs:herbalist",
               "level": 2,
               "equipped_item": "stonehearth_ace:herbalist:tools:simple_trowel"
            },
            "completion": {
               "rewards": [
                  {
                     "type": "experience",
                     "value": 25
                  }
               ]
            },
            "sequences": {  "__comment": "keys here are just for the designer's convenience",
               "quick": [
                  {
                     "effect": "stonehearth_ace:effects:static_effect",
                     "interaction_effect": "stonehearth_ace:effects:something_happens",
                     "cooldown": "4h",
                     "model": "stage_1",
                     "num_interactions": 3,
                     "interaction_points": [
                        {
                           "ai_status_key": "stonehearth_ace:ai.actions.status_text.periodic_interaction.find_native_seed.specific_1",
                           "worker_effect": "fiddle",
                           "weight": 3,
                           "point": [2, 0, 3]
                        },
                        {
                           "worker_effect": "fiddle",
                           "weight": 1,
                           "point": [1, 0, 1]
                        },
                        {
                           "worker_effect": "fiddle",
                           "weight": 1,
                           "point": [3, 0, 2]
                        }
                     ],
                     "rewards": [
                        {
                           "type": "experience",
                           "value": 10
                        },
                        {
                           "type": "script",
                           "script": "stonehearth_ace:scripts:periodic_interaction:herbalist_exploration_garden:rewards",
                           "script_data": {
                              "crop_category": "herb",
                              "none": 90,
                              "native": 10
                           }
                        }
                     ]
                  },
                  {
                     "effect": "stonehearth_ace:effects:static_effect",
                     "interaction_effect": "stonehearth_ace:effects:something_happens",
                     "cooldown": "4h",
                     "model": "stage_2",
                     "num_interactions": 3,
                     "interaction_points": [
                        {
                           "worker_effect": "fiddle",
                           "weight": 1,
                           "point": [2, 0, 3]
                        },
                        {
                           "worker_effect": "fiddle",
                           "weight": 3,
                           "point": [1, 0, 1]
                        },
                        {
                           "worker_effect": "fiddle",
                           "weight": 1,
                           "point": [3, 0, 2]
                        }
                     ],
                     "rewards": [
                        {
                           "type": "experience",
                           "value": 10
                        },
                        {
                           "type": "script",
                           "script": "stonehearth_ace:scripts:periodic_interaction:herbalist_exploration_garden:rewards",
                           "script_data": {
                              "crop_category": "herb",
                              "none": 69,
                              "native": 30,
                              "exotic": 1
                           }
                        }
                     ]
                  },
                  {
                     "effect": "stonehearth_ace:effects:static_effect",
                     "interaction_effect": "stonehearth_ace:effects:something_happens",
                     "model": "stage_3",
                     "num_interactions": 3,
                     "interaction_points": [
                        {
                           "worker_effect": "fiddle",
                           "weight": 1,
                           "point": [2, 0, 3]
                        },
                        {
                           "worker_effect": "fiddle",
                           "weight": 1,
                           "point": [1, 0, 1]
                        },
                        {
                           "worker_effect": "fiddle",
                           "weight": 3,
                           "point": [3, 0, 2]
                        }
                     ],
                     "rewards": [
                        {
                           "type": "experience",
                           "value": 10
                        },
                        {
                           "type": "script",
                           "script": "stonehearth_ace:scripts:periodic_interaction:herbalist_exploration_garden:rewards",
                           "script_data": {
                              "crop_category": "herb",
                              "native": 95,
                              "exotic": 5
                           }
                        }
                     ]
                  }
               ]
            }
         },
         "find_exotic_seed": {

         }
      }
   }
]]

local WeightedSet = require 'stonehearth.lib.algorithms.weighted_set'
local rng = _radiant.math.get_default_rng()

local PeriodicInteractionComponent = class()

local log = radiant.log.create_logger('periodic_interaction')

function PeriodicInteractionComponent:initialize()
   self._json = radiant.entities.get_json(self) or {}

   self._sv._mode_sequences = {}
   self._sv.ui_data = {}
   self._sv.current_mode = nil
   self._sv.current_user = nil
   self._sv.current_owner = nil
   self._sv.interaction_stage = 1
   self._sv.num_uses = 0
   self._sv.enabled = self._json.start_enabled ~= false
   self._sv.allow_mode_selection = self._json.allow_mode_selection ~= false
   self._sv._general_cooldown_timer = nil
   self._sv._interaction_cooldown_timer = nil
end

function PeriodicInteractionComponent:activate()
   self:_setup_ui_data()
   self:_select_mode_sequences()
end

function PeriodicInteractionComponent:post_activate()
   --Trace the parent to figure out if it's added or not:
   self._parent_trace = self._entity:add_component('mob'):trace_parent('periodic_interaction added or removed from world')
      :on_changed(function(parent_entity)
            if not parent_entity then
               --we were just removed from the world
               self:_shutdown()
            else
               --we were just added to the world
               self:_startup()
            end
         end)

   self:_startup()
end

function PeriodicInteractionComponent:destroy()
   if self._consider_usability_timer then
      self._consider_usability_timer:destroy()
      self._consider_usability_timer = nil
   end
   if self._parent_trace then
      self._parent_trace:destroy()
      self._parent_trace = nil
   end
   if self._interaction_stage_effect then
      self._interaction_stage_effect:stop()
      self._interaction_stage_effect = nil
   end
   if self._interaction_effect then
      self._interaction_effect:stop()
      self._interaction_effect = nil
   end
end

function PeriodicInteractionComponent:_startup()
   local location = radiant.entities.get_world_grid_location(self._entity)
   if not location then
      return
   end

   self:select_mode(self._sv.current_mode)
   self:_setup_consider_usability_timer()
   self:_consider_usability()
end

function PeriodicInteractionComponent:_shutdown()
   self:cancel_using(self._sv.current_user)
end

function PeriodicInteractionComponent:get_valid_users_command(session, response)
   local users = self:get_valid_potential_users()
   response:resolve({users = users})
end

function PeriodicInteractionComponent:set_enabled_command(session, response, enabled)
   self:set_enabled(enabled)
   return true
end

function PeriodicInteractionComponent:select_mode_command(session, response, mode)
   self:select_mode(mode)
   return true
end

function PeriodicInteractionComponent:set_owner_command(session, response, owner)
   self._sv.current_owner = owner
   self.__saved_variables:mark_changed()
   return true
end

function PeriodicInteractionComponent:is_enabled()
   return self._sv.enabled
end

function PeriodicInteractionComponent:set_enabled(enabled)
   self._sv.enabled = enabled
   self.__saved_variables:mark_changed()
end

function PeriodicInteractionComponent:get_current_mode()
   return self._sv.current_mode
end

function PeriodicInteractionComponent:get_current_user()
   return self._sv.current_user
end

function PeriodicInteractionComponent:start_using(user)
   if self._sv.current_user == user or not self._sv.current_user then
      self._sv.current_user = user
      self.__saved_variables:mark_changed()

      self._in_use = true
   end
end

function PeriodicInteractionComponent:cancel_using(user)
   if self._sv.current_user == user then
      self:_reset(false)
      self:_cancel_usage()
   end
end

function PeriodicInteractionComponent:_setup_consider_usability_timer()
   -- is this better than having the ai do find_best_reachable_entity_by_type?
   self._consider_usability_timer = stonehearth.calendar:set_interval('PeriodicInteraction consider_usability', '10m', function()
         self:_consider_usability()
      end)
end

function PeriodicInteractionComponent:_reset(completed)
   self._sv.interaction_stage = 1
   self._in_use = false

   -- if the interaction was completed, handle any rewards and then clear out the current sequence for it and set up a new one
   if completed then
      local completion_data = self._current_mode_data.completion
      if completion_data then
         if completion_data.rewards then
            self:_apply_rewards(completion_data.rewards, true)
         end
      end

      self._sv._mode_sequences[self._sv.current_mode] = nil
      self._sv.num_uses = self._sv.num_uses + 1

      if self._json.transform_after_using_key and self._json.transform_after_num_uses and self._sv.num_uses >= self._json.transform_after_num_uses then
         -- instead of doing any other resetting at this point, transform the entity
         local transform_comp = self._entity:add_component('stonehearth_ace:transform')
         if transform_comp then
            transform_comp:set_transform_option(self._json.transform_after_using_key)
            transform_comp:request_transform(self._entity:get_player_id())
            return
         end
      end

      self:_select_mode_sequences()
   end

   self._sv.current_user = nil

   if self._json.reset_effect then
      radiant.effects.run_effect(self._entity, self._json.reset_effect)
   end

   self._entity:add_component('render_info'):set_model_variant(self._json.default_model or 'default')

   self:select_mode(self._sv.current_mode)
end

function PeriodicInteractionComponent:_cancel_usage()
   radiant.events.trigger_async(self._entity, 'stonehearth_ace:periodic_interaction:cancel_usage')
end

function PeriodicInteractionComponent:_setup_ui_data()
   for id, data in pairs(self._json.modes) do
      self._sv.ui_data[id] = data.ui_data
   end
   self._sv.show_mode_selection = self._json.show_mode_selection

   self.__saved_variables:mark_changed()
end

function PeriodicInteractionComponent:_select_mode_sequences()
   -- remove any modes that don't have a definition in the json
   for id, _ in pairs(self._sv._mode_sequences) do
      if not self._json.modes[id] then
         self._sv._mode_sequences[id] = nil
      end
   end

   for id, data in pairs(self._json.modes) do
      if self._sv._mode_sequences[id] == nil then
         local sequences = WeightedSet(rng)
         for key, sequence in pairs(data.sequences) do
            sequences:add(key, sequence.weight or 1)
         end
         self._sv._mode_sequences[id] = sequences:choose_random()
      end
   end
end

function PeriodicInteractionComponent:select_mode(mode)
   if not mode or not self._sv._mode_sequences[mode] then
      mode = next(self._sv._mode_sequences)
   end

   self._current_mode_data = self._json.modes[mode]
   self._current_sequence = self._sv._mode_sequences[mode]
   self._current_sequence_data = self._current_mode_data.sequences[self._current_sequence]

   if mode ~= self._sv.current_mode then
      self:_cancel_usage()
      self._sv.current_mode = mode
      self.__saved_variables:mark_changed()
   end

   -- TODO: cancel any current interaction
   self:_stop_interaction_cooldown_timer()
   self:_apply_current_stage_settings()
   self:_consider_usability()
end

function PeriodicInteractionComponent:get_current_mode_ai_status()
   local status = self._current_mode_data and self._current_mode_data.ai_status_key
   return status or 'stonehearth_ace:ai.actions.status_text.periodic_interaction.default'
end

function PeriodicInteractionComponent:get_valid_potential_users()
   local users = {}
   local pop = stonehearth.population:get_population(self._entity)

   for id, citizen in pop:get_citizens():each() do
      if self:is_valid_potential_user(citizen) then
         table.insert(users, citizen)
      end
   end

   return users
end

function PeriodicInteractionComponent:is_valid_potential_user(entity)
   if entity and entity:is_valid() then
      local requirements = self._current_mode_data.requirements
      
      if requirements.job then
         local job_component = entity:get_component('stonehearth:job')
         if not job_component or job_component:get_job_uri() ~= requirements.job then
            return false
         end

         if requirements.level and job_component:get_current_job_level() < requirements.level then
            return false
         end
      end

      if requirements.equipped_item then
         local equipment_component = entity:get_component('stonehearth:equipment')
         if not equipment_component then
            return false
         end

         -- go through all of the items specified in equipped_item
         -- if *any* of them are equipped, the condition is satisfied
         local has_equipped = false
         local items = requirements.equipped_item
         if type(items) == 'string' then
            items = {items}
         end

         for _, item in ipairs(items) do
            if equipment_component:has_item_type(item) then
               has_equipped = true
               break
            end
         end

         if not has_equipped then
            return false
         end
      end

      return true
   end
end

function PeriodicInteractionComponent:get_current_interaction()
   return self._current_sequence_data and self._current_sequence_data[self._sv.interaction_stage]
end

function PeriodicInteractionComponent:set_current_interaction_completed(user)
   local current_interaction = self:get_current_interaction()
   if not current_interaction then
      return
   end

   self._sv.current_user = user
   self._in_use = false

   -- apply any rewards
   local completed = self:_apply_rewards(current_interaction.rewards, false)
   
   -- if this was the first interaction for this sequence, start the general cooldown
   if self._sv.interaction_stage == 1 and self._current_mode_data.cooldown then
      self:_start_general_cooldown_timer(self._current_mode_data.cooldown)
   end

   if completed then
      self:_reset(true)
   else
      self:_start_interaction_cooldown_timer(current_interaction.cooldown)
      self._sv.interaction_stage = self._sv.interaction_stage + 1
      self.__saved_variables:mark_changed()

      current_interaction = self:get_current_interaction()
      if not current_interaction then
         -- if there's no interaction for this stage, we must've completed it
         self:_reset(true)
      else
         self:_apply_current_stage_settings()
         self:_start_interaction_cooldown_timer(current_interaction.cooldown)
      end
   end
end

function PeriodicInteractionComponent:_apply_current_stage_settings()
   local current_interaction = self:get_current_interaction()
   if current_interaction then
      -- apply model/effect, etc.
      if current_interaction.model then
         self._entity:add_component('render_info'):set_model_variant(current_interaction.model)
      end
      if current_interaction.effect then
         self:_set_interaction_stage_effect(current_interaction.effect)
      end
   end
end

function PeriodicInteractionComponent:_set_interaction_stage_effect(effect)
   if self._interaction_stage_effect then
      self._interaction_stage_effect:stop()
      self._interaction_stage_effect = nil
   end

   if effect then
      self._interaction_stage_effect = radiant.effects.run_effect(self._entity, effect)
   end
end

function PeriodicInteractionComponent:set_interaction_effect(effect)
   if self._interaction_effect then
      self._interaction_effect:stop()
      self._interaction_effect = nil
   end

   if effect then
      self._interaction_effect = radiant.effects.run_effect(self._entity, effect)
   end
end

function PeriodicInteractionComponent:_apply_rewards(rewards, is_completed)
   local user = self._sv.current_user
   if not rewards or not user or not user:is_valid() then
      -- can't apply a reward without rewards or a recipient!
      return
   end

   local completed = false

   for _, reward in ipairs(rewards) do
      completed = completed or self:_apply_reward(reward, is_completed)
   end

   return completed
end

-- different types of rewards: user_buff, self_buff, experience, permanent_attribute, expendable_resource, script
function PeriodicInteractionComponent:_apply_reward(reward, is_completed)
   local user = self._sv.current_user
   
   if reward.type == 'user_buff' then
      user:add_component('stonehearth:buffs'):add_buff(reward.buff)
   elseif reward.type == 'self_buff' then
      self._entity:add_component('stonehearth:buffs'):add_buff(reward.buff)
   elseif reward.type == 'experience' then
      local job_component = user:get_component('stonehearth:job')
      if job_component then
         local level = job_component:get_current_job_level()
         job_component:add_exp(reward.value)
         if reward.levelup_triggers_completion and level < job_component:get_current_job_level() then
            return true
         end
      end
   elseif reward.type == 'permanent_attribute' then
      local attributes_component = user:add_component('stonehearth:attributes')
      local cur_value = attributes_component:get_attribute(reward.attribute)
      attributes_component:set_attribute(reward.attribute, cur_value + reward.amount or 1)
   elseif reward.type == 'expendable_resource' then
      local expendable_resources_component = user:add_component('stonehearth:expendable_resources')
      if reward.maximize then
         expendable_resources_component:set_value(reward.resource, expendable_resources_component:get_max_value(reward.resource))
      elseif reward.minimize then
         expendable_resources_component:set_value(reward.resource, expendable_resources_component:get_min_value(reward.resource))
      else
         local cur_value = expendable_resources_component:get_value(reward.resource)
         expendable_resources_component:set_value(reward.resource, cur_value + reward.amount or 0)
      end
   elseif reward.type == 'script' then
      local script = radiant.mods.load_script(reward.script)
      if script and script.process_reward then
         return script.process_reward(self._entity, user, self._sv.interaction_stage, reward.script_data, is_completed)
      end
   end

   return false
end

function PeriodicInteractionComponent:_start_general_cooldown_timer(duration)
   if not self._sv._general_cooldown_timer and duration then
      self._sv._general_cooldown_timer = stonehearth.calendar:set_persistent_timer("PeriodicInteraction general",
            duration, radiant.bind(self, '_general_cooldown_finished'))
   end
end

function PeriodicInteractionComponent:_start_interaction_cooldown_timer(duration)
   if not self._sv._interaction_cooldown_timer and duration then
      self._sv._interaction_cooldown_timer = stonehearth.calendar:set_persistent_timer("PeriodicInteraction interaction",
            duration, radiant.bind(self, '_interaction_cooldown_finished'))
   end
end

function PeriodicInteractionComponent:_stop_interaction_cooldown_timer()
   if self._sv._interaction_cooldown_timer then
      self._sv._interaction_cooldown_timer:destroy()
      self._sv._interaction_cooldown_timer = nil
   end
end

function PeriodicInteractionComponent:_general_cooldown_finished()
   self._sv._general_cooldown_timer = nil

   self:_consider_usability()
end

function PeriodicInteractionComponent:_interaction_cooldown_finished()
   self._sv._interaction_cooldown_timer = nil

   self:_consider_usability()
end

-- consider whether (and who) to alert that this entity can be interacted with
function PeriodicInteractionComponent:_consider_usability()
   -- if it's disabled or still on interaction cooldown or actively being used, don't inform anyone
   if not self._sv.enabled or self._sv._interaction_cooldown_timer or self._in_use then
      return
   end

   -- if it's not in the world, it's not actually usable, so make sure it's reset and don't inform anyone
   local location = radiant.entities.get_world_grid_location(self._entity)
   if not location then
      self:_reset(false)
      return
   end

   -- if we already have a user assigned, first ensure that user is stil valid;
   -- if so, only inform that user; otherwise, reset interaction so someone else can start
   if self._sv.current_user then
      if self:is_valid_potential_user(self._sv.current_user) then
         self:_inform_potential_user(self._sv.current_user)
      else
         self:_reset(false)
      end
      return
   end

   -- if it's still on general cooldown, don't inform anyone else
   if self._sv._general_cooldown_timer then
      return
   end

   -- next check if somebody owns this entity
   -- if so, check if they're still a valid user
   -- if they are, inform them; otherwise, clear ownership and inform all valid potential users
   -- we can't use base game ownership model because it's one-to-one and requires all hearthlings to be allowed to use that type
   local owner = self._sv.current_owner
   if owner then
      if self:is_valid_potential_user(owner) then
         self:_inform_potential_user(owner)
         return
      else
         self._sv.current_owner = nil
         self.__saved_variables:mark_changed()
      end
   end
   
   local potential_users = self:get_valid_potential_users()
   for _, user in ipairs(potential_users) do
      self:_inform_potential_user(user)
   end
end

function PeriodicInteractionComponent:_inform_potential_user(entity)
   --log:debug('%s informing potential user %s of usability...', self._entity, entity)
   radiant.events.trigger_async(entity, 'stonehearth_ace:periodic_interaction:became_usable', self._entity, self._sv.current_mode)
end

return PeriodicInteractionComponent