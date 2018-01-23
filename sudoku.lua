#! /usr/bin/env lua
-- sudoku.lua   © Dirk Laurie 2018   MIT License like Lua's.
-- Support for solving Sudoku puzzles, including Killer.

-- Quick start (with the module 'sudoku' loaded) 
--   print(sudoku():read'FILENAME':solve().solution)
-- Educational start (in an interactive session)
--   Sudoku, Dance, demo = dofile "sudoku.lua" 
--   demo()
--   Sudoku.help  
--   Dance.help  

-- Sample puzzle formats (contents of ipout file)

-- Standard sudoku has digits and dots, whitespace is optional
local arto_sudoku = [[
8.. ... ... 
..3 6.. ... 
.7. .9. 2.. 
.5. ..7 ... 
... .45 7.. 
... 1.. .3. 
..1 ... .68 
..8 5.. .1. 
.9. ... 4.. 
]]

-- Killer sudoku has exactly 81 whitespace-delimited items, each either:
-- * a number with the cage total in the main cell of the cage, i.e. top 
--   left, with top more important than left.
-- * an "arrow" denoted by <, ^, >, meaning that the cell belongs to the 
--   same cage as the cell to which it points.
local graph_killer = [[
19  6  < 23  <  <  <  < 12
 ^ 31  <  <  <  <  ^ 22  ^
 ^ 11 10 20  <  <  >  ^  9
 ^  ^  ^  ^ 23  <  <  >  ^
30  <  ^  <  ^ 13  < 10  <
 ^  ^ 10  < 21  5  < 19  <
 7  < 20  ^  ^  < 17  ^  ^
 >  >  ^ 14  <  >  ^ 25  <
20  <  <  <  8  <  <  ^  ^
]]

-- dclass.lua   © Dirk Laurie 2018   MIT License like Lua's.
--[=[    Very simple support for classes. 
  MyClass = class("my class",_methods)   
--   Name of class must be given. If `_methods` is not nil, it must be 
--     a table, whose contents will be copied into 'MyClass'.
  MyClass.method = function(object,...) --[[function body]] end
   obj = MyClass(...)
--   If `MyClass.init` is `false`, `...` is ignored.
--   If `MyClass.init` is a function, `obj:init(...)` is called by MyClass. 
--   Otherwise, the first argument in `...` must be nil or a table, 
--     whose contents will be copied into `obj`. 
--]=]
local class -- semi-global forward declaration
    do  
local new  -- forward declaration
class = function(name,_methods)   -- class creator
  if type(name)~='string' then error(
    "Bad argument #1 to 'class' (expected string, got "..type(name)..")")
  end
  if type(_methods)~='table' and type(_methods)~='nil' then error(
    "Bad argument #2 to 'class' (expected table, got "..type(_methods)..")")
  end
  local methods = {init="No initializer for class '"..name..
    "' has been defined yet."}
  if _methods then
    for k,v in pairs(_methods) do methods[k]=v end
  end
  methods.__name = name
  methods.__index = methods
  methods.__gc = true    -- to be overridden
  local meta = {
    __call=new,
    __name="constructor-metatable for class '"..name.."'"}
  local Class = setmetatable(methods,meta)
  return Class
end
new = function(Class,...)               -- generic constructor
  object = setmetatable({},Class)
  if type(Class.init)=='function' then  -- custom constructor 
    object:init(...) 
  elseif ... ~= nil and Class.init~=false then
    if type(...)=='table' then          -- default constructor
      for k,v in pairs((...)) do object[k]=v end
    else error("Bad initializer to class '"..
      Class.__name.."' (expected table, got "..type(...)..")")
    end
  end
  return object
end
    end 
-- return class   -- comment out this line if dclass.lua is copied into code
-- end of file dclass.lua

-- class Dance
-- purpose: interface to Knuth's 'Dancing Links' program
--   We use a patched version allowing 7-character labels rather than
--   the 3-character labels in the original.
local Dance = class"Dancing Links"

-- class Sudoku
-- purpose: create input suitable for Dance from the grid information of
--   standard and Killer Sudoku puzzles
local Sudoku = class"Sudoku"

-- Cell labels are upper-lower, e.g. 'Df'.
-- Box labels prefix the top-left cell label with an 'x', e.g. 'xDg'.
-- Cage labels prefix the top-left cell label with an 'y', e.g. 'yAb'.
-- Digits if present always come last, e.f. 'D2', 'g3', 'xDg4', 'yCf3'.
-- Row labels are not in 'universe', but are additional keys in 'subsets',
-- e.g. 'Ab7', 'yCe134578'.

local graphtomap, combinations  -- upvalues declared forward 
 
function Dance:__call(...)
--  local command = ("dance %s < "):format(table.concat({...},' '))
  local filename = os.tmpname()
  self.filename = filename
  local file = io.open(filename,"w")
  file:write(table.concat(self.universe,' '),"\n")
  for _,v in ipairs(self.subsets) do file:write(table.concat(v,' '),"\n") end
  file:close()
  self.result = io.popen(("dance < ")..filename):read"a"
  if self.result:match" 1 solution" then  -- redo to get the details
    local all = io.popen("dance 1 < "..filename):read"a"
    local sl = {}  -- make sorted list of subsets
    for k,v in ipairs(self.subsets) do
      table.sort(v)
      sl[table.concat(v,' ')]=k
    end
    local sol = {}
    for line in all:gmatch"[^\n]+" do  -- find number of actual subset
      if line:match"solution" then break end
      line = line:match"([^(]+)%(%d+ of %d+%)"
      if line then -- only recognizable subsets
        local v = {}
        line:gsub("%S+",function(label) v[#v+1]=label end)
        table.sort(v)
        sol[#sol+1] = sl[table.concat(v,' ')]
      end
    end
    self.result, self.solution = all, sol
  end
  return self
end

local rows, cols = "ABCDEFGHI", "abcdefghi"
local digits = "123456789" 

function Sudoku:read(filename)
  local infile = io.open(filename)
  if not infile then error("Could not read from "..filename) end
  local input = infile:read"a"
  infile:close()
  local extension = filename:match"%.([^.]+)$"
  return self:init(input,extension)
end 

function Sudoku:init(input,ext)
  local puzzle
  if not input then return self end
  if type(input) ~= 'string' then error("Bad initializer to class 'Sudoku'"..
     "' (expected string, got "..type(input)..")")
  end
-- decide whether input is standard or killer
  local grid = {}
  local function collect(item) grid[#grid+1] = item end
  if select(2,input:gsub('%S',collect)) == 81 then 
    puzzle = 'sudoku'
  else
    grid = {}
    if select(2,input:gsub('%S+',collect)) == 81 then 
      puzzle = 'killer'
    end
    if input:match"%A" then  -- replace < ^ > by cell labels
      graphtomap(grid) 
    end 
  end
  if not puzzle then error("Bad input to class 'Sudoku'"..
     "' (expected 81 items, got "..#grid..")")
  end
  if ext and ext~=puzzle then io.stderr:write(
    "Puzzle seems to be a "..puzzle.." but file extension is "..ext.."\n")
  end
  self.input, self.puzzle, self.grid = input, puzzle, grid
  return self
end

-- incorporate grid data for a standard Sudoku
function Sudoku:sudoku(dance)
  local universe = dance.universe
  local subsets = dance.subsets
  local k = 0
  for r in rows:gmatch"." do for c in cols:gmatch"." do
    k = k+1
    local data = self.grid[k]
    local here = r..c
    for d in digits:gmatch"." do
      local label = here..d
      local subset = subsets[label]
      if d==data:match"%d" then
        universe[#universe+1] = label
        subset[#subset+1]=label
      end
    end
  end end
end

-- incorporate grid data for a Killer Sudoku
function Sudoku:killer(dance)
  local universe = dance.universe
  local subsets = dance.subsets
  local cages, leader, totals = {}, {}, {}
  local cagelabel = function(cell)
    return 'y' .. leader[cell]
  end
  local tocage = function(data,here)
    local total = tonumber(data)
    if total then  -- start a new cage
      leader[here] = here
      cages[here] = {here}
      totals[here] = total
    else  -- add this cell to an existing cage
      assert(data<here,data.." must come before "..here)
      local cage = cages[data]
      assert(cage,data.." is not a leading cell")
      leader[here] = data
      cage[#cage+1] = here
    end
  end
  local k = 0
  for r in rows:gmatch"." do for c in cols:gmatch"." do
    k = k+1
    local data = self.grid[k]
    local here = r..c
    tocage(data,here)
    for d in digits:gmatch"." do
      local subset = subsets[here..d]
      local label = cagelabel(here)..d
      subset[#subset+1]=label
      if tonumber(data) then  -- add label only when this is a main cell
        universe[#universe+1] = label
      end
    end
  end end
  for k,v in pairs(cages) do -- add complementary subsets for cage totals
    local total = totals[k]
    local size = #v
    local label = cagelabel(v[1])
    for _,c in ipairs(combinations(size,total),label) do
      local comb = {}
      for _,j in ipairs(c) do comb[j]=j end
      local subset = {}
      for d=1,9 do if not comb[d] then 
        subset[#subset+1]=label..d 
      end end
      subsets[#subsets+1] = subset
      subsets[label..table.concat(c)] = subset
    end
  end
end

-- print-ready list of selected combinations
function Sudoku:combinations()
  if self.puzzle ~= "killer" then return end
  local list = {}
  for _,row in ipairs(self.dance.solution) do
    if row>729 then
      local s = self.dance.subsets[row]
      local t = {1,2,3,4,5,6,7,8,9}
      for _,v in ipairs(s) do t[tonumber(v:match"%d")]=nil end
      local u = {}
      for k=1,9 do u[#u+1]=t[k] end
      list[#list+1] = s[1]:match"%u%l"..' '..table.concat(u)
    end
  end 
  return table.concat(list,"\n")
end

-- boxlabel: an optional function that returns a box label given a cell label
--    nil or omitted  -- does standard 3x3 boxes
--    false -- omits box labels
    do -- closure
local edges = {A='A',B='A',C='A',D='D',E='D',F='D',G='G',H='G',I='G',
                 a='a',b='a',c='a',d='d',e='d',f='d',g='g',h='g',i='g'}
function Sudoku:solve(boxlabel)
  local dance = Dance()
  self.dance = dance
  local universe, subsets = {}, {}
  dance.universe, dance.subsets =  universe, subsets
  if boxlabel==nil then  -- default box labels
    boxlabel = function(cell) return 'x' .. cell:gsub(".",edges) end
  end
  local function populate(first,second)  -- two-character labels
    for f in first:gmatch"." do for s in second:gmatch"." do
      universe[#universe+1] = f..s
    end end
  end
  populate(rows,cols)
  populate(rows,digits)
  populate(cols,digits)
  if boxlabel then 
    for r in rows:gmatch"(.).." do for c in cols:gmatch"(.).." do
      local corner = boxlabel(r..c)
      for d in digits:gmatch"." do
        universe[#universe+1] = corner..d
      end 
    end end 
  end
  for r in rows:gmatch"." do for c in cols:gmatch"." do
    local here = r..c
    for d in digits:gmatch"." do
      local subset = {here, r..d, c..d}
      if boxlabel then
        subset[#subset+1]=boxlabel(here)..d
      end
      subsets[#subsets+1] = subset
      subsets[here..d] = subset
    end
  end end
  self[self.puzzle](self,dance)  -- apply data
  dance()
  if dance.solution then 
    local s = table.pack(table.unpack(dance.solution))
    local t = {}
    table.sort(s)
    for k=1,81 do s[k] = 1 + (s[k]-1)%9 end
    for k=1,81,9 do t[#t+1] = table.concat(s,' ',k,k+8) end
    self.solution = table.concat(t,"\n")
  end
  self.combos = self:combinations()
  return self
end
    end -- closure

    do local memo = {}
combinations = function(size,total,limit)
  if total==0 then return memo end
  limit = limit or 9
  if not next(memo) then 
    for n=1,(1<<limit)-1 do
      local s={}
      local t=0
      local k=0
      for j=1,limit do if (n & (1<<(j-1))) > 0 then
        k=k+1
        t=t+j
        s[#s+1]=j
      end end
      local mk = memo[k] or {}
      memo[k] = mk
      local mkt = mk[t] or {}
      mk[t] = mkt
      mkt[#mkt+1] = s
    end
  end
  return memo[size] and memo[size][total]
end
    end

-- Replace < ^ > by the label of the main cell of the cage
    do
local format = function(x,f)
  if x then return f:format(x) end
end
graphtomap = function(grid)
  local map, cage, todo = {}, {}, {}
  local k=0
  for r in rows:gmatch"." do
    for c in cols:gmatch"." do
      k = k+1 
      local cell = grid[k]
      local data = tonumber(cell)
      if cell=="^" then 
        data = map[#map-8]
      elseif cell=="<" then
        data = map[#map]
      elseif cell==">" then 
        data = cell
        todo[r..c] = #map+1
      else
        cage[r..c] = data
        data = r..c
      end 
      map[#map+1] = data      
    end
  end
  while next(todo) do
    for k,v in pairs(todo) do
      map[v] = map[v+1]
      if map[v]~='>' then todo[k] = nil end      
    end
  end
  local n=0
  for r in rows:gmatch"." do
    for c in cols:gmatch"." do 
      n=n+1; grid[n] = format(cage[r..c],"%02i") or map[n]
    end
  end
end
    end

-- Some sample puzzles

local easy_sudoku = [[
.83..2.75
....4..36
......219
..8.9...7
1..4..3..
4...2..98
3.9.6.5.1
.....5...
56.2.1...
]]

local medium_sudoku = [[
79.1.....
.84.25...
.......48
......15.
..7......
412......
..8.7..3.
.4.6..7..
6...532..
]]

-- local 
demo = function()
  local s = Sudoku(arto_sudoku)
  local k = Sudoku(graph_killer)
  print(s:solve().solution); print()
  print(k:solve().solution); print() 
  print(k.combos)
  return s,k
end

Dance.help = [[
Class 'Dance' is a callable table which constructs an object that eventually
has the following fields:
  universe  A list of possible labels.
  subsets   A list of selectable subsets, each consisting of a list of labels.
  filename  A temporary file containing the input for Knuth's program 'dance'.
  result    The output from Knuth's program.
  solution  A list of the numbers of selected subsets whose union contains each
            label exactly one (only present when there is only one solution).
The fields 'universe' and 'subsets' are set by the application. There is
only one metamethod '__call' which takes no parameters and sets the other three
fields.
]]

Sudoku.help = [[
Class 'Sudoku' is a callable table which constructs an object that eventually
has the following fields:
  puzzle    Either 'sudoku' or 'killer'.
  input     A string defining the puzzle (see top of file 'sudoku.lua' for
            specification and examples).
  grid      An 81-element array describing the puzzle. 
  solution  A 9-line string containing the solution.
  combos    A multiline string describing the selected combinations per cage
            (killer only)
  dance     An object of class 'Dance'.
The following methods are defined:
  init(input)     Set 'input' and initialize 'grid' and 'puzzle' (the formats
                  are sufficiently distinct that 'init' can tell).
  read(FILENAME)  Read 'input' from a file and call 'init'.
  solve()   Construct 'dance', modify it by either 'sudoku' or 'killer',
    call it, compose 'solution'
  sudoku()  Modify 'dance' Sudoku-style from given cell values
  killer()  Modify 'dance' Killer-style from given cage shapes and totals 
  combinations()  Constructs 'combos'.
  
]]

return Sudoku, Dance, demo 
