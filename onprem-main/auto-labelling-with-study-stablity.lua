-- Initialize global tables to track labels and study stability
if activeLabels == nil then
    activeLabels = {}  -- Tracks label timestamps
  end
  if studyInstanceCount == nil then
    studyInstanceCount = {}  -- Tracks instance counts per study
  end
  if studyStable == nil then
    studyStable = {}  -- Tracks stability status per study
  end
  
  -- Helper function to get current time (using Lua's os.time)
  local function getCurrentTime()
    local time = os.time()
    print("Current time (os.time): " .. time)
    return time
  end
  
  -- Cleanup function to remove expired labels (60 seconds)
  local function cleanupExpiredLabels()
    local currentTime = getCurrentTime()
    if not currentTime then
      print("Skipping cleanup due to time fetch failure")
      return
    end
    print("Running cleanup at " .. currentTime)
    if next(activeLabels) == nil then
      print("No active labels to clean")
      return
    end
  
    for studyId, timestamps in pairs(activeLabels) do
      print("Checking study " .. studyId .. " in activeLabels")
      if timestamps["NEW-STUDY"] then
        local age = currentTime - timestamps["NEW-STUDY"]
        print("NEW-STUDY label for study " .. studyId .. " is " .. age .. " seconds old")
        if age > 60 then  -- 60 seconds
          print("Removing expired NEW-STUDY label for study " .. studyId)
          local success, err = pcall(function() RestApiDelete("/studies/" .. studyId .. "/labels/NEW-STUDY") end)
          if success then
            timestamps["NEW-STUDY"] = nil
          else
            print("Failed to remove NEW-STUDY label: " .. tostring(err))
          end
        end
      end
      if timestamps["MODIFIED"] then
        local age = currentTime - timestamps["MODIFIED"]
        print("MODIFIED label for study " .. studyId .. " is " .. age .. " seconds old")
        if age > 60 then  -- 60 seconds
          print("Removing expired MODIFIED label for study " .. studyId)
          local success, err = pcall(function() RestApiDelete("/studies/" .. studyId .. "/labels/MODIFIED") end)
          if success then
            timestamps["MODIFIED"] = nil
          else
            print("Failed to remove MODIFIED label: " .. tostring(err))
          end
        end
      end
      if not timestamps["NEW-STUDY"] and not timestamps["MODIFIED"] then
        activeLabels[studyId] = nil
        print("Cleared study " .. studyId .. " from activeLabels")
      end
    end
  end
  
  -- Handle uploads (triggered by new DICOM instances)
  function OnStoredInstance(instanceId, tags, metadata)
    local study = ParseJson(RestApiGet("/instances/" .. instanceId .. "/study"))
    local series = ParseJson(RestApiGet("/instances/" .. instanceId .. "/series"))
    local studyId = study.ID
    local currentTime = getCurrentTime()
    if not currentTime then
      print("Skipping label addition for study " .. studyId .. " due to time fetch failure")
      return
    end
  
    -- Initialize instance count if not already tracked
    if not studyInstanceCount[studyId] then
      studyInstanceCount[studyId] = 0
    end
    studyInstanceCount[studyId] = studyInstanceCount[studyId] + 1
    print("Study " .. studyId .. " instance count: " .. studyInstanceCount[studyId])
  
    -- Add NEW-STUDY label for the first instance of a new study
    local isFirstInstance = (studyInstanceCount[studyId] == 1)
    if isFirstInstance and #study.Labels == 0 then
      print("Adding NEW-STUDY label for study " .. studyId .. " at " .. currentTime)
      local success, err = pcall(function() RestApiPut("/studies/" .. studyId .. "/labels/NEW-STUDY", '') end)
      if success then
        if not activeLabels[studyId] then activeLabels[studyId] = {} end
        activeLabels[studyId]["NEW-STUDY"] = currentTime
      else
        print("Failed to add NEW-STUDY label: " .. tostring(err))
      end
    end
  
    -- Check if this instance is added after stability
    if studyStable[studyId] and studyInstanceCount[studyId] > studyStable[studyId].count then
      print("Study " .. studyId .. " was stable, now modified with new instance at " .. currentTime)
      local success, err = pcall(function() RestApiPut("/studies/" .. studyId .. "/labels/MODIFIED", '') end)
      if success then
        if not activeLabels[studyId] then activeLabels[studyId] = {} end
        activeLabels[studyId]["MODIFIED"] = currentTime
      else
        print("Failed to add MODIFIED label: " .. tostring(err))
      end
    end
  
    -- Run cleanup on every upload
    cleanupExpiredLabels()
  end
  
  -- Handle modifications (triggered by study changes, e.g., metadata edits)
  function OnModifiedInstance(instanceId, tags, metadata, origin)
    local study = ParseJson(RestApiGet("/instances/" .. instanceId .. "/study"))
    local studyId = study.ID
    local currentTime = getCurrentTime()
    if not currentTime then
      print("Skipping label addition for study " .. studyId .. " due to time fetch failure")
      return
    end
  
    -- For metadata edits after stability, add MODIFIED label
    if studyStable[studyId] then
      print("Adding MODIFIED label for study " .. studyId .. " due to metadata change at " .. currentTime)
      local success, err = pcall(function() RestApiPut("/studies/" .. studyId .. "/labels/MODIFIED", '') end)
      if success then
        if not activeLabels[studyId] then activeLabels[studyId] = {} end
        activeLabels[studyId]["MODIFIED"] = currentTime
      else
        print("Failed to add MODIFIED label: " .. tostring(err))
      end
    end
  
    cleanupExpiredLabels()
  end
  
  -- Handle stable studies (runs when a study is fully received and stable)
  function OnStableStudy(studyId, tags, metadata)
    local currentTime = getCurrentTime()
    if not currentTime then
      print("Skipping stability handling for study " .. studyId .. " due to time fetch failure")
      return
    end
  
    print("Study " .. studyId .. " stabilized at " .. currentTime)
    local study = ParseJson(RestApiGet("/studies/" .. studyId))
    local totalInstances = 0
    for _, seriesId in ipairs(study.Series) do
      local series = ParseJson(RestApiGet("/series/" .. seriesId))
      totalInstances = totalInstances + #series.Instances
    end
  
    studyStable[studyId] = { time = currentTime, count = totalInstances }
    print("Study " .. studyId .. " stable with " .. totalInstances .. " instances")
    cleanupExpiredLabels()
  end
  
  -- Optional: Handle incoming HTTP requests (for debugging or manual triggers)
  function OnIncomingHttpRequest(method, uri, ip, username, httpHeaders)
    print("HTTP request received: " .. method .. " " .. uri .. " from " .. ip)
    cleanupExpiredLabels()
  end