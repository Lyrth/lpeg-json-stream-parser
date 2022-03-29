---
--- Generated by Luanalysis
--- Created by Lyr.
--- DateTime: 12/03/2022 2:00 AM +0800
---

local lpeg, rec = require "lpeg", require "re".compile
local utf8 = require "utf8"

--[==[

local _token = rec([[
    v_tok   <- ws (obj_s / arr_s / str_s / null / bool / num)

    k_sep   <- ws ':'   -> _f_ex_v  -- expect value
    e_sep   <- ws ','   -> _f_ex_e  -- expect entry

    obj_s   <- '{'  -> f_obj_s      -- + expect key
    obj_e   <- '}'  -> f_obj_e
    arr_s   <- '['  -> f_arr_s      -- + expect value
    arr_e   <- ']'  -> f_arr_e

    bool    <- ('true' / 'false')   -> f_bool
    null    <- ('null')             -> f_null

    str_s   <- '"'  -> _f_ex_s      -- expect string body*
    str_e   <- '"'
    ---- str = strict and str_st or str_ln ----
    -- strict strings
    str_st  <- ([^"\] / '\' ([\/"nrtbf] / 'u' [0-9A-Fa-f]^4) )*     -- TODO exclude \x00 to \x1F
    -- non-strict strings
    str_ln  <- ([^"\] / '\' .)*

    ---- num = strict and num_st or num_ln ----
    -- strict numbers
    num_st  <- '-'? ('0' / [1-9] %d*) ('.' %d+)? ([eE] [-+]? %d+)?
    -- non-strict numbers
    num_ln  <- '-'? %d [0-9.Ee+-]+

    num     <- %num     -> f_num
    ws      <- %ws
]], {
    _f_ex_v = function() print("_f_ex_v") end,
    _f_ex_e = function() print("_f_ex_e") end,
    _f_ex_s = function() print("_f_ex_s") end,
    f_obj_s = function() print("f_obj_s") end,
    f_obj_e = function() print("f_obj_e") end,
    f_arr_s = function() print("f_arr_s") end,
    f_arr_e = function() print("f_arr_e") end,
    f_bool  = function() print("f_bool") end,
    f_null  = function() print("f_null") end,
    f_num   = function() print("f_num") end,
    ws = ws,
    num = rec[[ '-'? %d [0-9.Ee+-]+ ]]
})

--]==]

-- filled later
local jExpect = {
    Value = 1,      -- value
    Member = 2,     -- { String , k_sep , Value }
    String = 3,     -- str_st / str_ln
    Number = 4      -- num_st / num_ln
}

-- filled later
local jType = {
    Object = 1,     -- { Member... , end = obj_e }
    Array = 2,      -- { Value...  , end = arr_e }
    String = 3,     -- { String... , end = str_e }
    Null = 4,       -- { null }
    Boolean = 5,    -- { bool }
    Number = 6      -- { Number }
}


do
    local P,R,S,Cp = lpeg.P, lpeg.R, lpeg.S, lpeg.Cp
    local push = function(name)
        return function(...)
            return jType[name], ...
        end
    end

    local ws    = S' \t\r\n' ^ 0

    local k_sep = ws * P':'
    local e_sep = ws * P',' * Cp()

    local obj_s = P'{'
    local obj_e = P'}' * Cp()
    local arr_s = P'['
    local arr_e = P']' * Cp()

    local bool  = P'true' + P'false'
    local null  = P'null'

    local str_s = P'"'
    local str_e = P'"' * Cp()
    local norm  = P(1) - R('\\\\', '""', '\0\31')
    local hex   = R('09','AF','af')
    local str_st    = (norm + (P'\\' * (S'\\/"nrtbf' + (P'u' * hex * hex * hex * hex)))) ^ 0
    local str_ln    = (norm + (P'\\' * P(1))) ^ 0

    local num_s     = #((P'-')^-1 * R'09')
    local num_st    = (P'-')^-1 * (P'0' + (R'19' * R'09'^0)) * (P'.' * R'09'^1)^-1 * (S'Ee' * S'+-'^-1 * R'09'^1)^-1
    local num_ln    = (P'-')^-1 * R'09' * (R'09' + S'.Ee+-')^0

    -- converters for non-skipped values
    local bool_c    = bool / { ['true'] = true, ['false'] = false }
    local num_c     = num_st / tonumber

    local esc = {['\\'] = '\\', ['/'] = '/', ['"'] = '"', b = '\b', f = '\f', n = '\n', r = '\r', t = '\t'}
    local uni = function(h) return utf8.char(tonumber(h, 16)) end
    local str_c     = lpeg.Cs((norm + (P'\\'/'' * (S'\\/"nrtbf'/esc + (P'u'/'' * (hex * hex * hex * hex / uni))))) ^ 0 )

    -- starts but proper
    local Object    = (obj_s / push 'Object') * Cp()
    local Array     = (arr_s / push 'Array') * Cp()
    local String    = (str_s / push 'String') * Cp()
    local Null      = (null / push 'Null') * Cp()
    local Boolean   = (bool / push 'Boolean') * Cp()
    local Number    = (num_s / push 'Number') * Cp()

    local Value     = ws * ((Object + Array + String + Null + Boolean + Number))

    jExpect.Value   = { Value }
    jExpect.String  = { modes = {lenient = {str_ln}, strict = {str_st}} }
    jExpect.Number  = { modes = {lenient = {num_ln}, strict = {num_st}} }
    jExpect.Member  = { String, k_sep, Value }

    jType.Object    = { jExpect.Member, rep = true, s = e_sep, e = obj_e }
    jType.Array     = { jExpect.Value,  rep = true, s = e_sep, e = arr_e }
    jType.String    = { jExpect.String, rep = true, e = str_e }
    jType.Null      = { }
    jType.Boolean   = { }
    jType.Number    = { jExpect.Number }


end


local s = [[  {"name" :"AAAAA", "value":  ["a", "b", "cdefg"], "bool" : true }  ]]


local stack = { {counter = 1, instr = {jExpect.Value}} }
local pos = 1
local str = ""
local nextType = nil        -- nothing yet

local match

--while #match > 0 do
for i = 1,1 do
    if #stack == 0 then return end

    local state = stack[#stack]
    if state.counter > #state.instr then
        stack[#stack] = nil
        goto continue
    end

    local pat = state.instr[state.counter]

    match = { pat:match(s, pos) }
    state.counter = state.counter + 1

    p(match)

    -- TODO uh whatever

    nextType, str, pos = match[1]
    if nextType[1] then
        expect = nextType[1]
        state[#state + 1] = 1

    end


    -- check for end or sep if we completed the sequence
    if state.instr.rep and state.counter > #state.instr then
        if state.instr.e then
            local ep = state.instr.e:match(s, pos)
            if ep then
                pos = ep
                stack[#stack] = nil
            end
        elseif state.instr.s then
            local sp = state.instr.s:match(s, pos)
            if sp then
                -- more entries incoming
                pos = sp
                state.counter = 1
            end
        else
            pos = pos + 1 -- TODO add by what amount
        end
    end

    ::continue::
end
