function OnStoredInstance(instanceId, tags, metadata)
    local studyId = GetParentResource(instanceId, "Study")
    if studyId then
        local success, err = pcall(SetLabel, studyId, "NEW")
        if not success then
            print("Error setting label for stored instance: " .. err)
        end
    else
        print("Study ID not found for stored instance: " .. instanceId)
    end
end

function OnModifiedInstance(instanceId, tags, metadata, origin)
    local studyId = GetParentResource(instanceId, "Study")
    if studyId then
        local success, err = pcall(SetLabel, studyId, "MODIFIED")
        if not success then
            print("Error setting label for modified instance: " .. err)
        end
    else
        print("Study ID not found for modified instance: " .. instanceId)
    end
end
