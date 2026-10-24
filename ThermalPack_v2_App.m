function varargout = ThermalPack_v2_App(action)
% THERMALPACK VERSION 2.0
varargout = cell(1,nargout);
if nargin > 0
    if ~strcmpi(string(action),"selftest")
        error("ThermalPack:Action","Use no argument to open the app, or 'selftest' to check optimization helpers.");
    end
    report = thermalPackOperatingSelfTest();
    if nargout > 0
        varargout{1} = report;
    else
        disp(report);
    end
    return;
end

baseMdl = "Thermal_Model_v5";
mdl     = "Thermal_Model_v5_UI";

%% Default operating profile
% Columns are time (s) and battery current (A); repeated times create steps.
CurrentProfileDefault = [ ...
      0,   80; ...
    300,   80; ...
    300,    0; ...
    600,    0; ...
    600,  -80; ...
    900,  -80];

%% Create the non-destructive UI working model
% Regenerate the working model from the protected master at every launch.
baseFile = which(baseMdl + ".slx");

if isempty(baseFile)
    tempFig = uifigure;
    uialert(tempFig, ...
        "Thermal_Model_v5.slx was not found in the current folder or MATLAB path.", ...
        "ThermalPack");
    delete(tempFig);
    return;
end

baseFolder = string(fileparts(baseFile));
workingFile = fullfile(baseFolder,mdl + ".slx");

%% Project-local Simscape and Battery Builder libraries
% Add the library root before loading the master model.
thermalPackLibraryRoot = fullfile( ...
    baseFolder, ...
    "Thermal_Pack_Libraries");

thermalPackComponentLibraryFile = fullfile( ...
    thermalPackLibraryRoot, ...
    "ThermalPackComponents_lib.slx");
thermalPackComponentLibraryModel = "ThermalPackComponents_lib";

baselineBatteryLibraryFile = fullfile( ...
    thermalPackLibraryRoot, ...
    "Cylindrical_Cell_Module_v2_5_lib.slx");
baselineBatteryLibraryModel = "Cylindrical_Cell_Module_v2_5_lib";
baselineBatteryPackageFolder = fullfile( ...
    thermalPackLibraryRoot, ...
    "+Cylindrical_Cell_Module_v2_5");
baselineBatterySource = ...
    "Cylindrical_Cell_Module_v2_5.Cylindrical_Cell_Module_Test";

if ~isfolder(thermalPackLibraryRoot)
    tempFig = uifigure;
    uialert(tempFig, ...
        "Thermal_Pack_Libraries was not found beside Thermal_Model_v5.slx.", ...
        "ThermalPack — Library Missing");
    delete(tempFig);
    return;
end

% Add the parent folder containing the +package namespaces.
if ~contains(path,char(thermalPackLibraryRoot))
    addpath(char(thermalPackLibraryRoot));
end

% Refresh package discovery after adding the generated Simscape sources.
rehash;
rehash toolboxcache;

%% Load ThermalPack custom isolation library
if ~isfile(thermalPackComponentLibraryFile)
    tempFig = uifigure;
    uialert(tempFig, ...
        "ThermalPackComponents_lib.slx was not found in Thermal_Pack_Libraries.", ...
        "ThermalPack — Library Missing");
    delete(tempFig);
    return;
end

if ~bdIsLoaded(thermalPackComponentLibraryModel)
    try
        load_system(char(thermalPackComponentLibraryFile));
    catch MElibrary
        tempFig = uifigure;
        uialert(tempFig, ...
            "Could not load ThermalPackComponents_lib:" + newline + ...
            string(MElibrary.message), ...
            "ThermalPack — Library Load Error");
        delete(tempFig);
        return;
    end
end

%% Load the baseline Battery Builder library
% Use the project-local copy first, then any path-visible copy.
if ~isfile(baselineBatteryLibraryFile)
    resolvedBaselineLibrary = which(baselineBatteryLibraryModel + ".slx");
    if ~isempty(resolvedBaselineLibrary)
        baselineBatteryLibraryFile = string(resolvedBaselineLibrary);
    end
end

if ~isfile(baselineBatteryLibraryFile)
    tempFig = uifigure;
    uialert(tempFig, ...
        "Cylindrical_Cell_Module_v2_5_lib.slx was not found in Thermal_Pack_Libraries or on the MATLAB path.", ...
        "ThermalPack — Battery Library Missing");
    delete(tempFig);
    return;
end

if ~bdIsLoaded(baselineBatteryLibraryModel)
    try
        load_system(char(baselineBatteryLibraryFile));
    catch MEbatteryLibrary
        tempFig = uifigure;
        uialert(tempFig, ...
            "Could not load Cylindrical_Cell_Module_v2_5_lib:" + newline + ...
            string(MEbatteryLibrary.message), ...
            "ThermalPack — Battery Library Load Error");
        delete(tempFig);
        return;
    end
end

rehash;

sourcePath = which(char(baselineBatterySource));
if isempty(sourcePath)
    tempFig = uifigure;
    uialert(tempFig, ...
        "MATLAB cannot resolve the generated Simscape source " + ...
        baselineBatterySource + ". Verify that Thermal_Pack_Libraries contains +Cylindrical_Cell_Module_v2_5 and restart MATLAB if the library was just generated.", ...
        "ThermalPack — Battery Source Missing");
    delete(tempFig);
    return;
end

if bdIsLoaded(mdl)
    close_system(mdl,0);
end

if ~bdIsLoaded(baseMdl)
    load_system(baseFile);
end

if isfile(workingFile)
    try
        delete(workingFile);
    catch MEdelete
        tempFig = uifigure;
        uialert(tempFig, ...
            "Could not refresh Thermal_Model_v5_UI.slx:" + newline + ...
            string(MEdelete.message), ...
            "ThermalPack");
        delete(tempFig);
        return;
    end
end

save_system(baseMdl,workingFile);
close_system(baseMdl,0);
load_system(workingFile);

% ThermalPack default solver.
% Apply this only to the non-destructive working model; never modify V5 master.
set_param(mdl, ...
    "SolverType","Variable-step", ...
    "Solver","ode23t");
save_system(mdl);

batteryBlock = mdl + "/Cylindrical_Cell_Module_Test";

% V5 stores each normal cooling network inside a dedicated subsystem.
bottomCoolingSubsystem = mdl + "/Bottom Cooling Plate";
topCoolingSubsystem    = mdl + "/Top Cooling Plate";

bottomPlateBlock = bottomCoolingSubsystem + "/Parallel Channels";
topPlateBlock    = topCoolingSubsystem + "/Parallel Channels1";

bottomIsolationBlock = bottomCoolingSubsystem + "/Bottom Cooling Isolation";
topIsolationBlock    = topCoolingSubsystem + "/Top Cooling Isolation";

bottomFlowSourceBlock = bottomCoolingSubsystem + "/Flow Rate Source" + newline + "(TL)";
topFlowSourceBlock    = topCoolingSubsystem + "/Flow Rate Source" + newline + "(TL)1";

bottomInletReservoirBlock  = bottomCoolingSubsystem + "/Reservoir (TL)1";
bottomOutletReservoirBlock = bottomCoolingSubsystem + "/Reservoir (TL)";
topInletReservoirBlock     = topCoolingSubsystem + "/Reservoir (TL)3";
topOutletReservoirBlock    = topCoolingSubsystem + "/Reservoir (TL)2";

% Serpentine remains structural/programmatic because SP is not available for
% every battery architecture.
serpentineIsolationBlock = mdl + "/Serpentine Cooling Isolation";
serpentinePlateBlock = mdl + "/Serpentine Parallel Channels";
serpentineFlowSourceBlock = mdl + "/Serpentine Flow Rate Source (TL)";
serpentineInletReservoirBlock = mdl + "/Serpentine Reservoir Inlet (TL)";
serpentineOutletReservoirBlock = mdl + "/Serpentine Reservoir Outlet (TL)";
serpentineTLPropertiesBlock = mdl + "/Serpentine Thermal Liquid Properties (TL)";

% V5 permanently contains all four native side-cooling networks.
sideBoundaryNames = ["Xmin","Xmax","Ymin","Ymax"];
sideCoolingSubsystems = mdl + "/" + sideBoundaryNames + " Cooling Plate";

sideIsolationBlocks = sideCoolingSubsystems + "/" + ...
    sideBoundaryNames + " Cooling Isolation";

sidePlateBlocks = sideCoolingSubsystems + "/Parallel Channels1";
sideFlowSourceBlocks = sideCoolingSubsystems + ...
    "/Flow Rate Source" + newline + "(TL)1";
sideOutletReservoirBlocks = sideCoolingSubsystems + "/Reservoir (TL)2";
sideInletReservoirBlocks  = sideCoolingSubsystems + "/Reservoir (TL)3";
sideTLPropertiesBlocks = sideCoolingSubsystems + ...
    "/Thermal Liquid" + newline + "Properties (TL)1";

% Compatibility aliases point at the currently selected permanent side.
% The permanent-side logic below updates all four branches explicitly.
selectedSideIndex = 1;
if isempty(selectedSideIndex)
    selectedSideIndex = 1;
end
sideIsolationBlock = sideIsolationBlocks(selectedSideIndex);
sidePlateBlock = sidePlateBlocks(selectedSideIndex);
sideFlowSourceBlock = sideFlowSourceBlocks(selectedSideIndex);
sideInletReservoirBlock = sideInletReservoirBlocks(selectedSideIndex);
sideOutletReservoirBlock = sideOutletReservoirBlocks(selectedSideIndex);
sideTLPropertiesBlock = sideTLPropertiesBlocks(selectedSideIndex);

% Keep plateBlock as a bottom-plate alias for legacy helper/UI code that
% reads the common plate material/channel defaults.
plateBlock = bottomPlateBlock;

if getSimulinkBlockHandle(batteryBlock) <= 0
    error("ThermalPack:BatteryBlockMissing", ...
        "Battery block '%s' was not found.",batteryBlock);
end

if getSimulinkBlockHandle(bottomPlateBlock) <= 0 || ...
        getSimulinkBlockHandle(topPlateBlock) <= 0
    error("ThermalPack:CoolingPlateMissing", ...
        "Thermal_Model_v5 must contain both external Parallel Channels blocks: 'Parallel Channels' (bottom) and 'Parallel Channels1' (top).");
end

if getSimulinkBlockHandle(topIsolationBlock) <= 0 || ...
        getSimulinkBlockHandle(bottomIsolationBlock) <= 0
    error("ThermalPack:CoolingIsolationMissing", ...
        "Thermal_Model_v5 must permanently contain both isolation blocks: 'Top Cooling Isolation' and 'Bottom Cooling Isolation'.");
end

for kSideMaster = 1:numel(sideBoundaryNames)
    if getSimulinkBlockHandle(sideIsolationBlocks(kSideMaster)) <= 0 || ...
            getSimulinkBlockHandle(sidePlateBlocks(kSideMaster)) <= 0 || ...
            getSimulinkBlockHandle(sideFlowSourceBlocks(kSideMaster)) <= 0
        error("ThermalPack:SideCoolingMasterMissing", ...
            "Thermal_Model_v5 must permanently contain the %s side cooling subsystem, isolation block, Parallel Channels block, and TL loop.", ...
            sideBoundaryNames(kSideMaster));
    end
end

%% Capture the v5 battery as the master physics definition
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
state.CellFormat = "Cylindrical";

% Keep separate format-specific GUI values so switching formats does not
% overwrite the user's settings for the other cell format.
state.Cylindrical = struct( ...
    'P',4, ...
    'S',3, ...
    'Diameter_mm',20, ...
    'Height_mm',70, ...
    'Mass_kg',0.1, ...
    'Capacity_Ah',masterCapacity_Ah, ...
    'Energy_Wh',18, ...
    'Topology',"Square", ...
    'Rows',1, ...
    'StackingAxis',"Y", ...
    'ThermalMass_J_K',masterThermalMass_J_K, ...
    'ConductivityZ_W_mK',15, ... % ThermalPack cylindrical baseline
    'ThermalAreaMode',"Automatic", ...
    'ThermalArea_m2',pi*(20e-3/2)^2, ...
    'CustomThermalArea_m2',masterCrossSection_m2);

% Prismatic v2.0 engineering baseline. Electrical and thermal values below
% are deliberately stored separately from the cylindrical master so each
% format can be edited without overwriting the other format's settings.
state.Prismatic = struct( ...
    'P',4, ...
    'S',2, ...
    'Length_mm',148, ...
    'Thickness_mm',27, ...
    'Height_mm',91, ...
    'Mass_kg',1.1, ...
    'Capacity_Ah',50, ...
    'Energy_Wh',180, ...
    'Topology',"SingleStack", ...
    'Rows',1, ...
    'StackingAxis',"Y", ...
    'ThermalMass_J_K',1088, ...
    'ConductivityZ_W_mK',23.36, ...
    'ThermalAreaMode',"Automatic", ...
    'ThermalArea_m2',(148e-3)*(27e-3), ...
    'CustomThermalArea_m2',(148e-3)*(27e-3));

% Pouch v2.0 engineering baseline. OCV intentionally remains identical to
% the master lookup table; only the provisional pouch R0 and pouch-specific
% geometry/thermal parameters differ.
state.Pouch = struct( ...
    'P',4, ...
    'S',2, ...
    'Length_mm',160, ...
    'Thickness_mm',7.25, ...
    'Height_mm',227, ...
    'TabLocation',"Standard", ...
    'TabWidth_mm',40, ...
    'TabHeight_mm',30, ...
    'Mass_kg',0.496, ...
    'Capacity_Ah',20, ...
    'Energy_Wh',65, ...
    'Topology',"SingleStack", ...
    'Rows',1, ...
    'StackingAxis',"Y", ...
    'ThermalMass_J_K',496, ...
    'ConductivityZ_W_mK',18.2, ...
    'ThermalAreaMode',"Automatic", ...
    'ThermalArea_m2',(160e-3)*(7.25e-3), ...
    'CustomThermalArea_m2',(160e-3)*(7.25e-3));

% Format-specific cell electrical data. The initial Prismatic OCV data use
% the master curve as a provisional baseline, while R0 starts from a flat
% 0.8 mOhm table until a cell-specific SOC/temperature map is supplied.
state.Cylindrical.ExtrapolationMethod = masterExtrapolation;
state.Cylindrical.VoltageRange_V = masterVoltageRange_V(:).';
state.Cylindrical.OCVSOCBreakpoints = masterOCVSOC(:).';
state.Cylindrical.OCVTemperature_C = masterOCVTemp_K(:).' - 273.15;
state.Cylindrical.OCVTable_V = masterOCVTable_V;
state.Cylindrical.ResistanceSOCBreakpoints = masterResistanceSOC(:).';
state.Cylindrical.ResistanceTemperature_C = masterResistanceTemp_K(:).' - 273.15;
state.Cylindrical.R0Table_Ohm = masterR0Table_Ohm;
% Optional electrochemical dynamics. Disabled by default. RC lookup tables
% share the R0 SOC/temperature grid; entropy uses the OCV SOC grid.
state.Cylindrical.PolarizationModel = "Disabled";
state.Cylindrical.R1Table_Ohm = zeros(size(masterR0Table_Ohm));
state.Cylindrical.Tau1Table_s = ones(size(masterR0Table_Ohm));
state.Cylindrical.R2Table_Ohm = zeros(size(masterR0Table_Ohm));
state.Cylindrical.Tau2Table_s = ones(size(masterR0Table_Ohm));
state.Cylindrical.EntropicHeatEnabled = false;
state.Cylindrical.EntropicCoefficient_mV_K = ...
    zeros(1,numel(state.Cylindrical.OCVSOCBreakpoints));
state.Cylindrical.R0Deviation_pct = masterR0Deviation_pct(:);
state.Cylindrical.ThermalMassDeviation_pct = masterThermalMassDeviation_pct(:);
state.Cylindrical.ThermalConductivityDeviation_pct = masterConductivityDeviation_pct(:);

state.Prismatic.ExtrapolationMethod = masterExtrapolation;
state.Prismatic.VoltageRange_V = masterVoltageRange_V(:).';
state.Prismatic.OCVSOCBreakpoints = masterOCVSOC(:).';
state.Prismatic.OCVTemperature_C = masterOCVTemp_K(:).' - 273.15;
state.Prismatic.OCVTable_V = masterOCVTable_V;
state.Prismatic.ResistanceSOCBreakpoints = masterResistanceSOC(:).';
state.Prismatic.ResistanceTemperature_C = masterResistanceTemp_K(:).' - 273.15;
state.Prismatic.R0Table_Ohm = 8e-4*ones(size(masterR0Table_Ohm));
state.Prismatic.PolarizationModel = "Disabled";
state.Prismatic.R1Table_Ohm = zeros(size(masterR0Table_Ohm));
state.Prismatic.Tau1Table_s = ones(size(masterR0Table_Ohm));
state.Prismatic.R2Table_Ohm = zeros(size(masterR0Table_Ohm));
state.Prismatic.Tau2Table_s = ones(size(masterR0Table_Ohm));
state.Prismatic.EntropicHeatEnabled = false;
state.Prismatic.EntropicCoefficient_mV_K = ...
    zeros(1,numel(state.Prismatic.OCVSOCBreakpoints));
state.Prismatic.R0Deviation_pct = zeros(state.Prismatic.P*state.Prismatic.S,1);
state.Prismatic.ThermalMassDeviation_pct = zeros(state.Prismatic.P*state.Prismatic.S,1);
state.Prismatic.ThermalConductivityDeviation_pct = zeros(state.Prismatic.P*state.Prismatic.S,1);

state.Pouch.ExtrapolationMethod = masterExtrapolation;
state.Pouch.VoltageRange_V = masterVoltageRange_V(:).';
state.Pouch.OCVSOCBreakpoints = masterOCVSOC(:).';
state.Pouch.OCVTemperature_C = masterOCVTemp_K(:).' - 273.15;
state.Pouch.OCVTable_V = masterOCVTable_V;
state.Pouch.ResistanceSOCBreakpoints = masterResistanceSOC(:).';
state.Pouch.ResistanceTemperature_C = masterResistanceTemp_K(:).' - 273.15;
state.Pouch.R0Table_Ohm = 2e-3*ones(size(masterR0Table_Ohm));
state.Pouch.PolarizationModel = "Disabled";
state.Pouch.R1Table_Ohm = zeros(size(masterR0Table_Ohm));
state.Pouch.Tau1Table_s = ones(size(masterR0Table_Ohm));
state.Pouch.R2Table_Ohm = zeros(size(masterR0Table_Ohm));
state.Pouch.Tau2Table_s = ones(size(masterR0Table_Ohm));
state.Pouch.EntropicHeatEnabled = false;
state.Pouch.EntropicCoefficient_mV_K = ...
    zeros(1,numel(state.Pouch.OCVSOCBreakpoints));
state.Pouch.R0Deviation_pct = zeros(state.Pouch.P*state.Pouch.S,1);
state.Pouch.ThermalMassDeviation_pct = zeros(state.Pouch.P*state.Pouch.S,1);
state.Pouch.ThermalConductivityDeviation_pct = zeros(state.Pouch.P*state.Pouch.S,1);

% Active geometry values. Diameter_mm is retained for the existing
% cylindrical renderer; Length_mm/Thickness_mm are used by Prismatic/Pouch.
state.Diameter_mm = state.Cylindrical.Diameter_mm;
state.Length_mm = state.Prismatic.Length_mm;
state.Thickness_mm = state.Prismatic.Thickness_mm;
state.Height_mm = state.Cylindrical.Height_mm;
state.InterCellGap_mm = 1;
state.InterAssemblyGap_mm = 1;
state.Topology = state.Cylindrical.Topology;
state.Rows = state.Cylindrical.Rows;
state.ParallelAssemblyStackingAxis = state.Cylindrical.StackingAxis;
state.ModuleStackingAxis = "X";
state.MassFactor = 1.0;
state.InterCellHeatTransfer = "Enabled";
state.CoolingPlateMode = "Bottom Cooling Plate";

% Cooling-interface switch resistance. The battery's normal Cell -> plate
% resistance remains inside the generated battery block. These two external
% array resistances only activate/isolate the Top and Bottom plate surfaces.
state.CoolingSwitchOnRth_K_W = 1e-6;
state.NoCoolingRth_K_W = 1e9;
state.LoadProfile = "Custom";

% Normal simulation thermal limit used for the Safety Margin KPI.
% This is independent of the Optimization-tab feasibility limit.
state.ThermalLimit_C = 60;
state.LastValidLoadProfile = "Custom";
state.CustomCurrentProfile = CurrentProfileDefault;
state.Solver = "ode23t";

%% Active cell electrical data (starts with Cylindrical settings)
state.ExtrapolationMethod = state.Cylindrical.ExtrapolationMethod;
state.VoltageRange_V = state.Cylindrical.VoltageRange_V;
state.OCVSOCBreakpoints = state.Cylindrical.OCVSOCBreakpoints;
state.OCVTemperature_C = state.Cylindrical.OCVTemperature_C;
state.OCVTable_V = state.Cylindrical.OCVTable_V;
state.ResistanceSOCBreakpoints = state.Cylindrical.ResistanceSOCBreakpoints;
state.ResistanceTemperature_C = state.Cylindrical.ResistanceTemperature_C;
state.R0Table_Ohm = state.Cylindrical.R0Table_Ohm;
state.PolarizationModel = state.Cylindrical.PolarizationModel;
state.R1Table_Ohm = state.Cylindrical.R1Table_Ohm;
state.Tau1Table_s = state.Cylindrical.Tau1Table_s;
state.R2Table_Ohm = state.Cylindrical.R2Table_Ohm;
state.Tau2Table_s = state.Cylindrical.Tau2Table_s;
state.EntropicHeatEnabled = state.Cylindrical.EntropicHeatEnabled;
state.EntropicCoefficient_mV_K = state.Cylindrical.EntropicCoefficient_mV_K;

%% Active per-cell percentage variation
state.R0Deviation_pct = state.Cylindrical.R0Deviation_pct;
state.ThermalMassDeviation_pct = state.Cylindrical.ThermalMassDeviation_pct;
state.ThermalConductivityDeviation_pct = state.Cylindrical.ThermalConductivityDeviation_pct;

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

% Dual-plate flow accounting.
% Total Flow mode treats the main coolant-flow field as the total system
% flow and allocates it between top and bottom using TopFlowShare_pct.
% Independent Flow mode exposes separate top and bottom loop flow rates.
state.FlowAllocationMode = "Total Flow";
state.TopFlowShare_pct = 50;
state.TopMassFlowRate_kg_s = 0.010;
state.BottomMassFlowRate_kg_s = 0.010;
state.TopVolumetricFlowRate_m3_s = 0;
state.BottomVolumetricFlowRate_m3_s = 0;

%% Cooling plate architecture
% The two v4 block locations remain fixed in the working model. The GUI
% resolves the installed Simscape Battery library block dynamically before
% replacing each slot. This avoids relying on release-specific capitalization
% or hierarchy details for Parallel / U-shaped / Edge cooling blocks.
state.CoolingPlateType = "Parallel Channels";

%% Native Battery Builder serpentine cooling (R2024a+)
% Serpentine is a distinct cooling architecture. It is available only for
% cylindrical cells in hexagonal topology and uses the generated SP thermal
% interface. The v5 master remains unchanged. After an SP-capable rebuild,
% The app creates a dedicated Parallel Channels + Thermal Liquid circuit in
% Thermal_Model_v5_UI and switches it with its own array isolation Rth.
state.SerpentineMode = "SingleSidedAlongStackingAxis";
state.SerpentineCircumferenceFraction = 0.25;
state.SerpentineHeightFraction = 0.60;
state.SerpentineContactRth_K_W = 25;
state.SerpentineThermalNodeCount = [];
state.SerpentineThermalNodeLocations = [];
state.SerpentineThermalNodeDimensions = [];
state.HasSerpentinePort = false;
state.SerpentineBranchCreated = false;

%% Native Battery Builder vectorized side cooling
% Cylindrical, Prismatic and Pouch formats use the native side boundaries. The cell-height
% heat-exchange fraction applies to all three formats. For Cylindrical cells,
% the side-contact defaults remain the manually validated ThermalPack case:
% full cell height and one-half circumference. The circumference fraction is
% cylindrical-only. Prismatic and Pouch obtain their second local side-node
% dimension directly from Battery Builder native face geometry. V5 keeps all
% four side ports permanently, so changing Xmin/Xmax/Ymin/Ymax is a runtime
% isolation switch. Only geometry/architecture changes require a rebuild.
state.SideBoundary = "Xmin";
state.SideHeightFraction = 1.00;
state.SideCircumferenceFraction = 0.50;
state.SideContactRth_K_W = 25;
state.SideThermalNodeCount = [];
state.SideThermalNodeLocations = [];
state.SideThermalNodeDimensions = [];
state.SideBoundaryCells = [];
state.HasSidePort = true;
state.SideBranchCreated = true;
state.BuiltSideBoundary = "All";

%% Forced-air cooling — geometry-aware Uniform AmbH + Progressive Gas
% The user supplies only the physical operating boundary conditions plus the
% in-plane airflow axis:
%   - approach/inlet air velocity
%   - inlet air temperature
%   - absolute pressure
%   - airflow axis X or Y
%
% ThermalPack then obtains dry-air properties automatically and inspects the
% rebuilt Battery Builder X-Y cell geometry to choose the supported
% convection family. For Cylindrical cells this distinguishes isolated/single
% row, aligned tube-bank and staggered tube-bank cross-flow. For Prismatic
% and Pouch cells, tangential broad-face flow is represented by either an
% external flat-plate or a parallel rectangular-channel model, depending on
% whether the rebuilt geometry creates repeated transverse air gaps.
%
% Two reduced-order forced-air architectures are supported:
%   1) Uniform AmbH  — one bulk-air temperature for the whole battery.
%   2) Progressive Gas — the rebuilt battery is partitioned into electrical/
%      airflow intersections and coupled to one serial Simscape Gas chamber
%      per detected flowwise column. The Gas network is generated inside a
%      subsystem in Thermal_Model_v5_UI.slx; Thermal_Model_v5 remains untouched.
%
% X/Y selects the airflow axis. Progressive Gas uses the fixed positive-axis
% direction: X = Xmin→Xmax and Y = Ymin→Ymax.
state.ForcedAirVelocity_m_s = 2.0;
state.ForcedAirTemperature_C = 25.0;
state.ForcedAirPressure_Pa = 101325;
state.ForcedAirAxis = "X";
state.ForcedAirModel = "Progressive Gas";
% Physical clearance from the outermost cell surface to each transverse duct
% wall. One value is applied symmetrically on both sides of the array.
state.ForcedAirWallClearance_mm = 4.0;
state.ForcedAirExposedAreaFraction = 1.0;
% Optional explicit X-Y cell-centre geometry. This is an input-geometry override,
% not a heat-transfer-physics override: the normal geometry detector, AUTO
% D/Dh selector, tube-bank correlations and Progressive Gas builder consume
% these coordinates exactly as they consume Battery Builder coordinates.
% It is disabled during normal app operation and enabled only when a supported
% custom/validation layout (for example Fan staggered) is requested.
state.ForcedAirCustomGeometryEnabled = false;
state.ForcedAirCustomCellCentres_m = zeros(0,2);
state.ForcedAirCustomGeometryLabel = "";
% Cylindrical Reynolds-number characteristic-length selector.
% AUTO is the normal generalized ThermalPack mode. It does not blend D and
% Dh. It classifies the rebuilt bank geometry, then selects one basis:
%   Confined compact repeated passage -> Dh for Re, D for Nu->h
%   Compact / transitional / conventional / sparse -> D for Re and Nu->h
% Manual values are retained as hidden engineering overrides for debugging.
state.ForcedAirCylindricalReLengthMode = "Auto";
state.ForcedAirCylindricalCompactPitchLimit = 1.25;
state.ForcedAirCylindricalTransitionPitchLimit = 1.40;
state.ForcedAirCylindricalWallRatioLimit = 2.0;
state.ForcedAirCylindricalMinStreamwiseColumnsForDh = 4;
% Future fifth gate: retained as metadata only. It does NOT block Dh yet.
state.ForcedAirDhCorrelationValidationRequired = false; % Reserved backend validation gate.
state.ForcedAirDhCorrelationValidationStatus = "Not Applied";
state.ForcedAirDhCorrelationValidationApplied = false;

% Geometry/correlation metadata are populated by the backend calculation.
state.ForcedAirArrangement = "";
state.ForcedAirCorrelation = "";
state.ForcedAirGeometrySource = "";
state.ForcedAirEffectiveVelocity_m_s = NaN;
state.ForcedAirCharacteristicLength_m = NaN;
state.ForcedAirHydraulicDiameter_m = NaN;
state.ForcedAirNusseltLength_m = NaN;
state.ForcedAirTransversePitch_m = NaN;
state.ForcedAirLongitudinalPitch_m = NaN;
state.ForcedAirColumns = NaN;
state.ForcedAirRows = NaN;
state.ForcedAirArrayTransverseWidth_m = NaN;
state.ForcedAirDuctWidth_m = NaN;
state.ForcedAirDuctHeight_m = NaN;
state.ForcedAirFlowArea_m2 = NaN;
state.ForcedAirVolumetricFlow_m3_s = NaN;
state.ForcedAirMassFlow_kg_s = NaN;
state.ForcedAirRepresentativeSegmentLength_m = NaN;
state.ForcedAirRepresentativeGasVolume_m3 = NaN;
% Cylindrical AUTO-classifier metadata.
state.ForcedAirCylindricalRegime = "";
state.ForcedAirCylindricalReLengthSelected = "";
state.ForcedAirCylindricalSelectionSource = "";
state.ForcedAirCylindricalPitchRatioT = NaN;
state.ForcedAirCylindricalPitchRatioL = NaN;
state.ForcedAirCylindricalWallRatioLeft = NaN;
state.ForcedAirCylindricalWallRatioRight = NaN;
state.ForcedAirCylindricalPassageGap_m = NaN;
state.ForcedAirCylindricalCandidateDh_m = NaN;
state.ForcedAirCylindricalDhEligible = false;
state.ForcedAirCylindricalIsCompact = false;
state.ForcedAirCylindricalIsTransitional = false;
state.ForcedAirCylindricalIsWallBounded = false;
state.ForcedAirCylindricalIsRepeated = false;

% Progressive-Gas generated-model bookkeeping. Paths are regenerated on every
% structural battery rebuild and never written into the V5 master.
state.ProgressiveForcedAirBuilt = false;
state.ProgressiveForcedAirSubsystem = "";
state.ProgressiveForcedAirSegmentBlocks = strings(0,1);
state.ProgressiveForcedAirSegmentNames = strings(0,1);
state.ProgressiveForcedAirSegmentCellIDs = cell(0,1);
state.ProgressiveForcedAirSegmentSeriesGroup = zeros(0,1);
state.ProgressiveForcedAirSegmentPhysicalGroup = zeros(0,1);
state.ProgressiveForcedAirSegmentAirOrder = zeros(0,1);
state.ProgressiveForcedAirChamberBlocks = strings(0,1);
state.ProgressiveForcedAirChamberPhysicalGroups = zeros(0,1);
state.ProgressiveForcedAirSegmentLengths_m = zeros(0,1);
state.ProgressiveForcedAirGasVolumes_m3 = zeros(0,1);
state.ProgressiveForcedAirFlowSourceBlock = "";
state.ProgressiveForcedAirMassFlowCommandBlock = "";
state.ProgressiveForcedAirInletReservoirBlock = "";
state.ProgressiveForcedAirOutletReservoirBlock = "";
state.ProgressiveForcedAirGasPropertiesBlock = "";
state.ProgressiveForcedAirGeneratedLibraries = strings(0,1);

% Calculate the default 4P x 3S square cylindrical case from the configured
% geometry. Before the first Battery Builder rebuild, the backend uses the
% app's configured geometry; after rebuild it prefers the actual generated
% thermal-node centre coordinates.
forcedAirDefault = forcedAirGeneralCalculation( ...
    state.ForcedAirVelocity_m_s, ...
    state.ForcedAirTemperature_C, ...
    state.ForcedAirPressure_Pa, ...
    state.ForcedAirAxis, ...
    state.ForcedAirWallClearance_mm);

state.ForcedAirDensity_kg_m3 = forcedAirDefault.rho_kg_m3;
state.ForcedAirDynamicViscosity_Pa_s = forcedAirDefault.mu_Pa_s;
state.ForcedAirConductivity_W_mK = forcedAirDefault.k_W_mK;
state.ForcedAirSpecificHeat_J_kgK = forcedAirDefault.cp_J_kgK;
state.ForcedAirPrandtl = forcedAirDefault.Pr;
state.ForcedAirReynolds = forcedAirDefault.Re;
state.ForcedAirNusselt = forcedAirDefault.Nu;
state.ForcedAirH_W_m2K = forcedAirDefault.h_W_m2K;
state.ForcedAirAreaPerCell_m2 = forcedAirDefault.Aeff_m2;
state.ForcedAirAmbientRth_K_W = forcedAirDefault.Rambient_K_W;
state.ForcedAirArrangement = forcedAirDefault.Arrangement;
state.ForcedAirCorrelation = forcedAirDefault.Correlation;
state.ForcedAirGeometrySource = forcedAirDefault.GeometrySource;
state.ForcedAirEffectiveVelocity_m_s = forcedAirDefault.Veffective_m_s;
state.ForcedAirCharacteristicLength_m = forcedAirDefault.Lc_m;
state.ForcedAirHydraulicDiameter_m = forcedAirDefault.Dh_m;
state.ForcedAirNusseltLength_m = forcedAirDefault.NuLength_m;
state.ForcedAirTransversePitch_m = forcedAirDefault.ST_m;
state.ForcedAirLongitudinalPitch_m = forcedAirDefault.SL_m;
state.ForcedAirColumns = forcedAirDefault.Columns;
state.ForcedAirRows = forcedAirDefault.Rows;
state.ForcedAirArrayTransverseWidth_m = forcedAirDefault.ArrayTransverseWidth_m;
state.ForcedAirDuctWidth_m = forcedAirDefault.DuctWidth_m;
state.ForcedAirDuctHeight_m = forcedAirDefault.DuctHeight_m;
state.ForcedAirFlowArea_m2 = forcedAirDefault.FlowArea_m2;
state.ForcedAirVolumetricFlow_m3_s = forcedAirDefault.VolumetricFlow_m3_s;
state.ForcedAirMassFlow_kg_s = forcedAirDefault.MassFlow_kg_s;
state.ForcedAirRepresentativeSegmentLength_m = forcedAirDefault.SegmentLength_m;
state.ForcedAirRepresentativeGasVolume_m3 = forcedAirDefault.RepresentativeGasVolume_m3;

state.LastNonSerpentineCoolingMode = "Bottom Cooling Plate";
state.LastNonSerpentineCoolingPlateType = state.CoolingPlateType;

% Type-specific design defaults. Parallel Channels retains the current
% ThermalPack v5 values. U-Shaped and Edge defaults follow the corresponding
% Simscape Battery block defaults and remain user-editable.
state.UShapedChannelPartitions = 1;
state.UShapedChannelThickness_mm = 5;
state.UShapedPartitionWidth_mm = 5;

state.EdgeCoolingSelection = ...
    "Edge cooling along Y axis at X = Xmin";
state.EdgeChannelHydraulicDiameter_mm = 5;
state.EdgeChannelArea_mm2 = 20;

%% Cooling plate common settings
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

%% Format-specific cooling-plate discretization defaults.
% Cylindrical preserves the existing master-model discretization.
% The Prismatic and Pouch 4P x 2S baselines use a 2 x 4 plate
% discretization so the eight thermal plate regions align naturally with
% the two-by-four cell footprint. Users can still edit these values in Cooling Plate Settings.
state.Cylindrical.PlatePartitionsX = state.PlatePartitionsX;
state.Cylindrical.PlatePartitionsY = state.PlatePartitionsY;
state.Prismatic.PlatePartitionsX = 2;
state.Prismatic.PlatePartitionsY = 4;
state.Pouch.PlatePartitionsX = 2;
state.Pouch.PlatePartitionsY = 4;

state.GeneratedLibrary = "";
state.GeneratedModuleObject = [];

%% Geometry captured directly from Battery Builder during REBUILD BATTERY.
% ThermalNodes.Bottom locations are centre coordinates of the battery
% contact regions. Dimensions and locations are passed unchanged to the
% Parallel Channels block; ThermalPack does not hand-calculate or shift
% these coordinates.
state.BatteryThermalNodeCount = [];
state.BatteryThermalNodeLocations = [];
state.BatteryThermalNodeDimensions = [];

% V5 keeps both cooling surfaces available. The generic fields above retain
% the bottom mapping for the existing 3-D cell-position logic.
state.BatteryThermalNodeLocationsTop = [];
state.BatteryThermalNodeDimensionsTop = [];
state.BatteryThermalNodeLocationsBottom = [];
state.BatteryThermalNodeDimensionsBottom = [];

%% Latest completed simulation results used by the Dashboard detail windows.
state.LastKPI = [];
state.LastTrace = [];
state.LastCoolantTrace = struct();
state.LastRuntime_s = NaN;
state.LastTopCoolantFlow = 0;
state.LastBottomCoolantFlow = state.MassFlowRate_kg_s;
state.LastSerpentineCoolantFlow = 0;
state.LastSideCoolantFlow = 0;
state.LastTotalCoolantFlow = state.MassFlowRate_kg_s;
state.LastCurrentProfileDescription = "";
state.LastOptimizationResults = table();
state.LastRecommendedCase = table();
state.LastOptimizationFolder = "";
state.OptimizationRunning = false;
state.OptimizationStopRequested = false;
state.OptimizationLiquidRange = [0.01 0.02 0.01];    % min, max, step; kg/s
state.OptimizationAirRange = [0.5 4.0 0.5];           % min, max, step; m/s
state.OptimizationInletRange = [20 25 5];            % min, max, step; degC
state.OptimizationTopFlowShareRange = [50 50 10];    % min, max, step; percent
state.CoolingSelectionOrder = ...
    ["PeakT","CellDelta","WithinDelta","Operating"];
state.LastOptimizationSettings = struct();

% Design-optimization state is independent from the operating/cooling sweep.
% Each range is [minimum maximum step]. Initial ranges evaluate the current
% design once; the user expands them explicitly before a multi-case sweep.
state.LastDesignOptimizationResults = table();
state.LastRecommendedDesign = table();
state.LastDesignOptimizationSettings = struct();
state.LastDesignOptimizationFolder = "";
state.DesignOptimizationRunning = false;
state.DesignOptimizationStopRequested = false;
state.DesignSelectionOrder = ...
    ["PeakT","CellDelta","WithinDelta","DesignParameters"];
state.DesignOptimizationRanges = struct( ...
    'ForcedAir',[state.InterCellGap_mm state.InterCellGap_mm 1; ...
                 state.ForcedAirWallClearance_mm state.ForcedAirWallClearance_mm 1; ...
                 1 1 1], ...
    'Plate',[2 3 1; ...
             1.2 1.5 0.3; ...
             1 1 1], ...
    'Side',[state.SideHeightFraction state.SideHeightFraction 0.1; ...
            state.SideContactRth_K_W state.SideContactRth_K_W 1; ...
            1 1 1], ...
    'Serpentine',[state.SerpentineHeightFraction state.SerpentineHeightFraction 0.1; ...
                  state.SerpentineCircumferenceFraction state.SerpentineCircumferenceFraction 0.05; ...
                  state.SerpentineContactRth_K_W state.SerpentineContactRth_K_W 1]);


state.NeedsRebuild = false;

%% Main window
screenSize = get(groot,"ScreenSize");   % [left bottom width height]

appWidth  = min(1500, max(1050, screenSize(3) - 100));
appHeight = min(900,  max(700,  screenSize(4) - 140));

appLeft   = screenSize(1) + max(20,(screenSize(3) - appWidth)/2);
appBottom = screenSize(2) + max(40,(screenSize(4) - appHeight)/2);

% Keep MATLAB and Simulink warnings out of the Command Window while the
% app is open. Errors remain visible through ThermalPack dialogs.
thermalPackWarningState = warning;

fig = uifigure( ...
    "Name","ThermalPack Version 2.0", ...
    "Position",[appLeft appBottom appWidth appHeight]);
warning("off","all");
fig.CloseRequestFcn = @closeThermalPackApp;

main = uigridlayout(fig,[1 2]);
main.ColumnWidth = {min(420,max(340,round(appWidth*0.30))),'1x'};
main.RowHeight = {'1x'};
main.Padding = [12 12 12 12];
main.ColumnSpacing = 12;

%% LEFT — Configuration
leftPanel = uipanel(main,"Title","Battery & Simulation Configuration");
leftPanel.Layout.Row = 1;
leftPanel.Layout.Column = 1;

left = uigridlayout(leftPanel,[71 2]);
left.ColumnWidth = {215,'1x'};

% Use fixed row heights so the configuration panel can scroll consistently.
left.RowHeight = repmat({29},1,71);
% Pouch-only tab rows stay collapsed for Cylindrical/Prismatic.
left.RowHeight(22:24) = {0,0,0};
% The final row is unused after grouping the validation cases.
left.RowHeight(71) = {0};
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
    "Text","Version 2.0 — Battery Thermal Design Platform", ...
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
    "Items",{'Cylindrical','Prismatic','Pouch'}, ...
    "Value","Cylindrical", ...
    "ValueChangedFcn",@cellFormatChanged);
formatField.Layout.Row = 7;
formatField.Layout.Column = 2;

addInputLabel(left,8,"Topology");
topologyField = uidropdown(left, ...
    "Items",{'Square','Hexagonal'}, ...
    "Value","Square", ...
    "ValueChangedFcn",@topologyChanged);
topologyField.Layout.Row = 8;
topologyField.Layout.Column = 2;

addInputLabel(left,9,"Parallel cells (P)");
parallelField = uieditfield(left,"numeric", ...
    "Value",state.Cylindrical.P,"Limits",[1 149],"RoundFractionalValues","on", ...
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
    "Value",state.Cylindrical.S,"Limits",[1 149],"RoundFractionalValues","on", ...
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

diameterLabel = addInputLabel(left,19,"Diameter (mm)");
diameterField = uieditfield(left,"numeric", ...
    "Value",state.Cylindrical.Diameter_mm,"Limits",[1 4999], ...
    "ValueChangedFcn",@geometryValueChanged);
diameterField.Layout.Row = 19;
diameterField.Layout.Column = 2;

% Hidden for cylindrical; used as Thickness for prismatic.
thicknessLabel = addInputLabel(left,20,"Thickness (mm)");
thicknessLabel.Visible = "off";
thicknessField = uieditfield(left,"numeric", ...
    "Value",state.Prismatic.Thickness_mm,"Limits",[0.001 499], ...
    "ValueChangedFcn",@geometryValueChanged, ...
    "Visible","off");
thicknessField.Layout.Row = 20;
thicknessField.Layout.Column = 2;

heightLabel = addInputLabel(left,21,"Height (mm)");
heightField = uieditfield(left,"numeric", ...
    "Value",state.Cylindrical.Height_mm,"Limits",[1 2000], ...
    "ValueChangedFcn",@structuralValueChanged);
heightField.Layout.Row = 21;
heightField.Layout.Column = 2;

% Pouch-only tab geometry. The rows expand only for the Pouch format.
tabLocationLabel = addInputLabel(left,22,"Tab location");
tabLocationLabel.Visible = "off";
tabLocationField = uidropdown(left, ...
    "Items",{'Standard','Opposed'}, ...
    "Value",char(state.Pouch.TabLocation), ...
    "ValueChangedFcn",@structuralValueChanged, ...
    "Visible","off");
tabLocationField.Layout.Row = 22;
tabLocationField.Layout.Column = 2;

tabWidthLabel = addInputLabel(left,23,"Tab width (mm)");
tabWidthLabel.Visible = "off";
tabWidthField = uieditfield(left,"numeric", ...
    "Value",state.Pouch.TabWidth_mm,"Limits",[0.001 4999], ...
    "ValueChangedFcn",@structuralValueChanged, ...
    "Visible","off");
tabWidthField.Layout.Row = 23;
tabWidthField.Layout.Column = 2;

tabHeightLabel = addInputLabel(left,24,"Tab height (mm)");
tabHeightLabel.Visible = "off";
tabHeightField = uieditfield(left,"numeric", ...
    "Value",state.Pouch.TabHeight_mm,"Limits",[0.001 1999], ...
    "ValueChangedFcn",@structuralValueChanged, ...
    "Visible","off");
tabHeightField.Layout.Row = 24;
tabHeightField.Layout.Column = 2;

addInputLabel(left,25,"Mass (kg)");
massField = uieditfield(left,"numeric", ...
    "Value",state.Cylindrical.Mass_kg,"Limits",[0.0001 Inf]);
massField.Layout.Row = 25;
massField.Layout.Column = 2;

addInputLabel(left,26,"Capacity (Ah)");
capacityField = uieditfield(left,"numeric", ...
    "Value",state.Cylindrical.Capacity_Ah,"Limits",[0.001 Inf]);
capacityField.Layout.Row = 26;
capacityField.Layout.Column = 2;

addInputLabel(left,27,"Nominal energy (Wh)");
energyField = uieditfield(left,"numeric", ...
    "Value",state.Cylindrical.Energy_Wh,"Limits",[0.001 Inf]);
energyField.Layout.Row = 27;
energyField.Layout.Column = 2;

addInputLabel(left,28,"Initial SOC");
socField = uieditfield(left,"numeric", ...
    "Value",0.40,"Limits",[0 1]);
socField.Layout.Row = 28;
socField.Layout.Column = 2;

addInputLabel(left,29,"Initial cell temperature (°C)");
initialCellTempField = uieditfield(left,"numeric", ...
    "Value",state.InitialCellTemperature_C, ...
    "Limits",[-273.14 Inf]);
initialCellTempField.Layout.Row = 29;
initialCellTempField.Layout.Column = 2;

cellElectricalButton = uibutton(left,"push", ...
    "Text","CELL ELECTRICAL DATA", ...
    "FontWeight","bold", ...
    "ButtonPushedFcn",@openCellElectricalData);
cellElectricalButton.Layout.Row = 30;
cellElectricalButton.Layout.Column = [1 2];

%% Thermal model
sectionLabel(left,31,"THERMAL MODEL");

addInputLabel(left,32,"Thermal model");
thermalModelField = uidropdown(left, ...
    "Items","Height-Distributed Thermal Mass", ...
    "Value","Height-Distributed Thermal Mass");
thermalModelField.Layout.Row = 32;
thermalModelField.Layout.Column = 2;

addInputLabel(left,33,"Thermal nodes");
nodesField = uispinner(left, ...
    "Limits",[1 20], ...
    "Step",1, ...
    "Value",min(20,max(1,round(masterNodes))));
nodesField.Layout.Row = 33;
nodesField.Layout.Column = 2;

%% Thermal properties
sectionLabel(left,34,"THERMAL PROPERTIES");

addInputLabel(left,35,"Thermal mass (J/K)");
thermalMassField = uieditfield(left,"numeric", ...
    "Value",state.Cylindrical.ThermalMass_J_K,"Limits",[0.001 Inf]);
thermalMassField.Layout.Row = 35;
thermalMassField.Layout.Column = 2;

addInputLabel(left,36,"Axial conductivity (W/mK)");
conductivityField = uieditfield(left,"numeric", ...
    "Value",state.Cylindrical.ConductivityZ_W_mK,"Limits",[0.001 Inf]);
conductivityField.Layout.Row = 36;
conductivityField.Layout.Column = 2;

addInputLabel(left,37,"Thermal cross section (m²)");
thermalAreaField = uieditfield(left,"numeric", ...
    "Value",state.Cylindrical.ThermalArea_m2,"Limits",[1e-10 Inf], ...
    "Editable","off", ...
    "ValueChangedFcn",@thermalAreaCustomChanged);
thermalAreaField.Layout.Row = 37;
thermalAreaField.Layout.Column = 2;

addInputLabel(left,38,"Thermal limit (°C)");
thermalLimitField = uieditfield(left,"numeric", ...
    "Value",state.ThermalLimit_C, ...
    "Limits",[-273.14 Inf], ...
    "ValueChangedFcn",@thermalLimitChanged);
thermalLimitField.Layout.Row = 38;
thermalLimitField.Layout.Column = 2;

%% Load profile
sectionLabel(left,39,"LOAD PROFILE");

addInputLabel(left,40,"Profile");
loadProfileField = uidropdown(left, ...
    "Items",[ ...
        "Custom", ...
        "Constant Discharge — Coming Soon", ...
        "Constant Charge — Coming Soon", ...
        "Pulse Load — Coming Soon", ...
        "Drive Cycle / CSV — Coming Soon"], ...
    "Value","Custom", ...
    "ValueChangedFcn",@loadProfileChanged);
loadProfileField.Layout.Row = 40;
loadProfileField.Layout.Column = 2;

customLoadProfileButton = uibutton(left,"push", ...
    "Text","CUSTOM LOAD PROFILE", ...
    "FontWeight","bold", ...
    "Enable","on", ...
    "ButtonPushedFcn",@openCustomLoadProfile);
customLoadProfileButton.Layout.Row = 41;
customLoadProfileButton.Layout.Column = [1 2];

addInputLabel(left,42,"Simulation time (s)");
stopField = uieditfield(left,"numeric", ...
    "Value",900,"Limits",[1 Inf]);
stopField.Layout.Row = 42;
stopField.Layout.Column = 2;

%% Cooling / boundary conditions
sectionLabel(left,43,"COOLING & ENVIRONMENT");

addInputLabel(left,44,"Cooling architecture");
coolingPlateField = uidropdown(left, ...
    "Items",["Bottom Cooling Plate","Top Cooling Plate", ...
             "Top + Bottom Cooling","Side Cooling","Forced Air Cooling", ...
             "Serpentine Cooling","No Cooling Plate"], ...
    "Value","Bottom Cooling Plate", ...
    "ValueChangedFcn",@coolingModeChanged);
coolingPlateField.Layout.Row = 44;
coolingPlateField.Layout.Column = 2;

addInputLabel(left,45,"Cooling plate type");
coolingPlateTypeField = uidropdown(left, ...
    "Items",["Parallel Channels","U-Shaped Channels","Edge Cooling"], ...
    "Value",state.CoolingPlateType, ...
    "ValueChangedFcn",@coolingPlateTypeChanged);
coolingPlateTypeField.Layout.Row = 45;
coolingPlateTypeField.Layout.Column = 2;

serpentineSettingsButton = uibutton(left,"push", ...
    "Text","SERPENTINE SETTINGS", ...
    "FontWeight","bold", ...
    "Enable","off", ...
    "ButtonPushedFcn",@openSerpentineSettings);
serpentineSettingsButton.Layout.Row = 46;
serpentineSettingsButton.Layout.Column = 1;

sideSettingsButton = uibutton(left,"push", ...
    "Text","SIDE SETTINGS", ...
    "FontWeight","bold", ...
    "Enable","off", ...
    "ButtonPushedFcn",@openSideCoolingSettings);
sideSettingsButton.Layout.Row = 46;
sideSettingsButton.Layout.Column = 2;

forcedAirSettingsButton = uibutton(left,"push", ...
    "Text","FORCED AIR SETTINGS", ...
    "FontWeight","bold", ...
    "Enable","off", ...
    "ButtonPushedFcn",@openForcedAirSettings);
forcedAirSettingsButton.Layout.Row = 47;
forcedAirSettingsButton.Layout.Column = [1 2];

coolingModeNote = uilabel(left, ...
    "Text","Bottom plate active — top interface is thermally isolated.", ...
    "FontAngle","italic", ...
    "WordWrap","on");
coolingModeNote.Layout.Row = 48;
coolingModeNote.Layout.Column = [1 2];

addInputLabel(left,49,"Flow accounting");
flowAllocationField = uidropdown(left, ...
    "Items",["Total Flow","Independent Flow"], ...
    "Value",state.FlowAllocationMode, ...
    "Enable","off", ...
    "ValueChangedFcn",@flowAllocationChanged);
flowAllocationField.Layout.Row = 49;
flowAllocationField.Layout.Column = 2;

flowLabel = addInputLabel(left,50,"Coolant flow (kg/s)");
flowField = uieditfield(left,"numeric", ...
    "Value",state.MassFlowRate_kg_s,"Limits",[0 Inf], ...
    "ValueChangedFcn",@mainFlowChanged);
flowField.Layout.Row = 50;
flowField.Layout.Column = 2;

topSplitLabel = addInputLabel(left,51,"Top flow share (%)");
topSplitField = uieditfield(left,"numeric", ...
    "Value",state.TopFlowShare_pct,"Limits",[0 100], ...
    "Enable","off", ...
    "ValueChangedFcn",@topFlowShareChanged);
topSplitField.Layout.Row = 51;
topSplitField.Layout.Column = 2;

topFlowLabel = addInputLabel(left,52,"Top flow (kg/s)");
topFlowField = uieditfield(left,"numeric", ...
    "Value",state.TopMassFlowRate_kg_s,"Limits",[0 Inf], ...
    "Enable","off", ...
    "ValueChangedFcn",@independentFlowChanged);
topFlowField.Layout.Row = 52;
topFlowField.Layout.Column = 2;

bottomFlowLabel = addInputLabel(left,53,"Bottom flow (kg/s)");
bottomFlowField = uieditfield(left,"numeric", ...
    "Value",state.BottomMassFlowRate_kg_s,"Limits",[0 Inf], ...
    "Enable","off", ...
    "ValueChangedFcn",@independentFlowChanged);
bottomFlowField.Layout.Row = 53;
bottomFlowField.Layout.Column = 2;

addInputLabel(left,54,"Coolant inlet (°C)");
tinField = uieditfield(left,"numeric","Value",25);
tinField.Layout.Row = 54;
tinField.Layout.Column = 2;

addInputLabel(left,55,"Ambient (°C)");
ambientField = uieditfield(left,"numeric","Value",25);
ambientField.Layout.Row = 55;
ambientField.Layout.Column = 2;

addInputLabel(left,56,"Cell → plate Rth (K/W)");
coolantRField = uieditfield(left,"numeric", ...
    "Value",masterCoolantR_K_W,"Limits",[0 Inf], ...
    "Tooltip",["Native Top/Bottom Cell → plate thermal-path resistance (CoolantResistance). " ...
               "Disabled during Side Cooling because the active side path uses the separate " ...
               "Cell → side boundary Rth in SIDE SETTINGS."]);
coolantRField.Layout.Row = 56;
coolantRField.Layout.Column = 2;

addInputLabel(left,57,"Cell → ambient Rth (K/W)");
ambientRField = uieditfield(left,"numeric", ...
    "Value",masterAmbientR_K_W,"Limits",[0 Inf], ...
    "Tooltip",["Cell-level ambient thermal resistance. During Forced Air Cooling " ...
               "this is calculated automatically as 1/(h*Aeff) and is read-only."]);
ambientRField.Layout.Row = 57;
ambientRField.Layout.Column = 2;

addInputLabel(left,58,"Inter-cell heat transfer");
interCellHeatField = uidropdown(left, ...
    "Items",["Enabled","Disabled"], ...
    "Value","Enabled", ...
    "ValueChangedFcn",@interCellHeatChanged);
interCellHeatField.Layout.Row = 58;
interCellHeatField.Layout.Column = 2;

addInputLabel(left,59,"Inter-cell Rth (K/W)");
interCellRField = uieditfield(left,"numeric", ...
    "Value",masterInterCellR_K_W,"Limits",[0 Inf]);
interCellRField.Layout.Row = 59;
interCellRField.Layout.Column = 2;

addInputLabel(left,60,"Inter-parallel assembly Rth (K/W)");
interParallelRField = uieditfield(left,"numeric", ...
    "Value",1,"Limits",[0 Inf]);
interParallelRField.Layout.Row = 60;
interParallelRField.Layout.Column = 2;

coolingPlateSettingsButton = uibutton(left,"push", ...
    "Text","COOLING PLATE SETTINGS", ...
    "FontWeight","bold", ...
    "ButtonPushedFcn",@openCoolingPlateSettings);
coolingPlateSettingsButton.Layout.Row = 61;
coolingPlateSettingsButton.Layout.Column = [1 2];

flowSourceSettingsButton = uibutton(left,"push", ...
    "Text","FLOW SOURCE SETTINGS", ...
    "FontWeight","bold", ...
    "ButtonPushedFcn",@openFlowSourceSettings);
flowSourceSettingsButton.Layout.Row = 62;
flowSourceSettingsButton.Layout.Column = [1 2];

coolantPropertiesButton = uibutton(left,"push", ...
    "Text","COOLANT PROPERTIES", ...
    "FontWeight","bold", ...
    "ButtonPushedFcn",@openCoolantProperties);
coolantPropertiesButton.Layout.Row = 63;
coolantPropertiesButton.Layout.Column = [1 2];

reservoirSettingsButton = uibutton(left,"push", ...
    "Text","RESERVOIR SETTINGS", ...
    "FontWeight","bold", ...
    "ButtonPushedFcn",@openReservoirSettings);
reservoirSettingsButton.Layout.Row = 64;
reservoirSettingsButton.Layout.Column = [1 2];

advancedButton = uibutton(left,"push", ...
    "Text","ADVANCED SETTINGS", ...
    "FontWeight","bold", ...
    "FontColor",[1 1 1], ...
    "BackgroundColor",[0.70 0.08 0.08], ...
    "ButtonPushedFcn",@openAdvancedSettings);
advancedButton.Layout.Row = 65;
advancedButton.Layout.Column = [1 2];

setupButtonGrid = uigridlayout(left,[1 2]);
setupButtonGrid.Layout.Row = 66;
setupButtonGrid.Layout.Column = [1 2];
setupButtonGrid.ColumnWidth = {'1x','1x'};
setupButtonGrid.RowHeight = {'1x'};
setupButtonGrid.Padding = [0 0 0 0];
setupButtonGrid.ColumnSpacing = 8;

saveSetupButton = uibutton(setupButtonGrid,"push", ...
    "Text","SAVE SIMULATION SETUP", ...
    "FontWeight","bold", ...
    "Tooltip",["Save the complete ThermalPack simulation configuration to a portable .mat setup file. " ...
               "Simulation results and generated-model runtime data are not stored."], ...
    "ButtonPushedFcn",@saveSimulationSetup);
saveSetupButton.Layout.Row = 1;
saveSetupButton.Layout.Column = 1;

loadSetupButton = uibutton(setupButtonGrid,"push", ...
    "Text","LOAD SIMULATION SETUP", ...
    "FontWeight","bold", ...
    "Tooltip",["Load a previously saved ThermalPack setup. The loaded configuration is applied to the UI " ...
               "and marked for REBUILD BATTERY before simulation."], ...
    "ButtonPushedFcn",@loadSimulationSetup);
loadSetupButton.Layout.Row = 1;
loadSetupButton.Layout.Column = 2;

rebuildButton = uibutton(left,"push", ...
    "Text","REBUILD BATTERY", ...
    "FontWeight","bold", ...
    "ButtonPushedFcn",@rebuildBattery);
rebuildButton.Layout.Row = 67;
rebuildButton.Layout.Column = [1 2];

runButton = uibutton(left,"push", ...
    "Text","RUN SIMULATION", ...
    "FontWeight","bold", ...
    "ButtonPushedFcn",@runSimulation);
runButton.Layout.Row = 68;
runButton.Layout.Column = [1 2];

validationCasesButton = uibutton(left,"push", ...
    "Text","VALIDATION CASES", ...
    "FontWeight","bold", ...
    "Tooltip","Open the literature validation cases.", ...
    "ButtonPushedFcn",@openValidationCases);
validationCasesButton.Layout.Row = 69;
validationCasesButton.Layout.Column = [1 2];

statusLabel = uilabel(left, ...
    "Text","Ready — current model is 4P × 3S", ...
    "HorizontalAlignment","center", ...
    "WordWrap","on");
statusLabel.Layout.Row = 70;
statusLabel.Layout.Column = [1 2];

% Seed every model-referenced operating variable with a physically valid
% default before any manual model update/compile. Runtime SimulationInput
% values still override these defaults for the actual simulation case.
initializeWorkingModelDefaults();

% Initialize the cooling/flow-accounting controls. The master already
% contains both permanent isolation blocks; startup only validates/configures
% them and applies the selected Rth state.
refreshFlowAccountingUI();
try
    swapCoolingPlateArchitecture();
catch MEstartupCooling
    warning("ThermalPack:StartupCoolingArchitecture", ...
        "Could not initialize the cooling-isolation network: %s", ...
        MEstartupCooling.message);
end

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
optimizationTab = uitab(rightTabs,"Title","Cooling Optimization");
designOptimizationTab = uitab(rightTabs,"Title","Design Optimization");

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

%% Detailed result actions and Excel export.
dashboardButtons = uigridlayout(right,[1 3]);
dashboardButtons.Layout.Row = 4;
dashboardButtons.Layout.Column = 1;
dashboardButtons.ColumnWidth = {'1x','1x','1x'};
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

exportResultsButton = uibutton(dashboardButtons,"push", ...
    "Text","EXPORT RESULTS TO EXCEL", ...
    "FontWeight","bold", ...
    "Enable","off", ...
    "ButtonPushedFcn",@exportSimulationResultsToExcel);
exportResultsButton.Layout.Row = 1;
exportResultsButton.Layout.Column = 3;

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

%% Operating-parameter optimization — geometry and load remain fixed.
optimizationGrid = uigridlayout(optimizationTab,[5 1]);
optimizationGrid.RowHeight = {270,28,28,220,390};
optimizationGrid.ColumnWidth = {'1x'};
optimizationGrid.Padding = [10 10 10 10];
optimizationGrid.RowSpacing = 6;
optimizationGrid.Scrollable = "on";

optimizationControls = uigridlayout(optimizationGrid,[8 5]);
optimizationControls.Layout.Row = 1;
optimizationControls.ColumnWidth = {190,'1x','1x','1x','1x'};
optimizationControls.RowHeight = {20,28,28,28,28,30,30,38};
optimizationControls.Padding = [0 0 0 0];
optimizationControls.ColumnSpacing = 6;
optimizationControls.RowSpacing = 4;

rangeHeader = uilabel(optimizationControls,"Text","Operating parameter", ...
    "FontWeight","bold");
rangeHeader.Layout.Row = 1; rangeHeader.Layout.Column = 1;
rangeHeadings = ["Minimum","Maximum","Step","Cases"];
for kHeading = 1:4
    rangeHeader = uilabel(optimizationControls,"Text",rangeHeadings(kHeading));
    rangeHeader.Layout.Row = 1; rangeHeader.Layout.Column = kHeading+1;
end
optRangeMode = "";
optFlowLabel = uilabel(optimizationControls,"Text","Total liquid flow (kg/s)");
optFlowLabel.Layout.Row = 2; optFlowLabel.Layout.Column = 1;
optFlowMinField = uieditfield(optimizationControls,"numeric","Value",0.005, ...
    "ValueChangedFcn",@optimizationRangeChanged);
optFlowMinField.Layout.Row = 2; optFlowMinField.Layout.Column = 2;
optFlowMaxField = uieditfield(optimizationControls,"numeric","Value",0.100, ...
    "ValueChangedFcn",@optimizationRangeChanged);
optFlowMaxField.Layout.Row = 2; optFlowMaxField.Layout.Column = 3;
optFlowStepField = uieditfield(optimizationControls,"numeric","Value",0.005, ...
    "ValueChangedFcn",@optimizationRangeChanged);
optFlowStepField.Layout.Row = 2; optFlowStepField.Layout.Column = 4;

optTinLabel = uilabel(optimizationControls,"Text","Coolant inlet temperature (°C)");
optTinLabel.Layout.Row = 3; optTinLabel.Layout.Column = 1;
optTinMinField = uieditfield(optimizationControls,"numeric","Value",15, ...
    "ValueChangedFcn",@optimizationRangeChanged);
optTinMinField.Layout.Row = 3; optTinMinField.Layout.Column = 2;
optTinMaxField = uieditfield(optimizationControls,"numeric","Value",35, ...
    "ValueChangedFcn",@optimizationRangeChanged);
optTinMaxField.Layout.Row = 3; optTinMaxField.Layout.Column = 3;
optTinStepField = uieditfield(optimizationControls,"numeric","Value",5, ...
    "ValueChangedFcn",@optimizationRangeChanged);
optTinStepField.Layout.Row = 3; optTinStepField.Layout.Column = 4;

optSplitLabel = uilabel(optimizationControls, ...
    "Text","Top flow share (%)","Visible","off");
optSplitLabel.Layout.Row = 4; optSplitLabel.Layout.Column = 1;
optSplitMinField = uieditfield(optimizationControls,"numeric", ...
    "Value",50,"Limits",[0 100],"Visible","off", ...
    "ValueChangedFcn",@optimizationRangeChanged);
optSplitMinField.Layout.Row = 4; optSplitMinField.Layout.Column = 2;
optSplitMaxField = uieditfield(optimizationControls,"numeric", ...
    "Value",50,"Limits",[0 100],"Visible","off", ...
    "ValueChangedFcn",@optimizationRangeChanged);
optSplitMaxField.Layout.Row = 4; optSplitMaxField.Layout.Column = 3;
optSplitStepField = uieditfield(optimizationControls,"numeric", ...
    "Value",10,"Visible","off", ...
    "ValueChangedFcn",@optimizationRangeChanged);
optSplitStepField.Layout.Row = 4; optSplitStepField.Layout.Column = 4;
optimizationCaseCount = uilabel(optimizationControls,"Text","—", ...
    "WordWrap","on","FontWeight","bold","HorizontalAlignment","center");
optimizationCaseCount.Layout.Row = [2 4]; optimizationCaseCount.Layout.Column = 5;

optLimitField = uieditfield(optimizationControls,"numeric","Value",60, ...
    "Visible","off");
optLimitField.Layout.Row = 5; optLimitField.Layout.Column = 1;
optUniformityField = uieditfield(optimizationControls,"numeric","Value",5, ...
    "Visible","off");
optUniformityField.Layout.Row = 5; optUniformityField.Layout.Column = 2;
optimizationDesignLimitsButton = uibutton(optimizationControls,"push", ...
    "Text","DESIGN LIMITS", ...
    "FontWeight","bold", ...
    "ButtonPushedFcn",@openOptimizationDesignLimits);
optimizationDesignLimitsButton.Layout.Row = 5;
optimizationDesignLimitsButton.Layout.Column = [1 5];

optimizationRunButton = uibutton(optimizationControls,"push", ...
    "Text","RUN OPERATING SWEEP","FontWeight","bold", ...
    "ButtonPushedFcn",@runCoolingOptimization);
optimizationRunButton.Layout.Row = 6; optimizationRunButton.Layout.Column = 1;
optimizationStopButton = uibutton(optimizationControls,"push", ...
    "Text","STOP SWEEP","Enable","off","ButtonPushedFcn",@stopCoolingOptimization);
optimizationStopButton.Layout.Row = 6; optimizationStopButton.Layout.Column = [2 3];
optimizationExportButton = uibutton(optimizationControls,"push", ...
    "Text","EXPORT SWEEP","Enable","off","ButtonPushedFcn",@exportCoolingOptimization);
optimizationExportButton.Layout.Row = 6; optimizationExportButton.Layout.Column = [4 5];
optimizationCsvButton = uibutton(optimizationControls,"push", ...
    "Text","EXPORT RESULTS (.CSV)","Enable","off", ...
    "FontWeight","bold","ButtonPushedFcn",@exportOptimizationResultsCsv);
optimizationCsvButton.Layout.Row = 7;
optimizationCsvButton.Layout.Column = [1 3];
optimizationCriteriaButton = uibutton(optimizationControls,"push", ...
    "Text","SELECTION CRITERIA","FontWeight","bold", ...
    "ButtonPushedFcn",@showCoolingSelectionCriteria);
optimizationCriteriaButton.Layout.Row = 7;
optimizationCriteriaButton.Layout.Column = [4 5];
optObjectiveText = uilabel(optimizationControls, ...
    "Text","Geometry, load and initial cell state stay fixed. Pump/fan power is not evaluated.", ...
    "WordWrap","on","FontAngle","italic");
optObjectiveText.Layout.Row = 8; optObjectiveText.Layout.Column = [1 5];

optimizationStatus = uilabel(optimizationGrid, ...
    "Text","Ready — review ranges and design limits, then run.", ...
    "HorizontalAlignment","center","FontWeight","bold","WordWrap","on");
optimizationStatus.Layout.Row = 2;
optimizationCurrentCase = uilabel(optimizationGrid,"Text","Current case: —", ...
    "HorizontalAlignment","center","FontAngle","italic");
optimizationCurrentCase.Layout.Row = 3;
optimizationResultsPanel = uipanel(optimizationGrid, ...
    "Title","Operating Sweep Results — All Simulated Cases");
optimizationResultsPanel.Layout.Row = 4;
optimizationResultsGrid = uigridlayout(optimizationResultsPanel,[1 1]);
optimizationResultsGrid.Padding = [0 0 0 0];
optimizationTable = uitable(optimizationResultsGrid, ...
    "CellSelectionCallback",@showOptimizationCaseError);
sweepPlotTabs = uitabgroup(optimizationGrid);
sweepPlotTabs.Layout.Row = 5;
sweepTmaxFlowTab = uitab(sweepPlotTabs,"Title","Peak Temperature");
sweepDeltaFlowTab = uitab(sweepPlotTabs,"Title","Cell Uniformity");
sweepTmaxHeatmapTab = uitab(sweepPlotTabs,"Title","Tmax Heatmap");
sweepSafetyHeatmapTab = uitab(sweepPlotTabs,"Title","Feasibility");
sweepParetoTab = uitab(sweepPlotTabs,"Title","Operating Points");

sweepTmaxFlowGrid = uigridlayout(sweepTmaxFlowTab,[1 1]);
sweepTmaxFlowGrid.RowHeight = {'1x'};
sweepTmaxFlowGrid.ColumnWidth = {'1x'};
sweepTmaxFlowGrid.Padding = [8 8 8 8];
sweepTmaxFlowAxes = uiaxes(sweepTmaxFlowGrid);
title(sweepTmaxFlowAxes,"Peak Temperature versus Coolant Flow Rate");
xlabel(sweepTmaxFlowAxes,"Mass Flow Rate (kg/s)");
ylabel(sweepTmaxFlowAxes,"Peak Nodal Temperature (°C)");
grid(sweepTmaxFlowAxes,"on");

sweepDeltaFlowGrid = uigridlayout(sweepDeltaFlowTab,[1 1]);
sweepDeltaFlowGrid.RowHeight = {'1x'};
sweepDeltaFlowGrid.ColumnWidth = {'1x'};
sweepDeltaFlowGrid.Padding = [8 8 8 8];
sweepDeltaFlowAxes = uiaxes(sweepDeltaFlowGrid);
title(sweepDeltaFlowAxes,"Maximum Cell-to-Cell Temperature Difference");
xlabel(sweepDeltaFlowAxes,"Mass Flow Rate (kg/s)");
ylabel(sweepDeltaFlowAxes,"Maximum Cell-to-Cell ΔT (°C)");
grid(sweepDeltaFlowAxes,"on");

sweepTmaxHeatmapGrid = uigridlayout(sweepTmaxHeatmapTab,[1 1]);
sweepTmaxHeatmapGrid.RowHeight = {'1x'};
sweepTmaxHeatmapGrid.ColumnWidth = {'1x'};
sweepTmaxHeatmapGrid.Padding = [8 8 8 8];
sweepTmaxHeatmapAxes = uiaxes(sweepTmaxHeatmapGrid);
title(sweepTmaxHeatmapAxes,"Peak Nodal Temperature (°C)");
xlabel(sweepTmaxHeatmapAxes,"Mass Flow Rate (kg/s)");
ylabel(sweepTmaxHeatmapAxes,"Inlet Temperature (°C)");

sweepSafetyHeatmapGrid = uigridlayout(sweepSafetyHeatmapTab,[1 1]);
sweepSafetyHeatmapGrid.RowHeight = {'1x'};
sweepSafetyHeatmapGrid.ColumnWidth = {'1x'};
sweepSafetyHeatmapGrid.Padding = [8 8 8 8];
sweepSafetyHeatmapAxes = uiaxes(sweepSafetyHeatmapGrid);
title(sweepSafetyHeatmapAxes,"Minimum Safety Margin (°C)");
xlabel(sweepSafetyHeatmapAxes,"Mass Flow Rate (kg/s)");
ylabel(sweepSafetyHeatmapAxes,"Inlet Temperature (°C)");

sweepParetoGrid = uigridlayout(sweepParetoTab,[1 1]);
sweepParetoGrid.RowHeight = {'1x'};
sweepParetoGrid.ColumnWidth = {'1x'};
sweepParetoGrid.Padding = [8 8 8 8];
optimizationAxes = uiaxes(sweepParetoGrid);
title(optimizationAxes,"Operating Points — Colour Indicates Inlet Temperature");
xlabel(optimizationAxes,"Mass Flow Rate (kg/s)");
ylabel(optimizationAxes,"Peak Nodal Temperature (°C)");
grid(optimizationAxes,"on");

%% Design optimization — operating point and load remain fixed.
designOptimizationGrid = uigridlayout(designOptimizationTab,[5 1]);
designOptimizationGrid.RowHeight = {270,28,28,220,390};
designOptimizationGrid.ColumnWidth = {'1x'};
designOptimizationGrid.Padding = [10 10 10 10];
designOptimizationGrid.RowSpacing = 6;
designOptimizationGrid.Scrollable = "on";

designOptimizationControls = uigridlayout(designOptimizationGrid,[8 5]);
designOptimizationControls.Layout.Row = 1;
designOptimizationControls.ColumnWidth = {210,'1x','1x','1x','1x'};
designOptimizationControls.RowHeight = {20,28,28,28,28,30,30,38};
designOptimizationControls.Padding = [0 0 0 0];
designOptimizationControls.ColumnSpacing = 6;
designOptimizationControls.RowSpacing = 4;

designRangeHeader = uilabel(designOptimizationControls, ...
    "Text","Design parameter","FontWeight","bold");
designRangeHeader.Layout.Row = 1;
designRangeHeader.Layout.Column = 1;
designRangeHeadings = ["Minimum","Maximum","Step","Cases"];
for kHeading = 1:4
    designRangeHeader = uilabel(designOptimizationControls, ...
        "Text",designRangeHeadings(kHeading));
    designRangeHeader.Layout.Row = 1;
    designRangeHeader.Layout.Column = kHeading+1;
end

designRangeMode = "";
designVariableLabels = gobjects(3,1);
designMinFields = gobjects(3,1);
designMaxFields = gobjects(3,1);
designStepFields = gobjects(3,1);
for kVariable = 1:3
    designVariableLabels(kVariable) = uilabel(designOptimizationControls, ...
        "Text","Design variable " + string(kVariable));
    designVariableLabels(kVariable).Layout.Row = kVariable+1;
    designVariableLabels(kVariable).Layout.Column = 1;
    designMinFields(kVariable) = uieditfield(designOptimizationControls, ...
        "numeric","Value",1,"ValueChangedFcn",@designOptimizationRangeChanged);
    designMinFields(kVariable).Layout.Row = kVariable+1;
    designMinFields(kVariable).Layout.Column = 2;
    designMaxFields(kVariable) = uieditfield(designOptimizationControls, ...
        "numeric","Value",1,"ValueChangedFcn",@designOptimizationRangeChanged);
    designMaxFields(kVariable).Layout.Row = kVariable+1;
    designMaxFields(kVariable).Layout.Column = 3;
    designStepFields(kVariable) = uieditfield(designOptimizationControls, ...
        "numeric","Value",1,"ValueChangedFcn",@designOptimizationRangeChanged);
    designStepFields(kVariable).Layout.Row = kVariable+1;
    designStepFields(kVariable).Layout.Column = 4;
end
designOptimizationCaseCount = uilabel(designOptimizationControls, ...
    "Text","—","WordWrap","on","FontWeight","bold", ...
    "HorizontalAlignment","center");
designOptimizationCaseCount.Layout.Row = [2 4];
designOptimizationCaseCount.Layout.Column = 5;

designOptimizationLimitsButton = uibutton(designOptimizationControls,"push", ...
    "Text","DESIGN LIMITS","FontWeight","bold", ...
    "ButtonPushedFcn",@openOptimizationDesignLimits);
designOptimizationLimitsButton.Layout.Row = 5;
designOptimizationLimitsButton.Layout.Column = [1 5];

designOptimizationRunButton = uibutton(designOptimizationControls,"push", ...
    "Text","RUN DESIGN SWEEP","FontWeight","bold", ...
    "ButtonPushedFcn",@runDesignOptimization);
designOptimizationRunButton.Layout.Row = 6;
designOptimizationRunButton.Layout.Column = 1;
designOptimizationStopButton = uibutton(designOptimizationControls,"push", ...
    "Text","STOP SWEEP","Enable","off", ...
    "ButtonPushedFcn",@stopDesignOptimization);
designOptimizationStopButton.Layout.Row = 6;
designOptimizationStopButton.Layout.Column = [2 3];
designOptimizationExportButton = uibutton(designOptimizationControls,"push", ...
    "Text","EXPORT SWEEP","Enable","off", ...
    "ButtonPushedFcn",@exportDesignOptimization);
designOptimizationExportButton.Layout.Row = 6;
designOptimizationExportButton.Layout.Column = [4 5];
designOptimizationCsvButton = uibutton(designOptimizationControls,"push", ...
    "Text","EXPORT RESULTS (.CSV)","Enable","off", ...
    "FontWeight","bold","ButtonPushedFcn",@exportDesignOptimizationResultsCsv);
designOptimizationCsvButton.Layout.Row = 7;
designOptimizationCsvButton.Layout.Column = [1 3];
designOptimizationCriteriaButton = uibutton(designOptimizationControls,"push", ...
    "Text","SELECTION CRITERIA","FontWeight","bold", ...
    "ButtonPushedFcn",@showDesignSelectionCriteria);
designOptimizationCriteriaButton.Layout.Row = 7;
designOptimizationCriteriaButton.Layout.Column = [4 5];
designObjectiveText = uilabel(designOptimizationControls, ...
    "Text","The current operating point, load and cell data remain fixed.", ...
    "WordWrap","on","FontAngle","italic");
designObjectiveText.Layout.Row = 8;
designObjectiveText.Layout.Column = [1 5];

designOptimizationStatus = uilabel(designOptimizationGrid, ...
    "Text","Ready — review ranges and design limits, then run.", ...
    "HorizontalAlignment","center","FontWeight","bold","WordWrap","on");
designOptimizationStatus.Layout.Row = 2;
designOptimizationCurrentCase = uilabel(designOptimizationGrid, ...
    "Text","Current case: —","HorizontalAlignment","center", ...
    "FontAngle","italic");
designOptimizationCurrentCase.Layout.Row = 3;

designOptimizationResultsPanel = uipanel(designOptimizationGrid, ...
    "Title","Design Sweep Results — All Simulated Cases");
designOptimizationResultsPanel.Layout.Row = 4;
designOptimizationResultsGrid = uigridlayout(designOptimizationResultsPanel,[1 1]);
designOptimizationResultsGrid.Padding = [0 0 0 0];
designOptimizationTable = uitable(designOptimizationResultsGrid, ...
    "CellSelectionCallback",@showDesignOptimizationCaseError);

designPlotTabs = uitabgroup(designOptimizationGrid);
designPlotTabs.Layout.Row = 5;
designPeakTab = uitab(designPlotTabs,"Title","Peak Temperature");
designUniformityTab = uitab(designPlotTabs,"Title","Cell Uniformity");
designSpaceTab = uitab(designPlotTabs,"Title","Design Space");
designPeakGrid = uigridlayout(designPeakTab,[1 1]);
designPeakGrid.Padding = [8 8 8 8];
designPeakAxes = uiaxes(designPeakGrid);
title(designPeakAxes,"Peak Nodal Temperature for Every Design Case");
xlabel(designPeakAxes,"Design case");
ylabel(designPeakAxes,"Peak nodal temperature (°C)");
grid(designPeakAxes,"on");
designUniformityGrid = uigridlayout(designUniformityTab,[1 1]);
designUniformityGrid.Padding = [8 8 8 8];
designUniformityAxes = uiaxes(designUniformityGrid);
title(designUniformityAxes,"Cell-to-Cell Temperature Difference for Every Design Case");
xlabel(designUniformityAxes,"Design case");
ylabel(designUniformityAxes,"Maximum cell-to-cell ΔT (°C)");
grid(designUniformityAxes,"on");
designSpaceGrid = uigridlayout(designSpaceTab,[1 1]);
designSpaceGrid.Padding = [8 8 8 8];
designSpaceAxes = uiaxes(designSpaceGrid);
title(designSpaceAxes,"Design Space — Colour Indicates Peak Nodal Temperature");
grid(designSpaceAxes,"on");

refreshOptimizationControls();
refreshDesignOptimizationControls();
resetSweepAnalysisPlots();

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

%% Nested callbacks
    function structuralValueChanged(~,~)
        % Native Battery Builder serpentine cooling requires the Module and
        % ParallelAssembly stacking axes to be identical. Keep the GUI
        % structurally self-consistent whenever Serpentine Cooling is active.
        if string(coolingPlateField.Value) == "Serpentine Cooling"
            moduleStackingAxisField.Value = parallelStackingAxisField.Value;
            moduleStackingAxisField.Enable = "off";
        end

        state.NeedsRebuild = true;
        statusLabel.Text = "Structural values changed — click REBUILD BATTERY";
    end

    function geometryValueChanged(~,~)
        % In Automatic mode the thermal cross-section is derived from the
        % geometry normal to the height/Z conduction direction.
        updateThermalAreaForActiveFormat();
        structuralValueChanged([],[]);
    end

    function thermalAreaCustomChanged(~,~)
        % Manual edits are accepted only when the active format uses Custom.
        activeFormat = string(formatField.Value);
        if activeFormat == "Cylindrical"
            key = 'Cylindrical';
        elseif activeFormat == "Prismatic"
            key = 'Prismatic';
        else
            key = 'Pouch';
        end
        if state.(key).ThermalAreaMode ~= "Custom"
            updateThermalAreaForActiveFormat();
            return;
        end
        state.(key).CustomThermalArea_m2 = thermalAreaField.Value;
        state.(key).ThermalArea_m2 = thermalAreaField.Value;
        state.NeedsRebuild = true;
        statusLabel.Text = "Thermal cross-section changed — click REBUILD BATTERY";
    end

    function area_m2 = automaticThermalAreaForActiveFormat()
        activeFormat = string(formatField.Value);
        if activeFormat == "Cylindrical"
            diameter_m = diameterField.Value/1000;
            area_m2 = pi*(diameter_m/2)^2;
        else
            length_m = diameterField.Value/1000;
            thickness_m = thicknessField.Value/1000;
            area_m2 = length_m*thickness_m;
        end
    end

    function updateThermalAreaForActiveFormat()
        activeFormat = string(formatField.Value);
        if activeFormat == "Cylindrical"
            key = 'Cylindrical';
        elseif activeFormat == "Prismatic"
            key = 'Prismatic';
        else
            key = 'Pouch';
        end
        areaMode = state.(key).ThermalAreaMode;
        if areaMode == "Automatic"
            area_m2 = automaticThermalAreaForActiveFormat();
            state.(key).ThermalArea_m2 = area_m2;
            thermalAreaField.Value = area_m2;
            thermalAreaField.Editable = "off";
        else
            area_m2 = state.(key).CustomThermalArea_m2;
            state.(key).ThermalArea_m2 = area_m2;
            thermalAreaField.Value = area_m2;
            thermalAreaField.Editable = "on";
        end
    end

    function saveElectricalStateForFormat(formatName)
        targetN = round(parallelField.Value) * round(seriesField.Value);
        key = char(string(formatName));
        if ~isfield(state,key)
            return;
        end
        state.(key).ExtrapolationMethod = state.ExtrapolationMethod;
        state.(key).VoltageRange_V = state.VoltageRange_V;
        state.(key).OCVSOCBreakpoints = state.OCVSOCBreakpoints;
        state.(key).OCVTemperature_C = state.OCVTemperature_C;
        state.(key).OCVTable_V = state.OCVTable_V;
        state.(key).ResistanceSOCBreakpoints = state.ResistanceSOCBreakpoints;
        state.(key).ResistanceTemperature_C = state.ResistanceTemperature_C;
        state.(key).R0Table_Ohm = state.R0Table_Ohm;
        state.(key).PolarizationModel = state.PolarizationModel;
        state.(key).R1Table_Ohm = state.R1Table_Ohm;
        state.(key).Tau1Table_s = state.Tau1Table_s;
        state.(key).R2Table_Ohm = state.R2Table_Ohm;
        state.(key).Tau2Table_s = state.Tau2Table_s;
        state.(key).EntropicHeatEnabled = state.EntropicHeatEnabled;
        state.(key).EntropicCoefficient_mV_K = state.EntropicCoefficient_mV_K;
        state.(key).R0Deviation_pct = resizeNumericVector(state.R0Deviation_pct,targetN,0);
        state.(key).ThermalMassDeviation_pct = resizeNumericVector(state.ThermalMassDeviation_pct,targetN,0);
        state.(key).ThermalConductivityDeviation_pct = resizeNumericVector(state.ThermalConductivityDeviation_pct,targetN,0);
    end

    function loadElectricalStateForFormat(formatName)
        key = char(string(formatName));
        src = state.(key);
        targetN = round(parallelField.Value) * round(seriesField.Value);
        state.ExtrapolationMethod = src.ExtrapolationMethod;
        state.VoltageRange_V = src.VoltageRange_V;
        state.OCVSOCBreakpoints = src.OCVSOCBreakpoints;
        state.OCVTemperature_C = src.OCVTemperature_C;
        state.OCVTable_V = src.OCVTable_V;
        state.ResistanceSOCBreakpoints = src.ResistanceSOCBreakpoints;
        state.ResistanceTemperature_C = src.ResistanceTemperature_C;
        state.R0Table_Ohm = src.R0Table_Ohm;
        state.PolarizationModel = src.PolarizationModel;
        state.R1Table_Ohm = src.R1Table_Ohm;
        state.Tau1Table_s = src.Tau1Table_s;
        state.R2Table_Ohm = src.R2Table_Ohm;
        state.Tau2Table_s = src.Tau2Table_s;
        state.EntropicHeatEnabled = src.EntropicHeatEnabled;
        state.EntropicCoefficient_mV_K = src.EntropicCoefficient_mV_K;
        state.R0Deviation_pct = resizeNumericVector(src.R0Deviation_pct,targetN,0);
        state.ThermalMassDeviation_pct = resizeNumericVector(src.ThermalMassDeviation_pct,targetN,0);
        state.ThermalConductivityDeviation_pct = resizeNumericVector(src.ThermalConductivityDeviation_pct,targetN,0);
    end

    function topologyChanged(~,~)
        activeFormat = string(formatField.Value);
        if (activeFormat == "Prismatic" || activeFormat == "Pouch") && ...
                string(topologyField.Value) == "SingleStack"
            rowsField.Value = 1;
            rowsField.Enable = "off";
        else
            rowsField.Enable = "on";
        end
        if string(coolingPlateField.Value) == "Serpentine Cooling" && ...
                ~isSerpentineCompatibleConfiguration()
            restoreNonSerpentineCoolingSelection();
            statusLabel.Text = ...
                "Serpentine disabled — requires Cylindrical + Hexagonal; rebuild required";
        else
            statusLabel.Text = "Structural values changed — click REBUILD BATTERY";
        end
        state.NeedsRebuild = true;
    end

    function cellFormatChanged(~,~)
        previousFormat = string(state.CellFormat);
        saveElectricalStateForFormat(previousFormat);
        saveActiveFormatGUIState(previousFormat);

        selectedFormat = string(formatField.Value);
        state.CellFormat = selectedFormat;
        loadFormatGUIState(selectedFormat);
        loadElectricalStateForFormat(selectedFormat);
        updateThermalAreaForActiveFormat();

        % A format switch invalidates the previous Battery Builder mapping.
        state.BatteryThermalNodeCount = [];
        state.BatteryThermalNodeLocations = [];
        state.BatteryThermalNodeDimensions = [];
        state.SerpentineThermalNodeCount = [];
        state.SerpentineThermalNodeLocations = [];
        state.SerpentineThermalNodeDimensions = [];
        state.SideThermalNodeCount = [];
        state.SideThermalNodeLocations = [];
        state.SideThermalNodeDimensions = [];
        state.SideBoundaryCells = [];
        state.NeedsRebuild = true;

        if string(coolingPlateField.Value) == "Serpentine Cooling" && ...
                ~isSerpentineCompatibleConfiguration()
            restoreNonSerpentineCoolingSelection();
            statusLabel.Text = selectedFormat + ...
                " selected — Serpentine Cooling disabled; click REBUILD BATTERY";
        else
            statusLabel.Text = selectedFormat + ...
                " cell selected — click REBUILD BATTERY";
        end
    end

    function saveActiveFormatGUIState(formatName)
        key = char(string(formatName));
        if ~isfield(state,key)
            return;
        end
        state.(key).PlatePartitionsX = state.PlatePartitionsX;
        state.(key).PlatePartitionsY = state.PlatePartitionsY;
        state.(key).P = round(parallelField.Value);
        state.(key).S = round(seriesField.Value);
        state.(key).Height_mm = heightField.Value;
        state.(key).Mass_kg = massField.Value;
        state.(key).Capacity_Ah = capacityField.Value;
        state.(key).Energy_Wh = energyField.Value;
        state.(key).Topology = string(topologyField.Value);
        state.(key).Rows = round(rowsField.Value);
        state.(key).StackingAxis = string(parallelStackingAxisField.Value);
        state.(key).ThermalMass_J_K = thermalMassField.Value;
        state.(key).ConductivityZ_W_mK = conductivityField.Value;
        state.(key).ThermalArea_m2 = thermalAreaField.Value;

        if string(formatName) == "Cylindrical"
            state.Cylindrical.Diameter_mm = diameterField.Value;
        else
            state.(key).Length_mm = diameterField.Value;
            state.(key).Thickness_mm = thicknessField.Value;
        end
        if state.(key).ThermalAreaMode == "Custom"
            state.(key).CustomThermalArea_m2 = thermalAreaField.Value;
        end
        if string(formatName) == "Pouch"
            state.Pouch.TabLocation = string(tabLocationField.Value);
            state.Pouch.TabWidth_mm = tabWidthField.Value;
            state.Pouch.TabHeight_mm = tabHeightField.Value;
        end
    end

    function loadFormatGUIState(formatName)
        key = char(string(formatName));
        src = state.(key);

        state.PlatePartitionsX = src.PlatePartitionsX;
        state.PlatePartitionsY = src.PlatePartitionsY;
        parallelField.Value = src.P;
        seriesField.Value = src.S;
        heightField.Value = src.Height_mm;
        massField.Value = src.Mass_kg;
        capacityField.Value = src.Capacity_Ah;
        energyField.Value = src.Energy_Wh;
        thermalMassField.Value = src.ThermalMass_J_K;
        conductivityField.Value = src.ConductivityZ_W_mK;
        parallelStackingAxisField.Value = src.StackingAxis;

        isPouch = string(formatName) == "Pouch";
        if isPouch
            left.RowHeight(22:24) = {29,29,29};
            tabLocationLabel.Visible = "on";
            tabLocationField.Visible = "on";
            tabWidthLabel.Visible = "on";
            tabWidthField.Visible = "on";
            tabHeightLabel.Visible = "on";
            tabHeightField.Visible = "on";
            tabLocationField.Value = char(state.Pouch.TabLocation);
            tabWidthField.Value = state.Pouch.TabWidth_mm;
            tabHeightField.Value = state.Pouch.TabHeight_mm;
        else
            left.RowHeight(22:24) = {0,0,0};
            tabLocationLabel.Visible = "off";
            tabLocationField.Visible = "off";
            tabWidthLabel.Visible = "off";
            tabWidthField.Visible = "off";
            tabHeightLabel.Visible = "off";
            tabHeightField.Visible = "off";
        end

        if string(formatName) == "Cylindrical"
            diameterLabel.Text = "Diameter (mm)";
            diameterField.Value = src.Diameter_mm;
            thicknessLabel.Visible = "off";
            thicknessField.Visible = "off";
            topologyField.Items = {'Square','Hexagonal'};
            topologyField.Value = char(src.Topology);
            rowsField.Value = src.Rows;
            rowsField.Enable = "on";
        elseif string(formatName) == "Prismatic"
            diameterLabel.Text = "Length (mm)";
            diameterField.Value = src.Length_mm;
            thicknessLabel.Visible = "on";
            thicknessField.Visible = "on";
            thicknessField.Value = src.Thickness_mm;
            topologyField.Items = {'SingleStack','NStack'};
            topologyField.Value = char(src.Topology);
            if string(src.Topology) == "SingleStack"
                rowsField.Value = 1;
                rowsField.Enable = "off";
            else
                rowsField.Value = max(1,src.Rows);
                rowsField.Enable = "on";
            end
        else
            diameterLabel.Text = "Length (mm)";
            diameterField.Value = src.Length_mm;
            thicknessLabel.Visible = "on";
            thicknessField.Visible = "on";
            thicknessField.Value = src.Thickness_mm;
            topologyField.Items = {'SingleStack'};
            topologyField.Value = 'SingleStack';
            rowsField.Value = 1;
            rowsField.Enable = "off";
        end
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
        dynamicsTab = uitab(tabs,"Title","RC & Entropic Heat");
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
        rGrid = uigridlayout(resistanceTab,[5 2]);
        rGrid.ColumnWidth = {260,'1x'};
        rGrid.RowHeight = {34,120,34,'1x',38};
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

        importR0Button = uibutton(rGrid,"push", ...
            "Text","IMPORT R0 FROM EXCEL", ...
            "FontWeight","bold", ...
            "ButtonPushedFcn",@(~,~)importResistanceTableFromExcel("R0"));
        importR0Button.Layout.Row = 5;
        importR0Button.Layout.Column = [1 2];
        refreshR0Labels();

        %% Optional RC polarization dynamics and reversible entropic heat
        dynGrid = uigridlayout(dynamicsTab,[4 2]);
        dynGrid.ColumnWidth = {280,'1x'};
        dynGrid.RowHeight = {38,38,54,'1x'};
        dynGrid.Padding = [14 14 14 14];
        dynGrid.RowSpacing = 8;

        dynModelLabel = uilabel(dynGrid,"Text","Polarization model");
        dynModelLabel.Layout.Row = 1;
        dynModelLabel.Layout.Column = 1;
        polarizationModelField = uidropdown(dynGrid, ...
            "Items",["Disabled","RC1","RC1 + RC2"], ...
            "Value",state.PolarizationModel);
        polarizationModelField.Layout.Row = 1;
        polarizationModelField.Layout.Column = 2;

        entropyLabel = uilabel(dynGrid,"Text","Entropic heat");
        entropyLabel.Layout.Row = 2;
        entropyLabel.Layout.Column = 1;
        entropicHeatCheck = uicheckbox(dynGrid, ...
            "Text","Enable reversible entropic heat", ...
            "Value",logical(state.EntropicHeatEnabled));
        entropicHeatCheck.Layout.Row = 2;
        entropicHeatCheck.Layout.Column = 2;

        dynNote = uilabel(dynGrid, ...
            "Text",["Disabled by default. Enabling/disabling RC or entropic heat changes the Battery Equivalent Circuit topology and therefore requires REBUILD BATTERY. " ...
                    "R1/R2 and Tau1/Tau2 use the same SOC/temperature grid as R0. Entropic coefficient uses the OCV SOC grid and Simscape units of mV/K."], ...
            "WordWrap","on", ...
            "FontAngle","italic");
        dynNote.Layout.Row = 3;
        dynNote.Layout.Column = [1 2];

        dynTabs = uitabgroup(dynGrid);
        dynTabs.Layout.Row = 4;
        dynTabs.Layout.Column = [1 2];
        rc1Tab = uitab(dynTabs,"Title","RC1");
        rc2Tab = uitab(dynTabs,"Title","RC2");
        entropyTab = uitab(dynTabs,"Title","Entropy");

        rc1Grid = uigridlayout(rc1Tab,[3 2]);
        rc1Grid.RowHeight = {30,'1x',36};
        rc1Grid.ColumnWidth = {'1x','1x'};
        rc1Grid.Padding = [8 8 8 8];
        rc1RLabel = uilabel(rc1Grid,"Text","R1(SOC,T) [Ω]","FontWeight","bold");
        rc1RLabel.Layout.Row = 1; rc1RLabel.Layout.Column = 1;
        rc1TauLabel = uilabel(rc1Grid,"Text","Tau1(SOC,T) [s]","FontWeight","bold");
        rc1TauLabel.Layout.Row = 1; rc1TauLabel.Layout.Column = 2;
        r1DataTable = uitable(rc1Grid, ...
            "Data",state.R1Table_Ohm, ...
            "ColumnEditable",true(1,size(state.R1Table_Ohm,2)));
        r1DataTable.Layout.Row = 2; r1DataTable.Layout.Column = 1;
        tau1DataTable = uitable(rc1Grid, ...
            "Data",state.Tau1Table_s, ...
            "ColumnEditable",true(1,size(state.Tau1Table_s,2)));
        tau1DataTable.Layout.Row = 2; tau1DataTable.Layout.Column = 2;

        importR1Button = uibutton(rc1Grid,"push", ...
            "Text","IMPORT R1 FROM EXCEL", ...
            "FontWeight","bold", ...
            "ButtonPushedFcn",@(~,~)importResistanceTableFromExcel("R1"));
        importR1Button.Layout.Row = 3;
        importR1Button.Layout.Column = 1;

        rc2Grid = uigridlayout(rc2Tab,[3 2]);
        rc2Grid.RowHeight = {30,'1x',36};
        rc2Grid.ColumnWidth = {'1x','1x'};
        rc2Grid.Padding = [8 8 8 8];
        rc2RLabel = uilabel(rc2Grid,"Text","R2(SOC,T) [Ω]","FontWeight","bold");
        rc2RLabel.Layout.Row = 1; rc2RLabel.Layout.Column = 1;
        rc2TauLabel = uilabel(rc2Grid,"Text","Tau2(SOC,T) [s]","FontWeight","bold");
        rc2TauLabel.Layout.Row = 1; rc2TauLabel.Layout.Column = 2;
        r2DataTable = uitable(rc2Grid, ...
            "Data",state.R2Table_Ohm, ...
            "ColumnEditable",true(1,size(state.R2Table_Ohm,2)));
        r2DataTable.Layout.Row = 2; r2DataTable.Layout.Column = 1;
        tau2DataTable = uitable(rc2Grid, ...
            "Data",state.Tau2Table_s, ...
            "ColumnEditable",true(1,size(state.Tau2Table_s,2)));
        tau2DataTable.Layout.Row = 2; tau2DataTable.Layout.Column = 2;

        importR2Button = uibutton(rc2Grid,"push", ...
            "Text","IMPORT R2 FROM EXCEL", ...
            "FontWeight","bold", ...
            "ButtonPushedFcn",@(~,~)importResistanceTableFromExcel("R2"));
        importR2Button.Layout.Row = 3;
        importR2Button.Layout.Column = 1;

        entropyGrid = uigridlayout(entropyTab,[2 1]);
        entropyGrid.RowHeight = {42,'1x'};
        entropyGrid.Padding = [8 8 8 8];
        entropyInfo = uilabel(entropyGrid, ...
            "Text","Entropic coefficient dOCV/dT versus OCV SOC breakpoint [mV/K]. Positive or negative values are allowed.", ...
            "WordWrap","on");
        entropyInfo.Layout.Row = 1;
        entropyDataTable = uitable(entropyGrid, ...
            "Data",state.EntropicCoefficient_mV_K(:), ...
            "ColumnName","dOCV/dT (mV/K)", ...
            "ColumnEditable",true, ...
            "RowName",cellstr(compose("SOC %.4g",state.OCVSOCBreakpoints(:))));
        entropyDataTable.Layout.Row = 2;

        refreshDynamicTableLabels();

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

        function refreshDynamicTableLabels()
            soc = resistanceSOCTable.Data(:);
            tc = resistanceTempTable.Data(:).';
            rowNames = cellstr(compose("SOC %.4g",soc));
            colNames = cellstr(compose("%.4g °C",tc));
            if size(r1DataTable.Data,1) == numel(soc)
                r1DataTable.RowName = rowNames;
                tau1DataTable.RowName = rowNames;
                r2DataTable.RowName = rowNames;
                tau2DataTable.RowName = rowNames;
            end
            if size(r1DataTable.Data,2) == numel(tc)
                r1DataTable.ColumnName = colNames;
                tau1DataTable.ColumnName = colNames;
                r2DataTable.ColumnName = colNames;
                tau2DataTable.ColumnName = colNames;
            end
        end

        function importResistanceTableFromExcel(targetName)
            targetName = upper(string(targetName));
            [fileName,pathName] = uigetfile( ...
                {'*.xlsx;*.xls','Excel workbooks (*.xlsx, *.xls)'}, ...
                "Import " + targetName + " Resistance Table");
            if isequal(fileName,0) || isequal(pathName,0), return; end
            filePath = fullfile(pathName,fileName);
            try
                sheets = string(sheetnames(filePath));
            catch
                sheets = "Sheet1";
            end
            sheetToRead = sheets(1);
            idx = find(strcmpi(strtrim(sheets),targetName),1);
            if ~isempty(idx), sheetToRead = sheets(idx); end
            try
                M = readmatrix(filePath,"Sheet",sheetToRead);
            catch MEread
                uialert(dataFig,getReport(MEread,"basic","hyperlinks","off"), ...
                    "ThermalPack — Excel Import Error");
                return;
            end
            if isempty(M) || ~isnumeric(M)
                uialert(dataFig,"No numeric resistance data were found.","ThermalPack — Excel Import");
                return;
            end
            M = M(~all(isnan(M),2),:);
            M = M(:,~all(isnan(M),1));
            importedSOC = []; importedTemp_C = []; importedValues = [];
            if size(M,1)>=2 && size(M,2)>=2
                s = M(2:end,1).'; tt = M(1,2:end); vv = M(2:end,2:end);
                if validSOCBreakpoints(s) && validTemperatureBreakpoints(tt) && all(isfinite(vv),"all")
                    importedSOC = s; importedTemp_C = tt; importedValues = vv;
                end
            end
            currentSOC = resistanceSOCTable.Data(:).';
            currentTemp_C = resistanceTempTable.Data(:).';
            if isempty(importedValues)
                if isequal(size(M),[numel(currentSOC),numel(currentTemp_C)]) && all(isfinite(M),"all")
                    importedValues = M;
                else
                    uialert(dataFig, ...
                        thermalPackFormatText("Excel size %dx%d does not match the current %dx%d resistance grid. Use a values-only matrix or a header matrix with temperature row + SOC column.", ...
                        size(M,1),size(M,2),numel(currentSOC),numel(currentTemp_C)), ...
                        "ThermalPack — Excel Resistance Layout");
                    return;
                end
            end
            if any(importedValues<0,"all")
                uialert(dataFig,"Resistance values must be non-negative.","ThermalPack — Excel Import");
                return;
            end
            units = uiconfirm(dataFig,"Which unit is used in the Excel file?", ...
                "Resistance Unit","Options",["Ohm (Ω)","mOhm (mΩ)","Cancel"], ...
                "DefaultOption","Ohm (Ω)","CancelOption","Cancel");
            if units=="Cancel", return; end
            if units=="mOhm (mΩ)", importedValues = 1e-3*importedValues; end

            if targetName=="R0"
                if ~isempty(importedSOC)
                    resistanceSOCTable.Data = importedSOC(:);
                    resistanceTempTable.Data = importedTemp_C(:);
                    currentSOC = importedSOC; currentTemp_C = importedTemp_C;
                end
                r0DataTable.Data = importedValues;
                r0DataTable.ColumnEditable = true(1,size(importedValues,2));
                targetSize = size(importedValues);
                if ~isequal(size(r1DataTable.Data),targetSize)
                    r1DataTable.Data=zeros(targetSize); tau1DataTable.Data=ones(targetSize);
                end
                if ~isequal(size(r2DataTable.Data),targetSize)
                    r2DataTable.Data=zeros(targetSize); tau2DataTable.Data=ones(targetSize);
                end
                r1DataTable.ColumnEditable=true(1,targetSize(2)); tau1DataTable.ColumnEditable=true(1,targetSize(2));
                r2DataTable.ColumnEditable=true(1,targetSize(2)); tau2DataTable.ColumnEditable=true(1,targetSize(2));
                refreshR0Labels(); refreshDynamicTableLabels();
            else
                if ~isempty(importedSOC)
                    sameSOC = numel(importedSOC)==numel(currentSOC) && all(abs(importedSOC-currentSOC)<=1e-10);
                    sameTemp = numel(importedTemp_C)==numel(currentTemp_C) && all(abs(importedTemp_C-currentTemp_C)<=1e-8);
                    if ~(sameSOC && sameTemp)
                        uialert(dataFig,targetName + " breakpoints do not match the current R0 grid.","ThermalPack — RC Grid Mismatch");
                        return;
                    end
                end
                expected=[numel(currentSOC),numel(currentTemp_C)];
                if ~isequal(size(importedValues),expected)
                    uialert(dataFig,targetName + " must match the R0 SOC×temperature grid.","ThermalPack — RC Grid Mismatch");
                    return;
                end
                if targetName=="R1"
                    r1DataTable.Data=importedValues; r1DataTable.ColumnEditable=true(1,size(importedValues,2));
                else
                    r2DataTable.Data=importedValues; r2DataTable.ColumnEditable=true(1,size(importedValues,2));
                end
                refreshDynamicTableLabels();
            end
            uialert(dataFig,targetName + " imported into the GUI. Review it and click APPLY.", ...
                "ThermalPack — Excel Import","Icon","success");
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
            newPolarizationModel = string(polarizationModelField.Value);
            newEntropicHeatEnabled = logical(entropicHeatCheck.Value);
            r1Values = r1DataTable.Data;
            tau1Values = tau1DataTable.Data;
            r2Values = r2DataTable.Data;
            tau2Values = tau2DataTable.Data;
            entropyValues_mV_K = entropyDataTable.Data(:).';
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

            rcGridSize = [numel(rSOC),numel(rTemp_C)];
            if newPolarizationModel ~= "Disabled"
                if ~isnumeric(r1Values) || ~isequal(size(r1Values),rcGridSize) || ...
                        any(~isfinite(r1Values),"all") || any(r1Values <= 0,"all") || ...
                        ~isnumeric(tau1Values) || ~isequal(size(tau1Values),rcGridSize) || ...
                        any(~isfinite(tau1Values),"all") || any(tau1Values <= 0,"all")
                    uialert(dataFig, ...
                        "RC1 requires positive finite R1(SOC,T) and Tau1(SOC,T) tables on the same grid as R0.", ...
                        "Invalid RC1 Data");
                    return;
                end
            end

            if newPolarizationModel == "RC1 + RC2"
                if ~isnumeric(r2Values) || ~isequal(size(r2Values),rcGridSize) || ...
                        any(~isfinite(r2Values),"all") || any(r2Values <= 0,"all") || ...
                        ~isnumeric(tau2Values) || ~isequal(size(tau2Values),rcGridSize) || ...
                        any(~isfinite(tau2Values),"all") || any(tau2Values <= 0,"all")
                    uialert(dataFig, ...
                        "RC2 requires positive finite R2(SOC,T) and Tau2(SOC,T) tables on the same grid as R0.", ...
                        "Invalid RC2 Data");
                    return;
                end
            end

            if newEntropicHeatEnabled
                if ~isnumeric(entropyValues_mV_K) || ...
                        numel(entropyValues_mV_K) ~= numel(ocvSOC) || ...
                        any(~isfinite(entropyValues_mV_K))
                    uialert(dataFig, ...
                        "Entropic heat requires one finite dOCV/dT value (mV/K) for every OCV SOC breakpoint.", ...
                        "Invalid Entropic Heat Data");
                    return;
                end
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
            oldPolarizationModel = state.PolarizationModel;
            oldEntropicHeatEnabled = logical(state.EntropicHeatEnabled);
            state.PolarizationModel = newPolarizationModel;
            state.R1Table_Ohm = double(r1Values);
            state.Tau1Table_s = double(tau1Values);
            state.R2Table_Ohm = double(r2Values);
            state.Tau2Table_s = double(tau2Values);
            state.EntropicHeatEnabled = newEntropicHeatEnabled;
            state.EntropicCoefficient_mV_K = double(entropyValues_mV_K);
            state.R0Deviation_pct = double(varData(:,2));
            state.ThermalMassDeviation_pct = double(varData(:,3));
            state.ThermalConductivityDeviation_pct = double(varData(:,4));
            saveElectricalStateForFormat(state.CellFormat);

            dynamicsTopologyChanged = ...
                oldPolarizationModel ~= state.PolarizationModel || ...
                oldEntropicHeatEnabled ~= logical(state.EntropicHeatEnabled);
            if dynamicsTopologyChanged
                state.NeedsRebuild = true;
            end

%% If topology has not changed, update the current working block
            if ~state.NeedsRebuild && targetN == state.TotalCells
                if state.ProgressiveForcedAirBuilt
                    applyProgressiveCellElectricalDataToBlocks();
                else
                    applyCellElectricalDataToBlock(batteryBlock,state,state.TotalCells);
                end
                save_system(mdl);
            end

            if dynamicsTopologyChanged
                statusLabel.Text = "RC / entropic topology changed — click REBUILD BATTERY";
            else
                statusLabel.Text = "Cell electrical data applied";
            end
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


    function saveSimulationSetup(~,~)
        % Save configuration only. Generated Battery Builder/Simscape models,
        % simulation logs, validation results and optimization results are
        % deliberately excluded so the file remains portable and stable.

        if ~settingsFileOperationAllowed("save")
            return;
        end

        try
            ThermalPackSettings = captureThermalPackSimulationSettings(); %#ok<NASGU>
        catch MEcapture
            uialert(fig,getReport(MEcapture,"basic","hyperlinks","off"), ...
                "ThermalPack — Save Setup");
            return;
        end

        defaultName = "ThermalPack_Setup_" + ...
            string(datetime("now","Format","yyyyMMdd_HHmmss")) + ".mat";

        [fileName,pathName] = uiputfile( ...
            {'*.mat','ThermalPack simulation setup (*.mat)'}, ...
            'Save ThermalPack Simulation Setup', ...
            fullfile(char(baseFolder),char(defaultName)));

        if isequal(fileName,0) || isequal(pathName,0)
            return;
        end

        targetFile = fullfile(pathName,fileName);

        try
            save(targetFile,"ThermalPackSettings","-mat");
        catch MEsave
            uialert(fig,getReport(MEsave,"basic","hyperlinks","off"), ...
                "ThermalPack — Save Setup Error");
            return;
        end

        statusLabel.Text = "Simulation setup saved — " + string(fileName);
    end

    function loadSimulationSetup(~,~)
        if ~settingsFileOperationAllowed("load")
            return;
        end

        [fileName,pathName] = uigetfile( ...
            {'*.mat','ThermalPack simulation setup (*.mat)'}, ...
            'Load ThermalPack Simulation Setup', ...
            char(baseFolder));

        if isequal(fileName,0) || isequal(pathName,0)
            return;
        end

        sourceFile = fullfile(pathName,fileName);

        try
            loaded = load(sourceFile,"ThermalPackSettings");
        catch MEload
            uialert(fig,getReport(MEload,"basic","hyperlinks","off"), ...
                "ThermalPack — Load Setup Error");
            return;
        end

        if ~isfield(loaded,"ThermalPackSettings") || ...
                ~isstruct(loaded.ThermalPackSettings)
            uialert(fig, ...
                "The selected MAT-file does not contain a ThermalPack simulation setup.", ...
                "ThermalPack — Invalid Setup File");
            return;
        end

        setup = loaded.ThermalPackSettings;

        if ~isfield(setup,"FileType") || ...
                string(setup.FileType) ~= "ThermalPackSimulationSettings"
            uialert(fig, ...
                "This MAT-file is not a recognized ThermalPack simulation setup.", ...
                "ThermalPack — Invalid Setup File");
            return;
        end

        if ~isfield(setup,"SchemaVersion") || ...
                ~isnumeric(setup.SchemaVersion) || ...
                ~isscalar(setup.SchemaVersion) || setup.SchemaVersion < 1
            uialert(fig, ...
                "The setup file does not contain a valid ThermalPack settings schema version.", ...
                "ThermalPack — Invalid Setup File");
            return;
        end

        if setup.SchemaVersion > 1
            uialert(fig, ...
                thermalPackFormatText( ...
                    ["This setup uses schema version %g, while this ThermalPack build " ...
                     "supports version 1. Load it with the same or a newer ThermalPack build."], ...
                    setup.SchemaVersion), ...
                "ThermalPack — Newer Setup File");
            return;
        end

        answer = uiconfirm(fig, ...
            ["Loading this setup replaces the current simulation configuration." ...
             newline newline ...
             "The battery will be marked for REBUILD BATTERY before the next simulation."], ...
            "Load ThermalPack Simulation Setup", ...
            "Options",["Load","Cancel"], ...
            "DefaultOption","Load", ...
            "CancelOption","Cancel");
        if answer ~= "Load"
            return;
        end

        % If the current working model is a generated Progressive Gas model,
        % return to the clean V5 working topology BEFORE applying the saved
        % setup. This prevents stale generated structure surviving the load.
        try
            if state.ProgressiveForcedAirBuilt
                restoreStandardWorkingModelBeforeRebuild();
            end
        catch MErestore
            uialert(fig,getReport(MErestore,"basic","hyperlinks","off"), ...
                "ThermalPack — Could Not Restore Working Model");
            return;
        end

        try
            applyThermalPackSimulationSettings(setup);
        catch MEapply
            uialert(fig,getReport(MEapply,"extended","hyperlinks","off"), ...
                "ThermalPack — Load Setup Error");
            return;
        end

        statusLabel.Text = "Simulation setup loaded — click REBUILD BATTERY";
        uialert(fig, ...
            "Simulation setup loaded successfully. Click REBUILD BATTERY before running the simulation.", ...
            "ThermalPack — Setup Loaded", ...
            "Icon","success");
    end

    function allowed = settingsFileOperationAllowed(operationName)
        allowed = false;

        if state.OptimizationRunning || state.DesignOptimizationRunning
            uialert(fig, ...
                "Simulation settings cannot be saved or loaded while an optimization sweep is running.", ...
                "ThermalPack — Setup File");
            return;
        end

        try
            if bdIsLoaded(mdl)
                simStatus = string(get_param(mdl,"SimulationStatus"));
                if any(simStatus == ["running","paused","initializing","updating"])
                    uialert(fig, ...
                        "Simulation settings cannot be saved or loaded while the model is running or updating.", ...
                        "ThermalPack — Setup File");
                    return;
                end
            end
        catch
        end

        %#ok<NASGU>
        operationName = string(operationName);
        allowed = true;
    end

    function setup = captureThermalPackSimulationSettings()
        % Synchronize any UI values that may not yet have passed through a
        % ValueChanged callback.
        currentFormat = string(formatField.Value);
        state.CellFormat = currentFormat;

        saveElectricalStateForFormat(currentFormat);
        saveActiveFormatGUIState(currentFormat);

        state.P = round(parallelField.Value);
        state.S = round(seriesField.Value);
        state.TotalCells = state.P*state.S;
        state.Topology = string(topologyField.Value);
        state.Rows = round(rowsField.Value);
        state.ParallelAssemblyStackingAxis = ...
            string(parallelStackingAxisField.Value);
        state.ModuleStackingAxis = string(moduleStackingAxisField.Value);
        state.MassFactor = massFactorField.Value;
        state.InterCellGap_mm = cellGapField.Value;
        state.InterAssemblyGap_mm = assemblyGapField.Value;
        state.Height_mm = heightField.Value;
        state.InitialCellTemperature_C = initialCellTempField.Value;
        state.ThermalLimit_C = thermalLimitField.Value;
        state.LoadProfile = string(loadProfileField.Value);
        state.CoolingPlateMode = string(coolingPlateField.Value);
        state.CoolingPlateType = string(coolingPlateTypeField.Value);
        state.InterCellHeatTransfer = string(interCellHeatField.Value);

        storedState = state;

        % Remove runtime/generated/result fields. Keep all engineering inputs,
        % including the complete per-format electrical lookup tables.
        removeExact = [ ...
            "GeneratedLibrary","GeneratedModuleObject","NeedsRebuild", ...
            "OptimizationRunning","OptimizationStopRequested", ...
            "DesignOptimizationRunning","DesignOptimizationStopRequested", ...
            "BatteryThermalNodeCount","BatteryThermalNodeLocations", ...
            "BatteryThermalNodeDimensions","BatteryThermalNodeLocationsTop", ...
            "BatteryThermalNodeDimensionsTop","BatteryThermalNodeLocationsBottom", ...
            "BatteryThermalNodeDimensionsBottom", ...
            "SerpentineThermalNodeCount","SerpentineThermalNodeLocations", ...
            "SerpentineThermalNodeDimensions","HasSerpentinePort", ...
            "SerpentineBranchCreated","SideThermalNodeCount", ...
            "SideThermalNodeLocations","SideThermalNodeDimensions", ...
            "SideBoundaryCells","HasSidePort","SideBranchCreated", ...
            "BuiltSideBoundary"];

        existingExact = intersect(fieldnames(storedState),cellstr(removeExact));
        if ~isempty(existingExact)
            storedState = rmfield(storedState,existingExact);
        end

        names = fieldnames(storedState);
        removePrefix = false(size(names));
        for kk = 1:numel(names)
            thisName = string(names{kk});
            removePrefix(kk) = ...
                startsWith(thisName,"Last") || ...
                startsWith(thisName,"FanFigure2") || ...
                startsWith(thisName,"Fedeli2026") || ...
                startsWith(thisName,"ProgressiveForcedAir");
        end
        prefixNames = names(removePrefix);
        if ~isempty(prefixNames)
            storedState = rmfield(storedState,prefixNames);
        end

        ui = struct;
        ui.CellFormat = currentFormat;
        ui.Topology = string(topologyField.Value);
        ui.ParallelCells = round(parallelField.Value);
        ui.Rows = round(rowsField.Value);
        ui.ParallelAssemblyStackingAxis = ...
            string(parallelStackingAxisField.Value);
        ui.SeriesGroups = round(seriesField.Value);
        ui.ModuleStackingAxis = string(moduleStackingAxisField.Value);
        ui.MassFactor = massFactorField.Value;
        ui.InterCellGap_mm = cellGapField.Value;
        ui.InterAssemblyGap_mm = assemblyGapField.Value;

        ui.DiameterOrLength_mm = diameterField.Value;
        ui.Thickness_mm = thicknessField.Value;
        ui.Height_mm = heightField.Value;
        ui.TabLocation = string(tabLocationField.Value);
        ui.TabWidth_mm = tabWidthField.Value;
        ui.TabHeight_mm = tabHeightField.Value;
        ui.Mass_kg = massField.Value;
        ui.Capacity_Ah = capacityField.Value;
        ui.NominalEnergy_Wh = energyField.Value;
        ui.InitialSOC = socField.Value;
        ui.InitialCellTemperature_C = initialCellTempField.Value;

        ui.ThermalNodes = round(nodesField.Value);
        ui.ThermalMass_J_K = thermalMassField.Value;
        ui.ConductivityZ_W_mK = conductivityField.Value;
        ui.ThermalArea_m2 = thermalAreaField.Value;
        ui.ThermalLimit_C = thermalLimitField.Value;

        ui.LoadProfile = string(loadProfileField.Value);
        ui.StopTime_s = stopField.Value;

        ui.CoolingArchitecture = string(coolingPlateField.Value);
        ui.CoolingPlateType = string(coolingPlateTypeField.Value);
        ui.FlowAllocationMode = string(flowAllocationField.Value);
        ui.CoolantFlow_kg_s = flowField.Value;
        ui.TopFlowShare_pct = topSplitField.Value;
        ui.TopFlow_kg_s = topFlowField.Value;
        ui.BottomFlow_kg_s = bottomFlowField.Value;
        ui.CoolantInlet_C = tinField.Value;
        ui.Ambient_C = ambientField.Value;
        ui.CellToPlateRth_K_W = coolantRField.Value;
        ui.CellToAmbientRth_K_W = ambientRField.Value;
        ui.InterCellHeatTransfer = string(interCellHeatField.Value);
        ui.InterCellRth_K_W = interCellRField.Value;
        ui.InterParallelAssemblyRth_K_W = interParallelRField.Value;

        storeOptimizationRanges();
        ui.OptimizationLiquidRange = state.OptimizationLiquidRange;
        ui.OptimizationAirRange = state.OptimizationAirRange;
        ui.OptimizationInletRange = state.OptimizationInletRange;
        ui.OptimizationTopFlowShareRange = state.OptimizationTopFlowShareRange;
        ui.OptimizationThermalLimit_C = optLimitField.Value;
        ui.OptimizationUniformityLimit_C = optUniformityField.Value;
        storeDesignOptimizationRanges();
        ui.DesignOptimizationRanges = state.DesignOptimizationRanges;

        setup = struct;
        setup.FileType = "ThermalPackSimulationSettings";
        setup.SchemaVersion = 1;
        setup.AppVersion = "ThermalPack Version 2.0";
        setup.SavedAt = char(datetime("now","Format","yyyy-MM-dd HH:mm:ss"));
        setup.State = storedState;
        setup.UI = ui;
    end

    function applyThermalPackSimulationSettings(setup)
        if ~isfield(setup,"State") || ~isstruct(setup.State) || ...
                ~isfield(setup,"UI") || ~isstruct(setup.UI)
            error("ThermalPack:SettingsFileIncomplete", ...
                "The selected setup file is missing required State or UI data.");
        end

        % Merge rather than replace so newer app fields retain their current
        % defaults when loading an older compatible schema.
        state = mergeThermalPackSettingsStruct(state,setup.State);
        ui = setup.UI;

        % Runtime/generated structure must never be restored from disk.
        clearProgressiveForcedAirState();
        state.GeneratedLibrary = "";
        state.GeneratedModuleObject = [];
        state.BatteryThermalNodeCount = [];
        state.BatteryThermalNodeLocations = [];
        state.BatteryThermalNodeDimensions = [];
        state.BatteryThermalNodeLocationsTop = [];
        state.BatteryThermalNodeDimensionsTop = [];
        state.BatteryThermalNodeLocationsBottom = [];
        state.BatteryThermalNodeDimensionsBottom = [];
        state.SerpentineThermalNodeCount = [];
        state.SerpentineThermalNodeLocations = [];
        state.SerpentineThermalNodeDimensions = [];
        state.HasSerpentinePort = false;
        state.SerpentineBranchCreated = false;
        state.SideThermalNodeCount = [];
        state.SideThermalNodeLocations = [];
        state.SideThermalNodeDimensions = [];
        state.SideBoundaryCells = [];
        state.HasSidePort = true;
        state.SideBranchCreated = true;
        state.BuiltSideBoundary = "All";
        state.OptimizationRunning = false;
        state.OptimizationStopRequested = false;
        state.DesignOptimizationRunning = false;
        state.DesignOptimizationStopRequested = false;

        % Apply cell format first so format-specific stored data can populate
        % the correct geometry and electrical controls without overwriting
        % the loaded nested format structures.
        savedFormat = string(ui.CellFormat);
        if ~any(savedFormat == ["Cylindrical","Prismatic","Pouch"])
            error("ThermalPack:SettingsCellFormat", ...
                "Saved cell format '%s' is not supported.",savedFormat);
        end

        state.CellFormat = savedFormat;
        formatField.Value = char(savedFormat);
        loadFormatGUIState(savedFormat);
        loadElectricalStateForFormat(savedFormat);

        % Restore architecture/common geometry.
        parallelField.Value = ui.ParallelCells;
        seriesField.Value = ui.SeriesGroups;
        rowsField.Value = ui.Rows;
        parallelStackingAxisField.Value = char(ui.ParallelAssemblyStackingAxis);
        moduleStackingAxisField.Value = char(ui.ModuleStackingAxis);
        massFactorField.Value = ui.MassFactor;
        cellGapField.Value = ui.InterCellGap_mm;
        assemblyGapField.Value = ui.InterAssemblyGap_mm;

        state.P = round(ui.ParallelCells);
        state.S = round(ui.SeriesGroups);
        state.TotalCells = state.P*state.S;
        state.Rows = round(ui.Rows);
        state.ParallelAssemblyStackingAxis = ...
            string(ui.ParallelAssemblyStackingAxis);
        state.ModuleStackingAxis = string(ui.ModuleStackingAxis);
        state.MassFactor = ui.MassFactor;
        state.InterCellGap_mm = ui.InterCellGap_mm;
        state.InterAssemblyGap_mm = ui.InterAssemblyGap_mm;

        % Format-specific visible geometry. loadFormatGUIState already applies
        % the saved nested format values; UI snapshot values are then restored
        % exactly for the active setup.
        diameterField.Value = ui.DiameterOrLength_mm;
        if savedFormat ~= "Cylindrical"
            thicknessField.Value = ui.Thickness_mm;
        end
        heightField.Value = ui.Height_mm;
        massField.Value = ui.Mass_kg;
        capacityField.Value = ui.Capacity_Ah;
        energyField.Value = ui.NominalEnergy_Wh;

        if savedFormat == "Pouch"
            tabLocationField.Value = char(ui.TabLocation);
            tabWidthField.Value = ui.TabWidth_mm;
            tabHeightField.Value = ui.TabHeight_mm;
        end

        socField.Value = ui.InitialSOC;
        initialCellTempField.Value = ui.InitialCellTemperature_C;
        state.InitialCellTemperature_C = ui.InitialCellTemperature_C;

        nodesField.Value = ui.ThermalNodes;
        thermalMassField.Value = ui.ThermalMass_J_K;
        conductivityField.Value = ui.ConductivityZ_W_mK;
        thermalAreaField.Value = ui.ThermalArea_m2;
        thermalLimitField.Value = ui.ThermalLimit_C;
        state.ThermalLimit_C = ui.ThermalLimit_C;

        loadProfileField.Value = char(ui.LoadProfile);
        stopField.Value = ui.StopTime_s;
        state.LoadProfile = string(ui.LoadProfile);
        state.LastValidLoadProfile = string(ui.LoadProfile);

        % Cooling and environment.
        coolingPlateField.Value = char(ui.CoolingArchitecture);
        coolingPlateTypeField.Value = char(ui.CoolingPlateType);
        flowAllocationField.Value = char(ui.FlowAllocationMode);
        flowField.Value = ui.CoolantFlow_kg_s;
        topSplitField.Value = ui.TopFlowShare_pct;
        topFlowField.Value = ui.TopFlow_kg_s;
        bottomFlowField.Value = ui.BottomFlow_kg_s;
        tinField.Value = ui.CoolantInlet_C;
        ambientField.Value = ui.Ambient_C;
        coolantRField.Value = ui.CellToPlateRth_K_W;
        ambientRField.Value = ui.CellToAmbientRth_K_W;
        interCellHeatField.Value = char(ui.InterCellHeatTransfer);
        interCellRField.Value = ui.InterCellRth_K_W;
        interParallelRField.Value = ui.InterParallelAssemblyRth_K_W;

        state.CoolingPlateMode = string(ui.CoolingArchitecture);
        state.CoolingPlateType = string(ui.CoolingPlateType);
        state.FlowAllocationMode = string(ui.FlowAllocationMode);
        state.MassFlowRate_kg_s = ui.CoolantFlow_kg_s;
        state.TopFlowShare_pct = ui.TopFlowShare_pct;
        state.TopMassFlowRate_kg_s = ui.TopFlow_kg_s;
        state.BottomMassFlowRate_kg_s = ui.BottomFlow_kg_s;
        state.InterCellHeatTransfer = string(ui.InterCellHeatTransfer);

        if state.InterCellHeatTransfer == "Enabled"
            interCellRField.Enable = "on";
            interParallelRField.Enable = "on";
        else
            interCellRField.Enable = "off";
            interParallelRField.Enable = "off";
        end

        % Optional optimization-entry fields are part of the user setup but
        % do not affect a normal simulation until a sweep is requested.
        rangeNames = ["OptimizationLiquidRange","OptimizationAirRange", ...
            "OptimizationInletRange","OptimizationTopFlowShareRange"];
        positiveOnly = [true,true,false,false];
        for kRange = 1:numel(rangeNames)
            if isfield(ui,rangeNames(kRange))
                thermalPackOperatingRange(double(ui.(rangeNames(kRange))), ...
                    rangeNames(kRange),positiveOnly(kRange));
                state.(rangeNames(kRange)) = double(ui.(rangeNames(kRange)));
            end
        end
        splitBounds = state.OptimizationTopFlowShareRange;
        if splitBounds(1) < 0 || splitBounds(2) > 100 || splitBounds(3) > 100
            error("ThermalPack:SettingsOptimizationSplit", ...
                "Saved Top + Bottom flow-share sweep values must remain between 0 and 100 percent.");
        end
        optRangeMode = ""; % Load the stored range for the selected architecture.
        if isfield(ui,"OptimizationThermalLimit_C")
            optLimitField.Value = ui.OptimizationThermalLimit_C;
        end
        if isfield(ui,"OptimizationUniformityLimit_C")
            optUniformityField.Value = ui.OptimizationUniformityLimit_C;
        end
        refreshOptimizationControls();
        if isfield(ui,"DesignOptimizationRanges") && ...
                isstruct(ui.DesignOptimizationRanges)
            state.DesignOptimizationRanges = mergeThermalPackSettingsStruct( ...
                state.DesignOptimizationRanges,ui.DesignOptimizationRanges);
        end
        designRangeMode = "";
        refreshDesignOptimizationControls();
        if isfield(ui,"OptimizationFlowRates") && ...
                ~isfield(ui,"OptimizationLiquidRange")
            uialert(fig, ...
                ["This setup uses the old list-based sweep inputs. " ...
                 "Review the new minimum, maximum and step values before running."], ...
                "ThermalPack — Review Sweep Ranges","Icon","info");
        end

        % Refresh automatic thermal cross-section and cooling-control enable
        % states. Loading always requires a structural rebuild; setting this
        % flag BEFORE coolingModeChanged prevents it from applying the loaded
        % architecture to a stale generated battery.
        updateThermalAreaForActiveFormat();
        state.NeedsRebuild = true;
        refreshFlowAccountingUI();
        coolingModeChanged([],[]);
        state.NeedsRebuild = true;

        % A loaded setup invalidates every result derived from the previous
        % battery configuration.
        pauseThermalAnimation();
        state.LastKPI = [];
        state.LastTrace = [];
        state.LastCoolantTrace = struct();
        state.LastRuntime_s = NaN;
        state.LastCurrentProfileDescription = "";
        state.LastOptimizationResults = table();
        state.LastRecommendedCase = table();
        state.LastOptimizationFolder = "";
        state.LastOptimizationSettings = struct();
        state.LastDesignOptimizationResults = table();
        state.LastRecommendedDesign = table();
        state.LastDesignOptimizationFolder = "";
        state.LastDesignOptimizationSettings = struct();
        optimizationExportButton.Enable = "off";
        optimizationCsvButton.Enable = "off";
        designOptimizationExportButton.Enable = "off";
        designOptimizationCsvButton.Enable = "off";

        cellNodalResultsButton.Enable = "off";
        simulationSummaryButton.Enable = "off";
        exportResultsButton.Enable = "off";

        kpiTmaxValue.Text = "-- °C";
        kpiDeltaValue.Text = "-- °C";
        kpiHotspotValue.Text = "--";
        kpiMarginValue.Text = "-- °C";
        kpiStatusValue.Text = "--";

        cla(temperatureAxes);
        title(temperatureAxes,"Cell Average Temperatures");
        xlabel(temperatureAxes,"Time (s)");
        ylabel(temperatureAxes,"Temperature (°C)");
        grid(temperatureAxes,"on");

        cla(cellAverageEnvelopeAxes);
        title(cellAverageEnvelopeAxes,"Cell-Average Temperature Summary");
        xlabel(cellAverageEnvelopeAxes,"Time (s)");
        ylabel(cellAverageEnvelopeAxes,"Temperature (°C)");
        grid(cellAverageEnvelopeAxes,"on");

        optimizationTable.Data = table();
        cla(optimizationAxes);
        title(optimizationAxes,"Peak Temperature Across the Operating Sweep");
        xlabel(optimizationAxes,"Coolant mass flow rate (kg/s)");
        ylabel(optimizationAxes,"Peak nodal temperature (°C)");
        grid(optimizationAxes,"on");
        optimizationStatus.Text = ...
            "Setup loaded — rebuild the battery before running a cooling sweep.";
        resetSweepAnalysisPlots( ...
            "Setup loaded — rebuild the battery before running a cooling sweep.");
        designOptimizationTable.Data = table();
        resetDesignOptimizationPlots( ...
            "Setup loaded — rebuild the battery before running a design sweep.");

        thermalMapPlaceholder.Visible = "on";
        thermalMapPlaceholder.Text = ...
            "Loaded setup requires REBUILD BATTERY before a new thermal map.";
        thermalMapStatus.Text = ...
            "Simulation setup loaded — thermal map awaiting rebuild and simulation";
        thermalTimeSlider.Enable = "off";
        thermalPlayButton.Enable = "off";
        thermalPauseButton.Enable = "off";
        thermalStopButton.Enable = "off";
        thermalSpeedButton.Enable = "off";

        geometryStatus.Text = ...
            "Simulation setup loaded — click REBUILD BATTERY to regenerate geometry.";
    end

    function merged = mergeThermalPackSettingsStruct(currentValue,savedValue)
        % Recursive compatibility merge. Fields present in the saved setup
        % replace current defaults; fields added by a newer app remain intact.
        if ~(isstruct(currentValue) && isscalar(currentValue) && ...
                isstruct(savedValue) && isscalar(savedValue))
            merged = savedValue;
            return;
        end

        merged = currentValue;
        savedNames = fieldnames(savedValue);
        for kk = 1:numel(savedNames)
            nm = savedNames{kk};
            if isfield(merged,nm) && ...
                    isstruct(merged.(nm)) && isscalar(merged.(nm)) && ...
                    isstruct(savedValue.(nm)) && isscalar(savedValue.(nm))
                merged.(nm) = mergeThermalPackSettingsStruct( ...
                    merged.(nm),savedValue.(nm));
            else
                merged.(nm) = savedValue.(nm);
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

        importLoadExcelButton = uibutton(loadGrid,"push", ...
            "Text","IMPORT EXCEL", ...
            "FontWeight","bold", ...
            "ButtonPushedFcn",@importLoadProfileFromExcel);
        importLoadExcelButton.Layout.Row = 3;
        importLoadExcelButton.Layout.Column = 4;

        applyButton = uibutton(loadGrid,"push", ...
            "Text","APPLY", ...
            "FontWeight","bold", ...
            "ButtonPushedFcn",@applyCustomLoadProfile);
        applyButton.Layout.Row = 3;
        applyButton.Layout.Column = 5;

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

        function importLoadProfileFromExcel(~,~)
            [fileName,pathName] = uigetfile( ...
                {'*.xlsx;*.xls','Excel workbooks (*.xlsx, *.xls)'}, ...
                'Import ThermalPack Load Profile');
            if isequal(fileName,0) || isequal(pathName,0), return; end
            filePath = fullfile(pathName,fileName);
            try
                sheets = string(sheetnames(filePath));
            catch
                sheets = "Sheet1";
            end
            sheetToRead = sheets(1);
            idx=find(strcmpi(strtrim(sheets),"LoadProfile") | strcmpi(strtrim(sheets),"Load Profile"),1);
            if ~isempty(idx), sheetToRead=sheets(idx); end
            try
                M=readmatrix(filePath,"Sheet",sheetToRead);
            catch MEread
                uialert(loadFig,getReport(MEread,"basic","hyperlinks","off"),"ThermalPack — Excel Import");
                return;
            end
            if isempty(M) || size(M,2)<2
                uialert(loadFig,"Excel must contain Time (s) and Current (A) as the first two numeric columns.","Invalid Load Profile Excel File");
                return;
            end
            M=M(:,1:2); M=M(all(isfinite(M),2),:);
            if size(M,1)<2 || abs(M(1,1))>1e-12 || any(M(:,1)<0) || any(diff(M(:,1))<0)
                uialert(loadFig,"Imported profile must contain at least two finite rows, start at 0 s, and use non-decreasing time. Repeated times are allowed.","Invalid Load Profile Excel File");
                return;
            end
            profileTable.Data=double(M); updateLoadProfilePreview();
            uialert(loadFig,thermalPackFormatText("Imported %d Time/Current points from sheet '%s'. Review and click APPLY.",size(M,1),sheetToRead), ...
                "ThermalPack — Load Profile Imported","Icon","success");
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

    function openSerpentineSettings(~,~)
        if ~isSerpentineCompatibleConfiguration()
            uialert(fig, ...
                ["Native Battery Builder serpentine cooling requires " ...
                 "Cylindrical cells with Hexagonal topology."], ...
                "ThermalPack — Serpentine Cooling");
            return;
        end

        parentPos = fig.Position;
        winW = min(720,max(580,parentPos(3)-500));
        winH = 430;
        winX = parentPos(1) + (parentPos(3)-winW)/2;
        winY = parentPos(2) + (parentPos(4)-winH)/2;

        serpFig = uifigure( ...
            "Name","ThermalPack — Serpentine Cooling Settings", ...
            "WindowStyle","modal", ...
            "Position",[winX winY winW winH]);
        movegui(serpFig,"onscreen");

        sg = uigridlayout(serpFig,[7 2]);
        sg.ColumnWidth = {330,'1x'};
        sg.RowHeight = {46,40,40,40,40,'1x',44};
        sg.Padding = [18 18 18 18];
        sg.RowSpacing = 10;
        sg.ColumnSpacing = 10;

        hdr = uilabel(sg, ...
            "Text","NATIVE BATTERY BUILDER SERPENTINE COOLING", ...
            "FontSize",17, ...
            "FontWeight","bold");
        hdr.Layout.Row = 1;
        hdr.Layout.Column = [1 2];

        modeLbl = uilabel(sg,"Text","Serpentine configuration");
        modeLbl.Layout.Row = 2;
        modeLbl.Layout.Column = 1;

        if state.SerpentineMode == "DoubleSidedAlongStackingAxis"
            modeDisplay = "Double sided along stacking axis";
        else
            modeDisplay = "Single sided along stacking axis";
        end

        modeField = uidropdown(sg, ...
            "Items",["Single sided along stacking axis", ...
                     "Double sided along stacking axis"], ...
            "Value",modeDisplay);
        modeField.Layout.Row = 2;
        modeField.Layout.Column = 2;

        circLbl = uilabel(sg,"Text","Cell circumference fraction");
        circLbl.Layout.Row = 3;
        circLbl.Layout.Column = 1;
        circField = uieditfield(sg,"numeric", ...
            "Value",state.SerpentineCircumferenceFraction, ...
            "Limits",[1e-6 0.499999]);
        circField.Layout.Row = 3;
        circField.Layout.Column = 2;

        heightLbl = uilabel(sg,"Text","Cell height fraction");
        heightLbl.Layout.Row = 4;
        heightLbl.Layout.Column = 1;
        heightFracField = uieditfield(sg,"numeric", ...
            "Value",state.SerpentineHeightFraction, ...
            "Limits",[1e-6 0.999999]);
        heightFracField.Layout.Row = 4;
        heightFracField.Layout.Column = 2;

        rthLbl = uilabel(sg,"Text","Cell → serpentine Rth (K/W)");
        rthLbl.Layout.Row = 5;
        rthLbl.Layout.Column = 1;
        rthField = uieditfield(sg,"numeric", ...
            "Value",state.SerpentineContactRth_K_W, ...
            "Limits",[1e-12 Inf]);
        rthField.Layout.Row = 5;
        rthField.Layout.Column = 2;

        if isempty(state.SerpentineThermalNodeCount)
            nodeText = "SP node mapping will be captured on REBUILD BATTERY.";
        else
            nodeText = thermalPackFormatText( ...
                "Current generated SP interface: %d thermal nodes.", ...
                state.SerpentineThermalNodeCount);
        end

        note = uilabel(sg, ...
            "Text",["Compatibility: Cylindrical + Hexagonal only. " ...
                    "Parallel Assembly and Module stacking axes must match; " ...
                    "ThermalPack synchronizes them automatically in Serpentine mode. " ...
                    "The SP interface is generated by Battery Builder and connected " ...
                    "to a dedicated programmatic Parallel Channels / Thermal Liquid loop. " ...
                    "Top/Bottom cell cooling ports remain thermally isolated in Serpentine mode. " ...
                    nodeText], ...
            "WordWrap","on", ...
            "FontAngle","italic");
        note.Layout.Row = 6;
        note.Layout.Column = [1 2];

        btn = uigridlayout(sg,[1 2]);
        btn.Layout.Row = 7;
        btn.Layout.Column = [1 2];
        btn.ColumnWidth = {'1x','1x'};
        btn.Padding = [0 0 0 0];

        applyBtn = uibutton(btn,"push", ...
            "Text","APPLY", ...
            "FontWeight","bold", ...
            "ButtonPushedFcn",@applySerpentineSettings);
        applyBtn.Layout.Column = 1;

        closeBtn = uibutton(btn,"push", ...
            "Text","CLOSE", ...
            "ButtonPushedFcn",@(srcBtn,~)delete(ancestor(srcBtn,"figure")));
        closeBtn.Layout.Column = 2;

        function applySerpentineSettings(~,~)
            if string(modeField.Value) == "Double sided along stacking axis"
                state.SerpentineMode = "DoubleSidedAlongStackingAxis";
            else
                state.SerpentineMode = "SingleSidedAlongStackingAxis";
            end

            state.SerpentineCircumferenceFraction = circField.Value;
            state.SerpentineHeightFraction = heightFracField.Value;
            state.SerpentineContactRth_K_W = rthField.Value;
            state.NeedsRebuild = true;
            statusLabel.Text = ...
                "Serpentine settings changed — click REBUILD BATTERY";
        end
    end

    function openSideCoolingSettings(~,~)
        activeSideFormat = string(formatField.Value);

        parentPos = fig.Position;
        winW = min(720,max(580,parentPos(3)-500));
        winH = 445;
        winX = parentPos(1) + (parentPos(3)-winW)/2;
        winY = parentPos(2) + (parentPos(4)-winH)/2;

        sideFig = uifigure( ...
            "Name","ThermalPack — Side Cooling Settings", ...
            "WindowStyle","modal", ...
            "Position",[winX winY winW winH]);
        movegui(sideFig,"onscreen");

        sgSide = uigridlayout(sideFig,[7 2]);
        sgSide.ColumnWidth = {330,'1x'};
        sgSide.RowHeight = {46,40,40,40,40,'1x',44};
        sgSide.Padding = [18 18 18 18];
        sgSide.RowSpacing = 10;
        sgSide.ColumnSpacing = 10;

        hdrSide = uilabel(sgSide, ...
            "Text","NATIVE BATTERY BUILDER SIDE COOLING", ...
            "FontSize",17, ...
            "FontWeight","bold");
        hdrSide.Layout.Row = 1;
        hdrSide.Layout.Column = [1 2];

        boundaryLbl = uilabel(sgSide,"Text","Vectorized side boundary");
        boundaryLbl.Layout.Row = 2;
        boundaryLbl.Layout.Column = 1;
        boundaryField = uidropdown(sgSide, ...
            "Items",["Xmin","Xmax","Ymin","Ymax"], ...
            "Value",state.SideBoundary);
        boundaryField.Layout.Row = 2;
        boundaryField.Layout.Column = 2;

        sideCircLbl = uilabel(sgSide,"Text","Cell circumference fraction");
        sideCircLbl.Layout.Row = 3;
        sideCircLbl.Layout.Column = 1;
        sideCircField = uieditfield(sgSide,"numeric", ...
            "Value",state.SideCircumferenceFraction, ...
            "Limits",[1e-6 0.5], ...
            "Tooltip","Cylindrical side-contact wrap fraction. Not used for Prismatic or Pouch cells.");
        sideCircField.Layout.Row = 3;
        sideCircField.Layout.Column = 2;

        sideHeightLbl = uilabel(sgSide,"Text","Cell height fraction");
        sideHeightLbl.Layout.Row = 4;
        sideHeightLbl.Layout.Column = 1;
        sideHeightField = uieditfield(sgSide,"numeric", ...
            "Value",state.SideHeightFraction, ...
            "Limits",[1e-6 1], ...
            "Tooltip","Side-contact height fraction used by Battery Builder for Cylindrical, Prismatic, and Pouch cells.");
        sideHeightField.Layout.Row = 4;
        sideHeightField.Layout.Column = 2;

        % Height fraction applies to every supported cell format.
        sideHeightField.Enable = "on";

        % Circumference/wrap fraction only has physical meaning for
        % Cylindrical cells.
        if activeSideFormat == "Cylindrical"
            sideCircField.Enable = "on";
        else
            sideCircField.Enable = "off";
            sideCircLbl.Text = "Cell circumference fraction (Cylindrical only)";
        end

        sideRthLbl = uilabel(sgSide,"Text","Cell → side boundary Rth (K/W)");
        sideRthLbl.Layout.Row = 5;
        sideRthLbl.Layout.Column = 1;
        sideRthField = uieditfield(sgSide,"numeric", ...
            "Value",state.SideContactRth_K_W, ...
            "Limits",[1e-12 Inf]);
        sideRthField.Layout.Row = 5;
        sideRthField.Layout.Column = 2;

        if isempty(state.SideThermalNodeCount)
            try
                selectedSideIndex = find( ...
                    sideBoundaryNames == state.SideBoundary,1);
                sidePlateBlock = sidePlateBlocks(selectedSideIndex);
                state.SideThermalNodeCount = ...
                    round(slResolve(get_param(sidePlateBlock, ...
                    "numBattThermalNodes1"),sidePlateBlock));
                state.SideThermalNodeLocations = ...
                    slResolve(get_param(sidePlateBlock, ...
                    "locationThermalNodes1"),sidePlateBlock);
                state.SideThermalNodeDimensions = ...
                    slResolve(get_param(sidePlateBlock, ...
                    "dimensionThermalNodes1"),sidePlateBlock);
            catch
            end
        end

        if isempty(state.SideThermalNodeCount)
            sideNodeText = ...
                "Side-node mapping is available after the next structural REBUILD BATTERY.";
        elseif isempty(state.SideBoundaryCells)
            sideNodeText = thermalPackFormatText( ...
                "Current %sH interface: %d vectorized thermal nodes.", ...
                state.SideBoundary,state.SideThermalNodeCount);
        else
            sideCellsText = strjoin(string(state.SideBoundaryCells),", ");
            sideNodeText = thermalPackFormatText( ...
                "Current %sH interface: %d vectorized thermal nodes | boundary cells: %s.", ...
                state.SideBoundary,state.SideThermalNodeCount,sideCellsText);
        end

        if activeSideFormat == "Cylindrical"
            sideGeometryText = ...
                "Cylindrical side contact uses the ThermalPack defaults of 100% cell height and 50% circumference. ";
        else
            sideGeometryText = ...
                activeSideFormat + " side cooling uses the selected cell-height fraction; the second local side-node dimension comes directly from Battery Builder face geometry. Circumference fraction is not used. ";
        end

        sideNote = uilabel(sgSide, ...
            "Text",["Xmin, Xmax, Ymin and Ymax remain permanent native Vectorized Battery Builder boundaries for Cylindrical, Prismatic and Pouch cells. " ...
                    sideGeometryText + ...
                    "Each side has its own permanent Parallel Channels / Thermal Liquid loop in Thermal_Model_v5. " ...
                    "Cell → side boundary Rth controls the native X/Y boundary resistance. " ...
                    "Cell → plate Rth controls only Top/Bottom and is disabled while Side Cooling is selected. " ...
                    "The selected side is activated only by its isolation resistance; the other three sides, Top and Bottom remain isolated. " ...
                    sideNodeText], ...
            "WordWrap","on", ...
            "FontAngle","italic");
        sideNote.Layout.Row = 6;
        sideNote.Layout.Column = [1 2];

        sideBtnGrid = uigridlayout(sgSide,[1 2]);
        sideBtnGrid.Layout.Row = 7;
        sideBtnGrid.Layout.Column = [1 2];
        sideBtnGrid.ColumnWidth = {'1x','1x'};
        sideBtnGrid.Padding = [0 0 0 0];

        sideApplyBtn = uibutton(sideBtnGrid,"push", ...
            "Text","APPLY", ...
            "FontWeight","bold", ...
            "ButtonPushedFcn",@applySideSettings);
        sideApplyBtn.Layout.Column = 1;

        sideCloseBtn = uibutton(sideBtnGrid,"push", ...
            "Text","CLOSE", ...
            "ButtonPushedFcn",@(srcBtn,~)delete(ancestor(srcBtn,"figure")));
        sideCloseBtn.Layout.Column = 2;

        function applySideSettings(~,~)
            oldBoundary = state.SideBoundary;
            oldHeightFraction = state.SideHeightFraction;
            oldCircumferenceFraction = state.SideCircumferenceFraction;

            state.SideBoundary = string(boundaryField.Value);

            % Battery Builder uses the cell-height heat-exchange fraction for
            % Cylindrical, Prismatic, and Pouch side thermal boundaries.
            state.SideHeightFraction = sideHeightField.Value;

            % Circumferential wrap is meaningful only for Cylindrical cells.
            if activeSideFormat == "Cylindrical"
                state.SideCircumferenceFraction = sideCircField.Value;
            end

            % Native side thermal-path resistance is independent from the
            % Top/Bottom Cell -> plate resistance.
            state.SideContactRth_K_W = sideRthField.Value;

            % Selecting Xmin/Xmax/Ymin/Ymax does NOT require rebuilding V5:
            % all four ports and branches permanently exist. Changing the
            % heat-exchange geometry does require Battery Builder regeneration.
            geometryChanged = ...
                abs(state.SideHeightFraction-oldHeightFraction) > 1e-12 || ...
                (activeSideFormat == "Cylindrical" && ...
                 abs(state.SideCircumferenceFraction-oldCircumferenceFraction) > 1e-12);

            if geometryChanged
                state.NeedsRebuild = true;
                statusLabel.Text = ...
                    "Side contact geometry changed — click REBUILD BATTERY";
            else
                % Update the selected permanent branch immediately.
                selectedSideIndex = find(sideBoundaryNames == state.SideBoundary,1);
                sideIsolationBlock = sideIsolationBlocks(selectedSideIndex);
                sidePlateBlock = sidePlateBlocks(selectedSideIndex);
                sideFlowSourceBlock = sideFlowSourceBlocks(selectedSideIndex);
                sideInletReservoirBlock = sideInletReservoirBlocks(selectedSideIndex);
                sideOutletReservoirBlock = sideOutletReservoirBlocks(selectedSideIndex);
                sideTLPropertiesBlock = sideTLPropertiesBlocks(selectedSideIndex);

                % Refresh the selected side-node information directly from
                % the permanent V5 Parallel Channels block.
                try
                    state.SideThermalNodeCount = ...
                        round(slResolve(get_param(sidePlateBlock, ...
                        "numBattThermalNodes1"),sidePlateBlock));
                    state.SideThermalNodeLocations = ...
                        slResolve(get_param(sidePlateBlock, ...
                        "locationThermalNodes1"),sidePlateBlock);
                    state.SideThermalNodeDimensions = ...
                        slResolve(get_param(sidePlateBlock, ...
                        "dimensionThermalNodes1"),sidePlateBlock);
                    state.HasSidePort = true;
                    state.SideBranchCreated = true;
                    state.BuiltSideBoundary = "All";
                catch
                end

                if string(coolingPlateField.Value) == "Side Cooling" && ...
                        ~state.NeedsRebuild
                    applyCoolingArchitectureResistance();
                end

                if oldBoundary ~= state.SideBoundary
                    statusLabel.Text = ...
                        "Side Cooling boundary switched to " + state.SideBoundary + ...
                        " — no battery rebuild required";
                else
                    statusLabel.Text = ...
                        "Side thermal resistance updated";
                end
            end
        end
    end

    function air = thermalPackDryAirProperties(T_C,p_Pa)
        %THERMALPACKDRYAIRPROPERTIES Temperature-dependent dry-air backend.
        % Standard dry-air table: 175 to 800 K. mu, k and cp are interpolated
        % with temperature. Density uses actual absolute pressure through
        % rho = p/(R_air*T). Pr is calculated from cp*mu/k. Table basis:
        % standard one-atmosphere dry-air engineering property data.

        if ~(isfinite(T_C) && isscalar(T_C) && ...
                isfinite(p_Pa) && isscalar(p_Pa) && p_Pa > 0)
            error("ThermalPack:AirPropertyInputs", ...
                "Air temperature and absolute pressure must be finite; pressure must be positive.");
        end

        T_K = T_C + 273.15;
        Ttab_K = [175 200 225 250 275 300 325 350 375 400 450 500 550 600 650 700 750 800];
        cpTab_J_kgK = 1000*[1.0023 1.0025 1.0027 1.0031 1.0038 1.0049 1.0063 1.0082 1.0106 1.0135 1.0206 1.0295 1.0398 1.0511 1.0629 1.0750 1.0870 1.0987];
        muTab_Pa_s = 1e-5*[1.182 1.329 1.467 1.599 1.725 1.846 1.962 2.075 2.181 2.286 2.485 2.670 2.849 3.017 3.178 3.332 3.482 3.624];
        kTab_W_mK = 1e-2*[1.593 1.809 2.020 2.227 2.428 2.624 2.816 3.003 3.186 3.365 3.710 4.041 4.357 4.661 4.954 5.236 5.509 5.774];

        if T_K < Ttab_K(1) || T_K > Ttab_K(end)
            msg = thermalPackFormatText( ...
                ["Automatic dry-air properties support %.2f to %.2f degC. " ...
                 "Current inlet temperature is %.3f degC."], ...
                Ttab_K(1)-273.15,Ttab_K(end)-273.15,T_C);
            error("ThermalPack:AirPropertyTemperatureRange",char(msg));
        end

        cp = interp1(Ttab_K,cpTab_J_kgK,T_K,"linear");
        mu = interp1(Ttab_K,muTab_Pa_s,T_K,"linear");
        kAir = interp1(Ttab_K,kTab_W_mK,T_K,"linear");
        Rair_J_kgK = 287.05;
        rho = p_Pa/(Rair_J_kgK*T_K);
        Pr = cp*mu/kAir;

        air = struct("T_C",T_C,"T_K",T_K,"Pressure_Pa",p_Pa, ...
            "rho_kg_m3",rho,"mu_Pa_s",mu,"k_W_mK",kAir, ...
            "cp_J_kgK",cp,"Pr",Pr);
    end

    function [centres_m,nodeDims_m,geometrySource] = forcedAirResolveCellGeometry()
        % Prefer the actual rebuilt Battery Builder X-Y thermal-node geometry.
        % The configured-geometry fallback is used only before a first rebuild.
        fmt = string(state.CellFormat);
        N = max(1,round(state.P)*round(state.S));
        centres_m = [];
        nodeDims_m = [];
        geometrySource = "Configured geometry";

        % Explicit custom geometry has highest precedence when enabled. The
        % downstream calculation is otherwise unchanged: arrangement detection,
        % pitch extraction, AUTO D/Dh classification, gas-column segmentation and
        % convection correlations all operate on these coordinates normally.
        if isfield(state,"ForcedAirCustomGeometryEnabled") && ...
                logical(state.ForcedAirCustomGeometryEnabled)
            customCentres = double(state.ForcedAirCustomCellCentres_m);
            if size(customCentres,1) ~= N || size(customCentres,2) ~= 2 || ...
                    any(~isfinite(customCentres),"all")
                error("ThermalPack:ForcedAirCustomGeometry", ...
                    "Custom forced-air geometry must contain exactly %d finite X-Y cell centres.",N);
            end
            if fmt == "Cylindrical"
                dx_m = state.Diameter_mm/1000;
                dy_m = dx_m;
            else
                dx_m = state.Length_mm/1000;
                dy_m = state.Thickness_mm/1000;
            end
            if ~(isfinite(dx_m) && dx_m > 0 && isfinite(dy_m) && dy_m > 0)
                error("ThermalPack:ForcedAirCustomGeometryDimensions", ...
                    "Cell X-Y dimensions must be positive for custom forced-air geometry.");
            end
            centres_m = customCentres;
            nodeDims_m = repmat([dx_m dy_m],N,1);
            customLabel = "Custom cell-centre geometry";
            if isfield(state,"ForcedAirCustomGeometryLabel") && ...
                    strlength(string(state.ForcedAirCustomGeometryLabel)) > 0
                customLabel = "Custom cell-centre geometry — " + ...
                    string(state.ForcedAirCustomGeometryLabel);
            end
            geometrySource = customLabel;
            return;
        end

        haveBuilt = isfield(state,"BatteryThermalNodeLocations") && ...
            isfield(state,"BatteryThermalNodeDimensions") && ...
            ~isempty(state.BatteryThermalNodeLocations) && ...
            ~isempty(state.BatteryThermalNodeDimensions) && ...
            isfield(state,"TotalCells") && state.TotalCells == N;

        if haveBuilt
            try
                centres_m = thermalPackCellCentres( ...
                    state.BatteryThermalNodeLocations, ...
                    state.BatteryThermalNodeDimensions,N);
                nodeDims_m = thermalPackNodeDimensions( ...
                    state.BatteryThermalNodeDimensions,N);
                if size(centres_m,1) == N && size(nodeDims_m,1) == N && ...
                        all(isfinite(centres_m),"all") && ...
                        all(isfinite(nodeDims_m),"all") && ...
                        all(nodeDims_m > 0,"all")
                    geometrySource = "Battery Builder rebuilt geometry";
                    return;
                end
            catch
                centres_m = [];
                nodeDims_m = [];
            end
        end

        % Geometry-only fallback. This exists so the default square module can
        % calculate forced-air settings even before the first rebuild. Once a
        % battery has been rebuilt, the generated coordinates above are the
        % preferred source of truth.
        P = max(1,round(state.P));
        S = max(1,round(state.S));
        rows = max(1,min(round(state.Rows),P));
        gapCell_m = state.InterCellGap_mm/1000;
        gapAssembly_m = state.InterAssemblyGap_mm/1000;

        if fmt == "Cylindrical"
            dx_m = state.Diameter_mm/1000;
            dy_m = dx_m;
        else
            dx_m = state.Length_mm/1000;
            dy_m = state.Thickness_mm/1000;
        end

        if ~(isfinite(dx_m) && dx_m > 0 && isfinite(dy_m) && dy_m > 0)
            error("ThermalPack:ForcedAirGeometry", ...
                "Cell X-Y dimensions must be positive for forced-air geometry analysis.");
        end

        local = zeros(P,2);
        if fmt == "Cylindrical" && string(state.Topology) == "Hexagonal"
            pitch_m = dx_m + gapCell_m;
            orthPitch_m = sqrt(3)/2*pitch_m;
            for p = 1:P
                r = mod(p-1,rows);
                c = floor((p-1)/rows);
                if string(state.ParallelAssemblyStackingAxis) == "Y"
                    local(p,:) = [r*pitch_m + 0.5*pitch_m*mod(c,2), ...
                                  c*orthPitch_m];
                else
                    local(p,:) = [c*orthPitch_m, ...
                                  r*pitch_m + 0.5*pitch_m*mod(c,2)];
                end
            end
        else
            pitchX_m = dx_m + gapCell_m;
            pitchY_m = dy_m + gapCell_m;
            for p = 1:P
                r = mod(p-1,rows);
                c = floor((p-1)/rows);
                if string(state.ParallelAssemblyStackingAxis) == "Y"
                    local(p,:) = [r*pitchX_m c*pitchY_m];
                else
                    local(p,:) = [c*pitchX_m r*pitchY_m];
                end
            end
        end

        % Shift first cell to a physical centre rather than an origin corner.
        local(:,1) = local(:,1) + 0.5*dx_m;
        local(:,2) = local(:,2) + 0.5*dy_m;
        localExtentX_m = (max(local(:,1))-min(local(:,1))) + dx_m;
        localExtentY_m = (max(local(:,2))-min(local(:,2))) + dy_m;

        if string(state.ModuleStackingAxis) == "X"
            assemblyPitch_m = localExtentX_m + gapAssembly_m;
            assemblyStep = [assemblyPitch_m 0];
        else
            assemblyPitch_m = localExtentY_m + gapAssembly_m;
            assemblyStep = [0 assemblyPitch_m];
        end

        centres_m = zeros(N,2);
        nodeDims_m = repmat([dx_m dy_m],N,1);
        idx = 1;
        for ss = 1:S
            shift = (ss-1)*assemblyStep;
            for pp = 1:P
                centres_m(idx,:) = local(pp,:) + shift;
                idx = idx + 1;
            end
        end
    end

    function [groupCentres,groupIndex] = forcedAirClusterCoordinates(values,tolerance)
        values = double(values(:));
        if isempty(values)
            groupCentres = [];
            groupIndex = [];
            return;
        end
        [sortedValues,order] = sort(values);
        groupSorted = zeros(size(sortedValues));
        groupCentres = sortedValues(1);
        groupCounts = 1;
        groupSorted(1) = 1;
        g = 1;
        for kk = 2:numel(sortedValues)
            if abs(sortedValues(kk)-groupCentres(g)) <= tolerance
                groupCounts(g) = groupCounts(g) + 1;
                groupCentres(g) = groupCentres(g) + ...
                    (sortedValues(kk)-groupCentres(g))/groupCounts(g);
                groupSorted(kk) = g;
            else
                g = g + 1;
                groupCentres(g,1) = sortedValues(kk); %#ok<AGROW>
                groupCounts(g,1) = 1; %#ok<AGROW>
                groupSorted(kk) = g;
            end
        end
        groupIndex = zeros(size(values));
        groupIndex(order) = groupSorted;
        groupCentres = groupCentres(:);
    end

    function geo = forcedAirGeometryAnalysis(flowAxis)
        flowAxis = upper(string(flowAxis));
        if ~(flowAxis == "X" || flowAxis == "Y")
            error("ThermalPack:ForcedAirAxis", ...
                "Uniform AmbH forced air requires airflow axis X or Y.");
        end

        [centres_m,nodeDims_m,geometrySource] = forcedAirResolveCellGeometry();
        N = size(centres_m,1);
        if N < 1
            error("ThermalPack:ForcedAirGeometry", ...
                "No cell centres are available for forced-air geometry analysis.");
        end

        if flowAxis == "X"
            flowIdx = 1;
            transIdx = 2;
        else
            flowIdx = 2;
            transIdx = 1;
        end

        flowCoord = centres_m(:,flowIdx);
        transCoord = centres_m(:,transIdx);
        cellFlowDim_m = median(nodeDims_m(:,flowIdx));
        cellTransDim_m = median(nodeDims_m(:,transIdx));
        tol = max(1e-8,0.03*min(nodeDims_m,[],"all"));
        [columnCentres,columnIndex] = forcedAirClusterCoordinates(flowCoord,tol);
        nColumns = numel(columnCentres);
        columnCounts = accumarray(columnIndex,1,[nColumns 1]);
        nRows = max(columnCounts);

        if nColumns >= 2
            SL_m = median(diff(sort(columnCentres)));
        else
            SL_m = NaN;
        end

        transverseDiffs = [];
        for gg = 1:nColumns
            tv = sort(transCoord(columnIndex == gg));
            if numel(tv) >= 2
                d = diff(tv);
                d = d(d > tol);
                transverseDiffs = [transverseDiffs; d(:)]; %#ok<AGROW>
            end
        end
        if isempty(transverseDiffs)
            ST_m = NaN;
        else
            ST_m = median(transverseDiffs);
        end

        arrangement = "";
        confidence = "High";
        fmt = string(state.CellFormat);

        if fmt == "Cylindrical"
            D_m = state.Diameter_mm/1000;
            if N == 1
                arrangement = "Isolated cylinder";
            elseif nColumns < 2 || nRows < 2 || ~isfinite(ST_m) || ~isfinite(SL_m)
                arrangement = "Single-row / sparse cylinders";
                confidence = "Reduced-order fallback";
            elseif ST_m <= D_m
                error("ThermalPack:ForcedAirGeometry", ...
                    "Detected transverse cylindrical pitch must exceed the cell diameter.");
            else
                phases = nan(nColumns,1);
                for gg = 1:nColumns
                    tv = transCoord(columnIndex == gg);
                    phases(gg) = mod(tv(1)/ST_m,1);
                end
                dphase = abs(phases-phases(1));
                dphase = min(dphase,1-dphase);
                if all(dphase < 0.12)
                    arrangement = "Aligned cylindrical tube bank";
                elseif all((dphase < 0.15) | (abs(dphase-0.5) < 0.15)) && ...
                        any(abs(dphase-0.5) < 0.15)
                    arrangement = "Staggered cylindrical tube bank";
                else
                    arrangement = "Irregular cylindrical array";
                    confidence = "Reduced-order fallback";
                end
            end
        else
            % Broad-face forced-air support is deliberately limited to flow
            % tangent to the long in-plane cell dimension. Flow along the short
            % thickness direction is normal to the broad face and needs an
            % a separate impingement/bluff-body model.
            if cellFlowDim_m + tol < cellTransDim_m
                arrangement = "Broad-face normal-flow geometry";
                confidence = "Unsupported";
            elseif nRows >= 2 && isfinite(ST_m) && ST_m > cellTransDim_m + tol
                arrangement = "Parallel rectangular air channels";
            else
                arrangement = "External broad-face flat-plate flow";
            end
        end

        % Outer module envelope in the X-Y plane. These are based on the
        % actual per-cell dimensions rather than centre-to-centre pitch alone.
        transverseMin_m = min(transCoord - 0.5*nodeDims_m(:,transIdx));
        transverseMax_m = max(transCoord + 0.5*nodeDims_m(:,transIdx));
        arrayTransverseWidth_m = transverseMax_m - transverseMin_m;

        flowMin_m = min(flowCoord - 0.5*nodeDims_m(:,flowIdx));
        flowMax_m = max(flowCoord + 0.5*nodeDims_m(:,flowIdx));
        arrayFlowLength_m = flowMax_m - flowMin_m;

        % One progressive-air control volume is associated with each detected
        % flowwise column. Boundaries are halfway between adjacent column
        % centres, with the first/last boundary on the outer cell envelope.
        % The resulting segment lengths sum exactly to the detected pack length.
        if nColumns == 1
            segmentLengths_m = arrayFlowLength_m;
        else
            sortedColumnCentres = sort(columnCentres(:));
            internalBounds = 0.5*(sortedColumnCentres(1:end-1) + ...
                sortedColumnCentres(2:end));
            segmentBounds = [flowMin_m; internalBounds; flowMax_m];
            segmentLengths_m = diff(segmentBounds);
        end
        if any(~isfinite(segmentLengths_m)) || any(segmentLengths_m <= 0)
            error("ThermalPack:ForcedAirSegmentGeometry", ...
                "Detected progressive-air segment lengths must all be positive.");
        end

        geo = struct("FlowAxis",flowAxis,"CellFormat",fmt, ...
            "Arrangement",arrangement,"Confidence",confidence, ...
            "GeometrySource",geometrySource,"Centres_m",centres_m, ...
            "NodeDims_m",nodeDims_m,"FlowDim_m",cellFlowDim_m, ...
            "TransverseDim_m",cellTransDim_m,"ST_m",ST_m,"SL_m",SL_m, ...
            "Columns",nColumns,"Rows",nRows, ...
            "ColumnCentres_m",columnCentres(:), ...
            "ColumnIndex",columnIndex(:), ...
            "ColumnCounts",columnCounts(:), ...
            "FlowCoordinate_m",flowCoord(:), ...
            "TransverseCoordinate_m",transCoord(:), ...
            "SegmentLengths_m",segmentLengths_m(:), ...
            "FlowMin_m",flowMin_m,"FlowMax_m",flowMax_m, ...
            "ArrayTransverseWidth_m",arrayTransverseWidth_m, ...
            "ArrayFlowLength_m",arrayFlowLength_m);
    end

    function epsilon = forcedAirTubeBankColumnCorrection(arrangement,Re,nColumns)
        % Finite-row factors retained from the validated tube-bank branch for
        % up to 9 flowwise columns. Larger banks use the asymptotic factor 1.
        n = round(nColumns);
        if n < 1
            epsilon = 1;
            return;
        end
        if n > 9
            epsilon = 1;
            return;
        end
        epsAlignedHigh = [0.700 0.800 0.865 0.910 0.928 0.942 0.954 0.965 0.972];
        epsStaggeredMid = [0.832 0.874 0.914 0.939 0.955 0.963 0.970 0.976 0.980];
        epsStaggeredHigh = [0.619 0.758 0.840 0.897 0.923 0.942 0.954 0.965 0.971];
        if startsWith(arrangement,"Aligned")
            if Re >= 1e3
                epsilon = epsAlignedHigh(n);
            else
                epsilon = 1;
            end
        else
            if Re >= 1e3
                epsilon = epsStaggeredHigh(n);
            elseif Re >= 1e2
                epsilon = epsStaggeredMid(n);
            else
                epsilon = 1;
            end
        end
    end

    function sel = forcedAirCylindricalAutoSelection(geo,D_m,wallClearance_m)
        % Generalized cylindrical D-versus-Dh selector.
        %
        % This is an engineering classifier, not a claim of a universal
        % literature switch. The geometry gates are intentionally explicit
        % and auditable. The future correlation-validation gate is stored in
        % metadata but is not currently enforced.
        %
        % Compact:       PT <= 1.25 AND PL <= 1.25
        % Transitional:  not compact AND max(PT,PL) < 1.40
        % Wall bounded:  left/right wall surface clearance divided by the
        %                transverse inter-cell gap is < 2 on both sides
        % Repeated:      at least 4 streamwise columns
        % AUTO Dh:       compact AND wall bounded AND repeated
        % Otherwise:     D

        compactLimit = state.ForcedAirCylindricalCompactPitchLimit;
        transitionLimit = state.ForcedAirCylindricalTransitionPitchLimit;
        wallLimit = state.ForcedAirCylindricalWallRatioLimit;
        minColumns = state.ForcedAirCylindricalMinStreamwiseColumnsForDh;

        sel = struct( ...
            "Regime","Non-bank cylindrical cross-flow", ...
            "UseDh",false, ...
            "ReLengthSelected","Cell Diameter", ...
            "SelectionSource","Auto", ...
            "PitchRatioT",NaN, ...
            "PitchRatioL",NaN, ...
            "WallRatioLeft",NaN, ...
            "WallRatioRight",NaN, ...
            "PassageGap_m",NaN, ...
            "CandidateDh_m",NaN, ...
            "IsCompact",false, ...
            "IsTransitional",false, ...
            "IsWallBounded",false, ...
            "IsRepeated",false, ...
            "DhEligible",false, ...
            "CorrelationValidationRequired",logical(state.ForcedAirDhCorrelationValidationRequired), ...
            "CorrelationValidationStatus",string(state.ForcedAirDhCorrelationValidationStatus), ...
            "CorrelationValidationApplied",logical(state.ForcedAirDhCorrelationValidationApplied));

        isBank = startsWith(geo.Arrangement,"Aligned") || ...
            startsWith(geo.Arrangement,"Staggered");
        if ~isBank || ~isfinite(geo.ST_m) || ~isfinite(geo.SL_m)
            return;
        end
        if ~(isfinite(D_m) && D_m > 0 && geo.ST_m > D_m && geo.SL_m > 0)
            return;
        end

        PT = geo.ST_m/D_m;
        PL = geo.SL_m/D_m;
        transverseGap_m = geo.ST_m-D_m;
        CwL = wallClearance_m/transverseGap_m;
        CwR = wallClearance_m/transverseGap_m; % current UI uses symmetric clearance

        isCompact = PT <= compactLimit && PL <= compactLimit;
        isTransitional = ~isCompact && max(PT,PL) < transitionLimit;
        isWallBounded = CwL < wallLimit && CwR < wallLimit;
        isRepeated = geo.Columns >= minColumns;
        dhEligible = isCompact && isWallBounded && isRepeated;

        % Candidate passage Dh uses the same minimum-gap concept as the
        % velocity calculation. The second passage dimension is ST, matching
        % the current Fan-aligned confined-passage representation.
        if startsWith(geo.Arrangement,"Staggered")
            SD_m = sqrt(geo.SL_m^2 + (0.5*geo.ST_m)^2);
            normalGap_m = geo.ST_m-D_m;
            diagonalGap_m = 2*(SD_m-D_m);
            if isfinite(diagonalGap_m) && diagonalGap_m > 0 && ...
                    diagonalGap_m < normalGap_m
                passageGap_m = diagonalGap_m;
            else
                passageGap_m = normalGap_m;
            end
        else
            passageGap_m = transverseGap_m;
        end
        candidateDh_m = 2*passageGap_m*geo.ST_m/(passageGap_m+geo.ST_m);

        if dhEligible
            regime = "Confined Cylindrical Passage";
            useDh = true;
            selected = "Hydraulic Diameter";
        elseif isCompact
            regime = "Compact Tube Bank (D retained)";
            useDh = false;
            selected = "Cell Diameter";
        elseif isTransitional
            regime = "Transitional Compact Tube Bank";
            useDh = false;
            selected = "Cell Diameter";
        else
            regime = "Conventional Tube Bank";
            useDh = false;
            selected = "Cell Diameter";
        end

        sel.Regime = regime;
        sel.UseDh = useDh;
        sel.ReLengthSelected = selected;
        sel.PitchRatioT = PT;
        sel.PitchRatioL = PL;
        sel.WallRatioLeft = CwL;
        sel.WallRatioRight = CwR;
        sel.PassageGap_m = passageGap_m;
        sel.CandidateDh_m = candidateDh_m;
        sel.IsCompact = isCompact;
        sel.IsTransitional = isTransitional;
        sel.IsWallBounded = isWallBounded;
        sel.IsRepeated = isRepeated;
        sel.DhEligible = dhEligible;
    end

    function calc = forcedAirGeneralCalculation(V_m_s,Tair_C,pAir_Pa,flowAxis,wallClearance_mm)
        if ~(isfinite(V_m_s) && isscalar(V_m_s) && V_m_s > 0)
            error("ThermalPack:ForcedAirInputs", ...
                "Approach air velocity must be positive.");
        end
        if nargin < 5 || isempty(wallClearance_mm) || ...
                ~(isfinite(wallClearance_mm) && isscalar(wallClearance_mm) && wallClearance_mm >= 0)
            error("ThermalPack:ForcedAirWallClearance", ...
                "Cell-to-duct wall gap must be a finite non-negative value in mm.");
        end
        air = thermalPackDryAirProperties(Tair_C,pAir_Pa);
        geo = forcedAirGeometryAnalysis(flowAxis);
        fmt = geo.CellFormat;
        H_m = state.Height_mm/1000;

        % Gross inlet/duct area is deliberately kept separate from the local
        % minimum-gap velocity used by the convection correlation. The user
        % supplies approach velocity at the duct inlet. ThermalPack uses the
        % rebuilt array width plus one symmetric wall clearance on each
        % transverse side to determine the gross inlet area and mass flow.
        wallClearance_m = wallClearance_mm/1000;
        arrayTransverseWidth_m = geo.ArrayTransverseWidth_m;
        ductWidth_m = arrayTransverseWidth_m + 2*wallClearance_m;
        ductHeight_m = H_m; % v2.0 assumption: duct spans the active cell height.
        flowArea_m2 = ductWidth_m*ductHeight_m;
        if ~(isfinite(flowArea_m2) && flowArea_m2 > 0)
            error("ThermalPack:ForcedAirDuctArea", ...
                "Calculated forced-air inlet area must be positive.");
        end
        volumetricFlow_m3_s = V_m_s*flowArea_m2;
        massFlow_kg_s = air.rho_kg_m3*volumetricFlow_m3_s;

        % Representative one-column streamwise segment. This does not alter
        % the current single-AmbH solution; it is stored for the progressive
        % Gas-network model where each flowwise group receives one gas volume.
        if isfinite(geo.SL_m) && geo.SL_m > 0
            segmentLength_m = geo.SL_m;
        else
            segmentLength_m = max(geo.FlowDim_m,geo.ArrayFlowLength_m);
        end
        representativeGasVolume_m3 = flowArea_m2*segmentLength_m;
        Veff = V_m_s;
        Dh_m = NaN;
        Lc_m = NaN;
        epsilon = 1;
        correlation = "";
        nuLength_m = NaN;
        cylRegime = "Not applicable";
        cylReLengthSelected = "Not applicable";
        cylSelectionSource = "Not applicable";
        cylPitchRatioT = NaN;
        cylPitchRatioL = NaN;
        cylWallRatioLeft = NaN;
        cylWallRatioRight = NaN;
        cylPassageGap_m = NaN;
        cylCandidateDh_m = NaN;
        cylDhEligible = false;
        cylIsCompact = false;
        cylIsTransitional = false;
        cylIsWallBounded = false;
        cylIsRepeated = false;
        dhCorrelationValidationRequired = logical(state.ForcedAirDhCorrelationValidationRequired);
        dhCorrelationValidationStatus = string(state.ForcedAirDhCorrelationValidationStatus);
        dhCorrelationValidationApplied = logical(state.ForcedAirDhCorrelationValidationApplied);

        if fmt == "Cylindrical"
            D_m = state.Diameter_mm/1000;
            Lc_m = D_m;
            nuLength_m = D_m;
            Aeff = state.ForcedAirExposedAreaFraction*pi*D_m*H_m;

            % AUTO selects D or Dh from rebuilt geometry. Hidden manual
            % overrides remain available for engineering diagnostics.
            requestedReLengthMode = "Auto";
            if isfield(state,"ForcedAirCylindricalReLengthMode")
                requestedReLengthMode = string(state.ForcedAirCylindricalReLengthMode);
            end
            cylSel = forcedAirCylindricalAutoSelection(geo,D_m,wallClearance_m);
            cylRegime = cylSel.Regime;
            cylReLengthSelected = cylSel.ReLengthSelected;
            cylSelectionSource = cylSel.SelectionSource;
            cylPitchRatioT = cylSel.PitchRatioT;
            cylPitchRatioL = cylSel.PitchRatioL;
            cylWallRatioLeft = cylSel.WallRatioLeft;
            cylWallRatioRight = cylSel.WallRatioRight;
            cylPassageGap_m = cylSel.PassageGap_m;
            cylCandidateDh_m = cylSel.CandidateDh_m;
            cylDhEligible = cylSel.DhEligible;
            cylIsCompact = cylSel.IsCompact;
            cylIsTransitional = cylSel.IsTransitional;
            cylIsWallBounded = cylSel.IsWallBounded;
            cylIsRepeated = cylSel.IsRepeated;

            if requestedReLengthMode == "Hydraulic Diameter"
                cylSel.UseDh = true;
                cylReLengthSelected = "Hydraulic Diameter";
                cylSelectionSource = "Manual override";
                cylRegime = cylRegime + " | manual Dh override";
            elseif requestedReLengthMode == "Cell Diameter"
                cylSel.UseDh = false;
                cylReLengthSelected = "Cell Diameter";
                cylSelectionSource = "Manual override";
                cylRegime = cylRegime + " | manual D override";
            end

            useBank = startsWith(geo.Arrangement,"Aligned") || ...
                startsWith(geo.Arrangement,"Staggered");

            if useBank
                ST_m = geo.ST_m;
                SL_m = geo.SL_m;
                if startsWith(geo.Arrangement,"Aligned")
                    Veff = V_m_s*ST_m/(ST_m-D_m);
                else
                    SD_m = sqrt(SL_m^2 + (0.5*ST_m)^2);
                    normalGap_m = ST_m-D_m;
                    diagonalGap_m = 2*(SD_m-D_m);
                    if diagonalGap_m > 0 && diagonalGap_m < normalGap_m
                        Veff = V_m_s*ST_m/diagonalGap_m;
                    else
                        Veff = V_m_s*ST_m/normalGap_m;
                    end
                end

                reLength_m = D_m;
                useHydraulicRe = logical(cylSel.UseDh);
                if useHydraulicRe
                    if ~(isfinite(cylSel.CandidateDh_m) && cylSel.CandidateDh_m > 0)
                        error("ThermalPack:ForcedAirHydraulicDiameter", ...
                            "AUTO hydraulic-diameter selection produced an invalid passage Dh.");
                    end
                    Dh_m = cylSel.CandidateDh_m;
                    reLength_m = Dh_m;
                    Lc_m = Dh_m;
                    % Current confined cylindrical formulation: Re uses Dh,
                    % while Nu-to-h remains referenced to cell diameter D.
                    nuLength_m = D_m;
                else
                    Dh_m = NaN;
                    Lc_m = D_m;
                    nuLength_m = D_m;
                end

                Re = air.rho_kg_m3*Veff*reLength_m/air.mu_Pa_s;
                epsilon = forcedAirTubeBankColumnCorrection(geo.Arrangement,Re,geo.Columns);

                if startsWith(geo.Arrangement,"Aligned")
                    if Re >= 1 && Re < 1e2
                        Nu = 0.90*Re^0.40*air.Pr^0.36;
                    elseif Re >= 1e2 && Re < 1e3
                        Nu = 0.52*Re^0.50*air.Pr^0.36;
                    elseif Re >= 1e3 && Re < 1e5
                        Nu = epsilon*0.27*Re^0.63*air.Pr^0.36;
                    else
                        useBank = false;
                    end
                    correlation = "Aligned cylindrical tube-bank correlation";
                else
                    spacingRatio = ST_m/SL_m;
                    if Re >= 1 && Re < 5e2
                        Nu = epsilon*1.04*Re^0.40*air.Pr^0.36;
                    elseif Re >= 5e2 && Re < 1e3
                        Nu = epsilon*0.71*Re^0.50*air.Pr^0.36;
                    elseif Re >= 1e3 && Re < 2e5 && spacingRatio <= 2
                        Nu = epsilon*0.35*spacingRatio^0.20*Re^0.60*air.Pr^0.36;
                    else
                        useBank = false;
                    end
                    correlation = "Staggered cylindrical tube-bank correlation";
                end

                if useBank
                    if useHydraulicRe
                        correlation = correlation + ...
                            " | AUTO/selected Re length = Dh passage | Nu length = D cell";
                    else
                        correlation = correlation + ...
                            " | AUTO/selected Re length = D cell | Nu length = D cell";
                    end
                    correlation = correlation + " | " + cylRegime;
                end
            end

            if ~useBank
                % Sparse/irregular single-cylinder fallback always uses D;
                % there is no repeated channel for a passage Dh definition.
                Veff = V_m_s;
                Dh_m = NaN;
                Lc_m = D_m;
                nuLength_m = D_m;
                Re = air.rho_kg_m3*Veff*D_m/air.mu_Pa_s;
                Nu = 0.3 + ...
                    (0.62*sqrt(Re)*air.Pr^(1/3)) / ...
                    (1 + (0.4/air.Pr)^(2/3))^(1/4) * ...
                    (1 + (Re/282000)^(5/8))^(4/5);
                if contains(geo.Arrangement,"Irregular") || ...
                        contains(geo.Arrangement,"Single-row")
                    correlation = "Churchill-Bernstein fallback for sparse/irregular cylindrical cross-flow";
                else
                    correlation = "Churchill-Bernstein single-cylinder cross-flow";
                end
                epsilon = 1;
                cylReLengthSelected = "Cell Diameter";
                if startsWith(geo.Arrangement,"Aligned") || startsWith(geo.Arrangement,"Staggered")
                    cylSelectionSource = "Correlation-range fallback";
                    cylRegime = "Tube-bank correlation out of range — D cylinder fallback";
                elseif requestedReLengthMode == "Hydraulic Diameter"
                    cylSelectionSource = "Fallback override rejected";
                    cylRegime = "Sparse/irregular cylinder — D required";
                else
                    cylSelectionSource = "Auto fallback";
                    cylRegime = "Sparse/irregular cylinder — D required";
                end
            end
            h = Nu*air.k_W_mK/nuLength_m;

        else
            if geo.Confidence == "Unsupported"
                msg = thermalPackFormatText( ...
                    ["For %s cells, airflow along %s is normal to the broad face " ...
                     "for the rebuilt orientation. ThermalPack supports tangential broad-face " ...
                     "flat-plate/channel flow only; choose the other in-plane axis. Normal broad-face impingement is not yet implemented."], ...
                    fmt,geo.FlowAxis);
                error("ThermalPack:ForcedAirPrismaticOrientation",char(msg));
            end

            Lflow_m = geo.FlowDim_m;
            Lc_m = Lflow_m;
            nuLength_m = Lflow_m;
            Aeff = 2*Lflow_m*H_m;

            if startsWith(geo.Arrangement,"Parallel rectangular")
                gap_m = geo.ST_m-geo.TransverseDim_m;
                if ~(isfinite(gap_m) && gap_m > 0)
                    error("ThermalPack:ForcedAirChannelGap", ...
                        "Detected rectangular air-channel gap must be positive.");
                end
                Veff = V_m_s*geo.ST_m/gap_m;
                Dh_m = 2*gap_m*H_m/(gap_m+H_m);
                Lc_m = Dh_m;
                nuLength_m = Dh_m;
                Re = air.rho_kg_m3*Veff*Dh_m/air.mu_Pa_s;
                alpha = min(gap_m,H_m)/max(gap_m,H_m);
                NuLam = 7.541*(1 - 2.610*alpha + 4.970*alpha^2 - ...
                    5.119*alpha^3 + 2.702*alpha^4 - 0.548*alpha^5);
                if Re <= 2300
                    Nu = NuLam;
                    correlation = "Fully developed laminar rectangular-channel correlation";
                else
                    fDarcy = (0.79*log(max(Re,3000))-1.64)^(-2);
                    NuTurb = (fDarcy/8)*(max(Re,3000)-1000)*air.Pr / ...
                        (1 + 12.7*sqrt(fDarcy/8)*(air.Pr^(2/3)-1));
                    if Re < 3000
                        w = (Re-2300)/(3000-2300);
                        Nu = (1-w)*NuLam + w*NuTurb;
                        correlation = "Laminar-to-Gnielinski rectangular-channel transition";
                    else
                        Nu = NuTurb;
                        correlation = "Gnielinski turbulent rectangular-channel correlation";
                    end
                end
                h = Nu*air.k_W_mK/Dh_m;
            else
                Veff = V_m_s;
                Re = air.rho_kg_m3*Veff*Lflow_m/air.mu_Pa_s;
                if Re <= 5e5
                    Nu = 0.664*sqrt(Re)*air.Pr^(1/3);
                    correlation = "Average laminar external flat-plate correlation";
                else
                    Nu = (0.037*Re^0.8-871)*air.Pr^(1/3);
                    if Nu <= 0
                        error("ThermalPack:ForcedAirFlatPlateRange", ...
                            "External flat-plate turbulent correlation returned non-positive Nu.");
                    end
                    correlation = "Average turbulent external flat-plate correlation";
                end
                h = Nu*air.k_W_mK/Lflow_m;
            end
        end

        Rambient = 1/(h*Aeff);
        calc = struct("rho_kg_m3",air.rho_kg_m3,"mu_Pa_s",air.mu_Pa_s, ...
            "k_W_mK",air.k_W_mK,"cp_J_kgK",air.cp_J_kgK,"Pr",air.Pr, ...
            "Re",Re,"Nu",Nu,"h_W_m2K",h,"Aeff_m2",Aeff, ...
            "Rambient_K_W",Rambient,"FlowAxis",geo.FlowAxis, ...
            "Arrangement",geo.Arrangement,"Correlation",correlation, ...
            "GeometrySource",geo.GeometrySource,"Veffective_m_s",Veff, ...
            "Lc_m",Lc_m,"Dh_m",Dh_m,"NuLength_m",nuLength_m, ...
            "ST_m",geo.ST_m,"SL_m",geo.SL_m, ...
            "Columns",geo.Columns,"Rows",geo.Rows,"Epsilon",epsilon, ...
            "WallClearance_mm",wallClearance_mm, ...
            "ArrayTransverseWidth_m",arrayTransverseWidth_m, ...
            "DuctWidth_m",ductWidth_m,"DuctHeight_m",ductHeight_m, ...
            "FlowArea_m2",flowArea_m2, ...
            "VolumetricFlow_m3_s",volumetricFlow_m3_s, ...
            "MassFlow_kg_s",massFlow_kg_s, ...
            "SegmentLength_m",segmentLength_m, ...
            "RepresentativeGasVolume_m3",representativeGasVolume_m3, ...
            "CylindricalRegime",cylRegime, ...
            "CylindricalReLengthSelected",cylReLengthSelected, ...
            "CylindricalSelectionSource",cylSelectionSource, ...
            "CylindricalPitchRatioT",cylPitchRatioT, ...
            "CylindricalPitchRatioL",cylPitchRatioL, ...
            "CylindricalWallRatioLeft",cylWallRatioLeft, ...
            "CylindricalWallRatioRight",cylWallRatioRight, ...
            "CylindricalPassageGap_m",cylPassageGap_m, ...
            "CylindricalCandidateDh_m",cylCandidateDh_m, ...
            "CylindricalDhEligible",logical(cylDhEligible), ...
            "CylindricalIsCompact",logical(cylIsCompact), ...
            "CylindricalIsTransitional",logical(cylIsTransitional), ...
            "CylindricalIsWallBounded",logical(cylIsWallBounded), ...
            "CylindricalIsRepeated",logical(cylIsRepeated), ...
            "DhCorrelationValidationRequired",dhCorrelationValidationRequired, ...
            "DhCorrelationValidationStatus",dhCorrelationValidationStatus, ...
            "DhCorrelationValidationApplied",dhCorrelationValidationApplied);
    end

    function updateForcedAirStateFromCalculation(calc)
        state.ForcedAirDensity_kg_m3 = calc.rho_kg_m3;
        state.ForcedAirDynamicViscosity_Pa_s = calc.mu_Pa_s;
        state.ForcedAirConductivity_W_mK = calc.k_W_mK;
        state.ForcedAirSpecificHeat_J_kgK = calc.cp_J_kgK;
        state.ForcedAirPrandtl = calc.Pr;
        state.ForcedAirReynolds = calc.Re;
        state.ForcedAirNusselt = calc.Nu;
        state.ForcedAirH_W_m2K = calc.h_W_m2K;
        state.ForcedAirAreaPerCell_m2 = calc.Aeff_m2;
        state.ForcedAirAmbientRth_K_W = calc.Rambient_K_W;
        state.ForcedAirArrangement = calc.Arrangement;
        state.ForcedAirCorrelation = calc.Correlation;
        state.ForcedAirGeometrySource = calc.GeometrySource;
        state.ForcedAirEffectiveVelocity_m_s = calc.Veffective_m_s;
        state.ForcedAirCharacteristicLength_m = calc.Lc_m;
        state.ForcedAirHydraulicDiameter_m = calc.Dh_m;
        state.ForcedAirNusseltLength_m = calc.NuLength_m;
        state.ForcedAirTransversePitch_m = calc.ST_m;
        state.ForcedAirLongitudinalPitch_m = calc.SL_m;
        state.ForcedAirColumns = calc.Columns;
        state.ForcedAirRows = calc.Rows;
        state.ForcedAirWallClearance_mm = calc.WallClearance_mm;
        state.ForcedAirArrayTransverseWidth_m = calc.ArrayTransverseWidth_m;
        state.ForcedAirDuctWidth_m = calc.DuctWidth_m;
        state.ForcedAirDuctHeight_m = calc.DuctHeight_m;
        state.ForcedAirFlowArea_m2 = calc.FlowArea_m2;
        state.ForcedAirVolumetricFlow_m3_s = calc.VolumetricFlow_m3_s;
        state.ForcedAirMassFlow_kg_s = calc.MassFlow_kg_s;
        state.ForcedAirRepresentativeSegmentLength_m = calc.SegmentLength_m;
        state.ForcedAirRepresentativeGasVolume_m3 = calc.RepresentativeGasVolume_m3;
        state.ForcedAirCylindricalRegime = calc.CylindricalRegime;
        state.ForcedAirCylindricalReLengthSelected = calc.CylindricalReLengthSelected;
        state.ForcedAirCylindricalSelectionSource = calc.CylindricalSelectionSource;
        state.ForcedAirCylindricalPitchRatioT = calc.CylindricalPitchRatioT;
        state.ForcedAirCylindricalPitchRatioL = calc.CylindricalPitchRatioL;
        state.ForcedAirCylindricalWallRatioLeft = calc.CylindricalWallRatioLeft;
        state.ForcedAirCylindricalWallRatioRight = calc.CylindricalWallRatioRight;
        state.ForcedAirCylindricalPassageGap_m = calc.CylindricalPassageGap_m;
        state.ForcedAirCylindricalCandidateDh_m = calc.CylindricalCandidateDh_m;
        state.ForcedAirCylindricalDhEligible = calc.CylindricalDhEligible;
        state.ForcedAirCylindricalIsCompact = calc.CylindricalIsCompact;
        state.ForcedAirCylindricalIsTransitional = calc.CylindricalIsTransitional;
        state.ForcedAirCylindricalIsWallBounded = calc.CylindricalIsWallBounded;
        state.ForcedAirCylindricalIsRepeated = calc.CylindricalIsRepeated;
    end

    function openForcedAirSettings(~,~)
        % The window remains available while a rebuild is pending so the user
        % can choose Uniform/Progressive and airflow axis before
        % generating the battery. X/Y uses the fixed positive-axis direction.
        % Preview uses configured geometry until the
        % next REBUILD supplies Battery Builder coordinates.

        parentPos = fig.Position;
        faWidth = 760;
        faHeight = 940;
        faX = parentPos(1) + 0.5*(parentPos(3)-faWidth);
        faY = parentPos(2) + 0.5*(parentPos(4)-faHeight);

        faFig = uifigure("Name","ThermalPack — Forced Air Settings", ...
            "Position",[faX faY faWidth faHeight],"Resize","off");
        faFig.UserData = struct("ThermalPackOwner",fig);

        fg = uigridlayout(faFig,[25 2]);
        fg.ColumnWidth = {365,'1x'};
        fg.RowHeight = {46,36,36,36,36,36,36,26,34,34,34,34,34,26,34,34,34,26,34,34,34,34,34,34,44};
        fg.Padding = [18 14 18 14];
        fg.RowSpacing = 5;
        fg.ColumnSpacing = 12;
        fg.Scrollable = "on";

        hdr = uilabel(fg,"Text","FORCED AIR — GEOMETRY-AWARE", ...
            "FontSize",17,"FontWeight","bold");
        hdr.Layout.Row = 1; hdr.Layout.Column = [1 2];

        addFALabel(2,"Forced-air model");
        modelField = uidropdown(fg, ...
            "Items",["Uniform AmbH","Progressive Gas"], ...
            "Value",state.ForcedAirModel, ...
            "ValueChangedFcn",@forcedAirModelChanged, ...
            "Tooltip","Uniform AmbH uses one bulk-air temperature. Progressive Gas partitions the rebuilt battery and creates one serial Simscape Gas chamber per detected flowwise column.");
        modelField.Layout.Row = 2; modelField.Layout.Column = 2;

        addFALabel(3,"Airflow axis");
        axisField = uidropdown(fg,"Items",["X","Y"],"Value",state.ForcedAirAxis, ...
            "ValueChangedFcn",@refreshForcedAirPreview, ...
            "Tooltip","X/Y selects the streamwise direction used to detect columns, pitches, gaps and the Re/Nu correlation.");
        axisField.Layout.Row = 3; axisField.Layout.Column = 2;

        addFALabel(4,"Approach air velocity (m/s)");
        velocityField = uieditfield(fg,"numeric","Value",state.ForcedAirVelocity_m_s, ...
            "Limits",[1e-9 Inf],"ValueChangedFcn",@refreshForcedAirPreview, ...
            "Tooltip","Bulk inlet velocity at the gross duct cross-section. Local gap velocity is calculated separately for Re/Nu/h.");
        velocityField.Layout.Row = 4; velocityField.Layout.Column = 2;

        addFALabel(5,"Air inlet temperature (°C)");
        airTempField = uieditfield(fg,"numeric","Value",state.ForcedAirTemperature_C, ...
            "Limits",[-98 526],"ValueChangedFcn",@refreshForcedAirPreview);
        airTempField.Layout.Row = 5; airTempField.Layout.Column = 2;

        addFALabel(6,"Absolute air pressure (kPa)");
        pressureField = uieditfield(fg,"numeric","Value",state.ForcedAirPressure_Pa/1000, ...
            "Limits",[10 200],"ValueChangedFcn",@refreshForcedAirPreview, ...
            "Tooltip","Absolute pressure. Density uses rho = p/(R*T).");
        pressureField.Layout.Row = 6; pressureField.Layout.Column = 2;

        addFALabel(7,"Cell-to-Duct Wall Gap (mm, Each Side)");
        wallClearanceField = uieditfield(fg,"numeric", ...
            "Value",state.ForcedAirWallClearance_mm,"Limits",[0 Inf], ...
            "ValueChangedFcn",@refreshForcedAirPreview, ...
            "Tooltip","Gap from the outermost cell surface to each transverse duct wall. It sets gross duct width, flow area and mass flow; local tube-bank/channel velocity remains correlation based.");
        wallClearanceField.Layout.Row = 7; wallClearanceField.Layout.Column = 2;

        propHdr = uilabel(fg,"Text","AUTOMATIC DRY-AIR PROPERTIES — READ ONLY","FontWeight","bold");
        propHdr.Layout.Row = 8; propHdr.Layout.Column = [1 2];
        addFALabel(9,"Density ρ (kg/m³)"); densityField = uieditfield(fg,"numeric","Editable","off"); densityField.Layout.Row=9; densityField.Layout.Column=2;
        addFALabel(10,"Dynamic viscosity μ (Pa·s)"); viscosityField = uieditfield(fg,"numeric","Editable","off"); viscosityField.Layout.Row=10; viscosityField.Layout.Column=2;
        addFALabel(11,"Thermal conductivity k (W/m·K)"); airKField = uieditfield(fg,"numeric","Editable","off"); airKField.Layout.Row=11; airKField.Layout.Column=2;
        addFALabel(12,"Specific heat cp (J/kg·K)"); cpField = uieditfield(fg,"numeric","Editable","off"); cpField.Layout.Row=12; cpField.Layout.Column=2;
        addFALabel(13,"Prandtl number Pr"); prField = uieditfield(fg,"numeric","Editable","off"); prField.Layout.Row=13; prField.Layout.Column=2;

        geoHdr = uilabel(fg,"Text","DETECTED FLOW GEOMETRY — READ ONLY","FontWeight","bold");
        geoHdr.Layout.Row = 14; geoHdr.Layout.Column = [1 2];
        addFALabel(15,"Arrangement"); arrangementField = uieditfield(fg,"text","Editable","off"); arrangementField.Layout.Row=15; arrangementField.Layout.Column=2;
        addFALabel(16,"Selected correlation"); correlationField = uieditfield(fg,"text","Editable","off"); correlationField.Layout.Row=16; correlationField.Layout.Column=2;
        addFALabel(17,"ST / SL / flow columns"); geometryField = uieditfield(fg,"text","Editable","off"); geometryField.Layout.Row=17; geometryField.Layout.Column=2;

        calcHdr = uilabel(fg,"Text","CONVECTION + AIRFLOW CALCULATION — READ ONLY","FontWeight","bold");
        calcHdr.Layout.Row = 18; calcHdr.Layout.Column = [1 2];
        addFALabel(19,"Local velocity / Re / Nu"); reNuField = uieditfield(fg,"text","Editable","off"); reNuField.Layout.Row=19; reNuField.Layout.Column=2;
        addFALabel(20,"h (W/m²·K)"); hField = uieditfield(fg,"numeric","Editable","off"); hField.Layout.Row=20; hField.Layout.Column=2;
        addFALabel(21,"A / cell (m²) | Rambient / cell (K/W)"); areaRField = uieditfield(fg,"text","Editable","off"); areaRField.Layout.Row=21; areaRField.Layout.Column=2;
        addFALabel(22,"Array width / duct width (m)"); ductWidthField = uieditfield(fg,"text","Editable","off"); ductWidthField.Layout.Row=22; ductWidthField.Layout.Column=2;
        addFALabel(23,"Gross inlet area / volumetric flow"); flowAreaField = uieditfield(fg,"text","Editable","off"); flowAreaField.Layout.Row=23; flowAreaField.Layout.Column=2;
        addFALabel(24,"Air mass flow / representative gas volume"); massFlowField = uieditfield(fg,"text","Editable","off"); massFlowField.Layout.Row=24; massFlowField.Layout.Column=2;

        btnGrid = uigridlayout(fg,[1 3]);
        btnGrid.Layout.Row = 25; btnGrid.Layout.Column = [1 2];
        btnGrid.ColumnWidth = {'1x','1x','1x'}; btnGrid.Padding = [0 0 0 0];
        resetBtn = uibutton(btnGrid,"push","Text","RESET OPERATING INPUTS","ButtonPushedFcn",@resetAirDefaults); resetBtn.Layout.Column=1;
        applyBtn = uibutton(btnGrid,"push","Text","APPLY","FontWeight","bold","ButtonPushedFcn",@applyForcedAirSettings); applyBtn.Layout.Column=2;
        closeBtn = uibutton(btnGrid,"push","Text","CLOSE","ButtonPushedFcn",@(srcBtn,~)delete(ancestor(srcBtn,"figure"))); closeBtn.Layout.Column=3;

        forcedAirModelChanged();
        refreshForcedAirPreview();

        function addFALabel(rowNum,labelText)
            lbl = uilabel(fg,"Text",labelText);
            lbl.Layout.Row = rowNum; lbl.Layout.Column = 1;
        end

        function forcedAirModelChanged(varargin)
            if string(modelField.Value) == "Progressive Gas"
                hdr.Text = "FORCED AIR — PROGRESSIVE SIMSCAPE GAS";
            else
                hdr.Text = "FORCED AIR — UNIFORM AmbH";
            end
            refreshForcedAirPreview();
        end

        function calc = previewCalculation()
            calc = forcedAirGeneralCalculation(velocityField.Value, ...
                airTempField.Value,pressureField.Value*1000,axisField.Value, ...
                wallClearanceField.Value);
        end

        function refreshForcedAirPreview(varargin)
            try
                calc = previewCalculation();
                densityField.Value = calc.rho_kg_m3;
                viscosityField.Value = calc.mu_Pa_s;
                airKField.Value = calc.k_W_mK;
                cpField.Value = calc.cp_J_kgK;
                prField.Value = calc.Pr;
                if string(calc.CylindricalRegime) ~= "Not applicable"
                    arrangementField.Value = calc.Arrangement + " | " + calc.CylindricalRegime;
                else
                    arrangementField.Value = calc.Arrangement;
                end
                correlationField.Value = calc.Correlation;
                stText = "—"; slText = "—";
                if isfinite(calc.ST_m), stText = thermalPackFormatText("%.3f mm",1000*calc.ST_m); end
                if isfinite(calc.SL_m), slText = thermalPackFormatText("%.3f mm",1000*calc.SL_m); end
                geometryField.Value = thermalPackFormatText("ST %s | SL %s | %d columns | %s", ...
                    stText,slText,round(calc.Columns),calc.GeometrySource);
                if string(calc.CylindricalReLengthSelected) ~= "Not applicable"
                    reNuField.Value = thermalPackFormatText( ...
                        "Veff %.3f m/s | Re %.3f | Nu %.3f | Re basis %s", ...
                        calc.Veffective_m_s,calc.Re,calc.Nu, ...
                        calc.CylindricalReLengthSelected);
                else
                    reNuField.Value = thermalPackFormatText("Veff %.3f m/s | Re %.3f | Nu %.3f", ...
                        calc.Veffective_m_s,calc.Re,calc.Nu);
                end
                hField.Value = calc.h_W_m2K;
                areaRField.Value = thermalPackFormatText("%.8g   |   %.8g",calc.Aeff_m2,calc.Rambient_K_W);
                ductWidthField.Value = thermalPackFormatText("%.6g   |   %.6g", ...
                    calc.ArrayTransverseWidth_m,calc.DuctWidth_m);
                flowAreaField.Value = thermalPackFormatText("%.8g m²   |   %.8g m³/s", ...
                    calc.FlowArea_m2,calc.VolumetricFlow_m3_s);
                massFlowField.Value = thermalPackFormatText("%.8g kg/s   |   %.8g m³", ...
                    calc.MassFlow_kg_s,calc.RepresentativeGasVolume_m3);
            catch MEpreview
                densityField.Value = 0; viscosityField.Value = 0; airKField.Value = 0;
                cpField.Value = 0; prField.Value = 0; hField.Value = 0;
                arrangementField.Value = "Unsupported / unresolved geometry";
                correlationField.Value = string(MEpreview.message);
                geometryField.Value = "Check airflow axis and rebuilt geometry";
                reNuField.Value = "—";
                areaRField.Value = "—";
                ductWidthField.Value = "—";
                flowAreaField.Value = "—";
                massFlowField.Value = "—";
            end
        end

        function resetAirDefaults(~,~)
            modelField.Value = "Progressive Gas";
            axisField.Value = "X";
            velocityField.Value = 2.0;
            airTempField.Value = 25.0;
            pressureField.Value = 101.325;
            wallClearanceField.Value = 4.0;
            forcedAirModelChanged();
            refreshForcedAirPreview();
        end

        function applyForcedAirSettings(~,~)
            try
                calc = previewCalculation();
            catch MEapply
                uialert(faFig,string(MEapply.message),"Forced Air Geometry");
                return;
            end

            newModel = string(modelField.Value);
            newAxis = string(axisField.Value);

            structureChanged = newModel ~= state.ForcedAirModel;
            if newModel == "Progressive Gas" || state.ForcedAirModel == "Progressive Gas"
                structureChanged = structureChanged || ...
                    newAxis ~= state.ForcedAirAxis;
            end

            state.ForcedAirModel = newModel;
            state.ForcedAirAxis = newAxis;
            state.ForcedAirVelocity_m_s = velocityField.Value;
            state.ForcedAirTemperature_C = airTempField.Value;
            state.ForcedAirPressure_Pa = pressureField.Value*1000;
            state.ForcedAirWallClearance_mm = wallClearanceField.Value;
            updateForcedAirStateFromCalculation(calc);
            ambientField.Value = state.ForcedAirTemperature_C;
            ambientRField.Value = state.ForcedAirAmbientRth_K_W;

            if structureChanged && string(coolingPlateField.Value) == "Forced Air Cooling"
                state.NeedsRebuild = true;
                statusLabel.Text = ...
                    "Forced-air model/direction changed — click REBUILD BATTERY";
                return;
            end

            if state.NeedsRebuild && string(coolingPlateField.Value) == "Forced Air Cooling"
                statusLabel.Text = ...
                    "Forced-air settings saved — click REBUILD BATTERY";
                return;
            end

            try
                if state.ForcedAirModel == "Progressive Gas" && ...
                        state.ProgressiveForcedAirBuilt
                    updateProgressiveForcedAirOperatingPoint(calc);
                    applyProgressiveAmbientResistanceToBlocks();
                elseif getSimulinkBlockHandle(batteryBlock) > 0
                    safeSetBlockParam(batteryBlock,"AmbientResistance", ...
                        num2str(state.ForcedAirAmbientRth_K_W,16));
                end
                save_system(mdl);
            catch MEupdateFA
                uialert(faFig,string(MEupdateFA.message), ...
                    "ThermalPack — Forced Air Update");
                return;
            end

            statusLabel.Text = thermalPackFormatText( ...
                "Forced air %s / %s — %s | h %.3f W/(m²·K) | mdot %.4g kg/s", ...
                state.ForcedAirModel,state.ForcedAirAxis,state.ForcedAirArrangement, ...
                state.ForcedAirH_W_m2K,state.ForcedAirMassFlow_kg_s);
        end
    end

    function clearProgressiveForcedAirState()
        state.ProgressiveForcedAirBuilt = false;
        state.ProgressiveForcedAirSubsystem = "";
        state.ProgressiveForcedAirSegmentBlocks = strings(0,1);
        state.ProgressiveForcedAirSegmentNames = strings(0,1);
        state.ProgressiveForcedAirSegmentCellIDs = cell(0,1);
        state.ProgressiveForcedAirSegmentSeriesGroup = zeros(0,1);
        state.ProgressiveForcedAirSegmentPhysicalGroup = zeros(0,1);
        state.ProgressiveForcedAirSegmentAirOrder = zeros(0,1);
        state.ProgressiveForcedAirChamberBlocks = strings(0,1);
        state.ProgressiveForcedAirChamberPhysicalGroups = zeros(0,1);
        state.ProgressiveForcedAirSegmentLengths_m = zeros(0,1);
        state.ProgressiveForcedAirGasVolumes_m3 = zeros(0,1);
        state.ProgressiveForcedAirFlowSourceBlock = "";
        state.ProgressiveForcedAirMassFlowCommandBlock = "";
        state.ProgressiveForcedAirInletReservoirBlock = "";
        state.ProgressiveForcedAirOutletReservoirBlock = "";
        state.ProgressiveForcedAirGasPropertiesBlock = "";
        state.ProgressiveForcedAirGeneratedLibraries = strings(0,1);
    end

    function restoreStandardWorkingModelBeforeRebuild()
        % Progressive Gas replaces the normal battery block by a generated
        % subsystem. Any later structural REBUILD starts again from the clean
        % V5 master so Uniform AmbH, liquid cooling and a new progressive
        % partition always have the same deterministic starting topology.
        if ~state.ProgressiveForcedAirBuilt
            return;
        end

        statusLabel.Text = "Restoring standard V5 working model before rebuild...";
        drawnow;

        if bdIsLoaded(mdl)
            close_system(mdl,0);
        end

        loadedBaseHere = false;
        if ~bdIsLoaded(baseMdl)
            load_system(baseFile);
            loadedBaseHere = true;
        end

        if isfile(workingFile)
            delete(workingFile);
        end
        save_system(baseMdl,workingFile);

        if loadedBaseHere
            close_system(baseMdl,0);
        end
        load_system(workingFile);
        set_param(mdl,"SolverType","Variable-step","Solver","ode23t");
        clearProgressiveForcedAirState();

        % A restored V5 working copy must also be immediately compilable.
        % Re-seed its model-workspace operating variables because a fresh
        % copy may not yet have received SimulationInput overrides.
        initializeWorkingModelDefaults();
    end

    function removeUnusedLiquidCoolingBranchesForProgressiveGas()
        % Progressive Gas owns the complete active thermal boundary. Once the
        % standard Battery Builder block has been replaced, the permanent
        % Top/Bottom/Xmin/Xmax/Ymin/Ymax liquid circuits no longer have a
        % conserving connection to the active battery. Leaving them in the
        % working model creates orphan Simscape physical networks that require
        % their own Solver Configuration blocks even though they are inactive.
        %
        % Delete ONLY from Thermal_Model_v5_UI. Thermal_Model_v5 is never
        % modified, and restoreStandardWorkingModelBeforeRebuild() recreates a
        % clean working copy before any later liquid/side/serpentine rebuild.
        if string(state.CoolingPlateMode) ~= "Forced Air Cooling" || ...
                string(state.ForcedAirModel) ~= "Progressive Gas"
            return;
        end

        liquidSubsystems = [ ...
            bottomCoolingSubsystem, ...
            topCoolingSubsystem, ...
            sideCoolingSubsystems];

        for kLiquid = 1:numel(liquidSubsystems)
            thisSubsystem = liquidSubsystems(kLiquid);
            if getSimulinkBlockHandle(thisSubsystem) > 0
                delete_block(thisSubsystem);
            end
        end

        % Serpentine is a programmatic top-level liquid branch rather than a
        % dedicated subsystem, so remove its six working-model blocks too if
        % they happen to exist. delete_block also removes attached lines.
        removeSerpentineCoolingBranch();

        % Fail immediately if any permanent liquid-cooling subsystem survived
        % the conversion. This keeps Progressive Gas as one deterministic
        % active Simscape network rather than silently compiling orphan loops.
        remainingLiquid = strings(0,1);
        for kLiquid = 1:numel(liquidSubsystems)
            if getSimulinkBlockHandle(liquidSubsystems(kLiquid)) > 0
                remainingLiquid(end+1,1) = liquidSubsystems(kLiquid); %#ok<AGROW>
            end
        end
        if ~isempty(remainingLiquid)
            error("ThermalPack:ProgressiveLiquidBranchRemoval", ...
                "Could not remove unused liquid-cooling working-model branches: %s", ...
                strjoin(remainingLiquid,", "));
        end

        % The standard V5 ambient source/sensor were connected to the original
        % battery AmbH network. Progressive Gas gives every generated battery
        % segment its AmbH connection directly to an Air_Chamber H port, so the
        % old ambient source and sensor become a separate orphan thermal network
        % with no Solver Configuration. They are therefore removed from the
        % non-destructive working model only. The V5 master remains untouched.
        progressiveUnusedAmbientBlocks = [ ...
            mdl + "/Ambient Temperature", ...
            mdl + "/Ambient Temperature Sensor"];
        for kAmbient = 1:numel(progressiveUnusedAmbientBlocks)
            thisAmbientBlock = progressiveUnusedAmbientBlocks(kAmbient);
            if getSimulinkBlockHandle(thisAmbientBlock) > 0
                delete_block(thisAmbientBlock);
            end
        end

        remainingAmbient = strings(0,1);
        for kAmbient = 1:numel(progressiveUnusedAmbientBlocks)
            if getSimulinkBlockHandle(progressiveUnusedAmbientBlocks(kAmbient)) > 0
                remainingAmbient(end+1,1) = progressiveUnusedAmbientBlocks(kAmbient); %#ok<AGROW>
            end
        end
        if ~isempty(remainingAmbient)
            error("ThermalPack:ProgressiveAmbientBranchRemoval", ...
                "Could not remove unused normal-ambient working-model blocks: %s", ...
                strjoin(remainingAmbient,", "));
        end

        state.SideBranchCreated = false;
        state.HasSidePort = false;
        state.BuiltSideBoundary = "";
    end

    function initializeWorkingModelDefaults()
        % Provide physically meaningful model-workspace defaults for every
        % operating variable referenced by the V5 working model. These values
        % exist to make manual update/compile robust before SimulationInput is
        % constructed. They are NOT a substitute for the selected operating
        % point: runSimulation overwrites them with the case-specific values.
        if ~bdIsLoaded(mdl)
            return;
        end

        try
            mdlWks = get_param(mdl,"ModelWorkspace");
        catch
            return;
        end

        % Zero is physically valid for inactive rate/command variables.
        coolingNames = ["bottom","top","serpentine",sideBoundaryNames];
        for kDefault = 1:numel(coolingNames)
            suffix = coolingNames(kDefault);
            assignin(mdlWks,char("mdot_coolant_" + suffix),0);
            assignin(mdlWks,char("qdot_coolant_" + suffix),0);
        end
        % Legacy generic names may temporarily exist in block masks before the
        % app replaces them with branch-specific variable names.
        assignin(mdlWks,"mdot_coolant",0);
        assignin(mdlWks,"qdot_coolant",0);

        % Temperatures, areas, pressure and SOC must remain physically valid;
        % do not use zero merely as a placeholder for these quantities.
        coolantTin_C = 25.0;
        ambient_C = 25.0;
        initialSOC = 0.50;
        try
            if isvalid(tinField), coolantTin_C = tinField.Value; end
        catch
        end
        try
            if isvalid(ambientField), ambient_C = ambientField.Value; end
        catch
        end
        try
            if isvalid(socField), initialSOC = socField.Value; end
        catch
        end

        coolantTin_K = coolantTin_C + 273.15;
        nominalArea_m2 = state.CoolantPortArea_m2;
        if ~(isfinite(nominalArea_m2) && nominalArea_m2 > 0)
            nominalArea_m2 = pi*(10e-3)^2/4;
        end

        for kDefault = 1:numel(coolingNames)
            suffix = coolingNames(kDefault);
            assignin(mdlWks,char("T_coolant_" + suffix + "_in_K"),coolantTin_K);
            assignin(mdlWks,char("Area_coolant_" + suffix + "_port_in_m2"),nominalArea_m2);
        end

        plateT_K = state.InitialPlateTemperature_C + 273.15;
        if ~(isfinite(plateT_K) && plateT_K > 0)
            plateT_K = 298.15;
        end
        ambientT_K = ambient_C + 273.15;
        if ~(isfinite(ambientT_K) && ambientT_K > 0)
            ambientT_K = 298.15;
        end
        pressure_Pa = state.AtmosphericPressure_Pa;
        if ~(isfinite(pressure_Pa) && pressure_Pa > 0)
            pressure_Pa = 101325;
        end
        initialSOC = min(1,max(0,initialSOC));

        assignin(mdlWks,"T_plate_K",plateT_K);
        assignin(mdlWks,"T_ambient_K",ambientT_K);
        assignin(mdlWks,"Atmospheric_pressure_in_Pa",pressure_Pa);
        assignin(mdlWks,"SOC0",initialSOC);

        % Use a valid current profile rather than leaving the From Workspace
        % source unresolved. Preserve the user's current custom profile when
        % available; otherwise fall back to the app's normal default profile.
        profile = CurrentProfileDefault;
        try
            candidateProfile = state.CustomCurrentProfile;
            if isnumeric(candidateProfile) && size(candidateProfile,2) == 2 && ...
                    size(candidateProfile,1) >= 2 && all(isfinite(candidateProfile),"all")
                profile = candidateProfile;
            end
        catch
        end
        assignin(mdlWks,"CurrentProfile",double(profile));
    end

    function parameterizeProgressiveSegmentBlock(blockPath,cellIDs)
        cellIDs = double(cellIDs(:));
        nSegCells = numel(cellIDs);
        if nSegCells < 1
            error("ThermalPack:ProgressiveSegmentEmpty", ...
                "A progressive forced-air battery segment cannot be empty.");
        end

        applyMasterBatteryParameters(blockPath,masterBatteryParams,nSegCells,1);

        if string(state.CellFormat) ~= "Cylindrical"
            resetCellParameterDeviations(blockPath,nSegCells);
        end

        safeSetBlockParam(blockPath,"BatteryCapacityCell", ...
            num2str(capacityField.Value,16));
        safeSetBlockParam(blockPath,"NumThermalModelsCell", ...
            num2str(round(nodesField.Value)));
        safeSetBlockParam(blockPath,"BatteryThermalMassCell", ...
            num2str(thermalMassField.Value,16));
        safeSetBlockParam(blockPath,"ThermalConductivityZCell", ...
            num2str(conductivityField.Value,16));
        safeSetBlockParam(blockPath,"CrossSectionalAreaXYCell", ...
            num2str(thermalAreaField.Value,16));
        safeSetBlockParam(blockPath,"HeightCell", ...
            num2str(heightField.Value/1000,16));

        fullR0Dev = resizeNumericVector( ...
            state.R0Deviation_pct,state.TotalCells,0);
        fullTMDev = resizeNumericVector( ...
            state.ThermalMassDeviation_pct,state.TotalCells,0);
        fullKDev = resizeNumericVector( ...
            state.ThermalConductivityDeviation_pct,state.TotalCells,0);

        segmentState = state;
        segmentState.R0Deviation_pct = fullR0Dev(cellIDs);
        segmentState.ThermalMassDeviation_pct = fullTMDev(cellIDs);
        segmentState.ThermalConductivityDeviation_pct = fullKDev(cellIDs);
        applyCellElectricalDataToBlock(blockPath,segmentState,nSegCells);

        % Battery Builder initializes from socCell, not the compatibility
        % SOC0 workspace variable alone.  Override the inherited V5 state
        % after master-parameter restoration for every 4P x 1S segment.
        applyInitialSOCToBlock(blockPath,socField.Value,nSegCells,1);

        safeSetBlockParam(blockPath,"batteryTemperature", ...
            thermalPackFormatText("repmat(%.16g,%d,1)", ...
            initialCellTempField.Value + 273.15,nSegCells));
        safeSetBlockParam(blockPath,"AmbientResistance", ...
            num2str(state.ForcedAirAmbientRth_K_W,16));

        if state.InterCellHeatTransfer == "Enabled"
            safeSetBlockParam(blockPath,"InterCellThermalResistance", ...
                num2str(interCellRField.Value,16));
        end
    end

    function opts = configureElectricalDynamicsCellModelOptions(opts)
        % RCPairs and ReversibleHeatModel are conditional Battery Equivalent
        % Circuit options and must be selected before buildBattery.
        % CurrentDependence is intentionally left at the installed/default
        % Battery Builder behavior in the generalized architecture.

        model = string(state.PolarizationModel);
        if model == "RC1"
            try
                opts.BlockParameters.RCPairs = "rc1";
            catch
                try
                    opts.BlockParameters.RCPairs = "OneTimeConstantDynamics";
                catch
                    opts.BlockParameters.RCPairs = ...
                        "simscape.battery.enum.cells.RCPairs.rc1";
                end
            end
        elseif any(model == ["RC1 + RC2","RC2"])
            try
                opts.BlockParameters.RCPairs = "rc2";
            catch
                try
                    opts.BlockParameters.RCPairs = "TwoTimeConstantDynamics";
                catch
                    opts.BlockParameters.RCPairs = ...
                        "simscape.battery.enum.cells.RCPairs.rc2";
                end
            end
        end

        if logical(state.EntropicHeatEnabled)
            try
                opts.BlockParameters.ReversibleHeatModel = "EntropicCoefficient";
            catch
                opts.BlockParameters.ReversibleHeatModel = ...
                    "simscape.battery.enum.cells.ReversibleHeatModel.EntropicCoefficient";
            end
        end
    end

    function [counts,sources,libraries] = buildProgressiveSegmentSources( ...
            uniqueCounts,generatedDir,stamp)
        counts = double(uniqueCounts(:));
        sources = strings(numel(counts),1);
        libraries = strings(numel(counts),1);

        fmt = string(state.CellFormat);
        height_m = heightField.Value/1000;
        cellGap_m = cellGapField.Value/1000;

        for iCount = 1:numel(counts)
            pCount = round(counts(iCount));
            if pCount < 1
                error("ThermalPack:ProgressiveSegmentCount", ...
                    "Progressive segment cell count must be at least one.");
            end

            opts = batteryCellModelBlock( ...
                "batt_lib/Cells/Battery Equivalent Circuit");
            try
                opts.BlockParameters.ThermalModel = "HeightDistributedMass";
            catch
                opts.BlockParameters.ThermalModel = ...
                    "simscape.battery.enum.cells.BatteryThermalModel.HeightDistributedMass";
            end
            opts = configureElectricalDynamicsCellModelOptions(opts);

            if fmt == "Cylindrical"
                segGeometry = batteryCylindricalGeometry( ...
                    simscape.Value(height_m,"m"), ...
                    simscape.Value(diameterField.Value/2000,"m"));
                cellName = "Cylindrical_Cell";
                assemblyName = "Cylindrical_Cell_Assembly";
                tag = "Cyl";
            elseif fmt == "Prismatic"
                segGeometry = batteryPrismaticGeometry( ...
                    simscape.Value(height_m,"m"), ...
                    simscape.Value(diameterField.Value/1000,"m"), ...
                    simscape.Value(thicknessField.Value/1000,"m"));
                cellName = "Prismatic_Cell";
                assemblyName = "Prismatic_Cell_Assembly";
                tag = "Prismatic";
            else
                segGeometry = batteryPouchGeometry( ...
                    simscape.Value(height_m,"m"), ...
                    simscape.Value(diameterField.Value/1000,"m"), ...
                    simscape.Value(thicknessField.Value/1000,"m"), ...
                    TabLocation=string(tabLocationField.Value), ...
                    TabWidth=simscape.Value(tabWidthField.Value/1000,"m"), ...
                    TabHeight=simscape.Value(tabHeightField.Value/1000,"m"));
                cellName = "Pouch_Cell";
                assemblyName = "Pouch_Cell_Assembly";
                tag = "Pouch";
            end

            segCell = batteryCell(segGeometry,opts);
            segCell.Name = cellName;
            segCell.Capacity = simscape.Value(capacityField.Value,"A*hr");
            try
                segCell.Mass = simscape.Value(massField.Value,"kg");
            catch
            end
            try
                segCell.Energy = simscape.Value(energyField.Value,"W*hr");
            catch
            end
            segCell.StackingAxis = state.ParallelAssemblyStackingAxis;

            segAssembly = batteryParallelAssembly(segCell,pCount);
            segAssembly.Name = assemblyName;
            if fmt == "Cylindrical"
                segAssembly.Topology = "Square";
            else
                segAssembly.Topology = "SingleStack";
            end
            segAssembly.Rows = 1;
            segAssembly.StackingAxis = state.ParallelAssemblyStackingAxis;
            segAssembly.InterCellGap = simscape.Value(cellGap_m,"m");
            segAssembly.ModelResolution = "Detailed";
            if state.InterCellHeatTransfer == "Enabled"
                segAssembly.InterCellThermalPath = "on";
            else
                segAssembly.InterCellThermalPath = "off";
            end

            segModule = batteryModule(segAssembly,1);
            segModule.Name = "FA_Segment_Module_" + pCount + "P";
            segModule.StackingAxis = state.ModuleStackingAxis;
            segModule.ModelResolution = "Detailed";
            segModule.MassFactor = state.MassFactor;
            segModule.AmbientThermalPath = "CellBasedThermalResistance";
            if state.InterCellHeatTransfer == "Enabled"
                segModule.InterCellThermalPath = "on";
            else
                segModule.InterCellThermalPath = "off";
            end
            segModule.CellParameterVariation = "PercentDeviation";

            libName = "ThermalPack_FA_" + tag + "_" + pCount + ...
                "P1S_" + stamp;
            buildBattery(segModule, ...
                LibraryName=libName, ...
                Directory=generatedDir, ...
                MaskParameters="NumericValues", ...
                Verbose="on");

            libModel = libName + "_lib";
            load_system(libModel);
            source = libModel + "/" + segModule.Name;
            if getSimulinkBlockHandle(source) <= 0
                topBlocks = string(find_system(libModel, ...
                    "SearchDepth",1,"Type","Block"));
                candidate = topBlocks(contains(topBlocks,segModule.Name));
                if isempty(candidate)
                    error("ThermalPack:ProgressiveSegmentSource", ...
                        "Could not locate generated progressive segment module %s.", ...
                        segModule.Name);
                end
                source = candidate(1);
            end
            sources(iCount) = source;
            libraries(iCount) = libModel;
        end
    end

    function source = progressiveSegmentSourceForCount(counts,sources,pCount)
        idx = find(counts == pCount,1);
        if isempty(idx)
            error("ThermalPack:ProgressiveSegmentSource", ...
                "No generated source exists for a %d-cell progressive segment.",pCount);
        end
        source = sources(idx);
    end

    function updateProgressiveForcedAirOperatingPoint(calc)
        if ~state.ProgressiveForcedAirBuilt
            return;
        end

        if strlength(state.ProgressiveForcedAirMassFlowCommandBlock) > 0
            thermalPackSetPSConstant( ...
                state.ProgressiveForcedAirMassFlowCommandBlock, ...
                calc.MassFlow_kg_s,"kg/s");
        end

        Tin_K = state.ForcedAirTemperature_C + 273.15;
        p_Pa = state.ForcedAirPressure_Pa;
        Ain = calc.FlowArea_m2;

        reservoirBlocks = [ ...
            state.ProgressiveForcedAirInletReservoirBlock, ...
            state.ProgressiveForcedAirOutletReservoirBlock];
        for kRes = 1:numel(reservoirBlocks)
            if strlength(reservoirBlocks(kRes)) == 0
                continue;
            end

            % Pressure is a front-end boundary condition, so select
            % specified-pressure mode when the installed Reservoir (G) exposes
            % that choice. The prompt helper is release tolerant.
            safeSetEnumBlockParamByPrompt(reservoirBlocks(kRes), ...
                "Reservoir pressure specification","Specified pressure");
            safeSetBlockParamByPrompt(reservoirBlocks(kRes), ...
                "Reservoir temperature", ...
                thermalPackFormatText("%.16g K",Tin_K));
            safeSetBlockParamByPrompt(reservoirBlocks(kRes), ...
                "Reservoir pressure", ...
                thermalPackFormatText("%.16g Pa",p_Pa));
            safeSetBlockParamByPrompt(reservoirBlocks(kRes), ...
                "Cross-sectional area at port A", ...
                thermalPackFormatText("%.16g m^2",Ain));
        end

        if strlength(state.ProgressiveForcedAirFlowSourceBlock) > 0
            safeSetBlockParamByPrompt(state.ProgressiveForcedAirFlowSourceBlock, ...
                "Cross-sectional area at port A", ...
                thermalPackFormatText("%.16g m^2",Ain));
            safeSetBlockParamByPrompt(state.ProgressiveForcedAirFlowSourceBlock, ...
                "Cross-sectional area at port B", ...
                thermalPackFormatText("%.16g m^2",Ain));
        end

        if strlength(state.ProgressiveForcedAirGasPropertiesBlock) > 0
            safeSetBlockParamByPrompt(state.ProgressiveForcedAirGasPropertiesBlock, ...
                "Reference temperature for gas properties", ...
                thermalPackFormatText("%.16g K",Tin_K));
            safeSetBlockParamByPrompt(state.ProgressiveForcedAirGasPropertiesBlock, ...
                "Specific heat at constant pressure", ...
                thermalPackFormatText("%.16g J/(kg*K)",calc.cp_J_kgK));
            safeSetBlockParamByPrompt(state.ProgressiveForcedAirGasPropertiesBlock, ...
                "Dynamic viscosity", ...
                thermalPackFormatText("%.16g Pa*s",calc.mu_Pa_s));
            safeSetBlockParamByPrompt(state.ProgressiveForcedAirGasPropertiesBlock, ...
                "Thermal conductivity", ...
                thermalPackFormatText("%.16g W/(m*K)",calc.k_W_mK));
        end

        if numel(state.ProgressiveForcedAirSegmentLengths_m) ~= ...
                numel(state.ProgressiveForcedAirChamberBlocks)
            error("ThermalPack:ProgressiveGasVolumeState", ...
                "Progressive Gas chamber/segment metadata are inconsistent.");
        end

        gasVolumes = zeros(numel(state.ProgressiveForcedAirChamberBlocks),1);
        for j = 1:numel(state.ProgressiveForcedAirChamberBlocks)
            gasVolumes(j) = Ain*state.ProgressiveForcedAirSegmentLengths_m(j);
            chamber = state.ProgressiveForcedAirChamberBlocks(j);
            safeSetBlockParamByPrompt(chamber,"Number of ports","2");
            safeSetBlockParamByPrompt(chamber,"Chamber volume", ...
                thermalPackFormatText("%.16g m^3",gasVolumes(j)));
            safeSetBlockParamByPrompt(chamber,"Cross-sectional area at port A", ...
                thermalPackFormatText("%.16g m^2",Ain));
            safeSetBlockParamByPrompt(chamber,"Cross-sectional area at port B", ...
                thermalPackFormatText("%.16g m^2",Ain));
            safeSetBlockParamByPrompt(chamber,"Initial temperature", ...
                thermalPackFormatText("%.16g K",Tin_K));
            safeSetBlockParamByPrompt(chamber,"Initial pressure", ...
                thermalPackFormatText("%.16g Pa",p_Pa));
        end
        state.ProgressiveForcedAirGasVolumes_m3 = gasVolumes;
    end

    function applyProgressiveAmbientResistanceToBlocks()
        if ~state.ProgressiveForcedAirBuilt
            return;
        end
        for kSeg = 1:numel(state.ProgressiveForcedAirSegmentBlocks)
            blockPath = state.ProgressiveForcedAirSegmentBlocks(kSeg);
            if getSimulinkBlockHandle(blockPath) > 0
                safeSetBlockParam(blockPath,"AmbientResistance", ...
                    num2str(state.ForcedAirAmbientRth_K_W,16));
            end
        end
    end

    function applyProgressiveCellElectricalDataToBlocks()
        if ~state.ProgressiveForcedAirBuilt
            return;
        end
        for kSeg = 1:numel(state.ProgressiveForcedAirSegmentBlocks)
            ids = state.ProgressiveForcedAirSegmentCellIDs{kSeg};
            segmentState = state;
            fullR0Dev = resizeNumericVector(state.R0Deviation_pct,state.TotalCells,0);
            fullTMDev = resizeNumericVector(state.ThermalMassDeviation_pct,state.TotalCells,0);
            fullKDev = resizeNumericVector(state.ThermalConductivityDeviation_pct,state.TotalCells,0);
            segmentState.R0Deviation_pct = fullR0Dev(ids);
            segmentState.ThermalMassDeviation_pct = fullTMDev(ids);
            segmentState.ThermalConductivityDeviation_pct = fullKDev(ids);
            applyCellElectricalDataToBlock( ...
                state.ProgressiveForcedAirSegmentBlocks(kSeg), ...
                segmentState,numel(ids));
        end
    end

    function buildProgressiveForcedAirSubsystem(generatedDir,stamp)
        if string(state.CoolingPlateMode) ~= "Forced Air Cooling" || ...
                string(state.ForcedAirModel) ~= "Progressive Gas"
            clearProgressiveForcedAirState();
            return;
        end

        calc = forcedAirGeneralCalculation( ...
            state.ForcedAirVelocity_m_s,state.ForcedAirTemperature_C, ...
            state.ForcedAirPressure_Pa,state.ForcedAirAxis, ...
            state.ForcedAirWallClearance_mm);
        geo = forcedAirGeometryAnalysis(state.ForcedAirAxis);

        N = state.TotalCells;
        P = state.P;
        S = state.S;
        if numel(geo.ColumnIndex) ~= N
            error("ThermalPack:ProgressiveCellMapping", ...
                "Forced-air geometry returned %d cell positions for a %d-cell battery.", ...
                numel(geo.ColumnIndex),N);
        end

        originalCellIDs = (1:N).';
        seriesGroup = ceil(originalCellIDs/P);
        physicalGroup = double(geo.ColumnIndex(:));
        pairRows = unique([seriesGroup physicalGroup],"rows","stable");
        nSegments = size(pairRows,1);

        if state.InterCellHeatTransfer == "Enabled" && nSegments > 1
            warning("ThermalPack:ProgressiveInterSegmentThermalPath", ...
                "Progressive Gas preserves the electrical P×S topology and " + ...
                "inter-cell thermal paths inside each generated segment, but direct " + ...
                "solid conduction across two different AmbH/Gas segments is not represented.");
        end

        segmentCellIDs = cell(nSegments,1);
        segmentCounts = zeros(nSegments,1);
        segmentSeries = pairRows(:,1);
        segmentPhysical = pairRows(:,2);
        segmentNames = strings(nSegments,1);
        % Fixed positive-axis airflow direction: Xmin→Xmax or Ymin→Ymax.
        physicalOrder = (1:geo.Columns).';
        airOrderForPhysical = zeros(geo.Columns,1);
        airOrderForPhysical(physicalOrder) = (1:geo.Columns).';
        segmentAirOrder = airOrderForPhysical(segmentPhysical);

        for kSeg = 1:nSegments
            ids = originalCellIDs(seriesGroup == segmentSeries(kSeg) & ...
                physicalGroup == segmentPhysical(kSeg));
            segmentCellIDs{kSeg} = ids(:).';
            segmentCounts(kSeg) = numel(ids);
            segmentNames(kSeg) = thermalPackFormatText( ...
                "FA_S%03d_G%03d",segmentSeries(kSeg),segmentPhysical(kSeg));
        end

        % Fail fast if the spatial/electrical partition does not form an
        % exact one-to-one cover of the original cell population. Progressive
        % Gas is allowed to repartition the model blocks, but never to duplicate
        % or omit a physical/electrical cell.
        partitionedIDs = sort([segmentCellIDs{:}]);
        if numel(partitionedIDs) ~= N || ...
                any(partitionedIDs(:).' ~= 1:N)
            error("ThermalPack:ProgressivePartitionCoverage", ...
                "Progressive forced-air partition did not cover original cell IDs 1:%d exactly once.",N);
        end

        if abs(sum(geo.SegmentLengths_m)-geo.ArrayFlowLength_m) > ...
                max(1e-10,1e-8*geo.ArrayFlowLength_m)
            error("ThermalPack:ProgressiveSegmentLengthClosure", ...
                "Progressive Gas segment lengths do not close to the detected streamwise battery length.");
        end

        [sourceCounts,segmentSources,segmentLibraries] = ...
            buildProgressiveSegmentSources(unique(segmentCounts), ...
            generatedDir,stamp);

        hOldBattery = getSimulinkBlockHandle(char(batteryBlock),true);
        if isempty(hOldBattery) || hOldBattery <= 0
            error("ThermalPack:ProgressiveOriginalBattery", ...
                "Could not resolve the standard rebuilt battery before progressive conversion.");
        end

        savedP = simscape.connectedPorts(hOldBattery,"p");
        savedN = simscape.connectedPorts(hOldBattery,"n");
        if isempty(savedP) || isempty(savedN)
            error("ThermalPack:ProgressiveElectricalConnection", ...
                "The standard rebuilt battery must have connected p and n ports before progressive conversion.");
        end
        oldPosition = get_param(batteryBlock,"Position");

        allPortInfo = simscape.connectionPortProperties(hOldBattery);
        for kPort = 1:numel(allPortInfo)
            portName = string(allPortInfo(kPort).Name);
            try
                if ~isempty(simscape.connectedPorts(hOldBattery,portName))
                    simscape.removeConnection(hOldBattery,portName);
                end
            catch
            end
        end
        delete_block(batteryBlock);
        % Mark structural conversion as started. If any subsequent block/library
        % operation fails, the next REBUILD will restore a clean V5 working model.
        state.ProgressiveForcedAirBuilt = true;
        state.ProgressiveForcedAirSubsystem = batteryBlock;

        add_block("simulink/Ports & Subsystems/Subsystem",char(batteryBlock), ...
            "Position",oldPosition);
        try delete_block(batteryBlock + "/In1"); catch, end
        try delete_block(batteryBlock + "/Out1"); catch, end

        connectionPortSrc = thermalPackResolveLibraryBlockByName( ...
            ["nesl_utility","simscape"],"Connection Port");
        flowSourceSrc = thermalPackResolveLibraryBlockByName( ...
            ["fl_lib"],"Flow Rate Source (G)");
        chamberSrc = thermalPackResolveLibraryBlockByName( ...
            ["fl_lib"],"Constant Volume Chamber (G)");
        reservoirSrc = thermalPackResolveLibraryBlockByName( ...
            ["fl_lib"],"Reservoir (G)");
        gasPropertiesSrc = thermalPackResolveLibraryBlockByName( ...
            ["fl_lib"],"Gas Properties (G)");
        psConstantSrc = thermalPackResolveLibraryBlockByName( ...
            ["fl_lib"],"PS Constant");

        required = [connectionPortSrc flowSourceSrc chamberSrc ...
            reservoirSrc gasPropertiesSrc psConstantSrc];
        if any(strlength(required) == 0)
            error("ThermalPack:ProgressiveLibraryResolution", ...
                "Could not resolve one or more required Simscape blocks: " + ...
                "Connection Port, Flow Rate Source (G), Constant Volume Chamber (G), " + ...
                "Reservoir (G), Gas Properties (G), PS Constant.");
        end

        pConnBlock = batteryBlock + "/p";
        nConnBlock = batteryBlock + "/n";
        add_block(char(connectionPortSrc),char(pConnBlock), ...
            "Position",[35 130 95 170]);
        add_block(char(connectionPortSrc),char(nConnBlock), ...
            "Position",[930 130 990 170]);
        try set_param(pConnBlock,"Port","1"); catch, end
        try set_param(nConnBlock,"Port","2"); catch, end
        safeSetBlockParamByPrompt(pConnBlock,"Port number","1");
        safeSetBlockParamByPrompt(nConnBlock,"Port number","2");
        pConnInner = thermalPackFirstConservingPortName( ...
            getSimulinkBlockHandle(char(pConnBlock),true));
        nConnInner = thermalPackFirstConservingPortName( ...
            getSimulinkBlockHandle(char(nConnBlock),true));

        segmentBlocks = strings(nSegments,1);
        segmentHandles = zeros(nSegments,1);
        for kSeg = 1:nSegments
            source = progressiveSegmentSourceForCount( ...
                sourceCounts,segmentSources,segmentCounts(kSeg));
            segmentBlocks(kSeg) = batteryBlock + "/" + segmentNames(kSeg);
            x0 = 180 + (segmentSeries(kSeg)-1)*165;
            y0 = 40 + (segmentAirOrder(kSeg)-1)*155;
            add_block(char(source),char(segmentBlocks(kSeg)), ...
                "Position",[x0 y0 x0+115 y0+125]);
            segmentHandles(kSeg) = getSimulinkBlockHandle( ...
                char(segmentBlocks(kSeg)),true);
            parameterizeProgressiveSegmentBlock( ...
                segmentBlocks(kSeg),segmentCellIDs{kSeg});
        end

        seriesRepresentative = zeros(S,1);
        for sGroup = 1:S
            idx = find(segmentSeries == sGroup);
            if isempty(idx)
                error("ThermalPack:ProgressiveElectricalMapping", ...
                    "No progressive segment was generated for series group %d.",sGroup);
            end
            rep = idx(1);
            seriesRepresentative(sGroup) = rep;
            for kLocal = 2:numel(idx)
                simscape.addConnection(segmentHandles(rep),"p", ...
                    segmentHandles(idx(kLocal)),"p","autorouting","smart");
                simscape.addConnection(segmentHandles(rep),"n", ...
                    segmentHandles(idx(kLocal)),"n","autorouting","smart");
            end
        end
        for sGroup = 1:S-1
            repA = seriesRepresentative(sGroup);
            repB = seriesRepresentative(sGroup+1);
            simscape.addConnection(segmentHandles(repA),"n", ...
                segmentHandles(repB),"p","autorouting","smart");
        end
        simscape.addConnection( ...
            getSimulinkBlockHandle(char(pConnBlock),true),pConnInner, ...
            segmentHandles(seriesRepresentative(1)),"p", ...
            "autorouting","smart");
        simscape.addConnection( ...
            segmentHandles(seriesRepresentative(end)),"n", ...
            getSimulinkBlockHandle(char(nConnBlock),true),nConnInner, ...
            "autorouting","smart");

        inletReservoirBlock = batteryBlock + "/Air_Inlet_Reservoir";
        outletReservoirBlock = batteryBlock + "/Air_Outlet_Reservoir";
        flowSourceBlock = batteryBlock + "/Air_Mass_Flow_Source";
        massFlowCommandBlock = batteryBlock + "/Air_Mass_Flow_Command";
        gasPropertiesBlock = batteryBlock + "/Dry_Air_Properties";

        gasY = 80 + geo.Columns*155 + 80;
        add_block(char(reservoirSrc),char(inletReservoirBlock), ...
            "Position",[80 gasY 180 gasY+80]);
        add_block(char(flowSourceSrc),char(flowSourceBlock), ...
            "Position",[230 gasY 340 gasY+80]);
        add_block(char(psConstantSrc),char(massFlowCommandBlock), ...
            "Position",[235 gasY-80 335 gasY-35]);
        add_block(char(gasPropertiesSrc),char(gasPropertiesBlock), ...
            "Position",[230 gasY+120 360 gasY+185]);

        hFlow = getSimulinkBlockHandle(char(flowSourceBlock),true);
        hCmd = getSimulinkBlockHandle(char(massFlowCommandBlock),true);

        % Make the gas source mode explicit instead of relying on release
        % defaults: the PS Constant commands positive A->B mass flow.
        safeSetEnumBlockParamByPrompt(flowSourceBlock, ...
            "Source type","Controlled");
        safeSetEnumBlockParamByPrompt(flowSourceBlock, ...
            "Flow rate type","Mass flow rate");

        thermalPackSetPSConstant(massFlowCommandBlock, ...
            calc.MassFlow_kg_s,"kg/s");
        simscape.addConnection(hCmd,"O",hFlow,"M", ...
            "autorouting","smart");

        chamberBlocks = strings(geo.Columns,1);
        chamberHandles = zeros(geo.Columns,1);
        orderedLengths = geo.SegmentLengths_m(physicalOrder);
        for j = 1:geo.Columns
            chamberBlocks(j) = batteryBlock + "/Air_Chamber_" + j;
            x0 = 390 + (j-1)*135;
            add_block(char(chamberSrc),char(chamberBlocks(j)), ...
                "Position",[x0 gasY x0+100 gasY+105]);

            % The serial gas network requires ports A and B. Configure both
            % ports before adding any B-port connection.
            safeSetBlockParamByPrompt(chamberBlocks(j), ...
                "Number of ports","2");

            chamberHandles(j) = getSimulinkBlockHandle( ...
                char(chamberBlocks(j)),true);

            % Fail here with a precise diagnostic if an installed release
            % uses a different chamber mask/port convention. This is a
            % structural compatibility check only; no thermal physics change.
            chamberPortInfo = simscape.connectionPortProperties( ...
                chamberHandles(j));
            chamberPortNames = strings(1,numel(chamberPortInfo));
            for kPortFA = 1:numel(chamberPortInfo)
                chamberPortNames(kPortFA) = ...
                    string(chamberPortInfo(kPortFA).Name);
            end
            if ~all(ismember(["A","B","H"],chamberPortNames))
                chamberPortMessage = thermalPackFormatText( ...
                    ["Progressive Gas chamber %s was configured for two gas ports, " ...
                     "but the required A/B/H ports were not exposed. Available ports: %s"], ...
                    chamberBlocks(j),strjoin(chamberPortNames,", "));
                error("ThermalPack:ProgressiveGasChamberPorts", ...
                    char(chamberPortMessage));
            end
        end
        outletX = 430 + geo.Columns*135;
        add_block(char(reservoirSrc),char(outletReservoirBlock), ...
            "Position",[outletX gasY outletX+100 gasY+80]);

        hInlet = getSimulinkBlockHandle(char(inletReservoirBlock),true);
        hOutlet = getSimulinkBlockHandle(char(outletReservoirBlock),true);
        hGasProperties = getSimulinkBlockHandle(char(gasPropertiesBlock),true);

        simscape.addConnection(hInlet,"A",hFlow,"A", ...
            "autorouting","smart");
        simscape.addConnection(hFlow,"B",chamberHandles(1),"A", ...
            "autorouting","smart");
        for j = 1:geo.Columns-1
            simscape.addConnection(chamberHandles(j),"B", ...
                chamberHandles(j+1),"A","autorouting","smart");
        end
        simscape.addConnection(chamberHandles(end),"B",hOutlet,"A", ...
            "autorouting","smart");
        simscape.addConnection(hGasProperties,"A",chamberHandles(1),"A", ...
            "autorouting","smart");

        for kSeg = 1:nSegments
            simscape.addConnection(segmentHandles(kSeg),"AmbH", ...
                chamberHandles(segmentAirOrder(kSeg)),"H", ...
                "autorouting","smart");
        end

        % Resolve the two Simscape Connection Port blocks as conserving ports
        % on the parent subsystem, then reconnect the original V5 electrical
        % source/load endpoints. No ambient or liquid boundary is exported:
        % Progressive Gas owns the complete forced-air thermal path.
        hSubsystem = getSimulinkBlockHandle(char(batteryBlock),true);
        subInfo = simscape.connectionPortProperties(hSubsystem);
        subNames = strings(1,numel(subInfo));
        for k = 1:numel(subInfo)
            subNames(k) = string(subInfo(k).Name);
        end
        pSub = ""; nSub = "";
        if any(subNames == "p"), pSub = "p"; end
        if any(subNames == "n"), nSub = "n"; end
        if strlength(pSub) == 0 && numel(subNames) >= 1
            pSub = subNames(1);
        end
        if strlength(nSub) == 0 && numel(subNames) >= 2
            nSub = subNames(2);
        end
        if strlength(pSub) == 0 || strlength(nSub) == 0 || pSub == nSub
            error("ThermalPack:ProgressiveSubsystemPorts", ...
                "Could not resolve separate p and n conserving ports on the progressive subsystem.");
        end
        simscape.addConnection(hSubsystem,pSub, ...
            savedP(1).Block,savedP(1).PortName,"autorouting","smart");
        simscape.addConnection(hSubsystem,nSub, ...
            savedN(1).Block,savedN(1).PortName,"autorouting","smart");

        % Progressive Gas does not use any Thermal Liquid cooling circuit.
        % The old battery thermal ports have now been removed, so retaining
        % those circuits would leave orphan physical networks with no Solver
        % Configuration. Remove them from Thermal_Model_v5_UI only.
        removeUnusedLiquidCoolingBranchesForProgressiveGas();

        % Publish the generated paths before compilation so physical
        % operating-point parameters are applied before network validation.
        state.ProgressiveForcedAirBuilt = true;
        state.ProgressiveForcedAirSubsystem = batteryBlock;
        state.ProgressiveForcedAirSegmentBlocks = segmentBlocks;
        state.ProgressiveForcedAirSegmentNames = segmentNames;
        state.ProgressiveForcedAirSegmentCellIDs = segmentCellIDs;
        state.ProgressiveForcedAirSegmentSeriesGroup = segmentSeries;
        state.ProgressiveForcedAirSegmentPhysicalGroup = segmentPhysical;
        state.ProgressiveForcedAirSegmentAirOrder = segmentAirOrder;
        state.ProgressiveForcedAirChamberBlocks = chamberBlocks;
        state.ProgressiveForcedAirChamberPhysicalGroups = physicalOrder;
        state.ProgressiveForcedAirSegmentLengths_m = orderedLengths(:);
        state.ProgressiveForcedAirFlowSourceBlock = flowSourceBlock;
        state.ProgressiveForcedAirMassFlowCommandBlock = massFlowCommandBlock;
        state.ProgressiveForcedAirInletReservoirBlock = inletReservoirBlock;
        state.ProgressiveForcedAirOutletReservoirBlock = outletReservoirBlock;
        state.ProgressiveForcedAirGasPropertiesBlock = gasPropertiesBlock;
        state.ProgressiveForcedAirGeneratedLibraries = segmentLibraries;

        updateProgressiveForcedAirOperatingPoint(calc);
        applyProgressiveAmbientResistanceToBlocks();

        % Refresh compile-time defaults after the structural conversion. This
        % keeps any surviving model-level references valid without changing the
        % actual Progressive Gas operating point set above.
        initializeWorkingModelDefaults();

        % Compile once after the complete electrical + gas topology AND the
        % intended gas operating point exist. Preserve every nested Simulink
        % cause instead of reducing "Error due to multiple causes" to one line.
        try
            set_param(mdl,"SimulationCommand","update");
        catch MEupdate
            detailedUpdateText = thermalPackDetailedExceptionText(MEupdate);
            try
                fprintf(2,'\n=== ThermalPack Progressive Gas model-update diagnostics ===\n%s\n=== End diagnostics ===\n', ...
                    char(detailedUpdateText));
            catch
            end
            wrappedUpdate = MException( ...
                "ThermalPack:ProgressiveSubsystemUpdate", ...
                "Generated progressive subsystem failed model update.%s%s", ...
                newline,char(detailedUpdateText));
            try
                wrappedUpdate = addCause(wrappedUpdate,MEupdate);
            catch
            end
            throw(wrappedUpdate);
        end

        try
            Simulink.Annotation(char(batteryBlock),sprintf([ ...
                'ThermalPack Progressive Forced Air\\n' ...
                '%d cells | %d electrical series groups | %d airflow columns\\n' ...
                'Airflow %s (Min->Max fixed) | %d battery segments\\n' ...
                'mdot = %.6g kg/s | h = %.3f W/m^2K'], ...
                N,S,geo.Columns,state.ForcedAirAxis, ...
                nSegments,calc.MassFlow_kg_s,calc.h_W_m2K));
        catch
        end

        save_system(mdl);
    end

    function simIn = applyProgressiveBatteryParametersToSimulationInput(simIn,cfg)
        fullR0Dev = resizeNumericVector(state.R0Deviation_pct,state.TotalCells,0);
        fullTMDev = resizeNumericVector(state.ThermalMassDeviation_pct,state.TotalCells,0);
        fullKDev = resizeNumericVector(state.ThermalConductivityDeviation_pct,state.TotalCells,0);

        for kSeg = 1:numel(state.ProgressiveForcedAirSegmentBlocks)
            blockPath = state.ProgressiveForcedAirSegmentBlocks(kSeg);
            ids = state.ProgressiveForcedAirSegmentCellIDs{kSeg};
            nSegCells = numel(ids);

            % Fail fast on the concrete generated block, then repeat the
            % state override on SimulationInput so a sweep/run cannot fall
            % back to the V5 master initialization.
            applyInitialSOCToBlock(blockPath,socField.Value,nSegCells,1);
            verifyInitialSOCOnBlock(blockPath,socField.Value,nSegCells,1);
            simIn = setInitialSOCOnSimulationInput( ...
                simIn,blockPath,socField.Value,nSegCells,1);

            simIn = simIn.setBlockParameter(blockPath,"batteryTemperature", ...
                thermalPackFormatText("repmat(%.16g,%d,1)", ...
                initialCellTempField.Value + 273.15,nSegCells));
            simIn = simIn.setBlockParameter(blockPath,"BatteryCapacityCell", ...
                num2str(capacityField.Value,16));
            simIn = simIn.setBlockParameter(blockPath,"HeightCell", ...
                num2str(heightField.Value/1000,16));
            simIn = simIn.setBlockParameter(blockPath,"NumThermalModelsCell", ...
                num2str(cfg.NodesPerCell));
            simIn = simIn.setBlockParameter(blockPath,"BatteryThermalMassCell", ...
                num2str(thermalMassField.Value,16));
            simIn = simIn.setBlockParameter(blockPath,"ThermalConductivityZCell", ...
                num2str(conductivityField.Value,16));
            simIn = simIn.setBlockParameter(blockPath,"CrossSectionalAreaXYCell", ...
                num2str(thermalAreaField.Value,16));

            [simIn,extrapSet] = setSimInputEnumParamByName( ...
                simIn,blockPath,"ExtrapolationMethodCell", ...
                state.ExtrapolationMethod);
            if ~extrapSet
                error("ThermalPack:ExtrapolationEnumResolution", ...
                    "Could not resolve Extrapolation Method for progressive segment %s.", ...
                    blockPath);
            end

            simIn = simIn.setBlockParameter(blockPath,"VoltageRangeCell", ...
                mat2str(state.VoltageRange_V,16));
            simIn = simIn.setBlockParameter(blockPath,"SOCBreakpointsCell", ...
                mat2str(state.OCVSOCBreakpoints,16));
            simIn = simIn.setBlockParameter(blockPath,"TemperatureBreakpointsCell", ...
                mat2str(state.OCVTemperature_C + 273.15,16));
            simIn = simIn.setBlockParameter(blockPath,"OpenCircuitVoltageThermalCell", ...
                mat2str(state.OCVTable_V,16));
            simIn = simIn.setBlockParameter(blockPath,"ResistanceSOCBreakpointsCell", ...
                mat2str(state.ResistanceSOCBreakpoints,16));
            simIn = simIn.setBlockParameter(blockPath,"ResistanceTemperatureBreakpointsCell", ...
                mat2str(state.ResistanceTemperature_C + 273.15,16));
            simIn = simIn.setBlockParameter(blockPath,"R0ThermalCell", ...
                mat2str(state.R0Table_Ohm,16));
            simIn = setSimInputElectrochemicalDynamics(simIn,blockPath,state);
            % Cell-deviation mask parameters are optional on some generated
            % Battery Builder variants/releases. Check the concrete block before
            % adding a SimulationInput override; setBlockParameter itself can
            % otherwise defer the "parameter does not exist" error until sim().
            [simIn,~] = setOptionalSimInputBlockParameter( ...
                simIn,blockPath,"R0ThermalCellPercentDeviation", ...
                mat2str(fullR0Dev(ids),16));
            [simIn,~] = setOptionalSimInputBlockParameter( ...
                simIn,blockPath,"BatteryThermalMassCellPercentDeviation", ...
                mat2str(fullTMDev(ids),16));
            [simIn,~] = setOptionalSimInputBlockParameter( ...
                simIn,blockPath,"ThermalConductivityZCellPercentDeviation", ...
                mat2str(fullKDev(ids),16));

            simIn = simIn.setBlockParameter(blockPath,"AmbientResistance", ...
                num2str(state.ForcedAirAmbientRth_K_W,16));

            if state.InterCellHeatTransfer == "Enabled"
                [simIn,interCellApplied] = setOptionalSimInputBlockParameter( ...
                    simIn,blockPath,"InterCellThermalResistance", ...
                    num2str(interCellRField.Value,16));
                if ~interCellApplied && nSegCells > 1
                    warning("ThermalPack:OptionalInterCellResistanceUnavailable", ...
                        ["Generated progressive battery segment '%s' does not expose " ...
                         "InterCellThermalResistance. The generated architecture's " ...
                         "native thermal connectivity will be retained."],blockPath);
                end
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

        winW = min(900,max(700,mon(3)-140));
        winH = min(820,max(650,mon(4)-120));
        winX = mon(1) + (mon(3)-winW)/2;
        winY = mon(2) + (mon(4)-winH)/2;

        plateFig = uifigure( ...
            "Name","ThermalPack — Cooling Plate Settings", ...
            "WindowStyle","modal", ...
            "Position",[winX winY winW winH], ...
            "CloseRequestFcn",@(srcFig,~)closeCoolingPlateSettings(srcFig));
        movegui(plateFig,"onscreen");

        pg = uigridlayout(plateFig,[22 2]);
        pg.ColumnWidth = {330,'1x'};
        pg.RowHeight = {44,32,36,36,36,32,36,72,120,32,36,36,36,36,36,32,36,36,36,36,36,44};
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

        %% Automatic battery-to-plate geometry mapping
        mappingHdr = uilabel(pg, ...
            "Text","BATTERY → PLATE MAPPING (AUTOMATIC)", ...
            "FontWeight","bold");
        mappingHdr.Layout.Row = 6;
        mappingHdr.Layout.Column = [1 2];

        nodeCountLbl = uilabel(pg,"Text","Battery Thermal Nodes");
        nodeCountLbl.Layout.Row = 7;
        nodeCountLbl.Layout.Column = 1;

        if string(state.CoolingPlateMode) == "Serpentine Cooling"
            activeNodeCount = state.SerpentineThermalNodeCount;
            activeNodeDimensions = state.SerpentineThermalNodeDimensions;
            activeNodeLocations = state.SerpentineThermalNodeLocations;
            nodeCountLbl.Text = "Battery SP Thermal Nodes";
        elseif string(state.CoolingPlateMode) == "Side Cooling"
            activeNodeCount = state.SideThermalNodeCount;
            activeNodeDimensions = state.SideThermalNodeDimensions;
            activeNodeLocations = state.SideThermalNodeLocations;
            nodeCountLbl.Text = "Battery " + state.SideBoundary + "H Thermal Nodes";
        else
            activeNodeCount = state.BatteryThermalNodeCount;
            activeNodeDimensions = state.BatteryThermalNodeDimensions;
            activeNodeLocations = state.BatteryThermalNodeLocations;
        end

        if isempty(activeNodeCount)
            nodeCountText = "Pending REBUILD BATTERY";
        else
            nodeCountText = string(activeNodeCount);
        end
        nodeCountField = uieditfield(pg,"text", ...
            "Value",nodeCountText, ...
            "Editable","off");
        nodeCountField.Layout.Row = 7;
        nodeCountField.Layout.Column = 2;

        nodeDimLbl = uilabel(pg,"Text","Thermal Node Dimensions (m)");
        nodeDimLbl.Layout.Row = 8;
        nodeDimLbl.Layout.Column = 1;
        nodeDimLbl.VerticalAlignment = "top";

        nodeDimField = uitextarea(pg, ...
            "Value",thermalNodeMatrixDisplay(activeNodeDimensions), ...
            "Editable","off");
        nodeDimField.Layout.Row = 8;
        nodeDimField.Layout.Column = 2;

        nodeLocLbl = uilabel(pg,"Text","Thermal Node Centre Locations (m)");
        nodeLocLbl.Layout.Row = 9;
        nodeLocLbl.Layout.Column = 1;
        nodeLocLbl.VerticalAlignment = "top";

        nodeLocField = uitextarea(pg, ...
            "Value",thermalNodeMatrixDisplay(activeNodeLocations), ...
            "Editable","off");
        nodeLocField.Layout.Row = 9;
        nodeLocField.Layout.Column = 2;

        %% Plate material
        materialHdr = uilabel(pg,"Text","PLATE MATERIAL","FontWeight","bold");
        materialHdr.Layout.Row = 10;
        materialHdr.Layout.Column = [1 2];

        thLbl = uilabel(pg,"Text","Plate Thickness (mm)");
        thLbl.Layout.Row = 11;
        thLbl.Layout.Column = 1;

        plateThicknessField = uieditfield(pg,"numeric", ...
            "Value",state.PlateThickness_mm, ...
            "Limits",[0.001 Inf]);
        plateThicknessField.Layout.Row = 11;
        plateThicknessField.Layout.Column = 2;

        kLbl = uilabel(pg,"Text","Thermal Conductivity (W/mK)");
        kLbl.Layout.Row = 12;
        kLbl.Layout.Column = 1;

        plateConductivityField = uieditfield(pg,"numeric", ...
            "Value",state.PlateConductivity_W_mK, ...
            "Limits",[0 Inf]);
        plateConductivityField.Layout.Row = 12;
        plateConductivityField.Layout.Column = 2;

        rhoLbl = uilabel(pg,"Text","Density (kg/m³)");
        rhoLbl.Layout.Row = 13;
        rhoLbl.Layout.Column = 1;

        plateDensityField = uieditfield(pg,"numeric", ...
            "Value",state.PlateDensity_kg_m3, ...
            "Limits",[0.001 Inf]);
        plateDensityField.Layout.Row = 13;
        plateDensityField.Layout.Column = 2;

        cpLbl = uilabel(pg,"Text","Specific Heat (J/kgK)");
        cpLbl.Layout.Row = 14;
        cpLbl.Layout.Column = 1;

        plateCpField = uieditfield(pg,"numeric", ...
            "Value",state.PlateSpecificHeat_J_kgK, ...
            "Limits",[0.001 Inf]);
        plateCpField.Layout.Row = 14;
        plateCpField.Layout.Column = 2;

        tempLbl = uilabel(pg,"Text","Initial Plate Temperature (°C)");
        tempLbl.Layout.Row = 15;
        tempLbl.Layout.Column = 1;

        plateInitialTempField = uieditfield(pg,"numeric", ...
            "Value",state.InitialPlateTemperature_C, ...
            "Limits",[-273.14 Inf]);
        plateInitialTempField.Layout.Row = 15;
        plateInitialTempField.Layout.Column = 2;

        %% Channel design
        designHdr = uilabel(pg,"Text","CHANNEL DESIGN","FontWeight","bold");
        designHdr.Layout.Row = 16;
        designHdr.Layout.Column = [1 2];

        nChLbl = uilabel(pg,"Text","Number of Coolant Channels");
        nChLbl.Layout.Row = 17;
        nChLbl.Layout.Column = 1;

        channelsField = uispinner(pg, ...
            "Limits",[1 50], ...
            "Step",1, ...
            "Value",min(50,max(1,round(state.NumCoolantChannels))));
        channelsField.Layout.Row = 17;
        channelsField.Layout.Column = 2;

        edgeField = uidropdown(pg, ...
            "Items",[ ...
                "Edge cooling along Y axis at X = Xmin", ...
                "Edge cooling along X axis at Y = Ymin", ...
                "Edge cooling along Y axis at X = Xmax", ...
                "Edge cooling along X axis at Y = Ymax"], ...
            "Value",state.EdgeCoolingSelection, ...
            "Visible","off");
        edgeField.Layout.Row = 17;
        edgeField.Layout.Column = 2;

        orientLbl = uilabel(pg,"Text","Channel Orientation");
        orientLbl.Layout.Row = 18;
        orientLbl.Layout.Column = 1;

        orientationField = uidropdown(pg, ...
            "Items",["Channels along X axis","Channels along Y axis"], ...
            "Value",state.ChannelOrientation);
        orientationField.Layout.Row = 18;
        orientationField.Layout.Column = 2;

        hydLbl = uilabel(pg,"Text","Coolant Channel Hydraulic Diameter (mm)");
        hydLbl.Layout.Row = 19;
        hydLbl.Layout.Column = 1;

        hydraulicDiameterField = uieditfield(pg,"numeric", ...
            "Value",state.ChannelHydraulicDiameter_mm, ...
            "Limits",[0.001 Inf]);
        hydraulicDiameterField.Layout.Row = 19;
        hydraulicDiameterField.Layout.Column = 2;

        distLbl = uilabel(pg,"Text","Distributor Pipe Diameter (mm)");
        distLbl.Layout.Row = 20;
        distLbl.Layout.Column = 1;

        distributorDiameterField = uieditfield(pg,"numeric", ...
            "Value",state.DistributorDiameter_mm, ...
            "Limits",[0.001 Inf]);
        distributorDiameterField.Layout.Row = 20;
        distributorDiameterField.Layout.Column = 2;

        roughLbl = uilabel(pg,"Text","Channel / Distributor Roughness (mm)");
        roughLbl.Layout.Row = 21;
        roughLbl.Layout.Column = 1;

        roughnessField = uieditfield(pg,"numeric", ...
            "Value",state.ChannelRoughness_mm, ...
            "Limits",[0 Inf]);
        roughnessField.Layout.Row = 21;
        roughnessField.Layout.Column = 2;

        refreshPlateTypeSettingsUI();

        function refreshPlateTypeSettingsUI()
            if string(state.CoolingPlateMode) == "Serpentine Cooling" || ...
                    string(state.CoolingPlateMode) == "Side Cooling"
                plateType = "Parallel Channels";
            else
                plateType = state.CoolingPlateType;
            end

            if plateType == "U-Shaped Channels"
                designHdr.Text = "U-SHAPED CHANNEL DESIGN";

                nChLbl.Text = "Number of Flat Channel Partitions";
                channelsField.Visible = "on";
                edgeField.Visible = "off";
                channelsField.Value = min(50,max(1, ...
                    round(state.UShapedChannelPartitions)));

                orientLbl.Text = "Channel Orientation";
                orientLbl.Visible = "on";
                orientationField.Visible = "on";
                orientationField.Value = state.ChannelOrientation;

                hydLbl.Text = "Channel Thickness (mm)";
                hydraulicDiameterField.Value = ...
                    state.UShapedChannelThickness_mm;

                distLbl.Text = "Partition Width (mm)";
                distributorDiameterField.Value = ...
                    state.UShapedPartitionWidth_mm;

                roughLbl.Text = "Coolant Channel Roughness (mm)";

            elseif plateType == "Edge Cooling"
                designHdr.Text = "EDGE COOLING DESIGN";

                nChLbl.Text = "Edge to be Cooled";
                channelsField.Visible = "off";
                edgeField.Visible = "on";
                edgeField.Value = state.EdgeCoolingSelection;

                orientLbl.Text = "Channel Orientation";
                orientLbl.Visible = "off";
                orientationField.Visible = "off";

                hydLbl.Text = "Cooling Channel Hydraulic Diameter (mm)";
                hydraulicDiameterField.Value = ...
                    state.EdgeChannelHydraulicDiameter_mm;

                distLbl.Text = "Cooling Channel Cross-Section Area (mm²)";
                distributorDiameterField.Value = ...
                    state.EdgeChannelArea_mm2;

                roughLbl.Text = "Coolant Channel Roughness (mm)";

            else
                designHdr.Text = "PARALLEL CHANNEL DESIGN";

                nChLbl.Text = "Number of Coolant Channels";
                channelsField.Visible = "on";
                edgeField.Visible = "off";
                channelsField.Value = min(50,max(1, ...
                    round(state.NumCoolantChannels)));

                orientLbl.Text = "Channel Orientation";
                orientLbl.Visible = "on";
                orientationField.Visible = "on";
                orientationField.Value = state.ChannelOrientation;

                hydLbl.Text = "Coolant Channel Hydraulic Diameter (mm)";
                hydraulicDiameterField.Value = ...
                    state.ChannelHydraulicDiameter_mm;

                distLbl.Text = "Distributor Pipe Diameter (mm)";
                distributorDiameterField.Value = ...
                    state.DistributorDiameter_mm;

                roughLbl.Text = "Channel / Distributor Roughness (mm)";
            end
        end

        btnGrid = uigridlayout(pg,[1 2]);
        btnGrid.Layout.Row = 22;
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

            % Preserve discretization independently for each cell format.
            formatKey = char(string(state.CellFormat));
            state.(formatKey).PlatePartitionsX = state.PlatePartitionsX;
            state.(formatKey).PlatePartitionsY = state.PlatePartitionsY;

            state.PlateThickness_mm = plateThicknessField.Value;
            state.PlateConductivity_W_mK = plateConductivityField.Value;
            state.PlateDensity_kg_m3 = plateDensityField.Value;
            state.PlateSpecificHeat_J_kgK = plateCpField.Value;
            state.InitialPlateTemperature_C = plateInitialTempField.Value;
            state.ChannelRoughness_mm = roughnessField.Value;

            activePlateType = state.CoolingPlateType;
            if string(state.CoolingPlateMode) == "Serpentine Cooling" || ...
                    string(state.CoolingPlateMode) == "Side Cooling"
                activePlateType = "Parallel Channels";
            end

            if activePlateType == "U-Shaped Channels"
                state.UShapedChannelPartitions = round(channelsField.Value);
                state.ChannelOrientation = string(orientationField.Value);
                state.UShapedChannelThickness_mm = ...
                    hydraulicDiameterField.Value;
                state.UShapedPartitionWidth_mm = ...
                    distributorDiameterField.Value;

            elseif activePlateType == "Edge Cooling"
                state.EdgeCoolingSelection = string(edgeField.Value);
                state.EdgeChannelHydraulicDiameter_mm = ...
                    hydraulicDiameterField.Value;
                state.EdgeChannelArea_mm2 = ...
                    distributorDiameterField.Value;

            else
                state.NumCoolantChannels = round(channelsField.Value);
                state.ChannelOrientation = string(orientationField.Value);
                state.ChannelHydraulicDiameter_mm = ...
                    hydraulicDiameterField.Value;
                state.DistributorDiameter_mm = ...
                    distributorDiameterField.Value;
            end

            applyCoolingPlateSettingsToBlock(bottomPlateBlock,state);
            applyCoolingPlateSettingsToBlock(topPlateBlock,state);
            if getSimulinkBlockHandle(serpentinePlateBlock) > 0
                serpPlateState = state;
                serpPlateState.CoolingPlateType = "Parallel Channels";
                applyCoolingPlateSettingsToBlock(serpentinePlateBlock,serpPlateState);
            end
            sidePlateState = state;
            sidePlateState.CoolingPlateType = "Parallel Channels";
            for kSide = 1:numel(sideBoundaryNames)
                applyCoolingPlateSettingsToBlock( ...
                    sidePlateBlocks(kSide),sidePlateState);
            end

%% Keep the existing model variable used by the Parallel Channels
            % initial-temperature parameter synchronized.
            try
                mdlWks = get_param(mdl,"ModelWorkspace");
                assignin(mdlWks,"T_plate_K", ...
                    state.InitialPlateTemperature_C + 273.15);
            catch
            end

            save_system(mdl);

            statusLabel.Text = thermalPackFormatText( ...
                "Cooling plate settings applied — %s, %d×%d plate partitions", ...
                state.CoolingPlateType, ...
                state.PlatePartitionsX,state.PlatePartitionsY);
        end
    end

    function lines = thermalNodeMatrixDisplay(data)
        if isempty(data)
            lines = "Pending REBUILD BATTERY";
            return;
        end

        numericData = [];
        try
            numericData = double(data);
        catch
            try
                numericData = value(data,"m");
            catch
            end
        end

        if isempty(numericData)
            lines = "Unavailable";
            return;
        end

        numericData = squeeze(numericData);
        if isvector(numericData)
            numericData = reshape(numericData,1,[]);
        end

        lines = strings(size(numericData,1),1);
        for iRow = 1:size(numericData,1)
            rowValues = compose("%.6g",numericData(iRow,:));
            lines(iRow) = "[" + strjoin(rowValues,"  ") + "]";
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

%% Apply immediately to both v5 liquid loops.
            [bottomFlowSourceBlock,topFlowSourceBlock] = ...
                findDualFlowRateSourceBlocks(mdl);

            if strlength(bottomFlowSourceBlock) > 0
                applyFlowSourceSettingsToBlockNamed( ...
                    bottomFlowSourceBlock,state, ...
                    "mdot_coolant_bottom","qdot_coolant_bottom");
            end
            if strlength(topFlowSourceBlock) > 0
                applyFlowSourceSettingsToBlockNamed( ...
                    topFlowSourceBlock,state, ...
                    "mdot_coolant_top","qdot_coolant_top");
            end
            if getSimulinkBlockHandle(serpentineFlowSourceBlock) > 0
                applyFlowSourceSettingsToBlockNamed( ...
                    serpentineFlowSourceBlock,state, ...
                    "mdot_coolant_serpentine","qdot_coolant_serpentine");
            end

            for kSide = 1:numel(sideBoundaryNames)
                applyFlowSourceSettingsToBlockNamed( ...
                    sideFlowSourceBlocks(kSide),state, ...
                    "mdot_coolant_" + sideBoundaryNames(kSide), ...
                    "qdot_coolant_" + sideBoundaryNames(kSide));
            end

            save_system(mdl);

            refreshFlowAccountingUI();
            statusLabel.Text = thermalPackFormatText( ...
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
            thermalLiquidBlocks = findThermalLiquidPropertiesBlocks(mdl);
            for kTL = 1:numel(thermalLiquidBlocks)
                applyCoolantPropertiesToBlock(thermalLiquidBlocks(kTL),state);
            end
            if ~isempty(thermalLiquidBlocks)
                save_system(mdl);
            end

            statusLabel.Text = thermalPackFormatText( ...
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

            statusLabel.Text = thermalPackFormatText( ...
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

    function portName = resolveBatterySurfacePort(hBattery,surfaceName)
        portName = "";
        info = simscape.connectionPortProperties(hBattery);
        names = strings(1,numel(info));
        for kInfo = 1:numel(info)
            names(kInfo) = string(info(kInfo).Name);
        end

        if surfaceName == "Top"
            candidates = ["TopExtClnt","CPT"];
        else
            candidates = ["BottomExtClnt","CPB"];
        end

        for kCandidate = 1:numel(candidates)
            if any(names == candidates(kCandidate))
                portName = candidates(kCandidate);
                return;
            end
        end
    end

    function tf = isSerpentineCompatibleConfiguration()
        tf = string(formatField.Value) == "Cylindrical" && ...
            string(topologyField.Value) == "Hexagonal";
    end

    function restoreNonSerpentineCoolingSelection()
        coolingPlateField.Value = state.LastNonSerpentineCoolingMode;
        state.CoolingPlateMode = state.LastNonSerpentineCoolingMode;
        state.CoolingPlateType = state.LastNonSerpentineCoolingPlateType;
        coolingPlateTypeField.Value = state.CoolingPlateType;
        coolingPlateTypeField.Enable = "on";
        serpentineSettingsButton.Enable = "off";
        sideSettingsButton.Enable = "off";
        forcedAirSettingsButton.Enable = "off";
        moduleStackingAxisField.Enable = "on";
        if state.CoolingPlateMode == "No Cooling Plate" || ...
                state.CoolingPlateMode == "Side Cooling" || ...
                state.CoolingPlateMode == "Forced Air Cooling"
            coolantRField.Enable = "off";
        else
            coolantRField.Enable = "on";
        end

        if state.CoolingPlateMode == "Forced Air Cooling"
            forcedAirSettingsButton.Enable = "on";
            ambientField.Enable = "off";
            ambientRField.Enable = "off";
        else
            forcedAirSettingsButton.Enable = "off";
            ambientField.Enable = "on";
            ambientRField.Enable = "on";
        end

        refreshFlowAccountingUI();
    end

    function cloneWorkingBlock(sourceBlock,destinationBlock,offsetY)
        if getSimulinkBlockHandle(destinationBlock) > 0
            return;
        end
        if getSimulinkBlockHandle(sourceBlock) <= 0
            error("ThermalPack:SerpentineTemplateMissing", ...
                "Could not find template block '%s'.",sourceBlock);
        end

        add_block(char(sourceBlock),char(destinationBlock), ...
            "MakeNameUnique","off");

        try
            position = get_param(sourceBlock,"Position");
            position = position + [0 offsetY 0 offsetY];
            set_param(destinationBlock,"Position",position);
        catch
        end
    end

    function ensureSimplePhysicalConnection(block1,port1,block2,port2,roleText)
        if strlength(port1) == 0 || strlength(port2) == 0
            error("ThermalPack:SerpentinePortResolution", ...
                "Could not resolve ports for %s.",roleText);
        end

        c1 = getPhysicalPortConnections(block1,port1);
        c2 = getPhysicalPortConnections(block2,port2);

        % Fresh branch: both ports are free. Existing branch: both ports are
        % already connected. If only one side is connected, addConnection
        % intentionally creates/restores the required conserving branch.
        if ~isempty(c1) && ~isempty(c2)
            return;
        end

        try
            simscape.addConnection( ...
                block1,port1,block2,port2,"autorouting","smart");
        catch MEadd
            c1 = getPhysicalPortConnections(block1,port1);
            c2 = getPhysicalPortConnections(block2,port2);
            if isempty(c1) || isempty(c2)
                msg = thermalPackFormatText( ...
                    "Could not create serpentine connection '%s'.\n%s", ...
                    roleText,MEadd.message);
                error("ThermalPack:SerpentineConnection",char(msg));
            end
        end
    end

    function removeSerpentineCoolingBranch()
        % Delete only App-created blocks in the working model. The v5 master
        % is never modified. delete_block also removes their physical lines.
        branchBlocks = [ ...
            serpentineIsolationBlock, ...
            serpentinePlateBlock, ...
            serpentineFlowSourceBlock, ...
            serpentineInletReservoirBlock, ...
            serpentineOutletReservoirBlock, ...
            serpentineTLPropertiesBlock];

        for kBlock = 1:numel(branchBlocks)
            if getSimulinkBlockHandle(branchBlocks(kBlock)) > 0
                try
                    delete_block(branchBlocks(kBlock));
                catch
                end
            end
        end

        state.SerpentineBranchCreated = false;
        state.HasSerpentinePort = false;
    end

    function ensureSerpentineCoolingBranch(numNodes,nodeDimensions,nodeLocations)
        % Create a complete THIRD coolant branch in Thermal_Model_v5_UI:
        % SP -> Serpentine Isolation -> Serpentine Parallel Channels
        % TL circuit: Inlet Reservoir -> Flow Source -> Plate -> Outlet Reservoir
        % plus a dedicated Thermal Liquid Properties block at the inlet node.
        if nargin < 1 || isempty(numNodes) || ~isfinite(numNodes) || numNodes < 1
            error("ThermalPack:SerpentineNodeCount", ...
                "A valid SP thermal-node count is required.");
        end
        numNodes = round(numNodes);

        hBattery = getSimulinkBlockHandle(char(batteryBlock),true);
        if isempty(hBattery) || hBattery <= 0
            error("ThermalPack:SerpentineBatteryMissing", ...
                "Could not resolve the rebuilt battery block.");
        end

        info = simscape.connectionPortProperties(hBattery);
        portNames = strings(1,numel(info));
        for kInfo = 1:numel(info)
            portNames(kInfo) = string(info(kInfo).Name);
        end
        if ~any(portNames == "SP")
            error("ThermalPack:SerpentinePortMissing", ...
                "The rebuilt battery does not expose SP. Serpentine Cooling requires a Cylindrical / Hexagonal rebuild.");
        end

        % Templates are copied from the proven bottom-cooling v4 circuit.
        [bottomFlowTemplate,~] = findDualFlowRateSourceBlocks(mdl);
        bottomInletTemplate = bottomInletReservoirBlock;
        bottomOutletTemplate = bottomOutletReservoirBlock;
        bottomPropertiesTemplate = ...
            bottomCoolingSubsystem + "/Thermal Liquid" + newline + ...
            "Properties (TL)";

        if strlength(bottomFlowTemplate) == 0 || ...
                getSimulinkBlockHandle(bottomInletTemplate) <= 0 || ...
                getSimulinkBlockHandle(bottomOutletTemplate) <= 0 || ...
                getSimulinkBlockHandle(bottomPropertiesTemplate) <= 0
            error("ThermalPack:SerpentineTLTemplateMissing", ...
                "The complete bottom Thermal Liquid template circuit was not found.");
        end

        % Create the six dedicated blocks. Offsetting them below the existing
        % v4 lower loop keeps the generated working model readable.
        cloneWorkingBlock(bottomIsolationBlock,serpentineIsolationBlock,210);
        cloneWorkingBlock(bottomPlateBlock,serpentinePlateBlock,250);
        cloneWorkingBlock(bottomFlowTemplate,serpentineFlowSourceBlock,250);
        cloneWorkingBlock(bottomInletTemplate,serpentineInletReservoirBlock,250);
        cloneWorkingBlock(bottomOutletTemplate,serpentineOutletReservoirBlock,250);
        cloneWorkingBlock(bottomPropertiesTemplate,serpentineTLPropertiesBlock,250);

        % The serpentine interface is documented against Parallel Channels.
        % If the bottom template currently uses another architecture, replace
        % only the newly created serpentine plate with Parallel Channels.
        parallelSource = coolingPlateLibraryPath("Parallel Channels");
        hSerpPlate = getSimulinkBlockHandle(char(serpentinePlateBlock),true);
        currentSource = "";
        try
            currentSource = string(get_param(serpentinePlateBlock,"ReferenceBlock"));
        catch
            try
                currentSource = string(get_param(serpentinePlateBlock,"SourceBlock"));
            catch
            end
        end
        if currentSource ~= parallelSource
            oldPosition = get_param(serpentinePlateBlock,"Position");
            delete_block(serpentinePlateBlock);
            add_block(char(parallelSource),char(serpentinePlateBlock), ...
                "MakeNameUnique","off","Position",oldPosition);
            hSerpPlate = getSimulinkBlockHandle(char(serpentinePlateBlock),true);
        end

        hIso = getSimulinkBlockHandle(char(serpentineIsolationBlock),true);
        hFlow = getSimulinkBlockHandle(char(serpentineFlowSourceBlock),true);
        hInlet = getSimulinkBlockHandle(char(serpentineInletReservoirBlock),true);
        hOutlet = getSimulinkBlockHandle(char(serpentineOutletReservoirBlock),true);
        hProperties = getSimulinkBlockHandle(char(serpentineTLPropertiesBlock),true);

        if any([hIso hSerpPlate hFlow hInlet hOutlet hProperties] <= 0)
            error("ThermalPack:SerpentineBranchCreation", ...
                "One or more serpentine working-model blocks could not be created.");
        end

        set_param(serpentineIsolationBlock,"N",num2str(numNodes));

        % Battery Builder SP mapping is passed unchanged to the dedicated plate.
        safeSetBlockParam(serpentinePlateBlock,"numBattThermalNodes1", ...
            num2str(numNodes));
        safeSetBlockParam(serpentinePlateBlock,"dimensionThermalNodes1", ...
            mat2str(nodeDimensions,16));
        safeSetBlockParam(serpentinePlateBlock,"locationThermalNodes1", ...
            mat2str(nodeLocations,16));

        serpPlateState = state;
        serpPlateState.CoolingPlateType = "Parallel Channels";
        applyCoolingPlateSettingsToBlock(serpentinePlateBlock,serpPlateState);
        applyCoolantPropertiesToBlock(serpentineTLPropertiesBlock,state);
        applyFlowSourceSettingsToBlockNamed( ...
            serpentineFlowSourceBlock,state, ...
            "mdot_coolant_serpentine","qdot_coolant_serpentine");
        safeSetBlockParamByPrompt(serpentineFlowSourceBlock, ...
            "Cross-sectional area at ports A and B", ...
            "Area_coolant_serpentine_port_in_m2");

        % Configure the dedicated reservoirs to use serpentine variables.
        safeSetBlockParam(serpentineInletReservoirBlock,"pressure_input","false");
        safeSetBlockParam(serpentineInletReservoirBlock,"temperature_input","false");
        safeSetBlockParam(serpentineInletReservoirBlock,"reservoir_temperature", ...
            "T_coolant_serpentine_in_K");
        safeSetBlockParam(serpentineInletReservoirBlock,"area", ...
            "Area_coolant_serpentine_port_in_m2");
        safeSetBlockParam(serpentineOutletReservoirBlock,"area", ...
            "Area_coolant_serpentine_port_in_m2");

        % Give the new working-model branch valid defaults before compilation.
        try
            mdlWks = get_param(mdl,"ModelWorkspace");
            assignin(mdlWks,"mdot_coolant_serpentine",state.MassFlowRate_kg_s);
            assignin(mdlWks,"qdot_coolant_serpentine",state.VolumetricFlowRate_m3_s);
            assignin(mdlWks,"T_coolant_serpentine_in_K",tinField.Value + 273.15);
            assignin(mdlWks,"Area_coolant_serpentine_port_in_m2", ...
                state.CoolantPortArea_m2);
        catch
        end

        % Resolve physical port names from the actual installed blocks.
        isoA = resolveConnectionPortByCandidates(hIso,["A"]);
        isoB = resolveConnectionPortByCandidates(hIso,["B"]);
        plateSurface = resolveCoolingPlatePortByRole(hSerpPlate,"surface1");
        plateIn = resolveCoolingPlatePortByRole(hSerpPlate,"fluid_in");
        plateOut = resolveCoolingPlatePortByRole(hSerpPlate,"fluid_out");
        flowA = resolveConnectionPortByCandidates(hFlow,["A","fluid_in"]);
        flowB = resolveConnectionPortByCandidates(hFlow,["B","fluid_out"]);
        inletPort = resolveConnectionPortByCandidates(hInlet,["A","fluid_in"]);
        outletPort = resolveConnectionPortByCandidates(hOutlet,["A","fluid_in"]);
        propertiesPort = resolveConnectionPortByCandidates(hProperties,["R","A"]);

        ensureSimplePhysicalConnection( ...
            hBattery,"SP",hIso,isoA,"SP to serpentine isolation");
        ensureSimplePhysicalConnection( ...
            hIso,isoB,hSerpPlate,plateSurface, ...
            "serpentine isolation to plate");

        % Thermal Liquid loop. The properties block shares the inlet node.
        ensureSimplePhysicalConnection( ...
            hProperties,propertiesPort,hInlet,inletPort, ...
            "serpentine TL properties to inlet node");
        ensureSimplePhysicalConnection( ...
            hInlet,inletPort,hFlow,flowA, ...
            "serpentine inlet reservoir to flow source");
        ensureSimplePhysicalConnection( ...
            hFlow,flowB,hSerpPlate,plateIn, ...
            "serpentine flow source to plate inlet");
        ensureSimplePhysicalConnection( ...
            hSerpPlate,plateOut,hOutlet,outletPort, ...
            "serpentine plate outlet to reservoir");

        verifyCoolingPlateCoreConnections(serpentinePlateBlock);
        state.HasSerpentinePort = true;
        state.SerpentineBranchCreated = true;
    end

    function [thermalNodes,boundaryCells] = sideThermalNodeData(moduleObj,boundaryName)
        boundaryName = string(boundaryName);
        if boundaryName == "Xmin"
            thermalNodes = moduleObj.ThermalNodes.Xmin;
            boundaryCells = moduleObj.CellsAtXminBoundary;
        elseif boundaryName == "Xmax"
            thermalNodes = moduleObj.ThermalNodes.Xmax;
            boundaryCells = moduleObj.CellsAtXmaxBoundary;
        elseif boundaryName == "Ymin"
            thermalNodes = moduleObj.ThermalNodes.Ymin;
            boundaryCells = moduleObj.CellsAtYminBoundary;
        elseif boundaryName == "Ymax"
            thermalNodes = moduleObj.ThermalNodes.Ymax;
            boundaryCells = moduleObj.CellsAtYmaxBoundary;
        else
            error("ThermalPack:SideBoundary", ...
                "Unsupported side boundary '%s'.",boundaryName);
        end
    end

    function [topRth,bottomRth,serpentineRth,sideRths] = resolveCoolingIsolationRth()
        mode = string(coolingPlateField.Value);
        Ron = state.CoolingSwitchOnRth_K_W;
        Roff = state.NoCoolingRth_K_W;

        topRth = Roff;
        bottomRth = Roff;
        serpentineRth = Roff;
        sideRths = repmat(Roff,1,numel(sideBoundaryNames));

        if mode == "Top Cooling Plate"
            topRth = Ron;
        elseif mode == "Bottom Cooling Plate"
            bottomRth = Ron;
        elseif mode == "Top + Bottom Cooling"
            topRth = Ron;
            bottomRth = Ron;
        elseif mode == "Serpentine Cooling"
            serpentineRth = Ron;
        elseif mode == "Side Cooling"
            idx = find(sideBoundaryNames == state.SideBoundary,1);
            if isempty(idx)
                error("ThermalPack:SideBoundary", ...
                    "Unsupported side boundary '%s'.",state.SideBoundary);
            end
            sideRths(idx) = Ron;
        end
    end

    function connected = getPhysicalPortConnections(blockHandle,portName)
        try
            connected = simscape.connectedPorts(blockHandle,portName);
        catch
            connected = [];
        end
    end

    function tf = isPhysicalPortConnected(blockHandle,portName)
        tf = ~isempty(getPhysicalPortConnections(blockHandle,portName));
    end

    function configureExistingCoolingIsolationBlocks(numNodes,sideNodeCounts)
        if nargin < 1 || isempty(numNodes) || ~isfinite(numNodes)
            numNodes = state.TotalCells;
        end
        numNodes = max(1,round(numNodes));

        if nargin < 2 || isempty(sideNodeCounts)
            sideNodeCounts = nan(1,numel(sideBoundaryNames));
        end

        if getSimulinkBlockHandle(topIsolationBlock) <= 0 || ...
                getSimulinkBlockHandle(bottomIsolationBlock) <= 0
            error("ThermalPack:CoolingIsolationMissing", ...
                "Thermal_Model_v5 must contain the permanent Top and Bottom Cooling Isolation blocks.");
        end

        set_param(topIsolationBlock,"N",num2str(numNodes));
        set_param(bottomIsolationBlock,"N",num2str(numNodes));

        for kSide = 1:numel(sideBoundaryNames)
            if getSimulinkBlockHandle(sideIsolationBlocks(kSide)) <= 0
                error("ThermalPack:SideCoolingIsolationMissing", ...
                    "Missing permanent %s Cooling Isolation block.", ...
                    sideBoundaryNames(kSide));
            end

            nSide = sideNodeCounts(kSide);
            if isfinite(nSide) && nSide >= 1
                set_param(sideIsolationBlocks(kSide),"N", ...
                    num2str(round(nSide)));
            end
        end
    end

    function applyCoolingArchitectureResistance()
        if getSimulinkBlockHandle(topIsolationBlock) <= 0 || ...
                getSimulinkBlockHandle(bottomIsolationBlock) <= 0
            error("ThermalPack:CoolingIsolationMissing", ...
                "Top and Bottom Cooling Isolation blocks must exist in Thermal_Model_v5.");
        end

        [topRth,bottomRth,serpentineRth,sideRths] = ...
            resolveCoolingIsolationRth();

        set_param(topIsolationBlock,"R",num2str(topRth,16));
        set_param(bottomIsolationBlock,"R",num2str(bottomRth,16));

        if getSimulinkBlockHandle(serpentineIsolationBlock) > 0
            set_param(serpentineIsolationBlock,"R", ...
                num2str(serpentineRth,16));
        elseif string(coolingPlateField.Value) == "Serpentine Cooling"
            if ~state.NeedsRebuild
                error("ThermalPack:SerpentineBranchMissing", ...
                    "Serpentine Cooling requires REBUILD BATTERY to generate SP.");
            end
        end

        for kSide = 1:numel(sideBoundaryNames)
            if getSimulinkBlockHandle(sideIsolationBlocks(kSide)) <= 0
                error("ThermalPack:SideCoolingIsolationMissing", ...
                    "Permanent %s Cooling Isolation block is missing from Thermal_Model_v5.", ...
                    sideBoundaryNames(kSide));
            end
            set_param(sideIsolationBlocks(kSide),"R", ...
                num2str(sideRths(kSide),16));
        end

        try
            save_system(mdl);
        catch
        end
    end

    function [topFlow,bottomFlow,serpentineFlow,sideFlow,totalFlow] = resolveCoolingFlows(mainFlowValue)
        mode = string(coolingPlateField.Value);
        topFlow = 0;
        bottomFlow = 0;
        serpentineFlow = 0;
        sideFlow = 0;

        if mode == "Top Cooling Plate"
            topFlow = mainFlowValue;
        elseif mode == "Bottom Cooling Plate"
            bottomFlow = mainFlowValue;
        elseif mode == "Serpentine Cooling"
            serpentineFlow = mainFlowValue;
        elseif mode == "Side Cooling"
            sideFlow = mainFlowValue;
        elseif mode == "Top + Bottom Cooling"
            if state.FlowAllocationMode == "Independent Flow"
                topFlow = topFlowField.Value;
                bottomFlow = bottomFlowField.Value;
            else
                topFraction = topSplitField.Value/100;
                topFlow = mainFlowValue*topFraction;
                bottomFlow = mainFlowValue*(1-topFraction);
            end
        end

        totalFlow = topFlow + bottomFlow + serpentineFlow + sideFlow;
    end

    function refreshFlowAccountingUI()
        mode = string(coolingPlateField.Value);
        dualMode = mode == "Top + Bottom Cooling";
        noCooling = mode == "No Cooling Plate" || ...
            mode == "Forced Air Cooling";

        if state.FlowRateType == "Volumetric flow rate"
            unitText = "m³/s";
            storedTopFlow = state.TopVolumetricFlowRate_m3_s;
            storedBottomFlow = state.BottomVolumetricFlowRate_m3_s;
        else
            unitText = "kg/s";
            storedTopFlow = state.TopMassFlowRate_kg_s;
            storedBottomFlow = state.BottomMassFlowRate_kg_s;
        end

        topFlowLabel.Text = "Top flow (" + unitText + ")";
        bottomFlowLabel.Text = "Bottom flow (" + unitText + ")";

        if noCooling
            flowAllocationField.Enable = "off";
            flowField.Enable = "off";
            topSplitField.Enable = "off";
            topFlowField.Enable = "off";
            bottomFlowField.Enable = "off";
            topFlowField.Value = 0;
            bottomFlowField.Value = 0;
            flowLabel.Text = "Coolant flow (" + unitText + ")";
            return;
        end

        if ~dualMode
            flowAllocationField.Enable = "off";
            topSplitField.Enable = "off";
            topFlowField.Enable = "off";
            bottomFlowField.Enable = "off";
            flowField.Enable = "on";
            if mode == "Serpentine Cooling"
                flowLabel.Text = "Serpentine flow (" + unitText + ")";
            elseif mode == "Side Cooling"
                flowLabel.Text = "Side coolant flow (" + unitText + ")";
            else
                flowLabel.Text = "Coolant flow (" + unitText + ")";
            end

            [topValue,bottomValue,~,~,~] = resolveCoolingFlows(flowField.Value);
            topFlowField.Value = topValue;
            bottomFlowField.Value = bottomValue;
            return;
        end

        flowAllocationField.Enable = "on";
        flowLabel.Text = "Total coolant flow (" + unitText + ")";

        if state.FlowAllocationMode == "Total Flow"
            flowField.Enable = "on";
            topSplitField.Enable = "on";
            topFlowField.Enable = "off";
            bottomFlowField.Enable = "off";

            [topValue,bottomValue,~,~,~] = resolveCoolingFlows(flowField.Value);
            topFlowField.Value = topValue;
            bottomFlowField.Value = bottomValue;
        else
            flowField.Enable = "off";
            topSplitField.Enable = "off";
            topFlowField.Enable = "on";
            bottomFlowField.Enable = "on";
            topFlowField.Value = storedTopFlow;
            bottomFlowField.Value = storedBottomFlow;
            flowField.Value = topFlowField.Value + bottomFlowField.Value;
        end
    end

    function mainFlowChanged(~,~)
        if state.FlowRateType == "Mass flow rate"
            state.MassFlowRate_kg_s = flowField.Value;
        else
            state.VolumetricFlowRate_m3_s = flowField.Value;
        end
        refreshFlowAccountingUI();
    end

    function flowAllocationChanged(~,~)
        state.FlowAllocationMode = string(flowAllocationField.Value);
        refreshFlowAccountingUI();
    end

    function topFlowShareChanged(~,~)
        state.TopFlowShare_pct = topSplitField.Value;
        refreshFlowAccountingUI();
    end

    function independentFlowChanged(~,~)
        if state.FlowRateType == "Mass flow rate"
            state.TopMassFlowRate_kg_s = topFlowField.Value;
            state.BottomMassFlowRate_kg_s = bottomFlowField.Value;
        else
            state.TopVolumetricFlowRate_m3_s = topFlowField.Value;
            state.BottomVolumetricFlowRate_m3_s = bottomFlowField.Value;
        end
        refreshFlowAccountingUI();
    end

    function key = normalizeCoolingPlateLibraryName(value)
        key = lower(string(value));
        key = replace(key,newline," ");
        key = regexprep(key,"[^a-z0-9]","");
    end

    function tf = coolingPlateNameMatches(blockName,plateType)
        key = normalizeCoolingPlateLibraryName(blockName);
        plateType = string(plateType);

        if plateType == "U-Shaped Channels"
            tf = (contains(key,"ushaped") && contains(key,"channel"));
        elseif plateType == "Edge Cooling"
            tf = (contains(key,"edge") && contains(key,"cool"));
        else
            tf = (contains(key,"parallel") && contains(key,"channel"));
        end
    end

    function score = coolingPlateCandidateScore(blockPath,plateType)
        % Lower score = better candidate.
        blockPath = string(blockPath);
        score = 1000;

        try
            blockName = string(get_param(blockPath,"Name"));
        catch
            blockName = "";
        end

        normalizedName = normalizeCoolingPlateLibraryName(blockName);

        if plateType == "U-Shaped Channels"
            exactKeys = ["ushapedchannels","ushapedchannel"];
        elseif plateType == "Edge Cooling"
            exactKeys = ["edgecooling","edgecoolingplate"];
        else
            exactKeys = ["parallelchannels","parallelchannel"];
        end

        if any(normalizedName == exactKeys)
            score = score - 500;
        end

        if startsWith(blockPath,"batt_lib/Thermal/")
            score = score - 300;
        elseif contains(blockPath,"/Thermal/")
            score = score - 200;
        end

        % Prefer a shallower library block over an internal child block.
        depth = count(blockPath,"/");
        score = score + 10*depth;

        % A library-linked/masked top-level block is generally a better
        % candidate than an ordinary internal implementation block.
        try
            maskType = string(get_param(blockPath,"MaskType"));
            if strlength(maskType) > 0
                score = score - 25;
            end
        catch
        end
    end

    function sourcePath = coolingPlateLibraryPath(plateType)
        % Resolve the ACTUAL installed Simscape Battery cooling-plate block.
        % Do not assume that documentation capitalization/hierarchy exactly
        % matches the installed Library Browser path.

        plateType = string(plateType);
        sourcePath = "";

        try
            load_system("batt_lib");
        catch MEload
            msg = thermalPackFormatText( ...
                "Could not load the Simscape Battery library batt_lib.\n%s", ...
                MEload.message);
            error("ThermalPack:CoolingPlateLibraryLoad",char(msg));
        end

        if plateType == "U-Shaped Channels"
            preferredNames = [ ...
                "U-shaped Channels", ...
                "U-Shaped Channels", ...
                "U shaped Channels", ...
                "U-Shaped Channel"];
        elseif plateType == "Edge Cooling"
            preferredNames = [ ...
                "Edge Cooling", ...
                "Edge Cooling Plate"];
        else
            preferredNames = [ ...
                "Parallel Channels", ...
                "Parallel Channel"];
        end

        % Fast path: try likely locations/names first.
        likelyParents = [ ...
            "batt_lib/Thermal/", ...
            "batt_lib/"];

        for kParent = 1:numel(likelyParents)
            for kName = 1:numel(preferredNames)
                candidate = likelyParents(kParent) + preferredNames(kName);

                try
                    hCandidate = ...
                        getSimulinkBlockHandle(char(candidate),true);
                catch
                    hCandidate = -1;
                end

                if ~isempty(hCandidate) && hCandidate > 0
                    sourcePath = candidate;
                    return;
                end
            end
        end

        % Robust fallback: recursively inspect the installed battery
        % library and use semantic matching instead of exact capitalization.
        try
            libraryBlocks = string(find_system( ...
                "batt_lib", ...
                "LookUnderMasks","all", ...
                "FollowLinks","on", ...
                "Type","Block"));
        catch MEfind
            msg = thermalPackFormatText( ...
                "Could not inspect the Simscape Battery library.\n%s", ...
                MEfind.message);
            error("ThermalPack:CoolingPlateLibrarySearch",char(msg));
        end

        matches = strings(0,1);
        scores = zeros(0,1);

        for kBlock = 1:numel(libraryBlocks)
            blockPath = libraryBlocks(kBlock);

            try
                blockName = string(get_param(blockPath,"Name"));
            catch
                continue;
            end

            if coolingPlateNameMatches(blockName,plateType)
                matches(end+1,1) = blockPath; %#ok<AGROW>
                scores(end+1,1) = ...
                    coolingPlateCandidateScore(blockPath,plateType); %#ok<AGROW>
            end
        end

        if ~isempty(matches)
            [~,order] = sort(scores,"ascend");
            matches = matches(order);

            % Confirm the selected candidate resolves to a valid block.
            for kMatch = 1:numel(matches)
                try
                    hMatch = ...
                        getSimulinkBlockHandle(char(matches(kMatch)),true);
                catch
                    hMatch = -1;
                end

                if ~isempty(hMatch) && hMatch > 0
                    sourcePath = matches(kMatch);
                    return;
                end
            end
        end

        % If nothing matched, expose the real library contents in the
        % diagnostic instead of throwing a second error while formatting it.
        nearby = strings(0,1);

        for kBlock = 1:numel(libraryBlocks)
            blockPath = libraryBlocks(kBlock);

            try
                blockName = string(get_param(blockPath,"Name"));
            catch
                continue;
            end

            blockNameLower = lower(replace(blockName,newline," "));

            if contains(blockNameLower,"channel") || ...
                    contains(blockNameLower,"cooling") || ...
                    contains(blockNameLower,"plate")
                nearby(end+1,1) = blockPath; %#ok<AGROW>
            end
        end

        nearby = unique(nearby,"stable");

        if numel(nearby) > 20
            nearby = nearby(1:20);
        end

        if isempty(nearby)
            nearbyText = "(no similarly named blocks found)";
        else
            nearbyText = strjoin(nearby,newline);
        end

        msg = thermalPackFormatText( ...
            "Could not find the installed Simscape Battery block for '%s'.\nCandidate cooling/channel blocks found in batt_lib:\n%s", ...
            plateType,nearbyText);

        error("ThermalPack:CoolingPlateLibraryBlockMissing",char(msg));
    end

    function portName = resolveCoolingPlatePortByRole(blockHandle,role)
        portName = "";

        info = simscape.connectionPortProperties(blockHandle);
        names = strings(1,numel(info));

        for kInfo = 1:numel(info)
            names(kInfo) = string(info(kInfo).Name);
        end

        role = string(role);

        if role == "surface1"
            candidates = ["Side1","Surf1"];
        elseif role == "surface2"
            candidates = ["Side2","Surf2"];
        elseif role == "fluid_in"
            candidates = ["fluid_in","Fluid_In"];
        elseif role == "fluid_out"
            candidates = ["fluid_out","Fluid_Out"];
        elseif role == "plate_temperature"
            candidates = ["plotPlateT","Tp"];
        elseif role == "fluid_temperature_change"
            candidates = ["tempSensor","dT"];
        elseif role == "pressure_drop"
            candidates = ["presSensor","dP"];
        else
            candidates = role;
        end

        % Exact match first.
        for kCandidate = 1:numel(candidates)
            if any(names == candidates(kCandidate))
                portName = candidates(kCandidate);
                return;
            end
        end

        % Case/format-insensitive fallback.
        normalizedNames = lower(regexprep(names,"[^A-Za-z0-9]",""));
        for kCandidate = 1:numel(candidates)
            candidateKey = lower(regexprep(candidates(kCandidate), ...
                "[^A-Za-z0-9]",""));

            idx = find(normalizedNames == candidateKey,1,"first");
            if ~isempty(idx)
                portName = names(idx);
                return;
            end
        end
    end

    function saved = captureCoolingPlateConnections(blockHandle)
        roles = [ ...
            "fluid_in", ...
            "fluid_out", ...
            "surface1", ...
            "surface2", ...
            "plate_temperature", ...
            "fluid_temperature_change", ...
            "pressure_drop"];

        saved = struct( ...
            "Role",cell(1,numel(roles)), ...
            "PortName",cell(1,numel(roles)), ...
            "Connected",cell(1,numel(roles)));

        for kRole = 1:numel(roles)
            role = roles(kRole);
            portName = resolveCoolingPlatePortByRole(blockHandle,role);

            saved(kRole).Role = role;
            saved(kRole).PortName = portName;
            saved(kRole).Connected = [];

            if strlength(portName) == 0
                continue;
            end

            try
                connected = simscape.connectedPorts(blockHandle,portName);
            catch
                connected = [];
            end

            saved(kRole).Connected = connected;
        end
    end

    function detachCapturedCoolingPlateConnections(blockHandle,saved)
        detachedPortNames = strings(0,1);

        for kSaved = 1:numel(saved)
            portName = string(saved(kSaved).PortName);
            connected = saved(kSaved).Connected;

            if strlength(portName) == 0 || isempty(connected)
                continue;
            end

            if any(detachedPortNames == portName)
                continue;
            end

            try
                currentConnections = ...
                    simscape.connectedPorts(blockHandle,portName);

                if ~isempty(currentConnections)
                    simscape.removeConnection(blockHandle,portName);
                end

                detachedPortNames(end+1,1) = portName; %#ok<AGROW>
            catch
                % Replacement may still preserve/recreate a connection.
                % restoreCapturedCoolingPlateConnections checks the final
                % state before attempting any addConnection call.
            end
        end
    end

    function tf = connectionListContainsAnyEndpoint(current,savedEndpoints)
        tf = false;

        if isempty(current) || isempty(savedEndpoints)
            return;
        end

        for kCurrent = 1:numel(current)
            for kSaved = 1:numel(savedEndpoints)
                sameBlock = false;
                samePort = false;

                try
                    sameBlock = isequal( ...
                        current(kCurrent).Block, ...
                        savedEndpoints(kSaved).Block);
                catch
                    try
                        sameBlock = ...
                            string(current(kCurrent).Block) == ...
                            string(savedEndpoints(kSaved).Block);
                    catch
                    end
                end

                try
                    samePort = ...
                        string(current(kCurrent).PortName) == ...
                        string(savedEndpoints(kSaved).PortName);
                catch
                end

                if sameBlock && samePort
                    tf = true;
                    return;
                end
            end
        end
    end

    function restoreCapturedCoolingPlateConnections(blockHandle,saved)
        for kSaved = 1:numel(saved)
            savedEndpoints = saved(kSaved).Connected;

            if isempty(savedEndpoints)
                continue;
            end

            role = string(saved(kSaved).Role);
            newPortName = ...
                resolveCoolingPlatePortByRole(blockHandle,role);

            if strlength(newPortName) == 0
                msg = thermalPackFormatText( ...
                    "The new cooling plate has no compatible port for role '%s'.", ...
                    role);
                error("ThermalPack:CoolingPlatePortMapping",char(msg));
            end

            % Some Simulink/Simscape block replacements automatically
            % preserve a physical connection even after the explicit
            % detach step. Therefore reconnection must be idempotent:
            % if the new port is already connected to the original branch,
            % leave it alone instead of calling addConnection again.
            try
                currentConnections = ...
                    simscape.connectedPorts(blockHandle,newPortName);
            catch
                currentConnections = [];
            end

            if ~isempty(currentConnections)
                if connectionListContainsAnyEndpoint( ...
                        currentConnections,savedEndpoints)
                    continue;
                end

                msg = thermalPackFormatText( ...
                    ["Cooling plate interface '%s' (port '%s') is already " ...
                     "connected, but not to the branch captured before the " ...
                     "architecture swap. ThermalPack will not overwrite an " ...
                     "unexpected physical connection."], ...
                    role,newPortName);

                error("ThermalPack:CoolingPlateUnexpectedConnection",char(msg));
            end

            % The saved endpoint belongs to the original external branch.
            % Reconnecting to one member restores the new cooling-plate port
            % to the same physical network.
            previous = savedEndpoints(1);

            simscape.addConnection( ...
                blockHandle,newPortName, ...
                previous.Block,previous.PortName, ...
                "autorouting","smart");
        end
    end

    function portName = resolveConnectionPortByCandidates( ...
            blockHandle,candidates)
        portName = "";

        info = simscape.connectionPortProperties(blockHandle);
        names = strings(1,numel(info));

        for kInfo = 1:numel(info)
            names(kInfo) = string(info(kInfo).Name);
        end

        for kCandidate = 1:numel(candidates)
            if any(names == candidates(kCandidate))
                portName = candidates(kCandidate);
                return;
            end
        end

        normalizedNames = lower(regexprep(names,"[^A-Za-z0-9]",""));

        for kCandidate = 1:numel(candidates)
            candidateKey = lower(regexprep( ...
                candidates(kCandidate),"[^A-Za-z0-9]",""));

            idx = find(normalizedNames == candidateKey,1,"first");
            if ~isempty(idx)
                portName = names(idx);
                return;
            end
        end
    end

    function ensurePlatePortConnectedToPeer( ...
            plateHandle,platePort,peerHandle,peerPort,roleText)
        if strlength(platePort) == 0 || strlength(peerPort) == 0
            msg = thermalPackFormatText( ...
                "Could not resolve ports required for cooling-loop role '%s'.", ...
                roleText);
            error("ThermalPack:CoolingLoopPortResolution",char(msg));
        end

        current = simscape.connectedPorts(plateHandle,platePort);

        if ~isempty(current)
            return;
        end

        try
            simscape.addConnection( ...
                plateHandle,platePort, ...
                peerHandle,peerPort, ...
                "autorouting","smart");
        catch MEadd
            % Some physical branches can be reconstituted by Simulink
            % during replacement. Check the final state before failing.
            current = simscape.connectedPorts(plateHandle,platePort);

            if isempty(current)
                msg = thermalPackFormatText( ...
                    "Could not restore cooling-loop role '%s'.\n%s", ...
                    roleText,MEadd.message);
                error("ThermalPack:CoolingLoopReconnect",char(msg));
            end
        end
    end

    function repairCoolingPlateFluidConnections(blockPath,surfaceName)
        hPlate = getSimulinkBlockHandle(char(blockPath),true);

        if isempty(hPlate) || hPlate <= 0
            msg = thermalPackFormatText( ...
                "Cooling plate block '%s' could not be resolved.",blockPath);
            error("ThermalPack:CoolingPlateSwap",char(msg));
        end

        fluidInPort = ...
            resolveCoolingPlatePortByRole(hPlate,"fluid_in");
        fluidOutPort = ...
            resolveCoolingPlatePortByRole(hPlate,"fluid_out");

        [bottomFlowSource,topFlowSource] = ...
            findDualFlowRateSourceBlocks(mdl);

        if surfaceName == "Top"
            flowSourceBlock = topFlowSource;
            outletReservoirBlock = topOutletReservoirBlock;
        else
            flowSourceBlock = bottomFlowSource;
            outletReservoirBlock = bottomOutletReservoirBlock;
        end

        if strlength(flowSourceBlock) == 0
            msg = thermalPackFormatText( ...
                "Could not find the %s Flow Rate Source (TL) block.", ...
                lower(surfaceName));
            error("ThermalPack:FlowSourceMissing",char(msg));
        end

        hFlow = getSimulinkBlockHandle(char(flowSourceBlock),true);
        hReservoir = ...
            getSimulinkBlockHandle(char(outletReservoirBlock),true);

        if isempty(hFlow) || hFlow <= 0 || ...
                isempty(hReservoir) || hReservoir <= 0
            msg = thermalPackFormatText( ...
                "Could not resolve the %s coolant-loop source/reservoir.", ...
                lower(surfaceName));
            error("ThermalPack:CoolingLoopEndpointMissing",char(msg));
        end

        % In Thermal_Model_v5, Flow Rate Source (TL) port B feeds the
        % plate inlet and the downstream Reservoir (TL) port A receives
        % the plate outlet.
        flowOutPort = ...
            resolveConnectionPortByCandidates(hFlow,["B","fluid_out"]);
        reservoirPort = ...
            resolveConnectionPortByCandidates(hReservoir,["A","fluid_in"]);

        ensurePlatePortConnectedToPeer( ...
            hPlate,fluidInPort,hFlow,flowOutPort, ...
            surfaceName + " fluid inlet");

        ensurePlatePortConnectedToPeer( ...
            hPlate,fluidOutPort,hReservoir,reservoirPort, ...
            surfaceName + " fluid outlet");
    end

    function verifyCoolingPlateCoreConnections(blockPath)
        hBlock = getSimulinkBlockHandle(char(blockPath),true);
        if isempty(hBlock) || hBlock <= 0
            msg = thermalPackFormatText( ...
                "Cooling plate block '%s' could not be resolved.",blockPath);
            error("ThermalPack:CoolingPlateSwap",char(msg));
        end

        requiredRoles = ["surface1","fluid_in","fluid_out"];

        for kRole = 1:numel(requiredRoles)
            role = requiredRoles(kRole);
            portName = resolveCoolingPlatePortByRole(hBlock,role);

            if strlength(portName) == 0
                info = simscape.connectionPortProperties(hBlock);
                available = strings(1,numel(info));
                for kInfo = 1:numel(info)
                    available(kInfo) = string(info(kInfo).Name);
                end

                msg = thermalPackFormatText( ...
                    "The selected cooling plate does not expose the required '%s' interface. Available ports: %s", ...
                    role,strjoin(available,", "));
                error("ThermalPack:CoolingPlateInterface",char(msg));
            end

            connected = simscape.connectedPorts(hBlock,portName);
            if isempty(connected)
                msg = thermalPackFormatText( ...
                    "Cooling plate '%s' interface '%s' (port '%s') is disconnected after switching architectures.", ...
                    blockPath,role,portName);
                error("ThermalPack:CoolingPlateConnection",char(msg));
            end
        end
    end

    function replaceCoolingPlateSlot(blockPath,newSource)
        hOld = getSimulinkBlockHandle(char(blockPath),true);
        if isempty(hOld) || hOld <= 0
            msg = thermalPackFormatText( ...
                "Cooling plate slot '%s' was not found.",blockPath);
            error("ThermalPack:CoolingPlateMissing",char(msg));
        end

        oldSource = "";
        try
            oldSource = string(get_param(blockPath,"ReferenceBlock"));
        catch
            try
                oldSource = string(get_param(blockPath,"SourceBlock"));
            catch
            end
        end

        if oldSource == newSource
            return;
        end

        load_system("batt_lib");

        hSource = getSimulinkBlockHandle(char(newSource),true);
        if isempty(hSource) || hSource <= 0
            msg = thermalPackFormatText( ...
                "Resolved cooling plate source '%s' is not a valid block.", ...
                newSource);
            error("ThermalPack:CoolingPlateLibraryBlockInvalid",char(msg));
        end

        % Save every external Simscape connection BEFORE replacement.
        % replace_block may preserve some physical lines and drop others
        % when the Simscape component class changes, so restore only
        % the connections that are actually missing.
        savedConnections = captureCoolingPlateConnections(hOld);

        % Detach only the cooling-plate branches. All neighboring TL,
        % isolation and PS-converter networks remain intact.
        detachCapturedCoolingPlateConnections(hOld,savedConnections);

        % Preserve visual placement/orientation of the slot.
        oldPosition = get_param(blockPath,"Position");

        try
            oldRotation = string(get_param(blockPath,"BlockRotation"));
        catch
            oldRotation = "0";
        end

        try
            oldNameLocation = string(get_param(blockPath,"NameLocation"));
        catch
            oldNameLocation = "";
        end

        % Replace the library reference in-place.
        replace_block( ...
            mdl,"Handle",hOld,char(newSource),"noprompt");

        hNew = getSimulinkBlockHandle(char(blockPath),true);
        if isempty(hNew) || hNew <= 0
            msg = thermalPackFormatText( ...
                "Cooling plate slot '%s' could not be resolved after replacement.", ...
                blockPath);
            error("ThermalPack:CoolingPlateReplacementMissing",char(msg));
        end

        try
            set_param(blockPath,"Position",oldPosition);
        catch
        end

        try
            set_param(blockPath,"BlockRotation",char(oldRotation));
        catch
        end

        if strlength(oldNameLocation) > 0
            try
                set_param(blockPath,"NameLocation",char(oldNameLocation));
            catch
            end
        end

        % Restore by logical interface role rather than literal port ID.
        % Current cooling blocks may use Side1 or Surf1 internally even
        % though they represent the same battery-facing surface.
        restoreCapturedCoolingPlateConnections( ...
            hNew,savedConnections);
    end

    function applyStoredThermalNodeMapping()
        if isempty(state.BatteryThermalNodeLocationsTop) || ...
                isempty(state.BatteryThermalNodeLocationsBottom)
            return;
        end

        numTop = size(state.BatteryThermalNodeLocationsTop,1);
        numBottom = size(state.BatteryThermalNodeLocationsBottom,1);

        safeSetBlockParam(topPlateBlock,"numBattThermalNodes1", ...
            num2str(numTop));
        safeSetBlockParam(topPlateBlock,"dimensionThermalNodes1", ...
            mat2str(state.BatteryThermalNodeDimensionsTop,16));
        safeSetBlockParam(topPlateBlock,"locationThermalNodes1", ...
            mat2str(state.BatteryThermalNodeLocationsTop,16));

        safeSetBlockParam(bottomPlateBlock,"numBattThermalNodes1", ...
            num2str(numBottom));
        safeSetBlockParam(bottomPlateBlock,"dimensionThermalNodes1", ...
            mat2str(state.BatteryThermalNodeDimensionsBottom,16));
        safeSetBlockParam(bottomPlateBlock,"locationThermalNodes1", ...
            mat2str(state.BatteryThermalNodeLocationsBottom,16));
    end

    function newSource = swapCoolingPlateArchitecture(numNodesForIsolation)
        if nargin < 1 || isempty(numNodesForIsolation) || ...
                ~isfinite(numNodesForIsolation)
            numNodesForIsolation = state.TotalCells;
        end
        numNodesForIsolation = max(1,round(numNodesForIsolation));

        newSource = coolingPlateLibraryPath(state.CoolingPlateType);

        replaceCoolingPlateSlot(bottomPlateBlock,newSource);
        replaceCoolingPlateSlot(topPlateBlock,newSource);

        % replace_block can preserve different subsets of conserving lines
        % for different Simscape component classes. Rebuild the two known
        % Thermal_Model_v5 liquid connections deterministically.
        repairCoolingPlateFluidConnections( ...
            bottomPlateBlock,"Bottom");
        repairCoolingPlateFluidConnections( ...
            topPlateBlock,"Top");

        % Reapply ThermalPack geometry/material/design values because a
        % newly inserted library block starts from its own defaults.
        applyStoredThermalNodeMapping();
        applyCoolingPlateSettingsToBlock(bottomPlateBlock,state);
        applyCoolingPlateSettingsToBlock(topPlateBlock,state);

        % The isolation blocks already live in the v5 master. Reassert
        % only the short physical connections if block replacement dropped
        % one, then apply the selected Top/Bottom resistance state.
        configureExistingCoolingIsolationBlocks(numNodesForIsolation,[]);
        applyCoolingArchitectureResistance();

        verifyCoolingPlateCoreConnections(bottomPlateBlock);
        verifyCoolingPlateCoreConnections(topPlateBlock);

        save_system(mdl);
    end

    function coolingPlateTypeChanged(~,~)
        if string(coolingPlateField.Value) == "Serpentine Cooling" || ...
                string(coolingPlateField.Value) == "Side Cooling" || ...
                string(coolingPlateField.Value) == "Forced Air Cooling"
            if string(coolingPlateField.Value) ~= "Forced Air Cooling"
                coolingPlateTypeField.Value = "Parallel Channels";
                state.CoolingPlateType = "Parallel Channels";
                uialert(fig, ...
                    "The dedicated Serpentine and Side cooling branches use Parallel Channels.", ...
                    "ThermalPack — Cooling Architecture");
            end
            return;
        end

        previousType = state.CoolingPlateType;
        requestedType = string(coolingPlateTypeField.Value);

        try
            state.CoolingPlateType = requestedType;
            resolvedSource = swapCoolingPlateArchitecture();

            state.LastNonSerpentineCoolingPlateType = requestedType;

            statusLabel.Text = ...
                "Cooling plate applied — " + requestedType + ...
                " | source: " + resolvedSource;
        catch ME
            state.CoolingPlateType = previousType;
            coolingPlateTypeField.Value = previousType;

            % Best-effort restoration of the previous plate type.
            try
                swapCoolingPlateArchitecture();
            catch
            end

            statusLabel.Text = ...
                "Cooling plate type change failed";

            alertText = ...
                "Requested cooling plate: " + requestedType + newline + newline + ...
                string(getReport(ME,"basic","hyperlinks","off"));

            uialert(fig,alertText, ...
                "ThermalPack Cooling Plate");
        end
    end

    function coolingModeChanged(~,~)
        optimizationModeCleanup = onCleanup(@refreshOptimizationControls); %#ok<NASGU>
        designOptimizationModeCleanup = ...
            onCleanup(@refreshDesignOptimizationControls); %#ok<NASGU>
        requestedMode = string(coolingPlateField.Value);
        previousMode = string(state.CoolingPlateMode);

        % Progressive Gas structurally replaces the standard battery block.
        % Leaving that mode therefore requires a clean structural rebuild from
        % the V5 master before any liquid/side/serpentine architecture can run.
        if state.ProgressiveForcedAirBuilt && ...
                requestedMode ~= "Forced Air Cooling"
            state.NeedsRebuild = true;
        end

        if requestedMode == "Serpentine Cooling" && ...
                ~isSerpentineCompatibleConfiguration()
            uialert(fig, ...
                "Serpentine Cooling is available only for Cylindrical cells with Hexagonal topology. Change the battery architecture first, then select Serpentine Cooling.", ...
                "ThermalPack — Serpentine Cooling");
            coolingPlateField.Value = previousMode;
            return;
        end

        % Serpentine remains a structural Battery Builder feature.
        if requestedMode == "Serpentine Cooling"
            if previousMode ~= "Serpentine Cooling"
                state.LastNonSerpentineCoolingMode = previousMode;
                state.LastNonSerpentineCoolingPlateType = state.CoolingPlateType;
            end

            state.CoolingPlateMode = requestedMode;
            coolingPlateTypeField.Value = "Parallel Channels";
            coolingPlateTypeField.Enable = "off";
            coolantRField.Enable = "on";

            previousModuleAxis = string(moduleStackingAxisField.Value);
            requiredSerpentineAxis = string(parallelStackingAxisField.Value);
            moduleStackingAxisField.Value = requiredSerpentineAxis;
            moduleStackingAxisField.Enable = "off";
            serpentineSettingsButton.Enable = "on";
            sideSettingsButton.Enable = "off";
            forcedAirSettingsButton.Enable = "off";
            ambientField.Enable = "on";
            ambientRField.Enable = "on";
            coolingModeNote.Text = ...
                "Native SP boundary with a dedicated programmatic Thermal Liquid loop.";

            branchReady = state.HasSerpentinePort && ...
                getSimulinkBlockHandle(serpentineIsolationBlock) > 0;

            refreshFlowAccountingUI();

            if state.NeedsRebuild || ~branchReady
                state.NeedsRebuild = true;
                msg = "Warning: Serpentine Cooling requires REBUILD BATTERY.";
                if previousModuleAxis ~= requiredSerpentineAxis
                    msg = msg + " Module stacking axis was synchronized to " + ...
                        requiredSerpentineAxis + ".";
                end
                statusLabel.Text = ...
                    "Serpentine Cooling selected — REBUILD BATTERY required";
                uialert(fig,msg,"ThermalPack — Rebuild Required");
                return;
            end

            applyCoolingArchitectureResistance();
            statusLabel.Text = ...
                "Serpentine Cooling active — SP coolant loop enabled";
            return;
        end

        % Leaving Serpentine restores the normal module-axis control.
        if previousMode == "Serpentine Cooling"
            moduleStackingAxisField.Enable = "on";
            serpentineSettingsButton.Enable = "off";
        end

        state.CoolingPlateMode = requestedMode;

        if requestedMode == "Side Cooling"
            % V5 permanently contains Xmin/Xmax/Ymin/Ymax. Side selection is
            % therefore an isolation switch, not a Battery Builder rebuild.
            % Serpentine and side cooling share Battery Builder's heat-exchange
            % fraction properties, so a battery most recently rebuilt for SP
            % must be regenerated if the requested side fractions differ.
            if previousMode == "Serpentine Cooling"
                sharedFractionMismatch = ...
                    abs(state.SideHeightFraction - ...
                        state.SerpentineHeightFraction) > 1e-12;
                if string(formatField.Value) == "Cylindrical"
                    sharedFractionMismatch = sharedFractionMismatch || ...
                        abs(state.SideCircumferenceFraction - ...
                            state.SerpentineCircumferenceFraction) > 1e-12;
                end
                if sharedFractionMismatch
                    state.NeedsRebuild = true;
                end
            end
            coolingPlateTypeField.Value = "Parallel Channels";
            coolingPlateTypeField.Enable = "off";
            coolantRField.Enable = "off";
            serpentineSettingsButton.Enable = "off";
            sideSettingsButton.Enable = "on";
            forcedAirSettingsButton.Enable = "off";
            ambientField.Enable = "on";
            ambientRField.Enable = "on";
            moduleStackingAxisField.Enable = "on";

            selectedSideIndex = find(sideBoundaryNames == state.SideBoundary,1);
            sideIsolationBlock = sideIsolationBlocks(selectedSideIndex);
            sidePlateBlock = sidePlateBlocks(selectedSideIndex);
            sideFlowSourceBlock = sideFlowSourceBlocks(selectedSideIndex);
            sideInletReservoirBlock = sideInletReservoirBlocks(selectedSideIndex);
            sideOutletReservoirBlock = sideOutletReservoirBlocks(selectedSideIndex);
            sideTLPropertiesBlock = sideTLPropertiesBlocks(selectedSideIndex);

            try
                state.SideThermalNodeCount = ...
                    round(slResolve(get_param(sidePlateBlock, ...
                    "numBattThermalNodes1"),sidePlateBlock));
                state.SideThermalNodeLocations = ...
                    slResolve(get_param(sidePlateBlock, ...
                    "locationThermalNodes1"),sidePlateBlock);
                state.SideThermalNodeDimensions = ...
                    slResolve(get_param(sidePlateBlock, ...
                    "dimensionThermalNodes1"),sidePlateBlock);
                state.HasSidePort = true;
                state.SideBranchCreated = true;
                state.BuiltSideBoundary = "All";
            catch
            end

            coolingModeNote.Text = ...
                "Native " + state.SideBoundary + ...
                "H active — other side, Top and Bottom interfaces isolated. " + ...
                "Use SIDE SETTINGS for Cell → side boundary Rth.";

            refreshFlowAccountingUI();

            if state.NeedsRebuild
                statusLabel.Text = ...
                    "Structural battery inputs changed — click REBUILD BATTERY";
                return;
            end

            applyCoolingArchitectureResistance();
            statusLabel.Text = ...
                "Side Cooling active on " + state.SideBoundary + ...
                " — Cell → plate Rth disabled";
            return;
        end

        if requestedMode == "Forced Air Cooling"
            state.CoolingPlateMode = requestedMode;

            % No liquid plate is active. The battery's existing cell-based
            % ambient thermal resistance represents 1/(h*Aeff).
            coolingPlateTypeField.Enable = "off";
            coolantRField.Enable = "off";
            serpentineSettingsButton.Enable = "off";
            sideSettingsButton.Enable = "off";
            forcedAirSettingsButton.Enable = "on";
            moduleStackingAxisField.Enable = "on";

            ambientField.Enable = "off";
            ambientRField.Enable = "off";
            refreshFlowAccountingUI();

            if state.ForcedAirModel == "Progressive Gas" && ...
                    ~state.ProgressiveForcedAirBuilt
                state.NeedsRebuild = true;
            end

            if state.NeedsRebuild
                coolingModeNote.Text = ...
                    "Forced air selected — rebuild first so geometry-based Re/Nu/h and the selected air network can be generated.";
                statusLabel.Text = ...
                    "Forced Air Cooling requires REBUILD BATTERY";
                return;
            end

            calc = forcedAirGeneralCalculation( ...
                state.ForcedAirVelocity_m_s, ...
                state.ForcedAirTemperature_C, ...
                state.ForcedAirPressure_Pa, ...
                state.ForcedAirAxis, ...
                state.ForcedAirWallClearance_mm);
            updateForcedAirStateFromCalculation(calc);
            ambientField.Value = state.ForcedAirTemperature_C;
            ambientRField.Value = state.ForcedAirAmbientRth_K_W;

            if state.ForcedAirModel == "Progressive Gas"
                coolingModeNote.Text = thermalPackFormatText( ...
                    ["Progressive Gas forced air — %s airflow (Min→Max fixed), %d detected columns, %s. " ...
                     "h = %.2f W/(m²·K), mdot = %.4g kg/s."], ...
                    state.ForcedAirAxis, ...
                    round(state.ForcedAirColumns),state.ForcedAirArrangement, ...
                    state.ForcedAirH_W_m2K,state.ForcedAirMassFlow_kg_s);
            else
                coolingModeNote.Text = thermalPackFormatText( ...
                    ["Uniform AmbH forced air — %s airflow, %s. " ...
                     "h = %.2f W/(m²·K), Rambient = %.3f K/W per cell."], ...
                    state.ForcedAirAxis,state.ForcedAirArrangement, ...
                    state.ForcedAirH_W_m2K,state.ForcedAirAmbientRth_K_W);
            end

            if ~state.ProgressiveForcedAirBuilt
                applyCoolingArchitectureResistance();
            end
            statusLabel.Text = ...
                "Forced Air Cooling active — use FORCED AIR SETTINGS";
            return;
        end

        % Normal Top/Bottom/None architectures.
        coolingPlateTypeField.Value = state.LastNonSerpentineCoolingPlateType;
        state.CoolingPlateType = state.LastNonSerpentineCoolingPlateType;
        coolingPlateTypeField.Enable = "on";
        serpentineSettingsButton.Enable = "off";
        sideSettingsButton.Enable = "off";
        forcedAirSettingsButton.Enable = "off";
        ambientField.Enable = "on";
        ambientRField.Enable = "on";
        moduleStackingAxisField.Enable = "on";

        if requestedMode == "No Cooling Plate"
            coolantRField.Enable = "off";
            coolingModeNote.Text = ...
                "All available cooling interfaces isolated with very high thermal resistance.";
        elseif requestedMode == "Top Cooling Plate"
            coolantRField.Enable = "on";
            coolingModeNote.Text = ...
                "Top active — Bottom and all side interfaces isolated.";
        elseif requestedMode == "Top + Bottom Cooling"
            coolantRField.Enable = "on";
            coolingModeNote.Text = ...
                "Top + Bottom active — all side interfaces isolated.";
        else
            coolantRField.Enable = "on";
            coolingModeNote.Text = ...
                "Bottom active — Top and all side interfaces isolated.";
        end

        state.LastNonSerpentineCoolingMode = requestedMode;
        refreshFlowAccountingUI();

        if state.NeedsRebuild
            statusLabel.Text = ...
                "Structural battery inputs changed — click REBUILD BATTERY";
            return;
        end

        try
            applyCoolingArchitectureResistance();
            statusLabel.Text = ...
                "Cooling architecture applied — inactive branches isolated";
        catch ME
            statusLabel.Text = "Cooling architecture could not be applied";
            uialert(fig,getReport(ME,"basic","hyperlinks","off"), ...
                "ThermalPack Cooling Architecture");
        end
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
        % Build the Advanced Settings window invisibly first.  This avoids a
        % partially-created modal window if a UI control fails during setup.
        advFig = [];
        try
            parentPos = fig.Position;
            advW = min(760,max(560,parentPos(3)-260));
            advH = min(790,max(520,parentPos(4)-80));
            advX = parentPos(1) + (parentPos(3)-advW)/2;
            advY = parentPos(2) + (parentPos(4)-advH)/2;

            advFig = uifigure( ...
                "Name","ThermalPack — Advanced Settings", ...
                "WindowStyle","modal", ...
                "Visible","off", ...
                "Position",[advX advY advW advH]);

            adv = uigridlayout(advFig,[38 2]);
            adv.ColumnWidth = {355,'1x'};
            adv.RowHeight = repmat({28},1,38);
            adv.RowHeight{1} = 40;
            adv.RowHeight{7} = 34;
            adv.RowHeight{15} = 34;
            adv.RowHeight{28} = 34;
            adv.RowHeight{31} = 34;
            adv.RowHeight{37} = '1x';
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

            crossSectionLbl = uilabel(adv,"Text","Thermal cross-section");
            crossSectionLbl.Layout.Row = 16;
            crossSectionLbl.Layout.Column = 1;

            activeFormatKey = char(string(formatField.Value));
            activeThermalAreaMode = string(state.(activeFormatKey).ThermalAreaMode);

            thermalAreaModeField = uidropdown(adv, ...
                "Items",["Automatic","Custom"], ...
                "Value",activeThermalAreaMode, ...
                "ValueChangedFcn",@thermalAreaModeChanged);
            thermalAreaModeField.Layout.Row = 16;
            thermalAreaModeField.Layout.Column = 2;

            addDisabledAdvancedRow(adv,17,"Inter-Cell Thermal Path","Main Panel Control");
            addDisabledAdvancedRow(adv,18,"Inter-Cell Radiative Thermal Path","Disabled");
            addDisabledAdvancedRow(adv,19,"Coolant Thermal Path","CellBasedThermalResistance");
            addDisabledAdvancedRow(adv,20,"Ambient Thermal Path","CellBasedThermalResistance");
            addDisabledAdvancedRow(adv,21,"Cooling Plate Block Path","External ThermalPack Plate");
            addDisabledAdvancedRow(adv,22,"Serpentine Cooling Plate",state.SerpentineMode);
            addDisabledAdvancedRow(adv,23,"Serpentine Circumference Fraction", ...
                num2str(state.SerpentineCircumferenceFraction,6));
            addDisabledAdvancedRow(adv,24,"Serpentine Height Fraction", ...
                num2str(state.SerpentineHeightFraction,6));
            addDisabledAdvancedRow(adv,25,"Side Thermal Boundary",state.SideBoundary);
            addDisabledAdvancedRow(adv,26,"Side Thermal Nodes",numericOrDash(state.SideThermalNodeCount));

            hierarchyInfo = uilabel(adv, ...
                "Text",["Thermal cross-section Automatic uses πD²/4 for Cylindrical " ...
                "and Length × Thickness for Prismatic/Pouch. Custom unlocks the main-panel " ...
                "thermal cross-section field for calibration."], ...
                "FontAngle","italic", ...
                "WordWrap","on");
            hierarchyInfo.Layout.Row = 27;
            hierarchyInfo.Layout.Column = [1 2];

            solverHdr = uilabel(adv, ...
                "Text","SOLVER SETTINGS", ...
                "FontWeight","bold");
            solverHdr.Layout.Row = 28;
            solverHdr.Layout.Column = [1 2];

            solverLbl = uilabel(adv,"Text","Solver");
            solverLbl.Layout.Row = 29;
            solverLbl.Layout.Column = 1;

            solverField = uidropdown(adv, ...
                "Items",["ode23t","Auto","daessc","ode15s"], ...
                "Value",string(state.Solver), ...
                "ValueChangedFcn",@solverChanged);
            solverField.Layout.Row = 29;
            solverField.Layout.Column = 2;

            futureHdr = uilabel(adv, ...
                "Text","FUTURE PHYSICS", ...
                "FontWeight","bold");
            futureHdr.Layout.Row = 31;
            futureHdr.Layout.Column = [1 2];

            addDisabledAdvancedRow(adv,32,"Cycling Aging","Future");
            addDisabledAdvancedRow(adv,33,"Calendar Aging","Future");
            addDisabledAdvancedRow(adv,34,"Self-Discharge","Future");
            addDisabledAdvancedRow(adv,35,"Thermal Runaway Model","Future");

            note = uitextarea(adv, ...
                "Editable","off", ...
                "Value",{'Most advanced options remain intentionally inactive.'; ...
                'Thermal cross-section can be Automatic or Custom for all cell formats.'; ...
                'Top/Bottom cooling and Inter-cell Thermal Path are controlled on the main panel.'; ...
                'Serpentine uses native Battery Builder SP plus a dedicated programmatic TL loop.'; ...
                'Side Cooling supports Cylindrical, Prismatic, and Pouch using one native vectorized Xmin/Xmax/Ymin/Ymax boundary plus a dedicated TL loop; height fraction applies to all formats and circumference fraction is Cylindrical-only.'; ...
                'No Cooling Plate isolates every available liquid cooling interface with 1e9 K/W.'; ...
                'Forced Air Cooling uses AmbH with AmbientResistance = 1/(h*Aeff) and isolates all liquid branches.'});
            note.Layout.Row = 37;
            note.Layout.Column = [1 2];

            closeButton = uibutton(adv,"push", ...
                "Text","CLOSE", ...
                "ButtonPushedFcn",@(srcBtn,~)delete(ancestor(srcBtn,"figure")));
            closeButton.Layout.Row = 38;
            closeButton.Layout.Column = [1 2];

            % Only show the modal window after every child has been created.
            movegui(advFig,"onscreen");
            advFig.Visible = "on";
            drawnow;

        catch MEadv
            if ~isempty(advFig) && isvalid(advFig)
                delete(advFig);
            end
            uialert(fig,getReport(MEadv,"basic","hyperlinks","off"), ...
                "ThermalPack — Advanced Settings Error");
        end
    end

    function thermalAreaModeChanged(src,~)
        activeFormat = string(formatField.Value);
        selectedMode = string(src.Value);
        key = char(activeFormat);

        % Preserve the current manually entered value before leaving Custom.
        if state.(key).ThermalAreaMode == "Custom"
            state.(key).CustomThermalArea_m2 = thermalAreaField.Value;
        end
        state.(key).ThermalAreaMode = selectedMode;

        updateThermalAreaForActiveFormat();
        state.NeedsRebuild = true;
        statusLabel.Text = thermalPackFormatText( ...
            "Thermal cross-section: %s — click REBUILD BATTERY",selectedMode);
    end

    function solverChanged(src,~)
        state.Solver = string(src.Value);
        statusLabel.Text = thermalPackFormatText("Solver selected: %s",state.Solver);
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
            "Text",thermalPackFormatText( ...
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

        summaryFormatKey = char(string(state.CellFormat));
        thermalAreaModeSummary = state.(summaryFormatKey).ThermalAreaMode;

        summaryLines = { ...
            thermalPackFormatText('Cell format: %s',state.CellFormat); ...
            thermalPackFormatText('Architecture: %dP × %dS = %d cells', ...
                state.P,state.S,state.TotalCells); ...
            thermalPackFormatText('Thermal cross-section: %.6g m² (%s)', ...
                thermalAreaField.Value,thermalAreaModeSummary); ...
            thermalPackFormatText('Thermal nodes: %d per cell / %d total', ...
                round(nodesField.Value), ...
                state.TotalCells*round(nodesField.Value)); ...
            thermalPackFormatText('Load profile: %s',state.LastCurrentProfileDescription); ...
            thermalPackFormatText('Simulation time: %.0f s',stopField.Value); ...
            thermalPackFormatText('Thermal limit: %.3f °C',thermalLimitField.Value); ...
            thermalPackFormatText('Solver: %s',state.Solver); ...
            ' '; ...
            thermalPackFormatText('Peak nodal temperature: %.3f °C',KPI.PeakTmaxNodal_C); ...
            thermalPackFormatText('Maximum nodal ΔT: %.3f °C',KPI.MaxDeltaTNodal_C); ...
            thermalPackFormatText('Hotspot: Cell %d / Node %d',KPI.WorstCell,KPI.WorstNode); ...
            thermalPackFormatText('Hotspot time: %.3f s',KPI.WorstTime_s); ...
            thermalPackFormatText('Safety margin: %.3f °C',KPI.MinSafetyMargin_C); ...
            thermalPackFormatText('Thermal status: %s',KPI.WorstStatus); ...
            ' '; ...
            thermalPackFormatText('Cooling location: %s',state.CoolingPlateMode); ...
            thermalPackFormatText('Cooling plate type (Top/Bottom): %s',state.CoolingPlateType); ...
            thermalPackFormatText('Serpentine coolant-side plate: Parallel Channels'); ...
            thermalPackFormatText('Serpentine mode: %s',state.SerpentineMode); ...
            thermalPackFormatText('Serpentine circumference fraction: %.4g', ...
                state.SerpentineCircumferenceFraction); ...
            thermalPackFormatText('Serpentine height fraction: %.4g', ...
                state.SerpentineHeightFraction); ...
            thermalPackFormatText('Serpentine contact Rth: %.6g K/W', ...
                state.SerpentineContactRth_K_W); ...
            thermalPackFormatText('Serpentine SP nodes: %s', ...
                numericOrDash(state.SerpentineThermalNodeCount)); ...
            thermalPackFormatText('Side boundary: %s',state.SideBoundary); ...
            thermalPackFormatText('Side height fraction: %.4g',state.SideHeightFraction); ...
            thermalPackFormatText('Side circumference fraction (Cylindrical): %.4g',state.SideCircumferenceFraction); ...
            thermalPackFormatText('Side contact Rth: %.6g K/W',state.SideContactRth_K_W); ...
            thermalPackFormatText('Side thermal nodes: %s', ...
                numericOrDash(state.SideThermalNodeCount)); ...
            thermalPackFormatText('Coolant: %s',state.CoolantFluid); ...
            thermalPackFormatText('Coolant inlet: %.3f °C',tinField.Value); ...
            thermalPackFormatText('Flow accounting: %s',state.FlowAllocationMode); ...
            thermalPackFormatText('Total coolant flow: %.6g %s', ...
                state.LastTotalCoolantFlow,coolantFlowUnit); ...
            thermalPackFormatText('Top coolant flow: %.6g %s', ...
                state.LastTopCoolantFlow,coolantFlowUnit); ...
            thermalPackFormatText('Bottom coolant flow: %.6g %s', ...
                state.LastBottomCoolantFlow,coolantFlowUnit); ...
            thermalPackFormatText('Serpentine coolant flow: %.6g %s', ...
                state.LastSerpentineCoolantFlow,coolantFlowUnit); ...
            thermalPackFormatText('Side coolant flow: %.6g %s', ...
                state.LastSideCoolantFlow,coolantFlowUnit); ...
            thermalPackFormatText('Ambient: %.3f °C',ambientField.Value); ...
            thermalPackFormatText('Forced air inlet temperature: %.3f °C',state.ForcedAirTemperature_C); ...
            thermalPackFormatText('Forced air pressure: %.6g kPa',state.ForcedAirPressure_Pa/1000); ...
            thermalPackFormatText('Forced air velocity: %.6g m/s',state.ForcedAirVelocity_m_s); ...
            thermalPackFormatText('Forced air model: %s',state.ForcedAirModel); ...
            thermalPackFormatText('Forced air axis: %s',state.ForcedAirAxis); ...
            thermalPackFormatText('Progressive battery segments / gas chambers: %d / %d', ...
                numel(state.ProgressiveForcedAirSegmentBlocks), ...
                numel(state.ProgressiveForcedAirChamberBlocks)); ...
            thermalPackFormatText('Forced air cell-to-duct wall gap: %.6g mm each side',state.ForcedAirWallClearance_mm); ...
            thermalPackFormatText('Forced air array transverse width: %.8g m',state.ForcedAirArrayTransverseWidth_m); ...
            thermalPackFormatText('Forced air duct width: %.8g m',state.ForcedAirDuctWidth_m); ...
            thermalPackFormatText('Forced air gross inlet area: %.8g m^2',state.ForcedAirFlowArea_m2); ...
            thermalPackFormatText('Forced air volumetric flow: %.8g m^3/s',state.ForcedAirVolumetricFlow_m3_s); ...
            thermalPackFormatText('Forced air mass flow: %.8g kg/s',state.ForcedAirMassFlow_kg_s); ...
            thermalPackFormatText('Forced air representative gas volume: %.8g m^3',state.ForcedAirRepresentativeGasVolume_m3); ...
            thermalPackFormatText('Forced air arrangement: %s',state.ForcedAirArrangement); ...
            thermalPackFormatText('Forced air correlation: %s',state.ForcedAirCorrelation); ...
            thermalPackFormatText('Forced air geometry source: %s',state.ForcedAirGeometrySource); ...
            thermalPackFormatText('Forced air effective velocity: %.8g m/s',state.ForcedAirEffectiveVelocity_m_s); ...
            thermalPackFormatText('Air density: %.8g kg/m^3',state.ForcedAirDensity_kg_m3); ...
            thermalPackFormatText('Air dynamic viscosity: %.8g Pa.s',state.ForcedAirDynamicViscosity_Pa_s); ...
            thermalPackFormatText('Air thermal conductivity: %.8g W/(m.K)',state.ForcedAirConductivity_W_mK); ...
            thermalPackFormatText('Air specific heat: %.8g J/(kg.K)',state.ForcedAirSpecificHeat_J_kgK); ...
            thermalPackFormatText('Air Prandtl number: %.8g',state.ForcedAirPrandtl); ...
            thermalPackFormatText('Forced air Reynolds number: %.8g',state.ForcedAirReynolds); ...
            thermalPackFormatText('Forced air Nusselt number: %.8g',state.ForcedAirNusselt); ...
            thermalPackFormatText('Forced air h: %.6g W/(m^2.K)',state.ForcedAirH_W_m2K); ...
            thermalPackFormatText('Forced air Aeff/cell: %.8g m^2',state.ForcedAirAreaPerCell_m2); ...
            thermalPackFormatText('Forced air Rambient/cell: %.8g K/W',state.ForcedAirAmbientRth_K_W); ...
            ' '; ...
            thermalPackFormatText('Runtime: %.3f s',state.LastRuntime_s)};

        summaryBox = uitextarea(g, ...
            "Editable","off", ...
            "Value",summaryLines);
        summaryBox.Layout.Row = 2;
        summaryBox.Layout.Column = 1;
    end

    function refreshThermalAnimation(~,Trace)
%% ThermalPack custom height-resolved nodal 3D thermal map.
        pauseThermalAnimation();
%% Cylindrical cells are rendered as axial cylindrical bands. Prismatic
        % and Pouch cells are rendered as axial rectangular bands. In all cases the
        % temperatures come directly from Trace.nodal_C(time,node,cell), and
        % the X-Y placement/footprint comes from Battery Builder
        % the selected ThermalNodes.Top/Bottom boundary captured during REBUILD BATTERY.

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

%% Convert Battery Builder bottom thermal-node information to N-by-2
            % centre coordinates and N-by-2 physical X-Y footprint dimensions.
            centres_m = thermalPackCellCentres( ...
                state.BatteryThermalNodeLocations, ...
                state.BatteryThermalNodeDimensions, ...
                thermalCellCount);

            nodeDims_m = thermalPackNodeDimensions( ...
                state.BatteryThermalNodeDimensions,thermalCellCount);

            if size(centres_m,1) ~= thermalCellCount
                error("ThermalPack:ThermalLocationCount", ...
                    "Could not resolve %d Battery Builder cell locations.", ...
                    thermalCellCount);
            end

            if size(nodeDims_m,1) ~= thermalCellCount
                error("ThermalPack:ThermalDimensionCount", ...
                    "Could not resolve %d Battery Builder thermal-node dimensions.", ...
                    thermalCellCount);
            end

            height_m = state.Height_mm/1000;
            if ~(isfinite(height_m) && height_m > 0)
                error("ThermalPack:InvalidRenderGeometry", ...
                    "Cell height must be positive for 3D rendering.");
            end

            if any(~isfinite(nodeDims_m),"all") || any(nodeDims_m <= 0,"all")
                error("ThermalPack:InvalidRenderGeometry", ...
                    "Battery Builder X-Y thermal-node dimensions must be positive.");
            end

            cellFormat = string(state.CellFormat);

            if cellFormat == "Cylindrical"
                radius_m = 0.5*state.Diameter_mm/1000;
                if ~(isfinite(radius_m) && radius_m > 0)
                    error("ThermalPack:InvalidRenderGeometry", ...
                        "Cell diameter must be positive for cylindrical 3D rendering.");
                end
            elseif ~(cellFormat == "Prismatic" || cellFormat == "Pouch")
                error("ThermalPack:UnsupportedRenderFormat", ...
                    "3D nodal rendering is not implemented for cell format '%s'.",cellFormat);
            end

%% Hide placeholder before creating the axes in the same 1x1 host.
            thermalMapPlaceholder.Visible = "off";

            thermalChart = uiaxes(thermalChartHost);
            thermalChart.Layout.Row = 1;
            thermalChart.Layout.Column = 1;
            hold(thermalChart,"on");

%% Cooling plate geometry. Use the exact Battery Builder contact
            % footprint. v4 can display bottom, top, or both simultaneously.
            if state.CoolingPlateMode ~= "No Cooling Plate" && ...
                    state.CoolingPlateMode ~= "Serpentine Cooling" && ...
                    state.CoolingPlateMode ~= "Side Cooling" && ...
                    state.CoolingPlateMode ~= "Forced Air Cooling"
                plateThickness_m = state.PlateThickness_mm/1000;

                if ~(isfinite(plateThickness_m) && plateThickness_m > 0)
                    plateThickness_m = 0.002;
                end

                plateBorder_m = max(0.001,0.5*state.InterCellGap_mm/1000);

                plateXMin = min(centres_m(:,1)-0.5*nodeDims_m(:,1)) - plateBorder_m;
                plateXMax = max(centres_m(:,1)+0.5*nodeDims_m(:,1)) + plateBorder_m;
                plateYMin = min(centres_m(:,2)-0.5*nodeDims_m(:,2)) - plateBorder_m;
                plateYMax = max(centres_m(:,2)+0.5*nodeDims_m(:,2)) + plateBorder_m;

                if state.CoolingPlateMode == "Top Cooling Plate"
                    surfacesToDraw = "Top";
                elseif state.CoolingPlateMode == "Top + Bottom Cooling"
                    surfacesToDraw = ["Bottom","Top"];
                else
                    surfacesToDraw = "Bottom";
                end

                for kSurfaceDraw = 1:numel(surfacesToDraw)
                    surfaceDraw = surfacesToDraw(kSurfaceDraw);

                    if surfaceDraw == "Top"
                        plateZBottom = height_m;
                        plateZTop = height_m + plateThickness_m;
                        zGuide = plateZTop + max(1e-6,plateThickness_m*0.01);
                    else
                        plateZTop = 0;
                        plateZBottom = -plateThickness_m;
                        zGuide = plateZBottom - max(1e-6,plateThickness_m*0.01);
                    end

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
                        1 2 3 4; ...
                        5 8 7 6; ...
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

                    nChannelsVisual = max(1,round(state.NumCoolantChannels));

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
            end

            vertices = zeros(0,3);
            faces = zeros(0,4);
            faceNodeIndex = zeros(0,1);
            outlineX = [];
            outlineY = [];
            outlineZ = [];

            if cellFormat == "Cylindrical"
%% Cylindrical cells: one combined patch made of axial cylindrical bands.
                angularDivisions = 24;
                theta = linspace(0,2*pi,angularDivisions+1);
                theta(end) = [];

                for c = 1:thermalCellCount
                    xc = centres_m(c,1);
                    yc = centres_m(c,2);

                    for n = 1:thermalNodeCount
%% HDistributed(1) is shown at the physical TOP; HDistributed(N)
                        % is nearest the bottom cooling interface.
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

%% Add one bottom and one top cap per cylindrical cell.
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

                        centreIdx = size(vertices,1) + 1;
                        ringStart = centreIdx + 1;
                        vertices = [vertices; ...
                            xc yc zCap; ...
                            xc + radius_m*cos(theta(:)), ...
                            yc + radius_m*sin(theta(:)), ...
                            zCap*ones(angularDivisions,1)]; %#ok<AGROW>

                        for k = 1:angularDivisions
                            kp = mod(k,angularDivisions) + 1;
                            faces(end+1,:) = [ ...
                                centreIdx,ringStart+k-1,ringStart+kp-1,ringStart+kp-1]; %#ok<AGROW>
                            faceNodeIndex(end+1,1) = sub2ind( ...
                                [thermalNodeCount thermalCellCount],nCap,c); %#ok<AGROW>
                        end
                    end
                end

%% Cylindrical nodal boundaries and generator lines.
                outlineTheta = linspace(0,2*pi,49);
                for c = 1:thermalCellCount
                    xc = centres_m(c,1);
                    yc = centres_m(c,2);

                    for nBoundary = 0:thermalNodeCount
                        zBoundary = height_m*nBoundary/thermalNodeCount;
                        outlineX = [outlineX, ...
                            xc + radius_m*cos(outlineTheta), NaN]; %#ok<AGROW>
                        outlineY = [outlineY, ...
                            yc + radius_m*sin(outlineTheta), NaN]; %#ok<AGROW>
                        outlineZ = [outlineZ, ...
                            zBoundary*ones(size(outlineTheta)), NaN]; %#ok<AGROW>
                    end

                    verticalAngles = [0 pi/2 pi 3*pi/2];
                    for kEdge = 1:numel(verticalAngles)
                        xEdge = xc + radius_m*cos(verticalAngles(kEdge));
                        yEdge = yc + radius_m*sin(verticalAngles(kEdge));
                        outlineX = [outlineX, xEdge xEdge NaN]; %#ok<AGROW>
                        outlineY = [outlineY, yEdge yEdge NaN]; %#ok<AGROW>
                        outlineZ = [outlineZ, 0 height_m NaN]; %#ok<AGROW>
                    end
                end

            else
%% Prismatic/Pouch cells: rectangular axial bands using the exact Battery Builder
                % X-Y footprint for each cell. This means the renderer remains
                % aligned even if future stacking/orientation settings rotate or
                % otherwise change the thermal-node dimensions.
                for c = 1:thermalCellCount
                    xc = centres_m(c,1);
                    yc = centres_m(c,2);
                    halfX = 0.5*nodeDims_m(c,1);
                    halfY = 0.5*nodeDims_m(c,2);
                    x0 = xc-halfX; x1 = xc+halfX;
                    y0 = yc-halfY; y1 = yc+halfY;

                    for n = 1:thermalNodeCount
                        z0 = height_m*(thermalNodeCount-n)/thermalNodeCount;
                        z1 = height_m*(thermalNodeCount-n+1)/thermalNodeCount;

                        firstVertex = size(vertices,1) + 1;
                        segmentVertices = [ ...
                            x0 y0 z0; ...
                            x1 y0 z0; ...
                            x1 y1 z0; ...
                            x0 y1 z0; ...
                            x0 y0 z1; ...
                            x1 y0 z1; ...
                            x1 y1 z1; ...
                            x0 y1 z1];
                        vertices = [vertices; segmentVertices]; %#ok<AGROW>

%% Only the four vertical side faces are needed per internal band.
                        localFaces = firstVertex - 1 + [ ...
                            1 5 6 2; ...
                            2 6 7 3; ...
                            3 7 8 4; ...
                            4 8 5 1];
                        faces = [faces; localFaces]; %#ok<AGROW>
                        faceNodeIndex = [faceNodeIndex; ...
                            repmat(sub2ind([thermalNodeCount thermalCellCount], ...
                            n,c),4,1)]; %#ok<AGROW>
                    end

%% Bottom and top caps use the bottom-most and top-most nodal values.
                    bottomStart = size(vertices,1) + 1;
                    vertices = [vertices; ...
                        x0 y0 0; x1 y0 0; x1 y1 0; x0 y1 0]; %#ok<AGROW>
                    faces(end+1,:) = bottomStart - 1 + [1 2 3 4]; %#ok<AGROW>
                    faceNodeIndex(end+1,1) = sub2ind( ...
                        [thermalNodeCount thermalCellCount],thermalNodeCount,c); %#ok<AGROW>

                    topStart = size(vertices,1) + 1;
                    vertices = [vertices; ...
                        x0 y0 height_m; x1 y0 height_m; ...
                        x1 y1 height_m; x0 y1 height_m]; %#ok<AGROW>
                    faces(end+1,:) = topStart - 1 + [1 4 3 2]; %#ok<AGROW>
                    faceNodeIndex(end+1,1) = sub2ind( ...
                        [thermalNodeCount thermalCellCount],1,c); %#ok<AGROW>

%% Prismatic/Pouch nodal boundaries: rectangular rings at every Z interface.
                    rectX = [x0 x1 x1 x0 x0];
                    rectY = [y0 y0 y1 y1 y0];
                    for nBoundary = 0:thermalNodeCount
                        zBoundary = height_m*nBoundary/thermalNodeCount;
                        outlineX = [outlineX, rectX, NaN]; %#ok<AGROW>
                        outlineY = [outlineY, rectY, NaN]; %#ok<AGROW>
                        outlineZ = [outlineZ, ...
                            zBoundary*ones(size(rectX)), NaN]; %#ok<AGROW>
                    end

                    corners = [x0 y0; x1 y0; x1 y1; x0 y1];
                    for kEdge = 1:4
                        outlineX = [outlineX, ...
                            corners(kEdge,1) corners(kEdge,1) NaN]; %#ok<AGROW>
                        outlineY = [outlineY, ...
                            corners(kEdge,2) corners(kEdge,2) NaN]; %#ok<AGROW>
                        outlineZ = [outlineZ, 0 height_m NaN]; %#ok<AGROW>
                    end
                end
            end

            thermalFaceNodeIndex = faceNodeIndex;
            initialTemps = squeeze(thermalNodal_C(1,:,:));
            initialTemps = initialTemps(:);

            thermalPatch = patch(thermalChart, ...
                "Vertices",vertices, ...
                "Faces",faces, ...
                "FaceVertexCData",initialTemps(thermalFaceNodeIndex), ...
                "FaceColor","flat", ...
                "EdgeColor","none");

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
                title(thermalChart,thermalPackFormatText( ...
                    "%s Height-Resolved Nodal Thermal Map — %d cells × %d nodes + bottom %s", ...
                    cellFormat,thermalCellCount,thermalNodeCount,state.CoolingPlateType));
            elseif state.CoolingPlateMode == "Top Cooling Plate"
                title(thermalChart,thermalPackFormatText( ...
                    "%s Height-Resolved Nodal Thermal Map — %d cells × %d nodes + top %s", ...
                    cellFormat,thermalCellCount,thermalNodeCount,state.CoolingPlateType));
            elseif state.CoolingPlateMode == "Top + Bottom Cooling"
                title(thermalChart,thermalPackFormatText( ...
                    "%s Height-Resolved Nodal Thermal Map — %d cells × %d nodes + top & bottom %s", ...
                    cellFormat,thermalCellCount,thermalNodeCount,state.CoolingPlateType));
            else
                title(thermalChart,thermalPackFormatText( ...
                    "%s Height-Resolved Nodal Thermal Map — %d cells × %d nodes", ...
                    cellFormat,thermalCellCount,thermalNodeCount));
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

%% ThermalPack auto-scaled nodal temperature colour map.
            anchorPosition = [0.00 0.20 0.40 0.60 0.80 1.00];
            anchorRGB = [ ...
                0.02 0.08 0.45; ...
                0.35 0.72 1.00; ...
                1.00 0.94 0.55; ...
                0.88 0.62 0.02; ...
                1.00 0.48 0.42; ...
                0.55 0.00 0.02];

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

            thermalMapStatus.Text = thermalPackFormatText( ...
                "%s 3D Nodal Thermal Map — %d cells × %d axial nodes — t = %.1f s", ...
                cellFormat,thermalCellCount,thermalNodeCount,tStart);

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
            thermalMapPlaceholder.Text = thermalPackFormatText( ...
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
        thermalSpeedButton.Text = thermalPackFormatText( ...
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
        if state.DesignOptimizationRunning
            stopDesignOptimization([],[]);
            designOptimizationCurrentCase.Text = ...
                "Stopping sweep — close the app again after cleanup finishes.";
            return;
        end
        if state.OptimizationRunning
            stopCoolingOptimization([],[]);
            optimizationCurrentCase.Text = ...
                "Stopping sweep — close the app again after cleanup finishes.";
            return;
        end
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

        try
            warning(thermalPackWarningState);
        catch
        end

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
        thermalMapStatus.Text = thermalPackFormatText( ...
            "3D Nodal Thermal Map — %d cells × %d axial nodes — t = %.1f s", ...
            thermalCellCount,thermalNodeCount,actualTime);

        drawnow limitrate;
    end

    function centres_m = thermalPackCellCentres(locations,dimensions,N)
%% Resolve Battery Builder selected cooling-surface geometry into N X-Y
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

%% Battery Builder ThermalNodes.Bottom Locations are centre coordinates.
        % Use them exactly as reported. Do not add half the thermal-node
        % dimensions: doing so would shift both the custom renderer and the
        % apparent cooling-plate alignment away from the physical cell centres.

        if ~isempty(centres_m) && ...
                size(centres_m,1) == N && all(isfinite(centres_m),"all")
            return;
        end

%% Emergency fallback for CYLINDRICAL geometry only.
        % Normal operation uses Battery Builder ThermalNodes.Bottom.Locations
        % directly. If those locations are unavailable, reproduce the
        % cylindrical cell-centre coordinates from the configured geometry.
        % The first centre is at [D/2,D/2], not [0,0]. The series-group pitch
        % is based on the actual parallel-assembly footprint along the module
        % stacking axis, not on the longest assembly dimension unconditionally.
        if string(state.CellFormat) ~= "Cylindrical"
            error("ThermalPack:ThermalLocationFallback", ...
                "Battery Builder thermal-node locations were unavailable. The emergency geometric fallback is intentionally limited to Cylindrical cells; Prismatic/Pouch coordinates must come from ThermalNodes.Bottom.Locations.");
        end

        P = state.P;
        S = state.S;
        rows = max(1,min(state.Rows,P));

        D_m = state.Diameter_mm/1000;
        interCellGap_m = state.InterCellGap_mm/1000;
        interAssemblyGap_m = state.InterAssemblyGap_mm/1000;
        cellPitch_m = D_m + interCellGap_m;

        % Match the same row/column convention used below to determine the
        % physical X-Y footprint of one cylindrical parallel assembly.
        if state.ParallelAssemblyStackingAxis == "Y"
            nCellsX = rows;
            nCellsY = ceil(P/rows);
        else
            nCellsX = ceil(P/rows);
            nCellsY = rows;
        end

        assemblyExtentX_m = D_m + max(0,nCellsX-1)*cellPitch_m;
        assemblyExtentY_m = D_m + max(0,nCellsY-1)*cellPitch_m;

        if state.ModuleStackingAxis == "X"
            assemblyPitch_m = assemblyExtentX_m + interAssemblyGap_m;
        else
            assemblyPitch_m = assemblyExtentY_m + interAssemblyGap_m;
        end

        baseCentre_m = [0.5*D_m 0.5*D_m];
        centres_m = zeros(N,2);
        idx = 1;

        for s = 1:S
            for p = 1:P
                row = mod(p-1,rows);
                col = floor((p-1)/rows);

                if state.ParallelAssemblyStackingAxis == "Y"
                    localOffset_m = [row*cellPitch_m col*cellPitch_m];
                else
                    localOffset_m = [col*cellPitch_m row*cellPitch_m];
                end

                if state.ModuleStackingAxis == "X"
                    assemblyOffset_m = [(s-1)*assemblyPitch_m 0];
                else
                    assemblyOffset_m = [0 (s-1)*assemblyPitch_m];
                end

                centres_m(idx,:) = ...
                    baseCentre_m + localOffset_m + assemblyOffset_m;
                idx = idx + 1;
            end
        end
    end

    function nodeDims_m = thermalPackNodeDimensions(dimensions,N)
%% Resolve Battery Builder ThermalNodes.Bottom.Dimensions into N-by-2
        % physical X-Y footprint dimensions. Use Battery Builder values first;
        % geometry-derived values are only a defensive renderer fallback.
        nodeDims_m = [];
        dims = [];

        try
            dims = double(dimensions);
        catch
            try
                dims = value(dimensions,"m");
            catch
            end
        end

        if ~isempty(dims)
            dims = squeeze(dims);
            if ismatrix(dims) && size(dims,1) == N && size(dims,2) >= 2
                nodeDims_m = dims(:,1:2);
            elseif ismatrix(dims) && size(dims,2) == N && size(dims,1) >= 2
                nodeDims_m = dims(1:2,:).';
            end
        end

        if ~isempty(nodeDims_m) && size(nodeDims_m,1) == N && ...
                all(isfinite(nodeDims_m),"all") && all(nodeDims_m > 0,"all")
            return;
        end

        if string(state.CellFormat) == "Cylindrical"
            D_m = state.Diameter_mm/1000;
            nodeDims_m = repmat([D_m D_m],N,1);
        elseif string(state.CellFormat) == "Prismatic" || ...
                string(state.CellFormat) == "Pouch"
            nodeDims_m = repmat( ...
                [state.Length_mm state.Thickness_mm]/1000,N,1);
        else
            nodeDims_m = [];
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

            geometryStatus.Text = thermalPackFormatText( ...
                "3D Battery Geometry — %dP × %dS = %d cells",P,S,N);

%% Show the geometry immediately after a successful rebuild.
            rightTabs.SelectedTab = geometryTab;
            drawnow;

        catch MEgeom
            geometryPlaceholder.Visible = "on";
            geometryPlaceholder.Text = thermalPackFormatText( ...
                "3D geometry could not be rendered:\\n%s",MEgeom.message);
            geometryStatus.Text = "Battery rebuilt — geometry renderer unavailable";
        end
    end

    function rebuildBattery(~,~)
        rebuildButton.Enable = "off";
        runButton.Enable = "off";
        optimizationRunButton.Enable = "off";
        designOptimizationRunButton.Enable = "off";

        try
            restoreStandardWorkingModelBeforeRebuild();

            CellFormat = string(formatField.Value);
            P = round(parallelField.Value);
            S = round(seriesField.Value);
            Rows = round(rowsField.Value);
            Topology = string(topologyField.Value);

            if (CellFormat == "Prismatic" || CellFormat == "Pouch") && ...
                    Topology == "SingleStack"
                Rows = 1;
            end
            ParallelAssemblyStackingAxis = string(parallelStackingAxisField.Value);
            ModuleStackingAxis = string(moduleStackingAxisField.Value);
            MassFactor = massFactorField.Value;
            CoolingPlateMode = string(coolingPlateField.Value);

            % Native Battery Builder serpentine cooling requires the module
            % stacking axis to equal the parallel-assembly stacking axis.
            % Enforce this again at rebuild time as a final safety check.
            if CoolingPlateMode == "Serpentine Cooling"
                ModuleStackingAxis = ParallelAssemblyStackingAxis;
                moduleStackingAxisField.Value = ModuleStackingAxis;
                moduleStackingAxisField.Enable = "off";
            end
            InterCellHeatTransfer = string(interCellHeatField.Value);
            N = P*S;

            if CoolingPlateMode == "Serpentine Cooling" && ...
                    ~(CellFormat == "Cylindrical" && Topology == "Hexagonal")
                error("ThermalPack:SerpentineCompatibility", ...
                    "Serpentine Cooling requires Cylindrical cells with Hexagonal topology.");
            end
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

            % Keep the physical Cell -> plate resistance unchanged for all
            % architectures. External isolation determines active liquid paths.
            effectiveCoolantR_K_W = coolantRField.Value;

            if CoolingPlateMode == "Forced Air Cooling"
                % A provisional numeric AmbientResistance is required while the
                % new Battery Builder block is being generated. The exact
                % geometry-aware value is recomputed immediately after the new
                % thermal-node coordinates are captured below.
                ambientField.Value = state.ForcedAirTemperature_C;
                ambientRField.Value = state.ForcedAirAmbientRth_K_W;
            end

%% Single ThermalPack-level configuration values.
            modelResolutionSetting = "Detailed";
            cellVariationSetting = "PercentDeviation";
            coolantThermalPathSetting = "CellBasedThermalResistance";
            ambientThermalPathSetting = "CellBasedThermalResistance";

            if N > 500
                answer = uiconfirm(fig, ...
                    thermalPackFormatText(["You selected %d detailed cell models.\n" ...
                    "Compilation and simulation can become very slow.\n\nContinue?"],N), ...
                    "Large Detailed Battery", ...
                    "Options",["Continue","Cancel"], ...
                    "DefaultOption","Cancel", ...
                    "CancelOption","Cancel");
                if answer == "Cancel"
                    statusLabel.Text = "Rebuild cancelled";
                    rebuildButton.Enable = "on";
                    runButton.Enable = "on";
                    if ~state.DesignOptimizationRunning
                        optimizationRunButton.Enable = "on";
                        refreshDesignOptimizationControls();
                    end
                    return;
                end
            end

            statusLabel.Text = thermalPackFormatText( ...
                "Building %d-cell %s module (%dP × %dS)...", ...
                N,lower(char(CellFormat)),P,S);
            drawnow;

            height_m = heightField.Value/1000;
            cellGap_m = cellGapField.Value/1000;
            assemblyGap_m = assemblyGapField.Value/1000;

            if CellFormat == "Cylindrical"
                radius_m = diameterField.Value/2000;
            else
                length_m = diameterField.Value/1000;
                thickness_m = thicknessField.Value/1000;
            end

            if CellFormat == "Pouch"
                tabWidth_m = tabWidthField.Value/1000;
                tabHeight_m = tabHeightField.Value/1000;
                tabLocation = string(tabLocationField.Value);
                if tabWidth_m >= length_m
                    error("Pouch tab width must be smaller than pouch length.");
                end
                if tabHeight_m >= height_m
                    error("Pouch tab height must be smaller than pouch height.");
                end
            end

            % Resolve the active thermal cross-section immediately before
            % rebuilding. Automatic is geometry-derived for both formats;
            % Custom uses the user-defined effective area.
            updateThermalAreaForActiveFormat();

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
            cellModelOptions = ...
                configureElectricalDynamicsCellModelOptions(cellModelOptions);

            if CellFormat == "Cylindrical"
                geometry = batteryCylindricalGeometry( ...
                    simscape.Value(height_m,"m"), ...
                    simscape.Value(radius_m,"m"));
                generatedCellName = "Cylindrical_Cell";
                generatedAssemblyName = "Cylindrical_Cell_Assembly";
                generatedModuleName = "Cylindrical_Cell_Module_Test";
                libraryFormatTag = "Cyl";
            elseif CellFormat == "Prismatic"
                geometry = batteryPrismaticGeometry( ...
                    simscape.Value(height_m,"m"), ...
                    simscape.Value(length_m,"m"), ...
                    simscape.Value(thickness_m,"m"));
                generatedCellName = "Prismatic_Cell";
                generatedAssemblyName = "Prismatic_Cell_Assembly";
                generatedModuleName = "Prismatic_Cell_Module_Test";
                libraryFormatTag = "Prismatic";
            else
                geometry = batteryPouchGeometry( ...
                    simscape.Value(height_m,"m"), ...
                    simscape.Value(length_m,"m"), ...
                    simscape.Value(thickness_m,"m"), ...
                    TabLocation=tabLocation, ...
                    TabWidth=simscape.Value(tabWidth_m,"m"), ...
                    TabHeight=simscape.Value(tabHeight_m,"m"));
                generatedCellName = "Pouch_Cell";
                generatedAssemblyName = "Pouch_Cell_Assembly";
                generatedModuleName = "Pouch_Cell_Module_Test";
                libraryFormatTag = "Pouch";
            end

            cellObj = batteryCell(geometry,cellModelOptions);
            cellObj.Name = generatedCellName;
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
            pAssembly.Name = generatedAssemblyName;
            pAssembly.Topology = Topology;
            pAssembly.Rows = Rows;
            pAssembly.StackingAxis = ParallelAssemblyStackingAxis;
            pAssembly.InterCellGap = simscape.Value(cellGap_m,"m");
            pAssembly.ModelResolution = modelResolutionSetting;
%% One ThermalPack setting is propagated to both hierarchy
            pAssembly.InterCellThermalPath = interCellPathState;

            moduleObj = batteryModule(pAssembly,S);
            moduleObj.Name = generatedModuleName;
            moduleObj.StackingAxis = ModuleStackingAxis;
            moduleObj.InterParallelAssemblyGap = ...
                simscape.Value(assemblyGap_m,"m");
            moduleObj.ModelResolution = modelResolutionSetting;
            moduleObj.MassFactor = MassFactor;

%% Thermal architecture matching ThermalPack v5:
            moduleObj.AmbientThermalPath = ambientThermalPathSetting;
            moduleObj.CoolantThermalPath = coolantThermalPathSetting;

            % The v5 master keeps BOTH cooling boundaries available at all
            % times. The GUI activates/deactivates the external connection
            % to each plate instead of rebuilding a different one-port battery.
            try
                moduleObj.CoolingPlate = ["Top","Bottom"];
            catch MEdual
                error("ThermalPack:DualCoolingBuilder", ...
                    "Battery Builder did not accept simultaneous Top + Bottom cooling surfaces in this MATLAB release. Thermal_Model_v5 requires both ports. Original error:\n%s", ...
                    MEdual.message);
            end

            moduleObj.CoolingPlateBlockPath = "None";

            % V5 permanently exposes ALL native vectorized side boundaries.
            % Xmin/Xmax/Ymin/Ymax are selected at runtime through isolation Rth.
            moduleObj.XminThermalNodes = "Vectorized";
            moduleObj.XmaxThermalNodes = "Vectorized";
            moduleObj.YminThermalNodes = "Vectorized";
            moduleObj.YmaxThermalNodes = "Vectorized";

            % The height fraction controls the side heat-exchange patch for all
            % supported formats. Cylindrical additionally uses wrap fraction.
            moduleObj.FractionOfCellHeightForHeatExchange = ...
                state.SideHeightFraction;
            if CellFormat == "Cylindrical"
                moduleObj.FractionOfCellCircumferenceForHeatExchange = ...
                    state.SideCircumferenceFraction;
            end

            if CoolingPlateMode == "Serpentine Cooling"
                if string(pAssembly.StackingAxis) ~= string(moduleObj.StackingAxis)
                    error("ThermalPack:SerpentineStackingAxis", ...
                        "Native Battery Builder Serpentine Cooling requires Parallel Assembly and Module stacking axes to match.");
                end
                moduleObj.SerpentineCoolingPlate = state.SerpentineMode;
                moduleObj.FractionOfCellCircumferenceForHeatExchange = ...
                    state.SerpentineCircumferenceFraction;
                moduleObj.FractionOfCellHeightForHeatExchange = ...
                    state.SerpentineHeightFraction;
            else
                moduleObj.SerpentineCoolingPlate = "None";
            end

            moduleObj.InterCellThermalPath = interCellPathState;
            moduleObj.CellParameterVariation = cellVariationSetting;

            %% Read BOTH cooling-surface mappings before build.
            topThermalNodes = moduleObj.ThermalNodes.Top;
            bottomThermalNodes = moduleObj.ThermalNodes.Bottom;

            numTopThermalNodes = topThermalNodes.NumNodes;
            numBottomThermalNodes = bottomThermalNodes.NumNodes;

            topThermalLocations = thermalNodeLocations(topThermalNodes,"Top");
            bottomThermalLocations = thermalNodeLocations(bottomThermalNodes,"Bottom");
            topThermalDimensions = topThermalNodes.Dimensions;
            bottomThermalDimensions = bottomThermalNodes.Dimensions;

            numSerpentineThermalNodes = 0;
            serpentineThermalLocations = [];
            serpentineThermalDimensions = [];
            if CoolingPlateMode == "Serpentine Cooling"
                serpentineThermalNodes = moduleObj.ThermalNodes.Serpentine;
                numSerpentineThermalNodes = serpentineThermalNodes.NumNodes;
                serpentineThermalLocations = ...
                    thermalNodeLocations(serpentineThermalNodes,"Serpentine");
                serpentineThermalDimensions = ...
                    serpentineThermalNodes.Dimensions;

                if isempty(numSerpentineThermalNodes) || ...
                        numSerpentineThermalNodes < 1
                    error("ThermalPack:SerpentineNodeMapping", ...
                        "Battery Builder returned no Serpentine thermal nodes.");
                end
            end

            sideNodeCounts = zeros(1,numel(sideBoundaryNames));
            sideNodeLocations = cell(1,numel(sideBoundaryNames));
            sideNodeDimensions = cell(1,numel(sideBoundaryNames));
            sideBoundaryCellsAll = cell(1,numel(sideBoundaryNames));

            for kSide = 1:numel(sideBoundaryNames)
                boundaryNow = sideBoundaryNames(kSide);
                [nodesNow,cellsNow] = sideThermalNodeData(moduleObj,boundaryNow);
                sideNodeCounts(kSide) = nodesNow.NumNodes;
                sideNodeLocations{kSide} = ...
                    thermalNodeLocations(nodesNow,boundaryNow);
                sideNodeDimensions{kSide} = nodesNow.Dimensions;
                sideBoundaryCellsAll{kSide} = cellsNow;

                if isempty(sideNodeCounts(kSide)) || sideNodeCounts(kSide) < 1
                    error("ThermalPack:SideNodeMapping", ...
                        "Battery Builder returned no %s side thermal nodes.", ...
                        boundaryNow);
                end
            end

            selectedSideIndex = find(sideBoundaryNames == state.SideBoundary,1);
            numSideThermalNodes = sideNodeCounts(selectedSideIndex);
            sideThermalLocations = sideNodeLocations{selectedSideIndex};
            sideThermalDimensions = sideNodeDimensions{selectedSideIndex};
            sideBoundaryCells = sideBoundaryCellsAll{selectedSideIndex};

            if numTopThermalNodes ~= N || numBottomThermalNodes ~= N
                warning("ThermalPack:NodeCount", ...
                    "Expected %d thermal nodes on each cooling surface but " + ...
                    "Battery Builder reported Top=%d and Bottom=%d.", ...
                    N,numTopThermalNodes,numBottomThermalNodes);
            end

            % Existing geometry/rendering code uses the generic mapping.
            % Top and bottom share the same X-Y cell footprint, so retain the
            % bottom surface as the generic reference.
            thermalLocations = bottomThermalLocations;
            thermalDimensions = bottomThermalDimensions;
            numThermalNodes = numBottomThermalNodes;

            %% Generate unique Simscape Battery library
            generatedDir = fullfile(pwd,"ThermalPack_Generated");
            if ~isfolder(generatedDir)
                mkdir(generatedDir);
            end
            addpath(generatedDir);

            stamp = string(datetime("now","Format","yyyyMMdd_HHmmss"));
            libName = "ThermalPack_" + libraryFormatTag + "_" + P + "P_" + S + "S_" + stamp;

            statusLabel.Text = "Running buildBattery / Simscape compilation...";
            drawnow;

            buildBattery(moduleObj, ...
                LibraryName=libName, ...
                Directory=generatedDir, ...
                MaskParameters="NumericValues", ...
                Verbose="on");

            libModel = libName + "_lib";
            load_system(libModel);

            newSource = libModel + "/" + generatedModuleName;
            if getSimulinkBlockHandle(newSource) <= 0
                topBlocks = string(find_system(libModel, ...
                    "SearchDepth",1,"Type","Block"));
                candidate = topBlocks(contains(topBlocks,generatedModuleName));

                if isempty(candidate)
                    error("Generated module block could not be located in %s.",char(libModel));
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

            %% Capture and detach every permanent V5 battery connection.
            savedConnections = struct;

            hBattery = getSimulinkBlockHandle(char(batteryBlock),true);
            if isempty(hBattery) || hBattery <= 0
                error("ThermalPack:BatteryHandleInvalid", ...
                    "Could not obtain a valid handle for %s.",batteryBlock);
            end

            fixedBatteryPortNames = ["AmbH","p","n"];
            for kPort = 1:numel(fixedBatteryPortNames)
                portName = fixedBatteryPortNames(kPort);
                connected = simscape.connectedPorts(hBattery,portName);
                if isempty(connected)
                    error("ThermalPack:BatteryPortDisconnected", ...
                        "Battery port '%s' is disconnected.",portName);
                end
                savedConnections.(char(portName)) = connected;
                simscape.removeConnection(hBattery,portName);
            end

            oldTopPort = resolveBatterySurfacePort(hBattery,"Top");
            oldBottomPort = resolveBatterySurfacePort(hBattery,"Bottom");

            if strlength(oldTopPort) == 0 || strlength(oldBottomPort) == 0
                error("ThermalPack:CoolingSurfacePortMissing", ...
                    "V5 battery must expose both Top and Bottom cooling ports.");
            end

            savedConnections.Top = simscape.connectedPorts(hBattery,oldTopPort);
            savedConnections.Bottom = simscape.connectedPorts(hBattery,oldBottomPort);
            if isempty(savedConnections.Top) || isempty(savedConnections.Bottom)
                error("ThermalPack:CoolingSurfaceDisconnected", ...
                    "V5 Top/Bottom cooling subsystem connection is missing.");
            end
            simscape.removeConnection(hBattery,oldTopPort);
            simscape.removeConnection(hBattery,oldBottomPort);

            for kSide = 1:numel(sideBoundaryNames)
                sidePort = sideBoundaryNames(kSide) + "H";
                connNow = simscape.connectedPorts(hBattery,sidePort);
                if isempty(connNow)
                    error("ThermalPack:SideCoolingDisconnected", ...
                        "Permanent V5 %s connection is missing.",sidePort);
                end
                savedConnections.(char(sidePort)) = connNow;
                simscape.removeConnection(hBattery,sidePort);
            end

            % A previous serpentine rebuild may also have SP connected to the
            % bottom coolant plate. Disconnect it before replace_block.
            try
                oldPortInfo = simscape.connectionPortProperties(hBattery);
                oldPortNames = strings(1,numel(oldPortInfo));
                for kInfo = 1:numel(oldPortInfo)
                    oldPortNames(kInfo) = string(oldPortInfo(kInfo).Name);
                end
                if any(oldPortNames == "SP") && ...
                        isPhysicalPortConnected(hBattery,"SP")
                    simscape.removeConnection(hBattery,"SP");
                end
            catch
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
                adoptedPath = mdl + "/" + generatedModuleName;
                if getSimulinkBlockHandle(adoptedPath) > 0
                    set_param(adoptedPath,"Name",char(oldBlockName));
                end
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

            for kPort = 1:numel(fixedBatteryPortNames)
                portName = fixedBatteryPortNames(kPort);
                if ~any(generatedPortNames == portName)
                    error("ThermalPack:GeneratedPortMissing", ...
                        "The generated battery does not expose required port '%s'. Available ports: %s", ...
                        portName,strjoin(generatedPortNames,", "));
                end
            end

            newTopPort = resolveBatterySurfacePort(hBatteryNew,"Top");
            newBottomPort = resolveBatterySurfacePort(hBatteryNew,"Bottom");

            if strlength(newTopPort) == 0 || strlength(newBottomPort) == 0
                error("ThermalPack:GeneratedDualCoolingPortsMissing", ...
                    "The rebuilt v5 battery must expose BOTH top and bottom cooling ports. Available ports: %s", ...
                    strjoin(generatedPortNames,", "));
            end

            if CoolingPlateMode == "Serpentine Cooling" && ...
                    ~any(generatedPortNames == "SP")
                error("ThermalPack:GeneratedSerpentinePortMissing", ...
                    "Battery Builder did not expose the required SP port. Available ports: %s", ...
                    strjoin(generatedPortNames,", "));
            end

            requiredSidePorts = sideBoundaryNames + "H";
            for kSide = 1:numel(requiredSidePorts)
                if ~any(generatedPortNames == requiredSidePorts(kSide))
                    error("ThermalPack:GeneratedSidePortMissing", ...
                        "V5 rebuilt battery must expose %s. Available ports: %s", ...
                        requiredSidePorts(kSide), ...
                        strjoin(generatedPortNames,", "));
                end
            end

            % Resize every permanent isolation array BEFORE reconnecting
            % the newly generated battery ports. This avoids transient
            % array-size mismatches when P/S/format changes node counts.
            configureExistingCoolingIsolationBlocks(N,sideNodeCounts);

            %% Restore fixed electrical/ambient connections.
            for kPort = 1:numel(fixedBatteryPortNames)
                portName = fixedBatteryPortNames(kPort);
                previous = savedConnections.(char(portName));
                simscape.addConnection( ...
                    hBatteryNew,portName, ...
                    previous(1).Block,previous(1).PortName, ...
                    "autorouting","smart");
            end

            simscape.addConnection( ...
                hBatteryNew,newTopPort, ...
                savedConnections.Top(1).Block, ...
                savedConnections.Top(1).PortName, ...
                "autorouting","smart");

            simscape.addConnection( ...
                hBatteryNew,newBottomPort, ...
                savedConnections.Bottom(1).Block, ...
                savedConnections.Bottom(1).PortName, ...
                "autorouting","smart");

            for kSide = 1:numel(sideBoundaryNames)
                sidePort = sideBoundaryNames(kSide) + "H";
                previous = savedConnections.(char(sidePort));
                simscape.addConnection( ...
                    hBatteryNew,sidePort, ...
                    previous(1).Block,previous(1).PortName, ...
                    "autorouting","smart");
            end

            %% Parameterize generated module
            % FIRST restore the master V5 cell physics exactly:
            % lookup tables, breakpoints, R0 table, initialization modes,
            % and original per-cell deviation pattern.
            applyMasterBatteryParameters( ...
                batteryBlock,masterBatteryParams,N,S);

%% Non-cylindrical formats start from a nominal cell population. The cylindrical master
            % can contain legacy per-cell deviations that are meaningful only
            % for that original 12-cell pack. Clear every generated deviation
            % vector for Prismatic/Pouch first; the three user-editable variation
            % vectors (R0, thermal mass and Z conductivity) are reapplied below.
            if CellFormat ~= "Cylindrical"
                resetCellParameterDeviations(batteryBlock,N);
            end

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

            % Reapply the GUI SOC after restoring the V5 master.  Without
            % this, the generated battery can silently retain the master's
            % historical ~0.40 socCell initialization.
            applyInitialSOCToBlock(batteryBlock,socField.Value,N,S);

%% Initial cell temperature is independent from ambient/coolant.
            state.InitialCellTemperature_C = initialCellTempField.Value;
            safeSetBlockParam(batteryBlock,"batteryTemperature", ...
                thermalPackFormatText("repmat(%.16g,%d,1)", ...
                initialCellTempField.Value + 273.15,N));

            safeSetBlockParam(batteryBlock,"CoolantResistance", ...
                num2str(effectiveCoolantR_K_W,16));
            safeSetBlockParam(batteryBlock,"AmbientResistance", ...
                num2str(ambientRField.Value,16));

            if CoolingPlateMode == "Serpentine Cooling"
                serpentineRthParam = dialogParameterNameByPrompt( ...
                    batteryBlock, ...
                    "Cell-level thermal path resistance at serpentine boundary");
                if strlength(serpentineRthParam) == 0
                    error("ThermalPack:SerpentineResistanceParameter", ...
                        "The generated battery exposes SP but its serpentine thermal-path resistance parameter could not be resolved.");
                end
                safeSetBlockParam(batteryBlock,serpentineRthParam, ...
                    num2str(state.SerpentineContactRth_K_W,16));
            end

            % V5 keeps the same configurable native side Rth on all four
            % boundaries so Xmin/Xmax/Ymin/Ymax can be switched at runtime.
            for kSide = 1:numel(sideBoundaryNames)
                sidePrompt = "Cell-level thermal path resistance at " + ...
                    sideBoundaryNames(kSide) + " boundary";
                sideRthParam = dialogParameterNameByPrompt( ...
                    batteryBlock,sidePrompt);
                if strlength(sideRthParam) == 0
                    error("ThermalPack:SideResistanceParameter", ...
                        "Could not resolve the generated %s side thermal-path resistance parameter.", ...
                        sideBoundaryNames(kSide));
                end
                safeSetBlockParam(batteryBlock,sideRthParam, ...
                    num2str(state.SideContactRth_K_W,16));
            end

            if InterCellHeatTransfer == "Enabled"
                safeSetBlockParam(batteryBlock,"InterCellThermalResistance", ...
                    num2str(interCellRField.Value,16));
                safeSetBlockParam(batteryBlock,"InterParallelAssemblyThermalResistance", ...
                    num2str(interParallelRField.Value,16));
            end

            %% Update existing external Parallel Channels cooling plate
            % Battery thermal-interface geometry remains automatic and comes
            % directly from the rebuilt Battery Builder object. Locations are
            % centre coordinates and dimensions/locations are passed unchanged.
            formatKey = char(CellFormat);
            state.PlatePartitionsX = state.(formatKey).PlatePartitionsX;
            state.PlatePartitionsY = state.(formatKey).PlatePartitionsY;

            % Bottom cooling plate mapping
            safeSetBlockParam(bottomPlateBlock,"numBattThermalNodes1", ...
                num2str(numBottomThermalNodes));
            safeSetBlockParam(bottomPlateBlock,"dimensionThermalNodes1", ...
                mat2str(bottomThermalDimensions,16));
            safeSetBlockParam(bottomPlateBlock,"locationThermalNodes1", ...
                mat2str(bottomThermalLocations,16));

            % Top cooling plate mapping
            safeSetBlockParam(topPlateBlock,"numBattThermalNodes1", ...
                num2str(numTopThermalNodes));
            safeSetBlockParam(topPlateBlock,"dimensionThermalNodes1", ...
                mat2str(topThermalDimensions,16));
            safeSetBlockParam(topPlateBlock,"locationThermalNodes1", ...
                mat2str(topThermalLocations,16));

%% Ensure the two permanent v5 plate slots retain the user's selected
            % normal top/bottom architecture. Serpentine gets its OWN plate.
            % IMPORTANT: pass the NEW battery node count explicitly.
            swapCoolingPlateArchitecture(N);

            % Reapply normal Top and Bottom mappings after any plate replacement.
            safeSetBlockParam(topPlateBlock,"numBattThermalNodes1", ...
                num2str(numTopThermalNodes));
            safeSetBlockParam(topPlateBlock,"dimensionThermalNodes1", ...
                mat2str(topThermalDimensions,16));
            safeSetBlockParam(topPlateBlock,"locationThermalNodes1", ...
                mat2str(topThermalLocations,16));
            safeSetBlockParam(bottomPlateBlock,"numBattThermalNodes1", ...
                num2str(numBottomThermalNodes));
            safeSetBlockParam(bottomPlateBlock,"dimensionThermalNodes1", ...
                mat2str(bottomThermalDimensions,16));
            safeSetBlockParam(bottomPlateBlock,"locationThermalNodes1", ...
                mat2str(bottomThermalLocations,16));

            if CoolingPlateMode == "Serpentine Cooling"
                ensureSerpentineCoolingBranch( ...
                    numSerpentineThermalNodes, ...
                    serpentineThermalDimensions, ...
                    serpentineThermalLocations);
            else
                removeSerpentineCoolingBranch();
            end

            % V5 side branches are permanent. Only update their Battery
            % Builder node mappings and common Parallel Channels settings.
            sidePlateState = state;
            sidePlateState.CoolingPlateType = "Parallel Channels";

            for kSide = 1:numel(sideBoundaryNames)
                safeSetBlockParam(sidePlateBlocks(kSide), ...
                    "numBattThermalNodes1", ...
                    num2str(sideNodeCounts(kSide)));
                safeSetBlockParam(sidePlateBlocks(kSide), ...
                    "dimensionThermalNodes1", ...
                    mat2str(sideNodeDimensions{kSide},16));
                safeSetBlockParam(sidePlateBlocks(kSide), ...
                    "locationThermalNodes1", ...
                    mat2str(sideNodeLocations{kSide},16));
                applyCoolingPlateSettingsToBlock( ...
                    sidePlateBlocks(kSide),sidePlateState);
            end

%% User cooling-plate material/discretization/channel settings.
            applyCoolingPlateSettingsToBlock(bottomPlateBlock,state);
            applyCoolingPlateSettingsToBlock(topPlateBlock,state);
            if getSimulinkBlockHandle(serpentinePlateBlock) > 0
                serpPlateState = state;
                serpPlateState.CoolingPlateType = "Parallel Channels";
                applyCoolingPlateSettingsToBlock(serpentinePlateBlock,serpPlateState);
            end

            try
                mdlWks = get_param(mdl,"ModelWorkspace");
                assignin(mdlWks,"T_plate_K", ...
                    state.InitialPlateTemperature_C + 273.15);
            catch
            end

%% Reapply the selected predefined coolant to both v5 liquid networks.
            thermalLiquidBlocks = findThermalLiquidPropertiesBlocks(mdl);
            for kTL = 1:numel(thermalLiquidBlocks)
                applyCoolantPropertiesToBlock(thermalLiquidBlocks(kTL),state);
            end

            %% Save working model
            save_system(mdl);

            %% Update app state
            state.P = P;
            state.S = S;
            state.TotalCells = N;
            state.CellFormat = CellFormat;
            state.Height_mm = heightField.Value;

            formatKey = char(CellFormat);
            if CellFormat == "Cylindrical"
                state.Diameter_mm = diameterField.Value;
                state.Cylindrical.Diameter_mm = diameterField.Value;
            else
                state.Length_mm = diameterField.Value;
                state.Thickness_mm = thicknessField.Value;
                state.(formatKey).Length_mm = diameterField.Value;
                state.(formatKey).Thickness_mm = thicknessField.Value;
            end

            state.(formatKey).P = P;
            state.(formatKey).S = S;
            state.(formatKey).Height_mm = heightField.Value;
            state.(formatKey).Mass_kg = massField.Value;
            state.(formatKey).Capacity_Ah = capacityField.Value;
            state.(formatKey).Energy_Wh = energyField.Value;
            state.(formatKey).Topology = Topology;
            state.(formatKey).Rows = Rows;
            state.(formatKey).StackingAxis = ParallelAssemblyStackingAxis;
            state.(formatKey).ThermalMass_J_K = thermalMassField.Value;
            state.(formatKey).ConductivityZ_W_mK = conductivityField.Value;
            state.(formatKey).ThermalArea_m2 = thermalAreaField.Value;
            if state.(formatKey).ThermalAreaMode == "Custom"
                state.(formatKey).CustomThermalArea_m2 = thermalAreaField.Value;
            end
            if CellFormat == "Pouch"
                state.Pouch.TabLocation = string(tabLocationField.Value);
                state.Pouch.TabWidth_mm = tabWidthField.Value;
                state.Pouch.TabHeight_mm = tabHeightField.Value;
            end
            saveElectricalStateForFormat(CellFormat);

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
            state.BatteryThermalNodeCount = numThermalNodes;
            state.BatteryThermalNodeLocations = bottomThermalLocations;
            state.BatteryThermalNodeDimensions = bottomThermalDimensions;
            state.BatteryThermalNodeLocationsTop = topThermalLocations;
            state.BatteryThermalNodeDimensionsTop = topThermalDimensions;
            state.BatteryThermalNodeLocationsBottom = bottomThermalLocations;
            state.BatteryThermalNodeDimensionsBottom = bottomThermalDimensions;
            if CoolingPlateMode == "Serpentine Cooling"
                state.SerpentineThermalNodeCount = numSerpentineThermalNodes;
                state.SerpentineThermalNodeLocations = serpentineThermalLocations;
                state.SerpentineThermalNodeDimensions = serpentineThermalDimensions;
                state.HasSerpentinePort = any(generatedPortNames == "SP");
                state.SerpentineBranchCreated = ...
                    getSimulinkBlockHandle(serpentineIsolationBlock) > 0;
            else
                state.SerpentineThermalNodeCount = [];
                state.SerpentineThermalNodeLocations = [];
                state.SerpentineThermalNodeDimensions = [];
                state.HasSerpentinePort = false;
                state.SerpentineBranchCreated = false;
            end

            selectedSideIndex = find(sideBoundaryNames == state.SideBoundary,1);
            state.SideThermalNodeCount = sideNodeCounts(selectedSideIndex);
            state.SideThermalNodeLocations = ...
                sideNodeLocations{selectedSideIndex};
            state.SideThermalNodeDimensions = ...
                sideNodeDimensions{selectedSideIndex};
            state.SideBoundaryCells = ...
                sideBoundaryCellsAll{selectedSideIndex};
            state.HasSidePort = true;
            state.SideBranchCreated = true;
            state.BuiltSideBoundary = "All";

            % Apply the currently selected Top / Bottom / Top+Bottom / None
            % resistance state after the newly rebuilt battery is in place.
            applyCoolingArchitectureResistance();

            % Now that the full Battery Builder geometry is available, resolve
            % the final forced-air correlation and, when requested, replace the
            % standard one-AmbH battery with the generated progressive Gas
            % subsystem. The full module object is retained in state for the 3-D
            % geometry renderer and cell-coordinate source of truth.
            if CoolingPlateMode == "Forced Air Cooling"
                calcForcedAir = forcedAirGeneralCalculation( ...
                    state.ForcedAirVelocity_m_s, ...
                    state.ForcedAirTemperature_C, ...
                    state.ForcedAirPressure_Pa, ...
                    state.ForcedAirAxis, ...
                    state.ForcedAirWallClearance_mm);
                updateForcedAirStateFromCalculation(calcForcedAir);
                ambientField.Value = state.ForcedAirTemperature_C;
                ambientRField.Value = state.ForcedAirAmbientRth_K_W;

                if state.ForcedAirModel == "Progressive Gas"
                    statusLabel.Text = ...
                        "Building progressive forced-air battery/Gas subsystem...";
                    drawnow;
                    buildProgressiveForcedAirSubsystem(generatedDir,stamp);
                else
                    clearProgressiveForcedAirState();
                    safeSetBlockParam(batteryBlock,"AmbientResistance", ...
                        num2str(state.ForcedAirAmbientRth_K_W,16));
                    save_system(mdl);
                end
            else
                clearProgressiveForcedAirState();
            end

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
            thermalMapPlaceholder.Text = thermalPackFormatText( ...
                "Run a simulation to generate the %s 3D nodal thermal map for this rebuilt battery.", ...
                lower(char(CellFormat)));
            thermalMapStatus.Text = thermalPackFormatText( ...
                "%s battery rebuilt — thermal map awaiting simulation",CellFormat);
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
            state.LastCoolantTrace = struct();
            state.LastRuntime_s = NaN;
            state.LastCurrentProfileDescription = "";
            state.LastOptimizationResults = table();
            state.LastRecommendedCase = table();
            state.LastOptimizationFolder = "";
            state.LastOptimizationSettings = struct();
            optimizationExportButton.Enable = "off";
            optimizationCsvButton.Enable = "off";
            optimizationTable.Data = table();
            cla(optimizationAxes);
            title(optimizationAxes,"Peak Temperature Across the Operating Sweep");
            xlabel(optimizationAxes,"Coolant mass flow rate (kg/s)");
            ylabel(optimizationAxes,"Peak nodal temperature (°C)");
            grid(optimizationAxes,"on");
            optimizationStatus.Text = ...
                "Battery rebuilt — run a new cooling sweep for this configuration.";
            resetSweepAnalysisPlots( ...
                "Battery rebuilt — run a new cooling sweep for this configuration.");
            if ~state.DesignOptimizationRunning
                state.LastDesignOptimizationResults = table();
                state.LastRecommendedDesign = table();
                state.LastDesignOptimizationFolder = "";
                state.LastDesignOptimizationSettings = struct();
                designOptimizationExportButton.Enable = "off";
                designOptimizationCsvButton.Enable = "off";
                designOptimizationTable.Data = table();
                resetDesignOptimizationPlots( ...
                    "Battery rebuilt — run a new design sweep for this configuration.");
            end
            cellNodalResultsButton.Enable = "off";
            simulationSummaryButton.Enable = "off";
            exportResultsButton.Enable = "off";

%% Render the actual Battery Builder module inside ThermalPack.
            refreshBatteryGeometry(moduleObj,P,S,N);

            if CoolingPlateMode == "Serpentine Cooling"
                statusLabel.Text = thermalPackFormatText( ...
                    "Rebuild complete — %dP × %dS | Serpentine SP nodes: %d", ...
                    P,S,numSerpentineThermalNodes);
            elseif CoolingPlateMode == "Side Cooling"
                statusLabel.Text = thermalPackFormatText( ...
                    "Rebuild complete — %dP × %dS | %sH side nodes: %d", ...
                    P,S,state.SideBoundary,numSideThermalNodes);
            elseif CoolingPlateMode == "Forced Air Cooling"
                if state.ProgressiveForcedAirBuilt
                    statusLabel.Text = thermalPackFormatText( ...
                        ["Rebuild complete — %dP × %dS | Progressive Gas: %d battery segments / %d air chambers " ...
                         "| %s airflow (Min→Max fixed) | h %.2f W/(m²·K)"], ...
                        P,S,numel(state.ProgressiveForcedAirSegmentBlocks), ...
                        numel(state.ProgressiveForcedAirChamberBlocks), ...
                        state.ForcedAirAxis, ...
                        state.ForcedAirH_W_m2K);
                else
                    statusLabel.Text = thermalPackFormatText( ...
                        "Rebuild complete — %dP × %dS | Uniform forced air %s | h %.2f W/(m²·K)", ...
                        P,S,state.ForcedAirArrangement,state.ForcedAirH_W_m2K);
                end
            else
                statusLabel.Text = thermalPackFormatText( ...
                    "Rebuild complete — %dP × %dS = %d cells",P,S,N);
            end

            moduleMass_kg = N * massField.Value * MassFactor;
            moduleEnergy_Wh = N * energyField.Value;

        catch ME
            state.NeedsRebuild = true;
            statusLabel.Text = "Battery rebuild failed — rebuild required";
            uialert(fig,getReport(ME,"extended","hyperlinks","off"), ...
                "ThermalPack Rebuild Error");
        end

        rebuildButton.Enable = "on";
        runButton.Enable = "on";
        if ~state.DesignOptimizationRunning
            optimizationRunButton.Enable = "on";
            refreshDesignOptimizationControls();
        end
    end

    function thermalLimitChanged(~,~)
        state.ThermalLimit_C = thermalLimitField.Value;
        statusLabel.Text = thermalPackFormatText( ...
            "Thermal limit set to %.1f °C — applies to Safety Margin KPI.", ...
            state.ThermalLimit_C);
    end

    function cfg = currentSimulationConfig()
        % Refresh forced-air properties before capturing the current
        % configuration so validation and sweep audit data are not stale.
        if string(state.CoolingPlateMode) == "Forced Air Cooling"
            calcCfgForcedAir = forcedAirGeneralCalculation( ...
                state.ForcedAirVelocity_m_s, ...
                state.ForcedAirTemperature_C, ...
                state.ForcedAirPressure_Pa, ...
                state.ForcedAirAxis, ...
                state.ForcedAirWallClearance_mm);
            updateForcedAirStateFromCalculation(calcCfgForcedAir);
        end

        cfg = struct;
        cfg.CellFormat = string(state.CellFormat);
        cfg.NumAssemblies = state.S;
        cfg.CellsPerAssembly = state.P;
        cfg.TotalCells = state.TotalCells;
        cfg.NodesPerCell = round(nodesField.Value);
        cfg.Twarning_C = 45;
        cfg.Tcritical_C = 60;
        cfg.Tlimit_C = thermalLimitField.Value;
        cfg.ForcedAirModel = string(state.ForcedAirModel);
        cfg.ProgressiveForcedAir = state.ProgressiveForcedAirBuilt;
        cfg.ModelName = mdl;
        cfg.ProgressiveSubsystemName = string(get_param(batteryBlock,"Name"));
        cfg.ProgressiveSegmentNames = state.ProgressiveForcedAirSegmentNames;
        cfg.ProgressiveSegmentCellIDs = state.ProgressiveForcedAirSegmentCellIDs;
        cfg.ProgressiveGasFlowSourcePath = state.ProgressiveForcedAirFlowSourceBlock;
        cfg.ProgressiveExpectedMassFlow_kg_s = state.ForcedAirMassFlow_kg_s;
        cfg.ProgressiveGasChamberPaths = state.ProgressiveForcedAirChamberBlocks;
        cfg.ProgressiveChamberPhysicalGroups = state.ProgressiveForcedAirChamberPhysicalGroups;
        cfg.ProgressiveSegmentLengths_m = state.ProgressiveForcedAirSegmentLengths_m;
        cfg.ProgressiveGasVolumes_m3 = state.ProgressiveForcedAirGasVolumes_m3;
        cfg.ProgressiveSegmentAirOrder = state.ProgressiveForcedAirSegmentAirOrder;
        cfg.ProgressiveSegmentSeriesGroup = state.ProgressiveForcedAirSegmentSeriesGroup;
        cfg.ProgressiveSegmentPhysicalGroup = state.ProgressiveForcedAirSegmentPhysicalGroup;
    end

    function [simIn,currentProfileDescription] = buildThermalSimulationInput( ...
            cfg,flowValue,tin_C)
        %% Build one simulation case from the CURRENT ThermalPack app state.
        % This single path is shared by RUN SIMULATION and the cooling
        % optimizer so Cylindrical, Prismatic and Pouch use identical physics.
        simIn = Simulink.SimulationInput(mdl);

        editorCurrentProfile = state.CustomCurrentProfile;
        keepLastAtTime = [diff(editorCurrentProfile(:,1)) ~= 0; true];
        CurrentProfile = editorCurrentProfile(keepLastAtTime,:);

        currentProfileDescription = thermalPackFormatText( ...
            "Custom (%d editor points, %d simulation breakpoints, %.0f s)", ...
            size(editorCurrentProfile,1), ...
            size(CurrentProfile,1), ...
            editorCurrentProfile(end,1));

        simIn = simIn.setVariable( ...
            "CurrentProfile",CurrentProfile,"Workspace",mdl);

        % Cell -> plate resistance stays physical/unchanged. Surface
        % activation is handled by the separate cooling isolation Rth.
        effectiveCoolantR_K_W = coolantRField.Value;

        if string(state.CoolingPlateMode) == "Forced Air Cooling"
            calcForcedAir = forcedAirGeneralCalculation( ...
                state.ForcedAirVelocity_m_s, ...
                state.ForcedAirTemperature_C, ...
                state.ForcedAirPressure_Pa, ...
                state.ForcedAirAxis, ...
                state.ForcedAirWallClearance_mm);
            updateForcedAirStateFromCalculation(calcForcedAir);
            ambientField.Value = state.ForcedAirTemperature_C;
            ambientRField.Value = state.ForcedAirAmbientRth_K_W;
            if state.ProgressiveForcedAirBuilt
                updateProgressiveForcedAirOperatingPoint(calcForcedAir);
                applyProgressiveAmbientResistanceToBlocks();
            end
        end

        [topFlow,bottomFlow,serpentineFlow,sideFlow,totalFlow] = ...
            resolveCoolingFlows(flowValue);
        state.LastTopCoolantFlow = topFlow;
        state.LastBottomCoolantFlow = bottomFlow;
        state.LastSerpentineCoolantFlow = serpentineFlow;
        state.LastSideCoolantFlow = sideFlow;
        state.LastTotalCoolantFlow = totalFlow;

        sideFlows = zeros(1,numel(sideBoundaryNames));
        if string(state.CoolingPlateMode) == "Side Cooling"
            idx = find(sideBoundaryNames == state.SideBoundary,1);
            sideFlows(idx) = sideFlow;
        end

        if state.FlowRateType == "Mass flow rate"
            simIn = simIn.setVariable( ...
                "mdot_coolant_top",topFlow,"Workspace",mdl);
            simIn = simIn.setVariable( ...
                "mdot_coolant_bottom",bottomFlow,"Workspace",mdl);
            simIn = simIn.setVariable( ...
                "mdot_coolant_serpentine",serpentineFlow,"Workspace",mdl);

            for kSide = 1:numel(sideBoundaryNames)
                simIn = simIn.setVariable( ...
                    "mdot_coolant_" + sideBoundaryNames(kSide), ...
                    sideFlows(kSide),"Workspace",mdl);
            end
        else
            simIn = simIn.setVariable( ...
                "qdot_coolant_top",topFlow,"Workspace",mdl);
            simIn = simIn.setVariable( ...
                "qdot_coolant_bottom",bottomFlow,"Workspace",mdl);
            simIn = simIn.setVariable( ...
                "qdot_coolant_serpentine",serpentineFlow,"Workspace",mdl);

            for kSide = 1:numel(sideBoundaryNames)
                simIn = simIn.setVariable( ...
                    "qdot_coolant_" + sideBoundaryNames(kSide), ...
                    sideFlows(kSide),"Workspace",mdl);
            end
        end

        if ~state.ProgressiveForcedAirBuilt
            [bottomFlowSourceBlock,topFlowSourceBlock] = ...
                findDualFlowRateSourceBlocks(mdl);

            if strlength(bottomFlowSourceBlock) > 0
                simIn = applyFlowSourceSettingsToSimulationInputNamed( ...
                    simIn,bottomFlowSourceBlock,state, ...
                    "mdot_coolant_bottom","qdot_coolant_bottom");
            end
            if strlength(topFlowSourceBlock) > 0
                simIn = applyFlowSourceSettingsToSimulationInputNamed( ...
                    simIn,topFlowSourceBlock,state, ...
                    "mdot_coolant_top","qdot_coolant_top");
            end
            if getSimulinkBlockHandle(serpentineFlowSourceBlock) > 0
                simIn = applyFlowSourceSettingsToSimulationInputNamed( ...
                    simIn,serpentineFlowSourceBlock,state, ...
                    "mdot_coolant_serpentine","qdot_coolant_serpentine");
            end
            for kSide = 1:numel(sideBoundaryNames)
                if getSimulinkBlockHandle(sideFlowSourceBlocks(kSide)) > 0
                    simIn = applyFlowSourceSettingsToSimulationInputNamed( ...
                        simIn,sideFlowSourceBlocks(kSide),state, ...
                        "mdot_coolant_" + sideBoundaryNames(kSide), ...
                        "qdot_coolant_" + sideBoundaryNames(kSide));
                end
            end
        end

        simIn = simIn.setVariable( ...
            "T_coolant_bottom_in_K",tin_C + 273.15,"Workspace",mdl);
        simIn = simIn.setVariable( ...
            "T_coolant_top_in_K",tin_C + 273.15,"Workspace",mdl);
        simIn = simIn.setVariable( ...
            "T_coolant_serpentine_in_K",tin_C + 273.15,"Workspace",mdl);
        for kSide = 1:numel(sideBoundaryNames)
            simIn = simIn.setVariable( ...
                "T_coolant_" + sideBoundaryNames(kSide) + "_in_K", ...
                tin_C + 273.15,"Workspace",mdl);
        end
        simIn = simIn.setVariable( ...
            "T_plate_K",state.InitialPlateTemperature_C + 273.15, ...
            "Workspace",mdl);
        simIn = simIn.setVariable( ...
            "Area_coolant_bottom_port_in_m2",state.CoolantPortArea_m2, ...
            "Workspace",mdl);
        simIn = simIn.setVariable( ...
            "Area_coolant_top_port_in_m2",state.CoolantPortArea_m2, ...
            "Workspace",mdl);
        simIn = simIn.setVariable( ...
            "Area_coolant_serpentine_port_in_m2",state.CoolantPortArea_m2, ...
            "Workspace",mdl);
        for kSide = 1:numel(sideBoundaryNames)
            simIn = simIn.setVariable( ...
                "Area_coolant_" + sideBoundaryNames(kSide) + "_port_in_m2", ...
                state.CoolantPortArea_m2,"Workspace",mdl);
        end
        simIn = simIn.setVariable( ...
            "T_ambient_K",ambientField.Value + 273.15,"Workspace",mdl);
        simIn = simIn.setVariable( ...
            "Atmospheric_pressure_in_Pa",state.AtmosphericPressure_Pa, ...
            "Workspace",mdl);
        simIn = simIn.setVariable( ...
            "SOC0",socField.Value,"Workspace",mdl);

        if ~state.ProgressiveForcedAirBuilt
            simIn = applyCoolingPlateSettingsToSimulationInput( ...
                simIn,bottomPlateBlock,state);
            simIn = applyCoolingPlateSettingsToSimulationInput( ...
                simIn,topPlateBlock,state);
            if getSimulinkBlockHandle(serpentinePlateBlock) > 0
                serpPlateState = state;
                serpPlateState.CoolingPlateType = "Parallel Channels";
                simIn = applyCoolingPlateSettingsToSimulationInput( ...
                    simIn,serpentinePlateBlock,serpPlateState);
            end
            sidePlateState = state;
            sidePlateState.CoolingPlateType = "Parallel Channels";
            for kSide = 1:numel(sideBoundaryNames)
                if getSimulinkBlockHandle(sidePlateBlocks(kSide)) > 0
                    simIn = applyCoolingPlateSettingsToSimulationInput( ...
                        simIn,sidePlateBlocks(kSide),sidePlateState);
                end
            end

            thermalLiquidBlocks = findThermalLiquidPropertiesBlocks(mdl);
            for kTL = 1:numel(thermalLiquidBlocks)
                simIn = applyCoolantPropertiesToSimulationInput( ...
                    simIn,thermalLiquidBlocks(kTL),state);
            end

            bottomReservoirBlock = bottomInletReservoirBlock;
            topReservoirBlock = topInletReservoirBlock;

            simIn = configureInletReservoirOnSimulationInput( ...
                simIn,bottomReservoirBlock,state, ...
                "T_coolant_bottom_in_K","Area_coolant_bottom_port_in_m2");
            simIn = configureInletReservoirOnSimulationInput( ...
                simIn,topReservoirBlock,state, ...
                "T_coolant_top_in_K","Area_coolant_top_port_in_m2");
            if getSimulinkBlockHandle(serpentineInletReservoirBlock) > 0
                simIn = configureInletReservoirOnSimulationInput( ...
                    simIn,serpentineInletReservoirBlock,state, ...
                    "T_coolant_serpentine_in_K", ...
                    "Area_coolant_serpentine_port_in_m2");
            end
            for kSide = 1:numel(sideBoundaryNames)
                if getSimulinkBlockHandle(sideInletReservoirBlocks(kSide)) > 0
                    simIn = configureInletReservoirOnSimulationInput( ...
                        simIn,sideInletReservoirBlocks(kSide),state, ...
                        "T_coolant_" + sideBoundaryNames(kSide) + "_in_K", ...
                        "Area_coolant_" + sideBoundaryNames(kSide) + "_port_in_m2");
                end
            end
        end

        if state.ProgressiveForcedAirBuilt
            simIn = applyProgressiveBatteryParametersToSimulationInput(simIn,cfg);
        else
                    applyInitialSOCToBlock( ...
                        batteryBlock,socField.Value,state.TotalCells,cfg.NumAssemblies);
                    verifyInitialSOCOnBlock( ...
                        batteryBlock,socField.Value,state.TotalCells,cfg.NumAssemblies);
                    simIn = setInitialSOCOnSimulationInput( ...
                        simIn,batteryBlock,socField.Value, ...
                        state.TotalCells,cfg.NumAssemblies);
                    simIn = simIn.setBlockParameter(batteryBlock, ...
                        "batteryTemperature", ...
                        thermalPackFormatText("repmat(%.16g,%d,1)", ...
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
                        "CrossSectionalAreaXYCell",num2str(thermalAreaField.Value,16));

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
                    simIn = setSimInputElectrochemicalDynamics( ...
                        simIn,batteryBlock,state);

                    r0DevRun = resizeNumericVector(state.R0Deviation_pct,state.TotalCells,0);
                    tmDevRun = resizeNumericVector(state.ThermalMassDeviation_pct,state.TotalCells,0);
                    kDevRun = resizeNumericVector( ...
                        state.ThermalConductivityDeviation_pct,state.TotalCells,0);

                    % These deviation fields are not guaranteed to exist on
                    % every generated cell/module topology or MATLAB release.
                    [simIn,~] = setOptionalSimInputBlockParameter( ...
                        simIn,batteryBlock,"R0ThermalCellPercentDeviation", ...
                        mat2str(r0DevRun,16));
                    [simIn,~] = setOptionalSimInputBlockParameter( ...
                        simIn,batteryBlock,"BatteryThermalMassCellPercentDeviation", ...
                        mat2str(tmDevRun,16));
                    [simIn,~] = setOptionalSimInputBlockParameter( ...
                        simIn,batteryBlock,"ThermalConductivityZCellPercentDeviation", ...
                        mat2str(kDevRun,16));

                    simIn = simIn.setBlockParameter(batteryBlock, ...
                        "CoolantResistance",num2str(effectiveCoolantR_K_W,16));

                    if string(state.CoolingPlateMode) == "Serpentine Cooling"
                        serpentineRthParam = dialogParameterNameByPrompt( ...
                            batteryBlock, ...
                            "Cell-level thermal path resistance at serpentine boundary");
                        if strlength(serpentineRthParam) == 0
                            error("ThermalPack:SerpentineResistanceParameter", ...
                                "Could not resolve the generated serpentine resistance parameter.");
                        end
                        simIn = simIn.setBlockParameter(batteryBlock, ...
                            char(serpentineRthParam), ...
                            num2str(state.SerpentineContactRth_K_W,16));
                    end

                    % Side thermal resistance parameters are generated
                    % conditionally. Apply every available side parameter, but
                    % require the selected one only when Side Cooling is active.
                    for kSide = 1:numel(sideBoundaryNames)
                        sidePrompt = "Cell-level thermal path resistance at " + ...
                            sideBoundaryNames(kSide) + " boundary";
                        sideRthParam = dialogParameterNameByPrompt( ...
                            batteryBlock,sidePrompt);

                        if strlength(sideRthParam) == 0
                            selectedSideRequired = ...
                                string(state.CoolingPlateMode) == "Side Cooling" && ...
                                string(state.SideBoundary) == sideBoundaryNames(kSide);
                            if selectedSideRequired
                                error("ThermalPack:SideResistanceParameter", ...
                                    ["Side Cooling is selected at %s, but the generated " ...
                                     "battery block does not expose that side-boundary " ...
                                     "thermal resistance. Rebuild with a compatible side " ...
                                     "thermal boundary."],sideBoundaryNames(kSide));
                            end
                            continue;
                        end

                        simIn = simIn.setBlockParameter(batteryBlock, ...
                            char(sideRthParam), ...
                            num2str(state.SideContactRth_K_W,16));
                    end

        end

        if ~state.ProgressiveForcedAirBuilt
            [topIsolationRth,bottomIsolationRth,serpentineIsolationRth,sideIsolationRths] = ...
                resolveCoolingIsolationRth();
            simIn = simIn.setBlockParameter(topIsolationBlock, ...
                "R",num2str(topIsolationRth,16));
            simIn = simIn.setBlockParameter(bottomIsolationBlock, ...
                "R",num2str(bottomIsolationRth,16));
            if getSimulinkBlockHandle(serpentineIsolationBlock) > 0
                simIn = simIn.setBlockParameter(serpentineIsolationBlock, ...
                    "R",num2str(serpentineIsolationRth,16));
            end
            for kSide = 1:numel(sideBoundaryNames)
                if getSimulinkBlockHandle(sideIsolationBlocks(kSide)) > 0
                    simIn = simIn.setBlockParameter(sideIsolationBlocks(kSide), ...
                        "R",num2str(sideIsolationRths(kSide),16));
                end
            end
        end

        if ~state.ProgressiveForcedAirBuilt
            simIn = simIn.setBlockParameter(batteryBlock, ...
                "AmbientResistance",num2str(ambientRField.Value,16));

            if state.InterCellHeatTransfer == "Enabled"
                % IMPORTANT: SimulationInput.setBlockParameter can accept an
                % unknown generated-mask parameter and only reject it when sim()
                % starts. Therefore try/catch around setBlockParameter is NOT
                % sufficient. Check the concrete generated block first.
                [simIn,interCellApplied] = setOptionalSimInputBlockParameter( ...
                    simIn,batteryBlock,"InterCellThermalResistance", ...
                    num2str(interCellRField.Value,16));

                [simIn,~] = setOptionalSimInputBlockParameter( ...
                    simIn,batteryBlock, ...
                    "InterParallelAssemblyThermalResistance", ...
                    num2str(interParallelRField.Value,16));

                if ~interCellApplied && state.TotalCells > 1
                    warning("ThermalPack:OptionalInterCellResistanceUnavailable", ...
                        ["Generated battery block '%s' does not expose " ...
                         "InterCellThermalResistance. The generated architecture's " ...
                         "native thermal connectivity will be retained."],batteryBlock);
                end
            end
        end

        if state.Solver == "Auto"
            solverName = "VariableStepAuto";
        else
            solverName = state.Solver;
        end

        simIn = simIn.setModelParameter( ...
            "StopTime",num2str(stopField.Value,16), ...
            "SolverType","Variable-step", ...
            "Solver",solverName, ...
            "SimscapeLogType","all", ...
            "SimscapeLogName","simlog", ...
            "ReturnWorkspaceOutputs","on");
    end

    function storeOptimizationRanges()
        bounds = [optFlowMinField.Value,optFlowMaxField.Value,optFlowStepField.Value];
        if optRangeMode == "air"
            state.OptimizationAirRange = bounds;
        elseif optRangeMode == "liquid"
            state.OptimizationLiquidRange = bounds;
        end
        state.OptimizationInletRange = ...
            [optTinMinField.Value,optTinMaxField.Value,optTinStepField.Value];
        state.OptimizationTopFlowShareRange = ...
            [optSplitMinField.Value,optSplitMaxField.Value,optSplitStepField.Value];
    end

    function optimizationRangeChanged(~,~)
        storeOptimizationRanges();
        refreshOptimizationCaseCount();
    end

    function showCoolingSelectionCriteria(~,~)
        state.CoolingSelectionOrder = thermalPackNormalizeSelectionOrder( ...
            state.CoolingSelectionOrder,"cooling");
        openSelectionCriteriaEditor("cooling",state.CoolingSelectionOrder);
    end

    function showDesignSelectionCriteria(~,~)
        spec = designOptimizationSpec();
        if spec.Count == 0
            uialert(fig,"Select a cooling architecture first.", ...
                "Design Optimization — Selection Criteria","Icon","info");
            return;
        end
        state.DesignSelectionOrder = thermalPackNormalizeSelectionOrder( ...
            state.DesignSelectionOrder,"design");
        openSelectionCriteriaEditor("design",state.DesignSelectionOrder);
    end

    function labels = selectionCriterionLabels(kind,order)
        order = thermalPackNormalizeSelectionOrder(order,kind);
        labels = strings(size(order));
        for kCriterion = 1:numel(order)
            switch order(kCriterion)
                case "PeakT"
                    labels(kCriterion) = "Peak Nodal Temperature";
                case "CellDelta"
                    labels(kCriterion) = "Cell-to-Cell ΔT";
                case "WithinDelta"
                    labels(kCriterion) = "Within-Cell ΔT";
                case "Operating"
                    if string(coolingPlateField.Value) == "Forced Air Cooling"
                        labels(kCriterion) = "Air Velocity";
                    else
                        labels(kCriterion) = "Coolant Flow Rate";
                    end
                case "DesignParameters"
                    labels(kCriterion) = "Design-Parameter Values";
            end
        end
    end

    function openSelectionCriteriaEditor(kind,order)
        windowTitle = "SELECTION CRITERIA";
        parentPosition = fig.Position;
        windowWidth = min(660,max(560,parentPosition(3)-400));
        windowHeight = min(440,max(400,parentPosition(4)-320));
        windowLeft = parentPosition(1) + (parentPosition(3)-windowWidth)/2;
        windowBottom = parentPosition(2) + (parentPosition(4)-windowHeight)/2;
        criteriaFig = uifigure("Name",windowTitle,"WindowStyle","modal", ...
            "Position",[windowLeft windowBottom windowWidth windowHeight]);
        criteriaFig.UserData = struct("Kind",kind,"Keys",order);
        movegui(criteriaFig,"onscreen");

        criteriaGrid = uigridlayout(criteriaFig,[5 1]);
        criteriaGrid.RowHeight = {44,62,'1x',36,38};
        criteriaGrid.Padding = [16 16 16 16];
        criteriaGrid.RowSpacing = 8;

        header = uilabel(criteriaGrid,"Text","SELECTION CRITERIA", ...
            "FontSize",18,"FontWeight","bold","HorizontalAlignment","center");
        header.Layout.Row = 1;
        instruction = uilabel(criteriaGrid, ...
            "Text","Only completed cases that pass both design limits are considered. " + ...
            "The highest-priority criterion is at the top; lower values are preferred.", ...
            "WordWrap","on","HorizontalAlignment","center");
        instruction.Layout.Row = 2;

        labels = selectionCriterionLabels(kind,order);
        criterionList = uilistbox(criteriaGrid,"Items",cellstr(labels), ...
            "Value",char(labels(1)),"FontSize",14);
        criterionList.Layout.Row = 3;

        moveButtons = uigridlayout(criteriaGrid,[1 3]);
        moveButtons.Layout.Row = 4;
        moveButtons.ColumnWidth = {'1x','1x','1x'};
        moveButtons.Padding = [0 0 0 0];
        uibutton(moveButtons,"push","Text","MOVE UP", ...
            "ButtonPushedFcn",@(src,event)moveSelectionCriterion( ...
            criteriaFig,criterionList,-1)); %#ok<NASGU,INUSD>
        uibutton(moveButtons,"push","Text","MOVE DOWN", ...
            "ButtonPushedFcn",@(src,event)moveSelectionCriterion( ...
            criteriaFig,criterionList,1)); %#ok<NASGU,INUSD>
        uibutton(moveButtons,"push","Text","RESET DEFAULT", ...
            "ButtonPushedFcn",@(src,event)resetSelectionCriterionOrder( ...
            criteriaFig,criterionList)); %#ok<NASGU,INUSD>

        actionButtons = uigridlayout(criteriaGrid,[1 2]);
        actionButtons.Layout.Row = 5;
        actionButtons.ColumnWidth = {'1x','1x'};
        actionButtons.Padding = [0 0 0 0];
        uibutton(actionButtons,"push","Text","APPLY ORDER", ...
            "FontWeight","bold","ButtonPushedFcn", ...
            @(src,event)applySelectionCriterionOrder(criteriaFig)); %#ok<NASGU,INUSD>
        uibutton(actionButtons,"push","Text","CANCEL", ...
            "ButtonPushedFcn",@(src,event)delete(criteriaFig)); %#ok<NASGU,INUSD>
    end

    function moveSelectionCriterion(criteriaFig,criterionList,direction)
        labels = string(criterionList.Items);
        selectedLabel = string(criterionList.Value);
        selectedIndex = find(labels == selectedLabel,1);
        targetIndex = selectedIndex + direction;
        if isempty(selectedIndex) || targetIndex < 1 || targetIndex > numel(labels)
            return;
        end
        userData = criteriaFig.UserData;
        userData.Keys([selectedIndex targetIndex]) = ...
            userData.Keys([targetIndex selectedIndex]);
        criteriaFig.UserData = userData;
        labels = selectionCriterionLabels(userData.Kind,userData.Keys);
        criterionList.Items = cellstr(labels);
        criterionList.Value = char(labels(targetIndex));
    end

    function resetSelectionCriterionOrder(criteriaFig,criterionList)
        userData = criteriaFig.UserData;
        userData.Keys = thermalPackDefaultSelectionOrder(userData.Kind);
        criteriaFig.UserData = userData;
        labels = selectionCriterionLabels(userData.Kind,userData.Keys);
        criterionList.Items = cellstr(labels);
        criterionList.Value = char(labels(1));
    end

    function applySelectionCriterionOrder(criteriaFig)
        userData = criteriaFig.UserData;
        order = thermalPackNormalizeSelectionOrder( ...
            userData.Keys,userData.Kind);
        if userData.Kind == "cooling"
            state.CoolingSelectionOrder = order;
            if ~isempty(state.LastOptimizationResults)
                [results,recommendations] = thermalPackOperatingRecommendations( ...
                    state.LastOptimizationResults,order);
                state.LastOptimizationResults = results;
                state.LastRecommendedCase = recommendations;
                if isstruct(state.LastOptimizationSettings)
                    state.LastOptimizationSettings.SelectionOrder = order;
                end
                showOptimizationTable(results);
                refreshSweepAnalysisPlots(results);
            end
        else
            state.DesignSelectionOrder = order;
            if ~isempty(state.LastDesignOptimizationResults)
                [results,recommendation] = thermalPackDesignRecommendations( ...
                    state.LastDesignOptimizationResults,order);
                state.LastDesignOptimizationResults = results;
                state.LastRecommendedDesign = recommendation;
                if isstruct(state.LastDesignOptimizationSettings)
                    state.LastDesignOptimizationSettings.SelectionOrder = order;
                end
                showDesignOptimizationTable(results);
                refreshDesignOptimizationPlots(results);
            end
        end
        delete(criteriaFig);
    end

    function openOptimizationDesignLimits(~,~)
        parentPosition = fig.Position;
        windowWidth = min(980,max(820,parentPosition(3)-120));
        windowHeight = min(410,max(360,parentPosition(4)-420));
        windowLeft = parentPosition(1) + (parentPosition(3)-windowWidth)/2;
        windowBottom = parentPosition(2) + (parentPosition(4)-windowHeight)/2;
        designFig = uifigure( ...
            "Name","ThermalPack — Shared Optimization Design Limits", ...
            "WindowStyle","modal", ...
            "Position",[windowLeft windowBottom windowWidth windowHeight]);
        designFig.UserData = struct("ThermalPackOwner",fig);
        movegui(designFig,"onscreen");

        designGrid = uigridlayout(designFig,[5 1]);
        designGrid.RowHeight = {42,92,92,28,42};
        designGrid.ColumnWidth = {'1x'};
        designGrid.Padding = [16 16 16 16];
        designGrid.RowSpacing = 6;

        designHeader = uilabel(designGrid, ...
            "Text","COOLING AND DESIGN OPTIMIZATION — SHARED LIMITS", ...
            "FontSize",18,"FontWeight","bold", ...
            "HorizontalAlignment","center");
        designHeader.Layout.Row = 1;

        peakPanel = uipanel(designGrid,"Title","Peak Nodal Temperature");
        peakPanel.Layout.Row = 2;
        peakGrid = uigridlayout(peakPanel,[2 2]);
        peakGrid.RowHeight = {32,28};
        peakGrid.ColumnWidth = {230,'1x'};
        peakGrid.Padding = [10 4 10 4];
        peakGrid.RowSpacing = 2;
        peakLabel = uilabel(peakGrid,"Text","Maximum allowed temperature (°C)", ...
            "FontWeight","bold");
        peakLabel.Layout.Row = 1; peakLabel.Layout.Column = 1;
        peakLimitEdit = uieditfield(peakGrid,"numeric", ...
            "Value",optLimitField.Value);
        peakLimitEdit.Layout.Row = 1; peakLimitEdit.Layout.Column = 2;
        peakDefinition = uilabel(peakGrid, ...
            "Text","Highest temperature reached by any cell thermal node during the complete simulation.", ...
            "WordWrap","off","VerticalAlignment","center");
        peakDefinition.Layout.Row = 2; peakDefinition.Layout.Column = [1 2];

        uniformityPanel = uipanel(designGrid, ...
            "Title","Maximum Cell-to-Cell Temperature Difference");
        uniformityPanel.Layout.Row = 3;
        uniformityGrid = uigridlayout(uniformityPanel,[2 2]);
        uniformityGrid.RowHeight = {32,28};
        uniformityGrid.ColumnWidth = {230,'1x'};
        uniformityGrid.Padding = [10 4 10 4];
        uniformityGrid.RowSpacing = 2;
        uniformityLabel = uilabel(uniformityGrid, ...
            "Text","Maximum allowed cell ΔT (°C)","FontWeight","bold");
        uniformityLabel.Layout.Row = 1; uniformityLabel.Layout.Column = 1;
        uniformityLimitEdit = uieditfield(uniformityGrid,"numeric", ...
            "Value",optUniformityField.Value);
        uniformityLimitEdit.Layout.Row = 1; uniformityLimitEdit.Layout.Column = 2;
        uniformityDefinition = uilabel(uniformityGrid, ...
            "Text","Largest difference between the hottest and coldest cell-average temperatures during the complete simulation.", ...
            "WordWrap","off","VerticalAlignment","center");
        uniformityDefinition.Layout.Row = 2;
        uniformityDefinition.Layout.Column = [1 2];

        designNote = uilabel(designGrid, ...
            "Text","Both limits must pass. Within-cell ΔT is reported separately and is not currently a pass/fail constraint.", ...
            "WordWrap","off","FontAngle","italic", ...
            "VerticalAlignment","center");
        designNote.Layout.Row = 4;

        designButtons = uigridlayout(designGrid,[1 2]);
        designButtons.Layout.Row = 5;
        designButtons.ColumnWidth = {'1x','1x'};
        designButtons.Padding = [0 0 0 0];
        applyDesignButton = uibutton(designButtons,"push", ...
            "Text","APPLY LIMITS","FontWeight","bold", ...
            "ButtonPushedFcn",@(src,event)applyOptimizationDesignLimits( ...
            designFig,peakLimitEdit,uniformityLimitEdit)); %#ok<NASGU,INUSD>
        cancelDesignButton = uibutton(designButtons,"push", ...
            "Text","CANCEL", ...
            "ButtonPushedFcn",@(src,event)delete(designFig)); %#ok<NASGU,INUSD>
    end

    function applyOptimizationDesignLimits(designFig,peakLimitEdit,uniformityLimitEdit)
        thermalLimit_C = peakLimitEdit.Value;
        uniformityLimit_C = uniformityLimitEdit.Value;
        if ~isfinite(thermalLimit_C) || thermalLimit_C <= -273.15
            uialert(designFig, ...
                "Peak nodal temperature limit must be finite and above absolute zero.", ...
                "ThermalPack — Invalid Design Limit");
            return;
        end
        if ~isfinite(uniformityLimit_C) || uniformityLimit_C < 0
            uialert(designFig, ...
                "Cell-to-cell temperature-difference limit must be finite and nonnegative.", ...
                "ThermalPack — Invalid Design Limit");
            return;
        end
        optLimitField.Value = thermalLimit_C;
        optUniformityField.Value = uniformityLimit_C;
        refreshOptimizationDesignLimitsButton();
        delete(designFig);
    end

    function refreshOptimizationDesignLimitsButton()
        if ~exist('optimizationDesignLimitsButton','var') || ...
                isempty(optimizationDesignLimitsButton) || ...
                ~isvalid(optimizationDesignLimitsButton)
            return;
        end
        optimizationDesignLimitsButton.Text = thermalPackFormatText( ...
            "DESIGN LIMITS  |  Peak nodal T ≤ %.4g °C  |  Cell-to-cell ΔT ≤ %.4g °C", ...
            optLimitField.Value,optUniformityField.Value);
        if exist('designOptimizationLimitsButton','var') && ...
                ~isempty(designOptimizationLimitsButton) && ...
                isvalid(designOptimizationLimitsButton)
            designOptimizationLimitsButton.Text = thermalPackFormatText( ...
                "DESIGN LIMITS  |  Peak nodal T ≤ %.4g °C  |  Cell-to-cell ΔT ≤ %.4g °C", ...
                optLimitField.Value,optUniformityField.Value);
        end
    end

    function refreshOptimizationControls()
        % coolingModeChanged can be called before these controls are created.
        if ~exist('optFlowMinField','var') || isempty(optFlowMinField) || ...
                ~isvalid(optFlowMinField)
            return;
        end
        selectedMode = string(coolingPlateField.Value);
        topBottomMode = selectedMode == "Top + Bottom Cooling";
        if selectedMode == "Forced Air Cooling"
            nextMode = "air";
            optFlowLabel.Text = "Air inlet velocity (m/s)";
            optTinLabel.Text = "Air inlet temperature (°C)";
            optObjectiveText.Text = [ ...
                "Fixed: battery geometry, air model, direction, clearance and load. " ...
                "Fan power is not evaluated."];
        else
            nextMode = "liquid";
            if selectedMode == "Top Cooling Plate"
                optFlowLabel.Text = "Top coolant flow (kg/s)";
            elseif selectedMode == "Bottom Cooling Plate"
                optFlowLabel.Text = "Bottom coolant flow (kg/s)";
            elseif selectedMode == "Side Cooling"
                optFlowLabel.Text = "Side coolant flow (kg/s)";
            elseif selectedMode == "Serpentine Cooling"
                optFlowLabel.Text = "Serpentine flow (kg/s)";
            else
                optFlowLabel.Text = "Total coolant flow (kg/s)";
            end
            optTinLabel.Text = "Coolant inlet temperature (°C)";
            optObjectiveText.Text = [ ...
                "Fixed: battery geometry, plate design, coolant properties and load. " ...
                "Pump power is not evaluated."];
        end
        splitControls = [optSplitLabel,optSplitMinField, ...
            optSplitMaxField,optSplitStepField];
        if topBottomMode
            for kSplitControl = 1:numel(splitControls)
                splitControls(kSplitControl).Visible = "on";
            end
            optObjectiveText.Text = [ ...
                "Top + Bottom sweep varies total flow, coolant inlet temperature and top-flow share. " ...
                "Pump power is not evaluated."];
        else
            for kSplitControl = 1:numel(splitControls)
                splitControls(kSplitControl).Visible = "off";
            end
        end
        if optRangeMode ~= nextMode
            if strlength(optRangeMode) > 0
                storeOptimizationRanges();
            end
            optRangeMode = nextMode;
            if optRangeMode == "air"
                bounds = state.OptimizationAirRange;
            else
                bounds = state.OptimizationLiquidRange;
            end
            optFlowMinField.Value = bounds(1);
            optFlowMaxField.Value = bounds(2);
            optFlowStepField.Value = bounds(3);
            bounds = state.OptimizationInletRange;
            optTinMinField.Value = bounds(1);
            optTinMaxField.Value = bounds(2);
            optTinStepField.Value = bounds(3);
        end
        splitBounds = state.OptimizationTopFlowShareRange;
        optSplitMinField.Value = splitBounds(1);
        optSplitMaxField.Value = splitBounds(2);
        optSplitStepField.Value = splitBounds(3);
        refreshOptimizationCaseCount();
        refreshOptimizationDesignLimitsButton();
    end

    function spec = designOptimizationSpec()
        mode = string(coolingPlateField.Value);
        spec = struct("Mode",mode,"RangeKey","","Count",2, ...
            "Labels",strings(1,3),"Units",strings(1,3), ...
            "PositiveOnly",false(1,3),"Structural",false);
        if mode == "Forced Air Cooling"
            spec.RangeKey = "ForcedAir";
            spec.Labels = ["Inter-cell gap (mm)", ...
                "Cell-to-Duct Wall Gap (mm)",""];
            spec.Units = ["mm","mm",""];
            spec.PositiveOnly = [false false false];
            spec.Structural = true;
        elseif any(mode == ["Top Cooling Plate","Bottom Cooling Plate", ...
                "Top + Bottom Cooling"])
            spec.RangeKey = "Plate";
            spec.Labels = ["Cooling plate thickness (mm)", ...
                "Cell-to-plate Rth (K/W)",""];
            spec.Units = ["mm","K/W",""];
            spec.PositiveOnly = [true false false];
        elseif mode == "Side Cooling"
            spec.RangeKey = "Side";
            spec.Labels = ["Side-contact height fraction", ...
                "Cell-to-side Rth (K/W)",""];
            spec.Units = ["fraction","K/W",""];
            spec.PositiveOnly = [true true false];
            spec.Structural = true;
        elseif mode == "Serpentine Cooling"
            spec.RangeKey = "Serpentine";
            spec.Count = 3;
            spec.Labels = ["Contact height fraction", ...
                "Circumference fraction","Cell-to-serpentine Rth (K/W)"];
            spec.Units = ["fraction","fraction","K/W"];
            spec.PositiveOnly = [true true true];
            spec.Structural = true;
        else
            spec.RangeKey = "";
            spec.Count = 0;
            spec.Labels = ["Select a cooling architecture","",""];
        end
    end

    function storeDesignOptimizationRanges()
        if strlength(designRangeMode) == 0 || ...
                ~isfield(state.DesignOptimizationRanges,char(designRangeMode))
            return;
        end
        ranges = zeros(3,3);
        for kVariable = 1:3
            ranges(kVariable,:) = [designMinFields(kVariable).Value, ...
                designMaxFields(kVariable).Value, ...
                designStepFields(kVariable).Value];
        end
        state.DesignOptimizationRanges.(char(designRangeMode)) = ranges;
    end

    function designOptimizationRangeChanged(~,~)
        storeDesignOptimizationRanges();
        refreshDesignOptimizationCaseCount();
    end

    function refreshDesignOptimizationControls()
        if ~exist('designMinFields','var') || isempty(designMinFields) || ...
                ~all(isvalid(designMinFields))
            return;
        end
        spec = designOptimizationSpec();
        nextMode = string(spec.RangeKey);
        if designRangeMode ~= nextMode
            if strlength(designRangeMode) > 0
                storeDesignOptimizationRanges();
            end
            designRangeMode = nextMode;
            if strlength(nextMode) > 0
                ranges = state.DesignOptimizationRanges.(char(nextMode));
                for kVariable = 1:3
                    designMinFields(kVariable).Value = ranges(kVariable,1);
                    designMaxFields(kVariable).Value = ranges(kVariable,2);
                    designStepFields(kVariable).Value = ranges(kVariable,3);
                end
            end
        end
        for kVariable = 1:3
            visibleNow = kVariable <= spec.Count;
            designVariableLabels(kVariable).Visible = visibleNow;
            designMinFields(kVariable).Visible = visibleNow;
            designMaxFields(kVariable).Visible = visibleNow;
            designStepFields(kVariable).Visible = visibleNow;
            if visibleNow
                designVariableLabels(kVariable).Text = spec.Labels(kVariable);
            end
        end
        if spec.Mode == "Forced Air Cooling"
            designObjectiveText.Text = [ ...
                "Fixed: air velocity, inlet temperature, airflow direction, model and load. " ...
                "Each cell-gap case rebuilds the battery; fan power is not evaluated."];
        elseif any(spec.Mode == ["Top Cooling Plate","Bottom Cooling Plate", ...
                "Top + Bottom Cooling"])
            designObjectiveText.Text = [ ...
                "Fixed: coolant flow, inlet temperature, channel design, material and load. " ...
                "Pump power is not evaluated."];
        elseif spec.Mode == "Side Cooling"
            designObjectiveText.Text = [ ...
                "Fixed: side boundary, coolant operating point, plate/channel design and load. " ...
                "Contact-height cases rebuild the battery."];
        elseif spec.Mode == "Serpentine Cooling"
            designObjectiveText.Text = [ ...
                "Fixed: coolant operating point, plate/channel design and load. " ...
                "Contact-geometry cases rebuild the battery."];
        else
            designObjectiveText.Text = ...
                "Select a supported cooling architecture in the main setup.";
        end
        if spec.Count > 0 && ~state.OptimizationRunning && ...
                ~state.DesignOptimizationRunning
            designOptimizationRunButton.Enable = "on";
        else
            designOptimizationRunButton.Enable = "off";
        end
        refreshDesignOptimizationCaseCount();
        refreshOptimizationDesignLimitsButton();
    end

    function [values,spec] = designOptimizationGridValues()
        spec = designOptimizationSpec();
        if spec.Count == 0
            error("ThermalPack:DesignOptimizationInput", ...
                "Select forced air or a supported liquid-cooling architecture first.");
        end
        values = cell(1,spec.Count);
        for kVariable = 1:spec.Count
            values{kVariable} = thermalPackOperatingRange( ...
                [designMinFields(kVariable).Value, ...
                 designMaxFields(kVariable).Value, ...
                 designStepFields(kVariable).Value], ...
                spec.Labels(kVariable),spec.PositiveOnly(kVariable));
        end
        if spec.Mode == "Forced Air Cooling"
            if any(values{1} < 0) || any(values{2} < 0)
                error("ThermalPack:DesignOptimizationInput", ...
                    "Inter-cell gap and cell-to-duct wall gap must be nonnegative.");
            end
        elseif any(spec.Mode == ["Top Cooling Plate","Bottom Cooling Plate", ...
                "Top + Bottom Cooling"])
            if any(values{2} < 0)
                error("ThermalPack:DesignOptimizationInput", ...
                    "Cell-to-plate thermal resistance must be nonnegative.");
            end
        elseif spec.Mode == "Side Cooling"
            if any(values{1} <= 0 | values{1} > 1)
                error("ThermalPack:DesignOptimizationInput", ...
                    "Side-contact height fraction must be greater than 0 and at most 1.");
            end
        elseif spec.Mode == "Serpentine Cooling"
            if any(values{1} <= 0 | values{1} > 1) || ...
                    any(values{2} <= 0 | values{2} > 0.5)
                error("ThermalPack:DesignOptimizationInput", ...
                    "Serpentine height fraction must be in (0,1] and circumference fraction in (0,0.5].");
            end
        end
        nCases = prod(cellfun(@numel,values));
        if nCases > 10000
            error("ThermalPack:DesignOptimizationInput", ...
                "Use at most 10000 design cases. Increase a step or narrow a range.");
        end
    end

    function refreshDesignOptimizationCaseCount()
        try
            [values,spec] = designOptimizationGridValues();
            counts = cellfun(@numel,values);
            if spec.Count == 2
                designOptimizationCaseCount.Text = thermalPackFormatText( ...
                    "%d × %d = %d",counts(1),counts(2),prod(counts));
            else
                designOptimizationCaseCount.Text = thermalPackFormatText( ...
                    "%d × %d × %d = %d",counts(1),counts(2),counts(3),prod(counts));
            end
        catch
            designOptimizationCaseCount.Text = "Invalid range";
        end
    end

    function [operatingValues,inletTemps,topFlowShares_pct] = optimizationGridValues()
        operatingValues = thermalPackOperatingRange( ...
            [optFlowMinField.Value,optFlowMaxField.Value,optFlowStepField.Value], ...
            "Flow / velocity",true);
        inletTemps = thermalPackOperatingRange( ...
            [optTinMinField.Value,optTinMaxField.Value,optTinStepField.Value], ...
            "Inlet temperature",false);
        if any(inletTemps <= -273.15)
            error("ThermalPack:OptimizationInput", ...
                "Inlet temperatures must be above absolute zero.");
        end
        if string(coolingPlateField.Value) == "Top + Bottom Cooling"
            topFlowShares_pct = thermalPackOperatingRange( ...
                [optSplitMinField.Value,optSplitMaxField.Value,optSplitStepField.Value], ...
                "Top flow share",false);
            if any(topFlowShares_pct < 0) || any(topFlowShares_pct > 100)
                error("ThermalPack:OptimizationInput", ...
                    "Top flow share must remain between 0 and 100 percent.");
            end
        else
            topFlowShares_pct = NaN;
        end
        if numel(operatingValues)*numel(inletTemps)*numel(topFlowShares_pct) > 10000
            error("ThermalPack:OptimizationInput", ...
                "Use at most 10000 cases per sweep. Increase a step or narrow a range.");
        end
    end

    function refreshOptimizationCaseCount()
        try
            [x,tin,split] = optimizationGridValues();
            if string(coolingPlateField.Value) == "Top + Bottom Cooling"
                optimizationCaseCount.Text = thermalPackFormatText( ...
                    "%d × %d × %d = %d",numel(x),numel(tin),numel(split), ...
                    numel(x)*numel(tin)*numel(split));
            else
                optimizationCaseCount.Text = thermalPackFormatText( ...
                    "%d × %d = %d",numel(x),numel(tin),numel(x)*numel(tin));
            end
        catch ME
            optimizationCaseCount.Text = "Invalid range";
        end
    end

    function labelText = optimizationAxisLabel(Results)
        if nargin > 0 && ~isempty(Results)
            mode = Results.CoolingArchitecture(1);
        else
            mode = string(coolingPlateField.Value);
        end
        if mode == "Forced Air Cooling"
            labelText = "Air inlet velocity (m/s)";
        elseif mode == "Top Cooling Plate"
            labelText = "Top coolant mass flow (kg/s)";
        elseif mode == "Bottom Cooling Plate"
            labelText = "Bottom coolant mass flow (kg/s)";
        elseif mode == "Side Cooling"
            labelText = "Side coolant mass flow (kg/s)";
        elseif mode == "Serpentine Cooling"
            labelText = "Serpentine coolant mass flow (kg/s)";
        else
            labelText = "Total liquid mass flow (kg/s)";
        end
    end

    function labelText = optimizationInletTemperatureLabel(Results)
        if nargin > 0 && ~isempty(Results)
            airMode = Results.CoolingArchitecture(1) == "Forced Air Cooling";
        else
            airMode = string(coolingPlateField.Value) == "Forced Air Cooling";
        end
        if airMode
            labelText = "Air inlet temperature (°C)";
        else
            labelText = "Coolant inlet temperature (°C)";
        end
    end

    function labelText = optimizationInletTemperatureTitle(Results)
        if nargin > 0
            labelText = optimizationInletTemperatureLabel(Results);
        else
            labelText = optimizationInletTemperatureLabel();
        end
        labelText = replace(erase(labelText," (°C)"), ...
            "inlet temperature","Inlet Temperature");
    end

    function labelText = optimizationInletLegendLabel(Results,value_C)
        if Results.CoolingArchitecture(1) == "Forced Air Cooling"
            labelText = thermalPackFormatText("Air inlet %.4g °C",value_C);
        else
            labelText = thermalPackFormatText("Coolant inlet %.4g °C",value_C);
        end
    end

    function resetSweepAnalysisPlots(messageText)
        if nargin < 1, messageText = ""; end %#ok<NASGU>
        axesList = [optimizationAxes,sweepTmaxFlowAxes,sweepDeltaFlowAxes, ...
            sweepTmaxHeatmapAxes,sweepSafetyHeatmapAxes];
        for kAx = 1:numel(axesList)
            colorbar(axesList(kAx),"off");
            legend(axesList(kAx),"off");
            cla(axesList(kAx),"reset");
            xlabel(axesList(kAx),optimizationAxisLabel());
            grid(axesList(kAx),"on");
        end
        title(optimizationAxes,"Operating Points — Colour Indicates " + ...
            optimizationInletTemperatureTitle());
        ylabel(optimizationAxes,"Peak nodal temperature (°C)");
        title(sweepTmaxFlowAxes,"Peak Nodal Temperature");
        ylabel(sweepTmaxFlowAxes,"Peak nodal temperature (°C)");
        title(sweepDeltaFlowAxes,"Maximum Cell-to-Cell Temperature Difference");
        ylabel(sweepDeltaFlowAxes,"Maximum cell-to-cell ΔT (°C)");
        title(sweepTmaxHeatmapAxes,"Peak Nodal Temperature (°C)");
        ylabel(sweepTmaxHeatmapAxes,optimizationInletTemperatureLabel());
        title(sweepSafetyHeatmapAxes, ...
            "Both Constraints — Grey Means No Valid Result");
        ylabel(sweepSafetyHeatmapAxes,optimizationInletTemperatureLabel());
    end

    function gridData = sweepMetricGrid(data,operatingValues,tinValues,metricName,shareValues)
        if nargin < 5
            shareValues = [];
        end
        gridData = NaN(numel(tinValues),numel(operatingValues));
        for kRow = 1:height(data)
            if ~data.Success(kRow)
                continue;
            end
            if isempty(shareValues)
                iTin = find(tinValues == data.Tin_C(kRow),1);
            else
                iTin = find(tinValues == data.Tin_C(kRow) & ...
                    shareValues == data.TopFlowShare_pct(kRow),1);
            end
            iX = find(operatingValues == data.OperatingValue(kRow),1);
            gridData(iTin,iX) = double(data.(metricName)(kRow));
        end
    end

    function drawSweepHeatmap(ax,gridData,xValues,tinValues,titleText,xText,yText,isFeasibility,yTickLabels)
        if nargin < 9 || isempty(yTickLabels)
            yTickLabels = string(tinValues);
        else
            yTickLabels = string(yTickLabels);
        end
        colorbar(ax,"off");
        cla(ax,"reset");
        im = imagesc(ax,1:numel(xValues),1:numel(tinValues),gridData);
        im.AlphaData = double(isfinite(gridData));
        ax.Color = [0.85 0.85 0.85];
        ax.YDir = "normal";
        ax.XTick = unique(round(linspace(1,numel(xValues),min(10,numel(xValues)))));
        ax.YTick = unique(round(linspace(1,numel(tinValues),min(10,numel(tinValues)))));
        ax.XTickLabel = string(xValues(ax.XTick));
        ax.YTickLabel = yTickLabels(ax.YTick);
        xlim(ax,[0.5 numel(xValues)+0.5]);
        ylim(ax,[0.5 numel(tinValues)+0.5]);
        xlabel(ax,xText);
        ylabel(ax,yText);
        title(ax,titleText);
        cb = colorbar(ax);
        if isFeasibility
            colormap(ax,[0.80 0.27 0.22;0.15 0.60 0.35]);
            caxis(ax,[-0.5 1.5]);
            cb.Ticks = [0 1];
            cb.TickLabels = {"Fails","Passes"};
        else
            colormap(ax,parula(256));
            cb.Label.String = "Peak nodal temperature (°C)";
        end
        if numel(gridData) <= 100
            for iRow = 1:size(gridData,1)
                for iCol = 1:size(gridData,2)
                    valueHere = gridData(iRow,iCol);
                    if ~isfinite(valueHere)
                        txt = "—";
                    elseif isFeasibility
                        if valueHere == 1, txt = "Pass"; else, txt = "Fail"; end
                    else
                        txt = thermalPackFormatText("%.1f",valueHere);
                    end
                    text(ax,iCol,iRow,txt,"HorizontalAlignment","center", ...
                        "FontWeight","bold","Color",[0 0 0]);
                end
            end
        end
    end

    function limits = sweepPaddedLimits(values)
        values = double(values(:));
        values = values(isfinite(values));
        if isempty(values)
            limits = [];
            return;
        end
        lowValue = min(values);
        highValue = max(values);
        valueSpan = highValue-lowValue;
        valueScale = max(abs([lowValue,highValue]));
        if valueSpan > 0
            padding = 0.06*valueSpan;
        elseif valueScale > 0
            padding = 0.08*valueScale;
        else
            padding = 1;
        end
        limits = [lowValue-padding,highValue+padding];
    end

    function fitSweepAxes(ax,xValues,yValues)
        xLimits = sweepPaddedLimits(xValues);
        finiteX = double(xValues(:));
        finiteX = finiteX(isfinite(finiteX));
        if ~isempty(xLimits) && ~isempty(finiteX) && all(finiteX >= 0)
            xLimits(1) = max(0,xLimits(1));
        end

        finiteY = double(yValues(:));
        finiteY = finiteY(isfinite(finiteY));
        yLimits = [];
        if ~isempty(finiteY)
            lowestY = min(finiteY);
            highestY = max(finiteY);
            ySpan = highestY-lowestY;
            yScale = max(abs([lowestY,highestY]));
            if ySpan > 0
                lowerPadding = 0.05*ySpan;
                upperPadding = max(0.05*ySpan,0.02*yScale);
            elseif yScale > 0
                lowerPadding = 0.08*yScale;
                upperPadding = lowerPadding;
            else
                lowerPadding = 1;
                upperPadding = 1;
            end
            yLimits = [lowestY-lowerPadding,highestY+upperPadding];
        end
        if ~isempty(xLimits), xlim(ax,xLimits); end
        if ~isempty(yLimits), ylim(ax,yLimits); end
        ax.XLimMode = "manual";
        ax.YLimMode = "manual";
        if ~isempty(xLimits) && ~isempty(yLimits) && ...
                isprop(ax.XAxis,'LimitsChangedFcn') && ...
                isprop(ax.YAxis,'LimitsChangedFcn')
            ax.XAxis.LimitsChangedFcn = ...
                @(~,~)enforceSweepAxisBounds(ax,"x",xLimits);
            ax.YAxis.LimitsChangedFcn = ...
                @(~,~)enforceSweepAxisBounds(ax,"y",yLimits);
        else
            % Older MATLAB releases without ruler limit callbacks cannot
            % safely constrain interactive navigation, so disable it.
            disableDefaultInteractivity(ax);
        end
    end

    function enforceSweepAxisBounds(ax,dimension,hardLimits)
        if isempty(ax) || ~isvalid(ax) || numel(hardLimits) ~= 2
            return;
        end
        if dimension == "x"
            currentLimits = ax.XLim;
        else
            currentLimits = ax.YLim;
        end
        hardSpan = hardLimits(2)-hardLimits(1);
        currentSpan = currentLimits(2)-currentLimits(1);
        tolerance = 64*eps(max([abs(hardLimits),1]));
        if currentSpan >= hardSpan-tolerance
            boundedLimits = hardLimits;
        else
            boundedLimits = currentLimits;
            if boundedLimits(1) < hardLimits(1)
                boundedLimits = [hardLimits(1),hardLimits(1)+currentSpan];
            end
            if boundedLimits(2) > hardLimits(2)
                boundedLimits = [hardLimits(2)-currentSpan,hardLimits(2)];
            end
        end
        if any(abs(currentLimits-boundedLimits) > tolerance)
            if dimension == "x"
                ax.XLim = boundedLimits;
            else
                ax.YLim = boundedLimits;
            end
        end
    end

    function addTopFlowShareLabels(ax,Results,yValues)
        if isempty(Results) || ...
                Results.CoolingArchitecture(1) ~= "Top + Bottom Cooling"
            return;
        end
        yValues = double(yValues(:));
        valid = Results.Success & isfinite(Results.OperatingValue) & ...
            isfinite(Results.TopFlowShare_pct) & isfinite(yValues);
        rowsToLabel = find(valid).';
        if isempty(rowsToLabel), return; end
        rightmostX = max(Results.OperatingValue(valid));
        xTolerance = 64*eps(max(1,abs(rightmostX)));
        for kLabel = rowsToLabel
            labelText = thermalPackFormatText("%.4g%% top", ...
                Results.TopFlowShare_pct(kLabel));
            if abs(Results.OperatingValue(kLabel)-rightmostX) <= xTolerance
                displayedText = labelText + "  ";
                horizontalAlignment = "right";
            else
                displayedText = "  " + labelText;
                horizontalAlignment = "left";
            end
            text(ax,Results.OperatingValue(kLabel),yValues(kLabel), ...
                displayedText,"HorizontalAlignment",horizontalAlignment, ...
                "VerticalAlignment","bottom","FontSize",9, ...
                "FontWeight","bold","Color",ax.XColor, ...
                "Clipping","on","HandleVisibility","off");
        end
    end

    function drawOperatingPoints(ax,Results)
        colorbar(ax,"off");
        cla(ax,"reset");
        hold(ax,"on");
        good = Results.Success & Results.Feasible;
        bad = Results.Success & ~Results.Feasible;
        legendHandles = gobjects(0,1);
        if any(bad)
            scatter(ax,Results.OperatingValue(bad),Results.PeakTmaxNodal_C(bad), ...
                45,Results.Tin_C(bad),"x","LineWidth",1.4, ...
                "HandleVisibility","off");
            legendHandles(end+1,1) = scatter(ax,NaN,NaN,55, ...
                [0.90 0.25 0.20],"x","LineWidth",1.8, ...
                "DisplayName","Fails a limit");
        end
        if any(good)
            scatter(ax,Results.OperatingValue(good),Results.PeakTmaxNodal_C(good), ...
                45,Results.Tin_C(good),"filled","HandleVisibility","off");
            legendHandles(end+1,1) = scatter(ax,NaN,NaN,55, ...
                [1 1 1],"filled", ...
                "MarkerEdgeColor",[1 1 1], ...
                "DisplayName","Passes both criteria");
        end
        recommended = good & Results.Recommended;
        if any(recommended)
            scatter(ax,Results.OperatingValue(recommended), ...
                Results.PeakTmaxNodal_C(recommended),150, ...
                Results.Tin_C(recommended),"p","filled", ...
                "MarkerEdgeColor","k","LineWidth",1.2, ...
                "HandleVisibility","off");
            legendHandles(end+1,1) = scatter(ax,NaN,NaN,150, ...
                [1 1 1],"p","filled", ...
                "MarkerEdgeColor",[1 1 1],"LineWidth",1.2, ...
                "DisplayName","Recommended setting");
        end
        addTopFlowShareLabels(ax,Results,Results.PeakTmaxNodal_C);
        hold(ax,"off");
        xlabel(ax,optimizationAxisLabel(Results));
        ylabel(ax,"Peak nodal temperature (°C)");
        title(ax,"Operating Points — Colour Indicates " + ...
            optimizationInletTemperatureTitle(Results));
        grid(ax,"on");
        successfulTemperature = Results.PeakTmaxNodal_C(Results.Success);
        fitSweepAxes(ax,Results.OperatingValue,successfulTemperature);
        if any(Results.Success)
            colormap(ax,parula(256));
            cb = colorbar(ax);
            cb.Label.String = optimizationInletTemperatureLabel(Results);
            if ~isempty(legendHandles)
                operatingLegend = legend(ax,legendHandles,"Location","best");
                drawnow limitrate;
                operatingLegend.Units = "normalized";
                legendPosition = operatingLegend.Position;
                legendPosition(2) = max(0.02,legendPosition(2)-0.045);
                operatingLegend.Position = legendPosition;
            end
        end
    end

    function refreshSweepAnalysisPlots(Results)
        resetSweepAnalysisPlots("Generating sweep plots...");
        if isempty(Results), return; end
        PlotResults = thermalPackOperatingPlotRows(Results);
        operatingValues = unique(PlotResults.OperatingValue).';
        inletTemps = unique(PlotResults.Tin_C).';
        splitSweep = PlotResults.CoolingArchitecture(1) == "Top + Bottom Cooling";
        xText = optimizationAxisLabel(PlotResults);
        inletText = optimizationInletTemperatureLabel(PlotResults);
        colours = lines(numel(inletTemps));
        splitMarkers = ["o","s","d","^","v",">","<","p","h","+","x"];
        plotAxes = [sweepTmaxFlowAxes,sweepDeltaFlowAxes];
        metrics = ["PeakTmaxNodal_C","MaxCellToCellDeltaT_C"];
        for kAx = 1:2
            ax = plotAxes(kAx);
            hold(ax,"on");
            for kTin = 1:numel(inletTemps)
                if splitSweep
                    splitShares = unique(PlotResults.TopFlowShare_pct( ...
                        PlotResults.Tin_C == inletTemps(kTin))).';
                else
                    splitShares = NaN;
                end
                for kSplit = 1:numel(splitShares)
                    sameSeries = PlotResults.Tin_C == inletTemps(kTin);
                    if splitSweep
                        sameSeries = sameSeries & ...
                            PlotResults.TopFlowShare_pct == splitShares(kSplit);
                    end
                    subset = sortrows(PlotResults(sameSeries,:),"OperatingValue");
                    values = subset.(metrics(kAx));
                    values(~subset.Success) = NaN;
                    if splitSweep
                        marker = splitMarkers(1+mod(kSplit-1,numel(splitMarkers)));
                        seriesName = optimizationInletLegendLabel( ...
                            PlotResults,inletTemps(kTin)) + ...
                            thermalPackFormatText(" | %.4g%% top",splitShares(kSplit));
                    else
                        marker = "o";
                        seriesName = optimizationInletLegendLabel( ...
                            PlotResults,inletTemps(kTin));
                    end
                    plot(ax,subset.OperatingValue,values,"-","Marker",marker, ...
                        "Color",colours(kTin,:),"DisplayName",seriesName);
                    addTopFlowShareLabels(ax,subset,values);
                end
            end
            hold(ax,"off");
            xlabel(ax,xText);
            metricValues = PlotResults.(metrics(kAx));
            metricValues(~PlotResults.Success) = NaN;
            fitSweepAxes(ax,PlotResults.OperatingValue,metricValues);
            if (~splitSweep && numel(inletTemps) <= 12) || ...
                    (splitSweep && numel(inletTemps)*numel(unique( ...
                    PlotResults.TopFlowShare_pct)) <= 12)
                legend(ax,"show","Location","best");
            end
        end
        if splitSweep
            heatmapGroups = unique(PlotResults(:,["Tin_C","TopFlowShare_pct"]), ...
                "rows","sorted");
            heatmapRows = (1:height(heatmapGroups)).';
            heatmapLabels = strings(height(heatmapGroups),1);
            for kGroup = 1:height(heatmapGroups)
                heatmapLabels(kGroup) = thermalPackFormatText( ...
                    "%.4g °C | %.4g%% top",heatmapGroups.Tin_C(kGroup), ...
                    heatmapGroups.TopFlowShare_pct(kGroup));
            end
            heatmapYText = "Coolant inlet temperature | top flow share";
            drawSweepHeatmap(sweepTmaxHeatmapAxes, ...
                sweepMetricGrid(PlotResults,operatingValues, ...
                heatmapGroups.Tin_C,"PeakTmaxNodal_C", ...
                heatmapGroups.TopFlowShare_pct),operatingValues,heatmapRows, ...
                "Peak Nodal Temperature — All Tested Splits (°C)", ...
                xText,heatmapYText,false,heatmapLabels);
            drawSweepHeatmap(sweepSafetyHeatmapAxes, ...
                sweepMetricGrid(PlotResults,operatingValues, ...
                heatmapGroups.Tin_C,"Feasible",heatmapGroups.TopFlowShare_pct), ...
                operatingValues,heatmapRows, ...
                "Both Constraints — All Tested Splits", ...
                xText,heatmapYText,true,heatmapLabels);
        else
            drawSweepHeatmap(sweepTmaxHeatmapAxes, ...
                sweepMetricGrid(PlotResults,operatingValues,inletTemps, ...
                "PeakTmaxNodal_C"),operatingValues,inletTemps, ...
                "Peak Nodal Temperature (°C)",xText,inletText,false);
            drawSweepHeatmap(sweepSafetyHeatmapAxes, ...
                sweepMetricGrid(PlotResults,operatingValues,inletTemps, ...
                "Feasible"),operatingValues,inletTemps, ...
                "Both Constraints — Grey Means No Valid Result", ...
                xText,inletText,true);
        end
        drawOperatingPoints(optimizationAxes,PlotResults);
        title(optimizationAxes, ...
            "Thermal Performance Map — Peak Temperature vs Operating Setting");
        if splitSweep
            title(optimizationAxes, ...
                "Operating Points — All Tested Top/Bottom Splits");
        end
    end

    function resetDesignOptimizationPlots(messageText)
        if nargin < 1
            messageText = "";
        end
        if strlength(string(messageText)) > 0 && ...
                exist('designOptimizationStatus','var') && ...
                ~isempty(designOptimizationStatus) && isvalid(designOptimizationStatus)
            designOptimizationStatus.Text = string(messageText);
        end
        axesList = [designPeakAxes,designUniformityAxes,designSpaceAxes];
        for kAx = 1:numel(axesList)
            colorbar(axesList(kAx),"off");
            legend(axesList(kAx),"off");
            cla(axesList(kAx),"reset");
            grid(axesList(kAx),"on");
        end
        title(designPeakAxes,"Peak Nodal Temperature for Every Design Case");
        xlabel(designPeakAxes,"Design case");
        ylabel(designPeakAxes,"Peak nodal temperature (°C)");
        title(designUniformityAxes, ...
            "Cell-to-Cell Temperature Difference for Every Design Case");
        xlabel(designUniformityAxes,"Design case");
        ylabel(designUniformityAxes,"Maximum cell-to-cell ΔT (°C)");
        title(designSpaceAxes, ...
            "Design Space — Colour Indicates Peak Nodal Temperature");
    end

    function labelText = designPointLabel(Results,kRow)
        labelText = thermalPackFormatText("%.4g, %.4g", ...
            Results.Parameter1Value(kRow),Results.Parameter2Value(kRow));
        if isfinite(Results.Parameter3Value(kRow))
            labelText = labelText + thermalPackFormatText( ...
                ", %.4g",Results.Parameter3Value(kRow));
        end
    end

    function drawDesignCaseMetric(ax,Results,metricName,yLabel,titleText)
        colorbar(ax,"off");
        cla(ax,"reset");
        hold(ax,"on");
        good = Results.Success & Results.Feasible;
        bad = Results.Success & ~Results.Feasible;
        failed = ~Results.Success;
        legendHandles = gobjects(0,1);
        if any(bad)
            scatter(ax,Results.CaseID(bad),Results.(metricName)(bad),55, ...
                [0.90 0.25 0.20],"x","LineWidth",1.6,"HandleVisibility","off");
            legendHandles(end+1,1) = scatter(ax,NaN,NaN,55, ...
                [0.90 0.25 0.20],"x","LineWidth",1.6, ...
                "DisplayName","Fails a limit");
        end
        if any(good)
            scatter(ax,Results.CaseID(good),Results.(metricName)(good),55, ...
                [0.15 0.60 0.35],"filled","HandleVisibility","off");
            legendHandles(end+1,1) = scatter(ax,NaN,NaN,55, ...
                [1 1 1],"filled","MarkerEdgeColor",[1 1 1], ...
                "DisplayName","Passes both criteria");
        end
        recommended = good & Results.Recommended;
        if any(recommended)
            scatter(ax,Results.CaseID(recommended), ...
                Results.(metricName)(recommended),150,[0.95 0.70 0.10], ...
                "p","filled","MarkerEdgeColor","k","LineWidth",1.2, ...
                "HandleVisibility","off");
            legendHandles(end+1,1) = scatter(ax,NaN,NaN,150,[1 1 1], ...
                "p","filled","MarkerEdgeColor",[1 1 1],"LineWidth",1.2, ...
                "DisplayName","Recommended design");
        end
        successfulRows = find(~failed & isfinite(Results.(metricName))).';
        for kRow = successfulRows
            text(ax,Results.CaseID(kRow),Results.(metricName)(kRow), ...
                "  " + designPointLabel(Results,kRow), ...
                "HorizontalAlignment","left","VerticalAlignment","bottom", ...
                "FontSize",8,"Clipping","on","HandleVisibility","off");
        end
        hold(ax,"off");
        xlabel(ax,"Design case");
        ylabel(ax,yLabel);
        title(ax,titleText);
        grid(ax,"on");
        metricValues = Results.(metricName);
        metricValues(~Results.Success) = NaN;
        fitSweepAxes(ax,Results.CaseID,metricValues);
        if ~isempty(legendHandles)
            successful = Results.Success & isfinite(metricValues);
            legendLocation = thermalPackPreferredLegendCorner( ...
                Results.CaseID(successful),metricValues(successful), ...
                ax.XLim,ax.YLim);
            legend(ax,legendHandles,"Location",legendLocation);
        end
    end

    function refreshDesignOptimizationPlots(Results)
        % Do not overwrite the final completion summary while regenerating
        % plots during restoration of the original design configuration.
        resetDesignOptimizationPlots();
        if isempty(Results), return; end
        drawDesignCaseMetric(designPeakAxes,Results,"PeakTmaxNodal_C", ...
            "Peak nodal temperature (°C)", ...
            "Peak Nodal Temperature for Every Design Case");
        drawDesignCaseMetric(designUniformityAxes,Results, ...
            "MaxCellToCellDeltaT_C","Maximum cell-to-cell ΔT (°C)", ...
            "Cell-to-Cell Temperature Difference for Every Design Case");

        colorbar(designSpaceAxes,"off");
        cla(designSpaceAxes,"reset");
        hold(designSpaceAxes,"on");
        valid = Results.Success & isfinite(Results.Parameter1Value) & ...
            isfinite(Results.Parameter2Value) & isfinite(Results.PeakTmaxNodal_C);
        if any(valid)
            markerSizes = 65*ones(height(Results),1);
            third = Results.Parameter3Value;
            finiteThird = third(isfinite(third));
            if ~isempty(finiteThird) && max(finiteThird) > min(finiteThird)
                markerSizes(isfinite(third)) = 45 + 70*(third(isfinite(third))- ...
                    min(finiteThird))/(max(finiteThird)-min(finiteThird));
            end
            scatter(designSpaceAxes,Results.Parameter1Value(valid), ...
                Results.Parameter2Value(valid),markerSizes(valid), ...
                Results.PeakTmaxNodal_C(valid),"filled", ...
                "MarkerEdgeColor","k","LineWidth",0.5);
            recommended = valid & Results.Recommended;
            if any(recommended)
                scatter(designSpaceAxes,Results.Parameter1Value(recommended), ...
                    Results.Parameter2Value(recommended),170, ...
                    Results.PeakTmaxNodal_C(recommended),"p","filled", ...
                    "MarkerEdgeColor","k","LineWidth",1.5);
            end
            validRows = find(valid).';
            for kRow = validRows
                pointText = thermalPackFormatText("  #%d",Results.CaseID(kRow));
                if isfinite(Results.Parameter3Value(kRow))
                    pointText = pointText + thermalPackFormatText( ...
                        " | %.4g",Results.Parameter3Value(kRow));
                end
                text(designSpaceAxes,Results.Parameter1Value(kRow), ...
                    Results.Parameter2Value(kRow),pointText, ...
                    "HorizontalAlignment","left","VerticalAlignment","bottom", ...
                    "FontSize",8,"Clipping","on");
            end
            colormap(designSpaceAxes,parula(256));
            cb = colorbar(designSpaceAxes);
            cb.Label.String = "Peak nodal temperature (°C)";
            fitSweepAxes(designSpaceAxes,Results.Parameter1Value(valid), ...
                Results.Parameter2Value(valid));
        end
        hold(designSpaceAxes,"off");
        xlabel(designSpaceAxes,Results.Parameter1Name(1));
        ylabel(designSpaceAxes,Results.Parameter2Name(1));
        title(designSpaceAxes, ...
            "Design Space — Colour Indicates Peak Nodal Temperature");
        grid(designSpaceAxes,"on");
    end

    function showDesignOptimizationTable(Results)
        if isempty(Results)
            designOptimizationTable.Data = table();
            return;
        end
        hasThird = any(isfinite(Results.Parameter3Value));
        commonTail = ["PeakTmaxNodal_C","MaxCellToCellDeltaT_C", ...
            "MaxWithinCellDeltaT_C","TemperatureMargin_C", ...
            "UniformityMargin_C","CaseStatus","Recommended", ...
            "Runtime_s","ErrorMessage"];
        if hasThird
            displayedColumns = ["CaseID","Parameter1Value", ...
                "Parameter2Value","Parameter3Value",commonTail];
            headings = {"Case",char(Results.Parameter1Name(1)), ...
                char(Results.Parameter2Name(1)),char(Results.Parameter3Name(1)), ...
                "Peak Nodal T (°C)","Cell-to-Cell ΔT (°C)", ...
                "Within-Cell ΔT (°C)","T Margin (°C)", ...
                "ΔT Margin (°C)","Result","Recommended", ...
                "Runtime (s)","Error Details"};
            widths = {55,230,230,230,125,135,135,100,105,105,100,90,260};
        else
            displayedColumns = ["CaseID","Parameter1Value", ...
                "Parameter2Value",commonTail];
            headings = {"Case",char(Results.Parameter1Name(1)), ...
                char(Results.Parameter2Name(1)), ...
                "Peak Nodal T (°C)","Cell-to-Cell ΔT (°C)", ...
                "Within-Cell ΔT (°C)","T Margin (°C)", ...
                "ΔT Margin (°C)","Result","Recommended", ...
                "Runtime (s)","Error Details"};
            widths = {55,230,230,125,135,135,100,105,105,100,90,260};
        end
        designOptimizationTable.Data = Results(:,displayedColumns);
        designOptimizationTable.ColumnName = headings;
        designOptimizationTable.ColumnWidth = widths;
    end

    function applyDesignOptimizationCase(row)
        mode = string(row.CoolingArchitecture);
        rebuildRequired = false;
        if mode == "Forced Air Cooling"
            rebuildRequired = abs(cellGapField.Value-row.InterCellGap_mm) > 1e-12;
            cellGapField.Value = row.InterCellGap_mm;
            state.InterCellGap_mm = row.InterCellGap_mm;
            state.ForcedAirWallClearance_mm = row.DuctWallClearance_mm;
        elseif any(mode == ["Top Cooling Plate","Bottom Cooling Plate", ...
                "Top + Bottom Cooling"])
            state.PlateThickness_mm = row.PlateThickness_mm;
            coolantRField.Value = row.InterfaceRth_K_W;
        elseif mode == "Side Cooling"
            rebuildRequired = abs(state.SideHeightFraction-row.ContactHeightFraction) > 1e-12;
            state.SideHeightFraction = row.ContactHeightFraction;
            state.SideContactRth_K_W = row.InterfaceRth_K_W;
        elseif mode == "Serpentine Cooling"
            rebuildRequired = ...
                abs(state.SerpentineHeightFraction-row.ContactHeightFraction) > 1e-12 || ...
                abs(state.SerpentineCircumferenceFraction-row.CircumferenceFraction) > 1e-12;
            state.SerpentineHeightFraction = row.ContactHeightFraction;
            state.SerpentineCircumferenceFraction = row.CircumferenceFraction;
            state.SerpentineContactRth_K_W = row.InterfaceRth_K_W;
        end
        if rebuildRequired
            state.NeedsRebuild = true;
            rebuildBattery([],[]);
            if state.NeedsRebuild
                error("ThermalPack:DesignOptimizationRebuild", ...
                    "Battery Builder could not create this design case.");
            end
            rightTabs.SelectedTab = designOptimizationTab;
        elseif mode == "Forced Air Cooling"
            calc = forcedAirGeneralCalculation(state.ForcedAirVelocity_m_s, ...
                state.ForcedAirTemperature_C,state.ForcedAirPressure_Pa, ...
                state.ForcedAirAxis,state.ForcedAirWallClearance_mm);
            updateForcedAirStateFromCalculation(calc);
            if state.ProgressiveForcedAirBuilt
                updateProgressiveForcedAirOperatingPoint(calc);
                applyProgressiveAmbientResistanceToBlocks();
            end
        end
    end

    function restoreDesignOptimizationSession(savedState,savedCellToPlateRth_K_W, ...
            handles,enabledValues)
        results = state.LastDesignOptimizationResults;
        recommendation = state.LastRecommendedDesign;
        settings = state.LastDesignOptimizationSettings;
        folder = state.LastDesignOptimizationFolder;
        savedCoolingResults = savedState.LastOptimizationResults;
        savedCoolingRecommendations = savedState.LastRecommendedCase;
        savedCoolingSettings = savedState.LastOptimizationSettings;
        savedCoolingFolder = savedState.LastOptimizationFolder;
        mode = string(savedState.CoolingPlateMode);
        structuralMode = any(mode == ["Forced Air Cooling", ...
            "Side Cooling","Serpentine Cooling"]);
        state = savedState;
        state.DesignOptimizationRunning = true;
        state.DesignOptimizationStopRequested = false;
        restoreError = "";
        if ~isvalid(fig), return; end
        cellGapField.Value = state.InterCellGap_mm;
        assemblyGapField.Value = state.InterAssemblyGap_mm;
        coolantRField.Value = savedCellToPlateRth_K_W;
        if structuralMode
            try
                state.NeedsRebuild = true;
                rebuildBattery([],[]);
                if state.NeedsRebuild
                    restoreError = "Battery rebuild did not complete.";
                end
            catch ME
                state.NeedsRebuild = true;
                restoreError = string(ME.message);
            end
        end
        state.LastDesignOptimizationResults = results;
        state.LastRecommendedDesign = recommendation;
        state.LastDesignOptimizationSettings = settings;
        state.LastDesignOptimizationFolder = folder;
        state.LastOptimizationResults = savedCoolingResults;
        state.LastRecommendedCase = savedCoolingRecommendations;
        state.LastOptimizationSettings = savedCoolingSettings;
        state.LastOptimizationFolder = savedCoolingFolder;
        state.DesignOptimizationRunning = false;
        state.DesignOptimizationStopRequested = false;
        for kHandle = 1:numel(handles)
            if isvalid(handles{kHandle})
                handles{kHandle}.Enable = enabledValues{kHandle};
            end
        end
        designOptimizationStopButton.Enable = "off";
        if ~isempty(results)
            designOptimizationExportButton.Enable = "on";
            designOptimizationCsvButton.Enable = "on";
            showDesignOptimizationTable(results);
            refreshDesignOptimizationPlots(results);
        else
            designOptimizationExportButton.Enable = "off";
            designOptimizationCsvButton.Enable = "off";
        end
        if ~isempty(savedCoolingResults)
            showOptimizationTable(savedCoolingResults);
            refreshSweepAnalysisPlots(savedCoolingResults);
            optimizationExportButton.Enable = "on";
            optimizationCsvButton.Enable = "on";
        end
        designRangeMode = "";
        refreshDesignOptimizationControls();
        rightTabs.SelectedTab = designOptimizationTab;
        if strlength(restoreError) > 0
            statusLabel.Text = "Design sweep saved; rebuild required to restore the original design.";
            uialert(fig,"The original design could not be fully restored. " + ...
                "Rebuild before another run." + newline + restoreError, ...
                "ThermalPack — Rebuild Required");
        end
    end

    function stopDesignOptimization(~,~)
        if ~state.DesignOptimizationRunning, return; end
        state.DesignOptimizationStopRequested = true;
        designOptimizationStopButton.Enable = "off";
        designOptimizationStatus.Text = ...
            "Stop requested — collecting partial design results.";
        statusLabel.Text = "Design sweep stop requested";
        try
            if bdIsLoaded(mdl) && any(string(get_param(mdl,"SimulationStatus")) == ...
                    ["running","paused","initializing"])
                set_param(mdl,"SimulationCommand","stop");
            end
        catch
        end
    end

    function runDesignOptimization(~,~)
        if state.OptimizationRunning || state.DesignOptimizationRunning, return; end
        refreshDesignOptimizationControls();
        try
            [designValues,spec] = designOptimizationGridValues();
            thermalLimit_C = optLimitField.Value;
            uniformityLimit_C = optUniformityField.Value;
            if ~isfinite(thermalLimit_C) || thermalLimit_C <= -273.15 || ...
                    ~isfinite(uniformityLimit_C) || uniformityLimit_C < 0
                error("ThermalPack:DesignOptimizationInput", ...
                    "The shared temperature limits are invalid.");
            end
            if ~isfinite(stopField.Value) || stopField.Value <= 0
                error("ThermalPack:DesignOptimizationInput", ...
                    "Simulation duration must be positive and finite.");
            end
            if spec.Mode ~= "Forced Air Cooling" && ...
                    state.FlowRateType ~= "Mass flow rate"
                error("ThermalPack:DesignOptimizationInput", ...
                    "Select Mass flow rate in the liquid flow-source settings.");
            end
            if bdIsLoaded(mdl) && string(get_param(mdl,"SimulationStatus")) ~= "stopped"
                error("ThermalPack:DesignOptimizationInput", ...
                    "Wait for the current model operation to finish.");
            end
        catch ME
            uialert(fig,ME.message,"ThermalPack — Design Sweep Inputs");
            return;
        end
        nCases = prod(cellfun(@numel,designValues));
        if nCases > 100
            answer = uiconfirm(fig,thermalPackFormatText( ...
                "This design sweep contains %d simulations. Continue?",nCases), ...
                "Large Design Sweep","Options",["Continue","Cancel"], ...
                "DefaultOption","Cancel","CancelOption","Cancel");
            if answer ~= "Continue", return; end
        end
        if state.NeedsRebuild
            rebuildBattery([],[]);
            if state.NeedsRebuild, return; end
        end
        storeDesignOptimizationRanges();
        fixedSetup = captureThermalPackSimulationSettings();
        savedState = state;
        savedCellToPlateRth_K_W = coolantRField.Value;
        pauseThermalAnimation();
        [lockedHandles,enabledValues] = ...
            lockOptimizationInputs(designOptimizationStopButton);
        cleanupSweep = onCleanup(@()restoreDesignOptimizationSession( ...
            savedState,savedCellToPlateRth_K_W, ...
            lockedHandles,enabledValues)); %#ok<NASGU>
        state.DesignOptimizationRunning = true;
        state.DesignOptimizationStopRequested = false;
        rightTabs.SelectedTab = designOptimizationTab;
        state.LastDesignOptimizationResults = table();
        state.LastRecommendedDesign = table();
        state.LastDesignOptimizationFolder = "";
        designOptimizationTable.Data = table();
        resetDesignOptimizationPlots("Design sweep in progress...");
        state.DesignSelectionOrder = thermalPackNormalizeSelectionOrder( ...
            state.DesignSelectionOrder,"design");

        sweepSettings = struct("AppVersion","ThermalPack Version 2.0", ...
            "CoolingArchitecture",spec.Mode,"ParameterNames",spec.Labels, ...
            "ParameterValues",{designValues},"ThermalLimit_C",thermalLimit_C, ...
            "UniformityLimit_C",uniformityLimit_C,"StopTime_s",stopField.Value, ...
            "FixedSetup",fixedSetup,"StartedAt", ...
            string(datetime("now","Format","yyyy-MM-dd HH:mm:ss")), ...
            "RecommendationRule","User-configurable priority order among feasible designs", ...
            "SelectionOrder",state.DesignSelectionOrder, ...
            "EnergyModel","Fan/pump power and pressure drop are not evaluated", ...
            "OriginalCellToPlateRth_K_W",coolantRField.Value);
        state.LastDesignOptimizationSettings = sweepSettings;

        grids = cell(1,spec.Count);
        [grids{:}] = ndgrid(designValues{:});
        rows = repmat(designOptimizationEmptyRow(),nCases,1);
        for k = 1:nCases
            rows(k).CaseID = k;
            rows(k).CoolingArchitecture = spec.Mode;
            rows(k).Parameter1Name = spec.Labels(1);
            rows(k).Parameter2Name = spec.Labels(2);
            rows(k).Parameter1Value = grids{1}(k);
            rows(k).Parameter2Value = grids{2}(k);
            if spec.Count == 3
                rows(k).Parameter3Name = spec.Labels(3);
                rows(k).Parameter3Value = grids{3}(k);
            end
            if spec.Mode == "Forced Air Cooling"
                rows(k).InterCellGap_mm = rows(k).Parameter1Value;
                rows(k).DuctWallClearance_mm = rows(k).Parameter2Value;
                rows(k).OperatingValue = state.ForcedAirVelocity_m_s;
                rows(k).AirVelocity_m_s = state.ForcedAirVelocity_m_s;
                rows(k).Tin_C = state.ForcedAirTemperature_C;
            elseif any(spec.Mode == ["Top Cooling Plate", ...
                    "Bottom Cooling Plate","Top + Bottom Cooling"])
                rows(k).PlateThickness_mm = rows(k).Parameter1Value;
                rows(k).InterfaceRth_K_W = rows(k).Parameter2Value;
                rows(k).OperatingValue = flowField.Value;
                rows(k).mdot_kg_s = flowField.Value;
                rows(k).Tin_C = tinField.Value;
            elseif spec.Mode == "Side Cooling"
                rows(k).ContactHeightFraction = rows(k).Parameter1Value;
                rows(k).InterfaceRth_K_W = rows(k).Parameter2Value;
                rows(k).OperatingValue = flowField.Value;
                rows(k).mdot_kg_s = flowField.Value;
                rows(k).Tin_C = tinField.Value;
            else
                rows(k).ContactHeightFraction = rows(k).Parameter1Value;
                rows(k).CircumferenceFraction = rows(k).Parameter2Value;
                rows(k).InterfaceRth_K_W = rows(k).Parameter3Value;
                rows(k).OperatingValue = flowField.Value;
                rows(k).mdot_kg_s = flowField.Value;
                rows(k).Tin_C = tinField.Value;
            end
            rows(k).TopFlowShare_pct = topSplitField.Value;
            rows(k).InitialSOC = socField.Value;
            rows(k).InitialCellTemperature_C = initialCellTempField.Value;
            rows(k).InitialPlateTemperature_C = state.InitialPlateTemperature_C;
            rows(k).ThermalLimit_C = thermalLimit_C;
            rows(k).UniformityLimit_C = uniformityLimit_C;
        end

        try
            for k = 1:nCases
                drawnow;
                if state.DesignOptimizationStopRequested, break; end
                row = rows(k);
                designOptimizationCurrentCase.Text = thermalPackFormatText( ...
                    "Case %d/%d | %s = %.5g | %s = %.5g", ...
                    k,nCases,row.Parameter1Name,row.Parameter1Value, ...
                    row.Parameter2Name,row.Parameter2Value);
                designOptimizationStatus.Text = ...
                    "Running — configuration inputs are locked.";
                statusLabel.Text = thermalPackFormatText( ...
                    "Design sweep — case %d/%d",k,nCases);
                drawnow;
                caseTimer = tic;
                caseStage = "Applying design";
                try
                    applyDesignOptimizationCase(row);
                    if state.DesignOptimizationStopRequested
                        row.CaseStatus = "Stopped";
                        row.ErrorMessage = ...
                            "Stopped by user; excluded from feasibility.";
                    else
                        caseStage = "Building simulation input";
                        cfg = currentSimulationConfig();
                        if spec.Mode == "Forced Air Cooling"
                            flowValue = flowField.Value;
                            inletTemperature_C = state.ForcedAirTemperature_C;
                        else
                            flowValue = flowField.Value;
                            inletTemperature_C = tinField.Value;
                        end
                        [caseIn,~] = buildThermalSimulationInput( ...
                            cfg,flowValue,inletTemperature_C);
                        caseStage = "Applying sweep logging settings";
                        designModelParameters = ...
                            thermalPackOperatingModelParameters();
                        caseIn = caseIn.setModelParameter( ...
                            designModelParameters{:});
                        caseStage = "Running simulation";
                        caseOut = sim(caseIn);
                        drawnow;
                        if state.DesignOptimizationStopRequested
                            row.CaseStatus = "Stopped";
                            row.ErrorMessage = ...
                                "Stopped by user; excluded from feasibility.";
                        else
                            caseStage = "Reading temperature logs";
                            [caseKPI,caseTrace] = extractUIResults(caseOut,cfg);
                            caseStage = "Checking full-run thermal results";
                            met = thermalPackOperatingMetrics( ...
                                caseTrace,cfg,sweepSettings.StopTime_s);
                            row.PeakTmaxNodal_C = met.PeakTmaxNodal_C;
                            row.MaxCellToCellDeltaT_C = ...
                                met.MaxCellToCellDeltaT_C;
                            row.MaxWithinCellDeltaT_C = ...
                                met.MaxWithinCellDeltaT_C;
                            row.MaxDeltaTNodal_C = met.MaxDeltaTNodal_C;
                            row.EndTime_s = met.EndTime_s;
                            row.TemperatureMargin_C = thermalLimit_C - ...
                                row.PeakTmaxNodal_C;
                            row.UniformityMargin_C = uniformityLimit_C - ...
                                row.MaxCellToCellDeltaT_C;
                            row.WorstCell = caseKPI.WorstCell;
                            row.WorstNode = caseKPI.WorstNode;
                            row.Success = true;
                            row.Feasible = thermalPackOperatingFeasible( ...
                                row.PeakTmaxNodal_C,row.MaxCellToCellDeltaT_C, ...
                                thermalLimit_C,uniformityLimit_C);
                            if row.Feasible
                                row.CaseStatus = "Pass";
                            else
                                row.CaseStatus = "Fails limits";
                            end
                        end
                    end
                catch MEcase
                    if state.DesignOptimizationStopRequested
                        row.CaseStatus = "Stopped";
                        row.ErrorMessage = ...
                            "Stopped by user; excluded from feasibility.";
                    else
                        row.CaseStatus = "Failed";
                        row.ErrorMessage = string(MEcase.message) + newline + ...
                            "Stage: " + caseStage + newline + ...
                            "Identifier: " + string(MEcase.identifier) + ...
                            newline + newline + string(getReport( ...
                            MEcase,"extended","hyperlinks","off"));
                    end
                end
                row.Runtime_s = toc(caseTimer);
                rows(k) = row;
                Results = struct2table(rows);
                [Results,Recommendation] = ...
                    thermalPackDesignRecommendations( ...
                    Results,state.DesignSelectionOrder);
                state.LastDesignOptimizationResults = Results;
                state.LastRecommendedDesign = Recommendation;
                showDesignOptimizationTable(Results);
                if state.DesignOptimizationStopRequested, break; end
            end
            Results = struct2table(rows);
            [Results,Recommendation] = thermalPackDesignRecommendations( ...
                Results,state.DesignSelectionOrder);
            state.LastDesignOptimizationResults = Results;
            state.LastRecommendedDesign = Recommendation;
            state.LastDesignOptimizationSettings.StoppedByUser = ...
                state.DesignOptimizationStopRequested;
            showDesignOptimizationTable(Results);
            refreshDesignOptimizationPlots(Results);
            failedCases = Results.CaseStatus == "Failed";
            if state.DesignOptimizationStopRequested
                outcome = "Stopped";
            elseif ~any(Results.Success) && any(failedCases)
                outcome = "Failed";
            elseif any(failedCases)
                outcome = "Finished with failures";
            else
                outcome = "Complete";
            end
            designOptimizationStatus.Text = thermalPackFormatText( ...
                "%s: %d/%d completed; %d failed; %d pass; %d recommended design.", ...
                outcome,sum(Results.Success),nCases,sum(failedCases), ...
                sum(Results.Feasible),sum(Results.Recommended));
            designOptimizationCurrentCase.Text = ...
                "Current case: " + lower(outcome);
            if ~any(Results.Success)
                designOptimizationCurrentCase.Text = ...
                    "No valid results — select an Error Details cell.";
            elseif ~any(Results.Feasible)
                designOptimizationCurrentCase.Text = ...
                    "No completed design met both limits.";
            end
            statusLabel.Text = ...
                "Design sweep " + lower(outcome) + " — results available to export.";
        catch ME
            Results = struct2table(rows);
            [Results,Recommendation] = thermalPackDesignRecommendations( ...
                Results,state.DesignSelectionOrder);
            state.LastDesignOptimizationResults = Results;
            state.LastRecommendedDesign = Recommendation;
            state.LastDesignOptimizationSettings.ReportingError = string(ME.message);
            designOptimizationStatus.Text = ...
                "Design sweep interrupted — accumulated results remain available.";
            statusLabel.Text = "Design sweep interrupted";
            uialert(fig,getReport(ME,"extended","hyperlinks","off"), ...
                "ThermalPack — Design Sweep");
        end
    end

    function showDesignOptimizationCaseError(src,event)
        if state.DesignOptimizationRunning || isempty(event.Indices) || ...
                isempty(src.Data)
            return;
        end
        errorColumn = find(strcmp(src.Data.Properties.VariableNames, ...
            "ErrorMessage"),1);
        selected = event.Indices(event.Indices(:,2) == errorColumn,:);
        if isempty(selected), return; end
        rowIndex = selected(1,1);
        if rowIndex > height(src.Data), return; end
        messageText = string(src.Data.ErrorMessage(rowIndex));
        if strlength(messageText) == 0, return; end
        showOptimizationErrorReport(src.Data.CaseID(rowIndex),messageText);
    end

    function exportDesignOptimizationResultsCsv(~,~)
        if state.DesignOptimizationRunning || isempty(designOptimizationTable.Data)
            return;
        end
        defaultName = "ThermalPack_DesignSweep_Results_" + ...
            string(datetime("now","Format","yyyyMMdd_HHmmss")) + ".csv";
        [fileName,parentFolder] = uiputfile( ...
            {'*.csv','CSV file (*.csv)'}, ...
            'Export the displayed design-sweep results',defaultName);
        if isequal(fileName,0) || isequal(parentFolder,0), return; end
        [~,~,fileExtension] = fileparts(fileName);
        if strlength(string(fileExtension)) == 0
            fileName = string(fileName) + ".csv";
        end
        try
            csvHeadings = string(designOptimizationTable.ColumnName(:).');
            csvHeadings = replace(csvHeadings,"Peak Nodal T (°C)", ...
                "Peak Nodal Temperature (deg C)");
            csvHeadings = replace(csvHeadings,"Cell-to-Cell ΔT (°C)", ...
                "Maximum Cell-to-Cell Delta T (deg C)");
            csvHeadings = replace(csvHeadings,"Within-Cell ΔT (°C)", ...
                "Maximum Within-Cell Delta T (deg C)");
            csvHeadings = replace(csvHeadings,"ΔT Margin (°C)", ...
                "Cell-to-Cell Delta T Margin (deg C)");
            csvHeadings = replace(csvHeadings,"T Margin (°C)", ...
                "Temperature Margin (deg C)");
            csvContents = [cellstr(csvHeadings); ...
                table2cell(designOptimizationTable.Data)];
            outputFile = fullfile(parentFolder,fileName);
            writecell(csvContents,outputFile);
            designOptimizationStatus.Text = ...
                "Results table exported: " + string(outputFile);
        catch ME
            uialert(fig,ME.message, ...
                "ThermalPack — Design Results CSV Export Error");
        end
    end

    function exportDesignOptimization(~,~)
        if state.DesignOptimizationRunning || ...
                isempty(state.LastDesignOptimizationResults)
            return;
        end
        parentFolder = uigetdir(pwd,"Choose a folder for the design-sweep results");
        if isequal(parentFolder,0), return; end
        try
            exportFolder = fullfile(parentFolder,"ThermalPack_DesignSweep_" + ...
                string(datetime("now","Format","yyyyMMdd_HHmmss_SSS")));
            mkdir(exportFolder);
            Results = state.LastDesignOptimizationResults;
            Recommendation = state.LastRecommendedDesign;
            SweepSettings = state.LastDesignOptimizationSettings;
            writetable(Results,fullfile(exportFolder,"All_Design_Cases.csv"));
            writetable(Recommendation,fullfile(exportFolder,"Recommended_Design.csv"));
            save(fullfile(exportFolder,"Design_Sweep.mat"), ...
                "Results","Recommendation","SweepSettings");
            state.LastDesignOptimizationFolder = string(exportFolder);
            designOptimizationStatus.Text = ...
                "Design sweep exported: " + string(exportFolder);
        catch ME
            uialert(fig,ME.message,"ThermalPack — Design Sweep Export Error");
        end
    end

    function showOptimizationTable(Results)
        resultMode = Results.CoolingArchitecture(1);
        if resultMode == "Forced Air Cooling"
            operatingColumn = "AirVelocity_m_s";
            operatingHeading = "Air Velocity (m/s)";
            inletHeading = "Air Inlet T (°C)";
        else
            operatingColumn = "mdot_kg_s";
            if resultMode == "Top Cooling Plate"
                operatingHeading = "Top Flow (kg/s)";
            elseif resultMode == "Bottom Cooling Plate"
                operatingHeading = "Bottom Flow (kg/s)";
            elseif resultMode == "Side Cooling"
                operatingHeading = "Side Flow (kg/s)";
            elseif resultMode == "Serpentine Cooling"
                operatingHeading = "Serpentine Flow (kg/s)";
            else
                operatingHeading = "Total Flow (kg/s)";
            end
            inletHeading = "Coolant Inlet T (°C)";
        end
        if resultMode == "Top + Bottom Cooling"
            optimizationTable.Data = Results(:,["CaseID",operatingColumn, ...
                "TopFlowShare_pct","TopFlow_kg_s","BottomFlow_kg_s","Tin_C", ...
                "PeakTmaxNodal_C","MaxCellToCellDeltaT_C","MaxWithinCellDeltaT_C", ...
                "TemperatureMargin_C","UniformityMargin_C","CaseStatus", ...
                "Recommended","Runtime_s","ErrorMessage"]);
            optimizationTable.ColumnName = { ...
                "Case",operatingHeading,"Top Share (%)","Top Flow (kg/s)", ...
                "Bottom Flow (kg/s)",inletHeading,"Peak Nodal T (°C)", ...
                "Cell-to-Cell ΔT (°C)","Within-Cell ΔT (°C)", ...
                "T Margin (°C)","ΔT Margin (°C)","Result", ...
                "Recommended","Runtime (s)","Error Details"};
            optimizationTable.ColumnWidth = {55,165,110,125,140,165,125, ...
                135,135,100,105,105,100,90,260};
        else
            optimizationTable.Data = Results(:,["CaseID",operatingColumn,"Tin_C", ...
                "PeakTmaxNodal_C","MaxCellToCellDeltaT_C","MaxWithinCellDeltaT_C", ...
                "TemperatureMargin_C","UniformityMargin_C","CaseStatus", ...
                "Recommended","Runtime_s","ErrorMessage"]);
            optimizationTable.ColumnName = { ...
                "Case",operatingHeading,inletHeading, ...
                "Peak Nodal T (°C)","Cell-to-Cell ΔT (°C)", ...
                "Within-Cell ΔT (°C)","T Margin (°C)", ...
                "ΔT Margin (°C)","Result","Recommended", ...
                "Runtime (s)","Error Details"};
            optimizationTable.ColumnWidth = {55,165,165,125,135,135,100, ...
                105,105,100,90,260};
        end
    end

    function [handles,enabledValues] = lockOptimizationInputs(activeStopButton)
        if nargin < 1
            activeStopButton = optimizationStopButton;
        end
        handles = {}; enabledValues = {};
        roots = {fig};
        candidates = findall(groot,"Type","figure");
        for kFig = 1:numel(candidates)
            owner = candidates(kFig).UserData;
            if isstruct(owner) && isfield(owner,"ThermalPackOwner") && ...
                    isequal(owner.ThermalPackOwner,fig)
                roots{end+1} = candidates(kFig); %#ok<AGROW>
            end
        end
        for kRoot = 1:numel(roots)
            controls = findall(roots{kRoot},"-property","Enable");
            for kControl = 1:numel(controls)
                h = controls(kControl);
                if isequal(h,activeStopButton), continue; end
                interactive = isprop(h,"ValueChangedFcn") || isprop(h,"ButtonPushedFcn") || ...
                    (isprop(h,"ColumnEditable") && any(h.ColumnEditable));
                if ~interactive, continue; end
                handles{end+1} = h; %#ok<AGROW>
                enabledValues{end+1} = h.Enable; %#ok<AGROW>
                h.Enable = "off";
            end
        end
        activeStopButton.Enable = "on";
    end

    function restoreOptimizationSession(savedState,savedAmbient, ...
            savedTopFlowShare_pct,handles,enabledValues)
        % Restore configuration on success, cancellation and exceptions while
        % retaining the newly collected results and their fixed-setup audit.
        results = state.LastOptimizationResults;
        recommendations = state.LastRecommendedCase;
        settings = state.LastOptimizationSettings;
        folder = state.LastOptimizationFolder;
        state = savedState;
        state.LastOptimizationResults = results;
        state.LastRecommendedCase = recommendations;
        state.LastOptimizationSettings = settings;
        state.LastOptimizationFolder = folder;
        restoreError = "";
        if string(state.CoolingPlateMode) == "Forced Air Cooling"
            try
                calc = forcedAirGeneralCalculation(state.ForcedAirVelocity_m_s, ...
                    state.ForcedAirTemperature_C,state.ForcedAirPressure_Pa, ...
                    state.ForcedAirAxis,state.ForcedAirWallClearance_mm);
                updateForcedAirStateFromCalculation(calc);
                if state.ProgressiveForcedAirBuilt
                    updateProgressiveForcedAirOperatingPoint(calc);
                    applyProgressiveAmbientResistanceToBlocks();
                end
            catch ME
                state.NeedsRebuild = true;
                restoreError = string(ME.message);
            end
        end
        state.OptimizationRunning = false;
        state.OptimizationStopRequested = false;
        if ~isvalid(fig), return; end
        ambientField.Value = savedAmbient(1);
        ambientRField.Value = savedAmbient(2);
        topSplitField.Value = savedTopFlowShare_pct;
        refreshFlowAccountingUI();
        for kHandle = 1:numel(handles)
            if isvalid(handles{kHandle})
                handles{kHandle}.Enable = enabledValues{kHandle};
            end
        end
        optimizationStopButton.Enable = "off";
        if ~isempty(results)
            optimizationExportButton.Enable = "on";
            optimizationCsvButton.Enable = "on";
        else
            optimizationExportButton.Enable = "off";
            optimizationCsvButton.Enable = "off";
        end
        if strlength(restoreError) > 0
            statusLabel.Text = "Sweep saved; rebuild required to restore the air model.";
            uialert(fig,"The original air settings could not be restored. Rebuild before another run." ...
                + newline + restoreError,"ThermalPack — Rebuild Required");
        end
        refreshDesignOptimizationControls();
    end

    function stopCoolingOptimization(~,~)
        if ~state.OptimizationRunning, return; end
        state.OptimizationStopRequested = true;
        optimizationStopButton.Enable = "off";
        optimizationStatus.Text = "Stop requested — collecting partial results.";
        statusLabel.Text = "Operating sweep stop requested";
        try
            if bdIsLoaded(mdl) && any(string(get_param(mdl,"SimulationStatus")) == ...
                    ["running","paused","initializing"])
                set_param(mdl,"SimulationCommand","stop");
            end
        catch
            % A blocking sim() may defer the callback until case completion.
            % The stop flag still prevents the next scheduled case from running.
        end
    end

    function runCoolingOptimization(~,~)
        if state.OptimizationRunning || state.DesignOptimizationRunning, return; end
        refreshOptimizationControls();
        try
            [operatingValues,inletTemps,topFlowShares_pct] = optimizationGridValues();
            thermalLimit_C = optLimitField.Value;
            uniformityLimit_C = optUniformityField.Value;
            if ~isfinite(thermalLimit_C) || thermalLimit_C <= -273.15 || ...
                    ~isfinite(uniformityLimit_C) || uniformityLimit_C < 0
                error("ThermalPack:OptimizationInput", ...
                    "T limit must be finite and above absolute zero; the ΔT limit must be finite and nonnegative.");
            end
            if ~isfinite(stopField.Value) || stopField.Value <= 0
                error("ThermalPack:OptimizationInput","Simulation duration must be positive and finite.");
            end
            mode = string(coolingPlateField.Value);
            airMode = mode == "Forced Air Cooling";
            if mode == "No Cooling Plate"
                error("ThermalPack:OptimizationInput", ...
                    "Select liquid cooling or forced air cooling before running a sweep.");
            end
            if ~airMode && state.FlowRateType ~= "Mass flow rate"
                error("ThermalPack:OptimizationInput", ...
                    "Select Mass flow rate in the liquid flow-source settings.");
            end
            if mode == "Top + Bottom Cooling" && state.FlowAllocationMode == "Independent Flow"
                error("ThermalPack:OptimizationInput", ...
                    "Select Total Flow for Top + Bottom Cooling so the sweep can vary the top-flow share.");
            end
            if bdIsLoaded(mdl) && string(get_param(mdl,"SimulationStatus")) ~= "stopped"
                error("ThermalPack:OptimizationInput", ...
                    "Wait for the current model operation to finish before starting a sweep.");
            end
        catch ME
            uialert(fig,ME.message,"ThermalPack — Sweep Inputs");
            return;
        end
        nCases = numel(operatingValues)*numel(inletTemps)*numel(topFlowShares_pct);
        if nCases > 100
            answer = uiconfirm(fig,thermalPackFormatText( ...
                "This sweep contains %d simulations. Continue?",nCases), ...
                "Large Operating Sweep","Options",["Continue","Cancel"], ...
                "DefaultOption","Cancel","CancelOption","Cancel");
            if answer ~= "Continue", return; end
        end
        if state.NeedsRebuild
            rebuildBattery([],[]);
            if state.NeedsRebuild, return; end
        end
        storeOptimizationRanges();
        fixedSetup = captureThermalPackSimulationSettings();
        savedState = state;
        savedAmbient = [ambientField.Value,ambientRField.Value];
        savedTopFlowShare_pct = topSplitField.Value;
        pauseThermalAnimation();
        [lockedHandles,enabledValues] = ...
            lockOptimizationInputs(optimizationStopButton);
        cleanupSweep = onCleanup(@()restoreOptimizationSession( ...
            savedState,savedAmbient,savedTopFlowShare_pct, ...
            lockedHandles,enabledValues)); %#ok<NASGU>
        state.OptimizationRunning = true;
        state.OptimizationStopRequested = false;
        rightTabs.SelectedTab = optimizationTab;
        state.LastOptimizationResults = table();
        state.LastRecommendedCase = table();
        state.LastOptimizationFolder = "";
        optimizationTable.Data = table();
        resetSweepAnalysisPlots("Sweep in progress...");
        state.CoolingSelectionOrder = thermalPackNormalizeSelectionOrder( ...
            state.CoolingSelectionOrder,"cooling");

        sweepSettings = struct("AppVersion","ThermalPack Version 2.0", ...
            "CoolingArchitecture",mode,"OperatingValues",operatingValues, ...
            "InletTemperatures_C",inletTemps, ...
            "TopFlowShares_pct",topFlowShares_pct,"ThermalLimit_C",thermalLimit_C, ...
            "UniformityLimit_C",uniformityLimit_C,"StopTime_s",stopField.Value, ...
            "OperatingParameter",optimizationAxisLabel(), ...
            "InletTemperatureParameter",optimizationInletTemperatureLabel(), ...
            "FixedSetup",fixedSetup,"StartedAt", ...
            string(datetime("now","Format","yyyy-MM-dd HH:mm:ss")), ...
            "RecommendationRule","User-configurable priority order among feasible cases at each Tin", ...
            "SelectionOrder",state.CoolingSelectionOrder, ...
            "CellToCellDefinition","max over time of max(cell averages)-min(cell averages)", ...
            "WithinCellDefinition","max over time and cells of max(nodes)-min(nodes)", ...
            "EnergyModel","Pump/fan and inlet-conditioning energy are not evaluated");
        state.LastOptimizationSettings = sweepSettings;
        rows = repmat(optimizationEmptyRow(),nCases,1);
        for iTin = 1:numel(inletTemps)
            for iValue = 1:numel(operatingValues)
                for iSplit = 1:numel(topFlowShares_pct)
                    k = (iTin-1)*numel(operatingValues)*numel(topFlowShares_pct) + ...
                        (iValue-1)*numel(topFlowShares_pct) + iSplit;
                    rows(k).CaseID = k;
                    rows(k).CoolingArchitecture = mode;
                    rows(k).OperatingValue = operatingValues(iValue);
                    if airMode
                        rows(k).AirVelocity_m_s = operatingValues(iValue);
                        rows(k).Tamb_C = inletTemps(iTin); % Cooling air is the ambient boundary.
                    else
                        rows(k).mdot_kg_s = operatingValues(iValue);
                        rows(k).Tamb_C = savedAmbient(1);
                    end
                    if mode == "Top + Bottom Cooling"
                        rows(k).TopFlowShare_pct = topFlowShares_pct(iSplit);
                        rows(k).TopFlow_kg_s = operatingValues(iValue)* ...
                            topFlowShares_pct(iSplit)/100;
                        rows(k).BottomFlow_kg_s = operatingValues(iValue)- ...
                            rows(k).TopFlow_kg_s;
                    end
                    rows(k).Tin_C = inletTemps(iTin);
                    rows(k).InitialSOC = socField.Value;
                    rows(k).InitialCellTemperature_C = initialCellTempField.Value;
                    rows(k).InitialPlateTemperature_C = state.InitialPlateTemperature_C;
                    rows(k).ThermalLimit_C = thermalLimit_C;
                    rows(k).UniformityLimit_C = uniformityLimit_C;
                end
            end
        end
        try
            for k = 1:nCases
                drawnow;
                if state.OptimizationStopRequested, break; end
                row = rows(k);
                if mode == "Top + Bottom Cooling"
                    optimizationCurrentCase.Text = thermalPackFormatText( ...
                        "Case %d/%d | Total flow = %.5g kg/s | Top share = %.4g%% | Tin = %.4g °C", ...
                        k,nCases,row.OperatingValue,row.TopFlowShare_pct,row.Tin_C);
                else
                    optimizationCurrentCase.Text = thermalPackFormatText( ...
                        "Case %d/%d | %s = %.5g | %s = %.4g °C", ...
                        k,nCases,optFlowLabel.Text,row.OperatingValue, ...
                        erase(optTinLabel.Text," (°C)"),row.Tin_C);
                end
                optimizationStatus.Text = "Running — configuration inputs are locked.";
                statusLabel.Text = thermalPackFormatText("Operating sweep — case %d/%d",k,nCases);
                drawnow;
                if state.OptimizationStopRequested, break; end
                caseTimer = tic;
                caseStage = "Configuring operating point";
                try
                    if airMode
                        state.ForcedAirVelocity_m_s = row.AirVelocity_m_s;
                        state.ForcedAirTemperature_C = row.Tin_C;
                        flowValue = flowField.Value; % Inactive liquid branches retain their setup.
                    else
                        flowValue = row.mdot_kg_s;
                        if mode == "Top + Bottom Cooling"
                            topSplitField.Value = row.TopFlowShare_pct;
                            state.TopFlowShare_pct = row.TopFlowShare_pct;
                        end
                    end
                    % Air properties and audit metadata must match THIS case.
                    cfg = currentSimulationConfig();
                    caseStage = "Building simulation input";
                    [caseIn,~] = buildThermalSimulationInput(cfg,flowValue,row.Tin_C);
                    caseStage = "Applying sweep logging settings";
                    sweepModelParameters = thermalPackOperatingModelParameters();
                    caseIn = caseIn.setModelParameter(sweepModelParameters{:});
                    caseStage = "Running simulation";
                    caseOut = sim(caseIn);
                    drawnow;
                    if state.OptimizationStopRequested
                        row.CaseStatus = "Stopped";
                        row.ErrorMessage = "Stopped by user; excluded from feasibility.";
                    else
                        caseStage = "Reading temperature logs";
                        [caseKPI,caseTrace] = extractUIResults(caseOut,cfg);
                        caseStage = "Checking full-run thermal results";
                        met = thermalPackOperatingMetrics(caseTrace,cfg,sweepSettings.StopTime_s);
                        row.PeakTmaxNodal_C = met.PeakTmaxNodal_C;
                        row.MaxCellToCellDeltaT_C = met.MaxCellToCellDeltaT_C;
                        row.MaxWithinCellDeltaT_C = met.MaxWithinCellDeltaT_C;
                        row.MaxDeltaTNodal_C = met.MaxDeltaTNodal_C;
                        row.EndTime_s = met.EndTime_s;
                        row.TemperatureMargin_C = thermalLimit_C - row.PeakTmaxNodal_C;
                        row.UniformityMargin_C = uniformityLimit_C - row.MaxCellToCellDeltaT_C;
                        row.WorstCell = caseKPI.WorstCell;
                        row.WorstNode = caseKPI.WorstNode;
                        row.Success = true;
                        row.Feasible = thermalPackOperatingFeasible( ...
                            row.PeakTmaxNodal_C,row.MaxCellToCellDeltaT_C, ...
                            thermalLimit_C,uniformityLimit_C);
                        if row.Feasible, row.CaseStatus = "Pass"; else, row.CaseStatus = "Fails limits"; end
                    end
                catch MEcase
                    if state.OptimizationStopRequested
                        row.CaseStatus = "Stopped";
                        row.ErrorMessage = "Stopped by user; excluded from feasibility.";
                    else
                        row.CaseStatus = "Failed";
                        row.ErrorMessage = string(MEcase.message) + newline + ...
                            "Stage: " + caseStage + newline + ...
                            "Identifier: " + string(MEcase.identifier) + newline + newline + ...
                            string(getReport(MEcase,"extended","hyperlinks","off"));
                    end
                end
                row.Runtime_s = toc(caseTimer);
                rows(k) = row;
                % Retain every scheduled row, including failed and unrun cases.
                Results = struct2table(rows);
                [Results,Recommendations] = thermalPackOperatingRecommendations( ...
                    Results,state.CoolingSelectionOrder);
                state.LastOptimizationResults = Results;
                state.LastRecommendedCase = Recommendations;
                showOptimizationTable(Results);
                if state.OptimizationStopRequested, break; end
            end
            Results = struct2table(rows);
            [Results,Recommendations] = thermalPackOperatingRecommendations( ...
                Results,state.CoolingSelectionOrder);
            state.LastOptimizationResults = Results;
            state.LastRecommendedCase = Recommendations;
            state.LastOptimizationSettings.StoppedByUser = state.OptimizationStopRequested;
            showOptimizationTable(Results);
            refreshSweepAnalysisPlots(Results);
            failedCases = Results.CaseStatus == "Failed";
            if state.OptimizationStopRequested
                outcome = "Stopped";
            elseif ~any(Results.Success) && any(failedCases)
                outcome = "Failed";
            elseif any(failedCases)
                outcome = "Finished with failures";
            else
                outcome = "Complete";
            end
            optimizationStatus.Text = thermalPackFormatText( ...
                "%s: %d/%d completed; %d failed; %d pass; recommendations for %d/%d inlet temperatures.", ...
                outcome,sum(Results.Success),nCases,sum(failedCases),sum(Results.Feasible), ...
                sum(Results.Recommended),numel(inletTemps));
            optimizationCurrentCase.Text = "Current case: " + lower(outcome);
            if ~any(Results.Success)
                optimizationCurrentCase.Text = ...
                    "No valid simulation results — select an ErrorMessage cell for details.";
            elseif ~any(Results.Feasible)
                optimizationCurrentCase.Text = "No completed case met both limits.";
            end
            statusLabel.Text = "Operating sweep " + lower(outcome) + " — results available to export.";
            if outcome == "Failed"
                firstFailed = find(failedCases,1);
                showOptimizationErrorReport(Results.CaseID(firstFailed), ...
                    Results.ErrorMessage(firstFailed));
            end
        catch ME
            % Save any accumulated cases even if reporting/plotting fails.
            Results = struct2table(rows);
            [Results,Recommendations] = thermalPackOperatingRecommendations( ...
                Results,state.CoolingSelectionOrder);
            state.LastOptimizationResults = Results;
            state.LastRecommendedCase = Recommendations;
            state.LastOptimizationSettings.ReportingError = string(ME.message);
            optimizationStatus.Text = "Sweep interrupted — accumulated cases are available to export.";
            statusLabel.Text = "Operating sweep interrupted";
            uialert(fig,getReport(ME,"extended","hyperlinks","off"), ...
                "ThermalPack — Operating Sweep");
        end
    end

    function showOptimizationCaseError(src,event)
        if state.OptimizationRunning || isempty(event.Indices) || isempty(src.Data)
            return;
        end
        errorColumn = find(strcmp(src.Data.Properties.VariableNames,"ErrorMessage"),1);
        selected = event.Indices(event.Indices(:,2) == errorColumn,:);
        if isempty(selected), return; end
        rowIndex = selected(1,1);
        if rowIndex > height(src.Data), return; end
        messageText = string(src.Data.ErrorMessage(rowIndex));
        if strlength(messageText) == 0, return; end
        showOptimizationErrorReport(src.Data.CaseID(rowIndex),messageText);
    end

    function showOptimizationErrorReport(caseID,messageText)
        % Read-only, scrollable text keeps full diagnostics copyable rather
        % than truncating them to the narrow ErrorMessage table column.
        screen = get(groot,"ScreenSize");
        width = min(900,max(500,screen(3)-80));
        height = min(600,max(350,screen(4)-100));
        errorFig = uifigure("Name",thermalPackFormatText( ...
            "ThermalPack — Sweep Case %d Error",caseID), ...
            "Position",[screen(1)+40 screen(2)+40 width height]);
        errorFig.UserData = struct("ThermalPackOwner",fig);
        errorGrid = uigridlayout(errorFig,[2 1]);
        errorGrid.RowHeight = {38,'1x'};
        errorGrid.Padding = [12 12 12 12];
        errorHeader = uilabel(errorGrid,"Text", ...
            "This case failed. Copy the diagnostic below if you need help; full details are also included in EXPORT SWEEP.", ...
            "WordWrap","on");
        errorHeader.Layout.Row = 1;
        errorText = uitextarea(errorGrid,"Editable","off", ...
            "Value",cellstr(splitlines(string(messageText))));
        errorText.Layout.Row = 2;
    end

    function exportOptimizationResultsCsv(~,~)
        if state.OptimizationRunning || isempty(optimizationTable.Data)
            return;
        end
        defaultName = "ThermalPack_OperatingSweep_Results_" + ...
            string(datetime("now","Format","yyyyMMdd_HHmmss")) + ".csv";
        [fileName,parentFolder] = uiputfile( ...
            {'*.csv','CSV file (*.csv)'}, ...
            'Export the displayed operating-sweep results',defaultName);
        if isequal(fileName,0) || isequal(parentFolder,0)
            return;
        end
        [~,~,fileExtension] = fileparts(fileName);
        if strlength(string(fileExtension)) == 0
            fileName = string(fileName) + ".csv";
        end
        try
            displayedResults = optimizationTable.Data;
            csvHeadings = string(optimizationTable.ColumnName(:).');
            csvHeadings = replace(csvHeadings,"Air Velocity (m/s)", ...
                "Air Inlet Velocity (m/s)");
            csvHeadings = replace(csvHeadings,"Top Flow (kg/s)", ...
                "Top Coolant Mass Flow (kg/s)");
            csvHeadings = replace(csvHeadings,"Bottom Flow (kg/s)", ...
                "Bottom Coolant Mass Flow (kg/s)");
            csvHeadings = replace(csvHeadings,"Side Flow (kg/s)", ...
                "Side Coolant Mass Flow (kg/s)");
            csvHeadings = replace(csvHeadings,"Serpentine Flow (kg/s)", ...
                "Serpentine Coolant Mass Flow (kg/s)");
            csvHeadings = replace(csvHeadings,"Total Flow (kg/s)", ...
                "Total Coolant Mass Flow (kg/s)");
            csvHeadings = replace(csvHeadings,"Top Share (%)", ...
                "Top Flow Share (%)");
            csvHeadings = replace(csvHeadings,"Air Inlet T (°C)", ...
                "Air Inlet Temperature (deg C)");
            csvHeadings = replace(csvHeadings,"Coolant Inlet T (°C)", ...
                "Coolant Inlet Temperature (deg C)");
            csvHeadings = replace(csvHeadings,"Peak Nodal T (°C)", ...
                "Peak Nodal Temperature (deg C)");
            csvHeadings = replace(csvHeadings,"Cell-to-Cell ΔT (°C)", ...
                "Maximum Cell-to-Cell Delta T (deg C)");
            csvHeadings = replace(csvHeadings,"Within-Cell ΔT (°C)", ...
                "Maximum Within-Cell Delta T (deg C)");
            csvHeadings = replace(csvHeadings,"ΔT Margin (°C)", ...
                "Cell-to-Cell Delta T Margin (deg C)");
            csvHeadings = replace(csvHeadings,"T Margin (°C)", ...
                "Temperature Margin (deg C)");
            csvContents = [cellstr(csvHeadings);table2cell(displayedResults)];
            outputFile = fullfile(parentFolder,fileName);
            writecell(csvContents,outputFile);
            optimizationStatus.Text = "Results table exported: " + string(outputFile);
        catch ME
            uialert(fig,ME.message,"ThermalPack — Results CSV Export Error");
        end
    end

    function exportCoolingOptimization(~,~)
        if state.OptimizationRunning || isempty(state.LastOptimizationResults), return; end
        parentFolder = uigetdir(pwd,"Choose a folder for the sweep results");
        if isequal(parentFolder,0), return; end
        try
            exportFolder = fullfile(parentFolder,"ThermalPack_OperatingSweep_" + ...
                string(datetime("now","Format","yyyyMMdd_HHmmss_SSS")));
            mkdir(exportFolder);
            Results = state.LastOptimizationResults;
            Recommendations = state.LastRecommendedCase;
            SweepSettings = state.LastOptimizationSettings;
            writetable(Results,fullfile(exportFolder,"All_Cases.csv"));
            writetable(Recommendations,fullfile(exportFolder,"Recommendations_Per_Inlet.csv"));
            save(fullfile(exportFolder,"Operating_Sweep.mat"), ...
                "Results","Recommendations","SweepSettings");
            state.LastOptimizationFolder = string(exportFolder);
            optimizationStatus.Text = "Sweep exported: " + string(exportFolder);
        catch ME
            uialert(fig,ME.message,"ThermalPack — Sweep Export Error");
        end
    end

    function openValidationCases(~,~)
        validationFig = uifigure( ...
            "Name","ThermalPack — Validation Cases", ...
            "Position",[100 100 940 355], ...
            "WindowStyle","modal");
        movegui(validationFig,"center");

        validationRoot = uigridlayout(validationFig,[1 1]);
        validationRoot.RowHeight = {'1x'};
        validationRoot.ColumnWidth = {'1x'};
        validationRoot.Padding = [10 10 10 10];

        validationTabs = uitabgroup(validationRoot);
        validationTabs.Layout.Row = 1;
        validationTabs.Layout.Column = 1;
        validationTab = uitab(validationTabs, ...
            "Title","Validated Designs from Literature");
        validationGrid = uigridlayout(validationTab,[3 1]);
        validationGrid.RowHeight = {34,'1x','1x'};
        validationGrid.Padding = [12 10 12 12];
        validationGrid.RowSpacing = 8;

        validationIntro = uilabel(validationGrid, ...
            "Text","Select a published case. ThermalPack configures the design and requests confirmation before running.", ...
            "WordWrap","off","HorizontalAlignment","center");
        validationIntro.Layout.Row = 1;

        fanPanel = uipanel(validationGrid, ...
            "Title","Forced-Air Cooling — Fan et al. (2019)", ...
            "FontWeight","bold");
        fanPanel.Layout.Row = 2;
        fanGrid = uigridlayout(fanPanel,[2 1]);
        fanGrid.RowHeight = {32,36};
        fanGrid.Padding = [10 4 10 4];
        fanGrid.RowSpacing = 4;
        fanDescription = uilabel(fanGrid, ...
            "Text","32-cell cylindrical layouts: aligned and staggered, 2C, 20 °C and 0.6–4 m/s; compares maximum, average and cell-to-cell temperatures.", ...
            "WordWrap","off","VerticalAlignment","center");
        fanDescription.Layout.Row = 1;
        fanRunButton = uibutton(fanGrid,"push", ...
            "Text","RUN FORCED-AIR VALIDATION", ...
            "FontWeight","bold", ...
            "ButtonPushedFcn",@(src,event)confirmValidationRun(validationFig,"fan"));
        fanRunButton.Layout.Row = 2;

        bottomPanel = uipanel(validationGrid, ...
            "Title","Bottom Cooling — Bahiraei et al. (2017)", ...
            "FontWeight","bold");
        bottomPanel.Layout.Row = 3;
        bottomGrid = uigridlayout(bottomPanel,[2 1]);
        bottomGrid.RowHeight = {32,36};
        bottomGrid.Padding = [10 4 10 4];
        bottomGrid.RowSpacing = 4;
        bottomDescription = uilabel(bottomGrid, ...
            "Text","Prismatic 6P design: single-channel bottom water cooling, 1 mm plate and 1400 s profile; compares battery and coolant temperatures.", ...
            "WordWrap","off","VerticalAlignment","center");
        bottomDescription.Layout.Row = 1;
        bottomRunButton = uibutton(bottomGrid,"push", ...
            "Text","RUN BOTTOM-COOLING VALIDATION", ...
            "FontWeight","bold", ...
            "ButtonPushedFcn",@(src,event)confirmValidationRun(validationFig,"bottom"));
        bottomRunButton.Layout.Row = 2;
    end

    function confirmValidationRun(validationFig,caseID)
        caseID = string(caseID);
        if caseID == "fan"
            prompt = "Run the Fan et al. (2019) forced-air validation? " + ...
                "This replaces the current setup with the published validation " + ...
                "geometry and runs ten simulations.";
        else
            prompt = "Run the Bahiraei et al. (2017) bottom-cooling validation? " + ...
                "This replaces the current setup with the published 6P design, " + ...
                "rebuilds the battery and runs the 1400 s simulation.";
        end

        answer = uiconfirm(validationFig,prompt,"Confirm Validation Run", ...
            "Options",["Run Validation","Cancel"], ...
            "DefaultOption","Run Validation", ...
            "CancelOption","Cancel");
        if answer ~= "Run Validation"
            return;
        end

        if isvalid(validationFig)
            delete(validationFig);
        end
        drawnow;

        if caseID == "fan"
            runFan2019Figure2Validation([],[]);
        else
            runBottomCoolingValidation([],[]);
        end
    end

    function runFan2019Figure2Validation(~,~)
        % FORCED-AIR VALIDATION — FAN 2019, ALIGNED + STAGGERED.
        %
        % Fan 2019 evaluates the pack at 20 degC and 2C over five inlet
        % velocities. ThermalPack reports three validation quantities:
        %   1) maximum cell temperature rise
        %   2) average cell temperature rise
        %   3) maximum cell-to-cell temperature difference
        %
        % This callback changes test geometry/configuration only. The normal
        % generalized ThermalPack ECM, entropy, distributed cell thermal model,
        % Progressive Gas network, temperature-dependent air properties and AUTO
        % D/Dh selector are used without a validation-only multiplier or override.

        arrangements = ["Aligned","Staggered"];
        velocities_m_s = [0.6 1.0 2.0 3.0 4.0];
        fanRef = fanFigure2ReferenceData();
        nArr = numel(arrangements);
        nVel = numel(velocities_m_s);

        relockFanFigure2Controls();
        progressFanFig2 = uiprogressdlg(fig, ...
            "Title","Forced-Air Validation — Fan 2019", ...
            "Message","Configuring aligned/staggered forced-air validation...", ...
            "Indeterminate","off", ...
            "Value",0);
        cleanupFanFig2 = onCleanup(@restoreFanFigure2Controls); %#ok<NASGU>

        % Model thermal metrics, arrangement x velocity.
        modelMaxRise_C = nan(nArr,nVel);
        modelMaxDelta_C = nan(nArr,nVel);
        modelAvgRise_C = nan(nArr,nVel);

        % Audit quantities proving both layouts use normal generalized physics.
        h_W_m2K = nan(nArr,nVel);
        Re = nan(nArr,nVel);
        Nu = nan(nArr,nVel);
        requestedMdot_kg_s = nan(nArr,nVel);
        loggedMdot_kg_s = nan(nArr,nVel);
        runtime_s = nan(nArr,nVel);
        selectedRegime = strings(nArr,nVel);
        selectedReBasis = strings(nArr,nVel);
        pitchRatioT = nan(nArr,nVel);
        pitchRatioL = nan(nArr,nVel);
        wallRatio = nan(nArr,nVel);
        candidateDh_mm = nan(nArr,nVel);
        detectedArrangement = strings(nArr,1);
        geometrySource = strings(nArr,1);
        detectedColumns = nan(nArr,1);
        columnCounts = cell(nArr,1);

        lastOut = [];
        lastKPI = [];
        lastTrace = [];
        lastProfileDescription = "";
        lastRuntime_s = NaN;

        try
            % Run staggered first and aligned last so normal app use returns to the
            % standard aligned Fan geometry after a successful validation.
            runOrder = [2 1];
            totalCases = nArr*nVel;
            completedCases = 0;

            for orderIndex = 1:numel(runOrder)
                iArr = runOrder(orderIndex);
                arrangementName = arrangements(iArr);

                configureFanFigure2BaseCase();
                if arrangementName == "Staggered"
                    state.ForcedAirCustomGeometryEnabled = true;
                    state.ForcedAirCustomCellCentres_m = fanStaggeredCellCentres();
                    state.ForcedAirCustomGeometryLabel = ...
                        "Fan 2019 staggered 9-column 4/3 layout";
                    expectedColumns = 9;
                    expectedCounts = [4 3 4 3 4 3 4 3 4];
                else
                    state.ForcedAirCustomGeometryEnabled = false;
                    state.ForcedAirCustomCellCentres_m = zeros(0,2);
                    state.ForcedAirCustomGeometryLabel = "";
                    expectedColumns = 8;
                    expectedCounts = 4*ones(1,8);
                end

                progressFanFig2.Value = min(0.88,0.03 + 0.43*(orderIndex-1));
                progressFanFig2.Message = thermalPackFormatText( ...
                    "Rebuilding generalized %s geometry...",arrangementName);
                drawnow;

                state.NeedsRebuild = true;
                rebuildBattery([],[]);
                relockFanFigure2Controls();
                assertFanFigure2ProgressiveBuild(expectedColumns,arrangementName);
                verifyFanFigure2SegmentSOC(1.0);

                geo = forcedAirGeometryAnalysis("X");
                detectedArrangement(iArr) = string(geo.Arrangement);
                geometrySource(iArr) = string(geo.GeometrySource);
                detectedColumns(iArr) = geo.Columns;
                columnCounts{iArr} = double(geo.ColumnCounts(:).');

                if numel(geo.ColumnCounts) ~= numel(expectedCounts) || ...
                        any(double(geo.ColumnCounts(:).') ~= expectedCounts)
                    error("ThermalPack:FanFig2ColumnPopulation", ...
                        "%s geometry produced airflow-column populations [%s], expected [%s].", ...
                        arrangementName, ...
                        strjoin(string(double(geo.ColumnCounts(:).'))," "), ...
                        strjoin(string(expectedCounts)," "));
                end
                if ~(isfinite(geo.ST_m) && isfinite(geo.SL_m) && ...
                        abs(geo.ST_m-22e-3) < 1e-7 && abs(geo.SL_m-22e-3) < 1e-7)
                    error("ThermalPack:FanFig2Pitch", ...
                        "%s geometry must resolve ST = SL = 22 mm; detected %.4f / %.4f mm.", ...
                        arrangementName,1000*geo.ST_m,1000*geo.SL_m);
                end
                if arrangementName == "Aligned" && ...
                        ~startsWith(string(geo.Arrangement),"Aligned")
                    error("ThermalPack:FanFig2ArrangementDetection", ...
                        "Aligned Fan geometry was detected as '%s'.",geo.Arrangement);
                elseif arrangementName == "Staggered" && ...
                        ~startsWith(string(geo.Arrangement),"Staggered")
                    error("ThermalPack:FanFig2ArrangementDetection", ...
                        "Staggered Fan geometry was detected as '%s'.",geo.Arrangement);
                end

                baseLengths_m = state.ProgressiveForcedAirSegmentLengths_m(:);

                for iVel = 1:nVel
                    V = velocities_m_s(iVel);
                    state.ForcedAirVelocity_m_s = V;
                    state.ProgressiveForcedAirSegmentLengths_m = baseLengths_m;

                    calc = forcedAirGeneralCalculation(V,20.0,101325,"X",4.0);
                    updateForcedAirStateFromCalculation(calc);
                    updateProgressiveForcedAirOperatingPoint(calc);
                    applyProgressiveAmbientResistanceToBlocks();

                    cfg = currentSimulationConfig();
                    [simIn,profileDescription] = buildThermalSimulationInput( ...
                        cfg,flowField.Value,20.0);

                    completedCases = completedCases + 1;
                    progressFanFig2.Value = 0.06 + 0.86*(completedCases/totalCases);
                    progressFanFig2.Message = thermalPackFormatText( ...
                        "%s — %.1f m/s (%d/%d)...", ...
                        arrangementName,V,completedCases,totalCases);
                    drawnow;

                    tRun = tic;
                    out = sim(simIn);
                    runtime_s(iArr,iVel) = toc(tRun);
                    [KPI,Trace] = extractUIResults(out,cfg);

                    met = fanFigure2EndMetrics(Trace,20.0);
                    modelMaxRise_C(iArr,iVel) = met.MaxRise_C;
                    modelMaxDelta_C(iArr,iVel) = met.MaxDelta_C;
                    modelAvgRise_C(iArr,iVel) = met.AvgRise_C;

                    h_W_m2K(iArr,iVel) = calc.h_W_m2K;
                    Re(iArr,iVel) = calc.Re;
                    Nu(iArr,iVel) = calc.Nu;
                    requestedMdot_kg_s(iArr,iVel) = calc.MassFlow_kg_s;
                    selectedRegime(iArr,iVel) = string(calc.CylindricalRegime);
                    selectedReBasis(iArr,iVel) = ...
                        string(calc.CylindricalReLengthSelected);
                    pitchRatioT(iArr,iVel) = calc.CylindricalPitchRatioT;
                    pitchRatioL(iArr,iVel) = calc.CylindricalPitchRatioL;
                    wallRatio(iArr,iVel) = calc.CylindricalWallRatioLeft;
                    candidateDh_mm(iArr,iVel) = 1000*calc.CylindricalCandidateDh_m;
                    if isfield(KPI,"GasMassFlow_kg_s")
                        loggedMdot_kg_s(iArr,iVel) = KPI.GasMassFlow_kg_s;
                    end

                    % Leave the dashboard synchronized with aligned 4 m/s.
                    if arrangementName == "Aligned" && iVel == nVel
                        lastOut = out;
                        lastKPI = KPI;
                        lastTrace = Trace;
                        lastProfileDescription = profileDescription;
                        lastRuntime_s = runtime_s(iArr,iVel);
                    end
                end
            end

            state.ForcedAirCustomGeometryEnabled = false;
            state.ForcedAirCustomCellCentres_m = zeros(0,2);
            state.ForcedAirCustomGeometryLabel = "";

            %% Validation statistics: each metric, separately for each layout.
            metricNames = [ ...
                "Maximum cell temperature rise"; ...
                "Average cell temperature rise"; ...
                "Maximum cell-to-cell temperature difference"];
            fanMetric = cat(3,fanRef.MaxRise_C,fanRef.AvgRise_C,fanRef.MaxDelta_C);
            modelMetric = cat(3,modelMaxRise_C,modelAvgRise_C,modelMaxDelta_C);

            statsArrangement = strings(nArr*numel(metricNames),1);
            statsMetric = strings(nArr*numel(metricNames),1);
            statsRMSE = nan(nArr*numel(metricNames),1);
            statsMAE = nan(nArr*numel(metricNames),1);
            statsMBE = nan(nArr*numel(metricNames),1);
            statsR2 = nan(nArr*numel(metricNames),1);
            statsN = nan(nArr*numel(metricNames),1);
            srow = 0;
            for iArr = 1:nArr
                for iMetric = 1:numel(metricNames)
                    srow = srow + 1;
                    refSeries = reshape(fanMetric(iArr,:,iMetric),1,[]);
                    modelSeries = reshape(modelMetric(iArr,:,iMetric),1,[]);
                    st = fanValidationStatistics(refSeries,modelSeries);
                    statsArrangement(srow) = arrangements(iArr);
                    statsMetric(srow) = metricNames(iMetric);
                    statsRMSE(srow) = st.RMSE;
                    statsMAE(srow) = st.MAE;
                    statsMBE(srow) = st.MBE;
                    statsR2(srow) = st.R2;
                    statsN(srow) = st.N;
                end
            end
            statsTable = table(statsArrangement,statsMetric,statsRMSE,statsMAE, ...
                statsMBE,statsR2,statsN, ...
                'VariableNames',{'Arrangement','ValidationMetric','RMSE_C','MAE_C', ...
                                 'MBE_C_ModelMinusFan','R2','N'});

            %% Detailed 10-case audit table.
            nRows = nArr*nVel;
            arrCol = strings(nRows,1); velCol = nan(nRows,1);
            fanMaxRiseCol = nan(nRows,1); modelMaxRiseCol = nan(nRows,1);
            fanMaxDeltaCol = nan(nRows,1); modelMaxDeltaCol = nan(nRows,1);
            fanAvgRiseCol = nan(nRows,1); modelAvgRiseCol = nan(nRows,1);
            hCol = nan(nRows,1); reCol = nan(nRows,1); nuCol = nan(nRows,1);
            reqMdotCol = nan(nRows,1); logMdotCol = nan(nRows,1);
            regimeCol = strings(nRows,1); basisCol = strings(nRows,1);
            detectedArrCol = strings(nRows,1); nColumnsCol = nan(nRows,1);
            stOverDCol = nan(nRows,1); slOverDCol = nan(nRows,1);
            wallRatioCol = nan(nRows,1); dhCol = nan(nRows,1);
            geomSourceCol = strings(nRows,1); runtimeCol = nan(nRows,1);
            refTypeCol = strings(nRows,1);
            row = 0;
            for iArr = 1:nArr
                for iVel = 1:nVel
                    row = row + 1;
                    arrCol(row) = arrangements(iArr);
                    velCol(row) = velocities_m_s(iVel);
                    fanMaxRiseCol(row) = fanRef.MaxRise_C(iArr,iVel);
                    modelMaxRiseCol(row) = modelMaxRise_C(iArr,iVel);
                    fanMaxDeltaCol(row) = fanRef.MaxDelta_C(iArr,iVel);
                    modelMaxDeltaCol(row) = modelMaxDelta_C(iArr,iVel);
                    fanAvgRiseCol(row) = fanRef.AvgRise_C(iArr,iVel);
                    modelAvgRiseCol(row) = modelAvgRise_C(iArr,iVel);
                    hCol(row) = h_W_m2K(iArr,iVel);
                    reCol(row) = Re(iArr,iVel);
                    nuCol(row) = Nu(iArr,iVel);
                    reqMdotCol(row) = requestedMdot_kg_s(iArr,iVel);
                    logMdotCol(row) = loggedMdot_kg_s(iArr,iVel);
                    regimeCol(row) = selectedRegime(iArr,iVel);
                    basisCol(row) = selectedReBasis(iArr,iVel);
                    detectedArrCol(row) = detectedArrangement(iArr);
                    nColumnsCol(row) = detectedColumns(iArr);
                    stOverDCol(row) = pitchRatioT(iArr,iVel);
                    slOverDCol(row) = pitchRatioL(iArr,iVel);
                    wallRatioCol(row) = wallRatio(iArr,iVel);
                    dhCol(row) = candidateDh_mm(iArr,iVel);
                    geomSourceCol(row) = geometrySource(iArr);
                    runtimeCol(row) = runtime_s(iArr,iVel);
                    refTypeCol(row) = fanRef.ReferenceType;
                end
            end
            auditTable = table(arrCol,velCol, ...
                fanMaxRiseCol,modelMaxRiseCol,fanMaxDeltaCol,modelMaxDeltaCol, ...
                fanAvgRiseCol,modelAvgRiseCol, ...
                hCol,reCol,nuCol,reqMdotCol,logMdotCol,detectedArrCol,nColumnsCol, ...
                regimeCol,basisCol,stOverDCol,slOverDCol,wallRatioCol,dhCol, ...
                geomSourceCol,refTypeCol,runtimeCol, ...
                'VariableNames',{ ...
                    'Arrangement','Velocity_m_s', ...
                    'FanMaxRise_C','GeneralizedMaxRise_C', ...
                    'FanMaxDelta_C','GeneralizedMaxDelta_C', ...
                    'FanAvgRise_C','GeneralizedAvgRise_C', ...
                    'h_W_m2K','Re','Nu','RequestedAirMassFlow_kg_s', ...
                    'LoggedAirMassFlow_kg_s','DetectedArrangement', ...
                    'DetectedAirColumns','CylindricalRegime','ReLengthBasis', ...
                    'ST_over_D','SL_over_D','WallGap_over_TransverseGap', ...
                    'CandidateDh_mm','GeometrySource','FanReferenceType','Runtime_s'});

            state.FanFigure2ValidationStatistics = statsTable;
            state.FanFigure2ValidationResults = auditTable;
            state.FanFigure2Reference = fanRef;
            state.FanFigure2Model.MaxRise_C = modelMaxRise_C;
            state.FanFigure2Model.MaxDelta_C = modelMaxDelta_C;
            state.FanFigure2Model.AvgRise_C = modelAvgRise_C;
            state.FanFigure2ColumnCounts = columnCounts;

            %% Forced-air validation post-processing: three thermal metrics.
            showForcedAirValidationWindow( ...
                velocities_m_s,fanRef,modelMaxRise_C,modelAvgRise_C,modelMaxDelta_C, ...
                statsTable,auditTable,false);

            if ~isempty(lastKPI)
                state.LastKPI = lastKPI;
                state.LastTrace = lastTrace;
                state.LastRuntime_s = lastRuntime_s;
                state.LastCurrentProfileDescription = lastProfileDescription;
                try
                    refreshThermalAnimation(lastOut,lastTrace);
                catch
                end
            end

            % Headline status uses max-temperature-rise statistics, while the full
            % table reports all reported statistics for both arrangements and all three validation metrics.
            aMax = statsTable(statsTable.Arrangement=="Aligned" & ...
                statsTable.ValidationMetric=="Maximum cell temperature rise",:);
            sMax = statsTable(statsTable.Arrangement=="Staggered" & ...
                statsTable.ValidationMetric=="Maximum cell temperature rise",:);
            progressFanFig2.Value = 1;
            progressFanFig2.Message = thermalPackFormatText( ...
                "Complete — max-rise RMSE: aligned %.2f C | staggered %.2f C", ...
                aMax.RMSE_C,sMax.RMSE_C);
            statusLabel.Text = thermalPackFormatText( ...
                ["Forced-air validation complete — max-rise RMSE A %.2f C / S %.2f C | " ...
                 "AUTO basis A %s / S %s"], ...
                aMax.RMSE_C,sMax.RMSE_C,selectedReBasis(1,1),selectedReBasis(2,1));
            drawnow;

        catch ME
            state.ForcedAirCustomGeometryEnabled = false;
            state.ForcedAirCustomCellCentres_m = zeros(0,2);
            state.ForcedAirCustomGeometryLabel = "";
            state.NeedsRebuild = true;
            statusLabel.Text = "Forced-air validation failed — rebuild required";
            uialert(fig,getReport(ME,"extended","hyperlinks","off"), ...
                "ThermalPack — Forced-Air Validation Error");
        end

        function configureFanFigure2BaseCase()
            % Full published Fan base case reset for every arrangement.
            state.ForcedAirCustomGeometryEnabled = false;
            state.ForcedAirCustomCellCentres_m = zeros(0,2);
            state.ForcedAirCustomGeometryLabel = "";

            formatField.Value = "Cylindrical";
            cellFormatChanged([],[]);
            topologyField.Value = "Square";
            parallelField.Value = 4;
            rowsField.Value = 1;
            parallelStackingAxisField.Value = "Y";
            seriesField.Value = 8;
            moduleStackingAxisField.Value = "X";
            massFactorField.Value = 1.0;
            cellGapField.Value = 4.0;
            assemblyGapField.Value = 4.0;
            diameterField.Value = 18.0;
            heightField.Value = 65.0;

            state.CellFormat = "Cylindrical";
            state.P = 4; state.S = 8; state.TotalCells = 32;
            state.Topology = "Square"; state.Rows = 1;
            state.ParallelAssemblyStackingAxis = "Y";
            state.ModuleStackingAxis = "X";
            state.MassFactor = 1.0;
            state.Diameter_mm = 18.0; state.Height_mm = 65.0;
            state.InterCellGap_mm = 4.0; state.InterAssemblyGap_mm = 4.0;
            state.Cylindrical.P = 4; state.Cylindrical.S = 8;
            state.Cylindrical.Topology = "Square";
            state.Cylindrical.Rows = 1;
            state.Cylindrical.StackingAxis = "Y";
            state.Cylindrical.Diameter_mm = 18.0;
            state.Cylindrical.Height_mm = 65.0;

            massField.Value = 0.049;
            capacityField.Value = 3.5;
            energyField.Value = 12.6;
            thermalMassField.Value = 0.049*912;
            conductivityField.Value = 15.0;
            nodesField.Value = 6;
            state.Cylindrical.Mass_kg = massField.Value;
            state.Cylindrical.Capacity_Ah = capacityField.Value;
            state.Cylindrical.Energy_Wh = energyField.Value;
            state.Cylindrical.ThermalMass_J_K = thermalMassField.Value;
            state.Cylindrical.ConductivityZ_W_mK = conductivityField.Value;
            state.Cylindrical.ThermalAreaMode = "Automatic";
            updateThermalAreaForActiveFormat();

            interCellHeatField.Value = "Disabled";
            state.InterCellHeatTransfer = "Disabled";
            interCellRField.Enable = "off";
            interParallelRField.Enable = "off";

            fanECM = thermalPackFanValidationECMData(state.OCVSOCBreakpoints);
            state.ExtrapolationMethod = "Nearest";
            state.ResistanceSOCBreakpoints = fanECM.ResistanceSOC;
            state.ResistanceTemperature_C = fanECM.ResistanceTemperature_C;
            state.R0Table_Ohm = fanECM.R0Table_Ohm;
            state.PolarizationModel = "RC1";
            state.R1Table_Ohm = fanECM.R1Table_Ohm;
            state.Tau1Table_s = fanECM.Tau1Table_s;
            state.R2Table_Ohm = zeros(size(fanECM.R0Table_Ohm));
            state.Tau2Table_s = ones(size(fanECM.R0Table_Ohm));
            state.EntropicHeatEnabled = true;
            state.EntropicCoefficient_mV_K = fanECM.EntropicCoefficient_mV_K;
            state.R0Deviation_pct = zeros(32,1);
            state.ThermalMassDeviation_pct = zeros(32,1);
            state.ThermalConductivityDeviation_pct = zeros(32,1);
            saveElectricalStateForFormat("Cylindrical");

            socField.Value = 1.0;
            initialCellTempField.Value = 20.0;
            state.InitialCellTemperature_C = 20.0;
            ambientField.Value = 20.0;
            tinField.Value = 20.0;
            stopField.Value = 1800;
            loadProfileField.Value = "Custom";
            state.LoadProfile = "Custom";
            state.LastValidLoadProfile = "Custom";
            state.CustomCurrentProfile = [0 -28; 1800 -28];
            state.Solver = "ode23t";

            state.ForcedAirModel = "Progressive Gas";
            state.ForcedAirVelocity_m_s = 2.0;
            state.ForcedAirTemperature_C = 20.0;
            state.ForcedAirPressure_Pa = 101325;
            state.ForcedAirAxis = "X";
            state.ForcedAirWallClearance_mm = 4.0;
            state.ForcedAirExposedAreaFraction = 1.0;
            state.AtmosphericPressure_Pa = 101325;
            state.ForcedAirCylindricalReLengthMode = "Auto";

            coolingPlateField.Value = "Forced Air Cooling";
            state.CoolingPlateMode = "Forced Air Cooling";
            coolingModeChanged([],[]);
        end

        function centres_m = fanStaggeredCellCentres()
            % Fan Fig. 3 schematic: 32 cells represented by nine flowwise
            % staggered columns with alternating 4/3 populations. The 4-cell
            % columns are at the base transverse phase; the 3-cell columns are
            % shifted by one-half transverse pitch. 5*4 + 4*3 = 32 cells.
            % This geometry changes coordinates only; all downstream physics is
            % the normal generalized ThermalPack implementation.
            D_m = 18e-3;
            ST_m = 22e-3;
            SL_m = 22e-3;
            counts = [4 3 4 3 4 3 4 3 4];
            centres_m = zeros(sum(counts),2);
            idx = 1;
            for col = 1:numel(counts)
                x_m = 0.5*D_m + (col-1)*SL_m;
                if mod(col,2) == 1
                    y0_m = 0.5*D_m;
                else
                    y0_m = 0.5*D_m + 0.5*ST_m;
                end
                for rr = 1:counts(col)
                    centres_m(idx,:) = [x_m y0_m + (rr-1)*ST_m];
                    idx = idx + 1;
                end
            end
        end


        function assertFanFigure2ProgressiveBuild(expectedColumns,arrangementName)
            if state.NeedsRebuild
                error("ThermalPack:FanFig2Rebuild", ...
                    "%s Fan Figure-2 rebuild did not complete.",arrangementName);
            end
            if ~state.ProgressiveForcedAirBuilt
                error("ThermalPack:FanFig2ProgressiveGas", ...
                    "%s Fan Figure-2 arrangement did not build Progressive Gas.",arrangementName);
            end
            if numel(state.ProgressiveForcedAirChamberBlocks) ~= expectedColumns
                error("ThermalPack:FanFig2Columns", ...
                    "%s geometry expected %d gas columns; generated %d.", ...
                    arrangementName,expectedColumns, ...
                    numel(state.ProgressiveForcedAirChamberBlocks));
            end
        end

        function verifyFanFigure2SegmentSOC(expectedSOC)
            for kk = 1:numel(state.ProgressiveForcedAirSegmentBlocks)
                ids = state.ProgressiveForcedAirSegmentCellIDs{kk};
                verifyInitialSOCOnBlock( ...
                    state.ProgressiveForcedAirSegmentBlocks(kk), ...
                    expectedSOC,numel(ids),1);
            end
        end

        function ref = fanFigure2ReferenceData()
            % Fan et al. (Applied Thermal Engineering 155, 2019), Fig. 2.
            % The publication presents these as plotted curves rather than a
            % numerical data table. Keep all digitized values isolated here so a
            % higher-resolution re-digitization can replace them without touching
            % the generalized simulation or the statistical/post-processing code.
            % Rows: 1 = aligned, 2 = staggered.
            % Columns: V = [0.6 1 2 3 4] m/s.
            ref.Velocity_m_s = [0.6 1.0 2.0 3.0 4.0];

            % Max-rise aligned row retains the established Fan benchmark used by
            % the earlier ThermalPack validation. Staggered values preserve the
            % Fig. 3 endpoint digitization and the reported ~7 C 0.6->1 m/s drop.
            ref.MaxRise_C = [ ...
                34.0 24.0 21.0 17.5 14.0; ...
                35.0 28.0 23.0 19.0 15.0];

            % Approximate Fig. 2(b-d) digitization. These affect comparison only.
            ref.MaxDelta_C = [ ...
                17.0 13.0 10.0  9.0  8.0; ...
                21.0 16.0 12.5 10.5  9.0];
            ref.AvgRise_C = [ ...
                25.5 18.5 15.2 12.8 10.8; ...
                26.5 21.0 16.8 14.2 12.0];
            ref.SigmaRise_C = [ ...
                 5.3  4.0  3.1  2.7  2.4; ...
                 6.2  4.8  3.7  3.1  2.7];

            ref.ReferenceType = "Approx. digitization of Fan 2019 Fig. 2";
        end

        function met = fanFigure2EndMetrics(Trace,T0_C)
            T = double(Trace.Tcell_C);
            if isempty(T) || size(T,2) ~= state.TotalCells
                error("ThermalPack:FanFig2Trace", ...
                    "Expected cell-average temperature traces for %d cells.", ...
                    state.TotalCells);
            end
            lastRow = find(any(isfinite(T),2),1,"last");
            if isempty(lastRow)
                error("ThermalPack:FanFig2Trace", ...
                    "No finite cell-temperature samples were logged.");
            end
            rise = T(lastRow,:) - T0_C;
            rise = rise(isfinite(rise));
            if numel(rise) < 2
                error("ThermalPack:FanFig2Trace", ...
                    "At least two finite cell temperatures are required.");
            end
            met.MaxRise_C = max(rise);
            met.MaxDelta_C = max(rise)-min(rise);
            met.AvgRise_C = mean(rise);
            % Fan's standard-deviation definition uses n-1 in the denominator.
            met.SigmaRise_C = std(rise,0);
        end

        function st = fanValidationStatistics(refSeries,modelSeries)
            refSeries = double(refSeries(:));
            modelSeries = double(modelSeries(:));
            valid = isfinite(refSeries) & isfinite(modelSeries);
            y = refSeries(valid);
            yhat = modelSeries(valid);
            st.N = numel(y);
            if st.N == 0
                st.RMSE = NaN; st.MAE = NaN; st.MBE = NaN; st.R2 = NaN;
                return;
            end
            e = yhat-y;
            st.RMSE = sqrt(mean(e.^2));
            st.MAE = mean(abs(e));
            st.MBE = mean(e); % Positive = generalized model predicts larger metric.
            sst = sum((y-mean(y)).^2);
            if sst > eps(max(1,max(abs(y))))
                st.R2 = 1-sum(e.^2)/sst;
            else
                st.R2 = NaN;
            end
        end

        function relockFanFigure2Controls()
            validationCasesButton.Enable = "off";
            rebuildButton.Enable = "off";
            runButton.Enable = "off";
            optimizationRunButton.Enable = "off";
            designOptimizationRunButton.Enable = "off";
        end

        function restoreFanFigure2Controls()
            try
                if isvalid(progressFanFig2), close(progressFanFig2); end
            catch
            end
            try
                validationCasesButton.Enable = "on";
                rebuildButton.Enable = "on";
                runButton.Enable = "on";
                optimizationRunButton.Enable = "on";
                refreshDesignOptimizationControls();
            catch
            end
        end
    end



    function showForcedAirValidationWindow(V,fanRef,modelMaxRise_C, ...
            modelAvgRise_C,modelMaxDelta_C,statsTable,~,previewOnly)
        % Final forced-air validation presentation window.

        resultScreen = get(groot,"ScreenSize");
        resultW = min(1720,max(1250,resultScreen(3)-60));
        resultH = min(980,max(760,resultScreen(4)-70));
        resultX = resultScreen(1) + max(15,(resultScreen(3)-resultW)/2);
        resultY = resultScreen(2) + max(20,(resultScreen(4)-resultH)/2);

        resultFig = uifigure( ...
            "Name","ThermalPack Forced-Air Validation — Fan 2019", ...
            "Position",[resultX resultY resultW resultH]);
        cg = uigridlayout(resultFig,[2 3]);
        cg.RowHeight = {64,'1x'};
        cg.ColumnWidth = {'1x','1x','1x'};
        cg.Padding = [12 10 12 10];
        cg.RowSpacing = 9;
        cg.ColumnSpacing = 10;

        % Preview and completed validation use the exact same compact
        % two-line presentation heading.
        headingText = [ ...
            "ThermalPack Forced-Air Validation — Fan 2019" + newline + ...
            "Aligned & Staggered Cylindrical Cell Arrangements | 2C | 20 °C Inlet | 0.6–4 m/s"];

        note = uilabel(cg, ...
            "Text",headingText, ...
            "FontWeight","bold", ...
            "HorizontalAlignment","center", ...
            "WordWrap","on");
        note.Layout.Row = 1;
        note.Layout.Column = [1 3];

        ax1 = uiaxes(cg); ax1.Layout.Row=2; ax1.Layout.Column=1;
        plotValidationMetric(ax1,V,fanRef.MaxRise_C,modelMaxRise_C, ...
            "Maximum Cell Temperature Rise","Temperature rise (°C)", ...
            "Maximum cell temperature rise");

        ax2 = uiaxes(cg); ax2.Layout.Row=2; ax2.Layout.Column=2;
        plotValidationMetric(ax2,V,fanRef.AvgRise_C,modelAvgRise_C, ...
            "Average Cell Temperature Rise","Temperature rise (°C)", ...
            "Average cell temperature rise");

        ax3 = uiaxes(cg); ax3.Layout.Row=2; ax3.Layout.Column=3;
        plotValidationMetric(ax3,V,fanRef.MaxDelta_C,modelMaxDelta_C, ...
            "Maximum Cell-to-Cell Temperature Difference", ...
            "Temperature difference (°C)", ...
            "Maximum cell-to-cell temperature difference");

        function plotValidationMetric(ax,Vplot,fanData,modelData, ...
                plotTitle,yLabelText,metricKey)
            cla(ax);
            hold(ax,"on");

            alignedStats = statsTable( ...
                statsTable.Arrangement=="Aligned" & ...
                statsTable.ValidationMetric==metricKey,:);
            staggeredStats = statsTable( ...
                statsTable.Arrangement=="Staggered" & ...
                statsTable.ValidationMetric==metricKey,:);

            alignedLegend = validationStatsLegendText( ...
                "ThermalPack aligned",alignedStats);
            staggeredLegend = validationStatsLegendText( ...
                "ThermalPack staggered",staggeredStats);

            plot(ax,Vplot,fanData(1,:),"--o","LineWidth",1.7, ...
                "DisplayName","Fan aligned");
            plot(ax,Vplot,modelData(1,:),"-s","LineWidth",1.7, ...
                "DisplayName",alignedLegend);
            plot(ax,Vplot,fanData(2,:),"--o","LineWidth",1.7, ...
                "DisplayName","Fan staggered");
            plot(ax,Vplot,modelData(2,:),"-s","LineWidth",1.7, ...
                "DisplayName",staggeredLegend);

            hold(ax,"off");
            grid(ax,"on");
            xlabel(ax,"Air inlet velocity (m/s)");
            ylabel(ax,yLabelText);
            title(ax,plotTitle);

            lgd = legend(ax,"Location","southoutside");
            try
                lgd.FontSize = 9;
            catch
            end

            xlim(ax,[min(Vplot) max(Vplot)]);
        end

        function txt = validationStatsLegendText(prefix,statRow)
            if isempty(statRow)
                txt = prefix + " | statistics unavailable";
                return;
            end

            rmse = statRow.RMSE_C(1);
            mae = statRow.MAE_C(1);
            mbe = statRow.MBE_C_ModelMinusFan(1);
            r2 = statRow.R2(1);

            txt = thermalPackFormatText( ...
                "%s | RMSE %.2f°C | MAE %.2f°C | MBE %+.2f°C | R² %.3f", ...
                prefix,rmse,mae,mbe,r2);
        end
    end

    function exportSimulationResultsToExcel(~,~)
        if isempty(state.LastTrace) || isempty(state.LastKPI)
            uialert(fig,"Run a successful simulation before exporting results.","ThermalPack — Excel Export"); return;
        end
        [fileName,pathName]=uiputfile({'*.xlsx','Excel workbook (*.xlsx)'}, ...
            'Export ThermalPack Simulation Results', ...
            fullfile(char(baseFolder),char("ThermalPack_Results_" + string(datetime("now","Format","yyyyMMdd_HHmmss")) + ".xlsx")));
        if isequal(fileName,0) || isequal(pathName,0), return; end
        targetFile=fullfile(pathName,fileName);
        if isfile(targetFile), delete(targetFile); end
        try
            T=state.LastTrace; KPI=state.LastKPI; t=double(T.tCell(:));
            avgT=double(T.TmeanCellAverage_C(:)); maxCell=double(T.TmaxCellAverage_C(:)); minCell=double(T.TminCellAverage_C(:));
            spread=maxCell-minCell;
            maxNode=thermalPackInterpolateTrace(T.tNodes,T.TmaxNodal_C,t);
            minNode=thermalPackInterpolateTrace(T.tNodes,T.TminNodal_C,t);
            dNode=thermalPackInterpolateTrace(T.tNodes,T.deltaTNodal_C,t);
            Tin=NaN(size(t)); Tout=NaN(size(t)); dTc=NaN(size(t)); coolantStatus="Not available";
            C=state.LastCoolantTrace;
            if isstruct(C) && isfield(C,"Available") && logical(C.Available)
                Tin=thermalPackInterpolateTrace(C.Time_s,C.Inlet_C,t);
                Tout=thermalPackInterpolateTrace(C.Time_s,C.CombinedOutlet_C,t);
                dTc=Tout-Tin; coolantStatus=string(C.Status);
            elseif isstruct(C) && isfield(C,"Status")
                coolantStatus=string(C.Status);
            end
            batteryTS=table(t,avgT,maxCell,minCell,spread,maxNode,minNode,dNode,Tin,Tout,dTc, ...
                'VariableNames',{'Time_s','Battery_CombinedCells_AvgTemp_C','Battery_MaxCellAverageTemp_C', ...
                'Battery_MinCellAverageTemp_C','Battery_CellAverageTempDifference_C','Battery_MaxNodalTemp_C', ...
                'Battery_MinNodalTemp_C','Battery_NodalTempDifference_C','Coolant_InletTemp_C', ...
                'Coolant_OutletTemp_C','Coolant_TemperatureDifference_C'});
            n=size(T.Tcell_C,2); names=cellstr(compose("Cell_%d_AvgTemp_C",1:n));
            cellTS=array2table([t double(T.Tcell_C)],'VariableNames',[{'Time_s'} names]);
            nodalTS=table(double(T.tNodes(:)),double(T.TmaxNodal_C(:)),double(T.TminNodal_C(:)),double(T.deltaTNodal_C(:)), ...
                'VariableNames',{'Time_s','Battery_MaxNodalTemp_C','Battery_MinNodalTemp_C','Battery_NodalTempDifference_C'});
            summary={'Metric','Value','Unit';
                'Cell format',char(string(state.CellFormat)),'';
                'Architecture',thermalPackFormatText('%dP x %dS = %d cells',state.P,state.S,state.TotalCells),'';
                'Cooling architecture',char(string(state.CoolingPlateMode)),'';
                'Peak combined-cells average temperature',max(avgT,[],'omitnan'),'degC';
                'Battery maximum temperature (nodal)',KPI.PeakTmaxNodal_C,'degC';
                'Maximum cell-average temperature difference',max(spread,[],'omitnan'),'degC';
                'Maximum nodal temperature difference',KPI.MaxDeltaTNodal_C,'degC';
                'Coolant status',char(coolantStatus),'';
                'Maximum coolant temperature rise',thermalPackSafeMax(dTc),'degC';
                'Final coolant temperature rise',thermalPackLastFinite(dTc),'degC'};
            writecell(summary,targetFile,"Sheet","Summary","Range","A1");
            writetable(batteryTS,targetFile,"Sheet","Battery Time Series");
            writetable(cellTS,targetFile,"Sheet","Cell Temperatures");
            writetable(nodalTS,targetFile,"Sheet","Nodal Summary");
            if isstruct(C) && isfield(C,"Available") && logical(C.Available)
                coolT=table(C.Time_s(:),C.Inlet_C(:),C.CombinedOutlet_C(:),C.DeltaT_C(:), ...
                    'VariableNames',{'Time_s','Coolant_InletTemp_C','Coolant_CombinedOutletTemp_C','Coolant_TemperatureDifference_C'});
                if isfield(C,"BranchNames") && isfield(C,"BranchOutlet_C")
                    for k=1:numel(C.BranchNames)
                        vn=matlab.lang.makeValidName("Outlet_"+string(C.BranchNames(k))+"_C"); coolT.(vn)=C.BranchOutlet_C(:,k);
                    end
                end
                writetable(coolT,targetFile,"Sheet","Coolant");
            else
                writecell({'Coolant temperature output unavailable';char(coolantStatus)},targetFile,"Sheet","Coolant","Range","A1");
            end
        catch ME
            uialert(fig,getReport(ME,"extended","hyperlinks","off"),"ThermalPack — Excel Export Error"); return;
        end
        statusLabel.Text="Simulation results exported — "+string(fileName);
        uialert(fig,"Excel export complete.","ThermalPack — Results Exported","Icon","success");
    end

    function coolant = extractCoolantTraceForExport(out)
        coolant=struct("Available",false,"Status","Coolant temperature not applicable or not resolved", ...
            "Time_s",[],"Inlet_C",[],"CombinedOutlet_C",[],"DeltaT_C",[],"BranchNames",strings(0,1),"BranchOutlet_C",zeros(0,0));
        mode=string(state.CoolingPlateMode);
        if any(mode==["Forced Air Cooling","No Cooling Plate"]), coolant.Status="No active liquid coolant for "+mode; return; end
        try, simlog=out.simlog; catch, try, simlog=out.get("simlog"); catch, simlog=[]; end, end
        if isempty(simlog), coolant.Status="Simscape log unavailable"; return; end
        switch mode
            case "Bottom Cooling Plate", names="Bottom"; blocks=bottomPlateBlock; flows=state.LastBottomCoolantFlow;
            case "Top Cooling Plate", names="Top"; blocks=topPlateBlock; flows=state.LastTopCoolantFlow;
            case "Top + Bottom Cooling", names=["Top";"Bottom"]; blocks=[topPlateBlock;bottomPlateBlock]; flows=[state.LastTopCoolantFlow;state.LastBottomCoolantFlow];
            case "Side Cooling"
                ix=find(sideBoundaryNames==state.SideBoundary,1); if isempty(ix), return; end
                names="Side_"+state.SideBoundary; blocks=sidePlateBlocks(ix); flows=state.LastSideCoolantFlow;
            case "Serpentine Cooling", names="Serpentine"; blocks=serpentinePlateBlock; flows=state.LastSerpentineCoolantFlow;
            otherwise, return;
        end
        active=isfinite(flows) & abs(flows)>0; if ~any(active), coolant.Status="Active coolant flow is zero"; return; end
        names=names(active); blocks=blocks(active); flows=flows(active);
        tt=cell(numel(names),1); yy=cell(numel(names),1); ok=false(numel(names),1);
        for k=1:numel(names), [tt{k},yy{k},ok(k)]=tryReadCoolingPlateOutletTemperature(simlog,blocks(k)); end
        if ~any(ok), coolant.Status="Could not resolve fluid_out temperature from cooling-plate Simscape log"; return; end
        r=find(ok,1); tref=tt{r}(:); outT=NaN(numel(tref),numel(names)); w=zeros(numel(names),1);
        for k=1:numel(names)
            if ok(k), outT(:,k)=thermalPackInterpolateTrace(tt{k},yy{k},tref); w(k)=abs(flows(k)); end
        end
        good=w>0 & any(isfinite(outT),1).'; if ~any(good), return; end
        combined=sum(outT(:,good).*reshape(w(good),1,[]),2,"omitnan")/sum(w(good));
        inlet=repmat(tinField.Value,numel(tref),1);
        coolant.Available=true; coolant.Status="Liquid coolant outlet temperature resolved"; coolant.Time_s=tref; coolant.Inlet_C=inlet;
        coolant.CombinedOutlet_C=combined; coolant.DeltaT_C=combined-inlet; coolant.BranchNames=names; coolant.BranchOutlet_C=outT;
    end

    function [t,Tc,ok]=tryReadCoolingPlateOutletTemperature(simlog,blockPath)
        t=[]; Tc=[]; ok=false; try, node=simscape.logging.findNode(simlog,string(blockPath)); catch, node=[]; end; if isempty(node), return; end
        ports=["fluid_out","B","outlet","Out"]; vars=["T","temperature","Temperature"];
        for i=1:numel(ports)
            try, p=node.(char(ports(i))); catch, continue; end
            for j=1:numel(vars)
                try
                    s=p.(char(vars(j))).series; v=s.values("K"); t=double(time(s)); Tc=double(v(:))-273.15; t=t(:);
                    if numel(t)==numel(Tc) && any(isfinite(Tc)), ok=true; return; end
                catch
                end
            end
        end
    end

    function yq = thermalPackInterpolateTrace(t,y,tq)
        t = double(t(:));
        y = double(y(:));
        tq = double(tq(:));

        good = isfinite(t) & isfinite(y);
        t = t(good);
        y = y(good);

        if isempty(t)
            yq = NaN(size(tq));
            return;
        end

        [t,ia] = unique(t,"stable");
        y = y(ia);

        if numel(t) == 1
            yq = repmat(y(1),size(tq));
        else
            yq = interp1(t,y,tq,"linear",NaN);
        end
    end

    function v = thermalPackSafeMax(x)
        x = double(x(:));
        x = x(isfinite(x));
        if isempty(x)
            v = NaN;
        else
            v = max(x);
        end
    end

    function v = thermalPackLastFinite(x)
        x = double(x(:));
        ix = find(isfinite(x),1,"last");
        if isempty(ix)
            v = NaN;
        else
            v = x(ix);
        end
    end


    function runBottomCoolingValidation(~,~)
        % Retained 1400-s Bahiraei paper-geometry case.
        % Preserve its electrical, thermal, current and cooling settings.
        factor = 1.8;
        validationCasesButton.Enable = "off";
        restoreButtons = onCleanup(@restoreBottomCoolingButtons); %#ok<NASGU>

        try
            statusLabel.Text = "Bottom-cooling validation — configuring 6P and scaled 2RC...";
            drawnow;
            configureRP1BahiraeiCase();
            % Table 3: 80 mm wide x 110 mm high x 9 mm thick. The previous
            % RP1 setup had width and height exchanged. At the same
            % areal contact resistance, Rth scales as 110/80 because the
            % bottom base changes from 110x9 to 80x9 mm2. This is an
            % assumption about the interface, not a measured Rth.
            diameterField.Value = 80.0;
            heightField.Value = 110.0;
            state.Length_mm = 80.0;
            state.Height_mm = 110.0;
            state.Prismatic.Length_mm = 80.0;
            state.Prismatic.Height_mm = 110.0;
            updateThermalAreaForActiveFormat();
            coolantRField.Value = 0.35*(110/80);
            saveActiveFormatGUIState("Prismatic");
            state.NeedsRebuild = true;
            state.R0Table_Ohm = factor * state.R0Table_Ohm;
            state.R1Table_Ohm = factor * state.R1Table_Ohm;
            state.R2Table_Ohm = factor * state.R2Table_Ohm;
            % C1=Tau1/R1 and C2=Tau2/R2 remain at source values.
            state.Tau1Table_s = factor * state.Tau1Table_s;
            state.Tau2Table_s = factor * state.Tau2Table_s;
            saveElectricalStateForFormat("Prismatic");

            if round(state.P) ~= 6 || abs(stopField.Value-1400) > 1e-9 || ...
                    state.CoolingPlateMode ~= "Bottom Cooling Plate" || ...
                    abs(state.MassFlowRate_kg_s-0.2706) > 1e-7 || ...
                    abs(thermalAreaField.Value-80*9e-6)>1e-9 || ...
                    abs(coolantRField.Value-0.48125)>1e-9 || ...
                    abs(state.Prismatic.Height_mm-110)>1e-9
                error("ThermalPack:RP1Cooled18xSetup", ...
                    "Expected paper geometry, 6P, 1400 s, 0.48125 K/W and 0.2706 kg/s water.");
            end

            statusLabel.Text = "Bottom-cooling validation — rebuilding battery...";
            drawnow;
            rebuildBattery([],[]);
            if state.NeedsRebuild
                error("ThermalPack:RP1Cooled18xRebuild", ...
                    "Battery rebuild did not complete successfully.");
            end

            % The standard runner reports errors in the GUI; reject missing
            % or incomplete results so a previous run is never compared.
            state.LastTrace = [];
            state.LastKPI = [];
            state.LastCoolantTrace = struct();
            statusLabel.Text = "Bottom-cooling validation — simulating 0-1400 s...";
            drawnow;
            runSimulation([],[]);
            if isempty(state.LastTrace) || isempty(state.LastKPI)
                error("ThermalPack:RP1Cooled18xSimulation", ...
                    "Simulation returned no valid battery results.");
            end
            tCell = double(state.LastTrace.tCell(:));
            if isempty(tCell) || abs(tCell(end)-1400) > 0.5
                error("ThermalPack:RP1Cooled18xIncomplete", ...
                    "Simulation did not reach 1400 seconds.");
            end

            showRP1BahiraeiComparison();
            statusLabel.Text = "Bottom-cooling validation complete";
        catch ME
            statusLabel.Text = "Bottom-cooling validation failed";
            uialert(fig,getReport(ME,"extended","hyperlinks","off"), ...
                "ThermalPack — Bottom-Cooling Validation Error");
        end

        function restoreBottomCoolingButtons()
            try validationCasesButton.Enable = "on"; catch, end
        end
    end

    function showRP1BahiraeiVoltageAudit(caseLabel)
        T = state.LastTrace;
        if ~isfield(T,"Vcell_V") || isempty(T.Vcell_V)
            message = "No cell terminal-voltage signal was resolved from the " + ...
                "generated module Simscape log. No voltage-validity result " + ...
                "can be reported for this run.";
            if isfield(T,"ElectricalLogStatus")
                message = message + newline + T.ElectricalLogStatus;
            end
            uialert(fig,message,"RP1 Voltage Audit Unavailable");
            return;
        end

        tV = double(T.tVoltage(:));
        voltage = double(T.Vcell_V);
        low_V = state.VoltageRange_V(1);
        high_V = state.VoltageRange_V(2);
        [minimum_V,whereMin] = min(voltage(:));
        [minTimeIndex,minCellIndex] = ind2sub(size(voltage),whereMin);
        maximum_V = max(voltage(:));
        anyOutside = any(voltage < low_V | voltage > high_V,2);
        outside_s = trapz(tV,double(anyOutside));
        minSOC = NaN;
        maxSOC = NaN;
        ocvTime_V = NaN(size(tV));
        if isfield(T,"SOCcell") && ~isempty(T.SOCcell)
            minSOC = min(T.SOCcell(:));
            maxSOC = max(T.SOCcell(:));
            socAtV = thermalPackInterpolateTrace( ...
                T.tSOC,T.SOCcell(:,1),tV);
            tempAtV_C = thermalPackInterpolateTrace( ...
                T.tCell,T.Tcell_C(:,1),tV);
            % Match the configured Nearest extrapolation when plotting the
            % estimated OCV; this is the model OCV, not a measured curve.
            socAtV = min(max(socAtV,min(state.OCVSOCBreakpoints)), ...
                max(state.OCVSOCBreakpoints));
            tempAtV_C = min(max(tempAtV_C,min(state.OCVTemperature_C)), ...
                max(state.OCVTemperature_C));
            ocvTime_V = interp2( ...
                state.OCVTemperature_C,state.OCVSOCBreakpoints, ...
                state.OCVTable_V,tempAtV_C,socAtV,"linear");
        end

        figCurrentTime_s = double(state.CustomCurrentProfile(:,1));
        figCellCurrent_A = double(state.CustomCurrentProfile(:,2))/6;
        currentTraceAvailable = isfield(T,"Icell_A") && ...
            ~isempty(T.Icell_A);
        currentRMSE_A = NaN;
        peakCellCurrent_A = max(abs(figCellCurrent_A));
        currentSourceText = "input";
        if currentTraceAvailable
            currentSourceText = "logged";
            tI = double(T.tCurrent(:));
            loggedCellCurrent_A = double(T.Icell_A(:,1));
            inputAtLogged_A = thermalPackInterpolateTrace( ...
                figCurrentTime_s,figCellCurrent_A,tI);
            validCurrent = isfinite(loggedCellCurrent_A) & ...
                isfinite(inputAtLogged_A);
            if any(validCurrent)
                currentRMSE_A = sqrt(mean(( ...
                    abs(loggedCellCurrent_A(validCurrent))- ...
                    abs(inputAtLogged_A(validCurrent))).^2));
            end
            peakCellCurrent_A = max(abs(loggedCellCurrent_A));
        end

        scr = get(groot,"ScreenSize");
        W = min(1550,max(1120,scr(3)-80));
        H = min(900,max(715,scr(4)-80));
        vf = uifigure("Name","ThermalPack — RP1 1.8x Voltage Audit — " + ...
            caseLabel,"Position",[scr(1)+max(15,(scr(3)-W)/2) ...
                            scr(2)+max(15,(scr(4)-H)/2) W H]);
        movegui(vf,"onscreen");
        vg = uigridlayout(vf,[3 2]);
        vg.RowHeight = {125,'1x','1x'};
        vg.ColumnWidth = {'1x','1x'};
        vg.Padding = [12 12 12 12];

        summary = uilabel(vg,"WordWrap","on","FontWeight","bold", ...
            "Text",thermalPackFormatText( ...
                ["RP1 1.8x | %s | actual Simscape cell terminal voltage | " ...
                 "5 Ah NCA | 6P | Fig. 8 module input 6x | " ...
                 "configured surrogate range %.2f-%.2f V\n" ...
                 "Lowest cell V %.3f V at %.1f s (cell %d); " ...
                 "highest V %.3f V; time with ANY cell outside range %.1f s.\n" ...
                 "Peak absolute %s cell current %.1f A; absolute-current " ...
                 "RMSE vs Fig. 8 per-cell input %s A; SOC %.3f to %.3f. " ...
                 "Model OCV is a surrogate; the paper supplies no terminal " ...
                 "voltage trace for comparison."], ...
                caseLabel,low_V,high_V,minimum_V,tV(minTimeIndex), ...
                minCellIndex,maximum_V,outside_s,currentSourceText, ...
                peakCellCurrent_A, ...
                rp1MetricText(currentRMSE_A),minSOC,maxSOC));
        summary.Layout.Row = 1; summary.Layout.Column = [1 2];

        ax1 = uiaxes(vg); ax1.Layout.Row = 2; ax1.Layout.Column = 1;
        hold(ax1,"on");
        plot(ax1,tV,min(voltage,[],2),"LineWidth",1.3, ...
            "DisplayName","Lowest cell terminal voltage");
        plot(ax1,tV,max(voltage,[],2),"LineWidth",1.1, ...
            "DisplayName","Highest cell terminal voltage");
        if any(isfinite(ocvTime_V))
            plot(ax1,tV,ocvTime_V,"k--","LineWidth",1, ...
                "DisplayName","Configured OCV (cell 1, estimated)");
        end
        yline(ax1,low_V,"r--","Configured lower limit");
        yline(ax1,high_V,"r--","Configured upper limit");
        hold(ax1,"off"); grid(ax1,"on"); xlim(ax1,[0 1400]);
        xlabel(ax1,"Time (s)"); ylabel(ax1,"Terminal voltage (V)");
        title(ax1,"Logged Voltage and Configured Bounds");
        legend(ax1,"Location","best");

        ax2 = uiaxes(vg); ax2.Layout.Row = 2; ax2.Layout.Column = 2;
        hold(ax2,"on");
        plot(ax2,figCurrentTime_s,abs(figCellCurrent_A), ...
            "LineWidth",1.0,"DisplayName","Absolute Fig. 8 cell input");
        if currentTraceAvailable
            plot(ax2,tI,abs(loggedCellCurrent_A),"LineWidth",1.0, ...
                "DisplayName","Absolute logged cell 1 current");
        end
        hold(ax2,"off"); grid(ax2,"on"); xlim(ax2,[0 1400]);
        xlabel(ax2,"Time (s)"); ylabel(ax2,"Absolute cell current (A)");
        if currentTraceAvailable
            title(ax2,"Check 6P Input Reaches Each Cell");
        else
            title(ax2,"Cell Current Log Unavailable: Input Only");
        end
        legend(ax2,"Location","best");

        ax3 = uiaxes(vg); ax3.Layout.Row = 3; ax3.Layout.Column = 1;
        if isfield(T,"SOCcell") && ~isempty(T.SOCcell)
            plot(ax3,T.tSOC,T.SOCcell,"LineWidth",1);
            ylabel(ax3,"Cell SOC (-)");
            title(ax3,"Logged State of Charge (All Cells)");
        else
            plot(ax3,T.tCell,T.TmeanCellAverage_C,"LineWidth",1);
            ylabel(ax3,"Battery-average temperature (°C)");
            title(ax3,"SOC Log Unavailable: Battery Temperature Shown");
        end
        xlim(ax3,[0 1400]); xlabel(ax3,"Time (s)"); grid(ax3,"on");

        ax4 = uiaxes(vg); ax4.Layout.Row = 3; ax4.Layout.Column = 2;
        if currentTraceAvailable
            iAtV = thermalPackInterpolateTrace(tI,loggedCellCurrent_A,tV);
            scatter(ax4,iAtV,voltage(:,1),5,"filled");
            xlabel(ax4,"Logged cell 1 current (A; model sign)");
        else
            iAtV = thermalPackInterpolateTrace( ...
                figCurrentTime_s,figCellCurrent_A,tV);
            scatter(ax4,iAtV,voltage(:,1),5,"filled");
            xlabel(ax4,"Fig. 8 input per cell (A)");
        end
        ylabel(ax4,"Logged cell 1 terminal voltage (V)");
        title(ax4,"Voltage vs Cell Current: Both Charge Directions");
        grid(ax4,"on");
    end





    function configureRP1BahiraeiCase()
        %% CELL / MODULE — Bahiraei Table 3 width, height and thickness.
        formatField.Value = "Prismatic";
        cellFormatChanged([],[]);

        topologyField.Value = "SingleStack";
        parallelField.Value = 6;
        rowsField.Value = 1;
        rowsField.Enable = "off";
        parallelStackingAxisField.Value = "Y";
        seriesField.Value = 1;
        moduleStackingAxisField.Value = "X";
        massFactorField.Value = 1.0;
        cellGapField.Value = 1.0;
        assemblyGapField.Value = 1.0;

        % The model's Length field corresponds to Table 3 cell width.
        diameterField.Value = 80.0;
        thicknessField.Value = 9.0;
        heightField.Value = 110.0;

        % Thermal-mass estimate based on Bahiraei Table 2.
        % Treat cathode/anode densities as solid-phase densities and fill
        % their reported 0.423/0.56 pore fractions with Table 2 electrolyte.
        % This is an explicit assumption, not measured mass/heat capacity.
        % Layer order: Al CC, cathode, electrolyte separator, anode, Cu CC.
        % Keep the previously selected 64.13 W/(m*K) conductivity unchanged.
        rp1LayerThickness_um = [23 46 26 48 16];
        rp1Density_kg_m3     = [2700 4740 1210 5031 8960];
        rp1Cp_J_kgK          = [900 1250 1518 1437 385];
        rp1Porosity          = [0 0.423 0 0.56 0];
        rp1LayerThickness_m  = rp1LayerThickness_um * 1e-6;
        rp1StackThickness_m  = sum(rp1LayerThickness_m);
        rp1ElectrolyteDensity_kg_m3 = rp1Density_kg_m3(3);
        rp1ElectrolyteCp_J_kgK = rp1Cp_J_kgK(3);
        rp1LayerDensity_kg_m3 = (1-rp1Porosity).*rp1Density_kg_m3 + ...
            rp1Porosity*rp1ElectrolyteDensity_kg_m3;
        rp1LayerRhoCp_J_m3K = (1-rp1Porosity).*rp1Density_kg_m3.* ...
            rp1Cp_J_kgK + rp1Porosity*rp1ElectrolyteDensity_kg_m3* ...
            rp1ElectrolyteCp_J_kgK;
        rp1RhoEff_kg_m3 = sum(rp1LayerThickness_m .* rp1LayerDensity_kg_m3) / ...
            rp1StackThickness_m;
        rp1RhoCpEff_J_m3K = sum(rp1LayerThickness_m .* ...
            rp1LayerRhoCp_J_m3K) / rp1StackThickness_m;
        rp1CellVolume_m3 = (80e-3) * (110e-3) * (9e-3);
        rp1CellMass_kg = rp1RhoEff_kg_m3 * rp1CellVolume_m3;
        rp1ThermalMass_J_K = rp1RhoCpEff_J_m3K * rp1CellVolume_m3;
        % Under the pore-filling assumption: mass ~= 0.26154 kg/cell,
        % thermal mass ~= 275.91 J/K/cell (formerly 387.74 J/K).

        massField.Value = rp1CellMass_kg;
        capacityField.Value = 5.0;
        energyField.Value = 18.5;

        state.CellFormat = "Prismatic";
        state.P = 6;
        state.S = 1;
        state.TotalCells = 6;
        state.Topology = "SingleStack";
        state.Rows = 1;
        state.ParallelAssemblyStackingAxis = "Y";
        state.ModuleStackingAxis = "X";
        state.MassFactor = 1.0;
        state.InterCellGap_mm = 1.0;
        state.InterAssemblyGap_mm = 1.0;
        state.Length_mm = 80.0;
        state.Thickness_mm = 9.0;
        state.Height_mm = 110.0;

        state.Prismatic.P = 6;
        state.Prismatic.S = 1;
        state.Prismatic.Length_mm = 80.0;
        state.Prismatic.Thickness_mm = 9.0;
        state.Prismatic.Height_mm = 110.0;
        state.Prismatic.Mass_kg = rp1CellMass_kg;
        state.Prismatic.Capacity_Ah = 5.0;
        state.Prismatic.Energy_Wh = 18.5;
        state.Prismatic.Topology = "SingleStack";
        state.Prismatic.Rows = 1;
        state.Prismatic.StackingAxis = "Y";

        %% INITIAL / THERMAL
        socField.Value = 0.70;
        initialCellTempField.Value = 20.0;
        thermalLimitField.Value = 60.0;
        nodesField.Value = 6;
        thermalMassField.Value = rp1ThermalMass_J_K;

        % Point 2 — effective height/in-plane conductivity derived from the
        % constituent k and layer-thickness data used in the paper.
        conductivityField.Value = 64.13;

        state.InitialCellTemperature_C = 20.0;
        state.ThermalLimit_C = 60.0;
        state.Prismatic.ThermalMass_J_K = rp1ThermalMass_J_K;
        state.Prismatic.ConductivityZ_W_mK = 64.13;
        state.Prismatic.ThermalAreaMode = "Automatic";
        updateThermalAreaForActiveFormat();

        %% ELECTRICAL MODEL — RP1 lookup data
        socGrid = [0 0.1 0.25 0.5 0.75 0.9 1.0];
        tempGrid_C = [4.85 19.85 39.85];

        ocv_V = [ ...
            3.480 3.500 3.515; ...
            3.550 3.565 3.575; ...
            3.620 3.630 3.640; ...
            3.710 3.715 3.725; ...
            3.905 3.920 3.930; ...
            4.065 4.075 4.080; ...
            4.190 4.190 4.195];

        % The unidentified RP1 5 Ah cell has no published full-cell ECM.
        % Castro/Ocon's 4 Ah NCA 2RC layer model is used as a surrogate.
        % Convert 40 parallel layers to one cell (R/40, C*40), then scale
        % 4 Ah -> 5 Ah (R*4/5, C*5/4). Per-layer source values:
        % R0=859.67 mOhm; R1=63.89 mOhm, C1=60.96 F;
        % R2=25.33 mOhm, C2=974.51 F.
        % This constant 2RC set is an estimate at the source operating point,
        % not a measured SOC/temperature map for the RP1 5 Ah cell.
        rp1R0_Ohm = 0.0171934;
        rp1R1_Ohm = 0.0012778;
        rp1C1_F = 3048.0;
        rp1R2_Ohm = 0.0005066;
        rp1C2_F = 48725.5;
        rp1Tau1_s = rp1R1_Ohm * rp1C1_F;
        rp1Tau2_s = rp1R2_Ohm * rp1C2_F;
        r0_Ohm = rp1R0_Ohm * ...
            ones(numel(socGrid),numel(tempGrid_C));
        r1_Ohm = rp1R1_Ohm * ones(size(r0_Ohm));
        tau1_s = rp1Tau1_s * ones(size(r0_Ohm));
        r2_Ohm = rp1R2_Ohm * ones(size(r0_Ohm));
        tau2_s = rp1Tau2_s * ones(size(r0_Ohm));

        state.ExtrapolationMethod = "Nearest";
        state.VoltageRange_V = [2.5 4.2];
        state.OCVSOCBreakpoints = socGrid;
        state.OCVTemperature_C = tempGrid_C;
        state.OCVTable_V = ocv_V;
        state.ResistanceSOCBreakpoints = socGrid;
        state.ResistanceTemperature_C = tempGrid_C;
        state.R0Table_Ohm = r0_Ohm;
        state.PolarizationModel = "RC1 + RC2";
        state.R1Table_Ohm = r1_Ohm;
        state.Tau1Table_s = tau1_s;
        state.R2Table_Ohm = r2_Ohm;
        state.Tau2Table_s = tau2_s;

        % Point 4 — include reversible/entropic heating. The coefficient
        % table is the existing RP1 ThermalPack table; the paper's Fig. 2(b)
        % is graphical and does not tabulate exact cell-level values.
        state.EntropicHeatEnabled = true;
        state.EntropicCoefficient_mV_K = ...
            [0.10 0.05 -0.10 -0.25 -0.10 -0.20 -0.30];

        state.R0Deviation_pct = zeros(1,6);
        state.ThermalMassDeviation_pct = zeros(1,6);
        state.ThermalConductivityDeviation_pct = zeros(1,6);
        saveElectricalStateForFormat("Prismatic");

        %% FUDC LOAD PROFILE — Bahiraei Fig. 8, 0.1 s digitization
        % Existing current extraction from a 1200-dpi rendering of Fig. 8.
        % The embedded paper image is only 1001 pixels wide (~1.7 s per
        % horizontal plot pixel); 0.1-s samples are interpolated, not
        % independent high-resolution measurements. The same input is kept
        % here as in the x1.8 no-cooling resistance sweep.
        % Fig. 8 is treated as the per-cell current. The 6P module-terminal
        % input is therefore 6x this trace so each cell receives Fig. 8 current.
        rp1Time_s = (0:0.1:1400)';
        rp1CellCurrent_A = [ ...
            0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 ...
            0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 ...
            0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 ...
            0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.159 0.255 0.350 0.446 0.542 0.638 ...
            0.733 0.829 0.925 1.021 1.116 1.212 1.308 1.403 1.499 1.595 1.691 1.786 1.882 1.978 2.074 2.169 ...
            2.265 2.361 2.457 2.552 2.648 2.744 2.839 2.935 3.031 3.127 3.222 3.318 3.414 3.510 3.605 3.701 ...
            3.797 3.892 3.988 4.084 4.180 4.275 4.371 4.467 4.563 4.658 4.754 4.850 4.945 5.041 5.137 5.233 ...
            5.328 5.424 5.520 5.616 5.711 5.807 5.903 5.998 6.094 6.190 6.286 6.381 6.477 6.573 6.669 6.764 ...
            6.860 6.956 7.039 7.039 7.039 7.039 7.039 7.039 7.039 7.039 7.039 7.039 7.039 7.039 7.039 7.039 ...
            7.039 7.039 7.039 7.039 7.039 7.039 7.039 7.039 7.039 7.039 7.039 7.039 7.039 7.039 7.039 7.039 ...
            8.023 11.021 14.019 17.017 19.803 19.803 19.803 19.803 19.803 19.803 19.803 19.803 19.803 19.803 19.803 19.803 ...
            19.803 20.261 21.802 23.344 24.886 26.368 26.368 26.368 26.368 26.368 26.368 26.368 26.368 26.368 26.368 26.368 ...
            26.368 26.368 26.936 29.077 31.218 33.359 35.485 35.485 35.485 35.485 35.485 35.485 35.485 35.485 35.485 35.485 ...
            35.485 35.485 35.485 35.885 37.598 39.311 41.024 42.737 42.779 42.779 42.779 42.779 42.779 42.779 42.779 42.779 ...
            42.779 42.779 42.779 42.779 43.281 45.765 48.248 50.732 53.216 53.355 53.355 53.355 53.355 53.355 53.355 53.355 ...
            53.355 53.355 53.355 53.355 53.355 53.545 54.658 55.772 56.885 57.999 58.096 58.096 58.096 58.096 58.096 58.096 ...
            58.096 58.096 58.096 58.096 58.096 58.096 58.209 59.023 59.837 60.650 61.464 61.561 61.561 61.561 61.561 61.561 ...
            61.561 61.561 61.561 61.561 61.561 61.561 61.561 61.488 60.802 60.117 59.432 58.747 58.643 58.643 58.643 58.643 ...
            58.643 58.643 58.643 58.643 58.643 58.643 58.643 58.643 58.411 55.327 52.244 49.160 46.077 45.514 45.514 45.514 ...
            45.514 45.514 45.514 45.514 45.514 45.514 45.514 45.514 45.514 45.299 40.374 35.449 30.524 25.599 24.544 24.544 ...
            24.544 24.544 24.544 24.544 24.544 24.544 24.544 24.544 24.544 24.544 24.495 20.470 16.444 12.418 8.393 7.403 ...
            7.403 7.403 7.403 7.403 7.403 7.403 7.403 7.403 7.403 7.403 7.403 7.403 7.277 7.149 7.020 6.892 ...
            6.856 6.856 6.856 6.856 6.856 6.856 6.856 6.856 6.856 6.856 6.856 6.856 6.856 8.482 10.195 11.908 ...
            13.621 14.150 14.150 14.150 14.150 14.150 14.150 14.150 14.150 14.150 14.150 14.150 14.150 14.150 16.193 18.420 ...
            20.647 22.874 23.632 23.632 23.632 23.632 23.632 23.632 23.632 23.632 23.632 23.632 23.632 23.632 23.632 24.960 ...
            26.459 27.958 29.457 30.015 30.015 30.015 30.015 30.015 30.015 30.015 30.015 30.015 30.015 30.015 30.015 30.015 ...
            32.465 35.334 38.204 41.073 42.232 42.232 42.232 42.232 42.232 42.232 42.232 42.232 42.232 42.232 42.232 42.232 ...
            42.232 42.760 43.403 44.045 44.687 44.967 44.967 44.967 44.967 44.967 44.967 44.967 44.967 44.967 44.967 44.967 ...
            44.967 44.967 44.425 43.740 43.055 42.370 42.050 42.050 42.050 42.050 42.050 42.050 42.050 42.050 42.050 42.050 ...
            42.050 42.050 42.050 35.222 26.229 17.236 8.242 3.756 3.756 3.756 3.756 3.756 3.756 3.756 3.756 3.756 ...
            3.756 3.756 3.756 3.756 3.289 2.647 2.004 1.362 1.021 1.021 1.021 1.021 1.021 1.021 1.021 1.021 ...
            1.021 1.021 1.021 1.021 1.021 -3.836 -10.817 -17.798 -24.778 -28.702 -28.702 -28.702 -28.702 -28.702 -28.702 -28.702 ...
            -28.702 -28.702 -28.702 -28.702 -28.702 -28.702 -24.207 -17.441 -10.674 -3.908 0.109 0.109 0.109 0.109 0.109 0.109 ...
            0.109 0.109 0.109 0.109 0.109 0.109 0.109 1.843 4.584 7.325 10.066 11.780 11.780 11.780 11.780 11.780 ...
            11.780 11.780 11.780 11.780 11.780 11.780 11.780 11.780 14.482 18.979 23.476 27.972 30.926 30.926 30.926 30.926 ...
            30.926 30.926 30.926 30.926 30.926 30.926 30.926 30.926 30.926 32.048 34.018 35.988 37.958 39.314 39.314 39.314 ...
            39.314 39.314 39.314 39.314 39.314 39.314 39.314 39.314 39.314 39.314 38.508 37.009 35.511 34.012 32.932 32.932 ...
            32.932 32.932 32.932 32.932 32.932 32.932 32.932 32.932 32.932 32.932 32.932 31.718 29.320 26.922 24.524 22.721 ...
            22.721 22.721 22.721 22.721 22.721 22.721 22.721 22.721 22.721 22.721 22.721 22.721 21.380 18.553 15.727 12.900 ...
            10.686 10.686 10.686 10.686 10.686 10.686 10.686 10.686 10.686 10.686 10.686 10.686 10.686 10.382 9.697 9.012 ...
            8.327 7.768 7.768 7.768 7.768 7.768 7.768 7.768 7.768 7.768 7.768 7.768 7.768 7.768 7.927 8.312 ...
            8.697 9.083 9.409 9.409 9.409 9.409 9.409 9.409 9.409 9.409 9.409 9.409 9.409 9.409 9.409 10.141 ...
            12.068 13.995 15.922 17.615 17.615 17.615 17.615 17.615 17.615 17.615 17.615 17.615 17.615 17.615 17.615 17.615 ...
            17.853 18.539 19.224 19.909 20.532 20.532 20.532 20.532 20.532 20.532 20.532 20.532 20.532 20.532 20.532 20.532 ...
            20.532 19.625 16.756 13.886 11.017 8.315 8.315 8.315 8.315 8.315 8.315 8.315 8.315 8.315 8.315 8.315 ...
            8.315 8.315 8.059 7.160 6.260 5.361 4.486 4.486 4.486 4.486 4.486 4.486 4.486 4.486 4.486 4.486 ...
            4.486 4.486 4.486 5.071 7.384 9.696 12.009 14.321 14.333 14.333 14.333 14.333 14.333 14.333 14.333 14.333 ...
            14.333 14.333 14.333 14.333 14.996 17.994 20.992 23.990 26.988 27.097 27.097 27.097 27.097 27.097 27.097 27.097 ...
            27.097 27.097 27.097 27.097 27.097 27.503 29.645 31.786 33.927 36.069 36.214 36.214 36.214 36.214 36.214 36.214 ...
            36.214 36.214 36.214 36.214 36.214 36.214 36.370 37.355 38.340 39.325 40.310 40.408 40.408 40.408 40.408 40.408 ...
            40.408 40.408 40.408 40.408 40.408 40.408 40.408 40.143 38.044 35.946 33.848 31.749 31.473 31.473 31.473 31.473 ...
            31.473 31.473 31.473 31.473 31.473 31.473 31.473 31.473 31.323 29.738 28.154 26.569 24.985 24.726 24.726 24.726 ...
            24.726 24.726 24.726 24.726 24.726 24.726 24.726 24.726 24.726 24.621 22.951 21.280 19.610 17.940 17.615 17.615 ...
            17.615 17.615 17.615 17.615 17.615 17.615 17.615 17.615 17.615 17.615 17.574 16.289 15.005 13.720 12.435 12.144 ...
            12.144 12.144 12.144 12.144 12.144 12.144 12.144 12.144 12.144 12.144 12.144 12.144 11.245 10.346 9.446 8.547 ...
            8.315 8.315 8.315 8.315 8.315 8.315 8.315 8.315 8.315 8.315 8.315 8.315 8.315 5.537 2.667 -0.202 ...
            -3.071 -3.902 -3.902 -3.902 -3.902 -3.902 -3.902 -3.902 -3.902 -3.902 -3.902 -3.902 -3.902 -3.902 -4.785 -5.727 ...
            -6.669 -7.611 -7.914 -7.914 -7.914 -7.914 -7.914 -7.914 -7.914 -7.914 -7.914 -7.914 -7.914 -7.914 -7.914 -8.457 ...
            -9.056 -9.656 -10.255 -10.467 -10.467 -10.467 -10.467 -10.467 -10.467 -10.467 -10.467 -10.467 -10.467 -10.467 -10.467 -10.467 ...
            -7.250 -3.567 0.116 3.799 5.215 5.215 5.215 5.215 5.215 5.215 5.215 5.215 5.215 5.215 5.215 5.215 ...
            5.215 5.215 5.215 5.215 5.215 5.215 5.215 5.215 5.215 5.215 5.215 5.215 5.215 5.215 5.215 5.215 ...
            5.215 5.215 8.373 12.270 16.167 20.064 21.809 21.809 21.809 21.809 21.809 21.809 21.809 21.809 21.809 21.809 ...
            21.809 21.809 21.809 23.509 25.694 27.878 30.062 31.109 31.109 31.109 31.109 31.109 31.109 31.109 31.109 31.109 ...
            31.109 31.109 31.109 31.109 31.096 31.079 31.062 31.044 31.027 31.010 30.993 30.976 30.959 30.942 30.925 30.907 ...
            30.890 30.873 30.856 30.839 30.822 30.805 30.788 30.770 30.753 30.744 30.744 30.744 30.744 30.744 30.744 30.744 ...
            30.744 30.744 30.744 30.744 30.744 30.744 30.674 30.571 30.468 30.365 30.263 30.160 30.057 29.954 29.851 29.749 ...
            29.646 29.543 29.440 29.338 29.235 29.132 29.029 28.926 28.824 28.721 28.618 28.556 28.556 28.556 28.556 28.556 ...
            28.556 28.556 28.556 28.556 28.556 28.556 28.556 28.556 24.464 17.869 11.274 4.678 0.474 0.474 0.474 0.474 ...
            0.474 0.474 0.474 0.474 0.474 0.474 0.474 0.474 0.474 -0.434 -1.975 -3.517 -5.059 -6.090 -6.090 -6.090 ...
            -6.090 -6.090 -6.090 -6.090 -6.090 -6.090 -6.090 -6.090 -6.090 -6.090 -11.173 -20.295 -29.417 -38.539 -44.931 -44.931 ...
            -44.931 -44.931 -44.931 -44.931 -44.931 -44.931 -44.931 -44.931 -44.931 -44.931 -44.931 -46.079 -48.263 -50.447 -52.631 -54.230 ...
            -54.230 -54.230 -54.230 -54.230 -54.230 -54.230 -54.230 -54.230 -54.230 -54.230 -54.230 -54.230 -54.844 -56.086 -57.328 -58.570 ...
            -59.519 -59.519 -59.519 -59.519 -59.519 -59.519 -59.519 -59.519 -59.519 -59.519 -59.519 -59.519 -59.519 -58.925 -57.640 -56.355 ...
            -55.070 -54.048 -54.048 -54.048 -54.048 -54.048 -54.048 -54.048 -54.048 -54.048 -54.048 -54.048 -54.048 -54.048 -53.495 -52.210 ...
            -50.925 -49.641 -48.578 -48.578 -48.578 -48.578 -48.578 -48.578 -48.578 -48.578 -48.578 -48.578 -48.578 -48.578 -48.578 -47.587 ...
            -45.103 -42.619 -40.135 -38.001 -38.001 -38.001 -38.001 -38.001 -38.001 -38.001 -38.001 -38.001 -38.001 -38.001 -38.001 -38.001 ...
            -37.514 -36.186 -34.858 -33.531 -32.349 -32.349 -32.349 -32.349 -32.349 -32.349 -32.349 -32.349 -32.349 -32.349 -32.349 -32.349 ...
            -32.349 -31.817 -30.232 -28.647 -27.063 -25.602 -25.602 -25.602 -25.602 -25.602 -25.602 -25.602 -25.602 -25.602 -25.602 -25.602 ...
            -25.602 -25.602 -24.755 -21.971 -19.188 -16.404 -13.749 -13.749 -13.749 -13.749 -13.749 -13.749 -13.749 -13.749 -13.749 -13.749 ...
            -13.749 -13.749 -13.749 -13.282 -11.569 -9.856 -8.143 -6.455 -6.455 -6.455 -6.455 -6.455 -6.455 -6.455 -6.455 -6.455 ...
            -6.455 -6.455 -6.455 -6.455 -6.300 -5.658 -5.016 -4.373 -3.731 -3.720 -3.720 -3.720 -3.720 -3.720 -3.720 -3.720 ...
            -3.720 -3.720 -3.720 -3.720 -3.720 -3.541 -2.684 -1.828 -0.971 -0.115 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 ...
            -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 ...
            -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 ...
            -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 ...
            -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 ...
            -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 ...
            -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.072 -0.029 0.014 0.056 0.099 ...
            0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.067 0.024 -0.019 ...
            -0.061 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.114 -0.157 ...
            -0.200 -0.242 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.251 ...
            -0.246 -0.241 -0.236 -0.230 -0.225 -0.220 -0.215 -0.210 -0.205 -0.200 -0.195 -0.190 -0.185 -0.180 -0.175 -0.170 ...
            -0.165 -0.160 -0.155 -0.150 -0.145 -0.140 -0.135 -0.130 -0.125 -0.120 -0.115 -0.110 -0.105 -0.099 -0.094 -0.089 ...
            -0.084 -0.079 -0.074 -0.069 -0.064 -0.059 -0.054 -0.049 -0.044 -0.039 -0.034 -0.029 -0.024 -0.019 -0.014 -0.009 ...
            -0.004 0.001 0.006 0.011 0.016 0.021 0.026 0.032 0.037 0.042 0.047 0.052 0.057 0.062 0.067 0.072 ...
            0.077 0.082 0.087 0.092 0.097 0.102 0.107 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 ...
            0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 ...
            0.109 0.109 0.109 0.109 0.109 0.481 0.986 1.491 1.997 2.502 3.007 3.513 4.018 4.523 5.029 5.534 ...
            6.040 6.545 7.050 7.556 8.061 8.566 9.072 9.577 10.082 10.588 10.868 10.868 10.868 10.868 10.868 10.868 ...
            10.868 10.868 10.868 10.868 10.868 10.868 10.868 15.556 22.536 29.517 36.498 40.591 40.591 40.591 40.591 40.591 ...
            40.591 40.591 40.591 40.591 40.591 40.591 40.591 40.591 39.659 38.203 36.747 35.291 34.391 34.391 34.391 34.391 ...
            34.391 34.391 34.391 34.391 34.391 34.391 34.391 34.391 34.391 24.909 9.320 -6.268 -21.857 -31.984 -31.984 -31.984 ...
            -31.984 -31.984 -31.984 -31.984 -31.984 -31.984 -31.984 -31.984 -31.984 -31.984 -35.268 -40.964 -46.660 -52.356 -56.236 -56.236 ...
            -56.236 -56.236 -56.236 -56.236 -56.236 -56.236 -56.236 -56.236 -56.236 -56.236 -56.236 -49.514 -37.180 -24.847 -12.513 -3.720 ...
            -3.720 -3.720 -3.720 -3.720 -3.720 -3.720 -3.720 -3.720 -3.720 -3.720 -3.720 -3.720 0.216 7.881 15.547 23.213 ...
            28.920 28.920 28.920 28.920 28.920 28.920 28.920 28.920 28.920 28.920 28.920 28.920 28.920 30.880 34.949 39.017 ...
            43.086 46.244 46.244 46.244 46.244 46.244 46.244 46.244 46.244 46.244 46.244 46.244 46.244 46.244 41.617 31.339 ...
            21.061 10.783 2.480 2.480 2.480 2.480 2.480 2.480 2.480 2.480 2.480 2.480 2.480 2.480 2.480 1.691 ...
            -0.193 -2.077 -3.962 -5.543 -5.543 -5.543 -5.543 -5.543 -5.543 -5.543 -5.543 -5.543 -5.543 -5.543 -5.543 -5.543 ...
            -5.543 -5.543 -5.543 -5.543 -5.543 -5.543 -5.543 -5.543 -5.543 -5.543 -5.543 -5.543 -5.543 -5.543 -5.543 -5.543 ...
            -5.543 -5.333 -4.742 -4.151 -3.560 -2.969 -2.378 -1.787 -1.196 -0.605 -0.014 0.577 1.168 1.759 2.350 2.941 ...
            3.531 4.122 4.713 5.304 5.895 6.486 7.039 7.039 7.039 7.039 7.039 7.039 7.039 7.039 7.039 7.039 ...
            7.039 7.039 7.039 8.977 15.615 22.253 28.891 35.303 35.303 35.303 35.303 35.303 35.303 35.303 35.303 35.303 ...
            35.303 35.303 35.303 35.303 35.526 36.382 37.239 38.095 38.950 38.950 38.950 38.950 38.950 38.950 38.950 38.950 ...
            38.950 38.950 38.950 38.950 38.950 37.529 31.320 25.110 18.900 12.690 12.509 12.509 12.509 12.509 12.509 12.509 ...
            12.509 12.509 12.509 12.509 12.509 12.509 11.901 8.818 5.735 2.651 -0.432 -0.620 -0.620 -0.620 -0.620 -0.620 ...
            -0.620 -0.620 -0.620 -0.620 -0.620 -0.620 -0.620 -1.959 -10.053 -18.147 -26.241 -34.336 -35.084 -35.084 -35.084 -35.084 ...
            -35.084 -35.084 -35.084 -35.084 -35.084 -35.084 -35.084 -35.084 -35.617 -39.600 -43.582 -47.565 -51.548 -52.042 -52.042 -52.042 ...
            -52.042 -52.042 -52.042 -52.042 -52.042 -52.042 -52.042 -52.042 -52.042 -52.419 -56.102 -59.785 -63.468 -67.151 -67.724 -67.724 ...
            -67.724 -67.724 -67.724 -67.724 -67.724 -67.724 -67.724 -67.724 -67.724 -67.724 -67.797 -68.825 -69.852 -70.880 -71.908 -72.101 ...
            -72.101 -72.101 -72.101 -72.101 -72.101 -72.101 -72.101 -72.101 -72.101 -72.101 -72.101 -71.891 -66.495 -61.098 -55.702 -50.306 ...
            -49.125 -49.125 -49.125 -49.125 -49.125 -49.125 -49.125 -49.125 -49.125 -49.125 -49.125 -49.125 -49.003 -32.301 -15.599 1.103 ...
            17.806 21.991 21.991 21.991 21.991 21.991 21.991 21.991 21.991 21.991 21.991 21.991 21.991 21.991 27.005 32.144 ...
            37.284 42.423 43.873 43.873 43.873 43.873 43.873 43.873 43.873 43.873 43.873 43.873 43.873 43.873 43.873 52.687 ...
            62.023 71.359 80.695 83.625 83.625 83.625 83.625 83.625 83.625 83.625 83.625 83.625 83.625 83.625 83.625 83.625 ...
            83.430 83.216 83.001 82.787 82.713 82.713 82.713 82.713 82.713 82.713 82.713 82.713 82.713 82.713 82.713 82.713 ...
            82.713 79.017 74.820 70.623 66.426 64.843 64.843 64.843 64.843 64.843 64.843 64.843 64.843 64.843 64.843 64.843 ...
            64.843 64.843 58.734 51.539 44.344 37.150 34.209 34.209 34.209 34.209 34.209 34.209 34.209 34.209 34.209 34.209 ...
            34.209 34.209 34.209 23.810 11.091 -1.628 -14.348 -19.949 -19.949 -19.949 -19.949 -19.949 -19.949 -19.949 -19.949 -19.949 ...
            -19.949 -19.949 -19.949 -19.949 -22.810 -26.450 -30.090 -33.730 -35.449 -35.449 -35.449 -35.449 -35.449 -35.449 -35.449 -35.449 ...
            -35.449 -35.449 -35.449 -35.449 -35.449 -38.000 -41.384 -44.767 -48.150 -49.854 -49.854 -49.854 -49.854 -49.854 -49.854 -49.854 ...
            -49.854 -49.854 -49.854 -49.854 -49.854 -49.854 -48.926 -47.641 -46.356 -45.071 -44.384 -44.384 -44.384 -44.384 -44.384 -44.384 ...
            -44.384 -44.384 -44.384 -44.384 -44.384 -44.384 -44.384 -41.898 -38.301 -34.703 -31.106 -29.066 -29.066 -29.066 -29.066 -29.066 ...
            -29.066 -29.066 -29.066 -29.066 -29.066 -29.066 -29.066 -29.066 -23.701 -15.564 -7.427 0.710 5.580 5.580 5.580 5.580 ...
            5.580 5.580 5.580 5.580 5.580 5.580 5.580 5.580 5.580 5.526 5.440 5.355 5.269 5.215 5.215 5.215 ...
            5.215 5.215 5.215 5.215 5.215 5.215 5.215 5.215 5.215 5.215 1.667 -4.286 -10.239 -16.192 -20.131 -20.131 ...
            -20.131 -20.131 -20.131 -20.131 -20.131 -20.131 -20.131 -20.131 -20.131 -20.131 -20.131 -20.180 -20.265 -20.351 -20.437 -20.496 ...
            -20.496 -20.496 -20.496 -20.496 -20.496 -20.496 -20.496 -20.496 -20.496 -20.496 -20.496 -20.496 -22.846 -27.257 -31.669 -36.080 ...
            -39.278 -39.278 -39.278 -39.278 -39.278 -39.278 -39.278 -39.278 -39.278 -39.278 -39.278 -39.278 -39.278 -40.072 -41.657 -43.241 ...
            -44.826 -46.025 -46.025 -46.025 -46.025 -46.025 -46.025 -46.025 -46.025 -46.025 -46.025 -46.025 -46.025 -46.025 -44.798 -42.186 ...
            -39.573 -36.961 -34.902 -34.902 -34.902 -34.902 -34.902 -34.902 -34.902 -34.902 -34.902 -34.902 -34.902 -34.902 -34.902 -27.831 ...
            -11.685 4.460 20.606 33.844 33.844 33.844 33.844 33.844 33.844 33.844 33.844 33.844 33.844 33.844 33.844 33.844 ...
            36.054 41.493 46.932 52.371 57.002 57.002 57.002 57.002 57.002 57.002 57.002 57.002 57.002 57.002 57.002 57.002 ...
            57.002 58.559 62.713 66.867 71.021 74.690 74.690 74.690 74.690 74.690 74.690 74.690 74.690 74.690 74.690 74.690 ...
            74.690 74.690 73.588 70.376 67.164 63.952 61.014 61.014 61.014 61.014 61.014 61.014 61.014 61.014 61.014 61.014 ...
            61.014 61.014 61.014 59.213 53.432 47.650 41.869 36.397 36.397 36.397 36.397 36.397 36.397 36.397 36.397 36.397 ...
            36.397 36.397 36.397 36.397 36.169 35.355 34.542 33.728 32.932 32.932 32.932 32.932 32.932 32.932 32.932 32.932 ...
            32.932 32.932 32.932 32.932 32.932 33.729 36.941 40.153 43.365 46.577 46.608 46.608 46.608 46.608 46.608 46.608 ...
            46.608 46.608 46.608 46.608 46.608 46.608 46.961 48.588 50.215 51.843 53.470 53.538 53.538 53.538 53.538 53.538 ...
            53.538 53.538 53.538 53.538 53.538 53.538 53.538 53.387 52.573 51.760 50.946 50.132 50.073 50.073 50.073 50.073 ...
            50.073 50.073 50.073 50.073 50.073 50.073 50.073 50.073 49.449 45.381 41.312 37.244 33.175 32.750 32.750 32.750 ...
            32.750 32.750 32.750 32.750 32.750 32.750 32.750 32.750 32.750 31.916 25.064 18.212 11.360 4.508 3.574 3.574 ...
            3.574 3.574 3.574 3.574 3.574 3.574 3.574 3.574 3.574 3.574 3.293 0.166 -2.960 -6.086 -9.213 -9.737 ...
            -9.737 -9.737 -9.737 -9.737 -9.737 -9.737 -9.737 -9.737 -9.737 -9.737 -9.737 -10.078 -15.902 -21.726 -27.550 -33.375 ...
            -34.537 -34.537 -34.537 -34.537 -34.537 -34.537 -34.537 -34.537 -34.537 -34.537 -34.537 -34.537 -34.604 -37.131 -39.658 -42.185 ...
            -44.711 -45.295 -45.295 -45.295 -45.295 -45.295 -45.295 -45.295 -45.295 -45.295 -45.295 -45.295 -45.295 -45.295 -45.636 -45.979 ...
            -46.322 -46.664 -46.754 -46.754 -46.754 -46.754 -46.754 -46.754 -46.754 -46.754 -46.754 -46.754 -46.754 -46.754 -46.754 -42.793 ...
            -38.682 -34.570 -30.459 -29.249 -29.249 -29.249 -29.249 -29.249 -29.249 -29.249 -29.249 -29.249 -29.249 -29.249 -29.249 -29.249 ...
            -27.732 -26.105 -24.477 -22.850 -22.319 -22.319 -22.319 -22.319 -22.319 -22.319 -22.319 -22.319 -22.319 -22.319 -22.319 -22.319 ...
            -22.319 -17.115 -11.333 -5.552 0.230 2.298 2.298 2.298 2.298 2.298 2.298 2.298 2.298 2.298 2.298 2.298 ...
            2.298 2.298 4.418 6.859 9.300 11.741 12.691 12.691 12.691 12.691 12.691 12.691 12.691 12.691 12.691 12.691 ...
            12.691 12.691 12.691 16.061 20.086 24.112 28.138 29.832 29.832 29.832 29.832 29.832 29.832 29.832 29.832 29.832 ...
            29.832 29.832 29.832 29.832 30.350 30.992 31.634 32.277 32.567 32.567 32.567 32.567 32.567 32.567 32.567 32.567 ...
            32.567 32.567 32.567 32.567 32.567 31.043 29.073 27.103 25.133 24.179 24.179 24.179 24.179 24.179 24.179 24.179 ...
            24.179 24.179 24.179 24.179 24.179 24.179 23.639 22.911 22.183 21.455 21.080 21.080 21.080 21.080 21.080 21.080 ...
            21.080 21.080 21.080 21.080 21.080 21.080 21.080 20.562 19.834 19.106 18.378 17.980 17.980 17.980 17.980 17.980 ...
            17.980 17.980 17.980 17.980 17.980 17.980 17.980 17.980 15.945 12.947 9.949 6.951 5.215 5.215 5.215 5.215 ...
            5.215 5.215 5.215 5.215 5.215 5.215 5.215 5.215 5.215 4.384 3.099 1.814 0.529 -0.255 -0.255 -0.255 ...
            -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -2.364 -5.790 -9.216 -12.642 -14.843 -14.843 ...
            -14.843 -14.843 -14.843 -14.843 -14.843 -14.843 -14.843 -14.843 -14.843 -14.843 -14.843 -18.394 -24.476 -30.557 -36.638 -40.737 ...
            -40.737 -40.737 -40.737 -40.737 -40.737 -40.737 -40.737 -40.737 -40.737 -40.737 -40.737 -40.737 -41.517 -42.930 -44.344 -45.757 ...
            -46.754 -46.754 -46.754 -46.754 -46.754 -46.754 -46.754 -46.754 -46.754 -46.754 -46.754 -46.754 -46.754 -40.444 -28.324 -16.204 ...
            -4.085 4.850 4.850 4.850 4.850 4.850 4.850 4.850 4.850 4.850 4.850 4.850 4.850 4.850 10.338 21.558 ...
            32.779 43.999 52.626 52.626 52.626 52.626 52.626 52.626 52.626 52.626 52.626 52.626 52.626 52.626 52.626 54.722 ...
            59.304 63.887 68.469 72.137 72.137 72.137 72.137 72.137 72.137 72.137 72.137 72.137 72.137 72.137 72.137 72.137 ...
            71.937 71.465 70.994 70.523 70.131 70.131 70.131 70.131 70.131 70.131 70.131 70.131 70.131 70.131 70.131 70.131 ...
            70.131 68.258 63.504 58.750 53.997 49.891 49.891 49.891 49.891 49.891 49.891 49.891 49.891 49.891 49.891 49.891 ...
            49.891 49.891 48.276 43.822 39.368 34.914 30.926 30.926 30.926 30.926 30.926 30.926 30.926 30.926 30.926 30.926 ...
            30.926 30.926 30.926 28.716 22.035 15.354 8.673 2.480 2.480 2.480 2.480 2.480 2.480 2.480 2.480 2.480 ...
            2.480 2.480 2.480 2.480 1.660 -1.081 -3.822 -6.563 -9.190 -9.190 -9.190 -9.190 -9.190 -9.190 -9.190 -9.190 ...
            -9.190 -9.190 -9.190 -9.190 -9.190 -10.130 -13.642 -17.154 -20.665 -24.143 -24.143 -24.143 -24.143 -24.143 -24.143 -24.143 ...
            -24.143 -24.143 -24.143 -24.143 -24.143 -24.143 -24.284 -24.884 -25.484 -26.083 -26.683 -26.696 -26.696 -26.696 -26.696 -26.696 ...
            -26.696 -26.696 -26.696 -26.696 -26.696 -26.696 -26.696 -26.162 -23.550 -20.937 -18.325 -15.712 -15.573 -15.573 -15.573 -15.573 ...
            -15.573 -15.573 -15.573 -15.573 -15.573 -15.573 -15.573 -15.573 -14.766 -10.098 -5.430 -0.762 3.906 4.303 4.303 4.303 ...
            4.303 4.303 4.303 4.303 4.303 4.303 4.303 4.303 4.303 4.406 5.134 5.862 6.590 7.318 7.403 7.403 ...
            7.403 7.403 7.403 7.403 7.403 7.403 7.403 7.403 7.403 7.403 7.980 13.248 18.515 23.783 29.050 29.832 ...
            29.832 29.832 29.832 29.832 29.832 29.832 29.832 29.832 29.832 29.832 29.832 29.832 29.832 29.832 29.832 29.832 ...
            29.832 29.832 29.832 29.832 29.832 29.832 29.832 29.832 29.832 29.832 29.832 29.832 29.787 28.802 27.817 26.832 ...
            25.847 25.638 25.638 25.638 25.638 25.638 25.638 25.638 25.638 25.638 25.638 25.638 25.638 25.593 22.510 19.426 ...
            16.343 13.259 12.509 12.509 12.509 12.509 12.509 12.509 12.509 12.509 12.509 12.509 12.509 12.509 12.509 9.647 ...
            6.734 3.822 0.910 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 ...
            -0.339 -0.810 -1.281 -1.752 -1.896 -1.896 -1.896 -1.896 -1.896 -1.896 -1.896 -1.896 -1.896 -1.896 -1.896 -1.896 ...
            -1.896 -5.087 -8.556 -12.025 -15.493 -16.667 -16.667 -16.667 -16.667 -16.667 -16.667 -16.667 -16.667 -16.667 -16.667 -16.667 ...
            -16.667 -16.667 -18.720 -21.033 -23.346 -25.658 -26.513 -26.513 -26.513 -26.513 -26.513 -26.513 -26.513 -26.513 -26.513 -26.513 ...
            -26.513 -26.513 -26.513 -27.761 -29.217 -30.673 -32.129 -32.713 -32.713 -32.713 -32.713 -32.713 -32.713 -32.713 -32.713 -32.713 ...
            -32.713 -32.713 -32.713 -32.713 -33.879 -35.292 -36.706 -38.119 -38.731 -38.731 -38.731 -38.731 -38.731 -38.731 -38.731 -38.731 ...
            -38.731 -38.731 -38.731 -38.731 -38.731 -36.964 -34.738 -32.511 -30.284 -29.249 -29.249 -29.249 -29.249 -29.249 -29.249 -29.249 ...
            -29.249 -29.249 -29.249 -29.249 -29.249 -29.249 -27.259 -24.647 -22.034 -19.422 -18.125 -18.125 -18.125 -18.125 -18.125 -18.125 ...
            -18.125 -18.125 -18.125 -18.125 -18.125 -18.125 -18.125 -14.624 -9.828 -5.031 -0.235 2.298 2.298 2.298 2.298 2.298 ...
            2.298 2.298 2.298 2.298 2.298 2.298 2.298 2.298 1.849 1.207 0.564 -0.078 -0.438 -0.438 -0.438 -0.438 ...
            -0.438 -0.438 -0.438 -0.438 -0.438 -0.438 -0.438 -0.438 -0.438 -2.065 -4.506 -6.947 -9.388 -10.832 -10.832 -10.832 ...
            -10.832 -10.832 -10.832 -10.832 -10.832 -10.832 -10.832 -10.832 -10.832 -10.832 -12.001 -13.842 -15.684 -17.525 -18.673 -18.673 ...
            -18.673 -18.673 -18.673 -18.673 -18.673 -18.673 -18.673 -18.673 -18.673 -18.673 -18.673 -20.559 -23.685 -26.812 -29.938 -31.984 ...
            -31.984 -31.984 -31.984 -31.984 -31.984 -31.984 -31.984 -31.984 -31.984 -31.984 -31.984 -31.984 -33.453 -36.023 -38.592 -41.162 ...
            -42.925 -42.925 -42.925 -42.925 -42.925 -42.925 -42.925 -42.925 -42.925 -42.925 -42.925 -42.925 -42.925 -43.711 -45.167 -46.624 ...
            -48.080 -49.125 -49.125 -49.125 -49.125 -49.125 -49.125 -49.125 -49.125 -49.125 -49.125 -49.125 -49.125 -49.125 -49.125 -49.125 ...
            -49.125 -49.125 -49.125 -49.125 -49.125 -49.125 -49.125 -49.125 -49.125 -49.125 -49.125 -49.125 -49.125 -49.125 -49.125 -48.492 ...
            -47.164 -45.836 -44.509 -43.472 -43.472 -43.472 -43.472 -43.472 -43.472 -43.472 -43.472 -43.472 -43.472 -43.472 -43.472 -43.472 ...
            -42.824 -41.368 -39.911 -38.455 -37.272 -37.272 -37.272 -37.272 -37.272 -37.272 -37.272 -37.272 -37.272 -37.272 -37.272 -37.272 ...
            -37.272 -36.564 -34.850 -33.137 -31.424 -29.978 -29.978 -29.978 -29.978 -29.978 -29.978 -29.978 -29.978 -29.978 -29.978 -29.978 ...
            -29.978 -29.978 -29.177 -27.078 -24.980 -22.881 -21.043 -21.043 -21.043 -21.043 -21.043 -21.043 -21.043 -21.043 -21.043 -21.043 ...
            -21.043 -21.043 -21.043 -20.683 -19.655 -18.627 -17.599 -16.667 -16.667 -16.667 -16.667 -16.667 -16.667 -16.667 -16.667 -16.667 ...
            -16.667 -16.667 -16.667 -16.667 -16.189 -14.690 -13.191 -11.692 -10.284 -10.284 -10.284 -10.284 -10.284 -10.284 -10.284 -10.284 ...
            -10.284 -10.284 -10.284 -10.284 -10.284 -9.694 -7.639 -5.583 -3.527 -1.532 -1.532 -1.532 -1.532 -1.532 -1.532 -1.532 ...
            -1.532 -1.532 -1.532 -1.532 -1.532 -1.532 -0.963 1.264 3.491 5.718 7.945 7.950 7.950 7.950 7.950 7.950 ...
            7.950 7.950 7.950 7.950 7.950 7.950 7.950 8.305 9.890 11.474 13.059 14.643 14.697 14.697 14.697 14.697 ...
            14.697 14.697 14.697 14.697 14.697 14.697 14.697 14.697 15.134 17.403 19.673 21.943 24.213 24.362 24.362 24.362 ...
            24.362 24.362 24.362 24.362 24.362 24.362 24.362 24.362 24.362 24.699 26.797 28.896 30.994 33.093 33.297 33.297 ...
            33.297 33.297 33.297 33.297 33.297 33.297 33.297 33.297 33.297 33.297 33.606 36.004 38.403 40.801 43.199 43.508 ...
            43.508 43.508 43.508 43.508 43.508 43.508 43.508 43.508 43.508 43.508 43.508 43.713 45.811 47.910 50.008 52.106 ...
            52.443 52.443 52.443 52.443 52.443 52.443 52.443 52.443 52.443 52.443 52.443 52.443 52.441 52.398 52.355 52.312 ...
            52.269 52.261 52.261 52.261 52.261 52.261 52.261 52.261 52.261 52.261 52.261 52.261 52.261 52.143 48.674 45.205 ...
            41.736 38.267 37.491 37.491 37.491 37.491 37.491 37.491 37.491 37.491 37.491 37.491 37.491 37.491 37.468 28.218 ...
            18.968 9.717 0.467 -1.896 -1.896 -1.896 -1.896 -1.896 -1.896 -1.896 -1.896 -1.896 -1.896 -1.896 -1.896 -1.896 ...
            -2.063 -2.234 -2.405 -2.577 -2.626 -2.626 -2.626 -2.626 -2.626 -2.626 -2.626 -2.626 -2.626 -2.626 -2.626 -2.626 ...
            -2.626 -9.745 -17.325 -24.905 -32.485 -34.902 -34.902 -34.902 -34.902 -34.902 -34.902 -34.902 -34.902 -34.902 -34.902 -34.902 ...
            -34.902 -34.902 -39.604 -44.786 -49.968 -55.150 -56.966 -56.966 -56.966 -56.966 -56.966 -56.966 -56.966 -56.966 -56.966 -56.966 ...
            -56.966 -56.966 -56.966 -57.041 -57.126 -57.212 -57.298 -57.330 -57.330 -57.330 -57.330 -57.330 -57.330 -57.330 -57.330 -57.330 ...
            -57.330 -57.330 -57.330 -57.330 -50.641 -42.719 -34.796 -26.873 -23.596 -23.596 -23.596 -23.596 -23.596 -23.596 -23.596 -23.596 ...
            -23.596 -23.596 -23.596 -23.596 -23.596 -13.016 0.003 13.022 26.041 31.838 31.838 31.838 31.838 31.838 31.838 31.838 ...
            31.838 31.838 31.838 31.838 31.838 31.838 31.872 31.914 31.957 32.000 32.020 32.020 32.020 32.020 32.020 32.020 ...
            32.020 32.020 32.020 32.020 32.020 32.020 32.020 31.411 30.597 29.783 28.970 28.556 28.556 28.556 28.556 28.556 ...
            28.556 28.556 28.556 28.556 28.556 28.556 28.556 28.556 25.974 22.376 18.779 15.182 13.239 13.239 13.239 13.239 ...
            13.239 13.239 13.239 13.239 13.239 13.239 13.239 13.239 13.239 13.003 12.661 12.318 11.976 11.780 11.780 11.780 ...
            11.780 11.780 11.780 11.780 11.780 11.780 11.780 11.780 11.780 11.780 12.817 14.401 15.986 17.570 18.527 18.527 ...
            18.527 18.527 18.527 18.527 18.527 18.527 18.527 18.527 18.527 18.527 18.527 18.953 19.639 20.324 21.009 21.444 ...
            21.444 21.444 21.444 21.444 21.444 21.444 21.444 21.444 21.444 21.444 21.444 21.444 17.823 11.699 5.575 -0.549 ...
            -4.632 -4.632 -4.632 -4.632 -4.632 -4.632 -4.632 -4.632 -4.632 -4.632 -4.632 -4.632 -4.632 -5.399 -6.769 -8.139 ...
            -9.510 -10.467 -10.467 -10.467 -10.467 -10.467 -10.467 -10.467 -10.467 -10.467 -10.467 -10.467 -10.467 -10.467 -11.937 -14.720 ...
            -17.504 -20.288 -22.319 -22.319 -22.319 -22.319 -22.319 -22.319 -22.319 -22.319 -22.319 -22.319 -22.319 -22.319 -22.319 -23.701 ...
            -26.485 -29.269 -32.052 -34.172 -34.172 -34.172 -34.172 -34.172 -34.172 -34.172 -34.172 -34.172 -34.172 -34.172 -34.172 -34.172 ...
            -35.904 -39.629 -43.355 -47.081 -50.036 -50.036 -50.036 -50.036 -50.036 -50.036 -50.036 -50.036 -50.036 -50.036 -50.036 -50.036 ...
            -50.036 -51.316 -54.271 -57.226 -60.181 -62.619 -62.619 -62.619 -62.619 -62.619 -62.619 -62.619 -62.619 -62.619 -62.619 -62.619 ...
            -62.619 -62.619 -62.309 -61.538 -60.767 -59.996 -59.336 -59.336 -59.336 -59.336 -59.336 -59.336 -59.336 -59.336 -59.336 -59.336 ...
            -59.336 -59.336 -59.336 -58.560 -56.462 -54.363 -52.265 -50.401 -50.401 -50.401 -50.401 -50.401 -50.401 -50.401 -50.401 -50.401 ...
            -50.401 -50.401 -50.401 -50.401 -49.503 -46.848 -44.193 -41.538 -39.096 -39.096 -39.096 -39.096 -39.096 -39.096 -39.096 -39.096 ...
            -39.096 -39.096 -39.096 -39.096 -39.096 -38.242 -35.458 -32.675 -29.891 -27.243 -27.243 -27.243 -27.243 -27.243 -27.243 -27.243 ...
            -27.243 -27.243 -27.243 -27.243 -27.243 -27.243 -26.595 -24.240 -21.884 -19.529 -17.214 -17.214 -17.214 -17.214 -17.214 -17.214 ...
            -17.214 -17.214 -17.214 -17.214 -17.214 -17.214 -17.214 -16.099 -11.516 -6.934 -2.352 2.231 2.298 2.298 2.298 2.298 ...
            2.298 2.298 2.298 2.298 2.298 2.298 2.298 2.298 2.778 5.048 7.318 9.587 11.857 11.962 11.962 11.962 ...
            11.962 11.962 11.962 11.962 11.962 11.962 11.962 11.962 11.962 12.386 14.742 17.097 19.452 21.808 21.991 21.991 ...
            21.991 21.991 21.991 21.991 21.991 21.991 21.991 21.991 21.991 21.991 22.627 26.909 31.192 35.475 39.757 40.226 ...
            40.226 40.226 40.226 40.226 40.226 40.226 40.226 40.226 40.226 40.226 40.226 40.681 44.578 48.476 52.373 56.270 ...
            56.820 56.820 56.820 56.820 56.820 56.820 56.820 56.820 56.820 56.820 56.820 56.820 57.046 59.701 62.356 65.012 ...
            67.667 68.125 68.125 68.125 68.125 68.125 68.125 68.125 68.125 68.125 68.125 68.125 68.125 68.256 70.697 73.138 ...
            75.579 78.020 78.519 78.519 78.519 78.519 78.519 78.519 78.519 78.519 78.519 78.519 78.519 78.519 78.408 73.311 ...
            68.215 63.119 58.023 56.820 56.820 56.820 56.820 56.820 56.820 56.820 56.820 56.820 56.820 56.820 56.820 56.820 ...
            46.472 36.023 25.573 15.123 12.327 12.327 12.327 12.327 12.327 12.327 12.327 12.327 12.327 12.327 12.327 12.327 ...
            12.327 8.837 5.197 1.557 -2.083 -3.173 -3.173 -3.173 -3.173 -3.173 -3.173 -3.173 -3.173 -3.173 -3.173 -3.173 ...
            -3.173 -3.173 -5.475 -7.959 -10.443 -12.927 -13.749 -13.749 -13.749 -13.749 -13.749 -13.749 -13.749 -13.749 -13.749 -13.749 ...
            -13.749 -13.749 -13.749 -20.958 -29.009 -37.061 -45.112 -48.031 -48.031 -48.031 -48.031 -48.031 -48.031 -48.031 -48.031 -48.031 ...
            -48.031 -48.031 -48.031 -48.031 -49.362 -50.904 -52.446 -53.987 -54.595 -54.595 -54.595 -54.595 -54.595 -54.595 -54.595 -54.595 ...
            -54.595 -54.595 -54.595 -54.595 -54.595 -54.625 -54.662 -54.698 -54.734 -54.770 -54.807 -54.843 -54.879 -54.915 -54.951 -54.988 ...
            -55.024 -55.060 -55.096 -55.133 -55.169 -55.205 -55.241 -55.278 -55.314 -55.350 -55.386 -55.423 -55.459 -55.495 -55.531 -55.568 ...
            -55.604 -55.640 -55.676 -55.712 -55.749 -55.785 -55.821 -55.857 -55.894 -55.930 -55.966 -56.002 -56.039 -56.075 -56.111 -56.147 ...
            -56.184 -56.220 -56.256 -56.292 -56.328 -56.365 -56.401 -56.437 -56.473 -56.510 -56.546 -56.582 -56.601 -56.601 -56.601 -56.601 ...
            -56.601 -56.601 -56.601 -56.601 -56.601 -56.601 -56.601 -56.601 -56.601 -56.571 -56.528 -56.485 -56.442 -56.419 -56.419 -56.419 ...
            -56.419 -56.419 -56.419 -56.419 -56.419 -56.419 -56.419 -56.419 -56.419 -56.419 -56.390 -56.347 -56.304 -56.261 -56.236 -56.236 ...
            -56.236 -56.236 -56.236 -56.236 -56.236 -56.236 -56.236 -56.236 -56.236 -56.236 -56.236 -55.824 -55.181 -54.539 -53.897 -53.501 ...
            -53.501 -53.501 -53.501 -53.501 -53.501 -53.501 -53.501 -53.501 -53.501 -53.501 -53.501 -53.501 -52.141 -49.914 -47.687 -45.460 ...
            -44.019 -44.019 -44.019 -44.019 -44.019 -44.019 -44.019 -44.019 -44.019 -44.019 -44.019 -44.019 -44.019 -43.027 -41.314 -39.601 ...
            -37.888 -36.725 -36.725 -36.725 -36.725 -36.725 -36.725 -36.725 -36.725 -36.725 -36.725 -36.725 -36.725 -36.725 -35.271 -32.616 ...
            -29.961 -27.306 -25.419 -25.419 -25.419 -25.419 -25.419 -25.419 -25.419 -25.419 -25.419 -25.419 -25.419 -25.419 -25.419 -23.763 ...
            -20.551 -17.339 -14.127 -11.743 -11.743 -11.743 -11.743 -11.743 -11.743 -11.743 -11.743 -11.743 -11.743 -11.743 -11.743 -11.743 ...
            -10.976 -9.391 -7.807 -6.222 -4.996 -4.996 -4.996 -4.996 -4.996 -4.996 -4.996 -4.996 -4.996 -4.996 -4.996 -4.996 ...
            -4.996 -4.454 -3.255 -2.055 -0.856 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 ...
            0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 ...
            0.109 0.109 0.109 0.076 -0.010 -0.095 -0.181 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 ...
            -0.255 -0.255 -0.255 -0.255 -0.225 -0.139 -0.053 0.032 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 ...
            0.109 0.109 0.109 0.109 0.109 0.108 0.103 0.098 0.093 0.088 0.083 0.078 0.072 0.067 0.062 0.057 ...
            0.052 0.047 0.042 0.037 0.032 0.027 0.022 0.017 0.012 0.007 0.002 -0.003 -0.008 -0.013 -0.018 -0.023 ...
            -0.028 -0.033 -0.038 -0.043 -0.048 -0.053 -0.058 -0.064 -0.069 -0.074 -0.079 -0.084 -0.089 -0.094 -0.099 -0.104 ...
            -0.109 -0.114 -0.119 -0.124 -0.129 -0.134 -0.139 -0.144 -0.149 -0.154 -0.159 -0.164 -0.169 -0.174 -0.179 -0.184 ...
            -0.189 -0.195 -0.200 -0.205 -0.210 -0.215 -0.220 -0.225 -0.230 -0.235 -0.240 -0.245 -0.250 -0.255 -0.255 -0.255 ...
            -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.201 0.125 0.450 0.776 1.101 1.427 ...
            1.752 2.078 2.403 2.729 3.054 3.380 3.705 4.031 4.356 4.682 5.007 5.332 5.658 5.983 6.309 6.634 ...
            6.674 6.674 6.674 6.674 6.674 6.674 6.674 6.674 6.674 6.674 6.674 6.674 6.732 7.289 7.846 8.402 ...
            8.959 9.044 9.044 9.044 9.044 9.044 9.044 9.044 9.044 9.044 9.044 9.044 9.044 9.426 14.651 19.875 ...
            25.100 30.325 31.291 31.291 31.291 31.291 31.291 31.291 31.291 31.291 31.291 31.291 31.291 31.291 31.419 34.502 ...
            37.585 40.669 43.752 44.420 44.420 44.420 44.420 44.420 44.420 44.420 44.420 44.420 44.420 44.420 44.420 44.450 ...
            47.490 50.531 53.572 56.612 57.367 57.367 57.367 57.367 57.367 57.367 57.367 57.367 57.367 57.367 57.367 57.367 ...
            57.367 62.226 67.194 72.162 77.129 78.519 78.519 78.519 78.519 78.519 78.519 78.519 78.519 78.519 78.519 78.519 ...
            78.519 78.519 81.559 84.771 87.983 91.195 92.195 92.195 92.195 92.195 92.195 92.195 92.195 92.195 92.195 92.195 ...
            92.195 92.195 92.195 91.960 91.703 91.446 91.190 91.101 91.101 91.101 91.101 91.101 91.101 91.101 91.101 91.101 ...
            91.101 91.101 91.101 91.101 85.957 80.133 74.309 68.484 66.302 66.302 66.302 66.302 66.302 66.302 66.302 66.302 ...
            66.302 66.302 66.302 66.302 66.302 63.311 59.800 56.288 52.776 51.349 51.349 51.349 51.349 51.349 51.349 51.349 ...
            51.349 51.349 51.349 51.349 51.349 51.349 47.487 42.776 38.065 33.354 31.291 31.291 31.291 31.291 31.291 31.291 ...
            31.291 31.291 31.291 31.291 31.291 31.291 31.291 28.421 24.781 21.141 17.501 15.791 15.791 15.791 15.791 15.791 ...
            15.791 15.791 15.791 15.791 15.791 15.791 15.791 15.791 14.560 12.933 11.305 9.678 8.862 8.862 8.862 8.862 ...
            8.862 8.862 8.862 8.862 8.862 8.862 8.862 8.862 8.862 8.117 7.089 6.061 5.033 4.486 4.486 4.486 ...
            4.486 4.486 4.486 4.486 4.486 4.486 4.486 4.486 4.486 4.486 5.585 7.169 8.754 10.338 11.233 11.233 ...
            11.233 11.233 11.233 11.233 11.233 11.233 11.233 11.233 11.233 11.233 11.233 12.111 13.439 14.766 16.094 16.885 ...
            16.885 16.885 16.885 16.885 16.885 16.885 16.885 16.885 16.885 16.885 16.885 16.885 17.452 18.352 19.251 20.150 ...
            20.715 20.715 20.715 20.715 20.715 20.715 20.715 20.715 20.715 20.715 20.715 20.715 20.715 21.586 23.042 24.498 ...
            25.955 26.915 26.915 26.915 26.915 26.915 26.915 26.915 26.915 26.915 26.915 26.915 26.915 26.915 27.012 27.183 ...
            27.354 27.526 27.644 27.644 27.644 27.644 27.644 27.644 27.644 27.644 27.644 27.644 27.644 27.644 27.644 27.507 ...
            27.250 26.993 26.736 26.550 26.550 26.550 26.550 26.550 26.550 26.550 26.550 26.550 26.550 26.550 26.550 26.550 ...
            24.005 18.951 13.898 8.844 5.033 5.033 5.033 5.033 5.033 5.033 5.033 5.033 5.033 5.033 5.033 5.033 ...
            5.033 4.305 2.763 1.222 -0.320 -1.532 -1.532 -1.532 -1.532 -1.532 -1.532 -1.532 -1.532 -1.532 -1.532 -1.532 ...
            -1.532 -1.532 -2.569 -4.924 -7.280 -9.635 -11.561 -11.561 -11.561 -11.561 -11.561 -11.561 -11.561 -11.561 -11.561 -11.561 ...
            -11.561 -11.561 -11.561 -12.471 -14.698 -16.925 -19.152 -21.043 -21.043 -21.043 -21.043 -21.043 -21.043 -21.043 -21.043 -21.043 ...
            -21.043 -21.043 -21.043 -21.043 -21.851 -23.992 -26.133 -28.274 -30.160 -30.160 -30.160 -30.160 -30.160 -30.160 -30.160 -30.160 ...
            -30.160 -30.160 -30.160 -30.160 -30.160 -30.738 -32.408 -34.078 -35.748 -37.272 -37.272 -37.272 -37.272 -37.272 -37.272 -37.272 ...
            -37.272 -37.272 -37.272 -37.272 -37.272 -37.272 -37.487 -38.172 -38.858 -39.543 -40.190 -40.190 -40.190 -40.190 -40.190 -40.190 ...
            -40.190 -40.190 -40.190 -40.190 -40.190 -40.190 -40.190 -40.492 -41.562 -42.633 -43.704 -44.748 -44.748 -44.748 -44.748 -44.748 ...
            -44.748 -44.748 -44.748 -44.748 -44.748 -44.748 -44.748 -44.748 -44.942 -45.712 -46.483 -47.254 -48.025 -48.031 -48.031 -48.031 ...
            -48.031 -48.031 -48.031 -48.031 -48.031 -48.031 -48.031 -48.031 -48.031 -48.124 -48.553 -48.981 -49.409 -49.837 -49.854 -49.854 ...
            -49.854 -49.854 -49.854 -49.854 -49.854 -49.854 -49.854 -49.854 -49.854 -49.854 -49.605 -48.278 -46.950 -45.623 -44.295 -44.201 ...
            -44.201 -44.201 -44.201 -44.201 -44.201 -44.201 -44.201 -44.201 -44.201 -44.201 -44.201 -43.815 -41.331 -38.847 -36.363 -33.879 ...
            -33.625 -33.625 -33.625 -33.625 -33.625 -33.625 -33.625 -33.625 -33.625 -33.625 -33.625 -33.625 -33.094 -28.811 -24.528 -20.246 ...
            -15.963 -15.390 -15.390 -15.390 -15.390 -15.390 -15.390 -15.390 -15.390 -15.390 -15.390 -15.390 -15.390 -15.240 -13.612 -11.985 ...
            -10.358 -8.730 -8.461 -8.461 -8.461 -8.461 -8.461 -8.461 -8.461 -8.461 -8.461 -8.461 -8.461 -8.461 -8.365 -6.780 ...
            -5.195 -3.611 -2.026 -1.714 -1.714 -1.714 -1.714 -1.714 -1.714 -1.714 -1.714 -1.714 -1.714 -1.714 -1.714 -1.702 ...
            -1.273 -0.845 -0.417 0.011 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 ...
            0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 ...
            0.109 0.109 1.805 3.561 5.317 7.073 7.586 7.586 7.586 7.586 7.586 7.586 7.586 7.586 7.586 7.586 ...
            7.586 7.586 7.586 7.586 7.586 7.586 7.586 7.586 7.586 7.586 7.586 7.586 7.586 7.586 7.586 7.586 ...
            7.586 7.586 7.586 7.586 12.341 17.608 22.876 28.143 30.015 30.015 30.015 30.015 30.015 30.015 30.015 30.015 ...
            30.015 30.015 30.015 30.015 30.015 29.753 29.454 29.154 28.854 28.738 28.738 28.738 28.738 28.738 28.738 28.738 ...
            28.738 28.738 28.738 28.738 28.738 28.738 31.003 33.701 36.399 39.097 40.226 40.226 40.226 40.226 40.226 40.226 ...
            40.226 40.226 40.226 40.226 40.226 40.226 40.226 39.811 39.297 38.783 38.269 38.038 38.038 38.038 38.038 38.038 ...
            38.038 38.038 38.038 38.038 38.038 38.038 38.038 38.038 37.838 37.582 37.325 37.068 36.944 36.944 36.944 36.944 ...
            36.944 36.944 36.944 36.944 36.944 36.944 36.944 36.944 36.944 36.497 35.898 35.298 34.699 34.391 34.391 34.391 ...
            34.391 34.391 34.391 34.391 34.391 34.391 34.391 34.391 34.391 34.391 33.964 33.364 32.764 32.165 31.838 31.838 ...
            31.838 31.838 31.838 31.838 31.838 31.838 31.838 31.838 31.838 31.838 31.838 31.488 30.974 30.460 29.946 29.650 ...
            29.650 29.650 29.650 29.650 29.650 29.650 29.650 29.650 29.650 29.650 29.650 29.650 29.372 28.943 28.515 28.087 ...
            27.826 27.826 27.826 27.826 27.826 27.826 27.826 27.826 27.826 27.826 27.826 27.826 27.826 27.350 26.579 25.808 ...
            25.037 24.544 24.544 24.544 24.544 24.544 24.544 24.544 24.544 24.544 24.544 24.544 24.544 24.544 23.916 22.846 ...
            21.775 20.704 19.985 19.985 19.985 19.985 19.985 19.985 19.985 19.985 19.985 19.985 19.985 19.985 19.985 19.558 ...
            18.787 18.016 17.245 16.703 16.703 16.703 16.703 16.703 16.703 16.703 16.703 16.703 16.703 16.703 16.703 16.703 ...
            16.479 16.051 15.623 15.194 14.880 14.880 14.880 14.880 14.880 14.880 14.880 14.880 14.880 14.880 14.880 14.880 ...
            14.880 14.227 12.900 11.572 10.244 9.227 9.227 9.227 9.227 9.227 9.227 9.227 9.227 9.227 9.227 9.227 ...
            9.227 9.227 9.148 8.977 8.805 8.634 8.497 8.497 8.497 8.497 8.497 8.497 8.497 8.497 8.497 8.497 ...
            8.497 8.497 8.497 7.856 6.357 4.858 3.359 2.115 2.115 2.115 2.115 2.115 2.115 2.115 2.115 2.115 ...
            2.115 2.115 2.115 2.115 1.215 -1.055 -3.324 -5.594 -7.549 -7.549 -7.549 -7.549 -7.549 -7.549 -7.549 -7.549 ...
            -7.549 -7.549 -7.549 -7.549 -7.549 -7.909 -8.894 -9.879 -10.864 -11.743 -11.743 -11.743 -11.743 -11.743 -11.743 -11.743 ...
            -11.743 -11.743 -11.743 -11.743 -11.743 -11.743 -12.771 -15.855 -18.938 -22.021 -24.872 -24.872 -24.872 -24.872 -24.872 -24.872 ...
            -24.872 -24.872 -24.872 -24.872 -24.872 -24.872 -24.872 -25.712 -28.496 -31.280 -34.063 -36.725 -36.725 -36.725 -36.725 -36.725 ...
            -36.725 -36.725 -36.725 -36.725 -36.725 -36.725 -36.725 -36.725 -37.118 -38.574 -40.030 -41.487 -42.925 -42.925 -42.925 -42.925 ...
            -42.925 -42.925 -42.925 -42.925 -42.925 -42.925 -42.925 -42.925 -42.925 -42.363 -40.008 -37.652 -35.297 -32.942 -32.896 -32.896 ...
            -32.896 -32.896 -32.896 -32.896 -32.896 -32.896 -32.896 -32.896 -32.896 -32.896 -32.169 -28.658 -25.146 -21.634 -18.123 -17.943 ...
            -17.943 -17.943 -17.943 -17.943 -17.943 -17.943 -17.943 -17.943 -17.943 -17.943 -17.943 -17.508 -15.024 -12.540 -10.056 -7.572 ...
            -7.367 -7.367 -7.367 -7.367 -7.367 -7.367 -7.367 -7.367 -7.367 -7.367 -7.367 -7.367 -7.133 -5.506 -3.879 -2.251 ...
            -0.624 -0.438 -0.438 -0.438 -0.438 -0.438 -0.438 -0.438 -0.438 -0.438 -0.438 -0.438 -0.438 -0.436 -0.423 -0.410 ...
            -0.397 -0.383 -0.370 -0.357 -0.344 -0.331 -0.318 -0.304 -0.291 -0.278 -0.265 -0.252 -0.239 -0.225 -0.212 -0.199 ...
            -0.186 -0.173 -0.159 -0.146 -0.133 -0.120 -0.107 -0.094 -0.080 -0.067 -0.054 -0.041 -0.028 -0.014 -0.001 0.012 ...
            0.025 0.038 0.051 0.065 0.078 0.091 0.104 0.117 0.130 0.144 0.157 0.170 0.183 0.196 0.210 0.223 ...
            0.236 0.249 0.262 0.275 0.289 0.292 0.292 0.292 0.292 0.292 0.292 0.292 0.292 0.292 0.292 0.292 ...
            0.292 0.292 2.908 5.563 8.219 10.874 11.597 11.597 11.597 11.597 11.597 11.597 11.597 11.597 11.597 11.597 ...
            11.597 11.597 11.597 14.007 16.534 19.061 21.587 22.356 22.356 22.356 22.356 22.356 22.356 22.356 22.356 22.356 ...
            22.356 22.356 22.356 22.356 23.896 25.566 27.237 28.907 29.468 29.468 29.468 29.468 29.468 29.468 29.468 29.468 ...
            29.468 29.468 29.468 29.468 29.468 31.794 34.406 37.019 39.631 40.591 40.591 40.591 40.591 40.591 40.591 40.591 ...
            40.591 40.591 40.591 40.591 40.591 40.591 40.922 41.307 41.693 42.078 42.232 42.232 42.232 42.232 42.232 42.232 ...
            42.232 42.232 42.232 42.232 42.232 42.232 42.232 40.567 38.554 36.541 34.528 33.662 33.662 33.662 33.662 33.662 ...
            33.662 33.662 33.662 33.662 33.662 33.662 33.662 33.662 32.878 31.893 30.908 29.923 29.468 29.468 29.468 29.468 ...
            29.468 29.468 29.468 29.468 29.468 29.468 29.468 29.468 29.468 28.486 27.201 25.916 24.632 23.997 23.997 23.997 ...
            23.997 23.997 23.997 23.997 23.997 23.997 23.997 23.997 23.997 23.997 23.433 22.662 21.891 21.120 20.715 20.715 ...
            20.715 20.715 20.715 20.715 20.715 20.715 20.715 20.715 20.715 20.715 20.715 19.724 18.311 16.898 15.485 14.697 ...
            14.697 14.697 14.697 14.697 14.697 14.697 14.697 14.697 14.697 14.697 14.697 14.697 14.010 12.982 11.954 10.926 ...
            10.321 10.321 10.321 10.321 10.321 10.321 10.321 10.321 10.321 10.321 10.321 10.321 10.321 9.011 6.955 4.899 ...
            2.844 1.568 1.568 1.568 1.568 1.568 1.568 1.568 1.568 1.568 1.568 1.568 1.568 1.568 1.542 1.499 ...
            1.457 1.414 1.386 1.386 1.386 1.386 1.386 1.386 1.386 1.386 1.386 1.386 1.386 1.386 1.386 0.968 ...
            0.240 -0.488 -1.216 -1.714 -1.714 -1.714 -1.714 -1.714 -1.714 -1.714 -1.714 -1.714 -1.714 -1.714 -1.714 -1.714 ...
            -1.714 -1.714 -1.714 -1.714 -1.714 -1.714 -1.714 -1.714 -1.714 -1.714 -1.714 -1.714 -1.714 -1.714 -1.714 -1.714 ...
            -1.714 -0.861 0.810 2.480 4.150 5.398 5.398 5.398 5.398 5.398 5.398 5.398 5.398 5.398 5.398 5.398 ...
            5.398 5.398 5.623 6.094 6.565 7.037 7.403 7.403 7.403 7.403 7.403 7.403 7.403 7.403 7.403 7.403 ...
            7.403 7.403 7.403 8.094 9.635 11.177 12.719 13.968 13.968 13.968 13.968 13.968 13.968 13.968 13.968 13.968 ...
            13.968 13.968 13.968 13.968 14.502 15.787 17.072 18.357 19.438 19.438 19.438 19.438 19.438 19.438 19.438 19.438 ...
            19.438 19.438 19.438 19.438 19.438 20.015 21.513 23.012 24.511 25.821 25.821 25.821 25.821 25.821 25.821 25.821 ...
            25.821 25.821 25.821 25.821 25.821 25.821 25.941 26.284 26.627 26.969 27.279 27.279 27.279 27.279 27.279 27.279 ...
            27.279 27.279 27.279 27.279 27.279 27.279 27.279 27.348 27.562 27.776 27.991 28.191 28.191 28.191 28.191 28.191 ...
            28.191 28.191 28.191 28.191 28.191 28.191 28.191 28.191 27.596 25.540 23.485 21.429 19.438 19.438 19.438 19.438 ...
            19.438 19.438 19.438 19.438 19.438 19.438 19.438 19.438 19.438 19.162 18.092 17.021 15.950 14.880 14.880 14.880 ...
            14.880 14.880 14.880 14.880 14.880 14.880 14.880 14.880 14.880 14.880 14.521 12.937 11.352 9.767 8.183 8.133 ...
            8.133 8.133 8.133 8.133 8.133 8.133 8.133 8.133 8.133 8.133 8.133 8.249 8.849 9.449 10.048 10.648 ...
            10.686 10.686 10.686 10.686 10.686 10.686 10.686 10.686 10.686 10.686 10.686 10.686 11.174 14.172 17.170 20.168 ...
            23.166 23.450 23.450 23.450 23.450 23.450 23.450 23.450 23.450 23.450 23.450 23.450 23.450 23.726 25.824 27.923 ...
            30.021 32.120 32.385 32.385 32.385 32.385 32.385 32.385 32.385 32.385 32.385 32.385 32.385 32.385 32.351 32.008 ...
            31.666 31.323 30.981 30.926 30.926 30.926 30.926 30.926 30.926 30.926 30.926 30.926 30.926 30.926 30.926 30.433 ...
            23.196 15.958 8.721 1.483 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 ...
            0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 ...
            0.109 0.077 -6.604 -13.285 -19.966 -26.646 -28.337 -28.337 -28.337 -28.337 -28.337 -28.337 -28.337 -28.337 -28.337 -28.337 ...
            -28.337 -28.337 -28.337 -32.588 -36.957 -41.325 -45.693 -46.937 -46.937 -46.937 -46.937 -46.937 -46.937 -46.937 -46.937 -46.937 ...
            -46.937 -46.937 -46.937 -46.937 -45.525 -44.026 -42.527 -41.028 -40.554 -40.554 -40.554 -40.554 -40.554 -40.554 -40.554 -40.554 ...
            -40.554 -40.554 -40.554 -40.554 -40.554 -37.008 -33.111 -29.214 -25.317 -23.961 -23.961 -23.961 -23.961 -23.961 -23.961 -23.961 ...
            -23.961 -23.961 -23.961 -23.961 -23.961 -23.961 -20.650 -16.882 -13.113 -9.344 -7.914 -7.914 -7.914 -7.914 -7.914 -7.914 ...
            -7.914 -7.914 -7.914 -7.914 -7.914 -7.914 -7.914 -7.334 -6.649 -5.963 -5.278 -4.996 -4.996 -4.996 -4.996 -4.996 ...
            -4.996 -4.996 -4.996 -4.996 -4.996 -4.996 -4.996 -4.996 -4.054 -2.898 -1.741 -0.585 -0.073 -0.073 -0.073 -0.073 ...
            -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.039 0.003 0.046 0.089 0.109 0.109 0.109 ...
            0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 ...
            0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 ...
            0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 ...
            0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 ...
            0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 ...
            0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 ...
            0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 ...
            0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 ...
            0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 ...
            0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 ...
            0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 ...
            0.109 0.109 0.109 0.109 0.214 0.454 0.694 0.933 1.173 1.413 1.653 1.893 2.132 2.372 2.612 2.852 ...
            3.092 3.332 3.571 3.811 4.051 4.291 4.531 4.771 5.010 5.215 5.215 5.215 5.215 5.215 5.215 5.215 ...
            5.215 5.215 5.215 5.215 5.215 5.215 5.279 5.450 5.622 5.793 5.945 5.945 5.945 5.945 5.945 5.945 ...
            5.945 5.945 5.945 5.945 5.945 5.945 5.945 6.207 6.978 7.749 8.520 9.227 9.227 9.227 9.227 9.227 ...
            9.227 9.227 9.227 9.227 9.227 9.227 9.227 9.227 9.849 11.862 13.874 15.887 17.797 17.797 17.797 17.797 ...
            17.797 17.797 17.797 17.797 17.797 17.797 17.797 17.797 17.797 18.035 18.891 19.748 20.604 21.444 21.444 21.444 ...
            21.444 21.444 21.444 21.444 21.444 21.444 21.444 21.444 21.444 21.444 21.749 22.991 24.233 25.475 26.717 26.732 ...
            26.732 26.732 26.732 26.732 26.732 26.732 26.732 26.732 26.732 26.732 26.732 26.934 27.876 28.818 29.761 30.703 ...
            30.744 30.744 30.744 30.744 30.744 30.744 30.744 30.744 30.744 30.744 30.744 30.744 30.642 30.086 29.529 28.972 ...
            28.415 28.373 28.373 28.373 28.373 28.373 28.373 28.373 28.373 28.373 28.373 28.373 28.373 28.180 26.895 25.610 ...
            24.325 23.041 22.903 22.903 22.903 22.903 22.903 22.903 22.903 22.903 22.903 22.903 22.903 22.903 22.801 21.944 ...
            21.088 20.231 19.375 19.256 19.256 19.256 19.256 19.256 19.256 19.256 19.256 19.256 19.256 19.256 19.256 18.922 ...
            15.111 11.299 7.488 3.676 3.027 3.027 3.027 3.027 3.027 3.027 3.027 3.027 3.027 3.027 3.027 3.027 ...
            2.984 2.213 1.442 0.671 -0.100 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 ...
            -0.255 -0.292 -1.791 -3.290 -4.788 -6.287 -6.637 -6.637 -6.637 -6.637 -6.637 -6.637 -6.637 -6.637 -6.637 -6.637 ...
            -6.637 -6.637 -6.637 -9.656 -12.697 -15.737 -18.778 -19.584 -19.584 -19.584 -19.584 -19.584 -19.584 -19.584 -19.584 -19.584 ...
            -19.584 -19.584 -19.584 -19.584 -21.642 -23.783 -25.925 -28.066 -28.702 -28.702 -28.702 -28.702 -28.702 -28.702 -28.702 -28.702 ...
            -28.702 -28.702 -28.702 -28.702 -28.702 -30.055 -31.511 -32.967 -34.423 -34.902 -34.902 -34.902 -34.902 -34.902 -34.902 -34.902 ...
            -34.902 -34.902 -34.902 -34.902 -34.902 -34.902 -35.055 -35.227 -35.398 -35.569 -35.631 -35.631 -35.631 -35.631 -35.631 -35.631 ...
            -35.631 -35.631 -35.631 -35.631 -35.631 -35.631 -35.631 -35.408 -35.151 -34.894 -34.637 -34.537 -34.537 -34.537 -34.537 -34.537 ...
            -34.537 -34.537 -34.537 -34.537 -34.537 -34.537 -34.537 -34.537 -33.429 -32.101 -30.774 -29.446 -28.884 -28.884 -28.884 -28.884 ...
            -28.884 -28.884 -28.884 -28.884 -28.884 -28.884 -28.884 -28.884 -28.884 -27.749 -26.336 -24.923 -23.510 -22.867 -22.867 -22.867 ...
            -22.867 -22.867 -22.867 -22.867 -22.867 -22.867 -22.867 -22.867 -22.867 -22.867 -22.536 -22.108 -21.680 -21.251 -21.043 -21.043 ...
            -21.043 -21.043 -21.043 -21.043 -21.043 -21.043 -21.043 -21.043 -21.043 -21.043 -21.043 -20.726 -20.298 -19.870 -19.441 -19.220 ...
            -19.220 -19.220 -19.220 -19.220 -19.220 -19.220 -19.220 -19.220 -19.220 -19.220 -19.220 -19.220 -18.856 -18.342 -17.828 -17.314 ...
            -17.031 -17.031 -17.031 -17.031 -17.031 -17.031 -17.031 -17.031 -17.031 -17.031 -17.031 -17.031 -17.031 -16.481 -15.667 -14.854 ...
            -14.040 -13.567 -13.567 -13.567 -13.567 -13.567 -13.567 -13.567 -13.567 -13.567 -13.567 -13.567 -13.567 -13.567 -13.401 -13.144 ...
            -12.887 -12.630 -12.473 -12.473 -12.473 -12.473 -12.473 -12.473 -12.473 -12.473 -12.473 -12.473 -12.473 -12.473 -12.473 -12.105 ...
            -11.505 -10.906 -10.306 -9.920 -9.920 -9.920 -9.920 -9.920 -9.920 -9.920 -9.920 -9.920 -9.920 -9.920 -9.920 -9.920 ...
            -9.596 -9.039 -8.483 -7.926 -7.549 -7.549 -7.549 -7.549 -7.549 -7.549 -7.549 -7.549 -7.549 -7.549 -7.549 -7.549 ...
            -7.549 -7.455 -7.284 -7.112 -6.941 -6.820 -6.820 -6.820 -6.820 -6.820 -6.820 -6.820 -6.820 -6.820 -6.820 -6.820 ...
            -6.820 -6.820 -6.398 -5.584 -4.771 -3.957 -3.355 -3.355 -3.355 -3.355 -3.355 -3.355 -3.355 -3.355 -3.355 -3.355 ...
            -3.355 -3.355 -3.355 -2.855 -1.827 -0.799 0.228 1.021 1.021 1.021 1.021 1.021 1.021 1.021 1.021 1.021 ...
            1.021 1.021 1.021 1.021 1.508 2.579 3.650 4.720 5.580 5.580 5.580 5.580 5.580 5.580 5.580 5.580 ...
            5.580 5.580 5.580 5.580 5.580 5.888 6.616 7.344 8.072 8.680 8.680 8.680 8.680 8.680 8.680 8.680 ...
            8.680 8.680 8.680 8.680 8.680 8.680 9.015 9.872 10.728 11.585 12.327 12.327 12.327 12.327 12.327 12.327 ...
            12.327 12.327 12.327 12.327 12.327 12.327 12.327 12.589 13.317 14.045 14.773 15.427 15.427 15.427 15.427 15.427 ...
            15.427 15.427 15.427 15.427 15.427 15.427 15.427 15.427 15.947 17.532 19.116 20.701 22.174 22.174 22.174 22.174 ...
            22.174 22.174 22.174 22.174 22.174 22.174 22.174 22.174 22.174 22.390 23.118 23.846 24.574 25.274 25.274 25.274 ...
            25.274 25.274 25.274 25.274 25.274 25.274 25.274 25.274 25.274 25.274 25.626 26.953 28.281 29.608 30.926 30.926 ...
            30.926 30.926 30.926 30.926 30.926 30.926 30.926 30.926 30.926 30.926 30.926 31.176 32.247 33.318 34.388 35.459 ...
            35.485 35.485 35.485 35.485 35.485 35.485 35.485 35.485 35.485 35.485 35.485 35.485 35.572 36.000 36.428 36.856 ...
            37.285 37.309 37.309 37.309 37.309 37.309 37.309 37.309 37.309 37.309 37.309 37.309 37.309 37.119 36.005 34.892 ...
            33.778 32.665 32.567 32.567 32.567 32.567 32.567 32.567 32.567 32.567 32.567 32.567 32.567 32.567 31.724 25.643 ...
            19.562 13.480 7.399 6.674 6.674 6.674 6.674 6.674 6.674 6.674 6.674 6.674 6.674 6.674 6.674 6.436 ...
            4.209 1.982 -0.245 -2.472 -2.808 -2.808 -2.808 -2.808 -2.808 -2.808 -2.808 -2.808 -2.808 -2.808 -2.808 -2.808 ...
            -2.996 -5.479 -7.963 -10.447 -12.931 -13.384 -13.384 -13.384 -13.384 -13.384 -13.384 -13.384 -13.384 -13.384 -13.384 -13.384 ...
            -13.384 -13.542 -17.139 -20.737 -24.334 -27.931 -28.702 -28.702 -28.702 -28.702 -28.702 -28.702 -28.702 -28.702 -28.702 -28.702 ...
            -28.702 -28.702 -28.719 -30.175 -31.632 -33.088 -34.544 -34.902 -34.902 -34.902 -34.902 -34.902 -34.902 -34.902 -34.902 -34.902 ...
            -34.902 -34.902 -34.902 -34.902 -34.944 -34.986 -35.029 -35.072 -35.084 -35.084 -35.084 -35.084 -35.084 -35.084 -35.084 -35.084 ...
            -35.084 -35.084 -35.084 -35.084 -35.084 -35.693 -36.336 -36.978 -37.621 -37.819 -37.819 -37.819 -37.819 -37.819 -37.819 -37.819 ...
            -37.819 -37.819 -37.819 -37.819 -37.819 -37.819 -37.858 -37.901 -37.944 -37.987 -38.001 -38.001 -38.001 -38.001 -38.001 -38.001 ...
            -38.001 -38.001 -38.001 -38.001 -38.001 -38.001 -38.001 -38.570 -39.213 -39.855 -40.498 -40.737 -40.737 -40.737 -40.737 -40.737 ...
            -40.737 -40.737 -40.737 -40.737 -40.737 -40.737 -40.737 -40.737 -40.773 -40.816 -40.859 -40.902 -40.919 -40.919 -40.919 -40.919 ...
            -40.919 -40.919 -40.919 -40.919 -40.919 -40.919 -40.919 -40.919 -40.919 -40.179 -39.280 -38.381 -37.481 -37.090 -37.090 -37.090 ...
            -37.090 -37.090 -37.090 -37.090 -37.090 -37.090 -37.090 -37.090 -37.090 -37.090 -35.701 -33.945 -32.190 -30.434 -29.613 -29.613 ...
            -29.613 -29.613 -29.613 -29.613 -29.613 -29.613 -29.613 -29.613 -29.613 -29.613 -29.613 -27.890 -25.621 -23.351 -21.081 -19.949 ...
            -19.949 -19.949 -19.949 -19.949 -19.949 -19.949 -19.949 -19.949 -19.949 -19.949 -19.949 -19.949 -18.422 -16.324 -14.225 -12.127 ...
            -11.014 -11.014 -11.014 -11.014 -11.014 -11.014 -11.014 -11.014 -11.014 -11.014 -11.014 -11.014 -11.014 -8.332 -4.477 -0.623 ...
            3.231 5.398 5.398 5.398 5.398 5.398 5.398 5.398 5.398 5.398 5.398 5.398 5.398 5.398 5.966 6.823 ...
            7.679 8.536 9.044 9.044 9.044 9.044 9.044 9.044 9.044 9.044 9.044 9.044 9.044 9.044 9.044 11.374 ...
            15.057 18.740 22.423 24.726 24.726 24.726 24.726 24.726 24.726 24.726 24.726 24.726 24.726 24.726 24.726 24.726 ...
            25.988 28.086 30.185 32.283 33.662 33.662 33.662 33.662 33.662 33.662 33.662 33.662 33.662 33.662 33.662 33.662 ...
            33.662 34.808 36.820 38.833 40.846 42.232 42.232 42.232 42.232 42.232 42.232 42.232 42.232 42.232 42.232 42.232 ...
            42.232 42.232 42.646 43.417 44.188 44.959 45.514 45.514 45.514 45.514 45.514 45.514 45.514 45.514 45.514 45.514 ...
            45.514 45.514 45.514 44.907 43.708 42.509 41.310 40.408 40.408 40.408 40.408 40.408 40.408 40.408 40.408 40.408 ...
            40.408 40.408 40.408 40.408 39.352 37.125 34.898 32.671 30.926 30.926 30.926 30.926 30.926 30.926 30.926 30.926 ...
            30.926 30.926 30.926 30.926 30.926 29.959 27.775 25.591 23.407 21.627 21.627 21.627 21.627 21.627 21.627 21.627 ...
            21.627 21.627 21.627 21.627 21.627 21.627 19.778 15.281 10.784 6.287 2.480 2.480 2.480 2.480 2.480 2.480 ...
            2.480 2.480 2.480 2.480 2.480 2.480 2.480 2.431 2.303 2.174 2.046 1.933 1.933 1.933 1.933 1.933 ...
            1.933 1.933 1.933 1.933 1.933 1.933 1.933 1.933 0.666 -2.974 -6.614 -10.254 -13.567 -13.567 -13.567 -13.567 ...
            -13.567 -13.567 -13.567 -13.567 -13.567 -13.567 -13.567 -13.567 -13.567 -14.068 -15.652 -17.237 -18.822 -20.314 -20.314 -20.314 ...
            -20.314 -20.314 -20.314 -20.314 -20.314 -20.314 -20.314 -20.314 -20.314 -20.314 -20.740 -22.239 -23.738 -25.237 -26.696 -26.696 ...
            -26.696 -26.696 -26.696 -26.696 -26.696 -26.696 -26.696 -26.696 -26.696 -26.696 -26.696 -27.021 -28.306 -29.590 -30.875 -32.160 ...
            -32.166 -32.166 -32.166 -32.166 -32.166 -32.166 -32.166 -32.166 -32.166 -32.166 -32.166 -32.166 -31.901 -30.702 -29.503 -28.303 ...
            -27.104 -27.061 -27.061 -27.061 -27.061 -27.061 -27.061 -27.061 -27.061 -27.061 -27.061 -27.061 -27.061 -26.760 -25.175 -23.591 ...
            -22.006 -20.422 -20.314 -20.314 -20.314 -20.314 -20.314 -20.314 -20.314 -20.314 -20.314 -20.314 -20.314 -20.314 -20.090 -18.677 ...
            -17.264 -15.850 -14.437 -14.296 -14.296 -14.296 -14.296 -14.296 -14.296 -14.296 -14.296 -14.296 -14.296 -14.296 -14.296 -14.188 ...
            -13.331 -12.475 -11.618 -10.762 -10.649 -10.649 -10.649 -10.649 -10.649 -10.649 -10.649 -10.649 -10.649 -10.649 -10.649 -10.649 ...
            -10.580 -9.852 -9.124 -8.396 -7.668 -7.549 -7.549 -7.549 -7.549 -7.549 -7.549 -7.549 -7.549 -7.549 -7.549 -7.549 ...
            -7.549 -7.490 -6.547 -5.605 -4.663 -3.721 -3.538 -3.538 -3.538 -3.538 -3.538 -3.538 -3.538 -3.538 -3.538 -3.538 ...
            -3.538 -3.538 -3.523 -3.078 -2.633 -2.187 -1.742 -1.297 -0.851 -0.406 0.040 0.485 0.930 1.376 1.821 2.267 ...
            2.712 3.157 3.603 4.048 4.494 4.939 5.384 5.830 5.945 5.945 5.945 5.945 5.945 5.945 5.945 5.945 ...
            5.945 5.945 5.945 5.945 5.945 6.608 7.293 7.979 8.664 8.862 8.862 8.862 8.862 8.862 8.862 8.862 ...
            8.862 8.862 8.862 8.862 8.862 8.862 9.825 10.853 11.881 12.908 13.239 13.239 13.239 13.239 13.239 13.239 ...
            13.239 13.239 13.239 13.239 13.239 13.239 13.239 13.665 14.136 14.607 15.078 15.244 15.244 15.244 15.244 15.244 ...
            15.244 15.244 15.244 15.244 15.244 15.244 15.244 15.244 16.404 17.732 19.059 20.387 20.897 20.897 20.897 20.897 ...
            20.897 20.897 20.897 20.897 20.897 20.897 20.897 20.897 20.897 21.582 22.396 23.210 24.023 24.362 24.362 24.362 ...
            24.362 24.362 24.362 24.362 24.362 24.362 24.362 24.362 24.362 24.362 22.141 19.400 16.659 13.919 12.691 12.691 ...
            12.691 12.691 12.691 12.691 12.691 12.691 12.691 12.691 12.691 12.691 12.691 11.024 8.883 6.742 4.600 3.574 ...
            3.574 3.574 3.574 3.574 3.574 3.574 3.574 3.574 3.574 3.574 3.574 3.574 2.998 2.227 1.456 0.686 ...
            0.292 0.292 0.292 0.292 0.292 0.292 0.292 0.292 0.292 0.292 0.292 0.292 0.292 -3.415 -8.597 -13.779 ...
            -18.961 -21.772 -21.772 -21.772 -21.772 -21.772 -21.772 -21.772 -21.772 -21.772 -21.772 -21.772 -21.772 -21.772 -25.345 -30.569 ...
            -35.794 -41.019 -44.019 -44.019 -44.019 -44.019 -44.019 -44.019 -44.019 -44.019 -44.019 -44.019 -44.019 -44.019 -44.019 -45.080 ...
            -46.708 -48.335 -49.962 -50.948 -50.948 -50.948 -50.948 -50.948 -50.948 -50.948 -50.948 -50.948 -50.948 -50.948 -50.948 -50.948 ...
            -49.460 -47.062 -44.664 -42.265 -40.737 -40.737 -40.737 -40.737 -40.737 -40.737 -40.737 -40.737 -40.737 -40.737 -40.737 -40.737 ...
            -40.737 -38.593 -34.953 -31.313 -27.673 -25.237 -25.237 -25.237 -25.237 -25.237 -25.237 -25.237 -25.237 -25.237 -25.237 -25.237 ...
            -25.237 -25.237 -20.918 -13.167 -5.415 2.336 7.768 7.768 7.768 7.768 7.768 7.768 7.768 7.768 7.768 7.768 ...
            7.768 7.768 7.768 7.723 7.637 7.552 7.466 7.403 7.403 7.403 7.403 7.403 7.403 7.403 7.403 7.403 ...
            7.403 7.403 7.403 7.403 10.682 17.320 23.958 30.596 35.667 35.667 35.667 35.667 35.667 35.667 35.667 35.667 ...
            35.667 35.667 35.667 35.667 35.667 37.905 42.744 47.583 52.423 56.273 56.273 56.273 56.273 56.273 56.273 56.273 ...
            56.273 56.273 56.273 56.273 56.273 56.273 56.457 56.885 57.314 57.742 58.096 58.096 58.096 58.096 58.096 58.096 ...
            58.096 58.096 58.096 58.096 58.096 58.096 58.096 52.560 38.684 24.808 10.933 -0.985 -0.985 -0.985 -0.985 -0.985 ...
            -0.985 -0.985 -0.985 -0.985 -0.985 -0.985 -0.985 -0.985 -1.567 -3.151 -4.736 -6.321 -7.732 -7.732 -7.732 -7.732 ...
            -7.732 -7.732 -7.732 -7.732 -7.732 -7.732 -7.732 -7.732 -7.732 -10.075 -17.056 -24.037 -31.017 -37.454 -37.454 -37.454 ...
            -37.454 -37.454 -37.454 -37.454 -37.454 -37.454 -37.454 -37.454 -37.454 -37.454 -36.686 -34.159 -31.632 -29.106 -26.696 -26.696 ...
            -26.696 -26.696 -26.696 -26.696 -26.696 -26.696 -26.696 -26.696 -26.696 -26.696 -26.696 -23.953 -13.889 -3.825 6.239 16.156 ...
            16.156 16.156 16.156 16.156 16.156 16.156 16.156 16.156 16.156 16.156 16.156 16.156 16.393 17.378 18.363 19.348 ...
            20.333 20.350 20.350 20.350 20.350 20.350 20.350 20.350 20.350 20.350 20.350 20.350 20.350 20.870 23.354 25.838 ...
            28.322 30.805 30.926 30.926 30.926 30.926 30.926 30.926 30.926 30.926 30.926 30.926 30.926 30.926 30.645 29.060 ...
            27.476 25.891 24.307 24.179 24.179 24.179 24.179 24.179 24.179 24.179 24.179 24.179 24.179 24.179 24.179 23.873 ...
            21.775 19.676 17.578 15.479 15.244 15.244 15.244 15.244 15.244 15.244 15.244 15.244 15.244 15.244 15.244 15.244 ...
            15.156 14.385 13.614 12.844 12.073 11.962 11.962 11.962 11.962 11.962 11.962 11.962 11.962 11.962 11.962 11.962 ...
            11.962 11.774 9.505 7.235 4.965 2.695 2.298 2.298 2.298 2.298 2.298 2.298 2.298 2.298 2.298 2.298 ...
            2.298 2.298 2.298 2.298 2.298 2.298 2.298 2.298 2.298 2.298 2.298 2.298 2.298 2.298 2.298 2.298 ...
            2.298 2.298 2.298 2.264 0.551 -1.162 -2.875 -4.588 -4.996 -4.996 -4.996 -4.996 -4.996 -4.996 -4.996 -4.996 ...
            -4.996 -4.996 -4.996 -4.996 -4.996 -6.139 -7.295 -8.451 -9.607 -9.920 -9.920 -9.920 -9.920 -9.920 -9.920 -9.920 ...
            -9.920 -9.920 -9.920 -9.920 -9.920 -9.920 -9.674 -9.417 -9.160 -8.903 -8.826 -8.826 -8.826 -8.826 -8.826 -8.826 ...
            -8.826 -8.826 -8.826 -8.826 -8.826 -8.826 -8.826 -8.390 -7.919 -7.448 -6.977 -6.820 -6.820 -6.820 -6.820 -6.820 ...
            -6.820 -6.820 -6.820 -6.820 -6.820 -6.820 -6.820 -6.820 -3.531 0.152 3.835 7.518 8.862 8.862 8.862 8.862 ...
            8.862 8.862 8.862 8.862 8.862 8.862 8.862 8.862 8.862 8.198 7.427 6.656 5.886 5.580 5.580 5.580 ...
            5.580 5.580 5.580 5.580 5.580 5.580 5.580 5.580 5.580 5.580 4.798 3.856 2.914 1.972 1.568 1.568 ...
            1.568 1.568 1.568 1.568 1.568 1.568 1.568 1.568 1.568 1.568 1.568 -1.303 -4.900 -8.497 -12.095 -13.749 ...
            -13.749 -13.749 -13.749 -13.749 -13.749 -13.749 -13.749 -13.749 -13.749 -13.749 -13.749 -13.749 -15.456 -17.683 -19.910 -22.137 ...
            -23.231 -23.231 -23.231 -23.231 -23.231 -23.231 -23.231 -23.231 -23.231 -23.231 -23.231 -23.231 -23.231 -23.609 -24.123 -24.637 ...
            -25.151 -25.419 -25.419 -25.419 -25.419 -25.419 -25.419 -25.419 -25.419 -25.419 -25.419 -25.419 -25.419 -25.419 -25.871 -26.513 ...
            -27.156 -27.798 -28.155 -28.155 -28.155 -28.155 -28.155 -28.155 -28.155 -28.155 -28.155 -28.155 -28.155 -28.155 -28.155 -26.774 ...
            -24.719 -22.663 -20.607 -19.402 -19.402 -19.402 -19.402 -19.402 -19.402 -19.402 -19.402 -19.402 -19.402 -19.402 -19.402 -19.402 ...
            -18.991 -18.348 -17.706 -17.064 -16.667 -16.667 -16.667 -16.667 -16.667 -16.667 -16.667 -16.667 -16.667 -16.667 -16.667 -16.667 ...
            -16.667 -13.879 -9.297 -4.715 -0.132 2.845 2.845 2.845 2.845 2.845 2.845 2.845 2.845 2.845 2.845 2.845 ...
            2.845 2.845 3.264 3.992 4.721 5.449 5.945 5.945 5.945 5.945 5.945 5.945 5.945 5.945 5.945 5.945 ...
            5.945 5.945 5.945 7.648 10.775 13.901 17.027 19.256 19.256 19.256 19.256 19.256 19.256 19.256 19.256 19.256 ...
            19.256 19.256 19.256 19.256 20.729 23.598 26.468 29.337 31.473 31.473 31.473 31.473 31.473 31.473 31.473 31.473 ...
            31.473 31.473 31.473 31.473 31.473 31.350 31.093 30.836 30.579 30.379 30.379 30.379 30.379 30.379 30.379 30.379 ...
            30.379 30.379 30.379 30.379 30.379 30.379 29.493 27.523 25.553 23.583 21.991 21.991 21.991 21.991 21.991 21.991 ...
            21.991 21.991 21.991 21.991 21.991 21.991 21.991 21.185 19.258 17.330 15.403 13.786 13.786 13.786 13.786 13.786 ...
            13.786 13.786 13.786 13.786 13.786 13.786 13.786 13.786 13.802 13.845 13.888 13.931 13.968 13.968 13.968 13.968 ...
            13.968 13.968 13.968 13.968 13.968 13.968 13.968 13.968 13.968 14.363 15.477 16.590 17.704 18.709 18.709 18.709 ...
            18.709 18.709 18.709 18.709 18.709 18.709 18.709 18.709 18.709 18.709 19.180 20.636 22.092 23.548 24.909 24.909 ...
            24.909 24.909 24.909 24.909 24.909 24.909 24.909 24.909 24.909 24.909 24.909 25.284 26.569 27.853 29.138 30.379 ...
            30.379 30.379 30.379 30.379 30.379 30.379 30.379 30.379 30.379 30.379 30.379 30.379 30.089 28.976 27.862 26.749 ...
            25.638 25.638 25.638 25.638 25.638 25.638 25.638 25.638 25.638 25.638 25.638 25.638 25.638 25.305 23.849 22.393 ...
            20.937 19.481 19.438 19.438 19.438 19.438 19.438 19.438 19.438 19.438 19.438 19.438 19.438 19.438 18.544 14.004 ...
            9.465 4.925 0.386 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.102 ...
            0.059 0.017 -0.026 -0.069 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 ...
            -0.474 -3.472 -6.470 -9.468 -12.465 -12.837 -12.837 -12.837 -12.837 -12.837 -12.837 -12.837 -12.837 -12.837 -12.837 -12.837 ...
            -12.837 -12.527 -9.486 -6.445 -3.405 -0.364 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 ...
            0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 ...
            0.109 0.109 0.109 0.254 3.980 7.706 11.432 15.158 15.974 15.974 15.974 15.974 15.974 15.974 15.974 15.974 ...
            15.974 15.974 15.974 15.974 15.988 18.001 20.014 22.027 24.040 24.544 24.544 24.544 24.544 24.544 24.544 24.544 ...
            24.544 24.544 24.544 24.544 24.544 24.544 24.878 25.221 25.564 25.906 26.003 26.003 26.003 26.003 26.003 26.003 ...
            26.003 26.003 26.003 26.003 26.003 26.003 26.003 26.609 27.252 27.894 28.537 28.738 28.738 28.738 28.738 28.738 ...
            28.738 28.738 28.738 28.738 28.738 28.738 28.738 28.738 27.761 26.691 25.620 24.549 24.179 24.179 24.179 24.179 ...
            24.179 24.179 24.179 24.179 24.179 24.179 24.179 24.179 24.179 23.086 21.844 20.602 19.360 18.891 18.891 18.891 ...
            18.891 18.891 18.891 18.891 18.891 18.891 18.891 18.891 18.891 18.891 17.037 14.853 12.668 10.484 9.592 9.592 ...
            9.592 9.592 9.592 9.592 9.592 9.592 9.592 9.592 9.592 9.592 9.592 8.471 7.101 5.730 4.360 3.756 ...
            3.756 3.756 3.756 3.756 3.756 3.756 3.756 3.756 3.756 3.756 3.756 3.756 4.295 4.980 5.665 6.351 ...
            6.674 6.674 6.674 6.674 6.674 6.674 6.674 6.674 6.674 6.674 6.674 6.674 6.674 7.288 8.101 8.915 ...
            9.729 10.139 10.139 10.139 10.139 10.139 10.139 10.139 10.139 10.139 10.139 10.139 10.139 10.139 11.098 12.426 ...
            13.753 15.081 15.791 15.791 15.791 15.791 15.791 15.791 15.791 15.791 15.791 15.791 15.791 15.791 15.791 16.827 ...
            18.326 19.825 21.324 22.174 22.174 22.174 22.174 22.174 22.174 22.174 22.174 22.174 22.174 22.174 22.174 22.174 ...
            22.258 22.387 22.515 22.644 22.721 22.721 22.721 22.721 22.721 22.721 22.721 22.721 22.721 22.721 22.721 22.721 ...
            22.721 21.941 20.699 19.457 18.215 17.433 17.433 17.433 17.433 17.433 17.433 17.433 17.433 17.433 17.433 17.433 ...
            17.433 17.433 14.880 10.597 6.314 2.032 -0.802 -0.802 -0.802 -0.802 -0.802 -0.802 -0.802 -0.802 -0.802 -0.802 ...
            -0.802 -0.802 -0.802 -0.827 -0.869 -0.912 -0.955 -0.985 -0.985 -0.985 -0.985 -0.985 -0.985 -0.985 -0.985 -0.985 ...
            -0.985 -0.985 -0.985 -0.985 -0.597 0.131 0.859 1.587 2.115 2.115 2.115 2.115 2.115 2.115 2.115 2.115 ...
            2.115 2.115 2.115 2.115 2.115 2.115 2.115 2.115 2.115 2.115 2.115 2.115 2.115 2.115 2.115 2.115 ...
            2.115 2.115 2.115 2.115 2.115 2.115 2.859 4.444 6.028 7.613 8.862 8.862 8.862 8.862 8.862 8.862 ...
            8.862 8.862 8.862 8.862 8.862 8.862 8.862 9.200 9.971 10.741 11.512 12.144 12.144 12.144 12.144 12.144 ...
            12.144 12.144 12.144 12.144 12.144 12.144 12.144 12.144 12.405 13.048 13.690 14.333 14.880 14.880 14.880 14.880 ...
            14.880 14.880 14.880 14.880 14.880 14.880 14.880 14.880 14.880 14.912 14.997 15.083 15.169 15.244 15.244 15.244 ...
            15.244 15.244 15.244 15.244 15.244 15.244 15.244 15.244 15.244 15.244 15.465 16.107 16.750 17.392 17.980 17.980 ...
            17.980 17.980 17.980 17.980 17.980 17.980 17.980 17.980 17.980 17.980 17.980 17.900 17.643 17.386 17.129 16.885 ...
            16.885 16.885 16.885 16.885 16.885 16.885 16.885 16.885 16.885 16.885 16.885 16.885 16.874 16.831 16.788 16.745 ...
            16.703 16.703 16.703 16.703 16.703 16.703 16.703 16.703 16.703 16.703 16.703 16.703 16.703 15.630 11.304 6.979 ...
            2.653 -1.672 -1.714 -1.714 -1.714 -1.714 -1.714 -1.714 -1.714 -1.714 -1.714 -1.714 -1.714 -1.714 -2.122 -4.006 ...
            -5.891 -7.775 -9.659 -9.737 -9.737 -9.737 -9.737 -9.737 -9.737 -9.737 -9.737 -9.737 -9.737 -9.737 -9.737 -9.246 ...
            -6.591 -3.936 -1.281 1.374 1.568 1.568 1.568 1.568 1.568 1.568 1.568 1.568 1.568 1.568 1.568 1.568 ...
            1.811 3.396 4.980 6.565 8.149 8.315 8.315 8.315 8.315 8.315 8.315 8.315 8.315 8.315 8.315 8.315 ...
            8.315 8.680 11.678 14.675 17.673 20.671 21.080 21.080 21.080 21.080 21.080 21.080 21.080 21.080 21.080 21.080 ...
            21.080 21.080 21.160 22.060 22.959 23.858 24.758 24.909 24.909 24.909 24.909 24.909 24.909 24.909 24.909 24.909 ...
            24.909 24.909 24.909 24.859 24.002 23.146 22.289 21.433 21.262 21.262 21.262 21.262 21.262 21.262 21.262 21.262 ...
            21.262 21.262 21.262 21.262 21.218 19.591 17.964 16.336 14.709 14.333 14.333 14.333 14.333 14.333 14.333 14.333 ...
            14.333 14.333 14.333 14.333 14.333 14.333 12.926 11.513 10.100 8.686 8.315 8.315 8.315 8.315 8.315 8.315 ...
            8.315 8.315 8.315 8.315 8.315 8.315 8.315 7.036 5.708 4.381 3.053 2.662 2.662 2.662 2.662 2.662 ...
            2.662 2.662 2.662 2.662 2.662 2.662 2.662 2.662 2.902 3.159 3.416 3.673 3.756 3.756 3.756 3.756 ...
            3.756 3.756 3.756 3.756 3.756 3.756 3.756 3.756 3.756 3.911 4.082 4.253 4.425 4.486 4.486 4.486 ...
            4.486 4.486 4.486 4.486 4.486 4.486 4.486 4.486 4.486 4.486 5.081 5.766 6.451 7.137 7.403 7.403 ...
            7.403 7.403 7.403 7.403 7.403 7.403 7.403 7.403 7.403 7.403 7.403 7.726 8.111 8.497 8.882 9.044 ...
            9.044 9.044 9.044 9.044 9.044 9.044 9.044 9.044 9.044 9.044 9.044 9.044 9.044 9.044 9.044 9.044 ...
            9.044 9.044 9.044 9.044 9.044 9.044 9.044 9.044 9.044 9.044 9.044 9.044 9.044 7.620 5.778 3.937 ...
            2.095 1.204 1.204 1.204 1.204 1.204 1.204 1.204 1.204 1.204 1.204 1.204 1.204 1.204 1.172 1.129 ...
            1.086 1.043 1.021 1.021 1.021 1.021 1.021 1.021 1.021 1.021 1.021 1.021 1.021 1.021 1.021 -0.287 ...
            -2.129 -3.970 -5.812 -6.820 -6.820 -6.820 -6.820 -6.820 -6.820 -6.820 -6.820 -6.820 -6.820 -6.820 -6.820 -6.820 ...
            -8.041 -9.840 -11.638 -13.437 -14.478 -14.478 -14.478 -14.478 -14.478 -14.478 -14.478 -14.478 -14.478 -14.478 -14.478 -14.478 ...
            -14.478 -15.033 -15.889 -16.746 -17.602 -18.125 -18.125 -18.125 -18.125 -18.125 -18.125 -18.125 -18.125 -18.125 -18.125 -18.125 ...
            -18.125 -18.125 -18.943 -20.270 -21.598 -22.925 -23.778 -23.778 -23.778 -23.778 -23.778 -23.778 -23.778 -23.778 -23.778 -23.778 ...
            -23.778 -23.778 -23.778 -24.328 -25.271 -26.213 -27.155 -27.790 -27.790 -27.790 -27.790 -27.790 -27.790 -27.790 -27.790 -27.790 ...
            -27.790 -27.790 -27.790 -27.790 -28.192 -28.920 -29.648 -30.376 -30.890 -30.890 -30.890 -30.890 -30.890 -30.890 -30.890 -30.890 ...
            -30.890 -30.890 -30.890 -30.890 -30.890 -31.470 -32.583 -33.697 -34.810 -35.631 -35.631 -35.631 -35.631 -35.631 -35.631 -35.631 ...
            -35.631 -35.631 -35.631 -35.631 -35.631 -35.631 -35.840 -36.269 -36.697 -37.125 -37.454 -37.454 -37.454 -37.454 -37.454 -37.454 ...
            -37.454 -37.454 -37.454 -37.454 -37.454 -37.454 -37.454 -36.788 -35.332 -33.876 -32.420 -31.255 -31.255 -31.255 -31.255 -31.255 ...
            -31.255 -31.255 -31.255 -31.255 -31.255 -31.255 -31.255 -31.255 -30.653 -29.240 -27.826 -26.413 -25.237 -25.237 -25.237 -25.237 ...
            -25.237 -25.237 -25.237 -25.237 -25.237 -25.237 -25.237 -25.237 -25.237 -22.823 -16.699 -10.575 -4.451 0.839 0.839 0.839 ...
            0.839 0.839 0.839 0.839 0.839 0.839 0.839 0.839 0.839 0.839 1.134 1.947 2.761 3.575 4.303 4.303 ...
            4.303 4.303 4.303 4.303 4.303 4.303 4.303 4.303 4.303 4.303 4.303 6.302 12.340 18.378 24.417 30.015 ...
            30.015 30.015 30.015 30.015 30.015 30.015 30.015 30.015 30.015 30.015 30.015 30.015 31.155 34.967 38.778 42.590 ...
            46.244 46.244 46.244 46.244 46.244 46.244 46.244 46.244 46.244 46.244 46.244 46.244 46.244 46.817 48.958 51.099 ...
            53.241 55.361 55.361 55.361 55.361 55.361 55.361 55.361 55.361 55.361 55.361 55.361 55.361 55.361 55.088 53.932 ...
            52.776 51.619 50.463 50.438 50.438 50.438 50.438 50.438 50.438 50.438 50.438 50.438 50.438 50.438 50.438 49.912 ...
            47.343 44.773 42.204 39.634 39.497 39.497 39.497 39.497 39.497 39.497 39.497 39.497 39.497 39.497 39.497 39.497 ...
            39.053 36.483 33.914 31.344 28.775 28.556 28.556 28.556 28.556 28.556 28.556 28.556 28.556 28.556 28.556 28.556 ...
            28.556 28.242 26.015 23.788 21.561 19.334 19.074 19.074 19.074 19.074 19.074 19.074 19.074 19.074 19.074 19.074 ...
            19.074 19.074 18.806 16.365 13.924 11.483 9.042 8.680 8.680 8.680 8.680 8.680 8.680 8.680 8.680 8.680 ...
            8.680 8.680 8.680 8.563 7.064 5.565 4.066 2.567 2.298 2.298 2.298 2.298 2.298 2.298 2.298 2.298 ...
            2.298 2.298 2.298 2.298 2.280 1.894 1.509 1.123 0.738 0.656 0.656 0.656 0.656 0.656 0.656 0.656 ...
            0.656 0.656 0.656 0.656 0.656 0.658 0.787 0.915 1.044 1.172 1.204 1.204 1.204 1.204 1.204 1.204 ...
            1.204 1.204 1.204 1.204 1.204 1.204 1.204 0.488 -0.240 -0.968 -1.696 -1.896 -1.896 -1.896 -1.896 -1.896 ...
            -1.896 -1.896 -1.896 -1.896 -1.896 -1.896 -1.896 -1.896 -3.445 -5.072 -6.699 -8.327 -8.826 -8.826 -8.826 -8.826 ...
            -8.826 -8.826 -8.826 -8.826 -8.826 -8.826 -8.826 -8.826 -8.826 -10.125 -11.539 -12.952 -14.365 -14.843 -14.843 -14.843 ...
            -14.843 -14.843 -14.843 -14.843 -14.843 -14.843 -14.843 -14.843 -14.843 -14.843 -16.593 -18.563 -20.533 -22.503 -23.231 -23.231 ...
            -23.231 -23.231 -23.231 -23.231 -23.231 -23.231 -23.231 -23.231 -23.231 -23.231 -23.231 -18.060 -12.021 -5.983 0.056 2.480 ...
            2.480 2.480 2.480 2.480 2.480 2.480 2.480 2.480 2.480 2.480 2.480 2.480 2.480 2.480 2.480 2.480 ...
            2.480 2.480 2.480 2.480 2.480 2.480 2.480 2.480 2.480 2.480 2.480 2.480 2.480 4.960 8.086 11.212 ...
            14.339 15.791 15.791 15.791 15.791 15.791 15.791 15.791 15.791 15.791 15.791 15.791 15.791 15.791 15.661 15.490 ...
            15.318 15.147 15.062 15.062 15.062 15.062 15.062 15.062 15.062 15.062 15.062 15.062 15.062 15.062 15.062 13.843 ...
            12.173 10.502 8.832 7.950 7.950 7.950 7.950 7.950 7.950 7.950 7.950 7.950 7.950 7.950 7.950 7.950 ...
            8.190 8.532 8.875 9.217 9.409 9.409 9.409 9.409 9.409 9.409 9.409 9.409 9.409 9.409 9.409 9.409 ...
            9.409 10.723 12.693 14.662 16.632 17.797 17.797 17.797 17.797 17.797 17.797 17.797 17.797 17.797 17.797 17.797 ...
            17.797 17.797 18.504 19.618 20.731 21.845 22.538 22.538 22.538 22.538 22.538 22.538 22.538 22.538 22.538 22.538 ...
            22.538 22.538 22.538 23.133 24.118 25.103 26.088 26.732 26.732 26.732 26.732 26.732 26.732 26.732 26.732 26.732 ...
            26.732 26.732 26.732 26.732 26.659 26.530 26.402 26.273 26.185 26.185 26.185 26.185 26.185 26.185 26.185 26.185 ...
            26.185 26.185 26.185 26.185 26.185 25.838 25.196 24.554 23.911 23.450 23.450 23.450 23.450 23.450 23.450 23.450 ...
            23.450 23.450 23.450 23.450 23.450 23.450 23.232 22.804 22.376 21.947 21.627 21.627 21.627 21.627 21.627 21.627 ...
            21.627 21.627 21.627 21.627 21.627 21.627 21.627 21.443 21.057 20.672 20.286 19.985 19.985 19.985 19.985 19.985 ...
            19.985 19.985 19.985 19.985 19.985 19.985 19.985 19.985 18.346 14.662 10.979 7.296 4.303 4.303 4.303 4.303 ...
            4.303 4.303 4.303 4.303 4.303 4.303 4.303 4.303 4.303 4.020 3.335 2.650 1.964 1.386 1.386 1.386 ...
            1.386 1.386 1.386 1.386 1.386 1.386 1.386 1.386 1.386 1.386 1.075 0.261 -0.552 -1.366 -2.079 -2.079 ...
            -2.079 -2.079 -2.079 -2.079 -2.079 -2.079 -2.079 -2.079 -2.079 -2.079 -2.079 -3.444 -7.341 -11.239 -15.136 -18.673 ...
            -18.673 -18.673 -18.673 -18.673 -18.673 -18.673 -18.673 -18.673 -18.673 -18.673 -18.673 -18.673 -19.628 -22.626 -25.624 -28.621 ...
            -31.437 -31.437 -31.437 -31.437 -31.437 -31.437 -31.437 -31.437 -31.437 -31.437 -31.437 -31.437 -31.437 -31.621 -32.264 -32.906 ...
            -33.549 -34.172 -34.172 -34.172 -34.172 -34.172 -34.172 -34.172 -34.172 -34.172 -34.172 -34.172 -34.172 -34.172 -34.347 -35.032 ...
            -35.718 -36.403 -37.088 -37.090 -37.090 -37.090 -37.090 -37.090 -37.090 -37.090 -37.090 -37.090 -37.090 -37.090 -37.090 -36.946 ...
            -36.304 -35.661 -35.019 -34.376 -34.354 -34.354 -34.354 -34.354 -34.354 -34.354 -34.354 -34.354 -34.354 -34.354 -34.354 -34.354 ...
            -33.935 -31.751 -29.566 -27.382 -25.198 -25.055 -25.055 -25.055 -25.055 -25.055 -25.055 -25.055 -25.055 -25.055 -25.055 -25.055 ...
            -25.055 -24.690 -22.420 -20.151 -17.881 -15.611 -15.390 -15.390 -15.390 -15.390 -15.390 -15.390 -15.390 -15.390 -15.390 -15.390 ...
            -15.390 -15.390 -15.169 -13.456 -11.743 -10.030 -8.317 -8.096 -8.096 -8.096 -8.096 -8.096 -8.096 -8.096 -8.096 -8.096 ...
            -8.096 -8.096 -8.096 -8.030 -7.344 -6.659 -5.974 -5.289 -5.179 -5.179 -5.179 -5.179 -5.179 -5.179 -5.179 -5.179 ...
            -5.179 -5.179 -5.179 -5.179 -5.100 -3.901 -2.702 -1.503 -0.303 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 ...
            -0.073 -0.073 -0.073 -0.073 -0.073 -0.071 -0.029 0.014 0.057 0.100 0.109 0.109 0.109 0.109 0.109 0.109 ...
            0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 ...
            0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.026 -0.059 -0.145 -0.231 -0.255 -0.255 -0.255 -0.255 ...
            -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.253 -0.250 -0.248 -0.245 -0.243 -0.240 -0.238 ...
            -0.235 -0.233 -0.230 -0.228 -0.225 -0.223 -0.220 -0.218 -0.215 -0.213 -0.210 -0.208 -0.205 -0.203 -0.200 -0.198 ...
            -0.195 -0.192 -0.190 -0.187 -0.185 -0.182 -0.180 -0.177 -0.175 -0.172 -0.170 -0.167 -0.165 -0.162 -0.160 -0.157 ...
            -0.155 -0.152 -0.150 -0.147 -0.145 -0.142 -0.140 -0.137 -0.135 -0.132 -0.129 -0.127 -0.124 -0.122 -0.119 -0.117 ...
            -0.114 -0.112 -0.109 -0.107 -0.104 -0.102 -0.099 -0.097 -0.094 -0.092 -0.089 -0.087 -0.084 -0.082 -0.079 -0.077 ...
            -0.074 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.039 0.003 ...
            0.046 0.089 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 ...
            0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 ...
            0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 ...
            0.109 0.051 -0.035 -0.121 -0.206 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 ...
            -0.255 -0.255 -0.087 0.170 0.427 0.684 0.941 1.198 1.455 1.712 1.969 2.225 2.482 2.739 2.996 3.253 ...
            3.510 3.767 4.024 4.281 4.538 4.795 5.052 5.215 5.215 5.215 5.215 5.215 5.215 5.215 5.215 5.215 ...
            5.215 5.215 5.215 5.215 6.507 8.691 10.875 13.059 14.515 14.515 14.515 14.515 14.515 14.515 14.515 14.515 ...
            14.515 14.515 14.515 14.515 14.515 15.713 17.855 19.996 22.137 23.632 23.632 23.632 23.632 23.632 23.632 23.632 ...
            23.632 23.632 23.632 23.632 23.632 23.632 26.414 31.681 36.949 42.216 46.061 46.061 46.061 46.061 46.061 46.061 ...
            46.061 46.061 46.061 46.061 46.061 46.061 46.061 45.997 45.869 45.741 45.612 45.514 45.514 45.514 45.514 45.514 ...
            45.514 45.514 45.514 45.514 45.514 45.514 45.514 45.514 42.350 35.540 28.731 21.922 16.521 16.521 16.521 16.521 ...
            16.521 16.521 16.521 16.521 16.521 16.521 16.521 16.521 16.521 12.273 2.466 -7.341 -17.148 -25.237 -25.237 -25.237 ...
            -25.237 -25.237 -25.237 -25.237 -25.237 -25.237 -25.237 -25.237 -25.237 -25.237 -25.804 -27.218 -28.631 -30.044 -31.255 -31.255 ...
            -31.255 -31.255 -31.255 -31.255 -31.255 -31.255 -31.255 -31.255 -31.255 -31.255 -31.255 -32.031 -34.129 -36.228 -38.326 -40.190 ...
            -40.190 -40.190 -40.190 -40.190 -40.190 -40.190 -40.190 -40.190 -40.190 -40.190 -40.190 -40.190 -40.088 -39.788 -39.489 -39.189 ...
            -38.913 -38.913 -38.913 -38.913 -38.913 -38.913 -38.913 -38.913 -38.913 -38.913 -38.913 -38.913 -38.913 -38.782 -38.354 -37.925 ...
            -37.497 -37.090 -37.090 -37.090 -37.090 -37.090 -37.090 -37.090 -37.090 -37.090 -37.090 -37.090 -37.090 -37.090 -37.090 -37.090 ...
            -37.090 -37.090 -37.090 -37.090 -37.090 -37.090 -37.090 -37.090 -37.090 -37.090 -37.090 -37.090 -37.090 -37.090 -37.090 -36.933 ...
            -36.291 -35.649 -35.006 -34.364 -34.354 -34.354 -34.354 -34.354 -34.354 -34.354 -34.354 -34.354 -34.354 -34.354 -34.354 -34.354 ...
            -34.336 -34.251 -34.165 -34.079 -33.994 -33.990 -33.990 -33.990 -33.990 -33.990 -33.990 -33.990 -33.990 -33.990 -33.990 -33.990 ...
            -33.990 -33.874 -33.232 -32.589 -31.947 -31.305 -31.255 -31.255 -31.255 -31.255 -31.255 -31.255 -31.255 -31.255 -31.255 -31.255 ...
            -31.255 -31.255 -31.242 -31.156 -31.071 -30.985 -30.899 -30.890 -30.890 -30.890 -30.890 -30.890 -30.890 -30.890 -30.890 -30.890 ...
            -30.890 -30.890 -30.890 -30.890 -30.890 -30.890 -30.890 -30.890 -30.890 -30.890 -30.890 -30.890 -30.890 -30.890 -30.890 -30.890 ...
            -30.890 -30.890 -30.890 -30.890 -30.835 -30.193 -29.550 -28.908 -28.266 -28.155 -28.155 -28.155 -28.155 -28.155 -28.155 -28.155 ...
            -28.155 -28.155 -28.155 -28.155 -28.155 -28.150 -28.064 -27.979 -27.893 -27.807 -27.790 -27.790 -27.790 -27.790 -27.790 -27.790 ...
            -27.790 -27.790 -27.790 -27.790 -27.790 -27.790 -27.774 -27.046 -26.318 -25.590 -24.862 -24.690 -24.690 -24.690 -24.690 -24.690 ...
            -24.690 -24.690 -24.690 -24.690 -24.690 -24.690 -24.690 -24.690 -23.927 -23.156 -22.385 -21.614 -21.408 -21.408 -21.408 -21.408 ...
            -21.408 -21.408 -21.408 -21.408 -21.408 -21.408 -21.408 -21.408 -21.408 -19.848 -18.220 -16.593 -14.966 -14.478 -14.478 -14.478 ...
            -14.478 -14.478 -14.478 -14.478 -14.478 -14.478 -14.478 -14.478 -14.478 -14.478 -13.208 -11.838 -10.467 -9.097 -8.643 -8.643 ...
            -8.643 -8.643 -8.643 -8.643 -8.643 -8.643 -8.643 -8.643 -8.643 -8.643 -8.643 -7.455 -6.127 -4.799 -3.472 -2.991 ...
            -2.991 -2.991 -2.991 -2.991 -2.991 -2.991 -2.991 -2.991 -2.991 -2.991 -2.991 -2.991 -2.103 -1.075 -0.047 0.981 ...
            1.386 1.386 1.386 1.386 1.386 1.386 1.386 1.386 1.386 1.386 1.386 1.386 1.386 1.136 0.837 0.537 ...
            0.237 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 -2.907 -6.676 ...
            -10.445 -14.213 -15.937 -15.937 -15.937 -15.937 -15.937 -15.937 -15.937 -15.937 -15.937 -15.937 -15.937 -15.937 -15.937 -18.143 ...
            -21.013 -23.882 -26.751 -28.155 -28.155 -28.155 -28.155 -28.155 -28.155 -28.155 -28.155 -28.155 -28.155 -28.155 -28.155 -28.155 ...
            -28.186 -28.229 -28.272 -28.315 -28.337 -28.337 -28.337 -28.337 -28.337 -28.337 -28.337 -28.337 -28.337 -28.337 -28.337 -28.337 ...
            -28.337 -27.068 -25.269 -23.470 -21.672 -20.678 -20.678 -20.678 -20.678 -20.678 -20.678 -20.678 -20.678 -20.678 -20.678 -20.678 ...
            -20.678 -20.678 -19.120 -16.807 -14.495 -12.182 -10.832 -10.832 -10.832 -10.832 -10.832 -10.832 -10.832 -10.832 -10.832 -10.832 ...
            -10.832 -10.832 -10.832 -8.246 -4.220 -0.194 3.831 6.309 6.309 6.309 6.309 6.309 6.309 6.309 6.309 6.309 ...
            6.309 6.309 6.309 6.309 6.545 6.930 7.316 7.701 7.950 7.950 7.950 7.950 7.950 7.950 7.950 7.950 ...
            7.950 7.950 7.950 7.950 7.950 9.711 12.752 15.792 18.833 20.897 20.897 20.897 20.897 20.897 20.897 20.897 ...
            20.897 20.897 20.897 20.897 20.897 20.897 22.046 24.144 26.243 28.341 29.832 29.832 29.832 29.832 29.832 29.832 ...
            29.832 29.832 29.832 29.832 29.832 29.832 29.832 30.716 32.429 34.142 35.855 37.126 37.126 37.126 37.126 37.126 ...
            37.126 37.126 37.126 37.126 37.126 37.126 37.126 37.126 37.790 39.160 40.531 41.901 42.961 42.961 42.961 42.961 ...
            42.961 42.961 42.961 42.961 42.961 42.961 42.961 42.961 42.961 39.492 31.826 24.160 16.495 10.321 10.321 10.321 ...
            10.321 10.321 10.321 10.321 10.321 10.321 10.321 10.321 10.321 10.321 9.456 7.400 5.344 3.289 1.568 1.568 ...
            1.568 1.568 1.568 1.568 1.568 1.568 1.568 1.568 1.568 1.568 1.568 -0.332 -5.215 -10.097 -14.979 -19.220 ...
            -19.220 -19.220 -19.220 -19.220 -19.220 -19.220 -19.220 -19.220 -19.220 -19.220 -19.220 -19.220 -19.189 -19.103 -19.018 -18.932 ...
            -18.855 -18.855 -18.855 -18.855 -18.855 -18.855 -18.855 -18.855 -18.855 -18.855 -18.855 -18.855 -18.855 -18.254 -16.413 -14.571 ...
            -12.730 -11.014 -11.014 -11.014 -11.014 -11.014 -11.014 -11.014 -11.014 -11.014 -11.014 -11.014 -11.014 -11.014 -9.993 -6.524 ...
            -3.055 0.414 3.756 3.756 3.756 3.756 3.756 3.756 3.756 3.756 3.756 3.756 3.756 3.756 3.756 4.105 ...
            5.433 6.760 8.088 9.409 9.409 9.409 9.409 9.409 9.409 9.409 9.409 9.409 9.409 9.409 9.409 9.409 ...
            9.587 10.358 11.129 11.900 12.671 12.691 12.691 12.691 12.691 12.691 12.691 12.691 12.691 12.691 12.691 12.691 ...
            12.691 12.820 13.462 14.104 14.747 15.389 15.427 15.427 15.427 15.427 15.427 15.427 15.427 15.427 15.427 15.427 ...
            15.427 15.427 15.477 15.777 16.077 16.376 16.676 16.703 16.703 16.703 16.703 16.703 16.703 16.703 16.703 16.703 ...
            16.703 16.703 16.703 16.826 17.725 18.624 19.524 20.423 20.532 20.532 20.532 20.532 20.532 20.532 20.532 20.532 ...
            20.532 20.532 20.532 20.532 20.523 20.438 20.352 20.267 20.181 20.168 20.168 20.168 20.168 20.168 20.168 20.168 ...
            20.168 20.168 20.168 20.168 20.168 20.096 19.111 18.126 17.141 16.156 15.974 15.974 15.974 15.974 15.974 15.974 ...
            15.974 15.974 15.974 15.974 15.974 15.974 15.933 14.948 13.963 12.978 11.993 11.780 11.780 11.780 11.780 11.780 ...
            11.780 11.780 11.780 11.780 11.780 11.780 11.780 11.752 8.926 6.099 3.273 0.446 -0.255 -0.255 -0.255 -0.255 ...
            -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.130 -0.001 0.127 0.256 0.292 0.292 0.292 ...
            0.292 0.292 0.292 0.292 0.292 0.292 0.292 0.292 0.292 0.292 -3.235 -6.961 -10.686 -14.412 -15.573 -15.573 ...
            -15.573 -15.573 -15.573 -15.573 -15.573 -15.573 -15.573 -15.573 -15.573 -15.573 -15.573 -16.474 -17.459 -18.444 -19.429 -19.767 ...
            -19.767 -19.767 -19.767 -19.767 -19.767 -19.767 -19.767 -19.767 -19.767 -19.767 -19.767 -19.767 -21.544 -23.557 -25.570 -27.583 ...
            -28.337 -28.337 -28.337 -28.337 -28.337 -28.337 -28.337 -28.337 -28.337 -28.337 -28.337 -28.337 -28.337 -27.462 -26.434 -25.406 ...
            -24.378 -23.961 -23.961 -23.961 -23.961 -23.961 -23.961 -23.961 -23.961 -23.961 -23.961 -23.961 -23.961 -23.961 -22.275 -20.219 ...
            -18.164 -16.108 -15.208 -15.208 -15.208 -15.208 -15.208 -15.208 -15.208 -15.208 -15.208 -15.208 -15.208 -15.208 -15.208 -14.195 ...
            -12.910 -11.626 -10.341 -9.737 -9.737 -9.737 -9.737 -9.737 -9.737 -9.737 -9.737 -9.737 -9.737 -9.737 -9.737 -9.737 ...
            -9.024 -8.082 -7.140 -6.198 -5.726 -5.726 -5.726 -5.726 -5.726 -5.726 -5.726 -5.726 -5.726 -5.726 -5.726 -5.726 ...
            -5.726 -4.794 -3.509 -2.225 -0.940 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 ...
            -0.255 -0.255 -0.196 -0.110 -0.025 0.061 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 ...
            0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 ...
            0.109 0.109 0.109 0.109 0.082 0.040 -0.003 -0.046 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 ...
            -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 ...
            -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 ...
            -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 ...
            -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 ...
            -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 ...
            -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.054 -0.011 0.032 0.074 0.109 0.109 ...
            0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.470 1.352 2.234 3.117 3.999 ...
            4.881 5.763 6.646 7.528 8.410 9.292 10.174 11.057 11.939 12.821 13.703 14.585 15.468 16.350 17.232 18.114 ...
            18.891 18.891 18.891 18.891 18.891 18.891 18.891 18.891 18.891 18.891 18.891 18.891 18.891 19.616 21.715 23.813 ...
            25.912 27.826 27.826 27.826 27.826 27.826 27.826 27.826 27.826 27.826 27.826 27.826 27.826 27.826 28.875 32.215 ...
            35.556 38.896 42.050 42.050 42.050 42.050 42.050 42.050 42.050 42.050 42.050 42.050 42.050 42.050 42.050 43.017 ...
            46.443 49.869 53.295 56.637 56.637 56.637 56.637 56.637 56.637 56.637 56.637 56.637 56.637 56.637 56.637 56.637 ...
            56.069 53.799 51.529 49.259 46.990 46.973 46.973 46.973 46.973 46.973 46.973 46.973 46.973 46.973 46.973 46.973 ...
            46.973 45.369 38.046 30.723 23.400 16.076 15.791 15.791 15.791 15.791 15.791 15.791 15.791 15.791 15.791 15.791 ...
            15.791 15.791 14.451 7.300 0.148 -7.004 -14.156 -14.661 -14.661 -14.661 -14.661 -14.661 -14.661 -14.661 -14.661 -14.661 ...
            -14.661 -14.661 -14.661 -14.981 -17.037 -19.092 -21.148 -23.204 -23.414 -23.414 -23.414 -23.414 -23.414 -23.414 -23.414 -23.414 ...
            -23.414 -23.414 -23.414 -23.414 -23.557 -24.713 -25.870 -27.026 -28.182 -28.337 -28.337 -28.337 -28.337 -28.337 -28.337 -28.337 ...
            -28.337 -28.337 -28.337 -28.337 -28.337 -28.250 -27.308 -26.366 -25.423 -24.481 -24.325 -24.325 -24.325 -24.325 -24.325 -24.325 ...
            -24.325 -24.325 -24.325 -24.325 -24.325 -24.325 -24.304 -23.962 -23.619 -23.277 -22.934 -22.867 -22.867 -22.867 -22.867 -22.867 ...
            -22.867 -22.867 -22.867 -22.867 -22.867 -22.867 -22.867 -22.852 -22.338 -21.824 -21.310 -20.796 -20.678 -20.678 -20.678 -20.678 ...
            -20.678 -20.678 -20.678 -20.678 -20.678 -20.678 -20.678 -20.678 -20.678 -19.909 -19.138 -18.368 -17.597 -17.396 -17.396 -17.396 ...
            -17.396 -17.396 -17.396 -17.396 -17.396 -17.396 -17.396 -17.396 -17.396 -17.396 -16.734 -16.049 -15.364 -14.679 -14.478 -14.478 ...
            -14.478 -14.478 -14.478 -14.478 -14.478 -14.478 -14.478 -14.478 -14.478 -14.478 -14.478 -13.878 -13.236 -12.594 -11.951 -11.743 ...
            -11.743 -11.743 -11.743 -11.743 -11.743 -11.743 -11.743 -11.743 -11.743 -11.743 -11.743 -11.743 -11.009 -10.195 -9.381 -8.568 ...
            -8.279 -8.279 -8.279 -8.279 -8.279 -8.279 -8.279 -8.279 -8.279 -8.279 -8.279 -8.279 -8.279 -7.607 -6.836 -6.065 ...
            -5.295 -4.996 -4.996 -4.996 -4.996 -4.996 -4.996 -4.996 -4.996 -4.996 -4.996 -4.996 -4.996 -4.996 -4.536 -3.988 ...
            -3.440 -2.892 -2.344 -1.795 -1.247 -0.699 -0.151 0.397 0.946 1.494 2.042 2.590 3.138 3.686 4.235 4.783 ...
            5.331 5.879 6.427 6.674 6.674 6.674 6.674 6.674 6.674 6.674 6.674 6.674 6.674 6.674 6.674 6.674 ...
            8.303 10.401 12.500 14.598 15.609 15.609 15.609 15.609 15.609 15.609 15.609 15.609 15.609 15.609 15.609 15.609 ...
            15.609 17.969 21.138 24.307 27.476 29.103 29.103 29.103 29.103 29.103 29.103 29.103 29.103 29.103 29.103 29.103 ...
            29.103 29.103 29.958 31.157 32.356 33.555 34.209 34.209 34.209 34.209 34.209 34.209 34.209 34.209 34.209 34.209 ...
            34.209 34.209 34.209 32.750 30.609 28.467 26.326 25.091 25.091 25.091 25.091 25.091 25.091 25.091 25.091 25.091 ...
            25.091 25.091 25.091 25.091 23.283 20.499 17.715 14.932 13.239 13.239 13.239 13.239 13.239 13.239 13.239 13.239 ...
            13.239 13.239 13.239 13.239 13.239 12.868 12.268 11.669 11.069 10.686 10.686 10.686 10.686 10.686 10.686 10.686 ...
            10.686 10.686 10.686 10.686 10.686 10.686 11.916 14.015 16.113 18.212 19.621 19.621 19.621 19.621 19.621 19.621 ...
            19.621 19.621 19.621 19.621 19.621 19.621 19.621 21.212 24.082 26.951 29.820 31.838 31.838 31.838 31.838 31.838 ...
            31.838 31.838 31.838 31.838 31.838 31.838 31.838 31.838 32.376 33.404 34.431 35.459 36.214 36.214 36.214 36.214 ...
            36.214 36.214 36.214 36.214 36.214 36.214 36.214 36.214 36.214 35.772 34.873 33.974 33.074 32.385 32.385 32.385 ...
            32.385 32.385 32.385 32.385 32.385 32.385 32.385 32.385 32.385 32.385 31.991 31.135 30.278 29.422 28.738 28.738 ...
            28.738 28.738 28.738 28.738 28.738 28.738 28.738 28.738 28.738 28.738 28.738 27.491 24.579 21.667 18.755 16.338 ...
            16.338 16.338 16.338 16.338 16.338 16.338 16.338 16.338 16.338 16.338 16.338 16.338 14.844 11.075 7.306 3.538 ...
            0.292 0.292 0.292 0.292 0.292 0.292 0.292 0.292 0.292 0.292 0.292 0.292 0.292 0.307 0.350 0.393 ...
            0.436 0.474 0.474 0.474 0.474 0.474 0.474 0.474 0.474 0.474 0.474 0.474 0.474 0.474 0.089 -1.068 ...
            -2.224 -3.380 -4.449 -4.449 -4.449 -4.449 -4.449 -4.449 -4.449 -4.449 -4.449 -4.449 -4.449 -4.449 -4.449 -4.682 ...
            -5.453 -6.224 -6.994 -7.732 -7.732 -7.732 -7.732 -7.732 -7.732 -7.732 -7.732 -7.732 -7.732 -7.732 -7.732 -7.732 ...
            -7.847 -8.276 -8.704 -9.132 -9.555 -9.555 -9.555 -9.555 -9.555 -9.555 -9.555 -9.555 -9.555 -9.555 -9.555 -9.555 ...
            -9.555 -9.729 -10.457 -11.185 -11.913 -12.641 -12.655 -12.655 -12.655 -12.655 -12.655 -12.655 -12.655 -12.655 -12.655 -12.655 ...
            -12.655 -12.655 -12.717 -13.017 -13.317 -13.616 -13.916 -13.931 -13.931 -13.931 -13.931 -13.931 -13.931 -13.931 -13.931 -13.931 ...
            -13.931 -13.931 -13.931 -13.984 -14.284 -14.584 -14.883 -15.183 -15.208 -15.208 -15.208 -15.208 -15.208 -15.208 -15.208 -15.208 ...
            -15.208 -15.208 -15.208 -15.208 -14.673 -10.947 -7.221 -3.495 0.230 0.656 0.656 0.656 0.656 0.656 0.656 0.656 ...
            0.656 0.656 0.656 0.656 0.656 0.704 1.133 1.561 1.989 2.417 2.480 2.480 2.480 2.480 2.480 2.480 ...
            2.480 2.480 2.480 2.480 2.480 2.480 2.507 2.850 3.193 3.535 3.878 3.939 3.939 3.939 3.939 3.939 ...
            3.939 3.939 3.939 3.939 3.939 3.939 3.939 3.910 3.310 2.710 2.111 1.511 1.386 1.386 1.386 1.386 ...
            1.386 1.386 1.386 1.386 1.386 1.386 1.386 1.386 1.309 -3.187 -7.684 -12.181 -16.678 -17.761 -17.761 -17.761 ...
            -17.761 -17.761 -17.761 -17.761 -17.761 -17.761 -17.761 -17.761 -17.761 -17.761 -18.014 -18.271 -18.528 -18.785 -18.855 -18.855 ...
            -18.855 -18.855 -18.855 -18.855 -18.855 -18.855 -18.855 -18.855 -18.855 -18.855 -18.855 -17.507 -16.094 -14.680 -13.267 -12.837 ...
            -12.837 -12.837 -12.837 -12.837 -12.837 -12.837 -12.837 -12.837 -12.837 -12.837 -12.837 -12.837 -10.981 -8.968 -6.956 -4.943 ...
            -4.267 -4.267 -4.267 -4.267 -4.267 -4.267 -4.267 -4.267 -4.267 -4.267 -4.267 -4.267 -4.267 -4.191 -4.105 -4.019 ...
            -3.934 -3.902 -3.902 -3.902 -3.902 -3.902 -3.902 -3.902 -3.902 -3.902 -3.902 -3.902 -3.902 -3.902 -2.688 -1.275 ...
            0.138 1.551 2.115 2.115 2.115 2.115 2.115 2.115 2.115 2.115 2.115 2.115 2.115 2.115 2.115 2.292 ...
            2.507 2.721 2.935 3.027 3.027 3.027 3.027 3.027 3.027 3.027 3.027 3.027 3.027 3.027 3.027 3.027 ...
            3.572 4.257 4.943 5.628 5.945 5.945 5.945 5.945 5.945 5.945 5.945 5.945 5.945 5.945 5.945 5.945 ...
            5.945 6.468 7.153 7.838 8.524 8.862 8.862 8.862 8.862 8.862 8.862 8.862 8.862 8.862 8.862 8.862 ...
            8.862 8.862 9.301 9.901 10.500 11.100 11.415 11.415 11.415 11.415 11.415 11.415 11.415 11.415 11.415 11.415 ...
            11.415 11.415 11.415 11.775 12.289 12.803 13.317 13.603 13.603 13.603 13.603 13.603 13.603 13.603 13.603 13.603 ...
            13.603 13.603 13.603 13.603 13.832 14.175 14.518 14.860 15.062 15.062 15.062 15.062 15.062 15.062 15.062 15.062 ...
            15.062 15.062 15.062 15.062 15.062 15.526 16.254 16.982 17.710 18.162 18.162 18.162 18.162 18.162 18.162 18.162 ...
            18.162 18.162 18.162 18.162 18.162 18.162 18.292 18.506 18.720 18.934 19.074 19.074 19.074 19.074 19.074 19.074 ...
            19.074 19.074 19.074 19.074 19.074 19.074 19.074 19.418 20.018 20.617 21.217 21.627 21.627 21.627 21.627 21.627 ...
            21.627 21.627 21.627 21.627 21.627 21.627 21.627 21.627 21.975 22.617 23.260 23.902 24.362 24.362 24.362 24.362 ...
            24.362 24.362 24.362 24.362 24.362 24.362 24.362 24.362 24.362 21.342 15.432 9.522 3.612 -0.802 -0.802 -0.802 ...
            -0.802 -0.802 -0.802 -0.802 -0.802 -0.802 -0.802 -0.802 -0.802 -0.802 -0.802 -0.802 -0.802 -0.802 -0.802 -0.802 ...
            -0.802 -0.802 -0.802 -0.802 -0.802 -0.802 -0.802 -0.802 -0.802 -0.802 -0.802 -4.541 -12.892 -21.243 -29.594 -36.360 ...
            -36.360 -36.360 -36.360 -36.360 -36.360 -36.360 -36.360 -36.360 -36.360 -36.360 -36.360 -36.360 -37.590 -40.545 -43.500 -46.455 ...
            -48.942 -48.942 -48.942 -48.942 -48.942 -48.942 -48.942 -48.942 -48.942 -48.942 -48.942 -48.942 -48.942 -48.728 -48.172 -47.615 ...
            -47.058 -46.572 -46.572 -46.572 -46.572 -46.572 -46.572 -46.572 -46.572 -46.572 -46.572 -46.572 -46.572 -46.572 -45.907 -44.023 ...
            -42.138 -40.254 -38.549 -38.549 -38.549 -38.549 -38.549 -38.549 -38.549 -38.549 -38.549 -38.549 -38.549 -38.549 -38.549 -35.550 ...
            -26.214 -16.878 -7.542 1.204 1.204 1.204 1.204 1.204 1.204 1.204 1.204 1.204 1.204 1.204 1.204 1.204 ...
            1.253 1.424 1.596 1.767 1.933 1.933 1.933 1.933 1.933 1.933 1.933 1.933 1.933 1.933 1.933 1.933 ...
            1.933 4.274 13.354 22.433 31.512 40.591 40.591 40.591 40.591 40.591 40.591 40.591 40.591 40.591 40.591 40.591 ...
            40.591 40.591 41.056 43.112 45.167 47.223 49.279 49.344 49.344 49.344 49.344 49.344 49.344 49.344 49.344 49.344 ...
            49.344 49.344 49.344 48.943 46.888 44.832 42.776 40.721 40.591 40.591 40.591 40.591 40.591 40.591 40.591 40.591 ...
            40.591 40.591 40.591 40.591 39.781 34.813 29.845 24.878 19.910 19.438 19.438 19.438 19.438 19.438 19.438 19.438 ...
            19.438 19.438 19.438 19.438 19.438 18.848 14.351 9.854 5.357 0.861 0.292 0.292 0.292 0.292 0.292 0.292 ...
            0.292 0.292 0.292 0.292 0.292 0.292 0.270 0.056 -0.158 -0.372 -0.586 -0.620 -0.620 -0.620 -0.620 -0.620 ...
            -0.620 -0.620 -0.620 -0.620 -0.620 -0.620 -0.620 -0.579 0.020 0.620 1.220 1.819 1.933 1.933 1.933 1.933 ...
            1.933 1.933 1.933 1.933 1.933 1.933 1.933 1.933 1.866 0.024 -1.817 -3.659 -5.500 -5.908 -5.908 -5.908 ...
            -5.908 -5.908 -5.908 -5.908 -5.908 -5.908 -5.908 -5.908 -5.908 -5.913 -6.855 -7.797 -8.739 -9.681 -9.920 -9.920 ...
            -9.920 -9.920 -9.920 -9.920 -9.920 -9.920 -9.920 -9.920 -9.920 -9.920 -9.920 -12.045 -14.230 -16.414 -18.598 -19.220 ...
            -19.220 -19.220 -19.220 -19.220 -19.220 -19.220 -19.220 -19.220 -19.220 -19.220 -19.220 -19.220 -19.986 -20.799 -21.613 -22.427 ...
            -22.684 -22.684 -22.684 -22.684 -22.684 -22.684 -22.684 -22.684 -22.684 -22.684 -22.684 -22.684 -22.684 -22.061 -21.375 -20.690 ...
            -20.005 -19.767 -19.767 -19.767 -19.767 -19.767 -19.767 -19.767 -19.767 -19.767 -19.767 -19.767 -19.767 -19.767 -15.704 -11.079 ...
            -6.454 -1.828 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 1.559 ...
            3.486 5.413 7.340 8.133 8.133 8.133 8.133 8.133 8.133 8.133 8.133 8.133 8.133 8.133 8.133 8.133 ...
            10.122 12.564 15.005 17.446 18.527 18.527 18.527 18.527 18.527 18.527 18.527 18.527 18.527 18.527 18.527 18.527 ...
            18.527 19.701 21.200 22.699 24.198 24.909 24.909 24.909 24.909 24.909 24.909 24.909 24.909 24.909 24.909 24.909 ...
            24.909 24.909 20.337 14.255 8.174 2.093 -0.985 -0.985 -0.985 -0.985 -0.985 -0.985 -0.985 -0.985 -0.985 -0.985 ...
            -0.985 -0.985 -0.985 -0.954 -0.911 -0.868 -0.825 -0.802 -0.802 -0.802 -0.802 -0.802 -0.802 -0.802 -0.802 -0.802 ...
            -0.802 -0.802 -0.802 -0.802 -7.408 -17.001 -26.594 -36.187 -41.648 -41.648 -41.648 -41.648 -41.648 -41.648 -41.648 -41.648 ...
            -41.648 -41.648 -41.648 -41.648 -41.648 -42.296 -43.281 -44.265 -45.250 -45.842 -45.842 -45.842 -45.842 -45.842 -45.842 -45.842 ...
            -45.842 -45.842 -45.842 -45.842 -45.842 -45.842 -43.486 -39.717 -35.949 -32.180 -29.796 -29.796 -29.796 -29.796 -29.796 -29.796 ...
            -29.796 -29.796 -29.796 -29.796 -29.796 -29.796 -29.796 -27.635 -23.994 -20.354 -16.714 -14.296 -14.296 -14.296 -14.296 -14.296 ...
            -14.296 -14.296 -14.296 -14.296 -14.296 -14.296 -14.296 -14.296 -13.454 -11.955 -10.456 -8.957 -7.914 -7.914 -7.914 -7.914 ...
            -7.914 -7.914 -7.914 -7.914 -7.914 -7.914 -7.914 -7.914 -7.914 -6.960 -5.161 -3.363 -1.564 -0.255 -0.255 -0.255 ...
            -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.255 -0.213 -0.127 -0.041 0.044 0.109 0.109 ...
            0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.089 0.047 0.004 -0.039 -0.073 ...
            -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.073 -0.054 -0.011 0.031 0.074 ...
            0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.109 0.110 0.112 0.114 ...
            0.116 0.118 0.120 0.122 0.125 0.127 0.129 0.131 0.133 0.135 0.137 0.139 0.141 0.143 0.145 0.147 ...
            0.149 0.151 0.153 0.155 0.157 0.159 0.161 0.163 0.165 0.167 0.169 0.171 0.173 0.175 0.178 0.180 ...
            0.182 0.184 0.186 0.188 0.190 0.192 0.194 0.196 0.198 0.200 0.202 0.204 0.206 0.208 0.210 0.212 ...
            0.214 0.216 0.218 0.220 0.222 0.224 0.226 0.229 0.231 0.233 0.235 0.237 0.239 0.241 0.243 0.245 ...
            0.247 0.249 0.251 0.253 0.255 0.257 0.259 0.261 0.263 0.265 0.267 0.269 0.271 0.273 0.275 0.277 ...
            0.279 0.282 0.284 0.286 0.288 0.290 0.292 0.292 0.292 0.292 0.292 0.292 0.292 0.292 0.292 0.292 ...
            0.292 0.292 0.292 0.466 1.280 2.093 2.907 3.721 3.756 3.756 3.756 3.756 3.756 3.756 3.756 3.756 ...
            3.756 3.756 3.756 3.756 4.006 5.377 6.747 8.118 9.488 9.592 9.592 9.592 9.592 9.592 9.592 9.592 ...
            9.592 9.592 9.592 9.592 9.592 9.837 11.464 13.092 14.719 16.347 16.521 16.521 16.521 16.521 16.521 16.521 ...
            16.521 16.521 16.521 16.521 16.521 16.521 16.694 18.150 19.607 21.063 22.519 22.721 22.721 22.721 22.721 22.721 ...
            22.721 22.721 22.721 22.721 22.721 22.721 22.721 22.867 24.537 26.207 27.878 29.548 29.832 29.832 29.832 29.832 ...
            29.832 29.832 29.832 29.832 29.832 29.832 29.832 29.832 29.950 32.048 34.147 36.245 38.344 38.767 38.767 38.767 ...
            38.767 38.767 38.767 38.767 38.767 38.767 38.767 38.767 38.767 38.787 39.601 40.415 41.228 42.042 42.232 42.232 ...
            42.232 42.232 42.232 42.232 42.232 42.232 42.232 42.232 42.232 42.232 42.232 41.382 40.525 39.669 38.812 38.585 ...
            38.585 38.585 38.585 38.585 38.585 38.585 38.585 38.585 38.585 38.585 38.585 38.585 37.021 35.394 33.766 32.139 ...
            31.656 31.656 31.656 31.656 31.656 31.656 31.656 31.656 31.656 31.656 31.656 31.656 31.656 30.382 29.012 27.641 ...
            26.271 25.821 25.821 25.821 25.821 25.821 25.821 25.821 25.821 25.821 25.821 25.821 25.821 25.821 23.821 21.594 ...
            19.367 17.140 16.338 16.338 16.338 16.338 16.338 16.338 16.338 16.338 16.338 16.338 16.338 16.338 16.338 15.671 ...
            14.900 14.129 13.358 13.056 13.056 13.056 13.056 13.056 13.056 13.056 13.056 13.056 13.056 13.056 13.056 13.056 ...
            9.268 4.728 0.189 -4.351 -6.273 -6.273 -6.273 -6.273 -6.273 -6.273 -6.273 -6.273 -6.273 -6.273 -6.273 -6.273 ...
            -6.273 -6.273 -6.273 -6.273 -6.273 -6.273 -6.273 -6.273 -6.273 -6.273 -6.273 -6.273 -6.273 -6.273 -6.273 -6.273 ...
            -6.273 -6.273 -7.561 -9.231 -10.901 -12.572 -13.384 -13.384 -13.384 -13.384 -13.384 -13.384 -13.384 -13.384 -13.384 -13.384 ...
            -13.384 -13.384 -13.384 -14.430 -15.843 -17.256 -18.669 -19.402 -19.402 -19.402 -19.402 -19.402 -19.402 -19.402 -19.402 -19.402 ...
            -19.402 -19.402 -19.402 -19.402 -18.947 -18.305 -17.662 -17.020 -16.667 -16.667 -16.667 -16.667 -16.667 -16.667 -16.667 -16.667 ...
            -16.667 -16.667 -16.667 -16.667 -16.667 -15.247 -13.149 -11.050 -8.952 -7.732 -7.732 -7.732 -7.732 -7.732 -7.732 -7.732 ...
            -7.732 -7.732 -7.732 -7.732 -7.732 -7.732 -7.732 -7.732 -7.732 -7.732 -7.732 -7.732 -7.732 -7.732 -7.732 -7.732 ...
            -7.732
        ];
        rp1CellCurrent_A = rp1CellCurrent_A(:);

        if numel(rp1CellCurrent_A) ~= 14001 || numel(rp1Time_s) ~= 14001
            error("ThermalPack:RP1Fig8ProfileLength", ...
                "Digitized RP1 Fig. 8 profile must contain 14001 samples at 0.1 s.");
        end
        if abs(rp1Time_s(end) - 1400) > 1e-9
            error("ThermalPack:RP1Fig8ProfileTime", ...
                "Digitized RP1 Fig. 8 profile must end at 1400 s.");
        end
        if round(state.P) ~= 6
            error("ThermalPack:RP1ParallelCount", ...
                "Bahiraei RP1 current conversion requires a 6P module.");
        end

        rp1ModuleCurrent_A = 6 * rp1CellCurrent_A;
        state.CustomCurrentProfile = [rp1Time_s rp1ModuleCurrent_A];
        state.LoadProfile = "Custom";
        state.LastValidLoadProfile = "Custom";
        loadProfileField.Value = "Custom";
        stopField.Value = 1400;
        state.Solver = "ode23t";

        %% COOLING — Bahiraei single-channel, t=1 mm, Re ~= 1100.
        coolingPlateField.Value = "Bottom Cooling Plate";
        state.CoolingPlateMode = "Bottom Cooling Plate";
        state.LastNonSerpentineCoolingMode = "Bottom Cooling Plate";
        coolingPlateTypeField.Value = "Parallel Channels";
        state.CoolingPlateType = "Parallel Channels";
        state.LastNonSerpentineCoolingPlateType = "Parallel Channels";

        flowAllocationField.Value = "Total Flow";
        state.FlowAllocationMode = "Total Flow";
        flowField.Value = 0.2706;
        topSplitField.Value = 50;
        topFlowField.Value = 0;
        bottomFlowField.Value = 0.2706;
        state.MassFlowRate_kg_s = 0.2706;
        state.TopFlowShare_pct = 50;
        state.TopMassFlowRate_kg_s = 0;
        state.BottomMassFlowRate_kg_s = 0.2706;

        tinField.Value = 20.0;
        ambientField.Value = 20.0;

        % Paper uses water at 293.15 K.
        state.CoolantFluid = "Water";
        state.CoolantConcentrationType = "Volume fraction";
        state.CoolantConcentration = 0.0;
        state.ReservoirPressureSpecification = "Atmospheric pressure";
        state.ReservoirPressure_Pa = 101325;
        state.AtmosphericPressure_Pa = 101325;
        state.CoolantPortDiameter_mm = 14.0;
        state.CoolantPortArea_m2 = pi*(14e-3)^2/4;

        % Provisional cell-to-plate path, 0.35 K/W area-scaled from the
        % older 110x9 mm base to the correct 80x9 mm base. The paper does
        % not provide this interface resistance or its physical makeup.
        coolantRField.Value = 0.35*(110/80);
        ambientRField.Value = 1e6;
        interCellHeatField.Value = "Enabled";
        interCellRField.Value = 4.37;
        interParallelRField.Value = 4.37;
        state.InterCellHeatTransfer = "Enabled";

        %% COOLING PLATE / CHANNEL
        state.PlateThickness_mm = 1.0;
        state.PlateConductivity_W_mK = 160.0;
        state.PlateDensity_kg_m3 = 2700.0;
        state.PlateSpecificHeat_J_kgK = 900.0;
        state.InitialPlateTemperature_C = 20.0;
        state.NumCoolantChannels = 1;
        state.ChannelHydraulicDiameter_mm = 11.8534;
        state.DistributorDiameter_mm = 13.0;
        state.ChannelRoughness_mm = 0.015;
        state.ChannelOrientation = "Channels along X axis";
        state.PlateConnectivity = "Single sided";

        % Point 7 — replace the prior 1x1 plate lump with one region per
        % cell footprint along the six-cell stack.
        state.PlatePartitionsX = 1;
        state.PlatePartitionsY = 6;
        state.Prismatic.PlatePartitionsX = 1;
        state.Prismatic.PlatePartitionsY = 6;

        refreshFlowAccountingUI();
        coolingModeChanged([],[]);
        interCellHeatChanged([],[]);
        saveActiveFormatGUIState("Prismatic");

        % Invalidate any result from the previously configured case so a
        % failed RP1 run can never be mistaken for a successful validation.
        state.LastKPI = [];
        state.LastTrace = [];
        state.LastCoolantTrace = struct();
        state.LastRuntime_s = NaN;
        cellNodalResultsButton.Enable = "off";
        simulationSummaryButton.Enable = "off";
        exportResultsButton.Enable = "off";
        state.NeedsRebuild = true;
    end

    function showRP1BahiraeiComparison()
        T = state.LastTrace;
        KPI = state.LastKPI;

        % Digitized battery-temperature points from Bahiraei et al.
        tPaper_s = (0:100:1400)';
        paperBatteryAvg_K = [ ...
            293.15 299.3 306.0 313.2 320.1 324.4 323.5 321.6 ...
            321.8 321.2 319.8 319.8 318.6 317.4 317.1]';
        paperBatteryAvg_C = paperBatteryAvg_K - 273.15;

        tTP = double(T.tCell(:));
        tpBatteryAvg_C = double(T.TmeanCellAverage_C(:));
        tpAtPaper_C = thermalPackInterpolateTrace(tTP,tpBatteryAvg_C,tPaper_s);
        validBatt = isfinite(tpAtPaper_C) & isfinite(paperBatteryAvg_C);
        battErr = tpAtPaper_C(validBatt)-paperBatteryAvg_C(validBatt);
        battRMSE_C = sqrt(mean(battErr.^2));
        battMAE_C = mean(abs(battErr));
        tpFinal_C = thermalPackLastFinite(tpBatteryAvg_C);
        paperFinal_C = paperBatteryAvg_C(end);

        % Fig. 14 t=1 mm single-channel scalar references, digitized from
        % the plotted three battery values (approximate).
        paperMaxCell_C = 343.5 - 273.15;

        scr = get(groot,"ScreenSize");
        W = min(1500,max(1100,scr(3)-80));
        H = min(760,max(620,scr(4)-140));
        X = scr(1)+max(20,(scr(3)-W)/2);
        Y = scr(2)+max(20,(scr(4)-H)/2);
        vf = uifigure( ...
            "Name","ThermalPack — Bottom-Cooling Validation — Bahiraei 2017", ...
            "Position",[X Y W H]);
        movegui(vf,"onscreen");

        vg = uigridlayout(vf,[2 2]);
        vg.RowHeight = {110,'1x'};
        vg.ColumnWidth = {'1x','1x'};
        vg.Padding = [12 12 12 12];
        vg.RowSpacing = 10;
        vg.ColumnSpacing = 10;

        summary = uilabel(vg, ...
            "Text",thermalPackFormatText( ...
                ["Case: Bahiraei 2017 | 6P × 1S Prismatic Module | 1400 s\n" ...
                 "Cooling: Bottom Water Cooling | 1 mm Plate | 20 °C Inlet | Re ≈ 1100\n" ...
                 "Battery Mean at 1400 s: ThermalPack %.2f °C | Research Paper %.2f °C\n" ...
                 "Temperature Error: RMSE %.2f °C | MAE %.2f °C"], ...
                tpFinal_C,paperFinal_C,battRMSE_C,battMAE_C), ...
            "FontWeight","bold","WordWrap","off");
        summary.Layout.Row = 1;
        summary.Layout.Column = [1 2];

        ax1 = uiaxes(vg);
        ax1.Layout.Row = 2; ax1.Layout.Column = 1;
        hold(ax1,"on");
        plot(ax1,tTP,tpBatteryAvg_C,"LineWidth",1.6, ...
            "DisplayName","ThermalPack");
        plot(ax1,tPaper_s,paperBatteryAvg_C,"o--","LineWidth",1.2, ...
            "DisplayName","Research Paper");
        hold(ax1,"off");
        grid(ax1,"on");
        xlabel(ax1,"Time (s)");
        ylabel(ax1,"Module-average battery temperature (°C)");
        title(ax1,"Battery Average Temperature");
        legend(ax1,"Location","best");

        ax3 = uiaxes(vg);
        ax3.Layout.Row = 2; ax3.Layout.Column = 2;
        valsMax = [KPI.PeakTmaxNodal_C paperMaxCell_C];
        bar(ax3,categorical(["ThermalPack","Research Paper"]),valsMax);
        grid(ax3,"on");
        ylabel(ax3,"Maximum temperature (°C)");
        title(ax3,"Maximum Cell Temperature — t = 1 mm");
    end

    function txt = rp1MetricText(value)
        if isfinite(value)
            txt = thermalPackFormatText("%.2f",value);
        else
            txt = "N/A";
        end
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
        optimizationRunButton.Enable = "off";
        designOptimizationRunButton.Enable = "off";
        exportResultsButton.Enable = "off";
        statusLabel.Text = "Running Simscape simulation...";
        drawnow;

        try
            cfg = currentSimulationConfig();
            [simIn,currentProfileDescription] = buildThermalSimulationInput( ...
                cfg,flowField.Value,tinField.Value);

            if state.FlowRateType == "Mass flow rate"
                state.MassFlowRate_kg_s = flowField.Value;
            else
                state.VolumetricFlowRate_m3_s = flowField.Value;
            end
            state.InitialCellTemperature_C = initialCellTempField.Value;

            t0 = tic;
            out = sim(simIn);
            runtime = toc(t0);

            [KPI,Trace] = extractUIResults(out,cfg);
            coolantTrace = extractCoolantTraceForExport(out);

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

            title(temperatureAxes,thermalPackFormatText( ...
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
            kpiTmaxValue.Text = thermalPackFormatText("%.2f °C",KPI.PeakTmaxNodal_C);
            kpiDeltaValue.Text = thermalPackFormatText("%.2f °C",KPI.MaxDeltaTNodal_C);
            kpiHotspotValue.Text = thermalPackFormatText("Cell %d / Node %d", ...
                KPI.WorstCell,KPI.WorstNode);
            kpiMarginValue.Text = thermalPackFormatText("%.2f °C",KPI.MinSafetyMargin_C);
            kpiStatusValue.Text = KPI.WorstStatus;

%% Cache completed results for the two Dashboard result windows.
            state.LastKPI = KPI;
            state.LastTrace = Trace;
            state.LastCoolantTrace = coolantTrace;
            state.LastRuntime_s = runtime;
            state.LastCurrentProfileDescription = currentProfileDescription;

            cellNodalResultsButton.Enable = "on";
            simulationSummaryButton.Enable = "on";
            exportResultsButton.Enable = "on";

%% Create/update the custom height-resolved nodal 3D thermal map.
            refreshThermalAnimation(out,Trace);

            statusLabel.Text = thermalPackFormatText("Simulation complete in %.2f s",runtime);

        catch ME
            statusLabel.Text = "Simulation failed";
            uialert(fig,getReport(ME,"extended","hyperlinks","off"), ...
                "ThermalPack Simulation Error");
        end

        runButton.Enable = "on";
        rebuildButton.Enable = "on";
        optimizationRunButton.Enable = "on";
        refreshDesignOptimizationControls();
    end
end


%% Fan 2019 generalized-validation parameter helper
function fan = thermalPackFanValidationECMData(ocvSOCBreakpoints)
% Return the current defensible MJ1 validation parameterization without
% changing any solver or heat-transfer equations in the generalized app.
%
% Absolute 25C 1RC anchor: SNU/Mendeley fresh MJ1, 2C 10 s pulse + relaxation.
% R0 temperature/SOC shape: Rizzello et al. 2021 Figure 5, normalized at 25C.
% R1/Tau1 remain temperature invariant (corrected Hybrid A).
% Entropic coefficient: approximate digitization of LeBel et al. 2025 Fig. 6.

soc = [ ...
    0.400 0.425 0.450 0.475 0.500 0.525 0.550 0.575 0.600 ...
    0.625 0.650 0.675 0.700 0.725 0.750 0.775 0.800];

r0_25 = [ ...
    0.0365050436 0.0365258170 0.0365216194 0.0365386966 ...
    0.0365427622 0.0365393164 0.0365548571 0.0365477490 ...
    0.0366169808 0.0366747648 0.0367417359 0.0368156039 ...
    0.0368426950 0.0369008067 0.0369411738 0.0370112420 ...
    0.0370887816];

r1_25 = [ ...
    0.0128058276 0.0133791068 0.0139304641 0.0144380126 ...
    0.0149444741 0.0156202265 0.0165504368 0.0172683430 ...
    0.0156804335 0.0141601110 0.0137045764 0.0136117875 ...
    0.0136441403 0.0136564994 0.0136136938 0.0135330395 ...
    0.0134405352];

tau1_25 = [ ...
    34.2033098 36.1379632 37.5864725 38.6718193 39.3333174 ...
    39.8923252 39.7870416 36.8853244 31.3539525 31.1822316 ...
    32.3077570 33.6720959 34.6433383 34.9450816 34.7976803 ...
    34.1290147 33.3290873];

% Digitized Rizzello Fig. 5 complete curves used for the relative R0 shape.
socFig5 = [ ...
    0.00 0.03 0.06 0.09 0.12 0.15 0.25 0.35 0.45 ...
    0.55 0.65 0.75 0.85 0.88 0.91 0.94 0.97];
r20 = [ ...
    0.0702 0.0704 0.0700 0.0694 0.0674 0.0635 0.0602 0.0593 0.0593 ...
    0.0591 0.0591 0.0592 0.0615 0.0622 0.0628 0.0639 0.0652];
r30 = [ ...
    0.0674 0.0669 0.0656 0.0632 0.0615 0.0593 0.0580 0.0577 0.0572 ...
    0.0572 0.0570 0.0572 0.0583 0.0585 0.0589 0.0593 0.0600];
r40 = [ ...
    0.0715 0.0689 0.0667 0.0648 0.0633 0.0624 0.0607 0.0600 0.0594 ...
    0.0593 0.0591 0.0593 0.0598 0.0600 0.0600 0.0604 0.0611];

r20q = interp1(socFig5,r20,soc,"linear");
r30q = interp1(socFig5,r30,soc,"linear");
r40q = interp1(socFig5,r40,soc,"linear");
r25q = 0.5*(r20q+r30q);
f20 = r20q./r25q;
f30 = r30q./r25q;
f40 = r40q./r25q;

tGrid_C = [20 25 30 40 50 60 70 80];
factor = [f20(:),ones(numel(soc),1),f30(:),f40(:),repmat(f40(:),1,4)];
R0 = r0_25(:).*factor;
R1 = repmat(r1_25(:),1,numel(tGrid_C));
Tau1 = repmat(tau1_25(:),1,numel(tGrid_C));

% LeBel et al. MJ1 entropic-coefficient digitization; interpolate onto the
% app's existing OCV SOC grid because Simscape requires that grid length.
entropySOC = 0:0.05:1.0;
entropy_mV_K = [ ...
    -0.500 -0.400 -0.375 -0.335 -0.035 ...
    -0.065 -0.045 -0.035  0.145  0.180 ...
     0.225  0.210  0.195  0.045  0.065 ...
     0.085  0.072  0.078  0.095  0.120 0.155];
ocvSOCBreakpoints = double(ocvSOCBreakpoints(:).');
entropic = interp1(entropySOC,entropy_mV_K,ocvSOCBreakpoints,"linear","extrap");

if any(~isfinite(R0),"all") || any(R0 <= 0,"all") || ...
        any(~isfinite(R1),"all") || any(R1 <= 0,"all") || ...
        any(~isfinite(Tau1),"all") || any(Tau1 <= 0,"all") || ...
        any(~isfinite(entropic))
    error("ThermalPack:FanValidationParameterMap", ...
        "Fan generalized-validation electrothermal parameter map is invalid.");
end

fan = struct;
fan.ResistanceSOC = soc;
fan.ResistanceTemperature_C = tGrid_C;
fan.R0Table_Ohm = R0;
fan.R1Table_Ohm = R1;
fan.Tau1Table_s = Tau1;
fan.EntropicCoefficient_mV_K = entropic;
fan.Source = ...
    "Mendeley 25C/2C 1RC anchor + corrected Rizzello Fig.5 R0(SOC,T) relative shape + LeBel entropy";
fan.Note = ...
    "SOC outside 0.40-0.80 uses the app Nearest extrapolation; R1/Tau1 are T-invariant; R0 relative factor is clamped above 40C.";
end


%% Operating optimization helpers — independent of the thermal model physics.
function row = optimizationEmptyRow()
row.CaseID = NaN;
row.CoolingArchitecture = "";
row.OperatingValue = NaN;
row.mdot_kg_s = NaN;
row.AirVelocity_m_s = NaN;
row.TopFlowShare_pct = NaN;
row.TopFlow_kg_s = NaN;
row.BottomFlow_kg_s = NaN;
row.Tin_C = NaN;
row.Tamb_C = NaN;
row.InitialSOC = NaN;
row.InitialCellTemperature_C = NaN;
row.InitialPlateTemperature_C = NaN;
row.ThermalLimit_C = NaN;
row.UniformityLimit_C = NaN;
row.PeakTmaxNodal_C = NaN;
row.MaxCellToCellDeltaT_C = NaN;
row.MaxWithinCellDeltaT_C = NaN;
row.MaxDeltaTNodal_C = NaN;
row.TemperatureMargin_C = NaN;
row.UniformityMargin_C = NaN;
row.WorstCell = NaN;
row.WorstNode = NaN;
row.EndTime_s = NaN;
row.Runtime_s = NaN;
row.Success = false;
row.Feasible = false;
row.Recommended = false;
row.ThermalRankingUnresolved = false;
row.CaseStatus = "Not run";
row.ErrorMessage = "";
end

function row = designOptimizationEmptyRow()
row.CaseID = NaN;
row.CoolingArchitecture = "";
row.Parameter1Name = "";
row.Parameter2Name = "";
row.Parameter3Name = "";
row.Parameter1Value = NaN;
row.Parameter2Value = NaN;
row.Parameter3Value = NaN;
row.InterCellGap_mm = NaN;
row.DuctWallClearance_mm = NaN;
row.PlateThickness_mm = NaN;
row.ContactHeightFraction = NaN;
row.CircumferenceFraction = NaN;
row.InterfaceRth_K_W = NaN;
row.OperatingValue = NaN;
row.mdot_kg_s = NaN;
row.AirVelocity_m_s = NaN;
row.TopFlowShare_pct = NaN;
row.Tin_C = NaN;
row.InitialSOC = NaN;
row.InitialCellTemperature_C = NaN;
row.InitialPlateTemperature_C = NaN;
row.ThermalLimit_C = NaN;
row.UniformityLimit_C = NaN;
row.PeakTmaxNodal_C = NaN;
row.MaxCellToCellDeltaT_C = NaN;
row.MaxWithinCellDeltaT_C = NaN;
row.MaxDeltaTNodal_C = NaN;
row.TemperatureMargin_C = NaN;
row.UniformityMargin_C = NaN;
row.WorstCell = NaN;
row.WorstNode = NaN;
row.EndTime_s = NaN;
row.Runtime_s = NaN;
row.Success = false;
row.Feasible = false;
row.Recommended = false;
row.CaseStatus = "Not run";
row.ErrorMessage = "";
end

function location = thermalPackPreferredLegendCorner( ...
        xValues,yValues,xLimits,yLimits)
% Prefer the upper-right corner. Move only when another corner contains
% fewer plotted points; ties follow upper-right, upper-left, lower-right,
% then lower-left priority.
location = "northeast";
xValues = double(xValues(:));
yValues = double(yValues(:));
valid = isfinite(xValues) & isfinite(yValues);
xValues = xValues(valid);
yValues = yValues(valid);
if isempty(xValues) || numel(xLimits) ~= 2 || numel(yLimits) ~= 2 || ...
        any(~isfinite([xLimits(:);yLimits(:)])) || ...
        xLimits(2) <= xLimits(1) || yLimits(2) <= yLimits(1)
    return;
end

xNormalized = (xValues-xLimits(1))/(xLimits(2)-xLimits(1));
yNormalized = (yValues-yLimits(1))/(yLimits(2)-yLimits(1));
cornerOccupancy = [ ...
    sum(xNormalized >= 0.58 & yNormalized >= 0.58), ...
    sum(xNormalized <= 0.42 & yNormalized >= 0.58), ...
    sum(xNormalized >= 0.58 & yNormalized <= 0.42), ...
    sum(xNormalized <= 0.42 & yNormalized <= 0.42)];
priorityPenalty = [0 0.25 0.50 0.75];
[~,bestCorner] = min(cornerOccupancy + priorityPenalty);
locations = ["northeast","northwest","southeast","southwest"];
location = locations(bestCorner);
end

function order = thermalPackDefaultSelectionOrder(kind)
if lower(string(kind)) == "cooling"
    order = ["PeakT","CellDelta","WithinDelta","Operating"];
else
    order = ["PeakT","CellDelta","WithinDelta","DesignParameters"];
end
end

function order = thermalPackNormalizeSelectionOrder(order,kind)
defaultOrder = thermalPackDefaultSelectionOrder(kind);
order = string(order(:).');
if numel(order) ~= numel(defaultOrder) || ...
        numel(unique(order)) ~= numel(defaultOrder) || ...
        any(~ismember(defaultOrder,order))
    order = defaultOrder;
end
end

function [Results,Recommendation] = thermalPackDesignRecommendations(Results,criterionOrder)
if nargin < 2
    criterionOrder = thermalPackDefaultSelectionOrder("design");
end
criterionOrder = thermalPackNormalizeSelectionOrder(criterionOrder,"design");
Results.Recommended(:) = false;
valid = Results.Success & Results.Feasible & ...
    isfinite(Results.PeakTmaxNodal_C) & ...
    isfinite(Results.MaxCellToCellDeltaT_C) & ...
    isfinite(Results.MaxWithinCellDeltaT_C) & ...
    isfinite(Results.Parameter1Value) & isfinite(Results.Parameter2Value);
candidates = find(valid);
if ~isempty(candidates)
    peak = Results.PeakTmaxNodal_C(candidates);
    cellDelta = Results.MaxCellToCellDeltaT_C(candidates);
    withinCellDelta = Results.MaxWithinCellDeltaT_C(candidates);
    parameter1 = Results.Parameter1Value(candidates);
    parameter2 = Results.Parameter2Value(candidates);
    parameter3 = Results.Parameter3Value(candidates);
    % Two-variable sweeps store NaN for Parameter 3; use a neutral key.
    parameter3(~isfinite(parameter3)) = 0;
    ranking = zeros(numel(candidates),0);
    for kCriterion = 1:numel(criterionOrder)
        switch criterionOrder(kCriterion)
            case "PeakT"
                ranking = [ranking,peak(:)]; %#ok<AGROW>
            case "CellDelta"
                ranking = [ranking,cellDelta(:)]; %#ok<AGROW>
            case "WithinDelta"
                ranking = [ranking,withinCellDelta(:)]; %#ok<AGROW>
            case "DesignParameters"
                ranking = [ranking,parameter1(:),parameter2(:), ...
                    parameter3(:)]; %#ok<AGROW>
        end
    end
    [~,rankingOrder] = sortrows(ranking,1:size(ranking,2));
    Results.Recommended(candidates(rankingOrder(1))) = true;
end
Recommendation = Results(Results.Recommended,:);
end

function parameters = thermalPackOperatingModelParameters()
% SimscapeLogDecimation is numeric; the other settings below are text.
% Keep this parameter contract separate so the MATLAB self-test covers it.
parameters = {"StartTime","0", ...
    "LoadInitialState","off", ...
    "SimscapeLogLimitData","off", ...
    "SimscapeLogDecimation",1};
end

function values = thermalPackOperatingRange(bounds,labelText,positiveOnly)
if ~isnumeric(bounds) || ~isreal(bounds) || numel(bounds) ~= 3 || ...
        any(~isfinite(bounds(:)))
    error("ThermalPack:OptimizationInput", ...
        "%s requires three finite real numbers: minimum, maximum and step.",labelText);
end
lo = bounds(1); hi = bounds(2); step = bounds(3);
if hi < lo || step <= 0 || (positiveOnly && lo <= 0)
    error("ThermalPack:OptimizationInput", ...
        "%s requires maximum >= minimum and step > 0; flow/velocity must be positive.",labelText);
end
spanInSteps = (hi-lo)/step;
if ~isfinite(spanInSteps) || spanInSteps >= 10000
    error("ThermalPack:OptimizationInput", ...
        "%s has too many samples; use at most 10000 values per axis.",labelText);
end
% Snap only a mathematically aligned endpoint. Absolute-temperature tolerances
% must not replace a single minimum with an off-grid maximum for tiny ranges.
roundTolerance = 32*eps(max(1,abs(spanInSteps)));
nSteps = floor(spanInSteps + roundTolerance);
if nSteps > 9999
    error("ThermalPack:OptimizationInput","%s exceeds 10000 samples.",labelText);
end
values = lo + (0:nSteps)*step;
if nSteps > 0 && abs(spanInSteps-nSteps) <= roundTolerance
    values(end) = hi;
end
if any(~isfinite(values)) || any(diff(values) <= 0) || any(values > hi)
    error("ThermalPack:OptimizationInput", ...
        "%s step cannot be resolved accurately at these bounds.",labelText);
end
end

function met = thermalPackOperatingMetrics(Trace,cfg,stopTime_s)
requiredFields = {'tCell','Tcell_C','tNodes','nodal_C'};
if ~all(isfield(Trace,requiredFields))
    error("ThermalPack:OptimizationTrace","Required thermal logs are missing.");
end
cellTemps = double(Trace.Tcell_C);
nodeTemps = double(Trace.nodal_C);
tCell = double(Trace.tCell(:));
tNode = double(Trace.tNodes(:));
if isempty(cellTemps) || isempty(nodeTemps) || ...
        ~isreal(cellTemps) || ~isreal(nodeTemps) || ...
        any(~isfinite(cellTemps(:))) || any(~isfinite(nodeTemps(:))) || ...
        size(cellTemps,1) ~= numel(tCell) || size(cellTemps,2) ~= cfg.TotalCells || ...
        size(nodeTemps,1) ~= numel(tNode) || size(nodeTemps,2) ~= cfg.NodesPerCell || ...
        size(nodeTemps,3) ~= cfg.TotalCells
    error("ThermalPack:OptimizationTrace", ...
        "Thermal logs contain missing, nonfinite or incorrectly sized temperatures.");
end
% Full-mission metrics require both time bases to cover the requested run.
% Data-limit truncation, user stops and early model termination cannot pass.
timeTolerance = max(1e-6,1e-8*abs(stopTime_s));
if numel(tCell) < 2 || numel(tNode) < 2 || ...
        any(~isfinite(tCell)) || any(~isfinite(tNode)) || ...
        any(diff(tCell) < 0) || any(diff(tNode) < 0) || ...
        abs(tCell(1)) > timeTolerance || abs(tNode(1)) > timeTolerance || ...
        abs(tCell(end)-stopTime_s) > timeTolerance || ...
        abs(tNode(end)-stopTime_s) > timeTolerance
    error("ThermalPack:OptimizationIncomplete", ...
        "Thermal logs do not cover the full simulation from 0 to %.6g s.",stopTime_s);
end
cellSpread = max(cellTemps,[],2) - min(cellTemps,[],2);
withinCellSpread = max(nodeTemps,[],2) - min(nodeTemps,[],2);
flatNodes = reshape(nodeTemps,numel(tNode),[]);
packNodalSpread = max(flatNodes,[],2) - min(flatNodes,[],2);
met.PeakTmaxNodal_C = max(nodeTemps(:));
met.MaxCellToCellDeltaT_C = max(cellSpread(:));
met.MaxWithinCellDeltaT_C = max(withinCellSpread(:));
met.MaxDeltaTNodal_C = max(packNodalSpread(:));
met.EndTime_s = min(tCell(end),tNode(end));
end

function [selected,rankingUnresolved] = thermalPackBestThermalByInlet( ...
        operatingValues,inletTemps,success,feasible,peakTemperature_C, ...
        cellDelta_C,withinCellDelta_C,criterionOrder)
% Each inlet temperature is its own decision group. Among completed feasible
% cases, thermal performance is ranked before flow or velocity.
if nargin < 5
    peakTemperature_C = zeros(size(operatingValues));
end
if nargin < 6
    cellDelta_C = zeros(size(operatingValues));
end
if nargin < 7
    withinCellDelta_C = zeros(size(operatingValues));
end
if nargin < 8
    criterionOrder = thermalPackDefaultSelectionOrder("cooling");
end
criterionOrder = thermalPackNormalizeSelectionOrder(criterionOrder,"cooling");
selected = false(size(operatingValues));
rankingUnresolved = false(size(operatingValues));
valid = success & feasible & isfinite(operatingValues) & isfinite(inletTemps) & ...
    isfinite(peakTemperature_C) & isfinite(cellDelta_C) & ...
    isfinite(withinCellDelta_C);
uniqueTin = unique(inletTemps);
for kTin = 1:numel(uniqueTin)
    sameTin = inletTemps == uniqueTin(kTin);
    candidates = find(sameTin & valid);
    if isempty(candidates), continue; end
    peak = peakTemperature_C(candidates);
    cellDelta = cellDelta_C(candidates);
    withinCellDelta = withinCellDelta_C(candidates);
    operating = operatingValues(candidates);
    ranking = zeros(numel(candidates),0);
    for kCriterion = 1:numel(criterionOrder)
        switch criterionOrder(kCriterion)
            case "PeakT"
                ranking = [ranking,peak(:)]; %#ok<AGROW>
            case "CellDelta"
                ranking = [ranking,cellDelta(:)]; %#ok<AGROW>
            case "WithinDelta"
                ranking = [ranking,withinCellDelta(:)]; %#ok<AGROW>
            case "Operating"
                ranking = [ranking,operating(:)]; %#ok<AGROW>
        end
    end
    [~,rankingOrder] = sortrows(ranking,1:size(ranking,2));
    best = candidates(rankingOrder(1));
    selected(best) = true;
    rankingUnresolved(best) = any(sameTin & ~success);
end
end

function [Results,Recommendations] = thermalPackOperatingRecommendations(Results,criterionOrder)
if nargin < 2
    criterionOrder = thermalPackDefaultSelectionOrder("cooling");
end
[Results.Recommended,Results.ThermalRankingUnresolved] = ...
    thermalPackBestThermalByInlet(Results.OperatingValue,Results.Tin_C, ...
    Results.Success,Results.Feasible,Results.PeakTmaxNodal_C, ...
    Results.MaxCellToCellDeltaT_C,Results.MaxWithinCellDeltaT_C,criterionOrder);
tinValues = unique(Results.Tin_C);
summary = struct("Tin_C",NaN,"OperatingValue",NaN,"mdot_kg_s",NaN, ...
    "AirVelocity_m_s",NaN,"TopFlowShare_pct",NaN,"TopFlow_kg_s",NaN, ...
    "BottomFlow_kg_s",NaN,"PeakTmaxNodal_C",NaN,"MaxCellToCellDeltaT_C",NaN, ...
    "MaxWithinCellDeltaT_C",NaN,"CaseID",NaN,"CompletedCases",0, ...
    "PlannedCases",0,"ThermalRankingUnresolved",false,"Status","");
rows = repmat(summary,numel(tinValues),1);
copyFields = ["OperatingValue","mdot_kg_s","AirVelocity_m_s", ...
    "TopFlowShare_pct","TopFlow_kg_s","BottomFlow_kg_s", ...
    "PeakTmaxNodal_C","MaxCellToCellDeltaT_C","MaxWithinCellDeltaT_C", ...
    "CaseID","ThermalRankingUnresolved"];
for kTin = 1:numel(tinValues)
    sameTin = Results.Tin_C == tinValues(kTin);
    rows(kTin).Tin_C = tinValues(kTin);
    rows(kTin).PlannedCases = sum(sameTin);
    rows(kTin).CompletedCases = sum(sameTin & Results.Success);
    best = find(sameTin & Results.Recommended,1);
    if ~isempty(best)
        for kField = 1:numel(copyFields)
            rows(kTin).(copyFields(kField)) = Results.(copyFields(kField))(best);
        end
        if rows(kTin).ThermalRankingUnresolved
            rows(kTin).Status = "Best completed thermal result; ranking incomplete";
        else
            rows(kTin).Status = "Best thermal performance";
        end
    elseif all(Results.Success(sameTin))
        rows(kTin).Status = "No feasible case";
    elseif all(Results.CaseStatus(sameTin) == "Not run")
        rows(kTin).Status = "Not run";
    else
        rows(kTin).Status = "No passing case; incomplete sweep";
    end
end
Recommendations = struct2table(rows);
end

function PlotResults = thermalPackOperatingPlotRows(Results)
% Plot every simulated case. Top + Bottom cooling is separated by inlet
% temperature and top-flow share in line plots and heatmaps, while point
% plots label each share directly beside its marker.
PlotResults = Results;
end

function feasible = thermalPackOperatingFeasible(peak_C,cellDelta_C,thermalLimit_C,uniformityLimit_C)
feasible = isfinite(peak_C) & isfinite(cellDelta_C) & ...
    peak_C <= thermalLimit_C & cellDelta_C <= uniformityLimit_C;
end

function report = thermalPackOperatingSelfTest()
% Deliberately small numerical fixtures exercise the actual helpers used by
% the app. This test requires MATLAB, but no model or Simulink licence.
checks = cell(0,1);
parameters = thermalPackOperatingModelParameters();
parameterNames = string(parameters(1:2:end));
decimation = parameters{2*find(parameterNames == "SimscapeLogDecimation",1)};
assert(isnumeric(decimation) && isscalar(decimation) && decimation == 1);
assert(string(parameters{2*find(parameterNames == "SimscapeLogLimitData",1)}) == "off");
checks{end+1,1} = 'Simscape logging uses numeric decimation and retains full history';
x = thermalPackOperatingRange([0.005 0.1 0.005],"Flow",true);
assert(numel(x) == 20 && x(1) == 0.005 && x(end) == 0.1);
checks{end+1,1} = 'Aligned endpoints and case count';
x = thermalPackOperatingRange([0.5 2 0.6],"Air",true);
assert(numel(x) == 3 && max(abs(x-[0.5 1.1 1.7])) < 1e-12);
checks{end+1,1} = 'Off-grid maximum is not appended';
assert(isequal(thermalPackOperatingRange([20 20 5],"Tin",false),20));
assert(isequal(thermalPackOperatingRange([0 100 25],"Top share",false), ...
    [0 25 50 75 100]));
assert(isequal(thermalPackOperatingRange([1e-16 2e-16 3e-16],"Flow",true),1e-16));
checks{end+1,1} = 'Single-value, percentage and tiny ranges preserve their grids';
expectFailure(@()thermalPackOperatingRange([2 1 0.1],"Flow",true), ...
    'ThermalPack:OptimizationInput');
expectFailure(@()thermalPackOperatingRange([1 2 0],"Flow",true), ...
    'ThermalPack:OptimizationInput');
expectFailure(@()thermalPackOperatingRange([0 1 0.1],"Flow",true), ...
    'ThermalPack:OptimizationInput');
expectFailure(@()thermalPackOperatingRange([1 NaN 0.1],"Flow",true), ...
    'ThermalPack:OptimizationInput');
expectFailure(@()thermalPackOperatingRange([1 10001 1],"Flow",true), ...
    'ThermalPack:OptimizationInput');
checks{end+1,1} = 'Invalid ranges and excessive counts rejected';

cfg = struct('TotalCells',2,'NodesPerCell',2);
trace.tCell = [0;5;10];
trace.tNodes = trace.tCell;
trace.Tcell_C = [21 23;36 29;36 39];
trace.nodal_C(:,:,1) = [20 22;30 42;35 37];
trace.nodal_C(:,:,2) = [22 24;28 30;38 40];
met = thermalPackOperatingMetrics(trace,cfg,10);
assert(met.PeakTmaxNodal_C == 42);
assert(met.MaxCellToCellDeltaT_C == 7);
assert(met.MaxWithinCellDeltaT_C == 12);
assert(met.MaxDeltaTNodal_C == 14);
assert(met.EndTime_s == 10);
checks{end+1,1} = 'Nodal peak, cell-to-cell, within-cell and pack spreads are distinct';
% The cell-average peaks occur at different times: subtracting their maxima
% would give 3 degC, rather than the correct simultaneous spread of 7 degC.
assert(max(trace.Tcell_C(:,2))-max(trace.Tcell_C(:,1)) ~= met.MaxCellToCellDeltaT_C);
checks{end+1,1} = 'Uniformity uses simultaneous temperatures over the full run';
assert(isequal(thermalPackOperatingFeasible([42 42.01 42 41 NaN], ...
    [7 7 7.01 6 6],42,7),logical([1 0 0 1 0])));
checks{end+1,1} = 'Inclusive bounds, separate constraints and nonfinite rejection';

badTrace = trace; badTrace.tNodes(end) = 9;
expectFailure(@()thermalPackOperatingMetrics(badTrace,cfg,10), ...
    'ThermalPack:OptimizationIncomplete');
badTrace = trace; badTrace.tCell(1) = 1;
expectFailure(@()thermalPackOperatingMetrics(badTrace,cfg,10), ...
    'ThermalPack:OptimizationIncomplete');
badTrace = trace; badTrace.nodal_C(2,1,1) = NaN;
expectFailure(@()thermalPackOperatingMetrics(badTrace,cfg,10), ...
    'ThermalPack:OptimizationTrace');
badTrace = trace; badTrace.Tcell_C = badTrace.Tcell_C(:,1);
expectFailure(@()thermalPackOperatingMetrics(badTrace,cfg,10), ...
    'ThermalPack:OptimizationTrace');
checks{end+1,1} = 'Stopped, truncated, nonfinite and missing-cell logs rejected';
one = trace; one.Tcell_C = trace.Tcell_C(:,1); one.nodal_C = trace.nodal_C(:,:,1);
oneCfg = struct('TotalCells',1,'NodesPerCell',2);
oneMet = thermalPackOperatingMetrics(one,oneCfg,10);
assert(oneMet.MaxCellToCellDeltaT_C == 0 && oneMet.MaxWithinCellDeltaT_C == 12);
checks{end+1,1} = 'Single-cell uniformity is zero; within-cell gradient retained';

values = [3;1;2;1;2;3;1;2];
tin = [15;15;15;25;25;25;35;35];
success = logical([1;1;1;0;1;1;1;0]);
feasible = logical([1;0;1;0;1;1;0;0]);
peak = [30;99;32;99;34;31;99;99];
cellDelta = [2;99;1;99;1;2;99;99];
withinDelta = [3;99;2;99;2;1;99;99];
[selected,unresolved] = thermalPackBestThermalByInlet( ...
    values,tin,success,feasible,peak,cellDelta,withinDelta);
assert(isequal(find(selected),[1;6]) && isequal(find(unresolved),6));
checks{end+1,1} = 'Independent per-inlet thermal ranking can select a higher operating setting';
[operatingFirst,~] = thermalPackBestThermalByInlet( ...
    values,tin,success,feasible,peak,cellDelta,withinDelta, ...
    ["Operating","PeakT","CellDelta","WithinDelta"]);
assert(isequal(find(operatingFirst),[3;5]));
checks{end+1,1} = 'Cooling recommendation follows a user-reordered priority list';
[same,~] = thermalPackBestThermalByInlet( ...
    values,tin,success,feasible | ~success,peak,cellDelta,withinDelta);
assert(isequal(same,selected));
checks{end+1,1} = 'Failed cases cannot be recommended even if flagged feasible';
rows = repmat(optimizationEmptyRow(),numel(values),1);
for k = 1:numel(values)
    rows(k).CaseID = k;
    rows(k).OperatingValue = values(k);
    rows(k).mdot_kg_s = values(k);
    rows(k).Tin_C = tin(k);
    rows(k).Success = success(k);
    rows(k).Feasible = feasible(k);
    rows(k).PeakTmaxNodal_C = peak(k);
    rows(k).MaxCellToCellDeltaT_C = cellDelta(k);
    rows(k).MaxWithinCellDeltaT_C = withinDelta(k);
    if success(k), rows(k).CaseStatus = "Completed"; end
end
[results,rec] = thermalPackOperatingRecommendations(struct2table(rows));
assert(isequal(find(results.Recommended),[1;6]) && height(rec) == 3);
assert(rec.Status(1) == "Best thermal performance");
assert(rec.Status(2) == "Best completed thermal result; ranking incomplete");
assert(rec.Status(3) == "No passing case; incomplete sweep");
rows(8).Success = true;
rows(8).CaseStatus = "Fails limits";
[~,rec] = thermalPackOperatingRecommendations(struct2table(rows));
assert(rec.Status(3) == "No feasible case");
rows(7).Success = false; rows(8).Success = false;
rows(7).CaseStatus = "Not run"; rows(8).CaseStatus = "Not run";
[~,rec] = thermalPackOperatingRecommendations(struct2table(rows));
assert(rec.Status(3) == "Not run");
checks{end+1,1} = 'Summary distinguishes feasible, unresolved, infeasible and unrun groups';

splitRows = repmat(optimizationEmptyRow(),4,1);
splitFlow = [1;1;1;2];
splitShare = [25;50;75;50];
splitPeak = [34;32;32;30];
splitDelta = [2;3;1;1];
splitWithinDelta = [3;2;1;1];
for k = 1:4
    splitRows(k).CaseID = k;
    splitRows(k).CoolingArchitecture = "Top + Bottom Cooling";
    splitRows(k).OperatingValue = splitFlow(k);
    splitRows(k).mdot_kg_s = splitFlow(k);
    splitRows(k).TopFlowShare_pct = splitShare(k);
    splitRows(k).TopFlow_kg_s = splitFlow(k)*splitShare(k)/100;
    splitRows(k).BottomFlow_kg_s = splitFlow(k)-splitRows(k).TopFlow_kg_s;
    splitRows(k).Tin_C = 20;
    splitRows(k).PeakTmaxNodal_C = splitPeak(k);
    splitRows(k).MaxCellToCellDeltaT_C = splitDelta(k);
    splitRows(k).MaxWithinCellDeltaT_C = splitWithinDelta(k);
    splitRows(k).Success = true;
    splitRows(k).Feasible = true;
    splitRows(k).CaseStatus = "Pass";
end
[splitResults,splitRec] = ...
    thermalPackOperatingRecommendations(struct2table(splitRows));
assert(isequal(find(splitResults.Recommended),4));
assert(splitRec.TopFlowShare_pct == 50 && ...
    splitRec.Status == "Best thermal performance");
splitPlot = thermalPackOperatingPlotRows(splitResults);
assert(height(splitPlot) == 4 && isequal(splitPlot.CaseID,[1;2;3;4]));
checks{end+1,1} = ...
    'Top/Bottom thermal ranking includes every split and operating value';

designRows = repmat(designOptimizationEmptyRow(),4,1);
designParameter1 = [2;1;1;0.5];
designParameter2 = [1;2;1;0.5];
designPeak = [31;34;32;30];
designDelta = [1;1;2;1];
designWithinDelta = [3;2;1;1];
designFeasible = logical([1;1;1;0]);
for k = 1:4
    designRows(k).CaseID = k;
    designRows(k).Parameter1Value = designParameter1(k);
    designRows(k).Parameter2Value = designParameter2(k);
    designRows(k).PeakTmaxNodal_C = designPeak(k);
    designRows(k).MaxCellToCellDeltaT_C = designDelta(k);
    designRows(k).MaxWithinCellDeltaT_C = designWithinDelta(k);
    designRows(k).Success = true;
    designRows(k).Feasible = designFeasible(k);
end
[designResults,designRecommendation] = ...
    thermalPackDesignRecommendations(struct2table(designRows));
assert(isequal(find(designResults.Recommended),1) && ...
    height(designRecommendation) == 1);
checks{end+1,1} = ...
    'Design recommendation ranks thermal performance before design variables';
[designByParameters,~] = thermalPackDesignRecommendations( ...
    struct2table(designRows), ...
    ["DesignParameters","PeakT","CellDelta","WithinDelta"]);
assert(isequal(find(designByParameters.Recommended),3));
checks{end+1,1} = 'Design recommendation follows a user-reordered priority list';
assert(thermalPackPreferredLegendCorner(1,1,[0 2],[0 2]) == "northeast");
assert(thermalPackPreferredLegendCorner([1 2],[1 2],[0 3],[0 3]) == "northwest");
checks{end+1,1} = 'Design legend prefers upper right and moves away from occupied corners';
report = table(string(checks),true(numel(checks),1),'VariableNames',{'Check','Passed'});

    function expectFailure(callback,identifier)
        caught = false;
        try
            callback();
        catch ME
            caught = strcmp(ME.identifier,identifier);
            if ~caught, rethrow(ME); end
        end
        assert(caught,'Expected failure %s was not raised.',identifier);
    end
end

function txt = numericOrDash(value)
if isempty(value) || ~isnumeric(value) || ~isscalar(value) || ~isfinite(value)
    txt = "—";
else
    txt = string(value);
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

% This is display-only state.  A text field is more robust than creating a
% disabled one-item drop-down for values that may arrive as char or string.
ctrl = uieditfield(parent,"text", ...
    "Value",char(string(stateText)), ...
    "Editable","off", ...
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

%% Selectable cooling-plate helpers
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

% Preserve the existing ThermalPack model-workspace interface.
safeSetBlockParam(blockPath,"plateTemp_ini","T_plate_K");

% Common coolant roughness parameter used by all three plate blocks.
safeSetBlockParamByPrompt(blockPath, ...
    "Coolant channel roughness", ...
    num2str(state.ChannelRoughness_mm/1000,16));

if state.CoolingPlateType == "U-Shaped Channels"
    safeSetBlockParamByPrompt(blockPath, ...
        "Number of flat channel partitions", ...
        num2str(round(state.UShapedChannelPartitions)));

    if state.ChannelOrientation == "Channels along Y axis"
        desiredOrientation = "Channel along Y axis";
    else
        desiredOrientation = "Channel along X axis";
    end
    safeSetEnumBlockParamByPrompt(blockPath, ...
        "Select channel orientation direction",desiredOrientation);

    safeSetBlockParamByPrompt(blockPath, ...
        "Channel thickness", ...
        num2str(state.UShapedChannelThickness_mm/1000,16));
    safeSetBlockParamByPrompt(blockPath, ...
        "Partition width", ...
        num2str(state.UShapedPartitionWidth_mm/1000,16));

elseif state.CoolingPlateType == "Edge Cooling"
    safeSetEnumBlockParamByPrompt(blockPath, ...
        "Select edge to be cooled",state.EdgeCoolingSelection);

    safeSetBlockParamByPrompt(blockPath, ...
        "Cooling channel hydraulic diameter", ...
        num2str(state.EdgeChannelHydraulicDiameter_mm/1000,16));
    safeSetBlockParamByPrompt(blockPath, ...
        "Cooling channel cross-sectional area", ...
        num2str(state.EdgeChannelArea_mm2*1e-6,16));

else
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

simIn = setSimInputBlockParamByPrompt( ...
    simIn,blockPath,"Coolant channel roughness", ...
    num2str(state.ChannelRoughness_mm/1000,16));

if state.CoolingPlateType == "U-Shaped Channels"
    simIn = setSimInputBlockParamByPrompt( ...
        simIn,blockPath,"Number of flat channel partitions", ...
        num2str(round(state.UShapedChannelPartitions)));

    if state.ChannelOrientation == "Channels along Y axis"
        desiredOrientation = "Channel along Y axis";
    else
        desiredOrientation = "Channel along X axis";
    end

    [simIn,~] = setSimInputEnumParamByPrompt( ...
        simIn,blockPath, ...
        "Select channel orientation direction",desiredOrientation);

    simIn = setSimInputBlockParamByPrompt( ...
        simIn,blockPath,"Channel thickness", ...
        num2str(state.UShapedChannelThickness_mm/1000,16));
    simIn = setSimInputBlockParamByPrompt( ...
        simIn,blockPath,"Partition width", ...
        num2str(state.UShapedPartitionWidth_mm/1000,16));

elseif state.CoolingPlateType == "Edge Cooling"
    [simIn,~] = setSimInputEnumParamByPrompt( ...
        simIn,blockPath, ...
        "Select edge to be cooled",state.EdgeCoolingSelection);

    simIn = setSimInputBlockParamByPrompt( ...
        simIn,blockPath,"Cooling channel hydraulic diameter", ...
        num2str(state.EdgeChannelHydraulicDiameter_mm/1000,16));
    simIn = setSimInputBlockParamByPrompt( ...
        simIn,blockPath,"Cooling channel cross-sectional area", ...
        num2str(state.EdgeChannelArea_mm2*1e-6,16));

else
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
end

function locations = thermalNodeLocations(thermalNodes,surfaceName)
if isfield(thermalNodes,"Locations")
    locations = thermalNodes.Locations;
elseif isfield(thermalNodes,"Location")
    locations = thermalNodes.Location;
else
    error("ThermalPack:ThermalNodeLocationMissing", ...
        "ThermalNodes.%s does not contain Locations/Location.",surfaceName);
end
end

function [bottomBlock,topBlock] = findDualFlowRateSourceBlocks(mdl)
bottomBlock = "";
topBlock = "";

try
    allBlocks = string(find_system(mdl, ...
        "LookUnderMasks","all", ...
        "FollowLinks","on", ...
        "Type","Block"));

    for k = 1:numel(allBlocks)
        pathNow = replace(allBlocks(k),newline," ");
        try
            nameNow = replace(string(get_param(allBlocks(k),"Name")),newline," ");
        catch
            continue
        end

        if ~contains(nameNow,"Flow Rate Source (TL)")
            continue
        end

        if contains(pathNow,"/Bottom Cooling Plate/")
            bottomBlock = allBlocks(k);
        elseif contains(pathNow,"/Top Cooling Plate/")
            topBlock = allBlocks(k);
        end
    end
catch
end
end

function blocks = findThermalLiquidPropertiesBlocks(mdl)
blocks = strings(0,1);
try
    allBlocks = string(find_system(mdl, ...
        "LookUnderMasks","all", ...
        "FollowLinks","on", ...
        "Type","Block"));

    for k = 1:numel(allBlocks)
        try
            nameNow = replace(string(get_param(allBlocks(k),"Name")),newline," ");
            maskType = string(get_param(allBlocks(k),"MaskType"));
            if contains(nameNow,"Thermal Liquid Properties (TL)") || ...
                    contains(lower(maskType),"thermal liquid properties")
                blocks(end+1,1) = allBlocks(k); %#ok<AGROW>
            end
        catch
        end
    end
catch
end
blocks = unique(blocks,"stable");
end

function applyFlowSourceSettingsToBlockNamed( ...
        blockPath,state,massVariableName,volVariableName)
safeSetFlowEnum(blockPath,"Source type","Constant");
safeSetFlowEnum(blockPath,"Flow rate type",state.FlowRateType);

if state.FlowRateType == "Mass flow rate"
    safeSetBlockParamByPrompt(blockPath, ...
        "Mass flow rate",massVariableName);
else
    safeSetBlockParamByPrompt(blockPath, ...
        "Volumetric flow rate",volVariableName);
end
end

function simIn = applyFlowSourceSettingsToSimulationInputNamed( ...
        simIn,blockPath,state,massVariableName,volVariableName)
simIn = setFlowEnumOnSimulationInput( ...
    simIn,blockPath,"Source type","Constant");
simIn = setFlowEnumOnSimulationInput( ...
    simIn,blockPath,"Flow rate type",state.FlowRateType);

if state.FlowRateType == "Mass flow rate"
    simIn = setSimInputBlockParamByPrompt( ...
        simIn,blockPath,"Mass flow rate",massVariableName);
else
    simIn = setSimInputBlockParamByPrompt( ...
        simIn,blockPath,"Volumetric flow rate",volVariableName);
end
end

function simIn = configureInletReservoirOnSimulationInput( ...
        simIn,blockPath,state,temperatureVariable,areaVariable)
if getSimulinkBlockHandle(blockPath) <= 0
    return;
end

simIn = simIn.setBlockParameter(blockPath, ...
    "pressure_input","false");
simIn = simIn.setBlockParameter(blockPath, ...
    "temperature_input","false");
simIn = simIn.setBlockParameter(blockPath, ...
    "reservoir_temperature",temperatureVariable);
simIn = simIn.setBlockParameter(blockPath, ...
    "area",areaVariable);

if state.ReservoirPressureSpecification == "Specified pressure"
    simIn = simIn.setBlockParameter(blockPath, ...
        "pressure_spec","foundation.enum.pressure_spec.specified");
    simIn = simIn.setBlockParameter(blockPath, ...
        "reservoir_pressure",num2str(state.ReservoirPressure_Pa,16));
else
    simIn = simIn.setBlockParameter(blockPath, ...
        "pressure_spec","foundation.enum.pressure_spec.atmospheric");
end
end

%% Flow Rate Source (TL) helpers
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

%% Thermal-liquid coolant helpers
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

function requireSetBlockParamByPrompt(blockPath,promptText,value)
paramName = dialogParameterNameByPrompt(blockPath,promptText);
if strlength(paramName) == 0
    error("ThermalPack:ElectrochemicalParameterMissing", ...
        "Enabled electrochemical parameter '%s' was not found on %s. Rebuild the battery with the requested RC/entropic topology.", ...
        promptText,blockPath);
end
try
    set_param(blockPath,char(paramName),char(string(value)));
catch ME
    error("ThermalPack:ElectrochemicalParameterSet", ...
        "Could not set enabled electrochemical parameter '%s' on %s: %s", ...
        promptText,blockPath,ME.message);
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
        "Could not resolve the Simscape enum for Thermal liquid fluid list. The working model was left unchanged.");
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
        "Could not resolve the Simscape enum for Thermal liquid fluid list.");
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

function applyInitialSOCToBlock(blockPath,initialSOC,N,S)
%% Apply Initial SOC directly to generated Battery Builder initialization states.
initialSOC = double(initialSOC);
if ~isscalar(initialSOC) || ~isfinite(initialSOC) || initialSOC < 0 || initialSOC > 1
    error("ThermalPack:InitialSOC", ...
        "Initial SOC must be a finite scalar between 0 and 1.");
end
N = max(1,round(N));
S = max(1,round(S));
cellExpr = thermalPackFormatText("repmat(%.16g,%d,1)",initialSOC,N);
safeSetBlockParam(blockPath,"socCell",cellExpr);
try
    dp = get_param(blockPath,"DialogParameters");
    if isfield(dp,"socParallelAssembly")
        assemblyExpr = thermalPackFormatText( ...
            "repmat(%.16g,%d,1)",initialSOC,S);
        set_param(char(blockPath),"socParallelAssembly",char(assemblyExpr));
    end
catch ME
    warning("ThermalPack:InitialSOCParallelAssembly", ...
        "Could not synchronize parallel-assembly initial SOC on %s: %s", ...
        blockPath,ME.message);
end
end

function verifyInitialSOCOnBlock(blockPath,expectedSOC,N,S)
%% Fail fast when a generated battery retained a stale master SOC.
try
    socCellValue = slResolve(get_param(blockPath,"socCell"),blockPath);
catch
    try
        socCellValue = str2num(get_param(blockPath,"socCell")); %#ok<ST2NM>
    catch
        socCellValue = [];
    end
end
if isempty(socCellValue)
    error("ThermalPack:InitialSOCUnresolved", ...
        "Could not resolve socCell on generated battery %s.",blockPath);
end
socCellValue = double(socCellValue(:));
if numel(socCellValue) ~= round(N) || ...
        any(abs(socCellValue-double(expectedSOC)) > 1e-10)
    error("ThermalPack:InitialSOCMismatch", ...
        ["Initial SOC did not propagate to %s. Expected %.6g for %d cells; " ...
         "resolved range %.6g to %.6g."], ...
        blockPath,expectedSOC,round(N),min(socCellValue),max(socCellValue));
end

try
    dp = get_param(blockPath,"DialogParameters");
    if isfield(dp,"socParallelAssembly")
        try
            socAssemblyValue = slResolve( ...
                get_param(blockPath,"socParallelAssembly"),blockPath);
        catch
            socAssemblyValue = str2num( ...
                get_param(blockPath,"socParallelAssembly")); %#ok<ST2NM>
        end
        if ~isempty(socAssemblyValue)
            socAssemblyValue = double(socAssemblyValue(:));
            if numel(socAssemblyValue) ~= round(S) || ...
                    any(abs(socAssemblyValue-double(expectedSOC)) > 1e-10)
                error("ThermalPack:InitialAssemblySOCMismatch", ...
                    "Parallel-assembly SOC is inconsistent with socCell on %s.",blockPath);
            end
        end
    end
catch ME
    if any(string(ME.identifier) == ...
            ["ThermalPack:InitialAssemblySOCMismatch"])
        rethrow(ME);
    end
end
end

function simIn = setInitialSOCOnSimulationInput(simIn,blockPath,initialSOC,N,S)
%% Repeat Initial SOC on SimulationInput so case sweeps cannot fall back.
% socCell is a required generated battery state parameter.
simIn = simIn.setBlockParameter(blockPath,"socCell", ...
    thermalPackFormatText("repmat(%.16g,%d,1)",initialSOC,round(N)));

% Assembly-level SOC is topology/release dependent.
[simIn,~] = setOptionalSimInputBlockParameter( ...
    simIn,blockPath,"socParallelAssembly", ...
    thermalPackFormatText("repmat(%.16g,%d,1)",initialSOC,round(S)));
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

function simIn = setSimInputElectrochemicalDynamics(simIn,blockPath,state)
model = string(state.PolarizationModel);
if model ~= "Disabled"
    paramName = dialogParameterNameByPrompt(blockPath, ...
        "First polarization resistance, R1(SOC,T)");
    if strlength(paramName) == 0
        error("ThermalPack:ElectrochemicalParameterMissing", ...
            "RC1 is enabled but the generated block %s has no R1 parameter. Rebuild the battery.",blockPath);
    end
    simIn = simIn.setBlockParameter(blockPath,char(paramName), ...
        mat2str(state.R1Table_Ohm,16));

    paramName = dialogParameterNameByPrompt(blockPath, ...
        "First time constant, Tau1(SOC,T)");
    if strlength(paramName) == 0
        error("ThermalPack:ElectrochemicalParameterMissing", ...
            "RC1 is enabled but the generated block %s has no Tau1 parameter. Rebuild the battery.",blockPath);
    end
    simIn = simIn.setBlockParameter(blockPath,char(paramName), ...
        mat2str(state.Tau1Table_s,16));
end

if any(model == ["RC1 + RC2","RC2"])
    paramName = dialogParameterNameByPrompt(blockPath, ...
        "Second polarization resistance, R2(SOC,T)");
    if strlength(paramName) == 0
        error("ThermalPack:ElectrochemicalParameterMissing", ...
            "RC2 is enabled but the generated block %s has no R2 parameter. Rebuild the battery.",blockPath);
    end
    simIn = simIn.setBlockParameter(blockPath,char(paramName), ...
        mat2str(state.R2Table_Ohm,16));

    paramName = dialogParameterNameByPrompt(blockPath, ...
        "Second time constant, Tau2(SOC,T)");
    if strlength(paramName) == 0
        error("ThermalPack:ElectrochemicalParameterMissing", ...
            "RC2 is enabled but the generated block %s has no Tau2 parameter. Rebuild the battery.",blockPath);
    end
    simIn = simIn.setBlockParameter(blockPath,char(paramName), ...
        mat2str(state.Tau2Table_s,16));
end

if logical(state.EntropicHeatEnabled)
    paramName = dialogParameterNameByPrompt(blockPath,"Entropic coefficient");
    if strlength(paramName) == 0
        error("ThermalPack:ElectrochemicalParameterMissing", ...
            "Entropic heat is enabled but the generated block %s has no entropic-coefficient parameter. Rebuild the battery.",blockPath);
    end
    simIn = simIn.setBlockParameter(blockPath,char(paramName), ...
        mat2str(state.EntropicCoefficient_mV_K,16));
end
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

model = string(state.PolarizationModel);
if model ~= "Disabled"
    requireSetBlockParamByPrompt(blockPath, ...
        "First polarization resistance, R1(SOC,T)", ...
        mat2str(state.R1Table_Ohm,16));
    requireSetBlockParamByPrompt(blockPath, ...
        "First time constant, Tau1(SOC,T)", ...
        mat2str(state.Tau1Table_s,16));
end
if any(model == ["RC1 + RC2","RC2"])
    requireSetBlockParamByPrompt(blockPath, ...
        "Second polarization resistance, R2(SOC,T)", ...
        mat2str(state.R2Table_Ohm,16));
    requireSetBlockParamByPrompt(blockPath, ...
        "Second time constant, Tau2(SOC,T)", ...
        mat2str(state.Tau2Table_s,16));
end
if logical(state.EntropicHeatEnabled)
    requireSetBlockParamByPrompt(blockPath, ...
        "Entropic coefficient", ...
        mat2str(state.EntropicCoefficient_mV_K,16));
end

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

function resetCellParameterDeviations(blockPath,N)
%% Reset generated per-cell parameter deviations to nominal for a new cell
% format. This prevents the original cylindrical pack's calibrated variation
% pattern from leaking into the Prismatic/Pouch baselines.
variationNames = [ ...
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

zeroExpr = thermalPackFormatText("zeros([%d, 1])",N);
for i = 1:numel(variationNames)
    safeSetBlockParam(blockPath,variationNames(i),zeroExpr);
end
end

%% Safe block parameter helpers

function txt = thermalPackFormatText(formatSpec,varargin)
%% Scalar text formatting helper used throughout ThermalPack.
% Joins multi-element string format specifications first, then uses compose.
% This avoids invalid-format errors from passing string arrays as a format.

formatSpec = join(string(formatSpec),"");

if isempty(varargin)
    txt = formatSpec;
    return;
end

txt = compose(formatSpec,varargin{:});

% ThermalPack call sites expect a single text value.
if numel(txt) > 1
    txt = join(txt,"");
end
end

function tf = thermalPackBlockHasParameter(blockPath,paramName)
%THERMALPACKBLOCKHASPARAMETER True only when the concrete loaded block
% actually exposes paramName. This is intentionally evaluated BEFORE a
% SimulationInput override is created because SimulationInput can defer
% unknown-mask-parameter validation until sim() starts.

tf = false;
blockPath = string(blockPath);
paramName = string(paramName);

try
    if getSimulinkBlockHandle(blockPath) <= 0
        return;
    end
catch
    return;
end

% Primary source: DialogParameters is the most reliable description of
% generated Battery Builder mask parameters.
try
    dp = get_param(char(blockPath),"DialogParameters");
    if isstruct(dp) && isfield(dp,char(paramName))
        tf = true;
        return;
    end
catch
end

% Fallback for non-mask/block parameters that are still settable through
% get_param/set_param but are not listed in DialogParameters.
try
    get_param(char(blockPath),char(paramName));
    tf = true;
catch
    tf = false;
end
end

function [simIn,applied] = setOptionalSimInputBlockParameter( ...
        simIn,blockPath,paramName,paramValue)
%SETOPTIONALSIMINPUTBLOCKPARAMETER Add an override only if the generated
% block actually owns the parameter. Missing architecture-dependent fields
% are skipped cleanly, preventing a deferred "block does not have a
% parameter named ..." failure when sim(simIn) begins.

applied = false;

if ~thermalPackBlockHasParameter(blockPath,paramName)
    return;
end

try
    simIn = simIn.setBlockParameter( ...
        char(string(blockPath)),char(string(paramName)),char(string(paramValue)));
    applied = true;
catch ME
    % A parameter that was positively detected should normally be settable.
    % Do not silently hide a real malformed-value or Simulink error.
    error("ThermalPack:OptionalSimulationInputParameterSet", ...
        "Could not set detected parameter '%s' on '%s': %s", ...
        string(paramName),string(blockPath),ME.message);
end
end

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
        resized = thermalPackFormatText("zeros([%d, 1])",N);
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
    expr = thermalPackFormatText("zeros([%d, 1])",N);
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
replacement = thermalPackFormatText('%d, 1)',newCount);
candidate = regexprep(exprOut,pattern,replacement);

if candidate == exprOut
%% Fallback for an unexpected expression: leave it unchanged rather
    % than silently fabricating a different physical initialization.
    candidate = exprOut;
end

exprOut = candidate;
end

%% Result extraction
function blockPath = thermalPackResolveLibraryBlockByName(libraryModels,blockName)
%% Resolve an installed Simscape/Simulink library block by exact Name.
blockPath = "";
libraryModels = string(libraryModels);
blockName = string(blockName);
for iLib = 1:numel(libraryModels)
    lib = libraryModels(iLib);
    try
        load_system(lib);
    catch
        continue;
    end
    try
        matches = find_system(lib, ...
            "LookUnderMasks","all", ...
            "FollowLinks","on", ...
            "Type","Block", ...
            "Name",char(blockName));
        if ~isempty(matches)
            blockPath = string(matches{1});
            return;
        end
    catch
    end
end
end

function txt = thermalPackDetailedExceptionText(ME)
%% Flatten an MException and all nested causes into readable text.
% Simulink frequently reports only "Error due to multiple causes" at the
% top level. ThermalPack keeps the actual compile causes visible so a failed
% generated topology can be corrected without guessing.
lines = strings(0,1);
try
    lines(end+1,1) = "Identifier: " + string(ME.identifier); %#ok<AGROW>
catch
end
try
    lines(end+1,1) = "Message: " + string(ME.message); %#ok<AGROW>
catch
end
try
    if ~isempty(ME.stack)
        s = ME.stack(1);
        lines(end+1,1) = thermalPackFormatText( ...
            "Location: %s (line %d)",string(s.name),s.line); %#ok<AGROW>
    end
catch
end

try
    causes = ME.cause;
catch
    causes = {};
end
for kCause = 1:numel(causes)
    try
        child = thermalPackDetailedExceptionText(causes{kCause});
        childLines = splitlines(string(child));
        lines(end+1,1) = thermalPackFormatText("Cause %d:",kCause); %#ok<AGROW>
        for kLine = 1:numel(childLines)
            if strlength(childLines(kLine)) > 0
                lines(end+1,1) = "  " + childLines(kLine); %#ok<AGROW>
            end
        end
    catch
    end
end

if isempty(lines)
    try
        txt = string(getReport(ME,"extended","hyperlinks","off"));
    catch
        txt = "Unknown Simulink/Simscape model-update error.";
    end
else
    txt = join(lines,newline);
end
end

function portName = thermalPackFirstConservingPortName(blockHandle)
%% Return the first Simscape conserving-port name on a block.
portName = "";
try
    info = simscape.connectionPortProperties(blockHandle);
    if ~isempty(info)
        portName = string(info(1).Name);
    end
catch
end
if strlength(portName) == 0
    error("ThermalPack:ConservingPortResolution", ...
        "Could not resolve a Simscape conserving port on block handle %g.", ...
        blockHandle);
end
end

function thermalPackSetPSConstant(blockPath,value,unitText)
%% Configure a PS Constant scalar value and physical unit robustly.
blockPath = string(blockPath);
unitText = string(unitText);
if ~(isnumeric(value) && isscalar(value) && isfinite(value))
    error("ThermalPack:PSConstantValue", ...
        "PS Constant value must be a finite numeric scalar.");
end
valueExpression = num2str(value,16);
try
    set_param(blockPath,"constant",valueExpression);
catch ME
    error("ThermalPack:PSConstantValueSet", ...
        "Could not set PS Constant numeric value on %s: %s", ...
        blockPath,ME.message);
end

unitParamName = "";
try
    dialogParameters = get_param(blockPath,"DialogParameters");
    paramNames = string(fieldnames(dialogParameters));
    exactIdx = find(strcmpi(paramNames,"constant_unit"),1);
    if ~isempty(exactIdx)
        unitParamName = paramNames(exactIdx);
    end
    if strlength(unitParamName) == 0
        lowerNames = lower(paramNames);
        candidateIdx = find(contains(lowerNames,"constant") & ...
            contains(lowerNames,"unit"),1);
        if ~isempty(candidateIdx)
            unitParamName = paramNames(candidateIdx);
        end
    end
catch
end
if strlength(unitParamName) == 0
    try
        set_param(blockPath,"constant_unit",char(unitText));
        unitParamName = "constant_unit";
    catch ME
        error("ThermalPack:PSConstantUnitResolution", ...
            "Could not set PS Constant unit '%s' on %s: %s", ...
            unitText,blockPath,ME.message);
    end
else
    try
        set_param(blockPath,char(unitParamName),char(unitText));
    catch ME
        error("ThermalPack:PSConstantUnitSet", ...
            "Could not set PS Constant unit '%s' on %s: %s", ...
            unitText,blockPath,ME.message);
    end
end
end


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

cellFormat = string(cfg.CellFormat);
if isfield(cfg,"ProgressiveForcedAir") && cfg.ProgressiveForcedAir
    [KPI,Trace] = extractProgressiveUIResults(simlog,cfg);
    return;
end
moduleLog = thermalPackResolveModuleLog(simlog,cellFormat);

%% Cell-average temperature. The generated module exposes the same
% batteryTemperature logging signal for Cylindrical, Prismatic and Pouch cells.
try
    cellSeries = moduleLog.batteryTemperature.series;
catch ME
    error("ThermalPack:CellTemperatureLogMissing", ...
        "Could not read the %s module batteryTemperature log:\n%s", ...
        cellFormat,ME.message);
end

Tcell_K = cellSeries.values("K");
tCell = time(cellSeries);
Tcell_K = reshape(Tcell_K,size(Tcell_K,1),[]);
Tcell_C = Tcell_K - 273.15;

if size(Tcell_C,2) ~= cfg.TotalCells
    warning("ThermalPack:CellAverageCount", ...
        "Expected %d cell-average temperature signals but read %d.", ...
        cfg.TotalCells,size(Tcell_C,2));
end

TmaxCell = max(Tcell_C,[],2);

%% Pack-level statistics of the CELL-AVERAGE temperature signals.
TmaxCellAverage_C = max(Tcell_C,[],2);
TmeanCellAverage_C = mean(Tcell_C,2,"omitnan");
TminCellAverage_C = min(Tcell_C,[],2);

%% Height-distributed nodes. Resolve the generated hierarchy by cell format
% while retaining fallbacks for a working model whose top-level block name is
% preserved as Cylindrical_Cell_Module_Test during block replacement.
firstAssembly = thermalPackResolveAssemblyLog(moduleLog,cellFormat,1);
firstCell = thermalPackResolveCellLog(firstAssembly,cellFormat,1);

try
    firstNode = firstCell.HDistributed(1).T;
catch ME
    error("ThermalPack:NodalTemperatureLogMissing", ...
        "Could not read HDistributed(1).T from the %s generated cell. Confirm NumThermalModelsCell uses HeightDistributedMass.\n%s", ...
        cellFormat,ME.message);
end

tNodes = time(firstNode.series);
nodal_K = zeros(numel(tNodes),cfg.NodesPerCell,cfg.TotalCells);
rawCell = 1;

for a = 1:cfg.NumAssemblies
    assembly = thermalPackResolveAssemblyLog(moduleLog,cellFormat,a);

    for c = 1:cfg.CellsPerAssembly
        cellLog = thermalPackResolveCellLog(assembly,cellFormat,c);

        for n = 1:cfg.NodesPerCell
            try
                values_K = cellLog.HDistributed(n).T.series.values("K");
            catch ME
                error("ThermalPack:NodalTemperatureLogMissing", ...
                    "Could not read %s Cell %d / Node %d from assembly %d.\n%s", ...
                    cellFormat,c,n,a,ME.message);
            end

            nodal_K(:,n,rawCell) = reshape(values_K,[],1);
        end
        rawCell = rawCell + 1;
    end
end

if rawCell-1 ~= cfg.TotalCells
    error("ThermalPack:NodalCellCount", ...
        "Extracted %d cells from simlog but expected %d.", ...
        rawCell-1,cfg.TotalCells);
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

% Generated battery modules log these cell-level public variables.
% Read actual Simscape outputs rather than inferring voltage from I*R0:
% polarization, SOC and cell temperature then remain in the audit.
Trace.tVoltage = [];
Trace.Vcell_V = [];
Trace.tCurrent = [];
Trace.Icell_A = [];
Trace.tSOC = [];
Trace.SOCcell = [];
Trace.ElectricalLogStatus = "";
try
    vSeries = moduleLog.batteryVoltage.series;
    tV = double(time(vSeries));
    v = double(vSeries.values("V"));
    v = reshape(v,numel(tV),[]);
    if size(v,2) ~= cfg.TotalCells || any(~isfinite(v),"all")
        error("ThermalPack:RP1VoltageCount", ...
            "Logged batteryVoltage must contain %d finite cell traces.", ...
            cfg.TotalCells);
    end
    Trace.tVoltage = tV(:);
    Trace.Vcell_V = v;
catch ME
    Trace.ElectricalLogStatus = "Cell voltage log unavailable: " + ...
        string(ME.message);
end
try
    iSeries = moduleLog.batteryCurrent.series;
    tI = double(time(iSeries));
    i = reshape(double(iSeries.values("A")),numel(tI),[]);
    if size(i,2) == cfg.TotalCells
        Trace.tCurrent = tI(:);
        Trace.Icell_A = i;
    end
catch
end
try
    socSeries = moduleLog.socCell.series;
    tSOC = double(time(socSeries));
    soc = reshape(double(socSeries.values("1")),numel(tSOC),[]);
    if size(soc,2) == cfg.TotalCells
        Trace.tSOC = tSOC(:);
        Trace.SOCcell = soc;
    end
catch
end
end

function [KPI,Trace] = extractProgressiveUIResults(simlog,cfg)
%% Reassemble cell/nodal temperatures from the generated Progressive Gas
% battery segments back into the original ThermalPack cell numbering.
cellFormat = string(cfg.CellFormat);
segmentNames = string(cfg.ProgressiveSegmentNames);
segmentCellIDs = cfg.ProgressiveSegmentCellIDs;

if isempty(segmentNames) || numel(segmentNames) ~= numel(segmentCellIDs)
    error("ThermalPack:ProgressiveResultMetadata", ...
        "Progressive forced-air result metadata are incomplete.");
end

% Verify the generated Gas circuit actually carried the commanded mass flow.
% This audit was important in the Fan validation: displaying a requested mdot
% is not sufficient if the controlled Flow Rate Source is misconfigured.
actualGasMassFlow_kg_s = NaN;
if isfield(cfg,"ProgressiveGasFlowSourcePath") && ...
        strlength(string(cfg.ProgressiveGasFlowSourcePath)) > 0
    flowNode = [];
    try
        flowNode = simscape.logging.findNode( ...
            simlog,string(cfg.ProgressiveGasFlowSourcePath));
    catch
    end
    if isempty(flowNode)
        error("ThermalPack:ProgressiveGasFlowLog", ...
            "Could not locate the generated Gas Flow Rate Source in the Simscape log.");
    end

    flowSeries = [];
    try
        flowSeries = reshape(flowNode.mdot_A.series.values("kg/s"),[],1);
    catch
        try
            flowSeries = reshape(-flowNode.mdot_B.series.values("kg/s"),[],1);
        catch MEflow
            error("ThermalPack:ProgressiveGasFlowVariable", ...
                "Could not read mdot_A/mdot_B from the generated Gas Flow Rate Source: %s", ...
                MEflow.message);
        end
    end
    finiteFlow = flowSeries(isfinite(flowSeries));
    if isempty(finiteFlow)
        error("ThermalPack:ProgressiveGasFlowNaN", ...
            "Generated Gas mass-flow logging is empty or non-finite.");
    end
    actualGasMassFlow_kg_s = median(finiteFlow);

    if isfield(cfg,"ProgressiveExpectedMassFlow_kg_s") && ...
            isfinite(cfg.ProgressiveExpectedMassFlow_kg_s)
        expectedMdot = cfg.ProgressiveExpectedMassFlow_kg_s;
        if abs(actualGasMassFlow_kg_s-expectedMdot) > ...
                max(1e-6,0.02*max(abs(expectedMdot),1e-9))
            flowError_pct = 100*(actualGasMassFlow_kg_s-expectedMdot) / ...
                max(abs(expectedMdot),1e-12);
            error("ThermalPack:ProgressiveGasFlowMismatch", ...
                "Generated Gas mass-flow verification failed. Requested %.6g kg/s, " + ...
                "logged %.6g kg/s (difference %+.2f%%).", ...
                expectedMdot,actualGasMassFlow_kg_s,flowError_pct);
        end
    end
end

Tcell_C = [];
nodal_C = [];
tCell = [];
tNodes = [];

for kSeg = 1:numel(segmentNames)
    segName = segmentNames(kSeg);
    blockPath = string(cfg.ModelName) + "/" + ...
        string(cfg.ProgressiveSubsystemName) + "/" + segName;

    moduleLog = [];
    try
        moduleLog = simscape.logging.findNode(simlog,blockPath);
    catch
    end
    if isempty(moduleLog)
        try
            shortPath = string(cfg.ProgressiveSubsystemName) + "/" + segName;
            moduleLog = simscape.logging.findNode(simlog,shortPath);
        catch
        end
    end
    if isempty(moduleLog)
        error("ThermalPack:ProgressiveModuleLogMissing", ...
            "Could not locate Simscape log for progressive segment %s.",segName);
    end

    try
        cellSeries = moduleLog.batteryTemperature.series;
    catch ME
        error("ThermalPack:ProgressiveCellTemperatureLog", ...
            "Could not read batteryTemperature for progressive segment %s:\n%s", ...
            segName,ME.message);
    end

    segT_K = cellSeries.values("K");
    segT_K = reshape(segT_K,size(segT_K,1),[]);
    segT_C = segT_K - 273.15;
    ids = double(segmentCellIDs{kSeg}(:));

    if size(segT_C,2) ~= numel(ids)
        error("ThermalPack:ProgressiveCellCount", ...
            "Segment %s logged %d cells but metadata assigns %d.", ...
            segName,size(segT_C,2),numel(ids));
    end

    % simscape.logging.Series time is accessed through the time(series) API.
    % Cache the segment time vector once so all comparisons use the same data.
    segTime = time(cellSeries);
    segTime = reshape(segTime,[],1);

    if isempty(Tcell_C)
        tCell = segTime;
        Tcell_C = NaN(numel(tCell),cfg.TotalCells);
    elseif numel(segTime) ~= numel(tCell) || ...
            any(abs(segTime(:)-tCell(:)) > 1e-9)
        error("ThermalPack:ProgressiveTimeBase", ...
            "Progressive battery segments do not share the same cell-temperature time base.");
    end
    Tcell_C(:,ids) = segT_C;

    assembly = thermalPackResolveAssemblyLog(moduleLog,cellFormat,1);
    firstCell = thermalPackResolveCellLog(assembly,cellFormat,1);
    try
        firstNode = firstCell.HDistributed(1).T;
    catch ME
        error("ThermalPack:ProgressiveNodalLog", ...
            "Could not read the first HDistributed node for segment %s:\n%s", ...
            segName,ME.message);
    end

    if isempty(nodal_C)
        tNodes = time(firstNode.series);
        nodal_C = NaN(numel(tNodes),cfg.NodesPerCell,cfg.TotalCells);
    end

    for cLocal = 1:numel(ids)
        cellLog = thermalPackResolveCellLog(assembly,cellFormat,cLocal);
        for n = 1:cfg.NodesPerCell
            try
                values_K = cellLog.HDistributed(n).T.series.values("K");
            catch ME
                error("ThermalPack:ProgressiveNodalLog", ...
                    "Could not read segment %s / local cell %d / node %d:\n%s", ...
                    segName,cLocal,n,ME.message);
            end
            values_K = reshape(values_K,[],1);
            if numel(values_K) ~= numel(tNodes)
                error("ThermalPack:ProgressiveNodalTimeBase", ...
                    "Progressive segment %s has inconsistent nodal time data.",segName);
            end
            nodal_C(:,n,ids(cLocal)) = values_K - 273.15;
        end
    end
end

if any(isnan(Tcell_C),"all") || any(isnan(nodal_C),"all")
    error("ThermalPack:ProgressiveResultAssembly", ...
        "One or more original cells were not reconstructed from progressive segment logs.");
end

TmaxCell = max(Tcell_C,[],2);
TmaxCellAverage_C = max(Tcell_C,[],2);
TmeanCellAverage_C = mean(Tcell_C,2,"omitnan");
TminCellAverage_C = min(Tcell_C,[],2);

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
KPI.GasMassFlow_kg_s = actualGasMassFlow_kg_s;

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
Trace.GasMassFlow_kg_s = actualGasMassFlow_kg_s;
end


function moduleLog = thermalPackResolveModuleLog(simlog,cellFormat)
%% The working model preserves its original top-level block name during
% replacement, so Cylindrical_Cell_Module_Test is tried first for all formats.
try
    moduleLog = simlog.Cylindrical_Cell_Module_Test;
    return;
catch
end
try
    moduleLog = simlog.Cylindrical_Cell_Module_Test;
    return;
catch
end
if cellFormat == "Prismatic"
    try
        moduleLog = simlog.Prismatic_Cell_Module_Test;
        return;
    catch
    end
elseif cellFormat == "Pouch"
    try
        moduleLog = simlog.Pouch_Cell_Module_Test;
        return;
    catch
    end
end
error("ThermalPack:ModuleLogMissing", ...
    "Could not locate the %s battery module in simlog.",cellFormat);
end

function assemblyLog = thermalPackResolveAssemblyLog(moduleLog,cellFormat,index)
if cellFormat == "Prismatic"
    try
        assemblyLog = moduleLog.Prismatic_Cell_Assembly(index);
        return;
    catch
    end
    try
        assemblyLog = moduleLog.Cylindrical_Cell_Assembly(index);
        return;
    catch
    end
    try
        assemblyLog = moduleLog.Pouch_Cell_Assembly(index);
        return;
    catch
    end
elseif cellFormat == "Pouch"
    try
        assemblyLog = moduleLog.Pouch_Cell_Assembly(index);
        return;
    catch
    end
    try
        assemblyLog = moduleLog.Cylindrical_Cell_Assembly(index);
        return;
    catch
    end
    try
        assemblyLog = moduleLog.Prismatic_Cell_Assembly(index);
        return;
    catch
    end
else
    try
        assemblyLog = moduleLog.Cylindrical_Cell_Assembly(index);
        return;
    catch
    end
    try
        assemblyLog = moduleLog.Prismatic_Cell_Assembly(index);
        return;
    catch
    end
    try
        assemblyLog = moduleLog.Pouch_Cell_Assembly(index);
        return;
    catch
    end
end
error("ThermalPack:AssemblyLogMissing", ...
    "Could not locate %s parallel assembly %d in simlog.",cellFormat,index);
end

function cellLog = thermalPackResolveCellLog(assemblyLog,cellFormat,index)
if cellFormat == "Prismatic"
    try
        cellLog = assemblyLog.Prismatic_Cell(index);
        return;
    catch
    end
    try
        cellLog = assemblyLog.Cylindrical_Cell(index);
        return;
    catch
    end
    try
        cellLog = assemblyLog.Pouch_Cell(index);
        return;
    catch
    end
elseif cellFormat == "Pouch"
    try
        cellLog = assemblyLog.Pouch_Cell(index);
        return;
    catch
    end
    try
        cellLog = assemblyLog.Cylindrical_Cell(index);
        return;
    catch
    end
    try
        cellLog = assemblyLog.Prismatic_Cell(index);
        return;
    catch
    end
else
    try
        cellLog = assemblyLog.Cylindrical_Cell(index);
        return;
    catch
    end
    try
        cellLog = assemblyLog.Prismatic_Cell(index);
        return;
    catch
    end
    try
        cellLog = assemblyLog.Pouch_Cell(index);
        return;
    catch
    end
end
error("ThermalPack:CellLogMissing", ...
    "Could not locate %s cell %d in the Simscape log.",cellFormat,index);
end
