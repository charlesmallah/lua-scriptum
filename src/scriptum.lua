--[[
@title lua-scriptum
@description Document generator for Lua based code;
The output files are in markdown syntax

@authors Charles Mallah
@copyright (c) 2020 Charles Mallah
@license MIT license (mit-license.org)

@sample Sample output is in markdown
`This document was created with this module

@example Generate all documentation from the root directory
`local scriptum = require("scriptum")
`scriptum.start()
]]

--[[ Configuration ]]--

local outputDir = "scriptum"

--[[ Locals ]]--

local love = love -- luacheck: ignore
local module = {}

local anyText = "(.*)"
local spaceChar = "%s"
local anyQuote = "\""
local openBracket = "%("
local closeBracket = "%)"
local openBracket2 = "%<"
local closeBracket2 = "%>"
local openBracket3 = "%["
local closeBracket3 = "%]"
local openBlockComment = "%-%-%[%["
local closeBlockComment = "%]%]"
local patternInsideBlockComment = openBlockComment..anyText..closeBlockComment
local startBlockComment = openBlockComment..anyText
local endBlockComment = anyText..closeBlockComment
local patternRequire = "require"..openBracket..anyQuote..anyText..anyQuote..closeBracket
local patternParam = "@param"..spaceChar..anyText
local patternReturn = "@return"..spaceChar..anyText
local patternTextToSpace = anyText..spaceChar..openBracket..anyText..closeBracket
local patternTextInBrackets = openBracket..anyText..closeBracket
local patternTextInAngled = openBracket2..anyText..closeBracket2
local patternTextInSquare = openBracket3..anyText..closeBracket3
local patternFunction = "function"..anyText..openBracket
local patternTitle = "@title"..anyText
local patternDesc = "@description"..anyText
local patternExample = "@example"..anyText
local patternSample = "@sample"..anyText
local patternAuthors = "@authors"..anyText
local patternCopyright = "@copyright"..anyText
local patternLicense = "@license"..anyText
local subpatternCode = "`"..anyText
local patternAt = "@"..anyText
local patternLeadingSpace = spaceChar.."*"..anyText

local toRoot = "Back to root"

local tags = {"title", "description", "authors", "copyright", "license", "sample", "example"}

local function recursivelyDelete(item)
  if love.filesystem.getInfo(item, "directory") then
    for _, child in pairs(love.filesystem.getDirectoryItems(item)) do
      recursivelyDelete(item .. '/' .. child)
      love.filesystem.remove(item .. '/' .. child)
    end
  end
  love.filesystem.remove(item)
end

local function recursiveFileSearch(folder, fileTree)
  if not fileTree then
    fileTree = {}
  end
  if not folder then
    folder = ""
  end
  local filesTable = love.filesystem.getDirectoryItems(folder)
  for _, v in ipairs(filesTable) do
    local file = folder.."/"..v
    local info = love.filesystem.getInfo(file)
    if info then
      if info.type == "file" then
        fileTree[#fileTree + 1] = file
      else
        if info.type == "directory" then
          fileTree = recursiveFileSearch(file, fileTree)
        end
      end
    end
  end
  return fileTree
end

local function sortStrings(tableOfStrings)
  table.sort(tableOfStrings, function(a, b) return a:upper() < b:upper() end)
end

local function filterFiles(fileTree, fileType)
  local set = {}
  local count = 0
  local typeSize = #fileType
  for i = 1, #fileTree do
    local name = fileTree[i]
    local typePart = string.sub(name, #name - typeSize + 1, #name)
    if typePart == fileType then
      name = string.sub(name, 1, #name - typeSize)
      count = count + 1
      set[count] = name
    end
  end
  return set
end

local function searchForPattern(lines, startLine, forLines, pattern)
  local count = #lines
  for j = 1, forLines do
    local k = startLine + j
    if k <= count then
      local line3 = string.match(lines[k], pattern)
      if line3 then
        return j, line3
      end
    end
  end
  return nil, nil
end

local function strReplace(stringIn, tag, replace)
  return stringIn:gsub(tag, replace)
end

local function extractRequires(lines, startLine, data)
  local search1, result1 = searchForPattern(lines, startLine, 1, patternRequire)
  if search1 then
    data.requires[#data.requires + 1] = "/"..result1..".lua"
  end
end

local function extractParam(paramset, lines, startLine, j)
  local match, line = searchForPattern(lines, startLine + j, 1, patternParam)
  if match then
    local par = {}
    local name = string.match(line, patternTextToSpace)
    if name then
      par.name = name
    end
    local typing = string.match(line, patternTextInBrackets)
    if typing then
      par.typing = typing
    end
    local default = string.match(line, patternTextInAngled)
    if default then
      par.default = default
    end
    local note = string.match(line, patternTextInSquare)
    if note then
      par.note = note
    end
    paramset.pars[#paramset.pars + 1] = par
  end
end

local function extractReturn(paramset, lines, startLine, j)
  local match, line = searchForPattern(lines, startLine + j, 1, patternReturn)
  if match then
    local par = {}
    local name = string.match(line, patternTextToSpace)
    if name then
      par.name = name
    end
    local typing = string.match(line, patternTextInBrackets)
    if typing then
      par.typing = typing
    end
    local default = string.match(line, patternTextInAngled)
    if default then
      par.default = default
    end
    local note = string.match(line, patternTextInSquare)
    if note then
      par.note = note
    end
    paramset.returns[#paramset.returns + 1] = par
  end
end

local function extractFunctionBlock(lines, startLine, data)
  local search2 = searchForPattern(lines, startLine, 1, patternInsideBlockComment)
  if search2 then
    data.api[#data.api + 1] = {line = startLine}
  else
    local search2b, result2b = searchForPattern(lines, startLine, 1, startBlockComment)
    if search2b then
      local search3 = searchForPattern(lines, startLine, 10, endBlockComment)
      -- Functions --
      local paramset = {pars = {}, returns = {}, line = startLine, desc = result2b}
      local fnL, fnLine = searchForPattern(lines, startLine + search3, 1, patternFunction)
      if fnL then
        paramset.name = fnLine
      end
      -- Function details --
      if search3 then
        for j = 1, search3 do
          extractParam(paramset, lines, startLine, j)
          extractReturn(paramset, lines, startLine, j)
        end
      end
      data.api[#data.api + 1] = paramset
    end
  end
end

local function firstToUpper(text)
  return (text:gsub("^%l", string.upper))
end

local function removeLeadingSpaces(text)
  return string.match(text, patternLeadingSpace)
end

local function multiLineField(set, field, data)
  if not set[field] then
    set[field] = {}
  else
    set[field][#set[field] + 1] = "||"
  end
  local text = removeLeadingSpaces(data)
  if text ~= "" then
    set[field][#set[field] + 1] = text
  end
end

local function catchMultilineEnd(set, multilines, multilineStarted)
  for i = 1, #multilines do
    set[multilineStarted][#set[multilineStarted] + 1] = multilines[i]
  end
end

local function searchForMultilineTaggedData(set, line, multilines, multilineStarted)
  local description = string.match(line, patternDesc)
  if description then
    if multilineStarted then
      catchMultilineEnd(set, multilines, multilineStarted)
    end
    multiLineField(set, "description", description)
    return "description"
  end
  local sample = string.match(line, patternSample)
  if sample then
    if multilineStarted then
      catchMultilineEnd(set, multilines, multilineStarted)
    end
    multiLineField(set, "sample", sample)
    return "sample"
  end
  local example = string.match(line, patternExample)
  if example then
    if multilineStarted then
      catchMultilineEnd(set, multilines, multilineStarted)
    end
    multiLineField(set, "example", example)
    return "example"
  end
  return nil
end

local function searchForTaggedData(line2, set)
  local title = string.match(line2, patternTitle)
  if title then
    set.title = removeLeadingSpaces(title)
    return "title"
  end
  local authors = string.match(line2, patternAuthors)
  if authors then
    set.authors = removeLeadingSpaces(authors)
    return "authors"
  end
  local copyright = string.match(line2, patternCopyright)
  if copyright then
    set.copyright = removeLeadingSpaces(copyright)
    return "copyright"
  end
  local license = string.match(line2, patternLicense)
  if license then
    set.license = removeLeadingSpaces(license)
    return "license"
  end
  return nil
end

local function extractHeaderBlock(lines, startLine, data)
  local search = searchForPattern(lines, startLine, 1, startBlockComment)
  if search then
    local search3 = searchForPattern(lines, startLine, 50, endBlockComment)
    local set = {}
    if search3 then
      set.endHeader = search3
      local multilineStarted = nil
      local multilines = {}
      for j = 1, search3 - 2 do
        local paramLineN = searchForPattern(lines, startLine + j, 1, patternAt)
        if paramLineN then -- Line is prefixed with '@' --
          local line = lines[startLine + j + paramLineN]
          local matched = searchForMultilineTaggedData(set, line, multilines, multilineStarted)
          if matched then
            multilineStarted = matched
            multilines = {}
          else
            local otherTagMatch = searchForTaggedData(line, set)
            if otherTagMatch and multilineStarted then
              catchMultilineEnd(set, multilines, multilineStarted)
              multilineStarted = nil
              multilines = {}
            end
          end
        else -- Line is not prefixed with '@' --
          local line = lines[startLine + j + 1]
          if multilineStarted then
            local text = removeLeadingSpaces(line)
            if text ~= "" then
              multilines[#multilines + 1] = text
            end
          end
        end
      end
      if multilineStarted then -- On end block, but check if a multiline catch wasn't done --
        catchMultilineEnd(set, multilines, multilineStarted)
      end
    end
    data.header = set
  end
end

--[[Will force a repeated header on a line that is '||', as code for a manual new line]]
local function writeVignette(output, set, fields)
  for i = 1, #fields do
    local field = fields[i]
    if set[field] then
      output:write("\n**"..firstToUpper(field).."**:")
      if type(set[field]) == "table" then
        local count = 0
        for j = 1, #set[field] do
          local text = set[field][j]
          count = count + 1
          if text == "||" then
            output:write("\n")
            output:write("\n**"..firstToUpper(field).."**:")
            count = 0
          else
            local code = string.match(text, subpatternCode)
            if code then
              if count == 2 then
                output:write("\n")
              end
              output:write("\n    "..code)
            else
              output:write("\n"..text)
            end
          end
        end
      else
        output:write("\n"..set[field])
      end
      output:write("\n")
    end
  end
end

local function generateItemName(file)
  return strReplace(file, "", "")
end

local function generateItemLink(file)
  local out = file..".md"
  out = strReplace(out, "/", ".")
  return out
end

local function generateReadme()
  local outFilename = outputDir.."/readme.md"
  local output = love.filesystem.newFile(outFilename)
  local opened = output:open("w")
  if not opened then
    print("error: failed to create '"..outFilename.."'")
    return
  end

  output:write("# Project Code Documentation")
  output:write("\n")
  output:write("\nTest output text.")
  output:write("\n")

  output:write("\n## Index")
  output:write("\n")
  for i = 1, #module.sortSet do
    local data = module.fileData[module.sortSet[i]]
    local name = generateItemName(data.file)
    local link = generateItemLink(data.file)
    output:write("\n+ ["..name.."]("..link..")")
  end
end

local function printFn(output, v3)
  output:write(" (")
  local cat = ""
  local count = 0
  for _, v4 in pairs(v3.pars) do
    if v4.name then
      count = count + 1
      if count > 1 then
        cat = cat..", "..v4.name
      else
        cat = cat..v4.name
      end
      if v4.default ~= "required" and v4.default ~= "r" then
        cat = cat.."\\*"
      end
    end
  end
  output:write(cat)
  output:write(")")
  if v3.returns then
    output:write(" : ")
    cat = ""
    count = 0
    for _, v4 in pairs(v3.returns) do
      if v4.name then
        count = count + 1
        if count > 1 then
          cat = cat..", "..v4.name
        else
          cat = cat..v4.name
        end
        -- if v4.default ~= "required" then
        --   cat = cat.."\\*"
        -- end
      end
    end
    output:write(cat)
  end
  output:write("  \n")
end

local function printParams(output, v3)
  for _, v4 in pairs(v3.pars) do
    local text2 = "> &rarr; "
    if v4.name then
      text2 = text2.."**"..v4.name.."**"
    end
    if v4.typing then
      text2 = text2.." ("..v4.typing..")"
    end
    if v4.default then
      text2 = text2.." <*"..v4.default.."*>"
    end
    if v4.note then
      text2 = text2.." `"..v4.note.."`"
    end
    output:write(text2)
    output:write("  \n")
  end
end

local function printReturns(output, v3)
  for _, v4 in pairs(v3.returns) do
    local text2 = "> &larr; "
    if v4.name then
      text2 = text2.."**"..v4.name.."**"
    end
    if v4.typing then
      text2 = text2.." ("..v4.typing..")"
    end
    if v4.default then
      text2 = text2.." <*"..v4.default.."*>"
    end
    if v4.note then
      text2 = text2.." `"..v4.note.."`"
    end
    output:write(text2)
    output:write("  \n")
  end
end

local function generateDoc(data)
  local out = data.file..".md"
  out = strReplace(out, "/", ".")
  out = outputDir.."/"..out
  local output = love.filesystem.newFile(out)
  local opened = output:open("w")
  if not opened then
    print("error: failed to create '"..out.."'")
    return
  end

  output:write("# "..data.file)
  output:write("\n")

  if data.header then
    output:write("\n## Vignette\n")
    writeVignette(output, data.header, tags)
    output:write("\n")
  end

  -- Requires --
  local hasREQ = false
  for _, v2 in pairs(data.requires) do
    if not hasREQ then
      output:write("\n## Requires")
      output:write("\n")
      hasREQ = true
    end
    local name = generateItemName(v2)
    local link = generateItemLink(v2)
    output:write("\n+ ["..name.."]("..link..")")
  end
  if hasREQ then
    output:write("\n")
  end

  -- API --
  local hasAPI = false
  local count = 0
  for _, v3 in pairs(data.api) do
    if v3.name then
      if not hasAPI then
        output:write("## API")
        output:write("\n")
        hasAPI = true
      end
      count = count + 1
      local nameText = strReplace(v3.name, "module.", "")
      output:write("\n**"..removeLeadingSpaces(nameText).."**")
      if v3.pars then
        printFn(output, v3)
      end
      if v3.desc then
        output:write("\n")
        output:write("> "..v3.desc)
        output:write("  \n")
      end
      if v3.pars then
        printParams(output, v3)
      end
      if v3.returns then
        printReturns(output, v3)
      end
    end
  end
  output:write("\n## Project\n")
  output:write("\n+ ["..toRoot.."](readme.md)")
  output:close()
end

local function prepareOutput()
  module.fileData = {}
  module.sortSet = {}
  recursivelyDelete(outputDir)
  love.timer.sleep(1)
  love.filesystem.createDirectory(outputDir)
end

local function parseFile(file)
  module.fileData[file] = { file = file, count = 0, requires = {}, api = {} }
  local data = module.fileData[file]
  local count = 0
  local lines = {}
  for line in love.filesystem.lines(file) do
    count = count + 1
    lines[count] = line
    data.count = count
  end

  for i = 1, #lines do
    if i == 1 then
      extractHeaderBlock(lines, 0, data)
    end
    if not data.header or (not data.header.endHeader or i > data.header.endHeader) then
      extractRequires(lines, i, data)
      extractFunctionBlock(lines, i, data)
    end
  end
end

--[[ Functions ]]--

--[[Start document generation
@param rootPath (string) <required> [Path that will contain the generated documentation]
@return x1 (boolean) [Testing for output]
@return x2 (number)
]]
function module.start(rootPath)
  -- Prep --
  prepareOutput()

  -- Parse --
  local fileTree = recursiveFileSearch(rootPath)
  local files = filterFiles(fileTree, ".lua")
  sortStrings(files)
  local fileCount = #files
  for i = 1, fileCount do
    local file = files[i]..".lua"
    parseFile(file)
  end

  -- Output order --
  local count = 0
  for k, _ in pairs(module.fileData) do
    count = count + 1
    module.sortSet[count] = k
  end
  sortStrings(module.sortSet)

  -- Generate markdown--
  generateReadme()
  for i = 1, count do
    local data = module.fileData[module.sortSet[i]]
    generateDoc(data)
  end
end

--[[ End ]]--
return module
