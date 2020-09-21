--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--    http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

local typedefs = require "kong.db.schema.typedefs"

return {
  name = "logfiles",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { path = { 
              type = "string",
              required = true,
              match = [[^[^*&%%\`]+$]],
              err = "not a valid path",
              default = "/data/kong-log",
          }, },
          { filename = { 
              type = "string",
              required = true,
              match = [[^[^*&%%\`]+$]],
              err = "not a valid filename",
              default = "access",
          }, },
          { reopen = { 
              type = "boolean", 
              default = false 
          }, },
          { recorded_all_content_type = { 
              type = "boolean", 
              default = false
          }, },
          { recorded_content_type_is_null = { 
              type = "boolean", 
              default = false
          }, },
          { recorded_content_type = {
              type = "array",
              required = true,
              elements = { type = "string" },
              default = { "application/json", "text/xml", "application/xml", "application/x-www-form-urlencoded", "multipart/form-data", },
          }, },
    }, }, },
  }
}