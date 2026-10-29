local Dictionary = {}
Dictionary.__index = Dictionary

-- 內部簡單的日誌函數，模擬 Perl 中的 Logger
local function _log(level, msg)
    print(string.format("[%s] %s", level, msg))
end

function Dictionary.new()
    local self = setmetatable({}, Dictionary)
    -- 初始化數據結構
    self.AttrNum = {}    -- AttrNum{vendornum}->{attrnum}
    self.AttrName = {}   -- AttrName{attrname}
    self.ValName = {}    -- ValName{attrname}->{valuenum}
    self.ValNum = {}     -- ValNum{attrname}->{valuenum}
    self.VendorName = {} -- VendorName{vendorname}
    self.VendorNum = {}  -- VendorNum{vendornum}
    return self
end

-- 模擬 Perl 的 is_known_type (需被子類別覆寫)
function Dictionary:is_known_type(type)
    _log("ERROR", "Someone forgot to override Dictionary:is_known_type")
    return false
end

-- 模擬 Perl 的 resolve_flags (需被子類別覆寫)
function Dictionary:resolve_flags(name, vendor, flags)
    _log("ERROR", "Someone forgot to override Dictionary:resolve_flags")
    return 0
end

function Dictionary:load_file(filename)
    local file = io.open(filename, "r")
    if not file then
        _log("ERROR", "Could not open dictionary file '" .. filename .. "'")
        return nil
    end
    self:load_handle(file, "file " .. filename)
    file:close()
    return true
end

function Dictionary:load_handle(handle, handledesc)
    -- 預編譯正則表達式 (使用 jo: JIT + compile once)
    local re_comment = "#.*$"
    local re_trim = "^\\s*(.*?)\\s*$"
    local re_attr = "^ATTRIBUTE\\s+(\\S+)\\s+(\\d+)\\s+(\\S+)\\s*(\\S*)\\s*(\\S*)"
    local re_vendor_attr = "^(\\S+)\\s+(\\S+)\\s+(\\S+)\\s+(\\S+)\\s*(\\S*)\\s*(\\S*)"
    local re_val = "^VALUE\\s+(\\S+)\\s+(\\S+)\\s+(\\d+)"
    local re_vendor = "^VENDOR\\s+(\\S+)\\s+(\\S+)\\s*(.*)"
    local re_vendor_code = "^VENDOR_CODE\\s+(\\S+)\\s+(\\S+)\\s*(.*)"

    while true do
        local l = handle:read("*l")
        if not l then break end

        -- 移除註解與空白 (使用 ngx.re.gsub)
        l = ngx.re.gsub(l, re_comment, "", "jo")
        l = ngx.re.gsub(l, re_trim, "%1", "jo")

        if l == "" then goto continue end

        -- 1. ATTRIBUTE pattern: ATTRIBUTE name number type [flags]
        local captures = ngx.re.match(l, re_attr, "jo")
        if captures then
            local name, num, atype, flag1, flag2 = captures[1], captures[2], captures[3], captures[4], captures[5]
            if flag2 and flag2 ~= "" then
                _log("WARNING", "Ignoring trailing garbage '" .. flag2 .. "' in Diameter dictionary " .. handledesc)
            end
            self:defineAttr(tonumber(num), 0, name, atype, flag1)
            goto continue
        end

        -- 2. VENDORATTR pattern: VENDORATTR|VSA|VENDOR_ATTRIBUTE vendornum name number type [flags]
        captures = ngx.re.match(l, re_vendor_attr, "jo")
        if captures then
            local v_key, v_name, v_attrnum, v_type, v_flag1, v_flag2 = captures[1], captures[2], captures[3], captures[4], captures[5], captures[6]
            if v_key == "VENDORATTR" or v_key == "VSA" or v_key == "VENDOR_ATTRIBUTE" then
                print("DEBUG: VENDORATTR match: key="..v_key..", name="..v_name..", num="..v_attrnum..", type="..v_type..", flag1="..v_flag1)
                local vendor = v_name
                -- 如果 vendor 是名稱，嘗試從 VendorName 查表轉為數字
                if self.VendorName[v_name] then
                    vendor = self.VendorName[v_name][2]
                end

                -- 處理八進制 (Perl 的 oct 功能)
                local attr_num = tonumber(v_attrnum)
                if v_attrnum:sub(1,1) == "0" then
                    attr_num = tonumber(v_attrnum, 8)
                end

                v_flag2 = v_flag2 or ""
                local v_garbage = v_flag2 -- 在這裡，v_flag2 是我們捕捉到的最後一個非空白字串

                if v_garbage and v_garbage ~= "" then
                    _log("WARNING", "Ignoring trailing garbage '" .. v_garbage .. "' in Diameter dictionary " .. handledesc)
                end

                -- 使用內部變數進行定義
                local v_name_internal = captures[2]
                local v_attrnum_internal = captures[3]
                local v_type_internal = captures[4]
                local v_flag1_internal = captures[5]
                local v_garbage_internal = captures[6]

                if v_garbage_internal and v_garbage_internal ~= "" then
                    _log("WARNING", "Ignoring trailing garbage '" .. v_garbage_internal .. "' in Diameter dictionary " .. handledesc)
                end

                local vendor_final = v_name_internal
                if self.VendorName[v_name_internal] then
                    vendor_final = self.VendorName[v_name_internal][2]
                end

                local attr_num_final = tonumber(v_attrnum_internal)
                if v_attrnum_internal:sub(1,1) == "0" then
                    attr_num_final = tonumber(v_attrnum_internal, 8)
                end

                self:defineAttr(tonumber(attr_num_final), tonumber(vendor_final), v_type_internal, v_flag1_internal)
                goto continue
            end
        end

        -- 3. VALUE pattern: VALUE attrname valname valnum
        captures = ngx.re.match(l, re_val, "jo")
        if captures then
            self:defineVal(captures[1], captures[2], tonumber(captures[3]))
            goto continue
        end

        -- 4. VENDOR pattern: VENDOR name number [extra]
        captures = ngx.re.match(l, re_vendor, "jo")
        if not captures then
            captures = ngx.re.match(l, re_vendor_code, "jo")
        end

        if captures then
            self:defineVendor(captures[1], tonumber(captures[2]), captures[3])
            goto continue
        end

        -- 如果沒匹配到任何模式
        _log("ERROR", "Bad format in dictionary " .. handledesc .. " at line: " .. l)

        ::continue::
    end
    return true
end

function Dictionary:defineAttr(number, vendor, name, type, flags)
    if not self:is_known_type(type) then
        _log("WARNING", "Bad type " .. type .. " for attribute " .. name .. " in dictionary. Encoding and decoding this attribute may fail.")
    end

    local resolvedflags = self:resolve_flags(name, vendor, flags)
    vendor = vendor or 0
    local a = {name, type, number, vendor, resolvedflags}

    self.AttrNum[vendor] = self.AttrNum[vendor] or {}
    self.AttrNum[vendor][number] = a
    self.AttrName[name] = a

    return a
end

function Dictionary:defineVal(attrname, valname, value)
    local v = {valname, value, attrname}
    self.ValName[attrname] = self.ValName[attrname] or {}
    self.ValName[attrname][valname] = v
    self.ValNum[attrname] = self.ValNum[attrname] or {}
    self.ValNum[attrname][value] = v
    return v
end

function Dictionary:defineVendor(name, number, ...)
    local extras = {...}
    local a = {name, number}
    for i, v in ipairs(extras) do table.insert(a, v) end

    self.VendorNum[number] = a
    self.VendorName[name] = a
    return a
end

function Dictionary:attrByName(name)
    return self.AttrName[name]
end

function Dictionary:attrByNum(number, vendor)
    vendor = tonumber(vendor) or 0
    if self.AttrNum[vendor] and self.AttrNum[vendor][number] then
        return self.AttrNum[vendor][number]
    end
    return {string.format("Attr-%s-%s", vendor, number), 'OctetString', number, vendor}
end

function Dictionary:valByNum(attrname, valnum)
    if self.ValNum[attrname] and self.ValNum[attrname][valnum] then
        return self.ValNum[attrname][valnum]
    end
    return nil
end

function Dictionary:valByName(attrname, valname)
    -- 處理 0x 開頭的十六進制轉換
    local hex_match = valname:match("^0x([0-9a-fA-F]+)$")
    if hex_match then
        valname = tonumber(hex_match, 16)
    end

    if self.ValName[attrname] and self.ValName[attrname][valname] then
        return self.ValName[attrname][valname]
    end
    return nil
end

function Dictionary:valuesForAttribute(attrname)
    local res = {}
    if self.ValName[attrname] then
        for k in pairs(self.ValName[attrname]) do
            table.insert(res, k)
        end
    end
    table.sort(res)
    return res
end

function Dictionary:vendorNums()
    local res = {}
    for k in pairs(self.VendorNum) do
        table.insert(res, k)
    end
    table.sort(res)
    return res
end

function Dictionary:vendorByNum(vendornum)
    if self.VendorNum[vendornum] then
        return self.VendorNum[vendornum]
    end
    return nil
end

function Dictionary:vendorByName(vendorname)
    if self.VendorName[vendorname] then
        return self.VendorName[vendorname]
    end
    return nil
end

return Dictionary
