local load_time_start = os.clock()
treecapitator = {}


--------------------------------------Setting-----------------------------------------------

treecapitator.drop_items = false	--drop them / get them in the inventory
treecapitator.drop_leaf = false
treecapitator.default_tree = {	--replaces not defined stuff (see below)
	trees = {"default:tree"},
	leaves = {"default:leaves"},
	range = 2,
	fruits = {},
}

---------------------------------------------------------------------------------------------


treecapitator.trees = {}
local num = 1

function treecapitator.register_tree(tab)
	for name,value in pairs(treecapitator.default_tree) do
		tab[name] = tab[name] or value	--replaces not defined stuff
	end
	treecapitator.trees[num] = tab
	num = num+1
end

dofile(minetest.get_modpath("treecapitator").."/trees.lua")


--------------------------------------------fcts----------------------------------------------

local destroy_node, drop_leaf, remove_leaf
if treecapitator.drop_items then
	function drop_leaf(pos, item, inv)
		minetest.add_item(pos, item)
	end

	function destroy_node(pos, node, digger)
		local drops = minetest.get_node_drops(node.name)
		for _,item in ipairs(drops) do
			minetest.add_item(pos, item)
		end
		minetest.remove_node(pos)
	end
else
	function drop_leaf(pos, item, inv)
		if inv
		and inv:room_for_item("main", item) then
			inv:add_item("main", item)
		else
			minetest.add_item(pos, item)
		end
	end

	function destroy_node(pos, node, digger)
		minetest.node_dig(pos, node, digger)
	end
end

if not treecapitator.drop_leaf then
	function remove_leaf(p, leaf, inv)
		local leaves_drops = minetest.get_node_drops(leaf)
		for _, itemname in ipairs(leaves_drops) do
			if itemname ~= leaf then
				drop_leaf(p, itemname, inv)
			end
		end
		minetest.remove_node(p)	--remove the leaves
	end
else
	function remove_leaf(p, _, _, node, digger)
		destroy_node(p, node, digger)
	end
end

table.icontains = table.icontains or function(t, v)
	for _,i in ipairs(t) do
		if i == v then
			return true
		end
	end
	return false
end

local function table_contains_pos(t, v)
	for _,i in ipairs(t) do
		if i.z == v.z
		and i.y == v.y
		and i.x == v.x then
			return true
		end
	end
	return false
end

local function findtree(nodename)
	for _,tr in ipairs(treecapitator.trees) do
		if table.icontains(tr.trees, nodename) then
			return true
		end
	end
	return false
end

local function find_next_trees(pos, range, trees, leaves, fruits)
	local tab = {}
	local r = 2*range
	for i = -r, r do
		for j = -r, r do
			for h = r,-r,-1 do
				local p = {x=pos.x+j, y=pos.y+h, z=pos.z+i}

				local leaf = minetest.get_node({x=p.x, y=p.y+1, z=p.z}).name
				local leaf_found = table.icontains(leaves, leaf) or table.icontains(fruits, leaf)
				if not leaf_found then
					leaf = minetest.get_node({x=p.x, y=p.y, z=p.z+1}).name
					leaf_found = table.icontains(leaves, leaf) or table.icontains(fruits, leaf)
				end

				if table.icontains(trees, minetest.get_node(p).name)
				and leaf_found then
					for z = -range+i,range+i do	--fix here
						for y = -range+h,range+h do
							for x = -range+j,range+j do
								if math.abs(z) <= range
								and math.abs(y) <= range
								and math.abs(x) <= range then
									tab[z.." "..y.." "..x] = true
								end
							end
						end
					end
				end
			end
		end
	end
	--minetest.chat_send_all(dump(tab))	<— I used these to find my mistake
	local tab2,n = {},1
	for z = -range,range do
		for y = -range,range do
			for x = -range,range do
				if not tab[z.." "..y.." "..x] then
					local p = {x=x, y=y, z=z}
					tab2[n] = p
					n = n+1
				end
			end
		end
	end
	return tab2
end


local capitating = false	--necessary if minetest.node_dig is used
minetest.register_on_dignode(function(pos, node, digger)
	if capitating then
		return
	end
	--minetest.chat_send_all("test0")	<— and this
	if digger == nil then
		return
	end
    if digger:get_player_control().sneak
    or not findtree(node.name) then
		return
	end
	local t1 = os.clock()
	capitating = true
	for _,tr in ipairs(treecapitator.trees) do
		local np = {x=pos.x, y=pos.y+1, z=pos.z}
		local nd = minetest.get_node(np)
		local trees = tr.trees
		local tree_found = table.icontains(trees, nd.name)
		if tree_found then
			local tab, n = {}, 1
			while tree_found do
				tab[n] = {vector.new(np), nd}
				n = n+1
				np.y = np.y+1
				nd = minetest.get_node(np)
				tree_found = table.icontains(trees, nd.name)
			end
			local leaves = tr.leaves
			local fruits = tr.fruits

			np.y = np.y-1
			local leaf_found = table.icontains(leaves, nd.name) or table.icontains(fruits, nd.name)
			if not leaf_found then
				local leaf = minetest.get_node({x=np.x, y=np.y, z=np.z+1}).name
				leaf_found = table.icontains(leaves, leaf) or table.icontains(fruits, leaf)
			end

			if leaf_found then
				for _,i in ipairs(tab) do
					destroy_node(i[1], i[2], digger)
				end
				local range = tr.range
				local inv = digger:get_inventory()
				local head_ps = find_next_trees(np, range, trees, leaves, fruits)	--definition of the leavespositions
				--minetest.chat_send_all("test1")	<— this too
				for _,i in ipairs(head_ps) do
					local p = vector.add(np, i)
					local node = minetest.get_node(p)
					local nodename = node.name
					if table.icontains(leaves, nodename) then
						remove_leaf(p, leaf, inv, node, digger)
					elseif table.icontains(fruits, nodename) then
						destroy_node(p, node, digger)
					end
				end
			end
		end
	end
	capitating = false
	print(string.format("[treecapitator] tree capitated at ("..pos.x.."|"..pos.y.."|"..pos.z..") after ca. %.2fs", os.clock() - t1))
end)

print(string.format("[treecapitator] loaded after ca. %.2fs", os.clock() - load_time_start))
