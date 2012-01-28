module(..., package.seeall);

require('Body')
require('Kinematics')
require('Config');
require('Config_OP_HZD')
require('vector')
require 'util'

t0 = Body.get_time();

-- Suport the Walk API
velCurrent = vector.new({0, 0, 0});
stopRequest = 0;
uLeft = vector.new({0, 0, 0});
uRight = vector.new({0, 0, 0});

-- Walk Parameters
hardnessLeg_gnd = Config_OP_HZD.hardnessLeg or vector.new({.1,.1,.1,.1,.1,.1});
hardnessLeg_gnd[5] = 0; -- Ankle pitch is free moving
hardnessLeg_air = Config_OP_HZD.hardnessLeg or vector.new({.1,.1,.1,.1,.1,.1});

-- For Debugging
saveCount = 0;
jointNames = {"Left_Hip_Yaw", "Left_Hip_Roll", "Left_Hip_Pitch", "Left_Knee_Pitch", "Left_Ankle_Pitch", "Left_Ankle_Roll", "Right_Hip_Yaw", "Right_Hip_Roll", "Right_Hip_Pitch", "Right_Knee_Pitch", "Right_Ankle_Pitch", "Right_Ankle_Roll"};
logfile_name = string.format("/tmp/joint_angles.raw");
stance_ankle_id = 5;
air_ankle_id = 11;
supportLeg = 0;
switchLeg = 0;
beta = .8;--.2;
qLegs = Body.get_lleg_position();
theta_running = qLegs[stance_ankle_id];
use_deadband = false;

-- Set the deadbands
hyst = 0.02;
qLegs_deadband_Lforward = vector.zeros(12)
alpha = Config_OP_HZD.alpha_L;
for i=1,12 do
--  if (i~=stance_ankle_id and i~=air_ankle_id) then
    qLegs_deadband_Lforward[i] = util.polyval_bz(alpha[i], 0); --s = 0 for alphaL with left forward
--  end
end
qLegs_deadband_Rforward = vector.zeros(12)
alpha = Config_OP_HZD.alpha_R;
for i=1,12 do
--  if (i~=stance_ankle_id and i~=air_ankle_id) then
    qLegs_deadband_Rforward[i] = util.polyval_bz(alpha[i], 0);
--  end
end


function entry()
  Body.set_syncread_enable( 3 );
  supportLeg = 0;
  switchLeg = 0;
  qLegs = Body.get_lleg_position();
  theta_running = qLegs[stance_ankle_id];

  -- Set arms out in front
  Body.set_larm_hardness(Config_OP_HZD.hardnessArm);
  Body.set_rarm_hardness(Config_OP_HZD.hardnessArm);
  Body.set_larm_command(Config_OP_HZD.qLArm);
  Body.set_rarm_command(Config_OP_HZD.qRArm);

end

function update( )
  t = Body.get_time();
  -- Read the ankle joint value
  qLegs = Body.get_lleg_position();
  qLegs2 = Body.get_rleg_position();
  for i=1,6 do
    qLegs[i+6] = qLegs2[i];
  end

  if( supportLeg == 0 ) then -- Left left on ground
    Body.set_lleg_hardness(hardnessLeg_gnd);
    Body.set_rleg_hardness(hardnessLeg_air);    
    alpha = Config_OP_HZD.alpha_L;
    stance_ankle_id = 5;
    air_ankle_id = 11;
    theta_min = Config_OP_HZD.theta_min_L;
    theta_max = Config_OP_HZD.theta_max_L;
  else
    Body.set_rleg_hardness(hardnessLeg_gnd);
    Body.set_lleg_hardness(hardnessLeg_air);    
    alpha = Config_OP_HZD.alpha_R;
    -- Read the ankle joint value
    stance_ankle_id = 11;
    air_ankle_id = 5;
    theta_min = Config_OP_HZD.theta_min_R;
    theta_max = Config_OP_HZD.theta_max_R;
  end

  -- Make the measurement of our ankle angle, and filter
  theta = qLegs[stance_ankle_id]; -- Just use the stance ankle
  theta_running = beta*theta + (1-beta)*theta_running;

--  s = (theta_running - theta_min) / (theta_max - theta_min) ;
  s = (theta - theta_min) / (theta_max - theta_min) ;
  -- Clamp s between 0 and 1
  s = math.max( math.min( s,1 ), 0 );

  -- Check if we are in the deadband
  if( use_deadband and ((s>(1-hyst) and supportLeg==0) or (s<hyst and supportLeg==1)) ) then
    -- s=0 with supportLeg as right or s=1 with supportLeg as left
    qLegs = qLegs_deadband_Rforward;
    print('deadband right forward!');
    -- Always switch legs in the deadband
    switchLeg = 1;
  elseif( use_deadband and ((s>(1-hyst) and supportLeg==1) or (s<hyst and supportLeg==0)) ) then
    qLegs = qLegs_deadband_Lforward;
    print('deadband left forward!')
    -- Always switch legs in the deadband
    switchLeg = 1;
  else
    -- Outside of the deadband
    -- Set each ankle position
    for i=1,12 do
      if (i~=stance_ankle_id) then
        qLegs[i] = util.polyval_bz(alpha[i], s);
      end
    end
    if( not use_deadband and (s>1-hyst or s<hyst)) then
      switchLeg = 1;      
    end
  end

  -- Add IMU feedback
  local imuAngle = Body.get_sensor_imuAngle();
  -- Bound the ankle of both left and right roll (-10 to +10 degrees)
  qLegs[i] = util.polyval_bz(alpha[i], s ) + imuAngle[1]; -- where is is ankle roll id

  -- Do we switch supportLeg this cycle?
  if( switchLeg == 1 ) then
    switchLeg = 0;
    supportLeg = 1 - supportLeg;
    -- Prepare to filter using the theta of the next ankle
    theta_running = qLegs[air_ankle_id];
  end

  -- Debug Printing in degrees
  print();
  print('Support Leg: ', supportLeg);
  print('theta / theta_running:', theta, '/', theta_running, '|| s:', s);
  print('theta min / max', theta_min, '/', theta_max );
--[[
  for i=1,12 do
    print( jointNames[i] .. ':\t'..qLegs[i]*180/math.pi );
  end
--]]

  Body.set_lleg_command(qLegs);
  -- return the HZD qLegs
  return qLegs;

end

function record_joint_angles( supportLeg, qlegs )

  -- Open the file
  local f = io.open(logfile_name, "a");
  assert(f, "Could not open save image file");
  if( saveCount == 0 ) then
    -- Write the Header
    f:write( "time,LeftOnGnd,RightOnGnd,IMU_Roll,IMU_Pitch,IMU_Yaw" );
    for i=1,12 do
      f:write( string.format(",%s",jointNames[i]) );
    end
    f:write( "\n" );
  end

  -- Write the data
  local t = Body.get_time();
  f:write( string.format("%f",t-t0) );
  f:write( string.format(",%d,%d",1-supportLeg,supportLeg) );
  local imuAngle = Body.get_sensor_imuAngle();
  f:write( string.format(",%f,%f,%f",unpack(imuAngle)) );
  -- Read the joint values
--[[
  qLegs = Body.get_lleg_position();
  qLegs2 = Body.get_rleg_position();
  for i=1,6 do
    qLegs[i+6] = qLegs2[i];
  end
--]]
  for i=1,12 do
    f:write( string.format(",%f",qlegs[i]) );
  end
  f:write( "\n" );
  -- Close the file
  f:close();
  saveCount = saveCount + 1;

end

-- Walk API functions
function set_velocity(vx, vy, vz)
end

function stop()
  stopRequest = math.max(1,stopRequest);
end

function stopAlign()
  stop()
end

--dummy function for NSL kick
function zero_velocity()
end

function start()
--  stopRequest = false;
  stopRequest = 0;
  if (not active) then
    active = true;
    iStep0 = -1;
    t0 = Body.get_time();
    initdone=false;
    delaycount=0;
    initial_step=1;
  end
end

function get_velocity()
  return velCurrent;
end

function exit()
end

function get_odometry(u0)
  return vector.new({0,0,0}),vector.new({0,0,0});
end
   
function get_body_offset()
  return {0,0,0}; 
end

entry();

