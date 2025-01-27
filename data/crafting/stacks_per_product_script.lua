local log = radiant.log.create_logger('stacks_per_product')

local stacks_per_product = {}

function stacks_per_product.on_craft(ai, crafter, workshop, recipe, ingredients, product, item, extra_products)
   if not item or not item:is_valid() then
      return
   end
   
   local ing_stacks = {}
   local max_crafts = product.max_crafts

   for id, ingredient in pairs(ingredients) do
      if product.stacks_per_product then
         local uri = ingredient:get_uri()   
         local stacks_per = product.stacks_per_product[uri]
         local stacks_comp = ingredient:get_component('stonehearth:stacks')
         if stacks_per and stacks_comp then
            local uri_data = ing_stacks[uri]
            if uri_data then
               uri_data.stacks = uri_data.stacks + stacks_comp:get_stacks()
            else
               ing_stacks[uri] = {
                  stacks = stacks_comp:get_stacks(),
                  max_stacks = stacks_comp:get_max_stacks(),
                  stacks_per = stacks_per
               }
            end
         end
      end
   end

   for uri, ing_data in pairs(ing_stacks) do
      local num_crafts = math.floor(ing_data.stacks / ing_data.stacks_per)
      if max_crafts then
         max_crafts = math.min(num_crafts, max_crafts)
      else
         max_crafts = num_crafts
      end
   end

   for uri, ing_data in pairs(ing_stacks) do
      ing_data.stacks_remaining = ing_data.stacks - max_crafts * ing_data.stacks_per
   end

   -- then do stuff based on min_crafts
   -- if it's < 1, then it's our own fault for not specifying a high enough min_stacks for the ingredient
   -- if it's >= 1, create that many of the product and additional copies of the ingredients for any remaining stacks
   for i = 2, max_crafts do
      table.insert(extra_products, product.item)
   end

   for uri, ing_data in pairs(ing_stacks) do
      if ing_data.stacks_remaining > 0 then
         local num_full = math.floor(ing_data.stacks_remaining / ing_data.max_stacks)
         local extra = ing_data.stacks_remaining - num_full
         for i = 1, num_full do
            table.insert(extra_products, stacks_per_product._create_item_with_stacks(uri, crafter))
         end
         if extra > 0 then
            table.insert(extra_products, stacks_per_product._create_item_with_stacks(uri, crafter, extra))
         end
      end
   end

   log:debug('crafting %s total products; extra products: %s', max_crafts, radiant.util.table_tostring(extra_products))
end

function stacks_per_product._create_item_with_stacks(uri, owner, stacks)
   local item = radiant.entities.create_entity(uri, { owner = owner })
   local entity_forms = item:get_component('stonehearth:entity_forms')
   if entity_forms then
      local iconic_entity = entity_forms:get_iconic_entity()
      if iconic_entity then
         item = iconic_entity
      end
   end

   local stacks_comp = item:get_component('stonehearth:stacks')
   if stacks_comp and stacks then
      stacks_comp:set_stacks(stacks)
   end

   return item
end

return stacks_per_product