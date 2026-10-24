# ThermalPack Version 2.0 — User Guide

## Setup and launch

Open the repository root as the current MATLAB folder. Keep `ThermalPack_v2_App.m`, `Thermal_Model_v5.slx` and the complete `Thermal_Pack_Libraries/` folder together. Preserve the `+package` subfolders inside the library root.

The supplied master model was saved in R2026a. MATLAB, Simulink, Simscape, Simscape Battery and Simscape Fluids are required; other releases have not been verified.

```matlab
ThermalPack_v2_App
```

The application adds the project-local library root to the path, loads the supplied libraries and creates `Thermal_Model_v5_UI.slx` from the master model. Rebuilds write generated battery files to `ThermalPack_Generated/`. Launching the app regenerates the working model, so make reusable changes through app settings and the supported configuration workflow.

## Single simulation

1. Select a cell format and configure the series/parallel architecture and geometry.
2. Review cell electrical/thermal data, initial SOC and temperature, and the current profile.
3. Select a cooling architecture and set its geometry, operating point and boundary conditions.
4. Rebuild the battery, run the simulation and inspect temperature histories, KPIs and the 3D nodal thermal map.

Default cell parameters are study inputs. In particular, prismatic and pouch baselines include provisional electrical data; supply suitable cell-specific data before interpreting a new configuration quantitatively.

## Cooling Optimization

1. Complete the main battery/cooling setup. There is no separate optimization architecture selector.
2. Enter minimum, maximum and step for flow or air velocity and inlet temperature. Top + Bottom Cooling also provides a top-flow-share range.
3. Open **DESIGN LIMITS** to review both feasibility limits. Starting values of 60 °C and 5 °C are editable study inputs, not validated cell-specific operating limits.
4. Open **SELECTION CRITERIA** to review the recommendation priorities.
5. Click **RUN OPERATING SWEEP**. A required structural rebuild runs first.
6. Inspect the all-case table and Peak Temperature, Cell Uniformity, Tmax Heatmap, Feasibility and Operating Points plots.
7. Export results, then confirm the original operating settings have been restored.

Liquid sweeps use total mass flow in kg/s and coolant inlet temperature. Use mass-flow-rate control in the source settings; Top + Bottom Cooling uses total-flow control and also sweeps branch allocation. Side and serpentine cooling each use their single active coolant branch.

Forced-air sweeps use inlet velocity in m/s and air inlet temperature. The selected Uniform AmbH or Progressive Gas model is retained. Air properties and heat-transfer coefficients are refreshed for each case. Ambient temperature follows swept air inlet temperature in forced-air studies; configured ambient temperature stays fixed in liquid studies.

## Design Optimization

1. Set the main cooling architecture and the operating point to hold fixed.
2. Enter ranges for the displayed architecture-specific design variables.
3. Review **DESIGN LIMITS** and **SELECTION CRITERIA**, then click **RUN DESIGN SWEEP**.
4. Inspect the complete results table and Peak Temperature, Cell Uniformity and Design Space plots.
5. Export results and confirm the original design has been restored.

Forced air varies inter-cell and cell-to-duct wall gaps. Top/bottom cooling varies plate thickness and cell-to-plate thermal resistance; top + bottom uses a shared plate design. Side cooling varies contact-height fraction and contact thermal resistance. Serpentine cooling varies contact-height fraction, circumference fraction and contact thermal resistance. Structural cases rebuild the battery as required.

## Sampling and recommendation rules

- Sampling uses `minimum + n × step` up to the maximum. A maximum off the sampling grid is not appended.
- Set minimum equal to maximum to hold a variable fixed. Steps must be positive.
- Liquid and air operating ranges are remembered separately. Review sweep ranges when loading older setup files.
- A case passes when both peak nodal temperature and maximum cell-to-cell difference are at or below their limits. Equality passes.
- Default ranking prefers lower peak nodal temperature, cell-to-cell difference, within-cell difference and then operating/design values, in that order.
- Cooling recommendations are selected separately at each inlet temperature. Every tested top/bottom flow share participates.
- Cooling and design priority orders are independent. Select a criterion, use **MOVE UP** or **MOVE DOWN**, then **APPLY ORDER**. Existing results are reranked without resimulation; **RESET DEFAULT** restores the default order.
- Exact ties are equivalent; case number is not a ranking criterion.
- Incomplete operating groups are marked `Best completed thermal result; ranking incomplete`. A complete group with no passing case is marked `No feasible case`.

Recommendations apply to the sampled range and thermal metrics. Pump/fan power and inlet-conditioning energy are not evaluated.

## Thermal metrics

| Metric | Definition |
| --- | --- |
| Peak nodal temperature | Maximum logged temperature over all nodes, cells and times |
| Cell-to-cell difference | At each time, hottest cell-average temperature minus coldest cell-average temperature; maximum over time |
| Within-cell difference | At each time and cell, hottest node minus coldest node; maximum over all cells and times |

Within-cell difference is reported separately from the cell-to-cell feasibility constraint. Temperature logs must be finite and cover the full requested simulation duration. A stopped simulation cannot pass.

## Stop, restore and export

Inputs are locked during a sweep. **STOP SWEEP** retains completed cases and records unrun cases. Original operating/design settings are restored after completion, stop or error. If restoration cannot rebuild a structural or Progressive Gas case, follow the reported rebuild requirement before another simulation.

**EXPORT RESULTS (.CSV)** saves the headings and rows displayed in the results table. **EXPORT SWEEP** saves all-case CSV, recommended-case CSV and a MAT package containing results and study metadata. Keep failed and unrun rows when reviewing completeness.

## Literature benchmarks

- **Forced-Air Validation — Fan 2019:** aligned/staggered cylindrical cases, 2C, 20 °C inlet and 0.6–4 m/s.
- **Bottom-Cooling Validation — Bahiraei 2017:** retained 1400 s paper-geometry case, 6P × 1S prismatic module and 1 mm plate.

The comparisons include digitized paper data. The Bahiraei workflow includes estimated/surrogate electrical parameters and resistance scaling; it is a case-specific benchmark. These workflows do not validate all supported configurations.

## Verification in MATLAB

The repository update was checked statically and against the supplied archive. MATLAB/Simulink was unavailable, so the following checks remain to be executed in the target installation.

```matlab
report = ThermalPack_v2_App('selftest');
```

The helper self-tests do not open a Simulink model. They cover range endpoints, case counts, invalid ranges, temperature metrics, time coverage, missing logs, inclusive limits, per-inlet ranking, incomplete ranking status and reordered recommendation priorities.

Then run a small two-case liquid sweep and two-case forced-air sweep. Confirm parameter changes, restored settings and CSV/MAT exports. Test stopping a longer sweep and inspect failed/unrun statuses. Repeat with a two-case design sweep and verify that the original design is restored. These checks assess operation; predictive accuracy requires suitable reference data for the specific model.
