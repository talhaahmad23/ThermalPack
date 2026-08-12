function ThermalPackApp_v1_App
% ThermalPack v1.0 — Battery Thermal Design & Simulation Platform
% Uses Thermal_Model_v3.slx as the master model and a non-destructive working copy.
% Generated battery libraries are stored in ThermalPack_Generated/.

baseMdl = "Thermal_Model_v3";
mdl     = "Thermal_Model_v3_UI";

%% Default operating profile
% TEMPORARY HARD-CODED OPERATING PROFILE
% CurrentProfile format:
%   column 1 = time [s]
%   column 2 = battery current [A]
% The From Workspace block in Thermal_Model_v3 must use:
%   Data = CurrentProfile
%   Interpolate data = OFF
% Signal-Editor-style representation. Repeated time values create
% vertical steps in the Custom Load Profile editor/preview.
CurrentProfileDefault = [ ...
      0,   80; ...
    300,   80; ...
    300,    0; ...
    600,    0; ...
    600,  -80; ...
    900,  -80];

%% Create a non-destructive UI working model
if isempty(which(mdl + ".slx"))
    if isempty(which(baseMdl + ".slx"))
        tempFig = uifigure;
        uialert(tempFig, ...
            "Thermal_Model_v3.slx was not found in the current folder or MATLAB path.", ...
            "ThermalPack");
        delete(tempFig);
        return;
    end

    if ~bdIsLoaded(baseMdl)
        load_system(baseMdl);
    end

    save_system(baseMdl, mdl + ".slx");
    close_system(baseMdl,0);
end

if ~bdIsLoaded(mdl)
    load_system(mdl);
end

batteryBlock = mdl + "/Cylindrical_Cell_Module_Test";
plateBlock   = mdl + "/Parallel Channels";

if getSimulinkBlockHandle(batteryBlock) <= 0
    error("ThermalPack:BatteryBlockMissing", ...
        "Battery block '%s' was not found.",batteryBlock);
end

if getSimulinkBlockHandle(plateBlock) <= 0
    error("ThermalPack:CoolingPlateMissing", ...
        "Cooling plate block '%s' was not found.",plateBlock);
end

%% Capture the v3 battery as the master physics definition
% Every rebuilt battery inherits these values before any UI override is
% applied. This preserves the original OCV/R0 lookup tables, breakpoints,
% thermal parameters, initialization settings, and per-cell deviations.
baseLoadedForCapture = false;
if ~bdIsLoaded(baseMdl)
    load_system(baseMdl);
    baseLoadedForCapture = true;
end

baseBatteryBlock = baseMdl + "/Cylindrical_Cell_Module_Test";
if getSimulinkBlockHandle(baseBatteryBlock) <= 0
    error("ThermalPack:MasterBatteryMissing", ...
        "Master battery block '%s' was not found.",baseBatteryBlock);
end

masterBatteryParams = captureMasterBatteryParameters(baseBatteryBlock);

if baseLoadedForCapture
    close_system(baseMdl,0);
end

masterCapacity_Ah = scalarParam(masterBatteryParams,"BatteryCapacityCell",5);
masterThermalMass_J_K = scalarParam(masterBatteryParams,"BatteryThermalMassCell",100);
masterNodes = round(scalarParam(masterBatteryParams,"NumThermalModelsCell",6));
masterConductivity_W_mK = scalarParam(masterBatteryParams,"ThermalConductivityZCell",15);
masterCrossSection_m2 = scalarParam(masterBatteryParams,"CrossSectionalAreaXYCell",3.5e-4);
masterHeight_m = scalarParam(masterBatteryParams,"HeightCell",0.07);
masterCoolantR_K_W = scalarParam(masterBatteryParams,"CoolantResistance",1.2);
masterAmbientR_K_W = scalarParam(masterBatteryParams,"AmbientResistance",25);
masterInterCellR_K_W = scalarParam(masterBatteryParams,"InterCellThermalResistance",1);

%% Master cell electrical / variation data used to initialize the editor.
masterVoltageRange_V = numericExpressionParam( ...
    masterBatteryParams,"VoltageRangeCell",[0 Inf]);
masterOCVSOC = rowVectorParam( ...
    masterBatteryParams,"SOCBreakpointsCell",[0 .1 .25 .5 .75 .9 1]);
masterOCVTemp_K = rowVectorParam( ...
    masterBatteryParams,"TemperatureBreakpointsCell",[278 293 313]);
masterOCVTable_V = numericExpressionParam( ...
    masterBatteryParams,"OpenCircuitVoltageThermalCell", ...
    [3.49 3.50 3.51; 3.55 3.57 3.56; 3.62 3.63 3.64; ...
     3.71 3.71 3.72; 3.91 3.93 3.94; 4.07 4.08 4.08; ...
     4.19 4.19 4.19]);

masterResistanceSOC = rowVectorParam( ...
    masterBatteryParams,"ResistanceSOCBreakpointsCell",masterOCVSOC);
masterResistanceTemp_K = rowVectorParam( ...
    masterBatteryParams,"ResistanceTemperatureBreakpointsCell",masterOCVTemp_K);
masterR0Table_Ohm = numericExpressionParam( ...
    masterBatteryParams,"R0ThermalCell", ...
    [.0117 .0085 .0090; .0110 .0085 .0090; .0114 .0087 .0092; ...
     .0107 .0082 .0088; .0107 .0083 .0091; .0113 .0085 .0089; ...
     .0116 .0085 .0089]);

masterInitialTemperature_K = firstNumericValueParam( ...
    masterBatteryParams,"batteryTemperature",298.15);

if isfield(masterBatteryParams,"ExtrapolationMethodCell")
    masterExtrapolation = friendlyExtrapolationLabel( ...
        masterBatteryParams.ExtrapolationMethodCell);
else
    masterExtrapolation = "Nearest";
end

masterR0Deviation_pct = deviationVectorParam( ...
    masterBatteryParams,"R0ThermalCellPercentDeviation",12);
masterThermalMassDeviation_pct = deviationVectorParam( ...
    masterBatteryParams,"BatteryThermalMassCellPercentDeviation",12);
masterConductivityDeviation_pct = deviationVectorParam( ...
    masterBatteryParams,"ThermalConductivityZCellPercentDeviation",12);

%% App state
state = struct;
state.P = 4;
state.S = 3;
state.TotalCells = 12;
state.Diameter_mm = 20;
state.Height_mm = 70;
state.InterCellGap_mm = 1;
state.InterAssemblyGap_mm = 1;
state.Topology = "Square";
state.Rows = 1;
state.ParallelAssemblyStackingAxis = "Y";
state.ModuleStackingAxis = "X";
state.MassFactor = 1.0;
state.InterCellHeatTransfer = "Enabled";
state.CoolingPlateMode = "Bottom Cooling Plate";
state.NoCoolingRth_K_W = 1e9;
state.LoadProfile = "Custom";
state.LastValidLoadProfile = "Custom";
state.CustomCurrentProfile = CurrentProfileDefault;
state.Solver = "Auto";

%% Cell electrical data
state.ExtrapolationMethod = masterExtrapolation;
state.VoltageRange_V = masterVoltageRange_V(:).';
state.OCVSOCBreakpoints = masterOCVSOC(:).';
state.OCVTemperature_C = masterOCVTemp_K(:).' - 273.15;
state.OCVTable_V = masterOCVTable_V;
state.ResistanceSOCBreakpoints = masterResistanceSOC(:).';
state.ResistanceTemperature_C = masterResistanceTemp_K(:).' - 273.15;
state.R0Table_Ohm = masterR0Table_Ohm;

%% Per-cell percentage variation
state.R0Deviation_pct = masterR0Deviation_pct(:);
state.ThermalMassDeviation_pct = masterThermalMassDeviation_pct(:);
state.ThermalConductivityDeviation_pct = masterConductivityDeviation_pct(:);

%% Initial condition
state.InitialCellTemperature_C = masterInitialTemperature_K - 273.15;

%% Thermal-liquid reservoir settings
state.ReservoirPressureSpecification = "Atmospheric pressure";
state.ReservoirPressure_Pa = 101325;
state.ReservoirPressureInput = false;
state.ReservoirTemperatureInput = false;
state.CoolantPortDiameter_mm = 10;
state.CoolantPortArea_m2 = pi*(state.CoolantPortDiameter_mm/1000)^2/4;

%% Thermal Liquid Properties (TL)
state.CoolantFluid = "Ethylene glycol and water mixture";
state.CoolantConcentrationType = "Volume fraction";
state.CoolantConcentration = 0.50;

%% Existing model variable used by Thermal Liquid Properties (TL).
state.AtmosphericPressure_Pa = 101325;

%% Flow Rate Source (TL)
state.FlowSourceType = "Constant";
state.FlowRateType = "Mass flow rate";
state.MassFlowRate_kg_s = 0.020;
state.VolumetricFlowRate_m3_s = 0;

%% Parallel Channels cooling plate
state.PlateConnectivity = "Single sided";
state.PlatePartitionsX = round(blockNumericParam(plateBlock,"plateDimX",3));
state.PlatePartitionsY = round(blockNumericParam(plateBlock,"plateDimY",4));
state.PlateThickness_mm = 1000*blockNumericParam(plateBlock,"plateTh",2e-3);
state.PlateConductivity_W_mK = blockNumericParam(plateBlock,"plateThCond",205);
state.PlateDensity_kg_m3 = blockNumericParam(plateBlock,"plateDen",2700);
state.PlateSpecificHeat_J_kgK = blockNumericParam(plateBlock,"plateCp",900);
state.InitialPlateTemperature_C = ...
    blockNumericParam(plateBlock,"plateTemp_ini",298.15) - 273.15;
state.NumCoolantChannels = round(blockNumericParam(plateBlock,"nChannels",4));

orientationRaw = string(get_param(plateBlock,"selectChannelOrientation"));
if contains(lower(orientationRaw),"alongy")
    state.ChannelOrientation = "Channels along Y axis";
else
    state.ChannelOrientation = "Channels along X axis";
end

state.ChannelHydraulicDiameter_mm = ...
    1000*blockNumericParam(plateBlock,"channelDia",0.004);
state.DistributorDiameter_mm = ...
    1000*blockNumericParam(plateBlock,"distributorDia",0.006);
state.ChannelRoughness_mm = ...
    1000*blockNumericParam(plateBlock,"roughnessPipe",1.5e-5);

state.GeneratedLibrary = "";
state.GeneratedModuleObject = [];

%% Geometry captured directly from Battery Builder during REBUILD BATTERY.
% These bottom-interface node locations are used as the X-Y cell positions
% for the custom height-resolved 3D thermal renderer.
state.BatteryThermalNodeLocations = [];
state.BatteryThermalNodeDimensions = [];

%% Latest completed simulation results used by the Dashboard detail windows.
state.LastKPI = [];
state.LastTrace = [];
state.LastRuntime_s = NaN;
state.LastCurrentProfileDescription = "";

state.NeedsRebuild = false;

%% Main window
screenSize = get(groot,"ScreenSize");   % [left bottom width height]

appWidth  = min(1500, max(1050, screenSize(3) - 100));
appHeight = min(900,  max(700,  screenSize(4) - 140));

appLeft   = screenSize(1) + max(20,(screenSize(3) - appWidth)/2);
appBottom = screenSize(2) + max(40,(screenSize(4) - appHeight)/2);

fig = uifigure( ...
    "Name","ThermalPack — Battery Thermal Design Platform", ...
    "Position",[appLeft appBottom appWidth appHeight]);

main = uigridlayout(fig,[1 2]);
main.ColumnWidth = {min(420,max(340,round(appWidth*0.30))),'1x'};
main.RowHeight = {'1x'};
main.Padding = [12 12 12 12];
main.ColumnSpacing = 12;

%% LEFT — Configuration
leftPanel = uipanel(main,"Title","Battery & Simulation Configuration");
leftPanel.Layout.Row = 1;
leftPanel.Layout.Column = 1;

left = uigridlayout(leftPanel,[57 2]);
left.ColumnWidth = {215,'1x'};

%% Fixed row heights intentionally make the configuration taller than the
left.RowHeight = repmat({29},1,57);
left.Padding = [12 12 18 12];
left.RowSpacing = 6;
left.Scrollable = "on";

titleLabel = uilabel(left, ...
    "Text","THERMALPACK", ...
    "FontSize",22, ...
    "FontWeight","bold");
titleLabel.Layout.Row = 1;
titleLabel.Layout.Column = [1 2];

subLabel = uilabel(left, ...
    "Text","Current Version - Version 1.0", ...
    "FontSize",12);
subLabel.Layout.Row = 2;
subLabel.Layout.Column = [1 2];

%% Parameterization
sectionLabel(left,3,"PARAMETERIZATION");

addInputLabel(left,4,"Cell data source");
parameterizationField = uidropdown(left, ...
    "Items","Custom Cell", ...
    "Value","Custom Cell");
parameterizationField.Layout.Row = 4;
parameterizationField.Layout.Column = 2;

manufacturerComingSoon = uilabel(left, ...
    "Text","Manufacturer Preset — Coming Soon!", ...
    "FontAngle","italic", ...
    "Enable","off");
manufacturerComingSoon.Layout.Row = 5;
manufacturerComingSoon.Layout.Column = [1 2];

%% Architecture
sectionLabel(left,6,"BATTERY ARCHITECTURE");

addInputLabel(left,7,"Cell format");
formatField = uidropdown(left, ...
    "Items","Cylindrical", ...
    "Value","Cylindrical");
formatField.Layout.Row = 7;
formatField.Layout.Column = 2;

addInputLabel(left,8,"Topology");
topologyField = uidropdown(left, ...
    "Items",["Square","Hexagonal"], ...
    "Value","Square", ...
    "ValueChangedFcn",@structuralValueChanged);
topologyField.Layout.Row = 8;
topologyField.Layout.Column = 2;

addInputLabel(left,9,"Parallel cells (P)");
parallelField = uieditfield(left,"numeric", ...
    "Value",4,"Limits",[1 149],"RoundFractionalValues","on", ...
    "ValueChangedFcn",@structuralValueChanged);
parallelField.Layout.Row = 9;
parallelField.Layout.Column = 2;

addInputLabel(left,10,"Rows");
rowsField = uieditfield(left,"numeric", ...
    "Value",1,"Limits",[1 49],"RoundFractionalValues","on", ...
    "ValueChangedFcn",@structuralValueChanged);
rowsField.Layout.Row = 10;
rowsField.Layout.Column = 2;

addInputLabel(left,11,"Parallel assembly stacking axis");
parallelStackingAxisField = uidropdown(left, ...
    "Items",["Y","X"], ...
    "Value","Y", ...
    "ValueChangedFcn",@structuralValueChanged);
parallelStackingAxisField.Layout.Row = 11;
parallelStackingAxisField.Layout.Column = 2;

addInputLabel(left,12,"Series groups (S)");
seriesField = uieditfield(left,"numeric", ...
    "Value",3,"Limits",[1 149],"RoundFractionalValues","on", ...
    "ValueChangedFcn",@structuralValueChanged);
seriesField.Layout.Row = 12;
seriesField.Layout.Column = 2;

addInputLabel(left,13,"Module stacking axis");
moduleStackingAxisField = uidropdown(left, ...
    "Items",["X","Y"], ...
    "Value","X", ...
    "ValueChangedFcn",@structuralValueChanged);
moduleStackingAxisField.Layout.Row = 13;
moduleStackingAxisField.Layout.Column = 2;

addInputLabel(left,14,"Mass factor");
massFactorField = uieditfield(left,"numeric", ...
    "Value",1.0,"Limits",[1 Inf], ...
    "ValueChangedFcn",@structuralValueChanged);
massFactorField.Layout.Row = 14;
massFactorField.Layout.Column = 2;

addInputLabel(left,15,"Inter-cell gap (mm)");
cellGapField = uieditfield(left,"numeric", ...
    "Value",1,"Limits",[0 99], ...
    "ValueChangedFcn",@structuralValueChanged);
cellGapField.Layout.Row = 15;
cellGapField.Layout.Column = 2;

addInputLabel(left,16,"Series-group gap (mm)");
assemblyGapField = uieditfield(left,"numeric", ...
    "Value",1,"Limits",[0 99], ...
    "ValueChangedFcn",@structuralValueChanged);
assemblyGapField.Layout.Row = 16;
assemblyGapField.Layout.Column = 2;

topologyNote = uilabel(left, ...
    "Text","Topology, rows, stacking axes and geometry changes require REBUILD BATTERY.", ...
    "FontAngle","italic", ...
    "WordWrap","on");
topologyNote.Layout.Row = 17;
topologyNote.Layout.Column = [1 2];

%% Cell specifications
sectionLabel(left,18,"CELL SPECIFICATIONS");

addInputLabel(left,19,"Diameter (mm)");
diameterField = uieditfield(left,"numeric", ...
    "Value",20,"Limits",[1 999], ...
    "ValueChangedFcn",@structuralValueChanged);
diameterField.Layout.Row = 19;
diameterField.Layout.Column = 2;

addInputLabel(left,20,"Height (mm)");
heightField = uieditfield(left,"numeric", ...
    "Value",70,"Limits",[1 2000], ...
    "ValueChangedFcn",@structuralValueChanged);
heightField.Layout.Row = 20;
heightField.Layout.Column = 2;

addInputLabel(left,21,"Mass (kg)");
massField = uieditfield(left,"numeric", ...
    "Value",0.1,"Limits",[0.0001 Inf]);
massField.Layout.Row = 21;
massField.Layout.Column = 2;

addInputLabel(left,22,"Capacity (Ah)");
capacityField = uieditfield(left,"numeric", ...
    "Value",masterCapacity_Ah,"Limits",[0.001 Inf]);
capacityField.Layout.Row = 22;
capacityField.Layout.Column = 2;

addInputLabel(left,23,"Nominal energy (Wh)");
energyField = uieditfield(left,"numeric", ...
    "Value",18,"Limits",[0.001 Inf]);
energyField.Layout.Row = 23;
energyField.Layout.Column = 2;

addInputLabel(left,24,"Initial SOC");
socField = uieditfield(left,"numeric", ...
    "Value",0.40,"Limits",[0 1]);
socField.Layout.Row = 24;
socField.Layout.Column = 2;

addInputLabel(left,25,"Initial cell temperature (°C)");
initialCellTempField = uieditfield(left,"numeric", ...
    "Value",state.InitialCellTemperature_C, ...
    "Limits",[-273.14 Inf]);
initialCellTempField.Layout.Row = 25;
initialCellTempField.Layout.Column = 2;

cellElectricalButton = uibutton(left,"push", ...
    "Text","CELL ELECTRICAL DATA", ...
    "FontWeight","bold", ...
    "ButtonPushedFcn",@openCellElectricalData);
cellElectricalButton.Layout.Row = 26;
cellElectricalButton.Layout.Column = [1 2];

%% Thermal model
sectionLabel(left,27,"THERMAL MODEL");

addInputLabel(left,28,"Thermal model");
thermalModelField = uidropdown(left, ...
    "Items","Height-Distributed Thermal Mass", ...
    "Value","Height-Distributed Thermal Mass");
thermalModelField.Layout.Row = 28;
thermalModelField.Layout.Column = 2;

addInputLabel(left,29,"Thermal nodes");
nodesField = uispinner(left, ...
    "Limits",[1 20], ...
    "Step",1, ...
    "Value",min(20,max(1,round(masterNodes))));
nodesField.Layout.Row = 29;
nodesField.Layout.Column = 2;

%% Thermal properties
sectionLabel(left,30,"THERMAL PROPERTIES");

addInputLabel(left,31,"Thermal mass (J/K)");
thermalMassField = uieditfield(left,"numeric", ...
    "Value",masterThermalMass_J_K,"Limits",[0.001 Inf]);
thermalMassField.Layout.Row = 31;
thermalMassField.Layout.Column = 2;

addInputLabel(left,32,"Axial conductivity (W/mK)");
conductivityField = uieditfield(left,"numeric", ...
    "Value",masterConductivity_W_mK,"Limits",[0.001 Inf]);
conductivityField.Layout.Row = 32;
conductivityField.Layout.Column = 2;

addInputLabel(left,33,"Thermal cross section (m²)");
thermalAreaField = uieditfield(left,"numeric", ...
    "Value",masterCrossSection_m2,"Limits",[1e-10 Inf]);
thermalAreaField.Layout.Row = 33;
thermalAreaField.Layout.Column = 2;

%% Load profile
sectionLabel(left,34,"LOAD PROFILE");

addInputLabel(left,35,"Profile");
loadProfileField = uidropdown(left, ...
    "Items",[ ...
        "Custom", ...
        "Constant Discharge — Coming Soon", ...
        "Constant Charge — Coming Soon", ...
        "Pulse Load — Coming Soon", ...
        "Drive Cycle / CSV — Coming Soon"], ...
    "Value","Custom", ...
    "ValueChangedFcn",@loadProfileChanged);
loadProfileField.Layout.Row = 35;
loadProfileField.Layout.Column = 2;

customLoadProfileButton = uibutton(left,"push", ...
    "Text","CUSTOM LOAD PROFILE", ...
    "FontWeight","bold", ...
    "Enable","on", ...
    "ButtonPushedFcn",@openCustomLoadProfile);
customLoadProfileButton.Layout.Row = 36;
customLoadProfileButton.Layout.Column = [1 2];

addInputLabel(left,37,"Simulation time (s)");
stopField = uieditfield(left,"numeric", ...
    "Value",900,"Limits",[1 Inf]);
stopField.Layout.Row = 37;
stopField.Layout.Column = 2;

%% Cooling / boundary conditions
sectionLabel(left,38,"COOLING & ENVIRONMENT");

addInputLabel(left,39,"Cooling plate");
coolingPlateField = uidropdown(left, ...
    "Items",["Bottom Cooling Plate","No Cooling Plate"], ...
    "Value","Bottom Cooling Plate", ...
    "ValueChangedFcn",@coolingModeChanged);
coolingPlateField.Layout.Row = 39;
coolingPlateField.Layout.Column = 2;

topCoolingComingSoon = uilabel(left, ...
    "Text","Top Cooling Plate — Coming Soon!", ...
    "FontAngle","italic", ...
    "Enable","off");
topCoolingComingSoon.Layout.Row = 40;
topCoolingComingSoon.Layout.Column = [1 2];

coolingModeNote = uilabel(left, ...
    "Text","Bottom plate active — Cell → plate Rth is applied.", ...
    "FontAngle","italic", ...
    "WordWrap","on");
coolingModeNote.Layout.Row = 41;
coolingModeNote.Layout.Column = [1 2];

flowLabel = addInputLabel(left,42,"Coolant flow (kg/s)");
flowField = uieditfield(left,"numeric", ...
    "Value",state.MassFlowRate_kg_s,"Limits",[0 Inf]);
flowField.Layout.Row = 42;
flowField.Layout.Column = 2;

addInputLabel(left,43,"Coolant inlet (°C)");
tinField = uieditfield(left,"numeric","Value",25);
tinField.Layout.Row = 43;
tinField.Layout.Column = 2;

addInputLabel(left,44,"Ambient (°C)");
ambientField = uieditfield(left,"numeric","Value",25);
ambientField.Layout.Row = 44;
ambientField.Layout.Column = 2;

addInputLabel(left,45,"Cell → plate Rth (K/W)");
coolantRField = uieditfield(left,"numeric", ...
    "Value",masterCoolantR_K_W,"Limits",[0 Inf]);
coolantRField.Layout.Row = 45;
coolantRField.Layout.Column = 2;

addInputLabel(left,46,"Cell → ambient Rth (K/W)");
ambientRField = uieditfield(left,"numeric", ...
    "Value",masterAmbientR_K_W,"Limits",[0 Inf]);
ambientRField.Layout.Row = 46;
ambientRField.Layout.Column = 2;

addInputLabel(left,47,"Inter-cell heat transfer");
interCellHeatField = uidropdown(left, ...
    "Items",["Enabled","Disabled"], ...
    "Value","Enabled", ...
    "ValueChangedFcn",@interCellHeatChanged);
interCellHeatField.Layout.Row = 47;
interCellHeatField.Layout.Column = 2;

addInputLabel(left,48,"Inter-cell Rth (K/W)");
interCellRField = uieditfield(left,"numeric", ...
    "Value",masterInterCellR_K_W,"Limits",[0 Inf]);
interCellRField.Layout.Row = 48;
interCellRField.Layout.Column = 2;

addInputLabel(left,49,"Inter-parallel assembly Rth (K/W)");
interParallelRField = uieditfield(left,"numeric", ...
    "Value",1,"Limits",[0 Inf]);
interParallelRField.Layout.Row = 49;
interParallelRField.Layout.Column = 2;

coolingPlateSettingsButton = uibutton(left,"push", ...
    "Text","COOLING PLATE SETTINGS", ...
    "FontWeight","bold", ...
    "ButtonPushedFcn",@openCoolingPlateSettings);
coolingPlateSettingsButton.Layout.Row = 50;
coolingPlateSettingsButton.Layout.Column = [1 2];

flowSourceSettingsButton = uibutton(left,"push", ...
    "Text","FLOW SOURCE SETTINGS", ...
    "FontWeight","bold", ...
    "ButtonPushedFcn",@openFlowSourceSettings);
flowSourceSettingsButton.Layout.Row = 51;
flowSourceSettingsButton.Layout.Column = [1 2];

coolantPropertiesButton = uibutton(left,"push", ...
    "Text","COOLANT PROPERTIES", ...
    "FontWeight","bold", ...
    "ButtonPushedFcn",@openCoolantProperties);
coolantPropertiesButton.Layout.Row = 52;
coolantPropertiesButton.Layout.Column = [1 2];

reservoirSettingsButton = uibutton(left,"push", ...
    "Text","RESERVOIR SETTINGS", ...
    "FontWeight","bold", ...
    "ButtonPushedFcn",@openReservoirSettings);
reservoirSettingsButton.Layout.Row = 53;
reservoirSettingsButton.Layout.Column = [1 2];

advancedButton = uibutton(left,"push", ...
    "Text","ADVANCED SETTINGS", ...
    "FontWeight","bold", ...
    "FontColor",[1 1 1], ...
    "BackgroundColor",[0.70 0.08 0.08], ...
    "ButtonPushedFcn",@openAdvancedSettings);
advancedButton.Layout.Row = 54;
advancedButton.Layout.Column = [1 2];

rebuildButton = uibutton(left,"push", ...
    "Text","REBUILD BATTERY", ...
    "FontWeight","bold", ...
    "ButtonPushedFcn",@rebuildBattery);
rebuildButton.Layout.Row = 55;
rebuildButton.Layout.Column = [1 2];

runButton = uibutton(left,"push", ...
    "Text","RUN SIMULATION", ...
    "FontWeight","bold", ...
    "ButtonPushedFcn",@runSimulation);
runButton.Layout.Row = 56;
runButton.Layout.Column = [1 2];

statusLabel = uilabel(left, ...
    "Text","Ready — current model is 4P × 3S", ...
    "HorizontalAlignment","center", ...
    "WordWrap","on");
statusLabel.Layout.Row = 57;
statusLabel.Layout.Column = [1 2];

%% RIGHT — Results and visualization
rightPanel = uipanel(main,"Title","Thermal Results & Visualization");
rightPanel.Layout.Row = 1;
rightPanel.Layout.Column = 2;

%% Make the tab group fill the complete right-side panel.
rightHost = uigridlayout(rightPanel,[1 1]);
rightHost.RowHeight = {'1x'};
rightHost.ColumnWidth = {'1x'};
rightHost.Padding = [0 0 0 0];
rightHost.RowSpacing = 0;
rightHost.ColumnSpacing = 0;

rightTabs = uitabgroup(rightHost);
rightTabs.Layout.Row = 1;
rightTabs.Layout.Column = 1;

dashboardTab = uitab(rightTabs,"Title","Dashboard");
geometryTab = uitab(rightTabs,"Title","Battery Geometry");
thermalMapTab = uitab(rightTabs,"Title","3D Thermal Map");

%% Dashboard tab
right = uigridlayout(dashboardTab,[4 1]);
right.RowHeight = {105,'1x','1x',48};
right.Padding = [12 12 12 12];
right.RowSpacing = 10;

kpiGrid = uigridlayout(right,[1 5]);
kpiGrid.Layout.Row = 1;
kpiGrid.Layout.Column = 1;
kpiGrid.ColumnWidth = {'1x','1x','1x','1x','1x'};
kpiGrid.Padding = [0 0 0 0];

[~,kpiTmaxValue]    = makeCard(kpiGrid,1,"PEAK NODAL TEMPERATURE","-- °C");
[~,kpiDeltaValue]   = makeCard(kpiGrid,2,"MAXIMUM NODAL ΔT","-- °C");
[~,kpiHotspotValue] = makeCard(kpiGrid,3,"HOTSPOT","--");
[~,kpiMarginValue]  = makeCard(kpiGrid,4,"SAFETY MARGIN","-- °C");
[~,kpiStatusValue]  = makeCard(kpiGrid,5,"THERMAL STATUS","--");

%% Graph 1 — individual cell-average temperatures.
temperatureAxes = uiaxes(right);
temperatureAxes.Layout.Row = 2;
temperatureAxes.Layout.Column = 1;
title(temperatureAxes,"Cell Average Temperatures");
xlabel(temperatureAxes,"Time (s)");
ylabel(temperatureAxes,"Temperature (°C)");
grid(temperatureAxes,"on");

%% Graph 2 — pack envelope based on CELL-AVERAGE temperatures.
cellAverageEnvelopeAxes = uiaxes(right);
cellAverageEnvelopeAxes.Layout.Row = 3;
cellAverageEnvelopeAxes.Layout.Column = 1;
title(cellAverageEnvelopeAxes,"Cell-Average Temperature Summary");
xlabel(cellAverageEnvelopeAxes,"Time (s)");
ylabel(cellAverageEnvelopeAxes,"Temperature (°C)");
grid(cellAverageEnvelopeAxes,"on");

%% Only the two detailed-result actions requested for the Dashboard.
dashboardButtons = uigridlayout(right,[1 2]);
dashboardButtons.Layout.Row = 4;
dashboardButtons.Layout.Column = 1;
dashboardButtons.ColumnWidth = {'1x','1x'};
dashboardButtons.RowHeight = {'1x'};
dashboardButtons.Padding = [0 0 0 0];
dashboardButtons.ColumnSpacing = 10;

cellNodalResultsButton = uibutton(dashboardButtons,"push", ...
    "Text","CELL / NODAL RESULTS", ...
    "FontWeight","bold", ...
    "Enable","off", ...
    "ButtonPushedFcn",@openCellNodalResults);
cellNodalResultsButton.Layout.Row = 1;
cellNodalResultsButton.Layout.Column = 1;

simulationSummaryButton = uibutton(dashboardButtons,"push", ...
    "Text","SIMULATION SUMMARY", ...
    "FontWeight","bold", ...
    "Enable","off", ...
    "ButtonPushedFcn",@openSimulationSummary);
simulationSummaryButton.Layout.Row = 1;
simulationSummaryButton.Layout.Column = 2;

%% Battery Geometry tab
geometryGrid = uigridlayout(geometryTab,[2 1]);
geometryGrid.RowHeight = {38,'1x'};
geometryGrid.ColumnWidth = {'1x'};
geometryGrid.Padding = [12 12 12 12];
geometryGrid.RowSpacing = 8;

geometryStatus = uilabel(geometryGrid, ...
    "Text","Rebuild the battery to generate the 3D geometry.", ...
    "FontWeight","bold", ...
    "HorizontalAlignment","center");
geometryStatus.Layout.Row = 1;
geometryStatus.Layout.Column = 1;

geometryPlaceholder = uilabel(geometryGrid, ...
    "Text","3D Battery Geometry will appear here after REBUILD BATTERY.", ...
    "HorizontalAlignment","center", ...
    "VerticalAlignment","center", ...
    "FontAngle","italic");
geometryPlaceholder.Layout.Row = 2;
geometryPlaceholder.Layout.Column = 1;

geometryChart = [];

%% 3D Thermal Map tab
thermalMapGrid = uigridlayout(thermalMapTab,[4 1]);
thermalMapGrid.RowHeight = {38,'1x',44,40};
thermalMapGrid.ColumnWidth = {'1x'};
thermalMapGrid.Padding = [12 12 12 12];
thermalMapGrid.RowSpacing = 8;

thermalMapStatus = uilabel(thermalMapGrid, ...
    "Text","Run a simulation after rebuilding the battery to generate the 3D thermal map.", ...
    "FontWeight","bold", ...
    "HorizontalAlignment","center");
thermalMapStatus.Layout.Row = 1;
thermalMapStatus.Layout.Column = 1;

thermalChartHost = uigridlayout(thermalMapGrid,[1 1]);
thermalChartHost.Layout.Row = 2;
thermalChartHost.Layout.Column = 1;
thermalChartHost.RowHeight = {'1x'};
thermalChartHost.ColumnWidth = {'1x'};
thermalChartHost.Padding = [0 0 0 0];

thermalMapPlaceholder = uilabel(thermalChartHost, ...
    "Text","3D thermal map will appear here after a successful simulation.", ...
    "HorizontalAlignment","center", ...
    "VerticalAlignment","center", ...
    "FontAngle","italic");
thermalMapPlaceholder.Layout.Row = 1;
thermalMapPlaceholder.Layout.Column = 1;

%% Minimal thermal-map control: scrub simulation time directly.
thermalTimeSlider = uislider(thermalMapGrid, ...
    "Limits",[0 1], ...
    "Value",0, ...
    "Enable","off", ...
    "ValueChangingFcn",@thermalSliderChanging, ...
    "ValueChangedFcn",@thermalSliderChanged);
thermalTimeSlider.Layout.Row = 3;
thermalTimeSlider.Layout.Column = 1;

%% Compact playback controls for Version 1.0.
thermalPlaybackControls = uigridlayout(thermalMapGrid,[1 4]);
thermalPlaybackControls.Layout.Row = 4;
thermalPlaybackControls.Layout.Column = 1;
thermalPlaybackControls.ColumnWidth = {'1x','1x','1x','1x'};
thermalPlaybackControls.RowHeight = {'1x'};
thermalPlaybackControls.Padding = [0 0 0 0];
thermalPlaybackControls.ColumnSpacing = 8;

thermalPlayButton = uibutton(thermalPlaybackControls,"push", ...
    "Text","PLAY", ...
    "FontWeight","bold", ...
    "Enable","off", ...
    "ButtonPushedFcn",@playThermalAnimation);
thermalPlayButton.Layout.Column = 1;

thermalPauseButton = uibutton(thermalPlaybackControls,"push", ...
    "Text","PAUSE", ...
    "Enable","off", ...
    "ButtonPushedFcn",@pauseThermalAnimation);
thermalPauseButton.Layout.Column = 2;

thermalStopButton = uibutton(thermalPlaybackControls,"push", ...
    "Text","STOP", ...
    "Enable","off", ...
    "ButtonPushedFcn",@stopThermalAnimation);
thermalStopButton.Layout.Column = 3;

thermalSpeedButton = uibutton(thermalPlaybackControls,"push", ...
    "Text","SPEED 1×", ...
    "Enable","off", ...
    "ButtonPushedFcn",@increaseThermalPlaybackSpeed);
thermalSpeedButton.Layout.Column = 4;

thermalChart = [];
thermalSimLog = [];
thermalColorBar = [];
thermalPlaybackEnd_s = 0;

%% Thermal animation playback state.
thermalPlaybackTimer = [];
thermalPlaybackSpeed = 1;
thermalPlaybackSpeeds = [1 2 4 8];
thermalPlaybackTimerPeriod_s = 0.05;
thermalPlaybackBaseDuration_s = 30;

%% Custom ThermalPack nodal 3D renderer state.
thermalPatch = [];
thermalFaceNodeIndex = [];
thermalNodal_C = [];
thermalNodalTime_s = [];
thermalNodeCount = 0;
thermalCellCount = 0;

%% Ensure an active playback timer is disposed when ThermalPack closes.
fig.CloseRequestFcn = @closeThermalPackApp;

%% Nested callbacks
    function structuralValueChanged(~,~)
        state.NeedsRebuild = true;
        statusLabel.Text = "Structural values changed — click REBUILD BATTERY";
    end

    function openCellElectricalData(~,~)
%% Cell Electrical Data is a runtime parameter editor. It does not
        % require a Battery Builder rebuild unless the cell count itself has
        % changed.

        parentPos = fig.Position;
        parentCenter = [parentPos(1)+parentPos(3)/2, ...
                        parentPos(2)+parentPos(4)/2];

        monitorPos = get(groot,"MonitorPositions");
        if isempty(monitorPos)
            monitorPos = get(groot,"ScreenSize");
        end

        monIdx = 1;
        for kMon = 1:size(monitorPos,1)
            m = monitorPos(kMon,:);
            if parentCenter(1) >= m(1) && ...
               parentCenter(1) <= m(1)+m(3) && ...
               parentCenter(2) >= m(2) && ...
               parentCenter(2) <= m(2)+m(4)
                monIdx = kMon;
                break
            end
        end
        mon = monitorPos(monIdx,:);

        winW = min(1120,max(820,mon(3)-120));
        winH = min(760,max(560,mon(4)-150));
        winX = mon(1) + (mon(3)-winW)/2;
        winY = mon(2) + (mon(4)-winH)/2;

        dataFig = uifigure( ...
            "Name","ThermalPack — Cell Electrical Data", ...
            "WindowStyle","modal", ...
            "Position",[winX winY winW winH], ...
            "CloseRequestFcn",@(srcFig,~)closeCellElectricalData(srcFig));
        movegui(dataFig,"onscreen");

        outer = uigridlayout(dataFig,[3 1]);
        outer.RowHeight = {46,'1x',44};
        outer.Padding = [14 14 14 14];
        outer.RowSpacing = 10;

        hdr = uilabel(outer, ...
            "Text","CELL ELECTRICAL DATA", ...
            "FontSize",18, ...
            "FontWeight","bold");
        hdr.Layout.Row = 1;

        tabs = uitabgroup(outer);
        tabs.Layout.Row = 2;

        generalTab = uitab(tabs,"Title","General");
        ocvTab = uitab(tabs,"Title","OCV");
        resistanceTab = uitab(tabs,"Title","Resistance");
        variationTab = uitab(tabs,"Title","Cell Variation");

        %% General
        gen = uigridlayout(generalTab,[5 2]);
        gen.ColumnWidth = {300,'1x'};
        gen.RowHeight = {38,38,38,38,'1x'};
        gen.Padding = [18 18 18 18];
        gen.RowSpacing = 10;

        g1 = uilabel(gen,"Text","Extrapolation method");
        g1.Layout.Row = 1; g1.Layout.Column = 1;
        extrapolationField = uidropdown(gen, ...
            "Items",["Nearest","Linear","Error"], ...
            "Value",state.ExtrapolationMethod);
        extrapolationField.Layout.Row = 1;
        extrapolationField.Layout.Column = 2;

        g2 = uilabel(gen,"Text","Minimum cell voltage (V)");
        g2.Layout.Row = 2; g2.Layout.Column = 1;
        voltageMinField = uieditfield(gen,"numeric", ...
            "Value",state.VoltageRange_V(1));
        voltageMinField.Layout.Row = 2;
        voltageMinField.Layout.Column = 2;

        g3 = uilabel(gen,"Text","Maximum cell voltage (V)");
        g3.Layout.Row = 3; g3.Layout.Column = 1;
        voltageMaxField = uieditfield(gen,"numeric", ...
            "Value",state.VoltageRange_V(min(2,end)));
        voltageMaxField.Layout.Row = 3;
        voltageMaxField.Layout.Column = 2;

        %% OCV
        ocvGrid = uigridlayout(ocvTab,[4 2]);
        ocvGrid.ColumnWidth = {260,'1x'};
        ocvGrid.RowHeight = {34,120,34,'1x'};
        ocvGrid.Padding = [14 14 14 14];
        ocvGrid.RowSpacing = 8;

        o1 = uilabel(ocvGrid,"Text","SOC breakpoints");
        o1.Layout.Row = 1; o1.Layout.Column = 1;
        o2 = uilabel(ocvGrid,"Text","Temperature breakpoints (°C)");
        o2.Layout.Row = 1; o2.Layout.Column = 2;

        ocvSOCTable = uitable(ocvGrid, ...
            "Data",state.OCVSOCBreakpoints(:), ...
            "ColumnName","SOC", ...
            "ColumnEditable",true, ...
            "RowName",[]);
        ocvSOCTable.Layout.Row = 2;
        ocvSOCTable.Layout.Column = 1;

        ocvTempTable = uitable(ocvGrid, ...
            "Data",state.OCVTemperature_C(:), ...
            "ColumnName","Temperature (°C)", ...
            "ColumnEditable",true, ...
            "RowName",[]);
        ocvTempTable.Layout.Row = 2;
        ocvTempTable.Layout.Column = 2;

        o3 = uilabel(ocvGrid,"Text","OCV(SOC,T) table (V)");
        o3.Layout.Row = 3;
        o3.Layout.Column = [1 2];

        ocvDataTable = uitable(ocvGrid, ...
            "Data",state.OCVTable_V, ...
            "ColumnEditable",true(1,size(state.OCVTable_V,2)));
        ocvDataTable.Layout.Row = 4;
        ocvDataTable.Layout.Column = [1 2];
        refreshOCVLabels();

        %% Resistance
        rGrid = uigridlayout(resistanceTab,[4 2]);
        rGrid.ColumnWidth = {260,'1x'};
        rGrid.RowHeight = {34,120,34,'1x'};
        rGrid.Padding = [14 14 14 14];
        rGrid.RowSpacing = 8;

        r1 = uilabel(rGrid,"Text","Resistance SOC breakpoints");
        r1.Layout.Row = 1; r1.Layout.Column = 1;
        r2 = uilabel(rGrid,"Text","Resistance temperature breakpoints (°C)");
        r2.Layout.Row = 1; r2.Layout.Column = 2;

        resistanceSOCTable = uitable(rGrid, ...
            "Data",state.ResistanceSOCBreakpoints(:), ...
            "ColumnName","SOC", ...
            "ColumnEditable",true, ...
            "RowName",[]);
        resistanceSOCTable.Layout.Row = 2;
        resistanceSOCTable.Layout.Column = 1;

        resistanceTempTable = uitable(rGrid, ...
            "Data",state.ResistanceTemperature_C(:), ...
            "ColumnName","Temperature (°C)", ...
            "ColumnEditable",true, ...
            "RowName",[]);
        resistanceTempTable.Layout.Row = 2;
        resistanceTempTable.Layout.Column = 2;

        r3 = uilabel(rGrid,"Text","R0(SOC,T) table (Ω)");
        r3.Layout.Row = 3;
        r3.Layout.Column = [1 2];

        r0DataTable = uitable(rGrid, ...
            "Data",state.R0Table_Ohm, ...
            "ColumnEditable",true(1,size(state.R0Table_Ohm,2)));
        r0DataTable.Layout.Row = 4;
        r0DataTable.Layout.Column = [1 2];
        refreshR0Labels();

        %% Cell variation
        targetN = round(parallelField.Value) * round(seriesField.Value);
        r0Dev = resizeNumericVector(state.R0Deviation_pct,targetN,0);
        tmDev = resizeNumericVector(state.ThermalMassDeviation_pct,targetN,0);
        kDev = resizeNumericVector(state.ThermalConductivityDeviation_pct,targetN,0);

        varGrid = uigridlayout(variationTab,[1 1]);
        varGrid.Padding = [14 14 14 14];

        variationTable = uitable(varGrid, ...
            "Data",[(1:targetN).' r0Dev tmDev kDev], ...
            "ColumnName",["Cell","R0 deviation (%)", ...
                          "Thermal mass deviation (%)", ...
                          "Thermal conductivity deviation (%)"], ...
            "ColumnEditable",[false true true true], ...
            "RowName",[]);
        variationTable.Layout.Row = 1;
        variationTable.Layout.Column = 1;

        %% Bottom buttons
        btnGrid = uigridlayout(outer,[1 4]);
        btnGrid.Layout.Row = 3;
        btnGrid.ColumnWidth = {'1x','1x','1x','1x'};
        btnGrid.Padding = [0 0 0 0];

        applyBtn = uibutton(btnGrid,"push", ...
            "Text","APPLY", ...
            "FontWeight","bold", ...
            "ButtonPushedFcn",@applyCellElectricalData);
        applyBtn.Layout.Column = [1 3];

        closeBtn = uibutton(btnGrid,"push", ...
            "Text","CLOSE", ...
            "ButtonPushedFcn",@(srcBtn,~) ...
                closeCellElectricalData(ancestor(srcBtn,"figure")));
        closeBtn.Layout.Column = 4;

        function refreshOCVLabels()
            soc = ocvSOCTable.Data;
            tc = ocvTempTable.Data;
            if isnumeric(soc) && ~isempty(soc)
                ocvDataTable.RowName = cellstr(compose("SOC %.4g",soc(:)));
            end
            if isnumeric(tc) && ~isempty(tc) && ...
                    size(ocvDataTable.Data,2) == numel(tc)
                ocvDataTable.ColumnName = cellstr(compose("%.4g °C",tc(:).'));
            end
        end

        function refreshR0Labels()
            soc = resistanceSOCTable.Data;
            tc = resistanceTempTable.Data;
            if isnumeric(soc) && ~isempty(soc)
                r0DataTable.RowName = cellstr(compose("SOC %.4g",soc(:)));
            end
            if isnumeric(tc) && ~isempty(tc) && ...
                    size(r0DataTable.Data,2) == numel(tc)
                r0DataTable.ColumnName = cellstr(compose("%.4g °C",tc(:).'));
            end
        end

        function applyCellElectricalData(~,~)
            vMin = voltageMinField.Value;
            vMax = voltageMaxField.Value;
            ocvSOC = ocvSOCTable.Data(:).';
            ocvTemp_C = ocvTempTable.Data(:).';
            ocvValues = ocvDataTable.Data;
            rSOC = resistanceSOCTable.Data(:).';
            rTemp_C = resistanceTempTable.Data(:).';
            r0Values = r0DataTable.Data;
            varData = variationTable.Data;

            if ~isfinite(vMin) || ~(isfinite(vMax) || isinf(vMax)) || ...
                    vMin < 0 || vMax <= vMin
                uialert(dataFig, ...
                    "Voltage range must satisfy 0 ≤ minimum < maximum.", ...
                    "Invalid Cell Data");
                return;
            end

            if ~validSOCBreakpoints(ocvSOC)
                uialert(dataFig, ...
                    "OCV SOC breakpoints must be finite, strictly increasing, and between 0 and 1.", ...
                    "Invalid Cell Data");
                return;
            end

            if ~validTemperatureBreakpoints(ocvTemp_C)
                uialert(dataFig, ...
                    "OCV temperature breakpoints must be finite, strictly increasing, and above absolute zero.", ...
                    "Invalid Cell Data");
                return;
            end

            if ~isnumeric(ocvValues) || ...
                    ~isequal(size(ocvValues),[numel(ocvSOC),numel(ocvTemp_C)]) || ...
                    any(~isfinite(ocvValues),"all") || any(ocvValues < 0,"all")
                uialert(dataFig, ...
                    "OCV table size must equal [number of SOC breakpoints × number of temperature breakpoints] and contain finite non-negative values.", ...
                    "Invalid Cell Data");
                return;
            end

            if ~validSOCBreakpoints(rSOC)
                uialert(dataFig, ...
                    "Resistance SOC breakpoints must be finite, strictly increasing, and between 0 and 1.", ...
                    "Invalid Cell Data");
                return;
            end

            if ~validTemperatureBreakpoints(rTemp_C)
                uialert(dataFig, ...
                    "Resistance temperature breakpoints must be finite, strictly increasing, and above absolute zero.", ...
                    "Invalid Cell Data");
                return;
            end

            if ~isnumeric(r0Values) || ...
                    ~isequal(size(r0Values),[numel(rSOC),numel(rTemp_C)]) || ...
                    any(~isfinite(r0Values),"all") || any(r0Values < 0,"all")
                uialert(dataFig, ...
                    "R0 table size must equal [number of SOC breakpoints × number of temperature breakpoints] and contain finite non-negative values.", ...
                    "Invalid Cell Data");
                return;
            end

            if ~isnumeric(varData) || size(varData,1) ~= targetN || ...
                    size(varData,2) ~= 4 || any(~isfinite(varData(:,2:4)),"all")
                uialert(dataFig, ...
                    "Cell variation values must be finite numeric percentages.", ...
                    "Invalid Cell Data");
                return;
            end

            state.ExtrapolationMethod = string(extrapolationField.Value);
            state.VoltageRange_V = [vMin vMax];
            state.OCVSOCBreakpoints = double(ocvSOC);
            state.OCVTemperature_C = double(ocvTemp_C);
            state.OCVTable_V = double(ocvValues);
            state.ResistanceSOCBreakpoints = double(rSOC);
            state.ResistanceTemperature_C = double(rTemp_C);
            state.R0Table_Ohm = double(r0Values);
            state.R0Deviation_pct = double(varData(:,2));
            state.ThermalMassDeviation_pct = double(varData(:,3));
            state.ThermalConductivityDeviation_pct = double(varData(:,4));

%% If topology has not changed, update the current working block
            if ~state.NeedsRebuild && targetN == state.TotalCells
                applyCellElectricalDataToBlock(batteryBlock,state,state.TotalCells);
                save_system(mdl);
            end

            statusLabel.Text = "Cell electrical data applied";
        end
    end

    function closeCellElectricalData(windowToClose)
        if ~isempty(windowToClose) && isvalid(windowToClose)
            delete(windowToClose);
        end

        drawnow;

        if isvalid(fig)
            try
                focus(cellElectricalButton);
            catch
                fig.Visible = "on";
                movegui(fig,"onscreen");
            end
        end
    end

    function loadProfileChanged(~,~)
        selected = string(loadProfileField.Value);

        if selected == "Custom"
            state.LoadProfile = "Custom";
            state.LastValidLoadProfile = "Custom";
            customLoadProfileButton.Enable = "on";
            statusLabel.Text = "Custom load profile selected";
        else
%% MATLAB uidropdown does not support disabling individual
            % entries. Future profiles remain visible but unavailable.
            uialert(fig, ...
                "This load profile is not enabled yet.", ...
                "ThermalPack — Coming Soon");

            loadProfileField.Value = "Custom";
            state.LoadProfile = "Custom";
            state.LastValidLoadProfile = "Custom";
            customLoadProfileButton.Enable = "on";
        end
    end

    function openCustomLoadProfile(~,~)
        if string(loadProfileField.Value) ~= "Custom"
            return;
        end

        parentPos = fig.Position;
        parentCenter = [parentPos(1)+parentPos(3)/2, ...
                        parentPos(2)+parentPos(4)/2];

        monitorPos = get(groot,"MonitorPositions");
        if isempty(monitorPos)
            monitorPos = get(groot,"ScreenSize");
        end

        monIdx = 1;
        for kMon = 1:size(monitorPos,1)
            m = monitorPos(kMon,:);
            if parentCenter(1) >= m(1) && ...
               parentCenter(1) <= m(1)+m(3) && ...
               parentCenter(2) >= m(2) && ...
               parentCenter(2) <= m(2)+m(4)
                monIdx = kMon;
                break
            end
        end
        mon = monitorPos(monIdx,:);

        winW = min(1000,max(740,mon(3)-120));
        winH = min(580,max(460,mon(4)-150));
        winX = mon(1) + (mon(3)-winW)/2;
        winY = mon(2) + (mon(4)-winH)/2;

        loadFig = uifigure( ...
            "Name","ThermalPack — Custom Load Profile", ...
            "WindowStyle","modal", ...
            "Position",[winX winY winW winH], ...
            "CloseRequestFcn",@(srcFig,~)closeCustomLoadProfile(srcFig));

        movegui(loadFig,"onscreen");

        loadGrid = uigridlayout(loadFig,[3 6]);
        loadGrid.ColumnWidth = {'1x','1x',12,'1x','1x','1x'};
        loadGrid.RowHeight = {42,'1x',42};
        loadGrid.Padding = [16 16 16 16];
        loadGrid.RowSpacing = 10;
        loadGrid.ColumnSpacing = 10;

        hdr = uilabel(loadGrid, ...
            "Text","CUSTOM CURRENT PROFILE", ...
            "FontSize",18, ...
            "FontWeight","bold");
        hdr.Layout.Row = 1;
        hdr.Layout.Column = [1 6];

        profileTable = uitable(loadGrid, ...
            "Data",state.CustomCurrentProfile, ...
            "ColumnName",["Time (s)","Current (A)"], ...
            "ColumnEditable",[true true], ...
            "RowName",[], ...
            "CellEditCallback",@profileTableEdited);
        profileTable.Layout.Row = 2;
        profileTable.Layout.Column = [1 2];

        profileAxes = uiaxes(loadGrid);
        profileAxes.Layout.Row = 2;
        profileAxes.Layout.Column = [4 6];
        title(profileAxes,"Current Load Profile");
        xlabel(profileAxes,"Time (s)");
        ylabel(profileAxes,"Current (A)");
        grid(profileAxes,"on");

        addStepButton = uibutton(loadGrid,"push", ...
            "Text","+ ADD STEP", ...
            "ButtonPushedFcn",@addLoadStep);
        addStepButton.Layout.Row = 3;
        addStepButton.Layout.Column = 1;

        deletePointButton = uibutton(loadGrid,"push", ...
            "Text","DELETE LAST POINT", ...
            "ButtonPushedFcn",@deleteLoadPoint);
        deletePointButton.Layout.Row = 3;
        deletePointButton.Layout.Column = 2;

        applyButton = uibutton(loadGrid,"push", ...
            "Text","APPLY", ...
            "FontWeight","bold", ...
            "ButtonPushedFcn",@applyCustomLoadProfile);
        applyButton.Layout.Row = 3;
        applyButton.Layout.Column = [4 5];

        closeButton = uibutton(loadGrid,"push", ...
            "Text","CLOSE", ...
            "ButtonPushedFcn",@(srcBtn,~) ...
                closeCustomLoadProfile(ancestor(srcBtn,"figure")));
        closeButton.Layout.Row = 3;
        closeButton.Layout.Column = 6;

        updateLoadProfilePreview();

        function profileTableEdited(~,~)
            updateLoadProfilePreview();
        end

        function updateLoadProfilePreview()
            data = profileTable.Data;

            cla(profileAxes);
            title(profileAxes,"Current Load Profile");
            xlabel(profileAxes,"Time (s)");
            ylabel(profileAxes,"Current (A)");
            grid(profileAxes,"on");

            if isempty(data) || ~isnumeric(data) || size(data,2) ~= 2
                return;
            end

            validRows = all(isfinite(data),2);
            plotData = data(validRows,:);

            if isempty(plotData)
                return;
            end

            plot(profileAxes, ...
                plotData(:,1),plotData(:,2),"-o", ...
                "LineWidth",1.5, ...
                "MarkerSize",5);

            if numel(unique(plotData(:,1))) > 1
                xlim(profileAxes,[min(plotData(:,1)) max(plotData(:,1))]);
            end
        end

        function addLoadStep(~,~)
            data = profileTable.Data;

            if isempty(data) || ~isnumeric(data) || size(data,2) ~= 2
                data = [0 0];
            end

            profileTable.Data = [data; data(end,1), data(end,2)];
            updateLoadProfilePreview();
        end

        function deleteLoadPoint(~,~)
            data = profileTable.Data;
            if isnumeric(data) && size(data,1) > 2
                profileTable.Data = data(1:end-1,:);
                updateLoadProfilePreview();
            else
                uialert(loadFig, ...
                    "A custom profile must contain at least two points.", ...
                    "ThermalPack");
            end
        end

        function applyCustomLoadProfile(~,~)
            data = profileTable.Data;

            if ~isnumeric(data) || size(data,2) ~= 2 || size(data,1) < 2
                uialert(loadFig, ...
                    "Enter at least two numeric rows.", ...
                    "Invalid Load Profile");
                return;
            end

            if any(~isfinite(data),"all")
                uialert(loadFig, ...
                    "Time and current values must be finite numbers.", ...
                    "Invalid Load Profile");
                return;
            end

            if abs(data(1,1)) > 1e-12
                uialert(loadFig, ...
                    "The first time value must be 0 s.", ...
                    "Invalid Load Profile");
                return;
            end

            if any(data(:,1) < 0) || any(diff(data(:,1)) < 0)
                uialert(loadFig, ...
                    "Time values must be non-negative and non-decreasing.", ...
                    "Invalid Load Profile");
                return;
            end

            state.CustomCurrentProfile = double(data);
            state.LoadProfile = "Custom";
            state.LastValidLoadProfile = "Custom";
            loadProfileField.Value = "Custom";
            customLoadProfileButton.Enable = "on";

            statusLabel.Text = "Custom load profile applied";
        end
    end

    function closeCustomLoadProfile(windowToClose)
        if ~isempty(windowToClose) && isvalid(windowToClose)
            delete(windowToClose);
        end

        drawnow;

        if isvalid(fig)
            try
                focus(customLoadProfileButton);
            catch
                fig.Visible = "on";
                movegui(fig,"onscreen");
            end
        end
    end

    function openCoolingPlateSettings(~,~)
        parentPos = fig.Position;
        parentCenter = [parentPos(1)+parentPos(3)/2, ...
                        parentPos(2)+parentPos(4)/2];

        monitorPos = get(groot,"MonitorPositions");
        if isempty(monitorPos)
            monitorPos = get(groot,"ScreenSize");
        end

        monIdx = 1;
        for kMon = 1:size(monitorPos,1)
            m = monitorPos(kMon,:);
            if parentCenter(1) >= m(1) && ...
               parentCenter(1) <= m(1)+m(3) && ...
               parentCenter(2) >= m(2) && ...
               parentCenter(2) <= m(2)+m(4)
                monIdx = kMon;
                break
            end
        end
        mon = monitorPos(monIdx,:);

        winW = min(800,max(620,mon(3)-140));
        winH = min(720,max(600,mon(4)-150));
        winX = mon(1) + (mon(3)-winW)/2;
        winY = mon(2) + (mon(4)-winH)/2;

        plateFig = uifigure( ...
            "Name","ThermalPack — Cooling Plate Settings", ...
            "WindowStyle","modal", ...
            "Position",[winX winY winW winH], ...
            "CloseRequestFcn",@(srcFig,~)closeCoolingPlateSettings(srcFig));
        movegui(plateFig,"onscreen");

        pg = uigridlayout(plateFig,[18 2]);
        pg.ColumnWidth = {330,'1x'};
        pg.RowHeight = {44,32,36,36,36,32,36,36,36,36,36,32,36,36,36,36,36,44};
        pg.Padding = [18 18 18 18];
        pg.RowSpacing = 7;
        pg.ColumnSpacing = 10;
        pg.Scrollable = "on";

        hdr = uilabel(pg, ...
            "Text","COOLING PLATE SETTINGS", ...
            "FontSize",18, ...
            "FontWeight","bold");
        hdr.Layout.Row = 1;
        hdr.Layout.Column = [1 2];

        %% Interface
        interfaceHdr = uilabel(pg,"Text","INTERFACE","FontWeight","bold");
        interfaceHdr.Layout.Row = 2;
        interfaceHdr.Layout.Column = [1 2];

        connectivityLbl = uilabel(pg,"Text","Battery Connectivity");
        connectivityLbl.Layout.Row = 3;
        connectivityLbl.Layout.Column = 1;

        connectivityField = uidropdown(pg, ...
            "Items",["Single sided","Double sided — Coming Soon"], ...
            "Value","Single sided", ...
            "ValueChangedFcn",@connectivityChanged);
        connectivityField.Layout.Row = 3;
        connectivityField.Layout.Column = 2;

        pxLbl = uilabel(pg,"Text","Plate Partitions X");
        pxLbl.Layout.Row = 4;
        pxLbl.Layout.Column = 1;

        partitionXField = uispinner(pg, ...
            "Limits",[1 20], ...
            "Step",1, ...
            "Value",min(20,max(1,round(state.PlatePartitionsX))));
        partitionXField.Layout.Row = 4;
        partitionXField.Layout.Column = 2;

        pyLbl = uilabel(pg,"Text","Plate Partitions Y");
        pyLbl.Layout.Row = 5;
        pyLbl.Layout.Column = 1;

        partitionYField = uispinner(pg, ...
            "Limits",[1 20], ...
            "Step",1, ...
            "Value",min(20,max(1,round(state.PlatePartitionsY))));
        partitionYField.Layout.Row = 5;
        partitionYField.Layout.Column = 2;

        %% Plate material
        materialHdr = uilabel(pg,"Text","PLATE MATERIAL","FontWeight","bold");
        materialHdr.Layout.Row = 6;
        materialHdr.Layout.Column = [1 2];

        thLbl = uilabel(pg,"Text","Plate Thickness (mm)");
        thLbl.Layout.Row = 7;
        thLbl.Layout.Column = 1;

        thicknessField = uieditfield(pg,"numeric", ...
            "Value",state.PlateThickness_mm, ...
            "Limits",[0.001 Inf]);
        thicknessField.Layout.Row = 7;
        thicknessField.Layout.Column = 2;

        kLbl = uilabel(pg,"Text","Thermal Conductivity (W/mK)");
        kLbl.Layout.Row = 8;
        kLbl.Layout.Column = 1;

        plateConductivityField = uieditfield(pg,"numeric", ...
            "Value",state.PlateConductivity_W_mK, ...
            "Limits",[0 Inf]);
        plateConductivityField.Layout.Row = 8;
        plateConductivityField.Layout.Column = 2;

        rhoLbl = uilabel(pg,"Text","Density (kg/m³)");
        rhoLbl.Layout.Row = 9;
        rhoLbl.Layout.Column = 1;

        plateDensityField = uieditfield(pg,"numeric", ...
            "Value",state.PlateDensity_kg_m3, ...
            "Limits",[0.001 Inf]);
        plateDensityField.Layout.Row = 9;
        plateDensityField.Layout.Column = 2;

        cpLbl = uilabel(pg,"Text","Specific Heat (J/kgK)");
        cpLbl.Layout.Row = 10;
        cpLbl.Layout.Column = 1;

        plateCpField = uieditfield(pg,"numeric", ...
            "Value",state.PlateSpecificHeat_J_kgK, ...
            "Limits",[0.001 Inf]);
        plateCpField.Layout.Row = 10;
        plateCpField.Layout.Column = 2;

        tempLbl = uilabel(pg,"Text","Initial Plate Temperature (°C)");
        tempLbl.Layout.Row = 11;
        tempLbl.Layout.Column = 1;

        plateInitialTempField = uieditfield(pg,"numeric", ...
            "Value",state.InitialPlateTemperature_C, ...
            "Limits",[-273.14 Inf]);
        plateInitialTempField.Layout.Row = 11;
        plateInitialTempField.Layout.Column = 2;

        %% Channel design
        designHdr = uilabel(pg,"Text","CHANNEL DESIGN","FontWeight","bold");
        designHdr.Layout.Row = 12;
        designHdr.Layout.Column = [1 2];

        nChLbl = uilabel(pg,"Text","Number of Coolant Channels");
        nChLbl.Layout.Row = 13;
        nChLbl.Layout.Column = 1;

        channelsField = uispinner(pg, ...
            "Limits",[1 50], ...
            "Step",1, ...
            "Value",min(50,max(1,round(state.NumCoolantChannels))));
        channelsField.Layout.Row = 13;
        channelsField.Layout.Column = 2;

        orientLbl = uilabel(pg,"Text","Channel Orientation");
        orientLbl.Layout.Row = 14;
        orientLbl.Layout.Column = 1;

        orientationField = uidropdown(pg, ...
            "Items",["Channels along X axis","Channels along Y axis"], ...
            "Value",state.ChannelOrientation);
        orientationField.Layout.Row = 14;
        orientationField.Layout.Column = 2;

        hydLbl = uilabel(pg,"Text","Coolant Channel Hydraulic Diameter (mm)");
        hydLbl.Layout.Row = 15;
        hydLbl.Layout.Column = 1;

        hydraulicDiameterField = uieditfield(pg,"numeric", ...
            "Value",state.ChannelHydraulicDiameter_mm, ...
            "Limits",[0.001 Inf]);
        hydraulicDiameterField.Layout.Row = 15;
        hydraulicDiameterField.Layout.Column = 2;

        distLbl = uilabel(pg,"Text","Distributor Pipe Diameter (mm)");
        distLbl.Layout.Row = 16;
        distLbl.Layout.Column = 1;

        distributorDiameterField = uieditfield(pg,"numeric", ...
            "Value",state.DistributorDiameter_mm, ...
            "Limits",[0.001 Inf]);
        distributorDiameterField.Layout.Row = 16;
        distributorDiameterField.Layout.Column = 2;

        roughLbl = uilabel(pg,"Text","Channel / Distributor Roughness (mm)");
        roughLbl.Layout.Row = 17;
        roughLbl.Layout.Column = 1;

        roughnessField = uieditfield(pg,"numeric", ...
            "Value",state.ChannelRoughness_mm, ...
            "Limits",[0 Inf]);
        roughnessField.Layout.Row = 17;
        roughnessField.Layout.Column = 2;

        btnGrid = uigridlayout(pg,[1 2]);
        btnGrid.Layout.Row = 18;
        btnGrid.Layout.Column = [1 2];
        btnGrid.ColumnWidth = {'1x','1x'};
        btnGrid.Padding = [0 0 0 0];

        applyBtn = uibutton(btnGrid,"push", ...
            "Text","APPLY", ...
            "FontWeight","bold", ...
            "ButtonPushedFcn",@applyCoolingPlateSettings);
        applyBtn.Layout.Column = 1;

        closeBtn = uibutton(btnGrid,"push", ...
            "Text","CLOSE", ...
            "ButtonPushedFcn",@(srcBtn,~) ...
                closeCoolingPlateSettings(ancestor(srcBtn,"figure")));
        closeBtn.Layout.Column = 2;

        function connectivityChanged(~,~)
            if string(connectivityField.Value) ~= "Single sided"
                uialert(plateFig, ...
                    "Double-sided battery connectivity is coming soon.", ...
                    "ThermalPack");
                connectivityField.Value = "Single sided";
            end
        end

        function applyCoolingPlateSettings(~,~)
            state.PlateConnectivity = "Single sided";
            state.PlatePartitionsX = round(partitionXField.Value);
            state.PlatePartitionsY = round(partitionYField.Value);
            state.PlateThickness_mm = thicknessField.Value;
            state.PlateConductivity_W_mK = plateConductivityField.Value;
            state.PlateDensity_kg_m3 = plateDensityField.Value;
            state.PlateSpecificHeat_J_kgK = plateCpField.Value;
            state.InitialPlateTemperature_C = plateInitialTempField.Value;
            state.NumCoolantChannels = round(channelsField.Value);
            state.ChannelOrientation = string(orientationField.Value);
            state.ChannelHydraulicDiameter_mm = hydraulicDiameterField.Value;
            state.DistributorDiameter_mm = distributorDiameterField.Value;
            state.ChannelRoughness_mm = roughnessField.Value;

            applyCoolingPlateSettingsToBlock(plateBlock,state);

%% Keep the existing model variable used by the Parallel Channels
            % initial-temperature parameter synchronized.
            try
                mdlWks = get_param(mdl,"ModelWorkspace");
                assignin(mdlWks,"T_plate_K", ...
                    state.InitialPlateTemperature_C + 273.15);
            catch
            end

            save_system(mdl);

            statusLabel.Text = sprintf( ...
                "Cooling plate applied — %d channels, %s", ...
                state.NumCoolantChannels,state.ChannelOrientation);
        end
    end

    function closeCoolingPlateSettings(windowToClose)
        if ~isempty(windowToClose) && isvalid(windowToClose)
            delete(windowToClose);
        end

        drawnow;

        if isvalid(fig)
            try
                focus(coolingPlateSettingsButton);
            catch
                fig.Visible = "on";
                movegui(fig,"onscreen");
            end
        end
    end

    function openFlowSourceSettings(~,~)
        parentPos = fig.Position;
        parentCenter = [parentPos(1)+parentPos(3)/2, ...
                        parentPos(2)+parentPos(4)/2];

        monitorPos = get(groot,"MonitorPositions");
        if isempty(monitorPos)
            monitorPos = get(groot,"ScreenSize");
        end

        monIdx = 1;
        for kMon = 1:size(monitorPos,1)
            m = monitorPos(kMon,:);
            if parentCenter(1) >= m(1) && ...
               parentCenter(1) <= m(1)+m(3) && ...
               parentCenter(2) >= m(2) && ...
               parentCenter(2) <= m(2)+m(4)
                monIdx = kMon;
                break
            end
        end
        mon = monitorPos(monIdx,:);

        winW = min(680,max(540,mon(3)-140));
        winH = min(300,max(260,mon(4)-180));
        winX = mon(1) + (mon(3)-winW)/2;
        winY = mon(2) + (mon(4)-winH)/2;

        flowFig = uifigure( ...
            "Name","ThermalPack — Flow Source Settings", ...
            "WindowStyle","modal", ...
            "Position",[winX winY winW winH], ...
            "CloseRequestFcn",@(srcFig,~)closeFlowSourceSettings(srcFig));
        movegui(flowFig,"onscreen");

        fg = uigridlayout(flowFig,[4 2]);
        fg.ColumnWidth = {260,'1x'};
        fg.RowHeight = {46,40,40,44};
        fg.Padding = [18 18 18 18];
        fg.RowSpacing = 12;
        fg.ColumnSpacing = 10;

        hdr = uilabel(fg, ...
            "Text","FLOW SOURCE SETTINGS", ...
            "FontSize",18, ...
            "FontWeight","bold");
        hdr.Layout.Row = 1;
        hdr.Layout.Column = [1 2];

        sourceLbl = uilabel(fg,"Text","Source Type");
        sourceLbl.Layout.Row = 2;
        sourceLbl.Layout.Column = 1;

        sourceTypeField = uidropdown(fg, ...
            "Items",["Constant","Controlled — Coming Soon"], ...
            "Value","Constant", ...
            "ValueChangedFcn",@sourceTypeChanged);
        sourceTypeField.Layout.Row = 2;
        sourceTypeField.Layout.Column = 2;

        flowTypeLbl = uilabel(fg,"Text","Flow Rate Type");
        flowTypeLbl.Layout.Row = 3;
        flowTypeLbl.Layout.Column = 1;

        flowRateTypeField = uidropdown(fg, ...
            "Items",["Mass flow rate","Volumetric flow rate"], ...
            "Value",state.FlowRateType);
        flowRateTypeField.Layout.Row = 3;
        flowRateTypeField.Layout.Column = 2;

        btnGrid = uigridlayout(fg,[1 2]);
        btnGrid.Layout.Row = 4;
        btnGrid.Layout.Column = [1 2];
        btnGrid.ColumnWidth = {'1x','1x'};
        btnGrid.Padding = [0 0 0 0];

        applyBtn = uibutton(btnGrid,"push", ...
            "Text","APPLY", ...
            "FontWeight","bold", ...
            "ButtonPushedFcn",@applyFlowSourceSettings);
        applyBtn.Layout.Column = 1;

        closeBtn = uibutton(btnGrid,"push", ...
            "Text","CLOSE", ...
            "ButtonPushedFcn",@(srcBtn,~) ...
                closeFlowSourceSettings(ancestor(srcBtn,"figure")));
        closeBtn.Layout.Column = 2;

        function sourceTypeChanged(~,~)
            if string(sourceTypeField.Value) ~= "Constant"
                uialert(flowFig, ...
                    "Controlled flow source is coming soon.", ...
                    "ThermalPack");
                sourceTypeField.Value = "Constant";
            end
        end

        function applyFlowSourceSettings(~,~)
%% Save the currently displayed value in its existing units.
            if state.FlowRateType == "Mass flow rate"
                state.MassFlowRate_kg_s = flowField.Value;
            else
                state.VolumetricFlowRate_m3_s = flowField.Value;
            end

            state.FlowSourceType = "Constant";
            newType = string(flowRateTypeField.Value);
            state.FlowRateType = newType;

            if newType == "Mass flow rate"
                flowLabel.Text = "Coolant flow (kg/s)";
                flowField.Value = state.MassFlowRate_kg_s;
            else
                flowLabel.Text = "Coolant flow (m³/s)";
                flowField.Value = state.VolumetricFlowRate_m3_s;
            end

%% Apply immediately to the current working model when possible.
            flowSourceBlock = findFlowRateSourceBlock(mdl);
            if strlength(flowSourceBlock) > 0
                applyFlowSourceSettingsToBlock( ...
                    flowSourceBlock,state);
                save_system(mdl);
            end

            statusLabel.Text = sprintf( ...
                "Flow source: Constant / %s",state.FlowRateType);
        end
    end

    function closeFlowSourceSettings(windowToClose)
        if ~isempty(windowToClose) && isvalid(windowToClose)
            delete(windowToClose);
        end

        drawnow;

        if isvalid(fig)
            try
                focus(flowSourceSettingsButton);
            catch
                fig.Visible = "on";
                movegui(fig,"onscreen");
            end
        end
    end

    function openCoolantProperties(~,~)
        parentPos = fig.Position;
        parentCenter = [parentPos(1)+parentPos(3)/2, ...
                        parentPos(2)+parentPos(4)/2];

        monitorPos = get(groot,"MonitorPositions");
        if isempty(monitorPos)
            monitorPos = get(groot,"ScreenSize");
        end

        monIdx = 1;
        for kMon = 1:size(monitorPos,1)
            m = monitorPos(kMon,:);
            if parentCenter(1) >= m(1) && ...
               parentCenter(1) <= m(1)+m(3) && ...
               parentCenter(2) >= m(2) && ...
               parentCenter(2) <= m(2)+m(4)
                monIdx = kMon;
                break
            end
        end
        mon = monitorPos(monIdx,:);

        winW = min(720,max(560,mon(3)-140));
        winH = min(390,max(330,mon(4)-180));
        winX = mon(1) + (mon(3)-winW)/2;
        winY = mon(2) + (mon(4)-winH)/2;

        coolantFig = uifigure( ...
            "Name","ThermalPack — Coolant Properties", ...
            "WindowStyle","modal", ...
            "Position",[winX winY winW winH], ...
            "CloseRequestFcn",@(srcFig,~)closeCoolantProperties(srcFig));
        movegui(coolantFig,"onscreen");

        cg = uigridlayout(coolantFig,[5 2]);
        cg.ColumnWidth = {290,'1x'};
        cg.RowHeight = {46,40,40,40,44};
        cg.Padding = [18 18 18 18];
        cg.RowSpacing = 12;
        cg.ColumnSpacing = 10;

        hdr = uilabel(cg, ...
            "Text","COOLANT PROPERTIES", ...
            "FontSize",18, ...
            "FontWeight","bold");
        hdr.Layout.Row = 1;
        hdr.Layout.Column = [1 2];

        fluidLbl = uilabel(cg,"Text","Coolant Fluid");
        fluidLbl.Layout.Row = 2;
        fluidLbl.Layout.Column = 1;

        coolantFluidField = uidropdown(cg, ...
            "Items",[ ...
                "Water", ...
                "Seawater (MIT model)", ...
                "Ethylene glycol and water mixture", ...
                "Propylene glycol and water mixture", ...
                "Glycerol and water mixture", ...
                "Diesel Fuel", ...
                "Aviation fuel Jet-A", ...
                "SAE 5W-30"], ...
            "Value",state.CoolantFluid, ...
            "ValueChangedFcn",@coolantFluidChanged);
        coolantFluidField.Layout.Row = 2;
        coolantFluidField.Layout.Column = 2;

        concentrationTypeLbl = uilabel(cg,"Text","Concentration Type");
        concentrationTypeLbl.Layout.Row = 3;
        concentrationTypeLbl.Layout.Column = 1;

        concentrationTypeField = uidropdown(cg, ...
            "Items",["Volume fraction","Mass fraction"], ...
            "Value",state.CoolantConcentrationType, ...
            "ValueChangedFcn",@concentrationTypeChanged);
        concentrationTypeField.Layout.Row = 3;
        concentrationTypeField.Layout.Column = 2;

        concentrationLbl = uilabel(cg,"Text","Coolant Concentration");
        concentrationLbl.Layout.Row = 4;
        concentrationLbl.Layout.Column = 1;

        concentrationField = uieditfield(cg,"numeric", ...
            "Value",state.CoolantConcentration);
        concentrationField.Layout.Row = 4;
        concentrationField.Layout.Column = 2;

        btnGrid = uigridlayout(cg,[1 2]);
        btnGrid.Layout.Row = 5;
        btnGrid.Layout.Column = [1 2];
        btnGrid.ColumnWidth = {'1x','1x'};
        btnGrid.Padding = [0 0 0 0];

        applyBtn = uibutton(btnGrid,"push", ...
            "Text","APPLY", ...
            "FontWeight","bold", ...
            "ButtonPushedFcn",@applyCoolantProperties);
        applyBtn.Layout.Column = 1;

        closeBtn = uibutton(btnGrid,"push", ...
            "Text","CLOSE", ...
            "ButtonPushedFcn",@(srcBtn,~) ...
                closeCoolantProperties(ancestor(srcBtn,"figure")));
        closeBtn.Layout.Column = 2;

        updateCoolantControls();

        function coolantFluidChanged(~,~)
            updateCoolantControls();
        end

        function concentrationTypeChanged(~,~)
            updateCoolantControls();
        end

        function updateCoolantControls()
            fluid = string(coolantFluidField.Value);

            switch fluid
                case "Ethylene glycol and water mixture"
                    concentrationTypeField.Enable = "on";
                    concentrationLbl.Text = "Ethylene Glycol Fraction";
                    concentrationField.Enable = "on";

                    if string(concentrationTypeField.Value) == "Mass fraction"
                        concentrationField.Limits = [0 0.6];
                        if concentrationField.Value > 0.6
                            concentrationField.Value = 0.5;
                        end
                    else
                        concentrationField.Limits = [0 1];
                    end

                case "Propylene glycol and water mixture"
                    concentrationTypeField.Enable = "on";
                    concentrationLbl.Text = "Propylene Glycol Fraction";
                    concentrationField.Enable = "on";

                    if string(concentrationTypeField.Value) == "Mass fraction"
                        concentrationField.Limits = [0 0.6];
                        if concentrationField.Value > 0.6
                            concentrationField.Value = 0.5;
                        end
                    else
                        concentrationField.Limits = [0.1 0.6];
                        if concentrationField.Value < 0.1 || ...
                                concentrationField.Value > 0.6
                            concentrationField.Value = 0.5;
                        end
                    end

                case "Glycerol and water mixture"
                    concentrationTypeField.Value = "Mass fraction";
                    concentrationTypeField.Enable = "off";
                    concentrationLbl.Text = "Glycerol Mass Fraction";
                    concentrationField.Enable = "on";
                    concentrationField.Limits = [0 0.6];
                    if concentrationField.Value > 0.6
                        concentrationField.Value = 0.5;
                    end

                case "Seawater (MIT model)"
                    concentrationTypeField.Value = "Mass fraction";
                    concentrationTypeField.Enable = "off";
                    concentrationLbl.Text = "Dissolved Salt Mass Fraction";
                    concentrationField.Enable = "on";
                    concentrationField.Limits = [0 0.12];
                    if concentrationField.Value > 0.12
                        concentrationField.Value = 0.035;
                    end

                otherwise
                    concentrationTypeField.Enable = "off";
                    concentrationField.Enable = "off";
                    concentrationLbl.Text = "Coolant Concentration";
            end
        end

        function applyCoolantProperties(~,~)
            fluid = string(coolantFluidField.Value);
            concentrationType = string(concentrationTypeField.Value);
            concentration = concentrationField.Value;

            if concentrationField.Enable == "on" && ...
                    (~isfinite(concentration) || concentration < 0)
                uialert(coolantFig, ...
                    "Enter a valid coolant concentration.", ...
                    "Invalid Coolant Properties");
                return;
            end

            state.CoolantFluid = fluid;
            state.CoolantConcentrationType = concentrationType;
            state.CoolantConcentration = concentration;

%% Apply immediately to the current working model when possible.
            thermalLiquidBlock = findThermalLiquidPropertiesBlock(mdl);
            if strlength(thermalLiquidBlock) > 0
                applyCoolantPropertiesToBlock( ...
                    thermalLiquidBlock,state);
                save_system(mdl);
            end

            statusLabel.Text = sprintf( ...
                "Coolant applied — %s",state.CoolantFluid);
        end
    end

    function closeCoolantProperties(windowToClose)
        if ~isempty(windowToClose) && isvalid(windowToClose)
            delete(windowToClose);
        end

        drawnow;

        if isvalid(fig)
            try
                focus(coolantPropertiesButton);
            catch
                fig.Visible = "on";
                movegui(fig,"onscreen");
            end
        end
    end

    function openReservoirSettings(~,~)
        parentPos = fig.Position;
        parentCenter = [parentPos(1)+parentPos(3)/2, ...
                        parentPos(2)+parentPos(4)/2];

        monitorPos = get(groot,"MonitorPositions");
        if isempty(monitorPos)
            monitorPos = get(groot,"ScreenSize");
        end

        monIdx = 1;
        for kMon = 1:size(monitorPos,1)
            m = monitorPos(kMon,:);
            if parentCenter(1) >= m(1) && ...
               parentCenter(1) <= m(1)+m(3) && ...
               parentCenter(2) >= m(2) && ...
               parentCenter(2) <= m(2)+m(4)
                monIdx = kMon;
                break
            end
        end
        mon = monitorPos(monIdx,:);

        winW = min(700,max(540,mon(3)-140));
        winH = min(470,max(400,mon(4)-170));
        winX = mon(1) + (mon(3)-winW)/2;
        winY = mon(2) + (mon(4)-winH)/2;

        reservoirFig = uifigure( ...
            "Name","ThermalPack — Reservoir Settings", ...
            "WindowStyle","modal", ...
            "Position",[winX winY winW winH], ...
            "CloseRequestFcn",@(srcFig,~)closeReservoirSettings(srcFig));
        movegui(reservoirFig,"onscreen");

        rg = uigridlayout(reservoirFig,[7 2]);
        rg.ColumnWidth = {300,'1x'};
        rg.RowHeight = {44,38,38,38,38,'1x',42};
        rg.Padding = [16 16 16 16];
        rg.RowSpacing = 10;
        rg.ColumnSpacing = 10;

        hdr = uilabel(rg, ...
            "Text","THERMAL-LIQUID RESERVOIR", ...
            "FontSize",18, ...
            "FontWeight","bold");
        hdr.Layout.Row = 1;
        hdr.Layout.Column = [1 2];

        pSpecLbl = uilabel(rg,"Text","Reservoir Pressure Specification");
        pSpecLbl.Layout.Row = 2;
        pSpecLbl.Layout.Column = 1;

        pressureSpecField = uidropdown(rg, ...
            "Items",["Atmospheric pressure","Specified pressure"], ...
            "Value",state.ReservoirPressureSpecification, ...
            "ValueChangedFcn",@pressureSpecificationChanged);
        pressureSpecField.Layout.Row = 2;
        pressureSpecField.Layout.Column = 2;

        pLbl = uilabel(rg,"Text","Reservoir Pressure (Pa)");
        pLbl.Layout.Row = 3;
        pLbl.Layout.Column = 1;

        pressureField = uieditfield(rg,"numeric", ...
            "Value",state.ReservoirPressure_Pa, ...
            "Limits",[1 Inf]);
        pressureField.Layout.Row = 3;
        pressureField.Layout.Column = 2;

        tLbl = uilabel(rg,"Text","Reservoir / Coolant Inlet Temperature (°C)");
        tLbl.Layout.Row = 4;
        tLbl.Layout.Column = 1;

        reservoirTempField = uieditfield(rg,"numeric", ...
            "Value",tinField.Value, ...
            "Limits",[-273.14 Inf]);
        reservoirTempField.Layout.Row = 4;
        reservoirTempField.Layout.Column = 2;

        dLbl = uilabel(rg,"Text","Coolant Port Diameter (mm)");
        dLbl.Layout.Row = 5;
        dLbl.Layout.Column = 1;

        diameterPortField = uieditfield(rg,"numeric", ...
            "Value",state.CoolantPortDiameter_mm, ...
            "Limits",[0.001 Inf], ...
            "ValueChangedFcn",@updatePortArea);
        diameterPortField.Layout.Row = 5;
        diameterPortField.Layout.Column = 2;

        aLbl = uilabel(rg,"Text","Calculated Port Area (m²)");
        aLbl.Layout.Row = 6;
        aLbl.Layout.Column = 1;

        areaPortField = uieditfield(rg,"numeric", ...
            "Value",state.CoolantPortArea_m2, ...
            "Editable","off");
        areaPortField.Layout.Row = 6;
        areaPortField.Layout.Column = 2;

        btnGrid = uigridlayout(rg,[1 2]);
        btnGrid.Layout.Row = 7;
        btnGrid.Layout.Column = [1 2];
        btnGrid.ColumnWidth = {'1x','1x'};
        btnGrid.Padding = [0 0 0 0];

        applyReservoirBtn = uibutton(btnGrid,"push", ...
            "Text","APPLY", ...
            "FontWeight","bold", ...
            "ButtonPushedFcn",@applyReservoirSettings);
        applyReservoirBtn.Layout.Column = 1;

        closeReservoirBtn = uibutton(btnGrid,"push", ...
            "Text","CLOSE", ...
            "ButtonPushedFcn",@(srcBtn,~) ...
                closeReservoirSettings(ancestor(srcBtn,"figure")));
        closeReservoirBtn.Layout.Column = 2;

        pressureSpecificationChanged();
        updatePortArea();

        function pressureSpecificationChanged(~,~)
            if string(pressureSpecField.Value) == "Specified pressure"
                pressureField.Enable = "on";
            else
                pressureField.Enable = "off";
            end
        end

        function updatePortArea(~,~)
            d_m = diameterPortField.Value/1000;
            areaPortField.Value = pi*d_m^2/4;
        end

        function applyReservoirSettings(~,~)
            d_mm = diameterPortField.Value;
            p_Pa = pressureField.Value;
            temp_C = reservoirTempField.Value;

            if ~isfinite(d_mm) || d_mm <= 0
                uialert(reservoirFig, ...
                    "Coolant port diameter must be greater than zero.", ...
                    "Invalid Reservoir Setting");
                return;
            end

            if string(pressureSpecField.Value) == "Specified pressure" && ...
                    (~isfinite(p_Pa) || p_Pa <= 0)
                uialert(reservoirFig, ...
                    "Specified reservoir pressure must be greater than zero.", ...
                    "Invalid Reservoir Setting");
                return;
            end

            if ~isfinite(temp_C) || temp_C <= -273.15
                uialert(reservoirFig, ...
                    "Reservoir temperature must be above absolute zero.", ...
                    "Invalid Reservoir Setting");
                return;
            end

            state.ReservoirPressureSpecification = ...
                string(pressureSpecField.Value);
            state.ReservoirPressure_Pa = p_Pa;
            state.CoolantPortDiameter_mm = d_mm;
            state.CoolantPortArea_m2 = pi*(d_mm/1000)^2/4;

            tinField.Value = temp_C;

            statusLabel.Text = sprintf( ...
                "Reservoir applied — %.2f mm port", ...
                state.CoolantPortDiameter_mm);
        end
    end

    function closeReservoirSettings(windowToClose)
        if ~isempty(windowToClose) && isvalid(windowToClose)
            delete(windowToClose);
        end

        drawnow;

        if isvalid(fig)
            try
                focus(reservoirSettingsButton);
            catch
                fig.Visible = "on";
                movegui(fig,"onscreen");
            end
        end
    end

    function coolingModeChanged(~,~)
        mode = string(coolingPlateField.Value);

        if mode == "No Cooling Plate"
            coolantRField.Enable = "off";
            coolingModeNote.Text = sprintf( ...
                "No cooling approximation — effective Cell → plate Rth = %.0e K/W.", ...
                state.NoCoolingRth_K_W);
        else
            coolantRField.Enable = "on";
            coolingModeNote.Text = ...
                "Bottom plate active — Cell → plate Rth is applied.";
        end

        state.CoolingPlateMode = mode;
    end

    function interCellHeatChanged(~,~)
        if string(interCellHeatField.Value) == "Enabled"
            interCellRField.Enable = "on";
            interParallelRField.Enable = "on";
        else
            interCellRField.Enable = "off";
            interParallelRField.Enable = "off";
        end

        state.NeedsRebuild = true;
        statusLabel.Text = ...
            "Inter-cell thermal path changed — click REBUILD BATTERY";
    end

    function openAdvancedSettings(~,~)
%% Size and center the dialog on the SAME monitor as ThermalPack.
        parentPos = fig.Position;
        parentCenter = [parentPos(1)+parentPos(3)/2, ...
                        parentPos(2)+parentPos(4)/2];

        monitorPos = get(groot,"MonitorPositions");
        if isempty(monitorPos)
            monitorPos = get(groot,"ScreenSize");
        end

%% Choose the monitor containing the centre of the main app.
        monIdx = 1;
        for kMon = 1:size(monitorPos,1)
            m = monitorPos(kMon,:);
            if parentCenter(1) >= m(1) && ...
               parentCenter(1) <= m(1)+m(3) && ...
               parentCenter(2) >= m(2) && ...
               parentCenter(2) <= m(2)+m(4)
                monIdx = kMon;
                break
            end
        end
        mon = monitorPos(monIdx,:);

%% Leave margins for the OS menu/task bar and figure title bar.
        advW = min(760,max(560,mon(3)-100));
        advH = min(790,max(480,mon(4)-140));

        advX = mon(1) + (mon(3)-advW)/2;
        advY = mon(2) + (mon(4)-advH)/2;

        advFig = uifigure( ...
            "Name","ThermalPack — Advanced Settings", ...
            "WindowStyle","modal", ...
            "Position",[advX advY advW advH], ...
            "CloseRequestFcn",@(srcFig,~)closeAdvancedSettings(srcFig));

%% Final guard against title bars / desktop geometry placing any
        movegui(advFig,"onscreen");

        adv = uigridlayout(advFig,[37 2]);
        adv.ColumnWidth = {355,'1x'};
        adv.RowHeight = repmat({28},1,37);
        adv.RowHeight{1} = 40;
        adv.RowHeight{7} = 34;
        adv.RowHeight{15} = 34;
        adv.RowHeight{27} = 34;
        adv.RowHeight{30} = 34;
        adv.RowHeight{36} = '1x';
        adv.Padding = [18 18 18 18];
        adv.RowSpacing = 7;
        adv.Scrollable = "on";

        hdr = uilabel(adv, ...
            "Text","ADVANCED CELL PHYSICS", ...
            "FontSize",18, ...
            "FontWeight","bold");
        hdr.Layout.Row = 1;
        hdr.Layout.Column = [1 2];

        addDisabledAdvancedRow(adv,2,"Current Dependence","Disabled");
        addDisabledAdvancedRow(adv,3,"RC Dynamics","Disabled");
        addDisabledAdvancedRow(adv,4,"Hysteresis Model","Disabled");
        addDisabledAdvancedRow(adv,5,"Reversible Heat Model","Disabled");

        fidelityHdr = uilabel(adv, ...
            "Text","MODEL FIDELITY & ELECTRICAL SETTINGS", ...
            "FontWeight","bold");
        fidelityHdr.Layout.Row = 7;
        fidelityHdr.Layout.Column = [1 2];

        addDisabledAdvancedRow(adv,8,"Model Resolution","Detailed");
        addDisabledAdvancedRow(adv,9,"Cell Parameter Variation","Percent Deviation");
        addDisabledAdvancedRow(adv,10,"Series Grouping","Not Applicable — Detailed");
        addDisabledAdvancedRow(adv,11,"Parallel Grouping","Not Applicable — Detailed");
        addDisabledAdvancedRow(adv,12,"Non-Cell Resistance","Disabled");
        addDisabledAdvancedRow(adv,13,"Balancing Strategy","None");

        thermalHdr = uilabel(adv, ...
            "Text","THERMAL CONFIGURATION", ...
            "FontWeight","bold");
        thermalHdr.Layout.Row = 15;
        thermalHdr.Layout.Column = [1 2];

        addDisabledAdvancedRow(adv,16,"Inter-Cell Thermal Path","Main Panel Control");
        addDisabledAdvancedRow(adv,17,"Inter-Cell Radiative Thermal Path","Disabled");
        addDisabledAdvancedRow(adv,18,"Coolant Thermal Path","CellBasedThermalResistance");
        addDisabledAdvancedRow(adv,19,"Ambient Thermal Path","CellBasedThermalResistance");
        addDisabledAdvancedRow(adv,20,"Cooling Plate Block Path","External ThermalPack Plate");
        addDisabledAdvancedRow(adv,21,"Serpentine Cooling Plate","Disabled");
        addDisabledAdvancedRow(adv,22,"Serpentine Circumference Fraction","Not Applicable");
        addDisabledAdvancedRow(adv,23,"Serpentine Height Fraction","Not Applicable");
        addDisabledAdvancedRow(adv,24,"Side Thermal Nodes Xmin / Xmax","Disabled");
        addDisabledAdvancedRow(adv,25,"Side Thermal Nodes Ymin / Ymax","Disabled");

        hierarchyInfo = uilabel(adv, ...
            "Text",["Each ThermalPack setting is shown only once. " ...
            "The backend applies the same setting to the Parallel Assembly " ...
            "and Module objects wherever Battery Builder requires it."], ...
            "FontAngle","italic", ...
            "WordWrap","on");
        hierarchyInfo.Layout.Row = 26;
        hierarchyInfo.Layout.Column = [1 2];

        solverHdr = uilabel(adv, ...
            "Text","SOLVER SETTINGS", ...
            "FontWeight","bold");
        solverHdr.Layout.Row = 27;
        solverHdr.Layout.Column = [1 2];

        solverLbl = uilabel(adv,"Text","Solver");
        solverLbl.Layout.Row = 28;
        solverLbl.Layout.Column = 1;

        solverField = uidropdown(adv, ...
            "Items",["Auto","daessc","ode15s","ode23t"], ...
            "Value",state.Solver, ...
            "ValueChangedFcn",@solverChanged);
        solverField.Layout.Row = 28;
        solverField.Layout.Column = 2;

        futureHdr = uilabel(adv, ...
            "Text","FUTURE PHYSICS", ...
            "FontWeight","bold");
        futureHdr.Layout.Row = 30;
        futureHdr.Layout.Column = [1 2];

        addDisabledAdvancedRow(adv,31,"Cycling Aging","Future");
        addDisabledAdvancedRow(adv,32,"Calendar Aging","Future");
        addDisabledAdvancedRow(adv,33,"Self-Discharge","Future");
        addDisabledAdvancedRow(adv,34,"Thermal Runaway Model","Future");

        note = uitextarea(adv, ...
            "Editable","off", ...
            "Value",{'Advanced options are visible but intentionally inactive.'; ...
            'Model Resolution and Cell Parameter Variation are single ThermalPack settings.'; ...
            'Bottom cooling and Inter-cell Thermal Path are controlled on the main panel.'; ...
            'No Cooling Plate uses an effective Cell → plate Rth of 1e9 K/W.'});
        note.Layout.Row = 36;
        note.Layout.Column = [1 2];

        closeButton = uibutton(adv,"push", ...
            "Text","CLOSE", ...
            "ButtonPushedFcn",@(srcBtn,~)closeAdvancedSettings(ancestor(srcBtn,"figure")));
        closeButton.Layout.Row = 37;
        closeButton.Layout.Column = [1 2];
    end

    function solverChanged(src,~)
        state.Solver = string(src.Value);
        statusLabel.Text = sprintf("Solver selected: %s",state.Solver);
    end

    function closeAdvancedSettings(windowToClose)
%% The Advanced Settings figure is passed directly into this
        % callback. This avoids relying on a variable created inside the
        % openAdvancedSettings function's local workspace.
        if ~isempty(windowToClose) && isvalid(windowToClose)
            delete(windowToClose);
        end

        drawnow;

%% Return focus to the main ThermalPack app after the modal figure
        if isvalid(fig)
            try
                focus(advancedButton);
            catch
                fig.Visible = "on";
                movegui(fig,"onscreen");
            end
        end
    end

    function openCellNodalResults(~,~)
        if isempty(state.LastTrace) || isempty(state.LastKPI)
            uialert(fig, ...
                "Run a simulation first to generate cell and nodal results.", ...
                "ThermalPack");
            return;
        end

        T = state.LastTrace;

        nCells = size(T.Tcell_C,2);
        nNodes = size(T.nodal_C,2);

        peakCellAverage_C = NaN(nCells,1);
        peakNodal_C = NaN(nCells,1);
        maxAxialDeltaT_C = NaN(nCells,1);
        hottestNode = NaN(nCells,1);
        hottestTime_s = NaN(nCells,1);

        for c = 1:nCells
            peakCellAverage_C(c) = max(T.Tcell_C(:,c),[],"omitnan");

            nodeMatrix = squeeze(T.nodal_C(:,:,c));
            [peakNodal_C(c),linearIndex] = max(nodeMatrix,[],"all","omitnan","linear");

            if isfinite(peakNodal_C(c))
                [timeIdx,nodeIdx] = ind2sub(size(nodeMatrix),linearIndex);
                hottestNode(c) = nodeIdx;
                hottestTime_s(c) = T.tNodes(timeIdx);
            end

            axialSpread = max(nodeMatrix,[],2,"omitnan") - ...
                min(nodeMatrix,[],2,"omitnan");
            maxAxialDeltaT_C(c) = max(axialSpread,[],"omitnan");
        end

        resultTable = table( ...
            (1:nCells).', ...
            peakCellAverage_C, ...
            peakNodal_C, ...
            maxAxialDeltaT_C, ...
            hottestNode, ...
            hottestTime_s, ...
            'VariableNames',{ ...
            'Cell', ...
            'PeakCellAverage_C', ...
            'PeakNodal_C', ...
            'MaxAxialDeltaT_C', ...
            'HottestNode', ...
            'HottestTime_s'});

        parentPos = fig.Position;
        winW = min(1000,max(780,parentPos(3)-180));
        winH = min(650,max(480,parentPos(4)-180));
        winX = parentPos(1) + (parentPos(3)-winW)/2;
        winY = parentPos(2) + (parentPos(4)-winH)/2;

        resultsFig = uifigure( ...
            "Name","ThermalPack — Cell / Nodal Results", ...
            "WindowStyle","modal", ...
            "Position",[winX winY winW winH]);

        g = uigridlayout(resultsFig,[2 1]);
        g.RowHeight = {42,'1x'};
        g.Padding = [14 14 14 14];
        g.RowSpacing = 8;

        hdr = uilabel(g, ...
            "Text",sprintf( ...
            "CELL / NODAL RESULTS — %d cells × %d thermal nodes", ...
            nCells,nNodes), ...
            "FontSize",17, ...
            "FontWeight","bold");
        hdr.Layout.Row = 1;

        tbl = uitable(g, ...
            "Data",resultTable, ...
            "ColumnName",{ ...
            "Cell", ...
            "Peak cell avg (°C)", ...
            "Peak nodal (°C)", ...
            "Max axial ΔT (°C)", ...
            "Hottest node", ...
            "Hotspot time (s)"}, ...
            "RowName",[]);
        tbl.Layout.Row = 2;
        tbl.Layout.Column = 1;
    end

    function openSimulationSummary(~,~)
        if isempty(state.LastTrace) || isempty(state.LastKPI)
            uialert(fig, ...
                "Run a simulation first to generate the simulation summary.", ...
                "ThermalPack");
            return;
        end

        KPI = state.LastKPI;

        parentPos = fig.Position;
        winW = min(760,max(620,parentPos(3)-360));
        winH = min(650,max(500,parentPos(4)-180));
        winX = parentPos(1) + (parentPos(3)-winW)/2;
        winY = parentPos(2) + (parentPos(4)-winH)/2;

        summaryFig = uifigure( ...
            "Name","ThermalPack — Simulation Summary", ...
            "WindowStyle","modal", ...
            "Position",[winX winY winW winH]);

        g = uigridlayout(summaryFig,[2 1]);
        g.RowHeight = {42,'1x'};
        g.Padding = [14 14 14 14];
        g.RowSpacing = 8;

        hdr = uilabel(g, ...
            "Text","SIMULATION SUMMARY", ...
            "FontSize",18, ...
            "FontWeight","bold");
        hdr.Layout.Row = 1;

        if state.FlowRateType == "Volumetric flow rate"
            coolantFlowUnit = "m³/s";
        else
            coolantFlowUnit = "kg/s";
        end

        summaryLines = { ...
            sprintf('Architecture: %dP × %dS = %d cells', ...
                state.P,state.S,state.TotalCells); ...
            sprintf('Thermal nodes: %d per cell / %d total', ...
                round(nodesField.Value), ...
                state.TotalCells*round(nodesField.Value)); ...
            sprintf('Load profile: %s',state.LastCurrentProfileDescription); ...
            sprintf('Simulation time: %.0f s',stopField.Value); ...
            sprintf('Solver: %s',state.Solver); ...
            ' '; ...
            sprintf('Peak nodal temperature: %.3f °C',KPI.PeakTmaxNodal_C); ...
            sprintf('Maximum nodal ΔT: %.3f °C',KPI.MaxDeltaTNodal_C); ...
            sprintf('Hotspot: Cell %d / Node %d',KPI.WorstCell,KPI.WorstNode); ...
            sprintf('Hotspot time: %.3f s',KPI.WorstTime_s); ...
            sprintf('Safety margin: %.3f °C',KPI.MinSafetyMargin_C); ...
            sprintf('Thermal status: %s',KPI.WorstStatus); ...
            ' '; ...
            sprintf('Cooling plate: %s',state.CoolingPlateMode); ...
            sprintf('Coolant: %s',state.CoolantFluid); ...
            sprintf('Coolant inlet: %.3f °C',tinField.Value); ...
            sprintf('Coolant flow: %.6g %s', ...
                flowField.Value,coolantFlowUnit); ...
            sprintf('Ambient: %.3f °C',ambientField.Value); ...
            ' '; ...
            sprintf('Runtime: %.3f s',state.LastRuntime_s)};

        summaryBox = uitextarea(g, ...
            "Editable","off", ...
            "Value",summaryLines);
        summaryBox.Layout.Row = 2;
        summaryBox.Layout.Column = 1;
    end

    function refreshThermalAnimation(~,Trace)
%% ThermalPack custom height-resolved nodal 3D thermal map.
        pauseThermalAnimation();
%% Each physical cylindrical cell is divided axially into the same
        % number of segments as NumThermalModelsCell. Segment colours come
        % directly from Trace.nodal_C(time,node,cell).
        % X-Y placement comes from the rebuilt Battery Builder module's
        % ThermalNodes.Bottom locations captured during REBUILD BATTERY.

%% Remove the previous renderer cleanly.
        if ~isempty(thermalChart)
            try
                if isvalid(thermalChart)
                    delete(thermalChart);
                end
            catch
                try
                    delete(thermalChart);
                catch
                end
            end
        end

        thermalChart = [];
        thermalPatch = [];
        thermalColorBar = [];
        thermalFaceNodeIndex = [];
        thermalNodal_C = [];
        thermalNodalTime_s = [];
        thermalNodeCount = 0;
        thermalCellCount = 0;

        if isempty(state.GeneratedModuleObject)
            thermalMapPlaceholder.Visible = "on";
            thermalMapPlaceholder.Text = ...
                "Rebuild the battery once before running the simulation to enable the 3D nodal thermal map.";
            thermalMapStatus.Text = ...
                "Thermal results available — 3D geometry object not available";
            thermalTimeSlider.Enable = "off";
            return;
        end

        if ~isfield(Trace,"nodal_C") || isempty(Trace.nodal_C)
            thermalMapPlaceholder.Visible = "on";
            thermalMapPlaceholder.Text = ...
                "Nodal temperature data were not available in the simulation results.";
            thermalMapStatus.Text = ...
                "Simulation complete — nodal thermal data unavailable";
            thermalTimeSlider.Enable = "off";
            return;
        end

        try
            thermalNodal_C = double(Trace.nodal_C);
            thermalNodalTime_s = double(Trace.tNodes(:));

            thermalNodeCount = size(thermalNodal_C,2);
            thermalCellCount = size(thermalNodal_C,3);

            if thermalCellCount ~= state.TotalCells
                error("ThermalPack:NodalCellCount", ...
                    "Nodal result contains %d cells but the rebuilt module contains %d.", ...
                    thermalCellCount,state.TotalCells);
            end

%% Convert Battery Builder bottom thermal-node locations to N-by-2
            centres_m = thermalPackCellCentres( ...
                state.BatteryThermalNodeLocations, ...
                state.BatteryThermalNodeDimensions, ...
                thermalCellCount);

            if size(centres_m,1) ~= thermalCellCount
                error("ThermalPack:ThermalLocationCount", ...
                    "Could not resolve %d Battery Builder cell locations.", ...
                    thermalCellCount);
            end

            radius_m = state.Diameter_mm/2000;
            height_m = state.Height_mm/1000;

            if ~(isfinite(radius_m) && radius_m > 0 && ...
                    isfinite(height_m) && height_m > 0)
                error("ThermalPack:InvalidRenderGeometry", ...
                    "Cell diameter and height must be positive for 3D rendering.");
            end

%% Hide placeholder before creating the axes in the same 1x1 host.
            thermalMapPlaceholder.Visible = "off";

            thermalChart = uiaxes(thermalChartHost);
            thermalChart.Layout.Row = 1;
            thermalChart.Layout.Column = 1;
            hold(thermalChart,"on");

%% Bottom cooling plate geometry
            if state.CoolingPlateMode == "Bottom Cooling Plate"
                plateThickness_m = state.PlateThickness_mm/1000;

                if ~(isfinite(plateThickness_m) && plateThickness_m > 0)
                    plateThickness_m = 0.002;
                end

%% Cover the complete physical cell footprint and leave a
                plateBorder_m = max(0.001,0.5*state.InterCellGap_mm/1000);

                plateXMin = min(centres_m(:,1)-radius_m) - plateBorder_m;
                plateXMax = max(centres_m(:,1)+radius_m) + plateBorder_m;
                plateYMin = min(centres_m(:,2)-radius_m) - plateBorder_m;
                plateYMax = max(centres_m(:,2)+radius_m) + plateBorder_m;

                plateZTop = 0;
                plateZBottom = -plateThickness_m;

                plateVertices = [ ...
                    plateXMin plateYMin plateZBottom; ...
                    plateXMax plateYMin plateZBottom; ...
                    plateXMax plateYMax plateZBottom; ...
                    plateXMin plateYMax plateZBottom; ...
                    plateXMin plateYMin plateZTop; ...
                    plateXMax plateYMin plateZTop; ...
                    plateXMax plateYMax plateZTop; ...
                    plateXMin plateYMax plateZTop];

                plateFaces = [ ...
                    1 2 3 4; ... % bottom
                    5 8 7 6; ... % top
                    1 5 6 2; ...
                    2 6 7 3; ...
                    3 7 8 4; ...
                    4 8 5 1];

                patch(thermalChart, ...
                    "Vertices",plateVertices, ...
                    "Faces",plateFaces, ...
                    "FaceColor",[0.42 0.45 0.48], ...
                    "FaceAlpha",0.72, ...
                    "EdgeColor",[0.78 0.80 0.82], ...
                    "LineWidth",0.8);

%% Show the configured parallel-channel direction on the top
                nChannelsVisual = max(1,round(state.NumCoolantChannels));
                zGuide = plateZTop + max(1e-6,plateThickness_m*0.01);

                if state.ChannelOrientation == "Channels along Y axis"
                    xGuide = linspace(plateXMin,plateXMax,nChannelsVisual+2);
                    xGuide = xGuide(2:end-1);
                    for kGuide = 1:numel(xGuide)
                        plot3(thermalChart, ...
                            [xGuide(kGuide) xGuide(kGuide)], ...
                            [plateYMin plateYMax], ...
                            [zGuide zGuide], ...
                            "Color",[0.72 0.74 0.76], ...
                            "LineWidth",0.7);
                    end
                else
                    yGuide = linspace(plateYMin,plateYMax,nChannelsVisual+2);
                    yGuide = yGuide(2:end-1);
                    for kGuide = 1:numel(yGuide)
                        plot3(thermalChart, ...
                            [plateXMin plateXMax], ...
                            [yGuide(kGuide) yGuide(kGuide)], ...
                            [zGuide zGuide], ...
                            "Color",[0.72 0.74 0.76], ...
                            "LineWidth",0.7);
                    end
                end
            end

%% One combined patch is considerably faster than creating one
            % graphics object for every cell/node segment.
            angularDivisions = 24;
            theta = linspace(0,2*pi,angularDivisions+1);
            theta(end) = [];

            vertices = zeros(0,3);
            faces = zeros(0,4);
            faceNodeIndex = zeros(0,1);

%% Each axial segment contributes angularDivisions side faces.
            for c = 1:thermalCellCount
                xc = centres_m(c,1);
                yc = centres_m(c,2);

                for n = 1:thermalNodeCount
%% Simscape HDistributed node order runs opposite to the
                    % physical Z direction used by the ThermalPack renderer:
                    % Node 1 is at the TOP and Node N is nearest the BOTTOM
                    % cooling interface. Reverse only the display position;
                    % the raw simulation node numbering remains unchanged.
                    z0 = height_m*(thermalNodeCount-n)/thermalNodeCount;
                    z1 = height_m*(thermalNodeCount-n+1)/thermalNodeCount;

                    firstVertex = size(vertices,1) + 1;

                    lowerRing = [ ...
                        xc + radius_m*cos(theta(:)), ...
                        yc + radius_m*sin(theta(:)), ...
                        z0*ones(angularDivisions,1)];

                    upperRing = [ ...
                        xc + radius_m*cos(theta(:)), ...
                        yc + radius_m*sin(theta(:)), ...
                        z1*ones(angularDivisions,1)];

                    vertices = [vertices; lowerRing; upperRing]; %#ok<AGROW>

                    localFaces = zeros(angularDivisions,4);
                    for k = 1:angularDivisions
                        kp = mod(k,angularDivisions) + 1;

                        v1 = firstVertex + k - 1;
                        v2 = firstVertex + kp - 1;
                        v3 = firstVertex + angularDivisions + kp - 1;
                        v4 = firstVertex + angularDivisions + k - 1;

                        localFaces(k,:) = [v1 v2 v3 v4];
                    end

                    faces = [faces; localFaces]; %#ok<AGROW>
                    faceNodeIndex = [faceNodeIndex; ...
                        repmat(sub2ind([thermalNodeCount thermalCellCount], ...
                        n,c),angularDivisions,1)]; %#ok<AGROW>
                end
            end

%% Add one bottom cap and one top cap to each cell so the pack is
            capVertices = zeros(0,3);
            capFaces = zeros(0,3);
            capNodeIndex = zeros(0,1);

            for c = 1:thermalCellCount
                xc = centres_m(c,1);
                yc = centres_m(c,2);

                for isTop = 0:1
                    if isTop
                        zCap = height_m;
                        nCap = 1;
                    else
                        zCap = 0;
                        nCap = thermalNodeCount;
                    end

                    centreIdx = size(vertices,1) + size(capVertices,1) + 1;
                    ringStart = centreIdx + 1;

                    capVertices = [capVertices; ...
                        xc yc zCap; ...
                        xc + radius_m*cos(theta(:)), ...
                        yc + radius_m*sin(theta(:)), ...
                        zCap*ones(angularDivisions,1)]; %#ok<AGROW>

                    for k = 1:angularDivisions
                        kp = mod(k,angularDivisions) + 1;
                        capFaces(end+1,:) = [ ...
                            centreIdx, ...
                            ringStart + k - 1, ...
                            ringStart + kp - 1]; %#ok<AGROW>

                        capNodeIndex(end+1,1) = sub2ind( ...
                            [thermalNodeCount thermalCellCount],nCap,c); %#ok<AGROW>
                    end
                end
            end

%% Faces must have a common column count in a single patch. Pad
            capFaces4 = [capFaces capFaces(:,3)];
            faces = [faces; capFaces4];
            vertices = [vertices; capVertices];

            thermalFaceNodeIndex = [faceNodeIndex; capNodeIndex];

            initialTemps = squeeze(thermalNodal_C(1,:,:));
            initialTemps = initialTemps(:);

            thermalPatch = patch(thermalChart, ...
                "Vertices",vertices, ...
                "Faces",faces, ...
                "FaceVertexCData",initialTemps(thermalFaceNodeIndex), ...
                "FaceColor","flat", ...
                "EdgeColor","none");

%% Cell and nodal boundaries
            outlineTheta = linspace(0,2*pi,49);
            outlineX = [];
            outlineY = [];
            outlineZ = [];

            for c = 1:thermalCellCount
                xc = centres_m(c,1);
                yc = centres_m(c,2);

%% Horizontal rings: bottom, every nodal interface, and top.
                for nBoundary = 0:thermalNodeCount
                    zBoundary = height_m*nBoundary/thermalNodeCount;

                    outlineX = [outlineX, ...
                        xc + radius_m*cos(outlineTheta), NaN]; %#ok<AGROW>
                    outlineY = [outlineY, ...
                        yc + radius_m*sin(outlineTheta), NaN]; %#ok<AGROW>
                    outlineZ = [outlineZ, ...
                        zBoundary*ones(size(outlineTheta)), NaN]; %#ok<AGROW>
                end

%% Four vertical generator lines define the individual
                verticalAngles = [0 pi/2 pi 3*pi/2];
                for kEdge = 1:numel(verticalAngles)
                    xEdge = xc + radius_m*cos(verticalAngles(kEdge));
                    yEdge = yc + radius_m*sin(verticalAngles(kEdge));

                    outlineX = [outlineX, xEdge xEdge NaN]; %#ok<AGROW>
                    outlineY = [outlineY, yEdge yEdge NaN]; %#ok<AGROW>
                    outlineZ = [outlineZ, 0 height_m NaN]; %#ok<AGROW>
                end
            end

            plot3(thermalChart,outlineX,outlineY,outlineZ, ...
                "Color",[0.16 0.16 0.16], ...
                "LineWidth",0.65);

            hold(thermalChart,"off");

            axis(thermalChart,"equal");
            axis(thermalChart,"tight");
            grid(thermalChart,"on");
            box(thermalChart,"on");
            view(thermalChart,35,25);
            xlabel(thermalChart,"X (m)");
            ylabel(thermalChart,"Y (m)");
            zlabel(thermalChart,"Cell height (m)");
            if state.CoolingPlateMode == "Bottom Cooling Plate"
                title(thermalChart,sprintf( ...
                    "Height-Resolved Nodal Thermal Map — %d cells × %d nodes + bottom cooling plate", ...
                    thermalCellCount,thermalNodeCount));
            else
                title(thermalChart,sprintf( ...
                    "Height-Resolved Nodal Thermal Map — %d cells × %d nodes", ...
                    thermalCellCount,thermalNodeCount));
            end

%% Keep one colour scale for the complete simulation so the same
            % colour always represents the same temperature while scrubbing.
            allTemps = thermalNodal_C(isfinite(thermalNodal_C));
            if isempty(allTemps)
                cLim = [0 1];
            else
                tMin = min(allTemps);
                tMax = max(allTemps);
                if abs(tMax-tMin) < 1e-9
                    pad = max(0.5,abs(tMin)*0.01);
                    cLim = [tMin-pad tMax+pad];
                else
                    pad = 0.03*(tMax-tMin);
                    cLim = [tMin-pad tMax+pad];
                end
            end
            clim(thermalChart,cLim);

%% ThermalPack auto-scaled nodal temperature colour map
            % The colour limits are the actual nodal Tmin/Tmax for THIS
            % simulation, while the colour progression remains physically
            % intuitive and constant while scrubbing through time:
            % dark blue -> light blue -> light yellow -> dark yellow
            % -> light red -> dark red
            % This is an auto-contrast visualization. Therefore a given
            % colour does not represent the same absolute temperature in
            % different simulations; the colorbar provides the actual °C.
            anchorPosition = [0.00 0.20 0.40 0.60 0.80 1.00];

            anchorRGB = [ ...
                0.02 0.08 0.45; ... % dark blue
                0.35 0.72 1.00; ... % light blue
                1.00 0.94 0.55; ... % light yellow
                0.88 0.62 0.02; ... % dark yellow / amber
                1.00 0.48 0.42; ... % light red
                0.55 0.00 0.02];    % dark red

            cmapPosition = linspace(0,1,256);
            thermalPackMap = interp1( ...
                anchorPosition,anchorRGB,cmapPosition,"linear");

            thermalPackMap = min(max(thermalPackMap,0),1);
            colormap(thermalChart,thermalPackMap);

            thermalColorBar = colorbar(thermalChart);
            ylabel(thermalColorBar,"Nodal temperature (°C) — auto-scaled");

            tStart = thermalNodalTime_s(1);
            tEnd = thermalNodalTime_s(end);

            if ~isfinite(tStart)
                tStart = 0;
            end
            if ~isfinite(tEnd) || tEnd <= tStart
                tEnd = max(tStart+1,stopField.Value);
            end

            thermalPlaybackEnd_s = tEnd;
            thermalTimeSlider.Limits = [tStart tEnd];
            thermalTimeSlider.Value = tStart;
            thermalTimeSlider.Enable = "on";
            thermalPlayButton.Enable = "on";
            thermalPauseButton.Enable = "on";
            thermalStopButton.Enable = "on";
            thermalSpeedButton.Enable = "on";
            thermalPlaybackSpeed = 1;
            thermalSpeedButton.Text = "SPEED 1×";

            thermalMapStatus.Text = sprintf( ...
                "3D Nodal Thermal Map — %d cells × %d axial nodes — t = %.1f s", ...
                thermalCellCount,thermalNodeCount,tStart);

            rightTabs.SelectedTab = thermalMapTab;
            drawnow;

        catch MEthermal
            if ~isempty(thermalChart)
                try
                    if isvalid(thermalChart)
                        delete(thermalChart);
                    end
                catch
                end
            end
            thermalChart = [];
            thermalPatch = [];

            thermalMapPlaceholder.Visible = "on";
            thermalMapPlaceholder.Text = sprintf( ...
                "3D nodal thermal map could not be created:\n%s",MEthermal.message);
            thermalMapStatus.Text = ...
                "Simulation complete — nodal thermal renderer unavailable";
            thermalTimeSlider.Enable = "off";
            thermalPlayButton.Enable = "off";
            thermalPauseButton.Enable = "off";
            thermalStopButton.Enable = "off";
            thermalSpeedButton.Enable = "off";
        end
    end

    function playThermalAnimation(~,~)
        if isempty(thermalPatch) || isempty(thermalNodalTime_s) || ...
                thermalTimeSlider.Enable == "off"
            return;
        end

        lim = thermalTimeSlider.Limits;

%% Starting PLAY at the end begins a fresh replay.
        if thermalTimeSlider.Value >= lim(2) - ...
                max(eps(lim(2)),1e-9)
            setThermalPlaybackTime(lim(1));
        end

        if isempty(thermalPlaybackTimer) || ...
                ~isvalid(thermalPlaybackTimer)
            thermalPlaybackTimer = timer( ...
                "ExecutionMode","fixedSpacing", ...
                "Period",thermalPlaybackTimerPeriod_s, ...
                "BusyMode","drop", ...
                "TimerFcn",@thermalPlaybackTick);
        end

        if strcmp(thermalPlaybackTimer.Running,"off")
            start(thermalPlaybackTimer);
        end
    end

    function pauseThermalAnimation(~,~)
        if ~isempty(thermalPlaybackTimer)
            try
                if isvalid(thermalPlaybackTimer) && ...
                        strcmp(thermalPlaybackTimer.Running,"on")
                    stop(thermalPlaybackTimer);
                end
            catch
            end
        end
    end

    function stopThermalAnimation(~,~)
        pauseThermalAnimation();

        if ~isempty(thermalNodalTime_s) && ...
                thermalTimeSlider.Enable == "on"
            setThermalPlaybackTime(thermalTimeSlider.Limits(1));
        end
    end

    function increaseThermalPlaybackSpeed(~,~)
        currentIndex = find(thermalPlaybackSpeeds == ...
            thermalPlaybackSpeed,1);

        if isempty(currentIndex)
            currentIndex = 1;
        end

        nextIndex = currentIndex + 1;
        if nextIndex > numel(thermalPlaybackSpeeds)
            nextIndex = 1;
        end

        thermalPlaybackSpeed = thermalPlaybackSpeeds(nextIndex);
        thermalSpeedButton.Text = sprintf( ...
            "SPEED %g×",thermalPlaybackSpeed);
    end

    function thermalPlaybackTick(~,~)
        if isempty(thermalPatch) || isempty(thermalNodalTime_s) || ...
                ~isvalid(fig)
            pauseThermalAnimation();
            return;
        end

        lim = thermalTimeSlider.Limits;
        span = lim(2)-lim(1);

        if ~isfinite(span) || span <= 0
            pauseThermalAnimation();
            return;
        end

%% At 1× the complete simulation replays in approximately 30 s.
        increment = span * thermalPlaybackTimerPeriod_s / ...
            thermalPlaybackBaseDuration_s * thermalPlaybackSpeed;

        nextValue = thermalTimeSlider.Value + increment;

        if nextValue >= lim(2)
            setThermalPlaybackTime(lim(2));
            pauseThermalAnimation();
        else
            setThermalPlaybackTime(nextValue);
        end
    end

    function closeThermalPackApp(src,~)
        pauseThermalAnimation();

        if ~isempty(thermalPlaybackTimer)
            try
                if isvalid(thermalPlaybackTimer)
                    delete(thermalPlaybackTimer);
                end
            catch
            end
        end

        thermalPlaybackTimer = [];

        if ~isempty(src) && isvalid(src)
            delete(src);
        end
    end

    function thermalSliderChanging(~,evt)
        setThermalPlaybackTime(evt.Value);
    end

    function thermalSliderChanged(src,~)
        setThermalPlaybackTime(src.Value);
    end

    function setThermalPlaybackTime(tValue)
        if isempty(thermalPatch) || isempty(thermalNodal_C) || ...
                isempty(thermalNodalTime_s)
            return;
        end

        lim = thermalTimeSlider.Limits;
        tValue = min(max(double(tValue),lim(1)),lim(2));

%% Use the nearest solver/logged thermal sample to avoid inventing a
        % temperature field between Simscape time points.
        [~,timeIndex] = min(abs(thermalNodalTime_s-tValue));

        nodalAtTime = squeeze(thermalNodal_C(timeIndex,:,:));
        nodalAtTime = nodalAtTime(:);

        try
            thermalPatch.FaceVertexCData = ...
                nodalAtTime(thermalFaceNodeIndex);
        catch
            return;
        end

        actualTime = thermalNodalTime_s(timeIndex);
        thermalTimeSlider.Value = tValue;
        thermalMapStatus.Text = sprintf( ...
            "3D Nodal Thermal Map — %d cells × %d axial nodes — t = %.1f s", ...
            thermalCellCount,thermalNodeCount,actualTime);

        drawnow limitrate;
    end

    function centres_m = thermalPackCellCentres(locations,dimensions,N)
%% Resolve Battery Builder ThermalNodes.Bottom geometry into N X-Y
        % centre coordinates. The exact field orientation has varied across
        % releases, so this intentionally accepts N×2, 2×N and N×3 forms.

        centres_m = [];

        loc = [];
        try
            loc = double(locations);
        catch
            try
                loc = value(locations,"m");
            catch
            end
        end

        dims = [];
        try
            dims = double(dimensions);
        catch
            try
                dims = value(dimensions,"m");
            catch
            end
        end

        if ~isempty(loc)
            loc = squeeze(loc);

            if ismatrix(loc) && size(loc,1) == N && size(loc,2) >= 2
                centres_m = loc(:,1:2);
            elseif ismatrix(loc) && size(loc,2) == N && size(loc,1) >= 2
                centres_m = loc(1:2,:).';
            end
        end

%% Thermal-node Locations may describe a rectangle origin rather than
        % its centre. When compatible node dimensions are available, shift by
        % half the X-Y dimensions. A uniform shift does not alter spacing,
        % while this keeps the custom renderer aligned with the plate geometry.
        if ~isempty(centres_m) && ~isempty(dims)
            dims = squeeze(dims);
            if ismatrix(dims) && size(dims,1) == N && size(dims,2) >= 2
                nodeDims = dims(:,1:2);
            elseif ismatrix(dims) && size(dims,2) == N && size(dims,1) >= 2
                nodeDims = dims(1:2,:).';
            else
                nodeDims = [];
            end

            if ~isempty(nodeDims)
%% Only apply the origin-to-centre shift when all dimensions
                if all(isfinite(nodeDims),"all") && all(nodeDims > 0,"all")
                    centres_m = centres_m + 0.5*nodeDims;
                end
            end
        end

        if ~isempty(centres_m) && ...
                size(centres_m,1) == N && all(isfinite(centres_m),"all")
            return;
        end

%% Conservative fallback using the already-confirmed ThermalPack UI
        P = state.P;
        S = state.S;
        rows = max(1,min(state.Rows,P));
        cellPitch = state.Diameter_mm/1000 + state.InterCellGap_mm/1000;
        assemblyPitch = ...
            ceil(P/rows)*cellPitch + state.InterAssemblyGap_mm/1000;

        centres_m = zeros(N,2);
        idx = 1;

        for s = 1:S
            for p = 1:P
                row = mod(p-1,rows);
                col = floor((p-1)/rows);

                if state.ParallelAssemblyStackingAxis == "Y"
                    localXY = [row*cellPitch col*cellPitch];
                else
                    localXY = [col*cellPitch row*cellPitch];
                end

                if state.ModuleStackingAxis == "X"
                    offsetXY = [(s-1)*assemblyPitch 0];
                else
                    offsetXY = [0 (s-1)*assemblyPitch];
                end

                centres_m(idx,:) = localXY + offsetXY;
                idx = idx + 1;
            end
        end
    end

    function refreshBatteryGeometry(moduleObj,P,S,N)
%% Recreate the BatteryChart so the visualization always matches the

        if ~isempty(geometryChart)
            try
                if isvalid(geometryChart)
                    delete(geometryChart);
                end
            catch
                try
                    delete(geometryChart);
                catch
                end
            end
        end

        geometryChart = [];

        try
            geometryPlaceholder.Visible = "off";

            geometryChart = batteryChart(geometryGrid,moduleObj);
            geometryChart.Layout.Row = 2;
            geometryChart.Layout.Column = 1;

            try
                geometryChart.AxesVisible = "on";
            catch
            end

            try
                geometryChart.SimulationStrategyVisible = "off";
            catch
            end

            try
                geometryChart.setDefaultLabels;
            catch
            end

            geometryStatus.Text = sprintf( ...
                "3D Battery Geometry — %dP × %dS = %d cells",P,S,N);

%% Show the geometry immediately after a successful rebuild.
            rightTabs.SelectedTab = geometryTab;
            drawnow;

        catch MEgeom
            geometryPlaceholder.Visible = "on";
            geometryPlaceholder.Text = sprintf( ...
                "3D geometry could not be rendered:\\n%s",MEgeom.message);
            geometryStatus.Text = "Battery rebuilt — geometry renderer unavailable";
        end
    end

    function rebuildBattery(~,~)
        rebuildButton.Enable = "off";
        runButton.Enable = "off";

        try
            P = round(parallelField.Value);
            S = round(seriesField.Value);
            Rows = round(rowsField.Value);
            Topology = string(topologyField.Value);
            ParallelAssemblyStackingAxis = string(parallelStackingAxisField.Value);
            ModuleStackingAxis = string(moduleStackingAxisField.Value);
            MassFactor = massFactorField.Value;
            CoolingPlateMode = string(coolingPlateField.Value);
            InterCellHeatTransfer = string(interCellHeatField.Value);
            N = P*S;

            if P < 1 || P >= 150 || S < 1 || S >= 150
                error("P and S must each be integers between 1 and 149.");
            end

            if Rows < 1 || Rows >= 50
                error("Rows must be an integer between 1 and 49.");
            end

%% Battery Builder requires Rows < NumParallelCells for
            % multi-cell parallel assemblies. A single-cell assembly uses
            % the default single row.
            if P > 1 && Rows >= P
                error("Rows must be less than the number of parallel cells P.");
            elseif P == 1 && Rows ~= 1
                error("For P = 1, Rows must be 1.");
            end

            if MassFactor < 1
                error("Mass factor must be greater than or equal to 1.");
            end

            if InterCellHeatTransfer == "Enabled"
                interCellPathState = "on";
            else
                interCellPathState = "off";
            end

            if CoolingPlateMode == "No Cooling Plate"
                effectiveCoolantR_K_W = state.NoCoolingRth_K_W;
            else
                effectiveCoolantR_K_W = coolantRField.Value;
            end

%% Single ThermalPack-level configuration values.
            modelResolutionSetting = "Detailed";
            cellVariationSetting = "PercentDeviation";
            coolantThermalPathSetting = "CellBasedThermalResistance";
            ambientThermalPathSetting = "CellBasedThermalResistance";

            if N > 500
                answer = uiconfirm(fig, ...
                    sprintf(["You selected %d detailed cell models.\n" ...
                    "Compilation and simulation can become very slow.\n\nContinue?"],N), ...
                    "Large Detailed Battery", ...
                    "Options",["Continue","Cancel"], ...
                    "DefaultOption","Cancel", ...
                    "CancelOption","Cancel");
                if answer == "Cancel"
                    statusLabel.Text = "Rebuild cancelled";
                    rebuildButton.Enable = "on";
                    runButton.Enable = "on";
                    return;
                end
            end

            statusLabel.Text = sprintf( ...
                "Building %d-cell cylindrical module (%dP × %dS)...",N,P,S);
            drawnow;

            height_m = heightField.Value/1000;
            radius_m = diameterField.Value/2000;
            cellGap_m = cellGapField.Value/1000;
            assemblyGap_m = assemblyGapField.Value/1000;

            %% Create Battery Builder objects
            cellModelOptions = batteryCellModelBlock( ...
                "batt_lib/Cells/Battery Equivalent Circuit");

%% R2026a Battery Equivalent Circuit option for the distributed
            % 1-D thermal model.
            try
                cellModelOptions.BlockParameters.ThermalModel = ...
                    "HeightDistributedMass";
            catch
                cellModelOptions.BlockParameters.ThermalModel = ...
                    "simscape.battery.enum.cells.BatteryThermalModel.HeightDistributedMass";
            end

            geometry = batteryCylindricalGeometry( ...
                simscape.Value(height_m,"m"), ...
                simscape.Value(radius_m,"m"));

            cellObj = batteryCell(geometry,cellModelOptions);
            cellObj.Name = "Cylindrical_Cell";
            cellObj.Capacity = simscape.Value(capacityField.Value,"A*hr");
            try
                cellObj.Mass = simscape.Value(massField.Value,"kg");
            catch
            end
            try
                cellObj.Energy = simscape.Value(energyField.Value,"W*hr");
            catch
            end
            cellObj.StackingAxis = ParallelAssemblyStackingAxis;

%% One physical row containing P cells along Y. This reproduces
            pAssembly = batteryParallelAssembly(cellObj,P);
            pAssembly.Name = "Cylindrical_Cell_Assembly";
            pAssembly.Topology = Topology;
            pAssembly.Rows = Rows;
            pAssembly.StackingAxis = ParallelAssemblyStackingAxis;
            pAssembly.InterCellGap = simscape.Value(cellGap_m,"m");
            pAssembly.ModelResolution = modelResolutionSetting;
%% One ThermalPack setting is propagated to both hierarchy
            pAssembly.InterCellThermalPath = interCellPathState;

            moduleObj = batteryModule(pAssembly,S);
            moduleObj.Name = "Cylindrical_Cell_Module_Test";
            moduleObj.StackingAxis = ModuleStackingAxis;
            moduleObj.InterParallelAssemblyGap = ...
                simscape.Value(assemblyGap_m,"m");
            moduleObj.ModelResolution = modelResolutionSetting;
            moduleObj.MassFactor = MassFactor;

%% Thermal architecture matching ThermalPack:
            moduleObj.AmbientThermalPath = ambientThermalPathSetting;
            moduleObj.CoolantThermalPath = coolantThermalPathSetting;
            moduleObj.CoolingPlate = "Bottom";
            moduleObj.CoolingPlateBlockPath = "None";
            moduleObj.InterCellThermalPath = interCellPathState;
            moduleObj.CellParameterVariation = cellVariationSetting;

            %% Read bottom thermal-node geometry BEFORE build
            thermalNodes = moduleObj.ThermalNodes.Bottom;
            numThermalNodes = thermalNodes.NumNodes;

            if isfield(thermalNodes,"Locations")
                thermalLocations = thermalNodes.Locations;
            elseif isfield(thermalNodes,"Location")
                thermalLocations = thermalNodes.Location;
            else
                error("ThermalNodes.Bottom does not contain Locations/Location.");
            end

            thermalDimensions = thermalNodes.Dimensions;

            if numThermalNodes ~= N
                warning("ThermalPack:NodeCount", ...
                    ["Expected %d bottom thermal nodes but Battery Builder " ...
                     "reported %d."],N,numThermalNodes);
            end

            %% Generate unique Simscape Battery library
            generatedDir = fullfile(pwd,"ThermalPack_Generated");
            if ~isfolder(generatedDir)
                mkdir(generatedDir);
            end
            addpath(generatedDir);

            stamp = string(datetime("now","Format","yyyyMMdd_HHmmss"));
            libName = "ThermalPack_Cyl_" + P + "P_" + S + "S_" + stamp;

            statusLabel.Text = "Running buildBattery / Simscape compilation...";
            drawnow;

            buildBattery(moduleObj, ...
                LibraryName=libName, ...
                Directory=generatedDir, ...
                MaskParameters="NumericValues", ...
                Verbose="on");

            libModel = libName + "_lib";
            load_system(libModel);

            newSource = libModel + "/Cylindrical_Cell_Module_Test";
            if getSimulinkBlockHandle(newSource) <= 0
                topBlocks = string(find_system(libModel, ...
                    "SearchDepth",1,"Type","Block"));
                candidate = topBlocks(contains(topBlocks, ...
                    "Cylindrical_Cell_Module_Test"));

                if isempty(candidate)
                    error(["Generated module block could not be located in " ...
                        char(libModel) "."]);
                end
                newSource = candidate(1);
            end

            %% Backup working model before block replacement
            backupDir = fullfile(pwd,"ThermalPack_Backups");
            if ~isfolder(backupDir)
                mkdir(backupDir);
            end
            backupFile = fullfile(backupDir, ...
                mdl + "_before_rebuild_" + stamp + ".slx");
            save_system(mdl,backupFile);

            %% Capture and detach the four physical battery connections
            % R2026a provides simscape.connectedPorts/removeConnection/
            % addConnection. This is safer than relying on replace_block to
            % preserve Simscape conserving lines, especially when a newly
            % generated block has different geometry or port positions.
            % removeConnection removes only the branch leading to the
            % battery port. Other members of a branched physical network
            % remain connected.
            batteryPortNames = ["AmbH","p","n","BottomExtClnt"];
            savedConnections = struct;

%% Use a numeric block handle for the R2026a Simscape
            % connection APIs. Generated Simscape Reference blocks can be
            % resolved by Simulink while connectedPorts rejects the string
            % path in some model/link states.
            hBattery = getSimulinkBlockHandle(char(batteryBlock),true);

            if isempty(hBattery) || hBattery <= 0
                error("ThermalPack:BatteryHandleInvalid", ...
                    "Could not obtain a valid handle for %s.",batteryBlock);
            end

            for kPort = 1:numel(batteryPortNames)
                portName = batteryPortNames(kPort);

                try
                    connected = simscape.connectedPorts( ...
                        hBattery,portName);
                catch MEconn
                    error("ThermalPack:ConnectionReadFailed", ...
                        "Could not read connection for battery port %s:\n%s", ...
                        portName,MEconn.message);
                end

                if isempty(connected)
                    error("ThermalPack:BatteryPortDisconnected", ...
                        ["Battery port '%s' is already disconnected in the " ...
                         "working model. Start from a clean ThermalPack UI " ...
                         "working copy."],portName);
                end

                savedConnections.(char(portName)) = connected;

                simscape.removeConnection(hBattery,portName);
            end

            %% Replace only the now-disconnected generated battery block
            if ~bdIsLoaded(mdl)
                load_system(mdl);
            end

            oldBlockName = get_param(batteryBlock,"Name");

            replacedBlocks = replace_block(char(mdl), ...
                "SearchDepth",1, ...
                "Name",char(oldBlockName), ...
                char(newSource), ...
                "noprompt");

            if isempty(replacedBlocks)
                error("ThermalPack:BatteryReplacementFailed", ...
                    "No battery block was replaced in %s.",mdl);
            end

            if getSimulinkBlockHandle(batteryBlock) <= 0
                error("ThermalPack:BatteryReplacementFailed", ...
                    "Battery replacement did not preserve the expected block path.");
            end

            %% Verify expected ports exist on the generated module
            hBatteryNew = getSimulinkBlockHandle(char(batteryBlock),true);

            if isempty(hBatteryNew) || hBatteryNew <= 0
                error("ThermalPack:NewBatteryHandleInvalid", ...
                    "Could not obtain a valid handle for the rebuilt battery block.");
            end

            generatedPortInfo = simscape.connectionPortProperties(hBatteryNew);
            generatedPortNames = strings(1,numel(generatedPortInfo));

            for kInfo = 1:numel(generatedPortInfo)
                generatedPortNames(kInfo) = string(generatedPortInfo(kInfo).Name);
            end

            for kPort = 1:numel(batteryPortNames)
                portName = batteryPortNames(kPort);

                if ~any(generatedPortNames == portName)
                    error("ThermalPack:GeneratedPortMissing", ...
                        ["The generated battery does not expose the required " ...
                         "physical port '%s'. Available ports: %s"], ...
                        portName,strjoin(generatedPortNames,", "));
                end
            end

            %% Restore physical connections by port NAME
            % For a branched network, connectedPorts can return more than
            % one connected port. After removeConnection, those other ports
            % remain connected to each other, so reconnecting to any one of
            % them restores the battery to the entire branch.
            for kPort = 1:numel(batteryPortNames)
                portName = batteryPortNames(kPort);
                previous = savedConnections.(char(portName));

                simscape.addConnection( ...
                    hBatteryNew,portName, ...
                    previous(1).Block,previous(1).PortName, ...
                    "autorouting","smart");
            end

            %% Verify every battery physical port is connected again
            for kPort = 1:numel(batteryPortNames)
                portName = batteryPortNames(kPort);
                restored = simscape.connectedPorts(hBatteryNew,portName);

                if isempty(restored)
                    error("ThermalPack:ConnectionRestoreFailed", ...
                        "Battery port '%s' was not reconnected.",portName);
                end
            end

            %% Parameterize generated module
            % FIRST restore the original v2_2 cell physics exactly:
            % lookup tables, breakpoints, R0 table, initialization modes,
            % and original per-cell deviation pattern.
            applyMasterBatteryParameters( ...
                batteryBlock,masterBatteryParams,N,S);

%% THEN apply only the parameters intentionally exposed in the UI.
            safeSetBlockParam(batteryBlock,"BatteryCapacityCell", ...
                num2str(capacityField.Value,16));
            safeSetBlockParam(batteryBlock,"NumThermalModelsCell", ...
                num2str(round(nodesField.Value)));
            safeSetBlockParam(batteryBlock,"BatteryThermalMassCell", ...
                num2str(thermalMassField.Value,16));
            safeSetBlockParam(batteryBlock,"ThermalConductivityZCell", ...
                num2str(conductivityField.Value,16));
            safeSetBlockParam(batteryBlock,"CrossSectionalAreaXYCell", ...
                num2str(thermalAreaField.Value,16));
            safeSetBlockParam(batteryBlock,"HeightCell", ...
                num2str(height_m,16));

%% Apply ThermalPack cell electrical data and per-cell variation.
            state.R0Deviation_pct = resizeNumericVector( ...
                state.R0Deviation_pct,N,0);
            state.ThermalMassDeviation_pct = resizeNumericVector( ...
                state.ThermalMassDeviation_pct,N,0);
            state.ThermalConductivityDeviation_pct = resizeNumericVector( ...
                state.ThermalConductivityDeviation_pct,N,0);

            applyCellElectricalDataToBlock(batteryBlock,state,N);

%% Initial cell temperature is independent from ambient/coolant.
            state.InitialCellTemperature_C = initialCellTempField.Value;
            safeSetBlockParam(batteryBlock,"batteryTemperature", ...
                sprintf("repmat(%.16g,%d,1)", ...
                initialCellTempField.Value + 273.15,N));

            safeSetBlockParam(batteryBlock,"CoolantResistance", ...
                num2str(effectiveCoolantR_K_W,16));
            safeSetBlockParam(batteryBlock,"AmbientResistance", ...
                num2str(ambientRField.Value,16));
            if InterCellHeatTransfer == "Enabled"
                safeSetBlockParam(batteryBlock,"InterCellThermalResistance", ...
                    num2str(interCellRField.Value,16));
                safeSetBlockParam(batteryBlock,"InterParallelAssemblyThermalResistance", ...
                    num2str(interParallelRField.Value,16));
            end

            %% Update existing external Parallel Channels cooling plate
            % Battery thermal-interface geometry remains automatic and comes
            % from the rebuilt Battery Builder object.
            safeSetBlockParam(plateBlock,"numBattThermalNodes1", ...
                num2str(numThermalNodes));
            safeSetBlockParam(plateBlock,"dimensionThermalNodes1", ...
                mat2str(thermalDimensions,16));
            safeSetBlockParam(plateBlock,"locationThermalNodes1", ...
                mat2str(thermalLocations,16));

%% User cooling-plate material/discretization/channel settings.
            applyCoolingPlateSettingsToBlock(plateBlock,state);

            try
                mdlWks = get_param(mdl,"ModelWorkspace");
                assignin(mdlWks,"T_plate_K", ...
                    state.InitialPlateTemperature_C + 273.15);
            catch
            end

%% Reapply the selected predefined coolant after the master model
            thermalLiquidBlock = findThermalLiquidPropertiesBlock(mdl);
            if strlength(thermalLiquidBlock) > 0
                applyCoolantPropertiesToBlock(thermalLiquidBlock,state);
            end

            %% Save working model
            save_system(mdl);

            %% Update app state
            state.P = P;
            state.S = S;
            state.TotalCells = N;
            state.Diameter_mm = diameterField.Value;
            state.Height_mm = heightField.Value;
            state.InterCellGap_mm = cellGapField.Value;
            state.InterAssemblyGap_mm = assemblyGapField.Value;
            state.Topology = Topology;
            state.Rows = Rows;
            state.ParallelAssemblyStackingAxis = ParallelAssemblyStackingAxis;
            state.ModuleStackingAxis = ModuleStackingAxis;
            state.MassFactor = MassFactor;
            state.InterCellHeatTransfer = InterCellHeatTransfer;
            state.CoolingPlateMode = CoolingPlateMode;
            state.GeneratedLibrary = libModel;
            state.GeneratedModuleObject = moduleObj;
            state.BatteryThermalNodeLocations = thermalLocations;
            state.BatteryThermalNodeDimensions = thermalDimensions;
            state.NeedsRebuild = false;

%% A structural rebuild invalidates any previous thermal animation.
            pauseThermalAnimation();
            if ~isempty(thermalChart)
                try
                    if isvalid(thermalChart)
                        delete(thermalChart);
                    end
                catch
                end
                thermalChart = [];
            end
            thermalMapPlaceholder.Visible = "on";
            thermalMapPlaceholder.Text = ...
                "Run a simulation to generate the 3D thermal map for this rebuilt battery.";
            thermalMapStatus.Text = "Battery rebuilt — thermal map awaiting simulation";
            thermalTimeSlider.Enable = "off";
            thermalTimeSlider.Limits = [0 1];
            thermalTimeSlider.Value = 0;
            thermalPlayButton.Enable = "off";
            thermalPauseButton.Enable = "off";
            thermalStopButton.Enable = "off";
            thermalSpeedButton.Enable = "off";
            thermalPlaybackSpeed = 1;
            thermalSpeedButton.Text = "SPEED 1×";

%% A structural rebuild invalidates the previous result detail
            state.LastKPI = [];
            state.LastTrace = [];
            state.LastRuntime_s = NaN;
            state.LastCurrentProfileDescription = "";
            cellNodalResultsButton.Enable = "off";
            simulationSummaryButton.Enable = "off";

%% Render the actual Battery Builder module inside ThermalPack.
            refreshBatteryGeometry(moduleObj,P,S,N);

            statusLabel.Text = sprintf( ...
                "Rebuild complete — %dP × %dS = %d cells",P,S,N);

            moduleMass_kg = N * massField.Value * MassFactor;
            moduleEnergy_Wh = N * energyField.Value;

        catch ME
            statusLabel.Text = "Battery rebuild failed";
            uialert(fig,getReport(ME,"extended","hyperlinks","off"), ...
                "ThermalPack Rebuild Error");
        end

        rebuildButton.Enable = "on";
        runButton.Enable = "on";
    end

    function runSimulation(~,~)
        if state.NeedsRebuild
            answer = uiconfirm(fig, ...
                ["Structural battery inputs have changed since the last rebuild." ...
                 newline newline ...
                 "Rebuild the battery before running the simulation?"], ...
                "Battery Rebuild Required", ...
                "Options",["Rebuild","Cancel"], ...
                "DefaultOption","Rebuild", ...
                "CancelOption","Cancel");

            if answer == "Rebuild"
                rebuildBattery([],[]);
            end
            return;
        end

        runButton.Enable = "off";
        rebuildButton.Enable = "off";
        statusLabel.Text = "Running Simscape simulation...";
        drawnow;

        try
            cfg = struct;
            cfg.NumAssemblies = state.S;
            cfg.CellsPerAssembly = state.P;
            cfg.TotalCells = state.TotalCells;
            cfg.NodesPerCell = round(nodesField.Value);
            cfg.Twarning_C = 45;
            cfg.Tcritical_C = 60;
            cfg.Tlimit_C = 60;

            simIn = Simulink.SimulationInput(mdl);

%% The editor stores Signal-Editor-style points, including
            % repeated timestamps for vertical steps. Thermal_Model_v3 uses
            % From Workspace with interpolation OFF, so before simulation
            % keep the LAST value at each repeated timestamp. This produces
            % the equivalent zero-order-hold step profile with unique times.
            editorCurrentProfile = state.CustomCurrentProfile;

            keepLastAtTime = [ ...
                diff(editorCurrentProfile(:,1)) ~= 0; ...
                true];

            CurrentProfile = editorCurrentProfile(keepLastAtTime,:);

            currentProfileDescription = sprintf( ...
                "Custom (%d editor points, %d simulation breakpoints, %.0f s)", ...
                size(editorCurrentProfile,1), ...
                size(CurrentProfile,1), ...
                editorCurrentProfile(end,1));

%% Thermal_Model_v3 uses a From Workspace block with
            simIn = simIn.setVariable( ...
                "CurrentProfile",CurrentProfile,"Workspace",mdl);

            if string(coolingPlateField.Value) == "No Cooling Plate"
                effectiveCoolantR_K_W = state.NoCoolingRth_K_W;
            else
                effectiveCoolantR_K_W = coolantRField.Value;
            end

%% Constant Flow Rate Source (TL)
            if state.FlowRateType == "Mass flow rate"
                state.MassFlowRate_kg_s = flowField.Value;
                simIn = simIn.setVariable( ...
                    "mdot_coolant",state.MassFlowRate_kg_s, ...
                    "Workspace",mdl);
            else
                state.VolumetricFlowRate_m3_s = flowField.Value;
                simIn = simIn.setVariable( ...
                    "qdot_coolant",state.VolumetricFlowRate_m3_s, ...
                    "Workspace",mdl);
            end

            flowSourceBlock = findFlowRateSourceBlock(mdl);
            if strlength(flowSourceBlock) > 0
                simIn = applyFlowSourceSettingsToSimulationInput( ...
                    simIn,flowSourceBlock,state);
            end

            simIn = simIn.setVariable( ...
                "T_coolant_in_K",tinField.Value + 273.15,"Workspace",mdl);
            simIn = simIn.setVariable( ...
                "T_plate_K",state.InitialPlateTemperature_C + 273.15, ...
                "Workspace",mdl);
            simIn = simIn.setVariable( ...
                "Area_coolant_port_in_m2",state.CoolantPortArea_m2, ...
                "Workspace",mdl);
%% Existing Thermal Liquid Properties variables.
            simIn = simIn.setVariable( ...
                "T_ambient_K",ambientField.Value + 273.15,"Workspace",mdl);
            simIn = simIn.setVariable( ...
                "Atmospheric_pressure_in_Pa",state.AtmosphericPressure_Pa, ...
                "Workspace",mdl);
            simIn = simIn.setVariable( ...
                "SOC0",socField.Value,"Workspace",mdl);

            state.InitialCellTemperature_C = initialCellTempField.Value;

%% Parallel Channels cooling plate
            simIn = applyCoolingPlateSettingsToSimulationInput( ...
                simIn,plateBlock,state);

%% Thermal Liquid Properties (TL)
            thermalLiquidBlock = findThermalLiquidPropertiesBlock(mdl);
            if strlength(thermalLiquidBlock) > 0
                simIn = applyCoolantPropertiesToSimulationInput( ...
                    simIn,thermalLiquidBlock,state);
            end

%% Reservoir (TL)1 is the coolant inlet reservoir.
            reservoirBlock = mdl + "/Reservoir (TL)1";

            if getSimulinkBlockHandle(reservoirBlock) > 0
%% Constant boundary-condition mode. Dynamic physical-signal
                % inputs remain disabled until ThermalPack provides signal
                % source blocks and profiles for ports P/T.
                simIn = simIn.setBlockParameter(reservoirBlock, ...
                    "pressure_input","false");
                simIn = simIn.setBlockParameter(reservoirBlock, ...
                    "temperature_input","false");
                simIn = simIn.setBlockParameter(reservoirBlock, ...
                    "reservoir_temperature","T_coolant_in_K");
                simIn = simIn.setBlockParameter(reservoirBlock, ...
                    "area","Area_coolant_port_in_m2");

                if state.ReservoirPressureSpecification == "Specified pressure"
                    simIn = simIn.setBlockParameter(reservoirBlock, ...
                        "pressure_spec","foundation.enum.pressure_spec.specified");
                    simIn = simIn.setBlockParameter(reservoirBlock, ...
                        "reservoir_pressure", ...
                        num2str(state.ReservoirPressure_Pa,16));
                else
                    simIn = simIn.setBlockParameter(reservoirBlock, ...
                        "pressure_spec","foundation.enum.pressure_spec.atmospheric");
                end
            end

            simIn = simIn.setBlockParameter(batteryBlock, ...
                "batteryTemperature", ...
                sprintf("repmat(%.16g,%d,1)", ...
                initialCellTempField.Value + 273.15,state.TotalCells));

            simIn = simIn.setBlockParameter(batteryBlock, ...
                "BatteryCapacityCell",num2str(capacityField.Value,16));
            simIn = simIn.setBlockParameter(batteryBlock, ...
                "HeightCell",num2str(heightField.Value/1000,16));
            simIn = simIn.setBlockParameter(batteryBlock, ...
                "NumThermalModelsCell",num2str(cfg.NodesPerCell));
            simIn = simIn.setBlockParameter(batteryBlock, ...
                "BatteryThermalMassCell",num2str(thermalMassField.Value,16));
            simIn = simIn.setBlockParameter(batteryBlock, ...
                "ThermalConductivityZCell",num2str(conductivityField.Value,16));
            simIn = simIn.setBlockParameter(batteryBlock, ...
                "CrossSectionalAreaXYCell", ...
                num2str(thermalAreaField.Value,16));

%% Cell electrical lookup data
            [simIn,extrapSet] = setSimInputEnumParamByName( ...
                simIn,batteryBlock,"ExtrapolationMethodCell", ...
                state.ExtrapolationMethod);

            if ~extrapSet
                error("ThermalPack:ExtrapolationEnumResolution", ...
                    "Could not resolve the Simscape enum for Extrapolation Method.");
            end
            simIn = simIn.setBlockParameter(batteryBlock, ...
                "VoltageRangeCell",mat2str(state.VoltageRange_V,16));
            simIn = simIn.setBlockParameter(batteryBlock, ...
                "SOCBreakpointsCell",mat2str(state.OCVSOCBreakpoints,16));
            simIn = simIn.setBlockParameter(batteryBlock, ...
                "TemperatureBreakpointsCell", ...
                mat2str(state.OCVTemperature_C + 273.15,16));
            simIn = simIn.setBlockParameter(batteryBlock, ...
                "OpenCircuitVoltageThermalCell",mat2str(state.OCVTable_V,16));
            simIn = simIn.setBlockParameter(batteryBlock, ...
                "ResistanceSOCBreakpointsCell", ...
                mat2str(state.ResistanceSOCBreakpoints,16));
            simIn = simIn.setBlockParameter(batteryBlock, ...
                "ResistanceTemperatureBreakpointsCell", ...
                mat2str(state.ResistanceTemperature_C + 273.15,16));
            simIn = simIn.setBlockParameter(batteryBlock, ...
                "R0ThermalCell",mat2str(state.R0Table_Ohm,16));

            r0DevRun = resizeNumericVector( ...
                state.R0Deviation_pct,state.TotalCells,0);
            tmDevRun = resizeNumericVector( ...
                state.ThermalMassDeviation_pct,state.TotalCells,0);
            kDevRun = resizeNumericVector( ...
                state.ThermalConductivityDeviation_pct,state.TotalCells,0);

            simIn = simIn.setBlockParameter(batteryBlock, ...
                "R0ThermalCellPercentDeviation",mat2str(r0DevRun,16));
            simIn = simIn.setBlockParameter(batteryBlock, ...
                "BatteryThermalMassCellPercentDeviation",mat2str(tmDevRun,16));
            simIn = simIn.setBlockParameter(batteryBlock, ...
                "ThermalConductivityZCellPercentDeviation",mat2str(kDevRun,16));

            simIn = simIn.setBlockParameter(batteryBlock, ...
                "CoolantResistance",num2str(effectiveCoolantR_K_W,16));
            simIn = simIn.setBlockParameter(batteryBlock, ...
                "AmbientResistance",num2str(ambientRField.Value,16));
            if state.InterCellHeatTransfer == "Enabled"
                simIn = simIn.setBlockParameter(batteryBlock, ...
                    "InterCellThermalResistance",num2str(interCellRField.Value,16));

%% Heat exchange between neighboring series parallel assemblies.
                try
                    simIn = simIn.setBlockParameter(batteryBlock, ...
                        "InterParallelAssemblyThermalResistance", ...
                        num2str(interParallelRField.Value,16));
                catch
                end
            end

%% Solver is a runtime simulation setting and does not
            % require rebuilding the Battery Builder model.
            if state.Solver == "Auto"
                solverName = "VariableStepAuto";
            else
                solverName = state.Solver;
            end

            simIn = simIn.setModelParameter( ...
                "StopTime",num2str(stopField.Value,16), ...
                "SolverType","Variable-step", ...
                "SolverName",solverName, ...
                "SimscapeLogType","all", ...
                "SimscapeLogName","simlog", ...
                "ReturnWorkspaceOutputs","on");

            t0 = tic;
            out = sim(simIn);
            runtime = toc(t0);

            [KPI,Trace] = extractUIResults(out,cfg);

%% Dashboard graph 1: individual cell-average temperatures
            cla(temperatureAxes);
            cellTemperatureLines = plot(temperatureAxes, ...
                Trace.tCell,Trace.Tcell_C,"LineWidth",1.05);

            nLegendCells = size(Trace.Tcell_C,2);
            cellLegendLabels = cellstr(compose( ...
                "Cell %d",1:nLegendCells));

            legend(temperatureAxes, ...
                cellTemperatureLines,cellLegendLabels, ...
                "Location","northoutside", ...
                "Orientation","horizontal", ...
                "NumColumns",min(6,max(1,nLegendCells)));

            title(temperatureAxes,sprintf( ...
                "Cell Average Temperatures — %dP × %dS",state.P,state.S));
            xlabel(temperatureAxes,"Time (s)");
            ylabel(temperatureAxes,"Temperature (°C)");
            grid(temperatureAxes,"on");

%% Dashboard graph 2: max / mean / min of CELL-AVERAGE
            % temperatures across all cells at each time.
            % Requested visual meaning:
            %   Minimum = blue
            %   Average = yellow
            %   Maximum = red
            cla(cellAverageEnvelopeAxes);
            hold(cellAverageEnvelopeAxes,"on");

            hMin = plot(cellAverageEnvelopeAxes, ...
                Trace.tCell,Trace.TminCellAverage_C, ...
                "Color",[0.10 0.42 0.95], ...
                "LineWidth",1.7, ...
                "DisplayName","Cell-averaged minimum");

            hAvg = plot(cellAverageEnvelopeAxes, ...
                Trace.tCell,Trace.TmeanCellAverage_C, ...
                "Color",[0.95 0.78 0.05], ...
                "LineWidth",1.7, ...
                "DisplayName","Cell average");

            hMax = plot(cellAverageEnvelopeAxes, ...
                Trace.tCell,Trace.TmaxCellAverage_C, ...
                "Color",[0.88 0.12 0.12], ...
                "LineWidth",1.7, ...
                "DisplayName","Cell-averaged maximum");

            hold(cellAverageEnvelopeAxes,"off");

            legend(cellAverageEnvelopeAxes,[hMin hAvg hMax], ...
                "Location","northoutside", ...
                "Orientation","horizontal");
            title(cellAverageEnvelopeAxes, ...
                "Cell-Average Maximum, Average and Minimum Temperatures");
            xlabel(cellAverageEnvelopeAxes,"Time (s)");
            ylabel(cellAverageEnvelopeAxes,"Temperature (°C)");
            grid(cellAverageEnvelopeAxes,"on");

%% KPI cards.
            kpiTmaxValue.Text = sprintf("%.2f °C",KPI.PeakTmaxNodal_C);
            kpiDeltaValue.Text = sprintf("%.2f °C",KPI.MaxDeltaTNodal_C);
            kpiHotspotValue.Text = sprintf("Cell %d / Node %d", ...
                KPI.WorstCell,KPI.WorstNode);
            kpiMarginValue.Text = sprintf("%.2f °C",KPI.MinSafetyMargin_C);
            kpiStatusValue.Text = KPI.WorstStatus;

%% Cache completed results for the two Dashboard result windows.
            state.LastKPI = KPI;
            state.LastTrace = Trace;
            state.LastRuntime_s = runtime;
            state.LastCurrentProfileDescription = currentProfileDescription;

            cellNodalResultsButton.Enable = "on";
            simulationSummaryButton.Enable = "on";

%% Create/update the custom height-resolved nodal 3D thermal map.
            refreshThermalAnimation(out,Trace);

            statusLabel.Text = sprintf("Simulation complete in %.2f s",runtime);

        catch ME
            statusLabel.Text = "Simulation failed";
            uialert(fig,getReport(ME,"extended","hyperlinks","off"), ...
                "ThermalPack Simulation Error");
        end

        runButton.Enable = "on";
        rebuildButton.Enable = "on";
    end
end

%% UI helpers
function label = addInputLabel(parent,row,textValue)
label = uilabel(parent,"Text",textValue);
label.Layout.Row = row;
label.Layout.Column = 1;
end

function addDisabledAdvancedRow(parent,row,labelText,stateText)
lbl = uilabel(parent,"Text",labelText);
lbl.Layout.Row = row;
lbl.Layout.Column = 1;

ctrl = uidropdown(parent, ...
    "Items",stateText, ...
    "Value",stateText, ...
    "Enable","off");
ctrl.Layout.Row = row;
ctrl.Layout.Column = 2;
end

function sectionLabel(parent,row,textValue)
label = uilabel(parent, ...
    "Text",textValue, ...
    "FontWeight","bold", ...
    "FontSize",12);
label.Layout.Row = row;
label.Layout.Column = [1 2];
end

function [panel,valueLabel] = makeCard(parent,column,titleText,valueText)
panel = uipanel(parent);
panel.Layout.Row = 1;
panel.Layout.Column = column;

g = uigridlayout(panel,[2 1]);
g.RowHeight = {25,'1x'};
g.Padding = [6 6 6 6];

t = uilabel(g, ...
    "Text",titleText, ...
    "HorizontalAlignment","center", ...
    "FontWeight","bold", ...
    "FontSize",10);
t.Layout.Row = 1;

valueLabel = uilabel(g, ...
    "Text",valueText, ...
    "HorizontalAlignment","center", ...
    "FontWeight","bold", ...
    "FontSize",17);
valueLabel.Layout.Row = 2;
end

%% Parallel Channels cooling-plate helpers
function value = blockNumericParam(blockPath,paramName,defaultValue)
value = defaultValue;

try
    raw = get_param(blockPath,paramName);
    candidate = str2double(raw);

    if isfinite(candidate)
        value = candidate;
        return;
    end

    candidate = str2num(char(raw)); %#ok<ST2NM>
    if isnumeric(candidate) && isscalar(candidate) && isfinite(candidate)
        value = candidate;
    end
catch
end
end

function applyCoolingPlateSettingsToBlock(blockPath,state)
safeSetBlockParam(blockPath,"plateConnectivity", ...
    "simscape.battery.enum.thermal.coolingPlateConnectivity.singleSided");

safeSetBlockParam(blockPath,"plateDimX", ...
    num2str(round(state.PlatePartitionsX)));
safeSetBlockParam(blockPath,"plateDimY", ...
    num2str(round(state.PlatePartitionsY)));

safeSetBlockParam(blockPath,"plateTh", ...
    num2str(state.PlateThickness_mm/1000,16));
safeSetBlockParam(blockPath,"plateThCond", ...
    num2str(state.PlateConductivity_W_mK,16));
safeSetBlockParam(blockPath,"plateDen", ...
    num2str(state.PlateDensity_kg_m3,16));
safeSetBlockParam(blockPath,"plateCp", ...
    num2str(state.PlateSpecificHeat_J_kgK,16));

%% Preserve the existing ThermalPack variable interface.
safeSetBlockParam(blockPath,"plateTemp_ini","T_plate_K");

safeSetBlockParam(blockPath,"nChannels", ...
    num2str(round(state.NumCoolantChannels)));

if state.ChannelOrientation == "Channels along Y axis"
    orientationValue = ...
        "simscape.battery.enum.thermal.coolingChannelsDirection.alongY";
else
    orientationValue = ...
        "simscape.battery.enum.thermal.coolingChannelsDirection.alongX";
end
safeSetBlockParam(blockPath,"selectChannelOrientation",orientationValue);

safeSetBlockParam(blockPath,"channelDia", ...
    num2str(state.ChannelHydraulicDiameter_mm/1000,16));
safeSetBlockParam(blockPath,"distributorDia", ...
    num2str(state.DistributorDiameter_mm/1000,16));
safeSetBlockParam(blockPath,"roughnessPipe", ...
    num2str(state.ChannelRoughness_mm/1000,16));
end

function simIn = applyCoolingPlateSettingsToSimulationInput( ...
        simIn,blockPath,state)

simIn = simIn.setBlockParameter(blockPath, ...
    "plateConnectivity", ...
    "simscape.battery.enum.thermal.coolingPlateConnectivity.singleSided");

simIn = simIn.setBlockParameter(blockPath, ...
    "plateDimX",num2str(round(state.PlatePartitionsX)));
simIn = simIn.setBlockParameter(blockPath, ...
    "plateDimY",num2str(round(state.PlatePartitionsY)));

simIn = simIn.setBlockParameter(blockPath, ...
    "plateTh",num2str(state.PlateThickness_mm/1000,16));
simIn = simIn.setBlockParameter(blockPath, ...
    "plateThCond",num2str(state.PlateConductivity_W_mK,16));
simIn = simIn.setBlockParameter(blockPath, ...
    "plateDen",num2str(state.PlateDensity_kg_m3,16));
simIn = simIn.setBlockParameter(blockPath, ...
    "plateCp",num2str(state.PlateSpecificHeat_J_kgK,16));
simIn = simIn.setBlockParameter(blockPath, ...
    "plateTemp_ini","T_plate_K");

simIn = simIn.setBlockParameter(blockPath, ...
    "nChannels",num2str(round(state.NumCoolantChannels)));

if state.ChannelOrientation == "Channels along Y axis"
    orientationValue = ...
        "simscape.battery.enum.thermal.coolingChannelsDirection.alongY";
else
    orientationValue = ...
        "simscape.battery.enum.thermal.coolingChannelsDirection.alongX";
end

simIn = simIn.setBlockParameter(blockPath, ...
    "selectChannelOrientation",orientationValue);

simIn = simIn.setBlockParameter(blockPath, ...
    "channelDia",num2str(state.ChannelHydraulicDiameter_mm/1000,16));
simIn = simIn.setBlockParameter(blockPath, ...
    "distributorDia",num2str(state.DistributorDiameter_mm/1000,16));
simIn = simIn.setBlockParameter(blockPath, ...
    "roughnessPipe",num2str(state.ChannelRoughness_mm/1000,16));
end

%% Flow Rate Source (TL) helpers
function blockPath = findFlowRateSourceBlock(mdl)
blockPath = "";

try
    matches = find_system(mdl, ...
        "LookUnderMasks","all", ...
        "FollowLinks","on", ...
        "Name","Flow Rate Source (TL)");

    if ~isempty(matches)
        blockPath = string(matches{1});
        return;
    end
catch
end

try
    allBlocks = find_system(mdl, ...
        "LookUnderMasks","all", ...
        "FollowLinks","on", ...
        "Type","Block");

    for k = 1:numel(allBlocks)
        try
            maskType = lower(string(get_param(allBlocks{k},"MaskType")));
            if contains(maskType,"flow rate source") && ...
                    contains(maskType,"thermal liquid")
                blockPath = string(allBlocks{k});
                return;
            end
        catch
        end
    end
catch
end
end

function safeSetFlowEnum(blockPath,promptText,displayValue)
paramName = dialogParameterNameByPrompt(blockPath,promptText);
if strlength(paramName) == 0
    return;
end

try
    if promptText == "Source type"
%% Constant is the only active ThermalPack source type for now.
        value = "foundation.enum.constant_controlled.constant";
    elseif promptText == "Flow rate type"
        if displayValue == "Volumetric flow rate"
            value = "foundation.enum.mass_volumetric_flow.volumetric";
        else
            value = "foundation.enum.mass_volumetric_flow.mass";
        end
    else
        value = displayValue;
    end

    set_param(blockPath,char(paramName),char(value));
catch
%% Fallback to the displayed mask value in case this release accepts it
    try
        set_param(blockPath,char(paramName),char(displayValue));
    catch
    end
end
end

function applyFlowSourceSettingsToBlock(blockPath,state)
safeSetFlowEnum(blockPath,"Source type","Constant");
safeSetFlowEnum(blockPath,"Flow rate type",state.FlowRateType);

if state.FlowRateType == "Mass flow rate"
    safeSetBlockParamByPrompt(blockPath, ...
        "Mass flow rate","mdot_coolant");
else
    safeSetBlockParamByPrompt(blockPath, ...
        "Volumetric flow rate","qdot_coolant");
end
end

function simIn = setFlowEnumOnSimulationInput( ...
        simIn,blockPath,promptText,displayValue)

paramName = dialogParameterNameByPrompt(blockPath,promptText);
if strlength(paramName) == 0
    return;
end

if promptText == "Source type"
    value = "foundation.enum.constant_controlled.constant";
elseif promptText == "Flow rate type"
    if displayValue == "Volumetric flow rate"
        value = "foundation.enum.mass_volumetric_flow.volumetric";
    else
        value = "foundation.enum.mass_volumetric_flow.mass";
    end
else
    value = displayValue;
end

try
    simIn = simIn.setBlockParameter( ...
        blockPath,char(paramName),char(value));
catch
    try
        simIn = simIn.setBlockParameter( ...
            blockPath,char(paramName),char(displayValue));
    catch
    end
end
end

function simIn = applyFlowSourceSettingsToSimulationInput( ...
        simIn,blockPath,state)

simIn = setFlowEnumOnSimulationInput( ...
    simIn,blockPath,"Source type","Constant");
simIn = setFlowEnumOnSimulationInput( ...
    simIn,blockPath,"Flow rate type",state.FlowRateType);

if state.FlowRateType == "Mass flow rate"
    simIn = setSimInputBlockParamByPrompt( ...
        simIn,blockPath,"Mass flow rate","mdot_coolant");
else
    simIn = setSimInputBlockParamByPrompt( ...
        simIn,blockPath,"Volumetric flow rate","qdot_coolant");
end
end

%% Thermal-liquid coolant helpers
function blockPath = findThermalLiquidPropertiesBlock(mdl)
blockPath = "";

try
    matches = find_system(mdl, ...
        "LookUnderMasks","all", ...
        "FollowLinks","on", ...
        "Name","Thermal Liquid Properties (TL)");

    if ~isempty(matches)
        blockPath = string(matches{1});
        return;
    end
catch
end

%% Fallback: look for the block by its mask type.
try
    allBlocks = find_system(mdl, ...
        "LookUnderMasks","all", ...
        "FollowLinks","on", ...
        "Type","Block");

    for k = 1:numel(allBlocks)
        try
            maskType = string(get_param(allBlocks{k},"MaskType"));
            if contains(lower(maskType),"thermal liquid properties")
                blockPath = string(allBlocks{k});
                return;
            end
        catch
        end
    end
catch
end
end

function paramName = dialogParameterNameByPrompt(blockPath,promptText)
paramName = "";

try
    dp = get_param(blockPath,"DialogParameters");
    names = fieldnames(dp);

    target = lower(strtrim(string(promptText)));

%% First try exact prompt match.
    for k = 1:numel(names)
        info = dp.(names{k});
        if isfield(info,"Prompt")
            p = lower(strtrim(string(info.Prompt)));
            if p == target
                paramName = string(names{k});
                return;
            end
        end
    end

%% Then allow substring matching for release-to-release wording changes.
    for k = 1:numel(names)
        info = dp.(names{k});
        if isfield(info,"Prompt")
            p = lower(strtrim(string(info.Prompt)));
            if contains(p,target) || contains(target,p)
                paramName = string(names{k});
                return;
            end
        end
    end
catch
end
end

function label = friendlyExtrapolationLabel(rawValue)
raw = lower(string(rawValue));

if contains(raw,"linear")
    label = "Linear";
elseif contains(raw,"error")
    label = "Error";
else
%% Includes both friendly "Nearest" and internal enum expressions
    label = "Nearest";
end
end

function enumValue = resolveEnumParameterValueByName( ...
        blockPath,paramName,desiredDisplay)
%% Resolve the actual expression accepted by an enum-backed Simscape
% parameter using its internal parameter name.

enumValue = "";
paramName = string(paramName);

%% 1) Current block value.
try
    currentValue = string(get_param(blockPath,char(paramName)));
    if enumTextMatchesDesired(currentValue,desiredDisplay)
        enumValue = currentValue;
        return;
    end
catch
end

%% 2) DialogParameters Enum values.
try
    dp = get_param(blockPath,"DialogParameters");

    if isfield(dp,char(paramName))
        info = dp.(char(paramName));

        if isfield(info,"Enum") && ~isempty(info.Enum)
            enumOptions = string(info.Enum);

            for k = 1:numel(enumOptions)
                if enumTextMatchesDesired(enumOptions(k),desiredDisplay)
                    enumValue = enumOptions(k);
                    return;
                end
            end
        end
    end
catch
end

%% 3) Mask parameter fallback.
try
    maskObj = Simulink.Mask.get(char(blockPath));

    if ~isempty(maskObj)
        maskParam = maskObj.getParameter(char(paramName));

        if ~isempty(maskParam)
            currentValue = string(maskParam.Value);
            if enumTextMatchesDesired(currentValue,desiredDisplay)
                enumValue = currentValue;
                return;
            end

            opts = maskParam.TypeOptions;
            if iscell(opts)
                enumOptions = string(opts);

                for k = 1:numel(enumOptions)
                    if enumTextMatchesDesired(enumOptions(k),desiredDisplay)
                        enumValue = enumOptions(k);
                        return;
                    end
                end
            end
        end
    end
catch
end
end

function ok = safeSetEnumBlockParamByName( ...
        blockPath,paramName,desiredDisplay)

ok = false;
enumValue = resolveEnumParameterValueByName( ...
    blockPath,paramName,desiredDisplay);

if strlength(enumValue) == 0
    return;
end

try
    set_param(blockPath,char(string(paramName)),char(enumValue));
    ok = true;
catch
end
end

function [simIn,ok] = setSimInputEnumParamByName( ...
        simIn,blockPath,paramName,desiredDisplay)

ok = false;
enumValue = resolveEnumParameterValueByName( ...
    blockPath,paramName,desiredDisplay);

if strlength(enumValue) == 0
    return;
end

try
    simIn = simIn.setBlockParameter( ...
        blockPath,char(string(paramName)),char(enumValue));
    ok = true;
catch
end
end

function tf = enumTextMatchesDesired(enumText,desiredDisplay)
%% Match a Simscape internal enumeration expression to a ThermalPack
% user-facing choice without hard-coding the enumeration class name.
enumText = lower(string(enumText));
desired = lower(string(desiredDisplay));

if desired == "ethylene glycol and water mixture"
    tf = contains(enumText,"ethylene");
elseif desired == "propylene glycol and water mixture"
    tf = contains(enumText,"propylene");
elseif desired == "glycerol and water mixture"
    tf = contains(enumText,"glycerol");
elseif desired == "seawater (mit model)"
    tf = contains(enumText,"seawater") || ...
         (contains(enumText,"sea") && contains(enumText,"water"));
elseif desired == "water"
    tf = contains(enumText,"water") && ...
         ~contains(enumText,"ethylene") && ...
         ~contains(enumText,"propylene") && ...
         ~contains(enumText,"glycerol") && ...
         ~contains(enumText,"sea");
elseif desired == "diesel fuel"
    tf = contains(enumText,"diesel");
elseif desired == "aviation fuel jet-a"
    tf = contains(enumText,"jet");
elseif desired == "sae 5w-30"
    tf = contains(enumText,"5w") || contains(enumText,"sae");
elseif desired == "volume fraction"
    tf = contains(enumText,"volume");
elseif desired == "mass fraction"
    tf = contains(enumText,"mass");
else
%% Generic fallback for any future enum options.
    lhs = regexprep(enumText,'[^a-z0-9]','');
    rhs = regexprep(desired,'[^a-z0-9]','');
    tf = contains(lhs,rhs) || contains(rhs,lhs);
end
end

function enumValue = resolveEnumParameterValue( ...
        blockPath,promptText,desiredDisplay)
%% Return the actual expression expected by a Simscape enum parameter.
% Simscape dialogs show friendly strings such as
% "Ethylene glycol and water mixture", but set_param / SimulationInput
% can require an internal enum expression. Resolve it from the block
% instead of passing the display string as MATLAB code.

enumValue = "";
paramName = dialogParameterNameByPrompt(blockPath,promptText);

if strlength(paramName) == 0
    return;
end

%% 1) Prefer the block's current value if it already represents the
try
    currentValue = string(get_param(blockPath,char(paramName)));
    if enumTextMatchesDesired(currentValue,desiredDisplay)
        enumValue = currentValue;
        return;
    end
catch
end

%% 2) Read the documented Enum values from DialogParameters and select
try
    dp = get_param(blockPath,"DialogParameters");
    info = dp.(char(paramName));

    if isfield(info,"Enum") && ~isempty(info.Enum)
        enumOptions = string(info.Enum);

        for k = 1:numel(enumOptions)
            if enumTextMatchesDesired(enumOptions(k),desiredDisplay)
                enumValue = enumOptions(k);
                return;
            end
        end
    end
catch
end

%% 3) Mask-object fallback for blocks whose popup is implemented as a
try
    maskObj = Simulink.Mask.get(char(blockPath));
    if ~isempty(maskObj)
        maskParam = maskObj.getParameter(char(paramName));

        if ~isempty(maskParam)
            currentValue = string(maskParam.Value);
            if enumTextMatchesDesired(currentValue,desiredDisplay)
                enumValue = currentValue;
                return;
            end

            opts = maskParam.TypeOptions;
            if iscell(opts)
                enumOptions = string(opts);
                for k = 1:numel(enumOptions)
                    if enumTextMatchesDesired(enumOptions(k),desiredDisplay)
                        enumValue = enumOptions(k);
                        return;
                    end
                end
            end
        end
    end
catch
end
end

function ok = safeSetEnumBlockParamByPrompt( ...
        blockPath,promptText,desiredDisplay)

ok = false;
paramName = dialogParameterNameByPrompt(blockPath,promptText);
if strlength(paramName) == 0
    return;
end

enumValue = resolveEnumParameterValue( ...
    blockPath,promptText,desiredDisplay);

if strlength(enumValue) == 0
    return;
end

try
    set_param(blockPath,char(paramName),char(enumValue));
    ok = true;
catch
end
end

function [simIn,ok] = setSimInputEnumParamByPrompt( ...
        simIn,blockPath,promptText,desiredDisplay)

ok = false;
paramName = dialogParameterNameByPrompt(blockPath,promptText);
if strlength(paramName) == 0
    return;
end

enumValue = resolveEnumParameterValue( ...
    blockPath,promptText,desiredDisplay);

if strlength(enumValue) == 0
    return;
end

try
    simIn = simIn.setBlockParameter( ...
        blockPath,char(paramName),char(enumValue));
    ok = true;
catch
end
end

function safeSetBlockParamByPrompt(blockPath,promptText,value)
paramName = dialogParameterNameByPrompt(blockPath,promptText);
if strlength(paramName) == 0
    return;
end

try
    set_param(blockPath,char(paramName),char(string(value)));
catch
%% Keep the master-model value if a release uses a different underlying
end
end

function applyCoolantPropertiesToBlock(blockPath,state)
%% Enum-valued coolant selectors must use the Simscape enum expression,
% not the human-readable dropdown text.
fluidSet = safeSetEnumBlockParamByPrompt( ...
    blockPath,"Thermal liquid fluid list",state.CoolantFluid);

if ~fluidSet
    error("ThermalPack:CoolantEnumResolution", ...
        ["Could not resolve the Simscape enum for Thermal liquid fluid " ...
         "list. The working model was left unchanged."]);
end

fluid = state.CoolantFluid;
ctype = state.CoolantConcentrationType;
c = state.CoolantConcentration;

if fluid == "Ethylene glycol and water mixture"
    typeSet = safeSetEnumBlockParamByPrompt( ...
        blockPath,"Concentration type",ctype);
    if ~typeSet
        error("ThermalPack:CoolantEnumResolution", ...
            "Could not resolve the Simscape enum for Concentration type.");
    end

    if ctype == "Volume fraction"
        safeSetBlockParamByPrompt(blockPath, ...
            "Ethylene glycol volume fraction",num2str(c,16));
    else
        safeSetBlockParamByPrompt(blockPath, ...
            "Ethylene glycol mass fraction",num2str(c,16));
    end

elseif fluid == "Propylene glycol and water mixture"
    typeSet = safeSetEnumBlockParamByPrompt( ...
        blockPath,"Concentration type",ctype);
    if ~typeSet
        error("ThermalPack:CoolantEnumResolution", ...
            "Could not resolve the Simscape enum for Concentration type.");
    end

    if ctype == "Volume fraction"
        safeSetBlockParamByPrompt(blockPath, ...
            "Propylene glycol volume fraction",num2str(c,16));
    else
        safeSetBlockParamByPrompt(blockPath, ...
            "Propylene glycol mass fraction",num2str(c,16));
    end

elseif fluid == "Glycerol and water mixture"
    safeSetBlockParamByPrompt(blockPath, ...
        "Glycerol mass fraction",num2str(c,16));

elseif fluid == "Seawater (MIT model)"
    safeSetBlockParamByPrompt(blockPath, ...
        "Dissolved salt mass fraction (salinity)",num2str(c,16));
end
end

function simIn = setSimInputBlockParamByPrompt( ...
        simIn,blockPath,promptText,value)

paramName = dialogParameterNameByPrompt(blockPath,promptText);
if strlength(paramName) == 0
    return;
end

try
    simIn = simIn.setBlockParameter( ...
        blockPath,char(paramName),char(string(value)));
catch
end
end

function simIn = applyCoolantPropertiesToSimulationInput( ...
        simIn,blockPath,state)

[simIn,fluidSet] = setSimInputEnumParamByPrompt( ...
    simIn,blockPath,"Thermal liquid fluid list",state.CoolantFluid);

if ~fluidSet
    error("ThermalPack:CoolantEnumResolution", ...
        ["Could not resolve the Simscape enum for Thermal liquid fluid " ...
         "list."]);
end

fluid = state.CoolantFluid;
ctype = state.CoolantConcentrationType;
c = state.CoolantConcentration;

if fluid == "Ethylene glycol and water mixture"
    [simIn,typeSet] = setSimInputEnumParamByPrompt( ...
        simIn,blockPath,"Concentration type",ctype);

    if ~typeSet
        error("ThermalPack:CoolantEnumResolution", ...
            "Could not resolve the Simscape enum for Concentration type.");
    end

    if ctype == "Volume fraction"
        simIn = setSimInputBlockParamByPrompt( ...
            simIn,blockPath,"Ethylene glycol volume fraction",num2str(c,16));
    else
        simIn = setSimInputBlockParamByPrompt( ...
            simIn,blockPath,"Ethylene glycol mass fraction",num2str(c,16));
    end

elseif fluid == "Propylene glycol and water mixture"
    [simIn,typeSet] = setSimInputEnumParamByPrompt( ...
        simIn,blockPath,"Concentration type",ctype);

    if ~typeSet
        error("ThermalPack:CoolantEnumResolution", ...
            "Could not resolve the Simscape enum for Concentration type.");
    end

    if ctype == "Volume fraction"
        simIn = setSimInputBlockParamByPrompt( ...
            simIn,blockPath,"Propylene glycol volume fraction",num2str(c,16));
    else
        simIn = setSimInputBlockParamByPrompt( ...
            simIn,blockPath,"Propylene glycol mass fraction",num2str(c,16));
    end

elseif fluid == "Glycerol and water mixture"
    simIn = setSimInputBlockParamByPrompt( ...
        simIn,blockPath,"Glycerol mass fraction",num2str(c,16));

elseif fluid == "Seawater (MIT model)"
    simIn = setSimInputBlockParamByPrompt( ...
        simIn,blockPath,"Dissolved salt mass fraction (salinity)",num2str(c,16));
end
end

%% Cell electrical data helpers
function value = numericExpressionParam(master,name,defaultValue)
value = defaultValue;
field = char(name);

if ~isfield(master,field)
    return;
end

try
    candidate = str2num(char(master.(field))); %#ok<ST2NM>
    if isnumeric(candidate) && ~isempty(candidate)
        value = candidate;
    end
catch
end
end

function value = rowVectorParam(master,name,defaultValue)
value = numericExpressionParam(master,name,defaultValue);
value = value(:).';
end

function value = firstNumericValueParam(master,name,defaultValue)
candidate = numericExpressionParam(master,name,defaultValue);
if isnumeric(candidate) && ~isempty(candidate) && isfinite(candidate(1))
    value = candidate(1);
else
    value = defaultValue;
end
end

function vec = deviationVectorParam(master,name,N)
raw = numericExpressionParam(master,name,zeros(N,1));
vec = resizeNumericVector(raw(:),N,0);
end

function vec = resizeNumericVector(vec,N,fillValue)
if isempty(vec)
    vec = repmat(fillValue,N,1);
    return;
end

vec = double(vec(:));

if numel(vec) >= N
    vec = vec(1:N);
else
    vec = [vec; repmat(fillValue,N-numel(vec),1)];
end
end

function tf = validSOCBreakpoints(v)
tf = isnumeric(v) && isvector(v) && numel(v) >= 2 && ...
    all(isfinite(v)) && all(v >= 0) && all(v <= 1) && ...
    all(diff(v) > 0);
end

function tf = validTemperatureBreakpoints(vC)
tf = isnumeric(vC) && isvector(vC) && numel(vC) >= 1 && ...
    all(isfinite(vC)) && all(vC > -273.15) && ...
    (numel(vC) == 1 || all(diff(vC) > 0));
end

function applyCellElectricalDataToBlock(blockPath,state,N)
extrapSet = safeSetEnumBlockParamByName( ...
    blockPath,"ExtrapolationMethodCell",state.ExtrapolationMethod);

if ~extrapSet
    error("ThermalPack:ExtrapolationEnumResolution", ...
        "Could not resolve the Simscape enum for Extrapolation Method.");
end

safeSetBlockParam(blockPath,"VoltageRangeCell", ...
    mat2str(state.VoltageRange_V,16));

safeSetBlockParam(blockPath,"SOCBreakpointsCell", ...
    mat2str(state.OCVSOCBreakpoints,16));
safeSetBlockParam(blockPath,"TemperatureBreakpointsCell", ...
    mat2str(state.OCVTemperature_C + 273.15,16));
safeSetBlockParam(blockPath,"OpenCircuitVoltageThermalCell", ...
    mat2str(state.OCVTable_V,16));

safeSetBlockParam(blockPath,"ResistanceSOCBreakpointsCell", ...
    mat2str(state.ResistanceSOCBreakpoints,16));
safeSetBlockParam(blockPath,"ResistanceTemperatureBreakpointsCell", ...
    mat2str(state.ResistanceTemperature_C + 273.15,16));
safeSetBlockParam(blockPath,"R0ThermalCell", ...
    mat2str(state.R0Table_Ohm,16));

r0Dev = resizeNumericVector(state.R0Deviation_pct,N,0);
tmDev = resizeNumericVector(state.ThermalMassDeviation_pct,N,0);
kDev = resizeNumericVector(state.ThermalConductivityDeviation_pct,N,0);

safeSetBlockParam(blockPath,"R0ThermalCellPercentDeviation", ...
    mat2str(r0Dev,16));
safeSetBlockParam(blockPath,"BatteryThermalMassCellPercentDeviation", ...
    mat2str(tmDev,16));
safeSetBlockParam(blockPath,"ThermalConductivityZCellPercentDeviation", ...
    mat2str(kDev,16));
end

%% Safe block parameter helpers
function safeSetBlockParam(blockPath,paramName,paramValue)
try
    set_param(char(blockPath),char(paramName),char(paramValue));
catch ME
    warning("ThermalPack:ParameterNotApplied", ...
        "Could not set %s on %s: %s", ...
        paramName,blockPath,ME.message);
end
end

function master = captureMasterBatteryParameters(blockPath)
%% Read the values from the ORIGINAL generated battery reference block.
% These strings are intentionally retained in MATLAB/Simscape syntax.

names = [ ...
    "BatteryCapacityCell", ...
    "ExtrapolationMethodCell", ...
    "SOCBreakpointsCell", ...
    "TemperatureBreakpointsCell", ...
    "OpenCircuitVoltageThermalCell", ...
    "VoltageRangeCell", ...
    "ResistanceSOCBreakpointsCell", ...
    "ResistanceTemperatureBreakpointsCell", ...
    "R0ThermalCell", ...
    "BatteryThermalMassCell", ...
    "NumThermalModelsCell", ...
    "ThermalConductivityZCell", ...
    "CrossSectionalAreaXYCell", ...
    "HeightCell", ...
    "CoolantResistance", ...
    "AmbientResistance", ...
    "InterCellThermalResistance", ...
    "InterParallelAssemblyThermalResistance", ...
    "BatteryCapacityCellPercentDeviation", ...
    "SOCBreakpointsCellPercentDeviation", ...
    "TemperatureBreakpointsCellPercentDeviation", ...
    "OpenCircuitVoltageThermalCellPercentDeviation", ...
    "VoltageRangeCellPercentDeviation", ...
    "ResistanceSOCBreakpointsCellPercentDeviation", ...
    "ResistanceTemperatureBreakpointsCellPercentDeviation", ...
    "R0ThermalCellPercentDeviation", ...
    "BatteryThermalMassCellPercentDeviation", ...
    "NumThermalModelsCellPercentDeviation", ...
    "ThermalConductivityZCellPercentDeviation", ...
    "CrossSectionalAreaXYCellPercentDeviation", ...
    "HeightCellPercentDeviation", ...
    "socCell_specify","socCell_priority","socCell", ...
    "socCell_nominal_specify","socCell_nominal_value", ...
    "batteryVoltage_specify","batteryVoltage_priority","batteryVoltage", ...
    "batteryVoltage_nominal_specify","batteryVoltage_nominal_value", ...
    "batteryCurrent_specify","batteryCurrent_priority","batteryCurrent", ...
    "batteryCurrent_nominal_specify","batteryCurrent_nominal_value", ...
    "numCycles_specify","numCycles_priority","numCycles", ...
    "numCycles_nominal_specify","numCycles_nominal_value", ...
    "batteryTemperature_specify","batteryTemperature_priority", ...
    "batteryTemperature","batteryTemperature_nominal_specify", ...
    "batteryTemperature_nominal_value", ...
    "vParallelAssembly_specify","vParallelAssembly_priority", ...
    "vParallelAssembly","vParallelAssembly_nominal_specify", ...
    "vParallelAssembly_nominal_value", ...
    "socParallelAssembly_specify","socParallelAssembly_priority", ...
    "socParallelAssembly","socParallelAssembly_nominal_specify", ...
    "socParallelAssembly_nominal_value"];

master = struct;

for i = 1:numel(names)
    name = names(i);
    try
        master.(char(name)) = string(get_param(blockPath,char(name)));
    catch
%% Not every generated-library version exposes every optional field.
    end
end
end

function value = scalarParam(master,name,defaultValue)
value = defaultValue;
field = char(name);

if isfield(master,field)
    candidate = str2double(master.(field));
    if isfinite(candidate)
        value = candidate;
    end
end
end

function applyMasterBatteryParameters(blockPath,master,N,S)
%% Apply the master battery data to a newly generated module.
% Scalar/table parameters are copied exactly. Per-cell deviation arrays are
% resized to the new number of cells: existing original entries are kept in
% order and any added cells are nominal (0 % deviation).

directNames = [ ...
    "BatteryCapacityCell", ...
    "SOCBreakpointsCell", ...
    "TemperatureBreakpointsCell", ...
    "OpenCircuitVoltageThermalCell", ...
    "VoltageRangeCell", ...
    "ResistanceSOCBreakpointsCell", ...
    "ResistanceTemperatureBreakpointsCell", ...
    "R0ThermalCell", ...
    "BatteryThermalMassCell", ...
    "NumThermalModelsCell", ...
    "ThermalConductivityZCell", ...
    "CrossSectionalAreaXYCell", ...
    "HeightCell", ...
    "CoolantResistance", ...
    "AmbientResistance", ...
    "InterCellThermalResistance", ...
    "InterParallelAssemblyThermalResistance"];

for i = 1:numel(directNames)
    name = directNames(i);
    if isfield(master,char(name))
        safeSetBlockParam(blockPath,name,master.(char(name)));
    end
end

%% Extrapolation method is enum-backed and must not be copied as a
% human-readable string such as "Nearest".
if isfield(master,"ExtrapolationMethodCell")
    masterExtrapLabel = friendlyExtrapolationLabel( ...
        master.ExtrapolationMethodCell);
    extrapSet = safeSetEnumBlockParamByName( ...
        blockPath,"ExtrapolationMethodCell",masterExtrapLabel);

    if ~extrapSet
        error("ThermalPack:ExtrapolationEnumResolution", ...
            "Could not resolve the Simscape enum for Extrapolation Method during rebuild.");
    end
end

deviationNames = [ ...
    "BatteryCapacityCellPercentDeviation", ...
    "SOCBreakpointsCellPercentDeviation", ...
    "TemperatureBreakpointsCellPercentDeviation", ...
    "OpenCircuitVoltageThermalCellPercentDeviation", ...
    "VoltageRangeCellPercentDeviation", ...
    "ResistanceSOCBreakpointsCellPercentDeviation", ...
    "ResistanceTemperatureBreakpointsCellPercentDeviation", ...
    "R0ThermalCellPercentDeviation", ...
    "BatteryThermalMassCellPercentDeviation", ...
    "NumThermalModelsCellPercentDeviation", ...
    "ThermalConductivityZCellPercentDeviation", ...
    "CrossSectionalAreaXYCellPercentDeviation", ...
    "HeightCellPercentDeviation"];

for i = 1:numel(deviationNames)
    name = deviationNames(i);

    if isfield(master,char(name))
        resized = resizeDeviationExpression(master.(char(name)),N);
    else
        resized = sprintf("zeros([%d, 1])",N);
    end

    safeSetBlockParam(blockPath,name,resized);
end

%% Restore initialization specification/priority settings from the original.
stateModeNames = [ ...
    "socCell_specify","socCell_priority", ...
    "socCell_nominal_specify","socCell_nominal_value", ...
    "batteryVoltage_specify","batteryVoltage_priority", ...
    "batteryVoltage_nominal_specify","batteryVoltage_nominal_value", ...
    "batteryCurrent_specify","batteryCurrent_priority", ...
    "batteryCurrent_nominal_specify","batteryCurrent_nominal_value", ...
    "numCycles_specify","numCycles_priority", ...
    "numCycles_nominal_specify","numCycles_nominal_value", ...
    "batteryTemperature_specify","batteryTemperature_priority", ...
    "batteryTemperature_nominal_specify","batteryTemperature_nominal_value", ...
    "vParallelAssembly_specify","vParallelAssembly_priority", ...
    "vParallelAssembly_nominal_specify","vParallelAssembly_nominal_value", ...
    "socParallelAssembly_specify","socParallelAssembly_priority", ...
    "socParallelAssembly_nominal_specify","socParallelAssembly_nominal_value"];

for i = 1:numel(stateModeNames)
    name = stateModeNames(i);
    if isfield(master,char(name))
        safeSetBlockParam(blockPath,name,master.(char(name)));
    end
end

%% Adapt the original initialization expressions to the rebuilt topology.
cellStateNames = [ ...
    "socCell","batteryVoltage","batteryCurrent", ...
    "numCycles","batteryTemperature"];

for i = 1:numel(cellStateNames)
    name = cellStateNames(i);
    if isfield(master,char(name))
        expr = adaptRepmatCount(master.(char(name)),N);
        safeSetBlockParam(blockPath,name,expr);
    end
end

assemblyStateNames = ["vParallelAssembly","socParallelAssembly"];

for i = 1:numel(assemblyStateNames)
    name = assemblyStateNames(i);
    if isfield(master,char(name))
        expr = adaptRepmatCount(master.(char(name)),S);
        safeSetBlockParam(blockPath,name,expr);
    end
end
end

function expr = resizeDeviationExpression(masterExpr,N)
%% Evaluate only the trusted parameter expression read from the user's
% original local Simulink model, then resize it without inventing new
% non-zero deviations.

try
    original = str2num(char(masterExpr)); %#ok<ST2NM>
catch
    original = [];
end

if isempty(original)
    expr = sprintf("zeros([%d, 1])",N);
    return;
end

original = original(:);
resized = zeros(N,1);
count = min(N,numel(original));
resized(1:count) = original(1:count);
expr = mat2str(resized,16);
end

function exprOut = adaptRepmatCount(exprIn,newCount)
exprOut = string(exprIn);

%% The original generated block uses forms such as
pattern = '\d+\s*,\s*1\)\s*$';
replacement = sprintf('%d, 1)',newCount);
candidate = regexprep(exprOut,pattern,replacement);

if candidate == exprOut
%% Fallback for an unexpected expression: leave it unchanged rather
    % than silently fabricating a different physical initialization.
    candidate = exprOut;
end

exprOut = candidate;
end

%% Result extraction
function [KPI,Trace] = extractUIResults(out,cfg)
simlog = [];

try
    simlog = out.simlog;
catch
    try
        simlog = out.get("simlog");
    catch
    end
end

if isempty(simlog)
    error("simlog was not returned by the simulation.");
end

%% Cell-average temperature
cellSeries = simlog.Cylindrical_Cell_Module_Test ...
    .batteryTemperature.series;

Tcell_K = cellSeries.values("K");
tCell = cellSeries.time;
Tcell_K = reshape(Tcell_K,size(Tcell_K,1),[]);
Tcell_C = Tcell_K - 273.15;

TmaxCell = max(Tcell_C,[],2);

%% Pack-level statistics of the CELL-AVERAGE temperature signals.
% These feed the second Dashboard graph.
TmaxCellAverage_C = max(Tcell_C,[],2);
TmeanCellAverage_C = mean(Tcell_C,2,"omitnan");
TminCellAverage_C = min(Tcell_C,[],2);

%% Height-distributed nodes
firstNode = simlog.Cylindrical_Cell_Module_Test ...
    .Cylindrical_Cell_Assembly(1) ...
    .Cylindrical_Cell(1) ...
    .HDistributed(1).T;

tNodes = firstNode.series.time;

nodal_K = zeros(numel(tNodes),cfg.NodesPerCell,cfg.TotalCells);
rawCell = 1;

for a = 1:cfg.NumAssemblies
    assembly = simlog.Cylindrical_Cell_Module_Test ...
        .Cylindrical_Cell_Assembly(a);

    for c = 1:cfg.CellsPerAssembly
        for n = 1:cfg.NodesPerCell
            values_K = assembly.Cylindrical_Cell(c) ...
                .HDistributed(n).T.series.values("K");

            nodal_K(:,n,rawCell) = reshape(values_K,[],1);
        end
        rawCell = rawCell + 1;
    end
end

nodal_C = nodal_K - 273.15;

TcellMaxNode_C = squeeze(max(nodal_C,[],2));
TcellMinNode_C = squeeze(min(nodal_C,[],2));

[TmaxNodal,hottestByNode] = max(TcellMaxNode_C,[],2);
[TminNodal,~] = min(TcellMinNode_C,[],2);
deltaTNodal = TmaxNodal - TminNodal;

[peakNodeTemp,worstIndex] = max(TmaxNodal);
worstCell = hottestByNode(worstIndex);
[~,worstNode] = max(nodal_C(worstIndex,:,worstCell));

safetyMargin = cfg.Tlimit_C - TmaxNodal;

worstState = 1;
if any(TmaxNodal >= cfg.Tcritical_C)
    worstState = 3;
elseif any(TmaxNodal >= cfg.Twarning_C)
    worstState = 2;
end

if worstState == 1
    worstStatus = "GREEN";
elseif worstState == 2
    worstStatus = "YELLOW";
else
    worstStatus = "RED";
end

KPI.PeakTmaxCell_C = max(TmaxCell,[],"omitnan");
KPI.PeakTmaxNodal_C = peakNodeTemp;
KPI.MaxDeltaTNodal_C = max(deltaTNodal,[],"omitnan");
KPI.MinSafetyMargin_C = min(safetyMargin,[],"omitnan");
KPI.WorstCell = worstCell;
KPI.WorstNode = worstNode;
KPI.WorstTime_s = tNodes(worstIndex);
KPI.WorstStatus = worstStatus;

Trace.tCell = tCell;
Trace.Tcell_C = Tcell_C;
Trace.TmaxCellAverage_C = TmaxCellAverage_C;
Trace.TmeanCellAverage_C = TmeanCellAverage_C;
Trace.TminCellAverage_C = TminCellAverage_C;
Trace.tNodes = tNodes;
Trace.nodal_C = nodal_C;
Trace.TmaxNodal_C = TmaxNodal;
Trace.TminNodal_C = TminNodal;
Trace.deltaTNodal_C = deltaTNodal;
end