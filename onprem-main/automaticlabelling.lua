function OnStoredInstance(instanceId, tags, metadata)
    -- Add "NEW" label to new studies
    SetLabel(instanceId, "NEW")
  end
  
  function OnModifiedInstance(instanceId, tags, metadata)
    -- Add "MODIFIED" label to edited studies
    SetLabel(instanceId, "MODIFIED")
  end