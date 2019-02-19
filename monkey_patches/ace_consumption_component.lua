local ConsumptionComponent = require 'stonehearth.components.consumption.consumption_component'

local AceConsumptionComponent = class()

AceConsumptionComponent._ace_old_activate = ConsumptionComponent.activate
function AceConsumptionComponent:activate()   
   self._sv._food_intolerances = ''
   self:_ace_old_activate()  
end

function AceConsumptionComponent:set_food_intolerances(intolerances)
   self._sv._food_intolerances = intolerances
end

function AceConsumptionComponent:_get_quality(food)
   local food_data = radiant.entities.get_entity_data(food, 'stonehearth:food', false)

   if not food_data then
      radiant.assert(false, 'Trying to eat a piece of food that has no entity data.')
      return -1
   end

   if not food_data.quality then
      log:error('Food %s has no quality entry, defaulting quality to raw & bland.', food)
   end

   if self:_has_food_preferences() then
      if not radiant.entities.is_material(food, self._sv._food_preferences) then
         return stonehearth.constants.food_qualities.UNPALATABLE
      end
   end
   
   if self:_has_food_intolerances() then
      if radiant.entities.is_material(food, self._sv._food_intolerances) then
	     radiant.entities.add_buff(self._entity, 'stonehearth_ace:buffs:upset_belly')
         return stonehearth.constants.food_qualities.INTOLERABLE	 
      end
   end
   return food_data.quality or stonehearth.constants.food_qualities.RAW_BLAND
   
end

function ConsumptionComponent:_has_food_intolerances()
   return self._sv._food_intolerances ~= ''
end

return AceConsumptionComponent