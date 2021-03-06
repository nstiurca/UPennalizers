module(..., package.seeall);

require('Config');	-- For Ball and Goal Size
require('ImageProc');
require('HeadTransform');	-- For Projection
require('Body')
require('Vision');

-- Dependency
require('Detection');

-- Define Color
colorOrange = 1;
colorYellow = 2;
colorCyan = 4;
colorField = 8;
colorWhite = 16;

use_point_goal=Config.vision.use_point_goal;
headInverted=Config.vision.headInverted;

function detect(color)
  local goal = {};
  goal.detect = 0;


  local postDiameter = 0.10;
  local postHeight = 0.80;
  local goalWidth = 1.40;
  local nPostB = 5;  -- appropriate for scaleB = 4

  local postB = ImageProc.goal_posts(Vision.labelB.data, Vision.labelB.m, Vision.labelB.n, color, nPostB);
  if (not postB) then 
    return goal; 
  end

  local npost = 0;
  local ivalidB = {};
  local postA = {};
  for i = 1,#postB do
    local valid = true;
    local postStats = Vision.bboxStats(color, postB[i].boundingBox);
    -- size and orientation
    --print("Size and orientation check ", postStats.area, 180/math.pi*postStats.orientation)
    if (math.abs(postStats.orientation) < 60*math.pi/180) then
      valid = false;
    end
      
    --fill extent check
    local extent = postStats.area / (postStats.axisMajor * postStats.axisMinor);
    --print("Fill extent check ", extent)

    --aspect ratio check
    local aspect = postStats.axisMajor/postStats.axisMinor;
    --print("Aspect check ", aspect)
    if ((aspect < 2.5) or (aspect > 15)) then 
--      valid = false; 
    end


    -- ground check
    -- is post at the bottom
    local bboxA = Vision.bboxB2A(postB[i].boundingBox);
    if (valid) then
      if (bboxA[4] < 0.9 * Vision.labelA.n) then

        -- field bounding box 
        local fieldBBox = {};
        fieldBBox[1] = bboxA[1] - 15;
        fieldBBox[2] = bboxA[2] + 15;
        fieldBBox[3] = bboxA[4] - 15;
        fieldBBox[4] = bboxA[4] + 10;

        -- color stats for the bbox
        local fieldBBoxStats = ImageProc.color_stats(Vision.labelA.data, Vision.labelA.m, Vision.labelA.n, colorField, fieldBBox);
        local fieldBBoxArea = Vision.bboxArea(fieldBBox);

        --print('field check: area: '..fieldBBoxArea..' bbox: '..fieldBBoxStats.area);

        -- is there green under the ball?
      end
    end


    --TODO: we need to check any bad color near post 
    --to get rid of any false positives (landmarks)

    if (valid) then
      ivalidB[#ivalidB + 1] = i;
      npost = npost + 1;
      postA[npost] = postStats;
    end
  end

  if ((npost < 1) or (npost > 2)) then 
    return goal; 
  end

  goal.propsB = {};
  goal.propsA = {};
  goal.v = {};
  for i = 1,npost do
    goal.propsB[i] = postB[ivalidB[i]];
    goal.propsA[i] = postA[i];

    scale = math.max(postA[i].axisMinor / postDiameter,
                      postA[i].axisMajor / postHeight,
                      math.sqrt(postA[i].area / (postDiameter*postHeight)));
    goal.v[i] = HeadTransform.coordinatesA(postA[i].centroid, scale);

    --print(string.format("post[%d] = %.2f %.2f %.2f", i, goal.v[i][1], goal.v[i][2], goal.v[i][3]));
  end

  if (npost == 2) then
    goal.type = 3;

    -- check for valid separation between posts:
    local dgoal = postA[2].centroid[1]-postA[1].centroid[1];
    local dpost = math.max(postA[1].axisMajor, postA[2].axisMajor);
  else
    goal.v[2] = vector.new({0,0,0,0});

    -- look for crossbar:
    local postWidth = postA[1].axisMinor;
    local leftX = postA[1].boundingBox[1]-5*postWidth;
    local rightX = postA[1].boundingBox[2]+5*postWidth;
    local topY = postA[1].boundingBox[3]-postWidth;
    local bottomY = postA[1].boundingBox[3]+2*postWidth;
    local bboxA = {leftX, rightX, topY, bottomY};
    local crossbarStats = ImageProc.color_stats(Vision.labelA.data, Vision.labelA.m, Vision.labelA.n, color, bboxA);
    local dxCrossbar = crossbarStats.centroid[1] - postA[1].centroid[1];
    if (math.abs(dxCrossbar) > 0.6*postWidth) then
      if (dxCrossbar > 0) then
        -- left post
--        goal.type = 1;
	goal.type = 0;
      else
        -- right post
--        goal.type = 2;
	goal.type = 0;
      end
    else
      -- unknown post
      goal.type = 0;
--      if (postA[1].area < 200) then
        -- eliminate small posts without cross bars
--        return goal;
--      end
    end
  end
  
  -- added for test_vision.m
  if Config.vision.copy_image_to_shm then
    vcm.set_goal_postBoundingBox1(postB[ivalidB[1]].boundingBox);
    if npost == 2 then
      vcm.set_goal_postBoundingBox2(postB[ivalidB[2]].boundingBox);
    else
      vcm.set_goal_postBoundingBox2(vector.zeros(4));
    end
  end

  goal.detect = 1;
  return goal;
end
