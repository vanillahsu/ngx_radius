local Dictionary = {}
Dictionary.__index = Dictionary

-- 內部簡單的日誌函數，模擬 Perl 中的 Logger
local function _log(level, msg)
    local levels = {
        ERROR = ngx.ERR,
        WARNING = ngx.WARN,
        DEBUG = ngx.DEBUG,
        INFO = ngx.INFO
    }
    ngx.log(levels[level] or ngx.ERR, msg)
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
    self.loaded_files = {} -- 防止循環引用與重複載入
    self.current_vendor_name = nil -- 當前廠商名稱
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

function Dictionary:load_file(filename, base_dir)
    local trimmed_name = filename:match("^%s*(.-)%s*$")
    if not trimmed_name then
        _log("ERROR", "Filename is empty or only whitespace")
        return nil
    end

    -- 2. 計算完整路徑
    local full_path = trimmed_name
    if base_dir and not trimmed_name:match("^/") then
        local clean_base = base_dir:sub(1, -1) == "/" and base_dir or base_dir .. "/"
        full_path = clean_base .. trimmed_name
    end

    _log("INFO", "load_file: filename='" .. trimmed_name .. "', base_dir='" .. tostr(base_dir) .. "', full_path='" .. full_path .. "'")

    -- 3. 檢查是否已載入
    if self.loaded_files[full_path] then
        _log("INFO", "Skipping already loaded file: " .. full_path)
        return true
    end
    self.loaded_files[full_path] = true

    -- 4. 開啟檔案
    local file = io.open(full_path, "r")
    if not file then
        _log("ERROR", "Could not open dictionary file '" .. full_path .. "'")
        return nil
    end

    -- 5. 計算當前目錄，供 $INCLUDE 使用
    local new_dir = full_path:match("^(.*[/\\])") or "./"
    _log("INFO", "Calculated new_dir: '" .. new_dir .. "'")

    self:load_handle(file, "file " .. full_path, new_dir)
    file:close()
    return true
end

function Dictionary:load_handle(file, file_info, new_dir)
    _log("INFO", "Loading handle for: " .. file_info)

    -- 預編譯正則表達式 (使用 jo: JIT + compile once)
    local re_comment = "#.*$"
    local re_attr = "^ATTRIBUTE%s+(%S+)%s+(%d+)%s+(%S+)%s*(%S*)$"
    local re_vendor_attr = "^(VENDORATTR|VSA|VENDOR_ATTRIBUTE)%s+(%S+)%s+(%d+)%s+(%S+)%s*(%S*)$"
    local re_val = "^VALUE%s+(%S+)%s+(%S+)%s+(%d+)$"
    local re_vendor = "^VENDOR%s+(%S+)%s+(%S+)%s*(.*)$"
    local re_vendor_code = "^VENDOR_CODE%s+(%S+)%s+(%S+)%s*(.*)$"
    local re_include = "^%s*%$INCLUDE%s+(%S+)%s*$"
    local re_begin_vendor = "^%s*BEGIN-VENDOR%s+(%S+)%s*$"
    local re_end_vendor = "^%s*END-VENDOR%s+(%S+)%s*$"

    while true do
        local l = file:read("*l")
        if not l then break end

        -- 1. 移除註解
        l = ngx.re.gsub(l, re_comment, "", "jo")

        -- 2. 修剪前後空白 (使用 Lua 原生的 string.match)
        l = l:match("^%s*(.-)%s*$")

        if not l or l == "" then goto continue end

        -- 3. ATTRIBUTE pattern
        local captures = ngx.re.match(l, re_attr, "jo")
        if captures then
            local name, num, atype, flag1, flag2 = captures[2], captures[3], captures[4], captures[5], captures[6]
            if flag2 and flag2 ~= "" then
                _log("WARNING", "Ignoring trailing garbage '" .. flag2 .. "' in Diameter dictionary " .. file_info)
            end
            local vendor_id = 0
            if self.current_vendor_name and self.VendorName[self.current_vendor_name] then
                vendor_id = self.VendorName[self.current_vendor_name][2]
            end
            self:defineAttr(tonumber(num), vendor_id, name, atype, flag1)
            goto continue
        end

        -- 4. VENDORATTR pattern
        captures = ngx.re.match(l, re_vendor_attr, "jo")
        if captures then
            local v_key, v_name, v_attrnum, v_type, v_flag1, v_flag2 = captures[2], captures[3], captures[4], captures[5], captures[6], captures[7]
            if v_key == "VENDORATTR" or v_key == "VSA" or v_key == "VENDOR_ATTRIBUTE" then
                _log("DEBUG", "VENDORATTR match: key="..v_key..", name="..v_name..", num="..v_attrnum..", type="..v_type..", flag1="..v_flag1)
                local vendor = v_name
                if self.VendorName[v_name] then
                    vendor = self.VendorName[v_name][2]
                end

                local attr_num = tonumber(v_attrnum)
                if v_attrnum:sub(1,1) == "0" then
                    attr_num = tonumber(v_attrnum, 8)
                end

                v_flag2 = v_flag2 or ""
                if v_flag2 ~= "" then
                    _log("WARNING", "Ignoring trailing garbage '" .. v_flag2 .. "' in Diameter dictionary " .. file_info)
                end

                local v_name_internal = captures[3]
                local v_attrnum_internal = captures[4]
                local v_type_internal = captures[5]
                local v_flag1_internal = captures[6]
                local v_garbage_internal = captures[7]

                if v_garbage_internal and v_garbage_internal ~= "" then
                    _log("WARNING", "Ignoring trailing garbage '" .. v_garbage_internal .. "' in Diameter dictionary " .. file_info)
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

        -- 5. VALUE pattern
        captures = ngx.re.match(l, re_val, "jo")
        if captures then
            self:defineVal(captures[2], captures[3], tonumber(captures[4]))
            goto continue
        end

        -- 6. VENDOR pattern
        captures = ngx.re.match(l, re_vendor, "jo")
        if not captures then
            captures = ngx.re.match(l, re_vendor_code, "jo")
        end

        if captures then
            self:defineVendor(captures[2], tonumber(captures[3]), captures[4])
            goto continue
        end

        -- 7. $INCLUDE pattern
        captures = ngx.re.match(l, re_include, "jo")
        if captures then
            local include_file = captures[2]
            local full_include_path = include_file
            if not include_file:match("^/") then
                local clean_new_dir = new_dir:sub(1, -1) == "/" and new_dir or new_dir .. "/"
                full_include_path = clean_new_dir .. include_file
            end
            self:load_file(full_include_path, new_dir)
            goto continue
        end

        -- 8. BEGIN-VENDOR pattern
        captures = ngx.re.match(l, re_begin_vendor, "jo")
        if captures then
            self.current_vendor_name = captures[2]
            goto continue
        end

        -- 9. END-VENDOR pattern
        captures = ngx.re.match(l, re_end_vendor, "jo")
        if captures then
            self.current_vendor_name = nil
            goto continue
        end

        -- 如果沒匹配到任何模式
        _log("ERROR", "Bad format in dictionary " .. file_info .. " at line: '" .. l .. "'")

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