-- Drowings® Enhanced LiDAR Safety Script

-- Param: SCR_USER1 (Distanza minima ostacolo)

-- Constants
local MODE_AUTO = 3
local MODE_LOITER = 5
local MINIMUM_OBSTACLE_PERSISTANCE = 200 -- ms (0.2 seconds)
local SLOWDOWN_AFTER = 300 -- ms (0.3 seconds)
local SLOWDOWN_DURATION = 1600 -- ms  (1.6 seconds)
local SLOW_SPEED = 0.1 -- m/s
local AUTO_MODE_COLLISION_DETECTION_MIN_ALTITUDE = 0.5 -- m

-- State
local obstacle_distance_threshold = 3.0 -- meters Param: SCR_USER1
local wpnav_speed = 100 -- Default speed in cm/s
local normal_speed = wpnav_speed / 100 -- m/s
local detection_start_time = 0
local slowed = false
local switched_to_loiter = false
local last_mode = -1
local elapsed = 0

function standby()
    gcs:send_text(6, "Drowings® LiDAR Safety v1 - Starting -")

    -- Load SCR Param
    local obstacle_distance_threshold_param = Parameter('SCR_USER1')

    local obstacle_distance_threshold_user =
        obstacle_distance_threshold_param:get()
    if obstacle_distance_threshold_user then
        if obstacle_distance_threshold_user < 1 then
            obstacle_distance_threshold = 1
        else
            obstacle_distance_threshold = obstacle_distance_threshold_user
        end
        obstacle_distance_threshold = obstacle_distance_threshold_user + 0.5 -- add safety margin
        -- gcs:send_text(6, string.format('Drowings® LiDAR Safety: Threshold: %.2f', obstacle_distance_threshold))

    else
        gcs:send_text(5, 'Drowings® LiDAR Safety: Threshold read failed')
        return standby, 5000 -- riprovo tra 5 secondi
    end

    -- Load WPNAV_SPEED Param
    local wpnav_speed_param = Parameter('WPNAV_SPEED')

    local wpnav_speed_param_value = wpnav_speed_param:get()
    if wpnav_speed_param_value then
        wpnav_speed = wpnav_speed_param_value
        normal_speed = wpnav_speed / 100 -- Convert cm/s to m/s
        -- gcs:send_text(6, string.format('Drowings® LiDAR Safety: Normal Speed: %.2f',normal_speed))

    else
        gcs:send_text(5, 'Drowings® LiDAR Safety read WPNAV_SPEED failed')
        return standby, 5000 -- riprovo tra 5 secondi
    end

    if ahrs:initialised() then
        gcs:send_text(6, "Drowings® LiDAR Safety - OK -")
        return update, 250
    else
        return standby, 5000 -- riprovo tra 5 secondi
    end
end

function update()

    local mode = vehicle:get_mode()

    -- Detect transition into AUTO
    if last_mode ~= mode and mode == MODE_AUTO then
        -- Restore speed on entering AUTO
        vehicle:set_desired_speed(normal_speed)
        gcs:send_text(6, "Drowings® LiDAR Safety: Speed reset to normal.")
        slowed = false
        switched_to_loiter = false
        detection_start_time = 0
    end

    last_mode = mode

    -- 25 = downward
    -- Se la quota è troppo bassa non si attiva l'anticollisione
    if rangefinder:has_data_orient(25) then
        if (rangefinder:distance_cm_orient(25) <
            AUTO_MODE_COLLISION_DETECTION_MIN_ALTITUDE) then
            gcs:send_text(5,
                          "Drowings® LiDAR Safety - Disabled due to low altitude -")
            return update, 5000 -- Riprovo tra cinque secondi
        end
    end

    -- Main logic only active in AUTO (checking if we are not in AUTO mode)
    if mode ~= MODE_AUTO then
        detection_start_time = 0
        return update, 1000
    end

    local angle, distance = proximity:get_closest_object()

    if distance ~= nil then

        if distance >= 0 and distance <= obstacle_distance_threshold then

            if detection_start_time == 0 then
                detection_start_time = millis()
            end

            elapsed = millis() - detection_start_time

            if elapsed >= SLOWDOWN_AFTER and not slowed then
                vehicle:set_desired_speed(SLOW_SPEED)
                gcs:send_text(6, "Drowings® LiDAR Safety: Slowing down")
                slowed = true
            end

            if elapsed >= SLOWDOWN_DURATION and not switched_to_loiter then
                gcs:send_text(6, "Drowings® LiDAR Safety: Stopping")
                vehicle:set_mode(MODE_LOITER)
                switched_to_loiter = true
            end
        else
            -- Obstacle cleared
            if elapsed >= MINIMUM_OBSTACLE_PERSISTANCE then
                detection_start_time = 0
                if slowed then
                    vehicle:set_desired_speed(normal_speed)
                    gcs:send_text(6, "Drowings® LiDAR Safety: Obstacle cleared")
                    slowed = false
                end
                switched_to_loiter = false
            end

        end
    else
        gcs:send_text(6, "Drowings® LiDAR Safety: Invalid LiDAD data")
        return update, 500
    end

    return update, 50
end

return standby()