--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

local kong = kong
local ffi = require "ffi"
local cjson = require "cjson"
local table_concat = table.concat
local table_insert = table.insert
local system_constants = require "lua_system_constants"

-- gzip start
local zlib = require('ffi-zlib')
local ZLIB_BUFSIZE = 16384
-- gzip end

-- skywalking 8 start
local SegmentRef = require("kong.plugins.skywalking.segment_ref")
local CONTEXT_CARRIER_KEY = 'sw8'
-- skywalking 8 end

local O_CREAT = system_constants.O_CREAT()
local O_WRONLY = system_constants.O_WRONLY()
local O_APPEND = system_constants.O_APPEND()
local S_IRUSR = system_constants.S_IRUSR()
local S_IWUSR = system_constants.S_IWUSR()
local S_IRGRP = system_constants.S_IRGRP()
local S_IROTH = system_constants.S_IROTH()

local oflags = bit.bor(O_WRONLY, O_CREAT, O_APPEND)

local mode = bit.bor(S_IRUSR, S_IWUSR, S_IRGRP, S_IROTH)

local C = ffi.C

ffi.cdef [[
int write(int fd, const void * ptr, int numbytes);
]]

-- fd tracking utility functions
local file_descriptors = {}

local LogfilesHandler = {}

LogfilesHandler.PRIORITY = 9
LogfilesHandler.VERSION = "0.1.0"

local function log()
    local data
    data = ngx.req.get_body_data()
    
    -- skywalking 8 start
    local trace_id ="";
    local propagatedContext = kong.request.get_header(CONTEXT_CARRIER_KEY)
    if propagatedContext ~= nil then
        local ref = SegmentRef.fromSW8Value(propagatedContext)
        if ref ~= nil then
            trace_id = ref.trace_id
        end
    end
    -- skywalking 8 end
    
    local logs = {
        client_ip = kong.client.get_ip(),
        client_forwarded_ip = kong.client.get_forwarded_ip(),
        trace_id = trace_id,
        request_scheme = kong.request.get_scheme(),
        request_host = kong.request.get_host(),
        request_method = kong.request.get_method(),
        request_path = kong.request.get_path(),
        request_headers = kong.request.get_headers(),
        request_sunmi_id = kong.ctx.shared.sunmi_id,
        request_sunmi_shopid = kong.ctx.shared.sunmi_shopid,
        request_raw_body = data,
        response_status = kong.response.get_status(),
        response_headers = kong.response.get_headers(),
        response_body = kong.ctx.plugin.respbody,
        process_time = 0,
        time = 0
    }

    if kong.ctx.plugin.access_time ~= nil then
        logs.process_time = (ngx.now() - kong.ctx.plugin.access_time)
        logs.time = kong.ctx.plugin.access_time
    end

    return logs
end

function LogfilesHandler:access(conf)
    kong.ctx.plugin.access_time = ngx.now()


end

function LogfilesHandler:body_filter(conf)

    local log_response_body_flag = false
    -- 
    if conf.recorded_all_content_type then
        log_response_body_flag = true
    else
        local content_type = kong.response.get_header("Content-Type")
        if content_type ~= nil then
            for index,value in pairs(conf.recorded_content_type) do
                if string.find(content_type, value) then
                    log_response_body_flag = true
                    break
                end
            end
        else
            if conf.recorded_content_type_is_null then
                log_response_body_flag = true
            end
        end
    end

    local ctx = ngx.ctx
    local chunk, eof = ngx.arg[1], ngx.arg[2]
    local uncompress = nil

    kong.ctx.plugin.body_chunks = kong.ctx.plugin.body_chunks or {}
    kong.ctx.plugin.body_chunk_number = kong.ctx.plugin.body_chunk_number or 1

    if eof then
        local chunks = table_concat(kong.ctx.plugin.body_chunks)
        if log_response_body_flag then
            -- gzip start
            local encoding = kong.response.get_header("Content-Encoding")
            if encoding == "gzip" then
                -- uncompress = zlib.inflate()(chunks)
                local count = 0
                local output_table = {}

                local output = function(data)
                    table_insert(output_table, data)
                end

                local input = function(bufsize)
                    local start = count > 0 and bufsize*count or 1
                    local data = chunks:sub(start, (bufsize*(count+1)-1) )
                    count = count + 1
                    return data
                end

                local ok, err = zlib.inflateGzip(input, output, ZLIB_BUFSIZE)
                if not ok then
                    ngx.log(ngx.ERR, "[logfiles] zlib.deflateGzip errror: ", err)
                end
                uncompress = table_concat(output_table,'')
            end
            -- gzip end
            kong.ctx.plugin.respbody = uncompress or chunks
        else
            kong.ctx.plugin.respbody = "[This response Content-Type is not recorded]"
        end
        ngx.arg[1] = chunks
    else
        kong.ctx.plugin.body_chunks[kong.ctx.plugin.body_chunk_number] = chunk
        kong.ctx.plugin.body_chunk_number = kong.ctx.plugin.body_chunk_number + 1
        ngx.arg[1] = nil
    end
end

function LogfilesHandler:log(conf)
    local logs = log()

    local msg = cjson.encode(logs) 
    msg = msg .. ",\n"

    local file_name = conf.filename .."-" .. os.date("%Y-%m-%d") .. ".log"

    local file_path = conf.path .. "/" .. file_name

    local fd = file_descriptors[file_path]

    if fd and conf.reopen then
        C.close(fd)
        file_descriptors[file_path] = nil
        fd = nil
    end

    if not fd then
        fd = C.open(file_path, oflags, mode)
        if fd < 0 then
            local errno = ffi.errno()
            ngx.log(ngx.ERR, "[logfiles] failed to open the file[" .. file_path .. "]: ", ffi.string(C.strerror(errno)))
        else
            file_descriptors[file_path] = fd
        end
    end

    C.write(fd, msg, #msg)

end

return LogfilesHandler