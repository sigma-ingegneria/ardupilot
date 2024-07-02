local scripting_rc_chan = rc:find_channel_for_option(300)
local previous_emergency_button_state = 0
local previous_flight_mode
local brake_mode_id = 17
local auto_mode_id = 3
local loiter_mode_id = 5
local auto_mode_safe_altitude = 280; -- 2.8m (disable AUTO below this altitude) (machinery directive says 2.7m)

function standby()
  -- wait until armed with healthy ahrs
  if ahrs:initialised() then
      gcs:send_text(6, "Drowings® Enhanced Safety - Starting -")
      return update, 250
  end
  return standby, 1000
end

function update()
  if rc:has_valid_input() then --verifico di non essere in failsafe
    pwm1 = rc:get_pwm(1) -- control stick
    pwm2 = rc:get_pwm(2) -- control stick
    emergency_button_state = scripting_rc_chan:get_aux_switch_pos()
    current_mode = vehicle:get_mode()

    -- controllo che i canali non siano zero, succede appena il drone si accende.
    if (pwm1 ~= 0) and (pwm2 ~= 0) then
      
      -- gestione bottone di emergenza
      if previous_emergency_button_state ~= emergency_button_state then
        -- restoring the previous mode is still missing
        if current_mode ~= brake_mode_id then -- if not brake mode (FIX)
        previous_flight_mode = current_mode;
        end

        vehicle:set_mode(brake_mode_id)
        gcs:send_text(5, "Braking! switch mode to regain control")
        previous_emergency_button_state = emergency_button_state
      end

      -- gestione uscita da AUTO se vengono mossi gli stick e se la quota scende sotto i 2.7m (direttiva macchine)
      if current_mode == auto_mode_id then 
      
        if (pwm1 > 1580) or (pwm1 < 1420) or (pwm2 > 1580) or (pwm2 < 1420) then --80uS deadband
          vehicle:set_mode(loiter_mode_id)
          gcs:send_text(5, "Mission paused, roll or pitch stick has been moved, switch mode to resume mission")
        end

        -- 25 = downward
        -- Se la quota è troppo bassa non si entra in modo LOITER!
        if rangefinder:has_data_orient(25) then
          if (rangefinder:distance_cm_orient(25) < auto_mode_safe_altitude) then
            vehicle:set_mode(loiter_mode_id)
            gcs:send_text(5, "Mission paused, drone is below safe altitude, switch mode to resume mission") 
          end
        end

      end
      
      -- Se sono in BRAKE e muovo gli stick torno in Loiter
      if current_mode == brake_mode_id then 
        if (pwm1 > 1580) or (pwm1 < 1420) or (pwm2 > 1580) or (pwm2 < 1420) then --80uS deadband
          vehicle:set_mode(loiter_mode_id)
          gcs:send_text(6, "Switching to Loiter, roll or pitch stick has been moved")
        end
      end
    end  
  end
  return update, 250 -- reschedules the loop
end

return standby()